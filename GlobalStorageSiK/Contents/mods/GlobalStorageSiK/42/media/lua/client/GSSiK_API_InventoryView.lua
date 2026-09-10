-- Neutral bridge to Core inventory gestures. Consumers supply physical groups;
-- only Core converts those references into its internal exact-withdraw rows.
require "GSSiK_API"
local View = GSSiK.API.InventoryView

local function integer(value)
	return type(value) == "number" and value >= 0 and value <= 2147483647 and value == math.floor(value)
end
local function text(value, limit)
	return type(value) == "string" and #value > 0 and #value <= limit
end

function View.create(panel, options)
	options = options or {}
	local terminal = options.terminal
	if not panel or not terminal or not terminal.terminalState then return nil, "ERR_SCHEMA" end
	require "GS_TerminalUI_Items"
	require "GS_TerminalDrop"
	require "GS_WithdrawClient"
	local items, drop = GlobalStorageSiK.TerminalItems, GlobalStorageSiK.TerminalDrop
	local handle = { roots = {}, disposed = false }
	local networkId = terminal.terminalState.networkId
	local controller = { player = terminal.player, playerNum = terminal.playerNum or 0,
		terminalState = terminal.terminalState, contextMenuOwner = terminal }
	handle.controller = controller
	panel._lastItems, panel._selectedKeys, panel._expandedKeys = {}, {}, {}
	local function changed(ok, result)
		if not handle.disposed and options.onChanged then options.onChanged(ok, result) end
	end
	function controller:getSearchQuery() return "" end
	function controller:setCapture(value)
		terminal._gsWithdrawDragCaptured = value and true or nil
		if terminal.setCapture then terminal:setCapture(value) end
	end
	function controller:onWithdrawCompleted(ok, result) changed(ok, result) end
	function controller:onWithdrawRow(row, amount, targetKey)
		if handle.disposed or row._gsStale or terminal.terminalState.networkId ~= networkId then return false end
		return GlobalStorageSiK.WithdrawClient.sendWithdraw(row, amount, targetKey, "", {
			playerNum = self.playerNum, networkId = networkId, onComplete = changed })
	end
	function controller:refreshItemsTab()
		if not handle.disposed and options.onLayoutChanged then options.onLayoutChanged() end
	end
	handle.row = items.createExternalRowAdapter(panel, controller)
	local function notifySelection()
		if not handle.disposed and options.onSelectionChanged then options.onSelectionChanged(handle:selectedItems()) end
	end
	for _, name in ipairs({ "onMouseUp", "onRightClick" }) do
		local original = handle.row[name]
		handle.row[name] = function(context)
			local result = original(context)
			notifySelection()
			return result
		end
	end
	function handle:setTable(widget)
		panel.itemTable = widget
		self.table = widget
	end
	function handle:isInteracting()
		local pool = self.table and self.table.list and self.table.list.pool or {}
		for i = 1, #pool do if pool[i]._sikExpansionPressed then return true end end
		return items.isInteractionActive(panel)
	end
	function handle:setEnabled(enabled)
		if self.enabled == (enabled == true) then return end
		self.enabled = enabled == true
		for i = 1, #panel._lastItems do panel._lastItems[i]._gsStale = not self.enabled end
	end
	-- Groups are ordered {key, items={physical refs}}. No aggregate server
	-- selector is inferred from a display key, and a ref may occur only once.
	function handle:setGroups(groups, revision)
		if self.disposed or type(groups) ~= "table" or #groups > 16384 or not integer(revision)
			or terminal.terminalState.networkId ~= networkId then return false, "ERR_SCHEMA" end
		if self:isInteracting() then return false, "ERR_BUSY" end
		local roots, flat, keys, seen, groupKeys, total = {}, {}, {}, {}, {}, 0
		for i = 1, #groups do
			local group = groups[i]
			if type(group) ~= "table" or not text(group.key, 200) or groupKeys[group.key]
				or type(group.items) ~= "table" or #group.items == 0 then return false, "ERR_SCHEMA" end
			groupKeys[group.key] = true
			local root = { rowKey = "group:" .. group.key, count = #group.items, itemIds = {},
				selectionMode = "exact_ids", selectionRevision = revision, networkId = networkId,
				_gsRowKind = "parent", _gsDepth = 0, expandable = true, _sikChildren = {}, reference = group.items[1] }
			roots[#roots + 1], flat[#flat + 1], keys[root.rowKey] = root, root, true
			for j = 1, #group.items do
				local ref = group.items[j]
				total = total + 1
				if total > 16384 or type(ref) ~= "table" or not integer(ref.itemId)
					or not text(ref.fullType, 160) or not text(ref.sourceNodeId, 240)
					or seen[ref.itemId] or (root.fullType and root.fullType ~= ref.fullType) then return false, "ERR_SCHEMA" end
				seen[ref.itemId], root.fullType = true, ref.fullType
				root.itemIds[#root.itemIds + 1] = ref.itemId
				local row = { rowKey = "item:" .. ref.sourceNodeId .. ":" .. tostring(ref.itemId),
					itemId = ref.itemId, itemIds = { ref.itemId }, fullType = ref.fullType,
					nodeId = ref.sourceNodeId, sourceNodeId = ref.sourceNodeId, networkId = networkId,
					count = 1, selectionMode = "exact_ids", selectionRevision = revision,
					_gsRowKind = "child", _gsDepth = 1, parentRowKey = root.rowKey, reference = ref }
				if integer(ref.mediaIndex) and ref.mediaIndex <= 32767 then row.mediaIndex = ref.mediaIndex end
				if text(ref.displayName, 512) then row.displayName = ref.displayName end
				root._sikChildren[#root._sikChildren + 1], flat[#flat + 1], keys[row.rowKey] = row, row, true
			end
			root.mediaIndex, root.displayName = root._sikChildren[1].mediaIndex, root._sikChildren[1].displayName
		end
		local selected, expanded = {}, {}
		for key in pairs(panel._selectedKeys) do if keys[key] then selected[key] = true end end
		for key in pairs(panel._expandedKeys) do if keys[key] then expanded[key] = true end end
		panel._lastItems, panel._selectedKeys, panel._expandedKeys = flat, selected, expanded
		controller.terminalState = terminal.terminalState
		self.roots, self.revision = roots, revision
		self:setEnabled(true)
		return true, "OK"
	end
	function handle:selectedItems()
		local out = {}
		for i = 1, #self.roots do
			local root = self.roots[i]
			for j = 1, #root._sikChildren do
				local row = root._sikChildren[j]
				if panel._selectedKeys[root.rowKey] or panel._selectedKeys[row.rowKey] then out[#out + 1] = row.reference end
			end
		end
		return out
	end
	function handle:selectionKeys()
		local keys = {}
		for key in pairs(panel._selectedKeys) do keys[#keys + 1] = key end
		return keys
	end
	function handle:selectItems(ids)
		if self.disposed then return false, "ERR_DISPOSED" end
		if type(ids) ~= "table" then return false, "ERR_SCHEMA" end
		local keys = {}
		for i = 1, #self.roots do
			local root, all = self.roots[i], true
			for j = 1, #root._sikChildren do
				local row = root._sikChildren[j]
				if not ids[tostring(row.itemId)] then all = false end
			end
			if all and panel._selectedKeys[root.rowKey] then keys[root.rowKey] = true
			else
				for j = 1, #root._sikChildren do
					local row = root._sikChildren[j]
					if ids[tostring(row.itemId)] then keys[row.rowKey] = true end
				end
			end
		end
		panel._selectedKeys = keys
		return true, "OK"
	end
	function handle:expand(key, expanded)
		panel._expandedKeys[key] = expanded == true or nil
	end
	function handle:hide()
		items.resetVirtualInteraction(panel)
		local pool = self.table and self.table.list and self.table.list.pool or {}
		for i = 1, #pool do pool[i]._sikExpansionPressed = nil end
	end
	function handle:dispose()
		if self.disposed then return end
		self.disposed = true
		local drag = GlobalStorageSiK.TerminalWithdrawDrag
		if drag and drag.isActiveForPanel(panel) then drag.cancel("view_disposed") end
		self:hide()
		drop.disposePanel(panel, controller)
		panel._lastItems, panel._selectedKeys, panel._expandedKeys, panel.itemTable = {}, {}, {}, nil
		self.roots, options = {}, {}
	end
	drop.setupPanel(panel, controller, {
		acceptItem = options.acceptItem,
		isEnabled = function()
			return not handle.disposed and handle.enabled == true and terminal.terminalState.networkId == networkId
		end,
		transferOptions = { networkId = networkId, onComplete = changed },
	})
	return handle, "OK"
end

return View
