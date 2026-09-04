--[[
	GlobalStorageSiK - Instalación de addons en terminales
	Autor: SiK
	Fecha: 2025-06-27
	Descripción: Módulos craftables instalados por terminal (ModData).
]]

require "GS_Network"
require "GSSiK_API"
require "GS_Permissions"
require "GS_I18n"
require "GS_Log"
require "GS_InventorySync"
require "GS_CraftUtils"
require "GS_Sandbox"
-- Registra el addon "Reader" (ver GS_ReaderAddon.lua) - require aqui, no
-- desde GS_AddonRegistry.lua, porque necesita que AddonRegistry.register ya
-- exista (este fichero carga siempre despues, nunca antes).
require "GS_ReaderAddon"

GlobalStorageSiK.Addons = {}

local AddonAPI = GSSiK.API.Addon

local function addonDefinition(addonId)
	local ok, _, definition = AddonAPI.get(addonId)
	if ok then return definition end
	return nil
end

local function addonIsActive(addonId)
	local ok, _, active = AddonAPI.isActive(addonId)
	return ok == true and active == true
end

local function playerKnowsMagazine(player, addonId)
	local ok, _, known = AddonAPI.playerKnowsMagazine(player, addonId)
	return ok == true and known == true
end

---@param anchor table|nil
---@return string|nil
function GlobalStorageSiK.Addons.anchorKey(anchor)
	if not anchor or anchor.x == nil or anchor.y == nil then
		return nil
	end
	return string.format("%d_%d_%d", math.floor(anchor.x), math.floor(anchor.y), math.floor(anchor.z or 0))
end

--- fullType del disquete de desinstalación (ver GS_DiskProgramming.lua,
--- programa "uninstall") - referencia suave (sin require, para no crear un
--- ciclo: GS_DiskProgramming no necesita conocer GS_Addons) igual que el
--- resto de referencias cruzadas de este fichero.
---@return string|nil
function GlobalStorageSiK.Addons.uninstallDiskItem()
	local prog = GlobalStorageSiK.DiskProgramming and GlobalStorageSiK.DiskProgramming.PROGRAMS
	return prog and prog.uninstall and prog.uninstall.outputItem or nil
end

