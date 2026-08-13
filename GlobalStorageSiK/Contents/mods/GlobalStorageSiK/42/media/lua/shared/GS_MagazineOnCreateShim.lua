--[[
	GlobalStorageSiK - Compat OnCreate revistas B42
	Autor: SiK
	Fecha: 2025-06-27
	Descripción: Alias SpecialLootSpawns → ItemCodeOnCreate (saves/mods con OnCreate legacy).
]]

local function installMagazineOnCreateShim()
	if not ItemCodeOnCreate or not ItemCodeOnCreate.onCreateRecipeMagazine then
		return
	end
	SpecialLootSpawns = SpecialLootSpawns or {}
	if not SpecialLootSpawns.OnCreateRecipeMagazine then
		SpecialLootSpawns.OnCreateRecipeMagazine = ItemCodeOnCreate.onCreateRecipeMagazine
	end
end

installMagazineOnCreateShim()
if Events and Events.OnGameBoot then
	Events.OnGameBoot.Add(installMagazineOnCreateShim)
end
