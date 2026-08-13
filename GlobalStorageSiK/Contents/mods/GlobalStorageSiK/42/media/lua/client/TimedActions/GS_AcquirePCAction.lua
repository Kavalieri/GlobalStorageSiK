--[[
	GlobalStorageSiK - Acción temporizada "Conseguir PC"
	Descripción: Consume las 4 piezas GS (I/O Controller, Keyboard,
	Motherboard, PC Tower) y entrega un Base.Mov_DesktopComputer al terminar.
	Todo lo valida el servidor (GS_PCAcquire.craft) - esta acción solo anima
	y, al completarse entera, manda el comando "acquirePC".
]]

require "TimedActions/ISBaseTimedAction"
require "GS_NetClient"
require "GS_PCAcquire"
require "GS_Sandbox"

GS_AcquirePCAction = ISBaseTimedAction:derive("GS_AcquirePCAction")

---@return boolean
function GS_AcquirePCAction:isValid()
	if not self.character then
		return false
	end
	return GlobalStorageSiK.PCAcquire.status(self.character).allReady
end

---@return boolean
function GS_AcquirePCAction:waitToStart()
	return false
end

function GS_AcquirePCAction:update()
end

function GS_AcquirePCAction:start()
	self:setActionAnim("Craft")
	self:setAnimVariable("CraftType", "electronics")
	self.character:reportEvent("EventCrafting")
	self:setOverrideHandModels(nil, nil)
end

--- Ver GS_InstallTerminalReaderAction:stop() - misma lección: si se
--- interrumpe, avisar localmente sin esperar respuesta de red.
function GS_AcquirePCAction:stop()
	ISBaseTimedAction.stop(self)
	if not self._performed and self.character and self.character.setHaloNote then
		self.character:setHaloNote(GlobalStorageSiK.I18n.text("IGUI_GS_CraftCancelled"), 220, 180, 100, 300)
	end
end

function GS_AcquirePCAction:perform()
	self._performed = true
	ISBaseTimedAction.perform(self)
	GlobalStorageSiK.NetClient.sendCommand("acquirePC", {})
end

---@param character IsoPlayer
---@return GS_AcquirePCAction
function GS_AcquirePCAction:new(character)
	local o = ISBaseTimedAction.new(self, character)
	o._performed = false
	o.maxTime = GlobalStorageSiK.Sandbox.getPCAcquireCraftTime()
	o.stopOnWalk = true
	o.stopOnRun = true
	o.useProgressBar = true
	return o
end
