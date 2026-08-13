--[[
	GlobalStorageSiK - Sincronización de inventario (servidor MP)
	Autor: SiK
	Fecha: 2025-06-24
	Descripción: Elimina y añade ítems notificando al cliente en multijugador.
]]

GlobalStorageSiK.InventorySync = {}

--- Comprueba espacio en contenedor (B42: hasRoomFor(character, item)).
---@param container ItemContainer
---@param item InventoryItem
---@param character IsoPlayer|IsoGameCharacter|nil
---@return boolean
local function containerHasRoom(container, item, character)
	if not container or not item then
		return false
	end
	if container.hasRoomFor and character then
		local ok, result = pcall(function()
			return container:hasRoomFor(character, item)
		end)
		if ok then
			return result == true
		end
	end
	if container.hasRoomFor then
		local okLegacy, resultLegacy = pcall(function()
			return container:hasRoomFor(item)
		end)
		if okLegacy then
			return resultLegacy == true
		end
	end
	return true
end

--- Notifica al cliente cambios en el inventario del jugador.
---@param player IsoPlayer|nil
function GlobalStorageSiK.InventorySync.notifyPlayer(player)
	if not player or not (isServer and isServer()) then
		return
	end
	pcall(function()
		if player.syncInventory then
			player:syncInventory()
		elseif player.sendInventory then
			player:sendInventory()
		end
	end)
end

--- Elimina un ítem del contenedor con sincronización en servidor.
---@param container ItemContainer|nil
---@param item InventoryItem
---@return boolean
function GlobalStorageSiK.InventorySync.removeItem(container, item)
	if not item then
		return false
	end
	local cont = (item.getContainer and item:getContainer()) or container
	if not cont then
		return false
	end
	if isServer and isServer() then
		cont:Remove(item)
		if sendRemoveItemFromContainer then
			sendRemoveItemFromContainer(cont, item)
		end
		return true
	end
	cont:Remove(item)
	return true
end

--- Añade un ítem a un contenedor con sincronización en servidor.
---@param container ItemContainer
---@param item InventoryItem
---@param character IsoPlayer|IsoGameCharacter|nil
---@return boolean
function GlobalStorageSiK.InventorySync.addToContainer(container, item, character)
	if not container or not item then
		return false
	end
	if not containerHasRoom(container, item, character) then
		return false
	end
	container:AddItem(item)
	if isServer and isServer() and sendAddItemToContainer then
		sendAddItemToContainer(container, item)
	end
	if character and character.getInventory and character:getInventory() == container then
		GlobalStorageSiK.InventorySync.notifyPlayer(character)
	end
	return true
end

--- Mueve un ítem entre contenedores con sync MP (autoritativo en servidor).
---@param source ItemContainer
---@param dest ItemContainer
---@param item InventoryItem
---@param character IsoPlayer|IsoGameCharacter|nil
---@return boolean
function GlobalStorageSiK.InventorySync.moveBetween(source, dest, item, character)
	if not source or not dest or not item then
		return false
	end
	if not source:contains(item) then
		return false
	end
	if not containerHasRoom(dest, item, character) then
		return false
	end
	if not GlobalStorageSiK.InventorySync.removeItem(source, item) then
		return false
	end
	if not GlobalStorageSiK.InventorySync.addToContainer(dest, item, character) then
		-- Revertir si falla el destino
		GlobalStorageSiK.InventorySync.addToContainer(source, item, character)
		return false
	end
	return true
end

--- Añade un ítem al inventario del jugador (suelta en suelo si no cabe).
---@param player IsoPlayer
---@param item InventoryItem
---@return boolean
function GlobalStorageSiK.InventorySync.addToPlayer(player, item)
	if not player or not item then
		return false
	end
	local inv = player.getInventory and player:getInventory() or nil
	if not inv then
		return false
	end
	if containerHasRoom(inv, item, player) then
		return GlobalStorageSiK.InventorySync.addToContainer(inv, item, player)
	end
	local sq = player.getCurrentSquare and player:getCurrentSquare() or nil
	if sq and sq.AddWorldInventoryItem then
		sq:AddWorldInventoryItem(item, 0.5, 0.5, 0)
		GlobalStorageSiK.InventorySync.notifyPlayer(player)
		return true
	end
	return false
end
