--[[
	GSSiK_Addon_Tablet - Comprobaciones de receta (OnTest)
	Cada receta de este addon tiene su propia opcion de sandbox EN SU PROPIO
	namespace (SandboxVars.GSSiK_Addon_Tablet.Recipe_<Slug>_Enable) - antes
	vivia en el namespace de Core por comodidad, pero eso mezclaba
	configuracion de addon dentro de Core; cada addon debe configurarse
	desde su propio sandbox. Default true si la opcion no existe
	(compatibilidad / addon aun sin sandbox-options.txt actualizado).
]]

require "GS_Sandbox"

GSSiK_Addon_Tablet_RecipeTests = GSSiK_Addon_Tablet_RecipeTests or {}

local RECIPE_SLUGS = {
	"AntennaDish", "AntennaTransmitter", "WifiChipT1", "WifiAntenna",
	"WifiChipT2", "WifiAntennaT2", "WifiChipT3", "WifiAntennaT3",
	"TabletScreen", "TabletBattery", "Tablet", "CraftTabletModule", "CraftTablet",
	"BuilderTabletModule", "BuilderTablet", "MasterTabletCore", "MasterTablet", "TabletDisk",
}

for i = 1, #RECIPE_SLUGS do
	local slug = RECIPE_SLUGS[i]
	GSSiK_Addon_Tablet_RecipeTests["Recipe_" .. slug .. "_Enable"] = function(recipe, character)
		if not SandboxVars.GSSiK_Addon_Tablet then return true end
		local v = SandboxVars.GSSiK_Addon_Tablet["Recipe_" .. slug .. "_Enable"]
		if v == nil then return true end
		return v == true
	end
end
