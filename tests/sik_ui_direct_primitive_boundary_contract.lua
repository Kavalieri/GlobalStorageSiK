-- Boundary inventory for visible Project Zomboid primitives that still live in
-- Core product consumers.  These are migration bridges, not proof that the UI
-- is fully framework-owned.  Any addition or silent movement fails this gate;
-- reductions are accepted so a neutral migration is never penalised.

local function quote(path)
	return '"' .. tostring(path):gsub('"', '\\"') .. '"'
end

local function read(path)
	local file = assert(io.open(path, "rb"), "cannot read " .. path)
	local text = file:read("*a")
	file:close()
	return text
end

local function list(root)
	local pipe = assert(io.popen("dir /b /s " .. quote(root .. "\\*.lua") .. " 2>nul"))
	local files = {}
	for path in pipe:lines() do files[#files + 1] = path:gsub("\\", "/") end
	pipe:close()
	table.sort(files)
	return files
end

local function countPlain(text, needle)
	local count, start = 0, 1
	while true do
		local found = string.find(text, needle, start, true)
		if not found then return count end
		count = count + 1
		start = found + #needle
	end
end

local function countPrerenderDefinitions(text)
	local count = 0
	for _ in string.gmatch(text, "function%s+[%w_%.]+:prerender%s*%(") do
		count = count + 1
	end
	for _ in string.gmatch(text, "[%w_%.]+%.prerender%s*=%s*function%s*%(") do
		count = count + 1
	end
	return count
end

local ROOT = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client"

-- Exact file/symbol ownership.  `bridge` identifies the public SiK.UI piece
-- already consumed around the vanilla leaf, or the product bridge that must be
-- replaced only after its exact HTML surface is validated.
local allowed = {}

local byFile = {}
local keys = {}
for key, entry in pairs(allowed) do
	assert(not byFile[entry.file], "duplicate primitive boundary file " .. entry.file)
	byFile[entry.file] = entry
	keys[#keys + 1] = key
end
table.sort(keys)

local fields = {
	{ key = "panel", needle = "ISPanel:new" },
	{ key = "label", needle = "ISLabel:new" },
	{ key = "combo", needle = "ISComboBox:new" },
	{ key = "list", needle = "ISScrollingListBox:new" },
	{ key = "button", needle = "ISButton:new" },
	{ key = "draw", needle = ":drawRect(" },
	{ key = "border", needle = ":drawRectBorder(" },
}

local retiredModules = {
	{ file = "GS_TerminalUI_NetworkList.lua", module = "GS_TerminalUI_NetworkList",
		symbol = "TerminalNetworkList" },
	{ file = "GS_TerminalUI_NetworkStatus.lua", module = "GS_TerminalUI_NetworkStatus",
		symbol = "TerminalNetworkStatus" },
}
for index = 1, #retiredModules do
	local retired = retiredModules[index]
	local handle = io.open(ROOT .. "/" .. retired.file, "rb")
	if handle then handle:close() end
	assert(not handle, "retired UI module still exists " .. retired.file)
end

local observedFiles = 0
for _, path in ipairs(list(ROOT)) do
	local fileName = path:match("([^/]+)$")
	local source = read(path)
	local executable = source:gsub("%-%-%[%[.-%]%]", ""):gsub("%-%-[^\r\n]*", "")
	for index = 1, #retiredModules do
		local retired = retiredModules[index]
		assert(not executable:find('require%s*["\']' .. retired.module),
			"runtime requires retired UI module " .. retired.module .. " in " .. path)
		assert(not executable:find(retired.symbol .. "[%.:]"),
			"runtime calls retired UI symbol " .. retired.symbol .. " in " .. path)
	end
	assert(not source:find("require%s*[\"']SiK/UI/"),
		"consumer imports standalone internal module directly " .. path)
	assert(not source:find("require%s*%(%s*[\"']SiK/UI/"),
		"consumer imports standalone internal module directly " .. path)
	assert(not source:find("GlobalStorageSiK%.SiK_UI"),
		"consumer uses removed private namespace " .. path)
	local entry = byFile[fileName]
	local hasPrimitive = false
	for index = 1, #fields do
		local field = fields[index]
		local count = countPlain(source, field.needle)
		if count > 0 then hasPrimitive = true end
		if entry then
			assert(count <= (entry[field.key] or 0), fileName .. " " .. field.key
				.. " allowed_max=" .. tostring(entry[field.key] or 0)
				.. " actual=" .. tostring(count))
		else
			assert(count == 0, "new direct primitive " .. field.needle .. " in " .. path)
		end
	end
	local prerender = countPrerenderDefinitions(source)
	if prerender > 0 then hasPrimitive = true end
	if entry then
		assert(prerender <= (entry.prerender or 0), fileName .. " prerender allowed_max="
			.. tostring(entry.prerender or 0) .. " actual=" .. tostring(prerender))
	elseif hasPrimitive then
		assert(false, "unowned visible primitive file " .. path)
	else
		assert(prerender == 0, "new product prerender in " .. path)
	end
	if entry then observedFiles = observedFiles + 1 end
end

assert(observedFiles == #keys, "primitive boundary allowlist contains missing files")

for index = 1, #keys do
	local entry = allowed[keys[index]]
	print("DIRECT_UI_BRIDGE\t" .. entry.file .. "\t" .. entry.symbols
		.. "\t" .. entry.bridge)
end

print("sik_ui_direct_primitive_boundary_contract: OK files=" .. tostring(observedFiles)
	.. " direct_buttons=0 surface_id=tab-options")
