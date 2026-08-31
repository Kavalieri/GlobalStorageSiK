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
		decodePath = function(path)
			if type(path) == "table" then return path end
			if type(path) ~= "string" then return nil end
			local l1, l2, l3 = path:match("^native:([^/]+)/([^/]+)/([^/]+)$")
			return l1 and { l1 = l1, l2 = l2, l3 = l3 } or nil
		end,
		getView = function() return { fullLabel = "unused" } end,
		getColor = function() return { 1, 1, 1, 1 } end,
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
		inspect = function()
			return {
				identityKey = "shape=Base.WaterBottle;content=base:water",
				source = "b42",
				descriptor = {
					canonicalType = "base:water", amount = 1, capacity = 1,
				},
			}
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
assert(resolved.identityKey == "shape=Base.WaterBottle;content=base:water",
	"single category resolution did not expose canonical physical identity")
assert(resolved.categoryPathKeys and resolved.categoryPathKeys.l1 == "food_drink"
	and resolved.categoryPathKeys.l2 == "non_perishable"
	and resolved.categoryPathKeys.l3 == "beverage",
	"single category resolution did not expose unlocalized category path keys")
assert(resolved.source == "b42" and resolved.descriptor
	and resolved.descriptor.canonicalType == "base:water"
	and resolved.descriptor.amount == 1 and resolved.descriptor.capacity == 1,
	"single category resolution did not expose source/descriptor")

local presentation = GlobalStorageSiK.CategoryResolution.presentation("Base.WaterBottle", nil, {
	getDisplayCategory = function() return "Container" end,
})
assert(presentation.resolution.identityKey == resolved.identityKey
	and presentation.source == "b42"
	and presentation.descriptor.canonicalType == "base:water"
	and presentation.categoryPathKeys.l3 == "beverage",
	"presentation recomposed or dropped fields from the canonical resolution")

print("category_resolution_fluid_regression: OK")
