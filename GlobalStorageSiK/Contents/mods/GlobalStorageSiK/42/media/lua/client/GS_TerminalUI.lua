--[[
	GlobalStorageSiK - Terminal UI (SiK UI)
	Autor: SiK
	Fecha: 2025-06-24
]]

require "GS_TerminalUI_Tabs"
require "GS_Config"
require "GS_Sandbox"
require "GS_I18n"
require "GS_Log"
require "GS_UI_Feedback"
require "GS_UI_PalettePreference"
require "GS_Index"
require "GS_Libs"
require "GS_BulkFilters"
require "GS_NetClient"
require "GS_Permissions"
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
require "GSSiK_API"

local UI = require "GS_UI_Framework"
local Loading = require "GS_TerminalLoading"
local CapacityPresentation = require "GlobalStorageSiK/UI/CapacityPresentation"

GlobalStorageSiK.TerminalUI = GlobalStorageSiK.TerminalUI or {}
GlobalStorageSiK.TerminalUI.instances = GlobalStorageSiK.TerminalUI.instances or {}

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
		local rev, navigationContainer = {}, ui.navigationContainer
		if ui.tabPanels then for k, p in pairs(ui.tabPanels) do rev[p] = k end end
		local list, visCount, hostCount = {}, 0, 0
		if navigationContainer and ui.tabPanels then
			for key in pairs(ui.tabPanels) do
				hostCount = hostCount + 1
				local host = navigationContainer:getContentHost(key)
				if host and host.panel then
				local hostList, hostVisible = gsCountVisibleChildren(host.panel, rev)
				if host.panel:isVisible() then visCount = visCount + hostVisible end
				for index = 1, #hostList do list[#list + 1] = key .. "/" .. hostList[index] end
				end
			end
		end
		GlobalStorageSiK.UIDebug.log("DIAG", "   navigation hosts=%d paneles-visibles=%d [%s]",
			hostCount, visCount, table.concat(list, ", "))
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

GS_TerminalUI = UI.Window.derive("GS_TerminalUI")

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

local function resolveConnectionPresentation(state)
	state = state or {}
	if state.networkId == nil or tostring(state.networkId) == "" then
		return T("IGUI_GS_AccessTerminalUnlinked"), "danger"
	end
	if state.powered == false then
		return T("IGUI_GS_HeaderNoPower"), "warning"
	end
	return T("IGUI_GS_Connected"), "success"
end

local function operationProgress(done, total)
	done, total = tonumber(done) or 0, tonumber(total) or 0
	if total <= 0 then return nil, "indeterminate" end
	return math.min(1, math.max(0, done / total)), "determinate"
end

local function operationLabel(key, done, total, asPercent)
	local label = T(key)
	done, total = tonumber(done) or 0, tonumber(total) or 0
	if total <= 0 then return label end
	if asPercent then
		return label .. " " .. tostring(math.floor((done / total) * 100 + 0.5)) .. "%"
	end
	return label .. " " .. tostring(math.floor(done)) .. "/" .. tostring(math.floor(total))
end

local function buildHeaderSpec(state, activeOperation, load)
	state = state or {}
	local networkTitle = state.networkName
	if type(networkTitle) ~= "string" or networkTitle == "" then
		if state.networkId ~= nil and tostring(state.networkId) ~= "" then
			networkTitle = tostring(state.networkId)
		else
			networkTitle = nil
		end
	end
	local statusLabel, statusTone = resolveConnectionPresentation(state)
	local operation = false
	local transient = state.headerTransient
	if activeOperation then
		operation = activeOperation
		if activeOperation.showProgress == true then
			statusLabel, statusTone = T("IGUI_GS_UpdatingInventory"), "warning"
		end
	elseif type(transient) == "table" then
		operation = {
			label = transient.label or transient.text or "",
			showProgress = false,
			value = transient.value or 1, mode = transient.mode or "determinate",
			status = transient.status or transient.tone or "warning",
			tone = transient.tone or transient.status or "warning",
		}
	elseif tonumber(state.inventoryRevision)
		and tonumber(state._gsAppliedCatalogRevision)
		and state.inventoryRevision > state._gsAppliedCatalogRevision then
		statusLabel, statusTone = T("IGUI_GS_UpdatingInventory"), "warning"
		operation = {label="", value=nil, mode="indeterminate",
			status="warning", tone="warning", showProgress=true}
	elseif state.redistributeActive == true then
		statusLabel, statusTone = T("IGUI_GS_RedistributeRunning"), "warning"
		local progress = state.redistributeProgress or {}
		local value, mode = operationProgress(progress.checked, progress.total)
		operation = {
			label = operationLabel("IGUI_GS_RedistributeRunning",
				progress.checked, progress.total, true), value = value, mode = mode,
			status = "warning", tone = "warning", showProgress = true,
		}
	elseif state.scanActive == true or state.reconcilePending == true
		or (state.scanStatus and (state.scanStatus.state == "RUNNING"
			or state.scanStatus.state == "STALE_RETRY")) then
		local scan = state.scanStatus or {}
		local done = scan.progressDone or scan.zonesDone
		local total = scan.progressTotal or scan.zonesTotal
		local value, mode = operationProgress(done, total)
		operation = {
			label = value and (tostring(math.floor(value * 100 + 0.5)) .. "%") or "",
			value = value, mode = mode,
			status = "warning", tone = "warning", showProgress = true,
		}
		statusLabel, statusTone = T("IGUI_GS_ScanRunningShort"), "warning"
	end
	if state.scanActive == true or state.reconcilePending == true
		or (state.scanStatus and (state.scanStatus.state == "RUNNING" or state.scanStatus.state == "STALE_RETRY")) then
		statusLabel, statusTone = T("IGUI_GS_ScanRunningShort"), "warning"
	end
	if load then
		local pendingStatus, pendingOperation = Loading.header(load)
		statusLabel, statusTone, operation = pendingStatus.text, pendingStatus.tone, pendingOperation
		if load.phase == "checking" then networkTitle = nil end
	end
	return {
		productName = T("IGUI_GS_TerminalTitle"),
		contextName = networkTitle,
		status = { text = statusLabel, tone = statusTone },
		operation = operation,
		statusPlacement = "inline",
		statusDot = true,
	}
