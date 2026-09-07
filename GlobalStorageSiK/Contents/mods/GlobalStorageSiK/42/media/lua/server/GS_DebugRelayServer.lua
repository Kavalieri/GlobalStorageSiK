--[[
	GlobalStorageSiK - Relay de diagnostico del servidor dedicado

	Agrupa lineas para no convertir cada Log.debug en un paquete de red. Mantiene
	player+onlineId en la sesión para validar identidad contra la instancia actual,
	limita cola/lote y se activa unicamente con la opcion sandbox explicita.
]]

require "GS_Config"
require "GS_Sandbox"
require "GS_DebugRelay"

if not (isServer and isServer()) or (isClient and isClient()) then
	return
end

local Relay = GlobalStorageSiK.DebugRelay
local subscribers = {} -- sessionId -> { username = string, player = player, onlineId = number|nil }
local queue = {}
local queueHead = 1
local queueTail = 0
local dropped = 0
local lastFlushAt = 0
local ADMIN_LEVEL = "admin"

local MAX_QUEUE_LINES = 256
local MAX_BATCH_LINES = 20
local MAX_BATCH_BYTES = 12000
local MAX_LINE_BYTES = 8000
local FLUSH_INTERVAL_MS = 250

local function relayEnabled()
	return GlobalStorageSiK.Sandbox.debugRelayToClients()
end

local function playerAccessLevel(player)
	local ok, accessLevel = pcall(function()
		return player and player:getAccessLevel()
	end)
	if ok and accessLevel ~= nil then
		return accessLevel
	end
	return nil
end

local function isExactAdmin(player)
	return playerAccessLevel(player) == ADMIN_LEVEL
end

local function playerSession(player)
	local ok, username = pcall(function() return player and player:getUsername() end)
	if not ok or type(username) ~= "string" or username == "" then
		return nil
	end

	local okOnlineId, resolvedOnlineId = pcall(function() return player:getOnlineID() end)
	if not (okOnlineId and resolvedOnlineId ~= nil) then
		return nil
	end
	local onlineId = resolvedOnlineId
	return tostring(username) .. ":" .. tostring(onlineId), tostring(username), onlineId
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

local function clearSubscriberBySession(sessionId)
	subscribers[sessionId] = nil
end

Relay.setServerSink(enqueue)

local function onlineSubscribers()
	local result = {}
	local seen = {}
	local players = getOnlinePlayers and getOnlinePlayers()
	if players then
		for i = 0, players:size() - 1 do
			local player = players:get(i)
			local sessionId = playerSession(player)
			local entry = sessionId and subscribers[sessionId]
			if sessionId and entry and entry.player == player and isExactAdmin(player) then
				result[#result + 1] = player
				seen[sessionId] = true
			else
				if sessionId then
					clearSubscriberBySession(sessionId)
				end
			end
		end
	end
	local stale = {}
	for sessionId in pairs(subscribers) do
		if not seen[sessionId] then stale[#stale + 1] = sessionId end
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
	local recipients = onlineSubscribers()
	if #recipients == 0 then
		-- Si no hay suscriptores administrativos vigentes, mantener limpieza de sesión.
		if queueHead <= queueTail or dropped > 0 then
			clearQueue()
		end
		return
	end
	if queueHead > queueTail and dropped == 0 then
		return
	end
	if queueHead > queueTail and dropped == 0 then return end
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
	local sessionId, username, onlineId = playerSession(player)
	if not sessionId or not username then return end
	if relayEnabled() and args and args.enabled == true then
		if isExactAdmin(player) then
			subscribers[sessionId] = { username = username, player = player, onlineId = onlineId }
			pcall(sendServerCommand, player, GlobalStorageSiK.MOD_ID, "debugTraceStatus", {
				payload = "[SRV][GlobalStorageSiK:SYSTEM:DebugRelay] subscribed",
			})
		else
			clearSubscriberBySession(sessionId)
		end
	else
		clearSubscriberBySession(sessionId)
	end
end

Events.OnClientCommand.Add(onClientCommand)
Events.OnTick.Add(flush)
