--[[
	GlobalStorageSiK - Pestaña Addons del terminal
	Autor: SiK
	Fecha: 2025-06-27
	Descripción: Bahía de módulos, recetas craftables e instalación por terminal.
]]

require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISLabel"
require "GS_I18n"
require "GS_AddonRegistry"
require "GS_AddonRecipes"
require "GS_Addons"
require "GS_NetClient"
require "GS_Permissions"
require "GS_TerminalUI_Scroll"
require "GS_TerminalUI_Chrome"
require "GS_TerminalUI_AddonBay"
require "GS_TerminalRecipeCards"

GlobalStorageSiK.TerminalAddons = {}

local T = GlobalStorageSiK.I18n.text
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local BLOCK_GAP = 10
local BTN_H = FONT_HGT_SMALL + 10
local REFRESH_HOOKED = false
local REFRESH_DEBOUNCE_TICKS = 8
local _refreshDueTick = 0
local _refreshTickCounter = 0

---@param scroll ISPanel
---@param x number
---@param y number
---@param titleKey string
---@param innerW number
---@return number
local function addSectionTitle(scroll, x, y, titleKey, innerW)
	local title = T(titleKey)
	local lbl = GlobalStorageSiK.TerminalChrome.createSectionLabel(x, y, title)
	GlobalStorageSiK.TerminalScroll.addChild(scroll, lbl)
	return y + FONT_HGT_SMALL + 8
end

---@param scroll ISPanel
---@param x number
---@param y number
---@param text string
---@param maxW number
---@param r number
---@param g number
---@param b number
---@return number
local function addWrappedLabel(scroll, x, y, text, maxW, r, g, b)
	local lines = GlobalStorageSiK.TerminalChrome.wrapTextLines(text, maxW, UIFont.Small)
	for i = 1, #lines do
		local lbl = ISLabel:new(x, y, FONT_HGT_SMALL, lines[i], r, g, b, 1, UIFont.Small, true)
		lbl:initialise()
		GlobalStorageSiK.TerminalScroll.addChild(scroll, lbl)
		y = y + FONT_HGT_SMALL + 2
	end
	return y
end

--- Refresca la pestaña si está visible (debounced).
local function refreshVisibleAddonsTab()
	_refreshDueTick = _refreshTickCounter + REFRESH_DEBOUNCE_TICKS
end

--- Tick debounce para evitar tormenta de refrescos.
local function onAddonsDebounceTick()
	_refreshTickCounter = _refreshTickCounter + 1
	if _refreshDueTick <= 0 or _refreshTickCounter < _refreshDueTick then
		return
	end
	_refreshDueTick = 0
	local terminal = GlobalStorageSiK.TerminalUI and GlobalStorageSiK.TerminalUI.instance
	if not terminal or not terminal.getIsVisible or not terminal:isVisible() then
		return
	end
	if terminal.activeTabKey ~= "addons" or not terminal.addonsPanel then
		return
	end
	if terminal.refreshAddonRecipesState then
		terminal:refreshAddonRecipesState()
	end
	GlobalStorageSiK.TerminalAddons.refresh(terminal.addonsPanel, terminal)
end

--- Registra eventos de refresco en vivo (una sola vez).
function GlobalStorageSiK.TerminalAddons.ensureRefreshHooks()
	if REFRESH_HOOKED then
		return
	end
	REFRESH_HOOKED = true
	if Events and Events.OnReadLiterature then
		Events.OnReadLiterature.Add(refreshVisibleAddonsTab)
	end
	if Events and Events.OnContainerUpdate then
		Events.OnContainerUpdate.Add(refreshVisibleAddonsTab)
	end
	if Events and Events.OnTick then
		Events.OnTick.Add(onAddonsDebounceTick)
	end
end

---@param panel ISPanel
---@param terminal GS_TerminalUI
function GlobalStorageSiK.TerminalAddons.buildPanel(panel, terminal)
	if panel.addonsBuilt then
		return
	end
	panel.addonsBuilt = true
	panel.drawBackground = false
	panel.terminalRef = terminal
	local pad = terminal.padding or 8
	panel.addonsScroll = GlobalStorageSiK.TerminalScroll.create(panel, pad, 0, 280, 120)
	GlobalStorageSiK.TerminalAddons.ensureRefreshHooks()
end

---@param panel ISPanel
---@param innerW number
---@param innerH number
function GlobalStorageSiK.TerminalAddons.layout(panel, innerW, innerH)
	if not panel or not panel.addonsScroll then
		return
	end
	local pad = panel.padding or 8
	local y = pad
	local bottomPad = GlobalStorageSiK.TerminalScroll.listBottomGap()
	local scrollH = math.max(120, innerH - y - pad - bottomPad)
	panel.addonsScroll:setX(pad)
	panel.addonsScroll:setY(y)
	GlobalStorageSiK.TerminalScroll.resize(panel.addonsScroll, innerW - pad * 2, scrollH)
	GlobalStorageSiK.TerminalScroll.removeLeftGhostScrollBars(panel.addonsScroll)
	if panel.addonsScroll.scrollChildren and #panel.addonsScroll.scrollChildren > 0 then
		GlobalStorageSiK.TerminalAddons.syncScrollLayout(panel, panel.terminalRef)
	end
end

