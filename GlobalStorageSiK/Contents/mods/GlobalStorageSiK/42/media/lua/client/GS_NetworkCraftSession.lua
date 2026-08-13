--[[
	GlobalStorageSiK - Sesión de crafteo/construcción remoto (Core, genérico)
	Autor: SiK
	Fecha: 2026-08-13 (migración Core -> addons)
	Descripción: Infraestructura GENÉRICA reutilizable por cualquier addon que
	quiera pedir prestados ítems de la red para una acción vanilla temporal
	(crafteo, construcción, o lo que se le ocurra a un addon futuro de
	terceros):
	- Inyección de contenedores de red en ISInventoryPaneContextMenu.getContainers
	  mientras hay sesión activa (patchedGetContainers).
	- Sesión de acceso al terminal (begin/endSession/validateAccess/onTick).
	- Préstamo y devolución de ítems (claimNetworkItem + sweepPendingReturns),
	  con depósito por prioridad al devolver (mismo sistema que ya usa el
	  jugador al depositar a mano).
	- Registro de hooks/tick por addon (registerAddonHooks/registerTickHandler):
	  cada addon (Craft, Builder, o futuros) trae SU PROPIO fichero que conoce
	  SU ventana concreta (ISWidgetHandCraftControl, NC_CraftActionPanel,
	  ISBuildingObject...) y se registra aquí - el Core NUNCA necesita saber
	  que esas clases existen.

	Migrado desde una versión anterior que tenía TODO ese conocimiento
	específico (hooks de ISWidgetHandCraftControl, NC_CraftActionPanel,
	ISBuildingObject, recorte de contenedores de HandcraftLogic, lotes...)
	mezclado directamente aquí - pedido explícito (2026-08-13): separar lo
	que es infraestructura genérica de lo que es "cómo se craftea/construye
	concretamente", para que Craft/Builder aporten conocimiento real y un
	addon de terceros pueda construir sobre la misma base sin que el Core
	absorba toda la lógica. Ver GSSiK_Addon_Craft_NetworkCraft.lua y
	GSSiK_Addon_Builder_NetworkBuild.lua para lo que se movió.
]]

require "GS_NetworkCraftBridge"
require "GS_TerminalAccess"
require "GS_NetClient"
require "GS_Network"
require "GS_Libs"
require "GS_Log"
require "GS_InventorySync"
require "GS_Deposit"
require "GS_Transfer"

GlobalStorageSiK.CraftSession = GlobalStorageSiK.CraftSession or {}

local session = nil
local lastEndReason = nil
local originalGetContainers = nil
local hookInstalled = false
local tickInstalled = false
local tickCounter = 0
local sweepTickInstalled = false
local ensureSweepTick -- forward-declarada: installHook() la llama, se define mas abajo (tras sweepPendingReturns)

--- Mismo intervalo que GS_TerminalAccessGuard.CHECK_TICKS - antes esta
--- sesion revalidaba CADA tick, sin histeresis (ver validateAccess), lo que
--- podia incluso "adelantarse" al chequeo mas tolerante del terminal y
--- marcar session.wasInRange=false (estado COMPARTIDO entre ambos) antes de
--- que el terminal tuviera ocasion de confirmar que seguia en rango.
local CHECK_TICKS = 12

--- Ultimo motivo por el que "Abrir crafteo/construccion" no abrio nada -
--- antes esto se perdia (return false silencioso), dejando al jugador sin
--- ninguna pista. Cualquier panel (Craft, Builder, futuros) puede leerlo
--- justo despues de intentar abrir para mostrar un mensaje claro.
local lastOpenErrorReason = nil

---@return string|nil
function GlobalStorageSiK.CraftSession.getLastOpenError()
	return lastOpenErrorReason
end

--- Envía un mensaje de debug al log PROPIO del addon activo (Craft/Builder,
--- cada uno con su propio DebugMode de sandbox, independiente del de Core -
--- ver GSSiK_Addon_Craft_Log.lua/GSSiK_Addon_Builder_Log.lua) en vez de
--- mezclarlo con el debug general del Core. Un addon se registra una vez
--- con GlobalStorageSiK.CraftSession.registerDebugSink(addonId, fn); si no
--- hay ninguno registrado (o no hay sesión activa todavía) cae al log
--- genérico de Core como red de seguridad. Declarada AQUÍ (antes de
--- patchedGetContainers y compañía) porque varias funciones más abajo la
--- usan como upvalue - Lua solo la ve si ya existe como local en el mismo
--- chunk en el momento en que se crea cada closure.
---@param message string
local function sessionDebugLog(message)
	local addonId = session and session.addonId
	local sink = addonId and GlobalStorageSiK.CraftSession._debugSinks and GlobalStorageSiK.CraftSession._debugSinks[addonId]
	if sink then
		local ok = pcall(sink, message)
		if ok then
			return
		end
	end
	if GlobalStorageSiK.Log then
		GlobalStorageSiK.Log.debug("CraftSession", message)
	end
end

