local ROOT = "addons/GSSiK_Addon_Craft/Contents/mods/GSSiK_Addon_Craft/42/"

local function read(path)
	local handle = assert(io.open(path, "rb"), "missing fixture: " .. path)
	local value = handle:read("*a")
	handle:close()
	return value
end

local ui = read(ROOT .. "media/lua/client/GSSiK_Addon_Craft_TerminalUI.lua")
local context = read(ROOT .. "media/lua/client/GSSiK_Addon_Craft/UI/TabCraftContext.lua")
local generated = read(ROOT .. "media/lua/client/GSSiK_Addon_Craft/UI/Generated/TabCraft.lua")
local spec = read("addons/GSSiK_Addon_Craft/ui/surfaces/tab-craft.surface.json")
local modInfo = read(ROOT .. "mod.info")
local version = read(ROOT .. "media/lua/shared/GSSiK_Addon_Craft_Sandbox.lua")
local registration = read(ROOT .. "media/lua/client/GSSiK_Addon_Craft_Client.lua")
local railAsset = ROOT .. "media/ui/GSSiK_Addon_Craft/sik-rail-craft.png"

local required = {
	'local Surface = require "GSSiK_Addon_Craft/UI/Generated/TabCraft"',
	'local Context = require "GSSiK_Addon_Craft/UI/TabCraftContext"',
	'TerminalModule.surfaceId = "tab-craft"',
	"TerminalModule.surface = Surface",
	"TerminalModule.builder = SiK.UI.SurfaceHost.mount",
	"function TerminalModule.contextFactory(terminal)",
	"return Context.create(terminal)",
}
for i = 1, #required do
	assert(ui:find(required[i], 1, true), "missing canonical UI contract: " .. required[i])
end

local forbidden = {
	"addSectionTitle",
	"addBlockInfoBtn",
	"versionLbl",
	"_gsScrollBarGap",
	"_gsBarRightPad",
	"options.right",
	"GS_SiK_UI",
	"TerminalScroll",
	"ISPanel:new",
	"drawRect(",
	"buildPanel",
	"function TerminalModule.layout",
	"setBounds(",
	"UI.Controls",
	"UI.Scroll",
}
for i = 1, #forbidden do
	assert(not ui:find(forbidden[i], 1, true), "legacy/local UI contract remains: " .. forbidden[i])
end

assert(context:find("actions = actions", 1, true), "context omits declarative actions")
assert(context:find("conditions =", 1, true), "context omits declarative conditions")
assert(context:find("i18n =", 1, true), "context omits runtime i18n")
assert(context:find("owner.openCraft(terminal", 1, true), "Craft action must invoke its implemented owner")
assert(context:find('and "neat" or "vanilla"', 1, true), "Craft action must preserve Neat/vanilla routing")
assert(context:find("owner.openCook(terminal)", 1, true), "Cook action must invoke its implemented owner")
assert(not context:find("terminal.onOpenVanillaCraft", 1, true), "dead terminal Craft callback returned")
assert(not context:find("terminal.onOpenCook", 1, true), "dead terminal Cook callback returned")
assert(generated:find("Generated data only. Do not edit.", 1, true))
assert(generated:find('"tab-craft"', 1, true))
assert(spec:find('"documentKind": "product-surface-spec"', 1, true))
assert(spec:find('"validation": "HTML_VALIDATED_BY_KAVA"', 1, true))
assert(registration:find('iconPath = "media/ui/GSSiK_Addon_Craft/sik-rail-craft.png"', 1, true),
	"Craft must supply its own rail asset through the neutral terminal-tab contract")
local assetHandle = assert(io.open(railAsset, "rb"), "Craft rail asset is not packaged by its addon")
assetHandle:close()
assert(io.open("GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/ui/GS/sik-rail-craft.png", "rb") == nil,
	"Core must not package the Craft rail asset")

local modVersion = assert(modInfo:match("\nmodversion=([^\r\n]+)"), "modversion missing")
local luaVersion = assert(version:match('GSSiK_Addon_Craft.VERSION%s*=%s*"([^"]+)"'),
	"Lua version mirror missing")
assert(modVersion == luaVersion, "version mismatch: " .. modVersion .. " vs " .. luaVersion)
assert(modVersion == "1.0.10-dev1.8", "unexpected Craft candidate version: " .. modVersion)

print("PASS terminal_ui_framework_contract")
