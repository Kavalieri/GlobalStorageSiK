-- Final mounted contract for the accepted Red surface.  This exercises the
-- concrete framework widgets so a declarative table or Block cannot pass while
-- rendering as an unframed vanilla-looking panel at runtime.

dofile("../SiKUIFramework-Repo/tests/geometry/pz_ui_stub.lua")
package.path = "../SiKUIFramework-Repo/SiKUIFramework/Contents/mods/SiKUIFramework/42/media/lua/client/?.lua;" .. package.path
dofile("../SiKUIFramework-Repo/SiKUIFramework/Contents/mods/SiKUIFramework/42/media/lua/client/SiK_UI.lua")

local CLIENT = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/"
local artifact = assert(dofile(CLIENT .. "GlobalStorageSiK/UI/Generated/TabNetwork.lua"))
local parent = ISPanel:new(0, 0, 1600, 900)
parent:initialise()
local function noop() return true end
local rows = {
	{ id = "zone:cocina", name = "Cocina · 3", protocol = "Comida y bebida › Perecederos",
		priority = 20, status = "OK", occupancy = "54%", children = {
			{ id = "node:nevera", name = "Nevera cocina", protocol = "Comida y bebida › Verduras",
				priority = 30, status = "OK", occupancy = "68%" },
		} },
}
local actions = {}
for _, id in ipairs({ "network.create-room", "network.create-building",
	"network.create-selection", "network.activate-row", "network.rescan" }) do
	actions[id] = noop
end
local tree, reason = SiK.UI.buildSurface(parent, artifact, {
	locale = "es", playerNum = 0, viewport = { x = 0, y = 0, w = 1500, h = 800 },
	data = { network = {
		headerActions = {}, createRoom = {}, createBuilding = {}, createSelection = {},
		rows = { rows = rows }, rescanHeaderActions = {},
		rescanFeedback = { text = "Una incidencia", severity = "warning" },
		scanProgress = { value = 0.5, max = 1, label = "Escaneando" },
		rescanAction = {},
	} },
	conditions = { ["network-rescan-visible"] = true,
		["network-rescan-has-incident"] = true, ["network-scan-running"] = true },
	actions = actions,
})
assert(tree, reason)

for _, id in ipairs({ "network-root", "network-rescan-block" }) do
	local block = assert(tree.nodes[id], "network block missing: " .. id)
	assert(block.panel.drawBackground == true and block.panel.backgroundColor.a > 0
		and block.panel.borderColor.a > 0, "network block lost its SiK frame: " .. id)
end
local tableView = assert(tree.nodes["network-table"])
assert(tableView._sikUiComponent == "table", "Red rows must use the SiK Table")
local row = assert(tableView.list.pool[1], "representative Red row was not mounted")
local paints = {}
row.drawRect = function(_, x, y, w, h)
	paints[#paints + 1] = { x = x, y = y, w = w, h = h }
end
row:prerender()
assert(#paints >= 2 and paints[1].w == row.width and paints[1].h == row.height,
	"Red rows must paint a complete framework-owned surface")
assert(paints[2].y == row.height - 1 and paints[2].h == 1,
	"Red rows must paint the canonical divider")
assert(tableView.header.width == tableView.block:getContentRect().w,
	"Red header and rows must share the same final content rectangle")
local progress = assert(tree.nodes["network-rescan-progress"])
assert(progress._sikUiControl == "progress", "network scan must mount the framework progress control")
assert(tree:dispose())
print("network_final_geometry_contract: OK frames, styled expandable rows, aligned columns and scan progress")
