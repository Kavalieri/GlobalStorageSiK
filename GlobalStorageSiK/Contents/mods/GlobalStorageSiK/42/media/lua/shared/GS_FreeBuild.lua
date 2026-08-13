--[[

	GlobalStorageSiK - Construcción gratuita (sandbox) — ver GS_RecipeTuning

	Autor: SiK

	Fecha: 2025-06-24

]]



require "GS_RecipeTuning"
require "GS_AddonRecipeTuning"



GlobalStorageSiK.FreeBuild = GlobalStorageSiK.FreeBuild or {}



GlobalStorageSiK.FreeBuild.RECIPE_NAMES = {
	"Build GS Terminal Unit",
}

--- Aplica parches de recetas (delegado a RecipeTuning).
function GlobalStorageSiK.FreeBuild.applyRecipePatches()
	GlobalStorageSiK.RecipeTuning.apply()
	GlobalStorageSiK.AddonRecipeTuning.apply()
end



Events.OnGameStart.Add(GlobalStorageSiK.FreeBuild.applyRecipePatches)

