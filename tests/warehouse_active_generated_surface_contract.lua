-- Authorial contract: the live Warehouse tab is a generated SiK.UI surface.
-- Product code owns data/actions only; framework factories own composition,
-- geometry, controls, table, expansion, pagination, tooltip and drag lifecycle.

local CLIENT = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/"

local function read(path)
	local file = assert(io.open(path, "rb"))
	local value = assert(file:read("*a"))
	file:close()
	return value
end

local function contains(value, needle, message)
	assert(string.find(value, needle, 1, true), message or ("missing: " .. needle))
end

local function absent(value, needle, message)
	assert(not string.find(value, needle, 1, true), message or ("forbidden: " .. needle))
end

local terminal = read(CLIENT .. "GS_TerminalUI.lua")
local items = read(CLIENT .. "GS_TerminalUI_Items.lua")
local context = read(CLIENT .. "GlobalStorageSiK/UI/TabWarehouseContext.lua")
local generated = assert(dofile(CLIENT .. "GlobalStorageSiK/UI/Generated/TabWarehouse.lua"))

contains(terminal, "TerminalItems.buildSection(self.itemsPanel, self)")
contains(terminal, "TerminalItems.layoutSection(self.itemsPanel, self")
contains(terminal, "TerminalItems.refreshSection(self.itemsPanel, self, filtered)")
absent(terminal, "UI.Controls.sectionTitle(self.itemsPanel", "Warehouse title must not be hand-painted")
absent(terminal, "UI.Controls.search(self.itemsPanel", "Warehouse search must not be hand-painted")
absent(terminal, "UI.Controls.combo(self.itemsPanel", "Warehouse filters must not be hand-painted")

contains(items, 'require "GlobalStorageSiK/UI/Generated/TabWarehouse"')
contains(items, 'require "GlobalStorageSiK/UI/TabWarehouseContext"')
contains(items, "SiK.UI.SurfaceHost.mount(panel, TabWarehouseSpec, {")
contains(items, "followParent = true", "Warehouse must wait for its final parent geometry")
contains(items, "surface:refresh(snapshot)")
contains(items, "surface:reflow(")
contains(items, "panel._sikWarehouseSurface:dispose()")
contains(items, "TerminalDrop.disposePanel(panel, terminal)")
contains(items, "if panel._sikWarehouseSurface then",
	"Generated Warehouse must retain ownership of its own bounds")
contains(items, "return GlobalStorageSiK.TerminalItems.layoutSection(panel, terminal, panel.width, panel.height)",
	"Post-resize sync must delegate to the generated Warehouse surface")
absent(items, "_gsPager = true", "Warehouse must not inject a second pager row")

assert(generated.surface and generated.surface.id == "tab-warehouse")
assert(generated.frameworkRef and generated.frameworkRef.namespace == "SiK.UI")
assert(generated.provenance and generated.provenance.visualMasterSha256 ==
	"43385818fad1dd71330fd657ed23a4550073c50f1889225e51bb7d96771efda9")

local function find(node, id)
	if type(node) ~= "table" then return nil end
	if node.id == id then return node end
	for i = 1, #(node.children or {}) do
		local found = find(node.children[i], id)
		if found then return found end
	end
	return nil
end

local root = generated.root or (generated.surface and generated.surface.root)
local tableNode = find(root, "warehouse-table")
assert(tableNode and tableNode.type == "table", "Warehouse must expose one framework Table")
assert(not find(root, "warehouse-scroll"), "Table owns its Block/Scroll; outer Scroll is forbidden")
local capabilities = {}
for i = 1, #(tableNode.capabilities or {}) do
	capabilities[tableNode.capabilities[i].id] = true
end
assert(capabilities["table.expandable"], "Warehouse Table must own expandable rows")
assert(capabilities["table.pagination"], "Warehouse Table must own optional child pagination")
assert(capabilities["table.row-interactions"],
	"Warehouse Table must receive product row bridges through one adapter")

contains(context, "function TabWarehouseContext.create(terminal, panel)")
contains(context, "tableOptions")
contains(context, "function context:dispose()")
absent(context, "ISUI/", "Warehouse context must not construct vanilla widgets")
absent(context, "UI.Controls", "Warehouse context must not paint controls")
absent(context, "UI.Table", "Warehouse context must not paint tables")

print("warehouse_active_generated_surface_contract: OK")
