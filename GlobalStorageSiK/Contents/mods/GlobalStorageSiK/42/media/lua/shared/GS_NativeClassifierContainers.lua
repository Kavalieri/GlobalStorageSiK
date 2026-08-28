--[[
	GlobalStorageSiK - Clasificador de bloque: Contenedores
	Autor: SiK
	Fecha: 2026-08-27

	dev11: único L1 de los 13 que seguía al 100% en `unclassified_modded`
	tras dev10 - nunca se había escrito un bloque para él. Confianza 30 por
	nombre, mismo criterio débil que Alimentos/Hogar-ocio/Supervivencia -
	sin tag oficial de "es un contenedor" confirmado.

	REORDENADO al ÚLTIMO bloque de identidad, justo antes de Materiales
	(débil) (dev12, hallazgo de sistemas sobre dev11: registrado tras
	Hogar-ocio en dev11, un contenedor genérico ROBABA identidades más
	específicas registradas después - bolsas de semillas a Agricultura,
	cajas de munición a Combate, sacos de dormir/cajas de trampas a
	Supervivencia, cajas de utilidad a Vehículos). Ahora solo reclama lo que
	NINGÚN otro bloque de identidad más específico ya reclamó - mismo
	criterio ya aplicado a Materiales desde dev6. Ver GS_NativeClassifier.lua
	para el orden real.

	Cubre `portable`/`liquid`/`special` (§5 grupo 7) y una excepción
	puntual `wearable/backpack` (ver más abajo). Objetos EQUIPABLES (que sí
	resolvieron BodyLocation) se excluyen - ya los reclamó Ropa antes en la
	cadena.
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

-- dev27: la excepcion de mochilas (containers/wearable/backpack, dev12) se
-- retira de aqui - "mochila o bolsa vestible se busca primariamente en
-- Ropa/Equipamiento" (decision de sistemas). Ver
-- GS_NativeClassifierClothing.lua, que ahora reclama estos tipos ANTES de
-- que este bloque los vea (Ropa se registra antes que Contenedores en
-- GS_NativeClassifier.lua).

local PORTABLE_TOKENS = toSet({ "bag", "box", "case", "briefcase", "cooler", "suitcase", "crate", "chest" })
-- BUG REAL cerrado (2026-08-27, hallazgo de sistemas sobre dev11): "jar"/
-- "bucket" afirmaban "líquido" sin evidencia real - Base.CookieJar no es
-- liquido, Base.HalloweenCandyBucket no es liquido, un cubo lleno de
-- cemento/yeso tiene una identidad de contenido mas importante. Solo los
-- tokens que SI son señal razonable de fluido real quedan en "liquid";
-- jar/bucket bajan a "portable" generico (contenedor sin afirmar que
-- contiene liquido).
local LIQUID_TOKENS = toSet({ "bottle", "canteen", "flask", "jug", "keg" })
local GENERIC_PORTABLE_TOKENS = toSet({ "jar", "bucket" })
local SPECIAL_TOKENS = toSet({ "wallet", "purse", "firstaidkit" })

-- Mismo criterio que Materiales/Alimentos/Conocimiento: un mueble/aparato
-- colocable ("Mov_...") o un arma real nunca deberian ser "contenedor" solo
-- por compartir una palabra (p.ej. "Cooler" como electrodomestico grande,
-- no una nevera portatil de camping). "lid" (Base.JarLid) y "debug"/"test"
-- (Base.BucketWaterDebug, tipos internos) añadidos dev12. "opener" añadido
-- dev13 (hallazgo de sistemas: Base.BottleOpener/BottleOpener_Keychain no
-- son contenedores solo porque el nombre contenga "bottle").
local CONTAINER_EXCLUDE_TOKENS = toSet({ "mov", "machine", "vending", "lid", "debug", "test", "opener" })

---@param fullType string
---@param si table|nil
---@return table|nil primaryPath
---@return table|nil facets
---@return table|nil attributes
---@return table|nil evidence
local function classifyContainers(fullType, si)
	if not si then return nil end

	local weaponCats = U.getWeaponCategories(si)
	if weaponCats and weaponCats.isEmpty and U.safeCall(function() return weaponCats:isEmpty() end) == false then
		return nil
	end

	local tokens = U.tokenize(U.typeName(si))
	if #tokens == 0 then return nil end
	if U.hasAnyToken(tokens, CONTAINER_EXCLUDE_TOKENS) then return nil end

	if isWearable(si) then return nil end

	-- dev14 (probe controlado de sistemas, confirmado via javap): ScriptItem
	-- hereda `containsComponent(ComponentType)` de GameEntityScript - señal
	-- ESTATICA real de fluido, confirmada en Base.Bucket/Canteen (SI lo
	-- tienen) y ausente en Base.CookieJar/JarLid/BottleOpener* (ya excluidos
	-- de todos modos). `hasFluidContainerComponent` devuelve `nil` si la API
	-- no esta disponible (degrada con seguridad a la heuristica de nombre de
	-- siempre), o `true`/`false` si se pudo determinar de verdad.
	local hasFluidComponent = U.hasFluidContainerComponent(si)
	if hasFluidComponent == true then
		return { l1 = "containers", l2 = "liquid", l3 = nil }, { containerForm = "liquid" }, {}, U.evidence("script_fluid_container_component", 100)
	end
	if hasFluidComponent == false then
		-- Componente confirmado AUSENTE - nunca "liquid" aunque el nombre lo
		-- sugiera (evita el mismo tipo de falso positivo que BottleOpener,
		-- con evidencia oficial en vez de una lista de exclusiones a mano).
		if U.hasAnyToken(tokens, LIQUID_TOKENS) then return nil end
	elseif U.hasAnyToken(tokens, LIQUID_TOKENS) then
		-- API no disponible (hasFluidComponent == nil) - cae a la
		-- heuristica de nombre de siempre, confianza baja.
		return { l1 = "containers", l2 = "liquid", l3 = nil }, { containerForm = "liquid" }, {}, U.evidence("name_containers_liquid", 30)
	end
	if U.hasAnyToken(tokens, SPECIAL_TOKENS) then
		return { l1 = "containers", l2 = "special", l3 = nil }, {}, {}, U.evidence("name_containers_special", 30)
	end
	if U.hasAnyToken(tokens, PORTABLE_TOKENS) then
		return { l1 = "containers", l2 = "portable", l3 = nil }, { containerForm = "bag_or_box" }, {}, U.evidence("name_containers_portable", 30)
	end
	if U.hasAnyToken(tokens, GENERIC_PORTABLE_TOKENS) then
		return { l1 = "containers", l2 = "portable", l3 = nil }, { containerForm = "jar_or_bucket" }, {}, U.evidence("name_containers_portable", 30)
	end

	-- BUG REAL cerrado (2026-08-27, hallazgo de sistemas sobre dev16): "empty
	-- demuestra que una variante está vacía, pero por sí solo no demuestra
	-- que el objeto sea un contenedor" - el fallback anterior reclamaba
	-- CUALQUIER "*Empty" sin más evidencia, incluidos Base.GardeningSprayEmpty
	-- (confirmado ItemType=base:normal, no container) y variantes visuales/
	-- coleccionables de mods de terceros (GroguCarriageEmpty). Confirmado
	-- leyendo items.txt real: Base.EmptySandbag SÍ es
	-- `ItemType=base:container`; Base.GardeningSprayEmpty es
	-- `ItemType=base:normal`. Ahora "empty" exige ADEMÁS esa confirmación -
	-- sin ItemType=base:container, se cede (nil) en vez de inventar un
	-- contenedor. Política del usuario: "un contenedor vacío se define por
	-- su contenedor" - el pool de este bloque son los REALMENTE
	-- confirmados como contenedor, no cualquier objeto con "Empty" en el
	-- nombre.
	if U.hasAnyToken(tokens, { empty = true }) and U.itemTypeLower(si) == "base:container" then
		return { l1 = "containers", l2 = "portable", l3 = nil }, { containerForm = "empty_variant" }, {}, U.evidence("name_containers_empty_variant", 30)
	end

	return nil
end

GlobalStorageSiK.NativeClassifier.registerBlock(classifyContainers, "containers")
