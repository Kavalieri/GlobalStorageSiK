--[[
	GlobalStorageSiK - Subcategorías preconfiguradas
	Autor: SiK
	Fecha: 2026-06-30
	Descripción: Subcategorías preconfiguradas, colgadas de su categoría vanilla madre.
	Clasificación automática por propiedades del ítem. Claves con prefijo "gs_".
	v0.10.18.81: clasificación vía SCRIPT item (clase estable) en vez del item vivo.
	Elimina excepciones Kahlua "No implementation found" con items moddeados.
]]

require "GS_Sandbox"
require "GS_Log"

GlobalStorageSiK.Subcategories = {}

--- Extended Categories (u otro mod de categorias extendidas equivalente) ya
--- gestiona esto, probablemente con mas detalle - nuestras subcategorias
--- internas (todas con "override" desde v1.2.76) se desactivan por completo
--- para no mezclar dos vocabularios en el mismo desplegable. Chequeo directo
--- de la tabla global (no via GS_CompatMods) para evitar acoplar este fichero,
--- de carga muy temprana, a modulos mas pesados.
---@return boolean
local function extendedCategoriesActive()
	return rawget(_G, "CAEC_Global") ~= nil
end

--- Better Sorting (BetterSortCC, Workshop 2313387159) fija BScats = BScats or
--- {} al cargar su shared file. Chequeo directo por el mismo motivo que
--- extendedCategoriesActive(): fichero de carga muy temprana.
---@return boolean
local function betterSortingActive()
	return rawget(_G, "BScats") ~= nil
end

-- Better Sorting reescribe getDisplayCategory() a ~79 codigos propios y
-- PLANOS (sin nivel 2/3, ver estudio de compatibilidad 2026-08-21) en
-- Events.OnGameBoot. A diferencia de Extended Categories, NO desactivamos
-- nuestro motor de subcategorias para el: normalizamos su codigo de vuelta a
-- la raiz vanilla ANTES de comparar (canonicalDisplayCat, definida mas abajo
-- una vez existe displayCat()), asi que catIs/catIsAny siguen reconociendo
-- Food/Weapon/Accessory/Material/FirstAid/Gardening exactamente igual que
-- sin ningun mod de categorias instalado. Solo se listan los codigos que
-- alimentan subcategorias GS reales (parentCategory abajo); el resto de
-- codigos de Better Sorting (ropa por slot, munición, furniture,
-- literatura...) no tiene equivalente GS y se deja tal cual, sin mapear (no
-- afecta a ningun matcher existente).
local BETTER_SORTING_CANON = {
	-- Alimentos: BS ya separa perecedero/no, pero isPerishableFood() usa
	-- getDaysFresh() (propiedad estable), no el texto de categoria - con
	-- normalizar a "Food" el propio motor GS vuelve a decidir bien.
	FoodA = "Food", FoodB = "Food", FoodN = "Food", FoodP = "Food",
	CookIng = "Food", CookIngP = "Food", CookBev = "Food", CookBevP = "Food",
	-- Jardineria: herramientas/insumos de granja (estiercol, pulverizador,
	-- pienso, esquiladora...). BS no parece tocar semillas (siguen "Gardening"
	-- vanilla), asi que gs_food_seed sigue funcionando sin mapear nada mas.
	SurFarm = "Gardening",
	-- Primeros auxilios: BS colapsa Bandage+FirstAid en estos 3 codigos.
	MedI = "FirstAid", MedM = "FirstAid", MedT = "FirstAid",
	-- Armas: isFirearm()/weaponMeleeTypeKey() usan propiedades del script item
	-- (isRanged/WeaponCategory), no el texto - normalizar a "Weapon" basta
	-- para que gs_weapon_firearm/gs_weapon_melee vuelvan a diferenciar bien.
	-- WepAmmo/WepAmmoMag/WepBomb/WepPart quedan fuera a proposito: no son el
	-- arma en si y GS no tiene subcategoria propia para ellos.
	WepFire = "Weapon", WepMelee = "Weapon",
	WepMAxe = "Weapon", WepMBluntL = "Weapon", WepMBluntS = "Weapon",
	WepMBladeL = "Weapon", WepMBladeS = "Weapon", WepMSpear = "Weapon",
	-- Accesorios: BS ya separa reloj/otros (ClothAcc) de joyeria (ClothJew),
	-- pero GS re-deriva joyeria real via BodyLocation (mas fino, ver
	-- JEWELRY_BODY_LOCATIONS) - basta con normalizar ambos a "Accessory".
	ClothAcc = "Accessory", ClothJew = "Accessory",
	-- Materiales: hasMetal() (tag) y el nombre "leather/hide/pelt" deciden el
	-- tipo real, no el texto de categoria - normalizar a "Material" basta.
	CraftBlack = "Material", CraftCarv = "Material", CraftG = "Material",
	CraftMas = "Material", CraftTailor = "Material",
}

