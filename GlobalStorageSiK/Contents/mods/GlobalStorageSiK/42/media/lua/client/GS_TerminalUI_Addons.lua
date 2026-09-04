-- Global Storage SiK - declarative data/action adapter for the Addons tab.
-- The product supplies addon state and actions; SiK.UI owns every visual.

require "GS_I18n"
require "GS_Log"
require "GSSiK_API"
require "GS_Addons"
require "GS_CraftUtils"
require "GS_NetClient"
require "GS_AddonManageUI"

local UI = require "GS_UI_Framework"
local Surface = require "GlobalStorageSiK/UI/Generated/TabAddons"
local AddonAPI = GSSiK.API.Addon

GlobalStorageSiK.TerminalAddons = GlobalStorageSiK.TerminalAddons or {}
local AddonsTab = GlobalStorageSiK.TerminalAddons
local T = GlobalStorageSiK.I18n.text

local function joined(values)
	local parts = {}
	for index = 1, #(values or {}) do parts[#parts + 1] = tostring(values[index]) end
	return #parts > 0 and table.concat(parts, ",") or "none"
end

local function boolText(value)
	return value == true and "true" or "false"
end

local function setFrom(values)
	local result = {}
	for index = 1, #(values or {}) do result[tostring(values[index])] = true end
	return result
end

