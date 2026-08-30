-- Author regression for Warehouse DragGhost semantics.
-- It executes the pure payload/visual split and checks the integration source;
-- no PZ UI manager, input loop or network transport is started.

local Support = dofile("tests/helpers/sik_ui_contract_support.lua")
local suite = Support.newSuite("sik_ui_drag_ghost_contract")

local CLIENT = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/"
local function read(path)
	local file = assert(io.open(path, "rb"), path)
	local text = file:read("*a")
	file:close()
	return text
end

local function contains(text, needle, label)
	assert(text:find(needle, 1, true), label or ("missing " .. needle))
end

local function excludes(text, needle, label)
	assert(not text:find(needle, 1, true), label or ("unexpected " .. needle))
end

local itemsSource = read(CLIENT .. "GS_TerminalUI_Items.lua")
local dragSource = read(CLIENT .. "GS_TerminalWithdrawDrag.lua")

Support.check(suite, "source row and DragGhost share one descriptor renderer", function()
	contains(itemsSource, "function GlobalStorageSiK.TerminalItems.describeRow",
		"shared row descriptor missing")
	contains(itemsSource, "function GlobalStorageSiK.TerminalItems.drawRowDescriptor",
		"shared row renderer missing")
	contains(dragSource, "items.describeRow", "DragGhost bypasses row descriptor")
	contains(dragSource, "items.drawRowDescriptor", "DragGhost bypasses row renderer")
	return true
end)

Support.check(suite, "drag integration keeps visual and payload rows separate", function()
	contains(itemsSource, "TerminalItems.buildDragState", "semantic drag builder missing")
	contains(itemsSource, "dragState.payloadRows, dragState.visualRows, self",
		"begin does not receive the exact semantic and visual sets")
	contains(dragSource, "payloadRows", "drag state omits semantic payload")
	contains(dragSource, "visualRows", "drag state omits ghost rows")
	contains(dragSource, "finishAtPointer", "drop completion is not event-driven")
	return true
end)

Support.check(suite, "drag has no polling sync or global monkey patch route", function()
	excludes(dragSource, "Events.OnTick", "DragGhost installs permanent polling")
	excludes(dragSource, "requestSync", "preview/drop forces inventory sync")
	excludes(dragSource, "ISInventoryPane.onMouseUp =", "drag monkey-patches vanilla globally")
	return true
end)

Support.check(suite, "Escape drop and cancel all converge on transient cleanup", function()
	contains(dragSource, "EscapeStack", "Escape does not own the transient layer")
	contains(dragSource, "TerminalWithdrawDrag.cancel()", "Escape/cancel callback missing")
	contains(dragSource, "destroyPreview", "preview cleanup missing")
	contains(dragSource, "activeDrag = nil", "semantic payload cleanup missing")
	contains(dragSource, "finishAtPointer", "drop cleanup entry point missing")
	return true
end)

-- Load the public pure builder with the same lightweight sentinels used by
-- other author regressions. No widget is instantiated by these calls.
for _, name in ipairs({
	"ISUI/ISPanel", "ISUI/ISLabel", "ISUI/ISContextMenu", "GS_Libs", "GS_BulkFilters",
	"GS_CatalogManager", "GS_I18n", "GS_NativeProduct", "GS_CategoryResolution",
	"GS_DepositSources", "GS_TerminalWithdrawDrag", "GS_WithdrawMenu", "GS_QuantityPrompt",
	"GS_Log", "GS_ContextMenuUi", "GS_NodeHighlight", "GS_ContainerTargets",
	"GS_TerminalUI_Scroll", "GS_SiK_UI_Table", "GS_SiK_UI_Core", "GS_ItemNetworkTooltip",
	"GS_NetworkReadAction", "GS_NetClient", "GS_RemoteItemDetail",
}) do
	package.loaded[name] = true
end
UIFont = { Small = "Small" }
function getTextManager()
	return { getFontHeight = function() return 12 end,
		MeasureStringX = function(_, _, value) return #tostring(value or "") * 6 end }
end
GlobalStorageSiK = {
	CatalogManager = {
		createEpochCache = function() return {} end,
	},
	I18n = {
		text = function(key) return key end,
	},
	NativeProduct = {},
	CategoryResolution = {},
	SiK_UI = {
		Table = { metrics = function() return { rowHeight = 24, headerHeight = 24 } end },
		truncateText = function(value) return value end,
	},
	TerminalWithdrawDrag = { isActive = function() return false end },
}
dofile(CLIENT .. "GS_TerminalUI_Items.lua")

local build = GlobalStorageSiK.TerminalItems.buildDragState

local parent = { rowKey = "parent", fullType = "Base.VHSTape", _gsRowKind = "parent",
	expandable = true, aggregateAllowed = true, count = 3 }
local childA = { rowKey = "child-a", fullType = "Base.VHSTape", _gsRowKind = "child",
	parentRowKey = "parent", itemId = 101, aggregateAllowed = false, count = 2 }
local childB = { rowKey = "child-b", fullType = "Base.VHSTape", _gsRowKind = "child",
	parentRowKey = "parent", itemId = 202, aggregateAllowed = false, count = 1 }
local exact = { rowKey = "exact", fullType = "Base.Hammer", _gsRowKind = "parent",
	aggregateAllowed = true, count = 4 }
local panel = { _lastItems = { parent, childA, childB, exact }, _expandedKeys = {} }

Support.check(suite, "collapsed parent has one visible header and one aggregate payload", function()
	panel._expandedKeys.parent = nil
	local state = build(panel, parent)
	assert(#state.visualRows == 1 and state.visualRows[1] == parent, "collapsed ghost shape")
	assert(#state.payloadRows == 1 and state.payloadRows[1] == parent, "collapsed payload")
	return true
end)

Support.check(suite, "expanded parent shows children but sends one aggregate payload", function()
	panel._expandedKeys.parent = true
	local state = build(panel, parent)
	assert(#state.visualRows == 3, "expanded ghost omitted visible children")
	assert(state.visualRows[1] == parent and state.visualRows[2] == childA
		and state.visualRows[3] == childB, "expanded ghost order")
	assert(#state.payloadRows == 1 and state.payloadRows[1] == parent,
		"expanded parent duplicated child payloads")
	return true
end)

Support.check(suite, "exact child remains one exact child payload", function()
	local state = build(panel, childA)
	assert(#state.visualRows == 1 and state.visualRows[1] == childA, "child ghost")
	assert(#state.payloadRows == 1 and state.payloadRows[1] == childA, "child payload")
	return true
end)

Support.check(suite, "multiselect dedupes parent child overlap without mutating selection", function()
	local selection = { parent, childA, exact, exact }
	local before = #selection
	local state = build(panel, parent, selection)
	assert(#selection == before, "builder mutated caller selection")
	assert(#state.payloadRows == 2 and state.payloadRows[1] == parent
		and state.payloadRows[2] == exact, "parent/child or duplicate payload leaked")
	assert(#state.visualRows == 4, "selected expanded block plus exact row not represented")
	return true
end)

Support.finish(suite)
