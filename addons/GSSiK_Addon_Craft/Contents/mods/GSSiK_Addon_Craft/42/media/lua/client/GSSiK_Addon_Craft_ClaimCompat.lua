-- GSSiK Addon Craft - adaptador local de la respuesta pública WorkSession.

local API = require "GSSiK_API_Client"
require "GSSiK_Addon_Craft_Log"

local Session = API.WorkSession

GSSiK_Addon_Craft = GSSiK_Addon_Craft or {}

---@return table waitingIds
---@return number waitingCount
---@return number moved
---@return number batchShortfall
---@return boolean batchContractSupported
function GSSiK_Addon_Craft.claimRecipeItemsCompat(player, logic, items, operationId, batchCount)
	local ok, code, result = Session.claimRecipeInputs(
		operationId, player, logic, items, batchCount)
	if ok ~= true or type(result) ~= "table" then
		GSSiK_Addon_Craft.Log.debug("Operations",
			"claimRecipeInputs rejected code=" .. tostring(code))
		return {}, 0, 0, math.max(1, tonumber(batchCount) or 1), false
	end
	return result.waitingIds or {}, result.waitingCount or 0,
		result.claimedCount or 0, result.batchShortfall or 0,
		result.batchSupported == true
end
