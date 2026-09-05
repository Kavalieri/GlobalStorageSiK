--[[
	GlobalStorageSiK - Auto-ordenar (antes "Redistribución por categoría")
	Autor: SiK
	Fecha: 2025-06-25
	Descripción: Mueve ítems mal ubicados por categoría, afinidad exacta o
	afinidad taxonómica canónica; fallback controlado a «cualquiera».
]]

require "GS_Network"
require "GS_Router"
require "GS_InventorySync"
require "GS_Sandbox"
require "GS_Power"
require "GS_Zones"
require "GS_ZonePriority"
require "GS_I18n"
require "GS_CategoryResolution"
require "GS_OperationPacing"
require "GS_Permissions"

GlobalStorageSiK.Redistribute = {}

-- Presupuesto por paso del job. El límite interno acota MOVIMIENTOS en
-- depósitos normales, pero Auto Sort también debe limitar ítems INSPECCIONADOS:
-- una red ya ordenada podía recorrer miles de ítems contra todos los nodos en
-- un único tick porque moved seguía en cero. Dos movimientos por paso reducen
-- además los pares remove/add que el servidor debe replicar a los clientes.
local function nowMs()
	return getTimestampMs and getTimestampMs() or 0
end

local function timeBudgetExceeded(startedAt, inspected, pacing)
	if inspected <= 0 or startedAt <= 0 then return false end
	local current = nowMs()
	return current > 0 and current - startedAt >= (pacing.cpuBudgetMs or 5)
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
--- La especificidad/tier ya se compara antes de llamar a esta funcion.
--- Dentro del mismo tier: 1) zona, 2) contenedor, 3) ID estable - prioridad de
--- ZONA primero (2026-08-24, pedido explicito del usuario: "lo mas normal es
--- que el jugador no toque el campo de zona; si lo toca, es porque quiere que
--- primero se revise esa zona" - mas amplio/deliberado que un solo contenedor
--- cuando se configura, asi que decide antes). Esto hace que la prioridad
--- solo ordene candidatos equivalentes y nunca adelante una categoria
--- generica frente a una coincidencia o afinidad mejores.
---@param a table live entry candidato
---@param b table live entry candidato
---@param zonePriorityOf table<string, number>
---@return boolean
local function candidateBetter(a, b, zonePriorityOf)
	local ea, eb = a.entry or {}, b.entry or {}
	local za = zonePriorityOf[ea.zoneId] or tonumber(a.zonePriority) or tonumber(ea.zonePriority) or 50
	local zb = zonePriorityOf[eb.zoneId] or tonumber(b.zonePriority) or tonumber(eb.zonePriority) or 50
	if za ~= zb then return za < zb end
	local pa = tonumber(ea.priority) or 50
	local pb = tonumber(eb.priority) or 50
	if pa ~= pb then return pa < pb end
	return tostring(ea.id or "") < tostring(eb.id or "")
end

--- Compara candidatos SIN categoria/filtro configurado (familia "sin
--- restriccion", antes tiers 4/5/6 separados): aqui la PRIORIDAD (zona
--- primero, contenedor despues - mismo orden que candidateBetter arriba)
--- manda antes que la afinidad (pedido explicito del usuario, 2026-08-24 -
--- antes la afinidad exacta/taxonomica ganaba siempre y un contenedor nuevo
--- vacio con prioridad alta nunca podia atraer objetos de una estanteria
--- vieja que ya los contenia, porque esa estanteria se autocalificaba mejor
--- tier por afinidad consigo misma). La afinidad solo desempata entre
--- candidatos que comparten AMBAS prioridades (zona Y contenedor) - cambiar
--- la prioridad de un contenedor/zona SI afecta al resultado de la afinidad,
--- no es un criterio aislado. Mismo cambio en paralelo en GS_Router.lua
--- (unrestrictedDepositCandidateBetter) para que Auto-ordenar y el deposito
--- manual decidan igual.
---@param a table candidato { live=table, affinityTier=number }
---@param b table candidato { live=table, affinityTier=number }
---@param zonePriorityOf table<string, number>
---@return boolean
local function unrestrictedCandidateBetter(a, b, zonePriorityOf)
	local ea, eb = a.live.entry or {}, b.live.entry or {}
	local za = zonePriorityOf[ea.zoneId] or tonumber(a.live.zonePriority) or tonumber(ea.zonePriority) or 50
	local zb = zonePriorityOf[eb.zoneId] or tonumber(b.live.zonePriority) or tonumber(eb.zonePriority) or 50
	if za ~= zb then return za < zb end
	local pa = tonumber(ea.priority) or 50
	local pb = tonumber(eb.priority) or 50
	if pa ~= pb then return pa < pb end
	if a.affinityTier ~= b.affinityTier then return a.affinityTier < b.affinityTier end
	return tostring(ea.id or "") < tostring(eb.id or "")
