--[[
	GlobalStorageSiK - Zonas de almacenamiento
	Autor: SiK
	Fecha: 2025-06-23
	Descripción: Definición y persistencia de zonas nombradas (SP/MP).
]]

require "GS_Config"
require "GS_Sandbox"
require "GS_RuleCoverage"

GlobalStorageSiK.Zones = {}

	GlobalStorageSiK.Zones.SOURCE = {
	MANUAL = "manual",
	SELECTION = "selection",
	ROOM = "room",
	BUILDING = "building",
	SAFEHOUSE = "safehouse",
}

--- Migra node.priority del enum viejo (1=Baja,2=Normal,3=Alta) a la escala fina
--- 1-100 (1=maxima prioridad, coherente con zone.priority). Se ejecuta UNA sola
--- vez por registro (marca registry.priorityMigratedV2); despues de eso, un
--- node.priority de 1/2/3 es un valor fino legitimo y no se reinterpreta.
---@param registry table
local function migratePriorityScale(registry)
	if registry.priorityMigratedV2 then
		return
	end
	local OLD_TO_NEW = { [3] = 10, [2] = 50, [1] = 90 }
	for _, node in pairs(registry.nodes or {}) do
		local p = node.priority
		if p ~= nil and OLD_TO_NEW[p] then
			node.priority = OLD_TO_NEW[p]
		end
	end
	registry.priorityMigratedV2 = true
end

--- Obtiene el registro global de zonas.
---@return table
function GlobalStorageSiK.Zones.getRegistry()
	local registry = ModData.getOrCreate(GlobalStorageSiK.MODDATA_KEY)
	registry.zones = registry.zones or {}
	registry.nodes = registry.nodes or {}
	migratePriorityScale(registry)
	return registry
end

--- Crea una zona vacía con metadatos mínimos.
---@param name string
---@param source string
---@param bounds table
---@param networkId string
---@param priority number|nil
---@return table
function GlobalStorageSiK.Zones.createZone(name, source, bounds, networkId, priority)
	return {
		id = "zone_" .. tostring(getTimestampMs()),
		name = name or "Zona",
		source = source or GlobalStorageSiK.Zones.SOURCE.MANUAL,
		bounds = bounds or {},
		networkId = networkId,
		defaultRules = {},
		enabled = true,
		priority = priority,
	}
end

--- Siguiente prioridad (menor importancia) para una red.
---@param registry table
---@param networkId string
---@return number
function GlobalStorageSiK.Zones.nextPriority(registry, networkId)
	local maxP = 0
	for _, zone in pairs(registry.zones or {}) do
		if zone.networkId == networkId then
			local p = tonumber(zone.priority) or 0
			if p > maxP then
				maxP = p
			end
		end
	end
	return maxP + 1
end

--- Reordena zonas según lista de ids (prioridad 1..N).
---@param networkId string
---@param zoneIds string[]
---@return boolean
function GlobalStorageSiK.Zones.reorderZones(networkId, zoneIds)
	if not networkId or not zoneIds or #zoneIds == 0 then
		return false
	end
	local registry = GlobalStorageSiK.Zones.getRegistry()
	for i = 1, #zoneIds do
		local zone = registry.zones and registry.zones[zoneIds[i]]
		if zone and zone.networkId == networkId then
			zone.priority = i
		end
	end
	return true
end

