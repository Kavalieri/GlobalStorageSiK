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
-- NOTA (v1.2.76): Accessory, Bandage, FirstAid, Food, Gardening, Material,
-- Weapon y WeaponCrafted NO estan aqui a proposito - GS_CategoryRewrite.lua
-- reescribe TODO item de esas categorias a una de nuestras subcategorias reales
-- (ver GS_Subcategories.lua, campo "override"), asi que ningun item vivo
-- vuelve a reportar la categoria vanilla "en crudo" nunca mas. Mantenerlas
-- aqui solo crearia una opcion fantasma en el editor de contenedor que jamas
-- coincidiria con ningun item.
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
-- sufijo codifica "groupLabel::subGroupLabel" (los mismos campos de
-- resolve(), fuente unica). GS_Router.lua recalcula resolve() del item
-- candidato y compara ambas etiquetas - no es una tabla de alias, es una
-- comparacion dinamica contra el mismo campo que ya pinta la UI.
GlobalStorageSiK.ItemTaxonomy.SUBGROUP_PREFIX = "__subgroup__:"

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
	return GlobalStorageSiK.ItemTaxonomy.normalizeDisplayCategoryKey(raw)
end

--- Lee subcategoría (getCategory / BodyLocation; no Categories del script).
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

	if item and item.getCategory then
		local cat = normKey(safeCall(function()
			return item:getCategory()
		end))
		if cat and not keysEqual(cat, mainKey) and not GlobalStorageSiK.ItemTaxonomy.isDisplayCategoryKey(cat) then
			return cat
		end
	end

	local fb = normKey(fallback)
	if fb and not keysEqual(fb, mainKey) and not GlobalStorageSiK.ItemTaxonomy.isDisplayCategoryKey(fb) then
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

	-- Categorias de mods de categorias extendidas (Extended Categories y
	-- similares) codifican su propia jerarquia en el TEXTO traducido
	-- ("Cocina - Copa"), no en la clave cruda (una unica clave plana por
	-- item, "CocinaCopa"). Partimos esa etiqueta para poder ofrecerla en
	-- nuestros dos desplegables (principal/sub) igual que ya hacemos con nuestras
	-- propias subcategorias gs_* colgando de una categoria vanilla.
	local extGroupLabel, extLeafLabel = GlobalStorageSiK.ItemTaxonomy.splitExtendedCategoryLabel(mainCanon, mainLabel)

	-- FUENTE UNICA DE VERDAD para "a que familia/grupo principal pertenece
	-- este item" - usada tal cual en collectMainFilters/collectSubFilters
	-- (UI de Almacen y Nodos) Y en GS_Router.lua (emparejamiento real al
	-- depositar). Antes existian dos caminos de codigo distintos (clave
	-- cruda "plana" vs. grupo partido de un mod de categorias extendidas)
	-- que, para la MISMA familia (ej. "Material"), podian acabar en dos
	-- entradas de UI con texto identico pero "key" interna distinta -
	-- confirmado con MainFilterDupTrace en partida real con Extended
	-- Categories activo. groupLabel es simplemente "el texto de grupo si lo
	-- hay, si no, la propia etiqueta principal" - sin inventar una tabla de
	-- alias ni una lista nueva, solo reutilizando extGroupLabel/mainLabel
	-- que ya se calculaban de todos modos.
	local groupLabel = extGroupLabel or mainLabel

	-- SISTEMA DE 3 NIVELES (Categoria > Subcategoria > Sub-subcategoria).
	-- Los mods de categorias extendidas (y las nuestras, con el mismo
	-- convenio) construyen categorias compuestas por concatenacion literal
	-- ("Food" + "Perishable" + "Cheese" = "FoodPerishableCheese", traducido
	-- "Comida - Perishable - Queso" - confirmado leyendo CAEC_Food.lua real).
	-- extLeafLabel ("Perishable - Queso") puede contener a su vez OTRO guion:
	-- se parte una vez mas para obtener nivel 2 (subGroupLabel) y candidato a
	-- nivel 3 (hyphenLeafLabel). Si extLeafLabel no tiene mas guiones (ej.
	-- "Metalisteria"), pasa entero a nivel 2 y no hay nivel 3 por este camino.
	local subGroupLabel, hyphenLeafLabel = nil, nil
	if extLeafLabel and extLeafLabel ~= "" then
		local seg2, seg3 = extLeafLabel:match("^(.-)%s+%-%s+(.+)$")
		if seg2 and seg3 and seg2 ~= "" and seg3 ~= "" then
			subGroupLabel = seg2
			hyphenLeafLabel = seg3
		else
			subGroupLabel = extLeafLabel
		end
	end

	-- Sin Extended Categories, "Firearm"/"WeaponMelee" (nuestro propio Nivel 1,
	-- ver GS_Subcategories.lua/GS_CategoryRewrite.lua) se quedaban sin Nivel 2
	-- (pistola/rifle/escopeta, hacha/contundente/hoja larga/hoja corta/lanza).
	-- Fallback SOLO si EC no aporto ya subGroupLabel via su propio guion (con
	-- EC instalado, este bloque nunca se ejecuta, no pisa su resultado).
	if not subGroupLabel and scriptItem and GlobalStorageSiK.Subcategories then
		if mainCanon == "Firearm" then
			local firearmKey = GlobalStorageSiK.Subcategories.weaponFirearmTypeKey
				and GlobalStorageSiK.Subcategories.weaponFirearmTypeKey(scriptItem)
			if firearmKey then
				subGroupLabel = GlobalStorageSiK.Subcategories.weaponFirearmTypeLabel(firearmKey)
			end
		elseif mainCanon == "WeaponMelee" or mainCanon == "Weapon" or mainCanon == "WeaponCrafted" then
			local meleeKey = GlobalStorageSiK.Subcategories.weaponMeleeTypeKey
				and GlobalStorageSiK.Subcategories.weaponMeleeTypeKey(scriptItem)
			if meleeKey then
				subGroupLabel = GlobalStorageSiK.Subcategories.weaponMeleeTypeLabel(meleeKey)
			end
		end
	end

	-- Nivel 3 final: prioridad hueco de joyeria (agrupado, mas util que el
	-- BodyLocation crudo) > tercer segmento con guion (EC) > subcategoria
	-- vanilla directa (subLabel: BodyLocation/perk, YA traducida - esto es
	-- lo que hace que Ropa funcione igual que Joyeria, por hueco corporal,
	-- SIN tabla nueva: subLabel ya existe y ya esta bien traducida hoy, solo
	-- se expone aqui como nivel 3 en vez de ir solo dentro de fullLabel).
	local leafLabel = jewelrySlotLabel or hyphenLeafLabel or (subLabel ~= "" and subLabel or nil)
		or (gsSubLabel ~= "" and gsSubLabel or nil)

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
		hyphenLeafLabel = hyphenLeafLabel,
		jewelrySlotKey   = jewelrySlotKey,
		jewelrySlotLabel = jewelrySlotLabel,
	}
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

