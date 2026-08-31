-- Core 1.4.3-dev32.4.2: compact parents + paged detail identities.
package.loaded["GS_Router"] = true
package.loaded["GS_I18n"] = true
package.loaded["GS_Network"] = true
package.loaded["GS_Zones"] = true
package.loaded["GS_ZoneRefresh"] = true
package.loaded["GS_NativeProduct"] = true
package.loaded["GS_CategoryResolution"] = true
package.loaded["GS_Permissions"] = true
package.loaded["GS_ItemSnapshot"] = nil

FluidCategory = { Fuel = "fuel", Beverage = "beverage", Water = "water" }
GlobalStorageSiK = {
	Router = { getItemCategory = function() return "Misc" end, getItemSubCategory = function() return nil end },
	I18n = {
		nameFromItemInstance = function(item) return item:getDisplayName() end,
		isLowQualityDisplayName = function() return false end,
		typeDisplayName = function(fullType) return fullType end,
		getScriptItem = function(fullType)
			return fullType == "Base.Crisps" and {} or nil
		end,
	},
	NativeProduct = { tracePathSample = function() end },
	CategoryResolution = {
		resolve = function(fullType, row, item)
			local path = row and row.nativePath or nil
			if item and GlobalStorageSiK.FluidTaxonomy then
				local dynamic = GlobalStorageSiK.FluidTaxonomy.resolve(item)
				if dynamic then path = "native:" .. dynamic.l1 .. "/" .. dynamic.l2 .. "/" .. dynamic.l3 end
			end
			return { nativePath = path or "native:food_drink/non_perishable/other_food",
				nativeStatus = "classified", vanillaKey = "Food", effective = "native",
				routingIdentity = path or "native:food_drink/non_perishable/other_food",
				categorySource = "VANILLA" }
		end,
	},
	isAuthoritative = function() return true end,
}

dofile("GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/GS_FluidTaxonomy.lua")
package.loaded["GS_FluidTaxonomy"] = true
dofile("GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/GS_ItemSnapshot.lua")
package.loaded["GS_ItemSnapshot"] = true

local function item(fullType, id, name, opts)
	opts = opts or {}
	local out = {
		getFullType = function() return fullType end,
		getID = function() return id end,
		getDisplayName = function() return name end,
		getName = function() return name end,
		getWorldSprite = function() return nil end,
		getRecordedMediaIndex = function() return opts.mediaIndex == nil and -1 or opts.mediaIndex end,
	}
	if opts.fluid then
		out.getFluidContainer = function()
			local f = opts.fluid
			return {
				isEmpty = function() return f.empty end,
				isMixture = function() return f.mixture == true end,
				isCategory = function(_, key) return key == f.category end,
				getAmount = function() return f.amount or 0 end,
				getCapacity = function() return f.capacity or 1 end,
				getPrimaryFluid = function()
					if f.empty then return nil end
					return { getFluidTypeString = function() return f.fluidType end }
				end,
			}
		end
	end
	return out
end

local snapshot = {}
for _, value in ipairs({
	item("Base.Crisps", 1, "Chips - Plain"),
	item("Base.Crisps2", 2, "Chips - Barbecue"),
	item("Base.Crisps3", 3, "Chips - Salt and Vinegar"),
	item("Base.VHSTape", 10, "Woodcraft Ep. 3", { mediaIndex = 214 }),
	item("Base.VHSTape", 11, "Woodcraft Ep. 3", { mediaIndex = 214 }),
	item("Base.VHSTape", 12, "Exposure Survival Ep. 5", { mediaIndex = 315 }),
	item("Base.VHSTape", 13, "VHS Tape", { mediaIndex = -1 }),
	item("Base.PetrolCan", 20, "Gas Can", { fluid = { empty = false, category = nil, fluidType = "Petrol", amount = 0.8, capacity = 10 } }),
	item("Base.PetrolCan", 21, "Empty Gas Can", { fluid = { empty = true } }),
}) do
	assert(GlobalStorageSiK.ItemSnapshot.addItem(snapshot, value), value:getFullType())
end
for id = 100, 115 do
	assert(GlobalStorageSiK.ItemSnapshot.addItem(snapshot, item("Base.Nails", id, "Nails")))
end

local registry = {
	networks = { net = { id = "net" } },
	zones = { zone = { id = "zone", networkId = "net" } },
	nodes = { node = { id = "node", zoneId = "zone", itemSnapshot = snapshot } },
}
GlobalStorageSiK.Network = {
	getDefaultNetworkId = function() return "net" end,
	getDisplayName = function() return "Test Network" end,
	getLiveContainers = function() return {} end,
	getRegistry = function() return registry end,
	ensureRegistry = function() end,
}
GlobalStorageSiK.Zones = { getRegistry = function() return registry end }
GlobalStorageSiK.Permissions = {
	filterLiveContainers = function() return {} end,
	canAccessZone = function() return true end,
	canAccess = function() return true end,
}
GlobalStorageSiK.ZoneRefresh = {}

