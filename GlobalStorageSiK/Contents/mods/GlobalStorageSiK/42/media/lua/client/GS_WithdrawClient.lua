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

GlobalStorageSiK.WithdrawClient = {}

local RESPONSE_TIMEOUT_MS = 10000
local MAX_QUEUED_REQUESTS = 4096

local queue = {}
local current = nil
local serial = 0
local tickInstalled = false
local nextDispatchMs = 0
local responseDeadlineMs = 0
local operation = nil

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
			itemIds = {},
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
		Events.OnTick.Remove(GlobalStorageSiK.WithdrawClient.onTick)
	end
	tickInstalled = false
	nextDispatchMs = 0
	responseDeadlineMs = 0
end

local function ensureTickInstalled()
	if tickInstalled or not Events or not Events.OnTick then return end
	tickInstalled = true
	Events.OnTick.Add(GlobalStorageSiK.WithdrawClient.onTick)
end

local function showLocalError(key)
	local player = GlobalStorageSiK.NetClient.getPlayer()
	if player then
		pcall(function()
			GlobalStorageSiK.UIFeedback.halo(player, GlobalStorageSiK.I18n.text(key),
				255, 120, 120, 250, { tone = "danger", channel = "withdraw" })
		end)
	end
end

local function showProgress(force)
	if not operation then return end
	if GlobalStorageSiK.Sandbox.operationHaloFeedbackEnabled
		and not GlobalStorageSiK.Sandbox.operationHaloFeedbackEnabled() then return end
	local now = nowMs()
	if not force and now - (operation.lastProgressMs or 0) < 1000 then return end
	operation.lastProgressMs = now
	local player = GlobalStorageSiK.NetClient.getPlayer()
	if not player then return end
	local text = GlobalStorageSiK.I18n.text("IGUI_GS_WithdrawPending")
	if (operation.totalExpected or 0) > 0 then
		text = text .. " " .. tostring(operation.totalMoved or 0)
			.. "/" .. tostring(operation.totalExpected)
	end
	-- Una operación puede contener grupos de títulos con varias unidades. Las
	-- filas internas son un detalle de cola, no progreso del jugador: mostrar
	-- ambas cifras convertía 8/34 en el engañoso "(6/28)" para VHS paginados.
	-- El halo siempre comunica únicamente unidades físicas confirmadas.
	pcall(function()
		GlobalStorageSiK.UIFeedback.halo(player, text, 200, 220, 200, 220,
			{ channel = "withdraw-progress", dedupeKey = text, throttleMs = 1000 })
	end)
end

local function activeNetworkId()
	local ui = GlobalStorageSiK.TerminalUI and GlobalStorageSiK.TerminalUI.instance
	return ui and ui.terminalState and ui.terminalState.networkId
		or (GlobalStorageSiK.Client and GlobalStorageSiK.Client.activeNetworkId)
end

