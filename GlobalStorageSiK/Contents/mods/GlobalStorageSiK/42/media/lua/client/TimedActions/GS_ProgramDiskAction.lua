--[[
	GlobalStorageSiK - Acción temporizada "Programar disquete"
	Descripción: Consume un disquete en blanco y entrega el disquete
	programado correspondiente al terminar. Todo lo valida el servidor
	(GS_DiskProgramming.program) - esta acción solo anima y, al completarse
	entera, manda el comando "programDisk" con el id de programa elegido.
]]

require "TimedActions/ISBaseTimedAction"
require "GS_NetClient"
require "GS_DiskProgramming"
require "GS_Sandbox"

GS_ProgramDiskAction = ISBaseTimedAction:derive("GS_ProgramDiskAction")

--- Tiempo fijo (ticks), en línea con GS_AcquirePCAction (100) pero más corto:
--- grabar un disquete es una tarea más ligera que montar hardware.
local PROGRAM_DISK_TIME = 60

---@return boolean
function GS_ProgramDiskAction:isValid()
	if not self.character or not self.programId then
		return false
	end
	return GlobalStorageSiK.DiskProgramming.knowsProgram(self.character, self.programId)
		and GlobalStorageSiK.DiskProgramming.terminalInRange(self.character)
end

---@return boolean
function GS_ProgramDiskAction:waitToStart()
	return false
end

function GS_ProgramDiskAction:update()
end

function GS_ProgramDiskAction:start()
	self:setActionAnim("Craft")
	self:setAnimVariable("CraftType", "electronics")
	self.character:reportEvent("EventCrafting")
	self:setOverrideHandModels(nil, nil)
end

--- Ver GS_AcquirePCAction:stop() - misma lección: si se interrumpe, avisar
--- localmente sin esperar respuesta de red.
function GS_ProgramDiskAction:stop()
	ISBaseTimedAction.stop(self)
	if not self._performed and self.character and self.character.setHaloNote then
		self.character:setHaloNote(GlobalStorageSiK.I18n.text("IGUI_GS_CraftCancelled"), 220, 180, 100, 300)
	end
end

function GS_ProgramDiskAction:perform()
	self._performed = true
	ISBaseTimedAction.perform(self)
	GlobalStorageSiK.NetClient.sendCommand("programDisk", { programId = self.programId })
end

---@param character IsoPlayer
---@param programId string
---@return GS_ProgramDiskAction
function GS_ProgramDiskAction:new(character, programId)
	local o = ISBaseTimedAction.new(self, character)
	o._performed = false
	o.programId = programId
	o.maxTime = PROGRAM_DISK_TIME
	o.stopOnWalk = true
	o.stopOnRun = true
	o.useProgressBar = true
	return o
end
