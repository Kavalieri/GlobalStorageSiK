-- Final mounted parity for the two card galleries rejected in runtime.

dofile("../SiKUIFramework-Repo/tests/geometry/pz_ui_stub.lua")
package.path = "../SiKUIFramework-Repo/SiKUIFramework/Contents/mods/SiKUIFramework/42/media/lua/client/?.lua;" .. package.path
dofile("../SiKUIFramework-Repo/SiKUIFramework/Contents/mods/SiKUIFramework/42/media/lua/client/SiK_UI.lua")

local CLIENT = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/"
local parent = ISPanel:new(0, 0, 1500, 900)
parent:initialise()

local function mount(modulePath, data, actions)
	local artifact = assert(dofile(CLIENT .. modulePath))
	local tree, reason = SiK.UI.buildSurface(parent, artifact, {
		locale = "es", playerNum = 0,
		viewport = { x = 0, y = 0, w = 1500, h = 900 },
		data = data, actions = actions,
	})
	assert(tree, reason)
	return tree
end

local addonActivations = 0
local addons = {}
for index = 1, 4 do
	addons[index] = { variant = "feature", title = "Addon " .. index,
		icon = "addon-" .. index, status = "Instalado", statusTone = "success",
		actionLabel = index == 1 and "Gestionar" or "Instalar",
		locked = index == 4, payload = { addonId = index } }
end
local addonTree = mount("GlobalStorageSiK/UI/Generated/TabAddons.lua",
	{ addons = { cards = addons } }, { ["addons.open"] = function()
		addonActivations = addonActivations + 1
		return true
	end })
local addonCollection = assert(addonTree.nodes["addons-cards"])
assert(#addonCollection.cards == 4 and addonCollection.columns == 2,
	"Addons must mount four cards in exactly two columns")
local addonA, addonB = addonCollection.cards[1], addonCollection.cards[2]
assert(addonA.variant == "feature" and addonA.panel.height == 164
	and addonA.actionButton and addonA.actionButton._sikUiControl == "button",
	"Addon feature cards must expose their visible action button")
assert(addonB.panel.x - addonA.panel.x - addonA.panel.width == 8,
	"Addon card columns lost the canonical gap")
assert(addonCollection.contentHeight == 164 * 2 + 8,
	"Addon rows must retain their final geometry")
addonA.actionButton.onclick(addonA.actionButton)
assert(addonActivations == 1, "Enabled addon CTA must dispatch its surface action")
local lockedAddon = addonCollection.cards[4]
assert(lockedAddon.actionButton.enable == false,
	"Unavailable addon CTA must be visibly disabled")
lockedAddon.actionButton.onclick(lockedAddon.actionButton)
assert(addonActivations == 1, "Disabled addon CTA must not dispatch")
addonTree:dispose()

local programs = {}
for index = 1, 6 do
	programs[index] = { variant = "process", title = "Program " .. index,
		description = "Purpose", requirement = index == 3 and "Requirement" or "",
		actionLabel = "Write", icon = "disk-" .. index,
		status = "Available", statusTone = "success", locked = index == 3,
		payload = { programId = index } }
end
local programTree = mount("GlobalStorageSiK/UI/Generated/TabProgramming.lua",
	{ programming = { status = { text = "Reader ready", kind = "success" }, cards = programs } },
	{ ["programming.run"] = function() return true end })
local programCollection = assert(programTree.nodes["programming-cards"])
assert(#programCollection.cards == 6 and programCollection.columns == 2,
	"Programming must mount six functional cards in exactly two columns")
local programA, programB = programCollection.cards[1], programCollection.cards[2]
assert(programA.variant == "process" and programA.panel.height == 148
	and programA.actionButton and programA.actionButton._sikUiControl == "button",
	"Programming cards must expose the complete process widget")
assert(programB.panel.x - programA.panel.x - programA.panel.width == 8,
	"Programming card columns lost the canonical gap")
assert(programCollection.contentHeight == 148 * 3 + 8 * 2,
	"Programming rows must retain their final geometry")
programTree:dispose()

print("addons_programming_final_geometry_contract: OK mounted feature/process galleries")
