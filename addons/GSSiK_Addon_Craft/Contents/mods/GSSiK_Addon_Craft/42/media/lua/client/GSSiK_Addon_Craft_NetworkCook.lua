--[[
	GSSiK Addon Craft - Cocina remota (Project_Cook, mod externo opcional)
	Autor: SiK
	Fecha: 2026-08-16
	Descripción: Mismo patrón exacto que el bloque "Neat Crafting" de
	GSSiK_Addon_Craft_NetworkCraft.lua, para el mod de cocina "Project Cook"
	(workshop 3490188370, id de mod "Project_Cook", requiere NeatUI_Framework).
	Confirmado leyendo su código fuente: PJCK_CraftActionPanel:new() crea
	o.logic = HandcraftLogic.new(o.player, nil, nil) - un HandcraftLogic
	VANILLA de verdad, no una reimplementación propia - y su método
	:startHandcraft(force, craftTimes) tiene la MISMA forma exacta que
	NC_CraftActionPanel:startHandcraft(force, craftTimes) de Neat Crafting.
	Por eso aquí se reutilizan las operaciones públicas de WorkSession
	extraídas de este mismo fichero para poder compartirlas con Project_Cook
	sin duplicar ~90 líneas de lógica de reclamo/recorte por tercera vez) -
	la misma limitación del motor (HandcraftLogic.performCurrentRecipe()
	devuelve itemsCreados=0 con cualquier contenedor de red en self.containers,
	ver CLAUDE.md del addon) aplica aquí exactamente igual que en crafteo.

	Instalación/desinstalación de estos hooks NO se registra por separado en
	WorkSession.registerLifecycle - el ciclo se indexa
	por addonId ("Craft") y ya está ocupada por
	GSSiK_Addon_Craft_NetworkCraft.lua; registrar aquí otra vez pisaría esa
	entrada. En su lugar, GSSiK_Addon_Craft_NetworkCraft.lua llama a
	GSSiK_Addon_Craft_NetworkCook.install()/.uninstall()/.tick() desde SUS
	propios installCraftHooks/uninstallCraftHooks/craftTickHandler - una sola
	sesión "Craft", todos los hooks (vanilla + Neat + Cook) se instalan y
	desinstalan siempre juntos.
]]

local API = require "GSSiK_API_Client"
require "GSSiK_Addon_Craft_Log"
require "GSSiK_Addon_Craft_ClaimCompat"
require "GSSiK_Addon_Craft_BatchState"

local BatchState = GSSiK_Addon_Craft.BatchState
local Session = API.WorkSession

GSSiK_Addon_Craft_NetworkCook = {}

local ADDON_ID = "Craft"

local function failCookOperation(operationId, player, reasonKey)
	if not operationId then return end
	Session.abortOperation(operationId, player)
	local reason = getText(reasonKey)
	local message = getText("IGUI_GSSIK_CraftOperationFailedReturned", reason)
	if player and player.setHaloNote then
		player:setHaloNote(message, 255, 120, 100, 450)
	end
end

local originalCookStartHandcraft = nil
local originalCookOnHandcraftActionComplete = nil
local originalCookOnHandcraftActionCancelled = nil

--- NOTA: a diferencia de GSSiK_Addon_Craft_NetworkCraft.lua, aquí NO hay un
--- "activeOperationId" propio - el hook genérico patchedTransferIfNeeded
--- (red de seguridad para recetas isCanBeDoneFromFloor que caminan hasta un
--- ítem del suelo) ya vive en NetworkCraft.lua y se dispara para CUALQUIER
--- sesión activa del addon "Craft" sea cual sea la UI que la abrió
--- (crafteo o cocina) - no hace falta duplicarlo aquí, solo compartir el
--- mismo addonId de sesión.

--- Arranques de cocina esperando confirmación del servidor de que los
--- ítems de red YA están de verdad en el inventario del jugador, antes de
--- dejar que Project_Cook continúe - mismo motivo que pendingCraftStarts en
--- GSSiK_Addon_Craft_NetworkCraft.lua (fixMovedItems es un check de un solo
--- disparo, el claim servidor tarda ~300-400ms).
local pendingCookCraftStarts = {}
local PENDING_COOK_TIMEOUT_MS = 4000