dofile("GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/GS_Index.lua")
local rows = GlobalStorageSiK.Index.buildRows("net", {})
local byType = {}
local vhsParents = {}
for _, row in ipairs(rows) do
        byType[row.fullType] = row
        if row.fullType == "Base.VHSTape" then vhsParents[#vhsParents + 1] = row end
end

local chips = byType["Base.Crisps"] or byType["Base.Crisps2"] or byType["Base.Crisps3"]
assert(chips and chips.count == 3 and chips.expandable and chips.aggregateAllowed, "chips family")
assert(#chips.fullTypes == 3 and chips.itemIds == nil, "chips compact payload")
local chipDetails = GlobalStorageSiK.Index.buildDetailPage("net", {}, chips.rowKey, 1, 20)
assert(chipDetails.total == 3 and #chipDetails.items == 3, "three cosmetic variants")
assert(chipDetails.items[1].aggregateAllowed == true, "expanded cosmetic rows transfer normally")

assert(#vhsParents == 3, "VHS titles were collapsed into one generic physical-type parent")
local woodcraft = nil
for _, row in ipairs(vhsParents) do if row.mediaIndex == 214 then woodcraft = row end end
assert(woodcraft and woodcraft.count == 2 and woodcraft.expandable
        and woodcraft.aggregateAllowed and woodcraft.displayName == "Woodcraft Ep. 3",
        "same-title VHS copies were not exposed as one exact transferable parent")
local vhsDetails = GlobalStorageSiK.Index.buildDetailPage("net", {}, woodcraft.rowKey, 1, 20)
assert(vhsDetails.total == 1 and #vhsDetails.items == 1
        and vhsDetails.items[1].count == 2 and #vhsDetails.items[1].itemIds == 2,
        "exact VHS parent did not retain both physical copies in its detail")

local petrol = byType["Base.PetrolCan"]
assert(petrol and petrol.count == 2 and petrol.expandable and not petrol.aggregateAllowed, "fluid parent")
assert(petrol.mixedVariants and petrol.nativePath == nil,
	"mixed fluid parent must report multiple categories, never invent a representative path")
local petrolDetails = GlobalStorageSiK.Index.buildDetailPage("net", {}, petrol.rowKey, 1, 20)
assert(petrolDetails.total == 2 and #petrolDetails.items == 2, "fluid physical instances")
local fluidPaths = {}
local filledFluidStateKey = nil
for _, detail in ipairs(petrolDetails.items) do
	fluidPaths[detail.nativePath] = true
	if detail.nativePath == "native:vehicles/consumable/fuel" then
		filledFluidStateKey = detail.dynamicStateKey
	end
end
assert(fluidPaths["native:vehicles/consumable/fuel"] and fluidPaths["native:containers/liquid/empty"],
	"each fluid child keeps its exact category")
assert(petrol.itemIds == nil, "ordinary snapshot must not expose all itemIds")

local nails = byType["Base.Nails"]
assert(nails and nails.count == 16 and nails.expandable and nails.aggregateAllowed, "all multi-unit rows expand")
local nailDetails = GlobalStorageSiK.Index.buildDetailPage("net", {}, nails.rowKey, 1, nil)
assert(nailDetails.pageSize == 15 and #nailDetails.items == 15 and nailDetails.hasNext, "default page size 15")

local counts = GlobalStorageSiK.Index.getNetworkCountsForItem({}, "Base.Crisps2")
assert(#counts == 1 and counts[1].count == 3, "tooltip sums cosmetic family")
counts = GlobalStorageSiK.Index.getNetworkCountsForItem({}, "Base.VHSTape", nil, 214, nil)
assert(#counts == 1 and counts[1].count == 2, "tooltip counts the same VHS edition")
counts = GlobalStorageSiK.Index.getNetworkCountsForItem({}, "Base.PetrolCan", nil, nil, "empty")
assert(#counts == 1 and counts[1].count == 1, "tooltip separates empty fluid containers")
counts = GlobalStorageSiK.Index.getNetworkCountsForItem({}, "Base.PetrolCan", nil, nil, filledFluidStateKey)
assert(#counts == 1 and counts[1].count == 1, "tooltip counts matching fluid content")

print("item_grouping_detail_regression: OK")
