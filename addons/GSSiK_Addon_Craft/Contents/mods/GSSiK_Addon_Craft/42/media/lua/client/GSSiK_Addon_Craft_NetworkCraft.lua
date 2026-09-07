--[[
	GSSiK Addon Craft - Crafteo remoto (vanilla + Neat Crafting)
	Autor: SiK
	Fecha: 2026-08-13 (migrado desde GS_NetworkCraftSession.lua del Core -
	pedido explícito: Core no debería conocer ISWidgetHandCraftControl ni
	NC_CraftActionPanel, eso es conocimiento exclusivo de este addon; el
	Core solo expone infraestructura genérica de sesión/préstamo vía
	GSSiK.API.WorkSession).
	Descripción: Intercepta el arranque de crafteo (vanilla y Neat Crafting,
	si está instalado) mientras hay una sesión GSSiK.API.WorkSession
	activa para este addon ("Craft"): mueve al inventario del jugador los
	ingredientes/herramientas que estén en un contenedor de red (confirmado
	con datos reales que HandcraftLogic.performCurrentRecipe() en servidor no
	puede consumir directamente de contenedores inyectados por el mod, ni
	siquiera 1 solo - ver comentarios abajo), recorta la lista de
	contenedores que ve la acción real a solo contenedores 100% vanilla, deja
	craftear, y devuelve sobrantes/herramientas a la red por prioridad al
	terminar.
]]

local API = require "GSSiK_API_Client"
require "GSSiK_Addon_Craft_Log"
require "GSSiK_Addon_Craft_ClaimCompat"
require "GSSiK_Addon_Craft_BatchState"
require "GSSiK_Addon_Craft_NetworkCook"

local BatchState = GSSiK_Addon_Craft.BatchState
local Session = API.WorkSession
local Diagnostics = API.Diagnostics

local ADDON_ID = "Craft"

local function failCraftOperation(operationId, player, reasonKey)
	if not operationId then return end
	Session.abortOperation(operationId, player)
	local reason = getText(reasonKey)
	local message = getText("IGUI_GSSIK_CraftOperationFailedReturned", reason)
	if player and player.setHaloNote then
		player:setHaloNote(message, 255, 120, 100, 450)
	end
end

local debugOk, debugCode, debugRegistration = Diagnostics.registerWorkSessionSink(ADDON_ID, function(message)
        GSSiK_Addon_Craft.Log.debug("Operations", message)
end)
if debugOk ~= true then
        error("GSSiK.API WorkSession debug sink: " .. tostring(debugCode))
end
GSSiK_Addon_Craft._workDebugRegistration = debugRegistration

local originalTransferIfNeeded = nil
local originalStartHandcraft = nil
local originalOnHandcraftActionComplete = nil
local originalOnHandcraftActionCancelled = nil
local originalNeatStartHandcraft = nil
local originalNeatOnHandcraftActionComplete = nil
local originalNeatOnHandcraftActionCancelled = nil

--- operationId del intento EN CURSO mientras vanilla ejecuta su propio
--- startHandcraft (primera pasada o reanudacion) - permite que
--- patchedTransferIfNeeded (que no recibe "self", solo playerObj/item) sepa
--- a que intento pertenece un reclamo de la red de seguridad, en vez de
--- loguear "operationId=nil". Declarada AQUI (antes de patchedTransferIfNeeded)
--- - el clasico bug de forward-reference de Kahlua: un local declarado
--- DESPUES de la closure que lo usa como upvalue nunca se resuelve.
local activeOperationId = nil

--- EXPERIMENTO CONFIRMADO (2026-08-13): la sola PRESENCIA de contenedores de
--- red "extra" en self.containers (25/26 en las pruebas, la lista COMPLETA
--- que patchedGetContainers fusiona) hace fallar
--- HandcraftLogic.performCurrentRecipe() en servidor (itemsCreados=0
--- SIEMPRE, tanto con recetas floor sin tocar nada como con recetas
--- no-floor con todo ya confirmado en el inventario) - independientemente
--- de donde este fisicamente el item. En vez de servir la lista COMPLETA a
--- la accion real, se reduce a: contenedores base (no de red) + SOLO los
--- contenedores de red que de verdad tienen algo que ESTA receta necesita
--- ahora mismo. Se restaura la lista completa justo despues, para no romper
--- el resto de la ventana de crafteo (browsing de otras recetas, etc.).
---@param self table ISWidgetHandCraftControl|NC_CraftActionPanel
---@param items userdata|nil ArrayList de InventoryItem (getAllInputItems), puede ser nil
---@return function restore
local function narrowContainersForAction(self, items)
	local ok, _, handle = Session.narrowInputs(self, items, ADDON_ID)
	return function()
		if ok and handle then handle:restore() end
	end
end

local function activeSession()
	local ok, _, value = Session.get(ADDON_ID)
	return ok and value or nil
