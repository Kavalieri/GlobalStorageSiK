-- Author regression for exact remote detail hover lifecycle and weak probes.
-- Run from GlobalStorageSiK-Repo with Lua 5.1.

package.loaded["GS_NetClient"] = true

local sent = {}
GlobalStorageSiK = {
	NetClient = {
		sendCommand = function(command, args)
			sent[#sent + 1] = { command = command, args = args }
			return true
		end,
	},
}

dofile("GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/GS_RemoteItemDetail.lua")
local Detail = GlobalStorageSiK.RemoteItemDetail
local terminal = { terminalState = { networkId = "net", inventoryRevision = 9 } }
local child = { _gsRowKind = "child", nodeId = "node-1", itemId = 44,
	fullType = "Base.PetrolCan" }
local ownerA = { received = 0 }
function ownerA:onRemoteItemDetail() self.received = self.received + 1 end
local ownerB = { received = 0 }
function ownerB:onRemoteItemDetail() self.received = self.received + 1 end

local detail, loading = Detail.activate(ownerA, child, terminal)
assert(detail == nil and loading == true, "uncached child hover must request exact detail")
assert(#sent == 1 and sent[1].command == "getItemTooltipDetail", "wrong exact-detail command")
assert(sent[1].args.nodeId == "node-1" and sent[1].args.itemId == 44,
	"exact request lost nodeId/itemId")

Detail.activate(ownerB, child, terminal)
assert(#sent == 1, "concurrent hover for the same exact key was not deduplicated")

-- No active consumer: a late response is neither applied nor cached.
Detail.deactivate(ownerA)
Detail.deactivate(ownerB)
local late = {
	ok = true, requestId = sent[1].args.requestId, networkId = "net",
	inventoryRevision = 9, nodeId = "node-1", itemId = 44, condition = 7,
}
assert(Detail.onReceived(late) == false, "cancelled hover accepted a late response")
assert(ownerA.received == 0 and ownerB.received == 0, "late response reached a cancelled owner")

Detail.activate(ownerA, child, terminal)
assert(#sent == 2, "late cancelled response was cached")
local current = {
	ok = true, requestId = sent[2].args.requestId, networkId = "net",
	inventoryRevision = 9, nodeId = "node-1", itemId = 44, condition = 8,
}
assert(Detail.onReceived(current) == true and ownerA.received == 1,
	"active exact response was not applied")
Detail.deactivate(ownerA)
detail, loading = Detail.activate(ownerB, child, terminal)
assert(detail == current and loading == false and #sent == 2,
	"active response did not populate the revision-scoped cache")

-- Probe context is deliberately weak and does not contaminate synthetic item
-- state. If the map retained a strong key, the external weak value would live.
local row = { fullType = "Base.PetrolCan", aggregateAllowed = false }
local probe = {}
Detail.bindProbe(probe, row, current, false)
assert(Detail.contextForProbe(probe).row == row, "probe context was not bound")
local weak = setmetatable({ probe }, { __mode = "v" })
probe = nil
collectgarbage("collect")
collectgarbage("collect")
assert(weak[1] == nil, "probe context holds a strong reference")

-- Static wiring guard: aggregate parents get the ordinary tooltip path; only
-- child rows request exact remote state on hover.
local sourcePath = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/GS_TerminalUI_Items.lua"
local sourceFile = assert(io.open(sourcePath, "rb"))
local source = sourceFile:read("*a")
sourceFile:close()
local tooltipStart = assert(source:find("%-%- Tooltip al pasar", 1))
local tooltipEnd = assert(source:find("row%.onRemoteItemDetail", tooltipStart))
local tooltipBlock = source:sub(tooltipStart, tooltipEnd - 1)
assert(tooltipBlock:find("if data and not data._gsPager and not data._gsStale and self:isMouseOver()", 1, true) ~= nil,
	"aggregated parent is excluded from the tooltip lifecycle")
assert(tooltipBlock:find("aggregateAllowed", 1, true) == nil,
	"tooltip lifecycle still gates aggregate parents")
assert(tooltipBlock:find('if data._gsRowKind == "child" then', 1, true) ~= nil
	and tooltipBlock:find("RemoteItemDetail.activate(self, data, self.terminal)", 1, true) ~= nil,
	"child hover is not wired to exact remote detail")

print("remote_item_detail_lifecycle_regression: OK")
