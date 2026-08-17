--[[
	GlobalStorageSiK - Reescaneo inteligente al abrir terminal
	Autor: SiK
	Fecha: 2025-06-23
	Descripción: Actualiza nodos de zona bajo demanda, sin polling continuo.
]]

require "GS_Zones"
require "GS_ZoneScanner"
require "GS_Sandbox"
require "GS_ZonePriority"
-- GS_Network.lua ya requiere este fichero (GS_ZoneRefresh) - NO se puede
-- añadir "require GS_Network" aqui arriba sin crear un require circular en
-- la carga inicial. GlobalStorageSiK.Network se usa mas abajo solo dentro
-- de funciones (en tiempo de ejecucion, no de carga), momento en el que ya
-- esta disponible sin falta.

GlobalStorageSiK.ZoneRefresh = {}

--- Lista zonas de red ordenadas por área ascendente (más específica primero).
---@param registry table
---@param networkId string
---@return table[]
local function sortedNetworkZones(registry, networkId)
	return GlobalStorageSiK.ZonePriority.listSorted(registry, networkId)
end

--- Fusiona contenedores detectados con el registro existente.
---@param registry table
---@param zone table
---@param detected table[]
---@param zoneAreaTiles number|nil
---@param zoneHadLoadedSquares boolean|nil false si la zona no tenía chunks cargados (no marcar offline)
---@return table summary
function GlobalStorageSiK.ZoneRefresh.mergeScanResults(registry, zone, detected, zoneAreaTiles, zoneHadLoadedSquares)
	registry.nodes = registry.nodes or {}
	local summary = { added = 0, updated = 0, offline = 0, limitHit = false, outOfRange = 0 }
	local myArea = zoneAreaTiles or GlobalStorageSiK.ZonePriority.zoneArea(zone)

	local maxNodes = GlobalStorageSiK.Sandbox.getMaxNodes()
	local existingCount = 0
	for _ in pairs(registry.nodes) do existingCount = existingCount + 1 end

	-- Contenedores demasiado lejos del terminal activo mas cercano de la red
	-- se descartan del escaneo (no se registran ni se actualizan). Una zona
	-- (habitacion/edificio/seleccion) puede seleccionar un area arbitraria,
	-- pero eso no debe permitir acceder a inventarios lejanos sin terminal
	-- fisico cerca - ver GS_Network.containerRangeEnabled/nearestTerminalDistance.
	local rangeEnabled = GlobalStorageSiK.Network.containerRangeEnabled(zone.networkId)
	local maxDist = rangeEnabled and GlobalStorageSiK.Sandbox.getContainerMaxDistance() or nil

	local detectedById = {}
	for i = 1, #detected do
		local entry = detected[i]
		if entry and entry.id then
			local include = true
			if maxDist then
				local d = GlobalStorageSiK.Network.nearestTerminalDistance(zone.networkId, entry.x, entry.y, entry.z)
				if d and d > maxDist then
					include = false
					summary.outOfRange = summary.outOfRange + 1
				end
			end
			if include then
				detectedById[entry.id] = entry
			end
		end
	end

	for id, entry in pairs(detectedById) do
		local existing = registry.nodes[id]
		if not existing then
			if existingCount + summary.added >= maxNodes then
				summary.limitHit = true
			else
				entry.membership = entry.membership or "auto"
				registry.nodes[id] = entry
				summary.added = summary.added + 1
			end
		else
			local existingZone = registry.zones and registry.zones[existing.zoneId]
			local existingArea = existingZone and GlobalStorageSiK.ZonePriority.zoneArea(existingZone) or math.huge
			if existing.zoneId == zone.id or myArea <= existingArea then
				existing.zoneId = zone.id
				existing.x = entry.x
				existing.y = entry.y
				existing.z = entry.z
				existing.name = entry.name
				existing.offline = false
				if existing.membership == "excluded" then
					existing.enabled = false
				elseif entry.enabled ~= false and existing.membership ~= "excluded" then
					existing.enabled = true
				end
				-- Solo sobrescribe si nunca tuvo nombre, o si sigue siendo el
				-- generico literal (nodos escaneados antes de la deteccion por
				-- tipo). Un nombre realmente personalizado por el jugador nunca
				-- se pisa: si el jugador ha renombrado el contenedor, displayName
				-- sera distinto de ambos.
				local T = GlobalStorageSiK.I18n and GlobalStorageSiK.I18n.text
				local generic = T and T("IGUI_GS_GenericContainerName") or "Contenedor"
				if existing.displayName == nil or existing.displayName == generic then
					existing.displayName = entry.displayName
				end
				if entry.itemSnapshot then
					existing.itemSnapshot = entry.itemSnapshot
				end
				if entry.storedCapacity then
					existing.storedCapacity = entry.storedCapacity
				end
				summary.updated = summary.updated + 1
			end
		end
	end

	if zoneHadLoadedSquares ~= false then
		for id, node in pairs(registry.nodes) do
			if node.zoneId == zone.id and not detectedById[id] then
				node.offline = true
				summary.offline = summary.offline + 1
			end
		end
	end

	zone.lastScanMs = getTimestampMs and getTimestampMs() or 0
	return summary
