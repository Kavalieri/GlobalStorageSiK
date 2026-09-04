-- Static boundary contract for editor/modal consumers migrated to standalone SiK.UI.
local coreRoot = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/"
local frameworkRoot = "../SiKUIFramework-Repo/SiKUIFramework/Contents/mods/SiKUIFramework/42/media/lua/client/SiK/UI/"

local function read(path)
	local file = assert(io.open(path, "rb"), path)
	local text = file:read("*a")
	file:close()
	return text
end

local function contains(text, value, note)
	assert(text:find(value, 1, true), note or value)
end

local function excludes(text, value, note)
	assert(not text:find(value, 1, true), note or value)
end

local editors = {
	"GS_FilterEditor.lua",
	"GS_TerminalUI_MemberEditor.lua",
	"GS_TerminalUI_TerminalEditor.lua",
	"GS_TerminalUI_NodeEditor.lua",
	"GS_TerminalUI_ZoneEditor.lua",
}

for index = 1, #editors do
	local source = read(coreRoot .. editors[index])
	contains(source, 'local UI = require "GS_UI_Framework"',
		editors[index] .. " enters through the public facade")
	excludes(source, "GS_SiK_UI", editors[index] .. " has no legacy module dependency")
	excludes(source, "GlobalStorageSiK.SiK_UI",
		editors[index] .. " has no product-private UI namespace access")
end

local memberEditor = read(coreRoot .. "GS_TerminalUI_MemberEditor.lua")
contains(memberEditor, 'UI.Window.derive("GS_MemberEditorUI")',
	"member editor derives through the public Window contract")
contains(memberEditor, "UI.Window.newInstance", "member editor uses framework construction")
contains(memberEditor, "UI.Controls.copyText", "member editor copy uses framework controls")
contains(memberEditor, "UI.Controls.combo", "member editor role selector uses framework controls")
contains(memberEditor, "UI.VirtualList.create", "member editor zones use framework virtual list")
contains(memberEditor, "UI.Lifecycle.own", "member editor owns list lifecycle")
excludes(memberEditor, "ISLabel:new", "member editor has no direct label")
excludes(memberEditor, "ISComboBox:new", "member editor has no direct combo")
excludes(memberEditor, "ISScrollingListBox:new", "member editor has no direct list")
excludes(memberEditor, ":drawRect(", "member editor has no local row painting")

local controls = read(frameworkRoot .. "Controls.lua")
contains(controls, "function Controls.styleField", "public field styling")
contains(controls, "function Controls.styleCombo", "public combo styling")
contains(controls, "function Controls.progress", "public progress control")
contains(controls, "if options.indicator == true then", "public status indicator variant")
contains(controls, "function Controls.renderWrappedLinePool", "public wrapped label pool")
contains(controls, "sectionHeight = rowHeight", "canonical section metric")

local theme = read(frameworkRoot .. "Theme.lua")
local container = read(frameworkRoot .. "Container.lua")
contains(theme, "function Theme.palette", "public semantic positional palette")
contains(container, "if options.accent ~= nil then", "generic container owns optional accent")
contains(container, "options.accentWidth", "generic container owns configurable accent geometry")

print("sik_ui_editor_family_migration_contract: OK")
