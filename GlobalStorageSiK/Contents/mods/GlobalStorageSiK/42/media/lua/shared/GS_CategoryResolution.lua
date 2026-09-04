--[[
	GlobalStorageSiK - Resolución única de categorías propias
	Core 1.4.3-dev30.5.1

	Contrato de producto: una ruta nativa útil gana; si el clasificador se
	abstiene, se conserva DisplayCategory del objeto/autor; sin ambos, Misc.
	Nunca deriva una categoría principal de metadata técnica de inventario.
]]

require "GS_NativeProduct"
require "GS_I18n"
require "GS_FluidTaxonomy"

GlobalStorageSiK.CategoryResolution = GlobalStorageSiK.CategoryResolution or {}

local Resolution = GlobalStorageSiK.CategoryResolution
local cache = {}

local VANILLA_KEYS = {
	Ammo = true, Appearance = true, Bag = true, Camping = true, Cartography = true,
	Clothing = true, Communications = true, Container = true, Cooking = true,
	Electronics = true, Entertainment = true, Explosives = true, Fishing = true,
	Food = true, Furniture = true, Household = true,
	Instrument = true, Junk = true, LightSource = true, Literature = true,
	MakeUp = true, Misc = true, Paint = true,
	Security = true, SkillBook = true, Sports = true, Tool = true, Trapping = true,
	VehicleMaintenance = true, Water = true, WaterContainer = true, WeaponPart = true,
}

-- Solo equivalencias históricas que se pueden expresar sin recuperar el
-- clasificador antiguo. Los alias desconocidos se mantienen inactivos.
local LEGACY_GS_ALIASES = {
	gs_mat_metal = "native:materials/metal",
	gs_mat_leather = "native:materials/leather_hide",
	gs_mat_wood = "native:materials/wood",
	gs_weapon_firearm = "native:combat/firearm",
	gs_weapon_melee = "native:combat/melee",
	gs_med_surgery = "native:medicine/instrument/surgical",
}

local function safeCall(fn)
	local ok, value = pcall(fn)
	return ok and value or nil
end

local function cleanVanillaKey(value)
	if type(value) ~= "string" then return nil end
	value = value:gsub("^%s+", ""):gsub("%s+$", "")
	if value == "" or #value > 80 then return nil end
	if value:match("^[BFW]$") then return nil end
	return value
end

local function isTechnicalValue(value)
	value = cleanVanillaKey(value)
	if not value then return true end
	return value:match("^native:") ~= nil or value:match("^__") ~= nil
		or value:find("::", 1, true) ~= nil
end

-- DisplayCategory público de GS: sirve a inventario vanilla/otros lectores,
-- pero nunca vuelve a entrar como una categoría fuente al resolver nuestra
-- propia ruta. Evita que un valor publicado se recicle si el clasificador se
-- abstiene en una época posterior.
local function isPublishedGSKey(value)
	return type(value) == "string" and value:match("^GSSiK_[a-z0-9_]+$") ~= nil
end

local function isSafeSourceCategory(value)
	return cleanVanillaKey(value) ~= nil and not isTechnicalValue(value)
		and not isPublishedGSKey(value)
end

local function scriptDisplayCategory(fullType)
	local i18n = GlobalStorageSiK.I18n
	local scriptItem = i18n and i18n.getScriptItem and i18n.getScriptItem(fullType) or nil
	if not scriptItem or not scriptItem.getDisplayCategory then return nil end
	local value = cleanVanillaKey(safeCall(function() return scriptItem:getDisplayCategory() end))
	return value and isSafeSourceCategory(value) and value or nil
end

local function itemDisplayCategory(item)
	if not item or not item.getDisplayCategory then return nil end
	local value = cleanVanillaKey(safeCall(function() return item:getDisplayCategory() end))
	return value and isSafeSourceCategory(value) and value or nil
end

