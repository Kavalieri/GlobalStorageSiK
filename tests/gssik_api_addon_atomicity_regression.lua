-- GSSiK.API.Addon preflight and atomic commit regression.
-- Run from GlobalStorageSiK-Repo with Lua 5.1.

package.loaded["GS_AddonRegistry"] = true
package.loaded["GS_DiskProgramming"] = true
package.loaded["GS_TerminalAccess"] = true

local definitions = { Existing = { id = "Existing", _generation = 7 } }
local sequence = {}
local allocated = 0
local rejectDisk = true

GlobalStorageSiK = {
	AddonRegistry = {
		MAX_ADDONS = 1,
		_prepareDefinition = function(definition)
			if type(definition) ~= "table" or not definition.id then
				return false, "ERR_SCHEMA", nil
			end
			return true, "OK", {
				id = definition.id,
				installDiskItem = definition.installDiskItem,
				recipeNames = { "Recipe", definition.diskProgram and definition.diskProgram.recipeName },
				diskProgram = definition.diskProgram,
			}
		end,
		_allocateGeneration = function()
			allocated = allocated + 1
			return 100 + allocated
		end,
		_commitPrepared = function(prepared, value)
			sequence[#sequence + 1] = "registry:" .. tostring(value)
			prepared._generation = value
			definitions[prepared.id] = prepared
		end,
		_removeIfGeneration = function() return false end,
		_count = function() return 1 end,
		_publicCopy = function(definition) return { id = definition.id } end,
		get = function(addonId) return definitions[addonId] end,
		listActive = function() return {} end,
	},
	DiskProgramming = {
		_prepareAddonProgram = function(_, program)
			if rejectDisk then return false, "ERR_DISK_SCHEMA", nil end
			return true, "OK", program
		end,
		_commitAddonProgram = function(_, value)
			sequence[#sequence + 1] = "disk:" .. tostring(value)
		end,
		_removeAddonProgramIfGeneration = function() return false end,
	},
}

dofile("GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/GSSiK_API.lua")

local capacityOk, capacityCode = GSSiK.API.Addon.register({
	id = "Overflow",
	installDiskItem = "Overflow.Disk",
	diskProgram = { recipeName = "Program Overflow", outputItem = "Overflow.Disk" },
})
assert(capacityOk == false and capacityCode == "ERR_CAPACITY",
	"new registrations beyond the bounded registry must fail preflight")
assert(allocated == 0 and #sequence == 0 and definitions.Overflow == nil,
	"capacity failure must not allocate or mutate either registry")

local diskOk, diskCode = GSSiK.API.Addon.register({
	id = "Existing",
	installDiskItem = "Existing.Disk",
	diskProgram = { recipeName = "Broken", outputItem = "Existing.Disk" },
})
assert(diskOk == false and diskCode == "ERR_DISK_SCHEMA",
	"disk validator result must be stable and visible")
assert(allocated == 0 and #sequence == 0 and definitions.Existing._generation == 7,
	"disk failure must leave the existing registration untouched")

rejectDisk = false
local ok, code = GSSiK.API.Addon.register({
	id = "Existing",
	installDiskItem = "Existing.Disk",
	diskProgram = { recipeName = "Valid", outputItem = "Existing.Disk" },
})
assert(ok == true and code == "OK", "validated replacement must commit")
assert(#sequence == 2 and sequence[1] == "registry:101" and sequence[2] == "disk:101",
	"registry and disk commits must share one generation and fixed order")

print("gssik_api_addon_atomicity_regression: OK")
