-- The filter editor delegates its complete visible composition to the public
-- SiK.UI facade. Product code retains only rule data, callbacks and layout
-- coordinates; the framework owns the window, controls and accent chrome.
local path = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/GS_FilterEditor.lua"

local function read(filePath)
	local file = assert(io.open(filePath, "rb"), filePath)
	local source = file:read("*a")
	file:close()
	return source
end

local function contains(source, value, note)
	assert(source:find(value, 1, true), note or value)
end

local function excludes(source, value, note)
	assert(not source:find(value, 1, true), note or value)
end

local source = read(path)

contains(source, 'local UI = require "GS_UI_Framework"', "public facade entry")
contains(source, 'GS_FilterEditorUI = UI.Window.derive("GS_FilterEditorUI")',
	"public window class")
contains(source, "UI.Window.newInstance", "public root instance")
contains(source, "UI.Window.callBase", "public base lifecycle")
contains(source, "UI.Modal.apply", "canonical modal shell")
contains(source, "UI.Modal.fitContent", "canonical content sizing")
contains(source, "UI.Modal.show", "canonical modal lifecycle")
contains(source, "Confirmation.show", "shared confirmation adapter")
contains(source, "UI.Block.create", "canonical visible Blocks")
contains(source, ":beginColumn()", "canonical Block composition")
contains(source, "IGUI_GS_FilterPathTitle", "localized route Block title")
contains(source, "IGUI_GS_PermColActions", "localized actions Block title")
contains(source, "_contentWidgets", "owned content cleanup")
contains(source, "function GS_FilterEditorUI:captureDraft()", "draft preservation")
contains(source, "self:refreshItemResults()", "live item search")
contains(source, "UI.Controls.copyText", "framework-owned form copy")
contains(source, "UI.Controls.combo", "framework-owned selectors")
contains(source, "UI.Controls.field", "framework-owned fields")
contains(source, "UI.Controls.styleCombo", "canonical selector chrome")
contains(source, "UI.Controls.styleField", "canonical field chrome")
contains(source, "UI.Controls.button", "framework-owned actions and results")
contains(source, "UI.Controls.panel", "framework-owned result host")
contains(source, "accent = operatorColor", "semantic operator accent")

excludes(source, 'require "ISUI/', "no direct vanilla UI dependency")
excludes(source, "ISPanel", "no direct panel construction or lifecycle")
excludes(source, "ISLabel:new", "no local visible labels")
excludes(source, "ISTextEntryBox:new", "no local text fields")
excludes(source, "ISComboBox:new", "no local combos")
excludes(source, "ISButton:new", "no local buttons")
excludes(source, ":drawRect", "no local rectangle painting")
excludes(source, ":drawText", "no local text painting")
excludes(source, "function GS_FilterEditorUI:prerender", "no local render override")
excludes(source, "GS_SiK_UI", "no private framework module")
excludes(source, "GlobalStorageSiK.SiK_UI", "no private framework namespace")
excludes(source, "onSubmit = function() self:onAddClicked() end",
	"Enter never opens contradiction confirmation")

print("sik_ui_filter_editor_composition_contract: OK")
