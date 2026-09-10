-- Neutral device custody. Only trusted authoritative addon callbacks may attest
-- native consumption/ejection. No player reference survives an authorized start.
require "GS_ItemLease"
require "GS_TransferLock"
require "GS_Index"
local GS = GlobalStorageSiK
local Service = {}
GS.DeviceItemLease = Service
local STORE = "GlobalStorageSiK_DeviceItemLease_v1"

local function text(value, limit)
	return type(value) == "string" and #value > 0 and #value <= limit
end
local function integer(value, low, high)
	return type(value) == "number" and value >= low and value <= high and value == math.floor(value)
end
local function keyFor(addonId, networkId, anchor)
	if not text(addonId, 64) or not text(networkId, 160) or type(anchor) ~= "table"
		or not integer(anchor.x, 0, 1000000) or not integer(anchor.y, 0, 1000000)
		or not integer(anchor.z, -32, 32) then return nil end
	-- Length prefixes avoid collisions when IDs themselves contain colons.
	return #addonId .. ":" .. addonId .. #networkId .. ":" .. networkId .. ":" .. anchor.x .. ":" .. anchor.y .. ":" .. anchor.z
end
local function store() return ModData.getOrCreate(STORE) end
local function copy(record)
	if not record then return nil end
	local result = {}
	for key, value in pairs(record) do
		if key == "anchor" then result.anchor = { x = value.x, y = value.y, z = value.z }
		elseif key ~= "allowedNodeIds" then result[key] = value end
	end
	return result
end
local function recordFor(key)
	if not GS.isAuthoritative() or not text(key, 512) then return nil end
	return store()[key]
end
local function locked(record, fn)
	return GS.TransferLock.withAuthorityLock(record.networkId, record.key, "device_item_lease", fn)
end
local function sourceFor(record, nodeId)
	local live = GS.Network.getLiveContainers(record.networkId)
	for i = 1, #live do
		if live[i].entry and live[i].entry.id == nodeId then return live[i] end
	end
end
local function changed(record, source)
	GS.Index.syncNodeSnapshot(source.entry, source.container)
	GS.Index.bumpInventoryRevision(record.networkId, true)
end

function Service.get(addonId, networkId, anchor)
	if not GS.isAuthoritative() then return false, "authority_required" end
	local key = keyFor(addonId, networkId, anchor)
	if not key then return false, "invalid_request" end
	return true, "OK", copy(store()[key])
end
function Service.open(player, args)
	if not GS.isAuthoritative() then return false, "authority_required" end
	if type(args) ~= "table" or not integer(args.sequence, 1, 2147483600) then return false, "invalid_request" end
	local key = keyFor(args.addonId, args.networkId, args.anchor)
	if not key then return false, "invalid_request" end
	local allowed, reason = GS.ItemLease.checkAccess(player, args.addonId, args.networkId, args.anchor)
	if not allowed then return false, reason end
	local records, previous = store(), store()[key]
	if previous and previous.state ~= "closed" then return false, "device_busy" end
	if args.sequence ~= (previous and previous.sequence + 1 or 1) then return false, "stale_request" end
	local count = 0
	for _, record in pairs(records) do if record.state ~= "closed" then count = count + 1 end end
	if count >= 128 then return false, "device_capacity" end
	local live = GS.Permissions.filterLiveContainers(player, args.networkId, GS.Network.getLiveContainers(args.networkId))
	local nodes = {}
	for i = 1, #live do if live[i].entry then nodes[live[i].entry.id] = true end end
	local record = { key = key, addonId = args.addonId, networkId = args.networkId,
		anchor = { x = args.anchor.x, y = args.anchor.y, z = args.anchor.z },
		sequence = args.sequence, state = "idle", allowedNodeIds = nodes }
	records[key] = record
	return true, "OK", copy(record)
end
function Service.validate(addonId, networkId, anchor)
	if not GS.isAuthoritative() then return false, "authority_required" end
	if not keyFor(addonId, networkId, anchor) then return false, "invalid_request" end
	if not GS.AddonRegistry.isModActive(addonId)
		or not GS.Addons.isInstalled(networkId, anchor, addonId) then return false, "addon_unavailable" end
	local a = anchor
	if not GS.TerminalRegistry.squareHasTerminal(a.x, a.y, a.z) then return false, "no_terminal" end
	if GS.Network.findNetworkIdAtTerminal(a.x, a.y, a.z, { activeOnly = true }) ~= networkId then
		return false, "terminal_mismatch"
	end
	return true, "OK"
