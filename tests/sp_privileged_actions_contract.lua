-- Regression contract: SP has no network-role hierarchy to enforce.

local path = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/server/GS_Server.lua"
local handle = assert(io.open(path, "rb"), path)
local source = handle:read("*a")
handle:close()

local function section(firstMarker, nextMarker)
	local first = assert(source:find(firstMarker, 1, true), firstMarker)
	local last = assert(source:find(nextMarker, first + #firstMarker, true), nextMarker)
	return source:sub(first, last - 1)
end

local admin = section("local function requireAdminAccess", "local function requireOwnerAccess")
assert(admin:find("if not GlobalStorageSiK.Permissions.shouldEnforce() then", 1, true),
	"admin gate must accept authoritative SP after member access")
assert(admin:find("return true", 1, true), "admin SP branch must grant access")

local owner = section("local function requireOwnerAccess", "local function requireServerMod")
assert(owner:find("if not GlobalStorageSiK.Permissions.shouldEnforce() then", 1, true),
	"owner gate must accept authoritative SP after member access")
assert(owner:find("return true", 1, true), "owner SP branch must grant access")

print("sp_privileged_actions_contract: OK")
