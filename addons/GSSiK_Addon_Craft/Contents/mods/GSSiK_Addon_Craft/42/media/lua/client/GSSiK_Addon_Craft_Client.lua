--[[
	GSSiK Addon Craft - Cliente
	Autor: SiK
	Fecha: 2025-06-27
]]

require "GS_TerminalUI"
require "GS_TerminalUI_Extensions"
require "GSSiK_Addon_Craft_Register"
require "GS_NetworkCraftBridge"
require "GS_NetworkCraftSession"
require "GS_ItemActions"
require "GSSiK_Addon_Craft_NetworkCraft"
require "GSSiK_Addon_Craft_NetworkCook"
require "GSSiK_Addon_Craft_TerminalUI"
require "GSSiK_Addon_Craft_Sandbox"
require "GSSiK_Addon_Craft_Log"

GlobalStorageSiK.TerminalTabs = GlobalStorageSiK.TerminalTabs or {}

-- El sink de debug y los hooks de crafteo en red ya se registran en
-- GSSiK_Addon_Craft_NetworkCraft.lua (migrado desde aqui, ver ese fichero).

GlobalStorageSiK.TerminalExtensions.registerDefinition("craft", {
	module = GlobalStorageSiK.TerminalCraft,
	titleKey = "IGUI_GS_TabCraft",
	iconPath = "media/ui/GS/GS_TabCraft.png",
	panelField = "craftPanel",
})

local DIRECT_RELOAD_TYPES = {
	["Base.BlowTorch"] = true,
	["Base.PropaneTank"] = true,
}
local DIRECT_REFILL_TYPES = {
	["Base.Bowl"] = true,
	["Base.ClayBowl"] = true,
}

local function itemFullType(item)
	local fullType = item and item.fullType
	if not fullType and item and item.getFullType then fullType = item:getFullType() end
	return fullType
end

local divideIntoBowlsTag = nil
local function canDivideIntoBowls(fullType)
	if not fullType or not getScriptManager or not ItemTag or not ItemTag.get
		or not ResourceLocation or not ResourceLocation.of then
		return false
	end
	local ok, tagged = pcall(function()
		if not divideIntoBowlsTag then
			divideIntoBowlsTag = ItemTag.get(ResourceLocation.of("base:canbedividedinbowls"))
		end
		local script = getScriptManager():getItem(fullType)
		return divideIntoBowlsTag and script and script.hasTag and script:hasTag(divideIntoBowlsTag)
	end)
	return ok and tagged == true
end

local function providerTerminal(context)
	local extra = context and context.extra or {}
	local terminal = extra.terminal or (GlobalStorageSiK.TerminalUI and GlobalStorageSiK.TerminalUI.instance)
	if not terminal or not terminal.terminalState then return nil end
	if not terminal.getIsVisible or terminal:getIsVisible() ~= true then return nil end
	local installed = terminal.terminalState.installedAddons
	if not installed or installed["Craft"] == nil then return nil end
	return terminal
end

local function contextHasType(context, accepted)
	local items = context and context.items or {}
	for i = 1, #items do
		local item = items[i]
		local fullType = itemFullType(item)
		if fullType and accepted[fullType] then return true end
	end
	return false
end

local function buildItemActionRequest(actionId, context)
	local items = context and context.items or {}
	local contextual = context and context.extra and context.extra.row or nil
	local inputFullType = itemFullType(contextual) or itemFullType(items[1])
	if actionId == "reload" and not DIRECT_RELOAD_TYPES[inputFullType] then
		for i = 1, #items do
			local candidate = itemFullType(items[i])
			if DIRECT_RELOAD_TYPES[candidate] then
				inputFullType = candidate
				break
			end
		end
	end
	if actionId == "refill" then
		for i = 1, #items do
			local candidate = itemFullType(items[i])
			if DIRECT_REFILL_TYPES[candidate] or canDivideIntoBowls(candidate) then
				inputFullType = candidate
				break
			end
		end
	end
	local request = { actionId = actionId, inputFullType = inputFullType,
		source = context and context.extra and context.extra.source or "inventory" }
	if actionId == "reload" then
		request.recipeName = "RefillBlowTorch"
	end
	return request
end

-- Core solo compone el menú. Craft conserva aplicabilidad y ejecución y abre
-- la sesión existente, que vuelve a validar addon, red, alcance e insumos.
GlobalStorageSiK.ItemActions.registerProvider({
	id = "craft.item-actions",
	addonId = "Craft",
	capabilities = { "reload", "refill", "craft" },
	actions = {
		{ id = "reload", labelKey = "IGUI_GS_ItemActionReload" },
		{ id = "refill", labelKey = "IGUI_GS_ItemActionRefill" },
		{ id = "craft", labelKey = "IGUI_GS_CraftOpenVanilla" },
	},
	appliesTo = function(context, actionId)
		if not providerTerminal(context) then return false end
		if actionId == "reload" then return contextHasType(context, DIRECT_RELOAD_TYPES) end
		if actionId == "refill" then
			if contextHasType(context, DIRECT_REFILL_TYPES) then return true end
			local items = context.items or {}
			for i = 1, #items do
				if canDivideIntoBowls(itemFullType(items[i])) then return true end
			end
			return false
		end
		return actionId == "craft"
	end,
	buildRequest = buildItemActionRequest,
	executeRequest = function(request, context)
		local terminal = providerTerminal(context)
		if not terminal then return false end
		local recipe = nil
		if request.recipeName and getScriptManager then
			recipe = getScriptManager():getCraftRecipe(request.recipeName)
			if not recipe then return false end
		end
		local itemString = not recipe and request.inputFullType and ("!" .. request.inputFullType) or nil
		terminal:openNetworkCraft("vanilla", recipe, itemString)
		return true
	end,
})

