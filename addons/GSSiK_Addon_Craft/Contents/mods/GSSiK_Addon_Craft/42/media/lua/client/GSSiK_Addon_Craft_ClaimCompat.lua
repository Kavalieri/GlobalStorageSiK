--[[
	GSSiK Addon Craft - Adaptador de contrato claimRecipeItems
	El Core y el addon son Workshop separados y Steam puede actualizarlos en
	momentos distintos. Esta capa conserva crafteo unitario con Core antiguo y
	nunca permite iniciar un lote parcial si falta el retorno batchShortfall.
]]

require "GS_NetworkCraftSession"

GSSiK_Addon_Craft = GSSiK_Addon_Craft or {}

local legacyContractLogged = false

---@return table waitingIds
---@return number waitingCount
---@return number moved
---@return number batchShortfall
---@return boolean batchContractSupported
function GSSiK_Addon_Craft.claimRecipeItemsCompat(player, logic, items, networkId, operationId, batchCount)
	local waitingIds, waitingCount, moved, batchShortfall =
		GlobalStorageSiK.CraftSession.claimRecipeItems(
			player, logic, items, networkId, operationId, batchCount)
	local numericShortfall = tonumber(batchShortfall)
	local batchContractSupported = numericShortfall ~= nil
	if not batchContractSupported then
		-- Core anterior a CLAIM_RECIPE_CONTRACT_VERSION=2 devolvía solo tres
		-- valores. Una unidad no necesita planificación extra y es compatible.
		-- Para lotes forzamos aborto seguro: ese Core no puede acreditar que
		-- reclamó todas las unidades y arrancar produciría resultados parciales.
		local count = math.max(1, tonumber(batchCount) or 1)
		numericShortfall = count > 1 and (count - 1) or 0
		if not legacyContractLogged then
			legacyContractLogged = true
			GlobalStorageSiK.CraftSession.debugLog(
				"claimRecipeItems COMPAT Core contract="
					.. tostring(GlobalStorageSiK.CraftSession.CLAIM_RECIPE_CONTRACT_VERSION or 1)
					.. " missing batchShortfall; single craft allowed, batch blocked")
		end
	end
	return type(waitingIds) == "table" and waitingIds or {},
		tonumber(waitingCount) or 0,
		tonumber(moved) or 0,
		numericShortfall,
		batchContractSupported
end