--- Solo geometría del scroll Addons (resize); sin clear ni reconstrucción.
---@param panel ISPanel
---@param terminal GS_TerminalUI|nil
local function layoutAddonsScrollContent(scroll)
	if not scroll or not scroll.scrollChildren then
		return
	end
	local pad = 8
	local innerW = GlobalStorageSiK.TerminalScroll.contentWidth(scroll)
	local cardW = math.max(260, innerW - pad * 2)
	for i = 1, #scroll.scrollChildren do
		local ch = scroll.scrollChildren[i]
		if ch and ch.recipeId then
			ch:setWidth(cardW)
			local contentPad = ch.contentPad or 10
			ch.textW = math.max(220, cardW - contentPad * 2)
		end
	end
end

--- Solo geometría del scroll Addons (resize); sin clear ni reconstrucción.
---@param panel ISPanel
---@param terminal GS_TerminalUI|nil
function GlobalStorageSiK.TerminalAddons.syncScrollLayout(panel, terminal)
	if not panel or not panel.addonsScroll then
		return
	end
	local scroll = panel.addonsScroll
	if not scroll.scrollChildren or #scroll.scrollChildren == 0 then
		return
	end
	local savedOffset = GlobalStorageSiK.TerminalScroll.getScrollOffset(scroll)
	local contentH = scroll._gsContentHeight or scroll.height or 320
	if scroll.setScrollHeight then
		scroll:setScrollHeight(contentH)
		if scroll.updateScroll then
			scroll:updateScroll()
		end
	end
	GlobalStorageSiK.TerminalScroll.setScrollOffset(scroll, savedOffset)
	GlobalStorageSiK.TerminalScroll.resetNeatScrollDelta(scroll)
	layoutAddonsScrollContent(scroll)
	GlobalStorageSiK.TerminalScroll.ensureScrollBars(scroll)
	GlobalStorageSiK.TerminalScroll.removeLeftGhostScrollBars(scroll)
end

---@param panel ISPanel
---@param terminal GS_TerminalUI|nil
function GlobalStorageSiK.TerminalAddons.refresh(panel, terminal)
	if not panel or not panel.addonsScroll or not terminal then
		return
	end
	local scroll = panel.addonsScroll
	local savedOffset = GlobalStorageSiK.TerminalScroll.getScrollOffset(scroll)
	GlobalStorageSiK.TerminalScroll.clear(scroll, true)
	GlobalStorageSiK.TerminalScroll.removeLeftGhostScrollBars(scroll)

	local pad = 8
	local innerW = GlobalStorageSiK.TerminalScroll.contentWidth(scroll)
	local state = terminal.terminalState or {}
	local anchor = state.terminalAnchor
	local networkId = state.networkId
		or (GlobalStorageSiK.Client and GlobalStorageSiK.Client.activeNetworkId)
		or GlobalStorageSiK.Network.getDefaultNetworkId()
	local installed = state.installedAddons or {}
	local y = pad

	y = addSectionTitle(scroll, pad, y, "IGUI_GS_AddonsSectionTitle", innerW)
	y = addWrappedLabel(scroll, pad, y, T("IGUI_GS_AddonsIntro"), innerW - pad * 2, 0.62, 0.66, 0.7)
	y = y + BLOCK_GAP

	if not anchor or not anchor.x then
		y = addWrappedLabel(scroll, pad, y, T("IGUI_GS_AddonsNeedTerminal"), innerW - pad * 2, 0.75, 0.55, 0.45)
		GlobalStorageSiK.TerminalScroll.finish(scroll, y + pad)
		GlobalStorageSiK.TerminalScroll.setScrollOffset(scroll, savedOffset)
		GlobalStorageSiK.TerminalScroll.removeLeftGhostScrollBars(scroll)
		return
	end

	local player = GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer and GlobalStorageSiK.NetClient.getPlayer()
	local isOwner = true
	if player and GlobalStorageSiK.Permissions.isOwnerPlayer then
		isOwner = GlobalStorageSiK.Permissions.isOwnerPlayer(player, networkId)
	end

	local defs = GlobalStorageSiK.AddonRegistry.listSorted()
	if #defs == 0 then
		y = addWrappedLabel(scroll, pad, y, T("IGUI_GS_AddonsEmpty"), innerW - pad * 2, 0.62, 0.64, 0.68)
	else
		-- Antes aqui se apilaban, siempre visibles, la descripcion + receta +
		-- boton instalar/desinstalar de los 4 addons a la vez (reportado:
		-- "ruido", ademas de un bug real de layout que hacia que Craft y
		-- Builder acabaran en la misma posicion visual). Ahora la bahia SOLO
		-- muestra el estado (icono real del periferico, instalado o no) -
		-- clic en una ranura abre GS_AddonManageUI con todo ese detalle, uno
		-- por addon, bajo demanda.
		y = addSectionTitle(scroll, pad, y, "IGUI_GS_AddonBayTitle", innerW)
		y = GlobalStorageSiK.TerminalAddonBay.addBay(scroll, pad, y, innerW, defs, {
			player = player,
			installed = installed,
			terminal = terminal,
			isOwner = isOwner,
			networkId = networkId,
			anchor = anchor,
		})
		y = y + BLOCK_GAP
	end

	GlobalStorageSiK.TerminalScroll.finish(scroll, y + pad)
	GlobalStorageSiK.TerminalScroll.setScrollOffset(scroll, savedOffset)
	GlobalStorageSiK.TerminalScroll.resetNeatScrollDelta(scroll)
	GlobalStorageSiK.TerminalScroll.removeLeftGhostScrollBars(scroll)
end
