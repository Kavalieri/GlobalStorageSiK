-- Technical PZ/Kahlua runtime smoke runner. Execute with the game's Lua host,
-- after GS_CatalogCodec is on the normal shared require path.
GlobalStorageSiK = GlobalStorageSiK or {}
local Codec = assert(CATALOG_CODEC)
local function check(value, message) if not value then error(message, 2) end end
local function equal(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for key, value in pairs(a) do if not equal(value, b[key]) then return false end end
  for key, value in pairs(b) do if not equal(value, a[key]) then return false end end
  return true
end

local value = {
  text = "inicio-é-東京-🚀-fin",
  boundary = string.rep("é東京🚀", 900),
  surrogatePair = "😀😃😄😁",
  values = { false, true, -0.25, empty = "", sparse = { [1] = "a", [3] = "c" } },
}
local encoded = assert(Codec.encode(value, Codec.FRAME_BYTES))
local decoded, reason = Codec.decode(encoded.chunks, encoded.tokenCount)
check(decoded ~= nil and equal(value, decoded), "Kahlua Unicode round-trip failed: " .. tostring(reason))
local long = { text = string.rep("長い文字列🚀", 5000) }
local size, sizeReason = Codec.size(long)
check(size == nil and sizeReason == "catalog_string_size", "Kahlua native short limit changed")
local longEncoded = assert(Codec.encode(long, Codec.FRAME_BYTES))
local longDecoded = assert(Codec.decode(longEncoded.chunks, longEncoded.tokenCount))
check(equal(long, longDecoded), "Kahlua segmented long string changed")
print("catalog_transport_kahlua_runner: PASS native Unicode, UTF-8 boundaries, segmented long string")
