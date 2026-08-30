local function readFile(path)
	local handle = assert(io.open(path, "rb"))
	local data = handle:read("*a")
	handle:close()
	return data
end

local root = "addons/GSSiK_Addon_Builder/"
local luaPath = root .. "Contents/mods/GSSiK_Addon_Builder/42/media/lua/client/"
	.. "GSSiK_Addon_Builder_TerminalUI.lua"
local modInfoPath = root .. "Contents/mods/GSSiK_Addon_Builder/42/mod.info"
local configPath = root .. "Contents/mods/GSSiK_Addon_Builder/42/media/lua/shared/"
	.. "GSSiK_Addon_Builder_Sandbox.lua"

local source = readFile(luaPath)
assert(source:find('require "GS_SiK_UI_Controls"', 1, true))
assert(source:find("Controls.blockHeader", 1, true))
assert(source:find("Controls.status", 1, true))
assert(source:find("Controls.button", 1, true))
assert(source:find("TerminalScroll.setOnContentRectChanged", 1, true))
assert(source:find("TerminalScroll.contentRect", 1, true))
assert(not source:find("CONTENT_PAD", 1, true))
assert(not source:find("BLOCK_GAP", 1, true))
assert(not source:find("BTN_H", 1, true))
assert(not source:find("versionLbl", 1, true))
assert(not source:find("options.right", 1, true))
assert(not source:find("_gsScrollBarGap", 1, true))
assert(not source:find("drawRect(", 1, true))

local modInfo = readFile(modInfoPath)
local config = readFile(configPath)
local modVersion = assert(modInfo:match("modversion=([^\r\n]+)"))
local configVersion = assert(config:match('GSSiK_Addon_Builder.VERSION%s*=%s*"([^"]+)"'))
assert(modVersion == "1.5.0", "unexpected Builder baseline version: " .. modVersion)
assert(configVersion == modVersion,
	"Builder config/mod.info version mismatch: " .. configVersion .. " vs " .. modVersion)

print("builder_terminal_ui_contract: OK")
