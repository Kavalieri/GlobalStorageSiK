--[[
	GlobalStorageSiK - Clasificador de bloque: Electrónica/energía, Vehículos, Supervivencia y exterior
	Autor: SiK
	Fecha: 2026-08-27

	Pedido explícito del usuario: "Un bloque mas, electrónica, vehículos y
	supervivencia, a ver que obtenemos hasta L3". Sin tags oficiales
	confirmados equivalentes a los de Combate/Herramientas para estos 3
	grupos (no se encontró ningún `base:xxx` de electrónica/vehículo/granja
	al revisar `media/scripts` del propio juego) - misma honestidad débil
	que Medicina/Hogar-ocio (confianza 30, coincidencia de TOKEN completo
	sobre el tipo real sin namespace de módulo, nunca subcadena).

	Registrado tras Hogar-ocio, ANTES de Combate/Materiales(débil) - mismo
	criterio que el resto: un objeto de electrónica/vehículo/supervivencia
	no debería competir con una clasificación de arma por casualidad, y
	Materiales(débil) es el catch-all de último recurso.

	Camping reclama explícitamente sacos de dormir y tiendas (antes caían en
	"medicine/medication/sedative" por "sleeping" suelto, o en
	"materials/leather_hide" por "hide" suelto - ver GS_NativeClassifierMedicine.lua
	y el EXCLUDE_TOKENS de GS_NativeClassifierMaterials.lua, ambos corregidos
	en la misma ronda dev7).
]]

require "GS_NativeClassifierApi"
require "GS_NativeClassifierUtils"

local U = GlobalStorageSiK.NativeClassifierUtils

---@param list string[]
---@return table<string, boolean>
local function toSet(list)
	local set = {}
	for i = 1, #list do set[list[i]] = true end
	return set
end

-- Electrónica y energía (§5 grupo 9).
local POWER_TOKENS = toSet({ "battery", "powerbank", "generator" })
-- dev9 (hallazgo de sistemas sobre dev8): Base.CarBattery es una pieza de
-- vehiculo, no energia domestica generica - "car"/"vehicle" excluye la
-- regla de energia (queda sin clasificar hasta que Vehiculos tenga una
-- señal real de bateria automotriz, mejor que forzarla mal).
local POWER_EXCLUDE_TOKENS = toSet({ "car", "vehicle" })
-- dev9: RadioMag1/2/3 son revistas de radioaficionado (literatura), no
-- comunicacion - "mag"/"magazine" excluye la regla de comunicacion.
local COMMUNICATION_EXCLUDE_TOKENS = toSet({ "mag", "magazine" })
local COMMUNICATION_TOKENS = toSet({ "radio", "walkie", "megaphone" })
local LIGHTING_TOKENS = toSet({ "flashlight", "lantern", "lightbulb" })
local ENTERTAINMENT_TOKENS = toSet({ "television", "stereo" })

