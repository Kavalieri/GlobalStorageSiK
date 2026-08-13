--[[
	GlobalStorageSiK - API pública del terminal (show / requestOpen)
	Autor: SiK
	Fecha: 2025-06-24
	Descripción: Evita referencias nil por orden de carga entre módulos cliente.
]]

require "GS_Sandbox"
require "GS_Network"
require "GS_TerminalAccess"
require "GS_PlayerUtils"
require "GS_UIDebug"

GlobalStorageSiK.TerminalUI = GlobalStorageSiK.TerminalUI or {}

local DEFER_REFRESH_ITEM_COUNT = 150

--- Cierra la ventana principal si existe (modo completo).
local function closeMainTerminal()
	local ui = GlobalStorageSiK.TerminalUI and GlobalStorageSiK.TerminalUI.instance
	if not ui or not ui.onClose then
		return
	end
	if ui.accessMode == "blocked" then
		return
	end
	pcall(function()
		ui:onClose()
	end)
end

--- Construye payload para ventana bloqueada (cliente).
---@param player IsoPlayer|nil
---@param reason string|nil
---@return table
local function buildBlockedPayload(player, reason)
	local payload = {
		reason = reason,
		proximityRange = GlobalStorageSiK.Sandbox.getTerminalProximityRange(),
		wirelessRange = GlobalStorageSiK.Sandbox.getWirelessRange(),
	}
	if player and GlobalStorageSiK.TerminalRecipes then
		local ok, enriched = pcall(GlobalStorageSiK.TerminalRecipes.serializeForClient, player)
		if ok and enriched then
			enriched.reason = reason or enriched.reason
			enriched.proximityRange = payload.proximityRange
			enriched.wirelessRange = payload.wirelessRange
			return enriched
		end
	end
	return payload
end

--- Aplica estado al panel; difiere refrescos muy grandes un tick para evitar bloqueos.
---@param ui GS_TerminalUI
---@param state table|nil
local function applyTerminalState(ui, state)
	if not ui or not ui.refreshFromState then
		return
	end
	local itemCount = state and state.items and #state.items or 0
	local function runRefresh()
		local ok, err = pcall(ui.refreshFromState, ui, state)
		if not ok then
			print("[GlobalStorageSiK] refreshFromState failed: " .. tostring(err))
		end
	end
	if itemCount > DEFER_REFRESH_ITEM_COUNT and Events and Events.OnTick then
		local function deferOnce()
			Events.OnTick.Remove(deferOnce)
			if GlobalStorageSiK.TerminalUI.instance == ui then
				runRefresh()
			end
		end
		Events.OnTick.Add(deferOnce)
	else
		runRefresh()
	end
end

