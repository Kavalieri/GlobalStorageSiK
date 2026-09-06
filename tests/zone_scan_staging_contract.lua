-- Executable author contract for atomic ZoneScan staging.
-- Uses deterministic Lua fixtures only; no Project Zomboid runtime is opened.

local Support = dofile("tests/helpers/sik_ui_contract_support.lua")
local suite = Support.newSuite("zone_scan_staging_contract")

local MODULE = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/server/GS_ZoneScanJob.lua"

local function read(path)
	local file = assert(io.open(path, "rb"), path)
	local text = file:read("*a")
	file:close()
	return text
end

local function section(text, first, last)
	local from = assert(text:find(first, 1, true), "missing section " .. first)
	local to = assert(text:find(last, from + #first, true), "missing boundary " .. last)
	return text:sub(from, to - 1)
end

local source = read(MODULE)
local completeZoneSource = section(source, "local function completeZone", "local function commitStaged")

local now = 1000
local revisionByNetwork = {}
local players = {}
local activeTick = nil
local lockHeld = false
local mergeCalls = {}
local notifyCount = 0
local completed = {}
local cancelled = {}
local registry = { zonesByNetwork = {} }

getTimestampMs = function() return now end
Events = {
	OnTick = {
		Add = function(callback) activeTick = callback end,
		Remove = function(callback)
			if activeTick == callback then activeTick = nil end
		end,
	},
}

for _, dependency in ipairs({
	"GS_PlayerUtils", "GS_Index", "GS_TransferLock", "GS_ZonePriority",
	"GS_ZoneRefresh", "GS_ZoneScanner",
}) do
	package.loaded[dependency] = true
end

GlobalStorageSiK = {
	PlayerUtils = {
		resolveByUsername = function(username) return players[username] end,
	},
	Index = {
		getInventoryRevision = function(networkId)
			return revisionByNetwork[networkId] or 0
		end,
		contentSignature = function(networkId)
			return "fixture-signature:" .. tostring(networkId)
		end,
	},
	TransferLock = {
		acquire = function()
			assert(not lockHeld, "scan acquired an already-held lock")
			lockHeld = true
			return true
		end,
		release = function()
			assert(lockHeld, "scan released a lock it did not hold")
			lockHeld = false
		end,
	},
	Zones = {
		getRegistry = function() return registry end,
	},
	ZonePriority = {
		listSorted = function(registryValue, networkId)
			assert(registryValue == registry, "scan used a foreign registry")
			return registry.zonesByNetwork[networkId] or {}
		end,
		zoneArea = function(zone) return { zone.id .. "-area" } end,
	},
	ZoneRefresh = {
		mergeScanResults = function(registryValue, zone, results, area, loaded, excluded)
			assert(lockHeld, "staged zone merged outside the transfer lock")
			assert(registryValue == registry, "merge targeted a foreign registry")
			mergeCalls[#mergeCalls + 1] = {
				zone = zone, results = results, area = area,
				loaded = loaded, excluded = excluded,
			}
			zone._mergedCount = (zone._mergedCount or 0) + 1
			return {
				added = 1, updated = 2, offline = 3,
				outOfRange = 4, removedIneligible = 5,
			}
		end,
	},
	ZoneScanner = {
		beginIncremental = function(zone)
			return {
				phase = "scan", results = { zone.id .. "-result" },
				anySquareLoaded = true, excludedEntryIds = { zone.id .. "-excluded" },
				metrics = {
					cookingContainersExcluded = 0, squaresVisited = 1,
					loadedSquares = 1, nodesDetected = 1,
					itemInstances = 1, snapshotRows = 1,
				},
				distinctTypeSet = { ["Base." .. zone.id] = true },
			}
		end,
		stepIncremental = function() return true end,
	},
	Sandbox = {
		getMaxContainersPerZone = function() return 500 end,
	},
	RedistributeJob = {
		isActive = function() return false end,
	},
	RegistryStore = {
		notifyChanged = function() notifyCount = notifyCount + 1 end,
	},
	Server = {
		onNetworkScanComplete = function(networkId, totals, watchers)
			completed[networkId] = { totals = totals, watchers = watchers }
		end,
		onNetworkScanCancelled = function(networkId, watchers, reason)
			cancelled[networkId] = { watchers = watchers, reason = reason }
		end,
	},
	I18n = {
		scanReasonCode = function(reason) return tostring(reason or "unknown") end,
	},
	Log = {
		info = function() end,
		warn = function() end,
	},
}

assert(loadfile(MODULE))()

local player = {
	getUsername = function() return "Kava" end,
}
players.Kava = player

local function jobsUpvalue()
	assert(type(activeTick) == "function", "ZoneScan OnTick is not installed")
	for i = 1, 32 do
		local name, value = debug.getupvalue(activeTick, i)
		if not name then break end
		if name == "jobs" then return value end
	end
	error("ZoneScan OnTick does not retain its bounded jobs table")
end

local function zones(networkId)
	local result = {
		{ id = networkId .. "-A", name = "A" },
		{ id = networkId .. "-B", name = "B" },
	}
	registry.zonesByNetwork[networkId] = result
	return result
end

local function start(networkId, revision)
	now = now + 1000
	revisionByNetwork[networkId] = revision
	local scanZones = zones(networkId)
	local ok, reason = GlobalStorageSiK.ZoneScanJob.start(player, networkId, {})
	assert(ok and reason == nil, "scan did not start: " .. tostring(reason))
	local job = assert(jobsUpvalue()[networkId], "started job is not retained")
	return job, scanZones
end

local function tick(delta)
	now = now + (delta or 100)
	assert(type(activeTick) == "function", "ZoneScan OnTick disappeared early")
	activeTick()
	assert(not lockHeld, "ZoneScan leaked the transfer lock")
end

local function finishIdleTick()
	if activeTick then tick(100) end
end

local function assertReferencesCleared(job, label)
	local watcherCount, distinctCount = 0, 0
	for _ in pairs(job.watchers or {}) do watcherCount = watcherCount + 1 end
	for _ in pairs(job.distinctTypeSet or {}) do distinctCount = distinctCount + 1 end
	assert(job.zoneState == nil, label .. " retained zoneState")
	assert(#(job.zones or {}) == 0, label .. " retained zones")
	assert(#(job.stagedZones or {}) == 0, label .. " retained stagedZones")
	assert(watcherCount == 0, label .. " retained watchers")
	assert(distinctCount == 0, label .. " retained distinct types")
end

Support.check(suite, "completeZone only stages and never mutates registry", function()
	mergeCalls = {}
	local job, scanZones = start("stage-only", 10)
	tick()
	assert(#job.stagedZones == 1, "completed zone was not staged")
	assert(#mergeCalls == 0, "completeZone merged before all zones completed")
	assert(scanZones[1]._mergedCount == nil, "completeZone mutated registry zone")
	assert(scanZones[1].everScanLoaded ~= true, "completeZone published loaded state")
	GlobalStorageSiK.ZoneScanJob.cancel("stage-only", "test_cleanup")
	finishIdleTick()
	return true
end)

Support.check(suite, "stable revision commits every zone once under one closure", function()
	mergeCalls = {}
	local notifyBefore = notifyCount
	local job, scanZones = start("stable", 20)
	tick()
	assert(#mergeCalls == 0 and #job.stagedZones == 1,
		"first zone escaped staging")
	tick()
	assert(#mergeCalls == 2, "stable close did not merge exactly two zones")
	assert(scanZones[1]._mergedCount == 1 and scanZones[2]._mergedCount == 1,
		"a staged zone merged more or less than once")
	assert(notifyCount == notifyBefore + 1, "stable close did not publish exactly once")
	assert(not GlobalStorageSiK.ZoneScanJob.isActive("stable"), "stable job remained active")
	assert(completed.stable and completed.stable.totals._terminalState == "COMPLETED",
		"stable close did not report COMPLETED")
	activeTick()
	assert(#mergeCalls == 2, "idle tick repeated a stable merge")
	return true
end)

Support.check(suite, "revision change discards all staging without publication", function()
	mergeCalls = {}
	local notifyBefore = notifyCount
	local job, scanZones = start("changed", 30)
	tick()
	assert(#job.stagedZones == 1, "first zone was not staged")
	revisionByNetwork.changed = 31
	tick()
	assert(#mergeCalls == 0, "stale staging mutated the registry")
	assert(scanZones[1]._mergedCount == nil and scanZones[2]._mergedCount == nil,
		"revision mismatch published a zone")
	assert(notifyCount == notifyBefore, "revision mismatch called notifyChanged")
	assert(completed.changed and completed.changed.totals._stagedDiscarded == true,
		"revision mismatch was not reported as discarded")
        assert(GlobalStorageSiK.ZoneScanJob.getStatus("changed").state == "INVALIDATED_BY_MUTATION",
                "revision mismatch did not close as INVALIDATED_BY_MUTATION")
	assertReferencesCleared(job, "revision mismatch")
	finishIdleTick()
	return true
end)

Support.check(suite, "manual cancel clears every retained scan reference", function()
	mergeCalls = {}
	local job = start("cancelled", 40)
	tick()
	assert(#job.stagedZones == 1, "cancel fixture has no staged data")
	assert(GlobalStorageSiK.ZoneScanJob.cancel("cancelled", "manual_test"),
		"active scan refused cancellation")
	assertReferencesCleared(job, "cancel")
	assert(cancelled.cancelled and cancelled.cancelled.reason == "manual_test",
		"cancel callback lost its reason")
	assert(GlobalStorageSiK.ZoneScanJob.getStatus("cancelled").state == "CANCELLED",
		"cancel did not publish terminal state")
	finishIdleTick()
	return true
end)

Support.check(suite, "timeout clears staging and all live references", function()
	mergeCalls = {}
	local job = start("timeout", 50)
	tick()
	assert(#job.stagedZones == 1, "timeout fixture has no staged data")
	tick(30001)
	assertReferencesCleared(job, "timeout")
	assert(cancelled.timeout and cancelled.timeout.reason == "timed_out",
		"timeout callback lost timed_out reason")
	assert(GlobalStorageSiK.ZoneScanJob.getStatus("timeout").state == "TIMED_OUT",
		"timeout did not publish TIMED_OUT")
	finishIdleTick()
	return true
end)

Support.check(suite, "source keeps merge and registry writes out of completeZone", function()
	assert(not completeZoneSource:find("mergeScanResults", 1, true),
		"completeZone directly merges registry")
	assert(not completeZoneSource:find("getRegistry", 1, true),
		"completeZone obtains mutable registry")
	assert(not completeZoneSource:find("everScanLoaded = true", 1, true),
		"completeZone publishes loaded state")
	return true
end)

Support.finish(suite)
