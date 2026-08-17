--[[
	GlobalStorageSiK - Sincronización de inventario del terminal (cliente)
	Autor: SiK
	Fecha: 2025-06-23
	Descripción: Refresco fiable tras depósitos/retiros en SP y MP.
]]

require "GS_NetClient"

GlobalStorageSiK.TerminalSync = GlobalStorageSiK.TerminalSync or {}

local PULL_DEBOUNCE_TICKS = 4
local _pullDueTick = 0
local _tickCounter = 0
local _lastAppliedRevision = {}
local _requiredSnapshotRevision = {}
local _tickInstalled = false
local _managedTransfer = nil

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
end

---@return string
local function currentSearchQuery()
	local ui = GlobalStorageSiK.TerminalUI and GlobalStorageSiK.TerminalUI.instance
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
function GlobalStorageSiK.TerminalSync.beginManagedTransfer(owner, networkId, searchQuery)
	if _managedTransfer then
		return _managedTransfer.owner == owner
	end
	local ui = GlobalStorageSiK.TerminalUI and GlobalStorageSiK.TerminalUI.instance
	local panel = ui and ui.itemsListPanel
	if panel and panel.itemScroll and GlobalStorageSiK.TerminalScroll
		and GlobalStorageSiK.TerminalScroll.getScrollOffset then
		panel._itemsScrollOffset = GlobalStorageSiK.TerminalScroll.getScrollOffset(panel.itemScroll)
	end
	_managedTransfer = {
		owner = owner,
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
function GlobalStorageSiK.TerminalSync.finishManagedTransfer(owner, searchQuery, expectedRevision)
	local managed = _managedTransfer
	if not managed or managed.owner ~= owner then
		return
	end
	_managedTransfer = nil
	local ui = GlobalStorageSiK.TerminalUI and GlobalStorageSiK.TerminalUI.instance
	if ui then
		ui._gsManagedTransferActive = nil
	end
	local uiVisible = ui and (not ui.isVisible or ui:isVisible())
	local uiNetworkId = ui and ui.terminalState and ui.terminalState.networkId
	local sameNetwork = not managed.networkId or not uiNetworkId or managed.networkId == uiNetworkId
	if managed.networkId and expectedRevision then
		_requiredSnapshotRevision[managed.networkId] = math.max(
			_requiredSnapshotRevision[managed.networkId] or 0, expectedRevision)
	end
	local pendingRevision = managed.pendingState and managed.pendingState.snapshotRevision or 0
	local pendingIsFresh = managed.pendingState
		and (not expectedRevision or pendingRevision >= expectedRevision)
	if pendingIsFresh and uiVisible and sameNetwork and GlobalStorageSiK.TerminalUI
		and type(GlobalStorageSiK.TerminalUI.show) == "function" then
		markRevision(managed.networkId or managed.pendingState.networkId, pendingRevision)
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
function GlobalStorageSiK.TerminalSync.requestInventoryRefresh(searchQuery)
	if not GlobalStorageSiK.NetClient or not GlobalStorageSiK.NetClient.sendCommand then
		return false
	end
	local ui = GlobalStorageSiK.TerminalUI and GlobalStorageSiK.TerminalUI.instance
	if not ui or not ui.getIsVisible or not ui:isVisible() then
		return false
	end
	return GlobalStorageSiK.NetClient.sendCommand("searchItems", {
		searchQuery = searchQuery or currentSearchQuery(),
	})
end

--- Programa pull de inventario (debounced).
---@param searchQuery string|nil
---@param expectedRevision number|nil
function GlobalStorageSiK.TerminalSync.scheduleInventoryPull(searchQuery, expectedRevision)
	local ui = GlobalStorageSiK.TerminalUI and GlobalStorageSiK.TerminalUI.instance
	if not ui or not ui.getIsVisible or not ui:isVisible() then
		return
	end
	local networkId = ui.terminalState and ui.terminalState.networkId
		or (GlobalStorageSiK.Client and GlobalStorageSiK.Client.activeNetworkId)
	if expectedRevision and networkId and getAppliedRevision(networkId) >= expectedRevision then
		return
	end
	_pullDueTick = _tickCounter + PULL_DEBOUNCE_TICKS
	ui._gsPendingInventorySearch = searchQuery or currentSearchQuery()
	if not _tickInstalled and Events and Events.OnTick then
		_tickInstalled = true
		Events.OnTick.Add(GlobalStorageSiK.TerminalSync.onTick)
	end
end

function GlobalStorageSiK.TerminalSync.onTick()
	_tickCounter = _tickCounter + 1
	if _pullDueTick <= 0 or _tickCounter < _pullDueTick then
		return
	end
	_pullDueTick = 0
	local ui = GlobalStorageSiK.TerminalUI and GlobalStorageSiK.TerminalUI.instance
	local q = (ui and ui._gsPendingInventorySearch) or currentSearchQuery()
	if ui then
		ui._gsPendingInventorySearch = nil
	end
	GlobalStorageSiK.TerminalSync.requestInventoryRefresh(q)
	-- El debounce es one-shot. Mantener este OnTick instalado despues del pull
	-- no aporta trabajo y deja un proceso latente por el resto de la sesion.
	if _tickInstalled and _pullDueTick <= 0 and Events and Events.OnTick then
		Events.OnTick.Remove(GlobalStorageSiK.TerminalSync.onTick)
		_tickInstalled = false
	end
end

--- Aplica retiro optimista a la lista cacheada del terminal.
---@param networkId string|nil
---@param fullType string
---@param moved number
function GlobalStorageSiK.TerminalSync.applyWithdrawDelta(networkId, fullType, moved)
	if not fullType or not moved or moved <= 0 then
		return
	end
	local ui = GlobalStorageSiK.TerminalUI and GlobalStorageSiK.TerminalUI.instance
	if not ui or not ui.terminalState or not ui.terminalState.items then
		return
	end
	local stateNid = ui.terminalState.networkId
		or (GlobalStorageSiK.Client and GlobalStorageSiK.Client.activeNetworkId)
	if networkId and stateNid and networkId ~= stateNid then
		return
	end
	local items = ui.terminalState.items
	for i = #items, 1, -1 do
		if items[i].fullType == fullType then
			local nextCount = (items[i].count or 0) - moved
			if nextCount <= 0 then
				table.remove(items, i)
			else
				items[i].count = nextCount
			end
			if GlobalStorageSiK.Client then
				GlobalStorageSiK.Client.cachedTerminalState = ui.terminalState
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
function GlobalStorageSiK.TerminalSync.refreshVisibleItemsTab()
	local ui = GlobalStorageSiK.TerminalUI and GlobalStorageSiK.TerminalUI.instance
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
function GlobalStorageSiK.TerminalSync.onTerminalState(state, inventorySync)
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
	local requiredRevision = networkId and _requiredSnapshotRevision[networkId] or 0
	if requiredRevision > 0 and snapshotRevision < requiredRevision then
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
function GlobalStorageSiK.TerminalSync.onActionResult(args)
	if not args or not args.transfer then
		return
	end
	local transfer = args.transfer
	local networkId = transfer.networkId
		or (GlobalStorageSiK.Client and GlobalStorageSiK.Client.activeNetworkId)

	-- El servidor manda terminalState (ya con la cantidad post-retiro) ANTES
	-- que actionResult en el flujo de withdrawItem. Si ese terminalState ya
	-- se aplico (revision ya marcada como vista), el estado cacheado ya
	-- refleja el retiro y NO hay que restar de nuevo aqui, o se resta dos
	-- veces (bug reportado: quedan 15 reales pero el almacen muestra 14).
	local alreadyApplied = networkId and transfer.inventoryRevision
		and getAppliedRevision(networkId) >= transfer.inventoryRevision
	if args.ok and transfer.op == "withdraw" and transfer.fullType and (transfer.moved or 0) > 0 and not alreadyApplied then
		GlobalStorageSiK.TerminalSync.applyWithdrawDelta(networkId, transfer.fullType, transfer.moved)
	end

	if args.ok and (transfer.moved or 0) > 0 and transfer.deferInventoryPull ~= true then
		GlobalStorageSiK.TerminalSync.scheduleInventoryPull(currentSearchQuery(), transfer.inventoryRevision)
	end

	-- WithdrawClient posee la cola y la correlación de respuestas. TerminalSync
	-- solo aplica el delta confirmado; nunca libera trabajos por su cuenta.
end
