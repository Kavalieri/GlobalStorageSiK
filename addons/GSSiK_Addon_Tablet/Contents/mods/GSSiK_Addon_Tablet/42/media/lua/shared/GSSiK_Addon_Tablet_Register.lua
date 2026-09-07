--[[
	GSSiK Addon Tablet - Registro en el core
	Autor: SiK
	Fecha: 2026-08-05
]]

require "GSSiK_API"
require "GSSiK_Addon_Tablet_Log"

--- Nombre de receta -> slug usado por su opcion propia
--- "Recipe_<slug>_RequireBook" (SandboxVars.GSSiK_Addon_Tablet.*, no Core).
local RECIPE_NAME_TO_SLUG = {
	["Build GS Antenna Dish"] = "AntennaDish",
	["Build GS Antenna Transmitter"] = "AntennaTransmitter",
	["Build GS WiFi Chip T1"] = "WifiChipT1",
	["Build GS WiFi Antenna"] = "WifiAntenna",
	["Build GS WiFi Chip T2"] = "WifiChipT2",
	["Build GS WiFi Antenna T2"] = "WifiAntennaT2",
	["Build GS WiFi Chip T3"] = "WifiChipT3",
	["Build GS WiFi Antenna T3"] = "WifiAntennaT3",
	["Build GS Tablet Screen"] = "TabletScreen",
	["Build GS Tablet Battery"] = "TabletBattery",
	["Build GS Tablet"] = "Tablet",
	["Build GS Craft Tablet Module"] = "CraftTabletModule",
	["Build GS Craft Tablet"] = "CraftTablet",
	["Build GS Builder Tablet Module"] = "BuilderTabletModule",
	["Build GS Builder Tablet"] = "BuilderTablet",
	["Build GS Master Tablet Core"] = "MasterTabletCore",
	["Build GS Master Tablet"] = "MasterTablet",
	["Program GS Tablet Install Disk"] = "TabletDisk",
}

--- Resolutor que Core llama (GS_AddonRecipeTuning.lua) para decidir si una
--- receta de este addon exige manual - vive aqui, no en Core.
---@param recipeName string
---@return boolean
local function resolveRecipeBookRequirement(recipeName)
	local slug = RECIPE_NAME_TO_SLUG[recipeName]
	if slug then
		local addonConfig = SandboxVars and SandboxVars.GSSiK_Addon_Tablet
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
	id = "TabletLink",
	modId = "GSSiK_Addon_Tablet",
	-- Periferico: Antena WiFi GS. Va instalada en el terminal (emite
	-- servicio de red), no la lleva el jugador encima - eso es la Tableta
	-- GS y sus tiers superiores, un arbol de crafteo aparte. itemType
	-- (T1) se mantiene como valor por defecto/compatibilidad; el sistema
	-- de instalacion real acepta CUALQUIERA de los 3 tiers via
	-- moduleItemTypes (ver GS_AddonRegistry.moduleItemTypes /
	-- GS_Addons.install-uninstall) - el rango de la red depende de cual de
	-- los 3 este instalado, no de la tableta que lleve el jugador.
	itemType = "GSSiK_Addon_Tablet.GS_WifiAntenna",
	moduleItemTypes = {
		"GSSiK_Addon_Tablet.GS_WifiAntenna",
		"GSSiK_Addon_Tablet.GS_WifiAntenna_T2",
		"GSSiK_Addon_Tablet.GS_WifiAntenna_T3",
	},
	magazineType = "GSSiK_Addon_Tablet.GS_Manual_Antenna",
	installDiskItem = "GSSiK_Addon_Tablet.GS_FloppyDisk_Tablet",
	diskProgram = {
		id = "tablet",
		recipeName = "Program GS Tablet Install Disk",
		manualItem = "GSSiK_Addon_Tablet.GS_Manual_Tablet_DiskProgram",
		outputItem = "GSSiK_Addon_Tablet.GS_FloppyDisk_Tablet",
		menuTextKey = "IGUI_GS_ProgramTabletDiskMenu",
		iconPath = "media/textures/Item_GS_FloppyDisk_Tablet.png",
		descKey = "IGUI_GS_ProgramTabletDiskDesc",
	},
	moduleRecipeName = "Build GS WiFi Antenna",
	moduleSkillLevel = 6,
	moduleCraftTime = 100,
	-- Icono REAL del periferico (antena), no el icono de pestaña estilizado -
	-- El Core entrega iconPath al CardCollection publico de SiK UI.
	-- (reportado: "no se muestran los perifericos por su icono en las
	-- bahias" - antes un mapa aparte en Core sobrescribia esto con el icono
	-- de pestaña, ahora retirado). El icono de la pestaña propia (si la
	-- hubiera) se define aparte, no aqui - esto es solo para la bahia.
	iconPath = "media/textures/Item_GS_WifiAntenna.png",
	moduleIngredients = {
		{ item = "GSSiK_Addon_Tablet.GS_WifiAntenna_Dish", count = 1 },
		{ item = "GSSiK_Addon_Tablet.GS_WifiAntenna_Transmitter", count = 1 },
		{ item = "GSSiK_Addon_Tablet.GS_WifiChip_T1", count = 1 },
	},
	-- Cadena de tiers (T1 -> T2 -> T3, cada uno consume el anterior al
	-- craftearse - ver gssik_addon_tablet_recipes.txt): campo opcional,
	-- generico para cualquier addon futuro con varios tiers del mismo
	-- periferico. GS_AddonManageUI.lua lo usa para mostrar los 3 claramente,
	-- con el tier realmente instalado resaltado (pedido explicitamente: "que
	-- las 3 se indiquen claramente en la ranura de addon adecuada").
	tierItems = {
		{ item = "GSSiK_Addon_Tablet.GS_WifiAntenna", recipeName = "Build GS WiFi Antenna" },
		{ item = "GSSiK_Addon_Tablet.GS_WifiAntenna_T2", recipeName = "Build GS WiFi Antenna T2" },
		{ item = "GSSiK_Addon_Tablet.GS_WifiAntenna_T3", recipeName = "Build GS WiFi Antenna T3" },
	},
	recipeNames = {
		"Build GS Antenna Dish",
		"Build GS Antenna Transmitter",
		"Build GS WiFi Chip T1",
		"Build GS WiFi Antenna",
		"Build GS WiFi Chip T2",
		"Build GS WiFi Antenna T2",
		"Build GS WiFi Chip T3",
		"Build GS WiFi Antenna T3",
		"Program GS Tablet Install Disk",
		"Build GS Tablet Screen",
		"Build GS Tablet Battery",
		"Build GS Tablet",
		"Build GS Craft Tablet Module",
		"Build GS Craft Tablet",
		"Build GS Builder Tablet Module",
		"Build GS Builder Tablet",
		"Build GS Master Tablet Core",
		"Build GS Master Tablet",
	},
	titleKey = "IGUI_GS_AddonTabletTitle",
	descKey = "IGUI_GS_AddonTabletDesc",
	workshopId = "3752379947",
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
	error("GSSiK Addon Tablet registration failed: " .. tostring(registerCode))
end

if Events and Events.OnGameStart then
	Events.OnGameStart.Add(function()
		local ok, code = registerDefinition()
		if not ok then
			GSSiK_Addon_Tablet.Log.debug(
				"registration_reconcile_failed code=" .. tostring(code))
		end
	end)
end
