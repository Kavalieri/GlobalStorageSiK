--[[
	GlobalStorageSiK - Pestaña Red ("Zonas y nodos", sin sub-pestañas)
	Autor: SiK
	Fecha: 2025-06-29 (simplificada 2026-08-26, dev41)
	Descripción: Hasta dev40 esta pestaña tenía 3 sub-pestañas propias
	             (Red | Admin | Nodos). Pedido explícito del usuario: Red se
	             queda SOLO con la tabla "Zonas y nodos" (creador de zonas +
	             tabla desplegable), ocupando toda la pestaña sin barra de
	             sub-pestañas; "Admin" y el antiguo resumen "Red" se mudan tal
	             cual a la nueva pestaña fija "Configuración" (ver
	             GS_TerminalUI_Options.lua). Mismo contenido, mismo Lua de
	             GS_TerminalUI_Nodes.lua, cero cambio de comportamiento interno.
]]

require "ISUI/ISPanel"
require "ISUI/ISLabel"
require "GS_I18n"
require "GS_TerminalUI_Scroll"
require "GS_Log"
require "GS_TerminalUI_Nodes"

GlobalStorageSiK.TerminalNetwork = {}

local NETWORK_UI_VERSION = 25

--- Comprueba que la UI del scroll único sigue válida (sin widgets huérfanos).
local function isUiHealthy(ui)
	return ui and ui.built and ui.version == NETWORK_UI_VERSION
end

--- Construye el estado persistente del scroll único (se llama una sola vez
--- por reconstrucción, p.ej. tras un cambio de ancho).
local function buildUi(scroll)
	GlobalStorageSiK.TerminalScroll.clear(scroll, false)
	local prevUi = scroll._gsNetUi
	return {
		built          = true,
		version        = NETWORK_UI_VERSION,
		collapsedZones = (prevUi and prevUi.collapsedZones) or {},
		nodesEmbedBuilt = false,
		_lastInnerW    = GlobalStorageSiK.TerminalScroll.contentWidth(scroll),
		_lastInnerH    = scroll.height or 0,
	}
end

--- Garantiza que networkPanel tiene un scroll creado y su UI es válida.
---@return ISPanel scroll
---@return table ui
local function ensureScroll(networkPanel)
	if not networkPanel.tabScroll then
		local w = math.max(180, networkPanel:getWidth())
		local h = math.max(160, networkPanel:getHeight())
		local scroll = GlobalStorageSiK.TerminalScroll.createInteractive(networkPanel, 0, 0, w, h)
		scroll:setVisible(true)
		networkPanel.tabScroll = scroll
	end
	local scroll = networkPanel.tabScroll
	if not isUiHealthy(scroll._gsNetUi) then
		scroll._gsNetUi = buildUi(scroll)
	end
	return scroll, scroll._gsNetUi
end

-- ---------------------------------------------------------------------------
-- API pública
-- ---------------------------------------------------------------------------

--- Marca la pestaña Red como construida (el scroll real se crea perezosamente
--- en el primer refresh, igual que antes).
---@param terminal GS_TerminalUI
---@param networkPanel ISPanel
function GlobalStorageSiK.TerminalNetwork.buildZonesSection(terminal, networkPanel)
	if networkPanel.netZonesBuilt then return end
	networkPanel.netZonesBuilt = true
	networkPanel.networkMainScroll = nil
end

--- Refresca el contenido (usado al cambiar a esta pestaña).
---@param terminal GS_TerminalUI
---@param state table|nil
function GlobalStorageSiK.TerminalNetwork.refreshActiveTab(terminal, state)
	GlobalStorageSiK.TerminalNetwork.refreshScroll(terminal, state)
end

--- Refresca el contenido al recibir datos nuevos del servidor.
---@param terminal GS_TerminalUI
---@param state table|nil
function GlobalStorageSiK.TerminalNetwork.refreshScroll(terminal, state)
	local np = terminal.networkPanel
	if not np then return end
	state = state or terminal.terminalState or {}

	local scroll, ui = ensureScroll(np)
	np.networkMainScroll = scroll

	local innerW = GlobalStorageSiK.TerminalScroll.contentWidth(scroll)
	local savedOffset = GlobalStorageSiK.TerminalScroll.getScrollOffset(scroll)

	local y = 8
	local ok, err = pcall(function()
		y = GlobalStorageSiK.TerminalNodes.embedInNetworkScroll(scroll, terminal, ui, y, innerW)
	end)
	if not ok then
		GlobalStorageSiK.Log.error("TerminalUI", "Network.refreshScroll failed", tostring(err))
	end

	local contentBottom = math.max((y or 8) + 16, 200)
	ui.contentBottom = contentBottom
	ui._lastInnerH = scroll.height or 0
	GlobalStorageSiK.TerminalScroll.setContentHeight(scroll, contentBottom)
	GlobalStorageSiK.TerminalScroll.setScrollOffset(scroll, savedOffset)
