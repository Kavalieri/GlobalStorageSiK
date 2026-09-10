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
require "GS_NativeWorldSync"
require "GS_UI_Feedback"
require "GS_RemoteItemDetail"
require "GS_Debug"
require "GS_NetTrace"
require "GS_Sandbox"

require "GS_NodeNaming"
require "GS_I18n"

local itemDetailsOrder = {}
local nodeContentsOrder = {}
local transientCleanupHandlers = {}
local MAX_ITEM_DETAIL_PAGES = 128
local MAX_NODE_CONTENT_ENTRIES = 128

local function storeBounded(cache, order, key, value, limit)
	if not key then return end
	if cache[key] == nil then
		order[#order + 1] = key
		if #order > limit then
			local oldest = table.remove(order, 1)
			if oldest then cache[oldest] = nil end
		end
	end
	cache[key] = value
end

local function terminalUiForPlayer(playerNum)
	if GlobalStorageSiK.TerminalUI and GlobalStorageSiK.TerminalUI.getInstanceForPlayer then
		return GlobalStorageSiK.TerminalUI.getInstanceForPlayer(playerNum)
	end
	return GlobalStorageSiK.TerminalUI and GlobalStorageSiK.TerminalUI.instance or nil
end

local function staleTerminalOpen(payload)
	if not payload or payload.openSeq == nil then return false end
	local playerNum = tonumber(payload.playerNum) or 0
	local sequences = GlobalStorageSiK.Client and GlobalStorageSiK.Client.terminalOpenSeqByPlayer
	local expected = sequences and sequences[playerNum]
	-- All physical/remote callers now allocate per-player sequences before send,
	-- including synchronous SP. The old global-counter desync workaround could
	-- revive an older open after the newer request had already completed.
	return expected ~= nil and tonumber(payload.openSeq) ~= expected
end

--- Fallos relevantes: halo breve. Información: estado de la UI del destinatario.
---@param text string|nil
---@param failed boolean|nil
local function showMessage(text, failed, playerNum)
	playerNum = tonumber(playerNum) or 0
	local player = getSpecificPlayer and getSpecificPlayer(playerNum)
	if not player and playerNum == 0 then
		player = GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer() or getPlayer()
	end
	if player and text then
		if failed then
			GlobalStorageSiK.UIFeedback.halo(player, tostring(text), 235, 90, 90, 1200,
				{ tone = "danger", playerNum = playerNum })
		else
			GlobalStorageSiK.UIFeedback.halo(player, tostring(text), 220, 220, 220, 300)
		end
	end
end

---@param args table|nil
---@return boolean
--- Fusiona terminalState parcial de inventario con el estado cacheado previo.
---@param incoming table|nil
---@param prev table|nil
---@return table|nil
local function mergeInventorySyncState(incoming, prev)
	if not incoming or not incoming.inventorySync or not prev
		or incoming.networkId ~= prev.networkId then
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

local function inventoryCatalogKey(playerNum, networkId)
	return tostring(tonumber(playerNum) or 0) .. "\30" .. tostring(networkId or "")
end

local function applyInventoryCatalog(incoming, playerNum)
	if not incoming or not incoming.networkId then return incoming end
	-- This private stamp describes actual catalog contents, not a generic
	-- state/ACK revision. A failed notModified restore must not inherit it.
	incoming._gsAppliedCatalogRevision = -1
	GlobalStorageSiK.Client.inventoryCatalogByPlayerNetwork =
		GlobalStorageSiK.Client.inventoryCatalogByPlayerNetwork or {}
	local key = inventoryCatalogKey(playerNum, incoming.networkId)
	local cached = GlobalStorageSiK.Client.inventoryCatalogByPlayerNetwork[key]
	if incoming.notModified == true then
		if cached and cached.inventoryRevision == incoming.inventoryRevision
			and cached.catalogScope == incoming.catalogScope then
			incoming.items = cached.items
			incoming.itemTypeCount = cached.itemTypeCount
			incoming.catalogRestored = true
			incoming._gsAppliedCatalogRevision = incoming.inventoryRevision
		end
	elseif type(incoming.items) == "table" and incoming.inventoryRevision ~= nil
		and type(incoming.catalogScope) == "string" then
		GlobalStorageSiK.Client.inventoryCatalogByPlayerNetwork[key] = {
			playerNum = tonumber(playerNum) or 0,
			networkId = incoming.networkId,
			items = incoming.items,
			itemTypeCount = incoming.itemTypeCount or #incoming.items,
			inventoryRevision = incoming.inventoryRevision,
			catalogScope = incoming.catalogScope,
		}
		incoming._gsAppliedCatalogRevision = incoming.inventoryRevision
	end
	return incoming
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
safeRequire("GS_DisplayCategoryPublisher")
safeRequire("GS_VanillaInventoryTaxonomy")
if GlobalStorageSiK.VanillaInventoryTaxonomy and GlobalStorageSiK.VanillaInventoryTaxonomy.installHooks then
	GlobalStorageSiK.VanillaInventoryTaxonomy.installHooks()
end
safeRequire("GS_CleanUIInventoryTaxonomy")

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
	if GlobalStorageSiK.NativeWorldSync and GlobalStorageSiK.NativeWorldSync.onCommand(command, args) then return end

	if command == "terminalAccessResult" then
		if GlobalStorageSiK.TerminalAccessGuard then
			GlobalStorageSiK.TerminalAccessGuard.acceptResponse(args, args and args.ok == true)
		end
	elseif command == "scanProgress" then
		local playerNum = tonumber(args and args.playerNum) or 0
		local ui = terminalUiForPlayer(playerNum)
		if ui and ui.accessMode ~= "blocked" and (not ui.isVisible or ui:isVisible())
			and ui._gsAccessState ~= "revoking" and ui._gsAccessState ~= "revalidating"
			and ui.terminalState and args
			and ui.terminalState.networkId == args.networkId then
			ui.terminalState.scanActive = args.state == "RUNNING" or args.state == "STALE_RETRY"
			ui.terminalState.scanStatus = args
			if args.snapshotAgeMs ~= nil then ui.terminalState.snapshotAgeMs = args.snapshotAgeMs end
			if ui.syncHeaderChrome then ui:syncHeaderChrome() end
			local now = getTimestampMs and getTimestampMs() or 0
			local panel = ui.networkPanel
			if panel and panel._sikNetworkSurface and panel.isVisible and panel:isVisible()
				and now >= (ui._gsScanStatusRefreshMs or 0)
				and GlobalStorageSiK.TerminalNetwork and GlobalStorageSiK.TerminalNetwork.refreshActiveTab then
				ui._gsScanStatusRefreshMs = now + 1000
				GlobalStorageSiK.TerminalNetwork.refreshActiveTab(ui, ui.terminalState)
			end
		end
		return
	elseif command == "actionResult" then
        -- Deposit batches also own their ACKs. A duplicate/retired response must
        -- not apply the same delta again or repaint a different gesture.
        if args and args.queueId and GlobalStorageSiK.TransferQueue
            and not GlobalStorageSiK.TransferQueue.isResponseExpected(args) then return end
		-- A retired/duplicate withdrawal ACK must not repaint another gesture's
		-- progress or apply its inventory delta twice. Server snapshots still reconcile.
		if args and args.withdrawId and GlobalStorageSiK.WithdrawClient
			and not GlobalStorageSiK.WithdrawClient.isResponseExpected(args) then return end
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
		local transferFeedback = (require "GS_TransferFeedback").showResult(args)
		if GlobalStorageSiK.ContainerInventory then GlobalStorageSiK.ContainerInventory.onActionResult(args) end
		if GlobalStorageSiK.TerminalSync and GlobalStorageSiK.TerminalSync.onActionResult then
			GlobalStorageSiK.TerminalSync.onActionResult(args)
		end
		if GlobalStorageSiK.AdminDashboard and GlobalStorageSiK.AdminDashboard.onActionResult then
			GlobalStorageSiK.AdminDashboard.onActionResult(args)
		end
		-- Cada cola consume exclusivamente su operation ID. Una respuesta de
		-- otra acción nunca libera ni hace avanzar depósitos o retiradas.
		if not continuing and not transferFeedback then
			local failed = args and args.ok == false
			local reason = args and (args.reason or args.transfer and args.transfer.reason)
			if reason == "cancelled" or reason == "snapshot_stale" or reason == "selection_stale" then
				failed = false
			end
			showMessage(resolvedMessage, failed, args and args.playerNum)
		end
		if args and args.jobType == "redistribute" then
			if args.jobState == "finished" and (args.redistributeTiers or args.redistributeTopTypes) then
				GlobalStorageSiK.Log.info("RedistributeJob", "completed breakdown",
					"tiers=" .. tostring(args.redistributeTiers or "none")
						.. " topTypes=" .. tostring(args.redistributeTopTypes or "none"))
			end
			local ui = GlobalStorageSiK.TerminalUI and GlobalStorageSiK.TerminalUI.instance
			if ui and args.jobState == "running" and ui.onRedistributeStarted then
				ui:onRedistributeStarted(resolvedMessage, {
					phase = args.progressPhase, checked = args.progressChecked,
					total = args.progressTotal, moved = args.progressMoved,
				})
			elseif ui and ui.onRedistributeFinished then
				-- Compatibilidad: una respuesta final de una version anterior del
				-- servidor no llevaba jobState y se interpreta como finalizada.
				ui:onRedistributeFinished(args.ok == true, resolvedMessage)
			end
		end
		if args and args.jobType == "zoneScan" then
			local ui = terminalUiForPlayer(tonumber(args.playerNum) or 0)
			if ui and ui.terminalState and ui.terminalState.networkId == args.networkId then
				local scanState = args.jobState or "IDLE"
				local running = scanState == "RUNNING" or scanState == "STALE_RETRY"
					or scanState == "INVALIDATED_BY_MUTATION"
				ui.terminalState.scanActive = running
				ui.terminalState.scan = ui.terminalState.scan or {}
				ui.terminalState.scan.running = running
				ui.terminalState.scanStatus = args.scanStatus or ui.terminalState.scanStatus or {}
				ui.terminalState.scanStatus.state = scanState
				ui.terminalState.scanStatus.reason = args.reason or ui.terminalState.scanStatus.reason
				ui.terminalState.scanStatus.reasonCode = args.reasonCode or ui.terminalState.scanStatus.reasonCode
				ui.terminalState.scanStatus.failedZones = args.failedZones or ui.terminalState.scanStatus.failedZones or 0
				ui.terminalState.scanStatus.snapshotCertified = args.snapshotCertified == true
				if ui.syncHeaderChrome then ui:syncHeaderChrome() end
				if scanState ~= "RUNNING" and args.ok == false and ui.setHeaderTransient then
					ui:setHeaderTransient(resolvedMessage, "danger", 5200)
				end
				if GlobalStorageSiK.TerminalNetwork and GlobalStorageSiK.TerminalNetwork.refreshActiveTab then
					GlobalStorageSiK.TerminalNetwork.refreshActiveTab(ui, ui.terminalState)
				end
			end
		end
		if args and args.ok and GlobalStorageSiK.TerminalNodeEditor
			and GlobalStorageSiK.TerminalNodeEditor.instance then
			if args.rebindCandidates then
				GlobalStorageSiK.TerminalNodeEditor.instance:showRebindCandidates(args)
			elseif args.rebindProposal then
				GlobalStorageSiK.TerminalNodeEditor.instance:confirmRebindProposal(args)
			elseif args.configTransferProposal then
				GlobalStorageSiK.TerminalNodeEditor.instance:confirmConfigTransferProposal(args)
			end
		end
		if args and args.transfer and GlobalStorageSiK.ItemNetworkTooltip and GlobalStorageSiK.ItemNetworkTooltip.invalidateAll then
			-- Cualquier deposito/retiro cambia cantidades en red: invalida la
			-- cache del tooltip global para que no siga mostrando el numero
			-- de antes de la transferencia.
			GlobalStorageSiK.ItemNetworkTooltip.invalidateAll()
		end
		local transfer = args and args.transfer
		if transfer and transfer.networkId and transfer.inventoryRevision
			and GlobalStorageSiK.RemoteItemDetail
			and GlobalStorageSiK.RemoteItemDetail.invalidateNetwork then
			-- El detalle exacto se identifica por revision. Invalidar en el ACK
			-- evita conservar una unidad retirada/depositada mientras llega el
			-- terminalState de sincronizacion.
			GlobalStorageSiK.RemoteItemDetail.invalidateNetwork(transfer.networkId)
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
		if staleTerminalOpen(args) then return end
		-- A confirmation can arrive after movement. Check geometry only, before
		-- applying catalogs; do not re-read stale local terminal/antenna caches.
		if args and args.openUi == true and GlobalStorageSiK.Sandbox.requireTerminalAccess()
			and GlobalStorageSiK.TerminalAccess.evaluateConfirmedAnchor then
			local n = tonumber(args.playerNum) or 0
			local confirmedPlayer = GlobalStorageSiK.NetClient.getPlayer(n)
			local allowed, _, reason = GlobalStorageSiK.TerminalAccess.evaluateConfirmedAnchor(
				confirmedPlayer, args.terminalAnchor, args.confirmedProximityRange, args.confirmedWirelessRange)
			if not allowed then
				local client = GlobalStorageSiK.Client
				if GlobalStorageSiK.TerminalUI.cancelPendingOpen then
					GlobalStorageSiK.TerminalUI.cancelPendingOpen(n)
				end
				if client.pendingTerminalOpenByPlayer then client.pendingTerminalOpenByPlayer[n] = nil end
				if n == 0 then
					client.pendingTerminalOpen = false
					client.cachedTerminalState = nil
				end
				if client.terminalStateByPlayer then client.terminalStateByPlayer[n] = nil end
				if GlobalStorageSiK.TerminalAccessGuard then
					GlobalStorageSiK.TerminalAccessGuard.acceptResponse({playerNum=n}, false)
				end
				if confirmedPlayer then
					GlobalStorageSiK.TerminalAccess.clearSession(confirmedPlayer)
					GlobalStorageSiK.NetClient.sendCommand("closeTerminal", {networkId=args.networkId}, confirmedPlayer)
				end
				if GlobalStorageSiK.TerminalUI.showBlocked then
					GlobalStorageSiK.TerminalUI.showBlocked({playerNum=n, networkId=args.networkId,
						reason=reason or "terminal_out_of_range"})
				end
				return
			end
		end
		if GlobalStorageSiK.TerminalAccessGuard
			and not GlobalStorageSiK.TerminalAccessGuard.acceptResponse(args, true) then return end
		local playerNum = tonumber(args and args.playerNum) or 0
		args = applyInventoryCatalog(args, playerNum)
		GlobalStorageSiK.Client.terminalStateByPlayer =
			GlobalStorageSiK.Client.terminalStateByPlayer or {}
		local previousState = GlobalStorageSiK.Client.terminalStateByPlayer[playerNum]
		local itemCount = args and args.items and #args.items or 0
		for i = 1, math.min(itemCount, 3) do
			local row = args.items[i]
			GlobalStorageSiK.NativeProduct.tracePathSample("clientReceive", row.fullType, row.nativePath)
		end
		local explicitOpen = args and args.openUi == true
		local inventorySync = args and args.inventorySync == true
		if explicitOpen and GlobalStorageSiK.TerminalUI
			and GlobalStorageSiK.TerminalUI.onRemoteOpenResult then
			GlobalStorageSiK.TerminalUI.onRemoteOpenResult(args, true)
		end
		if inventorySync then
			args = mergeInventorySyncState(args, previousState)
		end
		-- selection_stale conserva el gesto exact_group en espera de este
		-- terminalState autoritativo. La reanudación es de una sola vez y sucede
		-- antes de cualquier reconstrucción visual; no depende de páginas ni de
		-- que la ventana llegue a repintarse.
		if GlobalStorageSiK.WithdrawClient
			and GlobalStorageSiK.WithdrawClient.onTerminalState then
			GlobalStorageSiK.WithdrawClient.onTerminalState(args)
		end
		if args and args.networkId and args.inventoryRevision ~= nil
			and (not previousState
				or previousState.networkId ~= args.networkId
				or previousState.inventoryRevision ~= args.inventoryRevision)
			and GlobalStorageSiK.RemoteItemDetail
			and GlobalStorageSiK.RemoteItemDetail.invalidateNetwork then
			GlobalStorageSiK.RemoteItemDetail.invalidateNetwork(args.networkId)
		end
		if args and args.networkId and args.inventoryRevision ~= nil
			and (not previousState
				or previousState.networkId ~= args.networkId
				or previousState.inventoryRevision ~= args.inventoryRevision) then
			-- itemDetails lleva revision y puede conservar su pagina visual stale e
			-- inerte hasta la reconsulta. nodeContents se indexa solo por nodeId: se
			-- invalida siempre para no editar capacidad/ruta contra datos antiguos.
			GlobalStorageSiK.Client.nodeContentsCache = {}
			nodeContentsOrder = {}
			-- Conservar la pagina de itemDetails evita colapsar
			-- grupos mientras llega la nueva y libera solo el pending de los grupos
			-- expandidos para una unica reconsulta.
			if GlobalStorageSiK.TerminalItems
				and GlobalStorageSiK.TerminalItems.onInventoryRevisionChanged then
				GlobalStorageSiK.TerminalItems.onInventoryRevisionChanged(args.networkId, playerNum)
			end
		end
		local deferVisibleRefresh = false
		if GlobalStorageSiK.TerminalSync and GlobalStorageSiK.TerminalSync.onTerminalState then
			deferVisibleRefresh = GlobalStorageSiK.TerminalSync.onTerminalState(args, inventorySync) == true
		end
		if not deferVisibleRefresh then
			GlobalStorageSiK.Client.terminalStateByPlayer[playerNum] = args
			if GlobalStorageSiK.ContainerInventory then GlobalStorageSiK.ContainerInventory.onTerminalState(args) end
			local currentUi = terminalUiForPlayer(playerNum)
			local currentPlayerNum = currentUi and tonumber(currentUi.playerNum) or 0
			if currentPlayerNum == playerNum then
				GlobalStorageSiK.Client.cachedTerminalState = args
			end
		end
		if args and args.networkId and GlobalStorageSiK.Client then
			GlobalStorageSiK.Client.activeNetworkIdByPlayer[playerNum] = args.networkId
			if playerNum == 0 then GlobalStorageSiK.Client.activeNetworkId = args.networkId end
		end
		if args and args.networks and GlobalStorageSiK.Client then
			GlobalStorageSiK.Client.networkList = args.networks
		end
		if args and args.activeNetworkId and GlobalStorageSiK.Client then
			GlobalStorageSiK.Client.activeNetworkIdByPlayer[playerNum] = args.activeNetworkId
			if playerNum == 0 then GlobalStorageSiK.Client.activeNetworkId = args.activeNetworkId end
		end

		local ui = terminalUiForPlayer(playerNum)
		local uiVisible = ui ~= nil and (not ui.isVisible or ui:isVisible())
		if explicitOpen then
			if playerNum == 0 then GlobalStorageSiK.Client.pendingTerminalOpen = false end
			if GlobalStorageSiK.Client.pendingTerminalOpenByPlayer then
				GlobalStorageSiK.Client.pendingTerminalOpenByPlayer[playerNum] = nil
			end
		end

		local player = GlobalStorageSiK.NetClient.getPlayer(playerNum)
		local networkId = args and args.networkId
			or (GlobalStorageSiK.Client and GlobalStorageSiK.Client.activeNetworkIdByPlayer
				and GlobalStorageSiK.Client.activeNetworkIdByPlayer[playerNum])
			or (playerNum == 0 and GlobalStorageSiK.Client and GlobalStorageSiK.Client.activeNetworkId)
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
					GlobalStorageSiK.TerminalUI.showBlocked({
						playerNum = playerNum,
						reason = accessReason or "terminal_out_of_range",
					})
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
			local playerState = GlobalStorageSiK.Client.terminalStateByPlayer[playerNum]
			if explicitOpen and not uiVisible and playerState
				and playerState.networkId == args.networkId
				and GlobalStorageSiK.TerminalUI and type(GlobalStorageSiK.TerminalUI.show) == "function" then
				-- Reabrir con el modelo local ya confirmado en lugar de restaurar el
				-- snapshot servidor anterior mientras termina la consolidación.
				GlobalStorageSiK.TerminalUI.show(playerState)
			end
		elseif uiVisible then
			GlobalStorageSiK.Debug.log("Client", "terminalState", "refresh items=" .. tostring(itemCount))
			if GlobalStorageSiK.TerminalUI and type(GlobalStorageSiK.TerminalUI.show) == "function" then
				local ok, err = pcall(function()
					GlobalStorageSiK.TerminalUI.show(args)
				end)
				if not ok then
					GlobalStorageSiK.Log.error("Client", "TerminalUI.show", err)
					showMessage(GlobalStorageSiK.I18n.text("IGUI_GS_ClientTerminalUpdateError"), true)
				end
			end
		elseif explicitOpen then
			if GlobalStorageSiK.Client then
			end
			GlobalStorageSiK.Log.info("Client", "terminalState", "open items=" .. tostring(itemCount))
			if not GlobalStorageSiK.TerminalUI or type(GlobalStorageSiK.TerminalUI.show) ~= "function" then
				GlobalStorageSiK.Log.error("Client", "TerminalUI.show no disponible")
				showMessage(GlobalStorageSiK.I18n.text("IGUI_GS_ClientTerminalOpenError"), true)
				return
			end
			local ok, err = pcall(function()
				GlobalStorageSiK.TerminalUI.show(args)
			end)
			if not ok then
				GlobalStorageSiK.Log.error("Client", "TerminalUI.show", err)
				showMessage(GlobalStorageSiK.I18n.text("IGUI_GS_ClientTerminalOpenError"), true)
			elseif GlobalStorageSiK.Client and GlobalStorageSiK.Client.pendingInitialTab then
				-- Ver terminalRegistered mas arriba: tras instalar un terminal
				-- con exito, la ventana debe abrir directamente en Red (dev41:
				-- Red ya ES "Zonas y nodos" directamente, sin sub-pestañas -
				-- antes hacia falta un activateSubTab(ui, "nodos") aparte).
				local tabKey = GlobalStorageSiK.Client.pendingInitialTab
				GlobalStorageSiK.Client.pendingInitialTab = nil
				local ui = GlobalStorageSiK.TerminalUI.instance
				if ui and GlobalStorageSiK.TerminalTabs and GlobalStorageSiK.TerminalTabs.activate then
					GlobalStorageSiK.TerminalTabs.activate(ui, tabKey)
				end
			end
		else
			GlobalStorageSiK.Debug.log("Client", "terminalState", "cached items=" .. tostring(itemCount))
		end
		if explicitOpen and GlobalStorageSiK.NetworkReadAction then
			GlobalStorageSiK.NetworkReadAction.onTerminalOpen(args)
		end
	elseif command == "itemDetails" then
		GlobalStorageSiK.Client.itemDetailsCache = GlobalStorageSiK.Client.itemDetailsCache or {}
		-- Durante una transferencia visible puede diferirse la sustitucion del
		-- snapshot global. La ventana abierta es la autoridad para decidir si
		-- esta pagina de instancias pertenece a SU revision; el cache global es
		-- solo el fallback cuando no hay terminal visible.
		local visibleTerminal = GlobalStorageSiK.TerminalUI and GlobalStorageSiK.TerminalUI.instance
		local activeState = visibleTerminal and visibleTerminal.terminalState
			or GlobalStorageSiK.Client.cachedTerminalState
		local sameNetwork = not activeState or not args or not args.networkId
			or activeState.networkId == args.networkId
		local sameRevision = not activeState or not args or args.inventoryRevision == nil
			or activeState.inventoryRevision == args.inventoryRevision
		local accepted = args and args.rowKey and sameNetwork and sameRevision
		if accepted then
			storeBounded(GlobalStorageSiK.Client.itemDetailsCache, itemDetailsOrder,
				args.rowKey, args, MAX_ITEM_DETAIL_PAGES)
		end
		if GlobalStorageSiK.TerminalItems and GlobalStorageSiK.TerminalItems.onDetailsReceived then
			-- Una respuesta stale no puede limpiar pending ni reconstruir la lista:
			-- hacerlo reabre la misma consulta bajo demanda en un bucle de frames.
			GlobalStorageSiK.TerminalItems.onDetailsReceived(args, accepted == true)
		end
	elseif command == "itemTooltipDetail" then
		if GlobalStorageSiK.RemoteItemDetail and GlobalStorageSiK.RemoteItemDetail.onReceived then
			GlobalStorageSiK.RemoteItemDetail.onReceived(args)
		end
	elseif command == "remoteNetworkCandidates" then
		if GlobalStorageSiK.TerminalUI and GlobalStorageSiK.TerminalUI.onRemoteNetworkCandidates then
			GlobalStorageSiK.TerminalUI.onRemoteNetworkCandidates(args)
		end
	elseif command == "nodeContents" then
		if args and args.nodeId and GlobalStorageSiK.ContainerInventory then
			GlobalStorageSiK.ContainerInventory.receive(args)
		end
		if args and args.catalogRows and GlobalStorageSiK.WithdrawClient then
			GlobalStorageSiK.WithdrawClient.onTerminalState({ networkId = args.networkId, playerNum = args.playerNum,
				sourceNodeId = args.nodeId, inventoryRevision = args.inventoryRevision,
				snapshotRevision = args.snapshotRevision, snapshotCertified = args.snapshotCertified,
				items = args.catalogRows })
		end
		GlobalStorageSiK.Client.nodeContentsCache = GlobalStorageSiK.Client.nodeContentsCache or {}
		local activeState = GlobalStorageSiK.Client.cachedTerminalState
		local sameNetwork = not activeState or not args or not args.networkId
			or activeState.networkId == args.networkId
		local sameRevision = not activeState or not args or args.inventoryRevision == nil
			or activeState.inventoryRevision == args.inventoryRevision
		if args and args.nodeId and sameNetwork and sameRevision then
			storeBounded(GlobalStorageSiK.Client.nodeContentsCache, nodeContentsOrder,
				args.nodeId, args, MAX_NODE_CONTENT_ENTRIES)
		end
		if GlobalStorageSiK.TerminalConfig and GlobalStorageSiK.TerminalConfig.onNodeContentsReceived then
			GlobalStorageSiK.TerminalConfig.onNodeContentsReceived(args)
		end
	elseif command == "zoneCapacity" then
		-- dev26 ronda 4: indicador de ocupacion del editor de zona - a
		-- diferencia de nodeContents (ya pedido siempre al abrir el editor de
		-- contenedor), aqui el editor de zona pide esto explicitamente
		-- (GS_TerminalUI_ZoneEditor.lua:setZone) porque no existe ningun otro
		-- flujo que ya traiga este dato.
		local zoneUi = GlobalStorageSiK.TerminalZoneEditor and GlobalStorageSiK.TerminalZoneEditor.instance
		if zoneUi and zoneUi.zone and args and zoneUi.zone.id == args.zoneId and zoneUi.onCapacityReceived then
			zoneUi:onCapacityReceived(args.capacity)
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
		showMessage(GlobalStorageSiK.I18n.text(msgKey), true)
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
			if player then
				local msgKey = args.mode == "new" and "IGUI_GS_TerminalInstalledNew" or "IGUI_GS_TerminalInstalledJoined"
				GlobalStorageSiK.UIFeedback.halo(player,
					GlobalStorageSiK.I18n.text(msgKey, args.networkId), 180, 220, 160, 350,
					{ tone = "success" })
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
			GlobalStorageSiK.ItemNetworkTooltip.onCountsReceived(args and args.fullType,
				args and args.networks or {}, args and args.hasAnyNetwork,
				args and args.mediaTitle, args and args.mediaIndex, args and args.dynamicStateKey,
				args and args.playerNum)
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
		if staleTerminalOpen(args) then return end
		if GlobalStorageSiK.TerminalAccessGuard
			and not GlobalStorageSiK.TerminalAccessGuard.acceptResponse(args, false) then return end
		local blockedPlayerNum = tonumber(args and args.playerNum) or 0
		local remoteHandled = GlobalStorageSiK.TerminalUI
			and GlobalStorageSiK.TerminalUI.onRemoteOpenResult
			and GlobalStorageSiK.TerminalUI.onRemoteOpenResult(args, false)
		if remoteHandled then
			if blockedPlayerNum == 0 then GlobalStorageSiK.Client.pendingTerminalOpen = false end
			if GlobalStorageSiK.Client.pendingTerminalOpenByPlayer then
				GlobalStorageSiK.Client.pendingTerminalOpenByPlayer[blockedPlayerNum] = nil
			end
			local remotePlayer = GlobalStorageSiK.NetClient.getPlayer(blockedPlayerNum)
			if remotePlayer and GlobalStorageSiK.TerminalAccess
				and GlobalStorageSiK.TerminalAccess.clearSession then
				GlobalStorageSiK.TerminalAccess.clearSession(remotePlayer)
			end
			return
		end
		-- Correlation above replaces the old 1.5-second global grace window:
		-- another player's open must never suppress a valid access denial.
		if blockedPlayerNum == 0 then GlobalStorageSiK.Client.pendingTerminalOpen = false end
		if GlobalStorageSiK.Client.pendingTerminalOpenByPlayer then
			GlobalStorageSiK.Client.pendingTerminalOpenByPlayer[blockedPlayerNum] = nil
		end
		if GlobalStorageSiK.Client.terminalStateByPlayer then
			GlobalStorageSiK.Client.terminalStateByPlayer[blockedPlayerNum] = nil
		end
		if blockedPlayerNum == 0 then
			GlobalStorageSiK.Client.cachedTerminalState = nil
		end
		if GlobalStorageSiK.Client.clearTransientCaches then
			if GlobalStorageSiK.Client.clearInventoryCatalog then
				GlobalStorageSiK.Client.clearInventoryCatalog(blockedPlayerNum, args and args.networkId)
			end
			GlobalStorageSiK.Client.clearTransientCaches(blockedPlayerNum)
		end
		local player = GlobalStorageSiK.NetClient.getPlayer(blockedPlayerNum)
		if player and GlobalStorageSiK.TerminalAccess and GlobalStorageSiK.TerminalAccess.clearSession then
			GlobalStorageSiK.TerminalAccess.clearSession(player)
		end
		if GlobalStorageSiK.TransferQueue and GlobalStorageSiK.TransferQueue.clear then
			GlobalStorageSiK.TransferQueue.clear(blockedPlayerNum)
		end
		if GlobalStorageSiK.WithdrawClient and GlobalStorageSiK.WithdrawClient.cancelAll then
			GlobalStorageSiK.WithdrawClient.cancelAll("access_lost", blockedPlayerNum)
		end
		GlobalStorageSiK.Log.info("Client", "terminalBlocked", args and args.reason or "no_access")
		local payload = args or {}
		local player = GlobalStorageSiK.NetClient.getPlayer(blockedPlayerNum)
		if player and GlobalStorageSiK.TerminalRecipes then
			local ok, enriched = pcall(GlobalStorageSiK.TerminalRecipes.serializeForClient, player, { blockedOnly = true })
			if ok and enriched then
				enriched.playerNum = blockedPlayerNum
				enriched.reason = payload.reason or enriched.reason
				enriched.proximityRange = payload.proximityRange or enriched.proximityRange
				enriched.wirelessRange = payload.wirelessRange or enriched.wirelessRange
				enriched.networkId = payload.networkId or enriched.networkId
				enriched.canClaimOwnership = payload.canClaimOwnership
				enriched.claimTier = payload.claimTier
				enriched.canRecoverRole = payload.canRecoverRole
				enriched.recoverableRole = payload.recoverableRole
				payload = enriched
			end
		end
		local rect
		local mainUi = terminalUiForPlayer(blockedPlayerNum)
		if mainUi and mainUi.getIsVisible and mainUi:isVisible() then
			rect = { x = mainUi:getX(), y = mainUi:getY(), w = mainUi:getWidth(), h = mainUi:getHeight() }
		end
		if GlobalStorageSiK.TerminalUI and GlobalStorageSiK.TerminalUI.showBlocked then
			-- Un solo rebuild, con el payload YA completo (canClaimOwnership/
			-- networkId/claimTier incluidos) - antes esto reconstruia el panel
			-- dos veces por cada terminalBlocked recibido, la primera con datos
			-- a medias (ver comentario de showBlocked). showBlocked acepta ahora
			-- una tabla directamente, sin reconstruir nada por su cuenta.
			GlobalStorageSiK.TerminalUI.showBlocked(payload, rect)
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
	elseif command == "adminNetworkList" then
		if GlobalStorageSiK.AdminDashboard and GlobalStorageSiK.AdminDashboard.onNetworkList then
			GlobalStorageSiK.AdminDashboard.onNetworkList(args and args.networks or {})
		end
	elseif command == "adminNetworkMembers" then
		if GlobalStorageSiK.AdminDashboard and GlobalStorageSiK.AdminDashboard.onNetworkMembers then
			GlobalStorageSiK.AdminDashboard.onNetworkMembers(args and args.networkId, args and args.members or {})
		end
	elseif command == "adminOnlinePlayers" then
		if GlobalStorageSiK.AdminDashboard and GlobalStorageSiK.AdminDashboard.onOnlinePlayers then
			GlobalStorageSiK.AdminDashboard.onOnlinePlayers(args and args.players or {})
		end
	elseif command == "adminNetworkHistory" then
		if GlobalStorageSiK.AdminDashboard and GlobalStorageSiK.AdminDashboard.onNetworkHistory then
			GlobalStorageSiK.AdminDashboard.onNetworkHistory(args and args.networkId, args and args.events or {})
		end
	elseif command == "nativeAuditSummary" then
		-- Resultado del boton "Auditar catalogo" (ver GS_NativeAudit.lua) -
		-- solo el resumen llega aqui, el informe completo con muestras se
		-- queda en el fichero de diagnostico del servidor.
		if args and args.cached ~= true then
			local msg = GlobalStorageSiK.I18n.text("IGUI_GS_NativeAuditSummary",
				tostring(args.timeMs), tostring(args.totalTypes), tostring(args.pending),
				tostring(args.unclassified), tostring(args.invalidPath), tostring(args.fileName))
			GlobalStorageSiK.Log.info("NativeAudit", msg)
			local player = GlobalStorageSiK.NetClient.getPlayer()
			if player then
				GlobalStorageSiK.UIFeedback.halo(player, msg, 220, 220, 220, 600)
			end
		end
		-- Tanto una ejecucion nueva como la copia cacheada solicitada al abrir
		-- alimentan la pestaña; la cache no repite halo ni log.
		if args and GlobalStorageSiK.AdminDashboard and GlobalStorageSiK.AdminDashboard.onNativeAuditSummary then
			GlobalStorageSiK.AdminDashboard.onNativeAuditSummary(args)
		end
	elseif command == "nativeCorpusSummary" then
		-- dev24: resultado del boton "Validar corpus" - suite DIFERENCIADA
		-- de nativeAuditSummary, misma idea de solo mandar el resumen
		-- agregado (la lista de divergencias se queda en
		-- GlobalStorageSiK_NativeCorpus.log).
		if args and GlobalStorageSiK.AdminDashboard and GlobalStorageSiK.AdminDashboard.onNativeCorpusSummary then
			GlobalStorageSiK.AdminDashboard.onNativeCorpusSummary(args)
		end
	end
end

GlobalStorageSiK.Client = GlobalStorageSiK.Client or {}
GlobalStorageSiK.Client.lastItemIndex = {}
GlobalStorageSiK.Client.cachedTerminalState = nil
GlobalStorageSiK.Client.terminalStateByPlayer = {}
GlobalStorageSiK.Client.inventoryCatalogByPlayerNetwork = {}
GlobalStorageSiK.Client.nodeContentsCache = {}
GlobalStorageSiK.Client.pendingTerminalOpen = false
GlobalStorageSiK.Client.pendingTerminalOpenByPlayer = {}
GlobalStorageSiK.Client.terminalOpenSeq = 0
GlobalStorageSiK.Client.terminalOpenSeqByPlayer = {}
GlobalStorageSiK.Client.terminalManifest = nil
GlobalStorageSiK.Client.activeNetworkId = nil
GlobalStorageSiK.Client.activeNetworkIdByPlayer = {}

function GlobalStorageSiK.Client.addInventoryCatalogToken(payload, playerNum, networkId)
	payload = payload or {}
	networkId = networkId or payload.networkId
	if not networkId then return payload end
	local cache = GlobalStorageSiK.Client.inventoryCatalogByPlayerNetwork or {}
	local entry = cache[inventoryCatalogKey(playerNum, networkId)]
	if entry then
		payload.knownInventoryRevision = entry.inventoryRevision
		payload.knownCatalogScope = entry.catalogScope
	end
	return payload
end

function GlobalStorageSiK.Client.clearInventoryCatalog(playerNum, networkId)
	local cache = GlobalStorageSiK.Client.inventoryCatalogByPlayerNetwork or {}
	local remove = {}
	for key, entry in pairs(cache) do
		local samePlayer = playerNum == nil or entry.playerNum == (tonumber(playerNum) or 0)
		local sameNetwork = networkId == nil or entry.networkId == networkId
		if samePlayer and sameNetwork then remove[#remove + 1] = key end
	end
	for i = 1, #remove do cache[remove[i]] = nil end
end

--- Registro neutral y acotado para que addons limpien UI/callbacks efímeros
--- cuando Core cierra una sesión, una vida o un jugador local. La clave estable
--- sustituye el handler anterior y evita listeners de lifecycle duplicados.
function GlobalStorageSiK.Client.registerTransientCleanup(key, handler)
	if type(key) ~= "string" or key == "" or #key > 64 or type(handler) ~= "function" then
		return false
	end
	transientCleanupHandlers[key] = handler
	return true
end

if GlobalStorageSiK.UIFeedback and GlobalStorageSiK.UIFeedback.installCleanup then
	GlobalStorageSiK.UIFeedback.installCleanup()
end

function GlobalStorageSiK.Client.clearTransientCaches(playerNum)
	GlobalStorageSiK.Client.itemDetailsCache = {}
	GlobalStorageSiK.Client.nodeContentsCache = {}
	itemDetailsOrder = {}
	nodeContentsOrder = {}
	if GlobalStorageSiK.RemoteItemDetail and GlobalStorageSiK.RemoteItemDetail.invalidateAll then
		GlobalStorageSiK.RemoteItemDetail.invalidateAll()
	end
	if GlobalStorageSiK.ItemNetworkTooltip and GlobalStorageSiK.ItemNetworkTooltip.invalidateAll then
		GlobalStorageSiK.ItemNetworkTooltip.invalidateAll()
	end
	if GlobalStorageSiK.TerminalSync and GlobalStorageSiK.TerminalSync.clearRevisionState then
		GlobalStorageSiK.TerminalSync.clearRevisionState(nil, playerNum)
	end
	local cleanupKeys = {}
	for key in pairs(transientCleanupHandlers) do cleanupKeys[#cleanupKeys + 1] = key end
	table.sort(cleanupKeys)
	for i = 1, #cleanupKeys do
		local handler = transientCleanupHandlers[cleanupKeys[i]]
		local ok, err = pcall(handler, playerNum)
		if not ok then
			GlobalStorageSiK.Log.error("Client", "transient cleanup " .. cleanupKeys[i], tostring(err))
		end
	end
	if playerNum == nil then
		GlobalStorageSiK.Client.terminalStateByPlayer = {}
		GlobalStorageSiK.Client.cachedTerminalState = nil
		GlobalStorageSiK.Client.inventoryCatalogByPlayerNetwork = {}
	else
		playerNum = tonumber(playerNum) or 0
		GlobalStorageSiK.Client.terminalStateByPlayer[playerNum] = nil
		local ui = terminalUiForPlayer(playerNum)
		if not ui or (tonumber(ui.playerNum) or 0) == playerNum then
			GlobalStorageSiK.Client.cachedTerminalState = nil
		end
	end
end

local function logClientRuntimeIdentity()
	local version = GlobalStorageSiK.Config and GlobalStorageSiK.Config.MOD_VERSION or "?"
	GlobalStorageSiK.Log.runtimeIdentity("client", version)
end

Events.OnServerCommand.Add(onServerCommand)
Events.OnGameStart.Add(logClientRuntimeIdentity)

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
