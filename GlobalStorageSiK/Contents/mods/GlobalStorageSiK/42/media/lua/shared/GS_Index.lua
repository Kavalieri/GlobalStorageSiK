--[[
	GlobalStorageSiK - Índice agregado de la red
	Autor: SiK
	Fecha: 2025-06-23
	Descripción: Construye índice por tipo de ítem para búsqueda y terminal.
]]

require "GS_Network"
require "GS_Router"
require "GS_Zones"
require "GS_ItemSnapshot"
require "GS_ZoneRefresh"
require "GS_ItemTaxonomy"
require "GS_Permissions"

GlobalStorageSiK.Index = {}

--- Fusiona filas de contenedor vivo en el mapa por tipo.
---@param byType table<string, table>
---@param container ItemContainer
---@param nodeId string
local function mergeLiveContainer(byType, container, nodeId)
	if not container then
		return
	end
	local snap = GlobalStorageSiK.ItemSnapshot.fromContainer(container)
	for fullType, row in pairs(snap) do
		local existing = byType[fullType]
		if not existing then
			byType[fullType] = {
				fullType = row.fullType,
				displayName = row.displayName,
				worldSprite = row.worldSprite,
				category = row.category,
				subCategory = row.subCategory,
				gsSubKeys = row.gsSubKeys or {},
				gsSubKeysStr = row.gsSubKeysStr or "",
				count = row.count,
				nodeId = nodeId,
			}
		else
			existing.count = existing.count + row.count
		end
	end
end

--- Fusiona snapshot persistido de un nodo.
---@param byType table<string, table>
---@param node table
local function mergeNodeSnapshot(byType, node)
	if not node or not node.itemSnapshot then
		return
	end
	for fullType, row in pairs(node.itemSnapshot) do
		local existing = byType[fullType]
		if not existing then
			byType[fullType] = {
				fullType = row.fullType,
				displayName = row.displayName,
				worldSprite = row.worldSprite,
				category = row.category,
				subCategory = row.subCategory,
				gsSubKeys = row.gsSubKeys or {},
				gsSubKeysStr = row.gsSubKeysStr or "",
				count = row.count or 0,
				nodeId = node.id,
			}
		else
			existing.count = (existing.count or 0) + (row.count or 0)
		end
	end
end

--- Construye índice serializable para el cliente.
---@param networkId string|nil
---@param player IsoPlayer|nil limita el indice a sus zonas autorizadas
---@param freshSnapshotScope string|nil "network" o zoneId cuyo snapshot acaba de actualizarse
---@return table rows Lista ordenada { fullType, displayName, category, count, nodeId }
function GlobalStorageSiK.Index.buildRows(networkId, player, freshSnapshotScope)
	local registry = GlobalStorageSiK.Zones.getRegistry()
	networkId = networkId or GlobalStorageSiK.Network.getDefaultNetworkId()
	local byType = {}
	local liveIds = {}

	local live = GlobalStorageSiK.Permissions.filterLiveContainers(
		player, networkId, GlobalStorageSiK.Network.getLiveContainers(networkId))
	for i = 1, #live do
		local liveEntry = live[i]
		local nodeId = liveEntry.entry and liveEntry.entry.id or ("node_" .. i)
		liveIds[nodeId] = true
		local node = registry.nodes and registry.nodes[nodeId]
		local snapshotAvailable = node and node.itemSnapshot
		if snapshotAvailable then
			-- El snapshot persistido es la fuente de lectura del terminal. Abrir,
			-- buscar o editar configuración no debe volver a recorrer miles de
			-- InventoryItem. Un reescaneo incremental actualiza esta captura y al
			-- terminar envía el estado fresco solo a observadores de la red.
			mergeNodeSnapshot(byType, node)
		else
			-- Compatibilidad inicial/legacy: solo un nodo que aún no tenga captura
			-- paga una lectura viva. El siguiente scan lo deja cacheado.
			mergeLiveContainer(byType, liveEntry.container, nodeId)
		end
	end

	for _, node in pairs(registry.nodes or {}) do
		local zone = registry.zones and registry.zones[node.zoneId]
		if zone and zone.networkId == networkId and node.membership ~= "excluded" and node.enabled ~= false and node.offline ~= true
			and (not player or GlobalStorageSiK.Permissions.canAccessZone(player, networkId, node.zoneId)) then
			if not liveIds[node.id] then
				mergeNodeSnapshot(byType, node)
			end
		end
	end

	return GlobalStorageSiK.ItemSnapshot.toRows(byType)
