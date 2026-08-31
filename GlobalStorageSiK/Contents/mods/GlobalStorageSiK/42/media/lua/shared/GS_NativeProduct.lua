--[[
	GlobalStorageSiK - Consumo de producto de la taxonomía nativa
	Core 1.4.3-dev30

	Esta capa es el único puente entre NativeClassifier y los consumidores de
	producto. Conserva las cuatro fronteras exigidas por DEV30:
	- clasificación canónica por fullType/epoch;
	- proyección/etiquetas de presentación separadas;
	- índices inversos reutilizables;
	- índices y presentación reutilizables sin depender de proveedores externos.
]]

require "GS_CatalogManager"
require "GS_NativeClassifier"
require "GS_NativeTaxonomyRegistry"

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
}

local pathTraceSamples = {}

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
	pathTraceSamples = {}
end

--- Muestra extremo-a-extremo acotada y solo bajo el sublog DETALLE de
--- Inventario. Máximo tres filas por etapa y época; no reclasifica.
---@param stage string
---@param fullType string|nil
---@param nativePath string|nil
function GlobalStorageSiK.NativeProduct.tracePathSample(stage, fullType, nativePath)
	local count = pathTraceSamples[stage] or 0
	if count >= 3 or not GlobalStorageSiK.Log or not GlobalStorageSiK.Log.detail
		or not GlobalStorageSiK.Sandbox or not GlobalStorageSiK.Sandbox.debugDetailEnabled
		or not GlobalStorageSiK.Sandbox.debugDetailEnabled("Inventory") then return end
	pathTraceSamples[stage] = count + 1
	local area = stage == "clientReceive" and "Client" or "Server"
	GlobalStorageSiK.Log.detail(area, "nativePath stage=" .. tostring(stage)
		.. " fullType=" .. tostring(fullType) .. " value=" .. tostring(nativePath)
		.. " decodable=" .. tostring(GlobalStorageSiK.NativeProduct.decodePath(nativePath) ~= nil))
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
	if not result or result.pending or result.classifierError
		or not result.primaryPath or result.primaryPath.l1 == "other" then return nil end
	local path = GlobalStorageSiK.NativeProduct.normalizePath(result.primaryPath)
	pathCache[fullType] = path or false
	GlobalStorageSiK.NativeProduct.tracePathSample("getPath", fullType,
		GlobalStorageSiK.NativeProduct.encodePath(path))
	return path
end

--- Copia defensiva del contrato de una fila sin una lista blanca frágil. La
--- UI puede conservar su snapshot sin perder `nativePath`, `locations` ni
--- futuros campos serializables añadidos por el servidor.
---@param row table|nil
---@return table|nil
function GlobalStorageSiK.NativeProduct.copyRow(row)
	if type(row) ~= "table" then return nil end
	local copy = {}
	for key, value in pairs(row) do copy[key] = value end
	return copy
end

---@param rows table|nil
---@return table
function GlobalStorageSiK.NativeProduct.copyRows(rows)
	local copy = {}
	for i = 1, #(rows or {}) do
		copy[i] = GlobalStorageSiK.NativeProduct.copyRow(rows[i])
	end
	return copy
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
	-- Una ruta nativa procede del registro SiK: no puede degradar a un token
	-- humanizado en ingles por una clave i18n ausente. `humanize` queda para
	-- contenido ajeno sin ruta registrada; aqui usamos un fallback localizado
	-- neutro mientras la auditoria de traducciones fuerza la clave faltante.
	local registeredFallback = translated("IGUI_GS_NativeTax_other", "Other")
	local l1Label = translated("IGUI_GS_NativeTax_" .. normalized.l1, registeredFallback)
	local l2Label = normalized.l2 and translated(
		"IGUI_GS_NativeTax_" .. normalized.l2, registeredFallback) or nil
	local l3Label = normalized.l3 and translated(
		"IGUI_GS_NativeTax_" .. normalized.l3, registeredFallback) or nil
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