-- Vehículos (§5 grupo 10). Conjunto conservador - nombres de piezas de
-- vehiculos de mods de terceros varian mucho, solo tokens vanilla claros.
local VEHICLE_PART_TOKENS = toSet({
	"engine", "carburettor", "piston", "radiator", "alternator", "gearbox",
	"headlight", "taillight", "bumper", "muffler", "brakepad", "suspension",
	"exhaust", "doorhandle",
})
-- dev16 (política explícita del usuario: "si buscamos gasolina no nos
-- interesa un contenedor vacío que pueda contener o no gasolina, pero si
-- buscamos un bidón sí lo queremos vacío") - "empty" excluye el consumible,
-- cede a Contenedores.
local VEHICLE_CONSUMABLE_TOKENS = toSet({ "gasoline", "petrol", "antifreeze", "brakefluid" })
local VEHICLE_CONSUMABLE_EXCLUDE_TOKENS = toSet({ "empty" })

-- Supervivencia y exterior (§5 grupo 11).
local FARMING_TOKENS = toSet({ "seed", "fertilizer", "hoe", "wateringcan", "compost" })
local FISHING_TOKENS = toSet({ "bait", "lure" })
local TRAPPING_TOKENS = toSet({ "trap", "snare" })
-- dev9 (hallazgo de sistemas sobre dev8): Base.Mov_SnareDrum es un tambor
-- musical, no una trampa - "snare" ahi nombra el instrumento (snare drum),
-- no una trampa de caza. Exclusion puntual: si el tipo tambien tiene el
-- token "drum", "snare" no cuenta como trampa.
local MUSIC_INSTRUMENT_EXCLUDE_TOKENS = toSet({ "drum" })
-- "tent"/"sleeping" reclaman aqui explicitamente lo que antes eran falsos
-- positivos reales de otros bloques (ver comentario de cabecera).
-- BUG REAL cerrado (2026-08-27, hallazgo de sistemas sobre dev12):
-- "sleepingbag" como token unico nunca coincide de verdad -
-- "SleepingBag_HighQuality_Brown" tokeniza (limite CamelCase real) como
-- {"sleeping","bag",...}, nunca como un unico token "sleepingbag" - por
-- eso Base.SleepingBag_* seguia cayendo en Contenedores. "sleeping" solo
-- (ya libre desde que Medicina quito ese mismo token de sus sedantes en
-- dev7) es suficiente y correcto.
local CAMPING_TOKENS = toSet({ "tent", "sleeping", "campfire", "tarp", "hammock" })
local SECURITY_TOKENS = toSet({ "padlock" })

---@param fullType string
---@param si table|nil
---@return table|nil primaryPath
---@return table|nil facets
---@return table|nil attributes
---@return table|nil evidence
local function classifySurvival(fullType, si)
	if not si then return nil end
	local tokens = U.tokenize(U.typeName(si))
	if #tokens == 0 then return nil end

	if U.hasAnyToken(tokens, POWER_TOKENS) and not U.hasAnyToken(tokens, POWER_EXCLUDE_TOKENS) then
		return { l1 = "electronics_power", l2 = "power", l3 = nil }, {}, {}, U.evidence("name_electronics_power", 30)
	end
	if U.hasAnyToken(tokens, COMMUNICATION_TOKENS) and not U.hasAnyToken(tokens, COMMUNICATION_EXCLUDE_TOKENS) then
		return { l1 = "electronics_power", l2 = "communication", l3 = nil }, {}, {}, U.evidence("name_electronics_communication", 30)
	end
	if U.hasAnyToken(tokens, LIGHTING_TOKENS) then
		return { l1 = "electronics_power", l2 = "lighting", l3 = nil }, {}, {}, U.evidence("name_electronics_lighting", 30)
	end
	if U.hasAnyToken(tokens, ENTERTAINMENT_TOKENS) then
		return { l1 = "electronics_power", l2 = "entertainment", l3 = nil }, {}, {}, U.evidence("name_electronics_entertainment", 30)
	end

	if U.hasAnyToken(tokens, VEHICLE_PART_TOKENS) then
		return { l1 = "vehicles", l2 = "part", l3 = nil }, {}, {}, U.evidence("name_vehicles_part", 30)
	end
	if U.hasAnyToken(tokens, VEHICLE_CONSUMABLE_TOKENS) and not U.hasAnyToken(tokens, VEHICLE_CONSUMABLE_EXCLUDE_TOKENS) then
		return { l1 = "vehicles", l2 = "consumable", l3 = nil }, {}, {}, U.evidence("name_vehicles_consumable", 30)
	end

	-- dev17 (hallazgo de sistemas sobre dev16): "Base.RyeSeed -> food_drink/
	-- other_food, debería ganar Agricultura". Confirmado leyendo items.txt
	-- real: RyeSeed/CornSeed/etc. llevan el tag oficial `base:isseed`
	-- (Base.SeedPaste, harina de semilla molida y sí comestible, NO lo
	-- lleva) - señal fuerte (confianza 95, tag oficial) comprobada ANTES
	-- del token débil "seed" de abajo. GS_NativeClassifierFood.lua veta su
	-- propio reclamo cuando detecta este mismo tag, así que esta regla
	-- decide sin colisión.
	local isSeedTag = U.tagByLocation("base", "isseed")
	if isSeedTag and U.hasTag(si, isSeedTag) then
		return { l1 = "survival_outdoors", l2 = "farming", l3 = nil }, {}, {}, U.evidence("script_tag_isseed", 95)
	end
	if U.hasAnyToken(tokens, FARMING_TOKENS) then
		return { l1 = "survival_outdoors", l2 = "farming", l3 = nil }, {}, {}, U.evidence("name_survival_farming", 30)
	end
	if U.hasAnyToken(tokens, FISHING_TOKENS) then
		return { l1 = "survival_outdoors", l2 = "fishing", l3 = nil }, {}, {}, U.evidence("name_survival_fishing", 30)
	end
	if U.hasAnyToken(tokens, TRAPPING_TOKENS) and not U.hasAnyToken(tokens, MUSIC_INSTRUMENT_EXCLUDE_TOKENS) then
		return { l1 = "survival_outdoors", l2 = "trapping", l3 = nil }, {}, {}, U.evidence("name_survival_trapping", 30)
	end
	if U.hasAnyToken(tokens, CAMPING_TOKENS) then
		return { l1 = "survival_outdoors", l2 = "camping", l3 = nil }, {}, {}, U.evidence("name_survival_camping", 30)
	end
	if U.hasAnyToken(tokens, SECURITY_TOKENS) then
		return { l1 = "survival_outdoors", l2 = "security", l3 = nil }, {}, {}, U.evidence("name_survival_security", 30)
	end

	return nil
end

GlobalStorageSiK.NativeClassifier.registerBlock(classifySurvival, "electronics_vehicles_survival")
