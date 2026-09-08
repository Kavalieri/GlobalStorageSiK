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
require "GS_OperationPacing"
require "GS_UI_Feedback"

local Queue = {}
GlobalStorageSiK.TransferQueue = Queue
local queues = {}
local tickInstalled = false
local serial = 0

local function playerNumber(value)
    local number = value
    if value ~= nil and type(value) ~= "number" then
        if type(value) ~= "table" and type(value) ~= "userdata" then return nil end
        if not value.getPlayerNum then return nil end
        number = value:getPlayerNum()
    end
    number = number == nil and 0 or tonumber(number)
    if not number or number ~= math.floor(number) or number < 0 or number > 3 then return nil end
    return number
end

local function nextId(playerNum)
    serial = serial + 1
    return "deposit-" .. tostring(playerNum) .. "-" .. tostring(getTimestampMs and getTimestampMs() or 0) .. "-" .. tostring(serial)
end

local function ensureTickInstalled()
    if tickInstalled or not Events or not Events.OnTick then return end
    tickInstalled = true
    Events.OnTick.Add(Queue.onTick)
end

local function createQueue(playerNum)
local Q = {}
local function currentPlayer()
    return GlobalStorageSiK.NetClient.getPlayer(playerNum)
end

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
local batchCount = 0
local inFlight = false
local responseDeadlineMs = 0
local RESPONSE_TIMEOUT_MS = 10000
local MAX_TIMEOUT_RETRIES = 3
local MAX_QUEUED_JOBS = 64
local queuedJobs = {}
local operation = nil

local function nowMs()
	return getTimestampMs and getTimestampMs() or 0
end

local function batchDelayMs()
	return operation and operation.pacing and operation.pacing.batchDelayMs or 400
end

--- Feedback funcional local: no depende de DebugMode ni genera red adicional.
--- Se limita a una actualización por segundo para no reemplazar continuamente
--- otros avisos importantes sobre el personaje.
---@param force boolean|nil
local function showProgress(force)
	if not operation then return end
	local now = nowMs()
	if not force and now - (operation.lastProgressMs or 0) < 1000 then return end
	operation.lastProgressMs = now
	local player = pendingJob and pendingJob.player
	if not player then return end
	local moved = (operation.totalMoved or 0) + (pendingJob and pendingJob.totalMoved or 0)
	local text = GlobalStorageSiK.I18n.text("IGUI_GS_DepositPending")
	if (operation.totalExpected or 0) > 0 then
		text = text .. " " .. tostring(moved) .. "/" .. tostring(operation.totalExpected)
	else
		text = text .. " " .. tostring(moved)
	end
    GlobalStorageSiK.UIFeedback.updateOperation(playerNum, operation.id, text,
        moved, operation.totalExpected or 0)
end

---@param job table
---@return number
local function expectedUnits(job)
	if not job then return 0 end
	if job.expectedUnits then
		return math.max(0, math.floor(tonumber(job.expectedUnits) or 0))
	end
	if job.type == "depositIds" then return #(job.itemIds or {}) end
	if job.type == "physical" then return #(job.physicalItems or {}) end
	if job.type == "partial" then return math.max(0, math.floor(tonumber(job.count) or 0)) end
	return 0
end


---@return boolean
function Q.isActive()
	return pendingJob ~= nil or #queuedJobs > 0
end

local function activeNetworkId()
    local terminal = GlobalStorageSiK.TerminalUI
    local ui = terminal and terminal.getInstanceForPlayer and terminal.getInstanceForPlayer(playerNum)
    local client = GlobalStorageSiK.Client
    local state = ui and ui.terminalState or client and client.terminalStateByPlayer
        and client.terminalStateByPlayer[playerNum]
    return state and state.networkId
        or (playerNum == 0 and client and client.activeNetworkId) or nil
end

local function playerValid(job)
    return job and job.player and currentPlayer() == job.player
        and (not job.player.isDead or not job.player:isDead())
end

local function finishOperation()
    local finished = operation
    operation = nil
    if not finished then return end
    GlobalStorageSiK.UIFeedback.finishOperation(playerNum, finished.id)
    if GlobalStorageSiK.TerminalSync and GlobalStorageSiK.TerminalSync.finishManagedTransfer then
        GlobalStorageSiK.TerminalSync.finishManagedTransfer("deposit", finished.searchQuery,
            finished.lastRevision, playerNum, finished.id)
    end
