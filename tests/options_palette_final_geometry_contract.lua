-- Final mounted contract for the single Opciones surface. This catches
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
	power = { text = "Power", tone = "success", indicator = true },
	terminalStatus = { text = "Terminal", indicator = true },
	zonesStatus = { text = "Zones", indicator = true },
	accessStatus = { text = "Access", indicator = true },
	resourceSummary = { text = "Resources" }, accessMode = { text = "Physical" },
	consumption = { text = "0" }, capacityAvailable = { text = "Available" },
	capacity = { value = 20, max = 100, percent = 20, unit = "kg" },
	terminalRange = { text = "2" }, networkRange = { text = "40" },
	antennaRange = { text = "8" }, palettes = palettes,
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
for index = 2, 4 do
	admin.terminals[index] = { id = "terminal:" .. index, name = "Terminal " .. index,
		coords = index .. ", " .. index .. ", 0", role = "Secundario",
		status = { text = "Presente", color = color(0.45, 0.85, 0.45) } }
	admin.members[index] = { id = "member:" .. index,
		role = { text = "Miembro", color = color(0.91, 0.63, 0.31) },
		name = "Jugador " .. index,
		connection = { text = "Ahora", color = color(0.45, 0.85, 0.45) } }
end
local actions = {}
for _, id in ipairs({ "options.select-network",
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
for _, id in ipairs({ "options-network-block", "options-summary-block",
	"options-information-card", "options-energy-card", "options-range-card",
	"options-palette-block", "options-terminals-block", "options-members-block" }) do
	local block = assert(tree.nodes[id], "options block missing: " .. id)
	assert(block.panel.drawBackground == true and block.panel.backgroundColor.a > 0
		and block.panel.borderColor.a > 0, "options block lost its SiK frame: " .. id)
end
assert(collection.cards and #collection.cards == 6, "exactly six validated palette cards must be mounted")
assert(collection.columns == 3, "standard Options layout must keep three palette cards per row")
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
local terminal = assert(tree.nodes["options-info-terminals"], "terminal count missing")
local zones = assert(tree.nodes["options-info-zones"], "zone count missing")
local containers = assert(tree.nodes["options-info-containers"], "container count missing")
local membersCount = assert(tree.nodes["options-info-members"], "member count missing")
assert(power._sikUiControl == "statusIndicator",
	"power state must retain its semantic status indicator")
local powerPaint = {}
power.drawRect = function(_, x, y, w, h, a, r, g, b)
	powerPaint.dot = { r = r, g = g, b = b, a = a }
end
power.drawText = function(_, text, x, y, r, g, b, a)
	powerPaint.text = { text = text, r = r, g = g, b = b, a = a }
end
power:prerender()
assert(powerPaint.dot and powerPaint.text, "power indicator did not paint dot and text")
assert(powerPaint.dot.g ~= powerPaint.text.g or powerPaint.dot.r ~= powerPaint.text.r,
	"power status still paints the complete message with the semaphore colour")
local summaryCards = assert(tree.nodes["options-summary-cards"], "summary cards grid missing")
assert(summaryCards.options and summaryCards.options.padding == 0,
	"summary card grid retains an extra container padding above and below its cards")
local informationHost = assert(tree.nodes["options-information-host"],
	"information geometry host missing")
assert(informationHost.options and informationHost.options.padding == 0,
	"information host adds a second inset outside the canonical Block padding")
local function isSemanticStatus(control)
	return control._sikUiControl == "status"
		or control._sikUiControl == "statusIndicator"
end
assert(isSemanticStatus(terminal) and isSemanticStatus(zones)
	and isSemanticStatus(containers) and isSemanticStatus(membersCount),
	"information counts must use the compact semantic status control")
assert(terminal.y == zones.y and zones.y == containers.y and containers.y == membersCount.y,
	"information counts must remain one horizontal row in the standard profile")
assert(terminal.x < zones.x and zones.x < containers.x and containers.x < membersCount.x,
	"information counts lost their validated order")

local capacity = assert(tree.nodes["options-capacity"], "capacity bar missing")
assert(capacity.width > terminal.width,
	"capacity bar must span the full information card above the count row")
local terminalRange = assert(tree.nodes["options-terminal-range"], "terminal range missing")
local networkRange = assert(tree.nodes["options-network-range"], "network range missing")
local antennaRange = assert(tree.nodes["options-antenna-range"], "antenna range missing")
assert(terminalRange.y == networkRange.y and networkRange.x > terminalRange.x,
	"configured range lost its two-column first row")
assert(antennaRange.y > terminalRange.y,
	"WiFi range must remain below the first configured-range row")

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

local terminalsBlock = assert(tree.nodes["options-terminals-block"])
local terminalsTable = assert(tree.nodes["options-terminals-table"])
local membersBlock = assert(tree.nodes["options-members-block"])
local membersTableView = assert(tree.nodes["options-members-table"])
local function assertContained(block, tableView, label)
	local content = block:getContentRect()
	local bounds = tableView:getBounds()
	assert(bounds.x >= content.x and bounds.y >= content.y
		and bounds.x + bounds.w <= content.x + content.w
		and bounds.y + bounds.h <= content.y + content.h,
		label .. " table escaped its dynamic Block")
end
assertContained(terminalsBlock, terminalsTable, "Terminales")
assertContained(membersBlock, membersTableView, "Miembros")
assert(terminalsBlock.y + terminalsBlock.h <= membersBlock.y,
	"Terminales Block overlaps Miembros Block")

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
