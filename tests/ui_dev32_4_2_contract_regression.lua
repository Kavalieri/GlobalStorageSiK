-- Static contract for the Kava-approved Core 1.4.3-dev32.4.2 UI.
local root = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/"
local function read(name)
	local file = assert(io.open(root .. name, "rb"), name)
	local text = file:read("*a")
	file:close()
	return text
end
local function isMissing(name)
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

assert(isMissing("GS_TerminalUI_NetworkList.lua"),
	"retired manual NetworkList module must stay absent")
assert(isMissing("GS_TerminalUI_NetworkStatus.lua"),
	"retired manual NetworkStatus module must stay absent")

local options = read("GS_TerminalUI_Options.lua")
contains(options, 'require "GS_UI_Framework"', "Options loads the public SiK.UI framework")
contains(options, 'require "GlobalStorageSiK/UI/Generated/TabOptions"',
	"Options consumes the generated tab-options surface")
contains(options, 'require "GlobalStorageSiK/UI/TabOptionsContext"',
	"Options consumes the pure tab-options context adapter")
contains(options, "TabOptionsContext.create(terminal)", "Options creates one context adapter")
contains(options, "SiK.UI.SurfaceHost.mount(optionsPanel, TabOptionsSpec, {",
	"Options mounts the declarative surface through SurfaceHost")
contains(options, "followParent = true", "Options follows the final parent geometry")
contains(options, "surface:refresh(snapshot)", "Options refreshes the mounted surface from snapshots")
contains(options, "surface:reflow(panelBounds(panel))",
	"Options delegates panel resize to the mounted surface")
contains(options, "surface:reflow({ x = 0, y = 0, w = math.max(1, tonumber(innerW) or 1)",
	"Options delegates explicit bounds to the mounted surface")
contains(options, "adapter:dispose()", "Options releases its context adapter")
for _, legacyBuilder in ipairs({
	"GS_TerminalUI_NetworkList", "GS_TerminalUI_NetworkStatus",
	"GS_TerminalUI_NetworkTerminals", "GS_TerminalUI_Permissions",
}) do
	excludes(options, legacyBuilder, "Options retained a manual legacy builder")
end

local palette = read("GS_UI_PalettePreference.lua")
contains(palette, "UI.Controls.combo(panel, {", "palette uses the public combo control")
excludes(palette, "ISComboBox:new", "palette must not create a local combo")

local terminal = read("GS_TerminalUI.lua")
excludes(terminal, "syncBlockedFrame", "terminal shell must not poll blocked frame state")
excludes(terminal, "function GS_TerminalUI:prerender()",
	"terminal shell must not keep a polling prerender override")

local items = read("GS_TerminalUI_Items.lua")
contains(items, "pageSize = 15", "detail page size")
contains(items, "panel._expandedKeys", "semantic expansion state")
contains(items, "external = true", "Table owns external detail pagination")
contains(items, "disabled = pending or pageStale", "pending/stale page navigation is guarded")
excludes(items, "data._gsPager", "retired product pager rows must stay absent")
contains(items, "aggregateAllowed == false", "stateful parent is not transferable")

local dashboard = read("GS_AdminDashboard.lua")
excludes(dashboard, "self:clearChildren()", "resize must not rebuild the dashboard")
excludes(dashboard, "diagBtn", "temporary broken-item control removed")
excludes(dashboard, "IGUI_GS_AdminEditMember", "staff rows open their modal directly")
contains(dashboard, '{ key = "connection", titleKey = "IGUI_GS_PermColConnection", width = COL_SEEN_W, align = "right"',
	"staff connection column right aligned by the shared table descriptor")
contains(dashboard, "UI.Table.create({", "staff members use the public shared table")

local audit = read("GS_AdminDashboard_Audit.lua")
local corpus = read("GS_AdminDashboard_Corpus.lua")
contains(audit, "ui._activeStaffTab == \"taxonomy\"", "new audit labels inherit tab visibility")
contains(corpus, "ui._activeStaffTab == \"taxonomy\"", "new corpus labels inherit tab visibility")

local terminals = read("GS_TerminalUI_NetworkTerminals.lua")
local permissions = read("GS_TerminalUI_Permissions.lua")
local generatedOptions = read("GlobalStorageSiK/UI/Generated/TabOptions.lua")
contains(generatedOptions, '["id"] = "options-terminals-table"',
	"terminal table is declared by the generated framework surface")
contains(generatedOptions, '["key"] = "status"', "terminal status column is declared")
contains(generatedOptions, '["align"] = "right"', "generated status columns are right aligned")
contains(terminals, "function Terminals.presentationRows", "terminal adapter exposes data only")
excludes(terminals, "UI.Table.create", "terminal adapter must not construct its table")
excludes(terminals, "scrollBarWidth() + 4", "terminal table has no manual scrollbar compensation")
contains(generatedOptions, '["id"] = "options-members-table"',
	"member table is declared by the generated framework surface")
contains(generatedOptions, '["key"] = "connection"', "member connection column is declared")
contains(permissions, "align = \"right\"", "legacy member helper preserves right alignment while retired")
contains(permissions, "left = 0, right = 0, gap = 8",
	"legacy member helper preserves canonical content width while retired")
excludes(permissions, "scrollBarWidth() + 4", "member table has no manual scrollbar compensation")

local zoneEditor = read("GS_TerminalUI_ZoneEditor.lua")
contains(zoneEditor, "IGUI_GS_ZoneCtxRescan", "zone editor exposes its local rescan")

print("ui_dev32_4_2_contract_regression: OK")
