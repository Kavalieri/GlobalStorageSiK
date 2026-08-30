--[[
	GlobalStorageSiK - Pestaña Addons del terminal
	Autor: SiK
	Fecha: 2025-06-27
	Descripción: Bahía de módulos, recetas craftables e instalación por terminal.
]]

require "ISUI/ISPanel"
require "ISUI/ISButton"
require "GS_I18n"
require "GS_AddonRegistry"
require "GS_AddonRecipes"
require "GS_Addons"
require "GS_NetClient"
require "GS_Permissions"
require "GS_TerminalUI_Scroll"
require "GS_SiK_UI_Core"
require "GS_SiK_UI_Controls"
require "GS_TerminalUI_AddonBay"
require "GS_TerminalRecipeCards"

GlobalStorageSiK.TerminalAddons = {}

local T = GlobalStorageSiK.I18n.text
local BLOCK_GAP = GlobalStorageSiK.SiK_UI.Controls.metrics("standard").rowGap
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
	local lbl = GlobalStorageSiK.SiK_UI.Controls.sectionTitle(nil, {
		x = x, y = y, text = title,
	})
	GlobalStorageSiK.TerminalScroll.addChild(scroll, lbl)
	return y + GlobalStorageSiK.SiK_UI.Controls.metrics("standard").sectionHeight
end

local function addFeedback(scroll, x, y, width, text, kind)
	local feedback = GlobalStorageSiK.SiK_UI.Controls.feedback(nil, {
		x = x, y = y, w = width, text = text, kind = kind or "info",
	})
	GlobalStorageSiK.TerminalScroll.addChild(scroll, feedback)
	return y + feedback.height + BLOCK_GAP
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
	panel.addonsScroll = GlobalStorageSiK.TerminalScroll.create(panel, 0, 0, 280, 120)
	GlobalStorageSiK.TerminalAddons.ensureRefreshHooks()
end

---@param panel ISPanel
---@param innerW number
---@param innerH number
function GlobalStorageSiK.TerminalAddons.layout(panel, innerW, innerH)
	if not panel or not panel.addonsScroll then
		return
	end
	panel.addonsScroll:setX(0)
	panel.addonsScroll:setY(0)
	GlobalStorageSiK.TerminalScroll.resize(panel.addonsScroll, innerW, math.max(120, innerH))
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
		return 0
	end
	local pad = 8
	local innerW = GlobalStorageSiK.TerminalScroll.contentWidth(scroll)
	local cardW = math.max(80, innerW - pad * 2)
	local contentBottom = 0
	for i = 1, #scroll.scrollChildren do
		local ch = scroll.scrollChildren[i]
		if ch and ch.recipeId then
			ch:setWidth(cardW)
			local contentPad = ch.contentPad or 10
			ch.textW = math.max(80, cardW - contentPad * 2)
		elseif ch and ch._sikAddonBay then
			GlobalStorageSiK.TerminalAddonBay.layout(ch, cardW)
		end
		if ch and ch.getY and ch.getHeight then
			contentBottom = math.max(contentBottom, ch:getY() + ch:getHeight())
		end
	end
	return contentBottom + pad
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
	local contentBottom = layoutAddonsScrollContent(scroll)
	if contentBottom > 0 then
		GlobalStorageSiK.TerminalScroll.setContentHeight(scroll, contentBottom)
	end
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
	if not scroll._gsAddonContentRectBound then
		scroll._gsAddonContentRectBound = true
		GlobalStorageSiK.TerminalScroll.setOnContentRectChanged(scroll, function(changedScroll)
			layoutAddonsScrollContent(changedScroll)
		end)
	end
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
	local player = GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer
		and GlobalStorageSiK.NetClient.getPlayer()

	-- dev40 (pedido explicito del usuario, captura real: "no tiene mucho
	-- sentido aqui, ademas es feisimo"): el selector de paleta se muda a la
	-- pestaña Red -> sub-pestaña Red (GS_TerminalUI_NetworkStatus.lua) -
	-- ubicacion provisional, se movera de nuevo cuando se rediseñe a fondo
	-- esa pestaña, pero Addons deja de ser su sitio.

        y = addSectionTitle(scroll, pad, y, "IGUI_GS_AddonsSectionTitle", innerW)
	y = addFeedback(scroll, pad, y, innerW - pad * 2,
		T("IGUI_GS_AddonsIntro"), "info")

	if not anchor or not anchor.x then
		y = addFeedback(scroll, pad, y, innerW - pad * 2,
			T("IGUI_GS_AddonsNeedTerminal"), "warning")
		GlobalStorageSiK.TerminalScroll.finish(scroll, y + pad)
		GlobalStorageSiK.TerminalScroll.setScrollOffset(scroll, savedOffset)
		GlobalStorageSiK.TerminalScroll.removeLeftGhostScrollBars(scroll)
		return
	end

        local defs = GlobalStorageSiK.AddonRegistry.listSorted()
	if #defs == 0 then
		y = addFeedback(scroll, pad, y, innerW - pad * 2,
			T("IGUI_GS_AddonsEmpty"), "info")
	else
		-- Antes aqui se apilaban, siempre visibles, la descripcion + receta +
		-- boton instalar/desinstalar de los 4 addons a la vez (reportado:
		-- "ruido", ademas de un bug real de layout que hacia que Craft y
		-- Builder acabaran en la misma posicion visual). Ahora la bahia SOLO
		-- muestra el estado (icono real del periferico, instalado o no) -
		-- clic en una ranura abre GS_AddonManageUI con todo ese detalle, uno
		-- por addon, bajo demanda.
		y = GlobalStorageSiK.TerminalAddonBay.addBay(scroll, pad, y, innerW, defs, {
			player = player,
			installed = installed,
			terminal = terminal,
			networkId = networkId,
			anchor = anchor,
		})
		y = y + BLOCK_GAP
	end

	GlobalStorageSiK.TerminalScroll.finish(scroll, y + pad)
	GlobalStorageSiK.TerminalScroll.setScrollOffset(scroll, savedOffset)
	GlobalStorageSiK.TerminalScroll.removeLeftGhostScrollBars(scroll)
end
