-- ClientCommand is reliable but unordered in B42. Keep an opening/cancellation
-- fence for each connected player; these are transient intent counters, not IDs
-- or authority supplied by another player.
GlobalStorageSiK = GlobalStorageSiK or {}
GlobalStorageSiK.TerminalCommandOrder = GlobalStorageSiK.TerminalCommandOrder or {}
local sessions = {}
local MAX_SEQUENCE = 2147483647

local function validSequence(sequence)
	return type(sequence) == "number" and sequence == sequence and sequence >= 1
		and sequence <= MAX_SEQUENCE and sequence == math.floor(sequence)
end

local function pruneDisconnected(player, visitOnlinePlayers)
	if type(visitOnlinePlayers) ~= "function" then return end
	local live = {[player]=true}
	local ok = pcall(visitOnlinePlayers, function(online) live[online] = true end)
	if not ok then return end
	local retired = {}
	for previous in pairs(sessions) do
		if not live[previous] then retired[#retired + 1] = previous end
	end
	for i=1,#retired do sessions[retired[i]] = nil end
end

function GlobalStorageSiK.TerminalCommandOrder.accept(player, command, args, visitOnlinePlayers)
	if command ~= "openTerminal" and command ~= "closeTerminal" and command ~= "pingTerminalAccess" then return true end
	if not player or type(args) ~= "table" then return false end
	if command == "pingTerminalAccess" and args.reopen ~= nil and type(args.reopen) ~= "boolean" then return false end
	local previous = sessions[player]
	if command == "pingTerminalAccess" and args.reopen ~= true then
		if not previous then return args.openSeq == nil end
		return args.openSeq == previous.sequence and previous.activeSeq ~= nil
	end
	pruneDisconnected(player, visitOnlinePlayers)
	local sequence
	if command == "closeTerminal" then sequence = args.closeSeq else sequence = args.openSeq end
	-- Legacy traffic remains possible until this player starts sequenced traffic.
	-- Afterwards an uncorrelated close/open cannot override a newer intent.
	if sequence == nil then return previous == nil end
	if not validSequence(sequence) then return false end
	local closing = command == "closeTerminal"
	if closing and args.targetOpenSeq ~= nil and not validSequence(args.targetOpenSeq) then return false end
	if previous then
		local delta = (sequence - previous.sequence) % MAX_SEQUENCE
		if delta == 0 then
			if not closing or previous.closed then return false end
		elseif delta >= MAX_SEQUENCE / 2 then
			return false
		end
	end
	local activeSeq = previous and previous.activeSeq
	local closeActive = closing and (args.targetOpenSeq == nil or args.targetOpenSeq == activeSeq)
	if closeActive then activeSeq = nil end
	-- A targeted cancellation may only fence an unaccepted request. Keep a
	-- general close with that same fence usable for the still-active session.
	sessions[player] = {sequence=sequence, closed=closeActive, activeSeq=activeSeq}
	if closing then return closeActive end
	return true
end

-- Admission orders intents; only a successful authoritative opening becomes
-- the session a targeted cancellation may close.
function GlobalStorageSiK.TerminalCommandOrder.markOpened(player, sequence)
	local state = sessions[player]
	if state and state.sequence == sequence and not state.closed then
		state.activeSeq = sequence
	end
end
