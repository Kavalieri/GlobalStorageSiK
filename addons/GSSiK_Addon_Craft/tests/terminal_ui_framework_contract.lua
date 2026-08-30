local ROOT = "addons/GSSiK_Addon_Craft/Contents/mods/GSSiK_Addon_Craft/42/"

local function read(path)
	local handle = assert(io.open(path, "rb"), "missing fixture: " .. path)
	local value = handle:read("*a")
	handle:close()
	return value
end

local ui = read(ROOT .. "media/lua/client/GSSiK_Addon_Craft_TerminalUI.lua")
local modInfo = read(ROOT .. "mod.info")
local version = read(ROOT .. "media/lua/shared/GSSiK_Addon_Craft_Sandbox.lua")

local required = {
	'require "GS_SiK_UI_Controls"',
	"CONTROLS.blockHeader",
	"CONTROLS.feedback",
	"CONTROLS.button",
	"TerminalScroll.setOnContentRectChanged",
	"TerminalScroll.contentRect",
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
}
for i = 1, #forbidden do
	assert(not ui:find(forbidden[i], 1, true), "legacy/local UI contract remains: " .. forbidden[i])
end

local modVersion = assert(modInfo:match("\nmodversion=([^\r\n]+)"), "modversion missing")
local luaVersion = assert(version:match('GSSiK_Addon_Craft.VERSION%s*=%s*"([^"]+)"'),
	"Lua version mirror missing")
assert(modVersion == luaVersion, "version mismatch: " .. modVersion .. " vs " .. luaVersion)
assert(modVersion == "1.5.0", "unexpected Craft baseline version: " .. modVersion)

print("PASS terminal_ui_framework_contract")
