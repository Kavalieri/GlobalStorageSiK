--[[
	GlobalStorageSiK - Job en segundo plano para "Ordenar por categoria"
	Autor: SiK
	Fecha: 2026-07-02
	Descripcion: planificador incremental y equitativo de Auto Sort. Conserva
	una captura/cursor por red, ejecuta un solo paso global acotado cada vez y
	separa inspeccion de movimientos replicados hasta terminar con un clic.
]]

require "GS_Redistribute"
require "GS_PlayerUtils"
require "GS_TerminalAccess"
require "GS_TransferLock"
require "GS_InventorySync"

GlobalStorageSiK.RedistributeJob = {}

-- Cada paso ya tiene presupuesto de inspeccion, tiempo y movimientos en
-- GS_Redistribute. La pausa adicional deja respirar al resto de simulacion y
-- evita una rafaga continua de remove/add en servidores con muchos jugadores.
local INDEX_DELAY_MS = 250
local MOVE_DELAY_MS = 1000
local MOVE_IDLE_DELAY_MS = 250
local BUSY_DELAY_MS = 500
local GLOBAL_STEP_DELAY_MS = 100
local PROGRESS_INTERVAL_MS = 5000
local MAX_BUSY_RETRIES = 120
local MAX_STALLED_STEPS = 5

local jobs = {}          -- networkId -> { username, nextRunMs, moved, failed, skipped, watchers }
local tickInstalled = false
local nextGlobalRunMs = 0
local onTick

local function hasJobs()
	for _ in pairs(jobs) do return true end
	return false
end

local function uninstallTickIfIdle()
	if hasJobs() then return end
	if tickInstalled and Events and Events.OnTick and onTick then
		Events.OnTick.Remove(onTick)
	end
	tickInstalled = false
	nextGlobalRunMs = 0
end

local function nowMs()
	if getTimestampMs then
		return getTimestampMs()
	end
	return 0
end

--- Notifica al jugador (si sigue online) y limpia el job.
---@param networkId string
---@param job table
---@param reason string|nil razon final: nil/"done" = completado sin mas trabajo
local function resolvePlayer(username)
	-- getPlayerFromUsername demostro no ser fiable aqui: en pruebas devolvia
	-- nil con el jugador claramente conectado. GS_PlayerUtils.resolveByUsername
	-- itera getOnlinePlayers/getSpecificPlayer (el mismo patron ya usado con
	-- exito en GS_Server.lua) antes de caer a getPlayerFromUsername.
	return GlobalStorageSiK.PlayerUtils.resolveByUsername(username)
end

local function eachRecipient(job, fn)
	local recipients = { [job.username] = true }
	for username in pairs(job.watchers or {}) do recipients[username] = true end
	for username in pairs(recipients) do
		local player = resolvePlayer(username)
		if player then fn(player) end
	end
end

local function mergeCounts(dest, source)
	for key, count in pairs(source or {}) do
		dest[key] = (dest[key] or 0) + (tonumber(count) or 0)
	end
end