--- Abre o refresca la ventana principal del terminal.
---@param state table|nil
function GlobalStorageSiK.TerminalUI.show(state)
	if GlobalStorageSiK.TerminalAccessGuard and GlobalStorageSiK.TerminalAccessGuard.ensure then
		GlobalStorageSiK.TerminalAccessGuard.ensure()
	end
	local player = GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer() or getPlayer()
	local networkId = state and state.networkId
		or (GlobalStorageSiK.Client and GlobalStorageSiK.Client.activeNetworkId)
		or (GlobalStorageSiK.Network and GlobalStorageSiK.Network.getDefaultNetworkId())
	local needAccess = GlobalStorageSiK.Sandbox
		and GlobalStorageSiK.Sandbox.requireTerminalAccess
		and GlobalStorageSiK.Sandbox.requireTerminalAccess()
	local trustServer = GlobalStorageSiK.TerminalAccess
		and GlobalStorageSiK.TerminalAccess.trustServerForOpen
		and GlobalStorageSiK.TerminalAccess.trustServerForOpen()
	local serverConfirmed = state and state.openUi == true
		and state.terminalAnchor and state.accessMode
	if needAccess and player and GlobalStorageSiK.TerminalAccess.validateServerOpen
		and not (trustServer and serverConfirmed) then
		if GlobalStorageSiK.UIDebug then
			GlobalStorageSiK.UIDebug.log("OPEN", "revalidando en cliente pese a openUi=%s (trustServer=%s serverConfirmed=%s)",
				tostring(state and state.openUi), tostring(trustServer), tostring(serverConfirmed))
		end
		local accessOk, _, _, accessReason = GlobalStorageSiK.TerminalAccess.validateServerOpen(player, networkId, state)
		if not accessOk then
			GlobalStorageSiK.TerminalUI.showBlocked(accessReason)
			return
		end
	end
	local ui = GlobalStorageSiK.TerminalUI.instance
	GlobalStorageSiK.UIDebug.log("OPEN", "show() reuse=%s items=%d nid=%s",
		tostring(ui ~= nil), (state and state.items and #state.items) or 0, tostring(networkId))
	-- Singleton estricto: si ya existe instancia, siempre reutilizar (no crear segunda ventana).
	if ui then
		if GlobalStorageSiK.TerminalTabs and GlobalStorageSiK.TerminalTabs.applyAccessMode then
			GlobalStorageSiK.TerminalTabs.applyAccessMode(ui, "full", nil)
		end
		applyTerminalState(ui, state)
		ui:setVisible(true)
		ui:bringToTop()
		if GlobalStorageSiK.TerminalBlockedUI and GlobalStorageSiK.TerminalBlockedUI.instance == ui then
			GlobalStorageSiK.TerminalBlockedUI.instance = nil
		end
		return
	end

	if not GS_TerminalUI then
		print("[GlobalStorageSiK] GS_TerminalUI class missing")
		return
	end

	local sw = getCore():getScreenWidth()
	local sh = getCore():getScreenHeight()
	local w = math.min(1200, math.max(900, math.floor(sw * 0.85)))
	local h = math.min(1000, math.max(720, math.floor(sh * 0.90)))
	local x = (sw - w) / 2
	local y = (sh - h) / 2
	ui = GS_TerminalUI:new(x, y, w, h)
	ui.terminalState = state or {}
	ui:initialise()
	ui:addToUIManager()
	GlobalStorageSiK.TerminalUI.instance = ui
	GlobalStorageSiK.UIDebug.log("OPEN", "ventana CREADA x=%d y=%d w=%d h=%d", x, y, w, h)
	if GlobalStorageSiK.TerminalTabs and GlobalStorageSiK.TerminalTabs.applyAccessMode then
		GlobalStorageSiK.TerminalTabs.applyAccessMode(ui, "full", nil)
	end
	applyTerminalState(ui, state)
end

--- Muestra ventana bloqueada por acceso denegado (sin round-trip al servidor).
---@param reason string|nil
---@param rect table|nil { x, y, w, h }
function GlobalStorageSiK.TerminalUI.showBlocked(reason, rect)
	if GlobalStorageSiK.TerminalAccessGuard and GlobalStorageSiK.TerminalAccessGuard.ensure then
		GlobalStorageSiK.TerminalAccessGuard.ensure()
	end
	local player = GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer() or getPlayer()
	local payload = buildBlockedPayload(player, reason)
	local rx = rect and rect.x
	local ry = rect and rect.y
	local rw = rect and rect.w
	local rh = rect and rect.h
	local ui = GlobalStorageSiK.TerminalUI and GlobalStorageSiK.TerminalUI.instance
	-- Singleton estricto: si ya existe instancia, siempre reutilizar.
	if ui then
		if GlobalStorageSiK.TerminalTabs and GlobalStorageSiK.TerminalTabs.applyAccessMode then
			GlobalStorageSiK.TerminalTabs.applyAccessMode(ui, "blocked", payload)
		end
		ui:setVisible(true)
		ui:bringToTop()
		GlobalStorageSiK.TerminalBlockedUI.instance = ui
		return
	end
	if GlobalStorageSiK.TerminalBlockedUI and GlobalStorageSiK.TerminalBlockedUI.showFromMain then
		GlobalStorageSiK.TerminalBlockedUI.showFromMain(payload, rx, ry, rw, rh)
	elseif GlobalStorageSiK.TerminalBlockedUI and GlobalStorageSiK.TerminalBlockedUI.show then
		GlobalStorageSiK.TerminalBlockedUI.show(payload)
	end
end

--- Solicita abrir el terminal: validación en cliente primero; en MP el servidor confirma.
function GlobalStorageSiK.TerminalUI.requestOpen()
	GlobalStorageSiK.TerminalUI.requestOpenAt(nil, nil)
end

--- Abre el terminal vinculado a un objeto concreto (menú contextual).
---@param playerArg IsoPlayer|number|nil
---@param terminalObj IsoObject|nil
function GlobalStorageSiK.TerminalUI.requestOpenAt(playerArg, terminalObj)
	if GlobalStorageSiK.TerminalAccessGuard and GlobalStorageSiK.TerminalAccessGuard.ensure then
		GlobalStorageSiK.TerminalAccessGuard.ensure()
	end
	local player = GlobalStorageSiK.PlayerUtils and GlobalStorageSiK.PlayerUtils.resolve(playerArg)
		or GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer()
		or getPlayer()
	if not player or not GlobalStorageSiK.TerminalAccess then
		return
	end

	local hint = nil
	local openNetworkId = nil
	if terminalObj and GlobalStorageSiK.TerminalAccess.buildHintFromObject then
		hint = GlobalStorageSiK.TerminalAccess.buildHintFromObject(player, terminalObj)
		openNetworkId = hint and hint.networkId
	end

	if GlobalStorageSiK.TerminalAccess.trustServerForOpen() then
		if GlobalStorageSiK.Client then
			GlobalStorageSiK.Client.pendingTerminalOpen = true
			GlobalStorageSiK.Client.terminalOpenSeq = (GlobalStorageSiK.Client.terminalOpenSeq or 0) + 1
		end
		if GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.sendCommand then
			local payload = {
				openSeq = GlobalStorageSiK.Client and GlobalStorageSiK.Client.terminalOpenSeq or nil,
				terminalHint = hint,
				networkId = openNetworkId,
			}
			GlobalStorageSiK.NetClient.sendCommand("openTerminal", payload)
		end
		return
	end

	if not GlobalStorageSiK.TerminalAccess.evaluateClientOpen then
		return
	end

	local accessOk, mode, terminal, accessReason
	if hint and hint.x then
		accessOk, mode, terminal, accessReason = GlobalStorageSiK.TerminalAccess.evaluate(
			player, openNetworkId, hint, { ignoreSession = true, strictDistance = true }
		)
	else
		accessOk, mode, terminal, accessReason = GlobalStorageSiK.TerminalAccess.evaluateClientOpen(player, openNetworkId)
	end
	if GlobalStorageSiK.Debug and GlobalStorageSiK.Debug.log then
		GlobalStorageSiK.Debug.log("TerminalUI", "requestOpenAt", string.format(
			"ok=%s mode=%s reason=%s net=%s",
			tostring(accessOk), tostring(mode), tostring(accessReason),
			terminal and tostring(terminal.networkId) or tostring(openNetworkId)
		))
	end
	if not accessOk then
		if GlobalStorageSiK.Client then
			GlobalStorageSiK.Client.pendingTerminalOpen = false
		end
		GlobalStorageSiK.TerminalUI.showBlocked(accessReason)
		return
	end

	if terminal then
		openNetworkId = terminal.networkId or openNetworkId
		if not openNetworkId and terminal.x and GlobalStorageSiK.Network and GlobalStorageSiK.Network.findNetworkIdAtTerminal then
			openNetworkId = GlobalStorageSiK.Network.findNetworkIdAtTerminal(terminal.x, terminal.y, terminal.z or 0)
			if openNetworkId then
				terminal.networkId = openNetworkId
			end
		end
		if GlobalStorageSiK.TerminalAccess.setSessionAnchor then
			GlobalStorageSiK.TerminalAccess.setSessionAnchor(player, terminal, mode, openNetworkId)
		end
	end

	if GlobalStorageSiK.Client then
		GlobalStorageSiK.Client.pendingTerminalOpen = true
		GlobalStorageSiK.Client.terminalOpenSeq = (GlobalStorageSiK.Client.terminalOpenSeq or 0) + 1
	end
	if GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.sendCommand then
		local payload = GlobalStorageSiK.TerminalAccess.enrichCommandPayload(player, {
			openSeq = GlobalStorageSiK.Client and GlobalStorageSiK.Client.terminalOpenSeq or nil,
			networkId = openNetworkId,
			terminalHint = hint or terminal,
		}, openNetworkId)
		GlobalStorageSiK.NetClient.sendCommand("openTerminal", payload)
	end
end
