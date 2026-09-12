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
require "GS_Log"

local UI = require "GS_UI_Framework"
local Loading = require "GS_TerminalLoading"

GlobalStorageSiK.TerminalUI = GlobalStorageSiK.TerminalUI or {}
GlobalStorageSiK.TerminalUI.instances = GlobalStorageSiK.TerminalUI.instances or {}

local DEFER_REFRESH_ITEM_COUNT = 150
local TERMINAL_GEOMETRY_KEY = "terminal-shell"
local TERMINAL_GEOMETRY_VERSION = 2
local OPEN_TIMEOUT_MS = 10000
local pendingOpenDeadlines = {}

function GlobalStorageSiK.TerminalUI.getInstanceForPlayer(playerNum)
	return GlobalStorageSiK.TerminalUI.instances[tonumber(playerNum) or 0]
end

function GlobalStorageSiK.TerminalUI.setInstanceForPlayer(playerNum, ui)
	playerNum = tonumber(playerNum) or 0
	GlobalStorageSiK.TerminalUI.instances[playerNum] = ui
	if ui then GlobalStorageSiK.TerminalUI.instance = ui end
	return ui
end

function GlobalStorageSiK.TerminalUI.removeInstanceForPlayer(playerNum, expected)
	playerNum = tonumber(playerNum) or 0
	local current = GlobalStorageSiK.TerminalUI.instances[playerNum]
	if expected and current ~= expected then return false end
	GlobalStorageSiK.TerminalUI.instances[playerNum] = nil
	if GlobalStorageSiK.TerminalUI.instance == current then
		GlobalStorageSiK.TerminalUI.instance = nil
		local keys = {}
		for key in pairs(GlobalStorageSiK.TerminalUI.instances) do keys[#keys + 1] = key end
		table.sort(keys)
		if #keys > 0 then
			GlobalStorageSiK.TerminalUI.instance = GlobalStorageSiK.TerminalUI.instances[keys[1]]
		end
	end
	return true
end

local function resolveShellRect(player)
	local playerNum = player and player.getPlayerNum and player:getPlayerNum() or 0
	local viewport = UI.Viewport.resolve(playerNum)
	local profile = "terminal"
	local rect = UI.Window.resolveBounds({
		playerNum = playerNum,
		profile = profile,
		geometryKey = TERMINAL_GEOMETRY_KEY,
		geometryVersion = TERMINAL_GEOMETRY_VERSION,
	})
	-- resolveBounds owns only safe default geometry. GS_TerminalUI applies this
	-- same key through Window.apply, the single owner of saved geometry.
	rect.profile = profile
	rect.geometryVersion = TERMINAL_GEOMETRY_VERSION
	return rect
end

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
		playerNum = player and player.getPlayerNum and player:getPlayerNum() or 0,
		reason = reason,
		proximityRange = GlobalStorageSiK.Sandbox.getTerminalProximityRange(),
		wirelessRange = GlobalStorageSiK.Sandbox.getWirelessRange(),
	}
	if player and GlobalStorageSiK.TerminalRecipes then
		local ok, enriched = pcall(GlobalStorageSiK.TerminalRecipes.serializeForClient, player)
		if ok and enriched then
			enriched.playerNum = payload.playerNum
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
local function applyTerminalState(ui, state, forceDeferred)
	if not ui or not ui.refreshFromState then
		return
	end
	local itemCount = state and state.items and #state.items or 0
	ui._gsPendingTerminalState = state
	ui._gsPendingTerminalLoad = ui._gsCatalogLoad
	-- A queued callback owns the latest state even if a newer catalog is small.
	-- Running it immediately would leave the old callback refreshing nil next tick.
	if ui._gsTerminalRefreshQueued then return end
	local function runRefresh()
		local startedMs = GlobalStorageSiK.UIDebug and GlobalStorageSiK.UIDebug.enabled()
			and type(getTimestampMs) == "function" and getTimestampMs() or nil
		local pendingState = ui._gsPendingTerminalState
		local load = ui._gsPendingTerminalLoad
		ui._gsPendingTerminalState = nil
		ui._gsPendingTerminalLoad = nil
		-- A newer fragment batch or access transition supersedes this refresh.
		if load ~= ui._gsCatalogLoad or not pendingState then return end
		-- Restore previous widget availability before the authoritative refresh
		-- recomputes permissions. Input remains fenced throughout this callback.
		Loading.unlock(ui)
		if ui._gsCatalogBodyHidden then
			local panel = ui.tabPanels and ui.tabPanels[ui.activeTabKey or "items"]
			if panel and panel.setVisible then panel:setVisible(true) end
			ui._gsCatalogBodyHidden = nil
		end
		local ok, err = pcall(ui.refreshFromState, ui, pendingState)
		if not ok then
			GlobalStorageSiK.Log.error("TerminalUI", "refreshFromState failed", err)
			Loading.lock(ui)
			ui:onClose()
			GlobalStorageSiK.TerminalUI.showCatalogFailure(ui.playerNum, "catalog_apply", true)
		else
			Loading.finish(ui, load)
			local client = GlobalStorageSiK.Client
			if pendingState.openUi and client and client.pendingInitialTab then
				local tab = client.pendingInitialTab
				client.pendingInitialTab = nil
				GlobalStorageSiK.TerminalTabs.activate(ui, tab)
			end
		end
		if startedMs then
			GlobalStorageSiK.UIDebug.action("state_refresh",
				"durationMs=" .. tostring(getTimestampMs() - startedMs)
					.. " items=" .. tostring(pendingState and pendingState.items and #pendingState.items or 0)
					.. " deferred=" .. tostring(forceDeferred == true))
		end
	end
	if (forceDeferred or itemCount > DEFER_REFRESH_ITEM_COUNT) and Events and Events.OnTick then
		ui._gsTerminalRefreshQueued = true
		local function deferOnce()
			Events.OnTick.Remove(deferOnce)
			ui._gsTerminalRefreshQueued = nil
			if GlobalStorageSiK.TerminalUI.getInstanceForPlayer(ui.playerNum) == ui then
				runRefresh()
			else
				ui._gsPendingTerminalState = nil
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
	local showStartedMs = GlobalStorageSiK.UIDebug and GlobalStorageSiK.UIDebug.enabled()
		and type(getTimestampMs) == "function" and getTimestampMs() or nil
	if GlobalStorageSiK.TerminalAccessGuard and GlobalStorageSiK.TerminalAccessGuard.ensure then
		GlobalStorageSiK.TerminalAccessGuard.ensure()
	end
	local playerNum = tonumber(state and state.playerNum) or 0
	local player = GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer(playerNum)
		or (playerNum == 0 and getPlayer and getPlayer() or nil)
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
	local ui = GlobalStorageSiK.TerminalUI.getInstanceForPlayer(playerNum)
	local stateUpdate = ui ~= nil and state and state.openUi ~= true
	if needAccess and player and GlobalStorageSiK.TerminalAccess.validateServerOpen
		and not stateUpdate and not (trustServer and serverConfirmed) then
		if GlobalStorageSiK.UIDebug then
			GlobalStorageSiK.UIDebug.log("OPEN", "revalidando en cliente pese a openUi=%s (trustServer=%s serverConfirmed=%s)",
				tostring(state and state.openUi), tostring(trustServer), tostring(serverConfirmed))
		end
		local accessOk, _, _, accessReason = GlobalStorageSiK.TerminalAccess.validateServerOpen(player, networkId, state)
		if not accessOk then
			GlobalStorageSiK.TerminalUI.showBlocked({
				playerNum = playerNum, reason = accessReason,
			})
			return
		end
	end
	GlobalStorageSiK.UIDebug.log("OPEN", "show() reuse=%s items=%d nid=%s",
		tostring(ui ~= nil), (state and state.items and #state.items) or 0, tostring(networkId))
	-- Singleton estricto: si ya existe instancia, siempre reutilizar (no crear segunda ventana).
	if ui then
		local wasVisible = not ui.getIsVisible or ui:getIsVisible() ~= false
		GlobalStorageSiK.TerminalUI.instance = ui
		if GlobalStorageSiK.TerminalTabs and GlobalStorageSiK.TerminalTabs.applyAccessMode then
			GlobalStorageSiK.TerminalTabs.applyAccessMode(ui, "full", nil)
		end
		applyTerminalState(ui, state)
		ui:setVisible(true)
		-- Los estados periódicos refrescan datos, no el z-order. Solo una apertura
		-- explícita o la reaparición de una ventana oculta puede elevar el shell;
		-- Modal.raiseOwner conserva después cualquier modal hijo por encima.
		if not wasVisible or (state and state.openUi == true) then
			UI.Modal.raiseOwner(ui)
		end
		if GlobalStorageSiK.TerminalBlockedUI and GlobalStorageSiK.TerminalBlockedUI.instance == ui then
			GlobalStorageSiK.TerminalBlockedUI.instance = nil
		end
		return
	end

	if not GS_TerminalUI then
		GlobalStorageSiK.Log.error("TerminalUI", "GS_TerminalUI class missing")
		return
	end

	local rect = resolveShellRect(player)
	ui = GS_TerminalUI:new(rect.x, rect.y, rect.w, rect.h, playerNum)
	ui._sikWindowProfile = rect.profile
	ui.terminalState = state or {}
	ui:initialise()
	ui:show()
	GlobalStorageSiK.TerminalUI.setInstanceForPlayer(playerNum, ui)
	GlobalStorageSiK.UIDebug.log("OPEN", "ventana CREADA x=%d y=%d w=%d h=%d",
		rect.x, rect.y, rect.w, rect.h)
	if showStartedMs then
		GlobalStorageSiK.UIDebug.action("shell_visible",
			"durationMs=" .. tostring(getTimestampMs() - showStartedMs)
				.. " contentDeferred=true")
	end
	if GlobalStorageSiK.TerminalTabs and GlobalStorageSiK.TerminalTabs.applyAccessMode then
		GlobalStorageSiK.TerminalTabs.applyAccessMode(ui, "full", nil)
	end
	-- El shell ya esta en UIManager: construir/refrescar el contenido activo en
	-- el siguiente tick permite que la ventana se pinte antes del trabajo pesado
	-- y coalesce cualquier snapshot que llegue durante esa apertura.
	applyTerminalState(ui, state, true)
end

--- Muestra ventana bloqueada por acceso denegado (sin round-trip al servidor).
--- BUG REAL confirmado (2026-08-25, investigacion del cuelgue de cliente al
--- morir y reclamar): cuando el servidor manda "terminalBlocked" con la
--- ventana YA abierta, el handler de GS_Client.lua llamaba aqui pasando SOLO
--- el motivo (reason) - esta funcion reconstruia entonces su PROPIO payload
--- via buildBlockedPayload (incompleto: sin canClaimOwnership/networkId/
--- claimTier, nunca los rellena) y forzaba un primer rebuild completo del
--- panel con esos datos a medias, para que el propio handler, un par de
--- lineas despues, llamara OTRA VEZ a TerminalBlockedUI.refresh() con el
--- payload de verdad (completo) del servidor - forzando un SEGUNDO rebuild
--- completo inmediatamente detras. Cada respuesta periodica del servidor
--- (pingTerminalAccess, ver GS_TerminalAccessGuard.lua) reconstruia asi la
--- ventana dos veces en vez de una, ademas de mostrar brevemente el panel
--- sin el boton de reclamo aunque debiera tenerlo. payloadOrReason acepta
--- ahora una tabla ya completa (server payload real) ademas del string de
--- siempre (usado por el resto de llamantes, que no tienen un payload de
--- servidor a mano) - con tabla, se usa tal cual, sin reconstruir nada.
---@param payloadOrReason string|table|nil
---@param rect table|nil { x, y, w, h }
function GlobalStorageSiK.TerminalUI.showBlocked(payloadOrReason, rect)
	if GlobalStorageSiK.TerminalAccessGuard and GlobalStorageSiK.TerminalAccessGuard.ensure then
		GlobalStorageSiK.TerminalAccessGuard.ensure()
	end
	local payload
	if type(payloadOrReason) == "table" then
		payload = payloadOrReason
	else
		local player = GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer() or getPlayer()
		payload = buildBlockedPayload(player, payloadOrReason)
	end
	local playerNum = tonumber(payload and payload.playerNum) or 0
	local rx = rect and rect.x
	local ry = rect and rect.y
	local rw = rect and rect.w
	local rh = rect and rect.h
	local ui = GlobalStorageSiK.TerminalUI.getInstanceForPlayer(playerNum)
	if ui then
		Loading.unlock(ui)
		ui._gsCatalogLoad, ui._gsPendingTerminalState = nil, nil
	end
	-- Singleton estricto: si ya existe instancia, siempre reutilizar.
	if ui then
		local wasVisible = not ui.getIsVisible or ui:getIsVisible() ~= false
		GlobalStorageSiK.TerminalUI.instance = ui
		if GlobalStorageSiK.TerminalTabs and GlobalStorageSiK.TerminalTabs.applyAccessMode then
			GlobalStorageSiK.TerminalTabs.applyAccessMode(ui, "blocked", payload)
		end
		ui:setVisible(true)
		if not wasVisible or (payload and payload.openUi == true) then
			UI.Modal.raiseOwner(ui)
		end
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

--- Solicita al servidor la lista autoritativa de redes que pueden abrirse por
--- un proveedor inalambrico ahora mismo. Solo se conserva un callback acotado;
--- una nueva solicitud invalida la anterior y no instala listeners propios.
---@param callback function
---@return number|nil requestId
function GlobalStorageSiK.TerminalUI.requestRemoteNetworks(callback, playerArg)
	if type(callback) ~= "function" or not GlobalStorageSiK.NetClient then
		return nil
	end
	local seq = (GlobalStorageSiK.TerminalUI._remoteNetworkRequestSeq or 0) + 1
	if seq > 2147483647 then seq = 1 end
	local player = GlobalStorageSiK.PlayerUtils.resolve(playerArg)
	local playerNum = player and player.getPlayerNum and player:getPlayerNum() or 0
	GlobalStorageSiK.TerminalUI._remoteNetworkRequests =
		GlobalStorageSiK.TerminalUI._remoteNetworkRequests or {}
	GlobalStorageSiK.TerminalUI._remoteNetworkRequestSeq = seq
	GlobalStorageSiK.TerminalUI._remoteNetworkRequests[playerNum] = {
		requestId = seq,
		callback = callback,
	}
	local sent = GlobalStorageSiK.NetClient.sendCommand("getRemoteNetworkCandidates", {
		requestId = seq,
	}, player)
	if not sent then
		GlobalStorageSiK.TerminalUI._remoteNetworkRequests[playerNum] = nil
		return nil
	end
	return seq
end

function GlobalStorageSiK.TerminalUI.cancelRemoteNetworkRequest(requestId, playerArg)
	local player = GlobalStorageSiK.PlayerUtils.resolve(playerArg)
	local playerNum = player and player.getPlayerNum and player:getPlayerNum() or 0
	local requests = GlobalStorageSiK.TerminalUI._remoteNetworkRequests or {}
	local pending = requests[playerNum]
	if pending and (requestId == nil or requestId == pending.requestId) then
		requests[playerNum] = nil
	end
end

---@param payload table|nil
function GlobalStorageSiK.TerminalUI.onRemoteNetworkCandidates(payload)
	payload = payload or {}
	local playerNum = tonumber(payload.playerNum) or 0
	local requests = GlobalStorageSiK.TerminalUI._remoteNetworkRequests or {}
	local pending = requests[playerNum]
	if not pending or payload.requestId ~= pending.requestId then
		return
	end
	local callback = pending.callback
	requests[playerNum] = nil
	if type(callback) == "function" then
		local ok, err = pcall(callback, payload.networks or {}, payload.reason)
		if not ok then
			GlobalStorageSiK.Log.error("TerminalUI", "remote network callback", tostring(err))
		end
	end
end

local function nextOpenSequence(player)
	GlobalStorageSiK.Client.terminalOpenSeqByPlayer =
		GlobalStorageSiK.Client.terminalOpenSeqByPlayer or {}
	GlobalStorageSiK.Client.pendingTerminalOpenByPlayer =
		GlobalStorageSiK.Client.pendingTerminalOpenByPlayer or {}
	local playerNum = player and player.getPlayerNum and player:getPlayerNum() or 0
	if GlobalStorageSiK.CatalogFeedback then GlobalStorageSiK.CatalogFeedback.clear(playerNum) end
	local seq = (GlobalStorageSiK.Client.terminalOpenSeqByPlayer[playerNum] or 0) + 1
	if seq > 2147483647 then seq = 1 end
	GlobalStorageSiK.Client.terminalOpenSeqByPlayer[playerNum] = seq
	GlobalStorageSiK.Client.pendingTerminalOpenByPlayer[playerNum] = true
	if GlobalStorageSiK.CatalogClient then GlobalStorageSiK.CatalogClient.start(playerNum, seq) end
	local now = getTimestampMs and getTimestampMs() or 0
	pendingOpenDeadlines[playerNum] = {seq=seq, started=now, deadline=now + OPEN_TIMEOUT_MS, player=player}
	local guard = GlobalStorageSiK.TerminalAccessGuard
	if guard and guard.ensure then guard.ensure() end
	-- Compatibilidad temporal con consumidores del terminal físico que todavía
	-- consultan los escalares históricos. La correlación autoritativa usa siempre
	-- el mapa por playerNum y nunca deja que otro jugador local pise esta solicitud.
	if playerNum == 0 then
		GlobalStorageSiK.Client.terminalOpenSeq = seq
		GlobalStorageSiK.Client.pendingTerminalOpen = true
	end
	return playerNum, seq
end

local function clearPendingOpen(playerNum, seq)
	local pending = GlobalStorageSiK.Client.pendingTerminalOpenByPlayer or {}
	local sequences = GlobalStorageSiK.Client.terminalOpenSeqByPlayer or {}
	if seq == nil or sequences[playerNum] == seq then
		pending[playerNum] = nil
		pendingOpenDeadlines[playerNum] = nil
		if playerNum == 0 then GlobalStorageSiK.Client.pendingTerminalOpen = false end
	end
end

-- Recovery is a new opening intent, so a delayed close cannot cancel it.
function GlobalStorageSiK.TerminalUI.beginAccessRecovery(player)
	local _, sequence = nextOpenSequence(player)
	return sequence
end

local function sendPhysicalOpen(player, hint, networkId, enrich)
	local client = GlobalStorageSiK.Client
	local transport = GlobalStorageSiK.NetClient
	if not client or not transport or not transport.sendCommand then return nil end
	local old = GlobalStorageSiK.TerminalUI.getInstanceForPlayer(player:getPlayerNum())
	if old and old.onClose then old:onClose() end
	local playerNum, openSeq = nextOpenSequence(player)
	local payload = {openSeq=openSeq, terminalHint=hint, networkId=networkId}
	if enrich then
		payload = GlobalStorageSiK.TerminalAccess.enrichCommandPayload(player, payload, networkId)
	end
	if client.addInventoryCatalogToken then
		payload = client.addInventoryCatalogToken(payload, playerNum, networkId)
	end
	GlobalStorageSiK.TerminalUI.showPending(playerNum, openSeq)
	if not GlobalStorageSiK.TerminalUI.dispatchOpening(player, openSeq, function()
		return transport.sendCommand("openTerminal", payload, player)
	end) then
		clearPendingOpen(playerNum, openSeq)
		return nil
	end
	return openSeq
end

function GlobalStorageSiK.TerminalUI.cancelPendingOpen(playerArg)
	local player = GlobalStorageSiK.PlayerUtils.resolve(playerArg)
	if not player or not GlobalStorageSiK.Client then return end
	local playerNum, cancelledSeq = nextOpenSequence(player)
	clearPendingOpen(playerNum, cancelledSeq)
	if GlobalStorageSiK.CatalogClient then GlobalStorageSiK.CatalogClient.clear(playerNum) end
	local requests = GlobalStorageSiK.TerminalUI._remoteOpenRequests
	if requests then requests[playerNum] = nil end
end

function GlobalStorageSiK.TerminalUI.cancelOpenNetworkRequest(requestId, playerArg)
	local player = GlobalStorageSiK.PlayerUtils.resolve(playerArg)
	local playerNum = player and player.getPlayerNum and player:getPlayerNum() or 0
	local requests = GlobalStorageSiK.TerminalUI._remoteOpenRequests or {}
	local pending = requests[playerNum]
	if pending and (requestId == nil or requestId == pending.requestId) then
		local sequences = GlobalStorageSiK.Client.terminalOpenSeqByPlayer or {}
		if sequences[playerNum] == pending.requestId then
			local inFlight = GlobalStorageSiK.Client.pendingTerminalOpenByPlayer
				and GlobalStorageSiK.Client.pendingTerminalOpenByPlayer[playerNum] == true
			GlobalStorageSiK.TerminalUI.cancelPendingOpen(player)
			local transport = GlobalStorageSiK.NetClient
			if inFlight and transport and transport.sendCommand then
				transport.sendCommand("closeTerminal", {targetOpenSeq=pending.requestId}, player)
			end
		else
			-- Cancelling an older tablet request must not cancel a newer physical open.
			requests[playerNum] = nil
		end
	end
end

---@return boolean handled true solo para la solicitud remota exacta en vuelo
function GlobalStorageSiK.TerminalUI.onRemoteOpenResult(payload, accepted)
	payload = payload or {}
	local playerNum = tonumber(payload.playerNum) or 0
	local requests = GlobalStorageSiK.TerminalUI._remoteOpenRequests or {}
	local pending = requests[playerNum]
	if not pending or tonumber(payload.openSeq) ~= pending.requestId then return false end
	requests[playerNum] = nil
	clearPendingOpen(playerNum, pending.requestId)
	if type(pending.callback) == "function" then
		local ok, err = pcall(pending.callback, accepted == true, payload.reason, payload)
		if not ok then GlobalStorageSiK.Log.error("TerminalUI", "remote open callback", tostring(err)) end
	end
	return true
end

-- Called by the existing access watcher only while a view or request exists.
function GlobalStorageSiK.TerminalUI.showCatalogFailure(playerNum, reason, confirmed)
	local ui = GlobalStorageSiK.TerminalUI.getInstanceForPlayer(playerNum)
	if ui and ui.onClose then ui:onClose() end
	local seq = (GlobalStorageSiK.Client.terminalOpenSeqByPlayer or {})[playerNum]
	ui = GlobalStorageSiK.TerminalUI.showPending(playerNum, seq)
	if ui then
		Loading.set(ui, "failed", seq)
		ui._gsCatalogLoad.failureKey = confirmed and "IGUI_GS_InventoryIncomplete" or "IGUI_GS_AccessTimeoutTitle"
		ui:syncHeaderChrome()
	end
	local feedback = require "GS_CatalogFeedback"
	GlobalStorageSiK.CatalogFeedback = feedback
	return feedback.show(playerNum, reason, confirmed)
end

function GlobalStorageSiK.TerminalUI.confirmCatalogAccess(payload)
	local n = payload.playerNum
	local client = GlobalStorageSiK.Client
	if not client.terminalOpenSeqByPlayer or client.terminalOpenSeqByPlayer[n] ~= payload.openSeq then return false end
	-- Access has its ACK; catalog completion retains the pending opening intent
	-- and uses the transport deadline rather than the old access timeout.
	pendingOpenDeadlines[n] = nil
	return true
end

-- This is a shell presentation, never a synthetic terminalState response.
function GlobalStorageSiK.TerminalUI.showPending(n, sequence)
	if not GS_TerminalUI then return end
	local player = GlobalStorageSiK.NetClient.getPlayer(n)
	local rect = resolveShellRect(player)
	local ui = GS_TerminalUI:new(rect.x, rect.y, rect.w, rect.h, n)
	ui.terminalState = {playerNum=n}
	ui._gsCatalogLoad = {phase="checking", sequence=sequence, started=getTimestampMs and getTimestampMs() or 0}
	ui:initialise()
	GlobalStorageSiK.TerminalUI.setInstanceForPlayer(n, ui)
	Loading.lock(ui)
	ui:show()
	GlobalStorageSiK.Log.debug("CatalogTransport", "shell_visible", "player=" .. tostring(n)
		.. " openSeq=" .. tostring(sequence))
	return ui
end

function GlobalStorageSiK.TerminalUI.dispatchOpening(player, sequence, dispatch)
	local n = player:getPlayerNum()
	local ui = GlobalStorageSiK.TerminalUI.getInstanceForPlayer(n)
	if not ui or not Events or not Events.OnTick then return dispatch() end
	local function sendOnce()
		Events.OnTick.Remove(sendOnce)
		ui._gsOpenDispatch = nil
		if GlobalStorageSiK.TerminalUI.getInstanceForPlayer(n) ~= ui
			or GlobalStorageSiK.Client.terminalOpenSeqByPlayer[n] ~= sequence then return end
		if not dispatch() then
			local request = (GlobalStorageSiK.TerminalUI._remoteOpenRequests or {})[n]
			ui:onClose()
			GlobalStorageSiK.TerminalUI.showCatalogFailure(n, "catalog_send", false)
			if request and request.requestId == sequence and type(request.callback) == "function" then
				pcall(request.callback, false, "catalog_send", {playerNum=n, openSeq=sequence})
			end
		end
	end
	ui._gsOpenDispatch = sendOnce
	Events.OnTick.Add(sendOnce)
	return true
end

function GlobalStorageSiK.TerminalUI.catalogProgress(payload, done, total)
	local ui = GlobalStorageSiK.TerminalUI.getInstanceForPlayer(payload.playerNum)
	if not ui or GlobalStorageSiK.Client.terminalOpenSeqByPlayer[payload.playerNum] ~= payload.openSeq then return end
	local first = not ui._gsCatalogLoad or ui._gsCatalogLoad.phase == "checking"
	if first and done == 0 then
		-- ACK is already authorized by CatalogClient. Reuse only data matching
		-- this player's confirmed network/scope; no permission comes from cache.
		local cache = GlobalStorageSiK.Client.getInventoryCatalogPreview(payload)
		local preview = {}
		for k, v in pairs(payload) do preview[k] = v end
		if cache then
			preview.items, preview.itemTypeCount = cache.items, cache.itemTypeCount
			preview._gsAppliedCatalogRevision = cache.inventoryRevision
		end
		ui.terminalState = preview
		if GlobalStorageSiK.TerminalTabs and GlobalStorageSiK.TerminalTabs.applyAccessMode then
			GlobalStorageSiK.TerminalTabs.applyAccessMode(ui, "full", nil)
		else ui.accessMode = "full" end
		Loading.set(ui, cache and "validating" or "loading", payload.openSeq, done, total)
		if cache then
			Loading.unlock(ui)
			local ok, err = pcall(ui.refreshFromState, ui, preview)
			Loading.lock(ui)
			if not ok then GlobalStorageSiK.Log.error("TerminalUI", "catalog preview", tostring(err)) end
		end
	else
		local previous = ui.terminalState or {}
		local hasRows = type(previous.items) == "table"
		-- A changed scope must not keep exposing the prior restricted catalog.
		if previous.catalogScope ~= payload.catalogScope then
			ui.terminalState = {playerNum=payload.playerNum, networkId=payload.networkId,
				catalogScope=payload.catalogScope}
			for _, panel in pairs(ui.tabPanels or {}) do
				if panel.setVisible then panel:setVisible(false) end
			end
			ui._gsCatalogBodyHidden = true
			if ui.itemsPanel and GlobalStorageSiK.TerminalItems.disposeSection then
				GlobalStorageSiK.TerminalItems.disposeSection(ui.itemsPanel, ui)
				ui._gsBuiltTabs.items = nil
			end
			hasRows = false
		end
		local phase = hasRows and "updating" or "loading"
		if hasRows and ui._gsCatalogLoad and ui._gsCatalogLoad.phase == "validating" then phase = "validating" end
		Loading.set(ui, phase, payload.openSeq, done, total)
	end
end

-- Called by the existing access watcher only while a view or request exists.
-- Fence before callbacks: a late ACK must never reopen an expired request.
function GlobalStorageSiK.TerminalUI.expirePendingOpens(now)
	local client = GlobalStorageSiK.Client
	if not client then pendingOpenDeadlines = {}; return false end
	local pending = client.pendingTerminalOpenByPlayer or {}
	local sequences = client.terminalOpenSeqByPlayer or {}
	for n=0,3 do
		local entry = pendingOpenDeadlines[n]
		if entry then
			if not pending[n] or sequences[n] ~= entry.seq then
				pendingOpenDeadlines[n] = nil
			else
				if now < entry.started then
					entry.started, entry.deadline = now, now + OPEN_TIMEOUT_MS
				end
				if now >= entry.deadline then
					local seq = entry.seq + 1
					if seq > 2147483647 then seq = 1 end
					sequences[n] = seq
					if n == 0 then client.terminalOpenSeq = seq end
					clearPendingOpen(n, seq)
					local transport = GlobalStorageSiK.NetClient
					if transport and transport.sendCommand then
						transport.sendCommand("closeTerminal", {targetOpenSeq=entry.seq}, entry.player)
					end
					GlobalStorageSiK.TerminalUI.showCatalogFailure(n, "open_timeout", false)
					GlobalStorageSiK.TerminalUI.onRemoteOpenResult(
						{playerNum=n, openSeq=entry.seq, reason="open_timeout"}, false)
				end
			end
		end
	end
	for n=0,3 do if pendingOpenDeadlines[n] then return true end end
	return false
end

--- Apertura remota explicita. No envia coordenadas ni cambia primero la sesion:
--- el servidor resuelve anclas activas y revalida proveedor, rango y permisos.
---@param networkId string
---@param callback function|nil recibe (accepted, reason, payload)
---@return number|nil requestId
function GlobalStorageSiK.TerminalUI.requestOpenNetwork(networkId, playerArg, callback)
	if type(networkId) ~= "string" or networkId == "" or #networkId > 128
		or not GlobalStorageSiK.NetClient then
		return nil
	end
	local player = GlobalStorageSiK.PlayerUtils.resolve(playerArg)
	if not player then return nil end
	local old = GlobalStorageSiK.TerminalUI.getInstanceForPlayer(player:getPlayerNum())
	if old and old.onClose then old:onClose() end
	local playerNum, openSeq = nextOpenSequence(player)
	GlobalStorageSiK.TerminalUI._remoteOpenRequests =
		GlobalStorageSiK.TerminalUI._remoteOpenRequests or {}
	GlobalStorageSiK.TerminalUI._remoteOpenRequests[playerNum] = {
		requestId = openSeq, networkId = networkId, callback = callback,
	}
	local payload = {
		openSeq = openSeq,
		remoteAccess = true,
	}
	if GlobalStorageSiK.Client and GlobalStorageSiK.Client.addInventoryCatalogToken then
		payload = GlobalStorageSiK.Client.addInventoryCatalogToken(payload, playerNum, networkId)
	end
	GlobalStorageSiK.TerminalUI.showPending(playerNum, openSeq)
	local sent = GlobalStorageSiK.TerminalUI.dispatchOpening(player, openSeq, function()
		return GlobalStorageSiK.NetClient.sendNetworkCommand("openTerminal", networkId, payload, player)
	end)
	if not sent then
		GlobalStorageSiK.TerminalUI._remoteOpenRequests[playerNum] = nil
		clearPendingOpen(playerNum, openSeq)
		return nil
	end
	return openSeq
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
		return sendPhysicalOpen(player, hint, openNetworkId, false)
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
			clearPendingOpen(player:getPlayerNum())
		end
		local blocked = buildBlockedPayload(player, accessReason)
		blocked.networkId = openNetworkId
		GlobalStorageSiK.TerminalUI.showBlocked(blocked)
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

	return sendPhysicalOpen(player, hint or terminal, openNetworkId, true)
end
