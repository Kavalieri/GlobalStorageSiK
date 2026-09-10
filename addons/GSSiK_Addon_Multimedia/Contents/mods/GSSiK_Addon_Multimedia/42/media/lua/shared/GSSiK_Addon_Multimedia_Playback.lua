-- Persistent terminal-owned playback. Only commands depend on an actor.
local API = require "GSSiK_API"
require "GSSiK_Addon_Multimedia_Register"
local Log = require "GSSiK_Addon_Multimedia_Log"
GSSiK_Addon_Multimedia = GSSiK_Addon_Multimedia or {}
local M = GSSiK_Addon_Multimedia
if isClient and isClient() then return M end
if M._runtimeLoaded then return M end
require "TimedActions/ISDeviceMediaAction"
M._runtimeLoaded = true
local Lease, Custody = API.ItemLease, API.DeviceLease
local Host = require "GSSiK_Addon_Multimedia_Host"
local Queue = require "GSSiK_Addon_Multimedia_Queue"
local ADDON, KEY, DEVICE_KEY = "Multimedia", "GSSiK_Addon_Multimedia_v2", "GSSiK_MultimediaDevice"
local active, tick, tickInstalled = {}, nil, false
local receivers = {}
local resident = setmetatable({}, { __mode = "v" })
local lastTick, cursor, revision = 0, 0, 0
local function store()
	local data = ModData.getOrCreate(KEY); data.devices = data.devices or {}; return data.devices
end
local function radioStore()
	local data = ModData.getOrCreate(KEY); data.radios = data.radios or {}; return data.radios
end
local function receiverKey(anchor)
	return "radio:" .. anchor.x .. ":" .. anchor.y .. ":" .. anchor.z
end
local function cancelForUnload(owned)
	if not owned or owned.phase == "finished" then return end
	-- Keep exact custody intact. No ejection can target an unloaded container.
	owned.phase, owned.queue, owned.afterMode = "stopping", {}, nil
	owned.stopRequested, owned.nextTick = nil, nil
end
local function legacyPending(anchor)
	local legacy = ModData.get("GSSiK_Addon_Multimedia_v1")
	if not legacy or type(legacy.devices) ~= "table" then return false end
	for _, entry in pairs(legacy.devices) do
		local a = entry.anchor
		if entry.phase ~= "radio" and a and a.x == anchor.x and a.y == anchor.y and a.z == anchor.z then return true end
	end
	return false
end
local function number(value, low, high)
	return type(value) == "number" and value >= low and value <= high and value == math.floor(value)
end
local function access(player, args)
	if type(args) ~= "table" then return false, "invalid_request" end
	local ok, reason = Lease.checkAccess(player, ADDON, args.networkId, args.anchor)
	if not ok then return false, reason end
	-- A pre-release actor-owned tape cannot be adopted by guessing its identity.
	if legacyPending(args.anchor) then return false, "recovery_required" end
	return true, "OK"
end
local function inspect(item)
	if item:isRecordedMedia() and item:getMediaType() == 1 and item:getRecordedMediaIndex() >= 0 then return tostring(item:getRecordedMediaIndex()) end
end
local function matches(item, fingerprint) return inspect(item) == fingerprint end
local function resolve(owned)
	if not owned then return nil end
	local object = Host.find(owned.networkId, owned.anchor)
	if not object or object:getModData()[DEVICE_KEY] ~= owned.key then return nil end
	return object, object:getDeviceData()
end
local function recoverable(object)
	if not Host.owns(object) then return nil end
	local key = object:getModData()[DEVICE_KEY]
	if store()[key] then return store()[key] end
	local anchor = Host.snapshot(object)
	local ok, _, record = Custody.get(ADDON, anchor.networkId, anchor)
	local data = object:getDeviceData()
	-- A lost playlist must not strand an otherwise fully identified native tape.
	-- Never infer an origin from a title/index alone or recreate missing custody.
	if not ok or not record or record.key ~= key or record.state ~= "active"
		or not data:hasMedia() or tostring(data:getMediaIndex()) ~= record.fingerprint then return nil end
	local owned = { key = key, networkId = record.networkId, anchor = record.anchor,
		queue = {}, cursor = 1, phase = "stopping" }
	store()[key] = owned
	return owned
