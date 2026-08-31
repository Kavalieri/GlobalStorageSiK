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
local requestedPages, sentBatches = {}, {}
GlobalStorageSiK.NetClient = {
	sendCommand = function(command, args)
		requestedPages[#requestedPages + 1] = { command = command, args = args }
		return false
	end,
}
GlobalStorageSiK.WithdrawClient = {
	sendWithdrawBatch = function(rows)
		sentBatches[#sentBatches + 1] = rows
		return true
	end,
}
dofile("GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/GS_TerminalUI_Items.lua")

local parent = { rowKey = "Base.VHS_Retail", fullType = "Base.VHS_Retail", count = 34,
	expandable = true, aggregateAllowed = false, _gsRowKind = "parent",
	selectionMode = "exact_group", selectionRevision = 9 }
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

assert(GlobalStorageSiK.WithdrawClient.sendWithdrawBatch(expanded.payloadRows),
	"expanded semantic header was not accepted")
assert(GlobalStorageSiK.WithdrawClient.sendWithdrawBatch(collapsed.payloadRows),
	"collapsed semantic header was not accepted")
assert(#sentBatches == 2, "both header states must reach the same withdraw boundary")
for i = 1, 2 do
	local row = sentBatches[i][1]
	assert(#sentBatches[i] == 1 and row == parent,
		"visual children must never become withdrawal payload")
	assert(row.selectionMode == "exact_group" and row.selectionRevision == 9,
		"semantic selector and captured revision must survive either visual state")
	assert(not row.itemIds or #row.itemIds == 0,
		"client pagination must not manufacture authoritative physical IDs")
end
assert(#requestedPages == 0,
	"dragging a semantic header must not request detail pages before withdrawal")
print("withdraw_paginated_parent_regression: OK")
