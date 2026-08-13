--[[

	GlobalStorageSiK - Recetas de terminal y craft directo

	Autor: SiK

	Fecha: 2025-06-24

	Descripción: Definiciones para UI bloqueada y craft en servidor (sandbox).

]]



require "GS_Config"

require "GS_Sandbox"

require "GS_I18n"

require "GS_CraftUtils"

require "GS_InventorySync"
require "GS_TerminalAccess"
require "GS_Deposit"



GlobalStorageSiK.TerminalRecipes = {}

GlobalStorageSiK.TerminalRecipes.ING_VANILLA_DESKTOP = "vanilla_desktop"

-- Sentinel especial para el disquete GS (requerido pero no consumido)
GlobalStorageSiK.TerminalRecipes.ING_FLOPPY = "GlobalStorageSiK.GS_FloppyDisk"

-- LIST vacía a propósito (v1.2.58): las 3 recetas antiguas que vivían aquí
-- (terminal_install, terminal_unit, vanilla_pc) apuntaban a craftRecipes
-- vanilla ya eliminados (ver globalstoragesik_recipes.txt) - el método
-- nuevo (lector+disquete, o "Conseguir PC") es el único soportado. Se deja
-- la tabla vacía en vez de borrar el módulo entero por si algo del código
-- de UI del terminal bloqueado todavía itera sobre ella de forma segura.
GlobalStorageSiK.TerminalRecipes.LIST = {
}



--- Nivel de habilidad requerido según sandbox.

---@param recipeId string

---@return number

function GlobalStorageSiK.TerminalRecipes.getSkillLevel(recipeId)

	if recipeId == "terminal_install" then

		return GlobalStorageSiK.Sandbox.getInstallTerminalSkill()

	end

	if recipeId == "terminal_unit" then

		return GlobalStorageSiK.Sandbox.getTerminalUnitSkill()

	end

	if recipeId == "vanilla_pc" then
		-- Sin sandbox var propia todavia - mismo valor que declara
		-- "Build Desktop Computer" en globalstoragesik_recipes.txt
		-- (SkillRequired = Electricity:4), solo para que la tarjeta de la
		-- pantalla de bloqueo muestre el requisito real en vez de "0".
		return 4
	end

	return 0

end



--- Busca un ítem en inventario del jugador por ID de instancia.
---@param player IsoPlayer|nil
---@param itemId number|nil
---@return InventoryItem|nil
function GlobalStorageSiK.TerminalRecipes.findInventoryItemById(player, itemId)
	if not player or not itemId then
		return nil
	end
	if GlobalStorageSiK.Deposit and GlobalStorageSiK.Deposit.findItemById then
		return GlobalStorageSiK.Deposit.findItemById(player, itemId)
	end
	if not player.getInventory then
		return nil
	end
	local inv = player:getInventory()
	if not inv or not inv.getItems then
		return nil
	end
	local all = inv:getItems()
	for i = 0, all:size() - 1 do
		local item = all:get(i)
		if item and item.getID and item:getID() == itemId then
			return item
		end
	end
	return nil
end

--- Valida el ordenador vanilla concreto para instalar terminal.
---@param player IsoPlayer|nil
---@param desktopItem InventoryItem|nil
---@return boolean ok
---@return string|nil reason
local function validateInstallDesktop(player, desktopItem)
	if not player or not desktopItem then
		return false, "desktop"
	end
	if not GlobalStorageSiK.TerminalAccess.isVanillaDesktopItem(desktopItem) then
		return false, "desktop"
	end
	local inv = player:getInventory()
	if not inv or not inv.contains or not inv:contains(desktopItem) then
		return false, "desktop"
	end
	return true, nil
end

--- Busca receta por id.

---@param recipeId string

---@return table|nil

function GlobalStorageSiK.TerminalRecipes.getById(recipeId)

	for i = 1, #GlobalStorageSiK.TerminalRecipes.LIST do

		local recipe = GlobalStorageSiK.TerminalRecipes.LIST[i]

		if recipe.id == recipeId then

			return recipe

		end

	end

	return nil

end



--- Cuenta ítems en inventario del jugador (fullType o ingrediente especial).

---@param player IsoPlayer

---@param fullType string

---@return number

