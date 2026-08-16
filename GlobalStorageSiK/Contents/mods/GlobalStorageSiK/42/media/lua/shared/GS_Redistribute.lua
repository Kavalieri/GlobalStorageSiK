--[[
	GlobalStorageSiK - Auto-ordenar (antes "Redistribución por categoría")
	Autor: SiK
	Fecha: 2025-06-25
	Descripción: Mueve ítems mal ubicados al contenedor adecuado por categoría,
	o por afinidad "mismo ítem" si no hay categoría configurada; fallback a «cualquiera».
]]

require "GS_Network"
require "GS_Router"
require "GS_InventorySync"
require "GS_Sandbox"
require "GS_Power"
require "GS_Zones"
require "GS_ZonePriority"
require "GS_I18n"

GlobalStorageSiK.Redistribute = {}

-- Presupuesto por paso del job. MaxItemsPerBulkTick limita MOVIMIENTOS en
-- depósitos normales, pero Auto Sort también debe limitar ítems INSPECCIONADOS:
-- una red ya ordenada podía recorrer miles de ítems contra todos los nodos en
-- un único tick porque moved seguía en cero. Dos movimientos por paso reducen
-- además los pares remove/add que el servidor debe replicar a los clientes.
local MAX_INDEX_ITEMS_PER_STEP = 50
local MAX_MOVE_ITEMS_PER_STEP = 25
local MAX_MOVES_PER_STEP = 2
local MAX_STEP_MS = 5

local function nowMs()
	return getTimestampMs and getTimestampMs() or 0
end

local function timeBudgetExceeded(startedAt, inspected)
	if inspected <= 0 or startedAt <= 0 then return false end
	local current = nowMs()
	return current > 0 and current - startedAt >= MAX_STEP_MS
end

--- Construye tabla zoneId -> zone.priority (1 = zona principal) para la red.
---@param registry table
---@param networkId string
---@return table<string, number>
local function buildZonePriorityLookup(registry, networkId)
	GlobalStorageSiK.ZonePriority.ensurePriorities(registry, networkId)
	local lookup = {}
	for zoneId, zone in pairs(registry.zones or {}) do
		if zone.networkId == networkId then
			lookup[zoneId] = tonumber(zone.priority) or math.huge
		end
	end
	return lookup
end

--- Compara dos nodos candidatos para saber cual es mejor destino (true si a
--- es mejor que b, para ordenar de mejor a peor).
--- 1) Prioridad EXPLICITA del contenedor (entry.priority, 1-100, 1=mejor)
---    manda sobre cualquier orden de zona: si el jugador puso prioridad 1 a
---    un congelador de zona secundaria, ese gana siempre para su categoria.
--- 2) Si ninguno de los dos tiene prioridad explicita, decide el orden de
---    zonas ya configurado (zone.priority ascendente = zona principal primero).
---@param a table live entry candidato
---@param b table live entry candidato
---@param zonePriorityOf table<string, number>
---@return boolean
local function candidateBetter(a, b, zonePriorityOf)
	local pa = a.entry and a.entry.priority
	local pb = b.entry and b.entry.priority
	if pa ~= nil or pb ~= nil then
		local va = pa or math.huge
		local vb = pb or math.huge
		if va ~= vb then return va < vb end
	end
	local za = zonePriorityOf[a.entry and a.entry.zoneId] or math.huge
	local zb = zonePriorityOf[b.entry and b.entry.zoneId] or math.huge
	if za ~= zb then return za < zb end
	return false
end

