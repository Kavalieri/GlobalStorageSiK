-- Deposit/withdraw ACKs must invalidate immediately and coalesce one fresh
-- authoritative request on the next tick, even when revisions arrive quickly.
local root = arg[1] or "."
local sent, renders = {}, 0
GlobalStorageSiK = {
	I18n = { text = function(key) return key end },
	Client = { terminalStateByPlayer = { [0] = { networkId = "net",
		inventoryRevision = 1 } } },
}
local UI = { Block = {}, Controls = {}, Table = {} }
function UI.Block.create(options)
	local panel = { width = options.w, height = options.h, parent = options.parent }
	local block = { x = options.x or 0, y = options.y or 0, w = options.w,
		h = options.h, childParent = panel }
	function block:getContentRect() return { x = 8, y = 8, w = self.w - 16, h = self.h - 16 } end
	function block:setBounds(x, y, w, h) self.x, self.y, self.w, self.h = x, y, w, h end
	function block:dispose() self.disposed = true end
	return block
end
UI.Controls.metrics = function() return { rowHeight = 30 } end
UI.Controls.progress = function()
	local widget = {}; function widget:setProgress() end; function widget:setX() end
	function widget:setY() end; function widget:setWidth() end; function widget:setHeight() end
	return widget
end
UI.Controls.button = function()
	local widget = {}; function widget:setX() end; function widget:setY() end
	function widget:setWidth() end; function widget:setHeight() end
	return widget
end
UI.Table.create = function()
	local value = {}; function value:setRows() end; function value:getIntrinsicHeight() return 40 end
	function value:setBounds() end; function value:dispose() self.disposed = true end
	return value
end
package.preload["GS_UI_Framework"] = function() return UI end
package.preload["GS_WithdrawClient"] = function() return { sendWithdraw = function() return true end } end
package.preload["GS_TerminalDrop"] = function()
	GlobalStorageSiK.TerminalDrop = { setupPanel = function() end, disposePanel = function() end }
	return GlobalStorageSiK.TerminalDrop
end
package.preload["GS_TerminalUI_Items"] = function()
	GlobalStorageSiK.TerminalItems = {
		tableOptions = function() return { pagination = { external = true } } end,
		columns = function() return { { key = "name" }, { key = "count" } } end,
		presentationModel = function(_, _, rows) renders = renders + 1; return { rows = rows } end,
	}
	return GlobalStorageSiK.TerminalItems
end
package.preload["GlobalStorageSiK/UI/CapacityPresentation"] = function()
	return { fromState = function() return {} end }
end
Events = { OnTick = { handlers = {} } }
function Events.OnTick.Add(handler) Events.OnTick.handlers[handler] = true end
function Events.OnTick.Remove(handler) Events.OnTick.handlers[handler] = nil end
GlobalStorageSiK.Log = { debug = function() end }
GlobalStorageSiK.NetClient = { sendCommand = function(name, args)
	sent[#sent + 1] = { name = name, args = args }; return true
end }

local Inventory = dofile(root
	.. "/GlobalStorageSiK-Repo/GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/GS_ContainerInventory.lua")
local view = Inventory.mount({ width = 300 }, { playerNum = 0 }, { id = "nodeA" }, {})
local baselineSent, baselineRenders = #sent, renders
Inventory.onActionResult({ transfer = { op = "deposit", networkId = "net",
	moved = 1, inventoryRevision = 2 } })
Inventory.onActionResult({ transfer = { op = "deposit", networkId = "net",
	moved = 1, inventoryRevision = 3 } })
assert(#sent == baselineSent, "deposit ACK requested before the coalescing tick")
assert(renders == baselineRenders + 2, "each ACK must invalidate visible rows immediately")
local handlers, scheduled = 0, nil
for handler in pairs(Events.OnTick.handlers) do handlers, scheduled = handlers + 1, handler end
assert(handlers == 1 and scheduled, "rapid ACKs scheduled more than one refresh")
scheduled()
assert(#sent == baselineSent + 1 and sent[#sent].name == "getNodeContents",
	"coalesced refresh did not request authoritative node contents")
assert(view.requestedRevision == 3, "coalesced refresh did not retain the newest revision")
local remaining = 0
for _ in pairs(Events.OnTick.handlers) do remaining = remaining + 1 end
assert(remaining == 0, "refresh tick remained registered after dispatch")
view:dispose()
print("container_inventory_refresh_coalescing_contract: OK")
