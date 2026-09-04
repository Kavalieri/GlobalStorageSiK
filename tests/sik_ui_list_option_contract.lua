-- Author contract for the neutral public SiK.UI Controls.listOption component.

local Support = dofile("tests/helpers/sik_ui_contract_support.lua")
local suite = Support.newSuite("sik_ui_list_option_contract")
local Controls = Support.loadFrameworkModule(suite, "Controls")

getTextManager = function()
	return { getFontHeight = function() return 12 end,
		MeasureStringX = function(_, _, text) return #tostring(text or "") * 6 end }
end

local create = Support.requireFunction(suite, Controls, "listOption", "Controls.listOption")
if create then
	Support.check(suite, "ListOption uses canonical padding and dynamic wrapped height", function()
		local parent = ISPanel:new(0, 0, 300, 300); parent:initialise()
		local short = create(parent, { w = 160, text = "short" })
		local long = create(parent, { w = 100, text = string.rep("x", 80) })
		assert(short.height >= Controls.metrics().rowHeight,
			"short option ignores canonical row height")
		assert(long.height > short.height and #long.lines > 1,
			"long option does not wrap and grow")
		assert(short._sikUiControl == "listOption", "component identity missing")
		return true
	end)

	Support.check(suite, "ListOption state API updates payload selection availability and loading", function()
		local parent = ISPanel:new(0, 0, 300, 300); parent:initialise()
		local option = create(parent, { w = 120, text = "Initial", selected = true,
			payload = { id = "initial" } })
		assert(option.payload.id == "initial", "initial payload missing")
		assert(option:isSelected() and option:isEnabled(), "initial state missing")
		option:setData({ text = string.rep("z", 60), enabled = false, id = "next" })
		assert(not option:isEnabled(), "setData enabled state ignored")
		assert(option.payload.id == "next" and option.height > Controls.metrics().rowHeight,
			"setData did not update payload and wrapped height")
		option:setEnabled(true):setSelected(false):setLoading(true)
		assert(not option:isEnabled() and option:isLoading(), "loading must block activation")
		option:setLoading(false)
		assert(option:isEnabled() and not option:isSelected(), "state recovery failed")
		return true
	end)

	Support.check(suite, "ListOption callback keeps exact public context and blocks disabled states", function()
		local calls, received = 0, nil
		local parent = ISPanel:new(0, 0, 300, 300); parent:initialise()
		local option = create(parent, { w = 140, text = "Clickable", payload = { id = "opaque" },
			onClick = function(context) calls = calls + 1; received = context; return true end })
		option.onclick(option.target)
		assert(calls == 1 and received.component == option and received.payload.id == "opaque",
			"callback context or payload mismatch")
		option:setEnabled(false); option.onclick(option.target)
		option:setEnabled(true):setLoading(true); option.onclick(option.target)
		assert(calls == 1, "disabled/loading state invoked callback")
		return true
	end)

	Support.check(suite, "ListOption exists only in SiK.UI", function()
		assert(SiK.UI.Controls == Controls, "Controls owner differs from public namespace")
		assert(rawget(_G, "GlobalStorageSiK") == nil
			or rawget(GlobalStorageSiK, "SiK_UI") == nil,
			"private Core namespace recreated")
		return true
	end)
end

Support.finish(suite)
