--[[
	GlobalStorageSiK - Retiro incremental desde red (cliente)
	Autor: SiK
	Descripción: serializa todas las retiradas, exige respuesta correlacionada
	por micro-lote y elimina su OnTick al terminar o caducar.
]]

require "GS_NetClient"
require "GS_I18n"
require "GS_Log"
require "GS_PlayerUtils"
require "GS_Sandbox"
require "GS_UI_Feedback"
require "GS_OperationPacing"

-- Private worker: one captured gesture, one player, one physical destination.
-- Scheduling and routing belong to GS_WithdrawClient; no shared queue state.
return function(context)
local worker = {}
local function currentPlayer()
	local player = GlobalStorageSiK.NetClient.getPlayer(context.playerNum)
	if player ~= context.player then return nil end
	if player and player.isDead and player:isDead() then return nil end
	return player
end
local function sendCommand(command, payload)
	local player = currentPlayer()
	if not player then return false end
	return GlobalStorageSiK.NetClient.sendCommand(command, payload, player)
end

local RESPONSE_TIMEOUT_MS = 10000
-- A read-only recapture can take longer than a transfer ACK (12 s in TEST).
-- Transfers retry only their identical receipt-backed request, at most twice.
local SELECTION_REFRESH_TIMEOUT_MS = 30000
local MAX_QUEUED_REQUESTS = 4096

local queue = {}
local current = nil
local serial = 0
local tickInstalled = false
local nextDispatchMs = 0
local responseDeadlineMs = 0
local operation = nil
local traceSelectionRefresh
local beginSelectionRefresh

