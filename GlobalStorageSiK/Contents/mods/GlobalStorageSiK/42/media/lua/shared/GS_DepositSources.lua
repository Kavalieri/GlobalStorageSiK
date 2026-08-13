--[[
	GlobalStorageSiK - Fuentes de depósito (jugador + inventarios cercanos)
	Autor: SiK
	Fecha: 2025-06-24
	Descripción: Maleteros, cajas y contenedores accesibles cerca del jugador.
]]

require "GS_Sandbox"
require "GS_BulkFilters"
require "GS_I18n"
require "GS_Zones"
require "GS_Network"
require "GS_Utils"

GlobalStorageSiK.DepositSources = {}

--- Alcance en baldosas para contenedores del mundo (maleteros, cajas).
---@return number
function GlobalStorageSiK.DepositSources.getRange()
	local terminalRange = GlobalStorageSiK.Sandbox.getTerminalProximityRange()
	return math.max(4, terminalRange + 1)
end

--- Recoge inventario principal y mochilas equipadas.
---@param player IsoPlayer
---@return ItemContainer[]
function GlobalStorageSiK.DepositSources.collectPlayerContainers(player)
	local list = {}
	local seen = {}
	if not player then
		return list
	end
	local inv = player:getInventory()
	if inv and not seen[inv] then
		seen[inv] = true
		table.insert(list, inv)
	end
	local worn = player.getWornItems and player:getWornItems() or nil
	if worn then
		for i = 0, worn:size() - 1 do
			local wornItem = worn:get(i)
			if wornItem and wornItem.getItem then
				local item = wornItem:getItem()
				if item and item.getInventory then
					local bag = item:getInventory()
					if bag and not seen[bag] then
						seen[bag] = true
						table.insert(list, bag)
					end
				end
			end
		end
	end
	return list
end

--- Etiqueta legible de un contenedor para la UI.
---@param container ItemContainer
---@return string
function GlobalStorageSiK.DepositSources.describeContainer(container)
	if not container then
		return "?"
	end
	local T = GlobalStorageSiK.I18n and GlobalStorageSiK.I18n.text or getText

	local part = container.getVehiclePart and container:getVehiclePart() or nil
	if part then
		local typeKey = "IGUI_VehiclePart" .. tostring(container:getType())
		local partLabel = getText(typeKey)
		if not partLabel or partLabel == typeKey then
			partLabel = part.getId and part:getId() or container:getType()
		end
		return T("IGUI_GS_DepositVehiclePart", partLabel)
	end

	local parent = container.getParent and container:getParent() or nil
	if parent then
		if instanceof(parent, "IsoDeadBody") then
			return T("IGUI_GS_DepositCorpse")
		end
		if parent.getName then
			local name = parent:getName()
			if name and name ~= "" then
				return T("IGUI_GS_DepositNamed", name)
			end
		end
	end

	local typeKey = "IGUI_ContainerTitle_" .. tostring(container:getType())
	local typeLabel = getText(typeKey)
	if typeLabel and typeLabel ~= typeKey then
		return typeLabel
	end
	return T("IGUI_GS_DepositContainer")
end

--- Etiqueta del inventario del jugador (principal o mochila).
---@param player IsoPlayer
---@param container ItemContainer
---@param index number
---@return string
function GlobalStorageSiK.DepositSources.describePlayerContainer(player, container, index)
	local T = GlobalStorageSiK.I18n and GlobalStorageSiK.I18n.text or getText
	if index == 1 then
		return T("IGUI_GS_DepositMain")
	end
	local worn = player.getWornItems and player:getWornItems() or nil
	if worn then
		local bagIdx = 1
		for i = 0, worn:size() - 1 do
			local wornItem = worn:get(i)
			if wornItem and wornItem.getItem then
				local item = wornItem:getItem()
				if item and item.getInventory and item:getInventory() == container then
					return item:getName() or T("IGUI_GS_DepositBag", bagIdx)
				end
				if item and item.getInventory and item:getInventory() then
					bagIdx = bagIdx + 1
				end
			end
		end
	end
	return T("IGUI_GS_DepositBag", index)
end

