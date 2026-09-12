-- Lifecycle harness for real GS_TerminalLoading and extracted real API
-- functions. UI, Events and native controls are boundary doubles only.
local function check(value, message) if not value then error(message, 2) end end
local CLIENT = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/"
GlobalStorageSiK = {I18n={text=function(key) return key end}, Log={debug=function() end, error=function() end}, Client={terminalOpenSeqByPlayer={[0]=1,[1]=1}}}
ISUIElement = {setEnabled=function(widget, value) widget.enabled=value end}
getTimestampMs = function() return 1000 end
resolveShellRect = function() return {x=10,y=20,w=720,h=500} end
package.preload["GS_TerminalLoading"] = function() return dofile(CLIENT .. "GS_TerminalLoading.lua") end
local Loading = assert(require "GS_TerminalLoading")
_G.Loading = Loading

local source = assert(io.open(CLIENT .. "GS_TerminalUI_Api.lua", "r")):read("*a")
local function extract(startMarker, endMarker)
  local start = assert(source:find(startMarker, 1, true), startMarker)
  local finish = assert(source:find(endMarker, start, true), endMarker)
  return source:sub(start, finish - 1)
end
local showPending = extract("function GlobalStorageSiK.TerminalUI.showPending", "\n\nfunction GlobalStorageSiK.TerminalUI.dispatchOpening")
local dispatchOpening = extract("function GlobalStorageSiK.TerminalUI.dispatchOpening", "\n\nfunction GlobalStorageSiK.TerminalUI.catalogProgress")
local catalogProgress = extract("function GlobalStorageSiK.TerminalUI.catalogProgress", "\n\n-- Called by the existing access watcher")
local applySource = extract("local function applyTerminalState", "\n\n--- Abre o refresca la ventana principal")

