--[[
	GlobalStorageSiK - Vigilancia de acceso al terminal (cliente)
	Autor: SiK
	Fecha: 2025-06-25
	Descripción: SP valida en cliente; MP usa pingTerminalAccess (sin re-scan).
]]

require "GS_Sandbox"
require "GS_Network"
require "GS_NetClient"
require "GS_TerminalAccess"
require "GS_TerminalUI_Api"

GlobalStorageSiK.TerminalAccessGuard = GlobalStorageSiK.TerminalAccessGuard or {}

local CHECK_INTERVAL_MS = 200
local PROBE_INTERVAL_MS = 500
-- World changes made by vanilla/other mods do not all publish a usable access
-- event. Keep a small safety check for visible terminals, never a catalog scan.
local ACCESS_FALLBACK_MS = 1000
local RECOVERY_INTERVAL_MS = 5000
local states = {}
local lastClock = 0
local detach
local probeSerial = 0

local function viewForPlayer(playerNum)
	local api = GlobalStorageSiK.TerminalUI
	if api and api.getInstanceForPlayer then return api.getInstanceForPlayer(playerNum) end
	local view = api and api.instance
	if view and (view.playerNum or 0) == playerNum then return view end
end

---@return string
local function resolveNetworkId(playerNum, ui)
	if ui and ui.accessMode == "blocked" and ui.blockedState then
		return ui.blockedState.networkId
	end
	local state = ui and ui.terminalState
	if state and state.networkId then
		return state.networkId
	end
	-- BUG REAL cerrado (2026-08-22, confirmado en pruebas reales: la ventana
	-- de "Reclamar propiedad" cambiaba sola a "sin acceso" al cabo de unos
	-- segundos, sin moverse del sitio): en modo bloqueado, sendTerminalBlocked
	-- (servidor) ya manda el networkId EXACTO del terminal que el jugador
	-- tiene delante - ui.blockedState.networkId lo guarda (ver
	-- GS_TerminalUI_Blocked.lua:refresh) - pero el propio handler de
	-- "terminalBlocked" en GS_Client.lua limpia Client.cachedTerminalState a
	-- la vez, asi que la SIGUIENTE reprueba periodica (GS_TerminalAccessGuard,
	-- cada pocos segundos) caia al fallback Client.activeNetworkId - que
	-- puede apuntar a una red COMPLETAMENTE DISTINTA (la ultima gestionada
	-- activamente en cualquier otro momento de la sesion, sin relacion con el
	-- terminal actual) - reevaluando y sobreescribiendo el panel con el
	-- resultado de una red equivocada. Mientras el panel de bloqueo este
	-- activo, su propio blockedState.networkId es SIEMPRE la fuente correcta,
	-- prioridad maxima justo despues del tab principal abierto.
	if ui and ui.blockedState and ui.blockedState.networkId then
		return ui.blockedState.networkId
	end
	local client = GlobalStorageSiK.Client
	local cached = client and client.terminalStateByPlayer and client.terminalStateByPlayer[playerNum]
	if cached then return cached.networkId end
	return nil
end

---@return IsoPlayer|nil
local function resolvePlayer(playerNum)
	if GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer then
		local player = GlobalStorageSiK.NetClient.getPlayer(playerNum)
		if player and player:getPlayerNum() == playerNum then return player end
	end
	if playerNum == 0 and getPlayer then
		return getPlayer()
	end
	return nil
end

---@return boolean
local function accessRequired()
	return GlobalStorageSiK.Sandbox and GlobalStorageSiK.Sandbox.requireTerminalAccess
		and GlobalStorageSiK.Sandbox.requireTerminalAccess()
end

