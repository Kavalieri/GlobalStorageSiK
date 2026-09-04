-- The node and zone editors keep one vanilla root host for Window.applyEditor;
-- every visible child is constructed and owned by the public SiK.UI facade.
local root = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/"

local function read(path)
	local file = assert(io.open(path, "rb"), path)
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

local function occurrences(source, value)
	local count, from = 0, 1
	while true do
		local at = source:find(value, from, true)
		if not at then return count end
		count = count + 1
		from = at + #value
	end
end

local files = {
	"GS_TerminalUI_NodeEditor.lua",
	"GS_TerminalUI_ZoneEditor.lua",
}

for index = 1, #files do
	local name = files[index]
	local source = read(root .. name)
	contains(source, 'local UI = require "GS_UI_Framework"',
		name .. " enters through the public facade")
	contains(source, "UI.Window.applyEditor", name .. " uses the canonical editor shell")
	contains(source, "UI.Scroll.create", name .. " uses the public scroll region")
	contains(source, "UI.Controls.copyText", name .. " delegates copy rendering")
	contains(source, "UI.Controls.field", name .. " delegates editable fields")
	contains(source, "UI.Controls.panel", name .. " delegates transparent child hosts")
	contains(source, "UI.Controls.sectionTitle", name .. " delegates section headings")
	contains(source, "UI.Controls.button", name .. " delegates actions")
	contains(source, "UI.Container.create", name .. " delegates generic accented containers")
	contains(source, "local function createSectionCard", name .. " keeps one product composition adapter")
	contains(source, "UI.Modal.confirm", name .. " delegates confirmations")

	contains(source, "UI.Window.newInstance", name .. "delegates the root host")
	excludes(source, "ISPanel", name .. "has no direct window primitive")
	excludes(source, "ISLabel:new", name .. " has no local visible label primitive")
	excludes(source, "ISTextEntryBox:new", name .. " has no local field primitive")
	excludes(source, "ISComboBox:new", name .. " has no local combo primitive")
	excludes(source, "ISButton:new", name .. " has no local button primitive")
	excludes(source, ":drawRect", name .. " has no local rectangle painting")
	excludes(source, ":drawText", name .. " has no local text painting")
	excludes(source, "GS_SiK_UI", name .. " has no private framework import")
	excludes(source, "GlobalStorageSiK.SiK_UI",
		name .. " has no private framework namespace access")
end

print("sik_ui_node_zone_editor_composition_contract: OK")
