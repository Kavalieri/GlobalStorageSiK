-- Regression test for Core 1.4.3-dev32.4 visible vanilla movibles.
-- Run from GlobalStorageSiK-Repo: lua51.exe tests/native_classifier_movable_regression.lua

package.loaded["GS_NativeClassifierApi"] = true
package.loaded["GS_NativeClassifierUtils"] = true

local classifier = nil
GlobalStorageSiK = { NativeClassifier = { registerBlock = function(fn) classifier = fn end } }
dofile("GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/GS_NativeClassifierUtils.lua")
dofile("GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/GS_NativeClassifierHomeLeisure.lua")
assert(classifier, "home classifier must register its block")

local function movable(fullType)
	return { getFullName = function() return fullType end }
end

local function assertPath(fullType, expected)
	local path, _, _, evidence = classifier(fullType, movable(fullType))
	assert(path and path.l2 == "furnishing" and path.l3 == expected,
		fullType .. " must expose an actionable furnishing route")
	assert(evidence.primary.source == "name_movable_" .. expected, fullType .. " evidence")
end

assertPath("Base.Mov_BirchDrawers", "storage")
assertPath("Base.Mov_CabinetTool", "storage")
assertPath("Base.Mov_KitchenCounter", "surface")

print("native_classifier_movable_regression: OK")
