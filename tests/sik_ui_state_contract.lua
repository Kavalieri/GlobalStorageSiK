-- Author contract for semantic UI state across resize and reopen.

local Support = dofile("tests/helpers/sik_ui_contract_support.lua")
local suite = Support.newSuite("sik_ui_state_contract")

Support.loadClientModule(suite, "GS_SiK_UI_State")

local ui = GlobalStorageSiK and GlobalStorageSiK.SiK_UI or {}
local State = ui.State
local capture = Support.requireFunction(suite, State, "capture", "State.capture")
local restore = Support.requireFunction(suite, State, "restore", "State.restore")

if capture and restore then
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
		local snapshot = capture(source)
		local target = restore({}, snapshot, { reason = "resize" })
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
		local snapshot = capture(source)
		source.expandedKeys.a = false
		local target = restore({}, snapshot, { reason = "reopen" })
		assert(target.expandedKeys.a == true, "snapshot aliases live state")
		target.expandedKeys.a = false
		assert(snapshot.expandedKeys.a == true, "restored state aliases snapshot")
		return true
	end)

	Support.check(suite, "restore clamps geometry-dependent scroll without dropping semantics", function()
		local snapshot = capture({ selectedKey = "row-40", expandedKeys = { group = true }, scrollY = 900 })
		local target = restore({}, snapshot, { reason = "resize", maxScrollY = 220 })
		assert(target.scrollY == 220, "scroll not clamped")
		assert(target.selectedKey == "row-40", "semantic selection dropped")
		assert(target.expandedKeys.group == true, "semantic expansion dropped")
		return true
	end)

	Support.check(suite, "stored geometry and offset stay isolated per local player", function()
		State.saveBounds("terminal-shell", 0, { x = 20, y = 30, w = 900, h = 600 })
		State.saveBounds("terminal-shell", 1, { x = 980, y = 30, w = 700, h = 600 })
		State.saveOffset("terminal-shell", 0, 140)
		State.saveOffset("terminal-shell", 1, 40)
		local player0 = State.load("terminal-shell", 0)
		local player1 = State.load("terminal-shell", 1)
		assert(player0.bounds.x == 20 and player0.scrollY == 140, "player 0 state mixed")
		assert(player1.bounds.x == 980 and player1.scrollY == 40, "player 1 state mixed")
		return true
	end)
end

-- Optional hook: if the framework publishes a runtime surface inventory, it
-- must reject duplicate IDs. Absence is explicitly reported, never a PASS.
local Inventory = ui.SurfaceInventory
if type(Inventory) == "table" then
	local register = Support.requireFunction(suite, Inventory, "register", "SurfaceInventory.register")
	local all = Support.requireFunction(suite, Inventory, "all", "SurfaceInventory.all")
	if register and all then
		Support.check(suite, "surface inventory has stable unique identifiers", function()
			register({ id = "contract-window", kind = "window" })
			local duplicateOk = pcall(register, { id = "contract-window", kind = "modal" })
			assert(not duplicateOk, "duplicate surface ID accepted")
			local seen = {}
			for _, surface in ipairs(all()) do
				assert(type(surface.id) == "string" and surface.id ~= "", "surface without ID")
				assert(not seen[surface.id], "duplicate surface in inventory")
				seen[surface.id] = true
			end
			return true
		end)
	end
else
	Support.blocked(suite, "SurfaceInventory", "optional hook not implemented; required before automated full-surface coverage")
end

Support.finish(suite)
