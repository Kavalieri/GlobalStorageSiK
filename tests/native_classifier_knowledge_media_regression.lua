-- Regression test for Core 1.4.3-dev32.4 GS recipe-magazine structure.
-- Run from GlobalStorageSiK-Repo: lua51.exe tests/native_classifier_knowledge_media_regression.lua

package.loaded["GS_NativeClassifierApi"] = true
package.loaded["GS_NativeClassifierUtils"] = true

local classifier = nil
GlobalStorageSiK = { NativeClassifier = { registerBlock = function(fn) classifier = fn end } }
ResourceLocation = { of = function(key) return key end }
ItemTag = { get = function(key) return key end }

dofile("GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/GS_NativeClassifierUtils.lua")
dofile("GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/GS_NativeClassifierKnowledgeMedia.lua")
assert(classifier, "knowledge classifier must register its block")

local function scriptItem(fullType, displayCategory, magazine, skill, recipes)
	return {
		getFullName = function() return fullType end,
		getDisplayCategory = function() return displayCategory end,
		getItemType = function() return "base:literature" end,
		getSkillTrained = function() return skill end,
		getLearnedRecipes = function() return recipes end,
		getTags = function()
			return { contains = function(_, tag) return magazine and tag == "base:magazine" or false end }
		end,
	}
end

local path, _, _, evidence = classifier("GlobalStorageSiK.GS_Manual_TerminalUnit",
	scriptItem("GlobalStorageSiK.GS_Manual_TerminalUnit", "RecipeResource", true))
assert(path and path.l1 == "knowledge_media" and path.l2 == "recipe_magazine",
	"own manual with recipe display and magazine tag must be a recipe magazine")
assert(evidence.primary.source == "gs_recipe_manual_structural", "structural evidence")

local missingTag = classifier("GlobalStorageSiK.GS_Manual_TerminalUnit",
	scriptItem("GlobalStorageSiK.GS_Manual_TerminalUnit", "RecipeResource", false))
assert(missingTag and missingTag.l2 == "recipe_magazine",
	"the stable own marker plus recipe metadata must not depend on the runtime magazine tag")

local skillBook, _, _, skillEvidence = classifier("Base.BookElectrician1",
	scriptItem("Base.BookElectrician1", "SkillBook", false, "Electricity", nil))
assert(skillBook and skillBook.l2 == "skill_book", "skill training metadata wins over electrician name")
assert(skillEvidence.primary.source == "script_skill_trained", "skill book structural evidence")

local vanillaRecipe, _, _, recipeEvidence = classifier("Base.MagazineCooking1",
	scriptItem("Base.MagazineCooking1", "RecipeResource", false, nil, { "Make Soup" }))
assert(vanillaRecipe and vanillaRecipe.l2 == "recipe_magazine", "recipe data identifies vanilla recipe magazines")
assert(recipeEvidence.primary.source == "script_recipe_resource", "recipe structural evidence")

print("native_classifier_knowledge_media_regression: OK")
