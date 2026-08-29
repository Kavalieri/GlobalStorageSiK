-- Regression tests for Core 1.4.3-dev30 native-product consumption.
-- Run from repository root: lua51.exe tests/native_product_regression.lua

package.loaded["GS_CatalogManager"] = true
package.loaded["GS_NativeClassifier"] = true
package.loaded["GS_NativeTaxonomyRegistry"] = true
package.loaded["GS_ItemTaxonomy"] = true
package.loaded["GS_CategoryResolution"] = true
package.loaded["GS_RuleSanitizer"] = true

local classifierCalls = 0
GlobalStorageSiK = {
	CatalogManager = {
		createEpochCache = function() return {} end,
		onEpochChanged = function() end,
		getEpoch = function() return 7 end,
	},
	NativeTaxonomyRegistry = {
		getTree = function()
			return { food_drink = { produce = { "fruit", "vegetable" } }, materials = { wood = {} } }
		end,
		hasL1 = function(l1) return l1 == "food_drink" or l1 == "materials" end,
		hasL2 = function(l1, l2)
			return (l1 == "food_drink" and l2 == "produce") or (l1 == "materials" and l2 == "wood")
		end,
		hasL3 = function(l1, l2, l3)
			return l1 == "food_drink" and l2 == "produce" and (l3 == "fruit" or l3 == "vegetable")
		end,
	},
	NativeClassifier = {
		classify = function(fullType)
			classifierCalls = classifierCalls + 1
			if fullType == "Base.Apple" then
				return { primaryPath = { l1 = "food_drink", l2 = "produce", l3 = "fruit" } }
			end
			if fullType == "GlobalStorageSiK.Tablet" then
				return { primaryPath = { l1 = "globalstoragesik", l2 = "tablet" } }
			end
			return { primaryPath = { l1 = "materials", l2 = "wood" } }
		end,
		getMetrics = function()
			return { requests = classifierCalls, effectiveClassifications = classifierCalls, cacheHits = 0 }
		end,
	},
	ItemTaxonomy = {
		EXT_GROUP_PREFIX = "__extgroup__:",
		SUBGROUP_PREFIX = "__subgroup__:",
		resolve = function(_, row)
			return { mainCanon = row.category, subCanon = row.subCategory, groupKey = row.category }
		end,
	},
	CategoryResolution = {
		legacyAliasNativePath = function() return nil end,
		classifyStoredRule = function() return "SOURCE_CATEGORY" end,
	},
	I18n = { text = function(key) return key end },
}

local function assertEqual(actual, expected, message)
	if actual ~= expected then
		error((message or "values differ") .. ": expected=" .. tostring(expected)
			.. " actual=" .. tostring(actual), 2)
	end
end

dofile("GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/GS_NativeProduct.lua")
local Product = GlobalStorageSiK.NativeProduct
dofile("GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/GS_RuleSanitizer.lua")

local applePath = Product.getPath("Base.Apple")
assertEqual(Product.encodePath(applePath), "native:food_drink/produce/fruit", "canonical apple path")
assertEqual(Product.encodePath(Product.getPath("Base.Apple")), "native:food_drink/produce/fruit", "cached apple path")
assertEqual(classifierCalls, 1, "at most one effective classification per fullType")
assertEqual(Product.pathMatches("native:food_drink", applePath), true, "L1 prefix")
assertEqual(Product.pathMatches("native:food_drink/produce", applePath), true, "L2 prefix")
assertEqual(Product.pathMatches("native:food_drink/produce/vegetable", applePath), false, "different L3")

