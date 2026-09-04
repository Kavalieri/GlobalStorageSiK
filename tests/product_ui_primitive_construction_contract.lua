-- Transversal presentation boundary for released Mods PZ products/addons.
-- Product client code may bridge game input/world APIs, but reusable visual
-- primitives are constructed only by the public SiK.UI framework.
-- Run from GlobalStorageSiK-Repo with Lua 5.1.

local roots = {
	"GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client",
	"addons",
	"../ManureManagerSiK-Repo/Contents/mods/ManureManagerSiK/42/media/lua/client",
	"../SiKCorpseLootGuard-Repo/Contents/mods/SiKCorpseLootGuard/42/media/lua/client",
}

local visualConstructors = {
	"ISPanel:new", "ISPanelJoypad:new", "ISCollapsableWindow:new",
	"ISButton:new", "ISLabel:new", "ISComboBox:new", "ISTextEntryBox:new",
	"ISScrollingListBox:new", "ISRichTextPanel:new", "ISImage:new",
	"ISToolTip:new", "ISToolTipInv:new", "ISModalDialog:new",
}

-- Deliberate vanilla bridge required by the approved inventory-tooltip chain:
-- one reusable ISToolTipInv owned by the Warehouse row pool. It is not a SiK
-- chrome primitive and any second occurrence still fails. Match the complete
-- product suffix so another file with the same basename cannot inherit it.
local allowedConstructors = {
	["/GlobalStorageSiK/42/media/lua/client/GS_TerminalUI_Items.lua"] = {
		["ISToolTipInv:new"] = 1,
	},
}

-- Direct ISUI imports are forbidden by default. These exact modules remain
-- because the product integrates with an existing vanilla behavior/surface;
-- none author reusable product chrome. Every exception is path-scoped and
-- carries a justification so the list cannot become an unexplained bypass.
local allowedBehaviorImports = {
	["/GlobalStorageSiK/42/media/lua/client/GS_CleanUIInventoryTaxonomy.lua"] = {
		reason = "observes the existing vanilla inventory pane taxonomy",
		modules = { ["ISUI/ISInventoryPane"] = true },
	},
	["/GlobalStorageSiK/42/media/lua/client/GS_ContainerTargets.lua"] = {
		reason = "adds actions to the existing vanilla context menu",
		modules = { ["ISUI/ISContextMenu"] = true },
	},
	["/GlobalStorageSiK/42/media/lua/client/GS_ContextMenu.lua"] = {
		reason = "integrates terminal actions into the vanilla context menu",
		modules = { ["ISUI/ISContextMenu"] = true },
	},
	["/GlobalStorageSiK/42/media/lua/client/GS_EquippedItemHook.lua"] = {
		reason = "anchors SiK UI beside the existing vanilla equipped-item panel",
		modules = { ["ISUI/ISEquippedItem"] = true },
	},
	["/GlobalStorageSiK/42/media/lua/client/GS_ItemActions.lua"] = {
		reason = "registers actions on the existing vanilla inventory context menu",
		modules = {
			["ISUI/ISContextMenu"] = true,
			["ISUI/ISInventoryPaneContextMenu"] = true,
		},
	},
	["/GlobalStorageSiK/42/media/lua/client/GS_NetworkReadAction.lua"] = {
		reason = "uses vanilla inventory action eligibility without authoring UI",
		modules = { ["ISUI/ISInventoryPaneContextMenu"] = true },
	},
	["/GlobalStorageSiK/42/media/lua/client/GS_TerminalUI_Items.lua"] = {
		reason = "adds row actions to the existing vanilla context-menu bridge",
		modules = { ["ISUI/ISContextMenu"] = true },
	},
	["/GlobalStorageSiK/42/media/lua/client/GS_TransferMenu.lua"] = {
		reason = "adds transfer actions to the existing vanilla context menu",
		modules = { ["ISUI/ISContextMenu"] = true },
	},
	["/GlobalStorageSiK/42/media/lua/client/GS_VanillaInventoryTaxonomy.lua"] = {
		reason = "decorates the existing vanilla inventory pane taxonomy",
		modules = { ["ISUI/ISInventoryPane"] = true },
	},
	["/GlobalStorageSiK/42/media/lua/client/GS_WithdrawMenu.lua"] = {
		reason = "adds withdrawal actions to the existing vanilla context menu",
		modules = { ["ISUI/ISContextMenu"] = true },
	},
	["/ManureManagerSiK/42/media/lua/client/MM_FurrowCollector.lua"] = {
		reason = "reuses vanilla farming validity and menu behavior",
		modules = { ["Farming/ISUI/ISFarmingMenu"] = true },
	},
	["/ManureManagerSiK/42/media/lua/client/MM_ItemMenu.lua"] = {
		reason = "adds actions to the existing vanilla context menu",
		modules = { ["ISUI/ISContextMenu"] = true },
	},
}