end
-- One guard for our receiver; every ordinary vanilla TV keeps its old path.
-- A native player action cannot eject/insert around the terminal transaction.
local vanillaInvoke = ISDeviceMediaAction.invoke
function ISDeviceMediaAction:invoke()
	local parent = self.deviceData and self.deviceData:getParent()
	if Host.owns(parent) then return end
	return vanillaInvoke(self)
end
local function unwatch(key, preserveRadio)
	active[key] = nil
	receivers[key] = nil
	if not preserveRadio then radioStore()[key] = nil end
	local count = 0; for _ in pairs(active) do count = count + 1 end
	if count == 0 and tickInstalled then Events.OnTick.Remove(tick); tickInstalled = false end
end
local function watch(key)
	active[key] = true
	if not tickInstalled then Events.OnTick.Add(tick); tickInstalled = true end
end
local function watchRadio(object)
	local snapshot = Host.snapshot(object)
	if not snapshot or snapshot.mode ~= "radio" or not snapshot.powered then return end
	local key = receiverKey(snapshot)
	receivers[key] = { networkId = snapshot.networkId, anchor = { x = snapshot.x, y = snapshot.y, z = snapshot.z } }
	radioStore()[key] = { networkId = snapshot.networkId, anchor = { x = snapshot.x, y = snapshot.y, z = snapshot.z } }
	watch(key)
