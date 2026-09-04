local root = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/"

local function read(path)
	local file = assert(io.open(path, "rb"))
	local text = file:read("*a")
	file:close()
	return text
end

local blocked = read(root .. "GS_TerminalUI_BlockedPanel.lua")
local addons = read(root .. "GS_AddonManageUI.lua")
local block = read("../SiKUIFramework-Repo/SiKUIFramework/Contents/mods/SiKUIFramework/42/media/lua/client/SiK/UI/Block.lua")

assert(not string.find(blocked, "UI.Card.create", 1, true),
	"blocked composite content must use Block, never atomic Card")
assert(not string.find(addons, "UI.Card.create", 1, true),
	"addon requirement composition must use Block, never atomic Card")
assert(string.find(blocked, "UI.Block.create", 1, true)
	and string.find(addons, "UI.Block.create", 1, true),
	"both composite consumers must originate in the shared Block primitive")
assert(string.find(blocked, "contentHost = true", 1, true)
	and string.find(addons, "contentHost = true", 1, true),
	"composite consumers must request the explicit Block content host")
assert(string.find(block, "function BlockInstance:reflow", 1, true),
	"Block must expose the common compositional reflow contract")
assert(not string.find(blocked, "btn:setTooltip", 1, true)
	and not string.find(addons, "actionBtn:setTooltip", 1, true),
	"framework controls must not assume an optional vanilla tooltip method")
assert(string.find(blocked, "UI.Controls.setTooltip", 1, true)
	and string.find(addons, "UI.Controls.setTooltip", 1, true),
	"both composite consumers must use the shared tooltip contract")

print("sik_ui_card_atomicity_consumers_contract: OK")
