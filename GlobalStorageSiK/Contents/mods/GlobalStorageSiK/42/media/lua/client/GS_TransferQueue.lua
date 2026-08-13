--[[
	GlobalStorageSiK - Cola de transferencias masivas (cliente)
	Autor: SiK
	Fecha: 2025-06-25
	Descripción: Continúa depósitos por lotes cuando el servidor alcanza MaxItemsPerBulkTick.
]]

require "GS_NetClient"

GlobalStorageSiK.TransferQueue = {}

local BATCH_DELAY_MS = 400
local pendingJob = nil
local nextRunMs = 0
local tickInstalled = false
local batchCount = 0

---@return boolean
function GlobalStorageSiK.TransferQueue.isActive()
	return pendingJob ~= nil
end

---@param job table
function GlobalStorageSiK.TransferQueue.arm(job)
	if not job or not job.type then
		return
	end
	pendingJob = job
	batchCount = 0
	nextRunMs = math.huge
end

---@param job table
local function scheduleRetry(job)
	pendingJob = job
	batchCount = batchCount + 1
	nextRunMs = (getTimestampMs and getTimestampMs() or 0) + BATCH_DELAY_MS
	if not tickInstalled then
		tickInstalled = true
		Events.OnTick.Add(GlobalStorageSiK.TransferQueue.onTick)
	end
end

--- Envía el trabajo pendiente al servidor.
---@param job table
local function dispatchJob(job)
	if not job or not GlobalStorageSiK.NetClient or not GlobalStorageSiK.NetClient.sendCommand then
		return
	end
	if job.type == "depositIds" then
		GlobalStorageSiK.NetClient.sendCommand("depositItems", { itemIds = job.itemIds or {} })
	elseif job.type == "container" then
		GlobalStorageSiK.NetClient.sendCommand("depositItems", {
			mode = "container",
			referenceItemId = job.referenceItemId,
		})
	elseif job.type == "bulk" then
		GlobalStorageSiK.NetClient.sendCommand("bulkDeposit", { sourceIndex = job.sourceIndex or 1 })
	end
end

--- Limpia la cola de transferencias en curso (p. ej. al perder acceso).
function GlobalStorageSiK.TransferQueue.clear()
	pendingJob = nil
	nextRunMs = 0
end

function GlobalStorageSiK.TransferQueue.onTick()
	if not pendingJob then
		return
	end
	local now = getTimestampMs and getTimestampMs() or 0
	if now < nextRunMs then
		return
	end
	nextRunMs = now + BATCH_DELAY_MS
	dispatchJob(pendingJob)
end

--- Procesa respuesta del servidor; devuelve true si continúa en segundo plano.
---@param args table|nil
---@return boolean continuing
function GlobalStorageSiK.TransferQueue.onActionResult(args)
	if not pendingJob or not args then
		pendingJob = nil
		return false
	end

	local summary = args.deposit or args.bulk
	if not summary then
		pendingJob = nil
		return false
	end

	if summary.reason == "limit" and (summary.moved or 0) > 0 then
		scheduleRetry(pendingJob)
		return true
	end

	pendingJob = nil
	return false
end
