--[[
	GlobalStorageSiK - Catálogo y sondeo de recetas (spike craft terminal)
	Autor: SiK
	Fecha: 2025-06-24
	Descripción: Cuenta recetas vanilla válidas con inventario y/o red.
]]

require "GS_CraftingBridge"
require "GS_Workstations"

GlobalStorageSiK.CraftCatalog = {}

local SAMPLE_LIMIT = 40

--- Recoge contenedores del jugador (inventario + mochilas equipadas).
---@param player IsoPlayer
---@return table
function GlobalStorageSiK.CraftCatalog.collectPlayerContainers(player)
	local list = {}
	local seen = {}
	if not player then
		return list
	end
	local inv = player:getInventory()
	if inv and not seen[inv] then
		seen[inv] = true
		table.insert(list, inv)
	end
	local worn = player.getWornItems and player:getWornItems() or nil
	if worn then
		for i = 0, worn:size() - 1 do
			local wornItem = worn:get(i)
			if wornItem and wornItem.getItem then
				local item = wornItem:getItem()
				if item and item.getInventory then
					local bag = item:getInventory()
					if bag and not seen[bag] then
						seen[bag] = true
						table.insert(list, bag)
					end
				end
			end
		end
	end
	return list
end

--- Contenedores para sondeo (jugador y opcionalmente red).
---@param player IsoPlayer
---@param networkId string|nil
---@param includeNetwork boolean
---@return table
function GlobalStorageSiK.CraftCatalog.collectProbeContainers(player, networkId, includeNetwork)
	local list = GlobalStorageSiK.CraftCatalog.collectPlayerContainers(player)
	if includeNetwork then
		return GlobalStorageSiK.CraftingBridge.mergeContainerLists(list, networkId)
	end
	return list
end

--- Nombre legible de una receta.
---@param recipe CraftRecipe
---@return string
function GlobalStorageSiK.CraftCatalog.getRecipeLabel(recipe)
	if not recipe then
		return "?"
	end
	if recipe.getName then
		local name = recipe:getName()
		if name and name ~= "" then
			return name
		end
	end
	if recipe.getOriginalname then
		return recipe:getOriginalname() or "?"
	end
	return "?"
end

--- Extrae tags de estación de una receta.
---@param recipe CraftRecipe
---@return string[]
function GlobalStorageSiK.CraftCatalog.getRecipeTags(recipe)
	local tags = {}
	if not recipe then
		return tags
	end
	if recipe.getTags then
		local ok, recipeTags = pcall(function()
			return recipe:getTags()
		end)
		if ok and recipeTags then
			for i = 0, recipeTags:size() - 1 do
				local tag = recipeTags:get(i)
				if tag and tag ~= "" then
					table.insert(tags, tag)
				end
			end
		end
	end
	if recipe.getNearItem then
		local ok, near = pcall(function()
			return recipe:getNearItem()
		end)
		if ok and near and near ~= "" then
			table.insert(tags, near)
		end
	end
	return tags
end

--- Obtiene lista de recetas (B42 CraftRecipe + legacy).
---@return ArrayList|nil
local function resolveRecipeList()
	local sm = (ScriptManager and ScriptManager.instance) or (getScriptManager and getScriptManager()) or nil
	if sm then
		if sm.getAllCraftRecipes then
			local ok, list = pcall(function()
				return sm:getAllCraftRecipes()
			end)
			if ok and list and list.size and list:size() > 0 then
				return list
			end
		end
		if sm.getAllRecipes then
			local ok, list = pcall(function()
				return sm:getAllRecipes()
			end)
			if ok and list and list.size and list:size() > 0 then
				return list
			end
		end
	end
	if getAllRecipes then
		local ok, list = pcall(getAllRecipes)
		if ok and list and list.size and list:size() > 0 then
			return list
		end
	end
	return nil
end

--- Convierte tabla Lua de contenedores a ArrayList (requerido por HandcraftLogic B42).
---@param containers table|ArrayList|nil
---@return ArrayList
function GlobalStorageSiK.CraftCatalog.toContainerArrayList(containers)
	local list = ArrayList.new()
	if not containers then
		return list
	end
	if containers.size and containers.get and containers.add and not containers.insert then
		for i = 0, containers:size() - 1 do
			local c = containers:get(i)
			if c then
				list:add(c)
			end
		end
		return list
	end
	for i = 1, #containers do
		local c = containers[i]
		if c then
			list:add(c)
		end
	end
	return list
end

