-- Author contract for canonical SiK UI tokens and per-player safe viewport.
-- Run from GlobalStorageSiK-Repo with Lua 5.1.

local Support = dofile("tests/helpers/sik_ui_contract_support.lua")
local suite = Support.newSuite("sik_ui_metrics_viewport_contract")

Support.loadClientModule(suite, "GS_SiK_UI_Metrics")
Support.loadClientModule(suite, "GS_SiK_UI_Viewport")

local ui = GlobalStorageSiK and GlobalStorageSiK.SiK_UI or {}
local Metrics = ui.Metrics
local Viewport = ui.Viewport
local tokensFn = Support.requireFunction(suite, Metrics, "tokens", "Metrics.tokens")
local profileFn = Support.requireFunction(suite, Metrics, "profile", "Metrics.profile")
local viewportFn = Support.requireFunction(suite, Viewport, "resolve", "Viewport.resolve")

local tokens
if tokensFn then
	Support.check(suite, "canonical gutter and safe-area tokens", function()
		tokens = tokensFn()
		assert(type(tokens) == "table", "tokens must return a table")
		assert(tokens.safeMargin == 16, "safeMargin must be 16")
		assert(tokens.blockPaddingX == 8, "blockPaddingX must be 8")
		assert(tokens.scrollBarWidth == 14, "scrollBarWidth must be 14")
		assert(tokens.scrollBarGap == 10, "scrollBarGap must be 10")
		assert(tokens.scrollGutter == 24, "scrollGutter must be 24")
		assert(tokens.blockBaseReservation == 16,
			"blockBaseReservation must be left + right padding")
		assert(tokens.blockHorizontalReservation == 40,
			"maximum reservation must be 8 + 8 + 24")
		return true
	end)
end

if profileFn then
	Support.check(suite, "terminal uses one canonical geometry across legacy profile names", function()
		local compact = profileFn("compact")
		local standard = profileFn("standard")
		local wide = profileFn("wide")
		assert(type(compact) == "table" and compact.name == "terminal", "compact alias")
		assert(type(standard) == "table" and standard.name == "terminal", "standard alias")
		assert(type(wide) == "table" and wide.name == "terminal", "wide alias")
		for _, profile in ipairs({ compact, standard, wide }) do
			assert(type(profile.window) == "table", "terminal window metrics")
			assert(type(profile.controls) == "table", "terminal control metrics")
			assert(profile.window.preferredWidth == compact.window.preferredWidth
				and profile.window.preferredHeight == compact.window.preferredHeight,
				"legacy alias selected a second terminal geometry")
		end
		return true
	end)
end

if viewportFn then
	Support.check(suite, "viewport uses the requested local player and safe 16 inset", function()
		local players = {
			[0] = { x = 0, y = 0, w = 960, h = 1080 },
			[1] = { x = 960, y = 0, w = 960, h = 1080 },
		}
		local viewport = viewportFn(1, {
			screenW = 1920,
			screenH = 1080,
			playerRect = function(playerNum) return players[playerNum] end,
		})
		Support.assertRect(viewport, "viewport")
		assert(viewport.x == 976 and viewport.y == 16, "safe origin belongs to player 1")
		assert(viewport.w == 928 and viewport.h == 1048, "safe inset applies on every edge")
		assert(viewport.playerNum == 1, "player identity retained")
		assert(viewport.profile == "terminal", "viewport selected a second terminal geometry")
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
		assert(viewport.playerNum == 2, "local player retained")
		assert(viewport.x >= 816 and viewport.y >= 466, "own quadrant inset")
		return true
	end)
end

Support.finish(suite)
