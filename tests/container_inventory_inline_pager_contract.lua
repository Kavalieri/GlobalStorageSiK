-- Dynamic contract for the warehouse's inline external child pager adapter.
-- Extracts and executes the real adapter function with bounded product stubs.

local function read(path)
    local f = assert(io.open(path, "rb")); local s = f:read("*a"); f:close(); return s
end
local source = read("GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/GS_TerminalUI_Items.lua")
local start = assert(source:find("local function itemTableOptions(panel, terminal)", 1, true))
local finish = assert(source:find("\nend\n\n--- Runtime adapter", start, true)) + 4
local body = source:sub(start, finish)
local env = setmetatable({
    ROW_H = 20, HEADER_H = 22, ITEM_TABLE_OPTIONS = { gap = 8 },
    T = function(key, ...) return key end,
    itemRowAdapter = function() return {} end,
    rowIdentity = function(row) return row.id end,
    GlobalStorageSiK = { TerminalItems = {} },
}, { __index = _G })
local chunk = assert(loadstring(body .. "\nreturn itemTableOptions", "real_itemTableOptions"))
setfenv(chunk, env)
local itemTableOptions = chunk()

local details = {
    A = { page = 1, pageSize = 25, totalRows = 31, totalUnits = 31, networkId = "n", inventoryRevision = 7, ids = { 1, 2 } },
    B = { page = 1, pageSize = 2, totalRows = 2, totalUnits = 2, networkId = "n", inventoryRevision = 7, ids = { 8, 9 } },
}
local requests, refreshes, panel = {}, 0, { _detailPageByKey = {}, _detailPending = {} }
env.GlobalStorageSiK.TerminalItems.getDetails = function(key) return details[key] end
env.GlobalStorageSiK.TerminalItems.requestDetails = function(terminal, parent, page)
    requests[#requests + 1] = { key = parent.id, page = page }; return true
end
local terminal = { playerNum = 0, terminalState = { networkId = "n", inventoryRevision = 7 },
    refreshItemsTab = function() refreshes = refreshes + 1 end }
local options = itemTableOptions(panel, terminal)
assert(options.pagination and options.pagination.external == true,
    "warehouse adapter must declare external pagination")
local stateA = options.pagination.stateOf({ id = "A", count = 1 }, "A")
local stateB = options.pagination.stateOf({ id = "B", count = 2 }, "B")
assert(stateA.totalRows == 31 and stateA.totalUnits == 31 and stateB.totalRows == 2 and stateB.totalUnits == 2,
    "groups must retain independent row/unit totals")
assert(options.pagination.onPageChange({ parentKey = "A", parent = { id = "A" }, page = 2 }) == true)
assert(panel._detailPageByKey.A == 2 and panel._detailPending.A == true and #requests == 1,
    "page two must replace the requested A page, not append it")
assert(requests[1].key == "A" and requests[1].page == 2 and refreshes == 1,
    "A page request lost correlation or refresh")
assert(panel._detailPageByKey.B == nil and panel._detailPending.B == nil,
    "A page request leaked into B")
details.A.page, details.A.ids = 2, { 3 }
local returnedA = options.pagination.stateOf({ id = "A", count = 1 }, "A")
assert(returnedA.page == 2 and returnedA.totalRows == 31,
    "returned A page did not replace the materialized page")
details.B.page, details.B.ids = 2, { 10 }
local returnedB = options.pagination.stateOf({ id = "B", count = 2 }, "B")
assert(returnedB.page == 2 and returnedB.totalUnits == 2,
    "B page state was not independent")
assert(options.pagination.stateOf({ id = "C", count = 31 }, "C").totalUnits == 31,
    "missing detail must not fabricate child units")
assert(not source:find("scheduleDetail", 1, true), "warehouse pager must not schedule detail from the pager itself")

-- Integration harness: execute the real ContainerInventory mount/receive path.
-- The UI objects are deliberately small, but the production view lifecycle,
-- shared table options, page replacement and payload correlation are real.
local containerSource = read("GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/GS_ContainerInventory.lua")
local mountedInventory, sent = nil, {}
local mockUI = {
    Block = {}, Controls = {}, Table = {},
}
function mockUI.Block.create(spec)
    local block = { x = spec.x, y = spec.y, w = spec.w, h = spec.h, childParent = {}, block = true }
    function block:getContentRect() return { x = self.x + 8, y = self.y + 8, w = self.w - 16, h = self.h - 16 } end
    function block:setBounds(x, y, w, h) self.x, self.y, self.w, self.h = x, y, w, h end
    function block:dispose() self.disposed = true end
    return block
end
function mockUI.Controls.metrics() return { rowHeight = 20 } end
function mockUI.Controls.progress(_, spec)
    local widget = { x = spec.x, y = spec.y, w = spec.w, h = spec.h }
    function widget:setProgress(value) self.progress = value end
    function widget:setX(x) self.x = x end; function widget:setY(y) self.y = y end
    function widget:setWidth(w) self.w = w end; function widget:setHeight(h) self.h = h end
    return widget
end
function mockUI.Controls.button(_, spec)
    local widget = { onClick = spec.onClick }
    function widget:setX(x) self.x = x end; function widget:setY(y) self.y = y end
    function widget:setWidth(w) self.w = w end; function widget:setHeight(h) self.h = h end
    return widget
end
function mockUI.Table.create(spec)
    local table = { options = spec, rows = {} }
    function table:setRows(rows) self.rows = rows end
    function table:getIntrinsicHeight() return 40 end
    function table:setBounds(x, y, w, h) self.x, self.y, self.w, self.h = x, y, w, h end
    function table:dispose() self.disposed = true end
    return table
end
local function fakeRequire(name)
    if name == "GS_UI_Framework" then return mockUI end
    if name == "GS_TerminalUI_Items" then return env.GlobalStorageSiK.TerminalItems end
    if name == "GS_WithdrawClient" then return { sendWithdraw = function() return true end, sendWithdrawBatch = function() return true end } end
    if name == "GS_TerminalDrop" then return { setupPanel = function() end, disposePanel = function() end } end
    if name == "GlobalStorageSiK/UI/CapacityPresentation" then return { fromState = function(_, state) return state end } end
    return {}
end
local mountEnv = setmetatable({
    require = fakeRequire, GlobalStorageSiK = env.GlobalStorageSiK,
    Events = {}, getSpecificPlayer = nil,
}, { __index = _G })
mountEnv.GlobalStorageSiK.Client = { terminalStateByPlayer = {}, cachedTerminalState = { networkId = "n" },
    registerTransientCleanup = function() return true end }
mountEnv.GlobalStorageSiK.Log = { debug = function() end }
mountEnv.GlobalStorageSiK.I18n = { text = function(key) return key end }
mountEnv.GlobalStorageSiK.TerminalDrop = fakeRequire("GS_TerminalDrop")
mountEnv.GlobalStorageSiK.WithdrawClient = fakeRequire("GS_WithdrawClient")
mountEnv.GlobalStorageSiK.NetClient = { sendCommand = function(command, payload)
    sent[#sent + 1] = { command = command, payload = payload }
    if command == "getNodeContents" and payload.page then
        mountedInventory.receive({ networkId = "n", nodeId = "node-A", inventoryRevision = 7,
            detailPage = { rowKey = payload.rowKey, page = payload.page, pageSize = 25,
                totalRows = 31, totalUnits = 31, items = { { id = payload.page } } } })
    end
    return true
end }
env.GlobalStorageSiK.TerminalItems.tableOptions = function(panelArg, terminalArg)
    return itemTableOptions(panelArg, terminalArg)
end
env.GlobalStorageSiK.TerminalItems.requestDetails = function(terminalArg, row, page)
    if terminalArg and terminalArg.requestInventoryDetails then
        return terminalArg:requestInventoryDetails(row, page)
    end
    return false
end
env.GlobalStorageSiK.TerminalItems.presentationModel = function(_, _, rows) return { rows = rows } end
env.GlobalStorageSiK.TerminalItems.columns = function() return {} end
local mountChunk = assert(loadstring(containerSource, "real_ContainerInventory"))
setfenv(mountChunk, mountEnv)
mountedInventory = mountChunk()
local editor = { playerNum = 0 }
local node = { id = "node-A" }
local view = mountedInventory.mount({ width = 420 }, editor, node, { w = 420 })
assert(view and view.table.options.pagination and view.table.options.pagination.external == true
        and view.table.options.pagination.pageSize == options.pagination.pageSize
        and view.table.options.embedded == true,
    "mounted warehouse must pass shared pager options to the real table")
mountedInventory.receive({ networkId = "n", nodeId = "node-A", inventoryRevision = 7,
    catalogRows = { { id = "A", rowKey = "A", count = 31 } }, detailPage = nil })
view.panel._detailPageByKey.A = 1
mountedInventory.receive({ networkId = "n", nodeId = "node-A", inventoryRevision = 7,
    detailPage = { rowKey = "A", page = 1, pageSize = 25, totalRows = 31, totalUnits = 31,
        items = { { id = 1 } } } })
local before = #sent
view.panel._detailPageByKey.A = 2
-- The real receive path must ignore an old page, then accept page two. The
-- NetClient stub delivers page two synchronously from the request call.
view.panel._detailPending.A = true
mountedInventory.receive({ networkId = "n", nodeId = "node-A", inventoryRevision = 7,
    detailPage = { rowKey = "A", page = 1, pageSize = 25, totalRows = 31, totalUnits = 31,
        items = { { id = 99 } } } })
assert(view.panel._detailPages.A == nil or view.panel._detailPages.A.items[1].id ~= 99,
    "out-of-order page response must not replace the requested page")
local sentBeforePage = #sent
local mountedPager = view.table.options.pagination
assert(mountedPager.onPageChange({ parentKey = "A", parent = { id = "A", rowKey = "A" }, page = 2 }) == true)
assert(#sent > sentBeforePage and sent[#sent].payload.page == 2,
    "real mounted view did not issue the requested page")
assert(view.panel._detailPages.A and view.panel._detailPages.A.page == 2
        and view.panel._detailPages.A.items[1].id == 2,
    "synchronous page response did not replace the mounted page")
assert(#sent >= before, "mounted receive/request path lost its initial transport")
view.panel._itemsScrollOffset = 37
view.panel._detailPageByKey.A = 2
mountedInventory.receive({ networkId = "n", nodeId = "node-A", inventoryRevision = 8,
    catalogRows = { { id = "A", rowKey = "A", count = 31 } }, detailPage = nil })
assert(view.panel._detailPageByKey.A == nil or view.panel._detailPageByKey.A == 1,
    "new inventory revision must reset a removed last page to page one")
assert(view.panel._itemsScrollOffset == 37,
    "revision refresh must preserve the warehouse scroll offset")
view:dispose()
return true
