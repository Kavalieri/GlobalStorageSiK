--[[

	GlobalStorageSiK - Transferencias servidor

	Autor: SiK

	Fecha: 2025-06-23

	Descripción: Depósito y extracción atómicos en la red (MP autoritativo).

]]



require "GS_Network"

require "GS_Router"

require "GS_Power"

require "GS_Sandbox"

require "GS_BulkFilters"

require "GS_InventorySync"

require "GS_Index"

require "GS_TransferLock"

require "GS_Permissions"



GlobalStorageSiK.Transfer = {}



--- Mueve un ítem entre contenedores en servidor (con sync MP).

---@param item InventoryItem

---@param source ItemContainer

---@param dest ItemContainer

---@param character IsoPlayer|IsoGameCharacter|nil

---@return boolean

local function moveItem(item, source, dest, character)

	if not item or not source or not dest then

		return false

	end

	if not source:contains(item) then

		return false

	end

	if not GlobalStorageSiK.Router.containerHasSpace(dest, item, character) then

		return false

	end

	return GlobalStorageSiK.InventorySync.moveBetween(source, dest, item, character)

end



--- Cuenta unidades disponibles de un tipo en contenedores vivos de la red.

---@param networkId string|nil

---@param fullType string

---@return number

function GlobalStorageSiK.Transfer.countAvailableUnits(networkId, fullType, player)

	if not fullType or fullType == "" then

		return 0

	end

	local total = 0

	local live = GlobalStorageSiK.Permissions.filterLiveContainers(
		player, networkId, GlobalStorageSiK.Network.getLiveContainers(networkId))

	for i = 1, #live do

		local container = live[i].container

		if container and container.getItems then

			local items = container:getItems()

			for j = 0, items:size() - 1 do

				local item = items:get(j)

				if item and item.getFullType and item:getFullType() == fullType then

					-- Una entrada Java/itemId es una unidad física transferible.
					-- getCount() contiene metadata de script/receta en varios tipos.
					total = total + 1

				end

			end

		end

	end

	return total

end



--- Comprueba que el ítem sigue en su contenedor (revalidación MP).
---@param container ItemContainer
---@param item InventoryItem
---@return boolean
local function sourceContains(container, item)
	if not container or not item then
		return false
	end
	if container.contains and container:contains(item) then
		return true
	end
	if item.getContainer and item:getContainer() == container then
		return true
	end
	return false
end



--- Extrae unidades concretas de un tipo hacia un contenedor destino.

---@param player IsoPlayer

---@param fullType string

---@param networkId string|nil

---@param units number

---@param destContainer ItemContainer|nil

---@return number movedUnits

---@return string|nil reason

---@return number[] movedItemIds

---@return string[] sourceNodeIds

