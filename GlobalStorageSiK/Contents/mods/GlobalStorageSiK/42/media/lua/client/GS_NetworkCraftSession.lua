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

-- Contrato 2 añade el cuarto retorno numérico batchShortfall a
-- claimRecipeItems. Los addons se publican por separado y pueden consultar
-- esta señal para tolerar una actualización escalonada de Workshop.
GlobalStorageSiK.CraftSession.CLAIM_RECIPE_CONTRACT_VERSION = 2

local session = nil
local lastEndReason = nil
local originalGetContainers = nil
local hookInstalled = false
local tickInstalled = false
local tickCounter = 0
local sweepTickInstalled = false
local sweepTickUnavailableLogged = false
local ensureSweepTick -- forward-declarada: installHook() la llama, se define mas abajo (tras sweepPendingReturns)
local containerInjectionSuspendDepth = 0

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

--- Permite a un addon reportar un fallo de apertura a través del mismo
--- mecanismo que begin()/openHandcraft()/openBuild() ya usan, para ventanas
--- que el addon abre por su cuenta (ej. GSSiK_Addon_Craft_NetworkCook.lua
--- abriendo PJCK_CookingUI, que no pasa por openHandcraft porque Project_Cook
--- rastrea su propia ventana, no vía ISEntityUI) - así el panel de estado ya
--- existente (getLastOpenError) muestra el motivo sin que cada addon tenga
--- que inventar su propio campo de error paralelo.
---@param reason string|nil
function GlobalStorageSiK.CraftSession.setLastOpenError(reason)
	lastOpenErrorReason = reason
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

