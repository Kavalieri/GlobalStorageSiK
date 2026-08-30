-- Reusable author contract for the Kava-validated terminal-tabs package.
-- It keeps 13 surface IDs individually traceable while verifying their shared
-- Shell/Foundation composition without starting Project Zomboid.

local Support = dofile("tests/helpers/sik_ui_contract_support.lua")
local suite = Support.newSuite("sik_ui_terminal_tabs_parity_contract")

local CLIENT = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/"
local function read(path)
	local file = assert(io.open(path, "rb"), path)
	local text = file:read("*a")
	file:close()
	return text
end

local function contains(text, needle, label)
	assert(text:find(needle, 1, true), label or ("missing " .. needle))
end

local function excludes(text, needle, label)
	assert(not text:find(needle, 1, true), label or ("unexpected " .. needle))
end

local function countPlain(text, needle)
	local count, cursor = 0, 1
	while true do
		local at = text:find(needle, cursor, true)
		if not at then return count end
		count = count + 1
		cursor = at + #needle
	end
end

local function namedTable(text, name)
	local marker = "local " .. name .. " = {"
	local first = assert(text:find(marker, 1, true), "missing table " .. name)
	local lineEnd = text:find("\n", first, true) or (#text + 1)
	local inlineLast = text:find("}", first, true)
	if inlineLast and inlineLast < lineEnd then
		return text:sub(first, inlineLast)
	end
	local last = text:find("\n}", first, true)
	assert(last, "unterminated table " .. name)
	return text:sub(first, last + 1)
end

local function sortedKeys(map)
	local keys = {}
	for key in pairs(map) do keys[#keys + 1] = key end
	table.sort(keys)
	return keys
end

local expectedSurfaces = {
	["terminal-tabs"] = true,
	["terminal-remote"] = true,
	["tab-warehouse"] = true,
	["warehouse-drop-overlay"] = true,
	["tab-red"] = true,
	["tab-options"] = true,
	["tab-options-state"] = true,
	["tab-options-admin"] = true,
	["tab-addons"] = true,
	["tab-programming"] = true,
	["tab-craft"] = true,
	["tab-builder"] = true,
	["terminal-blocked"] = true,
}

local html = read("../Documentacion/UI/terminal-tabs.html")
local annex = read("../Documentacion/UI/terminal-tabs.md")

Support.check(suite, "validated package declares exactly 13 unique surface IDs", function()
	local actual, total = {}, 0
	for surfaceId in html:gmatch('data%-surface%-id="([^"]+)"') do
		assert(not actual[surfaceId], "duplicate HTML surfaceId " .. surfaceId)
		actual[surfaceId] = true
		total = total + 1
	end
	assert(total == 13, "expected 13 surface IDs, got " .. tostring(total))
	for surfaceId in pairs(expectedSurfaces) do
		assert(actual[surfaceId], "HTML missing surfaceId " .. surfaceId)
		contains(annex, "`" .. surfaceId .. "`", "annex missing " .. surfaceId)
	end
	for surfaceId in pairs(actual) do
		assert(expectedSurfaces[surfaceId], "unexpected surfaceId " .. surfaceId)
	end
	return true
end)

Support.check(suite, "package has eight tab routes and Tablet is context not a tab", function()
	local panels = {}
	for key in html:gmatch('data%-panel="([^"]+)"') do panels[key] = true end
	for _, key in ipairs({ "warehouse", "red", "options", "addons",
		"programming", "craft", "builder", "blocked" }) do
		assert(panels[key], "missing panel route " .. key)
	end
	assert(#sortedKeys(panels) == 8, "unexpected tab route count")
	assert(not panels.tablet and not panels.remote, "Tablet/remote became a tab")
	contains(html, 'data-state-view="remote"', "remote context state")
	contains(html, 'data-state-view="warehouse-drop"', "warehouse drop state")
	return true
end)

Support.check(suite, "HTML table descriptors cover 3 4 and 5 column compositions", function()
	local counts = {}
	for head in html:gmatch('<div class="[^"]*sik%-table[^"]*" data%-sik%-table>%s*<div class="sik%-table%-row sik%-table%-head">(.-)</div>') do
		counts[#counts + 1] = countPlain(head, "data-col")
	end
	table.sort(counts)
	assert(#counts == 4, "expected four tables")
	local expected = { 3, 4, 4, 5 }
	for i = 1, #expected do
		assert(counts[i] == expected[i], "table descriptor mismatch at " .. tostring(i))
	end
	return true
end)

local terminal = read(CLIENT .. "GS_TerminalUI.lua")
local tabs = read(CLIENT .. "GS_TerminalUI_Tabs.lua")
local api = read(CLIENT .. "GS_TerminalUI_Api.lua")
local blockedApi = read(CLIENT .. "GS_TerminalUI_Blocked.lua")
local blockedPanel = read(CLIENT .. "GS_TerminalUI_BlockedPanel.lua")
local items = read(CLIENT .. "GS_TerminalUI_Items.lua")
local network = read(CLIENT .. "GS_TerminalUI_Network.lua")
local nodes = read(CLIENT .. "GS_TerminalUI_Nodes.lua")
local options = read(CLIENT .. "GS_TerminalUI_Options.lua")
local status = read(CLIENT .. "GS_TerminalUI_NetworkStatus.lua")
local terminals = read(CLIENT .. "GS_TerminalUI_NetworkTerminals.lua")
local permissions = read(CLIENT .. "GS_TerminalUI_Permissions.lua")
local admin = read(CLIENT .. "GS_AdminDashboard.lua")
local addons = read(CLIENT .. "GS_TerminalUI_Addons.lua")
local programming = read(CLIENT .. "GS_TerminalUI_Programming.lua")
local craft = read("addons/GSSiK_Addon_Craft/Contents/mods/GSSiK_Addon_Craft/42/media/lua/client/GSSiK_Addon_Craft_TerminalUI.lua")
local builder = read("addons/GSSiK_Addon_Builder/Contents/mods/GSSiK_Addon_Builder/42/media/lua/client/GSSiK_Addon_Builder_TerminalUI.lua")

local registrySources = table.concat({ terminal, tabs, api, blockedApi,
	blockedPanel, items, network, nodes, options, status, terminals,
	permissions, addons, programming, craft, builder }, "\n")

Support.check(suite, "all 13 surfaces have a runtime SurfaceInventory registration", function()
	contains(registrySources, "SurfaceInventory.register", "runtime registry API unused")
	for surfaceId in pairs(expectedSurfaces) do
		contains(registrySources, 'id = "' .. surfaceId .. '"',
			"runtime registry missing " .. surfaceId)
	end
	return true
end)

Support.check(suite, "Shell and tab consumers enter through Foundation APIs", function()
	for _, moduleName in ipairs({ "Metrics", "Viewport", "Controls", "Block",
		"State", "List", "Table", "Window", "Modal" }) do
		contains(terminal, 'require "GS_SiK_UI_' .. moduleName .. '"',
			"Shell missing Foundation " .. moduleName)
	end
	for name, source in pairs({ Warehouse = items, Red = nodes,
		Terminals = terminals, Members = permissions }) do
		contains(source, 'require "GS_SiK_UI_Table"', name .. " bypasses Table")
		contains(source, "SiK_UI.Table", name .. " does not consume Table")
	end
	for name, source in pairs({ Addons = addons, Programming = programming,
		Craft = craft, Builder = builder, Blocked = blockedPanel }) do
		contains(source, 'require "GS_TerminalUI_Scroll"', name .. " bypasses Block bridge")
		contains(source, "SiK_UI", name .. " bypasses shared chrome")
	end
	contains(api, "SiK_UI.Window.resolveProfile", "remote/full API bypasses Window")
	contains(blockedApi, "SiK_UI.Window.resolveProfile", "blocked API bypasses Window")
	return true
end)

Support.check(suite, "table consumers match validated 4 5 4 3 descriptors", function()
	local specs = {
		{ label = "Warehouse", text = items, name = "ITEM_TABLE_COLUMNS", count = 4 },
		{ label = "Red", text = nodes, name = "NODE_TABLE_COLUMNS", count = 5 },
		{ label = "Terminals", text = terminals, name = "TERMINAL_TABLE_COLUMNS", count = 4 },
		{ label = "Members", text = permissions, name = "MEMBER_TABLE_COLUMNS", count = 3 },
	}
	for _, spec in ipairs(specs) do
		local literal = namedTable(spec.text, spec.name)
		assert(countPlain(literal, "key =") == spec.count,
			spec.label .. " column count differs from HTML")
		contains(spec.text, "SiK_UI.Table.drawHeader", spec.label .. " header bypasses Table")
		contains(spec.text, "SiK_UI.Table.resolveColumns", spec.label .. " rows bypass Table")
	end
	return true
end)

Support.check(suite, "Block owns the only scrollbar gutter for Lote2 tables", function()
	for name, source in pairs({ Warehouse = items, Terminals = terminals,
		Members = permissions }) do
		excludes(source, "scrollBarWidth()", name .. " reserves scrollbar manually")
		excludes(source, "_gsScrollBarGap", name .. " owns a second scrollbar gap")
		excludes(source, "_gsBarRightPad", name .. " owns a second bar padding")
	end
	local terminalOptions = namedTable(terminals, "TERMINAL_TABLE_OPTIONS")
	local memberOptions = namedTable(permissions, "MEMBER_TABLE_OPTIONS")
	local itemOptions = namedTable(items, "ITEM_TABLE_OPTIONS")
	for name, literal in pairs({ Warehouse = itemOptions,
		Terminals = terminalOptions, Members = memberOptions }) do
		local right = literal:match("right%s*=%s*([%d%.%-]+)")
		assert(right and tonumber(right) == 0,
			name .. " table must consume Block contentW with right=0")
	end
	return true
end)

Support.loadClientModule(suite, "GS_SiK_UI_Metrics")
Support.loadClientModule(suite, "GS_SiK_UI_Block")

Support.check(suite, "Block reserves the canonical gutter only while content overflows", function()
	local Metrics = GlobalStorageSiK.SiK_UI.Metrics
	local Block = GlobalStorageSiK.SiK_UI.Block
	local tokens = Metrics.tokens()
	local bounds = { x = 0, y = 0, w = 811, h = 500 }
	local short = Block.resolveContentRect(bounds, { scrollable = true, contentHeight = 100 })
	local long = Block.resolveContentRect(bounds, { scrollable = true, contentHeight = 2000 })
	local expectedShortW = bounds.w - tokens.blockPaddingX * 2
	local expectedLongW = expectedShortW - tokens.scrollGutter
	assert(short.w == expectedShortW, "short content did not recover the full Block width")
	assert(long.w == expectedLongW, "overflow did not reserve exactly the canonical gutter")
	assert(short.x == long.x, "overflow shifted content axis")
	return true
end)

Support.check(suite, "Options matches validated Estado then Admin composition", function()
	local tabKeys = namedTable(options, "TAB_KEYS")
	contains(tabKeys, '{ "estado", "admin" }', "Options subtab order differs from HTML")
	contains(options, 'local DEFAULT_TAB = "estado"', "Estado is not default")
	contains(options, "TerminalNetworkStatus.build", "Estado content missing")
	contains(options, "TerminalNetworkTerminals.build", "Admin terminals missing")
	contains(options, "TerminalPermissions.ensureInNetworkScroll", "Admin members missing")
	return true
end)

Support.check(suite, "Red and Warehouse expose their validated functional regions", function()
	contains(network, "TerminalNodes.embedInNetworkScroll", "Red omits zones/nodes")
	contains(network, "networkRescanBtn", "Red omits whole-network rescan")
	excludes(nodes, "createSectionCard(pad, cardY", "zones still own the global rescan card")
	contains(terminal, "mainCategoryFilterCombo", "Warehouse family filter missing")
	contains(terminal, "subCategoryFilterCombo", "Warehouse group filter missing")
	contains(terminal, "leafCategoryFilterCombo", "Warehouse detail filter missing")
	contains(terminal, "searchBox", "Warehouse search missing")
	contains(terminal, "TerminalDrop.setupPanel", "Warehouse drop surface missing")
	excludes(terminal, "yoffset = -2", "Warehouse filters retain local vertical offsets")
	excludes(terminal, "ISComboBox:new(0, y - 2", "Warehouse builds filters off the shared row")
	return true
end)

Support.check(suite, "Admin selectors and variable staff text reflow inside safe geometry", function()
	contains(permissions, "buttonW = math.min(rowW", "Options Add button is not measured first")
	contains(permissions, "local stacked =", "Options Add row has no narrow fallback")
	contains(admin, "wrapTextLines(sourceLines[i]", "staff info remains fixed-line")
	contains(admin, "Window.resolveProfile(\"staff\"", "staff bypasses the shared viewport")
	contains(admin, "staffColumns", "staff actions have no width-aware composition")
	return true
end)

Support.check(suite, "Addons Programming blocked and remote states keep their owners", function()
	contains(addons, 'require "GS_TerminalUI_AddonBay"', "Addon bay owner missing")
	contains(programming, 'KNOWN_PROGRAM_ORDER = { "network", "uninstall", "driveinstall" }',
		"Programming Core order differs from HTML")
	contains(tabs, 'applyAccessMode(terminal, mode, blockedState)', "blocked state router missing")
	contains(blockedApi, "ui = GS_TerminalUI:new", "blocked uses another shell")
	contains(api, "resolveShellRect(player)", "remote/full opening bypasses shared shell")
	excludes(tabs, 'tabViews["tablet"]', "Tablet became a tab")
	return true
end)

Support.finish(suite)
