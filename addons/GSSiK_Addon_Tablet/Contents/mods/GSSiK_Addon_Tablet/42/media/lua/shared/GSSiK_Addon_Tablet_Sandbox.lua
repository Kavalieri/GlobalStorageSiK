--[[
	GSSiK Addon Tablet - Sandbox
	Autor: SiK
	Fecha: 2026-08-05
	Descripción: Un rango independiente por tier (1 Tableta base, 2 Craft o
	Builder, 3 Maestra), preparado para sumar un Tier4Range el dia que haga
	falta. Y un peso de loot independiente por CADA ítem craftable del
	addon (montado y en piezas), escalado según su dificultad: más caro de
	fabricar = más raro de encontrar por defecto. Todos configurables desde
	sandbox, incluido 0 para desactivar cualquiera.
]]

GlobalStorageSiK = GlobalStorageSiK or {}
GSSiK_Addon_Tablet = GSSiK_Addon_Tablet or {}
GSSiK_Addon_Tablet.Sandbox = {}

--- Version del addon para mostrar en su propia pestaña del terminal - se
--- sincroniza a mano con Contents/mods/GSSiK_Addon_Tablet/42/mod.info
--- (modversion=) en cada release, mismo criterio que Core (GS_Config.MOD_VERSION).
GSSiK_Addon_Tablet.VERSION = "0.0.2.13"

--- Rango inalámbrico tier 1 (Tableta base).
---@return number
function GSSiK_Addon_Tablet.Sandbox.getTier1Range()
	local v = SandboxVars.GSSiK_Addon_Tablet
	return v and v.Tier1Range or 40
end

--- Rango inalámbrico tier 2 (Tableta Craft o Builder).
---@return number
function GSSiK_Addon_Tablet.Sandbox.getTier2Range()
	local v = SandboxVars.GSSiK_Addon_Tablet
	return v and v.Tier2Range or 70
end

--- Rango inalámbrico tier 3 (Tableta Maestra).
---@return number
function GSSiK_Addon_Tablet.Sandbox.getTier3Range()
	local v = SandboxVars.GSSiK_Addon_Tablet
	return v and v.Tier3Range or 120
end

-- Antena WiFi (periférico de terminal) -----------------------------------

---@return number
function GSSiK_Addon_Tablet.Sandbox.getLootAntennaWeight()
	local v = SandboxVars.GSSiK_Addon_Tablet
	return v and v.LootAntennaWeight or 0.06
end

---@return number
function GSSiK_Addon_Tablet.Sandbox.getLootAntennaDishWeight()
	local v = SandboxVars.GSSiK_Addon_Tablet
	return v and v.LootAntennaDishWeight or 0.18
end

---@return number
function GSSiK_Addon_Tablet.Sandbox.getLootAntennaTransmitterWeight()
	local v = SandboxVars.GSSiK_Addon_Tablet
	return v and v.LootAntennaTransmitterWeight or 0.18
end

--- Peso compartido por los 3 chips WiFi (T1/T2/T3) - misma familia de
--- componente suelto, igual criterio que el resto de piezas del addon.
---@return number
function GSSiK_Addon_Tablet.Sandbox.getLootAntennaChipWeight()
	local v = SandboxVars.GSSiK_Addon_Tablet
	return v and v.LootAntennaChipWeight or 0.15
end

---@return number
function GSSiK_Addon_Tablet.Sandbox.getLootAntennaT2Weight()
	local v = SandboxVars.GSSiK_Addon_Tablet
	return v and v.LootAntennaT2Weight or 0.03
end

---@return number
function GSSiK_Addon_Tablet.Sandbox.getLootAntennaT3Weight()
	local v = SandboxVars.GSSiK_Addon_Tablet
	return v and v.LootAntennaT3Weight or 0.015
end

-- Tableta base (tier 1) ---------------------------------------------------

---@return number
function GSSiK_Addon_Tablet.Sandbox.getLootTabletWeight()
	local v = SandboxVars.GSSiK_Addon_Tablet
	return v and v.LootTabletWeight or 0.15
end

---@return number
function GSSiK_Addon_Tablet.Sandbox.getLootTabletScreenWeight()
	local v = SandboxVars.GSSiK_Addon_Tablet
	return v and v.LootTabletScreenWeight or 0.25