-- ---------------------------------------------------------------------------
-- Helpers internos de clasificación
-- ---------------------------------------------------------------------------

local function safeGet(fn)
	local ok, v = pcall(fn)
	return ok and v or nil
end

-- CLAVE ARQUITECTÓNICA:
-- El item VIVO (InventoryItem) puede ser una subclase moddeada (ComboItem,
-- DrainableComboItem de damnCraft) cuyo dispatch de métodos en Kahlua falla con
-- "No implementation found" — excepción Java que PZ registra en consola incluso
-- capturada por pcall. NO es suprimible.
-- El SCRIPT item (zombie.scripting.objects.Item) es UNA sola clase, nunca
-- subclaseada por tipo, así que getDisplayCategory/getDaysFresh/isRanged/getTags/
-- getFullName tienen dispatch estable y NUNCA lanzan excepción.
-- Por eso TODAS las clasificaciones se calculan sobre el script item.
local _scriptItemCache = {}
local function scriptItemFor(item)
	local ft = safeGet(function() return item:getFullType() end)
	if not ft then return nil end
	local cached = _scriptItemCache[ft]
	if cached ~= nil then
		return cached or nil
	end
	local sm = getScriptManager and getScriptManager()
	local si = sm and safeGet(function() return sm:getItem(ft) end)
	_scriptItemCache[ft] = si or false
	if not si and GlobalStorageSiK.Sandbox.debugMode() then
		-- Diagnostico: si esto se ve para un fullType valido, la cache queda
		-- pillada en "false" PARA SIEMPRE (nunca se reintenta), y ese fullType
		-- jamas se clasificara en ninguna subcategoria GS en esta sesion.
		GlobalStorageSiK.Log.debug("Subcategories", "scriptItemFor | NO se pudo resolver script item para fullType=" .. tostring(ft) .. " (quedara cacheado como no-clasificable)")
	end
	return si
end

-- A partir de aquí, 'si' es SIEMPRE un script Item (no el item vivo).
local function displayCat(si)
	return (si and safeGet(function() return si:getDisplayCategory() end)) or ""
end

--- DisplayCategory ya normalizada: si Better Sorting esta activo y el codigo
--- tiene equivalente conocido (BETTER_SORTING_CANON), devuelve la raiz
--- vanilla; si no, el valor crudo. displayCat() se deja intacta (sin
--- normalizar) para cualquier otro consumidor que quiera el codigo real.
---@param si table script item
---@return string
local function canonicalDisplayCat(si)
	local raw = displayCat(si)
	if betterSortingActive() then
		local mapped = BETTER_SORTING_CANON[raw]
		if mapped then
			-- Log.detail: esto se llama por item/por refresco de Almacen, no
			-- por accion del jugador - volumen demasiado alto para Log.debug
			-- normal. Requiere activar tanto DebugCatCompatCategories como
			-- DebugDetailCompatCategories (AREA_CATEGORY CompatCategories =
			-- "CompatCategories" en GS_Log.lua).
			GlobalStorageSiK.Log.detail("CompatCategories", "canonicalDisplayCat | BetterSorting raw=" .. tostring(raw) .. " -> " .. mapped)
			return mapped
		end
	end
	return raw
end

local function catIs(si, cat)
	return string.lower(canonicalDisplayCat(si)) == string.lower(cat)
end

local function catIsAny(si, list)
	local dc = string.lower(canonicalDisplayCat(si))
	for i = 1, #list do
		if dc == string.lower(list[i]) then return true end
	end
	return false
end

local function getDaysFresh(si)
	if not si then return 0 end
	return safeGet(function() return si:getDaysFresh() end) or 0
end