end

--- Reclama de la red, para el jugador, todos los ingredientes/herramientas
--- de la receta que esten en un contenedor de red - UNIVERSAL para
--- cualquier receta (ya NO se exime a las recetas "craftable desde el
--- suelo" como SawLogs - confirmado con datos reales que el motor no
--- consume de NINGUN contenedor inyectado por el mod, sea 1 o sean 25; la
--- unica via que funciona de verdad es mover todo lo necesario al
--- inventario y servir a la accion real solo contenedores 100% vanilla, ver
--- narrowContainersForAction). Tiene en cuenta crafteo por lotes
--- (batchCount>1): para cada tipo de ingrediente ya reclamado en la primera
--- pasada, intenta reclamar unidades EXTRA de ese mismo tipo desde la red
--- hasta cubrir el lote completo - una herramienta reutilizable (1 sola
--- unidad en la receta) no necesita mas aunque el lote pida varias, asi que
--- esto no la duplica de mas.
---@param player IsoPlayer
---@param logic userdata HandcraftLogic
---@param items userdata ArrayList de InventoryItem (getAllInputItems)
---@param networkId string|nil
---@param operationId string
---@param batchCount number|nil
---@return table waitingIds, number waitingCount, number moved, number batchShortfall, boolean batchContractSupported
local function claimNetworkCraftItems(player, logic, items, operationId, batchCount)
	return GSSiK_Addon_Craft.claimRecipeItemsCompat(
		player, logic, items, operationId, batchCount)
end

--- Lee la cantidad de lote pedida en la ventana vanilla (entryBox), 1 si no
--- aplica batch o no se puede leer.
---@param self table ISWidgetHandCraftControl
---@return number
local function readVanillaBatchCount(self)
	if not self.allowBatchCraft or not self.entryBox or not self.entryBox.getInternalText then
		return 1
	end
	local ok, text = pcall(function() return self.entryBox:getInternalText() end)
	if ok and text then
		local n = tonumber(text)
		if n and n > 1 then
			return math.floor(n)
		end
	end
	return 1
end

--- Arranques de crafteo esperando confirmación del servidor de que los
--- ítems de red YA están de verdad en el inventario del jugador, antes de
--- dejar que vanilla continúe - ver patchedStartHandcraft para el porqué.
--- entry = { self, force, waitingIds = {[itemId]=true}, startedAt }
local pendingCraftStarts = {}
local PENDING_CRAFT_TIMEOUT_MS = 4000

--- Revisa cada tick si los ítems reclamados ya aparecen (por ID) en el
--- inventario del jugador; en cuanto TODOS estén, o tras un timeout de
--- seguridad, deja que arranque de verdad la acción de crafteo vanilla.
local function checkPendingCraftStarts()
	if #pendingCraftStarts == 0 then
		return
	end
	local nowMs = getTimestampMs and getTimestampMs() or 0
	for i = #pendingCraftStarts, 1, -1 do
		local entry = pendingCraftStarts[i]
		local inv = entry.self.player and entry.self.player.getInventory and entry.self.player:getInventory()
		local allReady = true
		for itemId in pairs(entry.waitingIds) do
			local found = nil
			if inv and inv.getItemWithID then
				local ok, result = pcall(function() return inv:getItemWithID(itemId) end)
				if ok then
					found = result
				end
			end
			if found then
				entry.waitingIds[itemId] = nil
			else
				allReady = false
			end
		end
		local timedOut = entry.startedAt and (nowMs - entry.startedAt) > PENDING_CRAFT_TIMEOUT_MS
		if allReady or timedOut then
			table.remove(pendingCraftStarts, i)
			if timedOut and not allReady then
				GSSiK_Addon_Craft.Log.debug("Operations", "craftAttempt ABORT operationId=" .. tostring(entry.operationId)
					.. " waitResult=timeout actionStarted=false")
				failCraftOperation(entry.operationId, entry.self.player, "IGUI_GSSIK_CraftFailClaimTimeout")
				BatchState.clear(entry.self)
				return
			end
			GSSiK_Addon_Craft.Log.debug("Operations", string.format(
				"craftAttempt RESUME operationId=%s waitResult=%s actionStarted=true",
				tostring(entry.operationId), allReady and "allReady" or "timeout"))
			local okFreshItems, freshItems = pcall(function()
				return entry.self.logic and entry.self.logic:getRecipeData() and entry.self.logic:getRecipeData():getAllInputItems()
			end)
			local restore = narrowContainersForAction(entry.self, okFreshItems and freshItems or nil)
			activeOperationId = entry.operationId
			pcall(function() entry.self.logic:autoPopulateInputs() end)
			local okCanPerform, canPerform = pcall(function() return entry.self.logic:canPerformCurrentRecipe() end)
			if not entry.force and okCanPerform and canPerform == false then
				activeOperationId = nil
				restore()
				failCraftOperation(entry.operationId, entry.self.player, "IGUI_GSSIK_CraftFailInvalid")
				BatchState.clear(entry.self)
				return
			end
			-- pcall (2026-08-13, diagnostico): si originalStartHandcraft revienta
			-- al llamarlo DIFERIDO desde el tick (en vez de sincrono desde el
			-- clic original), antes se perdia en silencio - ningun END/RESULT,
			-- sin ninguna pista en el log de por que. Con esto queda registrado.
			-- Congelar la cantidad leída en el clic original. Vanilla la guarda
			-- en self.craftTimes al entrar en startHandcraft; como nosotros
			-- reanudamos varios ticks después, no debe volver a inferirse del
			-- estado mutable del entryBox.
			entry.self.craftTimes = entry.batchCount or 1
			local okCall, errCall = pcall(originalStartHandcraft, entry.self, entry.force)
			if not okCall then
				GSSiK_Addon_Craft.Log.debug("Operations", "craftAttempt RESUME operationId=" .. tostring(entry.operationId)
					.. " originalStartHandcraft ERROR: " .. tostring(errCall))
				failCraftOperation(entry.operationId, entry.self.player, "IGUI_GSSIK_CraftFailStart")
				BatchState.clear(entry.self)
			end
			activeOperationId = nil
			restore()
		end
	end
