require "GS_TerminalUI_Items"
require "GS_WithdrawClient"
local UI = require "GS_UI_Framework"
local Capacity = require "GlobalStorageSiK/UI/CapacityPresentation"
local T = GlobalStorageSiK.I18n.text
local Inventory = {}
GlobalStorageSiK.ContainerInventory = Inventory
local views = {}

local function move(widget, x, y, w, h)
	widget:setX(x); widget:setY(y); widget:setWidth(w); widget:setHeight(h)
end

function Inventory.mount(parent, editor, node, options)
	options = options or {}
	local view = { node = node, editor = editor, options = options, rows = {}, disposed = false, detailQueue = {} }
	local width = options.w or parent.width or 1
	view.block = UI.Block.create({ parent = parent, x = options.x or 0, y = options.y or 0,
		w = width, h = 180, title = T("IGUI_GS_NodeContentsTitle"), tooltip = T("IGUI_GS_NodeContentsTitle") })
	local panel = view.block.childParent
	panel._detailPages = {}
	panel._detailPending = {}
	panel._allDetails = true
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
	function view.controller:refreshItemsTab() view:render() end
	function view.controller:onWithdrawRow(row, amount, targetKey)
		return GlobalStorageSiK.WithdrawClient.sendWithdraw(row, amount, targetKey, "", {
			networkId = view.networkId, onComplete = function() view:request() end,
		})
	end
	function view.controller:requestInventoryDetails(row, page)
		local sent = GlobalStorageSiK.NetClient.sendCommand("getNodeContents", {
			networkId = view.networkId, nodeId = view.node.id, rowKey = row.rowKey,
			inventoryRevision = self.terminalState.inventoryRevision, page = page or 1,
		})
		if sent == false then panel._detailPending[row.rowKey] = nil end
		return sent
	end
	local metrics = UI.Controls.metrics("editor")
	view.rowHeight = metrics.rowHeight
	view.bar = UI.Controls.progress(panel, { x = 8, y = 8, w = width - 16, h = metrics.rowHeight })
	view.withdraw = UI.Controls.button(panel, { text = T("IGUI_GS_WithdrawContainerAll"),
		onClick = function()
			GlobalStorageSiK.WithdrawClient.sendWithdrawBatch(view.rows, 0, nil, "", {
				networkId = view.networkId, onComplete = function() view:request() end,
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
	tableOptions.x, tableOptions.y, tableOptions.w, tableOptions.h = 8, 100, width - 16, 50
	tableOptions.columns = GlobalStorageSiK.TerminalItems.columns({ hideZone = true })
	tableOptions.rows, tableOptions.pagination = {}, nil
	tableOptions.heightMode, tableOptions.allRowsVisible = "content", true
	view.table = UI.Table.create(tableOptions)
	panel.itemTable = view.table
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
		self.bar:setProgress(Capacity.fromState(self.capacity, { count = count }))
		self.rendering = false
		for key, details in pairs(panel._detailPages) do
			if details.nextPage and panel._expandedKeys and panel._expandedKeys[key] then
				self:scheduleDetail(key, details.nextPage)
			end
		end
		if self.lastHeight ~= height then
			self.lastHeight = height
			if options.onHeightChanged then options.onHeightChanged(self) end
		end
		if self.renderAgain then self.renderAgain = false; self:render() end
	end
	function view:scheduleDetail(key, page)
		if self.disposed or panel._detailPending[key] then return end
		self.detailQueue[key] = page
		if self.detailTick then return end
		self.detailTick = function()
			local wantedKey, wantedPage
			for rowKey, number in pairs(self.detailQueue) do wantedKey, wantedPage = rowKey, number; break end
			if wantedKey then self.detailQueue[wantedKey] = nil end
			-- Detach before dispatch: SP can synchronously deliver a response.
			if Events and Events.OnTick then Events.OnTick.Remove(self.detailTick) end
			self.detailTick = nil
			if not self.disposed and wantedKey and panel._expandedKeys and panel._expandedKeys[wantedKey] then
				panel._detailPending[wantedKey] = true
				self.controller:requestInventoryDetails({ rowKey = wantedKey }, wantedPage)
			end
			if not self.disposed then
				local keyNext, pageNext
				for rowKey, number in pairs(self.detailQueue) do keyNext, pageNext = rowKey, number; break end
				if keyNext then self:scheduleDetail(keyNext, pageNext) end
			end
		end
		if Events and Events.OnTick then Events.OnTick.Add(self.detailTick) end
	end
	function view:request()
		if self.disposed then return end
		GlobalStorageSiK.NetClient.sendCommand("getNodeContents", { networkId = self.networkId, nodeId = self.node.id })
	end
	function view:refresh(nextNode)
		if nextNode then self.node = nextNode end
		self:render()
	end
	function view:dispose()
		if self.disposed then return end
		self.disposed = true
		if self.detailTick and Events and Events.OnTick then Events.OnTick.Remove(self.detailTick) end
		self.detailTick, self.detailQueue = nil, {}
		views[self] = nil
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
			self.detailQueue = {}
		end
		self.controller.terminalState.inventoryRevision = revision
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
			local existing = panel._detailPages[detail.rowKey]
			if not existing then
				existing = { page = 1, items = {}, receivedPages = {}, networkId = self.networkId, inventoryRevision = revision }
				panel._detailPages[detail.rowKey] = existing
			end
			local page = tonumber(detail.page) or 1
			if existing.receivedPages[page] then return end
			existing.receivedPages[page] = true
			for i = 1, #(detail.items or {}) do existing.items[#existing.items + 1] = detail.items[i] end
			existing.total = tonumber(detail.total) or #existing.items
			existing.hasPrevious, existing.hasNext = false, false
			panel._detailPending[detail.rowKey] = nil
			existing.nextPage = detail.hasNext and (page + 1) or nil
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
				view.requestedRevision = revision
				view:request()
			end
		end
	end
end

function Inventory.onActionResult(args)
	local transfer = args and args.transfer
	if not transfer or transfer.op ~= "redistribute" or args.jobState ~= "finished" then return end
	local snapshot = {}
	for view in pairs(views) do snapshot[#snapshot + 1] = view end
	for i = 1, #snapshot do
		local view = snapshot[i]
		if view.networkId == transfer.networkId and view.node.id == transfer.sourceNodeId
			and view.playerNum == (tonumber(args.playerNum) or 0) then view:request() end
	end
end

if GlobalStorageSiK.Client.registerTransientCleanup then
	GlobalStorageSiK.Client.registerTransientCleanup("containerInventory", function(playerNum)
		local snapshot = {}
		for view in pairs(views) do
			if playerNum == nil or view.playerNum == playerNum then snapshot[#snapshot + 1] = view end
		end
		for i = 1, #snapshot do snapshot[i]:dispose() end
	end)
end

return Inventory
