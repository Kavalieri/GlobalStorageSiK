-- Client facade over the existing inventory presentation, without new vanilla
-- hooks or a second tooltip renderer. The consumer drives show from row render.
require "GSSiK_API"
local Presentation = GSSiK.API.ItemPresentation

local function service()
	if not GlobalStorageSiK.TerminalItems then require "GS_TerminalUI_Items" end
	return GlobalStorageSiK.TerminalItems
end

local function text(value, limit)
	return type(value) == "string" and #value > 0 and #value <= limit
end

local function integer(value)
	return type(value) == "number" and value >= 0 and value <= 2147483647 and value == math.floor(value)
end

function Presentation.icon(fullType)
	if not text(fullType, 160) then return nil, "ERR_SCHEMA" end
	local items = service()
	return items and items.textureForRow({ fullType = fullType }) or nil, "OK"
end

function Presentation.create(surface, options)
	local terminal = type(options) == "table" and options.terminal
	if not surface or not surface.getAbsoluteX or not terminal or not terminal.terminalState then
		return nil, "ERR_SCHEMA"
	end
	local items, bindings, pool = service(), {}, {}
	if not items or not items.presentExternalTooltip then return nil, "ERR_UNAVAILABLE" end
	local disposed = false
	local handle = {}
	local function current(data)
		local state = terminal and terminal.terminalState
		return state and state.networkId == data.networkId and state.inventoryRevision == data.selectionRevision
	end
	function handle:hide(row)
		if row then items.hideRowTooltip(row)
		elseif pool._gsItemTooltipOwner then items.hideRowTooltip(pool._gsItemTooltipOwner) end
	end
	function handle:bind(row, candidate)
		if disposed or not row or not row.getAbsoluteX or type(candidate) ~= "table"
			or not text(candidate.networkId, 160) or not text(candidate.sourceNodeId, 240)
			or not text(candidate.fullType, 160) or not integer(candidate.itemId)
			or not integer(candidate.inventoryRevision) then return nil, "ERR_SCHEMA" end
		self:hide(row)
		local data = { _gsRowKind = "child", nodeId = candidate.sourceNodeId,
			itemId = candidate.itemId, fullType = candidate.fullType, networkId = candidate.networkId,
			selectionRevision = candidate.inventoryRevision, count = 1 }
		data.rowKey = table.concat({data.nodeId, tostring(data.itemId), tostring(data.selectionRevision)}, "\31")
		if integer(candidate.mediaIndex) and candidate.mediaIndex <= 32767 then data.mediaIndex = candidate.mediaIndex end
		if text(candidate.displayName, 512) then data.displayName = candidate.displayName end
		if not current(data) then bindings[row] = false; return nil, "ERR_STALE" end
		local binding = { row = row, data = data }
		bindings[row] = binding
		return binding, "OK"
	end
	function handle:show(binding)
		if disposed or not binding or bindings[binding.row] ~= binding then return false, "ERR_STALE" end
		local row, data = binding.row, binding.data
		if not current(data) then self:hide(row); return false, "ERR_STALE" end
		-- Clip hover to visible ancestors as well as the row rectangle. A scrolled
		-- child can be rendered under a stencil while its rectangle is offscreen.
		local node, mx, my = row, getMouseX(), getMouseY()
		while node do
			if node.isVisible and not node:isVisible() then self:hide(row); return false, "ERR_HIDDEN" end
			if node.getAbsoluteX and node.getAbsoluteY then
				local x, y = node:getAbsoluteX(), node:getAbsoluteY()
				if mx < x or my < y or mx >= x + node.width or my >= y + node.height then
					self:hide(row); return false, "ERR_HIDDEN"
				end
			end
			node = node.parent
		end
		items.presentExternalTooltip(row, data, pool, terminal)
		return row._gsTooltip ~= nil, row._gsLocalTooltip and "local-vanilla" or "remote-snapshot"
	end
	function handle:dispose()
		if disposed then return false end
		disposed = true
		for row in pairs(bindings) do
			items.disposeRowTooltip(row)
			row.itemData, row.listPanel, row.terminal, row.onRemoteItemDetail = nil, nil, nil, nil
		end
		if pool._gsItemTooltip then
			pool._gsItemTooltip:setItem(nil)
			pool._gsItemTooltip:setOwner(nil)
		end
		bindings, pool, terminal, surface = {}, {}, nil, nil
		return true
	end
	return handle, "OK"
end

return Presentation
