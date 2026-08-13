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
	-- Mismo material de acabado que exige la receta vanilla equivalente
	-- (globalstoragesik_recipes.txt: "Build GS Terminal Reader").
	"Base.DuctTape",
}
GlobalStorageSiK.ReaderAcquire.OUTPUT_ITEM = "GlobalStorageSiK.GS_TerminalReader"
-- Mismo nivel de Electricidad que exige la receta vanilla equivalente
-- (globalstoragesik_recipes.txt: "Build GS Terminal Reader") - montar el
-- lector desde esta ventana no debe ser una forma de saltarse ese requisito.
GlobalStorageSiK.ReaderAcquire.SKILL_REQUIRED = 6

---@param player IsoPlayer|nil
---@return boolean
function GlobalStorageSiK.ReaderAcquire.hasReadManual(player)
	return GlobalStorageSiK.CraftUtils.knowsRecipe(player, GlobalStorageSiK.ReaderAcquire.RECIPE_NAME)
end

--- Estado completo de requisitos (para la UI: qué hay, qué falta).
---@param player IsoPlayer|nil
---@return table status { manual=boolean, items=table<string,boolean>, tools=table, allReady=boolean }
function GlobalStorageSiK.ReaderAcquire.status(player)
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
	for i = 1, #GlobalStorageSiK.ReaderAcquire.REQUIRED_ITEMS do
		local ft = GlobalStorageSiK.ReaderAcquire.REQUIRED_ITEMS[i]
		local has = GlobalStorageSiK.CraftUtils.hasItemType(player, ft)
		status.items[ft] = has
		if not has then
			status.allReady = false
		end
	end
	status.tools.soldering = GlobalStorageSiK.CraftUtils.hasSolderingIron(player)
	status.tools.screwdriver = GlobalStorageSiK.CraftUtils.hasScrewdriver(player)
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
	local status = GlobalStorageSiK.ReaderAcquire.status(player)
	if not status.allReady then
		if not status.manual then return false, "book" end
		if not status.skillOk then return false, "skill" end
		if not status.tools.soldering or not status.tools.screwdriver then return false, "tools" end
		return false, "materials"
	end
	local inv = player:getInventory()
	if not inv then
		return false, "invalid"
	end
	-- Busca cada pieza en el inventario del jugador O en un contenedor
	-- cercano (igual que status() de arriba) y la quita de donde de verdad
	-- estaba, no siempre de player:getInventory().
	local items = {}
	for i = 1, #GlobalStorageSiK.ReaderAcquire.REQUIRED_ITEMS do
		local ft = GlobalStorageSiK.ReaderAcquire.REQUIRED_ITEMS[i]
		local item = GlobalStorageSiK.CraftUtils.findItemTypeNearby(player, ft)
		if not item then
			return false, "materials"
		end
		items[i] = item
	end
	for i = 1, #items do
		local item = items[i]
		local container = item.getContainer and item:getContainer() or inv
		container:Remove(item)
	end
	local output = instanceItem(GlobalStorageSiK.ReaderAcquire.OUTPUT_ITEM)
	if not output then
		return false, "output"
	end
	if GlobalStorageSiK.InventorySync and GlobalStorageSiK.InventorySync.addToPlayer then
		GlobalStorageSiK.InventorySync.addToPlayer(player, output)
	else
		inv:AddItem(output)
	end
	return true, nil
end
