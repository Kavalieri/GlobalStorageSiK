--[[
	GlobalStorageSiK - cobertura exclusiva de protocolos de rutas

	Las reservas se calculan sobre hojas nativas, nunca comparando textos. Una
	ruta completa puede conservarse cuando algunas de sus ramas ya pertenecen a
	otro destino: la regla nueva guarda esas ramas como exclusiones explícitas.
	AND/NOT no se convierten aquí en reservas simples: su conjunto efectivo
	depende de condiciones adicionales y no debe ocultar una categoría entera.
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
	if not fullType or fullType == "" then return false end
	for i = 1, #(rules or {}) do
		local rule = rules[i]
		local condition = rule and rule.condition
		if rule and rule.op == "OR" and condition and condition.type == "item"
			and condition.itemType == fullType then
			return false
		end
	end
	return true
end

---@param rule table|nil
---@param scopeRules table[]|nil
---@return boolean ok
---@return string|nil reason
function GlobalStorageSiK.RuleCoverage.prepareNewRule(rule, scopeRules)
	local condition = rule and rule.condition
	if not rule or rule.op ~= "OR" or not condition then return true, nil end
	if condition.type == "item" then
		return GlobalStorageSiK.RuleCoverage.isExactItemAvailable(condition.itemType, scopeRules), "item_reserved"
	end
	if condition.type ~= "category" then return true, nil end
	local path = condition.nativePath or condition.value
	if not GlobalStorageSiK.NativeProduct.decodePath(path) then return true, nil end
	local availability = GlobalStorageSiK.RuleCoverage.categoryAvailability(path, scopeRules)
	if availability.total == 0 or availability.available == 0 then
		return false, "category_reserved"
	end
	condition.coverageExclusions = availability.excludedLeaves
	return true, nil
end
