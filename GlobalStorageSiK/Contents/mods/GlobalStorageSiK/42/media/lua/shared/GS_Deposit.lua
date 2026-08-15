--[[
	GlobalStorageSiK - Depósito dirigido (ítems / contenedor)
	Autor: SiK
	Fecha: 2025-06-24
	Descripción: Depositar ítems concretos o un contenedor accesible (SP/MP autoritativo).
]]

require "GS_Sandbox"
require "GS_Power"
require "GS_BulkFilters"
require "GS_DepositSources"
require "GS_Transfer"
require "GS_Debug"
require "GS_I18n"

GlobalStorageSiK.Deposit = {}

--- Obtiene el ID numérico de un ítem.
---@param item InventoryItem|nil
---@return number|nil
function GlobalStorageSiK.Deposit.getItemId(item)
	if not item or not item.getID then
		return nil
	end
	local ok, id = pcall(function()
		return item:getID()
	end)
	if ok and id then
		return id
	end
	return nil
end

--- Busca un ítem por ID dentro de un contenedor (incluye subcontenedores de mochilas).
---@param container ItemContainer
---@param itemId number
---@param depth number|nil
---@return InventoryItem|nil
local function findInContainer(container, itemId, depth)
	if not container or not itemId then
		return nil
	end
	depth = depth or 0
	if depth > 10 then
		return nil
	end

	if container.getItemWithID then
		local ok, item = pcall(function()
			return container:getItemWithID(itemId)
		end)
		if ok and item then
			return item
		end
	end
	if container.getItemById then
		local okLegacy, itemLegacy = pcall(function()
			return container:getItemById(itemId)
		end)
		if okLegacy and itemLegacy then
			return itemLegacy
		end
	end
	if container.containsID and container:containsID(itemId) then
		local items = container:getItems()
		if items then
			for i = 0, items:size() - 1 do
				local item = items:get(i)
				if item and GlobalStorageSiK.Deposit.getItemId(item) == itemId then
					return item
				end
			end
		end
	end

	local items = container.getItems and container:getItems() or nil
	if items then
		for i = 0, items:size() - 1 do
			local item = items:get(i)
			if item and item.getInventory then
				local sub = item:getInventory()
				if sub then
					local nested = findInContainer(sub, itemId, depth + 1)
					if nested then
						return nested
					end
				end
			end
		end
	end

	return nil
end

--- Recoge contenedores accesibles para resolver ítems (jugador + cercanos no red).
---@param player IsoPlayer
---@return ItemContainer[]
function GlobalStorageSiK.Deposit.collectSearchContainers(player)
	local list = {}
	local seen = {}

	local function add(container)
		if container and not seen[container] then
			seen[container] = true
			table.insert(list, container)
		end
	end

	for _, c in ipairs(GlobalStorageSiK.DepositSources.collectPlayerContainers(player)) do
		add(c)
	end

	local ok, nearby = pcall(GlobalStorageSiK.DepositSources.collectNearbyContainers, player)
	if ok and nearby then
		for i = 1, #nearby do
			if not GlobalStorageSiK.DepositSources.isNetworkNodeContainer(nearby[i]) then
				add(nearby[i])
			end
		end
	end

	return list
end

--- Busca un ítem por ID en contenedores accesibles.
---@param player IsoPlayer
---@param itemId number
---@return InventoryItem|nil
---@return ItemContainer|nil
function GlobalStorageSiK.Deposit.findItemById(player, itemId)
	if not player or not itemId then
		return nil, nil
	end

	local containers = GlobalStorageSiK.Deposit.collectSearchContainers(player)
	for c = 1, #containers do
		local container = containers[c]
		if GlobalStorageSiK.DepositSources.canPlayerAccessContainer(player, container) then
			local item = findInContainer(container, itemId)
			if item then
				local actual = item.getContainer and item:getContainer() or container
				return item, actual
			end
		end
	end

	return nil, nil
end

--- Separa unidades de un ítem apilable para depósito parcial.
---@param item InventoryItem
---@param count number
---@return InventoryItem|nil
local function splitStackForDeposit(item, count)
	if not item or not count or count <= 0 then
		return nil
	end
	local total = 1
	if item.getCount then
		total = item:getCount() or 1
	end
	if count >= total then
		return item
	end
	if item.split then
		local ok, part = pcall(function()
			return item:split(count)
		end)
		if ok and part then
			return part
		end
	end
	local container = item.getContainer and item:getContainer() or nil
	if not container or not instanceItem or not item.getFullType then
		return nil
	end
	local part = instanceItem(item:getFullType())
	if not part then
		return nil
	end
	if part.copyModData and item.copyModData then
		pcall(function()
			part:copyModData(item)
		end)
	end
	part:setCount(count)
	item:setCount(total - count)
	if container.AddItem then
		pcall(function()
			container:AddItem(part)
		end)
	end
	return part
