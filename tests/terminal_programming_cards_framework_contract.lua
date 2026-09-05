local passed, failed = 0, 0
local root = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/"

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

local cards = source("GS_TerminalRecipeCards.lua")
local programming = source("GS_TerminalUI_Programming.lua")
local programmingSurface = source("GlobalStorageSiK/UI/Generated/TabProgramming.lua")

local forbidden = {
	"ISPanel:new", "ISLabel:new", ".prerender = function",
	":drawRect(", ":drawRectBorder(", ":drawText(",
	":drawTexture", "GS_SiK_UI_", "GlobalStorageSiK.SiK_UI",
}

for _, entry in ipairs({ { "cards", cards } }) do
	local name, lua = entry[1], entry[2]
	check(name .. " binds only public UI facade",
		lua:find('require "GS_UI_Framework"', 1, true) ~= nil)
	for index = 1, #forbidden do
		local token = forbidden[index]
		check(name .. " excludes direct primitive " .. token,
			lua:find(token, 1, true) == nil, token)
	end
end

check("programming consumes generated SiK UI surface",
	programming:find('require "GlobalStorageSiK/UI/Generated/TabProgramming"', 1, true) ~= nil
	and programming:find('TerminalExtensions.registerDefinition("programming"', 1, true) ~= nil
	and programmingSurface:find('["type"] = "card-collection"', 1, true) ~= nil)
for index = 1, #forbidden do
	local token = forbidden[index]
	check("programming excludes direct primitive " .. token,
		programming:find(token, 1, true) == nil, token)
end

check("recipe card delegates all visible leaves",
	cards:find("UI.Controls.panel", 1, true) ~= nil
	and cards:find("UI.Controls.icon", 1, true) ~= nil
	and cards:find("UI.Controls.copyText", 1, true) ~= nil
	and cards:find("UI.Controls.button", 1, true) ~= nil
	and cards:find("UI.Scroll.addChild", 1, true) ~= nil)
check("recipe card preserves live data without paint hook",
	cards:find("findLiveRecipe", 1, true) ~= nil
	and cards:find("presentationSignature", 1, true) ~= nil
	and cards:find("card.update = function", 1, true) ~= nil
	and cards:find("card.craftBtn:setEnabled(canCraft)", 1, true) ~= nil)
check("recipe card preserves approved geometry",
	cards:find("local LINE_GAP = 4", 1, true) ~= nil
	and cards:find("local REQ_ICON = 28", 1, true) ~= nil
	and cards:find("local REQ_ICON_GAP = 8", 1, true) ~= nil
	and cards:find("local CRAFT_BTN_W = 148", 1, true) ~= nil)

check("programming supplies data, actions and refresh lifecycle",
	programming:find('GS_ProgramDiskAction:new', 1, true) ~= nil
	and programming:find('ISTimedActionQueue.add(action)', 1, true) ~= nil
	and programming:find("refreshIntervalMs = 1000", 1, true) ~= nil
	and programming:find("cards = cards", 1, true) ~= nil
	and programming:find("programReadiness(player, id)", 1, true) ~= nil
	and programming:find('variant = "output"', 1, true) ~= nil
	and programming:find("actionLabel = T(\"IGUI_GS_ProgrammingButton\")", 1, true) ~= nil)

io.write(string.format("RESULT %d passed, %d failed\n", passed, failed))
if failed > 0 then os.exit(1) end
