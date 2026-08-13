--[[
	GlobalStorageSiK - Acción temporizada de craft (UI bloqueada)
	Autor: SiK
	Fecha: 2025-06-24
	Descripción: Aplica el tiempo de craft antes de enviar el comando al servidor.
]]

require "TimedActions/ISBaseTimedAction"
require "GS_TerminalRecipes"
require "GS_AddonRecipes"
require "GS_AddonRegistry"
require "GS_NetClient"

GS_CraftTerminalTimedAction = ISBaseTimedAction:derive("GS_CraftTerminalTimedAction")

---@return boolean
function GS_CraftTerminalTimedAction:isValid()
	if not self.character or not self.recipeId then
		return false
	end
	local addonId = GlobalStorageSiK.AddonRecipes.addonIdFromCardId(self.recipeId)
	if addonId then
		local def = GlobalStorageSiK.AddonRegistry.get(addonId)
		if not def then
			return false
		end
		return GlobalStorageSiK.AddonRecipes.canCraftModule(self.character, def) == true
	end
	local recipe = GlobalStorageSiK.TerminalRecipes.getById(self.recipeId)
	if not recipe then
		return false
	end
	local craftOpts = nil
	if self.craftExtra and self.craftExtra.desktopItemId and GlobalStorageSiK.TerminalRecipes.findInventoryItemById then
		craftOpts = {
			desktopItem = GlobalStorageSiK.TerminalRecipes.findInventoryItemById(
				self.character, self.craftExtra.desktopItemId),
		}
	end
	local ok = GlobalStorageSiK.TerminalRecipes.canCraft(self.character, recipe, craftOpts)
	return ok == true
end

---@return boolean
function GS_CraftTerminalTimedAction:waitToStart()
	return false
end

function GS_CraftTerminalTimedAction:update()
end

function GS_CraftTerminalTimedAction:start()
	self:setActionAnim("Craft")
	self:setAnimVariable("CraftType", "electronics")
	self.character:reportEvent("EventCrafting")
	self:setOverrideHandModels(nil, nil)
end

--- Se interrumpe la accion ANTES de completarse (jugador se mueve, corre, le
--- golpean, otro mod fuerza un reset de la cola de acciones, etc.). El motor
--- SIEMPRE llama a stop() al salir de la cola, tanto si termino con exito
--- (justo despues de perform()) como si se cancelo a medias — perform() en
--- cambio SOLO se ejecuta si la accion llega a completarse entera. Antes,
--- la ventana "Install GS Terminal" ponia busy=true al lanzar la accion y
--- SOLO lo desactivaba cuando llegaba la respuesta del servidor (via
--- onCraftResult) — si la accion se interrumpia, ese comando nunca se
--- llegaba a mandar (perform() nunca se ejecuta), nunca llegaba respuesta,
--- y la ventana se quedaba en "Instalando terminal..." para siempre, con el
--- boton deshabilitado y sin forma de reintentar. Bug confirmado por un
--- usuario de la comunidad.
--- IMPORTANTE (compatibilidad SP): esta notificacion es puramente local via
--- llamada directa de funcion, NO depende de ninguna respuesta de red — en
--- singleplayer real jamas "llega" una respuesta de servidor a la que
--- esperar (aunque isServer()/isClient() son ambos true en SP, ver nota SP
--- del proyecto), asi que el fix debe funcionar sin ese roundtrip. Al ser
--- una llamada de funcion sincrona en el mismo cliente, funciona igual en
--- SP y en MP.
function GS_CraftTerminalTimedAction:stop()
	ISBaseTimedAction.stop(self)
	if not self._performed then
		if GlobalStorageSiK.TerminalInstallChoice and GlobalStorageSiK.TerminalInstallChoice.onCraftResult then
			GlobalStorageSiK.TerminalInstallChoice.onCraftResult({
				ok = false,
				message = GlobalStorageSiK.I18n.text("IGUI_GS_CraftCancelled"),
				recipeId = self.recipeId,
			})
		end
	end
end

function GS_CraftTerminalTimedAction:perform()
	self._performed = true
	local addonId = GlobalStorageSiK.AddonRecipes.addonIdFromCardId(self.recipeId)
	if addonId then
		GlobalStorageSiK.NetClient.sendCommand("craftAddonModule", { addonId = addonId })
	else
		local payload = { recipeId = self.recipeId }
		if self.craftExtra and self.craftExtra.desktopItemId then
			payload.desktopItemId = self.craftExtra.desktopItemId
		end
		GlobalStorageSiK.NetClient.sendCommand("craftTerminalRecipe", payload)
	end
	ISBaseTimedAction.perform(self)
end

---@param character IsoPlayer
---@param recipeId string
---@param maxTime number
---@param craftExtra table|nil desktopItemId
---@return GS_CraftTerminalTimedAction
function GS_CraftTerminalTimedAction:new(character, recipeId, maxTime, craftExtra)
	local o = ISBaseTimedAction.new(self, character)
	o.recipeId = recipeId
	o.craftExtra = craftExtra
	o._performed = false
	o.maxTime = math.max(50, tonumber(maxTime) or 100)
	o.stopOnWalk = true
	o.stopOnRun = true
	o.useProgressBar = true
	return o
end