-- BUG REAL encontrado (confirmado con NetTrace/DebugMode): getDaysFresh()
-- para comida SIN campo "DaysFresh" en el script (ej. Crisps, no se pudre
-- nunca) NO devuelve 0 ni un numero negativo como se asumia al escribir
-- la clasificación de perecederos devuelve un centinela ENORME (1000000000).
-- Con el matcher original ("> 0"), TODA la comida caía en gs_food_cold.
-- Los valores reales de DaysFresh en comida perecedera son pequenos (2-28,
-- ver food.txt vanilla), muy por debajo de este centinela.
local NEVER_ROTS_SENTINEL = 1000000

--- Indica si un item de comida realmente se pudre (tiene un DaysFresh real
--- y pequeño), distinguiendolo del centinela "nunca se pudre".
---@param si table
---@return boolean
local function isPerishableFood(si)
	local df = getDaysFresh(si)
	return df > 0 and df < NEVER_ROTS_SENTINEL
end

local function isFirearm(si)
	if not si then return false end
	return safeGet(function() return si:isRanged() end) == true
end

local function fullTypeLower(si)
	return string.lower((si and safeGet(function() return si:getFullName() end)) or "")
end

-- Metal: conjunto pre-construido UNA vez vía API global de tags (class-stable).
-- El tag real en los scripts es "base:hasmetal". Evita iterar el Set<ItemTag>
-- por item y evita llamar hasTag() sobre items vivos moddeados.
local _metalTypes = nil
local function buildMetalSet()
	if _metalTypes then return _metalTypes end
	_metalTypes = {}
	local sm = getScriptManager and getScriptManager()
	if not sm or not sm.getItemsTag then return _metalTypes end
	local items = safeGet(function()
		return sm:getItemsTag(ItemTag.get(ResourceLocation.of("base:hasmetal")))
	end)
	if items and items.size then
		for i = 0, items:size() - 1 do
			local si = items:get(i)
			local fn = si and safeGet(function() return si:getFullName() end)
			if fn then _metalTypes[string.lower(fn)] = true end
		end
	end
	return _metalTypes
end

local function hasMetal(si)
	if not si then return false end
	local fn = safeGet(function() return si:getFullName() end)
	if not fn then return false end
	return buildMetalSet()[string.lower(fn)] == true
end

-- ---------------------------------------------------------------------------
-- Nivel 2 de armas SIN Extended Categories (division propia, mas sencilla que
-- la de EC pero real): "Firearm"/"WeaponMelee" (nuestro propio Nivel 1, ver
-- gs_weapon_firearm/gs_weapon_melee mas abajo) se quedaban sin division por
-- tipo exacto de arma cuando EC no esta instalado. Nos inspiramos en el MISMO
-- metodo que usa EC (WeaponCategory del script item para cuerpo a cuerpo,
-- isTwoHandWeapon()+AmmoType para el tipo de arma de fuego) pero con codigo
-- propio, sin copiar ni depender de sus tablas/funciones. Solo se usa como
-- FALLBACK en GS_ItemTaxonomy.resolve() cuando EC no aporta ya este nivel via
-- el guion de su propia traduccion.
-- ---------------------------------------------------------------------------

--- Tipo de arma cuerpo a cuerpo ("axe"/"blunt"/"smallblunt"/"longblade"/
--- "smallblade"/"spear"/"crafted"), o nil si no se reconoce ninguna categoria.
---@param si table script item
---@return string|nil
function GlobalStorageSiK.Subcategories.weaponMeleeTypeKey(si)
	if not si or not si.getWeaponCategories then return nil end
	local ok, categories = pcall(function() return si:getWeaponCategories() end)
	if not ok or not categories or not categories.contains then return nil end
	if categories:contains(WeaponCategory.AXE) then return "axe" end
	if categories:contains(WeaponCategory.BLUNT) then return "blunt" end
	if categories:contains(WeaponCategory.SMALL_BLUNT) then return "smallblunt" end
	if categories:contains(WeaponCategory.LONG_BLADE) then return "longblade" end
	if categories:contains(WeaponCategory.SMALL_BLADE) then return "smallblade" end
	if categories:contains(WeaponCategory.SPEAR) then return "spear" end
	if categories:contains(WeaponCategory.IMPROVISED) then return "crafted" end
	return nil
end

