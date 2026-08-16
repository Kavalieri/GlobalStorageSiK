--[[
	GSSiK Addon Builder - Loot procedural
	Autor: SiK
	Fecha: 2025-06-27
]]

require "Items/ProceduralDistributions"
require "GSSiK_Addon_Builder_Sandbox"

GSSiK_Addon_Builder = GSSiK_Addon_Builder or {}
GSSiK_Addon_Builder.Loot = GSSiK_Addon_Builder.Loot or {}

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

function GSSiK_Addon_Builder.Loot.register()
	if GSSiK_Addon_Builder.Loot.registered then
		return
	end
	if not ProceduralDistributions or not ProceduralDistributions.list then
		return
	end
	local moduleW = GSSiK_Addon_Builder.Sandbox.getLootPeripheralWeight()
	local manualW = GSSiK_Addon_Builder.Sandbox.getLootMagazineWeight()
	local diskManualW = GSSiK_Addon_Builder.Sandbox.getLootDiskProgramMagazineWeight()
	local componentW = GSSiK_Addon_Builder.Sandbox.getLootComponentWeight()
	local installModule = "GSSiK_Addon_Builder.GS_DigitalWhiteboard"
	local manualBuilder = "GSSiK_Addon_Builder.GS_Manual_Builder"
	local manualDiskProgram = "GSSiK_Addon_Builder.GS_Manual_Builder_DiskProgram"
	local componentItems = {
		"GSSiK_Addon_Builder.GS_DigitalWhiteboard_Frame",
		"GSSiK_Addon_Builder.GS_DigitalWhiteboard_Screen",
		"GSSiK_Addon_Builder.GS_DigitalWhiteboard_Stylus",
	}
	local bookLists = {
		"LibraryBooks", "LibraryMagazines", "UniversityLibraryMagazines",
		"LivingRoomShelf", "MagazineRackMixed", "MagazineRackPaperback", "MagazineRackFancy",
		"CrateMagazines", "ElectronicStoreMagazines", "OfficeDesk", "ToolStoreBooks",
	}
	for i = 1, #bookLists do
		addToList(bookLists[i], manualBuilder, manualW)
		addToList(bookLists[i], manualDiskProgram, diskManualW)
	end
	local rareLists = {
		"ToolStoreTools", "CarpenterTools", "GarageTools",
		"ElectronicStoreMisc", "CrateElectronics", "ToolStoreCarpentry",
	}
	for i = 1, #rareLists do
		addToList(rareLists[i], installModule, moduleW)
	end

	-- Las 3 piezas sueltas se encuentran mas a menudo que la pizarra ya
	-- montada, en tiendas de electronica y talleres (coherente con marco
	-- metalico, panel y lapiz optico).
	local componentLists = {
		"ElectronicStoreMisc", "ElectronicStoreComputers", "GarageTools",
		"ToolStoreTools", "CrateElectronics", "OfficeDesk",
	}
	for i = 1, #componentLists do
		for j = 1, #componentItems do
			addToList(componentLists[i], componentItems[j], componentW)
		end
	end

	-- GS_FloppyDisk_Builder ya programado: sitios de electronica/oficina,
	-- sin las estanterias de salon/biblioteca.
	local installDiskW = GSSiK_Addon_Builder.Sandbox.getLootInstallDiskWeight()
	local installDisk = "GSSiK_Addon_Builder.GS_FloppyDisk_Builder"
	local diskLists = { "OfficeDesk", "ElectronicStoreMisc", "ToolStoreBooks" }
	for i = 1, #diskLists do
		addToList(diskLists[i], installDisk, installDiskW)
	end

	GSSiK_Addon_Builder.Loot.registered = true
end

GSSiK_Addon_Builder.Loot.register()
