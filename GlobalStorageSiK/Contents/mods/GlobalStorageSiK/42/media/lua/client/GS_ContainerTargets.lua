--[[
	GlobalStorageSiK - Destinos de inventario (cliente)
	Autor: SiK
	Fecha: 2025-06-24
	Descripción: Destino propio seleccionado y destinos explícitos de arrastre.
]]

require "GS_DepositSources"
require "GS_UIDebug"
require "GS_FloorTargets"


GlobalStorageSiK.ContainerTargets = {}


--- Obtiene contenedor mostrado por un panel de inventario.
---@param pane ISInventoryPane|nil
---@return ItemContainer|nil
function GlobalStorageSiK.ContainerTargets.getPaneContainer(pane)
	if not pane then
		return nil
	end
	if pane.inventory then
		return pane.inventory
	end
	if pane.container then
		return pane.container
	end
	if pane.items and pane.items.inventory then
		return pane.items.inventory
	end
	return nil
end

--- Busca panel de inventario bajo coordenadas de pantalla.
---@param x number
---@param y number
---@param element ISUIElement|nil
---@return ISInventoryPane|nil
local function effectiveVisible(element)
	if not element then return false end
	local current = element
	while current do
		if current.isVisible and not current:isVisible() then return false end
		current = current.parent
	end
	return true
end

local function debugDropTarget(message)
	if GlobalStorageSiK.UIDebug and GlobalStorageSiK.UIDebug.log then
		GlobalStorageSiK.UIDebug.log("WithdrawDrop", message)
	end
end

--- Busca de arriba a abajo: el último hijo dibujado es el que está visualmente
--- encima. El pane devuelto siempre está visible en toda su cadena de padres.
--- Itera colecciones Lua y ArrayList de PZ sin asumir el operador #. UIManager
--- usa listas Java en varias builds: usar #children hacia que el hit-test no
--- descendiese nunca a los ISInventoryPane vanilla durante un drag.
local function visitChildrenReverse(element, visit)
        local children = element and (element.childrenInOrder or element.children)
        if not children then return nil end
	if children.size and children.get then
		for i = children:size() - 1, 0, -1 do
			local found = visit(children:get(i))
			if found then return found end
		end
		return nil
	end
	if type(children) == "table" then
		for i = #children, 1, -1 do
			local found = visit(children[i])
			if found then return found end
		end
	end
        return nil
end

local function isInventoryPane(element)
        if not element then return false end
        return element.Type == "ISInventoryPane"
                or (element.inventory ~= nil and element.items ~= nil
                        and element.inventoryPane == nil)
end

local function paneContainsPoint(pane, x, y)
        if not pane or not pane.getAbsoluteX or not pane.getAbsoluteY then return false end
        local ax, ay = pane:getAbsoluteX(), pane:getAbsoluteY()
        local w = pane.width or (pane.getWidth and pane:getWidth()) or 0
        local h = pane.height or (pane.getHeight and pane:getHeight()) or 0
        return x >= ax and y >= ay and x < ax + w and y < ay + h
end

local function findInventoryPaneAt(x, y, element)
	if not element or (element.isVisible and not element:isVisible()) then
		return nil
	end
	-- childrenInOrder es el array real de PZ; recorrerlo al revés preserva el
	-- hit-test de la superficie superior cuando hay panes solapados.
	local child = visitChildrenReverse(element, function(candidate)
		return findInventoryPaneAt(x, y, candidate)
	end)
	if child then return child end
	if isInventoryPane(element) and effectiveVisible(element) and paneContainsPoint(element, x, y) then
		return element
	end
	return nil
end

-- Vanilla ISInventoryPane checks every UI root before treating a drop as world.
-- Unknown UI state is occupied, never permission to drop behind a window.
function GlobalStorageSiK.ContainerTargets.isMouseOverAnyUI()
	local ok, occupied = pcall(function()
		if not UIManager or not UIManager.getUI or not getMouseX or not getMouseY then return true end
		local roots = UIManager.getUI()
		if not roots or not roots.size or not roots.get then return true end
		local x, y = getMouseX(), getMouseY()
		for i = 0, roots:size() - 1 do
			local element = roots:get(i)
			if not element or not element.isPointOver or element:isPointOver(x, y) then return true end
		end
		return false
	end)
	return not ok or occupied ~= false
