-- Author contract for canonical SiK UI tokens and per-player safe viewport.
-- Run from GlobalStorageSiK-Repo with Lua 5.1.

local Support = dofile("tests/helpers/sik_ui_contract_support.lua")
local suite = Support.newSuite("sik_ui_metrics_viewport_contract")

local Metrics = Support.loadFrameworkModule(suite, "Metrics")
local Viewport = Support.loadFrameworkModule(suite, "Viewport")
local tokensFn = Support.requireFunction(suite, Metrics, "tokens", "Metrics.tokens")
local profileFn = Support.requireFunction(suite, Metrics, "profile", "Metrics.profile")
local viewportFn = Support.requireFunction(suite, Viewport, "resolve", "Viewport.resolve")
local safeFn = Support.requireFunction(suite, Viewport, "safe", "Viewport.safe")

local tokens
if tokensFn then
	Support.check(suite, "canonical gutter and safe-area tokens", function()
		tokens = tokensFn()
		assert(type(tokens) == "table", "tokens must return a table")
		assert(tokens.safeMargin == 16, "safeMargin must be 16")
		assert(tokens.block.padding == 8, "block padding must be 8")
		assert(tokens.block.scrollBarWidth == 14, "scroll width must be 14")
		assert(tokens.block.scrollGap == 10, "scroll gap must be 10")
		assert(tokens.block.scrollGutter == 24, "scroll gutter must be 24")
		assert(tokens.block.padding * 2 == 16,
			"blockBaseReservation must be left + right padding")
		assert(tokens.block.padding * 2 + tokens.block.scrollGutter == 40,
			"maximum reservation must be 8 + 8 + 24")
		return true
	end)
end

if profileFn then
	Support.check(suite, "responsive and product profiles have one deterministic selector", function()
		local compact = profileFn(0, "compact")
		local standard = profileFn(0, "standard")
		local wide = profileFn(0, "wide")
		assert(compact.name == "compact" and standard.name == "standard"
			and wide.name == "wide", "requested responsive profile changed")
		assert(profileFn(719).name == "compact" and profileFn(720).name == "standard"
			and profileFn(1000).name == "wide", "width thresholds changed")
		local terminal = profileFn(0, "terminal")
		assert(terminal.name == "terminal" and type(terminal.window) == "table"
			and type(terminal.controls) == "table", "terminal product profile incomplete")
		return true
	end)
end

if viewportFn and safeFn then
	Support.check(suite, "viewport uses the requested local player and safe 16 inset", function()
		local players = {
			[0] = { x = 0, y = 0, w = 960, h = 1080 },
			[1] = { x = 960, y = 0, w = 960, h = 1080 },
		}
		local viewport = safeFn(1, {
			playerRect = function(playerNum) return players[playerNum] end,
		})
		Support.assertRect(viewport, "viewport")
		assert(viewport.x == 976 and viewport.y == 16, "safe origin belongs to player 1")
		assert(viewport.w == 928 and viewport.h == 1048, "safe inset applies on every edge")
		return true
	end)

	Support.check(suite, "viewport never falls back to player zero for split-screen", function()
		local viewport = viewportFn(2, {
			screenW = 1600,
			screenH = 900,
			playerRect = function(playerNum)
				assert(playerNum == 2, "wrong local player requested")
				return { x = 800, y = 450, w = 800, h = 450 }
			end,
		})
		assert(viewport.x == 800 and viewport.y == 450,
			"resolve did not retain the requested player's quadrant")
		return true
	end)
end

Support.finish(suite)
