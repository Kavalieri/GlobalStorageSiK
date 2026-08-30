-- Author regression for recorded-media identity versus presentation.
-- Pure Lua 5.1: RecMedia and tooltip rendering remain runtime responsibilities.

for _, name in ipairs({
	"GS_Router", "GS_I18n", "GS_FluidTaxonomy", "GS_NativeProduct", "GS_CategoryResolution",
	"GS_Network", "GS_Zones", "GS_ZoneRefresh", "GS_Permissions",
}) do
	package.loaded[name] = true
end
package.loaded["GS_ItemSnapshot"] = nil

GlobalStorageSiK = {
	Router = {
		getItemCategory = function() return "Entertainment" end,
		getItemSubCategory = function() return nil end,
	},
	I18n = {
		text = function(key) return key end,
		nameFromItemInstance = function(item) return item:getDisplayName() end,
		isLowQualityDisplayName = function() return false end,
		typeDisplayName = function(fullType) return fullType end,
		getScriptItem = function() return nil end,
	},
	FluidTaxonomy = {
		resolve = function() return nil, nil end,
		stateKey = function() return nil end,
		fillPercent = function() return nil end,
		amountAndCapacity = function() return nil, nil end,
	},
	NativeProduct = { tracePathSample = function() end },
	isAuthoritative = function() return true end,
}

local shared = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/"
dofile(shared .. "GS_ItemSnapshot.lua")

local function media(fullType, itemId, mediaIndex, title)
	local value = {}
	function value:getFullType() return fullType end
	function value:getID() return itemId end
	function value:getDisplayName() return title end
	function value:getName() return title end
	function value:getWorldSprite() return nil end
	function value:getRecordedMediaIndex() return mediaIndex end
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

local vhs = rowsFor({
	media("Base.VHSTape", 1, 214, "Woodcraft Ep. 3"),
	media("Base.VHSTape", 2, 214, "Woodcraft Episode Three"),
	media("Base.VHSTape", 3, 315, "Exposure Survival Ep. 5"),
	media("Base.VHSTape", 4, -1, "VHS Tape"),
	media("Base.VHSTape", 5, -1, "VHS Tape"),
})
assert(countRows(vhs) == 4,
	"media identity must be one row for index 214, one for 315 and one per unknown copy")
local woodcraft = nil
local unknown = 0
for _, row in pairs(vhs) do
	if row.mediaIndex == 214 then woodcraft = row end
	if row.detailKind == "recorded_media" and row.mediaIndex == nil then unknown = unknown + 1 end
end
assert(woodcraft and woodcraft.count == 2 and woodcraft.variantKey == "media:214",
	"same media index did not aggregate independent of presentation title")
assert(woodcraft.displayName == "Woodcraft Ep. 3" or woodcraft.displayName == "Woodcraft Episode Three",
	"media title was not retained as presentation")
assert(unknown == 2, "unknown media copies were collapsed")

-- Execute the real Index contract over the exact persisted snapshot shape.
-- This is the same direct path used by true SP (client/server flags both false).
package.loaded["GS_ItemSnapshot"] = true
local registry = {
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

local function exactNetworkCount(mediaIndex)
	local counts, hasAnyNetwork = GlobalStorageSiK.Index.getNetworkCountsForItem(
		{}, "Base.VHSTape", nil, mediaIndex, nil)
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

local snapshotSource = assert(io.open(shared .. "GS_ItemSnapshot.lua", "rb"))
local snapshotText = snapshotSource:read("*a")
snapshotSource:close()
assert(snapshotText:find('variantKey = mediaIndex ~= nil and ("media:" .. tostring(mediaIndex))', 1, true),
	"snapshot does not use mediaIndex as recorded identity")
local tooltipPath = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/GS_ItemNetworkTooltip.lua"
local tooltipSource = assert(io.open(tooltipPath, "rb"))
local tooltipText = tooltipSource:read("*a")
tooltipSource:close()
assert(tooltipText:find('"\\31mediaIndex:" .. tostring(mediaIndex)', 1, true),
	"tooltip cache/count contract does not key recorded media by index")
assert(tooltipText:find("getVHSTrainingLines", 1, true),
	"VHS skill presentation has no observable runtime hook")
assert(tooltipText:find("TooltipLib", 1, true),
	"third-party tooltip chain has no observable compatibility contract")

-- Load the real tooltip cache/request implementation. Its first SP read fills
-- synchronously but returns unloaded for that frame; the second read observes
-- the cache entry keyed by player + fullType + mediaIndex.
for _, name in ipairs({ "GS_NetClient", "GS_Sandbox", "GS_Log" }) do
	package.loaded[name] = true
end
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
local networks, loaded = Tooltip.getCachedCounts("Base.VHSTape", nil, 214, nil, 0)
assert(networks == nil and loaded == false, "first synchronous SP probe must not fake preloaded data")
networks, loaded = Tooltip.getCachedCounts("Base.VHSTape", nil, 214, nil, 0)
assert(loaded == true and #networks == 1 and networks[1].count == 2,
	"SP tooltip cache lost exact mediaIndex 214 count")
networks, loaded = Tooltip.getCachedCounts("Base.VHSTape", nil, 315, nil, 0)
assert(networks == nil and loaded == false, "mediaIndex 315 reused mediaIndex 214 cache key")
networks, loaded = Tooltip.getCachedCounts("Base.VHSTape", nil, 315, nil, 0)
assert(loaded == true and #networks == 1 and networks[1].count == 1,
	"SP tooltip cache lost exact mediaIndex 315 count")
assert(#sent == 0, "true SP path sent a network command")

-- Exercise the serialized client request and response surface with distinct
-- mediaIndex values. The response handler must not let either cache entry
-- overwrite the other, even though fullType is identical.
Tooltip.invalidateAll()
isClient = function() return true end
Tooltip.getCachedCounts("Base.VHSTape", nil, 214, nil, 3)
Tooltip.getCachedCounts("Base.VHSTape", nil, 315, nil, 3)
assert(#sent == 2, "serialized tooltip requests were incorrectly deduplicated by fullType")
assert(sent[1].command == "getItemNetworkCounts" and sent[1].args.mediaIndex == 214
	and sent[1].playerNum == 3, "serialized request lost mediaIndex 214 or playerNum")
assert(sent[2].command == "getItemNetworkCounts" and sent[2].args.mediaIndex == 315
	and sent[2].playerNum == 3, "serialized request lost mediaIndex 315 or playerNum")
Tooltip.onCountsReceived("Base.VHSTape", {
	{ id = "media_net", name = "Media Network", count = 2 },
}, true, nil, 214, nil, 3)
Tooltip.onCountsReceived("Base.VHSTape", {
	{ id = "media_net", name = "Media Network", count = 1 },
}, true, nil, 315, nil, 3)
local cached214 = select(1, Tooltip.getCachedCounts("Base.VHSTape", nil, 214, nil, 3))
local cached315 = select(1, Tooltip.getCachedCounts("Base.VHSTape", nil, 315, nil, 3))
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
