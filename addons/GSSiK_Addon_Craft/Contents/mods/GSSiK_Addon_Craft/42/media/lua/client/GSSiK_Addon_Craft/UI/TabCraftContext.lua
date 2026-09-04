-- Product data/actions adapter for the declarative tab-craft surface.

local API = require "GSSiK_API_Client"
require "GSSiK_Addon_Craft_Sandbox"

GSSiK_Addon_Craft = GSSiK_Addon_Craft or {}
GSSiK_Addon_Craft.UI = GSSiK_Addon_Craft.UI or {}
local Context = {}
GSSiK_Addon_Craft.UI.TabCraftContext = Context
local Session = API.WorkSession

local function T(key, ...) return getText(key, ...) end
local function isModActive(modId)
	local active = getActivatedMods and getActivatedMods() or nil
	return active ~= nil and active:contains(modId) == true
end

local function sessionPresentation()
	local _, _, state = Session.status("Craft")
	state = state or { active = false }
	local _, _, failure = Session.getOpenFailure("Craft")
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
	local actions = { craft = {
		["open-main"] = function()
			local callback = isModActive("Neat_Crafting") and terminal.onOpenNeatCraft
				or terminal.onOpenVanillaCraft
			if type(callback) ~= "function" then return false, "craft_action_unavailable" end
			callback(terminal)
			return true
		end,
		["open-cook"] = function()
			if type(terminal.onOpenCook) ~= "function" then return false, "cook_action_unavailable" end
			terminal:onOpenCook()
			return true
		end,
		["toggle-destination"] = function()
			local _, _, current = Session.getResultDestination("Craft")
			Session.setResultDestination("Craft", current == "network" and "inventory" or "network")
			API.Terminal.refresh(terminal, "craft")
			return true
		end,
	} }
	local state, statusText, statusTone = sessionPresentation()
	local neat, cook = isModActive("Neat_Crafting"), isModActive("Project_Cook")
	local _, _, destination = Session.getResultDestination("Craft")
	local warning = nil
	if state.active and (state.unavailableContainers or 0) > 0 then
		warning = { text = T("IGUI_GS_CraftContainersUnavailable",
			tostring(state.unavailableContainers)), tone = "warning" }
	end
	return {
		playerNum = tonumber(terminal.playerNum) or 0,
		i18n = {
			["craft.title"] = T("IGUI_GS_SectionCraftRemote"),
			["craft.help"] = T("IGUI_GS_CraftRemoteHint"),
		},
		data = { craft = {
			status = { text = statusText, tone = statusTone }, warning = warning,
			interface = { text = neat and T("IGUI_GS_CraftInterfaceNeat")
				or T("IGUI_GS_CraftInterfaceVanilla"), tone = "textMuted" },
			cook = { text = cook and T("IGUI_GS_CraftCookAvailable")
				or T("IGUI_GS_CraftCookUnavailable"), tone = "textMuted" },
			openMain = { text = T(neat and "IGUI_GS_CraftOpenNeat" or "IGUI_GS_CraftOpenVanilla") },
			openCook = { text = T("IGUI_GS_CraftOpenCook"), enabled = cook },
			destination = { text = T(destination == "network" and "IGUI_GS_CraftSendResultOn"
				or "IGUI_GS_CraftSendResultOff"), selected = destination == "network" },
		} },
		actions = actions,
		conditions = { ["cook-available"] = cook, ["has-warning"] = warning ~= nil },
	}
	end

return Context