end

---@param self table ISWidgetHandCraftControl
---@param force boolean|nil
local function patchedStartHandcraft(self, force)
	local sess = activeSession()
	if sess and self.logic and self.logic.getRecipeData then
		local okRecipeData, recipeData = pcall(function() return self.logic:getRecipeData() end)
		if okRecipeData and recipeData and recipeData.getAllInputItems then
			local okItems, items = pcall(function() return recipeData:getAllInputItems() end)
			local recipeName = "?"
			local okName, name = pcall(function() return self.logic:getRecipe() and self.logic:getRecipe():getName() end)
			if okName and name then
				recipeName = name
			end
			local floorOk = false
			local okFloor, floorVal = pcall(function() return self.logic:getRecipe():isCanBeDoneFromFloor() end)
			if okFloor and floorVal == true then
				floorOk = true
			end
			local containersCount = 0
			local okCon, containers = pcall(function() return self.logic:getContainers() end)
			if okCon and containers and containers.size then
				containersCount = containers:size()
			end
			local batchCount = readVanillaBatchCount(self)
			local operationOk, operationCode, operation = Session.startOperation({
				addonId = ADDON_ID, player = self.player, kind = "handcraft",
				recipeName = recipeName, batchCount = batchCount,
				canUseFloor = floorOk, containerCount = containersCount,
				diagnostics = true,
			})
			if operationOk ~= true or not operation then
				GSSiK_Addon_Craft.Log.debug("Operations",
					"craftAttempt rejected code=" .. tostring(operationCode))
				return originalStartHandcraft(self, force)
			end
			local operationId = operation.operationId
			self._gsOperationId = operationId
			BatchState.begin(self, operationId, batchCount)
			if okItems and items and items.size then
				local waitingIds, waitingCount, moved, batchShortfall, batchContractSupported = claimNetworkCraftItems(
					self.player, self.logic, items, operationId, batchCount)
				GSSiK_Addon_Craft.Log.debug("Operations", string.format(
					"craftAttempt START operationId=%s addonId=%s recipe=%s networkId=%s isCanBeDoneFromFloor=%s inputs=%d movidosDeRed=%d batchCount=%d containersCliente=%d",
					operationId, ADDON_ID, recipeName, tostring(sess.networkId),
					tostring(floorOk), items:size(), moved, batchCount, containersCount))
				if batchShortfall > 0 then
					GSSiK_Addon_Craft.Log.debug("Operations", "craftAttempt ABORT operationId=" .. operationId
						.. " batchShortfall=" .. tostring(batchShortfall))
					failCraftOperation(operationId, self.player, batchContractSupported
						and "IGUI_GSSIK_CraftFailBatchMaterials" or "IGUI_GSSIK_CraftFailCoreUpdate")
					BatchState.clear(self)
					return
				end
				if waitingCount > 0 then
					table.insert(pendingCraftStarts, {
						self = self,
						force = force,
						waitingIds = waitingIds,
						startedAt = getTimestampMs and getTimestampMs() or 0,
						operationId = operationId,
						batchCount = batchCount,
					})
					GSSiK_Addon_Craft.Log.debug("Operations", "craftAttempt WAIT operationId=" .. operationId .. " (esperando confirmacion del servidor)")
					return
				end
			end
			local restore = narrowContainersForAction(self, okItems and items or nil)
			local invBefore = "?"
			local okInv, invSize = pcall(function() return self.player:getInventory():getItems():size() end)
			if okInv then invBefore = tostring(invSize) end
			GSSiK_Addon_Craft.Log.debug("Operations", "craftAttempt invBefore=" .. invBefore .. " operationId=" .. operationId)
			activeOperationId = operationId
			pcall(function() self.logic:autoPopulateInputs() end)
			local okCanPerform, canPerform = pcall(function() return self.logic:canPerformCurrentRecipe() end)
			if not force and okCanPerform and canPerform == false then
				activeOperationId = nil
				restore()
				failCraftOperation(operationId, self.player, "IGUI_GSSIK_CraftFailInvalid")
				BatchState.clear(self)
				return
			end
			self.craftTimes = batchCount or 1
			local okCall, errCall = pcall(originalStartHandcraft, self, force)
			activeOperationId = nil
			restore()
			if not okCall then
				GSSiK_Addon_Craft.Log.debug("Operations", "craftAttempt START ERROR operationId=" .. tostring(operationId)
					.. " error=" .. tostring(errCall))
				failCraftOperation(operationId, self.player, "IGUI_GSSIK_CraftFailStart")
				BatchState.clear(self)
			end
			return
		end
	end
	return originalStartHandcraft(self, force)