--- Obtiene el ID de contenedor del mundo asociado a un ItemContainer.
---@param container ItemContainer|nil
---@return string|nil
function GlobalStorageSiK.DepositSources.getContainerWorldId(container)
	if not container then
		return nil
	end
	local parent = container.getParent and container:getParent() or nil
	if not parent or not parent.getSquare then
		return nil
	end
	if GlobalStorageSiK.Utils.getContainerId and GlobalStorageSiK.Utils.isStorageObject(parent) then
		-- Objeto con varios contenedores (nevera+congelador combinados, etc.):
		-- hay que identificar CUAL de sus indices es este "container" exacto,
		-- o siempre se devolveria el id del contenedor 0 aunque el deposito
		-- viniera del segundo compartimento (atribucion incorrecta de nodo).
		local count = GlobalStorageSiK.Utils.getContainerCount(parent)
		for containerIndex = 0, count - 1 do
			if GlobalStorageSiK.Utils.getContainerByIndex(parent, containerIndex) == container then
				return GlobalStorageSiK.Utils.getContainerId(parent, containerIndex)
			end
		end
		return GlobalStorageSiK.Utils.getContainerId(parent)
	end
	if parent.getContainer and parent:getContainer() == container then
		return GlobalStorageSiK.Utils.getContainerId(parent)
	end
	return nil
end

--- Indica si el contenedor pertenece a un nodo registrado de la red GS.
---@param container ItemContainer|nil
---@return boolean
function GlobalStorageSiK.DepositSources.isNetworkNodeContainer(container)
	if not container then
		return false
	end
	local worldId = GlobalStorageSiK.DepositSources.getContainerWorldId(container)
	if not worldId then
		return false
	end

	local registry = GlobalStorageSiK.Zones.getRegistry()
	if registry.nodes and registry.nodes[worldId] then
		return true
	end

	local netRegistry = GlobalStorageSiK.Network.getRegistry()
	GlobalStorageSiK.Network.ensureRegistry(netRegistry)
	local netId = netRegistry.defaultNetworkId
	local network = netRegistry.networks and netRegistry.networks[netId]
	if network and network.containers then
		for i = 1, #network.containers do
			if network.containers[i].id == worldId then
				return true
			end
		end
	end

	return false
end

--- Indica si el contenedor pertenece al inventario del jugador (principal o mochila equipada).
---@param player IsoPlayer
---@param container ItemContainer|nil
---@return boolean
function GlobalStorageSiK.DepositSources.isPlayerContainer(player, container)
	if not player or not container then
		return false
	end
	if player.getInventory and player:getInventory() == container then
		return true
	end
	local worn = player.getWornItems and player:getWornItems() or nil
	if worn then
		for i = 0, worn:size() - 1 do
			local wornItem = worn:get(i)
			if wornItem and wornItem.getItem then
				local item = wornItem:getItem()
				if item and item.getInventory and item:getInventory() == container then
					return true
				end
			end
		end
	end
	return false
end

--- Comprueba si el jugador puede acceder al contenedor (distancia, cerraduras, vehículo).
---@param player IsoPlayer
---@param container ItemContainer
---@return boolean
function GlobalStorageSiK.DepositSources.canPlayerAccessContainer(player, container)
	if not player or not container then
		return false
	end
	if GlobalStorageSiK.DepositSources.isPlayerContainer(player, container) then
		return true
	end
	if container.isInCharacterInventory and container:isInCharacterInventory(player) then
		return true
	end

	local playerSq = player.getSquare and player:getSquare() or nil
	if not playerSq then
		return false
	end

	local parent = container.getParent and container:getParent() or nil
	if not parent then
		return false
	end

	if instanceof(parent, "BaseVehicle") then
		if player.getVehicle and player:getVehicle() == parent then
			return true
		end
		local part = container.getVehiclePart and container:getVehiclePart() or nil
		if part and parent.canAccessContainer then
			return parent:canAccessContainer(part:getIndex(), player) == true
		end
		return false
	end

	if instanceof(parent, "IsoThumpable") then
		if parent.isLockedToCharacter and parent:isLockedToCharacter(player) then
			return false
		end
	end

	local sq = parent.getSquare and parent:getSquare() or nil
	if not sq then
		return false
	end

	return sq:DistToProper(playerSq) <= GlobalStorageSiK.DepositSources.getRange()
end