local function tierSummary(counts)
	local parts = {}
	for tier = 1, 5 do
		local count = counts and counts[tostring(tier)] or 0
		if count > 0 then
			parts[#parts + 1] = tostring(tier) .. ":" .. tostring(count)
		end
	end
	return #parts > 0 and table.concat(parts, ",") or "none"
end

local function topTypeSummary(counts, limit)
	local rows = {}
	for fullType, count in pairs(counts or {}) do
		rows[#rows + 1] = { fullType = tostring(fullType), count = tonumber(count) or 0 }
	end
	table.sort(rows, function(a, b)
		if a.count ~= b.count then return a.count > b.count end
		return a.fullType < b.fullType
	end)
	local parts = {}
	for i = 1, math.min(#rows, limit or 8) do
		parts[#parts + 1] = rows[i].fullType .. ":" .. tostring(rows[i].count)
	end
	return #parts > 0 and table.concat(parts, ",") or "none"
end

local function notifyProgress(job, summary)
	local messageKey = summary.phase == "index"
		and "IGUI_GS_RedistributeProgressIndex"
		or "IGUI_GS_RedistributeProgressMove"
	eachRecipient(job, function(player)
		GlobalStorageSiK.Server.sendCommand(player, "actionResult", {
			ok = true,
			message = GlobalStorageSiK.I18n.remote(messageKey,
				summary.checked or 0, summary.total or 0, job.moved or 0,
				job.skipped or 0, job.failed or 0),
			jobType = "redistribute",
			jobState = "running",
		})
	end)
end

local function finishJob(networkId, job, reason)
	local tiers = tierSummary(job.movedByTier)
	local topTypes = topTypeSummary(job.movedByType, 8)
	GlobalStorageSiK.Log.debug("RedistributeJob", "finishJob | networkId=" .. tostring(networkId) .. " reason=" .. tostring(reason)
		.. " moved=" .. tostring(job.moved) .. " failed=" .. tostring(job.failed)
		.. " tiers=" .. tiers .. " topTypes=" .. topTypes)
	jobs[networkId] = nil
	-- Liberar el tick antes de cualquier notificación/UI potencialmente falible:
	-- un error al informar no puede dejar polling sin un job que procesar.
	uninstallTickIfIdle()
	local summary = { moved = job.moved, failed = job.failed, skipped = job.skipped, reason = reason }
	local msg
	if reason == "network_busy" or reason == "stalled" then
		msg = GlobalStorageSiK.I18n.remote("IGUI_GS_InternalTransferError")
	elseif reason == "remote_disabled" or reason == "no_power" or reason == "no_nodes" then
		msg = GlobalStorageSiK.Redistribute.formatSummaryMessage(summary)
	elseif job.moved == 0 and job.failed == 0 then
		msg = GlobalStorageSiK.I18n.remote("IGUI_GS_RedistributeNothingToSort")
	else
		msg = GlobalStorageSiK.I18n.remote("IGUI_GS_RedistributeCompleteMsg",
			job.moved, job.skipped, job.failed)
	end
	local ok = reason ~= "remote_disabled" and reason ~= "no_power"
		and reason ~= "no_nodes" and reason ~= "no_player" and reason ~= "error"
		and reason ~= "network_busy" and reason ~= "stalled"
	-- gsSendServerCommand es local a GS_Server.lua; nunca fue global, por lo
	-- que esta llamada fallaba SIEMPRE ("tried to call nil") sin que se
	-- notara antes porque el error, aunque se imprimia en consola, no
	-- interrumpia el juego. Por eso el mensaje de finalizacion nunca llegaba.
	-- jobType="redistribute" (2026-08-17, pedido explicito): marca de fin
	-- para que el cliente pueda distinguir ESTE actionResult concreto del
	-- resto (depositos/retiros normales), actualizar el panel de estado y
	-- volver a habilitar Auto-ordenar sin adivinar por el texto.
	eachRecipient(job, function(player)
		GlobalStorageSiK.Server.sendCommand(player, "actionResult", {
			ok = ok,
			message = msg,
			jobType = "redistribute",
			jobState = "finished",
			redistributeTiers = tiers,
			redistributeTopTypes = topTypes,
		})
		if GlobalStorageSiK.Server and GlobalStorageSiK.Server.pushTerminalState then
			-- terminalAnchor preserva las pestañas de addons en cada estado
			-- enviado durante y al terminar el job.
			local anchor = GlobalStorageSiK.TerminalAccess and GlobalStorageSiK.TerminalAccess.getSessionAnchor
				and GlobalStorageSiK.TerminalAccess.getSessionAnchor(player)
			GlobalStorageSiK.Server.pushTerminalState(player, networkId, nil, "", nil, false, nil, anchor)
		end
	end)
end

--- Ejecuta como maximo UN lote global por tick. Con muchas redes activas,
--- ejecutar todos los jobs vencidos dentro del mismo OnTick sumaba sus
--- presupuestos y podia volver a bloquear el servidor aunque cada red
--- individual estuviera limitada. El job procesado aplaza su siguiente turno,
--- por lo que los demas vencidos quedan elegibles en los ticks siguientes.
onTick = function()
	local now = nowMs()
	if now < nextGlobalRunMs then return end
	local networkId = nil
	local job = nil
	local oldestDueMs = nil
	for candidateId, candidate in pairs(jobs) do
		if now >= candidate.nextRunMs
			and (oldestDueMs == nil or candidate.nextRunMs < oldestDueMs) then
			networkId = candidateId
			job = candidate
			oldestDueMs = candidate.nextRunMs
		end
	end
	if not job then
		return
	end
	-- Presupuesto compartido: aunque haya muchas redes vencidas, todo Auto Sort
	-- combinado ejecuta como máximo un paso cada 100 ms. El job elegido queda
	-- aplazado y los demás se atienden en ticks posteriores (round-robin por
	-- vencimiento, sin sumar N presupuestos pesados en el mismo frame).
	nextGlobalRunMs = now + GLOBAL_STEP_DELAY_MS

	local player = resolvePlayer(job.username)
	if not player then
		GlobalStorageSiK.Log.debug("RedistributeJob", "onTick | jugador " .. tostring(job.username) .. " no resuelto, job cancelado")
		finishJob(networkId, job, "no_player")
		return
	end

	-- El bloqueo se conserva solo durante ESTE paso acotado. Entre pasos la red
	-- queda libre para depósitos, retiros y otras sesiones; si otra operación
	-- está activa, Auto Sort cede el turno sin invalidar su captura/cursor.
	local acquired = GlobalStorageSiK.TransferLock.acquire(networkId, player, "redistribute")
	if not acquired then
		job.busyRetries = (job.busyRetries or 0) + 1
		if job.busyRetries > MAX_BUSY_RETRIES then
			GlobalStorageSiK.Log.error("RedistributeJob", "network remained busy",
				"networkId=" .. tostring(networkId) .. " retries=" .. tostring(MAX_BUSY_RETRIES))
			finishJob(networkId, job, "network_busy")
			return
		end
		job.nextRunMs = now + BUSY_DELAY_MS
		return
	end
	job.busyRetries = 0
	local ok, summary, session = pcall(function()
		return GlobalStorageSiK.InventorySync.withBatch(function()
			return GlobalStorageSiK.Redistribute.redistributeNetwork(player, networkId, job.session)
		end)
	end)
	GlobalStorageSiK.TransferLock.release(networkId, player)
	if ok then
		job.session = session
		GlobalStorageSiK.Log.detail("RedistributeJob", "onTick | redistributeNetwork moved=" .. tostring(summary.moved)
			.. " failed=" .. tostring(summary.failed) .. " skipped=" .. tostring(summary.skipped)
			.. " checked=" .. tostring(summary.checked) .. "/" .. tostring(summary.total)
			.. " phase=" .. tostring(summary.phase) .. " reason=" .. tostring(summary.reason))
	end
	if not ok then
		-- Sin este pcall, un error aqui dejaba el job colgado para siempre
		-- en silencio: nunca se volvia a intentar ni se avisaba al jugador.
		GlobalStorageSiK.Log.error("RedistributeJob", "onTick failed: " .. tostring(summary))
		finishJob(networkId, job, "error")
		return
	end

	job.moved   = job.moved   + (summary.moved   or 0)
	job.failed  = job.failed  + (summary.failed  or 0)
	job.skipped = job.skipped + (summary.skipped or 0)
	mergeCounts(job.movedByTier, summary.movedByTier)
	mergeCounts(job.movedByType, summary.movedByType)
	if (summary.moved or 0) > 0 and GlobalStorageSiK.Server
		and GlobalStorageSiK.Server.markInventoryDirty then
		GlobalStorageSiK.Server.markInventoryDirty(networkId, player)
	end
	if summary.reason == "limit" then
		local progressKey = tostring(summary.phase) .. ":" .. tostring(summary.checked or 0)
		if progressKey == job.lastProgressKey then
			job.stalledSteps = (job.stalledSteps or 0) + 1
		else
			job.lastProgressKey = progressKey
			job.stalledSteps = 0
		end
		if job.stalledSteps >= MAX_STALLED_STEPS then
			GlobalStorageSiK.Log.error("RedistributeJob", "job made no progress",
				"networkId=" .. tostring(networkId) .. " cursor=" .. progressKey)
			finishJob(networkId, job, "stalled")
			return
		end
		-- No se envia un terminalState completo en cada paso intermedio. El
		-- boton ya indica que el job sigue activo y el estado final refresca la
		-- UI; esto evita otro payload grande repetido durante redes masivas.
		local stepDelay = INDEX_DELAY_MS
		if summary.phase ~= "index" then
			-- Los remove/add replicados son lo caro y conservan la pausa larga.
			-- Un barrido que no movió nada puede continuar antes sin generar red.
			stepDelay = (summary.moved or 0) > 0 and MOVE_DELAY_MS or MOVE_IDLE_DELAY_MS
		end
		job.nextRunMs = now + stepDelay
		local phaseChanged = summary.phase ~= job.lastPhase
		if phaseChanged or now - (job.lastProgressMs or 0) >= PROGRESS_INTERVAL_MS then
			job.lastPhase = summary.phase
			job.lastProgressMs = now
			notifyProgress(job, summary)
		end
	else
		finishJob(networkId, job, summary.reason)
	end
end

local function ensureTickInstalled()
	if tickInstalled then
		return
	end
	tickInstalled = true
	if Events and Events.OnTick then
		Events.OnTick.Add(onTick)
	end
end

--- Inicia (o reengancha) la reordenacion automatica de una red completa.
--- Si ya hay un job en curso para esa red, no hace nada (evita duplicar
--- trabajo si el jugador pulsa el boton varias veces seguidas).
---@param player IsoPlayer
---@param networkId string|nil
---@return boolean started
function GlobalStorageSiK.RedistributeJob.start(player, networkId)
	if not player or not networkId then
		return false
	end
	if jobs[networkId] then
		GlobalStorageSiK.Log.debug("RedistributeJob", "start | ya habia un job activo para " .. tostring(networkId))
		return false
	end
	ensureTickInstalled()
	jobs[networkId] = {
		username  = player:getUsername(),
		nextRunMs = 0,
		moved     = 0,
		failed    = 0,
		skipped   = 0,
		watchers  = {},
		session   = nil,
		lastPhase = nil,
		lastProgressMs = 0,
		lastProgressKey = nil,
		stalledSteps = 0,
		busyRetries = 0,
		movedByTier = {},
		movedByType = {},
	}
	GlobalStorageSiK.Log.debug("RedistributeJob", "start | nuevo job para " .. tostring(networkId) .. " user=" .. tostring(player:getUsername()) .. " tickInstalled=" .. tostring(tickInstalled))
	return true
end

--- Registra otro cliente interesado en el resultado de un job ya activo.
---@param player IsoPlayer
---@param networkId string
function GlobalStorageSiK.RedistributeJob.addWatcher(player, networkId)
	local job = jobs[networkId]
	if not job or not player then return end
	local username = player:getUsername()
	if username and username ~= job.username then
		job.watchers[username] = true
	end
end

--- Indica si hay un job de reordenacion activo para esa red.
---@param networkId string
---@return boolean
function GlobalStorageSiK.RedistributeJob.isActive(networkId)
	return jobs[networkId] ~= nil
end
