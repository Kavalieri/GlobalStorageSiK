--[[
	GSSiK Addon Multimedia - Registro en el core

	Autor: SiK

	Fecha: 2026-09-09
]]

require "GSSiK_API"
local Log = require "GSSiK_Addon_Multimedia_Log"

local definition = {
	id = "Multimedia",
	modId = "GSSiK_Addon_Multimedia",
	-- Reproductor GS Multimedia; persistent item/recipe IDs stay compatible.
	itemType = "GSSiK_Addon_Multimedia.GS_VHSController",
	magazineType = "GSSiK_Addon_Multimedia.GS_Manual_Multimedia",
	-- Disquete de instalacion propio del addon: se conserva al instalar,
	-- no se consume (como los discos del Core).
	installDiskItem = "GSSiK_Addon_Multimedia.GS_FloppyDisk_Multimedia",
	diskProgram = {
		id = "multimedia",
		recipeName = "Program GS Multimedia Install Disk",
		manualItem = "GSSiK_Addon_Multimedia.GS_Manual_Multimedia_DiskProgram",
		outputItem = "GSSiK_Addon_Multimedia.GS_FloppyDisk_Multimedia",
		iconPath = "media/textures/Item_GS_FloppyDisk_Multimedia.png",
		menuTextKey = "IGUI_GS_ProgramMultimediaDiskMenu",
		titleKey = "IGUI_GS_ProgramMultimediaDiskTitle",
		descKey = "IGUI_GS_ProgramMultimediaDiskDesc",
	},
	moduleRecipeName = "Build GS VHS Controller",
	moduleSkillLevel = 3,
	moduleCraftTime = 110,
	moduleIngredients = {
		{ item = "GSSiK_Addon_Multimedia.GS_VHSHousing", count = 1 },
		{ item = "GSSiK_Addon_Multimedia.GS_VHSTransport", count = 1 },
		{ item = "GSSiK_Addon_Multimedia.GS_VHSSignalBoard", count = 1 },
	},
	recipeNames = {
		"Build GS VHS Housing",
		"Build GS VHS Transport",
		"Build GS VHS Signal Board",
		"Build GS VHS Controller",
		"Program GS Multimedia Install Disk",
	},
	titleKey = "IGUI_GS_AddonMultimediaTitle",
	descKey = "IGUI_GS_AddonMultimediaDesc",
	-- Without an override Core applies its configured recipe-book policy.
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
	Log.error("Registration", "registration_failed=" .. tostring(registerCode))
end

if Events and Events.OnGameStart then
	Events.OnGameStart.Add(function()
		local ok, code = registerDefinition()
		if not ok then
			Log.error("Registration", "world_registration_failed=" .. tostring(code))
		end
	end)
end
