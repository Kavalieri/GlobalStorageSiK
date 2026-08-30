-- Author contract for responsive windows, scrollable blocks and modals.

local Support = dofile("tests/helpers/sik_ui_contract_support.lua")
local suite = Support.newSuite("sik_ui_window_block_modal_contract")

Support.loadClientModule(suite, "GS_SiK_UI_Metrics")
Support.loadClientModule(suite, "GS_SiK_UI_Window")
Support.loadClientModule(suite, "GS_SiK_UI_Block")
Support.loadClientModule(suite, "GS_SiK_UI_Modal")

local ui = GlobalStorageSiK and GlobalStorageSiK.SiK_UI or {}
local Window = ui.Window
local Block = ui.Block
local Modal = ui.Modal
local resolveWindow = Support.requireFunction(suite, Window, "resolveProfile", "Window.resolveProfile")
local resolveBlock = Support.requireFunction(suite, Block, "resolveContentRect", "Block.resolveContentRect")
local resolveModal = Support.requireFunction(suite, Modal, "resolve", "Modal.resolve")

local viewport = { x = 16, y = 16, w = 1248, h = 688, profile = "standard", playerNum = 0 }

if resolveWindow then
	Support.check(suite, "window is bounded and landscape when the viewport permits it", function()
		local rect = resolveWindow("standard", viewport, { contentMinW = 640, contentMinH = 360 })
		Support.assertWithin(rect, viewport, "window")
		assert(rect.w > rect.h, "preferred standard window must be landscape")
		return true
	end)

	Support.check(suite, "compact window degrades within viewport instead of overflowing", function()
		local compactViewport = { x = 16, y = 16, w = 448, h = 608,
			profile = "compact", playerNum = 1 }
		local rect = resolveWindow("compact", compactViewport,
			{ contentMinW = 640, contentMinH = 480 })
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
		local rect = resolveModal("standard", { w = 2000, h = 1600 }, viewport)
		Support.assertWithin(rect, viewport, "modal")
		assert(rect.w <= math.floor(viewport.w * 0.70), "modal width cap")
		assert(rect.h <= math.floor(viewport.h * 0.80), "modal height cap")
		return true
	end)

	Support.check(suite, "small modal remains landscape and content-sized", function()
		local rect = resolveModal("standard", { w = 360, h = 160 }, viewport)
		Support.assertWithin(rect, viewport, "small modal")
		assert(rect.w > rect.h, "small modal is landscape")
		assert(rect.w >= 360 and rect.h >= 160, "content is not clipped")
		return true
	end)
end

Support.finish(suite)
