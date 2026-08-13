--[[
	GlobalStorageSiK - Registro del Lector (GS Floppy Drive) como addon
	Autor: SiK
	Fecha: 2026-08-12
	Descripción: El Lector se craftea y se instala en red exactamente igual
	que Tablet/Craft/Builder (receta -> modulo -> disquete de instalacion,
	sin consumirse - ver moduleRecipeName/installDiskItem abajo), asi que
	vive en el mismo AddonRegistry en vez de en un sistema aparte
	(GS_FloppyDriveNetwork.lua, ahora superseded). Requiere require
	"GS_AddonRegistry" ya cargado - por eso este fichero NO se require desde
	GS_AddonRegistry.lua ni desde GS_FloppyDriveNetwork.lua (evitaria el
	mismo ciclo de requires que ya documentaba GS_FloppyDriveNetwork.lua),
	sino desde GS_Addons.lua, que ya garantiza cargar despues del registro.
]]

require "GS_AddonRegistry"
require "GS_Config"
require "GS_Sandbox"

--- Igual criterio que el resto de addons: opcion propia de la receta si
--- esta definida, si no cae al interruptor global RequireRecipeBooks.
---@param recipeName string
---@return boolean
local function resolveRecipeBookRequirement(recipeName)
	if recipeName ~= "Build GS Terminal Reader" then
		return GlobalStorageSiK.Sandbox.requireRecipeBooks()
	end
	local v = SandboxVars.GlobalStorageSiK and SandboxVars.GlobalStorageSiK.Recipe_TerminalReader_RequireBook
	if v ~= nil then
		return v == true
	end
	return GlobalStorageSiK.Sandbox.requireRecipeBooks()
end

GlobalStorageSiK.AddonRegistry.register({
	id = "Reader",
	modId = "GlobalStorageSiK",
	itemType = GlobalStorageSiK.Config.ITEM_TERMINAL_READER,
	magazineType = "GlobalStorageSiK.GS_Manual_TerminalUnit",
	installDiskItem = GlobalStorageSiK.Config.ITEM_FLOPPY_DRIVE_INSTALL_DISK,
	moduleRecipeName = "Build GS Terminal Reader",
	moduleSkillLevel = 6,
	moduleCraftTime = 300,
	iconPath = "media/textures/Item_GS_TerminalReader.png",
	moduleIngredients = {
		{ item = "GlobalStorageSiK.GS_ReaderCasing", count = 1 },
		{ item = "GlobalStorageSiK.GS_ReaderCircuit", count = 1 },
		{ item = "GlobalStorageSiK.GS_ReaderAntenna", count = 1 },
	},
	recipeNames = {
		"Build GS Terminal Reader",
		"Build GS Reader Casing",
		"Build GS Reader Circuit Board",
		"Build GS Reader Antenna",
		"Program GS Floppy Drive Network Disk",
	},
	titleKey = "IGUI_GS_AddonReaderTitle",
	descKey = "IGUI_GS_AddonReaderDesc",
	workshopId = "3750612158",
	resolveRecipeBookRequirement = resolveRecipeBookRequirement,
})
