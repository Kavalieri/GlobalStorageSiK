-- Adversarial contract for the public per-player SiK.UI FocusStack.
-- Pure Lua 5.1: no Project Zomboid runtime or UIManager is opened.

local Support = dofile("tests/helpers/sik_ui_contract_support.lua")
local suite = Support.newSuite("sik_ui_escape_stack_adversarial")
local FocusStack = Support.loadFrameworkModule(suite, "FocusStack")
local priority = FocusStack.PRIORITY
local closed = {}
local tickCallbacks = {}

Keyboard = { KEY_ESCAPE = 27 }
Events = { OnTick = {} }
function Events.OnTick.Add(callback)
	tickCallbacks[#tickCallbacks + 1] = callback
end
function Events.OnTick.Remove(callback)
	for index = #tickCallbacks, 1, -1 do
		if tickCallbacks[index] == callback then table.remove(tickCallbacks, index) end
	end
end

local function runTick()
	local snapshot = {}
	for index = 1, #tickCallbacks do snapshot[index] = tickCallbacks[index] end
	for index = 1, #snapshot do snapshot[index]() end
end

local function panel(name, playerNum)
	local value = {
		name = name, playerNum = playerNum, visible = true,
		bringCount = 0, removeCount = 0, legacyKeyCount = 0,
	}
	function value:getIsVisible() return self.visible end
	function value:setVisible(visible) self.visible = visible == true end
	function value:removeFromUIManager()
		self.removeCount = self.removeCount + 1
		self.visible = false
	end
	function value:bringToTop() self.bringCount = self.bringCount + 1 end
	function value:setWantKeyEvents(enabled) self.wantsKeys = enabled == true end
	function value:onKeyPress()
		self.legacyKeyCount = self.legacyKeyCount + 1
		return false
	end
	function value:onKeyRelease() return false end
	return value
end

local function install(value, rank)
	local installation, err = FocusStack.install(value, function(target)
		closed[#closed + 1] = target.name
		target:setVisible(false)
	end, { playerNum = value.playerNum, priority = rank })
	assert(installation, err)
	value.installation = installation
	return value
end

local function isTop(value)
	return FocusStack.isTop(value, value.playerNum)
end

local function press(value)
	return value:onKeyPress(Keyboard.KEY_ESCAPE)
end

local function pulse(value)
	local before = #closed
	local down = value:onKeyPress(Keyboard.KEY_ESCAPE)
	assert(#closed == before, "Escape closed a layer before key-up")
	local up = value:onKeyRelease(Keyboard.KEY_ESCAPE)
	assert(#closed == before, "Escape closed before the release dispatch completed")
	assert(value:isKeyConsumed(Keyboard.KEY_ESCAPE) == true,
		"released Escape stopped being consumed before vanilla evaluated it")
	runTick()
	return down, up
end

Support.check(suite, "priority is semantic and player stacks are isolated", function()
	local transient0 = install(panel("p0-transient", 0), priority.TRANSIENT)
	local staff0 = install(panel("p0-staff", 0), priority.STAFF)
	local modal0 = install(panel("p0-modal", 0), priority.MODAL)
	local terminal0 = install(panel("p0-terminal", 0), priority.TERMINAL)
	assert(isTop(transient0), "TRANSIENT must beat later lower-priority pushes")
	assert(not isTop(modal0) and not isTop(terminal0) and not isTop(staff0),
		"more than one p0 panel is top")
	assert(press(terminal0) == false and #closed == 0,
		"an inferior surface consumed Escape")

	local terminal1 = install(panel("p1-terminal", 1), priority.TERMINAL)
	local modal1 = install(panel("p1-modal", 1), priority.MODAL)
	assert(isTop(modal1) and isTop(transient0), "player stacks leaked across playerNum")

	local down, up = pulse(transient0)
	assert(down == true and up == true and closed[1] == "p0-transient",
		"first Escape did not close the p0 transient")
	assert(#closed == 1 and isTop(modal0), "first Escape cascaded")
	down, up = pulse(modal0)
	assert(down == true and up == true and closed[2] == "p0-modal",
		"second Escape did not close the next p0 layer")
	assert(#closed == 2 and isTop(terminal0), "second Escape cascaded")
	assert(isTop(modal1), "p0 Escape mutated p1")

	for _, value in ipairs({ staff0, terminal0, terminal1, modal1 }) do
		value.installation:dispose()
	end
	return true
end)

Support.check(suite, "equal priority is LIFO and visibility re-registers", function()
	local sameA = install(panel("same-a", 0), priority.MODAL)
	local sameB = install(panel("same-b", 0), priority.MODAL)
	assert(isTop(sameB), "equal-priority stack is not LIFO")
	assert(press(sameA) == false, "older equal-priority panel consumed Escape")
	local down, up = pulse(sameB)
	assert(down == true and up == true and closed[#closed] == "same-b",
		"newest equal-priority panel did not consume Escape")
	assert(isTop(sameA), "LIFO predecessor was not exposed")

	sameA:setVisible(false)
	assert(not isTop(sameA), "hidden surface retained a stale layer")
	local sameC = install(panel("same-c", 0), priority.MODAL)
	sameA:setVisible(true)
	assert(isTop(sameA) and not isTop(sameC),
		"visible surface did not receive a fresh LIFO sequence")

	sameA:removeFromUIManager()
	assert(not isTop(sameA) and isTop(sameC), "UIManager removal retained a layer")
	assert(sameA.installation.disposed == true, "UIManager removal did not dispose installation")
	sameA:setVisible(true)
	assert(not isTop(sameA), "a disposed installation resurrected after removal")

	sameC:setVisible(false)
	assert(press(sameC) == false, "empty stack consumed Escape")
	sameC.installation:dispose()
	return true
end)

Support.check(suite, "deferred close cannot leak or cascade the release pulse", function()
	local lower = install(panel("dispose-lower", 0), priority.TERMINAL)
	local upper = panel("dispose-upper", 0)
	local installation
	installation = assert(FocusStack.install(upper, function(target)
		closed[#closed + 1] = target.name
		target.visible = false
		installation:dispose()
		return true
	end, { playerNum = 0, priority = priority.MODAL }))
	local down, up = pulse(upper)
	assert(down == true and up == true, "self-disposing top did not consume the full pulse")
	assert(closed[#closed] == "dispose-upper" and isTop(lower),
		"self-disposing top cascaded into the lower layer")
	down, up = pulse(lower)
	assert(down == true and up == true and closed[#closed] == "dispose-lower",
		"next physical pulse did not close the next layer")
	lower.installation:dispose()
	return true
end)

Support.check(suite, "disposing before the barrier tick cancels the armed close", function()
	local value = install(panel("cancel-pending", 0), priority.MODAL)
	local before = #closed
	assert(value:onKeyPress(Keyboard.KEY_ESCAPE) == true, "pending case did not arm")
	assert(value:onKeyRelease(Keyboard.KEY_ESCAPE) == true, "pending release leaked")
	assert(#tickCallbacks == 1, "pending close did not own exactly one tick callback")
	value.installation:dispose()
	assert(#tickCallbacks == 0, "dispose retained the pending tick callback")
	runTick()
	assert(#closed == before, "disposed pending close executed later")
	return true
end)

Support.check(suite, "non-Escape callback and cleanup remain exact", function()
	local ordinary = install(panel("ordinary", 0), priority.MODAL)
	assert(ordinary:onKeyPress(65) == false and ordinary.legacyKeyCount == 1,
		"installation replaced the ordinary key callback")
	assert(ordinary.wantsKeys == true, "installation did not request key events")
	ordinary.installation:dispose()
	assert(ordinary.wantsKeys == false, "dispose retained key events")
	return true
end)

local function read(path)
	local handle = assert(io.open(path, "rb"), "cannot read " .. path)
	local source = handle:read("*a"); handle:close(); return source
end

local function contains(source, needle, message)
	assert(source:find(needle, 1, true) ~= nil, message .. ": " .. needle)
end

Support.check(suite, "framework wraps existing callbacks and disposes atomically", function()
	local source = read(Support.frameworkPath("FocusStack.lua"))
	contains(source, "local previousPress = owner.onKeyPress", "ordinary key-down callback not preserved")
	contains(source, "owner.onKeyPress = pressWrapper", "Escape is not consumed on key-down")
	contains(source, "state.pendingEscapeTick", "key-up has no bounded pulse barrier")
	contains(source, "Events.OnTick.Remove(callback)", "pulse barrier is not self-cleaning")
	contains(source, "return FocusStack.handleEscape(state.playerNum)",
		"deferred key-up does not execute the armed close")
	contains(source, "return true", "consumed key-up can leak to vanilla")
	contains(source, "state:dispose()", "UIManager removal is not terminal")
	return true
end)

Support.check(suite, "current consumers use public ownership and exact close actions", function()
	local root = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/"
	local terminal = read(root .. "GS_TerminalUI.lua")
	local staff = read(root .. "GS_AdminDashboard.lua")
	local picker = read(root .. "GS_ZonePicker.lua")
	local drag = read(root .. "GS_TerminalWithdrawDrag.lua")
	local quantity = read(root .. "GS_QuantityPrompt.lua")
	contains(terminal, "UI.Window.apply(self", "terminal does not use public Window")
	contains(terminal, "focusPriority", "terminal does not declare its focus layer")
	contains(staff, "UI.Window.apply(self", "Staff does not use public Window")
	contains(staff, "UI.FocusStack.PRIORITY.STAFF", "Staff priority is not semantic")
	contains(picker, "GlobalStorageSiK.ZonePicker.cancel()", "picker cancel callback changed")
	contains(picker, "UI.FocusStack.PRIORITY.TRANSIENT", "picker priority changed")
	contains(drag, 'local UI = require "GS_UI_Framework"',
		"withdraw drag does not enter through the strict public framework binding")
	contains(drag, "UI.Drag.begin", "withdraw drag does not use public Drag")
	contains(drag, "GlobalStorageSiK.TerminalWithdrawDrag.cancel()", "drag cancel callback changed")
	contains(quantity, "UI.Modal.input", "quantity prompt does not use public Modal")
	contains(quantity, "onCancel = options.onClose", "quantity prompt lost external close callback")
	for _, forbidden in ipairs({
		"Events.OnKeyPressed.Add", "Events.OnKeyStartPressed.Add",
		"Events.OnKeyKeepPressed.Add", "Events.OnKeyReleased.Add", "Events.OnTick.Add",
	}) do
		assert(not terminal:find(forbidden, 1, true), "terminal uses global Escape route: " .. forbidden)
	end
	return true
end)

Support.finish(suite)
