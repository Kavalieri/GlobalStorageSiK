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
local context = readFile(root .. "Contents/mods/GSSiK_Addon_Builder/42/media/lua/client/"
	.. "GSSiK_Addon_Builder/UI/TabBuilderContext.lua")
local generated = readFile(root .. "Contents/mods/GSSiK_Addon_Builder/42/media/lua/client/"
	.. "GSSiK_Addon_Builder/UI/Generated/TabBuilder.lua")
local spec = readFile(root .. "ui/surfaces/tab-builder.surface.json")
assert(source:find('local Surface = require "GSSiK_Addon_Builder/UI/Generated/TabBuilder"', 1, true))
assert(source:find('local Context = require "GSSiK_Addon_Builder/UI/TabBuilderContext"', 1, true))
assert(source:find('TerminalModule.surfaceId = "tab-builder"', 1, true))
assert(source:find("TerminalModule.surface = Surface", 1, true))
assert(source:find("TerminalModule.builder = SiK.UI.SurfaceHost.mount", 1, true))
assert(source:find("function TerminalModule.contextFactory(terminal)", 1, true))
assert(source:find("return Context.create(terminal)", 1, true))
assert(not source:find("CONTENT_PAD", 1, true))
assert(not source:find("BLOCK_GAP", 1, true))
assert(not source:find("BTN_H", 1, true))
assert(not source:find("versionLbl", 1, true))
assert(not source:find("options.right", 1, true))
assert(not source:find("_gsScrollBarGap", 1, true))
assert(not source:find("drawRect(", 1, true))
assert(not source:find("GS_SiK_UI", 1, true))
assert(not source:find("TerminalScroll", 1, true))
assert(not source:find("ISPanel:new", 1, true))
assert(not source:find("buildPanel", 1, true))
assert(not source:find("function TerminalModule.layout", 1, true))
assert(not source:find("setBounds(", 1, true))
assert(not source:find("UI.Controls", 1, true))
assert(not source:find("UI.Scroll", 1, true))
assert(context:find("actions = actions", 1, true), "context omits declarative actions")
assert(context:find("conditions =", 1, true), "context omits declarative conditions")
assert(context:find("i18n =", 1, true), "context omits runtime i18n")
assert(context:find("terminal.onOpenVanillaBuild", 1, true), "vanilla build action lost")
assert(context:find("terminal.onOpenNeatBuild", 1, true), "Neat build action lost")
assert(generated:find("Generated data only. Do not edit.", 1, true))
assert(generated:find('"tab-builder"', 1, true))
assert(spec:find('"documentKind": "product-surface-spec"', 1, true))
assert(spec:find('"validation": "HTML_VALIDATED_BY_KAVA"', 1, true))

local modInfo = readFile(modInfoPath)
local config = readFile(configPath)
local modVersion = assert(modInfo:match("modversion=([^\r\n]+)"))
local configVersion = assert(config:match('GSSiK_Addon_Builder.VERSION%s*=%s*"([^"]+)"'))
assert(modVersion == "1.0.9-dev1.6", "unexpected Builder candidate version: " .. modVersion)
assert(configVersion == modVersion,
	"Builder config/mod.info version mismatch: " .. configVersion .. " vs " .. modVersion)

print("builder_terminal_ui_contract: OK")
