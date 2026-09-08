--[[
	GlobalStorageSiK - Depósito dirigido (cliente)
	Autor: SiK
	Fecha: 2025-06-24
	Descripción: Comandos depositItems y arrastre B42.
]]

require "GS_NetClient"
require "GS_Deposit"
require "GS_TerminalAccess"
require "GS_Network"
require "GS_DepositSources"
require "GS_I18n"
require "GS_PlayerUtils"
require "GS_Debug"
require "GS_TransferQueue"

GlobalStorageSiK.DepositClient = {}

--- Resuelve ítems del arrastre (formato B42, incluye mochilas).
---@param dragging table
---@return InventoryItem[]
local function resolveDraggedItemList(dragging)
	if not dragging then
		return {}
	end
	if ISInventoryPane and ISInventoryPane.getActualItems then
		local items = ISInventoryPane.getActualItems(dragging)
		if items and #items > 0 then
			return items
		end
	end
	local out = {}
	if type(dragging) == "table" then
		for i = 1, #dragging do
			local entry = dragging[i]
			if entry and entry.items then
				for j = 2, #entry.items do
					if entry.items[j] and entry.items[j].getContainer then
						table.insert(out, entry.items[j])
					end
				end
			elseif entry and entry.getContainer then
				table.insert(out, entry)
			end
		end
	end
	return out
end

--- Resuelve ítems en arrastre (B42).
---@return InventoryItem[]
function GlobalStorageSiK.DepositClient.collectDraggedItems()
	if not ISMouseDrag or not ISMouseDrag.dragging then
		return {}
	end
	return resolveDraggedItemList(ISMouseDrag.dragging)
end

--- Indica si hay ítems en arrastre.
---@return boolean
function GlobalStorageSiK.DepositClient.isDraggingItems()
	return #GlobalStorageSiK.DepositClient.collectDraggedItems() > 0
end

--- Recoge IDs de ítems.
---@param items InventoryItem[]
---@return number[]
function GlobalStorageSiK.DepositClient.collectItemIds(items)
	local ids = {}
	local seen = {}
	if not items then
		return ids
	end
	for i = 1, #items do
		local item = items[i]
		local id = GlobalStorageSiK.Deposit.getItemId(item)
		if id and not seen[id] then
			seen[id] = true
			table.insert(ids, id)
		end
	end
	return ids
end

--- Comprueba si los ítems pueden depositarse (no desde nodos de red).
---@param items InventoryItem[]
---@return boolean
function GlobalStorageSiK.DepositClient.canDepositDraggedItems(items, playerArg)
	if not items or #items == 0 or #items > 4096 then
		return false
	end
	for i = 1, #items do
		local item = items[i]
		local container = item and item.getContainer and item:getContainer() or nil
		local world = item and item.getWorldItem and item:getWorldItem() or nil
		if world then
			local player = GlobalStorageSiK.PlayerUtils.resolve(playerArg)
			if world:getItem() ~= item or not GlobalStorageSiK.FloorTargets.canAccessSquare(player, world:getSquare()) then return false end
		elseif not container or (container.getType and container:getType() == "floor") then
			return false
		end
		if container and GlobalStorageSiK.DepositSources.isNetworkNodeContainer(container) then
			return false
		end
	end
	return true
end

