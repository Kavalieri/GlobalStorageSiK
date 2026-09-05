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

local function inventoryCount(player, fullType)
	if not player or not player.getInventory or not fullType then return 0 end
	local inventory = player:getInventory()
	if not inventory or not inventory.getItemCount then return 0 end
	local ok, count = pcall(function() return inventory:getItemCount(fullType) end)
	return ok and math.max(0, tonumber(count) or 0) or 0
end

local function readerResource(terminal, player)
	local state = terminal and terminal.terminalState or {}
	local installed = GlobalStorageSiK.Addons and GlobalStorageSiK.Addons.isInstalled
		and GlobalStorageSiK.Addons.isInstalled(state.networkId, state.terminalAnchor, "Reader") == true
	local inInventory = inventoryCount(player, GlobalStorageSiK.Config.ITEM_TERMINAL_READER) > 0
	local availability = installed and "installed" or (inInventory and "inventory" or "unavailable")
	local labelKey = availability == "installed" and "IGUI_GS_ProgrammingReaderInstalled"
		or (availability == "inventory" and "IGUI_GS_ProgrammingReaderInventory"
			or "IGUI_GS_ProgrammingReaderUnavailable")
	return {
		text = GlobalStorageSiK.I18n.typeDisplayName(GlobalStorageSiK.Config.ITEM_TERMINAL_READER)
			.. " " .. MIDDLE_DOT .. " " .. T(labelKey),
		icon = "media/textures/Item_GS_TerminalReader.png",
		state = availability == "unavailable" and "missing" or "success",
		availability = availability,
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
		local recording = Programming.recordingProgramId == id
		local manualName = GlobalStorageSiK.I18n.typeDisplayName(def.manualItem)
		local title = T(def.menuTextKey or id)
		local actionLabel = T("IGUI_GS_ProgrammingButton", title)
		-- Keep product labels complete even if the host Translator returns a
		-- numbered placeholder literally on a particular locale/runtime.
		actionLabel = GlobalStorageSiK.I18n.plainReplace(actionLabel, "%1", title)
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
	return terminal ~= nil and terminal.terminalState ~= nil
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
