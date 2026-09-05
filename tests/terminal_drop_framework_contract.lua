-- Focal contract for terminal deposit drop migration to public SiK UI.
-- It preserves the product transfer path while reducing PZ widgets to stubs.

for _, name in ipairs({ "GS_I18n", "GS_Log", "GS_NetClient", "GS_DepositClient" }) do
	package.loaded[name] = true
end

local tickHandler, tickRemoveCount = nil, 0
Events = { OnTick = {
	Add = function(callback) tickHandler = callback end,
	Remove = function(callback)
		assert(callback == tickHandler, "framework removed another tick handler")
		tickHandler = nil; tickRemoveCount = tickRemoveCount + 1
	end,
} }

local attached, copied = {}, {}
local publicUI = {
	DropTarget = {
		attach = function(control, options)
			attached[#attached + 1] = { control = control, options = options }
			return { control = control, dispose = function() return true end }
		end,
		monitor = function(control, options)
			local handle = { control = control, options = options }
			Events.OnTick.Add(function()
				if options.isDragging() then
					handle.pending = options.payload()
				elseif handle.pending then
					local value = handle.pending; handle.pending = nil
					if options.isOver() then options.onDrop(value) end
				end
			end)
			return handle
		end,
	},
	Controls = {
		copyText = function(parent, options)
			local value = { parent = parent, options = options }
			copied[#copied + 1] = value
			return value
		end,
	},
}
package.loaded["GS_UI_Framework"] = publicUI

local now = 1000
local draggedItems = {}
local canDeposit = true
local clearCount, sent = 0, {}

GlobalStorageSiK = {
	I18n = { text = function(key) return key end },
	Log = { debug = function() end },
	DepositClient = {
		collectDraggedItems = function() return draggedItems end,
		isDraggingItems = function() return #draggedItems > 0 end,
		canDepositDraggedItems = function() return canDeposit end,
		collectItemIds = function(items)
			local ids = {}
			for index = 1, #items do ids[index] = items[index].id end
			return ids
		end,
		clearDrag = function()
			clearCount = clearCount + 1
			ISMouseDrag.dragging = nil
			draggedItems = {}
		end,
		sendDepositItems = function(ids)
			sent[#sent + 1] = ids
			return true
		end,
	},
	TerminalUI = {},
}

local terminal = {
	playerNum = 2,
	x = 100, y = 50, width = 500, height = 400,
	getIsVisible = function() return true end,
	isMouseOver = function() return true end,
	getX = function(self) return self.x end,
	getY = function(self) return self.y end,
	getWidth = function(self) return self.width end,
	getHeight = function(self) return self.height end,
}
GlobalStorageSiK.TerminalUI.instance = terminal

ISMouseDrag = { dragging = nil }
getMouseX, getMouseY = function() return 120 end, function() return 80 end
getTimestampMs = function() return now end

local sourcePath = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/GS_TerminalDrop.lua"
dofile(sourcePath)

local panel = { x = 0, y = 0, width = 320, height = 240, playerNum = 2,
	getIsVisible = function() return true end,
	isMouseOver = function() return true end,
	getX = function(self) return self.x end,
	getY = function(self) return self.y end,
	getWidth = function(self) return self.width end,
	getHeight = function(self) return self.height end }
GlobalStorageSiK.TerminalDrop.setupPanel(panel, terminal)
assert(#attached == 1 and attached[1].control == panel,
	"setupPanel did not attach the public DropTarget")
assert(panel.gsDropTarget ~= nil and panel.gsDropTerminal == terminal,
	"setupPanel did not retain its framework handle or terminal context")
assert(panel.gsDropMonitor ~= nil and terminal.gsDropMonitor == nil and type(tickHandler) == "function",
	"external drag monitor was not owned by its exact drop surface")
assert(attached[1].options.playerNum == 2 and attached[1].options.tone == "info",
	"DropTarget lost player or feedback tone")
GlobalStorageSiK.TerminalDrop.setupPanel(panel, terminal)
assert(#attached == 1, "setupPanel attached the same panel twice")

local itemA, itemB = { id = 41 }, { id = 42 }
draggedItems = { itemA, itemB }
local session = attached[1].options.dragProvider()
assert(session and session.payload == draggedItems,
	"drag provider did not preserve the exact dragged item collection")
assert(attached[1].options.accept(session.payload) == true,
	"valid vanilla drag was rejected")
canDeposit = false
assert(attached[1].options.accept(session.payload) == false,
	"product source validation was bypassed")
canDeposit = true

assert(attached[1].options.onDrop(session.payload) == true,
	"DropTarget did not enter the existing deposit route")
assert(clearCount == 1 and #sent == 1 and sent[1][1] == 41 and sent[1][2] == 42,
	"DropTarget changed drag cleanup, IDs or request count")

now = 2000
draggedItems = { { id = 77 } }
ISMouseDrag.dragging = { draggedItems[1] }
tickHandler()
ISMouseDrag.dragging = nil
tickHandler()
assert(clearCount == 2 and #sent == 2 and sent[2][1] == 77,
	"terminal-wide release fallback no longer deposits exactly once")

local hintParent = { width = 300, playerNum = 2 }
local hint = GlobalStorageSiK.TerminalDrop.createHintLabel(hintParent, 12, 7)
assert(hint == copied[1] and copied[1].parent == hintParent,
	"hint did not use the public Controls constructor")
assert(copied[1].options.text == "IGUI_GS_DropHint"
	and copied[1].options.tone == "textMuted"
	and copied[1].options.w == 288,
	"hint text, tone or available width changed")

local source = assert(io.open(sourcePath, "rb")):read("*a")
for _, forbidden in ipairs({ "ISLabel", ".prerender", "drawRect(", "drawRectBorder" }) do
	assert(not source:find(forbidden, 1, true),
		"local UI primitive remains in GS_TerminalDrop: " .. forbidden)
end
assert(source:find("UI.DropTarget.attach", 1, true), "public DropTarget is not used")
assert(source:find("UI.DropTarget.monitor", 1, true), "public drag monitor is not used")
assert(source:find("UI.Controls.copyText", 1, true), "public Controls hint is not used")
assert(not source:find("Events.OnTick", 1, true), "product retains a permanent tick hook")

print("terminal_drop_framework_contract: OK")
