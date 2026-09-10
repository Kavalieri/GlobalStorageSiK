-- Internal native receiver owned by the installed peripheral. The PC itself
-- is never replaced. Creation is demand-driven and requires Core authority.
-- No update loop: AddSpecialObject calls IsoWaveSignal.addToWorld,
-- which registers the vanilla radio receiver and static updater exactly once.
local API = require "GSSiK_API"
local Host = {}
local TAG = "GSSiK_MultimediaHost"
local MAX_OBJECTS = 1024
local applied = setmetatable({}, { __mode = "k" })
local pending, pendingOrder = {}, {}

-- The receiver is an implementation detail of the installed peripheral. Its
-- power follows the terminal session, so it must not inherit the extra grid
-- requirement of a floor television. A zero drain keeps that contract stable
-- across long queues without inventing a player-visible battery resource.
local function configureTerminalPower(data)
	data:setIsBatteryPowered(true)
	data:setHasBattery(true)
	data:setPower(1)
	data:setUseDelta(0)
end

local function authoritative()
	return not (isClient and isClient())
end

local function anchorValid(anchor)
	if type(anchor) ~= "table" then return false end
	for _, key in ipairs({ "x", "y", "z" }) do
		local value = anchor[key]
		if type(value) ~= "number" or value ~= math.floor(value) then return false end
		if key == "z" then
			if value < -32 or value > 32 then return false end
		elseif value < 0 or value > 1000000 then return false end
	end
	return true
end

function Host.owns(object)
	if not object or not object.getModData or not object.getDeviceData then return false end
	local tag = object:getModData()[TAG]
	return type(tag) == "table" and tag.version == 1
end

function Host.find(networkId, anchor)
	if type(networkId) ~= "string" or #networkId == 0 or #networkId > 160
		or not anchorValid(anchor) then return nil, "invalid_request" end
	local square = getCell():getGridSquare(anchor.x, anchor.y, anchor.z)
	if not square then return nil, "square_unavailable" end
	local objects, found = square:getObjects(), nil
	if objects:size() > MAX_OBJECTS then return nil, "square_limit" end
	for index = 0, objects:size() - 1 do
		local object = objects:get(index)
		local tag = object.getModData and object:getModData()[TAG]
		if tag ~= nil then
			-- Coordinates are the terminal identity. A changed network or damaged
			-- marker must not make an old receiver invisible and mint another one.
			if not Host.owns(object) or tag.x ~= anchor.x or tag.y ~= anchor.y or tag.z ~= anchor.z then
				return nil, "host_conflict"
			end
			if found then return nil, "host_conflict" end
			found = object
		end
	end
	if found and found:getModData()[TAG].networkId ~= networkId then return nil, "host_network_changed", square, found end
	return found, found and "OK" or "host_absent", square
end

function Host.ensure(player, networkId, anchor)
	if not authoritative() then return nil, "authority_required" end
	local allowed, reason = API.ItemLease.checkAccess(player, "Multimedia", networkId, anchor)
	if not allowed then return nil, reason end
	local existing, foundReason, square, previous = Host.find(networkId, anchor)
	if foundReason == "host_network_changed" and previous then
		local data = previous:getDeviceData()
		if data:hasMedia() or data:isPlayingMedia() then return nil, "media_pending" end
		-- The actual terminal at this anchor was authorized above. Reuse its
		-- empty peripheral after a network change; never create a second receiver.
		previous:getModData()[TAG].networkId = networkId
		Host.publish(previous)
		existing = previous
	end
	if existing then
		if existing:getModData()[TAG].phase ~= "ready" then return nil, "host_state_uncertain" end
		configureTerminalPower(existing:getDeviceData())
		return existing, "OK"
	end
	if foundReason ~= "host_absent" then return nil, foundReason end
	local object = IsoRadio.new(getCell(), square, nil)
	local data = object:getDeviceData()
	data:setDeviceName("GS Multimedia")
	data:setIsTelevision(true)
	data:setMediaType(1)
	configureTerminalPower(data)
	data:setDeviceVolumeRaw(0.3)
	data:setMinChannelRange(200)
	data:setMaxChannelRange(1000000)
	data:setChannelRaw(98400)
	object:getModData()[TAG] = { version = 1, mode = "vhs", phase = "registering", networkId = networkId,
		x = anchor.x, y = anchor.y, z = anchor.z }
	-- Same companion lifecycle as the native floor-radio path. Never call
	-- addToWorld manually too: it is dispatched by AddSpecialObject.
	local registered = pcall(function()
		square:AddSpecialObject(object, square:getObjects():size())
		triggerEvent("OnObjectAdded", object)
	end)
	if not registered or not square:getObjects():contains(object) or not square:getSpecialObjects():contains(object) then
		-- A thrown callback can follow successful insertion. Keep the marker
		-- and refuse retries as a new receiver; no blind compensating deletion.
		return nil, "host_registration_uncertain"
	end
	local tag = object:getModData()[TAG]
	tag.phase = "publishing"
	if isServer and isServer() then
		local published = pcall(function()
			object:transmitCompleteItemToClients()
			object:transmitModData()
		end)
		if not published then return nil, "host_sync_uncertain" end
	end
	tag.phase = "ready"
	Host.publish(object)
	return object, "OK"
end

function Host.snapshot(object)
	if not Host.owns(object) then return nil end
	local tag, data = object:getModData()[TAG], object:getDeviceData()
	return { x = tag.x, y = tag.y, z = tag.z, networkId = tag.networkId,
		mode = data:getIsTelevision() and "vhs" or "radio", volume = data:getDeviceVolume(),
		channel = data:getChannel(), powered = data:getIsTurnedOn(), playing = data:isPlayingMedia(),
		mediaPending = data:hasMedia(),
		availablePower = data:canBePoweredHere(), revision = tag.revision or 0 }