end

--- Red de seguridad: intercepta el paso que en vanilla camina hasta el
--- contenedor de un ingrediente que no está ya en el inventario (solo se
--- llega aqui para recetas isCanBeDoneFromFloor()==false, ya gestionadas por
--- patchedStartHandcraft - esto cubre el caso de un ítem que no pase por
--- getAllInputItems(), ej. recipeAtHandItem). Igual que patchedStartHandcraft:
--- mueve el ítem al inventario en vez de dejar que el personaje camine
--- (rechazado explícitamente). El guardián de itemId ya reclamado (Core)
--- evita reclamar dos veces el mismo ítem si patchedStartHandcraft ya lo movió.
---@param playerObj IsoPlayer
---@param item InventoryItem|userdata
---@param preventTransferWorldObjects boolean|nil
local function patchedTransferIfNeeded(playerObj, item, preventTransferWorldObjects)
	local sess = activeSession()
	if sess and instanceof then
		local okType, isItem = pcall(instanceof, item, "InventoryItem")
		if okType and isItem then
			local container = item.getContainer and item:getContainer()
			if container and activeOperationId then
				local claimOk, _, claimed = Session.claimItem(activeOperationId,
					playerObj, item, container)
				if claimOk and claimed then
					return
				end
				-- Sin espacio/peso real: dejamos que vanilla haga lo suyo
				-- (caminar) en vez de bloquear el crafteo por completo - caso
				-- raro (inventario lleno), mejor que un crafteo imposible.
			end
		end
	end
	return originalTransferIfNeeded(playerObj, item, preventTransferWorldObjects)
end

--- Diagnostico: confirma en CLIENTE si la accion de crafteo llega a
--- completarse o se cancela de verdad - ISWidgetHandCraftControl:
--- onHandcraftActionComplete/onHandcraftActionCancelled (codigo base del
--- juego) son los callbacks que vanilla dispara el mismo al terminar/cancelar
--- la ISHandcraftAction (ver ISHandcraftAction:perform/stop). Sin esto no
--- habia forma de saber, solo mirando el log, si la accion llegaba a
--- completarse (barra llena) o se cancelaba antes (ítem perdido/fuera de
--- rango) - ninguno de los dos casos deja rastro propio en el log del juego.
---
--- Vanilla ejecuta `setCraftQuantity()` tras CADA unidad pendiente. Ese
--- metodo llama `sanitizeCraftQuantity()` -> `getPossibleCraftCount(false)` y
--- vuelve a poblar el HandcraftLogic con todos los contenedores visibles en
--- la UI. Con una sesion GS activa eso reintroduce los contenedores virtuales
--- entre acciones ya encoladas: la ultima accion puede completar su callback
--- sin fabricar nada (confirmado en DEV5: lote 3 consumio solo 2 mangos + 6
--- clavos y el servidor vio containers=30/resultCreated=false). Neat ya evita
--- deliberadamente este refresco por unidad. En Vanilla conservamos su
--- stopCraftAction y decremento de craftTimes, pero aplazamos exclusivamente
--- setCraftQuantity hasta que finalice el lote.
---@param self table ISWidgetHandCraftControl
---@param suppressQuantityRefresh boolean
---@return any
local function callVanillaComplete(self, suppressQuantityRefresh)
	if not suppressQuantityRefresh or not self or type(self.setCraftQuantity) ~= "function" then
		return originalOnHandcraftActionComplete(self)
	end
	local previousOverride = rawget(self, "setCraftQuantity")
	self.setCraftQuantity = function() end
	local ok, result = pcall(originalOnHandcraftActionComplete, self)
	self.setCraftQuantity = previousOverride
	if not ok then
		error(result)
	end
	return result
end

