--[[
	GSSiK Addon Tablet - Acceso remoto (árbol de tabletas por niveles)
	Autor: SiK
	Fecha: 2026-08-05
	Descripción: La Antena WiFi GS es el periférico instalado en el
	terminal (emite servicio de red); no la lleva el jugador. Lo que el
	jugador lleva encima es la Tableta GS (tier 1, acceso base) -> Tableta
	Craft/Builder (tier 2, acceso base + su addon) -> Tableta Maestra
	(tier 3, acceso base + Craft + Builder). Cada tier superior también
	cuenta como tier inferior a efectos de acceso base, así que basta con
	llevar UNA tableta encima.
]]

require "GSSiK_Addon_Tablet_ItemHooks"
require "GSSiK_Addon_Tablet_Sandbox"
require "GSSiK_Addon_Tablet_Log"
require "GS_TerminalAccess"
require "GS_Addons"

GSSiK_Addon_Tablet = GSSiK_Addon_Tablet or {}

GSSiK_Addon_Tablet.ITEM_TABLET = "GSSiK_Addon_Tablet.GS_Tablet"
GSSiK_Addon_Tablet.ITEM_TABLET_CRAFT = "GSSiK_Addon_Tablet.GS_TabletCraft"
GSSiK_Addon_Tablet.ITEM_TABLET_BUILDER = "GSSiK_Addon_Tablet.GS_TabletBuilder"
GSSiK_Addon_Tablet.ITEM_TABLET_MASTER = "GSSiK_Addon_Tablet.GS_TabletMaster"

---@param player IsoPlayer|nil
---@param ... string
---@return boolean
local function hasAnyItem(player, ...)
	if not player or not player.getInventory then
		return false
	end
	local inv = player:getInventory()
	local types = { ... }
	for i = 1, #types do
		if (inv:getItemCountRecurse(types[i]) or 0) > 0 then
			return true
		end
	end
	return false
end

--- Acceso base al almacén: cualquier tier de tableta lo da.
---@param player IsoPlayer|nil
---@return boolean
function GSSiK_Addon_Tablet.hasAccessTablet(player)
	return hasAnyItem(
		player,
		GSSiK_Addon_Tablet.ITEM_TABLET,
		GSSiK_Addon_Tablet.ITEM_TABLET_CRAFT,
		GSSiK_Addon_Tablet.ITEM_TABLET_BUILDER,
		GSSiK_Addon_Tablet.ITEM_TABLET_MASTER
	)
end

--- Acceso remoto a la pestaña Craft: tier Craft o Maestra.
---@param player IsoPlayer|nil
---@return boolean
function GSSiK_Addon_Tablet.hasCraftTablet(player)
	local ok = hasAnyItem(player, GSSiK_Addon_Tablet.ITEM_TABLET_CRAFT, GSSiK_Addon_Tablet.ITEM_TABLET_MASTER)
	GSSiK_Addon_Tablet.Log.debug("hasCraftTablet -> " .. tostring(ok))
	return ok
end

--- Acceso remoto a la pestaña Build: tier Builder o Maestra.
---@param player IsoPlayer|nil
---@return boolean
function GSSiK_Addon_Tablet.hasBuilderTablet(player)
	local ok = hasAnyItem(player, GSSiK_Addon_Tablet.ITEM_TABLET_BUILDER, GSSiK_Addon_Tablet.ITEM_TABLET_MASTER)
	GSSiK_Addon_Tablet.Log.debug("hasBuilderTablet -> " .. tostring(ok))
	return ok
end

--- Techo teorico de rango, usado SOLO como radio de escaneo inicial (aun
--- no sabemos a que red ni a que antena nos conectaremos - ver
--- getWirelessRangeForNetwork para el rango REAL ya resuelto). Cualquier
--- tableta da acceso potencial hasta el tier maximo configurado; el tier de
--- LA ANTENA instalada en la red concreta es quien decide el rango de
--- verdad, no la tableta.
---@param player IsoPlayer|nil
---@return number
function GSSiK_Addon_Tablet.getWirelessRangeForPlayer(player)
	if GSSiK_Addon_Tablet.hasAccessTablet(player) then
		return GSSiK_Addon_Tablet.Sandbox.getTier3Range()
	end
	return 0
end

--- Rango inalámbrico REAL para una red concreta: segun el tier de Antena
--- WiFi GS instalado ahi (T1/T2/T3), NO segun la tableta que lleve el
--- jugador - la tableta solo decide SI hay acceso potencial (hasAccess) y
--- que funciones (craft/build), el "hasta donde llega" es cosa de la
--- antena. Sin antena instalada en esa red, 0 (sin cobertura).
---@param player IsoPlayer|nil
---@param networkId string|nil
---@param anchor table|nil
---@return number
function GSSiK_Addon_Tablet.getWirelessRangeForNetwork(player, networkId, anchor)
	if not GSSiK_Addon_Tablet.hasAccessTablet(player) then
		return 0
	end
	if not GlobalStorageSiK.Addons or not GlobalStorageSiK.Addons.isInstalled(networkId, anchor, "TabletLink") then
		GSSiK_Addon_Tablet.Log.debug("getWirelessRangeForNetwork -> antena no instalada, range=0")
		return 0
	end
	local installed = GlobalStorageSiK.Addons.serializeForTerminal(networkId, anchor)["TabletLink"]
	local itemType = installed and installed.itemType
	local range
	if itemType == "GSSiK_Addon_Tablet.GS_WifiAntenna_T3" then
		range = GSSiK_Addon_Tablet.Sandbox.getTier3Range()
	elseif itemType == "GSSiK_Addon_Tablet.GS_WifiAntenna_T2" then
		range = GSSiK_Addon_Tablet.Sandbox.getTier2Range()
	else
		-- T1, o instalada antes de este cambio (sin itemType guardado) -
		-- por defecto se asume la mas basica, nunca se regala rango de mas.
		range = GSSiK_Addon_Tablet.Sandbox.getTier1Range()
	end
	GSSiK_Addon_Tablet.Log.debug("getWirelessRangeForNetwork -> itemType=" .. tostring(itemType) .. " range=" .. tostring(range))
	return range
end

GlobalStorageSiK.TerminalAccess.registerWirelessProvider({
	hasAccess = GSSiK_Addon_Tablet.hasAccessTablet,
	hasCraft = GSSiK_Addon_Tablet.hasCraftTablet,
	hasBuilder = GSSiK_Addon_Tablet.hasBuilderTablet,
	getRange = GSSiK_Addon_Tablet.getWirelessRangeForPlayer,
	getRangeForNetwork = GSSiK_Addon_Tablet.getWirelessRangeForNetwork,
})
