-- Detalle exacto y acotado para tooltips de filas remotas del Almacén.
-- Nunca barre la red: resuelve el nodeId ya conocido, inspecciona únicamente
-- su contenedor y cachea por inventoryRevision + itemId.

require "GS_Index"
require "GS_ItemSnapshot"
require "GS_Network"
require "GS_Permissions"
require "GS_Utils"
require "GS_Zones"
require "GS_Log"

GlobalStorageSiK.ItemTooltipDetailServer = GlobalStorageSiK.ItemTooltipDetailServer or {}
local DetailServer = GlobalStorageSiK.ItemTooltipDetailServer

local cacheByNetwork = {}
local networkOrder = {}
local rateByPlayer = setmetatable({}, { __mode = "k" })
local RATE_WINDOW_MS = 1000
local RATE_LIMIT = 12
local MAX_CACHE_NETWORKS = 64
local MAX_CACHE_PER_NETWORK = 256

local function removeOrdered(order, key)
	for i = #order, 1, -1 do
		if order[i] == key then table.remove(order, i) end
	end
end

function DetailServer.invalidateNetwork(networkId)
	if not networkId then return end
	cacheByNetwork[networkId] = nil
	removeOrdered(networkOrder, networkId)
end

function DetailServer.invalidateAll()
	cacheByNetwork = {}
	networkOrder = {}
	rateByPlayer = setmetatable({}, { __mode = "k" })
end