--- Recopila categorías principales presentes en filas (solo DisplayCategory válidas).
---@param rows table[]
---@return table[] { key: string, label: string, typeCount: number }
function GlobalStorageSiK.ItemTaxonomy.collectMainFilters(rows)
	local map = {}
	local list = {}
	local EXT = GlobalStorageSiK.ItemTaxonomy.EXT_GROUP_PREFIX
	-- SIEMPRE se agrupa por tax.groupLabel (fuente unica, ver resolve()),
	-- nunca por la clave cruda mainKey directamente - asi una familia como
	-- "Material" aparece UNA sola vez en el desplegable principal, tenga o
	-- no algun item con clave cruda "generica" (sin subdividir) conviviendo
	-- con items de claves "cualificadas" (MaterialMetalworking, etc.) - antes
	-- cada caso tomaba una rama de codigo distinta y acababa con "key"
	-- distinta pese a mostrar el mismo texto (bug real, ver GS_TerminalUI_NodeEditor.lua
	-- historial). El key final SIEMPRE lleva el prefijo EXT_GROUP_PREFIX: ya
	-- no es "solo para grupos con guion", es EL identificador de familia -
	-- collectSubFilters/filterByMainCategory/GS_Router.lua leen ese mismo
	-- prefijo para saber que hay que comparar por groupLabel, no por clave.
	for i = 1, #rows do
		local tax = GlobalStorageSiK.ItemTaxonomy.resolve(rows[i].fullType, rows[i])
		if tax.mainKey ~= "" and GlobalStorageSiK.ItemTaxonomy.isDisplayCategoryKey(tax.mainCanon) and tax.groupLabel ~= "" then
			local label = tax.groupLabel
			-- Dedup por firma en minusculas, pero el "key" persistido conserva
			-- el texto ORIGINAL (mayus/minus) del groupLabel - asi
			-- GS_TerminalUI_Nodes.lua puede mostrarlo tal cual sin tener que
			-- volver a traducir nada a partir de una clave ya en minusculas.
			local sig = string.lower(label)
			local key = EXT .. label
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