--- Expone sessionDebugLog a los addons (parte de la API publica) - cada
--- addon llama a esto para que sus propias trazas de "reclamo/recorte de
--- contenedores/etc." salgan por su propio sink registrado, sin duplicar la
--- logica de enrutado en cada fichero de addon.
---@param message string
function GlobalStorageSiK.CraftSession.debugLog(message)
	sessionDebugLog(message)
end

--- Permite a un addon (Craft, Builder, o cualquier futuro addon que
--- reutilice esta sesión compartida) registrar su propio logger para que
--- las trazas de este módulo del Core aparezcan en SU debug aislado, en vez
--- de en el genérico. Parte de la superficie Core↔addons pensada para que
--- terceros puedan construir addons nuevos sobre lo mismo sin reinventarlo.
---@param addonId string
---@param fn fun(message:string)
function GlobalStorageSiK.CraftSession.registerDebugSink(addonId, fn)
	GlobalStorageSiK.CraftSession._debugSinks = GlobalStorageSiK.CraftSession._debugSinks or {}
	GlobalStorageSiK.CraftSession._debugSinks[addonId] = fn
end

--- Genera un operationId corto para correlacionar TODO lo que ocurre en un
--- mismo intento de crafteo/construccion (inicio, reclamos, resultado) entre
--- cliente y servidor - pedido explicito (2026-08-13): sin esto, cada log
--- CraftDiag/craftClaimItem del servidor era imposible de emparejar con el
--- intento concreto del cliente que lo causo, sobre todo con varios intentos
--- seguidos en el mismo log. Contador COMPARTIDO entre todos los addons (no
--- por addon) para que dos operationId nunca colisionen aunque Craft y
--- Builder generen uno en el mismo tick.
local operationCounter = 0
---@param addonId string
---@return string
function GlobalStorageSiK.CraftSession.newOperationId(addonId)
	operationCounter = operationCounter + 1
	local ts = getTimestampMs and getTimestampMs() or 0
	return tostring(addonId) .. "-" .. tostring(ts) .. "-" .. tostring(operationCounter)
end

--- Convierte ArrayList o tabla en tabla Lua.
---@param list table|userdata|nil
---@return table
local function arrayListToTable(list)
	local t = {}
	if not list then
		return t
	end
	if list.size and list.get then
		for i = 0, list:size() - 1 do
			table.insert(t, list:get(i))
		end
	elseif type(list) == "table" then
		for i = 1, #list do
			table.insert(t, list[i])
		end
	end
	return t
end

--- Convierte tabla Lua en ArrayList - expuesto (los addons lo necesitan para
--- servir listas de contenedores recortadas a HandcraftLogic/etc. sin tener
--- que reimplementar la conversion).
---@param items table
---@return userdata
function GlobalStorageSiK.CraftSession.tableToArrayList(items)
	local list = ArrayList.new()
	for i = 1, #items do
		list:add(items[i])
	end
	return list
end

