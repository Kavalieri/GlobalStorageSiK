-- The terminal rail is 76px wide (56 + 10 + 10) and uses square 56px cells/assets.
local tabsPath = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/GS_TerminalUI_Tabs.lua"
local tabs = assert(io.open(tabsPath, "rb")):read("*a")
local metricsPath = "../SiKUIFramework-Repo/SiKUIFramework/Contents/mods/SiKUIFramework/42/media/lua/client/SiK/UI/Metrics.lua"
local metrics = assert(io.open(metricsPath, "rb")):read("*a")
local frameworkTabsPath = "../SiKUIFramework-Repo/SiKUIFramework/Contents/mods/SiKUIFramework/42/media/lua/client/SiK/UI/Tabs.lua"
local frameworkTabs = assert(io.open(frameworkTabsPath, "rb")):read("*a")
local frameworkIconPath = "../SiKUIFramework-Repo/SiKUIFramework/Contents/mods/SiKUIFramework/42/media/lua/client/SiK/UI/Icon.lua"
local frameworkIcon = assert(io.open(frameworkIconPath, "rb")):read("*a")
assert(tabs:find("iconSize = 56", 1, true) and tabs:find("iconExact = true", 1, true)
	and tabs:find("iconOnly = true", 1, true), "rail does not request the exact product icon contract")
assert(tabs:find("railCrossInset = 10", 1, true), "rail cross inset drifted from the validated HTML")
assert(metrics:find("railWidth = 76", 1, true)
	and metrics:find("railItemHeight = 56", 1, true)
	and metrics:find("railIconSize = 56", 1, true),
	"framework rail does not preserve the 76px track with a square 56px cell and asset")
assert(frameworkTabs:find('or "semantic"', 1, true)
	and frameworkTabs:find('or "source"', 1, true),
	"exact product artwork is still implicitly tinted instead of preserving source colour")
local nativeBranch = assert(frameworkIcon:find("if target.drawTexture then", 1, true),
	"exact icons do not prefer the native renderer")
local scaledBranch = assert(frameworkIcon:find("target:drawTextureScaled", nativeBranch, true),
	"exact icon compatibility fallback is missing")
assert(nativeBranch < scaledBranch,
	"exact product artwork is routed through scaling before the native renderer")
print("PASS terminal rail exact icon contract")
