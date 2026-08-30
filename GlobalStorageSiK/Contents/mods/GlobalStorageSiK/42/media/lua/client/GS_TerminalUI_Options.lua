--[[
	GlobalStorageSiK - Pestaña Configuración (2 sub-pestañas: Admin | Estado)
	Autor: SiK
	Fecha: 2026-08-26
	Descripción: Pestaña fija nueva - aloja lo que antes vivía como sub-pestañas
	             "admin"/"red" dentro de la pestaña Red (ver GS_TerminalUI_Network.lua,
	             ahora simplificada a solo "Zonas y nodos"). Mismo patrón de barra de
	             sub-pestañas + scroll por sub-pestaña que tenía Red antes de dev41.
]]

require "ISUI/ISPanel"
require "ISUI/ISLabel"
require "GS_I18n"
require "GS_Sandbox"
require "GS_NetClient"
require "GS_UIDebug"
require "GS_TerminalUI_Scroll"
require "GS_TerminalUI_Permissions"
require "GS_SiK_UI_Core"
require "GS_SiK_UI_Metrics"
require "GS_SiK_UI_Controls"
require "GS_Log"
require "GS_TerminalUI_NetworkStatus"
require "GS_TerminalUI_NetworkList"
require "GS_TerminalUI_NetworkTerminals"

GlobalStorageSiK.TerminalOptions = {}

local T = GlobalStorageSiK.I18n.text
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local CONTROL_METRICS = GlobalStorageSiK.SiK_UI.Controls.metrics("standard")
local SECTION_GAP = CONTROL_METRICS.rowGap
local OPTIONS_UI_VERSION = 2

-- Altura de la barra de sub-pestañas
local TAB_BAR_H = CONTROL_METRICS.buttonHeight
local OPTIONS_TITLE_H = CONTROL_METRICS.sectionHeight + 16
-- Orden visual validado: Estado primero y activo; Admin despues.
local TAB_KEYS = { "estado", "admin" }
local DEFAULT_TAB = "estado"

-- ---------------------------------------------------------------------------
-- Helpers internos
-- ---------------------------------------------------------------------------

local function tabLabel(key)
	-- IGUI_GS_SubTabRed reutilizada: la clave conserva su nombre historico
	-- (antes decia "Red"/"Network") pero el VALOR paso a "Estado"/"Status"
	-- en los 10 idiomas al mudar esta sub-pestaña aqui (dev41) - evita crear
	-- una clave i18n nueva para lo mismo que ya existia con otro texto.
	if key == "estado" then return T("IGUI_GS_SubTabRed") end
	if key == "admin"  then return T("IGUI_GS_SubTabAdmin") end
	return key
end

--- Comprueba que la UI de una sub-pestaña sigue válida (sin widgets huérfanos).
local function isTabUiHealthy(scroll, ui, key)
	if not ui or not ui.built or ui.version ~= OPTIONS_UI_VERSION then return false end
	if ui._tabKey ~= key then return false end
	local live = GlobalStorageSiK.TerminalScroll.isLiveWidget
	if key == "estado" then
		return live(ui.stats and ui.stats.valPower) and live(ui.netListCard)
	elseif key == "admin" then
		-- BUG REAL encontrado (2026-08-26, al tocar este fichero por otro
		-- motivo): comprobaba ademas "ui.floppyBlockCard", un campo que ya no
		-- existe desde que la Disquetera se convirtio en addon (ver
		-- comentario historico en GS_TerminalUI_Network.lua) - live(nil) daba
		-- SIEMPRE false, asi que esta sub-pestaña se reconstruia entera en
		-- CADA sincronizacion en vez de solo cuando de verdad hacia falta.
		return live(ui.termTableHost)
	end
	return false
end

