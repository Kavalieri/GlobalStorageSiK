--[[
	Global Storage SiK - public product API

	This shared facade is the only public registration boundary for addons.
	The owning registries remain internal and may keep live definitions for Core
	callers; every value returned here is a defensive descriptor copy.
]]

require "GS_AddonRegistry"
pcall(require, "GS_DebugRelay")

GSSiK = GSSiK or {}
GSSiK.API = GSSiK.API or {}
GSSiK.API.Addon = GSSiK.API.Addon or {}
GSSiK.API.Access = GSSiK.API.Access or {}
GSSiK.API.Installation = GSSiK.API.Installation or {}
GSSiK.API.RemoteAccess = GSSiK.API.RemoteAccess or {}
GSSiK.API.Diagnostics = GSSiK.API.Diagnostics or {}
GSSiK.API.ItemActions = GSSiK.API.ItemActions or {}

local API = GSSiK.API
local Addon = GSSiK.API.Addon
local Access = GSSiK.API.Access
local Installation = GSSiK.API.Installation
local Diagnostics = GSSiK.API.Diagnostics
local Registry = GlobalStorageSiK.AddonRegistry

local API_VERSION = "1.0.0"
local CAPABILITY_VERSIONS = {
	Addon = "1.0.0",
	Access = "1.0.0",
	Installation = "1.0.0",
	RemoteAccess = "1.0.0",
	Diagnostics = "1.0.0",
	ItemActions = "1.0.0",
	WorkSession = "1.0.0",
	Terminal = "1.0.0",
}

local OK = "OK"
local ERR_SCHEMA = "ERR_SCHEMA"
local ERR_CAPACITY = "ERR_CAPACITY"
local ERR_NOT_FOUND = "ERR_NOT_FOUND"
local ERR_INTERNAL = "ERR_INTERNAL"
local ERR_UNAVAILABLE = "ERR_UNAVAILABLE"

local function semanticVersion(value)
	if type(value) ~= "string" then return nil end
	local major, minor, patch = string.match(value, "^(%d+)%.(%d+)%.(%d+)")
	if not major then return nil end
	return tonumber(major), tonumber(minor), tonumber(patch)
end

local function versionAtLeast(current, minimum)
	local currentMajor, currentMinor, currentPatch = semanticVersion(current)
	local minimumMajor, minimumMinor, minimumPatch = semanticVersion(minimum)
	if not currentMajor or not minimumMajor then return false end
	if currentMajor ~= minimumMajor then return currentMajor > minimumMajor end
	if currentMinor ~= minimumMinor then return currentMinor > minimumMinor end
	return currentPatch >= minimumPatch
end

API.Capabilities = API.Capabilities or {}

