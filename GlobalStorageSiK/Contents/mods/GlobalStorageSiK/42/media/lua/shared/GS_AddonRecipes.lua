--[[
	GlobalStorageSiK - Recetas de módulos addon (craft en terminal)
	Autor: SiK
	Fecha: 2025-06-27
	Descripción: Serializa recetas de módulos registrados y ejecuta craft en servidor.
]]

require "GS_AddonRegistry"
require "GS_CraftUtils"
require "GS_Sandbox"
require "GS_I18n"
require "GS_InventorySync"

GlobalStorageSiK.AddonRecipes = GlobalStorageSiK.AddonRecipes or {}

---@param fullType string|nil
---@return string
function GlobalStorageSiK.AddonRecipes.displayNameForType(fullType)
	if not fullType then
		return "?"
	end
	local item = instanceItem(fullType)
	if item and item.getName then
		return item:getName()
	end
	return fullType
end

local displayNameForType = GlobalStorageSiK.AddonRecipes.displayNameForType

---@param player IsoPlayer|nil
---@param fullType string|nil
---@return number
local function countItem(player, fullType)
	if not player or not fullType or not player.getInventory then
		return 0
	end
	local inv = player:getInventory()
	if not inv or not inv.getItemCountRecurse then
		return 0
	end
	return inv:getItemCountRecurse(fullType) or 0
end

---@param addonId string
---@return string
function GlobalStorageSiK.AddonRecipes.recipeCardId(addonId)
	return "addon:" .. tostring(addonId or "")
end

---@param recipeCardId string|nil
---@return string|nil
function GlobalStorageSiK.AddonRecipes.addonIdFromCardId(recipeCardId)
	if not recipeCardId or string.sub(recipeCardId, 1, 6) ~= "addon:" then
		return nil
	end
	local addonId = string.sub(recipeCardId, 7)
	if addonId == "" then
		return nil
	end
	return addonId
end

---@param def table
---@return table[]
function GlobalStorageSiK.AddonRecipes.getModuleIngredients(def)
	if not def then
		return {}
	end
	if def.moduleIngredients and #def.moduleIngredients > 0 then
		return def.moduleIngredients
	end
	return {}
end

---@param player IsoPlayer|nil
---@param def table|nil
---@return boolean
---@return string|nil
function GlobalStorageSiK.AddonRecipes.canCraftModule(player, def)
	if not player or not def then
		return false, "invalid"
	end
	if not GlobalStorageSiK.AddonRegistry.isModActive(def.id) then
		return false, "mod_off"
	end
	if not GlobalStorageSiK.AddonRegistry.playerKnowsModuleRecipe(player, def.id) then
		return false, "book"
	end
	local skillLevel = def.moduleSkillLevel or GlobalStorageSiK.AddonRegistry.DEFAULT_MODULE_SKILL
	local skillHave = GlobalStorageSiK.CraftUtils.getElectricityLevel(player)
	if skillHave < skillLevel then
		return false, "skill"
	end
	if GlobalStorageSiK.Sandbox.requireWorkbench() then
		local onDedicated = isServer and isServer()
		if not onDedicated then
			if not GlobalStorageSiK.CraftUtils.isNearWorkbench(player) then
				return false, "workbench"
			end
			if not GlobalStorageSiK.CraftUtils.hasCraftLight(player, def.moduleRecipeName) then
				return false, "light"
			end
		end
	end
	for i = 1, #GlobalStorageSiK.AddonRecipes.getModuleIngredients(def) do
		local ing = GlobalStorageSiK.AddonRecipes.getModuleIngredients(def)[i]
		if countItem(player, ing.item) < (ing.count or 1) then
			return false, "materials"
		end
	end
	return true, nil
end

