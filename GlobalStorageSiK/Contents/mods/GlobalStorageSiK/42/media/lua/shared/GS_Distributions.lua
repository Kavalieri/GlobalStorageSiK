--[[
	GlobalStorageSiK - Distribución de loot en el mundo
	Autor: SiK
	Descripción: Añade a contenedores del mundo el disquete, ambos manuales, las
	             piezas de PC/lector, el soldador y el lector ya montado.
	             El disquete es raro pero reutilizable (mode:keep en recetas).
	             Cada familia de ítem tiene su propio multiplicador de sandbox
	             (ver GS_Sandbox.lua, getLoot*Weight) - por defecto 1.0, igual
	             que ya funcionan los addons (Tablet/Craft/Builder). Los pesos
	             relativos entre contenedores de una misma familia se
	             mantienen (p.ej. ShelvesElectronics siempre mas probable que
	             Crate para el mismo item), el multiplicador solo escala el
	             conjunto.
]]

require "GS_Sandbox"

--- Multiplica y redondea: ProceduralDistributions acepta enteros o floats,
--- pero un peso fraccionario minusculo (multiplicador muy bajo) puede acabar
--- en 0 - eso es correcto e intencionado (el jugador pidio "no debe
--- aparecer"), no un bug.
---@param base number
---@param mult number
---@return number
local function w(base, mult)
	if base <= 0 then
		return 0
	end
	return base * (mult or 1)
end

local function addToDistribution(list, containerName, itemType, chance)
	local t = list[containerName]
	if not t then return end
	local items = t.items
	if not items then return end
	items[#items + 1] = itemType
	items[#items + 1] = chance
end

local function applyDistributions()
	local list = ProceduralDistributions and ProceduralDistributions.list
	if not list then return end

	local S = GlobalStorageSiK.Sandbox
	local diskW = S.getLootFloppyDiskWeight()
	local blankW = S.getLootBlankDiskWeight()
	local uninstallW = S.getLootUninstallDiskWeight()
	local driveW = S.getLootDriveDiskWeight()
	local manualW = S.getLootManualWeight()
	local diskProgManualW = S.getLootDiskProgramMagazineWeight()
	local ironW = S.getLootSolderingIronWeight()
	local partsW = S.getLootPCPartsWeight()
	local readerW = S.getLootTerminalReaderWeight()
	local ironManualW = S.getLootSolderingIronManualWeight()
	local solderingPartsW = S.getLootSolderingPartsWeight()

	-- GS_FloppyDisk: poco común, lugares con equipos informáticos u oficinas
	addToDistribution(list, "OfficeDesk",      "GlobalStorageSiK.GS_FloppyDisk", w(3, diskW))
	addToDistribution(list, "FilingCabinet",   "GlobalStorageSiK.GS_FloppyDisk", w(2, diskW))
	addToDistribution(list, "Crate",           "GlobalStorageSiK.GS_FloppyDisk", w(1, diskW))
	addToDistribution(list, "Locker",          "GlobalStorageSiK.GS_FloppyDisk", w(1, diskW))
	addToDistribution(list, "MetalShelf",      "GlobalStorageSiK.GS_FloppyDisk", w(1, diskW))
	addToDistribution(list, "WarehouseBox",    "GlobalStorageSiK.GS_FloppyDisk", w(2, diskW))
	-- Tiendas de electrónica y aulas de informática
	addToDistribution(list, "ShelvesElectronics", "GlobalStorageSiK.GS_FloppyDisk", w(5, diskW))
	addToDistribution(list, "DeskBig",         "GlobalStorageSiK.GS_FloppyDisk", w(2, diskW))

	-- GS_Manual_TerminalUnit: en librerías, tiendas de electrónica y escritorios
	addToDistribution(list, "ShelvesElectronics", "GlobalStorageSiK.GS_Manual_TerminalUnit", w(4, manualW))
	addToDistribution(list, "BookstoreBookcase",  "GlobalStorageSiK.GS_Manual_TerminalUnit", w(3, manualW))
	addToDistribution(list, "MagazineRack",       "GlobalStorageSiK.GS_Manual_TerminalUnit", w(5, manualW))
	addToDistribution(list, "OfficeDesk",         "GlobalStorageSiK.GS_Manual_TerminalUnit", w(2, manualW))
	addToDistribution(list, "Shelves",            "GlobalStorageSiK.GS_Manual_TerminalUnit", w(1, manualW))

	-- GS_Manual_PCBuild: mismos sitios que el otro manual, algo más raro
	-- (segundo manual, no queremos que compita demasiado con el primero).
	addToDistribution(list, "ShelvesElectronics", "GlobalStorageSiK.GS_Manual_PCBuild", w(3, manualW))
	addToDistribution(list, "BookstoreBookcase",  "GlobalStorageSiK.GS_Manual_PCBuild", w(2, manualW))
	addToDistribution(list, "MagazineRack",       "GlobalStorageSiK.GS_Manual_PCBuild", w(4, manualW))
	addToDistribution(list, "OfficeDesk",         "GlobalStorageSiK.GS_Manual_PCBuild", w(1, manualW))

	-- Piezas intermedias (lector Y ordenador propio): antes solo se podían
	-- conseguir crafteando desde cero, sin ninguna forma de encontrarlas ya
	-- hechas por el mundo. Tiendas de electrónica primero, luego sitios
	-- genéricos de trastos/almacén donde tendría sentido encontrar chatarra
	-- electrónica suelta.
	local pieces = {
		"GlobalStorageSiK.GS_PC_Tower",
		"GlobalStorageSiK.GS_Motherboard",
		"GlobalStorageSiK.GS_IODevice",
		"GlobalStorageSiK.GS_Keyboard",
		"GlobalStorageSiK.GS_ReaderCasing",
		"GlobalStorageSiK.GS_ReaderCircuit",
		"GlobalStorageSiK.GS_ReaderAntenna",
	}
	for i = 1, #pieces do
		addToDistribution(list, "ShelvesElectronics", pieces[i], w(3, partsW))
		addToDistribution(list, "WarehouseBox",       pieces[i], w(1, partsW))
		addToDistribution(list, "MetalShelf",         pieces[i], w(1, partsW))
		addToDistribution(list, "Crate",               pieces[i], w(1, partsW))
	end

	-- Componentes propios del soldador (Punta/Resistencia/Mango): mismos
	-- sitios y mismo criterio que el resto de piezas intermedias, con su
	-- propio multiplicador de sandbox independiente.
	local solderingParts = {
		"GlobalStorageSiK.GS_SolderingTip",
		"GlobalStorageSiK.GS_SolderingResistance",
		"GlobalStorageSiK.GS_SolderingHandle",
	}
	for i = 1, #solderingParts do
		addToDistribution(list, "ShelvesElectronics", solderingParts[i], w(3, solderingPartsW))
		addToDistribution(list, "WarehouseBox",       solderingParts[i], w(1, solderingPartsW))
		addToDistribution(list, "MetalShelf",         solderingParts[i], w(1, solderingPartsW))
		addToDistribution(list, "Crate",               solderingParts[i], w(1, solderingPartsW))
	end

	-- GS_SolderingIron: herramienta obligatoria para craftear cualquier pieza
	-- del mod. Electricistas y tiendas de electronica primero (tematicamente
	-- lo mas logico), luego tiendas de herramientas y garajes genericos.
	local solderingIron = "GlobalStorageSiK.GS_SolderingIron"
	addToDistribution(list, "ElectricianTools",   solderingIron, w(5, ironW))
	addToDistribution(list, "ShelvesElectronics", solderingIron, w(4, ironW))
	addToDistribution(list, "MechanicShelfElectric", solderingIron, w(3, ironW))
	addToDistribution(list, "ToolStoreTools",     solderingIron, w(2, ironW))
	addToDistribution(list, "GarageTools",        solderingIron, w(1, ironW))
	addToDistribution(list, "WarehouseBox",       solderingIron, w(1, ironW))
	addToDistribution(list, "Crate",              solderingIron, w(1, ironW))

	-- GS_FloppyDisk_Blank: disco en blanco, material de oficina corriente -
	-- mas comun que el disco de red "de fabrica" (GS_FloppyDisk), mismos
	-- sitios tematicos.
	addToDistribution(list, "OfficeDesk",         "GlobalStorageSiK.GS_FloppyDisk_Blank", w(4, blankW))
	addToDistribution(list, "FilingCabinet",      "GlobalStorageSiK.GS_FloppyDisk_Blank", w(3, blankW))
	addToDistribution(list, "ShelvesElectronics", "GlobalStorageSiK.GS_FloppyDisk_Blank", w(5, blankW))
	addToDistribution(list, "DeskBig",            "GlobalStorageSiK.GS_FloppyDisk_Blank", w(3, blankW))
	addToDistribution(list, "Crate",              "GlobalStorageSiK.GS_FloppyDisk_Blank", w(2, blankW))
	addToDistribution(list, "WarehouseBox",       "GlobalStorageSiK.GS_FloppyDisk_Blank", w(2, blankW))

	-- GS_FloppyDisk_Uninstall: ya programado, mucho mas raro encontrarlo
	-- hecho que uno en blanco - mismos sitios, pesos bajos a proposito.
	addToDistribution(list, "ShelvesElectronics", "GlobalStorageSiK.GS_FloppyDisk_Uninstall", w(1, uninstallW))
	addToDistribution(list, "OfficeDesk",         "GlobalStorageSiK.GS_FloppyDisk_Uninstall", w(1, uninstallW))

	-- GS_Manual_DiskPrograms: mismos sitios que los otros dos manuales.
	addToDistribution(list, "ShelvesElectronics", "GlobalStorageSiK.GS_Manual_DiskPrograms", w(3, diskProgManualW))
	addToDistribution(list, "BookstoreBookcase",  "GlobalStorageSiK.GS_Manual_DiskPrograms", w(2, diskProgManualW))
	addToDistribution(list, "MagazineRack",       "GlobalStorageSiK.GS_Manual_DiskPrograms", w(4, diskProgManualW))
	addToDistribution(list, "OfficeDesk",         "GlobalStorageSiK.GS_Manual_DiskPrograms", w(1, diskProgManualW))

	-- GS_FloppyDisk_DriveInstall: ya programado (instala el Lector en red),
	-- mismos sitios y peso bajo que GS_FloppyDisk_Uninstall.
	addToDistribution(list, "ShelvesElectronics", "GlobalStorageSiK.GS_FloppyDisk_DriveInstall", w(1, driveW))
	addToDistribution(list, "OfficeDesk",         "GlobalStorageSiK.GS_FloppyDisk_DriveInstall", w(1, driveW))

	-- GS_Manual_DriveInstall_DiskProgram: mismos sitios que los otros manuales.
	addToDistribution(list, "ShelvesElectronics", "GlobalStorageSiK.GS_Manual_DriveInstall_DiskProgram", w(3, diskProgManualW))
	addToDistribution(list, "BookstoreBookcase",  "GlobalStorageSiK.GS_Manual_DriveInstall_DiskProgram", w(2, diskProgManualW))
	addToDistribution(list, "MagazineRack",       "GlobalStorageSiK.GS_Manual_DriveInstall_DiskProgram", w(4, diskProgManualW))
	addToDistribution(list, "OfficeDesk",         "GlobalStorageSiK.GS_Manual_DriveInstall_DiskProgram", w(1, diskProgManualW))

	-- GS_Manual_NetworkDisk_DiskProgram: mismos sitios que los otros manuales.
	addToDistribution(list, "ShelvesElectronics", "GlobalStorageSiK.GS_Manual_NetworkDisk_DiskProgram", w(3, diskProgManualW))
	addToDistribution(list, "BookstoreBookcase",  "GlobalStorageSiK.GS_Manual_NetworkDisk_DiskProgram", w(2, diskProgManualW))
	addToDistribution(list, "MagazineRack",       "GlobalStorageSiK.GS_Manual_NetworkDisk_DiskProgram", w(4, diskProgManualW))
	addToDistribution(list, "OfficeDesk",         "GlobalStorageSiK.GS_Manual_NetworkDisk_DiskProgram", w(1, diskProgManualW))

	-- GS_Manual_SolderingIron: mismos sitios que los otros manuales. Solo es
	-- util si el jugador activo EnableSolderingIronCraft; leerla sin esa
	-- opcion no desbloquea nada (ver GS_RecipeTests.lua).
	addToDistribution(list, "ShelvesElectronics", "GlobalStorageSiK.GS_Manual_SolderingIron", w(3, ironManualW))
	addToDistribution(list, "BookstoreBookcase",  "GlobalStorageSiK.GS_Manual_SolderingIron", w(2, ironManualW))
	addToDistribution(list, "MagazineRack",       "GlobalStorageSiK.GS_Manual_SolderingIron", w(4, ironManualW))
	addToDistribution(list, "OfficeDesk",         "GlobalStorageSiK.GS_Manual_SolderingIron", w(1, ironManualW))

	-- GS_TerminalReader: la Disquetera GS ya montada. Es la pieza mas dificil
	-- de conseguir crafteando (3 componentes + ambas herramientas + nivel de
	-- electricidad), asi que encontrarla ya hecha debe ser un golpe de suerte
	-- raro, mas raro que cualquier pieza suelta. Mismos sitios tematicos que
	-- las piezas pero con pesos bajos a proposito.
	local terminalReader = "GlobalStorageSiK.GS_TerminalReader"
	addToDistribution(list, "ShelvesElectronics", terminalReader, w(2, readerW))
	addToDistribution(list, "ElectricianTools",   terminalReader, w(1, readerW))
	addToDistribution(list, "MetalShelf",         terminalReader, w(1, readerW))
	addToDistribution(list, "WarehouseBox",       terminalReader, w(1, readerW))
end

-- OnGameBoot es suficientemente temprano; ProceduralDistributions ya está cargado en ese punto.
if Events and Events.OnGameBoot then
	Events.OnGameBoot.Add(applyDistributions)
else
	-- Fallback: ejecutar inline si el evento no existe todavía
	applyDistributions()
end
