-- Authoritative floor transaction. Consumers must stop a batch
-- on reconcile=true and retain the returned receipt until reconciliation.
-- Live-animal conversion still needs runtime identity evidence before integration.
require "GS_FloorTargets"

GlobalStorageSiK.FloorMutation = {}
local Mutation = GlobalStorageSiK.FloorMutation

local function classify(item)
	if not item or not instanceof(item, "InventoryItem") or item:isEquipped() then return nil end
	if item:isHumanCorpse() or item:isAnimalCorpse() then return "corpse" end
	local generator = string.find(item:getFullType(), ".Generator", 1, true) ~= nil
		or item:hasTag(ItemTag.GENERATOR)
	if generator and item:getWorldObjectSprite() ~= nil then return "generator" end
	if instanceof(item, "AnimalInventoryItem") then return nil end
	if instanceof(item, "Radio") then return "radio" end
	-- A stored item must not still be worn/held. Vanilla's extinguish/unequip
	-- actions belong to the personal-inventory path, not a network withdrawal.
	return "ordinary"
end

local function inSource(receipt)
	local source, item = receipt.source, receipt.item
	return item:getID() == receipt.itemId and item:getContainer() == source
		and source:getItems():contains(item) and source:getItemWithID(receipt.itemId) == item
		and item:getWorldItem() == nil
end

local function onFloor(receipt)
	local item, square = receipt.item, receipt.square
	if receipt.kind == "corpse" or receipt.kind == "generator" then
		local object = receipt.createdObject
		if not object or item:getID() ~= receipt.itemId or item:getContainer() ~= nil
			or receipt.source:getItems():contains(item) or object:getSquare() ~= square then return false end
		if receipt.kind == "corpse" then return square:getStaticMovingObjects():contains(object) end
		return square:getObjects():contains(object) and square:getSpecialObjects():contains(object)
	end
	local world = item:getWorldItem()
	-- SP refreshBackpacks can assign the vanilla per-player floor projection.
	-- That cache is not storage authority: the physical wrapper remains proof.
	local container = item:getContainer()
	local complete = item:getID() == receipt.itemId
		and (container == nil or container:getType() == "floor")
		and not receipt.source:getItems():contains(item)
		and world ~= nil and world:getItem() == item and world:getSquare() == square
		and square:getWorldObjects():contains(world) and square:getObjects():contains(world)
	if not complete or receipt.kind ~= "radio" then return complete end
	local radio = receipt.createdObject
	return radio ~= nil and radio:getSquare() == square
		and radio:getModData().RadioItemID == receipt.itemId
		and square:getObjects():contains(radio) and square:getSpecialObjects():contains(radio)
end

local function checked(predicate, receipt)
	local ok, value = pcall(predicate, receipt)
	return ok and value == true
end

local function detached(receipt)
	return receipt.item:getContainer() == nil and receipt.item:getWorldItem() == nil
		and not receipt.source:getItems():contains(receipt.item)
end

local function restore(receipt)
	if checked(inSource, receipt) then return true end
	pcall(function()
		local item, source = receipt.item, receipt.source
		-- Never overwrite a foreign instance with the same ID, steal from another
		-- container or duplicate an object already represented in the world.
		local container = item:getContainer()
		if (container ~= nil and container:getType() ~= "floor") or item:getWorldItem() ~= nil
			or source:containsID(receipt.itemId) or source:getItems():contains(item) then return end
		-- Native AddItem removes a stale floor projection before restoring the
		-- source. Never treat that presentation container as another storage node.
		local restored = source:AddItem(item)
		if restored ~= item then return end
	end)
	-- AddItem can throw after inserting the exact original. Observe its actual
	-- postcondition rather than treating an exception as proof of no mutation.
	return checked(inSource, receipt)
end

local function publishWorld(receipt)
	if not (isServer and isServer()) then return true end
	local worldOk = true
	if receipt.kind == "ordinary" or receipt.kind == "radio" then
		worldOk = pcall(function() receipt.item:getWorldItem():transmitCompleteItemToClients() end)
	end
	if receipt.kind == "radio" then
		local radioOk = pcall(function() receipt.createdObject:transmitCompleteItemToClients() end)
		local dataOk = pcall(function() receipt.createdObject:transmitModData() end)
		worldOk = worldOk and radioOk and dataOk
	end
	return worldOk
end