--- Mueve una zona una posición en la prioridad (compatibilidad: intercambia
--- el VALOR de prioridad con el vecino en vez de renumerar 1..N - la escala
--- ahora es libre 1-100 como en los contenedores, no una secuencia de
--- posiciones. Se conserva por si algun sitio de la UI todavia usa flechas
--- arriba/abajo).
---@param networkId string
---@param zoneId string
---@param direction string up|down
---@return boolean
function GlobalStorageSiK.Zones.moveZonePriority(networkId, zoneId, direction)
	require "GS_ZonePriority"
	local registry = GlobalStorageSiK.Zones.getRegistry()
	local sorted = GlobalStorageSiK.ZonePriority.listSorted(registry, networkId)
	local idx = nil
	for i = 1, #sorted do
		if sorted[i].id == zoneId then
			idx = i
			break
		end
	end
	if not idx then
		return false
	end
	local swapIdx = direction == "up" and idx - 1 or idx + 1
	if swapIdx < 1 or swapIdx > #sorted then
		return false
	end
	local a, b = sorted[idx], sorted[swapIdx]
	a.priority, b.priority = b.priority, a.priority
	return true
end

--- Fija la prioridad de una zona a un valor exacto 1-100 (1 = se llena
--- primero), igual que la prioridad de contenedores - reemplaza el sistema
--- antiguo de posicion secuencial (1,2,3...) por uno consistente con el
--- resto del mod.
---@param networkId string
---@param zoneId string
---@param priority number
---@return boolean ok
function GlobalStorageSiK.Zones.setPriority(networkId, zoneId, priority)
	local registry = GlobalStorageSiK.Zones.getRegistry()
	local zone = registry.zones and registry.zones[zoneId]
	if not zone or zone.networkId ~= networkId then
		return false
	end
	local n = math.floor((tonumber(priority) or 50) + 0.5)
	if n < 1 then n = 1 elseif n > 100 then n = 100 end
	zone.priority = n
	return true
end

--- Bounds para zona amplia: safehouse (si aplica) o edificio completo.
---@param player IsoPlayer|nil
---@return table|nil bounds
---@return string|nil name
---@return string|nil source
function GlobalStorageSiK.Zones.boundsFromStructure(player)
	if not player then
		return nil
	end
	if GlobalStorageSiK.Sandbox and GlobalStorageSiK.Sandbox.allowSafehouseImport and GlobalStorageSiK.Sandbox.allowSafehouseImport() then
		local sq = player.getSquare and player:getSquare() or nil
		local shBounds = GlobalStorageSiK.Zones.boundsFromSafehouse(sq, player)
		if shBounds then
			return shBounds, shBounds.title or "Safehouse", GlobalStorageSiK.Zones.SOURCE.SAFEHOUSE
		end
	end
	local bBounds, title = GlobalStorageSiK.Zones.boundsFromPlayerBuilding(player)
	if bBounds then
		return bBounds, title or "Edificio", GlobalStorageSiK.Zones.SOURCE.BUILDING
	end
	return nil
end

--- Comprueba si unas coordenadas están dentro de una zona (una planta).
---@param zone table
---@param x number
---@param y number
---@param z number
---@return boolean
function GlobalStorageSiK.Zones.containsPoint(zone, x, y, z)
	if not zone or not zone.bounds then
		return false
	end

	local b = zone.bounds
	local x1 = math.min(b.x1 or b.x, b.x2 or b.x)
	local x2 = math.max(b.x1 or b.x, b.x2 or b.x)
	local y1 = math.min(b.y1 or b.y, b.y2 or b.y)
	local y2 = math.max(b.y1 or b.y, b.y2 or b.y)
	local zMin = b.z or b.zMin or 0
	local zMax = b.zMax or zMin

	if z < zMin or z > zMax then
		return false
	end

	return x >= x1 and x <= x2 and y >= y1 and y <= y2
end

--- Normaliza un bounds a sus 6 limites reales (min/max en los 3 ejes),
--- mismo criterio que containsPoint - evita comparar x1/x2 sin normalizar
--- (una zona guardada con x1>x2, por ejemplo tras un refactor de origen,
--- daria un falso "no coincide" contra la misma zona con los ejes en el
--- orden esperado).
---@param b table|nil
---@return number x1, number x2, number y1, number y2, number zMin, number zMax
local function normalizedBounds(b)
	b = b or {}
	local x1 = math.min(b.x1 or b.x or 0, b.x2 or b.x or 0)
	local x2 = math.max(b.x1 or b.x or 0, b.x2 or b.x or 0)
	local y1 = math.min(b.y1 or b.y or 0, b.y2 or b.y or 0)
	local y2 = math.max(b.y1 or b.y or 0, b.y2 or b.y or 0)
	local zMin = b.z or b.zMin or 0
	local zMax = b.zMax or zMin
	return x1, x2, y1, y2, zMin, zMax
