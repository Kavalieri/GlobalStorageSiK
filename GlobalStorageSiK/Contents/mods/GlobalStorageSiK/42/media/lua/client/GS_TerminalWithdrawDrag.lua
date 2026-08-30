--[[
	GlobalStorageSiK - Arrastre de retiro desde terminal hacia inventario vanilla
	El ghost comparte descriptor y renderer con la fila real del Almacen.
]]

require "GS_NetClient"
require "GS_WithdrawClient"
require "GS_ContainerTargets"
require "GS_SiK_UI_EscapeStack"
require "ISUI/ISPanel"

GlobalStorageSiK.TerminalWithdrawDrag = {}

local activeDrag = nil
local dragPreviewPanel = nil
local cleanupRegistered = false

local GSWithdrawDragPreview = ISPanel:derive("GSWithdrawDragPreview")
local GSWithdrawDragPreviewRow = ISPanel:derive("GSWithdrawDragPreviewRow")

local function rowIdentity(row)
	return row and (row.rowKey or row.fullType) or nil
end

function GSWithdrawDragPreviewRow:new(x, y, width, height, descriptor, rowIndex)
	local o = ISPanel:new(x, y, width, height)
	setmetatable(o, self)
	self.__index = self
	o.descriptor = descriptor
	o.rowIndex = rowIndex
	o.drawBackground = false
	o.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
	o.borderColor = { r = 0, g = 0, b = 0, a = 0 }
	return o
end

function GSWithdrawDragPreviewRow:prerender()
	ISPanel.prerender(self)
	if self.descriptor and GlobalStorageSiK.TerminalItems
		and GlobalStorageSiK.TerminalItems.drawRowDescriptor then
		GlobalStorageSiK.TerminalItems.drawRowDescriptor(self, self.descriptor, {
			rowIndex = self.rowIndex, hovered = false, selected = true,
		})
	end
end

function GSWithdrawDragPreview:new(x, y, width, height)
	local o = ISPanel:new(x, y, width, height)
	setmetatable(o, self)
	self.__index = self
	return o
end

local function destroyPreview()
	if dragPreviewPanel then
		GlobalStorageSiK.SiK_UI.EscapeStack.remove(dragPreviewPanel)
		dragPreviewPanel:removeFromUIManager()
		dragPreviewPanel = nil
	end
end

local function pointerPosition(width, height)
	local mx = getMouseX and getMouseX() or 0
	local my = getMouseY and getMouseY() or 0
	local screenW = getCore and getCore():getScreenWidth() or (mx + width + 16)
	local screenH = getCore and getCore():getScreenHeight() or (my + height + 16)
	return math.max(0, math.min(mx + 14, screenW - width - 8)),
		math.max(0, math.min(my + 14, screenH - height - 8))
end