end

local function startOperation(job)
    if not playerValid(job) then return false end
    local sync = GlobalStorageSiK.TerminalSync
    if sync and sync.beginManagedTransfer
        and not sync.beginManagedTransfer("deposit", job.networkId, job.searchQuery, playerNum, job.gestureId) then return false end
    if not GlobalStorageSiK.UIFeedback.beginOperation(job.player, job.gestureId, job.networkId, "deposit") then
        if sync and sync.finishManagedTransfer then
            sync.finishManagedTransfer("deposit", job.searchQuery, nil, playerNum, job.gestureId)
        end
        return false
    end
    operation = { id = job.gestureId, networkId = job.networkId, searchQuery = job.searchQuery,
        jobsTotal = 1, jobsDone = 0, totalBatches = 0, totalMoved = 0,
        totalSkipped = 0, totalMissing = 0, totalFailed = 0, totalInspected = 0,
        totalExpected = expectedUnits(job), lastProgressMs = 0, startedMs = nowMs(),
        pacing = GlobalStorageSiK.OperationPacing.resolve({ operationType = "deposit" }) }
    return true
end

---@param job table
local function initialiseJob(job)
	job.queueId = nextId(playerNum)
	job.gestureId = job.queueId
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
	if not startOperation(job) then return false end
	pendingJob = job
	batchCount = 0
	inFlight = firstRequestInFlight == true
	if inFlight then
		responseDeadlineMs = (getTimestampMs and getTimestampMs() or 0) + RESPONSE_TIMEOUT_MS
		nextRunMs = math.huge
	else
		responseDeadlineMs = 0
		nextRunMs = (getTimestampMs and getTimestampMs() or 0) + batchDelayMs()
	end
	ensureTickInstalled()
	return true
end

