-- Public SiK.UI shell ownership and geometry contract.
-- Pure Lua 5.1/static checks; no Project Zomboid window is rendered.

local Support = dofile("tests/helpers/sik_ui_contract_support.lua")
local suite = Support.newSuite("sik_ui_shell_parity_contract")

local function read(path)
	local file = assert(io.open(path, "rb"), path)
	local text = file:read("*a"); file:close(); return text
end
local function contains(text, needle, label)
	assert(text:find(needle, 1, true), label or ("missing " .. needle))
end
local function excludes(text, needle, label)
	assert(not text:find(needle, 1, true), label or ("unexpected " .. needle))
end

local CLIENT = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/"
local frameworkEntry = read(Support.frameworkRoot() .. "SiK_UI.lua")
local binding = read(CLIENT .. "GS_UI_Framework.lua")
local terminal = read(CLIENT .. "GS_TerminalUI.lua")
local staff = read(CLIENT .. "GS_AdminDashboard.lua")
local windowSource = read(Support.frameworkPath("Window.lua"))
local surfaceSource = read(Support.frameworkPath("Surface.lua"))

Support.check(suite, "standalone entrypoint owns one public namespace", function()
	contains(frameworkEntry, 'require "SiK/UI/Namespace"', "entrypoint misses Namespace")
	contains(frameworkEntry, 'require "SiK/UI/Surface"', "entrypoint misses Surface")
	contains(frameworkEntry, "local UI = SiK.UI", "entrypoint does not bind public namespace")
	contains(frameworkEntry, "return UI", "entrypoint does not return public namespace")
	contains(binding, 'pcall(require, "SiK_UI")', "Core binding bypasses guarded standalone entrypoint")
	contains(binding, 'error("Global Storage SiK requires the SiKUIFramework mod',
		"Core binding does not fail explicitly when the framework is unavailable")
	contains(binding, "return SiK.UI", "Core binding does not return public API")
	contains(binding, "no embedded UI", "strict no-fallback ownership is undocumented")
	return true
end)

Support.check(suite, "Core shells consume public Window instead of private chrome", function()
	for name, source in pairs({ Terminal = terminal, Staff = staff }) do
		contains(source, 'require "GS_UI_Framework"', name .. " does not load strict binding")
		contains(source, "UI.Window.apply(self", name .. " does not apply public Window")
	end
	contains(terminal, "UI.Window.chromeRects(self)", "terminal does not consume public content geometry")
	contains(terminal, "navigationContainer:getContentBounds(fallbackBounds)",
		"terminal bypasses the public container geometry contract")
	contains(terminal, "navigationContainer:setNavigationVisible(not blockedMode)",
		"terminal bypasses the public container navigation contract")
	excludes(terminal, "navigationContainer.navigation",
		"terminal reads mutable navigation internals")
	contains(terminal, 'profile = "terminal"', "terminal profile changed")
	contains(staff, 'profile = "staff"', "Staff profile changed")
	return true
end)

Support.check(suite, "framework owns header footer resize and focus lifecycle", function()
	contains(windowSource, "function Window.chromeRects(panel)", "chrome geometry is not public")
	contains(windowSource, "function Window.resizeHandleRect(panel, size)", "resize handle is not public")
	contains(windowSource, "SiK.UI.FocusStack.install", "Window does not register focus")
	contains(windowSource, "SiK.UI.State", "Window does not own persisted geometry")
	contains(surfaceSource, "function Surface.validate(spec)", "declarative surface validator missing")
	contains(surfaceSource, 'ref.namespace ~= "SiK.UI"', "surface provenance accepts another namespace")
	return true
end)

local Metrics = Support.loadFrameworkModule(suite, "Metrics")
local Viewport = Support.loadFrameworkModule(suite, "Viewport")
local State = Support.loadFrameworkModule(suite, "State")
local Window = Support.loadFrameworkModule(suite, "Window")
local Surface = Support.loadFrameworkModule(suite, "Surface")

Support.check(suite, "window profiles clamp to each player viewport", function()
	local players = {
		[0] = { x = 0, y = 0, w = 1920, h = 1080 },
		[1] = { x = 960, y = 0, w = 960, h = 1080 },
	}
	local environment = { playerRect = function(playerNum) return players[playerNum] end }
	local standard = Window.resolveBounds({ profile = "terminal", playerNum = 0,
		w = 5000, h = 5000, environment = environment })
	local split = Window.resolveBounds({ profile = "terminal", playerNum = 1,
		w = 5000, h = 5000, environment = environment })
	assert(standard.x >= 0 and standard.y >= 0 and standard.x + standard.w <= 1920,
		"standard window escaped player 0")
	assert(split.x >= 960 and split.x + split.w <= 1920 and split.playerNum == 1,
		"split-screen window escaped player 1")
	assert(split.w <= standard.w, "narrow player viewport did not constrain width")
	return true
end)

Support.check(suite, "chrome rectangles reserve header footer and content once", function()
	local panel = {
		x = 0, y = 0, width = 960, height = 680,
		windowPadding = 14, contentPadding = 14,
		headerHeight = 52, footerHeight = 34,
		_sikWindowOptions = { footerHeight = 34 },
	}
	local rects = assert(Window.chromeRects(panel))
	assert(rects.header.x == 0 and rects.header.w == 960 and rects.header.h == 52,
		"header rect drifted")
	assert(rects.content.x == 14 and rects.content.y == 52 + 14
		and rects.content.w == 960 - 28
		and rects.content.h == 680 - 52 - 34 - 28,
		"content double-reserved chrome")
	assert(rects.footer.y == 680 - 34 and rects.footer.h == 34,
		"footer rect drifted")
	local handle = Window.resizeHandleRect(panel, 14)
	assert(handle.x == 946 and handle.y == 666, "resize handle is not bottom-right")
	return true
end)

Support.check(suite, "state remains isolated and surface validation is fail-closed", function()
	State.save(0, "shell", { profile = "terminal", activeTab = "warehouse" })
	State.save(1, "shell", { profile = "staff", activeTab = "admin" })
	assert(State.load(0, "shell").profile == "terminal", "player 0 state changed")
	assert(State.load(1, "shell").profile == "staff", "player 1 state leaked")
	local ok, err = Surface.validate({})
	assert(ok == false and type(err) == "string" and err ~= "",
		"invalid surface artifact did not fail closed")
	assert(type(Metrics.tokens) == "function" and type(Viewport.safe) == "function",
		"shell dependencies are not public APIs")
	return true
end)

Support.finish(suite)
