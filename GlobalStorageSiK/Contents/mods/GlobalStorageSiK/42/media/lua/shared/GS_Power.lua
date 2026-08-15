--[[
	GlobalStorageSiK - Energía de red
	Autor: SiK
	Fecha: 2025-06-23
	Descripción: Comprueba electricidad vanilla en nodos/controlador.
]]

require "GS_Sandbox"
require "GS_Network"

GlobalStorageSiK.Power = {}

--- Comprueba electricidad en una baldosa.
---@param x number
---@param y number
---@param z number
---@return boolean
function GlobalStorageSiK.Power.squareHasPower(x, y, z)
	if not GlobalStorageSiK.Sandbox.requiresPower() then
		return true
	end
	local cell = getCell and getCell() or nil
	if not cell then
		-- Celda no disponible (servidor/cliente sin mundo cargado): no penalizar la red.
		return true
	end
	local square = cell:getGridSquare(x, y, z)
	if not square then
		-- Chunk descargado: estado de energía desconocido; conservar operabilidad hasta verificar.
		return true
	end
	if not square.haveElectricity then
		return true
	end
	return square:haveElectricity()
end

--- Comprueba electricidad en un radio alrededor de una baldosa, usando el
--- mismo alcance que vanilla usa para propagar la energía de un generador
--- (SandboxVars.GeneratorTileRange, mismo Z solamente). Evita que una
--- baldosa "de esquina" sin cableado propio (confirmado con un caso real:
--- terminal en una biblioteca, luces encendidas en la sala de al lado, pero
--- la baldosa exacta del terminal sin electricidad propia) bloquee la red
--- entera cuando el resto del edificio/generador sí la tiene. No
--- reimplementa la propagacion de generadores (eso ya lo hace vanilla
--- internamente sobre square:haveElectricity()) - solo amplia DONDE
--- miramos, de una unica baldosa a su entorno inmediato.
---@param x number
---@param y number
---@param z number
---@return boolean
function GlobalStorageSiK.Power.areaHasPower(x, y, z)
	local cell = getCell and getCell() or nil
	if not cell then
		return false
	end
	local range = (SandboxVars and SandboxVars.GeneratorTileRange) or 20
	range = math.min(math.max(range, 1), 20)
	for dx = -range, range do
		for dy = -range, range do
			if dx ~= 0 or dy ~= 0 then
				local sq = cell:getGridSquare(x + dx, y + dy, z)
				if sq and sq.haveElectricity and sq:haveElectricity() then
					return true
				end
			end
		end
	end
	return false
end

--- Si un objeto de una baldosa es un generador vanilla ENCENDIDO con
--- combustible. Deteccion por "pato" (duck typing: isActivated/getFuel/
--- getMaxFuel/setFuel), no por clase Java exacta - mismo patron ya usado en
--- el resto del mod para reconocer objetos del mundo sin depender de una
--- clase concreta que pueda variar entre builds.
---@param obj IsoObject|nil
---@return boolean
local function isRunningGenerator(obj)
	if not obj or not obj.isActivated or not obj.getFuel or not obj.getMaxFuel or not obj.setFuel then
		return false
	end
	local ok, activated = pcall(function() return obj:isActivated() end)
	if not ok or not activated then
		return false
	end
	local okFuel, fuel = pcall(function() return obj:getFuel() end)
	return okFuel and fuel and fuel > 0
end

--- Busca un generador vanilla encendido con combustible en un radio
--- alrededor de una baldosa (mismo alcance que areaHasPower). Se usa SOLO
--- para el consumo de combustible (GS_FuelConsumption.lua) - nunca para
--- decidir si la red tiene electricidad (eso ya lo hace vanilla via
--- square:haveElectricity(), independientemente de la fuente).
---@param x number
---@param y number
---@param z number
---@return IsoObject|nil
function GlobalStorageSiK.Power.findNearbyRunningGenerator(x, y, z)
	local cell = getCell and getCell() or nil
	if not cell then
		return nil
	end
	local range = (SandboxVars and SandboxVars.GeneratorTileRange) or 20
	range = math.min(math.max(range, 1), 20)
	for dx = -range, range do
		for dy = -range, range do
			local sq = cell:getGridSquare(x + dx, y + dy, z)
			if sq and sq.getObjects then
				local objs = sq:getObjects()
				for i = 0, objs:size() - 1 do
					local obj = objs:get(i)
					if isRunningGenerator(obj) then
						return obj
					end
				end
			end
		end
	end
	return nil
end

