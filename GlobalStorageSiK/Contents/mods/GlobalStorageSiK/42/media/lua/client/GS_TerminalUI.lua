--[[
	GlobalStorageSiK - Terminal UI (NeatUI)
	Autor: SiK
	Fecha: 2025-06-24
]]

require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISLabel"
require "ISUI/ISTextEntryBox"
require "GS_TerminalUI_TabRail"
require "GS_TerminalUI_Tabs"
require "ISUI/ISComboBox"
require "GS_Config"
require "GS_Sandbox"
require "GS_I18n"
require "GS_ItemTaxonomy"
require "GS_Index"
require "GS_Libs"
require "GS_BulkFilters"
require "GS_NetClient"
require "GS_Permissions"
require "GS_TerminalUI_Chrome"
require "GS_TerminalUI_Scroll"
require "GS_TerminalUI_Sections"
require "GS_TerminalUI_Items"
require "GS_TerminalUI_Config"
require "GS_TerminalUI_Addons"
require "GS_TerminalUI_Extensions"
require "GS_TerminalUI_Programming"
require "GS_TerminalRecipes"
require "GS_TerminalUI_Network"
require "GS_TerminalUI_Nodes"
require "GS_TerminalUI_NodeEditor"
require "GS_TerminalDrop"
require "GS_WithdrawClient"
require "GS_TerminalUI_BlockedPanel"
require "GS_UIDebug"
require "GS_UILayout"

GlobalStorageSiK.TerminalUI = GlobalStorageSiK.TerminalUI or {}
GlobalStorageSiK.TerminalUI.instance = nil

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
local RESIZE_GRAB = 14

local function bottomInset()
	return GlobalStorageSiK.TerminalScroll.contentBottomInset()
end

--- Refresca contenido de la pestaña activa (carga diferida).
---@param self GS_TerminalUI
function GS_TerminalUI:refreshActiveTabContent()
	local state = self.terminalState or {}
	local tab = self.activeTabKey or "items"
	if tab == "items" then
		GlobalStorageSiK.TerminalItems.refresh(self.itemsListPanel, self, state.items or {})
	elseif tab == "network" then
		GlobalStorageSiK.TerminalNetwork.refreshScroll(self, state)
	elseif tab == "addons" and self.addonsPanel then
		GlobalStorageSiK.TerminalAddons.refresh(self.addonsPanel, self)
	elseif tab == "craft" and self.craftPanel and GlobalStorageSiK.TerminalCraft then
		GlobalStorageSiK.TerminalCraft.refresh(self.craftPanel, self)
	elseif tab == "blocked" and GlobalStorageSiK.TerminalBlockedPanel then
		GlobalStorageSiK.TerminalBlockedPanel.applyRefreshIfNeeded(self, true)
	elseif GlobalStorageSiK.TerminalExtensions then
		GlobalStorageSiK.TerminalExtensions.refreshActive(self, tab)
	end
end

local function createNeatButton(x, y, w, h, title, target, onClick)
	return GlobalStorageSiK.TerminalChrome.createNeatButton(x, y, w, h, title, target, onClick)
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

function GS_TerminalUI:new(x, y, width, height)
	local o = ISPanel:new(x, y, width, height)
	setmetatable(o, self)
	self.__index = self
	o.moveWithMouse = false
	o.padding = math.floor(FONT_HGT_SMALL * 0.55)
	o.headerHeight = math.floor(FONT_HGT_MEDIUM * 1.55)
	o.sideTabItemHeight = math.floor(FONT_HGT_MEDIUM * 1.45)
	o.sideTabGap = 4
	o.backgroundColor = { r = 0.06, g = 0.06, b = 0.06, a = 0.98 }
	o.borderColor = { r = 0, g = 0, b = 0, a = 1 }
	o.terminalState = nil
	o.minimumWidth = 900
	o.minimumHeight = 720
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

