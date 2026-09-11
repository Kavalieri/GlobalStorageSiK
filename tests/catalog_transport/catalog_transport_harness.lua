-- Core 1.5.3-dev1: CatalogCodec transport harness.
-- Authorial harness: deliberately loads the real codec; no production mocks.
local CODEC_PATH = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/GS_CatalogCodec.lua"
GlobalStorageSiK = {}
local Codec = assert(dofile(CODEC_PATH))

local passed, failed = 0, 0
local function check(condition, message)
  if condition then passed = passed + 1 else failed = failed + 1; io.stderr:write("FAIL: " .. message .. "\n") end
end
local function equal(a, b, seen)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  seen = seen or {}
  if seen[a] == b then return true end
  seen[a] = b
  for k, v in pairs(a) do if not equal(v, b[k], seen) then return false end end
  for k, v in pairs(b) do if not equal(v, a[k], seen) then return false end end
  return true
end
local function expectError(label, fn)
  local value, reason = fn()
  check(value == nil and type(reason) == "string", label .. " must reject with a reason")
end

-- Independent TableNetworkUtils-style accounting over the token arrays.
local function utf8Bytes(s)
  -- Lua 5.1 strings carry UTF-8 bytes; Java's UTF-8 wire length is the same
  -- byte count for the valid text used by these fixtures.
  return #s
end
local function wirePrimitive(v)
  local t = type(v)
  if t == "string" then return 3 + utf8Bytes(v)
  elseif t == "number" then return 9
  elseif t == "boolean" then return 2
  elseif t == "table" then
    local n = 4
    for k, value in pairs(v) do n = n + wirePrimitive(k) + wirePrimitive(value) end
    return 1 + n
  end
  error("oracle unsupported " .. t)
end
local function oracleChunkBytes(chunk)
  local n = 4
  for i = 1, #chunk do n = n + 9 + wirePrimitive(chunk[i]) end
  return n
end
local function oracleTotal(chunks)
  local n = 0
  for i = 1, #chunks do n = n + oracleChunkBytes(chunks[i]) end
  return n
end

local function roundTrip(label, value, budget)
  local expectedSize, sizeReason = Codec.size(value)
  check(expectedSize ~= nil, label .. " size rejected: " .. tostring(sizeReason))
  local encoded, reason = Codec.encode(value, budget or Codec.FRAME_BYTES)
  check(encoded ~= nil, label .. " encode rejected: " .. tostring(reason))
  if not encoded then return end
  check(encoded.totalBytes == oracleTotal(encoded.chunks), label .. " codec byte count disagrees with independent oracle")
  check(encoded.totalBytes <= Codec.MAX_BATCH_BYTES, label .. " exceeds batch cap")
  for i = 1, #encoded.chunks do check(oracleChunkBytes(encoded.chunks[i]) <= Codec.FRAME_BYTES, label .. " frame " .. i .. " exceeds cap") end
  check(encoded.tokenCount > 0, label .. " emitted no tokens")
  local decoded, decodeReason = Codec.decode(encoded.chunks, encoded.tokenCount)
  check(decoded ~= nil, label .. " decode rejected: " .. tostring(decodeReason))
  if decoded then check(equal(value, decoded), label .. " round-trip changed value") end
  return encoded
end

local function row(i)
  local zone = ((i - 1) % 64) + 1
  return {
    id = "item-" .. i, zoneId = "zona-" .. zone,
    name = "Artículo español №" .. i .. " 東京 🚀 café",
    description = string.rep("Descripción larga: ñ 東京 🚀 ", 22),
    quantity = i + 0.25, enabled = (i % 3 ~= 0), empty = "",
    tags = { "ES", "中文", "emoji🚀", sparse = true },
  }
end

local catalog = { version = "1.5.3-dev1", rows = {}, nodes = {}, zones = {} }
for i = 1, 1500 do catalog.rows[i] = row(i) end
for i = 1, 64 do
  catalog.nodes[i] = { id = "node-" .. i, zoneId = "zona-" .. i, x = i + 0.5, y = i * 2, z = i % 3, online = i % 2 == 0 }
  catalog.zones[i] = { id = "zona-" .. i, name = (i % 2 == 0 and "Almacén 東京 " or "Zona 🚀 ") .. i, nodes = { i, i + 0.5 } }
end
catalog.flags = { falseValue = false, empty = "", sparse = { [1] = "first", [3] = "third" } }

local expectedMonolithic = Codec.size(catalog)
check(expectedMonolithic ~= nil and expectedMonolithic > 1024 * 1024, "monolithic fixture should exceed 1 MiB")
local encoded = roundTrip("catalog", catalog, Codec.FRAME_BYTES)
check(encoded and #encoded.chunks > 1, "large catalog must be chunked")
check(encoded and encoded.totalBytes == oracleTotal(encoded.chunks), "chunked total must use independent oracle")

roundTrip("unicode-boundary", { text = string.rep("é東京🚀", 1300), scalar = -3.125, bool = false })
roundTrip("scalars-and-sparse", { n = 0, negative = -0.5, truth = true, falseValue = false, empty = "", sparse = { [1] = "a", [3] = "c" } })

local long = string.rep("長い文字列🚀", 5000)
local longValue = { text = long }
local longSize, longReason = Codec.size(longValue)
check(longSize == nil and longReason == "catalog_string_size", "monolithic long string must expose native short limit")
local longEncoded, longEncodeReason = Codec.encode(longValue, Codec.FRAME_BYTES)
check(longEncoded ~= nil, "segmented long string rejected: " .. tostring(longEncodeReason))
if longEncoded then
  local longDecoded, longDecodeReason = Codec.decode(longEncoded.chunks, longEncoded.tokenCount)
  check(longDecoded ~= nil and equal(longValue, longDecoded), "segmented long string was not preserved: " .. tostring(longDecodeReason))
end

local deep = {}; local cursor = deep
for i = 1, Codec.MAX_DEPTH + 1 do cursor.next = {}; cursor = cursor.next end
expectError("depth", function() return Codec.size(deep) end)
expectError("depth encode", function() return Codec.encode(deep, Codec.FRAME_BYTES) end)
local cycle = {}; cycle.self = cycle
expectError("cycle", function() return Codec.size(cycle) end)
expectError("cycle encode", function() return Codec.encode(cycle, Codec.FRAME_BYTES) end)
expectError("function", function() return Codec.size({ value = function() end }) end)
expectError("nan", function() return Codec.size({ value = 0 / 0 }) end)
expectError("infinity", function() return Codec.size({ value = math.huge }) end)

expectError("duplicate decoded key", function() return Codec.decode({ { "t", 2, "s", 1, "x", "s", 1, "y", "s", 1, "x" } }, 11) end)
expectError("missing token", function() return Codec.decode({ { "t", 0 } }, 1) end)
expectError("extra token", function() return Codec.decode({ { "t", 0, "n", 1 } }, 4) end)
expectError("sparse chunks", function() return Codec.decode({ [1] = { "t", 0 }, [3] = { "n", 1 } }, 2) end)
expectError("malformed primitive", function() return Codec.decode({ { "t", 1, "x", 1 } }, 4) end)

io.write(string.format("catalog_transport_harness: %d passed, %d failed\n", passed, failed))
if failed > 0 then os.exit(1) end