--- Hook de contenedores para crafteo con inventario de red - GENERICO,
--- siempre activo mientras hay sesion, sea cual sea el addon.
---@param character IsoPlayer|nil
---@return userdata|nil
local function patchedGetContainers(character)
	local base = originalGetContainers(character)
	if not session or not session.active then
		return base
	end
	if not character or character:getPlayerNum() ~= session.playerNum then
		return base
	end
	if not GlobalStorageSiK.CraftSession.validateAccess(character) then
		GlobalStorageSiK.CraftSession.endSession("access_lost")
		return base
	end
	local baseTable = arrayListToTable(base)
	local merged = GlobalStorageSiK.CraftingBridge.mergeContainerLists(baseTable, session.networkId)
	if GlobalStorageSiK.CraftSession._debugSinks and session.addonId and GlobalStorageSiK.CraftSession._debugSinks[session.addonId] then
		sessionDebugLog("patchedGetContainers base=" .. tostring(#baseTable) .. " conRed=" .. tostring(#merged)
			.. " networkId=" .. tostring(session.networkId))
	end
	return GlobalStorageSiK.CraftSession.tableToArrayList(merged)
end

--- Indica si un contenedor pertenece a la red activa (mismos contenedores
--- que ya inyecta patchedGetContainers vía GS_Network.getLiveContainers,
--- la misma fuente de verdad que ya usan depositar/retirar/auto-ordenar) -
--- expuesto, cualquier addon lo necesita para distinguir "esto es de la
--- red" de "esto es local del jugador".
---@param container ItemContainer|nil
---@param networkId string|nil
---@return boolean
function GlobalStorageSiK.CraftSession.isNetworkContainer(container, networkId)
	if not container then
		return false
	end
	local rows = GlobalStorageSiK.Network.getLiveContainers(networkId)
	for i = 1, #rows do
		if rows[i].container == container then
			return true
		end
	end
	return false
end

--- Indica si el jugador tiene una acción de crafteo/construcción en curso
--- (primer elemento de su cola de acciones temporizadas). Se usa para saber
--- cuándo es seguro devolver un ítem "prestado" (ver claimNetworkItem) a la
--- red sin cortar una acción en marcha.
---@param player IsoPlayer|nil
---@return boolean
local function isCraftOrBuildActionActive(player)
	if not player or not ISTimedActionQueue or not ISTimedActionQueue.getTimedActionQueue then
		return false
	end
	local ok, queue = pcall(ISTimedActionQueue.getTimedActionQueue, player)
	if not ok or not queue or not queue.queue then
		return false
	end
	for i = 1, #queue.queue do
		local action = queue.queue[i]
		if action and instanceof then
			local okType, isMatch = pcall(function()
				return instanceof(action, "ISHandcraftAction") or instanceof(action, "ISBuildAction")
			end)
			if okType and isMatch then
				return true
			end
		end
	end
	return false
end

--- Ítems "prestados" de un contenedor de red al inventario del jugador para
--- poder craftear/construir sin desplazarse - itemId -> { networkId,
--- playerNum, fullType }. Se devuelven solos en sweepPendingReturns en
--- cuanto termina la acción, o se olvidan si la receta ya los consumió.
local pendingReturns = {}

--- itemId -> true para ítems cuyo reclamo YA se envió al servidor en esta
--- sesión - BUG REAL encontrado (reportado 2026-08-13, "Dupe item ID"/
--- "container already has id" en servidor, itemsCreados=0 pese a que el
--- primer reclamo ya habia sido confirmado): un addon que vuelve a comprobar
--- sus propios ingredientes (p.ej. al reanudar tras la espera) puede volver
--- a intentar reclamar el MISMO item - el servidor intentaba añadir un item
--- con un ID que ya tenia, lo corrompia, y el consumo de la receta no
--- encontraba nada valido. Se limpia en endSession, no dentro de
--- sweepPendingReturns - un reclamo duplicado puede llegar ANTES de que
--- sweepPendingReturns tenga ocasion de procesar el primero.
local claimedItemIds = {}

--- Indica si un itemId ya se reclamo en esta sesion - expuesto para que un
--- addon (ej. Craft, escaneando contenedores para completar un lote) pueda
--- evitar reclamar dos veces el mismo item sin reimplementar esta tabla.
---@param itemId number|nil
---@return boolean
function GlobalStorageSiK.CraftSession.isItemClaimed(itemId)
	return itemId ~= nil and claimedItemIds[itemId] == true
end

--- Mueve un ítem de un contenedor de red al inventario del jugador - API
--- PÚBLICA (antes local, uso exclusivo de este fichero): cualquier addon
--- que necesite pedir prestado un ítem de la red para una acción vanilla
--- llama a esto, sin reimplementar la lógica de autoridad SP/MP.
--- CRITICO (corregido tras confirmar "consume failed" en Craft Y Build):
--- GS_InventorySync.moveBetween NO es autoritativo si se llama directamente
--- desde código de CLIENTE - en servidor dedicado isServer() da false ahí,
--- así que el movimiento solo afectaba a la vista LOCAL del cliente, nunca
--- al estado real del servidor. La comprobación de consumo real
--- (HandcraftLogic/ISBuildIsoEntity.ConsumeBuildEntityItems) corre siempre
--- en servidor y nunca encontraba el ítem - de ahí la barra de progreso
--- completa sin producir nada, tanto en Craft como en Build. Ahora: si este
--- proceso YA es autoritativo (SP real, host LAN, o el propio servidor
--- dedicado - GlobalStorageSiK.isAuthoritative()), el movimiento local de
--- siempre es correcto y no hace falta nada más. Si NO (cliente MP puro
--- hablando con un servidor remoto), se pide al servidor vía el comando
--- "craftClaimItem" (ver GS_Server.lua) que haga el movimiento real - sin
--- intentar predecirlo localmente: la duración de cualquier acción de
--- crafteo/construcción (varios segundos) da tiempo de sobra al viaje de
--- ida y vuelta (~300-400ms observados en los logs) antes de que el
--- servidor compruebe el consumo.
---@param playerObj IsoPlayer
---@param item InventoryItem
---@param sourceContainer ItemContainer
---@param networkId string|nil
---@param operationId string|nil
---@return boolean ok
function GlobalStorageSiK.CraftSession.claimNetworkItem(playerObj, item, sourceContainer, networkId, operationId)
	local fullType = item.getFullType and item:getFullType() or "?"
	if not GlobalStorageSiK.isAuthoritative() then
		local itemId = item.getID and item:getID()
		if itemId and claimedItemIds[itemId] then
			-- Ya reclamado en esta sesion (ver comentario de claimedItemIds) -
			-- no reenviar, el item ya deberia estar en el inventario del
			-- jugador o en camino; reenviar corrompe el item en servidor.
			sessionDebugLog("claimNetworkItem -> itemId=" .. tostring(itemId)
				.. " YA reclamado antes, se ignora para evitar duplicado")
			return true
		end
		if itemId and GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.sendCommand then
			claimedItemIds[itemId] = true
			GlobalStorageSiK.NetClient.sendCommand("craftClaimItem", {
				itemId = itemId, networkId = networkId, operationId = operationId,
			})
			sessionDebugLog(string.format(
				"claimSend operationId=%s itemId=%s fullType=%s requiredQuantity=1",
				tostring(operationId), tostring(itemId), tostring(fullType)))
			pendingReturns[itemId] = {
				networkId = networkId,
				playerNum = playerObj:getPlayerNum(),
				fullType = fullType,
			}
			return true
		end
		return false
	end
	local destInv = playerObj:getInventory()
	local ok = GlobalStorageSiK.InventorySync.moveBetween(sourceContainer, destInv, item, playerObj)
	if ok then
		local itemId = item.getID and item:getID()
		if itemId then
			pendingReturns[itemId] = {
				networkId = networkId,
				playerNum = playerObj:getPlayerNum(),
				fullType = fullType,
			}
		end
		sessionDebugLog("claimNetworkItem OK (local, autoritativo) fullType=" .. fullType)
	else
		sessionDebugLog("claimNetworkItem FALLO (sin espacio/peso real) fullType=" .. fullType)
	end
	return ok
end

--- Barrido de préstamos pendientes (cada tick, tabla normalmente vacía o
--- muy pequeña): si el ítem ya no se puede localizar en el inventario del
--- jugador, se consumió en la receta - se olvida sin más. Si sigue ahí Y ya
--- no hay ninguna acción de crafteo/construcción activa para él, se
--- deposita en la red usando el MISMO sistema de depósito por prioridad que
--- ya usa el jugador al mandar cosas al almacén a mano (categoría, afinidad
--- "mismo ítem", prioridad de zona) - NO se devuelve al contenedor exacto de
--- origen (pedido explícito 2026-08-13: no tiene sentido rastrear
--- "originalContainer" cuando ya existe un sistema de depósito inteligente
--- que decide mejor destino que "donde estaba antes").
--- CORREGIDO (reportado 2026-08-13, "el martillo no vuelve al almacén"):
--- antes se indexaba por el objeto InventoryItem/userdata TAL CUAL se tenía
--- en el momento del reclamo - tras el viaje ida y vuelta cliente->servidor
--- ->cliente (craftClaimItem asíncrono), el cliente puede recibir una
--- instancia distinta para el MISMO id via sincronización de inventario,
--- dejando la referencia vieja obsoleta. Ahora se indexa y localiza por
--- itemId (GlobalStorageSiK.Deposit.findItemById, ya usado y probado para
--- depositar por ID), inmune a que la referencia de objeto cambie.
local function sweepPendingReturns()
	for itemId, info in pairs(pendingReturns) do
		local player = getSpecificPlayer and getSpecificPlayer(info.playerNum) or nil
		if not player then
			pendingReturns[itemId] = nil
		else
			local item, currentContainer = GlobalStorageSiK.Deposit.findItemById(player, itemId)
			if not item or not currentContainer then
				-- No localizable en ningun contenedor accesible del jugador:
				-- se consumio en la receta, nada que devolver.
				sessionDebugLog("sweepPendingReturns itemId=" .. tostring(itemId)
					.. " no localizable (consumido) fullType=" .. tostring(info.fullType))
				pendingReturns[itemId] = nil
			elseif not isCraftOrBuildActionActive(player) then
				if currentContainer == player:getInventory() then
					if GlobalStorageSiK.isAuthoritative() then
						local ok, reason = GlobalStorageSiK.Transfer.depositItem(player, item, info.networkId)
						sessionDebugLog("sweepPendingReturns devuelto=" .. tostring(ok)
							.. " (local, autoritativo, deposito por prioridad) itemId=" .. tostring(itemId)
							.. " fullType=" .. tostring(info.fullType) .. " reason=" .. tostring(reason))
					elseif GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.sendCommand then
						-- En cliente MP puro, "depositItems" ya ejecuta en
						-- servidor el mismo Transfer.depositItem por prioridad.
						GlobalStorageSiK.NetClient.sendCommand("depositItems", { itemIds = { itemId } })
						sessionDebugLog("sweepPendingReturns -> depositItems enviado al servidor itemId=" .. tostring(itemId)
							.. " fullType=" .. tostring(info.fullType))
					end
				end
				pendingReturns[itemId] = nil
			elseif not info.loggedWaitingActive then
				-- DIAGNOSTICO (2026-08-13): antes esto era silencioso - no había
				-- forma de distinguir "el item volverá en cuanto pares de
				-- craftear" de "esto está roto". Se loguea UNA vez por item (no
				-- cada tick, para no inundar el log) en cuanto se detecta el
				-- primer aplazamiento por cola de crafteo/construcción activa.
				info.loggedWaitingActive = true
				sessionDebugLog("sweepPendingReturns itemId=" .. tostring(itemId)
					.. " fullType=" .. tostring(info.fullType)
					.. " aplazado (accion craft/build activa en cola, se reintentara en cuanto la cola quede vacia)")
			end
		end
	end
