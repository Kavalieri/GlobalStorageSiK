-- An abstention stays visible as SiK Other/Unclassified, never vanilla.
package.loaded["GS_NativeProduct"] = true
package.loaded["GS_I18n"] = true
package.loaded["GS_FluidTaxonomy"] = true

GlobalStorageSiK = {
	CatalogManager = { onEpochChanged = function() end },
	NativeProduct = {
		normalizePath = function(path) return path end,
		encodePath = function(path) return "native:" .. path.l1 .. "/" .. path.l2 end,
		decodePath = function() return nil end,
		getView = function() return { fullLabel = "Sin clasificar" } end,
		getColor = function() return { 1, 1, 1, 1 } end,
	},
	NativeClassifier = {
		classify = function()
			return { primaryPath = { l1 = "other", l2 = "unclassified_modded" } }
		end,
	},
	FluidTaxonomy = { resolve = function() return nil end, inspect = function() return nil end },
	I18n = { getScriptItem = function() return nil end },
}

dofile("GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/GS_CategoryResolution.lua")
local result = GlobalStorageSiK.CategoryResolution.resolve("Base.FutureNativeItem", nil, {
	getDisplayCategory = function() return "VanillaCategory" end,
})
assert(result.nativeStatus == "unclassified", "abstention status")
assert(result.effective == "native", "abstention must not become vanilla")
assert(result.nativePath == "native:other/unclassified_modded", "visible abstention path")
assert(result.routingIdentity == result.nativePath, "visible abstention routing")
assert(result.vanillaKey == "VanillaCategory", "compatibility metadata remains available")

print("category_resolution_unclassified_visibility_regression: OK")
