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
dofile("GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/GS_RecordedMedia.lua")
package.loaded["GS_RecordedMedia"] = true
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
	item("Base.VHS_Retail", 10, "Woodcraft Ep. 3", { mediaIndex = 214 }),
	item("Base.VHS_Retail", 11, "Woodcraft Ep. 3", { mediaIndex = 214 }),
	item("Base.VHS_Retail", 12, "Exposure Survival Ep. 5", { mediaIndex = 315 }),
	item("Base.VHS_Home", 13, "VHS Tape", { mediaIndex = -1 }),
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
local petrolParents = {}
for _, row in ipairs(rows) do
        byType[row.fullType] = row
        if row.fullType == "Base.VHS_Retail" or row.fullType == "Base.VHS_Home" then
                vhsParents[#vhsParents + 1] = row
        end
        if row.fullType == "Base.PetrolCan" then petrolParents[#petrolParents + 1] = row end
end

local chips = byType["Base.Crisps"] or byType["Base.Crisps2"] or byType["Base.Crisps3"]
assert(chips and chips.count == 3 and chips.expandable and chips.aggregateAllowed, "chips family")
assert(#chips.fullTypes == 3 and chips.itemIds == nil, "chips compact payload")
local chipDetails = GlobalStorageSiK.Index.buildDetailPage("net", {}, chips.rowKey, 1, 20)
assert(chipDetails.total == 3 and #chipDetails.items == 3, "three cosmetic variants")
assert(chipDetails.items[1].aggregateAllowed == true, "expanded cosmetic rows transfer normally")
local chipVariants = {}
for _, detail in ipairs(chipDetails.items) do
	chipVariants[detail.fullType] = detail
end
assert(chipVariants["Base.Crisps"] and chipVariants["Base.Crisps"].count == 1
	and chipVariants["Base.Crisps"].displayName == "Chips - Plain",
	"plain crisps variant was lost inside the shared family")
assert(chipVariants["Base.Crisps2"] and chipVariants["Base.Crisps2"].count == 1
	and chipVariants["Base.Crisps2"].displayName == "Chips - Barbecue",
	"barbecue crisps variant was lost inside the shared family")
assert(chipVariants["Base.Crisps3"] and chipVariants["Base.Crisps3"].count == 1
	and chipVariants["Base.Crisps3"].displayName == "Chips - Salt and Vinegar",
	"salt and vinegar crisps variant was lost inside the shared family")

assert(#vhsParents == 3, "VHS titles were collapsed into one generic physical-type parent")
local woodcraft, exposure, unknown = nil, nil, nil
for _, row in ipairs(vhsParents) do
	if row.mediaIndex == 214 then woodcraft = row end
	if row.mediaIndex == 315 then exposure = row end
	if row.mediaIndex == nil then unknown = row end
end
assert(woodcraft and woodcraft.count == 2 and woodcraft.expandable
        and woodcraft.aggregateAllowed and woodcraft.displayName == "Woodcraft Ep. 3",
        "same-title VHS copies were not exposed as one exact transferable parent")
assert(exposure and exposure.count == 1 and exposure.displayName == "Exposure Survival Ep. 5"
	and exposure.rowKey ~= woodcraft.rowKey,
	"different VHS mediaIndex/title did not produce a distinct exact parent")
assert(unknown and unknown.count == 1 and unknown.rowKey ~= woodcraft.rowKey,
	"unknown VHS identity collapsed with a known edition")
local vhsDetails = GlobalStorageSiK.Index.buildDetailPage("net", {}, woodcraft.rowKey, 1, 20)
assert(vhsDetails.total == 1 and #vhsDetails.items == 1
        and vhsDetails.items[1].count == 2 and #vhsDetails.items[1].itemIds == 2,
        "exact VHS parent did not retain both physical copies in its detail")
assert(vhsDetails.items[1].mediaIndex == woodcraft.mediaIndex
	and vhsDetails.items[1].displayName == woodcraft.displayName,
	"VHS parent and child did not preserve the same vanilla title/identity")

assert(#petrolParents == 2, "different fluid identities were compacted into one parent")
local filledPetrol = nil
local emptyPetrol = nil
for _, parent in ipairs(petrolParents) do
	if parent.nativePath == "native:vehicles/consumable/fuel" then filledPetrol = parent end
	if parent.nativePath == "native:containers/liquid/empty" then emptyPetrol = parent end
end
assert(filledPetrol and emptyPetrol and filledPetrol.rowKey ~= emptyPetrol.rowKey,
	"filled and empty containers must expose distinct exact-group identities")
assert(filledPetrol.count == 1 and emptyPetrol.count == 1
	and not filledPetrol.mixedVariants and not emptyPetrol.mixedVariants,
	"each fluid parent must retain only its canonical identity")
assert(filledPetrol.selectionMode == "exact_group" and emptyPetrol.selectionMode == "exact_group",
	"fluid parents must use the same authoritative exact-group selection contract")
local filledFluidStateKey = nil
local emptyFluidStateKey = nil
local filledDetails = GlobalStorageSiK.Index.buildDetailPage("net", {}, filledPetrol.rowKey, 1, 20)
local emptyDetails = GlobalStorageSiK.Index.buildDetailPage("net", {}, emptyPetrol.rowKey, 1, 20)
assert(filledDetails.total == 1 and #filledDetails.items == 1
	and filledDetails.items[1].nativePath == filledPetrol.nativePath,
	"filled fluid detail lost its exact category")
assert(emptyDetails.total == 1 and #emptyDetails.items == 1
	and emptyDetails.items[1].nativePath == emptyPetrol.nativePath,
	"empty fluid detail lost its exact category")
filledFluidStateKey = filledDetails.items[1].dynamicStateKey
emptyFluidStateKey = emptyDetails.items[1].dynamicStateKey
assert(filledPetrol.itemIds == nil and emptyPetrol.itemIds == nil,
	"ordinary snapshots must not expose all fluid itemIds")

local nails = byType["Base.Nails"]
assert(nails and nails.count == 16 and nails.expandable and nails.aggregateAllowed, "all multi-unit rows expand")
local nailDetails = GlobalStorageSiK.Index.buildDetailPage("net", {}, nails.rowKey, 1, nil)
assert(nailDetails.pageSize == 15 and #nailDetails.items == 15 and nailDetails.hasNext, "default page size 15")

local counts = GlobalStorageSiK.Index.getNetworkCountsForItem({}, "Base.Crisps2")
assert(#counts == 1 and counts[1].count == 3, "tooltip sums cosmetic family")
counts = GlobalStorageSiK.Index.getNetworkCountsForItem({}, "Base.VHS_Retail", nil, 214, nil)
assert(#counts == 1 and counts[1].count == 2, "tooltip counts the same VHS edition")
counts = GlobalStorageSiK.Index.getNetworkCountsForItem({}, "Base.PetrolCan", nil, nil, emptyFluidStateKey)
assert(#counts == 1 and counts[1].count == 1, "tooltip separates empty fluid containers")
counts = GlobalStorageSiK.Index.getNetworkCountsForItem({}, "Base.PetrolCan", nil, nil, filledFluidStateKey)
assert(#counts == 1 and counts[1].count == 1, "tooltip counts matching fluid content")

print("item_grouping_detail_regression: OK")
