-- Author contract for the remote-network selector consumer.
-- Pure Lua 5.1. Product-boundary debt is an explicit FAIL, never a false PASS.

local selectorPath = "Contents/mods/GSSiK_Addon_Tablet/42/media/lua/client/"
	.. "GSSiK_Addon_Tablet_NetworkSelector.lua"
local clientPath = "Contents/mods/GSSiK_Addon_Tablet/42/media/lua/client/"
	.. "GSSiK_Addon_Tablet_Client.lua"
local addonLuaPaths = {
	selectorPath,
	clientPath,
	"Contents/mods/GSSiK_Addon_Tablet/42/media/lua/shared/GSSiK_Addon_Tablet_Log.lua",
	"Contents/mods/GSSiK_Addon_Tablet/42/media/lua/shared/GSSiK_Addon_Tablet_ItemHooks.lua",
	"Contents/mods/GSSiK_Addon_Tablet/42/media/lua/shared/GSSiK_Addon_Tablet_Access.lua",
	"Contents/mods/GSSiK_Addon_Tablet/42/media/lua/shared/GSSiK_Addon_Tablet_Sandbox.lua",
	"Contents/mods/GSSiK_Addon_Tablet/42/media/lua/shared/GSSiK_Addon_Tablet_Register.lua",
	"Contents/mods/GSSiK_Addon_Tablet/42/media/lua/shared/GSSiK_Addon_Tablet_RecipeTests.lua",
	"Contents/mods/GSSiK_Addon_Tablet/42/media/lua/server/GSSiK_Addon_Tablet_Server.lua",
	"Contents/mods/GSSiK_Addon_Tablet/42/media/lua/server/GSSiK_Addon_Tablet_Loot.lua",
}

local function read(path)
	local handle = io.open(path, "rb")
	if not handle then return nil end
	local source = handle:read("*a")
	handle:close()
	return source
end

local source = read(selectorPath)
if not source then
	local message = "tablet_network_selector_contract: BLOCKED product module not implemented: "
		.. selectorPath
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

contains(source, 'local ProductAPI = require "GSSiK_API_Client"',
	"selector bypasses the public product client API")
contains(source, 'local UI = require "SiK_UI"',
	"selector bypasses the public SiK.UI module")
for _, symbol in ipairs({
	"local RemoteAccess = ProductAPI.RemoteAccess",
	"local Modal = UI.Modal", "local Controls = UI.Controls", "local Block = UI.Block",
	"local Card = UI.Card", "local Scroll = UI.Scroll",
}) do
	contains(source, symbol, "selector omits public API primitive")
end
for _, symbol in ipairs({
	"RemoteAccess.list(", "RemoteAccess.open(", "RemoteAccess.registerCleanup(",
	"panel.requestHandle:dispose()", "panel.openRequestHandle:dispose()",
}) do
	contains(source, symbol, "selector omits public remote-access lifecycle")
end
for _, forbidden in ipairs({
	"GlobalStorageSiK", "GS_SiK_UI", "GS_UI_Framework", "TerminalScroll",
	"GS_TerminalUI", "GS_Client", "GS_PlayerUtils", "GS_I18n",
	"sendCommand(", "sendNetworkCommand(", "Events.OnTick", "Events.OnKey",
	"ISPanel:new", "drawRect(", "prerender = function",
}) do
	assert(not source:find(forbidden, 1, true),
		"selector retains private/local route: " .. forbidden)
end

for _, state in ipairs({ "loading", "available", "empty", "error" }) do
	contains(source, '"' .. state .. '"', "selector omits state")
end
for _, symbol in ipairs({ "show", "selectNetwork", "confirmSelection", "close" }) do
	contains(source, symbol, "selector lacks behavioral surface")
end
contains(source, "Modal.create", "selector does not use the shared modal layer")

local clientSource = assert(read(clientPath), "cannot read Tablet client registration")
assert(occurrenceCount(clientSource, "API.ItemActions.registerTablet({") == 1,
	"Tablet client does not use one shared public registration helper")
assert(occurrenceCount(clientSource, "NetworkSelector.onUseTablet") == 1,
	"Tablet client duplicates or bypasses the shared selector callback")
assert(occurrenceCount(clientSource,
	"registerTablet(GSSiK_Addon_Tablet.ITEM_TABLET") == 4,
	"the four tablet fullTypes are not registered exactly once through the helper")
assert(not clientSource:find("GlobalStorageSiK", 1, true),
	"Tablet client retains a private Core symbol")