local function createPreview(sourceWidget)
	destroyPreview()
	local items = GlobalStorageSiK.TerminalItems
	if not activeDrag or not items or not items.describeRow or not items.drawRowDescriptor then return end
	local rowH = items.rowHeight and items.rowHeight() or 40
	local visualRows = activeDrag.visualRows or {}
	local width = math.max(520, sourceWidget and sourceWidget.width or 720)
	local height = math.max(rowH, #visualRows * rowH)
	local x, y = pointerPosition(width, height)
	dragPreviewPanel = GSWithdrawDragPreview:new(x, y, width, height)
	dragPreviewPanel:initialise()
	dragPreviewPanel.backgroundColor = { r = 0.035, g = 0.035, b = 0.035, a = 0.94 }
	dragPreviewPanel.borderColor = { r = 0.38, g = 0.42, b = 0.46, a = 0.9 }
	local listPanel = sourceWidget and sourceWidget.listPanel or nil
	local terminal = sourceWidget and sourceWidget.terminal or nil
	for i = 1, #visualRows do
		local descriptor = items.describeRow(visualRows[i], listPanel, terminal, nil)
		local rowPanel = GSWithdrawDragPreviewRow:new(0, (i - 1) * rowH, width, rowH, descriptor, i)
		rowPanel:initialise()
		dragPreviewPanel:addChild(rowPanel)
	end
	local player = GlobalStorageSiK.NetClient.getPlayer()
	dragPreviewPanel.playerNum = player and player.getPlayerNum and player:getPlayerNum() or 0
	GlobalStorageSiK.SiK_UI.EscapeStack.install(dragPreviewPanel, function()
		GlobalStorageSiK.TerminalWithdrawDrag.cancel()
	end, GlobalStorageSiK.SiK_UI.EscapeStack.PRIORITY.TRANSIENT)
	if dragPreviewPanel.javaObject and dragPreviewPanel.javaObject.setConsumeMouseEvents then
		dragPreviewPanel.javaObject:setConsumeMouseEvents(false)
	end
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
			end
		end
	end
end

local function ensureTransientCleanup()
	if cleanupRegistered or not GlobalStorageSiK.Client
		or not GlobalStorageSiK.Client.registerTransientCleanup then return end
	cleanupRegistered = GlobalStorageSiK.Client.registerTransientCleanup("terminal-withdraw-drag", function()
		GlobalStorageSiK.TerminalWithdrawDrag.cancel()
	end) == true
end

function GlobalStorageSiK.TerminalWithdrawDrag.isActive()
	return activeDrag ~= nil
end

function GlobalStorageSiK.TerminalWithdrawDrag.getPreviewRows()
	return activeDrag and activeDrag.visualRows or {}
end

function GlobalStorageSiK.TerminalWithdrawDrag.getPayloadRows()
	return activeDrag and activeDrag.payloadRows or {}
end

--- Inicia un drag con estado visual y payload deliberadamente separados.
---@param rowData table
---@param amount number|nil
---@param payloadRows table[]|nil
---@param visualRows table[]|nil
---@param sourceWidget ISPanel|nil
function GlobalStorageSiK.TerminalWithdrawDrag.begin(rowData, amount, payloadRows, visualRows, sourceWidget)
	if not rowData or not rowData.fullType then return false end
	payloadRows = payloadRows and #payloadRows > 0 and payloadRows or { rowData }
	visualRows = visualRows and #visualRows > 0 and visualRows or { rowData }
	activeDrag = {
		payloadRows = payloadRows,
		visualRows = visualRows,
		rowData = rowData,
		amount = amount or 1,
	}
	GlobalStorageSiK.TerminalWithdrawDrag.activePreview = rowData
	GlobalStorageSiK.TerminalWithdrawDrag.activePreviewTypes = {}
	for i = 1, #visualRows do
		local key = rowIdentity(visualRows[i])
		if key then GlobalStorageSiK.TerminalWithdrawDrag.activePreviewTypes[key] = true end
	end
	ensureTransientCleanup()
	expandInventoryPages()
	createPreview(sourceWidget)
	return true
end

function GlobalStorageSiK.TerminalWithdrawDrag.moveToPointer()
	if not dragPreviewPanel then return false end
	local x, y = pointerPosition(dragPreviewPanel.width, dragPreviewPanel.height)
	dragPreviewPanel:setX(x)
	dragPreviewPanel:setY(y)
	return true
end

function GlobalStorageSiK.TerminalWithdrawDrag.cancel()
	activeDrag = nil
	GlobalStorageSiK.TerminalWithdrawDrag.activePreview = nil
	GlobalStorageSiK.TerminalWithdrawDrag.activePreviewTypes = nil
	destroyPreview()
end

function GlobalStorageSiK.TerminalWithdrawDrag.tryDropOnPane(pane)
	if not activeDrag then return false end
	pane = pane or GlobalStorageSiK.ContainerTargets.findPaneAtMouse()
	if not pane then return false end
	local container = GlobalStorageSiK.ContainerTargets.getPaneContainer(pane)
	if not container then return false end
	local player = GlobalStorageSiK.NetClient.getPlayer()
	if not player or not GlobalStorageSiK.ContainerTargets.canReceiveWithdraw(player, container) then
		return false
	end
	local key = GlobalStorageSiK.ContainerTargets.keyForContainer(player, container)
	if not key then return false end
	local drag = activeDrag
	GlobalStorageSiK.TerminalWithdrawDrag.cancel()
	local terminal = GlobalStorageSiK.TerminalUI and GlobalStorageSiK.TerminalUI.instance
	local searchQuery = terminal and terminal.getSearchQuery and terminal:getSearchQuery() or ""
	local rows = drag.payloadRows or { drag.rowData }
	if #rows > 1 then
		return GlobalStorageSiK.WithdrawClient.sendWithdrawBatch(rows, drag.amount, key, searchQuery)
	end
	return GlobalStorageSiK.WithdrawClient.sendWithdraw(rows[1], drag.amount, key, searchQuery)
end

function GlobalStorageSiK.TerminalWithdrawDrag.finishAtPointer()
	if not activeDrag then return false end
	local pane = GlobalStorageSiK.ContainerTargets.findPaneAtMouse()
	local dropped = pane and GlobalStorageSiK.TerminalWithdrawDrag.tryDropOnPane(pane) or false
	if activeDrag then GlobalStorageSiK.TerminalWithdrawDrag.cancel() end
	return dropped
end

-- Compatibilidad con el cargador anterior. Ya no instala OnTick ni monkey
-- patches globales: el widget de origen captura move/up/outside.
function GlobalStorageSiK.TerminalWithdrawDrag.installHooks()
	ensureTransientCleanup()
	return true
end