end

--- Alias de compatibilidad (código externo puede llamar layoutUi con scroll+ui).
---@param scroll ISPanel
---@param ui table
function GlobalStorageSiK.TerminalNetwork.layoutUi(scroll, ui)
	if not ui or not ui.built then return end
	if ui.nodesEmbedPanel and GlobalStorageSiK.TerminalScroll.isLiveWidget(ui.nodesEmbedPanel) then
		local innerW = GlobalStorageSiK.TerminalScroll.contentWidth(scroll)
		local embedH = ui.nodesEmbedHeight or math.max(140, ui.nodesEmbedPanel:getHeight() or 140)
		GlobalStorageSiK.TerminalScroll.setContentY(scroll, ui.nodesEmbedPanel, ui.nodesEmbedY or 8)
		ui.nodesEmbedPanel:setWidth(innerW)
		ui.nodesEmbedPanel:setHeight(embedH)
		GlobalStorageSiK.TerminalNodes.layout(ui.nodesEmbedPanel, innerW, embedH, 0, 0)
	end
end

--- Solo geometría: ajusta tamaños al cambiar dimensiones de ventana.
---@param terminal GS_TerminalUI
function GlobalStorageSiK.TerminalNetwork.syncScrollLayout(terminal)
	local np = terminal.networkPanel
	if not np or not np.tabScroll then return end

	local scroll = np.tabScroll
	local ui = scroll._gsNetUi
	if not ui then return end

	local newInnerW = GlobalStorageSiK.TerminalScroll.contentWidth(scroll)
	if ui._lastInnerW and math.abs(newInnerW - ui._lastInnerW) > 1 then
		scroll._gsNetUi = nil
		GlobalStorageSiK.TerminalNetwork.refreshScroll(terminal, terminal.terminalState)
		if scroll._gsNetUi then scroll._gsNetUi._lastInnerW = newInnerW end
		return
	end
	local newInnerH = scroll.height or 0
	if not ui._lastInnerH or math.abs(newInnerH - ui._lastInnerH) > 1 then
		ui._lastInnerH = newInnerH
		GlobalStorageSiK.TerminalNetwork.refreshScroll(terminal, terminal.terminalState)
		return
	end

	local savedOffset = GlobalStorageSiK.TerminalScroll.getScrollOffset(scroll)
	GlobalStorageSiK.TerminalScroll.setContentHeight(scroll, ui.contentBottom or 200)
	GlobalStorageSiK.TerminalScroll.setScrollOffset(scroll, savedOffset)
	GlobalStorageSiK.TerminalScroll.ensureScrollBars(scroll)
end

--- Layout externo: resize del panel de contenido al cambiar tamaño de ventana.
---@param terminal GS_TerminalUI
---@param innerW number
---@param innerH number
function GlobalStorageSiK.TerminalNetwork.layout(terminal, innerW, innerH)
	local np = terminal.networkPanel
	if not np then return end

	if np.tabScroll then
		GlobalStorageSiK.TerminalScroll.resize(np.tabScroll, innerW, innerH)
	end

	if terminal.activeTabKey == "network" then
		GlobalStorageSiK.TerminalNetwork.syncScrollLayout(terminal)
	end
end

--- Alias de compatibilidad (no usado internamente, pero puede llamarse desde legacy).
function GlobalStorageSiK.TerminalNetwork.ensureUi(terminal, scroll)
	return scroll and scroll._gsNetUi or {}
end

--- Devuelve el scroll de esta pestaña (usado por Scroll utils).
---@param terminal GS_TerminalUI
---@return ISPanel[]
function GlobalStorageSiK.TerminalNetwork.getAllTabScrolls(terminal)
	local np = terminal and terminal.networkPanel
	if np and np.tabScroll then
		return { np.tabScroll }
	end
	return {}
end
