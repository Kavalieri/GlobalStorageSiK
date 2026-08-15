--[[
	GSSiK Addon Craft - Sandbox
	Autor: SiK
	Fecha: 2025-06-27
]]

GlobalStorageSiK = GlobalStorageSiK or {}
GSSiK_Addon_Craft = GSSiK_Addon_Craft or {}
GSSiK_Addon_Craft.Sandbox = {}

--- Version del addon para mostrar en su propia pestaña del terminal - se
--- sincroniza a mano con Contents/mods/GSSiK_Addon_Craft/42/mod.info
--- (modversion=) en cada release, mismo criterio ya usado en Core con
--- GS_Config.MOD_VERSION (ver CLAUDE.md raiz, regla 7bis: mod.info es la
--- unica fuente de verdad de version, esto es solo un espejo para la UI).
GSSiK_Addon_Craft.VERSION = "0.0.2.18"

--- Peso loot periférico instalable (Craft).
---@return number
function GSSiK_Addon_Craft.Sandbox.getLootPeripheralWeight()
	local v = SandboxVars.GSSiK_Addon_Craft
	return v and v.LootPeripheralWeight or 0.08
end

--- Peso loot revista del addon Craft.
---@return number
function GSSiK_Addon_Craft.Sandbox.getLootMagazineWeight()
	local v = SandboxVars.GSSiK_Addon_Craft
	return v and v.LootMagazineWeight or 0.35
end

--- Peso loot revista de programación del disco de instalación (Craft).
---@return number
function GSSiK_Addon_Craft.Sandbox.getLootDiskProgramMagazineWeight()
	local v = SandboxVars.GSSiK_Addon_Craft
	return v and v.LootDiskProgramMagazineWeight or 0.3
end

--- Peso loot de las 3 piezas sueltas de la impresora (Chasis, Cabezal, Placa).
---@return number
function GSSiK_Addon_Craft.Sandbox.getLootComponentWeight()
	local v = SandboxVars.GSSiK_Addon_Craft
	return v and v.LootComponentWeight or 0.2
end

--- Peso loot del disco de instalacion ya programado (GS_FloppyDisk_Craft).
--- Bajo a proposito, igual que Core con sus discos ya programados (mas raro
--- encontrarlo hecho que uno en blanco - ver GS_Distributions.lua de Core).
---@return number
function GSSiK_Addon_Craft.Sandbox.getLootInstallDiskWeight()
	local v = SandboxVars.GSSiK_Addon_Craft
	return v and v.LootInstallDiskWeight or 0.15
end

--- Modo debug propio del addon Craft.
---@return boolean
function GSSiK_Addon_Craft.Sandbox.isDebugMode()
	local v = SandboxVars.GSSiK_Addon_Craft
	return v and v.DebugMode == true
end