--- Return a copied, deterministic description of the currently stable API.
---@return table descriptor
function API.Capabilities.describe()
	local entries = {}
	for name, version in pairs(CAPABILITY_VERSIONS) do
		entries[#entries + 1] = { name = name, version = version }
	end
	table.sort(entries, function(left, right) return left.name < right.name end)
	return {
		api = "GSSiK.API",
		apiVersion = API_VERSION,
		capabilities = entries,
	}
end

--- Negotiate one capability without exposing its implementation table.
---@param name string
---@param minimumVersion string|nil
---@return boolean available
---@return string code
function API.Capabilities.has(name, minimumVersion)
	if type(name) ~= "string" or name == "" then return false, ERR_SCHEMA end
	local current = CAPABILITY_VERSIONS[name]
	if current == nil then return false, "ERR_CAPABILITY_UNAVAILABLE" end
	if minimumVersion ~= nil then
		if semanticVersion(minimumVersion) == nil then return false, ERR_SCHEMA end
		if not versionAtLeast(current, minimumVersion) then
			return false, "ERR_CAPABILITY_VERSION"
		end
	end
	return true, OK
end

local function hasRegistryContract()
	return type(Registry) == "table"
		and type(Registry._prepareDefinition) == "function"
		and type(Registry._allocateGeneration) == "function"
		and type(Registry._commitPrepared) == "function"
		and type(Registry._removeIfGeneration) == "function"
		and type(Registry._count) == "function"
		and type(Registry._publicCopy) == "function"
		and type(Registry.get) == "function"
		and type(Registry.listActive) == "function"
end

local function resolveInternal(moduleName, fieldName)
	local current = GlobalStorageSiK and GlobalStorageSiK[fieldName]
	if type(current) == "table" then return current end
	local loaded = pcall(require, moduleName)
	if not loaded then return nil end
	current = GlobalStorageSiK and GlobalStorageSiK[fieldName]
	if type(current) ~= "table" then return nil end
	return current
end

local function resolveDisk()
	return resolveInternal("GS_DiskProgramming", "DiskProgramming")
end

local function resolveTerminalAccess()
	return resolveInternal("GS_TerminalAccess", "TerminalAccess")
end

local function hasDiskContract(disk)
	return type(disk) == "table"
		and type(disk._prepareAddonProgram) == "function"
		and type(disk._commitAddonProgram) == "function"
		and type(disk._removeAddonProgramIfGeneration) == "function"
end

local function newRegistration(addonId, generation, disk)
	local disposed = false
	local registration = { id = addonId }

	function registration:dispose()
		if disposed then return false end
		disposed = true
		local registryRemoved = Registry._removeIfGeneration(addonId, generation) == true
		local diskRemoved = disk._removeAddonProgramIfGeneration(addonId, generation) == true
		return registryRemoved or diskRemoved
	end

	return registration
end

local function hasAccessContract(terminalAccess)
	return type(terminalAccess) == "table"
		and type(terminalAccess._prepareWirelessProvider) == "function"
		and type(terminalAccess._allocateWirelessProviderGeneration) == "function"
		and type(terminalAccess._countWirelessProviders) == "function"
		and type(terminalAccess._commitWirelessProvider) == "function"
		and type(terminalAccess._removeWirelessProviderIfGeneration) == "function"
end

local function newAccessRegistration(providerId, generation, terminalAccess)
	local disposed = false
	local registration = { id = providerId }

	function registration:dispose()
		if disposed then return false end
		disposed = true
		return terminalAccess._removeWirelessProviderIfGeneration(providerId, generation) == true
	end

	return registration
end

local function copyPlain(value, depth)
	local valueType = type(value)
	if valueType == "nil" or valueType == "boolean" or valueType == "number" or valueType == "string" then
		return value, true
	end
	if valueType ~= "table" or depth >= 4 then return nil, false end
	local copy = {}
	for key, entry in pairs(value) do
		if type(key) ~= "string" and type(key) ~= "number" then return nil, false end
		local entryCopy, ok = copyPlain(entry, depth + 1)
		if not ok then return nil, false end
		copy[key] = entryCopy
	end
	return copy, true
end

local function validInstallationQuery(networkId, anchor, addonId)
	if type(networkId) ~= "string" or networkId == "" or #networkId > 128
		or type(anchor) ~= "table" or type(addonId) ~= "string" or addonId == "" or #addonId > 64 then
		return false
	end
	return tonumber(anchor.x) ~= nil and tonumber(anchor.y) ~= nil and tonumber(anchor.z or 0) ~= nil
end

local function containsValue(values, expected)
	for index = 1, #(values or {}) do
		if values[index] == expected then return true end
	end
	return false
end

local function registrationResult(definition, ok, code, registration)
	if Registry and type(Registry._recordRegistrationAttempt) == "function" then
		Registry._recordRegistrationAttempt(definition, ok, code)
	end
	return ok, code, registration
end

--- Register or replace one addon definition and its optional disk program.
--- All validation finishes before either internal registry is mutated.
---@param definition table
---@return boolean ok
---@return string code
---@return table|nil registration
function Addon.register(definition)
	local disk = resolveDisk()
	if not hasRegistryContract() or not hasDiskContract(disk) then
		return registrationResult(definition, false, ERR_INTERNAL, nil)
	end

	local valid, code, prepared = Registry._prepareDefinition(definition)
	if valid ~= true or type(prepared) ~= "table" then
		return registrationResult(definition, false, code or ERR_SCHEMA, nil)
	end

	local current = Registry.get(prepared.id)
	local maxAddons = tonumber(Registry.MAX_ADDONS)
	if current == nil and (not maxAddons or Registry._count() >= maxAddons) then
		return registrationResult(definition, false, ERR_CAPACITY, nil)
	end

	local diskValid, diskCode, preparedProgram =
		disk._prepareAddonProgram(prepared.id, prepared.diskProgram)
	if diskValid ~= true then
		return registrationResult(definition, false, diskCode or ERR_SCHEMA, nil)
	end
	if preparedProgram ~= nil then
		if not containsValue(prepared.recipeNames, preparedProgram.recipeName)
			or prepared.installDiskItem ~= preparedProgram.outputItem then
			return registrationResult(definition, false, ERR_SCHEMA, nil)
		end
	end

	local generation = Registry._allocateGeneration()
	if type(generation) ~= "number" then
		return registrationResult(definition, false, ERR_INTERNAL, nil)
	end

	-- Both commits consume already validated owned copies and neither invokes
	-- consumer callbacks. There is no yield or observable partial state between
	-- them in the shared Lua execution context.
	Registry._commitPrepared(prepared, generation)
	disk._commitAddonProgram(prepared.id, generation, preparedProgram)

	return registrationResult(definition, true, OK,
		newRegistration(prepared.id, generation, disk))
end

--- Return one immutable-by-ownership public descriptor copy.
---@param addonId string
---@return boolean ok
---@return string code
---@return table|nil descriptor
function Addon.get(addonId)
	if type(addonId) ~= "string" or addonId == "" then
		return false, ERR_SCHEMA, nil
	end
	if not hasRegistryContract() then return false, ERR_INTERNAL, nil end

	local definition = Registry.get(addonId)
	if definition == nil then return false, ERR_NOT_FOUND, nil end
	local copy = Registry._publicCopy(definition)
	if copy == nil then return false, ERR_INTERNAL, nil end
	return true, OK, copy
end

--- Return active addon descriptors as fresh defensive copies.
---@return boolean ok
---@return string code
---@return table descriptors
function Addon.listActive()
	if not hasRegistryContract() then return false, ERR_INTERNAL, {} end
	local active = Registry.listActive()
	if type(active) ~= "table" then return false, ERR_INTERNAL, {} end

	local copies = {}
	for index = 1, #active do
		local copy = Registry._publicCopy(active[index])
		if copy == nil then return false, ERR_INTERNAL, {} end
		copies[#copies + 1] = copy
	end
	return true, OK, copies
end

--- Return every registered addon in the stable product order.
--- Definitions are copied and never expose registry callbacks or ownership.
---@return boolean ok
---@return string code
---@return table descriptors
function Addon.list()
	if not hasRegistryContract() or type(Registry.listSorted) ~= "function" then
		return false, ERR_INTERNAL, {}
	end
	local registered = Registry.listSorted()
	if type(registered) ~= "table" then return false, ERR_INTERNAL, {} end
	local copies = {}
	for index = 1, #registered do
		local copy = Registry._publicCopy(registered[index])
		if copy == nil then return false, ERR_INTERNAL, {} end
		copies[#copies + 1] = copy
	end
	return true, OK, copies
end

local function activatedModIds()
	local result = {}
	if type(getActivatedMods) ~= "function" then return result, "unavailable" end
	local ok, mods = pcall(getActivatedMods)
	if not ok or not mods then return result, "unavailable" end
	if mods.size and mods.get then
		local sizeOk, size = pcall(function() return mods:size() end)
		if sizeOk and tonumber(size) then
			for index = 0, tonumber(size) - 1 do
				local valueOk, value = pcall(function() return mods:get(index) end)
				if valueOk and value ~= nil then result[#result + 1] = tostring(value) end
			end
		end
	elseif mods.iterator then
		local iteratorOk, iterator = pcall(function() return mods:iterator() end)
		if iteratorOk and iterator then
			while iterator:hasNext() do result[#result + 1] = tostring(iterator:next()) end
		end
	end
	table.sort(result)
	return result, "available"
end

--- Return a bounded, plain-data snapshot for targeted addon diagnostics.
--- It never logs and does not expose executable registry callbacks.
---@return boolean ok
---@return string code
---@return table snapshot
function Addon.diagnose()
	if not hasRegistryContract()
		or type(Registry._registrationDiagnosticSnapshot) ~= "function" then
		return false, ERR_INTERNAL, {}
	end
	local listedOk, listedCode, registered = Addon.list()
	if listedOk ~= true then return false, listedCode, {} end
	local activated, activatedSource = activatedModIds()
	return true, OK, {
		registered = registered,
		attempts = Registry._registrationDiagnosticSnapshot(),
		activatedModIds = activated,
		activatedSource = activatedSource,
	}
end

--- Report whether the addon definition exists and its owning ModID is active.
---@param addonId string
---@return boolean ok
---@return string code
---@return boolean active
function Addon.isActive(addonId)
	if type(addonId) ~= "string" or addonId == "" then
		return false, ERR_SCHEMA, false
	end
	if not hasRegistryContract() or type(Registry.isModActive) ~= "function" then
		return false, ERR_INTERNAL, false
	end
	return true, OK, Registry.isModActive(addonId) == true
end

--- Return public installation defaults instead of leaking registry constants.
---@return table defaults
function Addon.defaults()
	return { moduleSkillLevel = tonumber(Registry.DEFAULT_MODULE_SKILL) or 5 }
end

local function addonKnowledge(method, player, addonId)
	if type(addonId) ~= "string" or addonId == "" then
		return false, ERR_SCHEMA, false
	end
	if not hasRegistryContract() or type(Registry[method]) ~= "function" then
		return false, ERR_INTERNAL, false
	end
	return true, OK, Registry[method](player, addonId) == true
end

---@param player IsoPlayer|nil
---@param addonId string
---@return boolean ok
---@return string code
---@return boolean known
function Addon.playerKnowsModuleRecipe(player, addonId)
	return addonKnowledge("playerKnowsModuleRecipe", player, addonId)
end

---@param player IsoPlayer|nil
---@param addonId string
---@return boolean ok
---@return string code
---@return boolean known
function Addon.playerKnowsMagazine(player, addonId)
	return addonKnowledge("playerKnowsMagazine", player, addonId)
end

--- Resolve the accepted module item types from a registered addon id.
---@param addonId string
---@return boolean ok
---@return string code
---@return string[] itemTypes
function Addon.moduleItemTypes(addonId)
	if type(addonId) ~= "string" or addonId == "" then
		return false, ERR_SCHEMA, {}
	end
	if not hasRegistryContract() or type(Registry.moduleItemTypes) ~= "function" then
		return false, ERR_INTERNAL, {}
	end
	local definition = Registry.get(addonId)
	if definition == nil then return false, ERR_NOT_FOUND, {} end
	local source = Registry.moduleItemTypes(definition)
	local copy = {}
	for index = 1, #(source or {}) do copy[index] = source[index] end
	return true, OK, copy
end

--- Validate the complete product installation policy for one addon.
---@param player IsoPlayer|nil
---@param addonId string
---@param networkId string|nil
---@param anchor table|nil
---@return boolean ok
---@return string code
---@return boolean allowed
---@return string|nil reason
function Addon.canInstall(player, addonId, networkId, anchor)
	if type(addonId) ~= "string" or addonId == "" then
		return false, ERR_SCHEMA, false, "invalid"
	end
	if not hasRegistryContract() or type(Registry.canInstallModule) ~= "function" then
		return false, ERR_INTERNAL, false, "internal"
	end
	local allowed, reason = Registry.canInstallModule(player, addonId, networkId, anchor)
	return true, OK, allowed == true, reason
end

---@param player IsoPlayer|nil
---@param addonId string
---@return boolean ok
---@return string code
---@return boolean present
function Addon.playerHasModuleItem(player, addonId)
	return addonKnowledge("playerHasModuleItem", player, addonId)
end

--- Execute the registered recipe-book resolver behind the API boundary.
---@param addonId string
---@param recipeName string
---@return boolean ok
---@return string code
---@return boolean|nil required
function Addon.resolveRecipeBookRequirement(addonId, recipeName)
	if type(addonId) ~= "string" or addonId == ""
		or type(recipeName) ~= "string" or recipeName == "" then
		return false, ERR_SCHEMA, nil
	end
	if not hasRegistryContract() then return false, ERR_INTERNAL, nil end
	local definition = Registry.get(addonId)
	if definition == nil then return false, ERR_NOT_FOUND, nil end
	if type(definition.resolveRecipeBookRequirement) ~= "function" then
		return true, OK, nil
	end
	local called, required = pcall(definition.resolveRecipeBookRequirement, recipeName)
	if not called then
		return false, ERR_INTERNAL, nil
	end
	-- nil is an explicit abstention: the addon has no product-specific
	-- override for this recipe and Core must apply its own configured default.
	if required == nil then return true, OK, nil end
	if type(required) ~= "boolean" then return false, ERR_INTERNAL, nil end
	return true, OK, required
end

--- Register or atomically replace a remote-access provider. The returned
--- handle removes only its own generation, so disposing an older handle can
--- never unregister a newer replacement with the same id.
---@param definition table
---@return boolean ok
---@return string code
---@return table|nil registration
function Access.registerProvider(definition)
	local terminalAccess = resolveTerminalAccess()
	if not hasAccessContract(terminalAccess) then return false, ERR_INTERNAL, nil end
	local valid, code, prepared = terminalAccess._prepareWirelessProvider(definition)
	if valid ~= true or type(prepared) ~= "table" then
		return false, code or ERR_SCHEMA, nil
	end

	local exists = false
	local providers = terminalAccess._wirelessProviders or {}
	for index = 1, #providers do
		if providers[index] and providers[index].id == prepared.id then
			exists = true
			break
		end
	end
	local maxProviders = tonumber(terminalAccess.MAX_WIRELESS_PROVIDERS)
	if not exists and (not maxProviders or terminalAccess._countWirelessProviders() >= maxProviders) then
		return false, ERR_CAPACITY, nil
	end

	local generation = terminalAccess._allocateWirelessProviderGeneration()
	if type(generation) ~= "number" then return false, ERR_INTERNAL, nil end
	terminalAccess._commitWirelessProvider(prepared, generation)
	return true, OK, newAccessRegistration(prepared.id, generation, terminalAccess)
end

--- Read one installed-addon record as a defensive plain-data copy.
---@param networkId string
---@param anchor table
---@param addonId string
---@return boolean ok
---@return string code
---@return table|nil descriptor
function Installation.get(networkId, anchor, addonId)
	if not validInstallationQuery(networkId, anchor, addonId) then
		return false, ERR_SCHEMA, nil
	end
	local addons = GlobalStorageSiK.Addons
	if type(addons) ~= "table" or type(addons.serializeForTerminal) ~= "function" then
		return false, ERR_INTERNAL, nil
	end
	local installed = addons.serializeForTerminal(networkId, anchor)
	local descriptor = type(installed) == "table" and installed[addonId] or nil
	if descriptor == nil then return false, ERR_NOT_FOUND, nil end
	local copy, copied = copyPlain(descriptor, 0)
	if not copied then return false, ERR_INTERNAL, nil end
	return true, OK, copy
end

---@param networkId string
---@param anchor table
---@param addonId string
---@return boolean ok
---@return string code
---@return boolean installed
function Installation.isInstalled(networkId, anchor, addonId)
	if not validInstallationQuery(networkId, anchor, addonId) then
		return false, ERR_SCHEMA, false
	end
	local addons = GlobalStorageSiK.Addons
	if type(addons) ~= "table" or type(addons.isInstalled) ~= "function" then
		return false, ERR_INTERNAL, false
	end
	return true, OK, addons.isInstalled(networkId, anchor, addonId) == true
end

local function relay()
	return GlobalStorageSiK and GlobalStorageSiK.DebugRelay or nil
end

--- Return the normalized process origin used by the Core relay.
---@return boolean ok
---@return string code
---@return string origin
function Diagnostics.processTag()
	local current = relay()
	if not current or type(current.processTag) ~= "function" then
		return false, ERR_UNAVAILABLE, "?"
	end
	local ok, value = pcall(current.processTag)
	if not ok or type(value) ~= "string" or value == "" then
		return false, ERR_INTERNAL, "?"
	end
	return true, OK, value
end

--- Request the bounded server-log relay for one public addon channel.
---@param channel string
---@return boolean ok
---@return string code
function Diagnostics.subscribe(channel)
	if type(channel) ~= "string" or channel == "" or #channel > 48 then
		return false, ERR_SCHEMA
	end
	local current = relay()
	if not current or type(current.requestClientSubscription) ~= "function" then
		return false, ERR_UNAVAILABLE
	end
	local ok = pcall(current.requestClientSubscription, channel)
	return ok == true, ok == true and OK or ERR_INTERNAL
end

--- Emit one already formatted addon line through the optional Core relay.
--- The addon remains owner of its categories, sandbox gates and format.
---@param line string
---@return boolean ok
---@return string code
function Diagnostics.emit(line)
	if type(line) ~= "string" or line == "" or #line > 4096 then
		return false, ERR_SCHEMA
	end
	local current = relay()
	if not current or type(current.emit) ~= "function" then
		return false, ERR_UNAVAILABLE
	end
	local ok = pcall(current.emit, line)
	return ok == true, ok == true and OK or ERR_INTERNAL
end

return API
