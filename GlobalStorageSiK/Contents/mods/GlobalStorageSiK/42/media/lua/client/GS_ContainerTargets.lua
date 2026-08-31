--[[
	GlobalStorageSiK - Destinos de inventario (cliente)
	Autor: SiK
	Fecha: 2025-06-24
	Descripción: Resuelve contenedor activo, bajo ratón o elegido en menú contextual.
]]

require "GS_DepositSources"
require "GS_I18n"
require "GS_UIDebug"

require "ISUI/ISContextMenu"

GlobalStorageSiK.ContainerTargets = {}

local T = GlobalStorageSiK.I18n.text
local sessionTargets = {}

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
	return GlobalStorageSiK.DepositSources.buildContainerKey(player, container)
end

--- Panel de inventario activo o enfocado en la UI vanilla.
---@param player IsoPlayer
---@return ISInventoryPane|nil
function GlobalStorageSiK.ContainerTargets.findActivePane(player)
	if not player then
		return nil
	end
	local playerNum = player.getPlayerNum and player:getPlayerNum() or 0

	local page = nil
	if getPlayerInventory then
		local ok, result = pcall(getPlayerInventory, playerNum)
		if ok then
			page = result
		end
	end
	if not page and ISInventoryPage and ISInventoryPage.players then
		page = ISInventoryPage.players[playerNum]
	end
	if not page then
		return nil
	end

	local candidates = {}
	if page.lootPane then
		table.insert(candidates, page.lootPane)
	end
	if page.inventoryPane then
		table.insert(candidates, page.inventoryPane)
	end
	if page.backpacks then
		for i = 1, #page.backpacks do
			table.insert(candidates, page.backpacks[i])
		end
	end
	if page.paneList and page.paneList.size then
		for i = 0, page.paneList:size() - 1 do
			table.insert(candidates, page.paneList:get(i))
		end
	end

	for i = 1, #candidates do
		local pane = candidates[i]
		if pane and pane.isMouseOver and pane:isMouseOver() then
			return pane
		end
	end
	for i = 1, #candidates do
		local pane = candidates[i]
		if pane and pane.isVisible and pane:isVisible() and pane.isPointOver and pane:isPointOver(getMouseX(), getMouseY()) then
			return pane
		end
	end
	if page.lootPane and page.lootPane.isVisible and page.lootPane:isVisible() then
		return page.lootPane
	end
	return page.inventoryPane
end

--- Reinicia destino elegido en el menú actual.
---@param player IsoPlayer|nil
function GlobalStorageSiK.ContainerTargets.clearSessionTarget(player)
	if player then
		sessionTargets[player] = nil
	end
end

--- Guarda destino elegido en el menú contextual.
---@param player IsoPlayer|nil
---@param targetKey string|nil nil = automático
function GlobalStorageSiK.ContainerTargets.setSessionTarget(player, targetKey)
	if player then
		sessionTargets[player] = targetKey
	end
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

--- Resuelve clave de destino para extracción (sesión → panel activo → principal).
---@param player IsoPlayer|nil
---@return string|nil
function GlobalStorageSiK.ContainerTargets.resolveWithdrawTarget(player)
	if not player then
		return "player:main"
	end

	if sessionTargets[player] and sessionTargets[player] ~= "" then
		return sessionTargets[player]
	end

	local playerNum = player and player.getPlayerNum and player:getPlayerNum() or 0
	local pane = GlobalStorageSiK.ContainerTargets.findPaneAtMouse(nil, player, playerNum)
	if not pane then
		pane = GlobalStorageSiK.ContainerTargets.findActivePane(player)
	end
	if pane then
		local container = GlobalStorageSiK.ContainerTargets.getPaneContainer(pane)
		local key = GlobalStorageSiK.ContainerTargets.keyForContainer(player, container)
		if key then
			return key
		end
	end

	return "player:main"
end

--- Añade submenú para elegir destino de extracción.
---@param parentMenu ISContextMenu
---@param player IsoPlayer|nil
function GlobalStorageSiK.ContainerTargets.addDestinationSubMenu(parentMenu, player)
	if not parentMenu or not player then
		return
	end

	local root = parentMenu:addOption(T("IGUI_GS_WithdrawDest"))
	local sub = ISContextMenu:getNew(parentMenu)
	parentMenu:addSubMenu(root, sub)

	sub:addOption(T("IGUI_GS_WithdrawDestAuto"), player, function()
		GlobalStorageSiK.ContainerTargets.setSessionTarget(player, nil)
	end)

	local destinations = GlobalStorageSiK.ContainerTargets.listWithdrawDestinations(player)
	for i = 1, #destinations do
		local entry = destinations[i]
		sub:addOption(entry.label, player, function()
			GlobalStorageSiK.ContainerTargets.setSessionTarget(player, entry.key)
		end)
	end
end
