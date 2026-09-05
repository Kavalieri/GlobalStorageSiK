--[[
	GlobalStorageSiK - Reescaneo incremental y equitativo por red
	Autor: SiK
	Descripcion: descubre contenedores y construye snapshots con presupuesto
	por tick. Nunca transmite Global ModData: el servidor persiste la fuente
	autoritativa y GS_Server envia terminalState solo a observadores de la red.
]]

require "GS_PlayerUtils"
require "GS_Index"
require "GS_TransferLock"
require "GS_ZonePriority"
require "GS_ZoneRefresh"
require "GS_ZoneScanner"

GlobalStorageSiK.ZoneScanJob = GlobalStorageSiK.ZoneScanJob or {}

local STEP_DELAY_MS = 50
local BUSY_DELAY_MS = 250
local MAX_UNITS_PER_STEP = 50
local MAX_STEP_MS = 5
local STALL_TIMEOUT_MS = 30000

local jobs = {}
-- Último cierre por red: el terminal debe poder distinguir un trabajo acabado
-- de la ausencia histórica de trabajo, incluso después de liberar el job.
local terminalStates = {}
local terminalStateOrder = {}
local MAX_TERMINAL_STATES = 128
local tickInstalled = false
local nextGlobalRunMs = 0

local function removeTerminalStateOrder(networkId)
	for i = #terminalStateOrder, 1, -1 do
		if terminalStateOrder[i] == networkId then table.remove(terminalStateOrder, i) end
	end
end

