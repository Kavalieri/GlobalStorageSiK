--[[
	GlobalStorageSiK - Ritmo acotado de operaciones masivas
	Descripcion: resuelve una instantanea inmutable de presupuestos para deposito,
	retirada y Auto Sort. Multijugador siempre usa el perfil seguro.
]]

require "GS_Config"
require "GS_Sandbox"

GlobalStorageSiK.OperationPacing = GlobalStorageSiK.OperationPacing or {}

local SAFE = {
	profile = "safe", batchUnits = 10, batchDelayMs = 400,
	maxMovesPerStep = 2, moveDelayMs = 1000,
	inspectedPerStep = 25, indexItemsPerStep = 50, cpuBudgetMs = 5,
	schedulerDelayMs = 100,
}

local FAST = {
	profile = "fast", batchUnits = 25, batchDelayMs = 75,
	maxMovesPerStep = 5, moveDelayMs = 150,
	inspectedPerStep = 100, indexItemsPerStep = 100, cpuBudgetMs = 5,
	schedulerDelayMs = 100,
}

local operationCache = {}
local cacheOrder = {}
local CACHE_TTL_MS = 60000
local MAX_CACHED_OPERATIONS = 256

local function nowMs()
	return getTimestampMs and getTimestampMs() or 0
end

local function clampInteger(value, minimum, maximum, fallback)
	local number = math.floor(tonumber(value) or fallback)
	return math.max(minimum, math.min(maximum, number))
end

local function copyProfile(source)
	local copy = {}
	for key, value in pairs(source) do copy[key] = value end
	return copy
end

local function requestedProfile()
	local value = GlobalStorageSiK.Sandbox.getLocalPerformanceProfile
		and GlobalStorageSiK.Sandbox.getLocalPerformanceProfile() or 1
	if value == 2 or value == "fast" then return "fast" end
	if value == 3 or value == "custom" then return "custom" end
	return "safe"
end

local function customProfile()
	local profile = {
		profile = "custom",
		batchUnits = clampInteger(GlobalStorageSiK.Sandbox.getLocalBatchUnits(), 1, 100, 10),
		batchDelayMs = clampInteger(GlobalStorageSiK.Sandbox.getLocalBatchDelayMs(), 0, 1000, 400),
		maxMovesPerStep = clampInteger(GlobalStorageSiK.Sandbox.getLocalAutoSortMovesPerStep(), 1, 20, 2),
		moveDelayMs = clampInteger(GlobalStorageSiK.Sandbox.getLocalAutoSortMoveDelayMs(), 0, 2000, 1000),
		inspectedPerStep = clampInteger(GlobalStorageSiK.Sandbox.getLocalInspectedPerStep(), 10, 500, 25),
		indexItemsPerStep = clampInteger(GlobalStorageSiK.Sandbox.getLocalInspectedPerStep(), 10, 500, 50),
		cpuBudgetMs = clampInteger(GlobalStorageSiK.Sandbox.getLocalCpuBudgetMs(), 1, 15, 5),
	}
	-- 0 no encadena un bucle: OnTick ejecuta como maximo un paso. Solo elimina
	-- la espera artificial entre turnos del planificador local.
	profile.schedulerDelayMs = math.min(100, profile.moveDelayMs)
	return profile
end

--- Resuelve una copia que el caller conserva durante toda la operacion.
---@param context table|nil reservado para diagnostico/tipo de operacion
---@return table pacing
function GlobalStorageSiK.OperationPacing.resolve(context)
	local requested = requestedProfile()
	local splitScreen = getNumActivePlayers and getNumActivePlayers() > 1
	local onlineHumans = 0
	if getOnlinePlayers then
		local players = getOnlinePlayers()
		onlineHumans = players and players.size and players:size() or 0
	end
	local multiplayer = splitScreen or onlineHumans > 1 or (GlobalStorageSiK.isMultiplayerActive
		and GlobalStorageSiK.isMultiplayerActive() == true)
	local pacing
	if multiplayer then
		pacing = copyProfile(SAFE)
		pacing.mode = "multiplayer_safe"
		pacing.effectiveProfile = "safe"
	elseif requested == "fast" then
		pacing = copyProfile(FAST)
		pacing.mode = "local_single_player"
		pacing.effectiveProfile = "fast"
	elseif requested == "custom" then
		pacing = customProfile()
		pacing.mode = "local_single_player"
		pacing.effectiveProfile = "custom"
	else
		pacing = copyProfile(SAFE)
		pacing.mode = "local_single_player"
		pacing.effectiveProfile = "safe"
	end
	pacing.requestedProfile = requested
	pacing.operationType = context and context.operationType or "unknown"
	return pacing
end

local function sweepCache(now)
	local kept = {}
	for i = 1, #cacheOrder do
		local key = cacheOrder[i]
		local entry = operationCache[key]
		if entry and now - entry.createdMs <= CACHE_TTL_MS then
			kept[#kept + 1] = key
		else
			operationCache[key] = nil
		end
	end
	cacheOrder = kept
	while #cacheOrder >= MAX_CACHED_OPERATIONS do
		local key = table.remove(cacheOrder, 1)
		operationCache[key] = nil
	end
end

--- Cache autoritativa acotada para microlotes correlacionados.
---@param key string
---@param context table|nil
---@return table pacing
function GlobalStorageSiK.OperationPacing.forOperation(key, context)
	if type(key) ~= "string" or key == "" then
		return GlobalStorageSiK.OperationPacing.resolve(context)
	end
	local now = nowMs()
	sweepCache(now)
	local entry = operationCache[key]
	if entry then return entry.pacing end
	local pacing = GlobalStorageSiK.OperationPacing.resolve(context)
	operationCache[key] = { pacing = pacing, createdMs = now }
	cacheOrder[#cacheOrder + 1] = key
	return pacing
end

function GlobalStorageSiK.OperationPacing.release(key)
	if type(key) ~= "string" then return end
	operationCache[key] = nil
	local kept = {}
	for i = 1, #cacheOrder do
		if cacheOrder[i] ~= key then kept[#kept + 1] = cacheOrder[i] end
	end
	cacheOrder = kept
end

function GlobalStorageSiK.OperationPacing.describe(pacing)
	pacing = pacing or SAFE
	return "mode=" .. tostring(pacing.mode)
		.. " requested=" .. tostring(pacing.requestedProfile)
		.. " effective=" .. tostring(pacing.effectiveProfile or pacing.profile)
		.. " batch=" .. tostring(pacing.batchUnits)
		.. " batchDelayMs=" .. tostring(pacing.batchDelayMs)
		.. " movesPerStep=" .. tostring(pacing.maxMovesPerStep)
		.. " moveDelayMs=" .. tostring(pacing.moveDelayMs)
		.. " inspectedPerStep=" .. tostring(pacing.inspectedPerStep)
		.. " cpuBudgetMs=" .. tostring(pacing.cpuBudgetMs)
		.. " schedulerDelayMs=" .. tostring(pacing.schedulerDelayMs)
end
