-- Public remote work-session contract for Global Storage SiK addons.
--
-- Core owns the historical implementation. This facade adds the stable
-- product contract: validated inputs, defensive snapshots, operation
-- ownership, bounded diagnostics and lifecycle-safe registrations.

require "GSSiK_API"
require "GS_NetworkCraftSession"

GSSiK.API.CraftSession = nil
GSSiK.API.WorkSession = GSSiK.API.WorkSession or {}
local Public = GSSiK.API.WorkSession
local Diagnostics = GSSiK.API.Diagnostics

local OK = "OK"
local ERR_SCHEMA = "ERR_SCHEMA"
local ERR_UNAVAILABLE = "ERR_UNAVAILABLE"
local ERR_REQUEST = "ERR_REQUEST"
local ERR_SESSION = "ERR_SESSION"
local ERR_OPERATION = "ERR_OPERATION"
local ERR_OWNER = "ERR_OWNER"
local ERR_SOURCE = "ERR_SOURCE"

local operations = {}
local openFailures = {}
local resultDestinations = {}

local function internal()
	return GlobalStorageSiK and GlobalStorageSiK.CraftSession or nil
end

local function validId(value, limit)
	return type(value) == "string" and value ~= "" and #value <= (limit or 96)
end

local function playerNumber(player)
	if not player or type(player.getPlayerNum) ~= "function" then return nil end
	local ok, value = pcall(function() return player:getPlayerNum() end)
	if not ok or type(value) ~= "number" then return nil end
	return value
end

local function copyAnchor(anchor)
	if type(anchor) ~= "table" then return nil end
	local x, y, z = tonumber(anchor.x), tonumber(anchor.y), tonumber(anchor.z)
	if x == nil or y == nil or z == nil then return nil end
	return { x = x, y = y, z = z }
end

