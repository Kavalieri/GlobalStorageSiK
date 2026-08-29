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
	if type(row) ~= "table" or row.fullType ~= fullType then return nil end
	local effective = row.effective or row.categoryEffective
	local nativeStatus = cleanVanillaKey(row.nativeStatus)
	local vanillaKey = cleanVanillaKey(row.vanillaKey)
	if not nativeStatus or not vanillaKey or not isSafeSourceCategory(vanillaKey) then return nil end
	if effective == "native" then
		local nativePath = GlobalStorageSiK.NativeProduct.decodePath(row.nativePath)
		local encoded = GlobalStorageSiK.NativeProduct.encodePath(nativePath)
		if not encoded or row.routingIdentity ~= encoded then return nil end
		return {
			fullType = fullType, nativeStatus = nativeStatus, nativePath = encoded,
			vanillaKey = vanillaKey, effective = "native", routingIdentity = encoded,
			labelKey = encoded, colorL1 = nativePath.l1,
			categorySource = row.categorySource or sourceCategoryKind(vanillaKey),
		}
	end
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

local function buildBase(fullType, item)
	if type(fullType) ~= "string" or fullType == "" then
		return { fullType = fullType, nativeStatus = "error", vanillaKey = "Misc", effective = "vanilla", routingIdentity = "vanilla:Misc", labelKey = "Misc" }
	end
	local result = GlobalStorageSiK.NativeClassifier.classify(fullType)
	local path = result and GlobalStorageSiK.NativeProduct.normalizePath(result.primaryPath) or nil
	local fluidPath = item and GlobalStorageSiK.FluidTaxonomy.resolve(item) or nil
	if fluidPath then path = GlobalStorageSiK.NativeProduct.normalizePath(fluidPath) end
	-- El contenido de un contenedor es una variante declarada por instancia.
	-- Puede sustituir una ruta estática "containers/liquid" (o incluso una
	-- abstención del ScriptItem), por lo que no debe heredar el estado de la
	-- clasificación estática al decidir si la ruta dinámica es utilizable.
	local status = fluidPath and "classified" or nativeStatus(result, path)
	if status ~= "classified" then path = nil end
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

---@param fullType string|nil
---@param row table|nil
---@param item InventoryItem|nil
---@return table
function Resolution.resolve(fullType, row, item)
	if type(fullType) ~= "string" or fullType == "" then
		return buildBase(fullType, item)
	end
	if not item then
		local authoritative = fromAuthoritativeRow(fullType, row)
		if authoritative then return authoritative end
	end
	if item then return buildBase(fullType, item) end
	local cached = cache[fullType]
	if cached and cached.nativeStatus ~= "pending" then return cached end
	local resolved = buildBase(fullType, nil)
	if resolved.nativeStatus ~= "pending" then cache[fullType] = resolved end
	return resolved
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