local WEAPON_MELEE_TYPE_LABEL_KEY = {
	axe        = "IGUI_GS_WeaponMeleeType_Axe",
	blunt      = "IGUI_GS_WeaponMeleeType_Blunt",
	smallblunt = "IGUI_GS_WeaponMeleeType_SmallBlunt",
	longblade  = "IGUI_GS_WeaponMeleeType_LongBlade",
	smallblade = "IGUI_GS_WeaponMeleeType_SmallBlade",
	spear      = "IGUI_GS_WeaponMeleeType_Spear",
	crafted    = "IGUI_GS_WeaponMeleeType_Crafted",
}

--- Texto traducido de un tipo de arma cuerpo a cuerpo (ver weaponMeleeTypeKey).
---@param key string
---@return string
function GlobalStorageSiK.Subcategories.weaponMeleeTypeLabel(key)
	local labelKey = WEAPON_MELEE_TYPE_LABEL_KEY[key]
	if not labelKey then return key or "" end
	if GlobalStorageSiK.I18n and GlobalStorageSiK.I18n.tryGetText then
		local t = GlobalStorageSiK.I18n.tryGetText(labelKey)
		if t then return t end
	end
	return key
end

--- Tipo de arma de fuego ("handgun"/"rifle"/"shotgun"), o nil si el script
--- item no expone las propiedades necesarias (isTwoHandWeapon/AmmoType).
---@param si table script item
---@return string|nil
function GlobalStorageSiK.Subcategories.weaponFirearmTypeKey(si)
	if not si or not si.isTwoHandWeapon then return nil end
	local okTwo, twoHand = pcall(function() return si:isTwoHandWeapon() end)
	if not okTwo then return nil end
	if not twoHand then return "handgun" end
	local ammoLower = ""
	if si.getAmmoType then
		local okAmmo, ammoType = pcall(function() return si:getAmmoType() end)
		if okAmmo and ammoType then
			ammoLower = string.lower(tostring(ammoType))
		end
	end
	if ammoLower:find("shell", 1, true) or ammoLower:find("slug", 1, true) then
		return "shotgun"
	end
	return "rifle"
end

local WEAPON_FIREARM_TYPE_LABEL_KEY = {
	handgun = "IGUI_GS_WeaponFirearmType_Handgun",
	rifle   = "IGUI_GS_WeaponFirearmType_Rifle",
	shotgun = "IGUI_GS_WeaponFirearmType_Shotgun",
}

--- Texto traducido de un tipo de arma de fuego (ver weaponFirearmTypeKey).
---@param key string
---@return string
function GlobalStorageSiK.Subcategories.weaponFirearmTypeLabel(key)
	local labelKey = WEAPON_FIREARM_TYPE_LABEL_KEY[key]
	if not labelKey then return key or "" end
	if GlobalStorageSiK.I18n and GlobalStorageSiK.I18n.tryGetText then
		local t = GlobalStorageSiK.I18n.tryGetText(labelKey)
		if t then return t end
	end
	return key
end

-- ---------------------------------------------------------------------------
-- Definición de subcategorías
-- Cada entrada tiene parentCategory: la clave DisplayCategory vanilla de la que cuelga.
-- ---------------------------------------------------------------------------

-- Slots de BodyLocation que son claramente joyeria (anillos, collares,
-- pendientes, pulseras...), frente a otros "Accessory" que no lo son
-- (cinturones, gafas, relojes de pulsera funcional, mochilas de pecho...).
-- Sin esto, cualquier Accessory sin subcategoria GS caia en el fallback
-- generico "BodyLocation en crudo" (ej. "RightWrist", "Necklace_Long"),
-- que no es una subcategoria real - no aparecia en el filtro ni se podia
-- usar en un filtro de contenedor por categoria.
local JEWELRY_BODY_LOCATIONS = {
	necklace = true, necklace_long = true,
	ears = true, nose = true,
	rightwrist = true, leftwrist = true,
	right_ringfinger = true, left_ringfinger = true,
	right_middlefinger = true, left_middlefinger = true,
	right_indexfinger = true, left_indexfinger = true,
	right_pinkyfinger = true, left_pinkyfinger = true,
	right_thumb = true, left_thumb = true,
}

local function bodyLocationLower(si)
	if not si or not si.getBodyLocation then return "" end
	local loc = safeGet(function() return si:getBodyLocation() end)
	return loc and string.lower(tostring(loc)) or ""
end

