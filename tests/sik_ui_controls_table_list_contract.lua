-- Author contract for shared controls and one-rect List/Table geometry.

local Support = dofile("tests/helpers/sik_ui_contract_support.lua")
local suite = Support.newSuite("sik_ui_controls_table_list_contract")

package.loaded["ISUI/ISButton"] = true
ISPanel = ISPanel or {
	onMouseDown = function() return false end,
	onMouseMove = function() return false end,
	onMouseUp = function() return false end,
}

Support.loadClientModule(suite, "GS_SiK_UI_Metrics")
Support.loadClientModule(suite, "GS_SiK_UI_Controls")
Support.loadClientModule(suite, "GS_SiK_UI_List")

-- Table already exists and can run under small PZ mocks.
package.loaded["GS_SiK_UI_Core"] = true
package.loaded["GS_TerminalUI_Scroll"] = true
UIFont = UIFont or { Small = "Small" }
function getTextManager()
	return {
		MeasureStringX = function(_, _, text) return #tostring(text or "") * 6 end,
		getFontHeight = function() return 12 end,
	}
end
GlobalStorageSiK = GlobalStorageSiK or { SiK_UI = {}, I18n = {} }
GlobalStorageSiK.SiK_UI = GlobalStorageSiK.SiK_UI or {}
GlobalStorageSiK.SiK_UI.Table = GlobalStorageSiK.SiK_UI.Table or {}
GlobalStorageSiK.I18n = GlobalStorageSiK.I18n or { text = function(key) return key end }
if not GlobalStorageSiK.I18n.text then
	GlobalStorageSiK.I18n.text = function(key) return key end
end

local tablePath = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/GS_SiK_UI_Table.lua"
local tableFile = io.open(tablePath, "rb")
if tableFile then
	tableFile:close()
	local ok, result = pcall(dofile, tablePath)
	if not ok then Support.fail(suite, "GS_SiK_UI_Table", result) end
else
	Support.blocked(suite, "GS_SiK_UI_Table", "module not implemented")
end

local ui = GlobalStorageSiK.SiK_UI
local Controls = ui.Controls
local List = ui.List
local Table = ui.Table
local controlMetrics = Support.requireFunction(suite, Controls, "metrics", "Controls.metrics")
local listRect = Support.requireFunction(suite, List, "resolveContentRect", "List.resolveContentRect")
local rowRect = Support.requireFunction(suite, Table, "rowRect", "Table.rowRect")
local hitRect = Support.requireFunction(suite, Table, "hitRect", "Table.hitRect")

if controlMetrics then
	Support.check(suite, "controls expose one canonical height and gap set per profile", function()
		for _, profile in ipairs({ "compact", "standard", "wide" }) do
			local metrics = controlMetrics(profile)
			assert(type(metrics) == "table", profile .. " metrics")
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

local content = { x = 108, y = 80, w = 720, h = 400, scrollGutter = 24 }
if listRect then
	Support.check(suite, "list consumes the block content rect without adding a gutter", function()
		local rect = listRect(content, { rowCount = 4 })
		assert(rect.x == content.x and rect.w == content.w, "short list shifted content")
		local long = listRect(content, { rowCount = 400 })
		assert(long.x == content.x and long.w == content.w, "long list added a second gutter")
		return true
	end)
end

if type(Table) == "table" and type(Table.resolveColumns) == "function" then
	Support.check(suite, "table columns consume contentW and end at its right edge", function()
		local columns = {
			{ key = "name", flex = 1, minWidth = 80 },
			{ key = "status", width = 96, align = "right" },
		}
		local layout = Table.resolveColumns(content.w, columns, { left = 0, right = 0, gap = 4 })
		assert(layout[1].x == 0, "table added left reservation")
		assert(layout[#layout].finish == content.w, "table added right/double gutter")
		return true
	end)

	Support.check(suite, "table follows the dynamic Block rect without owning its gutter", function()
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
else
	Support.blocked(suite, "Table.resolveColumns", "missing function")
end

if rowRect and hitRect then
	Support.check(suite, "header row and hitbox share the same table rectangle", function()
		local row = rowRect(content, 2)
		local hit = hitRect(content, 2)
		assert(row.x == content.x and row.w == content.w, "row rect mismatch")
		assert(hit.x == row.x and hit.y == row.y and hit.w == row.w and hit.h == row.h,
			"hitbox differs from rendered row")
		return true
	end)
end

Support.finish(suite)
