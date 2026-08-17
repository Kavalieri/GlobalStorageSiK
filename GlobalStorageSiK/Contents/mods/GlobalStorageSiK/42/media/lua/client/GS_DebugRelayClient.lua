-- GlobalStorageSiK - receptor cliente de lotes de diagnostico del dedicado.

require "GS_Config"
require "GS_Sandbox"
require "GS_DebugRelay"

if not (isClient and isClient()) or (isServer and isServer()) then
	return
end

local Relay = GlobalStorageSiK.DebugRelay
local subscribed = false
local subscribeAttempts = 0
local nextSubscribeAt = 0
local tickInstalled = false
local RETRY_MS = 2000
local MAX_ATTEMPTS = 15

local function nowMs()
	return getTimestampMs and getTimestampMs() or 0
end

local function removeTick()
	if tickInstalled and Events and Events.OnTick then
		Events.OnTick.Remove(GlobalStorageSiK.DebugRelay._subscribeTick)
	end
	tickInstalled = false
end

local function subscribe()
	if subscribed or not Relay.hasRequestedSources()
		or not GlobalStorageSiK.Sandbox.debugRelayToClients() then
		return
	end
	if subscribeAttempts >= MAX_ATTEMPTS or nowMs() < nextSubscribeAt then return end
	local player = (getSpecificPlayer and getSpecificPlayer(0)) or (getPlayer and getPlayer())
	if not player then return end
	local ok = pcall(sendClientCommand, player, GlobalStorageSiK.MOD_ID, "debugTraceSubscribe", {
		enabled = true,
	})
	if ok then
		-- Enviar sin excepcion no significa que el dedicado haya aceptado el
		-- comando. Solo debugTraceStatus confirma la suscripcion; hasta entonces
		-- se reintenta con pausa y limite para no dejar polling latente.
		subscribeAttempts = subscribeAttempts + 1
		nextSubscribeAt = nowMs() + RETRY_MS
	end
end

Relay._clientSubscribe = subscribe

local function onSubscribeTick()
	if subscribed or not GlobalStorageSiK.Sandbox.debugRelayToClients()
		or subscribeAttempts >= MAX_ATTEMPTS then
		removeTick()
		return
	end
	subscribe()
end

GlobalStorageSiK.DebugRelay._subscribeTick = onSubscribeTick

local function ensureTick()
	if tickInstalled or not Events or not Events.OnTick then return end
	tickInstalled = true
	Events.OnTick.Add(onSubscribeTick)
end

-- La opción de relay es independiente del maestro de debug: WARN/ERROR del
-- dedicado también deben llegar aunque el cliente no active categorías. La
-- petición declarativa puede registrarse antes de que SandboxVars esté listo.
Relay.requestClientSubscription("Core")
ensureTick()

local function onCreatePlayer()
	subscribed = false
	subscribeAttempts = 0
	nextSubscribeAt = 0
	subscribe()
	ensureTick()
end

local function onServerCommand(module, command, args)
	if module == GlobalStorageSiK.MOD_ID and command == "debugTraceBatch" then
		subscribed = true
		removeTick()
		Relay.printRemotePayload(args and args.payload)
	elseif module == GlobalStorageSiK.MOD_ID and command == "debugTraceStatus" then
		subscribed = true
		removeTick()
		Relay.printRemotePayload(args and args.payload)
	end
end

Events.OnCreatePlayer.Add(onCreatePlayer)
Events.OnServerCommand.Add(onServerCommand)