--- Construye los widgets fijos de una sub-pestaña (se llama una sola vez).
local function buildTabUi(scroll, terminal, key)
	GlobalStorageSiK.TerminalScroll.clear(scroll, false)
	local innerW = GlobalStorageSiK.TerminalScroll.contentWidth(scroll)
	local ui = {
		built        = true,
		version      = OPTIONS_UI_VERSION,
		_tabKey      = key,
		stats        = {},
		permWidgets  = {},
		permsBuilt   = false,
		_lastInnerW  = innerW,
		_lastInnerH  = scroll.height or 0,
	}
	local y = 8
	if key == "estado" then
		y = GlobalStorageSiK.TerminalNetworkList.build(scroll, terminal, ui, y, innerW)
		y = y + SECTION_GAP
		y = GlobalStorageSiK.TerminalNetworkStatus.build(scroll, terminal, ui, y, innerW)
	elseif key == "admin" then
		y = GlobalStorageSiK.TerminalNetworkTerminals.build(scroll, terminal, ui, y, innerW)
		y = y + SECTION_GAP
		-- Permissions se añade en el primer sync (ensureInNetworkScroll)
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
		GlobalStorageSiK.TerminalScroll.setOnContentRectChanged(scroll, function(changedScroll)
			local currentUi = changedScroll._gsTabUi
			if currentUi and GlobalStorageSiK.TerminalOptions.layoutUi then
				GlobalStorageSiK.TerminalOptions.layoutUi(changedScroll, currentUi)
				currentUi._lastInnerW = GlobalStorageSiK.TerminalScroll.contentWidth(changedScroll)
			end
		end)
		scroll:setVisible(true)
		tabPanel.tabScroll = scroll
	end
	local scroll = tabPanel.tabScroll
	if not isTabUiHealthy(scroll, scroll._gsTabUi, key) then
		local ui = buildTabUi(scroll, terminal, key)
		scroll._gsTabUi = ui
	end
	return scroll, scroll._gsTabUi
end

--- Sincroniza y posiciona los widgets de una sub-pestaña concreta.
--- Devuelve el Y de fondo del contenido.
local function syncTabContent(scroll, ui, terminal, key, state, innerW)
	local y = 8
	if key == "estado" then
		GlobalStorageSiK.TerminalNetworkList.sync(ui, state)
		GlobalStorageSiK.TerminalNetworkStatus.sync(ui, state)
		GlobalStorageSiK.TerminalNetworkList.layout(scroll, ui, innerW)
		GlobalStorageSiK.TerminalNetworkStatus.layout(scroll, ui, innerW)
		y = ui.paletteEndY or ui.block1EndY or y

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
	end
	return y
end

--- Aplica geometría interna de una sub-pestaña (anchos, Y-positions) sin re-sincronizar datos.
local function layoutTabUiInternal(scroll, ui, key, innerW)
	if not ui or not ui.built then return end
	if key == "estado" then
		GlobalStorageSiK.TerminalNetworkList.layout(scroll, ui, innerW)
		GlobalStorageSiK.TerminalNetworkStatus.layout(scroll, ui, innerW)

	elseif key == "admin" then
		GlobalStorageSiK.TerminalNetworkTerminals.layout(scroll, ui, innerW)
		local permStartY = (ui.termBlockEndY or 8) + SECTION_GAP
		GlobalStorageSiK.TerminalPermissions.repositionBlock(scroll, ui, permStartY)
		GlobalStorageSiK.TerminalPermissions.layoutInNetworkScroll(scroll, ui, innerW)
	end
end

-- ---------------------------------------------------------------------------
-- Barra de sub-pestañas
-- ---------------------------------------------------------------------------

local function updateTabButtonStyles(optionsPanel)
	local active = optionsPanel.activeSubTab or DEFAULT_TAB
	local pal = GlobalStorageSiK.SiK_UI.PALETTE
	for key, btn in pairs(optionsPanel.tabButtons or {}) do
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

local function switchSubTab(optionsPanel, key)
	if GlobalStorageSiK.UIDebug then
		GlobalStorageSiK.UIDebug.action("options.switchSubTab", key)
	end
	optionsPanel.activeSubTab = key
	for k, panel in pairs(optionsPanel.tabPanels or {}) do
		if panel then panel:setVisible(k == key) end
	end
	updateTabButtonStyles(optionsPanel)
