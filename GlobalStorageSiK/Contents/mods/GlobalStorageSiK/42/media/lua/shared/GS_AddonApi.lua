--[[
	GlobalStorageSiK - API pública para addons de comunidad
	Autor: SiK
	Fecha: 2025-06-27
	Descripción: Punto de entrada estable para mods que extienden el almacén GS.
	Referencia: registrar addon, comprobar estado, instalar en terminal.
]]

require "GS_AddonRegistry"
require "GS_Addons"

GlobalStorageSiK.AddonApi = GlobalStorageSiK.AddonApi or {}

--- Registra un addon (llamar desde shared al cargar el mod addon).
---@param def table Ver GS_AddonRegistry.register
---@return boolean
function GlobalStorageSiK.AddonApi.register(def)
	return GlobalStorageSiK.AddonRegistry.register(def)
end

---@param addonId string
---@return boolean
function GlobalStorageSiK.AddonApi.isModActive(addonId)
	return GlobalStorageSiK.AddonRegistry.isModActive(addonId)
end

---@param addonId string
---@return table|nil
function GlobalStorageSiK.AddonApi.getDefinition(addonId)
	return GlobalStorageSiK.AddonRegistry.get(addonId)
end

--- Addons cuyo mod Workshop está activo.
---@return table[]
function GlobalStorageSiK.AddonApi.listActive()
	return GlobalStorageSiK.AddonRegistry.listActive()
end

--- Jugador ha leído la revista del addon (conoce todas sus recetas).
---@param player IsoPlayer|nil
---@param addonId string
---@return boolean
function GlobalStorageSiK.AddonApi.playerKnowsMagazine(player, addonId)
	return GlobalStorageSiK.AddonRegistry.playerKnowsMagazine(player, addonId)
end

--- Módulo instalado en un terminal concreto.
---@param networkId string
---@param anchor table|nil
---@param addonId string
---@return boolean
function GlobalStorageSiK.AddonApi.isInstalledOnTerminal(networkId, anchor, addonId)
	return GlobalStorageSiK.Addons.isInstalled(networkId, anchor, addonId)
end