end

--- Panel de inventario bajo el ratón.
---@return ISInventoryPane|nil
function GlobalStorageSiK.ContainerTargets.findPaneAtMouse(diagnostic, player, playerNum)
	local mx, my = getMouseX(), getMouseY()
	local uiList = UIManager and UIManager.getUI and UIManager:getUI() or nil
	-- UIManager puede no exponer el árbol completo en todos los layouts de
	-- inventario/mods. No abortar: el fallback por página sigue siendo una
	-- comprobación geométrica real y no una suposición de destino.
	local found = visitChildrenReverse({ children = uiList }, function(root)
		return findInventoryPaneAt(mx, my, root)
	end)
	if found then return found end
	-- La página de inventario puede no figurar como raíz de UIManager según el
	-- layout/mod de inventario. Es un fallback de hit-test real, no una decisión
	-- de destino: solo se acepta un pane que contiene el puntero.
	local active = GlobalStorageSiK.ContainerTargets.findActivePaneAtMouse(player, mx, my, playerNum)
	if active then return active end
	if diagnostic then debugDropTarget("pane=nil") end
	return nil
end

local function findPaneOnPageAtMouse(page, mx, my)
	if not page then return nil end
	-- En B42 el loot de vehiculo puede vivir bajo un contenedor intermedio de la
	-- pagina y no en page.lootPane. Recorrer la pagina completa conserva el orden
	-- visual y alcanza maleteros/containers de mods sin adivinar su campo.
	local nested = findInventoryPaneAt(mx, my, page)
	if nested then return nested end
	-- Mantener el orden de dibujo base; el recorrido inverso de abajo elige el
	-- pane superpuesto más alto (loot sobre inventario cuando un mod los solapa).
	local candidates = { page.inventoryPane, page.lootPane }
	if page.backpacks then
		visitChildrenReverse({ children = page.backpacks }, function(pane)
			candidates[#candidates + 1] = pane
			return nil
		end)
	end
	-- B42 registra los inventarios de vehiculo en paneList en algunos layouts;
	-- no siempre cuelgan de lootPane ni del arbol children de la pagina.
	if page.paneList and page.paneList.size and page.paneList.get then
		for i = page.paneList:size() - 1, 0, -1 do
			candidates[#candidates + 1] = page.paneList:get(i)
		end
	end
	-- El orden inverso elige el backpack/panel dibujado por encima.
	for i = #candidates, 1, -1 do
		local pane = candidates[i]
		local nestedPane = findInventoryPaneAt(mx, my, pane)
		if nestedPane then return nestedPane end
		if pane and effectiveVisible(pane) and paneContainsPoint(pane, mx, my) then
			return pane
		end
		-- Algunos panes vanilla de vehiculo delegan su rectangulo al host. El
		-- hit-test propio conserva la semantica vanilla sin aceptar un pane fuera
		-- del puntero.
		if pane and effectiveVisible(pane)
			and ((pane.isMouseOver and pane:isMouseOver())
				or (pane.isPointOver and pane:isPointOver(mx, my))) then
			return pane
		end
	end
	return nil
end

function GlobalStorageSiK.ContainerTargets.findActivePaneAtMouse(player, mx, my, playerNum)
	-- El drag conserva playerNum aunque el objeto Lua del jugador no este
	-- disponible durante la captura. El inventario/loot sigue perteneciendo a
	-- ese viewport y no debe descartarse antes del hit-test geometrico.
	if playerNum == nil then
		playerNum = player and player.getPlayerNum and player:getPlayerNum() or 0
	end
	local pages, seen = {}, {}
	local function addPage(page)
		if page and not seen[page] then
			seen[page] = true
			pages[#pages + 1] = page
		end
	end
	if getPlayerInventory then
		local ok, result = pcall(getPlayerInventory, playerNum)
		if ok then addPage(result) end
	end
	-- El maletero B42 puede residir en una pagina de loot distinta de la pagina
	-- de inventario. Depositar hacia ese panel ya funcionaba porque vanilla lo
	-- conoce; el drag SiK no lo recorria y terminaba en pane=nil antes de enviar.
	if getPlayerLoot then
		local ok, result = pcall(getPlayerLoot, playerNum)
		if ok then addPage(result) end
	end
	if ISInventoryPage and ISInventoryPage.players then
		addPage(ISInventoryPage.players[playerNum])
	end
	for i = #pages, 1, -1 do
		local pane = findPaneOnPageAtMouse(pages[i], mx, my)
		if pane then return pane end
	end
	return nil
end

function GlobalStorageSiK.ContainerTargets.debugDropTarget(message)
	debugDropTarget(message)
end

--- Comprueba si el contenedor puede recibir extracciones.
---@param player IsoPlayer
---@param container ItemContainer
---@return boolean
function GlobalStorageSiK.ContainerTargets.canReceiveWithdraw(player, container)
	if not player or not container then
		return false
	end
	if GlobalStorageSiK.DepositSources.isNetworkNodeContainer(container) then
		return false
	end
	if container.getType and container:getType() == "floor" then
		return GlobalStorageSiK.FloorTargets.captureCurrent(player) ~= nil
	end
	return GlobalStorageSiK.DepositSources.canPlayerAccessContainer(player, container)
end

--- Obtiene clave de contenedor si es destino válido.
---@param player IsoPlayer
---@param container ItemContainer|nil
---@return string|nil
function GlobalStorageSiK.ContainerTargets.keyForContainer(player, container)
	if not player or not container then
		return nil
	end
	if not GlobalStorageSiK.ContainerTargets.canReceiveWithdraw(player, container) then
		return nil
	end
	if container.getType and container:getType() == "floor" then
		-- Vanilla floor panes aggregate nearby wrappers and have no square of
		-- their own. Capture the player's current physical square once.
		return GlobalStorageSiK.FloorTargets.captureCurrent(player)
	end
	return GlobalStorageSiK.DepositSources.buildContainerKey(player, container)
end

--- Lista destinos de extracción accesibles (principal + mochilas).
---@param player IsoPlayer
---@return table[] { key: string, label: string, container: ItemContainer }
function GlobalStorageSiK.ContainerTargets.listWithdrawDestinations(player)
	local list = {}
	if not player then
		return list
	end
	local containers = GlobalStorageSiK.DepositSources.collectPlayerContainers(player)
	for i = 1, #containers do
		local container = containers[i]
		local key = GlobalStorageSiK.ContainerTargets.keyForContainer(player, container)
		if key then
			table.insert(list, {
				key = key,
				label = GlobalStorageSiK.DepositSources.describePlayerContainer(player, container, i),
				container = container,
			})
		end
	end
	return list
end

--- Captura exclusivamente el inventario propio seleccionado en vanilla.
--- No consulta ratón, botín ni preferencias de una sesión anterior.
---@param player IsoPlayer|nil
---@return string|nil targetKey
---@return string|nil reason
function GlobalStorageSiK.ContainerTargets.resolveWithdrawTarget(player)
	if not player or not player.getPlayerNum or not getPlayerInventory then
		return nil, "target_unavailable"
	end
	local playerNum = player:getPlayerNum()
	local ok, page = pcall(getPlayerInventory, playerNum)
	local container = ok and page and page.inventoryPane and page.inventoryPane.inventory or nil
	if not container then return nil, "target_unavailable" end
	if not GlobalStorageSiK.DepositSources.isPlayerContainer(player, container) then
		return nil, "invalid_target"
	end
	local key = GlobalStorageSiK.ContainerTargets.keyForContainer(player, container)
	if not key or (key ~= "player:main" and string.sub(key, 1, 4) ~= "bag:") then
		return nil, "invalid_target"
	end
	return key, nil
end