---@param self table ISWidgetHandCraftControl
local function patchedOnHandcraftActionComplete(self)
	local operationId, completed, expected, final = BatchState.completeUnit(self)
	if operationId and activeSession() then
		local recipeName = "?"
		local ok, name = pcall(function() return self.logic and self.logic:getRecipe() and self.logic:getRecipe():getName() end)
		if ok and name then recipeName = name end
		local invAfter = "?"
		local okInv, invSize = pcall(function() return self.player:getInventory():getItems():size() end)
		if okInv then invAfter = tostring(invSize) end
		if final then
			GSSiK_Addon_Craft.Log.debug("Operations", string.format(
				"craftAttempt END operationId=%s recipe=%s units=%d/%d actionCompleted=true actionCancelled=false invAfter=%s",
				tostring(operationId), recipeName, completed, expected, invAfter))
		else
			GSSiK_Addon_Craft.Log.debug("Operations", string.format(
				"craftAttempt PROGRESS operationId=%s recipe=%s units=%d/%d",
				tostring(operationId), recipeName, completed, expected))
		end
	end
	-- Los tres paneles notifican por unidad. Core solo debe conocer el fin del
	-- lote completo; de otro modo devuelve herramientas/materiales tras la
	-- primera unidad mientras las acciones siguientes siguen en cola.
	local result = callVanillaComplete(self, expected > 1 and not final)
	if final then
		-- Los callbacks intermedios no tocaron el entryBox ni recalcularon el
		-- logic. Ahora que no queda ninguna accion, restaurar una sola vez el
		-- estado visual vanilla sin poder contaminar otra receta encolada.
		if expected > 1 and self and type(self.setCraftQuantity) == "function" then
			self:setCraftQuantity(1)
		end
		Session.completeOperation(operationId, self.player)
	end
	return result
end

---@param self table ISWidgetHandCraftControl
local function patchedOnHandcraftActionCancelled(self)
	local operationId, completed, expected = BatchState.cancel(self)
	if operationId and activeSession() then
		local recipeName = "?"
		local ok, name = pcall(function() return self.logic and self.logic:getRecipe() and self.logic:getRecipe():getName() end)
		if ok and name then recipeName = name end
		GSSiK_Addon_Craft.Log.debug("Operations", string.format(
			"craftAttempt END operationId=%s recipe=%s units=%d/%d actionCompleted=false actionCancelled=true",
			tostring(operationId), recipeName, completed, expected))
	end
	if operationId then
		failCraftOperation(operationId, self.player, "IGUI_GSSIK_CraftFailCancelled")
	end
	return originalOnHandcraftActionCancelled(self)
end

--- Soporte para Neat Crafting (mod externo opcional, workshop "Neat_Crafting")
--- - cuando ese mod esta activo, el addon abre SU PROPIA ventana (clase
--- NC_CraftActionPanel, ver Neat_Crafting/.../NC_CraftActionPanel.lua), NO
--- ISWidgetHandCraftControl - ninguno de los hooks de arriba se disparaba
--- nunca en modo "neat" (confirmado: operationId=? en los logs, sin
--- craftAttempt START). NC_CraftActionPanel tiene la MISMA forma (self.logic,
--- self.player) y el mismo metodo startHandcraft(force, craftTimes) - aqui
--- craftTimes ya llega como argumento explicito (Neat lo calcula el mismo en
--- onCraftButtonClick antes de llamar), no hay que leerlo de un entryBox
--- como en vanilla.
local pendingNeatCraftStarts = {}

