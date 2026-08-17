--[[
	GlobalStorageSiK - Cola de transferencias masivas (cliente)
	Autor: SiK
	Fecha: 2025-06-25
	Descripción: Continúa depósitos mediante micro-lotes internos confirmados.
]]

require "GS_NetClient"
require "GS_Log"
require "GS_I18n"
require "GS_Sandbox"

GlobalStorageSiK.TransferQueue = {}

local BATCH_DELAY_MS = 400
-- Red de seguridad (reportada 2026-08-16, "el log de item not found no
-- puede estar en bucle sin fallar de forma informada o terminar de algun
-- modo"): el reintento YA termina solo por diseno (onActionResult solo
-- reprograma si summary.moved > 0, ver comentario de depositByIds en
-- GS_Deposit.lua sobre por que "no encontrado" no es un fallo real).
-- CORREGIDO (2026-08-16, bug real confirmado con Project Cook y ~200 items
-- en la red: la lista ORIGINAL completa se reenviaba entera en cada
-- reintento sin recortar los ya resueltos, asi que con maxPerTick pequeno
-- hacian falta cientos de lotes para converger y el trabajo chocaba contra
-- este limite sin terminar de verdad) - depositByIds ahora devuelve
-- summary.remainingIds (solo lo pendiente de verdad) y scheduleRetry lo usa
-- para recortar pendingJob.itemIds antes de cada reintento. El limite de
-- lotes se mantiene como red de seguridad, pero escala con el numero inicial
-- de IDs para admitir almacenes grandes incluso con presupuesto de 1 por lote.
local MIN_MAX_BATCHES = 200
local pendingJob = nil
local nextRunMs = 0
local tickInstalled = false
local batchCount = 0
local queueSerial = 0
local inFlight = false
local responseDeadlineMs = 0
local RESPONSE_TIMEOUT_MS = 10000
local MAX_TIMEOUT_RETRIES = 3
local MAX_QUEUED_JOBS = 256
local queuedJobs = {}
local operation = nil

local function nowMs()
	return getTimestampMs and getTimestampMs() or 0
end

local function feedbackEnabled()
	return not GlobalStorageSiK.Sandbox.operationHaloFeedbackEnabled
		or GlobalStorageSiK.Sandbox.operationHaloFeedbackEnabled()
end

--- Feedback funcional local: no depende de DebugMode ni genera red adicional.
--- Se limita a una actualización por segundo para no reemplazar continuamente
--- otros avisos importantes sobre el personaje.
---@param force boolean|nil
local function showProgress(force)
	if not operation or not feedbackEnabled() then return end
	local now = nowMs()
	if not force and now - (operation.lastProgressMs or 0) < 1000 then return end
	operation.lastProgressMs = now
	local player = GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer()
	if not player or not player.setHaloNote then return end
	local moved = (operation.totalMoved or 0) + (pendingJob and pendingJob.totalMoved or 0)
	local text = GlobalStorageSiK.I18n.text("IGUI_GS_DepositPending")
	if (operation.totalExpected or 0) > 0 then
		text = text .. " " .. tostring(moved) .. "/" .. tostring(operation.totalExpected)
	else
		text = text .. " " .. tostring(moved)
	end
	local currentJob = math.min(operation.jobsTotal or 1, (operation.jobsDone or 0) + 1)
	text = text .. " (" .. tostring(currentJob) .. "/" .. tostring(operation.jobsTotal or 1) .. ")"
	pcall(function() player:setHaloNote(text, 200, 220, 200, 220) end)
end

---@param job table
---@return number
local function expectedUnits(job)
	if not job then return 0 end
	if job.expectedUnits then
		return math.max(0, math.floor(tonumber(job.expectedUnits) or 0))
	end
	if job.type == "depositIds" then return #(job.itemIds or {}) end
	if job.type == "partial" then return math.max(0, math.floor(tonumber(job.count) or 0)) end
	return 0
end

local function ensureTickInstalled()
	if tickInstalled or not Events or not Events.OnTick then return end
	tickInstalled = true
	Events.OnTick.Add(GlobalStorageSiK.TransferQueue.onTick)
end

---@return boolean
function GlobalStorageSiK.TransferQueue.isActive()
	return pendingJob ~= nil or #queuedJobs > 0
end

local function activeNetworkId()
	local ui = GlobalStorageSiK.TerminalUI and GlobalStorageSiK.TerminalUI.instance
	return ui and ui.terminalState and ui.terminalState.networkId
		or (GlobalStorageSiK.Client and GlobalStorageSiK.Client.activeNetworkId)
