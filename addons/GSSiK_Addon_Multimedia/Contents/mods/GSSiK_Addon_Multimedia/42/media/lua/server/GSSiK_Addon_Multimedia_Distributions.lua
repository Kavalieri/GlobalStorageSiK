require "Items/ProceduralDistributions"
local Sandbox = require "GSSiK_Addon_Multimedia_Sandbox"
local M = GSSiK_Addon_Multimedia
if M._lootRegistered then return end
local function add(listName, item, weight)
	local list = ProceduralDistributions.list[listName]
	if not list or not list.items or weight <= 0 then return end
	local fullType = "GSSiK_Addon_Multimedia." .. item
	for i = 1, #list.items, 2 do if list.items[i] == fullType then return end end
	list.items[#list.items + 1] = fullType
	list.items[#list.items + 1] = weight
end
local books = { "LibraryBooks", "LibraryMagazines", "UniversityLibraryMagazines",
	"LivingRoomShelf", "MagazineRackMixed", "MagazineRackPaperback", "MagazineRackFancy",
	"CrateMagazines", "ElectronicStoreMagazines", "OfficeDesk", "ToolStoreBooks" }
for i = 1, #books do
	add(books[i], "GS_Manual_Multimedia", Sandbox.loot("LootMagazineWeight"))
	add(books[i], "GS_Manual_Multimedia_DiskProgram", Sandbox.loot("LootDiskProgramMagazineWeight"))
end
local electronics = { "ElectronicStoreMisc", "CrateElectronics", "ElectronicStoreComputers", "GarageTools" }
for i = 1, #electronics do
	add(electronics[i], "GS_VHSController", Sandbox.loot("LootPeripheralWeight"))
	for _, item in ipairs({ "GS_VHSHousing", "GS_VHSTransport", "GS_VHSSignalBoard" }) do
		add(electronics[i], item, Sandbox.loot("LootComponentWeight"))
	end
end
for _, list in ipairs({ "OfficeDesk", "ElectronicStoreMisc", "ToolStoreBooks" }) do
	add(list, "GS_FloppyDisk_Multimedia", Sandbox.loot("LootInstallDiskWeight"))
end
M._lootRegistered = true
