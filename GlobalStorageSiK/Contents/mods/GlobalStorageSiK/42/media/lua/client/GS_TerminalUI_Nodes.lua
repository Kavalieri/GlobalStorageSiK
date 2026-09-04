-- Global Storage SiK - product adapter for the tab-red hierarchical table.
-- No widget, row pool, header, hitbox or geometry is owned here.

require "GS_Config"
require "GS_I18n"
require "GS_RulesUI"
require "GS_TerminalUI_Config"
require "GS_TerminalUI_NodeEditor"
require "GS_TerminalUI_ZoneEditor"
require "GS_NodeHighlight"

GlobalStorageSiK.TerminalNodes = GlobalStorageSiK.TerminalNodes or {}

local Nodes = GlobalStorageSiK.TerminalNodes
local T = GlobalStorageSiK.I18n.text
local INHERIT_COLOR = { 0.36, 0.48, 0.58, 1 }
local MUTED_COLOR = { 0.45, 0.48, 0.52, 1 }

local function cell(text, r, g, b)
	return { text = tostring(text or ""), color = { r = r, g = g, b = b, a = 1 } }
end

local function nodeProtocolInfo(ownRules, zoneRules)
	if ownRules and #ownRules > 0 then
		local summary = GlobalStorageSiK.RulesUI.compactSummary(ownRules)
		if summary then
			local color = GlobalStorageSiK.RulesUI.conditionColor(summary.condition, MUTED_COLOR)
			local label = summary.label
			if summary.extraCount > 0 then label = label .. " +" .. tostring(summary.extraCount) end
			return label, color[1], color[2], color[3]
		end
	end
	if zoneRules and #zoneRules > 0 then
		local summary = GlobalStorageSiK.RulesUI.compactSummary(zoneRules)
		if summary then
			local color = GlobalStorageSiK.RulesUI.conditionColor(summary.condition, INHERIT_COLOR)
			return summary.label, color[1], color[2], color[3]
		end
	end
	return T("IGUI_GS_ProtocolGlobal"), MUTED_COLOR[1], MUTED_COLOR[2], MUTED_COLOR[3]
end

local function nodeStatusInfo(node)
	if node.offline then
		return { key = "offline", label = T("IGUI_GS_NodeStatusOffline"),
			detail = T("IGUI_GS_NodeStatusOfflineTip"), r = 0.92, g = 0.35, b = 0.3, incident = "red" }
	end
	if node.physicalAnomaly then
		return { key = "conflict", label = T("IGUI_GS_NodeStatusConflict"),
			detail = T("IGUI_GS_NodeStatusConflictTip"), r = 0.92, g = 0.35, b = 0.3, incident = "red" }
	end
	if node.membership == "excluded" then
		return { key = "excluded", label = T("IGUI_GS_NodeStatusExcluded"),
			detail = T("IGUI_GS_NodeStatusExcludedTip"), r = 0.75, g = 0.78, b = 0.82 }
	end
	if node.enabled == false then
		return { key = "disabled", label = T("IGUI_GS_NodeStatusDisabled"),
			detail = T("IGUI_GS_NodeStatusDisabledTip"), r = 0.92, g = 0.75, b = 0.35 }
	end
	return { key = "ok", label = T("IGUI_GS_NodeStatusOk"), r = 0.45, g = 0.85, b = 0.45 }
end

local function incidentInfo(list)
	local count, hasRed = 0, false
	for index = 1, #(list or {}) do
		local info = nodeStatusInfo(list[index])
		if info.incident then
			count = count + 1
			hasRed = hasRed or info.incident == "red"
		end
	end
	return { count = count, level = hasRed and "red" or (count > 0 and "amber" or nil) }
end

function Nodes.getNetworkIncidentInfo(nodes)
	return incidentInfo(nodes)
end

