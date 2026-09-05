-- The terminal rail uses 76px cells, cross inset 10, and exact 56px assets.
local tabsPath = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/GS_TerminalUI_Tabs.lua"
local tabs = assert(io.open(tabsPath, "rb")):read("*a")
local metricsPath = "../SiKUIFramework-Repo/SiKUIFramework/Contents/mods/SiKUIFramework/42/media/lua/client/SiK/UI/Metrics.lua"
local metrics = assert(io.open(metricsPath, "rb")):read("*a")
assert(tabs:find("iconSize = 56", 1, true) and tabs:find("iconExact = true", 1, true)
	and tabs:find("iconOnly = true", 1, true), "rail does not request the exact product icon contract")
assert(tabs:find("railCrossInset = 10", 1, true), "rail cross inset drifted from the validated HTML")
assert(metrics:find("railWidth = 76", 1, true) and metrics:find("railItemHeight = 76", 1, true),
	"framework rail cell is not 76px")
print("PASS terminal rail exact icon contract")
