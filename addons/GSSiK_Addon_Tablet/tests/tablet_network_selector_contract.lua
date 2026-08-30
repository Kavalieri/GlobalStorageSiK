-- Author contract for the remote-network selector consumer.
-- Pure Lua 5.1. Missing product is BLOCKED, never a false PASS.

local selectorPath = "Contents/mods/GSSiK_Addon_Tablet/42/media/lua/client/"
	.. "GSSiK_Addon_Tablet_NetworkSelector.lua"
local clientPath = "Contents/mods/GSSiK_Addon_Tablet/42/media/lua/client/"
	.. "GSSiK_Addon_Tablet_Client.lua"

local function read(path)
	local handle = io.open(path, "rb")
	if not handle then return nil end
	local source = handle:read("*a")
	handle:close()
	return source
end

local source = read(selectorPath)
if not source then
	local message = "tablet_network_selector_contract: BLOCKED product module not implemented: " .. selectorPath
	print(message)
	error(message, 0)
end

local function contains(text, needle, message)
	assert(text:find(needle, 1, true), message .. ": " .. needle)
end

local function occurrenceCount(text, needle)
	local count, start = 0, 1
	while true do
		local found = text:find(needle, start, true)
		if not found then return count end
		count = count + 1
		start = found + #needle
	end
end

-- Public Core surface only: the addon may consume TerminalUI, ItemActions and
-- SiK UI. It must not reach server/client internals or create network commands.
contains(source, "GlobalStorageSiK.TerminalUI.requestRemoteNetworks",
	"selector bypasses the public candidate API")
contains(source, "GlobalStorageSiK.TerminalUI.requestOpenNetwork",
	"selector bypasses the public remote-open API")
contains(source, "GlobalStorageSiK.TerminalUI.cancelRemoteNetworkRequest",
	"selector does not cancel its public request")
assert(occurrenceCount(source, "requestRemoteNetworks(") == 1,
	"selector owns more than one remote candidate request path")
for _, forbidden in ipairs({
	"sendCommand(", "sendNetworkCommand(", "GS_Server", "GS_Client",
	"Events.OnTick", "Events.OnKey", "Events.OnKeyPressed", "Events.OnKeyReleased",
}) do
	assert(not source:find(forbidden, 1, true),
		"selector uses forbidden internal/global route: " .. forbidden)
end

for _, state in ipairs({ "loading", "available", "empty", "error" }) do
	contains(source, '"' .. state .. '"', "selector omits state")
end
for _, symbol in ipairs({ "show", "selectNetwork", "confirmSelection", "close" }) do
	contains(source, symbol, "selector lacks behavioral surface")
end
assert(source:find("SiK_UI.Modal", 1, true) or source:find("Modal.create", 1, true),
	"selector does not use the shared modal layer")
assert(source:find("EscapeStack.PRIORITY.MODAL", 1, true)
	or source:find("Modal.apply", 1, true) or source:find("Modal.create", 1, true),
	"selector has no modal-priority Escape route")

local clientSource = assert(read(clientPath), "cannot read Tablet client registration")
assert(occurrenceCount(clientSource, "registerTabletItem(") == 4,
	"the four tablet fullTypes are not registered exactly once")
assert(occurrenceCount(clientSource, "NetworkSelector.onUseTablet") == 4,
	"the four tablet fullTypes do not share the selector callback")

-- Behavioral load with neutral mocks. The returned panel is deliberately the
-- controller too: state and actions remain observable without rendering PZ.
for _, name in ipairs({
	"GSSiK_Addon_Tablet_Register", "GSSiK_Addon_Tablet_Access",
	"GSSiK_Addon_Tablet_Log", "GS_TerminalUI_Api", "GS_ItemActions",
	"GS_PlayerUtils", "GS_I18n", "GS_SiK_UI_Modal", "GS_SiK_UI_Controls",
	"GS_SiK_UI_EscapeStack", "ISUI/ISPanel", "ISUI/ISLabel",
	"ISUI/ISButton", "ISUI/ISScrollingListBox",
}) do
	package.loaded[name] = true
end

local requestCount, nextRequestId = 0, 100
local callbacks, cancelled, opens = {}, {}, {}
local function player(number)
	return { getPlayerNum = function() return number end }
