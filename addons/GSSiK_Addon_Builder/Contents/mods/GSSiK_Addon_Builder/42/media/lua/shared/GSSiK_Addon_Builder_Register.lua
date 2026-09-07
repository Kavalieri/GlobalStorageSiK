--[[
	GSSiK Addon Builder - Registro en el core
	Autor: SiK
	Fecha: 2025-06-27
]]

require "GSSiK_API"
require "GSSiK_Addon_Builder_Log"

--- Nombre de receta -> slug usado por su opcion propia
--- "Recipe_<slug>_RequireBook" (SandboxVars.GSSiK_Addon_Builder.*, no Core).
local RECIPE_NAME_TO_SLUG = {
	["Build GS Whiteboard Frame"] = "WhiteboardFrame",
	["Build GS Whiteboard Display Panel"] = "WhiteboardPanel",
	["Build GS Whiteboard Stylus"] = "WhiteboardStylus",
	["Build GS Digital Whiteboard"] = "DigitalWhiteboard",
	["Program GS Builder Install Disk"] = "BuilderDisk",
}

--- Resolutor que Core llama (GS_AddonRecipeTuning.lua) para decidir si una
--- receta de este addon exige manual - vive aqui, no en Core.
---@param recipeName string
---@return boolean
local function resolveRecipeBookRequirement(recipeName)
	local slug = RECIPE_NAME_TO_SLUG[recipeName]
	if slug then
		local addonConfig = SandboxVars and SandboxVars.GSSiK_Addon_Builder
		local v = addonConfig and addonConfig["Recipe_" .. slug .. "_RequireBook"]
		if v ~= nil then
			return v == true
		end
	end
	-- Abstain instead of reading Core-owned sandbox state. GSSiK.API returns
	-- this nil unchanged and Core applies its own configured fallback.
	return nil
end

local definition = {
	id = "Builder",
	modId = "GSSiK_Addon_Builder",
	-- Periferico: Pizarra Digital GS. Se ensambla a mano en el menu de
	-- crafteo vanilla (3 piezas + soldador + destornillador), igual patron
	-- que el lector de disquetes del Core y la impresora 3D del addon Craft.
	itemType = "GSSiK_Addon_Builder.GS_DigitalWhiteboard",
	magazineType = "GSSiK_Addon_Builder.GS_Manual_Builder",
	-- Disquete de instalacion propio del addon: se conserva al instalar, no
	-- se consume. Se suma al lector universal GS_TerminalReader (siempre
	-- exigido, sea cual sea el addon).
	installDiskItem = "GSSiK_Addon_Builder.GS_FloppyDisk_Builder",
	diskProgram = {
		id = "builder",
		recipeName = "Program GS Builder Install Disk",
		manualItem = "GSSiK_Addon_Builder.GS_Manual_Builder_DiskProgram",
		outputItem = "GSSiK_Addon_Builder.GS_FloppyDisk_Builder",
		menuTextKey = "IGUI_GS_ProgramBuilderDiskMenu",
		iconPath = "media/textures/Item_GS_FloppyDisk_Builder.png",
		descKey = "IGUI_GS_ProgramBuilderDiskDesc",
	},
	moduleRecipeName = "Build GS Digital Whiteboard",
	moduleSkillLevel = 5,
	moduleCraftTime = 110,
	-- Icono REAL del periferico (pizarra digital) para la bahia de expansion -
	-- ver nota identica en GSSiK_Addon_Tablet_Register.lua. El icono de la
	-- pestaña Build del terminal usa el derivado canónico propiedad del addon,
	-- suministrado al Tab neutral por el cliente sin acoplar Core a este asset.
	iconPath = "media/textures/Item_GS_DigitalWhiteboard.png",
	-- Ingredientes del boton "crafteo instantaneo" de la pestaña Addons: el
	-- montaje final consume las 3 piezas ya fabricadas (cada una con receta
	-- y materiales reales propios), no materia prima suelta.
	moduleIngredients = {
		{ item = "GSSiK_Addon_Builder.GS_DigitalWhiteboard_Frame", count = 1 },
		{ item = "GSSiK_Addon_Builder.GS_DigitalWhiteboard_Screen", count = 1 },
		{ item = "GSSiK_Addon_Builder.GS_DigitalWhiteboard_Stylus", count = 1 },
	},
	recipeNames = {
		"Build GS Whiteboard Frame",
		"Build GS Whiteboard Display Panel",
		"Build GS Whiteboard Stylus",
		"Build GS Digital Whiteboard",
		"Program GS Builder Install Disk",
	},
	titleKey = "IGUI_GS_AddonBuilderTitle",
	descKey = "IGUI_GS_AddonBuilderDesc",
	workshopId = "3752437465",
	resolveRecipeBookRequirement = resolveRecipeBookRequirement,
}

-- The shared file can run before the client world has completed its addon
-- bootstrap. Re-applying the same public definition at world start is
-- idempotent and reconciles the dedicated-client registry without touching
-- Core internals.
local function registerDefinition()
	return GSSiK.API.Addon.register(definition)
end

local registered, registerCode = registerDefinition()

if not registered then
	error("GSSiK Addon Builder registration failed: " .. tostring(registerCode))
end

if Events and Events.OnGameStart then
	Events.OnGameStart.Add(function()
		local ok, code = registerDefinition()
		if not ok then
			GSSiK_Addon_Builder.Log.debug("Lifecycle",
				"registration_reconcile_failed code=" .. tostring(code))
		end
	end)
end
