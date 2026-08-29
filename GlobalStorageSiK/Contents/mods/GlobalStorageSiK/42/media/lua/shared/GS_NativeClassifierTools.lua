--[[
	GlobalStorageSiK - Clasificador de bloque: Herramientas
	Autor: SiK
	Fecha: 2026-08-27

	Registrado ANTES que Combate (pedido explícito: "si algo es herramienta
	y arma a la vez, gana herramienta" - el primer bloque que reclama un
	fullType se queda con él).

	Por tags oficiales confirmados (§3.2 del documento) - confianza alta
	(95, tag oficial específico). Una herramienta con varios usos reales
	(p.ej. un hacha: HAMMER no aplica pero WeaponCategory.AXE sí - eso ya lo
	reclama este bloque como "general/cutting" si tuviera tag de corte, o
	si no lo reclama nadie aquí, cae a Combate) usa el primer tag que
	coincida en este orden fijo como ruta primaria; el resto queda pendiente
	de facetas adicionales en una ronda posterior.
]]

require "GS_NativeClassifierApi"
require "GS_NativeClassifierUtils"

local U = GlobalStorageSiK.NativeClassifierUtils

-- Ancla exacta DEV32.3: el catálogo vanilla identifica el soplete como
-- herramienta de metalurgia incluso cuando el tag de la partida no está
-- disponible todavía durante el arranque del catálogo.
local EXACT = {
	["Base.BlowTorch"] = { l2 = "construction", l3 = "metalworking" },
}

--- Orden fijo de comprobación: { l2, l3, lista de nombres de ItemTag.XXX }.
--- Los nombres de tag son constantes reales del motor (confirmadas en
--- Documentacion/GSSiK_Taxonomia_Nativa_Analisis.md §3.2) - se resuelven
--- via ItemTag.<NOMBRE> directamente (mismo patrón ya usado en
--- GS_NetworkReadAction.lua con ItemTag.PICTURE/PICTUREBOOK).
local TAG_RULES = {
	{ l2 = "construction", l3 = "carpentry", tags = { "SAW", "SMALL_SAW", "CARPENTRY_CHISEL" } },
	{ l2 = "construction", l3 = "metalworking", tags = { "BLOW_TORCH", "METALWORKING_CHISEL" } },
	{ l2 = "construction", l3 = "masonry", tags = { "MASONS_CHISEL", "PLASTER_TROWEL" } },
	{ l2 = "maintenance", l3 = "mechanic", tags = { "WRENCH", "PIPE_WRENCH", "LUG_WRENCH", "PLIERS", "TONGS", "SCREWDRIVER" } },
	{ l2 = "maintenance", l3 = "sewing", tags = { "SEWING_NEEDLE", "KNITTING_NEEDLES" } },
	{ l2 = "general", l3 = "striking", tags = { "HAMMER", "SLEDGEHAMMER" } },
	{ l2 = "general", l3 = "cutting", tags = { "SHARP_KNIFE" } },
	{ l2 = "harvesting", l3 = "butchery", tags = { "KNAPPING_TOOL", "FLESHING_TOOL" } },
	{ l2 = "harvesting", l3 = "fishing", tags = { "FISHING_ROD", "FISHING_NET" } },
}

---@param names string[]
---@return table lista de ItemTag reales (omite los que no existan como constante)
local function resolveTagList(names)
	local out = {}
	for i = 1, #names do
		local tag = ItemTag and ItemTag[names[i]]
		if tag then out[#out + 1] = tag end
	end
	return out
end

-- Resueltos UNA vez al cargar el fichero, no en cada clasificacion.
local RESOLVED_RULES = {}
for i = 1, #TAG_RULES do
	local rule = TAG_RULES[i]
	RESOLVED_RULES[i] = { l2 = rule.l2, l3 = rule.l3, tags = resolveTagList(rule.tags) }
end

---@param fullType string
---@param si table|nil
---@return table|nil primaryPath
---@return table|nil facets
---@return table|nil attributes
---@return table|nil evidence
-- BUG REAL cerrado Y REVERTIDO (2026-08-27, dev8 → dev9): dev8 hizo que
-- machetes/kukris/tanto tacticos con tag SHARP_KNIFE cedieran el turno a
-- Combate si tambien tenian WeaponCategory. Sistemas revisó esa decisión
-- con la regla autoritativa final del proyecto: "la ruta primaria responde
-- a dónde buscaría PRIMERO este objeto un jugador que organiza un
-- almacén, no a si puede equiparse y causar daño" - un tag oficial
-- confirmado (SHARP_KNIFE) es evidencia de PROPÓSITO más fuerte que
-- WeaponCategory (que solo demuestra capacidad ofensiva). Provocó además
-- una regresión real medida: Herramientas bajó de 114 a 55 objetos.
-- REVERTIDO: la regla de corte vuelve a ganar SIEMPRE que tenga el tag,
-- conservando la capacidad de combate como faceta (`weaponCapability`/
-- `weaponCategories`), nunca cediendo la ruta primaria. Sistemas debe
-- resolver casos de arma pura mal etiquetada (si los hay) con excepciones
-- EXACTAS por fullType, nunca con una regla global de precedencia.
local function classifyTools(fullType, si)
	local exact = EXACT[fullType]
	if exact then
		return { l1 = "tools", l2 = exact.l2, l3 = exact.l3 }, {}, {}, U.evidence("exact_fulltype_tool", 100)
	end
	if not si then return nil end
	for i = 1, #RESOLVED_RULES do
		local rule = RESOLVED_RULES[i]
		if #rule.tags > 0 and U.hasAnyTag(si, rule.tags) then
			local facets = {}
			local weaponCats = U.getWeaponCategories(si)
			if weaponCats and weaponCats.isEmpty and U.safeCall(function() return weaponCats:isEmpty() end) == false then
				facets.weaponCapability = true
			end
			return
				{ l1 = "tools", l2 = rule.l2, l3 = rule.l3 },
				facets,
				{},
				U.evidence("script_tag_tool", 95)
		end
	end
	return nil
end

GlobalStorageSiK.NativeClassifier.registerBlock(classifyTools, "tools")