-- Los objetos recogidos del mundo no siempre conservan una identidad útil en
-- el ScriptItem. En particular, muchos muebles llegan como Moveable genérico:
-- su función real vive en las propiedades del sprite que ReadFromWorldSprite
-- dejó en la instancia. Resolverla aquí mantiene separadas dos familias que
-- vanilla también trata como clases distintas: Moveable (mueble) e
-- InventoryContainer equipable (mochila).
local function moveablePathFromItem(item)
	if not item then return nil end
	if instanceof then
		local isMoveable = safeCall(function() return instanceof(item, "Moveable") end)
		if isMoveable ~= true then return nil end
	end
	local worldSprite = item.getWorldSprite
		and safeCall(function() return item:getWorldSprite() end) or nil
	if (not worldSprite or worldSprite == "") and item.getWorldObjectSprite then
		worldSprite = safeCall(function() return item:getWorldObjectSprite() end)
	end
	if (not worldSprite or worldSprite == "") and item.getModData then
		local md = safeCall(function() return item:getModData() end)
		worldSprite = md and (md.WorldObjectSprite or md.worldObjectSprite
			or md.worldSprite or md.sprite) or nil
	end
	if not worldSprite or worldSprite == "" or not getSprite then return nil end
	local sprite = safeCall(function() return getSprite(worldSprite) end)
	local props = sprite and sprite.getProperties
		and safeCall(function() return sprite:getProperties() end) or nil
	if not props then return nil end
	local function has(name)
		return props.has and safeCall(function() return props:has(name) end) == true
	end
	local function value(name)
		return has(name) and props.get and safeCall(function() return props:get(name) end) or nil
	end
	local containerKind = string.lower(tostring(value("container") or ""))
	local applianceContainer = containerKind == "fridge" or containerKind == "freezer"
		or containerKind == "microwave" or containerKind == "stove"
		or containerKind == "oven" or containerKind == "dishwasher"
	local refrigerated = has("IsFridge") or has("Freezer")
		or containerKind:find("fridge", 1, true) ~= nil
		or containerKind:find("freezer", 1, true) ~= nil
	local isoType = string.lower(tostring(value("IsoType") or ""))
	if refrigerated or applianceContainer or isoType == "isostove" then
		return { l1 = "home_leisure_collection", l2 = "kitchen", l3 = "appliance" }
	end
	if containerKind ~= "" or has("ContainerCapacity") or has("FreezerCapacity") then
		return { l1 = "home_leisure_collection", l2 = "furnishing", l3 = "storage" }
	end
	return nil
end

Resolution.moveablePathFromItem = moveablePathFromItem

local function nativeStatus(result, path)
	if not result then return "error" end
	if result.pending then return "pending" end
	if result.classifierError then return "error" end
	if result.primaryPath and result.primaryPath.l1 == "other" then
		if result.primaryPath.l2 == "debug" then return "debug" end
		return "unclassified"
	end
	return path and "classified" or "error"
end

local function sourceCategoryKind(value)
	return VANILLA_KEYS[value] and "VANILLA" or "SOURCE_CATEGORY"
end

local function fromAuthoritativeRow(fullType, row)
	if type(row) ~= "table" or tostring(row.fullType or "") ~= tostring(fullType or "") then return nil end
	local effective = row.effective or row.categoryEffective
	local nativeStatus = cleanVanillaKey(row.nativeStatus)
	local vanillaKey = cleanVanillaKey(row.vanillaKey)
	if effective == "variants" and nativeStatus == "variants" and row.nativePath == nil
		and type(row.routingIdentity) == "string" and row.routingIdentity:match("^variants:")
		and type(row.nativePaths) == "table" and #row.nativePaths > 1 then
		return {
			fullType = fullType, nativeStatus = "variants", nativePath = nil,
			nativePaths = row.nativePaths, vanillaKey = vanillaKey,
			effective = "variants", routingIdentity = row.routingIdentity,
			labelKey = "IGUI_GS_MultipleCategories", colorL1 = nil,
			categorySource = row.categorySource,
		}
	end
	if effective == "native" then
		local nativePath = GlobalStorageSiK.NativeProduct.decodePath(row.nativePath)
		local encoded = GlobalStorageSiK.NativeProduct.encodePath(nativePath)
		if not encoded or row.routingIdentity ~= encoded then return nil end
		return {
			fullType = fullType, nativeStatus = nativeStatus or "classified", nativePath = encoded,
			vanillaKey = vanillaKey, effective = "native", routingIdentity = encoded,
			labelKey = encoded, colorL1 = nativePath.l1,
			categorySource = row.categorySource or (vanillaKey and sourceCategoryKind(vanillaKey)) or "NATIVE",
		}
	end
	if not nativeStatus or not vanillaKey or not isSafeSourceCategory(vanillaKey) then return nil end
	if effective == "vanilla" and row.nativePath == nil
		and row.routingIdentity == "vanilla:" .. vanillaKey then
		return {
			fullType = fullType, nativeStatus = nativeStatus, nativePath = nil,
			vanillaKey = vanillaKey, effective = "vanilla",
			routingIdentity = row.routingIdentity, labelKey = vanillaKey, colorL1 = nil,
			categorySource = row.categorySource or sourceCategoryKind(vanillaKey),
		}
	end
	return nil
end