end

--- Cachea el tier por fullType+nodo solo si el nodo no tiene filtros/reglas
--- personalizados NI su zona tiene reglas propias. Categorías/subcategorías
--- dependen del tipo de script y son estables; nombre/peso/tag (en filtros
--- legacy o en el motor unificado entry.rules/zone.rules, dev26) pueden
--- depender de la instancia concreta del item y se reevalúan siempre.
local function cachedMatchTier(session, nodeIndex, item, fullType)
	local live = session.liveNodes[nodeIndex]
	local entry = live and live.entry or {}
	local zoneRules = live and live.zoneRules
	local zoneEnabled = live and live.zoneEnabled
	local hasInstanceDependentRules = (entry.filters and #entry.filters > 0)
		or (entry.rules and #entry.rules > 0)
		or (zoneRules and #zoneRules > 0)
	if hasInstanceDependentRules or not fullType then
		return GlobalStorageSiK.Router.matchWithZoneGate(entry, zoneRules, zoneEnabled, item)
	end
	local byNode = session.matchTiersByType[fullType]
	if not byNode then
		byNode = {}
		session.matchTiersByType[fullType] = byNode
	end
	local cached = byNode[nodeIndex]
	if cached ~= nil then return cached ~= false and cached or nil end
	local tier = GlobalStorageSiK.Router.matchWithZoneGate(entry, zoneRules, zoneEnabled, item)
	byNode[nodeIndex] = tier or false
	return tier
end

--- Elige el MEJOR contenedor destino para un item, comparando TODOS los
--- candidatos validos (no el primero que encaje). Usa la MISMA
--- especificidad de categorias que GS_Router.pickDepositTarget
--- (matchSpecificity: 1=hoja exacta, 2=Nivel 2, 3=Nivel 1, 4=sin
--- restriccion), expandiendo el ultimo caso igual que Router: 4=sin
--- restriccion con el mismo fullType, 5=misma ruta taxonomica y 6=sin
--- restriccion cualquiera.
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
	local bestUnrestricted = nil
	local compatible = false
	local fullType = item.getFullType and item:getFullType() or nil
	local strictNoMatch = GlobalStorageSiK.Sandbox.rejectDepositIfNoMatch
		and GlobalStorageSiK.Sandbox.rejectDepositIfNoMatch()
	local affinityIndex = {
		exactByNode = session.typeCountsByNode,
		taxonomyByNode = session.affinityCountsByNode,
	}
	for i = 1, #liveNodes do
		local live = liveNodes[i]
		local matchTier = not live.unavailable and cachedMatchTier(session, i, item, fullType)
		if matchTier and not (session.sourceNodeId and live.container == fromLive.container) then
			local isSelf = (live.container == fromLive.container)
			local affinityTier = matchTier >= 4 and GlobalStorageSiK.Router.unrestrictedAffinityTier(
				item, i, affinityIndex, isSelf) or nil
			local allowed = matchTier < 4 or affinityTier < 6 or not strictNoMatch
			if allowed then compatible = true end
			local hasSpace = isSelf or GlobalStorageSiK.Router.containerHasSpace(live.container, item, character)
			if hasSpace and allowed then
				if matchTier < 4 then
					-- Categoria/filtro configurado a mano: sin cambios, sigue
					-- ganando siempre a la familia "sin restriccion" de abajo.
					local current = bestByTier[matchTier]
					if not current or candidateBetter(live, current.live, session.zonePriorityOf) then
						bestByTier[matchTier] = { live = live, index = i }
					end
				else
					-- Sin categoria configurada: la prioridad del contenedor
					-- manda, la afinidad solo desempata (ver unrestrictedCandidateBetter).
					if affinityTier < 6 or not strictNoMatch then
						local candidate = { live = live, index = i, affinityTier = affinityTier }
						if not bestUnrestricted
							or unrestrictedCandidateBetter(candidate, bestUnrestricted, session.zonePriorityOf) then
							bestUnrestricted = candidate
						end
					end
				end
			end
		end
	end

	for tierIdx = 1, 3 do
		local best = bestByTier[tierIdx]
		if best then
			if best.live.container == fromLive.container then
				return nil, nil, nil
			end
			return best.live, best.index, tierIdx
		end
	end
	if bestUnrestricted then
		if bestUnrestricted.live.container == fromLive.container then
			return nil, nil, nil
		end
		return bestUnrestricted.live, bestUnrestricted.index, bestUnrestricted.affinityTier
	end
	return nil, nil, nil, compatible and "destination_full" or "no_compatible_destination"
end

local function incrementSummaryCount(counts, key)
	if not counts or key == nil then return end
	key = tostring(key)
	counts[key] = (counts[key] or 0) + 1
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

local function updateAffinityCount(session, nodeIndex, item, delta)
	local fullType = item and item.getFullType and item:getFullType() or nil
	local resolved = GlobalStorageSiK.CategoryResolution.resolve(fullType, nil, item)
	local affinityKey = resolved and resolved.routingIdentity
	if not affinityKey then return end
	local counts = session.affinityCountsByNode[nodeIndex]
	if not counts then
		counts = {}
		session.affinityCountsByNode[nodeIndex] = counts
	end
	counts[affinityKey] = math.max(0, (counts[affinityKey] or 0) + delta)
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
		affinityCountsByNode = {},
		matchTiersByType = {},
		indexed = 0,
		processed = 0,
		total = total,
	}, summary
end

-- A job yields between batches. Re-resolve membership, permissions, rules and
-- physical identity before using its captured item references again.
local function revalidateSession(session, player)
	if not GlobalStorageSiK.Permissions.canAccess(player, session.networkId) then return "no_permission" end
	if GlobalStorageSiK.Permissions.shouldEnforce()
		and not GlobalStorageSiK.Permissions.isAdminPlayer(player, session.networkId) then return "no_permission" end
	local registry = GlobalStorageSiK.Zones.getRegistry()
	local sourceFound = not session.sourceNodeId
	session.matchTiersByType = {}
	session.zonePriorityOf = buildZonePriorityLookup(registry, session.networkId)
	for i = 1, #session.liveNodes do
		local live = session.liveNodes[i]
		local entry = live.entry and registry.nodes and registry.nodes[live.entry.id]
		local zone = entry and registry.zones and registry.zones[entry.zoneId]
		local allowed = entry and zone and zone.networkId == session.networkId
			and entry.enabled ~= false and entry.membership ~= "excluded" and zone.enabled ~= false
			and GlobalStorageSiK.Permissions.canAccessZone(player, session.networkId, entry.zoneId)
		if allowed then
			local object = GlobalStorageSiK.Network.findWorldObject(entry)
			allowed = object and GlobalStorageSiK.Utils.getObjectContainer(object, entry.containerIndex) == live.container
				and GlobalStorageSiK.Utils.isNetworkStorageContainer(object, entry.containerIndex)
		end
		live.unavailable = not allowed
		if allowed then
			live.entry, live.zoneRules, live.zoneEnabled = entry, zone.rules, true
			live.zonePriority = zone.priority
			if entry.id == session.sourceNodeId then sourceFound = true end
		end
	end
	if not sourceFound then return "source_unavailable" end
	return nil
end

local function stepIndex(session, startedAt, pacing)
	local inspected = 0
	while session.nodeIndex <= #session.liveNodes
		and inspected < (pacing.indexItemsPerStep or 50)
		and not timeBudgetExceeded(startedAt, inspected, pacing) do
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
				updateAffinityCount(session, nodeIndex, item, 1)
			end
		end
	end
	if session.nodeIndex > #session.liveNodes then
		session.phase = "move"
		session.nodeIndex = 1
		session.itemIndex = 1
	end
	return inspected, timeBudgetExceeded(startedAt, inspected, pacing)
end

local function stepMoves(session, player, summary, startedAt, pacing)
	local inspected = 0
	local maxMoves = pacing.maxMovesPerStep or 2
	while session.nodeIndex <= #session.liveNodes
		and inspected < (pacing.inspectedPerStep or 25)
		and summary.moved < maxMoves
		and not timeBudgetExceeded(startedAt, inspected, pacing) do
		local nodeIndex = session.nodeIndex
		local refs = session.itemRefsByNode[nodeIndex] or {}
		if session.liveNodes[nodeIndex].unavailable or (session.sourceNodeId
			and (not session.liveNodes[nodeIndex].entry
			or session.liveNodes[nodeIndex].entry.id ~= session.sourceNodeId)) then refs = {} end
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
				local target, targetIndex, targetTier, targetReason = pickRedistributeTarget(item, nodeIndex, session, player)
				if target and target.container and target.container ~= container then
					if GlobalStorageSiK.InventorySync.moveBetween(container, target.container, item, player) then
						summary.moved = summary.moved + 1
						summary.movedByTier = summary.movedByTier or {}
						summary.movedByType = summary.movedByType or {}
						incrementSummaryCount(summary.movedByTier, targetTier or "?")
						incrementSummaryCount(summary.movedByType, fullType or "?")
						updateTypeCount(session, nodeIndex, fullType, -1)
						updateTypeCount(session, targetIndex, fullType, 1)
						updateAffinityCount(session, nodeIndex, item, -1)
						updateAffinityCount(session, targetIndex, item, 1)
					else
						summary.failed = summary.failed + 1
					end
				else
					summary.skipped = summary.skipped + 1
					if session.sourceNodeId then
						summary.blockedReason = targetReason
						summary.blocked = (summary.blocked or 0) + 1
					end
				end
			else
				-- El mundo puede cambiar mientras el job cede tiempo a otros procesos.
				-- La referencia deja de procesarse y la caché se corrige sin perseguirla.
				summary.skipped = summary.skipped + 1
				updateTypeCount(session, nodeIndex, fullType, -1)
				updateAffinityCount(session, nodeIndex, item, -1)
			end
		end
	end
	return inspected, timeBudgetExceeded(startedAt, inspected, pacing)
end

--- Redistribuye una porción acotada de la red y conserva el cursor/cachés en
--- session. El job servidor debe devolver la misma session en la llamada
--- siguiente; así ninguna llamada vuelve a escanear la red desde el principio.
---@param player IsoPlayer
---@param networkId string|nil
---@param session table|nil
---@return table summary
---@return table|nil session
function GlobalStorageSiK.Redistribute.redistributeNetwork(player, networkId, session, pacing, options)
	local summary = { moved = 0, failed = 0, skipped = 0, checked = 0, total = 0, reason = nil }
	if session and session.networkId ~= networkId then session = nil end
	if not session then
		local initial
		session, initial = beginSession(player, networkId)
		if not session then return initial, nil end
		session.pacing = pacing or GlobalStorageSiK.OperationPacing.resolve({ operationType = "autosort" })
		session.sourceNodeId = options and options.sourceNodeId or nil
	end
	local effectivePacing = session.pacing
		or pacing or GlobalStorageSiK.OperationPacing.resolve({ operationType = "autosort" })
	session.pacing = effectivePacing
	if not GlobalStorageSiK.Sandbox.remoteTransferEnabled() then
		summary.reason = "remote_disabled"; return summary, session
	end
	if not GlobalStorageSiK.Power.networkPowered(networkId) then
		summary.reason = "no_power"; return summary, session
	end
	local invalid = revalidateSession(session, player)
	if invalid then summary.reason = invalid; return summary, session end

	local startedAt = nowMs()
	local inspected, budgetExhausted
	if session.phase == "index" then
		inspected, budgetExhausted = stepIndex(session, startedAt, effectivePacing)
	else
		inspected, budgetExhausted = stepMoves(session, player, summary, startedAt, effectivePacing)
	end
	summary.inspected = inspected or 0
	summary.budgetExhaustions = budgetExhausted and 1 or 0
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
