--[[
	GlobalStorageSiK - Acción temporizada "Fabricar lector" (SiK Disk Reader)
	Descripción: Consume las 3 piezas GS (Reader Casing, Reader Circuit
	Board, Reader Antenna) y entrega un SiK Disk Reader al terminar. Todo lo
	valida el servidor (GlobalStorageSiK.ReaderAcquire.craft) - esta acción
	solo anima y, al completarse entera, manda el comando "acquireReader".
	Mismo patrón que GS_AcquirePCAction.lua.
]]

require "TimedActions/ISBaseTimedAction"
require "GS_NetClient"
require "GS_ReaderAcquire"
require "GS_Sandbox"

GS_AcquireReaderAction = ISBaseTimedAction:derive("GS_AcquireReaderAction")

---@return boolean
function GS_AcquireReaderAction:isValid()
	-- No volver a escanear todos los contenedores cercanos en cada tick de la
	-- barra. La UI valida antes de encolarla y el proceso autoritativo vuelve a
	-- validar justo al terminar, antes de consumir una sola pieza.
	return self.character ~= nil
end

---@return boolean
function GS_AcquireReaderAction:waitToStart()
	return false
end

function GS_AcquireReaderAction:update()
end

function GS_AcquireReaderAction:start()
	self:setActionAnim("Craft")
	self:setAnimVariable("CraftType", "electronics")
	self.character:reportEvent("EventCrafting")
	self:setOverrideHandModels(nil, nil)
end

--- Ver GS_AcquirePCAction:stop() - misma lección: si se interrumpe, avisar
--- localmente sin esperar respuesta de red.
function GS_AcquireReaderAction:stop()
	ISBaseTimedAction.stop(self)
	if not self._performed and self.character and self.character.setHaloNote then
		self.character:setHaloNote(GlobalStorageSiK.I18n.text("IGUI_GS_CraftCancelled"), 220, 180, 100, 300)
	end
end

function GS_AcquireReaderAction:perform()
	self._performed = true
	ISBaseTimedAction.perform(self)
	GlobalStorageSiK.NetClient.sendCommand("acquireReader", {})
end

---@param character IsoPlayer
---@return GS_AcquireReaderAction
function GS_AcquireReaderAction:new(character)
	local o = ISBaseTimedAction.new(self, character)
	o._performed = false
	o.maxTime = GlobalStorageSiK.Sandbox.getReaderAcquireCraftTime()
	o.stopOnWalk = true
	o.stopOnRun = true
	o.useProgressBar = true
	return o
end
