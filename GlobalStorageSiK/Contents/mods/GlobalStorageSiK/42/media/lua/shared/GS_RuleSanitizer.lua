--[[
	GlobalStorageSiK - saneado recuperable de reglas legacy persistidas
	Core 1.4.3-dev30.3

	Las versiones antiguas pudieron persistir dimensiones tecnicas de una sola
	letra (B/F/W...) como si fueran categorias. Son inequívocamente basura, pero
	no se destruyen: se retiran de `rules` y de la coleccion legacy `categories`
	y se conservan, sin duplicados, en `legacyJunkRules`. `legacySource` permite
	reconstruir el origen exacto. El resto de condiciones desconocidas se
	preserva intacto.
]]

require "GS_CategoryResolution"

GlobalStorageSiK.RuleSanitizer = GlobalStorageSiK.RuleSanitizer or {}

local function cloneRule(rule)
	local condition = {}
	for key, value in pairs((rule and rule.condition) or {}) do condition[key] = value end
	return {
		op = rule and rule.op or "OR",
		condition = condition,
		legacySource = rule and rule.legacySource or nil,
		legacyRuleIndex = rule and rule.legacyRuleIndex or nil,
	}
end

local function asciiDimension(value)
	if type(value) ~= "string" then return nil end
	local dimension = value:match("^%s*([A-Za-z])%s*$")
	if dimension then return string.upper(dimension) end
	local sep = value:find("::", 1, true)
	if not sep then return nil end
	dimension = value:sub(sep + 2):match("^%s*([A-Za-z])%s*$")
	return dimension and string.upper(dimension) or nil
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
	-- UI y router priorizan nativePath incluso si es una ruta corrupta. DEV30.2
	-- solo comprobaba value, por lo que { nativePath="F", value="Food" }
	-- seguia mostrando F y quedaba fuera de la migracion.
	local activeValue = condition.nativePath
	if activeValue == nil then activeValue = condition.value end
	return asciiDimension(activeValue) ~= nil
end

---@param condition table|nil
---@return string
function GlobalStorageSiK.RuleSanitizer.classifyCategoryCondition(condition)
	return GlobalStorageSiK.CategoryResolution.classifyStoredRule(condition)
end

local function ruleSignature(rule)
	local condition = (rule and rule.condition) or {}
	return table.concat({
		tostring(rule and rule.op or "OR"), tostring(condition.type),
		tostring(condition.value), tostring(condition.nativePath),
		tostring(condition.legacyValue), tostring(rule and rule.legacySource),
	}, "\31")
end

local function appendSample(report, context, rule, ruleIndex)
	if #report.samples >= 3 then return end
	local condition = rule.condition or {}
	report.samples[#report.samples + 1] = {
		ownerKind = context and context.ownerKind or "unknown",
		ownerId = context and context.ownerId or "?",
		networkId = context and context.networkId or "?",
		source = rule.legacySource or "rules",
		ruleIndex = ruleIndex or rule.legacyRuleIndex,
		op = rule.op or "OR",
		type = condition.type,
		value = condition.value,
		nativePath = condition.nativePath,
		legacyValue = condition.legacyValue,
		categoryStatus = condition.categoryStatus,
		canonical = "legacy-junk:category-dimension:"
			.. tostring(asciiDimension(condition.nativePath ~= nil and condition.nativePath or condition.value) or "?"),
	}
end

