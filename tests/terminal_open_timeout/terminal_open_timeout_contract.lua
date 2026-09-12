-- R151-016 timeout contract. Extracts the real API block including its
-- private OPEN_TIMEOUT_MS/deadline state; transport and PZ are doubled.
local function exists(p)local f=io.open(p,"r");if f then f:close();return true end end
local PREFIX=exists("GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/GS_TerminalUI_Api.lua") and "" or "GlobalStorageSiK-Repo/"
local path=PREFIX.."GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/GS_TerminalUI_Api.lua"
local source=assert(io.open(path,"r")):read("*a")
local function at(s)return assert(string.find(source,s,1,true),s)end
local start=at("local OPEN_TIMEOUT_MS = 10000")
local players={};for n=0,3 do local p={num=n};function p:getPlayerNum()return self.num end;players[n]=p end
local sent={};local guardEnsures=0;local callbacks={};local now=1000;local syncRemote=false
GlobalStorageSiK={Client={terminalOpenSeqByPlayer={},pendingTerminalOpenByPlayer={},terminalOpenSeq=0,pendingTerminalOpen=false},TerminalUI={},
 PlayerUtils={resolve=function(v)if type(v)=="table" then return v end;return players[tonumber(v)or 0] end},
 TerminalAccessGuard={ensure=function()guardEnsures=guardEnsures+1 end},
 TerminalAccess={trustServerForOpen=function()return true end,buildHintFromObject=function(_,o)return o end,enrichCommandPayload=function(_,p)return p end},
 NetClient={getPlayer=function(n)return players[tonumber(n)or 0]end,sendCommand=function(n,p,pl)sent[#sent+1]={name=n,payload=p,player=pl};return true end,sendNetworkCommand=function(n,id,p,pl)sent[#sent+1]={name=n,networkId=id,payload=p,player=pl};if syncRemote then GlobalStorageSiK.TerminalUI.onRemoteOpenResult({playerNum=pl:getPlayerNum(),openSeq=p.openSeq},true)end;return true end},
 UIFeedback={halo=function()end},I18n={text=function(k)return k end},Debug={log=function()end},Log={error=function()end,debug=function()end}}
local env=setmetatable({GlobalStorageSiK=GlobalStorageSiK,getTimestampMs=function()return now end,getPlayer=function()return players[0]end,
 UI={Viewport={resolve=function()return{}end},Window={resolveBounds=function()return{x=0,y=0,w=720,h=480}end}}}, {__index=_G})
local chunk=assert(loadstring(string.sub(source,start),"GS_TerminalUI_Api.timeout"));setfenv(chunk,env);chunk()
local UI=GlobalStorageSiK.TerminalUI
local notices={}
package.preload["GS_CatalogFeedback"]=function()return {
 show=function(n,reason,confirmed)notices[#notices+1]={playerNum=n,reason=reason,confirmed=confirmed}end,
 clear=function()end,
}end
UI.instances={}
-- Edge shell double: the real timeout/cancel paths close the visible shell.
-- Its close hook exercises the public cancellation path, including the
-- sequence fence; no production constructor or UI implementation is copied.
function UI.getInstanceForPlayer(n)return UI.instances[n] end
function UI.setInstanceForPlayer(n,ui)UI.instances[n]=ui end
Loading={lock=function(ui)ui.locked=true end,unlock=function(ui)ui.locked=false end,set=function(ui,phase,seq)ui.phase=phase;ui.phaseSeq=seq end}
GS_TerminalUI={}
function GS_TerminalUI:new(x,y,w,h,n)
 local ui={playerNum=n,x=x,y=y,w=w,h=h,closed=false}
 function ui:initialise()self.initialised=true end
 function ui:show()self.visible=true end
 function ui:syncHeaderChrome()end
 function ui:onClose()
  if self.closed then return end
  self.closed=true;self.visible=false
  UI.cancelPendingOpen(self.playerNum)
  if UI.instances[self.playerNum]==self then UI.instances[self.playerNum]=nil end
 end
 return ui
end
-- Keep this contract focused on cleanup: the feedback double records the
-- failure while closing the shell, without recreating a failure presentation.
function UI.showCatalogFailure(n,reason,confirmed)
 local ui=UI.getInstanceForPlayer(n)
 if ui and ui.onClose then ui:onClose() end
 notices[#notices+1]={playerNum=n,reason=reason,confirmed=confirmed}
end
local function event()
    local t={adds={},removes={}}
    t.Add=function(f)t.adds[#t.adds+1]=f end;t.Remove=function(f)t.removes[#t.removes+1]=f end
    return t
end
Events={OnPlayerUpdate=event(),OnTick=event(),OnContainerUpdate=event(),OnClothingUpdated=event()}
package.preload["GS_Sandbox"]=function()return{}end;package.preload["GS_Network"]=function()return{}end
package.preload["GS_NetClient"]=function()return GlobalStorageSiK.NetClient end;package.preload["GS_TerminalAccess"]=function()return GlobalStorageSiK.TerminalAccess end
package.preload["GS_TerminalUI_Api"]=function()return UI end
assert(dofile(PREFIX.."GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/GS_TerminalAccessGuard.lua")==nil)
local realGuard=GlobalStorageSiK.TerminalAccessGuard
local function check(v,m)if not v then error(m,2)end end
local function eq(a,b,m)check(a==b,(m or "value").." got="..tostring(a).." expected="..tostring(b))end
local function physical(n,id)local p=UI.requestOpenAt(n,{networkId=id,x=10,y=20,z=0});return p end
local function reset()GlobalStorageSiK.Client.terminalOpenSeqByPlayer={};GlobalStorageSiK.Client.pendingTerminalOpenByPlayer={};GlobalStorageSiK.Client.terminalOpenSeq=0;GlobalStorageSiK.Client.pendingTerminalOpen=false;GlobalStorageSiK.TerminalUI._remoteOpenRequests={};UI.instances={};sent={};callbacks={};now=1000;syncRemote=false end
-- Lost physical ACK expires at ten seconds and fences the sequence first.
reset();local seq=physical(0,"physical");eq(seq,1,"physical sequence");check(GlobalStorageSiK.Client.pendingTerminalOpenByPlayer[0],"physical pending missing");check(realGuard._installed and #Events.OnPlayerUpdate.adds==1,"real Guard did not retain pending watcher");UI.expirePendingOpens(10999);check(GlobalStorageSiK.Client.pendingTerminalOpenByPlayer[0],"early expiry");UI.expirePendingOpens(11000);eq(GlobalStorageSiK.Client.pendingTerminalOpenByPlayer[0],nil,"physical pending not expired");eq(GlobalStorageSiK.Client.terminalOpenSeqByPlayer[0],3,"shell close fenced sequence after expiry");eq(sent[#sent].name,"closeTerminal","physical timeout did not release watcher");eq(sent[#sent].player,players[0],"physical timeout closed wrong player");eq(sent[#sent].payload.targetOpenSeq,seq,"physical timeout target drifted");realGuard.onTick(players[0]);check(not realGuard._installed and #Events.OnPlayerUpdate.removes==1,"real Guard did not detach after pending ended")
-- Remote timeout calls its callback exactly once with a stable reason.
reset();local remote=UI.requestOpenNetwork("net",1,function(ok,reason)callbacks[#callbacks+1]={ok=ok,reason=reason}end);eq(remote,1,"remote sequence");UI.expirePendingOpens(11000);eq(#callbacks,1,"remote timeout callback count");eq(callbacks[1].ok,false,"remote timeout accepted");eq(callbacks[1].reason,"open_timeout","remote timeout reason");eq(sent[#sent].name,"closeTerminal","remote timeout did not release watcher");eq(sent[#sent].player,players[1],"remote timeout closed wrong player");eq(sent[#sent].payload.targetOpenSeq,remote,"remote timeout target drifted");UI.expirePendingOpens(21000);eq(#callbacks,1,"remote callback repeated")
-- Timeout cleanup invokes the callback after the shell/request cleanup, so a
-- callback may immediately start the next request without an explicit cancel.
reset();local reopened=nil;local firstTimeout=UI.requestOpenNetwork("first",1,function(ok,reason,payload)
 callbacks[#callbacks+1]={ok=ok,reason=reason,payload=payload}
 reopened=UI.requestOpenNetwork("second",1,function(ok2,reason2,payload2)
  callbacks[#callbacks+1]={ok=ok2,reason=reason2,payload=payload2}
 end)
end);eq(firstTimeout,1,"reopen first sequence");local firstShell=UI.getInstanceForPlayer(1);check(firstShell and firstShell.visible,"timeout shell missing");UI.expirePendingOpens(11000)
eq(#callbacks,1,"timeout callback did not run once before reopen");eq(callbacks[1].reason,"open_timeout","reopen timeout reason drifted");eq(reopened,4,"callback reopen sequence was not fenced after shell cleanup");check(UI.getInstanceForPlayer(1) and not UI.getInstanceForPlayer(1).closed,"callback reopen shell missing");UI.expirePendingOpens(21000);eq(#callbacks,2,"reopened timeout callback repeated");eq(callbacks[2].payload.openSeq,reopened,"reopened callback sequence drifted")
-- A synchronous API ACK clears pending before any deadline can fire. The
-- transport is mocked, so this is an API correlation check rather than SP/PZ.
reset();syncRemote=true;local sp=UI.requestOpenNetwork("sp",0,function(ok)callbacks[#callbacks+1]=ok end);eq(sp,1,"synchronous sequence");local dispatch=Events.OnTick.adds[#Events.OnTick.adds];check(dispatch,"synchronous dispatch was not queued");dispatch();eq(callbacks[1],true,"synchronous ACK rejected");eq(GlobalStorageSiK.Client.pendingTerminalOpenByPlayer[0],nil,"synchronous ACK left pending");UI.expirePendingOpens(20000);eq(GlobalStorageSiK.Client.terminalOpenSeqByPlayer[0],sp,"synchronous ACK still expired")
-- A newer opening owns the slot; an older remote request cannot expire it.
reset();now=1000;local old=UI.requestOpenNetwork("old",1,function()callbacks[#callbacks+1]="old"end);now=2000;local newer=physical(1,"new");eq(old,1,"old remote id");eq(newer,3,"new physical sequence after shell close fence");UI.expirePendingOpens(11000);eq(#callbacks,0,"older request canceled newer opening");check(GlobalStorageSiK.Client.pendingTerminalOpenByPlayer[1],"new opening lost pending")
-- Four players remain independent and a backwards clock rebases deadlines.
reset();for n=0,3 do check(physical(n,"p"..n)==1,"four-player sequence")end;for n=0,3 do check(GlobalStorageSiK.Client.pendingTerminalOpenByPlayer[n],"player pending isolation")end;UI.expirePendingOpens(500);for n=0,3 do check(GlobalStorageSiK.Client.pendingTerminalOpenByPlayer[n],"clock rollback expired player")end;UI.expirePendingOpens(10499);for n=0,3 do check(GlobalStorageSiK.Client.pendingTerminalOpenByPlayer[n],"rebased deadline expired early")end;UI.expirePendingOpens(10500);for n=0,3 do eq(GlobalStorageSiK.Client.pendingTerminalOpenByPlayer[n],nil,"player deadline not expired")end
-- Explicit cancellation is not reported as open_timeout.
reset();local cancelled=UI.requestOpenNetwork("cancel",2,function(ok,reason)callbacks[#callbacks+1]={ok,reason}end);UI.cancelPendingOpen(2);UI.expirePendingOpens(20000);eq(#callbacks,0,"cancel produced timeout callback");eq(cancelled,1,"cancel sequence")
-- Cancelling the current remote request fences its slot and closes only its
-- own server watcher once.
reset();local current=UI.requestOpenNetwork("current",2,function()callbacks[#callbacks+1]="unexpected"end);check(UI._remoteOpenRequests[2] and UI._remoteOpenRequests[2].requestId==current,"current remote was not stored");UI.cancelOpenNetworkRequest(current,2);eq(current,1,"current remote sequence");eq(GlobalStorageSiK.Client.pendingTerminalOpenByPlayer[2],nil,"current remote remained pending");eq(GlobalStorageSiK.Client.terminalOpenSeqByPlayer[2],3,"current cancellation fenced sequence through shell close");eq(sent[#sent].name,"closeTerminal","current cancellation did not close watcher");eq(sent[#sent].player,players[2],"current cancellation closed wrong player");eq(sent[#sent].payload.targetOpenSeq,current,"current cancellation target drifted");UI.expirePendingOpens(20000);eq(#callbacks,0,"current cancellation produced timeout callback")
-- Cancelling the exact remote sequence closes only its shell. A different
-- player's pending sequence and shell remain untouched.
reset();local cancelSeq=UI.requestOpenNetwork("cancel-shell",2,function()callbacks[#callbacks+1]="cancelled"end);local cancelShell=UI.getInstanceForPlayer(2);check(cancelShell and cancelShell.visible,"cancel shell missing");local otherSeq=UI.requestOpenNetwork("other-player",3,function()callbacks[#callbacks+1]="other"end);local otherShell=UI.getInstanceForPlayer(3);check(otherShell and otherShell.visible,"other shell missing");UI.cancelOpenNetworkRequest(cancelSeq,2);check(cancelShell.closed and not cancelShell.visible,"remote cancel left shell visible");eq(GlobalStorageSiK.Client.pendingTerminalOpenByPlayer[2],nil,"remote cancel left pending player");eq(GlobalStorageSiK.Client.terminalOpenSeqByPlayer[3],otherSeq,"remote cancel touched other sequence");check(GlobalStorageSiK.Client.pendingTerminalOpenByPlayer[3],"remote cancel cleared other pending");check(UI.getInstanceForPlayer(3)==otherShell and not otherShell.closed,"remote cancel closed other shell")
-- An older remote request must not close a newer physical open of the same
-- player or disturb its deadline/pending state.
reset();local oldRemote=UI.requestOpenNetwork("old",1,function()callbacks[#callbacks+1]="old"end);local newPhysical=physical(1,"physical-new");local beforeClose=#sent;UI.cancelOpenNetworkRequest(oldRemote,1);eq(oldRemote,1,"old remote sequence");eq(newPhysical,3,"new physical sequence after shell close fence");check(GlobalStorageSiK.Client.pendingTerminalOpenByPlayer[1],"older cancellation cleared newer physical open");for i=beforeClose+1,#sent do check(sent[i].name~="closeTerminal","older cancellation closed newer physical open")end;check(UI.onRemoteOpenResult({playerNum=1,openSeq=oldRemote},false)==false,"older remote ACK handled after cancellation")
check(realGuard.onTick and realGuard.ensure,"real Guard loaded for pending-open lifecycle")
-- Access ACK stops only its deadline; inventory completion still owns opening.
reset();local confirmedSeq=physical(0,"confirmed")
check(UI.confirmCatalogAccess({playerNum=0,openSeq=confirmedSeq}),"valid access ACK rejected")
UI.expirePendingOpens(90000)
check(GlobalStorageSiK.Client.pendingTerminalOpenByPlayer[0],"access ACK cleared catalog pending")
eq(GlobalStorageSiK.Client.terminalOpenSeqByPlayer[0],confirmedSeq,"confirmed opening expired")
check(not UI.confirmCatalogAccess({playerNum=0,openSeq=confirmedSeq+1}),"foreign ACK accepted")
check(#notices>0 and notices[1].reason=="open_timeout" and notices[1].confirmed==false,"timeout notice not specific")
print("terminal_open_timeout_contract: PASS physical=1 remote=1 sp=1 race=1 players=4 rollback=1 cancel=1")
