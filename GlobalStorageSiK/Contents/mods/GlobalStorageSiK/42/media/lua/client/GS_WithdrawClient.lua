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

GlobalStorageSiK.WithdrawClient = {}

local SAFE_BATCH_UNITS = 10
local BATCH_DELAY_MS = 400
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
	if player and player.setHaloNote then
		pcall(function()
			player:setHaloNote(GlobalStorageSiK.I18n.text(key), 255, 120, 120, 250)
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
	if not player or not player.setHaloNote then return end
	local text = GlobalStorageSiK.I18n.text("IGUI_GS_WithdrawPending")
	if (operation.totalExpected or 0) > 0 then
		text = text .. " " .. tostring(operation.totalMoved or 0)
			.. "/" .. tostring(operation.totalExpected)
	end
	text = text .. " (" .. tostring(operation.rowsDone or 0)
		.. "/" .. tostring(operation.rowsTotal or 0) .. ")"
	pcall(function()
		player:setHaloNote(text, 200, 220, 200, 220)
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
	}
	GlobalStorageSiK.Log.info("WithdrawClient", "operation started")
	return operation
end

local function finishCurrent(delayNext)
	current = nil
	responseDeadlineMs = 0
	if #queue > 0 then
		nextDispatchMs = nowMs() + (delayNext and BATCH_DELAY_MS or 0)
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
	nextDispatchMs = nowMs()
	ensureTickInstalled()
end

local function dispatchCurrent()
	if not current then return end
	current.sequence = current.sequence + 1
	local requested = current.all and SAFE_BATCH_UNITS
		or math.min(current.remaining or 1, SAFE_BATCH_UNITS)
	current.batchRequested = requested
	current.requestId = current.logicalId .. ":" .. tostring(current.sequence)
	local expectedRequestId = current.requestId
	-- Armar ANTES del envío: en SP/host el bypass local puede entregar y
	-- resolver actionResult de forma síncrona dentro de sendCommand.
	responseDeadlineMs = nowMs() + RESPONSE_TIMEOUT_MS
	nextDispatchMs = math.huge
	local sent = GlobalStorageSiK.NetClient.sendCommand("withdrawItem", {
		fullType = current.rowData.fullType,
		amount = requested,
		targetKey = current.targetKey,
		searchQuery = current.searchQuery or "",
		withdrawId = current.requestId,
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
	if operation then
		GlobalStorageSiK.Log.warn("WithdrawClient", "operation cancelled moved="
			.. tostring(operation.totalMoved or 0)
			.. " rows=" .. tostring(operation.rowsDone or 0)
			.. "/" .. tostring(operation.rowsTotal or 0))
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

---@param rows table[]
---@param amount number|nil
---@param targetKey string|nil
---@param searchQuery string|nil
---@return boolean
function GlobalStorageSiK.WithdrawClient.sendWithdrawBatch(rows, amount, targetKey, searchQuery)
	if not rows or #rows == 0 then return false end
	if #queue + (current and 1 or 0) + #rows > MAX_QUEUED_REQUESTS then
		GlobalStorageSiK.Log.error("WithdrawClient", "batch queue limit reached",
			"rows=" .. tostring(#rows) .. " limit=" .. tostring(MAX_QUEUED_REQUESTS))
		showLocalError("IGUI_GS_InternalTransferError")
		return false
	end
	local okAny = false
	for i = 1, #rows do
		if enqueueWithdraw(rows[i], amount, targetKey, searchQuery, nil) then
			okAny = true
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
	current.totalMoved = (current.totalMoved or 0) + moved
	if operation then
		operation.totalMoved = (operation.totalMoved or 0) + moved
		local revision = tonumber(transfer.inventoryRevision)
		if revision then
			operation.lastRevision = math.max(operation.lastRevision or 0, revision)
		end
	end
	if not current.all then
		current.remaining = math.max(0, (current.remaining or 0) - moved)
	end
	-- not_found (tambien parcial) significa que la captura visible se agoto o
	-- quedo anticuada: termina este tipo y sigue con el siguiente. Los demas
	-- fallos son terminales para la operacion completa; no martillear todas las
	-- filas si se perdio energia, espacio, acceso o una mutacion fallo.
	local exhausted = reason == "not_found" or reason == "partial:not_found"
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
	local shouldContinue = args.ok == true and moved > 0 and not exhausted
		and ((current.all and moved >= (current.batchRequested or SAFE_BATCH_UNITS))
			or (not current.all and (current.remaining or 0) > 0))
	if shouldContinue then
		showProgress(false)
		nextDispatchMs = nowMs() + BATCH_DELAY_MS
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
		.. " elapsedMs=" .. tostring(elapsed))
	showProgress(true)
	if operation and GlobalStorageSiK.TerminalSync
		and GlobalStorageSiK.TerminalSync.finishManagedTransfer then
		GlobalStorageSiK.TerminalSync.finishManagedTransfer(
			"withdraw", operation.searchQuery, operation.lastRevision)
	end
	operation = nil
	return false
end
