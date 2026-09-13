-- Private terminal transport codec. Values stay native (including doubles).
-- Compact tokens: native number/boolean, ":text", u table e, S fragments e.
-- Decoder also accepts the 1.5.3 legacy n/b/s/t token format.
GlobalStorageSiK = GlobalStorageSiK or {}
local Codec = {}
GlobalStorageSiK.CatalogCodec = Codec
Codec.FRAME_BYTES = 24000
Codec.MAX_BATCH_BYTES = 16 * 1024 * 1024
Codec.MAX_TOKENS = 500000
Codec.MAX_CHUNKS = 4096
Codec.MAX_DEPTH = 32
local PART_BYTES = 4096
local UTF16 = #"é" == 1
Codec.STRING_CACHE_BYTES = 256 * 1024

local function rememberString(state,value,bytes,token)
	local cost=160+#value*4
	if #value<=256 and state.memoCount<2048 and state.memoBytes+cost<=Codec.STRING_CACHE_BYTES then
		state.memo[value]={bytes=bytes,token=token}
		state.memoCount=state.memoCount+1;state.memoBytes=state.memoBytes+cost
	end
end

local function finite(n)
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end
local function integer(n, low, high)
	return finite(n) and n == math.floor(n) and n >= low and n <= high
end
Codec.integer = integer

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

function Codec.size(value)
	local ok, result = pcall(wireSize, value, 0, {})
	if ok then return result end
	return nil, result
end

local function tokenCost(token, knownBytes)
	local kind = type(token)
	if kind == "string" then return 12 + (knownBytes or textBytes(token)) end
	if kind == "number" and finite(token) then return 18 end
	if kind == "boolean" then return 11 end
	error("catalog_schema", 0)
end