local function copyItemIds(itemIds, limit)
	local copied = {}
	local maximum = math.max(0, math.floor(tonumber(limit) or #(itemIds or {})))
	for i = 1, math.min(#(itemIds or {}), maximum) do
		copied[#copied + 1] = itemIds[i]
	end
	return copied
end

local function appendItemIds(target, itemIds)
	for i = 1, #(itemIds or {}) do target[#target + 1] = itemIds[i] end
end

-- Quita exclusivamente las identidades que el servidor confirma como movidas.
-- Las intentadas pero no movidas permanecen al frente para el siguiente lote.
local function consumeConfirmedItemIds(pendingItemIds, attemptedItemIds, movedItemIds)
	local attempted, confirmed = {}, {}
	for i = 1, #(attemptedItemIds or {}) do
		local itemId = tonumber(attemptedItemIds[i])
		if itemId then attempted[tostring(math.floor(itemId))] = true end
	end
	for i = 1, #(movedItemIds or {}) do
		local itemId = tonumber(movedItemIds[i])
		local key = itemId and tostring(math.floor(itemId)) or nil
		if not key or not attempted[key] or confirmed[key] then
			return pendingItemIds or {}, 0, false
		end
		confirmed[key] = true
	end
	local remaining = {}
	local consumed = 0
	for i = 1, #(pendingItemIds or {}) do
		local itemId = pendingItemIds[i]
		local numericId = tonumber(itemId)
		local key = numericId and tostring(math.floor(numericId)) or tostring(itemId)
		if confirmed[key] then
			confirmed[key] = nil
			consumed = consumed + 1
		else
			remaining[#remaining + 1] = itemId
		end
	end
	return remaining, consumed, true
end

local function runCompletion(request, ok, result)
	local callback = request and request.onComplete
	if not callback then return end
	request.onComplete = nil
	local callbackOk, err = pcall(callback, ok == true, result or {})
	if not callbackOk then
		GlobalStorageSiK.Log.error("WithdrawClient", "completion callback failed", tostring(err))
	end
end

local function failQueuedCompletions(cancelledCurrent, cancelledQueue, reason)
	if cancelledCurrent then
		runCompletion(cancelledCurrent, false, {
			reason = reason or "cancelled",
			moved = cancelledCurrent.totalMoved or 0,
			itemIds = cancelledCurrent.movedItemIds or {},
			unmovedItemIds = cancelledCurrent.pendingItemIds or {},
			unmovedCount = math.max(0,
				math.floor(tonumber(cancelledCurrent.remaining) or 0)),
		})
	end
	for i = 1, #cancelledQueue do
		runCompletion(cancelledQueue[i], false, {
			reason = reason or "cancelled",
			moved = 0,
			itemIds = {},
		})
	end
end

local function nowMs()
	return getTimestampMs and getTimestampMs() or 0
end

local function uninstallTickIfIdle()
	if current or #queue > 0 then return end
	if tickInstalled and Events and Events.OnTick then
		-- The coordinator removes its sole hook once every player is idle.
	end
	tickInstalled = false
	nextDispatchMs = 0
	responseDeadlineMs = 0
end

local function ensureTickInstalled()
	if tickInstalled or not Events or not Events.OnTick then return end
	tickInstalled = true
	context.requestPump()
end

local function showLocalError(key)
	local player = currentPlayer()
	if player then
		pcall(function()
			GlobalStorageSiK.UIFeedback.halo(player, GlobalStorageSiK.I18n.text(key),
				255, 120, 120, 250, { tone = "danger", channel = "withdraw" })
		end)
	end
end

local function showProgress(force)
	if not operation then return end
	local now = nowMs()
	if not force and now - (operation.lastProgressMs or 0) < 1000 then return end
	operation.lastProgressMs = now
	local player = currentPlayer()
	if not player then return end
	local text = GlobalStorageSiK.I18n.text("IGUI_GS_WithdrawPending")
	if (operation.totalExpected or 0) > 0 then
		text = text .. " " .. tostring(operation.totalMoved or 0)
			.. "/" .. tostring(operation.totalExpected)
	end
	-- Una operación puede contener grupos de títulos con varias unidades. Las
	-- filas internas son un detalle de cola, no progreso del jugador: mostrar
	-- ambas cifras convertía 8/34 en el engañoso "(6/28)" para VHS paginados.
	-- El estado siempre comunica únicamente unidades físicas confirmadas.
	GlobalStorageSiK.UIFeedback.updateOperation(context.playerNum, context.operationId,
		text, operation.totalMoved, operation.totalExpected)
end

local function activeNetworkId() return context.networkId end

local function revisionNumber(value)
 local revision=tonumber(value)
 if not revision or revision~=revision or revision<0 or revision==math.huge
  or revision~=math.floor(revision) then return nil end
 return revision
end
local function catalogState()
 local client=GlobalStorageSiK.Client
 return client and client.terminalStateByPlayer and client.terminalStateByPlayer[context.playerNum]
end
local function sameOpening(state)
 if not currentPlayer() or not operation then return false end
 local identity=operation.catalogIdentity
 local live=catalogState()
 if identity then
  if not live or live.networkId~=operation.networkId then return false end
  local client=GlobalStorageSiK.Client
  if identity.openSeq~=nil and client.terminalOpenSeqByPlayer
   and client.terminalOpenSeqByPlayer[context.playerNum]~=identity.openSeq then return false end
  for key,value in pairs(identity) do
   if live[key]~=value or state and state[key]~=nil and state[key]~=value then return false end
  end
 end
 return not state or state.playerNum==nil or tonumber(state.playerNum)==context.playerNum
end

---@param networkId string|nil
---@param searchQuery string|nil
---@return table|nil
local function ensureOperation(networkId, searchQuery)
	if operation then return operation end
	if GlobalStorageSiK.TerminalSync and GlobalStorageSiK.TerminalSync.beginManagedTransfer
		and not GlobalStorageSiK.TerminalSync.beginManagedTransfer("withdraw", networkId, searchQuery, context.playerNum, context.operationId) then
		return nil
	end
	if not GlobalStorageSiK.UIFeedback.beginOperation(currentPlayer(), context.operationId, networkId, "withdraw") then
		if GlobalStorageSiK.TerminalSync and GlobalStorageSiK.TerminalSync.finishManagedTransfer then
			GlobalStorageSiK.TerminalSync.finishManagedTransfer("withdraw", searchQuery, nil, context.playerNum, context.operationId)
		end
		return nil
	end
	local live=catalogState()
	local identity=nil
	if live and live.networkId==networkId then
		identity={}
		for _,key in ipairs({"openSeq","catalogScope","replicaEpoch","topologySequence"}) do identity[key]=live[key] end
	end
	operation = {
		catalogIdentity = identity,
		totalMoved = 0,
		totalExpected = 0,
		rowsTotal = 0,
		rowsDone = 0,
		startedMs = nowMs(),
		lastProgressMs = 0,
		networkId = networkId,
		searchQuery = searchQuery,
		lastRevision = nil,
		inspected = 0,
		skipped = 0,
		batches = 0,
		pacing = GlobalStorageSiK.OperationPacing.resolve({ operationType = "withdraw" }),
	}
	GlobalStorageSiK.Log.info("WithdrawClient", "operation started",
		GlobalStorageSiK.OperationPacing.describe(operation.pacing))
	return operation
end

local function finishCurrent(delayNext)
	current = nil
	responseDeadlineMs = 0
	if #queue > 0 then
		nextDispatchMs = nowMs() + (delayNext and operation and operation.pacing.batchDelayMs or 0)
		ensureTickInstalled()
		return true
	else
		uninstallTickIfIdle()
	end
	return false
end

local function startNext()
	if current or #queue == 0 then
		uninstallTickIfIdle()
		return
	end
	current = table.remove(queue, 1)
	current.totalMoved = 0
	current.movedItemIds = {}
	current.remaining = current.amount > 0 and math.floor(current.amount) or nil
	current.all = current.openEnded == true
	current.sequence = 0
	current.selectionTicket = nil
	current.selectionSequence = 1
	current.staleRetryCount = 0
	current.awaitingFreshSelection = false
	current.selectionMode = current.rowData.selectionMode
		or ((current.rowData.itemIds and #current.rowData.itemIds > 0) and "exact_ids" or "aggregate")
	if current.selectionMode == "exact_ids" then
		current.pendingItemIds = copyItemIds(current.rowData.itemIds, current.remaining)
		current.remaining = #current.pendingItemIds
		if operation and current.expectedCount ~= current.remaining then
			operation.totalExpected = math.max(0,
				(operation.totalExpected or 0) - (current.expectedCount or 0) + current.remaining)
		end
		current.expectedCount = current.remaining
	end
	if current.selectionMode == "exact_group" and not current.quantityLimit then
		current.all = true
		current.remaining = nil
	end
	nextDispatchMs = nowMs()
	ensureTickInstalled()
end

local function dispatchCurrent()
	if not current then return end
	-- A retained row can predate the complete view even in a new gesture.
	-- This is only a revision floor; beginSelectionRefresh still requires
	-- a fenced complete view before copying the consumed selector.
	if current.selectionMode=="exact_group" and not current.selectionTicket and operation then
		local live=catalogState()
		local revision=live and live.networkId==current.networkId
			and sameOpening(live) and revisionNumber(live.inventoryRevision)
		if revision then operation.lastRevision=math.max(operation.lastRevision or 0,revision) end
	end
	-- An ACK proves that the inventory changed, not the contents of another row.
	-- Reuse a complete current view or wait before sending an avoidable stale intent.
	if current.selectionMode=="exact_group" and not current.selectionTicket
		and operation and operation.lastRevision
		and (revisionNumber(current.rowData.selectionRevision) or -1)<operation.lastRevision then
		beginSelectionRefresh("continuation")
		return
	end
	if current.retryOnDispatch then
		current.staleRetryCount=(current.staleRetryCount or 0)+1
		current.retryOnDispatch=nil
	end
	current.sequence = current.sequence + 1
	local batchUnits = operation and operation.pacing and operation.pacing.batchUnits or 10
	if GlobalStorageSiK.FloorTargets and GlobalStorageSiK.FloorTargets.isKey(current.targetKey) then
		batchUnits = 1
	end
	local ticketHasBoundedRemainder = current.selectionMode == "exact_group"
		and current.selectionTicket ~= nil and current.remaining ~= nil
	local requested = ticketHasBoundedRemainder
		and math.min(current.remaining, batchUnits)
		or (current.all and batchUnits or math.min(current.remaining or 1, batchUnits))
	current.batchRequested = requested
	current.requestId = current.logicalId .. ":" .. tostring(current.sequence)
	local exactItemIds = {}
	if current.selectionMode == "exact_ids" then
		for i = 1, math.min(#(current.pendingItemIds or {}), requested) do
			exactItemIds[#exactItemIds + 1] = current.pendingItemIds[i]
		end
	end
	current.batchItemIds = exactItemIds
	local expectedRequestId = current.requestId
	-- Armar ANTES del envío: en SP/host el bypass local puede entregar y
	-- resolver actionResult de forma síncrona dentro de sendCommand.
	current.responsePending = true
	responseDeadlineMs = nowMs() + RESPONSE_TIMEOUT_MS
	nextDispatchMs = math.huge
	GlobalStorageSiK.Log.debug("WithdrawClient", "withdraw-intent mode="
		.. tostring(current.selectionMode)
		.. " rowKey=" .. tostring(current.rowData.rowKey)
		.. " revision=" .. tostring(current.rowData.selectionRevision)
		.. " count=" .. tostring(current.rowData.count)
		.. " destination=" .. tostring(current.targetKey))
	local payload = {
		-- Un itemId exacto ya identifica una unidad fisica unica. No acoplarlo
		-- al nodo que produjo la captura: el servidor vuelve a buscarlo solo en
		-- los contenedores accesibles de esta red y valida tipo/selector antes de
		-- moverlo. Esto tolera una captura de nodo renovada y permite que varias
		-- unidades iguales repartidas por la red compartan un microlote.
		sourceNodeId = current.selectionMode == "exact_ids"
			and nil or current.rowData.sourceNodeId,
		fullType = current.rowData.fullType,
		-- mediaTitle (2026-08-26, fix de agrupacion de VHS): cuando la fila
		-- retirada es una cinta VHS/radio, esta fila representa SOLO las
		-- cintas con este contenido exacto (ver GS_ItemSnapshot.lua) - hay que
		-- decirselo al servidor para que no tome cualquier cinta del mismo
		-- fullType generico, sino una que enseñe justo esto. nil para
		-- cualquier otro item (comportamiento identico a siempre).
		-- En una seleccion exacta el itemId es la identidad autoritativa. No
		-- conservar selectores derivados de la captura (titulo, indice o firma):
		-- pueden cambiar entre el snapshot y el movimiento y bloquear una unidad
		-- que el servidor volvera a validar por ID, tipo, red y permisos.
		mediaTitle = current.selectionMode == "exact_ids" and nil or current.rowData.mediaTitle,
		mediaIndex = current.selectionMode == "exact_ids" and nil or current.rowData.mediaIndex,
		fullTypes = current.rowData.aggregateAllowed and current.rowData.fullTypes or nil,
		dynamicSignature = current.selectionMode == "exact_ids"
			and nil or current.rowData.dynamicSignature,
		itemIds = exactItemIds,
		selectionMode = current.selectionMode,
		rowKey = not current.selectionTicket and current.rowData.rowKey or nil,
		selectionRevision = not current.selectionTicket and current.rowData.selectionRevision or nil,
		selectionTicket = current.selectionTicket,
		selectionSequence = current.selectionSequence,
		-- El servidor 1.5.7+ sella y avanza exact_group completo. Cero conserva
		-- la semantica historica de "toda la fila"; servidores anteriores ignoran
		-- este campo y siguen confirmando un microlote por RTT.
		taskAmount = current.selectionMode == "exact_group"
			and (current.quantityLimit or 0) or nil,
		amount = requested,
		targetKey = current.targetKey,
		searchQuery = current.searchQuery or "",
		withdrawId = current.requestId,
		pacingId = current.logicalId,
		pacingFinal = not current.all and (current.remaining or 0) <= requested,
		networkId = current.networkId,
		returnItemIds = current.returnItemIds == true,
		readLoanId = current.readLoanId,
	}
	current.sentPayload, current.responseRetries = payload, 0
	local sent = sendCommand("withdrawItem", payload)
	if not sent and current and current.requestId == expectedRequestId then
		GlobalStorageSiK.Log.error("WithdrawClient", "send failed",
			"withdrawId=" .. tostring(expectedRequestId))
		showLocalError("IGUI_GS_InternalTransferError")
		worker.cancelAll("send_failed")
	end
end

function worker.onTick()
	if not currentPlayer() then worker.cancelAll("player_unavailable"); return end
	local now = nowMs()
	if not current then
		if #queue > 0 and now >= nextDispatchMs then startNext() end
		return
	end
	if responseDeadlineMs > 0 then
		if now < responseDeadlineMs then return end
		if current.awaitingFreshSelection then
			GlobalStorageSiK.Log.debug("WithdrawClient", "selection refresh expired",
				"network=" .. tostring(current.networkId)
					.. " withdrawId=" .. tostring(current.requestId))
			local player = currentPlayer()
			if player then
				GlobalStorageSiK.UIFeedback.halo(player,
					GlobalStorageSiK.I18n.text("IGUI_GS_ScanReason_snapshot_stale"),
					220, 220, 220, 1800)
			end
			worker.cancelAll("selection_stale")
			return
		end
		-- Solo el recibo autoritativo permite repetir exactamente esta intención.
		-- Agotados los reintentos se aborta sin avanzar a las siguientes filas.
		if current.sentPayload and current.sentPayload.withdrawEpoch and (current.responseRetries or 0) < 2 then
			current.responseRetries = (current.responseRetries or 0) + 1
			responseDeadlineMs = now + RESPONSE_TIMEOUT_MS
			-- Preserve the exact request, including floor and receipt sequences.
			-- SP can complete synchronously, so do not touch current after sending.
			sendCommand("withdrawItem", current.sentPayload)
			return
		end
		GlobalStorageSiK.Log.error("WithdrawClient", "response timeout",
			"withdrawId=" .. tostring(current.requestId)
				.. " movedConfirmed=" .. tostring(current.totalMoved or 0))
		showLocalError("IGUI_GS_InternalTransferError")
		worker.cancelAll("response_timeout")
		return
	end
	if now >= nextDispatchMs then dispatchCurrent() end
end

--- Cancela el retiro activo y toda la cola local. No inicia otro trabajo.
function worker.cancelAll(reason)
	if traceSelectionRefresh then
		traceSelectionRefresh(current and current.refreshTraceState, "selector", reason or "cancelled", true)
	end
	local cancelledOperation = operation
	local cancelledCurrent = current
	local cancelledQueue = queue
	GlobalStorageSiK.UIFeedback.finishOperation(context.playerNum, context.operationId)
	if cancelledCurrent and (cancelledCurrent.selectionTicket
		or cancelledCurrent.sentPayload and cancelledCurrent.sentPayload.taskAmount ~= nil) then
		sendCommand("cancelWithdrawSelection", {
			networkId = cancelledCurrent.networkId,
			selectionTicket = cancelledCurrent.selectionTicket,
			withdrawId = cancelledCurrent.requestId,
		})
	end
	if operation then
		GlobalStorageSiK.Log.warn("WithdrawClient", "operation cancelled moved="
			.. tostring(operation.totalMoved or 0)
			.. " rows=" .. tostring(operation.rowsDone or 0)
			.. "/" .. tostring(operation.rowsTotal or 0)
			.. " cancelled=true timeout=" .. tostring(reason == "response_timeout")
			.. " error=" .. tostring(reason ~= nil and reason ~= "cancelled")
			.. " " .. GlobalStorageSiK.OperationPacing.describe(operation.pacing))
	end
	queue = {}
	current = nil
	operation = nil
	responseDeadlineMs = 0
	uninstallTickIfIdle()
	-- Release visual ownership before callbacks can start another gesture.
	if cancelledOperation and GlobalStorageSiK.TerminalSync
		and GlobalStorageSiK.TerminalSync.finishManagedTransfer then
		GlobalStorageSiK.TerminalSync.finishManagedTransfer(
			"withdraw", cancelledOperation.searchQuery, cancelledOperation.lastRevision, context.playerNum, context.operationId)
	end
	failQueuedCompletions(cancelledCurrent, cancelledQueue, reason)
end

--- Compatibilidad con callers antiguos: liberar ya significa cancelar, nunca
--- avanzar ante una respuesta no correlacionada.
function worker.clearPending()
	worker.cancelAll()
end

function worker.isPending()
	return current ~= nil or #queue > 0
end

--- Reanuda una sola vez un gesto exact_group cuando llega el catálogo fresco
--- solicitado expresamente tras selection_stale. No consulta páginas ni crea
--- polling: el terminalState autoritativo es el único disparador y el timeout
--- acotado ya gestionado por onTick cancela la espera si nunca llega.
---@param state table|nil
---@return boolean consumed
traceSelectionRefresh = function(state, stage, reason, final, completeReplica)
	if not current or current.awaitingFreshSelection ~= true then return end
	current.lastRefreshRejection = not final and reason or current.lastRefreshRejection
	local trace = GlobalStorageSiK.NetTrace
	if not trace or not trace.isEnabled then return end
	local enabledOk, enabled = pcall(trace.isEnabled)
	if not enabledOk or not enabled then return end
	state = state or {}
	current.refreshTraceState = current.refreshTraceState or {}
	for _, key in ipairs({"snapshotCertified", "snapshotRevision", "inventoryRevision", "openSeq", "viewSequence", "replicaPartial"}) do
		current.refreshTraceState[key] = state[key]
	end
	if current.refreshOutcomeLogged or current.refreshDecisionLogged and not final then return end
	current.refreshDecisionLogged = true
	if final then current.refreshOutcomeLogged = true end
	local rowRevision = current.rowData.selectionRevision
	if current.freshSelectionRowSeen then rowRevision = current.freshSelectionRowRevision end
	pcall(trace.write, "Withdraw: selection refresh",
		"operationId=" .. tostring(context.operationId) .. " withdrawId=" .. tostring(current.requestId)
		.. " player=" .. tostring(context.playerNum) .. " network=" .. tostring(current.networkId)
		.. " rowKey=" .. tostring(current.rowData.rowKey) .. " fullType=" .. tostring(current.rowData.fullType)
		.. " sourceNodeId=" .. tostring(current.rowData.sourceNodeId)
		.. " worker=true stage=" .. tostring(stage) .. " reason=" .. tostring(reason)
		.. " lastRejected=" .. tostring(current.lastRefreshRejection)
		.. " snapshotCertified=" .. tostring(state.snapshotCertified)
		.. " snapshotRevision=" .. tostring(state.snapshotRevision)
		.. " inventoryRevision=" .. tostring(state.inventoryRevision)
		.. " requiredRevision=" .. tostring(operation and operation.lastRevision)
		.. " refreshReason=" .. tostring(current.refreshReason)
		.. " refreshWaitMs=" .. tostring(math.max(0, nowMs()-(current.refreshStartedMs or nowMs())))
		.. " retryCount=" .. tostring(current.staleRetryCount or 0)
		.. " staleRevision=" .. tostring(current.staleSelectionRevision)
		.. " rowRevision=" .. tostring(rowRevision)
		.. " openSeq=" .. tostring(state.openSeq) .. " viewSequence=" .. tostring(state.viewSequence)
		.. " replicaPartial=" .. tostring(state.replicaPartial)
		.. " completeReplica=" .. tostring(completeReplica == true))
end

function worker.onCatalogRefreshRejected(state, stage, reason)
	traceSelectionRefresh(state, stage, reason, false)
end

function worker.onTerminalState(state, completeReplica)
	if not current or current.awaitingFreshSelection ~= true or not state then return false end
	local function reject(reason)
		traceSelectionRefresh(state, "selector", reason, false, completeReplica)
		return false
	end
	-- The transient proof comes only from the complete replica's fenced commit
	-- callback. It is never inferred from a server payload or stored on a row.
	local selectorCertified = state.snapshotCertified == true or completeReplica == true
	if state.networkId ~= current.networkId then return reject("network") end
	if not sameOpening(state) then return reject("opening") end
	if state.replicaPartial == true then return reject("partial") end
	if state.snapshotCertified == false and not selectorCertified then return reject("uncertified") end
	local freshRevision = revisionNumber(state.inventoryRevision)
	local staleRevision = revisionNumber(current.staleSelectionRevision)
	local requiredRevision = math.max(staleRevision or 0, operation and operation.lastRevision or 0)
	if not freshRevision or freshRevision < requiredRevision then return reject("revision") end
	if staleRevision == freshRevision and not selectorCertified then return reject("uncertified") end
	if state.sourceNodeId ~= current.rowData.sourceNodeId then
		if current.rowData.sourceNodeId and state.sourceNodeId == nil
			and selectorCertified and not current.freshNodeRequested then
			current.freshNodeRequested = true
			sendCommand("getNodeContents", {
				networkId = current.networkId, nodeId = current.rowData.sourceNodeId,
			})
		end
		return reject("source_node")
	end
	local freshRow = nil
	current.freshSelectionRowSeen = true
	current.freshSelectionRowRevision = nil
	for i = 1, #(state.items or {}) do
		local candidate = state.items[i]
		if candidate and candidate.rowKey == current.rowData.rowKey then
			freshRow = candidate
			break
		end
	end
	if not freshRow then
		traceSelectionRefresh(state, "selector", "selection_not_found", true, completeReplica)
		GlobalStorageSiK.Log.warn("WithdrawClient", "fresh selection missing",
			"rowKey=" .. tostring(current.rowData.rowKey)
				.. " revision=" .. tostring(freshRevision))
		worker.cancelAll("selection_not_found")
		return true
	end
	local previousExpected = current.expectedCount or 0
	-- Retained replica parents keep their materialization revision. Only this
	-- consumed selector gets the accepted complete view revision; shared rows
	-- and exact child IDs remain untouched, and the server still revalidates.
	local rowRevision = tonumber(freshRow.selectionRevision)
	current.freshSelectionRowRevision = rowRevision
	if not rowRevision or rowRevision ~= math.floor(rowRevision)
		or rowRevision < 0 or rowRevision > freshRevision then return reject("row_revision") end
	if rowRevision ~= freshRevision then
		if not selectorCertified then return reject("uncertified_retained_row") end
		local selector = {}
		for key, value in pairs(freshRow) do selector[key] = value end
		selector.selectionRevision = freshRevision
		freshRow = selector
	end
	current.rowData = freshRow
	current.selectionTicket = nil
	current.selectionSequence = 1
	current.ticketRemaining = nil
	current.remaining = current.quantityLimit and math.max(0, current.quantityLimit - (current.totalMoved or 0)) or nil
	current.expectedCount = current.quantityLimit or math.max(0, math.floor(tonumber(freshRow.count) or 0))
	if operation and current.expectedCount ~= previousExpected then
		operation.totalExpected = math.max(0,
			(operation.totalExpected or 0) - previousExpected + current.expectedCount)
	end
	traceSelectionRefresh(state, "selector", current.refreshReason=="continuation" and "continuation_scheduled" or "retry_scheduled", true, completeReplica)
	current.awaitingFreshSelection = false
	current.staleSelectionRevision = nil
	responseDeadlineMs = 0
	nextDispatchMs = nowMs()
	ensureTickInstalled()
	GlobalStorageSiK.Log.debug("WithdrawClient", "fresh selection received; continuing",
		"rowKey=" .. tostring(freshRow.rowKey)
			.. " revision=" .. tostring(freshRevision))
	return true
end


-- Arm the wait before any getter or send: local authority may deliver synchronously.
beginSelectionRefresh = function(reason)
 local waiting=current
 if not waiting or not sameOpening() then worker.cancelAll("selection_refresh_failed");return false end
 waiting.awaitingFreshSelection=true
 waiting.refreshReason=reason;waiting.refreshStartedMs=nowMs()
 waiting.refreshDecisionLogged=nil;waiting.refreshOutcomeLogged=nil
 waiting.lastRefreshRejection=nil;waiting.freshSelectionRowRevision=nil
 waiting.freshSelectionRowSeen=nil;waiting.refreshTraceState=nil
 waiting.staleSelectionRevision=waiting.rowData.selectionRevision
 waiting.selectionTicket=nil;waiting.selectionSequence=1
 waiting.retryOnDispatch=reason=="stale" or waiting.retryOnDispatch
 responseDeadlineMs=nowMs()+SELECTION_REFRESH_TIMEOUT_MS;nextDispatchMs=math.huge
 local replica=GlobalStorageSiK.NodeCatalogClient
 local sourceNodeId=waiting.rowData.sourceNodeId
 if not sourceNodeId and replica and replica.selectionState then
  local view=replica.selectionState(context.playerNum,waiting.networkId)
  if current~=waiting or not operation then return false end
  if not sameOpening() then worker.cancelAll("selection_refresh_failed");return false end
  if view and worker.onTerminalState(view,true) then return current~=nil end
  if current~=waiting then return false end
 end
 local sent
 if not sourceNodeId and replica and replica.requestSelectionRefresh then
  sent=replica.requestSelectionRefresh(context.playerNum,waiting.networkId)
 end
 if current~=waiting then return false end
 if not sameOpening() then worker.cancelAll("selection_refresh_failed");return false end
 if sent==nil then
  sent=sendCommand(sourceNodeId and "getNodeContents" or "requestItemIndex",{
   networkId=waiting.networkId,nodeId=sourceNodeId,searchQuery=waiting.searchQuery or "",
  })
 end
 if current~=waiting then return false end
 if not sent then worker.cancelAll("selection_refresh_failed");return false end
 return true
end

---@param rowData table
---@param amount number|nil
---@param targetKey string|nil
---@param searchQuery string|nil
---@param opts table|nil { networkId=string, returnItemIds=boolean, onComplete=fun(ok:boolean, result:table) }
---@return boolean
local function enqueueWithdraw(rowData, amount, targetKey, searchQuery, opts)
	if not rowData or not rowData.fullType then return false end
	if #queue + (current and 1 or 0) >= MAX_QUEUED_REQUESTS then return false end
	serial = serial + 1
	local numericAmount = tonumber(amount) or 1
	if numericAmount ~= numericAmount or numericAmount == math.huge or numericAmount == -math.huge then return false end
	local requested = math.floor(numericAmount)
	local quantityLimit = requested > 0 and requested or nil
	local openEnded = false
	if requested <= 0 then
		-- "Todo" trabaja contra la captura visible que inició el gesto. Conocer el
		-- total evita una sonda vacía por tipo y permite progreso determinista. Si
		-- un caller legacy no trae count, se conserva el fallback abierto.
		requested = math.max(0, math.floor(tonumber(rowData.count) or 0))
		openEnded = requested <= 0
	end
	local networkId = opts and opts.networkId or activeNetworkId()
	local op = operation
	if op and op.networkId and networkId and op.networkId ~= networkId then
		GlobalStorageSiK.Log.warn("WithdrawClient", "queue rejected across networks",
			"active=" .. tostring(op.networkId) .. " requested=" .. tostring(networkId))
		return false
	end
	op = ensureOperation(networkId, searchQuery)
	if not op then return false end
	op.rowsTotal = op.rowsTotal + 1
	if requested > 0 then op.totalExpected = op.totalExpected + requested end
	table.insert(queue, {
		logicalId = context.operationId .. ":" .. tostring(serial),
		rowData = rowData,
		amount = requested,
		quantityLimit = quantityLimit,
		openEnded = openEnded,
		targetKey = targetKey,
		searchQuery = searchQuery,
		networkId = op.networkId or networkId,
		returnItemIds = opts and opts.returnItemIds == true,
		readLoanId = opts and opts.readLoanId,
		onComplete = opts and opts.onComplete or nil,
		expectedCount = requested,
	})
	return true
end

---@param rowData table { fullType, count, ... }
---@param amount number|nil 1 = una unidad; 0 = todo el tipo
---@param targetKey string|nil
---@param searchQuery string|nil
---@param opts table|nil { networkId=string, returnItemIds=boolean, onComplete=fun(ok:boolean, result:table) }
---@return boolean
function worker.sendWithdraw(rowData, amount, targetKey, searchQuery, opts)
	if not enqueueWithdraw(rowData, amount, targetKey, searchQuery, opts) then
		GlobalStorageSiK.Log.error("WithdrawClient", "queue limit reached",
			"limit=" .. tostring(MAX_QUEUED_REQUESTS))
		showLocalError("IGUI_GS_InternalTransferError")
		if opts and opts.onComplete then
			local ok, err = pcall(opts.onComplete, false, { reason = "queue_rejected", moved = 0, itemIds = {} })
			if not ok then
				GlobalStorageSiK.Log.error("WithdrawClient", "rejected callback failed", tostring(err))
			end
		end
		return false
	end
	if not current then startNext() end
	showProgress(true)
	return true
end

--- Un ID exacto es más estricto que cualquier selector derivado (título VHS,
--- mediaIndex o firma dinámica): identifica una instancia física concreta que
--- el servidor vuelve a validar. Por ello varias filas exactas del mismo
--- fullType pueden compartir micro-lote, incluso si representan cintas con
--- títulos distintos. Conservar sus selectores al fusionarlas haría que el
--- servidor descartase los IDs de los otros títulos antes de compararlos.
--- No se agrupan filas sin IDs: esas sí conservan su selector autoritativo.
---@param rows table[]
---@return table[]
local function coalesceExactRows(rows)
	local grouped, order, passthrough = {}, {}, {}
	for i = 1, #rows do
		local row = rows[i]
		local ids = row and row.itemIds or nil
		if row and row.fullType and ids and #ids > 0 then
			local key = tostring(row.fullType)
			local merged = grouped[key]
			if not merged then
				merged = {}
				for field, value in pairs(row) do merged[field] = value end
				merged.itemIds = {}
				merged.count = 0
				-- `itemIds` es ahora el único selector. No permitir que un título o
				-- una firma de la primera fila reduzca un lote que contiene otros
				-- IDs exactos del mismo tipo.
				merged.mediaTitle = nil
				merged.mediaIndex = nil
				merged.dynamicSignature = nil
				merged.aggregateAllowed = false
				merged.fullTypes = nil
				merged.sourceNodeId = nil
				merged._gsMergedExact = true
				grouped[key] = merged
				order[#order + 1] = merged
			end
			local seen = merged._gsMergedIds or {}
			merged._gsMergedIds = seen
			for j = 1, #ids do
				local itemId = ids[j]
				if itemId ~= nil and not seen[itemId] then
					seen[itemId] = true
					merged.itemIds[#merged.itemIds + 1] = itemId
				end
			end
			merged.count = #merged.itemIds
		else
			passthrough[#passthrough + 1] = row
		end
	end
	local out = {}
	for i = 1, #order do
		order[i]._gsMergedIds = nil
		out[#out + 1] = order[i]
	end
	for i = 1, #passthrough do out[#out + 1] = passthrough[i] end
	return out
end

---@param rows table[]
---@param amount number|nil
---@param targetKey string|nil
---@param searchQuery string|nil
---@return boolean
function worker.sendWithdrawBatch(rows, amount, targetKey, searchQuery, options)
	if not rows or #rows == 0 then return false end
	local coalescedRows = coalesceExactRows(rows)
	if #queue + (current and 1 or 0) + #coalescedRows > MAX_QUEUED_REQUESTS then
		GlobalStorageSiK.Log.error("WithdrawClient", "batch queue limit reached",
			"rows=" .. tostring(#coalescedRows) .. " limit=" .. tostring(MAX_QUEUED_REQUESTS))
		showLocalError("IGUI_GS_InternalTransferError")
		return false
	end
	local okAny = false
	local remaining, moved, failed, failureReason = #coalescedRows, 0, false, nil
	local inventoryRevision = nil
	local requestOptions = nil
	if options then
		requestOptions = { networkId = options.networkId, onComplete = function(ok, result)
			remaining = remaining - 1
			moved = moved + (tonumber(result and result.moved) or 0)
			local revision = tonumber(result and result.inventoryRevision)
			if revision then inventoryRevision = math.max(inventoryRevision or 0, revision) end
			if not ok then failed = true; failureReason = result and result.reason or failureReason end
			if remaining == 0 and options.onComplete then
				options.onComplete(not failed, { moved = moved, reason = failureReason,
					inventoryRevision = inventoryRevision })
			end
		end }
	end
	for i = 1, #coalescedRows do
		local row = coalescedRows[i]
		-- El gesto aporta cantidad 1 porque comienza sobre una fila. Tras agrupar
		-- varias filas hijas exactas, la operacion debe cubrir todos sus IDs; usar
		-- aqui el 1 original reducia silenciosamente una multiseleccion a una sola
		-- unidad. La cola mantiene el microlote y el pacing habituales.
		local rowAmount = row._gsMergedExact and #(row.itemIds or {}) or amount
		if rowAmount == nil and row.selectionMode == "exact_group" then rowAmount = 0 end
		if enqueueWithdraw(row, rowAmount, targetKey, searchQuery, requestOptions) then
			okAny = true
		elseif requestOptions then
			requestOptions.onComplete(false, { reason = "queue_rejected", moved = 0 })
		end
	end
	if okAny and not current then startNext() end
	if okAny then showProgress(true) end
	return okAny
end

--- Consume solo la respuesta del micro-lote actualmente en vuelo.
---@param args table|nil
---@return boolean continuing
function worker.onActionResult(args)
	if not worker.matchesResponse(args) then return false end
	current.responsePending=false
	responseDeadlineMs = 0
	local transfer = args.transfer
	if not transfer or transfer.op ~= "withdraw" then
		worker.cancelAll("invalid_response")
		return false
	end
	if transfer.networkId ~= current.networkId then
		GlobalStorageSiK.Log.error("WithdrawClient", "response network mismatch",
			"expected=" .. tostring(current.networkId) .. " received=" .. tostring(transfer.networkId))
		worker.cancelAll("network_mismatch")
		return false
	end
	-- La lista visible se actualiza por delta confirmado en TerminalSync. No
	-- pedir además un catálogo completo por cada micro-lote; el servidor ya
	-- consolida una captura incremental después del periodo de calma.
	transfer.deferInventoryPull = true
	local moved = math.max(0, math.floor(tonumber(transfer.moved) or 0))
	local reason = transfer.reason and tostring(transfer.reason) or nil
	local selectionMode = transfer.selectionMode or current.selectionMode
	if selectionMode == "exact_group" then
		current.selectionTicket = transfer.selectionTicket
		current.selectionSequence = math.max(1,
			math.floor(tonumber(transfer.selectionSequence) or current.selectionSequence or 1))
		current.ticketRemaining = math.max(0, math.floor(tonumber(transfer.ticketRemaining) or 0))
		current.remaining = current.quantityLimit
			and math.min(current.ticketRemaining, math.max(0, current.quantityLimit - (current.totalMoved or 0) - moved))
			or current.ticketRemaining
		local selectionCount = current.quantityLimit or math.max(0, math.floor(tonumber(transfer.selectionCount) or 0))
		if selectionCount > 0 and selectionCount ~= (current.expectedCount or 0) then
			if operation then
				operation.totalExpected = math.max(0,
					(operation.totalExpected or 0) - (current.expectedCount or 0) + selectionCount)
			end
			current.expectedCount = selectionCount
		end
	end
	if reason == "selection_stale" and selectionMode == "exact_group" then
		if (current.staleRetryCount or 0) >= 1 then
			GlobalStorageSiK.Log.warn("WithdrawClient", "selection stale after explicit retry",
				"rowKey=" .. tostring(current.rowData.rowKey))
			worker.cancelAll("selection_stale")
			return false
		end
		local revision=revisionNumber(transfer.inventoryRevision)
		if operation and revision then operation.lastRevision=math.max(operation.lastRevision or 0,revision) end
		return beginSelectionRefresh("stale")
	end
	if selectionMode == "exact_ids" then
		local confirmedIds = transfer.itemIds or {}
		local pending, consumed, identitiesValid = consumeConfirmedItemIds(
			current.pendingItemIds, current.batchItemIds, confirmedIds)
		if not identitiesValid or consumed ~= moved then
			GlobalStorageSiK.Log.error("WithdrawClient", "exact response identity mismatch",
				"moved=" .. tostring(moved) .. " confirmedIds=" .. tostring(consumed)
					.. " withdrawId=" .. tostring(current.requestId)
					.. " network=" .. tostring(current.networkId))
			worker.cancelAll("identity_mismatch")
			return false
		end
		current.pendingItemIds = pending
		current.remaining = #pending
		appendItemIds(current.movedItemIds, confirmedIds)
	elseif selectionMode == "exact_group" and transfer.serverOwned ~= true then
		local confirmedIds = transfer.itemIds or {}
		if #confirmedIds ~= moved or moved > (current.batchRequested or 0) then
			GlobalStorageSiK.Log.error("WithdrawClient", "group response identity mismatch",
				"moved=" .. tostring(moved) .. " confirmedIds=" .. tostring(#confirmedIds)
					.. " withdrawId=" .. tostring(current.requestId)
					.. " network=" .. tostring(current.networkId))
			worker.cancelAll("identity_mismatch")
			return false
		end
		appendItemIds(current.movedItemIds, confirmedIds)
	end
	-- Solo contabilizar después de validar que cada unidad movida pertenece al
	-- microlote y a la operación/red que siguen en vuelo.
	current.totalMoved = (current.totalMoved or 0) + moved
	if GlobalStorageSiK.CatalogOverlay and moved > 0 then
		GlobalStorageSiK.CatalogOverlay.record(context.playerNum, current.networkId,
			current.rowData.rowKey, tonumber(transfer.inventoryRevision), moved, current.requestId)
	end
	if operation then
		operation.totalMoved = (operation.totalMoved or 0) + moved
		operation.inspected = (operation.inspected or 0) + moved
		operation.batches = (operation.batches or 0) + 1
		local revision = revisionNumber(transfer.inventoryRevision)
		if revision then
			operation.lastRevision = math.max(operation.lastRevision or 0, revision)
		end
	end
	if selectionMode ~= "exact_group" and selectionMode ~= "exact_ids" and not current.all then
		current.remaining = math.max(0, (current.remaining or 0) - moved)
	end
	-- not_found (tambien parcial) significa que la captura visible se agoto o
	-- quedo anticuada: termina este tipo y sigue con el siguiente. Los demas
	-- fallos son terminales para la operacion completa; no martillear todas las
	-- filas si se perdio energia, espacio, acceso o una mutacion fallo.
	local floorTarget = GlobalStorageSiK.FloorTargets and GlobalStorageSiK.FloorTargets.isKey(current.targetKey)
	local exhausted = not floorTarget
		and (reason == "not_found" or reason == "partial:not_found")
	local exactHasMore = (selectionMode == "exact_group" or selectionMode == "exact_ids")
		and (current.remaining or 0) > 0
	local hardFailure = transfer.reconcile == true or (args.ok ~= true and not exhausted)
		or (floorTarget and reason ~= nil and reason ~= "")
		or (reason and string.sub(reason, 1, 8) == "partial:" and not exhausted)
	if hardFailure then
		local cleanReason = reason and string.gsub(reason, "^partial:", "") or "unknown"
		GlobalStorageSiK.Log.debug("WithdrawClient", "operation stopped",
			"reason=" .. tostring(cleanReason)
				.. " movedConfirmed=" .. tostring(operation and operation.totalMoved or moved))
		args.ok = false
		args.message = GlobalStorageSiK.I18n.remote("IGUI_GS_WithdrawErrorReason", cleanReason)
		if floorTarget then
			args.message = GlobalStorageSiK.I18n.remote(cleanReason == "not_found"
				and "IGUI_GS_TransferSourceUnavailable" or "IGUI_GS_TransferWarning")
		end
		worker.cancelAll(cleanReason)
		return false
	end
	local shouldContinue = exactHasMore and moved > 0 and (args.ok == true or exhausted)
		or (selectionMode ~= "exact_group" and args.ok == true and moved > 0 and not exhausted
				and ((current.all) or (not current.all and (current.remaining or 0) > 0)))
	if shouldContinue then
		showProgress(false)
		nextDispatchMs = nowMs() + (operation and operation.pacing.batchDelayMs or 400)
		ensureTickInstalled()
		return true
	end
	if operation then operation.rowsDone = (operation.rowsDone or 0) + 1 end
	local completedRequest = current
	local unresolvedCount = math.max(0, math.floor(tonumber(completedRequest.remaining) or 0))
	if completedRequest.selectionTicket and (completedRequest.ticketRemaining or unresolvedCount) > 0 then
		sendCommand("cancelWithdrawSelection", {
			networkId = completedRequest.networkId,
			selectionTicket = completedRequest.selectionTicket,
		})
	end
	local completionResult = {
		reason = reason,
		moved = completedRequest and completedRequest.totalMoved or moved,
		itemIds = completedRequest.movedItemIds or {},
		unmovedItemIds = completedRequest.pendingItemIds or {},
		unmovedCount = unresolvedCount,
		sourceNodeId = transfer.sourceNodeId,
		networkId = transfer.networkId,
		fullType = transfer.fullType,
		inventoryRevision = transfer.inventoryRevision,
	}
	local hasNext = finishCurrent(true)
	if hasNext then
		runCompletion(completedRequest, completionResult.moved > 0, completionResult)
		showProgress(false)
		-- No mostrar un "Extraidos: 0" por cada tipo ya agotado; toda la
		-- selección es una sola operación visible y tendrá un único resultado.
		return true
	end
	local totalMoved = operation and operation.totalMoved or moved
	local elapsed = operation and (nowMs() - (operation.startedMs or nowMs())) or 0
	args.ok = totalMoved > 0
	args.message = GlobalStorageSiK.I18n.remote("IGUI_GS_WithdrawnCount", tostring(totalMoved))
	GlobalStorageSiK.Log.info("WithdrawClient", "operation complete moved="
		.. tostring(totalMoved)
		.. " rows=" .. tostring(operation and operation.rowsDone or 1)
		.. " elapsedMs=" .. tostring(elapsed)
		.. " inspected=" .. tostring(operation and operation.inspected or 0)
		.. " skipped=" .. tostring(operation and operation.skipped or 0)
		.. " batches=" .. tostring(operation and operation.batches or 0)
		.. " budgetExhaustions=0"
		.. " cancelled=false timeout=false error=false",
		GlobalStorageSiK.OperationPacing.describe(operation and operation.pacing))
	showProgress(true)
	if operation and GlobalStorageSiK.TerminalSync
		and GlobalStorageSiK.TerminalSync.finishManagedTransfer then
		GlobalStorageSiK.TerminalSync.finishManagedTransfer(
			"withdraw", operation.searchQuery, operation.lastRevision, context.playerNum, context.operationId)
	end
	operation = nil
	GlobalStorageSiK.UIFeedback.finishOperation(context.playerNum, context.operationId)
	runCompletion(completedRequest, completionResult.moved > 0, completionResult)
	return false
end

function worker.onProgress(args)
	if not worker.matchesResponse(args)
		or args.networkId ~= current.networkId then return false end
	responseDeadlineMs = nowMs() + RESPONSE_TIMEOUT_MS
	local moved = math.max(0, math.floor(tonumber(args.moved) or 0))
	local expected = operation and operation.totalExpected or tonumber(args.total) or 0
	local displayed = (operation and operation.totalMoved or current.totalMoved or 0) + moved
	local player = currentPlayer()
	if player then
		GlobalStorageSiK.UIFeedback.updateOperation(context.playerNum, context.operationId,
			GlobalStorageSiK.I18n.text("IGUI_GS_WithdrawPending") .. " "
				.. tostring(displayed) .. "/" .. tostring(expected), displayed, expected)
	end
	return true
end

function worker.matchesResponse(args)
	return current ~= nil and current.responsePending==true and current.requestId~=nil
		and args ~= nil and args.withdrawId == current.requestId
end
local tick = worker.onTick
worker.onTick = function()
	tick()
	context.afterDispatch(worker)
end
return worker
end
