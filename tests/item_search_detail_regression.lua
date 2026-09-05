-- Author regression for warehouse parent-row search without remote detail.
-- Pure Lua 5.1: real Index compaction + real localized I18n haystack/cache.

local shared = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/"

Events = {
	OnGameBoot = { Add = function() end },
}
GlobalStorageSiK = { Log = { debug = function() end } }
dofile(shared .. "GS_CatalogManager.lua")
package.loaded["GS_CatalogManager"] = true
dofile(shared .. "GS_I18n.lua")

local currentLocale = "ES"
local viewCalls = 0
local resolveCalls = 0
local paths = {
	food = "native:food/non_perishable/other_food",
	fuel = "native:vehicles/consumable/fuel",
	empty = "native:containers/liquid/empty",
	media = "native:knowledge/media/recorded",
}
local localizedViews = {
	ES = {
		[paths.food] = { "Comida y bebida", "No perecedero", "Otros alimentos" },
		[paths.fuel] = { "Veh" .. string.char(0xC3, 0xAD) .. "culos", "Consumibles", "Combustible" },
		[paths.empty] = { "Contenedores", "L" .. string.char(0xC3, 0xAD) .. "quidos", "Vac" .. string.char(0xC3, 0xAD) .. "o" },
		[paths.media] = { "Conocimiento", "Medios", "Grabados" },
	},
	PT = {
		[paths.food] = { "Comida", "N" .. string.char(0xC3, 0xA3) .. "o perec" .. string.char(0xC3, 0xAD) .. "vel", "Outros" },
		[paths.fuel] = { "Ve" .. string.char(0xC3, 0xAD) .. "culos", "Consum" .. string.char(0xC3, 0xAD) .. "veis", "Combust" .. string.char(0xC3, 0xAD) .. "vel" },
		[paths.empty] = { "Recipientes", "L" .. string.char(0xC3, 0xAD) .. "quidos", "Vazio" },
		[paths.media] = { "Conhecimento", "M" .. string.char(0xC3, 0xAD) .. "dia", "Gravados" },
	},
}

GlobalStorageSiK.NativeProduct = {
	tracePathSample = function() end,
	getView = function(nativePath)
		viewCalls = viewCalls + 1
		local labels = assert(localizedViews[currentLocale][nativePath], "missing fixture view: " .. tostring(nativePath))
		return {
			l1Label = labels[1], l2Label = labels[2], l3Label = labels[3],
			fullLabel = table.concat(labels, " > "),
		}
	end,
}
GlobalStorageSiK.CategoryResolution = {
	resolve = function(_, row)
		resolveCalls = resolveCalls + 1
		if row and row.nativePath then
			return { effective = "native", nativePath = row.nativePath, vanillaKey = row.category }
		end
		return { effective = "mixed", vanillaKey = row and row.category or "Misc" }
	end,
	label = function(resolved)
		return resolved and resolved.vanillaKey or "Misc"
	end,
}

-- Cache keys are intrinsic values, not Lua table identity. variantSearchText
-- must participate in the key, and language epoch must invalidate labels.
local cacheRowA = {
	fullType = "Base.VHS_Retail", displayName = "Cinta VHS", category = "Media",
	nativePath = paths.media, variantSearchText = "media:214 Woodcraft Ep. 3",
}
local haystackA = GlobalStorageSiK.I18n.itemSearchHaystack(cacheRowA)
local callsAfterA = resolveCalls + viewCalls
local cacheRowClone = {
	fullType = cacheRowA.fullType, displayName = cacheRowA.displayName,
	category = cacheRowA.category, nativePath = cacheRowA.nativePath,
	variantSearchText = cacheRowA.variantSearchText,
}
assert(GlobalStorageSiK.I18n.itemSearchHaystack(cacheRowClone) == haystackA,
	"logically equal replacement row changed its search haystack")
assert(resolveCalls + viewCalls == callsAfterA,
	"search cache depends on row table identity instead of intrinsic key")

local cacheRowChanged = {
	fullType = cacheRowA.fullType, displayName = cacheRowA.displayName,
	category = cacheRowA.category, nativePath = cacheRowA.nativePath,
	variantSearchText = "media:315 Exposure Survival Ep. 5",
}
local haystackChanged = GlobalStorageSiK.I18n.itemSearchHaystack(cacheRowChanged)
assert(haystackChanged:find("exposure survival", 1, true)
	and not haystackChanged:find("woodcraft", 1, true),
	"variantSearchText change reused a stale cache key")

