--[[
	GlobalStorageSiK - Capacidad de peso de la red
	Autor: SiK
	Fecha: 2025-06-23
	Descripción: Calcula peso usado y capacidad total de contenedores de la red.
]]

require "GS_Config"
require "GS_Network"
require "GS_Zones"
require "GS_ItemSnapshot"
require "GS_Log"
require "GS_I18n"

GlobalStorageSiK.NetworkCapacity = {}

--- Obtiene peso y capacidad de un contenedor vivo. Si se pasa `player`,
--- ademas devuelve el bonus personal REAL de ese jugador sobre este
--- contenedor (rasgos como Organizado/Packmule, vía la misma API vanilla
--- getEffectiveCapacity(character) que ya usa container:hasRoomFor(character,
--- item) para decidir si un deposito cabe de verdad - ver GS_InventorySync.lua
--- containerHasRoom). No inventamos ningun porcentaje propio: leemos
--- exactamente la misma cifra que el motor ya usa para decidir si algo cabe,
--- asi que el numero mostrado coincide siempre con el limite real aplicado.
---@param container ItemContainer
---@param player IsoPlayer|nil
---@return number used
---@return number|nil capacity
---@return number personalBonus  -- 0 si no hay player o el contenedor no expone getEffectiveCapacity
local function readContainerWeights(container, player)
	if not container then
		return 0, nil, 0
	end
	local used = 0
	local capacity = nil
	local personalBonus = 0
	if container.getWeight then
		local ok, w = pcall(function()
			return container:getWeight()
		end)
		if ok and w then
			used = w
		end
	end
	if used <= 0 and container.getContentsWeight then
		local okAlt, wAlt = pcall(function()
			return container:getContentsWeight()
		end)
		if okAlt and wAlt and wAlt > 0 then
			used = wAlt
		end
	end
	if used <= 0 and container.getItems then
		local okItems, items = pcall(function()
			return container:getItems()
		end)
		if okItems and items and items:size() > 0 then
			used = GlobalStorageSiK.NetworkCapacity.estimateSnapshotWeight(
				GlobalStorageSiK.ItemSnapshot.fromContainer(container)
			)
		end
	end
	if container.getCapacity then
		local okCap, cap = pcall(function()
			return container:getCapacity()
		end)
		if okCap and cap and cap > 0 then
			capacity = cap
			if player and container.getEffectiveCapacity then
				local okEff, effective = pcall(function()
					return container:getEffectiveCapacity(player)
				end)
				if okEff and effective and effective > cap then
					personalBonus = effective - cap
				end
			end
		end
	end
	return used, capacity, personalBonus
end

--- Estima el peso de un snapshot por tipo de ítem.
---@param snapshot table<string, table>|nil
---@return number
function GlobalStorageSiK.NetworkCapacity.estimateSnapshotWeight(snapshot)
	if not snapshot then
		return 0
	end
	local total = 0
	for fullType, row in pairs(snapshot) do
		local count = row.count or 1
		local unit = 0.1
		-- BUG REAL cerrado (2026-08-22, misma clase que GS_Categories.lua -
		-- sm:getItem(fullType) SIN CACHE por cada tipo distinto de un
		-- snapshot, en cada calculo de capacidad): usar el cache de sesion
		-- compartido (GlobalStorageSiK.I18n.getScriptItem) en vez de
		-- consultar ScriptManager a pelo.
		if GlobalStorageSiK.I18n and GlobalStorageSiK.I18n.getScriptItem then
			local ok, w = pcall(function()
				local script = GlobalStorageSiK.I18n.getScriptItem(fullType)
				if script and script.getActualWeight then
					return script:getActualWeight()
				end
				if script and script.getWeight then
					return script:getWeight()
				end
				return 0.1
			end)
			if ok and w then
				unit = w
			end
		end
		total = total + unit * count
	end
	return total
end

