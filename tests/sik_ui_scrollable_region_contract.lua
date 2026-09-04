-- Public SiK.UI contract for dynamic Block gutter and shared scroll geometry.

local FRAMEWORK = "../SiKUIFramework-Repo/SiKUIFramework/Contents/mods/"
	.. "SiKUIFramework/42/media/lua/client/SiK/UI/"

local function read(path)
	local handle = assert(io.open(path, "rb"), "cannot read " .. path)
	local source = handle:read("*a")
	handle:close()
	return source
end

local function contains(source, needle, label)
	assert(source:find(needle, 1, true), label or ("missing " .. needle))
end

local function excludes(source, needle, label)
	assert(not source:find(needle, 1, true), label or ("unexpected " .. needle))
end

SiK = {}
assert(dofile(FRAMEWORK .. "Namespace.lua"))
package.loaded["SiK/UI/Namespace"] = true
local Metrics = assert(dofile(FRAMEWORK .. "Metrics.lua"))

local tokens = Metrics.tokens()
assert(tokens.block.padding == 8, "Block padding must remain 8 px")
assert(tokens.block.scrollBarWidth == 14, "scrollbar width must remain 14 px")
assert(tokens.block.scrollGap == 10, "content/bar gap must remain 10 px")
assert(tokens.block.scrollGutter == 24, "overflow gutter must remain 24 px")

local short, shortTrack = Metrics.blockRects(500, 300, false, 0, 0)
assert(short.x == 8 and short.w == 484, "short Block must expose W - 16")
assert(shortTrack == nil, "short Block must not retain a dead scrollbar track")

local long, longTrack = Metrics.blockRects(500, 300, true, 0, 0)
assert(long.x == short.x, "overflow must not move the left edge")
assert(long.w == 460, "overflow must reserve exactly one 24 px gutter")
assert(longTrack and longTrack.x == 478 and longTrack.w == 14,
	"scrollbar must occupy the canonical track after the 10 px gap")

local shortAgain, noTrack = Metrics.blockRects(600, 300, false, 0, 0)
assert(shortAgain.x == 8 and shortAgain.w == 584,
	"resize without overflow must recover the complete content width")
assert(noTrack == nil, "resize must not force a scrollbar")

local block = read(FRAMEWORK .. "Block.lua")
local scroll = read(FRAMEWORK .. "Scroll.lua")
local tableSource = read(FRAMEWORK .. "Table.lua")
contains(block, "self.contentHeight > baseContent.h", "Block must own overflow detection")
contains(block, "self.scroll:setGeometry(self.contentRect, self.trackRect)",
	"Block must publish the same rect to Scroll")
contains(scroll, "function ScrollInstance:setGeometry", "Scroll must accept Block geometry")
contains(scroll, "function ScrollInstance:setContentHeight", "Scroll must clamp content changes")
contains(scroll, "return instance:scrollBy((tonumber(delta)",
	"legacy and modern scroll regions must preserve B42 runtime wheel direction")
contains(tableSource, "block:getContentRect()", "Table must consume the Block content rect")
excludes(tableSource, "scrollGutter", "Table must not reserve a second gutter")
excludes(tableSource, "scrollBarWidth", "Table must not know scrollbar width")
excludes(tableSource, "scrollBarGap", "Table must not know scrollbar gap")

print("sik_ui_scrollable_region_contract: OK")