--- [WIP] Best-effort: reconoce una bateria de mods solares tipo ISA
--- (Immersive Solar Arrays) o PSR (Plysken Solar Revolution). Confirmado
--- leyendo su codigo (sin copiarlo) que su "power bank" es en realidad un
--- IsoGenerator normal marcado como tal, pero su carga real NO vive en
--- getFuel() - la guardan en su propio ModData bajo las claves "charge" y
--- "maxcapacity" (identicas en los dos mods). Sin garantia de que sigan
--- iguales en futuras versiones de esos mods - si el campo desaparece,
--- esta funcion simplemente deja de reconocerla, sin error.
---@param obj IsoObject|nil
---@return boolean
local function isCompatBattery(obj)
	if not obj or not obj.hasModData or not obj:hasModData() then
		return false
	end
	local ok, md = pcall(function() return obj:getModData() end)
	if not ok or not md then
		return false
	end
	local maxcapacity = md.maxcapacity
	local charge = md.charge
	return type(maxcapacity) == "number" and maxcapacity > 0 and type(charge) == "number" and charge > 0
end

--- Nivel actual de combustible/carga de una fuente (generador normal o
--- bateria compatible), en su propia unidad.
---@param obj IsoObject
---@param isBattery boolean
---@return number
function GlobalStorageSiK.Power.getSourceLevel(obj, isBattery)
	if isBattery then
		local ok, md = pcall(function() return obj:getModData() end)
		return (ok and md and tonumber(md.charge)) or 0
	end
	local ok, fuel = pcall(function() return obj:getFuel() end)
	return (ok and fuel) or 0
end

--- Resta `amount` de una fuente (generador normal o bateria compatible),
--- sin bajar de 0. Devuelve lo realmente restado.
---@param obj IsoObject
---@param isBattery boolean
---@param amount number
---@return number drained
function GlobalStorageSiK.Power.drainSource(obj, isBattery, amount)
	if amount <= 0 then
		return 0
	end
	if isBattery then
		local ok, md = pcall(function() return obj:getModData() end)
		if not ok or not md then
			return 0
		end
		local cur = tonumber(md.charge) or 0
		local drained = math.min(cur, amount)
		md.charge = math.max(0, cur - amount)
		if obj.transmitModData then
			pcall(function() obj:transmitModData() end)
		end
		return drained
	end
	local ok, cur = pcall(function() return obj:getFuel() end)
	if not ok or not cur then
		return 0
	end
	local drained = math.min(cur, amount)
	pcall(function() obj:setFuel(math.max(0, cur - amount)) end)
	return drained
end

--- Bounds de la habitacion (no del edificio completo - ver comentario en
--- findAllSourcesInBuilding) que contiene una baldosa.
---@param x number
---@param y number
---@param z number
---@return table|nil { x1, y1, x2, y2 }
local function getRoomBounds(x, y, z)
	local cell = getCell and getCell() or nil
	if not cell then
		return nil
	end
	local sq = cell:getGridSquare(x, y, z)
	if not sq or not sq.getRoom then
		return nil
	end
	local ok, room = pcall(function() return sq:getRoom() end)
	if not ok or not room or not room.getRoomDef then
		return nil
	end
	local okDef, def = pcall(function() return room:getRoomDef() end)
	if not okDef or not def then
		return nil
	end
	local okBounds, x1, y1, x2, y2 = pcall(function()
		return def:getX(), def:getY(), def:getX2(), def:getY2()
	end)
	if not okBounds then
		return nil
	end
	return { x1 = x1, y1 = y1, x2 = x2, y2 = y2 }
end

