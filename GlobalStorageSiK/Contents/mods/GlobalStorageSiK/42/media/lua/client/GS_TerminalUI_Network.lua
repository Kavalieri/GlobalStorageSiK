--[[
	GlobalStorageSiK - Pestaña Red (4 sub-pestañas independientes)
	Autor: SiK
	Fecha: 2025-06-29
	Descripción: Cada sub-pestaña (Red | Zonas | Admin | Nodos) tiene su propio
	             scroll con coordenadas locales desde Y=8. No hay cascade de Y
	             entre secciones. Añadir una nueva sección = nuevo archivo + nueva clave.
]]

require "ISUI/ISPanel"
require "ISUI/ISLabel"
require "GS_I18n"
require "GS_Sandbox"
require "GS_NetClient"
require "GS_UIDebug"
require "GS_TerminalUI_Scroll"
require "GS_TerminalUI_Permissions"
require "GS_TerminalUI_Chrome"
require "GS_Log"
require "GS_TerminalUI_NetworkStatus"
require "GS_TerminalUI_NetworkList"
require "GS_TerminalUI_NetworkTerminals"
require "GS_TerminalUI_Nodes"

GlobalStorageSiK.TerminalNetwork = {}

local T = GlobalStorageSiK.I18n.text
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local SECTION_GAP = 10
local NET_UI_VERSION = 23

-- Altura de la barra de sub-pestañas
local TAB_BAR_H = FONT_HGT_SMALL + 14
-- Orden de las sub-pestañas. "zonas" se retiró (v1.2.56): la gestión de
-- zonas desde la pestaña Nodos (crear/editar/eliminar, editor modal por
-- clic en cabecera) ya cubre todo lo que hacía esta sub-pestaña duplicada,
-- confirmado por el equipo tras validar el editor de zona modal.
-- "Nodos" primero y por defecto (v1.2.84): incluye la creación de zonas, es
-- lo primero que se necesita al configurar una red nueva - mas logico que
-- abrir siempre en "Red" (solo estado/nombre), que ahora va al final.
local TAB_KEYS = { "nodos", "admin", "red" }
local DEFAULT_TAB = "nodos"

-- ---------------------------------------------------------------------------
-- Helpers internos
-- ---------------------------------------------------------------------------

local function tabLabel(key)
	if key == "red"   then return T("IGUI_GS_SubTabRed") end
	if key == "admin" then return T("IGUI_GS_SubTabAdmin") end
	if key == "nodos" then return T("IGUI_GS_SubTabNodos") end
	return key
end

--- Comprueba que la UI de una sub-pestaña sigue válida (sin widgets huérfanos).
local function isTabUiHealthy(scroll, ui, key)
	if not ui or not ui.built or ui.version ~= NET_UI_VERSION then return false end
	if ui._tabKey ~= key then return false end
	local live = GlobalStorageSiK.TerminalScroll.isLiveWidget
	if key == "red" then
		return live(ui.stats and ui.stats.valPower) and live(ui.netListCard)
	elseif key == "admin" then
		return live(ui.termTableHost) and live(ui.floppyBlockCard)
	elseif key == "nodos" then
		return ui.built == true
	end
	return false
end

