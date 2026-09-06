-- Author-side dynamic contract for ZoneScanJob scheduling and mutation safety.
-- All dependencies are deterministic mocks; this never touches PZ state.

local MODULE = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/server/GS_ZoneScanJob.lua"

local function scenario(config)
	local now = 0
	local tick, added, removed = nil, 0, 0
	local steps, begins, merges, releases = 0, 0, 0, 0
	local callbacks = { complete = {}, cancelled = {} }
	local registry = { publishedSnapshot = "old" }
	local revisions = { a = 1, b = 1 }
	local zones = { a = { { id = "za", x1 = 0, x2 = 0, y1 = 0, y2 = 0, z = 0 } },
		b = { { id = "zb", x1 = 0, x2 = 0, y1 = 0, y2 = 0, z = 0 } } }
	local scanner = config.scanner or {}

	GlobalStorageSiK = {
		PlayerUtils = { resolveByUsername = function(name)
			return name == "player" and { getUsername = function() return name end } or nil
		end },
		Index = {
			getInventoryRevision = function(network) return revisions[network] or 1 end,
			contentSignature = function(network) return "sig-" .. network end,
		},
		Zones = { getRegistry = function() return registry end },
		ZonePriority = {
			listSorted = function(_, network) return zones[network] end,
			zoneArea = function() return 1 end,
		},
		ZoneScanner = {
			beginIncremental = function(zone)
				begins = begins + 1
				if scanner.begin then return scanner.begin(zone) end
				return { phase = "scan", results = {}, metrics = {}, anySquareLoaded = false }
			end,
			stepIncremental = function(state)
				steps = steps + 1
				if scanner.step then return scanner.step(state, steps) end
				return true
			end,
		},
		ZoneRefresh = { mergeScanResults = function(reg)
			merges = merges + 1
			reg.publishedSnapshot = "new"
			return { added = 1 }
		end },
		TransferLock = {
			acquire = function() return true end,
			release = function() releases = releases + 1 end,
		},
		Sandbox = { getMaxContainersPerZone = function() return 50 end },
		RedistributeJob = { isActive = function() return false end },
		Server = {
			onNetworkScanComplete = function(network, totals) callbacks.complete[network] = totals end,
			onNetworkScanCancelled = function(network, _, reason) callbacks.cancelled[network] = reason end,
			onNetworkScanProgress = function() end,
		},
		I18n = { scanReasonCode = function(reason) return tostring(reason or "UNKN") end },
		RegistryStore = { notifyChanged = function() end },
		Log = { info = function() end, warn = function() end },
	}
	package.loaded["GS_ZoneScanJob"] = nil
	package.preload["GS_PlayerUtils"] = function() return true end
	package.preload["GS_Index"] = function() return true end
	package.preload["GS_TransferLock"] = function() return true end
	package.preload["GS_ZonePriority"] = function() return true end
	package.preload["GS_ZoneRefresh"] = function() return true end
	package.preload["GS_ZoneScanner"] = function() return true end
	Events = { OnTick = {
		Add = function(fn) tick = fn; added = added + 1 end,
		Remove = function(fn) if tick == fn then tick = nil end; removed = removed + 1 end,
	} }
	getTimestampMs = function() return now end
	dofile(MODULE)
	local jobApi = GlobalStorageSiK.ZoneScanJob
	local function at(value)
		now = value
		if tick then tick() end
	end
	local player = { getUsername = function() return "player" end }
	local function state()
		return jobApi.getStatus("a")
	end
	return {
		api = jobApi, player = player, at = at, revisions = revisions,
		registry = registry,
		counts = function() return steps, begins, merges, releases end,
		callbacks = callbacks, eventCounts = function() return added, removed, tick ~= nil end,
		state = state,
	}
end

local function checkMutation()
	local s = scenario({ scanner = { step = function() return false end } })
	assert(s.api.start(s.player, "a"))
	s.at(0) -- stages and commits only after the next due pass in this setup
	local before, _, _, beforeReleases = s.counts()
	s.revisions.a = 2
	s.at(50)
	local steps, _, merges, releases = s.counts()
	local status = s.state()
	assert(steps == before, "mutation advanced the scanner after invalidation")
	assert(merges == 0, "mutation committed staged scan data")
	assert(releases == beforeReleases, "mutation acquired a lock before invalidating")
	assert(status.state == "INVALIDATED_BY_MUTATION", "mutation did not publish terminal invalidation")
	assert(s.registry.publishedSnapshot == "old", "mutation replaced the published snapshot")
	s.at(100) -- terminal cleanup pass removes the now-empty scheduler hook
	assert(select(3, s.eventCounts()) == false, "invalidated job left OnTick installed")
end

local function checkFutureDueAndIsolation()
	local s = scenario({ scanner = { step = function() return false end } })
	assert(s.api.start(s.player, "a"))
	assert(s.api.start(s.player, "b"))
	s.at(0)
	local before = s.counts()
	local added, removed, installed = s.eventCounts()
	assert(installed and added == 1 and removed == 0, "future jobs removed the scheduler hook")
	s.at(10)
	local after = s.counts()
	assert(after == before, "future-due jobs consumed a scanner step early")
	s.revisions.a = 2
	s.at(50)
	s.at(100)
	local statusA = s.api.getStatus("a")
	assert(statusA.state == "INVALIDATED_BY_MUTATION", "network A did not invalidate")
	assert(s.api.isActive("b"), "network B was incorrectly discarded")
	s.at(150)
	assert(s.counts() > after, "unrelated network B did not continue")
end

local function checkCompletionFailureCancellation()
	local normal = scenario({ scanner = { step = function() return true end } })
	assert(normal.api.start(normal.player, "a")); normal.at(0)
	assert(normal.api.getStatus("a").state == "COMPLETED", "normal scan did not complete")
	local _, _, merges, releases = normal.counts()
	assert(merges == 1 and releases == 1, "normal scan did not commit/release exactly once")

	local failed = scenario({ scanner = { step = function() error("zone failure") end } })
	assert(failed.api.start(failed.player, "a")); failed.at(0)
	assert(failed.api.getStatus("a").state == "FAILED", "scanner error was not terminal FAILED")
	local _, _, failedMerges, failedReleases = failed.counts()
	assert(failedMerges == 0 and failedReleases == 1, "failed scan committed or leaked its lock")

	local cancelled = scenario({ scanner = { step = function() return false end } })
	assert(cancelled.api.start(cancelled.player, "a"))
	assert(cancelled.api.cancel("a", "manual"))
	cancelled.at(0)
	local _, removed = cancelled.eventCounts()
	assert(removed == 1 and not cancelled.api.isActive("a"), "cancellation did not clean scheduler/job")
end

checkMutation()
checkFutureDueAndIsolation()
checkCompletionFailureCancellation()
print("PASS zone scan mutation scheduler contract")
