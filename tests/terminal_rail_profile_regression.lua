-- The product rail and the framework Navigation must consume the same public
-- terminal profile. No removed product-local railProfile helper may survive.

local path = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/GS_TerminalUI_Tabs.lua"
local handle = assert(io.open(path, "rb"))
local source = handle:read("*a")
handle:close()

assert(source:find('UI.Metrics.profile(width or 0, "terminal")', 1, true),
	"rail width does not consume the public terminal profile")
assert(source:find('profile = "terminal"', 1, true),
	"Navigation does not consume the same terminal profile")
assert(not source:find("railProfile()", 1, true),
	"removed railProfile helper is still called")

local requestedWidth, requestedProfile
GlobalStorageSiK = { I18n = { text = function(key) return key end } }
package.preload["GS_I18n"] = function() return true end
package.preload["GS_Sandbox"] = function() return true end
package.preload["GS_UI_Framework"] = function()
	return { Metrics = { profile = function(width, profile)
		requestedWidth, requestedProfile = width, profile
		return { window = { railWidth = 76 } }
	end } }
end

assert(loadfile(path))()
assert(GlobalStorageSiK.TerminalTabs.measureRailWidth({ width = 1440 }) == 76,
	"runtime rail measurement did not return the terminal profile width")
assert(requestedWidth == 1440 and requestedProfile == "terminal",
	"runtime rail measurement requested a different profile")

print("PASS: terminal rail measurement and Navigation share the terminal profile")
