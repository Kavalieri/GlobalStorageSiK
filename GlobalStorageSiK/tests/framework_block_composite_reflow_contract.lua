-- Executes the real Block placement path with a composite Table-like handle.
local root = arg[1] or "."
local framework = root
	.. "/SiKUIFramework-Repo/SiKUIFramework/Contents/mods/SiKUIFramework/42/media/lua/client/SiK/UI/"
SiK = { UI = { Namespace = { define = function(_, value) return value end } } }
local function panel(parent)
	local value = { parent = parent, width = 0, height = 0 }
	function value:addChild(child) child.parent = self end
	function value:removeChild(child) if child.parent == self then child.parent = nil end end
	return value
end
SiK.UI.Container = { create = function(options)
	local value = panel(options.parent)
	if options.parent and options.parent.addChild then options.parent:addChild(value) end
	function value:dispose() self.disposed = true end
	return { panel = value, dispose = function(self) self.panel:dispose() end }
end }
SiK.UI.Theme = { tokens = function() return { surface = {}, border = {} } end }
SiK.UI.Controls = { metrics = function() return { rowHeight = 30 } end,
	blockHeader = function() return nil end }
SiK.UI.Metrics = {
	tokens = function() return { block = { padding = 8, scrollGutter = 24,
		scrollBarWidth = 14, scrollGap = 10 }, spacing = { sm = 8 } } end,
	blockRects = function(w, h, overflow)
		return { x = 8, y = 8, w = math.max(0, w - 16 - (overflow and 24 or 0)),
			h = math.max(0, h - 16) }, nil
	end,
}
SiK.UI.Layout = {
	apply = function(widget, rect)
		widget.x, widget.y, widget.width, widget.height = rect.x, rect.y, rect.w, rect.h
	end,
	column = function(options)
		local column = { startY = options.y, cursor = options.y, gap = options.gap,
			position = options.position }
		function column:add(widget, height)
			self.position(widget, options.x, self.cursor, options.w, height)
			self.cursor = self.cursor + height + self.gap
			return widget
		end
		return column
	end,
}
package.preload["SiK/UI/Container"] = function() return SiK.UI.Container end
package.preload["SiK/UI/Controls"] = function() return SiK.UI.Controls end
package.preload["SiK/UI/Metrics"] = function() return SiK.UI.Metrics end
package.preload["SiK/UI/Layout"] = function() return SiK.UI.Layout end
package.preload["SiK/UI/Theme"] = function() return SiK.UI.Theme end
local Block = dofile(framework .. "Block.lua")

local host, foreign = panel(nil), panel(nil)
local block = assert(Block.create({ parent = host, x = 0, y = 0, w = 200, h = 120 }))
local composite = { panel = panel(foreign), calls = 0 }
function composite:reflow(rect)
	self.calls, self.rect = self.calls + 1, rect
	SiK.UI.Layout.apply(self.panel, rect)
	return self
end
local column = block:beginColumn()
column:add(composite, 40)
column:finish()
assert(composite.panel.parent == block.childParent, "composite root was not adopted")
assert(composite.calls == 1, "composite reflow was not called exactly once")
assert(composite.rect.x == 8 and composite.rect.y == 8 and composite.rect.w == 184
	and composite.rect.h == 40, "composite received non-canonical Block geometry")
print("framework_block_composite_reflow_contract: OK")