---@param row table|nil
---@return table projection {mode,key,fullLabel,color,nativePath,vanillaKey}
function GlobalStorageSiK.NativeProduct.getRowProjection(row)
	local presentation = GlobalStorageSiK.CategoryResolution
		and GlobalStorageSiK.CategoryResolution.presentation(row and row.fullType, row, nil,
			row and row.nativePath) or nil
	local resolved = presentation and presentation.resolution or nil
	if resolved and resolved.effective == "native" then
		return { mode = "native", key = resolved.nativePath,
			fullLabel = presentation.labels.full, color = presentation.color,
			nativePath = resolved.nativePath }
	end
	if resolved and resolved.effective == "variants" then
		return { mode = "variants", key = resolved.routingIdentity,
			fullLabel = GlobalStorageSiK.CategoryResolution.label(resolved),
			color = nil, nativePath = nil, nativePaths = resolved.nativePaths }
	end
	local vanillaKey = resolved and resolved.vanillaKey or "Misc"
	return { mode = "vanilla", key = vanillaKey,
		fullLabel = resolved and GlobalStorageSiK.CategoryResolution.label(resolved) or vanillaKey,
		vanillaKey = vanillaKey, nativePath = nil }
end

---@param fullType string|nil
---@return boolean
function GlobalStorageSiK.NativeProduct.isOwnFullType(fullType)
	local path = GlobalStorageSiK.NativeProduct.getPath(fullType)
	return path and path.l1 == "globalstoragesik" or false
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
		-- El servidor puede enviar `nativePaths = {}` para una fila que tiene
		-- una ruta única en `nativePath`. En Lua una tabla vacía es truthy, por
		-- lo que el fallback con `or` dejaba esa fila fuera de los tres índices
		-- de filtros aunque la tabla ya pudiera dibujar su presentación. La
		-- fuente de verdad conserva ambas formas, pero el índice siempre recibe
		-- al menos la ruta única cuando no hay variantes.
		local sourcePaths = row.nativePaths
		if type(sourcePaths) ~= "table" or #sourcePaths == 0 then
			sourcePaths = { row.nativePath }
		end
		local seenPath, seenL1, seenL2, seenL3 = {}, {}, {}, {}
		for p = 1, #sourcePaths do
			local path = GlobalStorageSiK.NativeProduct.decodePath(sourcePaths[p])
			if path then
			local encoded = GlobalStorageSiK.NativeProduct.encodePath(path)
			if not seenPath[encoded] then addIndex(index.byPath, encoded, row); seenPath[encoded] = true end
			if not seenL1[path.l1] then addIndex(index.byL1, path.l1, row); seenL1[path.l1] = true end
			local l2 = path.l2 and (path.l1 .. "/" .. path.l2) or nil
			if l2 and not seenL2[l2] then addIndex(index.byL2, l2, row); seenL2[l2] = true end
			local l3 = path.l3 and (path.l1 .. "/" .. path.l2 .. "/" .. path.l3) or nil
			if l3 and not seenL3[l3] then addIndex(index.byL3, l3, row); seenL3[l3] = true end
			if not row.mixedVariants then
				row.nativePath = encoded
				index.byFullType[row.fullType] = path
			end
			end
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

---@return table
function GlobalStorageSiK.NativeProduct.getMetrics()
	local classifier = GlobalStorageSiK.NativeClassifier.getMetrics and GlobalStorageSiK.NativeClassifier.getMetrics() or {}
	return {
		catalogEpoch = GlobalStorageSiK.CatalogManager.getEpoch(),
		languageEpoch = GlobalStorageSiK.CatalogManager.getLanguageEpoch(),
		catalogFingerprint = GlobalStorageSiK.CatalogManager.getCatalogFingerprint(),
		pathRequests = metrics.pathRequests,
		pathCacheHits = metrics.pathCacheHits,
		indexBuilds = metrics.indexBuilds,
		indexRows = metrics.indexRows,
		presentationBuilds = metrics.presentationBuilds,
		classifierRequests = classifier.requests or 0,
		effectiveClassifications = classifier.effectiveClassifications or 0,
		classifierCacheHits = classifier.cacheHits or 0,
		pendingRequests = classifier.pendingRequests or 0,
		invalidRequests = classifier.invalidRequests or 0,
	}
end
