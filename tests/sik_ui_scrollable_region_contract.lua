-- Author contract for dynamic Block gutter and TerminalScroll notifications.

package.loaded["GS_SiK_UI_Core"] = true
package.loaded["ISUI/ISPanel"] = true

GlobalStorageSiK = {
	SiK_UI = {
		CHROME = {
			headerHeight = 48,
			closeButtonSize = 36,
			horizontalPadding = 14,
			titleCloseGap = 12,
		},
	},
	Log = { error = function() end, debug = function() end },
}
GlobalStorageSiK.SiK_UI.windowChrome = function()
	return GlobalStorageSiK.SiK_UI.CHROME
end
ISPanel = {
	prerender = function() end,
	render = function() end,
}

local root = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/"
dofile(root .. "GS_SiK_UI_Metrics.lua")
dofile(root .. "GS_SiK_UI_Block.lua")
dofile(root .. "GS_TerminalUI_Scroll.lua")

local Scroll = GlobalStorageSiK.TerminalScroll
local fake = { width = 500, height = 300, _gsContentHeight = 0, _gsScrollMode = "rows" }
function fake:setWidth(value) self.width = value end
function fake:setHeight(value) self.height = value end
local changes = 0
local lastReason

Scroll.setOnContentRectChanged(fake, function(_, current, previous, reason)
	assert(type(current) == "table", "current rect required")
	assert(type(previous) == "table", "previous rect required after initial bind")
	changes = changes + 1
	lastReason = reason
end)

local short = Scroll.contentRect(fake)
assert(short.x == 8 and short.w == 484, "short region must be W - 16")
assert(short.scrollGutter == 0 and not short.overflow, "short region has dead gutter")

-- Establish the initial bound rect, then cross the overflow threshold.
GlobalStorageSiK.SiK_UI.Block.bindScrollable(fake, { contentHeight = 0 })
Scroll.setContentHeight(fake, 600)
local long = Scroll.contentRect(fake)
assert(long.x == short.x, "left edge moved when scrollbar appeared")
assert(long.w == 460 and long.scrollGutter == 24 and long.overflow,
	"overflow region must reserve exactly 24 px")
assert(changes == 1 and lastReason == "content", "overflow transition not notified once")
Scroll.setScrollBarsVisible(fake, false)
assert(fake._gsScrollBarsHidden == false, "legacy visibility hid a required overflow bar")

fake._gsScrollOffset = 120
Scroll.setContentHeight(fake, 80)
local shortAgain = Scroll.contentRect(fake)
assert(shortAgain.w == 484 and not shortAgain.overflow, "gutter did not disappear")
assert(fake._gsScrollOffset == 0, "short content did not clamp stale offset")
assert(changes == 2, "gutter removal not notified once")
Scroll.setScrollBarsVisible(fake, true)
assert(fake._gsScrollBarsHidden == true, "legacy visibility forced a bar without overflow")

Scroll.resize(fake, 600, 300)
local resized = Scroll.contentRect(fake)
assert(resized.x == 8 and resized.w == 584, "resize did not preserve dynamic short geometry")
assert(changes == 3 and lastReason == "resize", "resize transition not notified")

print("sik_ui_scrollable_region_contract: OK")
