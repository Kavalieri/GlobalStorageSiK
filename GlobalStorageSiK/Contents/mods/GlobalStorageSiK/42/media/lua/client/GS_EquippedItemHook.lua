--[[
	GlobalStorageSiK - Icono lateral en barra de inventario
	Autor: SiK
	Fecha: 2025-06-24

	Patrón sidebar hover (ancla zoneBtn en B42).
	- Apertura Core: media/ui/GS/Launcher/sik-mainbutton-{48..128}.png
	- Admin: media/ui/GS/Launcher/sik-mainbutton-admin-{48..128}.png
	- Cabecera: media/ui/GS/GS_Logo_{24,32,48}.png (SiK.UI Window)
]]

require "GS_UI_Framework"
require "GS_I18n"
require "GS_NetClient"
require "GS_TerminalUI"
require "GS_TerminalUI_Api"
require "GS_TerminalUI_Blocked"
require "GS_TerminalAccess"
require "GS_TerminalRecipes"
require "GS_Permissions"
require "GS_AdminDashboard"

GlobalStorageSiK.UIHook = GlobalStorageSiK.UIHook or {}

local GS_SidebarPatch = {}
local T = GlobalStorageSiK.I18n.text
local UI = SiK.UI

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

--- Tercer icono del sidebar (panel de soporte GM/moderacion), solo visible
--- para rango de staff del servidor - unico sitio del CLIENTE donde se
--- consulta isServerStaff, y solo para decidir si DIBUJAR el icono. La
--- autorizacion real se revalida siempre en servidor (requireServerMod),
--- esto es pura UX: nadie deberia ver un boton que el servidor le va a
--- rechazar. Ademas exige shouldEnforce() (isMultiplayerActive() real): en SP
--- real el sistema de permisos ya esta inerte para TODO (nadie recibe
--- network_vacant/denied, el propio jugador suele tener rango "admin" de su
--- propia partida) - el panel de soporte no tiene nada que gestionar ahi, asi
--- que ni se ofrece, para no mostrar un icono sin uso real (pedido explicito
--- 2026-08-22: "de todo esto, en SP, no usaremos nada por ahora").
---@param chr IsoPlayer|nil
---@return boolean
local function isPlayerStaff(chr)
	return chr ~= nil and GlobalStorageSiK.Permissions.shouldEnforce()
		and GlobalStorageSiK.Permissions.isServerStaff(chr)
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

--- Carga el derivado canonico ya preparado para la celda cuadrada del popup.
---@param textureWidth number
---@param adminVariant boolean
---@return Texture|nil
local function loadSidebarIcon(textureWidth, adminVariant)
	local suffix = adminVariant and "-admin-" or "-"
	return getTexture("media/ui/GS/Launcher/sik-mainbutton" .. suffix .. textureWidth .. ".png")
end

local function popupY(panel, anchor, textureHeight)
	local anchorHeight = anchor and anchor.getHeight and anchor:getHeight() or textureHeight
	return panel:getAbsoluteY() + anchor:getY()
		+ math.floor((anchorHeight - textureHeight) / 2)
end

GS_InventorySidebarPopup = GS_InventorySidebarPopup or {}