local function quarantineRule(quarantine, seen, rule)
	local signature = ruleSignature(rule)
	if seen[signature] then return end
	seen[signature] = true
	quarantine[#quarantine + 1] = rule
end

---@param owner table nodo o zona persistida
---@return table report
function GlobalStorageSiK.RuleSanitizer.sanitizeOwner(owner, context)
	local report = { before = 0, after = 0, rulesBefore = 0, rulesAfter = 0,
		categoriesBefore = 0, categoriesAfter = 0, quarantined = 0,
		unknownPreserved = 0, deprecatedExternal = 0, changed = false, rulesChanged = false,
		categoriesChanged = false, samples = {} }
	if type(owner) ~= "table" then return report end
	local sourceRules = type(owner.rules) == "table" and owner.rules or {}
	local sourceCategories = type(owner.categories) == "table" and owner.categories or {}
	local active, quarantine, seen = {}, {}, {}
	for i = 1, #(owner.legacyJunkRules or {}) do
		local copy = cloneRule(owner.legacyJunkRules[i])
		quarantineRule(quarantine, seen, copy)
	end
	for i = 1, #sourceRules do
		local rawRule = sourceRules[i]
		if type(rawRule) ~= "table" or type(rawRule.condition) ~= "table" then
			report.rulesBefore = report.rulesBefore + 1
			report.before = report.before + 1
			report.unknownPreserved = report.unknownPreserved + 1
			active[#active + 1] = rawRule
		else
			local copy = cloneRule(rawRule)
			copy.legacySource = copy.legacySource or "rules"
			copy.legacyRuleIndex = copy.legacyRuleIndex or i
			report.rulesBefore = report.rulesBefore + 1
			report.before = report.before + 1
			if GlobalStorageSiK.RuleSanitizer.isJunkCategoryCondition(copy.condition) then
				quarantineRule(quarantine, seen, copy)
				appendSample(report, context, copy, i)
				report.quarantined = report.quarantined + 1
				report.changed = true
				report.rulesChanged = true
			else
				copy.legacySource = rawRule.legacySource
				if copy.condition.type == "category" then
					local status = GlobalStorageSiK.RuleSanitizer.classifyCategoryCondition(copy.condition)
					if copy.condition.categoryStatus ~= status then
						copy.condition.categoryStatus = status
						report.changed = true
						report.rulesChanged = true
					end
					if status == "DEPRECATED_EXTERNAL" then report.deprecatedExternal = report.deprecatedExternal + 1 end
				end
				active[#active + 1] = copy
				if copy.condition.type == "category"
					and not copy.condition.nativePath
					and type(copy.condition.value) == "string" then
					report.unknownPreserved = report.unknownPreserved + 1
				end
			end
		end
	end
	report.rulesAfter = #active
	local activeCategories = {}
	for i = 1, #sourceCategories do
		local value = sourceCategories[i]
		report.categoriesBefore = report.categoriesBefore + 1
		report.before = report.before + 1
		local synthetic = {
			op = "OR",
			condition = { type = "category", value = value },
			legacySource = "categories",
			legacyRuleIndex = i,
		}
		if GlobalStorageSiK.RuleSanitizer.isJunkCategoryCondition(synthetic.condition) then
			quarantineRule(quarantine, seen, synthetic)
			appendSample(report, context, synthetic, i)
			report.quarantined = report.quarantined + 1
			report.changed = true
			report.categoriesChanged = true
		else
			activeCategories[#activeCategories + 1] = value
		end
	end
	report.categoriesAfter = #activeCategories
	report.after = report.rulesAfter + report.categoriesAfter
	if report.changed then
		if report.rulesChanged then owner.rules = active end
		if report.categoriesChanged then owner.categories = activeCategories end
		owner.legacyJunkRules = quarantine
	end
	return report
end

---@param registry table|nil
---@param networkId string|nil
---@return table report
function GlobalStorageSiK.RuleSanitizer.inspectRegistry(registry, networkId)
	local total = { owners = 0, matches = 0, samples = {} }
	local function visit(owners, ownerKind)
		for ownerId, owner in pairs(owners or {}) do
			local ownerNetworkId = owner.networkId
			if ownerKind == "node" then
				local zone = registry and registry.zones and registry.zones[owner.zoneId]
				ownerNetworkId = zone and zone.networkId or ownerNetworkId
			end
			if networkId == nil or ownerNetworkId == networkId then
				total.owners = total.owners + 1
				for i = 1, #(owner.rules or {}) do
					local rule = owner.rules[i]
					if type(rule) == "table"
						and GlobalStorageSiK.RuleSanitizer.isJunkCategoryCondition(rule.condition) then
						total.matches = total.matches + 1
						appendSample(total, {
							ownerKind = ownerKind, ownerId = owner.id or ownerId,
							networkId = ownerNetworkId,
						}, rule, i)
					end
				end
				for i = 1, #(owner.categories or {}) do
					local synthetic = {
						op = "OR",
						condition = { type = "category", value = owner.categories[i] },
						legacySource = "categories", legacyRuleIndex = i,
					}
					if GlobalStorageSiK.RuleSanitizer.isJunkCategoryCondition(synthetic.condition) then
						total.matches = total.matches + 1
						appendSample(total, {
							ownerKind = ownerKind, ownerId = owner.id or ownerId,
							networkId = ownerNetworkId,
						}, synthetic, i)
					end
				end
			end
		end
	end
	visit(registry and registry.nodes, "node")
	visit(registry and registry.zones, "zone")
	return total
end

---@param registry table|nil
---@return table report
function GlobalStorageSiK.RuleSanitizer.sanitizeRegistry(registry, networkId)
	local total = { owners = 0, changedOwners = 0, before = 0, after = 0,
		rulesBefore = 0, rulesAfter = 0, categoriesBefore = 0, categoriesAfter = 0,
		quarantined = 0, unknownPreserved = 0, changed = false, samples = {} }
	local function visit(owners, ownerKind)
		for ownerId, owner in pairs(owners or {}) do
			local ownerNetworkId = owner.networkId
			if ownerKind == "node" then
				local zone = registry and registry.zones and registry.zones[owner.zoneId]
				ownerNetworkId = zone and zone.networkId or ownerNetworkId
			end
			if networkId == nil or ownerNetworkId == networkId then
			total.owners = total.owners + 1
			local report = GlobalStorageSiK.RuleSanitizer.sanitizeOwner(owner, {
				ownerKind = ownerKind, ownerId = owner.id or ownerId,
				networkId = ownerNetworkId,
			})
			total.before = total.before + report.before
			total.after = total.after + report.after
			total.rulesBefore = total.rulesBefore + report.rulesBefore
			total.rulesAfter = total.rulesAfter + report.rulesAfter
			total.categoriesBefore = total.categoriesBefore + report.categoriesBefore
			total.categoriesAfter = total.categoriesAfter + report.categoriesAfter
			total.quarantined = total.quarantined + report.quarantined
			total.unknownPreserved = total.unknownPreserved + report.unknownPreserved
			for i = 1, #report.samples do
				if #total.samples < 3 then total.samples[#total.samples + 1] = report.samples[i] end
			end
			if report.changed then total.changedOwners = total.changedOwners + 1 end
			end
		end
	end
	visit(registry and registry.nodes, "node")
	visit(registry and registry.zones, "zone")
	total.changed = total.changedOwners > 0
	return total
end