--- Acumula peso/capacidad de un nodo (vivo, offline o sin chunk).
--- Devuelve ADEMAS el peso usado y la capacidad EFECTIVA (ya con bonus
--- personal sumado) de ESTE nodo en concreto - dev26 ronda 4bis, para que
--- compute() pueda construir un desglose por-nodo/por-zona (columna
--- "% Ocupación" de la lista) SIN releer contenedores en vivo una segunda
--- vez; son exactamente los mismos numeros que ya calculaba para el
--- agregado de red, solo que ahora tambien se devuelven.
---@param totals table
---@param node table
---@param liveEntry table|nil
---@param player IsoPlayer|nil  -- si se pasa, suma tambien su bonus personal real (Organizado/etc.)
---@return number used
---@return number|nil effectiveCapacity
local function accumulateNode(totals, node, liveEntry, player)
	if liveEntry and liveEntry.container then
		local used, capacity, personalBonus = readContainerWeights(liveEntry.container, player)
		totals.usedWeight = totals.usedWeight + used
		if capacity then
			totals.totalCapacity = totals.totalCapacity + capacity
			-- BUG REAL reportado (2026-08-21, jugador con mod de expansion de
			-- capacidad de contenedores): storedCapacity solo se escribia
			-- durante un escaneo de zona (GS_ZoneScanner.lua) y nunca se
			-- refrescaba despues - si un contenedor quedaba fuera de rango
			-- (offline/sin chunk cargado) antes del siguiente escaneo
			-- completo, el total seguia usando la capacidad ANTIGUA
			-- (a veces la vanilla, previa a que el mod de expansion aplicara
			-- su bonus), sumando menos capacidad total de la real y
			-- disparando el aviso de "lleno" con margen real de sobra.
			-- Aqui, cada vez que SI tenemos una lectura en vivo, la
			-- persistimos en el nodo para que la proxima vez que este
			-- offline use el valor mas reciente conocido, no uno obsoleto.
			if node then
				node.storedCapacity = capacity
			end
			-- Bonus personal (Organizado/etc.): solo se conoce con el
			-- contenedor en directo (getEffectiveCapacity necesita el objeto
			-- Java real). No se cachea ni se aplica a nodos offline/sin
			-- chunk: preferimos infravalorar el extra disponible (nunca
			-- prometer mas capacidad de la que el motor concederia de verdad)
			-- antes que arriesgar un numero optimista sin poder confirmarlo.
			totals.personalBonus = (totals.personalBonus or 0) + personalBonus
			-- Log.detail, no Log.debug: esto se evalua en CADA refresco de
			-- terminal (cada accion, fin de escaneo, etc.), una linea por
			-- nodo en directo - con redes grandes es volumen alto y
			-- repetitivo, exactamente el caso para el que existe el sublog
			-- DETAIL (requiere activar tambien DebugDetailCapacityBonus).
			if personalBonus > 0 and GlobalStorageSiK.Log then
				GlobalStorageSiK.Log.detail("CapacityBonus", "accumulateNode | nodeId=" .. tostring(node and node.id)
					.. " baseCapacity=" .. tostring(capacity) .. " personalBonus=" .. tostring(personalBonus))
			end
		else
			totals.partialEstimate = true
		end
		totals.liveNodes = totals.liveNodes + 1
		return used, capacity and (capacity + (personalBonus or 0)) or nil
	end

	if node.offline == true then
		totals.offlineNodes = totals.offlineNodes + 1
	else
		totals.unloadedNodes = totals.unloadedNodes + 1
	end

	local used = 0
	if node.itemSnapshot then
		used = GlobalStorageSiK.NetworkCapacity.estimateSnapshotWeight(node.itemSnapshot)
		totals.usedWeight = totals.usedWeight + used
		totals.partialEstimate = true
	else
		totals.partialEstimate = true
	end

	if node.storedCapacity and node.storedCapacity > 0 then
		totals.totalCapacity = totals.totalCapacity + node.storedCapacity
		return used, node.storedCapacity
	end
	totals.partialEstimate = true
	return used, nil
end