function GS_InventorySidebarPopup:new(x, y, width, height, chr)
	local textureWidth = getTextureWidth()
	local o = UI.Controls.panel(nil, {
		x = x, y = y, w = width, h = height,
		controlId = "inventorySidebarPopup",
		playerNum = chr and chr:getPlayerNum() or 0,
		drawBackground = false,
	})
	o.chr = chr
	o.playerNum = chr and chr:getPlayerNum() or 0
	o.TEXTURE_WIDTH = textureWidth
	o.TEXTURE_HEIGHT = textureWidth
	o.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
	o.borderColor = { r = 0, g = 0, b = 0, a = 0 }
	o.gsIcon = loadSidebarIcon(textureWidth, false)
	o.gsAdminIcon = loadSidebarIcon(textureWidth, true) or o.gsIcon
	o.isStaff = isPlayerStaff(chr)
	local function mountProductButton(anchor, spec)
		return UI.Controls.iconButton(anchor, {
			x = spec.x, y = 0, w = textureWidth, h = o.TEXTURE_HEIGHT,
			chrome = false, iconFit = "square", iconSize = textureWidth, iconPadding = 0,
			icon = spec.asset, tooltip = spec.tooltip, playerNum = o.playerNum,
			onClick = spec.action,
		})
	end
	o.terminalExtension = UI.Menu.sideMenuExtension({
		asset = o.gsIcon, tooltip = T("IGUI_GS_OpenTerminal"),
		action = function()
			if isTerminalOpen() then closeTerminalPanels() else requestTerminalOpen() end
			return true
		end,
		mount = function(anchor, spec)
			spec.x = textureWidth
			return mountProductButton(anchor, spec)
		end,
		unmount = function(control) if control and control.dispose then control:dispose() end end,
	})
	o.terminalButton = o.terminalExtension:mount(o)
	o.staffExtension = UI.Menu.sideMenuExtension({
		asset = o.gsAdminIcon, tooltip = T("IGUI_GS_AdminDashboardTooltip"),
		action = function() GlobalStorageSiK.AdminDashboard.show(); return true end,
		mount = function(anchor, spec)
			spec.x = textureWidth * 2
			return mountProductButton(anchor, spec)
		end,
		unmount = function(control) if control and control.dispose then control:dispose() end end,
	})
	o.staffButton = o.staffExtension:mount(o)
	o.staffButton:setVisible(o.isStaff)
	o.onMouseDown = function(self, mouseX)
		if mouseX >= 0 and mouseX < self.TEXTURE_WIDTH then
			local anchor = self.owner and getInventoryAnchor(self.owner)
			if anchor and anchor.onMouseDown then
				anchor:onMouseDown(0, 0)
			end
			return true
		end
		return false
	end
	function o:hideTooltip()
		if self.terminalButton and self.terminalButton._sikTooltipHandle then
			self.terminalButton._sikTooltipHandle:hide()
		end
		if self.staffButton and self.staffButton._sikTooltipHandle then
			self.staffButton._sikTooltipHandle:hide()
		end
	end
	function o:reloadIcons()
		self.gsIcon = loadSidebarIcon(self.TEXTURE_WIDTH, false)
		self.gsAdminIcon = loadSidebarIcon(self.TEXTURE_WIDTH, true) or self.gsIcon
		if self.terminalExtension then self.terminalExtension.asset = self.gsIcon end
		if self.staffExtension then self.staffExtension.asset = self.gsAdminIcon end
		self.terminalButton:setTexture(self.gsIcon)
		self.staffButton:setTexture(self.gsAdminIcon)
	end
	function o:setSidebarGeometry(nextWidth, nextHeight, staff)
		self.TEXTURE_WIDTH, self.TEXTURE_HEIGHT = nextWidth, nextHeight
		self.isStaff = staff == true
		self:setWidth(nextWidth * (self.isStaff and 3 or 2))
		self:setHeight(nextHeight)
		self.terminalButton:setX(nextWidth); self.terminalButton:setY(0)
		self.terminalButton:setWidth(nextWidth); self.terminalButton:setHeight(nextHeight)
		self.staffButton:setX(nextWidth * 2); self.staffButton:setY(0)
		self.staffButton:setWidth(nextWidth); self.staffButton:setHeight(nextHeight)
		self.staffButton:setVisible(self.isStaff)
		self:reloadIcons()
		return self
	end
	local panelDispose = o.dispose
	o.dispose = function(self)
		if self._gsSidebarDisposed then return false end
		self._gsSidebarDisposed = true
		self:hideTooltip()
		if self.terminalExtension then self.terminalExtension:dispose(); self.terminalExtension = nil end
		if self.staffExtension then self.staffExtension:dispose(); self.staffExtension = nil end
		self.terminalButton, self.staffButton = nil, nil
		return panelDispose(self)
	end
	return o
end

function GS_SidebarPatch.updatePopupGeometry(panel)
	local anchor = getInventoryAnchor(panel)
	if not panel or not panel.gsInventoryPopup or not anchor then
		return
	end

	local textureWidth = getTextureWidth()
	local textureHeight = textureWidth
	panel.gsInventoryPopup:setX(panel:getAbsoluteX() + anchor:getX())
	panel.gsInventoryPopup:setY(popupY(panel, anchor, textureHeight))
	panel.gsInventoryPopup:setSidebarGeometry(textureWidth, textureHeight,
		isPlayerStaff(panel.chr))
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
		local textureHeight = textureWidth
		local absX = panel:getAbsoluteX() + anchor:getX()
		local absY = popupY(panel, anchor, textureHeight)
		panel.gsInventoryPopup = GS_InventorySidebarPopup:new(absX, absY, textureWidth * 2, textureHeight, panel.chr)
		panel.gsInventoryPopup.owner = panel
		panel.gsInventoryPopup:addToUIManager()
		panel.gsInventoryPopup:setVisible(false)
		local refresh = UI.Lifecycle.bindHoverReveal(panel, {
			target = panel.gsInventoryPopup,
			sources = function()
				return { getInventoryAnchor(panel) }
			end,
			graceTicks = 4,
			intervalTicks = 1,
			immediate = true,
			beforeUpdate = function()
				if not panel.gsInventoryPopup then return end
				GS_SidebarPatch.updatePopupGeometry(panel)
			end,
			forceVisible = function() return isTerminalOpen() end,
			forceHidden = function()
				return not isCurrentEquippedItemPanel(panel)
					or "Tutorial" == getCore():getGameMode()
			end,
			onHide = function()
				if panel.gsInventoryPopup then panel.gsInventoryPopup:hideTooltip() end
			end,
		})
		if refresh then
			panel.gsInventoryPopup._gsHoverReveal = refresh
			UI.Lifecycle.own(panel.gsInventoryPopup, refresh)
		end
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

	local reveal = panel.gsInventoryPopup._gsHoverReveal
	if reveal and reveal.refresh then reveal:refresh("visibility") end
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

	local originalRemoveFromUIManager = ISEquippedItem.removeFromUIManager
	ISEquippedItem.removeFromUIManager = function(self)
		if self.gsInventoryPopup then
			self.gsInventoryPopup:dispose()
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
