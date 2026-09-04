-- Advisory discovery for public SiK.UI ownership and product consumers.
-- Emits stable, grep-friendly records; it never edits product or framework.

local function quote(path)
	return '"' .. tostring(path):gsub('"', '\\"') .. '"'
end

local function read(path)
	local file = io.open(path, "rb")
	if not file then return "" end
	local text = file:read("*a"); file:close(); return text
end

local function list(root)
	local pipe = assert(io.popen("dir /b /s " .. quote(root .. "\\*.lua") .. " 2>nul"))
	local files = {}
	for path in pipe:lines() do files[#files + 1] = path:gsub("\\", "/") end
	pipe:close(); table.sort(files); return files
end

local CORE = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client"
local ADDONS = "addons"
local FRAMEWORK = "../SiKUIFramework-Repo/SiKUIFramework/Contents/mods/SiKUIFramework/42/media/lua/client"
local files = {}
for _, root in ipairs({ CORE, ADDONS, FRAMEWORK }) do
	for _, path in ipairs(list(root)) do files[#files + 1] = path end
end

local counts = { framework = 0, consumer = 0, directPz = 0, privateRef = 0 }
local forbiddenPrefix = "GS_" .. "SiK_UI"
local forbiddenNamespace = "GlobalStorageSiK." .. "SiK_UI"

for _, path in ipairs(files) do
	local normalized = path:gsub("\\", "/")
	-- Product discovery covers runtime sources only. Test fixtures intentionally
	-- quote forbidden symbols and construct vanilla stubs; counting them here
	-- produced false runtime findings for every official addon.
	if not normalized:find("/tests/", 1, true) then
		local text = read(path)
		local isFramework = normalized:find("/SiK/UI/", 1, true)
			or normalized:match("/SiK_UI%.lua$")
		if isFramework then
			counts.framework = counts.framework + 1
		elseif text:find('require "GS_UI_Framework"', 1, true)
			or text:find('require "SiK/UI/', 1, true) then
			counts.consumer = counts.consumer + 1
		end

		if not isFramework and (text:find("ISPanel:new", 1, true)
			or text:find("ISButton:new", 1, true)
			or text:find("ISScrollingListBox:new", 1, true)) then
			counts.directPz = counts.directPz + 1
			print("DIRECT_PZ_UI\tREVIEW\t" .. normalized)
		end
		if text:find(forbiddenPrefix, 1, true) or text:find(forbiddenNamespace, 1, true) then
			counts.privateRef = counts.privateRef + 1
			print("PRIVATE_UI_REF\tHIGH\t" .. normalized)
		end
	end
end

local entry = read(FRAMEWORK .. "/SiK_UI.lua")
assert(entry:find('require "SiK/UI/Surface"', 1, true), "public entrypoint misses Surface")
assert(entry:find("return UI", 1, true), "public entrypoint does not return SiK.UI")
for _, moduleName in ipairs({ "Window", "Modal", "Block", "Controls", "Table",
	"VirtualList", "FocusStack", "State", "Metrics", "Viewport" }) do
	local source = read(FRAMEWORK .. "/SiK/UI/" .. moduleName .. ".lua")
	assert(source ~= "", "public module missing: " .. moduleName)
	assert(source:find('SiK.UI.Namespace.define("' .. moduleName .. '"', 1, true),
		"public module has no exact namespace owner: " .. moduleName)
end

print("SURFACE_DISCOVERY\tframework=" .. counts.framework
	.. "\tconsumers=" .. counts.consumer
	.. "\tdirect_pz_review=" .. counts.directPz
	.. "\tprivate_refs=" .. counts.privateRef)
print("sik_ui_surface_inventory_discovery: OK remaining_private_refs="
	.. counts.privateRef .. " (advisory; see PRIVATE_UI_REF records)")