end

--- Hooks/tick registrados por cada addon - ver cabecera del fichero. El
--- Core solo llama a estas funciones en el momento adecuado (arranque/fin de
--- sesion, cada tick); nunca conoce que clase concreta patchea cada una.
local addonHooks = {}
local addonTickHandlers = {}

--- Permite a un addon registrar sus propios hooks de clases vanilla/mod
--- externo (install/uninstall), instalados/desinstalados junto con el hook
--- genérico de contenedores cuando una sesión arranca/termina.
---@param addonId string
---@param installFn fun()
---@param uninstallFn fun()
function GlobalStorageSiK.CraftSession.registerAddonHooks(addonId, installFn, uninstallFn)
	addonHooks[addonId] = { install = installFn, uninstall = uninstallFn }
end

--- Permite a un addon registrar una función a llamar CADA tick mientras el
--- hook está instalado (p.ej. para resolver reclamos pendientes antes de
--- dejar avanzar una acción vanilla - ver checkPendingCraftStarts en Craft).
---@param addonId string
---@param fn fun()
function GlobalStorageSiK.CraftSession.registerTickHandler(addonId, fn)
	addonTickHandlers[addonId] = fn
end

--- Instala el hook GENÉRICO de contenedores (getContainers) más los hooks
--- que cada addon haya registrado con registerAddonHooks.
function GlobalStorageSiK.CraftSession.installHook()
	if hookInstalled then
		return
	end
	if not ISInventoryPaneContextMenu or not ISInventoryPaneContextMenu.getContainers then
		return
	end
	originalGetContainers = ISInventoryPaneContextMenu.getContainers
	ISInventoryPaneContextMenu.getContainers = patchedGetContainers
	for addonId, hooks in pairs(addonHooks) do
		if hooks.install then
			local ok, err = pcall(hooks.install)
			if not ok then
				GlobalStorageSiK.Log.error("CraftSession", "installHook addon=" .. tostring(addonId) .. " fallo: " .. tostring(err))
			end
		end
	end
	hookInstalled = true
	if ensureSweepTick then
		ensureSweepTick()
	end