--- Intenta registrar un contenedor accesible y no duplicado.
---@param player IsoPlayer
---@param container ItemContainer|nil
---@param list ItemContainer[]
---@param seen table
local function tryAddNearby(player, container, list, seen)
	if not container or seen[container] then
		return
	end
	if container.isInCharacterInventory and container:isInCharacterInventory(player) then
		return
	end
	if GlobalStorageSiK.DepositSources.isNetworkNodeContainer(container) then
		return
	end
	if not GlobalStorageSiK.DepositSources.canPlayerAccessContainer(player, container) then
		return
	end
	seen[container] = true
	table.insert(list, container)
end

--- Registra contenedores de un objeto del mundo.
---@param player IsoPlayer
---@param obj IsoObject|nil
---@param list ItemContainer[]
---@param seen table
local function tryAddFromObject(player, obj, list, seen)
	if not obj then
		return
	end
	if obj.getContainer then
		tryAddNearby(player, obj:getContainer(), list, seen)
	end
	if obj.getInventory then
		tryAddNearby(player, obj:getInventory(), list, seen)
	end
end

--- Escanea una baldosa en busca de contenedores.
---@param player IsoPlayer
---@param sq IsoGridSquare|nil
---@param list ItemContainer[]
---@param seen table
local function scanSquare(player, sq, list, seen)
	if not sq then
		return
	end
	if sq.getVehicleContainer then
		tryAddNearby(player, sq:getVehicleContainer(), list, seen)
	end
	local objs = sq.getObjects and sq:getObjects() or nil
	if objs then
		for i = 0, objs:size() - 1 do
			tryAddFromObject(player, objs:get(i), list, seen)
		end
	end
	local specials = sq.getSpecialObjects and sq:getSpecialObjects() or nil
	if specials then
		for i = 0, specials:size() - 1 do
			tryAddFromObject(player, specials:get(i), list, seen)
		end
	end
end

--- Itera vehículos de una celda (API distinta en cliente B42).
---@param cell IsoCell|nil
---@param fn fun(vehicle: BaseVehicle)
local function foreachCellVehicle(cell, fn)
	if not cell or not fn then
		return
	end
	if cell.getVehicles then
		local vehicles = cell:getVehicles()
		if vehicles then
			if type(vehicles) == "table" then
				for i = 1, #vehicles do
					if vehicles[i] then
						fn(vehicles[i])
					end
				end
				return
			end
			if vehicles.size and type(vehicles.size) == "function" and vehicles.get and type(vehicles.get) == "function" then
				local n = vehicles:size()
				for i = 0, n - 1 do
					fn(vehicles:get(i))
				end
				return
			end
		end
	end
	if cell.getVehicleCount and cell.getVehicleForIndex then
		local n = cell:getVehicleCount()
		for i = 0, n - 1 do
			local vehicle = cell:getVehicleForIndex(i)
			if vehicle then
				fn(vehicle)
			end
		end
	end
end

--- Registra contenedores de un vehículo accesible.
---@param player IsoPlayer
---@param vehicle BaseVehicle|nil
---@param list ItemContainer[]
---@param seen table
local function tryAddVehicleContainers(player, vehicle, list, seen)
	if not vehicle or not vehicle.getPartCount then
		return
	end
	for i = 1, vehicle:getPartCount() do
		local part = vehicle:getPartByIndex(i - 1)
		if part and part.getItemContainer then
			local cont = part:getItemContainer()
			if cont and vehicle.canAccessContainer and vehicle:canAccessContainer(i - 1, player) then
				tryAddNearby(player, cont, list, seen)
			end
		end
	end
end

--- Recoge maleteros, cajas y contenedores del mundo cercanos al jugador.
---@param player IsoPlayer
---@return ItemContainer[]
function GlobalStorageSiK.DepositSources.collectNearbyContainers(player)
	local ok, result = pcall(function()
		local list = {}
		local seen = {}
		if not player then
			return list
		end
		local sq = player.getSquare and player:getSquare() or nil
		if not sq then
			return list
		end

		local range = GlobalStorageSiK.DepositSources.getRange()
		local px, py, pz = sq:getX(), sq:getY(), sq:getZ()
		local cell = sq.getCell and sq:getCell() or nil
		if cell and cell.getGridSquare then
			for dx = -range, range do
				for dy = -range, range do
					local tsq = cell:getGridSquare(px + dx, py + dy, pz)
					if tsq and tsq:DistToProper(sq) <= range then
						scanSquare(player, tsq, list, seen)
					end
				end
			end
		end

		foreachCellVehicle(cell, function(vehicle)
			if vehicle and vehicle.getSquare then
				local vsq = vehicle:getSquare()
				if vsq and vsq:DistToProper(sq) <= range then
					tryAddVehicleContainers(player, vehicle, list, seen)
				end
			end
		end)

		if player.getVehicle then
			local inVehicle = player:getVehicle()
			if inVehicle then
				tryAddVehicleContainers(player, inVehicle, list, seen)
			end
		end

		return list
	end)
	if ok and type(result) == "table" then
		return result
	end
	return {}
