--[[
	GlobalStorageSiK - Consumo de combustible de generador (opcional)
	Autor: SiK
	Fecha: 2026-08-03
	Descripcion: Cada pocos segundos reales, para cada red activa con un
	generador encendido cerca de su controlador, resta combustible segun las
	horas de partida transcurridas y el tamaño de la red (Sandbox
	EnableFuelConsumption/FuelConsumptionBase/FuelConsumptionPerContainer).
	Desactivado por defecto - sin esto activado, la red solo EXIGE que haya
	corriente, nunca gasta nada (ver GS_Power.lua).
	Solo corre en contexto autoritativo (servidor dedicado, host, SP real) -
	nunca en un cliente MP puro, para no duplicar el gasto ni desincronizar.
]]

require "GS_Sandbox"
require "GS_Network"
require "GS_Power"
require "GS_Config"
require "GS_Log"

GlobalStorageSiK.FuelConsumption = {}

--- Horas de partida (getWorldAgeHours) la ultima vez que se aplico consumo
--- a cada red - permite calcular el delta real transcurrido en vez de
--- asumir un intervalo fijo (importante porque la velocidad del tiempo de
--- partida varia con el sandbox "DayLength" y puede pausarse).
local lastHoursByNetwork = {}

local CHECK_INTERVAL_MS = 30000
local lastCheckMs = 0

local function nowMs()
	return (getTimestampMs and getTimestampMs()) or 0
end

--- Cuenta nodos (contenedores) de una red directamente del registro.
---@param registry table
---@param networkId string
---@return number
local function countNetworkNodes(registry, networkId)
	local count = 0
	for _, node in pairs(registry.nodes or {}) do
		local zone = registry.zones and registry.zones[node.zoneId]
		if zone and zone.networkId == networkId and node.membership ~= "excluded" then
			count = count + 1
		end
	end
	return count
end

--- [WIP] Reparte `drain` entre varias fuentes (generadores/baterias),
--- proporcional a la carga actual de cada una (misma filosofia que usan
--- PSR/ISA para repartir carga entre baterias enlazadas: cuanto mas llena
--- esta una fuente, mas aporta). Nunca deja ninguna por debajo de 0.
---@param sources table[] { obj, isBattery }
---@param drain number
local function distributeDrain(sources, drain)
	local total = 0
	for i = 1, #sources do
		total = total + GlobalStorageSiK.Power.getSourceLevel(sources[i].obj, sources[i].isBattery)
	end
	if total <= 0 then
		return
	end
	for i = 1, #sources do
		local level = GlobalStorageSiK.Power.getSourceLevel(sources[i].obj, sources[i].isBattery)
		local share = drain * (level / total)
		GlobalStorageSiK.Power.drainSource(sources[i].obj, sources[i].isBattery, share)
	end
end

---@param networkId string
---@param network table
---@param registry table
local function tickNetwork(networkId, network, registry)
	if not network or not network.controller then
		return
	end
	local c = network.controller
	local useGrid = GlobalStorageSiK.Sandbox.enableGeneratorGrid()
	local sources
	if useGrid then
		sources = GlobalStorageSiK.Power.findAllSourcesInBuilding(c.x, c.y, c.z)
	else
		local single = GlobalStorageSiK.Power.findNearbyRunningGenerator(c.x, c.y, c.z)
		sources = single and { { obj = single, isBattery = false } } or {}
	end
	if #sources == 0 then
		-- Sin generador/bateria encendida cerca (red electrica normal, o
		-- apagado/sin combustible): no se aplica ningun gasto, tal como se
		-- acordo ("antes del apagon, sin impacto hasta que se use generador").
		return
	end
	local ok, nowHours = pcall(function() return getGameTime():getWorldAgeHours() end)
	if not ok or not nowHours then
		return
	end
	local lastHours = lastHoursByNetwork[networkId]
	lastHoursByNetwork[networkId] = nowHours
	if not lastHours then
		-- Primera vez que se ve esta red con fuente activa: no hay delta
		-- todavia que aplicar, solo se marca el punto de partida.
		return
	end
	local deltaHours = nowHours - lastHours
	if deltaHours <= 0 then
		return
	end
	local containerCount = countNetworkNodes(registry, networkId)
	local rate = GlobalStorageSiK.Power.computeConsumptionRate(containerCount)
	if rate <= 0 then
		return
	end
	local drain = rate * deltaHours
	distributeDrain(sources, drain)
	if GlobalStorageSiK.Sandbox.debugMode() then
		GlobalStorageSiK.Log.debug("FuelConsumption", string.format(
			"net=%s containers=%d rate=%.3f deltaH=%.3f drain=%.3f fuentes=%d grid=%s",
			tostring(networkId), containerCount, rate, deltaHours, drain, #sources, tostring(useGrid)))
	end
end

local function onTick()
	if not GlobalStorageSiK.isAuthoritative or not GlobalStorageSiK.isAuthoritative() then
		return
	end
	local now = nowMs()
	if now - lastCheckMs < CHECK_INTERVAL_MS then
		return
	end
	lastCheckMs = now
	if not GlobalStorageSiK.Sandbox.enableFuelConsumption() then
		return
	end
	local registry = GlobalStorageSiK.Network.getRegistry()
	GlobalStorageSiK.Network.ensureRegistry(registry)
	for networkId, network in pairs(registry.networks or {}) do
		pcall(tickNetwork, networkId, network, registry)
	end
end

if Events and Events.OnTick then
	Events.OnTick.Add(onTick)
end
