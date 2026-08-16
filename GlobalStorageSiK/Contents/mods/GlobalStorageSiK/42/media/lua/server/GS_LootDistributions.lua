--[[
	GlobalStorageSiK - Fuente unica de loot procedural del Core

	Este archivo solo registra objetos del Core. Craft, Builder y Tablet poseen
	sus propias tablas de loot y opciones sandbox en sus respectivos addons.
	Todos los destinos se han contrastado con ProceduralDistributions de B42.
]]

require "Items/ProceduralDistributions"
require "GS_Sandbox"

GlobalStorageSiK.Loot = GlobalStorageSiK.Loot or {}

---@param listName string
---@param itemType string
---@param weight number
local function addUniqueToList(listName, itemType, weight)
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

---@param listSpecs table[]
---@param itemTypes string[]
---@param familyWeight number
local function addFamily(listSpecs, itemTypes, familyWeight)
	if not familyWeight or familyWeight <= 0 then
		return
	end
	for i = 1, #listSpecs do
		local spec = listSpecs[i]
		local weight = familyWeight * (spec[2] or 1)
		for j = 1, #itemTypes do
			addUniqueToList(spec[1], itemTypes[j], weight)
		end
	end
end

-- Revistas y manuales: revisteros de gasolineras/tiendas, librerias,
-- bibliotecas, oficinas y comercios tecnicos.
local BOOK_LISTS = {
	{ "LibraryBooks", 1 },
	{ "LibraryMagazines", 1.2 },
	{ "UniversityLibraryMagazines", 1.2 },
	{ "LibraryComputer", 1.5 },
	{ "BookstoreComputer", 1.5 },
	{ "LivingRoomShelf", 0.6 },
	{ "LivingRoomShelfNoTapes", 0.6 },
	{ "MagazineRackMixed", 1.5 },
	{ "MagazineRackPaperback", 1.2 },
	{ "MagazineRackFancy", 1 },
	{ "CrateMagazines", 0.6 },
	{ "ElectronicStoreMagazines", 1.5 },
	{ "ElectronicStoreMisc", 1 },
	{ "OfficeDesk", 0.7 },
	{ "OfficeDeskHome", 0.7 },
	{ "StoreShelfElectronics", 1 },
	{ "ToolStoreBooks", 0.8 },
	{ "PostOfficeMagazines", 1 },
}

-- Disquetes: oficinas y comercios/embalajes de informatica.
local DISK_LISTS = {
	{ "OfficeDesk", 3 },
	{ "OfficeDeskHome", 2 },
	{ "OfficeDrawers", 2 },
	{ "CrateOfficeSupplies", 2 },
	{ "ElectronicStoreComputers", 4 },
	{ "ElectronicStoreMisc", 3 },
	{ "StoreShelfElectronics", 4 },
	{ "Locker", 1 },
}

-- Componentes informaticos del PC y de la disquetera GS.
local COMPUTER_PART_LISTS = {
	{ "ElectronicStoreComputers", 3 },
	{ "ElectronicStoreMisc", 3 },
	{ "StoreShelfElectronics", 3 },
	{ "CrateComputer", 1 },
	{ "CrateElectronics", 1 },
	{ "ArmyStorageElectronics", 1 },
	{ "MechanicShelfElectric", 1 },
}

-- Soldador y sus piezas: electronica, electricistas, herramientas y garajes.
local SOLDERING_PART_LISTS = {
	{ "ElectronicStoreComputers", 3 },
	{ "ElectronicStoreMisc", 3 },
	{ "StoreShelfElectronics", 3 },
	{ "CrateElectronics", 1 },
	{ "ElectricianTools", 2 },
	{ "MechanicShelfElectric", 1 },
	{ "ToolStoreTools", 1 },
	{ "GarageTools", 1 },
}

local SOLDERING_IRON_LISTS = {
	{ "ElectricianTools", 5 },
	{ "ElectronicStoreMisc", 4 },
	{ "StoreShelfElectronics", 4 },
	{ "MechanicShelfElectric", 3 },
	{ "ToolStoreTools", 2 },
	{ "GarageTools", 1 },
	{ "CrateElectronics", 1 },
}

-- Disquetera terminada: rara, pero siempre en destinos B42 validos.
local TERMINAL_READER_LISTS = {
	{ "ElectronicStoreComputers", 2 },
	{ "ElectronicStoreMisc", 2 },
	{ "StoreShelfElectronics", 2 },
	{ "ElectricianTools", 1 },
	{ "CrateElectronics", 1 },
	{ "ArmyStorageElectronics", 1 },
}

function GlobalStorageSiK.Loot.register()
	if GlobalStorageSiK.Loot.registered then
		return
	end
	if not ProceduralDistributions or not ProceduralDistributions.list then
		return
	end

	local S = GlobalStorageSiK.Sandbox
	local P = "GlobalStorageSiK."

	addFamily(BOOK_LISTS, { P .. "GS_Manual_TerminalUnit" }, S.getLootBooksWeight())
	addFamily(BOOK_LISTS, { P .. "GS_Manual_PCBuild" }, S.getLootManualWeight())
	addFamily(BOOK_LISTS, {
		P .. "GS_Manual_DiskPrograms",
		P .. "GS_Manual_DriveInstall_DiskProgram",
		P .. "GS_Manual_NetworkDisk_DiskProgram",
	}, S.getLootDiskProgramMagazineWeight())
	addFamily(BOOK_LISTS, { P .. "GS_Manual_SolderingIron" }, S.getLootSolderingIronManualWeight())

	addFamily(DISK_LISTS, { P .. "GS_FloppyDisk" }, S.getLootFloppyDiskWeight() * 0.75)
	addFamily(DISK_LISTS, { P .. "GS_FloppyDisk_Blank" }, S.getLootBlankDiskWeight())
	addFamily(DISK_LISTS, { P .. "GS_FloppyDisk_Uninstall" }, S.getLootUninstallDiskWeight() * 0.25)
	addFamily(DISK_LISTS, { P .. "GS_FloppyDisk_DriveInstall" }, S.getLootDriveDiskWeight() * 0.25)

	addFamily(COMPUTER_PART_LISTS, {
		P .. "GS_PC_Tower",
		P .. "GS_Motherboard",
		P .. "GS_IODevice",
		P .. "GS_Keyboard",
		P .. "GS_ReaderCasing",
		P .. "GS_ReaderCircuit",
		P .. "GS_ReaderAntenna",
	}, S.getLootPCPartsWeight())

	addFamily(SOLDERING_PART_LISTS, {
		P .. "GS_SolderingTip",
		P .. "GS_SolderingResistance",
		P .. "GS_SolderingHandle",
	}, S.getLootSolderingPartsWeight())
	addFamily(SOLDERING_IRON_LISTS, { P .. "GS_SolderingIron" }, S.getLootSolderingIronWeight())
	addFamily(TERMINAL_READER_LISTS, { P .. "GS_TerminalReader" }, S.getLootTerminalReaderWeight() * 0.5)

	GlobalStorageSiK.Loot.registered = true
end

GlobalStorageSiK.Loot.register()
