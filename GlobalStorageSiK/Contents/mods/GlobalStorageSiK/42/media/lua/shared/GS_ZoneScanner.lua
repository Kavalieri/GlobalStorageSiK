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

-- Session-local capture proofs never enter ModData. Validation is incremental:
-- this is an observed snapshot with one logical publication, not a lock on PZ.
local MAX_CAPTURE_REFS = 262144
local MAX_CAPTURE_BYTES = 67108864

local function captureRef(state)
    local budget = state.captureBudget
    budget.refs = budget.refs + 1
    state.captureRefs = (state.captureRefs or 0) + 1
    budget.bytes = budget.bytes + 96
    if budget.refs > MAX_CAPTURE_REFS or budget.bytes > MAX_CAPTURE_BYTES then
        state.captureFailure = "scan_capture_budget"
        state.invalidated = true
        return false
    end
    return true
end

function GlobalStorageSiK.ZoneScanner.releaseIncremental(state)
    if not state then return end
    state.cell, state.discovery, state.containerTasks, state.capture = nil, nil, nil, nil
    state.captureBudget, state.protectedEntryIds = nil, nil
    state.discoveredObjects, state.verifiedObjects = nil, nil
end

function GlobalStorageSiK.ZoneScanner.beginValidation(state, protectedEntryIds)
    if not state or state.invalidated or not state.capture then return false end
    state.phase, state.validated = "verify", false
    state.verifySquare, state.verifyList, state.verifyObject = 1, 1, 1
    state.verifyTask, state.verifyItem = 1, 0
    state.verifiedObjects = {}
    state.validationStartUnits = state.workUnits or 0
    state.validationTotalUnits = (state.captureRefs or 0) + (state.metrics.loadedSquares or 0)
        + #state.capture.tasks + 1
    state.protectedEntryIds = protectedEntryIds
    return true
end

function GlobalStorageSiK.ZoneScanner.validateIncremental(state)
    return state ~= nil and state.validated == true and not state.invalidated
end

local function verifyIncrementalItem(state)
    local cell = getCell and getCell() or nil
    if cell ~= state.cell then state.invalidated = true; return end
    local square = state.capture.squares[state.verifySquare]
    if square then
        local live = cell:getGridSquare(square.x, square.y, square.z)
        if live ~= square.square then state.invalidated = true; return end
        if not live then state.verifySquare = state.verifySquare + 1; return end
        local list = state.verifyList == 1 and live:getObjects()
            or (live.getSpecialObjects and live:getSpecialObjects() or nil)
        local proof = state.verifyList == 1 and square.normal or square.special
        if (list and list:size() or 0) ~= proof.count then state.invalidated = true; return end
        local ref = proof.refs[state.verifyObject]
        if ref then
            local count = state.verifiedObjects[ref.object]
            if count == nil then
                count = GlobalStorageSiK.Utils.getContainerCount(ref.object)
                state.verifiedObjects[ref.object] = count
            end
            if list:get(state.verifyObject - 1) ~= ref.object or count ~= ref.count then
                state.invalidated = true; return
            end
            state.verifyObject = state.verifyObject + 1
        elseif state.verifyList == 1 then
            state.verifyList, state.verifyObject = 2, 1
        else
            state.verifySquare = state.verifySquare + 1
            state.verifyList, state.verifyObject = 1, 1
        end
        return
    end
    local task = state.capture.tasks[state.verifyTask]
    if not task then state.phase, state.validated = "done", true; return end
    -- Transfer has already captured this exact node and merge protects it.
    -- Its earlier scan body cannot overwrite that authoritative replacement.
    local proof = task.squareProof
    if cell:getGridSquare(proof.x, proof.y, proof.z) ~= proof.square
        or GlobalStorageSiK.Utils.getObjectContainer(task.object, task.containerIndex) ~= task.container
        or GlobalStorageSiK.Utils.getContainerId(task.object, task.containerIndex) ~= task.entry.id then
        state.invalidated = true; return
    end
    local list = task.special and proof.square:getSpecialObjects() or proof.square:getObjects()
    if not list or list:get(task.objectIndex) ~= task.object then state.invalidated = true; return end
    if state.protectedEntryIds and state.protectedEntryIds[task.entry.id] then
        state.verifyTask, state.verifyItem = state.verifyTask + 1, 0; return
    end
    local items = task.container and task.container:getItems() or nil
    if (items and items:size() or 0) ~= task.count then state.invalidated = true; return end
    if state.verifyItem >= task.count then
        state.verifyTask, state.verifyItem = state.verifyTask + 1, 0; return
    end
    local index = state.verifyItem + 1
    local item = items:get(state.verifyItem)
    if item ~= task.refs[index] then state.invalidated = true; return end
    state.verifyItem = index
