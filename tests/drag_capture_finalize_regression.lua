-- Executable author regression for one-shot drag finalization and cleanup.
-- PZ widgets are reduced to lifecycle-compatible stubs; transfer authority is
-- not simulated, only the exact client request count and capture ownership.

for _, name in ipairs({ "GS_NetClient", "GS_DepositSources", "GS_WithdrawClient",
	"GS_ContainerTargets", "GS_I18n", "GS_SiK_UI_EscapeStack", "GS_SiK_UI_Viewport",
	"ISUI/ISPanel" }) do
	package.loaded[name] = true
end

ISPanel = {}
function ISPanel:derive()
	local value = {}
	value.__index = value
	setmetatable(value, { __index = self })
	return value
end
function ISPanel:new(x, y, w, h)
	return setmetatable({ x = x, y = y, width = w, height = h, children = {} }, { __index = self })
end
function ISPanel:initialise() end
function ISPanel:prerender() end
function ISPanel:addChild(child) self.children[#self.children + 1] = child end
function ISPanel:setAlwaysOnTop() end
function ISPanel:addToUIManager() self.inManager = true end
function ISPanel:removeFromUIManager() self.inManager = false end
function ISPanel:setX(x) self.x = x end
function ISPanel:setY(y) self.y = y end

local escapeClose, transientCleanup = nil, nil
local sent, destinationAvailable, destinationKey = {}, true, "player:main"
local logEvents = {}
local player = { getPlayerNum = function() return 0 end }
GlobalStorageSiK = {
	NetClient = { getPlayer = function() return player end },
	WithdrawClient = {
		sendWithdraw = function(row, amount, key)
			sent[#sent + 1] = { mode = "one", row = row, amount = amount, key = key }
			return true
		end,
		sendWithdrawBatch = function(rows, amount, key)
			sent[#sent + 1] = { mode = "batch", rows = rows, amount = amount, key = key }
			return true
		end,
	},
	ContainerTargets = {
		findPaneAtMouse = function() return destinationAvailable and {} or nil end,
		getPaneContainer = function() return {} end,
                canReceiveWithdraw = function() return true end,
                keyForContainer = function() return destinationKey end,
                debugDropTarget = function() end,
	},
	SiK_UI = { Viewport = { resolve = function()
		return { x = 0, y = 0, w = 1280, h = 720 }
	end }, EscapeStack = {
		PRIORITY = { TRANSIENT = 400 },
		install = function(_, close) escapeClose = close end,
		remove = function() end,
	} },
	Client = { registerTransientCleanup = function(_, callback)
		transientCleanup = callback
		return true
	end },
	Log = { debug = function(_, message)
		logEvents[#logEvents + 1] = message
	end },
	TerminalItems = {
		rowHeight = function() return 40 end,
		describeRow = function(row) return { data = row } end,
		drawRowDescriptor = function() end,
	},
}

getMouseX, getMouseY = function() return 100 end, function() return 100 end
getCore = function() return { getScreenWidth = function() return 1280 end,
	getScreenHeight = function() return 720 end } end
getPlayerInventory, getPlayerLoot = function() return nil end, function() return nil end
UIFont = { Small = "Small" }
getTextManager = function() return {
	getFontHeight = function() return 20 end,
	MeasureStringX = function(_, _, value) return #tostring(value or "") * 8 end,
} end

dofile("GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/GS_TerminalWithdrawDrag.lua")

local captureEvents, sourceCaptureEvents = {}, {}
local terminal = {
	setCapture = function(_, value) captureEvents[#captureEvents + 1] = value == true end,
}
local source = {
	width = 400, listPanel = {}, terminal = terminal,
	setCapture = function(_, value) sourceCaptureEvents[#sourceCaptureEvents + 1] = value == true end,
}
local parent = { rowKey = "parent", fullType = "Base.Nails", count = 20 }
local child = { rowKey = "child", fullType = "Base.Nails", itemId = 42 }

assert(GlobalStorageSiK.TerminalWithdrawDrag.begin(parent, 0,
	{ parent, child }, { parent, child }, source) == true, "drag did not start")
assert(GlobalStorageSiK.TerminalWithdrawDrag.finishAtPointer() == true, "valid drop failed")
assert(#sent == 1 and sent[1].mode == "batch", "valid drop did not send one batch")
assert(sent[1].key == "player:main", "inventory drop lost its exact destination")
assert(GlobalStorageSiK.TerminalWithdrawDrag.finishAtPointer() == false,
	"second finalization was not ignored")
assert(#sent == 1, "same gesture sent more than one withdrawal")
assert(captureEvents[1] == true and captureEvents[#captureEvents] == false,
	"valid drop did not capture/release terminal")
assert(#sourceCaptureEvents == 0, "child row captured mouse instead of terminal")

destinationKey = "world:crate"
assert(GlobalStorageSiK.TerminalWithdrawDrag.begin(parent, 0,
	{ parent }, { parent }, source) == true, "container drag did not start")
assert(GlobalStorageSiK.TerminalWithdrawDrag.finishAtPointer() == true,
	"world-container drop failed")
assert(#sent == 2 and sent[2].key == "world:crate",
	"world-container drop lost its exact destination")

destinationAvailable = false
assert(GlobalStorageSiK.TerminalWithdrawDrag.begin(parent, 0,
	{ parent }, { parent }, source) == true, "invalid-drop drag did not start")
assert(GlobalStorageSiK.TerminalWithdrawDrag.finishAtPointer() == false,
	"invalid destination reported success")
assert(#sent == 2 and captureEvents[#captureEvents] == false,
	"invalid drop sent or retained capture")

destinationAvailable = true
assert(GlobalStorageSiK.TerminalWithdrawDrag.begin(parent, 0,
	{ parent }, { parent }, source) == true, "Escape drag did not start")
assert(type(escapeClose) == "function", "Escape transient callback missing")
escapeClose()
assert(not GlobalStorageSiK.TerminalWithdrawDrag.isActive(), "Escape retained active payload")
assert(captureEvents[#captureEvents] == false, "Escape did not release capture")
assert(#sent == 2, "Escape emitted a transfer")

assert(GlobalStorageSiK.TerminalWithdrawDrag.begin(parent, 0,
	{ parent }, { parent }, source) == true, "close-cleanup drag did not start")
assert(type(transientCleanup) == "function", "external close cleanup callback missing")
transientCleanup()
assert(not GlobalStorageSiK.TerminalWithdrawDrag.isActive(),
	"external close retained active payload")
assert(captureEvents[#captureEvents] == false, "external close did not release capture")
assert(#sent == 2, "external close emitted a transfer")

assert(logEvents[1] == "dragDropAttempt" and logEvents[2] == "dragDropSent",
	"valid drop lifecycle logs are not ordered")
local allowed = { dragDropAttempt = true, dragDropSent = true }
local sawCancel = false
for i = 1, #logEvents do
	local event = logEvents[i]
	if event:find("dragCancelled reason=", 1, true) == 1 then
		sawCancel = true
	else
		assert(allowed[event], "unexpected drag log event: " .. tostring(event))
	end
end
assert(sawCancel, "cancel lifecycle reason was not logged")

print("drag_capture_finalize_regression: OK")
