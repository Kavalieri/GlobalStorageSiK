--[[
	GlobalStorageSiK - Escáner de contenedores por zona
	Autor: SiK
	Fecha: 2025-06-23
	Descripción: Detecta contenedores en una zona sin clic en el mundo.
]]

require "GS_Utils"
require "GS_Zones"
require "GS_ItemSnapshot"

GlobalStorageSiK.ZoneScanner = {}

---@param zone table
---@param maxContainers number|nil
---@return table[] results
---@return boolean limitHit
---@return boolean anySquareLoaded true si al menos una baldosa de la zona estaba cargada
function GlobalStorageSiK.ZoneScanner.scanZone(zone, maxContainers)
	local state = GlobalStorageSiK.ZoneScanner.beginIncremental(zone, maxContainers)
	if not state then
		return {}, false, false
	end
	while not GlobalStorageSiK.ZoneScanner.isIncrementalDone(state) do
		GlobalStorageSiK.ZoneScanner.stepIncremental(state, 10000, 0)
	end
	return state.results, state.limitHit == true, state.anySquareLoaded == true
end

--- Añade contenedores de una baldosa a la lista de resultados.
---@param square IsoGridSquare
---@param zoneId string
---@param results table[]
---@param limit number
---@param seenEntryIds table<string, boolean>|nil identificadores ya contados durante el escaneo de la zona
---@return boolean|nil limitHit true si se alcanzó el límite
function GlobalStorageSiK.ZoneScanner.scanSquare(square, zoneId, results, limit, seenEntryIds)
	-- Un IsoObject con contenedor suele aparecer tanto en getObjects() como en
	-- getSpecialObjects(). El escáner antiguo añadía ambas apariciones y solo
	-- las deduplicaba mucho después, al fusionar por entry.id. Esos duplicados
	-- consumían antes el límite de MaxContainersPerZone, por lo que una zona
	-- grande podía detenerse a mitad del recorrido y dejar sin registrar una
	-- parte aparentemente diagonal de la habitación. El límite debe contar
	-- inventarios físicos únicos, no colecciones internas de PZ.
	seenEntryIds = seenEntryIds or {}
	if #results > 0 then
		for i = 1, #results do
			local existing = results[i]
			if existing and existing.id then
				seenEntryIds[existing.id] = true
			end
		end
	end

	-- Un mismo objeto del mundo puede exponer varios contenedores reales
	-- (mueble con nevera+congelador combinados, etc. - ver GS_Utils.lua,
	-- getContainerCount/getContainerByIndex): se registra UNA entrada por
	-- cada indice, no solo la del contenedor 0, o el resto quedaba invisible.
	local function tryObject(obj)
		local count = GlobalStorageSiK.Utils.getContainerCount(obj)
		for containerIndex = 0, count - 1 do
			local entry = GlobalStorageSiK.Utils.buildContainerEntry(obj, containerIndex)
			if entry and not seenEntryIds[entry.id] then
				if #results >= limit then
					return true
				end
				seenEntryIds[entry.id] = true
				entry.zoneId = zoneId
				entry.membership = "auto"
				entry.enabled = true
				entry.displayName = obj:getName() or entry.name
				local container = GlobalStorageSiK.Utils.getObjectContainer(obj, containerIndex)
				if container then
					entry.itemSnapshot = GlobalStorageSiK.ItemSnapshot.fromContainer(container)
					if container.getCapacity then
						local okCap, cap = pcall(function()
							return container:getCapacity()
						end)
						if okCap and cap and cap > 0 then
							entry.storedCapacity = cap
						end
					end
				end
				table.insert(results, entry)
			end
		end
		return false
	end

	for i = 0, square:getObjects():size() - 1 do
		if tryObject(square:getObjects():get(i)) then
			return true
		end
	end
	if square.getSpecialObjects then
		for i = 0, square:getSpecialObjects():size() - 1 do
			if tryObject(square:getSpecialObjects():get(i)) then
				return true
			end
		end
	end
	return false
end

--- Crea un cursor de escaneo que no recorre todavia ninguna instancia. Las
--- referencias Java a contenedores viven solo mientras dura este trabajo y no
--- se persisten en ModData; el resultado final conserva exclusivamente datos
--- Lua planos por tipo.
---@param zone table
---@param maxContainers number|nil
---@return table|nil state
function GlobalStorageSiK.ZoneScanner.beginIncremental(zone, maxContainers)
	if not zone or not zone.bounds then return nil end
	local cell = getCell and getCell() or nil
	if not cell then return nil end
	local b = zone.bounds
	local x1 = math.min(b.x1 or b.x, b.x2 or b.x)
	local x2 = math.max(b.x1 or b.x, b.x2 or b.x)
	local y1 = math.min(b.y1 or b.y, b.y2 or b.y)
	local y2 = math.max(b.y1 or b.y, b.y2 or b.y)
	local zMin = b.z or b.zMin or 0
	local zMax = b.zMax or zMin
	return {
		zone = zone,
		cell = cell,
		limit = maxContainers or 128,
		x1 = x1, x2 = x2, y1 = y1, y2 = y2, zMin = zMin, zMax = zMax,
		x = x1, y = y1, z = zMin,
		phase = "squares",
		results = {},
		seenEntryIds = {},
		containerTasks = {},
		taskIndex = 1,
		itemIndex = 0,
		limitHit = false,
		anySquareLoaded = false,
		metrics = {
			squaresVisited = 0,
			loadedSquares = 0,
			nodesDetected = 0,
			itemInstances = 0,
			snapshotRows = 0,
			distinctTypes = 0,
		},
		distinctTypeSet = {},
	}
