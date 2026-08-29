-- Core 1.4.3-dev32.4.2: source-safe accent folding and stable row refresh.
package.loaded["GS_CatalogManager"] = true
GlobalStorageSiK = {
	CatalogManager = {
		createEpochCache = function() return {} end,
		onEpochChanged = function() end,
		onLanguageEpochChanged = function() end,
		isReady = function() return false end,
	},
	Log = { debug = function() end },
}

dofile("GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/GS_I18n.lua")

local accentedName = "Bid" .. string.char(0xF3) .. "n de Gasolina"
local rows = {
	{ fullType = "Base.PetrolCan", displayName = accentedName,
		category = "VehicleMaintenance", subCategory = "Fuel" },
	{ fullType = "Base.Crisps", displayName = "Patatas fritas",
		category = "Food", subCategory = "Other" },
}

local filtered = GlobalStorageSiK.I18n.filterItemRows(rows, "bidon")
assert(#filtered == 1 and filtered[1].fullType == "Base.PetrolCan", "bidon must match Bidón")
filtered = GlobalStorageSiK.I18n.filterItemRows(rows, "BIDON")
assert(#filtered == 1, "uppercase query")
filtered = GlobalStorageSiK.I18n.filterItemRows(rows, "petrolcan")
assert(#filtered == 1, "fullType query")
filtered = GlobalStorageSiK.I18n.filterItemRows(rows, "fuel")
assert(#filtered == 1, "category query")

local refreshed = {
	{ fullType = "Base.PetrolCan", displayName = accentedName,
		category = "VehicleMaintenance", subCategory = "Fuel" },
}
filtered = GlobalStorageSiK.I18n.filterItemRows(refreshed, "bidon")
assert(#filtered == 1, "new row tables after refresh keep search semantics")

print("search_utf8_runtime_regression: OK")
