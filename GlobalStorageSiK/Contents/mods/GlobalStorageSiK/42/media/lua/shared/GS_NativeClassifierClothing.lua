--[[
	GlobalStorageSiK - Clasificador de bloque: Ropa y protección
	Autor: SiK
	Fecha: 2026-08-27

	6º bloque de clasificación real (dev6, "añade un bloque más al catálogo,
	el que tú decidas"). Elegido por ser el más honesto posible: usa
	`getBodyLocation()` (ItemBodyLocation), un campo OFICIAL del motor, ya
	confirmado y en producción en todo el mod (`U.bodyLocationLower`, usado
	por Materiales/Medicina/Hogar-ocio para EXCLUIR equipables) - nunca una
	heurística de nombre. Cualquier objeto con hueco de equipación real es,
	por definición, ropa/protección/accesorio - cero riesgo de falso
	positivo, a diferencia de las reglas de nombre del resto de bloques.

	L2 "clothing" (confianza 100, campo oficial). "protection"/"accessory"
	(§5 grupo 6) necesitarían distinguir por valor de defensa contra
	mordisco/arañazo o una lista de huecos de accesorio - ninguna con la
	misma confianza todavía, se dejan sin clasificar ese matiz.

	L3 AÑADIDO 2026-08-27 (pedido explícito del usuario: "L3 para ropa es
	importante, por su lugar donde se equipa, quiero poder filtrar por
	pierna, torso, cabeza etc") - agrupa el hueco de equipación REAL en
	región corporal (cabeza/cuello/torso/piernas/pies/brazos). Fuente: la
	lista COMPLETA y oficial de constantes ItemBodyLocation confirmada en
	`media/lua/shared/NPCs/BodyLocations.lua` del propio juego (no
	adivinada) - se tokeniza el valor devuelto por `getBodyLocation()`
	(límite CamelCase/guion bajo, mismo helper que el resto de bloques) y se
	compara por token exacto contra la región correspondiente. Huecos
	ambiguos o raros sin región corporal clara (correas/holsters/webbing/
	mochilas de cintura/hombreras sueltas) se dejan con `l3=nil` a propósito
	- nunca inventados.
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

-- Comprobados EN ORDEN contra BodyLocations.lua real del juego. TORSO se
-- comprueba ANTES que CABEZA a propósito: "FullSuitHead"/"SweaterHat"/
-- "JacketHat" son fundamentalmente prendas de torso con una variante que
-- también cubre la cabeza - el token "suit"/"sweater"/"jacket" debe ganar
-- sobre el token "hat"/"head" suelto que también contienen.
-- dev27 (hallazgo real detectado al construir el corpus de Ropa contra los
-- scripts vanilla reales de BodyLocation): "fullsuit"/"bathrobe" (torso) y
-- "longdress"/"longskirt" (piernas) son valores de BodyLocation de UNA sola
-- palabra (sin limite CamelCase, p.ej. Base.WeddingDress -> BodyLocation
-- "fullsuit") - nunca coincidian con los tokens "suit"/"robe"/"dress"/
-- "skirt" sueltos, dejando esas prendas reales con L3 vacio sin motivo
-- (region corporal real perfectamente determinable). Añadido aditivo, sin
-- quitar ningun token existente.
local TORSO_TOKENS = toSet({
	"torso", "tanktop", "tshirt", "shirt", "sweater", "jersey", "jacket",
	"suit", "boilersuit", "robe", "costume", "cuirass", "vest", "back",
	"fullsuit", "bathrobe",
})
local HEAD_TOKENS = toSet({ "hat", "mask", "eyes", "eye" })
local NECK_TOKENS = toSet({ "neck", "necklace", "scarf", "gorget" })
local ARMS_TOKENS = toSet({ "hand", "hands", "arm", "wrist", "elbow", "forearm", "shoulderpad" })
local LEGS_TOKENS = toSet({ "legs", "shorts", "pants", "skirt", "dress", "knee", "calf", "thigh", "codpiece", "gaiter", "longdress", "longskirt" })
local FEET_TOKENS = toSet({ "shoes", "socks" })

-- BUG REAL cerrado (2026-08-27, hallazgo de sistemas sobre dev6): Base.
-- Bandage_Chest/Base.Bandage_Head/... y Base.ZedDmg_BACK_Slash tienen un
-- BodyLocation real (son proxies visuales que el motor equipa para dibujar
-- la herida/venda sobre el personaje) - Ropa los reclamaba ANTES de que
-- Medicina pudiera clasificar la venda de verdad. Sistemas: "no conviene
-- resolverlo cambiando ciegamente la precedencia hasta confirmar su
-- naturaleza" - en vez de reordenar bloques enteros, esta exclusion
-- puntual deja pasar SOLO estos prefijos conocidos de proxy visual, para
-- que Medicina (Bandage) los reclame despues, o caigan honestamente en
-- unclassified_modded (ZedDmg, sin bloque de destino todavia) en vez de
-- una "Ropa" que no significa nada para el jugador.
local INTERNAL_PROXY_TOKENS = toSet({ "bandage", "wound", "zeddmg" })

-- dev27 (decision de producto de sistemas): "mochila o bolsa vestible se
-- busca primariamente en Ropa/Equipamiento; su capacidad se conserva como
-- faceta de contenedor" - reemplaza la excepcion que vivia en
-- GS_NativeClassifierContainers.lua desde dev12 (containers/wearable/backpack).
-- Misma deteccion por nombre ya validada en dev12 (BACKPACK_TOKENS +
-- "alicepack" por subcadena, ver comentario historico alli) - se mueve aqui
-- sin cambiar la logica de deteccion, solo el bloque de destino.
local BACKPACK_TOKENS = toSet({ "backpack", "rucksack", "duffel", "satchel" })

--- Región corporal real (L3) a partir del hueco de equipación tokenizado, o
--- nil si el hueco no encaja en ninguna región reconocida (nunca inventado).
---@param si table
---@return string|nil
local function bodyRegionL3(si)
	local tokens = U.tokenize(U.bodyLocation(si))
	if #tokens == 0 then return nil end
	if U.hasAnyToken(tokens, TORSO_TOKENS) then return "torso" end
	if U.hasAnyToken(tokens, HEAD_TOKENS) then return "head" end
	if U.hasAnyToken(tokens, NECK_TOKENS) then return "neck" end
	if U.hasAnyToken(tokens, ARMS_TOKENS) then return "arms" end
	if U.hasAnyToken(tokens, LEGS_TOKENS) then return "legs" end
	if U.hasAnyToken(tokens, FEET_TOKENS) then return "feet" end
	return nil
end

---@param fullType string
---@param si table|nil
---@return table|nil primaryPath
---@return table|nil facets
---@return table|nil attributes
---@return table|nil evidence
local function classifyClothing(fullType, si)
	if not si then return nil end

	-- dev27: mochilas/bolsas vestibles PRIMERO, antes del corte por
	-- BodyLocation vacio - dev12 confirmo que no todas resuelven
	-- BodyLocation sobre el ScriptItem estatico (Bag_ALICEpack_Army), asi
	-- que esta identidad no puede depender de ese campo. Faceta de
	-- capacidad de contenedor conservada explicitamente (nunca doble
	-- identidad contradictoria con Contenedores, que ya no reclama esto).
	local nameTokens = U.tokenize(U.typeName(si))
	local isAlicePack = U.fullTypeLower(si):find("alicepack", 1, true) ~= nil
	local isEquippableContainer = U.itemTypeLower(si) == "base:container"
		and U.displayCategoryLower(si) == "bag" and U.canBeEquippedLower(si) ~= ""
	if U.hasAnyToken(nameTokens, BACKPACK_TOKENS) or isAlicePack or isEquippableContainer then
		local bodyLoc = U.bodyLocationLower(si)
		if bodyLoc ~= "" then
			return
				{ l1 = "clothing_protection", l2 = "equipment", l3 = "backpack" },
				{ containerCapacity = true },
				{},
				U.evidence("script_body_location_backpack", 100)
		end
		return
			{ l1 = "clothing_protection", l2 = "equipment", l3 = "backpack" },
			{ containerCapacity = true },
			{},
			U.evidence(isEquippableContainer and "script_equippable_container" or "name_clothing_backpack",
				isEquippableContainer and 100 or 30)
	end

	-- dev27 (§5, decision explicita de sistemas: "elementos de municion
	-- vestibles requieren decision explicita de identidad primaria y faceta
	-- de contenido, sin dobles afirmaciones contradictorias"): confirmado
	-- por lectura real de scripts (AmmoStrap_Bullets/_Shells y variantes) -
	-- BodyLocation=base:ammostrap SI resuelve (a diferencia de las mochilas
	-- ALICE) y ademas llevan el tag oficial AMMO_CASE. Mismo criterio que
	-- backpack: identidad primaria en Ropa/Equipamiento (es una prenda que
	-- se lleva puesta), capacidad de municion conservada como faceta,
	-- nunca doble identidad con Combate para el mismo objeto. Las cajas de
	-- municion SIN BodyLocation (Bag_AmmoBox_*) no pasan por aqui (bodyLoc
	-- vacio) y siguen siendo Combate via el tag AMMO_CASE, sin cambios.
	local bodyLocForAmmo = U.bodyLocationLower(si):gsub("^[^:]+:", "")
	if bodyLocForAmmo == "ammostrap" and U.itemTypeLower(si) == "base:container" then
		return
			{ l1 = "clothing_protection", l2 = "equipment", l3 = "ammo_strap" },
			{ ammo = true, containerCapacity = true },
			{},
			U.evidence("script_body_location_ammo_strap", 100)
	end

	local bodyLocLower = U.bodyLocationLower(si)
	if bodyLocLower == "" then return nil end
	local normalizedBodyLoc = bodyLocLower:gsub("^[^:]+:", "")
	local displayCategory = U.displayCategoryLower(si):gsub("^[^:]+:", "")
	-- dev28.1: los proxies ZedDmg no siempre incluyen el token en el nombre
	-- que devuelve typeName(). BodyLocation/DisplayCategory son las señales
	-- estructurales reales y deben excluirlos antes del fallback de ropa.
	if normalizedBodyLoc == "zeddmg" or displayCategory == "zeddmg" then return nil end
	if U.hasAnyToken(nameTokens, INTERNAL_PROXY_TOKENS) then return nil end

	-- dev11 (pedido explícito del usuario: "las joyas ya lo teníamos
	-- organizados por hueco equipable también"): reutiliza
	-- NativeClassifierUtils.jewelrySlotKey() en vez de duplicar la lista de
	-- huecos de joyería aquí -
	-- collar/anillo/muñeca/pendiente/nariz son L2 "accessory", nunca
	-- "clothing" genérico, aunque compartan el mismo hueco de equipación
	-- oficial.
	local jewelrySlot = U.jewelrySlotKey(si)
	if jewelrySlot then
		return
			{ l1 = "clothing_protection", l2 = "accessory", l3 = jewelrySlot },
			{},
			{},
			U.evidence("script_body_location_jewelry", 100)
	end

	return
		{ l1 = "clothing_protection", l2 = "clothing", l3 = bodyRegionL3(si) },
		{},
		{},
		U.evidence("script_body_location", 100)
end

GlobalStorageSiK.NativeClassifier.registerBlock(classifyClothing, "clothing")