--- Limpia sesión, cola de transferencias y estado UI en bloqueo.
---@param player IsoPlayer|nil
local function clearAccessState(player)
	if GlobalStorageSiK.TerminalAccess and GlobalStorageSiK.TerminalAccess.clearSession then
		GlobalStorageSiK.TerminalAccess.clearSession(player)
	end
	if GlobalStorageSiK.TransferQueue and GlobalStorageSiK.TransferQueue.clear then
		GlobalStorageSiK.TransferQueue.clear(player and player:getPlayerNum() or 0)
	end
	if player and GlobalStorageSiK.WithdrawClient and GlobalStorageSiK.WithdrawClient.cancelAll then
		GlobalStorageSiK.WithdrawClient.cancelAll("access_lost", player:getPlayerNum())
	end
	if GlobalStorageSiK.Client then
		local playerNum = player and player:getPlayerNum() or 0
		local client = GlobalStorageSiK.Client
		if client.terminalStateByPlayer then client.terminalStateByPlayer[playerNum] = nil end
		if client.pendingTerminalOpenByPlayer then client.pendingTerminalOpenByPlayer[playerNum] = nil end
		if playerNum == 0 then
			client.cachedTerminalState = nil
			client.pendingTerminalOpen = false
		end
	end
end

--- Cierra terminal principal y muestra modo bloqueado en la misma ventana.
---@param reason string|nil
local function denyOpenUi(reason, playerNum, main, networkId)
	local px, py, pw, ph
	if main and (not main.isVisible or main:isVisible()) then
		px, py = main:getX(), main:getY()
		pw, ph = main:getWidth(), main:getHeight()
	end
	local player = resolvePlayer(playerNum)
	if player and GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.sendCommand then
		GlobalStorageSiK.NetClient.sendCommand("closeTerminal", {networkId=networkId}, player)
	end
	clearAccessState(player)
	if GlobalStorageSiK.TerminalUI and GlobalStorageSiK.TerminalUI.showBlocked then
		GlobalStorageSiK.TerminalUI.showBlocked({reason=reason, playerNum=playerNum,
			networkId=networkId}, { x = px, y = py, w = pw, h = ph })
	end
end

--- Pide al servidor validar acceso sin reescanear (MP).
---@param reopen boolean|nil true si la ventana bloqueada intenta recuperar acceso
local function probeServerAccess(reopen, playerNum, main, state, now)
	if not GlobalStorageSiK.NetClient or not GlobalStorageSiK.NetClient.sendCommand then
		return
	end
	local payload = {}
	local player = resolvePlayer(playerNum)
	if reopen then
		payload.reopen = true
		payload.openSeq = GlobalStorageSiK.TerminalUI.beginAccessRecovery(player)
	else
		payload.openSeq = GlobalStorageSiK.Client and GlobalStorageSiK.Client.terminalOpenSeqByPlayer
			and GlobalStorageSiK.Client.terminalOpenSeqByPlayer[playerNum]
	end
	probeSerial = probeSerial + 1
	payload.accessProbeId = tostring(playerNum) .. ":" .. tostring(now) .. ":" .. tostring(probeSerial)
	state.pendingProbe = payload.accessProbeId
	state.probeDeadline = now + 1500
	local networkId = resolveNetworkId(playerNum, main)
	state.probeNetworkId = networkId
	state.probeOpenSeq = GlobalStorageSiK.Client and GlobalStorageSiK.Client.terminalOpenSeqByPlayer
		and GlobalStorageSiK.Client.terminalOpenSeqByPlayer[playerNum] or 0
	if networkId then
		payload.networkId = networkId
	end
	payload = GlobalStorageSiK.TerminalAccess.enrichCommandPayload(player, payload, networkId)
	local sent = GlobalStorageSiK.NetClient.sendCommand("pingTerminalAccess", payload, player)
	if not sent and state.pendingProbe == payload.accessProbeId then
		-- A synchronous transport failure consumes the same bounded retry budget
		-- as a missing ACK. Keep the deadline; do not create an idle retry loop.
		state.access = "revoking"
		main._gsAccessState = "revoking"
	end
end