--- Recoge contenedores del jugador (y red) como ArrayList para craft B42.
---@param player IsoPlayer
---@param networkId string|nil
---@param includeNetwork boolean
---@return ArrayList
function GlobalStorageSiK.CraftCatalog.collectProbeContainersArrayList(player, networkId, includeNetwork)
	local list = ArrayList.new()
	if not player then
		return list
	end

	local function addUnique(container)
		if not container then
			return
		end
		for i = 0, list:size() - 1 do
			if list:get(i) == container then
				return
			end
		end
		list:add(container)
	end

	if isClient and isClient() and ISInventoryPaneContextMenu and ISInventoryPaneContextMenu.getContainers then
		local vanilla = ISInventoryPaneContextMenu.getContainers(player)
		if vanilla then
			for i = 0, vanilla:size() - 1 do
				addUnique(vanilla:get(i))
			end
		end
	elseif ItemUtils and ItemUtils.getContainers then
		local utils = ItemUtils.getContainers(player)
		if utils then
			for i = 0, utils:size() - 1 do
				addUnique(utils:get(i))
			end
		end
	else
		local luaList = GlobalStorageSiK.CraftCatalog.collectPlayerContainers(player)
		for i = 1, #luaList do
			addUnique(luaList[i])
		end
	end

	if includeNetwork and networkId then
		local networkOnes = GlobalStorageSiK.CraftingBridge.collectNetworkContainers(networkId)
		for i = 1, #networkOnes do
			addUnique(networkOnes[i])
		end
	end

	return list
end

--- Indica si la receta es CraftRecipe (B42).
---@param recipe any
---@return boolean
local function isCraftRecipe(recipe)
	return recipe and instanceof and instanceof(recipe, "CraftRecipe")
end

--- Indica si la receta es Recipe legacy.
---@param recipe any
---@return boolean
local function isLegacyRecipe(recipe)
	return recipe and instanceof and instanceof(recipe, "Recipe")
end

--- Comprueba validez con HandcraftLogic (B42) o RecipeManager (legacy).
---@param recipe CraftRecipe|Recipe
---@param player IsoPlayer
---@param containers table|ArrayList
---@return boolean
function GlobalStorageSiK.CraftCatalog.isRecipeValid(recipe, player, containers)
	if not recipe or not player then
		return false
	end

	local containerList = GlobalStorageSiK.CraftCatalog.toContainerArrayList(containers)

	if isCraftRecipe(recipe) then
		if not HandcraftLogic or not HandcraftLogic.new then
			return false
		end
		local ok, result = pcall(function()
			local logic = HandcraftLogic.new(player, nil, nil)
			logic:setContainers(containerList)
			if logic.setRecipe then
				logic:setRecipe(recipe)
			else
				return false
			end
			return logic:canPerformCurrentRecipe()
		end)
		return ok and result == true
	end

	if isLegacyRecipe(recipe) and RecipeManager and RecipeManager.IsRecipeValid then
		local ok, result = pcall(RecipeManager.IsRecipeValid, recipe, player, nil, containerList)
		return ok and result == true
	end

	return false
end

--- Añade muestra si hay hueco.
---@param list string[]
---@param label string
local function pushSample(list, label)
	if #list < SAMPLE_LIMIT then
		table.insert(list, label)
	end
end

--- Sondea recetas disponibles (servidor).
---@param player IsoPlayer
---@param networkId string|nil
---@return table
function GlobalStorageSiK.CraftCatalog.probe(player, networkId)
	local result = {
		total = 0,
		validPlayer = 0,
		validNetwork = 0,
		validTerminalTags = 0,
		networkContainers = 0,
		samplesPlayer = {},
		samplesNetwork = {},
		samplesTerminal = {},
		error = nil,
	}

	if not player then
		result.error = "no_player"
		return result
	end

	local sm = getScriptManager and getScriptManager() or nil
	local recipes = resolveRecipeList()
	if not recipes then
		result.error = sm and "no_recipes" or "no_recipes_api"
		return result
	end

	local playerContainers = GlobalStorageSiK.CraftCatalog.collectProbeContainersArrayList(player, networkId, false)
	local networkContainers = GlobalStorageSiK.CraftCatalog.collectProbeContainersArrayList(player, networkId, true)
	result.networkContainers = math.max(0, networkContainers:size() - playerContainers:size())

	local terminalTags = GlobalStorageSiK.Workstations.collectCraftTags({ "TerminalBase" })
	result.total = recipes:size()
	local maxCheck = math.min(recipes:size(), 800)

	local okLoop, loopErr = pcall(function()
		for i = 0, maxCheck - 1 do
			local recipe = recipes:get(i)
			if recipe and isCraftRecipe(recipe) then
				local label = GlobalStorageSiK.CraftCatalog.getRecipeLabel(recipe)
				local tags = GlobalStorageSiK.CraftCatalog.getRecipeTags(recipe)
				local tagMatch = GlobalStorageSiK.Workstations.recipeMatchesTags(tags, terminalTags)

				local validPlayer = GlobalStorageSiK.CraftCatalog.isRecipeValid(recipe, player, playerContainers)
				local validNetwork = GlobalStorageSiK.CraftCatalog.isRecipeValid(recipe, player, networkContainers)

				if validPlayer then
					result.validPlayer = result.validPlayer + 1
					pushSample(result.samplesPlayer, label)
				end
				if validNetwork then
					result.validNetwork = result.validNetwork + 1
					pushSample(result.samplesNetwork, label)
				end
				if validNetwork and tagMatch then
					result.validTerminalTags = result.validTerminalTags + 1
					pushSample(result.samplesTerminal, label)
				end
			end
		end
		if maxCheck < recipes:size() then
			result.truncated = true
		end
	end)
	if not okLoop then
		result.error = tostring(loopErr)
	end

	return result
end
