-- Final mounted contract for Opciones > Estado palette cards. This catches
-- regressions where the data exists but the runtime collapses it into plain
-- labels or loses the six validated colour previews.

dofile("../SiKUIFramework-Repo/tests/geometry/pz_ui_stub.lua")
package.path = "../SiKUIFramework-Repo/SiKUIFramework/Contents/mods/SiKUIFramework/42/media/lua/client/?.lua;" .. package.path
dofile("../SiKUIFramework-Repo/SiKUIFramework/Contents/mods/SiKUIFramework/42/media/lua/client/SiK_UI.lua")

local CLIENT = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/"
local artifact = assert(dofile(CLIENT .. "GlobalStorageSiK/UI/Generated/TabOptions.lua"))
local parent = ISPanel:new(0, 0, 1500, 900)
parent:initialise()

local function color(r, g, b) return { r = r, g = g, b = b, a = 1 } end
local palettes = {}
for index = 1, 6 do
	palettes[index] = {
		id = "palette-" .. index, text = "Palette " .. index,
		swatches = { color(0.05 * index, 0.08, 0.10), color(0.10, 0.05 * index, 0.15),
			color(0.20, 0.15, 0.04 * index) },
		selected = index == 1,
	}
end

local state = {
	networkName = { text = "Network" }, selectedNetwork = { items = {}, selected = nil },
	networkSummary = { text = "Summary" }, networkActions = {},
	power = { text = "Power", indicator = true },
	terminalStatus = { text = "Terminal", indicator = true },
	zonesStatus = { text = "Zones", indicator = true },
	accessStatus = { text = "Access", indicator = true },
	resourceSummary = { text = "Resources" }, accessMode = { text = "Physical" },
	consumption = { text = "0" }, capacityAvailable = { text = "Available" },
	capacity = { value = 20, max = 100, percent = 20, unit = "kg" },
	terminalRange = { text = "2" }, networkRange = { text = "8" }, palettes = palettes,
}
local admin = {
	terminalHeaderActions = {}, terminals = {
		{ id = "terminal:1", name = "Cocina", coords = "312, 180, 0", role = "Controlador",
			status = { text = "Presente", color = color(0.45, 0.85, 0.45) } },
	}, memberHeaderActions = {}, members = {
		{ id = "member:1", role = { text = "Propietario", color = color(0.91, 0.63, 0.31) },
			name = "Kava", connection = { text = "Ahora", color = color(0.45, 0.85, 0.45) } },
	},
	successionHint = { text = "" }, backupWarning = { text = "" }, canClaim = { text = "" },
	access = { subject = { items = {}, selected = nil } }, accessActions = {},
}
local actions = {}
for _, id in ipairs({ "options.change-subtab", "options.select-network",
	"options.use-network", "options.refresh-networks", "options.open-terminal",
	"options.open-member", "options.claim-ownership", "options.select-access",
	"options.add-access", "options.change-palette" }) do actions[id] = function() return true end end
local tree, reason = SiK.UI.buildSurface(parent, artifact, {
	locale = "es", playerNum = 0, viewport = { x = 0, y = 0, w = 1500, h = 900 },
	data = { options = { state = state, admin = admin } },
	state = { options = { state = { selectedNetwork = state.selectedNetwork },
		admin = { access = { subject = admin.access.subject } } } },
	conditions = { owner = true, ["owner-without-backup"] = false,
		["can-claim-as-admin"] = false, ["admin-or-owner"] = true,
		["tablet-addon-installed"] = true,
		["add-without-selection"] = false },
	i18n = {
		["options.admin.column.connection"] = "Última conexión",
		["options.admin.access.title"] = "Añadir acceso",
		["options.admin.access.add"] = "Añadir",
	},
	actions = actions, tableOptions = {
		["options-terminals-table"] = { rowHeight = 32, autoHeight = true, minRows = 0 },
		["options-members-table"] = { rowHeight = 32, autoHeight = true, minRows = 0 },
	},
})
assert(tree, reason)

local collection = assert(tree.nodes["options-palette-options"], "palette collection missing")
assert(collection.panel and collection.childParent == collection.panel,
	"palette cards must have one real collection parent")
for _, id in ipairs({ "options-network-block", "options-operational-block",
	"options-resources-block", "options-palette-block", "options-terminals-block",
	"options-members-block" }) do
	local block = assert(tree.nodes[id], "options block missing: " .. id)
	assert(block.panel.drawBackground == true and block.panel.backgroundColor.a > 0
		and block.panel.borderColor.a > 0, "options block lost its SiK frame: " .. id)
