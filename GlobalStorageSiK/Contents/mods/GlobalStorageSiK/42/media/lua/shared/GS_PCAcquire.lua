--[[
	GlobalStorageSiK - Adquisición directa de PC vanilla
	Descripción: Ventana propia para conseguir un Base.Mov_DesktopComputer a
	partir de las 4 piezas GS ya existentes (I/O Controller, Keyboard,
	Motherboard, PC Tower) + conocer la receta que enseña el manual dedicado
	(GS_Manual_PCBuild, ver RECIPE_NAME). La entrega real del PC la hace
	SIEMPRE esta ventana (GS_PCAcquire.craft, validado en servidor) - la
	receta en sí nunca se ejecuta desde el menú de crafteo vanilla, solo sirve
	como "llave" fiable (LearnedRecipes + isRecipeKnown, motor del juego) para
	saber si el jugador ya se ha leído el manual, en vez de un ModData propio
	marcado a mano en OnReadLiterature (ese método dependía de un orden de
	parámetros no confirmado en toda instalación/idioma de B42).
]]

require "GS_Config"
require "GS_Sandbox"
require "GS_InventorySync"
require "GS_CraftUtils"

GlobalStorageSiK.PCAcquire = {}

GlobalStorageSiK.PCAcquire.MANUAL_ITEM = "GlobalStorageSiK.GS_Manual_PCBuild"
-- Nombre del craftRecipe que ensena el manual (globalstoragesik_recipes.txt,
-- LearnedRecipes en el item). "Ha leido el manual" se detecta comprobando si
-- el jugador CONOCE esta receta (mismo sistema robusto con varios metodos de
-- fallback que ya usan el resto de manuales del mod - GS_CraftUtils.knowsRecipe),
-- no con un ModData propio marcado a mano en el evento OnReadLiterature: ese
-- metodo dependia de un orden de parametros (item, jugador) no confirmado en
-- toda instalacion/idioma de B42 y podia dejar la bandera sin marcar en
-- silencio, sin ningun aviso al jugador.
GlobalStorageSiK.PCAcquire.RECIPE_NAME = "Build GS Desktop Computer"
GlobalStorageSiK.PCAcquire.REQUIRED_ITEMS = {
	"GlobalStorageSiK.GS_IODevice",
	"GlobalStorageSiK.GS_Keyboard",
	"GlobalStorageSiK.GS_Motherboard",
	"GlobalStorageSiK.GS_PC_Tower",
	-- Mismo material de acabado que exige la receta vanilla equivalente
	-- (globalstoragesik_recipes.txt: "Build GS Desktop Computer").
	"Base.NutsBolts",
}
GlobalStorageSiK.PCAcquire.OUTPUT_ITEM = "Base.Mov_DesktopComputer"
-- Mismo nivel de Electricidad que exige la receta vanilla equivalente
-- (globalstoragesik_recipes.txt: "Build GS Desktop Computer") - montar el PC
-- desde esta ventana no debe ser una forma de saltarse ese requisito.
GlobalStorageSiK.PCAcquire.SKILL_REQUIRED = 6

---@param player IsoPlayer|nil
---@return boolean
function GlobalStorageSiK.PCAcquire.hasReadManual(player)
	return GlobalStorageSiK.CraftUtils.knowsRecipe(player, GlobalStorageSiK.PCAcquire.RECIPE_NAME)
end

--- Estado completo de requisitos (para la UI: qué hay, qué falta).
---@param player IsoPlayer|nil
---@return table status { manual=boolean, items=table<string,boolean>, tools=table, allReady=boolean }
function GlobalStorageSiK.PCAcquire.status(player, containers)
	local status = { manual = GlobalStorageSiK.PCAcquire.hasReadManual(player), items = {}, tools = {}, allReady = true }
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
	for i = 1, #GlobalStorageSiK.PCAcquire.REQUIRED_ITEMS do
		local ft = GlobalStorageSiK.PCAcquire.REQUIRED_ITEMS[i]
		local has = GlobalStorageSiK.CraftUtils.hasItemType(player, ft, containers)
		status.items[ft] = has
		if not has then
			status.allReady = false
		end
	end
	-- Herramientas (nunca se consumen, ver craft() mas abajo): igual que
	-- cualquier crafteo del mod, hace falta soldador + destornillador.
	status.tools.soldering = GlobalStorageSiK.CraftUtils.hasSolderingIron(player, containers)
	status.tools.screwdriver = GlobalStorageSiK.CraftUtils.hasScrewdriver(player, containers)
	if not status.tools.soldering or not status.tools.screwdriver then
		status.allReady = false
	end
	status.skillHave = GlobalStorageSiK.CraftUtils.getElectricityLevel(player)
	status.skillRequired = GlobalStorageSiK.PCAcquire.SKILL_REQUIRED
	status.skillOk = status.skillHave >= status.skillRequired
	if not status.skillOk then
		status.allReady = false
	end
	return status
end

--- Consume las piezas y entrega el PC. SOLO se llama en el servidor (o SP
--- autoritativo); vuelve a validar todo, nunca confía en lo que dijo el
--- cliente.
---@param player IsoPlayer
---@return boolean ok
---@return string|nil reason "book"|"skill"|"tools"|"materials"|"output"|"invalid"
function GlobalStorageSiK.PCAcquire.craft(player)
	if not player then
		return false, "invalid"
	end
	local containers = GlobalStorageSiK.CraftUtils.collectIngredientContainers(player)
	local status = GlobalStorageSiK.PCAcquire.status(player, containers)
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
	for i = 1, #GlobalStorageSiK.PCAcquire.REQUIRED_ITEMS do
		local ft = GlobalStorageSiK.PCAcquire.REQUIRED_ITEMS[i]
		local item = GlobalStorageSiK.CraftUtils.findItemTypeNearby(player, ft, containers)
		if not item then
			return false, "materials"
		end
		items[i] = item
	end
	local replaced, _, replaceReason = GlobalStorageSiK.CraftUtils.replaceItemsWithOutput(player, items,
		GlobalStorageSiK.PCAcquire.OUTPUT_ITEM)
	if not replaced then
		return false, replaceReason == "materials" and "materials" or "output"
	end
	return true, nil
end
