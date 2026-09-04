-- Real-entrypoint bootstrap contract for the three released official addons.
-- Exercises shared files as a dedicated process and client entry files as a
-- client process, then queries the real public GSSiK.API.Addon.list surface.
-- Run from GlobalStorageSiK-Repo with Lua 5.1.

local CORE_SHARED = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/"
local addons = {
	{ id = "Craft", name = "GSSiK_Addon_Craft",
		register = "addons/GSSiK_Addon_Craft/Contents/mods/GSSiK_Addon_Craft/42/media/lua/shared/GSSiK_Addon_Craft_Register.lua",
		server = "addons/GSSiK_Addon_Craft/Contents/mods/GSSiK_Addon_Craft/42/media/lua/server/GSSiK_Addon_Craft_Server.lua",
		client = "addons/GSSiK_Addon_Craft/Contents/mods/GSSiK_Addon_Craft/42/media/lua/client/GSSiK_Addon_Craft_Client.lua" },
	{ id = "Builder", name = "GSSiK_Addon_Builder",
		register = "addons/GSSiK_Addon_Builder/Contents/mods/GSSiK_Addon_Builder/42/media/lua/shared/GSSiK_Addon_Builder_Register.lua",
		server = "addons/GSSiK_Addon_Builder/Contents/mods/GSSiK_Addon_Builder/42/media/lua/server/GSSiK_Addon_Builder_Server.lua",
		client = "addons/GSSiK_Addon_Builder/Contents/mods/GSSiK_Addon_Builder/42/media/lua/client/GSSiK_Addon_Builder_Client.lua" },
	{ id = "TabletLink", name = "GSSiK_Addon_Tablet",
		register = "addons/GSSiK_Addon_Tablet/Contents/mods/GSSiK_Addon_Tablet/42/media/lua/shared/GSSiK_Addon_Tablet_Register.lua",
		server = "addons/GSSiK_Addon_Tablet/Contents/mods/GSSiK_Addon_Tablet/42/media/lua/server/GSSiK_Addon_Tablet_Server.lua",
		client = "addons/GSSiK_Addon_Tablet/Contents/mods/GSSiK_Addon_Tablet/42/media/lua/client/GSSiK_Addon_Tablet_Client.lua" },
}

local loggerNamespaces = {
	GSSiK_Addon_Craft_Log = "GSSiK_Addon_Craft",
	GSSiK_Addon_Builder_Log = "GSSiK_Addon_Builder",
	GSSiK_Addon_Tablet_Log = "GSSiK_Addon_Tablet",
}

local function loadLoggerFixture(moduleName)
	local namespace = loggerNamespaces[moduleName]
	if not namespace then return nil end
	_G[namespace] = _G[namespace] or {}
	_G[namespace].Log = { debug = function() end }
	return _G[namespace].Log
end