--- Construye los widgets fijos de una sub-pestaña (se llama una sola vez).
local function buildTabUi(scroll, terminal, key)
	GlobalStorageSiK.TerminalScroll.clear(scroll, false)
	local innerW = GlobalStorageSiK.TerminalScroll.contentWidth(scroll)
	-- Preservar zonas colapsadas si existía ui previa
	local prevUi = scroll._gsTabUi
	local ui = {
		built        = true,
		version      = NET_UI_VERSION,
		_tabKey      = key,
		stats        = {},
		collapsedZones = (prevUi and prevUi.collapsedZones) or {},
		permWidgets  = {},
		permsBuilt   = false,
		nodesEmbedBuilt = false,
		_lastInnerW  = innerW,
	}
	local y = 8
	if key == "red" then
		y = GlobalStorageSiK.TerminalNetworkList.build(scroll, terminal, ui, y, innerW)
		y = y + SECTION_GAP
		y = GlobalStorageSiK.TerminalNetworkStatus.build(scroll, terminal, ui, y, innerW)
	elseif key == "admin" then
		y = GlobalStorageSiK.TerminalNetworkTerminals.build(scroll, terminal, ui, y, innerW)
		y = y + SECTION_GAP
		-- El bloque de la Disquetera vivia aqui - retirado (v1.3.36): el
		-- Lector es ahora un addon mas, se instala/desinstala/consulta desde
		-- la bahia de expansion de la pestaña Addons (ver GS_ReaderAddon.lua),
		-- igual que Tablet/Craft/Builder, no un bloque aparte por su cuenta.
		-- Permissions se añaden en el primer sync (ensureInNetworkScroll)
	elseif key == "nodos" then
		-- Nodes embed se añade en el primer sync (embedInNetworkScroll)
	end
	ui.contentBottom = math.max(y + 16, 200)
	return ui
end

--- Garantiza que el tabPanel tiene un scroll creado y su UI es válida.
---@return ISPanel scroll
---@return table ui
local function ensureTabScroll(tabPanel, terminal, key)
	if not tabPanel.tabScroll then
		local w = math.max(180, tabPanel:getWidth())
		local h = math.max(160, tabPanel:getHeight())
		local scroll = GlobalStorageSiK.TerminalScroll.createInteractive(tabPanel, 0, 0, w, h)
		scroll:setVisible(true)
		tabPanel.tabScroll = scroll
	end
	local scroll = tabPanel.tabScroll
	if not isTabUiHealthy(scroll, scroll._gsTabUi, key) then
		local ui = buildTabUi(scroll, terminal, key)
		scroll._gsTabUi = ui
		scroll._gsNetUi = ui  -- backward compat para código externo que lee _gsNetUi
	end
	return scroll, scroll._gsTabUi
end

--- Sincroniza y posiciona los widgets de una sub-pestaña concreta.
--- Devuelve el Y de fondo del contenido.
local function syncTabContent(scroll, ui, terminal, key, state, innerW)
	local y = 8
	if key == "red" then
		GlobalStorageSiK.TerminalNetworkList.sync(ui, state)
		GlobalStorageSiK.TerminalNetworkStatus.sync(ui, state)
		GlobalStorageSiK.TerminalNetworkList.layout(scroll, ui, innerW)
		GlobalStorageSiK.TerminalNetworkStatus.layout(scroll, ui, innerW)
		y = ui.block1EndY or y

	elseif key == "admin" then
		GlobalStorageSiK.TerminalNetworkTerminals.sync(ui, state)
		GlobalStorageSiK.TerminalNetworkTerminals.layout(scroll, ui, innerW)
		y = (ui.termBlockEndY or y) + SECTION_GAP
		if GlobalStorageSiK.TerminalPermissions.shouldShowTab() then
			y = GlobalStorageSiK.TerminalPermissions.ensureInNetworkScroll(scroll, terminal, ui, state, y)
		else
			ui.permEndY = y
		end
		y = ui.permEndY or y

	elseif key == "nodos" then
		y = GlobalStorageSiK.TerminalNodes.embedInNetworkScroll(scroll, terminal, ui, 8, innerW)
		ui.block3EndY = y
	end
	return y
end