-- Agrupa los BodyLocation crudos de joyeria (8 variantes de dedo, 2 de
-- muñeca, 2 de collar...) en el hueco "amigable" que reconoce el jugador -
-- esto es SOLO para el texto del filtro de subcategoria, nunca se escribe
-- como DisplayCategory (evita el lio de la version anterior).
local JEWELRY_SLOT_BUCKET = {
	necklace = "necklace", necklace_long = "necklace",
	ears = "earring",
	nose = "nose",
	rightwrist = "wrist", leftwrist = "wrist",
	right_ringfinger = "ring", left_ringfinger = "ring",
	right_middlefinger = "ring", left_middlefinger = "ring",
	right_indexfinger = "ring", left_indexfinger = "ring",
	right_pinkyfinger = "ring", left_pinkyfinger = "ring",
	right_thumb = "ring", left_thumb = "ring",
}

local JEWELRY_SLOT_LABEL_KEY = {
	necklace = "IGUI_GS_JewelrySlot_Necklace",
	ring     = "IGUI_GS_JewelrySlot_Ring",
	wrist    = "IGUI_GS_JewelrySlot_Wrist",
	earring  = "IGUI_GS_JewelrySlot_Earring",
	nose     = "IGUI_GS_JewelrySlot_Nose",
}

--- Hueco de joyeria "amigable" a partir de un BodyLocation ya resuelto en
--- minusculas (p.ej. "rightringfinger", "necklace_long", "right_ring_finger").
--- Version pura, sin depender de tener un script item vivo a mano - reutilizable
--- tanto si se resolvio via scriptItem:getBodyLocation() como via el fallback
--- de red (row.subCategory), el mismo dato que ya usa la columna "Categoria".
---
--- Busca por SUBCADENA, no por coincidencia exacta: distintos mods de items
--- (el nuestro, uno de joyeria de terceros...) pueden escribir el BodyLocation
--- con o sin guion bajo, en distinto orden de palabras, etc. - una tabla de
--- claves exactas se rompia con la primera variante no prevista. "ear" se
--- comprueba antes que "ring" porque "earring" contiene "ring" como subcadena.
---@param locLower string
---@return string|nil
function GlobalStorageSiK.Subcategories.jewelrySlotBucket(locLower)
	if not locLower or locLower == "" then return nil end
	if JEWELRY_SLOT_BUCKET[locLower] then
		return JEWELRY_SLOT_BUCKET[locLower]
	end
	if locLower:find("neck", 1, true) then return "necklace" end
	if locLower:find("ear", 1, true) then return "earring" end
	if locLower:find("nose", 1, true) then return "nose" end
	if locLower:find("wrist", 1, true) then return "wrist" end
	if locLower:find("finger", 1, true) or locLower:find("thumb", 1, true) or locLower:find("ring", 1, true) then
		return "ring"
	end
	return nil
end

--- Hueco de joyeria "amigable" (collar/anillo/muñeca/pendiente/nariz) de un
--- script item, o nil si no es un hueco de joyeria reconocido.
---@param si table script item
---@return string|nil
function GlobalStorageSiK.Subcategories.jewelrySlotKey(si)
	if not si then return nil end
	return GlobalStorageSiK.Subcategories.jewelrySlotBucket(bodyLocationLower(si))
end

--- Texto traducido (idioma actual, con reserva a ingles) de un hueco de joyeria.
--- Añadir un idioma nuevo solo requiere traducir estas claves IGUI_GS_JewelrySlot_*
--- en su Translate/<LANG>/IG_UI.json - esta funcion no necesita ningun cambio.
---@param slotKey string
---@return string
function GlobalStorageSiK.Subcategories.jewelrySlotLabel(slotKey)
	local labelKey = JEWELRY_SLOT_LABEL_KEY[slotKey]
	if not labelKey then return slotKey or "" end
	if GlobalStorageSiK.I18n and GlobalStorageSiK.I18n.tryGetText then
		local t = GlobalStorageSiK.I18n.tryGetText(labelKey)
		if t then return t end
	end
	return slotKey
end

