--[[
	GlobalStorageSiK - Clasificador de bloque: Hogar, ocio y colección
	Autor: SiK
	Fecha: 2026-08-27

	Pedido explícito del usuario: "añade 1 o 2 bloques más, los sencillos,
	medicina, hogar ocio". Igual que Medicina, sin tag oficial confirmado
	equivalente para estas subcategorías (§3.2) - coincidencia de TOKEN
	completo (nunca subcadena) sobre el tipo real sin namespace de módulo,
	confianza 30 (§6), documentado como débil.

	CORREGIDO 2026-08-27 (dev6, hallazgo de sistemas sobre dev5): la versión
	anterior comparaba subcadenas ("pan"/"pot"/...) sobre el fullType
	completo - falsos positivos reales confirmados: Base.PanchoDog,
	Base.KeyRing_Panther, Base.SpottedBass ("s-POT-ted"), Base.Propane_Refill,
	Base.cold_steel_expandable_baton ("ex-PAN-dable"), Base.PancakesRecipe.
	Ahora usa GlobalStorageSiK.NativeClassifierUtils.typeName() (sin el
	prefijo de módulo) tokenizado por límite CamelCase/guion bajo
	(tokenize()), comparado por TOKEN EXACTO - "Pancho"/"Panther"/"Spotted"/
	"Propane"/"expandable"/"Pancakes" tokenizan como una sola palabra cada
	uno (sin frontera de mayúscula interna), nunca coinciden con "pan"/"pot".

	Registrado ANTES que Combate/Materiales: un objeto de cocina/ocio no
	debería competir con una clasificación de arma (p.ej. una guitarra usada
	como improvisada), mismo criterio que Medicina/Herramientas.

	Objetos EQUIPABLES se excluyen (igual que Materiales) para no capturar
	ropa o accesorios que casualmente compartan una palabra de nombre.
]]

require "GS_NativeClassifierApi"
require "GS_NativeClassifierUtils"

local U = GlobalStorageSiK.NativeClassifierUtils

---@param si table|nil
---@return boolean
local function isWearable(si)
	return U.bodyLocationLower(si) ~= ""
end

---@param list string[]
---@return table<string, boolean>
local function toSet(list)
	local set = {}
	for i = 1, #list do set[list[i]] = true end
	return set
end

-- BUG REAL cerrado (2026-08-27, hallazgo de sistemas sobre dev7): "cocina
-- confunde recipiente y contenido" - Base.PanFriedVegetablesForged/
-- PotOfSoupRecipe/PotOfStew/WaterSaucepanRice/PastaPot son COMIDA COCINADA
-- dentro de un recipiente, no menaje - "no deben quedar definitivamente
-- como menaje solo porque el tipo contenga Pot/Pan/Saucepan" (sistemas,
-- explicito). Hasta que exista el bloque Alimentos (bloqueado por probes
-- tecnicos, ver §10 del documento), es mas honesto dejarlos sin clasificar
-- que forzar una identidad de menaje equivocada - exclusion explicita por
-- token de "resultado de cocina" antes de comprobar Cocina.
-- dev9: sistemas encontro mas casos reales del mismo problema (RicePot,
-- RicePan, PastaPot, WaterPotRice, PastaPotForged, WaterSaucepanPasta) -
-- "rice"/"pasta" añadidos. El nuevo bloque Alimentos (GS_NativeClassifierFood.lua,
-- registrado ANTES que este fichero) reclama la mayoria de estos de verdad
-- ahora - esta exclusion queda como red de seguridad para lo que Alimentos
-- todavia no cubra.
local COOKED_FOOD_RESULT_TOKENS = toSet({ "recipe", "stew", "soup", "fried", "boiled", "roasted", "rice", "pasta" })

-- Cocina, dos L3: utensilio manual y electrodomestico.
local COOKWARE_TOKENS = toSet({ "pan", "pot", "spatula", "whisk", "ladle", "saucepan", "skillet" })
local APPLIANCE_TOKENS = toSet({ "kettle", "toaster", "blender" })
local MOVABLE_APPLIANCE_TOKENS = toSet({ "fridge", "refrigerator", "freezer", "microwave", "oven", "stove", "dishwasher" })
-- Limpieza, dos L3: producto quimico y utensilio.
local CLEANING_CHEMICAL_TOKENS = toSet({ "bleach", "detergent", "soap" })
local CLEANING_TOOL_TOKENS = toSet({ "mop", "sponge" })
-- Renovacion: un unico L3 real por ahora (pintura).
local PAINT_TOKENS = toSet({ "paintbrush", "paintcan", "paintbucket", "wallpaper" })
-- Coleccion, dos L3: objeto coleccionable y soporte/medio.
local COLLECTIBLE_TOKENS = toSet({ "trophy", "figurine", "stamp", "coin", "postcard" })
-- dev9: "vhs" se movió a Conocimiento y medios (GS_NativeClassifierKnowledgeMedia.lua,
-- registrado ANTES que este fichero) - sistemas: "VHS debe revisarse al
-- implementar Literatura/Multimedia", más correcto ahí semánticamente.
local MEDIA_TOKENS = toSet({ "painting" })
-- Ocio, dos L3: musica y juego de mesa/cartas. "drum" añadido en dev9
-- (Base.Mov_SnareDrum es un tambor real, no una trampa - ver la exclusión
-- correspondiente en GS_NativeClassifierSurvival.lua).
local MUSIC_TOKENS = toSet({ "guitar", "harmonica", "drum" })
local GAME_TOKENS = toSet({ "chess", "boardgame", "playingcard", "dice" })
-- Movibles vanilla: el prefijo `Mov_` identifica un objeto colocable, pero
-- no su uso. Solo se clasifica cuando el nombre real aporta una función
-- inequívoca; no se captura el resto con un cajón genérico.
local MOVABLE_STORAGE_TOKENS = toSet({ "drawer", "drawers", "cabinet", "chest", "dresser", "shelf", "shelves", "bookcase", "locker", "crate" })
local MOVABLE_SURFACE_TOKENS = toSet({ "table", "desk", "counter", "workbench" })
local MOVABLE_SEATING_TOKENS = toSet({ "chair", "sofa", "armchair", "bench", "stool" })

