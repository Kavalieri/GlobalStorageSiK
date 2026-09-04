-- Generation-safe GSSiK.API.Addon registration lifecycle.
-- Run from GlobalStorageSiK-Repo with Lua 5.1.

package.loaded["GS_AddonRegistry"] = true
package.loaded["GS_DiskProgramming"] = true
package.loaded["GS_TerminalAccess"] = true

local definitions, programs = {}, {}
local generation = 0

GlobalStorageSiK = {
	AddonRegistry = {
		MAX_ADDONS = 2,
		_prepareDefinition = function(definition)
			if type(definition) ~= "table" or not definition.id then
				return false, "ERR_SCHEMA", nil
			end
			local prepared = {
				id = definition.id,
				installDiskItem = definition.installDiskItem,
				recipeNames = { definition.recipeNames[1], definition.recipeNames[2] },
			}
			prepared.diskProgram = definition.diskProgram and {
				recipeName = definition.diskProgram.recipeName,
				outputItem = definition.diskProgram.outputItem,
			} or nil
			return true, "OK", prepared
		end,
		_allocateGeneration = function()
			generation = generation + 1
			return generation
		end,
		_commitPrepared = function(prepared, value)
			prepared._generation = value
			definitions[prepared.id] = prepared
		end,
		_removeIfGeneration = function(addonId, value)
			local current = definitions[addonId]
			if not current or current._generation ~= value then return false end
			definitions[addonId] = nil
			return true
		end,
		_count = function()
			local count = 0
			for _ in pairs(definitions) do count = count + 1 end
			return count
		end,
		_publicCopy = function(definition)
			return { id = definition.id, recipeNames = { definition.recipeNames[1] } }
		end,
		get = function(addonId) return definitions[addonId] end,
		listActive = function() return {} end,
	},
	DiskProgramming = {
		_prepareAddonProgram = function(_, program) return true, "OK", program end,
		_commitAddonProgram = function(addonId, value, program)
			programs[addonId] = program and { generation = value, definition = program } or nil
		end,
		_removeAddonProgramIfGeneration = function(addonId, value)
			local current = programs[addonId]
			if not current or current.generation ~= value then return false end
			programs[addonId] = nil
			return true
		end,
	},
}

dofile("GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/GSSiK_API.lua")

local function definition(recipe, withDisk)
	local diskRecipe = "Program " .. recipe
	return {
		id = "Builder",
		installDiskItem = withDisk and "Builder.Disk" or nil,
		recipeNames = { recipe, diskRecipe },
		diskProgram = withDisk and {
			recipeName = diskRecipe,
			outputItem = "Builder.Disk",
		} or nil,
	}
end

local ok, _, oldHandle = GSSiK.API.Addon.register(definition("Old", true))
assert(ok == true, "initial registration must succeed")
local oldGeneration = definitions.Builder._generation

local replaced, _, newHandle = GSSiK.API.Addon.register(definition("New", true))
assert(replaced == true, "same-id replacement must succeed at capacity")
local newGeneration = definitions.Builder._generation
assert(newGeneration ~= oldGeneration, "replacement must allocate a new generation")

assert(oldHandle:dispose() == false,
	"stale handle must not dispose a newer registration")
assert(definitions.Builder.recipeNames[1] == "New",
	"stale handle must preserve the newer registry entry")
assert(programs.Builder.generation == newGeneration,
	"stale handle must preserve the newer disk program")

assert(newHandle:dispose() == true, "current handle must dispose its own generation")
assert(definitions.Builder == nil and programs.Builder == nil,
	"current dispose must remove registry and disk state together")
assert(newHandle:dispose() == false, "dispose must be idempotent")

local _, _, diskHandle = GSSiK.API.Addon.register(definition("Disk", true))
assert(programs.Builder ~= nil, "disk-backed registration must publish its program")
local noDiskOk, _, noDiskHandle = GSSiK.API.Addon.register(definition("NoDisk", false))
assert(noDiskOk == true and programs.Builder == nil,
	"replacing disk-backed addon with diskless definition must remove stale program")
assert(diskHandle:dispose() == false,
	"disk-backed stale handle must not remove its diskless replacement")
assert(noDiskHandle:dispose() == true,
	"current diskless registration must remain disposable")

print("gssik_api_addon_lifecycle_regression: OK")
