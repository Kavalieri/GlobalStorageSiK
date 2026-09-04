-- Global Storage SiK public client API.
--
-- Product addons consume this module instead of reaching into TerminalUI,
-- NetClient or the client's transient-cleanup registry. The API owns request
-- validation, callback normalization, defensive payload copies and lifecycle.

require "GSSiK_API"
require "GS_PlayerUtils"
require "GS_TerminalUI_Api"
require "GS_ItemActions"
require "GSSiK_API_WorkSession"
require "GSSiK_API_Terminal"

local API = GSSiK.API
local RemoteAccess = API.RemoteAccess
local ItemActions = API.ItemActions
local active = RemoteAccess._active or {}
RemoteAccess._active = active
local cleanupEntries = RemoteAccess._cleanupEntries or {}
RemoteAccess._cleanupEntries = cleanupEntries
local cleanupGeneration = tonumber(RemoteAccess._cleanupGeneration) or 0

local OK = "OK"
local ERR_SCHEMA = "ERR_SCHEMA"
local ERR_UNAVAILABLE = "ERR_UNAVAILABLE"
local ERR_REQUEST = "ERR_REQUEST"
local ERR_CANCELLED = "ERR_CANCELLED"

local function resolvePlayer(playerArg)
	local utils = GlobalStorageSiK.PlayerUtils
	return utils and utils.resolve and utils.resolve(playerArg) or nil
end

local function playerNumber(player)
	return player and player.getPlayerNum and player:getPlayerNum() or 0
end

local function copyPlain(value, depth)
	local valueType = type(value)
	if valueType == "nil" or valueType == "boolean" or valueType == "number"
		or valueType == "string" then return value, true end
	if valueType ~= "table" or depth >= 5 then return nil, false end
	local copy, count = {}, 0
	for key, entry in pairs(value) do
		count = count + 1
		if count > 256 or (type(key) ~= "string" and type(key) ~= "number") then
			return nil, false
		end
		local entryCopy, ok = copyPlain(entry, depth + 1)
		if not ok then return nil, false end
		copy[key] = entryCopy
	end
	return copy, true
end

local function removeHandle(handle)
	if active[handle.playerNum] == handle then active[handle.playerNum] = nil end
end

local function cancelInternal(handle, code)
	if not handle or handle.done then return false end
	handle.done = true
	removeHandle(handle)
	local terminal = GlobalStorageSiK.TerminalUI
	if handle.requestId and terminal then
		if handle.kind == "list" and terminal.cancelRemoteNetworkRequest then
			terminal.cancelRemoteNetworkRequest(handle.requestId, handle.player)
		elseif handle.kind == "open" and terminal.cancelOpenNetworkRequest then
			terminal.cancelOpenNetworkRequest(handle.requestId, handle.player)
		end
	end
	handle.requestId = nil
	if code and type(handle.callback) == "function" then
		local callback = handle.callback
		handle.callback = nil
		pcall(callback, false, code, nil)
	else
		handle.callback = nil
	end
	return true
end

local function requestHandle(kind, player, callback)
	local handle = {
		kind = kind,
		player = player,
		playerNum = playerNumber(player),
		callback = callback,
		done = false,
	}
	function handle:cancel()
		return cancelInternal(self, ERR_CANCELLED)
	end
	function handle:dispose()
		return cancelInternal(self, nil)
	end
	return handle
end

local function replaceActive(handle)
	local previous = active[handle.playerNum]
	if previous and previous ~= handle then previous:dispose() end
	active[handle.playerNum] = handle
end