---@param job table
---@return string|nil queueId
---@return boolean|nil sendNow
---@return string|nil networkId
function Q.arm(input, player)
    if type(input) ~= "table" then return nil end
    local job = {}
    for _, key in ipairs({ "type", "networkId", "origin", "operationId", "preferredNodeId",
        "referenceItemId", "expectedUnits", "count", "searchQuery" }) do job[key] = input[key] end
    job.player = player
    if not playerValid(job) then return nil end
    if input.itemIds ~= nil then
        if type(input.itemIds) ~= "table" or #input.itemIds == 0 or #input.itemIds > 4096 then return nil end
        job.itemIds = {}
        local seen = {}
        for i = 1, #input.itemIds do
            local id = input.itemIds[i]
            if type(id) ~= "number" or id ~= id or id == math.huge or id == -math.huge
                or id ~= math.floor(id) then return nil end
            if not seen[id] then job.itemIds[#job.itemIds + 1] = id; seen[id] = true end
        end
    end
	if job.type == "physical" then
		if type(input.physicalItems) ~= "table" or #input.physicalItems < 1 or #input.physicalItems > 4096 then return nil end
		local retained = pendingJob and pendingJob.physicalItems and #pendingJob.physicalItems or 0
		for i = 1, #queuedJobs do retained = retained + #(queuedJobs[i].physicalItems or {}) end
		if retained + #input.physicalItems > 4096 then return nil end
		job.physicalItems, job.physicalIndex = {}, 1
		local seen = {}
		for i = 1, #input.physicalItems do
			local entry = input.physicalItems[i]
			local id = type(entry) == "table" and entry.itemId or nil
			if type(id) ~= "number" or id ~= id or id < 0 or id == math.huge
				or id ~= math.floor(id) or seen[id] then return nil end
			if entry.kind ~= "container" and entry.kind ~= "floor" then return nil end
			if entry.kind == "floor" and (type(entry.sourceKey) ~= "string" or #entry.sourceKey > 48
				or string.sub(entry.sourceKey, 1, 6) ~= "floor:" or type(entry.fullType) ~= "string"
				or entry.fullType == "" or #entry.fullType > 160) then return nil end
			seen[id] = true
			job.physicalItems[i] = { kind = entry.kind, itemId = id,
				sourceKey = entry.kind == "floor" and entry.sourceKey or nil,
				fullType = entry.kind == "floor" and entry.fullType or nil }
		end
	end
	local supported = job and (job.type == "depositIds" or job.type == "container" or job.type == "partial" or job.type == "physical")
	if not supported or #queuedJobs + (pendingJob and 1 or 0) >= MAX_QUEUED_JOBS then
		return nil
	end
	job.networkId = job.networkId or activeNetworkId()
    if type(job.networkId) ~= "string" or #job.networkId == 0 or #job.networkId > 192 then return nil end
    if job.type == "depositIds" and not job.itemIds then return nil end
    for _, key in ipairs({ "expectedUnits", "count", "referenceItemId" }) do
        local n = job[key]
        if n ~= nil and (type(n) ~= "number" or n ~= n or n == math.huge or n == -math.huge
            or n ~= math.floor(n)) then return nil end
    end
    if job.type ~= "depositIds" and job.type ~= "physical" and job.referenceItemId == nil then return nil end
    if job.type == "partial" and (not job.count or job.count < 1 or job.count > 4096) then return nil end
    if job.expectedUnits and (job.expectedUnits < 0 or job.expectedUnits > 4096) then return nil end
	if operation and operation.networkId and job.networkId
		and operation.networkId ~= job.networkId then
		GlobalStorageSiK.Log.warn("TransferQueue", "queue rejected across networks",
			"active=" .. tostring(operation.networkId) .. " requested=" .. tostring(job.networkId))
		return nil
	end
	initialiseJob(job)
	if pendingJob then
		table.insert(queuedJobs, job)
		showProgress(false)
		return job.queueId, false, job.networkId
	end
	-- El caller envía el primer request inmediatamente. Desde este instante la
	-- vigilancia ya está armada para que una respuesta perdida no deje residuos.
	if not activateJob(job, job.type ~= "physical") then return nil end
	showProgress(true)
	return job.queueId, job.type ~= "physical", job.networkId
end

---@param job table
local function scheduleRetry(job)
	job.queueId = nextId(playerNum)
	pendingJob = job
	batchCount = batchCount + 1
	nextRunMs = (getTimestampMs and getTimestampMs() or 0) + batchDelayMs()
	ensureTickInstalled()
end

--- Envía el trabajo pendiente al servidor.
---@param job table
local function dispatchJob(job)
	if not job or not GlobalStorageSiK.NetClient or not GlobalStorageSiK.NetClient.sendCommand then
		return false
	end
	if job.type == "physical" then
		local entry = job.physicalItems[job.physicalIndex]
		if not entry then return false end
		return GlobalStorageSiK.NetClient.sendCommand("depositItems", {
			mode = entry.kind == "floor" and "floor" or nil,
			sourceKey = entry.sourceKey, fullType = entry.fullType, itemIds = { entry.itemId },
			origin = "player_queue", queueId = job.queueId, depositId = job.gestureId,
			networkId = job.networkId,
		}, job.player)
	elseif job.type == "depositIds" then
		return GlobalStorageSiK.NetClient.sendCommand("depositItems", {
			itemIds = job.itemIds or {},
			origin = job.origin or "player_queue",
			operationId = job.operationId,
			preferredNodeId = job.preferredNodeId,
			queueId = job.queueId,
			depositId = job.gestureId,
			networkId = job.networkId,
		}, job.player)
	elseif job.type == "container" then
		return GlobalStorageSiK.NetClient.sendCommand("depositItems", {
			mode = "container",
			referenceItemId = job.referenceItemId,
			origin = "player_queue",
			queueId = job.queueId,
			depositId = job.gestureId,
			networkId = job.networkId,
		}, job.player)
	elseif job.type == "partial" then
		return GlobalStorageSiK.NetClient.sendCommand("depositItems", {
			mode = "partial",
			referenceItemId = job.referenceItemId,
			count = job.count,
			origin = "player_queue",
			queueId = job.queueId,
			depositId = job.gestureId,
			networkId = job.networkId,
		}, job.player)
	end
	return false
end

--- Limpia la cola de transferencias en curso (p. ej. al perder acceso).
function Q.clear(reason, feedbackHandled)
    local player = pendingJob and pendingJob.player
    pendingJob = nil
    queuedJobs = {}
    nextRunMs = 0
    inFlight = false
    responseDeadlineMs = 0
    finishOperation()
    if reason and player and not feedbackHandled then
        GlobalStorageSiK.UIFeedback.halo(player, GlobalStorageSiK.I18n.text("IGUI_GS_DepositFailGeneric"),
            255, 180, 100, 2500, { tone = "warning", channel = "deposit", dedupeKey = reason })
    end
end

function Q.isResponseExpected(args)
    return type(args) == "table" and pendingJob ~= nil and inFlight
        and args.queueId == pendingJob.queueId and playerValid(pendingJob)
end

function Q.onTick()
	if not pendingJob then
		return
	end
	if not playerValid(pendingJob) then Q.clear("player_unavailable"); return end
	local now = getTimestampMs and getTimestampMs() or 0
	if inFlight then
		if now < responseDeadlineMs then return end
		if pendingJob.type == "partial" or pendingJob.type == "physical" then
			-- Un depósito parcial puede conservar el mismo itemId con un count
			-- reducido. Reenviarlo a ciegas movería otra porción, así que ante una
			-- respuesta perdida se termina sin reintento (misma regla que retiro).
			GlobalStorageSiK.Log.error("TransferQueue", "non-replayable response timeout",
				"queueId=" .. tostring(pendingJob.queueId))
			Q.clear("transfer_failed")
			return
		end
		pendingJob.timeoutRetries = (pendingJob.timeoutRetries or 0) + 1
		if pendingJob.timeoutRetries > MAX_TIMEOUT_RETRIES then
			GlobalStorageSiK.Log.error("TransferQueue", "response timeout",
				"queueId=" .. tostring(pendingJob.queueId)
					.. " retries=" .. tostring(MAX_TIMEOUT_RETRIES))
			Q.clear("transfer_failed")
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
	nextRunMs = now + batchDelayMs()
	inFlight = true
	responseDeadlineMs = now + RESPONSE_TIMEOUT_MS
	local sent = dispatchJob(pendingJob)
	if sent == false and pendingJob then
		GlobalStorageSiK.Log.error("TransferQueue", "dispatch failed",
			"queueId=" .. tostring(pendingJob.queueId) .. " type=" .. tostring(pendingJob.type))
		Q.clear("transfer_failed")
	end
end

-- A continuation can only contain unprocessed IDs from this gesture. Copy it
-- before the caller shares the response with other UI consumers.
local function copyRemaining(job, ids)
    if type(ids) ~= "table" or #ids == 0 or #ids > 4096 then return nil end
    local allowed, seen, result = {}, {}, {}
    if job.itemIds then
        for i = 1, #job.itemIds do allowed[job.itemIds[i]] = true end
    end
    for i = 1, #ids do
        local id = ids[i]
        if type(id) ~= "number" or id ~= id or id == math.huge or id == -math.huge
            or id ~= math.floor(id) or seen[id] or (job.itemIds and not allowed[id]) then return nil end
        seen[id] = true; result[#result + 1] = id
    end
    return result
end

--- Procesa respuesta del servidor; devuelve true si continúa en segundo plano.
---@param args table|nil
---@return boolean continuing
function Q.onActionResult(args)
	if not Q.isResponseExpected(args) then
		return false
	end

	if args.queueId and args.queueId == pendingJob.queueId and not (args.deposit or args.bulk) then
		Q.clear("transfer_failed")
		return false
	end
	local summary = args.deposit or args.bulk
    if type(summary) ~= "table" then Q.clear("invalid_response"); return false end
    for _, key in ipairs({ "moved", "skipped", "failed", "missing", "processed" }) do
        local value = summary[key]
        if value ~= nil and (type(value) ~= "number" or value ~= value or value < 0
            or value == math.huge or value ~= math.floor(value)) then
            Q.clear("invalid_response"); return false
        end
    end
    local remaining
    if summary.reason == "limit" then
        remaining = copyRemaining(pendingJob, summary.remainingIds)
        if not remaining or (summary.processed or 0) <= 0 or pendingJob.type == "partial" then
            Q.clear("invalid_response"); return false
        end
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
	if pendingJob.type == "physical" then
		local entry = pendingJob.physicalItems[pendingJob.physicalIndex]
		local ids = summary.itemIds
		if args.ok ~= true or summary.reconcile == true or summary.moved ~= 1
			or (summary.failed or 0) > 0 or (summary.skipped or 0) > 0
			or (entry.kind == "floor" and (type(ids) ~= "table" or #ids ~= 1 or ids[1] ~= entry.itemId)) then
			args.ok = false
			args.message = GlobalStorageSiK.I18n.remote("IGUI_GS_TransferWarning")
			args.transfer = args.transfer or {}
			args.transfer.reason = summary.reason or "transfer_failed"
			args.transfer.reconcile = summary.reconcile == true
			-- GS_Client owns ACK feedback; avoid a second generic halo here.
			Q.clear(args.transfer.reason, true)
			return false
		end
		pendingJob.physicalIndex = pendingJob.physicalIndex + 1
		if pendingJob.physicalIndex <= #pendingJob.physicalItems then
			scheduleRetry(pendingJob)
			showProgress(false)
			return true
		end
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
			Q.clear("transfer_failed")
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
			Q.clear("transfer_failed")
			return false
		end
		if (pendingJob.type == "depositIds" or pendingJob.type == "container")
			and summary.remainingIds then
			pendingJob.type = "depositIds"
			pendingJob.itemIds = remaining
		end
		scheduleRetry(pendingJob)
		showProgress(false)
		return true
	end

	local completedJob = pendingJob
	local completedBatches = batchCount + 1
	if operation then
		operation.totalInspected = (operation.totalInspected or 0) + (summary.processed or 0)
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
		finishOperation()
		if not activateJob(table.remove(queuedJobs, 1), false) then Q.clear("transfer_failed"); return false end
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
			.. " inspected=" .. tostring(operation and operation.totalInspected or summary.processed or 0)
			.. " budgetExhaustions=0"
			.. " elapsedMs=" .. tostring(operation and nowMs() - (operation.startedMs or nowMs()) or 0)
			.. " cancelled=false timeout=false error=" .. tostring(summary.reason ~= nil
				and summary.reason ~= "not_found")
			.. " reason=" .. tostring(summary.reason)
			.. " " .. GlobalStorageSiK.OperationPacing.describe(operation and operation.pacing))
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
	Q.clear()
	return false
end

return Q
end

function Queue.arm(job, playerArg)
    local num = playerNumber(playerArg)
    if num == nil then return nil end
    local player = GlobalStorageSiK.NetClient.getPlayer(num)
    if playerArg ~= nil and type(playerArg) ~= "number" and player ~= playerArg then return nil end
    if not queues[num] then queues[num] = createQueue(num) end
    return queues[num].arm(job, player)
end

function Queue.isActive(playerArg)
    if playerArg == nil then
        for num = 0, 3 do if queues[num] and queues[num].isActive() then return true end end
        return false
    end
    local num = playerNumber(playerArg)
    return num ~= nil and queues[num] ~= nil and queues[num].isActive() or false
end

local function uninstallIdleTick()
    if tickInstalled and not Queue.isActive() then
        Events.OnTick.Remove(Queue.onTick)
        tickInstalled = false
    end
end

function Queue.clear(playerArg)
    if playerArg == nil then
        for num = 0, 3 do if queues[num] then queues[num].clear() end end
    else
        local num = playerNumber(playerArg)
        if num ~= nil and queues[num] then queues[num].clear() end
    end
    uninstallIdleTick()
end

function Queue.isResponseExpected(args)
    if type(args) ~= "table" then return false end
    local num = playerNumber(args.playerNum)
    return num ~= nil and queues[num] ~= nil and queues[num].isResponseExpected(args) or false
end

function Queue.onActionResult(args)
    if not Queue.isResponseExpected(args) then return false end
    local continuing = queues[playerNumber(args.playerNum)].onActionResult(args)
    uninstallIdleTick()
    return continuing
end

function Queue.onTick()
    for num = 0, 3 do if queues[num] then queues[num].onTick() end end
    uninstallIdleTick()
end

return Queue
