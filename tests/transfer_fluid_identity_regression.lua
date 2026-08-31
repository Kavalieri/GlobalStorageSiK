-- Author regression for authoritative withdrawal by canonical fluid identity.
-- Pure Lua 5.1: no Project Zomboid runtime is opened.

local shared = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/"
local sourceItems = {}
local destinationItems = {}

local function javaList(items)
	return {
		size = function() return #items end,
		get = function(_, index) return items[index + 1] end,
	}
end

local function container(kind, capacity, items)
	local value = { kind = kind, capacity = capacity, items = items }
	function value:getItems() return javaList(self.items) end
	function value:contains(item)
		for i = 1, #self.items do
			if self.items[i] == item then return true end
		end
		return false
	end
	function value:getContentsWeight() return #self.items end
	function value:getCapacity() return self.capacity end
	function value:getType() return self.kind end
	return value
end

local source = container("network-crate", 100, sourceItems)
local destination = container("player-inventory", 100, destinationItems)

local function fluidItem(id, containerName, amount, capacity)
	local fluid = {
		isEmpty = function() return amount <= 0 end,
		isMixture = function() return false end,
		isTainted = function() return false end,
		isPoisonous = function() return false end,
		getAmount = function() return amount end,
		getCapacity = function() return capacity end,
		getContainerName = function() return containerName end,
		getPrimaryFluidAmount = function() return amount end,
		getPrimaryFluid = function()
			return { getFluidTypeString = function() return "Base:Water" end }
		end,
	}
	local value = { id = id, owner = source }
	function value:getID() return self.id end
	function value:getFullType() return "Base.FluidContainer" end
	function value:getContainer() return self.owner end
	function value:getFluidContainer() return fluid end
	return value
end

-- Deliberately put the wrong form first. All three units share fullType and
-- content; only the canonical shape+content identity may choose the row.
local hydration = fluidItem(401, "HydrationPack", 0.75, 1)
local bottle25 = fluidItem(402, "BottlePlastic", 0.25, 1)
local bottle75 = fluidItem(403, "BottlePlastic", 0.75, 1)
sourceItems[1], sourceItems[2], sourceItems[3] = hydration, bottle25, bottle75

for _, name in ipairs({ "GS_Router", "GS_I18n", "GS_NativeProduct", "GS_CategoryResolution",
	"GS_Network", "GS_Power", "GS_Sandbox", "GS_BulkFilters", "GS_InventorySync",
	"GS_Index", "GS_ItemSnapshot", "GS_TransferLock", "GS_Permissions" }) do
	package.loaded[name] = true
end
package.loaded["GS_FluidTaxonomy"] = nil

FluidCategory = { Fuel = "fuel", Beverage = "beverage", Water = "water" }
GlobalStorageSiK = {
	Router = {
		containerHasSpace = function() return true end,
	},
	I18n = {},
	NativeProduct = {},
}
dofile(shared .. "GS_FluidTaxonomy.lua")
package.loaded["GS_FluidTaxonomy"] = true

local hydrationInfo = assert(GlobalStorageSiK.FluidTaxonomy.inspect(hydration))
local bottle25Info = assert(GlobalStorageSiK.FluidTaxonomy.inspect(bottle25))
local bottle75Info = assert(GlobalStorageSiK.FluidTaxonomy.inspect(bottle75))

assert(bottle25Info.identityKey == bottle75Info.identityKey,
	"litres/percentage leaked into authoritative fluid identity")
assert(bottle25Info.stateKey == bottle25Info.identityKey,
	"stateKey is not aligned with canonical shape+content identity")
assert(bottle25Info.contentStateKey == bottle25Info.contentSignature,
	"contentStateKey does not expose content-only state")
assert(hydrationInfo.contentStateKey == bottle25Info.contentStateKey,
	"equal contents must expose equal content-only state")
assert(hydrationInfo.identityKey ~= bottle25Info.identityKey,
	"different fluid container forms collapsed")
assert(bottle25Info.fillPercent == 25 and bottle75Info.fillPercent == 75,
	"exact percentages must remain presentation detail")

GlobalStorageSiK.Network = {
	getLiveContainers = function()
		return { { container = source, entry = { id = "node-fluid" } } }
	end,
}
GlobalStorageSiK.Permissions = {
	filterLiveContainers = function(_, _, live) return live end,
}
GlobalStorageSiK.Power = { networkPowered = function() return true end }
GlobalStorageSiK.Sandbox = {
	remoteTransferEnabled = function() return true end,
	getMaxItemsPerBulkTick = function() return 10 end,
}
GlobalStorageSiK.InventorySync = {
	moveBetween = function(from, to, item)
		for i = 1, #from.items do
			if from.items[i] == item then
				table.remove(from.items, i)
				break
			end
		end
		to.items[#to.items + 1] = item
		item.owner = to
		return true
	end,
}
GlobalStorageSiK.Index = { syncNodeSnapshot = function() end }
GlobalStorageSiK.ItemSnapshot = {
	recordedMediaTitleFromItem = function() return nil end,
	recordedMediaIndexFromItem = function() return nil end,
}
GlobalStorageSiK.Log = { info = function() end }

dofile(shared .. "GS_Transfer.lua")
local player = { getInventory = function() return destination end }
local ok, reason, moved, movedIds = GlobalStorageSiK.Transfer.withdrawType(
	player, "Base.FluidContainer", "network-fluid", 2, destination, nil,
	bottle25Info.identityKey)

assert(ok == true and reason == nil and moved == 2, "canonical bottle row was not withdrawn")
assert(movedIds[1] == 402 and movedIds[2] == 403,
	"authoritative withdrawal selected the wrong fluid units")
assert(#destinationItems == 2 and destinationItems[1] == bottle25 and destinationItems[2] == bottle75,
	"destination did not receive both bottle fill levels")
assert(#sourceItems == 1 and sourceItems[1] == hydration,
	"same-content hydration container was incorrectly withdrawn")

local hydrationOk, hydrationReason, hydrationMoved, hydrationIds =
	GlobalStorageSiK.Transfer.withdrawType(player, "Base.FluidContainer", "network-fluid", 1,
		destination, nil, hydrationInfo.identityKey)
assert(hydrationOk == true and hydrationReason == nil and hydrationMoved == 1
	and hydrationIds[1] == 401, "hydration row could not withdraw its own exact form")

print("transfer_fluid_identity_regression: OK")
