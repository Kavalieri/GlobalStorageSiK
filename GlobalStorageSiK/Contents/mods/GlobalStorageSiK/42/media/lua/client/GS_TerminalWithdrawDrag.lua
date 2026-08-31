--[[
	GlobalStorageSiK - Arrastre de retiro desde terminal hacia inventario vanilla
	El ghost es una señal compacta de selección; nunca replica la tabla origen.
]]

require "GS_NetClient"
require "GS_WithdrawClient"
require "GS_ContainerTargets"
require "GS_SiK_UI_EscapeStack"
require "GS_SiK_UI_Viewport"
require "GS_I18n"
require "ISUI/ISPanel"

GlobalStorageSiK.TerminalWithdrawDrag = {}

local activeDrag = nil
local dragPreviewPanel = nil
local cleanupRegistered = false
local PREVIEW_MIN_W = 180
local PREVIEW_MAX_W = 300
local PREVIEW_MAX_ROWS = 6
local PREVIEW_PAD = 8
local PREVIEW_ICON = 32
local PREVIEW_GAP = 8
local PREVIEW_ALPHA = 0.78

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

local function truncateMeasured(text, maxWidth)
	return GlobalStorageSiK.SiK_UI.truncateText(tostring(text or ""), maxWidth, UIFont.Small)
end

function GSWithdrawDragPreviewRow:prerender()
	ISPanel.prerender(self)
	local descriptor = self.descriptor
	if not descriptor then return end
	local pal = GlobalStorageSiK.SiK_UI.PALETTE
	self:drawRect(0, 0, self.width, self.height, PREVIEW_ALPHA,
		0.035, 0.035, 0.035)
	self:drawRectBorder(0, 0, self.width, self.height, PREVIEW_ALPHA,
		0.38, 0.42, 0.46)
	local iconX = PREVIEW_PAD + 16
	local iconY = math.floor((self.height - PREVIEW_ICON) / 2)
	if descriptor.texture then
		self:drawTextureScaledAspect(descriptor.texture, iconX, iconY,
			PREVIEW_ICON, PREVIEW_ICON, PREVIEW_ALPHA, 1, 1, 1)
	end
	local y = math.floor((self.height - getTextManager():getFontHeight(UIFont.Small)) / 2)
	if descriptor.indicator and descriptor.indicator ~= "" then
		self:drawText(descriptor.indicator, PREVIEW_PAD, y,
			pal.textSecondary[1], pal.textSecondary[2], pal.textSecondary[3],
			PREVIEW_ALPHA, UIFont.Small)
	end
	local textX = iconX + PREVIEW_ICON + PREVIEW_GAP
	local counter = descriptor.count and tostring(descriptor.count) or nil
	local counterW = counter and getTextManager():MeasureStringX(UIFont.Small, counter) or 0
	local counterReserve = counter and (counterW + PREVIEW_GAP) or 0
	local textW = math.max(20, self.width - textX - PREVIEW_PAD - counterReserve)
	self:drawText(truncateMeasured(descriptor.name, textW), textX, y,
		pal.textPrimary[1], pal.textPrimary[2], pal.textPrimary[3], PREVIEW_ALPHA, UIFont.Small)
	if counter then
		self:drawTextRight(counter, self.width - PREVIEW_PAD, y,
			pal.textSecondary[1], pal.textSecondary[2], pal.textSecondary[3],
			PREVIEW_ALPHA, UIFont.Small)
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

local function pointerPosition(width, height, playerNum)
	local mx = getMouseX and getMouseX() or 0
	local my = getMouseY and getMouseY() or 0
	local viewport = GlobalStorageSiK.SiK_UI.Viewport.resolve(playerNum or 0)
	local right = viewport.x + viewport.w
	local bottom = viewport.y + viewport.h
	local gap = 16
	local x = mx + gap
	local y = my + gap
	-- Se invierte cuando cabe al lado opuesto. Si tampoco cabe, se permite el
	-- recorte visual: el ghost jamás limita el cursor ni decide el hit-test.
	if x + width > right and mx - width - gap >= viewport.x then
		x = mx - width - gap
	end
	if y + height > bottom and my - height - gap >= viewport.y then
		y = my - height - gap
	end
	return x, y
end

