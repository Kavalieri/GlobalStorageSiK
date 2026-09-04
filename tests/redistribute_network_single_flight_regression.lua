-- Regression: Auto Sort admits one active launch per network, regardless of
-- which player requests it, while a distinct network remains independent.

local sourcePath = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/server/GS_RedistributeJob.lua"

GlobalStorageSiK = {
	Log = { debug = function() end, detail = function() end, error = function() end },
	OperationPacing = {
		resolve = function() return { schedulerDelayMs = 100 } end,
		describe = function() return "test" end,
	},
}

for _, name in ipairs({
	"GS_Redistribute", "GS_PlayerUtils", "GS_TerminalAccess",
	"GS_TransferLock", "GS_InventorySync", "GS_OperationPacing",
}) do
	package.preload[name] = function() return true end
end

local installed = 0
Events = {
	OnTick = {
		Add = function() installed = installed + 1 end,
		Remove = function() installed = installed - 1 end,
	},
}
function getTimestampMs() return 1234 end

local function player(name)
	return { getUsername = function() return name end }
end

dofile(sourcePath)
local Jobs = GlobalStorageSiK.RedistributeJob

assert(Jobs.start(player("Kava"), "network-a") == true,
	"first player must acquire network-a Auto Sort")
assert(Jobs.start(player("Sarini"), "network-a") == false,
	"second player must not launch a concurrent Auto Sort in the same network")
assert(Jobs.isActive("network-a") == true,
	"refused duplicate must not cancel the original network job")
assert(Jobs.start(player("Sarini"), "network-b") == true,
	"a separate network may own its own incremental job")
assert(Jobs.isActive("network-b") == true,
	"network-b job was not registered")
assert(installed == 1,
	"all networks must share the single global incremental scheduler")

io.write("PASS Auto Sort is single-flight per network and globally scheduled\n")
return true
