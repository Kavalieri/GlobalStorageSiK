--[[

	GSSiK Addon Craft - Loot procedural

	Autor: SiK

	Fecha: 2025-06-27

]]



require "Items/ProceduralDistributions"

require "GSSiK_Addon_Craft_Sandbox"



GSSiK_Addon_Craft = GSSiK_Addon_Craft or {}

GSSiK_Addon_Craft.Loot = GSSiK_Addon_Craft.Loot or {}



---@param listName string

---@param itemType string

---@param weight number

local function addToList(listName, itemType, weight)

	local list = ProceduralDistributions.list[listName]

	if not list or not list.items or not weight or weight <= 0 then

		return

	end

	table.insert(list.items, itemType)

	table.insert(list.items, weight)

end



function GSSiK_Addon_Craft.Loot.register()

	if not ProceduralDistributions or not ProceduralDistributions.list then

		return

	end



	local moduleW = GSSiK_Addon_Craft.Sandbox.getLootPeripheralWeight()

	local manualW = GSSiK_Addon_Craft.Sandbox.getLootMagazineWeight()

	local diskManualW = GSSiK_Addon_Craft.Sandbox.getLootDiskProgramMagazineWeight()

	local componentW = GSSiK_Addon_Craft.Sandbox.getLootComponentWeight()

	local installDiskW = GSSiK_Addon_Craft.Sandbox.getLootInstallDiskWeight()

	local installModule = "GSSiK_Addon_Craft.GS_Printer3D"

	local manualCraft = "GSSiK_Addon_Craft.GS_Manual_Craft"

	local manualDiskProgram = "GSSiK_Addon_Craft.GS_Manual_Craft_DiskProgram"

	local installDisk = "GSSiK_Addon_Craft.GS_FloppyDisk_Craft"

	local componentItems = {

		"GSSiK_Addon_Craft.GS_Printer3D_Frame",

		"GSSiK_Addon_Craft.GS_Printer3D_ExtruderHead",

		"GSSiK_Addon_Craft.GS_Printer3D_ControlBoard",

	}



	local bookLists = {

		"LibraryBooks",

		"LivingRoomShelf",

		"MagazineRackMixed",

		"ElectronicStoreBooks",

		"ElectronicStoreMisc",

		"OfficeDesk",

		"StoreShelfElectronics",

	}



	for i = 1, #bookLists do

		addToList(bookLists[i], manualCraft, manualW)

		addToList(bookLists[i], manualDiskProgram, diskManualW)

	end



	-- GS_FloppyDisk_Craft ya programado: mismos sitios de electronica/oficina

	-- que sus manuales, sin las estanterias de salon/biblioteca (un disco

	-- no encaja ahi tematicamente como si lo hace una revista).

	local diskLists = {

		"OfficeDesk", "ElectronicStoreMisc", "StoreShelfElectronics",

	}

	for i = 1, #diskLists do

		addToList(diskLists[i], installDisk, installDiskW)

	end



	local rareLists = {

		"ArmySurplusMisc",

		"ArmyStorageOutfit",

		"SecurityLockers",

		"PoliceEvidence",

		"ElectronicStoreMisc",

		"SafehouseLoot",

	}



	for i = 1, #rareLists do

		addToList(rareLists[i], installModule, moduleW)

	end



	-- Las 3 piezas sueltas se encuentran mas a menudo que la impresora ya

	-- montada, en tiendas de electronica y garajes/talleres (coherente con

	-- chasis metalico, cabezal y placa de control).

	local componentLists = {

		"ElectronicStoreMisc",

		"ElectronicStoreShelf",

		"GarageMisc",

		"ToolStoreTools",

		"WarehouseElectronics",

	}

	for i = 1, #componentLists do

		for j = 1, #componentItems do

			addToList(componentLists[i], componentItems[j], componentW)

		end

	end

end



GSSiK_Addon_Craft.Loot.register()

