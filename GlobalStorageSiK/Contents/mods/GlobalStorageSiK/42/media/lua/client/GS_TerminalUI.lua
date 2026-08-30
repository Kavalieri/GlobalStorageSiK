--[[
	GlobalStorageSiK - Terminal UI (SiK UI)
	Autor: SiK
	Fecha: 2025-06-24
]]

require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISLabel"
require "ISUI/ISTextEntryBox"
require "ISUI/ISToolTip"
require "GS_TerminalUI_TabRail"
require "GS_TerminalUI_Tabs"
require "ISUI/ISComboBox"
require "GS_Config"
require "GS_Sandbox"
require "GS_I18n"
require "GS_Index"
require "GS_Libs"
require "GS_BulkFilters"
require "GS_NetClient"
require "GS_Permissions"
require "GS_SiK_UI_Core"
require "GS_SiK_UI_Palette"
require "GS_SiK_UI_Metrics"
require "GS_SiK_UI_Viewport"
require "GS_SiK_UI_Controls"
require "GS_SiK_UI_Block"
require "GS_SiK_UI_State"
require "GS_TerminalUI_Scroll"
require "GS_SiK_UI_List"
require "GS_SiK_UI_Table"
require "GS_SiK_UI_Window"
require "GS_SiK_UI_Modal"
require "GS_TerminalUI_Sections"
require "GS_TerminalUI_Items"
require "GS_TerminalUI_Config"
require "GS_TerminalUI_Addons"
require "GS_TerminalUI_Extensions"
require "GS_TerminalUI_Programming"
require "GS_TerminalRecipes"
require "GS_TerminalUI_Network"
require "GS_TerminalUI_Options"
require "GS_TerminalUI_Nodes"
require "GS_TerminalUI_NodeEditor"
require "GS_TerminalDrop"
require "GS_WithdrawClient"
require "GS_TerminalUI_BlockedPanel"
require "GS_UIDebug"
require "GS_UILayout"

GlobalStorageSiK.TerminalUI = GlobalStorageSiK.TerminalUI or {}
GlobalStorageSiK.TerminalUI.instances = GlobalStorageSiK.TerminalUI.instances or {}
if not GlobalStorageSiK.SiK_UI.SurfaceInventory.get("terminal-shell") then
	GlobalStorageSiK.SiK_UI.SurfaceInventory.register({
		id = "terminal-shell",
		pack = "terminal-contenedor",
		owner = "GS_TerminalUI",
		parent = "UIManager",
		variants = { "compact", "standard", "wide" },
	})
end

-- Inventario contractual del paquete visual validado `terminal-tabs`.
-- Registrar una superficie no la hace visible ni concede autoridad: permite
-- a QA resolver cada surfaceId contra su owner real incluso cuando el addon
-- opcional que aporta la pestaña no está cargado en esta sesión.
local TERMINAL_TAB_SURFACES = {
	{ id = "terminal-tabs", owner = "GS_TerminalUI_Tabs", parent = "terminal-shell" },
	{ id = "terminal-remote", owner = "GS_TerminalUI_Api", parent = "terminal-shell", variants = { "tablet" } },
	{ id = "tab-warehouse", owner = "GS_TerminalUI_Items", parent = "terminal-tabs" },
	{ id = "warehouse-drop-overlay", owner = "GS_TerminalUI_Items", parent = "tab-warehouse" },
	{ id = "tab-red", owner = "GS_TerminalUI_Network", parent = "terminal-tabs" },
	{ id = "tab-options", owner = "GS_TerminalUI_Options", parent = "terminal-tabs" },
	{ id = "tab-options-state", owner = "GS_TerminalUI_NetworkStatus", parent = "tab-options" },
	{ id = "tab-options-admin", owner = "GS_TerminalUI_Options", parent = "tab-options" },
	{ id = "tab-addons", owner = "GS_TerminalUI_Addons", parent = "terminal-tabs" },
	{ id = "tab-programming", owner = "GS_TerminalUI_Programming", parent = "terminal-tabs" },
	{ id = "tab-craft", owner = "GSSiK_Addon_Craft_TerminalUI", parent = "terminal-tabs", optional = true },
	{ id = "tab-builder", owner = "GSSiK_Addon_Builder_TerminalUI", parent = "terminal-tabs", optional = true },
	{ id = "terminal-blocked", owner = "GS_TerminalUI_BlockedPanel", parent = "terminal-shell" },
}
for i = 1, #TERMINAL_TAB_SURFACES do
	local surface = TERMINAL_TAB_SURFACES[i]
	if not GlobalStorageSiK.SiK_UI.SurfaceInventory.get(surface.id) then
		surface.pack = "terminal-tabs"
		GlobalStorageSiK.SiK_UI.SurfaceInventory.register(surface)
	end
end

-- ===========================================================================
-- DIAGNÓSTICO doble-interfaz (v0.10.18.83) — temporal
-- Cuenta instancias vivas de GS_TerminalUI y vuelca qué paneles están
-- realmente visibles. Si hay >1 instancia o >1 panel visible a la vez,
-- ahí está el doble render. Salida en console.txt con prefijo [GS_DIAG].
-- ===========================================================================
GlobalStorageSiK.TerminalUI._liveInstances = GlobalStorageSiK.TerminalUI._liveInstances or setmetatable({}, { __mode = "k" })