end

local function buildTabBar(optionsPanel, terminal)
	local pal = GlobalStorageSiK.SiK_UI.PALETTE
	local barW = math.max(80, optionsPanel:getWidth())

	local bar = ISPanel:new(0, OPTIONS_TITLE_H, barW, TAB_BAR_H)
	bar:initialise()
	bar.drawBackground = true
	bar.borderColor = { r = 0, g = 0, b = 0, a = 0 }
	bar.backgroundColor = { r = pal.cardBg[1] or 0.06, g = pal.cardBg[2] or 0.06, b = pal.cardBg[3] or 0.08, a = 1 }
	bar.prerender = function(self)
		ISPanel.prerender(self)
		local d = GlobalStorageSiK.SiK_UI.PALETTE.divider
		self:drawRect(0, self.height - 1, self.width, 1, 0.9, d[1] or 0.18, d[2] or 0.18, d[3] or 0.22)
	end
	optionsPanel:addChild(bar)
	optionsPanel.tabBar = bar
	optionsPanel.tabButtons = {}

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
		btn._gsOptionsPanel = optionsPanel
		btn._gsTerminal = terminal
		btn._gsLabel = tabLabel(key)
		btn.prerender = function(self)
			ISPanel.prerender(self)
			local p = GlobalStorageSiK.SiK_UI.PALETTE
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
			if self._gsTabKey ~= TAB_KEYS[#TAB_KEYS] then
				local d = p.divider
				self:drawRect(self.width - 1, 3, 1, self.height - 6, 0.5, d[1] or 0.18, d[2] or 0.18, d[3] or 0.22)
			end
		end
		btn.onMouseUp = function(self, mx, my)
			local op = self._gsOptionsPanel
			local term = self._gsTerminal
			if not op or not self._gsTabKey then return end
			switchSubTab(op, self._gsTabKey)
			if term and term.terminalState then
				GlobalStorageSiK.TerminalOptions.refreshActiveTab(term, term.terminalState)
			end
		end
		bar:addChild(btn)
		optionsPanel.tabButtons[key] = btn
	end
end

-- ---------------------------------------------------------------------------
-- API pública
-- ---------------------------------------------------------------------------

--- Crea la estructura de la pestaña Configuración: barra de sub-pestañas + 2 paneles de contenido.
---@param terminal GS_TerminalUI
---@param optionsPanel ISPanel
function GlobalStorageSiK.TerminalOptions.buildSection(terminal, optionsPanel)
	if optionsPanel.optBuilt then return end
	optionsPanel.optBuilt = true
	optionsPanel.activeSubTab = DEFAULT_TAB
	optionsPanel.tabPanels = {}

	optionsPanel.optionsTitle = GlobalStorageSiK.SiK_UI.Controls.sectionTitle(optionsPanel, {
		x = 8, y = 8, text = T("IGUI_GS_TabConfig"),
	})
	buildTabBar(optionsPanel, terminal)

	local contentY = OPTIONS_TITLE_H + TAB_BAR_H
	local w = math.max(80, optionsPanel:getWidth())
	local h = optionsPanel:getHeight()
	for _, key in ipairs(TAB_KEYS) do
		local panel = ISPanel:new(0, contentY, w, math.max(160, h - contentY))
		panel:initialise()
		panel.drawBackground = false
		panel.borderColor = { r = 0, g = 0, b = 0, a = 0 }
		optionsPanel:addChild(panel)
		optionsPanel.tabPanels[key] = panel
		panel:setVisible(key == optionsPanel.activeSubTab)
	end

	updateTabButtonStyles(optionsPanel)
end

--- Activa una sub-pestaña de Configuración por clave ("admin"/"estado") desde
--- fuera de este fichero - misma lógica que el clic del propio botón.
---@param terminal GS_TerminalUI
---@param key string
function GlobalStorageSiK.TerminalOptions.activateSubTab(terminal, key)
	local op = terminal and terminal.configPanel
	if not op or not op.tabPanels or not op.tabPanels[key] then
		return
	end
	switchSubTab(op, key)
	if terminal.terminalState then
		GlobalStorageSiK.TerminalOptions.refreshActiveTab(terminal, terminal.terminalState)
	end
end

--- Refresca solo la sub-pestaña activa (usado al cambiar de pestaña).
---@param terminal GS_TerminalUI
---@param state table|nil
function GlobalStorageSiK.TerminalOptions.refreshActiveTab(terminal, state)
	local op = terminal.configPanel
	if not op or not op.tabPanels then return end
	local key = op.activeSubTab or DEFAULT_TAB
	local tabPanel = op.tabPanels[key]
	if not tabPanel then return end

	state = state or terminal.terminalState or {}
	local scroll, ui = ensureTabScroll(tabPanel, terminal, key)

	local innerW = GlobalStorageSiK.TerminalScroll.contentWidth(scroll)
	local savedOffset = GlobalStorageSiK.TerminalScroll.getScrollOffset(scroll)

	local y = 8
	local ok, err = pcall(function()
		y = syncTabContent(scroll, ui, terminal, key, state, innerW)
	end)
	if not ok then
		GlobalStorageSiK.Log.error("TerminalUI", "Options.refreshActiveTab failed", "tab=" .. tostring(key) .. " error=" .. tostring(err))
	end

	local contentBottom = math.max((y or 8) + 16, 200)
	ui.contentBottom = contentBottom
	ui._lastInnerH = scroll.height or 0
	GlobalStorageSiK.TerminalScroll.setContentHeight(scroll, contentBottom)
	GlobalStorageSiK.TerminalScroll.setScrollOffset(scroll, savedOffset)
end

--- Refresca todas las sub-pestañas al recibir datos nuevos del servidor.
---@param terminal GS_TerminalUI
---@param state table|nil
function GlobalStorageSiK.TerminalOptions.refreshScroll(terminal, state)
	local op = terminal.configPanel
	if not op or not op.tabPanels then return end
	if op._gsOptRefreshing then return end
	op._gsOptRefreshing = true

	state = state or terminal.terminalState or {}

	if not op._gsNetListRequested and (not state.networks or #state.networks == 0) then
		op._gsNetListRequested = true
		if GlobalStorageSiK.NetClient then
			GlobalStorageSiK.NetClient.sendCommand("getNetworkList", {})
		end
	end

	local activeKey = op.activeSubTab or DEFAULT_TAB
	for _, key in ipairs(TAB_KEYS) do
		local tabPanel = op.tabPanels[key]
		if tabPanel then
			local scroll, ui = ensureTabScroll(tabPanel, terminal, key)

			local innerW = GlobalStorageSiK.TerminalScroll.contentWidth(scroll)
			local savedOffset = (key == activeKey) and GlobalStorageSiK.TerminalScroll.getScrollOffset(scroll) or 0

			local y = 8
			local ok, err = pcall(function()
				y = syncTabContent(scroll, ui, terminal, key, state, innerW)
			end)
			if not ok then
				GlobalStorageSiK.Log.error("TerminalUI", "Options.refreshScroll failed", "tab=" .. tostring(key) .. " error=" .. tostring(err))
			end

			local contentBottom = math.max((y or 8) + 16, 200)
			ui.contentBottom = contentBottom
			ui._lastInnerH = scroll.height or 0
			GlobalStorageSiK.TerminalScroll.setContentHeight(scroll, contentBottom)
			if key == activeKey then
				GlobalStorageSiK.TerminalScroll.setScrollOffset(scroll, savedOffset)
			end
		end
	end

	op._gsOptRefreshing = false
end

--- Alias de compatibilidad (código externo puede llamar layoutUi con scroll+ui).
---@param scroll ISPanel
---@param ui table
function GlobalStorageSiK.TerminalOptions.layoutUi(scroll, ui)
	if not ui or not ui.built then return end
	local innerW = GlobalStorageSiK.TerminalScroll.contentWidth(scroll)
	layoutTabUiInternal(scroll, ui, ui._tabKey or DEFAULT_TAB, innerW)
end

--- Solo geometría: ajusta tamaños al cambiar dimensiones de ventana.
---@param terminal GS_TerminalUI
function GlobalStorageSiK.TerminalOptions.syncScrollLayout(terminal)
	local op = terminal.configPanel
	if not op or not op.tabPanels then return end
	local activeKey = op.activeSubTab or DEFAULT_TAB
	local tabPanel = op.tabPanels[activeKey]
	if not tabPanel or not tabPanel.tabScroll then return end

	local scroll = tabPanel.tabScroll
	local ui = scroll._gsTabUi
	if not ui then return end

	local newInnerW = GlobalStorageSiK.TerminalScroll.contentWidth(scroll)
	if ui._lastInnerW and math.abs(newInnerW - ui._lastInnerW) > 1 then
		scroll._gsTabUi = nil
		GlobalStorageSiK.TerminalOptions.refreshActiveTab(terminal, terminal.terminalState)
		if scroll._gsTabUi then scroll._gsTabUi._lastInnerW = newInnerW end
		return
	end
	local newInnerH = scroll.height or 0
	if not ui._lastInnerH or math.abs(newInnerH - ui._lastInnerH) > 1 then
		ui._lastInnerH = newInnerH
		GlobalStorageSiK.TerminalOptions.refreshActiveTab(terminal, terminal.terminalState)
		return
	end

	local savedOffset = GlobalStorageSiK.TerminalScroll.getScrollOffset(scroll)
	GlobalStorageSiK.TerminalScroll.setContentHeight(scroll, ui.contentBottom or 200)
	GlobalStorageSiK.TerminalScroll.setScrollOffset(scroll, savedOffset)
	GlobalStorageSiK.TerminalScroll.ensureScrollBars(scroll)
end

--- Layout externo: resize de barra y paneles de contenido al cambiar tamaño de ventana.
---@param terminal GS_TerminalUI
---@param innerW number
---@param innerH number
function GlobalStorageSiK.TerminalOptions.layout(terminal, innerW, innerH)
	local op = terminal.configPanel
	if not op then return end

	if op.tabBar then
		op.tabBar:setY(OPTIONS_TITLE_H)
		op.tabBar:setWidth(innerW)
		local count = #TAB_KEYS
		local btnW = math.floor(innerW / count)
		for i, key in ipairs(TAB_KEYS) do
			local btn = op.tabButtons and op.tabButtons[key]
			if btn then
				local bx = (i - 1) * btnW
				local bw = (i == count) and (innerW - bx) or btnW
				btn:setX(bx)
				btn:setWidth(bw)
			end
		end
	end

	if op.optionsTitle then
		op.optionsTitle:setX(8)
		op.optionsTitle:setY(8)
	end
	local contentY = OPTIONS_TITLE_H + TAB_BAR_H
	local contentH = math.max(160, innerH - contentY)
	local activeKey = op.activeSubTab or DEFAULT_TAB
	for _, key in ipairs(TAB_KEYS) do
		local panel = op.tabPanels and op.tabPanels[key]
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

	if terminal.activeTabKey == "config" then
		GlobalStorageSiK.TerminalOptions.syncScrollLayout(terminal)
	end
end

--- Alias de compatibilidad (no usado internamente, pero puede llamarse desde legacy).
function GlobalStorageSiK.TerminalOptions.ensureUi(terminal, scroll)
	return scroll and scroll._gsTabUi or {}
end

--- Devuelve todos los scrolls de sub-pestañas del terminal (usado por Scroll utils).
---@param terminal GS_TerminalUI
---@return ISPanel[]
function GlobalStorageSiK.TerminalOptions.getAllTabScrolls(terminal)
	local result = {}
	local op = terminal and terminal.configPanel
	if not op or not op.tabPanels then
		return result
	end
	for _, key in ipairs(TAB_KEYS) do
		local panel = op.tabPanels[key]
		if panel and panel.tabScroll then
			result[#result + 1] = panel.tabScroll
		end
	end
	return result
end
