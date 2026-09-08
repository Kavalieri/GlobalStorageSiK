-- Product data/actions adapter for the validated tab-options SiK.UI surface.
-- This module never creates or positions widgets. It converts terminal state
-- into plain, stable values consumed by the independent framework.

require "GS_I18n"
require "GS_Log"
require "GS_NetClient"
require "GS_Sandbox"
require "GS_TerminalCatalog"
require "GS_TerminalUI_Permissions"
require "GS_TerminalUI_TerminalEditor"
require "GS_TerminalUI_MemberEditor"
require "GS_UI_PalettePreference"
local CapacityPresentation = require "GlobalStorageSiK/UI/CapacityPresentation"

GlobalStorageSiK = GlobalStorageSiK or {}
GlobalStorageSiK.UI = GlobalStorageSiK.UI or {}

local TabOptionsContext = {}
GlobalStorageSiK.UI.TabOptionsContext = TabOptionsContext

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

local function status(value, tone, indicator)
	return { text = tostring(value or ""), tone = tone or "text", indicator = indicator == true }
end

local function tableCell(value, r, g, b)
	return { text = tostring(value or ""), color = { r = r, g = g, b = b, a = 1 } }
end

local function normalizeTerminalRows(state, rowMap)
	local rows = state.terminals or {}
	if #rows == 0 and state.networkId and GlobalStorageSiK.TerminalCatalog
		and type(GlobalStorageSiK.TerminalCatalog.serializeRows) == "function" then
		rows = GlobalStorageSiK.TerminalCatalog.serializeRows(state.networkId) or {}
	end
	local result = {}
	for index = 1, #rows do
		local source = rows[index]
		local unknown = source.unknown == true
			or (source.unknown == nil and source.present == false and source.missing ~= true)
		local id = string.format("terminal:%s:%s:%s", tostring(source.x or 0),
			tostring(source.y or 0), tostring(source.z or 0))
		local role = source.controller and text("IGUI_GS_TerminalController")
			or text("IGUI_GS_TerminalSecondary")
		local stateText = text("IGUI_GS_TerminalPresentPhys")
		if unknown then stateText = text("IGUI_GS_TerminalUnverified")
		elseif source.missing or source.present == false then stateText = text("IGUI_GS_TerminalMissingPhys")
		elseif source.suspended then stateText = text("IGUI_GS_TerminalSuspended") end
		local sr, sg, sb = 0.45, 0.85, 0.45
		if unknown then sr, sg, sb = 0.75, 0.78, 0.82
		elseif source.missing or source.present == false then sr, sg, sb = 0.92, 0.35, 0.30
		elseif source.suspended then sr, sg, sb = 0.92, 0.75, 0.35 end
		result[#result + 1] = {
			id = id, name = source.label or text("IGUI_GS_PunctuationEmDash"),
			coords = string.format("%d, %d, %d", source.x or 0, source.y or 0, source.z or 0),
			role = role, status = tableCell(stateText, sr, sg, sb),
		}
		rowMap[id] = source
	end
	return result
end

local function roleText(role)
	if role == "owner" then return text("IGUI_GS_PermRoleOwner") end
	if role == "admin" then return text("IGUI_GS_PermRoleAdmin") end
	if role == "faction" then return text("IGUI_GS_PermRoleFaction") end
	return text("IGUI_GS_PermRoleMember")
end

local function memberName(entry)
	if GlobalStorageSiK.Permissions
		and type(GlobalStorageSiK.Permissions.resolveMemberDisplayName) == "function" then
		return GlobalStorageSiK.Permissions.resolveMemberDisplayName(entry)
	end
	return entry.displayName or entry.name or entry.username or "?"
end

