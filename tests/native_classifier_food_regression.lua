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

local function item(fullType, daysFresh, spice, tags, itemType)
	return {
		getFullName = function() return fullType end,
		getItemType = function() return itemType or "base:food" end,
		getDaysFresh = function() return daysFresh end,
		isSpice = function() return spice end,
		getTags = function()
			return { contains = function(_, tag) return tags and tags[tag] == true or false end }
		end,
	}
end

local function assertPath(label, actual, l2, l3, source)
	local registered = {
		perishable = {
			meat_protein=true, dairy_egg=true, fish_seafood=true, produce=true,
			prepared_meal=true, ingredient=true, preserved=true, beverage=true, other_food=true,
		},
		non_perishable = {
			meat_protein=true, dairy_egg=true, fish_seafood=true, produce=true, pantry=true,
			ingredient=true, spice=true, preserved=true, prepared_meal=true, beverage=true,
			animal_feed=true, other_food=true,
		},
	}
	assert(actual and actual.l1 == "food_drink", label .. ": food root")
	assert(actual.l2 == l2, label .. ": expected shelf-life " .. l2 .. ", got " .. tostring(actual.l2))
	assert(actual.l3 == l3, label .. ": expected content " .. l3 .. ", got " .. tostring(actual.l3))
	assert(registered[actual.l2] and registered[actual.l2][actual.l3] == true,
		label .. ": classifier emitted an unregistered L3")
	assert(actual.evidence and actual.evidence.source == source,
		label .. ": expected source " .. source .. ", got " .. tostring(actual.evidence and actual.evidence.source))
end

local function classify(label, fullType, daysFresh, spice, tags, itemType)
	local path, _, _, evidence = classifier(fullType, item(fullType, daysFresh, spice, tags, itemType))
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
	"non_perishable", "other_food", "script_item_type")
assertPath("confirmed spice", classify("confirmed spice", "Base.Salt", 1000000, true),
	"non_perishable", "spice", "script_item_is_spice_confirmed")
assertPath("structural fish tag", classify("structural fish tag", "Base.MysteryFood", 3, false,
	{ ["base:fish_meat"] = true }), "perishable", "fish_seafood", "script_food_tag")
assertPath("perishable pasta tag", classify("perishable pasta tag", "Base.PastaBowl", 3, false,
	{ ["base:pasta"] = true }), "perishable", "prepared_meal", "script_food_tag")
assertPath("preserved food tag", classify("preserved food tag", "Base.DriedFish", 1000000, false,
	{ ["base:dried_food"] = true }), "non_perishable", "preserved", "script_food_tag")
assertPath("cake batter", classify("cake batter", "Base.CakeBatter", 1000000, false),
	"perishable", "ingredient", "script_item_type")
assertPath("canned pineapple", classify("canned pineapple", "Base.CannedPineapple", 1000000, false),
	"non_perishable", "produce", "script_item_type")
assertPath("fresh carrot", classify("fresh carrot", "Base.Carrot", 12, false),
	"perishable", "produce", "script_item_type")
assertPath("beer bottle contents", classify("beer bottle contents", "Base.BeerBottle", 1000000, false),
	"non_perishable", "beverage", "script_item_type")
assertPath("milk bottle contents", classify("milk bottle contents", "Base.MilkBottle", 1000000, false),
	"perishable", "dairy_egg", "script_item_type")
assertPath("filled meat cooler", classify("filled meat cooler", "Base.Cooler_Meat", 1000000, false),
	"non_perishable", "meat_protein", "script_item_type")
assertPath("filled beer cooler", classify("filled beer cooler", "Base.Cooler_Beer", 1000000, false, nil,
	"base:normal"), "non_perishable", "beverage", "name_food_beverage")

local empty = classifier("Base.EmptyBottle", item("Base.EmptyBottle", 4, false))
assert(empty == nil, "empty container must defer to the container classifier")

local cookieJar = item("Base.CookieJar", 1000000, false)
cookieJar.getItemType = function() return "base:normal" end
assert(classifier("Base.CookieJar", cookieJar) == nil,
	"a jar without structural food identity must defer to the container classifier")
local cookieBear = item("Base.CookieJar_Bear", 1000000, false, nil, "base:normal")
assert(classifier("Base.CookieJar_Bear", cookieBear) == nil,
	"a decorative jar suffix is not food content")
local candyBucket = item("Base.HalloweenCandyBucket", 1000000, false, nil, "base:normal")
assert(classifier("Base.HalloweenCandyBucket", candyBucket) == nil,
	"a named bucket without structural contents retains container form")

print("native_classifier_food_regression: OK")