end

--- Restaura getContainers y los hooks de cada addon registrado.
function GlobalStorageSiK.CraftSession.uninstallHook()
	if not hookInstalled or not originalGetContainers then
		return
	end
	ISInventoryPaneContextMenu.getContainers = originalGetContainers
	for addonId, hooks in pairs(addonHooks) do
		if hooks.uninstall then
			local ok, err = pcall(hooks.uninstall)
			if not ok then
				GlobalStorageSiK.Log.error("CraftSession", "uninstallHook addon=" .. tostring(addonId) .. " fallo: " .. tostring(err))
			end
		end
	end
	hookInstalled = false
end

--- Comprueba si el jugador sigue teniendo acceso al terminal.
---@param player IsoPlayer|nil
---@return boolean
function GlobalStorageSiK.CraftSession.validateAccess(player)
	if not session or not player then
		return false
	end
	if not GlobalStorageSiK.TerminalAccess or not GlobalStorageSiK.TerminalAccess.evaluate then
		return false
	end
	-- Antes se llamaba sin opts: sin sessionLock no hay margen de histeresis
	-- (ver evaluateAnchorDistance en GS_TerminalAccess.lua), asi que el
	-- jugador perdia el acceso al primer paso fuera del limite exacto -
	-- el terminal mismo (GS_TerminalAccessGuard) SIEMPRE pasa sessionLock=true
	-- y usa getSessionAnchor() como ancla preferente por la misma razon.
	local anchor = GlobalStorageSiK.TerminalAccess.getSessionAnchor and GlobalStorageSiK.TerminalAccess.getSessionAnchor(player)
	if not anchor then
		anchor = session.terminalAnchor
	end
	local ok = GlobalStorageSiK.TerminalAccess.evaluate(player, session.networkId, anchor, { sessionLock = true })
	return ok == true
end

--- Devuelve un snapshot de la sesión activa, o nil - API PÚBLICA para que
--- los addons no necesiten conocer la forma interna de "session" (antes
--- accedían a un upvalue local compartido dentro de este mismo fichero,
--- imposible una vez el código de cada addon vive en su propio fichero).
---@param addonId string|nil si se pasa, solo devuelve algo si la sesión es de ESE addon
---@return table|nil { active, networkId, addonId, playerNum, terminalAnchor, accessMode, uiMode }
function GlobalStorageSiK.CraftSession.getActiveSession(addonId)
	if not session or not session.active then
		return nil
	end
	if addonId and session.addonId ~= addonId then
		return nil
	end
	return {
		active = session.active,
		networkId = session.networkId,
		addonId = session.addonId,
		playerNum = session.playerNum,
		terminalAnchor = session.terminalAnchor,
		accessMode = session.accessMode,
		uiMode = session.uiMode,
	}
end

