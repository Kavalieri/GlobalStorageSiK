local root = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/"

local function read(path)
	local file = assert(io.open(path, "rb"), path)
	local text = file:read("*a")
	file:close()
	return text
end

-- Product UI must consume the SiK UI tooltip contract. A vanilla-looking
-- test stub may expose setTooltip even when the actual PZ widget does not, so
-- direct method calls are forbidden on every active UI surface.
local consumers = {
	"GS_AdminDashboard.lua",
	"GS_AddonManageUI.lua",
	"GS_TerminalUI.lua",
	"GS_TerminalUI_BlockedPanel.lua",
	"GS_TerminalUI_NodeEditor.lua",
	"GS_TerminalUI_Nodes.lua",
	"GS_TerminalUI_Programming.lua",
	"GS_TerminalUI_ZoneEditor.lua",
}

for index = 1, #consumers do
	local name = consumers[index]
	local source = read(root .. name)
	assert(not string.find(source, ":setTooltip(", 1, true),
		name .. " bypasses SiK.UI.Controls.setTooltip")
end

local controls = read("../SiKUIFramework-Repo/SiKUIFramework/Contents/mods/SiKUIFramework/42/media/lua/client/SiK/UI/Controls.lua")
assert(string.find(controls, "function Controls.setTooltip", 1, true),
	"the public control tooltip bridge must exist")

print("sik_ui_public_component_consumer_boundary_contract: OK")
