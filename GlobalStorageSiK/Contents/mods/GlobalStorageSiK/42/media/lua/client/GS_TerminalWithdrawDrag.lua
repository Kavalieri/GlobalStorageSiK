--[[
	GlobalStorageSiK - Arrastre de retiro desde terminal hacia inventario vanilla
	El ghost es una señal compacta de selección; nunca replica la tabla origen.
]]

require "GS_NetClient"
require "GS_WithdrawClient"
require "GS_ContainerTargets"
local UI = require "GS_UI_Framework"
require "GS_I18n"

GlobalStorageSiK.TerminalWithdrawDrag = {}

local activeDrag = nil
local dragPreviewPanel = nil
local dragSession = nil
local cleanupRegistered = false
local PREVIEW_MIN_W = 180
local PREVIEW_MAX_W = 300
local PREVIEW_MAX_ROWS = 6
local PREVIEW_PAD = 8
local PREVIEW_ICON = 32
local PREVIEW_GAP = 8
local PREVIEW_ALPHA = 0.78

local function rowIdentity(row)
	return row and (row.rowKey or row.fullType) or nil
end

local function destroyPreview()
	if dragSession then
		dragSession:dispose()
		dragSession = nil
		dragPreviewPanel = nil
	elseif dragPreviewPanel then
		UI.DragGhost.destroy(dragPreviewPanel)
		dragPreviewPanel = nil
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
		-- Warehouse llama `indicator` al estado jerarquico; el contrato publico
		-- de DragGhost lo recibe como prefijo visual neutral.
		descriptor.prefix = descriptor.prefix or descriptor.indicator
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
			prefix = "+", count = "", texture = nil, overflow = true,
		}
	end
	local player = GlobalStorageSiK.NetClient.getPlayer()
	local playerNum = player and player.getPlayerNum and player:getPlayerNum() or 0
	dragSession = UI.Drag.begin({
		playerNum = playerNum,
		payload = activeDrag.payloadRows,
		createGhost = function()
			return UI.DragGhost.create({
				descriptors = descriptors, playerNum = playerNum, rowHeight = rowH,
				maxRows = PREVIEW_MAX_ROWS,
				minWidth = PREVIEW_MIN_W, maxWidth = PREVIEW_MAX_W,
				padding = PREVIEW_PAD, iconSize = PREVIEW_ICON, gap = PREVIEW_GAP,
				alpha = PREVIEW_ALPHA,
			})
		end,
		onCancel = function()
			GlobalStorageSiK.TerminalWithdrawDrag.cancel()
		end,
	})
	dragPreviewPanel = dragSession and dragSession.ghost or nil
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
		amount = math.max(1, math.floor(tonumber(amount) or 1)),
                sourceWidget = sourceWidget,
                captureOwner = captureOwner,
		playerNum = (captureOwner and captureOwner.playerNum) or 0,
	}
	GlobalStorageSiK.Log.debug("ExactWithdraw", "drag.begin row="
		.. tostring(rowIdentity(rowData)) .. " kind=" .. tostring(rowData._gsRowKind)
		.. " amount=" .. tostring(activeDrag.amount) .. " payloadRows="
		.. tostring(#payloadRows) .. " player=" .. tostring(activeDrag.playerNum))
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
	if not dragSession then return false end
	return dragSession:update()
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
		GlobalStorageSiK.Log.debug("ExactWithdraw", "drag.drop rejected=pane_nil")
		clearDrag("pane=nil")
		return false
	end
	local container = GlobalStorageSiK.ContainerTargets.getPaneContainer(pane)
	if not container then
		GlobalStorageSiK.Log.debug("ExactWithdraw", "drag.drop rejected=container_nil")
		GlobalStorageSiK.ContainerTargets.debugDropTarget("container=nil")
		clearDrag("container=nil")
		return false
	end
	if not player or not GlobalStorageSiK.ContainerTargets.canReceiveWithdraw(player, container) then
		GlobalStorageSiK.Log.debug("ExactWithdraw", "drag.drop rejected=access_denied")
		GlobalStorageSiK.ContainerTargets.debugDropTarget("accessDenied")
		clearDrag("accessDenied")
		return false
	end
	local key = GlobalStorageSiK.ContainerTargets.keyForContainer(player, container)
	if not key then
		GlobalStorageSiK.Log.debug("ExactWithdraw", "drag.drop rejected=target_key_nil")
		GlobalStorageSiK.ContainerTargets.debugDropTarget("key=nil")
		clearDrag("key=nil")
		return false
	end
	local terminal = GlobalStorageSiK.TerminalUI and GlobalStorageSiK.TerminalUI.instance
	local searchQuery = terminal and terminal.getSearchQuery and terminal:getSearchQuery() or ""
	local rows = drag.payloadRows or { drag.rowData }
	local sourcePanel = drag.sourceWidget and drag.sourceWidget.listPanel or nil
	local sourceController = drag.captureOwner
	clearDrag(nil)
	-- La cabecera conserva exactamente el mismo payload semantico colapsada,
	-- expandida o paginada. Las paginas son solo presentacion; el servidor
	-- reconstruye el grupo fisico a partir de rowKey + revision.
	local function onComplete(ok, result)
		if sourceController and type(sourceController.onWithdrawCompleted) == "function" then
			sourceController:onWithdrawCompleted(ok, result)
		elseif GlobalStorageSiK.TerminalItems.onWithdrawCompleted then
			GlobalStorageSiK.TerminalItems.onWithdrawCompleted(sourcePanel, sourceController, ok, result)
		end
	end
	local requestOptions = { onComplete = onComplete }
	local sent
	GlobalStorageSiK.Log.debug("ExactWithdraw", "drag.drop target=" .. tostring(key)
		.. " amount=" .. tostring(drag.amount) .. " rows=" .. tostring(#rows))
	if #rows > 1 then
		sent = GlobalStorageSiK.WithdrawClient.sendWithdrawBatch(
			rows, drag.amount, key, searchQuery, requestOptions)
	else
		sent = GlobalStorageSiK.WithdrawClient.sendWithdraw(
			rows[1], drag.amount, key, searchQuery, requestOptions)
	end
	if sent then
		GlobalStorageSiK.Log.debug("ExactWithdraw", "drag.send accepted mode="
			.. (#rows > 1 and "batch" or "single"))
		GlobalStorageSiK.Log.debug("WithdrawDrag", "dragDropSent")
		GlobalStorageSiK.ContainerTargets.debugDropTarget("send=true")
	else
		GlobalStorageSiK.Log.debug("ExactWithdraw", "drag.send rejected")
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
