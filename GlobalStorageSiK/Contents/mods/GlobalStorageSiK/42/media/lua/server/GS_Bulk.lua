--[[

	GlobalStorageSiK - Depósito masivo (servidor)

	Autor: SiK

	Fecha: 2025-06-23

	Descripción: Guardar desde inventario del jugador o contenedores cercanos (maleteros, cajas).

]]



require "GS_BulkFilters"

require "GS_Transfer"

require "GS_Sandbox"

require "GS_Power"

require "GS_DepositSources"



GlobalStorageSiK.Bulk = {}



--- Deposita candidatos desde una lista de contenedores.

---@param player IsoPlayer

---@param networkId string|nil

---@param containers ItemContainer[]

---@param scope string

---@param summary table

---@param maxPerTick number

---@return table

local function depositFromContainers(player, networkId, containers, scope, summary, maxPerTick)
	local routingSession = GlobalStorageSiK.Transfer.createDepositSession(player, networkId)

	for s = 1, #(containers or {}) do

		local container = containers[s]

		local candidates = GlobalStorageSiK.BulkFilters.collectCandidates(container, player, scope)

		for c = 1, #candidates do

			if summary.processed >= maxPerTick then

				summary.reason = "limit"

				return summary

			end
			summary.processed = summary.processed + 1

			local item = candidates[c]

			if item and item:getContainer() == container then

				if not GlobalStorageSiK.DepositSources.canPlayerAccessContainer(player, container) then

					summary.skipped = summary.skipped + 1

				else

					local ok, reason = GlobalStorageSiK.Transfer.depositItem(player, item, networkId, {
						session = routingSession,
					})

					if ok then

						summary.moved = summary.moved + 1

					elseif reason == "filtered" then

						summary.skipped = summary.skipped + 1

					else

						summary.failed = summary.failed + 1

					end

				end

			end

		end

	end

	return summary

end



--- Deposita ítems según la opción elegida en el terminal.

---@param player IsoPlayer

---@param networkId string|nil

---@param sourceIndex number|nil índice 1-based en DepositSources.buildList

---@return table summary { moved, skipped, failed, reason }

function GlobalStorageSiK.Bulk.depositFromPlayer(player, networkId, sourceIndex)

	local summary = { processed = 0, moved = 0, skipped = 0, failed = 0, reason = nil }



	if not GlobalStorageSiK.Sandbox.bulkDepositEnabled() then

		summary.reason = "bulk_disabled"

		return summary

	end

	if not GlobalStorageSiK.Power.networkPowered(networkId) then

		summary.reason = "no_power"

		return summary

	end



	local entry = GlobalStorageSiK.DepositSources.resolveEntry(player, sourceIndex)

	if not entry or not entry.containers or #entry.containers == 0 then

		summary.reason = "invalid_source"

		return summary

	end



	local maxPerTick = GlobalStorageSiK.Sandbox.getMaxItemsPerBulkTick()

	local scope = entry.scope or GlobalStorageSiK.BulkFilters.SCOPE.SINGLE_BAG

	if scope == GlobalStorageSiK.BulkFilters.SCOPE.MAIN_INVENTORY then

		scope = GlobalStorageSiK.BulkFilters.SCOPE.SINGLE_BAG

	end



	return depositFromContainers(player, networkId, entry.containers, scope, summary, maxPerTick)

end
