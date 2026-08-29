-- Core 1.4.3-dev32.4.2: seed packets are farming, not recipe magazines.
package.loaded["GS_NativeClassifierApi"] = true
package.loaded["GS_NativeClassifierUtils"] = true

local classifier = nil
GlobalStorageSiK = { NativeClassifier = { registerBlock = function(fn) classifier = fn end } }
ResourceLocation = { of = function(key) return key end }
ItemTag = { get = function(key) return key end }

dofile("GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/GS_NativeClassifierUtils.lua")
dofile("GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/GS_NativeClassifierSurvival.lua")
assert(classifier, "survival classifier must register")

local function seedPacket(fullType, displayCategory)
	return {
		getFullName = function() return fullType end,
		getItemType = function() return "base:literature" end,
		getDisplayCategory = function() return displayCategory end,
		getTags = function() return { contains = function() return false end } end,
	}
end

for _, case in ipairs({
	{ "Base.WheatBagSeed", "Gardening" },
	{ "Base.LemonGrassBagSeed", "Gardening" },
	{ "Base.WheatBagSeed_Empty", "RecipeResource" },
}) do
	local path, _, _, evidence = classifier(case[1], seedPacket(case[1], case[2]))
	assert(path and path.l1 == "survival_outdoors" and path.l2 == "farming", case[1])
	assert(evidence.primary.source == "script_gardening_seed_packet", case[1] .. " source")
end

print("native_classifier_survival_seed_regression: OK")
