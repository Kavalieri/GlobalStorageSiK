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
local _tickInstalled = false

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
function GlobalStorageSiK.TerminalSync.onTerminalState(state)
	if not state then
		return
	end
	local networkId = state.networkId
	if networkId and state.inventoryRevision then
		markRevision(networkId, state.inventoryRevision)
	end
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

	if args.ok and (transfer.moved or 0) > 0 then
		GlobalStorageSiK.TerminalSync.scheduleInventoryPull(currentSearchQuery(), transfer.inventoryRevision)
	end

	if GlobalStorageSiK.WithdrawClient and GlobalStorageSiK.WithdrawClient.clearPending then
		GlobalStorageSiK.WithdrawClient.clearPending()
	end
end
