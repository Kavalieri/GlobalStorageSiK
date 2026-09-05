-- Focused runtime contract for the public Block geometry API.

local Support = dofile("tests/helpers/sik_ui_contract_support.lua")
local suite = Support.newSuite("sik_ui_block_geometry_subscription_regression")
local Block = Support.loadFrameworkModule(suite, "Block")

if Block then
	Support.check(suite, "resolveViewportRect keeps direct short content intact", function()
		local viewport, track = Block.resolveViewportRect({ x = 8, y = 4, w = 500, h = 120 }, false)
		assert(viewport.x == 8 and viewport.y == 4 and viewport.w == 500 and viewport.h == 120,
			"short direct block changed its content rectangle")
		assert(track == nil, "short direct block created an unnecessary track")
		return true
	end)

	Support.check(suite, "resolveViewportRect subtracts only the functional overflow gutter", function()
		local viewport, track = Block.resolveViewportRect({ x = 0, y = 0, w = 500, h = 120 }, true)
		assert(viewport.w == 476, "overflow content width must be W-24")
		assert(track and track.x == 486 and track.w == 14 and track.h == 120,
			"overflow track must start at W-14 with the canonical width")
		return true
	end)

	Support.check(suite, "setBounds synchronously notifies subscribers with the current rect", function()
		local parent = ISPanel:new(0, 0, 600, 400); parent:initialise()
		local instance = assert(Block.create({ parent = parent, x = 0, y = 0, w = 300, h = 160 }))
		local calls, received = 0, nil
		assert(instance:subscribe(function(_, rect, previous, reason)
			calls = calls + 1; received = { rect = rect, previous = previous, reason = reason }
		end))
		assert(instance:setBounds(4, 6, 340, 180))
		assert(calls == 1 and received and received.reason == "bounds", "bounds did not notify synchronously")
		local current = instance:getContentRect()
		assert(received.rect.x == current.x and received.rect.w == current.w,
			"subscriber received stale content geometry")
		assert(received.previous and received.previous.w ~= current.w, "previous geometry was not retained")
		assert(instance:setBounds(4, 6, 340, 180) and calls == 1,
			"unchanged bounds emitted a duplicate notification")
		instance:dispose()
		return true
	end)
end

Support.finish(suite)