--- Aplica geometría interna de una sub-pestaña (anchos, Y-positions) sin re-sincronizar datos.
local function layoutTabUiInternal(scroll, ui, key, innerW)
	if not ui or not ui.built then return end
	if key == "red" then
		GlobalStorageSiK.TerminalNetworkList.layout(scroll, ui, innerW)
		GlobalStorageSiK.TerminalNetworkStatus.layout(scroll, ui, innerW)

	elseif key == "admin" then
		GlobalStorageSiK.TerminalNetworkTerminals.layout(scroll, ui, innerW)
		local permStartY = (ui.termBlockEndY or 8) + SECTION_GAP
		GlobalStorageSiK.TerminalPermissions.repositionBlock(scroll, ui, permStartY)
		GlobalStorageSiK.TerminalPermissions.layoutInNetworkScroll(scroll, ui, innerW)

	elseif key == "nodos" then
		if ui.nodesEmbedPanel and GlobalStorageSiK.TerminalScroll.isLiveWidget(ui.nodesEmbedPanel) then
			local embedH = (GlobalStorageSiK.TerminalNodes.embedPanelHeight
				and GlobalStorageSiK.TerminalNodes.embedPanelHeight())
				or math.max(140, ui.nodesEmbedPanel:getHeight() or 140)
			GlobalStorageSiK.TerminalScroll.setContentY(scroll, ui.nodesEmbedPanel, 8)
			ui.nodesEmbedPanel:setWidth(innerW)
			ui.nodesEmbedPanel:setHeight(embedH)
			GlobalStorageSiK.TerminalNodes.layout(ui.nodesEmbedPanel, innerW, embedH, 0, 0)
		end
	end
end

-- ---------------------------------------------------------------------------
-- Barra de sub-pestañas
-- ---------------------------------------------------------------------------

local function updateTabButtonStyles(networkPanel)
	local active = networkPanel.activeSubTab or DEFAULT_TAB
	local pal = GlobalStorageSiK.TerminalChrome.PALETTE
	for key, btn in pairs(networkPanel.tabButtons or {}) do
		if btn then
			btn._gsActive = (key == active)
			if btn._gsActive then
				btn.backgroundColor = { r = pal.accent[1], g = pal.accent[2], b = pal.accent[3], a = 0.15 }
			else
				btn.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
			end
		end
	end
end

local function switchSubTab(networkPanel, key)
	if GlobalStorageSiK.UIDebug then
		GlobalStorageSiK.UIDebug.action("network.switchSubTab", key)
	end
	networkPanel.activeSubTab = key
	for k, panel in pairs(networkPanel.tabPanels or {}) do
		if panel then panel:setVisible(k == key) end
	end
	updateTabButtonStyles(networkPanel)
end

