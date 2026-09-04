-- Reusable author contract for the Kava-validated terminal-tabs package.
-- It keeps the 11 actual surfaces individually traceable while verifying that
-- their shared shell and widgets enter through the standalone SiK UI contract.

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

local function findNode(node, id)
	if type(node) ~= "table" then return nil end
	if node.id == id then return node end
	for _, child in ipairs(node.children or {}) do
		local found = findNode(child, id)
		if found then return found end
	end
	return nil
end

local expectedSurfaces = {
	["terminal-tabs"] = true,
	["terminal-remote"] = true,
	["tab-warehouse"] = true,
	["warehouse-drop-overlay"] = true,
	["tab-red"] = true,
	["tab-options"] = true,
	["tab-addons"] = true,
	["tab-programming"] = true,
	["tab-craft"] = true,
	["tab-builder"] = true,
	["terminal-blocked"] = true,
}

local html = read("../Documentacion/UI/terminal-tabs.html")
local annex = read("../Documentacion/UI/terminal-tabs.md")

local annexDeclarations = {
	["terminal-tabs"] = "| `terminal-tabs` |",
	["terminal-remote"] = "| `terminal-remote` |",
	["tab-warehouse"] = "| `tab-warehouse` |",
	["warehouse-drop-overlay"] = "| `warehouse-drop-overlay` |",
	["tab-red"] = "| `tab-red` |",
	["tab-options"] = "| `tab-options` |",
	["tab-addons"] = "| `tab-addons` |",
	["tab-programming"] = "| `tab-programming` |",
	["tab-craft"] = "| `tab-craft` |",
	["tab-builder"] = "| `tab-builder` |",
	["terminal-blocked"] = "| `terminal-blocked` |",
}

