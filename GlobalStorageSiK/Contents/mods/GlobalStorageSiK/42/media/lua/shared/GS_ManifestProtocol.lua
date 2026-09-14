-- Small manifest records; snapshots travel in independently acknowledged blocks.
require "GS_Config"
local Protocol = { SCHEMA = 1, MAX_NODES = 8192, MAX_REQUEST_NODES = 64 }
GlobalStorageSiK.ManifestProtocol = Protocol
Protocol.METADATA_FIELDS={"networkName","configEpoch","routingRevision","powered","fuelConsumption",
	"scan","scanActive","scanStatus","zones","terminals","nodes","permissions","redistributeActive",
	"craftProbe","capacity","proximityRange","wirelessRange","readLoans","installedAddons",
	"craftTabEnabled","buildTabEnabled","networks","activeNetworkId","categories"}

function Protocol.integer(value, minimum, maximum)
	return type(value) == "number" and value == value and value >= minimum
		and value <= maximum and value == math.floor(value)
end

function Protocol.id(value)
	return type(value) == "string" and #value > 0 and #value <= 512
end

function Protocol.part(value)
	local text = tostring(value)
	return tostring(#text) .. ":" .. text
end

function Protocol.key(epoch, playerNum, networkId, scope)
	return Protocol.part(epoch) .. Protocol.part(playerNum)
		.. Protocol.part(networkId) .. Protocol.part(scope)
end

function Protocol.sameBlock(a, b)
	return a and b and a.nodeId == b.nodeId and a.zoneId == b.zoneId
		and a.revision == b.revision and a.schema == b.schema and a.signature == b.signature
		and a.confirmed == b.confirmed
end

function Protocol.record(value)
	if type(value) ~= "table" or getmetatable(value) ~= nil
		or not Protocol.id(value.nodeId) or not Protocol.id(value.zoneId)
		or not Protocol.integer(value.revision, 0, 9007199254740991)
		or not Protocol.integer(value.schema, 0, Protocol.SCHEMA)
		or not Protocol.integer(value.units, 0, 2147483647)
		or not Protocol.integer(value.rows, 0, 500000)
		or type(value.weight) ~= "number" or value.weight ~= value.weight
		or value.weight < 0 or value.weight >= math.huge
		or type(value.enabled) ~= "boolean" or type(value.confirmed) ~= "boolean"
		or not Protocol.id(value.availability)
		or (value.confirmed and (value.schema ~= Protocol.SCHEMA or not Protocol.id(value.signature))) then return nil end
	return {nodeId=value.nodeId, zoneId=value.zoneId, revision=value.revision,
		schema=value.schema, signature=value.signature, units=value.units, rows=value.rows,
		weight=value.weight, enabled=value.enabled, confirmed=value.confirmed,
		availability=value.availability}
end

function Protocol.records(values)
	if type(values) ~= "table" or getmetatable(values) ~= nil then return nil end
	local count, records, byId = 0, {}, {}
	for key in pairs(values) do
		if not Protocol.integer(key, 1, Protocol.MAX_NODES) then return nil end
		count = count + 1
	end
	for i = 1, count do
		local record = Protocol.record(values[i])
		if not record or byId[record.nodeId] then return nil end
		records[i], byId[record.nodeId] = record, record
	end
	return records, byId
end

-- Configuration-only identity. Never pass inventory rows or unit details here.
function Protocol.metadataSignature(value)
	local fields,bytes,active=0,0,{}
	local function visit(v,depth)
		fields=fields+1
		if fields>200000 or depth>16 then return nil end
		local kind=type(v)
		if kind~="table" then
			if kind~="string" and kind~="number" and kind~="boolean" and kind~="nil" then return nil end
			if kind=="number" and (v~=v or v==math.huge or v==-math.huge) then return nil end
			local encoded=kind..Protocol.part(v);bytes=bytes+#encoded
			if bytes>4*1024*1024 then return nil end
			return encoded
		end
		if getmetatable(v)~=nil or active[v] then return nil end
		active[v]=true
		local parts={}
		for k,child in pairs(v) do
			if type(k)~="string" and type(k)~="number" then return nil end
			local key,encoded=visit(k,depth+1),visit(child,depth+1)
			if not key or not encoded then return nil end
			parts[#parts+1]=key..encoded
		end
		table.sort(parts);active[v]=nil
		return "{"..table.concat(parts).."}"
	end
	return visit(value,0)
end

return Protocol