end
local function projected(player, args)
	revision = revision + 1
	local result = { ok = true, stateRevision = revision, nextSequence = 1, playerOnlineId = player:getOnlineID() }
	result.requestId = type(args) == "table" and number(args.requestId, 1, 2147483646) and args.requestId or nil
	local draft = Queue.status(player, getTimestampMs())
	if draft then
		result.queueToken, result.nextOffset = draft.queueToken, draft.nextOffset
		result.queuedCount, result.queueTotal = draft.queuedCount, draft.queueTotal
	end
	if access(player, args) then
		result.networkId = args.networkId
		local _, _, record = Custody.get(ADDON, args.networkId, args.anchor)
		local object = Host.find(args.networkId, args.anchor)
		if object then result.device = Host.snapshot(object) end
		if record then
			local owned = store()[record.key]
			result.nextSequence, result.sequence = record.sequence + 1, record.sequence
			result.state = record.state == "closed" and "settled" or record.state
			result.itemId, result.contextKey = record.itemId, record.key
			result.reason = owned and owned.reason
			result.remaining = owned and math.max(0, #owned.queue - (owned.cursor or 1) + 1) or 0
			if owned and owned.phase == "parked" then result.state = "parked" end
		end
	end
	return result
end
local function reply(player, args, ok, reason)
	local result = projected(player, args)
	if ok ~= nil then
		result.ok = ok
		if not ok or reason ~= "OK" or not result.reason then result.reason = reason end
	end
	if isServer and isServer() then sendServerCommand(player, "GSSiK_Multimedia", "state", result)
	elseif M.onState then M.onState(player, result) end
	return result
end
function M.state(player, args)
	local ok, reason = access(player, args); return reply(player, args, ok, reason)
end
function M.catalog(player, args)
	if type(args) ~= "table" then return false, "invalid_request" end
	local ok, reason, page = Lease.listCandidates(player, { addonId = ADDON, networkId = args.networkId,
		anchor = args.anchor, node = args.node, offset = args.offset }, inspect)
	local result = projected(player, args); result.ok, result.reason, result.page = ok, reason, page
	if isServer and isServer() then sendServerCommand(player, "GSSiK_Multimedia", "catalog", result)
	elseif M.onCatalog then M.onCatalog(player, result) end
	return ok, reason
end
local function settle(owned, data)
	if data:isPlayingMedia() then
		-- Repeated Stop resets the SP fade counter: send it once, then wait.
		if not owned.stopRequested then data:StopPlayMedia(); owned.stopRequested = true end
		return false, "stopping"
	end
	local _, _, record = Custody.get(ADDON, owned.networkId, owned.anchor)
	if not record then return false, "unknown_loan" end
	if record.state == "idle" then return true, "OK" end
	if record.state ~= "active" then return false, "loan_unresolved" end
	if not data:hasMedia() or tostring(data:getMediaIndex()) ~= record.fingerprint then return false, "media_unavailable" end
	local ok, reason, result = Custody.release(owned.key, function(container) data:removeMediaItem(container) end,
		function() return not data:hasMedia() and not data:isPlayingMedia() end, matches)
	if ok then
		owned.stopRequested = nil
		local message = { networkId = owned.networkId, originalItemId = result.originalItemId, returnedItemId = result.returnedItemId }
		if isServer and isServer() then sendServerCommand("GSSiK_Multimedia", "returned", message)
		elseif M.onReturn then M.onReturn(message) end
	end
	return ok, reason
end
local function startOne(owned, entry, data)
	if not data:getIsTurnedOn() or not data:canBePoweredHere() then return false, "no_power" end
	if data:hasMedia() or data:isPlayingMedia() then return false, "device_busy" end
	local ok, reason = Custody.consume(owned.key, entry, inspect, function(item) data:addMediaItem(item) end,
		function(fingerprint) return data:hasMedia() and tostring(data:getMediaIndex()) == fingerprint end)
	if not ok then return false, reason end
	owned.phase, owned.stopRequested, owned.reason = "playing", nil, nil
	local started = pcall(function() data:StartPlayMedia() end)
	if not started or not data:isPlayingMedia() then return false, "playback_unavailable" end
	Log.debug("Playback", "start terminal=" .. owned.key .. " item=" .. tostring(entry.itemId))
	return true, "OK"
end
local function finish(owned, object)
	if not Custody.close(owned.key) then return false end
	local afterMode = owned.afterMode
	owned.queue, owned.phase, owned.afterMode = {}, "finished", nil
	if afterMode then Host.setMode(object, afterMode) end
	object:getDeviceData():setIsTurnedOn(afterMode == "radio")
	unwatch(owned.key); Host.publish(object); Host.retireEmpty(object)
	watchRadio(object)
	return true
end
local function expected(args)
	local ok, _, record = Custody.get(ADDON, args.networkId, args.anchor)
	return ok and (not record or record.state == "closed") and args.sequence == (record and record.sequence + 1 or 1)
end
local function currentSequence(args)
	local ok, _, record = Custody.get(ADDON, args.networkId, args.anchor)
	return ok and args.expectedSequence == (record and record.sequence or 0)
end
function M.prepare(player, args)
	local allowed, reason = access(player, args)
	if not allowed then return reply(player, args, false, reason) end
	if not expected(args) then return reply(player, args, false, "device_busy") end
	local ok, why = Queue.prepare(player, args, getTimestampMs()); return reply(player, args, ok, why)
end
function M.append(player, args)
	local allowed, reason = access(player, args)
	if not allowed then Queue.cancel(player); return reply(player, args, false, reason) end
	local ok, why = Queue.append(player, args, getTimestampMs()); return reply(player, args, ok, why)
end
function M.start(player, args)
	local allowed, reason = access(player, args)
	if not allowed then return reply(player, args, false, reason) end
	if not expected(args) then return reply(player, args, false, "device_busy") end
	local object, hostReason = Host.ensure(player, args.networkId, args.anchor)
	if not object then return reply(player, args, false, hostReason) end
	local data = object:getDeviceData()
	if data:hasMedia() or data:isPlayingMedia() then return reply(player, args, false, "device_busy") end
	if not data:canBePoweredHere() then return reply(player, args, false, "no_power") end
	local queued, why, queue = Queue.take(player, args, getTimestampMs())
	if not queued then return reply(player, args, false, why) end
	local opened, openReason, record = Custody.open(player, { addonId = ADDON, networkId = args.networkId, anchor = args.anchor, sequence = args.sequence })
	if not opened then return reply(player, args, false, openReason) end
	local owned = { key = record.key, networkId = record.networkId, anchor = record.anchor, queue = queue, cursor = 2, phase = "starting" }
	store()[owned.key] = owned; object:getModData()[DEVICE_KEY] = owned.key
	resident[receiverKey(owned.anchor)] = object
	Host.setMode(object, "vhs"); data:setIsTurnedOn(true)
	local ok, startReason = startOne(owned, queue[1], data)
	if not ok then owned.phase, owned.reason, owned.queue = "stopping", startReason, {} end
	watch(owned.key); Host.publish(object)
	return reply(player, args, ok, startReason)
end
function M.stop(player, args)
	Queue.cancel(player)
	local allowed, reason = access(player, args)
	if not allowed then return reply(player, args, false, reason) end
	if not currentSequence(args) then return reply(player, args, false, "stale_request") end
	local object = Host.find(args.networkId, args.anchor)
	if object then
		local owned = store()[object:getModData()[DEVICE_KEY]]
		local _, _, record = Custody.get(ADDON, args.networkId, args.anchor)
		if owned and record and record.state ~= "closed" then
			owned.phase, owned.queue, owned.afterMode = "stopping", {}, nil; watch(owned.key)
		elseif not object:getDeviceData():hasMedia() then
			object:getDeviceData():setIsTurnedOn(false); Host.publish(object); Host.retireEmpty(object)
		end
	end
	return reply(player, args, true, "OK")
end
function M.control(player, args)
	local allowed, reason = access(player, args)
	if not allowed then return reply(player, args, false, reason) end
	if not currentSequence(args) then return reply(player, args, false, "stale_request") end
	local action, value = args.action, args.value
	if (action == "mode" and value ~= "vhs" and value ~= "radio")
		or (action == "volume" and (type(value) ~= "number" or value ~= value or value < 0 or value > 1))
		or (action == "channel" and not number(value, 200, 1000000))
		or (action == "power" and type(value) ~= "boolean")
		or (action ~= "mode" and action ~= "volume" and action ~= "channel" and action ~= "power") then return reply(player, args, false, "invalid_control") end
	local object, hostReason = Host.ensure(player, args.networkId, args.anchor)
	if not object then return reply(player, args, false, hostReason) end
	local data = object:getDeviceData()
	resident[receiverKey(args.anchor)] = object
	if (action == "mode" or (action == "power" and not value)) and (data:hasMedia() or data:isPlayingMedia()) then
		local owned = store()[object:getModData()[DEVICE_KEY]]
		if not owned then return reply(player, args, false, "recovery_required") end
		owned.phase, owned.queue, owned.afterMode = "stopping", {}, action == "mode" and value or nil
		watch(owned.key); return reply(player, args, true, "stopping")
	elseif action == "mode" then Host.setMode(object, value)
	elseif action == "volume" then Host.setVolume(object, value)
	elseif action == "channel" then
		if data:getIsTelevision() then return reply(player, args, false, "radio_required") end
		if value < data:getMinChannelRange() or value > data:getMaxChannelRange() then return reply(player, args, false, "invalid_channel") end
		data:setChannel(value)
	elseif action == "power" then data:setIsTurnedOn(value) end
	if (action == "mode" and value == "radio") or action == "channel" then data:setIsTurnedOn(true) end
	-- Radio is a world receiver; no actor watcher switches it off on departure.
	Host.publish(object); watchRadio(object); return reply(player, args, true, "OK")
end
function M.recover(player, args)
	local allowed, reason = access(player, args)
	if not allowed then return reply(player, args, false, reason) end
	if not currentSequence(args) then return reply(player, args, false, "stale_request") end
	local object = Host.find(args.networkId, args.anchor)
	local owned = object and recoverable(object)
	if not owned then return reply(player, args, false, "recovery_required") end
	owned.phase, owned.queue, owned.afterMode, owned.reason = "stopping", {}, nil, nil
	watch(owned.key); return reply(player, args, true, "stopping")
end
local function updateDevice(key, now)
	local receiver = receivers[key]
	if receiver then
		if now < (receiver.nextTick or 0) then return end
		receiver.nextTick = now + 1000
		local object = Host.find(receiver.networkId, receiver.anchor)
		if not object then resident[key] = nil; unwatch(key, true); return end
		local data = object:getDeviceData()
		if data:getIsTelevision() or not data:getIsTurnedOn() then unwatch(key); return end
		if not Custody.validate(ADDON, receiver.networkId, receiver.anchor) then
			data:setIsTurnedOn(false); unwatch(key); Host.publish(object); Host.retireEmpty(object)
		end
		return
	end
	local owned = store()[key]
	local object, data = resolve(owned)
	if not object then
		cancelForUnload(owned)
		if owned then resident[receiverKey(owned.anchor)] = nil end
		unwatch(key); return
	end
	if now < (owned.nextTick or 0) then return end
	owned.nextTick = now + 1000
	local allowed, reason = Custody.check(key)
	if not allowed or not data:getIsTurnedOn() or not data:canBePoweredHere() then
		owned.phase, owned.queue, owned.reason = "stopping", {}, not allowed and reason or "no_power"
	end
	if owned.phase == "playing" and data:isPlayingMedia() then return end
	local ok, why = settle(owned, data)
	if not ok then
		if why ~= "stopping" then owned.phase, owned.reason = "parked", why; unwatch(key); Host.publish(object) end
		return
	end
	local entry = owned.phase == "playing" and owned.queue[owned.cursor]
	if entry then
		local started, startReason = startOne(owned, entry, data)
		if started then owned.cursor = owned.cursor + 1 else owned.phase, owned.queue, owned.reason = "stopping", {}, startReason end
		Host.publish(object)
	else finish(owned, object) end
end
tick = function()
	local now = getTimestampMs()
	if now - lastTick < 250 then return end
	lastTick = now
	local keys = {}; for key in pairs(active) do keys[#keys + 1] = key end
	table.sort(keys)
	-- Eight queue transitions per slice; native playback updates independently.
	for _ = 1, math.min(8, #keys) do cursor = cursor % #keys + 1; updateDevice(keys[cursor], now) end
end
local function resume(object)
	if not Host.owns(object) then return end
	local snapshot = Host.snapshot(object)
	local key = receiverKey(snapshot)
	if resident[key] == object then return end
	resident[key] = object
	-- Loading a world/area is a fresh receiver lifetime, not a Play command.
	-- Stop immediately and reconcile the inserted native tape before any new job.
	unwatch(key)
	local data = object:getDeviceData()
	data:setIsTurnedOn(false)
	local owned = recoverable(object)
	if owned and owned.phase ~= "finished" then
		cancelForUnload(owned)
		if data:isPlayingMedia() then data:StopPlayMedia(); owned.stopRequested = true end
		watch(owned.key)
	end
	Host.publish(object); Host.retireEmpty(object)
end
local function loadedSquare(square)
	if not square or not square.getObjects then return end
	local objects = square:getObjects(); if objects:size() > 1024 then return end
	for i = objects:size() - 1, 0, -1 do resume(objects:get(i)) end
end
local function loadedGame()
	for _, owned in pairs(store()) do
		local object = resolve(owned)
		if object then resume(object) else cancelForUnload(owned) end
	end
	local radios = {}; for _, radio in pairs(radioStore()) do radios[#radios + 1] = radio end
	for i = 1, #radios do
		local radio = radios[i]
		local object = Host.find(radio.networkId, radio.anchor)
		if object then resume(object) end
	end
end
local commands = setmetatable({}, { __mode = "k" })
local function onCommand(module, command, player, args)
	if module ~= "GSSiK_Multimedia" or not player then return end
	local handlers = { start = M.start, prepare = M.prepare, append = M.append, control = M.control,
		stop = M.stop, recover = M.recover, state = M.state, catalog = M.catalog }
	if not handlers[command] then return end
	local now = getTimestampMs(); commands[player] = commands[player] or {}
	local previous = commands[player][command]; if previous and now - previous < 100 then return end
	commands[player][command] = now; handlers[command](player, args)
end
Events.OnClientCommand.Add(onCommand)
if Events.LoadGridsquare then Events.LoadGridsquare.Add(loadedSquare) end
if Events.OnGameStart then Events.OnGameStart.Add(loadedGame) end
return M
