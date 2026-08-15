--[[
	GSSiK Addon Builder - Construcción remota
	Autor: SiK
	Fecha: 2026-08-13 (migrado desde GS_NetworkCraftSession.lua del Core -
	pedido explícito: Core no debería conocer ISBuildingObject, eso es
	conocimiento exclusivo de este addon; el Core solo expone infraestructura
	genérica de sesión/préstamo vía GlobalStorageSiK.CraftSession).
	Descripción: Reclama de la red al inventario del jugador los materiales
	que necesita ESTA construcción concreta, ANTES de dejar que vanilla cree
	la acción de construcción - confirmado con log real ("ISBuildIsoEntity ->
	consume failed", repetido) que Build NUNCA pasa por transferIfNeeded/
	startHandcraft (eso es solo de Handcraft/Craft) - el consumo real
	(ISBuildIsoEntity.ConsumeBuildEntityItems) solo mira el suelo (1 baldosa)
	+ inventario del jugador, jamás los contenedores de red, así que sin este
	hook Build no tenía NINGÚN mecanismo propio de traer materiales.
]]

require "GS_NetworkCraftSession"
require "GSSiK_Addon_Builder_Log"

local ADDON_ID = "Builder"

GlobalStorageSiK.CraftSession.registerDebugSink(ADDON_ID, function(message)
	GSSiK_Addon_Builder.Log.debug(message)
end)

local originalTryBuild = nil
local originalBuildActionPerform = nil
local originalBuildActionStop = nil
local pendingBuildStarts = {}
local PENDING_BUILD_TIMEOUT_MS = 4000

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
	local ok, playerNum = pcall(function()
		local char = action.character or action.player
		return char and char.getPlayerNum and char:getPlayerNum()
	end)
	if ok and playerNum and lastOperationByPlayer[playerNum] then
		print("[GlobalStorageSiK:BuildDiag] markBuildOperationComplete source=" .. tostring(source)
			.. " playerNum=" .. tostring(playerNum) .. " operationId=" .. tostring(lastOperationByPlayer[playerNum]))
		GlobalStorageSiK.CraftSession.markOperationComplete(lastOperationByPlayer[playerNum])
	else
		-- Diagnostico (2026-08-16, "sin verificar aun que ISBuildAction.
		-- perform/stop disparan de verdad"): si esto aparece, el hook SI se
		-- disparo pero no se pudo resolver el playerNum/operationId - revisar
		-- si action.character/action.player es el campo correcto.
		print("[GlobalStorageSiK:BuildDiag] markBuildOperationComplete source=" .. tostring(source)
			.. " NO RESUELTO (ok=" .. tostring(ok) .. " playerNum=" .. tostring(playerNum) .. ")")
	end
end

--- NOTA (2026-08-16): a diferencia de Craft/Cook, Build no tiene una ventana
--- propia con callbacks onHandcraftActionComplete/Cancelled que enganchar -
--- por eso aqui se parchea directamente ISBuildAction (la timed action
--- nativa), en vez de un widget. perform() y stop() son los puntos de
--- finalizacion estandar de ISBaseTimedAction en PZ (mismo patron ya usado
--- por Core para instrumentar ISHandcraftAction.performRecipe server-side).
--- SIN VERIFICAR AUN en partida real que estos dos metodos existen con este
--- nombre exacto en ISBuildAction (a diferencia de ISHandcraftAction.
--- performRecipe, que si esta confirmado y en uso) - todo pcall-envuelto y
--- con guardia "if X and X.metodo then" antes de parchear, asi que si el
--- nombre no coincide simplemente no se instala nada (los materiales caeran
--- al margen de seguridad de 30s de GS_NetworkCraftSession.lua en vez de
--- romper la construccion). Confirmar con un test real antes de dar esto
--- por bueno para la v1.0 de Builder.
local function patchedBuildActionPerform(self)
	local result = originalBuildActionPerform(self)
	markBuildOperationComplete(self, "perform")
	return result
end

---@param self table ISBuildAction
local function patchedBuildActionStop(self)
	markBuildOperationComplete(self, "stop")
	return originalBuildActionStop(self)
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
		if allReady or timedOut then
			table.remove(pendingBuildStarts, i)
			GlobalStorageSiK.CraftSession.debugLog(string.format(
				"buildAttempt RESUME operationId=%s waitResult=%s",
				tostring(entry.operationId), allReady and "allReady" or "timeout"))
			originalTryBuild(entry.self, entry.x, entry.y, entry.z)
		end
	end
end

--- Fulltypes que un InputScript de receta de construcción acepta.
---@param inputScript any
---@return string[]
local function buildRecipeInputTypes(inputScript)
	local types = {}
	local ok, entryItems = pcall(function() return inputScript:getPossibleInputItems() end)
	if ok and entryItems and entryItems.size then
		for i = 0, entryItems:size() - 1 do
			local okName, fullName = pcall(function() return entryItems:get(i):getFullName() end)
			if okName and fullName then
				types[#types + 1] = fullName
			end
		end
	end
	return types
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
			local okInputs, inputs = pcall(function() return craftRecipe:getInputs() end)
			if okInputs and inputs and inputs.size then
				local waitingIds = {}
				local waitingCount = 0
				local authoritative = GlobalStorageSiK.isAuthoritative()
				local claimed = 0
				local liveContainers = GlobalStorageSiK.Network.getLiveContainers(sess.networkId)
				local inv = playerObj:getInventory()
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
				GlobalStorageSiK.CraftSession.debugLog(string.format(
					"buildAttempt START operationId=%s recipe=%s networkId=%s containersCliente=%s",
					operationId, recipeName, tostring(sess.networkId), tostring(#liveContainers)))
				for i = 0, inputs:size() - 1 do
					local types = buildRecipeInputTypes(inputs:get(i))
					for t = 1, #types do
						local fullType = types[t]
						local alreadyHas = inv and inv.getItemCountRecurse
							and (inv:getItemCountRecurse(fullType) or 0) > 0
						if not alreadyHas then
							for c = 1, #liveContainers do
								local container = liveContainers[c].container
								local items = container and container.getItems and container:getItems()
								if items then
									for j = 0, items:size() - 1 do
										local item = items:get(j)
										if item and item.getFullType and item:getFullType() == fullType then
											local itemId = item.getID and item:getID()
											if GlobalStorageSiK.CraftSession.claimNetworkItem(playerObj, item, container, sess.networkId, operationId) then
												claimed = claimed + 1
												GlobalStorageSiK.CraftSession.debugLog(string.format(
													"buildAttempt claimSend operationId=%s itemId=%s fullType=%s",
													operationId, tostring(itemId), fullType))
												if not authoritative and itemId then
													waitingIds[itemId] = true
													waitingCount = waitingCount + 1
												end
											end
											break
										end
									end
								end
							end
						end
					end
				end
				GlobalStorageSiK.CraftSession.debugLog(string.format(
					"buildAttempt materiales reclamados=%s operationId=%s", tostring(claimed), operationId))
				if waitingCount > 0 then
					table.insert(pendingBuildStarts, {
						self = self, x = x, y = y, z = z,
						player = playerObj,
						waitingIds = waitingIds,
						startedAt = getTimestampMs and getTimestampMs() or 0,
						operationId = operationId,
					})
					GlobalStorageSiK.CraftSession.debugLog("buildAttempt WAIT operationId=" .. operationId
						.. " (esperando confirmacion del servidor)")
					return
				end
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
	-- Confirmacion incondicional (no gateada por DebugMode) de que hook
	-- realmente se instalo - responde de una vez la duda abierta en CLAUDE.md
	-- regla 4 sobre si ISBuildAction.perform/.stop existen con ese nombre.
	print("[GlobalStorageSiK:BuildDiag] installBuilderHooks ISBuildingObject.tryBuild=" .. tostring(originalTryBuild ~= nil)
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
end

GlobalStorageSiK.CraftSession.registerAddonHooks(ADDON_ID, installBuilderHooks, uninstallBuilderHooks)
GlobalStorageSiK.CraftSession.registerTickHandler(ADDON_ID, checkPendingBuildStarts)