end

--- Deposita una cantidad parcial de un ítem por ID.
---@param player IsoPlayer
---@param networkId string|nil
---@param referenceItemId number
---@param count number
---@return table summary
function GlobalStorageSiK.Deposit.depositPartialCount(player, networkId, referenceItemId, count)
	local summary = { moved = 0, skipped = 0, failed = 0, reason = nil }

	local item, container = GlobalStorageSiK.Deposit.findItemById(player, referenceItemId)
	if not item or not container then
		summary.reason = "invalid"
		return summary
	end
	if GlobalStorageSiK.DepositSources.isNetworkNodeContainer(container) then
		summary.reason = "network_source"
		return summary
	end
	if not GlobalStorageSiK.DepositSources.canPlayerAccessContainer(player, container) then
		summary.reason = "no_access"
		return summary
	end
	if not GlobalStorageSiK.Sandbox.remoteTransferEnabled() then
		summary.reason = "remote_disabled"
		return summary
	end
	if not GlobalStorageSiK.Power.networkPowered(networkId) then
		summary.reason = "no_power"
		return summary
	end

	count = math.floor(count or 1)
	if count < 1 then
		summary.reason = "invalid"
		return summary
	end

	local allowed = GlobalStorageSiK.BulkFilters.canDeposit(
		item, player, GlobalStorageSiK.BulkFilters.SCOPE.SELECTION, item:getContainer()
	)
	if not allowed then
		summary.skipped = summary.skipped + 1
		return summary
	end

	local toMove = splitStackForDeposit(item, count)
	if not toMove then
		summary.failed = summary.failed + 1
		return summary
	end

	local ok, reason = GlobalStorageSiK.Transfer.depositItem(player, toMove, networkId)
	if ok then
		summary.moved = summary.moved + 1
	elseif reason == "filtered" then
		summary.skipped = summary.skipped + 1
	else
		summary.failed = summary.failed + 1
		if (reason == "no_space" or reason == "no_match") and not summary.reason then
			summary.reason = reason
		end
	end

	return summary
end

--- Deposita ítems por lista de IDs.
---@param player IsoPlayer
---@param networkId string|nil
---@param itemIds number[]
---@return table summary
function GlobalStorageSiK.Deposit.depositByIds(player, networkId, itemIds)
	local summary = { moved = 0, skipped = 0, failed = 0, reason = nil }

	if not player or not itemIds or #itemIds == 0 then
		summary.reason = "invalid"
		return summary
	end

	if not GlobalStorageSiK.Sandbox.remoteTransferEnabled() then
		summary.reason = "remote_disabled"
		return summary
	end
	if not GlobalStorageSiK.Power.networkPowered(networkId) then
		summary.reason = "no_power"
		return summary
	end

	local maxPerTick = GlobalStorageSiK.Sandbox.getMaxItemsPerBulkTick()
	local seenIds = {}

	for i = 1, #itemIds do
		if summary.moved >= maxPerTick then
			summary.reason = "limit"
			break
		end

		local itemId = itemIds[i]
		if itemId and not seenIds[itemId] then
			seenIds[itemId] = true
			local item, container = GlobalStorageSiK.Deposit.findItemById(player, itemId)
			if not item or not container then
				-- "No encontrado" NO cuenta como fallo real: GS_TransferQueue
				-- reenvia la lista COMPLETA de itemIds original en cada
				-- reintento (cuando se alcanza MaxItemsPerBulkTick), asi que
				-- los items YA depositados con exito en una pasada anterior
				-- ya no estan en ningun contenedor alcanzable del jugador -
				-- "no encontrado" en ese caso significa "ya se hizo", no un
				-- error. Contarlo como "failed" inflaba el resumen mostrado
				-- (ej. "5 depositados, 100 fallidos" con la transferencia
				-- COMPLETA realizada con exito) sin que hubiera ningun
				-- problema real. Se ignora en silencio.
				GlobalStorageSiK.Debug.log("Deposit", "depositByIds item not found (ya depositado o invalido)", tostring(itemId))
			elseif GlobalStorageSiK.DepositSources.isNetworkNodeContainer(container) then
				summary.skipped = summary.skipped + 1
			elseif not GlobalStorageSiK.DepositSources.canPlayerAccessContainer(player, container) then
				summary.skipped = summary.skipped + 1
			else
				local allowed = GlobalStorageSiK.BulkFilters.canDeposit(
					item, player, GlobalStorageSiK.BulkFilters.SCOPE.SELECTION, item:getContainer()
				)
				if not allowed then
					summary.skipped = summary.skipped + 1
				else
					local ok, reason = GlobalStorageSiK.Transfer.depositItem(player, item, networkId)
					if ok then
						summary.moved = summary.moved + 1
					elseif reason == "filtered" then
						summary.skipped = summary.skipped + 1
					else
						summary.failed = summary.failed + 1
						if (reason == "no_space" or reason == "no_match") and not summary.reason then
							summary.reason = reason
						end
						GlobalStorageSiK.Debug.log("Deposit", "depositByIds item failed", string.format(
							"fullType=%s reason=%s movedSoFar=%d",
							tostring(item.getFullType and item:getFullType() or "?"), tostring(reason), summary.moved
						))
					end
				end
			end
		end
	end

	return summary
