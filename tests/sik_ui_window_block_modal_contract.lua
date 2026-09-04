-- Author contract for responsive windows, scrollable blocks and modals.

local Support = dofile("tests/helpers/sik_ui_contract_support.lua")
local suite = Support.newSuite("sik_ui_window_block_modal_contract")

local Window = Support.loadFrameworkModule(suite, "Window")
local Block = Support.loadFrameworkModule(suite, "Block")
local Modal = Support.loadFrameworkModule(suite, "Modal")
local resolveWindow = Support.requireFunction(suite, Window, "resolveBounds", "Window.resolveBounds")
local resolveBlock = Support.requireFunction(suite, Block, "resolveContentRect", "Block.resolveContentRect")
local resolveModal = Support.requireFunction(suite, Modal, "resolve", "Modal.resolve")

local viewport = { x = 16, y = 16, w = 1248, h = 688, profile = "standard", playerNum = 0 }

if resolveWindow then
	Support.check(suite, "window is bounded and landscape when the viewport permits it", function()
		local rect = resolveWindow({ profile = "standard", playerNum = 0,
			width = 900, height = 560, minWidth = 640, minHeight = 360,
			environment = { playerRect = function() return viewport end } })
		Support.assertWithin(rect, viewport, "window")
		assert(rect.w > rect.h, "preferred standard window must be landscape")
		return true
	end)

	Support.check(suite, "compact window degrades within viewport instead of overflowing", function()
		local compactViewport = { x = 16, y = 16, w = 448, h = 608,
			profile = "compact", playerNum = 1 }
		local rect = resolveWindow({ profile = "compact", playerNum = 1,
			width = 700, height = 640, minWidth = 640, minHeight = 480,
			environment = { playerRect = function() return compactViewport end } })
		Support.assertWithin(rect, compactViewport, "compact window")
		return true
	end)
end

if resolveBlock then
	Support.check(suite, "scrollable block reserves gutter only while content overflows", function()
		local bounds = { x = 40, y = 70, w = 760, h = 420 }
		local short = resolveBlock(bounds, { scrollable = true, contentHeight = 120 })
		local long = resolveBlock(bounds, { scrollable = true, contentHeight = 1200 })
		Support.assertWithin(short, bounds, "short block content")
		Support.assertWithin(long, bounds, "long block content")
		assert(short.x == bounds.x + 8 and long.x == short.x, "canonical left padding")
		assert(short.w == 744, "short content recovers the full W - 16 width")
		assert(long.w == 720, "overflow content reserves W - 40")
		assert(short.scrollGutter == 0 and not short.overflow, "short block has no dead gutter")
		assert(long.scrollGutter == 24 and long.overflow, "long block owns one gutter")
		return true
	end)

	Support.check(suite, "non-tabular scrollable block uses the same reservation", function()
		local list = resolveBlock({ x = 0, y = 0, w = 500, h = 300 },
			{ scrollable = true, kind = "form", contentHeight = 800 })
		assert(list.w == 460, "form content is W - 40")
		assert(list.scrollGutter == 24, "form uses block gutter")
		return true
	end)

	Support.check(suite, "fill block keeps height and dynamically resolves horizontal overflow", function()
		local bounds = { x = 20, y = 30, w = 600, h = 360 }
		local short = Block.resolveLayout(bounds,
			{ fill = true, scrollable = true, headerHeight = 30, contentHeight = 80 })
		local long = Block.resolveLayout(bounds,
			{ fill = true, scrollable = true, headerHeight = 30, contentHeight = 900 })
		assert(short.bodyRect.h == long.bodyRect.h, "fill body height changed with content")
		assert(short.contentRect.x == long.contentRect.x, "left edge shifted with scrollbar")
		assert(short.contentRect.w - long.contentRect.w == 24, "dynamic gutter is not exactly 24")
		return true
	end)
end

if resolveModal then
	Support.check(suite, "modal caps width at 70 percent and height at 80 percent", function()
		local rect = resolveModal("standard", { w = 2000, h = 1600 }, {
			playerNum = 0, environment = { playerRect = function() return viewport end } })
		Support.assertWithin(rect, viewport, "modal")
		assert(rect.w <= math.floor(viewport.w * 0.70), "modal width cap")
		assert(rect.h <= math.floor(viewport.h * 0.80), "modal height cap")
		return true
	end)

	Support.check(suite, "small modal remains landscape and content-sized", function()
		local rect = resolveModal("standard", { w = 360, h = 160 }, {
			playerNum = 0, environment = { playerRect = function() return viewport end } })
		Support.assertWithin(rect, viewport, "small modal")
		assert(rect.w > rect.h, "small modal is landscape")
		assert(rect.w >= 360 and rect.h >= 160, "content is not clipped")
		return true
	end)

	Support.check(suite, "owned modal remains above its owner without global always-on-top", function()
		local order = {}
		local owner = { playerNum = 0 }
		function owner:bringToTop() order[#order + 1] = "owner" end
		local originalBring = owner.bringToTop
		local child = { playerNum = 0, visible = true, _sikModal = true,
			_sikModalOwner = owner }
		function child:getIsVisible() return self.visible end
		function child:bringToTop() order[#order + 1] = "modal" end
		function child:show() self.visible = true; self:bringToTop() end
		function child:close() self.visible = false; return true end
		assert(Modal.show(child) == child, "owned modal did not open")
		order = {}
		Modal.raiseOwner(owner)
		assert(table.concat(order, ",") == "owner,modal",
			"owner activation did not preserve owner -> modal order")
		assert(owner.bringToTop ~= originalBring, "owner was not scoped while modal was open")
		assert(Modal.topForOwner(owner) == child, "owner cannot resolve its top modal")
		assert(Modal.close(child, "test") == true, "owned modal did not close")
		assert(owner.bringToTop == originalBring, "owner binding leaked after last modal closed")
		order = {}
		owner:bringToTop()
		assert(table.concat(order, ",") == "owner", "closed modal was raised again")
		return true
	end)
end

Support.check(suite, "task modals resize only by explicit opt-in", function()
	local file = assert(io.open(Support.frameworkPath("Modal.lua"), "rb"))
	local source = file:read("*a"); file:close()
	assert(source:find("options.resizable = false", 1, true), "apply does not default to fixed")
	assert(source:find("windowOptions.resizable = windowOptions.resizable == true", 1, true),
		"create still forces task modals resizable")
	assert(not source:find('or kind == "task"', 1, true), "task kind still implies resize")
	return true
end)

Support.check(suite, "Window Block and Modal are published only by SiK.UI", function()
	assert(SiK.UI.Window == Window and SiK.UI.Block == Block and SiK.UI.Modal == Modal,
		"public owner mismatch")
	assert(rawget(_G, "GlobalStorageSiK") == nil
		or rawget(GlobalStorageSiK, "SiK_UI") == nil,
		"private Core namespace recreated")
	return true
end)

Support.finish(suite)
