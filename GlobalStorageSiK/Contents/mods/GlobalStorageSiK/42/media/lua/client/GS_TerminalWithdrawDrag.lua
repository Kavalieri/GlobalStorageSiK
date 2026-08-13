--[[
	GlobalStorageSiK - Arrastre de retiro desde terminal hacia inventario vanilla
	Autor: SiK
	Fecha: 2025-06-24
	Descripción: Soltar fila de red sobre ISInventoryPane para extraer al contenedor bajo el ratón.
]]

require "GS_NetClient"
require "GS_DepositSources"
require "GS_WithdrawClient"
require "GS_ContainerTargets"
require "GS_I18n"

GlobalStorageSiK.TerminalWithdrawDrag = {}

local activeDrag = nil
local tickInstalled = false
local hooksInstalled = false
local WITHDRAW_COOLDOWN_MS = 400
local lastWithdrawMs = 0

--- Indica si hay un arrastre de retiro activo.
---@return boolean
function GlobalStorageSiK.TerminalWithdrawDrag.isActive()
	return activeDrag ~= nil
end

--- Inicia arrastre de una fila de la red (o de la selección múltiple).
---@param rowData table
---@param amount number|nil
---@param selectionRows table[]|nil
function GlobalStorageSiK.TerminalWithdrawDrag.begin(rowData, amount, selectionRows)
	if not rowData or not rowData.fullType then
		return
	end
	local rows = selectionRows
	if selectionRows and #selectionRows > 1 then
		rows = selectionRows
	else
		rows = { rowData }
	end
	activeDrag = {
		rows = rows,
		rowData = rowData,
		amount = amount or 1,
	}
	GlobalStorageSiK.TerminalWithdrawDrag.activePreview = rowData
	GlobalStorageSiK.TerminalWithdrawDrag.activePreviewTypes = {}
	for i = 1, #rows do
		local ft = rows[i] and rows[i].fullType
		if ft then
			GlobalStorageSiK.TerminalWithdrawDrag.activePreviewTypes[ft] = true
		end
	end
end

--- Cancela arrastre activo.
function GlobalStorageSiK.TerminalWithdrawDrag.cancel()
	activeDrag = nil
	GlobalStorageSiK.TerminalWithdrawDrag.activePreview = nil
	GlobalStorageSiK.TerminalWithdrawDrag.activePreviewTypes = nil
end

--- Intenta completar retiro sobre un panel de inventario.
---@param pane ISInventoryPane|nil
---@return boolean
function GlobalStorageSiK.TerminalWithdrawDrag.tryDropOnPane(pane)
	if not activeDrag then
		return false
	end

	local now = getTimestampMs and getTimestampMs() or 0
	if now - lastWithdrawMs < WITHDRAW_COOLDOWN_MS then
		activeDrag = nil
		return false
	end

	pane = pane or GlobalStorageSiK.ContainerTargets.findPaneAtMouse()
	if not pane then
		return false
	end

	local container = GlobalStorageSiK.ContainerTargets.getPaneContainer(pane)
	if not container then
		return false
	end

	local player = GlobalStorageSiK.NetClient.getPlayer()
	if not player then
		return false
	end
	if not GlobalStorageSiK.ContainerTargets.canReceiveWithdraw(player, container) then
		activeDrag = nil
		GlobalStorageSiK.TerminalWithdrawDrag.activePreview = nil
		GlobalStorageSiK.TerminalWithdrawDrag.activePreviewTypes = nil
		return false
	end

	local key = GlobalStorageSiK.ContainerTargets.keyForContainer(player, container)
	if not key then
		activeDrag = nil
		GlobalStorageSiK.TerminalWithdrawDrag.activePreview = nil
		GlobalStorageSiK.TerminalWithdrawDrag.activePreviewTypes = nil
		return false
	end

	local drag = activeDrag
	activeDrag = nil
	GlobalStorageSiK.TerminalWithdrawDrag.activePreview = nil
	GlobalStorageSiK.TerminalWithdrawDrag.activePreviewTypes = nil
	lastWithdrawMs = now

	local terminal = GlobalStorageSiK.TerminalUI and GlobalStorageSiK.TerminalUI.instance
	local searchQuery = terminal and terminal.getSearchQuery and terminal:getSearchQuery() or ""

	local rows = drag.rows or { drag.rowData }
	if #rows > 1 then
		return GlobalStorageSiK.WithdrawClient.sendWithdrawBatch(rows, drag.amount, key, searchQuery)
	end
	return GlobalStorageSiK.WithdrawClient.sendWithdraw(rows[1], drag.amount, key, searchQuery)
end

--- Tick: suelta fuera de inventario cancela; suelta sobre inventario retira.
local function onTickWithdraw()
	if not activeDrag then
		return
	end
	if isMouseButtonDown and isMouseButtonDown(0) then
		return
	end
	GlobalStorageSiK.TerminalWithdrawDrag.tryDropOnPane(GlobalStorageSiK.ContainerTargets.findPaneAtMouse())
	if activeDrag then
		activeDrag = nil
		GlobalStorageSiK.TerminalWithdrawDrag.activePreview = nil
		GlobalStorageSiK.TerminalWithdrawDrag.activePreviewTypes = nil
	end
end

--- Engancha soltado sobre paneles de inventario vanilla.
function GlobalStorageSiK.TerminalWithdrawDrag.installHooks()
	if hooksInstalled then
		return
	end
	hooksInstalled = true

	if ISInventoryPane and ISInventoryPane.onMouseUp then
		local originalMouseUp = ISInventoryPane.onMouseUp
		ISInventoryPane.onMouseUp = function(self, x, y)
			if GlobalStorageSiK.TerminalWithdrawDrag.tryDropOnPane(self) then
				return true
			end
			return originalMouseUp(self, x, y)
		end
	end

	if not tickInstalled then
		tickInstalled = true
		Events.OnTick.Add(onTickWithdraw)
	end
end

GlobalStorageSiK.TerminalWithdrawDrag.installHooks()