end

--- Deposita todo lo permitido del contenedor de un ítem de referencia.
---@param player IsoPlayer
---@param networkId string|nil
---@param referenceItemId number
---@return table summary
function GlobalStorageSiK.Deposit.depositFromContainer(player, networkId, referenceItemId)
	local summary = { moved = 0, skipped = 0, failed = 0, reason = nil }

	local item, container = GlobalStorageSiK.Deposit.findItemById(player, referenceItemId)
	if not item or not container then
		summary.reason = "invalid"
		return summary
	end
	if GlobalStorageSiK.DepositSources.isNetworkNodeContainer(container) then
		summary.reason = "network_source"
		return summary
	end
	if not GlobalStorageSiK.DepositSources.canPlayerAccessContainer(player, container) then
		summary.reason = "no_access"
		return summary
	end

	if not GlobalStorageSiK.Sandbox.remoteTransferEnabled() then
		summary.reason = "remote_disabled"
		return summary
	end
	if not GlobalStorageSiK.Power.networkPowered(networkId) then
		summary.reason = "no_power"
		return summary
	end

	local maxPerTick = GlobalStorageSiK.Sandbox.getMaxItemsPerBulkTick()
	local candidates = GlobalStorageSiK.BulkFilters.collectCandidates(
		container, player, GlobalStorageSiK.BulkFilters.SCOPE.SINGLE_BAG
	)

	for c = 1, #candidates do
		if summary.moved >= maxPerTick then
			summary.reason = "limit"
			break
		end
		local candidate = candidates[c]
		if candidate and candidate:getContainer() == container then
			local ok, reason = GlobalStorageSiK.Transfer.depositItem(player, candidate, networkId)
			if ok then
				summary.moved = summary.moved + 1
			elseif reason == "filtered" then
				summary.skipped = summary.skipped + 1
			else
				summary.failed = summary.failed + 1
				if (reason == "no_space" or reason == "no_match") and not summary.reason then
					summary.reason = reason
				end
				-- Diagnostico (gated DebugMode): el equipo reportaba resúmenes
				-- "5 movidos / 100 fallidos" cuando en realidad TODOS los
				-- ítems terminaban en el almacén. Sin saber el "reason" real
				-- de cada fallo (not_found/no_space/move_failed/...) es
				-- imposible saber si el contador miente o si de verdad se
				-- estaban reintentando (via GS_TransferQueue) hasta acabar
				-- bien pero mostrando solo el resumen del primer intento.
				GlobalStorageSiK.Debug.log("Deposit", "depositFromContainer item failed", string.format(
					"fullType=%s reason=%s movedSoFar=%d totalCandidates=%d",
					tostring(candidate.getFullType and candidate:getFullType() or "?"),
					tostring(reason), summary.moved, #candidates
				))
			end
		end
	end

	return summary
end

--- Formatea mensaje de resumen de depósito.
---@param summary table
---@return string
function GlobalStorageSiK.Deposit.formatSummaryMessage(summary)
	summary = summary or {}
	-- Solo se llama desde codigo servidor (GS_Server.lua, depositItems) para
	-- construir el mensaje de un actionResult - I18n.remote (no .text) para
	-- que cada cliente lo resuelva en su propio idioma, ver GS_I18n.lua.
	local T = GlobalStorageSiK.I18n.remote
	if summary.reason == "remote_disabled" then
		return T("IGUI_GS_DepositFailRemoteDisabled")
	end
	if summary.reason == "no_power" then
		return T("IGUI_GS_DepositFailNoPower")
	end
	if summary.reason == "no_access" then
		return T("IGUI_GS_DepositFailNoAccess")
	end
	if summary.reason == "invalid" then
		return T("IGUI_GS_DepositFailInvalid")
	end
	if summary.reason == "network_source" then
		return T("IGUI_GS_DepositFailNetworkSource")
	end
	if summary.reason == "no_space" then
		return T("IGUI_GS_DepositFailNoSpace")
	end
	if summary.reason == "no_match" then
		return T("IGUI_GS_DepositFailNoMatch")
	end
	if (summary.failed or 0) > 0 and (summary.moved or 0) == 0 then
		return T("IGUI_GS_DepositFailGeneric")
	end
	return T("IGUI_GS_DepositSummary",
		tostring(summary.moved or 0),
		tostring(summary.skipped or 0),
		tostring(summary.failed or 0)
	)
end