local function setTerminalState(networkId, state)
	removeTerminalStateOrder(networkId)
	terminalStates[networkId] = state
	terminalStateOrder[#terminalStateOrder + 1] = networkId
	if #terminalStateOrder > MAX_TERMINAL_STATES then
		local oldest = table.remove(terminalStateOrder, 1)
		if oldest then terminalStates[oldest] = nil end
	end
end

local function nowMs()
	return getTimestampMs and getTimestampMs() or 0
end

local function resolvePlayer(username)
	return GlobalStorageSiK.PlayerUtils.resolveByUsername(username)
end

local function sortedZones(networkId, zoneId)
	local registry = GlobalStorageSiK.Zones.getRegistry()
	local rows = GlobalStorageSiK.ZonePriority.listSorted(registry, networkId)
	if not zoneId or zoneId == "" then return rows end
	local filtered = {}
	for i = 1, #rows do
		if rows[i] and rows[i].id == zoneId then
			filtered[1] = rows[i]
			break
		end
	end
	return filtered
end

local function addWatcher(job, player, searchQuery)
	if not job or not player or not player.getUsername then return end
	local username = player:getUsername()
	if username and username ~= "" then
		job.watchers[username] = searchQuery or job.watchers[username] or ""
	end
end

local function resolveAnyWatcher(job)
	local player = resolvePlayer(job.username)
	if player then return player end
	for username in pairs(job.watchers or {}) do
		player = resolvePlayer(username)
		if player then return player end
	end
	return nil
end

local function mergeDistinctTypes(job, state)
	for fullType in pairs(state.distinctTypeSet or {}) do
		if not job.distinctTypeSet[fullType] then
			job.distinctTypeSet[fullType] = true
			job.totals.distinctTypes = job.totals.distinctTypes + 1
		end
	end
end

local function progressStatus(job)
	local total = #(job and job.zones or {})
	local completed = math.max(0, (job and job.zoneIndex or 1) - 1)
	local fraction = 0
	local state = job and job.zoneState or nil
	local zone = job and job.zones and job.zones[job.zoneIndex] or nil
	if state and zone then
		if state.phase == "snapshots" then
			local tasks = math.max(1, #(state.containerTasks or {}))
			fraction = 0.70 + 0.30 * math.min(1,
				math.max(0, ((tonumber(state.taskIndex) or 1) - 1) / tasks))
		else
			local squares = math.max(1,
				((tonumber(zone.x2) or 0) - (tonumber(zone.x1) or 0) + 1)
				* ((tonumber(zone.y2) or 0) - (tonumber(zone.y1) or 0) + 1)
				* ((tonumber(zone.zMax) or tonumber(zone.z) or 0)
					- (tonumber(zone.zMin) or tonumber(zone.z) or 0) + 1))
			fraction = 0.70 * math.min(1,
				math.max(0, (tonumber(state.metrics and state.metrics.squaresVisited) or 0) / squares))
		end
	end
	return {
		state = "RUNNING", phase = job and job.phase or "preparing",
		zoneId = zone and zone.id or nil, zoneName = zone and zone.name or nil,
		zonesDone = completed, zonesTotal = total,
		progressDone = math.min(total, completed + fraction), progressTotal = total,
		startedMs = job and job.startedMs or 0,
		lastProgressMs = job and job.lastProgressMs or 0,
		failedZones = job and job.totals and job.totals.failedZones or 0,
	}
end

local function markProgress(job, now, phase)
	job.lastProgressMs = now
	job.phase = phase or job.phase or "preparing"
	if now - (job.lastUiProgressMs or 0) >= 250
		and GlobalStorageSiK.Server and GlobalStorageSiK.Server.onNetworkScanProgress then
		job.lastUiProgressMs = now
		GlobalStorageSiK.Server.onNetworkScanProgress(job.networkId,
			progressStatus(job), job.watchers)
	end
end

local function currentZone(job)

	return job and job.zones and job.zones[job.zoneIndex] or nil

end

local function stateProgressToken(state)

	if not state then return "none" end
	return table.concat({
		tostring(state.phase or ""), tostring(state.x or ""), tostring(state.y or ""),
		tostring(state.z or ""), tostring(state.taskIndex or ""),
		tostring(state.itemIndex or ""), tostring(#(state.results or {})),
	}, "|")

end

local function completeZone(job)
	local state = job.zoneState
	local zone = job.zones[job.zoneIndex]
	if not state or not zone then return end
	-- El scan cede el lock entre pasos. No fusionar zona a zona: si una
	-- transferencia cambia inventoryRevision, el registro quedaria compuesto
	-- por instantes distintos. Se conserva staging acotado y se hace commit
	-- atomico bajo el lock solo al certificar la revision inicial.
	job.stagedZones[#job.stagedZones + 1] = {
		zone = zone, results = state.results,
		area = GlobalStorageSiK.ZonePriority.zoneArea(zone),
		loaded = state.anySquareLoaded,
		excludedEntryIds = state.excludedEntryIds,
	}
	job.totals.cookingContainersExcluded = job.totals.cookingContainersExcluded
		+ (state.metrics.cookingContainersExcluded or 0)
	job.totals.zones = job.totals.zones + 1
	job.totals.limitHit = job.totals.limitHit or state.limitHit == true
	job.totals.squaresVisited = job.totals.squaresVisited + (state.metrics.squaresVisited or 0)
	job.totals.loadedSquares = job.totals.loadedSquares + (state.metrics.loadedSquares or 0)
	job.totals.nodesScanned = job.totals.nodesScanned + (state.metrics.nodesDetected or 0)
	job.totals.itemInstances = job.totals.itemInstances + (state.metrics.itemInstances or 0)
	job.totals.snapshotRows = job.totals.snapshotRows + (state.metrics.snapshotRows or 0)
	mergeDistinctTypes(job, state)
	job.zoneState = nil
	job.zoneIndex = job.zoneIndex + 1
end

local function commitStaged(job)
	local currentRevision = GlobalStorageSiK.Index.getInventoryRevision(job.networkId)
	if currentRevision ~= (job.startRevision or 0) then
		job.totals._stagedDiscarded = true
		return false
	end
	local registry = GlobalStorageSiK.Zones.getRegistry()
	for i = 1, #(job.stagedZones or {}) do
		local staged = job.stagedZones[i]
		if staged.loaded then staged.zone.everScanLoaded = true end
		local summary = GlobalStorageSiK.ZoneRefresh.mergeScanResults(
			registry, staged.zone, staged.results, staged.area, staged.loaded,
			staged.excludedEntryIds)
		job.totals.added = job.totals.added + (summary.added or 0)
		job.totals.updated = job.totals.updated + (summary.updated or 0)
		job.totals.offline = job.totals.offline + (summary.offline or 0)
		job.totals.outOfRange = job.totals.outOfRange + (summary.outOfRange or 0)
		job.totals.removedIneligible = job.totals.removedIneligible
			+ (summary.removedIneligible or 0)
	end
	job.stagedZones = {}
	return true
end

local function discardJobState(job)

	if not job then return end
	job.zoneState = nil
	job.zones = {}
	job.watchers = {}
	job.distinctTypeSet = {}
	job.stagedZones = {}

end

local function recordTerminalState(networkId, job, state, reason)
	local zone = currentZone(job)
	setTerminalState(networkId, {
		state = state, reason = reason, phase = job.phase or "finalizing",
		reasonCode = GlobalStorageSiK.I18n and GlobalStorageSiK.I18n.scanReasonCode
			and GlobalStorageSiK.I18n.scanReasonCode(reason) or "UNKN",
		zoneId = zone and zone.id or nil, zoneName = zone and zone.name or nil,
		zonesDone = math.max(0, (job.zoneIndex or 1) - 1), zonesTotal = #(job.zones or {}),
		startedMs = job.startedMs or 0, lastProgressMs = job.lastProgressMs or 0,
		finishedMs = nowMs(), failedZones = job.totals and job.totals.failedZones or 0,
	})
end

local function finishCancelled(networkId, job, reason)

	jobs[networkId] = nil
	local state = reason == "timed_out" and "TIMED_OUT" or "CANCELLED"
	recordTerminalState(networkId, job, state, reason)
	local durationMs = math.max(0, nowMs() - (job.startedMs or nowMs()))
	GlobalStorageSiK.Log.warn("ZoneScanJob", "cancel network=" .. tostring(networkId)
		.. " reason=" .. tostring(reason or "manual") .. " durationMs=" .. tostring(durationMs))
	if GlobalStorageSiK.Server and GlobalStorageSiK.Server.onNetworkScanCancelled then
		GlobalStorageSiK.Server.onNetworkScanCancelled(networkId, job.watchers, reason or "manual")
	end
	discardJobState(job)

end

local function finishJob(networkId, job)
	jobs[networkId] = nil
	job.totals.durationMs = math.max(0, nowMs() - job.startedMs)
	local state = ((job.totals.failedZones or 0) > 0 or job.totals._stagedDiscarded)
		and "FAILED" or "COMPLETED"
	job.totals._terminalState = state
	if state == "COMPLETED" then job.totals._freshSnapshotScope = job.zoneId or "network" end
	job.totals._background = job.background == true
	job.totals._startRevision = job.startRevision or 0
	job.totals._startContentSignature = job.startContentSignature
	recordTerminalState(networkId, job, state, state == "FAILED" and "zone_error" or "complete")
	if not job.totals._stagedDiscarded and GlobalStorageSiK.RegistryStore
		and GlobalStorageSiK.RegistryStore.notifyChanged then
		GlobalStorageSiK.RegistryStore.notifyChanged()
	end
	GlobalStorageSiK.Log.info("ZoneScanJob", string.format(
		"complete network=%s state=%s durationMs=%d zones=%d nodes=%d instances=%d distinctTypes=%d snapshotRows=%d squares=%d loadedSquares=%d added=%d updated=%d offline=%d failedZones=%d cookingExcluded=%d removedIneligible=%d limitHit=%s",
		tostring(networkId), state, job.totals.durationMs or 0, job.totals.zones or 0,
		job.totals.nodesScanned or 0, job.totals.itemInstances or 0,
		job.totals.distinctTypes or 0, job.totals.snapshotRows or 0,
		job.totals.squaresVisited or 0, job.totals.loadedSquares or 0,
		job.totals.added or 0, job.totals.updated or 0, job.totals.offline or 0, job.totals.failedZones or 0,
		job.totals.cookingContainersExcluded or 0, job.totals.removedIneligible or 0,
		tostring(job.totals.limitHit == true)))
	if GlobalStorageSiK.Server and GlobalStorageSiK.Server.onNetworkScanComplete then
		GlobalStorageSiK.Server.onNetworkScanComplete(networkId, job.totals, job.watchers)
	end
	-- El callback anterior consume totals/watchers de forma sincrona. A partir
	-- de aqui ningún cierre debe conservar zonas, resultados ni referencias a
	-- contenedores, tanto si hizo commit como si descartó por revisión cambiante.
	discardJobState(job)
end

local function onTick()
	local now = nowMs()
	if now < nextGlobalRunMs then return end
	local networkId, job, oldestDue = nil, nil, nil
	for candidateId, candidate in pairs(jobs) do
		if now >= candidate.nextRunMs and (oldestDue == nil or candidate.nextRunMs < oldestDue) then
			networkId, job, oldestDue = candidateId, candidate, candidate.nextRunMs
		end
	end
	if not job then
		if tickInstalled and Events and Events.OnTick then
			Events.OnTick.Remove(onTick)
			tickInstalled = false
		end
		return
	end
	nextGlobalRunMs = now + STEP_DELAY_MS
	if now > 0 and job.lastProgressMs and now - job.lastProgressMs > STALL_TIMEOUT_MS then
		finishCancelled(networkId, job, "timed_out")
		return
	end

	if GlobalStorageSiK.RedistributeJob and GlobalStorageSiK.RedistributeJob.isActive(networkId) then
		job.nextRunMs = now + BUSY_DELAY_MS
		return
	end
	local player = resolveAnyWatcher(job)
	if not player then
		-- La captura es util solo para una peticion viva. Liberar referencias a
		-- contenedores si todos los observadores se desconectaron.
		finishCancelled(networkId, job, "no_player")
		return
	end
	local acquired = GlobalStorageSiK.TransferLock.acquire(networkId, player, "zoneScan")
	if not acquired then
		job.nextRunMs = now + BUSY_DELAY_MS
		return
	end
	local beforeToken = stateProgressToken(job.zoneState)
	local ok, err = pcall(function()
		if job.zoneIndex > #job.zones then return end
		if not job.zoneState then
			job.zoneState = GlobalStorageSiK.ZoneScanner.beginIncremental(
				job.zones[job.zoneIndex], GlobalStorageSiK.Sandbox.getMaxContainersPerZone())
			if not job.zoneState then
				job.zoneIndex = job.zoneIndex + 1
				return
			end
		end
		if GlobalStorageSiK.ZoneScanner.stepIncremental(job.zoneState, MAX_UNITS_PER_STEP, MAX_STEP_MS) then
			completeZone(job)
		end
		if job.zoneIndex > #job.zones then commitStaged(job) end
	end)
	GlobalStorageSiK.TransferLock.release(networkId, player)
	if not ok then
		local zone = currentZone(job)
		job.totals.failedZones = (job.totals.failedZones or 0) + 1
		GlobalStorageSiK.Log.warn("ZoneScanJob", "zone_failed network=" .. tostring(networkId)
			.. " zone=" .. tostring(zone and zone.id or "?") .. " error=" .. tostring(err))
		job.zoneState = nil
		job.zoneIndex = job.zoneIndex + 1
		markProgress(job, now, "recovering")
	elseif beforeToken ~= stateProgressToken(job.zoneState) then
		markProgress(job, now, job.zoneState and job.zoneState.phase or "merging")
	end
	if job.zoneIndex > #job.zones then
		finishJob(networkId, job)
	else
		job.nextRunMs = now + STEP_DELAY_MS
	end
end

local function ensureTickInstalled()
	if tickInstalled then return end
	tickInstalled = true
	if Events and Events.OnTick then Events.OnTick.Add(onTick) end
end

--- Inicia un unico trabajo por red. Una segunda peticion se convierte en
--- observador del trabajo existente y recibe su resultado, sin repetir scan.
---@param player IsoPlayer
---@param networkId string
---@param opts table|nil { zoneId=string, searchQuery=string, background=boolean }
---@return boolean started
---@return string|nil reason
function GlobalStorageSiK.ZoneScanJob.start(player, networkId, opts)
	opts = opts or {}
	if not player or not networkId or networkId == "" then return false, "invalid" end
	local existing = jobs[networkId]
	if existing then
		addWatcher(existing, player, opts.searchQuery)
		return false, "active"
	end
	if GlobalStorageSiK.RedistributeJob and GlobalStorageSiK.RedistributeJob.isActive(networkId) then
		return false, "redistribute_active"
	end
	local zones = sortedZones(networkId, opts.zoneId)
	if opts.zoneId and #zones == 0 then return false, "zone_not_found" end
	local username = player.getUsername and player:getUsername() or nil
	if not username or username == "" then return false, "no_player" end
	local job = {
		username = username,
		networkId = networkId,
		zoneId = opts.zoneId,
		zones = zones,
		zoneIndex = 1,
		zoneState = nil,
		background = opts.background == true,
		startedMs = nowMs(),
		lastProgressMs = nowMs(),
		phase = "preparing",
		startRevision = GlobalStorageSiK.Index.getInventoryRevision(networkId),
		startContentSignature = GlobalStorageSiK.Index.contentSignature(networkId),
		nextRunMs = 0,
		watchers = {},
		distinctTypeSet = {},
		stagedZones = {},
		totals = {
			added = 0, updated = 0, offline = 0, outOfRange = 0,
			removedIneligible = 0, cookingContainersExcluded = 0,
			zones = 0, limitHit = false, squaresVisited = 0,
			loadedSquares = 0, nodesScanned = 0, itemInstances = 0,
			distinctTypes = 0, snapshotRows = 0,
			failedZones = 0,
		},
	}
	terminalStates[networkId] = nil
	removeTerminalStateOrder(networkId)
	if opts.background ~= true then addWatcher(job, player, opts.searchQuery) end
	jobs[networkId] = job
	-- Publicar el 0% real antes del primer lote. Sin este estado inicial la
	-- cabecera conservaba una barra vacia hasta el primer umbral de 250 ms y,
	-- con una sola zona, el siguiente estado visible podia saltar ya al 70%.
	if opts.background ~= true then markProgress(job, job.startedMs, "preparing") end
	ensureTickInstalled()
	GlobalStorageSiK.Log.info("ZoneScanJob", "start network=" .. tostring(networkId)
		.. " zones=" .. tostring(#zones) .. " scope=" .. tostring(opts.zoneId or "network"))
	return true, nil
end

---@param player IsoPlayer
---@param networkId string
---@param searchQuery string|nil
function GlobalStorageSiK.ZoneScanJob.addWatcher(player, networkId, searchQuery)
	addWatcher(jobs[networkId], player, searchQuery)
end

---@param networkId string|nil
---@return boolean
function GlobalStorageSiK.ZoneScanJob.isActive(networkId)
	return networkId ~= nil and jobs[networkId] ~= nil
end

---@param networkId string|nil
---@return table
function GlobalStorageSiK.ZoneScanJob.getStatus(networkId)

	local job = networkId and jobs[networkId] or nil
	if not job then return terminalStates[networkId] or { state = "IDLE" } end
	return progressStatus(job)

end

--- Reemplaza un cierre ya registrado cuando la certificación final de snapshot
--- detecta una condición posterior al barrido. No reabre ni muta el job.
---@param networkId string|nil
---@param state string
---@param reason string|nil
function GlobalStorageSiK.ZoneScanJob.overrideTerminalState(networkId, state, reason)
	if not networkId or jobs[networkId] then return false end
	local status = terminalStates[networkId] or { state = "IDLE" }
	status.state = state
	status.reason = reason
	status.reasonCode = GlobalStorageSiK.I18n and GlobalStorageSiK.I18n.scanReasonCode
		and GlobalStorageSiK.I18n.scanReasonCode(reason) or "UNKN"
	status.finishedMs = nowMs()
	setTerminalState(networkId, status)
	return true
end

---@param networkId string|nil
---@param reason string|nil
---@return boolean cancelled
function GlobalStorageSiK.ZoneScanJob.cancel(networkId, reason)

	local job = networkId and jobs[networkId] or nil
	if not job then return false end
	finishCancelled(networkId, job, reason or "manual")
	return true

end

--- Limpia trabajo y cierre historico al eliminar una red.
---@param networkId string|nil
function GlobalStorageSiK.ZoneScanJob.clearNetwork(networkId)
	if not networkId then return end
	local job = jobs[networkId]
	if job then discardJobState(job) end
	jobs[networkId] = nil
	terminalStates[networkId] = nil
	removeTerminalStateOrder(networkId)
end
