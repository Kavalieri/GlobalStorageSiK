-- Static contract for event-driven shell state and the public palette control.
local root = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/"

local function read(name)
	local file = assert(io.open(root .. name, "rb"), name)
	local text = file:read("*a")
	file:close()
	return text
end

local function missing(name)
	local file = io.open(root .. name, "rb")
	if file then
		file:close()
		return false
	end
	return true
end

local function contains(text, value, note)
	assert(text:find(value, 1, true), note or value)
end

local function excludes(text, value, note)
	assert(not text:find(value, 1, true), note or value)
end

assert(missing("GS_TerminalUI_NetworkList.lua"), "NetworkList must remain retired")
assert(missing("GS_TerminalUI_NetworkStatus.lua"), "NetworkStatus must remain retired")

local terminal = read("GS_TerminalUI.lua")
contains(terminal, "UI.Window.apply(self, {", "terminal keeps the adopted public Window shell")
excludes(terminal, "syncBlockedFrame", "shell must not poll blocked frame state")
excludes(terminal, "function GS_TerminalUI:prerender()", "shell must not poll from prerender")

local tabs = read("GS_TerminalUI_Tabs.lua")
contains(tabs, "function GlobalStorageSiK.TerminalTabs.applyAccessMode(terminal, mode, blockedState)",
	"access mode owns the shell state transition")
contains(tabs, "if terminal.syncHeaderChrome then terminal:syncHeaderChrome() end",
	"access mode refreshes public window chrome")
contains(tabs, "GlobalStorageSiK.TerminalTabs.syncBlockedFrame(terminal)",
	"tab state transition synchronizes blocked frame once")
contains(tabs, "terminal._gsBlockedFrameState == blocked",
	"blocked frame synchronization is state guarded")

local palette = read("GS_UI_PalettePreference.lua")
contains(palette, 'local UI = require "GS_UI_Framework"', "palette loads the public facade")
contains(palette, "UI.Controls.combo(panel, {", "palette uses the public combo")
contains(palette, "context and context.value", "palette consumes the normalized combo payload")
excludes(palette, "ISComboBox:new", "palette must not construct a vanilla combo locally")
excludes(palette, "styleComboBox", "palette must not restyle the public combo")

print("terminal_shell_state_binding_contract: OK")
