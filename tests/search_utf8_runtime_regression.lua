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

local accentedName = "Bid" .. string.char(0xC3, 0xB3) .. "n de Gasolina"
local rows = {
	{ fullType = "Base.PetrolCan", displayName = accentedName,
		category = "VehicleMaintenance", subCategory = "Fuel" },
	{ fullType = "Base.Crisps", displayName = "Patatas fritas",
		category = "Food", subCategory = "Other" },
}

local filtered = GlobalStorageSiK.I18n.filterItemRows(rows, "bidon")
assert(#filtered == 1 and filtered[1].fullType == "Base.PetrolCan", "bidon must match Bidón")
local kahluaUnitName = "Bid" .. string.char(0xF3) .. "n de Gasolina"
filtered = GlobalStorageSiK.I18n.filterItemRows({ { fullType = "Base.PetrolCan", displayName = kahluaUnitName } }, "bidon")
assert(#filtered == 1, "single-unit Kahlua/Latin-1 accent must also fold")
local sharpS = "Stra" .. string.char(0xC3, 0x9F) .. "e"
assert(GlobalStorageSiK.I18n.asciiLower(sharpS) == "stra" .. string.char(0xC3, 0x9F) .. "e",
	"unmapped UTF-8 sequences must remain byte-exact")
local chineseName = string.char(0xE6, 0xB1, 0xBD, 0xE6, 0xB2, 0xB9, 0xE6, 0xA1, 0xB6)
assert(GlobalStorageSiK.I18n.asciiLower(chineseName) == chineseName,
	"Chinese UTF-8 must remain byte-exact")
filtered = GlobalStorageSiK.I18n.filterItemRows({ { fullType = "Base.PetrolCan", displayName = chineseName } }, chineseName)
assert(#filtered == 1, "Chinese query must match an unchanged Chinese display name")
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
