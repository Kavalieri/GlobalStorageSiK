--[[
	GSSiK Addon Tablet - Loot procedural
	Autor: SiK
	Fecha: 2026-08-05
	Descripción: Todo lo craftable del addon aparece también en el mundo,
	cada ítem con su propio peso de sandbox escalado por dificultad (los
	montajes finales son más raros que sus piezas sueltas, y los tiers
	superiores más raros que los inferiores).
]]

require "Items/ProceduralDistributions"
require "GSSiK_Addon_Tablet_Sandbox"

GSSiK_Addon_Tablet = GSSiK_Addon_Tablet or {}
GSSiK_Addon_Tablet.Loot = GSSiK_Addon_Tablet.Loot or {}

---@param listName string
---@param itemType string
---@param weight number
local function addToList(listName, itemType, weight)
	local list = ProceduralDistributions.list[listName]
	if not list or not list.items or not weight or weight <= 0 then
		return
	end
	for i = 1, #list.items, 2 do
		if list.items[i] == itemType then
			return
		end
	end
	table.insert(list.items, itemType)
	table.insert(list.items, weight)
end

---@param lists string[]
---@param itemType string
---@param weight number
local function addToLists(lists, itemType, weight)
	for i = 1, #lists do
		addToList(lists[i], itemType, weight)
	end
end

function GSSiK_Addon_Tablet.Loot.register()
	if GSSiK_Addon_Tablet.Loot.registered then
		return
	end
	if not ProceduralDistributions or not ProceduralDistributions.list then
		return
	end

	local S = GSSiK_Addon_Tablet.Sandbox
	local P = "GSSiK_Addon_Tablet."

	local bookLists = {
		"LibraryBooks", "LibraryMagazines", "UniversityLibraryMagazines",
		"LivingRoomShelf", "MagazineRackMixed", "MagazineRackPaperback", "MagazineRackFancy",
		"CrateMagazines", "ElectronicStoreMagazines", "ElectronicStoreMisc", "OfficeDesk",
		"StoreShelfElectronics",
	}
	addToLists(bookLists, P .. "GS_Manual_Antenna", S.getLootManualAntennaWeight())
	addToLists(bookLists, P .. "GS_Manual_TabletBase", S.getLootManualTabletWeight())
	addToLists(bookLists, P .. "GS_Manual_TabletCraft", S.getLootManualTabletCraftWeight())
	addToLists(bookLists, P .. "GS_Manual_TabletBuilder", S.getLootManualTabletBuilderWeight())
	addToLists(bookLists, P .. "GS_Manual_TabletMaster", S.getLootManualTabletMasterWeight())
	addToLists(bookLists, P .. "GS_Manual_Tablet_DiskProgram", S.getLootDiskProgramMagazineWeight())
	addToLists(bookLists, P .. "GS_Manual_AntennaAdvanced", S.getLootManualAntennaAdvancedWeight())

	-- Montajes completos: solo en loot raro, mas dificiles de encontrar
	-- cuanto mas alto el tier.
	local rareLists = {
		"ArmySurplusMisc", "SecurityLockers", "PoliceEvidence",
		"ElectronicStoreMisc", "ArmyStorageElectronics", "LockerArmyBedroom",
	}
	addToLists(rareLists, P .. "GS_WifiAntenna", S.getLootAntennaWeight())
	addToLists(rareLists, P .. "GS_WifiAntenna_T2", S.getLootAntennaT2Weight())
	addToLists(rareLists, P .. "GS_WifiAntenna_T3", S.getLootAntennaT3Weight())
	addToLists(rareLists, P .. "GS_Tablet", S.getLootTabletWeight())
	addToLists(rareLists, P .. "GS_TabletCraft", S.getLootTabletCraftWeight())
	addToLists(rareLists, P .. "GS_TabletBuilder", S.getLootTabletBuilderWeight())
	addToLists(rareLists, P .. "GS_TabletMaster", S.getLootTabletMasterWeight())

	-- Piezas sueltas: mas comunes que los montajes completos, en tiendas
	-- de electronica.
	local componentLists = {
		"ElectronicStoreMisc", "ElectronicStoreComputers", "StoreShelfElectronics",
		"CrateElectronics",
	}
	addToLists(componentLists, P .. "GS_WifiAntenna_Dish", S.getLootAntennaDishWeight())
	addToLists(componentLists, P .. "GS_WifiAntenna_Transmitter", S.getLootAntennaTransmitterWeight())
	addToLists(componentLists, P .. "GS_WifiChip_T1", S.getLootAntennaChipWeight())
	addToLists(componentLists, P .. "GS_WifiChip_T2", S.getLootAntennaChipWeight())
	addToLists(componentLists, P .. "GS_WifiChip_T3", S.getLootAntennaChipWeight())
	addToLists(componentLists, P .. "GS_Tablet_Screen", S.getLootTabletScreenWeight())
	addToLists(componentLists, P .. "GS_Tablet_Battery", S.getLootTabletBatteryWeight())
	addToLists(componentLists, P .. "GS_TabletCraft_Module", S.getLootTabletCraftModuleWeight())
	addToLists(componentLists, P .. "GS_TabletBuilder_Module", S.getLootTabletBuilderModuleWeight())
	addToLists(componentLists, P .. "GS_TabletMaster_Core", S.getLootTabletMasterCoreWeight())

	-- GS_FloppyDisk_Tablet ya programado: sitios de electronica/oficina.
	local diskLists = { "OfficeDesk", "ElectronicStoreMisc", "StoreShelfElectronics" }
	addToLists(diskLists, P .. "GS_FloppyDisk_Tablet", S.getLootInstallDiskWeight())

	GSSiK_Addon_Tablet.Loot.registered = true
end

GSSiK_Addon_Tablet.Loot.register()
