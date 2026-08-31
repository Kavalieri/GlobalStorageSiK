-- Core 1.4.3-dev32.4.1: exact dynamic row + second jerrycan no_room.
-- Static harness only; it does not certify Project Zomboid runtime.

local logs = {}
local sourceItems = {}
local destinationItems = {}

local function list(items)
	return {
		size = function() return #items end,
		get = function(_, index) return items[index + 1] end,
	}
end

local function container(kind, capacity, items)
	local self = { kind = kind, capacity = capacity, items = items }
	function self:getItems() return list(self.items) end
	function self:contains(item)
		for i = 1, #self.items do if self.items[i] == item then return true end end
		return false
	end
	function self:getContentsWeight()
		local total = 0
		for i = 1, #self.items do total = total + self.items[i].weight end
		return total
	end
	function self:getCapacity() return self.capacity end
	function self:getType() return self.kind end
	return self
end

local source = container("network-crate", 100, sourceItems)
local destination = container("TruckBed", 10, destinationItems)
local function item(id, signature, weight)
	local value = { id = id, signature = signature, weight = weight, owner = source }
	function value:getID() return self.id end
	function value:getFullType() return "Base.PetrolCan" end
	function value:getContainer() return self.owner end
	return value
end

sourceItems[1] = item(201, "empty:0", 1)
sourceItems[2] = item(202, "fluid:fuel:8", 6)
sourceItems[3] = item(203, "fluid:water:8", 6)
sourceItems[4] = item(204, "fluid:fuel:8", 6)
sourceItems[5] = item(205, "fluid:mixed:8", 6)

local modules = { "GS_Network", "GS_Router", "GS_Power", "GS_Sandbox", "GS_BulkFilters",
	"GS_InventorySync", "GS_Index", "GS_ItemSnapshot", "GS_TransferLock", "GS_Permissions" }
for i = 1, #modules do package.loaded[modules[i]] = true end

GlobalStorageSiK = {
	Network = { getLiveContainers = function() return { { container = source, entry = { id = "node-A" } } } end },
	Permissions = { filterLiveContainers = function(_, _, live) return live end },
	Power = { networkPowered = function() return true end },
	Sandbox = { remoteTransferEnabled = function() return true end,
		getMaxItemsPerBulkTick = function() return 20 end },
	Router = { containerHasSpace = function(dest, value)
		return dest:getContentsWeight() + value.weight <= dest:getCapacity()
	end },
	InventorySync = { moveBetween = function(from, to, value)
		for i = 1, #from.items do
			if from.items[i] == value then table.remove(from.items, i) break end
		end
		to.items[#to.items + 1] = value
		value.owner = to
		return true
	end },
	Index = { syncNodeSnapshot = function() end },
	ItemSnapshot = { recordedMediaTitleFromItem = function() return nil end },
	FluidTaxonomy = { inspect = function(value) return { identityKey = value.signature } end },
	Log = { info = function(category, event, message)
		logs[#logs + 1] = category .. " " .. event .. " " .. message
	end },
}

local function assertEqual(actual, expected, note)
	if actual ~= expected then error((note or "mismatch") .. ": expected=" .. tostring(expected)
		.. " actual=" .. tostring(actual), 2) end
end
local function containsLog(fragment)
	for i = 1, #logs do if logs[i]:find(fragment, 1, true) then return true end end
	return false
end

dofile("GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/GS_Transfer.lua")
local player = { getInventory = function() return destination end }
local ok, reason, moved, ids = GlobalStorageSiK.Transfer.withdrawType(
	player, "Base.PetrolCan", "network-A", 2, destination, nil, "fluid:fuel:8", { 202, 204 })

assertEqual(ok, true, "first exact jerrycan moves")
assertEqual(reason, "partial:no_room", "second exact jerrycan reports capacity failure")
assertEqual(moved, 1, "only one jerrycan fits")
assertEqual(ids[1], 202, "the exact requested dynamic item is transferred")
assertEqual(destinationItems[1].id, 202, "destination receives no other fluid variant")
assertEqual(#sourceItems, 4, "rejected second jerrycan remains at source")
if not containsLog("itemId=202") or not containsLog("result=moved")
	or not containsLog("itemId=204") or not containsLog("reason=no_room")
	or not containsLog("sourceNodeId=node-A") or not containsLog("destination=TruckBed") then
	error("operation-level capacity evidence is incomplete")
end

print("transfer_dynamic_capacity_regression: OK")