end

--- Reescanea una sola zona de la red.
---@param networkId string
---@param zoneId string
---@return table|nil summary
function GlobalStorageSiK.ZoneRefresh.refreshZone(networkId, zoneId)
	if not networkId or not zoneId or zoneId == "" then
		return nil
	end
	local registry = GlobalStorageSiK.Zones.getRegistry()
	local zone = registry.zones and registry.zones[zoneId]
	if not zone or zone.networkId ~= networkId or zone.enabled == false then
		return nil
	end
	local maxPerZone = GlobalStorageSiK.Sandbox.getMaxContainersPerZone()
	local detected, limitHit, zoneLoaded = GlobalStorageSiK.ZoneScanner.scanZone(zone, maxPerZone)
	if zoneLoaded then
		zone.everScanLoaded = true
	end
	local summary = GlobalStorageSiK.ZoneRefresh.mergeScanResults(
		registry, zone, detected, GlobalStorageSiK.ZonePriority.zoneArea(zone), zoneLoaded
	)
	-- Marca interna consumida por GS_Index al construir inmediatamente el
	-- terminalState: solo esta zona tiene snapshots recién capturados.
	summary._freshSnapshotScope = zoneId
	summary.limitHit = limitHit == true
	-- Un reescaneo actualiza snapshots autoritativos, pero no debe difundir el
	-- Global ModData completo (incluye todas las redes/nodos). GS_Server envia
	-- terminalState dirigido y RegistryStore persiste el catalogo por separado.
	if GlobalStorageSiK.RegistryStore and GlobalStorageSiK.RegistryStore.notifyChanged then
		GlobalStorageSiK.RegistryStore.notifyChanged()
	end
	return summary
end

--- Refresca todas las zonas de una red al abrir el terminal.
---@param networkId string
---@return table
function GlobalStorageSiK.ZoneRefresh.refreshNetworkOnTerminalOpen(networkId)
	local registry = GlobalStorageSiK.Zones.getRegistry()
	local totals = { added = 0, updated = 0, offline = 0, zones = 0, limitHit = false, outOfRange = 0 }
	local maxPerZone = GlobalStorageSiK.Sandbox.getMaxContainersPerZone()
	local zones = sortedNetworkZones(registry, networkId)

	for i = 1, #zones do
		local zone = zones[i]
		totals.zones = totals.zones + 1
		local detected, limitHit, zoneLoaded = GlobalStorageSiK.ZoneScanner.scanZone(zone, maxPerZone)
		if zoneLoaded then
			zone.everScanLoaded = true
		end
		local summary = GlobalStorageSiK.ZoneRefresh.mergeScanResults(
			registry, zone, detected, GlobalStorageSiK.ZonePriority.zoneArea(zone), zoneLoaded
		)
		totals.added = totals.added + summary.added
		totals.updated = totals.updated + summary.updated
		totals.offline = totals.offline + summary.offline
		totals.outOfRange = totals.outOfRange + (summary.outOfRange or 0)
		if limitHit then
			totals.limitHit = true
		end
	end

	if GlobalStorageSiK.RegistryStore and GlobalStorageSiK.RegistryStore.notifyChanged then
		GlobalStorageSiK.RegistryStore.notifyChanged()
	end

	-- Todas las zonas de esta red acaban de recorrer sus contenedores cargados.
	-- GS_Index puede reutilizar esas capturas sin repetir el mismo barrido.
	totals._freshSnapshotScope = "network"
	return totals
end

--- Devuelve nodos activos de una red (en zona, habilitados, no offline).
---@param networkId string
---@return table[]
function GlobalStorageSiK.ZoneRefresh.getActiveNodes(networkId)
	local registry = GlobalStorageSiK.Zones.getRegistry()
	local nodes = {}

	for _, node in pairs(registry.nodes or {}) do
		if node.membership == "excluded" then
			-- omitido de nodos activos
		elseif node.enabled ~= false and node.offline ~= true then
			local zone = registry.zones and registry.zones[node.zoneId]
			if zone and zone.enabled ~= false and zone.networkId == networkId then
				table.insert(nodes, node)
			end
		end
	end

	return nodes
end

--[[
	Política:
	- No hay polling continuo. Apertura, reescaneo y consolidación tras cambios
	  crean un GS_ZoneScanJob incremental con presupuesto temporal por red.
	- refreshNetworkOnTerminalOpen()/refreshZone() quedan como wrappers legacy;
	  GS_Server no los usa en el flujo normal porque son síncronos.
	- Un escaneo de inventario no transmite Global ModData completo: persiste la
	  captura y GS_Server envía terminalState solo a observadores de esa red.
	- Zonas solapadas: gana la de menor área (orden ascendente al escanear).
	- Contenedor en zona = accesible; offline solo si no se detecta en el último scan.
	- Configuración del jugador (nombre, reglas, enabled) persiste aunque esté offline.
]]