--- Abre crafteo con contenedores de red.
---@param mode string
function GS_TerminalUI:openNetworkCraft(mode, recipe, itemString)
	local player = GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer() or nil
	if not player or not GlobalStorageSiK.CraftSession then
		return
	end
	local state = self.terminalState or {}
	-- Antes, si begin() u openHandcraft() fallaban, el clic no hacia nada
	-- visible - ahora SIEMPRE se refresca el panel al final (exito o fallo)
	-- para que GS_NetworkCraftSession.getLastOpenError() se muestre en la
	-- etiqueta de estado que ya existe en este panel.
	-- Confiar en el terminalState ya confirmado por el servidor (el mismo
	-- dato que hace que la pestaña Addons muestre el modulo instalado) en
	-- vez de solo el mirror local de red (ModData), que puede ir con
	-- retraso justo tras instalar - ver comentario en CraftSession.begin.
	local knownInstalled = state.installedAddons and state.installedAddons["Craft"] ~= nil
	local began, beginReason = GlobalStorageSiK.CraftSession.begin({
		player = player,
		networkId = state.networkId,
		terminalAnchor = state.terminalAnchor,
		accessMode = state.accessMode,
		uiMode = "handcraft_" .. tostring(mode or "auto"),
		addonId = "Craft",
		knownInstalled = knownInstalled,
	})
	GSSiK_Addon_Craft.Log.debug("openNetworkCraft mode=" .. tostring(mode)
		.. " networkId=" .. tostring(state.networkId) .. " began=" .. tostring(began)
		.. " reason=" .. tostring(beginReason))
	if began then
		local opened, openReason = GlobalStorageSiK.CraftSession.openHandcraft(mode, recipe, itemString)
		GSSiK_Addon_Craft.Log.debug("openHandcraft opened=" .. tostring(opened) .. " reason=" .. tostring(openReason))
	end
	if self.craftPanel and GlobalStorageSiK.TerminalCraft then
		GlobalStorageSiK.TerminalCraft.refresh(self.craftPanel, self)
	end
end

function GS_TerminalUI:onOpenVanillaCraft()
	self:openNetworkCraft("vanilla")
end

function GS_TerminalUI:onOpenNeatCraft()
	self:openNetworkCraft("neat")
end

GlobalStorageSiK.TerminalExtensions.registerStaffAction("craft.vanilla", {
	labelKey = "IGUI_GS_CraftOpenVanilla",
	order = 10,
	invoke = function(dashboard)
		if dashboard and dashboard.setVisible then
			dashboard:setVisible(false)
		end
		local terminal = GlobalStorageSiK.TerminalUI and GlobalStorageSiK.TerminalUI.instance or nil
		if terminal and terminal.openNetworkCraft then
			terminal:openNetworkCraft("vanilla")
		else
			GlobalStorageSiK.CraftSession.openHandcraft("vanilla")
		end
	end,
})

--- Abre cocina (Project_Cook, mod externo opcional) con contenedores de red
--- - misma sesion "Craft" que crafteo, distinto uiMode para diagnostico. Ver
--- GSSiK_Addon_Craft_NetworkCook.lua: Project_Cook rastrea su propia
--- ventana, no via ISEntityUI, así que no reutiliza CraftSession.openHandcraft.
function GS_TerminalUI:onOpenCook()
	local player = GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer() or nil
	if not player or not GlobalStorageSiK.CraftSession then
		return
	end
	local state = self.terminalState or {}
	local knownInstalled = state.installedAddons and state.installedAddons["Craft"] ~= nil
	local began, beginReason = GlobalStorageSiK.CraftSession.begin({
		player = player,
		networkId = state.networkId,
		terminalAnchor = state.terminalAnchor,
		accessMode = state.accessMode,
		uiMode = "cook",
		addonId = "Craft",
		knownInstalled = knownInstalled,
	})
	GSSiK_Addon_Craft.Log.debug("onOpenCook networkId=" .. tostring(state.networkId) .. " began=" .. tostring(began)
		.. " reason=" .. tostring(beginReason))
	if began then
		local opened, openReason = GSSiK_Addon_Craft_NetworkCook.openCookUI(player)
		GSSiK_Addon_Craft.Log.debug("openCookUI opened=" .. tostring(opened) .. " reason=" .. tostring(openReason))
		if opened then
			GlobalStorageSiK.CraftSession.setLastOpenError(nil)
		else
			GlobalStorageSiK.CraftSession.setLastOpenError(openReason)
			GlobalStorageSiK.CraftSession.endSession(nil)
		end
	end
	if self.craftPanel and GlobalStorageSiK.TerminalCraft then
		GlobalStorageSiK.TerminalCraft.refresh(self.craftPanel, self)
	end
end

function GS_TerminalUI:syncCraftTabVisibility()
	local state = self.terminalState or {}
	local player = GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer() or nil
	local show = state.craftTabEnabled
	if show == nil and GlobalStorageSiK.Addons then
		show = GlobalStorageSiK.Addons.canShowTerminalCraftTab(
			state.networkId,
			state.terminalAnchor,
			state.accessMode,
			player
		)
	end
	if GlobalStorageSiK.TerminalExtensions then
		GlobalStorageSiK.TerminalExtensions.setTabVisible(self, "craft", show == true)
	end
end
