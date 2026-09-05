-- Focused contract for exact post-transfer snapshot capture.
-- The harness deliberately treats nil/pcall failure as false and verifies that
-- a failed capture cannot masquerade as a fresh snapshot.

local ROOT = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/"
local function read(path)
	local h = assert(io.open(ROOT .. path, "rb"), path)
	local v = h:read("*a"); h:close(); return v
end
local function contains(source, needle, label)
	assert(source:find(needle, 1, true), label .. ": " .. needle)
end

for _, name in ipairs({ "GS_Network", "GS_Router", "GS_Zones", "GS_ItemSnapshot",
	"GS_ZoneRefresh", "GS_NativeProduct", "GS_CategoryResolution", "GS_Permissions" }) do
	package.preload[name] = function() return {} end
end
GlobalStorageSiK = {
	isAuthoritative = function() return true end,
	ItemSnapshot = { fromContainer = function(container)
		if container.mode == "error" then error("capture failed") end
		if container.mode == "nil" then return nil end
		if container.mode == "malformed" then return "not-a-snapshot" end
		return { captured = true }
	end },
}
dofile(ROOT .. "shared/GS_Index.lua")

local entry = { itemSnapshot = { capturedAt = 17 } }
local function capture(mode)
	local before = entry.itemSnapshot
	local ok = GlobalStorageSiK.Index.syncNodeSnapshot(entry, { mode = mode })
	local expected = mode == "ok" and GlobalStorageSiK.isAuthoritative()
	assert(ok == expected, "capture result must be strict boolean: mode=" .. mode .. " value=" .. tostring(ok))
	if mode ~= "ok" then
		assert(entry.itemSnapshot == before,
			"failed capture replaced the prior snapshot")
	end
end
capture("ok")
entry.itemSnapshot = { capturedAt = 17 }
capture("nil")
capture("error")
capture("malformed")
GlobalStorageSiK.isAuthoritative = function() return false end
capture("ok")

local transfer = read("shared/GS_Transfer.lua")
local server = read("server/GS_Server.lua")
contains(transfer, "return true, nil, snapshotsUpdated",
	"deposit must expose its capture result")
contains(transfer, "return true, \"partial:\" .. tostring(reason), moved, movedItemIds, sourceNodeIds, snapshotsUpdated",
	"partial withdrawal must expose its capture result")
contains(transfer, "snapshotsUpdated = false",
	"withdrawal must fail closed when any capture fails")
	contains(server, "snapshotsUpdated = options.snapshotsUpdated == true",
		"server transfer options must carry capture state")
	contains(server, "scheduleSnapshot = options.snapshotsUpdated ~= true",
	"server must not schedule a rescan when all exact captures succeeded")

print("snapshot_capture_failure_regression: OK")
