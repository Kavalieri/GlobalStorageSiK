-- Product adapter for a native tooltip's separately owned scrollable annex.
-- No global hooks or ticking monitor: the existing visible owner drives life.
local UI = require "GS_UI_Framework"
local Overflow = {}
local function now()
	return getTimestampMs and getTimestampMs() or 0
end
local function rect(panel)
	return { x = panel.getAbsoluteX and panel:getAbsoluteX() or panel.x or 0,
		y = panel.getAbsoluteY and panel:getAbsoluteY() or panel.y or 0,
		w = panel.width or 0, h = panel.height or 0 }
end
local function inside(area)
	if not getMouseX or not getMouseY then return false end
	local x, y = getMouseX(), getMouseY()
	return x >= area.x and x < area.x + area.w and y >= area.y and y < area.y + area.h
end
local function live(panel, state)
	if not panel or panel.item ~= state.item or not panel:isVisible() then return false end
	if panel.owner and panel.owner.isReallyVisible and not panel.owner:isReallyVisible() then return false end
	if ISContextMenu and ISContextMenu.instance and ISContextMenu.instance.visibleCheck then return false end
	local drag = GlobalStorageSiK.TerminalWithdrawDrag
	if drag and drag.isActive and drag.isActive() then return false end
	if state.container and state.item.getContainer and state.item:getContainer() ~= state.container then return false end
	return true
end
function Overflow.isRetained(panel)
	local state = panel and panel._gsObjectOverflow
	if not state or state.dismissed or not live(panel, state) then return false end
	if state.handle:isPointerOver() or inside(rect(panel)) then
		state.lastInside = now()
		return true
	end
	-- A short input-driven grace bridges the native 24px pointer gutter. No
	-- recurring job is created; the ordinary visible inventory update checks it.
	local elapsed = now() - state.lastInside
	return elapsed >= 0 and elapsed < 200
end
local function restoreHost(panel, state)
	if state.owner and state.owner.updateTooltip == state.ownerWrapper then
		state.owner.updateTooltip = state.previousOwnerUpdate
	end
	panel.followMouse, panel.anchorBottomLeft = state.followMouse, state.anchorBottomLeft
end
function Overflow.release(panel)
	local state = panel and panel._gsObjectOverflow
	if not state then return end
	panel._gsObjectOverflow = nil
	restoreHost(panel, state)
	state.handle:dispose()
	state.item, state.container, state.owner = nil, nil, nil
end
function Overflow.bounds(panel, width, playerNum)
	local safe = UI.Viewport.resolve(playerNum)
	local box = rect(panel)
	local gap, minimum = 2, 64
	width = math.min(width, safe.w)
	local below = safe.y + safe.h - box.y - box.h - gap
	if below >= minimum then return { x = box.x, y = box.y + box.h + gap, w = width, h = below } end
	local above = box.y - safe.y - gap
	if above >= minimum then return { x = box.x, y = safe.y, w = width, h = above } end
	local right = safe.x + safe.w - box.x - box.w - gap
	if right >= 120 then
		return { x = box.x + box.w + gap, y = safe.y, w = math.min(width, right), h = safe.h }
	end
	local left = box.x - safe.x - gap
	if left >= 120 then
		return { x = safe.x, y = safe.y, w = math.min(width, left), h = safe.h }
	end
	-- A native body can itself consume the whole player viewport. Keep the
	-- annex readable as the topmost transient instead of discarding its text;
	-- Escape dismisses it and exposes the untouched native body immediately.
	return { x = safe.x + safe.w - width, y = safe.y + math.floor(safe.h * 0.6),
		w = width, h = math.max(1, math.floor(safe.h * 0.4)) }
end
function Overflow.show(panel, blocks, width, playerNum)
	if not panel or not panel.item or not UI.Tooltip.createScrollableSections then return false end
	local state = panel._gsObjectOverflow
	if state and state.item ~= panel.item then Overflow.release(panel); state = nil end
	if not state then
		state = { item = panel.item, owner = panel.owner, followMouse = panel.followMouse,
			anchorBottomLeft = panel.anchorBottomLeft, lastInside = now() }
		state.container = panel.item.getContainer and panel.item:getContainer() or nil
		state.handle = UI.Tooltip.createScrollableSections({ playerNum = playerNum,
			backgroundColor = { r = 0.05, g = 0.05, b = 0.05, a = 0.85 },
			borderColor = { r = 0.9, g = 0.9, b = 1, a = 0.6 },
			onClose = function()
				state.dismissed = true
				restoreHost(panel, state)
			end,
			onInvalid = function() Overflow.release(panel) end,
			isValid = function() return live(panel, state) end })
		panel._gsObjectOverflow = state
		-- Freeze only this instance while its annex can be entered. Never replace
		-- ISToolTipInv.render or the vanilla class-level inventory lifecycle here.
		panel.followMouse, panel.anchorBottomLeft = false, nil
		if state.owner and type(state.owner.updateTooltip) == "function" then
			state.previousOwnerUpdate = state.owner.updateTooltip
			state.ownerWrapper = function(owner, ...)
				if Overflow.isRetained(panel) then return end
				local result = state.previousOwnerUpdate(owner, ...)
				if not live(panel, state) then Overflow.release(panel) end
				return result
			end
			state.owner.updateTooltip = state.ownerWrapper
		end
	end
	if state.dismissed then return false end
	if state.owner and inside(rect(state.owner)) then state.lastInside = now() end
	local sections, identity = {}, {}
	for index = 1, #blocks do
		local block = blocks[index]
		sections[index] = UI.Tooltip.objectSection(block.lines, { font = UIFont.Small,
			lineColor = block.color, framed = false, paddingX = 8, paddingY = 4 })
		for line = 1, #(block.lines or {}) do identity[#identity + 1] = tostring(block.lines[line]) end
		identity[#identity + 1] = "\30"
	end
	local documentKey = table.concat(identity, "\31")
	local result = state.handle:update(sections, documentKey, Overflow.bounds(panel, width, playerNum))
	if not result then Overflow.release(panel) end
	return result ~= nil
end
return Overflow
