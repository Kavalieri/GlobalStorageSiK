-- Exercise the actual private scheduler with controlled OnTick/instance seams.
local path = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/GS_TerminalUI_Api.lua"
local handle = assert(io.open(path, "rb"))
local source = handle:read("*a"):gsub("\r\n", "\n")
handle:close()
local threshold = assert(tonumber(source:match("local DEFER_REFRESH_ITEM_COUNT = (%d+)")))
local body = assert(source:match("local function applyTerminalState%(ui, state, forceDeferred%).-\nend\n"))
local active, callbacks, calls, errors = {}, {}, {}, {}
local env = setmetatable({
    DEFER_REFRESH_ITEM_COUNT = threshold,
    Events = { OnTick = {
        Add = function(callback) callbacks[#callbacks + 1] = callback end,
        Remove = function(callback)
            for i = #callbacks, 1, -1 do if callbacks[i] == callback then table.remove(callbacks, i) end end
        end,
    } },
    GlobalStorageSiK = {
        TerminalUI = { getInstanceForPlayer = function(playerNum) return active[playerNum] end, showCatalogFailure = function() end },
        Log = { error = function(...) errors[#errors + 1] = { ... } end },
    },
	Loading = {
		lock = function() end,
		unlock = function() end,
		finish = function(ui, expected) if ui._gsCatalogLoad == expected then ui._gsCatalogLoad = nil end end,
	},
}, { __index = _G })
local chunk = assert(loadstring(body .. "\nreturn applyTerminalState"))
setfenv(chunk, env)
local apply = chunk()
local function check(value, message) assert(value, message) end
local function window(playerNum)
    local ui = { playerNum = playerNum, refreshFromState = function(self, state)
        calls[#calls + 1] = { ui = self, state = state }
    end }
    function ui:onClose() self.closed = true; active[playerNum] = nil end
    active[playerNum] = ui
    return ui
end
local function tick()
    local snapshot = {}
    for i = 1, #callbacks do snapshot[i] = callbacks[i] end
    for i = 1, #snapshot do snapshot[i]() end
end
local large = { items = {} }
for i = 1, threshold + 1 do large.items[i] = { id = i } end
local small, newest = { items = { { id = 1 } } }, { items = {} }
local ui = window(0)
apply(ui, large)
apply(ui, small)
check(#calls == 0, "small state bypassed the already queued refresh")
check(#callbacks == 1, "more than one callback owns the pending state")
tick()
check(#calls == 1 and calls[1].state == small, "queued refresh must apply latest state exactly once")
check(#callbacks == 0 and ui._gsPendingTerminalState == nil and not ui._gsTerminalRefreshQueued, "queue not released")
apply(ui, small, true)
apply(ui, large)
apply(ui, newest)
tick()
check(#calls == 2 and calls[2].state == newest, "empty latest catalog lost during coalescing")
apply(ui, small)
check(#calls == 3 and #callbacks == 0, "small unqueued refresh should stay immediate")
local other = window(1)
apply(ui, large)
apply(other, small, true)
active[0] = window(0)
tick()
check(#calls == 4 and calls[4].ui == other, "closed/replaced window refreshed or another player lost state")
check(ui._gsPendingTerminalState == nil, "replaced window retains the pending catalog")
local failing = window(2)
failing.refreshFromState = function() error("fixture failure") end
apply(failing, small, true)
tick()
check(#errors == 1 and not failing._gsTerminalRefreshQueued and #callbacks == 0, "failure retained scheduler")
failing.refreshFromState = ui.refreshFromState
apply(failing, newest)
check(#calls == 5 and calls[5].state == newest, "scheduler failed to recover")
print("terminal_refresh_coalescing_contract PASS: latest state, empty catalog, immediate path, replacement, players, failure recovery")