Support.check(suite, "validated package declares exactly 11 unique surface IDs", function()
	local actual, total = {}, 0
	for surfaceId in html:gmatch('data%-surface%-id="([^"]+)"') do
		assert(not actual[surfaceId], "duplicate HTML surfaceId " .. surfaceId)
		actual[surfaceId] = true
		total = total + 1
	end
	assert(total == 11, "expected 11 surface IDs, got " .. tostring(total))
	for surfaceId in pairs(expectedSurfaces) do
		assert(actual[surfaceId], "HTML missing surfaceId " .. surfaceId)
		contains(annex, assert(annexDeclarations[surfaceId], "missing annex declaration contract " .. surfaceId),
			"annex ownership inventory missing " .. surfaceId)
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
contains(blockedPanel, "UI.Scroll.setOnContentRectChanged",
	"blocked layout misses immediate framework content-rect reflow")
contains(blockedPanel, "UI.Scroll.contentWidth(scroll)",
	"blocked cards bypass the effective framework scroll width")
contains(blockedPanel, "tooltip = tooltip",
	"blocked cards do not opt into the reusable framework info tooltip")
for _, surfacePath in ipairs({
	"GlobalStorageSiK/ui/surfaces/tab-options.surface.json",
	"GlobalStorageSiK/ui/surfaces/tab-warehouse.surface.json",
}) do
	local surfaceText = read(surfacePath)
	excludes(surfaceText, '"name": "x"', surfacePath .. " uses coordinate compensation")
	excludes(surfaceText, '"name": "y"', surfacePath .. " uses coordinate compensation")
end
local items = read(CLIENT .. "GS_TerminalUI_Items.lua")
local network = read(CLIENT .. "GS_TerminalUI_Network.lua")
local nodes = read(CLIENT .. "GS_TerminalUI_Nodes.lua")
local redGeneratedPath = CLIENT .. "GlobalStorageSiK/UI/Generated/TabNetwork.lua"
local redGenerated = assert(dofile(redGeneratedPath), "generated tab-red artifact did not return a table")
local redSurface = assert(redGenerated.surface, "generated tab-red surface missing")
local options = read(CLIENT .. "GS_TerminalUI_Options.lua")
local optionsGeneratedPath = CLIENT .. "GlobalStorageSiK/UI/Generated/TabOptions.lua"
local optionsGeneratedText = read(optionsGeneratedPath)
local optionsGenerated = assert(dofile(optionsGeneratedPath),
	"generated tab-options artifact did not return a table")
local optionsSurface = assert(optionsGenerated.surface, "generated tab-options surface missing")
local terminals = read(CLIENT .. "GS_TerminalUI_NetworkTerminals.lua")
local permissions = read(CLIENT .. "GS_TerminalUI_Permissions.lua")
local admin = read(CLIENT .. "GS_AdminDashboard.lua")
local addons = read(CLIENT .. "GS_TerminalUI_Addons.lua")
local programming = read(CLIENT .. "GS_TerminalUI_Programming.lua")
local extensions = read(CLIENT .. "GS_TerminalUI_Extensions.lua")
local terminalApi = read(CLIENT .. "GSSiK_API_Terminal.lua")
local craft = read("addons/GSSiK_Addon_Craft/Contents/mods/GSSiK_Addon_Craft/42/media/lua/client/GSSiK_Addon_Craft_TerminalUI.lua")
local builder = read("addons/GSSiK_Addon_Builder/Contents/mods/GSSiK_Addon_Builder/42/media/lua/client/GSSiK_Addon_Builder_TerminalUI.lua")

Support.check(suite, "Shell and tab consumers enter through Foundation APIs", function()
	contains(terminal, 'local UI = require "GS_UI_Framework"',
		"Shell bypasses the mandatory standalone framework binding")
	contains(terminal, "UI.Window.apply(self, {", "Shell bypasses Window.apply")
	contains(terminal, "UI.Window.chromeRects(self)", "Shell bypasses Window geometry")
	for _, forbidden in ipairs({ "renderPanelBackground", "renderHeader",
		"renderStatusFooter", "renderWindowFrame", "renderResizeHandle",
		"createCloseButton", "installEscape", "installWheelCapture" }) do
		excludes(terminal, forbidden, "Shell retains product-painted chrome " .. forbidden)
	end
	contains(network, 'require "GS_UI_Framework"',
		"Red bypasses the mandatory framework binding")
	contains(network, 'require "GlobalStorageSiK/UI/Generated/TabNetwork"',
		"Red bypasses its generated surface")
	contains(network, "SiK.UI.SurfaceHost.mount(networkPanel, TabNetworkSpec, {",
		"Red does not mount its generated surface through SurfaceHost")
	contains(network, "followParent = true",
		"Red surface does not follow its final parent geometry")
	contains(items, 'local UI = require "GS_UI_Framework"',
		"Warehouse bypasses the mandatory framework binding")
	contains(items, 'require "GlobalStorageSiK/UI/Generated/TabWarehouse"',
		"Warehouse bypasses its generated Table surface")
	contains(items, "SiK.UI.SurfaceHost.mount(panel, TabWarehouseSpec, {",
		"Warehouse does not mount its generated Table through SurfaceHost")
	contains(items, "followParent = true",
		"Warehouse surface does not follow its final parent geometry")
	contains(api, 'local UI = require "GS_UI_Framework"', "remote/full API bypasses Window")
	contains(blockedApi, 'local UI = require "GS_UI_Framework"', "blocked API bypasses Window")
	return true
end)

Support.check(suite, "table consumers match validated 4 5 4 3 descriptors", function()
	local warehouseColumns = namedTable(items, "ITEM_TABLE_COLUMNS")
	assert(countPlain(warehouseColumns, "key =") == 4,
		"Warehouse column count differs from HTML")
	contains(items, "return itemTableOptions(panel, terminal)",
		"Warehouse does not supply its descriptor to the generated Table")
	local redTable = assert(findNode(redSurface.root, "network-table"),
		"generated Red table missing")
	assert(redTable.type == "table", "generated Red descriptor is not a Table")
	assert(#(redTable.columns or {}) == 5, "Red column count differs from HTML")
	local terminalTable = assert(findNode(optionsSurface.root, "options-terminals-table"),
		"generated terminal table missing")
	local memberTable = assert(findNode(optionsSurface.root, "options-members-table"),
		"generated member table missing")
	assert(terminalTable.type == "table" and #(terminalTable.columns or {}) == 4,
		"Terminals column count differs from HTML")
	assert(memberTable.type == "table" and #(memberTable.columns or {}) == 3,
		"Members column count differs from HTML")
	return true
end)

Support.check(suite, "Block owns the only scrollbar gutter for Lote2 tables", function()
	for name, source in pairs({ Warehouse = items, Options = optionsGeneratedText,
		Red = read(redGeneratedPath) }) do
		excludes(source, "scrollBarWidth()", name .. " reserves scrollbar manually")
		excludes(source, "_gsScrollBarGap", name .. " owns a second scrollbar gap")
		excludes(source, "_gsBarRightPad", name .. " owns a second bar padding")
	end
	local itemOptions = namedTable(items, "ITEM_TABLE_OPTIONS")
	for name, literal in pairs({ Warehouse = itemOptions }) do
		local right = literal:match("right%s*=%s*([%d%.%-]+)")
		assert((not right) or tonumber(right) == 0,
			name .. " table must not reserve a private right gutter")
	end
	return true
end)

local Metrics = Support.loadFrameworkModule(suite, "Metrics")
local Block = Support.loadFrameworkModule(suite, "Block")

Support.check(suite, "runtime rail fills each 76 px cell with the product icon", function()
	local profile = Metrics.profile(0, "terminal")
	assert(profile.window.railWidth == 104, "runtime rail track clips the production icon")
	assert(profile.window.railPadding == 4, "runtime rail inset differs from HTML")
	assert(profile.window.railItemHeight == 76, "runtime rail cell clips the production icon")
	assert(profile.window.railGap == 4, "runtime rail gap differs from HTML")
	contains(tabs, "iconSize = 76", "product rail does not request the full cell extent")
	contains(tabs, 'iconFit = "fill"', "product rail leaves forbidden inner icon margins")
	contains(tabs, "iconPadding = 0", "product rail adds forbidden icon padding")
	return true
end)

Support.check(suite, "Block reserves the canonical gutter only while content overflows", function()
	local tokens = Metrics.tokens()
	local bounds = { x = 0, y = 0, w = 811, h = 500 }
	local short = Block.resolveContentRect(bounds, { scrollable = true, contentHeight = 100 })
	local long = Block.resolveContentRect(bounds, { scrollable = true, contentHeight = 2000 })
	local expectedShortW = bounds.w - tokens.block.padding * 2
	local expectedLongW = expectedShortW - tokens.block.scrollGutter
	assert(short.w == expectedShortW, "short content did not recover the full Block width")
	assert(long.w == expectedLongW, "overflow did not reserve exactly the canonical gutter")
	assert(short.x == long.x, "overflow shifted content axis")
	return true
end)

Support.check(suite, "Options uses the generated Estado then Admin declaration once", function()
	local contextPath = CLIENT .. "GlobalStorageSiK/UI/TabOptionsContext.lua"
	local surface = optionsSurface
	assert(surface.id == "tab-options", "generated tab-options surfaceId changed")
	assert(surface.owner and surface.owner.modulePath:find("GS_TerminalUI_Options.lua", 1, true),
		"generated tab-options owner no longer declares the Options adapter")
	assert(surface.callers and surface.callers[1]
		and surface.callers[1].modulePath:find("GS_TerminalUI.lua", 1, true),
		"generated tab-options declaration no longer identifies the terminal caller")
	local tabNode = assert(findNode(surface.root, "options-root"), "generated Options container missing")
	assert(tabNode.type == "container", "Options root is not the declarative content container")
	local navigation = nil
	for _, capability in ipairs(tabNode.capabilities or {}) do
		if capability.id == "container.navigation" then navigation = capability; break end
	end
	assert(navigation, "Options container does not own its navigation capability")
	assert(#(tabNode.options or {}) == 2, "Options must declare exactly Estado and Admin")
	assert(tabNode.options[1].id == "estado" and tabNode.options[1].contentId == "options-state-content",
		"Estado is not the first declared Options state")
	assert(tabNode.options[2].id == "admin" and tabNode.options[2].contentId == "options-admin-content",
		"Admin is not the second declared Options state")

	contains(options, 'local TabOptionsSpec = require "GlobalStorageSiK/UI/Generated/TabOptions"',
		"Options caller does not load the generated declaration")
	contains(options, 'local TabOptionsContext = require "GlobalStorageSiK/UI/TabOptionsContext"',
		"Options caller does not load its pure context adapter")
	assert(countPlain(options, "SiK.UI.SurfaceHost.mount(") == 1,
		"Options caller must mount its declaration through one SiK.UI SurfaceHost")
	contains(options, "followParent = true",
		"Options surface does not follow its final parent geometry")
	for _, legacy in ipairs({ "TAB_KEYS", "TerminalNetworkList", "TerminalNetworkStatus",
		"TerminalNetworkTerminals", "TerminalPermissions" }) do
		excludes(options, legacy, "Options caller retains legacy composition " .. legacy)
	end

	local context = read(contextPath)
	contains(context, "function TabOptionsContext.create(terminal)", "Options context factory missing")
	contains(context, "function context:snapshot(serverState)", "Options context snapshot missing")
	contains(context, "function context:dispose()", "Options context disposal missing")
	excludes(context, "GS_UI_Framework", "Options context imports the visual framework")
	excludes(context, "buildSurface", "Options context renders instead of supplying plain state")
	return true
end)

Support.check(suite, "Red and Warehouse expose their validated functional regions", function()
	assert(redSurface.id == "tab-red", "generated Red surfaceId changed")
	assert(findNode(redSurface.root, "network-create-actions"), "Red omits zone creation")
	assert(findNode(redSurface.root, "network-table"), "Red omits zones/nodes")
	assert(findNode(redSurface.root, "network-rescan-block"), "Red omits whole-network rescan")
	contains(nodes, "function Nodes.presentationModel", "Red product row projection missing")
	contains(nodes, "function Nodes.tableOptions", "Red Table adapter missing")
	for _, legacy in ipairs({ "embedInNetworkScroll", "ISPanel", "createSectionCard",
		"nodeRowPool", "drawRect(" }) do
		excludes(nodes, legacy, "Red retains legacy/manual nodes composition " .. legacy)
	end
	for _, legacy in ipairs({ "embedInNetworkScroll", "networkRescanBtn",
		"GS_TerminalUI_Scroll" }) do
		excludes(network, legacy, "Red retains legacy composition " .. legacy)
	end
	contains(items, "mainCategoryFilterCombo", "Warehouse family filter missing")
	contains(items, "subCategoryFilterCombo", "Warehouse group filter missing")
	contains(items, "leafCategoryFilterCombo", "Warehouse detail filter missing")
	contains(items, "searchBox", "Warehouse search missing")
	contains(items, "TerminalDrop.setupPanel", "Warehouse drop surface missing")
	excludes(terminal, "yoffset = -2", "Warehouse filters retain local vertical offsets")
	excludes(terminal, "ISComboBox:new(0, y - 2", "Warehouse builds filters off the shared row")
	return true
end)

Support.check(suite, "Admin selectors and variable staff text reflow inside safe geometry", function()
	contains(permissions, "buttonW = math.min(rowW", "Options Add button is not measured first")
	contains(permissions, "local stacked =", "Options Add row has no narrow fallback")
	contains(admin, "UI.Controls.wrapText(sourceLines[i]", "staff info remains fixed-line")
	contains(admin, "UI.Window.resolveBounds({", "staff bypasses the shared viewport")
	contains(admin, "staffColumns", "staff actions have no width-aware composition")
	return true
end)

Support.check(suite, "Addons Programming blocked and remote states keep their owners", function()
	contains(addons, "UI.SurfaceHost.mount", "Addon declarative surface owner missing")
	contains(programming, 'KNOWN_PROGRAM_ORDER = { "network", "uninstall", "driveinstall", "craft", "builder", "tablet" }',
		"Programming Core order differs from HTML")
	contains(tabs, 'applyAccessMode(terminal, mode, blockedState)', "blocked state router missing")
	contains(blockedApi, "ui = GS_TerminalUI:new", "blocked uses another shell")
	contains(blockedPanel, "UI.Block.create({", "blocked compositions bypass the shared Block")
	contains(blockedPanel, 'variant = "section"',
		"blocked titled blocks do not select the canonical section treatment")
	contains(blockedPanel, "contentHost = true",
		"blocked compositions do not request the framework content host")
	for _, forbidden in ipairs({ "drawRect(", "drawRectBorder(", "ISLabel:new(" }) do
		excludes(blockedPanel, forbidden,
			"blocked panel retains product-painted card chrome " .. forbidden)
	end
	contains(api, "resolveShellRect(player)", "remote/full opening bypasses shared shell")
	excludes(tabs, 'tabViews["tablet"]', "Tablet became a tab")
	return true
end)

Support.check(suite, "dynamic addon tabs preserve visibility and parent first construction", function()
	contains(terminalApi, "enabledStateKey = definition.enabledStateKey",
		"public tab registration drops the addon visibility state key")
	contains(extensions, "enabledStateKey = opts.enabledStateKey",
		"Core extension definition drops the addon visibility state key")
	contains(extensions, "state[definition.enabledStateKey] == true",
		"Core cannot restore Craft or Builder visibility from terminal state")
	local destinationAt = assert(extensions:find("setDynamicVisible(terminal, true", 1, true))
	local parentAt = assert(extensions:find("getContentHost(tabKey)", destinationAt, true))
	local panelAt = assert(extensions:find("UI.Controls.panel(parent", parentAt, true))
	local mountAt = assert(extensions:find("def.builder(panel", panelAt, true))
	assert(destinationAt < parentAt and parentAt < panelAt and panelAt < mountAt,
		"addon surface is built before its real navigation parent")
	contains(extensions, "followParent = true",
		"dynamic surface does not follow final parent geometry")
	return true
end)

Support.check(suite, "base surfaces mount only after navigation has final geometry", function()
	contains(terminal, "local shell = UI.Window.chromeRects(terminal)",
		"base tab hosts do not derive their initial size from the final shell")
	contains(terminal, "w = math.max(2, shell.content.w - railW)",
		"base tab hosts can still be born with placeholder width")
	excludes(terminal, "x = 0, y = 0, w = 1, h = 1",
		"a 1 px unmounted geometry sentinel survives in the runtime")
	local navigationAt = assert(terminal:find("GlobalStorageSiK.TerminalTabs.build(self, tabDefs)", 1, true))
	local layoutAt = assert(terminal:find("self:calculateLayout()", navigationAt, true))
	local warehouseAt = assert(terminal:find("self:ensureTabBuilt(tab)", layoutAt, true))
	assert(navigationAt < layoutAt and layoutAt < warehouseAt,
		"warehouse surface is built before its navigation parent has final geometry")
	local addToUiAt = assert(api:find("ui:addToUIManager()", 1, true))
	local deferredStateAt = assert(api:find("applyTerminalState(ui, state, true)", addToUiAt, true))
	assert(addToUiAt < deferredStateAt,
		"initial surface blocks before the shell enters UIManager")
	return true
end)

Support.finish(suite)
