-- Regression test for Core 1.4.3-dev32.4 shared SiK UI table resize.
-- Run from GlobalStorageSiK-Repo: lua51.exe tests/sik_ui_table_resize_regression.lua

package.loaded["GS_SiK_UI_Core"] = true
package.loaded["GS_TerminalUI_Scroll"] = true

UIFont = { Small = "Small" }
function getTextManager()
	return { MeasureStringX = function(_, _, text) return #tostring(text or "") * 6 end,
		getFontHeight = function() return 12 end }
end

ISPanel = {
	onMouseDown = function() return false end,
	onMouseMove = function() return false end,
	onMouseUp = function() return false end,
}
GlobalStorageSiK = {
	SiK_UI = { Table = {} },
	I18n = { text = function(key) return key end },
}

local function assertEqual(actual, expected, message)
	if actual ~= expected then
		error((message or "values differ") .. ": expected=" .. tostring(expected)
			.. " actual=" .. tostring(actual), 2)
	end
end

dofile("GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/GS_SiK_UI_Table.lua")

local Table = GlobalStorageSiK.SiK_UI.Table
local columns = {
	{ key = "name", flex = 1, minWidth = 80 },
	{ key = "category", flex = 1, minWidth = 100 },
	{ key = "zone", width = 72 },
	{ key = "count", width = 48, align = "right" },
}
local options = { left = 0, right = 0, gap = 4 }
local header = { width = 420 }
local sorts = 0
header.onMouseUp = function() sorts = sorts + 1 return true end
Table.attachHeaderResize(header, columns, options)

local before = Table.resolveColumns(header.width, columns, options)
local boundary = before[1].finish
assert(header:onMouseDown(boundary, 4), "shared divider must start a drag")
assert(header:onMouseMove(28, 0), "drag must be handled by the common helper")
assert(header:onMouseUp(boundary + 28, 4), "drag release must be handled")
local after = Table.resolveColumns(header.width, columns, options)
assertEqual(after[1].width, before[1].width + 28, "left column follows the divider")
assertEqual(after[2].width, before[2].width - 28, "adjacent column gives the same width")
assertEqual(after[4].finish, before[4].finish, "right-anchored quantity remains at the table edge")
assertEqual(sorts, 0, "a resize never triggers column sorting")

assert(not header:onMouseDown(12, 4), "ordinary header click is not claimed as resize")
assert(header:onMouseUp(12, 4), "ordinary header click reaches the original handler")
assertEqual(sorts, 1, "sort handler remains intact after common resize wiring")

print("sik_ui_table_resize_regression: OK")
