local sourcePath = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/GS_IdentityHello.lua"

local sent = 0
GlobalStorageSiK = {
	MOD_ID = "GlobalStorageSiK",
	NetClient = { sendCommand = function() sent = sent + 1; return true end },
	Log = { debug = function() end, error = function() end },
}
package.preload["GS_NetClient"] = function() return GlobalStorageSiK.NetClient end

local createPlayer, tick
Events = {
	OnCreatePlayer = { Add = function(callback) createPlayer = callback end },
	OnTick = { Add = function(callback) tick = callback end },
	OnServerCommand = { Add = function() end },
}
function isClient() return false end

dofile(sourcePath)
assert(type(createPlayer) == "function", "identity hello registers player lifecycle")
assert(type(tick) == "function", "identity hello registers retry lifecycle")
createPlayer()
for _ = 1, 250 do tick() end
assert(sent == 0, "SP real must not send or retry the MP identity handshake")

io.write("PASS identity hello is inert in SP real\n")
return true
