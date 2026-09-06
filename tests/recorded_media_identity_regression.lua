-- Author regression for recorded-media identity versus presentation.
-- Pure Lua 5.1: RecMedia and tooltip rendering remain runtime responsibilities.

for _, name in ipairs({
	"GS_Router", "GS_I18n", "GS_FluidTaxonomy", "GS_NativeProduct", "GS_CategoryResolution",
	"GS_Network", "GS_Zones", "GS_ZoneRefresh", "GS_Permissions",
}) do
	package.loaded[name] = true
end
package.loaded["SiK/UI/Controls"] = true
package.loaded["SiK/UI/Viewport"] = true
package.loaded["GS_ItemSnapshot"] = nil

SiK = { UI = {
	Controls = {
		truncateText = function(text) return text end,
		wrapText = function(text) return { text } end,
	},
	Viewport = { resolve = function()
		return { x = 0, y = 0, w = 1280, h = 720 }
	end },
} }

GlobalStorageSiK = {
	Router = {
		getItemCategory = function() return "Entertainment" end,
		getItemSubCategory = function() return nil end,
	},
	I18n = {
		text = function(key) return key end,
		nameFromItemInstance = function(item) return item:getName() end,
		isLowQualityDisplayName = function() return false end,
		typeDisplayName = function() return "VHS comercial" end,
		getScriptItem = function() return nil end,
	},
	FluidTaxonomy = {
		resolve = function() return nil, nil end,
		stateKey = function() return nil end,
		fillPercent = function() return nil end,
		amountAndCapacity = function() return nil, nil end,
	},
	CategoryResolution = {
		resolve = function(_, _, _, dynamicPath)
			local encoded = dynamicPath and table.concat({
				dynamicPath.l1, dynamicPath.l2, dynamicPath.l3,
			}, "/") or nil
			return {
				nativePath = encoded,
				nativeStatus = dynamicPath and "classified" or "fallback",
				effective = dynamicPath and "native" or "vanilla",
				routingIdentity = encoded or "vanilla:Entertainment",
				categorySource = dynamicPath and "NATIVE" or "VANILLA",
			}
		end,
	},
	NativeProduct = { tracePathSample = function() end },
	isAuthoritative = function() return true end,
}

local shared = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/"
dofile(shared .. "GS_RecordedMedia.lua")
package.loaded["GS_RecordedMedia"] = true
dofile(shared .. "GS_ItemSnapshot.lua")

local learningPath = GlobalStorageSiK.RecordedMedia.nativePath(214, { "CRP=1,COO=1" })
local leisurePath = GlobalStorageSiK.RecordedMedia.nativePath(315, {})
assert(learningPath and learningPath.l1 == "knowledge_media"
	and learningPath.l2 == "recorded_media" and learningPath.l3 == "with_learning",
	"teaching VHS did not resolve to Knowledge > Recorded media > With learning")
assert(leisurePath and leisurePath.l1 == "knowledge_media"
	and leisurePath.l2 == "recorded_media" and leisurePath.l3 == "leisure",
	"leisure VHS did not resolve to Knowledge > Recorded media > Leisure")
assert(GlobalStorageSiK.RecordedMedia.nativePath(315, nil) == nil,
	"unresolved VHS metadata was guessed as leisure")
assert(GlobalStorageSiK.RecordedMedia.nativePath(-1, nil) == nil,
	"unknown home VHS fabricated a recorded-media L3")

local function media(fullType, itemId, mediaIndex, title, codesOverride)
	local value = {}
	function value:getFullType() return fullType end
	function value:getID() return itemId end
	-- La etiqueta de script es deliberadamente genérica. La única proyección
	-- válida de la edición es getName(player), como hace vanilla RecMedia.
	function value:getDisplayName() return "VHS comercial" end
	function value:getName() return title end
	function value:getWorldSprite() return nil end
	function value:getRecordedMediaIndex() return mediaIndex end
	function value:getMediaData()
		if not mediaIndex or mediaIndex < 0 then return nil end
		local codes = codesOverride
		if codes == nil then
			codes = mediaIndex == 214 and { "CRP=1,COO=1" }
				or mediaIndex == 315 and { "DOC=1" } or {}
		end
		return {
			getId = function() return mediaIndex end,
			getTranslatedItemDisplayName = function() return title end,
			getLineCount = function() return #codes end,
			getLine = function(_, index)
				local value = codes[index + 1]
				if not value then return nil end
				return { getCodes = function() return value end }
			end,
		}
	end
	function value:getActualWeight() return 1 end
	return value
