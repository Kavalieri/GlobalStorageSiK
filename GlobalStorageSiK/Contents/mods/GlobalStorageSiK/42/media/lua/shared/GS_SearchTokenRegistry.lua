-- Optional search evidence. No provider is installed by Core and no timer runs.
GlobalStorageSiK = GlobalStorageSiK or {}
require "GS_CatalogManager"
local Registry = {}
GlobalStorageSiK.SearchTokenRegistry = Registry
local providers, ordered = {}, {}
local revision, generation = 0, 0
local cache, cacheCount, cacheEpoch = {}, 0, nil
local resolving = false

local function resetCache(stamp)
	cache, cacheCount, cacheEpoch = {}, 0, stamp
	local catalog = GlobalStorageSiK.CatalogManager
	if catalog and catalog.registerFullTypeCache then
		catalog.registerFullTypeCache("search-provider-tokens", cache, 1)
	end
end

local function epoch()
	local catalog = GlobalStorageSiK.CatalogManager
	local content = catalog and catalog.getEpoch and catalog.getEpoch() or 0
	local language = catalog and catalog.getLanguageEpoch and catalog.getLanguageEpoch() or 0
	return tostring(content) .. ":" .. tostring(language), content, language
end

local function invalidate()
	revision = revision + 1
	resetCache(nil)
	ordered = {}
	for _, provider in pairs(providers) do ordered[#ordered + 1] = provider end
	table.sort(ordered, function(a, b)
		if a.priority ~= b.priority then return a.priority > b.priority end
		return a.id < b.id
	end)
end

function Registry.revision() return revision end

function Registry.register(definition)
	if resolving then return false, "ERR_BUSY" end
	if type(definition) ~= "table" or getmetatable(definition) ~= nil then return false, "ERR_SCHEMA" end
	local id, priority = definition.id, definition.priority or 0
	if type(id) ~= "string" or #id < 1 or #id > 64
		or not string.match(id, "^[a-zA-Z0-9][a-zA-Z0-9_.%-]*$")
		or type(definition.resolve) ~= "function" or type(priority) ~= "number"
		or priority ~= priority or priority ~= math.floor(priority) or math.abs(priority) > 1000 then
		return false, "ERR_SCHEMA"
	end
	for key in pairs(definition) do
		if key ~= "id" and key ~= "priority" and key ~= "resolve" then return false, "ERR_SCHEMA" end
	end
	if not providers[id] and #ordered >= 16 then return false, "ERR_CAPACITY" end
	generation = generation + 1
	local current = generation
	providers[id] = { id = id, priority = priority, resolve = definition.resolve, generation = current }
	invalidate()
	local handle = { id = id }
	function handle:dispose()
		if resolving then return false end
		local provider = providers[id]
		if not provider or provider.generation ~= current then return false end
		providers[id] = nil
		invalidate()
		return true
	end
	return true, "OK", handle
end

local function copyTokens(tokens)
	local result = {}
	for index = 1, #tokens do result[index] = tokens[index] end
	return result
end

local function checkedTokens(value, normalize)
	if type(value) ~= "table" or getmetatable(value) ~= nil then return nil end
	local count, total = 0, 0
	for key, token in pairs(value) do
		if type(key) ~= "number" or key ~= math.floor(key) or key < 1 or key > 16
			or type(token) ~= "string" or #token < 1 or #token > 128 then return nil end
		count, total = count + 1, total + #token
		if total > 1024 then return nil end
	end
	if count ~= #value then return nil end
	local tokens = {}
	for index = 1, count do
		local token = normalize(value[index])
		if type(token) ~= "string" or #token > 128 then return nil end
		tokens[#tokens + 1] = token
	end
	return tokens
end

-- Internal consumer gets copied tokens; providers see only copied plain text.
-- Exceptions and malformed output quarantine that provider for this epoch.
function Registry.resolve(fullType, displayName, normalize)
	if #ordered == 0 or resolving or type(normalize) ~= "function" then return {} end
	if type(fullType) ~= "string" or #fullType > 160 or not fullType:match("^[^%.%s%c]+%.[^%s%c]+$")
		or type(displayName) ~= "string" or #displayName > 2048 then return {} end
	local stamp, contentEpoch, languageEpoch = epoch()
	if cacheEpoch ~= stamp then resetCache(stamp) end
	local key = fullType .. "\1" .. displayName
	if cache[key] then return copyTokens(cache[key]) end
	local result, seen = {}, {}
	resolving = true
	for index = 1, #ordered do
		local provider = ordered[index]
		if provider.failedEpoch ~= stamp then
			local ok, value = pcall(provider.resolve, { fullType = fullType, displayName = displayName,
				catalogEpoch = contentEpoch, languageEpoch = languageEpoch })
			local valid, tokens = false, nil
			if ok then valid, tokens = pcall(checkedTokens, value, normalize) end
			if not valid or not tokens then
				provider.failedEpoch = stamp
			else
				for tokenIndex = 1, #tokens do
					local token = tokens[tokenIndex]
					if token ~= "" and not seen[token] and #result < 64 then
						seen[token] = true
						result[#result + 1] = token
					end
				end
			end
		end
	end
	resolving = false
	if cacheCount >= 4096 then resetCache(stamp) end
	cache[key], cacheCount = result, cacheCount + 1
	return copyTokens(result)
end

return Registry