local function checkPlayer(playerNum, now)
	if not accessRequired() then
		return
	end

	local main = viewForPlayer(playerNum)
	local isVis = main ~= nil and (not main.isVisible or main:isVisible())
	local blockedOpen = isVis and main.accessMode == "blocked"
	local mainOpen = isVis and main.accessMode ~= "blocked"
	if not mainOpen and not blockedOpen then
		states[playerNum] = nil
		return
	end

	local player = resolvePlayer(playerNum)
	if not player or not GlobalStorageSiK.TerminalAccess then
		states[playerNum] = nil
		return
	end
	if player.isDead and player:isDead() then
		states[playerNum] = nil
		return
	end
	local state = states[playerNum]
	if not state or state.player ~= player or state.ui ~= main then
		state = {player=player, ui=main, dirty=true, nextCheck=0, nextProbe=0,
			confirmedAccess=main.terminalState,
			access=blockedOpen and "blocked" or "in_range"}
		states[playerNum] = state
	end
	local x, y, z = player:getX(), player:getY(), player:getZ()
	if state.x ~= x or state.y ~= y or state.z ~= z or state.mode ~= main.accessMode then
		state.x, state.y, state.z, state.mode = x, y, z, main.accessMode
		state.dirty = true
		state.positionDirty = true
		state.probeRetries = 0
		state.probeExhausted = false
	end
	if state.pendingProbe and now >= state.probeDeadline then
		state.pendingProbe = nil
		state.probeRetries = math.min((state.probeRetries or 0) + 1, 3)
		state.dirty = state.probeRetries <= 2
		if not state.dirty and not state.probeExhausted then
			state.nextRecoveryProbe = now + RECOVERY_INTERVAL_MS
			state.probeExhausted = true
			state.access = "revoking"
			main._gsAccessState = "revoking"
			if GlobalStorageSiK.UIFeedback and GlobalStorageSiK.I18n then
				GlobalStorageSiK.UIFeedback.halo(player,
					GlobalStorageSiK.I18n.text("IGUI_GS_AccessUnconfirmed"), nil, nil, nil, nil,
					{tone="warning", channel="terminal-access"})
			end
		end
	end
	if now >= (state.nextSafetyCheck or 0) then
		state.dirty = true
	end
	if not state.dirty or now < state.nextCheck then return end
	state.nextCheck = now + CHECK_INTERVAL_MS
	state.nextSafetyCheck = now + ACCESS_FALLBACK_MS
	if state.positionDirty then
		state.positionDirty = false
		local panel = GlobalStorageSiK.TerminalBlockedPanel
		if blockedOpen and panel and panel.invalidate then panel.invalidate(main) end
	end

	local trustServer = GlobalStorageSiK.TerminalAccess.trustServerForOpen()
	local pending = GlobalStorageSiK.Client and GlobalStorageSiK.Client.pendingTerminalOpenByPlayer
		and GlobalStorageSiK.Client.pendingTerminalOpenByPlayer[playerNum]

	if trustServer then
		local access = GlobalStorageSiK.TerminalAccess
		local confirmed = state.confirmedAccess or main.terminalState
		if mainOpen and access.evaluateConfirmedAnchor then
			local allowed = access.evaluateConfirmedAnchor(player, confirmed and confirmed.terminalAnchor,
				confirmed and confirmed.confirmedProximityRange, confirmed and confirmed.confirmedWirelessRange)
			if not allowed then
				state.access = "revoking"
				main._gsAccessState = "revoking"
			end
		end
		-- Losing responses must not disable observation or require the player to
		-- move to recover. After the initial budget, probe slowly while visible.
		local recoveryReady = not state.probeExhausted
			or now >= (state.nextRecoveryProbe or 0)
		if not pending and not state.pendingProbe and now >= state.nextProbe and recoveryReady then
			if state.probeExhausted then state.nextRecoveryProbe = now + RECOVERY_INTERVAL_MS end
			state.nextProbe = now + PROBE_INTERVAL_MS
			state.dirty = false
			if blockedOpen then state.access = "revalidating" end
			main._gsAccessState = state.access
			probeServerAccess(blockedOpen, playerNum, main, state, now)
		elseif state.probeExhausted then
			state.dirty = false
		end
		return
	end

	state.dirty = false
	local networkId = resolveNetworkId(playerNum, main)
	local anchor = GlobalStorageSiK.TerminalAccess.getSessionAnchor(player)
	if not anchor and main.terminalState then
		anchor = main.terminalState.terminalAnchor
	end
	local sessionLock = mainOpen and anchor ~= nil
	local accessOk, mode, terminal, accessReason
	if blockedOpen and not pending then
		accessOk, mode, terminal, accessReason = GlobalStorageSiK.TerminalAccess.evaluateClientOpen(player, networkId)
	else
		accessOk, mode, terminal, accessReason = GlobalStorageSiK.TerminalAccess.evaluate(
			player, networkId, anchor, { sessionLock = sessionLock, strictDistance = true }
		)
	end

	if mainOpen and not accessOk then
		state.access = "blocked"
		main._gsAccessState = "blocked"
		denyOpenUi(accessReason or "terminal_out_of_range", playerNum, main, networkId)
		return
	end

	if blockedOpen and not pending and accessOk then
		if now >= state.nextProbe then
			state.nextProbe = now + PROBE_INTERVAL_MS
			if terminal and GlobalStorageSiK.TerminalAccess.setSessionAnchor then
				local nid = terminal.networkId or networkId
				GlobalStorageSiK.TerminalAccess.setSessionAnchor(player, terminal, mode, nid)
			end
			if GlobalStorageSiK.TerminalUI and GlobalStorageSiK.TerminalUI.requestOpenAt then
				GlobalStorageSiK.TerminalUI.requestOpenAt(player, nil)
			end
		end
	end