local function occupancyDisplay(percent)
	if not percent then return cell(T("IGUI_GS_PunctuationEmDash"), 0.45, 0.48, 0.52) end
	local warning = GlobalStorageSiK.Config.WEIGHT_WARN_PERCENT or 80
	local critical = GlobalStorageSiK.Config.WEIGHT_CRITICAL_PERCENT or 95
	if percent >= critical then return cell(tostring(percent) .. "%", 0.92, 0.35, 0.3) end
	if percent >= warning then return cell(tostring(percent) .. "%", 0.92, 0.75, 0.35) end
	return cell(tostring(percent) .. "%", 0.75, 0.78, 0.82)
end

local function sortValue(node, column)
	if column == "priority" then return tonumber(node.priority) or 50 end
	if column == "status" then return nodeStatusInfo(node).label end
	if column == "occupancy" then return tonumber(node.occupancyPercent) or -1 end
	if column == "protocol" then
		local summary = node.rules and #node.rules > 0
			and GlobalStorageSiK.RulesUI.compactSummary(node.rules) or nil
		return summary and summary.label:lower() or ""
	end
	return (node.displayName or node.name or ""):lower()
end

local function sortNodes(nodes, column, direction)
	local ascending = direction ~= "desc"
	table.sort(nodes, function(left, right)
		local a, b = sortValue(left, column), sortValue(right, column)
		if a == b then
			a = (left.displayName or left.name or ""):lower()
			b = (right.displayName or right.name or ""):lower()
		end
		if ascending then return a < b end
		return a > b
	end)
end

