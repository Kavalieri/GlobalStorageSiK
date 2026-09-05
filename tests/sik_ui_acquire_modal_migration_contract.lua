local root = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/"

local passed, failed = 0, 0
local function check(name, condition, detail)
	if condition then
		passed = passed + 1
		io.write("PASS ", name, "\n")
	else
		failed = failed + 1
		io.write("FAIL ", name, ": ", tostring(detail), "\n")
	end
end

local function source(name)
	local file = assert(io.open(root .. name, "rb"))
	local value = file:read("*a")
	file:close()
	return value
end

local files = {
	"GS_QuantityPrompt.lua",
	"GS_PCAcquireUI.lua",
	"GS_ReaderAcquireUI.lua",
	"GS_TerminalInstallReaderChoice.lua",
}

for index = 1, #files do
	local name = files[index]
	local lua = source(name)
	check(name .. " uses standalone binding",
		lua:find('require "GS_UI_Framework"', 1, true) ~= nil)
	check(name .. " has no embedded UI dependency",
		lua:find("GS_SiK_UI_", 1, true) == nil
		and lua:find("GlobalStorageSiK.SiK_UI", 1, true) == nil)
end

local quantity = source("GS_QuantityPrompt.lua")
check("quantity uses typed validating modal input",
	quantity:find("UI.Modal.input", 1, true) ~= nil
	and quantity:find("numeric = true", 1, true) ~= nil
	and quantity:find("validate = function", 1, true) ~= nil
	and quantity:find("onCancel = options.onClose", 1, true) ~= nil)

for _, name in ipairs({ "GS_PCAcquireUI.lua", "GS_ReaderAcquireUI.lua" }) do
	local lua = source(name)
	check(name .. " composes public task modal and requirements",
		lua:find("UI.Modal.apply", 1, true) ~= nil
		and lua:find("UI.Requirements.create", 1, true) ~= nil
		and lua:find("UI.Controls.button", 1, true) ~= nil
		and lua:find("UI.Modal.fitContent", 1, true) ~= nil)
	check(name .. " is owner-scoped and explicitly fixed-size",
		lua:find("owner = self.modalOwner", 1, true) ~= nil
		and lua:find("resizable = false", 1, true) ~= nil
		and lua:find("setAlwaysOnTop", 1, true) == nil)
end

local blocked = source("GS_TerminalUI_BlockedPanel.lua")
local acquireCallStart = assert(blocked:find("GlobalStorageSiK.PCAcquireUI.show(", 1, true),
	"blocked panel lost the PC acquire modal call")
local acquireCall = blocked:sub(acquireCallStart, acquireCallStart + 300)
check("blocked panel passes its terminal as modal owner",
	acquireCall:find("terminal", 1, true) ~= nil)

local terminalApi = source("GS_TerminalUI_Api.lua")
local blockedApi = source("GS_TerminalUI_Blocked.lua")
check("terminal refresh cannot steal z-order from an owned modal",
	terminalApi:find("state and state.openUi == true", 1, true) ~= nil
	and terminalApi:find("payload and payload.openUi == true", 1, true) ~= nil
	and terminalApi:find("UI.Modal.raiseOwner(ui)", 1, true) ~= nil
	and terminalApi:find("ui:bringToTop()", 1, true) == nil
	and blockedApi:find("state and state.openUi == true", 1, true) ~= nil
	and blockedApi:find("UI.Modal.raiseOwner(ui)", 1, true) ~= nil
	and blockedApi:find("ui:bringToTop()", 1, true) == nil)

local choice = source("GS_TerminalInstallReaderChoice.lua")
check("reader choice uses public controls only",
	choice:find("UI.Controls.field", 1, true) ~= nil
	and choice:find("UI.Controls.combo", 1, true) ~= nil
	and choice:find("UI.Controls.sectionTitle", 1, true) ~= nil
	and choice:find("UI.Controls.status", 1, true) ~= nil)

io.write(string.format("RESULT %d passed, %d failed\n", passed, failed))
if failed > 0 then os.exit(1) end
