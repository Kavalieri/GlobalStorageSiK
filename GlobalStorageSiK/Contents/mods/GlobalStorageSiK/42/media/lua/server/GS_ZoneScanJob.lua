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

local jobs = {}
local tickInstalled = false
local nextGlobalRunMs = 0

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

local function completeZone(job)
	local state = job.zoneState
	local zone = job.zones[job.zoneIndex]
	if not state or not zone then return end
	if state.anySquareLoaded then zone.everScanLoaded = true end
	local summary = GlobalStorageSiK.ZoneRefresh.mergeScanResults(
		GlobalStorageSiK.Zones.getRegistry(), zone, state.results,
		GlobalStorageSiK.ZonePriority.zoneArea(zone), state.anySquareLoaded,
		state.excludedEntryIds)
	job.totals.added = job.totals.added + (summary.added or 0)
	job.totals.updated = job.totals.updated + (summary.updated or 0)
	job.totals.offline = job.totals.offline + (summary.offline or 0)
	job.totals.outOfRange = job.totals.outOfRange + (summary.outOfRange or 0)
	job.totals.removedIneligible = job.totals.removedIneligible + (summary.removedIneligible or 0)
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

local function finishJob(networkId, job)
	jobs[networkId] = nil
	job.totals.durationMs = math.max(0, nowMs() - job.startedMs)
	job.totals._freshSnapshotScope = job.zoneId or "network"
	job.totals._background = job.background == true
	job.totals._startRevision = job.startRevision or 0
	if GlobalStorageSiK.RegistryStore and GlobalStorageSiK.RegistryStore.notifyChanged then
		GlobalStorageSiK.RegistryStore.notifyChanged()
	end
	GlobalStorageSiK.Log.info("ZoneScanJob", string.format(
		"complete network=%s durationMs=%d zones=%d nodes=%d instances=%d distinctTypes=%d snapshotRows=%d squares=%d loadedSquares=%d added=%d updated=%d offline=%d cookingExcluded=%d removedIneligible=%d limitHit=%s",
		tostring(networkId), job.totals.durationMs or 0, job.totals.zones or 0,
		job.totals.nodesScanned or 0, job.totals.itemInstances or 0,
		job.totals.distinctTypes or 0, job.totals.snapshotRows or 0,
		job.totals.squaresVisited or 0, job.totals.loadedSquares or 0,
		job.totals.added or 0, job.totals.updated or 0, job.totals.offline or 0,
		job.totals.cookingContainersExcluded or 0, job.totals.removedIneligible or 0,
		tostring(job.totals.limitHit == true)))
	if GlobalStorageSiK.Server and GlobalStorageSiK.Server.onNetworkScanComplete then
		GlobalStorageSiK.Server.onNetworkScanComplete(networkId, job.totals, job.watchers)
	end
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

	if GlobalStorageSiK.RedistributeJob and GlobalStorageSiK.RedistributeJob.isActive(networkId) then
		job.nextRunMs = now + BUSY_DELAY_MS
		return
	end
	local player = resolveAnyWatcher(job)
	if not player then
		-- La captura es util solo para una peticion viva. Liberar referencias a
		-- contenedores si todos los observadores se desconectaron.
		jobs[networkId] = nil
		GlobalStorageSiK.Log.warn("ZoneScanJob", "cancel no_player network=" .. tostring(networkId))
		return
	end
	local acquired = GlobalStorageSiK.TransferLock.acquire(networkId, player, "zoneScan")
	if not acquired then
		job.nextRunMs = now + BUSY_DELAY_MS
		return
	end
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
	end)
	GlobalStorageSiK.TransferLock.release(networkId, player)
	if not ok then
		jobs[networkId] = nil
		GlobalStorageSiK.Log.error("ZoneScanJob", "failed network=" .. tostring(networkId) .. " error=" .. tostring(err))
		if GlobalStorageSiK.Server and GlobalStorageSiK.Server.onNetworkScanFailed then
			GlobalStorageSiK.Server.onNetworkScanFailed(networkId, job.watchers, tostring(err))
		end
		return
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
		startRevision = GlobalStorageSiK.Index.getInventoryRevision(networkId),
		nextRunMs = 0,
		watchers = {},
		distinctTypeSet = {},
		totals = {
			added = 0, updated = 0, offline = 0, outOfRange = 0,
			removedIneligible = 0, cookingContainersExcluded = 0,
			zones = 0, limitHit = false, squaresVisited = 0,
			loadedSquares = 0, nodesScanned = 0, itemInstances = 0,
			distinctTypes = 0, snapshotRows = 0,
		},
	}
	if opts.background ~= true then addWatcher(job, player, opts.searchQuery) end
	jobs[networkId] = job
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
