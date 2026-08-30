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

-- Lexical fixtures validate normalization only; they are not product
-- translations. Non-Latin scripts must retain every original byte.
local multilingual = {
	{ locale = "ES", text = "cami" .. string.char(0xC3, 0xB3) .. "n", query = "camion" },
	{ locale = "PT", text = "a" .. string.char(0xC3, 0xA7, 0xC3, 0xA3) .. "o", query = "acao" },
	{ locale = "FR", text = "r" .. string.char(0xC3, 0xA9) .. "frig"
		.. string.char(0xC3, 0xA9) .. "rateur", query = "refrigerateur" },
	{ locale = "DE", text = "K" .. string.char(0xC3, 0xBC) .. "che", query = "kuche" },
	{ locale = "IT", text = "citt" .. string.char(0xC3, 0xA0), query = "citta" },
	{ locale = "EN-fallback", text = "Storage Crate", query = "STORAGE" },
}
for i = 1, #multilingual do
	local sample = multilingual[i]
	filtered = GlobalStorageSiK.I18n.filterItemRows({ {
		fullType = "Fixture." .. sample.locale, displayName = sample.text,
	} }, sample.query)
	assert(#filtered == 1, sample.locale .. " normalized query did not match")
end

local cyrillicName = string.char(
	0xD1, 0x82, 0xD0, 0xBE, 0xD0, 0xBF, 0xD0, 0xBB,
	0xD0, 0xB8, 0xD0, 0xB2, 0xD0, 0xBE)
local cyrillicUpper = string.char(
	0xD0, 0xA2, 0xD0, 0x9E, 0xD0, 0x9F, 0xD0, 0x9B,
	0xD0, 0x98, 0xD0, 0x92, 0xD0, 0x9E)
local cjkExtended = chineseName .. string.char(0xE7, 0xAE, 0xB1)
assert(GlobalStorageSiK.I18n.asciiLower(cyrillicName) == cyrillicName,
	"Cyrillic UTF-8 must remain byte-exact")
assert(GlobalStorageSiK.I18n.asciiLower(cyrillicUpper) == cyrillicName,
	"Russian Cyrillic uppercase did not casefold to lowercase")
assert(GlobalStorageSiK.I18n.asciiLower(cjkExtended) == cjkExtended,
	"CJK UTF-8 with a Latin-1-looking lead byte must remain byte-exact")
filtered = GlobalStorageSiK.I18n.filterItemRows({ {
	fullType = "Fixture.Cyrillic", displayName = cyrillicName,
} }, cyrillicName)
assert(#filtered == 1, "Cyrillic exact query did not match")
filtered = GlobalStorageSiK.I18n.filterItemRows({ {
	fullType = "Fixture.RussianUpper", displayName = cyrillicUpper,
} }, cyrillicName)
assert(#filtered == 1, "Russian lowercase query did not match uppercase display name")
filtered = GlobalStorageSiK.I18n.filterItemRows({ {
	fullType = "Fixture.CJK", displayName = cjkExtended,
} }, cjkExtended)
assert(#filtered == 1, "CJK exact query did not match")

local polishUpper = string.char(0xC5, 0xBB, 0xC3, 0x93, 0xC5, 0x81, 0xC4, 0x86)
local polishLower = string.char(0xC5, 0xBC, 0xC3, 0xB3, 0xC5, 0x82, 0xC4, 0x87)
assert(GlobalStorageSiK.I18n.asciiLower(polishUpper) == "zolc"
	and GlobalStorageSiK.I18n.asciiLower(polishLower) == "zolc",
	"Polish diacritics/case did not fold to the same ASCII key")
filtered = GlobalStorageSiK.I18n.filterItemRows({ {
	fullType = "Fixture.Polish", displayName = polishUpper,
} }, "zolc")
assert(#filtered == 1, "ASCII query did not match uppercase Polish diacritics")
assert(#GlobalStorageSiK.I18n.asciiLower(cjkExtended) == #cjkExtended
	and #GlobalStorageSiK.I18n.asciiLower(cyrillicName) == #cyrillicName,
	"non-Latin normalization changed Kahlua byte units")

print("search_utf8_runtime_regression: OK")
