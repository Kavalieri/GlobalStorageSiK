--[[
	GlobalStorageSiK - Adquisición directa del SiK Disk Reader
	Descripción: Ventana propia para montar un GS_TerminalReader (SiK Disk
	Reader) a partir de sus 3 piezas ya existentes (Reader Casing, Reader
	Circuit Board, Reader Antenna) + conocer la receta que enseña el manual
	"GS Network Monthly" (Build GS Terminal Reader - nombre interno heredado,
	el nombre visible en el menú vanilla y en esta ventana dice "SiK Disk
	Reader", ver Translate/Recipes.json). Misma arquitectura que
	GS_PCAcquire.lua: la entrega real la hace SIEMPRE esta ventana
	(GlobalStorageSiK.ReaderAcquire.craft, validado en servidor), la receta
	en sí nunca se ejecuta desde el menú de crafteo vanilla, solo sirve como
	"llave" fiable (LearnedRecipes + isRecipeKnown) para saber si el jugador
	ya se leyó el manual.
]]

require "GS_Config"
require "GS_Sandbox"
require "GS_InventorySync"
require "GS_CraftUtils"

GlobalStorageSiK.ReaderAcquire = {}

GlobalStorageSiK.ReaderAcquire.MANUAL_ITEM = "GlobalStorageSiK.GS_Manual_TerminalUnit"
-- Nombre interno del craftRecipe (globalstoragesik_recipes.txt) - el nombre
-- VISIBLE al jugador (menú vanilla y esta ventana) es "SiK Disk Reader", ver
-- Translate/Recipes.json. No se toca el nombre interno para no romper
-- LearnedRecipes del manual ni las comprobaciones de knowsRecipe.
GlobalStorageSiK.ReaderAcquire.RECIPE_NAME = "Build GS Terminal Reader"
GlobalStorageSiK.ReaderAcquire.REQUIRED_ITEMS = {
	"GlobalStorageSiK.GS_ReaderCasing",
	"GlobalStorageSiK.GS_ReaderCircuit",
	"GlobalStorageSiK.GS_ReaderAntenna",
}
GlobalStorageSiK.ReaderAcquire.OUTPUT_ITEM = "GlobalStorageSiK.GS_TerminalReader"
-- El lector es la puerta de entrada al sistema: mantiene manual y herramientas
-- especializadas, pero su montaje queda en Electricidad 3. La receta B42
-- equivalente usa el mismo valor para que el modal no salte requisitos.
GlobalStorageSiK.ReaderAcquire.SKILL_REQUIRED = 3

---@param player IsoPlayer|nil
---@return boolean
function GlobalStorageSiK.ReaderAcquire.hasReadManual(player)
	return GlobalStorageSiK.CraftUtils.knowsRecipe(player, GlobalStorageSiK.ReaderAcquire.RECIPE_NAME)
end

--- Estado completo de requisitos (para la UI: qué hay, qué falta).
---@param player IsoPlayer|nil
---@return table status { manual=boolean, items=table<string,boolean>, tools=table, allReady=boolean }
function GlobalStorageSiK.ReaderAcquire.status(player, containers)
	local status = { manual = GlobalStorageSiK.ReaderAcquire.hasReadManual(player), items = {}, tools = {}, allReady = true }
	if not GlobalStorageSiK.Sandbox.requireRecipeBooks() then
		status.manual = true
	end
	if not status.manual then
		status.allReady = false
	end
	if not player then
		status.allReady = false
		return status
	end
	containers = containers or GlobalStorageSiK.CraftUtils.collectIngredientContainers(player)
	for i = 1, #GlobalStorageSiK.ReaderAcquire.REQUIRED_ITEMS do
		local ft = GlobalStorageSiK.ReaderAcquire.REQUIRED_ITEMS[i]
		local has = GlobalStorageSiK.CraftUtils.hasItemType(player, ft, containers)
		status.items[ft] = has
		if not has then
			status.allReady = false
		end
	end
	status.tools.soldering = GlobalStorageSiK.CraftUtils.hasSolderingIron(player, containers)
	status.tools.screwdriver = GlobalStorageSiK.CraftUtils.hasScrewdriver(player, containers)
	if not status.tools.soldering or not status.tools.screwdriver then
		status.allReady = false
	end
	status.skillHave = GlobalStorageSiK.CraftUtils.getElectricityLevel(player)
	status.skillRequired = GlobalStorageSiK.ReaderAcquire.SKILL_REQUIRED
	status.skillOk = status.skillHave >= status.skillRequired
	if not status.skillOk then
		status.allReady = false
	end
	return status
end

--- Consume las piezas y entrega el lector. SOLO se llama en el servidor (o
--- SP autoritativo); vuelve a validar todo, nunca confía en lo que dijo el
--- cliente.
---@param player IsoPlayer
---@return boolean ok
---@return string|nil reason "book"|"skill"|"tools"|"materials"|"output"|"invalid"
function GlobalStorageSiK.ReaderAcquire.craft(player)
	if not player then
		return false, "invalid"
	end
	local containers = GlobalStorageSiK.CraftUtils.collectIngredientContainers(player)
	local status = GlobalStorageSiK.ReaderAcquire.status(player, containers)
	if not status.allReady then
		if not status.manual then return false, "book" end
		if not status.skillOk then return false, "skill" end
		if not status.tools.soldering or not status.tools.screwdriver then return false, "tools" end
		return false, "materials"
	end
	if not player:getInventory() then
		return false, "invalid"
	end
	-- Busca cada pieza en el inventario del jugador O en un contenedor
	-- cercano (igual que status() de arriba) y la quita de donde de verdad
	-- estaba, no siempre de player:getInventory().
	local items = {}
	for i = 1, #GlobalStorageSiK.ReaderAcquire.REQUIRED_ITEMS do
		local ft = GlobalStorageSiK.ReaderAcquire.REQUIRED_ITEMS[i]
		local item = GlobalStorageSiK.CraftUtils.findItemTypeNearby(player, ft, containers)
		if not item then
			return false, "materials"
		end
		items[i] = item
	end
	local replaced, _, replaceReason = GlobalStorageSiK.CraftUtils.replaceItemsWithOutput(player, items,
		GlobalStorageSiK.ReaderAcquire.OUTPUT_ITEM)
	if not replaced then
		return false, replaceReason == "materials" and "materials" or "output"
	end
	return true, nil
end
