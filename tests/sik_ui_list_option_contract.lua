-- Author contract for the neutral SiK UI ListOption component.

local Support = dofile("tests/helpers/sik_ui_contract_support.lua")
local suite = Support.newSuite("sik_ui_list_option_contract")

UIFont = { Small = "Small" }
function getTextManager()
	return {
		getFontHeight = function() return 12 end,
		MeasureStringX = function(_, _, text) return #tostring(text or "") * 6 end,
	}
end

ISPanel = {}
function ISPanel:derive(name)
	local class = { Type = name }
	class.__index = class
	setmetatable(class, { __index = self })
	return class
end
function ISPanel:new(x, y, width, height)
	local panel = { x = x, y = y, width = width, height = height, children = {} }
	setmetatable(panel, { __index = self })
	return panel
end
function ISPanel:initialise() self.initialised = true end
function ISPanel:addChild(child) self.children[#self.children + 1] = child end
function ISPanel:setWidth(width) self.width = width end
function ISPanel:setHeight(height) self.height = height end
function ISPanel:setCapture(captured) self.captured = captured == true end
function ISPanel:prerender() end
function ISPanel:drawRect() end
function ISPanel:drawRectBorder() end
function ISPanel:drawText() end

GlobalStorageSiK = {
	SiK_UI = {
		PALETTE = {
			btnDefault = { 0.2, 0.2, 0.2 }, btnHover = { 0.3, 0.3, 0.3 },
			btnPressed = { 0.1, 0.1, 0.1 }, btnActive = { 0.95, 0.5, 0.1 },
			border = { 0.4, 0.4, 0.4 }, textPrimary = { 0.92, 0.94, 0.96 },
			textMuted = { 0.58, 0.62, 0.66 },
		},
		Controls = {
			metrics = function()
				return { buttonHeight = 30, inputHeight = 30 }
			end,
		},
	},
}

function GlobalStorageSiK.SiK_UI.wrapTextLines(text, width)
	local maxChars = math.max(1, math.floor(width / 6))
	local source = tostring(text or "")
	local lines = {}
	while #source > maxChars do
		lines[#lines + 1] = source:sub(1, maxChars)
		source = source:sub(maxChars + 1)
	end
	lines[#lines + 1] = source
	return lines
end

package.loaded["GS_SiK_UI_Core"] = true
package.loaded["GS_SiK_UI_Controls"] = true

local listPath = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/GS_SiK_UI_List.lua"
local ok, result = pcall(dofile, listPath)
if not ok then Support.fail(suite, "GS_SiK_UI_List", result) end

local List = GlobalStorageSiK.SiK_UI.List

Support.check(suite, "ListOption exposes canonical padding gap and dynamic height", function()
	local metrics = List.optionMetrics("compact")
	assert(metrics.padding == 8, "padding must be 8")
	assert(metrics.gap == 8, "gap must be 8")
	assert(metrics.minHeight == 30, "minimum must use control height")
	local short = List.measureOption("short", 160, { profile = "compact" })
	local long = List.measureOption(string.rep("x", 80), 100, { profile = "compact" })
	assert(short.height >= 30, "short option must respect canonical minimum")
	assert(long.height > short.height and #long.lines > 1,
		"long option must wrap and grow")
	assert(short.textX == 8 and short.textWidth == 144,
		"text must consume symmetric 8px padding")
	local leading = List.measureOption("with leading", 160,
		{ profile = "compact", leadingWidth = 16 })
	assert(leading.textX == 32, "leading content must reserve padding + width + 8px gap")
	return true
end)

Support.check(suite, "ListOption state API updates data selection availability and loading", function()
	local option
	option = List.createOption(nil, {
		w = 120, data = { text = "Initial", selected = true },
	})
	assert(option:getData().text == "Initial", "initial data missing")
	assert(option:isSelected(), "selected state missing")
	assert(option:isEnabled(), "option should start enabled")
	option:setData({ text = string.rep("z", 60), enabled = false })
	assert(not option:isEnabled(), "setData enabled state ignored")
	assert(option.height > 30, "setData did not remeasure wrapped height")
	option:setEnabled(true):setSelected(false):setLoading(true)
	assert(not option:isEnabled() and option:isLoading(), "loading must block activation")
	option:setLoading(false)
	assert(option:isEnabled() and not option:isSelected(), "state recovery failed")
	return true
end)

Support.check(suite, "ListOption full hitbox activates once and disabled states never callback", function()
	local calls = 0
	local payload
	local target = {}
	local option
	option = List.createOption(nil, {
		w = 140, data = { text = "Clickable option", id = "opaque" },
		target = target,
		callback = function(receivedTarget, receivedOption, receivedData)
			assert(receivedTarget == target, "callback target mismatch")
			assert(receivedOption == option, "callback option mismatch")
			calls = calls + 1
			payload = receivedData
		end,
	})
	assert(option:hitTest(0, 0), "top-left must be clickable")
	assert(option:hitTest(option.width - 1, option.height - 1),
		"bottom-right must be clickable")
	assert(not option:hitTest(option.width, option.height - 1), "outside width accepted")
	assert(option:onMouseDown(0, 0), "mouse down was not consumed")
	assert(option:onMouseUp(option.width - 1, option.height - 1),
		"full-row mouse up did not activate")
	assert(calls == 1 and payload.id == "opaque", "callback payload mismatch")
	assert(option:isSelected(), "activation should select by default")
	option:setEnabled(false)
	assert(not option:onMouseDown(4, 4), "disabled option consumed mouse down")
	option:onMouseUp(4, 4)
	option:setEnabled(true):setLoading(true)
	assert(not option:activate(), "loading option activated")
	assert(calls == 1, "blocked state invoked callback")
	return true
end)

Support.finish(suite)
