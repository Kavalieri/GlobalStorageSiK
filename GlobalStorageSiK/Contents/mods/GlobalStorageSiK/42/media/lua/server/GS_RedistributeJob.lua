--[[
	GlobalStorageSiK - Job en segundo plano para "Ordenar por categoria"
	Autor: SiK
	Fecha: 2026-07-02
	Descripcion: redistributeNetwork() solo mueve un lote (MaxItemsPerBulkTick)
	por llamada. Antes el jugador tenia que pulsar el boton a mano una vez por
	lote. Este modulo relanza la redistribucion automaticamente cada pocos
	segundos hasta terminar toda la red (o hasta que ya no quede nada por
	mover), con un solo click inicial.
]]

require "GS_Redistribute"
require "GS_PlayerUtils"
require "GS_TerminalAccess"

GlobalStorageSiK.RedistributeJob = {}

-- Pausa entre lotes. Bajo para que se note fluido, alto para no saturar el
-- servidor si hay muchos items desordenados; el propio limite de
-- MaxItemsPerBulkTick ya acota el coste de cada lote individual.
local RETRY_DELAY_MS = 2500

local jobs = {}          -- networkId -> { username, nextRunMs, moved, failed, skipped }
local tickInstalled = false

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

local function finishJob(networkId, job, reason)
	GlobalStorageSiK.Log.debug("RedistributeJob", "finishJob | networkId=" .. tostring(networkId) .. " reason=" .. tostring(reason)
		.. " moved=" .. tostring(job.moved) .. " failed=" .. tostring(job.failed))
	jobs[networkId] = nil
	local player = resolvePlayer(job.username)
	if not player then
		GlobalStorageSiK.Log.debug("RedistributeJob", "finishJob | jugador " .. tostring(job.username) .. " no resuelto, sin notificar")
		return
	end
	local summary = { moved = job.moved, failed = job.failed, skipped = job.skipped, reason = reason }
	local msg
	if reason == "remote_disabled" or reason == "no_power" or reason == "no_nodes" then
		msg = GlobalStorageSiK.Redistribute.formatSummaryMessage(summary)
	elseif job.moved == 0 and job.failed == 0 then
		msg = GlobalStorageSiK.I18n.remote("IGUI_GS_RedistributeNothingToSort")
	else
		msg = GlobalStorageSiK.I18n.remote("IGUI_GS_RedistributeCompleteMsg", job.moved, job.failed)
	end
	local ok = reason ~= "remote_disabled" and reason ~= "no_power" and reason ~= "no_player"
	-- gsSendServerCommand es local a GS_Server.lua; nunca fue global, por lo
	-- que esta llamada fallaba SIEMPRE ("tried to call nil") sin que se
	-- notara antes porque el error, aunque se imprimia en consola, no
	-- interrumpia el juego. Por eso el mensaje de finalizacion nunca llegaba.
	-- jobType="redistribute" (2026-08-17, pedido explicito): marca de fin
	-- para que el cliente pueda distinguir ESTE actionResult concreto del
	-- resto (depositos/retiros normales) y actualizar el semaforo de estado
	-- del boton Auto-ordenar en GS_TerminalUI.lua sin adivinar por el texto.
	GlobalStorageSiK.Server.sendCommand(player, "actionResult", { ok = ok, message = msg, jobType = "redistribute" })
	if GlobalStorageSiK.Server and GlobalStorageSiK.Server.pushTerminalState then
		-- BUG REAL encontrado (reportado 2026-08-16, "las pestañas de addon
		-- desaparecen mientras el reordenado esta activo"): pushTerminalState
		-- SOLO incluye installedAddons/craftTabEnabled/buildTabEnabled en el
		-- payload si se le pasa terminalAnchor (ver GS_Server.lua) - sin el,
		-- el cliente recibe un terminalState con esos campos ausentes y la
		-- visibilidad de la pestaña se recalcula como "ocultar". Un job de
		-- reordenado dura decenas de segundos y empuja este estado cada
		-- ~2.5s (RETRY_DELAY_MS), asi que sin el anchor las pestañas
		-- parpadeaban/desaparecian repetidamente durante todo el job.
		local anchor = GlobalStorageSiK.TerminalAccess and GlobalStorageSiK.TerminalAccess.getSessionAnchor
			and GlobalStorageSiK.TerminalAccess.getSessionAnchor(player)
		GlobalStorageSiK.Server.pushTerminalState(player, networkId, nil, "", nil, false, nil, anchor)
	end
end

--- Ejecuta un lote para cada job cuyo turno haya llegado.
local function onTick()
	local now = nowMs()
	for networkId, job in pairs(jobs) do
		if now >= job.nextRunMs then
			local player = resolvePlayer(job.username)
			if not player then
				GlobalStorageSiK.Log.debug("RedistributeJob", "onTick | jugador " .. tostring(job.username) .. " no resuelto, job cancelado en silencio")
				jobs[networkId] = nil
			else
				local ok, summary = pcall(GlobalStorageSiK.Redistribute.redistributeNetwork, player, networkId)
				if ok then
					GlobalStorageSiK.Log.debug("RedistributeJob", "onTick | redistributeNetwork moved=" .. tostring(summary.moved)
						.. " failed=" .. tostring(summary.failed) .. " skipped=" .. tostring(summary.skipped) .. " reason=" .. tostring(summary.reason))
				end
				if not ok then
					-- Sin este pcall, un error aqui dejaba el job colgado para
					-- siempre en silencio: nunca se volvia a intentar y nunca
					-- se avisaba al jugador (el boton "no hacia nada").
					GlobalStorageSiK.Log.error("RedistributeJob", "onTick failed: " .. tostring(summary))
					finishJob(networkId, job, "error")
				else
					job.moved   = job.moved   + (summary.moved   or 0)
					job.failed  = job.failed  + (summary.failed  or 0)
					job.skipped = job.skipped + (summary.skipped or 0)
					if summary.reason == "limit" then
						-- Queda mas trabajo: siguiente lote dentro de RETRY_DELAY_MS.
						-- Empuja el estado ya para que el jugador vea progreso en vivo.
						job.nextRunMs = now + RETRY_DELAY_MS
						if GlobalStorageSiK.Server and GlobalStorageSiK.Server.pushTerminalState then
							-- Mismo motivo que en finishJob: sin terminalAnchor el
							-- cliente pierde installedAddons/craftTabEnabled/
							-- buildTabEnabled en cada empuje intermedio del job.
							local anchor = GlobalStorageSiK.TerminalAccess and GlobalStorageSiK.TerminalAccess.getSessionAnchor
								and GlobalStorageSiK.TerminalAccess.getSessionAnchor(player)
							GlobalStorageSiK.Server.pushTerminalState(player, networkId, nil, "", nil, false, nil, anchor)
						end
					else
						finishJob(networkId, job, summary.reason)
					end
				end
			end
		end
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
	}
	GlobalStorageSiK.Log.debug("RedistributeJob", "start | nuevo job para " .. tostring(networkId) .. " user=" .. tostring(player:getUsername()) .. " tickInstalled=" .. tostring(tickInstalled))
	return true
end

--- Indica si hay un job de reordenacion activo para esa red.
---@param networkId string
---@return boolean
function GlobalStorageSiK.RedistributeJob.isActive(networkId)
	return jobs[networkId] ~= nil
end
