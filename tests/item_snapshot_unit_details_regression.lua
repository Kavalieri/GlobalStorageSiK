-- Author regression for sparse per-unit details in authoritative snapshots.
-- Run from GlobalStorageSiK-Repo with Lua 5.1.

for _, name in ipairs({ "GS_Router", "GS_I18n", "GS_FluidTaxonomy", "GS_NativeProduct" }) do
	package.loaded[name] = true
end

GlobalStorageSiK = {
	Router = { getItemCategory = function() return "Misc" end,
		getItemSubCategory = function() return nil end },
	I18n = {
		nameFromItemInstance = function(item) return item:getDisplayName() end,
		isLowQualityDisplayName = function() return false end,
		typeDisplayName = function(fullType) return fullType end,
	},
	FluidTaxonomy = {
		inspect = function(item)
			if item.kind ~= "fluid" then return nil end
			return {
				path = { l1 = "vehicles", l2 = "consumable", l3 = "fuel" },
				signature = "fluid:petrol",
				stateKey = "fluid:petrol",
				fillPercent = 50,
				amount = 5,
				capacity = 10,
				canonicalType = "petrol",
				detail = { canonicalType = "petrol", compositionExact = true },
			}
		end,
		resolve = function(item)
			if item.kind == "fluid" then
				return { l1 = "vehicles", l2 = "consumable", l3 = "fuel" }, "fluid:petrol"
			end
			return nil, nil
		end,
		stateKey = function(item) return item.kind == "fluid" and "fluid:petrol" or nil end,
		fillPercent = function(item) return item.kind == "fluid" and 50 or nil end,
		amountAndCapacity = function(item)
			if item.kind == "fluid" then return 5, 10 end
			return nil, nil
		end,
		canonicalType = function(item) return item.kind == "fluid" and "petrol" or nil end,
	},
	NativeProduct = { encodePath = function() return "native:vehicles/consumable/fuel" end },
	CategoryResolution = {
		resolve = function()
			return { nativePath = "native:vehicles/consumable/fuel", nativeStatus = "classified",
				effective = "native", routingIdentity = "native:vehicles/consumable/fuel" }
		end,
	},
}

dofile("GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/GS_RecordedMedia.lua")
package.loaded["GS_RecordedMedia"] = true
dofile("GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/GS_ItemSnapshot.lua")

local function item(fullType, id, kind)
	local value = {
		kind = kind,
		getFullType = function() return fullType end,
		getID = function() return id end,
		getDisplayName = function() return fullType end,
		getName = function() return fullType end,
		getWorldSprite = function() return nil end,
	}
	if kind == "media" then
		value.getRecordedMediaIndex = function() return 42 end
	elseif kind == "condition" then
		value.getCondition = function() return 7 end
		value.getConditionMax = function() return 10 end
	else
		value.getRecordedMediaIndex = function() return -1 end
	end
	return value
end

local function onlyRow(map)
	local found, count = nil, 0
	for _, row in pairs(map) do found, count = row, count + 1 end
	assert(count == 1, "expected one snapshot row")
	return found
end

local fungibleMap = {}
assert(GlobalStorageSiK.ItemSnapshot.addItem(fungibleMap, item("Base.Nails", 1, "fungible")))
local fungible = onlyRow(fungibleMap)
assert(fungible.unitDetails == nil,
	"fungible snapshots must omit unitDetails instead of serializing an empty table")

local merged = {}
GlobalStorageSiK.ItemSnapshot.mergeMaps(merged, fungibleMap)
assert(onlyRow(merged).unitDetails == nil,
	"mergeMaps recreated empty unitDetails for a fungible row")

for _, fixture in ipairs({
	{ fullType = "Base.VHS_Retail", id = 2, kind = "media", field = "mediaIndex", expected = 42 },
	{ fullType = "Base.PetrolCan", id = 3, kind = "fluid", field = "dynamicPercent", expected = 50 },
	{ fullType = "Base.Hammer", id = 4, kind = "condition", field = "condition", expected = 7 },
}) do
	local map = {}
	assert(GlobalStorageSiK.ItemSnapshot.addItem(map,
		item(fixture.fullType, fixture.id, fixture.kind)))
	local row = onlyRow(map)
	assert(type(row.unitDetails) == "table" and type(row.unitDetails[fixture.id]) == "table",
		fixture.kind .. " snapshot lost exact unitDetails")
	assert(row.unitDetails[fixture.id][fixture.field] == fixture.expected,
		fixture.kind .. " snapshot lost its exact state")
end

print("item_snapshot_unit_details_regression: OK")