end

function Host.publish(object)
	if not authoritative() or not Host.owns(object) then return false end
	local tag = object:getModData()[TAG]
	tag.revision = (tag.revision or 0) + 1
	tag.projection = Host.snapshot(object)
	if isServer and isServer() then
		-- DeviceData setters only send from a native client. Authority therefore
		-- publishes an absolute projection; clients apply raw setters without echo.
		object:transmitModData()
		sendServerCommand("GSSiK_Multimedia", "device", tag.projection)
	end
	return true
end

function Host.apply(snapshot)
	if authoritative() or type(snapshot) ~= "table" or not anchorValid(snapshot)
		or type(snapshot.revision) ~= "number" or snapshot.revision < 0
		or snapshot.revision ~= math.floor(snapshot.revision)
		or (snapshot.mode ~= "vhs" and snapshot.mode ~= "radio")
		or type(snapshot.powered) ~= "boolean" or type(snapshot.volume) ~= "number"
		or snapshot.volume ~= snapshot.volume or snapshot.volume < 0 or snapshot.volume > 1
		or type(snapshot.channel) ~= "number" or snapshot.channel < 200 or snapshot.channel > 1000000
		or snapshot.channel ~= math.floor(snapshot.channel) then return false end
	if type(snapshot.networkId) ~= "string" or #snapshot.networkId == 0 or #snapshot.networkId > 160 then return false end
	local key = snapshot.x .. ":" .. snapshot.y .. ":" .. snapshot.z
	local object = Host.find(snapshot.networkId, snapshot)
	if not object then
		-- Retain only the latest projection for a bounded set of unloaded hosts.
		-- Loading the square supplies the durable projection if this cache evicts it.
		if not pending[key] then
			if #pendingOrder >= 128 then pending[table.remove(pendingOrder, 1)] = nil end
			pendingOrder[#pendingOrder + 1] = key
		end
		if not pending[key] or pending[key].networkId ~= snapshot.networkId or pending[key].revision < snapshot.revision then pending[key] = snapshot end
		return false
	end
	if snapshot.revision <= (applied[object] or -1) then return false end
	local data = object:getDeviceData()
	configureTerminalPower(data)
	data:setIsTelevision(snapshot.mode == "vhs")
	data:setChannelRaw(snapshot.channel)
	data:setDeviceVolumeRaw(snapshot.volume)
	data:setTurnedOnRaw(snapshot.powered)
	applied[object] = snapshot.revision
	return true
end

-- These operations accept only the trusted host returned by find/ensure.
-- Product commands must revalidate actor/network/installation before calling.
function Host.setMode(object, mode)
	if not authoritative() then return false, "authority_required" end
	if not Host.owns(object) or (mode ~= "vhs" and mode ~= "radio") then return false, "invalid_request" end
	local data = object:getDeviceData()
	if data:hasMedia() or data:isPlayingMedia() then return false, "media_pending" end
	data:setIsTelevision(mode == "vhs")
	-- Media type remains VHS; radio mode receives broadcast without a tape.
	-- Complete-item publication belongs ONLY to creation. Existing clients
	-- receive the mode through the addon's authoritative state projection;
	-- publishing the object again could create a second world representation.
	object:getModData()[TAG].mode = mode
	return true, "OK"
end

function Host.loaded(object)
	if not Host.owns(object) then return end
	local tag = object:getModData()[TAG]
	if authoritative() then
		if Host.retireEmpty(object) then return end
		-- Loading a persisted IsoRadio has completed the native registration.
		-- It is safe to reconcile its marker without adding/publishing it again.
		configureTerminalPower(object:getDeviceData())
		tag.phase = "ready"
	else
		if tag.projection then Host.apply(tag.projection) end
		local cached = pending[tag.x .. ":" .. tag.y .. ":" .. tag.z]
		if cached then Host.apply(cached) end
	end
end

local function loadedSquare(square)
	if not square or not square.getObjects then return end
	local objects = square:getObjects()
	if objects:size() > MAX_OBJECTS then return end
	for i = objects:size() - 1, 0, -1 do Host.loaded(objects:get(i)) end
end
-- Event-driven streaming reconciliation; no global receiver scan or timer.
if Events and Events.LoadGridsquare then Events.LoadGridsquare.Add(loadedSquare) end

function Host.setVolume(object, volume)
	if not authoritative() then return false, "authority_required" end
	if not Host.owns(object) or type(volume) ~= "number" or volume < 0 or volume > 1
		or volume ~= volume then return false, "invalid_request" end
	object:getDeviceData():setDeviceVolume(volume)
	return true, "OK"
end

function Host.removeEmpty(object)
	if not authoritative() then return false, "authority_required" end
	if not Host.owns(object) then return false, "invalid_host" end
	local data = object:getDeviceData()
	if data:hasMedia() or data:isPlayingMedia() then return false, "media_pending" end
	local square = object:getSquare()
	if not square then return false, "square_unavailable" end
	-- This path invokes removeFromWorld/UnRegisterDevice and emitter cleanup.
	-- Removal packets need the current index; never remove locally beforehand.
	local removed = pcall(function() square:transmitRemoveItemFromSquare(object) end)
	if square:getObjects():contains(object) or square:getSpecialObjects():contains(object) then
		return false, "host_removal_uncertain"
	end
	if not removed then return false, "host_removal_sync_uncertain" end
	return true, "OK"
end

function Host.retireEmpty(object)
	if not authoritative() or not Host.owns(object) then return false end
	local tag = object:getModData()[TAG]
	local ok, _, installed = API.Installation.isInstalled(tag.networkId, tag, "Multimedia")
	if ok and not installed then return Host.removeEmpty(object) end
	return false
end

return Host
