--[[
	GSSiK Addon Builder - Construcción remota
	Autor: SiK
	Fecha: 2026-08-13 (migrado desde GS_NetworkCraftSession.lua del Core -
	pedido explícito: Core no debería conocer ISBuildingObject, eso es
	conocimiento exclusivo de este addon; el Core solo expone infraestructura
	genérica de sesión/préstamo vía GlobalStorageSiK.CraftSession).
	Descripción: Reclama de la red al inventario del jugador los inputs reales
	seleccionados por BuildLogic, crea para la acción una copia de BuildLogic
	que solo ve ese inventario y deja que ISBuildAction complete la ruta
	vanilla. Compartido por las ventanas vanilla y Neat Building.
]]

require "GS_NetworkCraftSession"
require "GS_I18n"
require "GSSiK_Addon_Builder_Log"

local ADDON_ID = "Builder"

local function failBuildOperation(operationId, player, reasonKey)
	if not operationId then return end
	GlobalStorageSiK.CraftSession.abortOperation(operationId)
	local reason = GlobalStorageSiK.I18n.text(reasonKey)
	local message = GlobalStorageSiK.I18n.text("IGUI_GSSIK_BuilderOperationFailedReturned", reason)
	if player and player.setHaloNote then
		player:setHaloNote(message, 255, 120, 100, 450)
	end
end

GlobalStorageSiK.CraftSession.registerDebugSink(ADDON_ID, function(message)
	GSSiK_Addon_Builder.Log.debug("Operations", message)
end)

local originalTryBuild = nil
local originalBuildActionPerform = nil
local originalBuildActionStop = nil
local originalBuildActionForceComplete = nil
local originalBuildActionForceStop = nil
local originalBuildActionForceCancel = nil
local pendingBuildStarts = {}
local PENDING_BUILD_TIMEOUT_MS = 10000

--- playerNum -> ultimo operationId de construccion reclamado - mismo patron
--- que lastOperationByPlayer en GS_Server.lua (Core), necesario porque
--- ISBuildAction (la timed action nativa que de verdad ejecuta
--- ConsumeBuildEntityItems) es una instancia SEPARADA de self
--- (ISBuildingObject) usada en patchedTryBuild - no hay forma directa de
--- llevar el operationId de una a otra salvo por este mapa, igual que Craft
--- ya no puede llevar su propio operationId a traves de ISHandcraftAction.
local lastOperationByPlayer = {}

--- Marca el operationId de construccion en curso para un jugador como
--- terminado - llamado desde los hooks de ISBuildAction.perform/stop (ver
--- installBuilderHooks). Necesario para que GS_NetworkCraftSession.lua sepa
--- que ya puede devolver los materiales reclamados a la red (2026-08-16,
--- mismo fix que Craft: antes la devolucion se basaba en un margen de
--- tiempo fijo, con riesgo real de devolver materiales mientras la
--- construccion aun podia estar consumiendolos - ahora se ata al evento
--- real de fin de la accion).
---@param action table ISBuildAction
---@param source string "perform"|"stop" - de donde se llamo, para el diagnostico
local function markBuildOperationComplete(action, source)
	if action and action._gsBuilderOperationResolved then return end
	local ok, playerNum = pcall(function()
		local char = action.character or action.player
		return char and char.getPlayerNum and char:getPlayerNum()
	end)
	local operationId = action and action._gsBuilderOperationId
		or (ok and playerNum and lastOperationByPlayer[playerNum])
	if operationId then
		local character = action and action.character or nil
		if not character and ok and playerNum and getSpecificPlayer then
			character = getSpecificPlayer(playerNum)
		end
		GSSiK_Addon_Builder.Log.debug("Operations", "resolve source=" .. tostring(source)
			.. " playerNum=" .. tostring(playerNum) .. " operationId=" .. tostring(operationId))
		-- La copia aislada de BuildLogic pertenece a esta accion; detenerla al
		-- resolver evita dejar un estado de crafteo interno vivo tras cancelar.
		pcall(function()
			if action.item and action.item.buildPanelLogic then
				action.item.buildPanelLogic:stopCraftAction()
			end
		end)
		if source == "perform" or source == "forceComplete" then
			GlobalStorageSiK.CraftSession.markOperationComplete(operationId)
		else
			local reasonKey = source == "forceStop" and "IGUI_GSSIK_BuilderFailInvalid"
				or "IGUI_GSSIK_BuilderFailCancelled"
			failBuildOperation(operationId, character, reasonKey)
		end
		if action then
			action._gsBuilderOperationId = nil
			action._gsBuilderOperationResolved = true
		end
		if ok and playerNum and lastOperationByPlayer[playerNum] == operationId then
			lastOperationByPlayer[playerNum] = nil
		end
	else
		-- Si aparece, el hook se disparo pero no pudo resolver el jugador o la
		-- operacion. Conservar una sola linea correlacionable para diagnostico.
		GSSiK_Addon_Builder.Log.debug("Operations", "resolve source=" .. tostring(source)
			.. " NO RESUELTO (ok=" .. tostring(ok) .. " playerNum=" .. tostring(playerNum) .. ")")
	end
