-- Core 1.4.3-dev32.4.3: delayed search rereads current text and thresholds.
for _, name in ipairs({ "GS_I18n", "ISUI/ISButton", "ISUI/ISPanel", "ISUI/ISLabel",
	"GS_Libs", "GS_UIDebug", "GS_CraftUtils" }) do
	package.loaded[name] = true
end

local function utf8Codepoints(text, maxChars)
	local out, i = {}, 1
	while i <= #text and #out < (maxChars or 100000) do
		local b1 = string.byte(text, i)
		local cp, size = b1, 1
		if b1 >= 0xF0 and i + 3 <= #text then
			local b2, b3, b4 = string.byte(text, i + 1, i + 3)
			cp, size = (b1 - 0xF0) * 0x40000 + (b2 - 0x80) * 0x1000
				+ (b3 - 0x80) * 0x40 + (b4 - 0x80), 4
		elseif b1 >= 0xE0 and i + 2 <= #text then
			local b2, b3 = string.byte(text, i + 1, i + 2)
			cp, size = (b1 - 0xE0) * 0x1000 + (b2 - 0x80) * 0x40 + (b3 - 0x80), 3
		elseif b1 >= 0xC0 and i + 1 <= #text then
			local b2 = string.byte(text, i + 1)
			cp, size = (b1 - 0xC0) * 0x40 + (b2 - 0x80), 2
		end
		out[#out + 1] = cp
		i = i + size
	end
	return out
end

local now = 0
local pending = nil
getTimestampMs = function() return now end
Events = { OnTick = {
	Add = function(fn) pending = fn end,
	Remove = function(fn) if pending == fn then pending = nil end end,
} }
UIFont = { Small = "small" }
getTextManager = function()
	return { getFontHeight = function() return 12 end, MeasureStringX = function(_, _, text) return #text end }
end
ISButton, ISPanel, ISLabel = {}, {}, {}
GlobalStorageSiK = {
	I18n = { text = function(key) return key end },
	Libs = { unicodeCodepoints = utf8Codepoints },
	UIDebug = {}, CraftUtils = {},
	Log = { debug = function() end },
}

dofile("GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/GS_SiK_UI_Core.lua")

local entry = { text = "" }
function entry:getText() return self.text end
function entry:setPlaceholderText() end
local calls = {}
local panel = { onSearch = function(_, force)
	calls[#calls + 1] = { force = force, text = entry.text }
end }
GlobalStorageSiK.SiK_UI.bindSearchEntry(panel, entry)

local function advance(ms)
	now = now + ms
	local fn = pending
	if fn then fn() end
end

-- B42 can fire before the entry exposes the new value: schedule on "ab",
-- then publish "abc" before the debounce executes.
entry.text = "ab"
entry.onTextChange()
entry.text = "abc"
advance(180)
assert(#calls == 1 and calls[1].text == "abc" and calls[1].force == false,
	"ASCII 2->3 must apply at the third current character, not the stale callback value")

entry.text = "abcd"
entry.onTextChange()
advance(50)
entry.text = "abcde"
entry.onTextChange()
advance(179)
assert(#calls == 1, "rapid typing must remain debounced")
advance(1)
assert(#calls == 2 and calls[2].text == "abcde", "debounce must reread latest text")

entry.text = "ab"
entry.onTextChange()
advance(180)
assert(#calls == 3 and calls[3].text == "ab", "deleting below threshold restores full rows once")
entry.text = "a"
entry.onTextChange()
advance(180)
entry.text = ""
entry.onTextChange()
advance(180)
assert(#calls == 3, "continued deletion below threshold must not refresh repeatedly")

local accented = "b" .. string.char(0xC3, 0xAD) .. "d"
entry.text = accented
entry.onTextChange()
advance(180)
assert(#calls == 4 and calls[4].text == accented,
	"accented Latin text must use the three-character threshold")

entry.text = ""
entry.onTextChange()
advance(180)
local cjkOne = string.char(0xE6, 0xB1, 0xBD)
local cjkTwo = cjkOne .. string.char(0xE6, 0xB2, 0xB9)
entry.text = cjkOne
entry.onTextChange()
advance(180)
assert(#calls == 5, "one CJK character stays below its threshold")
entry.text = cjkTwo
entry.onTextChange()
advance(180)
assert(#calls == 6 and calls[6].text == cjkTwo,
	"two CJK characters activate without corrupting UTF-8 test bytes")

print("dev32_4_3_search_debounce_contract: OK")
