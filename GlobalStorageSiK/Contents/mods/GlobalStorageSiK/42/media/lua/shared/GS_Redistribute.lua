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

--- Indica si el nodo acepta cualquier categoría (sin reglas o solo *).
---@param entry table|nil
---@return boolean
local function nodeIsAnyCategory(entry)
	if not entry then
		return true
	end
	local rules = entry.categories
	if not rules or #rules == 0 then
		return true
	end
	if #rules == 1 and rules[1] == "*" then
		return true
	end
	return false
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
--- candidatos validos (no el primero que encaje). Dos bolsas separadas:
--- "specific" (nodos cuya categoria/subcategoria acepta este item concreto)
--- y "catchAll" (nodos sin restriccion de categoria). Se usa "specific" si
--- hay al menos un candidato ahi (con hueco); si no, cae a "catchAll". El
--- propio nodo de origen se incluye en su bolsa correspondiente (con hueco
--- garantizado) para poder compararlo de tu a tu contra el resto: si ya es
--- el mejor, no se mueve nada.
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

	local specific, catchAll = {}, {}
	for i = 1, #liveNodes do
		local live = liveNodes[i]
		local isSelf = (live.container == fromLive.container)
		local hasSpace = isSelf or GlobalStorageSiK.Router.containerHasSpace(live.container, item, character)
		if hasSpace then
			if nodeIsAnyCategory(live.entry) then
				catchAll[#catchAll + 1] = live
			elseif GlobalStorageSiK.Router.nodeAcceptsItem(live.entry, item) then
				specific[#specific + 1] = live
			end
		end
	end

	-- Afinidad "mismo item, mismo contenedor" (misma regla que
	-- GS_Router.pickDepositTarget para el arrastre/deposito manual - antes
	-- Auto-ordenar tenia su propia logica sin afinidad, asi que un click
	-- podia enviar TODOS los items sin categoria configurada al mismo
	-- contenedor "cualquiera" solo por ser el primero en prioridad/zona).
	-- Solo se aplica dentro de catchAll (nodos sin restriccion): una
	-- categoria o filtro configurado a mano por el jugador sigue ganando
	-- siempre, esto no lo pisa.
	if #specific == 0 and #catchAll > 0 then
		local fullType = item.getFullType and item:getFullType() or nil
		if fullType then
			for i = 1, #catchAll do
				local live = catchAll[i]
				if live.container ~= fromLive.container
					and GlobalStorageSiK.Router.containerHasItemType(live.container, fullType) then
					return live
				end
			end
		end
	end

	local pool = (#specific > 0) and specific or catchAll
	if #pool == 0 then
		return nil
	end

	table.sort(pool, function(a, b) return candidateBetter(a, b, zonePriorityOf) end)
	local best = pool[1]
	if best.container == fromLive.container then
		return nil
	end
	return best
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
	local T = GlobalStorageSiK.I18n.text
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
