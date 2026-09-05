-- Public SiK.UI framework composition contract.
--
-- Static author-side gate: it verifies the product consumes only the public
-- facade and that table, block and scroll geometry have one framework owner.

local Support = dofile("tests/helpers/sik_ui_contract_support.lua")
local suite = Support.newSuite("sik_ui_framework_contract")

local CLIENT = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/"
local FRAMEWORK = "../SiKUIFramework-Repo/SiKUIFramework/Contents/mods/"
	.. "SiKUIFramework/42/media/lua/client/SiK/UI/"

local function read(path)
	local handle = assert(io.open(path, "rb"), "cannot read " .. path)
	local source = handle:read("*a")
	handle:close()
	return source
end

local function contains(source, needle, label)
	assert(source:find(needle, 1, true), label or ("missing " .. needle))
end

local function excludes(source, needle, label)
	assert(not source:find(needle, 1, true), label or ("unexpected " .. needle))
end

local function countPlain(source, needle)
	local count, cursor = 0, 1
	while true do
		local found = source:find(needle, cursor, true)
		if not found then return count end
		count = count + 1
		cursor = found + #needle
	end
end

local facade = read(CLIENT .. "GS_UI_Framework.lua")
local network = read(CLIENT .. "GS_TerminalUI_Network.lua")
local nodes = read(CLIENT .. "GS_TerminalUI_Nodes.lua")
local zones = read(CLIENT .. "GS_TerminalUI_NetworkZones.lua")
local networkSurface = read(CLIENT .. "GlobalStorageSiK/UI/Generated/TabNetwork.lua")
local metrics = read(FRAMEWORK .. "Metrics.lua")
local block = read(FRAMEWORK .. "Block.lua")
local scroll = read(FRAMEWORK .. "Scroll.lua")
local virtualList = read(FRAMEWORK .. "VirtualList.lua")
local tableSource = read(FRAMEWORK .. "Table.lua")

Support.check(suite, "GS facade is strict and returns SiK.UI", function()
	contains(facade, 'pcall(require, "SiK_UI")',
		"facade must guard the standalone framework load")
	contains(facade, "return SiK.UI", "facade must return the public namespace")
	contains(facade, "SiKUIFramework mod", "missing dependency must fail explicitly")
	excludes(facade, "GlobalStorageSiK.SiK_UI", "facade must not publish a product alias")
	excludes(facade, "GS_SiK_UI_", "facade must not load private product modules")
	return true
end)

Support.check(suite, "public Table.create owns complete composition", function()
	assert(countPlain(tableSource, "function Table.create(") == 1,
		"Table.create must be the single public table constructor")
	excludes(tableSource, "function Table.createBlock", "createBlock is obsolete")
	excludes(tableSource, "function Table.createVirtual", "createVirtual is not a public table API")
	contains(tableSource, "options.block", "Table must consume the caller-owned Block")
	contains(tableSource, "Block.resolveViewportRect", "Table must delegate viewport geometry to Block")
	contains(tableSource, "Scroll.create", "Table must delegate scroll ownership")
	contains(tableSource, "VirtualList.create", "Table must delegate row pooling")
	contains(tableSource, "block:getContentRect()", "header/body must consume the Block rect")
	contains(tableSource, "function TableInstance:dispose", "Table lifecycle must be disposable")
	assert(countPlain(block, "function Block.create(") == 1, "Block.create must have one owner")
	assert(countPlain(scroll, "function Scroll.create(") == 1, "Scroll.create must have one owner")
	assert(countPlain(virtualList, "function VirtualList.create(") == 1,
		"VirtualList.create must have one owner")
	return true
end)

