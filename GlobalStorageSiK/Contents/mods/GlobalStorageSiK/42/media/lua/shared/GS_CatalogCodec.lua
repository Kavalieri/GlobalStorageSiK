-- Private terminal transport codec. Values stay native (including doubles).
-- Compact tokens: native number/boolean, ":text", u table e, S fragments e.
-- Exact final7 negotiation additionally permits R/r schemas, dense arrays,
-- !id:text definitions and @id references, local to one bounded batch.
-- Decoder also accepts the 1.5.3 legacy n/b/s/t token format.
GlobalStorageSiK = GlobalStorageSiK or {}
local Codec = {}
GlobalStorageSiK.CatalogCodec = Codec
Codec.FRAME_BYTES = 24000
Codec.MAX_RESEARCH_FRAME_BYTES = 48000
Codec.MAX_BATCH_BYTES = 16 * 1024 * 1024
Codec.MAX_TOKENS = 500000
Codec.MAX_CHUNKS = 4096
Codec.MAX_DEPTH = 32
local PART_BYTES = 4096
local UTF16 = #"é" == 1
Codec.STRING_CACHE_BYTES = 256 * 1024
Codec.SCHEMA_CACHE_BYTES = 64 * 1024
Codec.TEXT_CACHE_BYTES = 256 * 1024

-- Count implicit keys as well as wire tokens. Compact records must not turn a
-- small wire body into an unaccounted replica allocation.
local function expand(state, count)
	local total=(state.expandedKeys or 0)+count
	if total+(state.expected or state.tokenCount)>Codec.MAX_TOKENS then error("catalog_budget",0) end
	if state.reserveExpanded and not state.reserveExpanded(total) then error("catalog_budget",0) end
	state.expandedKeys=total
end

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
	local size, chunkBytes = 4, 0
	for key, item in pairs(value) do
		if type(key) ~= "string" and type(key) ~= "number" then error("catalog_schema", 0) end
		local keyBytes = wireSize(key, depth + 1, active)
		local itemBytes = wireSize(item, depth + 1, active)
		if depth == 0 and key == "data" and item then chunkBytes = itemBytes end
		size = size + keyBytes + itemBytes
		if type(item) == "table" then size = size + 1 end
		if size > Codec.MAX_BATCH_BYTES then error("catalog_budget", 0) end
	end
	active[value] = nil
	return size, chunkBytes
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

-- One wire-size contract for final framing and both transport endpoints.
Codec.COMMAND_BYTES = 128
function Codec.frameSize(frame)
	local ok,payloadBytes,chunkBytes=pcall(wireSize,frame,0,{})
	if not ok then return nil,payloadBytes end
	return payloadBytes+Codec.COMMAND_BYTES,nil,chunkBytes,payloadBytes
end
function Codec.frame(envelope,data,part)
	local frame={}
	for key,value in pairs(envelope) do frame[key]=value end
	frame.data,frame.part=data,part
	return frame
end
function Codec.beginFraming(encoded,envelope,frameBytes)
	frameBytes=frameBytes or Codec.FRAME_BYTES
	if not integer(frameBytes,Codec.FRAME_BYTES,Codec.MAX_RESEARCH_FRAME_BYTES) then return nil,"catalog_budget" end
	local empty=Codec.frame(envelope,{},1)
	local bytes,reason=Codec.frameSize(empty)
	if not bytes then return nil,reason end
	local budget=frameBytes-bytes+4
	if budget<=4 then return nil,"catalog_frame_envelope" end
	local fits=encoded.chunkSizes and #encoded.chunkSizes==#encoded.chunks
	if fits then
		for i=1,#encoded.chunkSizes do if encoded.chunkSizes[i]>budget then fits=false;break end end
	end
	if fits then return {done=true,source={},chunks=encoded.chunks,chunkSizes=encoded.chunkSizes,totalBytes=encoded.totalBytes,
		tokenCount=encoded.tokenCount,work=0,budget=budget} end
	local chunk={}
	return {source=encoded.chunks,sourcePart=1,sourceAt=1,chunks={chunk},chunkSizes={4},chunk=chunk,
		chunkBytes=4,totalBytes=4,tokenCount=0,budget=budget,work=0}
