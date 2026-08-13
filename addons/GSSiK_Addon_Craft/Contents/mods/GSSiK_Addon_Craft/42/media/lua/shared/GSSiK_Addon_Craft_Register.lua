--[[

	GSSiK Addon Craft - Registro en el core

	Autor: SiK

	Fecha: 2025-06-27

]]



require "GS_AddonRegistry"
require "GS_DiskProgramming"
require "GS_Sandbox"

--- Nombre de receta -> slug usado por su opcion propia
--- "Recipe_<slug>_RequireBook" (SandboxVars.GSSiK_Addon_Craft.*, no Core).
local RECIPE_NAME_TO_SLUG = {
	["Build GS Printer Frame"] = "PrinterFrame",
	["Build GS Printer Extruder Head"] = "PrinterExtruderHead",
	["Build GS Printer Control Board"] = "PrinterControlBoard",
	["Build GS 3D Printer"] = "Printer3D",
	["Program GS Craft Install Disk"] = "CraftDisk",
}

--- Resolutor que Core llama (GS_AddonRecipeTuning.lua) para decidir si una
--- receta de este addon exige manual - vive aqui, no en Core, porque solo
--- este addon conoce sus propios slugs y su propio namespace de sandbox.
---@param recipeName string
---@return boolean
local function resolveRecipeBookRequirement(recipeName)
	local slug = RECIPE_NAME_TO_SLUG[recipeName]
	if slug then
		local v = SandboxVars.GSSiK_Addon_Craft and SandboxVars.GSSiK_Addon_Craft["Recipe_" .. slug .. "_RequireBook"]
		if v ~= nil then
			return v == true
		end
	end
	return GlobalStorageSiK.Sandbox.requireRecipeBooks()
end

GlobalStorageSiK.DiskProgramming.registerProgram("craft", {
	recipeName = "Program GS Craft Install Disk",
	manualItem = "GSSiK_Addon_Craft.GS_Manual_Craft_DiskProgram",
	outputItem = "GSSiK_Addon_Craft.GS_FloppyDisk_Craft",
	menuTextKey = "IGUI_GS_ProgramCraftDiskMenu",
})

GlobalStorageSiK.AddonRegistry.register({

	id = "Craft",

	modId = "GSSiK_Addon_Craft",

	-- Periferico: Impresora 3D GS. Se ensambla a mano en el menu de crafteo
	-- vanilla (3 piezas + soldador + destornillador, igual patron que el
	-- lector de disquetes del Core), no de un tiron con materia prima suelta.
	itemType = "GSSiK_Addon_Craft.GS_Printer3D",

	magazineType = "GSSiK_Addon_Craft.GS_Manual_Craft",

	-- Disquete de instalacion propio del addon: se conserva al instalar, no
	-- se consume (igual que GS_FloppyDisk del terminal). Se suma al lector
	-- universal GS_TerminalReader, que tambien hace falta siempre.
	installDiskItem = "GSSiK_Addon_Craft.GS_FloppyDisk_Craft",

	moduleRecipeName = "Build GS 3D Printer",

	moduleSkillLevel = 5,

	moduleCraftTime = 120,

	-- Icono REAL del periferico (impresora 3D) para la bahia de expansion -
	-- ver nota identica en GSSiK_Addon_Tablet_Register.lua. El icono de la
	-- pestaña Craft del terminal sigue siendo GS_TabCraft.png, definido
	-- aparte en GSSiK_Addon_Craft_Client.lua - no se toca, es correcto.
	iconPath = "media/textures/Item_GS_Printer3D.png",

	-- Ingredientes del boton "crafteo instantaneo" de la pestaña Addons:
	-- el montaje final consume las 3 piezas ya fabricadas (cada una con su
	-- propia receta y materiales reales, ver gssik_addon_craft_recipes.txt),
	-- no materia prima suelta - evita que este atajo salte el paso de
	-- fabricar cada componente.
	moduleIngredients = {

		{ item = "GSSiK_Addon_Craft.GS_Printer3D_Frame", count = 1 },

		{ item = "GSSiK_Addon_Craft.GS_Printer3D_ExtruderHead", count = 1 },

		{ item = "GSSiK_Addon_Craft.GS_Printer3D_ControlBoard", count = 1 },

	},

	recipeNames = {

		"Build GS Printer Frame",

		"Build GS Printer Extruder Head",

		"Build GS Printer Control Board",

		"Build GS 3D Printer",

		"Program GS Craft Install Disk",

	},

	titleKey = "IGUI_GS_AddonCraftTitle",

	descKey = "IGUI_GS_AddonCraftDesc",

	workshopId = "3752379654",

	resolveRecipeBookRequirement = resolveRecipeBookRequirement,

})