--- Calcula estadísticas de capacidad de una red.
--- Si se pasa `player`, el bonus personal real de rasgos como Organizado
--- (leido de la misma API vanilla que ya decide si un deposito cabe, ver
--- readContainerWeights) se suma al total y afecta al % y al status
--- ("lleno"/"critico"/"aviso") devueltos - no es solo un dato informativo,
--- es el mismo limite que el motor aplicaria si ESE jugador depositase ahora
--- mismo. Sin `player`, el calculo es identico a como era antes (capacidad
--- base, sin ningun bonus de rasgo).
---@param networkId string|nil
---@param player IsoPlayer|nil
---@return table
function GlobalStorageSiK.NetworkCapacity.compute(networkId, player)
	networkId = networkId or GlobalStorageSiK.Network.getDefaultNetworkId()
	local totals = {
		usedWeight = 0,
		totalCapacity = 0,
		personalBonus = 0,
		liveNodes = 0,
		offlineNodes = 0,
		unloadedNodes = 0,
		partialEstimate = false,
		-- dev26 ronda 4bis: desglose por-nodo/por-zona, subproducto GRATIS de
		-- este mismo barrido (ya se recorre cada nodo de la red en cada
		-- refresco de terminal para el agregado - ver GS_Server.lua:512) - lo
		-- usa la columna "% Ocupación" de GS_TerminalUI_Nodes.lua sin ninguna
		-- lectura de contenedor adicional.
		perNode = {},
		perZone = {},
	}

	local liveById = {}
	local live = GlobalStorageSiK.Network.getLiveContainers(networkId)
	for i = 1, #live do
		local entry = live[i].entry
		if entry and entry.id then
			liveById[entry.id] = live[i]
		end
	end

	local counted = {}
	local registry = GlobalStorageSiK.Zones.getRegistry()

	for _, node in pairs(registry.nodes or {}) do
		if node.enabled ~= false and node.membership ~= "excluded" and node.id then
			local zone = registry.zones and registry.zones[node.zoneId]
			if zone and zone.networkId == networkId and zone.enabled ~= false then
				counted[node.id] = true
				local nodeUsed, nodeCap = accumulateNode(totals, node, liveById[node.id], player)
				if nodeCap and nodeCap > 0 then
					totals.perNode[node.id] = {
						usedWeight = math.floor(nodeUsed * 10 + 0.5) / 10,
						capacity = math.floor(nodeCap * 10 + 0.5) / 10,
						percent = math.min(100, math.floor((nodeUsed / nodeCap) * 100 + 0.5)),
					}
				end
				if node.zoneId then
					local z = totals.perZone[node.zoneId] or { usedWeight = 0, capacity = 0 }
					z.usedWeight = z.usedWeight + nodeUsed
					z.capacity = z.capacity + (nodeCap or 0)
					totals.perZone[node.zoneId] = z
				end
			end
		end
	end

	local netRegistry = GlobalStorageSiK.Network.getRegistry()
	local network = netRegistry.networks and netRegistry.networks[networkId]
	if network and network.containers then
		for i = 1, #network.containers do
			local entry = network.containers[i]
			if entry and entry.id and not counted[entry.id] then
				counted[entry.id] = true
				local nodeUsed, nodeCap = accumulateNode(totals, entry, liveById[entry.id], player)
				if nodeCap and nodeCap > 0 then
					totals.perNode[entry.id] = {
						usedWeight = math.floor(nodeUsed * 10 + 0.5) / 10,
						capacity = math.floor(nodeCap * 10 + 0.5) / 10,
						percent = math.min(100, math.floor((nodeUsed / nodeCap) * 100 + 0.5)),
					}
				end
				if entry.zoneId then
					local z = totals.perZone[entry.zoneId] or { usedWeight = 0, capacity = 0 }
					z.usedWeight = z.usedWeight + nodeUsed
					z.capacity = z.capacity + (nodeCap or 0)
					totals.perZone[entry.zoneId] = z
				end
			end
		end
	end

	-- Cierra perZone con su % final (usedWeight/capacity ya acumulados arriba).
	for _, z in pairs(totals.perZone) do
		z.usedWeight = math.floor(z.usedWeight * 10 + 0.5) / 10
		z.capacity = math.floor(z.capacity * 10 + 0.5) / 10
		z.percent = (z.capacity > 0) and math.min(100, math.floor((z.usedWeight / z.capacity) * 100 + 0.5)) or nil
	end

	-- El bonus personal se suma DESPUES de acumular todos los nodos, como
	-- capacidad extra sobre el total base - nunca sustituye ni reescribe
	-- totalCapacity, solo la amplia para el jugador que la consulto.
	local effectiveCapacity = totals.totalCapacity + (totals.personalBonus or 0)

	local percent = 0
	if effectiveCapacity > 0 then
		percent = math.min(100, math.floor((totals.usedWeight / effectiveCapacity) * 100 + 0.5))
	end

	local warnPct = GlobalStorageSiK.Config.WEIGHT_WARN_PERCENT or 80
	local critPct = GlobalStorageSiK.Config.WEIGHT_CRITICAL_PERCENT or 95
	local status = "ok"
	if effectiveCapacity > 0 then
		if totals.usedWeight >= effectiveCapacity or percent >= 100 then
			status = "full"
		elseif percent >= critPct then
			status = "critical"
		elseif percent >= warnPct then
			status = "warning"
		end
	end

	totals.effectiveCapacity = effectiveCapacity
	totals.percent = percent
	totals.status = status
	return totals