end

--- Construye lista de opciones de depósito masivo (solo inventario del jugador).
--- Los contenedores del mundo se depositan vía menú contextual o arrastre al terminal.
---@param player IsoPlayer|nil
---@return table[]
function GlobalStorageSiK.DepositSources.buildList(player)
	local T = GlobalStorageSiK.I18n and GlobalStorageSiK.I18n.text or getText
	local list = {}
	if not player then
		return list
	end

	local playerContainers = GlobalStorageSiK.DepositSources.collectPlayerContainers(player)

	table.insert(list, {
		label = T("IGUI_GS_DepositAll"),
		scope = GlobalStorageSiK.BulkFilters.SCOPE.MAIN_INVENTORY,
		containers = playerContainers,
	})

	for i = 1, #playerContainers do
		table.insert(list, {
			label = GlobalStorageSiK.DepositSources.describePlayerContainer(player, playerContainers[i], i),
			scope = GlobalStorageSiK.BulkFilters.SCOPE.SINGLE_BAG,
			containers = { playerContainers[i] },
		})
	end

	return list
end

--- Resuelve entrada de depósito por índice 1-based.
---@param player IsoPlayer
---@param listIndex number|nil
---@return table|nil
function GlobalStorageSiK.DepositSources.resolveEntry(player, listIndex)
	local entries = GlobalStorageSiK.DepositSources.buildList(player)
	local idx = listIndex or 1
	if idx < 1 or idx > #entries then
		return nil
	end
	return entries[idx]
end

--- Obtiene ID de ítem para clave de mochila.
---@param item InventoryItem|nil
---@return number|nil
local function bagItemId(item)
	if not item or not item.getID then
		return nil
	end
	local ok, id = pcall(function()
		return item:getID()
	end)
	if ok then
		return id
	end
	return nil
end

--- Genera clave estable de un contenedor accesible (cliente → servidor).
---@param player IsoPlayer
---@param container ItemContainer
---@return string|nil
function GlobalStorageSiK.DepositSources.buildContainerKey(player, container)
	if not container then
		return nil
	end

	local worldId = GlobalStorageSiK.DepositSources.getContainerWorldId(container)
	if worldId then
		return "world:" .. worldId
	end

	local part = container.getVehiclePart and container:getVehiclePart() or nil
	if part and part.getVehicle and part.getId then
		local veh = part:getVehicle()
		if veh and veh.getX then
			return string.format(
				"vehicle:%d,%d,%d:%s",
				math.floor(veh:getX()),
				math.floor(veh:getY()),
				math.floor(veh:getZ()),
				tostring(part:getId())
			)
		end
	end

	if player and player.getInventory and container == player:getInventory() then
		return "player:main"
	end

	if player then
		local worn = player.getWornItems and player:getWornItems() or nil
		if worn then
			for i = 0, worn:size() - 1 do
				local wornItem = worn:get(i)
				if wornItem and wornItem.getItem then
					local item = wornItem:getItem()
					if item and item.getInventory and item:getInventory() == container then
						local id = bagItemId(item)
						if id then
							return "bag:" .. tostring(id)
						end
					end
				end
			end
		end
	end

	return nil
end

--- Resuelve contenedor destino a partir de clave (servidor / cliente).
---@param player IsoPlayer
---@param key string|nil
---@return ItemContainer|nil
function GlobalStorageSiK.DepositSources.resolveContainerKey(player, key)
	if not player or not key or key == "" then
		return nil
	end

	local candidates = {}
	for _, c in ipairs(GlobalStorageSiK.DepositSources.collectPlayerContainers(player)) do
		table.insert(candidates, c)
	end
	for _, c in ipairs(GlobalStorageSiK.DepositSources.collectNearbyContainers(player)) do
		table.insert(candidates, c)
	end

	for i = 1, #candidates do
		local container = candidates[i]
		if GlobalStorageSiK.DepositSources.buildContainerKey(player, container) == key then
			return container
		end
	end

	return nil
end