local function buildBase(fullType, item, knownInstancePath)
	if type(fullType) ~= "string" or fullType == "" then
		return { fullType = fullType, nativeStatus = "error", vanillaKey = "Misc", effective = "vanilla", routingIdentity = "vanilla:Misc", labelKey = "Misc" }
	end
	local result = GlobalStorageSiK.NativeClassifier.classify(fullType)
	local path = result and GlobalStorageSiK.NativeProduct.normalizePath(result.primaryPath) or nil
	local fluidPath = knownInstancePath or (item and GlobalStorageSiK.FluidTaxonomy.resolve(item) or nil)
	local moveablePath = item and moveablePathFromItem(item) or nil
	local instancePath = fluidPath or moveablePath
	if instancePath then path = GlobalStorageSiK.NativeProduct.normalizePath(instancePath) end
	-- El contenido de un contenedor es una variante declarada por instancia.
	-- Puede sustituir una ruta estática "containers/liquid" (o incluso una
	-- abstención del ScriptItem), por lo que no debe heredar el estado de la
	-- clasificación estática al decidir si la ruta dinámica es utilizable.
	local status = instancePath and "classified" or nativeStatus(result, path)
	-- Una abstencion honesta conserva su ruta nativa visible. Caer aqui a
	-- DisplayCategory ocultaba el fullType sin clasificar bajo una categoria
	-- vanilla y hacia imposible distinguir clasificacion de compatibilidad.
	local visibleAbstention = status == "unclassified" and path
		and path.l1 == "other" and path.l2 == "unclassified_modded"
	if status ~= "classified" and not visibleAbstention then path = nil end
	local vanillaKey = itemDisplayCategory(item) or scriptDisplayCategory(fullType) or "Misc"
	local categorySource = sourceCategoryKind(vanillaKey)
	if path then
		local encoded = GlobalStorageSiK.NativeProduct.encodePath(path)
		return {
			fullType = fullType, nativeStatus = status, nativePath = encoded,
			vanillaKey = vanillaKey, effective = "native", routingIdentity = encoded,
			labelKey = encoded, colorL1 = path.l1, categorySource = categorySource,
		}
	end
	return {
		fullType = fullType, nativeStatus = status, nativePath = nil,
		vanillaKey = vanillaKey, effective = "vanilla", routingIdentity = "vanilla:" .. vanillaKey,
		labelKey = vanillaKey, colorL1 = nil, categorySource = categorySource,
	}
end

local function resetCache()
	for key in pairs(cache) do cache[key] = nil end
end

GlobalStorageSiK.CatalogManager.onEpochChanged(resetCache)

local function withCanonicalContract(resolved, row, item)
	resolved = resolved or {}
	local out = {}
	for key, value in pairs(resolved) do out[key] = value end
	local path = GlobalStorageSiK.NativeProduct.decodePath(out.nativePath)
	local fluid = item and GlobalStorageSiK.FluidTaxonomy
		and type(GlobalStorageSiK.FluidTaxonomy.inspect) == "function"
		and GlobalStorageSiK.FluidTaxonomy.inspect(item) or nil
	out.identityKey = fluid and fluid.identityKey
		or (row and (row.dynamicSignature or row.routingIdentity)) or out.routingIdentity
	out.categoryPathKeys = path and { l1 = path.l1, l2 = path.l2, l3 = path.l3 } or nil
	out.source = fluid and fluid.source or out.categorySource
	out.descriptor = fluid and fluid.descriptor or nil
	return out
end

---@param fullType string|nil
---@param row table|nil
---@param item InventoryItem|nil
---@return table
function Resolution.resolve(fullType, row, item, knownInstancePath)
	if type(fullType) ~= "string" or fullType == "" then
		return withCanonicalContract(buildBase(fullType, item), row, item)
	end
	-- Una fila del indice ya contiene la decision autoritativa del escaneo. Se
	-- consulta antes que un probe de tooltip: ese probe solo existe para que
	-- vanilla pinte el objeto y no puede sustituir la ruta final del servidor.
	local authoritative = fromAuthoritativeRow(fullType, row)
	if authoritative then return withCanonicalContract(authoritative, row, item) end
	if item then return withCanonicalContract(buildBase(fullType, item, knownInstancePath), row, item) end
	local cached = cache[fullType]
	if cached and cached.nativeStatus ~= "pending" then return withCanonicalContract(cached, row, nil) end
	local resolved = buildBase(fullType, nil)
	if resolved.nativeStatus ~= "pending" then cache[fullType] = resolved end
	return withCanonicalContract(resolved, row, nil)
end

