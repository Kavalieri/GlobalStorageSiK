--[[
	GlobalStorageSiK - Icono lateral en barra de inventario
	Autor: SiK
	Fecha: 2025-06-24

	Patrón sidebar hover (ancla zoneBtn en B42).
	- Logo Workshop: icon.png → media/ui/Sidebar/{48..128}/GS_Off|On_{size}.png
	- Cabecera: media/ui/GS/GS_Logo_{24,32,48}.png (GS_TerminalUI_Chrome)
]]

require "ISUI/ISPanel"
require "ISUI/ISToolTip"
require "GS_I18n"
require "GS_NetClient"
require "GS_TerminalUI"
require "GS_TerminalUI_Api"
require "GS_TerminalUI_Blocked"
require "GS_TerminalAccess"
require "GS_TerminalRecipes"

GlobalStorageSiK.UIHook = GlobalStorageSiK.UIHook or {}

local GS_SidebarPatch = {}
local T = GlobalStorageSiK.I18n.text

---@return number
local function getTextureWidth()
	local size = getCore():getOptionSidebarSize()
	if size == 6 then
		size = getCore():getOptionFontSizeReal() - 1
	end
	if size == 2 then return 64 end
	if size == 3 then return 80 end
	if size == 4 then return 96 end
	if size == 5 then return 128 end
	return 48
end

---@param panel ISEquippedItem
---@return boolean
local function isCurrentEquippedItemPanel(panel)
	if not panel or panel.playerNum == nil then
		return false
	end
	local playerData = getPlayerData(panel.playerNum)
	if playerData and playerData.equipped and playerData.equipped ~= panel then
		return false
	end
	return true
end

---@param panel ISEquippedItem
---@return ISUIElement|nil
local function getInventoryAnchor(panel)
	if not panel then
		return nil
	end
	local names = { "invBtn", "zoneBtn", "inventoryBtn", "btnInventory" }
	for i = 1, #names do
		local btn = panel[names[i]]
		if btn and btn.getX then
			return btn
		end
	end
	return nil
end

local function isTerminalOpen()
	local main = GlobalStorageSiK.TerminalUI and GlobalStorageSiK.TerminalUI.instance
	return main and main.getIsVisible and main:getIsVisible()
end

local function closeTerminalPanels()
	local main = GlobalStorageSiK.TerminalUI and GlobalStorageSiK.TerminalUI.instance
	if main and main.onClose then
		main:onClose()
	end
end

--- Abre el terminal asegurando que la API esté cargada (evita nil tras recarga de módulos).
local function requestTerminalOpen()
	if not GlobalStorageSiK.TerminalUI or type(GlobalStorageSiK.TerminalUI.requestOpen) ~= "function" then
		require "GS_TerminalUI_Api"
	end
	if GlobalStorageSiK.TerminalUI and type(GlobalStorageSiK.TerminalUI.requestOpen) == "function" then
		GlobalStorageSiK.TerminalUI.requestOpen()
	end
end

--- Carga icono sidebar pre-dimensionado para la celda del popup.
---@param textureWidth number
---@param onState boolean
---@return Texture|nil
local function loadSidebarIcon(textureWidth, onState)
	local state = onState and "On" or "Off"
	return getTexture("media/ui/Sidebar/" .. textureWidth .. "/GS_" .. state .. "_" .. textureWidth .. ".png")
end

GS_InventorySidebarPopup = ISPanel:derive("GS_InventorySidebarPopup")

function GS_InventorySidebarPopup:new(x, y, width, height, chr)
	local textureWidth = getTextureWidth()
	local o = ISPanel:new(x, y, width, height)
	setmetatable(o, self)
	self.__index = self
	o.chr = chr
	o.playerNum = chr and chr:getPlayerNum() or 0
	o.TEXTURE_WIDTH = textureWidth
	o.TEXTURE_HEIGHT = textureWidth * 0.75
	o.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
	o.borderColor = { r = 0, g = 0, b = 0, a = 0 }
	o.gsIcon = loadSidebarIcon(textureWidth, false)
	o.gsIconOn = loadSidebarIcon(textureWidth, true) or o.gsIcon
	return o
end

function GS_InventorySidebarPopup:initialise()
	ISPanel.initialise(self)
end

function GS_InventorySidebarPopup:reloadIcons()
	self.gsIcon = loadSidebarIcon(self.TEXTURE_WIDTH, false)
	self.gsIconOn = loadSidebarIcon(self.TEXTURE_WIDTH, true) or self.gsIcon
end

function GS_InventorySidebarPopup:showTooltip(text)
	if not text then
		return
	end
	if not self.tooltip then
		self.tooltip = ISToolTip:new()
		self.tooltip:initialise()
		self.tooltip:instantiate()
		self.tooltip:setOwner(self)
	end
	self.tooltip:setName(text)
	self.tooltip:setVisible(true)
	self.tooltip:addToUIManager()
	self.tooltip:bringToTop()
end

function GS_InventorySidebarPopup:hideTooltip()
	if self.tooltip and self.tooltip:isVisible() then
		self.tooltip:removeFromUIManager()
		self.tooltip:setVisible(false)
	end
end

function GS_InventorySidebarPopup:onMouseMove()
	local index = math.floor(self:getMouseX() / self.TEXTURE_WIDTH)
	if index == 1 then
		self:showTooltip(T("IGUI_GS_OpenTerminal"))
	else
		self:hideTooltip()
	end
	return true
end

function GS_InventorySidebarPopup:onMouseMoveOutside()
	self:hideTooltip()
	return true