local function emit(state, token, knownBytes)
	local cost = tokenCost(token, knownBytes)
	if cost + 4 > state.budget then error("catalog_budget", 0) end
	if state.chunkBytes + cost > state.budget then
		if #state.chunks >= Codec.MAX_CHUNKS then error("catalog_budget", 0) end
		state.chunk = {}
		state.chunks[#state.chunks + 1] = state.chunk
		state.chunkBytes = 4
		state.totalBytes = state.totalBytes + 4
	end
	state.chunk[#state.chunk + 1] = token
	state.chunkBytes = state.chunkBytes + cost
	state.totalBytes = state.totalBytes + cost
	state.tokenCount = state.tokenCount + 1
	if state.totalBytes > Codec.MAX_BATCH_BYTES or state.tokenCount > Codec.MAX_TOKENS then
		error("catalog_budget", 0)
	end
end

local function pushValue(state, value, depth)
	state.stack[#state.stack + 1] = { kind = "value", value = value, depth = depth }
end

local function encodeAction(state)
	local frame = state.stack[#state.stack]
	if not frame then return true end
	if frame.kind == "value" then
		local kind = type(frame.value)
		if kind == "number" and finite(frame.value) then
			emit(state, frame.value); state.stack[#state.stack] = nil
		elseif kind == "boolean" then
			emit(state, frame.value); state.stack[#state.stack] = nil
		elseif kind == "string" then
			local cached=state.memo[frame.value]
			if cached then
				emit(state,cached.token,cached.bytes+1);state.stack[#state.stack]=nil
			else
				frame.kind, frame.at, frame.startAt, frame.bytes = "string", 1, 1, 0
				frame.phase, frame.long = "scan", false
			end
		elseif kind == "table" then
			if frame.depth > Codec.MAX_DEPTH or state.active[frame.value] then error("catalog_schema", 0) end
			state.active[frame.value] = true
			frame.kind = "table"
			frame.iterator, frame.subject, frame.key = pairs(frame.value)
			emit(state, "u", 1)
		else error("catalog_schema", 0) end
	elseif frame.kind == "table" then
		local key, value = frame.iterator(frame.subject, frame.key)
		if key == nil then
			emit(state, "e", 1)
			state.active[frame.value] = nil
			state.stack[#state.stack] = nil
		else
			if type(key) ~= "string" and not finite(key) then error("catalog_schema", 0) end
			frame.key = key
			pushValue(state, value, frame.depth + 1)
			pushValue(state, key, frame.depth + 1)
		end
	elseif frame.kind == "string" then
		if frame.phase == "scan" then
			if frame.at > #frame.value then
				if frame.long then
					frame.pending, frame.pendingBytes = string.sub(frame.value, frame.startAt), frame.bytes
					frame.phase = "finalFragment"
				else frame.phase = "short" end
			else
				-- UTF validation stays exact, but one ASCII/codepoint must not
				-- consume an entire scheduler work slot. Fragment boundaries yield.
				for i=1,32 do
					if frame.at>#frame.value then break end
					local following, cost = codepoint(frame.value, frame.at)
					if frame.bytes + cost > PART_BYTES then
						frame.pending = string.sub(frame.value, frame.startAt, frame.at - 1)
						frame.pendingBytes, frame.startAt, frame.bytes = frame.bytes, frame.at, 0
						if not frame.long then frame.long, frame.phase = true, "startMarker"
						else frame.phase = "fragment" end
						break
					else frame.at, frame.bytes = following, frame.bytes + cost end
				end
			end
		elseif frame.phase == "startMarker" then
			emit(state, "S", 1); frame.phase = "fragment"
		elseif frame.phase == "fragment" or frame.phase == "finalFragment" then
			emit(state, ":" .. frame.pending, frame.pendingBytes + 1)
			frame.pending = nil
			if frame.phase == "finalFragment" then frame.phase = "endMarker"
			else frame.phase = "scan" end
		elseif frame.phase == "short" then
			local token=":"..frame.value
			emit(state,token,frame.bytes+1)
			rememberString(state,frame.value,frame.bytes,token)
			state.stack[#state.stack] = nil
		elseif frame.phase == "endMarker" then
			emit(state, "e", 1)
			state.stack[#state.stack] = nil
		end
	end
	return #state.stack == 0
end

function Codec.beginEncode(value, budget)
	if not integer(budget, 4200, Codec.FRAME_BYTES) then return nil, "catalog_budget" end
	local chunk = {}
	local state = { mode = "encode", budget = budget, chunks = { chunk }, chunk = chunk,
		chunkBytes = 4, totalBytes = 4, tokenCount = 0, active = {}, stack = {},
		memo={},memoCount=0,memoBytes=0 }
	pushValue(state, value, 0)
	return state
end

function Codec.stepEncode(state, maxWork)
	if type(state) ~= "table" or state.mode ~= "encode"
		or not integer(maxWork, 1, Codec.MAX_TOKENS) then return nil, "catalog_schema", true end
	if state.error then return nil, state.error, true end
	if state.result then return state.result, nil, true end
	local ok, reason = pcall(function()
		local work = 0
		while work < maxWork and not encodeAction(state) do work = work + 1 end
		if #state.stack == 0 then
			state.result = { chunks = state.chunks, totalBytes = state.totalBytes,
				tokenCount = state.tokenCount }
		end
	end)
	if not ok then state.error = reason; return nil, reason, true end
	if state.result then return state.result, nil, true end
	return nil, nil, false
end

function Codec.encode(value, budget)
	local state, reason = Codec.beginEncode(value, budget)
	if not state then return nil, reason end
	while true do
		local result, stepReason, done = Codec.stepEncode(state, 4096)
		if done then return result, stepReason end
	end
end

local function beginChunk(state)
	if state.chunkIndex > state.chunkCount then
		if state.validatedTokens ~= state.expected then error("catalog_incomplete", 0) end
		state.phase, state.part, state.index, state.consumed = "parse", 1, 0, 0
		return
	end
	local chunk = state.chunks[state.chunkIndex]
	if type(chunk) ~= "table" then error("catalog_schema", 0) end
	local iterator, subject, key = pairs(chunk)
	state.chunkValidation = { iterator = iterator, subject = subject, key = key,
		count = 0, maximum = 0, bytes = 4 }
end

local function validationAction(state)
	if state.phase == "outer" then
		local key = state.outerIterator(state.outerSubject, state.outerKey)
		if key == nil then
			if state.outerCount == 0 or state.outerCount ~= state.outerMaximum then error("catalog_schema", 0) end
			state.chunkCount, state.chunkIndex, state.phase = state.outerCount, 1, "chunks"
			beginChunk(state)
		else
			if not integer(key, 1, Codec.MAX_CHUNKS) then error("catalog_schema", 0) end
			state.outerKey, state.outerCount = key, state.outerCount + 1
			if key > state.outerMaximum then state.outerMaximum = key end
		end
		return
	end
	if state.scanToken then
		local scan = state.scanToken
		if scan.at <= #scan.value then
			local following, cost = codepoint(scan.value, scan.at)
			scan.at, scan.bytes = following, scan.bytes + cost
			if scan.bytes > 32767 then error("catalog_string_size", 0) end
		else
			state.chunkValidation.bytes = state.chunkValidation.bytes + 12 + scan.bytes
			rememberString(state,scan.value,scan.bytes)
			state.scanToken = nil
		end
		return
	end
	local check = state.chunkValidation
	local key, token = check.iterator(check.subject, check.key)
	if key == nil then
		if check.count ~= check.maximum then error("catalog_schema", 0) end
		if check.bytes > Codec.FRAME_BYTES then error("catalog_budget", 0) end
		state.totalBytes = state.totalBytes + check.bytes
		state.validatedTokens = state.validatedTokens + check.count
		if state.totalBytes > Codec.MAX_BATCH_BYTES or state.validatedTokens > state.expected
			or state.validatedTokens > Codec.MAX_TOKENS then error("catalog_budget", 0) end
		state.lengths[state.chunkIndex] = check.count
		state.chunkIndex = state.chunkIndex + 1
		beginChunk(state)
		return
	end
	if not integer(key, 1, Codec.MAX_TOKENS) then error("catalog_schema", 0) end
	local kind = type(token)
	if kind ~= "string" and kind ~= "boolean" and not (kind == "number" and finite(token)) then
		error("catalog_schema", 0)
	end
	check.key, check.count = key, check.count + 1
	if key > check.maximum then check.maximum = key end
	if kind == "string" then
		local cached=state.memo[token]
		if cached then check.bytes=check.bytes+12+cached.bytes
		else state.scanToken = { value = token, at = 1, bytes = 0 } end
	elseif kind == "number" then check.bytes = check.bytes + 18
	else check.bytes = check.bytes + 11 end
end

local function nextToken(state)
	state.index = state.index + 1
	while state.part <= state.chunkCount and state.index > state.lengths[state.part] do
		state.part, state.index = state.part + 1, 1
	end
	if state.part > state.chunkCount then error("catalog_incomplete", 0) end
	state.consumed = state.consumed + 1
	return state.chunks[state.part][state.index]
end

local function acceptValue(state, value)
	while true do
		local frame = state.stack[#state.stack]
		if not frame then
			if state.result ~= nil then error("catalog_schema", 0) end
			state.result = value
			return
		end
		if frame.expectKey then
			if type(value) ~= "string" and not finite(value) then error("catalog_schema", 0) end
			if frame.value[value] ~= nil then error("catalog_schema", 0) end
			frame.key, frame.expectKey = value, false
			return
		end
		frame.value[frame.key] = value
		frame.key, frame.expectKey = nil, true
		if frame.remaining then
			frame.remaining = frame.remaining - 1
			if frame.remaining == 0 then
				state.stack[#state.stack] = nil
				value = frame.value
			else return end
		else return end
	end
end

local function startTable(state, remaining)
	if #state.stack + 1 > Codec.MAX_DEPTH + 1 then error("catalog_schema", 0) end
	local frame = { value = {}, expectKey = true, remaining = remaining }
	if remaining == 0 then acceptValue(state, frame.value)
	else state.stack[#state.stack + 1] = frame end
end

local function parseAction(state)
	if state.result ~= nil then
		if state.consumed ~= state.expected or #state.stack ~= 0 or type(state.result) ~= "table" then
			error("catalog_schema", 0)
		end
		state.done = true
		return
	end
	local token = nextToken(state)
	if state.stringMode then
		local mode = state.stringMode
		if mode.remaining then
			if type(token) ~= "string" then error("catalog_schema", 0) end
			mode.parts[#mode.parts + 1] = token
			mode.remaining = mode.remaining - 1
			if mode.remaining == 0 then state.stringMode = nil; acceptValue(state, table.concat(mode.parts)) end
		elseif token == "e" then
			state.stringMode = nil
			acceptValue(state, table.concat(mode.parts))
		elseif type(token) == "string" and string.sub(token, 1, 1) == ":" then
			mode.parts[#mode.parts + 1] = string.sub(token, 2)
		else error("catalog_schema", 0) end
		return
	end
	if state.rawMode then
		local mode = state.rawMode
		state.rawMode = nil
		if mode == "number" then
			if not finite(token) then error("catalog_schema", 0) end
			acceptValue(state, token)
		elseif mode == "boolean" then
			if type(token) ~= "boolean" then error("catalog_schema", 0) end
			acceptValue(state, token)
		elseif mode == "table" then
			if not integer(token, 0, Codec.MAX_TOKENS) then error("catalog_schema", 0) end
			startTable(state, token)
		elseif mode == "string" then
			if not integer(token, 1, Codec.MAX_TOKENS) then error("catalog_schema", 0) end
			state.stringMode = { remaining = token, parts = {} }
		end
		return
	end
	local kind = type(token)
	if kind == "number" then acceptValue(state, token)
	elseif kind == "boolean" then acceptValue(state, token)
	elseif kind ~= "string" then error("catalog_schema", 0)
	elseif string.sub(token, 1, 1) == ":" then acceptValue(state, string.sub(token, 2))
	elseif token == "n" then state.rawMode = "number"
	elseif token == "b" then state.rawMode = "boolean"
	elseif token == "t" then state.rawMode = "table"
	elseif token == "s" then state.rawMode = "string"
	elseif token == "S" then state.stringMode = { parts = {} }
	elseif token == "u" then startTable(state, nil)
	elseif token == "e" then
		local frame = state.stack[#state.stack]
		if not frame or frame.remaining ~= nil or not frame.expectKey then error("catalog_schema", 0) end
		state.stack[#state.stack] = nil
		acceptValue(state, frame.value)
	else error("catalog_schema", 0) end
end

function Codec.beginDecode(chunks, expected)
	if type(chunks) ~= "table" or not integer(expected, 1, Codec.MAX_TOKENS) then
		return nil, "catalog_schema"
	end
	local iterator, subject, key = pairs(chunks)
	return { mode = "decode", chunks = chunks, expected = expected, phase = "outer",
		outerIterator = iterator, outerSubject = subject, outerKey = key,
		outerCount = 0, outerMaximum = 0, lengths = {}, validatedTokens = 0,
		totalBytes = 0, stack = {},memo={},memoCount=0,memoBytes=0 }
end

function Codec.stepDecode(state, maxWork)
	if type(state) ~= "table" or state.mode ~= "decode"
		or not integer(maxWork, 1, Codec.MAX_TOKENS) then return nil, "catalog_schema", true end
	if state.error then return nil, state.error, true end
	if state.done then return state.result, nil, true end
	local ok, reason = pcall(function()
		local work = 0
		while work < maxWork and not state.done do
			if state.phase == "parse" then parseAction(state) else validationAction(state) end
			work = work + 1
		end
	end)
	if not ok then state.error = reason; return nil, reason, true end
	if state.done then return state.result, nil, true end
	return nil, nil, false
end

function Codec.decode(chunks, expected)
	local state, reason = Codec.beginDecode(chunks, expected)
	if not state then return nil, reason end
	while true do
		local result, stepReason, done = Codec.stepDecode(state, 4096)
		if done then return result, stepReason end
	end
end

return Codec
