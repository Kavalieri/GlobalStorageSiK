-- Static contract for the Kava-approved Core 1.4.3-dev32.4.2 UI.
local root = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/"
local function read(name)
	local file = assert(io.open(root .. name, "rb"), name)
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

local status = read("GS_TerminalUI_NetworkStatus.lua")
contains(status, "TerminalNetworkStatus.build = buildV2", "V2 status API")
contains(status, "ui.paletteEndY", "palette is part of measured content")
excludes(status, "scanNew", "scan summary must not live in Status")
excludes(status, "networkRenameBtn", "duplicated identity card removed")

local options = read("GS_TerminalUI_Options.lua")
contains(options, "ui.paletteEndY or ui.block1EndY", "Options uses the actual final child")

local items = read("GS_TerminalUI_Items.lua")
contains(items, "pageSize = 15", "detail page size")
contains(items, "panel._expandedKeys", "semantic expansion state")
contains(items, "data._gsPager", "pager rows")
contains(items, "aggregateAllowed == false", "stateful parent is not transferable")

local dashboard = read("GS_AdminDashboard.lua")
excludes(dashboard, "self:clearChildren()", "resize must not rebuild the dashboard")
excludes(dashboard, "diagBtn", "temporary broken-item control removed")
excludes(dashboard, "IGUI_GS_AdminEditMember", "staff rows open their modal directly")
contains(dashboard, "drawTextRight", "staff connection column right aligned")

local audit = read("GS_AdminDashboard_Audit.lua")
local corpus = read("GS_AdminDashboard_Corpus.lua")
contains(audit, "ui._activeStaffTab == \"taxonomy\"", "new audit labels inherit tab visibility")
contains(corpus, "ui._activeStaffTab == \"taxonomy\"", "new corpus labels inherit tab visibility")

local terminals = read("GS_TerminalUI_NetworkTerminals.lua")
local permissions = read("GS_TerminalUI_Permissions.lua")
contains(terminals, "align = \"right\"", "terminal status right aligned")
contains(terminals, "scrollBarWidth() + 4", "terminal table reserves scrollbar")
contains(permissions, "align = \"right\"", "member connection right aligned")
contains(permissions, "scrollBarWidth() + 4", "member table reserves scrollbar")

local zoneEditor = read("GS_TerminalUI_ZoneEditor.lua")
contains(zoneEditor, "IGUI_GS_ZoneCtxRescan", "zone editor exposes its local rescan")

print("ui_dev32_4_2_contract_regression: OK")
