--[[
	GlobalStorageSiK - Ajuste de recetas de addons registrados
	Autor: SiK
	Fecha: 2025-06-27
	Descripción: Aplica revista obligatoria y Electricidad del módulo según AddonRegistry.
]]

require "GS_AddonRegistry"
require "GS_Sandbox"

GlobalStorageSiK.AddonRecipeTuning = GlobalStorageSiK.AddonRecipeTuning or {}

---@param sm ScriptManager
---@param recipeName string
---@return CraftRecipe|nil
local function resolveCraftRecipe(sm, recipeName)
	if not sm or not recipeName then
		return nil
	end
	if sm.getCraftRecipe then
		local craftRecipe = sm:getCraftRecipe(recipeName)
		if craftRecipe then
			return craftRecipe
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

--- Decide si una receta de addon exige manual: Core NO conoce los slugs ni
--- el namespace de sandbox de cada addon (eso viviria en Core y mezclaria
--- configuracion de addon dentro de Core, justo lo que queremos evitar).
--- En su lugar, cada addon puede registrar opcionalmente su propia funcion
--- resolutora (def.resolveRecipeBookRequirement(recipeName) -> boolean),
--- leyendo SU PROPIO SandboxVars[def.modId]. Si un addon no la define
--- (compatibilidad con addons de terceros mas simples), se usa el
--- interruptor global de Core como antes.
---@param def table
---@param recipeName string
---@return boolean
local function resolveBookRequirement(def, recipeName)
	if def.resolveRecipeBookRequirement then
		local ok, result = pcall(def.resolveRecipeBookRequirement, recipeName)
		if ok and result ~= nil then
			return result == true
		end
	end
	return GlobalStorageSiK.Sandbox.requireRecipeBooks()
end

--- Parchea recetas B42 de addons activos (revista + skill módulo).
--- Bug corregido: antes forzaba needToBeLearn=true sin condicion ninguna,
--- ignorando activamente GlobalStorageSiK.RequireRecipeBooks - desactivar
--- esa opcion de sandbox nunca desbloqueaba ninguna receta de addon en el
--- menu de crafteo vanilla real. Ahora sigue el mismo sandbox que el resto
--- del mod (ver GS_RecipeTuning.lua, mismo bug, mismo arreglo), y ademas
--- respeta la opcion individual por receta si el jugador la ha fijado.
function GlobalStorageSiK.AddonRecipeTuning.apply()
	local sm = getScriptManager and getScriptManager() or nil
	if not sm then
		return
	end

	for addonId, def in pairs(GlobalStorageSiK.AddonRegistry.all()) do
		if GlobalStorageSiK.AddonRegistry.isModActive(addonId) and def.recipeNames then
			for i = 1, #def.recipeNames do
				local recipeName = def.recipeNames[i]
				local recipe = resolveCraftRecipe(sm, recipeName)
				if recipe then
					if recipe.setNeedToBeLearn then
						recipe:setNeedToBeLearn(resolveBookRequirement(def, recipeName))
					end
					if def.moduleRecipeName
						and recipeName == def.moduleRecipeName
						and recipe.setRequiredSkillCount
						and Perks and Perks.Electricity then
						local skill = def.moduleSkillLevel or GlobalStorageSiK.AddonRegistry.DEFAULT_MODULE_SKILL
						recipe:setRequiredSkillCount(Perks.Electricity, skill)
					end
				end
			end
		end
	end
end
