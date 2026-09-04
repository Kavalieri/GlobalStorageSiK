-- Author regression for Core surfaces whose chrome is owned by SiK.UI.
-- This is source-only: it does not instantiate PZ widgets or alter product state.

local Support = dofile("tests/helpers/sik_ui_contract_support.lua")
local suite = Support.newSuite("sik_ui_core_shell_inheritance_contract")

local CLIENT = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/"
local surfaces = {
	{ file = "GS_AdminDashboard.lua", classes = {
		"GS_AdminHistoryUI", "GS_AdminMemberEditorUI", "GS_AdminDashboardUI",
	} },
	{ file = "GS_AddonManageUI.lua", classes = { "GS_AddonManageUI" } },
	{ file = "GS_PCAcquireUI.lua", classes = { "GS_PCAcquireUI" } },
	{ file = "GS_ReaderAcquireUI.lua", classes = { "GS_ReaderAcquireUI" } },
	{ file = "GS_TerminalInstallReaderChoice.lua",
		classes = { "GS_TerminalInstallReaderChoice" } },
	{ file = "GS_TerminalUI_TerminalEditor.lua",
		classes = { "GS_TerminalEditorUI" } },
}

local function read(path)
	local file = assert(io.open(path, "rb"), path)
	local source = file:read("*a")
	file:close()
	return source
end

local function contains(source, needle, label)
	assert(source:find(needle, 1, true), label or ("missing " .. needle))
end

local function excludes(source, needle, label)
	assert(not source:find(needle, 1, true), label or ("unexpected " .. needle))
end

Support.check(suite, "owned Core shells derive only through the public Window contract", function()
	for index = 1, #surfaces do
		local spec = surfaces[index]
		local source = read(CLIENT .. spec.file)
		contains(source, 'local UI = require "GS_UI_Framework"',
			spec.file .. " does not load the public UI facade")
		excludes(source, "ISPanel:derive", spec.file .. " derives ISPanel directly")
		excludes(source, "ISPanelJoypad:derive", spec.file .. " derives ISPanelJoypad directly")
		excludes(source, "ISPanel:new", spec.file .. " constructs ISPanel directly")
		excludes(source, "ISPanelJoypad:new", spec.file .. " constructs ISPanelJoypad directly")
		for classIndex = 1, #spec.classes do
			local className = spec.classes[classIndex]
			contains(source, className .. ' = UI.Window.derive("' .. className .. '")',
				className .. " is not owned by UI.Window")
		end
	end
	return true
end)

Support.check(suite, "owned Core shells delegate base lifecycle through Window", function()
	for index = 1, #surfaces do
		local spec = surfaces[index]
		local source = read(CLIENT .. spec.file)
		excludes(source, "ISPanel.initialise(", spec.file .. " calls ISPanel.initialise directly")
		excludes(source, "ISPanelJoypad.initialise(",
			spec.file .. " calls ISPanelJoypad.initialise directly")
		contains(source, 'UI.Window.callBase(self, "initialise")',
			spec.file .. " does not delegate initialise through UI.Window")
	end
	local admin = read(CLIENT .. "GS_AdminDashboard.lua")
	excludes(admin, "ISPanel.onKeyRelease(", "Admin delegates keys directly to ISPanel")
	contains(admin, 'UI.Window.callBase(self, "onKeyRelease", key)',
		"Admin does not delegate keys through UI.Window")
	return true
end)

Support.finish(suite)