end

local function rowsFor(items)
	local snapshot = {}
	for i = 1, #items do assert(GlobalStorageSiK.ItemSnapshot.addItem(snapshot, items[i])) end
	return snapshot
end

local function countRows(snapshot)
	local count = 0
	for _ in pairs(snapshot) do count = count + 1 end
	return count
end

local exactTooltipDetail = GlobalStorageSiK.ItemSnapshot.tooltipDetailFromItem(
	media("Base.VHS_Retail", 99, 214, "Woodcraft Ep. 3"))
assert(exactTooltipDetail.mediaIndex == 214
	and exactTooltipDetail.mediaTitle == "Woodcraft Ep. 3"
	and exactTooltipDetail.mediaCodes[1] == "CRP=1,COO=1",
	"exact item detail did not propagate mediaIndex/mediaTitle/mediaCodes")

local vhs = rowsFor({
	media("Base.VHS_Retail", 1, 214, "Woodcraft Ep. 3"),
	media("Base.VHS_Retail", 2, 214, "Woodcraft Episode Three"),
	media("Base.VHS_Retail", 3, 315, "Exposure Survival Ep. 5", {}),
	media("Base.VHS_Home", 4, -1, "VHS Tape"),
	media("Base.VHS_Home", 5, -1, "VHS Tape"),
})
assert(countRows(vhs) == 4,
	"media identity must be one row for index 214, one for 315 and one per unknown copy")
local woodcraft = nil
local exposure = nil
local unknown = 0
for _, row in pairs(vhs) do
	if row.mediaIndex == 214 then woodcraft = row end
	if row.mediaIndex == 315 then exposure = row end
	if row.detailKind == "recorded_media" and row.mediaIndex == nil then unknown = unknown + 1 end
end
assert(woodcraft and woodcraft.count == 2 and woodcraft.variantKey == "media:214",
	"same media index did not aggregate independent of presentation title")
assert(woodcraft.displayName == "Woodcraft Ep. 3" or woodcraft.displayName == "Woodcraft Episode Three",
	"media title was not retained as presentation")
assert(woodcraft.mediaTitle ~= "VHS Tape" and woodcraft.mediaCodes
	and woodcraft.mediaCodes[1] == "CRP=1,COO=1",
	"snapshot lost the exact VHS title or training codes")
assert(woodcraft.unitDetails[1].mediaIndex == 214
	and woodcraft.unitDetails[1].mediaTitle ~= "VHS Tape"
	and woodcraft.unitDetails[1].mediaCodes[1] == "CRP=1,COO=1",
	"snapshot unit detail did not propagate exact recorded-media identity")
assert(exposure and exposure.mediaTitle == "Exposure Survival Ep. 5"
	and exposure.mediaCodes and #exposure.mediaCodes == 0,
	"second VHS edition lost its individual title/codes")
assert(woodcraft.nativePath == "knowledge_media/recorded_media/with_learning",
	"teaching VHS lost its L3 in the persisted snapshot")
assert(exposure.nativePath == "knowledge_media/recorded_media/leisure",
	"leisure VHS lost its L3 in the persisted snapshot")
for _, row in pairs(vhs) do
	if row.fullType == "Base.VHS_Home" then
		assert(row.nativePath == nil,
			"unknown home VHS was silently classified as leisure")
	end
end
assert(unknown == 2, "unknown media copies were collapsed")