local function buildTabBar(networkPanel, terminal)
	local pal = GlobalStorageSiK.TerminalChrome.PALETTE
	local barW = math.max(80, networkPanel:getWidth())

	local bar = ISPanel:new(0, 0, barW, TAB_BAR_H)
	bar:initialise()
	bar.drawBackground = true
	bar.borderColor = { r = 0, g = 0, b = 0, a = 0 }
	bar.backgroundColor = { r = pal.cardBg[1] or 0.06, g = pal.cardBg[2] or 0.06, b = pal.cardBg[3] or 0.08, a = 1 }
	bar.prerender = function(self)
		ISPanel.prerender(self)
		local d = GlobalStorageSiK.TerminalChrome.PALETTE.divider
		self:drawRect(0, self.height - 1, self.width, 1, 0.9, d[1] or 0.18, d[2] or 0.18, d[3] or 0.22)
	end
	networkPanel:addChild(bar)
	networkPanel.tabBar = bar
	networkPanel.tabButtons = {}

	local count = #TAB_KEYS
	local btnW = math.floor(barW / count)
	for i, key in ipairs(TAB_KEYS) do
		local bx = (i - 1) * btnW
		local bw = (i == count) and (barW - bx) or btnW
		local btn = ISPanel:new(bx, 0, bw, TAB_BAR_H)
		btn:initialise()
		btn.drawBackground = true
		btn.borderColor = { r = 0, g = 0, b = 0, a = 0 }
		btn.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
		btn._gsTabKey = key
		btn._gsNetworkPanel = networkPanel
		btn._gsTerminal = terminal
		btn._gsLabel = tabLabel(key)
		btn.prerender = function(self)
			ISPanel.prerender(self)
			local p = GlobalStorageSiK.TerminalChrome.PALETTE
			local active = self._gsActive
			local tr = active and p.textPrimary[1] or p.textMuted[1]
			local tg = active and p.textPrimary[2] or p.textMuted[2]
			local tb = active and p.textPrimary[3] or p.textMuted[3]
			local lbl = self._gsLabel or ""
			local tw = getTextManager():MeasureStringX(UIFont.Small, lbl)
			local tx = math.max(2, math.floor((self.width - tw) / 2))
			local ty = math.floor((self.height - FONT_HGT_SMALL) / 2)
			self:drawText(lbl, tx, ty, tr, tg, tb, 1, UIFont.Small)
			if active then
				self:drawRect(0, self.height - 2, self.width, 2, 1, p.accent[1], p.accent[2], p.accent[3])
			end
			-- Separador vertical entre botones (excepto el último)
			if self._gsTabKey ~= TAB_KEYS[#TAB_KEYS] then
				local d = p.divider
				self:drawRect(self.width - 1, 3, 1, self.height - 6, 0.5, d[1] or 0.18, d[2] or 0.18, d[3] or 0.22)
			end
		end
		btn.onMouseUp = function(self, mx, my)
			local np = self._gsNetworkPanel
			local term = self._gsTerminal
			if not np or not self._gsTabKey then return end
			switchSubTab(np, self._gsTabKey)
			-- Refrescar la pestaña recién activada con los datos actuales
			if term and term.terminalState then
				GlobalStorageSiK.TerminalNetwork.refreshActiveTab(term, term.terminalState)
			end
		end
		bar:addChild(btn)
		networkPanel.tabButtons[key] = btn
	end
end

-- ---------------------------------------------------------------------------
-- API pública
-- ---------------------------------------------------------------------------

--- Crea la estructura de la pestaña Red: barra de sub-pestañas + 4 paneles de contenido.
---@param terminal GS_TerminalUI
---@param networkPanel ISPanel
function GlobalStorageSiK.TerminalNetwork.buildZonesSection(terminal, networkPanel)
	if networkPanel.netZonesBuilt then return end
	networkPanel.netZonesBuilt = true
	networkPanel.activeSubTab = DEFAULT_TAB
	networkPanel.tabPanels = {}

	buildTabBar(networkPanel, terminal)

	local contentY = TAB_BAR_H
	local w = math.max(80, networkPanel:getWidth())
	local h = networkPanel:getHeight()
	for _, key in ipairs(TAB_KEYS) do
		local panel = ISPanel:new(0, contentY, w, math.max(160, h - contentY))
		panel:initialise()
		panel.drawBackground = false
		panel.borderColor = { r = 0, g = 0, b = 0, a = 0 }
		networkPanel:addChild(panel)
		networkPanel.tabPanels[key] = panel
		panel:setVisible(key == networkPanel.activeSubTab)
	end

	-- networkMainScroll se asigna al primer ensureTabScroll de "red" (backward compat)
	networkPanel.networkMainScroll = nil
	updateTabButtonStyles(networkPanel)
end

--- Activa una sub-pestaña de Red por clave ("nodos"/"admin"/"red") desde
--- fuera de este fichero - misma lógica que el clic del propio botón (ver
--- onMouseUp más arriba). Usado para abrir el terminal directamente en
--- Red > Nodos tras instalar un terminal con éxito.
---@param terminal GS_TerminalUI
---@param key string
function GlobalStorageSiK.TerminalNetwork.activateSubTab(terminal, key)
	local np = terminal and terminal.networkPanel
	if not np or not np.tabPanels or not np.tabPanels[key] then
		return
	end
	switchSubTab(np, key)
	if terminal.terminalState then
		GlobalStorageSiK.TerminalNetwork.refreshActiveTab(terminal, terminal.terminalState)
	end
end

--- Refresca solo la sub-pestaña activa (usado al cambiar de pestaña).
---@param terminal GS_TerminalUI
---@param state table|nil
function GlobalStorageSiK.TerminalNetwork.refreshActiveTab(terminal, state)
	local np = terminal.networkPanel
	if not np or not np.tabPanels then return end
	local key = np.activeSubTab or DEFAULT_TAB
	local tabPanel = np.tabPanels[key]
	if not tabPanel then return end

	state = state or terminal.terminalState or {}
	local scroll, ui = ensureTabScroll(tabPanel, terminal, key)

	-- Actualizar networkMainScroll si el activo es "red" (backward compat)
	if key == "red" then np.networkMainScroll = scroll end

	local innerW = GlobalStorageSiK.TerminalScroll.contentWidth(scroll)
	local savedOffset = GlobalStorageSiK.TerminalScroll.getScrollOffset(scroll)

	local y = 8
	local ok, err = pcall(function()
		y = syncTabContent(scroll, ui, terminal, key, state, innerW)
	end)
	if not ok then
		GlobalStorageSiK.Log.error("TerminalUI", "refreshActiveTab failed", "tab=" .. tostring(key) .. " error=" .. tostring(err))
	end

	local contentBottom = math.max((y or 8) + 16, 200)
	ui.contentBottom = contentBottom
	GlobalStorageSiK.TerminalScroll.setContentHeight(scroll, contentBottom)
	GlobalStorageSiK.TerminalScroll.setScrollOffset(scroll, savedOffset)
	GlobalStorageSiK.TerminalScroll.resetNeatScrollDelta(scroll)
end

--- Refresca todas las sub-pestañas al recibir datos nuevos del servidor.
---@param terminal GS_TerminalUI
---@param state table|nil
function GlobalStorageSiK.TerminalNetwork.refreshScroll(terminal, state)
	local np = terminal.networkPanel
	if not np or not np.tabPanels then return end
	if np._gsNetRefreshing then return end
	np._gsNetRefreshing = true

	state = state or terminal.terminalState or {}

	-- Solicitar lista de redes si todavía no ha llegado
	if not np._gsNetListRequested and (not state.networks or #state.networks == 0) then
		np._gsNetListRequested = true
		if GlobalStorageSiK.NetClient then
			GlobalStorageSiK.NetClient.sendCommand("getNetworkList", {})
		end
	end

	local activeKey = np.activeSubTab or DEFAULT_TAB
	for _, key in ipairs(TAB_KEYS) do
		local tabPanel = np.tabPanels[key]
		if tabPanel then
			local scroll, ui = ensureTabScroll(tabPanel, terminal, key)
			if key == "red" then np.networkMainScroll = scroll end

			local innerW = GlobalStorageSiK.TerminalScroll.contentWidth(scroll)
			local savedOffset = (key == activeKey) and GlobalStorageSiK.TerminalScroll.getScrollOffset(scroll) or 0

			local y = 8
			local ok, err = pcall(function()
				y = syncTabContent(scroll, ui, terminal, key, state, innerW)
			end)
			if not ok then
				GlobalStorageSiK.Log.error("TerminalUI", "refreshScroll failed", "tab=" .. tostring(key) .. " error=" .. tostring(err))
			end

			local contentBottom = math.max((y or 8) + 16, 200)
			ui.contentBottom = contentBottom
			GlobalStorageSiK.TerminalScroll.setContentHeight(scroll, contentBottom)
			if key == activeKey then
				GlobalStorageSiK.TerminalScroll.setScrollOffset(scroll, savedOffset)
			end
			GlobalStorageSiK.TerminalScroll.resetNeatScrollDelta(scroll)
		end
	end

	np._gsNetRefreshing = false
end

--- Alias de compatibilidad (código externo puede llamar layoutUi con scroll+ui).
---@param scroll ISPanel
---@param ui table
function GlobalStorageSiK.TerminalNetwork.layoutUi(scroll, ui)
	if not ui or not ui.built then return end
	local innerW = GlobalStorageSiK.TerminalScroll.contentWidth(scroll)
	layoutTabUiInternal(scroll, ui, ui._tabKey or DEFAULT_TAB, innerW)
end

--- Solo geometría: ajusta tamaños al cambiar dimensiones de ventana.
---@param terminal GS_TerminalUI
function GlobalStorageSiK.TerminalNetwork.syncScrollLayout(terminal)
	local np = terminal.networkPanel
	if not np or not np.tabPanels then return end
	local activeKey = np.activeSubTab or DEFAULT_TAB
	local tabPanel = np.tabPanels[activeKey]
	if not tabPanel or not tabPanel.tabScroll then return end

	local scroll = tabPanel.tabScroll
	local ui = scroll._gsTabUi
	if not ui then return end

	local newInnerW = GlobalStorageSiK.TerminalScroll.contentWidth(scroll)
	if ui._lastInnerW and math.abs(newInnerW - ui._lastInnerW) > 1 then
		-- Ancho cambió: rebuild de la pestaña activa
		scroll._gsTabUi = nil
		GlobalStorageSiK.TerminalNetwork.refreshActiveTab(terminal, terminal.terminalState)
		if scroll._gsTabUi then scroll._gsTabUi._lastInnerW = newInnerW end
		return
	end

	local savedOffset = GlobalStorageSiK.TerminalScroll.getScrollOffset(scroll)
	GlobalStorageSiK.TerminalScroll.setContentHeight(scroll, ui.contentBottom or 200)
	GlobalStorageSiK.TerminalScroll.setScrollOffset(scroll, savedOffset)
	GlobalStorageSiK.TerminalScroll.resetNeatScrollDelta(scroll)
	GlobalStorageSiK.TerminalScroll.ensureScrollBars(scroll)
end

--- Layout externo: resize de barra y paneles de contenido al cambiar tamaño de ventana.
---@param terminal GS_TerminalUI
---@param innerW number
---@param innerH number
function GlobalStorageSiK.TerminalNetwork.layout(terminal, innerW, innerH)
	local np = terminal.networkPanel
	if not np then return end

	-- Redimensionar barra de sub-pestañas
	if np.tabBar then
		np.tabBar:setWidth(innerW)
		-- Redistribuir botones
		local count = #TAB_KEYS
		local btnW = math.floor(innerW / count)
		for i, key in ipairs(TAB_KEYS) do
			local btn = np.tabButtons and np.tabButtons[key]
			if btn then
				local bx = (i - 1) * btnW
				local bw = (i == count) and (innerW - bx) or btnW
				btn:setX(bx)
				btn:setWidth(bw)
			end
		end
	end

	-- Redimensionar paneles de contenido
	local contentY = TAB_BAR_H
	local contentH = math.max(160, innerH - contentY)
	local activeKey = np.activeSubTab or DEFAULT_TAB
	for _, key in ipairs(TAB_KEYS) do
		local panel = np.tabPanels and np.tabPanels[key]
		if panel then
			panel:setX(0)
			panel:setY(contentY)
			panel:setWidth(innerW)
			panel:setHeight(contentH)
			panel:setVisible(key == activeKey)
			if panel.tabScroll then
				GlobalStorageSiK.TerminalScroll.resize(panel.tabScroll, innerW, contentH)
			end
		end
	end

	if terminal.activeTabKey == "network" then
		GlobalStorageSiK.TerminalNetwork.syncScrollLayout(terminal)
	end
end

--- Alias de compatibilidad (no usado internamente, pero puede llamarse desde legacy).
function GlobalStorageSiK.TerminalNetwork.ensureUi(terminal, scroll)
	return scroll and scroll._gsTabUi or {}
end

--- Devuelve todos los scrolls de sub-pestañas del terminal (usado por Scroll utils).
---@param terminal GS_TerminalUI
---@return ISPanel[]
function GlobalStorageSiK.TerminalNetwork.getAllTabScrolls(terminal)
	local result = {}
	local np = terminal and terminal.networkPanel
	if not np or not np.tabPanels then
		-- Backward compat: si todavía existe networkMainScroll solo
		if np and np.networkMainScroll then
			result[1] = np.networkMainScroll
		end
		return result
	end
	for _, key in ipairs(TAB_KEYS) do
		local panel = np.tabPanels[key]
		if panel and panel.tabScroll then
			result[#result + 1] = panel.tabScroll
		end
	end
	return result
end
