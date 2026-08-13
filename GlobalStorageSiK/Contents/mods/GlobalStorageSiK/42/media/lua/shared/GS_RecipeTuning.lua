--[[
	GlobalStorageSiK - Ajuste de recetas según sandbox
	Autor: SiK
	Fecha: 2025-06-24
]]

require "GS_Sandbox"
require "GS_Debug"
require "GS_TerminalRecipes"

GlobalStorageSiK.RecipeTuning = GlobalStorageSiK.RecipeTuning or {}

--- Busca una craftRecipe B42 por nombre (variantes de módulo).
---@param sm ScriptManager
---@param recipeName string
---@return CraftRecipe|Recipe|nil
local function resolveCraftRecipe(sm, recipeName)
	if not sm or not recipeName then
		return nil
	end
	local variants = {
		recipeName,
		"GlobalStorageSiK." .. recipeName,
		"GlobalStorageSiK:" .. recipeName,
	}
	for i = 1, #variants do
		local name = variants[i]
		if sm.getCraftRecipe then
			local craftRecipe = sm:getCraftRecipe(name)
			if craftRecipe then
				return craftRecipe
			end
		end
		if sm.getRecipe then
			local legacy = sm:getRecipe(name)
			if legacy then
				return legacy
			end
		end
	end
	if sm.getAllCraftRecipes then
		local all = sm:getAllCraftRecipes()
		if all then
			for j = 0, all:size() - 1 do
				local candidate = all:get(j)
				if candidate and candidate.getName and candidate:getName() == recipeName then
					return candidate
				end
			end
		end
	end
	return nil
end

--- Construye lista de tags B42 para craftRecipe:setTags.
---@param requireWorkbench boolean
---@return ArrayList|nil
local function buildRecipeTagList(requireWorkbench)
	if not ArrayList then
		return nil
	end
	local tags = ArrayList.new()
	tags:add("AnySurfaceCraft")
	tags:add("Electrical")
	if not requireWorkbench then
		tags:add("InHandCraft")
	end
	return tags
end

--- Vacía fuentes de ingredientes de una receta.
---@param recipe CraftRecipe
local function clearRecipeSources(recipe)
	if not recipe or not recipe.getSource then
		return
	end
	local sources = recipe:getSource()
	if not sources then
		return
	end
	for j = 0, sources:size() - 1 do
		local source = sources:get(j)
		if source and source.getItems then
			local items = source:getItems()
			while items and items:size() > 0 do
				items:remove(0)
			end
		end
	end
end

--- Las 13 craftRecipe normales de globalstoragesik_recipes.txt (nada que ver
--- con TerminalRecipes.LIST, vacia hoy - ver comentario de esa tabla) tienen
--- needToBeLearn=true FIJO en el script. Antes de este parche, "Requerir
--- manuales GS para craftear" (RequireRecipeBooks) nunca llegaba a ninguna
--- de ellas: desactivar esa opcion no desbloqueaba nada en el menu de
--- crafteo vanilla real, solo afectaba al atajo de clic derecho de discos
--- (CraftUtils.knowsRecipe, sistema aparte). Bug confirmado y corregido
--- para las 13 a la vez, con el mismo API ya probado en produccion por
--- GS_AddonRecipeTuning.lua.
--- {recipeName, slug}. El Soldador usa el mismo mecanismo generico de
--- Recipe_<slug>_RequireBook que el resto; su Enable sigue siendo la opcion
--- propia ya existente, EnableSolderingIronCraft (distinta por historial).
local CORE_BOOK_GATED_RECIPES = {
	{"Build GS Soldering Iron", "SolderingIron"},
	{"Build GS PC Tower", "PCTower"},
	{"Build GS Motherboard", "Motherboard"},
	{"Build GS IO Controller", "IOController"},
	{"Build GS Keyboard", "Keyboard"},
	{"Build GS Reader Casing", "ReaderCasing"},
	{"Build GS Reader Circuit Board", "ReaderCircuit"},
	{"Build GS Reader Antenna", "ReaderAntenna"},
	{"Build GS Terminal Reader", "TerminalReader"},
	{"Build GS Desktop Computer", "DesktopComputer"},
	{"Program GS Network Disk", "NetworkDisk"},
	{"Program GS Uninstall Disk", "UninstallDisk"},
	{"Program GS Floppy Drive Network Disk", "DriveDisk"},
	{"Build GS Soldering Tip", "SolderingTip"},
	{"Build GS Soldering Resistance Coil", "SolderingResistance"},
	{"Build GS Soldering Handle", "SolderingHandle"},
}

--- Decide si una receta concreta exige tener el manual leido: usa su propia
--- opcion "Recipe_<slug>_RequireBook" si existe (no es nil), y si no cae al
--- interruptor global RequireRecipeBooks - asi cada receta puede anularse
--- individualmente sin perder el comportamiento por defecto para el resto.
---@param slug string
---@return boolean
local function resolveBookRequirement(slug)
	local perRecipe = SandboxVars.GlobalStorageSiK and SandboxVars.GlobalStorageSiK["Recipe_" .. slug .. "_RequireBook"]
	if perRecipe ~= nil then
		return perRecipe == true
	end
	return GlobalStorageSiK.Sandbox.requireRecipeBooks()
end

---@param sm ScriptManager
local function applyCoreBookRequirement(sm)
	for i = 1, #CORE_BOOK_GATED_RECIPES do
		local recipeName, slug = CORE_BOOK_GATED_RECIPES[i][1], CORE_BOOK_GATED_RECIPES[i][2]
		local recipe = resolveCraftRecipe(sm, recipeName)
		if recipe and recipe.setNeedToBeLearn then
			recipe:setNeedToBeLearn(resolveBookRequirement(slug))
		end
	end
end

--- Aplica parches de sandbox a recetas vanilla del mod.
function GlobalStorageSiK.RecipeTuning.apply()
	local sm = getScriptManager()
	if not sm then
		return
	end

	applyCoreBookRequirement(sm)

	for i = 1, #GlobalStorageSiK.TerminalRecipes.LIST do
		local def = GlobalStorageSiK.TerminalRecipes.LIST[i]
		local recipe = resolveCraftRecipe(sm, def.recipeName)
		if not recipe then
			GlobalStorageSiK.Debug.log("RecipeTuning", "Receta no encontrada", def.recipeName)
		else
			if recipe.setNeedToBeLearn then
				recipe:setNeedToBeLearn(GlobalStorageSiK.Sandbox.requireRecipeBooks())
			end
			if recipe.setTags then
				local tagList = buildRecipeTagList(GlobalStorageSiK.Sandbox.requireWorkbench())
				if tagList then
					pcall(function()
						recipe:setTags(tagList)
					end)
				end
			end
			if GlobalStorageSiK.Sandbox.isFreeCraft(def.id) then
				clearRecipeSources(recipe)
				if recipe.setTimeToMake then
					recipe:setTimeToMake(10)
				end
				GlobalStorageSiK.Debug.log("RecipeTuning", "Craft gratis", def.recipeName)
			end
			local skillLevel = GlobalStorageSiK.TerminalRecipes.getSkillLevel(def.id)
			if skillLevel and recipe.setRequiredSkillCount and Perks and Perks.Electricity then
				recipe:setRequiredSkillCount(Perks.Electricity, skillLevel)
			end
		end
	end
end
