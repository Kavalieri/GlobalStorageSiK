local clientRoot = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/"

local function read(path)
	local file = assert(io.open(path, "rb"))
	local source = file:read("*a")
	file:close()
	return source
end

local files = {}
local command = package.config:sub(1, 1) == "\\"
	and ('dir /s /b "' .. clientRoot:gsub("/", "\\") .. '*.lua"')
	or ('find "' .. clientRoot .. '" -type f -name "*.lua"')
local pipe = assert(io.popen(command))
for path in pipe:lines() do files[#files + 1] = path:gsub("\\", "/") end
pipe:close()

for index = 1, #files do
	local source = read(files[index])
	assert(not source:find("setHaloNote", 1, true),
		"direct setHaloNote outside SiK.UI adapter: " .. files[index])
	assert(not source:find("HaloTextHelper", 1, true),
		"direct HaloTextHelper outside SiK.UI adapter: " .. files[index])
end

local adapter = read(clientRoot .. "GS_UI_Feedback.lua")
assert(adapter:find('require "GS_UI_Framework"', 1, true))
assert(adapter:find("UI.Feedback.halo", 1, true))
assert(adapter:find("registerTransientCleanup", 1, true))
assert(adapter:find('policy = options.policy or "replace"', 1, true),
	"product bridge must preserve the former display-every-call default")

local items = read(clientRoot .. "GS_TerminalUI_Items.lua")
assert(items:find('variant = "transient"', 1, true))
assert(items:find('channel = "warehouse-item"', 1, true))
assert(not items:find("_gsTooltipAttached", 1, true))

io.write("PASS sik ui feedback boundary contract\n")