-- Execute the real Index contract over the exact persisted snapshot shape.
-- This is the same direct path used by true SP (client/server flags both false).
package.loaded["GS_ItemSnapshot"] = true
local registry = {
	_inventoryRevision = { media_net = 7 },
	networks = { media_net = { id = "media_net", name = "Media Network" } },
	zones = { media_zone = { id = "media_zone", networkId = "media_net" } },
	nodes = {
		media_node = {
			id = "media_node", zoneId = "media_zone", itemSnapshot = vhs,
		},
	},
}
GlobalStorageSiK.Network = {
	getRegistry = function() return registry end,
	ensureRegistry = function() end,
	getDefaultNetworkId = function() return "media_net" end,
	getDisplayName = function() return "Media Network" end,
	getLiveContainers = function() return {} end,
}
GlobalStorageSiK.Zones = { getRegistry = function() return registry end }
GlobalStorageSiK.ZoneRefresh = {}
GlobalStorageSiK.Permissions = {
	canAccess = function() return true end,
	canAccessZone = function() return true end,
	filterLiveContainers = function() return {} end,
}
dofile(shared .. "GS_Index.lua")
package.loaded["GS_Index"] = true

GlobalStorageSiK.CategoryResolution = {
	resolve = function(_, row)
		return {
			nativePath = row and row.nativePath or nil,
			nativeStatus = row and row.nativePath and "classified" or "fallback",
			effective = row and row.nativePath and "native" or "vanilla",
			categoryEffective = row and row.nativePath and "native" or "vanilla",
			routingIdentity = row and row.routingIdentity or "vanilla:Entertainment",
			categorySource = "VANILLA",
		}
	end,
}
local parentRows = GlobalStorageSiK.Index.buildRows("media_net", {})
local woodcraftParent = nil
local exposureParent = nil
for i = 1, #parentRows do
	if parentRows[i].mediaIndex == 214 then woodcraftParent = parentRows[i] end
	if parentRows[i].mediaIndex == 315 then exposureParent = parentRows[i] end
end
assert(woodcraftParent and woodcraftParent.count == 2
	and woodcraftParent.displayName == "Woodcraft Ep. 3"
	and woodcraftParent.mediaTitle == "Woodcraft Ep. 3"
	and woodcraftParent.mediaCodes[1] == "CRP=1,COO=1",
	"Index parent dropped exact VHS identity/presentation metadata")
assert(exposureParent and exposureParent.count == 1
	and exposureParent.displayName == "Exposure Survival Ep. 5"
	and exposureParent.mediaTitle == "Exposure Survival Ep. 5"
	and exposureParent.rowKey ~= woodcraftParent.rowKey,
	"single VHS edition lost its title or collapsed into another mediaIndex")
local detailPage = GlobalStorageSiK.Index.buildDetailPage(
	"media_net", {}, woodcraftParent.rowKey, 1, 15)
assert(detailPage.total == 1 and #detailPage.items == 1,
	"two copies of one VHS edition must form one exact detail row")
local woodcraftDetail = detailPage.items[1]
assert(woodcraftDetail.count == 2 and woodcraftDetail.mediaIndex == 214
	and woodcraftDetail.displayName == woodcraftParent.displayName
	and woodcraftDetail.mediaTitle == woodcraftParent.mediaTitle
	and woodcraftDetail.mediaCodes[1] == "CRP=1,COO=1",
	"Index detail dropped mediaIndex/mediaTitle/mediaCodes")
local exposurePage = GlobalStorageSiK.Index.buildDetailPage(
	"media_net", {}, exposureParent.rowKey, 1, 15)
assert(exposurePage.total == 1 and #exposurePage.items == 1,
	"single VHS edition did not produce one exact child")
local exposureDetail = exposurePage.items[1]
assert(exposureDetail.count == 1 and exposureDetail.mediaIndex == 315
	and exposureDetail.displayName == "Exposure Survival Ep. 5"
	and exposureDetail.mediaTitle == "Exposure Survival Ep. 5"
	and exposureDetail.nativePath == "knowledge_media/recorded_media/leisure",
	"single VHS child lost title, identity or leisure L3")