assert(haystackA:find("conocimiento", 1, true), "ES localized path missing before epoch change")
currentLocale = "PT"
GlobalStorageSiK.CatalogManager.bumpLanguageEpoch()
local haystackPt = GlobalStorageSiK.I18n.itemSearchHaystack(cacheRowA)
assert(haystackPt:find("conhecimento", 1, true)
	and not haystackPt:find("conocimiento", 1, true),
	"language epoch did not rebuild the localized search cache")
currentLocale = "ES"
GlobalStorageSiK.CatalogManager.bumpLanguageEpoch()

-- Build real compact parents from persisted snapshots. No buildDetailPage,
-- RemoteItemDetail or tooltip request is available to this harness.
for _, moduleName in ipairs({
	"GS_Network", "GS_Router", "GS_Zones", "GS_ItemSnapshot", "GS_ZoneRefresh",
	"GS_NativeProduct", "GS_CategoryResolution", "GS_Permissions",
}) do
	package.loaded[moduleName] = true
end
GlobalStorageSiK.RemoteItemDetail = {
	request = function() error("search attempted remote item detail", 0) end,
}
GlobalStorageSiK.I18n.getScriptItem = function(fullType)
	return fullType == "Base.Crisps" and {} or nil
end
GlobalStorageSiK.I18n.typeDisplayName = function(fullType) return fullType end

