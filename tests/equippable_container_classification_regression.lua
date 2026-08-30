-- Equipable InventoryContainer items are clothing/equipment, not world storage
-- or generic portable containers. Pure Lua 5.1 author regression.
package.loaded["GS_NativeClassifierApi"] = true
package.loaded["GS_NativeClassifierUtils"] = true

local classifier = nil
GlobalStorageSiK = { NativeClassifier = { registerBlock = function(fn) classifier = fn end } }
local ROOT = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/"
dofile(ROOT .. "GS_NativeClassifierUtils.lua")
dofile(ROOT .. "GS_NativeClassifierClothing.lua")
assert(classifier, "clothing classifier did not register")

local function scriptItem(fullType, equipped, category)
	return {
		getFullName = function() return fullType end,
		getItemType = function() return "base:container" end,
		getDisplayCategory = function() return category or "Bag" end,
		getCanBeEquipped = function() return equipped or "" end,
		getBodyLocation = function() return "" end,
	}
end

for _, fullType in ipairs({
	"Base.Bag_Schoolbag", "Base.Bag_BigHikingBag", "Base.Bag_ALICEpack_Army",
	"Base.Bag_HydrationBackpack", "Base.Bag_HydrationBackpack_Camo",
}) do
	local path, facets, _, evidence = classifier(fullType, scriptItem(fullType, "base:back"))
	assert(path and path.l1 == "clothing_protection" and path.l2 == "equipment"
		and path.l3 == "backpack", fullType .. " was not classified as equipable container")
	assert(facets and facets.containerCapacity == true, fullType .. " lost container facet")
	assert(evidence and evidence.primary and evidence.primary.confidence >= 30,
		fullType .. " missing evidence")
end

local plasticBag = classifier("Base.Plasticbag", scriptItem("Base.Plasticbag", "", "Container"))
assert(plasticBag == nil, "non-equipable plastic bag was captured as clothing")

print("equippable_container_classification_regression: OK")