end
function Codec.stepFraming(state,maxWork)
	if state.done then return {chunks=state.chunks,chunkSizes=state.chunkSizes,totalBytes=state.totalBytes,tokenCount=state.tokenCount},nil,true end
	local ok,reason=pcall(function()
		for i=1,maxWork do
			local source=state.source[state.sourcePart]
			if not source then state.done=true;return end
			local token=source[state.sourceAt]
			if token==nil then state.sourcePart=state.sourcePart+1;state.sourceAt=1
			else
				local cost=tokenCost(token)
				if cost+4>state.budget then error("catalog_frame_token",0) end
				if state.chunkBytes+cost>state.budget then
					if #state.chunks>=Codec.MAX_CHUNKS then error("catalog_budget",0) end
					state.chunk={};state.chunks[#state.chunks+1]=state.chunk
					state.chunkBytes=4;state.totalBytes=state.totalBytes+4
				end
				state.chunk[#state.chunk+1]=token
				state.chunkBytes=state.chunkBytes+cost;state.totalBytes=state.totalBytes+cost
				state.chunkSizes[#state.chunks]=state.chunkBytes
				state.tokenCount=state.tokenCount+1;state.sourceAt=state.sourceAt+1
				if state.totalBytes>Codec.MAX_BATCH_BYTES then error("catalog_budget",0) end
			end
			state.work=state.work+1
		end
	end)
	if not ok then return nil,reason,true end
	if state.done then return {chunks=state.chunks,chunkSizes=state.chunkSizes,totalBytes=state.totalBytes,tokenCount=state.tokenCount},nil,true end
	return nil,nil,false
end

local function emit(state, token, knownBytes)
	local cost = tokenCost(token, knownBytes)
	if cost + 4 > state.budget then error("catalog_budget", 0) end
	if state.chunkBytes + cost > state.budget then
		if #state.chunks >= Codec.MAX_CHUNKS then error("catalog_budget", 0) end
		state.chunk = {}
		state.chunks[#state.chunks + 1] = state.chunk
		state.chunkBytes = 4
		state.chunkSizes[#state.chunks]=4
		state.totalBytes = state.totalBytes + 4
	end
	state.chunk[#state.chunk + 1] = token
	state.chunkBytes = state.chunkBytes + cost
	state.chunkSizes[#state.chunks]=state.chunkBytes
	state.totalBytes = state.totalBytes + cost
	state.tokenCount = state.tokenCount + 1
	if state.totalBytes > Codec.MAX_BATCH_BYTES or state.tokenCount+(state.expandedKeys or 0) > Codec.MAX_TOKENS then
		error("catalog_budget", 0)
	end
end

local function pushValue(state, value, depth)
	state.stack[#state.stack + 1] = { kind = "value", value = value, depth = depth }
end

-- Already validated scalars/references need no stack frame or second action.
-- New strings and containers retain the incremental validator and depth fence.
local function pushChild(state,value,depth)
 if state.efficient then
  if finite(value) or type(value)=="boolean" then emit(state,value);return end
  if type(value)=="string" then
   local id=state.compactTables and state.texts[value]
   local cached=state.memo[value]
   if id then emit(state,"@"..tostring(id));return end
   if cached then emit(state,cached.token,cached.bytes+1);return end
  end
 end
 pushValue(state,value,depth)
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
			local textId=state.compactTables and state.texts[frame.value]
			local cached=state.memo[frame.value]
			if textId then
				emit(state,"@"..tostring(textId));state.stack[#state.stack]=nil
			elseif cached then
				emit(state,cached.token,cached.bytes+1);state.stack[#state.stack]=nil
			else
				frame.kind, frame.at, frame.startAt, frame.bytes = "string", 1, 1, 0
				frame.phase, frame.long = "scan", false
			end
		elseif kind == "table" then
			if frame.depth > Codec.MAX_DEPTH or state.active[frame.value] then error("catalog_schema", 0) end
			state.active[frame.value] = true
			frame.kind = state.compactTables and "shapeScan" or state.optimized and "arrayScan" or "table"
			frame.iterator, frame.subject, frame.key = pairs(frame.value)
			frame.count,frame.maximum=0,0
			frame.keys,frame.keyBytes,frame.dense,frame.record={},0,true,true
			if not state.optimized and not state.compactTables then emit(state, "u", 1) end
		else error("catalog_schema", 0) end
	elseif frame.kind == "shapeScan" then
		local key=frame.iterator(frame.subject,frame.key)
		if key~=nil then
			frame.key=key;frame.count=frame.count+1
   if state.efficient then
    if frame.count==1 then frame.candidate=state.shapeHints[key] end
    if frame.candidate and not frame.candidate.keySet[key] then frame.candidate=nil end
   end
			if integer(key,1,Codec.MAX_TOKENS) then frame.maximum=math.max(frame.maximum,key)
			else frame.dense=false end
			if type(key)=="string" and #key<=256 and frame.count<=128 then
				frame.keys[#frame.keys+1]=key;frame.keyBytes=frame.keyBytes+#key*4+160
			else frame.record=false end
			if not frame.record and not frame.dense then
				frame.kind="table";frame.iterator,frame.subject,frame.key=pairs(frame.value);emit(state,"u",1)
			end
		elseif frame.dense and frame.count>=3 and frame.count==frame.maximum then
			expand(state,frame.count);frame.kind,frame.index="array",0;emit(state,"a",1);emit(state,frame.count)
		elseif frame.record and frame.count>=2 then
			-- At most 128 short keys; the inventory traversal itself stays sliced.
			local schema=frame.candidate
   if schema and #schema.keys~=frame.count then schema=nil end
   local signature
   if not schema then
    table.sort(frame.keys)
    local parts={}
    for i=1,#frame.keys do parts[i]=tostring(#frame.keys[i])..":"..frame.keys[i] end
    signature=table.concat(parts);schema=state.schemas[signature]
   end
   -- The hint/set are batch-local and charged before allocation. A hint is
   -- usable only after every unique key and the exact cardinality match.
   local hintBytes=state.efficient and (frame.count*256+160) or 0
   if not schema and state.schemaCount<128 and state.schemaBytes+frame.keyBytes+#signature*4+hintBytes<=Codec.SCHEMA_CACHE_BYTES then
				state.schemaCount=state.schemaCount+1
				schema={id=state.schemaCount,keys=frame.keys};state.schemas[signature]=schema
				state.schemaBytes=state.schemaBytes+frame.keyBytes+#signature*4+hintBytes
    if state.efficient then
     schema.keySet={}
     for i=1,#schema.keys do local key=schema.keys[i];schema.keySet[key]=true;state.shapeHints[key]=schema end
    end
				frame.kind,frame.index="schemaKeys",0
				emit(state,"R",1);emit(state,schema.id);emit(state,frame.count)
			elseif schema then frame.kind,frame.index="record",0;emit(state,"r",1);emit(state,schema.id)
			else frame.kind="table";frame.iterator,frame.subject,frame.key=pairs(frame.value);emit(state,"u",1) end
			if schema then frame.keys=schema.keys;expand(state,frame.count) end
		else frame.kind="table";frame.iterator,frame.subject,frame.key=pairs(frame.value);emit(state,"u",1) end
	elseif frame.kind == "schemaKeys" then
		frame.index=frame.index+1
		if frame.index>frame.count then frame.kind,frame.index="record",0
		else local key=frame.keys[frame.index];emit(state,":"..key,textBytes(key)+1) end
	elseif frame.kind == "record" then
		frame.index=frame.index+1
		if frame.index>frame.count then state.active[frame.value]=nil;state.stack[#state.stack]=nil
		else pushChild(state,frame.value[frame.keys[frame.index]],frame.depth+1) end
	elseif frame.kind == "arrayScan" then
		-- Detection is incremental and charged to the same global work slice.
		local key=frame.iterator(frame.subject,frame.key)
		if key==nil then
			if frame.count>=3 and frame.count==frame.maximum then
				frame.kind,frame.index="array",0;emit(state,"a",1);emit(state,frame.count)
			else frame.kind="table";frame.iterator,frame.subject,frame.key=pairs(frame.value);emit(state,"u",1) end
		elseif not integer(key,1,Codec.MAX_TOKENS) then
			frame.kind="table";frame.iterator,frame.subject,frame.key=pairs(frame.value);emit(state,"u",1)
		else frame.key=key;frame.count=frame.count+1;frame.maximum=math.max(frame.maximum,key) end
	elseif frame.kind == "array" then
		frame.index=frame.index+1
		if frame.index>frame.count then state.active[frame.value]=nil;state.stack[#state.stack]=nil
		else pushChild(state,frame.value[frame.index],frame.depth+1) end
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
			-- Keys are scalar. Avoid a temporary stack frame when already validated.
			if state.optimized and finite(key) then emit(state,key)
			elseif state.optimized and state.memo[key] then
				local cached=state.memo[key];emit(state,cached.token,cached.bytes+1)
			else pushValue(state, key, frame.depth + 1) end
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
			local prefix=1
			local cost=160+#frame.value*4
			if state.compactTables and #frame.value>=24 and #frame.value<=2048 and state.textCount<2048
				and state.textBytes+cost<=Codec.TEXT_CACHE_BYTES then
				state.textCount=state.textCount+1;state.texts[frame.value]=state.textCount;state.textBytes=state.textBytes+cost
				local header="!"..tostring(state.textCount)..":"
				token=header..frame.value;prefix=#header
			end
			emit(state,token,frame.bytes+prefix)
			rememberString(state,frame.value,frame.bytes,":"..frame.value)
			state.stack[#state.stack] = nil
		elseif frame.phase == "endMarker" then
			emit(state, "e", 1)
			state.stack[#state.stack] = nil
		end
	end
	return #state.stack == 0
end

function Codec.beginEncode(value, budget,frameBytes,optimized,compactTables,efficient)
	frameBytes=frameBytes or Codec.FRAME_BYTES
	if not integer(frameBytes,Codec.FRAME_BYTES,Codec.MAX_RESEARCH_FRAME_BYTES)
		or not integer(budget, 4200,frameBytes) then return nil, "catalog_budget" end
	local chunk = {}
	local state = { mode = "encode", budget = budget, chunks = { chunk }, chunk = chunk,
		chunkBytes = 4, chunkSizes={4}, totalBytes = 4, tokenCount = 0, active = {}, stack = {},
		memo={},memoCount=0,memoBytes=0,optimized=optimized==true,compactTables=compactTables==true,
		efficient=efficient==true,shapeHints={},schemas={},schemaCount=0,schemaBytes=0,expandedKeys=0,texts={},textCount=0,textBytes=0 }
	pushValue(state, value, 0)
	return state
end

function Codec.stepEncode(state, maxWork,deadline)
	if type(state) ~= "table" or state.mode ~= "encode"
		or not integer(maxWork, 1, Codec.MAX_TOKENS) then return nil, "catalog_schema", true end
	if state.error then return nil, state.error, true end
	if state.result then return state.result, nil, true end
	local ok, reason = pcall(function()
		local work = 0
		if state.optimized or state.efficient then
			repeat
				work=work+1
				if encodeAction(state) then break end
			until work>=maxWork or (state.optimized and deadline and work%32==0 and getTimestampMs and getTimestampMs()>=deadline)
		else while work < maxWork and not encodeAction(state) do work = work + 1 end end
		state.workLastStep=work
		if #state.stack == 0 then
			state.result = { chunks = state.chunks, totalBytes = state.totalBytes,
				tokenCount = state.tokenCount,chunkSizes=state.chunkSizes,expandedKeys=state.expandedKeys }
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
			for i=1,((state.optimized or state.compactTables) and 32 or 1) do
				if scan.at>#scan.value then break end
				local following, cost = codepoint(scan.value, scan.at)
				scan.at, scan.bytes = following, scan.bytes + cost
				if scan.bytes > 32767 then error("catalog_string_size", 0) end
			end
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
		if check.bytes > state.frameBytes then error("catalog_budget", 0) end
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
		if frame.array or frame.keys then
			frame.index=frame.index+1;frame.value[frame.keys and frame.keys[frame.index] or frame.index]=value;frame.remaining=frame.remaining-1
			if frame.remaining==0 then state.stack[#state.stack]=nil;value=frame.value
			else return end
		elseif frame.expectKey then
			if type(value) ~= "string" and not finite(value) then error("catalog_schema", 0) end
			if frame.value[value] ~= nil then error("catalog_schema", 0) end
			frame.key, frame.expectKey = value, false
			return
		end
		if not frame.array and not frame.keys then
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
end

local function startTable(state, remaining,array,keys)
	if #state.stack + 1 > Codec.MAX_DEPTH + 1 then error("catalog_schema", 0) end
	if state.compactTables and (array or keys) then expand(state,remaining) end
	local frame = { value = {}, expectKey = true, remaining = remaining,array=array,keys=keys,index=0 }
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
	if state.schemaMode then
		local mode=state.schemaMode
		if mode.phase=="id" then
			if not integer(token,1,128) then error("catalog_schema",0) end
			mode.id=token
			if mode.definition then
				if token~=state.schemaCount+1 then error("catalog_schema",0) end
				mode.phase="count"
			else
				local keys=state.schemas[token]
				if not keys then error("catalog_schema",0) end
				state.schemaMode=nil;startTable(state,#keys,false,keys)
			end
		elseif mode.phase=="count" then
			if not integer(token,2,128) then error("catalog_schema",0) end
			mode.count,mode.keys,mode.phase=token,{},"keys"
		else
			if type(token)~="string" or string.sub(token,1,1)~=":" or #token>257 then error("catalog_schema",0) end
			local key=string.sub(token,2);local last=mode.keys[#mode.keys]
			if last and key<=last then error("catalog_schema",0) end
			state.schemaBytes=state.schemaBytes+160+#key*4
			if state.schemaBytes>Codec.SCHEMA_CACHE_BYTES then error("catalog_budget",0) end
			mode.keys[#mode.keys+1]=key
			if #mode.keys==mode.count then
				state.schemas[mode.id]=mode.keys;state.schemaCount=mode.id
				state.schemaMode=nil;startTable(state,mode.count,false,mode.keys)
			end
		end
		return
	end
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
		elseif mode == "table" or mode == "array" then
			if not integer(token, 0, Codec.MAX_TOKENS) then error("catalog_schema", 0) end
			startTable(state, token,mode=="array")
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
	elseif token == "a" and (state.optimized or state.compactTables) then state.rawMode = "array"
	elseif (token=="R" or token=="r") and state.compactTables then state.schemaMode={phase="id",definition=token=="R"}
	elseif string.sub(token,1,1)=="!" and state.compactTables then
		local separator=string.find(token,":",2,true)
		local id=separator and tonumber(string.sub(token,2,separator-1))
		if not integer(id,1,2048) or id~=state.textCount+1
			or string.sub(token,1,separator)~="!"..tostring(id)..":" then error("catalog_schema",0) end
		local text=string.sub(token,separator+1)
		if #text<24 or #text>2048 then error("catalog_schema",0) end
		state.textBytes=state.textBytes+160+#text*4
		if state.textBytes>Codec.TEXT_CACHE_BYTES then error("catalog_budget",0) end
		state.textCount=id;state.texts[id]=text;acceptValue(state,text)
	elseif string.sub(token,1,1)=="@" and state.compactTables then
		local id=tonumber(string.sub(token,2))
		if not integer(id,1,2048) or token~="@"..tostring(id) or not state.texts[id] then error("catalog_schema",0) end
		acceptValue(state,state.texts[id])
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

function Codec.beginDecode(chunks, expected,frameBytes,optimized,compactTables,reserveExpanded)
	frameBytes=frameBytes or Codec.FRAME_BYTES
	if not integer(frameBytes,Codec.FRAME_BYTES,Codec.MAX_RESEARCH_FRAME_BYTES) then return nil,"catalog_budget" end
	if type(chunks) ~= "table" or not integer(expected, 1, Codec.MAX_TOKENS) then
		return nil, "catalog_schema"
	end
	local iterator, subject, key = pairs(chunks)
	return { mode = "decode", chunks = chunks, expected = expected, phase = "outer",frameBytes=frameBytes,
		outerIterator = iterator, outerSubject = subject, outerKey = key,
		outerCount = 0, outerMaximum = 0, lengths = {}, validatedTokens = 0,
		totalBytes = 0, stack = {},memo={},memoCount=0,memoBytes=0,optimized=optimized==true,
		compactTables=compactTables==true,reserveExpanded=reserveExpanded,
		schemas={},schemaCount=0,schemaBytes=0,expandedKeys=0,texts={},textCount=0,textBytes=0 }
end

function Codec.stepDecode(state, maxWork,deadline)
	if type(state) ~= "table" or state.mode ~= "decode"
		or not integer(maxWork, 1, Codec.MAX_TOKENS) then return nil, "catalog_schema", true end
	if state.error then return nil, state.error, true end
	if state.done then return state.result, nil, true end
	local ok, reason = pcall(function()
		local work = 0
		while work < maxWork and not state.done do
			if state.phase == "parse" then parseAction(state) else validationAction(state) end
			work = work + 1
			if deadline and work%32==0 and getTimestampMs and getTimestampMs()>=deadline then break end
		end
		state.workLastStep=work
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