local function activeSession()
	local ok, _, value = Session.get(ADDON_ID)
	return ok and value or nil
end

local function narrowInputs(panel, items)
	local ok, _, handle = Session.narrowInputs(panel, items, ADDON_ID)
	return function()
		if ok and handle then handle:restore() end
	end
end

---@param self table PJCK_CraftActionPanel
local function checkPendingCookCraftStarts()
	if #pendingCookCraftStarts == 0 then
		return
	end
	local nowMs = getTimestampMs and getTimestampMs() or 0
	for i = #pendingCookCraftStarts, 1, -1 do
		local entry = pendingCookCraftStarts[i]
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
		local timedOut = entry.startedAt and (nowMs - entry.startedAt) > PENDING_COOK_TIMEOUT_MS
		if allReady or timedOut then
			table.remove(pendingCookCraftStarts, i)
			if timedOut and not allReady then
				GSSiK_Addon_Craft.Log.debug("Operations", "cookAttempt ABORT operationId=" .. tostring(entry.operationId)
					.. " waitResult=timeout actionStarted=false")
				failCookOperation(entry.operationId, entry.self.player, "IGUI_GSSIK_CraftFailClaimTimeout")
				BatchState.clear(entry.self)
				return
			end
			GSSiK_Addon_Craft.Log.debug("Operations", string.format(
				"cookAttempt RESUME operationId=%s waitResult=%s actionStarted=true",
				tostring(entry.operationId), allReady and "allReady" or "timeout"))
			local okFreshItems, freshItems = pcall(function()
				return entry.self.logic and entry.self.logic:getRecipeData() and entry.self.logic:getRecipeData():getAllInputItems()
			end)
			local restore = narrowInputs(entry.self, okFreshItems and freshItems or nil)
			-- CONFIRMADO CON DATOS REALES (2026-08-16, ver bloque Neat en
			-- GSSiK_Addon_Craft_NetworkCraft.lua): isCraftActionInProgress no
			-- era el guardia real (siempre false). El guardia real es
			-- canPerformCurrentRecipe(), que lee false justo aqui porque
			-- HandcraftLogic cachea la validez de la receta desde ANTES del
			-- claim de red. autoPopulateInputs() (la misma funcion que
			-- PJCK_CraftActionPanel:onHandcraftActionComplete llama tras cada
			-- crafteo) refresca ese cache - forzarla aqui antes de reanudar.
			pcall(function() entry.self.logic:autoPopulateInputs() end)
			local okCanPerform, canPerform = pcall(function() return entry.self.logic and entry.self.logic:canPerformCurrentRecipe() end)
			GSSiK_Addon_Craft.Log.debug("Operations", string.format(
				"cookAttempt RESUME operationId=%s tras autoPopulateInputs canPerformCurrentRecipe=%s",
				tostring(entry.operationId), tostring(okCanPerform and canPerform)))
			if not entry.force and okCanPerform and canPerform == false then
				restore()
				failCookOperation(entry.operationId, entry.self.player, "IGUI_GSSIK_CraftFailInvalid")
				BatchState.clear(entry.self)
				return
			end
			local okCall, errCall = pcall(originalCookStartHandcraft, entry.self, entry.force, entry.craftTimes)
			if not okCall then
				GSSiK_Addon_Craft.Log.debug("Operations", "cookAttempt RESUME operationId=" .. tostring(entry.operationId)
					.. " originalCookStartHandcraft ERROR: " .. tostring(errCall))
				failCookOperation(entry.operationId, entry.self.player, "IGUI_GSSIK_CraftFailStart")
				BatchState.clear(entry.self)
			end
			restore()
		end
	end
end

