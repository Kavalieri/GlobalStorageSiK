-- Core 1.4.3-dev32.4.2: a cosmetic parent can transfer across its fullTypes.
local sourceItems, destinationItems = {}, {}
local function list(items)
	return { size = function() return #items end, get = function(_, i) return items[i + 1] end }
end
local function container(items)
	local value = { items = items }
	function value:getItems() return list(self.items) end
	function value:contains(item)
		for i = 1, #self.items do if self.items[i] == item then return true end end
		return false
	end
	function value:getContentsWeight() return #self.items end
	function value:getCapacity() return 100 end
	function value:getType() return "inventory" end
	return value
end
local source, destination = container(sourceItems), container(destinationItems)
local function item(id, fullType)
	local value = { id = id, fullType = fullType, owner = source }
	function value:getID() return self.id end
	function value:getFullType() return self.fullType end
	function value:getContainer() return self.owner end
	return value
end
sourceItems[1] = item(1, "Base.Crisps")
sourceItems[2] = item(2, "Base.Crisps2")
sourceItems[3] = item(3, "Base.Crisps3")

for _, module in ipairs({ "GS_Network", "GS_Router", "GS_Power", "GS_Sandbox", "GS_BulkFilters",
	"GS_InventorySync", "GS_Index", "GS_ItemSnapshot", "GS_TransferLock", "GS_Permissions" }) do
	package.loaded[module] = true
end
GlobalStorageSiK = {
	Network = { getLiveContainers = function() return { { container = source, entry = { id = "node" } } } end },
	Permissions = { filterLiveContainers = function(_, _, live) return live end },
	Power = { networkPowered = function() return true end },
	Sandbox = { remoteTransferEnabled = function() return true end, getMaxItemsPerBulkTick = function() return 20 end },
	Router = { containerHasSpace = function() return true end },
	InventorySync = { moveBetween = function(from, to, value)
		for i = 1, #from.items do if from.items[i] == value then table.remove(from.items, i) break end end
		to.items[#to.items + 1] = value
		value.owner = to
		return true
	end },
	Index = { syncNodeSnapshot = function() end },
	ItemSnapshot = {
		recordedMediaTitleFromItem = function() return nil end,
		recordedMediaIndexFromItem = function() return nil end,
	},
	FluidTaxonomy = { resolve = function() return nil, nil end },
	Log = { info = function() end },
}

dofile("GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/GS_Transfer.lua")
local player = { getInventory = function() return destination end }
local ok, reason, moved = GlobalStorageSiK.Transfer.withdrawType(
	player, "Base.Crisps", "network", 3, destination, nil, nil, nil, nil,
	{ "Base.Crisps", "Base.Crisps2", "Base.Crisps3" })
assert(ok and reason == nil and moved == 3, "cosmetic family withdraw")
assert(#sourceItems == 0 and #destinationItems == 3, "all cosmetic variants move")

print("transfer_fungible_family_regression: OK")
