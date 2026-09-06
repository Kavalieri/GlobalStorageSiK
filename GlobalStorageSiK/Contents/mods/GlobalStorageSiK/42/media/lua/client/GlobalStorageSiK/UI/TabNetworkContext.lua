-- Product data/actions adapter for the validated tab-red SiK.UI surface.
-- It intentionally creates no widgets and owns no geometry.

require "GS_I18n"
require "GS_TerminalUI_Nodes"
require "GS_TerminalUI_NetworkZones"

GlobalStorageSiK = GlobalStorageSiK or {}
GlobalStorageSiK.UI = GlobalStorageSiK.UI or {}

local TabNetworkContext = {}
GlobalStorageSiK.UI.TabNetworkContext = TabNetworkContext

local function text(key, ...)
	local i18n = GlobalStorageSiK.I18n
	if i18n and type(i18n.text) == "function" then return i18n.text(key, ...) end
	return tostring(key or "")
end

local function semantic(envelope)
	if type(envelope) == "table" and type(envelope.payload) == "table" then
		return envelope.payload
	end
	return type(envelope) == "table" and envelope or {}
end

local function runtimeI18n()
	return {
		["network.title"] = text("IGUI_GS_TabNodes"),
		["network.help"] = text("IGUI_GS_NodesPriorityHelp"),
		["network.create.room"] = text("IGUI_GS_CreateRoomZone"),
		["network.create.building"] = text("IGUI_GS_CreateStructureZone"),
		["network.create.selection"] = text("IGUI_GS_CreateSelectionZone"),
		["network.column.name"] = text("IGUI_GS_ColName"),
		["network.column.protocol"] = text("IGUI_GS_ColProtocol"),
		["network.column.priority"] = text("IGUI_GS_ColPriority"),
		["network.column.status"] = text("IGUI_GS_ColStatus"),
		["network.column.occupancy"] = text("IGUI_GS_ColOccupancy"),
		["network.rescan.title"] = text("IGUI_GS_RescanAll"),
		["network.rescan.help"] = text("IGUI_GS_RescanAllHint"),
		["network.rescan.action"] = text("IGUI_GS_RescanAll"),
	}
end

local function rescanState(state)
	local scan = state.scanStatus or state.scan or {}
	local scanState = tostring(scan.state or scan.phase or ""):upper()
	local running = state.scanActive == true or state.scanRunning == true
		or scan.running == true or scanState == "RUNNING" or scanState == "STALE_RETRY"
		or scanState == "INVALIDATED_BY_MUTATION" or state.reconcilePending == true
	local incidents = GlobalStorageSiK.TerminalNodes.getNetworkIncidentInfo(state.nodes or {})
	local feedback
	if incidents.count > 0 then
		feedback = { text = text("IGUI_GS_NetworkIncidentTip", incidents.count),
			tone = "text", severity = "warning", glow = true }
	end
	local progress
	if running then
		progress = {
			text = state.snapshotAgeMs ~= nil
				and text("IGUI_GS_ScanUpdatingAge", math.floor(math.max(0, tonumber(state.snapshotAgeMs) or 0) / 1000))
				or text("IGUI_GS_ScanRunning"),
			severity = "warning", tone = "text", glow = false,
		}
	end
	return running, feedback, progress
end

function TabNetworkContext.create(terminal)
	if type(terminal) ~= "table" then return nil, "invalid_terminal" end
	local context = { terminal = terminal, nodes = {}, zones = {}, categories = {},
		rowsByKey = {}, sortColumn = nil, sortDirection = "asc", disposed = false }

	context.actions = {
		["network.create-room"] = function()
			return GlobalStorageSiK.TerminalNetworkZones.create(terminal, "room")
		end,
		["network.create-building"] = function()
			return GlobalStorageSiK.TerminalNetworkZones.create(terminal, "building")
		end,
		["network.create-selection"] = function()
			return GlobalStorageSiK.TerminalNetworkZones.create(terminal, "selection")
		end,
		["network.activate-row"] = function(envelope)
			local payload = semantic(envelope)
			return GlobalStorageSiK.TerminalNodes.activateRow(terminal,
				context.rowsByKey[payload.rowKey],
				context.nodes, context.categories)
		end,
		["network.rescan"] = function()
			return GlobalStorageSiK.TerminalNetworkZones.rescanNetwork(terminal, context.scanRunning)
		end,
	}

	function context:snapshot(serverState)
		if self.disposed then return nil, "disposed" end
		local state = serverState or terminal.terminalState or {}
		self.nodes, self.zones, self.categories = state.nodes or {}, state.zones or {}, state.categories or {}
		local model = GlobalStorageSiK.TerminalNodes.presentationModel(self.nodes, self.zones,
			self.sortColumn, self.sortDirection)
		self.rowsByKey = {}
		for index = 1, #(model.rows or {}) do
			local row = model.rows[index]
			if row and row.id ~= nil then self.rowsByKey[row.id] = row end
			for childIndex = 1, #(row and row.children or {}) do
				local child = row.children[childIndex]
				if child and child.id ~= nil then self.rowsByKey[child.id] = child end
			end
		end
		self.scanRunning, self.rescanFeedback, self.scanProgress = rescanState(state)
		local permissions = state.permissions or {}
		local role = permissions.playerRole or permissions.role or "member"
		local canManage = role == "owner" or role == "admin"
		local canConfigure = GlobalStorageSiK.TerminalNetworkZones.canConfigure(terminal, false)
		return {
			data = { network = {
				headerActions = {}, rescanHeaderActions = {},
				rows = model,
				createRoom = { enabled = canConfigure },
				createBuilding = { enabled = canConfigure },
				createSelection = { enabled = canConfigure },
				rescanFeedback = self.rescanFeedback,
				scanProgress = self.scanProgress,
				rescanAction = { text = self.scanRunning and text("IGUI_GS_ScanCancel")
					or text("IGUI_GS_RescanAll"), enabled = canManage },
			} },
			conditions = {
				["network-rescan-visible"] = canManage,
				["network-rescan-has-incident"] = self.rescanFeedback ~= nil,
				["network-scan-running"] = self.scanRunning,
			},
			actions = self.actions,
			tableOptions = { ["network-table"] = GlobalStorageSiK.TerminalNodes.tableOptions(terminal, self) },
			i18n = runtimeI18n(), playerNum = terminal.playerNum or 0,
		}
	end

	function context:dispose()
		if self.disposed then return false end
		self.disposed = true
		self.actions, self.terminal, self.nodes, self.zones, self.categories = nil, nil, nil, nil, nil
		return true
	end

	return context
end

return TabNetworkContext