local function countPlain(source, needle)
	local count, offset = 0, 1
	while true do
		local found = source:find(needle, offset, true)
		if not found then return count end
		count, offset = count + 1, found + #needle
	end
end

local function quote(path) return '"' .. path:gsub('"', '\\"') .. '"' end
local function list(root)
	local pipe = assert(io.popen("dir /b /s " .. quote(root .. "\\*.lua") .. " 2>nul"),
		"cannot enumerate " .. root)
	local result = {}
	for path in pipe:lines() do
		path = path:gsub("\\", "/")
		if path:find("/42/media/lua/client/", 1, true)
			and not path:find("/tests/", 1, true) then
			result[#result + 1] = path
		end
	end
	pipe:close()
	return result
end

local function read(path)
	local handle = assert(io.open(path, "rb"), "cannot read " .. path)
	local source = handle:read("*a")
	handle:close()
	return source
end

local function codeOnly(source)
	source = tostring(source or ""):gsub("%-%-%[%[.-%]%]", "")
	return source:gsub("%-%-[^\r\n]*", "")
end

local function suffixEntry(map, path)
	for suffix, entry in pairs(map) do
		if #path >= #suffix and path:sub(-#suffix) == suffix then return entry end
	end
	return nil
end

local function directImports(source)
	local result = {}
	for line in tostring(source or ""):gmatch("[^\r\n]+") do
		local module = line:match("require%s*[\"']([^\"']+)[\"']")
			or line:match("require%s*%(%s*[\"']([^\"']+)[\"']%s*%)")
		if module then result[#result + 1] = module end
	end
	return result
end

local function isIsuiModule(module)
	return module:sub(1, 5) == "ISUI/" or module:find("/ISUI/", 1, true) ~= nil
end

local failures, scanned = {}, 0
for rootIndex = 1, #roots do
	for _, path in ipairs(list(roots[rootIndex])) do
		local source = codeOnly(read(path))
		scanned = scanned + 1
		for index = 1, #visualConstructors do
			local symbol = visualConstructors[index]
			local actual = countPlain(source, symbol)
			local constructorEntry = suffixEntry(allowedConstructors, path)
			local permitted = constructorEntry and constructorEntry[symbol] or 0
			if actual > permitted then
				failures[#failures + 1] = path .. " constructs " .. symbol
					.. " actual=" .. tostring(actual) .. " allowed=" .. tostring(permitted)
			end
		end
		local importEntry = suffixEntry(allowedBehaviorImports, path)
		if importEntry then
			assert(type(importEntry.reason) == "string" and importEntry.reason ~= "",
				"behavior import exception requires a justification: " .. path)
		end
		for _, module in ipairs(directImports(source)) do
			if isIsuiModule(module)
				and not (importEntry and importEntry.modules[module] == true) then
				failures[#failures + 1] = path .. " imports vanilla visual module " .. module
			end
		end
		for _, symbol in ipairs({ "ISPanel:derive", "ISCollapsableWindow:derive" }) do
			if source:find(symbol, 1, true) then
				failures[#failures + 1] = path .. " derives " .. symbol
			end
		end
		if source:find('require "SiK/UI/', 1, true)
			or source:find("require 'SiK/UI/", 1, true) then
			failures[#failures + 1] = path .. " imports a private framework module"
		end
		if source:find("GlobalStorageSiK.SiK_UI", 1, true) then
			failures[#failures + 1] = path .. " uses removed product-owned UI namespace"
		end
	end
end

if #failures > 0 then
	table.sort(failures)
	error("reusable visual primitives escaped SiK.UI:\n" .. table.concat(failures, "\n"), 0)
end

assert(scanned > 0, "no product client runtime files were scanned")
print("product_ui_primitive_construction_contract: OK files=" .. tostring(scanned))