local function publish(receipt, creationOk)
	local synced = creationOk
	if isServer and isServer() then
		local worldOk = publishWorld(receipt)
		local removeOk = pcall(function() sendRemoveItemFromContainer(receipt.source, receipt.item) end)
		synced = synced and worldOk and removeOk
	end
	receipt.state = synced and "committed" or "sync_uncertain"
	return true, not synced and "floor_sync_uncertain" or nil, not synced, receipt
end

local function createWorld(receipt, x, y, z)
	local square, item = receipt.square, receipt.item
	if receipt.kind == "corpse" then
		-- Native Lua precedent: ISDropAnimalCorpseAndThen. Its optional boolean
		-- controls doRender, NOT transmission; use the normal visible overload.
		receipt.createdObject = square:tryAddCorpseToWorld(item, x, y)
		return receipt.createdObject ~= nil
	end
	if receipt.kind == "generator" then
		-- The native constructor inserts and transmits exactly once. Retain its
		-- reference before scheduling removal of the consumed inventory item.
		receipt.createdObject = IsoGenerator.new(item, getCell(), square)
		getCell():addToProcessItemsRemove(item)
		return receipt.createdObject ~= nil
	end
	local returned = square:AddWorldInventoryItem(item, x, y, z, false)
	if receipt.kind == "radio" and returned == item then
		-- Preserve vanilla's companion IsoRadio and its device state. It is not
		-- another inventory item and must never be counted as a second transfer.
		receipt.radioStage = "prepare"
		receipt.worldObject = item:getWorldItem()
		local radio = IsoRadio.new(getCell(), square, nil)
		receipt.createdObject = radio
		local deviceData = item:getDeviceData()
		receipt.deviceData = deviceData
		if deviceData then radio:setDeviceData(deviceData) end
		radio:getModData().RadioItemID = receipt.itemId
		receipt.radioStage = "register"
		square:AddSpecialObject(radio, square:getObjects():size())
		triggerEvent("OnObjectAdded", radio)
		square:RecalcProperties()
		square:RecalcAllWithNeighbours(true)
		receipt.radioStage = "ready"
	end
	return returned == item
end

local function restorePrivateRadio(receipt)
	if receipt.radioStage ~= "prepare" then return false end
	local cleaned = pcall(function()
		local square, item, radio = receipt.square, receipt.item, receipt.createdObject
		if radio and (square:getObjects():contains(radio)
			or square:getSpecialObjects():contains(radio)) then error("radio_already_registered") end
		local world = receipt.worldObject
		if not world or item:getWorldItem() ~= world or world:getItem() ~= item
			or world:getSquare() ~= square then error("floor_identity_changed") end
		-- setDeviceData reparents the shared data even on a private IsoRadio.
		-- Reattach it before restoring the item, preserving the native data.
		if receipt.deviceData then item:setDeviceData(receipt.deviceData) end
		DesignationZoneAnimal.removeItemFromGround(world)
		square:removeWorldObject(world)
		if square:getObjects():contains(world) or square:getWorldObjects():contains(world)
			or item:getWorldItem() ~= world then error("floor_cleanup_incomplete") end
		item:setWorldItem(nil)
	end)
	return cleaned and restore(receipt)
end

function Mutation.toFloor(player, source, item, targetKey)
	if not GlobalStorageSiK.isAuthoritative() then return false, "not_authoritative", false end
	if not source or not item then return false, "not_found", false end
	local receipt = { source = source, item = item, itemId = item:getID(), targetKey = targetKey,
		direction = "network_to_floor" }
	if not checked(inSource, receipt) then return false, "not_found", false end
	local classificationOk, kind = pcall(classify, item)
	if not classificationOk or not kind then return false, "special_drop_required", false end
	receipt.kind = kind
	local room, reason, square = GlobalStorageSiK.FloorTargets.hasRoom(player, targetKey, item)
	if not room then return false, reason, false end
	receipt.square = square
	-- Compute the vanilla placement before detaching the source instance.
	local offsetOk, x, y, z = pcall(ISTransferAction.GetDropItemOffset, player, square, item)
	if not offsetOk or type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number"
		or x ~= x or y ~= y or z ~= z or math.abs(x) == math.huge
		or math.abs(y) == math.huge or math.abs(z) == math.huge then
		return false, "move_failed", false
	end
	local removed = pcall(function() source:DoRemoveItem(item) end)
	if checked(inSource, receipt) then return false, "move_failed", false end
	if not removed or not checked(detached, receipt) then
		local restored = restore(receipt)
		receipt.state = restored and "restored" or "unresolved"
		return false, restored and "move_failed" or "floor_state_uncertain", not restored, receipt
	end
	-- B42's ordinary overload performs the same initialization with false;
	-- only its final transmitCompleteItemToClients call is deferred. Verify the
	-- authoritative mutation before publishing either side of the transfer.
	local created, complete = pcall(createWorld, receipt, x, y, z)
	if checked(onFloor, receipt) then return publish(receipt, created and complete == true) end
	if kind == "radio" and restorePrivateRadio(receipt) then
		receipt.state = "restored"
		return false, "move_failed", false, receipt
	end
	if kind ~= "ordinary" then
		-- Native conversion may already have created/transmitted an entity before
		-- throwing, without returning its reference. Restoring the inventory item
		-- would risk duplication. Preserve the receipt; never guess from counts.
		receipt.state = "unresolved"
		return false, "floor_state_uncertain", true, receipt
	end
	local restored = restore(receipt)
	receipt.state = restored and "restored" or "unresolved"
	return false, restored and "move_failed" or "floor_state_uncertain", not restored, receipt
