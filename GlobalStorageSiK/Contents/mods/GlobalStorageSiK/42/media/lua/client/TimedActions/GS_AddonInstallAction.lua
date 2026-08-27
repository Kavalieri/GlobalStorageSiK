--[[
	GlobalStorageSiK - Acción temporizada "Instalar/Desinstalar addon"
	Autor: SiK
	Fecha: 2026-08-27
	Descripción: pedido explícito del usuario - instalar/desinstalar un addon
	del terminal (impresora 3D, antena WiFi, pizarra digital, disquetera...)
	ya no es instantáneo al pulsar el botón: ahora corre una acción
	cronometrada con barra de progreso y animación de manos trabajando
	(mismo patrón ya probado en GS_ProgramDiskAction.lua/
	GS_InstallTerminalReaderAction.lua - "Craft"/"electronics"). Todo lo
	valida el servidor igual que antes (GS_Addons.install/uninstall); esta
	acción solo anima y, al completarse ENTERA, manda el comando
	installAddon/uninstallAddon - si el jugador se mueve o cancela a medio
	camino, no se envía nada (perform() solo corre si termina).
]]

require "TimedActions/ISBaseTimedAction"
require "GS_NetClient"
require "GS_AddonRegistry"
require "GS_Addons"
require "GS_Sandbox"

GS_AddonInstallAction = ISBaseTimedAction:derive("GS_AddonInstallAction")

---@return boolean
function GS_AddonInstallAction:isValid()
	if not self.character or not self.addonId then
		return false
	end
	if self.mode == "install" then
		return GlobalStorageSiK.AddonRegistry.canInstallModule(self.character, self.addonId, self.networkId, self.anchor) == true
	end
	-- Desinstalar: mismo par de requisitos ya revalidados por el boton antes
	-- de arrancar esta accion (disquetera disponible + disquete de
	-- desinstalacion si el registro lo exige).
	local hasReader = GlobalStorageSiK.Addons.hasReaderAvailable(self.character, self.networkId, self.anchor)
	local uninstallDiskItem = GlobalStorageSiK.Addons.uninstallDiskItem()
	local inv = self.character:getInventory()
	local hasUninstallDisk = not uninstallDiskItem
		or (inv and (inv:getItemCountRecurse(uninstallDiskItem) or 0) >= 1)
	return hasReader and hasUninstallDisk
end

---@return boolean
function GS_AddonInstallAction:waitToStart()
	return false
end

function GS_AddonInstallAction:update()
end

function GS_AddonInstallAction:start()
	self:setActionAnim("Craft")
	self:setAnimVariable("CraftType", "electronics")
	self.character:reportEvent("EventCrafting")
	self:setOverrideHandModels(nil, nil)
end

--- Ver GS_ProgramDiskAction:stop()/GS_InstallTerminalReaderAction:stop() -
--- misma leccion: si se interrumpe, avisar localmente sin esperar red.
function GS_AddonInstallAction:stop()
	ISBaseTimedAction.stop(self)
	if not self._performed and self.character and self.character.setHaloNote then
		self.character:setHaloNote(GlobalStorageSiK.I18n.text("IGUI_GS_CraftCancelled"), 220, 180, 100, 300)
	end
end

function GS_AddonInstallAction:perform()
	self._performed = true
	ISBaseTimedAction.perform(self)
	local command = self.mode == "install" and "installAddon" or "uninstallAddon"
	GlobalStorageSiK.NetClient.sendCommand(command, { addonId = self.addonId, searchQuery = self.searchQuery })
end

---@param character IsoPlayer
---@param addonId string
---@param mode "install"|"uninstall"
---@param networkId string|nil
---@param anchor table|nil
---@param searchQuery string|nil
---@return GS_AddonInstallAction
function GS_AddonInstallAction:new(character, addonId, mode, networkId, anchor, searchQuery)
	local o = ISBaseTimedAction.new(self, character)
	o._performed = false
	o.addonId = addonId
	o.mode = mode
	o.networkId = networkId
	o.anchor = anchor
	o.searchQuery = searchQuery
	-- Mismo tiempo configurable que instalar el programa de la disquetera
	-- sobre el ordenador (GS_Sandbox.getTerminalInstallTime) - misma
	-- naturaleza de tarea (manipular hardware/cableado del terminal), sin
	-- inventar una opcion de sandbox nueva solo para esto.
	o.maxTime = math.max(50, GlobalStorageSiK.Sandbox.getTerminalInstallTime())
	o.stopOnWalk = true
	o.stopOnRun = true
	o.useProgressBar = true
	return o
end