end
assert(collection.cards and #collection.cards == 6, "exactly six validated palette cards must be mounted")
assert(collection.columns == 3, "standard Estado layout must keep three palette cards per row")
for index = 1, 6 do
	local card = assert(collection.cards[index], "palette card missing: " .. index)
	assert(card.variant == "palette", "palette item degraded to a generic/plain card")
	assert(type(card.data.swatches) == "table" and #card.data.swatches == 3,
		"palette card lost its three-colour visual preview")
end
local first, second = collection.cards[1].panel, collection.cards[2].panel
assert(second.x - (first.x + first.width) == 8, "palette columns lost the canonical 8 px gap")
local fourth = collection.cards[4].panel
assert(fourth.y - (first.y + first.height) == 8, "palette rows lost the canonical 8 px gap")
assert(collection.contentHeight == first.height * 2 + 8,
	"six palette cards must remain two symmetric rows")
assert(collection.panel.height >= collection.contentHeight,
	"palette collection hitbox must contain its lower row")
assert(collection.cards[6].panel.parent == collection.panel,
	"lower palette row must be parented inside the collection")

local power = assert(tree.nodes["options-power-status"], "power status missing")
local terminal = assert(tree.nodes["options-terminal-status"], "terminal status missing")
local zones = assert(tree.nodes["options-zones-status"], "zones status missing")
local access = assert(tree.nodes["options-access-status"], "access status missing")
assert(power._sikUiControl == "statusIndicator" and terminal._sikUiControl == "statusIndicator"
	and zones._sikUiControl == "statusIndicator" and access._sikUiControl == "statusIndicator",
	"operational dashboard must use the semantic status-dot component")
assert(power.y == terminal.y and zones.y == access.y and zones.y > power.y,
	"operational dashboard must remain a compact two-by-two grid")
assert(terminal.x > power.x and access.x > zones.x,
	"operational dashboard second column collapsed into vertical loose text")

local resource = assert(tree.nodes["options-resource-summary"], "resource summary missing")
local accessMode = assert(tree.nodes["options-resource-access"], "access mode missing")
local consumption = assert(tree.nodes["options-resource-consumption"], "consumption missing")
local availability = assert(tree.nodes["options-resource-capacity-availability"], "capacity availability missing")
assert(resource.y == accessMode.y and consumption.y == availability.y
	and accessMode.x > resource.x and availability.x > consumption.x,
	"resources dashboard must remain a compact two-column grid")
local capacity = assert(tree.nodes["options-capacity"], "capacity bar missing")
local rangeTitle = assert(tree.nodes["options-range-title"], "range title missing")
assert(capacity.width > resource.width and rangeTitle.width > resource.width,
	"capacity and reach summary must span both resource columns")

for _, id in ipairs({ "options-terminals-table", "options-members-table" }) do
	local tableView = assert(tree.nodes[id], "options table missing: " .. id)
	assert(tableView._sikUiComponent == "table", "options data degraded outside SiK Table: " .. id)
	assert(tableView.root.panel.drawBackground == false
		and tableView.root.panel.borderColor.a == 0,
		"embedded options table painted a second frame: " .. id)
	assert(tableView:getHeight() == tableView:getRequiredHeight(),
		"options table retained unexplained space below its real rows: " .. id)
	local content = tableView.root:getContentRect()
	assert(tableView.header.y == content.y,
		"table header does not begin at the Block content origin: " .. id)
	assert(tableView.scroll.viewport.y == tableView.header.y + tableView.header.height,
		"table viewport does not begin immediately below its header: " .. id)
	local row = assert(tableView.list.pool[1], "options representative row missing: " .. id)
	local paints = {}
	row.drawRect = function(_, x, y, w, h)
		paints[#paints + 1] = { x = x, y = y, w = w, h = h }
	end
	row:prerender()
	assert(#paints >= 2 and paints[1].w == row.width and paints[1].h == row.height,
		"options row lost its full SiK surface: " .. id)
	assert(paints[2].y == row.height - 1 and paints[2].h == 1,
		"options row lost its SiK divider: " .. id)
end

local members = assert(tree.nodes["options-members-table"], "members table missing")
assert(members.columns[#members.columns].title == "Última conexión",
	"runtime lost the UTF-8 translated member connection heading")
local accessTitle = assert(tree.nodes["options-access-title"], "access title missing")
assert(accessTitle._sikFullText == "Añadir acceso",
	"runtime lost the UTF-8 translated access section title")
local accessAdd = assert(tree.nodes["options-access-add"], "access add action missing")
assert((accessAdd.title or accessAdd.text) == "Añadir",
	"runtime lost the UTF-8 translated add action")

assert(tree:dispose())
print("options_palette_final_geometry_contract: OK frames, styled tables, UTF-8 labels, six visual cards and symmetric gaps")
