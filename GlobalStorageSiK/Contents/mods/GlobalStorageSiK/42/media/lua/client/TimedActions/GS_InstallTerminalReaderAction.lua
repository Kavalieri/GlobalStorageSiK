--[[
	GlobalStorageSiK - Acción temporizada de instalación (lector + disquete)
	Autor: SiK
	Descripción: Igual que GS_CraftTerminalTimedAction (misma lección
	aprendida: perform() SOLO corre si la acción llega a completarse entera,
	stop() SIEMPRE corre - hay que limpiar "busy" ahí, no esperar respuesta
	de servidor, para no dejar el diálogo colgado si el jugador se mueve a
	medio instalar). No consume el lector ni el disquete: son reutilizables
	para instalar más terminales.

	Orden del proceso (igual que el método antiguo de craftear+colocar):
	esta acción SOLO instala el programa en el ordenador ya localizado, sin
	preguntar nada. La elección de red nueva/existente se pide DESPUÉS, al
	completarse con éxito (perform), abriendo GS_TerminalInstallReaderChoice
	- no antes de empezar a esperar, como se hacía en la primera versión de
	este flujo.
]]

require "TimedActions/ISBaseTimedAction"
require "GS_NetClient"
require "GS_TerminalAccess"
require "GS_TerminalInstallReaderChoice"

GS_InstallTerminalReaderAction = ISBaseTimedAction:derive("GS_InstallTerminalReaderAction")

---@return boolean
function GS_InstallTerminalReaderAction:isValid()
	if not self.character or not self.target or not self.target.x then
		return false
	end
	local inv = self.character:getInventory()
	if not inv then
		return false
	end
	-- El lector debe estar en el inventario PRINCIPAL, no en una mochila
	-- (getItemCount, no getItemCountRecurse).
	local hasReader = (inv:getItemCount(GlobalStorageSiK.Config.ITEM_TERMINAL_READER) or 0) > 0
	local hasFloppy = (inv:getItemCountRecurse("GlobalStorageSiK.GS_FloppyDisk") or 0) > 0
	if not hasReader or not hasFloppy then
		return false
	end
	-- Revalidar que el ordenador sigue ahí (pudo ser destruido/movido mientras se instalaba)
	-- y que nadie mas lo instalo entretanto.
	if not GlobalStorageSiK.TerminalAccess.isKnownComputerObject(self.target.object) then
		return false
	end
	return not GlobalStorageSiK.TerminalAccess.isTerminalObject(self.target.object)
end

---@return boolean
function GS_InstallTerminalReaderAction:waitToStart()
	return false
end

function GS_InstallTerminalReaderAction:update()
end

function GS_InstallTerminalReaderAction:start()
	self:setActionAnim("Craft")
	self:setAnimVariable("CraftType", "electronics")
	self.character:reportEvent("EventCrafting")
	self:setOverrideHandModels(nil, nil)
end

--- Ver comentario largo en GS_CraftTerminalTimedAction:stop() - misma
--- lección: si se interrumpe, avisar localmente sin esperar red.
function GS_InstallTerminalReaderAction:stop()
	ISBaseTimedAction.stop(self)
	if not self._performed and self.character and self.character.setHaloNote then
		self.character:setHaloNote(GlobalStorageSiK.I18n.text("IGUI_GS_CraftCancelled"), 220, 180, 100, 300)
	end
end

--- Al completarse: NO se manda nada al servidor todavía (no hay red
--- elegida). Solo se abre el diálogo de red nueva/existente - el propio
--- diálogo es quien manda "installTerminalReader" al pulsar Crear o
--- vincular a una red concreta.
function GS_InstallTerminalReaderAction:perform()
	self._performed = true
	ISBaseTimedAction.perform(self)
	GlobalStorageSiK.TerminalInstallReaderChoice.show(self.character, self.target)
end

---@param character IsoPlayer
---@param target table { x, y, z, object }
---@return GS_InstallTerminalReaderAction
function GS_InstallTerminalReaderAction:new(character, target)
	local o = ISBaseTimedAction.new(self, character)
	o.target = target
	o._performed = false
	-- maxTime usa las mismas unidades que "time" en las recetas B42 (no
	-- segundos literales) - igual que GS_CraftTerminalTimedAction, que pasa
	-- el "time" de la receta directamente sin multiplicar.
	o.maxTime = math.max(50, (GlobalStorageSiK.InstallTerminalReader and GlobalStorageSiK.InstallTerminalReader.getInstallTime and GlobalStorageSiK.InstallTerminalReader.getInstallTime()) or 90)
	o.stopOnWalk = true
	o.stopOnRun = true
	o.useProgressBar = true
	return o
end