--- Cachea el tier por fullType+nodo solo si el nodo no tiene filtros
--- personalizados. Categorías/subcategorías dependen del tipo de script y son
--- estables; nombre/peso/tag pueden depender de la instancia y se reevalúan.
local function cachedMatchTier(session, nodeIndex, item, fullType)
	local live = session.liveNodes[nodeIndex]
	local entry = live and live.entry or {}
	if (entry.filters and #entry.filters > 0) or not fullType then
		return GlobalStorageSiK.Router.matchSpecificity(entry, item)
	end
	local byNode = session.matchTiersByType[fullType]
	if not byNode then
		byNode = {}
		session.matchTiersByType[fullType] = byNode
	end
	local cached = byNode[nodeIndex]
	if cached ~= nil then return cached ~= false and cached or nil end
	local tier = GlobalStorageSiK.Router.matchSpecificity(entry, item)
	byNode[nodeIndex] = tier or false
	return tier
end

--- Elige el MEJOR contenedor destino para un item, comparando TODOS los
--- candidatos validos (no el primero que encaje). Usa la MISMA
--- especificidad de categorias que GS_Router.pickDepositTarget
--- (matchSpecificity: 1=hoja exacta, 2=Nivel 2, 3=Nivel 1, 4=sin
--- restriccion), expandiendo el ultimo caso igual que Router: 4=sin
--- restriccion con el mismo fullType, 5=sin restriccion cualquiera.
--- antes Auto-ordenar solo distinguia esas dos bolsas y trataba Nivel 1/2/3
--- como un mismo grupo "especifico" sin desempate entre ellos, dando
--- resultados distintos a un deposito manual del MISMO item con la MISMA
--- configuracion de contenedores (pedido explicito: no debe haber diferencia
--- entre ambos caminos, es la misma decision de enrutado). El propio nodo de
--- origen se incluye en su tier correspondiente (con hueco garantizado) para
--- poder compararlo de tu a tu contra el resto: si ya es el mejor, no se
--- mueve nada.
---@param item InventoryItem
---@param fromIndex number
---@param session table
---@param character IsoPlayer|nil
---@return table|nil live
---@return number|nil liveIndex
local function pickRedistributeTarget(item, fromIndex, session, character)
	local liveNodes = session and session.liveNodes
	local fromLive = liveNodes and liveNodes[fromIndex]
	if not item or not fromLive or not liveNodes then
		return nil, nil
	end

	local bestByTier = {}
	local fullType = item.getFullType and item:getFullType() or nil
	for i = 1, #liveNodes do
		local live = liveNodes[i]
		local matchTier = cachedMatchTier(session, i, item, fullType)
		if matchTier then
			local isSelf = (live.container == fromLive.container)
			local hasSpace = isSelf or GlobalStorageSiK.Router.containerHasSpace(live.container, item, character)
			if hasSpace then
				local destinationTier = matchTier
				if matchTier == 4 then
					local counts = session.typeCountsByNode[i] or {}
					destinationTier = fullType and (counts[fullType] or 0) > 0 and 4 or 5
				end
				if destinationTier then
					local current = bestByTier[destinationTier]
					if not current or candidateBetter(live, current.live, session.zonePriorityOf) then
						bestByTier[destinationTier] = { live = live, index = i }
					end
				end
			end
		end
	end

	for tierIdx = 1, 5 do
		local best = bestByTier[tierIdx]
		if best then
			if best.live.container == fromLive.container then
				return nil, nil
			end
			return best.live, best.index
		end
	end
	return nil, nil
end

local function updateTypeCount(session, nodeIndex, fullType, delta)
	if not fullType or fullType == "" then return end
	local counts = session.typeCountsByNode[nodeIndex]
	if not counts then
		counts = {}
		session.typeCountsByNode[nodeIndex] = counts
	end
	counts[fullType] = math.max(0, (counts[fullType] or 0) + delta)
end

---@param player IsoPlayer
---@param networkId string
---@return table|nil session
---@return table summary
local function beginSession(player, networkId)
	local summary = { moved = 0, failed = 0, skipped = 0, checked = 0, total = 0, reason = nil }
	if not player then summary.reason = "no_player"; return nil, summary end
	if not GlobalStorageSiK.Sandbox.remoteTransferEnabled() then
		summary.reason = "remote_disabled"; return nil, summary
	end
	if not GlobalStorageSiK.Power.networkPowered(networkId) then
		summary.reason = "no_power"; return nil, summary
	end
	local liveNodes = GlobalStorageSiK.Network.getLiveContainers(networkId)
	if #liveNodes == 0 then summary.reason = "no_nodes"; return nil, summary end

	local total = 0
	for i = 1, #liveNodes do
		local container = liveNodes[i].container
		local items = container and container.getItems and container:getItems() or nil
		if items and items.size then total = total + items:size() end
	end
	local registry = GlobalStorageSiK.Zones.getRegistry()
	return {
		networkId = networkId,
		liveNodes = liveNodes,
		zonePriorityOf = buildZonePriorityLookup(registry, networkId),
		phase = "index",
		nodeIndex = 1,
		itemIndex = 0,
		itemRefsByNode = {},
		typeCountsByNode = {},
		matchTiersByType = {},
		indexed = 0,
		processed = 0,
		total = total,
	}, summary
end

local function stepIndex(session, startedAt)
	local inspected = 0
	while session.nodeIndex <= #session.liveNodes
		and inspected < MAX_INDEX_ITEMS_PER_STEP
		and not timeBudgetExceeded(startedAt, inspected) do
		local nodeIndex = session.nodeIndex
		local live = session.liveNodes[nodeIndex]
		local container = live and live.container
		local items = container and container.getItems and container:getItems() or nil
		local size = items and items.size and items:size() or 0
		if session.itemIndex >= size then
			session.nodeIndex = nodeIndex + 1
			session.itemIndex = 0
		else
			local item = items:get(session.itemIndex)
			session.itemIndex = session.itemIndex + 1
			inspected = inspected + 1
			session.indexed = session.indexed + 1
			if item then
				session.itemRefsByNode[nodeIndex] = session.itemRefsByNode[nodeIndex] or {}
				local refs = session.itemRefsByNode[nodeIndex]
				refs[#refs + 1] = item
				local fullType = item.getFullType and item:getFullType() or nil
				updateTypeCount(session, nodeIndex, fullType, 1)
			end
		end
	end
	if session.nodeIndex > #session.liveNodes then
		session.phase = "move"
		session.nodeIndex = 1
		session.itemIndex = 1
	end
	return inspected
end

local function stepMoves(session, player, summary, startedAt)
	local inspected = 0
	local configured = tonumber(GlobalStorageSiK.Sandbox.getMaxItemsPerBulkTick()) or MAX_MOVES_PER_STEP
	-- Una opción dañada o antigua con 0 no puede dejar el cursor vivo para
	-- siempre. El techo local continúa prevaleciendo aunque Sandbox sea mayor.
	local maxMoves = math.max(1, math.min(configured, MAX_MOVES_PER_STEP))
	while session.nodeIndex <= #session.liveNodes
		and inspected < MAX_MOVE_ITEMS_PER_STEP
		and summary.moved < maxMoves
		and not timeBudgetExceeded(startedAt, inspected) do
		local nodeIndex = session.nodeIndex
		local refs = session.itemRefsByNode[nodeIndex] or {}
		if session.itemIndex > #refs then
			session.nodeIndex = nodeIndex + 1
			session.itemIndex = 1
		else
			local item = refs[session.itemIndex]
			session.itemIndex = session.itemIndex + 1
			inspected = inspected + 1
			session.processed = session.processed + 1
			local fromLive = session.liveNodes[nodeIndex]
			local container = fromLive and fromLive.container
			local fullType = item and item.getFullType and item:getFullType() or nil
			if item and container and container:contains(item) then
				local target, targetIndex = pickRedistributeTarget(item, nodeIndex, session, player)
				if target and target.container and target.container ~= container then
					if GlobalStorageSiK.InventorySync.moveBetween(container, target.container, item, player) then
						summary.moved = summary.moved + 1
						updateTypeCount(session, nodeIndex, fullType, -1)
						updateTypeCount(session, targetIndex, fullType, 1)
					else
						summary.failed = summary.failed + 1
					end
				else
					summary.skipped = summary.skipped + 1
				end
			else
				-- El mundo puede cambiar mientras el job cede tiempo a otros procesos.
				-- La referencia deja de procesarse y la caché se corrige sin perseguirla.
				summary.skipped = summary.skipped + 1
				updateTypeCount(session, nodeIndex, fullType, -1)
			end
		end
	end
	return inspected
end

--- Redistribuye una porción acotada de la red y conserva el cursor/cachés en
--- session. El job servidor debe devolver la misma session en la llamada
--- siguiente; así ninguna llamada vuelve a escanear la red desde el principio.
---@param player IsoPlayer
---@param networkId string|nil
---@param session table|nil
---@return table summary
---@return table|nil session
function GlobalStorageSiK.Redistribute.redistributeNetwork(player, networkId, session)
	local summary = { moved = 0, failed = 0, skipped = 0, checked = 0, total = 0, reason = nil }
	if session and session.networkId ~= networkId then session = nil end
	if not session then
		local initial
		session, initial = beginSession(player, networkId)
		if not session then return initial, nil end
	end
	if not GlobalStorageSiK.Sandbox.remoteTransferEnabled() then
		summary.reason = "remote_disabled"; return summary, session
	end
	if not GlobalStorageSiK.Power.networkPowered(networkId) then
		summary.reason = "no_power"; return summary, session
	end

	local startedAt = nowMs()
	if session.phase == "index" then
		stepIndex(session, startedAt)
	else
		stepMoves(session, player, summary, startedAt)
	end
	summary.phase = session.phase
	summary.checked = session.phase == "index" and session.indexed or session.processed
	summary.total = session.total
	if session.phase == "index" or session.nodeIndex <= #session.liveNodes then
		summary.reason = "limit"
	end
	return summary, session
end

--- Mensaje legible del resumen de redistribución.
---@param summary table|nil
---@return string
function GlobalStorageSiK.Redistribute.formatSummaryMessage(summary)
	summary = summary or {}
	-- Solo se llama desde codigo servidor (GS_RedistributeJob.lua) para
	-- construir el mensaje de un actionResult - I18n.remote (no .text) para
	-- que cada cliente lo resuelva en su propio idioma, ver GS_I18n.lua.
	local T = GlobalStorageSiK.I18n.remote
	if summary.reason == "remote_disabled" then
		return T("IGUI_GS_RedistributeFailRemoteDisabled")
	end
	if summary.reason == "no_power" then
		return T("IGUI_GS_RedistributeFailNoPower")
	end
	if summary.reason == "no_nodes" then
		return T("IGUI_GS_RedistributeFailNoNodes")
	end
	local moved = summary.moved or 0
	local failed = summary.failed or 0
	if summary.reason == "limit" then
		return T("IGUI_GS_RedistributeSummaryLimit", tostring(moved))
	end
	if moved == 0 and failed == 0 then
		return T("IGUI_GS_RedistributeSummaryNothing")
	end
	return T("IGUI_GS_RedistributeSummary", tostring(moved), tostring(failed))
end