local players = {[0]={getPlayerNum=function() return 0 end}, [1]={getPlayerNum=function() return 1 end}}
local sent, refreshed, failures = {}, {}, 0
local events = {adds={}, removes={}}
Events = {OnTick={Add=function(fn) events.adds[#events.adds+1]=fn end, Remove=function(fn) events.removes[#events.removes+1]=fn end}}
local function newUi(x, y, w, h, n)
  local bodyChild = {enabled=true, children={}}
  local disabledChild = {enabled=false, children={}}
  local ui = {x=x,y=y,w=w,h=h,playerNum=n,visible=false, navigationContainer={panel={children={body=bodyChild,disabled=disabledChild}}},
    terminalState={playerNum=n}, _gsBuiltTabs={}}
  function ui:initialise() self.initialised=true end
  function ui:show() self.visible=true end
  function ui:onClose() self.closed=true; self.visible=false; GlobalStorageSiK.TerminalUI.instances[self.playerNum]=nil end
  function ui:syncHeaderChrome() self.synced=(self.synced or 0)+1 end
  function ui:refreshFromState(value) refreshed[#refreshed+1]=value end
  return ui
end
GS_TerminalUI = {new=newUi}
GlobalStorageSiK.NetClient = {getPlayer=function(n) return players[n] end}
GlobalStorageSiK.TerminalUI = {instances={}, getInstanceForPlayer=function(n) return GlobalStorageSiK.TerminalUI.instances[n] end,
  setInstanceForPlayer=function(n, ui) GlobalStorageSiK.TerminalUI.instances[n]=ui end,
  showCatalogFailure=function() failures=failures+1 end,
  onRemoteOpenResult=function() end}
GlobalStorageSiK.TerminalItems = {disposeSection=function() end}
GlobalStorageSiK.Client.getInventoryCatalogPreview = function() return nil end
assert(loadstring(showPending))(); assert(loadstring(dispatchOpening))(); assert(loadstring(catalogProgress))()
local applyTerminalState = assert(loadstring("local DEFER_REFRESH_ITEM_COUNT=150\n" .. applySource
  .. "\nreturn applyTerminalState"))()
local UI = GlobalStorageSiK.TerminalUI

-- Shell is visible synchronously; opening transport is deferred to OnTick.
local ui0 = UI.showPending(0, 1)
check(ui0 and ui0.visible == true and ui0._gsCatalogLoad ~= nil, "pending shell was not visible immediately")
local dispatched = 0
check(UI.dispatchOpening(players[0], 1, function() dispatched=dispatched+1; return true end), "dispatch was not queued")
check(dispatched == 0 and #events.adds == 1, "opening dispatched before OnTick")
events.adds[1](); check(dispatched == 1 and #events.removes == 1, "OnTick did not dispatch once")

-- Closing/removing the window cancels a queued send through the instance fence.
local ui1 = UI.showPending(1, 1)
UI.dispatchOpening(players[1], 1, function() dispatched=dispatched+1; return true end)
ui1:onClose(); UI.setInstanceForPlayer(1, nil); events.adds[#events.adds]()
check(dispatched == 1, "closed window dispatched stale opening")

-- ACK progress is determinate-independent and leaves the loading slot alive.
local progressUi = UI.showPending(0, 1)
UI.catalogProgress({playerNum=0,openSeq=1,networkId="net",catalogScope="all"}, 0, nil)
check(progressUi._gsCatalogLoad and progressUi._gsCatalogLoad.phase == "loading",
  "ACK progress did not retain loading state")
check(progressUi.visible == true, "ACK progress hid pending shell")
UI.catalogProgress({playerNum=0,openSeq=999,networkId="net",catalogScope="all"}, 1, 2)
check(progressUi._gsCatalogLoad.done == 0, "stale progress changed active window")

-- Loading unlock restores original native enabled state, including disabled
-- descendants, while Close remains outside the locked navigation body.
local close = {enabled=true}; progressUi.closeButton=close
Loading.lock(progressUi)
local body = progressUi.navigationContainer.panel.children.body
local disabled = progressUi.navigationContainer.panel.children.disabled
check(body.enabled == false and disabled.enabled == false and close.enabled == true,
  "native body descendants or Close lock boundary incorrect")
Loading.unlock(progressUi)
check(body.enabled == true and disabled.enabled == false and close.enabled == true,
  "unlock did not restore native enabled states")
local expected = progressUi._gsCatalogLoad
Loading.finish(progressUi, expected)
check(progressUi._gsCatalogLoad == nil and #refreshed == 0 and failures == 0,
  "finish performed an unexpected refresh/failure")

-- Large state application is deferred and captures its loading generation.
local deferredUi = UI.showPending(0, 2)
GlobalStorageSiK.Client.terminalOpenSeqByPlayer[0] = 2
Loading.set(deferredUi, "loading", 2, 0, 4)
local large = {playerNum=0, openSeq=2, networkId="net", catalogScope="all", items={}}
for i = 1, 151 do large.items[i] = {id=i} end
local refreshBefore = #refreshed
applyTerminalState(deferredUi, large, true)
check(deferredUi._gsPendingTerminalLoad ~= nil and #refreshed == refreshBefore,
  "large state refreshed before deferred tick")
local oldLoad = deferredUi._gsPendingTerminalLoad
UI.catalogProgress({playerNum=0,openSeq=2,networkId="net",catalogScope="all"}, 1, 4)
check(deferredUi._gsCatalogLoad ~= oldLoad, "new progress did not replace loading generation")
local staleRefreshCallback = events.adds[#events.adds]
staleRefreshCallback()
check(#refreshed == refreshBefore and deferredUi._gsPendingTerminalState == nil,
  "stale deferred refresh changed the new loading state")

-- A current deferred refresh runs only after the tick and then finishes.
local currentLoad = deferredUi._gsCatalogLoad
check(deferredUi._gsTerminalRefreshQueued == nil, "stale deferred callback left queued flag")
applyTerminalState(deferredUi, {playerNum=0,openSeq=2,networkId="net",catalogScope="all",items={{id="ok"}}}, false)
check(#refreshed == refreshBefore + 1 and deferredUi._gsCatalogLoad == nil,
  "current deferred refresh did not finish after refresh")

-- Refresh errors close the current window and report the catalog failure.
local errorUi = UI.showPending(1, 3)
GlobalStorageSiK.Client.terminalOpenSeqByPlayer[1] = 3
Loading.set(errorUi, "loading", 3, 0, 1)
local originalRefresh = errorUi.refreshFromState
errorUi.refreshFromState = function() error("refresh-failure") end
local failureBefore = failures
applyTerminalState(errorUi, {playerNum=1,openSeq=3,networkId="net-1",catalogScope="all",items={{id="bad"}}}, false)
check(failures == failureBefore + 1 and errorUi.closed == true,
  "refresh failure did not close/report current window")
errorUi.refreshFromState = originalRefresh

print("catalog_loading_lifecycle_harness: PASS shell/deferred dispatch/cancel/ACK-progress/stale-fence/native-lock/apply-refresh-error")
