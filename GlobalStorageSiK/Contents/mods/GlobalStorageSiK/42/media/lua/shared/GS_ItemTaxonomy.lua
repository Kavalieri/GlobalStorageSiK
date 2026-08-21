--[[
	GlobalStorageSiK - Taxonomía vanilla de ítems (DisplayCategory + subcategoría)
	Autor: SiK
	Fecha: 2025-06-25
	Descripción: Alinea categorías con el inventario vanilla (p. ej. Arma - Hacha, Ropa - Calzado).
	Nota: mainCategory del ítem NO es DisplayCategory; solo usar getDisplayCategory().
	Compatibilidad: isDisplayCategoryKey() acepta cualquier categoría vanilla O
	cualquier categoría con traducción IGUI_ItemCat_<key> ya cargada por CUALQUIER
	mod activo (getText() es global, no solo de este mod) - por eso las categorías
	de Extended Categories aparecen solas en nuestros desplegables sin código extra.
]]

require "GS_Subcategories"
require "GS_Sandbox"
require "GS_Log"

GlobalStorageSiK.ItemTaxonomy = {}

-- Firma de la ultima llamada a collectSubFilters registrada en debug (dedup de spam).
local _lastCollectSubFiltersSig = nil

--- DisplayCategory base del juego (excluye rarezas tipo Badger/Fox del combo de filtros).
-- NOTA: Food sí permanece como categoría general. Solo los perecederos se
-- reescriben a FoodPerishable; el resto conserva Food y actúa como fallback
-- menos específico. Accessory, Bandage, FirstAid, Gardening, Material, Weapon
-- y WeaponCrafted sí se reescriben por completo mediante GS_CategoryRewrite.
GlobalStorageSiK.ItemTaxonomy.MAIN_DISPLAY_KEYS = {
	"Ammo",
	"Appearance",
	"Bag",
	"Camping",
	"Cartography",
	"Clothing",
	"Communications",
	"Container",
	"Cooking",
	"Electronics",
	"Entertainment",
	"Explosives",
	"Fishing",
	"Food",
	"Furniture",
	"Household",
	"Instrument",
	"Junk",
	"LightSource",
	"Literature",
	"MakeUp",
	"Paint",
	"Security",
	"SkillBook",
	"Sports",
	"Tool",
	"Trapping",
	"VehicleMaintenance",
	"Water",
	"WaterContainer",
	"WeaponPart",
}

local MAIN_DISPLAY_LOOKUP = {}
for i = 1, #GlobalStorageSiK.ItemTaxonomy.MAIN_DISPLAY_KEYS do
	local key = GlobalStorageSiK.ItemTaxonomy.MAIN_DISPLAY_KEYS[i]
	MAIN_DISPLAY_LOOKUP[string.lower(key)] = key
end

--- Ejecuta función con pcall.
---@param fn function
---@return any|nil
local function safeCall(fn)
	if not fn then
		return nil
	end
	local ok, result = pcall(fn)
	if ok then
		return result
	end
	return nil
end

--- Normaliza clave interna (sin prefijos base: / Base.).
---@param value any
---@return string|nil
local function normKey(value)
	if value == nil then
		return nil
	end
	local text = tostring(value)
	if text == "" then
		return nil
	end
	text = text:gsub("^base:", "")
	text = text:gsub("^Base%.", "")
	return text
end

--- Compara claves sin distinguir mayúsculas.
---@param a string|nil
---@param b string|nil
---@return boolean
local function keysEqual(a, b)
	if not a or not b or a == "" or b == "" then
		return false
	end
	return string.lower(a) == string.lower(b)
end