end

--- Busca, entre las zonas YA registradas de una red, una cuyos limites
--- coincidan EXACTAMENTE con los de "bounds" - guarda de seguridad
--- (2026-08-23, pedido explicito tras un reporte real: un jugador con 8
--- zonas contando para el limite de sandbox pero solo 2 realmente
--- utiles/pobladas, sin ningun aviso al crear zonas repetidas sobre la
--- MISMA area fisica). createZone()/addZone() nunca comprobaban solapamiento
--- - cada pulsacion de "Crear zona desde mi habitacion/edificio/refugio"
--- crea una entrada nueva con ID propio, aunque el jugador la aplique dos
--- veces sobre el mismo sitio, consumiendo un hueco del limite de zonas sin
--- ningun beneficio real.
--- Deliberadamente EXACTA, no "solapamiento parcial": el mod SI soporta
--- zonas anidadas/solapadas a proposito (una zona pequeña de alta prioridad
--- dentro de otra mas grande, resuelto por GS_ZonePriority) - bloquear
--- cualquier solapamiento romperia ese uso legitimo. Solo el caso "esto ya
--- es literalmente la misma zona" debe rechazarse.
---@param registry table
---@param networkId string
---@param bounds table
---@return table|nil existingZone
function GlobalStorageSiK.Zones.findDuplicateZone(registry, networkId, bounds)
	if not registry or not networkId or not bounds then return nil end
	local x1, x2, y1, y2, zMin, zMax = normalizedBounds(bounds)
	for _, zone in pairs(registry.zones or {}) do
		if zone.networkId == networkId then
			local ex1, ex2, ey1, ey2, ezMin, ezMax = normalizedBounds(zone.bounds)
			if ex1 == x1 and ex2 == x2 and ey1 == y1 and ey2 == y2
				and ezMin == zMin and ezMax == zMax then
				return zone
			end
		end
	end
	return nil
end