end

local function declaredModLine(modId, fallbackName)
	local info = nil
	if getModInfoByID and type(modId) == "string" and modId ~= "" then
		local ok, detected = pcall(function() return getModInfoByID(modId) end)
		if ok then info = detected end
	end
	local name, version = nil, nil
	if info and info.getName then
		local ok, value = pcall(function() return info:getName() end)
		if ok and value ~= nil and tostring(value) ~= "" then name = tostring(value) end
	end
	if info and info.getModVersion then
		local ok, value = pcall(function() return info:getModVersion() end)
		if ok and value ~= nil and tostring(value) ~= "" then version = tostring(value) end
	end
	name = name or fallbackName or modId or "?"
	return name .. (version and (" " .. version) or "")
end

local function resolveRuntimeVersions()
	local coreVersion = GlobalStorageSiK.Config and GlobalStorageSiK.Config.MOD_VERSION
	local visible = coreVersion and ("Core " .. tostring(coreVersion)) or "Core"
	local tooltip = { declaredModLine("SiKUIFramework", "SiK UI Framework") }
	local ok, _, addons = GSSiK.API.Addon.listActive()
	addons = ok and addons or {}
	for i = 1, #addons do
		local def = addons[i]
		local fallback = def.titleKey and T(def.titleKey) or def.id or def.modId
		tooltip[#tooltip + 1] = declaredModLine(def.modId, fallback)
	end
	return visible, tooltip
end

--- Sincroniza únicamente datos del shell. Geometría, controles y dibujo
--- pertenecen a SiK.UI.Window y nunca se recrean desde el producto.
function GS_TerminalUI:syncHeaderChrome()
	if not self.setHeader then return end
	local transient = self.terminalState and self.terminalState.headerTransient
	if transient and transient.expiresMs and getTimestampMs
		and getTimestampMs() >= transient.expiresMs then
		self.terminalState.headerTransient = nil
	end
	local activeOperation = GlobalStorageSiK.UIFeedback.operationFor(self.playerNum,
		self.terminalState and self.terminalState.networkId)
	local spec = buildHeaderSpec(self.terminalState, activeOperation, self._gsCatalogLoad)
	if not self._gsCatalogLoad and (self._gsAccessState == "revoking" or self._gsAccessState == "revalidating") then
		spec.status, spec.operation = Loading.header({phase="checking"})
	end
	spec.variant = self.accessMode == "blocked" and "blocked" or "default"
	if self.accessMode == "blocked" then
		-- Use the body's already resolved presentation; no scan/read to paint a header.
		spec.contextName = nil
		spec.operation = false
		spec.status = { text = T(self._blockedHeaderTitleKey or "IGUI_GS_BlockedNoTerminalTitle"), tone = "danger" }
	end
	self:setHeader(spec)
	if self.setVersions then
		local visible, tooltip = resolveRuntimeVersions()
		self:setVersions(visible, tooltip)
	end
end

local TAB_BG = { r = 0, g = 0, b = 0, a = 0 }
--- Refresca contenido de la pestaña activa (carga diferida).
---@param self GS_TerminalUI
function GS_TerminalUI:refreshActiveTabContent()
	local state = self.terminalState or {}
	local tab = self.activeTabKey or "items"
	local builtNow = self.ensureTabBuilt and self:ensureTabBuilt(tab) == true
	-- Every builder mounts with the current terminal state. Re-running the
	-- tab refresh immediately afterwards mounted/updated the same surface a
	-- second time in the same frame and made opening/tab switches stall.
	if builtNow then return end
	if tab == "items" then
		self:refreshItemsTab()
	elseif tab == "network" then
		GlobalStorageSiK.TerminalNetwork.refreshScroll(self, state)
	elseif tab == "config" then
		GlobalStorageSiK.TerminalOptions.refreshScroll(self, state)
	elseif tab == "addons" and self.addonsPanel then
		self:refreshAddonRecipesState()
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
	if self._gsBuiltTabs[tabKey] then return false end
	if tabKey == "items" then
		local built, reason = GlobalStorageSiK.TerminalItems.buildSection(self.itemsPanel, self)
		if not built then
			GlobalStorageSiK.Log.error("TerminalUI", "warehouse_surface_failed", tostring(reason))
			return false
		end
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
		return true
	end
	self._gsBuiltTabs[tabKey] = true
	return true
end

local function createTabPanel(terminal)
	-- Los paneles se crean ya con la geometria real del Shell. Navigation los
	-- adopta despues, pero ningun widget nace sobre un host provisional.
	local shell = UI.Window.chromeRects(terminal)
	local railW = GlobalStorageSiK.TerminalTabs.measureRailWidth(terminal)
	local panel = UI.Controls.panel(nil, {
		x = 0, y = 0, w = math.max(2, shell.content.w - railW),
		h = math.max(2, shell.content.h), drawBackground = false,
		backgroundColor = TAB_BG,
		borderColor = { r = 0, g = 0, b = 0, a = 0 },
		controlId = "terminalTabHost",
		theme = terminal._sikThemeContext,
	})
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
	if palettePlayer then
		GlobalStorageSiK.UIPalette.load(palettePlayer)
		GlobalStorageSiK.UIOpacity.load(palettePlayer)
	end
	local o = UI.Window.newInstance(self, x, y, width, height)
	o.moveWithMouse = false
	playerNum = palettePlayer and palettePlayer.getPlayerNum and palettePlayer:getPlayerNum() or playerNum
	local viewport = UI.Viewport.resolve(playerNum)
	local profile = UI.Metrics.profile(viewport.w, "terminal")
	local rect = UI.Window.resolveBounds({
		profile = "terminal", playerNum = playerNum,
		x = x, y = y, w = width, h = height,
	})
	local tokens = UI.Metrics.tokens()
	local themeContext = UI.Theme.context(nil, nil, playerNum)
	local theme = UI.Theme.tokens(themeContext)
	o._sikThemeContext = themeContext
	o.playerNum = playerNum
	o._sikWindowProfile = "terminal"
	o.padding = 14
	o.headerHeight = 50
	o.statusFooterHeight = UI.Controls.metrics(profile.name).rowHeight
	o.backgroundColor = theme.background
	o.borderColor = { r = 0, g = 0, b = 0, a = 1 }
	o.terminalState = nil
	o.minimumWidth = rect.minWidth
	o.minimumHeight = rect.minHeight
	o.maximumWidth = rect.maxWidth
	o.maximumHeight = rect.maxHeight
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
	local viewport = UI.Viewport.resolve(self.playerNum or 0)
	local profile = UI.Metrics.profile(viewport.w, "terminal")
	local _, rect = self:updateConstraints({
		profile = "terminal", playerNum = self.playerNum or 0,
		x = nextX, y = nextY, w = nextW, h = nextH,
		minWidth = 720, minHeight = 480,
		maxWidth = viewport.w, maxHeight = viewport.h,
		capWidth = 1, capHeight = 1,
	})
	self._sikWindowProfile = "terminal"
	self.minimumWidth = rect.minWidth
	self.minimumHeight = rect.minHeight
	self.maximumWidth = rect.maxWidth
	self.maximumHeight = rect.maxHeight
	self._sikSafeViewport = viewport
	self.statusFooterHeight = self.footerHeight or 0
end

function GS_TerminalUI:syncAfterResponsiveResize()
	-- onReflow ya aplica dinamicamente cada geometria real durante el gesto.
	-- onResizeEnd solo cierra/persiste la operacion del framework; repetir aqui
	-- el mismo layout congelaba brevemente la ventana al soltar el raton.
end

--- El framework posee drag/resize/captura. El producto solo intercepta su
--- operación de retirada para no iniciar simultáneamente un gesto de ventana.
function GS_TerminalUI:onMouseMove(dx, dy)
	if GlobalStorageSiK.TerminalWithdrawDrag.isActive() then
		GlobalStorageSiK.TerminalWithdrawDrag.moveToPointer()
		return true
	end
	return UI.Window.callBase(self, "onMouseMove", dx, dy)
end

function GS_TerminalUI:onMouseMoveOutside(dx, dy)
	if GlobalStorageSiK.TerminalWithdrawDrag.isActive() then
		GlobalStorageSiK.TerminalWithdrawDrag.moveToPointer()
		return true
	end
	return UI.Window.callBase(self, "onMouseMoveOutside", dx, dy)
end

function GS_TerminalUI:onMouseUp(x, y)
	if GlobalStorageSiK.TerminalWithdrawDrag.isActive() then
		return GlobalStorageSiK.TerminalWithdrawDrag.finishAtPointer()
	end
	return UI.Window.callBase(self, "onMouseUp", x, y)
end

function GS_TerminalUI:onMouseUpOutside(x, y)
	if GlobalStorageSiK.TerminalWithdrawDrag.isActive() then
		return GlobalStorageSiK.TerminalWithdrawDrag.finishAtPointer()
	end
	return UI.Window.callBase(self, "onMouseUpOutside", x, y)
end

function GS_TerminalUI:initialise()
	UI.Window.callBase(self, "initialise")
	self.clipChildren = true
	local versionText, versionTooltip = resolveRuntimeVersions()
	UI.Window.apply(self, {
		x = self.x, y = self.y, w = self.width, h = self.height,
		playerNum = self.playerNum or 0,
		profile = "terminal",
		theme = self._sikThemeContext, cascadeOnOverlap = true,
		minWidth = self.minimumWidth, minHeight = self.minimumHeight,
		maxWidth = self.maximumWidth, maxHeight = self.maximumHeight,
		capWidth = 1, capHeight = 1,
		padding = self.padding, contentPadding = 0,
		headerHeight = self.headerHeight,
		header = buildHeaderSpec(self.terminalState, nil, self._gsCatalogLoad),
		footer = { versions = versionText, tooltip = versionTooltip, align = "center",
			expandWhenTight = true },
		geometryKey = "terminal-shell",
		geometryVersion = 2,
		resizable = true, resizeHandle = 24, draggable = true, closeOnEscape = true,
		focusPriority = 50,
		pointerGuard = function()
			return not GlobalStorageSiK.TerminalWithdrawDrag.isActive()
		end,
		canStartPointer = function()
			return not GlobalStorageSiK.TerminalWithdrawDrag.isActive()
		end,
		onReflow = function(context)
			if context.component._gsChildrenBuilt then
				context.component:calculateLayout()
			end
		end,
		onResizeEnd = function(context)
			if context.component._gsChildrenBuilt then
				context.component:syncAfterResponsiveResize()
			end
		end,
		onClose = function(context)
			return context.component:cleanupTerminalSession()
		end,
	})
	-- Compatibilidad transitoria de producto: TerminalTabs solo usa esta
	-- referencia para elevar el control; la creación y geometría son públicas.
	self.closeBtn = self.closeControl
	self:setVisible(true)
	self:createChildren()
end

function GS_TerminalUI:createChildren()
	-- PZ llama createChildren automáticamente desde instantiate() (ISUIElement),
	-- y nuestro initialise() lo llama también. Sin guard se construían DOS juegos
	-- de navegación/itemsPanel: uno quedaba huérfano pero seguía pintándose
	-- (doble interfaz) y nunca se reposicionaba (campos en sitio viejo).
	if self._gsChildrenBuilt then
		return
	end
	self._gsChildrenBuilt = true
	self.networkPanel = createTabPanel(self)
	self.configPanel = createTabPanel(self)
	self.itemsPanel = createTabPanel(self)
	self.addonsPanel = createTabPanel(self)
	self.blockedPanel = createTabPanel(self)
	self._gsBuiltTabs = {}

	-- "Configuración" (dev41) va justo despues de Red en el riel principal -
	-- "Addons" sigue como pestaña fija de PIE (footerTabDef, mas abajo), sin
	-- relacion de orden con este array: insertar aqui no la desplaza.
	local tabDefs = {
		{ key = "items", titleKey = "IGUI_GS_TabWarehouse", panelField = "itemsPanel", iconPath = "media/ui/GS/sik-rail-warehouse.png" },
		{ key = "network", titleKey = "IGUI_GS_TabNetwork", panelField = "networkPanel", iconPath = "media/ui/GS/sik-rail-network.png" },
		{ key = "config", titleKey = "IGUI_GS_TabConfig", panelField = "configPanel", iconPath = "media/ui/GS/sik-rail-config.png" },
	}
	self.footerTabDef = {
		key = "addons",
		titleKey = "IGUI_GS_TabAddons",
		panelField = "addonsPanel",
		iconPath = "media/ui/GS/sik-rail-addons.png",
	}
	GlobalStorageSiK.TerminalTabs.build(self, tabDefs)
	if self.navigationContainer then self.navigationContainer:ensureContentHost("blocked") end
	GlobalStorageSiK.TerminalTabs.registerPanel(self, "blocked", self.blockedPanel)

	-- El Shell y todos sus hosts padre reciben geometria antes de montar una
	-- superficie. El contenido activo se crea un tick despues de añadir la
	-- ventana al UIManager: asi el armazon aparece inmediatamente y ningun widget
	-- nace sobre un padre provisional ni bloquea la primera presentacion.
	self:calculateLayout()
end

--- Cambia la pestaña activa.
---@param tabKey string
function GS_TerminalUI:activateTab(tabKey)
	GlobalStorageSiK.TerminalTabs.activate(self, tabKey)
end

function GS_TerminalUI:buildItemsToolbar()
	return GlobalStorageSiK.TerminalItems.buildSection(self.itemsPanel, self)
end

function GS_TerminalUI:calculateLayout()
	local w = self.width
	local h = self.height
	local pad = self.padding
	local blockedMode = self.accessMode == "blocked"
	local shell = UI.Window.chromeRects(self)
	local tabY = shell.content.y
	local railW = blockedMode and 0
		or GlobalStorageSiK.TerminalTabs.measureRailWidth(self)
	-- The footer divider belongs to the global window chrome and spans below
	-- both the navigation rail and the content area.
	self._sikFooterInsetLeft = 0
	shell = UI.Window.chromeRects(self)
	local bodyH = shell.content.h
	self.headerHeight = shell.header.h
	self.statusFooterHeight = shell.footer.h
	local navigationContainer = self.navigationContainer
	if navigationContainer then
		navigationContainer:setNavigationVisible(not blockedMode)
		self.navigationContainer:reflow({ x = shell.content.x, y = tabY,
			w = shell.content.w, h = bodyH })
	end
	local fallbackBounds = { x = shell.content.x, y = tabY,
		w = shell.content.w, h = bodyH }
	local contentBounds = navigationContainer and navigationContainer:getContentBounds(fallbackBounds)
		or UI.Layout.resolveRect(fallbackBounds, nil, 1)
	local innerW, innerH = contentBounds.w, contentBounds.h

	-- Navigation owns the one common content area and the exact bounds of
	-- every selectable surface inside it.  Rewriting panel geometry here used
	-- to erase its 12 px inset and made fixed and dynamic tabs diverge.

	local activeLayoutTab = blockedMode and "blocked" or (self.activeTabKey or "items")
	if activeLayoutTab == "blocked" and self.blockedPanel and self._gsBuiltTabs and self._gsBuiltTabs.blocked
		and GlobalStorageSiK.TerminalBlockedPanel then
		GlobalStorageSiK.TerminalBlockedPanel.layout(self, innerW, innerH)
	end

	if activeLayoutTab == "network" and self._gsBuiltTabs and self._gsBuiltTabs.network then
		GlobalStorageSiK.TerminalNetwork.layout(self, innerW, innerH)
	end
	if activeLayoutTab == "config" and self._gsBuiltTabs and self._gsBuiltTabs.config then
		GlobalStorageSiK.TerminalOptions.layout(self, innerW, innerH)
	end

	if activeLayoutTab == "items" and self.itemsPanel and self._gsBuiltTabs and self._gsBuiltTabs.items then
		GlobalStorageSiK.TerminalItems.layoutSection(self.itemsPanel, self, innerW, innerH)
	end

	if activeLayoutTab == "addons" and self.addonsPanel and self._gsBuiltTabs and self._gsBuiltTabs.addons then
		GlobalStorageSiK.TerminalAddons.layout(self.addonsPanel, innerW, innerH)
	end
	if GlobalStorageSiK.TerminalExtensions and GlobalStorageSiK.TerminalExtensions.layoutActive then
		GlobalStorageSiK.TerminalExtensions.layoutActive(self, activeLayoutTab, innerW, innerH)
	end
end

--- Reconstruye contenido scrollable tras redimensionar (patrón Blocked UI).
function GS_TerminalUI:rebuildScrollContent()
	local state = self.terminalState
	if not state then return end
	self:calculateLayout()
	-- Los recorridos de diagnóstico del árbol completo son exclusivamente bajo
	-- demanda mediante TerminalUI.debugDumpTree(). Ejecutarlos al soltar cada
	-- resize bloqueaba el hilo UI aun cuando la geometría no había cambiado.
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
	local tone = "success"
	if status == "warning" then
		tone = "warning"
	elseif status == "critical" or status == "full" then
		tone = "danger"
	end
	local color = UI.Theme.color(tone)
	local r, g, b = color.r, color.g, color.b

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
	if statWeight and statWeight.setName and UI.Scroll.isLiveWidget(statWeight) then
		statWeight:setName(weightText)
		statWeight.r = r
		statWeight.g = g
		statWeight.b = b
	end
	if netUi and UI.Scroll.isLiveWidget(netUi.weightBar) then
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
		-- El Almacen comparte la barra de capacidad con el resumen fisico del
		-- inventario. Ambos contadores proceden del estado autoritativo: las
		-- unidades son la suma de sus filas agregadas y los tipos distintos son
		-- el itemTypeCount calculado por servidor (incluido el cero explicito).
		-- No reutilizar weightText aqui: hacerlo borraba el binding compuesto
		-- creado por TabWarehouseContext en cada refreshNetworkPanel().
		local state = self.terminalState or {}
		local rows = state.items
		local itemCount = nil
		if rows ~= nil then
			itemCount = 0
			for i = 1, #rows do
				itemCount = itemCount + (tonumber(rows[i].count) or 0)
			end
		end
		local warehouseCapacity = CapacityPresentation.fromState(cap, {
			count = itemCount,
			typeCount = tonumber(state.itemTypeCount),
		})
		if self.itemsWeightLbl.setProgress then
			self.itemsWeightLbl:setProgress(warehouseCapacity)
		elseif self.itemsWeightLbl.setStatus then
			self.itemsWeightLbl:setStatus(warehouseCapacity.label, warehouseCapacity.tone)
		elseif self.itemsWeightLbl.setName then
			self.itemsWeightLbl:setName(warehouseCapacity.label)
			self.itemsWeightLbl.r = r
			self.itemsWeightLbl.g = g
			self.itemsWeightLbl.b = b
		end
	end
	if netScroll and netScroll._weightBar then
		netScroll._weightBar.capacityPercent = pct
		netScroll._weightBar.capacityStatus = status
	end
end

function GS_TerminalUI:render()
	UI.Window.callBase(self, "render")
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
	if self.navigationContainer and self.activeTabKey then
		self.navigationContainer:setActive(self.activeTabKey, false)
	end
end

function GS_TerminalUI:refreshFromState(state)
	local prev = self.terminalState or {}
	local incoming = state
	local firstState = self._gsHasAppliedState ~= true
	local reusedCatalog = not firstState and incoming and incoming.catalogRestored == true
		and incoming.catalogScope == prev.catalogScope
		and incoming.inventoryRevision == prev._gsAppliedCatalogRevision
	if reusedCatalog then incoming.items = prev.items end
	local inventoryChanged = firstState or (incoming and (
		(incoming.inventoryRevision ~= nil and incoming.inventoryRevision ~= prev.inventoryRevision)
		or (incoming.items ~= nil and incoming.items ~= prev.items)))
	local capacityChanged = firstState or (incoming and incoming.capacity ~= nil
		and incoming.capacity ~= prev.capacity)
	local networkChanged = firstState or (incoming and (
		(incoming.snapshotRevision ~= nil and incoming.snapshotRevision ~= prev.snapshotRevision)
		or (incoming.nodes ~= nil and incoming.nodes ~= prev.nodes)
		or (incoming.zones ~= nil and incoming.zones ~= prev.zones)
		or incoming.nodeTypeCounts ~= nil))
	local addonsChanged = firstState or (incoming and incoming.installedAddons ~= nil
		and incoming.installedAddons ~= prev.installedAddons)
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
		if state.itemTypeCount ~= nil then
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
			merged.items = state.items
		end
		state = merged
	end
	if state and state.items and not reusedCatalog then
		state.items = GlobalStorageSiK.NativeProduct.copyRows(state.items)
	end
	if state and state.headerTransient == nil and prev.headerTransient ~= nil then
		state.headerTransient = prev.headerTransient
	end
	self.terminalState = state or prev
	self:syncHeaderChrome()
	if capacityChanged then self:applyCapacityState(self.terminalState.capacity) end
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
		-- El resumen con el indicador de energia vive en la pestaña normal de
		-- Opciones. Sin suministro, el redirect conserva visible el diagnostico.
		self:activateTab("config")
	end
	self:setRedistributeState(self.terminalState.redistributeActive == true,
		self.terminalState.redistributeActive == true and T("IGUI_GS_RedistributeConfigLocked") or nil,
		self.terminalState.redistributeActive == true and "warn" or nil,
		self.terminalState.redistributeProgress)
	if state and state.accessMode then
		self.terminalState.accessMode = state.accessMode
	elseif state and not state.openUi and prev.accessMode then
		self.terminalState.accessMode = prev.accessMode
	end
	-- Search belongs to this player's UI, never to a remote inventory update.
	-- Empty is an intentional query too; do not resurrect another watcher's echo.
	if self._warehouseQuery == nil then
		self._warehouseQuery = self.searchEntry and self.searchEntry:getText() or ""
	end
	self:refreshNetworkPanel()
	local cap = self.terminalState.capacity
	if cap and not self._capacityHaloShown then
		local st = cap.status
		if st == "warning" or st == "critical" or st == "full" then
			local player = GlobalStorageSiK.NetClient.getPlayer(self.playerNum)
			if player then
				local msg
				if st == "full" then
					msg = T("IGUI_GS_WeightFull")
				elseif st == "critical" then
					msg = T("IGUI_GS_WeightCritical", tostring(cap.percent or 0) .. "%")
				else
					msg = T("IGUI_GS_WeightWarn", tostring(cap.percent or 0) .. "%")
				end
				GlobalStorageSiK.UIFeedback.halo(player, msg, 255,
					st == "warning" and 200 or 120, 60, 520,
					{ tone = st == "warning" and "warning" or "danger", channel = "capacity" })
				self._capacityHaloShown = true
			end
		end
	end
	local tab = self.activeTabKey or "items"
	local builtNow = self.ensureTabBuilt and self:ensureTabBuilt(tab) == true
	if tab == "items" and (inventoryChanged or capacityChanged) and not builtNow then
		self:refreshItemsTab()
	elseif tab == "network" and networkChanged and not builtNow then
		GlobalStorageSiK.TerminalNetwork.refreshScroll(self, self.terminalState)
		if GlobalStorageSiK.TerminalNodeEditor.syncNodeData then
			GlobalStorageSiK.TerminalNodeEditor.syncNodeData(self, self.terminalState.nodes or {})
		end
		if GlobalStorageSiK.TerminalZoneEditor and GlobalStorageSiK.TerminalZoneEditor.syncZoneData then
			GlobalStorageSiK.TerminalZoneEditor.syncZoneData(self.terminalState.zones or {})
		end
	elseif tab == "config" and (networkChanged or inventoryChanged or addonsChanged) and not builtNow then
		GlobalStorageSiK.TerminalOptions.refreshScroll(self, self.terminalState)
	elseif tab == "addons" and self.addonsPanel and addonsChanged and not builtNow then
		GlobalStorageSiK.TerminalAddons.refresh(self.addonsPanel, self)
	elseif not builtNow and GlobalStorageSiK.TerminalExtensions then
		GlobalStorageSiK.TerminalExtensions.refreshActive(self, tab)
	end
	-- Programación va ANTES que Craft/Build para que, si el periférico Reader
	-- ya está instalado cuando el terminal abre por primera vez, su pestaña
	-- reclame su hueco en self.dynamicSlots (append-only, ver
	-- GS_TerminalTabRail:setDynamicTabVisible) antes que ellas.
	if addonsChanged and self.syncProgrammingTabVisibility then
		self:syncProgrammingTabVisibility()
	end
	if addonsChanged and GlobalStorageSiK.TerminalExtensions
		and GlobalStorageSiK.TerminalExtensions.syncVisibilityAll then
		GlobalStorageSiK.TerminalExtensions.syncVisibilityAll(self)
	end
	if networkChanged and GlobalStorageSiK.NodeHighlight and GlobalStorageSiK.NodeHighlight.reapplyAfterRefresh then
		GlobalStorageSiK.NodeHighlight.reapplyAfterRefresh(self.terminalState and self.terminalState.nodes)
	end
	self._gsHasAppliedState = true
end

--- Compatibilidad con API de ventana bloqueada integrada.
---@param force boolean|nil
function GS_TerminalUI:applyRefreshIfNeeded(force)
	if self.accessMode == "blocked" and GlobalStorageSiK.TerminalBlockedPanel then
		GlobalStorageSiK.TerminalBlockedPanel.applyRefreshIfNeeded(self, force)
	end
end

function GS_TerminalUI:cleanupTerminalSession()
        if self._terminalSessionClosed then return true end
        self._terminalSessionClosed = true
	if self._gsOpenDispatch and Events and Events.OnTick then
		Events.OnTick.Remove(self._gsOpenDispatch)
		self._gsOpenDispatch = nil
	end
	self._gsCatalogWidgetLocks = nil
	self._gsCatalogLoad = nil
        if GlobalStorageSiK.TerminalOptions and GlobalStorageSiK.TerminalOptions.dispose then
                GlobalStorageSiK.TerminalOptions.dispose(self)
        end
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
	if GlobalStorageSiK.TerminalUI.cancelPendingOpen then
		GlobalStorageSiK.TerminalUI.cancelPendingOpen(self.playerNum)
	end
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
	if GlobalStorageSiK.TerminalAccessGuard and GlobalStorageSiK.TerminalAccessGuard.clear then
		GlobalStorageSiK.TerminalAccessGuard.clear(self.playerNum)
	end
	if GlobalStorageSiK.WithdrawClient and GlobalStorageSiK.WithdrawClient.cancelAll then
		GlobalStorageSiK.WithdrawClient.cancelAll("terminal_closed", self.playerNum)
	end
	if GlobalStorageSiK.TerminalWithdrawDrag and GlobalStorageSiK.TerminalWithdrawDrag.cancel then
		GlobalStorageSiK.TerminalWithdrawDrag.cancel()
	end
	if GlobalStorageSiK.TerminalItems and GlobalStorageSiK.TerminalItems.disposeSection then
		GlobalStorageSiK.TerminalItems.disposeSection(self.itemsPanel, self)
	end
	if GlobalStorageSiK.Client and GlobalStorageSiK.Client.clearTransientCaches then
		GlobalStorageSiK.Client.clearTransientCaches(self.playerNum)
	end
	if GlobalStorageSiK.TransferQueue and GlobalStorageSiK.TransferQueue.clear then
		GlobalStorageSiK.TransferQueue.clear(self.playerNum)
	end
	self._capacityHaloShown = nil
	if GlobalStorageSiK.TerminalUI.removeInstanceForPlayer then
		GlobalStorageSiK.TerminalUI.removeInstanceForPlayer(self.playerNum, self)
	elseif GlobalStorageSiK.TerminalUI.instance == self then
		GlobalStorageSiK.TerminalUI.instance = nil
	end
	if GlobalStorageSiK.TerminalUI._liveInstances then
		GlobalStorageSiK.TerminalUI._liveInstances[self] = nil
	end
	self.closeBtn = nil
	return true
end

function GS_TerminalUI:onClose()
	if self.close then return self:close("product") end
	return self:cleanupTerminalSession()
end

function GS_TerminalUI:sendCommand(command, payload)
	if self._gsCatalogLoad then return false end
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
		searchQuery = self:getSearchQuery(),
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
	if GlobalStorageSiK.Client and GlobalStorageSiK.Client.addInventoryCatalogToken then
		payload = GlobalStorageSiK.Client.addInventoryCatalogToken(payload, self.playerNum,
			payload.networkId or (self.terminalState and self.terminalState.networkId))
	end
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
function GS_TerminalUI:setRedistributeState(running, message, status, progress)
	local stateChanged = self._autoSortRunning ~= (running == true)
	self._autoSortRunning = running == true
	self._autoSortMessage = message
	self._autoSortStatus = status
	if self.terminalState then
		self.terminalState.redistributeActive = self._autoSortRunning
		self.terminalState.redistributeProgress = self._autoSortRunning and progress or nil
	end
	if self.autoSortBtn then
		self.autoSortBtn._sikUiLabel = T("IGUI_GS_Redistribute")
		-- ISButton reads textColor.r without a nil guard.  This control is
		-- retained by the terminal shell when its tab is hidden, so clearing the
		-- colour here breaks every subsequent frame, not just the inventory tab.
		if UI.Controls.styleButton then
			UI.Controls.styleButton(self.autoSortBtn, {})
		end
		local allowed = self:canUseAutoSort()
		-- Auditoria de botones (2026-08-26): el lock del framework refleja SOLO el
		-- motivo "sin permiso" (requisito no cumplido, el mismo concepto que
		-- el resto de botones bloqueados) - "ya se esta ejecutando" es un
		-- estado transitorio de trabajo en curso, categoria distinta, no se
		-- pinta igual (sigue usando el atenuado plano de setEnable a secas).
		self.autoSortBtn:setLocked(not allowed)
		self.autoSortBtn:setEnabled(not self._autoSortRunning and allowed)
		UI.Controls.setTooltip(self.autoSortBtn, allowed
				and T("IGUI_GS_RedistributeHint")
				or T("IGUI_GS_RedistributeAdminOnly"), { kind = "descriptive" })
	end
	self:syncHeaderChrome()
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
		if player then
			GlobalStorageSiK.UIFeedback.halo(player, T("IGUI_GS_RedistributeConfigLocked"),
				255, 190, 70, 420, { tone = "warning", channel = "redistribute" })
		end
	end
	return not locked
end

function GS_TerminalUI:onRedistributeNetwork()
	if self._autoSortRunning then return end
	if not self:canUseAutoSort() then
		local player = GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer
			and GlobalStorageSiK.NetClient.getPlayer(self.playerNum) or nil
		if player then
			GlobalStorageSiK.UIFeedback.halo(player, T("IGUI_GS_RedistributeAdminOnly"),
				255, 190, 70, 420, { tone = "warning", channel = "redistribute" })
		end
		return
	end
	self:setRedistributeState(true, T("IGUI_GS_RedistributingNetwork"), "warn")
	self:sendCommand("redistributeNetwork", {
		searchQuery = self:getSearchQuery(),
	})
end

---@param message string|nil
function GS_TerminalUI:onRedistributeStarted(message, progress)
	self:setRedistributeState(true, message, "warn", progress)
end

--- Llamado desde GS_Client.lua al recibir el actionResult de fin de job
--- (jobType="redistribute").
---@param ok boolean
---@param message string|nil
function GS_TerminalUI:onRedistributeFinished(ok, message)
	self:setRedistributeState(false, nil, nil, nil)
	self:setHeaderTransient(message, ok and "success" or "danger", ok and 2200 or 5200)
end

function GS_TerminalUI:setHeaderTransient(message, tone, durationMs)
	if not self.terminalState or message == nil or tostring(message) == "" then return end
	local now = getTimestampMs and getTimestampMs() or 0
	self.terminalState.headerTransient = {
		label = tostring(message), tone = tone or "warning",
		expiresMs = now + (tonumber(durationMs) or 4200),
	}
	self:syncHeaderChrome()
end

--- Texto actual del buscador de ítems.
---@return string
function GS_TerminalUI:getSearchQuery()
	if self._warehouseQuery ~= nil then return self._warehouseQuery end
	return self.searchEntry and self.searchEntry:getText() or ""
end

--- Filtra el catálogo de ítems según categoría y buscador (idioma del cliente).
---@param rows table[]|nil
---@return table[]
function GS_TerminalUI:applyItemsFilter(rows)
	rows = rows or {}
	-- Nombre, busqueda y filtros parten de la misma proyeccion localizada que
	-- renderiza Almacen. Prepararlo aqui evita filtrar antes de conocer el titulo
	-- exacto de una edicion RecordedMedia.
	if GlobalStorageSiK.TerminalItems.prepareRecordedMediaRows then
		GlobalStorageSiK.TerminalItems.prepareRecordedMediaRows(rows, self.playerNum or 0)
	end
	rows = GlobalStorageSiK.TerminalItems.filterByMainCategory(rows, self:getMainCategoryFilterKey())
	rows = GlobalStorageSiK.TerminalItems.filterBySubCategory(rows, self:getSubCategoryFilterKey())
	rows = GlobalStorageSiK.TerminalItems.filterByLeafCategory(rows, self:getLeafCategoryFilterKey())
	local q = UI.Controls.effectiveSearchQuery(self:getSearchQuery())
	if not q or q == "" then
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
-- evita a proposito, ver regla de diagnostico dirigido del AGENTS.md).
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
	local filtered = self:applyItemsFilter(allItems)
	GlobalStorageSiK.TerminalItems.refreshSection(self.itemsPanel, self, filtered)
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
		self:getSearchQuery(),
		{ playerNum = self.playerNum, networkId = self.terminalState and self.terminalState.networkId }
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
		searchQuery = self:getSearchQuery(),
	})