GlobalStorageSiK.Subcategories.LIST = {

	-- NOTA (v1.2.76): cada entrada con "override" ya no es solo una etiqueta
	-- interna nuestra - GS_CategoryRewrite.lua la escribe como DisplayCategory
	-- REAL del item (vía DoParam, una vez al arrancar), igual que hace Extended
	-- Categories con las suyas. Reutilizamos exactamente sus mismas claves/
	-- etiquetas cuando existe un equivalente (Accessory-Jewelry, Food-Perishable,
	-- Food-Seed->Gardening-Seed, Material-Metalworking, Firearm), para no tener
	-- dos vocabularios de categorías distintos conviviendo. Las que ya eran una
	-- categoría vanilla real y distinta (ToolWeapon, RecipeResource, SkillBook,
	-- Literature) no necesitan entrada aquí: ya se descubren solas.

	-- ── Accessory (joyeria vs el resto) ─────────────────────────────────
	-- El hueco de equipacion (collar/anillo/muñeca/pendiente...) NO se fija
	-- aqui como categoria - ya se detecta solo, vanilla, via BodyLocation
	-- (ItemTaxonomy.readSubKey/subLabel), y aparece como subcategoria real sin
	-- inventar nada encima. Ver GS_ItemTaxonomy.lua:collectSubFilters.
	{
		key            = "gs_accessory_jewelry",
		parentCategory = "Accessory",
		labelKey       = "IGUI_GS_SubCat_AccessoryJewelry",
		override       = "AccessoryJewelry",
		matches        = function(item)
			if not catIs(item, "Accessory") then return false end
			return JEWELRY_BODY_LOCATIONS[bodyLocationLower(item)] == true
		end,
	},
	{
		key            = "gs_accessory_other",
		parentCategory = "Accessory",
		labelKey       = "IGUI_GS_SubCat_AccessoryOther",
		override       = "AccessoryOther",
		matches        = function(item)
			if not catIs(item, "Accessory") then return false end
			return JEWELRY_BODY_LOCATIONS[bodyLocationLower(item)] ~= true
		end,
	},

	-- ── Food ─────────────────────────────────────────────────────────────
	{
		key            = "gs_food_cold",
		parentCategory = "Food",
		labelKey       = "IGUI_GS_SubCat_FoodCold",
		override       = "FoodPerishable",
		matches        = function(item)
			if not catIs(item, "Food") then return false end
			return isPerishableFood(item)
		end,
	},
	-- No existe una categoria "no perecedero": la comida estable conserva la
	-- DisplayCategory general Food. Asi, FoodPerishable (tier 2) gana cuando
	-- corresponde y Food (tier 3) actua como fallback para toda la comida.
	-- Las claves gs_food_dry/FoodNonPerishable se conservan solo en migracion e
	-- i18n para datos antiguos; no se generan ni aparecen en filtros nuevos.

	-- ── Gardening (semillas vs herramientas) ─────────────────────────────
	{
		key            = "gs_food_seed",
		parentCategory = "Gardening",
		labelKey       = "IGUI_GS_SubCat_FoodSeed",
		override       = "GardeningSeed",
		matches        = function(item)
			if not catIs(item, "Gardening") then return false end
			return fullTypeLower(item):find("seed") ~= nil
		end,
	},
	{
		key            = "gs_tool_farm",
		parentCategory = "Gardening",
		labelKey       = "IGUI_GS_SubCat_ToolFarm",
		override       = "GardeningTool",
		matches        = function(item)
			if not catIs(item, "Gardening") then return false end
			return fullTypeLower(item):find("seed") == nil
		end,
	},

	-- ── FirstAid ─────────────────────────────────────────────────────────
	{
		key            = "gs_med_aid",
		parentCategory = "FirstAid",
		labelKey       = "IGUI_GS_SubCat_MedAid",
		override       = "FirstAidAid",
		matches        = function(item)
			return catIsAny(item, { "Bandage", "FirstAid" })
				and not (fullTypeLower(item):find("scalpel") or fullTypeLower(item):find("suture")
				         or fullTypeLower(item):find("surgic") or fullTypeLower(item):find("bloodbag"))
		end,
	},
	{
		key            = "gs_med_surgery",
		parentCategory = "FirstAid",
		labelKey       = "IGUI_GS_SubCat_MedSurgery",
		override       = "FirstAidSurgery",
		matches        = function(item)
			if not catIsAny(item, { "Bandage", "FirstAid" }) then return false end
			local ft = fullTypeLower(item)
			-- El contrato de overrideForScriptItem exige result == true. Devolver
			-- directamente string.find() entregaba un numero y hacía que Cirugía no
			-- se seleccionase nunca, aunque la coincidencia existiera.
			return ft:find("scalpel", 1, true) ~= nil or ft:find("suture", 1, true) ~= nil
			    or ft:find("surgic", 1, true) ~= nil or ft:find("bloodbag", 1, true) ~= nil
			    or ft:find("retractor", 1, true) ~= nil or ft:find("forcep", 1, true) ~= nil
		end,
	},

	-- ── Weapon ───────────────────────────────────────────────────────────
	{
		key            = "gs_weapon_firearm",
		parentCategory = "Weapon",
		labelKey       = "IGUI_GS_SubCat_WeaponFirearm",
		override       = "Firearm",
		matches        = function(item)
			return catIsAny(item, { "Weapon", "WeaponCrafted" }) and isFirearm(item)
		end,
	},
	{
		key            = "gs_weapon_melee",
		parentCategory = "Weapon",
		labelKey       = "IGUI_GS_SubCat_WeaponMelee",
		override       = "WeaponMelee",
		matches        = function(item)
			return catIsAny(item, { "Weapon", "WeaponCrafted" }) and not isFirearm(item)
		end,
	},

	-- ── Material — por profesión/uso mayoritario ──────────────────────────
	{
		key            = "gs_mat_metal",
		parentCategory = "Material",
		labelKey       = "IGUI_GS_SubCat_MatMetal",
		override       = "MaterialMetalworking",
		-- Tag "hasmetal" identifica lingotes, chapas, barras, herramientas de forja
		matches        = function(item)
			return catIs(item, "Material") and hasMetal(item)
		end,
	},
	{
		key            = "gs_mat_leather",
		parentCategory = "Material",
		labelKey       = "IGUI_GS_SubCat_MatLeather",
		override       = "MaterialLeather",
		-- Pieles, cuero curtido y sin curtir — nombre siempre contiene "leather" o "hide"
		matches        = function(item)
			if not catIs(item, "Material") then return false end
			local ft = fullTypeLower(item)
			return ft:find("leather") ~= nil or ft:find("hide") ~= nil or ft:find("pelt") ~= nil
		end,
	},
	{
		key            = "gs_mat_wood",
		parentCategory = "Material",
		labelKey       = "IGUI_GS_SubCat_MatWood",
		override       = "MaterialWood",
		-- Materiales de construcción: Material que no es metal ni cuero
		matches        = function(item)
			if not catIs(item, "Material") then return false end
			if hasMetal(item) then return false end
			local ft = fullTypeLower(item)
			return ft:find("leather") == nil and ft:find("hide") == nil and ft:find("pelt") == nil
		end,
	},

}

