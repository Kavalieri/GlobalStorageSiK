-- Authorial regression for the Warehouse initial/loading lifecycle.
-- Run from GlobalStorageSiK-Repo with Lua 5.1.

local ROOT = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/"

local function read(path)
	local handle = assert(io.open(path, "rb"), "cannot read " .. path)
	local source = handle:read("*a")
	handle:close()
	return source
end

local itemsSource = read(ROOT .. "GS_TerminalUI_Items.lua")
local terminalSource = read(ROOT .. "GS_TerminalUI.lua")
local syncSource = read(ROOT .. "GS_TerminalSync.lua")
local clientSource = read(ROOT .. "GS_Client.lua")
local apiSource = read(ROOT .. "GS_TerminalUI_Api.lua")

-- Load the real Warehouse presentation function with only engine/framework
-- leaves stubbed.  Empty input deliberately avoids inventing item semantics.
local originalRequire = require
function require(name)
	if name == "GS_UI_Framework" then
		return {
			Table = { metrics = function() return { rowHeight = 40, headerHeight = 32 } end },
			Tooltip = {}, Controls = {}, Block = {}, Scroll = {},
		}
	end
	if name == "GlobalStorageSiK/UI/Generated/TabWarehouse" then return { surface = {} } end
	if name == "GlobalStorageSiK/UI/TabWarehouseContext" then return {} end
	return true
end

GlobalStorageSiK = {
	I18n = { text = function(key) return key end },
	CatalogManager = { createEpochCache = function() return {} end },
	NativeProduct = {}, RecordedMedia = {}, CategoryResolution = {},
	TerminalWithdrawDrag = {}, WithdrawMenu = {}, QuantityPrompt = {}, Log = {},
	ContextMenuUi = {}, NodeHighlight = {}, ContainerTargets = {},
	ItemNetworkTooltip = {}, NetworkReadAction = {}, NetClient = {},
	RemoteItemDetail = {}, UIDebug = {}, Client = {},
}
UIFont = { Small = 1 }
function getTextManager()
	return { getFontHeight = function() return 16 end }
end

dofile(ROOT .. "GS_TerminalUI_Items.lua")
require = originalRequire

local panel = { _expandedKeys = {} }
local function model(state, filtered)
	panel._lastItems, panel._lastItemRoots = nil, nil
	return assert(GlobalStorageSiK.TerminalItems.presentationModel(
		panel, { playerNum = 0, terminalState = state }, filtered or {}))
end

assert(model(nil).emptyText == "",
	"missing snapshot duplicated the shell-owned scan status inside Warehouse")
assert(model({ scanActive = true }).emptyText == "",
	"active scan duplicated the shell-owned scan status inside Warehouse")
assert(model({ items = {}, scanStatus = { state = "RUNNING" } }).emptyText == "",
	"RUNNING provisional table duplicated the shell-owned scan status")
assert(itemsSource:find("Scan progress has one canonical, permanently visible owner: the shell", 1, true),
	"Warehouse no longer documents the single scan-status owner")
assert(model({ items = {}, scanActive = false,
	scanStatus = { state = "COMPLETED" } }).emptyText == "IGUI_GS_NoItems",
	"completed authoritative empty snapshot did not become the real empty state")
assert(model({ items = { { rowKey = "server-row" } }, scanActive = false,
	scanStatus = { state = "COMPLETED" } }, {}).emptyText == "IGUI_GS_NoFilterMatches",
	"post-snapshot filtered empty state was not distinguished from inventory empty")

assert(itemsSource:find('sortKey%s*=%s*panel%.itemsSortKey%s*or%s*"category"'),
	"Warehouse creation must expose category as the untouched default sort")
assert(itemsSource:find('panel%.itemsSortKey%s*=%s*panel%.itemsSortKey%s*or%s*"category"'),
	"Warehouse refresh must preserve category as the untouched default sort")
assert(not itemsSource:find('itemsSortKey%s*=%s*panel%.itemsSortKey%s*or%s*"name"'),
	"Warehouse silently restored the legacy name sort")

-- Completion is pushed into the already-open shell.  It must refresh the
-- active Warehouse and update its single surface, never require close/reopen.
local refreshFunction = assert(terminalSource:match(
	"function GS_TerminalUI:refreshFromState%(state%)(.-)\nend"),
	"refreshFromState function missing")
assert(refreshFunction:find("self.terminalState = state or prev", 1, true),
	"fresh terminalState is not committed before rendering")
assert(refreshFunction:find('if tab == "items" and inventoryChanged and not builtNow then', 1, true)
	and refreshFunction:find("self:refreshItemsTab()", 1, true),
	"changed authoritative Warehouse state is not refreshed in the existing surface")
assert(itemsSource:find("local updated, updateReason = surface:refresh(snapshot)", 1, true),
	"Warehouse refresh does not update the existing declarative surface")
assert(not itemsSource:find("function GlobalStorageSiK.TerminalItems.refreshSection", 1, true)
	or itemsSource:find("if not surface then", 1, true),
	"Warehouse refreshSection contract missing")

local onState = assert(syncSource:match(
	"function GlobalStorageSiK.TerminalSync.onTerminalState%(state, inventorySync%)(.-)\nend"),
	"TerminalSync.onTerminalState missing")
assert(onState:find("return false", 1, true),
	"accepted terminalState no longer permits the caller to refresh the live UI")
assert(clientSource:find("deferVisibleRefresh = GlobalStorageSiK.TerminalSync.onTerminalState(args, inventorySync) == true", 1, true),
	"client does not honor the terminal-state defer contract")
assert(clientSource:find("elseif uiVisible then", 1, true)
	and clientSource:find("GlobalStorageSiK.TerminalUI.show(args)", 1, true),
	"accepted terminalState is not sent to the already-visible terminal")
assert(apiSource:find("if ui then", 1, true)
	and apiSource:find("applyTerminalState(ui, state)", 1, true)
	and apiSource:find("pcall(ui.refreshFromState, ui, pendingState)", 1, true),
	"TerminalUI.show does not reuse and refresh its existing instance")
local showReuseStart = assert(apiSource:find("if ui then", 1, true))
local showReuseEnd = assert(apiSource:find("return", showReuseStart, true))
local reuseBranch = apiSource:sub(showReuseStart, showReuseEnd)
for _, forbidden in ipairs({ "onClose()", ":onClose()", "removeFromUIManager()", "GS_TerminalUI:new" }) do
	assert(not reuseBranch:find(forbidden, 1, true),
		"terminalState live refresh recreates/closes the terminal via " .. forbidden)
end

print("warehouse_initial_snapshot_contract: OK loading, empty, filtered, live refresh")