local teachingPerks = GlobalStorageSiK.RecordedMedia.perkKeysFromCodes(woodcraftDetail.mediaCodes)
assert(#teachingPerks == 2 and teachingPerks[1] == "IGUI_perks_Carpentry"
	and teachingPerks[2] == "IGUI_perks_Cooking",
	"teaching codes did not survive snapshot -> group -> detail for tooltip presentation")

-- Pagination is only a view over exact unknown units. Replacing page 1 with
-- another page must neither change the parent identity nor lose/duplicate IDs.
local originalSnapshot = registry.nodes.media_node.itemSnapshot
local unknownItems = {}
for itemId = 1001, 1032 do
	unknownItems[#unknownItems + 1] = media(
		"Base.VHS_Home", itemId, -1, "VHS Tape")
end
registry.nodes.media_node.itemSnapshot = rowsFor(unknownItems)
local unknownParents = GlobalStorageSiK.Index.buildRows("media_net", {})
assert(#unknownParents == 1 and unknownParents[1].count == 32,
	"unknown VHS parent does not represent the complete physical set")
local unknownParent = unknownParents[1]
local seenUnknown, unknownCount = {}, 0
for page = 1, 3 do
	local result = GlobalStorageSiK.Index.buildDetailPage(
		"media_net", {}, unknownParent.rowKey, page, 15)
	assert(result.total == 32 and result.page == page and result.pageSize == 15,
		"pagination changed the exact VHS set metadata")
	for i = 1, #result.items do
		local child = result.items[i]
		assert(child.parentRowKey == unknownParent.rowKey and child.mediaIndex == nil,
			"paginated child changed VHS identity")
		assert(not seenUnknown[child.itemIds[1]], "pagination duplicated an unknown VHS unit")
		seenUnknown[child.itemIds[1]] = true
		unknownCount = unknownCount + 1
	end
end
assert(unknownCount == 32, "pagination omitted unknown VHS units")
registry.nodes.media_node.itemSnapshot = originalSnapshot