--- Elimina una zona y los nodos asociados del registro.
---@param zoneId string
---@return boolean removed
function GlobalStorageSiK.Zones.removeZone(zoneId)
	if not zoneId or zoneId == "" then
		return false
	end
	local registry = GlobalStorageSiK.Zones.getRegistry()
	if not registry.zones or not registry.zones[zoneId] then
		return false
	end
	-- No mutar registry.nodes mientras pairs() lo recorre: en Kahlua puede
	-- saltarse entradas y dejar reglas/reservas fantasma tras una cascada.
	local nodeIds = {}
	for id, node in pairs(registry.nodes or {}) do
		if node.zoneId == zoneId then nodeIds[#nodeIds + 1] = id end
	end
	registry.zones[zoneId] = nil
	for i = 1, #nodeIds do
		registry.nodes[nodeIds[i]] = nil
	end
	return true, #nodeIds
end

--- Elimina solo el registro lógico de un contenedor. Nunca modifica el
--- IsoObject ni vacía su inventario; un escaneo posterior lo descubre limpio.
---@param nodeId string
---@param networkId string
---@return boolean removed
function GlobalStorageSiK.Zones.removeNode(nodeId, networkId)
	if not nodeId or nodeId == "" or not networkId then return false end
	local registry = GlobalStorageSiK.Zones.getRegistry()
	local node = registry.nodes and registry.nodes[nodeId]
	local zone = node and registry.zones and registry.zones[node.zoneId]
	if not node or not zone or zone.networkId ~= networkId then return false end
	registry.nodes[nodeId] = nil
	return true
end

--- Compara firmas físicas persistidas sin depender de ids posicionales.
---@param left table|nil
---@param right table|nil
---@return boolean
function GlobalStorageSiK.Zones.samePhysicalSignature(left, right)
	if not left or not right then return false end
	return left.sprite == right.sprite
		and left.containerType == right.containerType
		and left.containerIndex == right.containerIndex
end

--- Indica si un alta es todavía limpia y puede recibir una configuración lógica.
---@param node table|nil
---@return boolean
function GlobalStorageSiK.Zones.isCleanAutomaticNode(node)
	return node and node.membership == "auto" and not node.rules and not node.filters
		and not node.categories and not node.notes and not node.priority
		and (node.displayName == nil or node.displayName == "" or node.displayName == node.name)
end

local PHYSICAL_NODE_FIELDS = {
	id = true, x = true, y = true, z = true, name = true, zoneId = true,
	containerIndex = true, itemSnapshot = true, storedCapacity = true,
	offline = true, physicalSignature = true, physicalAnomaly = true,
	discoveredAtMs = true, lastSeenMs = true,
}

local function copyLogicalConfig(source)
	local copied = {}
	for key, value in pairs(source or {}) do
		if not PHYSICAL_NODE_FIELDS[key] then copied[key] = value end
	end
	return copied
end

local function cloneRule(rule)
	local condition = {}
	for key, value in pairs((rule and rule.condition) or {}) do
		if key == "coverageExclusions" and type(value) == "table" then
			local copied = {}
			for i = 1, #value do copied[i] = value[i] end
			condition[key] = copied
		else
			condition[key] = value
		end
	end
	return { op = rule and rule.op, condition = condition }
end

-- Recalcula la reserva de las reglas trasladadas contra los hermanos REALES
-- de la zona de destino. Las exclusiones de la zona anterior no se reutilizan:
-- podrían ocultar rutas libres o colisionar con una regla ya presente allí.
local function prepareTargetZoneRules(registry, sourceId, target, sourceRules)
	local scopeRules = {}
	for id, node in pairs(registry.nodes or {}) do
		if id ~= sourceId and id ~= target.id and node.zoneId == target.zoneId then
			for i = 1, #(node.rules or {}) do
				scopeRules[#scopeRules + 1] = node.rules[i]
			end
		end
	end
	local prepared = {}
	for i = 1, #(sourceRules or {}) do
		local rule = cloneRule(sourceRules[i])
		if not GlobalStorageSiK.RuleCoverage.prepareNewRule(rule, scopeRules) then
			return nil
		end
		prepared[#prepared + 1] = rule
		scopeRules[#scopeRules + 1] = rule
	end
	return prepared
end

--- Asocia configuración lógica ya validada por servidor a un destino físico
--- concreto. El destino conserva siempre zona, identidad, coordenadas, snapshot
--- y capacidad: moverlo de zona es una operación de producto distinta.
---@param sourceId string
---@param targetId string
---@param networkId string
---@return boolean rebound
function GlobalStorageSiK.Zones.rebindNode(sourceId, targetId, networkId)
	if not sourceId or not targetId or sourceId == targetId or not networkId then return false end
	local registry = GlobalStorageSiK.Zones.getRegistry()
	local source = registry.nodes and registry.nodes[sourceId]
	local target = registry.nodes and registry.nodes[targetId]
	local sourceZone = source and registry.zones and registry.zones[source.zoneId]
	local targetZone = target and registry.zones and registry.zones[target.zoneId]
	if not source or not target or not sourceZone or not targetZone
		or sourceZone.networkId ~= networkId or targetZone.networkId ~= networkId then return false end
	if source.offline ~= true or target.offline == true
		or not GlobalStorageSiK.Zones.isCleanAutomaticNode(target)
		or not GlobalStorageSiK.Zones.samePhysicalSignature(source.physicalSignature, target.physicalSignature) then
		return false
	end
	local preserved = copyLogicalConfig(source)
	-- La zona del alta física es soberana. Si cambia, las reservas se deben
	-- recalcular ANTES de mutar nada; una colisión deja ambos registros intactos.
	local preparedRules = prepareTargetZoneRules(registry, sourceId, target, source.rules)
	if not preparedRules then return false end
	if source.rules ~= nil then preserved.rules = preparedRules end
	for key, value in pairs(preserved) do target[key] = value end
	for key, value in pairs(preserved) do
		if target[key] ~= value then return false end
	end
	registry.nodes[sourceId] = nil
	return true
end

--- Intenta crear bounds desde la safehouse vanilla (MP).
---@param square IsoGridSquare|nil
---@param player IsoPlayer|nil
---@return table|nil
function GlobalStorageSiK.Zones.boundsFromSafehouse(square, player)
	if not SafeHouse or not SafeHouse.getSafeHouse then
		return nil
	end

	local sh = square and SafeHouse.getSafeHouse(square) or nil
	if not sh and player and SafeHouse.getSafehouseList then
		local username = player.getUsername and player:getUsername() or nil
		if username then
			local list = SafeHouse.getSafehouseList()
			if list then
				for i = 0, list:size() - 1 do
					local candidate = list:get(i)
					if candidate then
						local owner = candidate.getOwner and candidate:getOwner() or nil
						local allowed = candidate.playerAllowed and candidate:playerAllowed(username)
						if owner == username or allowed then
							sh = candidate
							break
						end
					end
				end
			end
		end
	end
	if not sh then
		return nil
	end

	local z = square and square.getZ and square:getZ() or 0
	if player and player.getSquare then
		local psq = player:getSquare()
		if psq then
			z = psq:getZ()
		end
	end

	return {
		x1 = sh:getX(),
		y1 = sh:getY(),
		x2 = sh:getX2(),
		y2 = sh:getY2(),
		z = z,
		zMax = z,
		safehouseId = sh:getId(),
		title = sh:getTitle(),
	}
end

--- Intenta crear bounds del edificio donde está el jugador.
---@param player IsoPlayer|nil
---@return table|nil bounds
---@return string|nil buildingTitle
function GlobalStorageSiK.Zones.boundsFromPlayerBuilding(player)
	if not player or not player.getSquare then
		return nil
	end
	local square = player:getSquare()
	if not square or not square.getBuilding then
		return nil
	end
	local okB, building = pcall(function()
		return square:getBuilding()
	end)
	if not okB or not building then
		return nil
	end

	local z = square:getZ()
	local x1, y1, x2, y2
	local title

	if building.getDef then
		local okD, def = pcall(function()
			return building:getDef()
		end)
		if okD and def and def.getX and def.getX2 then
			x1 = def:getX()
			y1 = def:getY()
			x2 = def:getX2()
			y2 = def:getY2()
			if def.getName then
				local okN, n = pcall(function()
					return def:getName()
				end)
				if okN and n and n ~= "" then
					title = n
				end
			end
		end
	end

	if not x1 and building.getX and building.getW and building.getY and building.getH then
		x1 = building:getX()
		y1 = building:getY()
		x2 = x1 + building:getW() - 1
		y2 = y1 + building:getH() - 1
	end
	if not x1 then
		return nil
	end

	local zMin, zMax = z, z
	if building.getZ then
		local okZ, bz = pcall(function()
			return building:getZ()
		end)
		if okZ and bz then
			zMin = bz
		end
	end
	if building.getHighestZ then
		local okH, hz = pcall(function()
			return building:getHighestZ()
		end)
		if okH and hz then
			zMax = hz
		end
	end

	return {
		x1 = x1,
		y1 = y1,
		x2 = x2,
		y2 = y2,
		z = zMin,
		zMax = zMax,
		buildingId = building.getID and building:getID() or nil,
	}, title
end
