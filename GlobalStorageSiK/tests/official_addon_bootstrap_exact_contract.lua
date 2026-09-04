-- Integration contract: the real official bootstrap registers exactly the
-- released Craft, Builder and Tablet addons, once each and in load order.
-- Run from GlobalStorageSiK-Repo with Lua 5.1.

package.loaded["GSSiK_API"] = true

local expected = {
	{ name = "Craft", id = "Craft",
		path = "addons/GSSiK_Addon_Craft/Contents/mods/GSSiK_Addon_Craft/42/media/lua/shared/GSSiK_Addon_Craft_Register.lua" },
	{ name = "Builder", id = "Builder",
		path = "addons/GSSiK_Addon_Builder/Contents/mods/GSSiK_Addon_Builder/42/media/lua/shared/GSSiK_Addon_Builder_Register.lua" },
	{ name = "Tablet", id = "TabletLink",
		path = "addons/GSSiK_Addon_Tablet/Contents/mods/GSSiK_Addon_Tablet/42/media/lua/shared/GSSiK_Addon_Tablet_Register.lua" },
}

local registered = {}
GSSiK = { API = { Addon = {} } }
function GSSiK.API.Addon.register(definition)
	assert(type(definition) == "table" and type(definition.id) == "string")
	registered[#registered + 1] = definition.id
	return true, "OK", { id = definition.id, dispose = function() return true end }
end

SandboxVars = {
	GlobalStorageSiK = { RequireRecipeBooks = true },
	GSSiK_Addon_Craft = {}, GSSiK_Addon_Builder = {}, GSSiK_Addon_Tablet = {},
}
Events = { OnGameStart = { Add = function() end } }

for index = 1, #expected do dofile(expected[index].path) end

assert(#registered == #expected,
	"official bootstrap count changed: " .. tostring(#registered))
local seen = {}
for index = 1, #expected do
	local actual, wanted = registered[index], expected[index].id
	assert(actual == wanted, "bootstrap order " .. tostring(index)
		.. " expected " .. wanted .. " got " .. tostring(actual))
	assert(not seen[actual], "duplicate official addon " .. tostring(actual))
	seen[actual] = true
end
assert(seen.Craft and seen.Builder and seen.TabletLink and not seen.Rack,
	"official bootstrap set must be exactly Craft/Builder/Tablet")

print("official_addon_bootstrap_exact_contract: OK Craft,Builder,Tablet")
