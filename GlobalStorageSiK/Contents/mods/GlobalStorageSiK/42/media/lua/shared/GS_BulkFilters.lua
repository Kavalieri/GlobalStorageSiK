--[[
	GlobalStorageSiK - Filtros de depósito masivo
	Autor: SiK
	Fecha: 2025-06-23
	Descripción: Decide qué ítems pueden moverse a la red en operaciones bulk.
]]

require "GS_Config"
require "GS_Sandbox"

GlobalStorageSiK.BulkFilters = {}

--- Tipos de ámbito para operaciones bulk.
GlobalStorageSiK.BulkFilters.SCOPE = {
	MAIN_INVENTORY = "main",
	SINGLE_BAG = "bag",
	SELECTION = "selection",
	CATEGORY = "category",
}

--- Comprueba si un ítem está equipado en el personaje.
---@param item InventoryItem
---@param character IsoGameCharacter
---@return boolean
function GlobalStorageSiK.BulkFilters.isEquipped(item, character)
	if not item or not character then
		return false
	end

	if character:isEquipped(item) then
		return true
	end

	local worn = character:getWornItems()
	if not worn then
		return false
	end

	for i = 0, worn:size() - 1 do
		local wornItem = worn:get(i)
		if wornItem and wornItem:getItem() == item then
			return true
		end
	end

	return false
end

--- Comprueba si un ítem está marcado como favorito.
---@param item InventoryItem
---@return boolean
function GlobalStorageSiK.BulkFilters.isFavorite(item)
	if not item or not item.isFavorite then
		return false
	end
	return item:isFavorite()
end

--- Indica si el ítem puede incluirse en un depósito masivo.
---@param item InventoryItem
---@param character IsoGameCharacter
---@param scope string
---@param sourceContainer ItemContainer|nil
---@return boolean allowed
---@return string|nil reason
function GlobalStorageSiK.BulkFilters.canDeposit(item, character, scope, sourceContainer)
	if not item or not character then
		return false, "invalid"
	end

	if GlobalStorageSiK.Sandbox.respectEquippedItems() and GlobalStorageSiK.BulkFilters.isEquipped(item, character) then
		return false, "equipped"
	end

	if GlobalStorageSiK.Sandbox.respectFavoriteItems() and GlobalStorageSiK.BulkFilters.isFavorite(item) then
		return false, "favorite"
	end

	if scope == GlobalStorageSiK.BulkFilters.SCOPE.SINGLE_BAG then
		if not sourceContainer or item:getContainer() ~= sourceContainer then
			return false, "wrong_bag"
		end
	end

	return true, nil
end

--- Recoge ítems candidatos desde un contenedor según scope.
---@param container ItemContainer
---@param character IsoGameCharacter
---@param scope string
---@return InventoryItem[]
function GlobalStorageSiK.BulkFilters.collectCandidates(container, character, scope)
	local candidates = {}
	if not container or not character then
		return candidates
	end

	local items = container:getItems()
	for i = 0, items:size() - 1 do
		local item = items:get(i)
		local allowed = GlobalStorageSiK.BulkFilters.canDeposit(item, character, scope, container)
		if allowed then
			table.insert(candidates, item)
		end
	end

	return candidates
end
