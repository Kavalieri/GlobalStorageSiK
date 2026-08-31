-- An expanded group is a visual projection only. Dragging its header must
-- resolve exactly the same complete set of physical instances as a collapsed
-- header, irrespective of how many detail pages happen to be displayed.

for _, name in ipairs({
	"ISUI/ISPanel", "ISUI/ISButton", "ISUI/ISLabel", "ISUI/ISComboBox", "ISUI/ISScrollingListBox",
	"ISUI/ISContextMenu", "GS_CatalogManager", "GS_I18n", "GS_ItemSnapshot", "GS_NativeProduct",
	"GS_CategoryResolution", "GS_Libs", "GS_BulkFilters", "GS_DepositSources", "GS_WithdrawClient", "GS_TerminalWithdrawDrag",
	"GS_WithdrawMenu", "GS_QuantityPrompt", "GS_Log", "GS_ContextMenuUi", "GS_NodeHighlight",
	"GS_ContainerTargets", "GS_TerminalUI_Scroll", "GS_SiK_UI_Table", "GS_SiK_UI_Core",
	"GS_ItemNetworkTooltip", "GS_NetworkReadAction", "GS_NetClient", "GS_RemoteItemDetail", "GS_UIDebug",
}) do package.loaded[name] = true end

getTextManager = function() return { getFontHeight = function() return 12 end } end
UIFont = { Small = "small", Medium = "medium" }
ISPanel = { new = function() return {} end }
ISButton = { new = function() return {} end }
ISLabel = { new = function() return {} end }
ISComboBox = { new = function() return {} end }
ISScrollingListBox = { new = function() return {} end }
ISContextMenu = {}

GlobalStorageSiK = {
	I18n = { text = function(key) return key end },
	SiK_UI = { Table = { metrics = function() return { rowHeight = 40, headerHeight = 28 } end } },
	TerminalUI = {},
	Log = { debug = function() end },
}
local requestedPages, sentRows = {}, nil
GlobalStorageSiK.NetClient = {
	sendCommand = function(command, args)
		assert(command == "getItemDetails", "unexpected request " .. tostring(command))
		requestedPages[#requestedPages + 1] = args.page
		return true
	end,
}
GlobalStorageSiK.WithdrawClient = {
	sendWithdrawBatch = function(rows)
		sentRows = rows
		return true
	end,
}
dofile("GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/GS_TerminalUI_Items.lua")

local parent = { rowKey = "Base.VHS_Retail", fullType = "Base.VHS_Retail", count = 34,
	expandable = true, aggregateAllowed = false, _gsRowKind = "parent" }
local displayed = { parent }
for i = 1, 15 do
	displayed[#displayed + 1] = { rowKey = "detail:" .. i, fullType = "Base.VHS_Retail", count = 1,
		_gsRowKind = "child", parentRowKey = parent.rowKey }
end
local expanded = GlobalStorageSiK.TerminalItems.buildDragState(
	{ _lastItems = displayed, _expandedKeys = { [parent.rowKey] = true } }, parent)
local collapsed = GlobalStorageSiK.TerminalItems.buildDragState(
	{ _lastItems = { parent }, _expandedKeys = {} }, parent)

assert(#expanded.payloadRows == 1 and expanded.payloadRows[1] == parent,
	"expanded header must send only the semantic parent")
assert(#collapsed.payloadRows == 1 and collapsed.payloadRows[1] == parent,
	"collapsed header must send the same semantic parent")
assert(#expanded.visualRows == 16, "ghost may show parent plus visible page only")
assert(#collapsed.visualRows == 1, "collapsed ghost must show only its header")

local terminal = { terminalState = { networkId = "net", inventoryRevision = 9 } }
GlobalStorageSiK.TerminalUI.instance = terminal
assert(GlobalStorageSiK.TerminalItems.deferExactWithdraw(terminal, { parent }, "player:main", "vhs"),
	"stateful header did not start exact resolution")
assert(#requestedPages == 1 and requestedPages[1] == 1, "first exact page was not requested")

local function details(page, firstId, count, hasNext)
	local items = {}
	for i = 0, count - 1 do
		items[#items + 1] = { rowKey = "detail:" .. tostring(firstId + i), fullType = parent.fullType,
			itemIds = { firstId + i }, count = 1, _gsRowKind = "child", parentRowKey = parent.rowKey }
	end
	GlobalStorageSiK.TerminalItems.onDetailsReceived({
		rowKey = parent.rowKey, networkId = "net", inventoryRevision = 9,
		page = page, hasNext = hasNext, items = items,
	}, true)
end

details(1, 1, 15, true)
assert(#requestedPages == 2 and requestedPages[2] == 2 and not sentRows,
	"first visual page was sent instead of resolving the next page")
details(2, 16, 15, true)
assert(#requestedPages == 3 and requestedPages[3] == 3 and not sentRows,
	"second visual page was sent instead of resolving the final page")
details(3, 31, 4, false)
assert(sentRows and #sentRows == 34, "header must yield all 34 physical IDs, not a visible page")
for i = 1, 34 do
	assert(sentRows[i].itemIds[1] == i, "exact ID missing or reordered at " .. tostring(i))
end
print("withdraw_paginated_parent_regression: OK")