local function makeMouseTransparent(panel)
	if not panel then return end
	panel.onMouseDown = function() return false end
	panel.onMouseUp = function() return false end
	panel.onMouseUpOutside = function() return false end
	panel.onMouseMove = function() return false end
	panel.onMouseMoveOutside = function() return false end
	if panel.javaObject and panel.javaObject.setConsumeMouseEvents then
		panel.javaObject:setConsumeMouseEvents(false)
	end
end

local function createPreview(sourceWidget)
	destroyPreview()
	local items = GlobalStorageSiK.TerminalItems
	if not activeDrag or not items or not items.describeRow then return end
	local rowH = items.rowHeight and items.rowHeight() or 40
	local visualRows = activeDrag.visualRows or {}
	local listPanel = sourceWidget and sourceWidget.listPanel or nil
	local terminal = sourceWidget and sourceWidget.terminal or nil
	if #visualRows == 0 then visualRows[1] = activeDrag.rowData end
	local descriptors = {}
	local tm = getTextManager()
	local desiredW = PREVIEW_MIN_W
	local overflow = #visualRows > PREVIEW_MAX_ROWS
	local visibleDataCount = overflow and (PREVIEW_MAX_ROWS - 1) or #visualRows
	for i = 1, #visualRows do
		if i > visibleDataCount then break end
		local descriptor = items.describeRow(visualRows[i], listPanel, terminal, nil)
		descriptors[i] = descriptor
		local counterW = descriptor.count
			and tm:MeasureStringX(UIFont.Small, tostring(descriptor.count)) + PREVIEW_GAP or 0
		desiredW = math.max(desiredW, PREVIEW_PAD + PREVIEW_ICON + PREVIEW_GAP
			+ tm:MeasureStringX(UIFont.Small, descriptor.name or "") + counterW + PREVIEW_PAD)
	end
	if overflow then
		local hidden = #visualRows - visibleDataCount
		descriptors[#descriptors + 1] = {
			name = GlobalStorageSiK.I18n.text("IGUI_GS_DragMoreObjects", tostring(hidden)),
			indicator = "+", count = "", texture = nil, overflow = true,
		}
	end
	local width = math.max(PREVIEW_MIN_W, math.min(PREVIEW_MAX_W, desiredW))
	local player = GlobalStorageSiK.NetClient.getPlayer()
	local playerNum = player and player.getPlayerNum and player:getPlayerNum() or 0
	local naturalHeight = #visualRows * rowH
	local height = math.max(rowH, math.min(naturalHeight, PREVIEW_MAX_ROWS * rowH))
	local x, y = pointerPosition(width, height, playerNum)
	dragPreviewPanel = GSWithdrawDragPreview:new(x, y, width, height)
	dragPreviewPanel:initialise()
	dragPreviewPanel.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
	dragPreviewPanel.borderColor = { r = 0, g = 0, b = 0, a = 0 }
	for i = 1, #descriptors do
		local rowPanel = GSWithdrawDragPreviewRow:new(
			0, (i - 1) * rowH, width, rowH, descriptors[i], i)
		rowPanel:initialise()
		dragPreviewPanel:addChild(rowPanel)
		makeMouseTransparent(rowPanel)
	end
	dragPreviewPanel.playerNum = playerNum
	GlobalStorageSiK.SiK_UI.EscapeStack.install(dragPreviewPanel, function()
		GlobalStorageSiK.TerminalWithdrawDrag.cancel()
	end, GlobalStorageSiK.SiK_UI.EscapeStack.PRIORITY.TRANSIENT)
	makeMouseTransparent(dragPreviewPanel)
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

function GlobalStorageSiK.TerminalWithdrawDrag.isActiveForPanel(panel)
	local source = activeDrag and activeDrag.sourceWidget or nil
	return source ~= nil and source.listPanel == panel
end

function GlobalStorageSiK.TerminalWithdrawDrag.getPreviewRows()
	return activeDrag and activeDrag.visualRows or {}
end

function GlobalStorageSiK.TerminalWithdrawDrag.getPayloadRows()
	return activeDrag and activeDrag.payloadRows or {}
end

