-- Author regression for per-instance food identity.
-- Pure Lua 5.1: no Project Zomboid runtime is opened.

for _, name in ipairs({ "GS_Router", "GS_I18n", "GS_NativeProduct", "GS_CategoryResolution" }) do
	package.loaded[name] = true
end
package.loaded["GS_FluidTaxonomy"] = nil
package.loaded["GS_ItemSnapshot"] = nil

GlobalStorageSiK = {
	Router = {
		getItemCategory = function() return "Food" end,
		getItemSubCategory = function() return nil end,
	},
	I18n = {
		nameFromItemInstance = function(item) return item:getDisplayName() end,
		isLowQualityDisplayName = function() return false end,
		typeDisplayName = function(fullType) return fullType end,
	},
	NativeProduct = { tracePathSample = function() end },
	isAuthoritative = function() return true end,
}

instanceof = function(value, className)
	return value and value.__class == className
end

local shared = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/"
dofile(shared .. "GS_FluidTaxonomy.lua")
package.loaded["GS_FluidTaxonomy"] = true
dofile(shared .. "GS_RecordedMedia.lua")
package.loaded["GS_RecordedMedia"] = true
dofile(shared .. "GS_ItemSnapshot.lua")

local function javaList(values)
	return {
		size = function() return #values end,
		get = function(_, index) return values[index + 1] end,
	}
end

local nextId = 0
local function food(opts)
	opts = opts or {}
	nextId = nextId + 1
	local value = { __class = "Food", id = nextId }
	function value:getFullType() return opts.fullType or "Base.Soup" end
	function value:getID() return self.id end
	function value:getDisplayName() return opts.name or "Soup" end
	function value:getName() return opts.name or "Soup" end
	function value:getWorldSprite() return nil end
	function value:getRecordedMediaIndex() return -1 end
	function value:isFood() return true end
	function value:isCooked() return opts.cooked == true end
	function value:isBurnt() return opts.burnt == true end
	function value:isFrozen() return opts.frozen == true end
	function value:isRotten() return opts.rotten == true end
	function value:getExtraItems() return javaList(opts.extraItems or {}) end
	function value:getSpices() return javaList(opts.spices or {}) end
	function value:getCurrentUsesFloat() return opts.uses == nil and 1 or opts.uses end
	function value:isCustomName() return opts.customName == true end
	function value:getActualWeight() return 1 end
	return value
end

local function rowsFor(items)
	local snapshot = {}
	for i = 1, #items do
		assert(GlobalStorageSiK.ItemSnapshot.addItem(snapshot, items[i]), "food add " .. tostring(i))
	end
	return snapshot
end

local function countRows(snapshot)
	local count = 0
	for _ in pairs(snapshot) do count = count + 1 end
	return count
end

local states = rowsFor({
	food(),
	food({ cooked = true }),
	food({ burnt = true }),
	food({ frozen = true }),
	food({ rotten = true }),
})
assert(countRows(states) == 5, "raw/cooked/burnt/frozen/rotten food states collapsed")

local ordered = rowsFor({
	food({ extraItems = { "Base.Ham", "Base.Cheese" }, spices = { "Base.Salt", "Base.Pepper" } }),
	food({ extraItems = { "Base.Cheese", "Base.Ham" }, spices = { "Base.Pepper", "Base.Salt" } }),
})
assert(countRows(ordered) == 1, "equivalent extraItems/spices differ only by iteration order")
local orderedRow = nil
for _, row in pairs(ordered) do orderedRow = row end
assert(orderedRow and orderedRow.count == 2, "equivalent food compositions did not aggregate")

local compositions = rowsFor({
	food({ extraItems = { "Base.Ham", "Base.Cheese" }, spices = { "Base.Salt" } }),
	food({ extraItems = { "Base.Ham", "Base.Tomato" }, spices = { "Base.Salt" } }),
	food({ extraItems = { "Base.Ham", "Base.Cheese" }, spices = { "Base.Pepper" } }),
})
assert(countRows(compositions) == 3, "different food composition or spices collapsed")

local partialAndNamed = rowsFor({
	food({ uses = 1 }),
	food({ uses = 0.5 }),
	food({ uses = 1, customName = true, name = "Emergency soup" }),
	food({ uses = 1, customName = true, name = "Celebration soup" }),
})
assert(countRows(partialAndNamed) == 4, "partial uses or custom names collapsed")

for _, row in pairs(partialAndNamed) do
	assert(row.detailKind == "food" and row.dynamicStateKey == row.variantKey,
		"food row did not publish its exact dynamic identity")
	assert(row.unitDetails and row.unitDetails[row.itemIds[1]],
		"food row lost per-unit details")
end

print("dynamic_food_identity_regression: OK")