end

function GlobalStorageSiK.TerminalAccessGuard.clear(playerNum)
	if playerNum == nil then states = {} else states[playerNum] = nil end
end

function GlobalStorageSiK.TerminalAccessGuard.invalidate(playerNum)
	for n=0,3 do
		if playerNum == nil or n == playerNum then
			if states[n] then
				states[n].dirty = true
				states[n].probeRetries = 0
				states[n].probeExhausted = false
			end
		end
	end
end

--- Correlate a response before it can touch catalogs, UI or another session.
function GlobalStorageSiK.TerminalAccessGuard.acceptResponse(payload, allowed)
	if not payload then return true end
	local playerNum = tonumber(payload.playerNum)
	local state = playerNum and states[playerNum]
	if not payload.accessProbeId then
		if state then
			if allowed and state.access ~= "in_range" and payload.openUi ~= true then return false end
			state.pendingProbe = nil
			state.probeRetries = 0
			state.probeExhausted = false
			if allowed and payload.openUi == true then state.confirmedAccess = payload end
			state.access = allowed and "in_range" or "blocked"
			state.ui._gsAccessState = state.access
		end
		return true
	end
	if not state or state.pendingProbe ~= payload.accessProbeId
		or state.player ~= resolvePlayer(playerNum) or state.ui ~= viewForPlayer(playerNum)
		or (state.ui.isVisible and not state.ui:isVisible()) then return false end
	local openSeq = GlobalStorageSiK.Client and GlobalStorageSiK.Client.terminalOpenSeqByPlayer
		and GlobalStorageSiK.Client.terminalOpenSeqByPlayer[playerNum] or 0
	if state.probeOpenSeq ~= openSeq
		or state.probeNetworkId ~= resolveNetworkId(playerNum, state.ui)
		or (payload.networkId ~= nil and payload.networkId ~= state.probeNetworkId) then return false end
	state.pendingProbe = nil
	state.probeRetries = 0
	state.probeExhausted = false
	-- A valid ACK describes the server check, which may precede movement on
	-- this client. Recheck the captured anchor before restoring new work.
	local access = GlobalStorageSiK.TerminalAccess
	if allowed and access and access.evaluateConfirmedAnchor
		and not access.evaluateConfirmedAnchor(state.player, payload.terminalAnchor,
			payload.confirmedProximityRange, payload.confirmedWirelessRange) then
		state.access = "revoking"
		state.ui._gsAccessState = "revoking"
		state.dirty = true
		return false
	end
	if allowed then state.confirmedAccess = payload end
	state.access = allowed and "in_range" or "blocked"
	state.ui._gsAccessState = state.access
	return true
