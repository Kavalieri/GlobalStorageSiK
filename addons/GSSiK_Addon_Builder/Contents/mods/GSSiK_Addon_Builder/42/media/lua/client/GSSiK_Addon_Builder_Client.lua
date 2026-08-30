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
require "GS_ItemActions"
require "GSSiK_Addon_Builder_NetworkBuild"
require "GSSiK_Addon_Builder_TerminalUI"
require "GSSiK_Addon_Builder_Sandbox"
require "GSSiK_Addon_Builder_Log"

GSSiK_Addon_Builder = GSSiK_Addon_Builder or {}

-- El sink de debug y los hooks de construccion en red ya se registran en
-- GSSiK_Addon_Builder_NetworkBuild.lua (migrado desde aqui, ver ese fichero).

GlobalStorageSiK.TerminalExtensions.registerDefinition("build", {
	module = GlobalStorageSiK.TerminalBuilder,
	titleKey = "IGUI_GS_TabBuilder",
	iconPath = "media/ui/GS/GS_TabBuilder.png",
	panelField = "buildPanel",
})

local function providerTerminal(context)
	local extra = context and context.extra or {}
	local terminal = extra.terminal or (GlobalStorageSiK.TerminalUI and GlobalStorageSiK.TerminalUI.instance)
	if not terminal or not terminal.terminalState then return nil end
	if not terminal.getIsVisible or terminal:getIsVisible() ~= true then return nil end
	local installed = terminal.terminalState.installedAddons
	if not installed or installed["Builder"] == nil then return nil end
	return terminal
end

local function buildItemActionRequest(actionId, context)
	local items = context and context.items or {}
	local item = context and context.extra and context.extra.row or items[1]
	local inputFullType = item and item.fullType
	if not inputFullType and item and item.getFullType then inputFullType = item:getFullType() end
	return { actionId = actionId, inputFullType = inputFullType,
		source = context and context.extra and context.extra.source or "inventory" }
end

-- Builder declara la fabricación contextual y reutiliza la sesión/autoridad
-- compartida; Core no contiene ninguna rama específica del addon.
GlobalStorageSiK.ItemActions.registerProvider({
	id = "builder.item-actions",
	addonId = "Builder",
	capabilities = { "craft" },
	actions = {
		{ id = "craft", labelKey = "IGUI_GS_CraftOpenBuildVanilla" },
	},
	appliesTo = function(context, actionId)
		return actionId == "craft" and providerTerminal(context) ~= nil
			and context.items ~= nil and #context.items > 0
	end,
	buildRequest = buildItemActionRequest,
	executeRequest = function(request, context)
		local terminal = providerTerminal(context)
		if not terminal then return false end
		local itemString = request.inputFullType and ("!" .. request.inputFullType) or nil
		terminal:openNetworkBuild("vanilla", nil, itemString)
		return true
	end,
})

--- Abre construcción con contenedores de red.
---@param mode string
function GS_TerminalUI:openNetworkBuild(mode, recipe, itemString)
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
		local opened, openReason = GlobalStorageSiK.CraftSession.openBuild(mode, recipe, itemString)
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

GlobalStorageSiK.TerminalExtensions.registerStaffAction("builder.vanilla", {
	labelKey = "IGUI_GS_CraftOpenBuildVanilla",
	order = 20,
	invoke = function(dashboard)
		if dashboard and dashboard.setVisible then
			dashboard:setVisible(false)
		end
		local terminal = GlobalStorageSiK.TerminalUI and GlobalStorageSiK.TerminalUI.instance or nil
		if terminal and terminal.openNetworkBuild then
			terminal:openNetworkBuild("vanilla")
		else
			GlobalStorageSiK.CraftSession.openBuild("vanilla")
		end
	end,
})

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
	if GlobalStorageSiK.TerminalExtensions then
		GlobalStorageSiK.TerminalExtensions.setTabVisible(self, "build", show == true)
	end
end
