require "GS_TerminalUI_Items"
require "GS_WithdrawClient"
require "GS_TerminalDrop"
local UI = require "GS_UI_Framework"
local Capacity = require "GlobalStorageSiK/UI/CapacityPresentation"
local T = GlobalStorageSiK.I18n.text
local Inventory = {}
GlobalStorageSiK.ContainerInventory = Inventory
local views = {}
local cleanupRegistered = false

function Inventory.installCleanup()
	if cleanupRegistered then return true end
	local client = GlobalStorageSiK.Client
	if not client or type(client.registerTransientCleanup) ~= "function" then return false end
	cleanupRegistered = client.registerTransientCleanup("containerInventory", function(playerNum)
		local snapshot = {}
		for view in pairs(views) do
			if playerNum == nil or view.playerNum == playerNum then snapshot[#snapshot + 1] = view end
		end
		for i = 1, #snapshot do snapshot[i]:dispose() end
	end) == true
	return cleanupRegistered
end

local function move(widget, x, y, w, h)
	widget:setX(x); widget:setY(y); widget:setWidth(w); widget:setHeight(h)
end

function Inventory.mount(parent, editor, node, options)
	Inventory.installCleanup()
	options = options or {}
	local view = { node = node, editor = editor, options = options, rows = {}, disposed = false, detailQueue = {} }
	local width = options.w or parent.width or 1
	view.block = UI.Block.create({ parent = parent, x = options.x or 0, y = options.y or 0,
		w = width, h = 180, title = T("IGUI_GS_NodeContentsTitle"), tooltip = T("IGUI_GS_NodeContentsTitle") })
	local panel = view.block.childParent
	panel._detailPages = {}
	panel._detailPending = {}
	panel._detailPageByKey = {}
	view.panel = panel
	local playerNum = editor.playerNum or 0
	view.playerNum = playerNum
	local state = GlobalStorageSiK.Client.terminalStateByPlayer[playerNum]
		or GlobalStorageSiK.Client.cachedTerminalState or {}
	view.networkId = state.networkId
	view.controller = { playerNum = playerNum, terminalState = {
		networkId = state.networkId, inventoryRevision = state.inventoryRevision,
		zones = state.zones, nodes = state.nodes, items = view.rows,
	} }
	-- TerminalItems reutiliza el mismo menú contextual en Almacén y editores.
	-- Aquí la capa superior real es el editor, no la terminal principal.
	view.controller.contextMenuOwner = editor
	function view.controller:refreshItemsTab() view:render() end
	function view.controller:onWithdrawCompleted(ok, result) view:afterWithdraw(ok, result) end
	function view:invalidateAndScheduleRefresh(revision, reason)
		if self.disposed then return end
		-- Exact rows are bound to one authoritative revision. Invalidate them
		-- immediately so repeated gestures cannot act on an item that another
		-- transfer has already moved.
		panel._detailPages, panel._detailPending = {}, {}
		panel._detailPageByKey = {}
		self.detailQueue = {}
		local wanted = tonumber(revision)
		local known = tonumber(self.controller.terminalState.inventoryRevision)
		if wanted and (not known or wanted > known) then
			self.controller.terminalState.inventoryRevision = wanted
		end
		if wanted and (not self.refreshRevision or wanted > self.refreshRevision) then
			self.refreshRevision = wanted
		end
		self.refreshReason = reason or self.refreshReason or "inventory-change"
		self:render()
		if self.refreshTick then return end
		self.refreshTick = function()
			-- Detach before dispatch: SP may return getNodeContents synchronously.
			if Events and Events.OnTick then Events.OnTick.Remove(self.refreshTick) end
			self.refreshTick = nil
			local requested, refreshReason = self.refreshRevision, self.refreshReason
			self.refreshRevision, self.refreshReason = nil, nil
			if self.disposed then return end
			self.requestedRevision = requested
			self:request()
			GlobalStorageSiK.Log.debug("ExactWithdraw", "container.refresh requested"
				.. " reason=" .. tostring(refreshReason)
				.. " revision=" .. tostring(requested))
		end
		if Events and Events.OnTick then Events.OnTick.Add(self.refreshTick)
		else self.refreshTick() end
	end
	function view:afterWithdraw(ok, result)
		local revision = result and tonumber(result.inventoryRevision)
		self:invalidateAndScheduleRefresh(revision, "withdraw-ack")
		GlobalStorageSiK.Log.debug("ExactWithdraw", "detail-cache invalidated surface=container-editor"
			.. " ok=" .. tostring(ok == true) .. " revision=" .. tostring(revision))
	end
	function view.controller:onWithdrawRow(row, amount, targetKey)
		return GlobalStorageSiK.WithdrawClient.sendWithdraw(row, amount, targetKey, "", {
			networkId = view.networkId, playerNum = view.playerNum,
			onComplete = function(ok, result) view:afterWithdraw(ok, result) end,
		})
	end
	function view.controller:requestInventoryDetails(row, page)
		local sent = GlobalStorageSiK.NetClient.sendCommand("getNodeContents", {
			networkId = view.networkId, nodeId = view.node.id, rowKey = row.rowKey,
			inventoryRevision = self.terminalState.inventoryRevision, page = page or 1,
		}, getSpecificPlayer and getSpecificPlayer(view.playerNum) or nil)
		if sent == false then panel._detailPending[row.rowKey] = nil end
		return sent
	end
	local metrics = UI.Controls.metrics("editor")
	view.rowHeight = metrics.rowHeight
	view.bar = UI.Controls.progress(panel, { x = 8, y = 8, w = width - 16, h = metrics.rowHeight })
	view.withdraw = UI.Controls.button(panel, { text = T("IGUI_GS_WithdrawContainerAll"),
			onClick = function()
			GlobalStorageSiK.WithdrawClient.sendWithdrawBatch(view.rows, 0, nil, "", {
				networkId = view.networkId, playerNum = view.playerNum,
				onComplete = function(ok, result) view:afterWithdraw(ok, result) end,
			})
		end })
	view.empty = UI.Controls.button(panel, { text = T("IGUI_GS_EmptyContainer"),
		onClick = function()
			GlobalStorageSiK.NetClient.sendCommand("redistributeNetwork", {
				networkId = view.networkId, sourceNodeId = view.node.id,
			})
		end })
	local tableOptions = GlobalStorageSiK.TerminalItems.tableOptions(panel, view.controller)
	tableOptions.parent, tableOptions.embedded = panel, true
	-- Este Block contiene barra, acciones y tabla. La tabla es un hermano
	-- compuesto, no el unico contenido directo del Block: si toma propiedad
	-- directa ocupa todo el rectangulo y tapa los widgets anteriores.
	tableOptions.directBlock = false
	tableOptions.x, tableOptions.y, tableOptions.w, tableOptions.h = 8, 100, width - 16, 50
	tableOptions.columns = GlobalStorageSiK.TerminalItems.columns({ hideZone = true })
	tableOptions.rows = {}
	tableOptions.heightMode, tableOptions.allRowsVisible = "content", true
	view.table = UI.Table.create(tableOptions)
	panel.itemTable = view.table
	GlobalStorageSiK.TerminalDrop.setupPanel(panel, view.controller)
	function view:getHeight() return self.block.h end
	function view:render()
		if self.disposed then return end
		if self.rendering then self.renderAgain = true; return end
		self.rendering = true
		local model = GlobalStorageSiK.TerminalItems.presentationModel(panel, self.controller, self.rows)
		self.table:setRows(model.rows, true)
		local rect = self.block:getContentRect()
		local y, h = rect.y, self.rowHeight
		move(self.bar, rect.x, y, rect.w, h)
		y = y + h + 8
		local half = math.max(1, (rect.w - 8) / 2)
		move(self.withdraw, rect.x, y, half, h)
		move(self.empty, rect.x + half + 8, y, half, h)
		y = y + h + 8
		local tableH = self.table:getIntrinsicHeight()
		self.table:setBounds(rect.x, y, rect.w, tableH)
		local height = y + tableH + 8
		self.block:setBounds(self.block.x, self.block.y, self.block.w, height)
		local count = 0
		for i = 1, #self.rows do count = count + (tonumber(self.rows[i].count) or 0) end
		self.bar:setProgress(Capacity.fromState(self.capacity, {
			count = count,
			typeCount = #self.rows,
		}))
		self.rendering = false
		if self.lastHeight ~= height then
			self.lastHeight = height
			if options.onHeightChanged then options.onHeightChanged(self) end
		end
		if self.renderAgain then self.renderAgain = false; self:render() end
	end
	function view:request()
		if self.disposed then return end
		GlobalStorageSiK.NetClient.sendCommand("getNodeContents", { networkId = self.networkId, nodeId = self.node.id },
			getSpecificPlayer and getSpecificPlayer(self.playerNum) or nil)
	end
	function view:refresh(nextNode)
		if nextNode then self.node = nextNode end
		self:render()
	end
	function view:dispose()
		if self.disposed then return end
		self.disposed = true
		if self.detailTick and Events and Events.OnTick then Events.OnTick.Remove(self.detailTick) end
		if self.refreshTick and Events and Events.OnTick then Events.OnTick.Remove(self.refreshTick) end
		self.detailTick, self.refreshTick, self.detailQueue = nil, nil, {}
		views[self] = nil
		GlobalStorageSiK.TerminalDrop.disposePanel(panel, self.controller)
		self.table:dispose(); self.block:dispose()
		panel._detailPages = nil
	end
	function view:receive(payload)
		if self.disposed or payload.networkId ~= self.networkId or payload.nodeId ~= self.node.id then return end
		if payload.playerNum ~= nil and payload.playerNum ~= self.playerNum then return end
		local revision = payload.inventoryRevision
		local knownRevision = self.controller.terminalState.inventoryRevision
		if tonumber(revision) and tonumber(knownRevision) and revision < knownRevision then return end
		if self.controller.terminalState.inventoryRevision ~= revision then
			panel._detailPages, panel._detailPending = {}, {}
			panel._detailPageByKey = {}
			self.detailQueue = {}
		end
		self.controller.terminalState.inventoryRevision = revision
		self.controller.terminalState.snapshotCertified = payload.snapshotCertified
		self.controller.terminalState.snapshotRevision = payload.snapshotRevision
		self.controller.terminalState.snapshotAgeMs = payload.snapshotAgeMs
		self.controller.terminalState.reconcilePending = payload.reconcilePending
		self.requestedRevision = nil
		self.capacity = payload.capacity or self.capacity
		if payload.catalogRows then
			self.rows = payload.catalogRows
			self.controller.terminalState.items = self.rows
		end
		local detail = payload.detailPage
		if detail and detail.reason then
			panel._detailPending[detail.rowKey] = nil
			if detail.reason == "revision_mismatch" then self:request() end
			return
		end
		if detail and detail.rowKey and not detail.reason then
			local page = tonumber(detail.page) or 1
			local wantedPage = panel._detailPageByKey[detail.rowKey] or 1
			if page ~= wantedPage then return end
			local existing = { page = page, pageSize = tonumber(detail.pageSize) or 25,
				items = detail.items or {}, networkId = self.networkId, inventoryRevision = revision }
			panel._detailPages[detail.rowKey] = existing
			existing.totalRows = tonumber(detail.totalRows) or tonumber(detail.total) or #existing.items
			existing.totalUnits = tonumber(detail.totalUnits) or existing.totalRows
			existing.total = existing.totalRows
			existing.hasPrevious, existing.hasNext = detail.hasPrevious == true, detail.hasNext == true
			panel._detailPending[detail.rowKey] = nil
		end
		self:render()
	end
	views[view] = true
	view:render()
	view:request()
	return view
end

function Inventory.receive(payload)
	local snapshot = {}
	for view in pairs(views) do snapshot[#snapshot + 1] = view end
	for i = 1, #snapshot do snapshot[i]:receive(payload) end
end

function Inventory.onTerminalState(state)
	if not state or not state.networkId then return end
	local snapshot = {}
	for view in pairs(views) do snapshot[#snapshot + 1] = view end
	for i = 1, #snapshot do
		local view = snapshot[i]
		if not view.disposed and view.networkId == state.networkId
			and view.playerNum == (tonumber(state.playerNum) or 0) then
			view.controller.terminalState.zones = state.zones
			view.controller.terminalState.nodes = state.nodes
			local capacity = state.capacity and state.capacity.perNode
				and state.capacity.perNode[view.node.id]
			if capacity then
				view.capacity = capacity
				view:render()
			end
			local revision = tonumber(state.inventoryRevision)
			local known = tonumber(view.controller.terminalState.inventoryRevision) or -1
			if revision and revision > known and view.requestedRevision ~= revision then
				view:invalidateAndScheduleRefresh(revision, "terminal-state")
			end
		end
	end
end

function Inventory.onActionResult(args)
	local transfer = args and args.transfer
	if not transfer then return end
	local moved = tonumber(transfer.moved) or 0
	local refresh = (transfer.op == "deposit" or transfer.op == "bulkDeposit") and moved > 0
		or (transfer.op == "redistribute" and args.jobState == "finished")
	if not refresh then return end
	local snapshot = {}
	for view in pairs(views) do snapshot[#snapshot + 1] = view end
	for i = 1, #snapshot do
		local view = snapshot[i]
		if not view.disposed and view.networkId == transfer.networkId
			and (args.playerNum == nil or view.playerNum == tonumber(args.playerNum))
			and (transfer.op ~= "redistribute" or view.node.id == transfer.sourceNodeId) then
			view:invalidateAndScheduleRefresh(transfer.inventoryRevision,
				transfer.op .. "-ack")
		end
	end
end

return Inventory
