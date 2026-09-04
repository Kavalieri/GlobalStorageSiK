-- Regression contract for public SiK.UI.Table resize and sort interaction.

local Support = dofile("tests/helpers/sik_ui_contract_support.lua")
local suite = Support.newSuite("sik_ui_table_resize_regression")
local Table = Support.loadFrameworkModule(suite, "Table")

local columns = {
	{ key = "name", title = "Name", flex = 1, minWidth = 80, sortable = true },
	{ key = "category", title = "Category", flex = 1, minWidth = 100 },
	{ key = "zone", title = "Zone", width = 72 },
	{ key = "count", title = "Count", width = 48, align = "right" },
}
local parent = ISPanel:new(0, 0, 500, 360); parent:initialise()
local sorts, resizeEvents = 0, 0
local instance = assert(Table.create({
	parent = parent, x = 0, y = 0, w = 420, h = 260,
	columns = columns, gap = 4, rows = {},
	onSort = function() sorts = sorts + 1 end,
	onColumnResize = function() resizeEvents = resizeEvents + 1 end,
}))

Support.check(suite, "drag redistributes adjacent widths and preserves right edge", function()
	local header = instance.header
	local before = instance.columnLayout
	local boundary = before[1].finish
	local leftBefore, rightBefore, finalEdge = before[1].width, before[2].width,
		before[#before].finish
	assert(header:onMouseDown(boundary, 4), "shared divider must start a drag")
	assert(header:onMouseMove(28, 0), "drag must be handled by Table")
	assert(header:onMouseUp(boundary + 28, 4), "drag release must be handled")
	local after = instance.columnLayout
	assert(after[1].width == leftBefore + 28, "left column did not follow divider")
	assert(after[2].width == rightBefore - 28, "adjacent column did not yield width")
	assert(after[#after].finish == finalEdge, "right-anchored quantity moved")
	assert(resizeEvents == 1 and sorts == 0, "resize emitted wrong callbacks")
	return true
end)

Support.check(suite, "ordinary sortable header click remains intact", function()
	local header = instance.header
	assert(header:onMouseDown(12, 4) == false, "ordinary click was claimed as resize")
	assert(header:onMouseUp(12, 4) == true, "ordinary sortable click was ignored")
	assert(sorts == 1 and instance.sortKey == "name", "sort callback/state changed")
	return true
end)

Support.check(suite, "resize owner is exact public Table instance", function()
	assert(SiK.UI.Table == Table, "Table is not owned by SiK.UI")
	assert(instance.header._sikTable == instance, "header lost its public Table owner")
	instance:dispose()
	return true
end)

Support.finish(suite)
