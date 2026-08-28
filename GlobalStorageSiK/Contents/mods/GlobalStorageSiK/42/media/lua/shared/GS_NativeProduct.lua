--[[
	GlobalStorageSiK - Consumo de producto de la taxonomía nativa
	Core 1.4.3-dev30

	Esta capa es el único puente entre NativeClassifier y los consumidores de
	producto. Conserva las cuatro fronteras exigidas por DEV30:
	- clasificación canónica por fullType/epoch;
	- proyección/etiquetas de presentación separadas;
	- índices inversos reutilizables;
	- compatibilidad y migración explícitas, nunca destructivas al cargar.
]]

require "GS_CatalogManager"
require "GS_NativeClassifier"
require "GS_NativeTaxonomyRegistry"
require "GS_ItemTaxonomy"

GlobalStorageSiK.NativeProduct = GlobalStorageSiK.NativeProduct or {}

local PREFIX = "native:"
-- La clasificación no depende del idioma: su cache escucha solo catalogEpoch.
-- PresentationCache sí usa el helper común, que también atiende languageEpoch.
local pathCache = {}
local viewCache = GlobalStorageSiK.CatalogManager.createEpochCache()

local metrics = {
	pathRequests = 0,
	pathCacheHits = 0,
	indexBuilds = 0,
	indexRows = 0,
	presentationBuilds = 0,
	migrationAudits = 0,
	routingContrastComparisons = 0,
	routingContrastEquivalent = 0,
	routingContrastDeltas = 0,
}

-- Acentos exclusivos de interfaces GS. La ruta completa hereda el color de
-- L1; no se exportan hooks ni se modifica el inventario vanilla en DEV30.
local L1_COLORS = {
	combat = { 0.92, 0.44, 0.41 }, food_drink = { 0.45, 0.78, 0.53 },
	tools = { 0.91, 0.70, 0.34 }, materials = { 0.68, 0.56, 0.43 },
	medicine = { 0.56, 0.78, 0.78 }, clothing_protection = { 0.71, 0.58, 0.86 },
	containers = { 0.55, 0.75, 0.95 }, knowledge_media = { 0.80, 0.66, 0.91 },
	electronics_power = { 0.94, 0.82, 0.38 }, vehicles = { 0.65, 0.72, 0.78 },
	survival_outdoors = { 0.47, 0.70, 0.43 }, home_leisure_collection = { 0.86, 0.59, 0.67 },
	other = { 0.58, 0.58, 0.58 }, globalstoragesik = { 0.88, 0.64, 0.36 },
}

---@param path string|table|nil
---@return table RGB
function GlobalStorageSiK.NativeProduct.getColor(path)
	path = GlobalStorageSiK.NativeProduct.decodePath(path)
	return path and L1_COLORS[path.l1] or { 0.54, 0.54, 0.54 }
end

local function resetMetrics()
	metrics.pathRequests = 0
	metrics.pathCacheHits = 0
	metrics.indexBuilds = 0
	metrics.indexRows = 0
	metrics.presentationBuilds = 0
	metrics.migrationAudits = 0
	metrics.routingContrastComparisons = 0
	metrics.routingContrastEquivalent = 0
	metrics.routingContrastDeltas = 0
end

local function resetCatalogState()
	for key in pairs(pathCache) do pathCache[key] = nil end
	resetMetrics()
end

GlobalStorageSiK.CatalogManager.onEpochChanged(resetCatalogState)

local function cleanSegment(value)
	if type(value) ~= "string" or value == "" or #value > 80 then return nil end
	if value:find("[^a-z0-9_]", 1) then return nil end
	return value
end

---@param path table|nil
---@return table|nil
function GlobalStorageSiK.NativeProduct.normalizePath(path)
	if type(path) ~= "table" then return nil end
	local l1 = cleanSegment(path.l1)
	local l2 = cleanSegment(path.l2)
	local l3 = cleanSegment(path.l3)
	if not l1 or not GlobalStorageSiK.NativeTaxonomyRegistry.hasL1(l1) then return nil end
	if l2 and not GlobalStorageSiK.NativeTaxonomyRegistry.hasL2(l1, l2) then return nil end
	if l3 and (not l2 or not GlobalStorageSiK.NativeTaxonomyRegistry.hasL3(l1, l2, l3)) then return nil end
	return { l1 = l1, l2 = l2, l3 = l3 }
end