local function countItem(player, fullType)

	if not player or not fullType then

		return 0

	end

	if fullType == GlobalStorageSiK.TerminalRecipes.ING_VANILLA_DESKTOP then

		if GlobalStorageSiK.TerminalAccess and GlobalStorageSiK.TerminalAccess.countVanillaDesktopItems then

			return GlobalStorageSiK.TerminalAccess.countVanillaDesktopItems(player)

		end

		return 0

	end

	local inv = player:getInventory()

	if not inv or not inv.getItemCountRecurse then

		return 0

	end

	return inv:getItemCountRecurse(fullType) or 0

end



--- Nombre legible de un ítem.
---@param fullType string
---@return string
local function displayNameForType(fullType)
	if not fullType then
		return "?"
	end
	if GlobalStorageSiK.I18n and GlobalStorageSiK.I18n.typeDisplayName then
		return GlobalStorageSiK.I18n.typeDisplayName(fullType)
	end
	return fullType
end

--- Nombre legible de un ingrediente de receta.
---@param ing table
---@return string
local function ingredientDisplayName(ing)
	if not ing then
		return "?"
	end
	if ing.item == GlobalStorageSiK.TerminalRecipes.ING_VANILLA_DESKTOP then
		return GlobalStorageSiK.I18n.text("IGUI_GS_IngVanillaDesktop")
	end
	if ing.item == GlobalStorageSiK.TerminalRecipes.ING_FLOPPY then
		return GlobalStorageSiK.I18n.text("IGUI_GS_IngFloppyDisk")
	end
	return displayNameForType(ing.item)
end

--- Nombre legible del resultado de craft (muebles moveable devuelven el sprite vanilla).

---@param recipe table

---@return string

local function outputDisplayForRecipe(recipe)

	if recipe and recipe.outputDisplayKey then

		return GlobalStorageSiK.I18n.text(recipe.outputDisplayKey)

	end

	return displayNameForType(recipe and recipe.output)

end



--- Comprueba si el jugador cumple requisitos de una receta.

---@param player IsoPlayer
---@param recipe table
---@param opts table|nil desktopItem: ordenador vanilla concreto al instalar
---@return boolean ok
---@return string|nil reason
function GlobalStorageSiK.TerminalRecipes.canCraft(player, recipe, opts)
	opts = opts or {}

	if not player or not recipe then

		return false, "invalid"

	end



	if GlobalStorageSiK.Sandbox.requireRecipeBooks()

		and not GlobalStorageSiK.CraftUtils.knowsRecipe(player, recipe.recipeName) then

		return false, "book"

	end



	if GlobalStorageSiK.Sandbox.requireWorkbench() then
		local onDedicated = isServer and isServer()
		if not onDedicated then
			if not GlobalStorageSiK.CraftUtils.isNearWorkbench(player) then
				return false, "workbench"
			end
			if not GlobalStorageSiK.CraftUtils.hasCraftLight(player, recipe.recipeName) then
				return false, "light"
			end
		end
	end



	local skillLevel = GlobalStorageSiK.TerminalRecipes.getSkillLevel(recipe.id)

	if skillLevel > 0 then

		local have = GlobalStorageSiK.CraftUtils.getElectricityLevel(player)

		if have < skillLevel then

			return false, "skill"

		end

	end



	if not GlobalStorageSiK.Sandbox.isFreeCraft(recipe.id) then
		if recipe.id == "terminal_install" then
			local okDesktop, desktopReason = validateInstallDesktop(player, opts.desktopItem)
			if not okDesktop then
				return false, desktopReason or "desktop"
			end
		end

		for i = 1, #(recipe.ingredients or {}) do
			local ing = recipe.ingredients[i]
			if ing.item == GlobalStorageSiK.TerminalRecipes.ING_VANILLA_DESKTOP then
				if recipe.id == "terminal_install" then
					-- Ya validado arriba con opts.desktopItem concreto.
				elseif countItem(player, ing.item) < ing.count then
					return false, "desktop"
				end
			elseif ing.item == GlobalStorageSiK.TerminalRecipes.ING_FLOPPY then
				if countItem(player, ing.item) < ing.count then
					return false, "floppy"
				end
			else
				local haveCount = countItem(player, ing.item)
				if haveCount < ing.count then
					return false, "materials"
				end
			end
		end
	end

	return true

end