---@param self table PJCK_CraftActionPanel
---@param force boolean|nil
---@param craftTimes number|nil
local function patchedCookStartHandcraft(self, force, craftTimes)
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
				addonId = ADDON_ID, player = self.player, kind = "cook",
				recipeName = recipeName, batchCount = batchCount,
				canUseFloor = floorOk, containerCount = containersCount,
				diagnostics = true,
			})
			if operationOk ~= true or not operation then
				GSSiK_Addon_Craft.Log.debug("Operations",
					"cookAttempt rejected code=" .. tostring(operationCode))
				return originalCookStartHandcraft(self, force, craftTimes)
			end
			local operationId = operation.operationId
			self._gsOperationId = operationId
			if okItems and items and items.size then
				BatchState.begin(self, operationId, batchCount)
				local waitingIds, waitingCount, moved, batchShortfall, batchContractSupported = GSSiK_Addon_Craft.claimRecipeItemsCompat(
					self.player, self.logic, items, operationId, batchCount)
				GSSiK_Addon_Craft.Log.debug("Operations", string.format(
					"cookAttempt START operationId=%s addonId=%s recipe=%s networkId=%s isCanBeDoneFromFloor=%s inputs=%d movidosDeRed=%d batchCount=%d containersCliente=%d",
					operationId, ADDON_ID, recipeName, tostring(sess.networkId),
					tostring(floorOk), items:size(), moved, batchCount, containersCount))
				if batchShortfall > 0 then
					GSSiK_Addon_Craft.Log.debug("Operations", "cookAttempt ABORT operationId=" .. operationId
						.. " batchShortfall=" .. tostring(batchShortfall))
					failCookOperation(operationId, self.player, batchContractSupported
						and "IGUI_GSSIK_CraftFailBatchMaterials" or "IGUI_GSSIK_CraftFailCoreUpdate")
					BatchState.clear(self)
					return
				end
				if waitingCount > 0 then
					table.insert(pendingCookCraftStarts, {
						self = self, force = force, craftTimes = craftTimes,
						waitingIds = waitingIds,
						startedAt = getTimestampMs and getTimestampMs() or 0,
						operationId = operationId,
					})
					GSSiK_Addon_Craft.Log.debug("Operations", "cookAttempt WAIT operationId=" .. operationId .. " (esperando confirmacion del servidor)")
					return
				end
			end
			local restore = narrowInputs(self, okItems and items or nil)
			local invBefore = "?"
			local okInv, invSize = pcall(function() return self.player:getInventory():getItems():size() end)
			if okInv then invBefore = tostring(invSize) end
			GSSiK_Addon_Craft.Log.debug("Operations", "cookAttempt invBefore=" .. invBefore .. " operationId=" .. operationId)
			pcall(function() self.logic:autoPopulateInputs() end)
			local okCanPerform, canPerform = pcall(function() return self.logic:canPerformCurrentRecipe() end)
			if not force and okCanPerform and canPerform == false then
				restore()
				failCookOperation(operationId, self.player, "IGUI_GSSIK_CraftFailInvalid")
				BatchState.clear(self)
				return
			end
			local okCall, errCall = pcall(originalCookStartHandcraft, self, force, craftTimes)
			restore()
			if not okCall then
				GSSiK_Addon_Craft.Log.debug("Operations", "cookAttempt START ERROR operationId=" .. tostring(operationId)
					.. " error=" .. tostring(errCall))
				failCookOperation(operationId, self.player, "IGUI_GSSIK_CraftFailStart")
				BatchState.clear(self)
			end
			return
		end
	end
	return originalCookStartHandcraft(self, force, craftTimes)
end

---@param self table PJCK_CraftActionPanel
local function patchedCookOnHandcraftActionComplete(self, ...)
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
				"cookAttempt END operationId=%s recipe=%s units=%d/%d actionCompleted=true actionCancelled=false invAfter=%s",
				tostring(operationId), recipeName, completed, expected, invAfter))
		else
			GSSiK_Addon_Craft.Log.debug("Operations", string.format(
				"cookAttempt PROGRESS operationId=%s recipe=%s units=%d/%d",
				tostring(operationId), recipeName, completed, expected))
		end
	end
	if final then
		Session.completeOperation(operationId, self.player)
	end
	return originalCookOnHandcraftActionComplete(self, ...)
end

