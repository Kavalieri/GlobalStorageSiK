--[[
	GlobalStorageSiK - Relay de diagnostico del servidor dedicado

	Agrupa lineas para no convertir cada Log.debug en un paquete de red. Mantiene
	solo nombres de cuenta (no referencias Java persistentes), limita cola/lote y
	se activa unicamente con la opcion sandbox explicita.
]]

require "GS_Config"
require "GS_Sandbox"
require "GS_DebugRelay"

if not (isServer and isServer()) or (isClient and isClient()) then
	return
end

local Relay = GlobalStorageSiK.DebugRelay
local subscribers = {}
local queue = {}
local queueHead = 1
local queueTail = 0
local dropped = 0
local lastFlushAt = 0

local MAX_QUEUE_LINES = 256
local MAX_BATCH_LINES = 20
local MAX_BATCH_BYTES = 12000
local MAX_LINE_BYTES = 8000
local FLUSH_INTERVAL_MS = 250

local function relayEnabled()
	return GlobalStorageSiK.Sandbox.debugRelayToClients()
end

local function subscriberCount()
	local count = 0
	for _ in pairs(subscribers) do count = count + 1 end
	return count
end

local function clearQueue()
	queue = {}
	queueHead = 1
	queueTail = 0
	dropped = 0
end

---@param line string
---@return boolean
local function enqueue(line)
	if not relayEnabled() or subscriberCount() == 0 then
		return false
	end
	line = tostring(line):gsub("\r\n", "\\n"):gsub("[\r\n]", "\\n")
	if #line > MAX_LINE_BYTES then
		line = "[SRV][GlobalStorageSiK:WARN:DebugRelay] oversized line omitted bytes=" .. tostring(#line)
	end
	if (queueTail - queueHead + 1) >= MAX_QUEUE_LINES then
		dropped = dropped + 1
		return false
	end
	queueTail = queueTail + 1
	queue[queueTail] = line
	return true
end

Relay.setServerSink(enqueue)

local function usernameOf(player)
	local ok, username = pcall(function() return player and player:getUsername() end)
	if ok and type(username) == "string" and username ~= "" then
		return username
	end
	return nil
end

local function onlineSubscribers()
	local result = {}
	local seen = {}
	local players = getOnlinePlayers and getOnlinePlayers()
	if players then
		for i = 0, players:size() - 1 do
			local player = players:get(i)
			local username = usernameOf(player)
			if username and subscribers[username] then
				result[#result + 1] = player
				seen[username] = true
			end
		end
	end
	local stale = {}
	for username in pairs(subscribers) do
		if not seen[username] then stale[#stale + 1] = username end
	end
	for i = 1, #stale do subscribers[stale[i]] = nil end
	return result
end

local function takeBatch()
	local lines = {}
	local bytes = 0
	if dropped > 0 then
		local notice = "[SRV][GlobalStorageSiK:WARN:DebugRelay] dropped=" .. tostring(dropped)
		lines[#lines + 1] = notice
		bytes = #notice
		dropped = 0
	end
	while queueHead <= queueTail and #lines < MAX_BATCH_LINES do
		local line = queue[queueHead]
		local extra = #line + (#lines > 0 and 1 or 0)
		if #lines > 0 and (bytes + extra) > MAX_BATCH_BYTES then break end
		queue[queueHead] = nil
		queueHead = queueHead + 1
		lines[#lines + 1] = line
		bytes = bytes + extra
	end
	if queueHead > queueTail then
		queue = {}
		queueHead = 1
		queueTail = 0
	end
	return table.concat(lines, "\n")
end

local function flush()
	local now = getTimestampMs and getTimestampMs() or 0
	if (now - lastFlushAt) < FLUSH_INTERVAL_MS then return end
	lastFlushAt = now
	if not relayEnabled() then
		subscribers = {}
		clearQueue()
		return
	end
	if queueHead > queueTail and dropped == 0 then return end
	local recipients = onlineSubscribers()
	if #recipients == 0 then
		clearQueue()
		return
	end
	local payload = takeBatch()
	if payload == "" then return end
	for i = 1, #recipients do
		pcall(sendServerCommand, recipients[i], GlobalStorageSiK.MOD_ID, "debugTraceBatch", {
			payload = payload,
		})
	end
end

local function onClientCommand(module, command, player, args)
	if module ~= GlobalStorageSiK.MOD_ID or command ~= "debugTraceSubscribe" then return end
	local username = usernameOf(player)
	if not username then return end
	if relayEnabled() and args and args.enabled == true then
		subscribers[username] = true
		pcall(sendServerCommand, player, GlobalStorageSiK.MOD_ID, "debugTraceStatus", {
			payload = "[SRV][GlobalStorageSiK:SYSTEM:DebugRelay] subscribed",
		})
	else
		subscribers[username] = nil
	end
end

Events.OnClientCommand.Add(onClientCommand)
Events.OnTick.Add(flush)
