-- Binding author contract for the Warehouse contextual menu.
-- The terminal already identifies the network; withdrawal chooses quantity,
-- never a redundant persistent destination. No PZ menu is opened.

for _, name in ipairs({ "GS_I18n", "GS_QuantityPrompt", "GS_ContainerTargets",
	"GS_ContextMenuUi", "GS_ContextMenu", "ISUI/ISContextMenu" }) do
	package.loaded[name] = true
end

local destinationCalls = 0
local function newMenu(parent)
	local menu = { parent = parent, options = {}, subMenus = {} }
	function menu:addOption(label, ...)
		local option = { label = label, args = { ... } }
		self.options[#self.options + 1] = option
		return option
	end
	function menu:addSubMenu(option, child) self.subMenus[option] = child end
	return menu
end

ISContextMenu = { getNew = function(_, parent) return newMenu(parent) end }
GlobalStorageSiK = {
	I18n = { text = function(key) return key end },
	QuantityPrompt = { show = function() end },
	ContainerTargets = {
		clearSessionTarget = function() end,
		addDestinationSubMenu = function()
			destinationCalls = destinationCalls + 1
			error("Warehouse withdrawal must not expose a destination selector")
		end,
		resolveWithdrawTarget = function() return "player:main" end,
	},
	ContextMenuUi = {
		prepareTerminal = function() return {} end,
		scheduleTerminalRestore = function() end,
	},
	ContextMenu = { ensureRoot = function() error("internal menu must use received root") end },
}

dofile("GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/GS_WithdrawMenu.lua")

local function exercise(row, selection)
	local context = newMenu(nil)
	GlobalStorageSiK.WithdrawMenu.addToContext(context, {}, row, function() end, selection)
	assert(#context.options == 1, "withdrawal must be one direct root action")
	assert(context.options[1].label == "IGUI_GS_ContextWithdraw", "wrong root action")
	return context.subMenus[context.options[1]]
end

local parent = { rowKey = "Base.Nails", fullType = "Base.Nails", count = 20,
	expandable = true, aggregateAllowed = true }
local child = { rowKey = "Base.Nails\31id:42", fullType = "Base.Nails", count = 1,
	itemId = 42, nodeId = "node", aggregateAllowed = false }
local parentSub = exercise(parent)
assert(parentSub and #parentSub.options >= 1, "parent has no quantity action")
local childSub = exercise(child)
assert(childSub and #childSub.options == 1, "exact child must withdraw exactly once")
local multiSub = exercise(parent, { parent, child })
assert(multiSub and #multiSub.options == 2, "multi-selection actions are not exact")
assert(destinationCalls == 0, "Warehouse contextual retained a destination path")

local sourcePath = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/GS_WithdrawMenu.lua"
local handle = assert(io.open(sourcePath, "rb"))
local source = handle:read("*a")
handle:close()
assert(not source:find("addDestinationSubMenu", 1, true),
	"destination selector remains in the Warehouse withdraw implementation")

print("withdraw_context_contract: OK")
