-- Global Storage SiK - product actions for zones shown by tab-red.
-- Composition, controls and geometry belong to the generated SiK.UI surface.

GlobalStorageSiK.TerminalNetworkZones = GlobalStorageSiK.TerminalNetworkZones or {}

local Zones = GlobalStorageSiK.TerminalNetworkZones

function Zones.canConfigure(terminal, notify)
	if not terminal then return false end
	if type(terminal.canEditNetworkConfig) ~= "function" then return true end
	return terminal:canEditNetworkConfig(notify == true)
end

function Zones.create(terminal, kind)
	if not Zones.canConfigure(terminal, true) then return false, "permission_denied" end
	local method
	if kind == "room" then method = terminal.onCreateRoomZone
	elseif kind == "building" then method = terminal.onCreateStructureZone
	elseif kind == "selection" then method = terminal.onCreateSelectionZone end
	if type(method) ~= "function" then return false, "zone_action_unavailable" end
	method(terminal)
	return true
end

function Zones.rescanNetwork(terminal, running)
	if not terminal then return false, "terminal_unavailable" end
	if running == true then
		if type(terminal.onCancelZoneScan) ~= "function" then return false, "cancel_unavailable" end
		terminal:onCancelZoneScan()
		return true
	end
	if type(terminal.onRescanNetwork) ~= "function" then return false, "rescan_unavailable" end
	terminal:onRescanNetwork()
	return true
end

return Zones