--- Consume materiales de una receta.
---@param player IsoPlayer
---@param recipe table
---@param opts table|nil
---@return boolean ok
---@return string|nil reason
local function consumeRecipeMaterials(player, recipe, opts)
	opts = opts or {}
	if not player or not recipe then
		return false, "invalid"
	end
	local inv = player:getInventory()
	if not inv then
		return false, "invalid"
	end
	if GlobalStorageSiK.Sandbox.isFreeCraft(recipe.id) then
		return true, nil
	end
	if recipe.id == "terminal_install" then
		local okDesktop, desktopReason = validateInstallDesktop(player, opts.desktopItem)
		if not okDesktop then
			return false, desktopReason or "desktop"
		end
	end
	for i = 1, #(recipe.ingredients or {}) do
		local ing = recipe.ingredients[i]
		if ing.keep then
			-- Ingrediente requerido pero no consumido (ej: disquete)
			local have = countItem(player, ing.item)
			if have < ing.count then
				return false, "materials"
			end
		else
			for _ = 1, ing.count do
				local item = nil
				if ing.item == GlobalStorageSiK.TerminalRecipes.ING_VANILLA_DESKTOP then
					item = opts.desktopItem
				else
					item = inv:getFirstTypeRecurse(ing.item)
				end
				if not item then
					if ing.item == GlobalStorageSiK.TerminalRecipes.ING_VANILLA_DESKTOP then
						return false, "desktop"
					end
					return false, "materials"
				end
				GlobalStorageSiK.InventorySync.removeItem(inv, item)
			end
		end
	end
	return true, nil
end



--- Consume materiales y entrega el resultado.

---@param player IsoPlayer
---@param recipeId string
---@param opts table|nil
---@return boolean ok
---@return string message
function GlobalStorageSiK.TerminalRecipes.craft(player, recipeId, opts)
	opts = opts or {}

	local recipe = GlobalStorageSiK.TerminalRecipes.getById(recipeId)

	if not recipe or not player then

		return false, GlobalStorageSiK.I18n.text("IGUI_GS_CraftFail")

	end

	local ok, reason = GlobalStorageSiK.TerminalRecipes.canCraft(player, recipe, opts)

	if not ok then

		if reason == "skill" then

			return false, GlobalStorageSiK.I18n.text("IGUI_GS_CraftSkillFail", GlobalStorageSiK.TerminalRecipes.getSkillLevel(recipeId))

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

		if reason == "desktop" then

			return false, GlobalStorageSiK.I18n.text("IGUI_GS_CraftDesktopFail")

		end

		if reason == "floppy" then

			return false, GlobalStorageSiK.I18n.text("IGUI_GS_CraftFloppyFail")

		end

		return false, GlobalStorageSiK.I18n.text("IGUI_GS_CraftMaterialsFail")

	end

	local inv = player:getInventory()

	if not inv then

		return false, GlobalStorageSiK.I18n.text("IGUI_GS_CraftFail")

	end

	local consumed, failReason = consumeRecipeMaterials(player, recipe, opts)
	if not consumed then
		if failReason == "desktop" then
			return false, GlobalStorageSiK.I18n.text("IGUI_GS_CraftDesktopFail")
		end
		if failReason == "materials" then
			return false, GlobalStorageSiK.I18n.text("IGUI_GS_CraftMaterialsFail")
		end
		return false, GlobalStorageSiK.I18n.text("IGUI_GS_CraftFail")
	end

	local output = instanceItem(recipe.output)

	if not output then

		return false, GlobalStorageSiK.I18n.text("IGUI_GS_CraftFail")

	end

	if recipe.outputCount and recipe.outputCount > 1 and output.setCount then

		output:setCount(recipe.outputCount)

	end

	if GlobalStorageSiK.ItemHooks and GlobalStorageSiK.ItemHooks.applyForOutput then
		GlobalStorageSiK.ItemHooks.applyForOutput(recipe.output, output)
	end

	if not GlobalStorageSiK.InventorySync.addToPlayer(player, output) then

		return false, GlobalStorageSiK.I18n.text("IGUI_GS_CraftFail")

	end

	GlobalStorageSiK.InventorySync.notifyPlayer(player)

	return true, GlobalStorageSiK.I18n.text("IGUI_GS_CraftOk", outputDisplayForRecipe(recipe))

end



