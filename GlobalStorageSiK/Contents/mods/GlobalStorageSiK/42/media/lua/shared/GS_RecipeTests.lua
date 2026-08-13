--[[
	GlobalStorageSiK - Comprobaciones de receta (OnTest)
	Descripcion: "Build GS Soldering Iron" es la unica pieza del mod pensada
	para quedar SIEMPRE oculta salvo que el jugador/admin decida explicitamente
	facilitar el mod (EnableSolderingIronCraft, false por defecto - el
	soldador sigue siendo solo de hallazgo salvo que se active). El nivel de
	habilidad (Electricity:7) es FIJO en el script, igual que el resto de
	recetas del mod - se probo un nivel dinamico por sandbox pero no mostraba
	la etiqueta de nivel en el menu de crafteo, dejando al jugador sin forma
	de ver el requisito. Se prefiere consistencia visual.
]]

require "GS_Sandbox"

GS_RecipeTests = GS_RecipeTests or {}

---@param recipe any
---@param character IsoGameCharacter|nil
---@return boolean
function GS_RecipeTests.canCraftSolderingIron(recipe, character)
	return SandboxVars.GlobalStorageSiK ~= nil and SandboxVars.GlobalStorageSiK.EnableSolderingIronCraft == true
end

--[[
	Resto de recetas de Core: cada una tiene su propia opcion
	"Recipe_<Slug>_Enable" (sandbox, default true) que decide si la receta
	existe en el menu de crafteo o si el item queda solo de hallazgo. Se
	genera de forma generica para no repetir 12 funciones casi identicas.
]]
local CORE_RECIPE_SLUGS = {
	"PCTower", "Motherboard", "IOController", "Keyboard", "DesktopComputer",
	"TerminalReader", "ReaderCasing", "ReaderCircuit", "ReaderAntenna",
	"NetworkDisk", "UninstallDisk", "DriveDisk",
}

for i = 1, #CORE_RECIPE_SLUGS do
	local slug = CORE_RECIPE_SLUGS[i]
	GS_RecipeTests["Recipe_" .. slug .. "_Enable"] = function(recipe, character)
		if not SandboxVars.GlobalStorageSiK then return true end
		local v = SandboxVars.GlobalStorageSiK["Recipe_" .. slug .. "_Enable"]
		if v == nil then return true end
		return v == true
	end
end

--[[
	Los 3 componentes propios del soldador (Punta/Resistencia/Mango): igual
	que el resto, con su propia opcion "Recipe_<slug>_Enable" (default true),
	pero ademas supeditados a EnableSolderingIronCraft - no tiene sentido
	poder craftear piezas sueltas del soldador si el soldador en si sigue
	siendo solo de hallazgo (esa es la unica excepcion a "todo independiente"
	de todo el sistema, y es deliberada: son piezas de UNA receta concreta).
]]
local SOLDERING_PART_SLUGS = { "SolderingTip", "SolderingResistance", "SolderingHandle" }

for i = 1, #SOLDERING_PART_SLUGS do
	local slug = SOLDERING_PART_SLUGS[i]
	GS_RecipeTests["Recipe_" .. slug .. "_Enable"] = function(recipe, character)
		if not SandboxVars.GlobalStorageSiK or SandboxVars.GlobalStorageSiK.EnableSolderingIronCraft ~= true then
			return false
		end
		local v = SandboxVars.GlobalStorageSiK["Recipe_" .. slug .. "_Enable"]
		if v == nil then return true end
		return v == true
	end
end
