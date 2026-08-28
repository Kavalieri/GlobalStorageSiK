--[[
	GlobalStorageSiK - Resolución única de categorías propias
	Core 1.4.3-dev30.5

	Contrato de producto: una ruta nativa útil gana; si el clasificador se
	abstiene, se conserva DisplayCategory del objeto/autor; sin ambos, Misc.
	Nunca deriva una categoría principal de metadata técnica de inventario.
]]

require "GS_NativeProduct"
require "GS_I18n"

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

local function scriptDisplayCategory(fullType)
	local i18n = GlobalStorageSiK.I18n
	local scriptItem = i18n and i18n.getScriptItem and i18n.getScriptItem(fullType) or nil
	if not scriptItem or not scriptItem.getDisplayCategory then return nil end
	local value = cleanVanillaKey(safeCall(function() return scriptItem:getDisplayCategory() end))
	return value and VANILLA_KEYS[value] and value or nil
end

local function itemDisplayCategory(item)
	if not item or not item.getDisplayCategory then return nil end
	local value = cleanVanillaKey(safeCall(function() return item:getDisplayCategory() end))
	return value and VANILLA_KEYS[value] and value or nil
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

local function buildBase(fullType, item, row)
	if type(fullType) ~= "string" or fullType == "" then
		return { fullType = fullType, nativeStatus = "error", vanillaKey = "Misc", effective = "vanilla", routingIdentity = "vanilla:Misc", labelKey = "Misc" }
	end
	local result = GlobalStorageSiK.NativeClassifier.classify(fullType)
	local path = result and GlobalStorageSiK.NativeProduct.normalizePath(result.primaryPath) or nil
	local status = nativeStatus(result, path)
	if status ~= "classified" then path = nil end
	local vanillaKey = itemDisplayCategory(item) or scriptDisplayCategory(fullType) or "Misc"
	if path then
		local encoded = GlobalStorageSiK.NativeProduct.encodePath(path)
		return {
			fullType = fullType, nativeStatus = status, nativePath = encoded,
			vanillaKey = vanillaKey, effective = "native", routingIdentity = encoded,
			labelKey = encoded, colorL1 = path.l1,
		}
	end
	return {
		fullType = fullType, nativeStatus = status, nativePath = nil,
		vanillaKey = vanillaKey, effective = "vanilla", routingIdentity = "vanilla:" .. vanillaKey,
		labelKey = vanillaKey, colorL1 = nil,
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
		return buildBase(fullType, item, row)
	end
	if item then return buildBase(fullType, item, row) end
	local cached = cache[fullType]
	if cached and cached.nativeStatus ~= "pending" then return cached end
	local resolved = buildBase(fullType, nil, row)
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
end

---@param condition table|nil
---@return string NATIVE|VANILLA|LEGACY_GS_ALIAS|DEPRECATED_EXTERNAL|TECHNICAL_RESIDUE
function Resolution.classifyStoredRule(condition)
	condition = type(condition) == "table" and condition or {}
	local nativePath = GlobalStorageSiK.NativeProduct.decodePath(condition.nativePath or condition.value)
	if nativePath then return "NATIVE" end
	local value = type(condition.value) == "string" and condition.value or ""
	if Resolution.isTechnicalResidue(condition.nativePath or value) then return "TECHNICAL_RESIDUE" end
	if value:match("^gs_[a-z0-9_]+$") then return "LEGACY_GS_ALIAS" end
	if Resolution.isVanillaKey(value) then return "VANILLA" end
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