end

--- Actualiza itemSnapshot de nodos con contenedores vivos (servidor tras transferencias).
---@param networkId string|nil
function GlobalStorageSiK.Index.syncLiveSnapshots(networkId)
	-- En SP real la autoridad vive en este proceso aunque isServer() sea
	-- false. El mismo contrato se usa para dedicado y host.
	if not GlobalStorageSiK.isAuthoritative() then
		return
	end
	networkId = networkId or GlobalStorageSiK.Network.getDefaultNetworkId()
	if not networkId then
		return
	end
	local registry = GlobalStorageSiK.Zones.getRegistry()
	if not registry or not registry.nodes then
		return
	end
	local live = GlobalStorageSiK.Network.getLiveContainers(networkId)
	for i = 1, #live do
		local entry = live[i].entry
		local container = live[i].container
		if entry and entry.id and container then
			local node = registry.nodes[entry.id]
			if node then
				local ok, snap = pcall(GlobalStorageSiK.ItemSnapshot.fromContainer, container)
				if ok and snap then
					node.itemSnapshot = snap
				end
			end
		end
	end
end

--- Incrementa revisión de inventario de la red (servidor).
---@param networkId string|nil
---@param transmitModData boolean|nil si false, no llama ModData.transmit
---@return number revision
function GlobalStorageSiK.Index.bumpInventoryRevision(networkId, transmitModData)
	networkId = networkId or GlobalStorageSiK.Network.getDefaultNetworkId()
	if not networkId then
		return 0
	end
	local registry = GlobalStorageSiK.Network.getRegistry()
	GlobalStorageSiK.Network.ensureRegistry(registry)
	registry._inventoryRevision = registry._inventoryRevision or {}
	local rev = (registry._inventoryRevision[networkId] or 0) + 1
	registry._inventoryRevision[networkId] = rev
	if transmitModData ~= false and isServer and isServer() and ModData and ModData.transmit and GlobalStorageSiK.MODDATA_KEY then
		ModData.transmit(GlobalStorageSiK.MODDATA_KEY)
	end
	return rev
end

--- Revisión actual del inventario agregado de la red.
---@param networkId string|nil
---@return number
function GlobalStorageSiK.Index.getInventoryRevision(networkId)
	networkId = networkId or GlobalStorageSiK.Network.getDefaultNetworkId()
	if not networkId then
		return 0
	end
	local registry = GlobalStorageSiK.Network.getRegistry()
	GlobalStorageSiK.Network.ensureRegistry(registry)
	registry._inventoryRevision = registry._inventoryRevision or {}
	return registry._inventoryRevision[networkId] or 0
end

--- Revisión hasta la que los snapshots persistidos representan una captura
--- completa y estable de la red. No debe adelantarse al inventoryRevision:
--- una transferencia incrementa este último inmediatamente, mientras que el
--- snapshot se consolida después mediante ZoneScanJob.
---@param networkId string|nil
---@param revision number|nil
---@return number
function GlobalStorageSiK.Index.setSnapshotRevision(networkId, revision)
	networkId = networkId or GlobalStorageSiK.Network.getDefaultNetworkId()
	if not networkId then
		return 0
	end
	local registry = GlobalStorageSiK.Network.getRegistry()
	GlobalStorageSiK.Network.ensureRegistry(registry)
	registry._snapshotRevision = registry._snapshotRevision or {}
	local stableRevision = math.max(0, math.floor(tonumber(revision) or 0))
	registry._snapshotRevision[networkId] = stableRevision
	return stableRevision
