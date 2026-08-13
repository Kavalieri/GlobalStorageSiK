--[[
	GSSiK Addon Builder - Cliente
	Autor: SiK
	Fecha: 2026-08-04
]]

require "GS_TerminalUI"
require "GS_TerminalUI_Extensions"
require "GSSiK_Addon_Builder_Register"
require "GS_NetworkCraftBridge"
require "GS_NetworkCraftSession"
require "GSSiK_Addon_Builder_NetworkBuild"
require "GSSiK_Addon_Builder_TerminalUI"
require "GSSiK_Addon_Builder_Sandbox"
require "GSSiK_Addon_Builder_Log"

GSSiK_Addon_Builder = GSSiK_Addon_Builder or {}

-- El sink de debug y los hooks de construccion en red ya se registran en
-- GSSiK_Addon_Builder_NetworkBuild.lua (migrado desde aqui, ver ese fichero).

--- Asegura panel build en el terminal (solo addon activo).
---@param terminal GS_TerminalUI
local function ensureBuildPanel(terminal)
	if not terminal or terminal.buildPanel then
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
	terminal.buildPanel = panel
	GlobalStorageSiK.TerminalBuilder.buildPanel(panel, terminal)
	GlobalStorageSiK.TerminalExtensions.registerTab(terminal, "build", {
		panel = panel,
		module = GlobalStorageSiK.TerminalBuilder,
		titleKey = "IGUI_GS_TabBuilder",
		iconPath = "media/ui/GS/GS_TabBuilder.png",
	})
end

--- Abre construcción con contenedores de red.
---@param mode string
function GS_TerminalUI:openNetworkBuild(mode)
	local player = GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer() or nil
	if not player or not GlobalStorageSiK.CraftSession then
		return
	end
	local state = self.terminalState or {}
	-- Antes, si begin() u openBuild() fallaban, el clic no hacia nada
	-- visible - ahora SIEMPRE se refresca el panel al final (exito o fallo)
	-- para que GS_NetworkCraftSession.getLastOpenError() se muestre en la
	-- etiqueta de estado que ya existe en este panel.
	-- Confiar en el terminalState ya confirmado por el servidor (el mismo
	-- dato que hace que la pestaña Addons muestre el modulo instalado) en
	-- vez de solo el mirror local de red (ModData), que puede ir con
	-- retraso justo tras instalar - ver comentario en CraftSession.begin.
	local knownInstalled = state.installedAddons and state.installedAddons["Builder"] ~= nil
	local began, beginReason = GlobalStorageSiK.CraftSession.begin({
		player = player,
		networkId = state.networkId,
		terminalAnchor = state.terminalAnchor,
		accessMode = state.accessMode,
		uiMode = "build_" .. tostring(mode or "auto"),
		addonId = "Builder",
		knownInstalled = knownInstalled,
	})
	GSSiK_Addon_Builder.Log.debug("openNetworkBuild mode=" .. tostring(mode)
		.. " networkId=" .. tostring(state.networkId) .. " began=" .. tostring(began)
		.. " reason=" .. tostring(beginReason))
	if began then
		local opened, openReason = GlobalStorageSiK.CraftSession.openBuild(mode)
		GSSiK_Addon_Builder.Log.debug("openBuild opened=" .. tostring(opened) .. " reason=" .. tostring(openReason))
	end
	if self.buildPanel and GlobalStorageSiK.TerminalBuilder then
		GlobalStorageSiK.TerminalBuilder.refresh(self.buildPanel, self)
	end
end

function GS_TerminalUI:onOpenVanillaBuild()
	self:openNetworkBuild("vanilla")
end

function GS_TerminalUI:onOpenNeatBuild()
	self:openNetworkBuild("neat")
end

--- Muestra/oculta la pestaña Build según addon instalado en este terminal
--- y, si el acceso es inalámbrico, según la tableta que lleve el jugador.
function GS_TerminalUI:syncBuildTabVisibility()
	local state = self.terminalState or {}
	local player = GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer() or nil
	local show = state.buildTabEnabled
	if show == nil and GlobalStorageSiK.Addons then
		show = GlobalStorageSiK.Addons.canShowTerminalBuildTab(
			state.networkId,
			state.terminalAnchor,
			state.accessMode,
			player
		)
	end
	if show then
		ensureBuildPanel(self)
	end
	if GlobalStorageSiK.TerminalExtensions then
		GlobalStorageSiK.TerminalExtensions.setTabVisible(self, "build", show == true)
	end
	if show and self.activeTabKey == "build" and self.buildPanel then
		GlobalStorageSiK.TerminalBuilder.refresh(self.buildPanel, self)
	end
end