local function exactNetworkCount(mediaIndex)
	local counts, hasAnyNetwork = GlobalStorageSiK.Index.getNetworkCountsForItem(
		{}, "Base.VHS_Retail", nil, mediaIndex, nil)
	assert(hasAnyNetwork == true, "accessible media network was not reported")
	assert(#counts == 1 and counts[1].id == "media_net", "exact VHS lookup lost its network")
	return counts[1].count
end

assert(exactNetworkCount(214) == 2, "mediaIndex 214 included another edition or unknown tape")
assert(exactNetworkCount(315) == 1, "mediaIndex 315 included another edition or unknown tape")
assert(exactNetworkCount(214) ~= 3, "VHS tooltip collapsed mediaIndex 214 and 315")

local devices = rowsFor({
	media("Base.LCDDisplay", 10, -1, "LCD Display"),
	media("Base.LCDDisplay", 11, -1, "LCD Display"),
	media("Base.DVDPlayer", 12, -1, "DVD Player"),
	media("Base.DVDPlayer", 13, -1, "DVD Player"),
})
assert(countRows(devices) == 2, "CD/DVD substring heuristic split ordinary devices by itemId")
for _, row in pairs(devices) do
	assert(row.count == 2 and row.detailKind ~= "recorded_media",
		"ordinary CD/DVD-named device was treated as recorded media")
end

-- RecordedMedia may not be initialized when instanceItem first reconstructs
-- a tape. The integer setter can then return normally without preserving the
-- index. That transient probe must not cache its generic name (or a false
-- miss), so a later surface rebuild can resolve the exact edition.
local terminalItemsPath =
	"GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/GS_TerminalUI_Items.lua"
local terminalItemsHandle = assert(io.open(terminalItemsPath, "rb"))
local terminalItemsText = terminalItemsHandle:read("*a")
terminalItemsHandle:close()
local mediaLocalizerStart = assert(terminalItemsText:find(
	"local function scriptItem(fullType)", 1, true), "VHS probe adapter start missing")
local mediaLocalizerEnd = assert(terminalItemsText:find(
	"--- Textura de inventario resuelta", mediaLocalizerStart, true),
	"VHS probe adapter boundary missing")
local mediaLocalizerSource = terminalItemsText:sub(mediaLocalizerStart, mediaLocalizerEnd - 1)
local mediaLocalizerFactory = assert(loadstring([[
return function(deps)
	local GlobalStorageSiK = deps.GlobalStorageSiK
	local instanceItem = deps.instanceItem
]] .. mediaLocalizerSource .. [[
	return localizeRecordedMediaRows
end
]], "@recorded_media_localizer"))()

local recordedMediaReady = false
local probeAttempts, setterCalls = 0, 0
local function transientMediaProbe()
	probeAttempts = probeAttempts + 1
	local probe = { appliedIndex = -1 }
	function probe:setRecordedMediaIndexInteger(index)
		setterCalls = setterCalls + 1
		if recordedMediaReady then self.appliedIndex = index end
	end
	function probe:getRecordedMediaIndex() return self.appliedIndex end
	function probe:getDisplayName()
		return "VHS comercial"
	end
	function probe:getName()
		return self.appliedIndex == 214 and "Woodcraft Ep. 3" or "VHS comercial"
	end
	return probe
end
local localizeRecordedMediaRows = mediaLocalizerFactory({
	GlobalStorageSiK = {
		TerminalItems = {},
		Log = { debug = function() end },
		I18n = {
			getScriptItem = function(fullType)
				return fullType == "Base.VHS_Retail" and {} or nil
			end,
			typeDisplayName = function() return "VHS comercial" end,
		},
	},
	instanceItem = function(fullType)
		assert(fullType == "Base.VHS_Retail", "unexpected media probe type")
		return transientMediaProbe()
	end,
})
local delayedRow = {
	fullType = "Base.VHS_Retail", mediaIndex = 214,
	detailKind = "recorded_media", displayName = "Cinta VHS", variantSummary = {},
}
localizeRecordedMediaRows({ delayedRow })
assert(probeAttempts == 1 and setterCalls == 1,
	"transient RecordedMedia fixture did not exercise the integer setter")
assert(delayedRow.displayName == "Cinta VHS" and delayedRow.mediaTitle == nil,
	"unapplied media index replaced the generic VHS name")
recordedMediaReady = true
localizeRecordedMediaRows({ delayedRow })
assert(probeAttempts == 2 and setterCalls == 2,
	"failed RecordedMedia attempt poisoned probe/title cache")
assert(delayedRow.displayName == "Woodcraft Ep. 3"
	and delayedRow.mediaTitle == "Woodcraft Ep. 3",
	"later valid RecordedMedia probe could not locate the exact edition")
localizeRecordedMediaRows({ delayedRow })
assert(probeAttempts == 2,
	"successful RecordedMedia title was not cached after recovery")

assert(mediaLocalizerSource:find("probe:getName(player)", 1, true),
	"VHS row resolver does not use vanilla getName(player)")
assert(not mediaLocalizerSource:find("probe:getDisplayName", 1, true),
	"VHS row resolver still accepts the generic script display name")
assert(mediaLocalizerSource:find("tostring(tonumber(playerNum) or 0)", 1, true),
	"VHS title cache is not partitioned by player")

local snapshotSource = assert(io.open(shared .. "GS_ItemSnapshot.lua", "rb"))
local snapshotText = snapshotSource:read("*a")
snapshotSource:close()
local titleStart = assert(snapshotText:find(
	"function GlobalStorageSiK.ItemSnapshot.recordedMediaTitleFromItem(item)", 1, true),
	"recorded media title resolver missing")
local titleEnd = assert(snapshotText:find(
	"local recordedMediaTitleFromItem = GlobalStorageSiK.ItemSnapshot.recordedMediaTitleFromItem",
	titleStart, true), "recorded media title resolver boundary missing")
local titleResolver = snapshotText:sub(titleStart, titleEnd - 1)
assert(not titleResolver:find("item:getDisplayName()", 1, true),
	"VHS title still accepts the generic InventoryItem display name")
assert(titleResolver:find("mediaIndex", 1, true) or titleResolver:find("idx", 1, true),
	"VHS title resolver does not consume mediaIndex")
assert(titleResolver:find("item:getMediaData()", 1, true),
	"VHS title does not use the B42 per-instance MediaData adapter")
assert(titleResolver:find("mediaData:getTranslatedItemDisplayName()", 1, true),
	"VHS title does not use the translated title carried by MediaData")
assert(snapshotText:find('variantKey = mediaIndex ~= nil and ("media:" .. tostring(mediaIndex))', 1, true),
	"snapshot does not use mediaIndex as recorded identity")
local tooltipPath = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/GS_ItemNetworkTooltip.lua"
package.path = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/?.lua;" .. package.path
local tooltipSource = assert(io.open(tooltipPath, "rb"))
local tooltipText = tooltipSource:read("*a")
tooltipSource:close()
assert(tooltipText:find('"\\31mediaIndex:" .. tostring(mediaIndex)', 1, true),
	"tooltip cache/count contract does not key recorded media by index")
assert(tooltipText:find("getVHSTrainingLines", 1, true),
        "VHS skill presentation has no observable runtime hook")
assert(tooltipText:find("perkKeysFromCodes(detail.mediaCodes)", 1, true),
	"tooltip does not consume the exact teaching codes propagated by detail")
assert(tooltipText:find("TerminalItems.probeForRow", 1, true),
        "remote VHS tooltip does not reuse the indexed row probe")
local exactProbeAt = assert(tooltipText:find("getVHSTrainingLines(mediaProbe)", 1, true),
        "VHS tooltip does not ask the exact indexed vanilla probe first")
local remoteFallbackAt = assert(tooltipText:find("getRemoteVHSTrainingLines(mediaDetail)", 1, true),
        "VHS tooltip lost the bounded remote fallback")
assert(exactProbeAt < remoteFallbackAt,
        "remote VHS codes take precedence over the exact vanilla probe")
local mediaSkillsStart = assert(tooltipText:find("local function mediaSkillNames(item)", 1, true),
	"per-item MediaData skill adapter missing")
local mediaSkillsEnd = assert(tooltipText:find("local function getVHSTrainingLines(item)",
	mediaSkillsStart, true), "per-item MediaData adapter boundary missing")
local mediaSkills = tooltipText:sub(mediaSkillsStart, mediaSkillsEnd - 1)
assert(mediaSkills:find("item:getMediaData()", 1, true)
	and mediaSkills:find("mediaData:getLineCount()", 1, true)
	and mediaSkills:find("mediaData:getLine(i)", 1, true)
	and mediaSkills:find("line:getCodes()", 1, true),
	"VHS skills do not read only the hovered item's B42 MediaData lines")
assert(not mediaSkills:find("pairs(RecMedia)", 1, true)
	and not mediaSkills:find("getDisplayName", 1, true),
	"VHS skills scan global RecMedia or correlate by display name")
assert(tooltipText:find("TooltipLib", 1, true),
	"third-party tooltip chain has no observable compatibility contract")

-- Load the real tooltip cache/request implementation. Its first SP read fills
-- synchronously but returns unloaded for that frame; the second read observes
-- the cache entry keyed by player + fullType + mediaIndex.
for _, name in ipairs({ "GS_NetClient", "GS_Sandbox", "GS_Log" }) do
	package.loaded[name] = true
end
package.loaded["GS_UI_Framework"] = { Controls = {}, Viewport = {} }
local sent = {}
local directPlayer = {}
GlobalStorageSiK.NetClient = {
	getPlayer = function() return directPlayer end,
	sendCommand = function(command, args, playerNum)
		sent[#sent + 1] = { command = command, args = args, playerNum = playerNum }
		return true
	end,
}
GlobalStorageSiK.Sandbox = { debugMode = function() return false end }
GlobalStorageSiK.Log = {
	debug = function() end, detail = function() end, warn = function() end,
}
GlobalStorageSiK.CategoryResolution = {
	resolve = function() return nil end,
	label = function() return "" end,
}
Events = {
	OnTick = { Add = function() end, Remove = function() end },
}
UIFont = { Small = 1 }
getTimestampMs = function() return 100 end
isClient = function() return false end
isServer = function() return false end
dofile(tooltipPath)

local Tooltip = assert(GlobalStorageSiK.ItemNetworkTooltip)
local networks, loaded = Tooltip.getCachedCounts("Base.VHS_Retail", nil, 214, nil, 0)
assert(networks == nil and loaded == false, "first synchronous SP probe must not fake preloaded data")
networks, loaded = Tooltip.getCachedCounts("Base.VHS_Retail", nil, 214, nil, 0)
assert(loaded == true and #networks == 1 and networks[1].count == 2,
	"SP tooltip cache lost exact mediaIndex 214 count")
networks, loaded = Tooltip.getCachedCounts("Base.VHS_Retail", nil, 315, nil, 0)
assert(networks == nil and loaded == false, "mediaIndex 315 reused mediaIndex 214 cache key")
networks, loaded = Tooltip.getCachedCounts("Base.VHS_Retail", nil, 315, nil, 0)
assert(loaded == true and #networks == 1 and networks[1].count == 1,
	"SP tooltip cache lost exact mediaIndex 315 count")
assert(#sent == 0, "true SP path sent a network command")

-- Exercise the serialized client request and response surface with distinct
-- mediaIndex values. The response handler must not let either cache entry
-- overwrite the other, even though fullType is identical.
Tooltip.invalidateAll()
isClient = function() return true end
Tooltip.getCachedCounts("Base.VHS_Retail", nil, 214, nil, 3)
Tooltip.getCachedCounts("Base.VHS_Retail", nil, 315, nil, 3)
assert(#sent == 2, "serialized tooltip requests were incorrectly deduplicated by fullType")
assert(sent[1].command == "getItemNetworkCounts" and sent[1].args.mediaIndex == 214
	and sent[1].playerNum == 3, "serialized request lost mediaIndex 214 or playerNum")
assert(sent[2].command == "getItemNetworkCounts" and sent[2].args.mediaIndex == 315
	and sent[2].playerNum == 3, "serialized request lost mediaIndex 315 or playerNum")
Tooltip.onCountsReceived("Base.VHS_Retail", {
	{ id = "media_net", name = "Media Network", count = 2 },
}, true, nil, 214, nil, 3)
Tooltip.onCountsReceived("Base.VHS_Retail", {
	{ id = "media_net", name = "Media Network", count = 1 },
}, true, nil, 315, nil, 3)
local cached214 = select(1, Tooltip.getCachedCounts("Base.VHS_Retail", nil, 214, nil, 3))
local cached315 = select(1, Tooltip.getCachedCounts("Base.VHS_Retail", nil, 315, nil, 3))
assert(cached214 and cached214[1].count == 2 and cached315 and cached315[1].count == 1,
	"serialized responses collided in the mediaIndex cache")

local function readRequired(path)
	local handle = assert(io.open(path, "rb"), "cannot read serialization contract: " .. path)
	local text = handle:read("*a")
	handle:close()
	return (text:gsub("%s+", " "))
end
local serverText = readRequired(
	"GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/server/GS_Server.lua")
assert(serverText:find('elseif command == "getItemNetworkCounts" then', 1, true),
	"server omits getItemNetworkCounts dispatcher")
assert(serverText:find("player, fullType, mediaTitle, mediaIndex, dynamicStateKey", 1, true),
	"server does not pass serialized mediaIndex to Index")
assert(serverText:find("mediaIndex = mediaIndex", 1, true),
	"server response does not echo the normalized mediaIndex")
local clientText = readRequired(
	"GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/GS_Client.lua")
assert(clientText:find("args and args.mediaTitle, args and args.mediaIndex, args and args.dynamicStateKey", 1, true),
	"client response dispatcher drops mediaIndex before onCountsReceived")

print("recorded_media_identity_regression: OK")