local function clearOperations()
	local ids = {}
	for operationId in pairs(operations) do
		ids[#ids + 1] = operationId
	end
	for i = 1, #ids do
		operations[ids[i]] = nil
	end
end

local function sessionSnapshot(value)
	if type(value) ~= "table" then return nil end
	return {
		active = value.active == true,
		networkId = value.networkId,
		addonId = value.addonId,
		playerNum = value.playerNum,
		terminalAnchor = copyAnchor(value.terminalAnchor),
		accessMode = value.accessMode,
		uiMode = value.uiMode,
	}
end

local function operationSnapshot(value)
	if type(value) ~= "table" then return nil end
	return {
		operationId = value.operationId,
		addonId = value.addonId,
		playerNum = value.playerNum,
		networkId = value.networkId,
		kind = value.kind,
		recipeName = value.recipeName,
		batchCount = value.batchCount,
	}
end

local function registration(id, generation, remover)
	local disposed = false
	local handle = { id = id }
	function handle:dispose()
		if disposed then return false end
		disposed = true
		return remover(id, generation) == true
	end
	return handle
end

function Diagnostics.registerWorkSessionSink(addonId, callback)
	local current = internal()
	if not validId(addonId, 64) or type(callback) ~= "function" then
		return false, ERR_SCHEMA, nil
	end
	if not current or type(current.registerDebugSink) ~= "function"
		or type(current.removeDebugSinkIfGeneration) ~= "function" then
		return false, ERR_UNAVAILABLE, nil
	end
	local ok, generation = current.registerDebugSink(addonId, callback)
	if ok ~= true or type(generation) ~= "number" then
		return false, ERR_REQUEST, nil
	end
	return true, OK, registration(addonId, generation, current.removeDebugSinkIfGeneration)
end

function Public.registerLifecycle(addonId, definition)
	local current = internal()
	if not validId(addonId, 64) or type(definition) ~= "table"
		or type(definition.install) ~= "function"
		or type(definition.uninstall) ~= "function"
		or (definition.tick ~= nil and type(definition.tick) ~= "function") then
		return false, ERR_SCHEMA, nil
	end
	if not current or type(current.registerAddonHooks) ~= "function"
		or type(current.removeAddonHooksIfGeneration) ~= "function"
		or type(current.registerTickHandler) ~= "function"
		or type(current.removeTickHandlerIfGeneration) ~= "function" then
		return false, ERR_UNAVAILABLE, nil
	end
	local hooksOk, hooksGeneration = current.registerAddonHooks(addonId,
		definition.install, definition.uninstall)
	if hooksOk ~= true or type(hooksGeneration) ~= "number" then
		return false, ERR_REQUEST, nil
	end
	local tickGeneration = nil
	if definition.tick then
		local tickOk
		tickOk, tickGeneration = current.registerTickHandler(addonId, definition.tick)
		if tickOk ~= true or type(tickGeneration) ~= "number" then
			current.removeAddonHooksIfGeneration(addonId, hooksGeneration)
			return false, ERR_REQUEST, nil
		end
	end
	local disposed = false
	local handle = { id = addonId }
	function handle:dispose()
		if disposed then return false end
		disposed = true
		local hooksRemoved = current.removeAddonHooksIfGeneration(addonId, hooksGeneration) == true
		local tickRemoved = false
		if tickGeneration then
			tickRemoved = current.removeTickHandlerIfGeneration(addonId, tickGeneration) == true
		end
		return hooksRemoved or tickRemoved
	end
	return true, OK, handle
end

function Public.begin(options)
	local current = internal()
	local anchor = type(options) == "table" and copyAnchor(options.terminalAnchor) or nil
	if type(options) ~= "table" or not validId(options.addonId, 64)
		or options.player == nil or not validId(options.networkId, 128)
		or anchor == nil then
		return false, ERR_SCHEMA
	end
	if not current or type(current.begin) ~= "function" then
		return false, ERR_UNAVAILABLE
	end
	local request = {}
	for key, value in pairs(options) do request[key] = value end
	request.terminalAnchor = anchor
	local ok, reason = current.begin(request)
	openFailures[options.addonId] = ok == true and nil or reason
	return ok == true, ok == true and OK or (reason or ERR_REQUEST)
end

function Public.endSession(reason)
	local current = internal()
	if reason ~= nil and type(reason) ~= "string" then return false, ERR_SCHEMA end
	if not current or type(current.endSession) ~= "function" then
		return false, ERR_UNAVAILABLE
	end
	current.endSession(reason)
	clearOperations()
	return true, OK
end

function Public.get(addonId)
	local current = internal()
	if not validId(addonId, 64) then return false, ERR_SCHEMA, nil end
	if not current or type(current.getActiveSession) ~= "function" then
		return false, ERR_UNAVAILABLE, nil
	end
	local snapshot = sessionSnapshot(current.getActiveSession(addonId))
	if not snapshot then return false, ERR_SESSION, nil end
	return true, OK, snapshot
end

function Public.status(addonId)
	local current = internal()
	if not validId(addonId, 64) then return false, ERR_SCHEMA, nil end
	if not current or type(current.getStatus) ~= "function" then
		return false, ERR_UNAVAILABLE, nil
	end
	local value = current.getStatus(addonId)
	if type(value) ~= "table" then return false, ERR_REQUEST, nil end
	return true, OK, {
		active = value.active == true,
		networkId = value.networkId,
		networkContainers = tonumber(value.networkContainers) or 0,
		unavailableContainers = tonumber(value.unavailableContainers) or 0,
		uiMode = value.uiMode,
		addonId = value.addonId,
		lastEndReason = value.lastEndReason,
	}
end

function Public.getOpenFailure(addonId)
	if not validId(addonId, 64) then return false, ERR_SCHEMA, nil end
	return true, OK, openFailures[addonId]
end

function Public.reportOpenFailure(addonId, reason)
	if not validId(addonId, 64) or (reason ~= nil and not validId(reason, 160)) then
		return false, ERR_SCHEMA
	end
	openFailures[addonId] = reason
	local current = internal()
	if current and type(current.setLastOpenError) == "function" then
		current.setLastOpenError(reason)
	end
	return true, OK
end

local function openWith(addonId, methodName, mode, recipe, itemString)
	local current = internal()
	if not validId(addonId, 64)
		or (mode ~= nil and type(mode) ~= "string")
		or (itemString ~= nil and type(itemString) ~= "string") then
		return false, ERR_SCHEMA
	end
	if not current or type(current[methodName]) ~= "function" then
		return false, ERR_UNAVAILABLE
	end
	local ok, reason = current[methodName](mode, recipe, itemString)
	openFailures[addonId] = ok == true and nil or reason
	return ok == true, ok == true and OK or (reason or ERR_REQUEST)
end

function Public.openHandcraft(addonId, mode, recipe, itemString)
	return openWith(addonId, "openHandcraft", mode, recipe, itemString)
end

function Public.openBuild(addonId, mode, recipe, itemString)
	return openWith(addonId, "openBuild", mode, recipe, itemString)
end

local function boundedAttemptPayload(operation, options)
	return {
		operationId = operation.operationId,
		addonId = operation.addonId,
		recipe = operation.recipeName,
		networkId = operation.networkId,
		isCanBeDoneFromFloor = options.canUseFloor == true,
		containersCliente = math.max(0, math.floor(tonumber(options.containerCount) or 0)),
	}
end

function Public.startOperation(options)
	local current = internal()
	if type(options) ~= "table" or not validId(options.addonId, 64)
		or options.player == nil or not validId(options.kind, 48)
		or (options.recipeName ~= nil and not validId(options.recipeName, 256)) then
		return false, ERR_SCHEMA, nil
	end
	if not current or type(current.getActiveSession) ~= "function"
		or type(current.newOperationId) ~= "function" then
		return false, ERR_UNAVAILABLE, nil
	end
	local active = current.getActiveSession(options.addonId)
	local currentPlayerNum = playerNumber(options.player)
	if type(active) ~= "table" or currentPlayerNum == nil then
		return false, ERR_SESSION, nil
	end
	if active.playerNum ~= currentPlayerNum then return false, ERR_OWNER, nil end
	local operationId = current.newOperationId(options.addonId)
	if not validId(operationId, 160) then return false, ERR_REQUEST, nil end
	local operation = {
		operationId = operationId,
		addonId = options.addonId,
		playerNum = currentPlayerNum,
		networkId = active.networkId,
		kind = options.kind,
		recipeName = options.recipeName or "?",
		batchCount = math.max(1, math.floor(tonumber(options.batchCount) or 1)),
	}
	operations[operationId] = operation
	current.sendResultToNetwork = resultDestinations[options.addonId] == "network"
	if options.diagnostics == true then
		local client = GlobalStorageSiK and GlobalStorageSiK.NetClient or nil
		if client and type(client.sendCommand) == "function" then
			client.sendCommand("craftAttemptStart", boundedAttemptPayload(operation, options))
		end
	end
	return true, OK, operationSnapshot(operation)
end

local function ownedOperation(operationId, player)
	if not validId(operationId, 160) then return nil, ERR_SCHEMA end
	local operation = operations[operationId]
	if not operation then return nil, ERR_OPERATION end
	if player ~= nil and playerNumber(player) ~= operation.playerNum then
		return nil, ERR_OWNER
	end
	return operation, OK
end

function Public.claimRecipeInputs(operationId, player, logic, items, batchCount)
	local current = internal()
	local operation, code = ownedOperation(operationId, player)
	if not operation then return false, code, nil end
	if logic == nil or items == nil then return false, ERR_SCHEMA, nil end
	if not current or type(current.claimRecipeItems) ~= "function" then
		return false, ERR_UNAVAILABLE, nil
	end
	local count = math.max(1, math.floor(tonumber(batchCount) or operation.batchCount))
	local waitingIds, waitingCount, moved, shortfall = current.claimRecipeItems(
		player, logic, items, operation.networkId, operationId, count)
	return true, OK, {
		waitingIds = type(waitingIds) == "table" and waitingIds or {},
		waitingCount = tonumber(waitingCount) or 0,
		claimedCount = tonumber(moved) or 0,
		batchShortfall = tonumber(shortfall) or 0,
		batchSupported = tonumber(current.CLAIM_RECIPE_CONTRACT_VERSION) >= 2,
	}
end

function Public.claimItem(operationId, player, item, container)
	local current = internal()
	local operation, code = ownedOperation(operationId, player)
	if not operation then return false, code, false end
	if item == nil or container == nil then return false, ERR_SCHEMA, false end
	if not current or type(current.claimNetworkItem) ~= "function"
		or type(current.isNetworkContainer) ~= "function" then
		return false, ERR_UNAVAILABLE, false
	end
	if current.isNetworkContainer(container, operation.networkId) ~= true then
		return false, ERR_SOURCE, false
	end
	local claimed = current.claimNetworkItem(player, item, container,
		operation.networkId, operationId) == true
	return claimed, claimed and OK or ERR_REQUEST, claimed
end

function Public.completeOperation(operationId, player)
	local current = internal()
	local operation, code = ownedOperation(operationId, player)
	if not operation then return false, code end
	if not current or type(current.markOperationComplete) ~= "function" then
		return false, ERR_UNAVAILABLE
	end
	current.markOperationComplete(operationId)
	operations[operationId] = nil
	return true, OK
end

function Public.abortOperation(operationId, player)
	local current = internal()
	local operation, code = ownedOperation(operationId, player)
	if not operation then return false, code end
	if not current or type(current.abortOperation) ~= "function" then
		return false, ERR_UNAVAILABLE
	end
	current.abortOperation(operationId)
	operations[operationId] = nil
	return true, OK
end

function Public.narrowInputs(panel, items, addonId)
	local current = internal()
	if panel == nil or not validId(addonId, 64) then
		return false, ERR_SCHEMA, nil
	end
	if not current or type(current.narrowContainersForAction) ~= "function" then
		return false, ERR_UNAVAILABLE, nil
	end
	local restore = current.narrowContainersForAction(panel, items, addonId)
	if type(restore) ~= "function" then return false, ERR_REQUEST, nil end
	local restored = false
	local handle = {}
	function handle:restore()
		if restored then return false end
		restored = true
		return pcall(restore) == true
	end
	function handle:dispose()
		return self:restore()
	end
	return true, OK, handle
end

function Public.withContainerInjectionSuspended(callback, ...)
	local current = internal()
	if type(callback) ~= "function" then return false, ERR_SCHEMA end
	if not current or type(current.withContainerInjectionSuspended) ~= "function" then
		return false, ERR_UNAVAILABLE
	end
	return current.withContainerInjectionSuspended(callback, ...)
end

function Public.setResultDestination(addonId, destination)
	if not validId(addonId, 64)
		or (destination ~= "inventory" and destination ~= "network") then
		return false, ERR_SCHEMA
	end
	resultDestinations[addonId] = destination
	return true, OK
end

function Public.getResultDestination(addonId)
	if not validId(addonId, 64) then return false, ERR_SCHEMA, nil end
	return true, OK, resultDestinations[addonId] or "inventory"
end

return GSSiK.API
