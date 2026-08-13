--[[
	GSSiK Addon Craft - Crafteo remoto (vanilla + Neat Crafting)
	Autor: SiK
	Fecha: 2026-08-13 (migrado desde GS_NetworkCraftSession.lua del Core -
	pedido explícito: Core no debería conocer ISWidgetHandCraftControl ni
	NC_CraftActionPanel, eso es conocimiento exclusivo de este addon; el
	Core solo expone infraestructura genérica de sesión/préstamo vía
	GlobalStorageSiK.CraftSession).
	Descripción: Intercepta el arranque de crafteo (vanilla y Neat Crafting,
	si está instalado) mientras hay una sesión GlobalStorageSiK.CraftSession
	activa para este addon ("Craft"): mueve al inventario del jugador los
	ingredientes/herramientas que estén en un contenedor de red (confirmado
	con datos reales que HandcraftLogic.performCurrentRecipe() en servidor no
	puede consumir directamente de contenedores inyectados por el mod, ni
	siquiera 1 solo - ver comentarios abajo), recorta la lista de
	contenedores que ve la acción real a solo contenedores 100% vanilla, deja
	craftear, y devuelve sobrantes/herramientas a la red por prioridad al
	terminar.
]]

require "GS_NetworkCraftSession"
require "GSSiK_Addon_Craft_Log"

local ADDON_ID = "Craft"