end

function GlobalStorageSiK.TerminalAccessGuard.canOperate(player)
	local playerNum = player and player.getPlayerNum and player:getPlayerNum()
	local state = playerNum and states[playerNum]
	return not state or state.access == "in_range"
end

function GlobalStorageSiK.TerminalAccessGuard.isTransitioning(player)
	local playerNum = player and player.getPlayerNum and player:getPlayerNum()
	local state = playerNum and states[playerNum]
	if state and (state.player ~= player or state.ui ~= viewForPlayer(playerNum)
		or (state.ui.isVisible and not state.ui:isVisible())) then return false end
	return state and (state.access == "revoking" or state.access == "revalidating") or false
end

function GlobalStorageSiK.TerminalAccessGuard.onTick(player)
	local now = getTimestampMs and getTimestampMs() or 0
	local api = GlobalStorageSiK.TerminalUI
	local pendingOpen = api and api.expirePendingOpens and api.expirePendingOpens(now)
	local catalogPending = GlobalStorageSiK.CatalogClient and GlobalStorageSiK.CatalogClient.update(now)
	if now < lastClock then
		for n=0,3 do
			if states[n] then
				states[n].nextCheck = now + CHECK_INTERVAL_MS
				states[n].nextProbe = now + PROBE_INTERVAL_MS
				states[n].nextSafetyCheck = now + ACCESS_FALLBACK_MS
				if states[n].probeExhausted then
					states[n].nextRecoveryProbe = now + RECOVERY_INTERVAL_MS
				end
				if states[n].pendingProbe then states[n].probeDeadline = now + 1500 end
			end
		end
	end
	lastClock = now
	if (type(player) == "table" or type(player) == "userdata") and player.getPlayerNum then
		local playerNum = player:getPlayerNum()
		if playerNum >= 0 and playerNum <= 3 then checkPlayer(playerNum, now) end
	else for n=0,3 do checkPlayer(n, now) end end
	local visible = false
	for n=0,3 do
		local view = viewForPlayer(n)
		if view and (not view.isVisible or view:isVisible()) then visible = true end
	end
	if not visible and not pendingOpen and not catalogPending and detach then detach() end
end

local function inventoryChanged(source)
	if source then
		for n=0,3 do
			if resolvePlayer(n) == source then
				GlobalStorageSiK.TerminalAccessGuard.invalidate(n)
				return
			end
		end
	end
	GlobalStorageSiK.TerminalAccessGuard.invalidate()
end

local function clothingChanged(player)
	GlobalStorageSiK.TerminalAccessGuard.invalidate(player and player:getPlayerNum() or nil)
end

detach = function()
	local guard = GlobalStorageSiK.TerminalAccessGuard
	if not guard._installed then return end
	local updateEvent = Events.OnPlayerUpdate or Events.OnTick
	updateEvent.Remove(guard.onTick)
	if Events.OnContainerUpdate then Events.OnContainerUpdate.Remove(inventoryChanged) end
	if Events.OnClothingUpdated then Events.OnClothingUpdated.Remove(clothingChanged) end
	guard._installed = false
	states = {}
end

function GlobalStorageSiK.TerminalAccessGuard.ensure()
	if GlobalStorageSiK.TerminalAccessGuard._installed then
		return
	end
	if not Events or not (Events.OnPlayerUpdate or Events.OnTick) then
		return
	end
	GlobalStorageSiK.TerminalAccessGuard._installed = true
	local updateEvent = Events.OnPlayerUpdate or Events.OnTick
	updateEvent.Add(GlobalStorageSiK.TerminalAccessGuard.onTick)
	if Events.OnContainerUpdate then Events.OnContainerUpdate.Add(inventoryChanged) end
	if Events.OnClothingUpdated then Events.OnClothingUpdated.Add(clothingChanged) end
end