Support.check(suite, "Block is sole dynamic gutter owner", function()
	contains(metrics, "function Metrics.blockRects", "Metrics must calculate canonical block rects")
	contains(block, "SiK.UI.Metrics.blockRects", "Block must consume canonical rects")
	contains(block, "self.contentHeight > baseContent.h", "Block must derive overflow")
	contains(block, "self.scroll:setGeometry(self.contentRect, self.trackRect)",
		"Block must push one shared rect to Scroll")
	excludes(tableSource, "scrollGutter", "Table must not reserve a gutter")
	excludes(tableSource, "scrollBarWidth", "Table must not know scrollbar width")
	excludes(tableSource, "scrollBarGap", "Table must not know scrollbar gap")
	return true
end)

Support.check(suite, "retired TerminalScroll has no product owner or consumer", function()
	local legacyPath = CLIENT .. "GS_TerminalUI_Scroll.lua"
	local handle = io.open(legacyPath, "rb")
	if handle then handle:close() end
	assert(not handle, "retired TerminalScroll module still exists")
	for name, source in pairs({ Nodes = nodes, Zones = zones }) do
		excludes(source, "GS_TerminalUI_Scroll", name .. " still requires retired TerminalScroll")
		excludes(source, "TerminalScroll.", name .. " still calls retired TerminalScroll")
	end
	return true
end)

Support.check(suite, "tab-red surface owns expandable Table without child pagination", function()
	contains(network, 'require "GS_UI_Framework"', "tab-red adapter must load the public facade")
	contains(network, "SiK.UI.SurfaceHost.mount(networkPanel, TabNetworkSpec, {",
		"tab-red adapter must mount its generated surface through SurfaceHost")
	contains(network, "followParent = true",
		"tab-red surface must follow its final parent geometry")
	contains(networkSurface, '["type"] = "table"', "generated surface must declare a table")
	contains(networkSurface, '["variant"] = "hierarchical"',
		"generated surface must declare hierarchical rows")
	contains(networkSurface, '["name"] = "child-pagination"',
		"generated surface must declare child pagination behavior")
	contains(networkSurface, '["value"] = false',
		"expanded node children must use continuous scrolling")
	contains(nodes, "children = children", "zone presentation must expose complete children")
	contains(nodes, "function Nodes.tableOptions", "product adapter must expose row interactions")
	excludes(nodes, "pagination =", "Nodes must not paginate expanded children")
	excludes(nodes, 'require "GS_UI_Framework"', "data adapter must not construct UI")
	excludes(nodes, 'require "GS_SiK_UI_', "Nodes must not import private UI modules")
	excludes(nodes, "GlobalStorageSiK.SiK_UI", "Nodes must not consume the old namespace")
	excludes(nodes, "createNodeRow", "manual node row renderer must be removed")
	excludes(nodes, "nodeRowPool", "manual node pool must be removed")
	excludes(nodes, "ensureColumnHeader", "manual node header must be removed")
	excludes(nodes, "ensureNodeScroll", "manual node scroll must be removed")
	excludes(nodes, "updateVirtualRows", "manual node pool refresh must be removed")
	excludes(nodes, "nodesListPanel", "Nodes must not wrap Table in a local table host")
	excludes(nodes, "terminal.nodesScroll", "public Table scroll must not leak as legacy scroll")
	excludes(nodes, "drawCardBackground", "Table must own its own block chrome")
	return true
end)

Support.check(suite, "Network zones remain a pure action adapter", function()
	contains(zones, "function Zones.create", "Network zones must expose create actions")
	contains(zones, "function Zones.rescanNetwork", "Network zones must expose rescan actions")
	excludes(zones, 'require "GS_UI_Framework"', "Network zones must not construct UI")
	excludes(zones, "pagination =", "Network zones must retain continuous scrolling")
	excludes(zones, "zoneTableMount", "Network zones must not add a local table mount")
	excludes(zones, "zoneTableHost", "Network zones must not expose the internal Block panel")
	excludes(zones, "updateVirtualRows", "legacy table refresh alias must be removed")
	excludes(zones, 'require "GS_SiK_UI_', "Network zones must not import private UI")
	excludes(zones, "GlobalStorageSiK.SiK_UI", "Network zones must not consume the old namespace")
	return true
end)

Support.finish(suite)
