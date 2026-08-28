--[[
	GlobalStorageSiK - saneado recuperable de reglas legacy persistidas
	Core 1.4.3-dev30.1

	Las versiones antiguas pudieron persistir dimensiones tecnicas de una sola
	letra (B/F/W...) como si fueran categorias. Son inequívocamente basura, pero
	no se destruyen: se retiran de `rules` y se conservan, sin duplicados, en
	`legacyJunkRules`. El resto de condiciones desconocidas se preserva intacto.
]]

GlobalStorageSiK.RuleSanitizer = GlobalStorageSiK.RuleSanitizer or {}

local function cloneRule(rule)
	local condition = {}
	for key, value in pairs((rule and rule.condition) or {}) do condition[key] = value end
	return { op = rule and rule.op or "OR", condition = condition }
end

local function isSingleAsciiDimension(value)
	return type(value) == "string" and value:match("^%s*[A-Za-z]%s*$") ~= nil
end

---@param condition table|nil
---@return boolean
function GlobalStorageSiK.RuleSanitizer.isJunkCategoryCondition(condition)
	if type(condition) ~= "table" or condition.type ~= "category" then return false end
	-- Una ruta nativa válida declarada conserva autoridad aunque su alias legacy
	-- fuera corto. El saneado solo actúa sobre condiciones puramente legacy.
	if type(condition.nativePath) == "string" and GlobalStorageSiK.NativeProduct
		and GlobalStorageSiK.NativeProduct.decodePath
		and GlobalStorageSiK.NativeProduct.decodePath(condition.nativePath) then
		return false
	end
	local value = condition.value
	if isSingleAsciiDimension(value) then return true end
	if type(value) == "string" then
		local sep = value:find("::", 1, true)
		if sep and isSingleAsciiDimension(value:sub(sep + 2)) then return true end
	end
	return false
end

local function ruleSignature(rule)
	local condition = (rule and rule.condition) or {}
	return table.concat({
		tostring(rule and rule.op or "OR"), tostring(condition.type),
		tostring(condition.value), tostring(condition.nativePath),
		tostring(condition.legacyValue),
	}, "\31")
end

---@param owner table nodo o zona persistida
---@return table report
function GlobalStorageSiK.RuleSanitizer.sanitizeOwner(owner)
	local report = { before = 0, after = 0, quarantined = 0, unknownPreserved = 0, changed = false }
	if type(owner) ~= "table" or type(owner.rules) ~= "table" then return report end
	local active, quarantine, seen = {}, {}, {}
	for i = 1, #(owner.legacyJunkRules or {}) do
		local copy = cloneRule(owner.legacyJunkRules[i])
		local signature = ruleSignature(copy)
		if not seen[signature] then
			seen[signature] = true
			quarantine[#quarantine + 1] = copy
		end
	end
	for i = 1, #owner.rules do
		local copy = cloneRule(owner.rules[i])
		report.before = report.before + 1
		if GlobalStorageSiK.RuleSanitizer.isJunkCategoryCondition(copy.condition) then
			local signature = ruleSignature(copy)
			if not seen[signature] then
				seen[signature] = true
				quarantine[#quarantine + 1] = copy
			end
			report.quarantined = report.quarantined + 1
			report.changed = true
		else
			active[#active + 1] = copy
			if copy.condition.type == "category"
				and not copy.condition.nativePath
				and type(copy.condition.value) == "string" then
				report.unknownPreserved = report.unknownPreserved + 1
			end
		end
	end
	report.after = #active
	if report.changed then
		owner.rules = active
		owner.legacyJunkRules = quarantine
	end
	return report
end

---@param registry table|nil
---@return table report
function GlobalStorageSiK.RuleSanitizer.sanitizeRegistry(registry)
	local total = { owners = 0, changedOwners = 0, before = 0, after = 0,
		quarantined = 0, unknownPreserved = 0, changed = false }
	local function visit(owners)
		for _, owner in pairs(owners or {}) do
			total.owners = total.owners + 1
			local report = GlobalStorageSiK.RuleSanitizer.sanitizeOwner(owner)
			total.before = total.before + report.before
			total.after = total.after + report.after
			total.quarantined = total.quarantined + report.quarantined
			total.unknownPreserved = total.unknownPreserved + report.unknownPreserved
			if report.changed then total.changedOwners = total.changedOwners + 1 end
		end
	end
	visit(registry and registry.nodes)
	visit(registry and registry.zones)
	total.changed = total.changedOwners > 0
	return total
end
