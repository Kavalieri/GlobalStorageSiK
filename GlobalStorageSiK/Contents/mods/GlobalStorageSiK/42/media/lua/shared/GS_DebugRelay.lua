--[[
	GlobalStorageSiK - Contrato neutral de transporte de diagnostico

	Los loggers del Core y de los addons publican aqui sus lineas ya formateadas.
	Solo el proceso de servidor dedicado instala un sink de salida; SP y host
	comparten consola con su cliente y no necesitan duplicar cada linea por red.
	El transporte concreto vive en GS_DebugRelayServer/Client.
]]

GlobalStorageSiK = GlobalStorageSiK or {}
GlobalStorageSiK.DebugRelay = GlobalStorageSiK.DebugRelay or {}

local Relay = GlobalStorageSiK.DebugRelay
Relay._requestedSources = Relay._requestedSources or {}

---@return string "SRV"|"HOST"|"CLI"|"SP"
function Relay.processTag()
	local server = isServer and isServer() or false
	local client = isClient and isClient() or false
	if server and not client then return "SRV" end
	if server and client then return "HOST" end
	if client then return "CLI" end
	return "SP"
end
---@param sink function|nil
function Relay.setServerSink(sink)
	Relay._serverSink = sink
end

---@param line string
---@return boolean queued
function Relay.emit(line)
	if Relay.processTag() ~= "SRV" or type(Relay._serverSink) ~= "function" then
		return false
	end
	local ok, queued = pcall(Relay._serverSink, tostring(line))
	return ok and queued == true
end

--- Solicitud declarativa usada por cada addon. El Core no necesita conocer
--- qué addons existen: el cliente de transporte solo sabe que al menos una
--- fuente de diagnostico quiere recibir la consola del dedicado.
---@param source string|nil
function Relay.requestClientSubscription(source)
	Relay._requestedSources[tostring(source or "unknown")] = true
	if type(Relay._clientSubscribe) == "function" then
		pcall(Relay._clientSubscribe)
	end
end

---@return boolean
function Relay.hasRequestedSources()
	local count = 0
	for _ in pairs(Relay._requestedSources) do
		count = count + 1
	end
	return count > 0
end

--- Imprime un lote remoto sin volver a pasarlo por Log.debug: de ese modo se
--- conserva exactamente la marca [SRV], no se filtra dos veces y no hay eco.
---@param payload string|nil
function Relay.printRemotePayload(payload)
	if type(payload) ~= "string" or payload == "" then
		return
	end
	for line in string.gmatch(payload .. "\n", "([^\n]*)\n") do
		if line ~= "" then
			print(line)
		end
	end
end