---@param self table PJCK_CraftActionPanel
local function patchedCookOnHandcraftActionCancelled(self, ...)
	local operationId, completed, expected = BatchState.cancel(self)
	if operationId and activeSession() then
		local recipeName = "?"
		local ok, name = pcall(function() return self.logic and self.logic:getRecipe() and self.logic:getRecipe():getName() end)
		if ok and name then recipeName = name end
		GSSiK_Addon_Craft.Log.debug("Operations", string.format(
			"cookAttempt END operationId=%s recipe=%s units=%d/%d actionCompleted=false actionCancelled=true",
			tostring(operationId), recipeName, completed, expected))
	end
	if operationId then
		failCookOperation(operationId, self.player, "IGUI_GSSIK_CraftFailCancelled")
	end
	return originalCookOnHandcraftActionCancelled(self, ...)
end

--- Instala los hooks de cocina - llamado desde installCraftHooks() en
--- GSSiK_Addon_Craft_NetworkCraft.lua, nunca directamente por Core. Solo
--- parchea si PJCK_CraftActionPanel existe como global (Project_Cook activo)
--- - si no está instalado, esta función no hace nada, sin errores ni ramas
--- especiales que comprobar en el resto del addon.
function GSSiK_Addon_Craft_NetworkCook.install()
	if not PJCK_CraftActionPanel then
		return
	end
	if PJCK_CraftActionPanel and PJCK_CraftActionPanel.startHandcraft then
		originalCookStartHandcraft = PJCK_CraftActionPanel.startHandcraft
		PJCK_CraftActionPanel.startHandcraft = patchedCookStartHandcraft
	end
	if PJCK_CraftActionPanel and PJCK_CraftActionPanel.onHandcraftActionComplete then
		originalCookOnHandcraftActionComplete = PJCK_CraftActionPanel.onHandcraftActionComplete
		PJCK_CraftActionPanel.onHandcraftActionComplete = patchedCookOnHandcraftActionComplete
	end
	if PJCK_CraftActionPanel and PJCK_CraftActionPanel.onHandcraftActionCancelled then
		originalCookOnHandcraftActionCancelled = PJCK_CraftActionPanel.onHandcraftActionCancelled
		PJCK_CraftActionPanel.onHandcraftActionCancelled = patchedCookOnHandcraftActionCancelled
	end
end

--- Restaura los métodos originales de PJCK_CraftActionPanel.
function GSSiK_Addon_Craft_NetworkCook.uninstall()
	if originalCookStartHandcraft then
		PJCK_CraftActionPanel.startHandcraft = originalCookStartHandcraft
		originalCookStartHandcraft = nil
	end
	if originalCookOnHandcraftActionComplete then
		PJCK_CraftActionPanel.onHandcraftActionComplete = originalCookOnHandcraftActionComplete
		originalCookOnHandcraftActionComplete = nil
	end
	if originalCookOnHandcraftActionCancelled then
		PJCK_CraftActionPanel.onHandcraftActionCancelled = originalCookOnHandcraftActionCancelled
		originalCookOnHandcraftActionCancelled = nil
	end
end

--- Manejador de tick - llamado desde craftTickHandler() en
--- GSSiK_Addon_Craft_NetworkCraft.lua junto con las colas de vanilla/Neat.
function GSSiK_Addon_Craft_NetworkCook.tick()
	checkPendingCookCraftStarts()
end

--- Abre (o trae al frente) la ventana de Project_Cook para el jugador -
--- Project_Cook rastrea su propia ventana vía PJCK_CookingUI.IsWindowOpen/
--- GetWindowInstance (API propia, NO vía ISEntityUI como el crafteo/
--- construcción vanilla/Neat), así que no puede reutilizarse
--- WorkSession.openHandcraft para esto.
---@param player IsoPlayer
---@return boolean ok
---@return string|nil reason "no_player"|"opener_unresolved" si falla
function GSSiK_Addon_Craft_NetworkCook.openCookUI(player)
	if not player then
		return false, "no_player"
	end
	if not PJCK_CookingUI or not PJCK_CookingUI.OnOpenPanel then
		return false, "opener_unresolved"
	end
	local playerNum = player:getPlayerNum()
	if PJCK_CookingUI.IsWindowOpen and PJCK_CookingUI.IsWindowOpen(playerNum) then
		local win = PJCK_CookingUI.GetWindowInstance and PJCK_CookingUI.GetWindowInstance(playerNum)
		if win and win.bringToTop then
			win:bringToTop()
		end
		return true
	end
	PJCK_CookingUI.OnOpenPanel(player, nil)
	return true
end
