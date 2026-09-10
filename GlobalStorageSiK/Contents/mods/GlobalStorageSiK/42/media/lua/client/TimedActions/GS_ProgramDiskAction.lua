--[[
	GlobalStorageSiK - Acción temporizada "Programar disquete"
	Descripción: Consume un disquete en blanco y entrega el disquete
	programado correspondiente al terminar. Todo lo valida el servidor
	(GS_DiskProgramming.program) - esta acción solo anima y, al completarse
	entera, manda el comando "programDisk" con el id de programa elegido.
]]

require "TimedActions/ISBaseTimedAction"
require "GS_UI_Feedback"
require "GS_NetClient"
require "GS_DiskProgramming"
require "GS_Sandbox"

GS_ProgramDiskAction = ISBaseTimedAction:derive("GS_ProgramDiskAction")

--- Tiempo fijo (ticks), en línea con GS_AcquirePCAction (100) pero más corto:
--- grabar un disquete es una tarea más ligera que montar hardware.
local PROGRAM_DISK_TIME = 60

---@return boolean
function GS_ProgramDiskAction:isValid()
	if not self.character or not self.programId
		or (self.character.isDead and self.character:isDead()) then
		return false
	end
	if self.terminalContext and (not self.callbacks or type(self.callbacks.isAvailable) ~= "function"
		or not self.callbacks.isAvailable()) then return false end
	if self.sourceItem and (self.sourceItem:getContainer() ~= self.character:getInventory()
		or self.sourceItem:getID() ~= self.sourceItemId
		or self.sourceItem:getFullType() ~= GlobalStorageSiK.DiskProgramming.BLANK_DISK) then return false end
	-- World lookup is bounded to this active action. Completion always forces
	-- a fresh check; the server independently validates before consuming.
	local now = type(getTimestampMs) == "function" and getTimestampMs() or nil
	if not now or not self._nextContextCheck or now >= self._nextContextCheck then
		if self.terminalContext then
			self._contextReady = GlobalStorageSiK.DiskProgramming.terminalInRange(self.character)
		else
			self._contextReady = GlobalStorageSiK.DiskProgramming.contextReadiness(self.character)
		end
		self._nextContextCheck = now and (now + 250) or nil
	end
	return self._contextReady == true
		and GlobalStorageSiK.DiskProgramming.knowsProgram(self.character, self.programId)
end

---@return boolean
function GS_ProgramDiskAction:waitToStart()
	return false
end

function GS_ProgramDiskAction:update()
end

function GS_ProgramDiskAction:start()
	if self.callbacks and type(self.callbacks.onStart) == "function" then
		self.callbacks.onStart(self)
	end
	self:setActionAnim("Craft")
	self:setAnimVariable("CraftType", "electronics")
	self.character:reportEvent("EventCrafting")
	self:setOverrideHandModels(nil, nil)
end

--- Ver GS_AcquirePCAction:stop() - misma lección: si se interrumpe, avisar
--- localmente sin esperar respuesta de red.
function GS_ProgramDiskAction:stop()
	ISBaseTimedAction.stop(self)
	if self.callbacks and type(self.callbacks.onStop) == "function" then
		self.callbacks.onStop(self)
	end
	if not self._performed and self.character then
		GlobalStorageSiK.UIFeedback.halo(self.character,
			GlobalStorageSiK.I18n.text("IGUI_GS_CraftCancelled"),
			220, 180, 100, 300, { tone = "warning", channel = "timed-action" })
	end
end

function GS_ProgramDiskAction:perform()
	self._nextContextCheck = nil
	if not self:isValid() then self:stop(); return end
	self._performed = true
	ISBaseTimedAction.perform(self)
	local payload = { programId = self.programId, itemId = self.sourceItemId }
	if self.terminalContext then
		payload.networkId = self.terminalContext.networkId
		payload.terminalAnchor = self.terminalContext.terminalAnchor
	end
	GlobalStorageSiK.NetClient.sendCommand(self.terminalContext and "programTerminalDisk" or "programDisk",
		payload, self.character)
	if self.callbacks and type(self.callbacks.onPerform) == "function" then
		self.callbacks.onPerform(self)
	end
end

---@param character IsoPlayer
---@param programId string
---@return GS_ProgramDiskAction
function GS_ProgramDiskAction:new(character, programId, callbacks, terminalContext, sourceItem)
	local o = ISBaseTimedAction.new(self, character)
	o._performed = false
	o.programId = programId
	o.callbacks = callbacks
	if sourceItem then
		o.sourceItem = sourceItem
		o.sourceItemId = sourceItem:getID()
	end
	if terminalContext then
		local anchor = terminalContext.terminalAnchor
		o.terminalContext = { networkId = terminalContext.networkId,
			terminalAnchor = { x = anchor.x, y = anchor.y, z = anchor.z } }
	end
	o.maxTime = PROGRAM_DISK_TIME
	o.stopOnWalk = true
	o.stopOnRun = true
	o.useProgressBar = true
	return o
end