-- ---------------------------------------------------------------------------
-- Índice por clave (construido una sola vez)
-- ---------------------------------------------------------------------------

local _byKey = nil
local function buildIndex()
	if _byKey then return _byKey end
	_byKey = {}
	for i = 1, #GlobalStorageSiK.Subcategories.LIST do
		local sub = GlobalStorageSiK.Subcategories.LIST[i]
		_byKey[sub.key] = sub
	end
	return _byKey
end

--- Devuelve la definición de una subcategoría por su clave.
---@param key string
---@return table|nil
function GlobalStorageSiK.Subcategories.get(key)
	return buildIndex()[key]
end

--- Indica si la clave pertenece a una subcategoría GS.
---@param key string|nil
---@return boolean
function GlobalStorageSiK.Subcategories.isSubcategoryKey(key)
	if not key then return false end
	return buildIndex()[key] ~= nil
end

--- Comprueba si un ítem encaja en la subcategoría indicada.
--- Resuelve el script item (clase estable) y ejecuta el matcher sobre él.
---@param key string
---@param item InventoryItem
---@return boolean
function GlobalStorageSiK.Subcategories.matches(key, item)
	if not item or extendedCategoriesActive() then return false end
	local sub = GlobalStorageSiK.Subcategories.get(key)
	if not sub or not sub.matches then return false end
	local si = scriptItemFor(item)
	if not si then return false end
	local ok, result = pcall(sub.matches, si)
	return ok and result == true
end

