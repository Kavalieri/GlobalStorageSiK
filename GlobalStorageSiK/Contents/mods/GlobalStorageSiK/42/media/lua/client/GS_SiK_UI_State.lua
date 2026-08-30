--[[
	GlobalStorageSiK - Estado semantico SiK UI
	Snapshots sin alias y almacenamiento aislado por jugador/superficie.
]]

require "GS_SiK_UI_Core"

GlobalStorageSiK.SiK_UI.State = GlobalStorageSiK.SiK_UI.State or {}

local State = GlobalStorageSiK.SiK_UI.State
local stores = {}

local function clone(value, depth)
	if type(value) ~= "table" then
		return value
	end
	depth = depth or 0
	if depth >= 6 then
		return nil
	end
	local result = {}
	for key, child in pairs(value) do
		local keyType = type(key)
		local childType = type(child)
		if (keyType == "string" or keyType == "number")
			and (childType == "nil" or childType == "boolean" or childType == "number"
				or childType == "string" or childType == "table") then
			result[key] = clone(child, depth + 1)
		end
	end
	return result
end

local function playerStore(playerNum, create)
	local key = tostring(math.max(0, math.floor(tonumber(playerNum) or 0)))
	local store = stores[key]
	if not store and create then
		store = {}
		stores[key] = store
	end
	return store
end

function State.capture(source)
	return clone(type(source) == "table" and source or {}, 0)
end

function State.restore(target, snapshot, options)
	target = type(target) == "table" and target or {}
	local values = clone(type(snapshot) == "table" and snapshot or {}, 0)
	for key, value in pairs(values) do
		target[key] = value
	end
	options = options or {}
	if tonumber(target.scrollY) then
		local maximum = tonumber(options.maxScrollY)
		target.scrollY = math.max(0, tonumber(target.scrollY) or 0)
		if maximum then
			target.scrollY = math.min(target.scrollY, math.max(0, maximum))
		end
	end
	return target
end

function State.save(surfaceKey, playerNum, source)
	assert(type(surfaceKey) == "string" and surfaceKey ~= "", "surfaceKey required")
	local store = playerStore(playerNum, true)
	store[surfaceKey] = State.capture(source)
	return State.capture(store[surfaceKey])
end

function State.load(surfaceKey, playerNum)
	local store = playerStore(playerNum, false)
	if not store or not store[surfaceKey] then
		return nil
	end
	return State.capture(store[surfaceKey])
end

function State.clear(surfaceKey, playerNum)
	local store = playerStore(playerNum, false)
	if not store then
		return
	end
	if type(surfaceKey) == "string" and surfaceKey ~= "" then
		store[surfaceKey] = nil
	end
end

function State.saveBounds(surfaceKey, playerNum, bounds)
	local current = State.load(surfaceKey, playerNum) or {}
	current.bounds = clone(bounds or {}, 0)
	return State.save(surfaceKey, playerNum, current).bounds
end

function State.loadBounds(surfaceKey, playerNum)
	local current = State.load(surfaceKey, playerNum)
	return current and clone(current.bounds, 0) or nil
end

function State.saveOffset(surfaceKey, playerNum, offset)
	local current = State.load(surfaceKey, playerNum) or {}
	current.scrollY = math.max(0, tonumber(offset) or 0)
	State.save(surfaceKey, playerNum, current)
	return current.scrollY
end

function State.loadOffset(surfaceKey, playerNum)
	local current = State.load(surfaceKey, playerNum)
	return current and math.max(0, tonumber(current.scrollY) or 0) or 0
end

GlobalStorageSiK.SiK_UI.SurfaceInventory = GlobalStorageSiK.SiK_UI.SurfaceInventory or {}

local SurfaceInventory = GlobalStorageSiK.SiK_UI.SurfaceInventory
local surfaces = {}
local surfaceIds = {}

function SurfaceInventory.register(surface)
	assert(type(surface) == "table", "surface required")
	assert(type(surface.id) == "string" and surface.id ~= "", "surface.id required")
	assert(not surfaceIds[surface.id], "duplicate surface id: " .. surface.id)
	local copy = clone(surface, 0)
	surfaces[#surfaces + 1] = copy
	surfaceIds[surface.id] = copy
	return clone(copy, 0)
end

function SurfaceInventory.get(surfaceId)
	return clone(surfaceIds[surfaceId], 0)
end

function SurfaceInventory.all()
	return clone(surfaces, 0)
end
