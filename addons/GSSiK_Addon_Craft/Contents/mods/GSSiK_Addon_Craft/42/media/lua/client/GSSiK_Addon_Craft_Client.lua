--[[
	GSSiK Addon Craft - Cliente
	Autor: SiK
	Fecha: 2025-06-27
]]

require "GS_TerminalUI"
require "GSSiK_Addon_Craft_Register"
require "GS_NetworkCraftBridge"
require "GS_NetworkCraftSession"
require "GSSiK_Addon_Craft_NetworkCraft"
require "GSSiK_Addon_Craft_NetworkCook"
require "GSSiK_Addon_Craft_TerminalUI"
require "GSSiK_Addon_Craft_Sandbox"
require "GSSiK_Addon_Craft_Log"

GlobalStorageSiK.TerminalTabs = GlobalStorageSiK.TerminalTabs or {}

-- El sink de debug y los hooks de crafteo en red ya se registran en
-- GSSiK_Addon_Craft_NetworkCraft.lua (migrado desde aqui, ver ese fichero).

--- Asegura panel craft en el terminal (solo addon activo).
---@param terminal GS_TerminalUI
function GlobalStorageSiK.TerminalTabs.ensureCraftPanel(terminal)
	if not terminal or terminal.craftPanel then
		return
	end
	local panel = ISPanel:new(0, 0, 10, 10)
	panel:initialise()
	panel.drawBackground = false
	panel.clipChildren = true
	panel:setScrollWithParent(false)
	if panel.setScrollChildren then
		panel:setScrollChildren(false)
	end
	terminal.craftPanel = panel
	GlobalStorageSiK.TerminalCraft.buildPanel(terminal.craftPanel, terminal)
	terminal.tabViews = terminal.tabViews or {}
	terminal.tabViews.craft = terminal.craftPanel
end

---@param terminal GS_TerminalUI
---@param visible boolean
function GlobalStorageSiK.TerminalTabs.setCraftTabVisible(terminal, visible)
	if not terminal or not terminal.tabRail then
		return
	end
	if visible then
		GlobalStorageSiK.TerminalTabs.ensureCraftPanel(terminal)
	end
	terminal.tabRail:setCraftTabVisible(visible, {
		key = "craft",
		titleKey = "IGUI_GS_TabCraft",
		panelField = "craftPanel",
		iconPath = "media/ui/GS/GS_TabCraft.png",
	})
	if visible and terminal.activeTabKey == "craft" and terminal.craftPanel then
		GlobalStorageSiK.TerminalCraft.refresh(terminal.craftPanel, terminal)
	end
end

--- Abre crafteo con contenedores de red.
---@param mode string
function GS_TerminalUI:openNetworkCraft(mode)
	local player = GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer() or nil
	if not player or not GlobalStorageSiK.CraftSession then
		return
	end
	local state = self.terminalState or {}
	-- Antes, si begin() u openHandcraft() fallaban, el clic no hacia nada
	-- visible - ahora SIEMPRE se refresca el panel al final (exito o fallo)
	-- para que GS_NetworkCraftSession.getLastOpenError() se muestre en la
	-- etiqueta de estado que ya existe en este panel.
	-- Confiar en el terminalState ya confirmado por el servidor (el mismo
	-- dato que hace que la pestaña Addons muestre el modulo instalado) en
	-- vez de solo el mirror local de red (ModData), que puede ir con
	-- retraso justo tras instalar - ver comentario en CraftSession.begin.
	local knownInstalled = state.installedAddons and state.installedAddons["Craft"] ~= nil
	local began, beginReason = GlobalStorageSiK.CraftSession.begin({
		player = player,
		networkId = state.networkId,
		terminalAnchor = state.terminalAnchor,
		accessMode = state.accessMode,
		uiMode = "handcraft_" .. tostring(mode or "auto"),
		addonId = "Craft",
		knownInstalled = knownInstalled,
	})
	GSSiK_Addon_Craft.Log.debug("openNetworkCraft mode=" .. tostring(mode)
		.. " networkId=" .. tostring(state.networkId) .. " began=" .. tostring(began)
		.. " reason=" .. tostring(beginReason))
	if began then
		local opened, openReason = GlobalStorageSiK.CraftSession.openHandcraft(mode)
		GSSiK_Addon_Craft.Log.debug("openHandcraft opened=" .. tostring(opened) .. " reason=" .. tostring(openReason))
	end
	if self.craftPanel and GlobalStorageSiK.TerminalCraft then
		GlobalStorageSiK.TerminalCraft.refresh(self.craftPanel, self)
	end
end

function GS_TerminalUI:onOpenVanillaCraft()
	self:openNetworkCraft("vanilla")
end

function GS_TerminalUI:onOpenNeatCraft()
	self:openNetworkCraft("neat")
end

--- Abre cocina (Project_Cook, mod externo opcional) con contenedores de red
--- - misma sesion "Craft" que crafteo, distinto uiMode para diagnostico. Ver
--- GSSiK_Addon_Craft_NetworkCook.lua: Project_Cook rastrea su propia
--- ventana, no via ISEntityUI, así que no reutiliza CraftSession.openHandcraft.
function GS_TerminalUI:onOpenCook()
	local player = GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer() or nil
	if not player or not GlobalStorageSiK.CraftSession then
		return
	end
	local state = self.terminalState or {}
	local knownInstalled = state.installedAddons and state.installedAddons["Craft"] ~= nil
	local began, beginReason = GlobalStorageSiK.CraftSession.begin({
		player = player,
		networkId = state.networkId,
		terminalAnchor = state.terminalAnchor,
		accessMode = state.accessMode,
		uiMode = "cook",
		addonId = "Craft",
		knownInstalled = knownInstalled,
	})
	GSSiK_Addon_Craft.Log.debug("onOpenCook networkId=" .. tostring(state.networkId) .. " began=" .. tostring(began)
		.. " reason=" .. tostring(beginReason))
	if began then
		local opened, openReason = GSSiK_Addon_Craft_NetworkCook.openCookUI(player)
		GSSiK_Addon_Craft.Log.debug("openCookUI opened=" .. tostring(opened) .. " reason=" .. tostring(openReason))
		if opened then
			GlobalStorageSiK.CraftSession.setLastOpenError(nil)
		else
			GlobalStorageSiK.CraftSession.setLastOpenError(openReason)
			GlobalStorageSiK.CraftSession.endSession(nil)
		end
	end
	if self.craftPanel and GlobalStorageSiK.TerminalCraft then
		GlobalStorageSiK.TerminalCraft.refresh(self.craftPanel, self)
	end
end

function GS_TerminalUI:syncCraftTabVisibility()
	local state = self.terminalState or {}
	local player = GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer() or nil
	local show = state.craftTabEnabled
	if show == nil and GlobalStorageSiK.Addons then
		show = GlobalStorageSiK.Addons.canShowTerminalCraftTab(
			state.networkId,
			state.terminalAnchor,
			state.accessMode,
			player
		)
	end
	if GlobalStorageSiK.TerminalTabs.setCraftTabVisible then
		GlobalStorageSiK.TerminalTabs.setCraftTabVisible(self, show == true)
	end
	if show and self.activeTabKey == "craft" and self.craftPanel then
		GlobalStorageSiK.TerminalCraft.refresh(self.craftPanel, self)
	end
end

function GS_TerminalUI:onCraftTabActivated()
	if self.craftPanel and GlobalStorageSiK.TerminalCraft then
		GlobalStorageSiK.TerminalCraft.refresh(self.craftPanel, self)
	end
end
