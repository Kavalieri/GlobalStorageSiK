-- Exact detail rows must match InventoryItem:getID() even when Kahlua exposes
-- the live ID as a Java numeric value and the command payload contains a Lua
-- number.  Table keys compare by type, so the transfer boundary canonicalizes.
local sourceItems, destinationItems = {}, {}
local function list(items)
	return { size = function() return #items end, get = function(_, i) return items[i + 1] end }
end
local function container(items)
	local value = { items = items }
	function value:getItems() return list(self.items) end
	function value:contains(candidate)
		for i = 1, #self.items do if self.items[i] == candidate then return true end end
		return false
	end
	function value:getContentsWeight() return #self.items end
	function value:getCapacity() return 100 end
	function value:getType() return "inventory" end
	return value
end

local source, destination = container(sourceItems), container(destinationItems)
local javaLikeId = setmetatable({ value = 810162816 }, {
	__tostring = function(self) return tostring(self.value) end,
})
local selected = { owner = source }
function selected:getID() return javaLikeId end
function selected:getFullType() return "Base.Pear" end
function selected:getContainer() return self.owner end
sourceItems[1] = selected

for _, module in ipairs({ "GS_Network", "GS_Router", "GS_Power", "GS_Sandbox", "GS_BulkFilters",
	"GS_InventorySync", "GS_Index", "GS_ItemSnapshot", "GS_TransferLock", "GS_Permissions" }) do
	package.loaded[module] = true
end
GlobalStorageSiK = {
	Network = { getLiveContainers = function()
		return { { container = source, entry = { id = "node" } } }
	end },
	Permissions = { filterLiveContainers = function(_, _, live) return live end },
	Power = { networkPowered = function() return true end },
	Sandbox = { remoteTransferEnabled = function() return true end,
		getMaxItemsPerBulkTick = function() return 20 end },
	Router = { containerHasSpace = function() return true end },
	InventorySync = { moveBetween = function(from, to, value)
		table.remove(from.items, 1)
		to.items[#to.items + 1] = value
		value.owner = to
		return true
	end },
	Index = { syncNodeSnapshot = function() end },
	ItemSnapshot = { recordedMediaTitleFromItem = function() return nil end,
		recordedMediaIndexFromItem = function() return nil end },
	FluidTaxonomy = { resolve = function() return nil, nil end },
	Log = { info = function() end },
}

dofile("GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/GS_Transfer.lua")
local player = { getInventory = function() return destination end }
local ok, reason, moved = GlobalStorageSiK.Transfer.withdrawType(
	player, "Base.Pear", "network", 1, destination, nil, nil, { 810162816 })
assert(ok and reason == nil and moved == 1, "wire ID must match the live Java numeric ID")
assert(#sourceItems == 0 and destinationItems[1] == selected, "the exact selected unit must move")

print("transfer_exact_java_id_regression: OK")