end

--- A diferencia de Craft/Cook, Build no tiene una ventana propia con callbacks
--- de finalizacion. La fuente vanilla B42 confirma que la ruta termina en
--- ISBuildAction; por eso el addon intercepta aqui perform/stop y las variantes
--- force*, siempre con guardas de existencia para conservar compatibilidad.
local function patchedBuildActionPerform(self)
	local ok, result = pcall(originalBuildActionPerform, self)
	if ok then
		markBuildOperationComplete(self, "perform")
	else
		markBuildOperationComplete(self, "forceStop")
		GlobalStorageSiK.CraftSession.debugLog("buildAttempt PERFORM ERROR: " .. tostring(result))
	end
	return ok and result or nil
end

---@param self table ISBuildAction
local function patchedBuildActionStop(self)
	markBuildOperationComplete(self, "stop")
	return originalBuildActionStop(self)
end

local function patchedBuildActionForceComplete(self)
	local result = originalBuildActionForceComplete(self)
	markBuildOperationComplete(self, "forceComplete")
	return result
end

local function patchedBuildActionForceStop(self)
	markBuildOperationComplete(self, "forceStop")
	return originalBuildActionForceStop(self)
end

local function patchedBuildActionForceCancel(self)
	markBuildOperationComplete(self, "forceCancel")
	return originalBuildActionForceCancel(self)
end

--- Crea el BuildLogic que viaja con ISBuildAction usando exclusivamente el
--- inventario principal. El cursor conserva su logic original para que las
--- ventanas vanilla/Neat sigan funcionando tras colocar el objeto.
---@param buildObject table ISBuildIsoEntity
---@param player IsoPlayer
---@param craftRecipe any
---@return any isolatedLogic
---@return function restoreOriginalContainers
local function createInventoryBuildLogic(buildObject, player, craftRecipe)
	if not BuildLogic or not BuildLogic.new then
		return nil, function() end
	end
	local originalLogic = buildObject.buildPanelLogic
	local originalContainers = nil
	if originalLogic and originalLogic.getContainers then
		pcall(function() originalContainers = originalLogic:getContainers() end)
	end
	local localContainers = GlobalStorageSiK.CraftSession.tableToArrayList({ player:getInventory() })
	if originalLogic then
		pcall(function()
			originalLogic:setContainers(localContainers)
			originalLogic:autoPopulateInputs()
		end)
	end

	local isolated = BuildLogic.new(player, nil, nil)
	isolated:setContainers(localContainers)
	isolated:setRecipe(craftRecipe)
	local copied = false
	if originalLogic and isolated.copyManualInputsFrom then
		copied = pcall(function() isolated:copyManualInputsFrom(originalLogic) end)
	end
	if not copied and isolated.autoPopulateInputs then
		isolated:autoPopulateInputs()
	end

	return isolated, function()
		if originalLogic and originalContainers then
			pcall(function() originalLogic:setContainers(originalContainers) end)
		end
	end
end

---@param inputScript any
---@param inventory ItemContainer
---@return InventoryItem|nil
local function findTool(inputScript, inventory)
	if not inputScript or not inventory then return nil end
	local ok, possible = pcall(function() return inputScript:getPossibleInputItems() end)
	if not ok or not possible or not possible.size then return nil end
	for i = 0, possible:size() - 1 do
		local fullType = possible:get(i):getFullName()
		local found = inventory:getAllTypeEvalRecurse(fullType, ISBuildIsoEntity.predicateMaterial)
		if found and found:size() > 0 then
			return found:get(0)
		end
	end
	return nil
end

---@param buildObject table
---@param player IsoPlayer
---@param craftRecipe any
local function refreshBuildTools(buildObject, player, craftRecipe)
	local inv = player:getInventory()
	local both = findTool(craftRecipe:getToolBoth(), inv)
	local right = findTool(craftRecipe:getToolRight(), inv)
	local left = findTool(craftRecipe:getToolLeft(), inv)
	-- Vanilla espera el OBJETO para equipBothHandItem, pero nombres de tipo
	-- para firstItem/secondItem (ISBuildingObject.tryBuild, B42).
	buildObject.equipBothHandItem = both
	buildObject.firstItem = right and right:getFullType() or nil
	buildObject.secondItem = left and left:getFullType() or nil
