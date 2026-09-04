-- Binding data-driven contract for authorized item actions owned by addons.
-- Core is only a neutral registry/dispatcher; Craft and Builder declare their
-- own applicability, request data and capabilities.

local CORE = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/"
local CRAFT = "addons/GSSiK_Addon_Craft/Contents/mods/GSSiK_Addon_Craft/42/media/lua/"
local BUILDER = "addons/GSSiK_Addon_Builder/Contents/mods/GSSiK_Addon_Builder/42/media/lua/"
local function read(path)
	local handle = assert(io.open(path, "rb"), path)
	local value = handle:read("*a")
	handle:close()
	return value
end
local function contains(source, needle, label)
	assert(source:find(needle, 1, true), label .. ": " .. needle)
end
local function excludes(source, needle, label)
	assert(not source:find(needle, 1, true), label .. ": " .. needle)
end
local function section(source, first, last)
	local from = assert(source:find(first, 1, true), "section missing: " .. first)
	local to = assert(source:find(last, from + #first, true), "section end missing: " .. last)
	return source:sub(from, to - 1)
end

local core = read(CORE .. "client/GS_ItemActions.lua")
local coreClient = read(CORE .. "client/GS_Client.lua")
local craftSession = read(CORE .. "client/GS_NetworkCraftSession.lua")
local apiClient = read(CORE .. "client/GSSiK_API_Client.lua")
local workSession = read(CORE .. "client/GSSiK_API_WorkSession.lua")
local server = read(CORE .. "server/GS_Server.lua")
local warehouse = read(CORE .. "client/GS_TerminalUI_Items.lua")
local craftRegister = read(CRAFT .. "client/GSSiK_Addon_Craft_Client.lua")
local builderRegister = read(BUILDER .. "client/GSSiK_Addon_Builder_Client.lua")
local craftEn = read(CRAFT .. "shared/Translate/EN/IG_UI.json")
local craftEs = read(CRAFT .. "shared/Translate/ES/IG_UI.json")
local builderEn = read(BUILDER .. "shared/Translate/EN/IG_UI.json")
local builderEs = read(BUILDER .. "shared/Translate/ES/IG_UI.json")

contains(craftSession,
	"function GlobalStorageSiK.CraftSession.openHandcraft(mode, recipe, itemString)",
	"CraftSession handcraft signature drops recipe/filter")
contains(craftSession,
	"function GlobalStorageSiK.CraftSession.openBuild(mode, recipe, itemString)",
	"CraftSession build signature drops recipe/filter")
local handcraftOpen = section(craftSession,
	"function GlobalStorageSiK.CraftSession.openHandcraft", "function GlobalStorageSiK.CraftSession.openBuild")
local buildOpen = section(craftSession,
	"function GlobalStorageSiK.CraftSession.openBuild", "local function refreshAddonTabIfVisible")
contains(handcraftOpen, 'opener(player, nil, "*", false, recipe, itemString)',
	"handcraft opener does not preserve the B42 six-argument signature")
contains(buildOpen, 'opener(player, nil, "*", false, recipe, itemString)',
	"build opener does not preserve the B42 six-argument signature")

-- Addons consume the public WorkSession facade; the private CraftSession
-- remains the owner of the existing six-argument vanilla opener.
contains(workSession, "function Public.openHandcraft(addonId, mode, recipe, itemString)",
	"public WorkSession handcraft signature drops owner/recipe/filter")
contains(workSession, 'return openWith(addonId, "openHandcraft", mode, recipe, itemString)',
	"public WorkSession does not delegate to the existing handcraft session")
contains(workSession, "function Public.openBuild(addonId, mode, recipe, itemString)",
	"public WorkSession build signature drops owner/recipe/filter")
contains(workSession, 'return openWith(addonId, "openBuild", mode, recipe, itemString)',
	"public WorkSession does not delegate to the existing build session")

contains(core, "function GlobalStorageSiK.ItemActions.registerProvider(def)",
	"neutral provider API missing")
for _, field in ipairs({ "id", "addonId", "capabilities", "actions", "appliesTo", "buildRequest" }) do
	contains(core, "def." .. field, "provider field is not validated")
end
assert(core:find("def.executeRequest", 1, true) or core:find("def.execute", 1, true),
	"provider execution callback is not validated")
contains(core, "registerProvider", "Core never enumerates registered providers")
contains(apiClient, "function ItemActions.registerProvider(definition)",
	"public ItemActions provider API missing")
contains(apiClient, "local prepared = copyProviderDefinition(definition)",
	"public ItemActions does not take a defensive provider copy")
contains(apiClient, "actionRegistration(prepared.id, generation",
	"public ItemActions does not return a generation-safe registration")
for _, field in ipairs({ "id", "addonId", "capabilities", "actions", "appliesTo", "buildRequest" }) do
	contains(apiClient, "definition." .. field, "public provider field is not validated")
end
assert(apiClient:find("definition.executeRequest", 1, true)
	or apiClient:find("definition.execute", 1, true),
	"public provider execution callback is not validated")

local providerOptions = section(core,
	"function GlobalStorageSiK.ItemActions.addProviderOptions", "function GlobalStorageSiK.ItemActions.onTransferOne")
contains(providerOptions, 'local targetMenu = type(menu) == "table" and menu or nil',
	"provider composer cannot defer submenu creation")
contains(providerOptions, "if okApplies and applies == true then",
	"submenu factory is not gated by an applicable action")
contains(providerOptions, "if not targetMenu then targetMenu = menu() end",
	"submenu factory is not invoked lazily")
local appliesAt = assert(providerOptions:find("if okApplies and applies == true then", 1, true))
local factoryAt = assert(providerOptions:find("if not targetMenu then targetMenu = menu() end", 1, true))
assert(appliesAt < factoryAt, "submenu root can be created before any provider applies")

contains(warehouse, "local providerRows = getSelectedRows(listPanel)",
	"Warehouse provider context ignores the current selection")
contains(warehouse, "if #providerRows == 0 then providerRows = { data } end",
	"Warehouse has no clicked-row fallback when selection is empty")
contains(warehouse, "ItemActions.addProviderOptions(cm, player, providerRows, {",
	"Warehouse does not send its resolved contextual rows to providers")

for _, addon in ipairs({
	{ name = "Craft", register = craftRegister, requiredActions = { "reload", "refill", "craft" },
		providerCall = 'terminal:openNetworkCraft("vanilla", recipe, itemString)',
		openerSignature = "function TerminalModule.openCraft(terminal, mode, recipe, itemString)",
		sessionOpen = 'Session.openHandcraft("Craft", mode, recipe, itemString)',
		installedKey = "Craft", translations = { craftEn, craftEs },
		translationKeys = { "IGUI_GS_ItemActionReload", "IGUI_GS_ItemActionRefill", "IGUI_GS_CraftOpenVanilla" } },
	{ name = "Builder", register = builderRegister, requiredActions = { "craft" },
		providerCall = 'TerminalModule.openBuild(terminal, "vanilla", nil, itemString)',
		openerSignature = "function TerminalModule.openBuild(terminal, mode, recipe, itemString)",
		sessionOpen = 'Session.openBuild("Builder", mode, recipe, itemString)',
		installedKey = "Builder", translations = { builderEn, builderEs },
		translationKeys = { "IGUI_GS_CraftOpenBuildVanilla" } },
}) do
	contains(addon.register, "API.ItemActions.registerProvider({",
		addon.name .. " does not own its provider")
	contains(addon.register, 'local API = require "GSSiK_API_Client"',
		addon.name .. " does not consume the public client API")
	contains(addon.register, "local Session = API.WorkSession",
		addon.name .. " does not consume public WorkSession")
	contains(addon.register, 'addonId = "' .. addon.name .. '"',
		addon.name .. " provider identity")
	contains(addon.register, "capabilities =", addon.name .. " capabilities missing")
	contains(addon.register, "actions =", addon.name .. " action declarations missing")
	contains(addon.register, "appliesTo =", addon.name .. " applicability missing")
	contains(addon.register, "buildRequest =", addon.name .. " request builder missing")
	assert(addon.register:find("executeRequest =", 1, true)
		or addon.register:find("execute =", 1, true),
		addon.name .. " provider does not own execution through public Core APIs")
	for i = 1, #addon.requiredActions do
		contains(addon.register, addon.requiredActions[i], addon.name
			.. " omits required action " .. addon.requiredActions[i])
	end
	contains(addon.register, addon.providerCall,
		addon.name .. " provider does not propagate its exact request")
	contains(addon.register, addon.openerSignature,
		addon.name .. " terminal opener drops provider args")
	contains(addon.register, "Session.begin({",
		addon.name .. " terminal opener bypasses WorkSession begin")
	contains(addon.register, addon.sessionOpen,
		addon.name .. " terminal opener bypasses public WorkSession authority")
	excludes(addon.register, "sendClientCommand", addon.name
		.. " invents a parallel network protocol")
	excludes(addon.register, "GlobalStorageSiK", addon.name
		.. " reaches into private Core internals")
	local terminalGuard = section(addon.register, "local function providerTerminal", "local function ")
	contains(terminalGuard,
		"if not terminal.getIsVisible or terminal:getIsVisible() ~= true then return nil end",
		addon.name .. " provider accepts a terminal not proven visible")
	contains(terminalGuard, 'Terminal.isAddonInstalled(terminal, "' .. addon.installedKey .. '")',
		addon.name .. " provider does not require its installed addon")
	for i = 1, #addon.translationKeys do
		local quoted = '"' .. addon.translationKeys[i] .. '"'
		contains(addon.translations[1], quoted, addon.name .. " EN action key missing")
		contains(addon.translations[2], quoted, addon.name .. " ES action key missing")
	end
end

local directRefill = section(craftRegister, "local DIRECT_REFILL_TYPES", "local function itemFullType")
contains(directRefill, '["Base.Bowl"] = true', "Craft lost the concrete empty bowl")
contains(directRefill, '["Base.ClayBowl"] = true', "Craft lost the concrete empty clay bowl")
excludes(directRefill, "Base.Pot", "empty Pot was guessed refillable without structure")
excludes(directRefill, "Base.Saucepan", "empty Saucepan was guessed refillable without structure")

local bowlStructure = section(craftRegister, "local function canDivideIntoBowls", "local function providerTerminal")
contains(bowlStructure, 'ResourceLocation.of("base:canbedividedinbowls")',
	"bowl refill does not resolve the structural B42 tag")
contains(bowlStructure, "ItemTag.get", "bowl refill does not use ItemTag")
contains(bowlStructure, "getScriptManager():getItem(fullType)",
	"bowl refill does not inspect the exact script item")
contains(bowlStructure, "script:hasTag(divideIntoBowlsTag)",
	"bowl refill guesses by fullType instead of the structural tag")

local craftProvider = section(craftRegister, "API.ItemActions.registerProvider({",
	"function TerminalModule.openCraft")
local builderProvider = section(builderRegister, "API.ItemActions.registerProvider({",
	"function TerminalModule.openBuild")
contains(craftRegister, 'request.recipeName = "RefillBlowTorch"',
	"blowtorch reload does not select the exact recipe")
contains(craftProvider, 'local itemString = not recipe and request.inputFullType and ("!" .. request.inputFullType) or nil',
	"Craft does not choose recipe OR exact !fullType filter")
contains(builderProvider, 'local itemString = request.inputFullType and ("!" .. request.inputFullType) or nil',
	"Builder does not propagate the exact !fullType filter")
contains(craftProvider, 'return actionId == "craft"',
	"generic Craft filter is not reachable for Base.Plank")
contains(builderProvider, 'return actionId == "craft"',
	"generic Builder filter is not reachable for Base.Plank")
for _, providerSource in ipairs({ craftProvider, builderProvider }) do
	excludes(providerSource, "_gsPreferredItemAction", "provider keeps dead request state")
	excludes(providerSource, "sendClientCommand", "provider adds an action protocol")
	excludes(providerSource, "perform", "provider autoexecutes an action")
end

contains(craftRegister, "function TerminalModule.openCraft(terminal, mode, recipe, itemString)",
	"terminal Craft signature drops provider args")
contains(craftRegister, 'Session.openHandcraft("Craft", mode, recipe, itemString)',
	"terminal Craft does not propagate recipe/filter through public WorkSession")
contains(builderRegister, "function TerminalModule.openBuild(terminal, mode, recipe, itemString)",
	"terminal Builder signature drops provider args")
contains(builderRegister, 'Session.openBuild("Builder", mode, recipe, itemString)',
	"terminal Builder does not propagate recipe/filter through public WorkSession")
excludes(craftRegister, "_gsPreferredItemAction", "Craft retained dead preferred action state")
excludes(builderRegister, "_gsPreferredItemAction", "Builder retained dead preferred action state")

-- No action-specific addon switch belongs in Core.
for _, forbidden in ipairs({
	'addonId == "Craft"', 'addonId == "Builder"', 'addonId == "Tablet"',
	'provider.id == "Craft"', 'provider.id == "Builder"',
}) do
	excludes(core, forbidden, "Core contains addon-specific item action routing")
	excludes(server, forbidden, "Core server contains addon-specific item action routing")
end

-- This DEV may compose providers over the existing CraftSession/claim flow,
-- but must not add a new authority command or protocol surface.
excludes(server, 'command == "itemAction"', "server gained a new itemAction command")
excludes(server, 'command == "ItemAction"', "server gained a new ItemAction command")
excludes(coreClient, '"itemAction"', "client protocol gained itemAction")
excludes(coreClient, '"ItemAction"', "client protocol gained ItemAction")

print("addon_item_action_provider_contract: OK")