---@param self table NC_CraftActionPanel
---@param force boolean|nil
---@param craftTimes number|nil
local function patchedNeatStartHandcraft(self, force, craftTimes)
	local sess = activeSession()
	if sess and self.logic and self.logic.getRecipeData then
		local okRecipeData, recipeData = pcall(function() return self.logic:getRecipeData() end)
		if okRecipeData and recipeData and recipeData.getAllInputItems then
			local okItems, items = pcall(function() return recipeData:getAllInputItems() end)
			local recipeName = "?"
			local okName, name = pcall(function() return self.logic:getRecipe() and self.logic:getRecipe():getName() end)
			if okName and name then recipeName = name end
			local floorOk = false
			local okFloor, floorVal = pcall(function() return self.logic:getRecipe():isCanBeDoneFromFloor() end)
			if okFloor and floorVal == true then floorOk = true end
			local containersCount = 0
			local okCon, containers = pcall(function() return self.logic:getContainers() end)
			if okCon and containers and containers.size then containersCount = containers:size() end
			local batchCount = tonumber(craftTimes) or 1
			local operationOk, operationCode, operation = Session.startOperation({
				addonId = ADDON_ID, player = self.player, kind = "neat_handcraft",
				recipeName = recipeName, batchCount = batchCount,
				canUseFloor = floorOk, containerCount = containersCount,
				diagnostics = true,
			})
			if operationOk ~= true or not operation then
				GSSiK_Addon_Craft.Log.debug("Operations",
					"craftAttempt(neat) rejected code=" .. tostring(operationCode))
				return originalNeatStartHandcraft(self, force, craftTimes)
			end
			local operationId = operation.operationId
			self._gsOperationId = operationId
			if okItems and items and items.size then
				BatchState.begin(self, operationId, batchCount)
				local waitingIds, waitingCount, moved, batchShortfall, batchContractSupported = claimNetworkCraftItems(
					self.player, self.logic, items, operationId, batchCount)
				GSSiK_Addon_Craft.Log.debug("Operations", string.format(
					"craftAttempt(neat) START operationId=%s addonId=%s recipe=%s networkId=%s isCanBeDoneFromFloor=%s inputs=%d movidosDeRed=%d batchCount=%d containersCliente=%d",
					operationId, ADDON_ID, recipeName, tostring(sess.networkId),
					tostring(floorOk), items:size(), moved, batchCount, containersCount))
				if batchShortfall > 0 then
					GSSiK_Addon_Craft.Log.debug("Operations", "craftAttempt(neat) ABORT operationId=" .. operationId
						.. " batchShortfall=" .. tostring(batchShortfall))
					failCraftOperation(operationId, self.player, batchContractSupported
						and "IGUI_GSSIK_CraftFailBatchMaterials" or "IGUI_GSSIK_CraftFailCoreUpdate")
					BatchState.clear(self)
					return
				end
				if waitingCount > 0 then
					table.insert(pendingNeatCraftStarts, {
						self = self, force = force, craftTimes = craftTimes,
						waitingIds = waitingIds,
						startedAt = getTimestampMs and getTimestampMs() or 0,
						operationId = operationId,
					})
					GSSiK_Addon_Craft.Log.debug("Operations", "craftAttempt(neat) WAIT operationId=" .. operationId .. " (esperando confirmacion del servidor)")
					return
				end
			end
			local restore = narrowContainersForAction(self, okItems and items or nil)
			local invBefore = "?"
			local okInv, invSize = pcall(function() return self.player:getInventory():getItems():size() end)
			if okInv then invBefore = tostring(invSize) end
			GSSiK_Addon_Craft.Log.debug("Operations", "craftAttempt(neat) invBefore=" .. invBefore .. " operationId=" .. operationId)
			activeOperationId = operationId
			pcall(function() self.logic:autoPopulateInputs() end)
			local okCanPerform, canPerform = pcall(function() return self.logic:canPerformCurrentRecipe() end)
			if not force and okCanPerform and canPerform == false then
				activeOperationId = nil
				restore()
				failCraftOperation(operationId, self.player, "IGUI_GSSIK_CraftFailInvalid")
				BatchState.clear(self)
				return
			end
			local okCall, errCall = pcall(originalNeatStartHandcraft, self, force, craftTimes)
			activeOperationId = nil
			restore()
			if not okCall then
				GSSiK_Addon_Craft.Log.debug("Operations", "craftAttempt(neat) START ERROR operationId=" .. tostring(operationId)
					.. " error=" .. tostring(errCall))
				failCraftOperation(operationId, self.player, "IGUI_GSSIK_CraftFailStart")
				BatchState.clear(self)
			end
			return
		end
	end
	return originalNeatStartHandcraft(self, force, craftTimes)
end