end

function GS_TerminalUI:onRenameZone(zoneId, name)
	if not self:canEditNetworkConfig(true) then return end
	self:sendCommand("renameZone", {
		zoneId = zoneId,
		name = name,
		searchQuery = self:getSearchQuery(),
	})
end

function GS_TerminalUI:onDeleteZone(zoneId)
	if not self:canEditNetworkConfig(true) then return end
	self:sendCommand("deleteZone", {
		zoneId = zoneId,
		searchQuery = self:getSearchQuery(),
	})
end

function GS_TerminalUI:onRemoveNode(nodeId)
	if not self:canEditNetworkConfig(true) then return end
	self:sendCommand("removeNode", {
		nodeId = nodeId,
		searchQuery = self:getSearchQuery(),
	})
end

function GS_TerminalUI:onRequestRebindProposal(nodeId, targetNodeId)
	if not self:canEditNetworkConfig(true) then return end
	self:sendCommand("requestRebindProposal", {
		nodeId = nodeId, targetNodeId = targetNodeId,
		searchQuery = self:getSearchQuery(),
	})
end

function GS_TerminalUI:onRebindNode(nodeId, rebindToken)
	if not self:canEditNetworkConfig(true) then return end
	self:sendCommand("rebindNode", {
		nodeId = nodeId, rebindToken = rebindToken,
		searchQuery = self:getSearchQuery(),
	})
