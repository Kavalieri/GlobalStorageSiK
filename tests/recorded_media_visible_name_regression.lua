-- Regression autoral: un titulo VHS exacto que ya llego como displayName no
-- puede degradarse a la etiqueta generica solo porque mediaTitle aun sea nil.

local terminalItemsPath =
	"GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/GS_TerminalUI_Items.lua"
local handle = assert(io.open(terminalItemsPath, "rb"))
local source = handle:read("*a")
handle:close()

local adapterStart = assert(source:find("local function scriptItem(fullType)", 1, true),
	"VHS presentation adapter start missing")
local adapterEnd = assert(source:find("--- Textura de inventario resuelta", adapterStart, true),
	"VHS presentation adapter boundary missing")
local adapterSource = source:sub(adapterStart, adapterEnd - 1)

local factory = assert(loadstring([[
return function(deps)
	local GlobalStorageSiK = deps.GlobalStorageSiK
	local instanceItem = deps.instanceItem
]] .. adapterSource .. [[
	return localizeRecordedMediaRows, displayNameForRow
end
]], "@recorded_media_visible_name_adapter"))()

local exactTitle = "Woodcraft Ep. 3"
local catalogCalls, probeCalls = 0, 0
local localizeRows, visibleName = factory({
	GlobalStorageSiK = {
		TerminalItems = {},
		Log = { debug = function() end },
		RecordedMedia = {
			titleFromIndex = function(mediaIndex, fullType)
				catalogCalls = catalogCalls + 1
				assert(mediaIndex == 214 and fullType == "Base.VHS_Retail",
					"catalogue received the wrong VHS identity")
				return exactTitle
			end,
		},
		I18n = {
			getScriptItem = function(fullType)
				return fullType == "Base.VHS_Retail" and {} or nil
			end,
			typeDisplayName = function() return "VHS comercial" end,
			-- This is the normal non-media row fallback. If mediaTitle is not
			-- promoted, displayNameForRow will visibly degrade the exact title.
			itemDisplayName = function() return "VHS comercial" end,
		},
	},
	instanceItem = function(fullType)
		probeCalls = probeCalls + 1
		assert(fullType == "Base.VHS_Retail", "probe received the wrong VHS type")
		local probe = { mediaIndex = -1 }
		function probe:setRecordedMediaIndexInteger(value) self.mediaIndex = value end
		function probe:getRecordedMediaIndex() return self.mediaIndex end
		function probe:getName() return exactTitle end
		function probe:getMediaData()
			return { getTranslatedItemDisplayName = function() return exactTitle end }
		end
		return probe
	end,
})

local row = {
	fullType = "Base.VHS_Retail",
	mediaIndex = 214,
	mediaTitle = nil,
	displayName = exactTitle,
	variantSummary = {},
}

localizeRows({ row }, 0)
assert(catalogCalls == 1,
	"fixture did not resolve the exact VHS edition through the vanilla catalogue")
assert(probeCalls == 0,
	"an exact catalogue title must not fall through to synthetic item probing")
assert(row.mediaTitle == exactTitle,
	"exact visible VHS title was not promoted when mediaTitle started nil")
assert(row.displayName == exactTitle and visibleName(row) == exactTitle,
	"exact visible VHS title degraded to the generic item label")

print("recorded_media_visible_name_regression: OK")
