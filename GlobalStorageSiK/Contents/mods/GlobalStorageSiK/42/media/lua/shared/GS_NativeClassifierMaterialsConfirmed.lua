--[[
	GlobalStorageSiK - Clasificador de bloque: Materiales confirmados (lista exacta)
	Autor: SiK
	Fecha: 2026-08-27

	Nuevo en dev7 (hallazgo de sistemas sobre dev6): "MetalBar"/"SteelBar" son
	genuinamente materia prima, pero Combate los reclamaba antes como arma
	contundente (WeaponCategory.BLUNT/SMALL_BLUNT) porque el motor SÍ permite
	golpear con ellos. La solución no es reordenar Combate/Materiales otra
	vez (eso rompería a `Base.Sword`/`Base.Axe`, que ahora SÍ deben ganar
	Combate) - es dar a un pequeño conjunto de materia prima confirmada una
	identidad tan fuerte como los objetos propios de GS (coincidencia EXACTA
	por fullType, confianza 90) y registrarla ANTES que Combate/Herramientas,
	para que decida primero sin tocar el resto del orden.

	Lista deliberadamente pequeña y curada a mano (nunca un token genérico)
	- cada entrada es un fullType real confirmado en el catálogo durante la
	revisión de dev5/dev6. Ampliar esta lista es la vía correcta cuando
	sistemas detecte otro caso "material real que el motor también permite
	usar como arma", en vez de tocar la precedencia entre bloques.
]]

require "GS_NativeClassifierApi"
require "GS_NativeClassifierUtils"

local U = GlobalStorageSiK.NativeClassifierUtils

-- fullType exacto -> ruta Materials. Dataset centralizado: estos objetos
-- vanilla normales no dependen de traducciones ni de heurísticas nominales.
local EXACT = {
	["Base.MetalBar"] = "metal",
	["Base.SteelBar"] = "metal",
	["Base.SteelBarHalf"] = "metal",
	["Base.ScrapMetal"] = "metal",
	["Base.MetalSheet"] = "metal",
	["Base.MetalPipe"] = "metal",
	-- dev9 (hallazgo de sistemas sobre dev8): "MetalPipe_Broken" y las
	-- barras/planchas de madera son materia prima real tan genuina como
	-- MetalBar/SteelBar - Combate las reclamaba como arma improvisada por
	-- WeaponCategory.BLUNT antes de que existiera esta lista exacta.
	["Base.MetalPipe_Broken"] = "metal",
	["Base.Plank"] = "wood",
	["Base.LargePlank"] = "wood",
	["Base.Plank_Nails"] = "wood",
	["Base.Plank_Broken"] = "wood",
	["Base.LongStick"] = "wood",
	["Base.LongStick_Broken"] = "wood",
	["Base.WoodenStick2"] = "wood",
	["Base.WoodenStick_Broken"] = "wood",
	["Base.TreeBranch2"] = "wood",
	["Base.LargeBranch"] = "wood",
	["Base.Clay"] = "mineral",
	["Base.ConcretePowder"] = "mineral",
	["Base.StoneBlock"] = "mineral",
	["Base.LargeStone"] = "mineral",
	["Base.Stone2"] = "mineral",
	["Base.Thread"] = "textile",
	["Base.Thread_Sinew"] = "textile",
	["Base.Thread_Aramid"] = "textile",
	["Base.LeatherStrips"] = "leather_hide",
	["Base.LeatherStripsDirty"] = "leather_hide",
	["Base.LeatherStripsBundle"] = "leather_hide",
	["Base.DuctTape"] = { l2 = "component", l3 = "adhesive" },
	["Base.Nails"] = { l2 = "component", l3 = "fastener" },
	["Base.NailsCarton"] = { l2 = "component", l3 = "fastener" },
	["Base.NutsBolts"] = { l2 = "component", l3 = "fastener" },
	["Base.Screws"] = { l2 = "component", l3 = "fastener" },
	["Base.ScrewsCarton"] = { l2 = "component", l3 = "fastener" },
	["Base.WeldingRods"] = { l2 = "component", l3 = "welding_consumable" },
}

---@param fullType string
---@param si table|nil sin usar - coincidencia solo por fullType
---@return table|nil primaryPath
---@return table|nil facets
---@return table|nil attributes
---@return table|nil evidence
local function classifyMaterialsConfirmed(fullType, si)
	local exact = EXACT[fullType]
	if not exact then return nil end
	local l2 = type(exact) == "table" and exact.l2 or exact
	local l3 = type(exact) == "table" and exact.l3 or nil
	return
		{ l1 = "materials", l2 = l2, l3 = l3 },
		{},
		{},
		U.evidence("exact_fulltype_material", 90)
end

GlobalStorageSiK.NativeClassifier.registerBlock(classifyMaterialsConfirmed, "materials_confirmed")