-- Presentacion comun e inmutable para inventario, tooltip y filas SiK. La
-- resolucion sigue siendo la unica autoridad; esta fachada evita que cada
-- consumidor reconstruya etiquetas o pierda la firma dinamica de la instancia.
function Resolution.dynamicSignature(item)
	local signature = item and GlobalStorageSiK.FluidTaxonomy and GlobalStorageSiK.FluidTaxonomy.stateKey
		and GlobalStorageSiK.FluidTaxonomy.stateKey(item) or nil
	-- Los movibles pueden compartir fullType y divergir por sprite/mod-data.
	-- Esos campos forman parte de la identidad visual, nunca se guardan ni se
	-- mutan; solo evitan reutilizar una presentacion de otra instancia.
	if not signature and item and item.getWorldSprite then
		signature = item:getWorldSprite()
	end
	if not signature and item and item.getModData then
		local modData = item:getModData()
		if modData then
			signature = modData.worldSprite or modData.sprite or modData.SpriteName
		end
	end
	return signature
end

function Resolution.presentation(fullType, row, item, knownInstancePath)
	local resolved = Resolution.resolve(fullType, row, item, knownInstancePath)
	local path = resolved and GlobalStorageSiK.NativeProduct.decodePath(resolved.nativePath) or nil
	local view = path and GlobalStorageSiK.NativeProduct.getView(path) or nil
	local signature = resolved and resolved.identityKey or Resolution.dynamicSignature(item)
	return {
		resolution = resolved,
		nativePath = path,
		routingIdentity = resolved and resolved.routingIdentity or nil,
		labels = view and { l1 = view.l1Label, l2 = view.l2Label, l3 = view.l3Label,
			full = view.fullLabel } or { full = Resolution.label(resolved) },
		color = Resolution.color(resolved),
		dynamicSignature = signature,
		source = resolved and resolved.source or nil,
		descriptor = resolved and resolved.descriptor or nil,
		categoryPathKeys = resolved and resolved.categoryPathKeys or nil,
	}
end

---@param value string|nil
---@return boolean
function Resolution.isVanillaKey(value)
	value = cleanVanillaKey(value)
	return value ~= nil and VANILLA_KEYS[value] == true
end

---@param value string|nil
---@return boolean
function Resolution.isTechnicalResidue(value)
	value = type(value) == "string" and value or ""
	return value:match("^%s*[BFW]%s*$") ~= nil or value:match("::%s*[BFW]%s*$") ~= nil
		or isTechnicalValue(value)
end

---@param value string|nil
---@return boolean
function Resolution.isSafeSourceCategory(value)
	return isSafeSourceCategory(value)
end

---@param value string|nil
---@return string|nil
function Resolution.legacyAliasNativePath(value)
	return type(value) == "string" and LEGACY_GS_ALIASES[value] or nil
end

---@param condition table|nil
---@return string NATIVE|VANILLA|SOURCE_CATEGORY|LEGACY_GS_ALIAS|DEPRECATED_EXTERNAL|TECHNICAL_RESIDUE
function Resolution.classifyStoredRule(condition)
	condition = type(condition) == "table" and condition or {}
	local nativePath = GlobalStorageSiK.NativeProduct.decodePath(condition.nativePath or condition.value)
	if nativePath then return "NATIVE" end
	local value = type(condition.value) == "string" and condition.value or ""
	if Resolution.isTechnicalResidue(condition.nativePath or value) then return "TECHNICAL_RESIDUE" end
	if value:match("^gs_[a-z0-9_]+$") then return "LEGACY_GS_ALIAS" end
	if Resolution.isVanillaKey(value) then return "VANILLA" end
	if condition.categorySource == "SOURCE_CATEGORY" and isSafeSourceCategory(value) then
		return "SOURCE_CATEGORY"
	end
	return "DEPRECATED_EXTERNAL"
end

---@param resolved table|nil
---@return string
function Resolution.label(resolved)
	if resolved and resolved.effective == "native" then
		return GlobalStorageSiK.NativeProduct.getView(resolved.nativePath).fullLabel
	end
	if resolved and resolved.effective == "variants" then
		return GlobalStorageSiK.I18n.text("IGUI_GS_MultipleCategories")
	end
	local key = resolved and resolved.vanillaKey or "Misc"
	local i18n = GlobalStorageSiK.I18n
	local text = i18n and i18n.tryGetText and i18n.tryGetText("IGUI_ItemCat_" .. key) or nil
	return text or key
end

---@param resolved table|nil
---@return table|nil
function Resolution.color(resolved)
	if not resolved or resolved.effective ~= "native" then return nil end
	return GlobalStorageSiK.NativeProduct.getColor(resolved.nativePath)
end
