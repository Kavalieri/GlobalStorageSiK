-- Authorial source contract for the active VHS presentation path.  Dynamic
-- grouping and fungible-family semantics remain covered by the executable
-- recorded-media/item-grouping regressions run beside this gate.

local CLIENT = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/"
local SHARED = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/"

local function read(path)
	local file = assert(io.open(path, "rb"))
	local value = assert(file:read("*a"))
	file:close()
	return value
end

local function expectContains(value, needle, message)
	assert(string.find(value, needle, 1, true), message or ("missing: " .. needle))
end

local function expectAbsent(value, needle, message)
	assert(not string.find(value, needle, 1, true), message or ("forbidden: " .. needle))
end

local items = read(CLIENT .. "GS_TerminalUI_Items.lua")
local tooltip = read(CLIENT .. "GS_ItemNetworkTooltip.lua")
local spanish = read(SHARED .. "Translate/ES/IG_UI.json")

expectContains(items, "local function resolveRecordedMediaVanillaName", "VHS rows need an exact vanilla-title resolver")
expectContains(items, "local function localizeRecordedMediaRows", "VHS parent and child rows need one localization pass")
expectContains(items, "row.displayName = title", "VHS parent row must display the exact resolved title")
expectContains(items, "row.mediaTitle = title", "VHS parent row must retain the exact media title")
expectContains(items, "summary.displayName = variantTitle", "VHS child row must display the same exact resolved title")
expectContains(items, "summary.mediaTitle = variantTitle", "VHS child row must retain the same exact media title")
expectContains(items, "local function displayNameForRow", "all active row renderers need one VHS-aware name resolver")
expectContains(items, "return row.mediaTitle", "VHS-aware name resolver must prefer the exact title")
expectContains(items, "local function updateRemoteMediaTitle", "lazy detail must update the visible row without regrouping")
expectContains(items, "candidate.mediaCodes = detail.mediaCodes", "lazy exact detail must preserve teaching codes")

expectContains(tooltip, "getVHSTrainingLines", "tooltip must extract teaching data from the concrete VHS")
expectContains(tooltip, "getRemoteVHSTrainingLines", "lazy remote VHS detail must support teaching data")
expectContains(tooltip, "RecordedMedia.perkKeysFromCodes", "teaching labels must derive from propagated mediaCodes")
expectContains(tooltip, 'T("IGUI_GS_VHSSkillHeader")', "teaching block must use its localized Enseña heading")
expectContains(spanish, '"IGUI_GS_VHSSkillHeader": "Enseña:"', "Spanish teaching heading must remain player-facing")
expectContains(tooltip, 'T("IGUI_GS_NetworkCountLine"', "tooltip must include the network-count annex")
expectContains(tooltip, "self.item:DoTooltip(self.tooltip)", "local vanilla tooltip content must remain intact")
expectContains(tooltip, "buildTooltipBlocks(self.item, self._gsRemoteRow)", "the annex must use the exact active row")
expectContains(tooltip, "if #blocks > 0 and placeMeasuredTooltip(",
	"an empty annex must stay hidden instead of painting an empty tooltip")

expectAbsent(tooltip, "IGUI_GS_CategoryTooltipMain", "tooltip must not repeat the table category")
expectAbsent(tooltip, "IGUI_GS_CategoryTooltipSub", "tooltip must not repeat the table category")
expectAbsent(tooltip, "IGUI_GS_CategoryTooltipLeaf", "tooltip must not repeat the table category")

print("vhs_active_presentation_contract: OK")
