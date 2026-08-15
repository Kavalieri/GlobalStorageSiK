--[[
	GSSiK Addon Builder - Sandbox
	Autor: SiK
	Fecha: 2025-06-27
]]

GSSiK_Addon_Builder = GSSiK_Addon_Builder or {}
GSSiK_Addon_Builder.Sandbox = {}

--- Version del addon para mostrar en su propia pestaña del terminal - se
--- sincroniza a mano con Contents/mods/GSSiK_Addon_Builder/42/mod.info
--- (modversion=) en cada release, mismo criterio que Core (GS_Config.MOD_VERSION).
GSSiK_Addon_Builder.VERSION = "0.0.2.18-dev2"

--- Peso loot periférico instalable (Pizarra Digital GS).
---@return number
function GSSiK_Addon_Builder.Sandbox.getLootPeripheralWeight()
	local v = SandboxVars.GSSiK_Addon_Builder
	return v and v.LootPeripheralWeight or 0.08
end

--- Peso loot revista principal del addon Builder.
---@return number
function GSSiK_Addon_Builder.Sandbox.getLootMagazineWeight()
	local v = SandboxVars.GSSiK_Addon_Builder
	return v and v.LootMagazineWeight or 0.35
end

--- Peso loot revista de programación del disco de instalación (Builder).
---@return number
function GSSiK_Addon_Builder.Sandbox.getLootDiskProgramMagazineWeight()
	local v = SandboxVars.GSSiK_Addon_Builder
	return v and v.LootDiskProgramMagazineWeight or 0.3
end

--- Peso loot de las 3 piezas sueltas de la pizarra (Marco, Panel, Lápiz).
---@return number
function GSSiK_Addon_Builder.Sandbox.getLootComponentWeight()
	local v = SandboxVars.GSSiK_Addon_Builder
	return v and v.LootComponentWeight or 0.2
end

--- Peso loot del disco de instalacion ya programado (GS_FloppyDisk_Builder).
---@return number
function GSSiK_Addon_Builder.Sandbox.getLootInstallDiskWeight()
	local v = SandboxVars.GSSiK_Addon_Builder
	return v and v.LootInstallDiskWeight or 0.15
end

--- Modo debug propio del addon Builder.
---@return boolean
function GSSiK_Addon_Builder.Sandbox.isDebugMode()
	local v = SandboxVars.GSSiK_Addon_Builder
	return v and v.DebugMode == true
end
