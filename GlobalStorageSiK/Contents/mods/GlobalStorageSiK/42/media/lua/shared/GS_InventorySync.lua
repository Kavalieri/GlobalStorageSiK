--[[
	GlobalStorageSiK - Sincronización de inventario (servidor MP)
	Autor: SiK
	Fecha: 2025-06-24
	Descripción: Elimina y añade ítems notificando al cliente en multijugador.
]]

GlobalStorageSiK.InventorySync = {}

-- Durante una operación autoritativa se agrupan los mensajes vanilla por
-- contenedor. El estado Java se modifica inmediatamente, pero MP recibe una
-- lista por origen/destino en vez de dos paquetes por cada objeto. Esto evita
-- saturar la conexión del jugador y dejar copias fantasma en su inventario al
-- depositar cientos de instancias.
local batchDepth = 0
local pendingRemovals = {}
local pendingAdds = {}

local function notifyPlayerNow(player)
	if not player or not (isServer and isServer()) then return end
	pcall(function()
		if player.syncInventory then
			player:syncInventory()
		elseif player.sendInventory then
			player:sendInventory()
		end
	end)
end

local function queueItem(groups, container, item)
	local group = groups[container]
	if not group then
		group = { container = container, items = {} }
		groups[container] = group
	end
	group.items[#group.items + 1] = item
end

local function toJavaList(items)
	if not ArrayList or not ArrayList.new then
		return nil
	end
	local list = ArrayList.new()
	for i = 1, #items do
		list:add(items[i])
	end
	return list
end

local function flushGroups(groups, batchFn, singleFn)
	for _, group in pairs(groups) do
		local sent = false
		local list = toJavaList(group.items)
		if list and batchFn then
			local ok = pcall(batchFn, group.container, list)
			sent = ok
		end
		if not sent and singleFn then
			for i = 1, #group.items do
				pcall(singleFn, group.container, group.items[i])
			end
		end
	end
end

function GlobalStorageSiK.InventorySync.beginBatch()
	if isServer and isServer() then
		batchDepth = batchDepth + 1
	end
end

function GlobalStorageSiK.InventorySync.endBatch()
	if not (isServer and isServer()) or batchDepth <= 0 then
		return
	end
	batchDepth = batchDepth - 1
	if batchDepth > 0 then
		return
	end
	local removals = pendingRemovals
	local additions = pendingAdds
	pendingRemovals = {}
	pendingAdds = {}
	flushGroups(removals, sendRemoveItemsFromContainer, sendRemoveItemFromContainer)
	flushGroups(additions, sendAddItemsToContainer, sendAddItemToContainer)
	-- No forzar player:syncInventory() despues de los paquetes incrementales.
	-- Vanilla usa sendAddItemsToContainer(player:getInventory(), items) como
	-- notificacion completa del lote. Enviar inmediatamente despues un snapshot
	-- global del jugador permite que ambos paquetes lleguen/apliquen fuera de
	-- orden y que el snapshot anterior sobrescriba parte de las altas. En la
	-- prueba dedicada dev9 el servidor confirmaba 10 clavos por micro-lote pero
	-- el cliente solo conservaba aproximadamente 2. Un unico mecanismo de sync
	-- por mutacion evita esa carrera y sigue exactamente el patron vanilla B42.
end

---@param fn function
---@return any
function GlobalStorageSiK.InventorySync.withBatch(fn)
	GlobalStorageSiK.InventorySync.beginBatch()
	-- No guardar los retornos de pcall en una tabla y desempaquetarla sin un
	-- limite explicito. Un retorno perfectamente valido como
	--   true, nil, 10
	-- crea un hueco en el indice 2; en Kahlua/Lua la longitud de esa tabla no
	-- esta definida y unpack puede cortar antes del 10. Eso hizo que el servidor
	-- moviese 10 unidades pero confirmase moved=0 al cliente, deteniendo cada
	-- retirada incremental tras el primer micro-lote. Los consumidores actuales
	-- usan como maximo cuatro valores (la lectura prestada añade itemIds);
	-- conservamos margen sin depender de #table.
	local ok, r1, r2, r3, r4, r5, r6, r7, r8 = pcall(fn)
	GlobalStorageSiK.InventorySync.endBatch()
	if not ok then
		error(r1)
	end
	return r1, r2, r3, r4, r5, r6, r7, r8
end

--- Comprueba espacio en contenedor (B42: hasRoomFor(character, item)). La
--- carga ilimitada solo anula la capacidad del inventario principal del propio
--- personaje; bolsas y cofres conservan siempre su límite físico.
---@param container ItemContainer
---@param item InventoryItem
---@param character IsoPlayer|IsoGameCharacter|nil
---@return boolean
function GlobalStorageSiK.InventorySync.containerHasRoom(container, item, character)
	if not container or not item then
		return false
	end
	if character and character.isUnlimitedCarry and character.getInventory then
		local unlimitedOk, unlimited = pcall(function()
			return character:isUnlimitedCarry() == true
				and character:getInventory() == container
		end)
		if unlimitedOk and unlimited then
			return true
		end
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
	if container.getCapacity and container.getWeight then
		local cap = container:getCapacity()
		local cur = container:getWeight()
		local weight = 0
		if item.getActualWeight then
			weight = item:getActualWeight()
		elseif item.getWeight then
			weight = item:getWeight()
		end
		return (cur + weight) <= cap
	end
	return true
end

--- Notifica al cliente cambios en el inventario del jugador.
---@param player IsoPlayer|nil
function GlobalStorageSiK.InventorySync.notifyPlayer(player)
	notifyPlayerNow(player)
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
		if batchDepth > 0 then
			queueItem(pendingRemovals, cont, item)
		elseif sendRemoveItemFromContainer then
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
	if not GlobalStorageSiK.InventorySync.containerHasRoom(container, item, character) then
		return false
	end
	container:AddItem(item)
	if isServer and isServer() then
		if batchDepth > 0 then
			queueItem(pendingAdds, container, item)
		elseif sendAddItemToContainer then
			sendAddItemToContainer(container, item)
		end
	end
	-- No llamar tambien a notifyPlayer() cuando el destino es el inventario
	-- del personaje. Tanto sendAddItemToContainer() como su variante plural
	-- ya replican el alta en MP; añadir un snapshot completo despues reproduce
	-- la misma carrera que en los lotes. En SP la mutacion Java local ya es
	-- visible y tampoco necesita una segunda ruta de sincronizacion.
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
	if not GlobalStorageSiK.InventorySync.containerHasRoom(dest, item, character) then
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
	if GlobalStorageSiK.InventorySync.containerHasRoom(inv, item, player) then
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
