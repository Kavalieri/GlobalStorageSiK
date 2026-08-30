-- Executable geometry/lifecycle regression for the compact withdrawal preview.
-- This does not emulate PZ hit-testing: it verifies the observable panel rect,
-- pointer preservation, mouse transparency and cleanup against the real module.

for _, name in ipairs({ "GS_NetClient", "GS_WithdrawClient", "GS_ContainerTargets",
	"GS_SiK_UI_EscapeStack", "GS_SiK_UI_Viewport", "GS_I18n", "ISUI/ISPanel" }) do
	package.loaded[name] = true
end

local createdPanels = {}
local dragPath = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/GS_TerminalWithdrawDrag.lua"
local dragHandle = assert(io.open(dragPath, "rb"))
local dragSource = dragHandle:read("*a")
dragHandle:close()
local maxRows = tonumber(dragSource:match("local PREVIEW_MAX_ROWS = (%d+)"))
assert(maxRows and maxRows >= 2, "bounded compact stack row constant missing")
ISPanel = {}
function ISPanel:derive()
	local value = {}
	value.__index = value
	setmetatable(value, { __index = self })
	return value
end
function ISPanel:new(x, y, w, h)
	return setmetatable({ x = x, y = y, width = w, height = h, children = {} },
		{ __index = self })
end
function ISPanel:initialise()
	local owner = self
	self.javaObject = { setConsumeMouseEvents = function(_, value)
		owner.consumesMouse = value == true
	end }
