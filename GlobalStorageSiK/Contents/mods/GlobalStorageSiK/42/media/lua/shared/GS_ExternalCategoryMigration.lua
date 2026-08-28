--[[
	GlobalStorageSiK - migración recuperable de vocabulario externo persistido
	Core 1.4.3-dev30.4

	Esta migración es deliberadamente distinta del saneador de dimensiones
	basura. Una clave de proveedor externo puede tener semántica válida incluso
	cuando el mod que la traducía ya no está cargado. Solo se sustituye si el
	conjunto efectivo de fullTypes coincide exactamente con una ruta nativa.
]]

require "GS_NativeProduct"

GlobalStorageSiK.ExternalCategoryMigration = GlobalStorageSiK.ExternalCategoryMigration or {}

local Migration = GlobalStorageSiK.ExternalCategoryMigration
Migration.VERSION = 1

local MAPPINGS = {
	FoodSpice = {
		key = "FoodSpice",
		targetPath = "native:food_drink/ingredient/spice",
		aliases = { "FoodSpice", "__subgroup__:Food::FoodSpice" },
		fullTypes = { "Base.Pepper", "Base.Salt", "Base.SeasoningSalt" },
	},
}

local aliasLookup = {}
for _, mapping in pairs(MAPPINGS) do
	for i = 1, #mapping.aliases do
		aliasLookup[string.lower(mapping.aliases[i])] = mapping
	end
	local expected = {}
	for i = 1, #mapping.fullTypes do expected[string.lower(mapping.fullTypes[i])] = true end
	mapping.expectedFullTypes = expected
end

local function activeValue(condition)
	if type(condition) ~= "table" then return nil end
	return condition.nativePath or condition.value
end

local function mappingFor(value)
	if type(value) ~= "string" then return nil end
	return aliasLookup[string.lower(value)]
end

local function isExternalSyntax(value)
	return type(value) == "string" and value:sub(1, 13) == "__subgroup__:"
end

local function addSample(report, ownerKind, ownerId, source, index, value, mapping)
	if #report.samples >= 3 then return end
	report.samples[#report.samples + 1] = {
		ownerKind = ownerKind, ownerId = ownerId, source = source, index = index,
		previousValue = value, mapping = mapping and mapping.key or "unknown",
		targetPath = mapping and mapping.targetPath or nil,
	}
end

local function addOwnerOperations(report, owner, ownerKind, ownerId, ownerNetworkId, networkId)
	if networkId ~= nil and ownerNetworkId ~= networkId then return end
	report.owners = report.owners + 1
	for i = 1, #(owner.rules or {}) do
		local rule = owner.rules[i]
		local condition = rule and rule.condition
		local value = activeValue(condition)
		local mapping = mappingFor(value)
		if mapping then
			report.matches = report.matches + 1
			report.rules = report.rules + 1
			report.operations[#report.operations + 1] = {
				owner = owner, ownerKind = ownerKind, ownerId = ownerId, source = "rules", index = i,
				rule = rule, condition = condition, previousValue = value, mapping = mapping,
			}
			addSample(report, ownerKind, ownerId, "rules", i, value, mapping)
		elseif isExternalSyntax(value) then
			report.unknownPreserved = report.unknownPreserved + 1
			addSample(report, ownerKind, ownerId, "rules", i, value, nil)
		end
	end
	for i = 1, #(owner.categories or {}) do
		local value = owner.categories[i]
		local mapping = mappingFor(value)
		if mapping then
			report.matches = report.matches + 1
			report.categories = report.categories + 1
			report.operations[#report.operations + 1] = {
				owner = owner, ownerKind = ownerKind, ownerId = ownerId, source = "categories", index = i,
				previousValue = value, mapping = mapping,
			}
			addSample(report, ownerKind, ownerId, "categories", i, value, mapping)
		elseif isExternalSyntax(value) then
			report.unknownPreserved = report.unknownPreserved + 1
			addSample(report, ownerKind, ownerId, "categories", i, value, nil)
		end
	end
end

