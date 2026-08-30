-- Core 1.4.3-dev32.4.3: runtime structure outranks weak names/types.
package.loaded["GS_NativeClassifierApi"] = true
package.loaded["GS_NativeClassifierUtils"] = true

local classifiers = {}
GlobalStorageSiK = {
	NativeClassifier = {
		registerBlock = function(fn, name) classifiers[name] = fn end,
	},
}
ResourceLocation = { of = function(key) return key end }
ItemTag = { get = function(key) return key end }

local ROOT = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/"
dofile(ROOT .. "GS_NativeClassifierUtils.lua")
dofile(ROOT .. "GS_NativeClassifierContainers.lua")
dofile(ROOT .. "GS_NativeClassifierSurvival.lua")

local containers = assert(classifiers.containers, "containers classifier must register")
local survival = assert(classifiers.electronics_vehicles_survival,
	"survival classifier must register")

local function scriptItem(fullType, itemType, displayCategory)
	return {
		getFullName = function() return fullType end,
		getItemType = function() return itemType end,
		getDisplayCategory = function() return displayCategory end,
		getTags = function()
			return { contains = function() return false end }
		end,
	}
end

local coolerPath, coolerFacets, _, coolerEvidence = containers(
	"Base.Cooler_Beer", scriptItem("Base.Cooler_Beer", "base:container", "Container"))
assert(coolerPath and coolerPath.l1 == "containers" and coolerPath.l2 == "portable",
	"Cooler_Beer must be a portable container by ScriptItem structure")
assert(coolerFacets and coolerFacets.containerForm,
	"Cooler_Beer must expose a concrete portable-container form")
assert(coolerEvidence and coolerEvidence.primary
	and coolerEvidence.primary.source == "script_container_structure"
	and coolerEvidence.primary.confidence == 100,
	"Cooler_Beer must carry strong structural evidence")

for _, case in ipairs({
	{ "Base.WheatBagSeed", "Gardening", nil },
	{ "Base.LemonGrassBagSeed", "Gardening", "Literature" },
	{ "Base.WheatBagSeed_Empty", "RecipeResource", "BASE:LITERATURE" },
}) do
	local path, _, _, evidence = survival(case[1], scriptItem(case[1], case[3], case[2]))
	assert(path and path.l1 == "survival_outdoors" and path.l2 == "farming",
		case[1] .. " must classify as farming")
	assert(evidence and evidence.primary
		and evidence.primary.source == "script_gardening_seed_packet"
		and evidence.primary.confidence == 100,
		case[1] .. " must not depend on canonical getItemType")
end

print("dev32_4_3_classifier_contract: OK")
