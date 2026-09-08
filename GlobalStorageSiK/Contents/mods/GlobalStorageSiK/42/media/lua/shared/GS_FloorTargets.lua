-- Physical floor references. No synthetic ItemContainer, retained Java square,
-- mutation, listener or fallback to another destination.
require "TimedActions/ISTransferAction"

GlobalStorageSiK.FloorTargets = {}
local Floor = GlobalStorageSiK.FloorTargets
local FLOOR_CAPACITY = 50 -- ItemContainer("floor"): traits do not alter capacity.

local function integer(value)
	return type(value) == "number" and value == value
		and value > -2147483648 and value < 2147483647 and value == math.floor(value)
end

function Floor.isKey(key)
	return type(key) == "string" and string.sub(key, 1, 6) == "floor:"
end

function Floor.squareKey(square)
	if not square then return nil end
	local x, y, z = square:getX(), square:getY(), square:getZ()
	if not integer(x) or not integer(y) or not integer(z) then return nil end
	return "floor:" .. tostring(x) .. ":" .. tostring(y) .. ":" .. tostring(z)
end

-- Mirrors the vanilla floor pane's 3x3 and canReachTo check. Check loot
-- permissions in the authoritative process too, not just its client projection.
function Floor.canAccessSquare(player, square)
	local current = player and player:getCurrentSquare()
	if not current or not square or (player.isDead and player:isDead()) then return false end
	if square:getZ() ~= current:getZ()
		or math.abs(square:getX() - current:getX()) > 1
		or math.abs(square:getY() - current:getY()) > 1 then return false end
	if square ~= current and not current:canReachTo(square) then return false end
	if SafeHouse and SafeHouse.isSafehouseAllowLoot
		and not SafeHouse.isSafehouseAllowLoot(square, player) then return false end
	return true
end

function Floor.resolveSquare(player, key, forSource)
	if not Floor.isKey(key) or #key > 48 then return nil, "invalid_destination" end
	local x, y, z = string.match(key, "^floor:(%-?%d+):(%-?%d+):(%-?%d+)$")
	x, y, z = tonumber(x), tonumber(y), tonumber(z)
	if not integer(x) or not integer(y) or not integer(z) then return nil, "invalid_destination" end
	local cell = getCell and getCell()
	local square = cell and cell:getGridSquare(x, y, z)
	if not Floor.canAccessSquare(player, square) then return nil, "target_unavailable" end
	if not forSource and not ISTransferAction:canDropOnFloor(square, player) then
		return nil, "target_unavailable"
	end
	return square
end

function Floor.captureCurrent(player)
	local square = player and player:getCurrentSquare()
	local key = Floor.squareKey(square)
	if key and Floor.resolveSquare(player, key) then return key end
	return nil
end

function Floor.hasRoom(player, key, item)
	local square, reason = Floor.resolveSquare(player, key)
	if not square then return false, reason end
	if not item or not item:CanBeDroppedOnFloor() then return false, "invalid_destination" end
	local weight = item:getUnequippedWeight()
	local total = square:getTotalWeightOfItemsOnFloor()
	if weight ~= weight or total ~= total or weight < 0 or total < 0
		or weight == math.huge or total == math.huge then return false, "invalid_destination" end
	if total >= FLOOR_CAPACITY then return false, "destination_full" end
	-- Same vanilla exception: one indivisible heavy bag can exceed the limit
	-- while the square is below capacity. Never split or clone that instance.
	if ItemContainer.floatingPointCorrection(total) + weight <= FLOOR_CAPACITY
		or weight >= FLOOR_CAPACITY then return true, nil, square end
	return false, "destination_full"
end

function Floor.findItemOnSquare(player, key, itemId, fullType)
	-- Physical identities do not share the coordinate range.
	if type(itemId) ~= "number" or itemId ~= itemId or itemId < 0
		or itemId == math.huge or itemId ~= math.floor(itemId)
		or type(fullType) ~= "string" or fullType == "" or #fullType > 160 then
		return nil, "invalid_request"
	end
	local square, reason = Floor.resolveSquare(player, key, true)
	if not square then return nil, reason end
	local objects = square:getWorldObjects()
	for i = 0, objects:size() - 1 do
		local world = objects:get(i)
		local item = world and world:getItem()
		if item and item:getID() == itemId and item:getFullType() == fullType
			and item:getWorldItem() == world and world:getSquare() == square then
			return item, nil, world, square
		end
	end
	return nil, "not_found"
end
