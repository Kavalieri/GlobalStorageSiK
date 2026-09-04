-- Regression contract: tab-options and tab-red declare their tables in the
-- generated surface and mount them once through public SiK.UI.SurfaceHost.

local function readFile(path)
	local handle = assert(io.open(path, "rb"), "cannot read " .. path)
	local text = handle:read("*a")
	handle:close()
	return text
end

local function countNodesByType(node, wanted)
	if type(node) ~= "table" then return 0 end
	local total = node.type == wanted and 1 or 0
	for index = 1, #(node.children or {}) do
		total = total + countNodesByType(node.children[index], wanted)
	end
	return total
end

local root = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/"
local loaderSource = readFile(root .. "GS_UI_Framework.lua")
local optionsSource = readFile(root .. "GS_TerminalUI_Options.lua")
local optionsArtifact = assert(dofile(root .. "GlobalStorageSiK/UI/Generated/TabOptions.lua"))
local networkSource = readFile(root .. "GS_TerminalUI_Network.lua")
local networkArtifact = assert(dofile(root .. "GlobalStorageSiK/UI/Generated/TabNetwork.lua"))
local staffSource = readFile(root .. "GS_AdminDashboard.lua")
local itemsSource = readFile(root .. "GS_TerminalUI_Items.lua")
local warehouseArtifact = assert(dofile(root .. "GlobalStorageSiK/UI/Generated/TabWarehouse.lua"))

assert(loaderSource:find('pcall(require, "SiK_UI")', 1, true),
	"GS_UI_Framework must guard the mandatory external framework load")
assert(loaderSource:find("return SiK.UI", 1, true),
	"GS_UI_Framework must return the public SiK.UI namespace")
assert(loaderSource:find("SiKUIFramework", 1, true) and loaderSource:find("error(", 1, true),
	"missing framework must fail explicitly and identify its ModID")
assert(not loaderSource:find("GlobalStorageSiK.SiK_UI", 1, true),
	"strict loader must not publish a private compatibility namespace")

assert(staffSource:find('local UI = require "GS_UI_Framework"', 1, true),
	"Staff Admin must import the strict product binding")
assert(staffSource:find("UI.Table.create({", 1, true),
	"Staff Admin members must use the same public Table.create constructor")
for _, forbidden in ipairs({
	'GS_SiK_UI_Table', "Table.createBlock", "Table.createVirtual",
	"drawTableRowBackground", "Table.drawHeader", "Table.attachHeaderResize",
}) do
	assert(not staffSource:find(forbidden, 1, true),
		"Staff Admin retains private or locally painted table path " .. forbidden)
end

assert(optionsArtifact.surface and optionsArtifact.surface.id == "tab-options",
	"tab-options generated declaration is missing")
assert(countNodesByType(optionsArtifact.surface.root, "table") == 2,
	"tab-options must declare exactly its terminal and member public Tables")
assert(optionsSource:find('require "GlobalStorageSiK/UI/Generated/TabOptions"', 1, true)
	and optionsSource:find('require "GlobalStorageSiK/UI/TabOptionsContext"', 1, true),
	"tab-options must consume its generated declaration and pure context")
assert(optionsSource:find("SiK.UI.SurfaceHost.mount(", 1, true)
	and optionsSource:find("followParent = true", 1, true),
	"tab-options must mount through a host that waits for final parent geometry")
assert(optionsSource:find("panel._sikOptionsSurface:dispose()", 1, true)
	and optionsSource:find("panel._sikOptionsContext:dispose()", 1, true),
	"tab-options must dispose both the generated surface and its context")
assert(optionsSource:find('SURFACE_ID = "tab-options"', 1, true),
	"Options must expose only the canonical tab-options surface id")
for _, forbidden in ipairs({ "TerminalNetworkStatus", "TerminalNetworkTerminals",
	"TerminalPermissions", "UI.Table.create", "drawTableRowBackground" }) do
	assert(not optionsSource:find(forbidden, 1, true),
		"tab-options retains a manual table/composition path " .. forbidden)
end
for _, alias in ipairs({ "terminal-tabs", "options-tab", "tab-options-admin",
	"tab-options-status" }) do
	assert(not optionsSource:find('"' .. alias .. '"', 1, true),
		"tab-options must not retain surface alias " .. alias)
end

assert(networkArtifact.surface and networkArtifact.surface.id == "tab-red",
	"tab-red generated declaration is missing")
assert(countNodesByType(networkArtifact.surface.root, "table") == 1,
	"tab-red must declare exactly its zones/nodes public Table")
assert(networkSource:find('require "GlobalStorageSiK/UI/Generated/TabNetwork"', 1, true)
	and networkSource:find('require "GlobalStorageSiK/UI/TabNetworkContext"', 1, true),
	"tab-red must consume its generated declaration and pure context")
assert(networkSource:find("SiK.UI.SurfaceHost.mount(", 1, true)
	and networkSource:find("followParent = true", 1, true),
	"tab-red must mount through a host that waits for final parent geometry")
for _, forbidden in ipairs({ "UI.Table.create", "ISScrollingListBox:new",
	"TerminalNetworkList", "TerminalNetworkStatus", "drawTableRowBackground",
	"Table.drawHeader", "Table.attachHeaderResize" }) do
	assert(not networkSource:find(forbidden, 1, true),
		"tab-red retains a manual table/composition path " .. forbidden)
end

assert(itemsSource:find('local UI = require "GS_UI_Framework"', 1, true),
	"Warehouse must import the strict product binding")
assert(countNodesByType(warehouseArtifact.surface.root, "table") == 1,
	"Warehouse must declare exactly one generated public Table")
assert(itemsSource:find("function GlobalStorageSiK.TerminalItems.tableOptions", 1, true),
	"Warehouse must adapt product interactions through tableOptions")
assert(itemsSource:find('selectionMode = "multiple"', 1, true),
	"Warehouse multi-selection must be declared on the shared table")
assert(itemsSource:find("expansion = {", 1, true)
	and itemsSource:find("hasChildren = function", 1, true),
	"Warehouse lazy expansion must be a Table feature")
assert(not itemsSource:find("UI.Table.create({", 1, true),
	"Warehouse must not construct a second product-local Table")
for _, forbidden in ipairs({
	"GlobalStorageSiK.SiK_UI", "GS_SiK_UI_Table", "GS_SiK_UI_TableExpansion",
	"Table.createVirtual", "columnHeader", "itemScroll", "createItemRow",
}) do
	assert(not itemsSource:find(forbidden, 1, true),
		"Warehouse retains a private or locally composed table path " .. forbidden)
end

print("ui_table_composition_regression: OK")