-- Inventory all current private product accesses in the official addon. This
-- is asserted only after behavioral coverage so migration debt remains precise.
local privateProductAccesses = {}
for _, path in ipairs(addonLuaPaths) do
	local text = assert(read(path), "cannot inventory addon Lua: " .. path)
	local lineNumber = 0
	for line in (text .. "\n"):gmatch("(.-)\n") do
		lineNumber = lineNumber + 1
		if line:find("GlobalStorageSiK%.") then
			privateProductAccesses[#privateProductAccesses + 1] = path .. ":" .. lineNumber
		end
	end
end

-- Behavioral load with neutral public mocks. No GlobalStorageSiK namespace is
-- created: the selector must execute using only GSSiK.API and SiK.UI.
package.loaded["GSSiK_Addon_Tablet_Access"] = true

local listRequests, openRequests, cleanupRegistrations = {}, {}, {}
local nextRequestId = 100
local function requestHandle(kind, player, callback)
	nextRequestId = nextRequestId + 1
	local value = {
		id = nextRequestId, kind = kind, player = player, callback = callback,
		disposed = false, cancelled = false,
	}
	function value:cancel()
		if self.disposed or self.cancelled then return false end
		self.cancelled = true
		return true
	end
	function value:dispose()
		if self.disposed or self.cancelled then return false end
		self.disposed = true
		return true
	end
	return value
end

local RemoteAccess = {}
function RemoteAccess.list(player, callback)
	local handle = requestHandle("list", player, callback)
	listRequests[#listRequests + 1] = handle
	return true, "OK", handle
end
function RemoteAccess.open(networkId, player, callback)
	local handle = requestHandle("open", player, callback)
	handle.networkId = networkId
	openRequests[#openRequests + 1] = handle
	return true, "OK", handle
end
function RemoteAccess.registerCleanup(id, callback)
	local generation = #cleanupRegistrations + 1
	local value = { id = id, callback = callback, generation = generation, disposed = false }
	function value:dispose()
		if self.disposed then return false end
		self.disposed = true
		return true
	end
	cleanupRegistrations[#cleanupRegistrations + 1] = value
	return true, "OK", value
end

local ProductAPI = { RemoteAccess = RemoteAccess }
package.preload["GSSiK_API_Client"] = function() return ProductAPI end

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
	function value:setX(x) self.x = x end
	function value:setY(y) self.y = y end
	function value:setWidth(width) self.width = width end
	function value:setHeight(height) self.height = height end
	function value:dispose() self.disposed = true; return true end
	return value
end

local function control()
	local value = { enabled = true, items = {}, selected = 0, width = 100, height = 34 }
	function value:setEnable(enabled) self.enabled = enabled == true end
	function value:setVisible() end
	function value:clear() self.items = {} end
	function value:addItem(label, data) self.items[#self.items + 1] = { text = label, item = data } end
	function value:setX(x) self.x = x end
	function value:setY(y) self.y = y end
	function value:setWidth(width) self.width = width end
	function value:setHeight(height) self.height = height end
	function value:getWidth() return self.width end
	function value:reflow(width) self.width = width; return self end
	function value:dispose() self.disposed = true; return true end
	return value
end

local UI = {
	Controls = {
		metrics = function() return {
			buttonHeight = 34, rowGap = 8, controlGap = 8,
			rowHeight = 34, statusHeight = 24, sectionHeight = 34,
		} end,
		button = function() return control() end,
		feedback = function() local value = control(); value.height = 32; return value end,
		blockHeader = function() local value = control(); value.height = 34; return value end,
		listOption = function(_, options)
			local value = control(); value.payload = options and options.payload
			value.height = 34
			return value
		end,
	},
	Block = {
		create = function(options)
			local host = panel(); host.width = options.w or 100; host.height = options.h or 100
			local value = { panel = panel(), host = host, contentHeight = options.contentHeight or 0 }
			function value:getContentRect()
				return { x = 0, y = 0, w = self.host.width, h = self.host.height }
			end
			function value:getTrackRect() return nil end
			function value:setContentHeight(height) self.contentHeight = height end
			function value:attachScroll(scroll) self.scroll = scroll end
			function value:subscribe(callback) self.listener = callback end
			function value:dispose() self.disposed = true; return true end
			return value
		end,
	},
	Scroll = {
		create = function()
			local value = { host = panel(), offset = 0 }
			function value:getScrollOffset() return self.offset end
			function value:setScrollOffset(offset) self.offset = offset end
			function value:dispose() self.disposed = true; return true end
			return value
		end,
	},
	Card = {
		create = function(options)
			local value = { content = panel() }
			value.content.width = options.w or 100
			value.content.height = options.h or 100
			function value:dispose() self.disposed = true; return true end
			return value
		end,
	},
}

UI.Modal = {
	create = function(options)
		local value = panel()
		value._contractOptions = options
		value.close = function(self) return UI.Modal.close(self, "method") end
		if options and options.buildContent then
			options.buildContent(value, { x = 0, y = 0, w = 420, h = 200 }, value)
		end
		return value
	end,
	show = function(value) value:addToUIManager(); return value end,
	close = function(value)
		if value._contractOptions and value._contractOptions.onClose then
			value._contractOptions.onClose({ component = value })
		end
		value:removeFromUIManager()
		return true
	end,
	fitContent = function() return true end,
}

SiK = { UI = UI }
package.preload["SiK_UI"] = function() return SiK.UI end

GSSiK_Addon_Tablet = {
	ITEM_TABLET = "GSSiK_Addon_Tablet.GS_Tablet",
	ITEM_TABLET_CRAFT = "GSSiK_Addon_Tablet.GS_TabletCraft",
	ITEM_TABLET_BUILDER = "GSSiK_Addon_Tablet.GS_TabletBuilder",
	ITEM_TABLET_MASTER = "GSSiK_Addon_Tablet.GS_TabletMaster",
	Log = { debug = function() end },
}
getText = function(key) return key end

dofile(selectorPath)
local Selector = assert(GSSiK_Addon_Tablet.NetworkSelector, "selector namespace not exported")
assert(type(Selector.show) == "function", "selector show is not public")
assert(#cleanupRegistrations == 1
	and cleanupRegistrations[1].id == "TabletNetworkSelector",
	"selector did not register one public transient cleanup")

local p0 = player(0)
local blocked = assert(Selector.show(p0), "show did not return selector instance")
assert(#listRequests == 1, "show did not issue exactly one public list request")
assert(blocked.state == "loading" and blocked.requestHandle == listRequests[1],
	"initial loading state did not retain the public request handle")
listRequests[1].callback(true, "OK", {
	{ networkId = "net-blocked", name = "Out of range", selectable = false,
		reason = "antenna_out_of_range" },
	{ networkId = "net-a", name = "Alpha" },
})
assert(blocked.state == "available" and #blocked.networks == 2,
	"mixed response did not preserve visible candidates")
assert(blocked:selectNetwork("net-blocked") == false,
	"out-of-range candidate became selectable")
blocked.selectedNetworkId = "net-blocked"
assert(blocked:confirmSelection() == false and #openRequests == 0,
	"forced blocked selection opened a remote network")
assert(blocked:selectNetwork("net-a") == true, "available network could not be selected")
assert(blocked:confirmSelection() == true, "available selection could not open")
assert(#openRequests == 1 and openRequests[1].networkId == "net-a"
	and openRequests[1].player:getPlayerNum() == 0,
	"open lost exact networkId or playerNum")
openRequests[1].callback(true, "OK", { networkId = "net-a" })
assert(blocked.closed == true and not blocked:getIsVisible(),
	"accepted open did not close the selector")

local sanitized = assert(Selector.show(p0), "sanitizing selector show failed")
local oversizedId = string.rep("x", 129)
local sanitizeRequest = listRequests[#listRequests]
sanitizeRequest.callback(true, "OK", {
	{ networkId = "net-safe", name = "First" },
	{ networkId = "net-safe", name = "Duplicate" },
	{ networkId = "", name = "Empty" },
	{ networkId = oversizedId, name = "Oversized" },
})
assert(sanitized.state == "available" and #sanitized.networks == 1
	and sanitized.networks[1].networkId == "net-safe",
	"candidate IDs were not deduplicated and bounded")

local p1 = player(1)
local playerZeroPending = assert(Selector.show(p0), "player zero pending selector failed")
local playerZeroRequest = listRequests[#listRequests]
local playerOnePending = assert(Selector.show(p1), "player one selector failed")
local playerOneRequest = listRequests[#listRequests]
assert(playerZeroPending:getIsVisible() and playerOnePending:getIsVisible(),
	"per-player selector singleton was not isolated")
playerZeroPending:close()
assert(playerZeroRequest.disposed == true,
	"close did not dispose player zero's exact request handle")
local closedState = playerZeroPending.state
playerZeroRequest.callback(true, "OK", { { networkId = "late-p0", name = "Late" } })
assert(playerZeroPending.state == closedState and playerZeroPending.selectedNetworkId == nil,
	"late callback mutated a closed selector")
assert(playerOnePending.state == "loading", "late callback crossed player instances")
playerOneRequest.callback(true, "OK", { { networkId = "net-p1", name = "P1" } })
assert(playerOnePending.state == "available"
	and playerOnePending.selectedNetworkId == "net-p1",
	"live player callback was lost")

local replacement = assert(Selector.show(p1), "same-player replacement failed")
assert(playerOnePending.closed == true and not playerOnePending:getIsVisible(),
	"same-player singleton was not replaced")
local replacementRequest = listRequests[#listRequests]
cleanupRegistrations[1].callback(1)
assert(replacement.closed == true and replacementRequest.disposed == true,
	"registered cleanup did not close/dispose the exact player selector")

local empty = assert(Selector.show(p0))
listRequests[#listRequests].callback(true, "OK", {})
assert(empty.state == "empty" and empty:confirmSelection() == false,
	"empty response did not remain non-actionable")
local failed = assert(Selector.show(p0))
listRequests[#listRequests].callback(false, "rate_limited", {})
assert(failed.state == "error" and failed:confirmSelection() == false,
	"failed response did not remain non-actionable")

assert(#privateProductAccesses == 0,
	"official Tablet addon still consumes private GlobalStorageSiK.* symbols: "
		.. table.concat(privateProductAccesses, ", "))

print("tablet_network_selector_contract: OK")
