--[[
	GlobalStorageSiK - Loot procedural (manual terminal)
	Autor: SiK
	Fecha: 2025-06-24
]]

require "Items/ProceduralDistributions"
require "GS_Sandbox"

GlobalStorageSiK.Loot = GlobalStorageSiK.Loot or {}

--- Inserta ítem + peso en una lista procedural.
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

--- Registra spawns según sandbox.
function GlobalStorageSiK.Loot.register()
	if not ProceduralDistributions or not ProceduralDistributions.list then
		return
	end

	local bookW = GlobalStorageSiK.Sandbox.getLootBooksWeight()
	local manualUnit = "GlobalStorageSiK.GS_Manual_TerminalUnit"

	local bookLists = {
		"LibraryBooks",
		"LivingRoomShelf",
		"LivingRoomShelfNoTapes",
		"MagazineRackMixed",
		"ElectronicStoreBooks",
		"ElectronicStoreMisc",
		"OfficeDesk",
		"OfficeDeskHome",
		"StoreShelfElectronics",
		"ToolStoreBooks",
		"PostOfficeMagazines",
	}

	for i = 1, #bookLists do
		addToList(bookLists[i], manualUnit, bookW)
	end
end

GlobalStorageSiK.Loot.register()