---@param networkId string|nil
---@param searchQuery string|nil
---@return table|nil
local function ensureOperation(networkId, searchQuery)
	if operation then return operation end
	if GlobalStorageSiK.TerminalSync and GlobalStorageSiK.TerminalSync.beginManagedTransfer
		and not GlobalStorageSiK.TerminalSync.beginManagedTransfer("withdraw", networkId, searchQuery) then
		return nil
	end
	operation = {
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
	current.remaining = current.amount > 0 and math.floor(current.amount) or nil
	current.all = current.openEnded == true
	current.sequence = 0
	current.itemIdOffset = 1
	current.selectionTicket = nil
	current.selectionSequence = 1
	current.staleRetryCount = 0
	current.awaitingFreshSelection = false
	current.selectionMode = current.rowData.selectionMode
		or ((current.rowData.itemIds and #current.rowData.itemIds > 0) and "exact_ids" or "aggregate")
	if current.selectionMode == "exact_group" then
		current.all = true
		current.remaining = nil
	end
	nextDispatchMs = nowMs()
	ensureTickInstalled()
end

local function dispatchCurrent()
	if not current then return end
	current.sequence = current.sequence + 1
	local batchUnits = operation and operation.pacing and operation.pacing.batchUnits or 10
	local ticketHasBoundedRemainder = current.selectionMode == "exact_group"
		and current.selectionTicket ~= nil and current.remaining ~= nil
	local requested = ticketHasBoundedRemainder
		and math.min(current.remaining, batchUnits)
		or (current.all and batchUnits or math.min(current.remaining or 1, batchUnits))
	current.batchRequested = requested
	current.requestId = current.logicalId .. ":" .. tostring(current.sequence)
	local exactItemIds = {}
	local visibleIds = current.rowData.itemIds or {}
	if current.selectionMode == "exact_ids" then
		for i = current.itemIdOffset, math.min(#visibleIds, current.itemIdOffset + requested - 1) do
			exactItemIds[#exactItemIds + 1] = visibleIds[i]
		end
	end
	local expectedRequestId = current.requestId
	-- Armar ANTES del envío: en SP/host el bypass local puede entregar y
	-- resolver actionResult de forma síncrona dentro de sendCommand.
	responseDeadlineMs = nowMs() + RESPONSE_TIMEOUT_MS
	nextDispatchMs = math.huge
	GlobalStorageSiK.Log.debug("WithdrawClient", "withdraw-intent mode="
		.. tostring(current.selectionMode)
		.. " rowKey=" .. tostring(current.rowData.rowKey)
		.. " revision=" .. tostring(current.rowData.selectionRevision)
		.. " count=" .. tostring(current.rowData.count)
		.. " destination=" .. tostring(current.targetKey))
	local sent = GlobalStorageSiK.NetClient.sendCommand("withdrawItem", {
		sourceNodeId = current.rowData.sourceNodeId,
		fullType = current.rowData.fullType,
		-- mediaTitle (2026-08-26, fix de agrupacion de VHS): cuando la fila
		-- retirada es una cinta VHS/radio, esta fila representa SOLO las
		-- cintas con este contenido exacto (ver GS_ItemSnapshot.lua) - hay que
		-- decirselo al servidor para que no tome cualquier cinta del mismo
		-- fullType generico, sino una que enseñe justo esto. nil para
		-- cualquier otro item (comportamiento identico a siempre).
		mediaTitle = current.rowData.mediaTitle,
		mediaIndex = current.rowData.mediaIndex,
		fullTypes = current.rowData.aggregateAllowed and current.rowData.fullTypes or nil,
		dynamicSignature = current.rowData.dynamicSignature,
		itemIds = exactItemIds,
		selectionMode = current.selectionMode,
		rowKey = not current.selectionTicket and current.rowData.rowKey or nil,
		selectionRevision = not current.selectionTicket and current.rowData.selectionRevision or nil,
		selectionTicket = current.selectionTicket,
		selectionSequence = current.selectionSequence,
		amount = requested,
		targetKey = current.targetKey,
		searchQuery = current.searchQuery or "",
		withdrawId = current.requestId,
		pacingId = current.logicalId,
		pacingFinal = not current.all and (current.remaining or 0) <= requested,
		networkId = current.networkId,
		returnItemIds = current.returnItemIds == true,
	})
	if not sent and current and current.requestId == expectedRequestId then
		GlobalStorageSiK.Log.error("WithdrawClient", "send failed",
			"withdrawId=" .. tostring(expectedRequestId))
		showLocalError("IGUI_GS_InternalTransferError")
		GlobalStorageSiK.WithdrawClient.cancelAll("send_failed")
	end
end

function GlobalStorageSiK.WithdrawClient.onTick()
	local now = nowMs()
	if not current then
		if #queue > 0 and now >= nextDispatchMs then startNext() end
		return
	end
	if responseDeadlineMs > 0 then
		if now < responseDeadlineMs then return end
		-- Retirar no es idempotente: jamás se reenvía a ciegas una petición cuya
		-- respuesta se perdió, porque podría retirar dos veces. Tampoco se continúa
		-- con las filas siguientes: se aborta la operación lógica completa y se
		-- elimina su OnTick, sin dejar trabajos latentes ni un resultado engañoso.
		GlobalStorageSiK.Log.error("WithdrawClient", "response timeout",
			"withdrawId=" .. tostring(current.requestId)
				.. " movedConfirmed=" .. tostring(current.totalMoved or 0))
		showLocalError("IGUI_GS_InternalTransferError")
		GlobalStorageSiK.WithdrawClient.cancelAll("response_timeout")
		return
	end
	if now >= nextDispatchMs then dispatchCurrent() end
end

--- Cancela el retiro activo y toda la cola local. No inicia otro trabajo.
function GlobalStorageSiK.WithdrawClient.cancelAll(reason)
	local cancelledOperation = operation
	local cancelledCurrent = current
	local cancelledQueue = queue
	if cancelledCurrent and cancelledCurrent.selectionTicket then
		GlobalStorageSiK.NetClient.sendCommand("cancelWithdrawSelection", {
			networkId = cancelledCurrent.networkId,
			selectionTicket = cancelledCurrent.selectionTicket,
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
	-- Limpiar primero evita que un callback que inicie una nueva operación sea
	-- borrado por la cancelación de la anterior.
	failQueuedCompletions(cancelledCurrent, cancelledQueue, reason)
	if cancelledOperation and GlobalStorageSiK.TerminalSync
		and GlobalStorageSiK.TerminalSync.finishManagedTransfer then
		GlobalStorageSiK.TerminalSync.finishManagedTransfer(
			"withdraw", cancelledOperation.searchQuery, cancelledOperation.lastRevision)
	end
end

--- Compatibilidad con callers antiguos: liberar ya significa cancelar, nunca
--- avanzar ante una respuesta no correlacionada.
function GlobalStorageSiK.WithdrawClient.clearPending()
	GlobalStorageSiK.WithdrawClient.cancelAll()
end

function GlobalStorageSiK.WithdrawClient.isPending()
	return current ~= nil or #queue > 0
end

--- Reanuda una sola vez un gesto exact_group cuando llega el catálogo fresco
--- solicitado expresamente tras selection_stale. No consulta páginas ni crea
--- polling: el terminalState autoritativo es el único disparador y el timeout
--- acotado ya gestionado por onTick cancela la espera si nunca llega.
---@param state table|nil
---@return boolean consumed
function GlobalStorageSiK.WithdrawClient.onTerminalState(state)
	if not current or current.awaitingFreshSelection ~= true or not state then return false end
	if state.networkId ~= current.networkId then return false end
	if state.sourceNodeId ~= current.rowData.sourceNodeId then return false end
	local freshRevision = tonumber(state.inventoryRevision)
	local staleRevision = tonumber(current.staleSelectionRevision)
	if not freshRevision or (staleRevision and freshRevision <= staleRevision) then return false end
	local freshRow = nil
	for i = 1, #(state.items or {}) do
		local candidate = state.items[i]
		if candidate and candidate.rowKey == current.rowData.rowKey then
			freshRow = candidate
			break
		end
	end
	if not freshRow then
		GlobalStorageSiK.Log.warn("WithdrawClient", "fresh selection missing",
			"rowKey=" .. tostring(current.rowData.rowKey)
				.. " revision=" .. tostring(freshRevision))
		GlobalStorageSiK.WithdrawClient.cancelAll("selection_not_found")
		return true
	end
	local previousExpected = current.expectedCount or 0
	current.rowData = freshRow
	current.selectionTicket = nil
	current.selectionSequence = 1
	current.remaining = nil
	current.expectedCount = math.max(0, math.floor(tonumber(freshRow.count) or 0))
	if operation and current.expectedCount ~= previousExpected then
		operation.totalExpected = math.max(0,
			(operation.totalExpected or 0) - previousExpected + current.expectedCount)
	end
	current.awaitingFreshSelection = false
	current.staleSelectionRevision = nil
	responseDeadlineMs = 0
	nextDispatchMs = nowMs()
	ensureTickInstalled()
	GlobalStorageSiK.Log.debug("WithdrawClient", "fresh selection received; retrying once",
		"rowKey=" .. tostring(freshRow.rowKey)
			.. " revision=" .. tostring(freshRevision))
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
	local requested = math.floor(tonumber(amount) or 1)
	if rowData.selectionMode == "exact_group" then
		requested = math.max(0, math.floor(tonumber(rowData.count) or 0))
	end
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
		logicalId = tostring(nowMs()) .. "-" .. tostring(serial),
		rowData = rowData,
		amount = requested,
		openEnded = openEnded,
		targetKey = targetKey,
		searchQuery = searchQuery,
		networkId = op.networkId or networkId,
		returnItemIds = opts and opts.returnItemIds == true,
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
function GlobalStorageSiK.WithdrawClient.sendWithdraw(rowData, amount, targetKey, searchQuery, opts)
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
			local key = tostring(row.sourceNodeId or "") .. ":" .. tostring(row.fullType)
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
function GlobalStorageSiK.WithdrawClient.sendWithdrawBatch(rows, amount, targetKey, searchQuery, options)
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
	local requestOptions = nil
	if options then
		requestOptions = { networkId = options.networkId, onComplete = function(ok, result)
			remaining = remaining - 1
			moved = moved + (tonumber(result and result.moved) or 0)
			if not ok then failed = true; failureReason = result and result.reason or failureReason end
			if remaining == 0 and options.onComplete then
				options.onComplete(not failed, { moved = moved, reason = failureReason })
			end
		end }
	end
	for i = 1, #coalescedRows do
		if enqueueWithdraw(coalescedRows[i], amount, targetKey, searchQuery, requestOptions) then
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
function GlobalStorageSiK.WithdrawClient.onActionResult(args)
	if not current or not args or args.withdrawId ~= current.requestId then return false end
	responseDeadlineMs = 0
	local transfer = args.transfer
	if not transfer or transfer.op ~= "withdraw" then
		GlobalStorageSiK.WithdrawClient.cancelAll("invalid_response")
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
		current.remaining = math.max(0, math.floor(tonumber(transfer.ticketRemaining) or 0))
		local selectionCount = math.max(0, math.floor(tonumber(transfer.selectionCount) or 0))
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
			GlobalStorageSiK.WithdrawClient.cancelAll("selection_stale")
			return false
		end
		current.staleRetryCount = 1
		current.awaitingFreshSelection = true
		current.staleSelectionRevision = current.rowData.selectionRevision
		current.selectionTicket = nil
		current.selectionSequence = 1
		responseDeadlineMs = nowMs() + RESPONSE_TIMEOUT_MS
		nextDispatchMs = math.huge
		local sourceNodeId = current.rowData.sourceNodeId
		local refreshSent = GlobalStorageSiK.NetClient.sendCommand(sourceNodeId and "getNodeContents" or "requestItemIndex", {
			networkId = current.networkId, nodeId = sourceNodeId, searchQuery = current.searchQuery or "",
		})
		if not refreshSent then
			GlobalStorageSiK.WithdrawClient.cancelAll("selection_refresh_failed")
			return false
		end
		-- En SP el bypass puede entregar terminalState de forma síncrona dentro
		-- de sendCommand; si ese snapshot confirmó que la fila ya no existe,
		-- onTerminalState habrá cancelado y limpiado current antes de volver aquí.
		if not current then return false end
		GlobalStorageSiK.Log.debug("WithdrawClient", "selection stale; explicit refresh requested")
		return true
	end
	current.totalMoved = (current.totalMoved or 0) + moved
	if selectionMode == "exact_ids" then
		current.itemIdOffset = (current.itemIdOffset or 1) + (current.batchRequested or 0)
	else
		current.itemIdOffset = (current.itemIdOffset or 1) + moved
	end
	if operation then
		operation.totalMoved = (operation.totalMoved or 0) + moved
		operation.inspected = (operation.inspected or 0) + (current.batchRequested or 0)
		operation.skipped = (operation.skipped or 0)
			+ math.max(0, (current.batchRequested or 0) - moved)
		operation.batches = (operation.batches or 0) + 1
		local revision = tonumber(transfer.inventoryRevision)
		if revision then
			operation.lastRevision = math.max(operation.lastRevision or 0, revision)
		end
	end
	if selectionMode == "exact_ids" then
		current.remaining = math.max(0, (current.remaining or 0) - (current.batchRequested or 0))
	elseif selectionMode ~= "exact_group" and not current.all then
		current.remaining = math.max(0, (current.remaining or 0) - moved)
	end
	-- not_found (tambien parcial) significa que la captura visible se agoto o
	-- quedo anticuada: termina este tipo y sigue con el siguiente. Los demas
	-- fallos son terminales para la operacion completa; no martillear todas las
	-- filas si se perdio energia, espacio, acceso o una mutacion fallo.
	local exhausted = reason == "not_found" or reason == "partial:not_found"
	local exactHasMore = (selectionMode == "exact_group" or selectionMode == "exact_ids")
		and (current.remaining or 0) > 0
	local hardFailure = (args.ok ~= true and not exhausted)
		or (reason and string.sub(reason, 1, 8) == "partial:" and not exhausted)
	if hardFailure then
		local cleanReason = reason and string.gsub(reason, "^partial:", "") or "unknown"
		GlobalStorageSiK.Log.error("WithdrawClient", "operation stopped",
			"reason=" .. tostring(cleanReason)
				.. " movedConfirmed=" .. tostring(operation and operation.totalMoved or moved))
		args.ok = false
		args.message = GlobalStorageSiK.I18n.remote("IGUI_GS_WithdrawErrorReason", cleanReason)
		GlobalStorageSiK.WithdrawClient.cancelAll(cleanReason)
		return false
	end
	local shouldContinue = exactHasMore and (args.ok == true or exhausted)
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
	local completionResult = {
		reason = reason,
		moved = completedRequest and completedRequest.totalMoved or moved,
		itemIds = transfer.itemIds or {},
		sourceNodeId = transfer.sourceNodeId,
		networkId = transfer.networkId,
		fullType = transfer.fullType,
	}
	local hasNext = finishCurrent(true)
	runCompletion(completedRequest, completionResult.moved > 0, completionResult)
	if hasNext then
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
			"withdraw", operation.searchQuery, operation.lastRevision)
	end
	operation = nil
	return false
end
