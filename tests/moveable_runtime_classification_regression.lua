-- Author regression for Moveable world-sprite classification and identity.
-- Pure Lua 5.1: sprite/property and inventory classes are deterministic mocks.

for _, name in ipairs({ "GS_NativeProduct", "GS_I18n", "GS_FluidTaxonomy", "GS_Router" }) do
	package.loaded[name] = true
end
package.loaded["GS_CategoryResolution"] = nil
package.loaded["GS_ItemSnapshot"] = nil

local function encode(path)
	if not path or not path.l1 then return nil end
	local out = "native:" .. path.l1
	if path.l2 then out = out .. "/" .. path.l2 end
	if path.l3 then out = out .. "/" .. path.l3 end
	return out
end

GlobalStorageSiK = {
	NativeClassifier = {
		classify = function()
			return { primaryPath = { l1 = "other", l2 = "unclassified", l3 = "other" } }
		end,
	},
	NativeProduct = {
		normalizePath = function(path) return path end,
		encodePath = encode,
		decodePath = function(value) return value end,
		tracePathSample = function() end,
	},
	I18n = {
		getScriptItem = function() return nil end,
		nameFromItemInstance = function(item) return item:getDisplayName() end,
		moveableDisplayNameFromSprite = function(sprite) return sprite end,
		isLowQualityDisplayName = function() return false end,
		humanizeFallbackName = function(value) return value end,
		typeDisplayName = function(value) return value end,
	},
	FluidTaxonomy = {
		resolve = function() return nil, nil end,
		stateKey = function() return nil end,
		fillPercent = function() return nil end,
		amountAndCapacity = function() return nil, nil end,
	},
	Router = {
		getItemCategory = function() return "Furniture" end,
		getItemSubCategory = function() return nil end,
	},
	CatalogManager = { onEpochChanged = function() end },
	isAuthoritative = function() return true end,
}

local spriteProperties = {
	["fixtures_locker_01"] = { container = "locker" },
	["fixtures_crate_01"] = { container = "crate" },
	["appliances_fridge_01"] = { container = "fridge", IsFridge = true },
	["appliances_freezer_01"] = { container = "freezer", Freezer = true },
	["decor_painting_01"] = {},
}

getSprite = function(spriteName)
	local source = spriteProperties[spriteName]
	if not source then return nil end
	local props = {
		has = function(_, key) return source[key] ~= nil end,
		get = function(_, key) return source[key] end,
	}
	return { getProperties = function() return props end }
end

instanceof = function(value, className)
	return value and value.__class == className
end

local shared = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/"
dofile(shared .. "GS_CategoryResolution.lua")
package.loaded["GS_CategoryResolution"] = true

local nextId = 0
local function inventoryItem(className, spriteName, fullType)
	nextId = nextId + 1
	local value = { __class = className, id = nextId }
	function value:getFullType() return fullType or "Base.Moveable" end
	function value:getID() return self.id end
	function value:getDisplayName() return spriteName or "Inventory item" end
	function value:getName() return self:getDisplayName() end
	function value:getWorldSprite() return spriteName end
	function value:getRecordedMediaIndex() return -1 end
	function value:getDisplayCategory() return className == "InventoryContainer" and "Bag" or "Furniture" end
	function value:getActualWeight() return 1 end
	return value
end

local function assertPath(item, l2, l3, note)
	local path = GlobalStorageSiK.CategoryResolution.moveablePathFromItem(item)
	assert(path and path.l1 == "home_leisure_collection" and path.l2 == l2 and path.l3 == l3,
		(note or item:getWorldSprite()) .. " path")
end

assertPath(inventoryItem("Moveable", "fixtures_locker_01"), "furnishing", "storage", "locker")
assertPath(inventoryItem("Moveable", "fixtures_crate_01"), "furnishing", "storage", "crate")
assertPath(inventoryItem("Moveable", "appliances_fridge_01"), "kitchen", "appliance", "fridge")
assertPath(inventoryItem("Moveable", "appliances_freezer_01"), "kitchen", "appliance", "freezer")
assert(GlobalStorageSiK.CategoryResolution.moveablePathFromItem(
	inventoryItem("Moveable", "decor_painting_01")) == nil,
	"painting without structural sprite properties was forced into furnishing")

local backpack = inventoryItem("InventoryContainer", "fixtures_locker_01", "Base.Bag_BigHikingBag")
assert(GlobalStorageSiK.CategoryResolution.moveablePathFromItem(backpack) == nil,
	"equippable InventoryContainer was classified as Moveable")
local backpackResolution = GlobalStorageSiK.CategoryResolution.resolve(backpack:getFullType(), nil, backpack)
assert(backpackResolution.nativePath ~= "native:home_leisure_collection/furnishing/storage",
	"equippable InventoryContainer inherited world-sprite furniture taxonomy")

dofile(shared .. "GS_ItemSnapshot.lua")
local snapshot = {}
local locker = inventoryItem("Moveable", "fixtures_locker_01")
local crate = inventoryItem("Moveable", "fixtures_crate_01")
assert(GlobalStorageSiK.ItemSnapshot.addItem(snapshot, locker))
assert(GlobalStorageSiK.ItemSnapshot.addItem(snapshot, crate))
local count = 0
for _, row in pairs(snapshot) do
	count = count + 1
	assert(row.detailKind == "moveable", "Moveable sprite row lost detail kind")
end
assert(count == 2, "different world sprites with the same fullType collapsed")

local bagSnapshot = {}
assert(GlobalStorageSiK.ItemSnapshot.addItem(bagSnapshot, backpack))
local bagRow = nil
for _, row in pairs(bagSnapshot) do bagRow = row end
assert(bagRow and bagRow.detailKind ~= "moveable",
	"InventoryContainer snapshot was exposed as Moveable detail")

print("moveable_runtime_classification_regression: OK")