end
function ISPanel:prerender() end
function ISPanel:addChild(child) self.children[#self.children + 1] = child end
function ISPanel:setAlwaysOnTop() end
function ISPanel:addToUIManager()
	self.inManager = true
	createdPanels[#createdPanels + 1] = self
end
function ISPanel:removeFromUIManager() self.inManager = false end
function ISPanel:setX(x) self.x = x end
function ISPanel:setY(y) self.y = y end

local mouseX, mouseY = 200, 150
getMouseX, getMouseY = function() return mouseX end, function() return mouseY end
getCore = function() return {
	getScreenWidth = function() return 400 end,
	getScreenHeight = function() return 300 end,
} end
getPlayerInventory, getPlayerLoot = function() return nil end, function() return nil end
UIFont = { Small = "Small" }
getTextManager = function() return {
	getFontHeight = function() return 20 end,
	MeasureStringX = function(_, _, value) return #tostring(value or "") * 8 end,
} end

local escapeClose = nil
local player = { getPlayerNum = function() return 1 end }
GlobalStorageSiK = {
	NetClient = { getPlayer = function() return player end },
	Log = { debug = function() end },
	I18n = { text = function(key, count)
		if key == "IGUI_GS_DragMoreObjects" then return "+" .. tostring(count) .. " objetos" end
		return key
	end },
	WithdrawClient = { sendWithdraw = function() return true end,
		sendWithdrawBatch = function() return true end },
	ContainerTargets = {},
	SiK_UI = {
		Viewport = { resolve = function(playerNum)
			assert(playerNum == 1, "preview resolved another player's viewport")
			return { x = 0, y = 0, w = 400, h = 300 }
		end },
		PALETTE = { textPrimary = { 1, 1, 1 }, textSecondary = { 0.7, 0.7, 0.7 } },
		truncateText = function(value, maxWidth)
			if #value * 8 <= maxWidth then return value end
			return value:sub(1, math.max(1, math.floor(maxWidth / 8) - 1)) .. "..."
		end,
		EscapeStack = {
			PRIORITY = { TRANSIENT = 400 },
			install = function(panel, close)
				assert(panel.playerNum == 1, "preview registered under wrong player")
				escapeClose = close
			end,
			remove = function() end,
		},
	},
	Client = { registerTransientCleanup = function() return true end },
	TerminalItems = {
		rowHeight = function() return 40 end,
		describeRow = function(row) return {
			data = row, texture = row.texture, name = row.displayName,
			count = tostring(row.count or 0), indicator = row.indicator or ".",
		} end,
		drawRowDescriptor = function() end,
	},
}

dofile(dragPath)

local tooltip = {
	removed = false, visible = true,
	removeFromUIManager = function(self) self.removed = true end,
	setVisible = function(self, value) self.visible = value end,
}
local capture = nil
local terminal = {
	setCapture = function(_, value) capture = value == true end,
}
local source = {
	width = 900, listPanel = {}, terminal = terminal, _gsTooltip = tooltip,
	setCapture = function() error("row must not own terminal drag capture") end,
}
local row = {
	rowKey = "very-long", fullType = "Base.VHSTape", count = 125,
	indicator = ">", texture = "vhs-texture", _gsRowKind = "parent", expandable = true,
	displayName = "A deliberately very long recorded-media title that cannot fit",
}
local childA = { rowKey = "child-a", parentRowKey = "very-long", _gsRowKind = "child",
	fullType = "Base.VHSTape", displayName = "Woodcraft episode 3", count = 2,
	indicator = "L", texture = "vhs-texture" }
local childB = { rowKey = "child-b", parentRowKey = "very-long", _gsRowKind = "child",
	fullType = "Base.VHSTape", displayName = "Exposure Survival episode 5", count = 1,
	indicator = "L", texture = "vhs-texture" }
local exact = { rowKey = "exact", fullType = "Base.Hammer", displayName = "Hammer",
	count = 4, indicator = ".", texture = "hammer-texture" }

assert(GlobalStorageSiK.TerminalWithdrawDrag.begin(row, 1, { row }, { row }, source),
	"compact preview did not start")
local preview = assert(createdPanels[#createdPanels], "compact preview panel missing")
assert(preview.width >= 180 and preview.width <= 300,
	"compact preview width escaped 180..300: " .. tostring(preview.width))
assert(preview.height == 40, "compact preview does not use one canonical ROW_H")
assert(#preview.children == 1, "collapsed parent is not exactly one compact row")
assert(preview.children[1].descriptor.name == row.displayName
	and preview.children[1].descriptor.count == "125"
	and preview.children[1].descriptor.indicator == ">",
	"collapsed row lost icon/name/quantity/group state")
assert(preview.width ~= source.width, "preview copied its source-window width")
	assert(preview.backgroundColor and preview.backgroundColor.a == 0,
		"outer preview adds an opaque table/window background")
assert(preview.consumesMouse == false, "preview consumes mouse events")
assert(tooltip.removed and tooltip.visible == false, "source tooltip remained visible during drag")

GlobalStorageSiK.TerminalWithdrawDrag.cancel()
row.indicator = "v"
assert(GlobalStorageSiK.TerminalWithdrawDrag.begin(row, 1, { row },
	{ row, childA, childB }, source), "expanded-parent preview did not start")
preview = assert(createdPanels[#createdPanels], "expanded compact preview missing")
assert(preview.height == 3 * 40 and #preview.children == 3,
	"expanded parent did not preserve all three compact visual rows")
assert(preview.children[1].descriptor.name == row.displayName
	and preview.children[2].descriptor.name == childA.displayName
	and preview.children[3].descriptor.name == childB.displayName,
	"expanded stack changed original visual order")
assert(preview.children[1].descriptor.indicator == "v"
	and preview.children[2].descriptor.indicator == "L",
	"expanded stack lost row group/detail state")

GlobalStorageSiK.TerminalWithdrawDrag.cancel()
assert(GlobalStorageSiK.TerminalWithdrawDrag.begin(row, 1, { row, exact },
	{ row, exact }, source), "multiselection preview did not start")
preview = assert(createdPanels[#createdPanels], "multiselection compact preview missing")
assert(preview.height == 2 * 40 and #preview.children == 2,
	"multiselection did not preserve every selected compact visual row")
assert(preview.children[1].descriptor.name == row.displayName
	and preview.children[2].descriptor.name == exact.displayName,
	"multiselection stack changed selection order")

GlobalStorageSiK.TerminalWithdrawDrag.cancel()
local many = {}
for i = 1, maxRows + 4 do
	many[i] = { rowKey = "many-" .. i, fullType = "Base.Nails",
		displayName = "Object " .. i, count = i, indicator = "." }
end
assert(GlobalStorageSiK.TerminalWithdrawDrag.begin(many[1], 1, many, many, source),
	"overflow preview did not start")
preview = assert(createdPanels[#createdPanels], "overflow compact preview missing")
assert(#preview.children <= maxRows and #preview.children < #many,
	"overflow stack did not enforce its maximum visible rows")
local overflowRow = preview.children[#preview.children]
local overflowLabel = overflowRow and overflowRow.descriptor and overflowRow.descriptor.name or ""
assert(overflowLabel:find("+", 1, true) and overflowLabel:lower():find("objet", 1, true),
	"overflow stack does not end with localized +N objects indicator")

local function expectPosition(x, y, horizontalSide, verticalSide)
	mouseX, mouseY = x, y
	assert(GlobalStorageSiK.TerminalWithdrawDrag.moveToPointer(), "preview did not move")
	assert(mouseX == x and mouseY == y, "preview placement mutated the real pointer")
	if horizontalSide == "right" then assert(preview.x > x, "preview did not stay right") end
	if horizontalSide == "left" then assert(preview.x + preview.width < x, "preview did not flip left") end
	if verticalSide == "down" then assert(preview.y > y, "preview did not stay below") end
	if verticalSide == "up" then assert(preview.y + preview.height < y, "preview did not flip above") end
	assert(preview.x >= 0 and preview.y >= 0, "preview escaped the screen origin")
	assert(preview.x + preview.width <= 400 and preview.y + preview.height <= 300,
		"preview was not clipped to the visible screen")
end

expectPosition(5, 5, "right", "down")
expectPosition(395, 5, "left", "down")
expectPosition(5, 295, "right", "up")
expectPosition(395, 295, "left", "up")
expectPosition(200, 295, "right", "up")

assert(type(escapeClose) == "function", "Escape callback missing")
escapeClose()
assert(capture == false, "Escape retained terminal capture")
assert(preview.inManager == false, "Escape retained compact preview")
assert(not GlobalStorageSiK.TerminalWithdrawDrag.isActive(), "Escape retained payload")

print("drag_compact_preview_regression: OK")