end

--- Peso/capacidad de UN contenedor en vivo - mismo camino que accumulateNode
--- pero para un unico contenedor en vez de sumar toda la red. dev26 ronda 4,
--- indicador de ocupacion en el editor de contenedor: se pide sobre la marcha
--- desde getNodeContents (mismo momento en que el servidor ya resuelve el
--- objeto en vivo para leer las filas), no un escaneo de red aparte. Sin
--- contenedor en vivo (offline/chunk sin cargar) o sin capacidad legible,
--- nil - el cliente ya sabe mostrar "sin dato" en ese caso.
---@param container ItemContainer|nil
---@param player IsoPlayer|nil
---@return table|nil
function GlobalStorageSiK.NetworkCapacity.computeNode(container, player)
	if not container then
		return nil
	end
	local used, capacity, personalBonus = readContainerWeights(container, player)
	if not capacity or capacity <= 0 then
		return nil
	end
	local effective = capacity + (personalBonus or 0)
	local percent = math.min(100, math.floor((used / effective) * 100 + 0.5))
	return {
		usedWeight = math.floor(used * 10 + 0.5) / 10,
		capacity = math.floor(effective * 10 + 0.5) / 10,
		percent = percent,
	}
end

--- Peso/capacidad de UNA zona (solo sus nodos, no toda la red) - mismo motor
--- que compute() filtrado a un unico zoneId, para el indicador de ocupacion
--- del editor de zona sin tener que escanear la red entera. Nodos offline/
--- sin chunk cargado dentro de la zona se saltan (mismo criterio que
--- accumulateNode - partialEstimate marca que el numero puede quedarse corto).
---@param zoneId string
---@param player IsoPlayer|nil
---@return table|nil
function GlobalStorageSiK.NetworkCapacity.computeZone(zoneId, player)
	local registry = GlobalStorageSiK.Zones.getRegistry()
	local zone = registry.zones and registry.zones[zoneId]
	if not zone then
		return nil
	end
	local totals = {
		usedWeight = 0, totalCapacity = 0, personalBonus = 0,
		liveNodes = 0, offlineNodes = 0, unloadedNodes = 0, partialEstimate = false,
	}
	local liveById = {}
	local live = GlobalStorageSiK.Network.getLiveContainers(zone.networkId)
	for i = 1, #live do
		local entry = live[i].entry
		if entry and entry.id then
			liveById[entry.id] = live[i]
		end
	end
	for _, node in pairs(registry.nodes or {}) do
		if node.zoneId == zoneId and node.enabled ~= false and node.membership ~= "excluded" and node.id then
			accumulateNode(totals, node, liveById[node.id], player)
		end
	end
	if totals.totalCapacity <= 0 and (totals.personalBonus or 0) <= 0 then
		return nil
	end
	local effectiveCapacity = totals.totalCapacity + (totals.personalBonus or 0)
	local percent = 0
	if effectiveCapacity > 0 then
		percent = math.min(100, math.floor((totals.usedWeight / effectiveCapacity) * 100 + 0.5))
	end
	return {
		usedWeight = math.floor(totals.usedWeight * 10 + 0.5) / 10,
		capacity = math.floor(effectiveCapacity * 10 + 0.5) / 10,
		percent = percent,
		partialEstimate = totals.partialEstimate == true,
	}
end

--- Redondea y serializa para envío al cliente.
---@param stats table|nil
---@return table
function GlobalStorageSiK.NetworkCapacity.serialize(stats)
	stats = stats or {}
	return {
		usedWeight = math.floor((stats.usedWeight or 0) * 10 + 0.5) / 10,
		totalCapacity = math.floor((stats.totalCapacity or 0) * 10 + 0.5) / 10,
		-- Bonus personal real (Organizado/etc.) del jugador que consulto este
		-- calculo, y el total ya sumado con el - ver GS_NetworkCapacity.compute.
		personalBonus = math.floor((stats.personalBonus or 0) * 10 + 0.5) / 10,
		effectiveCapacity = math.floor((stats.effectiveCapacity or stats.totalCapacity or 0) * 10 + 0.5) / 10,
		percent = stats.percent or 0,
		status = stats.status or "ok",
		liveNodes = stats.liveNodes or 0,
		offlineNodes = stats.offlineNodes or 0,
		unloadedNodes = stats.unloadedNodes or 0,
		partialEstimate = stats.partialEstimate == true,
	}
end
