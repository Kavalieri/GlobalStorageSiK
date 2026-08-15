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
function GlobalStorageSiK.DepositClient.canDepositDraggedItems(items)
	if not items or #items == 0 then
		return false
	end
	for i = 1, #items do
		local item = items[i]
		local container = item and item.getContainer and item:getContainer() or nil
		if not container then
			return false
		end
		if GlobalStorageSiK.DepositSources.isNetworkNodeContainer(container) then
			return false
		end
	end
	return true
end

--- Muestra halo de depósito pendiente de forma segura.
---@param player IsoPlayer|nil
local function showDepositPending(player)
	if not player or not player.setHaloNote then
		return
	end
	pcall(function()
		player:setHaloNote(GlobalStorageSiK.I18n.text("IGUI_GS_DepositPending"), 200, 220, 200, 200)
	end)
end

--- Solicita depósito de ítems por ID (validación en servidor).
---@param itemIds number[]
---@param playerArg IsoPlayer|number|nil
---@return boolean
function GlobalStorageSiK.DepositClient.sendDepositItems(itemIds, playerArg)
	if not itemIds or #itemIds == 0 then
		return false
	end
	-- DIAGNOSTICO TEMPORAL (2026-08-16, "el mismo lote de ~200 items se
	-- reenvia una y otra vez indefinidamente, incluso tras terminar un
	-- trabajo con exito"): no se pudo confirmar aun por lectura de codigo
	-- quien re-arma el trabajo completo repetidamente (candidatos
	-- descartados por ahora: GS_TerminalDrop ya filtra items de contenedores
	-- de red vía canDepositDraggedItems). print incondicional con traceback
	-- para identificar la funcion/fichero que llama a sendDepositItems cada
	-- vez que esto ocurra en el proximo test. Quitar cuando se confirme la
	-- causa real.
	GlobalStorageSiK.Log.warn("DepositClient", string.format("sendDepositItems | count=%s", tostring(#itemIds)))
	if debug and debug.traceback then
		print(debug.traceback("[GlobalStorageSiK:DepositDiag] sendDepositItems call stack", 2))
	end
	local player = GlobalStorageSiK.PlayerUtils and GlobalStorageSiK.PlayerUtils.resolve(playerArg)
		or GlobalStorageSiK.NetClient.getPlayer()
	showDepositPending(player)
	if GlobalStorageSiK.TransferQueue and GlobalStorageSiK.TransferQueue.arm then
		GlobalStorageSiK.TransferQueue.arm({ type = "depositIds", itemIds = itemIds })
	end
	return GlobalStorageSiK.NetClient.sendCommand("depositItems", {
		itemIds = itemIds,
	})
end

--- Solicita depósito parcial de un ítem apilable.
---@param playerArg IsoPlayer|number|nil
---@param referenceItem InventoryItem|nil
---@param count number
---@return boolean
function GlobalStorageSiK.DepositClient.sendDepositPartial(playerArg, referenceItem, count)
	local refId = GlobalStorageSiK.Deposit.getItemId(referenceItem)
	if not refId or not count or count < 1 then
		return false
	end
	showDepositPending(GlobalStorageSiK.PlayerUtils.resolve(playerArg))
	return GlobalStorageSiK.NetClient.sendCommand("depositItems", {
		mode = "partial",
		referenceItemId = refId,
		count = math.floor(count),
	})
end

--- Solicita depósito de todo el contenedor del ítem de referencia.
---@param playerArg IsoPlayer|number|nil
---@param referenceItem InventoryItem|nil
---@return boolean
function GlobalStorageSiK.DepositClient.sendDepositContainer(playerArg, referenceItem)
	local refId = GlobalStorageSiK.Deposit.getItemId(referenceItem)
	if not refId then
		return false
	end
	showDepositPending(GlobalStorageSiK.PlayerUtils.resolve(playerArg))
	if GlobalStorageSiK.TransferQueue and GlobalStorageSiK.TransferQueue.arm then
		GlobalStorageSiK.TransferQueue.arm({ type = "container", referenceItemId = refId })
	end
	return GlobalStorageSiK.NetClient.sendCommand("depositItems", {
		mode = "container",
		referenceItemId = refId,
	})
end

--- Deposita ítems ya resueltos (arrastre).
---@param items InventoryItem[]
---@return boolean
function GlobalStorageSiK.DepositClient.depositItemList(items)
	if not GlobalStorageSiK.DepositClient.canDepositDraggedItems(items) then
		return false
	end
	local ids = GlobalStorageSiK.DepositClient.collectItemIds(items)
	if #ids == 0 then
		return false
	end
	return GlobalStorageSiK.DepositClient.sendDepositItems(ids)
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
