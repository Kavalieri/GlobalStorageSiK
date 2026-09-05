-- Regression contract for live peripheral-install requirements.

local SHARED = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/"
local CLIENT = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/"

local function read(path)
	local handle = assert(io.open(path, "rb"), path)
	local source = handle:read("*a")
	handle:close()
	return source
end

local function section(source, firstMarker, nextMarker)
	local first = assert(source:find(firstMarker, 1, true), firstMarker)
	local last = assert(source:find(nextMarker, first + #firstMarker, true), nextMarker)
	return source:sub(first, last - 1)
end

local function contains(source, needle, label)
	assert(source:find(needle, 1, true), label .. ": " .. needle)
end

local function excludes(source, needle, label)
	assert(not source:find(needle, 1, true), label .. ": " .. needle)
end

local craft = read(SHARED .. "GS_CraftUtils.lua")
local modal = read(CLIENT .. "GS_AddonManageUI.lua")
local recipeCards = read(CLIENT .. "GS_TerminalRecipeCards.lua")

local strict = section(craft,
	"function GlobalStorageSiK.CraftUtils.knowsRecipeStrict",
	"local MANUAL_RECIPES")
excludes(strict, "player:isRecipeKnown",
	"strict magazine knowledge must not accept a readable item in inventory")
contains(strict, "isRecipeActuallyKnown",
	"strict magazine knowledge checks permanent learned state")
contains(strict, "getKnownRecipes",
	"strict magazine knowledge retains the B42 learned-recipe fallback")

local signature = section(modal,
	"local function installRequirementSignature",
	"local function statusSignature")
contains(signature, "hasReaderAvailable", "reader state is absent from live signature")
contains(signature, "moduleCount", "module count is absent from live signature")
contains(signature, "diskCount", "installation disk is absent from live signature")
contains(signature, "playerKnowsMagazine", "learned magazine is absent from live signature")
contains(signature, "skillHave", "skill state is absent from live signature")

local refreshSignature = section(modal,
	"local function statusSignature",
	"function GS_AddonManageUI:initialise")
contains(refreshSignature, "installRequirementSignature",
        "modal refresh still collapses all requirements into canInstall")

contains(modal, "contentMode = \"dock\"",
        "addon modal must use the unframed dock content host")
contains(modal, "UI.Scroll.create(self.contentHost",
        "addon modal must own one scroll root")
contains(modal, "manageBlock:beginColumn()",
        "installed/install requirements must be composed inside a real Block")
contains(modal, "createAddonActionButton(self, manageBlock.childParent, manageW",
        "action button must be created directly in the Block child parent")
contains(modal, "manageColumn:label(action, action.height)",
        "action panel must be placed through the real Layout.Column API")
contains(modal, "recipeColumn:block(requirements.panel, requirements.height)",
        "recipe Requirements must be placed through the real Layout.Column API")
excludes(modal, "recipeColumn:block(card, cardH)",
        "recipe Block must not retain the replaced inner recipe-card representation")
excludes(modal, "manageColumn:add(",
        "Layout.Column has no add API")

-- Execute the framework's actual Column implementation: the product may only
-- use its public place/label/block verbs, never an invented add method.
local originalRequire = require
require = function() return {} end
SiK = { UI = { Metrics = { spacing = { sm = 8 } }, Namespace = { define = function() end } } }
local Layout = assert(loadfile("../SiKUIFramework-Repo/SiKUIFramework/Contents/mods/SiKUIFramework/42/media/lua/client/SiK/UI/Layout.lua"))()
require = originalRequire
local column = Layout.column({ x = 3, y = 7, w = 40, gap = 8 })
assert(column.add == nil, "framework Column must not expose an invented add API")
local widget = { setX = function(self, value) self.x = value end,
        setY = function(self, value) self.y = value end,
        setWidth = function(self, value) self.w = value end }
column:label(widget, 12)
assert(widget.x == 3 and widget.y == 7 and widget.w == 40,
        "Column.label must place a widget through the real framework API")
contains(modal, "manageBlock.y + manageHeight + 8",
        "next Block must retain the first Block's scroll-local y coordinate")
contains(modal, "recipeBlock.y + recipeHeight + 8",
        "recipe Block must retain its scroll-local y coordinate")
contains(modal, "IGUI_GS_ProgrammingRecipeRequirement",
        "magazine requirement must use the canonical Learn label")
contains(modal, "recipeBlock:beginColumn()",
        "module recipe must be composed inside its titled Block")
contains(modal, "GS_Confirmation",
        "uninstall must use the product confirmation adapter")
contains(modal, "IGUI_GS_AddonUninstallConsequences",
        "uninstall confirmation must declare product consequences")
contains(modal, "currentReader and currentDiskOk and currentSkillOk",
        "uninstall confirmation must revalidate live requirements on acceptance")
contains(recipeCards, "options.parent",
        "recipe cards must support a declarative composition parent")
contains(recipeCards, "return cardH, card",
        "recipe cards must return their panel for Block composition")

print("addon_install_live_requirements_contract: OK")
