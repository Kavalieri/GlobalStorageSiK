-- Integration regression for the real Registry + Disk + public facade seams.
-- Run from GlobalStorageSiK-Repo with Lua 5.1.

for _, moduleName in ipairs({
	"GS_Config", "GS_CraftUtils", "GS_Sandbox", "GS_InventorySync",
	"GS_TerminalAccess", "GS_AddonRegistry", "GS_DiskProgramming",
}) do
	package.loaded[moduleName] = true
end

GlobalStorageSiK = {
	CraftUtils = {},
	Sandbox = {},
	TerminalAccess = {},
}

local shared = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/"
dofile(shared .. "GS_AddonRegistry.lua")
dofile(shared .. "GS_DiskProgramming.lua")
dofile(shared .. "GSSiK_API.lua")

local function definition(withDisk, programId)
	local def = {
		id = "FixtureAddon",
		modId = "FixtureAddonMod",
		itemType = "FixtureAddon.Module",
		magazineType = "FixtureAddon.Magazine",
		moduleRecipeName = "Build Fixture Module",
		recipeNames = { "Build Fixture Module" },
	}
	if withDisk then
		def.installDiskItem = "FixtureAddon.InstallDisk"
		def.recipeNames[2] = "Program Fixture Disk"
		def.diskProgram = {
			id = programId or "fixture_program",
			recipeName = "Program Fixture Disk",
			manualItem = "FixtureAddon.DiskManual",
			outputItem = "FixtureAddon.InstallDisk",
			menuTextKey = "IGUI_FixtureProgram",
			iconPath = "media/textures/Item_FixtureDisk.png",
			descKey = "IGUI_FixtureProgramDesc",
		}
	end
	return def
end

local ok, code, diskHandle = GSSiK.API.Addon.register(definition(true))
assert(ok == true and code == "OK", "real registries must accept a valid aggregate definition")
local stored = GlobalStorageSiK.AddonRegistry.get("FixtureAddon")
local program = GlobalStorageSiK.DiskProgramming.PROGRAMS.fixture_program
assert(stored ~= nil and program ~= nil, "one call must publish addon and disk program")
assert(stored._generation == GlobalStorageSiK.DiskProgramming._programGenerations.fixture_program,
	"addon and disk program must share the same generation")

local conflict, conflictCode = GSSiK.API.Addon.register(definition(true, "network"))
assert(conflict == false and conflictCode == "ERR_PROGRAM_ID_CONFLICT",
	"addon cannot claim a Core-owned disk program ID")
assert(GlobalStorageSiK.AddonRegistry.get("FixtureAddon")._generation == stored._generation,
	"disk ownership conflict must not replace the current addon")

local diskless, disklessCode, disklessHandle = GSSiK.API.Addon.register(definition(false))
assert(diskless == true and disklessCode == "OK", "diskProgram must remain optional")
assert(GlobalStorageSiK.DiskProgramming.PROGRAMS.fixture_program == nil,
	"disk-backed to diskless replacement must retire the old program atomically")
assert(diskHandle:dispose() == false,
	"stale disk-backed handle must not dispose the replacement generation")

local publicOk, publicCode, publicDef = GSSiK.API.Addon.get("FixtureAddon")
assert(publicOk == true and publicCode == "OK" and publicDef.diskProgram == nil,
	"public query must describe the current diskless registration")
publicDef.recipeNames[1] = "Mutated"
assert(GlobalStorageSiK.AddonRegistry.get("FixtureAddon").recipeNames[1]
	== "Build Fixture Module", "public descriptor must not mutate the live registry")

assert(disklessHandle:dispose() == true, "current real registration must dispose")
assert(GlobalStorageSiK.AddonRegistry.get("FixtureAddon") == nil,
	"dispose must remove the matching real registry generation")

local externalDisk = definition(false)
externalDisk.installDiskItem = "GlobalStorageSiK.CoreProvisionedDisk"
local externalOk, externalCode, externalHandle = GSSiK.API.Addon.register(externalDisk)
assert(externalOk == true and externalCode == "OK",
	"an addon may require a Core- or externally-provisioned install disk without owning its program")
assert(GlobalStorageSiK.AddonRegistry.get("FixtureAddon").installDiskItem
	== "GlobalStorageSiK.CoreProvisionedDisk",
	"externally-provisioned install disk identity must remain in the addon contract")
assert(externalHandle:dispose() == true, "external-disk registration must retain normal lifecycle")

print("gssik_api_addon_integration_regression: OK")
