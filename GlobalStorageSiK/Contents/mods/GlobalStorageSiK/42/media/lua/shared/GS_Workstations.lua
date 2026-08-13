--[[
	GlobalStorageSiK - Estaciones de craft en la red
	Autor: SiK
	Fecha: 2025-06-23
	Descripción: Tags de banco que aporta el terminal y módulos ampliación.
]]

require "GS_Config"

GlobalStorageSiK.Workstations = {}

--- Definición de módulos crafteables que se conectan a la red.
GlobalStorageSiK.Workstations.MODULES = {
	TerminalBase = {
		id = "TerminalBase",
		craftTags = { "AnySurfaceCraft", "InHandCraft" },
		powerDraw = 0.001,
	},
	ForgeModule = {
		id = "ForgeModule",
		craftTags = { "Forge", "Advanced_Forge", "Primitive_Forge" },
		powerDraw = 0.008,
	},
	FurnaceModule = {
		id = "FurnaceModule",
		craftTags = { "Furnace" },
		powerDraw = 0.006,
	},
	ButcherModule = {
		id = "ButcherModule",
		craftTags = { "ButcherHook" },
		powerDraw = 0.003,
	},
	GrindstoneModule = {
		id = "GrindstoneModule",
		craftTags = { "Grindstone" },
		powerDraw = 0.004,
	},
	PotteryModule = {
		id = "PotteryModule",
		craftTags = { "PotteryBench", "PotteryWheel" },
		powerDraw = 0.004,
	},
}

--- Obtiene los tags de craft disponibles en una red según módulos activos.
---@param activeModuleIds string[]
---@return table<string, boolean>
function GlobalStorageSiK.Workstations.collectCraftTags(activeModuleIds)
	local tags = {}
	local ids = activeModuleIds or { "TerminalBase" }

	for i = 1, #ids do
		local moduleDef = GlobalStorageSiK.Workstations.MODULES[ids[i]]
		if moduleDef and moduleDef.craftTags then
			for j = 1, #moduleDef.craftTags do
				tags[moduleDef.craftTags[j]] = true
			end
		end
	end

	local hasTag = false
	for _ in pairs(tags) do
		hasTag = true
		break
	end
	if not hasTag then
		tags.AnySurfaceCraft = true
	end

	return tags
end

--- Comprueba si una receta es viable con los tags disponibles.
---@param recipeTags string[]|nil
---@param availableTags table<string, boolean>
---@return boolean
function GlobalStorageSiK.Workstations.recipeMatchesTags(recipeTags, availableTags)
	if not recipeTags or #recipeTags == 0 then
		return false
	end

	for i = 1, #recipeTags do
		local tag = recipeTags[i]
		if availableTags[tag] then
			return true
		end
	end

	return false
end

--[[
	Implementación B42 (fase 2):
	- Terminal base = entidad con componente workstation (AnySurfaceCraft).
	- Módulos = muebles IsoThumpable en la red con modData.moduleId.
	- GS_CraftingBridge filtra recetas por collectCraftTags() de módulos online con energía.
	- Recetas vanilla que exigen Forge solo aparecen si hay ForgeModule en la red.
]]
