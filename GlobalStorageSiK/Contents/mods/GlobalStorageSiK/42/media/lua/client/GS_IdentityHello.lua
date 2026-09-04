--[[
	GlobalStorageSiK - Aviso de conexion para resolucion de identidad
	Autor: SiK
	Fecha: 2026-08-26

	BUG REAL cerrado (revision tecnica de Desarrollo tras probar en TEST,
	3 reconexiones reales en el servidor de pruebas): Events.OnCreatePlayer
	del SERVIDOR nunca se disparaba en un dedicado (confirmado por ausencia
	total de su traza siempre-visible en el log) - la identidad de personaje
	solo se resolvia de forma perezosa al primer runtime_lookup (abrir un
	terminal), nunca al conectar. El cliente avisa explicitamente al servidor
	nada mas cargar su propio personaje, y el servidor (ver "identityHello" en
	GS_Server.lua/onClientCommand) resuelve todo usando el objeto `player`
	AUTORITATIVO que el propio motor entrega al comando, nunca un dato que
	pudiera venir en el payload.

	BUG REAL cerrado (2026-08-26, revision tecnica de Desarrollo tras la
	SIGUIENTE prueba en TEST: "no existe ninguna traza reason=identity_hello
	en esta conexion"): la version anterior enviaba el aviso UNA sola vez, sin
	comprobar si el envio tuvo exito (GlobalStorageSiK.NetClient.getPlayer()
	puede devolver nil justo en el instante de OnCreatePlayer) ni esperar
	confirmacion del servidor - si fallaba esa unica vez, la identidad volvia
	a depender del runtime_lookup perezoso de siempre. Ahora reintenta cada
	pocos ticks hasta recibir el ACK del servidor (identityHelloAck) o agotar
	un numero maximo de intentos.
]]

require "GS_NetClient"

local MAX_ATTEMPTS = 20
local RETRY_TICKS = 10
local attempts = 0
local tickCounter = 0
local awaitingAck = false

local function trySend()
	attempts = attempts + 1
	local sent = GlobalStorageSiK.NetClient.sendCommand("identityHello", {})
	if not sent and GlobalStorageSiK.Log then
		GlobalStorageSiK.Log.debug("Identity", "identityHello send failed (player not ready) attempt=" .. attempts)
	end
end

local function onCreatePlayer()
	attempts = 0
	tickCounter = 0
	-- En SP real isClient() e isServer() son false: no existe un servidor
	-- remoto que pueda devolver identityHelloAck. La identidad se resuelve en
	-- el mismo proceso autoritativo y no debe iniciar este handshake MP.
	if type(isClient) ~= "function" or not isClient() then
		awaitingAck = false
		return
	end
	awaitingAck = true
	trySend()
end

local function onTick()
	if not awaitingAck then return end
	tickCounter = tickCounter + 1
	if tickCounter < RETRY_TICKS then return end
	tickCounter = 0
	if attempts >= MAX_ATTEMPTS then
		awaitingAck = false
		if GlobalStorageSiK.Log then
			GlobalStorageSiK.Log.error("Identity", "identityHelloGaveUp", "sin ACK del servidor tras " .. attempts .. " intentos")
		end
		return
	end
	trySend()
end

local function onServerCommand(module, command, args)
	if module == GlobalStorageSiK.MOD_ID and command == "identityHelloAck" then
		awaitingAck = false
	end
end

Events.OnCreatePlayer.Add(onCreatePlayer)
Events.OnTick.Add(onTick)
Events.OnServerCommand.Add(onServerCommand)