--- Serializa una receta con estado de inventario (una entrada).
---@param player IsoPlayer|nil
---@param recipe table
---@param options table|nil
---@return table
local function serializeRecipeForClient(player, recipe, options)
	options = options or {}
	local ingredients = {}
	local freeCraft = GlobalStorageSiK.Sandbox.isFreeCraft(recipe.id)
	for j = 1, #(recipe.ingredients or {}) do
		local ing = recipe.ingredients[j]
		local have = player and countItem(player, ing.item) or 0
		if ing.item == GlobalStorageSiK.TerminalRecipes.ING_VANILLA_DESKTOP and options.desktopItem then
			have = GlobalStorageSiK.TerminalAccess.isVanillaDesktopItem(options.desktopItem) and 1 or 0
		end
		table.insert(ingredients, {
			item = ing.item,
			count = ing.count,
			have = have,
			displayName = ingredientDisplayName(ing),
			ok = freeCraft or have >= ing.count,
		})
	end
	local skillLevel = GlobalStorageSiK.TerminalRecipes.getSkillLevel(recipe.id)
	local skillHave = player and GlobalStorageSiK.CraftUtils.getElectricityLevel(player) or 0
	local knowsBook = not GlobalStorageSiK.Sandbox.requireRecipeBooks()
		or (player and GlobalStorageSiK.CraftUtils.knowsRecipe(player, recipe.recipeName))
	local nearBench = not GlobalStorageSiK.Sandbox.requireWorkbench()
	local hasLight = true
	if not options.skipWorldChecks and player then
		nearBench = nearBench or GlobalStorageSiK.CraftUtils.isNearWorkbench(player)
		hasLight = GlobalStorageSiK.CraftUtils.hasCraftLight(player, recipe.recipeName)
	end
	local canCraft = false
	if player and not options.skipWorldChecks then
		canCraft = GlobalStorageSiK.TerminalRecipes.canCraft(player, recipe, options)
	end
	return {
		id = recipe.id,
		recipeName = recipe.recipeName,
		output = recipe.output,
		outputDisplay = outputDisplayForRecipe(recipe),
		manualDisplay = displayNameForType(recipe.manualItem),
		manualItem = recipe.manualItem,
		skillLevel = skillLevel,
		skillHave = skillHave,
		skillOk = skillHave >= skillLevel,
		knowsBook = knowsBook,
		nearWorkbench = nearBench,
		hasCraftLight = hasLight,
		requireLight = GlobalStorageSiK.Sandbox.requireWorkbench()
			and not GlobalStorageSiK.CraftUtils.recipeAllowsDarkCraft(recipe.recipeName),
		requireBooks = GlobalStorageSiK.Sandbox.requireRecipeBooks(),
		requireWorkbench = GlobalStorageSiK.Sandbox.requireWorkbench(),
		ingredients = ingredients,
		canCraft = canCraft,
		freeCraft = freeCraft,
	}
end

--- Estado de la receta instalar terminal para un ordenador vanilla concreto.
---@param player IsoPlayer|nil
---@param desktopItem InventoryItem|nil
---@return table|nil
function GlobalStorageSiK.TerminalRecipes.serializeInstallForClient(player, desktopItem)
	local recipe = GlobalStorageSiK.TerminalRecipes.getById("terminal_install")
	if not recipe then
		return nil
	end
	return serializeRecipeForClient(player, recipe, { desktopItem = desktopItem })
end

--- Serializa recetas con estado de inventario para el cliente.
---@param player IsoPlayer|nil
---@param options table|nil skipWorldChecks, blockedOnly, desktopItem
---@return table
function GlobalStorageSiK.TerminalRecipes.serializeForClient(player, options)
	options = options or {}
	if isServer and isServer() then
		options.skipWorldChecks = true
	end

	local recipes = {}

	-- Recetas que se sirven en la ventana de bloqueo cuando blockedOnly=true:
	-- el terminal antiguo (compatibilidad) y el PC vanilla liso (para quien
	-- no encuentre uno en el mundo). ANTES esta lista solo dejaba pasar
	-- "terminal_unit" aqui mismo, asi que aunque "vanilla_pc" ya estuviera en
	-- LIST y en el filtro del lado cliente (GS_TerminalUI_BlockedPanel.lua),
	-- el servidor nunca la serializaba - nunca llegaba a la ventana.
	local BLOCKED_ONLY_IDS = { terminal_unit = true, vanilla_pc = true }

	for i = 1, #GlobalStorageSiK.TerminalRecipes.LIST do
		local recipe = GlobalStorageSiK.TerminalRecipes.LIST[i]
		if not options.blockedOnly or BLOCKED_ONLY_IDS[recipe.id] then
			table.insert(recipes, serializeRecipeForClient(player, recipe, options))
		end
	end

	return {
		recipes = recipes,
		wirelessRange = GlobalStorageSiK.Sandbox.getWirelessRange(),
		proximityRange = GlobalStorageSiK.Sandbox.getTerminalProximityRange(),
	}
end