---@param player IsoPlayer|nil
---@param addonId string
---@return table|nil
function GlobalStorageSiK.AddonRecipes.serializeModuleForClient(player, addonId)
	local def = GlobalStorageSiK.AddonRegistry.get(addonId)
	if not def then
		return nil
	end
	local ingredients = {}
	local ingDefs = GlobalStorageSiK.AddonRecipes.getModuleIngredients(def)
	for i = 1, #ingDefs do
		local ing = ingDefs[i]
		local have = player and countItem(player, ing.item) or 0
		table.insert(ingredients, {
			item = ing.item,
			count = ing.count or 1,
			have = have,
			displayName = displayNameForType(ing.item),
			ok = have >= (ing.count or 1),
		})
	end
	local skillLevel = def.moduleSkillLevel or GlobalStorageSiK.AddonRegistry.DEFAULT_MODULE_SKILL
	local skillHave = player and GlobalStorageSiK.CraftUtils.getElectricityLevel(player) or 0
	local knowsBook = player and GlobalStorageSiK.AddonRegistry.playerKnowsModuleRecipe(player, addonId)
	local nearBench = not GlobalStorageSiK.Sandbox.requireWorkbench()
	local hasLight = true
	if player and not (isServer and isServer()) then
		nearBench = nearBench or GlobalStorageSiK.CraftUtils.isNearWorkbench(player)
		hasLight = GlobalStorageSiK.CraftUtils.hasCraftLight(player, def.moduleRecipeName)
	end
	local canCraft = false
	if player then
		canCraft = GlobalStorageSiK.AddonRecipes.canCraftModule(player, def)
	end
	return {
		id = GlobalStorageSiK.AddonRecipes.recipeCardId(addonId),
		addonId = addonId,
		recipeName = def.moduleRecipeName,
		output = def.itemType,
		outputDisplay = displayNameForType(def.itemType),
		manualDisplay = displayNameForType(def.magazineType),
		manualItem = def.magazineType,
		skillLevel = skillLevel,
		skillHave = skillHave,
		skillOk = skillHave >= skillLevel,
		knowsBook = knowsBook == true,
		nearWorkbench = nearBench,
		hasCraftLight = hasLight,
		requireLight = GlobalStorageSiK.Sandbox.requireWorkbench()
			and not GlobalStorageSiK.CraftUtils.recipeAllowsDarkCraft(def.moduleRecipeName),
		requireBooks = true,
		requireWorkbench = GlobalStorageSiK.Sandbox.requireWorkbench(),
		ingredients = ingredients,
		canCraft = canCraft == true,
		freeCraft = false,
	}
end

---@param player IsoPlayer|nil
---@return table
function GlobalStorageSiK.AddonRecipes.serializeAllForClient(player)
	local recipes = {}
	for _, def in ipairs(GlobalStorageSiK.AddonRegistry.listSorted()) do
		if GlobalStorageSiK.AddonRegistry.isModActive(def.id) then
			local row = GlobalStorageSiK.AddonRecipes.serializeModuleForClient(player, def.id)
			if row then
				recipes[#recipes + 1] = row
			end
		end
	end
	return { recipes = recipes }
end

---@param player IsoPlayer
---@param addonId string
---@return boolean
---@return string
function GlobalStorageSiK.AddonRecipes.craftModule(player, addonId)
	local def = GlobalStorageSiK.AddonRegistry.get(addonId)
	if not def or not player then
		return false, GlobalStorageSiK.I18n.text("IGUI_GS_CraftFail")
	end
	local ok, reason = GlobalStorageSiK.AddonRecipes.canCraftModule(player, def)
	if not ok then
		if reason == "skill" then
			return false, GlobalStorageSiK.I18n.text("IGUI_GS_CraftSkillFail", def.moduleSkillLevel or 5)
		end
		if reason == "book" then
			return false, GlobalStorageSiK.I18n.text("IGUI_GS_CraftBookFail")
		end
		if reason == "workbench" then
			return false, GlobalStorageSiK.I18n.text("IGUI_GS_CraftWorkbenchFail")
		end
		if reason == "light" then
			return false, GlobalStorageSiK.I18n.text("IGUI_GS_CraftLightFail")
		end
		return false, GlobalStorageSiK.I18n.text("IGUI_GS_CraftMaterialsFail")
	end
	local inv = player:getInventory()
	if not inv then
		return false, GlobalStorageSiK.I18n.text("IGUI_GS_CraftFail")
	end
	for i = 1, #GlobalStorageSiK.AddonRecipes.getModuleIngredients(def) do
		local ing = GlobalStorageSiK.AddonRecipes.getModuleIngredients(def)[i]
		for _ = 1, (ing.count or 1) do
			local item = inv:getFirstTypeRecurse(ing.item)
			if not item then
				return false, GlobalStorageSiK.I18n.text("IGUI_GS_CraftMaterialsFail")
			end
			GlobalStorageSiK.InventorySync.removeItem(inv, item)
		end
	end
	local output = instanceItem(def.itemType)
	if not output then
		return false, GlobalStorageSiK.I18n.text("IGUI_GS_CraftFail")
	end
	if GlobalStorageSiK.ItemHooks and GlobalStorageSiK.ItemHooks.applyForOutput then
		GlobalStorageSiK.ItemHooks.applyForOutput(def.itemType, output)
	end
	if not GlobalStorageSiK.InventorySync.addToPlayer(player, output) then
		return false, GlobalStorageSiK.I18n.text("IGUI_GS_CraftFail")
	end
	-- addToPlayer ya replica el alta mediante el paquete vanilla del
	-- contenedor. Un sync completo adicional puede llegar fuera de orden y
	-- restaurar el inventario anterior.
	return true, GlobalStorageSiK.I18n.text("IGUI_GS_CraftOk", displayNameForType(def.itemType))
end
