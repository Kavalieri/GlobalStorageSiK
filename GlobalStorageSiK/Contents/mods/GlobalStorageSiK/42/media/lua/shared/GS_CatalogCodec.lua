-- Private terminal transport codec. Values stay native (including doubles).
-- B42 TableNetworkUtils: table=count:int + typed key/value pairs; string=
-- type:byte + length:short + UTF-8. Kahlua indexes Java UTF-16, Lua 5.1 bytes.
GlobalStorageSiK = GlobalStorageSiK or {}
local Codec = {}
GlobalStorageSiK.CatalogCodec = Codec
Codec.FRAME_BYTES = 24000
Codec.MAX_BATCH_BYTES = 16 * 1024 * 1024
Codec.MAX_TOKENS = 500000
Codec.MAX_CHUNKS = 4096
Codec.MAX_DEPTH = 32
local UTF16 = #"é" == 1
local function finite(n)
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end
local function integer(n, minimum, maximum)
	return finite(n) and n == math.floor(n) and n >= minimum and n <= maximum
end
Codec.integer = integer

-- Return the next codepoint boundary and its actual UTF-8 wire cost.
local function codepoint(s, at)
	local a = string.byte(s, at)
	if UTF16 then
		if a < 128 then return at + 1, 1 end
		if a < 2048 then return at + 1, 2 end
		if a >= 55296 and a <= 56319 then
			local b = string.byte(s, at + 1)
			if not b or b < 56320 or b > 57343 then error("catalog_encoding", 0) end
			return at + 2, 4
		end
		if a >= 56320 and a <= 57343 then error("catalog_encoding", 0) end
		return at + 1, 3
	end
	if a < 128 then return at + 1, 1 end
	local width = a >= 194 and a <= 223 and 2
		or a >= 224 and a <= 239 and 3 or a >= 240 and a <= 244 and 4
	if not width or at + width - 1 > #s then error("catalog_encoding", 0) end
	for i = 1, width - 1 do
		local b = string.byte(s, at + i)
		if b < 128 or b > 191 then error("catalog_encoding", 0) end
	end
	local b = string.byte(s, at + 1)
	if (a == 224 and b < 160) or (a == 237 and b > 159)
		or (a == 240 and b < 144) or (a == 244 and b > 143) then error("catalog_encoding", 0) end
	return at + width, width
end

local function textBytes(s)
	local at, bytes = 1, 0
	while at <= #s do
		local following, cost = codepoint(s, at)
		at, bytes = following, bytes + cost
	end
	return bytes
end

local function wireSize(value, depth, active)
	local kind = type(value)
	if kind == "string" then
		local bytes = textBytes(value)
		if bytes > 32767 then error("catalog_string_size", 0) end
		return 3 + bytes
	elseif kind == "number" and finite(value) then return 9
	elseif kind == "boolean" then return 2
	elseif kind ~= "table" then error("catalog_schema", 0) end
	if depth > Codec.MAX_DEPTH or active[value] then error("catalog_schema", 0) end
	active[value] = true
	local size = 4
	for key, item in pairs(value) do
		if type(key) ~= "string" and type(key) ~= "number" then error("catalog_schema", 0) end
		size = size + wireSize(key, depth + 1, active) + wireSize(item, depth + 1, active)
		if type(item) == "table" then size = size + 1 end
		if size > Codec.MAX_BATCH_BYTES then error("catalog_budget", 0) end
	end
	active[value] = nil
	return size
end

-- Top-level table has no type marker; nested tables have one.
function Codec.size(value)
	local ok, result = pcall(wireSize, value, 0, {})
	if ok then return result end
	return nil, result
end

