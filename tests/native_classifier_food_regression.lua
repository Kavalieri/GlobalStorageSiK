-- Regression tests for Core 1.4.3-dev32.4 food shelf-life/content paths.
-- Run from GlobalStorageSiK-Repo: lua51.exe tests/native_classifier_food_regression.lua

package.loaded["GS_NativeClassifierApi"] = true
package.loaded["GS_NativeClassifierUtils"] = true

local classifier = nil
GlobalStorageSiK = {
	NativeClassifier = {
		registerBlock = function(fn) classifier = fn end,
	},
}

ResourceLocation = { of = function(key) return key end }
ItemTag = { get = function(key) return key end }

dofile("GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/GS_NativeClassifierUtils.lua")
dofile("GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/GS_NativeClassifierFood.lua")
assert(classifier, "food classifier must register its block")

local function item(fullType, daysFresh, spice, tags)
	return {
		getFullName = function() return fullType end,
		getItemType = function() return "base:food" end,
		getDaysFresh = function() return daysFresh end,
		isSpice = function() return spice end,
		getTags = function()
			return { contains = function(_, tag) return tags and tags[tag] == true or false end }
		end,
	}
end

local function assertPath(label, actual, l2, l3, source)
	assert(actual and actual.l1 == "food_drink", label .. ": food root")
	assert(actual.l2 == l2, label .. ": expected shelf-life " .. l2 .. ", got " .. tostring(actual.l2))
	assert(actual.l3 == l3, label .. ": expected content " .. l3 .. ", got " .. tostring(actual.l3))
	assert(actual.evidence and actual.evidence.source == source,
		label .. ": expected source " .. source .. ", got " .. tostring(actual.evidence and actual.evidence.source))
end

local function classify(label, fullType, daysFresh, spice, tags)
	local path, _, _, evidence = classifier(fullType, item(fullType, daysFresh, spice, tags))
	path.evidence = evidence and evidence.primary or nil
	return path
end

-- `isSpice()` is deliberately true in several B42 foods. It cannot erase a
-- more useful content signal unless the product is actually a spice.
assertPath("raw meat", classify("raw meat", "Base.Beef", 4, true),
	"perishable", "meat_protein", "script_item_type")
assertPath("prepared burger", classify("prepared burger", "Base.Burger", 4, true),
	"perishable", "prepared_meal", "script_item_type")
assertPath("opened canned produce", classify("opened canned produce", "Base.CannedTomatoOpen", 4, true),
	"perishable", "produce", "script_item_type")
assertPath("shelf-stable snack", classify("shelf-stable snack", "Base.Chips", 1000000, false),
	"non_perishable", "snack", "script_item_type")
assertPath("confirmed spice", classify("confirmed spice", "Base.Salt", 1000000, true),
	"non_perishable", "spice", "script_item_is_spice_confirmed")
assertPath("structural fish tag", classify("structural fish tag", "Base.MysteryFood", 3, false,
	{ ["base:fish_meat"] = true }), "perishable", "fish_seafood", "script_food_tag")
assertPath("perishable pasta tag", classify("perishable pasta tag", "Base.PastaBowl", 3, false,
	{ ["base:pasta"] = true }), "perishable", "prepared_meal", "script_food_tag")
assertPath("preserved food tag", classify("preserved food tag", "Base.DriedFish", 1000000, false,
	{ ["base:dried_food"] = true }), "non_perishable", "preserved", "script_food_tag")

local empty = classifier("Base.EmptyBottle", item("Base.EmptyBottle", 4, false))
assert(empty == nil, "empty container must defer to the container classifier")

print("native_classifier_food_regression: OK")