local snapshot = {
	chips_plain = {
		rowKey = "Base.Crisps", fullType = "Base.Crisps", displayName = "Patatas fritas - Original",
		category = "Food", count = 1, variantKey = "fungible", nativePath = paths.food,
	},
	chips_barbecue = {
		rowKey = "Base.Crisps2", fullType = "Base.Crisps2", displayName = "Patatas fritas - Barbacoa",
		category = "Food", count = 1, variantKey = "fungible", nativePath = paths.food,
	},
	vhs_214 = {
		rowKey = "Base.VHS_Retail\31variant:media:214", fullType = "Base.VHS_Retail",
		displayName = "Woodcraft Ep. 3", category = "Media", count = 2,
		detailKind = "recorded_media", variantKey = "media:214", mediaIndex = 214,
		mediaTitle = "Woodcraft Ep. 3", nativePath = paths.media,
	},
	vhs_315 = {
		rowKey = "Base.VHS_Retail\31variant:media:315", fullType = "Base.VHS_Retail",
		displayName = "Exposure Survival Ep. 5", category = "Media", count = 1,
		detailKind = "recorded_media", variantKey = "media:315", mediaIndex = 315,
		mediaTitle = "Exposure Survival Ep. 5", nativePath = paths.media,
	},
	petrol = {
		rowKey = "Base.PetrolCan\31variant:fluid:petrol", fullType = "Base.PetrolCan",
		displayName = "Bid" .. string.char(0xC3, 0xB3) .. "n de gasolina", category = "Container",
		count = 1, detailKind = "fluid", variantKey = "fluid:petrol",
		dynamicStateKey = "fluid:Base.Petrol", nativePath = paths.fuel,
	},
	empty_can = {
		rowKey = "Base.PetrolCan\31variant:fluid:empty", fullType = "Base.PetrolCan",
		displayName = "Bid" .. string.char(0xC3, 0xB3) .. "n vac" .. string.char(0xC3, 0xAD) .. "o",
		category = "Container", count = 1, detailKind = "fluid", variantKey = "fluid:empty",
		dynamicStateKey = "empty", nativePath = paths.empty,
	},
}
local registry = {
	networks = { net = { id = "net" } },
	zones = { zone = { id = "zone", networkId = "net" } },
	nodes = { node = { id = "node", zoneId = "zone", itemSnapshot = snapshot } },
}
GlobalStorageSiK.Network = {
	getDefaultNetworkId = function() return "net" end,
	getLiveContainers = function() return {} end,
	getRegistry = function() return registry end,
	ensureRegistry = function() end,
}
GlobalStorageSiK.Zones = { getRegistry = function() return registry end }
GlobalStorageSiK.Permissions = {
	filterLiveContainers = function() return {} end,
	canAccessZone = function() return true end,
	canAccess = function() return true end,
}
GlobalStorageSiK.ZoneRefresh = {}
GlobalStorageSiK.ItemSnapshot = {
	toRows = function(byType)
		local rows = {}
		for _, row in pairs(byType or {}) do rows[#rows + 1] = row end
		return rows
	end,
}
UI = { Controls = {
	effectiveSearchQuery = function(query) return query end,
} }
dofile(shared .. "GS_Index.lua")

local rows = GlobalStorageSiK.Index.buildRows("net", {})
local byType = {}
local vhsByIndex = {}
for i = 1, #rows do
	byType[rows[i].fullType] = rows[i]
	if rows[i].fullType == "Base.VHS_Retail" then
		vhsByIndex[rows[i].mediaIndex] = rows[i]
	end
end
local chips = assert(byType["Base.Crisps"], "chips parent missing")
local vhs214 = assert(vhsByIndex[214], "VHS mediaIndex 214 parent missing")
local vhs315 = assert(vhsByIndex[315], "VHS mediaIndex 315 parent missing")
local fluid = assert(byType["Base.PetrolCan"], "fluid parent missing")

assert(chips.variantSearchText:find("Patatas fritas - Barbacoa", 1, true),
	"distinct unit display name is absent from parent search text")
assert(vhs214.variantSearchText:find("Woodcraft Ep. 3", 1, true)
	and vhs214.variantSearchText:find("media:214", 1, true),
	"VHS 214 title/identity is absent from its parent search text")
assert(vhs315.variantSearchText:find("Exposure Survival Ep. 5", 1, true)
	and vhs315.variantSearchText:find("media:315", 1, true),
	"VHS 315 title/identity is absent from its parent search text")
assert(fluid.variantSearchText:find("Bid", 1, true)
	and fluid.variantSearchText:find("fluid:Base.Petrol", 1, true)
	and fluid.variantSearchText:find("empty", 1, true),
	"fluid unit/state data is absent from parent search text")
assert(fluid.mixedVariants and #fluid.nativePaths == 2,
	"fluid parent did not preserve both exact native paths")

local function expectOne(query, expected, message)
	local filtered = GlobalStorageSiK.I18n.filterItemRows(rows, query)
	assert(#filtered == 1 and filtered[1] == expected, message .. ": " .. query)
end
expectOne("Barbacoa", chips, "unit display-name search failed")
expectOne("Woodcraft", vhs214, "VHS title search failed")
expectOne("315", vhs315, "VHS edition/index search failed")
expectOne("Base.PetrolCan", fluid, "fullType search failed")
expectOne("PetrolCan", fluid, "short fullType search failed")
expectOne("Base.Petrol", fluid, "fluid content/state search failed")
expectOne("vacio", fluid, "localized empty-container/path search failed")
expectOne("combustible", fluid, "localized mixed fuel path search failed")

-- Execute the exact applyItemsFilter function body from product source with
-- three process-mode flag combinations. The function is intentionally pure:
-- localized filtering must not depend on isClient/isServer.
local function read(path)
	local handle = assert(io.open(path, "rb"), "cannot read search contract: " .. path)
	local text = handle:read("*a")
	handle:close()
	return text
end
local terminalPath = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/GS_TerminalUI.lua"
local terminalSource = read(terminalPath)
local applyStart = assert(terminalSource:find("function GS_TerminalUI:applyItemsFilter(rows)", 1, true),
	"TerminalUI applyItemsFilter missing")
local applyFinish = assert(terminalSource:find("function GS_TerminalUI:getMainCategoryFilterKey()", applyStart, true),
	"TerminalUI applyItemsFilter boundary missing")
local applySource = terminalSource:sub(applyStart, applyFinish - 1)
local i18nPos = assert(applySource:find("GlobalStorageSiK.I18n.filterItemRows", 1, true),
	"TerminalUI does not prefer localized item filtering")
local fallbackPos = assert(applySource:find("GlobalStorageSiK.Index.filterRows", 1, true),
	"TerminalUI omits defensive Index fallback")
assert(i18nPos < fallbackPos, "Index fallback precedes localized filtering")
for _, forbidden in ipairs({ "isClient", "isServer", "isAuthoritative" }) do
	assert(not applySource:find(forbidden, 1, true),
		"TerminalUI search has a process-mode gate: " .. forbidden)
end

GS_TerminalUI = {}
assert(loadstring(applySource, "@applyItemsFilter-product"))()
local originalFilter = GlobalStorageSiK.I18n.filterItemRows
local localizedCalls, fallbackCalls = 0, 0
GlobalStorageSiK.I18n.filterItemRows = function(inputRows, query)
	localizedCalls = localizedCalls + 1
	return originalFilter(inputRows, query)
end
GlobalStorageSiK.Index.filterRows = function(inputRows)
	fallbackCalls = fallbackCalls + 1
	return inputRows
end
GlobalStorageSiK.TerminalItems = {
	filterByMainCategory = function(inputRows) return inputRows end,
	filterBySubCategory = function(inputRows) return inputRows end,
	filterByLeafCategory = function(inputRows) return inputRows end,
}
local terminal = {
	getMainCategoryFilterKey = function() return "" end,
	getSubCategoryFilterKey = function() return "" end,
	getLeafCategoryFilterKey = function() return "" end,
	getSearchQuery = function() return "Woodcraft" end,
}
local modes = {
	{ name = "SP", client = false, server = false },
	{ name = "host", client = true, server = true },
	{ name = "MP-client", client = true, server = false },
}
for i = 1, #modes do
	local mode = modes[i]
	isClient = function() return mode.client end
	isServer = function() return mode.server end
	local result = GS_TerminalUI.applyItemsFilter(terminal, rows)
	assert(#result == 1 and result[1] == vhs214,
		mode.name .. " did not return the same localized VHS search result")
end
assert(localizedCalls == #modes and fallbackCalls == 0,
	"localized filtering was not the sole primary path in every process mode")
GlobalStorageSiK.I18n.filterItemRows = nil
local fallbackResult = GS_TerminalUI.applyItemsFilter(terminal, rows)
assert(fallbackCalls == 1 and fallbackResult == rows,
	"Index fallback did not run exactly when localized filtering was absent")
GlobalStorageSiK.I18n.filterItemRows = originalFilter

local itemsSource = read(
	"GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/GS_TerminalUI_Items.lua")
assert(not itemsSource:find("local detailPagesByRowKey = {}", 1, true),
	"TerminalItems restored a duplicate detail-page cache")
assert(itemsSource:find("client and client.itemDetailsCache or nil", 1, true),
	"TerminalItems does not read the shared Client.itemDetailsCache")
local clientSource = read(
	"GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/GS_Client.lua")
assert(clientSource:find("MAX_ITEM_DETAIL_PAGES", 1, true)
	and clientSource:find("storeBounded(GlobalStorageSiK.Client.itemDetailsCache", 1, true),
	"Client itemDetailsCache is not observably bounded")

local i18nSource = read(shared .. "GS_I18n.lua")
assert(i18nSource:find("local ITEM_SEARCH_CACHE_MAX = 4096", 1, true)
	and i18nSource:find("local ITEM_SEARCH_CACHE_TRIM = 2048", 1, true),
	"item search cache cap/trim constants changed or disappeared")
assert(i18nSource:find("GlobalStorageSiK.CatalogManager.onEpochChanged(clearItemSearchOrder)", 1, true)
	and i18nSource:find("GlobalStorageSiK.CatalogManager.onLanguageEpochChanged(clearItemSearchOrder)", 1, true),
	"item search cache order is not invalidated with both epochs")

-- Runtime eviction: place a known oldest key, add more than the hard cap,
-- then require a recomputation with identical semantics. Category resolution
-- is the observable expensive step; a table-identity cache could not satisfy
-- the earlier clone check, and an untrimmed cache would not increment here.
local evictionRow = {
	fullType = "Fixture.CacheOldest", displayName = "Oldest searchable value",
	category = "Fixture", variantSearchText = "oldest-detail",
}
local evictionHaystack = GlobalStorageSiK.I18n.itemSearchHaystack(evictionRow)
local afterEvictionSeed = resolveCalls
assert(GlobalStorageSiK.I18n.itemSearchHaystack({
	fullType = evictionRow.fullType, displayName = evictionRow.displayName,
	category = evictionRow.category, variantSearchText = evictionRow.variantSearchText,
}) == evictionHaystack and resolveCalls == afterEvictionSeed,
	"eviction seed was not cached by intrinsic key")
for i = 1, 4097 do
	GlobalStorageSiK.I18n.itemSearchHaystack({
		fullType = "Fixture.Cache" .. tostring(i),
		displayName = "Cache value " .. tostring(i),
		category = "Fixture", variantSearchText = "detail:" .. tostring(i),
	})
end
local beforeOldestReload = resolveCalls
local evictionReloaded = GlobalStorageSiK.I18n.itemSearchHaystack(evictionRow)
assert(evictionReloaded == evictionHaystack,
	"evicted search key changed its result after recomputation")
assert(resolveCalls == beforeOldestReload + 1,
	"oldest key was not evicted/recomputed after exceeding 4096 entries")

print("item_search_detail_regression: OK rows=" .. tostring(#rows))