--- Inicia sesión de crafteo/construcción remoto.
---@param opts table|nil { player, networkId, terminalAnchor, accessMode, uiMode, addonId, knownInstalled }
--- addonId (obligatorio): id registrado en GS_AddonRegistry cuyo acceso se
--- valida vía GlobalStorageSiK.Addons.canUseAddon. Cada addon pasa el suyo
--- (p.ej. "Craft" o "Builder"); sesiones de addons distintos no se pisan
--- porque solo puede haber una activa a la vez (se cierra la anterior al
--- cerrar su ventana, igual que siempre).
--- knownInstalled (opcional, boolean): si el llamante YA sabe con certeza
--- (por el ultimo terminalState confirmado por el servidor, p.ej.
--- state.installedAddons) que el modulo esta instalado en este terminal,
--- se salta la comprobacion de GlobalStorageSiK.Addons.canUseAddon - esa
--- funcion lee el registro de red MIRROR local (sincronizado por ModData,
--- con su propio retraso), que puede ir por detras del terminalState que
--- el jugador ya ha visto confirmado en su propia pantalla (reportado: en
--- modpacks grandes, instalar el modulo y abrir crafteo justo despues
--- podia decir "no instalado" un instante despues de verlo instalado en la
--- pestaña Addons). El mod addon activo SI se sigue comprobando siempre
--- (barato, no depende de ModData).
---@return boolean ok
---@return string|nil reason "no_player"|"addon_unavailable" si falla
function GlobalStorageSiK.CraftSession.begin(opts)
	opts = opts or {}
	local player = opts.player
	if not player and GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer then
		player = GlobalStorageSiK.NetClient.getPlayer()
	end
	if not player then
		GlobalStorageSiK.Log.warn("CraftSession", "begin: sin jugador valido")
		lastOpenErrorReason = "no_player"
		return false, "no_player"
	end
	local networkId = opts.networkId
	if not networkId and GlobalStorageSiK.Network and GlobalStorageSiK.Network.getDefaultNetworkId then
		networkId = GlobalStorageSiK.Network.getDefaultNetworkId()
	end
	local addonId = opts.addonId
	local addonAvailable = false
	if addonId and GlobalStorageSiK.AddonRegistry and GlobalStorageSiK.AddonRegistry.isModActive(addonId) then
		if opts.knownInstalled == true then
			addonAvailable = true
		elseif GlobalStorageSiK.Addons then
			addonAvailable = GlobalStorageSiK.Addons.canUseAddon(addonId, networkId, opts.terminalAnchor)
		end
	end
	if not addonAvailable then
		-- Antes fallaba en silencio: el boton parecia no hacer nada si el
		-- modulo del addon (p.ej. la Impresora 3D) no estaba instalado en ESE
		-- terminal, o si networkId/anchor no se resolvian a tiempo.
		GlobalStorageSiK.Log.warn("CraftSession", "begin: addon no disponible",
			"addonId=" .. tostring(addonId) .. " networkId=" .. tostring(networkId))
		lastOpenErrorReason = "addon_unavailable"
		return false, "addon_unavailable"
	end

	-- Antes begin() nunca comprobaba distancia: la ventana se abria igual
	-- estando fuera de rango y se cerraba de golpe unos ticks despues (via
	-- onTick/validateAccess), sin ningun aviso claro de "por que". Ahora se
	-- avisa ANTES de abrir nada, con el mismo criterio (sessionLock + ancla
	-- de sesion) que usara luego validateAccess.
	if GlobalStorageSiK.TerminalAccess and GlobalStorageSiK.TerminalAccess.evaluate then
		local anchor = GlobalStorageSiK.TerminalAccess.getSessionAnchor and GlobalStorageSiK.TerminalAccess.getSessionAnchor(player)
		if not anchor then
			anchor = opts.terminalAnchor
		end
		local rangeOk = GlobalStorageSiK.TerminalAccess.evaluate(player, networkId, anchor, { sessionLock = true })
		if rangeOk ~= true then
			GlobalStorageSiK.Log.warn("CraftSession", "begin: fuera de rango del terminal",
				"addonId=" .. tostring(addonId) .. " networkId=" .. tostring(networkId))
			lastOpenErrorReason = "out_of_range"
			return false, "out_of_range"
		end
	end

	GlobalStorageSiK.CraftSession.installHook()
	lastEndReason = nil
	lastOpenErrorReason = nil
	session = {
		active = true,
		networkId = networkId,
		playerNum = player:getPlayerNum(),
		terminalAnchor = opts.terminalAnchor,
		accessMode = opts.accessMode,
		uiMode = opts.uiMode,
		addonId = addonId,
	}
	sessionDebugLog("begin OK addonId=" .. tostring(addonId) .. " networkId=" .. tostring(networkId)
		.. " uiMode=" .. tostring(opts.uiMode) .. " accessMode=" .. tostring(opts.accessMode))
	GlobalStorageSiK.CraftSession.ensureTick()
	return true
end

--- Finaliza la sesión de crafteo/construcción remoto.
---@param reason string|nil
function GlobalStorageSiK.CraftSession.endSession(reason)
	sessionDebugLog("endSession reason=" .. tostring(reason) .. " addonId=" .. tostring(session and session.addonId))
	lastEndReason = reason
	session = nil
	for k in pairs(claimedItemIds) do
		claimedItemIds[k] = nil
	end
	GlobalStorageSiK.CraftSession.uninstallHook()
