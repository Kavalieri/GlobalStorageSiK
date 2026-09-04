-- Author contract for public controls and one-rect VirtualList/Table geometry.

local Support = dofile("tests/helpers/sik_ui_contract_support.lua")
local suite = Support.newSuite("sik_ui_controls_table_list_contract")
local Controls = Support.loadFrameworkModule(suite, "Controls")
local VirtualList = Support.loadFrameworkModule(suite, "VirtualList")
local Table = Support.loadFrameworkModule(suite, "Table")

getTextManager = function()
	return { MeasureStringX = function(_, _, text) return #tostring(text or "") * 6 end,
		getFontHeight = function() return 12 end }
end

local controlMetrics = Support.requireFunction(suite, Controls, "metrics", "Controls.metrics")
local rowRect = Support.requireFunction(suite, Table, "rowRect", "Table.rowRect")
local hitRect = Support.requireFunction(suite, Table, "hitRect", "Table.hitRect")

if controlMetrics then
	Support.check(suite, "controls expose one canonical height and gap set per profile", function()
		for _, profile in ipairs({ "compact", "standard", "wide" }) do
			local metrics = controlMetrics(profile)
			for _, key in ipairs({ "buttonHeight", "inputHeight", "rowGap", "controlGap" }) do
				Support.assertNumber(metrics[key], profile .. "." .. key)
				assert(metrics[key] > 0, profile .. "." .. key .. " must be positive")
			end
			assert(metrics.buttonHeight == metrics.inputHeight,
				profile .. " button/input heights must align")
		end
		return true
	end)
end

Support.check(suite, "decorative icons tolerate bridges without mouse transparency", function()
	local parent = Controls.panel(nil, { x = 0, y = 0, w = 64, h = 64 })
	local ok, icon = pcall(Controls.icon, parent, { x = 4, y = 4, w = 24, h = 24 })
	assert(ok and icon, "decorative icon creation failed without setMouseTransparent")
	assert(type(icon.onMouseDown) == "function" and icon:onMouseDown() == false,
		"decorative icon intercepted mouse input")
	return true
end)

Support.check(suite, "public table columns consume contentW and end at its right edge", function()
	local columns = {
		{ key = "name", flex = 1, minWidth = 80 },
		{ key = "status", width = 96, align = "right" },
	}
	local layout = Table.resolveColumns(720, columns, { left = 0, right = 0, gap = 4 })
	assert(layout[1].x == 0, "table added left reservation")
	assert(layout[#layout].finish == 720, "table added right/double gutter")
	return true
end)

Support.check(suite, "table follows the Block rect without owning a scrollbar gutter", function()
	local columns = {
		{ key = "name", flex = 1, minWidth = 80 },
		{ key = "status", width = 96, align = "right" },
	}
	local shortRect = { x = 8, y = 8, w = 484, h = 280, scrollGutter = 0 }
	local longRect = { x = 8, y = 8, w = 460, h = 280, scrollGutter = 24 }
	local short = Table.resolve(shortRect, columns, { left = 0, right = 0, gap = 4 })
	local long = Table.resolve(longRect, columns, { left = 0, right = 0, gap = 4 })
	assert(short.contentRect.x == long.contentRect.x, "table shifted its left edge")
	assert(short.columns[#short.columns].finish == shortRect.w, "short edge mismatch")
	assert(long.columns[#long.columns].finish == longRect.w, "overflow edge mismatch")
	return true
end)

if rowRect and hitRect then
	Support.check(suite, "header row and hitbox share the same table rectangle", function()
		local content = { x = 108, y = 80, w = 720, h = 400 }
		local row = rowRect(content, 2)
		local hit = hitRect(content, 2)
		assert(row.x == content.x and row.w == content.w, "row rect mismatch")
		assert(hit.x == row.x and hit.y == row.y and hit.w == row.w and hit.h == row.h,
			"hitbox differs from rendered row")
		return true
	end)
end

Support.check(suite, "List and Table have exact public owners and no Core alias", function()
	assert(SiK.UI.Controls == Controls and SiK.UI.VirtualList == VirtualList
		and SiK.UI.Table == Table, "public owner mismatch")
	assert(rawget(_G, "GlobalStorageSiK") == nil
		or rawget(GlobalStorageSiK, "SiK_UI") == nil,
		"private Core namespace recreated")
	return true
end)

Support.finish(suite)