end

--- Revisión de la última captura completa y estable de la red.
---@param networkId string|nil
---@return number
function GlobalStorageSiK.Index.getSnapshotRevision(networkId)
	networkId = networkId or GlobalStorageSiK.Network.getDefaultNetworkId()
	if not networkId then
		return 0
	end
	local registry = GlobalStorageSiK.Network.getRegistry()
	GlobalStorageSiK.Network.ensureRegistry(registry)
	registry._snapshotRevision = registry._snapshotRevision or {}
	return registry._snapshotRevision[networkId] or 0
end

--- Cuenta cuántas unidades de un fullType tiene el jugador en cada red
--- accesible (para tooltip global "cuántos tengo en mi red"). Agrupa
--- variantes de sabor/color del mismo item base (Crisps/Crisps2/Crisps3...,
--- ver GlobalStorageSiK.ItemTaxonomy.getVariantFamilyKey): al explorar solo
--- nos interesa saber si tenemos "patatas fritas" en total, sin importar el
--- sabor concreto. La pestaña Almacen sigue mostrando cada fullType exacto
--- por separado (no usa esta funcion para sus filas, solo para su tooltip).
---@param player IsoPlayer
---@param fullType string
---@return table[], boolean out { name, count } ordenado por nombre; hasAnyNetwork indica si el jugador tiene AL MENOS una red accesible (para distinguir, en el tooltip, "no tienes redes todavia" de "tienes redes pero este item no esta en ninguna")
function GlobalStorageSiK.Index.getNetworkCountsForItem(player, fullType)
	if not player or not fullType or not GlobalStorageSiK.Network then
		return {}, false
	end
	local familyKey = GlobalStorageSiK.ItemTaxonomy and GlobalStorageSiK.ItemTaxonomy.getVariantFamilyKey
		and GlobalStorageSiK.ItemTaxonomy.getVariantFamilyKey(fullType) or fullType
	local registry = GlobalStorageSiK.Network.getRegistry()
	GlobalStorageSiK.Network.ensureRegistry(registry)
	local out = {}
	local hasAnyNetwork = false
	for networkId, net in pairs(registry.networks or {}) do
		local allowed = select(1, GlobalStorageSiK.Permissions.canAccess(player, networkId))
		if allowed and net then
			hasAnyNetwork = true
			local total = 0
			for _, node in pairs(registry.nodes or {}) do
				local zone = registry.zones and registry.zones[node.zoneId]
				if zone and zone.networkId == networkId and node.membership ~= "excluded"
						and node.enabled ~= false and node.offline ~= true then
					local snapshot = node.itemSnapshot
					if snapshot then
						for rowType, row in pairs(snapshot) do
							if GlobalStorageSiK.ItemTaxonomy.getVariantFamilyKey(rowType) == familyKey then
								total = total + (row.count or 0)
							end
						end
					end
				end
			end
			if total > 0 then
				out[#out + 1] = { id = networkId, name = net.name or networkId, count = total }
			end
		end
	end
	table.sort(out, function(a, b) return a.name < b.name end)
	return out, hasAnyNetwork
end

--- Filtra filas por texto de búsqueda (servidor / inglés en snapshot).
--- En cliente preferir `GlobalStorageSiK.I18n.filterItemRows` para idioma del jugador.
---@param rows table[]
---@param query string|nil
---@return table[]
function GlobalStorageSiK.Index.filterRows(rows, query)
	if not query or query == "" then
		return rows
	end
	local asciiLower = GlobalStorageSiK.I18n and GlobalStorageSiK.I18n.asciiLower or string.lower
	local q = asciiLower(query)
	local filtered = {}
	for i = 1, #rows do
		local row = rows[i]
		local name = asciiLower(row.displayName or "")
		local cat = asciiLower(row.category or "")
		local typ = asciiLower(row.fullType or "")
		if string.find(name, q, 1, true) or string.find(cat, q, 1, true) or string.find(typ, q, 1, true) then
			table.insert(filtered, row)
		end
	end
	return filtered
end
