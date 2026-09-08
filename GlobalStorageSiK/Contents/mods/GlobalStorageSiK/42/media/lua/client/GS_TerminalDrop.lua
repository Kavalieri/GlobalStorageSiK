--[[
	GlobalStorageSiK - Zona de drop en terminal (arrastre B42)
	Autor: SiK
	Fecha: 2025-06-24
	Descripción: Depósito al soltar ítems sobre el terminal (un solo handler por tick).
]]

require "GS_I18n"
require "GS_Log"
require "GS_NetClient"
require "GS_DepositClient"

local UI = require "GS_UI_Framework"

GlobalStorageSiK.TerminalDrop = {}

local T = GlobalStorageSiK.I18n.text
local lastDepositMs = {}
local DEPOSIT_COOLDOWN_MS = 500

--- Indica si el ratón está sobre el terminal visible.
---@return boolean
function GlobalStorageSiK.TerminalDrop.isMouseOverTerminal()
	local ui = GlobalStorageSiK.TerminalUI and GlobalStorageSiK.TerminalUI.instance or nil
	return GlobalStorageSiK.TerminalDrop.isMouseOverPanel(ui)
end

--- Indica si el puntero está realmente sobre una superficie receptora visible.
---@param panel ISUIElement|nil
---@return boolean
function GlobalStorageSiK.TerminalDrop.isMouseOverPanel(panel)
	local ui = panel
	if not ui or not ui.getIsVisible or not ui:getIsVisible() then
		return false
	end
	if ui.isMouseOver and ui:isMouseOver() then
		return true
	end
	local mx, my = getMouseX(), getMouseY()
	local x = ui.getAbsoluteX and ui:getAbsoluteX() or ui:getX()
	local y = ui.getAbsoluteY and ui:getAbsoluteY() or ui:getY()
	return mx >= x and my >= y and mx < x + ui:getWidth() and my < y + ui:getHeight()
end

--- Intenta depositar ítems pendientes o en arrastre (una sola petición por cooldown).
---@param items InventoryItem[]|nil
---@return boolean
function GlobalStorageSiK.TerminalDrop.tryDepositItems(items, playerNum)
	playerNum = playerNum or 0
	local now = getTimestampMs and getTimestampMs() or 0
	if lastDepositMs[playerNum] and now - lastDepositMs[playerNum] < DEPOSIT_COOLDOWN_MS then
		GlobalStorageSiK.Log.debug("ExactWithdraw", "deposit.rejected reason=cooldown")
		return false
	end

	items = items or GlobalStorageSiK.DepositClient.collectDraggedItems()
	if #items == 0 then
		GlobalStorageSiK.Log.debug("ExactWithdraw", "deposit.rejected reason=no_items")
		return false
	end
	if not GlobalStorageSiK.DepositClient.canDepositDraggedItems(items, playerNum) then
		GlobalStorageSiK.Log.debug("ExactWithdraw", "deposit.rejected reason=not_depositable count=" .. tostring(#items))
		return false
	end

	local ids = GlobalStorageSiK.DepositClient.collectItemIds(items)
	if #ids == 0 then
		GlobalStorageSiK.Log.debug("ExactWithdraw", "deposit.rejected reason=no_ids")
		return false
	end

	local sent = GlobalStorageSiK.DepositClient.sendDraggedItems(items, playerNum)
    if sent then
        lastDepositMs[playerNum] = now
        GlobalStorageSiK.DepositClient.clearDrag()
    end
	GlobalStorageSiK.Log.debug("ExactWithdraw", "deposit.sent count=" .. tostring(#ids)
		.. " accepted=" .. tostring(sent ~= false))
	return sent
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
				and GlobalStorageSiK.TerminalDrop.isMouseOverPanel(panel)
				and GlobalStorageSiK.DepositClient.canDepositDraggedItems(items, terminal and terminal.playerNum or panel.playerNum or 0)
		end,
		onDrop = function(items)
			return GlobalStorageSiK.TerminalDrop.tryDepositItems(items, terminal and terminal.playerNum or panel.playerNum or 0)
		end,
	})
	-- Cada superficie tiene su monitor. Compartir uno en `terminal` dejaba los
	-- editores sin captura porque la pestaña Almacén ya lo había ocupado.
	if not panel.gsDropMonitor then
		panel.gsDropMonitor = UI.DropTarget.monitor(panel, {
			playerNum = terminal and terminal.playerNum or panel.playerNum or 0,
			isDragging = function()
				return ISMouseDrag and ISMouseDrag.dragging ~= nil
			end,
			payload = function()
				local items = GlobalStorageSiK.DepositClient.collectDraggedItems()
				if #items == 0 then return nil end
				return items
			end,
			isOver = function()
				return GlobalStorageSiK.TerminalDrop.isMouseOverPanel(panel)
			end,
			onDrop = function(items)
				return GlobalStorageSiK.TerminalDrop.tryDepositItems(items, terminal and terminal.playerNum or panel.playerNum or 0)
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
	if panel.gsDropTarget and panel.gsDropTarget.dispose then
		panel.gsDropTarget:dispose()
	end
	panel.gsDropTarget = nil
	panel.gsDropSetup = nil
	panel.gsDropTerminal = nil
	if panel.gsDropMonitor then
		if panel.gsDropMonitor.dispose then panel.gsDropMonitor:dispose() end
		panel.gsDropMonitor = nil
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
