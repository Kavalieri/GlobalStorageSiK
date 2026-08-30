-- Core 1.4.3-dev32.4.3: internal withdraw menu owns the received root.
for _, name in ipairs({ "GS_I18n", "GS_QuantityPrompt", "GS_ContainerTargets",
	"GS_ContextMenuUi", "GS_ContextMenu", "ISUI/ISContextMenu" }) do
	package.loaded[name] = true
end

local ensureRootCalls = 0
local function newMenu(parent)
	local menu = { parent = parent, options = {}, subMenus = {} }
	function menu:addOption(label, ...)
		local option = { label = label, args = { ... } }
		self.options[#self.options + 1] = option
		return option
	end
	function menu:addSubMenu(option, child)
		self.subMenus[option] = child
	end
	return menu
end

ISContextMenu = {
	getNew = function(_, parent) return newMenu(parent) end,
}
GlobalStorageSiK = {
	I18n = { text = function(key) return key end },
	QuantityPrompt = { show = function() end },
	ContainerTargets = {
		clearSessionTarget = function() end,
		addDestinationSubMenu = function(menu)
			menu:addOption("destination")
		end,
		resolveWithdrawTarget = function() return "player:main" end,
	},
	ContextMenuUi = {
		prepareTerminal = function() return {} end,
		scheduleTerminalRestore = function() end,
	},
	ContextMenu = {
		ensureRoot = function()
			ensureRootCalls = ensureRootCalls + 1
			error("WithdrawMenu must use the received context directly")
		end,
	},
}

dofile("GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/GS_WithdrawMenu.lua")

local function rootCount(menu)
	local count = 0
	for i = 1, #menu.options do
		if menu.options[i].label == "IGUI_GS_ContextWithdraw" then count = count + 1 end
	end
	return count
end

local function exercise(row, selection)
	local context = newMenu(nil)
	GlobalStorageSiK.WithdrawMenu.addToContext(context, {}, row, function() end, selection)
	assert(rootCount(context) == 1, "received context must contain exactly one withdraw root")
	assert(#context.options == 1, "withdraw root must not be wrapped in Global Storage")
	local sub = context.subMenus[context.options[1]]
	assert(sub and sub.parent == context, "withdraw submenu must belong to received context")
	return sub
end

local parent = { rowKey = "Base.Nails", fullType = "Base.Nails", count = 20, expandable = true }
local child = { rowKey = "Base.Nails\31id:42", fullType = "Base.Nails", count = 1,
	itemId = 42, nodeId = "node" }
local parentSub = exercise(parent)
assert(#parentSub.options >= 2, "parent row must expose destination and quantity actions")
local childSub = exercise(child)
assert(#childSub.options == 2, "exact child must expose one destination and one withdraw action")
local multiSub = exercise(parent, { parent, child })
local selectionOptions = 0
for i = 1, #multiSub.options do
	if multiSub.options[i].label == "IGUI_GS_WithdrawSelectionOne"
		or multiSub.options[i].label == "IGUI_GS_WithdrawSelectionAll" then
		selectionOptions = selectionOptions + 1
	end
end
assert(selectionOptions == 2, "multi-selection must expose each batch action exactly once")
assert(ensureRootCalls == 0, "ContextMenu.ensureRoot must never be used internally")

print("dev32_4_3_withdraw_menu_root_contract: OK")