end

---@return number
function GSSiK_Addon_Tablet.Sandbox.getLootTabletBatteryWeight()
	local v = SandboxVars.GSSiK_Addon_Tablet
	return v and v.LootTabletBatteryWeight or 0.25
end

-- Tableta Craft (tier 2a) --------------------------------------------------

---@return number
function GSSiK_Addon_Tablet.Sandbox.getLootTabletCraftWeight()
	local v = SandboxVars.GSSiK_Addon_Tablet
	return v and v.LootTabletCraftWeight or 0.08
end

---@return number
function GSSiK_Addon_Tablet.Sandbox.getLootTabletCraftModuleWeight()
	local v = SandboxVars.GSSiK_Addon_Tablet
	return v and v.LootTabletCraftModuleWeight or 0.15
end

-- Tableta Builder (tier 2b) -------------------------------------------------

---@return number
function GSSiK_Addon_Tablet.Sandbox.getLootTabletBuilderWeight()
	local v = SandboxVars.GSSiK_Addon_Tablet
	return v and v.LootTabletBuilderWeight or 0.08
end

---@return number
function GSSiK_Addon_Tablet.Sandbox.getLootTabletBuilderModuleWeight()
	local v = SandboxVars.GSSiK_Addon_Tablet
	return v and v.LootTabletBuilderModuleWeight or 0.15
end

-- Tableta Maestra (tier 3) --------------------------------------------------

---@return number
function GSSiK_Addon_Tablet.Sandbox.getLootTabletMasterWeight()
	local v = SandboxVars.GSSiK_Addon_Tablet
	return v and v.LootTabletMasterWeight or 0.02
end

---@return number
function GSSiK_Addon_Tablet.Sandbox.getLootTabletMasterCoreWeight()
	local v = SandboxVars.GSSiK_Addon_Tablet
	return v and v.LootTabletMasterCoreWeight or 0.06
end

-- Revistas ------------------------------------------------------------------

---@return number
function GSSiK_Addon_Tablet.Sandbox.getLootManualAntennaWeight()
	local v = SandboxVars.GSSiK_Addon_Tablet
	return v and v.LootManualAntennaWeight or 0.3
end

---@return number
function GSSiK_Addon_Tablet.Sandbox.getLootManualAntennaAdvancedWeight()
	local v = SandboxVars.GSSiK_Addon_Tablet
	return v and v.LootManualAntennaAdvancedWeight or 0.15
end

---@return number
function GSSiK_Addon_Tablet.Sandbox.getLootManualTabletWeight()
	local v = SandboxVars.GSSiK_Addon_Tablet
	return v and v.LootManualTabletWeight or 0.35
end

---@return number
function GSSiK_Addon_Tablet.Sandbox.getLootManualTabletCraftWeight()
	local v = SandboxVars.GSSiK_Addon_Tablet
	return v and v.LootManualTabletCraftWeight or 0.25
end

---@return number
function GSSiK_Addon_Tablet.Sandbox.getLootManualTabletBuilderWeight()
	local v = SandboxVars.GSSiK_Addon_Tablet
	return v and v.LootManualTabletBuilderWeight or 0.25
end

---@return number
function GSSiK_Addon_Tablet.Sandbox.getLootManualTabletMasterWeight()
	local v = SandboxVars.GSSiK_Addon_Tablet
	return v and v.LootManualTabletMasterWeight or 0.12
end

---@return number
function GSSiK_Addon_Tablet.Sandbox.getLootDiskProgramMagazineWeight()
	local v = SandboxVars.GSSiK_Addon_Tablet
	return v and v.LootDiskProgramMagazineWeight or 0.3
end

--- Peso loot del disco de instalacion ya programado (GS_FloppyDisk_Tablet).
---@return number
function GSSiK_Addon_Tablet.Sandbox.getLootInstallDiskWeight()
	local v = SandboxVars.GSSiK_Addon_Tablet
	return v and v.LootInstallDiskWeight or 0.15
end

--- Modo debug propio del addon Tablet.
---@return boolean
function GSSiK_Addon_Tablet.Sandbox.isDebugMode()
	local v = SandboxVars.GSSiK_Addon_Tablet
	return v and v.DebugMode == true
end
