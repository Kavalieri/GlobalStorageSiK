-- Global Storage SiK - declarative data/action adapter for the Programming tab.
-- SiK.UI owns composition, cards, layout, input and lifecycle.

require "GS_I18n"
require "GS_Addons"
require "GS_Config"
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
local MIDDLE_DOT = T("IGUI_GS_PunctuationMiddleDot")
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
	return GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer(terminal and terminal.playerNum or 0) or nil
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

local function integer(value)
	return type(value) == "number" and value == value and value ~= math.huge
		and value ~= -math.huge and value == math.floor(value)
end

local function captureTerminal(terminal)
	local state = terminal and terminal.terminalState
	local anchor = type(state) == "table" and state.terminalAnchor
	if type(state) ~= "table" or type(state.networkId) ~= "string"
		or state.networkId == "" or #state.networkId > 192 or type(anchor) ~= "table"
		or not integer(anchor.x) or not integer(anchor.y) or not integer(anchor.z)
		or type(state.installedAddons) ~= "table"
		or (state.installedAddons.Reader ~= true and type(state.installedAddons.Reader) ~= "table") then
		return nil
	end
	return { networkId = state.networkId, terminalAnchor = { x = anchor.x, y = anchor.y, z = anchor.z } }
end

local function sameTerminal(terminal, captured)
	local current = captureTerminal(terminal)
	return current ~= nil and captured ~= nil and current.networkId == captured.networkId
		and current.terminalAnchor.x == captured.terminalAnchor.x
		and current.terminalAnchor.y == captured.terminalAnchor.y
		and current.terminalAnchor.z == captured.terminalAnchor.z
end

local function readerResource(terminal)
	local installed = captureTerminal(terminal) ~= nil
	return {
		text = GlobalStorageSiK.I18n.typeDisplayName(GlobalStorageSiK.Config.ITEM_TERMINAL_READER)
			.. " " .. MIDDLE_DOT .. " " .. T(installed and "IGUI_GS_ProgrammingReaderInstalled"
				or "IGUI_GS_ProgrammingReaderUnavailable"),
		icon = "media/textures/Item_GS_TerminalReader.png",
		state = installed and "success" or "missing",
		availability = installed and "installed" or "unavailable",
	}
end

local function programReadiness(player, id)
	local known = GlobalStorageSiK.DiskProgramming.knowsProgram(player, id)
	local disk = player ~= nil and GlobalStorageSiK.CraftUtils.findItemTypeNearby(
		player, GlobalStorageSiK.DiskProgramming.BLANK_DISK) ~= nil
	return known == true, disk == true
end

function Programming.context(terminal)
	local player = playerFor(terminal)
	local captured = captureTerminal(terminal)
	local blankCount = countBlankDisksNearby(player)
	local reader = readerResource(terminal, player)
	local canProgram = reader.availability ~= "unavailable"
	local cards = {}
	local ids = orderedProgramIds()
	for i = 1, #ids do
		local id = ids[i]
		local def = GlobalStorageSiK.DiskProgramming.PROGRAMS[id]
		local known, hasDisk = programReadiness(player, id)
		local ready = canProgram and known and hasDisk
		local recording = terminal and terminal._gsRecordingProgramId == id
		local manualName = GlobalStorageSiK.I18n.typeDisplayName(def.manualItem)
		local title = T(def.menuTextKey or id)
		-- menuTextKey already contains the complete localized action (for
		-- example, "Grabar disco de red"). Formatting it through a second
		-- "Grabar %1" template duplicates the verb and leaks %1 on runtimes
		-- whose Translator does not expand numbered placeholders.
		local actionLabel = title
		cards[#cards + 1] = {
			variant = "output", title = title,
			description = def.descKey and T(def.descKey) or "", icon = def.iconPath,
			requirement = {
				text = T("IGUI_GS_ProgrammingRecipeRequirement", manualName),
				icon = "media/textures/Item_MagazineElectronics03.png",
				state = known and "success" or "missing",
				iconSize = 32,
			},
			actionLabel = actionLabel,
			locked = not ready or recording,
			tooltip = (not canProgram and reader.text)
				or (not known and T("IGUI_GS_ProgrammingRecipeRequirement", manualName))
				or (not hasDisk and T("IGUI_GS_ProgrammingNeedsBlankDisk") or nil),
			payload = { programId = id, state = recording and "recording"
				or (ready and "available") or "unavailable" },
		}
	end
	return {
		playerNum = terminal and terminal.playerNum or 0,
		i18n = {
			["programming.title"] = T("IGUI_GS_SectionProgramming"),
			["programming.resources.title"] = T("IGUI_GS_ProgrammingResourcesTitle"),
			["programming.programs.title"] = T("IGUI_GS_SectionProgramming"),
			["programming.help"] = T("IGUI_GS_TabProgramming"),
		},
		data = { programming = {
			resources = {
				reader = reader,
				blankDisk = {
					text = GlobalStorageSiK.I18n.typeDisplayName(GlobalStorageSiK.DiskProgramming.BLANK_DISK)
						.. " " .. MIDDLE_DOT .. " "
						.. T("IGUI_GS_ProgrammingBlankDiskCount", tostring(blankCount)),
					icon = "media/textures/Item_GS_FloppyDisk_Blank.png",
					state = blankCount > 0 and "success" or "missing",
				},
			},
			canProgram = canProgram,
			cards = cards,
		} },
		actions = {
			["programming.run"] = function(envelope)
				local payload = envelope and (envelope.payload or envelope) or {}
				if type(payload) ~= "table" or type(payload.programId) ~= "string"
					or not sameTerminal(terminal, captured) or terminal._gsRecordingProgramId
					or playerFor(terminal) ~= player then return false end
				local known, disk = programReadiness(player, payload.programId)
				if not known or not disk then return false end
				local token = {}
				local function release()
					if terminal._gsRecordingToken == token then
						terminal._gsRecordingToken, terminal._gsRecordingProgramId = nil, nil
					end
				end
				local action = GS_ProgramDiskAction:new(player, payload.programId, {
					isAvailable = function()
						return sameTerminal(terminal, captured) and playerFor(terminal) == player
							and terminal._gsRecordingToken == token
					end,
					onStop = release,
					onPerform = release,
				}, captured)
				terminal._gsRecordingToken = token
				terminal._gsRecordingProgramId = payload.programId
				ISTimedActionQueue.add(action)
				return true
			end,
		},
	}
end

local function isVisible(terminal)
	return captureTerminal(terminal) ~= nil
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
