-- Final-rectangle contract for the exact generated Warehouse surface.
-- This deliberately builds the runtime tree: validating JSON/Lua declarations
-- alone previously missed gaps discarded by the concrete child placement.

dofile("../SiKUIFramework-Repo/tests/geometry/pz_ui_stub.lua")
package.path = "../SiKUIFramework-Repo/SiKUIFramework/Contents/mods/SiKUIFramework/42/media/lua/client/?.lua;" .. package.path
dofile("../SiKUIFramework-Repo/SiKUIFramework/Contents/mods/SiKUIFramework/42/media/lua/client/SiK_UI.lua")

local CLIENT = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/"
local uiHandle = assert(io.open(CLIENT .. "GS_TerminalUI.lua", "rb"))
local uiSource = uiHandle:read("*a")
uiHandle:close()
local artifact = assert(dofile(CLIENT .. "GlobalStorageSiK/UI/Generated/TabWarehouse.lua"))
local parent = ISPanel:new(0, 0, 1600, 900)
parent:initialise()

local function noop() return true end
local options = {
	{ id = "", value = "", text = "All" },
	{ id = "one", value = "one", text = "One" },
}
local warehouseRows = {
	{ id = "row:parent", name = "Patatas fritas", category = "Comida", zone = "Varias zonas", count = 12,
		children = { { id = "row:child", name = "Patatas fritas - Original", category = "Comida", zone = "Cocina", count = 5 } } },
}
local tree, reason = SiK.UI.buildSurface(parent, artifact, {
	locale = "es", playerNum = 0,
	viewport = { x = 0, y = 0, w = 1500, h = 800 },
	data = { warehouse = {
		headerActions = { { id = "auto-sort", text = "Auto-sort", onClick = noop } },
		capacity = { value = 81.1, max = 360, unit = "kg", percent = 23 },
		search = { query = "" },
		filters = {
			family = { items = options, selected = "" },
			group = { items = options, selected = "" },
			detail = { items = options, selected = "" },
		},
		rows = { rows = warehouseRows },
	} },
	tableOptions = { ["warehouse-table"] = {} },
	actions = { warehouse = {
		["auto-sort"] = noop, search = noop, ["search-change"] = noop,
		["filter-family"] = noop, ["filter-group"] = noop,
		["filter-detail"] = noop, ["row-activate"] = noop,
	} },
})
assert(tree, reason)

local searchForm = assert(tree.nodes["warehouse-search-form"])
local capacity = assert(tree.nodes["warehouse-capacity"])
local search = assert(tree.nodes["warehouse-search-field"])
local searchButton = assert(tree.nodes["warehouse-search-button"])
local filterForm = assert(tree.nodes["warehouse-filter-form"])
local family = assert(tree.nodes["warehouse-family-filter"])
local group = assert(tree.nodes["warehouse-group-filter"])
local detail = assert(tree.nodes["warehouse-detail-filter"])
local tableView = assert(tree.nodes["warehouse-table"])

assert(capacity._sikUiControl == "progress", "Warehouse capacity must be a SiK progress control")
assert(uiSource:find("self.itemsWeightLbl:setProgress", 1, true),
	"Warehouse capacity alias is not updated through the progress contract")
assert(uiSource:find("inventoryChanged or capacityChanged", 1, true),
	"capacity-only snapshots do not refresh the Warehouse surface")
assert(capacity.y + capacity.height <= searchForm.panel.y,
	"capacity must precede the Warehouse search form without overlap")
assert(searchForm.panel.y + searchForm.panel.height <= filterForm.panel.y,
	"search form must precede Warehouse filters without overlap")
assert(filterForm.panel.y + filterForm.panel.height <= tableView.panel.y,
	"filters must precede the Warehouse table without overlap: filter="
		.. tostring(filterForm.panel.y) .. "+" .. tostring(filterForm.panel.height)
		.. " table=" .. tostring(tableView.panel.y))

assert(search._sikUiControl == "field", "Warehouse search must be SiK field chrome")
assert(searchButton._sikUiControl == "iconButton", "Warehouse search action must be SiK chrome")
assert(family._sikUiComponent == "combo" and group._sikUiComponent == "combo"
	and detail._sikUiComponent == "combo", "all filters must be concrete SiK combos")
assert(searchButton.x - (search.x + search.width) == 8,
	"search field/action final rectangles must preserve the canonical 8 px gap")
assert(group.x - (family.x + family.width) == 8
	and detail.x - (group.x + group.width) == 8,
	"filter final rectangles must preserve both canonical 8 px gaps")
assert(search.x >= 0 and searchButton.x + searchButton.width <= searchForm.panel.width,
	"search controls must stay inside their final parent rectangle")
assert(family.x >= 0 and detail.x + detail.width <= filterForm.panel.width,
	"filter controls must stay inside their final parent rectangle")
assert(tableView._sikUiComponent == "table", "Warehouse rows must use the SiK Table")
assert(tableView.root.panel.drawBackground == false
	and tableView.root.panel.borderColor.a == 0,
	"embedded Warehouse table must not paint a second frame inside its Block")
assert(searchButton.iconSource == "sik.search.18" and searchButton.iconSize == 18,
	"Warehouse search must consume the native pre-sized framework icon")
assert(tableView.header.width == tableView.root:getContentRect().w,
	"table header and rows must consume the same final content rectangle")

local root = assert(tree.nodes["warehouse-root"])
assert(root.panel.drawBackground == true and root.panel.backgroundColor.a > 0
	and root.panel.borderColor.a > 0,
	"Warehouse root must paint the accepted SiK block frame")
local rootRect = root:getContentRect()
assert(tableView.panel.y >= rootRect.y
	and tableView.panel.y + tableView.panel.height <= rootRect.y + rootRect.h,
	"table must remain inside the visible Warehouse block")
local row = assert(tableView.list.pool[1], "representative Warehouse row was not mounted")
local paints = {}
row.drawRect = function(_, x, y, w, h)
	paints[#paints + 1] = { x = x, y = y, w = w, h = h }
end
row:prerender()
assert(#paints >= 2 and paints[1].w == row.width and paints[1].h == row.height,
	"Warehouse rows must paint the complete framework-owned row surface")
assert(paints[2].y == row.height - 1 and paints[2].h == 1,
	"Warehouse rows must paint the canonical divider")
for _, width in ipairs({ 1180, 1900 }) do
	assert(tree:reflow({ x = 0, y = 0, w = width, h = 800 }))
	assert(searchButton.x - (search.x + search.width) == 8,
		"search gap changed after runtime reflow at " .. width)
	assert(group.x - (family.x + family.width) == 8
		and detail.x - (group.x + group.width) == 8,
		"filter gaps changed after runtime reflow at " .. width)
	assert(searchButton.x + searchButton.width <= searchForm.panel.width
		and detail.x + detail.width <= filterForm.panel.width,
		"Warehouse controls overlap or escape after runtime reflow at " .. width)
end
assert(tree:dispose())
print("warehouse_final_geometry_contract: OK final gaps, native icon, frame, styled rows and clipping")
