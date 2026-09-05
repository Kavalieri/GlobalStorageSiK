-- B42 may update only the native ISUIElement rectangle from setters. SiK UI
-- mirrors it into Lua fields because renderers and diagnostics consume both.

local Support = dofile("tests/helpers/sik_ui_contract_support.lua")
local suite = Support.newSuite("sik_ui_native_geometry_mirror_regression")
local Layout = Support.loadFrameworkModule(suite, "Layout")

if Layout then
	Support.check(suite, "Layout.apply mirrors native and Lua geometry", function()
		local native = {}
		local widget = {
			setX = function(_, value) native.x = value end,
			setY = function(_, value) native.y = value end,
			setWidth = function(_, value) native.w = value end,
			setHeight = function(_, value) native.h = value end,
		}
		Layout.apply(widget, { x = 7, y = 9, w = 56, h = 56 })
		assert(native.x == 7 and native.y == 9 and native.w == 56 and native.h == 56,
			"native setters did not receive the resolved rectangle")
		assert(widget.x == 7 and widget.y == 9 and widget.width == 56 and widget.height == 56,
			"Lua geometry was left at its construction size")
		return true
	end)
end

local builderPath = "../SiKUIFramework-Repo/SiKUIFramework/Contents/mods/SiKUIFramework/42/media/lua/client/SiK/UI/Builder.lua"
Support.check(suite, "Builder does not inset an owned content rectangle twice", function()
	local file = assert(io.open(builderPath, "rb"))
	local source = assert(file:read("*a")); file:close()
	assert(source:find("_sikContentAlreadyInset", 1, true),
		"Builder does not mark component-owned content rectangles")
	assert(source:find("area._sikContentAlreadyInset and 0 or parentLayout.padding", 1, true),
		"Builder still reapplies parent padding to an already inset content rectangle")
	return true
end)

Support.finish(suite)