--- Arrastre por cabecera y redimensionado en esquina inferior derecha.
function GS_TerminalUI:installMouseHandlers()
	self.onMouseDown = function(me, x, y)
		if x >= me.width - RESIZE_GRAB and y >= me.height - RESIZE_GRAB then
			me.resizing = true
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
		if me.resizing then
			me.resizing = false
			me:setCapture(false)
			me:rebuildScrollContent()
			return true
		end
		if me.moving then
			me.moving = false
			me:setCapture(false)
			return true
		end
		return ISPanel.onMouseUp(me, x, y)
	end
	self.onMouseUpOutside = function(me, x, y)
		if me.resizing then
			me.resizing = false
			me:setCapture(false)
			me:rebuildScrollContent()
			return true
		end
		if me.moving then
			me.moving = false
			me:setCapture(false)
			return true
		end
		return ISPanel.onMouseUpOutside(me, x, y)
	end
	self.onMouseMove = function(me, dx, dy)
		if me.resizing then
			me:setWidth(math.max(me.minimumWidth, me.width + dx))
			me:setHeight(math.max(me.minimumHeight, me.height + dy))
			me:calculateLayout()
			if me.activeTabKey == "network" then
				GlobalStorageSiK.TerminalNetwork.syncScrollLayout(me)
			elseif me.activeTabKey == "addons" and me.addonsPanel then
				GlobalStorageSiK.TerminalAddons.syncScrollLayout(me.addonsPanel, me)
			end
			GlobalStorageSiK.TerminalScroll.stripTerminalTree(me)
			if me.activeTabKey == "items" and me.itemsListPanel and GlobalStorageSiK.TerminalItems.syncLayout then
				GlobalStorageSiK.TerminalItems.syncLayout(me.itemsListPanel, me)
			end
			return true
		end
		if me.moving then
			me:setX(me.x + dx)
			me:setY(me.y + dy)
			return true
		end
		return ISPanel.onMouseMove(me, dx, dy)
	end
	self.onMouseMoveOutside = function(me, dx, dy)
		if me.resizing then
			me:setWidth(math.max(me.minimumWidth, me.width + dx))
			me:setHeight(math.max(me.minimumHeight, me.height + dy))
			me:calculateLayout()
			if me.activeTabKey == "network" then
				GlobalStorageSiK.TerminalNetwork.syncScrollLayout(me)
			elseif me.activeTabKey == "addons" and me.addonsPanel then
				GlobalStorageSiK.TerminalAddons.syncScrollLayout(me.addonsPanel, me)
			end
			GlobalStorageSiK.TerminalScroll.stripTerminalTree(me)
			return true
		end
		if me.moving then
			me:setX(me.x + dx)
			me:setY(me.y + dy)
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
	GlobalStorageSiK.TerminalNetwork.buildZonesSection(self, self.networkPanel)

	self.itemsPanel = createTabPanel()
	self:buildItemsToolbar()

	self.addonsPanel = createTabPanel()
	GlobalStorageSiK.TerminalAddons.buildPanel(self.addonsPanel, self)

	self.blockedPanel = createTabPanel()
	GlobalStorageSiK.TerminalBlockedPanel.build(self)

	local tabDefs = {
		{ key = "items", titleKey = "IGUI_GS_TabWarehouse", panelField = "itemsPanel", iconPath = "media/ui/GS/GS_TabWarehouse.png" },
		{ key = "network", titleKey = "IGUI_GS_TabNetwork", panelField = "networkPanel", iconPath = "media/ui/GS/GS_TabNetwork.png" },
	}
	self.footerTabDef = {
		key = "addons",
		titleKey = "IGUI_GS_TabAddons",
		panelField = "addonsPanel",
		iconPath = "media/ui/GS/GS_TabAddons.png",
	}
	GlobalStorageSiK.TerminalTabs.build(self, tabDefs)
	self.tabViews.blocked = self.blockedPanel

	self.closeBtn = GlobalStorageSiK.TerminalChrome.createCloseButton(self, self, GS_TerminalUI.onClose)

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
	local rowH = FONT_HGT_SMALL + 8
	local btnW = GlobalStorageSiK.TerminalChrome.measureNeatButtonWidth(T("IGUI_GS_Search"), UIFont.Small, 16, 56, 120)
	local gap = 6
	local y = pad

	self.itemsTitleLbl = GlobalStorageSiK.TerminalSections.addTitleLabel(
		self.itemsPanel, pad, y, "IGUI_GS_SectionItems"
	)
	-- La accion conserva siempre la misma etiqueta. El estado y el resumen del
	-- job viven en una fila separada para no truncar mensajes dentro del boton.
	self.autoSortBtn = createNeatButton(0, y, 220, FONT_HGT_SMALL + 8, T("IGUI_GS_Redistribute"), self, GS_TerminalUI.onRedistributeNetwork)
	self.itemsPanel:addChild(self.autoSortBtn)
	-- Hasta recibir el rol serializado por el servidor no se permite iniciar
	-- una operación sensible. updateState lo habilita solo para owner/admin.
	self.autoSortBtn:setEnable(false)
	if self.autoSortBtn.setTooltip then
		self.autoSortBtn:setTooltip(T("IGUI_GS_RedistributeHint"))
	end
	y = y + FONT_HGT_SMALL + gap

	local statusH = FONT_HGT_SMALL + 6
	self.autoSortStatusRow = GlobalStorageSiK.TerminalChrome.createStatusIndicatorRow(pad, y, 320, statusH)
	self.autoSortStatusRow.drawBackground = true
	self.autoSortStatusRow.backgroundColor = { r = 0.075, g = 0.075, b = 0.09, a = 0.8 }
	self.autoSortStatusRow.borderColor = { r = 0.18, g = 0.18, b = 0.22, a = 0.9 }
	GlobalStorageSiK.TerminalChrome.setStatusIndicatorRow(
		self.autoSortStatusRow, T("IGUI_GS_RedistributeIdle"), "muted", 320
	)
	self.itemsPanel:addChild(self.autoSortStatusRow)
	y = y + statusH + gap

	local _wpal = GlobalStorageSiK.TerminalChrome.PALETTE
	self.itemsWeightLbl = ISLabel:new(pad, y, FONT_HGT_SMALL, T("IGUI_GS_WeightUsage", "0.0", "0.0", "0"), _wpal.statusOk[1], _wpal.statusOk[2], _wpal.statusOk[3], 1, UIFont.Small, true)
	self.itemsWeightLbl:initialise()
	self.itemsPanel:addChild(self.itemsWeightLbl)
	y = y + FONT_HGT_SMALL + gap

	local _dpal = GlobalStorageSiK.TerminalChrome.PALETTE
	self.depositDropHint = ISLabel:new(pad, y, FONT_HGT_SMALL * 2, T("IGUI_GS_DropHint"), _dpal.textMuted[1], _dpal.textMuted[2], _dpal.textMuted[3], 1, UIFont.Small, true)
	self.depositDropHint:initialise()
	self.itemsPanel:addChild(self.depositDropHint)
	y = y + FONT_HGT_SMALL + gap

	local searchW = 220
	local searchBox, searchEntry = GlobalStorageSiK.TerminalChrome.createNeatSearchBox(pad, y, searchW, rowH, self.itemsPanel, nil)
	self.itemsPanel:addChild(searchBox)
	self.searchBox = searchBox
	self.searchEntry = searchEntry
	GlobalStorageSiK.TerminalChrome.bindSearchEntry(self, self.searchEntry)

	local function styleFilterCombo(combo)
		GlobalStorageSiK.TerminalChrome.styleComboBox(combo)
		combo:instantiate()
		combo.filterKeys = { "" }
		if combo.bringToTop then
			combo:bringToTop()
		end
	end

	self.mainCategoryFilterCombo = ISComboBox:new(0, y - 2, 140, rowH)
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

	self.subCategoryFilterCombo = ISComboBox:new(0, y - 2, 140, rowH)
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

	self.leafCategoryFilterCombo = ISComboBox:new(0, y - 2, 140, rowH)
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

	self.searchBtn = createNeatButton(0, y, 120, rowH, T("IGUI_GS_Search"), self, GS_TerminalUI.onSearch)
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
	local closeSize = math.max(FONT_HGT_MEDIUM, 24)

	if self.closeBtn then
		local closeSize = math.max(FONT_HGT_MEDIUM, 24)
		self.closeBtn:setX(w - closeSize - pad)
		self.closeBtn:setY(math.floor((self.headerHeight - closeSize) / 2))
		self.closeBtn:setWidth(closeSize)
		self.closeBtn:setHeight(closeSize)
		self.closeBtn:setVisible(true)
		self.closeBtn:bringToTop()
	end

	local tabY = self.headerHeight
	local bodyH = math.max(160, h - tabY - pad - bottomInset())
	local railW = GlobalStorageSiK.TerminalTabs.measureRailWidth(self)
	local railGap = 4
	local contentPad = pad
	local contentW = math.max(240, w - contentPad - railW - railGap)

	local blockedMode = self.accessMode == "blocked"
	if self.tabRail then
		self.tabRail:setVisible(not blockedMode)
		self.tabRail:setX(0)
		self.tabRail:setY(tabY)
		self.tabRail:setWidth(railW)
		self.tabRail:setHeight(bodyH)
		if not blockedMode then
			GlobalStorageSiK.TerminalTabs.layoutRail(self)
		end
	end
	if self.contentHost then
		if blockedMode then
			self.contentHost:setX(contentPad)
			self.contentHost:setY(tabY)
			self.contentHost:setWidth(math.max(240, w - contentPad * 2))
			self.contentHost:setHeight(bodyH)
		else
			self.contentHost:setX(railW + railGap)
			self.contentHost:setY(tabY)
			self.contentHost:setWidth(contentW)
			self.contentHost:setHeight(bodyH)
		end
	end

	local innerW = blockedMode and math.max(240, w - contentPad * 2) or contentW
	local innerH = bodyH

	local tabPanels = { self.networkPanel, self.itemsPanel, self.addonsPanel, self.craftPanel, self.blockedPanel }
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

	if self.blockedPanel and GlobalStorageSiK.TerminalBlockedPanel then
		GlobalStorageSiK.TerminalBlockedPanel.layout(self, innerW, innerH)
	end

	GlobalStorageSiK.TerminalNetwork.layout(self, innerW, innerH)

	if self.itemsListPanel and self.itemsPanel then
		local searchLabel = T("IGUI_GS_Search")
		local rowH = FONT_HGT_SMALL + 8
		local gap = 6
		local hintH = FONT_HGT_SMALL * 2
		local statusH = FONT_HGT_SMALL + 6
		local contentW = innerW - pad * 2

		-- Anchos de la fila de búsqueda (idénticos al cálculo previo).
		local btnW = GlobalStorageSiK.TerminalChrome.measureNeatButtonWidth(searchLabel, UIFont.Small, 16, 56, 120)
		if self.searchBtn then
			GlobalStorageSiK.TerminalChrome.fitNeatButtonToLabel(self.searchBtn)
			btnW = self.searchBtn.width
		end
		-- 3 desplegables (Categoria/Subcategoria/Sub-subcategoria) en vez de
		-- 2: cada uno mas estrecho para que quepan los 3 + buscador + boton.
		local filterW = math.max(90, math.floor(contentW * 0.15))
		local searchW = math.max(80, contentW - btnW - gap * 4 - filterW * 3)
		if self.searchBox then
			GlobalStorageSiK.TerminalChrome.layoutNeatSearchBox(self.searchBox, searchW, rowH)
		end
		local searchWidget = self.searchBox or self.searchEntry

		-- Stack vertical de bloques: cada uno reserva su altura, ancho = contentW,
		-- la lista ocupa el resto. Reescala completo en cada pasada (resize).
		local col = GlobalStorageSiK.UILayout.column{
			x = pad, y = pad, width = contentW, bottom = innerH - pad, gap = gap,
		}
		col:place(self.itemsTitleLbl, FONT_HGT_SMALL)   -- título (solo x/y)
		if self.autoSortBtn then
			GlobalStorageSiK.TerminalChrome.fitNeatButtonToLabel(self.autoSortBtn)
			self.autoSortBtn:setX(pad + contentW - self.autoSortBtn.width)
			self.autoSortBtn:setY(pad)
		end
		col:place(self.autoSortStatusRow, statusH)
		col:label(self.itemsWeightLbl, FONT_HGT_SMALL)  -- peso (x/y/width)
		col:label(self.depositDropHint, hintH)          -- hint (x/y/width)
		col:row(rowH, {
			{ widget = searchWidget,                w = searchW },
			{ widget = self.mainCategoryFilterCombo, w = filterW, yoffset = -2 },
			{ widget = self.subCategoryFilterCombo,  w = filterW, yoffset = -2 },
			{ widget = self.leafCategoryFilterCombo, w = filterW, yoffset = -2 },
			{ widget = self.searchBtn,               w = btnW },
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
			self.itemsListPanel.columnHeader:setWidth(self.itemsListPanel.width)
		end
	end

	if self.addonsPanel then
		GlobalStorageSiK.TerminalAddons.layout(self.addonsPanel, innerW, innerH)
	end
	if self.craftPanel and GlobalStorageSiK.TerminalCraft then
		GlobalStorageSiK.TerminalCraft.layout(self.craftPanel, innerW, innerH)
	end
	if GlobalStorageSiK.TerminalExtensions then
		GlobalStorageSiK.TerminalExtensions.layoutAll(self, innerW, innerH)
	end
	GlobalStorageSiK.TerminalScroll.applyTabScrollVisibility(self)
	if GlobalStorageSiK.TerminalTabs and GlobalStorageSiK.TerminalTabs.syncBlockedChrome then
		GlobalStorageSiK.TerminalTabs.syncBlockedChrome(self)
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
	elseif tab == "addons" and self.addonsPanel then
		GlobalStorageSiK.TerminalAddons.syncScrollLayout(self.addonsPanel, self)
	elseif tab == "items" and self.itemsListPanel then
		GlobalStorageSiK.TerminalItems.syncLayout(self.itemsListPanel, self)
	else
		self:refreshActiveTabContent()
	end
	GlobalStorageSiK.TerminalScroll.stripTerminalTree(self)
	-- Verificación tras redimensionar: ningún elemento debe pisar a otro.
	-- Cubre CUALQUIER pestaña activa (no solo bloqueo) - sandbox DebugModeUI,
	-- desactivado no cuesta nada ni genera ruido.
	if GlobalStorageSiK.UIDebug and GlobalStorageSiK.UIDebug.enabled and GlobalStorageSiK.UIDebug.enabled() then
		GlobalStorageSiK.UIDebug.dumpTree(self, "resize->" .. tostring(self.activeTabKey))
		GlobalStorageSiK.UIDebug.checkOverlaps(self, "resize->" .. tostring(self.activeTabKey))
	end
end

function GS_TerminalUI:prerender()
	ISPanel.prerender(self)
	GlobalStorageSiK.TerminalChrome.renderPanelBackground(self)
	if self.accessMode == "blocked" then
		GlobalStorageSiK.TerminalChrome.renderBlockedHeader(self)
	else
		GlobalStorageSiK.TerminalChrome.renderHeader(self)
	end
	if GlobalStorageSiK.TerminalTabs and GlobalStorageSiK.TerminalTabs.syncBlockedChrome then
		GlobalStorageSiK.TerminalTabs.syncBlockedChrome(self)
	end
end

function GS_TerminalUI:applyCapacityState(cap)
	if not cap then
		return
	end
	local used = string.format("%.1f", tonumber(cap.usedWeight) or 0)
	local total = string.format("%.1f", tonumber(cap.totalCapacity) or 0)
	local pct = tonumber(cap.percent) or 0
	local status = cap.status or "ok"
	local pal = GlobalStorageSiK.TerminalChrome.PALETTE
	local r, g, b = pal.statusOk[1], pal.statusOk[2], pal.statusOk[3]
	if status == "warning" then
		r, g, b = pal.statusWarn[1], pal.statusWarn[2], pal.statusWarn[3]
	elseif status == "critical" or status == "full" then
		r, g, b = pal.statusDanger[1], pal.statusDanger[2], pal.statusDanger[3]
	end

	local pctText = tostring(pct) .. "%"
	local weightText
	if (cap.totalCapacity or 0) > 0 then
		weightText = T("IGUI_GS_WeightUsage", used, total, pctText)
	else
		weightText = T("IGUI_GS_WeightUsedOnly", used)
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
			local copy = {}
			for i = 1, #state.items do
				local row = state.items[i]
				if row then
					copy[i] = {
						fullType = row.fullType,
						displayName = row.displayName,
						worldSprite = row.worldSprite,
						category = row.category,
						subCategory = row.subCategory,
						count = row.count,
						nodeId = row.nodeId,
						gsSubKeysStr = row.gsSubKeysStr,
						gsSubKeys = row.gsSubKeys,
					}
				end
			end
			merged.items = copy
		end
		state = merged
	end
	if state and state.items then
		local copy = {}
		for i = 1, #state.items do
			local row = state.items[i]
			if row then
				copy[i] = {
					fullType = row.fullType,
					displayName = row.displayName,
					worldSprite = row.worldSprite,
					category = row.category,
					subCategory = row.subCategory,
					count = row.count,
					nodeId = row.nodeId,
					gsSubKeysStr = row.gsSubKeysStr,
					gsSubKeys = row.gsSubKeys,
				}
			end
		end
		state.items = copy
	end
	self.terminalState = state or prev
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
			local player = GlobalStorageSiK.NetClient.getPlayer()
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
	elseif tab == "addons" and self.addonsPanel then
		GlobalStorageSiK.TerminalAddons.refresh(self.addonsPanel, self)
	elseif tab == "craft" and self.craftPanel and GlobalStorageSiK.TerminalCraft then
		GlobalStorageSiK.TerminalCraft.refresh(self.craftPanel, self)
	elseif GlobalStorageSiK.TerminalExtensions then
		GlobalStorageSiK.TerminalExtensions.refreshActive(self, tab)
	end
	-- Programación va ANTES que Craft/Build para que, si el periférico Reader
	-- ya está instalado cuando el terminal abre por primera vez, su pestaña
	-- reclame su hueco en self.dynamicSlots (append-only, ver
	-- GS_TerminalTabRail:setCraftTabVisible) antes que ellas.
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
	if GlobalStorageSiK.UIDebug then GlobalStorageSiK.UIDebug.log("OPEN", "onClose()") end
	if GlobalStorageSiK.TerminalBlockedUI and GlobalStorageSiK.TerminalBlockedUI.instance == self then
		GlobalStorageSiK.TerminalBlockedUI.instance = nil
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
	local player = GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer and GlobalStorageSiK.NetClient.getPlayer()
	-- El servidor mantiene una lista explicita de clientes que estan mirando
	-- cada terminal para no difundirles indices completos solo por tener acceso
	-- a la red. Notificar el cierre antes de borrar la sesion local.
	if player and GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.sendCommand then
		GlobalStorageSiK.NetClient.sendCommand("closeTerminal", {
			networkId = self.terminalState and self.terminalState.networkId or nil,
		})
	end
	if player and GlobalStorageSiK.TerminalAccess and GlobalStorageSiK.TerminalAccess.clearSession then
		GlobalStorageSiK.TerminalAccess.clearSession(player)
	end
	if GlobalStorageSiK.TransferQueue and GlobalStorageSiK.TransferQueue.clear then
		GlobalStorageSiK.TransferQueue.clear()
	end
	self:setVisible(false)
	self:removeFromUIManager()
	self._capacityHaloShown = nil
	GlobalStorageSiK.TerminalUI.instance = nil
	if GlobalStorageSiK.TerminalUI._liveInstances then
		GlobalStorageSiK.TerminalUI._liveInstances[self] = nil
	end
end

function GS_TerminalUI:onCreateStructureZone()
	if not self:canEditNetworkConfig(true) then return end
	GlobalStorageSiK.NetClient.sendCommand("createZoneStructure", {})
end

function GS_TerminalUI:onCreateRoomZone()
	if not self:canEditNetworkConfig(true) then return end
	GlobalStorageSiK.NetClient.sendCommand("createZoneRoom", {})
end

function GS_TerminalUI:onCreateSafehouseZone()
	if not self:canEditNetworkConfig(true) then return end
	GlobalStorageSiK.NetClient.sendCommand("createZoneSafehouse", {})
end

function GS_TerminalUI:onCreateSelectionZone()
	if not self:canEditNetworkConfig(true) then return end
	if GlobalStorageSiK.ZonePicker then
		GlobalStorageSiK.ZonePicker.start(self)
	end
end

function GS_TerminalUI:onCreateBuildingZone()
	if not self:canEditNetworkConfig(true) then return end
	GlobalStorageSiK.NetClient.sendCommand("createZoneBuilding", {})
end

function GS_TerminalUI:onRescanZone(zoneId)
	if not self:canEditNetworkConfig(true) then return end
	GlobalStorageSiK.NetClient.sendCommand("rescanZone", {
		zoneId = zoneId,
		searchQuery = self.searchEntry and self.searchEntry:getText() or "",
	})
end

function GS_TerminalUI:onRescanNetwork()
	if not self:canEditNetworkConfig(true) then return end
	GlobalStorageSiK.NetClient.sendCommand("rescanNetwork", {
		searchQuery = self:getSearchQuery(),
	})
end

function GS_TerminalUI:onRequestOpen()
	local player = GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer() or getPlayer()
	local payload = GlobalStorageSiK.TerminalAccess.enrichCommandPayload(player, {
		searchQuery = self:getSearchQuery(),
	}, GlobalStorageSiK.Client and GlobalStorageSiK.Client.activeNetworkId)
	GlobalStorageSiK.NetClient.sendCommand("openTerminal", payload)
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
		self.autoSortBtn._gsNeatLabel = T("IGUI_GS_Redistribute")
		self.autoSortBtn.textColor = nil
		local allowed = self:canUseAutoSort()
		self.autoSortBtn:setEnable(not self._autoSortRunning and allowed)
		if self.autoSortBtn.setTooltip then
			self.autoSortBtn:setTooltip(allowed
				and T("IGUI_GS_RedistributeHint")
				or T("IGUI_GS_RedistributeAdminOnly"))
		end
	end
	GlobalStorageSiK.TerminalChrome.setStatusIndicatorRow(
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
			and GlobalStorageSiK.NetClient.getPlayer() or nil
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
			and GlobalStorageSiK.NetClient.getPlayer() or nil
		if player and player.setHaloNote then
			player:setHaloNote(T("IGUI_GS_RedistributeAdminOnly"), 255, 190, 70, 420)
		end
		return
	end
	self:setRedistributeState(true, T("IGUI_GS_RedistributingNetwork"), "warn")
	GlobalStorageSiK.NetClient.sendCommand("redistributeNetwork", {
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
	if q == "" or (#q < 3 and not self._searchForceApply) then
		return rows
	end
	if isClient and isClient() and GlobalStorageSiK.I18n.filterItemRows then
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

--- Rellena el combo de categorías principales a partir del catálogo actual.
---@param allItems table[]
function GS_TerminalUI:rebuildMainCategoryFilterCombo(allItems)
	local combo = self.mainCategoryFilterCombo
	if not combo then
		return
	end
	local prevKey = self:getMainCategoryFilterKey()
	local filters = GlobalStorageSiK.TerminalItems.collectMainCategoryFilters(allItems or {})
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
	local prevKey = self:getSubCategoryFilterKey()
	local mainKey = self:getMainCategoryFilterKey()
	local filters = GlobalStorageSiK.TerminalItems.collectSubCategoryFilters(allItems or {}, mainKey)
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
	local prevKey = self:getLeafCategoryFilterKey()
	local mainKey = self:getMainCategoryFilterKey()
	local subKey = self:getSubCategoryFilterKey()
	local filters = GlobalStorageSiK.TerminalItems.collectLeafCategoryFilters(allItems or {}, mainKey, subKey)
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
function GS_TerminalUI:refreshItemsTab()
	if not self.itemsListPanel then
		return
	end
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
	GlobalStorageSiK.NetClient.sendCommand("moveZonePriority", {
		zoneId = zoneId,
		direction = direction,
		searchQuery = self:getSearchQuery(),
	})
end

function GS_TerminalUI:onSetZonePriority(zoneId, priority)
	if not self:canEditNetworkConfig(true) then return end
	GlobalStorageSiK.NetClient.sendCommand("setZonePriority", {
		zoneId = zoneId,
		priority = priority,
		searchQuery = self.searchEntry and self.searchEntry:getText() or "",
	})
end

function GS_TerminalUI:onRenameZone(zoneId, name)
	if not self:canEditNetworkConfig(true) then return end
	GlobalStorageSiK.NetClient.sendCommand("renameZone", {
		zoneId = zoneId,
		name = name,
		searchQuery = self.searchEntry and self.searchEntry:getText() or "",
	})
end

function GS_TerminalUI:onDeleteZone(zoneId)
	if not self:canEditNetworkConfig(true) then return end
	GlobalStorageSiK.NetClient.sendCommand("deleteZone", {
		zoneId = zoneId,
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
	GlobalStorageSiK.NetClient.sendCommand("updateNode", payload)
end

function GS_TerminalUI:onRequestNodeContents(nodeId)
	GlobalStorageSiK.NetClient.sendCommand("getNodeContents", { nodeId = nodeId })
end

function GS_TerminalUI:onTransferOwnership(newOwner, keepFormer, characterId)
	GlobalStorageSiK.NetClient.sendCommand("transferOwnership", {
		newOwner = newOwner,
		characterId = characterId or "",
		keepFormerOwner = keepFormer == true,
		searchQuery = self.searchEntry and self.searchEntry:getText() or "",
	})
end

--- Refresca estado de recetas del mod en cliente.
function GS_TerminalUI:refreshCraftRecipesState()
	local player = GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer() or nil
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
	local player = GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer() or nil
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
	local player = GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer() or getPlayer()
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
	GlobalStorageSiK.NetClient.sendCommand("addCategory", {
		name = name or "",
		searchQuery = self.searchEntry and self.searchEntry:getText() or "",
	})
end

function GS_TerminalUI:onAddPermissionUser(characterName, characterId, factionUsername)
	GlobalStorageSiK.NetClient.sendCommand("addPermissionUser", {
		characterName = characterName or "",
		username = characterName or "",
		characterId = characterId or "",
		factionUsername = factionUsername or "",
		searchQuery = self.searchEntry and self.searchEntry:getText() or "",
	})
end

function GS_TerminalUI:onAddMyFaction()
	local fname = ""
	if GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer then
		local fac = GlobalStorageSiK.Permissions.getPlayerFaction(GlobalStorageSiK.NetClient.getPlayer())
		if fac and fac.getName then
			fname = fac:getName() or ""
		end
	end
	if fname ~= "" then
		self:onAddPermissionFaction(fname)
	end
end

function GS_TerminalUI:onAddFactionMembers()
	GlobalStorageSiK.NetClient.sendCommand("addFactionMembers", {
		searchQuery = self.searchEntry and self.searchEntry:getText() or "",
	})
end

function GS_TerminalUI:onAddPermissionFaction(factionName)
	GlobalStorageSiK.NetClient.sendCommand("addPermissionFaction", {
		factionName = factionName or "",
		searchQuery = self.searchEntry and self.searchEntry:getText() or "",
	})
end

function GS_TerminalUI:onRemovePermissionFaction(factionName)
	GlobalStorageSiK.NetClient.sendCommand("removePermissionFaction", {
		factionName = factionName or "",
		searchQuery = self.searchEntry and self.searchEntry:getText() or "",
	})
end

function GS_TerminalUI:onRenameNetwork(name)
	GlobalStorageSiK.NetClient.sendCommand("renameNetwork", {
		name = name or "",
		searchQuery = self.searchEntry and self.searchEntry:getText() or "",
	})
end

function GS_TerminalUI:onLeaveNetwork()
	GlobalStorageSiK.NetClient.sendCommand("leaveNetwork", {
		searchQuery = self.searchEntry and self.searchEntry:getText() or "",
	})
end

function GS_TerminalUI:onRemovePermissionUser(username, characterId)
	GlobalStorageSiK.NetClient.sendCommand("removePermissionUser", {
		username = username or "",
		characterId = characterId or "",
		searchQuery = self.searchEntry and self.searchEntry:getText() or "",
	})
end

function GS_TerminalUI:onSetMemberRole(username, role, characterId)
	GlobalStorageSiK.NetClient.sendCommand("setMemberRole", {
		username = username or "",
		characterId = characterId or "",
		role = role or "member",
		searchQuery = self.searchEntry and self.searchEntry:getText() or "",
	})
end

function GS_TerminalUI:onSetMemberZoneAccess(username, characterId, deniedZoneIds)
	GlobalStorageSiK.NetClient.sendCommand("setMemberZoneAccess", {
		username = username or "",
		characterId = characterId or "",
		deniedZoneIds = deniedZoneIds or {},
		searchQuery = self.searchEntry and self.searchEntry:getText() or "",
	})
end

function GlobalStorageSiK.TerminalUI:onToggleFactionOnly()
	local perms = self.terminalState and self.terminalState.permissions or {}
	GlobalStorageSiK.NetClient.sendCommand("setFactionOnly", {
		enabled = not (perms.factionOnly == true),
		searchQuery = self.searchEntry and self.searchEntry:getText() or "",
	})
end

-- ===========================================================================
-- Escape cierra nuestro terminal cuando cierra la ventana de crafteo/
-- construccion (vanilla o Neat) delante de el (pedido explicito en UX: "al
-- cerrar el panel de crafteo/construccion con Escape, nuestro terminal se
-- queda abierto por detras"). Nuestro terminal NO se oculta mientras esas
-- ventanas estan abiertas (por diseno, ver GS_NetworkCraftSession.onTick -
-- la sesion de red sigue viva independientemente de si la ventana esta
-- tecnicamente abierta), asi que Escape solo actuaba sobre la ventana de
-- crafteo/construccion, dejando la nuestra visible detras.
--
-- Implementacion deliberadamente NO invasiva: no se sobreescribe el manejo
-- de Escape de ISHandcraftWindow/ISBuildWindow (vanilla o Neat, desconocido
-- desde aqui) - solo se observa. Al pulsar Escape con nuestro terminal
-- visible y una de esas ventanas abierta, se vigila un margen corto de
-- ticks; si esa ventana se cierra de verdad en ese margen (la cerro Escape,
-- no otra cosa), se cierra tambien nuestro terminal. Si no se cierra
-- (Escape lo consumio un dialogo anidado, o no era esa ventana), no pasa
-- nada - falla seguro, no interfiere con ningun otro flujo.
-- ===========================================================================
local _escCloseWatchPlayerNum = nil
local _escCloseWatchTicks = 0
local ESC_CLOSE_WATCH_MAX_TICKS = 15

local function craftOrBuildWindowOpen(playerNum)
	if not ISEntityUI or not ISEntityUI.IsWindowOpen then
		return false
	end
	return ISEntityUI.IsWindowOpen(playerNum, "HandcraftWindow") ~= nil
		or ISEntityUI.IsWindowOpen(playerNum, "BuildWindow") ~= nil
end

if Events and Events.OnKeyStartPressed then
	Events.OnKeyStartPressed.Add(function(key)
		if key ~= Keyboard.KEY_ESCAPE then
			return
		end
		local ui = GlobalStorageSiK.TerminalUI.instance
		if not ui or not ui.getIsVisible or not ui:isVisible() then
			return
		end
		local player = GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer() or getPlayer()
		if not player or not player.getPlayerNum then
			return
		end
		local playerNum = player:getPlayerNum()
		if craftOrBuildWindowOpen(playerNum) then
			_escCloseWatchPlayerNum = playerNum
			_escCloseWatchTicks = 0
		end
	end)
end

if Events and Events.OnTick then
	Events.OnTick.Add(function()
		if not _escCloseWatchPlayerNum then
			return
		end
		_escCloseWatchTicks = _escCloseWatchTicks + 1
		if not craftOrBuildWindowOpen(_escCloseWatchPlayerNum) then
			local ui = GlobalStorageSiK.TerminalUI.instance
			if ui and ui.onClose then
				ui:onClose()
			end
			_escCloseWatchPlayerNum = nil
			return
		end
		if _escCloseWatchTicks > ESC_CLOSE_WATCH_MAX_TICKS then
			_escCloseWatchPlayerNum = nil
		end
	end)
end
