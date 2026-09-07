--[[
        GlobalStorageSiK - compatibilidad de protocolos de rutas

        Las reglas de aceptación no son reservas globales: la misma categoría o
        ítem puede configurarse en varios destinos. El Router aplica después la
        prioridad de zona, prioridad de contenedor, afinidad y desempate estable.
        Se conserva esta fachada para mundos que aún cargan el módulo, pero no crea
        exclusiones ni rechaza una regla por existir en otro destino.
]]

require "GS_NativeProduct"
require "GS_NativeTaxonomyRegistry"

GlobalStorageSiK.RuleCoverage = {}

local function encoded(path)
	return GlobalStorageSiK.NativeProduct.encodePath(path)
end

local function addLeaf(leaves, path)
	local key = encoded(path)
	if key then
		leaves[#leaves + 1] = key
	end
end

--- Devuelve las hojas estáticas comprendidas por una ruta. Si un grupo no
--- tiene detalles registrados, el grupo mismo es su unidad mínima válida.
---@param path string|table|nil
---@return string[]
function GlobalStorageSiK.RuleCoverage.leavesForPath(path)
	local decoded = GlobalStorageSiK.NativeProduct.decodePath(path)
	if not decoded then return {} end
	if decoded.l3 then
		return { encoded(decoded) }
	end
	local tree = GlobalStorageSiK.NativeTaxonomyRegistry.getTree()
	local leaves = {}
	if decoded.l2 then
		local details = tree[decoded.l1] and tree[decoded.l1][decoded.l2] or nil
		if not details or #details == 0 then
			addLeaf(leaves, decoded)
			return leaves
		end
		for i = 1, #details do
			addLeaf(leaves, { l1 = decoded.l1, l2 = decoded.l2, l3 = details[i] })
		end
		return leaves
	end
	local groups = tree[decoded.l1] or {}
	for group, details in pairs(groups) do
		if #details == 0 then
			addLeaf(leaves, { l1 = decoded.l1, l2 = group })
		else
			for i = 1, #details do
				addLeaf(leaves, { l1 = decoded.l1, l2 = group, l3 = details[i] })
			end
		end
	end
	return leaves
end

local function isPositiveCategoryRule(rule)
	local condition = rule and rule.condition
	return rule and rule.op == "OR" and condition and condition.type == "category"
		and GlobalStorageSiK.NativeProduct.decodePath(condition.nativePath or condition.value) ~= nil
end

local function excludesLeaf(condition, leaf)
	local exclusions = condition and condition.coverageExclusions
	for i = 1, #(exclusions or {}) do
		if GlobalStorageSiK.NativeProduct.pathMatches(exclusions[i], leaf) then
			return true
		end
	end
	return false
end

local function ruleReservesLeaf(rule, leaf)
	if not isPositiveCategoryRule(rule) then return false end
	local condition = rule.condition
	local path = condition.nativePath or condition.value
	return GlobalStorageSiK.NativeProduct.pathMatches(path, leaf)
		and not excludesLeaf(condition, leaf)
end

--- Calcula qué hojas de candidatePath ya pertenecen a otros destinos del
--- mismo ámbito. La salida se puede guardar tal cual como exclusions de una
--- regla de ruta completa nueva.
---@param candidatePath string|table|nil
---@param rules table[]|nil
---@return table availability {total,available,excludedLeaves}
function GlobalStorageSiK.RuleCoverage.categoryAvailability(candidatePath, rules)
	local leaves = GlobalStorageSiK.RuleCoverage.leavesForPath(candidatePath)
	local excluded = {}
	local available = 0
	for i = 1, #leaves do
		local reserved = false
		for j = 1, #(rules or {}) do
			if ruleReservesLeaf(rules[j], leaves[i]) then
				reserved = true
				break
			end
		end
		if reserved then
			excluded[#excluded + 1] = leaves[i]
		else
			available = available + 1
		end
	end
	return { total = #leaves, available = available, excludedLeaves = excluded }
end

---@param fullType string|nil
---@param rules table[]|nil
---@return boolean
function GlobalStorageSiK.RuleCoverage.isExactItemAvailable(fullType, rules)
	return fullType ~= nil and fullType ~= ""
end

---@param rule table|nil
---@param scopeRules table[]|nil
---@return boolean ok
---@return string|nil reason
function GlobalStorageSiK.RuleCoverage.prepareNewRule(rule, scopeRules)
	local condition = rule and rule.condition
	-- Retirar los datos heredados de la antigua reserva exclusiva antes de
	-- persistir la regla. `scopeRules` se mantiene en la firma por compatibilidad
	-- con los llamadores de servidor y de transferencia de configuración.
	if condition then condition.coverageExclusions = nil end
	return true, nil
end