local function encodeValue(value, state, depth)
	if depth > Codec.MAX_DEPTH then error("catalog_schema", 0) end
	local function emit(token)
		local cost = 9 + wireSize(token, 0, {})
		if cost + 4 > state.budget then error("catalog_budget", 0) end
		if state.bytes + cost > state.budget then
			state.chunk = {}; state.bytes = 4
			state.chunks[#state.chunks + 1] = state.chunk
			state.totalBytes = state.totalBytes + 4
		end
		state.chunk[#state.chunk + 1] = token
		state.bytes = state.bytes + cost
		state.totalBytes = state.totalBytes + cost
		state.tokenCount = state.tokenCount + 1
		if state.totalBytes > Codec.MAX_BATCH_BYTES or state.tokenCount > Codec.MAX_TOKENS
			or #state.chunks > Codec.MAX_CHUNKS then error("catalog_budget", 0) end
	end
	local kind = type(value)
	if kind == "table" then
		if state.active[value] then error("catalog_schema", 0) end
		state.active[value] = true
		local keys = {}
		for key in pairs(value) do
			if type(key) ~= "string" and not finite(key) then error("catalog_schema", 0) end
			keys[#keys + 1] = key
			if #keys > Codec.MAX_TOKENS then error("catalog_budget", 0) end
		end
		emit("t"); emit(#keys)
		for i = 1, #keys do
			encodeValue(keys[i], state, depth + 1)
			encodeValue(value[keys[i]], state, depth + 1)
		end
		state.active[value] = nil
	elseif kind == "string" then
		-- Count UTF-8 and fragments before allocating copies. Kahlua offsets
		-- are UTF-16 units; neither offsets nor characters are a byte budget.
		local parts, at, bytes, total = 1, 1, 0, 0
		while at <= #value do
			local following, cost = codepoint(value, at)
			if bytes + cost > 4096 then parts, bytes = parts + 1, 0 end
			at, bytes = following, bytes + cost
			total = total + cost
			if state.totalBytes + total + parts * 12 + 31 > Codec.MAX_BATCH_BYTES
				or state.tokenCount + parts + 2 > Codec.MAX_TOKENS then error("catalog_budget", 0) end
		end
		emit("s"); emit(parts)
		local startAt = 1
		at, bytes = 1, 0
		while at <= #value do
			local following, cost = codepoint(value, at)
			if bytes + cost > 4096 then
				emit(string.sub(value, startAt, at - 1))
				startAt, bytes = at, 0
			end
			at, bytes = following, bytes + cost
		end
		emit(string.sub(value, startAt))
	elseif kind == "number" and finite(value) then emit("n"); emit(value)
	elseif kind == "boolean" then emit("b"); emit(value)
	else error("catalog_schema", 0) end
end

function Codec.encode(value, budget)
	if not integer(budget, 4200, Codec.FRAME_BYTES) then return nil, "catalog_budget" end
	local chunk = {}
	local state = {budget=budget, chunks={chunk}, chunk=chunk, bytes=4,
		totalBytes=4, tokenCount=0, active={}}
	local ok, reason = pcall(encodeValue, value, state, 0)
	if not ok then return nil, reason end
	return {chunks=state.chunks, totalBytes=state.totalBytes, tokenCount=state.tokenCount}
end

local function denseSize(values, maximum)
	if type(values) ~= "table" then error("catalog_schema", 0) end
	local count = 0
	for key in pairs(values) do
		if not integer(key, 1, maximum) then error("catalog_schema", 0) end
		count = count + 1
	end
	for i = 1, count do if values[i] == nil then error("catalog_schema", 0) end end
	return count
end

local function decodeValue(take, depth)
	if depth > Codec.MAX_DEPTH then error("catalog_schema", 0) end
	local kind = take()
	if kind == "n" then
		local number = take()
		if not finite(number) then error("catalog_schema", 0) end
		return number
	elseif kind == "b" then
		local boolean = take()
		if type(boolean) ~= "boolean" then error("catalog_schema", 0) end
		return boolean
	elseif kind == "s" then
		local count = take()
		if not integer(count, 1, Codec.MAX_TOKENS) then error("catalog_schema", 0) end
		local parts = {}
		for i = 1, count do
			parts[i] = take()
			if type(parts[i]) ~= "string" or textBytes(parts[i]) > 4096 then error("catalog_schema", 0) end
		end
		return table.concat(parts)
	elseif kind == "t" then
		local count = take()
		if not integer(count, 0, Codec.MAX_TOKENS) then error("catalog_schema", 0) end
		local result = {}
		for _ = 1, count do
			local key = decodeValue(take, depth + 1)
			if type(key) ~= "string" and not finite(key) then error("catalog_schema", 0) end
			if result[key] ~= nil then error("catalog_schema", 0) end
			result[key] = decodeValue(take, depth + 1)
		end
		return result
	end
	error("catalog_schema", 0)
end

local function decode(chunks, expected)
	if not integer(expected, 1, Codec.MAX_TOKENS) then error("catalog_schema", 0) end
	local count = denseSize(chunks, Codec.MAX_CHUNKS)
	local tokens, bytes, lengths = 0, 0, {}
	for i = 1, count do
		lengths[i] = denseSize(chunks[i], Codec.MAX_TOKENS)
		tokens = tokens + lengths[i]
		local size = wireSize(chunks[i], 0, {})
		if size > Codec.FRAME_BYTES then error("catalog_budget", 0) end
		bytes = bytes + size
		if bytes > Codec.MAX_BATCH_BYTES or tokens > expected then error("catalog_budget", 0) end
	end
	if tokens ~= expected then error("catalog_incomplete", 0) end
	local part, index, consumed = 1, 0, 0
	local function take()
		index = index + 1
		while part <= count and index > lengths[part] do part, index = part + 1, 1 end
		if part > count then error("catalog_incomplete", 0) end
		consumed = consumed + 1
		return chunks[part][index]
	end
	local result = decodeValue(take, 0)
	if consumed ~= expected or type(result) ~= "table" then error("catalog_schema", 0) end
	return result
end

function Codec.decode(chunks, expected)
	local ok, result = pcall(decode, chunks, expected)
	if ok then return result end
	return nil, result
end
return Codec