--- Convierte enum SCREAMING_SNAKE o texto crudo a clave IGUI_ItemCat (FirstAid, LightSource…).
---@param raw any
---@return string|nil
function GlobalStorageSiK.ItemTaxonomy.normalizeDisplayCategoryKey(raw)
	raw = normKey(raw)
	if not raw then
		return nil
	end
	if raw:match("^[A-Z0-9_]+$") then
		local parts = {}
		for part in raw:gmatch("[^_]+") do
			if #part > 0 then
				parts[#parts + 1] = part:sub(1, 1) .. part:sub(2):lower()
			end
		end
		if #parts > 0 then
			return table.concat(parts)
		end
	end
	return raw
end

--- Indica si una clave corresponde a DisplayCategory vanilla (traducible con IGUI_ItemCat_*).
---@param key string|nil
---@return boolean
function GlobalStorageSiK.ItemTaxonomy.isDisplayCategoryKey(key)
	key = GlobalStorageSiK.ItemTaxonomy.normalizeDisplayCategoryKey(key)
	if not key then
		return false
	end
	if MAIN_DISPLAY_LOOKUP[string.lower(key)] then
		return true
	end
	if GlobalStorageSiK.I18n and GlobalStorageSiK.I18n.tryGetText then
		return GlobalStorageSiK.I18n.tryGetText("IGUI_ItemCat_" .. key) ~= nil
	end
	return false
end

--- Obtiene script de ítem.
---@param fullType string|nil
---@return any|nil
local function scriptForFullType(fullType)
	if not fullType or not getScriptManager then
		return nil
	end
	local sm = getScriptManager()
	if not sm or not sm.getItem then
		return nil
	end
	local ok, item = pcall(function()
		return sm:getItem(fullType)
	end)
	return ok and item or nil
end

-- Nota: instanceItem NO se usa en cliente para evitar NPE en Kahlua con items moddeados.
-- Ver keysForItemScript en GS_Subcategories.lua

--- Traduce clave de categoría principal (IGUI_ItemCat_*).
---@param key string|nil
---@return string
function GlobalStorageSiK.ItemTaxonomy.translateMainKey(key)
	key = GlobalStorageSiK.ItemTaxonomy.normalizeDisplayCategoryKey(key)
	if not key then
		return "—"
	end
	if GlobalStorageSiK.I18n and GlobalStorageSiK.I18n.tryGetText then
		local translated = GlobalStorageSiK.I18n.tryGetText("IGUI_ItemCat_" .. key)
		if translated then
			return translated
		end
	end
	if GlobalStorageSiK.I18n and GlobalStorageSiK.I18n.humanizeToken then
		return GlobalStorageSiK.I18n.humanizeToken(key)
	end
	return key
end

-- Prefijo de clave "virtual" para grupos de categorias extendidas (ver abajo).
-- Nunca puede coincidir con una clave de categoria real (esas son PascalCase
-- sin ":" ni espacios), asi que sirve para distinguir ambos casos donde se usa.
GlobalStorageSiK.ItemTaxonomy.EXT_GROUP_PREFIX = "__extgroup__:"

-- Prefijo de clave "virtual" de NIVEL 2 (subcategoria elegida sin bajar a la
-- hoja mas especifica, ej. "Comida > Perecedero" sin elegir el tipo) - el
-- sufijo codifica "groupKey::subGroupKey" con claves canonicas. Las etiquetas
-- traducidas se calculan solo al pintar la UI.
GlobalStorageSiK.ItemTaxonomy.SUBGROUP_PREFIX = "__subgroup__:"

-- Las reglas persistidas NUNCA deben depender del idioma. Extended Categories
-- y nuestras reescrituras usan DisplayCategory canonicas concatenadas
-- (FoodPerishableVegetables, AccessoryJewelry...), mientras que las etiquetas
-- IGUI_ItemCat_* son solo presentacion. Estos helpers construyen una ruta
-- estable de hasta 3 niveles usando exclusivamente esas claves crudas.
local WEAPON_TYPE_PREFIX = "__weapontype__:"
local FLAT_CATEGORY_ROOTS = { firearm = true, weaponmelee = true }

-- Gramática estable que usa Extended Categories para armas. No se deduce por
-- texto localizado ni partiendo CamelCase: WeaponSmallBlunt significa
-- Weapon > SmallBlunt (dos niveles), no Weapon > WeaponSmall > SmallBlunt.
-- Las mismas claves se pueden resolver aunque el ScriptItem no esté disponible
-- en el cliente, mientras que weapon*MeleeTypeKey confirma el tipo cuando sí lo
-- está. Las combinaciones conservan su categoría primaria y el arma como hoja.
local CAEC_MELEE_SUFFIX = {
	Axe = "axe",
	Blunt = "blunt",
	SmallBlunt = "smallblunt",
	LongBlade = "longblade",
	SmallBlade = "smallblade",
	Spear = "spear",
	Crafted = "crafted",
	Improvised = "crafted",
}

local CAEC_FIREARM_SUFFIX = {
	Handgun = "handgun",
	Rifle = "rifle",
	Shotgun = "shotgun",
}

-- Raíces B42 cuyo nombre canónico contiene varias palabras. Sin esta lista,
-- un separador CamelCase genérico convertiría AnimalPart en Animal, FirstAid
-- en First o ProtectiveGear en Protective. Son identidad de primer nivel, no
-- una jerarquía. Beverage/Liquid son raíces añadidas por Extended Categories.
local ATOMIC_CATEGORY_ROOTS = {
	"Accessory",
	"AlarmClock",
	"AnimalPart",
	"Beverage",
	"FireSource",
	"FirstAid",
	"Food",
	"Gardening",
	"LightSource",
	"Liquid",
	"Material",
	"Memento",
	"ProtectiveGear",
	"RecipeResource",
	"Smoking",
	"VehicleMaintenance",
	"WaterContainer",
	"Weapon",
}

-- Extended Categories solo declara tres niveles puros para estas familias
-- (además de Tool<X>OrWeapon<Y>, tratado por su gramática OrWeapon). El resto
-- de claves concatenadas son conceptos completos de Nivel 2: SoftDrink,
-- SmallBlunt, FancyBook, etc.; partir su última mayúscula inventa niveles.
local CAEC_THREE_LEVEL_PARENT = {
	FoodPerishable = true,
	ContainerWearable = true,
}

-- Excepciones vanilla cuyo orden canónico no empieza por su familia visual.
-- La identidad exacta se conserva como Nivel 2 para que el router siga
-- comparando la DisplayCategory real.
local EXACT_CATEGORY_GROUP = {
	BrokenWeapon = "Weapon",
}

--- Última defensa para claves auxiliares realmente degeneradas. Se aplica
--- después de normalizar la gramática de armas; por tanto W en un ScriptItem no
--- oculta Weapon: el tipo ya se obtuvo de WeaponSmallBlunt/WeaponCategory.
local function isSingleAsciiDimension(key)
	if not key or key == "" then return false end
	local part = tostring(key):match("^%s*(.-)%s*$") or ""
	return part:match("^[A-Za-z]$") ~= nil
end

local _canonicalRootKeys = nil
local function canonicalRootKeys()
	if _canonicalRootKeys then return _canonicalRootKeys end
	_canonicalRootKeys = {}
	for i = 1, #GlobalStorageSiK.ItemTaxonomy.MAIN_DISPLAY_KEYS do
		local key = GlobalStorageSiK.ItemTaxonomy.MAIN_DISPLAY_KEYS[i]
		_canonicalRootKeys[string.lower(key)] = key
	end
	for i = 1, #(GlobalStorageSiK.Subcategories.LIST or {}) do
		local sub = GlobalStorageSiK.Subcategories.LIST[i]
		if sub.parentCategory and sub.parentCategory ~= "" then
			_canonicalRootKeys[string.lower(sub.parentCategory)] = sub.parentCategory
		end
	end
	for i = 1, #ATOMIC_CATEGORY_ROOTS do
		local key = ATOMIC_CATEGORY_ROOTS[i]
		_canonicalRootKeys[string.lower(key)] = key
	end
	-- Firearm/WeaponMelee son familias de Nivel 1 deliberadas; sus tipos
	-- (rifle, escopeta, hacha...) cuelgan como Nivel 2.
	_canonicalRootKeys.firearm = "Firearm"
	_canonicalRootKeys.weaponmelee = "WeaponMelee"
	return _canonicalRootKeys
end

local function isCanonicalPrefix(value, prefix)
	if not value or not prefix or #prefix > #value then return false end
	if string.lower(value:sub(1, #prefix)) ~= string.lower(prefix) then return false end
	if #value == #prefix then return true end
	local boundary = value:sub(#prefix + 1, #prefix + 1)
	return boundary:match("[%u%d_]") ~= nil
end

--- Devuelve la ruta canonica de una DisplayCategory, independiente del idioma.
--- Las relaciones propias conocidas y la gramática publicada por Extended
--- Categories tienen prioridad. CamelCase solo identifica la familia raíz;
--- nunca se usa para inventar niveles intermedios. Una categoría desconocida
--- sin raíz reconocible queda plana.
---@param mainCanon string
---@param scriptItem any|nil
---@return string groupKey
---@return string|nil subGroupKey
---@return string|nil categoryLeafKey
local function canonicalHierarchy(mainCanon, scriptItem)
	if not mainCanon or mainCanon == "" then return "", nil, nil end
	local roots = canonicalRootKeys()
	local groupKey = EXACT_CATEGORY_GROUP[mainCanon]
	for _, candidate in pairs(roots) do
		if isCanonicalPrefix(mainCanon, candidate)
			and (not groupKey or #candidate > #groupKey) then
			groupKey = candidate
		end
	end
	-- Una clave desconocida se conserva plana. CamelCase no codifica por sí
	-- solo una jerarquía: SoftDrink, SmallBlade, KeyRing o AnimalPart son
	-- conceptos atómicos reales. Solo las raíces/gramáticas registradas arriba
	-- pueden crear niveles; así un mod nuevo sigue siendo filtrable por su clave
	-- exacta sin que cliente y servidor inventen relaciones distintas.
	groupKey = groupKey or mainCanon
	if EXACT_CATEGORY_GROUP[mainCanon] then
		return groupKey, mainCanon, nil
	end

	-- Categorías mixtas reales de Extended Categories:
	-- ToolCarpentryOrWeaponSmallBlunt -> Tool > ToolCarpentry > clave exacta.
	-- MaterialOrWeaponAxe             -> Material > clave exacta.
	-- Nunca inventar un cuarto nivel ni usar la W de la subcategoría vanilla.
	local comboPos = mainCanon:find("OrWeapon", 1, true)
	if comboPos then
		local primaryKey = mainCanon:sub(1, comboPos - 1)
		local weaponSuffix = mainCanon:sub(comboPos + #"OrWeapon")
		if primaryKey ~= "" and CAEC_MELEE_SUFFIX[weaponSuffix] then
			if string.lower(primaryKey) == string.lower(groupKey) then
				return groupKey, mainCanon, nil
			end
			return groupKey, primaryKey, mainCanon
		end
	end

	-- Armas puras de Extended Categories: familia -> tipo real. El helper del
	-- ScriptItem tiene prioridad; el sufijo canónico permite la misma respuesta
	-- en cliente y servidor incluso si uno de ellos no puede resolver el item.
	local groupLower = string.lower(groupKey)
	if groupLower == "weapon" then
		local suffix = mainCanon:match("^Weapon(.+)$")
		local weaponKey = GlobalStorageSiK.Subcategories.weaponMeleeTypeKey
			and GlobalStorageSiK.Subcategories.weaponMeleeTypeKey(scriptItem) or nil
		weaponKey = weaponKey or (suffix and CAEC_MELEE_SUFFIX[suffix]) or nil
		if weaponKey then
			return groupKey, WEAPON_TYPE_PREFIX .. "Weapon:" .. weaponKey, nil
		end
	elseif groupLower == "firearm" then
		local suffix = mainCanon:match("^Firearm(.+)$")
		local weaponKey = GlobalStorageSiK.Subcategories.weaponFirearmTypeKey
			and GlobalStorageSiK.Subcategories.weaponFirearmTypeKey(scriptItem) or nil
		weaponKey = weaponKey or (suffix and CAEC_FIREARM_SUFFIX[suffix]) or nil
		if weaponKey then
			return groupKey, WEAPON_TYPE_PREFIX .. "Firearm:" .. weaponKey, nil
		end
	end

	-- Familias propias cuando Extended Categories no está instalado.
	if FLAT_CATEGORY_ROOTS[string.lower(groupKey)] then
		local weaponKey = nil
		if string.lower(groupKey) == "firearm" and GlobalStorageSiK.Subcategories.weaponFirearmTypeKey then
			weaponKey = GlobalStorageSiK.Subcategories.weaponFirearmTypeKey(scriptItem)
		elseif string.lower(groupKey) == "weaponmelee" and GlobalStorageSiK.Subcategories.weaponMeleeTypeKey then
			weaponKey = GlobalStorageSiK.Subcategories.weaponMeleeTypeKey(scriptItem)
		end
		return groupKey, weaponKey and (WEAPON_TYPE_PREFIX .. groupKey .. ":" .. weaponKey) or nil, nil
	end
	if string.lower(mainCanon) == string.lower(groupKey) then
		return groupKey, nil, nil
	end

	local subGroupKey = nil
	for i = 1, #(GlobalStorageSiK.Subcategories.LIST or {}) do
		local sub = GlobalStorageSiK.Subcategories.LIST[i]
		if sub.override and sub.parentCategory
			and string.lower(sub.parentCategory) == string.lower(groupKey)
			and isCanonicalPrefix(mainCanon, sub.override)
			and (string.lower(mainCanon) == string.lower(sub.override)
				or CAEC_THREE_LEVEL_PARENT[sub.override])
			and not FLAT_CATEGORY_ROOTS[string.lower(sub.override)]
			and (not subGroupKey or #sub.override > #subGroupKey) then
			subGroupKey = sub.override
		end
	end

	-- Los únicos padres de tres niveles adicionales publicados hoy por EC. Las
	-- relaciones GS registradas arriba (FoodPerishable, AccessoryJewelry, etc.)
	-- siguen siendo la primera fuente y cubren también el modo sin EC.
	if not subGroupKey then
		for parentKey in pairs(CAEC_THREE_LEVEL_PARENT) do
			if isCanonicalPrefix(mainCanon, parentKey) then
				subGroupKey = parentKey
				break
			end
		end
	end
	-- Cualquier otra clave concatenada representa UN concepto completo de
	-- Nivel 2. Su etiqueta puede contener varias palabras, pero eso no crea más
	-- niveles. Es la diferencia entre Beverage > Soft Drink (correcto) y el
	-- antiguo Beverage > Soft > Drink (inventado).
	if not subGroupKey then subGroupKey = mainCanon end
	local leafKey = string.lower(subGroupKey) ~= string.lower(mainCanon) and mainCanon or nil
	return groupKey, subGroupKey, leafKey
end

--- Etiqueta localizada para una clave canonica. El recorte del padre es solo
--- cosmetico; aunque un idioma/mod use otro separador, la identidad guardada
--- y el matching siguen siendo las claves crudas.
---@param key string|nil
---@param parentKey string|nil
---@return string
function GlobalStorageSiK.ItemTaxonomy.hierarchyLabel(key, parentKey)
	if not key or key == "" then return "" end
	if key:sub(1, #WEAPON_TYPE_PREFIX) == WEAPON_TYPE_PREFIX then
		local rest = key:sub(#WEAPON_TYPE_PREFIX + 1)
		local sep = rest:find(":", 1, true)
		local family = sep and rest:sub(1, sep - 1) or ""
		local typeKey = sep and rest:sub(sep + 1) or rest
		if family == "Firearm" and GlobalStorageSiK.Subcategories.weaponFirearmTypeLabel then
			return GlobalStorageSiK.Subcategories.weaponFirearmTypeLabel(typeKey)
		elseif (family == "Weapon" or family == "WeaponMelee")
			and GlobalStorageSiK.Subcategories.weaponMeleeTypeLabel then
			return GlobalStorageSiK.Subcategories.weaponMeleeTypeLabel(typeKey)
		end
		return typeKey
	end
	for i = 1, #(GlobalStorageSiK.Subcategories.LIST or {}) do
		local sub = GlobalStorageSiK.Subcategories.LIST[i]
		if sub.override and string.lower(sub.override) == string.lower(key) then
			return GlobalStorageSiK.Subcategories.label(sub.key)
		end
	end
	local label = GlobalStorageSiK.ItemTaxonomy.translateMainKey(key)
	if parentKey and parentKey ~= "" then
		local parentLabel = GlobalStorageSiK.ItemTaxonomy.translateMainKey(parentKey)
		local separators = { " - ", ", ", " / ", " > " }
		for i = 1, #separators do
			local prefix = parentLabel .. separators[i]
			if label:sub(1, #prefix) == prefix then
				return label:sub(#prefix + 1)
			end
		end
		-- Algunos packs usan separadores distintos entre el padre y la hoja.
		-- Es solo presentacion: como ultimo recurso mostrar el segmento final.
		for i = 1, #separators do
			local separator = separators[i]
			local from = 1
			local last = nil
			while true do
				local pos = label:find(separator, from, true)
				if not pos then break end
				last = pos
				from = pos + #separator
			end
			if last then return label:sub(last + #separator) end
		end
	end
	return label
end

--- Intenta partir la etiqueta traducida de una categoria NO vanilla en
--- "grupo - especifico" (convencion que usan mods de categorias extendidas,
--- p.ej. Extended Categories: "Cocina - Copa", "Accessory - Arms"). Las
--- categorias vanilla NUNCA se reinterpretan asi, solo las que no estan en
--- MAIN_DISPLAY_KEYS - por eso necesita la clave cruda, no solo la etiqueta.
---@param mainCanon string|nil
---@param mainLabel string|nil
---@return string|nil groupLabel
---@return string|nil leafLabel
function GlobalStorageSiK.ItemTaxonomy.splitExtendedCategoryLabel(mainCanon, mainLabel)
	if not mainCanon or mainCanon == "" then return nil, nil end
	if MAIN_DISPLAY_LOOKUP[string.lower(mainCanon)] then
		return nil, nil
	end
	if not mainLabel or mainLabel == "" then return nil, nil end
	local group, leaf = mainLabel:match("^(.-)%s+%-%s+(.+)$")
	if group and leaf and group ~= "" and leaf ~= "" then
		return group, leaf
	end
	return nil, nil
end

-- Cache de groupLabelForRawKey (ver mas abajo) - claves crudas conocidas
-- (Material, Food, Accessory...) son un conjunto pequeño y estable durante
-- toda la sesion, no hace falta recalcular en cada llamada.
local _groupLabelCache = {}

--- Devuelve el groupLabel (misma fuente unica que resolve()) de una clave
--- cruda de DisplayCategory ya conocida (p.ej. "Material", el parentCategory
--- declarado en GS_Subcategories.lua) - SIN necesitar un item concreto.
--- Usado para comparar "a que familia pertenece esta subcategoria gs_*" con
--- el groupLabel real de un item, en vez de comparar texto crudo contra
--- texto traducido (lo que rompia en cualquier idioma que no fuera ingles).
---@param rawKey string
---@return string
function GlobalStorageSiK.ItemTaxonomy.groupLabelForRawKey(rawKey)
	if not rawKey or rawKey == "" then return "" end
	local cached = _groupLabelCache[rawKey]
	if cached then return cached end
	local label = GlobalStorageSiK.ItemTaxonomy.translateMainKey(rawKey)
	local group = GlobalStorageSiK.ItemTaxonomy.splitExtendedCategoryLabel(rawKey, label)
	local result = group or label
	_groupLabelCache[rawKey] = result
	return result
end

--- Traduce subcategoría (perk, BodyLocation…).
---@param key string|nil
---@param mainKey string|nil
---@param scriptItem any|nil
---@return string|nil
function GlobalStorageSiK.ItemTaxonomy.translateSubKey(key, mainKey, scriptItem)
	if scriptItem and scriptItem.getBodyLocation then
		local bodyLoc = safeCall(function()
			return scriptItem:getBodyLocation()
		end)
		if bodyLoc and bodyLoc.getTranslationName then
			local bodyLabel = safeCall(function()
				return bodyLoc:getTranslationName()
			end)
			if bodyLabel and bodyLabel ~= "" then
				return bodyLabel
			end
		end
	end

	key = normKey(key)
	if not key or keysEqual(key, mainKey) then
		return nil
	end
	if GlobalStorageSiK.ItemTaxonomy.isDisplayCategoryKey(key) then
		return nil
	end

	if GlobalStorageSiK.I18n and GlobalStorageSiK.I18n.tryGetText then
		local prefixes = {
			"IGUI_perks_",
			"IGUI_WeaponCategory_",
			"IGUI_BodyLocation_",
			"IGUI_ItemBodyLocation_",
			"IGUI_ClothingBodyLocation_",
			"IGUI_Clothing_",
		}
		for i = 1, #prefixes do
			local translated = GlobalStorageSiK.I18n.tryGetText(prefixes[i] .. key)
			if translated then
				return translated
			end
		end
	end
	if GlobalStorageSiK.I18n and GlobalStorageSiK.I18n.humanizeToken then
		return GlobalStorageSiK.I18n.humanizeToken(key)
	end
	return key
end

--- Lee categoría principal (solo DisplayCategory; nunca mainCategory).
---@param item any|nil
---@param scriptItem any|nil
---@param fallback string|nil
---@return string|nil
function GlobalStorageSiK.ItemTaxonomy.readMainKey(item, scriptItem, fallback)
	local raw = nil
	if item and item.getDisplayCategory then
		raw = safeCall(function()
			return item:getDisplayCategory()
		end)
	end
	if (not raw or raw == "") and scriptItem and scriptItem.getDisplayCategory then
		raw = safeCall(function()
			return scriptItem:getDisplayCategory()
		end)
	end
	if (not raw or raw == "") and GlobalStorageSiK.ItemTaxonomy.isDisplayCategoryKey(fallback) then
		raw = fallback
	end
	local normalized = GlobalStorageSiK.ItemTaxonomy.normalizeDisplayCategoryKey(raw)
	-- B/F/W procedentes de metadata técnica no son DisplayCategory utilizables.
	-- Las categorías reales de armas/comida se resuelven por su clave completa o
	-- por nuestras reescrituras base, nunca por estos códigos de tipo.
	if isSingleAsciiDimension(normalized) then return nil end
	return normalized
end

--- Lee subcategoría semántica (BodyLocation; no Categories/getCategory).
---@param item any|nil
---@param scriptItem any|nil
---@param mainKey string|nil
---@param fallback string|nil
---@return string|nil
function GlobalStorageSiK.ItemTaxonomy.readSubKey(item, scriptItem, mainKey, fallback)
	if scriptItem and scriptItem.getBodyLocation then
		local bodyLoc = safeCall(function()
			return scriptItem:getBodyLocation()
		end)
		if bodyLoc then
			-- getBodyLocation() devuelve un string plano en B42 (verificado con
			-- JewelrySlotTrace: subCanon salia siempre vacio porque este bloque
			-- exigia un objeto con metodo .getId que nunca existe). tostring()
			-- directo es el mismo patron que ya usa GS_Subcategories.lua
			-- (bodyLocationLower), que si funciona.
			local bodyKey = normKey(tostring(bodyLoc))
			if bodyKey and not keysEqual(bodyKey, mainKey) then
				return bodyKey
			end
		end
	end

	local fb = normKey(fallback)
	-- Compatibilidad con snapshots antiguos: conservar BodyLocation/perk reales,
	-- pero descartar B/F/W. InventoryItem:getCategory() en B42 expone esos
	-- códigos de tipo y nunca fue una dimensión taxonómica válida.
	if fb and not isSingleAsciiDimension(fb)
		and not keysEqual(fb, mainKey)
		and not GlobalStorageSiK.ItemTaxonomy.isDisplayCategoryKey(fb) then
		return fb
	end
	return nil
end

--- Calcula la "familia" de variantes de un fullType: mismo item base con un
--- sufijo numerico (Base.Crisps, Crisps2, Crisps3... = mismos stats, distinto
--- sabor/color/icono). Es un patron oficial y muy extendido en PZ para
--- reskins/sabores del mismo item base — pero NO esta declarado en ningun
--- campo del script, asi que lo detectamos por convencion de nombre.
--- Para evitar falsos positivos (nombres que casualmente acaban en digito,
--- p.ej. calibres de arma), solo se agrupa si el nombre base sin sufijo
--- TAMBIEN existe como item real en el ScriptManager; si no, se devuelve el
--- fullType tal cual (sin agrupar).
--- OJO: agrupar por nombre traducido NO sirve como alternativa — se
--- comprobo que en ingles "Crisps/Crisps2/Crisps3/Crisps4" tienen nombres de
--- sabor DISTINTOS ("Chips - Plain/Barbecue/Salt & Vinegar/..."), solo el
--- texto ES generico los iguala a todos como "Patatas fritas de bolsa".
---@param fullType string|nil
---@return string
function GlobalStorageSiK.ItemTaxonomy.getVariantFamilyKey(fullType)
	if not fullType then
		return fullType
	end
	local mod, name = fullType:match("^([^%.]+)%.(.+)$")
	if not mod or not name then
		return fullType
	end
	local base = name:match("^(.-)%d+$")
	if not base or base == "" then
		return fullType
	end
	local baseFullType = mod .. "." .. base
	if scriptForFullType(baseFullType) then
		return baseFullType
	end
	return fullType
end

--- Resuelve taxonomía de un ítem (claves + etiquetas localizadas).
---@param fullType string|nil
---@param row table|nil
---@return table { mainKey: string, subKey: string, mainLabel: string, subLabel: string, fullLabel: string }
function GlobalStorageSiK.ItemTaxonomy.resolve(fullType, row)
	row = row or {}
	local scriptItem = scriptForFullType(fullType)

	local mainCanon = GlobalStorageSiK.ItemTaxonomy.readMainKey(nil, scriptItem, row.category) or ""
	-- DIAGNOSTICO DIRIGIDO (2026-08-21, reportado con Better Sorting activo:
	-- fila "Caja de madera" con columna Categoria totalmente vacia, sin
	-- ningun texto ni siquiera "-"). mainCanon="" es la unica via conocida a
	-- una columna vacia (translateMainKey(nil) devuelve "-", no vacio, asi
	-- que si el jugador ve blanco de verdad, mainCanon es "" antes de llegar
	-- ahi). Traza dirigida en vez de adivinar mas la causa raiz sin datos.
	if mainCanon == "" and GlobalStorageSiK.Sandbox.debugCategoryEnabled("CompatCategories") then
		GlobalStorageSiK.Log.debug("CompatCategories", "resolve | mainCanon vacio fullType=" .. tostring(fullType)
			.. " row.category=" .. tostring(row.category) .. " hasScriptItem=" .. tostring(scriptItem ~= nil))
	end
	local subCanon = GlobalStorageSiK.ItemTaxonomy.readSubKey(nil, scriptItem, mainCanon, row.subCategory) or ""
	local mainLabel = GlobalStorageSiK.ItemTaxonomy.translateMainKey(mainCanon ~= "" and mainCanon or nil)
	local subLabel = GlobalStorageSiK.ItemTaxonomy.translateSubKey(subCanon ~= "" and subCanon or nil, mainCanon, scriptItem) or ""

	-- Subcategorías GS (gs_*) — obtiene valores cacheados desde servidor (ItemSnapshot).
	-- Nunca instancia items en cliente (evita NPE en Kahlua).
	-- IMPORTANTE: se lee de gsSubKeysStr (string "|"-separado), NO de
	-- row.gsSubKeys (array anidado) — confirmado con NetTrace que ese array,
	-- al ir 3 niveles anidado dentro del payload de red (items[] -> row ->
	-- gsSubKeys[]), se pierde en la transmision y siempre llega nil/vacio al
	-- cliente, aunque el servidor lo calcule bien. El string plano si sobrevive.
	local gsSubKeys = {}
	if row.gsSubKeysStr and row.gsSubKeysStr ~= "" then
		for key in string.gmatch(row.gsSubKeysStr, "[^|]+") do
			gsSubKeys[#gsSubKeys + 1] = key
		end
	elseif row.gsSubKeys then
		gsSubKeys = row.gsSubKeys
	end

	-- La etiqueta completa mostrada al jugador (columna "Categoria" del
	-- Almacen/Contenedores) debe reflejar la subcategoria GS (gs_food_cold,
	-- etc.) cuando exista — antes solo se contemplaba la subcategoria VANILLA
	-- (perk/BodyLocation), asi que un item con subcategoria GS pero sin
	-- subcategoria vanilla (caso normal: comida) mostraba solo "Comida" sin
	-- rastro de "Perecedero"/"No perecedero" en ningun sitio del Almacen.
	-- Hueco de joyeria "amigable" (collar/anillo/muñeca/pendiente/nariz). Se
	-- calcula a partir de subCanon (BodyLocation ya resuelto arriba, con su
	-- propio fallback a row.subCategory - el mismo dato que ya se muestra
	-- correctamente en la columna "Categoria"), SIN exigir que mainCanon sea
	-- exactamente "AccessoryJewelry": esa comprobacion fallaba en la practica
	-- (Extended Categories, u otras variantes, puede no usar ese texto exacto)
	-- y estos huecos de BodyLocation (dedo/muñeca/collar/oreja/nariz) son de
	-- joyeria por construccion en el propio juego - no hace falta adivinar
	-- la categoria por su nombre para saber que lo son.
	-- CALCULADO ANTES de fullLabel (ver mas abajo): la columna "Categoria" debe
	-- mostrar el hueco TRADUCIDO ("Joyeria - Anillo"), no el BodyLocation crudo
	-- ("Left_RingFinger") que subLabel devolvia sin traducir.
	local jewelrySlotKey, jewelrySlotLabel = nil, nil
	if subCanon ~= "" and GlobalStorageSiK.Subcategories and GlobalStorageSiK.Subcategories.jewelrySlotBucket then
		local slot = GlobalStorageSiK.Subcategories.jewelrySlotBucket(string.lower(subCanon))
		if slot then
			jewelrySlotKey = slot
			jewelrySlotLabel = GlobalStorageSiK.Subcategories.jewelrySlotLabel(slot)
		end
	end

	local gsSubLabel = ""
	if #gsSubKeys > 0 and GlobalStorageSiK.Subcategories and GlobalStorageSiK.Subcategories.label then
		gsSubLabel = GlobalStorageSiK.Subcategories.label(gsSubKeys[1]) or ""
	end
	-- fullLabel YA NO se construye aqui - se rehace mas abajo, DESPUES de
	-- calcular groupLabel/subGroupLabel/leafLabel, para usar SIEMPRE el mismo
	-- separador " - " en los 3 niveles. Antes mezclaba " - " [EC] con " / "
	-- [subcategoria propia], dando resultados inconsistentes como "Complemento
	-- - Joyeria / Anillo" frente a "Comida - Perecedero - Queso" - feedback
	-- directo del jugador tras probar en MP.

	-- Se conservan estos campos legacy para tooltips/compatibilidad visual, pero
	-- ya NO gobiernan la identidad ni el matching: partir texto traducido hacia
	-- que cliente ES y servidor EN generasen reglas incompatibles.
	local extGroupLabel, extLeafLabel = GlobalStorageSiK.ItemTaxonomy.splitExtendedCategoryLabel(mainCanon, mainLabel)

	-- FUENTE UNICA DE VERDAD: claves canonicas independientes del idioma.
	-- Funciona tanto con nuestras reescrituras basicas como con las categorias
	-- concatenadas de Extended Categories.
	local groupKey, subGroupKey, categoryLeafKey = canonicalHierarchy(mainCanon, scriptItem)
	local groupLabel = GlobalStorageSiK.ItemTaxonomy.hierarchyLabel(groupKey, nil)
	local subGroupLabel = subGroupKey and GlobalStorageSiK.ItemTaxonomy.hierarchyLabel(subGroupKey, groupKey) or nil
	local categoryLeafLabel = categoryLeafKey
		and GlobalStorageSiK.ItemTaxonomy.hierarchyLabel(categoryLeafKey, subGroupKey or groupKey) or nil

	-- Nivel 3 final: prioridad hueco de joyeria (agrupado, mas util que el
	-- BodyLocation crudo) > tercer segmento con guion (EC) > subcategoria
	-- vanilla directa (subLabel: BodyLocation/perk, YA traducida - esto es
	-- lo que hace que Ropa funcione igual que Joyeria, por hueco corporal,
	-- SIN tabla nueva: subLabel ya existe y ya esta bien traducida hoy, solo
	-- se expone aqui como nivel 3 en vez de ir solo dentro de fullLabel).
	local gsLeafLabel = gsSubLabel ~= "" and gsSubLabel or nil
	local isWeaponTypeSubgroup = subGroupKey
		and subGroupKey:sub(1, #WEAPON_TYPE_PREFIX) == WEAPON_TYPE_PREFIX
	if isWeaponTypeSubgroup then
		gsLeafLabel = nil
	end
	if subGroupKey and #gsSubKeys > 0 and GlobalStorageSiK.Subcategories.get then
		local gsDef = GlobalStorageSiK.Subcategories.get(gsSubKeys[1])
		if gsDef and gsDef.override and string.lower(gsDef.override) == string.lower(subGroupKey) then
			gsLeafLabel = nil
		end
	end
	-- Una ruta normalizada de arma ya consumió toda la semántica disponible en
	-- su Nivel 2. La subcategoría vanilla (W/Swinging/etc.) es metadata del motor,
	-- no un tercer nivel de organización y no debe reaparecer en ningún idioma.
	local rawSubLeafLabel = not isWeaponTypeSubgroup and (subLabel ~= "" and subLabel or nil) or nil
	if isSingleAsciiDimension(subCanon) or (rawSubLeafLabel and rawSubLeafLabel:match("^[A-Za-z]$")) then
		rawSubLeafLabel = nil
	end
	if categoryLeafKey and isSingleAsciiDimension(categoryLeafKey) then
		categoryLeafLabel = nil
	end
	local leafLabel = jewelrySlotLabel or categoryLeafLabel or rawSubLeafLabel or gsLeafLabel

	-- fullLabel (columna "Categoria"): SIEMPRE los mismos 3 niveles con el
	-- MISMO separador " - ", sin mezclar con " / " en ningun caso - fuente
	-- unica con collectMainFilters/collectSubFilters/collectLeafFilters y los
	-- tooltips, solo aplanada a una linea para la columna/busqueda.
	local fullLabelParts = {}
	if groupLabel ~= "" then
		fullLabelParts[#fullLabelParts + 1] = groupLabel
	elseif mainLabel ~= "" then
		fullLabelParts[#fullLabelParts + 1] = mainLabel
	end
	if subGroupLabel and subGroupLabel ~= "" then
		fullLabelParts[#fullLabelParts + 1] = subGroupLabel
	end
	if leafLabel and leafLabel ~= "" then
		fullLabelParts[#fullLabelParts + 1] = leafLabel
	end
	local fullLabel = table.concat(fullLabelParts, " - ")

	return {
		mainKey   = mainCanon ~= "" and string.lower(mainCanon) or "",
		subKey    = subCanon ~= "" and string.lower(subCanon) or "",
		gsSubKeys = gsSubKeys,
		mainCanon = mainCanon,
		subCanon  = subCanon,
		mainLabel = mainLabel,
		subLabel  = subLabel,
		fullLabel = fullLabel,
		extGroupLabel = extGroupLabel,
		extLeafLabel  = extLeafLabel,
		groupLabel = groupLabel,
		subGroupLabel = subGroupLabel,
		leafLabel = leafLabel,
		groupKey = groupKey,
		subGroupKey = subGroupKey,
		categoryLeafKey = categoryLeafKey,
		hyphenLeafLabel = categoryLeafLabel,
		jewelrySlotKey   = jewelrySlotKey,
		jewelrySlotLabel = jewelrySlotLabel,
	}
end

--- Construye una identidad semantica estable para afinidad de contenedor.
--- Usa exclusivamente claves canonicas (nunca etiquetas traducidas), por lo
--- que cliente ES, servidor EN y Extended Categories producen la misma ruta.
--- La hoja mas especifica disponible distingue, por ejemplo, revistas de
--- receta, comida perecedera por tipo y huecos de joyeria; si una familia no
--- tiene mas detalle, su Nivel 1 sigue siendo una afinidad valida.
---@param tax table|nil Resultado de ItemTaxonomy.resolve
---@return string|nil
function GlobalStorageSiK.ItemTaxonomy.affinityKeyFromResolved(tax)
	if not tax then return nil end
	local parts = {}
	local seen = {}
	local function add(value)
		if value == nil then return end
		value = tostring(value)
		if value == "" or isSingleAsciiDimension(value) then return end
		local normalized = string.lower(value)
		if seen[normalized] then return end
		seen[normalized] = true
		parts[#parts + 1] = normalized
	end

	add(tax.groupKey or tax.mainCanon)
	add(tax.subGroupKey)
	add(tax.categoryLeafKey)
	add(tax.jewelrySlotKey)

	-- Las reescrituras basicas (sin Extended Categories) viven en gsSubKeys.
	-- Solo completan la ruta cuando la jerarquia canonica no expuso ya una hoja.
	if not tax.categoryLeafKey and not tax.jewelrySlotKey
		and tax.gsSubKeys and #tax.gsSubKeys > 0 then
		add(tax.gsSubKeys[1])
	end
	if #parts <= 1 and tax.subCanon and tax.subCanon ~= "" then
		add(tax.subCanon)
	end
	if #parts == 0 then return nil end
	return table.concat(parts, "::")
end

---@param fullType string|nil
---@param row table|nil
---@return string|nil
function GlobalStorageSiK.ItemTaxonomy.affinityKey(fullType, row)
	if not fullType or fullType == "" then return nil end
	return GlobalStorageSiK.ItemTaxonomy.affinityKeyFromResolved(
		GlobalStorageSiK.ItemTaxonomy.resolve(fullType, row or {}))
end

local _affinityKeyByFullType = {}

---@param item InventoryItem|nil
---@return string|nil
function GlobalStorageSiK.ItemTaxonomy.affinityKeyFromItem(item)
	if not item or not item.getFullType then return nil end
	local fullType = item:getFullType()
	local cached = _affinityKeyByFullType[fullType]
	if cached ~= nil then return cached ~= false and cached or nil end
	local mainKey, subKey = GlobalStorageSiK.ItemTaxonomy.keysFromItem(item)
	local gsSubKeys = GlobalStorageSiK.Subcategories and GlobalStorageSiK.Subcategories.keysForItem
		and GlobalStorageSiK.Subcategories.keysForItem(item) or {}
	local affinityKey = GlobalStorageSiK.ItemTaxonomy.affinityKey(fullType, {
		category = mainKey,
		subCategory = subKey,
		gsSubKeys = gsSubKeys,
	})
	_affinityKeyByFullType[fullType] = affinityKey or false
	return affinityKey
end

--- Claves desde instancia viva (escaneo servidor / cliente).
---@param item any|nil
---@return string mainKey
---@return string|nil subKey
function GlobalStorageSiK.ItemTaxonomy.keysFromItem(item)
	if not item then
		return "", nil
	end
	local scriptItem = nil
	if item.getScriptItem then
		scriptItem = safeCall(function()
			return item:getScriptItem()
		end)
	end
	local mainKey = GlobalStorageSiK.ItemTaxonomy.readMainKey(item, scriptItem, nil) or ""
	local subKey = GlobalStorageSiK.ItemTaxonomy.readSubKey(item, scriptItem, mainKey, nil)
	return mainKey, subKey
end

-- Catalogo completo (TODOS los tipos de item del juego, tenga o no el
-- jugador alguno en la red), cacheado una sola vez tras el primer uso.
-- Usado SOLO por el editor de filtros de contenedor (Nodos): a diferencia
-- del Almacen, ahi el jugador debe poder preparar un filtro de categoria/
-- subcategoria para algo que todavia no tiene (p.ej. antes de salir a
-- farmear), no solo para lo que ya esta en la red.
local _fullCatalogRows = nil
local _canonicalRuleAliasMap = nil

--- Filas sinteticas equivalentes a las de un terminalState.items, pero para
--- CADA tipo de item del ScriptManager en vez de solo los que hay en la red.
---@return table[] { fullType: string, gsSubKeysStr: string }
function GlobalStorageSiK.ItemTaxonomy.getFullCatalogRows()
	if _fullCatalogRows then return _fullCatalogRows end
	_fullCatalogRows = {}
	if not getAllItems then return _fullCatalogRows end
	local ok, items = pcall(getAllItems)
	if not ok or not items or not items.size then return _fullCatalogRows end
	local total = items:size()
	for i = 0, total - 1 do
		local si = items:get(i)
		local fn = si and safeCall(function() return si:getFullName() end)
		if fn then
			local gsKeys = {}
			if GlobalStorageSiK.Subcategories and GlobalStorageSiK.Subcategories.keysForScriptItem then
				gsKeys = GlobalStorageSiK.Subcategories.keysForScriptItem(si)
			end
			_fullCatalogRows[#_fullCatalogRows + 1] = {
				fullType = fn,
				gsSubKeysStr = #gsKeys > 0 and table.concat(gsKeys, "|") or "",
			}
		end
	end
	return _fullCatalogRows
end

-- Defensa final para snapshots antiguos o metadata defectuosa que aún contenga
-- códigos técnicos de tipo de una sola letra (B/F/W). Las rutas nuevas no los
-- producen: readSubKey() ya no consulta InventoryItem:getCategory(). Aun así,
-- nunca deben reaparecer como dimensiones configurables al leer datos viejos.
--
-- La comprobacion se limita deliberadamente a UNA letra ASCII. Una etiqueta
-- localizada de un solo caracter en chino/japones sigue siendo valida, igual
-- que cualquier clave real de Extended Categories o nuestros huecos de joyeria.
---@param key string|nil clave canonica del nivel
---@param label string|nil etiqueta localizada del nivel
---@param parentKey string|nil clave canonica del nivel padre
---@return boolean
local function isUsefulFilterDimension(key, label, parentKey)
	if not key or key == "" or not label or label == "" then return false end
	local keyPart = tostring(key):match("^%s*(.-)%s*$") or ""
	if parentKey and parentKey ~= "" and isCanonicalPrefix(keyPart, parentKey) and #keyPart > #parentKey then
		keyPart = keyPart:sub(#parentKey + 1):gsub("^[_%-%s]+", "")
	end
	local labelPart = tostring(label):match("^%s*(.-)%s*$") or ""
	if isSingleAsciiDimension(keyPart) then return false end
	if labelPart:match("^[A-Za-z]$") then return false end
	return true
end

--- Recopila categorías principales presentes en filas (solo DisplayCategory válidas).
---@param rows table[]
---@return table[] { key: string, label: string, typeCount: number }
function GlobalStorageSiK.ItemTaxonomy.collectMainFilters(rows)
	local map = {}
	local list = {}
	local EXT = GlobalStorageSiK.ItemTaxonomy.EXT_GROUP_PREFIX
	-- SIEMPRE se agrupa por tax.groupKey canonica (fuente unica, ver resolve()),
	-- nunca por la etiqueta traducida - asi una familia como
	-- "Material" aparece UNA sola vez en el desplegable principal, tenga o
	-- no algun item con clave cruda "generica" (sin subdividir) conviviendo
	-- con items de claves "cualificadas" (MaterialMetalworking, etc.) - antes
	-- cada caso tomaba una rama de codigo distinta y acababa con "key"
	-- distinta pese a mostrar el mismo texto (bug real, ver GS_TerminalUI_NodeEditor.lua
	-- historial). El key final SIEMPRE lleva el prefijo EXT_GROUP_PREFIX: ya
	-- no es "solo para grupos con guion", es EL identificador de familia -
	-- collectSubFilters/filterByMainCategory/GS_Router.lua leen ese mismo
	-- prefijo para distinguirla de una hoja exacta al persistir la regla.
	for i = 1, #rows do
		local tax = GlobalStorageSiK.ItemTaxonomy.resolve(rows[i].fullType, rows[i])
		if tax.mainKey ~= "" and GlobalStorageSiK.ItemTaxonomy.isDisplayCategoryKey(tax.mainCanon)
			and isUsefulFilterDimension(tax.groupKey, tax.groupLabel, nil) then
			local label = tax.groupLabel
			local sig = string.lower(tax.groupKey)
			local key = EXT .. tax.groupKey
			if not map[sig] then
				map[sig] = { key = key, label = label, typeCount = 0 }
				list[#list + 1] = map[sig]
			end
			map[sig].typeCount = map[sig].typeCount + 1
		end
	end
	table.sort(list, function(a, b)
		return string.lower(a.label) < string.lower(b.label)
	end)
	return list
end

-- Tope duro de lineas de log DETALLADO por fila: con el catalogo completo
-- (miles de items del juego, no solo lo que hay en la red) un log por fila
-- colgaba/crasheaba el cliente al abrir el editor de Nodos con Modo
-- depuracion activo (confirmado en partida real). Por encima de este limite
-- solo se registra la firma/resumen, nunca fila por fila. Compartido entre
-- collectSubFilters y collectLeafFilters (mismo criterio de spam/crash).
local MAX_DETAILED_LOG_ROWS = 80

--- Extrae el groupKey (Nivel 1, sin prefijo) de una clave de Nivel 1 o 2.
---@param key string
---@return string groupLower en minusculas
---@return string groupOriginal case original (para reconstruir claves de nivel 2)
local function extractGroupFromKey(key)
	local EXT = GlobalStorageSiK.ItemTaxonomy.EXT_GROUP_PREFIX
	local SUB = GlobalStorageSiK.ItemTaxonomy.SUBGROUP_PREFIX
	local rest = key
	if key:sub(1, #EXT) == EXT then
		rest = key:sub(#EXT + 1)
	elseif key:sub(1, #SUB) == SUB then
		rest = key:sub(#SUB + 1)
		local sepPos = rest:find("::", 1, true)
		if sepPos then rest = rest:sub(1, sepPos - 1) end
	end
	return string.lower(rest), rest
end

--- Recopila subcategorías de NIVEL 2 (grupo intermedio, ej. "Perecedero"),
--- restringidas a la categoria de Nivel 1 elegida. Devuelve claves con el
--- prefijo SUBGROUP_PREFIX: "elegir Nivel 2 sin bajar a Nivel 3" es un
--- filtro real y util por si mismo (acepta CUALQUIER item de ese subgrupo,
--- tenga o no Nivel 3 propio) - ver GS_Router.lua para el emparejamiento.
---@param rows table[]
---@param mainKey string|nil clave de Nivel 1 (EXT_GROUP_PREFIX..groupKey)
---@return table[] { key: string, label: string, typeCount: number }
function GlobalStorageSiK.ItemTaxonomy.collectSubFilters(rows, mainKey)
	local map = {}
	local list = {}
	local SUB = GlobalStorageSiK.ItemTaxonomy.SUBGROUP_PREFIX
	if not mainKey or mainKey == "" then
		return list
	end
	local groupLower, groupOriginal = extractGroupFromKey(mainKey)

	local debugOn = GlobalStorageSiK.Sandbox.debugMode()
	local detailOn = GlobalStorageSiK.Sandbox.debugDetailEnabled("Inventory")
	local sig = "L2|" .. groupLower .. "|" .. tostring(#rows)
	local logChanged = debugOn and sig ~= _lastCollectSubFiltersSig
	local shouldLog = logChanged and detailOn and #rows <= MAX_DETAILED_LOG_ROWS
	if logChanged then
		_lastCollectSubFiltersSig = sig
		GlobalStorageSiK.Log.debug("ItemTaxonomy", "collectSubFilters(L2) | group=" .. groupLower .. " rows=" .. tostring(#rows)
			.. (#rows > MAX_DETAILED_LOG_ROWS and " (catalogo completo, detalle por fila omitido)" or ""))
	end

	for i = 1, #rows do
		local tax = GlobalStorageSiK.ItemTaxonomy.resolve(rows[i].fullType, rows[i])
		if shouldLog then
			GlobalStorageSiK.Log.detail("ItemTaxonomy", "collectSubFilters(L2) | fullType=" .. tostring(rows[i].fullType)
				.. " groupKey=" .. tostring(tax.groupKey) .. " subGroupKey=" .. tostring(tax.subGroupKey)
				.. " groupLabel=" .. tostring(tax.groupLabel) .. " subGroupLabel=" .. tostring(tax.subGroupLabel))
		end
		if tax.groupKey and string.lower(tax.groupKey) == groupLower
			and isUsefulFilterDimension(tax.subGroupKey, tax.subGroupLabel, tax.groupKey) then
			local label = tax.subGroupLabel
			local sig2 = string.lower(tax.subGroupKey)
			local key = SUB .. groupOriginal .. "::" .. tax.subGroupKey
			if not map[sig2] then
				map[sig2] = { key = key, label = label, typeCount = 0 }
				list[#list + 1] = map[sig2]
			end
			map[sig2].typeCount = map[sig2].typeCount + 1
		end
	end
	table.sort(list, function(a, b)
		return string.lower(a.label) < string.lower(b.label)
	end)
	return list
end

--- Recopila sub-subcategorías de NIVEL 3 (hoja final: tipo de comida, hueco
--- de joyeria/ropa, o el tercer segmento con guion de un mod de categorias
--- extendidas), restringidas al Nivel 1 (y Nivel 2, si se eligio) elegidos.
--- Si subKey es "" (no se eligio Nivel 2), se listan TODAS las hojas del
--- Nivel 1 sin restringir por subgrupo - igual que collectSubFilters cuando
--- no hay Nivel 1 elegido, mismo patron.
---@param rows table[]
---@param mainKey string|nil clave de Nivel 1
---@param subKey string|nil clave de Nivel 2, o "" para no restringir
---@return table[] { key: string, label: string, typeCount: number }
function GlobalStorageSiK.ItemTaxonomy.collectLeafFilters(rows, mainKey, subKey)
	local map = {}
	local list = {}
	if not mainKey or mainKey == "" then
		return list
	end
	local groupLower = extractGroupFromKey(mainKey)

	local wantSubGroup = nil
	local SUB = GlobalStorageSiK.ItemTaxonomy.SUBGROUP_PREFIX
	if subKey and subKey ~= "" and subKey:sub(1, #SUB) == SUB then
		local rest = subKey:sub(#SUB + 1)
		local sepPos = rest:find("::", 1, true)
		if sepPos then
			wantSubGroup = string.lower(rest:sub(sepPos + 2))
		end
	end

	local debugOn = GlobalStorageSiK.Sandbox.debugMode()
	local detailOn = GlobalStorageSiK.Sandbox.debugDetailEnabled("Inventory")
	local sig = "L3|" .. groupLower .. "|" .. tostring(wantSubGroup) .. "|" .. tostring(#rows)
	local logChanged = debugOn and sig ~= _lastCollectSubFiltersSig
	local shouldLog = logChanged and detailOn and #rows <= MAX_DETAILED_LOG_ROWS
	if logChanged then
		_lastCollectSubFiltersSig = sig
		GlobalStorageSiK.Log.debug("ItemTaxonomy", "collectLeafFilters(L3) | group=" .. groupLower
			.. " subgroup=" .. tostring(wantSubGroup) .. " rows=" .. tostring(#rows)
			.. (#rows > MAX_DETAILED_LOG_ROWS and " (catalogo completo, detalle por fila omitido)" or ""))
	end

	for i = 1, #rows do
		local tax = GlobalStorageSiK.ItemTaxonomy.resolve(rows[i].fullType, rows[i])
		if shouldLog then
			GlobalStorageSiK.Log.detail("ItemTaxonomy", "collectLeafFilters(L3) | fullType=" .. tostring(rows[i].fullType)
				.. " groupLabel=" .. tostring(tax.groupLabel) .. " subGroupLabel=" .. tostring(tax.subGroupLabel)
				.. " leafLabel=" .. tostring(tax.leafLabel))
		end
		if tax.groupKey and string.lower(tax.groupKey) == groupLower and tax.leafLabel and tax.leafLabel ~= "" then
			local subOk = not wantSubGroup
				or (tax.subGroupKey and string.lower(tax.subGroupKey) == wantSubGroup)
			if subOk then
				local label = tax.leafLabel
				-- Clave REAL (nunca sintetica): joyeria/ropa por hueco usan el
				-- combo "mainCanon::subCanon" (subCanon = BodyLocation cruda,
				-- ya usada por GS_Router.lua para el hueco de joyeria - se
				-- extiende aqui al mismo combo para cualquier hueco, no solo
				-- joyeria). El tercer segmento con guion (EC) ya es unico
				-- dentro de mainCanon completo, sin combo necesario.
				local key
				if tax.jewelrySlotKey then
					key = tax.mainCanon .. "::" .. tax.jewelrySlotKey
				elseif tax.hyphenLeafLabel then
					key = tax.mainCanon
				elseif tax.subCanon and tax.subCanon ~= "" then
					key = tax.mainCanon .. "::" .. tax.subCanon
				else
					key = tax.mainCanon
				end
				local dimensionKey = tax.jewelrySlotKey or tax.categoryLeafKey or tax.subCanon or tax.mainCanon
				local dimensionParent = tax.categoryLeafKey and (tax.subGroupKey or tax.groupKey) or nil
				if isUsefulFilterDimension(dimensionKey, label, dimensionParent) then
					local sig2 = string.lower(key)
					if not map[sig2] then
						map[sig2] = { key = key, label = label, typeCount = 0 }
						list[#list + 1] = map[sig2]
					end
					map[sig2].typeCount = map[sig2].typeCount + 1
				end
			end
		end
	end
	table.sort(list, function(a, b)
		return string.lower(a.label) < string.lower(b.label)
	end)
	return list
end

--- Convierte reglas virtuales legacy que guardaban etiquetas traducidas
--- ("__subgroup__:Comida::Perecedero") a sus claves canonicas. Se ejecuta
--- en el cliente que abre el editor, donde las etiquetas antiguas siguen
--- disponibles en el mismo idioma con que se configuraron normalmente.
--- Las hojas exactas y los combos categoria::hueco (joyeria/ropa) no se tocan.
---@param rule string
---@param rows table[]
---@return string canonicalRule
function GlobalStorageSiK.ItemTaxonomy.canonicalizeFilterRule(rule, rows)
	if not rule or rule == "" then return rule end
	rows = rows or {}
	local EXT = GlobalStorageSiK.ItemTaxonomy.EXT_GROUP_PREFIX
	local SUB = GlobalStorageSiK.ItemTaxonomy.SUBGROUP_PREFIX
	if rule:sub(1, #EXT) ~= EXT and rule:sub(1, #SUB) ~= SUB then return rule end

	local aliases = rows == _fullCatalogRows and _canonicalRuleAliasMap or nil
	if not aliases then
		aliases = {}
		-- Una sola pasada por el catalogo: el intento inicial reconstruia todos
		-- los subfiltros por cada regla/nodo y multiplicaba miles de resolve().
		for i = 1, #rows do
			local tax = GlobalStorageSiK.ItemTaxonomy.resolve(rows[i].fullType, rows[i])
			if tax.groupKey and tax.groupKey ~= "" and tax.groupLabel and tax.groupLabel ~= "" then
				local mainKey = EXT .. tax.groupKey
				aliases[string.lower(mainKey)] = mainKey
				aliases[string.lower(EXT .. tax.groupLabel)] = mainKey
				if tax.subGroupKey and tax.subGroupKey ~= "" and tax.subGroupLabel and tax.subGroupLabel ~= "" then
					local subKey = SUB .. tax.groupKey .. "::" .. tax.subGroupKey
					aliases[string.lower(subKey)] = subKey
					aliases[string.lower(SUB .. tax.groupLabel .. "::" .. tax.subGroupLabel)] = subKey
				end
			end
		end
		if rows == _fullCatalogRows then _canonicalRuleAliasMap = aliases end
	end
	return aliases[string.lower(rule)] or rule
end
