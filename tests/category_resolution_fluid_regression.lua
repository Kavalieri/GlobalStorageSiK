-- Regression test for Core 1.4.3-dev32.4 dynamic-fluid routing identity.
-- Run from GlobalStorageSiK-Repo: lua51.exe tests/category_resolution_fluid_regression.lua

package.loaded["GS_NativeProduct"] = true
package.loaded["GS_I18n"] = true
package.loaded["GS_FluidTaxonomy"] = true

GlobalStorageSiK = {
	CatalogManager = { onEpochChanged = function() end },
	NativeProduct = {
		normalizePath = function(path) return path end,
		encodePath = function(path)
			return path and ("native:" .. path.l1 .. "/" .. tostring(path.l2)
				.. (path.l3 and ("/" .. path.l3) or "")) or nil
		end,
		decodePath = function(path) return type(path) == "table" and path or nil end,
		getView = function() return { fullLabel = "unused" } end,
	},
	NativeClassifier = {
		classify = function()
			return { primaryPath = { l1 = "other", l2 = "unclassified_modded" } }
		end,
	},
	FluidTaxonomy = {
		resolve = function()
			return { l1 = "food_drink", l2 = "non_perishable", l3 = "beverage" }, "fluid=Water amount=1"
		end,
	},
	I18n = { getScriptItem = function() return nil end },
}

dofile("GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/GS_CategoryResolution.lua")

local resolved = GlobalStorageSiK.CategoryResolution.resolve("Base.WaterBottle", nil, {
	getDisplayCategory = function() return "Container" end,
})
assert(resolved.nativeStatus == "classified", "dynamic content must not inherit the static abstention")
assert(resolved.nativePath == "native:food_drink/non_perishable/beverage", "dynamic content path")
assert(resolved.routingIdentity == "native:food_drink/non_perishable/beverage", "routing separates the same fullType by content")

print("category_resolution_fluid_regression: OK")
