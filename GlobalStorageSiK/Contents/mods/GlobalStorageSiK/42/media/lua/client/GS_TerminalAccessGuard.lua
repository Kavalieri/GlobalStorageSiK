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

local CHECK_TICKS = 12
local MP_PROBE_BLOCKED = 18
local MP_PROBE_MAIN = 36

---@return string
local function resolveNetworkId()
	local ui = GlobalStorageSiK.TerminalUI and GlobalStorageSiK.TerminalUI.instance
	local state = ui and ui.terminalState
	if state and state.networkId then
		return state.networkId
	end
	if GlobalStorageSiK.Client and GlobalStorageSiK.Client.cachedTerminalState and GlobalStorageSiK.Client.cachedTerminalState.networkId then
		return GlobalStorageSiK.Client.cachedTerminalState.networkId
	end
	if GlobalStorageSiK.Client and GlobalStorageSiK.Client.activeNetworkId then
		return GlobalStorageSiK.Client.activeNetworkId
	end
	if GlobalStorageSiK.Network and GlobalStorageSiK.Network.getDefaultNetworkId then
		return GlobalStorageSiK.Network.getDefaultNetworkId()
	end
	return nil
end

---@return IsoPlayer|nil
local function resolvePlayer()
	if GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer then
		return GlobalStorageSiK.NetClient.getPlayer()
	end
	if getPlayer then
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
		GlobalStorageSiK.TransferQueue.clear()
	end
	if GlobalStorageSiK.Client then
		GlobalStorageSiK.Client.cachedTerminalState = nil
		GlobalStorageSiK.Client.pendingTerminalOpen = false
	end
end

--- Cierra terminal principal y muestra modo bloqueado en la misma ventana.
---@param reason string|nil
local function denyOpenUi(reason)
	local main = GlobalStorageSiK.TerminalUI and GlobalStorageSiK.TerminalUI.instance
	local px, py, pw, ph
	if main and (not main.isVisible or main:isVisible()) then
		px, py = main:getX(), main:getY()
		pw, ph = main:getWidth(), main:getHeight()
	end
	clearAccessState(resolvePlayer())
	if GlobalStorageSiK.TerminalUI and GlobalStorageSiK.TerminalUI.showBlocked then
		GlobalStorageSiK.TerminalUI.showBlocked(reason, { x = px, y = py, w = pw, h = ph })
	end
end

--- Pide al servidor validar acceso sin reescanear (MP).
---@param reopen boolean|nil true si la ventana bloqueada intenta recuperar acceso
local function probeServerAccess(reopen)
	if not GlobalStorageSiK.NetClient or not GlobalStorageSiK.NetClient.sendCommand then
		return
	end
	local payload = {}
	local networkId = resolveNetworkId()
	if networkId then
		payload.networkId = networkId
	end
	if reopen then
		payload.reopen = true
		if GlobalStorageSiK.Client and GlobalStorageSiK.Client.terminalOpenSeq then
			payload.openSeq = GlobalStorageSiK.Client.terminalOpenSeq
		end
	end
	local player = resolvePlayer()
	payload = GlobalStorageSiK.TerminalAccess.enrichCommandPayload(player, payload, networkId)
	GlobalStorageSiK.NetClient.sendCommand("pingTerminalAccess", payload)
end

function GlobalStorageSiK.TerminalAccessGuard.onTick()
	if not accessRequired() then
		return
	end

	local main = GlobalStorageSiK.TerminalUI and GlobalStorageSiK.TerminalUI.instance
	local isVis = main ~= nil and (not main.isVisible or main:isVisible())
	local blockedOpen = isVis and main.accessMode == "blocked"
	local mainOpen = isVis and main.accessMode ~= "blocked"
	if not mainOpen and not blockedOpen then
		return
	end

	local player = resolvePlayer()
	if not player or not GlobalStorageSiK.TerminalAccess then
		return
	end

	local trustServer = GlobalStorageSiK.TerminalAccess.trustServerForOpen()
	local pending = GlobalStorageSiK.Client and GlobalStorageSiK.Client.pendingTerminalOpen

	if trustServer then
		if mainOpen and not pending then
			main._serverAccessProbe = (main._serverAccessProbe or 0) + 1
			if main._serverAccessProbe % MP_PROBE_MAIN == 0 then
				probeServerAccess()
			end
		end
		if blockedOpen and not pending then
			main._openProbeTick = (main._openProbeTick or 0) + 1
			if main._openProbeTick % MP_PROBE_BLOCKED == 0 then
				probeServerAccess(true)
			end
		end
		return
	end

	local networkId = resolveNetworkId()
	local anchor = GlobalStorageSiK.TerminalAccess.getSessionAnchor(player)
	if not anchor and GlobalStorageSiK.Client and GlobalStorageSiK.Client.cachedTerminalState then
		anchor = GlobalStorageSiK.Client.cachedTerminalState.terminalAnchor
	end
	local sessionLock = mainOpen and anchor ~= nil
	local accessOk, mode, terminal, accessReason
	if blockedOpen and not pending then
		accessOk, mode, terminal, accessReason = GlobalStorageSiK.TerminalAccess.evaluateClientOpen(player, networkId)
	else
		accessOk, mode, terminal, accessReason = GlobalStorageSiK.TerminalAccess.evaluate(
			player, networkId, anchor, { sessionLock = sessionLock }
		)
	end

	if mainOpen and not accessOk then
		denyOpenUi(accessReason or "terminal_out_of_range")
		return
	end

	if blockedOpen and not pending and accessOk then
		main._openProbeTick = (main._openProbeTick or 0) + 1
		if main._openProbeTick % MP_PROBE_BLOCKED == 0 then
			if terminal and GlobalStorageSiK.TerminalAccess.setSessionAnchor then
				local nid = terminal.networkId or networkId
				GlobalStorageSiK.TerminalAccess.setSessionAnchor(player, terminal, mode, nid)
			end
			if GlobalStorageSiK.TerminalUI and GlobalStorageSiK.TerminalUI.requestOpen then
				GlobalStorageSiK.TerminalUI.requestOpen()
			end
		end
	elseif blockedOpen then
		main._openProbeTick = 0
	end
end

function GlobalStorageSiK.TerminalAccessGuard.ensure()
	if GlobalStorageSiK.TerminalAccessGuard._installed then
		return
	end
	GlobalStorageSiK.TerminalAccessGuard._installed = true
	GlobalStorageSiK.TerminalAccessGuard._tick = 0
	if not Events or not Events.OnTick then
		return
	end
	Events.OnTick.Add(function()
		GlobalStorageSiK.TerminalAccessGuard._tick = (GlobalStorageSiK.TerminalAccessGuard._tick or 0) + 1
		if GlobalStorageSiK.TerminalAccessGuard._tick % CHECK_TICKS ~= 0 then
			return
		end
		GlobalStorageSiK.TerminalAccessGuard.onTick()
	end)
end
