--[[
	GlobalStorageSiK - Sincronización de inventario del terminal (cliente)
	Autor: SiK
	Fecha: 2025-06-23
	Descripción: Refresco fiable tras depósitos/retiros en SP y MP.
]]

require "GS_NetClient"
local UI = require "GS_UI_Framework"

-- Revision, debounce and visual transfer ownership are local to each player.
local function createPlayerSync(playerNum)
local sync = {}
local function currentUI()
	local terminal = GlobalStorageSiK.TerminalUI
	if terminal and terminal.getInstanceForPlayer then return terminal.getInstanceForPlayer(playerNum) end
	return playerNum == 0 and terminal and terminal.instance or nil
end
local function activeNetworkId()
	local client = GlobalStorageSiK.Client
	local value = client and client.activeNetworkIdByPlayer and client.activeNetworkIdByPlayer[playerNum]
	return value or (playerNum == 0 and client and client.activeNetworkId) or nil
end

local PULL_DEBOUNCE_TICKS = 4
local _pullDueTick = 0
local _tickCounter = 0
local _lastAppliedRevision = {}
local _requiredSnapshotRevision = {}
local _tickInstalled = false
local _managedTransfer = nil
local _revisionOrder = {}
local MAX_REVISION_NETWORKS = 64

local function touchRevisionNetwork(networkId)
	for i = #_revisionOrder, 1, -1 do
		if _revisionOrder[i] == networkId then table.remove(_revisionOrder, i) end
	end
	_revisionOrder[#_revisionOrder + 1] = networkId
	if #_revisionOrder > MAX_REVISION_NETWORKS then
		local oldest = table.remove(_revisionOrder, 1)
		if oldest then
			_lastAppliedRevision[oldest] = nil
			_requiredSnapshotRevision[oldest] = nil
		end
	end
end

---@param networkId string|nil
---@return number
local function getAppliedRevision(networkId)
	if not networkId then
		return 0
	end
	return _lastAppliedRevision[networkId] or 0
end

---@param networkId string|nil
---@param revision number|nil
local function markRevision(networkId, revision)
	if not networkId or not revision then
		return
	end
	_lastAppliedRevision[networkId] = math.max(getAppliedRevision(networkId), revision)
	touchRevisionNetwork(networkId)
end

function sync.clearRevisionState(networkId)
	if networkId then
		_lastAppliedRevision[networkId] = nil
		_requiredSnapshotRevision[networkId] = nil
		for i = #_revisionOrder, 1, -1 do
			if _revisionOrder[i] == networkId then table.remove(_revisionOrder, i) end
		end
		return
	end
	_lastAppliedRevision = {}
	_requiredSnapshotRevision = {}
	_revisionOrder = {}
	_managedTransfer = nil
	_pullDueTick = 0
	if _tickInstalled and Events and Events.OnTick then
		Events.OnTick.Remove(sync.onTick)
		_tickInstalled = false
	end
end

---@return string
local function currentSearchQuery()
	local ui = currentUI()
	if ui and ui.getSearchQuery then
		return ui:getSearchQuery() or ""
	end
	if ui and ui.searchEntry and ui.searchEntry.getText then
		return ui.searchEntry:getText() or ""
	end
	return ""
end

---@param networkId string|nil
---@return boolean
local function isManagedTransferNetwork(networkId)
	if not _managedTransfer then
		return false
	end
	if not _managedTransfer.networkId then
		return true
	end
	return networkId == _managedTransfer.networkId
end

--- Abre una transaccion visual para una cola de transferencias. Los micro-lotes
--- siguen confirmandose uno a uno, pero la lista visible no se reconstruye
--- hasta que toda la operacion termina o se cancela.
---@param owner string
---@param networkId string|nil
---@param searchQuery string|nil
---@return boolean
function sync.beginManagedTransfer(owner, networkId, searchQuery, operationId)
	if _managedTransfer then
		return _managedTransfer.owner == owner and _managedTransfer.operationId == operationId
			and _managedTransfer.networkId == networkId
	end
	local ui = currentUI()
	local panel = ui and ui.itemsListPanel
	if panel and panel.itemTable and panel.itemTable.getScrollOffset then
		panel._itemsScrollOffset = panel.itemTable:getScrollOffset()
	end
	_managedTransfer = {
		owner = owner,
		operationId = operationId,
		networkId = networkId,
		searchQuery = searchQuery or currentSearchQuery(),
		pendingState = nil,
		dirty = false,
	}
	if ui then
		ui._gsManagedTransferActive = true
	end
	return true
end

--- Cierra la transaccion visual y reconcilia una sola vez. Si el servidor ya
--- envio un snapshot ligero durante la cola se aplica el mas reciente; si no,
--- se pinta el modelo ajustado por deltas y se solicita una verificacion.
---@param owner string
---@param searchQuery string|nil
---@param expectedRevision number|nil
function sync.finishManagedTransfer(owner, searchQuery, expectedRevision, operationId)
	local managed = _managedTransfer
	if not managed or managed.owner ~= owner or managed.operationId ~= operationId then
		return
	end
	_managedTransfer = nil
	local ui = currentUI()
	if ui then
		ui._gsManagedTransferActive = nil
	end
	local uiVisible = ui and (not ui.isVisible or ui:isVisible())
	local uiNetworkId = ui and ui.terminalState and ui.terminalState.networkId
	local sameNetwork = not managed.networkId or not uiNetworkId or managed.networkId == uiNetworkId
	-- BUG REAL (2026-08-21, reportado: "pulso F9 y el terminal ya no abre,
	-- el servidor confirma acceso una y otra vez pero el cliente nunca
	-- muestra nada"): este flag SOLO se limpia mas abajo dentro de la rama
	-- "pendingIsFresh and uiVisible" - pero se ESCRIBIA aqui de forma
	-- incondicional, sin importar si habia UI visible que proteger. Si una
	-- transferencia gestionada terminaba con el terminal CERRADO (p.ej. leer
	-- una revista de red sin tener el terminal abierto, o cerrarlo mientras
	-- un deposito seguia en cola), el flag quedaba escrito y NUNCA se
	-- limpiaba - onTerminalState() lo comprueba en CUALQUIER terminalState
	-- futuro (linea ~263), incluida una apertura normal por F9, y la
	-- descarta indefinidamente hasta que el snapshotRevision del siguiente
	-- ZoneScanJob completo alcance ese valor por pura casualidad. El
	-- proposito real de este flag es proteger una UI QUE YA ESTA ABIERTA de
	-- un envio tardio con datos viejos - si no hay UI abierta no hay nada
	-- que proteger, asi que ahora solo se escribe cuando uiVisible es
	-- cierto, evitando dejarlo huerfano para siempre.
	if managed.networkId and expectedRevision and uiVisible and sameNetwork then
		_requiredSnapshotRevision[managed.networkId] = math.max(
			_requiredSnapshotRevision[managed.networkId] or 0, expectedRevision)
		touchRevisionNetwork(managed.networkId)
	end
	-- BUG REAL (2026-08-21): expectedRevision viene de operation.lastRevision,
	-- que se rellena con inventoryRevision (sube en CADA transferencia). Antes
	-- se comparaba contra pendingState.snapshotRevision - un contador DISTINTO
	-- que solo avanza al terminar el ZoneScanJob completo (~12s). Al ser
	-- incompatibles, pendingIsFresh daba practicamente siempre false: el
	-- estado fresco que pushTerminalInventorySync ya entregaba correctamente
	-- (ver GS_Server.lua/GS_Transfer.lua, fix "-dev11" del snapshot preciso
	-- por nodo) se descartaba sin aplicarse, y solo se repintaba el
	-- ui.terminalState VIEJO via refreshItemsTab() - de ahi que pareciera que
	-- el deposito/retorno "no refrescaba" hasta el siguiente scan de 12s.
	-- Fix: comparar inventoryRevision contra inventoryRevision (misma
	-- familia de contador que expectedRevision), conservando snapshotRevision
	-- solo para markRevision/_requiredSnapshotRevision, que SI son sobre el
	-- contador de snapshot y no deben mezclarse con este.
	local pendingInventoryRevision = managed.pendingState and managed.pendingState.inventoryRevision or 0
	local pendingSnapshotRevision = managed.pendingState and managed.pendingState.snapshotRevision or 0
	local pendingIsFresh = managed.pendingState
		and (not expectedRevision or pendingInventoryRevision >= expectedRevision)
	if pendingIsFresh and uiVisible and sameNetwork and GlobalStorageSiK.TerminalUI
		and type(GlobalStorageSiK.TerminalUI.show) == "function" then
		markRevision(managed.networkId or managed.pendingState.networkId, pendingSnapshotRevision)
		if managed.networkId then _requiredSnapshotRevision[managed.networkId] = nil end
		GlobalStorageSiK.TerminalUI.show(managed.pendingState)
	elseif uiVisible and sameNetwork then
		if managed.dirty and ui.refreshItemsTab then
			ui:refreshItemsTab()
		end
		if managed.dirty and ui.refreshNetworkPanel then
			ui:refreshNetworkPanel()
		end
	end
	-- No pedir inmediatamente searchItems: mientras el snapshot incremental de
	-- fondo no termine, esa consulta solo devolvería la misma captura antigua y
	-- haría parpadear/reaparecer cantidades. El servidor empuja el estado estable
	-- a los observadores al finalizar el scan.
end

--- Solicita al servidor un terminalState actualizado.
---@param searchQuery string|nil
---@return boolean
function sync.requestInventoryRefresh(searchQuery)
	if not GlobalStorageSiK.NetClient or not GlobalStorageSiK.NetClient.sendCommand then
		return false
	end
	local ui = currentUI()
	if not ui or not ui.getIsVisible or not ui:isVisible() then
		return false
	end
	local payload = {
		searchQuery = searchQuery or currentSearchQuery(),
	}
	local networkId = ui.terminalState and ui.terminalState.networkId
	if GlobalStorageSiK.Client and GlobalStorageSiK.Client.addInventoryCatalogToken then
		payload = GlobalStorageSiK.Client.addInventoryCatalogToken(payload,
			ui.playerNum or 0, networkId)
	end
	return GlobalStorageSiK.NetClient.sendCommand("searchItems", payload, playerNum)
end

--- Programa pull de inventario (debounced).
---@param searchQuery string|nil
---@param expectedRevision number|nil
function sync.scheduleInventoryPull(searchQuery, expectedRevision)
	local ui = currentUI()
	if not ui or not ui.getIsVisible or not ui:isVisible() then
		return
	end
	local networkId = ui.terminalState and ui.terminalState.networkId
		or activeNetworkId()
	local catalogRevision = ui.terminalState and
		(ui.terminalState._gsAppliedCatalogRevision or ui.terminalState.inventoryRevision)
	if expectedRevision and networkId and ui.terminalState and type(ui.terminalState.items) == "table"
		and (tonumber(catalogRevision) or -1) >= expectedRevision then
		return
	end
	_pullDueTick = _tickCounter + PULL_DEBOUNCE_TICKS
	ui._gsPendingInventorySearch = searchQuery or currentSearchQuery()
	if not _tickInstalled and Events and Events.OnTick then
		_tickInstalled = true
		Events.OnTick.Add(sync.onTick)
	end
end

function sync.onTick()
	_tickCounter = _tickCounter + 1
	if _pullDueTick <= 0 or _tickCounter < _pullDueTick then
		return
	end
	_pullDueTick = 0
	local ui = currentUI()
	local q = (ui and ui._gsPendingInventorySearch) or currentSearchQuery()
	if ui then
		ui._gsPendingInventorySearch = nil
	end
	sync.requestInventoryRefresh(q)
	-- El debounce es one-shot. Mantener este OnTick instalado despues del pull
	-- no aporta trabajo y deja un proceso latente por el resto de la sesion.
	if _tickInstalled and _pullDueTick <= 0 and Events and Events.OnTick then
		Events.OnTick.Remove(sync.onTick)
		_tickInstalled = false
	end
end

--- Aplica retiro optimista a la lista cacheada del terminal.
---@param networkId string|nil
---@param fullType string
---@param moved number
function sync.applyWithdrawDelta(networkId, fullType, moved)
	if not fullType or not moved or moved <= 0 then
		return
	end
	local ui = currentUI()
	if not ui or not ui.terminalState or not ui.terminalState.items then
		return
	end
	local stateNid = ui.terminalState.networkId
		or activeNetworkId()
	if networkId and stateNid and networkId ~= stateNid then
		return
	end
	local items = ui.terminalState.items
	for i = #items, 1, -1 do
		if items[i].fullType == fullType then
			-- A family root can combine several fullTypes. A fullType delta
			-- cannot identify that root or its children; await the real catalog.
			if items[i].rowKey or items[i].mixedVariants then return end
			local nextCount = (items[i].count or 0) - moved
			if nextCount <= 0 then
				table.remove(items, i)
			else
				items[i].count = nextCount
			end
			if GlobalStorageSiK.Client then
				GlobalStorageSiK.Client.cachedTerminalStateByPlayer = GlobalStorageSiK.Client.cachedTerminalStateByPlayer or {}
				GlobalStorageSiK.Client.cachedTerminalStateByPlayer[playerNum] = ui.terminalState
				if playerNum == 0 then GlobalStorageSiK.Client.cachedTerminalState = ui.terminalState end
			end
			if isManagedTransferNetwork(networkId) then
				_managedTransfer.dirty = true
				return
			end
			if ui.refreshItemsTab then
				ui:refreshItemsTab()
			end
			if ui.refreshNetworkPanel then
				ui:refreshNetworkPanel()
			end
			return
		end
	end
end

--- Fuerza refresco de la pestaña ítems si el terminal está visible.
function sync.refreshVisibleItemsTab()
	local ui = currentUI()
	if not ui or not ui.getIsVisible or not ui:isVisible() then
		return
	end
	if ui.refreshItemsTab then
		ui:refreshItemsTab()
	end
end

---@param state table|nil
---@param inventorySync boolean|nil estado ligero antes de fusionarlo con cache
---@return boolean deferVisibleRefresh
function sync.onTerminalState(state, inventorySync)
	if not state then
		return false
	end
	local networkId = state.networkId
	local snapshotRevision = state.snapshotRevision or 0
	if inventorySync == true and state.openUi ~= true and isManagedTransferNetwork(networkId) then
		_managedTransfer.pendingState = state
		_managedTransfer.dirty = true
		return true
	end
	local requiredRevision = (networkId and _requiredSnapshotRevision[networkId]) or 0
	-- Cinturon de seguridad ademas del fix de arriba (finishManagedTransfer ya
	-- no deja este flag huerfano si no habia UI visible al terminar) - una
	-- apertura EXPLICITA del terminal (F9/interaccion directa del jugador,
	-- state.openUi == true) nunca debe poder quedar descartada por este
	-- mecanismo pensado solo para no pisar una UI ya abierta con datos
	-- viejos. Si igualmente quedara un flag huerfano por cualquier otra via
	-- no prevista, esto evita que bloquee indefinidamente el propio boton
	-- de abrir - la sincronizacion fina de cantidades ya la cubre el push
	-- normal nada mas abrir.
	if requiredRevision > 0 and snapshotRevision < requiredRevision and state.openUi ~= true then
		-- Una búsqueda o reapertura puede responder antes que el escaneo de fondo.
		-- No permitir que ese snapshot anterior restaure cantidades confirmadas.
		return true
	end
	if networkId then
		markRevision(networkId, snapshotRevision)
		if requiredRevision > 0 and snapshotRevision >= requiredRevision then
			_requiredSnapshotRevision[networkId] = nil
		end
	end
	return false
end

--- Procesa actionResult de transferencias.
---@param args table|nil
function sync.onActionResult(args)
	if not args or not args.transfer then
		return
	end
	local transfer = args.transfer
	local networkId = transfer.networkId
		or activeNetworkId()

	-- El servidor manda terminalState (ya con la cantidad post-retiro) ANTES
	-- que actionResult en el flujo de withdrawItem. Si ese terminalState ya
	-- se aplico (revision ya marcada como vista), el estado cacheado ya
	-- refleja el retiro y NO hay que restar de nuevo aqui, o se resta dos
	-- veces (bug reportado: quedan 15 reales pero el almacen muestra 14).
	local ui = currentUI()
	local state = ui and ui.terminalState
	local alreadyApplied = state and state.networkId == networkId
		and type(state.items) == "table" and transfer.inventoryRevision
		and (tonumber(state._gsAppliedCatalogRevision or state.inventoryRevision) or -1) >= transfer.inventoryRevision
	local exact = transfer.selectionMode == "exact_group" or transfer.selectionMode == "exact_ids"
	if args.ok and transfer.op == "withdraw" and not exact and transfer.fullType and (transfer.moved or 0) > 0 and not alreadyApplied then
		sync.applyWithdrawDelta(networkId, transfer.fullType, transfer.moved)
	end

	if args.ok and (transfer.moved or 0) > 0 and transfer.deferInventoryPull ~= true then
		sync.scheduleInventoryPull(currentSearchQuery(), transfer.inventoryRevision)
	end

	-- WithdrawClient posee la cola y la correlación de respuestas. TerminalSync
	-- solo aplica el delta confirmado; nunca libera trabajos por su cuenta.
end

return sync
end

local players = {}
local function forPlayer(playerNum)
	playerNum = playerNum == nil and 0 or tonumber(playerNum)
	if not playerNum or playerNum ~= math.floor(playerNum) or playerNum < 0 or playerNum > 3 then return nil end
	if not players[playerNum] then players[playerNum] = createPlayerSync(playerNum) end
	return players[playerNum]
end

local Sync = {}
GlobalStorageSiK.TerminalSync = Sync
function Sync.beginManagedTransfer(owner, networkId, searchQuery, playerNum, operationId)
	local sync = forPlayer(playerNum)
	return sync and sync.beginManagedTransfer(owner, networkId, searchQuery, operationId) or false
end
function Sync.finishManagedTransfer(owner, searchQuery, expectedRevision, playerNum, operationId)
	local sync = forPlayer(playerNum)
	if sync then return sync.finishManagedTransfer(owner, searchQuery, expectedRevision, operationId) end
end
function Sync.clearRevisionState(networkId, playerNum)
	if playerNum ~= nil then
		local sync = forPlayer(playerNum)
		if sync then sync.clearRevisionState(networkId) end
		return
	end
	for i = 0, 3 do
		if players[i] then players[i].clearRevisionState(networkId) end
	end
end
function Sync.requestInventoryRefresh(searchQuery, playerNum)
	local sync = forPlayer(playerNum)
	return sync and sync.requestInventoryRefresh(searchQuery) or false
end
function Sync.scheduleInventoryPull(searchQuery, expectedRevision, playerNum)
	local sync = forPlayer(playerNum)
	if sync then return sync.scheduleInventoryPull(searchQuery, expectedRevision) end
end
function Sync.applyWithdrawDelta(networkId, fullType, moved, playerNum)
	local sync = forPlayer(playerNum)
	if sync then return sync.applyWithdrawDelta(networkId, fullType, moved) end
end
function Sync.refreshVisibleItemsTab(playerNum)
	local sync = forPlayer(playerNum)
	if sync then return sync.refreshVisibleItemsTab() end
end
function Sync.onTerminalState(state, inventorySync)
	if not state then return false end
	local sync = forPlayer(state.playerNum)
	return sync and sync.onTerminalState(state, inventorySync) or false
end
function Sync.onActionResult(args)
	if not args then return end
	local sync = forPlayer(args.playerNum)
	if sync then return sync.onActionResult(args) end
end
function Sync.onTick()
	for i = 0, 3 do if players[i] then players[i].onTick() end end
end
return Sync