--- Reanudacion equivalente a checkPendingCraftStarts, cola aparte porque el
--- punto de reanudacion es distinto (originalNeatStartHandcraft, con 3
--- argumentos, no 2).
local function checkPendingNeatCraftStarts()
	if #pendingNeatCraftStarts == 0 then
		return
	end
	local nowMs = getTimestampMs and getTimestampMs() or 0
	for i = #pendingNeatCraftStarts, 1, -1 do
		local entry = pendingNeatCraftStarts[i]
		local inv = entry.self.player and entry.self.player.getInventory and entry.self.player:getInventory()
		local allReady = true
		for itemId in pairs(entry.waitingIds) do
			local found = nil
			if inv and inv.getItemWithID then
				local ok, result = pcall(function() return inv:getItemWithID(itemId) end)
				if ok then found = result end
			end
			if found then
				entry.waitingIds[itemId] = nil
			else
				allReady = false
			end
		end
		local timedOut = entry.startedAt and (nowMs - entry.startedAt) > PENDING_CRAFT_TIMEOUT_MS
		if allReady or timedOut then
			table.remove(pendingNeatCraftStarts, i)
			if timedOut and not allReady then
				GSSiK_Addon_Craft.Log.debug("Operations", "craftAttempt(neat) ABORT operationId=" .. tostring(entry.operationId)
					.. " waitResult=timeout actionStarted=false")
				failCraftOperation(entry.operationId, entry.self.player, "IGUI_GSSIK_CraftFailClaimTimeout")
				BatchState.clear(entry.self)
				return
			end
			GSSiK_Addon_Craft.Log.debug("Operations", string.format(
				"craftAttempt(neat) RESUME operationId=%s waitResult=%s actionStarted=true",
				tostring(entry.operationId), allReady and "allReady" or "timeout"))
			local okFreshItems, freshItems = pcall(function()
				return entry.self.logic and entry.self.logic:getRecipeData() and entry.self.logic:getRecipeData():getAllInputItems()
			end)
			local restore = narrowContainersForAction(entry.self, okFreshItems and freshItems or nil)
			activeOperationId = entry.operationId
			-- CONFIRMADO CON DATOS REALES (2026-08-16): isCraftActionInProgress
			-- es SIEMPRE false aqui (hipotesis inicial descartada) - el guardia
			-- real es canPerformCurrentRecipe(), tambien false, porque
			-- HandcraftLogic cachea si la receta es realizable a partir del
			-- estado de ANTES de que los items de red llegaran al inventario
			-- (el round-trip al servidor). Nada en el flujo normal le pide que
			-- recalcule ese cache tras el claim - por eso originalNeatStartHandcraft
			-- no hacia nada, ni error ni accion. autoPopulateInputs() es la
			-- funcion que el propio Project_Cook llama tras cada crafteo
			-- (PJCK_CraftActionPanel:onHandcraftActionComplete) precisamente
			-- para refrescar ese cache - forzarla aqui, justo antes de
			-- reanudar, deberia dejar canPerformCurrentRecipe() en true.
			pcall(function() entry.self.logic:autoPopulateInputs() end)
			local okCanPerform, canPerform = pcall(function() return entry.self.logic and entry.self.logic:canPerformCurrentRecipe() end)
			GSSiK_Addon_Craft.Log.debug("Operations", string.format(
				"craftAttempt(neat) RESUME operationId=%s tras autoPopulateInputs canPerformCurrentRecipe=%s",
				tostring(entry.operationId), tostring(okCanPerform and canPerform)))
			if not entry.force and okCanPerform and canPerform == false then
				activeOperationId = nil
				restore()
				failCraftOperation(entry.operationId, entry.self.player, "IGUI_GSSIK_CraftFailInvalid")
				BatchState.clear(entry.self)
				return
			end
			local okCall, errCall = pcall(originalNeatStartHandcraft, entry.self, entry.force, entry.craftTimes)
			if not okCall then
				GSSiK_Addon_Craft.Log.debug("Operations", "craftAttempt(neat) RESUME operationId=" .. tostring(entry.operationId)
					.. " originalNeatStartHandcraft ERROR: " .. tostring(errCall))
				failCraftOperation(entry.operationId, entry.self.player, "IGUI_GSSIK_CraftFailStart")
				BatchState.clear(entry.self)
			end
			activeOperationId = nil
			restore()
		end
	end
end

---@param self table NC_CraftActionPanel
local function patchedNeatOnHandcraftActionComplete(self)
	local operationId, completed, expected, final = BatchState.completeUnit(self)
	if operationId and activeSession() then
		local recipeName = "?"
		local ok, name = pcall(function() return self.logic and self.logic:getRecipe() and self.logic:getRecipe():getName() end)
		if ok and name then recipeName = name end
		local invAfter = "?"
		local okInv, invSize = pcall(function() return self.player:getInventory():getItems():size() end)
		if okInv then invAfter = tostring(invSize) end
		if final then
			GSSiK_Addon_Craft.Log.debug("Operations", string.format(
				"craftAttempt(neat) END operationId=%s recipe=%s units=%d/%d actionCompleted=true actionCancelled=false invAfter=%s",
				tostring(operationId), recipeName, completed, expected, invAfter))
		else
			GSSiK_Addon_Craft.Log.debug("Operations", string.format(
				"craftAttempt(neat) PROGRESS operationId=%s recipe=%s units=%d/%d",
				tostring(operationId), recipeName, completed, expected))
		end
	end
	if final then
		Session.completeOperation(operationId, self.player)
	end
	return originalNeatOnHandcraftActionComplete(self)
end

---@param self table NC_CraftActionPanel
local function patchedNeatOnHandcraftActionCancelled(self)
	local operationId, completed, expected = BatchState.cancel(self)
	if operationId and activeSession() then
		local recipeName = "?"
		local ok, name = pcall(function() return self.logic and self.logic:getRecipe() and self.logic:getRecipe():getName() end)
		if ok and name then recipeName = name end
		GSSiK_Addon_Craft.Log.debug("Operations", string.format(
			"craftAttempt(neat) END operationId=%s recipe=%s units=%d/%d actionCompleted=false actionCancelled=true",
			tostring(operationId), recipeName, completed, expected))
	end
	if operationId then
		failCraftOperation(operationId, self.player, "IGUI_GSSIK_CraftFailCancelled")
	end
	return originalNeatOnHandcraftActionCancelled(self)
end