local function freshEvents()
	local handlers = {}
	return { OnGameStart = { Add = function(handler) handlers[#handlers + 1] = handler end } }, handlers
end

local function bootstrapCore()
	for _, moduleName in ipairs({
		"GS_Config", "GS_CraftUtils", "GS_Sandbox", "GS_InventorySync",
		"GS_TerminalAccess", "GS_AddonRegistry", "GS_DiskProgramming", "GSSiK_API",
	}) do package.loaded[moduleName] = true end
	GlobalStorageSiK = { CraftUtils = {}, Sandbox = {}, TerminalAccess = {} }
	GSSiK = nil
	GSSiK_Addon_Craft, GSSiK_Addon_Builder, GSSiK_Addon_Tablet = nil, nil, nil
	SandboxVars = {
		GlobalStorageSiK = { RequireRecipeBooks = true },
		GSSiK_Addon_Craft = {}, GSSiK_Addon_Builder = {}, GSSiK_Addon_Tablet = {},
	}
	Events = freshEvents()
	dofile(CORE_SHARED .. "GS_AddonRegistry.lua")
	dofile(CORE_SHARED .. "GS_DiskProgramming.lua")
	dofile(CORE_SHARED .. "GSSiK_API.lua")
	return GSSiK.API
end

local function assertPublicSet(label, api)
	local ok, code, listed = api.Addon.list()
	assert(ok == true and code == "OK", label .. " Addon.list failed: " .. tostring(code))
	assert(#listed == 3, label .. " expected exactly three addons, got " .. tostring(#listed))
	local seen = {}
	for index = 1, #listed do
		local id = listed[index] and listed[index].id
		assert(type(id) == "string" and id ~= "", label .. " returned invalid addon descriptor")
		assert(not seen[id], label .. " returned duplicate addon " .. id)
		seen[id] = true
	end
	for index = 1, #addons do
		assert(seen[addons[index].id], label .. " omitted " .. addons[index].id)
	end
	assert(not seen.Rack, label .. " exposed preproduction Rack")
end

local registerByModule = {
	GSSiK_Addon_Craft_Register = addons[1].register,
	GSSiK_Addon_Builder_Register = addons[2].register,
	GSSiK_Addon_Tablet_Register = addons[3].register,
}

-- Dedicated/server-side VM: execute the actual server entrypoints, whose only
-- product responsibility is loading their real shared Register modules.
local dedicatedApi = bootstrapCore()
local originalRequire = require
local dedicatedLoaded = {}
function require(name)
	if name == "GSSiK_API" then return dedicatedApi end
	local logger = loadLoggerFixture(name)
	if logger then return logger end
	local registerPath = registerByModule[name]
	if registerPath then
		if not dedicatedLoaded[name] then
			dedicatedLoaded[name] = true
			dofile(registerPath)
		end
		return true
	end
	return originalRequire(name)
end
for index = 1, #addons do dofile(addons[index].server) end
require = originalRequire
assertPublicSet("dedicated", dedicatedApi)

-- Client VM: execute each real client entrypoint.  Only the engine-facing
-- leaves are replaced; the Register module and public Addon API stay real.
local clientApi = bootstrapCore()
local registrations = { addon = {}, tabs = {}, providers = {}, tablets = {} }
local realAddonRegister = clientApi.Addon.register
clientApi.Addon.register = function(definition)
	registrations.addon[#registrations.addon + 1] = definition.id
	return realAddonRegister(definition)
end
local function handle(id) return { id = id, dispose = function() return true end } end
clientApi.Terminal = {
	registerTab = function(definition)
		registrations.tabs[#registrations.tabs + 1] = definition.key
		return true, "OK", handle(definition.key)
	end,
	registerStaffAction = function(id) return true, "OK", handle(id) end,
	current = function() return nil end,
	player = function() return nil end,
	state = function() return {} end,
	isAddonInstalled = function() return false end,
	isTabEnabled = function() return false end,
	setTabVisible = function() return true end,
}
clientApi.WorkSession = setmetatable({}, { __index = function() return function() return false, "fixture" end end })
clientApi.ItemActions = {
	registerProvider = function(definition)
		registrations.providers[#registrations.providers + 1] = definition.id
		return true, "OK", handle(definition.id)
	end,
	registerTablet = function(definition)
		registrations.tablets[#registrations.tablets + 1] = definition.fullType
		return true, "OK", handle(definition.fullType)
	end,
}

local loadedRegisters = {}
function require(name)
	if name == "GSSiK_API" or name == "GSSiK_API_Client" then return clientApi end
	local logger = loadLoggerFixture(name)
	if logger then return logger end
	local registerPath = registerByModule[name]
	if registerPath then
		if not loadedRegisters[name] then
			loadedRegisters[name] = true
			dofile(registerPath)
		end
		return true
	end
	if name == "GSSiK_Addon_Craft_TerminalUI" then
		return { surface = { id = "tab-craft" }, contextFactory = function() return {} end,
			refresh = function() return true end }
	end
	if name == "GSSiK_Addon_Builder_TerminalUI" then
		return { surface = { id = "tab-builder" }, contextFactory = function() return {} end,
			refresh = function() return true end }
	end
	if name == "GSSiK_Addon_Craft_NetworkCook" then
		GSSiK_Addon_Craft_NetworkCook = { openCookUI = function() return false end }
		return GSSiK_Addon_Craft_NetworkCook
	end
	if name == "GSSiK_Addon_Craft_Log" then
		GSSiK_Addon_Craft = GSSiK_Addon_Craft or {}
		GSSiK_Addon_Craft.Log = { debug = function() end }
		return GSSiK_Addon_Craft.Log
	end
	if name == "GSSiK_Addon_Builder_Log" then
		GSSiK_Addon_Builder = GSSiK_Addon_Builder or {}
		GSSiK_Addon_Builder.Log = { debug = function() end }
		return GSSiK_Addon_Builder.Log
	end
	if name == "GSSiK_Addon_Tablet_NetworkSelector" then
		GSSiK_Addon_Tablet = GSSiK_Addon_Tablet or {}
		GSSiK_Addon_Tablet.NetworkSelector = { onUseTablet = function() return true end }
		return GSSiK_Addon_Tablet.NetworkSelector
	end
	if name == "GSSiK_Addon_Tablet_Access" then
		GSSiK_Addon_Tablet = GSSiK_Addon_Tablet or {}
		GSSiK_Addon_Tablet.ITEM_TABLET = "GSSiK_Addon_Tablet.GS_Tablet"
		GSSiK_Addon_Tablet.ITEM_TABLET_CRAFT = "GSSiK_Addon_Tablet.GS_TabletCraft"
		GSSiK_Addon_Tablet.ITEM_TABLET_BUILDER = "GSSiK_Addon_Tablet.GS_TabletBuilder"
		GSSiK_Addon_Tablet.ITEM_TABLET_MASTER = "GSSiK_Addon_Tablet.GS_TabletMaster"
		return GSSiK_Addon_Tablet
	end
	-- Remaining modules are side-effect leaves irrelevant to registration.
	return true
end

for index = 1, #addons do dofile(addons[index].client) end
require = originalRequire

assertPublicSet("client", clientApi)
assert(#registrations.addon == 3, "client entrypoints did not execute three real Register modules")
for index = 1, #addons do
	assert(registrations.addon[index] == addons[index].id,
		"client register order mismatch at " .. tostring(index))
end
assert(registrations.tabs[1] == "craft" and registrations.tabs[2] == "build"
	and #registrations.tabs == 2, "Craft/Builder client tabs did not bootstrap exactly once")
assert(registrations.providers[1] == "craft.item-actions"
	and registrations.providers[2] == "builder.item-actions"
	and #registrations.providers == 2, "official item-action providers did not bootstrap")
assert(#registrations.tablets == 4, "Tablet client did not register its four real item variants")

print("official_addon_process_bootstrap_contract: OK dedicated=3 client=3")