end

local function pickupSourceGone(receipt)
	local square, world, radio = receipt.square, receipt.originalWorldObject, receipt.originalRadio
	return not square:getObjects():contains(world) and not square:getWorldObjects():contains(world)
		and (not radio or (not square:getObjects():contains(radio)
			and not square:getSpecialObjects():contains(radio)))
end

local function pickupDetached(receipt)
	local item, parent = receipt.item, receipt.item:getContainer()
	return item:getID() == receipt.itemId and item:getWorldItem() == nil
		and (parent == nil or parent:getType() == "floor")
		and not receipt.source:getItems():contains(item) and pickupSourceGone(receipt)
end

local function preparePickup(receipt)
	local item, square, world = receipt.item, receipt.square, receipt.originalWorldObject
	local kind = classify(item)
	if kind ~= "ordinary" and kind ~= "radio" then return false end
	receipt.kind = kind
	if kind == "radio" then
		local objects = square:getObjects()
		for i = 0, objects:size() - 1 do
			local object = objects:get(i)
			if instanceof(object, "IsoRadio") and object:getModData().RadioItemID == receipt.itemId then
				if receipt.originalRadio then return false end
				receipt.originalRadio = object
			end
		end
		if not receipt.originalRadio then return false end
		receipt.createdObject = receipt.originalRadio
		receipt.pickupDeviceData = receipt.originalRadio:getDeviceData()
	end
	if not onFloor(receipt) or receipt.source:containsID(receipt.itemId) then return false end
	receipt.offX, receipt.offY, receipt.offZ = world:getOffX(), world:getOffY(), world:getOffZ()
	for _, value in ipairs({ receipt.offX, receipt.offY, receipt.offZ }) do
		if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then return false end
	end
	return type(receipt.offX) == "number" and type(receipt.offY) == "number"
		and type(receipt.offZ) == "number"
end

local function removePickupSource(receipt)
	local square, world, radio = receipt.square, receipt.originalWorldObject, receipt.originalRadio
	DesignationZoneAnimal.removeItemFromGround(world)
	if radio then
		-- Preserve live device state before the native remove path discards the
		-- companion. The world wrapper remains authoritative until its removal.
		if receipt.pickupDeviceData then receipt.item:setDeviceData(receipt.pickupDeviceData) end
		square:transmitRemoveItemFromSquare(radio)
		if square:getObjects():contains(radio) or square:getSpecialObjects():contains(radio) then
			error("radio_removal_incomplete")
		end
		square:RecalcProperties()
		square:RecalcAllWithNeighbours(true)
	end
	-- Removal packets identify the still-listed object by index. Never remove
	-- it locally before invoking the native transmission/removal operation.
	square:transmitRemoveItemFromSquare(world)
	square:removeWorldObject(world)
	if not pickupSourceGone(receipt) then error("floor_removal_incomplete") end
end

local function restorePickupFloor(receipt, removalOk)
	if not checked(pickupDetached, receipt) then return false end
	-- Restore the exact item and captured offsets, not a clone or a newly
	-- selected square. Native compensation creates a new world wrapper.
	local created, complete = pcall(createWorld, receipt, receipt.offX, receipt.offY, receipt.offZ)
	if not checked(onFloor, receipt) then return false end
	local synced = publishWorld(receipt)
	return removalOk and created and complete == true and synced
end