local function ensureCleanup()
	if RemoteAccess._cleanupRegistered then return true end
	local client = GlobalStorageSiK.Client
	if not client or type(client.registerTransientCleanup) ~= "function" then return false end
	RemoteAccess._cleanupRegistered = client.registerTransientCleanup("GSSiK.API.RemoteAccess", function(playerNum)
		local keys = {}
		for key, _ in pairs(active) do keys[#keys + 1] = key end
		for index = 1, #keys do
			local key, handle = keys[index], active[keys[index]]
			if handle and (playerNum == nil or tonumber(playerNum) == tonumber(key)) then
				handle:dispose()
			end
		end
	end) == true
	return RemoteAccess._cleanupRegistered
end

--- Register product-owned UI cleanup for remote-access lifecycle events.
--- The internal client registry retains only an id lookup closure; disposing
--- the public handle releases the consumer callback immediately and an older
--- handle can never remove a newer replacement with the same id.
---@return boolean ok
---@return string code
---@return table|nil registration
function RemoteAccess.registerCleanup(id, handler)
	if type(id) ~= "string" or id == "" or #id > 96 or type(handler) ~= "function" then
		return false, ERR_SCHEMA, nil
	end
	local client = GlobalStorageSiK.Client
	if not client or type(client.registerTransientCleanup) ~= "function" then
		return false, ERR_UNAVAILABLE, nil
	end
	cleanupGeneration = cleanupGeneration + 1
	RemoteAccess._cleanupGeneration = cleanupGeneration
	local generation = cleanupGeneration
	cleanupEntries[id] = { generation = generation, handler = handler }
	local registryId = "GSSiK.API.RemoteAccess." .. id
	local registered = client.registerTransientCleanup(registryId, function(playerNum)
		local entry = cleanupEntries[id]
		if entry and entry.generation == generation then
			pcall(entry.handler, playerNum)
		end
	end) == true
	if not registered then
		if cleanupEntries[id] and cleanupEntries[id].generation == generation then
			cleanupEntries[id] = nil
		end
		return false, ERR_UNAVAILABLE, nil
	end
	local disposed = false
	local registration = { id = id }
	function registration:dispose()
		if disposed then return false end
		disposed = true
		local entry = cleanupEntries[id]
		if entry and entry.generation == generation then
			cleanupEntries[id] = nil
			return true
		end
		return false
	end
	return true, OK, registration
end

--- List remote networks accessible to one player.
--- Callback signature: callback(ok, code, copiedNetworks).
---@return boolean ok
---@return string code
---@return table|nil request
function RemoteAccess.list(playerArg, callback)
	if type(callback) ~= "function" then return false, ERR_SCHEMA, nil end
	local player = resolvePlayer(playerArg)
	local terminal = GlobalStorageSiK.TerminalUI
	if not player or not terminal or type(terminal.requestRemoteNetworks) ~= "function" then
		return false, ERR_UNAVAILABLE, nil
	end
	ensureCleanup()
	local handle = requestHandle("list", player, callback)
	replaceActive(handle)
	local completed = false
	local requestId = terminal.requestRemoteNetworks(function(networks, reason)
		if handle.done then return end
		completed = true
		handle.done = true
		handle.requestId = nil
		removeHandle(handle)
		local result, copied = copyPlain(networks or {}, 0)
		local cb = handle.callback
		handle.callback = nil
		if type(cb) == "function" then
			if reason then cb(false, tostring(reason), {})
			elseif not copied then cb(false, "ERR_PAYLOAD", {})
			else cb(true, OK, result) end
		end
	end, player)
	if not requestId and not completed then
		cancelInternal(handle, nil)
		return false, ERR_REQUEST, nil
	end
	handle.requestId = requestId
	return true, OK, handle
end

--- Open one remote network after the authoritative server revalidates it.
--- Callback signature: callback(ok, code, copiedResult).
---@return boolean ok
---@return string code
---@return table|nil request
function RemoteAccess.open(networkId, playerArg, callback)
	if type(networkId) ~= "string" or networkId == "" or #networkId > 128
		or (callback ~= nil and type(callback) ~= "function") then
		return false, ERR_SCHEMA, nil
	end
	local player = resolvePlayer(playerArg)
	local terminal = GlobalStorageSiK.TerminalUI
	if not player or not terminal or type(terminal.requestOpenNetwork) ~= "function" then
		return false, ERR_UNAVAILABLE, nil
	end
	ensureCleanup()
	local handle = requestHandle("open", player, callback)
	replaceActive(handle)
	local completed = false
	local requestId = terminal.requestOpenNetwork(networkId, player, function(accepted, reason, payload)
		if handle.done then return end
		completed = true
		handle.done = true
		handle.requestId = nil
		removeHandle(handle)
		local result, copied = copyPlain(payload or {}, 0)
		local cb = handle.callback
		handle.callback = nil
		if type(cb) == "function" then
			if accepted == true and copied then cb(true, OK, result)
			elseif not copied then cb(false, "ERR_PAYLOAD", nil)
			else cb(false, tostring(reason or "ERR_REJECTED"), result) end
		end
	end)
	if not requestId and not completed then
		cancelInternal(handle, nil)
		return false, ERR_REQUEST, nil
	end
	handle.requestId = requestId
	return true, OK, handle
end

local function itemActionsInternal()
	return GlobalStorageSiK and GlobalStorageSiK.ItemActions or nil
end

local function actionRegistration(id, generation, remove)
	local disposed = false
	local registration = { id = id }
	function registration:dispose()
		if disposed then return false end
		disposed = true
		return remove(id, generation) == true
	end
	return registration
end

--- Register one inventory item as a tablet entry. This public boundary owns
--- validation, replacement generations and disposal; addons never retain or
--- mutate the Core context-menu registries directly.
---@param definition table
---@return boolean ok
---@return string code
---@return table|nil registration
function ItemActions.registerTablet(definition)
	if type(definition) ~= "table" or type(definition.fullType) ~= "string"
		or definition.fullType == "" or #definition.fullType > 128
		or type(definition.labelKey) ~= "string" or definition.labelKey == ""
		or #definition.labelKey > 128 or type(definition.onUse) ~= "function" then
		return false, ERR_SCHEMA, nil
	end
	local internal = itemActionsInternal()
	if not internal or type(internal.registerTabletItem) ~= "function"
		or type(internal.removeTabletItemIfGeneration) ~= "function" then
		return false, ERR_UNAVAILABLE, nil
	end
	local ok, generation = internal.registerTabletItem(definition.fullType,
		definition.labelKey, definition.onUse)
	if ok ~= true or type(generation) ~= "number" then
		return false, ERR_REQUEST, nil
	end
	return true, OK, actionRegistration(definition.fullType, generation,
		internal.removeTabletItemIfGeneration)
end

local function copyProviderDefinition(definition)
	if type(definition) ~= "table" or type(definition.id) ~= "string"
		or definition.id == "" or #definition.id > 96
		or type(definition.addonId) ~= "string" or definition.addonId == ""
		or #definition.addonId > 64 or type(definition.capabilities) ~= "table"
		or type(definition.actions) ~= "table" or #definition.actions == 0
		or #definition.actions > 16 or type(definition.appliesTo) ~= "function"
		or type(definition.buildRequest) ~= "function"
		or (type(definition.executeRequest) ~= "function"
			and type(definition.execute) ~= "function") then
		return nil
	end
	local prepared = {
		id = definition.id, addonId = definition.addonId,
		appliesTo = definition.appliesTo, buildRequest = definition.buildRequest,
		executeRequest = definition.executeRequest, execute = definition.execute,
		capabilities = {}, actions = {},
	}
	for index = 1, #definition.capabilities do
		local value = definition.capabilities[index]
		if type(value) ~= "string" or value == "" or #value > 64 then return nil end
		prepared.capabilities[index] = value
	end
	for index = 1, #definition.actions do
		local action = definition.actions[index]
		if type(action) ~= "table" or type(action.id) ~= "string" or action.id == ""
			or #action.id > 64 or type(action.labelKey) ~= "string"
			or action.labelKey == "" or #action.labelKey > 128 then return nil end
		prepared.actions[index] = { id = action.id, labelKey = action.labelKey }
	end
	return prepared
end

--- Register one declarative inventory action provider with an owned copy and
--- a generation-safe disposable registration.
---@param definition table
---@return boolean ok
---@return string code
---@return table|nil registration
function ItemActions.registerProvider(definition)
	local prepared = copyProviderDefinition(definition)
	if not prepared then return false, ERR_SCHEMA, nil end
	local internal = itemActionsInternal()
	if not internal or type(internal.registerProvider) ~= "function"
		or type(internal.removeProviderIfGeneration) ~= "function" then
		return false, ERR_UNAVAILABLE, nil
	end
	local ok, generation = internal.registerProvider(prepared)
	if ok ~= true or type(generation) ~= "number" then
		return false, ERR_REQUEST, nil
	end
	return true, OK, actionRegistration(prepared.id, generation,
		internal.removeProviderIfGeneration)
end

return API
