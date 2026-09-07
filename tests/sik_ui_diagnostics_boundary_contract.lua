local function read(path)
	local file = assert(io.open(path, "rb"))
	local text = file:read("*a")
	file:close()
	return text
end

local framework = read("../SiKUIFramework-Repo/SiKUIFramework/Contents/mods/SiKUIFramework/42/media/lua/client/SiK/UI/Diagnostics.lua")
local navigation = read("../SiKUIFramework-Repo/SiKUIFramework/Contents/mods/SiKUIFramework/42/media/lua/client/SiK/UI/Navigation.lua")
local adapter = read("GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/GS_UIDebug.lua")
local frameworkSandbox = read("../SiKUIFramework-Repo/SiKUIFramework/Contents/mods/SiKUIFramework/42/media/sandbox-options.txt")

assert(framework:find("function Diagnostics.snapshot", 1, true),
	"framework must own component-tree inspection")
assert(framework:find("function Diagnostics.checkOverlaps", 1, true),
	"framework must own overlap inspection")
assert(framework:find("function Diagnostics.inspectMount", 1, true),
	"framework must own mounted-content diagnosis")
assert(navigation:find("self.mountedContents", 1, true)
	and navigation:find("panel:setVisible(contentKey == key)", 1, true),
	"navigation activation must update adopted content visibility")
assert(framework:find('Diagnostics.registerSink("SiK.UI.Framework"', 1, true),
	"framework must own its diagnostic sink")
assert(framework:find("SandboxVars.SiKUIFramework.DebugMode", 1, true),
	"framework diagnostics must use the framework Sandbox namespace")
assert(frameworkSandbox:find("option SiKUIFramework.DebugMode", 1, true),
	"framework must expose diagnostics on its own Sandbox page")

assert(adapter:find("UI.Diagnostics.snapshot", 1, true),
	"Global Storage tree diagnostics must delegate to SiK UI")
assert(adapter:find("UI.Diagnostics.checkOverlaps", 1, true),
	"Global Storage overlap diagnostics must delegate to SiK UI")
assert(adapter:find("UI.Diagnostics.event(kind, message)", 1, true),
		"Global Storage diagnostics must delegate product events to the framework sink")
assert(adapter:find("function GlobalStorageSiK.UIDebug.log", 1, true),
		"Global Storage diagnostics adapter must preserve its product log API")
assert(not adapter:find("childrenInOrder", 1, true),
	"product adapter must not traverse the widget tree")
assert(not adapter:find("print(", 1, true),
	"product adapter must use the registered logger sink")

io.write("sik_ui_diagnostics_boundary_contract: OK\n")
return true