end
function Service.check(key)
	local record = recordFor(key)
	if not record or record.state == "closed" then return false, "unknown_loan" end
	return Service.validate(record.addonId, record.networkId, record.anchor)
end
function Service.consume(key, ref, inspect, invoke, verify)
	local record = recordFor(key)
	if not record or record.state ~= "idle" then return false, "invalid_transition" end
	if type(ref) ~= "table" or not integer(ref.itemId, 0, 9007199254740991)
		or not text(ref.fullType, 160) or not text(ref.sourceNodeId, 240)
		or type(inspect) ~= "function" or type(invoke) ~= "function" or type(verify) ~= "function" then
		return false, "invalid_request"
	end
	local allowed, reason = Service.check(key)
	if not allowed then return false, reason end
	if not record.allowedNodeIds[ref.sourceNodeId] then return false, "no_permission" end
	return locked(record, function()
		if record.state ~= "idle" then return false, "invalid_transition" end
		local source = sourceFor(record, ref.sourceNodeId)
		local container = source and source.container
		local item = container and container:getItemById(ref.itemId)
		if not item or item:getFullType() ~= ref.fullType then return false, "source_unavailable" end
		local inspected, fingerprint = pcall(inspect, item)
		if not inspected or not text(fingerprint, 240) then return false, "item_rejected" end
		local weight = item:getActualWeight()
		if type(weight) ~= "number" or weight < 0 or weight ~= weight then return false, "invalid_weight" end
		record.sourceNodeId, record.itemId, record.originalItemId = ref.sourceNodeId, ref.itemId, ref.itemId
		record.fullType, record.fingerprint, record.weight = ref.fullType, fingerprint, weight
		record.returnedItemId, record.state = nil, "consuming"
		local invoked = pcall(invoke, item)
		local checked, accepted = pcall(verify, fingerprint)
		local removed = not container:contains(item)
		if removed then changed(record, source) end
		if not invoked or not checked or accepted ~= true or not removed then
			record.state = "unresolved"; return false, "consumption_unconfirmed", copy(record)
		end
		record.state = "active"
		return true, "OK", copy(record)
	end)
end
function Service.release(key, invoke, verify, matches)
	local record = recordFor(key)
	if not record or record.state ~= "active" then return false, "invalid_transition" end
	if type(invoke) ~= "function" or type(verify) ~= "function" or type(matches) ~= "function" then
		return false, "invalid_request"
	end
	return locked(record, function()
		if record.state ~= "active" then return false, "invalid_transition" end
		local source = sourceFor(record, record.sourceNodeId)
		local container = source and source.container
		if not container then return false, "source_unavailable" end
		if not container.getCapacity or not container.getContentsWeight then return false, "capacity_unavailable" end
		local cap, weight = container:getCapacity(), container:getContentsWeight()
		if type(cap) ~= "number" or type(weight) ~= "number" or cap ~= cap or weight ~= weight then
			return false, "capacity_unavailable"
		end
		if weight + record.weight > cap then return false, "destination_full" end
		local items, before = container:getItems(), {}
		if items:size() >= 8192 then return false, "inventory_limit" end
		for i = 0, items:size() - 1 do before[tostring(items:get(i):getID())] = true end
		record.state = "replacing"
		local invoked = pcall(invoke, container)
		local checked, empty = pcall(verify)
		local successor, count = nil, 0
		items = container:getItems()
		if items:size() <= 8192 then
			for i = 0, items:size() - 1 do
				local item = items:get(i)
				if not before[tostring(item:getID())] and item:getFullType() == record.fullType then
					local matched, accepted = pcall(matches, item, record.fingerprint)
					if matched and accepted == true then successor = item; count = count + 1 end
				end
			end
		end
		changed(record, source)
		if not invoked or not checked or empty ~= true or count ~= 1 then
			record.state = "unresolved"; return false, "replacement_unconfirmed", copy(record)
		end
		record.returnedItemId, record.state = tonumber(tostring(successor:getID())), "idle"
		return true, "OK", copy(record)
	end)
end
function Service.close(key)
	local record = recordFor(key)
	if not record or (record.state ~= "idle" and record.state ~= "closed") then return false, "loan_pending" end
	record.state, record.allowedNodeIds = "closed", nil
	return true, "OK", copy(record)
end
return Service