local function pushMember(result, rowMap, source, kind, key)
	local id = "member:" .. tostring(key or source.id or source.characterId or source.name or #result + 1)
	local connection = ""
	if source.online == true then connection = text("IGUI_GS_AdminOnline")
	elseif source.lastSeenAt then connection = text("IGUI_GS_AdminOffline", tostring(source.lastSeenAt)) end
	local role = roleText(kind)
	if kind == "owner" then role = tableCell(role, 0.91, 0.63, 0.31)
	elseif kind == "admin" then role = tableCell(role, 0.92, 0.75, 0.35) end
	local connectionCell = tableCell(connection, source.online == true and 0.45 or 0.55,
		source.online == true and 0.85 or 0.60, source.online == true and 0.45 or 0.68)
	result[#result + 1] = { id = id, role = role, name = memberName(source), connection = connectionCell }
	rowMap[id] = {
		kind = kind, name = source.name or source.username, displayName = memberName(source),
		characterId = tostring(source.id or source.characterId or ""), username = source.username or "",
		legacy = source.legacy == true, deniedZoneIds = source.deniedZoneIds or {},
		lastSeenAt = source.lastSeenAt, online = source.online == true,
	}
end

local function normalizeMemberRows(perms, rowMap)
	local result, seen = {}, {}
	local entries = perms.memberEntries or {}
	if #entries > 0 then
		for index = 1, #entries do
			local entry = entries[index]
			local role = entry.role == "member" and "user" or entry.role
			local key = tostring(entry.id or entry.characterId or entry.name or index)
			if role ~= "dead" and not seen[key] then
				seen[key] = true
				pushMember(result, rowMap, entry, role, key)
			end
		end
		return result
	end
	local owner = perms.owner
	if owner and owner ~= "" then pushMember(result, rowMap, { name = owner }, "owner", "owner:" .. owner) end
	local admins = {}
	for index = 1, #(perms.adminUsers or {}) do admins[perms.adminUsers[index]] = true end
	for index = 1, #(perms.allowedUsers or {}) do
		local name = perms.allowedUsers[index]
		if name and name ~= "" and name ~= owner then
			pushMember(result, rowMap, { name = name }, admins[name] and "admin" or "user", name)
		end
	end
	for index = 1, #(perms.allowedFactions or {}) do
		local name = perms.allowedFactions[index]
		if name and name ~= "" then pushMember(result, rowMap, { name = name }, "faction", name) end
	end
	return result
end

local function accessRows(perms, pickMap)
	local rows = {}
	local candidates = perms.pickerCandidates
	if type(candidates) == "table" then
		for index = 1, #candidates do
			local source = candidates[index]
			local id = tostring(source.characterId or source.id or "")
			local key = "member:" .. (id ~= "" and id or tostring(index))
			rows[#rows + 1] = { id = key, value = key, text = memberName(source) }
			pickMap[key] = { kind = "member", value = source.characterName or source.name,
				characterId = id, factionUsername = source.factionUsername or "" }
		end
		return rows
	end
	local permissionUi = GlobalStorageSiK.TerminalPermissions
	local factions = permissionUi and type(permissionUi.collectFactionPickerOptions) == "function"
		and permissionUi.collectFactionPickerOptions(perms) or {}
	local players = permissionUi and type(permissionUi.collectOnlineCharacters) == "function"
		and permissionUi.collectOnlineCharacters(perms) or {}
	for index = 1, #factions do
		local source = factions[index]
		local key = "faction:" .. tostring(source.characterId or source.value or index)
		rows[#rows + 1] = { id = key, value = key, text = source.label or source.value }
		pickMap[key] = source
	end
	for index = 1, #players do
		local source = players[index]
		local key = "member:" .. tostring(source.id or index)
		rows[#rows + 1] = { id = key, value = key, text = source.label or source.name }
		pickMap[key] = { kind = "member", value = source.name, characterId = source.id,
			factionUsername = source.username or "" }
	end
	return rows
end

local function playerFor(terminal)
	local client = GlobalStorageSiK.NetClient
	if client and type(client.getPlayer) == "function" then return client.getPlayer(terminal.playerNum) end
	return nil
end

local function paletteRows()
	local palette = GlobalStorageSiK.UIPalette
	local result = {}
	for index = 1, #((palette and palette.DEFINITIONS) or {}) do
		local source = palette.DEFINITIONS[index]
		result[#result + 1] = { id = source.key, key = source.key, value = source.key,
			text = text(source.titleKey), swatches = palette.previewSwatches(source.key),
			selected = palette.getActiveKey() == source.key }
	end
	return result
end

local function itemCount(state)
	local total = 0
	for index = 1, #(state.items or {}) do
		total = total + math.max(0, math.floor(tonumber(state.items[index].count) or 0))
	end
	return total
end

-- Surface specs retain Spanish only as visual design metadata. Runtime text
-- always crosses the product i18n boundary so Kahlua never decodes a raw UTF-8
-- fallback embedded in generated Lua and every locale can use its own catalog.
local function runtimeI18n()
	return {
		["options.state.operational.title"] = text("IGUI_GS_OptionsEnergyTitle"),
		["options.state.operational.help"] = text("IGUI_GS_OptionsEnergyHelp"),
		["options.state.operational.power"] = text("IGUI_GS_ValPowerOk"),
		["options.state.operational.terminal"] = text("IGUI_GS_OptionsTerminalsTitle"),
		["options.state.operational.zones"] = text("IGUI_GS_StatsZones", 0),
		["options.state.operational.access"] = text("IGUI_GS_OptionsAccessHelp"),
		["options.state.resources.title"] = text("IGUI_GS_OptionsInformationTitle"),
		["options.state.resources.help"] = text("IGUI_GS_OptionsInformationHelp"),
		["options.state.resources.summary"] = text("IGUI_GS_OptionsSummaryTitle"),
		["options.state.resources.access"] = text("IGUI_GS_OptionsAccessHelp"),
		["options.state.resources.consumption"] = text("IGUI_GS_StatsConsumption", 0),
		["options.state.resources.capacity-available"] = text("IGUI_GS_OptionsInformationTitle"),
		["options.state.resources.capacity"] = text("IGUI_GS_OptionsInformationTitle"),
		["options.state.resources.warning"] = text("IGUI_GS_OptionsSummaryHelp"),
		["options.summary.title"] = text("IGUI_GS_OptionsSummaryTitle"),
		["options.summary.help"] = text("IGUI_GS_OptionsSummaryHelp"),
		["options.summary.information.title"] = text("IGUI_GS_OptionsInformationTitle"),
		["options.summary.information.help"] = text("IGUI_GS_OptionsInformationHelp"),
		["options.summary.energy.title"] = text("IGUI_GS_OptionsEnergyTitle"),
		["options.summary.energy.help"] = text("IGUI_GS_OptionsEnergyHelp"),
		["options.state.range.title"] = text("IGUI_GS_OptionsRangeTitle"),
		["options.state.range.help"] = text("IGUI_GS_OptionsRangeHelp"),
		["options.state.range.terminal"] = text("IGUI_GS_DistTerminalUse", 0),
		["options.state.range.network"] = text("IGUI_GS_DistNetworkReach", 0),
		["options.state.palette.title"] = text("IGUI_GS_UIPaletteLabel"),
		["options.state.palette.help"] = text("IGUI_GS_OptionsPaletteHelp"),
		["options.admin.terminals.title"] = text("IGUI_GS_OptionsTerminalsTitle"),
		["options.admin.terminals.help"] = text("IGUI_GS_OptionsTerminalsHelp"),
		["options.admin.column.terminal-name"] = text("IGUI_GS_ColTerminalName"),
		["options.admin.column.coordinates"] = text("IGUI_GS_ColTerminalCoords"),
		["options.admin.column.terminal-role"] = text("IGUI_GS_ColTerminalRole"),
		["options.admin.column.status"] = text("IGUI_GS_ColTerminalStatus"),
		["options.admin.members.title"] = text("IGUI_GS_OptionsMembersTitle"),
		["options.admin.members.help"] = text("IGUI_GS_OptionsMembersHelp"),
		["options.admin.column.member-role"] = text("IGUI_GS_PermColRole"),
		["options.admin.column.member-name"] = text("IGUI_GS_PermColMemberName"),
		["options.admin.column.connection"] = text("IGUI_GS_PermColConnection"),
		["options.admin.succession.title"] = text("IGUI_GS_SuccessionTitle"),
		["options.admin.succession.header-help"] = text("IGUI_GS_SuccessionHeaderHelp"),
		["options.admin.succession.no-backup-help"] = text("IGUI_GS_SuccessionNoBackupHelp"),
		["options.admin.succession.help"] = text("IGUI_GS_SuccessionBody"),
		["options.admin.succession.warning"] = text("IGUI_GS_PermNoBackupWarn"),
		["options.admin.claim"] = text("IGUI_GS_ClaimOwnershipButton"),
		["options.admin.access.title"] = text("IGUI_GS_PermAddBlockTitle"),
		["options.admin.access.help"] = text("IGUI_GS_OptionsAccessHelp"),
		["options.admin.access.select"] = text("IGUI_GS_OptionsAccessSelect"),
		["options.admin.access.add"] = text("IGUI_GS_AddMember"),
		["options.admin.access.empty"] = text("IGUI_GS_PermPickNone"),
	}
end

function TabOptionsContext.create(terminal)
	if type(terminal) ~= "table" then return nil, "invalid_terminal" end
	local context = { terminal = terminal, terminalRows = {}, memberRows = {}, accessPicks = {}, disposed = false }
	context.actions = {
		["options.open-terminal"] = function(envelope)
			local row = context.terminalRows[semantic(envelope).rowKey]
			local editor = GlobalStorageSiK.TerminalTerminalEditor
			if not row or not editor or type(editor.open) ~= "function" then return false, "terminal_row_unavailable" end
			return editor.open(terminal, row)
		end,
		["options.open-member"] = function(envelope)
			local row = context.memberRows[semantic(envelope).rowKey]
			local editor = GlobalStorageSiK.TerminalMemberEditor
			if not row or not editor or type(editor.open) ~= "function" then return false, "member_row_unavailable" end
			local perms = (terminal.terminalState or {}).permissions or {}
			return editor.open(terminal, row, perms.playerRole or perms.role or "member")
		end,
		["options.claim-ownership"] = function()
			if type(terminal.onClaimAsAdmin) ~= "function" then return false, "claim_unavailable" end
			terminal:onClaimAsAdmin(); return true
		end,
		["options.select-access"] = function(envelope) context.selectedAccessKey = semantic(envelope).value; return true end,
		["options.add-access"] = function()
			local pick = context.accessPicks[context.selectedAccessKey]
			if not pick then return false, "access_subject_not_selected" end
			if pick.kind == "whole" then
				if type(terminal.onAddPermissionFaction) ~= "function" then return false, "action_unavailable" end
				terminal:onAddPermissionFaction(pick.value)
			else
				if type(terminal.onAddPermissionUser) ~= "function" then return false, "action_unavailable" end
				terminal:onAddPermissionUser(pick.value, pick.characterId, pick.factionUsername)
			end
			return true
		end,
		["options.change-palette"] = function(envelope)
			local payload = semantic(envelope)
			local key = payload.id or payload.key or payload.value
			local palette = GlobalStorageSiK.UIPalette
			if not key or not palette or type(palette.save) ~= "function" then return false, "palette_unavailable" end
			palette.save(playerFor(terminal), key)
			if type(palette.refreshTree) == "function" then
				palette.refreshTree(GlobalStorageSiK.TerminalUI and GlobalStorageSiK.TerminalUI.instance)
			end
			if GlobalStorageSiK.TerminalOptions
				and type(GlobalStorageSiK.TerminalOptions.refreshScroll) == "function" then
				GlobalStorageSiK.TerminalOptions.refreshScroll(terminal, terminal.terminalState or {})
			end
			if type(terminal.setDirty) == "function" then terminal:setDirty(true) end
			return true
		end,
	}

	function context:snapshot(serverState)
		if self.disposed then return nil, "disposed" end
		local state = serverState or terminal.terminalState or {}
		local perms = state.permissions or {}
		self.terminalRows, self.memberRows, self.accessPicks = {}, {}, {}
		local terminals = normalizeTerminalRows(state, self.terminalRows)
		local members = normalizeMemberRows(perms, self.memberRows)
		local access = accessRows(perms, self.accessPicks)
		if not self.accessPicks[self.selectedAccessKey] then self.selectedAccessKey = nil end
		local powered = state.powered ~= false
		local terminalCount = #terminals
		if state.terminalAnchor and state.terminalAnchor.x then terminalCount = math.max(1, terminalCount) end
		local zoneCount, nodeCount = #(state.zones or {}), #(state.nodes or {})
		local capacity = state.capacity or {}
		local installedAddons = state.installedAddons or {}
		local antennaInstalled = installedAddons.TabletLink ~= nil
		local antennaRange = 0
		if antennaInstalled and GlobalStorageSiK.TerminalAccess
			and GlobalStorageSiK.TerminalAccess.getWirelessRangeForNetwork then
			antennaRange = GlobalStorageSiK.TerminalAccess.getWirelessRangeForNetwork(
				playerFor(terminal), state.networkId or state.activeNetworkId, state.terminalAnchor)
		end
		local role = perms.playerRole or perms.role or "member"
		local isOwner, isAdmin = role == "owner", role == "admin" or role == "owner"
		local backupCount = tonumber(perms.backupMemberCount)
		local backupKnown = backupCount ~= nil and backupCount == backupCount and backupCount >= 0
		GlobalStorageSiK.Log.debug("OptionsTables", "snapshot rows terminals="
			.. tostring(#terminals) .. " members=" .. tostring(#members))
		return {
			data = { options = {
				state = {
					power = status(powered and text("IGUI_GS_ValPowerOk") or text("IGUI_GS_ValPowerOff"), powered and "success" or "danger", true),
					terminalStatus = status(text("IGUI_GS_StatsTerminals", terminalCount)),
					zonesStatus = status(text("IGUI_GS_StatsZones", zoneCount)),
					resourceSummary = status(text("IGUI_GS_StatsNodes", nodeCount)),
					accessStatus = status(text("IGUI_GS_StatsMembers", #members)),
					capacity = CapacityPresentation.fromState(capacity, { count = itemCount(state) }),
					terminalRange = status(text("IGUI_GS_DistTerminalUse", GlobalStorageSiK.Sandbox and GlobalStorageSiK.Sandbox.getTerminalProximityRange and GlobalStorageSiK.Sandbox.getTerminalProximityRange() or 0)),
					networkRange = status(text("IGUI_GS_DistNetworkReach", GlobalStorageSiK.Sandbox and GlobalStorageSiK.Sandbox.getContainerMaxDistance and GlobalStorageSiK.Sandbox.getContainerMaxDistance() or 0)),
					antennaRange = status(text("IGUI_GS_DistWifiReach", antennaRange)), palettes = paletteRows(),
				},
				admin = {
					terminalHeaderActions = {}, terminals = terminals, memberHeaderActions = {}, members = members,
					successionHint = status(text("IGUI_GS_SuccessionBody"), "textMuted"),
					backupWarning = status(text("IGUI_GS_PermNoBackupWarn"), "textMuted"),
					successionIndicator = { icon = "sik.alert.warning.24", tooltip = text("IGUI_GS_SuccessionTooltip"), severity = "warning" },
					noBackupIndicator = { icon = "sik.alert.warning.24", tooltip = text("IGUI_GS_SuccessionNoBackupTooltip"), severity = "warning" },
					canClaim = status(text("IGUI_GS_ClaimOwnershipButton"), "warning"),
					access = { items = access, selected = self.selectedAccessKey,
						subject = { items = access, selected = self.selectedAccessKey } }, accessActions = {},
				},
			} },
			state = { options = {
				admin = { access = { subject = { items = access, selected = self.selectedAccessKey } } },
			} },
			conditions = {
				owner = isOwner, ["owner-without-backup"] = isOwner and backupKnown and backupCount == 0,
				["owner-with-backup"] = isOwner and (not backupKnown or backupCount > 0),
				["can-claim-as-admin"] = perms.canClaimAsAdmin == true, ["admin-or-owner"] = isAdmin,
				["add-without-selection"] = isAdmin and self.selectedAccessKey == nil,
				["tablet-addon-installed"] = antennaInstalled,
			},
			i18n = runtimeI18n(),
			tableOptions = {
				["options-terminals-table"] = { autoHeight = true, minRows = 0 },
				["options-members-table"] = { autoHeight = true, minRows = 0 },
			},
			actions = self.actions, playerNum = terminal.playerNum or 0,
		}
	end

	function context:dispose()
		if self.disposed then return false end
		self.disposed = true
		self.actions, self.terminalRows, self.memberRows, self.accessPicks, self.terminal = nil, nil, nil, nil, nil
		return true
	end
	return context
end

return TabOptionsContext