end

--- Indica si hay sesión activa.
---@return boolean
function GlobalStorageSiK.CraftSession.isActive()
	return session ~= nil and session.active == true
end

--- Última razón de cierre de sesión.
---@return string|nil
function GlobalStorageSiK.CraftSession.getLastEndReason()
	return lastEndReason
end

--- Devuelve estado resumido de la sesión.
---@param addonId string|nil si se pasa, solo devuelve activo si la sesión
--- pertenece a ese addon (para que la pestaña de un addon no muestre "activa"
--- una sesión que en realidad abrió otro addon distinto).
---@return table
function GlobalStorageSiK.CraftSession.getStatus(addonId)
	if not session or (addonId and session.addonId ~= addonId) then
		return { active = false, lastEndReason = lastEndReason }
	end
	local containers = GlobalStorageSiK.CraftingBridge.collectNetworkContainers(session.networkId) or {}
	local liveCount, totalCount = GlobalStorageSiK.CraftingBridge.getContainerAvailability(session.networkId)
	return {
		active = true,
		networkId = session.networkId,
		networkContainers = #containers,
		unavailableContainers = math.max(0, totalCount - liveCount),
		uiMode = session.uiMode,
		addonId = session.addonId,
		lastEndReason = nil,
	}
end

--- Comprueba si una ventana entity UI está abierta.
---@param playerNum number
---@param windowKey string
---@return boolean
local function isEntityWindowOpen(playerNum, windowKey)
	return ISEntityUI
		and ISEntityUI.IsWindowOpen
		and ISEntityUI.IsWindowOpen(playerNum, windowKey) ~= nil
end

--- Abre la ventana de crafteo (vanilla, neat o automático).
---@param mode string|nil "auto"|"vanilla"|"neat"
---@return boolean ok
---@return string|nil reason "no_player"|"opener_unresolved" si falla
function GlobalStorageSiK.CraftSession.openHandcraft(mode)
	mode = mode or "auto"
	local player = GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer() or getPlayer()
	if not player then
		lastOpenErrorReason = "no_player"
		return false, "no_player"
	end
	local playerNum = player:getPlayerNum()
	if isEntityWindowOpen(playerNum, "HandcraftWindow") then
		local win = ISEntityUI.GetWindowInstance and ISEntityUI.GetWindowInstance(playerNum, "HandcraftWindow")
		if win and win.bringToTop then
			win:bringToTop()
		end
		lastOpenErrorReason = nil
		return true
	end
	local opener = GlobalStorageSiK.Libs.resolveHandcraftOpener(mode)
	if not opener then
		-- Antes fallaba en silencio: si ISEntityUI.OpenHandcraftWindow (o su
		-- variante Neat) no existia en este build/combinacion de mods, el
		-- boton no hacia absolutamente nada, sin pista de por que.
		GlobalStorageSiK.Log.warn("CraftSession", "openHandcraft: no se pudo resolver el abridor",
			"mode=" .. tostring(mode) .. " ISEntityUI=" .. tostring(ISEntityUI ~= nil)
			.. " OpenHandcraftWindow=" .. tostring(ISEntityUI and ISEntityUI.OpenHandcraftWindow ~= nil))
		lastOpenErrorReason = "opener_unresolved"
		return false, "opener_unresolved"
	end
	lastOpenErrorReason = nil
	opener(player, nil)
	return true
end

--- Abre la ventana de construcción (vanilla, neat o automático).
---@param mode string|nil "auto"|"vanilla"|"neat"
---@return boolean ok
---@return string|nil reason "no_player"|"opener_unresolved" si falla
function GlobalStorageSiK.CraftSession.openBuild(mode)
	mode = mode or "auto"
	local player = GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer() or getPlayer()
	if not player then
		lastOpenErrorReason = "no_player"
		return false, "no_player"
	end
	local playerNum = player:getPlayerNum()
	if isEntityWindowOpen(playerNum, "BuildWindow") then
		local win = ISEntityUI.GetWindowInstance and ISEntityUI.GetWindowInstance(playerNum, "BuildWindow")
		if win and win.bringToTop then
			win:bringToTop()
		end
		lastOpenErrorReason = nil
		return true
	end
	local opener = GlobalStorageSiK.Libs.resolveBuildOpener(mode)
	if not opener then
		GlobalStorageSiK.Log.warn("CraftSession", "openBuild: no se pudo resolver el abridor",
			"mode=" .. tostring(mode) .. " ISEntityUI=" .. tostring(ISEntityUI ~= nil)
			.. " OpenBuildWindow=" .. tostring(ISEntityUI and ISEntityUI.OpenBuildWindow ~= nil))
		lastOpenErrorReason = "opener_unresolved"
		return false, "opener_unresolved"
	end
	lastOpenErrorReason = nil
	opener(player, nil, "*")
	return true
