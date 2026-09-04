--[[
	GlobalStorageSiK - Zona de drop en terminal (arrastre B42)
	Autor: SiK
	Fecha: 2025-06-24
	Descripción: Depósito al soltar ítems sobre el terminal (un solo handler por tick).
]]

require "GS_I18n"
require "GS_NetClient"
require "GS_DepositClient"

local UI = require "GS_UI_Framework"

GlobalStorageSiK.TerminalDrop = {}

local T = GlobalStorageSiK.I18n.text
local lastDepositMs = 0
local DEPOSIT_COOLDOWN_MS = 500

--- Indica si el ratón está sobre el terminal visible.
---@return boolean
function GlobalStorageSiK.TerminalDrop.isMouseOverTerminal()
	local ui = GlobalStorageSiK.TerminalUI and GlobalStorageSiK.TerminalUI.instance or nil
	if not ui or not ui.getIsVisible or not ui:getIsVisible() then
		return false
	end
	if ui.isMouseOver and ui:isMouseOver() then
		return true
	end
	local mx, my = getMouseX(), getMouseY()
	return mx >= ui:getX() and my >= ui:getY() and mx < ui:getX() + ui:getWidth() and my < ui:getY() + ui:getHeight()
end

--- Intenta depositar ítems pendientes o en arrastre (una sola petición por cooldown).
---@param items InventoryItem[]|nil
---@return boolean
function GlobalStorageSiK.TerminalDrop.tryDepositItems(items)
	local now = getTimestampMs and getTimestampMs() or 0
	if now - lastDepositMs < DEPOSIT_COOLDOWN_MS then
		return false
	end

	items = items or GlobalStorageSiK.DepositClient.collectDraggedItems()
	if #items == 0 then
		return false
	end
	if not GlobalStorageSiK.DepositClient.canDepositDraggedItems(items) then
		return false
	end

	local ids = GlobalStorageSiK.DepositClient.collectItemIds(items)
	if #ids == 0 then
		return false
	end

	lastDepositMs = now
	GlobalStorageSiK.DepositClient.clearDrag()

	return GlobalStorageSiK.DepositClient.sendDepositItems(ids)
end

--- Configura el panel como destino visual mediante el contrato publico SiK UI.
---@param panel ISPanel
---@param terminal GS_TerminalUI|nil
function GlobalStorageSiK.TerminalDrop.setupPanel(panel, terminal)
	if not panel or panel.gsDropSetup then
		return
	end
	panel.gsDropSetup = true
	panel.gsDropTerminal = terminal
	panel.gsDropTarget = UI.DropTarget.attach(panel, {
		playerNum = terminal and terminal.playerNum or 0,
		tone = "info",
		dragProvider = function()
			local items = GlobalStorageSiK.DepositClient.collectDraggedItems()
			if #items == 0 then
				return nil
			end
			return { payload = items }
		end,
		accept = function(items)
			return items ~= nil and #items > 0
				and GlobalStorageSiK.TerminalDrop.isMouseOverTerminal()
				and GlobalStorageSiK.DepositClient.canDepositDraggedItems(items)
		end,
		onDrop = function(items)
			return GlobalStorageSiK.TerminalDrop.tryDepositItems(items)
		end,
	})
	if terminal and not terminal.gsDropMonitor then
		terminal.gsDropMonitor = UI.DropTarget.monitor(terminal, {
			playerNum = terminal.playerNum or 0,
			isDragging = function()
				return ISMouseDrag and ISMouseDrag.dragging ~= nil
			end,
			payload = function()
				local items = GlobalStorageSiK.DepositClient.collectDraggedItems()
				if #items == 0 then return nil end
				return items
			end,
			isOver = function()
				return GlobalStorageSiK.TerminalDrop.isMouseOverTerminal()
			end,
			onDrop = function(items)
				return GlobalStorageSiK.TerminalDrop.tryDepositItems(items)
			end,
		})
	end
end

--- Libera destino y monitor del ciclo de vida de la superficie. No quedan
--- handlers de arrastre vivos tras cerrar o reconstruir la pestaña.
---@param panel ISPanel|nil
---@param terminal GS_TerminalUI|nil
---@return boolean
function GlobalStorageSiK.TerminalDrop.disposePanel(panel, terminal)
	if not panel then return false end
	local owner = terminal or panel.gsDropTerminal
	if panel.gsDropTarget and panel.gsDropTarget.dispose then
		panel.gsDropTarget:dispose()
	end
	panel.gsDropTarget = nil
	panel.gsDropSetup = nil
	panel.gsDropTerminal = nil
	if owner and owner.gsDropMonitor then
		if owner.gsDropMonitor.dispose then owner.gsDropMonitor:dispose() end
		owner.gsDropMonitor = nil
	end
	return true
end

--- Texto de ayuda para arrastre construido por el framework publico.
---@param parent ISPanel
---@param x number
---@param y number
---@return ISPanel
function GlobalStorageSiK.TerminalDrop.createHintLabel(parent, x, y)
	local parentWidth = parent and tonumber(parent.width) or nil
	if not parentWidth and parent and parent.getWidth then
		parentWidth = tonumber(parent:getWidth())
	end
	return UI.Controls.copyText(parent, {
		x = x,
		y = y,
		w = math.max(1, (parentWidth or 240) - (tonumber(x) or 0)),
		text = T("IGUI_GS_DropHint"),
		tone = "textMuted",
		playerNum = parent and parent.playerNum or 0,
	})
end