GlobalStorageSiK.CraftSession.registerDebugSink(ADDON_ID, function(message)
	GSSiK_Addon_Craft.Log.debug(message)
end)

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
	local okFull, fullList = pcall(function() return self.logic:getContainers() end)
	if not okFull or not fullList or not fullList.size then
		return function() end
	end
	local sess = GlobalStorageSiK.CraftSession.getActiveSession(ADDON_ID)
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
	local okSet = pcall(function() self.logic:setContainers(GlobalStorageSiK.CraftSession.tableToArrayList(narrowed)) end)
	GlobalStorageSiK.CraftSession.debugLog(string.format("containersNarrow original=%d narrowed=%d aplicado=%s",
		fullList:size(), #narrowed, tostring(okSet)))
	return function()
		pcall(function() self.logic:setContainers(fullList) end)
	end
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
---@return table waitingIds, number waitingCount, number moved
local function claimNetworkCraftItems(player, logic, items, networkId, operationId, batchCount)
	local waitingIds = {}
	local waitingCount = 0
	local moved = 0
	local authoritative = GlobalStorageSiK.isAuthoritative()
	local movedFullTypes = {}
	local movedFullTypeCount = 0

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
				local container = item.getContainer and item:getContainer()
				if container and GlobalStorageSiK.CraftSession.isNetworkContainer(container, networkId) then
					local fullType = item.getFullType and item:getFullType() or nil
					if claim(item, container) and fullType then
						if not movedFullTypes[fullType] then
							movedFullTypeCount = movedFullTypeCount + 1
						end
						movedFullTypes[fullType] = (movedFullTypes[fullType] or 0) + 1
					end
				end
			end
		end
	end

	-- NUNCA next() aqui (Kahlua no lo soporta de forma fiable) - se usa el
	-- contador propio movedFullTypeCount en vez de next(movedFullTypes) ~= nil
	-- para saber si hay algo que escanear.
	if batchCount and batchCount > 1 and movedFullTypeCount > 0 then
		local okCon, containers = pcall(function() return logic:getContainers() end)
		if okCon and containers and containers.size then
			for fullType, haveCount in pairs(movedFullTypes) do
				local need = batchCount - haveCount
				local c = 0
				while need > 0 and c < containers:size() do
					local container = containers:get(c)
					c = c + 1
					if container and GlobalStorageSiK.CraftSession.isNetworkContainer(container, networkId) then
						local okItems2, itemsInC = pcall(function() return container:getItems() end)
						if okItems2 and itemsInC and itemsInC.size then
							local j = 0
							while need > 0 and j < itemsInC:size() do
								local extraItem = itemsInC:get(j)
								j = j + 1
								if extraItem and extraItem.getFullType and extraItem:getFullType() == fullType
									and not (extraItem.getID and GlobalStorageSiK.CraftSession.isItemClaimed(extraItem:getID())) then
									if claim(extraItem, container) then
										need = need - 1
									end
								end
							end
						end
					end
				end
			end
		end
	end

	return waitingIds, waitingCount, moved
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
			GlobalStorageSiK.CraftSession.debugLog(string.format(
				"craftAttempt RESUME operationId=%s waitResult=%s actionStarted=true",
				tostring(entry.operationId), allReady and "allReady" or "timeout"))
			local okFreshItems, freshItems = pcall(function()
				return entry.self.logic and entry.self.logic:getRecipeData() and entry.self.logic:getRecipeData():getAllInputItems()
			end)
			local restore = narrowContainersForAction(entry.self, okFreshItems and freshItems or nil)
			activeOperationId = entry.operationId
			originalStartHandcraft(entry.self, entry.force)
			activeOperationId = nil
			restore()
		end
	end
end

---@param self table ISWidgetHandCraftControl
---@param force boolean|nil
local function patchedStartHandcraft(self, force)
	local sess = GlobalStorageSiK.CraftSession.getActiveSession(ADDON_ID)
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
			local operationId = GlobalStorageSiK.CraftSession.newOperationId(ADDON_ID)
			self._gsOperationId = operationId
			-- "craftAttemptStart" es solo para diagnostico (log estructurado
			-- correlacionable via operationId en el servidor) - no cambia
			-- ningun comportamiento de juego, ver GS_Server.lua.
			if GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.sendCommand then
				GlobalStorageSiK.NetClient.sendCommand("craftAttemptStart", {
					operationId = operationId, addonId = ADDON_ID, recipe = recipeName,
					networkId = sess.networkId, isCanBeDoneFromFloor = floorOk,
					containersCliente = containersCount,
				})
			end
			if okItems and items and items.size then
				local batchCount = readVanillaBatchCount(self)
				local waitingIds, waitingCount, moved = claimNetworkCraftItems(
					self.player, self.logic, items, sess.networkId, operationId, batchCount)
				GlobalStorageSiK.CraftSession.debugLog(string.format(
					"craftAttempt START operationId=%s addonId=%s recipe=%s networkId=%s isCanBeDoneFromFloor=%s inputs=%d movidosDeRed=%d batchCount=%d containersCliente=%d",
					operationId, ADDON_ID, recipeName, tostring(sess.networkId),
					tostring(floorOk), items:size(), moved, batchCount, containersCount))
				if waitingCount > 0 then
					table.insert(pendingCraftStarts, {
						self = self,
						force = force,
						waitingIds = waitingIds,
						startedAt = getTimestampMs and getTimestampMs() or 0,
						operationId = operationId,
					})
					GlobalStorageSiK.CraftSession.debugLog("craftAttempt WAIT operationId=" .. operationId .. " (esperando confirmacion del servidor)")
					return
				end
			end
			local restore = narrowContainersForAction(self, okItems and items or nil)
			local invBefore = "?"
			local okInv, invSize = pcall(function() return self.player:getInventory():getItems():size() end)
			if okInv then invBefore = tostring(invSize) end
			GlobalStorageSiK.CraftSession.debugLog("craftAttempt invBefore=" .. invBefore .. " operationId=" .. operationId)
			activeOperationId = operationId
			originalStartHandcraft(self, force)
			activeOperationId = nil
			restore()
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
	local sess = GlobalStorageSiK.CraftSession.getActiveSession(ADDON_ID)
	if sess and instanceof then
		local okType, isItem = pcall(instanceof, item, "InventoryItem")
		if okType and isItem then
			local container = item.getContainer and item:getContainer()
			if container and GlobalStorageSiK.CraftSession.isNetworkContainer(container, sess.networkId) then
				if GlobalStorageSiK.CraftSession.claimNetworkItem(playerObj, item, container, sess.networkId, activeOperationId) then
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
---@param self table ISWidgetHandCraftControl
local function patchedOnHandcraftActionComplete(self)
	if GlobalStorageSiK.CraftSession.getActiveSession(ADDON_ID) then
		local recipeName = "?"
		local ok, name = pcall(function() return self.logic and self.logic:getRecipe() and self.logic:getRecipe():getName() end)
		if ok and name then recipeName = name end
		local invAfter = "?"
		local okInv, invSize = pcall(function() return self.player:getInventory():getItems():size() end)
		if okInv then invAfter = tostring(invSize) end
		GlobalStorageSiK.CraftSession.debugLog(string.format(
			"craftAttempt END operationId=%s recipe=%s actionCompleted=true actionCancelled=false invAfter=%s",
			tostring(self._gsOperationId), recipeName, invAfter))
	end
	return originalOnHandcraftActionComplete(self)
end

---@param self table ISWidgetHandCraftControl
local function patchedOnHandcraftActionCancelled(self)
	if GlobalStorageSiK.CraftSession.getActiveSession(ADDON_ID) then
		local recipeName = "?"
		local ok, name = pcall(function() return self.logic and self.logic:getRecipe() and self.logic:getRecipe():getName() end)
		if ok and name then recipeName = name end
		GlobalStorageSiK.CraftSession.debugLog(string.format(
			"craftAttempt END operationId=%s recipe=%s actionCompleted=false actionCancelled=true",
			tostring(self._gsOperationId), recipeName))
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
	local sess = GlobalStorageSiK.CraftSession.getActiveSession(ADDON_ID)
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
			local operationId = GlobalStorageSiK.CraftSession.newOperationId(ADDON_ID)
			self._gsOperationId = operationId
			if GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.sendCommand then
				GlobalStorageSiK.NetClient.sendCommand("craftAttemptStart", {
					operationId = operationId, addonId = ADDON_ID, recipe = recipeName,
					networkId = sess.networkId, isCanBeDoneFromFloor = floorOk,
					containersCliente = containersCount,
				})
			end
			if okItems and items and items.size then
				local batchCount = tonumber(craftTimes) or 1
				local waitingIds, waitingCount, moved = claimNetworkCraftItems(
					self.player, self.logic, items, sess.networkId, operationId, batchCount)
				GlobalStorageSiK.CraftSession.debugLog(string.format(
					"craftAttempt(neat) START operationId=%s addonId=%s recipe=%s networkId=%s isCanBeDoneFromFloor=%s inputs=%d movidosDeRed=%d batchCount=%d containersCliente=%d",
					operationId, ADDON_ID, recipeName, tostring(sess.networkId),
					tostring(floorOk), items:size(), moved, batchCount, containersCount))
				if waitingCount > 0 then
					table.insert(pendingNeatCraftStarts, {
						self = self, force = force, craftTimes = craftTimes,
						waitingIds = waitingIds,
						startedAt = getTimestampMs and getTimestampMs() or 0,
						operationId = operationId,
					})
					GlobalStorageSiK.CraftSession.debugLog("craftAttempt(neat) WAIT operationId=" .. operationId .. " (esperando confirmacion del servidor)")
					return
				end
			end
			local restore = narrowContainersForAction(self, okItems and items or nil)
			local invBefore = "?"
			local okInv, invSize = pcall(function() return self.player:getInventory():getItems():size() end)
			if okInv then invBefore = tostring(invSize) end
			GlobalStorageSiK.CraftSession.debugLog("craftAttempt(neat) invBefore=" .. invBefore .. " operationId=" .. operationId)
			activeOperationId = operationId
			originalNeatStartHandcraft(self, force, craftTimes)
			activeOperationId = nil
			restore()
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
			GlobalStorageSiK.CraftSession.debugLog(string.format(
				"craftAttempt(neat) RESUME operationId=%s waitResult=%s actionStarted=true",
				tostring(entry.operationId), allReady and "allReady" or "timeout"))
			local okFreshItems, freshItems = pcall(function()
				return entry.self.logic and entry.self.logic:getRecipeData() and entry.self.logic:getRecipeData():getAllInputItems()
			end)
			local restore = narrowContainersForAction(entry.self, okFreshItems and freshItems or nil)
			activeOperationId = entry.operationId
			originalNeatStartHandcraft(entry.self, entry.force, entry.craftTimes)
			activeOperationId = nil
			restore()
		end
	end
end

---@param self table NC_CraftActionPanel
local function patchedNeatOnHandcraftActionComplete(self)
	if GlobalStorageSiK.CraftSession.getActiveSession(ADDON_ID) then
		local recipeName = "?"
		local ok, name = pcall(function() return self.logic and self.logic:getRecipe() and self.logic:getRecipe():getName() end)
		if ok and name then recipeName = name end
		local invAfter = "?"
		local okInv, invSize = pcall(function() return self.player:getInventory():getItems():size() end)
		if okInv then invAfter = tostring(invSize) end
		GlobalStorageSiK.CraftSession.debugLog(string.format(
			"craftAttempt(neat) END operationId=%s recipe=%s actionCompleted=true actionCancelled=false invAfter=%s",
			tostring(self._gsOperationId), recipeName, invAfter))
	end
	return originalNeatOnHandcraftActionComplete(self)
end

---@param self table NC_CraftActionPanel
local function patchedNeatOnHandcraftActionCancelled(self)
	if GlobalStorageSiK.CraftSession.getActiveSession(ADDON_ID) then
		local recipeName = "?"
		local ok, name = pcall(function() return self.logic and self.logic:getRecipe() and self.logic:getRecipe():getName() end)
		if ok and name then recipeName = name end
		GlobalStorageSiK.CraftSession.debugLog(string.format(
			"craftAttempt(neat) END operationId=%s recipe=%s actionCompleted=false actionCancelled=true",
			tostring(self._gsOperationId), recipeName))
	end
	return originalNeatOnHandcraftActionCancelled(self)
end

--- Instala/restaura los hooks de este addon - registrado en Core via
--- registerAddonHooks, llamado automaticamente al arrancar/terminar CUALQUIER
--- sesion (Core no distingue, cada addon comprueba getActiveSession(ADDON_ID)
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
end

--- Manejador de tick registrado en Core - resuelve esperas de reclamo tanto
--- para la ventana vanilla como para Neat.
local function craftTickHandler()
	checkPendingCraftStarts()
	checkPendingNeatCraftStarts()
end

GlobalStorageSiK.CraftSession.registerAddonHooks(ADDON_ID, installCraftHooks, uninstallCraftHooks)
GlobalStorageSiK.CraftSession.registerTickHandler(ADDON_ID, craftTickHandler)
