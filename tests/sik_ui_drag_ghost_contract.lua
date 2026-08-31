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

local function countPlain(text, needle)
        local count, cursor = 0, 1
        while true do
                local at = text:find(needle, cursor, true)
                if not at then return count end
                count = count + 1
                cursor = at + #needle
        end
end

local itemsSource = read(CLIENT .. "GS_TerminalUI_Items.lua")
local dragSource = read(CLIENT .. "GS_TerminalWithdrawDrag.lua")
local truncateStart = assert(dragSource:find("local function truncateMeasured", 1, true),
	"shared preview truncator adapter missing")
local truncateEnd = assert(dragSource:find("function GSWithdrawDragPreviewRow:prerender", truncateStart, true),
	"shared preview truncator adapter boundary missing")
local truncateSource = dragSource:sub(truncateStart, truncateEnd - 1)
local previewStart = assert(dragSource:find("local function createPreview", 1, true),
	"compact preview constructor missing")
local previewEnd = assert(dragSource:find("local function expandInventoryPages", previewStart, true),
	"compact preview constructor boundary missing")
local previewSource = dragSource:sub(previewStart, previewEnd - 1)

Support.check(suite, "DragGhost is a compact row stack rather than a copied table", function()
	contains(dragSource, "local PREVIEW_MIN_W = 180", "compact minimum width missing")
	contains(dragSource, "local PREVIEW_MAX_W = 300", "compact maximum width missing")
	contains(dragSource, "local PREVIEW_MAX_ROWS =", "compact stack has no bounded row count")
	contains(previewSource, "items.rowHeight", "preview does not consume canonical ROW_H")
	contains(dragSource, "truncateMeasured", "long preview names are not truncated")
	contains(dragSource, "local PREVIEW_ALPHA = 0.78", "light preview alpha missing")
	excludes(previewSource, "drawRowDescriptor", "preview still copies the Warehouse row renderer")
	excludes(previewSource, "sourceWidget.width", "preview width still depends on its source window")
	contains(previewSource, "#visualRows * rowH", "preview height does not preserve visual rows")
	contains(previewSource, "for i = 1, #visualRows do", "preview does not render every visual row")
	contains(dragSource, "descriptor.texture", "compact row omits the item icon")
	contains(dragSource, "descriptor.name", "compact row omits the item name")
	contains(dragSource, "descriptor.count", "compact row omits its own quantity")
	contains(dragSource, "descriptor.indicator", "compact row omits group/expanded state")
	contains(dragSource, "IGUI_GS_DragMoreObjects", "overflow has no localized +N objects label")
	excludes(previewSource, "selectionCount", "stack replaces row quantities with one selection summary")
	excludes(previewSource, ".category", "preview leaks the Category column")
	excludes(previewSource, ".zone", "preview leaks the Zone column")
	return true
end)

Support.check(suite, "preview truncates through the shared UTF-safe SiK UI helper", function()
	contains(truncateSource, "GlobalStorageSiK.SiK_UI.truncateText",
		"preview does not delegate truncation to the shared UTF-safe helper")
	contains(dragSource, "truncateMeasured(descriptor.name, textW)",
		"preview name bypasses the shared truncator adapter")
	excludes(truncateSource, "string.sub", "preview defines a local byte truncator")
	excludes(truncateSource, ":sub(", "preview defines a local byte truncator")
	excludes(truncateSource, "while ", "preview defines a local truncation loop")
	excludes(truncateSource, "for ", "preview defines a local truncation loop")
	return true
end)

Support.check(suite, "drag integration keeps compact visuals and exact semantic payload separate", function()
	contains(itemsSource, "TerminalItems.buildDragState", "semantic drag builder missing")
	contains(itemsSource, "dragState.payloadRows, dragState.visualRows, self",
		"begin does not receive the exact semantic and visual sets")
	contains(dragSource, "payloadRows", "drag state omits semantic payload")
	contains(previewSource, "activeDrag.visualRows", "preview drops expanded or selected visual rows")
	assert(select(2, previewSource:gsub("GSWithdrawDragPreviewRow:new", "")) == 1,
		"preview row constructor is duplicated instead of reused in one loop")
	contains(dragSource, "finishAtPointer", "drop completion is not event-driven")
	return true
end)

Support.check(suite, "terminal owns capture exactly once and every finalization releases it", function()
        contains(dragSource, "local captureOwner = sourceWidget and sourceWidget.terminal or nil",
                "capture owner is not the source row terminal")
        contains(dragSource, "captureOwner = captureOwner", "active drag loses its capture owner")
        contains(dragSource, "captureOwner:setCapture(true)", "terminal never captures mouse-up")
        excludes(dragSource, "sourceWidget:setCapture(true)", "child row captures instead of terminal")
        contains(dragSource, "function GlobalStorageSiK.TerminalWithdrawDrag.finishAtPointer",
                "single finalization entry point missing")
        contains(dragSource, "activeDrag and activeDrag.captureOwner or nil",
                "cancel does not read the exact active capture owner")
        contains(dragSource, "captureOwner:setCapture(false)",
                "cancel/drop does not release terminal capture")
        return true
end)