local function reportAddonDiagnostics(stage, cards, surfaceMounted)
	local cardCount = #(cards or {})
	if type(AddonAPI.diagnose) ~= "function" then
		GlobalStorageSiK.Log.debug("Addons", "catalog stage=" .. tostring(stage)
			.. " diagnostic_api=missing cards=" .. tostring(cardCount))
		return
	end
	local ok, code, snapshot = AddonAPI.diagnose()
	if ok ~= true then
		GlobalStorageSiK.Log.debug("Addons", "catalog stage=" .. tostring(stage)
			.. " diagnostic_failed code=" .. tostring(code))
		return
	end
	local registeredIds = {}
	local mountedIds = {}
	for index = 1, cardCount do
		local payload = cards[index] and cards[index].payload
		if type(payload) == "table" and payload.addonId then
			mountedIds[tostring(payload.addonId)] = true
		end
	end
	local activatedIds = setFrom(snapshot.activatedModIds)
	local attemptsById = {}
	for index = 1, #(snapshot.attempts or {}) do
		local row = snapshot.attempts[index]
		if row and row.id then attemptsById[tostring(row.id)] = row end
	end
	for index = 1, #(snapshot.registered or {}) do
		local def = snapshot.registered[index]
		registeredIds[#registeredIds + 1] = tostring(def.id) .. "@" .. tostring(def.modId)
		local addonId = tostring(def.id)
		local modId = tostring(def.modId)
		local attempt = attemptsById[addonId]
		local available = activatedIds[modId] == true
		local cause = available and "available" or "mod_not_activated"
		GlobalStorageSiK.Log.debug("Addons", "catalog_item stage=" .. tostring(stage)
			.. " id=" .. addonId
			.. " modId=" .. modId
			.. " registration=" .. tostring(attempt and attempt.code or "registered_before_diagnostics")
			.. " registered=" .. boolText(not attempt or attempt.registered == true)
			.. " available=" .. boolText(available)
			.. " mounted=" .. boolText(surfaceMounted == true and mountedIds[addonId] == true)
			.. " cause=" .. cause)
	end
	GlobalStorageSiK.Log.debug("Addons", "catalog stage=" .. tostring(stage)
		.. " registered=" .. joined(registeredIds)
		.. " cards=" .. tostring(cardCount)
		.. " activated_source=" .. tostring(snapshot.activatedSource)
		.. " activated=" .. joined(snapshot.activatedModIds))
	for index = 1, #(snapshot.attempts or {}) do
		local row = snapshot.attempts[index]
		GlobalStorageSiK.Log.debug("Addons", "registration id=" .. tostring(row.id)
			.. " modId=" .. tostring(row.modId)
			.. " registered=" .. tostring(row.registered)
			.. " code=" .. tostring(row.code)
			.. " sequence=" .. tostring(row.sequence))
	end
end

local function addonIsActive(addonId)
	local ok, _, active = AddonAPI.isActive(addonId)
	return ok == true and active == true
end

local function cardTitle(def, installed)
	local itemType = installed and installed.itemType or def.itemType
	if itemType and itemType ~= "" and GlobalStorageSiK.I18n.typeDisplayName then
		local name = GlobalStorageSiK.I18n.typeDisplayName(itemType)
		if name and name ~= "" then return name end
	end
	return T(def.titleKey or "IGUI_GS_AddonUnknown")
end

local function cardIcon(def, installed)
	local itemType = installed and installed.itemType or def.itemType
	if itemType and GlobalStorageSiK.CraftUtils and GlobalStorageSiK.CraftUtils.getItemIconTexture then
		local texture = GlobalStorageSiK.CraftUtils.getItemIconTexture(itemType)
		if texture then return texture end
	end
	return def.iconPath
end

local function cardState(def, installed)
	if not addonIsActive(def.id) then
		return T("IGUI_GS_AddonStatusMissingMod"), "danger", T("IGUI_GS_AddonStatusModOff"),
			true, T("IGUI_GS_AddonInstallBtn")
	end
	if installed then
		return T("IGUI_GS_AddonStatusInstalled"), "success", T("IGUI_GS_AddonStatusInstalled"),
			false, T("IGUI_GS_AddonManageBtn")
	end
	return T("IGUI_GS_AddonNotInstalledHereMsg"), "textMuted", T("IGUI_GS_AddonStatusReady"),
		false, T("IGUI_GS_AddonInstallBtn")
end

local function currentNetwork(terminal)
	local state = terminal and terminal.terminalState or {}
	local networkId = state.networkId
		or (GlobalStorageSiK.Client and GlobalStorageSiK.Client.activeNetworkId)
		or GlobalStorageSiK.Network.getDefaultNetworkId()
	return state, networkId, state.terminalAnchor
end

function AddonsTab.context(terminal)
	local state, networkId, anchor = currentNetwork(terminal)
	local cards = {}
	local status = { text = T("IGUI_GS_AddonsIntro"), kind = "info" }
	if not anchor or anchor.x == nil then
		status = { text = T("IGUI_GS_AddonsNeedTerminal"), kind = "error" }
	else
		local listed, code, defs = AddonAPI.list()
		if listed ~= true then
			status = { text = T("IGUI_GS_AddonsEmpty") .. " [" .. tostring(code) .. "]", kind = "error" }
			GlobalStorageSiK.Log.error("TerminalAddons", "Addon.list failed", tostring(code))
		else
			local installed = state.installedAddons or {}
			for i = 1, #defs do
				local def = defs[i]
				local installedDef = installed[def.id]
				local label, tone, tooltip, locked = cardState(def, installedDef)
				cards[#cards + 1] = {
					variant = "feature", title = cardTitle(def, installedDef),
					icon = cardIcon(def, installedDef), status = label,
					statusTone = tone, tooltip = tooltip, locked = locked,
					payload = { addonId = def.id },
				}
			end
			if #cards == 0 then status = { text = T("IGUI_GS_AddonsEmpty"), kind = "info" } end
		end
	end
	reportAddonDiagnostics("context", cards, false)
	return {
		playerNum = terminal and terminal.playerNum or 0,
		i18n = {
			["addons.title"] = T("IGUI_GS_AddonsSectionTitle"),
			["addons.help"] = T("IGUI_GS_AddonsIntro"),
		},
		data = { addons = { status = status, cards = cards } },
		actions = {
			["addons.open"] = function(envelope)
				local payload = envelope and (envelope.payload or envelope) or {}
				local addonId = type(payload) == "table" and payload.addonId or nil
				if type(addonId) ~= "string" or not addonIsActive(addonId) then return end
				local found, _, def = AddonAPI.get(addonId)
				if found ~= true or not def then return end
				local latestState, latestNetwork, latestAnchor = currentNetwork(terminal)
				GlobalStorageSiK.AddonManageUI.show(addonId, latestNetwork, latestAnchor,
					terminal, latestState.installedAddons or {})
			end,
		},
	}
end

local function reportSurfaceError(payload)
	GlobalStorageSiK.Log.error("TerminalAddons", "SiK.UI surface failure",
		tostring(payload and payload.reason or "unknown"))
end

function AddonsTab.buildPanel(panel, terminal)
	if not panel or panel._gsSurfaceHost then return end
	panel.terminalRef = terminal
	local initialContext = AddonsTab.context(terminal)
	local host, reason = SiK.UI.SurfaceHost.mount(panel, Surface, {
		context = initialContext,
		contextProvider = function() return AddonsTab.context(panel.terminalRef) end,
		onError = reportSurfaceError,
		followParent = true,
	})
	if not host then
		GlobalStorageSiK.Log.error("TerminalAddons", "Unable to mount declarative surface", tostring(reason))
		return
	end
	panel._gsSurfaceHost = host
	reportAddonDiagnostics("mounted", initialContext.data.addons.cards or {}, true)
end

function AddonsTab.layout(panel, innerW, innerH)
	if panel and panel._gsSurfaceHost then
		panel._gsSurfaceHost:reflow({ x = 0, y = 0, w = innerW, h = math.max(1, innerH) })
	end
end

function AddonsTab.refresh(panel, terminal)
	if not panel then return end
	panel.terminalRef = terminal or panel.terminalRef
	if not panel._gsSurfaceHost then AddonsTab.buildPanel(panel, panel.terminalRef) end
	if panel._gsSurfaceHost then panel._gsSurfaceHost:refresh() end
end

function AddonsTab.syncScrollLayout(panel)
	if panel and panel._gsSurfaceHost then
		panel._gsSurfaceHost:reflow(panel._gsSurfaceHost:getBounds())
	end
end

function AddonsTab.ensureRefreshHooks()
	-- The terminal lifecycle refreshes the SurfaceHost; no duplicate OnTick UI loop.
	return true
end
