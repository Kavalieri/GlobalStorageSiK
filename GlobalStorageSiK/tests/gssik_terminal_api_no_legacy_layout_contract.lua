-- Public API regression: addon tabs cannot register imperative panel builders
-- or layout callbacks. Run from GlobalStorageSiK-Repo with Lua 5.1.

package.loaded["GSSiK_API"] = true
package.loaded["GS_PlayerUtils"] = true
package.loaded["GS_TerminalUI_Extensions"] = true

GSSiK = { API = {} }
local committed = 0
GlobalStorageSiK = {
	TerminalExtensions = {
		registerDefinition = function()
			committed = committed + 1
			return true, committed
		end,
		removeDefinitionIfGeneration = function() return true end,
	},
}

local path = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/GSSiK_API_Terminal.lua"
dofile(path)
local Terminal = assert(GSSiK.API.Terminal, "public Terminal API missing")

local legacyCases = {
	{
		key = "legacy-build-panel", titleKey = "IGUI_Test",
		module = { buildPanel = function() end },
	},
	{
		key = "legacy-layout", titleKey = "IGUI_Test",
		module = { buildPanel = function() end, layout = function() end },
	},
}

local violations = {}
for index = 1, #legacyCases do
	local ok, code, handle = Terminal.registerTab(legacyCases[index])
	if ok ~= false or code ~= "ERR_SCHEMA" or handle ~= nil then
		violations[#violations + 1] = legacyCases[index].key
	end
end

if committed ~= 0 then
	violations[#violations + 1] = "internal registry commits=" .. tostring(committed)
end
if #violations > 0 then
	error("Terminal.registerTab accepted legacy definitions: "
		.. table.concat(violations, ", "), 0)
end

print("gssik_terminal_api_no_legacy_layout_contract: OK")