local function zoneMaps(zones)
	local names, priorities, enabled, rules, occupancy, sources, order = {}, {}, {}, {}, {}, {}, {}
	for index = 1, #(zones or {}) do
		local zone = zones[index]
		if zone and zone.id then
			local id = tostring(zone.id)
			names[id], priorities[id] = zone.name or id, tonumber(zone.priority) or 50
			enabled[id], rules[id] = zone.enabled ~= false, zone.rules
			occupancy[id], sources[id] = zone.occupancyPercent, zone
			order[#order + 1] = id
		end
	end
	return names, priorities, enabled, rules, occupancy, sources, order
end

local function sortZones(order, names, priorities, column, direction)
	if column ~= "name" and column ~= "priority" then
		return
	end
	local ascending = direction ~= "desc"
	table.sort(order, function(a, b)
		local va, vb
		if column == "priority" then va, vb = priorities[a] or 50, priorities[b] or 50
		else va, vb = (names[a] or ""):lower(), (names[b] or ""):lower() end
		if va == vb then va, vb = a, b end
		if ascending then return va < vb end
		return va > vb
	end)
end

local function nodeRow(node, zoneRules)
	local protocol, r, g, b = nodeProtocolInfo(node.rules, zoneRules)
	local status = nodeStatusInfo(node)
	return {
		id = "node:" .. tostring(node.id or node.nodeId or "?"), kind = "node",
		name = node.displayName or node.name or "?", protocol = cell(protocol, r, g, b),
		priority = tonumber(node.priority) or 50,
		status = cell(status.label, status.r, status.g, status.b),
		occupancy = occupancyDisplay(node.occupancyPercent), sourceNode = node,
		tooltip = status.detail,
	}
end

local function zoneRow(id, list, names, priorities, enabled, rules, occupancy, sources)
	local protocol, r, g, b = nodeProtocolInfo(rules[id], nil)
	local incident = incidentInfo(list)
	local status
	if enabled[id] == false then status = cell(T("IGUI_GS_NodeStatusExcluded"), 0.75, 0.78, 0.82)
	elseif incident.count > 0 then
		local red = incident.level == "red"
		status = cell("! " .. tostring(incident.count), 0.92, red and 0.35 or 0.75, red and 0.3 or 0.35)
	else status = cell(T("IGUI_GS_NodeStatusOk"), 0.45, 0.85, 0.45) end
	local children = {}
	for index = 1, #list do children[index] = nodeRow(list[index], rules[id]) end
	return {
		id = "zone:" .. tostring(id), kind = "zone", zoneId = id,
		name = T("IGUI_GS_ZoneGroupHeader", names[id] or id, #list),
		protocol = cell(protocol, r, g, b), priority = priorities[id] or 50,
		status = status, occupancy = occupancyDisplay(occupancy[id]),
		children = children, sourceZone = sources[id],
	}
end

function Nodes.presentationModel(nodes, zones, sortColumn, sortDirection)
	local names, priorities, enabled, rules, occupancy, sources, order = zoneMaps(zones)
	local grouped, unknown = {}, {}
	for index = 1, #(nodes or {}) do
		local node = nodes[index]
		local id = node.zoneId and tostring(node.zoneId) or ""
		if id == "" then unknown[#unknown + 1] = node
		else grouped[id] = grouped[id] or {}; grouped[id][#grouped[id] + 1] = node end
	end
	sortZones(order, names, priorities, sortColumn, sortDirection)
	local rows = {}
	local function append(id, list)
		if not list or #list == 0 then return end
		sortNodes(list, sortColumn, sortDirection)
		rows[#rows + 1] = zoneRow(id, list, names, priorities, enabled, rules,
			occupancy, sources)
		grouped[id] = nil
	end
	for index = 1, #order do append(order[index], grouped[order[index]]) end
	local remainder = {}
	for id, _ in pairs(grouped) do remainder[#remainder + 1] = id end
	table.sort(remainder)
	for index = 1, #remainder do append(remainder[index], grouped[remainder[index]]) end
	if #unknown > 0 then
		local id = ""
		names[id], priorities[id], enabled[id], rules[id], sources[id] =
			T("IGUI_GS_ZoneUnknown"), 50, true, nil, nil
		sortNodes(unknown, sortColumn, sortDirection)
		rows[#rows + 1] = zoneRow(id, unknown, names, priorities, enabled, rules,
			occupancy, sources)
	end
	return { rows = rows, emptyText = T("IGUI_GS_NoNodesYet"),
		sortKey = sortColumn, sortAsc = sortDirection ~= "desc" }
end

function Nodes.activateRow(terminal, row, allNodes, categories)
	if not terminal or not row then return false, "row_unavailable" end
	if row.kind == "zone" then
		if GlobalStorageSiK.NodeHighlight then
			GlobalStorageSiK.NodeHighlight.highlightZone(row.zoneId,
				row.sourceZone and row.sourceZone.name or row.name, allNodes or {})
		end
		if terminal.canEditNetworkConfig and not terminal:canEditNetworkConfig(true) then
			return false, "permission_denied"
		end
		if row.sourceZone and GlobalStorageSiK.TerminalZoneEditor then
			GlobalStorageSiK.TerminalZoneEditor.open(terminal, row.sourceZone, allNodes or {})
			return true
		end
		return false, "zone_unavailable"
	end
	local node = row.sourceNode
	if not node then return false, "node_unavailable" end
	if GlobalStorageSiK.NodeHighlight then
		GlobalStorageSiK.NodeHighlight.highlightNode(node, allNodes or {})
	end
	if terminal.canEditNetworkConfig and not terminal:canEditNetworkConfig(true) then
		return false, "permission_denied"
	end
	GlobalStorageSiK.TerminalNodeEditor.open(terminal, node, categories or {})
	return true
end

function Nodes.tableOptions(terminal, context)
	return {
		keyOf = function(row, index) return row and row.id or index end,
		onExpansionChange = function(payload)
			local row = payload and payload.item
			if row and row.kind == "zone" and GlobalStorageSiK.NodeHighlight then
				GlobalStorageSiK.NodeHighlight.highlightZone(row.zoneId,
					row.sourceZone and row.sourceZone.name or row.name,
					context.nodes or {})
			end
		end,
		onSort = function(payload)
			context.sortColumn = payload and payload.key or nil
			context.sortDirection = payload and payload.ascending == false and "desc" or "asc"
			local model = Nodes.presentationModel(context.nodes, context.zones,
				context.sortColumn, context.sortDirection)
			if payload and payload.component then payload.component:setRows(model.rows, true) end
			return true
		end,
	}
end

return Nodes