--- Indica si el jugador tiene el Lector universal a mano para operar
--- disquetes en este terminal - instalado como addon en la red, o llevado
--- en el inventario principal. Mismo criterio (y mismo motivo: "como el
--- resto de ejecuciones de programas") que ya usa
--- GS_AddonRegistry.hasRequiredInstallItems para instalar cualquier
--- periferico, reutilizado aqui para exigirlo tambien al desinstalar con el
--- disquete de desinstalacion.
---@param player IsoPlayer|nil
---@param networkId string|nil
---@param anchor table|nil
---@return boolean
function GlobalStorageSiK.Addons.hasReaderAvailable(player, networkId, anchor)
	if not player or not player.getInventory then
		return false
	end
	local inv = player:getInventory()
	local readerType = GlobalStorageSiK.Config and GlobalStorageSiK.Config.ITEM_TERMINAL_READER
	local readerInInventory = readerType and (inv:getItemCount(readerType) or 0) >= 1
	local readerInNetwork = networkId ~= nil and GlobalStorageSiK.Addons.isInstalled(networkId, anchor, "Reader") == true
	return readerInInventory == true or readerInNetwork
end

--- BUG REAL confirmado (dedicado, log 2026-08-12): en cliente MP puro, el
--- ModData "GlobalStorageSiK_Network" (registry.networks[*].addonInstalls)
--- puede no llegar a sincronizarse nunca via ModData.transmit, dejando
--- isInstalled/serializeForTerminal SIEMPRE en false/vacio en ese cliente
--- aunque el addon (p.ej. antena WiFi T3) SI este instalado de verdad en el
--- servidor - reportado como "antena no instalada" pese a llevar la T3
--- puesta. El canal de comandos (terminalState) SI llega fiable (se ve en
--- los mismos logs), asi que en cliente no autoritativo usamos como
--- respaldo el ultimo installedAddons recibido por ese canal
--- (GlobalStorageSiK.Client.cachedTerminalState, ver GS_Client.lua) cuando
--- el registry local no tiene nada para esta red.
---
--- BUG REAL cerrado (2026-08-27, reporte real de jugador: "el addon solo se
--- puede instalar por disquete, no desde el menu; y al reabrir el menu la
--- opcion desaparece" - diagnostico conjunto con el equipo de sistemas):
--- este respaldo solo comparaba `networkId`, nunca el terminal concreto -
--- una red con MAS DE UN terminal podia devolver aqui el ultimo
--- installedAddons cacheado de OTRO terminal de la misma red (distinto
--- anchor), mostrando addons instalados/faltantes que no correspondian al
--- terminal que el jugador tenia realmente abierto. Ahora se exige tambien
--- que el anchor coincida - si no coincide, se trata como "sin respaldo
--- valido para ESTE terminal" en vez de devolver el de otro.
---@param networkId string
---@param anchor table|nil terminal concreto para el que se pide el respaldo
---@return table|nil
local function cachedInstalledAddons(networkId, anchor)
	if GlobalStorageSiK.isAuthoritative() then
		return nil
	end
	local cached = GlobalStorageSiK.Client and GlobalStorageSiK.Client.cachedTerminalState
	if not cached or cached.networkId ~= networkId or not cached.installedAddons then
		return nil
	end
	local wantedKey = GlobalStorageSiK.Addons.anchorKey(anchor)
	local cachedKey = GlobalStorageSiK.Addons.anchorKey(cached.terminalAnchor)
	if wantedKey and cachedKey and wantedKey ~= cachedKey then
		return nil
	end
	return cached.installedAddons
end

---@param networkId string
---@param anchor table|nil
---@param addonId string
---@return boolean
function GlobalStorageSiK.Addons.isInstalled(networkId, anchor, addonId)
	local key = GlobalStorageSiK.Addons.anchorKey(anchor)
	if not key or not addonId then
		return false
	end
	local registry = GlobalStorageSiK.Network.getRegistry()
	GlobalStorageSiK.Network.ensureRegistry(registry)
	local net = registry.networks[networkId]
	if net and net.addonInstalls and net.addonInstalls[key] and net.addonInstalls[key][addonId] ~= nil then
		return true
	end
	local fallback = cachedInstalledAddons(networkId, anchor)
	if fallback then
		return fallback[addonId] ~= nil
	end
	return false
end

--- Nivel de Electrónica del jugador frente al mínimo exigido por sandbox
--- para instalar/desinstalar CUALQUIER addon del terminal - pedido explícito
--- del usuario junto a la acción cronometrada de instalar/desinstalar:
--- "poco pero algo de conocimiento". Mismo requisito para los 4 periféricos
--- actuales (disquetera, impresora 3D, antena WiFi, pizarra digital); no
--- depende del addon concreto, a diferencia del manual/magazine (que sí es
--- por addon) - instalar hardware en el terminal exige el mismo conocimiento
--- eléctrico base sea cual sea el módulo.
---@param player IsoPlayer|nil
---@return boolean
function GlobalStorageSiK.Addons.hasRequiredSkill(player)
	local required = GlobalStorageSiK.Sandbox.getAddonInstallSkillRequired()
	if required <= 0 then
		return true
	end
	return GlobalStorageSiK.CraftUtils.getElectricityLevel(player) >= required
end

--- Genérico: mod addon activo + periférico instalado en el terminal ancla.
--- Punto único que cualquier addon (Craft, Builder, o futuros) puede llamar
--- directamente para saber si su propia mecánica de red está disponible en
--- ese terminal, sin que el Core necesite conocer al addon de antemano.
---@param addonId string
---@param networkId string|nil
---@param anchor table|nil
---@return boolean
function GlobalStorageSiK.Addons.canUseAddon(addonId, networkId, anchor)
	if not addonId or not addonIsActive(addonId) then
		return false
	end
	local nid = networkId or GlobalStorageSiK.Network.getDefaultNetworkId()
	return GlobalStorageSiK.Addons.isInstalled(nid, anchor, addonId)
end

--- Tableta inalámbrica: mod activo + módulo instalado en el terminal ancla.
---@param networkId string|nil
---@param anchor table|nil
---@return boolean
function GlobalStorageSiK.Addons.canUseTabletWireless(networkId, anchor)
	return GlobalStorageSiK.Addons.canUseAddon("TabletLink", networkId, anchor)
end

--- Craft remoto: mod activo + módulo instalado en el terminal de sesión.
---@param networkId string|nil
---@param anchor table|nil
---@return boolean
function GlobalStorageSiK.Addons.canUseCraftAddon(networkId, anchor)
	return GlobalStorageSiK.Addons.canUseAddon("Craft", networkId, anchor)
end

--- Muestra pestaña Craft: módulo remoto instalado y tableta de crafteo (o
--- Maestra, que también la cubre) si el acceso es inalámbrico.
---@param networkId string|nil
---@param anchor table|nil
---@param accessMode string|nil
---@param player IsoPlayer|nil
---@return boolean
function GlobalStorageSiK.Addons.canShowTerminalCraftTab(networkId, anchor, accessMode, player)
	if not GlobalStorageSiK.Addons.canUseCraftAddon(networkId, anchor) then
		return false
	end
	if accessMode == "wireless_craft" or accessMode == "wireless_master" then
		return player ~= nil and GlobalStorageSiK.TerminalAccess.hasCraftTablet(player)
	end
	if accessMode == "wireless_access" or accessMode == "wireless_builder" then
		return false
	end
	return true
end

--- Muestra pestaña Build: módulo remoto instalado y tableta de construcción
--- (o Maestra) si el acceso es inalámbrico. Mismo criterio que Craft.
---@param networkId string|nil
---@param anchor table|nil
---@param accessMode string|nil
---@param player IsoPlayer|nil
---@return boolean
function GlobalStorageSiK.Addons.canShowTerminalBuildTab(networkId, anchor, accessMode, player)
	if not GlobalStorageSiK.Addons.canUseAddon("Builder", networkId, anchor) then
		return false
	end
	if accessMode == "wireless_builder" or accessMode == "wireless_master" then
		return player ~= nil and GlobalStorageSiK.TerminalAccess.hasBuilderTablet(player)
	end
	if accessMode == "wireless_access" or accessMode == "wireless_craft" then
		return false
	end
	return true
end

--- Serializa addons instalados en un terminal concreto.
---@param networkId string
---@param anchor table|nil
---@return table
function GlobalStorageSiK.Addons.serializeForTerminal(networkId, anchor)
	local key = GlobalStorageSiK.Addons.anchorKey(anchor)
	local out = {}
	local hasAny = false
	if key then
		local registry = GlobalStorageSiK.Network.getRegistry()
		local net = registry.networks and registry.networks[networkId]
		if net and net.addonInstalls and net.addonInstalls[key] then
			for addonId, meta in pairs(net.addonInstalls[key]) do
				out[addonId] = meta
				hasAny = true
			end
		end
	end
	-- BUG REAL (dedicado, log 2026-08-12): "next" NO existe en el entorno
	-- Kahlua de PZ (no expuesto a mods) - usarlo aqui tumbaba openTerminal
	-- entero con "Object tried to call nil in serializeForTerminal" en TODA
	-- apertura, no solo cuando hacia falta el respaldo. Nunca usar next() en
	-- este codebase; comprobar "vacio" con un flag propio como hasAny.
	if not hasAny then
		local fallback = cachedInstalledAddons(networkId, anchor)
		if fallback then
			return fallback
		end
	end
	return out
end

--- Crea ítem de módulo en inventario del jugador.
--- BUG REAL cerrado (2026-08-23, reportado explicitamente: "el periferico
--- nunca vuelve al inventario al desinstalar" - confirmado tras 3 pruebas
--- aisladas del usuario, con datos de servidor mostrando "itemGiven=true" a
--- pesar de que el jugador nunca lo recibia): esto llamaba a `inv:AddItem`
--- directamente, sin pasar por el patron de sincronizacion MP ya establecido
--- en `GS_InventorySync.lua` (usado en el resto del mod) - en servidor,
--- `AddItem` en crudo muta el objeto Lua autoritativo pero nunca transmite
--- el alta al cliente, asi que el item se creaba "de verdad" (de ahi que el
--- log dijera exito) pero jamas llegaba a la pantalla del jugador. Ahora usa
--- `GlobalStorageSiK.InventorySync.addToPlayer`, el mismo helper publico que
--- ya gestiona `sendAddItemToContainer`/lotes en MP.
---@param player IsoPlayer
---@param fullType string
---@return InventoryItem|nil
local function giveModuleItem(player, fullType)
	if not player or not fullType or fullType == "" then
		return nil
	end
	local item = nil
	if instanceItem then
		item = instanceItem(fullType)
	elseif InventoryItemFactory and InventoryItemFactory.CreateItem then
		item = InventoryItemFactory.CreateItem(fullType)
	end
	if item then
		if not GlobalStorageSiK.InventorySync.addToPlayer(player, item) then
			return nil
		end
	end
	return item
end

--- Instala addon consumiendo el módulo del inventario.
---@param player IsoPlayer
---@param networkId string
---@param anchor table
---@param addonId string
---@return boolean ok
---@return string message
function GlobalStorageSiK.Addons.install(player, networkId, anchor, addonId)
	local def = addonDefinition(addonId)
	if not def then
		return false, GlobalStorageSiK.I18n.remote("IGUI_GS_AddonUnknownMsg")
	end
	if not addonIsActive(addonId) then
		return false, GlobalStorageSiK.I18n.remote("IGUI_GS_AddonModInactiveMsg")
	end
	if not playerKnowsMagazine(player, addonId) then
		-- Antes texto fijo en español, se le mostraba literal a cualquier
		-- jugador sea cual sea su idioma (reportado: un jugador ingles vio
		-- este mensaje en español). GS_I18n.text() ya se usa asi en servidor
		-- para otros mensajes (ver GS_Server.lua, IGUI_GS_PCAcquireFailBook).
		return false, GlobalStorageSiK.I18n.remote("IGUI_GS_AddonStatusNeedMagazine")
	end
	if not GlobalStorageSiK.Addons.hasRequiredSkill(player) then
		return false, GlobalStorageSiK.I18n.remote("IGUI_GS_AddonStatusNeedSkill")
	end
	-- BUG REAL cerrado (2026-08-22, reportado en Steam Workshop y confirmado
	-- en auditoria: "un admin debe poder instalar addons, configurar
	-- contenedores, etc." - politica explicita del usuario): esto exigia
	-- SOLO propietario, contradiciendo el gate de GS_Server.lua
	-- (requireAdminAccess, propietario O admin) - un admin de red nunca
	-- podia instalar un addon aunque el servidor le fuera a dejar. Se ajusta
	-- al mismo nivel que el resto de herramientas de gestion (zonas,
	-- contenedores): admin O propietario.
	if not GlobalStorageSiK.Permissions.isAdminPlayer(player, networkId) then
		return false, GlobalStorageSiK.I18n.remote("IGUI_GS_OnlyOwnerInstallAddonsMsg")
	end
	local key = GlobalStorageSiK.Addons.anchorKey(anchor)
	if not key then
		return false, GlobalStorageSiK.I18n.remote("IGUI_GS_InvalidTerminalMsg")
	end
	if GlobalStorageSiK.Addons.isInstalled(networkId, anchor, addonId) then
		return false, GlobalStorageSiK.I18n.remote("IGUI_GS_AddonAlreadyInstalledMsg")
	end
	-- Igual que instalar el terminal en un PC: hace falta el lector
	-- universal en el inventario principal (autoridad de servidor, no basta
	-- con lo que ya valida el cliente), y el disquete propio del addon si
	-- lo define (se conserva, no se consume aqui abajo).
	local policyOk, _, hasItems, itemsReason = AddonAPI.canInstall(player, addonId, networkId, anchor)
	if not policyOk or not hasItems then
		if itemsReason == "reader" then
			return false, GlobalStorageSiK.I18n.remote("IGUI_GS_NeedReaderMainInventoryMsg")
		end
		if itemsReason == "module" then
			return false, GlobalStorageSiK.I18n.remote("IGUI_GS_MissingModuleMsg")
		end
		return false, GlobalStorageSiK.I18n.remote("IGUI_GS_MissingInstallDiskMsg")
	end
	local inv = player:getInventory()
	if not inv or not def.itemType then
		return false, GlobalStorageSiK.I18n.remote("IGUI_GS_InvalidInventoryMsg")
	end
	-- Cualquiera de los tiers del modulo sirve para instalar (ver
	-- GS_AddonRegistry.moduleItemTypes) - se recuerda EXACTAMENTE cual se
	-- instalo para poder devolver el mismo tier al retirar, y para que
	-- quien consulte el rango de la red sepa que tier esta activo.
	local moduleItem, moduleItemType = nil, nil
	local typesOk, _, candidateTypes = AddonAPI.moduleItemTypes(addonId)
	if not typesOk then candidateTypes = {} end
	for i = 1, #candidateTypes do
		if candidateTypes[i] then
			local found = inv:getFirstTypeRecurse(candidateTypes[i])
			if found then
				moduleItem = found
				moduleItemType = candidateTypes[i]
				break
			end
		end
	end
	if not moduleItem then
		GlobalStorageSiK.Log.debug("Addons", "installFailed",
			"addonId=" .. tostring(addonId) .. " reason=no_module_found candidateTypes=" .. tostring(#candidateTypes))
		return false, GlobalStorageSiK.I18n.remote("IGUI_GS_MissingModuleMsg")
	end
	-- Traza dirigida (2026-08-23, pedido explicito del usuario tras reporte
	-- de que la impresora/pizarra no se consumia al instalar y no volvia al
	-- retirar): confirma con datos reales el fullType exacto que se
	-- encontro/elimino, no una suposicion.
	GlobalStorageSiK.Log.debug("Addons", "installConsuming",
		"addonId=" .. tostring(addonId) .. " moduleItemType=" .. tostring(moduleItemType)
			.. " itemId=" .. tostring(moduleItem.getID and moduleItem:getID() or "?"))
	-- Mismo bug real y mismo arreglo que giveModuleItem() - inv:Remove()
	-- en crudo nunca transmitia la baja al cliente en MP.
	GlobalStorageSiK.InventorySync.removeItem(inv, moduleItem)
	local registry = GlobalStorageSiK.Network.getRegistry()
	GlobalStorageSiK.Network.ensureRegistry(registry)
	local net = registry.networks[networkId]
	net.addonInstalls = net.addonInstalls or {}
	net.addonInstalls[key] = net.addonInstalls[key] or {}
	net.addonInstalls[key][addonId] = {
		by = GlobalStorageSiK.Permissions.getCharacterName(player),
		at = (getTimestamp and getTimestamp()) or 0,
		itemType = moduleItemType,
	}
	if ModData and ModData.transmit then
		ModData.transmit(GlobalStorageSiK.MODDATA_KEY)
	end
	GlobalStorageSiK.Log.debug("Addons", "installOk",
		"addonId=" .. tostring(addonId) .. " key=" .. tostring(key) .. " recordedItemType=" .. tostring(moduleItemType))
	return true, GlobalStorageSiK.I18n.remote("IGUI_GS_AddonInstalledMsg")
end

--- Retira addon y devuelve el módulo al inventario.
---@param player IsoPlayer
---@param networkId string
---@param anchor table
---@param addonId string
---@return boolean ok
---@return string message
function GlobalStorageSiK.Addons.uninstall(player, networkId, anchor, addonId)
	local def = addonDefinition(addonId)
	if not def then
		return false, GlobalStorageSiK.I18n.remote("IGUI_GS_AddonUnknownMsg")
	end
	-- Mismo criterio y mismo bug real que install() arriba - admin O
	-- propietario, no solo propietario.
	if not GlobalStorageSiK.Permissions.isAdminPlayer(player, networkId) then
		return false, GlobalStorageSiK.I18n.remote("IGUI_GS_OnlyOwnerRemoveAddonsMsg")
	end
	if not GlobalStorageSiK.Addons.hasRequiredSkill(player) then
		return false, GlobalStorageSiK.I18n.remote("IGUI_GS_AddonStatusNeedSkill")
	end
	local key = GlobalStorageSiK.Addons.anchorKey(anchor)
	if not key then
		return false, GlobalStorageSiK.I18n.remote("IGUI_GS_InvalidTerminalMsg")
	end
	if not GlobalStorageSiK.Addons.isInstalled(networkId, anchor, addonId) then
		return false, GlobalStorageSiK.I18n.remote("IGUI_GS_AddonNotInstalledHereMsg")
	end
	-- Operar el disquete de desinstalacion exige el Lector a mano, igual que
	-- cualquier otra ejecucion/grabacion de programa (ver
	-- GS_DiskProgramming.lua) - instalado en esta red o llevado encima.
	if not GlobalStorageSiK.Addons.hasReaderAvailable(player, networkId, anchor) then
		return false, GlobalStorageSiK.I18n.remote("IGUI_GS_NeedReaderNetworkOrInventoryMsg")
	end
	-- Disquete de desinstalacion: se exige en el inventario pero NO se
	-- consume (igual que installDiskItem al instalar - ver
	-- GS_AddonRegistry.hasRequiredInstallItems, "se conserva, no se
	-- consume"). Autoridad de servidor: revalida aqui, no basta con lo que
	-- ya comprobo el cliente en GS_AddonManageUI.lua.
	local uninstallDiskItem = GlobalStorageSiK.Addons.uninstallDiskItem()
	if uninstallDiskItem then
		local inv = player:getInventory()
		if not inv or (inv:getItemCountRecurse(uninstallDiskItem) or 0) < 1 then
			return false, GlobalStorageSiK.I18n.remote("IGUI_GS_NeedUninstallDiskMsg")
		end
	end
	local registry = GlobalStorageSiK.Network.getRegistry()
	local net = registry.networks[networkId]
	local installedType = def.itemType
	local hadRecord = false
	if net and net.addonInstalls and net.addonInstalls[key] and net.addonInstalls[key][addonId] then
		installedType = net.addonInstalls[key][addonId].itemType or def.itemType
		hadRecord = true
	end
	if not hadRecord then
		return false, GlobalStorageSiK.I18n.remote("IGUI_GS_AddonNotInstalledHereMsg")
	end
	local given = giveModuleItem(player, installedType)
	GlobalStorageSiK.Log.debug("Addons", "uninstallReturn",
		"addonId=" .. tostring(addonId) .. " key=" .. tostring(key) .. " hadRecord=" .. tostring(hadRecord)
			.. " installedType=" .. tostring(installedType) .. " itemGiven=" .. tostring(given ~= nil))
	if not given then
		GlobalStorageSiK.Log.error("Addons", "uninstallReturnFailed",
			"addonId=" .. tostring(addonId) .. " installedType=" .. tostring(installedType)
				.. " - registro conservado porque giveModuleItem() no confirmo la devolucion")
		return false, GlobalStorageSiK.I18n.remote("IGUI_GS_InvalidInventoryMsg")
	end
	-- La desinstalacion es transaccional: el registro solo desaparece despues
	-- de que la unidad exacta haya sido entregada y sincronizada con exito.
	net.addonInstalls[key][addonId] = nil
	if ModData and ModData.transmit then
		ModData.transmit(GlobalStorageSiK.MODDATA_KEY)
	end
	return true, GlobalStorageSiK.I18n.remote("IGUI_GS_AddonRemovedMsg")
end
