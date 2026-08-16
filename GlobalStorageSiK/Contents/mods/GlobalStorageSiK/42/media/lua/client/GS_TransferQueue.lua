--[[
	GlobalStorageSiK - Cola de transferencias masivas (cliente)
	Autor: SiK
	Fecha: 2025-06-25
	Descripción: Continúa depósitos por lotes cuando el servidor alcanza MaxItemsPerBulkTick.
]]

require "GS_NetClient"
require "GS_Log"

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
-- para recortar pendingJob.itemIds antes de cada reintento. MAX_BATCHES se
-- mantiene como red de seguridad por si algun otro tipo de job (container/
-- bulk, que no devuelven remainingIds) se queda enganchado de verdad.
local MAX_BATCHES = 200
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
		GlobalStorageSiK.NetClient.sendCommand("depositItems", {
			itemIds = job.itemIds or {},
			origin = "player_queue",
		})
	elseif job.type == "container" then
		GlobalStorageSiK.NetClient.sendCommand("depositItems", {
			mode = "container",
			referenceItemId = job.referenceItemId,
			origin = "player_queue",
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
		if batchCount + 1 >= MAX_BATCHES then
			GlobalStorageSiK.Log.error("TransferQueue", "max batches reached",
				"batches=" .. tostring(MAX_BATCHES) .. " moved=" .. tostring(summary.moved)
					.. " type=" .. tostring(pendingJob.type))
			pendingJob = nil
			return false
		end
		if pendingJob.type == "depositIds" and summary.remainingIds then
			pendingJob.itemIds = summary.remainingIds
		end
		scheduleRetry(pendingJob)
		return true
	end

	GlobalStorageSiK.Log.debug("TransferQueue", "complete",
		"batches=" .. tostring(batchCount + 1) .. " moved=" .. tostring(summary.moved or 0)
			.. " skipped=" .. tostring(summary.skipped or 0) .. " failed=" .. tostring(summary.failed or 0)
			.. " reason=" .. tostring(summary.reason))
	pendingJob = nil
	return false
end
