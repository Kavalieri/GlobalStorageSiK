--[[
	GlobalStorageSiK - Destinos de inventario (cliente)
	Autor: SiK
	Fecha: 2025-06-24
	Descripción: Resuelve contenedor activo, bajo ratón o elegido en menú contextual.
]]

require "GS_DepositSources"
require "GS_I18n"

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
local function findInventoryPaneAt(x, y, element)
	if not element or (element.isVisible and not element:isVisible()) then
		return nil
	end
	if element.Type == "ISInventoryPane" then
		local ax = element:getAbsoluteX()
		local ay = element:getAbsoluteY()
		local w = element.width or element:getWidth()
		local h = element.height or element:getHeight()
		if x >= ax and y >= ay and x < ax + w and y < ay + h then
			return element
		end
	end
	-- childrenInOrder es el array real de PZ (children es hash por ID, #=0)
	local children = element.childrenInOrder
	if children then
		for i = 1, #children do
			local found = findInventoryPaneAt(x, y, children[i])
			if found then
				return found
			end
		end
	end
	return nil
end

--- Panel de inventario bajo el ratón.
---@return ISInventoryPane|nil
function GlobalStorageSiK.ContainerTargets.findPaneAtMouse()
	local mx, my = getMouseX(), getMouseY()
	if not UIManager or not UIManager.getUI then
		return nil
	end
	local uiList = UIManager:getUI()
	if not uiList then
		return nil
	end
	for i = 0, uiList:size() - 1 do
		local found = findInventoryPaneAt(mx, my, uiList:get(i))
		if found then
			return found
		end
	end
	return nil
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

	local pane = GlobalStorageSiK.ContainerTargets.findPaneAtMouse()
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