end

--- Refresca la pestaña de un addon si está visible (lee su panel/módulo de
--- terminal via el estado del terminal activo, generalizado por addonId).
---@param addonId string
local function refreshAddonTabIfVisible(addonId)
	local ui = GlobalStorageSiK.TerminalUI and GlobalStorageSiK.TerminalUI.instance
	if not ui or not ui.getIsVisible or not ui:isVisible() then
		return
	end
	-- BUG REAL (reportado: cerrar Craft dejaba "sesion activa, N contenedores"
	-- visible hasta cambiar de pestaña, mientras Build si se actualizaba al
	-- instante). Antes, cuando addonId=="Craft" esta funcion SOLO refrescaba
	-- la bahia de addons y hacia return sin pasar nunca por
	-- TerminalExtensions.refreshActive - una rama especial que quedo de antes
	-- de generalizar este modulo (ver cabecera del fichero), nunca migrada a
	-- la ruta generica que ya usaban Builder y cualquier addon nuevo. Ahora
	-- ambas rutas se aplican siempre, sea cual sea el addon que cerro sesion.
	if ui.activeTabKey == "addons" and GlobalStorageSiK.TerminalAddons and GlobalStorageSiK.TerminalAddons.refresh then
		GlobalStorageSiK.TerminalAddons.refresh(ui.addonsPanel, ui)
	end
	if GlobalStorageSiK.TerminalExtensions then
		GlobalStorageSiK.TerminalExtensions.refreshActive(ui, ui.activeTabKey)
	end
end

--- Tick: cierra sesión SOLO por pérdida real de acceso (mismo criterio que
--- depositar/retirar - GlobalStorageSiK.TerminalAccess.evaluate). El estado
--- de HandcraftWindow/BuildWindow ya NO decide nada aquí: ambas ventanas
--- vanilla se autocierran solas a 1.5 baldosas de donde se abrieron
--- (ISBuildWindow.autoCloseDistance / ISHandcraftWindow.autoCloseDistance,
--- ver fuente vanilla), sin ninguna relación con si el jugador sigue
--- teniendo acceso real a la red. Cerrar la sesión por eso rompía
--- craftear/construir a mitad de acción: ISBuildAction:start() vuelve a
--- pedir contenedores DESPUÉS de que la ventana ya se hubiera autocerrado
--- durante el paseo hasta el punto de colocación, perdiendo los
--- contenedores de red justo antes de que el servidor validara los
--- materiales - la causa real del "barra completa, objeto no aparece"
--- reportado por Eric. Si el jugador sigue con acceso real (en rango o con
--- tableta), la sesión sigue viva sin importar si la ventana está
--- técnicamente abierta o no.
function GlobalStorageSiK.CraftSession.onTick()
	if not session then
		return
	end
	local playerNum = session.playerNum
	local addonId = session.addonId
	local player = getSpecificPlayer and getSpecificPlayer(playerNum) or nil
	if player and not GlobalStorageSiK.CraftSession.validateAccess(player) then
		GlobalStorageSiK.CraftSession.endSession("access_lost")
		if isEntityWindowOpen(playerNum, "HandcraftWindow") then
			local win = ISEntityUI.GetWindowInstance(playerNum, "HandcraftWindow")
			if win and win.close then
				win:close()
			end
		end
		if isEntityWindowOpen(playerNum, "BuildWindow") then
			local win = ISEntityUI.GetWindowInstance(playerNum, "BuildWindow")
			if win and win.close then
				win:close()
			end
		end
		refreshAddonTabIfVisible(addonId)
	end
end

--- Registra OnTick una sola vez.
function GlobalStorageSiK.CraftSession.ensureTick()
	if tickInstalled or not Events or not Events.OnTick then
		return
	end
	Events.OnTick.Add(function()
		tickCounter = tickCounter + 1
		if tickCounter % CHECK_TICKS ~= 0 then
			return
		end
		GlobalStorageSiK.CraftSession.onTick()
	end)
	tickInstalled = true
end

--- Registra el barrido de préstamos pendientes (ver sweepPendingReturns) más
--- los manejadores de tick que cada addon haya registrado con
--- registerTickHandler, en CADA tick (no cada CHECK_TICKS - a diferencia de
--- onTick(), aquí queremos devolver un ítem "en préstamo" o resolver una
--- espera de reclamo sin retraso perceptible). Las tablas involucradas están
--- vacías la inmensa mayoría del tiempo (pairs() sobre tabla vacía es
--- practicamente gratis).
ensureSweepTick = function()
	if sweepTickInstalled or not Events or not Events.OnTick then
		return
	end
	Events.OnTick.Add(function()
		sweepPendingReturns()
		for addonId, fn in pairs(addonTickHandlers) do
			local ok, err = pcall(fn)
			if not ok then
				GlobalStorageSiK.Log.error("CraftSession", "tick addon=" .. tostring(addonId) .. " fallo: " .. tostring(err))
			end
		end
	end)
	sweepTickInstalled = true
end
