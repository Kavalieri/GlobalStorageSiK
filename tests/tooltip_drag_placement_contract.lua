-- Author contract for tooltip placement and drag coexistence.
-- Geometry is exercised without a PZ window manager; source assertions bind
-- the matrix to the real wrapper and prevent a reference-only false PASS.

local Support = dofile("tests/helpers/sik_ui_contract_support.lua")
local suite = Support.newSuite("tooltip_drag_placement_contract")

local CLIENT = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/"
local function read(path)
	local file = assert(io.open(path, "rb"), path)
	local text = file:read("*a")
	file:close()
	return text
end

local function contains(text, needle, label)
	assert(text:find(needle, 1, true), label or ("missing " .. needle))
end

local function excludes(text, needle, label)
	assert(not text:find(needle, 1, true), label or ("unexpected " .. needle))
end

local function countPlain(text, needle)
	local count, at = 0, 1
	while true do
		local found = text:find(needle, at, true)
		if not found then return count end
		count = count + 1
		at = found + #needle
	end
end

local function section(text, first, last)
	local from = assert(text:find(first, 1, true), "missing section start " .. first)
	local to = last and assert(text:find(last, from + #first, true),
		"missing section end " .. last) or #text + 1
	return text:sub(from, to - 1)
end

local tooltipSource = read(CLIENT .. "GS_ItemNetworkTooltip.lua")
local dragSource = read(CLIENT .. "GS_TerminalWithdrawDrag.lua")
local placementSource = section(tooltipSource,
	"local function placeMeasuredTooltip", "local function drawNetworkExtension")
local fixedPlacementSource = section(placementSource,
	"if panel.followMouse == false or (panel.contextMenu and panel.contextMenu.joyfocus) then",
	"local anchorX = getMouseX")
local movingPlacementSource = section(placementSource,
	"local anchorX = getMouseX", "return true\nend")
local fallbackSource = section(tooltipSource,
	"local function safeFallbackRender", "local function buildTooltipBlocks")
local wrapperSource = section(tooltipSource,
	"wrapperBody = function", "ISToolTipInv.render = wrapper")

-- Mirrors the deliberately tiny pure axis contract in production. Source
-- checks below require that implementation and its ordering to remain exact.
local GUTTER = 16
local function axisPlacement(anchor, size, low, high)
	local forward = anchor + GUTTER
	if forward + size <= high then return forward end
	local backward = anchor - size - GUTTER
	if backward >= low then return backward end
	return nil
end

local function place(anchorX, anchorY, width, height, viewport)
	local x = axisPlacement(anchorX, width, viewport.x, viewport.x + viewport.w)
	local y = axisPlacement(anchorY, height, viewport.y, viewport.y + viewport.h)
	if x == nil or y == nil then return nil end
	return { x = x, y = y }
end

local viewport = { x = 100, y = 50, w = 800, h = 600 }
local cases = {
	{ name = "interior prefers right and down", ax = 300, ay = 200, w = 160, h = 100,
		x = 316, y = 216 },
	{ name = "right edge inverts left", ax = 860, ay = 200, w = 160, h = 100,
		x = 684, y = 216 },
	{ name = "bottom edge inverts up", ax = 300, ay = 620, w = 160, h = 100,
		x = 316, y = 504 },
	{ name = "bottom-right corner inverts left and up", ax = 860, ay = 620,
		w = 160, h = 100, x = 684, y = 504 },
	{ name = "top-left uses safe forward placement", ax = 100, ay = 50,
		w = 160, h = 100, x = 116, y = 66 },
}

for i = 1, #cases do
	local case = cases[i]
	Support.check(suite, case.name, function()
		local result = assert(place(case.ax, case.ay, case.w, case.h, viewport),
			"safe placement unexpectedly absent")
		assert(result.x == case.x and result.y == case.y,
			string.format("got %s,%s expected %s,%s", result.x, result.y, case.x, case.y))
		return true
	end)
end

Support.check(suite, "oversize annex is withheld instead of overlapping cursor", function()
	assert(place(500, 350, 790, 590, viewport) == nil,
		"unsafe placement should have no result")
	return true
end)

Support.check(suite, "production measures complete tooltip before final placement", function()
	contains(tooltipSource, "local neededW, extensionH = extensionMetrics(blocks, self.width)")
	contains(tooltipSource, "self, self.item, neededW, baseH + extensionH")
	local measuredAt = assert(wrapperSource:find("extensionMetrics(blocks, self.width)", 1, true))
	local placedAt = assert(wrapperSource:find("placeMeasuredTooltip(", 1, true))
	assert(measuredAt < placedAt, "placement occurs before width/height measurement")
	return true
end)

Support.check(suite, "production prefers forward axes then inverts with canonical gutter", function()
	contains(tooltipSource, "local TOOLTIP_GUTTER = 24")
	contains(tooltipSource, "local forward = anchor + TOOLTIP_GUTTER")
	contains(tooltipSource, "local backward = anchor - size - TOOLTIP_GUTTER")
	contains(tooltipSource, "if forward + size <= high then return forward end")
	contains(tooltipSource, "if backward >= low then return backward end")
	return true
end)

Support.check(suite, "placement resolves the owning player's safe viewport", function()
	contains(placementSource, "local playerNum = playerNumForItem(item)")
	contains(placementSource, "Viewport.resolve(playerNum)")
	contains(placementSource, "viewport.x + viewport.w")
	contains(placementSource, "viewport.y + viewport.h")
	return true
end)

Support.check(suite, "fixed and joypad tooltips preserve their vanilla panel anchor", function()
	contains(fixedPlacementSource,
		"panel.followMouse == false or (panel.contextMenu and panel.contextMenu.joyfocus)",
		"fixed/joypad placement branch missing")
	contains(fixedPlacementSource, "panel:getX()", "fixed branch discards panel x")
	contains(fixedPlacementSource, "panel:getY()", "fixed branch discards panel y")
	contains(fixedPlacementSource, "panel:setX(x)", "fixed branch does not preserve adjusted x")
	contains(fixedPlacementSource, "panel:setY(y)", "fixed branch does not preserve adjusted y")
	excludes(fixedPlacementSource, "getMouseX", "fixed branch reads the global mouse x")
	excludes(fixedPlacementSource, "getMouseY", "fixed branch reads the global mouse y")
	excludes(fixedPlacementSource, "axisPlacement", "fixed branch replaces vanilla anchor with cursor flipping")
	return true
end)

Support.check(suite, "follow-mouse tooltip still flips against the player viewport", function()
	contains(movingPlacementSource, "getMouseX", "follow-mouse branch lost cursor x")
	contains(movingPlacementSource, "getMouseY", "follow-mouse branch lost cursor y")
	contains(movingPlacementSource, "axisPlacement(anchorX, width, viewport.x, right)",
		"follow-mouse branch no longer flips horizontally inside the viewport")
	contains(movingPlacementSource, "axisPlacement(anchorY, totalHeight, viewport.y, bottom)",
		"follow-mouse branch no longer flips vertically inside the viewport")
	return true
end)

Support.check(suite, "clamp is fallback guardrail and annex has no unsafe draw path", function()
	excludes(placementSource, "math.max", "primary placement clamps horizontally")
	excludes(placementSource, "math.min", "primary placement clamps vertically")
	contains(fallbackSource, "math.max(viewport.x, math.min(mx, viewport.x + viewport.w - tw))")
	contains(fallbackSource, "math.max(viewport.y, math.min(my, viewport.y + viewport.h - th))")
	contains(wrapperSource, "if #blocks > 0 and placeMeasuredTooltip(")
	local guarded = section(wrapperSource,
		"if #blocks > 0 and placeMeasuredTooltip(", "end\n\t\tend)")
	contains(guarded, "drawNetworkExtension(", "annex not guarded by safe placement")
	return true
end)

Support.check(suite, "drag suppresses the complete tooltip and both overlays ignore mouse", function()
	contains(tooltipSource, "if withdrawDragActive() then")
	contains(tooltipSource, "if self.setVisible then self:setVisible(false) end")
	contains(tooltipSource, "panel.javaObject:setConsumeMouseEvents(false)")
	contains(dragSource, "panel.javaObject:setConsumeMouseEvents(false)")
	contains(dragSource, "makeMouseTransparent(dragPreviewPanel)")
	return true
end)

Support.check(suite, "wrapper remains single and does not add remote tooltip renders", function()
	assert(countPlain(tooltipSource, "ISToolTipInv.render = wrapper") == 1,
		"tooltip render wrapper is not installed exactly once")
	contains(tooltipSource, "if not FEATURE_ENABLED or hooksInstalled then")
	assert(countPlain(tooltipSource, ":DoTooltip(") == 2,
		"unexpected DoTooltip call added outside the measured fallback")
	assert(countPlain(fallbackSource, ":DoTooltip(") == 2,
		"DoTooltip calls escaped the local vanilla fallback")
	excludes(tooltipSource, "RemoteItemDetail.DoTooltip")
	return true
end)

Support.finish(suite)