---@param path table|nil
---@return string|nil
function GlobalStorageSiK.NativeProduct.encodePath(path)
	path = GlobalStorageSiK.NativeProduct.normalizePath(path)
	if not path then return nil end
	local value = PREFIX .. path.l1
	if path.l2 then value = value .. "/" .. path.l2 end
	if path.l3 then value = value .. "/" .. path.l3 end
	return value
end

---@param value string|table|nil
---@return table|nil
function GlobalStorageSiK.NativeProduct.decodePath(value)
	if type(value) == "table" then
		return GlobalStorageSiK.NativeProduct.normalizePath(value)
	end
	if type(value) ~= "string" or value:sub(1, #PREFIX) ~= PREFIX then return nil end
	local raw = value:sub(#PREFIX + 1)
	local parts = {}
	for segment in raw:gmatch("[^/]+") do
		parts[#parts + 1] = segment
	end
	if #parts < 1 or #parts > 3 then return nil end
	return GlobalStorageSiK.NativeProduct.normalizePath({ l1 = parts[1], l2 = parts[2], l3 = parts[3] })
end

---@param fullType string|nil
---@return table|nil path referencia canónica de solo lectura
function GlobalStorageSiK.NativeProduct.getPath(fullType)
	metrics.pathRequests = metrics.pathRequests + 1
	if not fullType or fullType == "" then return nil end
	local cached = pathCache[fullType]
	if cached ~= nil then
		metrics.pathCacheHits = metrics.pathCacheHits + 1
		return cached ~= false and cached or nil
	end
	local result = GlobalStorageSiK.NativeClassifier.classify(fullType)
	if not result or result.pending then return nil end
	local path = GlobalStorageSiK.NativeProduct.normalizePath(result.primaryPath)
	pathCache[fullType] = path or false
	return path
end

---@param rulePath string|table|nil
---@param itemPath string|table|nil
---@return boolean
function GlobalStorageSiK.NativeProduct.pathMatches(rulePath, itemPath)
	rulePath = GlobalStorageSiK.NativeProduct.decodePath(rulePath)
	itemPath = GlobalStorageSiK.NativeProduct.decodePath(itemPath)
	if not rulePath or not itemPath or rulePath.l1 ~= itemPath.l1 then return false end
	if rulePath.l2 and rulePath.l2 ~= itemPath.l2 then return false end
	if rulePath.l3 and rulePath.l3 ~= itemPath.l3 then return false end
	return true
end

local function humanize(key)
	if not key then return nil end
	local text = tostring(key):gsub("_", " ")
	return text:sub(1, 1):upper() .. text:sub(2)
end

local function translated(key, fallback)
	if not key then return nil end
	local value = GlobalStorageSiK.I18n and GlobalStorageSiK.I18n.text
		and GlobalStorageSiK.I18n.text(key) or nil
	if not value or value == "" or value == key then return fallback end
	return value
end

---@param path string|table|nil
---@return table view {path,key,l1Label,l2Label,l3Label,fullLabel}
function GlobalStorageSiK.NativeProduct.getView(path)
	local normalized = GlobalStorageSiK.NativeProduct.decodePath(path)
	if not normalized then return { path = nil, key = nil, fullLabel = "" } end
	local key = GlobalStorageSiK.NativeProduct.encodePath(normalized)
	local cached = viewCache[key]
	if cached then return cached end
	metrics.presentationBuilds = metrics.presentationBuilds + 1
	local l1Label = translated("IGUI_GS_NativeTax_" .. normalized.l1, humanize(normalized.l1))
	local l2Label = normalized.l2 and translated(
		"IGUI_GS_NativeTax_" .. normalized.l2, humanize(normalized.l2)) or nil
	local l3Label = normalized.l3 and translated(
		"IGUI_GS_NativeTax_" .. normalized.l3, humanize(normalized.l3)) or nil
	local labels = { l1Label }
	if l2Label then labels[#labels + 1] = l2Label end
	if l3Label then labels[#labels + 1] = l3Label end
	local view = {
		path = normalized,
		key = key,
		l1Label = l1Label,
		l2Label = l2Label,
		l3Label = l3Label,
		fullLabel = table.concat(labels, " > "),
	}
	viewCache[key] = view
	return view
end

local function addIndex(index, key, row)
	if not key then return end
	local list = index[key]
	if not list then
		list = {}
		index[key] = list
	end
	list[#list + 1] = row
end

--- Construye índices solo para un dataset ya solicitado (red o catálogo bajo
--- acción explícita). Nunca recorre ScriptManager por sí mismo.
---@param rows table[]
---@return table
function GlobalStorageSiK.NativeProduct.buildIndex(rows)
	metrics.indexBuilds = metrics.indexBuilds + 1
	local index = { rows = rows or {}, byPath = {}, byL1 = {}, byL2 = {}, byL3 = {}, byFullType = {} }
	for i = 1, #(rows or {}) do
		local row = rows[i]
		local path = GlobalStorageSiK.NativeProduct.decodePath(row.nativePath)
		if path then
			local encoded = GlobalStorageSiK.NativeProduct.encodePath(path)
			row.nativePath = encoded
			index.byFullType[row.fullType] = path
			addIndex(index.byPath, encoded, row)
			addIndex(index.byL1, path.l1, row)
			if path.l2 then addIndex(index.byL2, path.l1 .. "/" .. path.l2, row) end
			if path.l3 then addIndex(index.byL3, path.l1 .. "/" .. path.l2 .. "/" .. path.l3, row) end
		end
		metrics.indexRows = metrics.indexRows + 1
	end
	return index
end

---@param index table
---@param path string|table|nil
---@return table[]
function GlobalStorageSiK.NativeProduct.rowsForPath(index, path)
	path = GlobalStorageSiK.NativeProduct.decodePath(path)
	if not index or not path then return index and index.rows or {} end
	if path.l3 then return index.byL3[path.l1 .. "/" .. path.l2 .. "/" .. path.l3] or {} end
	if path.l2 then return index.byL2[path.l1 .. "/" .. path.l2] or {} end
	return index.byL1[path.l1] or {}
end

local function optionLess(a, b)
	local al, bl = string.lower(a.label or ""), string.lower(b.label or "")
	if al == bl then return (a.key or "") < (b.key or "") end
	return al < bl
end

--- Opciones estables desde el registro, sin barrer ScriptManager ni depender
--- del stock actual. parent vacío -> L1; native:L1 -> L2; native:L1/L2 -> L3.
---@param parent string|table|nil
---@return table[] {key,label,path}
function GlobalStorageSiK.NativeProduct.listOptions(parent)
	local tree = GlobalStorageSiK.NativeTaxonomyRegistry.getTree()
	local parentPath = GlobalStorageSiK.NativeProduct.decodePath(parent)
	local options = {}
	if parent == "" then
		return options
	end
	if parent ~= nil and not parentPath then
		return options
	end
	if not parentPath then
		for l1 in pairs(tree) do
			local path = { l1 = l1 }
			local view = GlobalStorageSiK.NativeProduct.getView(path)
			options[#options + 1] = { key = view.key, label = view.l1Label, path = path }
		end
	elseif not parentPath.l2 then
		for l2 in pairs(tree[parentPath.l1] or {}) do
			local path = { l1 = parentPath.l1, l2 = l2 }
			local view = GlobalStorageSiK.NativeProduct.getView(path)
			options[#options + 1] = { key = view.key, label = view.l2Label, path = path }
		end
	else
		local leaves = tree[parentPath.l1] and tree[parentPath.l1][parentPath.l2] or {}
		for i = 1, #leaves do
			local path = { l1 = parentPath.l1, l2 = parentPath.l2, l3 = leaves[i] }
			local view = GlobalStorageSiK.NativeProduct.getView(path)
			options[#options + 1] = { key = view.key, label = view.l3Label, path = path }
		end
	end
	table.sort(options, optionLess)
	return options
end

local function legacyAliasesForRow(row)
	local aliases = {}
	local seen = {}
	local function add(value)
		if value and value ~= "" then
			local sig = string.lower(tostring(value))
			if not seen[sig] then seen[sig] = true; aliases[#aliases + 1] = tostring(value) end
		end
	end
	add(row.category)
	add(row.subCategory)
	for key in tostring(row.gsSubKeysStr or ""):gmatch("[^|]+") do add(key) end
	local tax = GlobalStorageSiK.ItemTaxonomy.resolve(row.fullType, row)
	add(tax.mainCanon)
	add(tax.subCanon)
	add(GlobalStorageSiK.ItemTaxonomy.EXT_GROUP_PREFIX .. tostring(tax.groupKey or ""))
	if tax.groupKey and tax.subGroupKey then
		add(GlobalStorageSiK.ItemTaxonomy.SUBGROUP_PREFIX .. tax.groupKey .. "::" .. tax.subGroupKey)
	end
	return aliases
end

--- Preflight explícito: no muta owners ni recorre el catálogo por iniciativa
--- propia. Solo las aliases que convergen en una única ruta son transformables.
---@param owners table[] {id=string,rules=table[]}
---@param catalogRows table[]
---@return table plan
function GlobalStorageSiK.NativeProduct.auditMigration(owners, catalogRows)
	metrics.migrationAudits = metrics.migrationAudits + 1
	local aliasPaths = {}
	for i = 1, #(catalogRows or {}) do
		local row = catalogRows[i]
		local path = GlobalStorageSiK.NativeProduct.getPath(row.fullType)
		local encoded = GlobalStorageSiK.NativeProduct.encodePath(path)
		if encoded then
			local aliases = legacyAliasesForRow(row)
			for a = 1, #aliases do
				local sig = string.lower(aliases[a])
				aliasPaths[sig] = aliasPaths[sig] or {}
				aliasPaths[sig][encoded] = true
			end
		end
	end
	local plan = { transformable = {}, ambiguous = {}, orphan = {}, alreadyNative = 0, totalCategoryRules = 0 }
	for i = 1, #(owners or {}) do
		local owner = owners[i]
		for r = 1, #(owner.rules or {}) do
			local rule = owner.rules[r]
			local condition = rule and rule.condition
			if condition and condition.type == "category" then
				plan.totalCategoryRules = plan.totalCategoryRules + 1
				if GlobalStorageSiK.NativeProduct.decodePath(condition.nativePath or condition.value) then
					plan.alreadyNative = plan.alreadyNative + 1
				else
					local candidates = aliasPaths[string.lower(tostring(condition.value or ""))] or {}
					local count, only = 0, nil
					for encoded in pairs(candidates) do count = count + 1; only = encoded end
					local entry = { owner = owner, ownerId = owner.id, ruleIndex = r, rule = rule, nativePath = only }
					if count == 1 then plan.transformable[#plan.transformable + 1] = entry
					elseif count > 1 then plan.ambiguous[#plan.ambiguous + 1] = entry
					else plan.orphan[#plan.orphan + 1] = entry end
				end
			end
		end
	end
	return plan
end

--- Migración aditiva/idempotente sobre un plan ya auditado. Conserva value
--- original y jamás aplica entradas ambiguas/huérfanas.
---@param plan table
---@return number changed
function GlobalStorageSiK.NativeProduct.applyAuditedMigration(plan)
	local changed = 0
	for i = 1, #((plan and plan.transformable) or {}) do
		local entry = plan.transformable[i]
		local condition = entry.rule and entry.rule.condition
		if condition and not condition.nativePath and GlobalStorageSiK.NativeProduct.decodePath(entry.nativePath) then
			condition.legacyValue = condition.value
			condition.nativePath = entry.nativePath
			changed = changed + 1
		end
	end
	return changed
end

--- Registra contraste escalar sin conservar item, regla ni referencias Java.
---@param legacyTier number|nil
---@param nativeTier number|nil
---@return boolean equivalent
function GlobalStorageSiK.NativeProduct.recordRoutingContrast(legacyTier, nativeTier)
	metrics.routingContrastComparisons = metrics.routingContrastComparisons + 1
	local equivalent = legacyTier == nativeTier
	if equivalent then
		metrics.routingContrastEquivalent = metrics.routingContrastEquivalent + 1
	else
		metrics.routingContrastDeltas = metrics.routingContrastDeltas + 1
	end
	return equivalent
end

---@return table
function GlobalStorageSiK.NativeProduct.getMetrics()
	local classifier = GlobalStorageSiK.NativeClassifier.getMetrics and GlobalStorageSiK.NativeClassifier.getMetrics() or {}
	return {
		catalogEpoch = GlobalStorageSiK.CatalogManager.getEpoch(),
		languageEpoch = GlobalStorageSiK.CatalogManager.getLanguageEpoch(),
		catalogFingerprint = GlobalStorageSiK.CatalogManager.getCatalogFingerprint(),
		externalModsFingerprint = GlobalStorageSiK.CatalogManager.getExternalModsFingerprint(),
		pathRequests = metrics.pathRequests,
		pathCacheHits = metrics.pathCacheHits,
		indexBuilds = metrics.indexBuilds,
		indexRows = metrics.indexRows,
		presentationBuilds = metrics.presentationBuilds,
		migrationAudits = metrics.migrationAudits,
		routingContrastComparisons = metrics.routingContrastComparisons,
		routingContrastEquivalent = metrics.routingContrastEquivalent,
		routingContrastDeltas = metrics.routingContrastDeltas,
		classifierRequests = classifier.requests or 0,
		effectiveClassifications = classifier.effectiveClassifications or 0,
		classifierCacheHits = classifier.cacheHits or 0,
		pendingRequests = classifier.pendingRequests or 0,
		invalidRequests = classifier.invalidRequests or 0,
	}
end
