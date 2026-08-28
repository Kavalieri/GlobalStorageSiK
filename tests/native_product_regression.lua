-- Regression tests for Core 1.4.3-dev30 native-product consumption.
-- Run from repository root: lua51.exe tests/native_product_regression.lua

package.loaded["GS_CatalogManager"] = true
package.loaded["GS_NativeClassifier"] = true
package.loaded["GS_NativeTaxonomyRegistry"] = true
package.loaded["GS_ItemTaxonomy"] = true

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

local owners = { { id = "node-a", rules = {
	{ op = "OR", condition = { type = "category", value = "Food" } },
} } }
local catalog = { {
	fullType = "Base.Apple", category = "Food", subCategory = "Produce",
	gsSubKeysStr = "", nativePath = "native:food_drink/produce/fruit",
} }
local plan = Product.auditMigration(owners, catalog)
assertEqual(#plan.transformable, 1, "legacy alias preflight")
assertEqual(#plan.ambiguous, 0, "unambiguous preflight")
assertEqual(Product.applyAuditedMigration(plan), 1, "first additive migration")
assertEqual(Product.applyAuditedMigration(plan), 0, "second migration is idempotent")
local condition = owners[1].rules[1].condition
assertEqual(condition.value, "Food", "legacy value preserved")
assertEqual(condition.legacyValue, "Food", "recoverable legacy copy")
assertEqual(condition.nativePath, "native:food_drink/produce/fruit", "native path added")
assertEqual(Product.recordRoutingContrast(2, 2), true, "equivalent routing contrast")
assertEqual(Product.recordRoutingContrast(nil, 1), false, "routing delta detected")

print("native_product_regression: OK")