--- Igual que keysForItem, pero operando directamente sobre un SCRIPT item ya
--- resuelto (sin necesitar un InventoryItem vivo) - usado para construir el
--- catalogo completo de subcategorias posibles (GS_ItemTaxonomy.getFullCatalogRows),
--- donde se recorre CADA tipo de item del juego, no solo los que el jugador
--- ya tiene en la red.
---@param si table script item
---@return string[]
function GlobalStorageSiK.Subcategories.keysForScriptItem(si)
	local out = {}
	if not si or extendedCategoriesActive() then return out end
	local list = GlobalStorageSiK.Subcategories.LIST
	for i = 1, #list do
		local sub = list[i]
		local ok, result = pcall(sub.matches, si)
		if ok and result == true then
			out[#out + 1] = sub.key
		end
	end
	return out
end

--- Devuelve todas las claves de subcategoría que corresponden a un ítem.
--- Resuelve el script item UNA vez y pasa ése a los matchers (dispatch estable,
--- sin excepciones Kahlua con items moddeados).
---@param item InventoryItem
---@return string[]
function GlobalStorageSiK.Subcategories.keysForItem(item)
	local out = {}
	if not item or extendedCategoriesActive() then return out end
	local si = scriptItemFor(item)
	if not si then return out end
	local debugOn = GlobalStorageSiK.Sandbox.debugMode()
	local detailOn = GlobalStorageSiK.Sandbox.debugDetailEnabled("Inventory")
	local list = GlobalStorageSiK.Subcategories.LIST
	for i = 1, #list do
		local sub = list[i]
		local ok, result = pcall(sub.matches, si)
		if debugOn and not ok then
			GlobalStorageSiK.Log.debug("Subcategories", "keysForItem | matcher \"" .. tostring(sub.key) .. "\" fallo con error: " .. tostring(result))
		end
		if ok and result == true then
			out[#out + 1] = sub.key
		end
	end
	if detailOn then
		local ft = safeGet(function() return item:getFullType() end)
		local dc = displayCat(si)
		local df = getDaysFresh(si)
		GlobalStorageSiK.Log.detail("Subcategories", "keysForItem | fullType=" .. tostring(ft)
			.. " displayCategory=" .. tostring(dc) .. " daysFresh=" .. tostring(df)
			.. " gsKeys=" .. (#out > 0 and table.concat(out, ",") or "(ninguna)"))
	end
	return out
end

--- Resuelve la primera subcategoria (con "override") cuyo matcher acepta un
--- SCRIPT item directamente - usado en el arranque (GS_CategoryRewrite.lua),
--- donde solo existen script items, nunca instancias vivas.
---@param si table script item (zombie.scripting.objects.Item)
---@return table|nil sub  la definicion completa (con .override), o nil
function GlobalStorageSiK.Subcategories.overrideForScriptItem(si)
	if not si then return nil end
	local list = GlobalStorageSiK.Subcategories.LIST
	for i = 1, #list do
		local sub = list[i]
		if sub.override then
			local ok, result = pcall(sub.matches, si)
			if ok and result == true then
				return sub
			end
		end
	end
	return nil
end

--- Texto de display de una subcategoría (traduce labelKey).
---@param key string
---@return string
function GlobalStorageSiK.Subcategories.label(key)
	local sub = GlobalStorageSiK.Subcategories.get(key)
	if not sub then return key end
	if GlobalStorageSiK.I18n and GlobalStorageSiK.I18n.tryGetText then
		local t = GlobalStorageSiK.I18n.tryGetText(sub.labelKey)
		if t then return t end
	end
	return sub.labelKey
end


-- Índice por parentCategory (construido una sola vez)
local _byParent = nil
local function buildParentIndex()
	if _byParent then return _byParent end
	_byParent = {}
	for i = 1, #GlobalStorageSiK.Subcategories.LIST do
		local sub = GlobalStorageSiK.Subcategories.LIST[i]
		local p = sub.parentCategory or ""
		if p ~= "" then
			if not _byParent[p] then _byParent[p] = {} end
			_byParent[p][#_byParent[p] + 1] = sub
		end
	end
	return _byParent
end

--- Devuelve las subcategorías GS que cuelgan de una categoría vanilla dada.
---@param parentCategory string  -- clave DisplayCategory vanilla (p. ej. "Food")
---@return table[]  -- lista de definiciones de subcategoría
function GlobalStorageSiK.Subcategories.childrenOf(parentCategory)
	if not parentCategory or parentCategory == "" or extendedCategoriesActive() then return {} end
	local idx = buildParentIndex()
	return idx[parentCategory] or {}
end

--- Indica si alguna subcategoría GS cuelga de esa categoría vanilla.
---@param parentCategory string
---@return boolean
function GlobalStorageSiK.Subcategories.hasChildren(parentCategory)
	return #GlobalStorageSiK.Subcategories.childrenOf(parentCategory) > 0
end
