-- Staff writes are correlated, bounded and never replayed automatically.
require "GS_NativeWorldOverrides"
require "GS_NetClient"
local Editor = {}
GlobalStorageSiK.NativeWorldEditor = Editor
local states, sequence = {}, 0
local World = GlobalStorageSiK.NativeWorldOverrides

local function clock()
	local value = getTimestampMs and getTimestampMs()
	if type(value) == "number" and value == value and value >= 0 and value < math.huge then return value end
end

function Editor.state(playerNum)
	if type(playerNum) ~= "number" or playerNum < 0 or playerNum > 3 or playerNum ~= math.floor(playerNum) then return nil end
	states[playerNum] = states[playerNum] or { status = "idle" }
	local state = states[playerNum]
	local now = clock()
	if state.status == "pending" and (not now or now < state.startedAt or now >= state.deadline) then
		state.status, state.reason = "uncertain", "response_timeout"
	end
	return state
end

function Editor.submit(playerNum, captured, operation, nativePath, reason)
	local state, now = Editor.state(playerNum), clock()
	if not state or not now then return false, "invalid_time" end
	if state.status == "pending" or state.status == "uncertain" then return false, "busy" end
	if type(captured) ~= "table" or not World.validFullType(captured.fullType)
		or not World.validRevision(captured.revision) then return false, "source_missing" end
	if captured.revision ~= World.getRevision() then return false, "revision_conflict" end
	if operation ~= "apply" and operation ~= "restore" then return false, "invalid_request" end
	if operation == "apply" and not World.decodePath(nativePath) then return false, "invalid_choice" end
	if type(reason) ~= "string" or #reason > 512 or not reason:find("%S") or reason:find("%c") then
		return false, "invalid_reason"
	end
	if sequence == 2147483647 then return false, "sequence_exhausted" end
	sequence = sequence + 1
	state.requestId, state.fullType = sequence, captured.fullType
	state.status, state.reason = "pending", nil
	state.startedAt, state.deadline = now, now + 15000
	local sent = GlobalStorageSiK.NetClient.sendCommand("changeTaxonomyOverride", {
		requestId = sequence, fullType = captured.fullType, expectedRevision = captured.revision,
		expectedClassifierSchema = captured.classifierSchema, expectedCatalogFingerprint = captured.catalogFingerprint,
		operation = operation, nativePath = operation == "apply" and nativePath or nil, reason = reason,
	}, playerNum)
	if not sent and state.status == "pending" then
		-- The transport can fail after dispatch; an uncertain mutation is not retried.
		state.status, state.reason = "uncertain", "send_failed"
	end
	return sent, state.reason
end

function Editor.onResult(args)
	if type(args) ~= "table" or type(args.ok) ~= "boolean" then return end
	for _, state in pairs(states) do
		if state.requestId == args.requestId and (state.status == "pending" or state.status == "uncertain") then
			if args.fullType ~= nil and args.fullType ~= state.fullType then return end
			if args.ok and (not World.validRevision(args.revision) or args.fullType ~= state.fullType) then return end
			state.status = args.ok and "success" or "failed"
			state.reason = type(args.reason) == "string" and args.reason:sub(1, 80) or nil
			state.revision, state.syncPending = args.revision, args.syncPending == true
			if GlobalStorageSiK.NativeWorldSync then GlobalStorageSiK.NativeWorldSync.request(true) end
			return
		end
	end
end

function Editor.reset()
	states = {} -- Keep the sequence: a late ACK must not match a new world.
end

return Editor