end

---@param buildObject table
---@param x number
---@param y number
---@param z number
---@param player IsoPlayer
---@param craftRecipe any
---@param operationId string
local function startInventoryBuild(buildObject, x, y, z, player, craftRecipe, operationId)
	local originalLogic = buildObject.buildPanelLogic
	local isolatedLogic, restoreContainers = createInventoryBuildLogic(buildObject, player, craftRecipe)
	if isolatedLogic then
		buildObject.buildPanelLogic = isolatedLogic
	end
	refreshBuildTools(buildObject, player, craftRecipe)
	local ok, result = pcall(originalTryBuild, buildObject, x, y, z)
	buildObject.buildPanelLogic = originalLogic
	restoreContainers()
	if not ok then
		GlobalStorageSiK.CraftSession.debugLog("buildAttempt START ERROR operationId="
			.. tostring(operationId) .. " error=" .. tostring(result))
		failBuildOperation(operationId, player, "IGUI_GSSIK_BuilderFailStart")
		if player.getPlayerNum and lastOperationByPlayer[player:getPlayerNum()] == operationId then
			lastOperationByPlayer[player:getPlayerNum()] = nil
		end
		return nil
	end
	if result then
		result._gsBuilderOperationId = operationId
	else
		-- skipBuildAction es la unica ruta instantanea conocida. Sin accion y
		-- sin ese flag, vanilla/Neat rechazaron el intento: informar y devolver.
		if buildObject.skipBuildAction then
			GlobalStorageSiK.CraftSession.markOperationComplete(operationId)
		else
			failBuildOperation(operationId, player, "IGUI_GSSIK_BuilderFailInvalid")
		end
		if player.getPlayerNum and lastOperationByPlayer[player:getPlayerNum()] == operationId then
			lastOperationByPlayer[player:getPlayerNum()] = nil
		end
	end
	return result
end

--- Revisa cada tick si los materiales reclamados para una construcción ya
--- están de verdad en el inventario del jugador - mismo mecanismo que el
--- de Craft, cola propia porque el punto de reanudación es distinto
--- (originalTryBuild, no originalStartHandcraft).
local function checkPendingBuildStarts()
	if #pendingBuildStarts == 0 then
		return
	end
	local nowMs = getTimestampMs and getTimestampMs() or 0
	for i = #pendingBuildStarts, 1, -1 do
		local entry = pendingBuildStarts[i]
		local inv = entry.player and entry.player.getInventory and entry.player:getInventory()
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
		local timedOut = entry.startedAt and (nowMs - entry.startedAt) > PENDING_BUILD_TIMEOUT_MS
		if allReady then
			table.remove(pendingBuildStarts, i)
			GlobalStorageSiK.CraftSession.debugLog(string.format(
				"buildAttempt RESUME operationId=%s waitResult=%s",
				tostring(entry.operationId), "allReady"))
			startInventoryBuild(entry.self, entry.x, entry.y, entry.z,
				entry.player, entry.craftRecipe, entry.operationId)
		elseif timedOut then
			table.remove(pendingBuildStarts, i)
			GlobalStorageSiK.CraftSession.debugLog("buildAttempt ABORT operationId="
				.. tostring(entry.operationId) .. " timeout esperando materiales")
			failBuildOperation(entry.operationId, entry.player, "IGUI_GSSIK_BuilderFailClaimTimeout")
			if entry.player and entry.player.getPlayerNum
				and lastOperationByPlayer[entry.player:getPlayerNum()] == entry.operationId then
				lastOperationByPlayer[entry.player:getPlayerNum()] = nil
			end
		end
	end
end

