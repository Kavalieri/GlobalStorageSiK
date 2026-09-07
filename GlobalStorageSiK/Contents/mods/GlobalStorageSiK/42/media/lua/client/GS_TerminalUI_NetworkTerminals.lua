-- Global Storage SiK - terminal registry data/actions adapter.
-- The visible Admin table is owned by tab-options and SiK.UI.Table.

require "GS_I18n"
require "GS_NetClient"
require "GS_TerminalCatalog"
require "GS_TerminalUI_TerminalEditor"

GlobalStorageSiK.TerminalNetworkTerminals = GlobalStorageSiK.TerminalNetworkTerminals or {}

local Terminals = GlobalStorageSiK.TerminalNetworkTerminals
local T = GlobalStorageSiK.I18n.text

local function sourceRows(state)
	state = state or {}
	local rows = state.terminals or {}
	if #rows == 0 and state.networkId and GlobalStorageSiK.TerminalCatalog then
		rows = GlobalStorageSiK.TerminalCatalog.serializeRows(state.networkId) or {}
	end
	return rows
end

local function status(row)
	local unknown = row.unknown == true
		or (row.unknown == nil and row.present == false and row.missing ~= true)
	if unknown then return T("IGUI_GS_TerminalUnverified"), "textMuted" end
	if row.missing or row.present == false then return T("IGUI_GS_TerminalMissingPhys"), "danger" end
	if row.suspended then return T("IGUI_GS_TerminalSuspended"), "warning" end
	return T("IGUI_GS_TerminalPresentPhys"), "success"
end

function Terminals.presentationRows(state, rowMap)
	local result = {}
	local rows = sourceRows(state)
	for index = 1, #rows do
		local row = rows[index]
		local id = string.format("terminal:%s:%s:%s", tostring(row.x or 0),
			tostring(row.y or 0), tostring(row.z or 0))
		local label, tone = status(row)
		result[#result + 1] = {
			id = id,
			name = row.label or T("IGUI_GS_PunctuationEmDash"),
			coords = string.format("%d, %d, %d", row.x or 0, row.y or 0, row.z or 0),
			role = row.controller and T("IGUI_GS_TerminalController")
				or T("IGUI_GS_TerminalSecondary"),
			status = { text = label, tone = tone },
		}
		if rowMap then rowMap[id] = row end
	end
	return result
end

function Terminals.activate(terminal, row)
	if not terminal or not row then return false, "terminal_row_unavailable" end
	local editor = GlobalStorageSiK.TerminalTerminalEditor
	if not editor or type(editor.open) ~= "function" then return false, "editor_unavailable" end
	editor.open(terminal, row)
	return true
end

return Terminals
