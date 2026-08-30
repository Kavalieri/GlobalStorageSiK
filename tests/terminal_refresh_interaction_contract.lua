-- Binding source contract for interaction-safe Warehouse refresh.
-- Runtime recycling/hit-testing remains a PZ check, but the required state and
-- defer/flush paths must be explicit and observable in author code.

local ROOT = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/"
local SERVER_ROOT = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/server/"
local function read(name)
	local handle = assert(io.open(ROOT .. name, "rb"), name)
	local value = handle:read("*a")
	handle:close()
	return value
end
local function contains(source, needle, label)
	assert(source:find(needle, 1, true), label .. ": " .. needle)
end
local function excludes(source, needle, label)
	assert(not source:find(needle, 1, true), label .. ": " .. needle)
end
local function section(source, firstMarker, nextMarker)
	local first = assert(source:find(firstMarker, 1, true), firstMarker)
	local last = assert(source:find(nextMarker, first + #firstMarker, true), nextMarker)
	return source:sub(first, last - 1)
end

local items = read("GS_TerminalUI_Items.lua")
local drag = read("GS_TerminalWithdrawDrag.lua")
local terminal = read("GS_TerminalUI.lua")
local serverHandle = assert(io.open(SERVER_ROOT .. "GS_Server.lua", "rb"), "GS_Server.lua")
local server = serverHandle:read("*a")
serverHandle:close()

-- Stable semantic state survives new row tables and inventory revisions.
contains(items, "panel._expandedKeys = panel._expandedKeys or {}", "expansion state missing")
contains(items, "panel._selectedKeys = panel._selectedKeys or {}", "selection state missing")
contains(items, "panel._itemsScrollOffset", "scroll offset missing")
contains(items, "panel._detailPageByKey = panel._detailPageByKey or {}", "detail page missing")
contains(items, "panel._detailPending = panel._detailPending or {}", "detail pending state missing")
contains(terminal, "state.searchQuery", "search query is not restored")
contains(terminal, "_mainCategoryFilterKey", "Family filter state missing")
contains(terminal, "_subCategoryFilterKey", "Group filter state missing")
contains(terminal, "_leafCategoryFilterKey", "Detail filter state missing")

-- A refresh cannot recycle the row owning click/drag/tooltip. It is queued
-- once and flushed after cancel/drop through the same explicit API.
contains(items, "function GlobalStorageSiK.TerminalItems.deferRefresh",
	"authoritative deferred-refresh API missing")
contains(items, "function GlobalStorageSiK.TerminalItems.flushDeferredRefresh",
	"deferred refresh cannot be applied after interaction")
contains(items, "TerminalWithdrawDrag.isActive()", "refresh ignores active drag")
contains(items, "_deferredRefresh", "coalesced refresh slot missing")
contains(items, "function GlobalStorageSiK.TerminalItems.onInteractionFinished",
	"interaction completion bridge missing")
contains(drag, "TerminalItems.onInteractionFinished", "drag cleanup does not release queued refresh")
local refresh = section(items, "function GlobalStorageSiK.TerminalItems.refresh(panel, terminal, items)",
	"function GlobalStorageSiK.TerminalItems.syncLayout(panel, terminal)")
excludes(refresh, "panel._expandedKeys = {}", "refresh resets all expansions")
excludes(refresh, "panel._selectedKeys = {}", "refresh resets selection")

-- An old detail page remains a visible reference while the current revision
-- is requested, but every stale child/pager is inert until that response.
contains(items, "local displayable = detailPage and detailPage.page == wantedPage",
	"old detail page is discarded instead of remaining visible")
contains(items,
	"local pageStale = tonumber(detailPage.inventoryRevision or -1) ~= tonumber(revision)",
	"detail page is not compared with the current inventory revision")
contains(items, "child._gsStale = pageStale", "stale child is not marked")
contains(items, "hasNext = detailPage.hasNext, _gsStale = pageStale",
	"stale pager is not marked")
contains(items, "stale = data._gsStale == true", "stale state is not passed to rendering")
contains(items, "local alpha = descriptor.stale and 0.45 or 1",
	"stale visual reference is not attenuated")
contains(items, "if row and not row._gsStale and row.fullType",
	"stale rows can enter a drag payload")
contains(items, "not data._gsPager and not data._gsStale and self:isMouseOver()",
	"stale row can activate its remote tooltip")

local remoteCallback = section(items, "row.onRemoteItemDetail = function", "row.onMouseDown = function")
contains(remoteCallback, "self.itemData._gsStale", "late remote detail can bind to a stale row")
for _, handler in ipairs({ "row.onMouseDown = function", "row.onMouseUp = function",
	"row.onMouseDoubleClick = function", "row.onRightMouseUp = function" }) do
	local at = assert(items:find(handler, 1, true), "missing row handler: " .. handler)
	local guard = assert(items:find("self.itemData._gsStale", at, true),
		"stale guard missing after " .. handler)
	assert(guard - at < 180, "stale guard is too late to protect " .. handler)
end

-- Server snapshots are coherent by revision. A scan that crosses a mutation
-- is failed and retried after the coalesced quiet period, never completed by
-- combining directed deltas with an unstable full capture.
local schedule = section(server, "local function scheduleSnapshotSync", "local function flushPendingSnapshotSync")
contains(schedule, "pending.dueMs = now + SNAPSHOT_QUIET_MS",
	"new mutations do not restart the quiet period")
contains(schedule, "pending.revision = math.max", "snapshot retry loses the latest revision")
local flush = section(server, "local function flushPendingSnapshotSync", "function GlobalStorageSiK.Server.markInventoryDirty")
contains(flush, "if now >= pending.dueMs or now >= pending.forceMs then",
	"snapshot retry does not wait for its coalesced deadline")
contains(flush, "GlobalStorageSiK.ZoneScanJob.start", "quiet queue never starts a fresh capture")
local dirty = section(server, "function GlobalStorageSiK.Server.markInventoryDirty", "local function terminalWatcherKey")
excludes(dirty, "ZoneScanJob.start", "inventory delta starts an immediate full capture")
local completion = section(server, "function GlobalStorageSiK.Server.onNetworkScanComplete",
	"function GlobalStorageSiK.Server.onNetworkScanFailed")
local discardCondition =
	"if summary._stagedDiscarded == true or currentRevision ~= startRevision then"
contains(completion, discardCondition,
	"server does not reject staged discard and revision mismatch through one path")
local discardedAt = assert(completion:find("summary._stagedDiscarded == true", 1, true),
	"server ignores ZoneScan staging discard")
local revisionAt = assert(completion:find("currentRevision ~= startRevision", 1, true),
	"server accepts a capture spanning multiple revisions")
local genericFailedAt = assert(completion:find('if summary._terminalState == "FAILED" then', 1, true),
	"generic scan failure branch missing")
assert(discardedAt < genericFailedAt and revisionAt < genericFailedAt,
	"generic FAILED branch swallows staged/revision discard before retry")
contains(completion, "scheduleSnapshotSync(networkId, retryPlayer, currentRevision)",
	"unstable capture is not queued for a fresh retry")
contains(completion, 'overrideTerminalState(networkId, "FAILED", "snapshot_stale")',
	"unstable capture is not explicitly rejected")
local unstable = section(completion, discardCondition,
	"-- Un scan estable")
contains(unstable, "return", "unstable capture can fall through to COMPLETED")
excludes(unstable, '"COMPLETED"', "unstable directed delta is accepted as complete")
excludes(unstable, '"complete"', "unstable directed delta reports complete")

print("terminal_refresh_interaction_contract: OK")
