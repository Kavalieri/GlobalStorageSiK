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

GlobalStorageSiK.RedistributeJob = {}

-- Cada paso ya tiene presupuesto de inspeccion, tiempo y movimientos en
-- GS_Redistribute. La pausa adicional deja respirar al resto de simulacion y
-- evita una rafaga continua de remove/add en servidores con muchos jugadores.
local INDEX_DELAY_MS = 250
local MOVE_DELAY_MS = 1000
local MOVE_IDLE_DELAY_MS = 250
local BUSY_DELAY_MS = 500
local GLOBAL_STEP_DELAY_MS = 100
local PROGRESS_INTERVAL_MS = 15000

local jobs = {}          -- networkId -> { username, nextRunMs, moved, failed, skipped, watchers }
local tickInstalled = false
local nextGlobalRunMs = 0

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

local function notifyProgress(job, summary)
	local messageKey = summary.phase == "index"
		and "IGUI_GS_RedistributeProgressIndex"
		or "IGUI_GS_RedistributeProgressMove"
	eachRecipient(job, function(player)
		GlobalStorageSiK.Server.sendCommand(player, "actionResult", {
			ok = true,
			message = GlobalStorageSiK.I18n.remote(messageKey,
				summary.checked or 0, summary.total or 0, job.moved or 0),
			jobType = "redistribute",
			jobState = "running",
		})
	end)
end

local function finishJob(networkId, job, reason)
	GlobalStorageSiK.Log.debug("RedistributeJob", "finishJob | networkId=" .. tostring(networkId) .. " reason=" .. tostring(reason)
		.. " moved=" .. tostring(job.moved) .. " failed=" .. tostring(job.failed))
	jobs[networkId] = nil
	local summary = { moved = job.moved, failed = job.failed, skipped = job.skipped, reason = reason }
	local msg
	if reason == "remote_disabled" or reason == "no_power" or reason == "no_nodes" then
		msg = GlobalStorageSiK.Redistribute.formatSummaryMessage(summary)
	elseif job.moved == 0 and job.failed == 0 then
		msg = GlobalStorageSiK.I18n.remote("IGUI_GS_RedistributeNothingToSort")
	else
		msg = GlobalStorageSiK.I18n.remote("IGUI_GS_RedistributeCompleteMsg", job.moved, job.failed)
	end
	local ok = reason ~= "remote_disabled" and reason ~= "no_power"
		and reason ~= "no_nodes" and reason ~= "no_player" and reason ~= "error"
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
local function onTick()
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
		job.nextRunMs = now + BUSY_DELAY_MS
		return
	end
	local ok, summary, session = pcall(
		GlobalStorageSiK.Redistribute.redistributeNetwork, player, networkId, job.session)
	GlobalStorageSiK.TransferLock.release(networkId, player)
	if ok then
		job.session = session
		GlobalStorageSiK.Log.debug("RedistributeJob", "onTick | redistributeNetwork moved=" .. tostring(summary.moved)
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
	if (summary.moved or 0) > 0 and GlobalStorageSiK.Server
		and GlobalStorageSiK.Server.markInventoryDirty then
		GlobalStorageSiK.Server.markInventoryDirty(networkId)
	end
	if summary.reason == "limit" then
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
