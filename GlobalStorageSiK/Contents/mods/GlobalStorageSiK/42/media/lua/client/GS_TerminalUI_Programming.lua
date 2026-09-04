-- Global Storage SiK - declarative data/action adapter for the Programming tab.
-- SiK.UI owns composition, cards, layout, input and lifecycle.

require "GS_I18n"
require "GS_Addons"
require "GS_DiskProgramming"
require "GS_CraftUtils"
require "GS_NetClient"
require "GS_TerminalUI_Extensions"
require "TimedActions/ISTimedActionQueue"
require "TimedActions/GS_ProgramDiskAction"

local Surface = require "GlobalStorageSiK/UI/Generated/TabProgramming"

GlobalStorageSiK.TerminalProgramming = GlobalStorageSiK.TerminalProgramming or {}
local Programming = GlobalStorageSiK.TerminalProgramming
local T = GlobalStorageSiK.I18n.text
local KNOWN_PROGRAM_ORDER = { "network", "uninstall", "driveinstall", "craft", "builder", "tablet" }

local function orderedProgramIds()
	local out, seen = {}, {}
	for i = 1, #KNOWN_PROGRAM_ORDER do
		local id = KNOWN_PROGRAM_ORDER[i]
		if GlobalStorageSiK.DiskProgramming.PROGRAMS[id] then
			out[#out + 1], seen[id] = id, true
		end
	end
	for id in pairs(GlobalStorageSiK.DiskProgramming.PROGRAMS) do
		if not seen[id] then out[#out + 1], seen[id] = id, true end
	end
	return out
end

local function playerFor(terminal)
	if terminal and terminal.player then return terminal.player end
	return GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer() or nil
end

local function countBlankDisksNearby(player)
	if not player or not GlobalStorageSiK.CraftUtils.collectIngredientContainers then return 0 end
	local containers = GlobalStorageSiK.CraftUtils.collectIngredientContainers(player)
	local total = 0
	for i = 1, #containers do
		local ok, count = pcall(function()
			return containers[i]:getItemCountRecurse(GlobalStorageSiK.DiskProgramming.BLANK_DISK)
		end)
		if ok and tonumber(count) then total = total + tonumber(count) end
	end
	return total
end

local function programReadiness(player, id)
	local known = GlobalStorageSiK.DiskProgramming.knowsProgram(player, id)
	local disk = player ~= nil and GlobalStorageSiK.CraftUtils.findItemTypeNearby(
		player, GlobalStorageSiK.DiskProgramming.BLANK_DISK) ~= nil
	return known == true, disk == true
end

local function hasProgrammedDiskNearby(player, outputItem)
	if not player or not outputItem or not GlobalStorageSiK.CraftUtils.findItemTypeNearby then return false end
	return GlobalStorageSiK.CraftUtils.findItemTypeNearby(player, outputItem) ~= nil
end

function Programming.context(terminal)
	local player = playerFor(terminal)
	local blankCount = countBlankDisksNearby(player)
	local cards = {}
	local ids = orderedProgramIds()
	for i = 1, #ids do
		local id = ids[i]
		local def = GlobalStorageSiK.DiskProgramming.PROGRAMS[id]
		local known, hasDisk = programReadiness(player, id)
		local ready = known and hasDisk
		local completed = hasProgrammedDiskNearby(player, def.outputItem)
		local recording = Programming.recordingProgramId == id
		local statusKey = recording and "IGUI_GS_ProgrammingButton"
			or (completed and "IGUI_GS_ProgramDiskSuccess")
			or (ready and "IGUI_GS_ProgrammingReady")
			or (not known and "IGUI_GS_ProgrammingNeedsBook" or "IGUI_GS_ProgrammingNeedsBlankDisk")
		local tone = recording and "warning" or ((completed or ready) and "success" or "warning")
		local requirement = not known and T("IGUI_GS_ProgrammingNeedsBook")
			or (not hasDisk and T("IGUI_GS_ProgrammingNeedsBlankDisk") or "")
		local title = T(def.menuTextKey or id)
		cards[#cards + 1] = {
			variant = "process", title = title,
			description = def.descKey and T(def.descKey) or "", icon = def.iconPath,
			requirement = requirement, actionLabel = title,
			status = T(statusKey), statusTone = tone,
			locked = not ready or recording, tooltip = T(statusKey),
			payload = { programId = id, state = recording and "recording"
				or (completed and "completed") or (ready and "available") or "unknown" },
		}
	end
	return {
		playerNum = terminal and terminal.playerNum or 0,
		i18n = {
			["programming.title"] = T("IGUI_GS_SectionProgramming"),
			["programming.help"] = T("IGUI_GS_TabProgramming"),
		},
		data = { programming = {
			status = {
				text = T("IGUI_GS_ProgrammingReaderInstalled") .. " | "
					.. T("IGUI_GS_ProgrammingBlankDiskCount", tostring(blankCount), "1"),
				kind = blankCount > 0 and "success" or "warning",
			},
			cards = cards,
		} },
		actions = {
			["programming.run"] = function(envelope)
				local payload = envelope and (envelope.payload or envelope) or {}
				if type(payload) ~= "table" or type(payload.programId) ~= "string"
					or Programming.recordingProgramId then return false end
				local action = GS_ProgramDiskAction:new(player, payload.programId, {
					onStart = function() Programming.recordingProgramId = payload.programId end,
					onStop = function() Programming.recordingProgramId = nil end,
					onPerform = function() Programming.recordingProgramId = nil end,
				})
				Programming.recordingProgramId = payload.programId
				ISTimedActionQueue.add(action)
				return true
			end,
		},
	}
end

local function isVisible(terminal)
	local state = terminal and terminal.terminalState or {}
	return GlobalStorageSiK.Addons and GlobalStorageSiK.Addons.isInstalled(
		state.networkId, state.terminalAnchor, "Reader") == true
end

GlobalStorageSiK.TerminalExtensions.registerDefinition("programming", {
	surface = Surface,
	builder = SiK.UI.SurfaceHost.mount,
	contextFactory = Programming.context,
	titleKey = "IGUI_GS_TabProgramming",
	iconPath = "media/ui/GS/sik-rail-programming.png",
	panelField = "programmingPanel",
	isVisible = isVisible,
	refreshIntervalMs = 1000,
})

function Programming.syncTabVisibility(terminal)
	GlobalStorageSiK.TerminalExtensions.setTabVisible(terminal, "programming", isVisible(terminal))
end