-- Capture the entire gesture before arming a queue. Mixed floor/container
-- selections occupy one bounded job; no Java item/square is retained there.
function GlobalStorageSiK.DepositClient.sendDraggedItems(items, playerArg, opts)
	if not GlobalStorageSiK.DepositClient.canDepositDraggedItems(items, playerArg) or #items > 4096 then return false end
	local physical, seen, hasFloor = {}, {}, false
	for i = 1, #items do
		local item = items[i]
		local id = GlobalStorageSiK.Deposit.getItemId(item)
		if type(id) ~= "number" or id ~= id or id < 0 or id == math.huge or id ~= math.floor(id) then return false end
		if not seen[id] then
			seen[id] = true
			local world = item.getWorldItem and item:getWorldItem() or nil
			local entry = { kind = "container", itemId = id }
			if world then
				entry.kind, entry.sourceKey, entry.fullType = "floor",
					GlobalStorageSiK.FloorTargets.squareKey(world:getSquare()), item:getFullType()
				if not entry.sourceKey then return false end
				hasFloor = true
			end
			physical[#physical + 1] = entry
		end
	end
	if not hasFloor then
		return GlobalStorageSiK.DepositClient.sendDepositItems(
			GlobalStorageSiK.DepositClient.collectItemIds(items), playerArg, opts)
	end
	opts = opts or {}
	local player = GlobalStorageSiK.PlayerUtils.resolve(playerArg)
	local queueId = GlobalStorageSiK.TransferQueue.arm({ type = "physical", physicalItems = physical,
		networkId = opts.networkId, searchQuery = opts.searchQuery }, player)
	return queueId ~= nil
end

--- Solicita depósito de ítems por ID (validación en servidor).
---@param itemIds number[]
---@param playerArg IsoPlayer|number|nil
---@param opts table|nil { networkId=string, origin=string, operationId=string, preferredNodeId=string }
---@return boolean
function GlobalStorageSiK.DepositClient.sendDepositItems(itemIds, playerArg, opts)
	if not itemIds or #itemIds == 0 then
		return false
	end
	-- Una sola cabecera por lote. El traceback temporal usado para investigar
	-- reenvíos repetidos se retiró: duplicaba muchas líneas y no pertenece al
	-- flujo normal; el job posterior queda correlacionado por TransferQueue.
	GlobalStorageSiK.Debug.log("Deposit", "sendDepositItems", "count=" .. tostring(#itemIds))
	opts = opts or {}
	local player = GlobalStorageSiK.PlayerUtils.resolve(playerArg)
    if not player or not player.getPlayerNum then return false end
    local playerNum = player:getPlayerNum()
	local queueId, sendNow, networkId = nil, true, nil
	if GlobalStorageSiK.TransferQueue and GlobalStorageSiK.TransferQueue.arm then
		queueId, sendNow, networkId = GlobalStorageSiK.TransferQueue.arm({
			type = "depositIds",
			itemIds = itemIds,
			networkId = opts.networkId,
			origin = opts.origin,
			operationId = opts.operationId,
			preferredNodeId = opts.preferredNodeId,
		}, player)
		if not queueId then return false end
	end
	if sendNow == false then return true end
	local sent = GlobalStorageSiK.NetClient.sendCommand("depositItems", {
		itemIds = itemIds,
		origin = opts.origin or "player",
		operationId = opts.operationId,
		preferredNodeId = opts.preferredNodeId,
		queueId = queueId,
		depositId = queueId,
		networkId = networkId,
	}, player)
	if not sent and GlobalStorageSiK.TransferQueue and GlobalStorageSiK.TransferQueue.clear then
		GlobalStorageSiK.TransferQueue.clear(playerNum)
	end
	return sent
end

--- Recopila itemId físicos del mismo tipo y contenedor que la referencia.
--- InventoryItem:getCount() no representa el tamaño de una pila transferible.
---@param referenceItem InventoryItem|nil
---@param limit number|nil
---@return number[]
function GlobalStorageSiK.DepositClient.collectSameTypeItemIds(referenceItem, limit)
	if not referenceItem or not referenceItem.getContainer or not referenceItem.getFullType then
		return {}
	end
	local container = referenceItem:getContainer()
	local fullType = referenceItem:getFullType()
	local items = container and container.getItems and container:getItems() or nil
	if not items or not fullType then return {} end
	local wanted = limit and math.max(0, math.floor(tonumber(limit) or 0)) or nil
	local ids = {}
	for i = 0, items:size() - 1 do
		if wanted and #ids >= wanted then break end
		local candidate = items:get(i)
		if candidate and candidate.getFullType and candidate:getFullType() == fullType then
			local id = GlobalStorageSiK.Deposit.getItemId(candidate)
			if id then ids[#ids + 1] = id end
		end
	end
	return ids
end

--- Solicita depósito de una cantidad de instancias físicas del mismo tipo.
---@param playerArg IsoPlayer|number|nil
---@param referenceItem InventoryItem|nil
---@param count number
---@return boolean
function GlobalStorageSiK.DepositClient.sendDepositPartial(playerArg, referenceItem, count)
	local ids = GlobalStorageSiK.DepositClient.collectSameTypeItemIds(referenceItem, count)
	if #ids == 0 then return false end
	return GlobalStorageSiK.DepositClient.sendDepositItems(ids, playerArg)
end

--- Solicita depósito de todo el contenedor del ítem de referencia.
---@param playerArg IsoPlayer|number|nil
---@param referenceItem InventoryItem|nil
---@return boolean
function GlobalStorageSiK.DepositClient.sendDepositContainer(playerArg, referenceItem)
    local source = referenceItem and referenceItem.getContainer and referenceItem:getContainer()
    local items = source and source.getItems and source:getItems()
    if not items then return false end
    -- Capture the physical items at the gesture, not a live container expansion
    -- on a later tick. Items added afterwards belong to a subsequent gesture.
    local captured = {}
    for i = 0, items:size() - 1 do captured[#captured + 1] = items:get(i) end
    local ids = GlobalStorageSiK.DepositClient.collectItemIds(captured)
    return GlobalStorageSiK.DepositClient.sendDepositItems(ids, playerArg)
end

--- Deposita ítems ya resueltos (arrastre).
---@param items InventoryItem[]
---@return boolean
function GlobalStorageSiK.DepositClient.depositItemList(items, playerArg)
	return GlobalStorageSiK.DepositClient.sendDraggedItems(items, playerArg)
end

--- Limpia estado de arrastre tras depósito (sin re-disparar onMouseUp del inventario).
function GlobalStorageSiK.DepositClient.clearDrag()
	if ISMouseDrag then
		ISMouseDrag.dragging = nil
		ISMouseDrag.draggingFocus = nil
	end
	if ISInventoryPage and ISInventoryPage.dirtyUI then
		pcall(ISInventoryPage.dirtyUI)
	end
end