local function normalizePayloadRows(rows, fallback)
	rows = rows and #rows > 0 and rows or { fallback }
	local selectedParents = {}
	for i = 1, #rows do
		local row = rows[i]
		if row and row._gsRowKind == "parent" then
			local key = rowIdentity(row)
			if key then selectedParents[key] = true end
		end
	end
	local out, seen = {}, {}
	for i = 1, #rows do
		local row = rows[i]
		local key = rowIdentity(row)
		local coveredChild = row and row._gsRowKind == "child" and row.parentRowKey
			and selectedParents[row.parentRowKey]
		if row and row.fullType and key and not seen[key] and not coveredChild then
			seen[key] = true
			out[#out + 1] = row
		end
	end
	return out
end

local function normalizeVisualRows(rows, payloadRows, fallback)
	rows = rows and #rows > 0 and rows or { fallback }
	local out, seen = {}, {}
	for i = 1, #rows do
		local row = rows[i]
		local key = rowIdentity(row)
		-- La lista visual ya fue compuesta por buildDragState(): al arrastrar
		-- una cabecera desplegada contiene deliberadamente padre + hijos. Filtrar
		-- contra el payload (que solo lleva hijos exactos) eliminaba la cabecera
		-- del ghost y hacia parecer que se movia otra seleccion.
		if row and not row._gsPager and key and not seen[key] then
			seen[key] = true
			out[#out + 1] = row
		end
	end
	if #out == 0 and fallback then out[1] = fallback end
	return out
end

local function logCancelled(reason)
	GlobalStorageSiK.Log.debug("WithdrawDrag", "dragCancelled reason=" .. tostring(reason))
end

--- Inicia un drag con estado visual y payload deliberadamente separados.
---@param rowData table
---@param amount number|nil
---@param payloadRows table[]|nil
---@param visualRows table[]|nil
---@param sourceWidget ISPanel|nil
function GlobalStorageSiK.TerminalWithdrawDrag.begin(rowData, amount, payloadRows, visualRows, sourceWidget)
	if not rowData or not rowData.fullType then return false end
	-- Un nuevo drag nunca hereda ghost/captura/Escape de una selección anterior.
	if activeDrag then GlobalStorageSiK.TerminalWithdrawDrag.cancel("replaced") end
	payloadRows = normalizePayloadRows(payloadRows, rowData)
	visualRows = normalizeVisualRows(visualRows, payloadRows, rowData)
	local captureOwner = sourceWidget and sourceWidget.terminal or nil
        activeDrag = {
		payloadRows = payloadRows,
		visualRows = visualRows,
		rowData = rowData,
		amount = amount or 1,
                sourceWidget = sourceWidget,
                captureOwner = captureOwner,
                playerNum = (captureOwner and captureOwner.playerNum) or 0,
	}
	-- La captura empieza solo al superar el umbral. Así el origen recibe el
	-- mouseUp aunque el cursor ya este sobre ISInventoryPane/loot vanilla.
	if captureOwner and captureOwner.setCapture then
		captureOwner:setCapture(true)
		captureOwner._gsWithdrawDragCaptured = true
	end
	if sourceWidget and GlobalStorageSiK.RemoteItemDetail then
		GlobalStorageSiK.RemoteItemDetail.deactivate(sourceWidget)
	end
	if sourceWidget and sourceWidget._gsTooltip then
		if GlobalStorageSiK.TerminalItems and GlobalStorageSiK.TerminalItems.hideRowTooltip then
			GlobalStorageSiK.TerminalItems.hideRowTooltip(sourceWidget)
		else
			sourceWidget._gsTooltip:removeFromUIManager()
			sourceWidget._gsTooltip:setVisible(false)
		end
	end
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
	local x, y = pointerPosition(dragPreviewPanel.width, dragPreviewPanel.height,
		dragPreviewPanel.playerNum)
	dragPreviewPanel:setX(x)
	dragPreviewPanel:setY(y)
	return true
end

local function clearDrag(cancelReason)
	local source = activeDrag and activeDrag.sourceWidget or nil
	local captureOwner = activeDrag and activeDrag.captureOwner or nil
	if captureOwner and captureOwner.setCapture and captureOwner._gsWithdrawDragCaptured then
		-- Liberacion unica y comun para drop valido, invalido, Escape, cierre y
		-- limpieza de sesion. No queda captura viva aunque el preview ya no exista.
		pcall(function() captureOwner:setCapture(false) end)
		captureOwner._gsWithdrawDragCaptured = nil
	end
	activeDrag = nil
	GlobalStorageSiK.TerminalWithdrawDrag.activePreview = nil
	GlobalStorageSiK.TerminalWithdrawDrag.activePreviewTypes = nil
	destroyPreview()
	if GlobalStorageSiK.TerminalItems then
		-- El pool puede haberse reciclado mientras la retirada esperaba respuesta.
		-- Limpiar primero todos sus estados visuales y solo después permitir el
		-- refresco aplazado impide que una fila inferior herede hover/tooltip.
		if GlobalStorageSiK.TerminalItems.resetVirtualInteraction then
			GlobalStorageSiK.TerminalItems.resetVirtualInteraction(source and source.listPanel or nil)
		end
		if GlobalStorageSiK.TerminalItems.onInteractionFinished then
			GlobalStorageSiK.TerminalItems.onInteractionFinished(source and source.listPanel or nil)
		end
	end
	if cancelReason then
		logCancelled(cancelReason)
	end
end

function GlobalStorageSiK.TerminalWithdrawDrag.cancel(reason)
	if not activeDrag then return false end
	clearDrag(reason or "cancelled")
	return true
end

function GlobalStorageSiK.TerminalWithdrawDrag.tryDropOnPane(pane)
	if not activeDrag then return false end
        local drag = activeDrag
	local player = GlobalStorageSiK.NetClient.getPlayer(drag.playerNum)
	pane = pane or GlobalStorageSiK.ContainerTargets.findPaneAtMouse(true, player, drag.playerNum)
	if not pane then
		clearDrag("pane=nil")
		return false
	end
	local container = GlobalStorageSiK.ContainerTargets.getPaneContainer(pane)
	if not container then
		GlobalStorageSiK.ContainerTargets.debugDropTarget("container=nil")
		clearDrag("container=nil")
		return false
	end
        if not player or not GlobalStorageSiK.ContainerTargets.canReceiveWithdraw(player, container) then
		GlobalStorageSiK.ContainerTargets.debugDropTarget("accessDenied")
		clearDrag("accessDenied")
		return false
	end
	local key = GlobalStorageSiK.ContainerTargets.keyForContainer(player, container)
	if not key then
		GlobalStorageSiK.ContainerTargets.debugDropTarget("key=nil")
		clearDrag("key=nil")
		return false
	end
	local terminal = GlobalStorageSiK.TerminalUI and GlobalStorageSiK.TerminalUI.instance
	local searchQuery = terminal and terminal.getSearchQuery and terminal:getSearchQuery() or ""
	local rows = drag.payloadRows or { drag.rowData }
	clearDrag(nil)
	-- La cabecera conserva exactamente el mismo payload semantico colapsada,
	-- expandida o paginada. Las paginas son solo presentacion; el servidor
	-- reconstruye el grupo fisico a partir de rowKey + revision.
	local sent
	if #rows > 1 then
		sent = GlobalStorageSiK.WithdrawClient.sendWithdrawBatch(rows, drag.amount, key, searchQuery)
	else
		sent = GlobalStorageSiK.WithdrawClient.sendWithdraw(rows[1], drag.amount, key, searchQuery)
	end
	if sent then
		GlobalStorageSiK.Log.debug("WithdrawDrag", "dragDropSent")
		GlobalStorageSiK.ContainerTargets.debugDropTarget("send=true")
	else
		logCancelled("sendRejected")
	end
	return sent
end

function GlobalStorageSiK.TerminalWithdrawDrag.finishAtPointer()
	if not activeDrag then return false end
	if activeDrag.finishing then return false end
	activeDrag.finishing = true
	GlobalStorageSiK.Log.debug("WithdrawDrag", "dragDropAttempt")
	local player = GlobalStorageSiK.NetClient.getPlayer(activeDrag.playerNum)
	local pane = GlobalStorageSiK.ContainerTargets.findPaneAtMouse(true, player, activeDrag.playerNum)
	if not pane then
		clearDrag("pane=nil")
		return false
	end
	return GlobalStorageSiK.TerminalWithdrawDrag.tryDropOnPane(pane)
end

-- Compatibilidad con el cargador anterior. Ya no instala OnTick ni monkey
-- patches globales: el widget de origen captura move/up/outside.
function GlobalStorageSiK.TerminalWithdrawDrag.installHooks()
	ensureTransientCleanup()
	return true
end
