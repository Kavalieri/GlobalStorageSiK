--[[
	GSSiK Addon Builder - Cliente
	Autor: SiK
	Fecha: 2026-08-04
]]

local API = require "GSSiK_API_Client"
require "GSSiK_Addon_Builder_Register"
require "GSSiK_Addon_Builder_NetworkBuild"
local TerminalModule = require "GSSiK_Addon_Builder_TerminalUI"
require "GSSiK_Addon_Builder_Sandbox"
require "GSSiK_Addon_Builder_Log"

GSSiK_Addon_Builder = GSSiK_Addon_Builder or {}
GSSiK_Addon_Builder._apiRegistrations = GSSiK_Addon_Builder._apiRegistrations or {}
local registrations = GSSiK_Addon_Builder._apiRegistrations
local Session = API.WorkSession
local Terminal = API.Terminal

local function retainRegistration(key, ok, code, handle)
	if ok ~= true or not handle then
		error("GSSiK.API " .. key .. ": " .. tostring(code))
	end
	local previous = registrations[key]
	if previous and previous.dispose then previous:dispose() end
	registrations[key] = handle
end

-- El sink de debug y los hooks de construccion en red ya se registran en
-- GSSiK_Addon_Builder_NetworkBuild.lua (migrado desde aqui, ver ese fichero).

retainRegistration("terminal-tab", Terminal.registerTab({
	key = "build",
	surface = TerminalModule.surface,
	builder = TerminalModule.builder,
	contextFactory = TerminalModule.contextFactory,
	titleKey = "IGUI_GS_TabBuilder",
	iconPath = "media/ui/GSSiK_Addon_Builder/sik-rail-builder.png",
	panelField = "buildPanel",
	enabledStateKey = "buildTabEnabled",
	order = 20,
}))

local function providerTerminal(context)
	local extra = context and context.extra or {}
	local terminal = extra.terminal or Terminal.current()
	if not terminal or not terminal.terminalState then return nil end
	if not terminal.getIsVisible or terminal:getIsVisible() ~= true then return nil end
	if not Terminal.isAddonInstalled(terminal, "Builder") then return nil end
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
retainRegistration("item-actions", API.ItemActions.registerProvider({
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
		return TerminalModule.openBuild(terminal, "vanilla", nil, itemString)
	end,
}))

--- Abre construcción con contenedores de red.
---@param mode string
function TerminalModule.openBuild(terminal, mode, recipe, itemString)
	local player = Terminal.player(terminal)
	if not player or not terminal then
		return false, terminal and "no_player" or "no_terminal"
	end
	local state = Terminal.state(terminal) or {}
	-- Antes, si begin() u openBuild() fallaban, el clic no hacia nada
	-- visible - ahora SIEMPRE se refresca el panel al final (exito o fallo)
	-- para que WorkSession.getOpenFailure() se muestre en la
	-- etiqueta de estado que ya existe en este panel.
	-- Confiar en el terminalState ya confirmado por el servidor (el mismo
	-- dato que hace que la pestaña Addons muestre el modulo instalado) en
	-- vez de solo el mirror local de red (ModData), que puede ir con
	-- retraso justo tras instalar - ver el contrato WorkSession.begin.
	local knownInstalled = state.installedAddons and state.installedAddons["Builder"] ~= nil
	local began, beginReason = Session.begin({
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
	local opened, openReason = false, beginReason
	if began then
		opened, openReason = Session.openBuild("Builder", mode, recipe, itemString)
		GSSiK_Addon_Builder.Log.debug("openBuild opened=" .. tostring(opened) .. " reason=" .. tostring(openReason))
	end
	if terminal.buildPanel then
		TerminalModule.refresh(terminal.buildPanel, terminal)
	end
	return opened == true, openReason
end

retainRegistration("staff-action", Terminal.registerStaffAction("builder.vanilla", {
	labelKey = "IGUI_GS_CraftOpenBuildVanilla",
	order = 20,
	invoke = function(dashboard)
		local terminal = Terminal.current()
		local opened, reason = TerminalModule.openBuild(terminal, "vanilla")
		if opened and dashboard and dashboard.setVisible then
			dashboard:setVisible(false)
		end
		return opened, reason
	end,
}))

--- Muestra/oculta la pestaña Build según addon instalado en este terminal
--- y, si el acceso es inalámbrico, según la tableta que lleve el jugador.
function TerminalModule.syncVisibility(terminal)
	local show = Terminal.isTabEnabled(terminal, "Builder", "buildTabEnabled")
	Terminal.setTabVisible(terminal, "build", show)
end

return GSSiK_Addon_Builder
