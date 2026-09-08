-- World taxonomy synchronizes at connection and on explicit authoritative changes.
require "GS_NativeWorldProjection"
require "GS_NetClient"
GlobalStorageSiK.NativeWorldSync = {}
local Sync = GlobalStorageSiK.NativeWorldSync
local World = GlobalStorageSiK.NativeWorldOverrides
local Projection = GlobalStorageSiK.NativeWorldProjection
local sequence, lastError = 0, nil
local retryState

local function now()
	return getTimestampMs and getTimestampMs() or nil
end

local function stopRetry()
	if retryState and Events.OnTick and Events.OnTick.Remove then
		Events.OnTick.Remove(Sync.retryPending)
	end
	retryState = nil
end

-- Temporary only: one requested read, at most three retries, then detach.
-- No terminal access/range polling is changed by taxonomy synchronization.
function Sync.retryPending()
	local state = retryState
	if not state then return end
	state.ticks = state.ticks + 1
	local timestamp = now()
	if type(timestamp) ~= "number" or timestamp ~= timestamp or timestamp < state.startedAt
		or timestamp >= state.deadline or state.ticks >= 3600 then
		Projection.cancel()
		lastError = lastError or "projection_timeout"
		stopRetry()
		return
	end
	if timestamp < state.nextAt or Projection.isPending(timestamp) then return end
	if state.remaining == 0 then
		lastError = lastError or "projection_timeout"
		stopRetry()
		return
	end
	state.remaining = state.remaining - 1
	state.nextAt = timestamp + 1100
	Sync.request(true, nil, true)
end

local function armRetry(timestamp)
	if retryState or not Events.OnTick or not Events.OnTick.Add or not Events.OnTick.Remove then return end
	if type(timestamp) ~= "number" or timestamp ~= timestamp or timestamp < 0 or timestamp >= math.huge then return end
	retryState = { startedAt = timestamp, deadline = timestamp + 35000,
		nextAt = timestamp + 1100, remaining = 3, ticks = 0 }
	Events.OnTick.Add(Sync.retryPending)
end

function Sync.reset()
	stopRetry()
	Projection.clear()
	lastError = nil
	-- Keep sequence monotonic: a late page from the previous world cannot match.
end

function Sync.request(force, player, retrying)
	if GlobalStorageSiK.isAuthoritative() then return true end
	local timestamp = now()
	if not force and World.getRevision() ~= nil then return true end
	if Projection.isPending(timestamp) then return true end
	if sequence == 2147483647 then lastError = "sequence_exhausted"; return false end
	sequence = sequence + 1
	if not Projection.begin(sequence, timestamp) then lastError = "invalid_time"; return false end
	local requestId = sequence
	lastError = nil
	if not retrying then armRetry(timestamp) end
	if retryState then retryState.nextAt = timestamp + 1100 end
	if not GlobalStorageSiK.NetClient.sendCommand("getTaxonomyOverrides", { requestId = requestId }, player) then
		Projection.cancel(requestId)
		lastError = "send_failed"
		return false
	end
	return true
end

function Sync.getStatus()
	return { revision = World.getRevision(), pending = Projection.isPending(now()),
		retrying = retryState ~= nil, reason = lastError }
end

function Sync.onCommand(command, args)
	if command == "identityHelloAck" then
		Sync.request(false)
		return false -- Existing identity handler still owns its ACK.
	end
	if command == "taxonomyOverridePage" then
		local ok, reason = Projection.accept(args, now())
		if not ok and reason ~= "unrequested" and reason ~= "stale_projection" then lastError = reason end
		if reason == "complete" or reason == "stale_projection" then lastError = nil; stopRetry() end
		return true
	end
	if command == "taxonomyOverrideError" then
		if type(args) == "table" and args.requestId == sequence then
			Projection.cancel(args.requestId)
			lastError = type(args.reason) == "string" and args.reason:sub(1, 80) or "projection_failed"
		end
		return true
	end
	if command == "taxonomyOverrideChanged" then
		if GlobalStorageSiK.isAuthoritative() then return true end
		if type(args) ~= "table" then return true end
		local ok, reason = World.acceptDelta(args.revision, args.fullType, args.nativePath)
		if not ok and reason ~= "stale_projection" then
			lastError = reason
			if reason == "projection_required" or reason == "projection_conflict" then
				Projection.cancel()
				Sync.request(true)
			end
		end
		return true
	end
	return false
end

local function onCreatePlayer(playerNum)
	if playerNum == nil or playerNum == 0 then Sync.reset() end
end

if Events.OnCreatePlayer then Events.OnCreatePlayer.Add(onCreatePlayer) end
if Events.OnGameStart then Events.OnGameStart.Add(function() Sync.request(false) end) end
if Events.OnDisconnect then Events.OnDisconnect.Add(Sync.reset) end

return Sync