end

function GS_InventorySidebarPopup:onMouseDown(x, y)
	self:hideTooltip()
	local index = math.floor(x / self.TEXTURE_WIDTH)
	if index == 0 then
		local anchor = self.owner and getInventoryAnchor(self.owner)
		if anchor and anchor.onMouseDown then
			anchor:onMouseDown(0, 0)
		end
		return true
	end
	if index == 1 then
		if isTerminalOpen() then
			closeTerminalPanels()
		else
			requestTerminalOpen()
		end
		return true
	end
	return false
end

function GS_InventorySidebarPopup:render()
	local tex = self.gsIcon
	if isTerminalOpen() and self.gsIconOn then
		tex = self.gsIconOn
	end
	if tex then
		self:drawTextureScaledAspect(tex, self.TEXTURE_WIDTH, 0, self.TEXTURE_WIDTH, self.TEXTURE_HEIGHT, 1, 1, 1, 1)
	end
end

function GS_SidebarPatch.updatePopupGeometry(panel)
	local anchor = getInventoryAnchor(panel)
	if not panel or not panel.gsInventoryPopup or not anchor then
		return
	end

	local textureWidth = getTextureWidth()
	local textureHeight = textureWidth * 0.75
	panel.gsInventoryPopup:setX(panel:getAbsoluteX() + anchor:getX())
	panel.gsInventoryPopup:setY(panel:getAbsoluteY() + anchor:getY())
	panel.gsInventoryPopup:setWidth(textureWidth * 2)
	panel.gsInventoryPopup:setHeight(textureHeight)
	panel.gsInventoryPopup.TEXTURE_WIDTH = textureWidth
	panel.gsInventoryPopup.TEXTURE_HEIGHT = textureHeight
	panel.gsInventoryPopup:reloadIcons()
end

function GS_SidebarPatch.ensurePopup(panel)
	if not panel or not panel.chr or panel.chr:getPlayerNum() ~= 0 then
		return
	end
	if not isCurrentEquippedItemPanel(panel) then
		return
	end

	local anchor = getInventoryAnchor(panel)
	if not anchor then
		return
	end

	if not panel.gsInventoryPopup then
		local textureWidth = getTextureWidth()
		local textureHeight = textureWidth * 0.75
		local absX = panel:getAbsoluteX() + anchor:getX()
		local absY = panel:getAbsoluteY() + anchor:getY()
		panel.gsInventoryPopup = GS_InventorySidebarPopup:new(absX, absY, textureWidth * 2, textureHeight, panel.chr)
		panel.gsInventoryPopup.owner = panel
		panel.gsInventoryPopup:initialise()
		panel.gsInventoryPopup:addToUIManager()
		panel.gsInventoryPopup:setVisible(false)
	end

	GS_SidebarPatch.updatePopupGeometry(panel)
end

function GS_SidebarPatch.updatePopupVisibility(panel)
	local anchor = getInventoryAnchor(panel)
	if not panel or not anchor or not panel.gsInventoryPopup then
		return
	end
	if not isCurrentEquippedItemPanel(panel) then
		return
	end

	local showPopup = false
	if anchor:isMouseOver() then
		showPopup = true
	elseif panel.gsInventoryPopup:isMouseOver() then
		showPopup = true
	elseif isTerminalOpen() then
		showPopup = true
	end

	if "Tutorial" == getCore():getGameMode() then
		showPopup = false
	end

	panel.gsInventoryPopup:setVisible(showPopup)
	if showPopup then
		panel.gsInventoryPopup:bringToTop()
	elseif panel.gsInventoryPopup.tooltip then
		panel.gsInventoryPopup:hideTooltip()
	end
end

function GlobalStorageSiK.UIHook.patchEquippedItem()
	if not ISEquippedItem then
		require "ISUI/ISEquippedItem"
	end
	if not ISEquippedItem or ISEquippedItem.GlobalStorageSiKPatched then
		return
	end
	ISEquippedItem.GlobalStorageSiKPatched = true

	local originalInitialise = ISEquippedItem.initialise
	ISEquippedItem.initialise = function(self)
		originalInitialise(self)
		GS_SidebarPatch.ensurePopup(self)
	end

	local originalPrerender = ISEquippedItem.prerender
	ISEquippedItem.prerender = function(self)
		originalPrerender(self)
		if not isCurrentEquippedItemPanel(self) then
			return
		end
		GS_SidebarPatch.ensurePopup(self)
		GS_SidebarPatch.updatePopupVisibility(self)
	end

	local originalRemoveFromUIManager = ISEquippedItem.removeFromUIManager
	ISEquippedItem.removeFromUIManager = function(self)
		if self.gsInventoryPopup then
			self.gsInventoryPopup:hideTooltip()
			self.gsInventoryPopup:removeFromUIManager()
			self.gsInventoryPopup = nil
		end
		originalRemoveFromUIManager(self)
	end

	local originalCheckSidebarSizeOption = ISEquippedItem.checkSidebarSizeOption
	ISEquippedItem.checkSidebarSizeOption = function(self)
		originalCheckSidebarSizeOption(self)
		if isCurrentEquippedItemPanel(self) then
			GS_SidebarPatch.updatePopupGeometry(self)
		end
	end
end

local function onGameStart()
	GlobalStorageSiK.UIHook.patchEquippedItem()
	local playerData = getPlayerData(0)
	if playerData and playerData.equipped then
		GS_SidebarPatch.ensurePopup(playerData.equipped)
	end
end

Events.OnGameStart.Add(onGameStart)