local function ensureBucket(networkId, revision)
	local bucket = cacheByNetwork[networkId]
	if bucket and bucket.revision == revision then return bucket end
	if bucket then
		DetailServer.invalidateNetwork(networkId)
	end
	bucket = { revision = revision, values = {}, order = {} }
	cacheByNetwork[networkId] = bucket
	networkOrder[#networkOrder + 1] = networkId
	if #networkOrder > MAX_CACHE_NETWORKS then
		local oldest = networkOrder[1]
		if oldest then DetailServer.invalidateNetwork(oldest) end
	end
	return bucket
end

local function nowMs()
	return getTimestampMs and getTimestampMs() or 0
end

local function copyTable(source)
	local out = {}
	for key, value in pairs(source or {}) do out[key] = value end
	return out
end

local function allowRequest(player, now)
	local state = rateByPlayer[player]
	if not state or now - state.startedAt >= RATE_WINDOW_MS then
		state = { startedAt = now, count = 0 }
		rateByPlayer[player] = state
	end
	if state.count >= RATE_LIMIT then return false end
	state.count = state.count + 1
	return true
end

local function validateKnownNode(networkId, nodeId, player)
	local registry = GlobalStorageSiK.Zones.getRegistry()
	local node = registry.nodes and registry.nodes[nodeId] or nil
	local zone = node and registry.zones and registry.zones[node.zoneId] or nil
	if not node or not zone or zone.networkId ~= networkId then return nil, "invalid_node" end
	if node.membership == "excluded" or node.enabled == false then return nil, "inactive_node" end
	if node.offline == true then return nil, "offline_node" end
	if player and not GlobalStorageSiK.Permissions.canAccessZone(player, networkId, node.zoneId) then
		return nil, "forbidden_node"
	end
	return node, nil
end

local function resolveNodeContainer(node)
	local obj = GlobalStorageSiK.Network.findWorldObject(node)
	local container = obj and GlobalStorageSiK.Utils.getObjectContainer(obj, node.containerIndex) or nil
	if not container then return nil, "offline_node" end
	return container, nil
end

local function findItem(container, itemId)
	if not container or not itemId then return nil, 0 end
	if container.getItemWithID then
		local ok, item = pcall(function() return container:getItemWithID(itemId) end)
		if ok and item then return item, 1 end
	end
	if container.getItemById then
		local ok, item = pcall(function() return container:getItemById(itemId) end)
		if ok and item then return item, 1 end
	end
	local items = container.getItems and container:getItems() or nil
	if not items then return nil, 0 end
	local inspected = 0
	for i = 0, items:size() - 1 do
		local item = items:get(i)
		inspected = inspected + 1
		if item and item.getID and item:getID() == itemId then return item, inspected end
	end
	return nil, inspected
end

local function logMetrics(result, cacheState, elapsed, inspected)
	GlobalStorageSiK.Log.debug("ItemNetworkTooltipDetail", "request",
		"result=" .. tostring(result) .. " cache=" .. tostring(cacheState)
		.. " elapsedMs=" .. tostring(elapsed) .. " nodesInspected=1 itemsInspected=" .. tostring(inspected or 0))
end

---@param player IsoPlayer
---@param args table
---@param networkId string
---@param requireAccess function
---@param send function
function DetailServer.handle(player, args, networkId, requireAccess, send)
	args = args or {}
	local requestId = type(args.requestId) == "string" and string.sub(args.requestId, 1, 96) or nil
	local nodeId = type(args.nodeId) == "string" and string.sub(args.nodeId, 1, 160) or nil
	local itemId = tonumber(args.itemId)
	local requestedRevision = tonumber(args.inventoryRevision)
	local revision = GlobalStorageSiK.Index.getInventoryRevision(networkId)
	if not requireAccess(player, networkId) then
		-- Completar siempre el canal que originó la petición; de lo contrario el
		-- cliente conserva el request en vuelo para siempre.
		send(player, "itemTooltipDetail", {
			requestId = requestId, networkId = networkId, nodeId = nodeId,
			itemId = itemId, inventoryRevision = revision,
			ok = false, reason = "forbidden_network",
		})
		return
	end
	local startedAt = nowMs()
	local function respond(payload)
		payload = payload or {}
		payload.requestId = requestId
		payload.networkId = networkId
		payload.nodeId = nodeId
		payload.itemId = itemId
		payload.inventoryRevision = revision
		send(player, "itemTooltipDetail", payload)
	end
	if not requestId or not nodeId or not itemId or itemId < 0 or itemId ~= math.floor(itemId) then
		respond({ ok = false, reason = "invalid_request" })
		return
	end
	if not allowRequest(player, startedAt) then
		respond({ ok = false, reason = "rate_limited" })
		logMetrics("rate_limited", "miss", nowMs() - startedAt, 0)
		return
	end
	if requestedRevision ~= revision then
		respond({ ok = false, reason = "stale_revision" })
		return
	end
	-- La autorización del nodo precede SIEMPRE al cache compartido por red.
	-- Un hit creado por otro miembro no puede saltarse el alcance de zona.
	local node, nodeReason = validateKnownNode(networkId, nodeId, player)
	if not node then
		respond({ ok = false, reason = nodeReason })
		logMetrics(nodeReason, "miss", nowMs() - startedAt, 0)
		return
	end
	local bucket = ensureBucket(networkId, revision)
	local cacheKey = tostring(nodeId) .. "\31" .. tostring(itemId)
	local cached = bucket.values[cacheKey]
	if cached then
		local payload = copyTable(cached)
		payload.ok = true
		payload.cache = "hit"
		respond(payload)
		logMetrics("ok", "hit", nowMs() - startedAt, 0)
		return
	end
	local container, reason = resolveNodeContainer(node)
	if not container then
		respond({ ok = false, reason = reason })
		logMetrics(reason, "miss", nowMs() - startedAt, 0)
		return
	end
	local item, inspected = findItem(container, itemId)
	if not item then
		respond({ ok = false, reason = "item_missing" })
		logMetrics("item_missing", "miss", nowMs() - startedAt, inspected)
		return
	end
	local detail = GlobalStorageSiK.ItemSnapshot.tooltipDetailFromItem(item)
	detail.ok = true
	detail.cache = "miss"
	bucket.order[#bucket.order + 1] = cacheKey
	if #bucket.order > MAX_CACHE_PER_NETWORK then
		local oldest = table.remove(bucket.order, 1)
		if oldest then bucket.values[oldest] = nil end
	end
	bucket.values[cacheKey] = copyTable(detail)
	respond(detail)
	logMetrics("ok", "miss", nowMs() - startedAt, inspected)
end
