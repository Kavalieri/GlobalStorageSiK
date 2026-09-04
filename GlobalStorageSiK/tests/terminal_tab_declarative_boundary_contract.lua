-- Authorial boundary: active product tabs are declarative surface adapters.
-- They provide a generated artifact and a pure context, and never compose or
-- position framework widgets directly. Run from GlobalStorageSiK-Repo.

local function read(path)
	local handle = assert(io.open(path, "rb"), "cannot read " .. path)
	local source = handle:read("*a")
	handle:close()
	return source
end

local function codeOnly(source)
	source = source:gsub("%-%-%[%[.-%]%]", "")
	local lines = {}
	for line in (source .. "\n"):gmatch("(.-)\n") do
		lines[#lines + 1] = line:gsub("%-%-.*$", "")
	end
	return table.concat(lines, "\n")
end

local tabs = {
	{ id = "warehouse", path = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/GS_TerminalUI_Items.lua" },
	{ id = "network", path = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/GS_TerminalUI_Network.lua" },
	{ id = "options", path = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/GS_TerminalUI_Options.lua" },
	{ id = "addons", path = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/GS_TerminalUI_Addons.lua" },
	{ id = "craft", path = "addons/GSSiK_Addon_Craft/Contents/mods/GSSiK_Addon_Craft/42/media/lua/client/GSSiK_Addon_Craft_TerminalUI.lua" },
	{ id = "builder", path = "addons/GSSiK_Addon_Builder/Contents/mods/GSSiK_Addon_Builder/42/media/lua/client/GSSiK_Addon_Builder_TerminalUI.lua" },
}

local forbidden = {
	{ label = "UI.Controls", pattern = "UI%.Controls" },
	{ label = "UI.Scroll", pattern = "UI%.Scroll" },
	{ label = "UI.Table", pattern = "UI%.Table" },
	{ label = "UI.Card", pattern = "UI%.Card" },
	{ label = "setBounds", pattern = ":setBounds%s*%(" },
	{ label = "setX", pattern = ":setX%s*%(" },
	{ label = "setY", pattern = ":setY%s*%(" },
	{ label = "setWidth", pattern = ":setWidth%s*%(" },
	{ label = "setHeight", pattern = ":setHeight%s*%(" },
	{ label = "addChild", pattern = ":addChild%s*%(" },
}

local violations = {}
local function violation(id, reason)
	violations[#violations + 1] = id .. ": " .. reason
end

for index = 1, #tabs do
	local tab = tabs[index]
	local source = codeOnly(read(tab.path))
	if not source:find('require%s+["\'].-/Generated/') then
		violation(tab.id, "missing generated surface declaration")
	end
	if not source:find('require%s+["\'].-/UI/.-Context["\']')
		and not source:find('require%s+["\'].-/.-Context["\']') then
		violation(tab.id, "missing pure context declaration")
	end
	local builds = 0
	for _ in source:gmatch("SiK%.UI%.buildSurface%s*%(") do builds = builds + 1 end
	if builds ~= 1 then
		violation(tab.id, "expected exactly one SiK.UI.buildSurface call, got " .. tostring(builds))
	end
	for forbiddenIndex = 1, #forbidden do
		local entry = forbidden[forbiddenIndex]
		if source:find(entry.pattern) then violation(tab.id, "direct " .. entry.label) end
	end
end

if #violations > 0 then
	error("declarative tab boundary failed:\n - " .. table.concat(violations, "\n - "), 0)
end

print("terminal_tab_declarative_boundary_contract: OK tabs=" .. tostring(#tabs))
