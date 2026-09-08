require "GS_Config"

GlobalStorageSiK.ZoneBounds = {}

-- B42 IsoWorld.isValidSquare / IsoCell.getGridSquare: inclusive world levels.
-- getMaxFloors() returns 32 and does not describe the negative basement range.
local MIN_WORLD_Z, MAX_WORLD_Z = -32, 31

local function coordinate(value)
	return type(value) == "number" and value == value
		and value >= -2147483648 and value <= 2147483647
		and value == math.floor(value)
end

local function axis(first, last, legacy)
	if first == nil and last == nil then first, last = legacy, legacy end
	if not coordinate(first) or not coordinate(last) then return nil end
	return math.min(first, last), math.max(first, last)
end

--- Read legacy/current bounds without repairing or mutating persisted data.
--- Invalid or partial XY must never become a valid zone at the origin.
function GlobalStorageSiK.ZoneBounds.normalize(bounds)
	if type(bounds) ~= "table" then return nil end
	local x1, x2 = axis(bounds.x1, bounds.x2, bounds.x)
	local y1, y2 = axis(bounds.y1, bounds.y2, bounds.y)
	if x1 == nil or y1 == nil then return nil end
	local zMin = bounds.z
	if zMin == nil then zMin = bounds.zMin end
	if zMin == nil then zMin = 0 end
	local zMax = bounds.zMax
	if zMax == nil then zMax = zMin end
	if not coordinate(zMin) or not coordinate(zMax) then return nil end
	local firstZ, lastZ = math.min(zMin, zMax), math.max(zMin, zMax)
	if firstZ < MIN_WORLD_Z or lastZ > MAX_WORLD_Z then return nil end
	return x1, x2, y1, y2, firstZ, lastZ
end