-- Internal authority helper. The caller owns network routing/permissions and
-- retains every uncertain receipt before allowing another operation on it.
function Mutation.fromFloor(player, destination, sourceKey, itemId, fullType)
	if not GlobalStorageSiK.isAuthoritative() then return false, "not_authoritative", false end
	if not destination then return false, "invalid_destination", false end
	local item, reason, world, square = GlobalStorageSiK.FloorTargets.findItemOnSquare(
		player, sourceKey, itemId, fullType)
	if not item then return false, reason, false end
	local receipt = { source = destination, item = item, itemId = itemId, square = square,
		targetKey = sourceKey, originalWorldObject = world, direction = "floor_to_network" }
	if not checked(preparePickup, receipt) then return false, "source_unavailable", false end
	local room, roomReason = GlobalStorageSiK.InventorySync.containerHasRoom(destination, item, player)
	if not room then return false, roomReason or "destination_full", false end
	local removed = pcall(removePickupSource, receipt)
	if not checked(pickupSourceGone, receipt) then
		-- A failed native removal may leave the original radio active. Undo the
		-- private DeviceData reparenting when that same companion still exists.
		pcall(function()
			local radio = receipt.originalRadio
			if radio and receipt.pickupDeviceData and square:getObjects():contains(radio)
				and square:getSpecialObjects():contains(radio) then
				radio:setDeviceData(receipt.pickupDeviceData)
			end
		end)
		receipt.state = "unresolved"
		return false, "floor_state_uncertain", true, receipt
	end
	local cleared = pcall(function()
		local currentWorld = item:getWorldItem()
		if currentWorld ~= nil and currentWorld ~= world then error("floor_identity_changed") end
		item:setWorldItem(nil)
	end)
	if not cleared then
		receipt.state = "unresolved"
		return false, "floor_state_uncertain", true, receipt
	end
	-- Native world-removal callbacks can change capacity during this same
	-- synchronous operation. Recheck immediately before the destination write.
	local roomChecked, stillRoom, finalRoomReason = pcall(
		GlobalStorageSiK.InventorySync.containerHasRoom, destination, item, player)
	if not roomChecked then stillRoom, finalRoomReason = false, "move_failed" end
	local added, returned = false, nil
	if stillRoom and checked(pickupDetached, receipt) then
		added, returned = pcall(function() return destination:AddItem(item) end)
	end
	if checked(inSource, receipt) and checked(pickupSourceGone, receipt) then
		local synced = true
		if isServer and isServer() then
			synced = pcall(function() sendAddItemToContainer(destination, item) end)
		end
		local complete = removed and added and returned == item and synced
		receipt.state = complete and "committed" or "sync_uncertain"
		return true, not complete and "floor_sync_uncertain" or nil, not complete, receipt
	end
	local restored = restorePickupFloor(receipt, removed)
	receipt.state = restored and "restored" or "unresolved"
	local failure = not stillRoom and (finalRoomReason or "destination_full") or "move_failed"
	return false, restored and failure or "floor_state_uncertain", not restored, receipt
end

-- Internal, authority-only observation. This settles physical custody only;
-- it neither declares packet delivery nor repeats a world/container mutation.
local function noResidualWorldItem(receipt)
	local worldObjects, squareObjects = receipt.square:getWorldObjects(), receipt.square:getObjects()
	if not worldObjects or not squareObjects then return false end
	for _, objects in ipairs({ worldObjects, squareObjects }) do
		for i = 0, objects:size() - 1 do
			local object = objects:get(i)
			local item = object and object.getItem and object:getItem()
			if item and (item == receipt.item or item:getID() == receipt.itemId) then return false end
		end
	end
	return true
end

function Mutation.inspectReceipt(receipt)
	if not GlobalStorageSiK.isAuthoritative() or type(receipt) ~= "table"
		or not receipt.item or not receipt.source or not receipt.square then return "unresolved" end
	local source = checked(inSource, receipt)
	local floor = checked(onFloor, receipt)
	if source and floor then return "unresolved" end
	if receipt.direction == "floor_to_network" then
		if source and checked(pickupSourceGone, receipt) then return "moved" end
		if floor then return "restored" end
	else
		if floor then return "moved" end
		-- A native conversion may have created an untracked entity before an
		-- exception. Source membership alone cannot disprove that extra entity.
		if source and receipt.kind == "ordinary" and receipt.createdObject == nil
			and checked(noResidualWorldItem, receipt) then return "restored" end
	end
	return "unresolved"
end