Support.check(suite, "drag logging is event-only and has no move or frame noise", function()
        assert(countPlain(dragSource, "GlobalStorageSiK.Log.") == 3,
                "drag has logs outside the three allowed lifecycle events")
        contains(dragSource, '"dragDropAttempt"', "drop attempt log missing")
        contains(dragSource, '"dragDropSent"', "drop sent log missing")
        contains(dragSource, '"dragCancelled reason="', "cancel reason log missing")
        excludes(dragSource, "print(", "drag emits an unstructured print")
        local moveStart = assert(dragSource:find(
                "function GlobalStorageSiK.TerminalWithdrawDrag.moveToPointer", 1, true),
                "moveToPointer missing")
        local moveEnd = assert(dragSource:find(
                "local function clearDrag", moveStart, true), "moveToPointer boundary missing")
        excludes(dragSource:sub(moveStart, moveEnd - 1), "GlobalStorageSiK.Log.",
                "pointer movement logs per event/frame")
        return true
end)

Support.check(suite, "warehouse expander owns a 32 pixel click target", function()
        contains(itemsSource, "local EXPANDER_HITBOX_W = 32", "expander target is not canonical")
        contains(itemsSource, "x <= EXPANDER_HITBOX_W", "row click bypasses expander target")
        excludes(itemsSource, "x <= 20", "legacy 20 pixel expander target remains")
        return true
end)

Support.check(suite, "drag has no polling sync or global monkey patch route", function()
	excludes(dragSource, "Events.OnTick", "DragGhost installs permanent polling")
	excludes(dragSource, "requestSync", "preview/drop forces inventory sync")
	excludes(dragSource, "ISInventoryPane.onMouseUp =", "drag monkey-patches vanilla globally")
	return true
end)

Support.check(suite, "preview placement uses the real pointer and never becomes the drop target", function()
	contains(dragSource, "getMouseX", "preview does not follow the real horizontal pointer")
	contains(dragSource, "getMouseY", "preview does not follow the real vertical pointer")
	contains(dragSource, "findPaneAtMouse(true, player, activeDrag.playerNum)",
		"drop does not resolve the real pointer target in its captured viewport")
	contains(dragSource, "setConsumeMouseEvents(false)", "preview consumes vanilla pane mouse events")
	return true
end)

Support.check(suite, "sent drags release their visual state and group headers remain draggable", function()
	contains(dragSource, "clearDrag(nil)", "valid drop does not clear capture and preview before send")
	local dragStart = assert(itemsSource:find("row.onMouseMove = function", 1, true),
		"row drag handler missing")
	local dragEnd = assert(itemsSource:find("row.onMouseUpOutside = function", dragStart, true),
		"row drag handler boundary missing")
	excludes(itemsSource:sub(dragStart, dragEnd - 1),
		"aggregateAllowed == false and not self.itemData.itemIds",
		"group header is excluded from drag before payload construction")
	return true
end)

Support.check(suite, "stateful group header resolves exact pages without using visual payload", function()
	contains(dragSource, "payloadRows or { drag.rowData }", "drop does not use semantic payload")
	contains(dragSource, "TerminalItems.deferExactWithdraw(terminal, rows, key, searchQuery)",
		"stateful header is not resolved to exact IDs before withdrawal")
	contains(itemsSource, "if args.hasNext then", "detail resolver stops at the first visual page")
	contains(itemsSource, "sendWithdrawBatch(", "resolved exact rows never reach the common batch client")
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
	"GS_CatalogManager", "GS_I18n", "GS_ItemSnapshot", "GS_NativeProduct", "GS_CategoryResolution",
	"GS_DepositSources", "GS_TerminalWithdrawDrag", "GS_WithdrawMenu", "GS_QuantityPrompt",
        "GS_Log", "GS_ContextMenuUi", "GS_NodeHighlight", "GS_ContainerTargets", "GS_UIDebug",
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

Support.check(suite, "collapsed parent sends one semantic header", function()
	panel._expandedKeys.parent = nil
	local state = build(panel, parent)
	assert(#state.visualRows == 1 and state.visualRows[1] == parent, "collapsed ghost shape")
	assert(#state.payloadRows == 1 and state.payloadRows[1] == parent, "collapsed payload")
	return true
end)

Support.check(suite, "expanded parent keeps visible children visual and transfers the complete parent", function()
	panel._expandedKeys.parent = true
	local state = build(panel, parent)
	assert(#state.visualRows == 3, "expanded ghost omitted visible children")
	assert(state.visualRows[1] == parent and state.visualRows[2] == childA
		and state.visualRows[3] == childB, "expanded ghost order")
	assert(#state.payloadRows == 1 and state.payloadRows[1] == parent,
		"expanded parent payload was limited to visible paginated children")
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
		and state.payloadRows[2] == exact,
		"parent/child or duplicate payload leaked")
	assert(#state.visualRows == 4, "selected expanded block plus exact row not represented")
	return true
end)

Support.finish(suite)
