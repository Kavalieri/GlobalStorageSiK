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

local function scriptItem(fullType, displayCategory, magazine)
	return {
		getFullName = function() return fullType end,
		getDisplayCategory = function() return displayCategory end,
		getItemType = function() return "base:literature" end,
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
assert(missingTag == nil, "the own marker alone cannot classify an arbitrary manual as a recipe magazine")

print("native_classifier_knowledge_media_regression: OK")
