require "GS_RoutingProtocol"
GlobalStorageSiK.RoutingClient = {}
local Client = GlobalStorageSiK.RoutingClient
local Protocol = GlobalStorageSiK.RoutingProtocol
local slots = {}
local function now() return getTimestampMs and getTimestampMs() or 0 end

function Client.observe(payload)
	if type(payload) ~= "table" or type(payload.configEpoch) ~= "string"
		or type(payload.routingRevision) ~= "number" or not payload.networkId then return end
	local n = tonumber(payload.playerNum) or 0
	if n < 0 or n > 3 then return end
	local state = slots[n]
	if not state or state.epoch ~= payload.configEpoch then
		state = { epoch = payload.configEpoch, sequence = 0, pending = {}, order = {}, revisions = {} }
		slots[n] = state
	end
	state.revisions[payload.networkId] = math.max(state.revisions[payload.networkId] or 0, payload.routingRevision)
end

-- Installed before sendClientCommand, including SP's synchronous response.
-- Repeated clicks on an unresolved identical intent resend the same request.
function Client.prepare(command, args, playerNum, callback)
	if not Protocol.commands[command] then return true end
	local state = slots[playerNum]
	local revision = state and state.revisions[args.networkId]
	if not state or revision == nil then
		if callback then callback({ ok = false, reason = "configuration_unconfirmed" }) end
		return false
	end
	local clean, signature = Protocol.copy(args)
	if not clean then return false end
	signature = command .. signature
	for _, id in ipairs(state.order) do
		local pending = state.pending[id]
		if pending and pending.signature == signature then
			for key, value in pairs(pending.args) do args[key] = value end
			if callback then pending.callback = callback end
			pending.started = now()
			pending.timedOut = false
			return true
		end
	end
	if #state.order >= 32 or state.sequence >= 2147483647 then return false end
	state.sequence = state.sequence + 1
	args.configEpoch, args.requestSeq = state.epoch, state.sequence
	args.requestId = state.epoch .. ":" .. state.sequence
	local metadata = GlobalStorageSiK.Client and GlobalStorageSiK.Client.terminalStateByPlayer
		and GlobalStorageSiK.Client.terminalStateByPlayer[playerNum]
	-- ACK may arrive before refreshed editor metadata. Never use that newer
	-- token to overwrite a list the user still sees at an older revision.
	local visibleRevision = metadata and metadata.networkId == args.networkId and metadata.routingRevision
	args.expectedRoutingRevision = args.expectedRoutingRevision or visibleRevision or revision
	state.pending[args.requestId] = { args = Protocol.copy(args), signature = signature,
		callback = callback, networkId = args.networkId, started = now() }
	state.order[#state.order + 1] = args.requestId
	return true
end

function Client.result(payload)
	if not payload or not payload.routingResult then return false end
	local state = slots[tonumber(payload.playerNum) or 0]
	if not state or state.epoch ~= payload.configEpoch then return true end
	local pending = state.pending[payload.requestId]
	if not pending or pending.networkId ~= payload.networkId then return true end
	Client.observe(payload)
	state.pending[payload.requestId] = nil
	for i = #state.order, 1, -1 do
		if state.order[i] == payload.requestId then table.remove(state.order, i) break end
	end
	if pending.callback then pending.callback(payload) end
	return true
end

function Client.prepareWithdrawal(args,playerNum)
	local state=slots[playerNum]
	if not state then return false end
	if args.withdrawEpoch~=nil then return args.withdrawEpoch==state.epoch end
	state.withdrawSequence=(state.withdrawSequence or 0)+1
	if state.withdrawSequence>2147483647 then return false end
	args.withdrawEpoch,args.withdrawSequence=state.epoch,state.withdrawSequence
	return true
end

-- A timeout is an uncertain result, not a new intent. Keep its ID for retry.
function Client.update()
	for n=0,3 do
		local state=slots[n]
		for _,id in ipairs(state and state.order or {}) do
			local pending=state.pending[id]
			if pending and pending.callback and not pending.timedOut and now()-pending.started>=10000 then
				local callback=pending.callback; pending.timedOut=true
				callback({ok=false,reason="request_timeout",requestId=id,networkId=pending.networkId,playerNum=n})
			end
		end
	end
end
function Client.suspend(playerNum)
	for n=0,3 do
		local state=slots[n]
		if state and (playerNum==nil or playerNum==n) then
			state.revisions={}
			for _,pending in pairs(state.pending) do pending.callback=nil end
		end
	end
end
if Events and Events.OnTick then Events.OnTick.Add(Client.update) end

return Client
