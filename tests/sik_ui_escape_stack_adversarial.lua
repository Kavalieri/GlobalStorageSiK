-- Author adversarial contract for the per-player SiK UI Escape stack.
-- Pure Lua 5.1: no Project Zomboid runtime or UIManager is opened.

Keyboard = { KEY_ESCAPE = 27 }
GlobalStorageSiK = { SiK_UI = {} }

local root = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/"
local EscapeStack = dofile(root .. "GS_SiK_UI_EscapeStack.lua")
local priority = EscapeStack.PRIORITY
local closed = {}

local function panel(name, playerNum)
	local value = {
		name = name,
		playerNum = playerNum,
		visible = true,
		bringCount = 0,
		removeCount = 0,
		legacyKeyCount = 0,
	}
	function value:getIsVisible() return self.visible end
	function value:setVisible(visible) self.visible = visible == true end
	function value:removeFromUIManager()
		self.removeCount = self.removeCount + 1
		self.visible = false
	end
	function value:bringToTop() self.bringCount = self.bringCount + 1 end
	function value:onKeyRelease()
		self.legacyKeyCount = self.legacyKeyCount + 1
		return false
	end
	return value
end

local function install(value, rank)
	EscapeStack.install(value, function(target)
		closed[#closed + 1] = target.name
		target:setVisible(false)
	end, rank)
	return value
end

local function press(value)
	return value:onKeyRelease(Keyboard.KEY_ESCAPE)
end

-- Priority is semantic, never push-order. Deliberately push in a hostile order.
local transient0 = install(panel("p0-transient", 0), priority.TRANSIENT)
local staff0 = install(panel("p0-staff", 0), priority.STAFF)
local modal0 = install(panel("p0-modal", 0), priority.MODAL)
local terminal0 = install(panel("p0-terminal", 0), priority.TERMINAL)
assert(EscapeStack.isTop(transient0), "TRANSIENT must beat later lower-priority pushes")
assert(not EscapeStack.isTop(modal0) and not EscapeStack.isTop(terminal0)
	and not EscapeStack.isTop(staff0), "more than one p0 panel is top")
assert(press(terminal0) == false and #closed == 0,
	"an inferior surface consumed Escape")

-- Player 1 is isolated from every priority and sequence in player 0.
local terminal1 = install(panel("p1-terminal", 1), priority.TERMINAL)
local modal1 = install(panel("p1-modal", 1), priority.MODAL)
assert(EscapeStack.isTop(modal1), "player 1 top was affected by player 0")
assert(EscapeStack.isTop(transient0), "player 0 top was affected by player 1")

-- One press closes exactly one layer. A second press is required for the next.
assert(press(transient0) == true and closed[1] == "p0-transient",
	"first Escape did not close the p0 transient")
assert(#closed == 1 and EscapeStack.isTop(modal0),
	"first Escape cascaded into more than one layer")
assert(press(modal0) == true and closed[2] == "p0-modal",
	"second Escape did not close exactly the next p0 layer")
assert(#closed == 2 and EscapeStack.isTop(terminal0),
	"second Escape cascaded or selected the wrong priority")
assert(EscapeStack.isTop(modal1), "p0 Escape mutated the p1 stack")

-- LIFO applies only within an equal priority.
local sameA = install(panel("same-a", 0), priority.MODAL)
local sameB = install(panel("same-b", 0), priority.MODAL)
assert(EscapeStack.isTop(sameB), "equal-priority stack is not LIFO")
assert(press(sameA) == false, "older equal-priority panel consumed Escape")
assert(press(sameB) == true and closed[#closed] == "same-b",
	"newest equal-priority panel did not consume Escape")
assert(EscapeStack.isTop(sameA), "LIFO predecessor was not exposed after close")

-- Visibility changes purge and reopening reinserts with a fresh LIFO sequence.
sameA:setVisible(false)
assert(not EscapeStack.isTop(sameA), "setVisible(false) retained a stale stack entry")
local sameC = install(panel("same-c", 0), priority.MODAL)
sameA:setVisible(true)
assert(EscapeStack.isTop(sameA), "reopening did not reinsert the surface")
assert(not EscapeStack.isTop(sameC), "reopening did not receive fresh LIFO order")

-- UIManager removal and an external destroy-style close also purge safely.
sameA:removeFromUIManager()
assert(not EscapeStack.isTop(sameA) and EscapeStack.isTop(sameC),
	"removeFromUIManager did not purge the top surface")
sameA:setVisible(true)
assert(EscapeStack.isTop(sameA), "surface could not be reinserted after UIManager removal")
local function externalClose(value)
	value:removeFromUIManager()
end
externalClose(sameA)
assert(not EscapeStack.isTop(sameA) and EscapeStack.isTop(sameC),
	"external close retained a stale stack entry")

-- Removing every visible layer returns Escape to vanilla (false).
sameC:setVisible(false)
terminal0:setVisible(false)
staff0:setVisible(false)
assert(press(sameC) == false, "empty p0 stack consumed Escape instead of returning to vanilla")
modal1:setVisible(false)
terminal1:setVisible(false)
assert(press(modal1) == false, "empty p1 stack consumed Escape instead of returning to vanilla")

-- Non-Escape keys keep the exact pre-existing surface callback.
local ordinary = install(panel("ordinary", 0), priority.MODAL)
assert(ordinary:onKeyRelease(65) == false and ordinary.legacyKeyCount == 1,
	"Escape installation replaced the ordinary key callback")
ordinary:setVisible(false)

local function read(path)
	local handle = assert(io.open(root .. path, "rb"), "cannot read " .. path)
	local source = handle:read("*a")
	handle:close()
	return source
end

local function contains(source, needle, message)
	assert(source:find(needle, 1, true) ~= nil, message .. ": " .. needle)
end

local terminalSource = read("GS_TerminalUI.lua")
local staffSource = read("GS_AdminDashboard.lua")
local pickerSource = read("GS_ZonePicker.lua")
local dragSource = read("GS_TerminalWithdrawDrag.lua")
local quantitySource = read("GS_QuantityPrompt.lua")

-- Exact consumers and callbacks. This guards against installing a stack layer
-- that closes a different surface or uses the wrong priority.
contains(terminalSource, "Window.installEscape(self, GS_TerminalUI.onClose,",
	"terminal does not register its exact close callback")
contains(terminalSource, "EscapeStack.PRIORITY.TERMINAL",
	"terminal does not use TERMINAL priority")
contains(staffSource, "Window.installEscape(self, GS_AdminDashboardUI.destroy,",
	"Staff does not register its exact destroy callback")
contains(staffSource, "EscapeStack.PRIORITY.STAFF",
	"Staff does not use STAFF priority")
contains(pickerSource, "GlobalStorageSiK.ZonePicker.cancel()",
	"zone picker does not register its exact cancel callback")
contains(pickerSource, "EscapeStack.PRIORITY.TRANSIENT",
	"zone picker does not use TRANSIENT priority")
contains(dragSource, "GlobalStorageSiK.TerminalWithdrawDrag.cancel()",
	"withdraw drag does not register its exact cancel callback")
contains(dragSource, "EscapeStack.PRIORITY.TRANSIENT",
	"withdraw drag does not use TRANSIENT priority")
contains(quantitySource, "EscapeStack.install(box, function(panel)",
	"quantity prompt does not register its own surface")
contains(quantitySource, "if options.onClose then options.onClose() end",
	"quantity prompt loses its exact external close callback")
contains(quantitySource, "EscapeStack.PRIORITY.TRANSIENT",
	"quantity prompt does not use TRANSIENT priority")

-- Terminal Escape is local to its panel. A global key/tick dispatcher is a
-- prohibited route because it breaks player isolation and vanilla fallback.
for _, forbidden in ipairs({
	"Events.OnKeyPressed.Add", "Events.OnKeyStartPressed.Add",
	"Events.OnKeyKeepPressed.Add", "Events.OnKeyReleased.Add", "Events.OnTick.Add",
}) do
	assert(terminalSource:find(forbidden, 1, true) == nil,
		"GS_TerminalUI uses a prohibited global Escape route: " .. forbidden)
end

print("sik_ui_escape_stack_adversarial: OK")
