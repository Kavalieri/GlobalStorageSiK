-- Canonical RecordedMedia identity must come from the vanilla catalogue by
-- mediaIndex. The inventory fullType identifies only the physical carrier.

GlobalStorageSiK = {}

local function data(index, title)
	return {
		getIndexForLua = function() return index end,
		getTranslatedItemDisplayName = function() return title end,
	}
end

local retailEntries = {
	data(214, "VHS: Woodcraft Ep. 3"),
	data(315, "VHS: Exposure Survival Ep. 5"),
}
local homeEntries = { data(701, "Home VHS: Birthday") }
local categoryReads = 0
local categories = { "Retail-VHS", "Home-VHS" }

local carrierCategories = {
	["Base.VHS_Retail"] = "Retail-VHS",
	["Base.VHS_Home"] = "Home-VHS",
}

function getScriptManager()
	return {
		getItem = function(_, fullType)
			local category = assert(carrierCategories[fullType], "unexpected recorded-media carrier")
			return { getRecordedMediaCat = function() return category end }
		end,
	}
end

function getZomboidRadio()
	return {
		getRecordedMedia = function()
			return {
				getCategories = function()
					return {
						size = function() return #categories end,
						get = function(_, index) return categories[index + 1] end,
					}
				end,
				getAllMediaForCategory = function(_, category)
					categoryReads = categoryReads + 1
					local entries = category == "Retail-VHS" and retailEntries
						or category == "Home-VHS" and homeEntries or nil
					assert(entries, "wrong vanilla media category")
					return {
						size = function() return #entries end,
						get = function(_, index) return entries[index + 1] end,
					}
				end,
			}
		end,
	}
end

local shared = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/"
dofile(shared .. "GS_RecordedMedia.lua")

local RecordedMedia = assert(GlobalStorageSiK.RecordedMedia)
assert(RecordedMedia.titleFromIndex(214, "Base.VHS_Retail") == "VHS: Woodcraft Ep. 3",
	"catalogue lookup lost the exact translated VHS title")
assert(RecordedMedia.titleFromIndex(315, "Base.VHS_Retail") == "VHS: Exposure Survival Ep. 5",
	"different mediaIndex values collapsed into the same VHS title")
assert(RecordedMedia.titleFromIndex(701, "Base.VHS_Home") == "Home VHS: Birthday",
	"real Base.VHS_Home carrier did not use its vanilla media category")
assert(RecordedMedia.titleFromIndex(701, "Base.LegacyRecordedCarrier") == "Home VHS: Birthday",
	"canonical mediaIndex did not recover a persisted/third-party carrier without category")
assert(RecordedMedia.titleFromIndex(999, "Base.VHS_Home") == nil,
	"unknown mediaIndex fabricated a title")
assert(RecordedMedia.titleFromIndex(-1, "Base.VHS_Retail") == nil,
	"unrecorded carrier fabricated a title")
assert(categoryReads == 7, "category fallback did not remain bounded to the vanilla catalogue")

local learning = RecordedMedia.nativePath(214, { "CRP=1" })
local leisure = RecordedMedia.nativePath(315, {})
assert(learning and learning.l3 == "with_learning", "teaching VHS lost its L3")
assert(leisure and leisure.l3 == "leisure", "leisure VHS lost its L3")
assert(RecordedMedia.nativePath(999, nil) == nil,
	"unknown VHS fabricated a learning/leisure L3")

print("recorded_media_catalog_regression: OK")