--- [WIP] Busca TODOS los generadores encendidos (y, si esta activada la
--- compatibilidad, baterias de mods solares) dentro de la habitacion del
--- terminal - no del edificio completo con varias habitaciones, por
--- seguridad: la API de vanilla para enumerar TODAS las habitaciones de un
--- edificio desde Lua no esta confirmada de forma fiable, mientras que
--- habitacion->getRoomDef() con sus bordes x1/y1/x2/y2 si esta verificada
--- contra el propio motor. En la practica cubre la sala donde esta el
--- terminal, que suele ser donde tambien esta el generador/panel solar.
--- Si la habitacion no se puede determinar, cae al radio de siempre
--- (findNearbyRunningGenerator).
---@param x number
---@param y number
---@param z number
---@return table[] { obj, isBattery }
function GlobalStorageSiK.Power.findAllSourcesInBuilding(x, y, z)
	local bounds = getRoomBounds(x, y, z)
	local batteryCompat = GlobalStorageSiK.Sandbox.enableBatteryCompat()
	if not bounds then
		local single = GlobalStorageSiK.Power.findNearbyRunningGenerator(x, y, z)
		if single then
			return { { obj = single, isBattery = false } }
		end
		return {}
	end
	local cell = getCell and getCell() or nil
	if not cell then
		return {}
	end
	local out = {}
	local seen = {}
	for sx = bounds.x1, bounds.x2 do
		for sy = bounds.y1, bounds.y2 do
			local sq = cell:getGridSquare(sx, sy, z)
			if sq and sq.getObjects then
				local objs = sq:getObjects()
				for i = 0, objs:size() - 1 do
					local obj = objs:get(i)
					if obj and not seen[obj] then
						if isRunningGenerator(obj) then
							seen[obj] = true
							out[#out + 1] = { obj = obj, isBattery = false }
						elseif batteryCompat and isCompatBattery(obj) then
							seen[obj] = true
							out[#out + 1] = { obj = obj, isBattery = true }
						end
					end
				end
			end
		end
	end
	return out
end

--- Consumo total (misma unidad que getFuel()/getMaxFuel() del generador,
--- ej. litros) por hora de partida para una red con containerCount
--- contenedores/nodos registrados. 0 si el consumo esta desactivado.
---@param containerCount number
---@return number
function GlobalStorageSiK.Power.computeConsumptionRate(containerCount)
	if not GlobalStorageSiK.Sandbox.enableFuelConsumption() then
		return 0
	end
	local base = GlobalStorageSiK.Sandbox.fuelConsumptionBase()
	local perContainer = GlobalStorageSiK.Sandbox.fuelConsumptionPerContainer()
	return base + perContainer * (containerCount or 0)
end

--- Serializa el consumo de combustible de una red para mostrar en la UI
--- (pestaña Red): desglose base/por-contenedor/total, en la misma unidad
--- que usa el generador. Todo a 0 si el consumo esta desactivado - la red
--- sigue funcionando igual, solo no gasta nada.
---@param containerCount number
---@return table { enabled, base, perContainer, containerCount, total }
function GlobalStorageSiK.Power.serializeConsumption(containerCount)
	local enabled = GlobalStorageSiK.Sandbox.enableFuelConsumption()
	containerCount = containerCount or 0
	if not enabled then
		return { enabled = false, base = 0, perContainer = 0, containerCount = containerCount, total = 0 }
	end
	local base = GlobalStorageSiK.Sandbox.fuelConsumptionBase()
	local perContainer = GlobalStorageSiK.Sandbox.fuelConsumptionPerContainer()
	return {
		enabled = true,
		base = base,
		perContainer = perContainer,
		containerCount = containerCount,
		total = base + perContainer * containerCount,
	}
end

--- Indica si la sandbox tiene la electricidad de ciudad puesta en "Nunca"
--- (Sandbox_ElecShut = 9, "Deshabilitado"/"Never"/"Mai" en las traducciones
--- oficiales del juego - confirmado leyendo los ficheros de traduccion de
--- PZ, no una suposicion). Pedido explicito de diseño (2026-08-16): un
--- jugador que elige esta opcion esta diciendo "no quiero lidiar con
--- electricidad en absoluto", asi que nuestra red debe respetarlo y no
--- exigir cobertura de red real baldosa a baldosa en ese caso - la
--- alternativa (seguir pidiendole generador/tendido real) iria en contra de
--- la intencion explicita del jugador al elegir esa opcion.
---@return boolean
local function elecNeverShutsOff()
	local ok, val = pcall(function() return SandboxVars and SandboxVars.ElecShut end)
	return ok and val == 9
end

--- Indica si la red tiene energía suficiente para operar.
---@param networkId string|nil
---@return boolean
function GlobalStorageSiK.Power.networkPowered(networkId)
	if not GlobalStorageSiK.Sandbox.requiresPower() then
		return true
	end
	if elecNeverShutsOff() then
		return true
	end

	local registry = GlobalStorageSiK.Network.getRegistry()
	local netId = networkId or registry.defaultNetworkId
	local network = registry.networks and registry.networks[netId]
	local hasController = network and network.controller ~= nil

	if hasController then
		local c = network.controller
		if GlobalStorageSiK.Power.squareHasPower(c.x, c.y, c.z) then
			return true
		end
		if GlobalStorageSiK.Power.areaHasPower(c.x, c.y, c.z) then
			return true
		end
	end

	-- Tambien se comprueban los contenedores enlazados (con o sin
	-- controlador): antes esto SOLO se miraba si no habia controlador,
	-- dejando la red entera a merced de una unica baldosa si lo habia.
	local live = GlobalStorageSiK.Network.getLiveContainers(netId)
	for i = 1, #live do
		local obj = live[i].object
		if obj and obj.getSquare then
			local sq = obj:getSquare()
			if sq and sq.haveElectricity and sq:haveElectricity() then
				return true
			end
		end
	end

	if #live == 0 and not hasController then
		return true
	end

	return false
end