end

---@param job table
local function initialiseJob(job)
	queueSerial = queueSerial + 1
	job.queueId = tostring(getTimestampMs and getTimestampMs() or 0) .. "-" .. tostring(queueSerial)
	job.totalMoved = 0
	job.totalSkipped = 0
	job.totalMissing = 0
	job.totalFailed = 0
	job.timeoutRetries = 0
	job.failureReason = nil
	job.lastRemainingCount = job.itemIds and #job.itemIds or nil
	job.maxBatches = math.max(MIN_MAX_BATCHES, #(job.itemIds or {}) + 10)
end

---@param job table
---@param firstRequestInFlight boolean
local function activateJob(job, firstRequestInFlight)
	pendingJob = job
	batchCount = 0
	inFlight = firstRequestInFlight == true
	if inFlight then
		responseDeadlineMs = (getTimestampMs and getTimestampMs() or 0) + RESPONSE_TIMEOUT_MS
		nextRunMs = math.huge
	else
		responseDeadlineMs = 0
		nextRunMs = (getTimestampMs and getTimestampMs() or 0) + BATCH_DELAY_MS
	end
	ensureTickInstalled()
end

---@param job table
---@return string|nil queueId
---@return boolean|nil sendNow
---@return string|nil networkId
function GlobalStorageSiK.TransferQueue.arm(job)
	local supported = job and (job.type == "depositIds" or job.type == "container" or job.type == "partial")
	if not supported or #queuedJobs + (pendingJob and 1 or 0) >= MAX_QUEUED_JOBS then
		return nil
	end
	job.networkId = job.networkId or activeNetworkId()
	if operation and operation.networkId and job.networkId
		and operation.networkId ~= job.networkId then
		GlobalStorageSiK.Log.warn("TransferQueue", "queue rejected across networks",
			"active=" .. tostring(operation.networkId) .. " requested=" .. tostring(job.networkId))
		return nil
	end
	if not operation then
		if GlobalStorageSiK.TerminalSync and GlobalStorageSiK.TerminalSync.beginManagedTransfer
			and not GlobalStorageSiK.TerminalSync.beginManagedTransfer("deposit", job.networkId, job.searchQuery) then
			return nil
		end
		operation = {
			networkId = job.networkId,
			searchQuery = job.searchQuery,
			jobsTotal = 0,
			jobsDone = 0,
			totalBatches = 0,
			totalMoved = 0,
			totalSkipped = 0,
			totalMissing = 0,
			totalFailed = 0,
			totalExpected = 0,
			lastProgressMs = 0,
			startedMs = nowMs(),
		}
	end
	initialiseJob(job)
	operation.jobsTotal = operation.jobsTotal + 1
	operation.totalExpected = operation.totalExpected + expectedUnits(job)
	if pendingJob then
		table.insert(queuedJobs, job)
		showProgress(false)
		return job.queueId, false, job.networkId
	end
	-- El caller envía el primer request inmediatamente. Desde este instante la
	-- vigilancia ya está armada para que una respuesta perdida no deje residuos.
	activateJob(job, true)
	showProgress(true)
	return job.queueId, true, job.networkId
end

---@param job table
local function scheduleRetry(job)
	pendingJob = job
	batchCount = batchCount + 1
	nextRunMs = (getTimestampMs and getTimestampMs() or 0) + BATCH_DELAY_MS
	ensureTickInstalled()
end

--- Envía el trabajo pendiente al servidor.
---@param job table
local function dispatchJob(job)
	if not job or not GlobalStorageSiK.NetClient or not GlobalStorageSiK.NetClient.sendCommand then
		return false
	end
	if job.type == "depositIds" then
		return GlobalStorageSiK.NetClient.sendCommand("depositItems", {
			itemIds = job.itemIds or {},
			origin = "player_queue",
			queueId = job.queueId,
			networkId = job.networkId,
		})
	elseif job.type == "container" then
		return GlobalStorageSiK.NetClient.sendCommand("depositItems", {
			mode = "container",
			referenceItemId = job.referenceItemId,
			origin = "player_queue",
			queueId = job.queueId,
			networkId = job.networkId,
		})
	elseif job.type == "partial" then
		return GlobalStorageSiK.NetClient.sendCommand("depositItems", {
			mode = "partial",
			referenceItemId = job.referenceItemId,
			count = job.count,
			origin = "player_queue",
			queueId = job.queueId,
			networkId = job.networkId,
		})
	end
	return false
end

--- Limpia la cola de transferencias en curso (p. ej. al perder acceso).
function GlobalStorageSiK.TransferQueue.clear()
	local cancelledOperation = operation
	pendingJob = nil
	queuedJobs = {}
	operation = nil
	nextRunMs = 0
	inFlight = false
	responseDeadlineMs = 0
	if tickInstalled and Events and Events.OnTick then
		Events.OnTick.Remove(GlobalStorageSiK.TransferQueue.onTick)
		tickInstalled = false
	end
	if cancelledOperation and GlobalStorageSiK.TerminalSync
		and GlobalStorageSiK.TerminalSync.finishManagedTransfer then
		GlobalStorageSiK.TerminalSync.finishManagedTransfer(
			"deposit", cancelledOperation.searchQuery, cancelledOperation.lastRevision)
	end
end

function GlobalStorageSiK.TransferQueue.onTick()
	if not pendingJob then
		return
	end
	local now = getTimestampMs and getTimestampMs() or 0
	if inFlight then
		if now < responseDeadlineMs then return end
		if pendingJob.type == "partial" then
			-- Un depósito parcial puede conservar el mismo itemId con un count
			-- reducido. Reenviarlo a ciegas movería otra porción, así que ante una
			-- respuesta perdida se termina sin reintento (misma regla que retiro).
			GlobalStorageSiK.Log.error("TransferQueue", "partial response timeout",
				"queueId=" .. tostring(pendingJob.queueId))
			GlobalStorageSiK.TransferQueue.clear()
			return
		end
		pendingJob.timeoutRetries = (pendingJob.timeoutRetries or 0) + 1
		if pendingJob.timeoutRetries > MAX_TIMEOUT_RETRIES then
			GlobalStorageSiK.Log.error("TransferQueue", "response timeout",
				"queueId=" .. tostring(pendingJob.queueId)
					.. " retries=" .. tostring(MAX_TIMEOUT_RETRIES))
			GlobalStorageSiK.TransferQueue.clear()
			return
		end
		-- Los depósitos por ID son idempotentes en servidor: un ID ya movido no
		-- puede volver a encontrarse en el inventario origen. Reenviar tras un
		-- timeout largo recupera una respuesta perdida sin duplicar el objeto.
		inFlight = false
		nextRunMs = now
	end
	if now < nextRunMs then
		return
	end
	nextRunMs = now + BATCH_DELAY_MS
	inFlight = true
	responseDeadlineMs = now + RESPONSE_TIMEOUT_MS
	local sent = dispatchJob(pendingJob)
	if sent == false and pendingJob then
		GlobalStorageSiK.Log.error("TransferQueue", "dispatch failed",
			"queueId=" .. tostring(pendingJob.queueId) .. " type=" .. tostring(pendingJob.type))
		GlobalStorageSiK.TransferQueue.clear()
	end
end

--- Procesa respuesta del servidor; devuelve true si continúa en segundo plano.
---@param args table|nil
---@return boolean continuing
function GlobalStorageSiK.TransferQueue.onActionResult(args)
	if not pendingJob or not args then
		return false
	end

	if args.queueId and args.queueId == pendingJob.queueId and not (args.deposit or args.bulk) then
		GlobalStorageSiK.TransferQueue.clear()
		return false
	end
	local summary = args.deposit or args.bulk
	if not summary then
		return false
	end
	if args.queueId ~= pendingJob.queueId then
		return false
	end
	inFlight = false
	responseDeadlineMs = 0
	pendingJob.timeoutRetries = 0
	pendingJob.totalMoved = (pendingJob.totalMoved or 0) + (summary.moved or 0)
	pendingJob.totalSkipped = (pendingJob.totalSkipped or 0) + (summary.skipped or 0)
	pendingJob.totalMissing = (pendingJob.totalMissing or 0) + (summary.missing or 0)
	pendingJob.totalFailed = (pendingJob.totalFailed or 0) + (summary.failed or 0)
	local revision = tonumber(summary.inventoryRevision or args.inventoryRevision
		or (args.transfer and args.transfer.inventoryRevision))
	if operation and revision then
		operation.lastRevision = math.max(operation.lastRevision or 0, revision)
	end
	if args.transfer then
		-- La cola visual se reconcilia una sola vez contra el snapshot estable;
		-- no lanzar un searchItems obsoleto por cada micro-lote de depósito.
		args.transfer.deferInventoryPull = true
	end
	if summary.failureReason and not pendingJob.failureReason then
		pendingJob.failureReason = summary.failureReason
	end

	if summary.reason == "limit" and (summary.processed or 0) > 0
		and summary.remainingIds and #summary.remainingIds > 0 then
		local remainingCount = #summary.remainingIds
		-- Todo lote continuable debe reducir el conjunto pendiente. Repetir el
		-- mismo conjunto indicaría una respuesta obsoleta o un servidor sin
		-- progreso; se corta aquí para impedir un bucle de ticks/red.
		if pendingJob.lastRemainingCount and remainingCount >= pendingJob.lastRemainingCount then
			GlobalStorageSiK.Log.error("TransferQueue", "non-progressing response",
				"queueId=" .. tostring(pendingJob.queueId)
					.. " previous=" .. tostring(pendingJob.lastRemainingCount)
					.. " remaining=" .. tostring(remainingCount))
			GlobalStorageSiK.TransferQueue.clear()
			return false
		end
		pendingJob.lastRemainingCount = remainingCount
		if pendingJob.type == "container" and summary.remainingIds then
			pendingJob.maxBatches = math.max(pendingJob.maxBatches or MIN_MAX_BATCHES,
				batchCount + #summary.remainingIds + 10)
		end
		if batchCount + 1 >= (pendingJob.maxBatches or MIN_MAX_BATCHES) then
			GlobalStorageSiK.Log.error("TransferQueue", "max batches reached",
				"batches=" .. tostring(pendingJob.maxBatches or MIN_MAX_BATCHES)
					.. " moved=" .. tostring(summary.moved)
					.. " type=" .. tostring(pendingJob.type))
			GlobalStorageSiK.TransferQueue.clear()
			return false
		end
		if (pendingJob.type == "depositIds" or pendingJob.type == "container")
			and summary.remainingIds then
			pendingJob.type = "depositIds"
			pendingJob.itemIds = summary.remainingIds
		end
		scheduleRetry(pendingJob)
		showProgress(false)
		return true
	end

	local completedJob = pendingJob
	local completedBatches = batchCount + 1
	if operation then
		operation.jobsDone = operation.jobsDone + 1
		operation.totalBatches = operation.totalBatches + completedBatches
		operation.totalMoved = operation.totalMoved + (completedJob.totalMoved or 0)
		operation.totalSkipped = operation.totalSkipped + (completedJob.totalSkipped or 0)
		operation.totalMissing = operation.totalMissing + (completedJob.totalMissing or 0)
		operation.totalFailed = operation.totalFailed + (completedJob.totalFailed or 0)
		if completedJob.failureReason and not operation.failureReason then
			operation.failureReason = completedJob.failureReason
		end
	end
	if #queuedJobs > 0 then
		GlobalStorageSiK.Log.detail("TransferQueue", "job complete; advancing FIFO",
			"queueId=" .. tostring(completedJob.queueId)
				.. " moved=" .. tostring(completedJob.totalMoved or 0)
				.. " queued=" .. tostring(#queuedJobs))
		activateJob(table.remove(queuedJobs, 1), false)
		showProgress(false)
		return true
	end
	local finalMoved = operation and operation.totalMoved or completedJob.totalMoved or 0
	local finalSkipped = operation and operation.totalSkipped or completedJob.totalSkipped or 0
	local finalMissing = operation and operation.totalMissing or completedJob.totalMissing or 0
	local finalFailed = operation and operation.totalFailed or completedJob.totalFailed or 0
	GlobalStorageSiK.Log.debug("TransferQueue", "complete",
		"jobs=" .. tostring(operation and operation.jobsDone or 1)
			.. " batches=" .. tostring(operation and operation.totalBatches or completedBatches)
			.. " moved=" .. tostring(finalMoved)
			.. " skipped=" .. tostring(finalSkipped) .. " failed=" .. tostring(finalFailed)
			.. " reason=" .. tostring(summary.reason))
	summary.moved = finalMoved
	summary.skipped = finalSkipped
	summary.failed = finalFailed
	summary.missing = finalMissing
	if not summary.reason and operation and operation.failureReason then summary.reason = operation.failureReason end
	if not summary.reason and completedJob.failureReason then summary.reason = completedJob.failureReason end
	if summary.missing > 0 and not summary.reason then summary.reason = "not_found" end
	if not summary.reason or summary.reason == "not_found" then
		args.message = GlobalStorageSiK.I18n.remote("IGUI_GS_DepositSummary",
			tostring(summary.moved), tostring(summary.skipped), tostring(summary.failed or 0))
	end
	GlobalStorageSiK.TransferQueue.clear()
	return false
end
