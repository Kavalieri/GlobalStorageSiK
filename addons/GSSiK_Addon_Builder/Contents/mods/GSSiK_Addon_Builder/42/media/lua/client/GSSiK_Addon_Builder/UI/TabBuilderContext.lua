-- Product data/actions adapter for the declarative tab-builder surface.

local API = require "GSSiK_API_Client"
require "GSSiK_Addon_Builder_Sandbox"

GSSiK_Addon_Builder = GSSiK_Addon_Builder or {}
GSSiK_Addon_Builder.UI = GSSiK_Addon_Builder.UI or {}
local Context = {}
GSSiK_Addon_Builder.UI.TabBuilderContext = Context
local Session = API.WorkSession

local function T(key, ...) return getText(key, ...) end
local function isModActive(modId)
	local active = getActivatedMods and getActivatedMods() or nil
	return active ~= nil and active:contains(modId) == true
end
local function sessionPresentation()
	local _, _, state = Session.status("Builder")
	state = state or { active = false }
	local _, _, failure = Session.getOpenFailure("Builder")
	if failure == "addon_unavailable" then return state, T("IGUI_GS_CraftOpenErrorAddon"), "danger" end
	if failure == "no_player" then return state, T("IGUI_GS_CraftOpenErrorNoPlayer"), "danger" end
	if failure == "out_of_range" then return state, T("IGUI_GS_CraftOpenErrorRange"), "danger" end
	if failure then return state, T("IGUI_GS_CraftOpenErrorOpener"), "danger" end
	if state.active then
		return state, T("IGUI_GS_CraftSessionActive", tostring(state.networkContainers or 0)), "success"
	end
	if state.lastEndReason == "access_lost" then
		return state, T("IGUI_GS_CraftSessionAccessLost"), "warning"
	end
	return state, T("IGUI_GS_CraftSessionInactive"), "info"
end

function Context.create(terminal)
	if type(terminal) ~= "table" then return nil, "invalid_terminal_context" end
	local actions = { builder = { ["open-main"] = function()
		local owner = GSSiK_Addon_Builder and GSSiK_Addon_Builder.TerminalUI
		if not owner or type(owner.openBuild) ~= "function" then
			return false, "build_action_unavailable"
		end
		owner.openBuild(terminal, isModActive("Neat_Building") and "neat" or "vanilla")
		return true
	end } }
	local state, statusText, statusTone = sessionPresentation()
	local neat, warning = isModActive("Neat_Building"), nil
	if state.active and (state.unavailableContainers or 0) > 0 then
		warning = { text = T("IGUI_GS_CraftContainersUnavailable",
			tostring(state.unavailableContainers)), tone = "warning" }
	end
	return {
		playerNum = tonumber(terminal.playerNum) or 0,
		i18n = {
			["builder.title"] = T("IGUI_GS_SectionBuildRemote"),
			["builder.help"] = T("IGUI_GS_BuildRemoteHint"),
		},
		data = { builder = {
			status = { text = statusText, tone = statusTone }, warning = warning,
			interface = { text = T("IGUI_GS_BuildInterfaceDetected",
				T(neat and "IGUI_GS_BuildInterfaceNeat" or "IGUI_GS_BuildInterfaceVanilla")),
				tone = "textMuted" },
			openMain = { text = T(neat and "IGUI_GS_CraftOpenBuildNeat"
				or "IGUI_GS_CraftOpenBuildVanilla") },
		} },
		actions = actions,
		conditions = { ["has-warning"] = warning ~= nil },
	}
	end

return Context