local rows = {
	{ fullType = "Base.Apple", nativePath = "native:food_drink/produce/fruit" },
	{ fullType = "Base.Plank", nativePath = "native:materials/wood" },
}
local index = Product.buildIndex(rows)
assertEqual(#Product.rowsForPath(index, "native:food_drink"), 1, "L1 inverse index")
assertEqual(#Product.rowsForPath(index, "native:food_drink/produce"), 1, "L2 inverse index")
assertEqual(classifierCalls, 1, "index consumes precomputed paths")

local copiedRows = Product.copyRows({ {
	fullType = "Base.Apple", nativePath = "native:food_drink/produce/fruit",
	locations = { { nodeId = "node-a", count = 2 } }, futureProductField = "preserved",
} })
assertEqual(copiedRows[1].nativePath, "native:food_drink/produce/fruit", "UI snapshot preserves native path")
assertEqual(copiedRows[1].locations[1].nodeId, "node-a", "UI snapshot preserves locations")
assertEqual(copiedRows[1].futureProductField, "preserved", "UI snapshot preserves future contract fields")

local persisted = { nodes = {
	a = { id = "a", zoneId = "z", categories = { "Food::F", "ValidLegacy" }, rules = {
		{ op = "OR", condition = { type = "category", value = "F" } },
		{ op = "AND", condition = { type = "category", value = "Food", nativePath = "F", legacyValue = "Food" } },
		{ op = "OR", condition = { type = "category", value = "F", nativePath = "native:food_drink/produce/fruit", legacyValue = "F" } },
		{ op = "OR", condition = { type = "category", value = "UnknownButValid" } },
	} },
	b = { id = "b", zoneId = "other", categories = { "Weapon::W" } },
}, zones = {
	z = { id = "z", networkId = "net-a", rules = {
		{ op = "NOT", condition = { type = "category", value = "Food::W" } },
	} },
	other = { id = "other", networkId = "net-b", rules = {} },
} }
local capturedSanitize = GlobalStorageSiK.RuleSanitizer.inspectRegistry(persisted, "net-a")
assertEqual(capturedSanitize.matches, 4, "pre-mutation inspection captures every active junk source")
assertEqual(capturedSanitize.samples[2].nativePath, "F", "inspection captures corrupt nativePath exactly")
assertEqual(capturedSanitize.samples[2].legacyValue, "Food", "inspection captures legacyValue exactly")
local firstSanitize = GlobalStorageSiK.RuleSanitizer.sanitizeRegistry(persisted, "net-a")
assertEqual(firstSanitize.quarantined, 4, "node categories plus node/zone junk rules quarantined")
assertEqual(firstSanitize.unknownPreserved, 1, "unknown non-junk rule preserved")
assertEqual(#persisted.nodes.a.rules, 2, "junk removed while native and unknown rules remain active")
assertEqual(persisted.nodes.a.rules[1].condition.nativePath,
	"native:food_drink/produce/fruit", "valid native path remains authoritative")
assertEqual(#persisted.nodes.a.categories, 1, "junk removed from active legacy categories")
assertEqual(persisted.nodes.a.categories[1], "ValidLegacy", "valid legacy category preserved")
assertEqual(#persisted.nodes.a.legacyJunkRules, 3, "node junk from both sources remains recoverable")
assertEqual(persisted.nodes.a.legacyJunkRules[2].condition.nativePath, "F", "hybrid junk remains restorable")
assertEqual(persisted.nodes.a.legacyJunkRules[3].legacySource, "categories", "legacy category source recorded")
assertEqual(persisted.nodes.a.legacyJunkRules[3].legacyRuleIndex, 1, "legacy source index recorded")
assertEqual(#persisted.zones.z.legacyJunkRules, 1, "zone junk remains recoverable")
assertEqual(persisted.nodes.b.categories[1], "Weapon::W", "other network remains untouched")
assertEqual(firstSanitize.samples[1].networkId, "net-a", "sample records owning network")
local secondSanitize = GlobalStorageSiK.RuleSanitizer.sanitizeRegistry(persisted, "net-a")
assertEqual(secondSanitize.changed, false, "second persisted-rule migration is idempotent")
assertEqual(secondSanitize.quarantined, 0, "second migration quarantines nothing")
assertEqual(#persisted.nodes.a.legacyJunkRules, 3, "quarantine not duplicated")
assertEqual(GlobalStorageSiK.RuleSanitizer.inspectRegistry(persisted, "net-a").matches,
	0, "postvalidation finds no active junk")

print("native_product_regression: OK")
