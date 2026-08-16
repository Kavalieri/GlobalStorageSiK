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

--- Copia ítems de un contenedor a una tabla (evita mutar durante iteración).
---@param container ItemContainer
---@return InventoryItem[]
local function snapshotContainerItems(container)
	local list = {}
	if not container or not container.getItems then
		return list
	end
	local items = container:getItems()
	if not items or not items.size then
		return list
	end
	for i = 0, items:size() - 1 do
		local item = items:get(i)
		if item then
			list[#list + 1] = item
		end
	end
	return list
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
---@param fromLive table
---@param liveNodes table[]
---@param character IsoPlayer|nil
---@param zonePriorityOf table<string, number>
---@return table|nil
local function pickRedistributeTarget(item, fromLive, liveNodes, character, zonePriorityOf)
	if not item or not fromLive or not liveNodes then
		return nil
	end

	local tiers = { {}, {}, {}, {}, {} }
	local fullType = item.getFullType and item:getFullType() or nil
	for i = 1, #liveNodes do
		local live = liveNodes[i]
		local isSelf = (live.container == fromLive.container)
		local hasSpace = isSelf or GlobalStorageSiK.Router.containerHasSpace(live.container, item, character)
		if hasSpace then
			local matchTier = GlobalStorageSiK.Router.matchSpecificity(live.entry or {}, item)
			local destinationTier = matchTier
			if matchTier == 4 then
				destinationTier = fullType and GlobalStorageSiK.Router.containerHasItemType(live.container, fullType) and 4 or 5
			end
			if destinationTier then
				tiers[destinationTier][#tiers[destinationTier] + 1] = live
			end
		end
	end

	for tierIdx = 1, 5 do
		local pool = tiers[tierIdx]
		if #pool > 0 then
			table.sort(pool, function(a, b) return candidateBetter(a, b, zonePriorityOf) end)
			local best = pool[1]
			if best.container == fromLive.container then
				return nil
			end
			return best
		end
	end
	return nil
end

--- Redistribuye ítems de la red según categorías de nodos.
---@param player IsoPlayer
---@param networkId string|nil
---@return table summary
function GlobalStorageSiK.Redistribute.redistributeNetwork(player, networkId)
	local summary = { moved = 0, failed = 0, skipped = 0, reason = nil }
	if not player then
		summary.reason = "no_player"
		return summary
	end
	if not GlobalStorageSiK.Sandbox.remoteTransferEnabled() then
		summary.reason = "remote_disabled"
		return summary
	end
	if not GlobalStorageSiK.Power.networkPowered(networkId) then
		summary.reason = "no_power"
		return summary
	end

	local liveNodes = GlobalStorageSiK.Network.getLiveContainers(networkId)
	if #liveNodes == 0 then
		summary.reason = "no_nodes"
		return summary
	end

	local registry = GlobalStorageSiK.Zones.getRegistry()
	local zonePriorityOf = buildZonePriorityLookup(registry, networkId)
	local maxPerTick = GlobalStorageSiK.Sandbox.getMaxItemsPerBulkTick()

	for i = 1, #liveNodes do
		if summary.moved >= maxPerTick then
			summary.reason = "limit"
			break
		end
		local fromLive = liveNodes[i]
		local container = fromLive.container
		if not container then
			summary.skipped = summary.skipped + 1
		else
			local items = snapshotContainerItems(container)
			for j = 1, #items do
				if summary.moved >= maxPerTick then
					summary.reason = "limit"
					break
				end
				local item = items[j]
				if item and container:contains(item) then
					local target = pickRedistributeTarget(item, fromLive, liveNodes, player, zonePriorityOf)
					if target and target.container and target.container ~= container then
						if GlobalStorageSiK.InventorySync.moveBetween(container, target.container, item, player) then
							summary.moved = summary.moved + 1
						else
							summary.failed = summary.failed + 1
						end
					else
						summary.skipped = summary.skipped + 1
					end
				end
			end
		end
	end

	return summary
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
