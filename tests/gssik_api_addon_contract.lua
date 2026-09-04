-- Public GSSiK.API.Addon schema and defensive-copy contract.
-- Run from GlobalStorageSiK-Repo with Lua 5.1.

package.loaded["GS_AddonRegistry"] = true
package.loaded["GS_DiskProgramming"] = true
package.loaded["GS_TerminalAccess"] = true

local definitions = {}
local programs = {}
local generation = 0

local function copyDefinition(source)
	local copy = {}
	for key, value in pairs(source) do
		if type(value) ~= "table" and key ~= "resolveRecipeBookRequirement" then
			copy[key] = value
		end
	end
	copy.recipeNames = {}
	for index = 1, #(source.recipeNames or {}) do
		copy.recipeNames[index] = source.recipeNames[index]
	end
	if source.diskProgram then
		copy.diskProgram = {}
		for key, value in pairs(source.diskProgram) do copy.diskProgram[key] = value end
	end
	return copy
end

GlobalStorageSiK = {
	AddonRegistry = {
		MAX_ADDONS = 32,
		_prepareDefinition = function(definition)
			if type(definition) ~= "table" or type(definition.id) ~= "string"
				or type(definition.recipeNames) ~= "table" then
				return false, "ERR_SCHEMA", nil
			end
			return true, "OK", copyDefinition(definition)
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
		_publicCopy = copyDefinition,
		get = function(addonId) return definitions[addonId] end,
		listActive = function()
			local rows = {}
			for _, definition in pairs(definitions) do rows[#rows + 1] = definition end
			return rows
		end,
	},
	DiskProgramming = {
		_prepareAddonProgram = function(addonId, program)
			if program and type(program.recipeName) ~= "string" then
				return false, "ERR_DISK_SCHEMA", nil
			end
			local copy = nil
			if program then
				copy = {}
				for key, value in pairs(program) do copy[key] = value end
			end
			return true, "OK", copy
		end,
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

local callback = function() return 5 end
local source = {
	id = "Craft",
	modId = "GSSiK_Addon_Craft",
	itemType = "Craft.Module",
	magazineType = "Craft.Magazine",
	recipeNames = { "Build Craft Module", "Program Craft Disk" },
	moduleRecipeName = "Build Craft Module",
	installDiskItem = "Craft.Disk",
	resolveRecipeBookRequirement = callback,
	diskProgram = { recipeName = "Program Craft Disk", outputItem = "Craft.Disk" },
}

local ok, code, registration = GSSiK.API.Addon.register(source)
assert(ok == true and code == "OK", "valid addon must register")
assert(type(registration) == "table" and registration.id == "Craft",
	"registration handle must expose only stable addon identity")
assert(registration._generation == nil, "generation must remain private to the handle closure")

source.recipeNames[1] = "MUTATED"
source.diskProgram.outputItem = "Mutated.Disk"
assert(definitions.Craft.recipeNames[1] == "Build Craft Module",
	"registration must not retain caller-owned recipe arrays")
assert(programs.Craft.definition.outputItem == "Craft.Disk",
	"disk registration must not retain caller-owned program tables")

local got, getCode, first = GSSiK.API.Addon.get("Craft")
assert(got == true and getCode == "OK", "registered addon must be queryable")
assert(first.resolveRecipeBookRequirement == nil,
	"public descriptor must not expose executable callbacks")
first.recipeNames[1] = "PUBLIC MUTATION"
first.diskProgram.outputItem = "Public.Mutation"

local _, _, second = GSSiK.API.Addon.get("Craft")
assert(second.recipeNames[1] == "Build Craft Module",
	"get must return a fresh defensive copy")
assert(second.diskProgram.outputItem == "Craft.Disk",
	"nested public disk descriptors must be copied")

local listed, listCode, active = GSSiK.API.Addon.listActive()
assert(listed == true and listCode == "OK" and #active == 1,
	"listActive must return active public descriptors")
active[1].recipeNames[1] = "LIST MUTATION"
local _, _, afterListMutation = GSSiK.API.Addon.get("Craft")
assert(afterListMutation.recipeNames[1] == "Build Craft Module",
	"listActive must not leak live registry definitions")

local missing, missingCode, missingValue = GSSiK.API.Addon.get("Missing")
assert(missing == false and missingCode == "ERR_NOT_FOUND" and missingValue == nil,
	"missing addon must use the stable not-found result")
local invalid, invalidCode = GSSiK.API.Addon.register({})
assert(invalid == false and invalidCode == "ERR_SCHEMA",
	"invalid definitions must preserve the validator result code")

local mismatch, mismatchCode = GSSiK.API.Addon.register({
	id = "Mismatch",
	modId = "Mismatch",
	itemType = "Mismatch.Module",
	magazineType = "Mismatch.Magazine",
	moduleRecipeName = "Build Mismatch",
	installDiskItem = "Mismatch.ExpectedDisk",
	recipeNames = { "Build Mismatch", "Program Mismatch" },
	diskProgram = { recipeName = "Program Mismatch", outputItem = "Mismatch.OtherDisk" },
})
assert(mismatch == false and mismatchCode == "ERR_SCHEMA",
	"install disk and program output must describe the same item")

definitions.Craft.resolveRecipeBookRequirement = function(recipeName)
	if recipeName == "Build Craft Module" then return true end
	if recipeName == "Use Core Default" then return nil end
	if recipeName == "Invalid Resolver" then return "yes" end
	error("resolver failure")
end
local resolved, resolvedCode, required = GSSiK.API.Addon.resolveRecipeBookRequirement(
	"Craft", "Build Craft Module")
assert(resolved == true and resolvedCode == "OK" and required == true,
	"boolean resolver results must cross the public boundary")
local abstained, abstainedCode, abstainedValue = GSSiK.API.Addon.resolveRecipeBookRequirement(
	"Craft", "Use Core Default")
assert(abstained == true and abstainedCode == "OK" and abstainedValue == nil,
	"nil must be a stable resolver abstention for the Core fallback")
local invalidResolver, invalidResolverCode = GSSiK.API.Addon.resolveRecipeBookRequirement(
	"Craft", "Invalid Resolver")
assert(invalidResolver == false and invalidResolverCode == "ERR_INTERNAL",
	"non-boolean non-nil resolver results must be rejected")
local failedResolver, failedResolverCode = GSSiK.API.Addon.resolveRecipeBookRequirement(
	"Craft", "Resolver Failure")
assert(failedResolver == false and failedResolverCode == "ERR_INTERNAL",
	"resolver exceptions must be contained behind the public API")

print("gssik_api_addon_contract: OK")
