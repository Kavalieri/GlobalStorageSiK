-- The node editor is required during Lua reset before GS_Client necessarily
-- creates GlobalStorageSiK.Client. Loading the inventory adapter must be safe,
-- and cleanup registration must be deferred and idempotent.

local root = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/"

GlobalStorageSiK = {
	I18n = { text = function(key) return key end },
}

package.preload["GS_TerminalUI_Items"] = function() return true end
package.preload["GS_WithdrawClient"] = function() return true end
package.preload["GS_UI_Framework"] = function() return {} end
package.preload["GlobalStorageSiK/UI/CapacityPresentation"] = function() return {} end

local chunk = assert(loadfile(root .. "GS_ContainerInventory.lua"))
local Inventory = chunk()
assert(type(Inventory) == "table", "inventory adapter did not load before GS_Client")
assert(Inventory.installCleanup() == false, "cleanup cannot register before GS_Client exists")

local registrations = 0
GlobalStorageSiK.Client = {
	registerTransientCleanup = function(key, handler)
		assert(key == "containerInventory", "unexpected cleanup key")
		assert(type(handler) == "function", "cleanup handler must be callable")
		registrations = registrations + 1
		return true
	end,
}

assert(Inventory.installCleanup() == true, "cleanup did not register after GS_Client became available")
assert(Inventory.installCleanup() == true, "registered cleanup did not remain installed")
assert(registrations == 1, "cleanup registration is not idempotent")

print("PASS: container inventory tolerates load order and registers cleanup once")
