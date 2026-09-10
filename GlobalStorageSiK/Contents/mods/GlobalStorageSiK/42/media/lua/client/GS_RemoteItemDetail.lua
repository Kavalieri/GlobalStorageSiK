-- Cache cliente para detalle exacto de una fila hija remota.
-- Sin OnTick: la solicitud nace del hover, se deduplica en vuelo y una
-- respuesta tardía se descarta si el cursor ya abandonó ese contexto.

require "GS_NetClient"

GlobalStorageSiK.RemoteItemDetail = GlobalStorageSiK.RemoteItemDetail or {}
local RemoteDetail = GlobalStorageSiK.RemoteItemDetail

local cache = {}
local cacheOrderByNetwork = {}
local networkOrder = {}
local inFlightByKey = {}
local inFlightOrder = {}
local keyByRequestId = {}
local retryAfterByKey = {}
local retryOrder = {}
local activeByOwner = setmetatable({}, { __mode = "k" })
local revisionByNetwork = {}
local sequence = 0
local MAX_CACHE_PER_NETWORK = 128
local MAX_CACHE_NETWORKS = 16
local MAX_IN_FLIGHT = 128
local MAX_RETRY_KEYS = 256
local FAILURE_BACKOFF_MS = 1500
local REQUEST_TIMEOUT_MS = 5000

local function validItemId(value)
	return type(value) == "number" and value == value and value >= 0
		and value <= 2147483647 and value == math.floor(value)
end

local function nowMs()
	if getTimestampMs then return getTimestampMs() end
	if getTimestamp then return (getTimestamp() or 0) * 1000 end
	return 0
end
-- Las sondas de ISToolTipInv son efimeras. Una tabla debil permite que la
-- extension SiK consulte el contexto remoto sin escribir modData ni retener
-- InventoryItems artificiales cuando una fila virtual se recicla.
local probeContexts = setmetatable({}, { __mode = "k" })

local function removeOrdered(order, key)
	for i = #order, 1, -1 do
		if order[i] == key then table.remove(order, i) end
	end
end

local function contextKey(row, terminal)
	local state = terminal and terminal.terminalState or {}
	if not row or not row.itemId or not row.nodeId or not state.networkId then return nil end
	local revision = tonumber(state.inventoryRevision) or 0
	return tostring(state.networkId) .. "\31" .. tostring(revision) .. "\31"
		.. tostring(row.nodeId) .. "\31" .. tostring(row.itemId) .. "\31"
		.. tostring(terminal.playerNum or 0), revision, state.networkId
end

function RemoteDetail.invalidateAll()
	cache = {}
	cacheOrderByNetwork = {}
	networkOrder = {}
	inFlightByKey = {}
	inFlightOrder = {}
	keyByRequestId = {}
	retryAfterByKey = {}
	retryOrder = {}
	activeByOwner = setmetatable({}, { __mode = "k" })
	revisionByNetwork = {}
	probeContexts = setmetatable({}, { __mode = "k" })
end