---@param fullType string
---@param si table|nil
---@return table|nil primaryPath
---@return table|nil facets
---@return table|nil attributes
---@return table|nil evidence
local function classifyHomeLeisure(fullType, si)
	if not si or isWearable(si) then return nil end
	local tokens = U.tokenize(U.typeName(si))
	if #tokens == 0 then return nil end
	if U.hasAnyToken(tokens, COOKED_FOOD_RESULT_TOKENS) then return nil end
	local isMoveable = U.itemTypeLower(si) == "base:moveable" or U.worldObjectSprite(si) ~= ""
	if isMoveable and U.hasAnyToken(tokens, MOVABLE_APPLIANCE_TOKENS) then
		return { l1 = "home_leisure_collection", l2 = "kitchen", l3 = "appliance" }, {}, {},
			U.evidence("script_movable_appliance", 100)
	end
	if isMoveable and U.hasAnyToken(tokens, MOVABLE_STORAGE_TOKENS) then
		return { l1 = "home_leisure_collection", l2 = "furnishing", l3 = "storage" }, {}, {},
			U.evidence("script_movable_storage", 100)
	end
	if isMoveable and U.hasAnyToken(tokens, MOVABLE_SURFACE_TOKENS) then
		return { l1 = "home_leisure_collection", l2 = "furnishing", l3 = "surface" }, {}, {},
			U.evidence("name_movable_surface", 30)
	end
	if isMoveable and U.hasAnyToken(tokens, MOVABLE_SEATING_TOKENS) then
		return { l1 = "home_leisure_collection", l2 = "furnishing", l3 = "seating" }, {}, {},
			U.evidence("name_movable_seating", 30)
	end

	if U.hasAnyToken(tokens, COOKWARE_TOKENS) then
		return
			{ l1 = "home_leisure_collection", l2 = "kitchen", l3 = "cookware" },
			{},
			{},
			U.evidence("name_home_kitchen", 30)
	end
	if U.hasAnyToken(tokens, APPLIANCE_TOKENS) then
		return
			{ l1 = "home_leisure_collection", l2 = "kitchen", l3 = "appliance" },
			{},
			{},
			U.evidence("name_home_kitchen", 30)
	end
	if U.hasAnyToken(tokens, CLEANING_CHEMICAL_TOKENS) then
		return
			{ l1 = "home_leisure_collection", l2 = "cleaning", l3 = "chemical" },
			{},
			{},
			U.evidence("name_home_cleaning", 30)
	end
	if U.hasAnyToken(tokens, CLEANING_TOOL_TOKENS) then
		return
			{ l1 = "home_leisure_collection", l2 = "cleaning", l3 = "tool" },
			{},
			{},
			U.evidence("name_home_cleaning", 30)
	end
	if U.hasAnyToken(tokens, PAINT_TOKENS) then
		return
			{ l1 = "home_leisure_collection", l2 = "renovation", l3 = "paint" },
			{},
			{},
			U.evidence("name_home_renovation", 30)
	end
	if U.hasAnyToken(tokens, COLLECTIBLE_TOKENS) then
		return
			{ l1 = "home_leisure_collection", l2 = "collection", l3 = "collectible" },
			{},
			{},
			U.evidence("name_home_collection", 30)
	end
	if U.hasAnyToken(tokens, MEDIA_TOKENS) then
		return
			{ l1 = "home_leisure_collection", l2 = "collection", l3 = "media" },
			{},
			{},
			U.evidence("name_home_collection", 30)
	end
	if U.hasAnyToken(tokens, MUSIC_TOKENS) then
		return
			{ l1 = "home_leisure_collection", l2 = "leisure", l3 = "music" },
			{},
			{},
			U.evidence("name_home_leisure", 30)
	end
	if U.hasAnyToken(tokens, GAME_TOKENS) then
		return
			{ l1 = "home_leisure_collection", l2 = "leisure", l3 = "game" },
			{},
			{},
			U.evidence("name_home_leisure", 30)
	end

	return nil
end

GlobalStorageSiK.NativeClassifier.registerBlock(classifyHomeLeisure, "home_leisure_collection")