end

local function advanceSquareCursor(state)
	state.y = state.y + 1
	if state.y > state.y2 then
		state.y = state.y1
		state.x = state.x + 1
	end
	if state.x > state.x2 then
		state.x = state.x1
		state.z = state.z + 1
	end
	if state.z > state.zMax then
		state.phase = "snapshots"
	end
end

local function queueIncrementalObject(state, obj)
	if not obj then return false end
	local count = GlobalStorageSiK.Utils.getContainerCount(obj)
	for containerIndex = 0, count - 1 do
		local entry = GlobalStorageSiK.Utils.buildContainerEntry(obj, containerIndex)
		if entry and not state.seenEntryIds[entry.id] then
			if #state.results >= state.limit then
				state.limitHit = true
				state.phase = "snapshots"
				return true
			end
			state.seenEntryIds[entry.id] = true
			entry.zoneId = state.zone.id
			entry.membership = "auto"
			entry.enabled = true
			entry.displayName = obj:getName() or entry.name
			entry.itemSnapshot = {}
			local container = GlobalStorageSiK.Utils.getObjectContainer(obj, containerIndex)
			if container and container.getCapacity then
				local okCap, cap = pcall(function() return container:getCapacity() end)
				if okCap and cap and cap > 0 then entry.storedCapacity = cap end
			end
			state.results[#state.results + 1] = entry
			state.containerTasks[#state.containerTasks + 1] = {
				entry = entry,
				container = container,
			}
			state.metrics.nodesDetected = state.metrics.nodesDetected + 1
		end
	end
	return false
end

local function scanIncrementalSquare(state)
	state.metrics.squaresVisited = state.metrics.squaresVisited + 1
	local square = state.cell:getGridSquare(state.x, state.y, state.z)
	if square then
		state.anySquareLoaded = true
		state.metrics.loadedSquares = state.metrics.loadedSquares + 1
		local objects = square:getObjects()
		for i = 0, objects:size() - 1 do
			if queueIncrementalObject(state, objects:get(i)) then return end
		end
		if square.getSpecialObjects then
			local special = square:getSpecialObjects()
			for i = 0, special:size() - 1 do
				if queueIncrementalObject(state, special:get(i)) then return end
			end
		end
	end
	advanceSquareCursor(state)
end

local function scanIncrementalItem(state)
	local task = state.containerTasks[state.taskIndex]
	if not task then
		state.phase = "done"
		state.cell = nil
		state.containerTasks = nil
		return
	end
	local container = task.container
	local items = container and container.getItems and container:getItems() or nil
	local size = items and items.size and items:size() or 0
	if state.itemIndex >= size then
		task.container = nil
		state.taskIndex = state.taskIndex + 1
		state.itemIndex = 0
		return
	end
	local item = items:get(state.itemIndex)
	state.itemIndex = state.itemIndex + 1
	state.metrics.itemInstances = state.metrics.itemInstances + 1
	if item and item.getFullType then
		local fullType = item:getFullType()
		local hadNodeType = fullType and task.entry.itemSnapshot[fullType] ~= nil
		if GlobalStorageSiK.ItemSnapshot.addItem(task.entry.itemSnapshot, item, fullType) and fullType then
			if not hadNodeType then state.metrics.snapshotRows = state.metrics.snapshotRows + 1 end
			if not state.distinctTypeSet[fullType] then
				state.distinctTypeSet[fullType] = true
				state.metrics.distinctTypes = state.metrics.distinctTypes + 1
			end
		end
	end
end

--- Ejecuta una porcion acotada. `maxUnits` cuenta baldosas durante la fase de
--- descubrimiento e instancias durante snapshots; `maxMs=0` desactiva solo el
--- reloj y se usa exclusivamente por el wrapper sincrono legacy.
---@param state table
---@param maxUnits number|nil
---@param maxMs number|nil
---@return boolean done
function GlobalStorageSiK.ZoneScanner.stepIncremental(state, maxUnits, maxMs)
	if not state or state.phase == "done" then return true end
	local budget = math.max(1, tonumber(maxUnits) or 50)
	local timeBudget = tonumber(maxMs)
	if timeBudget == nil then timeBudget = 5 end
	local started = getTimestampMs and getTimestampMs() or 0
	local units = 0
	while state.phase ~= "done" and units < budget do
		if state.phase == "squares" then
			scanIncrementalSquare(state)
		else
			scanIncrementalItem(state)
		end
		units = units + 1
		if timeBudget > 0 and units > 0 and started > 0 and getTimestampMs
			and getTimestampMs() - started >= timeBudget then
			break
		end
	end
	return state.phase == "done"
end

---@param state table|nil
---@return boolean
function GlobalStorageSiK.ZoneScanner.isIncrementalDone(state)
	return state == nil or state.phase == "done"
end