local function withdrawUnits(player, fullType, networkId, units, destContainer)

	destContainer = destContainer or player:getInventory()

	if units <= 0 then

		return 0, "invalid"

	end

	local live = GlobalStorageSiK.Permissions.filterLiveContainers(
		player, networkId, GlobalStorageSiK.Network.getLiveContainers(networkId))

	local moved = 0

	local movedItemIds = {}

	local sourceNodeIds = {}

	local lastReason = nil

	for i = 1, #live do

		if moved >= units then

			break

		end

		local container = live[i].container

		local sourceNodeId = live[i].entry and live[i].entry.id or nil

		if not container or not container.getItems then

			-- skip

		else

			local items = container:getItems()

			local j = 0

			while moved < units and j < items:size() do

				local item = items:get(j)

				if not item or item.getFullType == nil or item:getFullType() ~= fullType then

					j = j + 1

				elseif not sourceContains(container, item) then

					lastReason = "not_found"

					j = j + 1

				else

					-- Nunca dividir una instancia usando InventoryItem:getCount():
					-- cada itemId cubre exactamente una unidad física.
					local toMove = item

					if not toMove then

						lastReason = "move_failed"

						j = j + 1

					elseif not GlobalStorageSiK.Router.containerHasSpace(destContainer, toMove, player) then

						lastReason = "no_room"

						break

					elseif moveItem(toMove, toMove:getContainer() or container, destContainer, player) then

						moved = moved + 1

						if toMove.getID then

							movedItemIds[#movedItemIds + 1] = toMove:getID()

							sourceNodeIds[#sourceNodeIds + 1] = sourceNodeId and tostring(sourceNodeId) or ""

						end

					else

						lastReason = "move_failed"

						j = j + 1

					end

				end

			end

		end

	end

	if moved > 0 then

		return moved, nil, movedItemIds, sourceNodeIds

	end

	return 0, lastReason or "not_found", movedItemIds, sourceNodeIds

end



--- Notifica cambio de inventario de red en servidor.
--- La revisión y snapshots se aplican una sola vez en afterTransferSync (lote).
---@param networkId string|nil
---@param movedUnits number|nil
local function notifyInventoryChanged(networkId, movedUnits)
	-- Intencionalmente vacío: evitar ModData.transmit por cada ítem movido.
end



--- Crea una captura de enrutado reutilizable durante un micro-lote. Las
--- transferencias individuales pueden omitirla; los lotes deben compartirla
--- para no reescanear toda la red por cada item.
---@param player IsoPlayer
---@param networkId string|nil
---@return table
function GlobalStorageSiK.Transfer.createDepositSession(player, networkId)
	local live = GlobalStorageSiK.Permissions.filterLiveContainers(
		player, networkId, GlobalStorageSiK.Network.getLiveContainers(networkId))
	return {
		networkId = networkId,
		liveNodes = live,
		affinityIndex = GlobalStorageSiK.Router.buildAffinityIndex(live),
	}
end

--- Deposita un ítem del jugador en la red.

---@param player IsoPlayer

---@param item InventoryItem

---@param networkId string|nil

---@param options table|nil { session=table, preferredNodeId=string }

---@return boolean ok

---@return string|nil reason

function GlobalStorageSiK.Transfer.depositItem(player, item, networkId, options)

	if not player or not item then

		return false, "invalid"

	end

	if not GlobalStorageSiK.Sandbox.remoteTransferEnabled() then

		return false, "remote_disabled"

	end

	if not GlobalStorageSiK.Power.networkPowered(networkId) then

		return false, "no_power"

	end



	local character = player

	local source = item:getContainer()

	if not source then

		return false, "no_source"

	end

	if not sourceContains(source, item) then

		return false, "not_found"

	end



	local allowed = GlobalStorageSiK.BulkFilters.canDeposit(item, character, GlobalStorageSiK.BulkFilters.SCOPE.MAIN_INVENTORY, source)

	if not allowed then

		return false, "filtered"

	end



	options = options or {}
	local session = options.session
	if not session or session.networkId ~= networkId then
		session = GlobalStorageSiK.Transfer.createDepositSession(player, networkId)
	end
	local live = session.liveNodes or {}

	local target, targetReason = GlobalStorageSiK.Router.pickDepositTarget(item, live, character, {
		affinityIndex = session.affinityIndex,
		preferredNodeId = options.preferredNodeId,
	})

	if not target then

		return false, targetReason or "no_space"

	end



	if moveItem(item, source, target.container, character) then
		local targetId = target.entry and target.entry.id or nil
		local targetIndex = targetId and session.affinityIndex.nodeIndexById[tostring(targetId)] or nil
		GlobalStorageSiK.Router.updateAffinityIndex(session.affinityIndex, targetIndex, item, 1)

		local units = 1

		notifyInventoryChanged(networkId, units)

		return true, nil

	end

	return false, "move_failed"

end



--- Extrae ítems por tipo hacia un contenedor accesible.

---@param player IsoPlayer

---@param fullType string

---@param networkId string|nil

---@param amount number|nil 1 = una unidad; 0 o negativo = todo lo disponible

---@param destContainer ItemContainer|nil

---@return boolean ok

---@return string|nil reason

---@return number moved

---@return number[] movedItemIds

---@return string[] sourceNodeIds

function GlobalStorageSiK.Transfer.withdrawType(player, fullType, networkId, amount, destContainer)

	if not player or not fullType or fullType == "" then

		return false, "invalid", 0, {}

	end

	if not GlobalStorageSiK.Sandbox.remoteTransferEnabled() then

		return false, "remote_disabled", 0, {}

	end

	if not GlobalStorageSiK.Power.networkPowered(networkId) then

		return false, "no_power", 0, {}

	end



	local target = amount or 1
	-- Nunca recorrer/mover un tipo completo en una sola llamada. El cliente
	-- serializa la operación lógica y solicita el siguiente micro-lote solo
	-- después de recibir la confirmación correlacionada del anterior.
	target = math.floor(tonumber(target) or 1)
	if target <= 0 then target = GlobalStorageSiK.Sandbox.getMaxItemsPerBulkTick() end
	target = math.min(target, GlobalStorageSiK.Sandbox.getMaxItemsPerBulkTick())



	local moved, reason, movedItemIds, sourceNodeIds = withdrawUnits(player, fullType, networkId, target, destContainer)

	if moved > 0 then

		notifyInventoryChanged(networkId, moved)

		if moved < target and reason then

			return true, "partial:" .. tostring(reason), moved, movedItemIds, sourceNodeIds

		end

		return true, nil, moved, movedItemIds, sourceNodeIds

	end

	return false, reason or "not_found", 0, movedItemIds or {}, sourceNodeIds or {}

end
