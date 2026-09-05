-- Authorial contract for the terminal configuration/nodes consumer.  Loads
-- the real module with neutral framework doubles and exercises selection,
-- control composition and scroll-state preservation.

local SOURCE_PATH = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/GS_TerminalUI_Config.lua"

local function read(path)
	local file = assert(io.open(path, "rb"))
	local value = assert(file:read("*a"))
	file:close()
	return value
end

local function executableSource(value)
	value = value:gsub("%-%-%[%[.-%]%]", "")
	local lines = {}
	for line in (value .. "\n"):gmatch("(.-)\n") do
		lines[#lines + 1] = line:gsub("%-%-.*$", "")
	end
	return table.concat(lines, "\n")
end

local code = executableSource(read(SOURCE_PATH))
assert(code:find('local UI = require "GS_UI_Framework"', 1, true),
	"TerminalConfig must load the public SiK.UI facade")

local requiredControls = {
	"UI.Controls.field", "UI.Controls.combo", "UI.Controls.copyText",
	"UI.Controls.separator", "UI.Controls.button",
}
for i = 1, #requiredControls do
	assert(code:find(requiredControls[i], 1, true),
		"TerminalConfig lost shared control " .. requiredControls[i])
end

local forbiddenPrimitives = {
	'require "ISUI/ISLabel"', 'require "ISUI/ISComboBox"',
	'require "ISUI/ISTextEntryBox"', 'require "ISUI/ISButton"',
}
for i = 1, #forbiddenPrimitives do
	assert(not code:find(forbiddenPrimitives[i], 1, true),
		"TerminalConfig must not load primitive " .. forbiddenPrimitives[i])
end
assert(not code:match("ISLabel%s*[:.]"), "TerminalConfig must not create or mutate ISLabel")
assert(not code:match("ISComboBox%s*[:.]"), "TerminalConfig must not create or mutate ISComboBox")
assert(not code:match("ISTextEntryBox%s*[:.]"), "TerminalConfig must not create or mutate ISTextEntryBox")
assert(not code:match("ISButton%s*[:.]"), "TerminalConfig must not create or mutate ISButton")
assert(not code:match(":drawText"), "TerminalConfig must not paint text locally")
assert(not code:match(":drawRect"), "TerminalConfig must not paint chrome locally")
assert(not code:match("function%s+.-:prerender"), "TerminalConfig must not own prerender chrome")
assert(not code:match("function%s+.-:render%s*%(%s*%)"), "TerminalConfig must not own render chrome")

local created = { field = {}, combo = {}, copyText = {}, separator = {}, button = {} }
local function widget(kind, options)
	local value = {
		kind = kind,
		options = options,
		x = options.x or 0,
		y = options.y or 0,
		width = options.w or 0,
		height = options.h or 0,
	}
	function value:setWidth(width) self.width = width end
	function value:setX(x) self.x = x end
	function value:getText() return self.text or "" end
	if kind == "field" then value.text = options.text or "" end
	if kind == "button" then
		function value:activate() return options.onClick and options.onClick() end
	end
	if kind == "combo" then
		value.items = {}
		value.selected = 1
		function value:setItems(items, selected)
			self.items = items or {}
			self.selected = selected or 1
		end
		function value:getSelectedItem() return self.items[self.selected] end
		function value:getSelectedText()
			local item = self:getSelectedItem()
			return item and item.text or ""
		end
		function value:clear() self.items = {}; self.selected = 1 end
		function value:addOption(text) self.items[#self.items + 1] = { text = text, value = text } end
	end
	created[kind][#created[kind] + 1] = value
	return value
end

local scrollStats = { clearPreserve = nil, contentHeight = nil, restoredOffset = nil }
local confirmationCalls = {}
local Confirmation = {
	show = function(options)
		confirmationCalls[#confirmationCalls + 1] = options
		return options
	end,
}
local UI = {
	Controls = {
		metrics = function() return { inputHeight = 28, buttonHeight = 28 } end,
		field = function(_, options) return widget("field", options) end,
		combo = function(_, options) return widget("combo", options) end,
		copyText = function(_, options) return widget("copyText", options) end,
		separator = function(_, options) return widget("separator", options) end,
		button = function(_, options) return widget("button", options) end,
	},
	Scroll = {
		contentWidth = function(scroll) return scroll.contentWidth end,
		getScrollOffset = function(scroll) return scroll.offset or 0 end,
		clear = function(scroll, preserve)
			scrollStats.clearPreserve = preserve
			scroll.children = {}
		end,
		addChild = function(scroll, child)
			scroll.children = scroll.children or {}
			scroll.children[#scroll.children + 1] = child
		end,
		setContentHeight = function(_, height) scrollStats.contentHeight = height end,
		setScrollOffset = function(scroll, offset)
			scroll.offset = offset
			scrollStats.restoredOffset = offset
		end,
	},
}

UIFont = { Small = 1 }
function getTextManager()
	return { getFontHeight = function() return 14 end }
end

GlobalStorageSiK = {
	I18n = {
		text = function(key) return key end,
		itemDisplayName = function(fullType, displayName) return displayName or fullType end,
		itemCategoryDisplay = function() return "Category" end,
	},
	NativeProduct = {
		decodePath = function(key)
			if type(key) == "string" and key:sub(1, 7) == "native:" then return key end
			return nil
		end,
		getView = function(path) return { fullLabel = "Label " .. path } end,
		listOptions = function() return {} end,
	},
	CategoryResolution = {},
	Client = {},
}

package.preload["GS_I18n"] = function() return GlobalStorageSiK.I18n end
package.preload["GS_NativeProduct"] = function() return GlobalStorageSiK.NativeProduct end
package.preload["GS_CategoryResolution"] = function() return GlobalStorageSiK.CategoryResolution end
package.preload["GS_UI_Framework"] = function() return UI end
package.preload["GS_Confirmation"] = function() return Confirmation end

assert(dofile(SOURCE_PATH) == nil, "TerminalConfig did not load with neutral SiK.UI doubles")
local Config = GlobalStorageSiK.TerminalConfig

local existing = widget("combo", { x = 0, y = 0, w = 200, h = 28 })
Config.fillCategoryCombo(existing, { "native:food", "native:tools" }, "NATIVE:TOOLS")
assert(#existing.items == 3 and existing.selected == 3,
	"setItems must preserve a case-insensitive existing category selection")
assert(existing.items[3].value == "native:tools" and Config.getSelectedCategory(existing) == "native:tools",
	"selected combo item must expose its semantic category value")

local unknown = widget("combo", { x = 0, y = 0, w = 200, h = 28 })
Config.fillCategoryCombo(unknown, { "native:food" }, "native:future")
assert(#unknown.items == 3 and unknown.selected == 3
	and unknown.items[3].value == "native:future",
	"a persisted category absent from the current catalog must remain selected and visible")

local baseline = {}
for kind, values in pairs(created) do baseline[kind] = #values end

local scroll = { contentWidth = 420, offset = 37, children = {}, expandedNodes = {} }
local updates = {}
local terminal = {
	playerNum = 3,
	onUpdateNode = function(_, ...)
		updates[#updates + 1] = { ... }
	end,
	onRequestNodeContents = function() error("collapsed fixture must not request contents") end,
}
local node = {
	id = "node-1", name = "Crate", displayName = "Pantry crate",
	x = 10, y = 20, zoneName = "Kitchen", itemTypeCount = 4,
	categories = { "native:food" }, enabled = true, membership = "active",
}
Config.refreshNodesPanel(scroll, terminal, { node }, { "native:food", "native:tools" })

assert(scrollStats.clearPreserve == true, "refresh must clear children through Scroll while preserving state")
assert(scrollStats.restoredOffset == 37 and scroll.offset == 37,
	"refresh must restore the exact pre-refresh Scroll offset")
assert(type(scrollStats.contentHeight) == "number" and scrollStats.contentHeight > 0,
	"refresh must publish content height back to Scroll")
assert(#scroll.nodeRows == 1 and scroll.nodeRows[1].nameEntry and scroll.nodeRows[1].catCombo,
	"node row must retain semantic field/combo handles")

local expectedCreated = { field = 1, combo = 1, copyText = 3, separator = 1, button = 4 }
for kind, minimum in pairs(expectedCreated) do
	assert(#created[kind] - baseline[kind] >= minimum,
		"runtime node composition did not use SiK.UI.Controls." .. kind)
end
for i = 1, #scroll.children do
	assert(scroll.children[i].kind, "all node widgets must be adopted through SiK.UI.Scroll")
end

local row = scroll.nodeRows[1]
assert(row.nameEntry.text == "Pantry crate", "field must preserve the node display name")
assert(Config.getSelectedCategory(row.catCombo) == "native:food",
	"combo must preserve the node's selected semantic category")
row.saveBtn:activate()
assert(#updates == 1 and updates[1][1] == "node-1"
	and updates[1][2] == "Pantry crate" and updates[1][3] == "native:food",
	"save button must dispatch the field text and selected category without UI-object leakage")
assert(row.membershipBtn.options.active == false,
	"membership button must receive semantic active state through Controls")
assert(row.deleteBtn == nil, "node composition must not inherit unrelated zone actions")

print("terminal_config_controls_contract: OK")