-- BUG REAL de ruido de log encontrado (reportado 2026-08-16, "el spam nos
-- impide ver nada"): patchedGetContainers es un hook GENERICO llamado por el
-- motor/UI constantemente (varias veces por tick mientras el panel de
-- crafteo/construccion esta abierto, no solo al reclamar) - logueaba
-- INCONDICIONALMENTE en cada llamada, inundando el log con miles de lineas
-- identicas "base=10 conRed=26" y tapando las trazas realmente utiles
-- (craftAttempt/sweepPendingReturns). Ahora solo loguea cuando los conteos
-- CAMBIAN respecto a la ultima vez, que es la unica informacion que aporta
-- esta linea de todas formas.
local lastLoggedContainerCounts = { base = nil, merged = nil }

--- Hook de contenedores para crafteo con inventario de red - GENERICO,
--- siempre activo mientras hay sesion, sea cual sea el addon.
---@param character IsoPlayer|nil
---@return userdata|nil
local function patchedGetContainers(character)
	local base = originalGetContainers(character)
	if containerInjectionSuspendDepth > 0 then
		return base
	end
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
	local merged = GlobalStorageSiK.CraftingBridge.mergeContainerLists(baseTable, session.networkId, character)
	if GlobalStorageSiK.CraftSession._debugSinks and session.addonId and GlobalStorageSiK.CraftSession._debugSinks[session.addonId]
		and (lastLoggedContainerCounts.base ~= #baseTable or lastLoggedContainerCounts.merged ~= #merged) then
		lastLoggedContainerCounts.base = #baseTable
		lastLoggedContainerCounts.merged = #merged
		sessionDebugLog("patchedGetContainers base=" .. tostring(#baseTable) .. " conRed=" .. tostring(#merged)
			.. " networkId=" .. tostring(session.networkId))
	end
	return GlobalStorageSiK.CraftSession.tableToArrayList(merged)
end

--- Ejecuta una llamada sin que patchedGetContainers añada contenedores de
--- red. Es una primitiva neutral para cualquier addon que necesite dejar que
--- vanilla serialice una acción usando exclusivamente sus contenedores
--- físicos. El contador permite anidamiento y siempre se restaura aunque la
--- llamada falle.
---@param fn function
---@param ... any
---@return boolean ok
---@return any result
function GlobalStorageSiK.CraftSession.withContainerInjectionSuspended(fn, ...)
	if type(fn) ~= "function" then
		return false, "invalid_callback"
	end
	containerInjectionSuspendDepth = containerInjectionSuspendDepth + 1
	-- Kahlua/Lua 5.1 no expone table.unpack. El contrato publico de esta
	-- primitiva solo necesita el primer resultado del callback, igual que
	-- pcall: `ok, resultOrError`.
	local ok, result = pcall(fn, ...)
	containerInjectionSuspendDepth = math.max(0, containerInjectionSuspendDepth - 1)
	return ok, result
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

--- Ítems "prestados" de un contenedor de red al inventario del jugador para
--- poder craftear/construir sin desplazarse - itemId -> { networkId,
--- playerNum, fullType }. Se devuelven solos en sweepPendingReturns en
--- cuanto termina la acción, o se olvidan si la receta ya los consumió.
local pendingReturns = {}

--- Asocia una operacion adicional a un item ya prestado. Es necesario cuando
--- vanilla/Neat encolan varias construcciones: la siguiente accion puede
--- reutilizar la misma herramienta que la anterior aun tiene en inventario.
--- El item solo podra volver a la red cuando TODAS sus operaciones terminen.
---@param info table
---@param operationId string|nil
local function addOperationLease(info, operationId)
	if not info or not operationId then
		return
	end
	info.operationIds = info.operationIds or {}
	if info.operationId then
		info.operationIds[info.operationId] = true
	end
	info.operationIds[operationId] = true
	info.loggedWaitingActive = nil
	info.addedAt = getTimestampMs and getTimestampMs() or info.addedAt
end

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

--- Retiene para otra operacion un item ya reclamado. No mueve ni duplica el
--- objeto; solo amplía el lease neutral que controla su devolución.
---@param itemId number|nil
---@param operationId string|nil
---@return boolean retained
function GlobalStorageSiK.CraftSession.retainClaimedItem(itemId, operationId)
	local info = itemId and pendingReturns[itemId] or nil
	if not info or claimedItemIds[itemId] ~= true then
		return false
	end
	addOperationLease(info, operationId)
	return true
end

--- operationId -> true para operaciones de crafteo/construccion cuyo evento
--- de fin (onHandcraftActionComplete/Cancelled, o el equivalente de
--- construccion) YA se disparo - CRITICO (reportado 2026-08-16, "posible
--- dupeo, se devuelven objetos con los que todavia esta fabricando"): antes
--- sweepPendingReturns decidia si devolver un item SOLO por tiempo
--- transcurrido desde el reclamo (RETURN_GRACE_MS), sin saber si la accion
--- de crafteo/construccion habia terminado de verdad. Confirmado con logs
--- reales: el margen fijo vencia y devolvia el material AL ALMACEN SIETE
--- SEGUNDOS ANTES de que craftAttempt RESULT/END llegara - exactamente el
--- riesgo de dupe que se queria evitar (material fisico devuelto a la red
--- mientras la receta aun podia estar consumiendolo). Ahora la devolucion
--- se ata al evento REAL de fin de operacion (ver markOperationComplete,
--- llamado desde cada addon en sus 4 manejadores onHandcraftActionComplete/
--- Cancelled - vanilla y Neat - y el equivalente de Cook), no a un
--- cronometro. Se limpia en endSession igual que claimedItemIds.
local completedOperations = {}

--- Enviar el RESULTADO del crafteo (y cualquier material sobrante) a la red
--- por prioridad en vez de dejarlo en el inventario del jugador - pedido
--- explicito (2026-08-17), preferencia SOLO de cliente (checkbox en la
--- pestaña Craft, GSSiK_Addon_Craft_TerminalUI.lua). Las herramientas YA
--- vuelven solas sin esto (sweepPendingReturns, mecanismo existente sin
--- tocar) - esto es aparte, solo para lo NUEVO que aparece en el inventario
--- tras crafteo. Compartido con Builder (misma infraestructura Core), pero
--- en la practica no afecta a construccion: un build no añade ningun item
--- nuevo al inventario (el objeto construido va directo al mundo), asi que
--- el barrido de abajo no encuentra nada que mover en ese caso.
GlobalStorageSiK.CraftSession.sendResultToNetwork = false

-- operationId -> snapshot de IDs de item en el inventario principal del
-- jugador ANTES de reclamar nada (ver claimRecipeItems) - solo se rellena
-- si sendResultToNetwork esta activo al empezar la operacion, para no pagar
-- el coste de escanear el inventario cuando el jugador no usa esto.
local preClaimSnapshot = {}
local preClaimNetworkId = {}
local preClaimPlayerNum = {}

--- Envia a la red cualquier item nuevo en el inventario del jugador que NO
--- estuviera antes del claim (preClaimSnapshot) y que no sea un material/
--- herramienta ya reclamado de la red (eso lo devuelve sweepPendingReturns
--- por su cuenta, no hay que interferir) - en la practica, "nuevo" = el
--- resultado del crafteo.
---@param operationId string
local function sweepCraftResultToNetwork(operationId)
	local before = preClaimSnapshot[operationId]
	local networkId = preClaimNetworkId[operationId]
	local playerNum = preClaimPlayerNum[operationId]
	preClaimSnapshot[operationId] = nil
	preClaimNetworkId[operationId] = nil
	preClaimPlayerNum[operationId] = nil
	if not before or not networkId or not playerNum then
		return
	end
	local player = getSpecificPlayer and getSpecificPlayer(playerNum) or nil
	if not player then
		return
	end
	local inv = player.getInventory and player:getInventory()
	local items = inv and inv.getItems and inv:getItems()
	if not items or not items.size then
		return
	end
	local toDeposit = {}
	for i = 0, items:size() - 1 do
		local item = items:get(i)
		if item and item.getID then
			local id = item:getID()
			if not before[id] and not GlobalStorageSiK.CraftSession.isItemClaimed(id) then
				toDeposit[#toDeposit + 1] = item
			end
		end
	end
	if #toDeposit == 0 then
		return
	end
	if GlobalStorageSiK.isAuthoritative() then
		for i = 1, #toDeposit do
			GlobalStorageSiK.Transfer.depositItem(player, toDeposit[i], networkId)
		end
	elseif GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.sendCommand then
		local ids = {}
		for i = 1, #toDeposit do
			ids[#ids + 1] = toDeposit[i]:getID()
		end
		-- En cliente MP puro, "depositItems" ejecuta en servidor el mismo
		-- Transfer.depositItem por prioridad - mismo patron que
		-- sweepPendingReturns usa para devolver herramientas.
		GlobalStorageSiK.NetClient.sendCommand("depositItems", {
			itemIds = ids,
			origin = "operation_result_deposit",
			operationId = operationId,
		})
	end
end

--- Marca una operacion de crafteo/construccion como terminada (completada O
--- cancelada, ambas formas validas de "ya no se va a tocar mas este item") -
--- llamado por cada addon desde sus manejadores de fin de accion. Necesario
--- porque el Core no conoce las clases concretas de accion de cada addon
--- (vanilla ISWidgetHandCraftControl, Neat NC_CraftActionPanel, Project_Cook
--- PJCK_CraftActionPanel...) - solo conoce el operationId que el addon ya le
--- paso al reclamar los items via claimRecipeItems/claimNetworkItem.
---@param operationId string|nil
function GlobalStorageSiK.CraftSession.markOperationComplete(operationId)
	if not operationId then
		return
	end
	completedOperations[operationId] = true
	if preClaimSnapshot[operationId] then
		-- Si se cancelo el crafteo, el diff no encuentra nada nuevo (no se
		-- creo nada) y esto no hace nada - seguro llamarlo siempre que haya
		-- snapshot, sin distinguir completado de cancelado.
		sweepCraftResultToNetwork(operationId)
	end
end

--- Un préstamo compartido solo está libre cuando finalizaron todas las
--- operaciones que lo adoptaron. El fallback mantiene compatibilidad con
--- entradas creadas antes de introducir operationIds.
---@param info table
---@return boolean
local function areItemOperationsComplete(info)
	if info.operationIds then
		local hasOperations = false
		for operationId in pairs(info.operationIds) do
			hasOperations = true
			if completedOperations[operationId] ~= true then
				return false
			end
		end
		return hasOperations
	end
	return info.operationId ~= nil and completedOperations[info.operationId] == true
end

--- Aborta una operacion de préstamo. El Core no decide qué constituye un
--- fallo ni cómo comunicarlo: esas responsabilidades pertenecen al addon.
--- Solo descarta el snapshot de resultado y conserva los préstamos hasta
--- devolverlos, incluso si el ACK del servidor llega después del aborto.
---@param operationId string|nil
function GlobalStorageSiK.CraftSession.abortOperation(operationId)
	if not operationId then
		return
	end
	completedOperations[operationId] = true
	preClaimSnapshot[operationId] = nil
	preClaimNetworkId[operationId] = nil
	preClaimPlayerNum[operationId] = nil
	for _, info in pairs(pendingReturns) do
		if info.operationId == operationId
			or (info.operationIds and info.operationIds[operationId] == true) then
			info.failedOperation = true
		end
	end
	sessionDebugLog("operation ABORTED operationId=" .. tostring(operationId))
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
			addOperationLease(pendingReturns[itemId], operationId)
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
				addedAt = getTimestampMs and getTimestampMs() or 0,
				operationId = operationId,
				operationIds = operationId and { [operationId] = true } or {},
				wasLocated = false,
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
				addedAt = getTimestampMs and getTimestampMs() or 0,
				operationId = operationId,
				operationIds = operationId and { [operationId] = true } or {},
				wasLocated = true,
			}
		end
		sessionDebugLog("claimNetworkItem OK (local, autoritativo) fullType=" .. fullType)
	else
		sessionDebugLog("claimNetworkItem FALLO (sin espacio/peso real) fullType=" .. fullType)
	end
	return ok
end

--- Recorta self.containers de un panel de crafteo (ISWidgetHandCraftControl,
--- NC_CraftActionPanel, PJCK_CraftActionPanel de Project_Cook, o cualquier
--- panel de un addon futuro con campo .logic de tipo HandcraftLogic) a:
--- contenedores base (no de red) + SOLO los contenedores de red que de
--- verdad tienen algo que la receta actual necesita ahora mismo - confirmado
--- con datos reales (ver CLAUDE.md de GSSiK_Addon_Craft) que
--- HandcraftLogic.performCurrentRecipe() en servidor devuelve
--- itemsCreados=0 en cuanto self.containers incluye CUALQUIER contenedor
--- inyectado de red, sea 1 o sean todos - limitación del motor, no cosa de
--- un panel concreto. GENÉRICO: no conoce la clase concreta del panel, solo
--- necesita panel.logic y panel.logic:getContainers()/setContainers()
--- (API vanilla de HandcraftLogic, presente en cualquier panel construido
--- sobre ella, sea vanilla, Neat Crafting o un mod de terceros como
--- Project_Cook).
---@param panel table objeto con campo .logic (HandcraftLogic)
---@param items userdata|nil ArrayList de InventoryItem (getAllInputItems), puede ser nil
---@param addonId string
---@return function restore
function GlobalStorageSiK.CraftSession.narrowContainersForAction(panel, items, addonId)
	local okFull, fullList = pcall(function() return panel.logic:getContainers() end)
	if not okFull or not fullList or not fullList.size then
		return function() end
	end
	local sess = GlobalStorageSiK.CraftSession.getActiveSession(addonId)
	local networkId = sess and sess.networkId
	local neededNetwork = {}
	local seen = {}
	if items and items.size then
		for i = 1, items:size() do
			local ok, item = pcall(function() return items:get(i - 1) end)
			local container = ok and item and item.getContainer and item:getContainer()
			if container and GlobalStorageSiK.CraftSession.isNetworkContainer(container, networkId) and not seen[container] then
				seen[container] = true
				neededNetwork[#neededNetwork + 1] = container
			end
		end
	end
	local narrowed = {}
	for i = 0, fullList:size() - 1 do
		local c = fullList:get(i)
		if not (c and GlobalStorageSiK.CraftSession.isNetworkContainer(c, networkId)) then
			narrowed[#narrowed + 1] = c
		end
	end
	for i = 1, #neededNetwork do
		narrowed[#narrowed + 1] = neededNetwork[i]
	end
	local okSet = pcall(function() panel.logic:setContainers(GlobalStorageSiK.CraftSession.tableToArrayList(narrowed)) end)
	sessionDebugLog(string.format("containersNarrow original=%d narrowed=%d aplicado=%s",
		fullList:size(), #narrowed, tostring(okSet)))
	return function()
		pcall(function() panel.logic:setContainers(fullList) end)
	end
end

--- Reclama de la red, para el jugador, todos los ingredientes/herramientas
--- de la receta que estén en un contenedor de red - GENÉRICO, usado por
--- vanilla/Neat Crafting/Project_Cook/cualquier panel basado en
--- HandcraftLogic (ver narrowContainersForAction). Tiene en cuenta crafteo
--- por lotes (batchCount>1): para cada tipo de ingrediente ya reclamado en
--- la primera pasada, intenta reclamar unidades EXTRA de ese mismo tipo
--- desde la red hasta cubrir el lote completo.
---@param player IsoPlayer
---@param logic userdata HandcraftLogic
---@param items userdata ArrayList de InventoryItem (getAllInputItems)
---@param networkId string|nil
---@param operationId string
---@param batchCount number|nil
---@return table waitingIds, number waitingCount, number moved, number batchShortfall
function GlobalStorageSiK.CraftSession.claimRecipeItems(player, logic, items, networkId, operationId, batchCount)
	if operationId and player and GlobalStorageSiK.CraftSession.sendResultToNetwork then
		local snap = {}
		local inv = player.getInventory and player:getInventory()
		local invItems = inv and inv.getItems and inv:getItems()
		if invItems and invItems.size then
			for i = 0, invItems:size() - 1 do
				local it = invItems:get(i)
				if it and it.getID then
					snap[it:getID()] = true
				end
			end
		end
		preClaimSnapshot[operationId] = snap
		preClaimNetworkId[operationId] = networkId
		preClaimPlayerNum[operationId] = player.getPlayerNum and player:getPlayerNum() or nil
	end

	local waitingIds = {}
	local waitingCount = 0
	local moved = 0
	local batchShortfall = 0
	local authoritative = GlobalStorageSiK.isAuthoritative()
	local selectedConsumableCounts = {}
	local selectedConsumableTypeCount = 0
	local selectedInputIds = {}
	local consumableIds = {}
	local keepIds = {}
	local hasConsumableMetadata = false
	local useKeepFallback = false
	local recipeData = logic and logic.getRecipeData and logic:getRecipeData() or nil
	-- `getAllPutBackInputItems()` NO significa "keep/tool": incluye inputs
	-- cuya politica devuelve su contenedor y, en B42, puede contener también
	-- consumibles normales. La separación autoritativa que usa HandcraftLogic
	-- es getAllNotKeepInputItems()/getAllKeepInputItems(). Confundir ambas APIs
	-- hacía que un lote de 2 detectara cero consumibles extra.
	local notKeepItems = nil
	if recipeData and recipeData.getAllNotKeepInputItems then
		local ok, result = pcall(function() return recipeData:getAllNotKeepInputItems() end)
		if ok and result and result.size then
			notKeepItems = result
			hasConsumableMetadata = true
		end
	end
	if notKeepItems then
		for i = 0, notKeepItems:size() - 1 do
			local item = notKeepItems:get(i)
			if item and item.getID then
				consumableIds[item:getID()] = true
			end
		end
	elseif recipeData and recipeData.getAllKeepInputItems then
		local ok, keepItems = pcall(function() return recipeData:getAllKeepInputItems() end)
		if ok and keepItems and keepItems.size then
			useKeepFallback = true
			hasConsumableMetadata = true
			for i = 0, keepItems:size() - 1 do
				local item = keepItems:get(i)
				if item and item.getID then
					keepIds[item:getID()] = true
				end
			end
		end
	end

	local function claim(item, container)
		if GlobalStorageSiK.CraftSession.claimNetworkItem(player, item, container, networkId, operationId) then
			moved = moved + 1
			if not authoritative and item.getID then
				waitingIds[item:getID()] = true
				waitingCount = waitingCount + 1
			end
			return true
		end
		return false
	end

	if items and items.size then
		for i = 1, items:size() do
			local item = items:get(i - 1)
			if item then
				local fullType = item.getFullType and item:getFullType() or nil
				local itemId = item.getID and item:getID() or nil
				if itemId then
					selectedInputIds[itemId] = true
					-- Una herramienta reclamada por una construccion anterior puede
					-- aparecer ahora como input local. Adoptarla evita que la primera
					-- operacion la devuelva mientras esta segunda aun la usa.
					GlobalStorageSiK.CraftSession.retainClaimedItem(itemId, operationId)
				end
				local isConsumable = itemId and consumableIds[itemId] == true
				if useKeepFallback then
					isConsumable = itemId ~= nil and keepIds[itemId] ~= true
				end
				if fullType and isConsumable then
					if not selectedConsumableCounts[fullType] then
						selectedConsumableTypeCount = selectedConsumableTypeCount + 1
					end
					selectedConsumableCounts[fullType] = (selectedConsumableCounts[fullType] or 0) + 1
				end
				local container = item.getContainer and item:getContainer()
				if container and GlobalStorageSiK.CraftSession.isNetworkContainer(container, networkId) then
					claim(item, container)
				end
			end
		end
	end

	-- NUNCA next() aqui (Kahlua no lo soporta de forma fiable): el contador
	-- propio indica si hay consumibles seleccionados que ampliar para el lote.
	if batchCount and batchCount > 1 and not hasConsumableMetadata then
		batchShortfall = batchCount - 1
		sessionDebugLog("batchPlan operationId=" .. tostring(operationId)
			.. " sin metadata keep/notKeep; se abortara de forma segura")
	elseif batchCount and batchCount > 1 and selectedConsumableTypeCount > 0 then
		local okCon, containers = pcall(function() return logic:getContainers() end)
		local planParts = {}
		for fullType, perCraftCount in pairs(selectedConsumableCounts) do
			local need = (batchCount - 1) * perCraftCount
			local requiredExtra = need
			local claimedExtra = 0
			local localExtra = 0
			-- CraftRecipeData ya entrega exactamente las instancias asignadas a
			-- la primera receta. InventoryItem:getCount() NO es capacidad extra:
			-- en el caso real de Base.Nails devolvía 3 por cada clavo seleccionado
			-- y hacía creer que tres IDs cubrían las nueve unidades de un lote 3.
			-- Cada itemId candidato cubre una única entrada consumible.
			local usedSelectedSurplus = 0
			if okCon and containers and containers.size then
				-- La primera receta ya está representada por `items`. Para cada
				-- unidad adicional hay que reclamar TODOS los consumibles de ese
				-- tipo seleccionados para una receta, no solo "batch - movidos".
				-- Ejemplo real: una receta usa 4 clavos; lote 2 necesita 4 clavos
				-- extra. La fórmula anterior daba 2-4 y no reclamaba ninguno.
				-- Primero snapshot de candidatos: en SP/host claim() mueve el ítem
				-- y mutaría la lista Java que estamos recorriendo, pudiendo saltarse
				-- el siguiente. En MP remoto todavía no se mueve localmente, pero se
				-- usa el mismo camino determinista.
				local candidates = {}
				local candidateIds = {}
				local c = 0
				while c < containers:size() do
					local container = containers:get(c)
					c = c + 1
					if container then
						local isNetwork = GlobalStorageSiK.CraftSession.isNetworkContainer(container, networkId)
						local okItems2, itemsInC = pcall(function() return container:getItems() end)
						if okItems2 and itemsInC and itemsInC.size then
							for j = 0, itemsInC:size() - 1 do
								local extraItem = itemsInC:get(j)
								local extraId = extraItem and extraItem.getID and extraItem:getID() or nil
								if extraItem and extraItem.getFullType and extraItem:getFullType() == fullType
									and extraId and not selectedInputIds[extraId]
									and not candidateIds[extraId]
									and not GlobalStorageSiK.CraftSession.isItemClaimed(extraId) then
									candidateIds[extraId] = true
									candidates[#candidates + 1] = {
										item = extraItem,
										container = container,
										isNetwork = isNetwork,
									}
								end
							end
						end
					end
				end
				for i = 1, #candidates do
					if need <= 0 then break end
					local candidate = candidates[i]
					local units = 1
					if candidate.isNetwork then
						if claim(candidate.item, candidate.container) then
							claimedExtra = claimedExtra + units
							need = need - units
						end
					else
						-- Ya está en un contenedor físico que la acción vanilla puede
						-- consumir; cuenta para el lote pero no es un préstamo de red.
						localExtra = localExtra + units
						need = need - units
					end
				end
			end
			batchShortfall = batchShortfall + need
			planParts[#planParts + 1] = tostring(fullType) .. ":" .. tostring(perCraftCount)
				.. "->extra" .. tostring(requiredExtra - need)
				.. "(selected" .. tostring(usedSelectedSurplus)
				.. ",red" .. tostring(claimedExtra) .. ",local" .. tostring(localExtra) .. ")"
				.. (need > 0 and ("/faltan" .. tostring(need)) or "")
		end
		table.sort(planParts)
		sessionDebugLog("batchPlan operationId=" .. tostring(operationId)
			.. " batchCount=" .. tostring(batchCount)
			.. " consumibles=" .. table.concat(planParts, ","))
	end

	return waitingIds, waitingCount, moved, batchShortfall
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
--- CAUSA REAL CONFIRMADA (2026-08-16, con logs reales con print() directo):
--- sweepPendingReturns SI se ejecuta cada tick (esto ya se habia dudado y se
--- descarto), pero corre en el MISMO tick en que se envia el claim - en ese
--- instante el item todavia aparece fisicamente en el contenedor de RED
--- desde el punto de vista del cliente (el servidor tarda ~300-400ms en
--- confirmar el movimiento real, ver comentario de claimNetworkItem). La
--- rama "no esta en el inventario principal" trataba eso IGUAL que "el
--- jugador lo movio a otro sitio a proposito" y borraba la entrada de
--- pendingReturns para siempre, ANTES de que el item terminara de llegar al
--- inventario - de ahi que ninguna herramienta volviera nunca: se dejaba de
--- rastrear en el primerisimo tick, sistematicamente, en el 100% de los
--- casos.
--- REGRESION 1 (build -dev5): el margen de gracia solo se aplicaba cuando
--- el item AUN NO estaba en el inventario, dejando sin cubrir el caso
--- simetrico (item ya en inventario, crafteo aun no encolado) - arreglado
--- en -dev6 aplicando el margen SIEMPRE desde addedAt.
--- REGRESION 2, la de fondo (reportada 2026-08-16, "posible dupeo, se
--- devuelven objetos con los que todavia esta fabricando"): incluso con el
--- fix de -dev6, un margen de tiempo FIJO (RETURN_GRACE_MS) sigue sin saber
--- si el crafteo ya termino de verdad - solo mide "ha pasado tiempo desde
--- el reclamo". Confirmado con logs reales: el margen vencia y el material
--- se devolvia al almacen SIETE SEGUNDOS ANTES de que craftAttempt RESULT/
--- END llegara - exactamente el riesgo de dupe que preocupaba (material
--- fisico devuelto a la red mientras la receta aun podia estar
--- consumiendolo/produciendo el resultado). FIX DEFINITIVO: la devolucion
--- ya NO se basa en tiempo transcurrido, se ata al evento REAL de fin de
--- operacion (ver markOperationComplete, llamado por cada addon desde sus
--- manejadores onHandcraftActionComplete/Cancelled - vanilla, Neat y Cook).
--- Mientras completedOperations[info.operationId] no sea true, el item
--- NUNCA se devuelve, sin importar cuanto tiempo pase ni donde este. Se
--- Un cronometro tampoco es una red de seguridad valida para lotes largos:
--- 10 unidades pueden tardar bastante mas de 30 segundos. Si falta el evento
--- se avisa una sola vez, pero NO se transfiere nada automaticamente; el addon
--- debe completar o abortar explicitamente la operacion.
local RETURN_STUCK_WARN_MS = 300000

-- El print() incondicional "tick, pendientes=N" (una linea por CADA tick
-- mientras hubiera algo pendiente, hasta 60/s) ya cumplio su proposito -
-- confirmar con datos reales que la funcion SI se ejecuta cada tick - y se
-- ha retirado (2026-08-16) por puro ruido de log una vez confirmado; los
-- logs por-item de mas abajo (que disparan una sola vez cada uno, no cada
-- tick) siguen siendo suficientes para depurar el resultado real.
local function sweepPendingReturns()
	local nowMs = getTimestampMs and getTimestampMs() or 0
	local remoteBatches = {}
	for itemId, info in pairs(pendingReturns) do
		local player = getSpecificPlayer and getSpecificPlayer(info.playerNum) or nil
		if not player then
			pendingReturns[itemId] = nil
		else
			local item, currentContainer = GlobalStorageSiK.Deposit.findItemById(player, itemId)
			if not item or not currentContainer then
				local operationDone = areItemOperationsComplete(info)
				-- En cliente MP el item aun no es localizable mientras el servidor
				-- procesa el claim. No confundir ese viaje con un consumo real.
				if not operationDone then
					if not info.loggedWaitingArrival then
						info.loggedWaitingArrival = true
						sessionDebugLog("return waitArrival itemId=" .. tostring(itemId)
							.. " esperando llegada del claim operationId=" .. tostring(info.operationId))
					end
					if not info.loggedStuckWarning and info.addedAt
						and (nowMs - info.addedAt) >= RETURN_STUCK_WARN_MS then
						info.loggedStuckWarning = true
						sessionDebugLog("return stuckActive itemId=" .. tostring(itemId)
							.. " operationId=" .. tostring(info.operationId)
							.. " sin evento de fin tras " .. tostring(RETURN_STUCK_WARN_MS)
							.. "ms; se conserva, no se devuelve por tiempo")
					end
				else
					sessionDebugLog("return resolvedMissing itemId=" .. tostring(itemId)
						.. " no localizable (consumido o claim agotado) fullType=" .. tostring(info.fullType))
					pendingReturns[itemId] = nil
					claimedItemIds[itemId] = nil
				end
			else
				info.wasLocated = true
				local operationDone = areItemOperationsComplete(info)
				if not operationDone then
					if not info.loggedWaitingActive then
						-- Se loguea UNA vez por item (no cada tick) en cuanto se
						-- detecta el primer aplazamiento, no en cada iteracion.
						info.loggedWaitingActive = true
						sessionDebugLog("return waitActive itemId=" .. tostring(itemId)
							.. " fullType=" .. tostring(info.fullType)
							.. " aplazado (operationId=" .. tostring(info.operationId)
							.. " todavia no ha terminado, se reintentara cuando llegue el evento de fin)")
					end
					if not info.loggedStuckWarning and info.addedAt
						and (nowMs - info.addedAt) >= RETURN_STUCK_WARN_MS then
						info.loggedStuckWarning = true
						sessionDebugLog("return stuckActive itemId=" .. tostring(itemId)
							.. " operationId=" .. tostring(info.operationId)
							.. " sin evento de fin tras " .. tostring(RETURN_STUCK_WARN_MS)
							.. "ms; se conserva, no se devuelve por tiempo")
					end
				else
					local returnOrigin
					if info.failedOperation then
						returnOrigin = "operation_abort_return"
					else
						returnOrigin = "operation_complete_return"
					end
					if GlobalStorageSiK.isAuthoritative() then
						local ok, reason = GlobalStorageSiK.Transfer.depositItem(player, item, info.networkId)
						sessionDebugLog("return local ok=" .. tostring(ok)
							.. " (local, autoritativo, deposito por prioridad) itemId=" .. tostring(itemId)
							.. " fullType=" .. tostring(info.fullType)
							.. " origin=" .. tostring(returnOrigin)
							.. " operationId=" .. tostring(info.operationId)
							.. " reason=" .. tostring(reason))
					elseif GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.sendCommand then
						-- Agrupar además por operación/origen: mezclar un aborto con
						-- un final correcto haría ambiguo el diagnóstico.
						local batchKey = tostring(info.networkId or "") .. "|"
							.. tostring(info.operationId or "") .. "|" .. returnOrigin
						local batch = remoteBatches[batchKey]
						if not batch then
							batch = {
								networkId = info.networkId,
								operationId = info.operationId,
								origin = returnOrigin,
								itemIds = {},
							}
							remoteBatches[batchKey] = batch
						end
						batch.itemIds[#batch.itemIds + 1] = itemId
					else
						sessionDebugLog("return noTransport itemId=" .. tostring(itemId)
							.. " isAuthoritative=" .. tostring(GlobalStorageSiK.isAuthoritative())
							.. " NetClient=" .. tostring(GlobalStorageSiK.NetClient ~= nil))
					end
					pendingReturns[itemId] = nil
					-- Limpia claimedItemIds al devolverlo - ver comentario
					-- arriba (rama "no localizable"), mismo motivo.
					claimedItemIds[itemId] = nil
				end
			end
		end
	end
	for _, batch in pairs(remoteBatches) do
		GlobalStorageSiK.NetClient.sendCommand("depositItems", {
			itemIds = batch.itemIds,
			networkId = batch.networkId,
			origin = batch.origin,
			operationId = batch.operationId,
		})
		sessionDebugLog("return remoteBatchSent count=" .. tostring(#batch.itemIds)
			.. " networkId=" .. tostring(batch.networkId)
			.. " origin=" .. tostring(batch.origin)
			.. " operationId=" .. tostring(batch.operationId))
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
	local containers = GlobalStorageSiK.CraftingBridge.collectNetworkContainers(session.networkId, player) or {}
	local liveCount, totalCount = GlobalStorageSiK.CraftingBridge.getContainerAvailability(session.networkId, player)
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
	if sweepTickInstalled then
		return
	end
	if not Events or not Events.OnTick then
		if not sweepTickUnavailableLogged then
			sweepTickUnavailableLogged = true
			sessionDebugLog("sweepTick unavailable Events=" .. tostring(Events ~= nil)
				.. " Events.OnTick=" .. tostring(Events and Events.OnTick ~= nil))
		end
		return
	end
	sessionDebugLog("sweepTick installing")
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
