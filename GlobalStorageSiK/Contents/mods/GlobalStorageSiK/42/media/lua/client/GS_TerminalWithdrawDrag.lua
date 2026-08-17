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
require "ISUI/ISPanel"

GlobalStorageSiK.TerminalWithdrawDrag = {}

local activeDrag = nil
local tickInstalled = false
local hooksInstalled = false
local dragPreviewPanel = nil

local GSWithdrawDragPreview = ISPanel:derive("GSWithdrawDragPreview")

local function dragTexture(row)
	if not row or not row.fullType then return nil end
	if getItemTex then
		local ok, texture = pcall(getItemTex, row.fullType)
		if ok and texture then return texture end
	end
	if ScriptManager and ScriptManager.instance then
		local ok, script = pcall(function()
			return ScriptManager.instance:getItem(row.fullType)
		end)
		if ok and script and script.getNormalTexture then
			local texOk, texture = pcall(function() return script:getNormalTexture() end)
			if texOk and texture then return texture end
		end
	end
	if row.worldSprite and getSprite then
		local ok, texture = pcall(function()
			local sprite = getSprite(row.worldSprite)
			return sprite and sprite.getTexture and sprite:getTexture() or nil
		end)
		if ok then return texture end
	end
	return nil
end

function GSWithdrawDragPreview:new(x, y, width, height)
	local o = ISPanel:new(x, y, width, height)
	setmetatable(o, self)
	self.__index = self
	return o
end

function GSWithdrawDragPreview:render()
	ISPanel.render(self)
	local drag = activeDrag
	if not drag then return end
	local row = drag.rowData or {}
	local texture = dragTexture(row)
	if texture then
		self:drawTextureScaledAspect(texture, 6, 6, 40, 40, 0.95, 1, 1, 1)
	else
		self:drawText("?", 20, 12, 1, 1, 1, 1, UIFont.Medium)
	end
	local rows = drag.rows or {}
	local amount = math.max(1, math.floor(tonumber(drag.amount) or 1))
	local label = #rows > 1 and ("+" .. tostring(#rows - 1)) or tostring(amount)
	local badgeW = math.max(22, 8 + (#label * 8))
	local badgeX = self.width - badgeW - 2
	self:drawRect(badgeX, self.height - 20, badgeW, 18, 0.92, 0.05, 0.05, 0.05)
	self:drawRectBorder(badgeX, self.height - 20, badgeW, 18, 0.9, 0.7, 0.7, 0.7)
	self:drawTextCentre(label, badgeX + math.floor(badgeW / 2), self.height - 19,
		1, 1, 1, 1, UIFont.Small)
end

local function destroyPreview()
	if dragPreviewPanel then
		dragPreviewPanel:removeFromUIManager()
		dragPreviewPanel = nil
	end
end

local function createPreview()
	destroyPreview()
	dragPreviewPanel = GSWithdrawDragPreview:new((getMouseX and getMouseX() or 0) + 14,
		(getMouseY and getMouseY() or 0) + 14, 54, 54)
	dragPreviewPanel:initialise()
	if dragPreviewPanel.javaObject and dragPreviewPanel.javaObject.setConsumeMouseEvents then
		dragPreviewPanel.javaObject:setConsumeMouseEvents(false)
	end
	dragPreviewPanel.backgroundColor = { r = 0.05, g = 0.05, b = 0.05, a = 0.72 }
	dragPreviewPanel.borderColor = { r = 0.75, g = 0.75, b = 0.75, a = 0.75 }
	dragPreviewPanel:setAlwaysOnTop(true)
	dragPreviewPanel:addToUIManager()
end

local function expandInventoryPages()
	local player = GlobalStorageSiK.NetClient.getPlayer()
	local playerNum = player and player.getPlayerNum and player:getPlayerNum() or 0
	local pages = {
		getPlayerInventory and getPlayerInventory(playerNum) or nil,
		getPlayerLoot and getPlayerLoot(playerNum) or nil,
	}
	for i = 1, #pages do
		local page = pages[i]
		if page then
			page.collapseCounter = 0
			if page.isCollapsed then
				page.isCollapsed = false
				if page.clearMaxDrawHeight then page:clearMaxDrawHeight() end
				local pane = page.inventoryPane
				if isClient and isClient() and pane and pane.inventory and pane.inventory.requestSync then
					pane.inventory:requestSync()
				end
			end
		end
	end
end

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
	expandInventoryPages()
	createPreview()
end

--- Cancela arrastre activo.
function GlobalStorageSiK.TerminalWithdrawDrag.cancel()
	activeDrag = nil
	GlobalStorageSiK.TerminalWithdrawDrag.activePreview = nil
	GlobalStorageSiK.TerminalWithdrawDrag.activePreviewTypes = nil
	destroyPreview()
end

--- Intenta completar retiro sobre un panel de inventario.
---@param pane ISInventoryPane|nil
---@return boolean
function GlobalStorageSiK.TerminalWithdrawDrag.tryDropOnPane(pane)
	if not activeDrag then
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
		GlobalStorageSiK.TerminalWithdrawDrag.cancel()
		return false
	end

	local key = GlobalStorageSiK.ContainerTargets.keyForContainer(player, container)
	if not key then
		GlobalStorageSiK.TerminalWithdrawDrag.cancel()
		return false
	end

	local drag = activeDrag
	GlobalStorageSiK.TerminalWithdrawDrag.cancel()

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
	if dragPreviewPanel then
		dragPreviewPanel:setX((getMouseX and getMouseX() or 0) + 14)
		dragPreviewPanel:setY((getMouseY and getMouseY() or 0) + 14)
	end
	if isMouseButtonDown and isMouseButtonDown(0) then
		return
	end
	GlobalStorageSiK.TerminalWithdrawDrag.tryDropOnPane(GlobalStorageSiK.ContainerTargets.findPaneAtMouse())
	if activeDrag then
		GlobalStorageSiK.TerminalWithdrawDrag.cancel()
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
