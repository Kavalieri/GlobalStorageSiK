--[[
	GlobalStorageSiK - Clasificador de bloque: Materiales
	Autor: SiK
	Fecha: 2026-08-27

	REESCRITO POR COMPLETO 2026-08-27 (dev6, tras la revisión de precisión de
	sistemas sobre dev5). Dos hallazgos críticos cerrados:

	1. **"base:hasmetal" no es identidad, es composición.** El tag confirma
	   que el objeto CONTIENE metal, nunca que SEA una materia prima. La
	   versión anterior lo usaba como reclamo primario (confianza 95) y por
	   eso ganaba sobre espadas, revólveres, munición, instrumental
	   quirúrgico y ollas - todos ellos objetos con identidad propia mucho
	   más fuerte que "contiene metal". Ahora el tag es SOLO una faceta de
	   composición (`facets.composition.metal`), nunca decide la ruta
	   primaria por sí solo - la ruta L2 "metal" exige evidencia de NOMBRE
	   real (mismo criterio débil que el resto), el tag es solo apoyo.
	2. **Namespace contaminando el nombre + subcadenas sin límite.** La
	   versión anterior buscaba sobre el fullType COMPLETO (namespace
	   incluido) con `find(needle, 1, true)` - de ahí "log" dentro de
	   "Catalog"/"Cologne", "stick" dentro de "Lipstick"/"Nightstick", "rag"
	   dentro de "Foraging"/"Fragment". Ahora usa
	   `NativeClassifierUtils.typeName()` (sin el módulo) tokenizado por
	   límite CamelCase/guion bajo, comparado por TOKEN EXACTO.

	**Reordenado a ÚLTIMO bloque** (ver GS_NativeClassifier.lua): con
	Herramientas/Ropa/Medicina/Hogar-ocio/Combate resolviendo identidad
	primero, Materiales solo reclama lo que NINGÚN otro bloque de identidad
	ya reclamó - vuelve a ser un catch-all honesto de materia prima, no un
	competidor de identidad. La regla original del usuario ("si es material
	Y arma, gana material") sigue viva en espíritu: un objeto que es
	GENUINAMENTE materia prima (un tronco, un trozo de cuero) nunca debería
	perder frente a una clasificación de arma - pero eso ya no puede pasar
	porque Materiales ya no reclama objetos con identidad propia fuerte.

	Objetos EQUIPABLES se excluyen (igual que antes).
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

-- BUG REAL cerrado (2026-08-27): "rock"/"glass" quitados de Mineral - Base.
-- RockCandy (comida) y Base.GlassChampagne/DrinkingGlass/GlassWine/
-- GlassTumbler/LanternGlass (vajilla/iluminación, no materia prima de
-- vidrio) eran falsos positivos reales confirmados por sistemas. El vidrio
-- en bruto real (GlassPanel, BrokenGlass, GlassBlowingPipe) es un conjunto
-- pequeño y se deja pendiente de una lista exacta en vez de un token
-- genérico que sobre-reclama.
local METAL_TOKENS = toSet({ "metal", "steel", "scrap", "ingot", "wire", "rebar" })
local WOOD_TOKENS = toSet({ "wood", "log", "plank", "twig", "branch", "stick", "firewood" })
local TEXTILE_TOKENS = toSet({ "cloth", "denim", "fabric", "thread", "yarn", "rag", "cotton" })
local LEATHER_HIDE_TOKENS = toSet({ "leather", "hide", "pelt" })
local MINERAL_TOKENS = toSet({ "stone", "clay", "cement", "concrete" })
local ORGANIC_TOKENS = toSet({ "bone", "feather", "tendon", "organ", "fat", "gut" })

-- BUG REAL cerrado (2026-08-27, hallazgo de sistemas sobre dev6): "materia
-- prima" y "producto terminado hecho de esa materia" seguian mezclados -
-- Base.ToolRoll_Leather/Wallet_Hide/Bag_CrudeLeatherBag (cuero ya cosido en
-- una herramienta/contenedor), Base.RiceBowlClay/ClayPlate/ClayMug/
-- CanteenClay (vajilla de arcilla YA cocida), Base.Mov_ConcreteMixer/
-- Mov_WoodSpeakerCabinet/Mov_MirrorWood (mueble/electrodomestico
-- ambientado, "Mov_" = objeto colocable), Base.DehydratedMeatStick (comida,
-- "stick" aqui es un palito de carne, no un palo de madera) eran todos
-- objetos terminados, nunca insumos. Exclusion explicita por token de
-- "producto terminado" - si aparece CUALQUIERA de estos, Materiales no
-- reclama nada (deja unclassified_modded en vez de un insumo falso, mas
-- honesto que forzar una ruta equivocada). Lista pequeña y ampliable a
-- mano, igual que GS_NativeClassifierMaterialsConfirmed.lua en la
-- direccion opuesta.
local FINISHED_GOODS_TOKENS = toSet({
	"bag", "wallet", "satchel", "toolroll",
	"bowl", "plate", "mug", "jar", "canteen", "goblet", "bucket",
	"mixer", "cabinet", "mirror", "speaker",
	"mov", "meat",
})

---@param fullType string
---@param si table|nil
---@return table|nil primaryPath
---@return table|nil facets
---@return table|nil attributes
---@return table|nil evidence
local function classifyMaterials(fullType, si)
	if not si or isWearable(si) then return nil end

	local tokens = U.tokenize(U.typeName(si))
	if U.hasAnyToken(tokens, FINISHED_GOODS_TOKENS) then return nil end

	-- Composicion (nunca identidad): el tag oficial "base:hasmetal" solo se
	-- adjunta como faceta de apoyo, decida quien decida la ruta primaria de
	-- este mismo bloque.
	local composition = nil
	local hasMetalTag = U.tagByLocation("base", "hasmetal")
	if hasMetalTag and U.hasTag(si, hasMetalTag) then
		composition = { metal = true }
	end

	if #tokens == 0 then return nil end

	---@param l2 string
	---@param source string
	---@return table primaryPath
	---@return table facets
	---@return table attributes
	---@return table evidence
	local function result(l2, source)
		local facets = {}
		if composition then facets.composition = composition end
		return
			{ l1 = "materials", l2 = l2, l3 = nil },
			facets,
			{},
			U.evidence(source, 30)
	end

	if U.hasAnyToken(tokens, METAL_TOKENS) then
		return result("metal", "name_metal")
	end
	if U.hasAnyToken(tokens, LEATHER_HIDE_TOKENS) then
		return result("leather_hide", "name_leather")
	end
	if U.hasAnyToken(tokens, TEXTILE_TOKENS) then
		return result("textile", "name_textile")
	end
	if U.hasAnyToken(tokens, MINERAL_TOKENS) then
		return result("mineral", "name_mineral")
	end
	if U.hasAnyToken(tokens, ORGANIC_TOKENS) then
		return result("organic", "name_organic")
	end
	if U.hasAnyToken(tokens, WOOD_TOKENS) then
		return result("wood", "name_wood")
	end

	return nil
end

GlobalStorageSiK.NativeClassifier.registerBlock(classifyMaterials, "materials")
