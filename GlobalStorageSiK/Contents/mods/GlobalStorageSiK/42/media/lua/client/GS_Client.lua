--[[
	GlobalStorageSiK - Lógica cliente
	Autor: SiK
	Fecha: 2025-06-24
]]

require "GS_Config"
require "GS_Utils"
require "GS_Network"
require "GS_Log"
require "GS_NetClient"
require "GS_Debug"
require "GS_NetTrace"
require "GS_Sandbox"

require "GS_NodeNaming"
require "GS_I18n"

--- Nota flotante sobre el jugador. Los fallos (ok=false, p.ej. "Red sin
--- energía") se pintan en rojo y duran mas tiempo - antes todo salia en gris
--- clarito 300ms, facil de no ver mientras se mira la ventana del terminal
--- en vez del personaje.
---@param text string|nil
---@param failed boolean|nil
local function showMessage(text, failed)
	local player = GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer() or getPlayer()
	if player and text then
		if failed then
			player:setHaloNote(tostring(text), 235, 90, 90, 600)
		else
			player:setHaloNote(tostring(text), 220, 220, 220, 300)
		end
	end
end

---@param args table|nil
---@return boolean
local function isOperationFeedback(args)
	return args ~= nil and (args.transfer ~= nil or args.deposit ~= nil or args.bulk ~= nil
		or args.jobType == "redistribute")
end

--- Fusiona terminalState parcial de inventario con el estado cacheado previo.
---@param incoming table|nil
---@param prev table|nil
---@return table|nil
local function mergeInventorySyncState(incoming, prev)
	if not incoming or not incoming.inventorySync or not prev then
		return incoming
	end
	local merged = {}
	for k, v in pairs(prev) do
		merged[k] = v
	end
	for k, v in pairs(incoming) do
		if k ~= "inventorySync" and k ~= "openUi" then
			merged[k] = v
		end
	end
	return merged
end

local function safeRequire(name)
	local ok, err = pcall(require, name)
	if not ok then
		GlobalStorageSiK.Log.error("Client", "require failed: " .. tostring(name), err)
		return false
	end
	return true
end

if not safeRequire("GS_TerminalUI") then
	return
end
if not safeRequire("GS_TerminalUI_Api") then
	return
end
if not safeRequire("GS_TerminalUI_Blocked") then
	return
end
safeRequire("GS_TerminalAccessGuard")
if GlobalStorageSiK.TerminalAccessGuard and GlobalStorageSiK.TerminalAccessGuard.ensure then
	GlobalStorageSiK.TerminalAccessGuard.ensure()
end
safeRequire("GS_WorldHighlight")
safeRequire("GS_ZonePicker")
if GlobalStorageSiK.ZonePicker and GlobalStorageSiK.ZonePicker.install then
	GlobalStorageSiK.ZonePicker.install()
end
safeRequire("GS_TerminalPlace")
safeRequire("GS_DepositClient")
safeRequire("GS_TransferQueue")
safeRequire("GS_TerminalSync")
safeRequire("GS_TerminalDrop")
safeRequire("GS_WithdrawClient")
safeRequire("GS_QuantityPrompt")
safeRequire("GS_ContainerTargets")
safeRequire("GS_ContextMenuUi")
safeRequire("GS_ContextMenu")
safeRequire("GS_WithdrawMenu")
safeRequire("GS_TransferMenu")
safeRequire("GS_TerminalWithdrawDrag")
safeRequire("GS_ItemActions")

if GlobalStorageSiK.TerminalDrop and GlobalStorageSiK.TerminalDrop.installHooks then
	GlobalStorageSiK.TerminalDrop.installHooks()
end
if GlobalStorageSiK.TerminalWithdrawDrag and GlobalStorageSiK.TerminalWithdrawDrag.installHooks then
	GlobalStorageSiK.TerminalWithdrawDrag.installHooks()
end

local function onServerCommand(module, command, args)
	if module ~= GlobalStorageSiK.MOD_ID then
		return
	end
	if GlobalStorageSiK.NetTrace and GlobalStorageSiK.NetTrace.logClientRecv then
		GlobalStorageSiK.NetTrace.logClientRecv(command, args)
	end

	if command == "actionResult" then
		-- El servidor envía la clave (+ args) en vez del texto ya resuelto,
		-- para que cada cliente lo traduzca a SU propio idioma en vez de
		-- heredar el idioma configurado en el proceso del servidor - ver
		-- GlobalStorageSiK.I18n.remote / resolveRemote en GS_I18n.lua.
		local continuing = false
		if GlobalStorageSiK.TransferQueue and GlobalStorageSiK.TransferQueue.onActionResult then
			continuing = GlobalStorageSiK.TransferQueue.onActionResult(args) == true
		end
		if GlobalStorageSiK.WithdrawClient and GlobalStorageSiK.WithdrawClient.onActionResult then
			continuing = GlobalStorageSiK.WithdrawClient.onActionResult(args) == true or continuing
		end
		local resolvedMessage = args and GlobalStorageSiK.I18n.resolveRemote(args.message)
		if GlobalStorageSiK.TerminalSync and GlobalStorageSiK.TerminalSync.onActionResult then
			GlobalStorageSiK.TerminalSync.onActionResult(args)
		end
		-- Cada cola consume exclusivamente su operation ID. Una respuesta de
		-- otra acción nunca libera ni hace avanzar depósitos o retiradas.
		if not continuing then
			local failed = args and args.ok == false
			local showOperation = not GlobalStorageSiK.Sandbox.operationHaloFeedbackEnabled
				or GlobalStorageSiK.Sandbox.operationHaloFeedbackEnabled()
			-- Los errores nunca se silencian. La opción solo controla feedback
			-- funcional de procesos largos; el resto de mensajes conserva su flujo.
			if failed or not isOperationFeedback(args) or showOperation then
				showMessage(resolvedMessage or "Listo", failed)
			end
		end
		if args and args.jobType == "redistribute" then
			if args.jobState == "finished" and (args.redistributeTiers or args.redistributeTopTypes) then
				GlobalStorageSiK.Log.info("RedistributeJob", "completed breakdown",
					"tiers=" .. tostring(args.redistributeTiers or "none")
						.. " topTypes=" .. tostring(args.redistributeTopTypes or "none"))
			end
			local ui = GlobalStorageSiK.TerminalUI and GlobalStorageSiK.TerminalUI.instance
			if ui and args.jobState == "running" and ui.onRedistributeStarted then
				ui:onRedistributeStarted(resolvedMessage)
			elseif ui and ui.onRedistributeFinished then
				-- Compatibilidad: una respuesta final de una version anterior del
				-- servidor no llevaba jobState y se interpreta como finalizada.
				ui:onRedistributeFinished(args.ok == true, resolvedMessage)
			end
		end
		if args and args.jobType == "zoneScan" then
			local ui = GlobalStorageSiK.TerminalUI and GlobalStorageSiK.TerminalUI.instance
			if ui and ui.terminalState then
				ui.terminalState.scanActive = args.jobState == "running"
				ui.terminalState.scan = ui.terminalState.scan or {}
				ui.terminalState.scan.running = args.jobState == "running"
				if GlobalStorageSiK.TerminalNetwork and GlobalStorageSiK.TerminalNetwork.refreshActiveTab then
					GlobalStorageSiK.TerminalNetwork.refreshActiveTab(ui, ui.terminalState)
				end
			end
		end
		if args and args.transfer and GlobalStorageSiK.ItemNetworkTooltip and GlobalStorageSiK.ItemNetworkTooltip.invalidateAll then
			-- Cualquier deposito/retiro cambia cantidades en red: invalida la
			-- cache del tooltip global para que no siga mostrando el numero
			-- de antes de la transferencia.
			GlobalStorageSiK.ItemNetworkTooltip.invalidateAll()
		end
		if continuing then
			GlobalStorageSiK.Log.detail("Client", "actionResult batch", resolvedMessage or "")
		else
			GlobalStorageSiK.Debug.log("Client", "actionResult", resolvedMessage or "")
		end
		local player = GlobalStorageSiK.NetClient.getPlayer()
		if player and player.getInventory then
			local inv = player:getInventory()
			if inv and inv.setDrawDirty then
				inv:setDrawDirty(true)
			end
		end
		if ISInventoryPage and ISInventoryPage.dirtyUI then
			ISInventoryPage.dirtyUI()
		end
		if args and not args.ok then
			GlobalStorageSiK.Log.debug("Client", "actionResult failed", resolvedMessage)
		end
		if GlobalStorageSiK.TerminalBlockedUI and GlobalStorageSiK.TerminalBlockedUI.instance then
			local player = GlobalStorageSiK.NetClient.getPlayer()
			if player and GlobalStorageSiK.TerminalRecipes then
				local ok, state = pcall(GlobalStorageSiK.TerminalRecipes.serializeForClient, player)
				if ok and state and GlobalStorageSiK.TerminalBlockedUI.refresh then
					GlobalStorageSiK.TerminalBlockedUI.refresh(state)
				end
			end
		end
		local termUi = GlobalStorageSiK.TerminalUI and GlobalStorageSiK.TerminalUI.instance
		if termUi and termUi.getIsVisible and termUi:isVisible() then
			if termUi.refreshCraftRecipesState then
				termUi:refreshCraftRecipesState()
			end
			if termUi.refreshAddonRecipesState then
				termUi:refreshAddonRecipesState()
			end
			if termUi.activeTabKey == "addons" and termUi.addonsPanel and GlobalStorageSiK.TerminalAddons then
				GlobalStorageSiK.TerminalAddons.refresh(termUi.addonsPanel, termUi)
			end
		end
		if GlobalStorageSiK.TerminalInstallChoice and GlobalStorageSiK.TerminalInstallChoice.onCraftResult then
			GlobalStorageSiK.TerminalInstallChoice.onCraftResult(args)
		end
		if args and args.ok and GlobalStorageSiK.TerminalPlacement
			and GlobalStorageSiK.TerminalPlacement.isTerminalOutputRecipe(args.recipeId) then
			if args.recipeId == "terminal_unit" then
				local blockedUi = GlobalStorageSiK.TerminalUI and GlobalStorageSiK.TerminalUI.instance
				if blockedUi and blockedUi.accessMode == "blocked" and blockedUi.applyRefreshIfNeeded then
					blockedUi:applyRefreshIfNeeded(true)
				end
			end
			local player = GlobalStorageSiK.NetClient.getPlayer()
			if player and GlobalStorageSiK.TerminalPlacement.offerAfterTerminalOutput then
				GlobalStorageSiK.TerminalPlacement.offerAfterTerminalOutput(player, {})
			end
		end
		if args and args.ok and args.containerUpdated then
			local node = nil
			local ui = GlobalStorageSiK.TerminalNodeEditor and GlobalStorageSiK.TerminalNodeEditor.instance
			if ui and ui.node and (not args.nodeId or ui.node.id == args.nodeId) then
				node = ui.node
				if args.displayName and args.displayName ~= "" then
					node.displayName = args.displayName
				end
			else
				local state = GlobalStorageSiK.Client and GlobalStorageSiK.Client.cachedTerminalState
				if state and state.nodes and args.nodeId then
					for i = 1, #state.nodes do
						if state.nodes[i].id == args.nodeId then
							node = state.nodes[i]
							break
						end
					end
				end
			end
			if node and GlobalStorageSiK.NodeNaming and GlobalStorageSiK.NodeNaming.applyToNode then
				GlobalStorageSiK.NodeNaming.applyToNode(node)
			end
		end
	elseif command == "terminalState" then
		local itemCount = args and args.items and #args.items or 0
		local explicitOpen = args and args.openUi == true
		local inventorySync = args and args.inventorySync == true
		local openSeq = args and args.openSeq
		-- Solo se descarta como "respuesta vieja" si sabemos POSITIVAMENTE que
		-- hay una petición más nueva todavía en vuelo (pendingTerminalOpen).
		-- Antes se descartaba por el mero hecho de no coincidir el openSeq,
		-- sin comprobar si de verdad venía algo más nuevo detrás - si por lo
		-- que sea el contador se desincronizaba (dos peticiones casi
		-- simultáneas, sesión SP donde cliente/servidor comparten proceso,
		-- etc.), esa respuesta se perdía para siempre y el terminal quedaba
		-- sin abrirse sin ningún aviso, con el servidor certificando "todo
		-- bien" en su log y el jugador viendo que no pasa nada. Si no hay
		-- nada pendiente, se acepta la respuesta igualmente Y se resincroniza
		-- el contador al valor que confirma el servidor, para no arrastrar el
		-- desajuste a la siguiente apertura.
		if explicitOpen and openSeq and GlobalStorageSiK.Client
			and GlobalStorageSiK.Client.terminalOpenSeq
			and openSeq ~= GlobalStorageSiK.Client.terminalOpenSeq then
			if GlobalStorageSiK.Client.pendingTerminalOpen then
				GlobalStorageSiK.Debug.log("Client", "terminalState", "ignored stale openSeq=" .. tostring(openSeq))
				return
			end
			GlobalStorageSiK.Debug.log("Client", "terminalState", "openSeq desync resync -> " .. tostring(openSeq))
			GlobalStorageSiK.Client.terminalOpenSeq = openSeq
		end
		if inventorySync then
			args = mergeInventorySyncState(args, GlobalStorageSiK.Client.cachedTerminalState)
		end
		local deferVisibleRefresh = false
		if GlobalStorageSiK.TerminalSync and GlobalStorageSiK.TerminalSync.onTerminalState then
			deferVisibleRefresh = GlobalStorageSiK.TerminalSync.onTerminalState(args, inventorySync) == true
		end
		if not deferVisibleRefresh then
			GlobalStorageSiK.Client.cachedTerminalState = args
		end
		if args and args.networkId and GlobalStorageSiK.Client then
			GlobalStorageSiK.Client.activeNetworkId = args.networkId
		end
		if args and args.networks and GlobalStorageSiK.Client then
			GlobalStorageSiK.Client.networkList = args.networks
		end
		if args and args.activeNetworkId and GlobalStorageSiK.Client then
			GlobalStorageSiK.Client.activeNetworkId = args.activeNetworkId
		end

		local ui = GlobalStorageSiK.TerminalUI and GlobalStorageSiK.TerminalUI.instance
		local uiVisible = ui ~= nil and (not ui.isVisible or ui:isVisible())
		GlobalStorageSiK.Client.pendingTerminalOpen = false

		local player = GlobalStorageSiK.NetClient.getPlayer()
		local networkId = args and args.networkId
			or (GlobalStorageSiK.Client and GlobalStorageSiK.Client.activeNetworkId)
			or GlobalStorageSiK.Network.getDefaultNetworkId()
		local needAccess = GlobalStorageSiK.Sandbox
			and GlobalStorageSiK.Sandbox.requireTerminalAccess
			and GlobalStorageSiK.Sandbox.requireTerminalAccess()

		if needAccess and explicitOpen and player and GlobalStorageSiK.TerminalAccess.validateServerOpen then
			local trustServer = GlobalStorageSiK.TerminalAccess.trustServerForOpen
				and GlobalStorageSiK.TerminalAccess.trustServerForOpen()
			local serverConfirmed = args and args.terminalAnchor and args.accessMode
			if not (trustServer and serverConfirmed) then
				local accessOk, _, _, accessReason = GlobalStorageSiK.TerminalAccess.validateServerOpen(
					player, networkId, args
				)
				if not accessOk and (uiVisible or explicitOpen) then
					if GlobalStorageSiK.TerminalAccess.clearSession then
						GlobalStorageSiK.TerminalAccess.clearSession(player)
					end
					if GlobalStorageSiK.TerminalUI.showBlocked then
						GlobalStorageSiK.TerminalUI.showBlocked(accessReason or "terminal_out_of_range")
					end
					return
				end
			end
		end

		if explicitOpen and player and args and args.terminalAnchor and GlobalStorageSiK.TerminalAccess.setSessionAnchor then
			GlobalStorageSiK.TerminalAccess.setSessionAnchor(player, args.terminalAnchor, args.accessMode, args.networkId)
			if GlobalStorageSiK.TerminalManifest and GlobalStorageSiK.TerminalManifest.rememberTerminal then
				local anchor = {
					x = args.terminalAnchor.x,
					y = args.terminalAnchor.y,
					z = args.terminalAnchor.z or 0,
					networkId = args.networkId,
				}
				GlobalStorageSiK.TerminalManifest.rememberTerminal(player, anchor)
			end
		end

		if explicitOpen and args and args.accessMode then
			GlobalStorageSiK.Client.lastServerAccessMode = args.accessMode
		end

		if deferVisibleRefresh then
			GlobalStorageSiK.Log.detail("Client", "terminalState deferred during transfer",
				"items=" .. tostring(itemCount))
			if explicitOpen and not uiVisible and GlobalStorageSiK.Client.cachedTerminalState
				and GlobalStorageSiK.Client.cachedTerminalState.networkId == args.networkId
				and GlobalStorageSiK.TerminalUI and type(GlobalStorageSiK.TerminalUI.show) == "function" then
				-- Reabrir con el modelo local ya confirmado en lugar de restaurar el
				-- snapshot servidor anterior mientras termina la consolidación.
				GlobalStorageSiK.TerminalUI.show(GlobalStorageSiK.Client.cachedTerminalState)
			end
		elseif uiVisible then
			GlobalStorageSiK.Debug.log("Client", "terminalState", "refresh items=" .. tostring(itemCount))
			if GlobalStorageSiK.TerminalUI and type(GlobalStorageSiK.TerminalUI.show) == "function" then
				local ok, err = pcall(function()
					GlobalStorageSiK.TerminalUI.show(args)
				end)
				if not ok then
					GlobalStorageSiK.Log.error("Client", "TerminalUI.show", err)
					showMessage(GlobalStorageSiK.I18n.text("IGUI_GS_ClientTerminalUpdateError"))
				end
			end
		elseif explicitOpen then
			if GlobalStorageSiK.Client then
				GlobalStorageSiK.Client.lastTerminalOpenTime = (getTimestamp and getTimestamp()) or 0
			end
			GlobalStorageSiK.Log.info("Client", "terminalState", "open items=" .. tostring(itemCount))
			if not GlobalStorageSiK.TerminalUI or type(GlobalStorageSiK.TerminalUI.show) ~= "function" then
				GlobalStorageSiK.Log.error("Client", "TerminalUI.show no disponible")
				showMessage(GlobalStorageSiK.I18n.text("IGUI_GS_ClientTerminalOpenError"))
				return
			end
			local ok, err = pcall(function()
				GlobalStorageSiK.TerminalUI.show(args)
			end)
			if not ok then
				GlobalStorageSiK.Log.error("Client", "TerminalUI.show", err)
				showMessage(GlobalStorageSiK.I18n.text("IGUI_GS_ClientTerminalOpenError"))
			elseif GlobalStorageSiK.Client and GlobalStorageSiK.Client.pendingInitialTab then
				-- Ver terminalRegistered mas arriba: tras instalar un terminal
				-- con exito, la ventana debe abrir directamente en Red > Nodos
				-- en vez de en la pestaña por defecto (Almacen).
				local tabKey = GlobalStorageSiK.Client.pendingInitialTab
				GlobalStorageSiK.Client.pendingInitialTab = nil
				local ui = GlobalStorageSiK.TerminalUI.instance
				if ui and GlobalStorageSiK.TerminalTabs and GlobalStorageSiK.TerminalTabs.activate then
					GlobalStorageSiK.TerminalTabs.activate(ui, tabKey)
					if tabKey == "network" and GlobalStorageSiK.TerminalNetwork and GlobalStorageSiK.TerminalNetwork.activateSubTab then
						GlobalStorageSiK.TerminalNetwork.activateSubTab(ui, "nodos")
					end
				end
			end
		else
			GlobalStorageSiK.Debug.log("Client", "terminalState", "cached items=" .. tostring(itemCount))
		end
	elseif command == "nodeContents" then
		GlobalStorageSiK.Client.nodeContentsCache = GlobalStorageSiK.Client.nodeContentsCache or {}
		if args and args.nodeId then
			GlobalStorageSiK.Client.nodeContentsCache[args.nodeId] = args
		end
		if GlobalStorageSiK.TerminalConfig and GlobalStorageSiK.TerminalConfig.onNodeContentsReceived then
			GlobalStorageSiK.TerminalConfig.onNodeContentsReceived(args)
		end
	elseif command == "terminalManifest" then
		local player = GlobalStorageSiK.NetClient.getPlayer()
		if GlobalStorageSiK.TerminalManifest and GlobalStorageSiK.TerminalManifest.applyFromServer then
			GlobalStorageSiK.TerminalManifest.applyFromServer(player, args)
		elseif GlobalStorageSiK.Client then
			GlobalStorageSiK.Client.terminalManifest = args
		end
		GlobalStorageSiK.Debug.log("Client", "terminalManifest", "terminals=" .. tostring(args and args.terminals and #args.terminals or 0))
		local termUi = GlobalStorageSiK.TerminalUI and GlobalStorageSiK.TerminalUI.instance
		if termUi and termUi.refreshNetworkPanel and termUi:isVisible() then
			termUi:refreshNetworkPanel()
		end
	elseif command == "terminalRelocated" then
		-- Ya no se sustituye el item recogido por ningun GS_TerminalUnit
		-- canonico (sistema retirado) - recoger un terminal instalado
		-- siempre deja el PC vanilla normal en el inventario, a proposito.
	elseif command == "placementPrepared" then
		if args and args.ok then
			local player = GlobalStorageSiK.NetClient.getPlayer()
			if player and GlobalStorageSiK.TerminalPlacementIntent then
				GlobalStorageSiK.TerminalPlacementIntent.setIntent(player, {
					mode = args.mode,
					networkId = args.networkId,
					preparedAt = (getTimestampMs and getTimestampMs()) or 0,
				})
			end
		end
		if GlobalStorageSiK.TerminalPlacementChoice and GlobalStorageSiK.TerminalPlacementChoice.onPrepared then
			GlobalStorageSiK.TerminalPlacementChoice.onPrepared(args)
		end
	elseif command == "terminalRegisterFailed" then
		local reason = args and args.reason or "error"
		local msgKey = "IGUI_GS_TerminalRegisterFailed"
		if reason == "terminal_too_far" then
			msgKey = "IGUI_GS_TerminalTooFar"
		elseif reason == "terminal_limit" then
			msgKey = "IGUI_GS_TerminalLimit"
		elseif reason == "not_a_computer" then
			msgKey = "IGUI_GS_InstallReaderNotComputer"
		elseif reason == "already_installed" then
			msgKey = "IGUI_GS_InstallReaderAlreadyInstalled"
		elseif reason == "missing_items" then
			msgKey = "IGUI_GS_InstallReaderMissingItems"
		elseif reason == "out_of_network_range" then
			msgKey = "IGUI_GS_TerminalOutOfNetworkRange"
		end
		showMessage(GlobalStorageSiK.I18n.text(msgKey))
	elseif command == "terminalRegistered" then
		if args and args.ok and args.networkId then
			local player = GlobalStorageSiK.NetClient.getPlayer()
			if player and GlobalStorageSiK.TerminalAccess and GlobalStorageSiK.TerminalAccess.setSessionAnchor then
				GlobalStorageSiK.TerminalAccess.setSessionAnchor(player, {
					x = args.x,
					y = args.y,
					z = args.z or 0,
					networkId = args.networkId,
				}, "physical", args.networkId)
			end
			if player and GlobalStorageSiK.TerminalPlacementIntent then
				GlobalStorageSiK.TerminalPlacementIntent.consumeIntent(player)
			end
			-- Aviso SIEMPRE (antes solo en modo "new" - unirse a una red ya
			-- existente se quedaba sin ningún mensaje de confirmación, un
			-- vacío informativo tras una acción que sí tuvo éxito).
			if player and player.setHaloNote then
				local msgKey = args.mode == "new" and "IGUI_GS_TerminalInstalledNew" or "IGUI_GS_TerminalInstalledJoined"
				player:setHaloNote(GlobalStorageSiK.I18n.text(msgKey, args.networkId), 180, 220, 160, 350)
			end
			-- Refrescar lista de redes para que el estado del selector (suspendido/activo) sea correcto.
			if GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.sendCommand then
				GlobalStorageSiK.NetClient.sendCommand("getNetworkList", {})
			end
			-- Abre el mod directamente en Red > Nodos tras instalar con éxito,
			-- para que el jugador pueda crear su primera zona sin tener que
			-- buscar el botón de acceso ni la pestaña él mismo. El cambio de
			-- pestaña real ocurre en el handler de "terminalState" de más
			-- abajo (ahí es donde la ventana ya existe de verdad), este flag
			-- solo marca la intención.
			GlobalStorageSiK.Client.pendingInitialTab = "network"
			if GlobalStorageSiK.TerminalUI and GlobalStorageSiK.TerminalUI.requestOpen then
				GlobalStorageSiK.TerminalUI.requestOpen()
			end
		end
	elseif command == "recoveryNetworks" then
		if not GlobalStorageSiK.Client then
			GlobalStorageSiK.Client = {}
		end
		GlobalStorageSiK.Client.recoveryNetworks = args and args.networks
		if GlobalStorageSiK.TerminalPlacementChoice and GlobalStorageSiK.TerminalPlacementChoice.onNetworksReceived then
			GlobalStorageSiK.TerminalPlacementChoice.onNetworksReceived(args and args.networks or {})
		end
		if GlobalStorageSiK.TerminalInstallReaderChoice and GlobalStorageSiK.TerminalInstallReaderChoice.onNetworksReceived then
			GlobalStorageSiK.TerminalInstallReaderChoice.onNetworksReceived(args and args.networks or {})
		end
		if GlobalStorageSiK.TerminalBlockedPanel and GlobalStorageSiK.TerminalBlockedPanel.onNetworksReceived then
			GlobalStorageSiK.TerminalBlockedPanel.onNetworksReceived(args and args.networks or {})
		end
	elseif command == "itemNetworkCounts" then
		if GlobalStorageSiK.ItemNetworkTooltip and GlobalStorageSiK.ItemNetworkTooltip.onCountsReceived then
			GlobalStorageSiK.ItemNetworkTooltip.onCountsReceived(args and args.fullType, args and args.networks or {}, args and args.hasAnyNetwork)
		end
	elseif command == "networkList" then
		if not GlobalStorageSiK.Client then
			GlobalStorageSiK.Client = {}
		end
		GlobalStorageSiK.Client.networkList = args and args.networks or {}
		GlobalStorageSiK.Client.activeNetworkId = args and args.activeNetworkId or nil
		local mainUi = GlobalStorageSiK.TerminalUI and GlobalStorageSiK.TerminalUI.instance
		if mainUi and mainUi.refreshNetworkPanel then
			mainUi:refreshNetworkPanel()
		end
	elseif command == "activeNetworkSet" then
		if args and args.ok and args.networkId and GlobalStorageSiK.Client then
			GlobalStorageSiK.Client.activeNetworkId = args.networkId
		end
		local mainUi = GlobalStorageSiK.TerminalUI and GlobalStorageSiK.TerminalUI.instance
		if mainUi and mainUi.refreshNetworkPanel then
			mainUi:refreshNetworkPanel()
		end
	elseif command == "networkCreated" then
		if args and args.ok and args.networkId then
			if not GlobalStorageSiK.Client then
				GlobalStorageSiK.Client = {}
			end
			GlobalStorageSiK.Client.activeNetworkId = args.networkId
			showMessage(GlobalStorageSiK.I18n.text("IGUI_GS_NetworkCreated", args.networkId))
			GlobalStorageSiK.NetClient.sendCommand("getNetworkList", {})
		end
	elseif command == "terminalBlocked" then
		local trustServer = GlobalStorageSiK.TerminalAccess
			and GlobalStorageSiK.TerminalAccess.trustServerForOpen
			and GlobalStorageSiK.TerminalAccess.trustServerForOpen()
		if trustServer and GlobalStorageSiK.Client and GlobalStorageSiK.Client.lastTerminalOpenTime then
			local now = (getTimestamp and getTimestamp()) or 0
			local mainUi = GlobalStorageSiK.TerminalUI and GlobalStorageSiK.TerminalUI.instance
			local mainVisible = mainUi and mainUi.getIsVisible and mainUi:isVisible()
			local hadState = GlobalStorageSiK.Client.cachedTerminalState ~= nil
			if (mainVisible or hadState) and now - GlobalStorageSiK.Client.lastTerminalOpenTime < 1.5 then
				GlobalStorageSiK.Debug.log("Client", "terminalBlocked", "ignored race after open reason=" .. tostring(args and args.reason))
				return
			end
		end
		GlobalStorageSiK.Client.pendingTerminalOpen = false
		GlobalStorageSiK.Client.cachedTerminalState = nil
		local player = GlobalStorageSiK.NetClient.getPlayer()
		if player and GlobalStorageSiK.TerminalAccess and GlobalStorageSiK.TerminalAccess.clearSession then
			GlobalStorageSiK.TerminalAccess.clearSession(player)
		end
		if GlobalStorageSiK.TransferQueue and GlobalStorageSiK.TransferQueue.clear then
			GlobalStorageSiK.TransferQueue.clear()
		end
		if GlobalStorageSiK.WithdrawClient and GlobalStorageSiK.WithdrawClient.cancelAll then
			GlobalStorageSiK.WithdrawClient.cancelAll()
		end
		GlobalStorageSiK.Log.info("Client", "terminalBlocked", args and args.reason or "no_access")
		local payload = args or {}
		local player = GlobalStorageSiK.NetClient.getPlayer()
		if player and GlobalStorageSiK.TerminalRecipes then
			local ok, enriched = pcall(GlobalStorageSiK.TerminalRecipes.serializeForClient, player, { blockedOnly = true })
			if ok and enriched then
				enriched.reason = payload.reason or enriched.reason
				enriched.proximityRange = payload.proximityRange or enriched.proximityRange
				enriched.wirelessRange = payload.wirelessRange or enriched.wirelessRange
				payload = enriched
			end
		end
		local rect
		local mainUi = GlobalStorageSiK.TerminalUI and GlobalStorageSiK.TerminalUI.instance
		if mainUi and mainUi.getIsVisible and mainUi:isVisible() then
			rect = { x = mainUi:getX(), y = mainUi:getY(), w = mainUi:getWidth(), h = mainUi:getHeight() }
		end
		if GlobalStorageSiK.TerminalUI and GlobalStorageSiK.TerminalUI.showBlocked then
			GlobalStorageSiK.TerminalUI.showBlocked(payload.reason, rect)
			if GlobalStorageSiK.TerminalBlockedUI and GlobalStorageSiK.TerminalBlockedUI.refresh then
				GlobalStorageSiK.TerminalBlockedUI.refresh(payload)
			end
		else
			showMessage(GlobalStorageSiK.I18n.text("IGUI_GS_BlockedTitle"))
		end
	elseif command == "itemIndex" then
		GlobalStorageSiK.Client.lastItemIndex = args and args.index or {}
		local count = 0
		for _ in pairs(GlobalStorageSiK.Client.lastItemIndex) do
			count = count + 1
		end
		showMessage(GlobalStorageSiK.I18n.text("IGUI_GS_ItemTypes", count))
	end
end

GlobalStorageSiK.Client = GlobalStorageSiK.Client or {}
GlobalStorageSiK.Client.lastItemIndex = {}
GlobalStorageSiK.Client.cachedTerminalState = nil
GlobalStorageSiK.Client.nodeContentsCache = {}
GlobalStorageSiK.Client.pendingTerminalOpen = false
GlobalStorageSiK.Client.lastTerminalOpenTime = 0
GlobalStorageSiK.Client.terminalOpenSeq = 0
GlobalStorageSiK.Client.terminalManifest = nil
GlobalStorageSiK.Client.activeNetworkId = nil

Events.OnServerCommand.Add(onServerCommand)

--- Expuesto para GS_Server.lua: en SP real, sendServerCommand()/
--- Events.OnServerCommand NO entregan nada (confirmado con traza completa -
--- la llamada "tiene exito" segun pcall pero el cliente jamas la recibe,
--- ningun comando, ni siquiera debugEcho; en MP real cada envio SI llega).
--- Mismo motivo de fondo que el crash de getAccessLevel() en
--- SiKCorpseLootGuard: en SP real no existe GameClient.connection, y las
--- APIs de red vanilla que dependen de esa conexion fallan (con excepcion,
--- o aqui, en silencio) - no es arreglable desde nuestro lado del canal.
--- La solucion es no usar el canal de red en absoluto en SP real: llamar
--- a esta funcion directamente, en el mismo proceso, con los mismos
--- argumentos que recibiria via Events.OnServerCommand.
GlobalStorageSiK.Client.dispatchServerCommand = onServerCommand