---@param self table ISBuildingObject/ISBuildIsoEntity
---@param x number
---@param y number
---@param z number
local function patchedTryBuild(self, x, y, z)
	local sess = GlobalStorageSiK.CraftSession.getActiveSession(ADDON_ID)
	if sess and self.objectInfo then
		local playerObj = getSpecificPlayer and self.player and getSpecificPlayer(self.player) or nil
		local okRecipe, craftRecipe = pcall(function()
			local recipe = self.objectInfo:getRecipe()
			return recipe and recipe:getCraftRecipe()
		end)
		if playerObj and okRecipe and craftRecipe then
			local logic = self.buildPanelLogic
			local okInputs, inputs = pcall(function()
				return logic and logic:getRecipeData() and logic:getRecipeData():getAllInputItems()
			end)
			if okInputs and inputs and inputs.size then
				-- operationId nuevo por cada intento de construccion (mismo
				-- patron que Craft) - guardado por playerNum para que los
				-- hooks de ISBuildAction.perform/stop sepan que operacion
				-- marcar como terminada cuando la accion nativa acabe de
				-- verdad (ver markBuildOperationComplete).
				local operationId = GlobalStorageSiK.CraftSession.newOperationId(ADDON_ID)
				if playerObj.getPlayerNum then
					lastOperationByPlayer[playerObj:getPlayerNum()] = operationId
				end
				local recipeName = "?"
				local okName, name = pcall(function() return craftRecipe:getName() end)
				if okName and name then recipeName = name end
				local waitingIds, waitingCount, claimed = GlobalStorageSiK.CraftSession.claimRecipeItems(
					playerObj, logic, inputs, sess.networkId, operationId, 1)
				GlobalStorageSiK.CraftSession.debugLog(string.format(
					"buildAttempt START operationId=%s recipe=%s networkId=%s inputs=%s reclamados=%s",
					operationId, recipeName, tostring(sess.networkId), tostring(inputs:size()), tostring(claimed)))
				if waitingCount > 0 then
					table.insert(pendingBuildStarts, {
						self = self, x = x, y = y, z = z,
						player = playerObj,
						craftRecipe = craftRecipe,
						waitingIds = waitingIds,
						startedAt = getTimestampMs and getTimestampMs() or 0,
						operationId = operationId,
					})
					GlobalStorageSiK.CraftSession.debugLog("buildAttempt WAIT operationId=" .. operationId
						.. " (esperando confirmacion del servidor)")
					return
				end
				return startInventoryBuild(self, x, y, z, playerObj, craftRecipe, operationId)
			end
		end
	end
	return originalTryBuild(self, x, y, z)
end

local function installBuilderHooks()
	if ISBuildingObject and ISBuildingObject.tryBuild then
		originalTryBuild = ISBuildingObject.tryBuild
		ISBuildingObject.tryBuild = patchedTryBuild
	end
	if ISBuildAction and ISBuildAction.perform then
		originalBuildActionPerform = ISBuildAction.perform
		ISBuildAction.perform = patchedBuildActionPerform
	end
	if ISBuildAction and ISBuildAction.stop then
		originalBuildActionStop = ISBuildAction.stop
		ISBuildAction.stop = patchedBuildActionStop
	end
	if ISBuildAction and ISBuildAction.forceComplete then
		originalBuildActionForceComplete = ISBuildAction.forceComplete
		ISBuildAction.forceComplete = patchedBuildActionForceComplete
	end
	if ISBuildAction and ISBuildAction.forceStop then
		originalBuildActionForceStop = ISBuildAction.forceStop
		ISBuildAction.forceStop = patchedBuildActionForceStop
	end
	if ISBuildAction and ISBuildAction.forceCancel then
		originalBuildActionForceCancel = ISBuildAction.forceCancel
		ISBuildAction.forceCancel = patchedBuildActionForceCancel
	end
	-- Resumen unico de instalacion, visible solo con Lifecycle habilitado.
	GSSiK_Addon_Builder.Log.debug("Lifecycle", "hooks installed tryBuild=" .. tostring(originalTryBuild ~= nil)
		.. " ISBuildAction.perform=" .. tostring(originalBuildActionPerform ~= nil)
		.. " ISBuildAction.stop=" .. tostring(originalBuildActionStop ~= nil))
end

local function uninstallBuilderHooks()
	if originalTryBuild then
		ISBuildingObject.tryBuild = originalTryBuild
		originalTryBuild = nil
	end
	if originalBuildActionPerform then
		ISBuildAction.perform = originalBuildActionPerform
		originalBuildActionPerform = nil
	end
	if originalBuildActionStop then
		ISBuildAction.stop = originalBuildActionStop
		originalBuildActionStop = nil
	end
	if originalBuildActionForceComplete then
		ISBuildAction.forceComplete = originalBuildActionForceComplete
		originalBuildActionForceComplete = nil
	end
	if originalBuildActionForceStop then
		ISBuildAction.forceStop = originalBuildActionForceStop
		originalBuildActionForceStop = nil
	end
	if originalBuildActionForceCancel then
		ISBuildAction.forceCancel = originalBuildActionForceCancel
		originalBuildActionForceCancel = nil
	end
end

GlobalStorageSiK.CraftSession.registerAddonHooks(ADDON_ID, installBuilderHooks, uninstallBuilderHooks)
GlobalStorageSiK.CraftSession.registerTickHandler(ADDON_ID, checkPendingBuildStarts)