--- Extrae el groupLabel (Nivel 1, sin prefijo) de una clave de Nivel 1 o 2.
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
---@param mainKey string|nil clave de Nivel 1 (EXT_GROUP_PREFIX..groupLabel)
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
	local sig = "L2|" .. groupLower .. "|" .. tostring(#rows)
	local logChanged = debugOn and sig ~= _lastCollectSubFiltersSig
	local shouldLog = logChanged and #rows <= MAX_DETAILED_LOG_ROWS
	if logChanged then
		_lastCollectSubFiltersSig = sig
		GlobalStorageSiK.Log.debug("ItemTaxonomy", "collectSubFilters(L2) | group=" .. groupLower .. " rows=" .. tostring(#rows)
			.. (#rows > MAX_DETAILED_LOG_ROWS and " (catalogo completo, detalle por fila omitido)" or ""))
	end

	for i = 1, #rows do
		local tax = GlobalStorageSiK.ItemTaxonomy.resolve(rows[i].fullType, rows[i])
		if shouldLog then
			GlobalStorageSiK.Log.debug("ItemTaxonomy", "collectSubFilters(L2) | fullType=" .. tostring(rows[i].fullType)
				.. " groupLabel=" .. tostring(tax.groupLabel) .. " subGroupLabel=" .. tostring(tax.subGroupLabel))
		end
		if tax.groupLabel ~= "" and string.lower(tax.groupLabel) == groupLower
			and tax.subGroupLabel and tax.subGroupLabel ~= "" then
			local label = tax.subGroupLabel
			local sig2 = string.lower(label)
			local key = SUB .. groupOriginal .. "::" .. label
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
	local sig = "L3|" .. groupLower .. "|" .. tostring(wantSubGroup) .. "|" .. tostring(#rows)
	local logChanged = debugOn and sig ~= _lastCollectSubFiltersSig
	local shouldLog = logChanged and #rows <= MAX_DETAILED_LOG_ROWS
	if logChanged then
		_lastCollectSubFiltersSig = sig
		GlobalStorageSiK.Log.debug("ItemTaxonomy", "collectLeafFilters(L3) | group=" .. groupLower
			.. " subgroup=" .. tostring(wantSubGroup) .. " rows=" .. tostring(#rows)
			.. (#rows > MAX_DETAILED_LOG_ROWS and " (catalogo completo, detalle por fila omitido)" or ""))
	end

	for i = 1, #rows do
		local tax = GlobalStorageSiK.ItemTaxonomy.resolve(rows[i].fullType, rows[i])
		if shouldLog then
			GlobalStorageSiK.Log.debug("ItemTaxonomy", "collectLeafFilters(L3) | fullType=" .. tostring(rows[i].fullType)
				.. " groupLabel=" .. tostring(tax.groupLabel) .. " subGroupLabel=" .. tostring(tax.subGroupLabel)
				.. " leafLabel=" .. tostring(tax.leafLabel))
		end
		if tax.groupLabel ~= "" and string.lower(tax.groupLabel) == groupLower and tax.leafLabel and tax.leafLabel ~= "" then
			local subOk = not wantSubGroup
				or (tax.subGroupLabel and string.lower(tax.subGroupLabel) == wantSubGroup)
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
				local sig2 = string.lower(key)
				if not map[sig2] then
					map[sig2] = { key = key, label = label, typeCount = 0 }
					list[#list + 1] = map[sig2]
				end
				map[sig2].typeCount = map[sig2].typeCount + 1
			end
		end
	end
	table.sort(list, function(a, b)
		return string.lower(a.label) < string.lower(b.label)
	end)
	return list
end