--- Instala/restaura los hooks de este addon - registrado en Core via
--- WorkSession.registerLifecycle, llamado al arrancar/terminar CUALQUIER
--- sesion (Core no distingue, cada addon comprueba WorkSession.get(ADDON_ID)
--- dentro de su propio hook antes de actuar).
local function installCraftHooks()
	if ISInventoryPaneContextMenu and ISInventoryPaneContextMenu.transferIfNeeded then
		originalTransferIfNeeded = ISInventoryPaneContextMenu.transferIfNeeded
		ISInventoryPaneContextMenu.transferIfNeeded = patchedTransferIfNeeded
	end
	if ISWidgetHandCraftControl and ISWidgetHandCraftControl.startHandcraft then
		originalStartHandcraft = ISWidgetHandCraftControl.startHandcraft
		ISWidgetHandCraftControl.startHandcraft = patchedStartHandcraft
	end
	if ISWidgetHandCraftControl and ISWidgetHandCraftControl.onHandcraftActionComplete then
		originalOnHandcraftActionComplete = ISWidgetHandCraftControl.onHandcraftActionComplete
		ISWidgetHandCraftControl.onHandcraftActionComplete = patchedOnHandcraftActionComplete
	end
	if ISWidgetHandCraftControl and ISWidgetHandCraftControl.onHandcraftActionCancelled then
		originalOnHandcraftActionCancelled = ISWidgetHandCraftControl.onHandcraftActionCancelled
		ISWidgetHandCraftControl.onHandcraftActionCancelled = patchedOnHandcraftActionCancelled
	end
	-- Neat Crafting (mod externo, opcional) - NC_CraftActionPanel solo existe
	-- como global si ese mod esta activo.
	if NC_CraftActionPanel and NC_CraftActionPanel.startHandcraft then
		originalNeatStartHandcraft = NC_CraftActionPanel.startHandcraft
		NC_CraftActionPanel.startHandcraft = patchedNeatStartHandcraft
	end
	if NC_CraftActionPanel and NC_CraftActionPanel.onHandcraftActionComplete then
		originalNeatOnHandcraftActionComplete = NC_CraftActionPanel.onHandcraftActionComplete
		NC_CraftActionPanel.onHandcraftActionComplete = patchedNeatOnHandcraftActionComplete
	end
	if NC_CraftActionPanel and NC_CraftActionPanel.onHandcraftActionCancelled then
		originalNeatOnHandcraftActionCancelled = NC_CraftActionPanel.onHandcraftActionCancelled
		NC_CraftActionPanel.onHandcraftActionCancelled = patchedNeatOnHandcraftActionCancelled
	end
	-- Project Cook (mod externo, opcional) - ver GSSiK_Addon_Craft_NetworkCook.lua.
	-- Se instala/desinstala siempre junto con el resto: una unica sesion
	-- "Craft" cubre vanilla + Neat + Cook a la vez.
	GSSiK_Addon_Craft_NetworkCook.install()
end

local function uninstallCraftHooks()
	if originalTransferIfNeeded then
		ISInventoryPaneContextMenu.transferIfNeeded = originalTransferIfNeeded
	end
	if originalStartHandcraft then
		ISWidgetHandCraftControl.startHandcraft = originalStartHandcraft
	end
	if originalOnHandcraftActionComplete then
		ISWidgetHandCraftControl.onHandcraftActionComplete = originalOnHandcraftActionComplete
	end
	if originalOnHandcraftActionCancelled then
		ISWidgetHandCraftControl.onHandcraftActionCancelled = originalOnHandcraftActionCancelled
	end
	if originalNeatStartHandcraft then
		NC_CraftActionPanel.startHandcraft = originalNeatStartHandcraft
	end
	if originalNeatOnHandcraftActionComplete then
		NC_CraftActionPanel.onHandcraftActionComplete = originalNeatOnHandcraftActionComplete
	end
	if originalNeatOnHandcraftActionCancelled then
		NC_CraftActionPanel.onHandcraftActionCancelled = originalNeatOnHandcraftActionCancelled
	end
	GSSiK_Addon_Craft_NetworkCook.uninstall()
end

--- Manejador de tick registrado en Core - resuelve esperas de reclamo tanto
--- para la ventana vanilla como para Neat.
local function craftTickHandler()
	checkPendingCraftStarts()
	checkPendingNeatCraftStarts()
	GSSiK_Addon_Craft_NetworkCook.tick()
end

local lifecycleOk, lifecycleCode, lifecycleRegistration = Session.registerLifecycle(ADDON_ID, {
        install = installCraftHooks,
        uninstall = uninstallCraftHooks,
        tick = craftTickHandler,
})
if lifecycleOk ~= true then
        error("GSSiK.API WorkSession lifecycle: " .. tostring(lifecycleCode))
end
GSSiK_Addon_Craft._workLifecycleRegistration = lifecycleRegistration
