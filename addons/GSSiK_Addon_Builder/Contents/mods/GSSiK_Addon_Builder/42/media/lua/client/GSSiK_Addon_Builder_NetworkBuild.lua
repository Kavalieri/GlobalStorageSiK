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
local pendingBuildStarts = {}
local PENDING_BUILD_TIMEOUT_MS = 4000

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
			GlobalStorageSiK.CraftSession.debugLog("patchedTryBuild reanuda tras espera - allReady=" .. tostring(allReady)
				.. " timedOut=" .. tostring(timedOut))
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
											if GlobalStorageSiK.CraftSession.claimNetworkItem(playerObj, item, container, sess.networkId) then
												claimed = claimed + 1
												if not authoritative and item.getID then
													waitingIds[item:getID()] = true
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
				GlobalStorageSiK.CraftSession.debugLog("patchedTryBuild materiales reclamados=" .. tostring(claimed))
				if waitingCount > 0 then
					table.insert(pendingBuildStarts, {
						self = self, x = x, y = y, z = z,
						player = playerObj,
						waitingIds = waitingIds,
						startedAt = getTimestampMs and getTimestampMs() or 0,
					})
					GlobalStorageSiK.CraftSession.debugLog("patchedTryBuild esperando confirmacion del servidor antes de construir")
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
end

local function uninstallBuilderHooks()
	if originalTryBuild then
		ISBuildingObject.tryBuild = originalTryBuild
	end
end

GlobalStorageSiK.CraftSession.registerAddonHooks(ADDON_ID, installBuilderHooks, uninstallBuilderHooks)
GlobalStorageSiK.CraftSession.registerTickHandler(ADDON_ID, checkPendingBuildStarts)
