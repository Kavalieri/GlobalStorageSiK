-- Regression: PZ exposes UIManager children as Java ArrayList in affected
-- builds.  The topmost ISInventoryPane must win; a Lua length check silently
-- skips those children and makes every drag drop look invalid.

for _, name in ipairs({ "GS_DepositSources", "GS_I18n", "GS_UIDebug", "ISUI/ISContextMenu" }) do
	package.loaded[name] = true
end

local function javaList(values)
	return {
		size = function() return #values end,
		get = function(_, index) return values[index + 1] end,
	}
end

local function pane(name, x, y, w, h)
	return {
		name = name, Type = "ISInventoryPane", width = w, height = h,
		getAbsoluteX = function() return x end,
		getAbsoluteY = function() return y end,
		isVisible = function() return true end,
	}
end

local back = pane("back", 0, 0, 100, 100)
local front = pane("front", 10, 10, 80, 80)
UIManager = { getUI = function() return javaList({ back, front }) end }
getMouseX, getMouseY = function() return 20 end, function() return 20 end
GlobalStorageSiK = {
	I18n = { text = function(key) return key end },
	DepositSources = { isNetworkNodeContainer = function() return false end },
	UIDebug = { log = function() end },
}

dofile("GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/GS_ContainerTargets.lua")

assert(GlobalStorageSiK.ContainerTargets.findPaneAtMouse(true) == front,
	"topmost Java-list pane was not selected")

UIManager = nil
local player = { getPlayerNum = function() return 0 end }
getPlayerInventory = function() return { inventoryPane = back, lootPane = front } end
assert(GlobalStorageSiK.ContainerTargets.findPaneAtMouse(true, player) == front,
	"page fallback did not use visible pane geometry")

-- B42 puede separar el maletero/loot de vehiculo de la pagina de inventario.
-- El destino superior sigue siendo valido aunque no cuelgue de getPlayerInventory.
getPlayerInventory = function() return { inventoryPane = back } end
getPlayerLoot = function() return { lootPane = front } end
assert(GlobalStorageSiK.ContainerTargets.findPaneAtMouse(true, player) == front,
	"vehicle loot page was not included in drag hit-test")

assert(GlobalStorageSiK.ContainerTargets.findPaneAtMouse(true, nil, 0) == front,
	"page fallback discarded the captured drag viewport when player object was nil")

print("container_targets_hit_test_regression: OK")
