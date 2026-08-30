-- Core 1.4.3-dev32.4.3: internal withdraw menu owns the received root.
for _, name in ipairs({ "GS_I18n", "GS_QuantityPrompt", "GS_ContainerTargets",
	"GS_ContextMenuUi", "GS_ContextMenu", "ISUI/ISContextMenu" }) do
	package.loaded[name] = true
end

local ensureRootCalls, destinationCalls = 0, 0
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
		clearSessionTarget = function()
			destinationCalls = destinationCalls + 1
			error("withdraw contextual must not mutate target state")
		end,
		addDestinationSubMenu = function()
			destinationCalls = destinationCalls + 1
			error("withdraw contextual must not create a destination submenu")
		end,
		resolveWithdrawTarget = function()
			destinationCalls = destinationCalls + 1
			error("withdraw contextual must not resolve persisted target state")
		end,
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
	local withdrawals = {}
	GlobalStorageSiK.WithdrawMenu.addToContext(context, {}, row, function(data, amount, targetKey)
		withdrawals[#withdrawals + 1] = { data = data, amount = amount, targetKey = targetKey }
	end, selection)
	assert(rootCount(context) == 1, "received context must contain exactly one withdraw root")
	assert(#context.options == 1, "withdraw root must not be wrapped in Global Storage")
	local sub = context.subMenus[context.options[1]]
	assert(sub and sub.parent == context, "withdraw submenu must belong to received context")
	return sub, withdrawals
end

local parent = { rowKey = "Base.Nails", fullType = "Base.Nails", count = 20, expandable = true }
local child = { rowKey = "Base.Nails\31id:42", fullType = "Base.Nails", count = 1,
	itemId = 42, nodeId = "node" }
local parentSub, parentWithdrawals = exercise(parent)
assert(#parentSub.options == 3,
	"parent row must expose exactly one, all and quantity actions without destination")
assert(parentSub.options[1].label == "IGUI_GS_WithdrawOne"
	and parentSub.options[2].label == "IGUI_GS_WithdrawType"
	and parentSub.options[3].label == "IGUI_GS_WithdrawAmount",
	"parent withdraw actions changed order or gained a destination option")
parentSub.options[1].args[2](parentSub.options[1].args[1])
assert(#parentWithdrawals == 1 and parentWithdrawals[1].amount == 1
	and parentWithdrawals[1].targetKey == nil,
	"single withdraw did not use the implicit player inventory target")

local childSub, childWithdrawals = exercise(child)
assert(#childSub.options == 1 and childSub.options[1].label == "IGUI_GS_WithdrawOne",
	"exact child must expose only its exact withdraw action")
childSub.options[1].args[2](childSub.options[1].args[1])
assert(#childWithdrawals == 1 and childWithdrawals[1].data == child
	and childWithdrawals[1].targetKey == nil,
	"exact child withdraw gained destination state")
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
assert(destinationCalls == 0, "withdraw contextual touched destination submenu/target state")

print("dev32_4_3_withdraw_menu_root_contract: OK")