---@param networkId string|nil
function RemoteDetail.invalidateNetwork(networkId)
	if not networkId then return end
	local prefix = tostring(networkId) .. "\31"
	local removeCache, removeFlight, removeRetry = {}, {}, {}
	for key in pairs(cache) do if key:sub(1, #prefix) == prefix then removeCache[#removeCache + 1] = key end end
	for key in pairs(inFlightByKey) do if key:sub(1, #prefix) == prefix then removeFlight[#removeFlight + 1] = key end end
	for key in pairs(retryAfterByKey) do if key:sub(1, #prefix) == prefix then removeRetry[#removeRetry + 1] = key end end
	for i = 1, #removeCache do cache[removeCache[i]] = nil end
	for i = 1, #removeFlight do
		local flight = inFlightByKey[removeFlight[i]]
		if flight then keyByRequestId[flight.requestId] = nil end
		inFlightByKey[removeFlight[i]] = nil
		removeOrdered(inFlightOrder, removeFlight[i])
	end
	for i = 1, #removeRetry do
		retryAfterByKey[removeRetry[i]] = nil
		removeOrdered(retryOrder, removeRetry[i])
	end
	cacheOrderByNetwork[networkId] = nil
	removeOrdered(networkOrder, networkId)
	local removeOwners = {}
	for owner, state in pairs(activeByOwner) do
		if state.networkId == networkId then removeOwners[#removeOwners + 1] = owner end
	end
	for i = 1, #removeOwners do activeByOwner[removeOwners[i]] = nil end
	revisionByNetwork[networkId] = nil
end

local function touchNetwork(networkId)
	for i = 1, #networkOrder do
		if networkOrder[i] == networkId then return end
	end
	networkOrder[#networkOrder + 1] = networkId
	if #networkOrder > MAX_CACHE_NETWORKS then
		local oldest = networkOrder[1]
		if oldest then RemoteDetail.invalidateNetwork(oldest) end
	end
end

local function capInFlight()
	while #inFlightOrder > MAX_IN_FLIGHT do
		local oldest = table.remove(inFlightOrder, 1)
		local flight = oldest and inFlightByKey[oldest] or nil
		if flight then keyByRequestId[flight.requestId] = nil end
		if oldest then inFlightByKey[oldest] = nil end
	end
end

local function setRetry(key, untilMs)
	if retryAfterByKey[key] == nil then retryOrder[#retryOrder + 1] = key end
	retryAfterByKey[key] = untilMs
	while #retryOrder > MAX_RETRY_KEYS do
		local oldest = table.remove(retryOrder, 1)
		if oldest then retryAfterByKey[oldest] = nil end
	end
end

---@param probe InventoryItem|nil
---@param row table|nil
---@param detail table|nil
---@param loading boolean|nil
function RemoteDetail.bindProbe(probe, row, detail, loading)
	if not probe then return end
	probeContexts[probe] = {
		row = row,
		detail = detail,
		loading = loading == true,
	}
end

---@param probe InventoryItem|nil
---@return table|nil
function RemoteDetail.contextForProbe(probe)
	return probe and probeContexts[probe] or nil
end

local function physicalRow(row)
	if not row then return nil end
	if validItemId(row.itemId) and type(row.nodeId) == "string"
		and type(row.fullType) == "string" and type(row.selectionRevision) == "number" then
		return row
	end
	if validItemId(row.representativeItemId) and type(row.representativeNodeId) == "string"
		and type(row.representativeFullType) == "string"
		and type(row.representativeRevision) == "number" then
		return {
			itemId = row.representativeItemId,
			nodeId = row.representativeNodeId,
			fullType = row.representativeFullType,
			selectionRevision = row.representativeRevision,
		}
	end
	return nil
end

function RemoteDetail.unbindProbe(probe)
	if probe then probeContexts[probe] = nil end
end

---@return table|nil detail
---@return boolean loading
function RemoteDetail.activate(owner, row, terminal)
	local exactRow = physicalRow(row)
	local state = terminal and terminal.terminalState or nil
	if not exactRow or not state
		or exactRow.selectionRevision ~= state.inventoryRevision then return nil, false end
	local key, revision, networkId = contextKey(exactRow, terminal)
	if not key then return nil, false end
	if revisionByNetwork[networkId] ~= nil and revisionByNetwork[networkId] ~= revision then
		RemoteDetail.invalidateNetwork(networkId)
	end
	revisionByNetwork[networkId] = revision
	touchNetwork(networkId)
	local cached = cache[key]
	if cached then
		activeByOwner[owner] = { key = key, requestId = nil, networkId = networkId }
		return cached, false
	end
	local now = nowMs()
	if now > 0 and (retryAfterByKey[key] or 0) > now then
		activeByOwner[owner] = { key = key, requestId = nil, networkId = networkId }
		return nil, false
	end
	local flight = inFlightByKey[key]
	if flight and now > 0 and flight.sentAt > 0 and now - flight.sentAt >= REQUEST_TIMEOUT_MS then
		keyByRequestId[flight.requestId] = nil
		inFlightByKey[key] = nil
		removeOrdered(inFlightOrder, key)
		flight = nil
	end
	local requestId = flight and flight.requestId or nil
	if not requestId then
		sequence = sequence + 1
		requestId = "tooltip:" .. tostring(sequence) .. ":" .. tostring(exactRow.itemId)
		inFlightByKey[key] = { requestId = requestId, sentAt = now,
			networkId = networkId, revision = revision, nodeId = exactRow.nodeId, itemId = exactRow.itemId }
		inFlightOrder[#inFlightOrder + 1] = key
		capInFlight()
		keyByRequestId[requestId] = key
		-- SP can respond synchronously inside sendCommand. Register the owner
		-- first, otherwise the valid response is discarded as an abandoned hover.
		activeByOwner[owner] = { key = key, requestId = requestId, networkId = networkId }
		local sent = GlobalStorageSiK.NetClient.sendCommand("getItemTooltipDetail", {
			requestId = requestId,
			networkId = networkId,
			inventoryRevision = revision,
			nodeId = exactRow.nodeId,
			itemId = exactRow.itemId,
		}, getSpecificPlayer and getSpecificPlayer(terminal.playerNum or 0) or nil)
		if not sent then
			keyByRequestId[requestId] = nil
			inFlightByKey[key] = nil
			removeOrdered(inFlightOrder, key)
			requestId = nil
		end
		if cache[key] then return cache[key], false end
		if not inFlightByKey[key] then requestId = nil end
	end
	activeByOwner[owner] = { key = key, requestId = requestId, networkId = networkId }
	return nil, requestId ~= nil
end

function RemoteDetail.deactivate(owner)
	if owner then activeByOwner[owner] = nil end
end

function RemoteDetail.onReceived(args)
	if not args or not args.requestId then return false end
	local key = keyByRequestId[args.requestId]
	if not key then return false end
	local flight = inFlightByKey[key]
	if not flight or args.networkId ~= flight.networkId or args.nodeId ~= flight.nodeId
		or tonumber(args.itemId) ~= tonumber(flight.itemId)
		or (args.ok == true and tonumber(args.inventoryRevision) ~= flight.revision) then return false end
	keyByRequestId[args.requestId] = nil
	inFlightByKey[key] = nil
	removeOrdered(inFlightOrder, key)
	-- Resolver por propietario permite split-screen y más de una superficie sin
	-- que el último hover global robe la respuesta al anterior.
	local owners = {}
	for owner, state in pairs(activeByOwner) do
		if state.key == key and state.requestId == args.requestId then owners[#owners + 1] = owner end
	end
	-- El hover se canceló o cambió: no conservar una respuesta que nadie espera.
	if #owners == 0 then return false end
	if args.ok == true then
		retryAfterByKey[key] = nil
		removeOrdered(retryOrder, key)
		if cache[key] == nil then
			local order = cacheOrderByNetwork[args.networkId] or {}
			cacheOrderByNetwork[args.networkId] = order
			order[#order + 1] = key
			if #order > MAX_CACHE_PER_NETWORK then
				local oldest = table.remove(order, 1)
				if oldest then cache[oldest] = nil end
			end
		end
		cache[key] = args
	else
		local failedAt = nowMs()
		setRetry(key, failedAt > 0 and (failedAt + FAILURE_BACKOFF_MS) or 0)
	end
	for i = 1, #owners do
		local owner = owners[i]
		if owner and owner.onRemoteItemDetail then owner:onRemoteItemDetail(args) end
	end
	return true
end
