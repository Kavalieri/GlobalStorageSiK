--[[
	GlobalStorageSiK - Zona de drop en terminal (arrastre B42)
	Autor: SiK
	Fecha: 2025-06-24
	Descripción: Depósito al soltar ítems sobre el terminal (un solo handler por tick).
]]

require "GS_I18n"
require "GS_NetClient"
require "GS_DepositClient"

GlobalStorageSiK.TerminalDrop = {}

local T = GlobalStorageSiK.I18n.text
local tickInstalled = false
local wasDragging = false
local pendingItems = nil
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
	pendingItems = nil
	wasDragging = false
	GlobalStorageSiK.DepositClient.clearDrag()

	return GlobalStorageSiK.DepositClient.sendDepositItems(ids)
end

--- Tick: captura suelta de ítem sobre el terminal.
local function onTickDrop()
	local dragging = ISMouseDrag and ISMouseDrag.dragging
	if dragging then
		wasDragging = true
		if GlobalStorageSiK.TerminalDrop.isMouseOverTerminal() then
			pendingItems = GlobalStorageSiK.DepositClient.collectDraggedItems()
		else
			pendingItems = nil
		end
		return
	end

	if wasDragging then
		wasDragging = false
		if pendingItems and #pendingItems > 0 and GlobalStorageSiK.TerminalDrop.isMouseOverTerminal() then
			GlobalStorageSiK.TerminalDrop.tryDepositItems(pendingItems)
		end
		pendingItems = nil
	end
end

--- Engancha detección de arrastre (solo tick; sin hook en onMouseUp para evitar bucles).
function GlobalStorageSiK.TerminalDrop.installHooks()
	if tickInstalled then
		return
	end
	tickInstalled = true
	Events.OnTick.Add(onTickDrop)
end

--- Configura panel como zona visual de drop (sin interceptar mouseUp).
---@param panel ISPanel
---@param terminal GS_TerminalUI|nil
function GlobalStorageSiK.TerminalDrop.setupPanel(panel, terminal)
	if not panel or panel.gsDropSetup then
		return
	end
	panel.gsDropSetup = true
	panel.gsDropTerminal = terminal

	local basePrerender = panel.prerender
	panel.prerender = function(self)
		if basePrerender then
			basePrerender(self)
		elseif ISPanel.prerender then
			ISPanel.prerender(self)
		end
		if GlobalStorageSiK.DepositClient.isDraggingItems() and GlobalStorageSiK.TerminalDrop.isMouseOverTerminal() then
			self:drawRect(0, 0, self.width, self.height, 0.2, 0.2, 0.45, 0.65)
			self:drawRectBorder(0, 0, self.width, self.height, 0.65, 0.4, 0.7, 0.9)
		end
	end
end

--- Etiqueta de ayuda para arrastre.
---@param parent ISPanel
---@param x number
---@param y number
---@return ISLabel
function GlobalStorageSiK.TerminalDrop.createHintLabel(parent, x, y)
	local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
	local lbl = ISLabel:new(x, y, FONT_HGT_SMALL, T("IGUI_GS_DropHint"), 0.5, 0.58, 0.66, 1, UIFont.Small, true)
	lbl:initialise()
	parent:addChild(lbl)
	return lbl
end

GlobalStorageSiK.TerminalDrop.installHooks()
