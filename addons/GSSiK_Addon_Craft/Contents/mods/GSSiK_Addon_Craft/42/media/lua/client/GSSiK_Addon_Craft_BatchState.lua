--[[
	GSSiK Addon Craft - Estado de operaciones por lote
	Neat Crafting, Project Cook y el panel vanilla disparan el callback de
	completado UNA VEZ POR UNIDAD, no una vez por lote. Este helper pertenece al
	addon porque esa semantica es propia de sus paneles; Core solo recibe el fin
	de la operacion completa.
]]

GSSiK_Addon_Craft = GSSiK_Addon_Craft or {}
GSSiK_Addon_Craft.BatchState = GSSiK_Addon_Craft.BatchState or {}

local BatchState = GSSiK_Addon_Craft.BatchState

---@param panel table
---@param operationId string
---@param expected number|nil
function BatchState.begin(panel, operationId, expected)
	local count = math.floor(tonumber(expected) or 1)
	if count < 1 then count = 1 end
	panel._gsOperationId = operationId
	panel._gsBatchExpected = count
	panel._gsBatchCompleted = 0
end

---@param panel table
---@return string|nil operationId
---@return number completed
---@return number expected
---@return boolean final
function BatchState.completeUnit(panel)
	local operationId = panel and panel._gsOperationId or nil
	if not operationId then
		return nil, 0, 0, false
	end
	local expected = math.max(1, tonumber(panel._gsBatchExpected) or 1)
	local completed = math.min(expected, (tonumber(panel._gsBatchCompleted) or 0) + 1)
	panel._gsBatchCompleted = completed
	local final = completed >= expected
	if final then
		BatchState.clear(panel)
	end
	return operationId, completed, expected, final
end

---@param panel table
---@return string|nil operationId
---@return number completed
---@return number expected
function BatchState.cancel(panel)
	local operationId = panel and panel._gsOperationId or nil
	local completed = panel and tonumber(panel._gsBatchCompleted) or 0
	local expected = panel and tonumber(panel._gsBatchExpected) or 0
	BatchState.clear(panel)
	return operationId, completed or 0, expected or 0
end

---@param panel table|nil
function BatchState.clear(panel)
	if not panel then return end
	panel._gsOperationId = nil
	panel._gsBatchExpected = nil
	panel._gsBatchCompleted = nil
end

return BatchState