local function gsCountVisibleChildren(host, revMap)
	local out = {}
	-- PZ: childrenInOrder es el ARRAY real (children es hash por ID, #children da 0).
	local ch = host and host.childrenInOrder
	if not ch then return out, 0 end
	local visCount = 0
	for i = 1, #ch do
		local c = ch[i]
		local vis = (c and c.isVisible and c:isVisible()) and true or false
		if vis then visCount = visCount + 1 end
		local key = (revMap and revMap[c]) or "?"
		out[#out + 1] = key .. ":" .. (vis and "VIS" or "hid")
	end
	return out, visCount
end

function GlobalStorageSiK.TerminalUI.debugDumpTree(tag)
	if not (GlobalStorageSiK.UIDebug and GlobalStorageSiK.UIDebug.enabled()) then
		return
	end
	local reg = GlobalStorageSiK.TerminalUI._liveInstances or {}
	local n = 0
	for _ in pairs(reg) do n = n + 1 end
	GlobalStorageSiK.UIDebug.log("DIAG", "=== %s === instancias GS_TerminalUI vivas: %d", tostring(tag), n)
	if n > 1 then
		GlobalStorageSiK.UIDebug.log("DIAG", "*** ANOMALIA: >1 ventana GS_TerminalUI viva ***")
	end
	local idx = 0
	for ui in pairs(reg) do
		idx = idx + 1
		local vis = (ui.isVisible and ui:isVisible()) and "VIS" or "hid"
		GlobalStorageSiK.UIDebug.log("DIAG", " inst#%d %s mode=%s tab=%s x=%d y=%d w=%d h=%d",
			idx, vis, tostring(ui.accessMode), tostring(ui.activeTabKey),
			ui:getX(), ui:getY(), ui:getWidth(), ui:getHeight())
		local rev = {}
		if ui.tabViews then for k, p in pairs(ui.tabViews) do rev[p] = k end end
		local list, visCount = gsCountVisibleChildren(ui.contentHost, rev)
		GlobalStorageSiK.UIDebug.log("DIAG", "   contentHost hijos=%d visibles=%d [%s]",
			#list, visCount, table.concat(list, ", "))
		if visCount > 1 then
			GlobalStorageSiK.UIDebug.log("DIAG", "   *** ANOMALIA: >1 panel de tab visible a la vez ***")
		end
		local np = ui.networkPanel
		if np and np.tabPanels then
			local sv, svCount = {}, 0
			for k, p in pairs(np.tabPanels) do
				local pv = (p and p.isVisible and p:isVisible()) and true or false
				if pv then svCount = svCount + 1 end
				sv[#sv + 1] = k .. ":" .. (pv and "VIS" or "hid")
			end
			GlobalStorageSiK.UIDebug.log("DIAG", "   network.subtabs visibles=%d [%s]", svCount, table.concat(sv, ", "))
			if svCount > 1 then
				GlobalStorageSiK.UIDebug.log("DIAG", "   *** ANOMALIA: >1 sub-tab de red visible ***")
			end
		end
		-- Verificación objetiva: ningún hermano visible pisa a otro. El
		-- volcado completo del árbol (dumpTree) se queda disponible en
		-- GS_UIDebug.lua pero ya no se invoca aquí por defecto: generaba
		-- decenas de líneas por apertura/cambio de pestaña sin aportar nada
		-- a los bugs que estamos siguiendo ahora mismo.
		GlobalStorageSiK.UIDebug.checkOverlaps(ui, tag)
	end
end

GS_TerminalUI = ISPanel:derive("GS_TerminalUI")

--- Delega en GlobalStorageSiK.TerminalProgramming.syncTabVisibility - ver
--- comentario en GS_TerminalUI_Programming.lua: esa lógica NO puede vivir
--- como "function GS_TerminalUI:xxx()" en su propio fichero porque ese
--- fichero se requiere más arriba, antes de que la clase GS_TerminalUI (esta
--- misma línea) exista todavía.
function GS_TerminalUI:syncProgrammingTabVisibility()
	if GlobalStorageSiK.TerminalProgramming and GlobalStorageSiK.TerminalProgramming.syncTabVisibility then
		GlobalStorageSiK.TerminalProgramming.syncTabVisibility(self)
	end
end

local T = GlobalStorageSiK.I18n.text
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local FONT_HGT_MEDIUM = getTextManager():getFontHeight(UIFont.Medium)

local TAB_BG = { r = 0.12, g = 0.12, b = 0.12, a = 1 }
local function resizeHandleSize()
	return GlobalStorageSiK.SiK_UI.Metrics.tokens().resizeHandle
end

--- Refresca contenido de la pestaña activa (carga diferida).
---@param self GS_TerminalUI
function GS_TerminalUI:refreshActiveTabContent()
	local state = self.terminalState or {}
	local tab = self.activeTabKey or "items"
	if self.ensureTabBuilt then self:ensureTabBuilt(tab) end
	if tab == "items" then
		GlobalStorageSiK.TerminalItems.refresh(self.itemsListPanel, self, state.items or {})
	elseif tab == "network" then
		GlobalStorageSiK.TerminalNetwork.refreshScroll(self, state)
	elseif tab == "config" then
		GlobalStorageSiK.TerminalOptions.refreshScroll(self, state)
	elseif tab == "addons" and self.addonsPanel then
		GlobalStorageSiK.TerminalAddons.refresh(self.addonsPanel, self)
	elseif tab == "blocked" and GlobalStorageSiK.TerminalBlockedPanel then
		GlobalStorageSiK.TerminalBlockedPanel.applyRefreshIfNeeded(self, true)
	elseif GlobalStorageSiK.TerminalExtensions then
		GlobalStorageSiK.TerminalExtensions.refreshActive(self, tab)
	end
end

-- Construye solo el cuerpo que el jugador va a ver. Los paneles vacíos existen
-- desde el Shell para conservar contratos/geometry, pero no crean controles,
-- scrolls, tooltips ni listeners hasta su primera activación.
function GS_TerminalUI:ensureTabBuilt(tabKey)
	self._gsBuiltTabs = self._gsBuiltTabs or {}
	if self._gsBuiltTabs[tabKey] then return end
	if tabKey == "items" then
		self:buildItemsToolbar()
	elseif tabKey == "network" then
		GlobalStorageSiK.TerminalNetwork.buildZonesSection(self, self.networkPanel)
	elseif tabKey == "config" then
		GlobalStorageSiK.TerminalOptions.buildSection(self, self.configPanel)
	elseif tabKey == "addons" then
		GlobalStorageSiK.TerminalAddons.buildPanel(self.addonsPanel, self)
	elseif tabKey == "blocked" then
		GlobalStorageSiK.TerminalBlockedPanel.build(self)
	else
		-- Las pestañas de addons conservan su propio lifecycle.
		self._gsBuiltTabs[tabKey] = true
		return
	end
	self._gsBuiltTabs[tabKey] = true
end

local function createButton(x, y, w, h, title, target, onClick)
	return GlobalStorageSiK.SiK_UI.createButton(x, y, w, h, title, target, onClick)
end

local function createTabPanel()
	local panel = ISPanel:new(0, 0, 10, 10)
	panel:initialise()
	panel.drawBackground = false
	panel.backgroundColor = TAB_BG
	panel.borderColor = { r = 0, g = 0, b = 0, a = 0 }
	panel.clipChildren = true
	panel:setScrollWithParent(false)
	if panel.setScrollChildren then
		panel:setScrollChildren(false)
	end
	return panel
end

function GS_TerminalUI:new(x, y, width, height, playerNum)
	playerNum = tonumber(playerNum) or 0
	local palettePlayer = GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer
		and GlobalStorageSiK.NetClient.getPlayer(playerNum)
		or (playerNum == 0 and getPlayer and getPlayer() or nil)
	GlobalStorageSiK.SiK_UI.Palette.load(palettePlayer)
        local o = ISPanel:new(x, y, width, height)
	setmetatable(o, self)
	self.__index = self
	o.moveWithMouse = false
	playerNum = palettePlayer and palettePlayer.getPlayerNum and palettePlayer:getPlayerNum() or playerNum
	local viewport = GlobalStorageSiK.SiK_UI.Viewport.resolve(playerNum)
	local profile = GlobalStorageSiK.SiK_UI.Metrics.profile(viewport.profile)
	local limits = GlobalStorageSiK.SiK_UI.Window.resolveLimits(viewport.profile, viewport, {
		playerNum = playerNum,
	})
	local tokens = GlobalStorageSiK.SiK_UI.Metrics.tokens()
	o.playerNum = playerNum
	o._sikWindowProfile = viewport.profile
	o.padding = tokens.windowPadding
	o.headerHeight = profile.window.headerHeight
	o.statusFooterHeight = profile.window.footerHeight
	local uiBg = GlobalStorageSiK.SiK_UI.PALETTE.bgHeader
	o.backgroundColor = { r = uiBg[1], g = uiBg[2], b = uiBg[3], a = 0.98 }
	o.borderColor = { r = 0, g = 0, b = 0, a = 1 }
	o.terminalState = nil
	o.minimumWidth = limits.minW
	o.minimumHeight = limits.minH
	o.maximumWidth = limits.maxW
	o.maximumHeight = limits.maxH
	o._sikSafeViewport = viewport
	o.resizable = true
	o.drawBackground = false
	o.resizing = false
	o.moving = false
	o.accessMode = "full"
	o.blockedState = nil
	o._gsIsTerminalUI = true
	GlobalStorageSiK.TerminalUI._liveInstances[o] = true
	return o
end

function GS_TerminalUI:applyResponsiveBounds(nextX, nextY, nextW, nextH)
	local viewport = GlobalStorageSiK.SiK_UI.Viewport.resolve(self.playerNum or 0)
	local profile = GlobalStorageSiK.SiK_UI.Metrics.profile(viewport.profile)
	local limits = GlobalStorageSiK.SiK_UI.Window.resolveLimits(viewport.profile, viewport, {
		playerNum = self.playerNum or 0,
	})
	local rect = GlobalStorageSiK.SiK_UI.Window.resolveProfile(viewport.profile, viewport, {
		x = nextX, y = nextY, width = nextW, height = nextH,
		playerNum = self.playerNum or 0,
	})
	self._sikWindowProfile = viewport.profile
	self.minimumWidth = limits.minW
	self.minimumHeight = limits.minH
	self.maximumWidth = limits.maxW
	self.maximumHeight = limits.maxH
	self._sikSafeViewport = viewport
	self.headerHeight = profile.window.headerHeight
	self.statusFooterHeight = profile.window.footerHeight
	self:setWidth(rect.w)
	self:setHeight(rect.h)
	self:setX(rect.x)
	self:setY(rect.y)
end

function GS_TerminalUI:syncAfterResponsiveResize()
	self:calculateLayout()
	if self.activeTabKey == "network" then
		if self._gsBuiltTabs and self._gsBuiltTabs.network then
			GlobalStorageSiK.TerminalNetwork.syncScrollLayout(self)
		end
	elseif self.activeTabKey == "config" then
		if self._gsBuiltTabs and self._gsBuiltTabs.config then
			GlobalStorageSiK.TerminalOptions.syncScrollLayout(self)
		end
	elseif self.activeTabKey == "addons" and self.addonsPanel then
		if self._gsBuiltTabs and self._gsBuiltTabs.addons then
			GlobalStorageSiK.TerminalAddons.syncScrollLayout(self.addonsPanel, self)
		end
	end
	GlobalStorageSiK.TerminalScroll.stripTerminalTree(self)
	if self.activeTabKey == "items" and self.itemsListPanel and GlobalStorageSiK.TerminalItems.syncLayout then
		GlobalStorageSiK.TerminalItems.syncLayout(self.itemsListPanel, self)
	end
end

--- Arrastre por cabecera y redimensionado en esquina inferior derecha.
function GS_TerminalUI:installMouseHandlers()
	self.onMouseDown = function(me, x, y)
		local resizeEdge = GlobalStorageSiK.SiK_UI.Window.resizeEdgeAt(me, x, y, resizeHandleSize())
		if resizeEdge then
			me.resizing = true
			me.resizeEdge = resizeEdge
			me:setCapture(true)
			return true
		end
		if y >= 0 and y < me.headerHeight and x < me.width - (me.closeBtn and me.closeBtn.width or 36) then
			me.moving = true
			me:setCapture(true)
			return true
		end
		return ISPanel.onMouseDown(me, x, y)
	end
	self.onMouseUp = function(me, x, y)
		if GlobalStorageSiK.TerminalWithdrawDrag.isActive() then
			return GlobalStorageSiK.TerminalWithdrawDrag.finishAtPointer()
		end
		if me.resizing then
			me.resizing = false
			me.resizeEdge = nil
			me:setCapture(false)
			me:rebuildScrollContent()
			GlobalStorageSiK.SiK_UI.Window.remember(me, "terminal-shell", me.playerNum)
			return true
		end
		if me.moving then
			me.moving = false
			me:setCapture(false)
			GlobalStorageSiK.SiK_UI.Window.remember(me, "terminal-shell", me.playerNum)
			return true
		end
		return ISPanel.onMouseUp(me, x, y)
	end
	self.onMouseUpOutside = function(me, x, y)
		if GlobalStorageSiK.TerminalWithdrawDrag.isActive() then
			return GlobalStorageSiK.TerminalWithdrawDrag.finishAtPointer()
		end
		if me.resizing then
			me.resizing = false
			me.resizeEdge = nil
			me:setCapture(false)
			me:rebuildScrollContent()
			GlobalStorageSiK.SiK_UI.Window.remember(me, "terminal-shell", me.playerNum)
			return true
		end
		if me.moving then
			me.moving = false
			me:setCapture(false)
			GlobalStorageSiK.SiK_UI.Window.remember(me, "terminal-shell", me.playerNum)
			return true
		end
		return ISPanel.onMouseUpOutside(me, x, y)
	end
	self.onMouseMove = function(me, dx, dy)
		if GlobalStorageSiK.TerminalWithdrawDrag.isActive() then
			GlobalStorageSiK.TerminalWithdrawDrag.moveToPointer()
			return true
		end
		if me.resizing then
			local rect = GlobalStorageSiK.SiK_UI.Window.resizeDelta(me, me.resizeEdge, dx, dy)
			if rect then me:applyResponsiveBounds(rect.x, rect.y, rect.w, rect.h) end
			me:syncAfterResponsiveResize()
			return true
		end
		if me.moving then
			me:applyResponsiveBounds(me.x + dx, me.y + dy, me.width, me.height)
			return true
		end
		return ISPanel.onMouseMove(me, dx, dy)
	end
	self.onMouseMoveOutside = function(me, dx, dy)
		if GlobalStorageSiK.TerminalWithdrawDrag.isActive() then
			GlobalStorageSiK.TerminalWithdrawDrag.moveToPointer()
			return true
		end
		if me.resizing then
			local rect = GlobalStorageSiK.SiK_UI.Window.resizeDelta(me, me.resizeEdge, dx, dy)
			if rect then me:applyResponsiveBounds(rect.x, rect.y, rect.w, rect.h) end
			me:syncAfterResponsiveResize()
			return true
		end
		if me.moving then
			me:applyResponsiveBounds(me.x + dx, me.y + dy, me.width, me.height)
			return true
		end
		return ISPanel.onMouseMoveOutside(me, dx, dy)
	end
end

function GS_TerminalUI:initialise()
        ISPanel.initialise(self)
        self.clipChildren = true
        self:installMouseHandlers()
        self:setVisible(true)
	GlobalStorageSiK.SiK_UI.Window.installEscape(self, GS_TerminalUI.onClose,
		GlobalStorageSiK.SiK_UI.EscapeStack.PRIORITY.TERMINAL)
        self:createChildren()
        self:calculateLayout()
end

function GS_TerminalUI:createChildren()
	-- PZ llama createChildren automáticamente desde instantiate() (ISUIElement),
	-- y nuestro initialise() lo llama también. Sin guard se construían DOS juegos
	-- de contentHost/tabRail/itemsPanel: uno quedaba huérfano pero seguía pintándose
	-- (doble interfaz) y nunca se reposicionaba (campos en sitio viejo).
	if self._gsChildrenBuilt then
		return
	end
	self._gsChildrenBuilt = true
	self.networkPanel = createTabPanel()
	self.configPanel = createTabPanel()
	self.itemsPanel = createTabPanel()
	self.addonsPanel = createTabPanel()
	self.blockedPanel = createTabPanel()
	self._gsBuiltTabs = {}
	self:ensureTabBuilt("items")

	-- "Configuración" (dev41) va justo despues de Red en el riel principal -
	-- "Addons" sigue como pestaña fija de PIE (footerTabDef, mas abajo), sin
	-- relacion de orden con este array: insertar aqui no la desplaza.
	local tabDefs = {
		{ key = "items", titleKey = "IGUI_GS_TabWarehouse", panelField = "itemsPanel", iconPath = "media/ui/GS/GS_TabWarehouse.png" },
		{ key = "network", titleKey = "IGUI_GS_TabNetwork", panelField = "networkPanel", iconPath = "media/ui/GS/GS_TabNetwork.png" },
		{ key = "config", titleKey = "IGUI_GS_TabConfig", panelField = "configPanel", iconPath = "media/ui/GS/GS_TabConfig.png" },
	}
	self.footerTabDef = {
		key = "addons",
		titleKey = "IGUI_GS_TabAddons",
		panelField = "addonsPanel",
		iconPath = "media/ui/GS/GS_TabAddons.png",
	}
	GlobalStorageSiK.TerminalTabs.build(self, tabDefs)
	self.tabViews.blocked = self.blockedPanel

	self.closeBtn = GlobalStorageSiK.SiK_UI.createCloseButton(self, self, GS_TerminalUI.onClose)

	self:calculateLayout()
	GlobalStorageSiK.TerminalScroll.stripTerminalTree(self)
end

--- Cambia la pestaña activa.
---@param tabKey string
function GS_TerminalUI:activateTab(tabKey)
	GlobalStorageSiK.TerminalTabs.activate(self, tabKey)
end

function GS_TerminalUI:buildItemsToolbar()
	local pad = self.padding
	local controls = GlobalStorageSiK.SiK_UI.Controls.metrics()
	local rowH = controls.inputHeight
	local gap = GlobalStorageSiK.SiK_UI.Metrics.spacing(8)
	local y = pad

	self.itemsTitleLbl = GlobalStorageSiK.TerminalSections.addTitleLabel(
		self.itemsPanel, pad, y, "IGUI_GS_SectionItems"
	)
	-- La accion conserva siempre la misma etiqueta. El estado y el resumen del
	-- job viven en una fila separada para no truncar mensajes dentro del boton.
	self.autoSortBtn = createButton(0, y, 220, FONT_HGT_SMALL + 8, T("IGUI_GS_Redistribute"), self, GS_TerminalUI.onRedistributeNetwork)
	self.itemsPanel:addChild(self.autoSortBtn)
	-- Hasta recibir el rol serializado por el servidor no se permite iniciar
	-- una operación sensible. updateState lo habilita solo para owner/admin.
	self.autoSortBtn:setEnable(false)
	if self.autoSortBtn.setTooltip then
		self.autoSortBtn:setTooltip(T("IGUI_GS_RedistributeHint"))
	end
	y = y + FONT_HGT_SMALL + gap

	local statusH = FONT_HGT_SMALL + 6
	self.autoSortStatusRow = GlobalStorageSiK.SiK_UI.createStatusIndicatorRow(pad, y, 320, statusH)
	self.autoSortStatusRow.drawBackground = true
	self.autoSortStatusRow.backgroundColor = { r = 0.075, g = 0.075, b = 0.09, a = 0.8 }
	self.autoSortStatusRow.borderColor = { r = 0.18, g = 0.18, b = 0.22, a = 0.9 }
	GlobalStorageSiK.SiK_UI.setStatusIndicatorRow(
		self.autoSortStatusRow, T("IGUI_GS_RedistributeIdle"), "muted", 320
	)
	self.itemsPanel:addChild(self.autoSortStatusRow)
	y = y + statusH + gap

	local _wpal = GlobalStorageSiK.SiK_UI.PALETTE
	self.itemsWeightLbl = ISLabel:new(pad, y, FONT_HGT_SMALL, T("IGUI_GS_WeightUsage", "0.0", "0.0", "0"), _wpal.statusOk[1], _wpal.statusOk[2], _wpal.statusOk[3], 1, UIFont.Small, true)
	self.itemsWeightLbl:initialise()
	self.itemsPanel:addChild(self.itemsWeightLbl)
	y = y + FONT_HGT_SMALL + gap

	local _dpal = GlobalStorageSiK.SiK_UI.PALETTE
	self.depositDropHint = ISLabel:new(pad, y, FONT_HGT_SMALL * 2, T("IGUI_GS_DropHint"), _dpal.textMuted[1], _dpal.textMuted[2], _dpal.textMuted[3], 1, UIFont.Small, true)
	self.depositDropHint:initialise()
	self.itemsPanel:addChild(self.depositDropHint)
	y = y + FONT_HGT_SMALL + gap

	local searchW = 220
	local searchBox, searchEntry = GlobalStorageSiK.SiK_UI.createSearchBox(pad, y, searchW, rowH, self.itemsPanel, nil)
	self.itemsPanel:addChild(searchBox)
	self.searchBox = searchBox
	self.searchEntry = searchEntry
	GlobalStorageSiK.SiK_UI.bindSearchEntry(self, self.searchEntry)

	local function styleFilterCombo(combo)
		GlobalStorageSiK.SiK_UI.styleComboBox(combo)
		combo:instantiate()
		combo.filterKeys = { "" }
		if combo.bringToTop then
			combo:bringToTop()
		end
	end

	self.mainCategoryFilterCombo = ISComboBox:new(0, y, 140, rowH)
	self.mainCategoryFilterCombo:initialise()
	styleFilterCombo(self.mainCategoryFilterCombo)
	self.mainCategoryFilterCombo.onChange = function()
		if self._rebuildingMainCategoryCombo or self._rebuildingSubCategoryCombo or self._rebuildingLeafCategoryCombo then
			return
		end
		if self.mainCategoryFilterCombo and self.mainCategoryFilterCombo.filterKeys then
			local idx = self.mainCategoryFilterCombo.selected or 1
			self._mainCategoryFilterKey = self.mainCategoryFilterCombo.filterKeys[idx] or ""
		end
		self:refreshItemsTab()
	end
	self.itemsPanel:addChild(self.mainCategoryFilterCombo)
	self._mainCategoryFilterKey = ""

	self.subCategoryFilterCombo = ISComboBox:new(0, y, 140, rowH)
	self.subCategoryFilterCombo:initialise()
	styleFilterCombo(self.subCategoryFilterCombo)
	self.subCategoryFilterCombo.onChange = function()
		if self._rebuildingSubCategoryCombo or self._rebuildingLeafCategoryCombo then
			return
		end
		if self.subCategoryFilterCombo and self.subCategoryFilterCombo.filterKeys then
			local idx = self.subCategoryFilterCombo.selected or 1
			self._subCategoryFilterKey = self.subCategoryFilterCombo.filterKeys[idx] or ""
		end
		self:refreshItemsTab()
	end
	self.itemsPanel:addChild(self.subCategoryFilterCombo)
	self._subCategoryFilterKey = ""

	self.leafCategoryFilterCombo = ISComboBox:new(0, y, 140, rowH)
	self.leafCategoryFilterCombo:initialise()
	styleFilterCombo(self.leafCategoryFilterCombo)
	self.leafCategoryFilterCombo.onChange = function()
		if self._rebuildingLeafCategoryCombo then
			return
		end
		if self.leafCategoryFilterCombo and self.leafCategoryFilterCombo.filterKeys then
			local idx = self.leafCategoryFilterCombo.selected or 1
			self._leafCategoryFilterKey = self.leafCategoryFilterCombo.filterKeys[idx] or ""
		end
		self:refreshItemsTab()
	end
	self.itemsPanel:addChild(self.leafCategoryFilterCombo)
	self._leafCategoryFilterKey = ""

	-- Dev30: la lupa propia sustituye al boton textual "Buscar". Es la misma
	-- accion real (no decorativa) y ocupa un cuadrado igual a la altura de la
	-- fila para liberar ancho a la caja de texto sin mover los tres filtros.
	self.searchBtn = GlobalStorageSiK.SiK_UI.createIconButton(
		0, y, rowH,
		GlobalStorageSiK.SiK_UI.getIconTexture("search"),
		self,
		GS_TerminalUI.onSearch
	)
	self.searchBtn:setTooltip(T("IGUI_GS_Search"))
	self.itemsPanel:addChild(self.searchBtn)
	y = y + rowH + gap

	self.itemsListPanel = ISPanel:new(pad, y, 200, 120)
	self.itemsListPanel:initialise()
	self.itemsListPanel.drawBackground = false
	self.itemsListPanel.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
	self.itemsListPanel.borderColor = { r = 0, g = 0, b = 0, a = 0 }
	self.itemsListPanel.clipChildren = true
	self.itemsListPanel:setScrollWithParent(false)
	self.itemsPanel:addChild(self.itemsListPanel)
	self.itemsToolbarBottomY = y
	GlobalStorageSiK.TerminalDrop.setupPanel(self.itemsListPanel, self)
	GlobalStorageSiK.TerminalDrop.setupPanel(self.itemsPanel, self)
	GlobalStorageSiK.TerminalDrop.installHooks()
end

function GS_TerminalUI:calculateLayout()
	local w = self.width
	local h = self.height
	local pad = self.padding
	local profileName = self._sikWindowProfile or "standard"
	local shell = GlobalStorageSiK.SiK_UI.Metrics.shellRects(
		profileName, w, h, self.accessMode == "blocked")
	self.headerHeight = shell.header.h
	self.statusFooterHeight = shell.footer.h
	self._sikRuntimeVersionText = GlobalStorageSiK.SiK_UI.runtimeVersionText()
	self._sikHeaderRects = GlobalStorageSiK.SiK_UI.Metrics.headerRects(profileName, w, pad)

	if self.closeBtn then
		local closeRect = self._sikHeaderRects.close
		self.closeBtn:setX(closeRect.x)
		self.closeBtn:setY(closeRect.y)
		self.closeBtn:setWidth(closeRect.w)
		self.closeBtn:setHeight(closeRect.h)
		self.closeBtn:setVisible(true)
		self.closeBtn:bringToTop()
	end

	local tabY = shell.content.y
	local bodyH = shell.content.h
	local railH = shell.rail.h
	local railW = shell.rail.w
	local contentW = shell.content.w

	local blockedMode = self.accessMode == "blocked"
	if self.tabRail then
		self.tabRail:setVisible(not blockedMode)
		self.tabRail:setX(0)
		self.tabRail:setY(tabY)
		self.tabRail:setWidth(railW)
		self.tabRail:setHeight(railH)
		if not blockedMode then
			GlobalStorageSiK.TerminalTabs.layoutRail(self)
		end
	end
	if self.contentHost then
		if blockedMode then
			self.contentHost:setX(0)
			self.contentHost:setY(tabY)
			self.contentHost:setWidth(w)
			self.contentHost:setHeight(bodyH)
		else
			self.contentHost:setX(railW)
			self.contentHost:setY(tabY)
			self.contentHost:setWidth(contentW)
			self.contentHost:setHeight(bodyH)
		end
	end

	local innerW = blockedMode and w or contentW
	local innerH = bodyH

	local tabPanels = { self.networkPanel, self.configPanel, self.itemsPanel, self.addonsPanel, self.blockedPanel }
	if self.extraTabs then
		for _, entry in pairs(self.extraTabs) do
			if entry.panel then
				tabPanels[#tabPanels + 1] = entry.panel
			end
		end
	end
	for i = 1, #tabPanels do
		local panel = tabPanels[i]
		if panel then
			panel:setX(0)
			panel:setWidth(innerW)
			panel:setHeight(innerH)
		end
	end

	if self.blockedPanel and self._gsBuiltTabs and self._gsBuiltTabs.blocked
		and GlobalStorageSiK.TerminalBlockedPanel then
		GlobalStorageSiK.TerminalBlockedPanel.layout(self, innerW, innerH)
	end

	if self._gsBuiltTabs and self._gsBuiltTabs.network then
		GlobalStorageSiK.TerminalNetwork.layout(self, innerW, innerH)
	end
	if self._gsBuiltTabs and self._gsBuiltTabs.config then
		GlobalStorageSiK.TerminalOptions.layout(self, innerW, innerH)
	end

	if self.itemsListPanel and self.itemsPanel then
		local rowH = GlobalStorageSiK.SiK_UI.Controls.metrics().inputHeight
		local gap = GlobalStorageSiK.SiK_UI.Metrics.spacing(8)
		local hintH = FONT_HGT_SMALL * 2
		local statusH = FONT_HGT_SMALL + 6
		local contentW = innerW - pad * 2

		-- La lupa usa exactamente la altura de la fila; al sustituir el boton
		-- textual su ancho sobrante pasa al campo de busqueda.
		local btnW = rowH
		if self.searchBtn then
			self.searchBtn:setWidth(btnW)
			self.searchBtn:setHeight(rowH)
		end
		-- El HTML validado separa búsqueda y filtros en dos filas: la caja no
		-- compite con tres combos y cada nivel conserva un ancho útil estable.
		local searchW = math.max(80, contentW - btnW - gap)
		if self.searchBox then
			GlobalStorageSiK.SiK_UI.layoutSearchBox(self.searchBox, searchW, rowH)
		end
		local searchWidget = self.searchBox or self.searchEntry

		-- Stack vertical de bloques: cada uno reserva su altura, ancho = contentW,
		-- la lista ocupa el resto. Reescala completo en cada pasada (resize).
		local col = GlobalStorageSiK.UILayout.column{
			x = pad, y = pad, width = contentW, bottom = innerH - pad, gap = gap,
		}
		col:place(self.itemsTitleLbl, FONT_HGT_SMALL)   -- título (solo x/y)
		if self.autoSortBtn then
			GlobalStorageSiK.SiK_UI.fitButtonToLabel(self.autoSortBtn)
			self.autoSortBtn:setX(pad + contentW - self.autoSortBtn.width)
			self.autoSortBtn:setY(pad)
		end
		col:place(self.autoSortStatusRow, statusH)
		col:label(self.itemsWeightLbl, FONT_HGT_SMALL)  -- peso (x/y/width)
		col:label(self.depositDropHint, hintH)          -- hint (x/y/width)
		col:row(rowH, {
			{ widget = searchWidget,                w = searchW },
			{ widget = self.searchBtn,               w = btnW },
		}, { gap = gap })
		col:row(rowH, {
			{ widget = self.mainCategoryFilterCombo, weight = 1, min = 90 },
			{ widget = self.subCategoryFilterCombo,  weight = 1, min = 90 },
			{ widget = self.leafCategoryFilterCombo, weight = 1, min = 90 },
		}, { gap = gap })
		col:fill(self.itemsListPanel, 120)

		local listHeaderH = FONT_HGT_SMALL + 10
		local listGap = GlobalStorageSiK.TerminalScroll.listBottomGap()
		if self.itemsListPanel.itemScroll then
			local scrollH = math.max(80, self.itemsListPanel.height - listHeaderH - listGap - 4)
			self.itemsListPanel.itemScroll:setWidth(self.itemsListPanel.width)
			self.itemsListPanel.itemScroll:setHeight(scrollH)
			if GlobalStorageSiK.TerminalItems.syncLayout then
				GlobalStorageSiK.TerminalItems.syncLayout(self.itemsListPanel, self)
			elseif GlobalStorageSiK.TerminalItems.updateVirtualRows then
				GlobalStorageSiK.TerminalItems.updateVirtualRows(self.itemsListPanel)
			end
		end
		if self.itemsListPanel.columnHeader then
			local rect = self.itemsListPanel.itemScroll
				and GlobalStorageSiK.TerminalScroll.contentRect(self.itemsListPanel.itemScroll)
				or { x = 0, w = self.itemsListPanel.width }
			self.itemsListPanel.columnHeader:setX(rect.x)
			self.itemsListPanel.columnHeader:setWidth(rect.w)
		end
	end

	if self.addonsPanel and self._gsBuiltTabs and self._gsBuiltTabs.addons then
		GlobalStorageSiK.TerminalAddons.layout(self.addonsPanel, innerW, innerH)
	end
	if GlobalStorageSiK.TerminalExtensions then
		GlobalStorageSiK.TerminalExtensions.layoutAll(self, innerW, innerH)
	end
	GlobalStorageSiK.TerminalScroll.applyTabScrollVisibility(self)
	if GlobalStorageSiK.TerminalTabs and GlobalStorageSiK.TerminalTabs.syncBlockedFrame then
		GlobalStorageSiK.TerminalTabs.syncBlockedFrame(self)
	end
end

--- Reconstruye contenido scrollable tras redimensionar (patrón Blocked UI).
function GS_TerminalUI:rebuildScrollContent()
	local state = self.terminalState
	if not state then
		GlobalStorageSiK.TerminalScroll.stripTerminalTree(self)
		return
	end
	self:calculateLayout()
	local tab = self.activeTabKey or "items"
	if tab == "network" then
		GlobalStorageSiK.TerminalNetwork.syncScrollLayout(self)
	elseif tab == "config" then
		GlobalStorageSiK.TerminalOptions.syncScrollLayout(self)
	elseif tab == "addons" and self.addonsPanel then
		GlobalStorageSiK.TerminalAddons.syncScrollLayout(self.addonsPanel, self)
	elseif tab == "items" and self.itemsListPanel then
		GlobalStorageSiK.TerminalItems.syncLayout(self.itemsListPanel, self)
	else
		self:refreshActiveTabContent()
	end
	GlobalStorageSiK.TerminalScroll.stripTerminalTree(self)
	-- Verificación tras redimensionar: ningún elemento debe pisar a otro.
	-- Cubre CUALQUIER pestaña activa (no solo bloqueo) - sandbox DebugCatSiKUI
	-- (dev36, antes DebugModeUI), desactivado no cuesta nada ni genera ruido.
	if GlobalStorageSiK.UIDebug and GlobalStorageSiK.UIDebug.enabled and GlobalStorageSiK.UIDebug.enabled() then
		GlobalStorageSiK.UIDebug.dumpTree(self, "resize->" .. tostring(self.activeTabKey))
		GlobalStorageSiK.UIDebug.checkOverlaps(self, "resize->" .. tostring(self.activeTabKey))
	end
end

function GS_TerminalUI:prerender()
	ISPanel.prerender(self)
	GlobalStorageSiK.SiK_UI.renderPanelBackground(self)
	if self.accessMode == "blocked" then
		GlobalStorageSiK.SiK_UI.renderBlockedHeader(self)
	else
		GlobalStorageSiK.SiK_UI.renderHeader(self)
	end
	if GlobalStorageSiK.TerminalTabs and GlobalStorageSiK.TerminalTabs.syncBlockedFrame then
		GlobalStorageSiK.TerminalTabs.syncBlockedFrame(self)
	end
	GlobalStorageSiK.SiK_UI.renderStatusFooter(self, self.terminalState)
	local grip = resizeHandleSize()
	local gx, gy = self.width - grip, self.height - grip
	local pal = GlobalStorageSiK.SiK_UI.PALETTE
	-- Tres diagonales escalonadas con la primitiva ISUI garantizada. No usar
	-- drawLine2: no forma parte del contrato Lua/Kahlua expuesto por vanilla.
	for line = 0, 2 do
		local length = 4 + line * 3
		for step = 0, length - 1 do
			self:drawRect(self.width - 3 - step * 2,
				self.height - 3 - (length - 1 - step) * 2,
				2, 2, 1, pal.textMuted[1], pal.textMuted[2], pal.textMuted[3])
		end
	end
	local mouseX = getMouseX and (getMouseX() - self:getAbsoluteX()) or -1
	local mouseY = getMouseY and (getMouseY() - self:getAbsoluteY()) or -1
	local overGrip = mouseX >= gx and mouseX <= self.width
		and mouseY >= gy and mouseY <= self.height
	if overGrip and not GlobalStorageSiK.TerminalWithdrawDrag.isActive() then
		if not self._gsResizeTooltip then
			self._gsResizeTooltip = ISToolTip:new()
			self._gsResizeTooltip:initialise()
			self._gsResizeTooltip:instantiate()
			self._gsResizeTooltip:setOwner(self)
		end
		self._gsResizeTooltip:setName(T("IGUI_GS_ResizeDragTooltip"))
		if not self._gsResizeTooltip:isVisible() then
			self._gsResizeTooltip:setVisible(true)
			self._gsResizeTooltip:addToUIManager()
		end
	else
		if self._gsResizeTooltip and self._gsResizeTooltip:isVisible() then
			self._gsResizeTooltip:removeFromUIManager()
			self._gsResizeTooltip:setVisible(false)
		end
	end
	GlobalStorageSiK.SiK_UI.renderWindowFrame(self)
end

function GS_TerminalUI:applyCapacityState(cap)
	if not cap then
		return
	end
	local used = string.format("%.1f", tonumber(cap.usedWeight) or 0)
	-- effectiveCapacity (base + bonus personal real de rasgos como Organizado,
	-- ver GS_NetworkCapacity.compute) es el mismo limite que el motor ya
	-- aplica para decidir si un deposito de ESTE jugador cabe de verdad - el
	-- porcentaje/estado ya vienen calculados sobre ese numero desde el
	-- servidor, asi que el total mostrado tiene que coincidir con el mismo
	-- para que la cuenta cuadre visualmente. Sin bonus, effectiveCapacity ==
	-- totalCapacity y no cambia nada respecto a antes.
	local personalBonus = tonumber(cap.personalBonus) or 0
	local effectiveCapacityNum = tonumber(cap.effectiveCapacity) or tonumber(cap.totalCapacity) or 0
	local total = string.format("%.1f", effectiveCapacityNum)
	local pct = tonumber(cap.percent) or 0
	local status = cap.status or "ok"
	local pal = GlobalStorageSiK.SiK_UI.PALETTE
	local r, g, b = pal.statusOk[1], pal.statusOk[2], pal.statusOk[3]
	if status == "warning" then
		r, g, b = pal.statusWarn[1], pal.statusWarn[2], pal.statusWarn[3]
	elseif status == "critical" or status == "full" then
		r, g, b = pal.statusDanger[1], pal.statusDanger[2], pal.statusDanger[3]
	end

	local pctText = tostring(pct) .. "%"
	local weightText
	if effectiveCapacityNum > 0 then
		weightText = T("IGUI_GS_WeightUsage", used, total, pctText)
	else
		weightText = T("IGUI_GS_WeightUsedOnly", used)
	end
	if personalBonus > 0 then
		weightText = weightText .. " " .. T("IGUI_GS_WeightPersonalBonus", string.format("%.1f", personalBonus))
	end

	-- Los widgets de estado (statWeight, weightBar) viven en la sub-pestaña "red"
	local netScroll = nil
	local np = self.networkPanel
	if np and np.tabPanels and np.tabPanels.red and np.tabPanels.red.tabScroll then
		netScroll = np.tabPanels.red.tabScroll
	elseif np then
		netScroll = np.networkMainScroll  -- backward compat
	end
	local netUi = netScroll and (netScroll._gsTabUi or netScroll._gsNetUi)
	local statWeight = netUi and netUi.stats and netUi.stats.statWeight
	if statWeight and statWeight.setName and GlobalStorageSiK.TerminalScroll.isLiveWidget(statWeight) then
		statWeight:setName(weightText)
		statWeight.r = r
		statWeight.g = g
		statWeight.b = b
	end
	if netUi and GlobalStorageSiK.TerminalScroll.isLiveWidget(netUi.weightBar) then
		netUi.weightBar.capacityPercent = pct
		netUi.weightBar.capacityStatus = status
	end
	if netScroll and netScroll._weightLbl then
		netScroll._weightLbl:setName(weightText)
		netScroll._weightLbl.r = r
		netScroll._weightLbl.g = g
		netScroll._weightLbl.b = b
	end
	if self.itemsWeightLbl then
		self.itemsWeightLbl:setName(weightText)
		self.itemsWeightLbl.r = r
		self.itemsWeightLbl.g = g
		self.itemsWeightLbl.b = b
	end
	if netScroll and netScroll._weightBar then
		netScroll._weightBar.capacityPercent = pct
		netScroll._weightBar.capacityStatus = status
	end
end

function GS_TerminalUI:render()
	ISPanel.render(self)
end

function GS_TerminalUI:refreshNetworkPanel()
	self:applyCapacityState((self.terminalState or {}).capacity)
	local nodes = self.terminalState and self.terminalState.nodes or {}
	local info = GlobalStorageSiK.TerminalNodes.getNetworkIncidentInfo
		and GlobalStorageSiK.TerminalNodes.getNetworkIncidentInfo(nodes) or { count = 0 }
	if info.count and info.count > 0 then
		info.tooltip = T("IGUI_GS_NetworkIncidentTip", info.count)
	end
	self.networkIncident = info
	if self.tabRail and self.tabRail.syncSelection then
		self.tabRail:syncSelection()
	end
end

function GS_TerminalUI:refreshFromState(state)
	local prev = self.terminalState or {}
	if state and state.inventorySync then
		local merged = {}
		for k, v in pairs(prev) do
			merged[k] = v
		end
		if state.networkId then
			merged.networkId = state.networkId
		end
		if state.searchQuery ~= nil then
			merged.searchQuery = state.searchQuery
		end
		if state.inventoryRevision then
			merged.inventoryRevision = state.inventoryRevision
		end
		if state.snapshotRevision then
			merged.snapshotRevision = state.snapshotRevision
		end
		if state.redistributeActive ~= nil then
			merged.redistributeActive = state.redistributeActive == true
		end
		if state.itemTypeCount then
			merged.itemTypeCount = state.itemTypeCount
		end
		if state.capacity then
			merged.capacity = state.capacity
		end
		-- BUG REAL (2026-08-16, "la lista de nodos no actualiza su cantidad de
		-- tipos distintos en tiempo real... no actualiza si no cierro y abro o
		-- cambio de pestaña"): esta rama inventorySync (sync ligero tras
		-- depositar/retirar) nunca tocaba merged.nodes, asi que la columna
		-- "Tipos" (node.itemTypeCount) se quedaba con el valor del ultimo
		-- pushTerminalState completo. Parchea in-place por id contra el mapa
		-- ligero nodeTypeCounts que ahora manda el servidor
		-- (buildLiveNodeTypeCounts en GS_Server.lua), sin reenviar zones/nodes
		-- completos.
		if state.nodeTypeCounts and merged.nodes then
			for i = 1, #merged.nodes do
				local node = merged.nodes[i]
				local c = node and state.nodeTypeCounts[node.id]
				if c ~= nil then
					node.itemTypeCount = c
				end
			end
		end
		if state.items then
			merged.items = GlobalStorageSiK.NativeProduct.copyRows(state.items)
		end
		state = merged
	end
	if state and state.items then
		state.items = GlobalStorageSiK.NativeProduct.copyRows(state.items)
	end
	self.terminalState = state or prev
	-- BUG REAL reportado por el usuario (2026-08-26): sin energia, el
	-- terminal se abria igualmente en Almacen (activeTabKey nil al abrir
	-- nunca pasa por TerminalTabs.activate, que ya bloquea el CAMBIO a esa
	-- pestaña pero no la apertura inicial por defecto). Fuerza el mismo
	-- redirect a Red -> Red en cuanto llega el primer estado sin energia,
	-- tanto en la apertura como si la red se queda sin ella mientras el
	-- jugador esta viendo Almacen/Addons.
	if GlobalStorageSiK.Sandbox.requiresPower()
		and self.terminalState.powered == false
		and (self.activeTabKey == nil or self.activeTabKey == "items" or self.activeTabKey == "addons") then
		-- dev41: el resumen con el indicador de energia vive ahora en
		-- Configuracion -> "Estado" (antes Red -> "Red"), tras mudar esa
		-- sub-pestaña fuera de la pestaña Red (que se quedo solo con "Zonas y
		-- nodos"). Mismo redirect, nueva casa.
		if self.configPanel then
			self.configPanel.activeSubTab = "estado"
		end
		self:activateTab("config")
	end
	if self.terminalState.redistributeActive == true then
		self:setRedistributeState(true, T("IGUI_GS_RedistributeConfigLocked"), "warn")
	elseif self._autoSortRunning then
		self:setRedistributeState(false, T("IGUI_GS_RedistributeIdle"), "muted")
	elseif self:canUseAutoSort() then
		self:setRedistributeState(false, T("IGUI_GS_RedistributeIdle"), "muted")
	else
		self:setRedistributeState(false, T("IGUI_GS_RedistributeAdminOnly"), "warn")
	end
	if state and state.accessMode then
		self.terminalState.accessMode = state.accessMode
	elseif state and not state.openUi and prev.accessMode then
		self.terminalState.accessMode = prev.accessMode
	end
	if state and state.searchQuery and self.searchEntry then
		local entryText = self.searchEntry:getText() or ""
		if entryText == "" and state.searchQuery ~= "" then
			self.searchEntry:setText(state.searchQuery)
		end
	end
	self:calculateLayout()
	self:refreshNetworkPanel()
	local cap = self.terminalState.capacity
	if cap and not self._capacityHaloShown then
		local st = cap.status
		if st == "warning" or st == "critical" or st == "full" then
			local player = GlobalStorageSiK.NetClient.getPlayer(self.playerNum)
			if player and player.setHaloNote then
				local msg
				if st == "full" then
					msg = T("IGUI_GS_WeightFull")
				elseif st == "critical" then
					msg = T("IGUI_GS_WeightCritical", tostring(cap.percent or 0) .. "%")
				else
					msg = T("IGUI_GS_WeightWarn", tostring(cap.percent or 0) .. "%")
				end
				player:setHaloNote(msg, 255, st == "warning" and 200 or 120, 60, 520)
				self._capacityHaloShown = true
			end
		end
	end
	local tab = self.activeTabKey or "items"
	if tab == "items" then
		self:refreshItemsTab()
	elseif tab == "network" then
		GlobalStorageSiK.TerminalNetwork.refreshScroll(self, self.terminalState)
		if GlobalStorageSiK.TerminalNodeEditor.syncNodeData then
			GlobalStorageSiK.TerminalNodeEditor.syncNodeData(self, self.terminalState.nodes or {})
		end
		if GlobalStorageSiK.TerminalZoneEditor and GlobalStorageSiK.TerminalZoneEditor.syncZoneData then
			GlobalStorageSiK.TerminalZoneEditor.syncZoneData(self.terminalState.zones or {})
		end
	elseif tab == "config" then
		GlobalStorageSiK.TerminalOptions.refreshScroll(self, self.terminalState)
	elseif tab == "addons" and self.addonsPanel then
		GlobalStorageSiK.TerminalAddons.refresh(self.addonsPanel, self)
	elseif GlobalStorageSiK.TerminalExtensions then
		GlobalStorageSiK.TerminalExtensions.refreshActive(self, tab)
	end
	-- Programación va ANTES que Craft/Build para que, si el periférico Reader
	-- ya está instalado cuando el terminal abre por primera vez, su pestaña
	-- reclame su hueco en self.dynamicSlots (append-only, ver
	-- GS_TerminalTabRail:setDynamicTabVisible) antes que ellas.
	if self.syncProgrammingTabVisibility then
		self:syncProgrammingTabVisibility()
	end
	if self.syncCraftTabVisibility then
		self:syncCraftTabVisibility()
	end
	if self.syncBuildTabVisibility then
		self:syncBuildTabVisibility()
	end
	if GlobalStorageSiK.NodeHighlight and GlobalStorageSiK.NodeHighlight.reapplyAfterRefresh then
		GlobalStorageSiK.NodeHighlight.reapplyAfterRefresh(self.terminalState and self.terminalState.nodes)
	end
	GlobalStorageSiK.TerminalScroll.stripTerminalTree(self)
end

--- Compatibilidad con API de ventana bloqueada integrada.
---@param force boolean|nil
function GS_TerminalUI:applyRefreshIfNeeded(force)
	if self.accessMode == "blocked" and GlobalStorageSiK.TerminalBlockedPanel then
		GlobalStorageSiK.TerminalBlockedPanel.applyRefreshIfNeeded(self, force)
	end
end

function GS_TerminalUI:onClose()
	if self._closing then return end
	self._closing = true
	if self._gsResizeTooltip and self._gsResizeTooltip:isVisible() then
		self._gsResizeTooltip:removeFromUIManager()
		self._gsResizeTooltip:setVisible(false)
	end
	GlobalStorageSiK.SiK_UI.Window.remember(self, "terminal-shell", self.playerNum)
	if GlobalStorageSiK.UIDebug then GlobalStorageSiK.UIDebug.log("OPEN", "onClose()") end
	if GlobalStorageSiK.TerminalBlockedUI and GlobalStorageSiK.TerminalBlockedUI.instance == self then
		GlobalStorageSiK.TerminalBlockedUI.instance = nil
	end
	if GlobalStorageSiK.TerminalBlockedUI and GlobalStorageSiK.TerminalBlockedUI.instances
		and GlobalStorageSiK.TerminalBlockedUI.instances[self.playerNum] == self then
		GlobalStorageSiK.TerminalBlockedUI.instances[self.playerNum] = nil
	end
	if GlobalStorageSiK.NodeHighlight and GlobalStorageSiK.NodeHighlight.clear then
		GlobalStorageSiK.NodeHighlight.clear()
	end
	if GlobalStorageSiK.TerminalBlockedPanel and GlobalStorageSiK.TerminalBlockedPanel._marking then
		GlobalStorageSiK.TerminalBlockedPanel._marking = false
		if GlobalStorageSiK.WorldHighlight and GlobalStorageSiK.WorldHighlight.clearAll then
			GlobalStorageSiK.WorldHighlight.clearAll()
		end
	end
	if GlobalStorageSiK.TerminalBlockedPanel and GlobalStorageSiK.TerminalBlockedPanel._singleMarking then
		GlobalStorageSiK.TerminalBlockedPanel._singleMarking = false
		GlobalStorageSiK.TerminalBlockedPanel._singleMarkedRow = nil
		if GlobalStorageSiK.WorldHighlight and GlobalStorageSiK.WorldHighlight.clearAll then
			GlobalStorageSiK.WorldHighlight.clearAll()
		end
	end
	local player = GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer
		and GlobalStorageSiK.NetClient.getPlayer(self.playerNum)
	-- El servidor mantiene una lista explicita de clientes que estan mirando
	-- cada terminal para no difundirles indices completos solo por tener acceso
	-- a la red. Notificar el cierre antes de borrar la sesion local.
	if player and GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.sendCommand then
		GlobalStorageSiK.NetClient.sendCommand("closeTerminal", {
			networkId = self.terminalState and self.terminalState.networkId or nil,
		}, player)
	end
	if player and GlobalStorageSiK.TerminalAccess and GlobalStorageSiK.TerminalAccess.clearSession then
		GlobalStorageSiK.TerminalAccess.clearSession(player)
	end
	if GlobalStorageSiK.WithdrawClient and GlobalStorageSiK.WithdrawClient.cancelAll then
		GlobalStorageSiK.WithdrawClient.cancelAll()
	end
	if GlobalStorageSiK.TerminalWithdrawDrag and GlobalStorageSiK.TerminalWithdrawDrag.cancel then
		GlobalStorageSiK.TerminalWithdrawDrag.cancel()
	end
	if GlobalStorageSiK.Client and GlobalStorageSiK.Client.clearTransientCaches then
		GlobalStorageSiK.Client.clearTransientCaches(self.playerNum)
	end
	if GlobalStorageSiK.TransferQueue and GlobalStorageSiK.TransferQueue.clear then
		GlobalStorageSiK.TransferQueue.clear()
	end
	self:setVisible(false)
	self:removeFromUIManager()
	self._capacityHaloShown = nil
	if GlobalStorageSiK.TerminalUI.removeInstanceForPlayer then
		GlobalStorageSiK.TerminalUI.removeInstanceForPlayer(self.playerNum, self)
	elseif GlobalStorageSiK.TerminalUI.instance == self then
		GlobalStorageSiK.TerminalUI.instance = nil
	end
	if GlobalStorageSiK.TerminalUI._liveInstances then
		GlobalStorageSiK.TerminalUI._liveInstances[self] = nil
	end
end

function GS_TerminalUI:sendCommand(command, payload)
	return GlobalStorageSiK.NetClient.sendCommand(command, payload or {}, self.playerNum)
end

function GS_TerminalUI:onCreateStructureZone()
	if not self:canEditNetworkConfig(true) then return end
	self:sendCommand("createZoneStructure", {})
end

function GS_TerminalUI:onCreateRoomZone()
	if not self:canEditNetworkConfig(true) then return end
	self:sendCommand("createZoneRoom", {})
end

function GS_TerminalUI:onCreateSafehouseZone()
	if not self:canEditNetworkConfig(true) then return end
	self:sendCommand("createZoneSafehouse", {})
end

function GS_TerminalUI:onCreateSelectionZone()
	if not self:canEditNetworkConfig(true) then return end
	if GlobalStorageSiK.ZonePicker then
		GlobalStorageSiK.ZonePicker.start(self)
	end
end

function GS_TerminalUI:onCreateBuildingZone()
	if not self:canEditNetworkConfig(true) then return end
	self:sendCommand("createZoneBuilding", {})
end

function GS_TerminalUI:onRescanZone(zoneId)
	if not self:canEditNetworkConfig(true) then return end
	self:sendCommand("rescanZone", {
		zoneId = zoneId,
		searchQuery = self.searchEntry and self.searchEntry:getText() or "",
	})
end

function GS_TerminalUI:onRescanNetwork()
	if not self:canEditNetworkConfig(true) then return end
	self:sendCommand("rescanNetwork", {
		searchQuery = self:getSearchQuery(),
	})
end

function GS_TerminalUI:onCancelZoneScan()
	if not self:canEditNetworkConfig(true) then return end
	self:sendCommand("cancelZoneScan", {
		searchQuery = self:getSearchQuery(),
	})
end

function GS_TerminalUI:onRequestOpen()
	local player = GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer(self.playerNum)
		or (self.playerNum == 0 and getPlayer and getPlayer() or nil)
	local payload = GlobalStorageSiK.TerminalAccess.enrichCommandPayload(player, {
		searchQuery = self:getSearchQuery(),
	}, self.terminalState and self.terminalState.networkId
		or (GlobalStorageSiK.Client and GlobalStorageSiK.Client.activeNetworkIdByPlayer
			and GlobalStorageSiK.Client.activeNetworkIdByPlayer[self.playerNum]))
	GlobalStorageSiK.NetClient.sendCommand("openTerminal", payload, player)
end

--- El payload de permisos lo calcula el servidor con la identidad persistente
--- del personaje. El cliente solo lo usa para representar el mismo gate; el
--- handler servidor sigue siendo la autoridad definitiva.
---@return boolean
function GS_TerminalUI:canUseAutoSort()
	local permissions = self.terminalState and self.terminalState.permissions or nil
	return permissions and permissions.canAutoSort == true or false
end

---@param running boolean
---@param message string|nil
---@param status string|nil
function GS_TerminalUI:setRedistributeState(running, message, status)
	local stateChanged = self._autoSortRunning ~= (running == true)
	self._autoSortRunning = running == true
	if self.terminalState then
		self.terminalState.redistributeActive = self._autoSortRunning
	end
	if self.autoSortBtn then
		self.autoSortBtn._sikUiLabel = T("IGUI_GS_Redistribute")
		self.autoSortBtn.textColor = nil
		local allowed = self:canUseAutoSort()
		-- Auditoria de botones (2026-08-26): _sikUiLocked refleja SOLO el
		-- motivo "sin permiso" (requisito no cumplido, el mismo concepto que
		-- el resto de botones bloqueados) - "ya se esta ejecutando" es un
		-- estado transitorio de trabajo en curso, categoria distinta, no se
		-- pinta igual (sigue usando el atenuado plano de setEnable a secas).
		self.autoSortBtn._sikUiLocked = not allowed
		self.autoSortBtn:setEnable(not self._autoSortRunning and allowed)
		if self.autoSortBtn.setTooltip then
			self.autoSortBtn:setTooltip(allowed
				and T("IGUI_GS_RedistributeHint")
				or T("IGUI_GS_RedistributeAdminOnly"))
		end
	end
	GlobalStorageSiK.SiK_UI.setStatusIndicatorRow(
		self.autoSortStatusRow,
		message or (self._autoSortRunning and T("IGUI_GS_RedistributingNetwork") or T("IGUI_GS_RedistributeIdle")),
		status or (self._autoSortRunning and "warn" or "muted"),
		self.autoSortStatusRow and self.autoSortStatusRow.width or nil
	)
	if stateChanged and self.activeTabKey == "network" and GlobalStorageSiK.TerminalNetwork then
		GlobalStorageSiK.TerminalNetwork.refreshActiveTab(self, self.terminalState)
	end
end

--- La autoridad real vive en servidor; este gate evita abrir editores que el
--- servidor tendría que rechazar mientras la captura de Auto Sort está activa.
function GS_TerminalUI:canEditNetworkConfig(showWarning)
	local locked = self._autoSortRunning == true
		or (self.terminalState and self.terminalState.redistributeActive == true)
	if locked and showWarning then
		local player = GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer
			and GlobalStorageSiK.NetClient.getPlayer(self.playerNum) or nil
		if player and player.setHaloNote then
			player:setHaloNote(T("IGUI_GS_RedistributeConfigLocked"), 255, 190, 70, 420)
		end
	end
	return not locked
end

function GS_TerminalUI:onRedistributeNetwork()
	if self._autoSortRunning then return end
	if not self:canUseAutoSort() then
		local player = GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer
			and GlobalStorageSiK.NetClient.getPlayer(self.playerNum) or nil
		if player and player.setHaloNote then
			player:setHaloNote(T("IGUI_GS_RedistributeAdminOnly"), 255, 190, 70, 420)
		end
		return
	end
	self:setRedistributeState(true, T("IGUI_GS_RedistributingNetwork"), "warn")
	self:sendCommand("redistributeNetwork", {
		searchQuery = self.searchEntry and self.searchEntry:getText() or "",
	})
end

---@param message string|nil
function GS_TerminalUI:onRedistributeStarted(message)
	self:setRedistributeState(true, message, "warn")
end

--- Llamado desde GS_Client.lua al recibir el actionResult de fin de job
--- (jobType="redistribute").
---@param ok boolean
---@param message string|nil
function GS_TerminalUI:onRedistributeFinished(ok, message)
	self:setRedistributeState(false, message, ok and "ok" or "error")
end

--- Texto actual del buscador de ítems.
---@return string
function GS_TerminalUI:getSearchQuery()
	return self.searchEntry and self.searchEntry:getText() or ""
end

--- Filtra el catálogo de ítems según categoría y buscador (idioma del cliente).
---@param rows table[]|nil
---@return table[]
function GS_TerminalUI:applyItemsFilter(rows)
	rows = rows or {}
	rows = GlobalStorageSiK.TerminalItems.filterByMainCategory(rows, self:getMainCategoryFilterKey())
	rows = GlobalStorageSiK.TerminalItems.filterBySubCategory(rows, self:getSubCategoryFilterKey())
	rows = GlobalStorageSiK.TerminalItems.filterByLeafCategory(rows, self:getLeafCategoryFilterKey())
	local q = self:getSearchQuery()
	if q == "" then
		return rows
	end
	-- El filtro localizado es puro y opera sobre el snapshot ya disponible;
	-- debe ser idéntico en SP, host y cliente MP. Index.filterRows queda solo
	-- como fallback defensivo si la capa i18n no llegó a cargar.
	if GlobalStorageSiK.I18n.filterItemRows then
		return GlobalStorageSiK.I18n.filterItemRows(rows, q)
	end
	return GlobalStorageSiK.Index.filterRows(rows, q)
end

--- Clave de categoría principal activa (vacío = todas).
---@return string
function GS_TerminalUI:getMainCategoryFilterKey()
	local combo = self.mainCategoryFilterCombo
	if combo and combo.filterKeys then
		local idx = combo.selected or 1
		return combo.filterKeys[idx] or ""
	end
	return self._mainCategoryFilterKey or ""
end

--- Clave de subcategoría (Nivel 2) activa (vacío = todas).
---@return string
function GS_TerminalUI:getSubCategoryFilterKey()
	local combo = self.subCategoryFilterCombo
	if combo and combo.filterKeys then
		local idx = combo.selected or 1
		return combo.filterKeys[idx] or ""
	end
	return self._subCategoryFilterKey or ""
end

--- Clave de sub-subcategoría (Nivel 3) activa (vacío = todas).
---@return string
function GS_TerminalUI:getLeafCategoryFilterKey()
	local combo = self.leafCategoryFilterCombo
	if combo and combo.filterKeys then
		local idx = combo.selected or 1
		return combo.filterKeys[idx] or ""
	end
	return self._leafCategoryFilterKey or ""
end

--- Firma de una lista de filtros de combo (solo las claves, orden estable) -
--- dos snapshots con el mismo conjunto de tipos/categorias visibles producen
--- la MISMA firma aunque `allItems` sea una tabla nueva por referencia.
---@param filters table[] lista de {key=..., label=...}
---@return string
local function filterListSignature(filters)
	local keys = {}
	for i = 1, #filters do
		keys[i] = filters[i].key or ""
	end
	return table.concat(keys, "\1")
end

--- Rellena el combo de categorías principales a partir del catálogo actual.
---@param allItems table[]
-- BUG REAL DE RENDIMIENTO cerrado (2026-08-26, mismo informe de telemetria
-- real que los fixes de sortRows/asciiLower/itemSearchHaystack de arriba -
-- "los 3 combos de categoria se reconstruyen en cada refresco aunque solo
-- dependan del catalogo"): refreshItemsTab() los reconstruye SIEMPRE,
-- incluida cada pulsacion de tecla en el buscador (via onSearch), aunque el
-- catalogo y la seleccion de categoria/subcategoria no hayan cambiado en
-- absoluto - clear()+addOption() por cada opcion es coste de UI real, no
-- solo de Lua. Cada rebuildXCombo salta el trabajo si su propia firma de
-- entrada (catalogo + claves de las que depende) es identica a la del
-- ultimo build - misma logica ya usada en isTabUiHealthy() para otras
-- pestañas ("solo reconstruir cuando algo relevante cambio de verdad").
--
-- BUG REAL DE RENDIMIENTO #2 cerrado (2026-08-27, informe de telemetria de
-- Simucad tras dev19: "el snapshot del servidor entrega tablas de fila
-- nuevas cada ~2s - la identidad de tabla cambia aunque el catalogo logico
-- sea identico, y la comparacion `== allItems` falla siempre entre
-- snapshots"): la comparacion de REFERENCIA sigue como guardia rapida (0
-- coste mientras `allItems` no cambie, es decir entre pulsaciones de tecla
-- dentro del mismo snapshot), pero cuando la referencia SI cambia ya no se
-- reconstruye la UI a ciegas - se recalculan los filtros (barato, sin tocar
-- el combo) y solo se llama a clear()/addOption() si la FIRMA semantica
-- (conjunto real de claves de categoria) difiere de la ultima construida.
-- Los contadores de objetos no entran en la firma - un snapshot que solo
-- cambia cantidades nunca dispara una reconstruccion de combo.
function GS_TerminalUI:rebuildMainCategoryFilterCombo(allItems)
	local combo = self.mainCategoryFilterCombo
	if not combo then
		return
	end
	if self._mainCategoryComboSourceItems == allItems then
		return
	end
	self._mainCategoryComboSourceItems = allItems
	local filters = GlobalStorageSiK.TerminalItems.collectMainCategoryFilters(allItems or {})
	local signature = filterListSignature(filters)
	if self._mainCategoryComboSignature == signature then
		return
	end
	self._mainCategoryComboSignature = signature
	local prevKey = self:getMainCategoryFilterKey()
	self._rebuildingMainCategoryCombo = true
	combo:clear()
	combo.filterKeys = { "" }
	combo:addOption(T("IGUI_GS_FilterCategoryAll"))
	for i = 1, #filters do
		local entry = filters[i]
		combo.filterKeys[#combo.filterKeys + 1] = entry.key
		combo:addOption(entry.label)
	end
	combo.selected = 1
	for i = 1, #combo.filterKeys do
		if combo.filterKeys[i] == prevKey then
			combo.selected = i
			break
		end
	end
	self._mainCategoryFilterKey = combo.filterKeys[combo.selected] or ""
	self._rebuildingMainCategoryCombo = nil
end

--- Rellena el combo de subcategorías (dependiente de la categoría principal).
---@param allItems table[]
function GS_TerminalUI:rebuildSubCategoryFilterCombo(allItems)
	local combo = self.subCategoryFilterCombo
	if not combo then
		return
	end
	local mainKey = self:getMainCategoryFilterKey()
	if self._subCategoryComboSourceItems == allItems and self._subCategoryComboSourceMainKey == mainKey then
		return
	end
	self._subCategoryComboSourceItems = allItems
	self._subCategoryComboSourceMainKey = mainKey
	local filters = GlobalStorageSiK.TerminalItems.collectSubCategoryFilters(allItems or {}, mainKey)
	local signature = mainKey .. "\2" .. filterListSignature(filters)
	if self._subCategoryComboSignature == signature then
		return
	end
	self._subCategoryComboSignature = signature
	local prevKey = self:getSubCategoryFilterKey()
	self._rebuildingSubCategoryCombo = true
	combo:clear()
	combo.filterKeys = { "" }
	combo:addOption(T("IGUI_GS_FilterSubCategoryAll"))
	for i = 1, #filters do
		local entry = filters[i]
		combo.filterKeys[#combo.filterKeys + 1] = entry.key
		combo:addOption(entry.label)
	end
	combo.selected = 1
	for i = 1, #combo.filterKeys do
		if combo.filterKeys[i] == prevKey then
			combo.selected = i
			break
		end
	end
	self._subCategoryFilterKey = combo.filterKeys[combo.selected] or ""
	self._rebuildingSubCategoryCombo = nil
end

--- Rellena el combo de sub-subcategorías (dependiente de categoria y subcategoria).
---@param allItems table[]
function GS_TerminalUI:rebuildLeafCategoryFilterCombo(allItems)
	local combo = self.leafCategoryFilterCombo
	if not combo then
		return
	end
	local mainKey = self:getMainCategoryFilterKey()
	local subKey = self:getSubCategoryFilterKey()
	if self._leafCategoryComboSourceItems == allItems
		and self._leafCategoryComboSourceMainKey == mainKey
		and self._leafCategoryComboSourceSubKey == subKey then
		return
	end
	self._leafCategoryComboSourceItems = allItems
	self._leafCategoryComboSourceMainKey = mainKey
	self._leafCategoryComboSourceSubKey = subKey
	local filters = GlobalStorageSiK.TerminalItems.collectLeafCategoryFilters(allItems or {}, mainKey, subKey)
	local signature = mainKey .. "\2" .. subKey .. "\2" .. filterListSignature(filters)
	if self._leafCategoryComboSignature == signature then
		return
	end
	self._leafCategoryComboSignature = signature
	local prevKey = self:getLeafCategoryFilterKey()
	self._rebuildingLeafCategoryCombo = true
	combo:clear()
	combo.filterKeys = { "" }
	combo:addOption(T("IGUI_GS_FilterSubCategoryAll"))
	for i = 1, #filters do
		local entry = filters[i]
		combo.filterKeys[#combo.filterKeys + 1] = entry.key
		combo:addOption(entry.label)
	end
	combo.selected = 1
	for i = 1, #combo.filterKeys do
		if combo.filterKeys[i] == prevKey then
			combo.selected = i
			break
		end
	end
	self._leafCategoryFilterKey = combo.filterKeys[combo.selected] or ""
	self._rebuildingLeafCategoryCombo = nil
end

--- Refresca la pestaña Ítems aplicando filtros locales.
-- Traza `durationMs` (2026-08-26, mismo patron ya usado en GS_ZoneScanJob.lua)
-- añadida para poder MEDIR de verdad el efecto de los fixes de rendimiento de
-- dev18 (sortRows/asciiLower/itemSearchHaystack/combos), no solo asumirlo -
-- reportado originalmente por un miembro de la comunidad con telemetria real
-- de servidor (refreshItemsTab en 1157ms sobre 1286 tipos/188 nodos, 15-16ms
-- esperados tras memorizar). Reutiliza el canal YA gateado de UIDebug (esta
-- funcion se dispara en CADA tecla del buscador - un Log.warn "siempre
-- visible" aqui seria justo el tipo de ruido de consola que el proyecto
-- evita a proposito, ver regla de diagnostico dirigido del CLAUDE.md).
function GS_TerminalUI:refreshItemsTab()
	if not self.itemsListPanel then
		return
	end
	local startedMs = (GlobalStorageSiK.UIDebug and GlobalStorageSiK.UIDebug.enabled() and getTimestampMs)
		and getTimestampMs() or nil
	local allItems = self.terminalState and self.terminalState.items or {}
	if GlobalStorageSiK.UIDebug then
		GlobalStorageSiK.UIDebug.action("refreshItemsTab", "items=" .. tostring(#allItems))
	end
	self.itemsListPanel._itemsCatalog = allItems
	self:rebuildMainCategoryFilterCombo(allItems)
	self:rebuildSubCategoryFilterCombo(allItems)
	self:rebuildLeafCategoryFilterCombo(allItems)
	local filtered = self:applyItemsFilter(allItems)
	GlobalStorageSiK.TerminalItems.refresh(self.itemsListPanel, self, filtered)
	if startedMs then
		GlobalStorageSiK.UIDebug.action("refreshItemsTab_done",
			"durationMs=" .. tostring(getTimestampMs() - startedMs)
				.. " items=" .. tostring(#allItems)
				.. " filtered=" .. tostring(#filtered))
	end
end

function GS_TerminalUI:onSearch(force)
	if type(force) ~= "boolean" then
		force = true
	end
	self._searchForceApply = force
	self:refreshItemsTab()
	self._searchForceApply = nil
end

function GS_TerminalUI:onWithdrawRow(row, amount, targetKey)
	if not row or not row.fullType then
		return
	end
	GlobalStorageSiK.WithdrawClient.sendWithdraw(
		row,
		amount or 1,
		targetKey,
		self.searchEntry and self.searchEntry:getText() or ""
	)
end

function GS_TerminalUI:onMoveZonePriority(zoneId, direction)
	if not self:canEditNetworkConfig(true) then return end
	self:sendCommand("moveZonePriority", {
		zoneId = zoneId,
		direction = direction,
		searchQuery = self:getSearchQuery(),
	})
end

function GS_TerminalUI:onSetZonePriority(zoneId, priority)
	if not self:canEditNetworkConfig(true) then return end
	self:sendCommand("setZonePriority", {
		zoneId = zoneId,
		priority = priority,
		searchQuery = self.searchEntry and self.searchEntry:getText() or "",
	})
end

function GS_TerminalUI:onRenameZone(zoneId, name)
	if not self:canEditNetworkConfig(true) then return end
	self:sendCommand("renameZone", {
		zoneId = zoneId,
		name = name,
		searchQuery = self.searchEntry and self.searchEntry:getText() or "",
	})
end

function GS_TerminalUI:onDeleteZone(zoneId)
	if not self:canEditNetworkConfig(true) then return end
	self:sendCommand("deleteZone", {
		zoneId = zoneId,
		searchQuery = self.searchEntry and self.searchEntry:getText() or "",
	})
end

function GS_TerminalUI:onRemoveNode(nodeId)
	if not self:canEditNetworkConfig(true) then return end
	self:sendCommand("removeNode", {
		nodeId = nodeId,
		searchQuery = self.searchEntry and self.searchEntry:getText() or "",
	})
end

function GS_TerminalUI:onRequestRebindProposal(nodeId, targetNodeId)
	if not self:canEditNetworkConfig(true) then return end
	self:sendCommand("requestRebindProposal", {
		nodeId = nodeId, targetNodeId = targetNodeId,
		searchQuery = self.searchEntry and self.searchEntry:getText() or "",
	})
end

function GS_TerminalUI:onRebindNode(nodeId, rebindToken)
	if not self:canEditNetworkConfig(true) then return end
	self:sendCommand("rebindNode", {
		nodeId = nodeId, rebindToken = rebindToken,
		searchQuery = self.searchEntry and self.searchEntry:getText() or "",
	})
end

function GS_TerminalUI:onRequestConfigTransferProposal(nodeId, targetNodeId)
	if not self:canEditNetworkConfig(true) then return end
	self:sendCommand("requestConfigTransferProposal", {
		nodeId = nodeId, targetNodeId = targetNodeId,
		searchQuery = self.searchEntry and self.searchEntry:getText() or "",
	})
end

function GS_TerminalUI:onTransferNodeConfiguration(nodeId, transferToken)
	if not self:canEditNetworkConfig(true) then return end
	self:sendCommand("transferNodeConfiguration", {
		nodeId = nodeId, transferToken = transferToken,
		searchQuery = self.searchEntry and self.searchEntry:getText() or "",
	})
end

function GS_TerminalUI:onUpdateNode(nodeId, displayName, category, enabled, membership)
	if not self:canEditNetworkConfig(true) then return end
	local payload = {
		nodeId = nodeId,
		displayName = displayName,
		category = category or "",
		searchQuery = self.searchEntry and self.searchEntry:getText() or "",
	}
	if enabled ~= nil then
		payload.enabled = enabled
	end
	if membership ~= nil then
		payload.membership = membership
	end
	self:sendCommand("updateNode", payload)
end

function GS_TerminalUI:onRequestNodeContents(nodeId)
	self:sendCommand("getNodeContents", { nodeId = nodeId })
end

function GS_TerminalUI:onTransferOwnership(newOwner, keepFormer, characterId, username)
	self:sendCommand("transferOwnership", {
		newOwner = newOwner,
		characterId = characterId or "",
		username = username or "",
		keepFormerOwner = keepFormer == true,
		searchQuery = self.searchEntry and self.searchEntry:getText() or "",
	})
end

--- Refresca estado de recetas del mod en cliente.
function GS_TerminalUI:refreshCraftRecipesState()
	local player = GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer(self.playerNum) or nil
	if not player or not GlobalStorageSiK.TerminalRecipes then
		return
	end
	local ok, state = pcall(GlobalStorageSiK.TerminalRecipes.serializeForClient, player)
	if ok and state then
		self.craftRecipesState = state
	end
end

--- Refresca recetas de módulos addon para tarjetas craft en pestaña Addons.
function GS_TerminalUI:refreshAddonRecipesState()
	local player = GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer(self.playerNum) or nil
	if not player or not GlobalStorageSiK.AddonRecipes then
		return
	end
	local ok, state = pcall(GlobalStorageSiK.AddonRecipes.serializeAllForClient, player)
	if ok and state then
		self.addonRecipesState = state
	end
end

function GS_TerminalUI:onAddonsTabActivated()
	self:refreshAddonRecipesState()
	if self.addonsPanel then
		GlobalStorageSiK.TerminalAddons.refresh(self.addonsPanel, self)
	end
end

--- Craftea receta del mod (terminal / módulo addon).
---@param recipeId string
function GS_TerminalUI:onCraftModRecipe(recipeId)
	local player = GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer(self.playerNum)
		or (self.playerNum == 0 and getPlayer and getPlayer() or nil)
	if not player or not recipeId then
		return
	end
	local addonId = GlobalStorageSiK.AddonRecipes
		and GlobalStorageSiK.AddonRecipes.addonIdFromCardId
		and GlobalStorageSiK.AddonRecipes.addonIdFromCardId(recipeId)
	if addonId then
		if ISTimedActionQueue and ISTimedActionQueue.getTimedActionQueue then
			local queue = ISTimedActionQueue.getTimedActionQueue(player)
			if queue and queue.queue then
				for i = 1, #queue.queue do
					if queue.queue[i] and queue.queue[i].Type == "GS_CraftTerminalTimedAction" then
						return
					end
				end
			end
		end
		local def = GlobalStorageSiK.AddonRegistry.get(addonId)
		if not def or not GlobalStorageSiK.AddonRecipes.canCraftModule(player, def) then
			return
		end
		if not GS_CraftTerminalTimedAction then
			require "TimedActions/GS_CraftTerminalTimedAction"
		end
		if GS_CraftTerminalTimedAction then
			local craftTime = def.moduleCraftTime or 100
			ISTimedActionQueue.add(GS_CraftTerminalTimedAction:new(player, recipeId, craftTime))
		end
		return
	end
	local recipe = GlobalStorageSiK.TerminalRecipes.getById(recipeId)
	if not recipe then
		return
	end
	if ISTimedActionQueue and ISTimedActionQueue.getTimedActionQueue then
		local queue = ISTimedActionQueue.getTimedActionQueue(player)
		if queue and queue.queue then
			for i = 1, #queue.queue do
				if queue.queue[i] and queue.queue[i].Type == "GS_CraftTerminalTimedAction" then
					return
				end
			end
		end
	end
	local ok = GlobalStorageSiK.TerminalRecipes.canCraft(player, recipe)
	if not ok then
		return
	end
	if not GS_CraftTerminalTimedAction then
		require "TimedActions/GS_CraftTerminalTimedAction"
	end
	if GS_CraftTerminalTimedAction then
		ISTimedActionQueue.add(GS_CraftTerminalTimedAction:new(player, recipeId, recipe.time or 100))
	end
end

function GS_TerminalUI:onAddCategory(name)
	if not self:canEditNetworkConfig(true) then return end
	self:sendCommand("addCategory", {
		name = name or "",
		searchQuery = self.searchEntry and self.searchEntry:getText() or "",
	})
end

function GS_TerminalUI:onAddPermissionUser(characterName, characterId, factionUsername)
	self:sendCommand("addPermissionUser", {
		characterName = characterName or "",
		username = characterName or "",
		characterId = characterId or "",
		factionUsername = factionUsername or "",
		searchQuery = self.searchEntry and self.searchEntry:getText() or "",
	})
end

--- Boton "Reclamar propiedad" de la propia pestaña de admin (2026-08-23,
--- ver GlobalStorageSiK.Permissions.canAdminClaimOwnership): distinto del
--- boton de la pantalla de bloqueo (GS_TerminalUI_BlockedPanel.lua) - este
--- solo aparece para un admin que YA tiene acceso normal, cuando el
--- propietario lleva demasiado inactivo (o la red esta vacante). Sin
--- networkId explicito, igual que onAddPermissionUser - el servidor
--- resuelve la red desde la sesion activa del terminal ya abierto.
function GS_TerminalUI:onClaimAsAdmin()
	self:sendCommand("adminClaimOwnership", {
		searchQuery = self.searchEntry and self.searchEntry:getText() or "",
	})
end

function GS_TerminalUI:onAddMyFaction()
	local fname = ""
	if GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer then
		local fac = GlobalStorageSiK.Permissions.getPlayerFaction(
			GlobalStorageSiK.NetClient.getPlayer(self.playerNum))
		if fac and fac.getName then
			fname = fac:getName() or ""
		end
	end
	if fname ~= "" then
		self:onAddPermissionFaction(fname)
	end
end

function GS_TerminalUI:onAddFactionMembers()
	self:sendCommand("addFactionMembers", {
		searchQuery = self.searchEntry and self.searchEntry:getText() or "",
	})
end

function GS_TerminalUI:onAddPermissionFaction(factionName)
	self:sendCommand("addPermissionFaction", {
		factionName = factionName or "",
		searchQuery = self.searchEntry and self.searchEntry:getText() or "",
	})
end

function GS_TerminalUI:onRemovePermissionFaction(factionName)
	self:sendCommand("removePermissionFaction", {
		factionName = factionName or "",
		searchQuery = self.searchEntry and self.searchEntry:getText() or "",
	})
end

function GS_TerminalUI:onRenameNetwork(name)
	self:sendCommand("renameNetwork", {
		name = name or "",
		searchQuery = self.searchEntry and self.searchEntry:getText() or "",
	})
end

function GS_TerminalUI:onLeaveNetwork()
	self:sendCommand("leaveNetwork", {
		searchQuery = self.searchEntry and self.searchEntry:getText() or "",
	})
end

function GS_TerminalUI:onRemovePermissionUser(username, characterId)
	self:sendCommand("removePermissionUser", {
		username = username or "",
		characterId = characterId or "",
		searchQuery = self.searchEntry and self.searchEntry:getText() or "",
	})
end

function GS_TerminalUI:onSetMemberRole(username, role, characterId)
	self:sendCommand("setMemberRole", {
		username = username or "",
		characterId = characterId or "",
		role = role or "member",
		searchQuery = self.searchEntry and self.searchEntry:getText() or "",
	})
end

function GS_TerminalUI:onSetMemberZoneAccess(username, characterId, deniedZoneIds)
	self:sendCommand("setMemberZoneAccess", {
		username = username or "",
		characterId = characterId or "",
		deniedZoneIds = deniedZoneIds or {},
		searchQuery = self.searchEntry and self.searchEntry:getText() or "",
	})
end

function GlobalStorageSiK.TerminalUI:onToggleFactionOnly()
	local perms = self.terminalState and self.terminalState.permissions or {}
	self:sendCommand("setFactionOnly", {
		enabled = not (perms.factionOnly == true),
		searchQuery = self.searchEntry and self.searchEntry:getText() or "",
	})
end