end

function GS_TerminalUI:onRequestConfigTransferProposal(nodeId, targetNodeId)
	if not self:canEditNetworkConfig(true) then return end
	self:sendCommand("requestConfigTransferProposal", {
		nodeId = nodeId, targetNodeId = targetNodeId,
		searchQuery = self:getSearchQuery(),
	})
end

function GS_TerminalUI:onTransferNodeConfiguration(nodeId, transferToken)
	if not self:canEditNetworkConfig(true) then return end
	self:sendCommand("transferNodeConfiguration", {
		nodeId = nodeId, transferToken = transferToken,
		searchQuery = self:getSearchQuery(),
	})
end

function GS_TerminalUI:onUpdateNode(nodeId, displayName, category, enabled, membership)
	if not self:canEditNetworkConfig(true) then return end
	local payload = {
		nodeId = nodeId,
		displayName = displayName,
		category = category or "",
		searchQuery = self:getSearchQuery(),
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
		searchQuery = self:getSearchQuery(),
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
	-- Compatibilidad para callers antiguos: una unica ruta de refresco posee
	-- tanto recetas como tarjetas; TerminalTabs no invoca ya este alias aparte.
	self:refreshActiveTabContent()
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
		local definitionOk, _, def = GSSiK.API.Addon.get(addonId)
		if not definitionOk or not def or not GlobalStorageSiK.AddonRecipes.canCraftModule(player, def) then
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
		searchQuery = self:getSearchQuery(),
	})