local function collectCatalogFullTypes()
	if not getAllItems then return nil end
	local ok, items = pcall(getAllItems)
	if not ok or not items or not items.size or not items.get then return nil end
	local fullTypes, seen = {}, {}
	for i = 0, items:size() - 1 do
		local item = items:get(i)
		local okName, fullType = pcall(function() return item and item:getFullName() end)
		if okName and type(fullType) == "string" and fullType ~= "" then
			local sig = string.lower(fullType)
			if not seen[sig] then seen[sig] = true; fullTypes[#fullTypes + 1] = fullType end
		end
	end
	return fullTypes
end

local function auditEquivalence(report, fullTypes, resolvePath)
	if type(fullTypes) ~= "table" or type(resolvePath) ~= "function" then
		report.catalogReady = false
		return
	end
	report.catalogReady = true
	local seenExpected = {}
	for i = 1, #fullTypes do
		local fullType = fullTypes[i]
		local lower = string.lower(tostring(fullType))
		for _, mapping in pairs(MAPPINGS) do
			local expected = mapping.expectedFullTypes[lower] == true
			local actual = resolvePath(fullType)
			if expected then seenExpected[mapping.key .. "\31" .. lower] = true end
			if expected and actual ~= mapping.targetPath then
				report.missingNative = report.missingNative + 1
			elseif not expected and actual == mapping.targetPath then
				report.unexpectedNative = report.unexpectedNative + 1
			end
		end
	end
	for _, mapping in pairs(MAPPINGS) do
		for fullType in pairs(mapping.expectedFullTypes) do
			if not seenExpected[mapping.key .. "\31" .. fullType] then
				report.missingCatalog = report.missingCatalog + 1
			end
		end
	end
end

--- Audita las equivalencias y localiza todas las mutaciones potenciales sin escribir.
---@param registry table|nil
---@param networkId string|nil
---@param fullTypes table[]|nil sustituye el catálogo real en regresiones
---@param resolvePath fun(fullType:string):string|nil sustituye NativeProduct en regresiones
---@return table report
function Migration.auditRegistry(registry, networkId, fullTypes, resolvePath)
	local report = { owners = 0, matches = 0, rules = 0, categories = 0,
		unknownPreserved = 0, missingNative = 0, unexpectedNative = 0, missingCatalog = 0,
		catalogReady = false, samples = {}, operations = {} }
	local resolve = resolvePath or function(fullType)
		local product = GlobalStorageSiK.NativeProduct
		return product and product.encodePath and product.encodePath(product.getPath(fullType)) or nil
	end
	fullTypes = fullTypes or collectCatalogFullTypes()
	auditEquivalence(report, fullTypes, resolve)
	for ownerId, owner in pairs((registry and registry.zones) or {}) do
		addOwnerOperations(report, owner, "zone", owner.id or ownerId, owner.networkId, networkId)
	end
	for ownerId, owner in pairs((registry and registry.nodes) or {}) do
		local zone = registry and registry.zones and registry.zones[owner.zoneId]
		local ownerNetworkId = zone and zone.networkId or owner.networkId
		if ownerNetworkId == networkId or networkId == nil then
			-- Los nodos heredan su red de la zona; la auditoría no los muta.
			addOwnerOperations(report, owner, "node", owner.id or ownerId, ownerNetworkId, networkId)
		end
	end
	report.equivalent = report.catalogReady and report.missingNative == 0
		and report.unexpectedNative == 0 and report.missingCatalog == 0
	return report
end

local function appendHistory(owner, operation)
	local history = type(owner.externalCategoryMigrationHistory) == "table"
		and owner.externalCategoryMigrationHistory or {}
	for i = 1, #history do
		local entry = history[i]
		if entry.source == operation.source and entry.index == operation.index
			and entry.previousValue == operation.previousValue and entry.targetPath == operation.mapping.targetPath then
			return
		end
	end
	history[#history + 1] = {
		version = Migration.VERSION, mapping = operation.mapping.key, source = operation.source,
		index = operation.index, previousValue = operation.previousValue,
		previousNativePath = operation.condition and operation.condition.nativePath or nil,
		previousLegacyValue = operation.condition and operation.condition.legacyValue or nil,
		targetPath = operation.mapping.targetPath, op = operation.rule and operation.rule.op or "OR",
	}
	owner.externalCategoryMigrationHistory = history
end

--- Aplica un informe ya auditado. Si la equivalencia no es exacta, no muta nada.
---@param report table|nil
---@return table result
function Migration.applyAudit(report)
	local result = { changedOwners = 0, changedRules = 0, changedCategories = 0, changed = false }
	if not report or not report.equivalent then return result end
	local changedOwners = {}
	for i = 1, #(report.operations or {}) do
		local operation = report.operations[i]
		local owner = operation.owner
		if operation.source == "rules" and operation.condition then
			appendHistory(owner, operation)
			operation.condition.value = operation.mapping.targetPath
			operation.condition.nativePath = operation.mapping.targetPath
			operation.condition.legacyValue = nil
			operation.condition.externalCategoryMigration = operation.mapping.key
			result.changedRules = result.changedRules + 1
			changedOwners[owner] = true
		elseif operation.source == "categories" and owner.categories then
			appendHistory(owner, operation)
			owner.categories[operation.index] = operation.mapping.targetPath
			result.changedCategories = result.changedCategories + 1
			changedOwners[owner] = true
		end
	end
	for _ in pairs(changedOwners) do result.changedOwners = result.changedOwners + 1 end
	result.changed = result.changedOwners > 0
	return result
end