end


---@param zone table
---@param maxContainers number|nil
---@return table[] results
---@return boolean limitHit
---@return boolean anySquareLoaded true si al menos una baldosa de la zona estaba cargada
---@return table<string, boolean> excludedEntryIds cámaras de cocción encontradas
function GlobalStorageSiK.ZoneScanner.scanZone(zone, maxContainers)
	local state, reason = GlobalStorageSiK.ZoneScanner.beginIncremental(zone, maxContainers)
	if not state then
		return {}, false, false, {}, reason
	end
	while not GlobalStorageSiK.ZoneScanner.isIncrementalDone(state) do
		GlobalStorageSiK.ZoneScanner.stepIncremental(state, 10000, 0)
	end
	if state.invalidated then return {}, false, false, {}, state.captureFailure or "snapshot_stale" end
	return state.results, state.limitHit == true, state.anySquareLoaded == true,
		state.excludedEntryIds
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
			local entry = GlobalStorageSiK.Utils.isNetworkStorageContainer(obj, containerIndex)
				and GlobalStorageSiK.Utils.buildContainerEntry(obj, containerIndex) or nil
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
function GlobalStorageSiK.ZoneScanner.beginIncremental(zone, maxContainers, retainProof, captureBudget, protectedEntryIds)
	if type(zone) ~= "table" then return nil, "invalid_bounds" end
	local x1, x2, y1, y2, zMin, zMax = GlobalStorageSiK.ZoneBounds.normalize(zone.bounds)
	if x1 == nil then return nil, "invalid_bounds" end
	local cell = getCell and getCell() or nil
	if not cell then return nil, "no_cell" end
	return {
		zone = zone,
		cell = cell,
		limit = maxContainers or 128,
		x1 = x1, x2 = x2, y1 = y1, y2 = y2, zMin = zMin, zMax = zMax,
		x = x1, y = y1, z = zMin,
		phase = "squares",
        retainProof = retainProof == true,
        discoveredObjects = {},
        captureBudget = captureBudget or {refs = 0, bytes = 0},
        protectedEntryIds = protectedEntryIds,
        capture = { squares = {}, tasks = {} },
        verifyTask = 1, verifyItem = 0,
		results = {},
		seenEntryIds = {},
		excludedEntryIds = {},
		containerTasks = {},
		taskIndex = 1,
		itemIndex = 0,
		limitHit = false,
		anySquareLoaded = false,
		metrics = {
			squaresVisited = 0,
			loadedSquares = 0,
			nodesDetected = 0,
			cookingContainersExcluded = 0,
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

local function queueIncrementalContainer(state, obj, containerIndex)
	local eligible, rejectionReason = GlobalStorageSiK.Utils.isNetworkStorageContainer(obj, containerIndex)
	if not eligible and rejectionReason == "cooking" then
		local excludedId = GlobalStorageSiK.Utils.getContainerId(obj, containerIndex)
		if excludedId and not state.excludedEntryIds[excludedId] then
			state.excludedEntryIds[excludedId] = true
			state.metrics.cookingContainersExcluded = state.metrics.cookingContainersExcluded + 1
		end
	elseif eligible then
		local entry = GlobalStorageSiK.Utils.buildContainerEntry(obj, containerIndex)
		if entry and not state.seenEntryIds[entry.id] then
			if #state.results >= state.limit then
				state.limitHit = true
				state.phase = "snapshots"
				state.discovery = nil
				return
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
			local task = { entry = entry, container = container, object = obj,
                containerIndex = containerIndex, refs = {},
                squareProof = state.discovery.proof, special = state.discovery.special,
                objectIndex = state.discovery.index - 1 }
            state.containerTasks[#state.containerTasks + 1] = task
            state.capture.tasks[#state.capture.tasks + 1] = task
			state.metrics.nodesDetected = state.metrics.nodesDetected + 1
		end
	end
end

-- Each visit performs one square lookup, one object lookup or one container.
-- Dense tiles and multi-compartment objects yield through the same budget as items.
local function scanIncrementalSquare(state)
	local cursor = state.discovery
	if not cursor then
		state.metrics.squaresVisited = state.metrics.squaresVisited + 1
		local square = state.cell:getGridSquare(state.x, state.y, state.z)
        if not captureRef(state) then return end
        local proof = { x = state.x, y = state.y, z = state.z, square = square,
            normal = {count = 0, refs = {}}, special = {count = 0, refs = {}} }
        state.capture.squares[#state.capture.squares + 1] = proof
        if not square then advanceSquareCursor(state); return end
		state.anySquareLoaded = true
		state.metrics.loadedSquares = state.metrics.loadedSquares + 1
		local normal = square:getObjects()
        local special = square.getSpecialObjects and square:getSpecialObjects() or nil
        proof.normal.count = normal and normal:size() or 0
        proof.special.count = special and special:size() or 0
        state.discovery = { square = square, list = normal, index = 0, special = false, proof = proof }
		return
	end
    local proof = cursor.special and cursor.proof.special or cursor.proof.normal
    if state.cell:getGridSquare(state.x, state.y, state.z) ~= cursor.square
        or (cursor.list and cursor.list:size() or 0) ~= proof.count then
        state.invalidated = true; return
    end
    if cursor.object then
		local index = cursor.containerIndex
		if index < cursor.containerCount then
			cursor.containerIndex = index + 1
			queueIncrementalContainer(state, cursor.object, index)
			return
		end
		cursor.object = nil
	end
	if cursor.list and cursor.index < cursor.list:size() then
		local obj = cursor.list:get(cursor.index)
		cursor.index = cursor.index + 1
		if obj then
            if not captureRef(state) then return end
            local prior = state.discoveredObjects[obj]
            local count = prior or GlobalStorageSiK.Utils.getContainerCount(obj)
            proof.refs[#proof.refs + 1] = {object = obj, count = count}
            if prior ~= nil then return end
            state.discoveredObjects[obj] = count
			cursor.object = obj
			cursor.containerCount = count
			cursor.containerIndex = 0
		end
		return
	end
	if not cursor.special then
		cursor.special = true
		cursor.list = cursor.square.getSpecialObjects and cursor.square:getSpecialObjects() or nil
		cursor.index = 0
		return
	end
	state.discovery = nil
	advanceSquareCursor(state)
end

local function scanIncrementalItem(state)
	local task = state.containerTasks[state.taskIndex]
	if not task then
		state.phase = "done"
		state.containerTasks = nil
		return
	end
    if state.protectedEntryIds and state.protectedEntryIds[task.entry.id] then
        state.taskIndex, state.itemIndex = state.taskIndex + 1, 0; return
    end
	local container = task.container
	local items = container and container.getItems and container:getItems() or nil
	local size = items and items.size and items:size() or 0
    if task.count == nil then task.count = size end
    if size ~= task.count then state.invalidated = true; return end
	if state.itemIndex >= size then
		state.taskIndex = state.taskIndex + 1
		state.itemIndex = 0
		return
	end
	local item = items:get(state.itemIndex)
    if not captureRef(state) then return end
    task.refs[state.itemIndex + 1] = item
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

--- Ejecuta una porcion acotada. `maxUnits` cuenta pasos de cursor durante la fase de
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
		elseif state.phase == "snapshots" then
			scanIncrementalItem(state)
        else
            verifyIncrementalItem(state)
		end
		units = units + 1
        if state.invalidated then state.phase = "done"; break end
		if timeBudget > 0 and units > 0 and getTimestampMs
			and getTimestampMs() - started >= timeBudget then
			break
		end
	end
	state.workUnits = (state.workUnits or 0) + units
    if state.phase == "done" and not state.retainProof then
        if not state.validated and not state.invalidated then
            GlobalStorageSiK.ZoneScanner.beginValidation(state)
        else GlobalStorageSiK.ZoneScanner.releaseIncremental(state) end
    end
	return state.phase == "done", units
end

---@param state table|nil
---@return boolean
function GlobalStorageSiK.ZoneScanner.isIncrementalDone(state)
	return state == nil or state.phase == "done"
end