end

function GS_TerminalUI:onAddPermissionUser(characterName, characterId, factionUsername)
	self:sendCommand("addPermissionUser", {
		characterName = characterName or "",
		username = characterName or "",
		characterId = characterId or "",
		factionUsername = factionUsername or "",
		searchQuery = self:getSearchQuery(),
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
		searchQuery = self:getSearchQuery(),
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
		searchQuery = self:getSearchQuery(),
	})
end

function GS_TerminalUI:onAddPermissionFaction(factionName)
	self:sendCommand("addPermissionFaction", {
		factionName = factionName or "",
		searchQuery = self:getSearchQuery(),
	})
end

function GS_TerminalUI:onRemovePermissionFaction(factionName)
	self:sendCommand("removePermissionFaction", {
		factionName = factionName or "",
		searchQuery = self:getSearchQuery(),
	})
end

function GS_TerminalUI:onRenameNetwork(name)
	self:sendCommand("renameNetwork", {
		name = name or "",
		searchQuery = self:getSearchQuery(),
	})
end

function GS_TerminalUI:onLeaveNetwork()
	self:sendCommand("leaveNetwork", {
		searchQuery = self:getSearchQuery(),
	})
end

function GS_TerminalUI:onRemovePermissionUser(username, characterId)
	self:sendCommand("removePermissionUser", {
		username = username or "",
		characterId = characterId or "",
		searchQuery = self:getSearchQuery(),
	})
end

function GS_TerminalUI:onSetMemberRole(username, role, characterId)
	self:sendCommand("setMemberRole", {
		username = username or "",
		characterId = characterId or "",
		role = role or "member",
		searchQuery = self:getSearchQuery(),
	})
end

function GS_TerminalUI:onSetMemberZoneAccess(username, characterId, deniedZoneIds)
	self:sendCommand("setMemberZoneAccess", {
		username = username or "",
		characterId = characterId or "",
		deniedZoneIds = deniedZoneIds or {},
		searchQuery = self:getSearchQuery(),
	})
end

function GlobalStorageSiK.TerminalUI:onToggleFactionOnly()
	local perms = self.terminalState and self.terminalState.permissions or {}
	self:sendCommand("setFactionOnly", {
		enabled = not (perms.factionOnly == true),
		searchQuery = self:getSearchQuery(),
	})
end
