-- Author contract for semantic UI state across resize and reopen.

local Support = dofile("tests/helpers/sik_ui_contract_support.lua")
local suite = Support.newSuite("sik_ui_state_contract")

local State = Support.loadFrameworkModule(suite, "State")
local snapshot = Support.requireFunction(suite, State, "snapshot", "State.snapshot")
local merge = Support.requireFunction(suite, State, "merge", "State.merge")

if snapshot and merge then
	Support.check(suite, "resize preserves semantic selection expansion sort and scroll", function()
		local source = {
			selectedKey = "item:Base.WaterBottle",
			expandedKeys = { ["family:food"] = true, ["media:vhs"] = true },
			sortKey = "name",
			sortAscending = false,
			scrollY = 312,
			activeTab = "warehouse",
			searchText = "bidon",
		}
		local captured = snapshot(source)
		local target = assert(merge({}, captured))
		assert(target.selectedKey == source.selectedKey, "selection lost")
		assert(target.expandedKeys["family:food"] == true, "expansion lost")
		assert(target.sortKey == source.sortKey and target.sortAscending == false, "sort lost")
		assert(target.scrollY == source.scrollY, "scroll lost")
		assert(target.activeTab == source.activeTab, "tab lost")
		assert(target.searchText == source.searchText, "search lost")
		return true
	end)

	Support.check(suite, "reopen restores copied state without aliasing mutable tables", function()
		local source = { expandedKeys = { a = true }, selectedKey = "a", scrollY = 20 }
		local captured = snapshot(source)
		source.expandedKeys.a = false
		local target = assert(merge({}, captured))
		assert(target.expandedKeys.a == true, "snapshot aliases live state")
		target.expandedKeys.a = false
		assert(captured.expandedKeys.a == true, "restored state aliases snapshot")
		return true
	end)

	Support.check(suite, "restore clamps geometry-dependent scroll without dropping semantics", function()
		local captured = snapshot({ selectedKey = "row-40", expandedKeys = { group = true }, scrollY = 900 })
		local target = assert(merge({}, captured))
		target.scrollY = math.min(target.scrollY, 220)
		assert(target.scrollY == 220, "consumer clamp precondition failed")
		assert(target.selectedKey == "row-40", "semantic selection dropped")
		assert(target.expandedKeys.group == true, "semantic expansion dropped")
		return true
	end)

	Support.check(suite, "stored geometry and offset stay isolated per local player", function()
		State.save(0, "terminal-shell", { bounds = { x = 20, y = 30, w = 900, h = 600 }, scrollY = 140 })
		State.save(1, "terminal-shell", { bounds = { x = 980, y = 30, w = 700, h = 600 }, scrollY = 40 })
		local player0 = State.load(0, "terminal-shell")
		local player1 = State.load(1, "terminal-shell")
		assert(player0.bounds.x == 20 and player0.scrollY == 140, "player 0 state mixed")
		assert(player1.bounds.x == 980 and player1.scrollY == 40, "player 1 state mixed")
		return true
	end)
end

Support.check(suite, "State has one exact owner in the public namespace", function()
	assert(type(SiK) == "table" and type(SiK.UI) == "table", "SiK.UI unavailable")
	assert(SiK.UI.State == State, "State loaded outside SiK.UI")
	return true
end)

Support.finish(suite)
