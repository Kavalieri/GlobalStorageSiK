-- Public terminal-extension contract for product addons.

require "GSSiK_API"
require "GS_PlayerUtils"
require "GS_TerminalUI_Extensions"

GSSiK.API.Terminal = GSSiK.API.Terminal or {}
local Terminal = GSSiK.API.Terminal

local OK = "OK"
local ERR_SCHEMA = "ERR_SCHEMA"
local ERR_UNAVAILABLE = "ERR_UNAVAILABLE"
local ERR_REQUEST = "ERR_REQUEST"

local function validId(value, limit)
	return type(value) == "string" and value ~= "" and #value <= (limit or 96)
end

local function extensions()
	return GlobalStorageSiK and GlobalStorageSiK.TerminalExtensions or nil
end

local function makeRegistration(id, generation, remover)
	local disposed = false
	local handle = { id = id }
	function handle:dispose()
		if disposed then return false end
		disposed = true
		return remover(id, generation) == true
	end
	return handle
end

function Terminal.registerTab(definition)
	if type(definition) ~= "table" or not validId(definition.key, 48)
		or not validId(definition.titleKey, 128)
		or type(definition.surface) ~= "table"
		or type(definition.contextFactory) ~= "function"
		or (definition.builder ~= nil and type(definition.builder) ~= "function")
		or definition.module ~= nil or definition.buildPanel ~= nil
		or definition.layout ~= nil or definition.refresh ~= nil
		or (definition.iconPath ~= nil and type(definition.iconPath) ~= "string")
		or (definition.panelField ~= nil and type(definition.panelField) ~= "string")
		or (definition.isVisible ~= nil and type(definition.isVisible) ~= "function")
		or (definition.enabledStateKey ~= nil
			and not validId(definition.enabledStateKey, 64)) then
		return false, ERR_SCHEMA, nil
	end
	local current = extensions()
	if not current or type(current.registerDefinition) ~= "function"
		or type(current.removeDefinitionIfGeneration) ~= "function" then
		return false, ERR_UNAVAILABLE, nil
	end
	local ok, generation = current.registerDefinition(definition.key, {
		surface = definition.surface,
		builder = definition.builder,
		contextFactory = definition.contextFactory,
		titleKey = definition.titleKey,
		iconPath = definition.iconPath,
		panelField = definition.panelField,
		isVisible = definition.isVisible,
		enabledStateKey = definition.enabledStateKey,
		refreshIntervalMs = tonumber(definition.refreshIntervalMs),
		order = tonumber(definition.order) or 100,
	})
	if ok ~= true or type(generation) ~= "number" then
		return false, ERR_REQUEST, nil
	end
	local handle = makeRegistration(definition.key, generation,
		current.removeDefinitionIfGeneration)
	handle.enabledStateKey = definition.enabledStateKey
	return true, OK, handle
end

function Terminal.registerStaffAction(actionKey, definition)
	if not validId(actionKey, 96) or type(definition) ~= "table"
		or not validId(definition.labelKey, 128)
		or type(definition.invoke) ~= "function"
		or (definition.isAvailable ~= nil
			and type(definition.isAvailable) ~= "function") then
		return false, ERR_SCHEMA, nil
	end
	local current = extensions()
	if not current or type(current.registerStaffAction) ~= "function"
		or type(current.removeStaffActionIfGeneration) ~= "function" then
		return false, ERR_UNAVAILABLE, nil
	end
	local ok, generation = current.registerStaffAction(actionKey, {
		labelKey = definition.labelKey,
		order = tonumber(definition.order) or 100,
		invoke = definition.invoke,
		isAvailable = definition.isAvailable,
	})
	if ok ~= true or type(generation) ~= "number" then
		return false, ERR_REQUEST, nil
	end
	return true, OK, makeRegistration(actionKey, generation,
		current.removeStaffActionIfGeneration)
end

function Terminal.current()
	local current = GlobalStorageSiK and GlobalStorageSiK.TerminalUI or nil
	return current and current.instance or nil
end

function Terminal.player(terminal)
	local utils = GlobalStorageSiK and GlobalStorageSiK.PlayerUtils or nil
	local playerNum = terminal and tonumber(terminal.playerNum) or 0
	if utils and type(utils.resolve) == "function" then
		return utils.resolve(playerNum)
	end
	return getSpecificPlayer and getSpecificPlayer(playerNum) or nil
end

function Terminal.state(terminal)
	local state = terminal and terminal.terminalState or nil
	if type(state) ~= "table" then return nil end
	local installedAddons = {}
	for addonId, descriptor in pairs(state.installedAddons or {}) do
		installedAddons[addonId] = descriptor == nil and nil or true
	end
	return {
		networkId = state.networkId,
		terminalAnchor = type(state.terminalAnchor) == "table" and {
			x = state.terminalAnchor.x,
			y = state.terminalAnchor.y,
			z = state.terminalAnchor.z,
		} or nil,
		accessMode = state.accessMode,
		craftTabEnabled = state.craftTabEnabled,
		buildTabEnabled = state.buildTabEnabled,
		installedAddons = installedAddons,
	}
end

function Terminal.isAddonInstalled(terminal, addonId)
	if not validId(addonId, 64) then return false end
	local state = Terminal.state(terminal)
	return state and type(state.installedAddons) == "table"
		and state.installedAddons[addonId] ~= nil or false
end

function Terminal.isTabEnabled(terminal, addonId, stateKey)
	if not validId(addonId, 64) then return false end
	local state = Terminal.state(terminal)
	if not state then return false end
	if stateKey and state[stateKey] ~= nil then return state[stateKey] == true end
	return Terminal.isAddonInstalled(terminal, addonId)
end

function Terminal.setTabVisible(terminal, tabKey, visible)
	if terminal == nil or not validId(tabKey, 48) or type(visible) ~= "boolean" then
		return false, ERR_SCHEMA
	end
	local current = extensions()
	if not current or type(current.setTabVisible) ~= "function" then
		return false, ERR_UNAVAILABLE
	end
	local changed = current.setTabVisible(terminal, tabKey, visible) == true
	return changed, changed and OK or ERR_REQUEST
end

function Terminal.refresh(terminal, tabKey)
	if terminal == nil or not validId(tabKey, 48) then return false end
	local current = extensions()
	return current and type(current.refreshActive) == "function"
		and current.refreshActive(terminal, tabKey) == true or false
end

return GSSiK.API