end

local function panel()
	local value = { visible = false, removed = false, children = {}, width = 460, height = 260 }
	function value:addChild(child) self.children[#self.children + 1] = child end
	function value:addToUIManager() self.visible = true end
	function value:removeFromUIManager() self.visible = false; self.removed = true end
	function value:setVisible(visible) self.visible = visible == true end
	function value:getIsVisible() return self.visible end
	function value:getWidth() return self.width end
	function value:getHeight() return self.height end
	return value
end

local function control()
	local value = { enabled = true, items = {}, selected = 0 }
	function value:setEnable(enabled) self.enabled = enabled == true end
	function value:setVisible() end
	function value:clear() self.items = {} end
	function value:addItem(label, data) self.items[#self.items + 1] = { text = label, item = data } end
	return value
end

GSSiK_Addon_Tablet = {
	ITEM_TABLET = "GSSiK_Addon_Tablet.GS_Tablet",
	ITEM_TABLET_CRAFT = "GSSiK_Addon_Tablet.GS_TabletCraft",
	ITEM_TABLET_BUILDER = "GSSiK_Addon_Tablet.GS_TabletBuilder",
	ITEM_TABLET_MASTER = "GSSiK_Addon_Tablet.GS_TabletMaster",
	Log = { debug = function() end },
}
GlobalStorageSiK = {
	I18n = { text = function(key) return key end },
	PlayerUtils = { resolve = function(value) return value end },
	ItemActions = { registerTabletItem = function() end },
	TerminalUI = {
		requestRemoteNetworks = function(callback, playerArg)
			requestCount = requestCount + 1
			nextRequestId = nextRequestId + 1
			callbacks[nextRequestId] = { callback = callback, player = playerArg }
			return nextRequestId
		end,
		cancelRemoteNetworkRequest = function(requestId, playerArg)
			cancelled[#cancelled + 1] = { requestId = requestId, player = playerArg }
		end,
		requestOpenNetwork = function(networkId, playerArg)
			opens[#opens + 1] = { networkId = networkId, player = playerArg }
			return true
		end,
	},
	SiK_UI = {
		EscapeStack = { PRIORITY = { MODAL = 300 } },
		Controls = {
			metrics = function() return { buttonHeight = 34, rowGap = 8, controlGap = 8 } end,
			button = function() return control() end,
		},
		Modal = {
			create = function(options)
				local value = panel()
				value._contractOptions = options
				if options and options.buildContent then
					options.buildContent(value, { x = 0, y = 0, w = 420, h = 200 }, value)
				end
				return value, { x = 0, y = 0, w = 460, h = 260, playerNum = options.playerNum or 0 }
			end,
			show = function(value) value:addToUIManager(); return value end,
			close = function(value) value:removeFromUIManager() end,
			apply = function(value) return value end,
		},
	},
}

ISPanel = { new = function() return panel() end }
ISLabel = { new = function() return control() end }
ISButton = { new = function() return control() end }
ISScrollingListBox = { new = function() return control() end }
UIFont = { Small = 1, Medium = 2 }
getText = function(key) return key end

dofile(selectorPath)
local Selector = assert(GSSiK_Addon_Tablet.NetworkSelector, "selector namespace not exported")
assert(type(Selector.show) == "function", "selector show is not public")

local p0 = player(0)
local blocked = assert(Selector.show(p0), "show did not return selector instance")
assert(requestCount == 1, "show did not issue exactly one candidate request")
assert(blocked.state == "loading", "initial state is not loading")
local blockedRequestId = assert(blocked.requestId, "selector did not retain requestId")
callbacks[blockedRequestId].callback({
	{
		networkId = "net-blocked",
		name = "Out of range",
		selectable = false,
		reason = "antenna_out_of_range",
	},
	{ networkId = "net-a", name = "Alpha" },
}, nil)
assert(blocked.state == "available", "mixed response did not enter available state")
assert(#blocked.networks == 2, "non-selectable candidate was hidden from the selector")
local blockedCandidate = nil
for _, candidate in ipairs(blocked.networks) do
	if candidate.networkId == "net-blocked" then blockedCandidate = candidate end
end
assert(blockedCandidate and blockedCandidate.selectable == false
	and blockedCandidate.reason == "antenna_out_of_range",
	"non-selectable candidate lost its visible reason")
assert(blocked:selectNetwork("net-blocked") == false,
	"out-of-range candidate became selectable")
blocked.selectedNetworkId = "net-blocked"
assert(blocked:confirmSelection() == false and #opens == 0,
	"forced blocked selection opened a remote network")
assert(blocked:selectNetwork("missing") == false, "unavailable network became selectable")
assert(blocked:selectNetwork("net-a") == true, "available network could not be selected")
assert(blocked:confirmSelection() == true, "available selection could not open")
assert(#opens == 1 and opens[1].networkId == "net-a"
	and opens[1].player:getPlayerNum() == 0,
	"open lost exact networkId or playerNum")

local sanitized = assert(Selector.show(p0), "sanitizing selector show failed")
local oversizedId = string.rep("x", 129)
callbacks[sanitized.requestId].callback({
	{ networkId = "net-safe", name = "First" },
	{ networkId = "net-safe", name = "Duplicate" },
	{ networkId = "", name = "Empty" },
	{ networkId = oversizedId, name = "Oversized" },
}, nil)
assert(sanitized.state == "available", "valid candidate was lost during sanitizing")
assert(#sanitized.networks == 1 and sanitized.networks[1].networkId == "net-safe",
	"candidate IDs were not deduplicated and bounded")

local p1 = player(1)
local playerZeroPending = assert(Selector.show(p0), "player zero pending selector failed")
local playerZeroRequestId = assert(playerZeroPending.requestId)
local playerOnePending = assert(Selector.show(p1), "player one selector failed")
local playerOneRequestId = assert(playerOnePending.requestId)
assert(playerZeroPending.closed ~= true and playerZeroPending:getIsVisible(),
	"opening player one's selector closed player zero's singleton")
assert(playerOnePending.closed ~= true and playerOnePending:getIsVisible(),
	"player one selector was not independently visible")

playerZeroPending:close()
assert(cancelled[#cancelled].requestId == playerZeroRequestId
	and cancelled[#cancelled].player:getPlayerNum() == 0,
	"close did not cancel player zero's exact request")
assert(playerOnePending.closed ~= true and playerOnePending:getIsVisible(),
	"closing player zero's selector affected player one")
local closedState = playerZeroPending.state
callbacks[playerZeroRequestId].callback({ { networkId = "late-p0", name = "Late" } }, nil)
assert(playerZeroPending.state == closedState and playerZeroPending.selectedNetworkId == nil,
	"late callback mutated player zero's closed selector")
assert(playerOnePending.state == "loading",
	"player zero's late callback mutated player one's selector")
callbacks[playerOneRequestId].callback({ { networkId = "net-p1", name = "Player one" } }, nil)
assert(playerOnePending.state == "available"
	and playerOnePending.selectedNetworkId == "net-p1",
	"player one's live callback was lost after player zero closed")

local late = assert(Selector.show(p1), "same-player replacement failed")
assert(playerOnePending.closed == true and not playerOnePending:getIsVisible(),
	"same-player singleton was not replaced")
local lateRequestId = assert(late.requestId)
late:close()
assert(cancelled[#cancelled].requestId == lateRequestId
	and cancelled[#cancelled].player:getPlayerNum() == 1,
	"close did not cancel the exact player's request")
closedState = late.state
callbacks[lateRequestId].callback({ { networkId = "late", name = "Late" } }, nil)
assert(late.state == closedState and late.selectedNetworkId == nil,
	"late callback mutated a closed selector")

local empty = assert(Selector.show(p0))
callbacks[empty.requestId].callback({}, nil)
assert(empty.state == "empty", "empty response did not enter empty state")
assert(empty:confirmSelection() == false, "empty selector opened a network")

local failed = assert(Selector.show(p0))
callbacks[failed.requestId].callback({}, "rate_limited")
assert(failed.state == "error", "error response did not enter error state")
assert(failed:confirmSelection() == false, "error selector opened a network")

print("tablet_network_selector_contract: OK")
