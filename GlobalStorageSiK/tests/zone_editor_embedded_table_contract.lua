-- ZoneEditor tables must be physically embedded in the caller-owned block.
local path = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/GS_TerminalUI_ZoneEditor.lua"
local source = assert(io.open(path, "rb")):read("*a")
assert(source:find("UI.Table.create({", 1, true), "ZoneEditor no longer creates its container table")
assert(source:find("parent = containersColumn.parent, x = 0, y = 0, embedded = true,", 1, true),
	"ZoneEditor table must use the real embedded contract")
assert(not source:find("embedded = false", 1, true), "ZoneEditor contains a forbidden fake non-embedded table")
print("PASS ZoneEditor embedded table contract")
