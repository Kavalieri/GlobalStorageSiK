--[[
	GlobalStorageSiK - Extensiones de pestaña para addons
	Autor: SiK
	Fecha: 2026-08-04
	Descripción: Punto único data-driven que el Core expone para que un addon
	registre contenido de pestaña sin construir ni adjuntar paneles por su
	cuenta. El Core conserva una sola instancia por terminal y tabKey.
]]

local UI = require "GS_UI_Framework"

GlobalStorageSiK.TerminalExtensions = GlobalStorageSiK.TerminalExtensions or {}
GlobalStorageSiK.TerminalExtensions._definitions = GlobalStorageSiK.TerminalExtensions._definitions or {}
GlobalStorageSiK.TerminalExtensions._staffActions = GlobalStorageSiK.TerminalExtensions._staffActions or {}
GlobalStorageSiK.TerminalExtensions._generation =
	tonumber(GlobalStorageSiK.TerminalExtensions._generation) or 0

local function allocateGeneration()
	GlobalStorageSiK.TerminalExtensions._generation =
		GlobalStorageSiK.TerminalExtensions._generation + 1
	return GlobalStorageSiK.TerminalExtensions._generation
end

--- Registra una accion interna aportada por un addon para superficies de
--- diagnostico del Core. El Core solo conoce etiqueta, orden y callback; la
--- deteccion de mods externos y la apertura concreta siguen perteneciendo al
--- addon. Idempotente por actionKey para soportar recarga de Lua.
---@param actionKey string
---@param opts table { labelKey:string, order?:number, invoke:function, isAvailable?:function }
---@return boolean ok
function GlobalStorageSiK.TerminalExtensions.registerStaffAction(actionKey, opts)
	if type(actionKey) ~= "string" or actionKey == "" or type(opts) ~= "table"
		or type(opts.labelKey) ~= "string" or type(opts.invoke) ~= "function" then
		return false
	end
	local generation = allocateGeneration()
	GlobalStorageSiK.TerminalExtensions._staffActions[actionKey] = {
		key = actionKey,
		generation = generation,
		labelKey = opts.labelKey,
		order = tonumber(opts.order) or 100,
		invoke = opts.invoke,
		isAvailable = opts.isAvailable,
	}
	return true, generation
end

function GlobalStorageSiK.TerminalExtensions.removeStaffActionIfGeneration(actionKey, generation)
	local current = GlobalStorageSiK.TerminalExtensions._staffActions[actionKey]
	if not current or current.generation ~= generation then return false end
	GlobalStorageSiK.TerminalExtensions._staffActions[actionKey] = nil
	return true
end

--- Devuelve un snapshot estable y ordenado de las acciones disponibles.
--- Nunca expone la tabla de registro para que una UI no pueda mutarla al
--- recorrerla.
---@return table[] actions
function GlobalStorageSiK.TerminalExtensions.getStaffActions()
	local actions = {}
	for _, action in pairs(GlobalStorageSiK.TerminalExtensions._staffActions) do
		local available = true
		if type(action.isAvailable) == "function" then
			local ok, result = pcall(action.isAvailable)
			available = ok and result ~= false
		end
		if available then
			actions[#actions + 1] = action
		end
	end
	table.sort(actions, function(a, b)
		if a.order == b.order then
			return tostring(a.key) < tostring(b.key)
		end
		return a.order < b.order
	end)
	return actions
end

--- Registra la definicion global de una pestaña. Es idempotente por tabKey:
--- una recarga del fichero actualiza la definicion, pero no crea UI.
---@param tabKey string
---@param opts table { surface, builder?, contextFactory, titleKey, iconPath?, panelField?, isVisible?, enabledStateKey? }
---@return boolean ok
function GlobalStorageSiK.TerminalExtensions.registerDefinition(tabKey, opts)
	if type(tabKey) ~= "string" or tabKey == "" or type(opts) ~= "table" then
		return false
	end
	if type(opts.surface) ~= "table" or type(opts.contextFactory) ~= "function"
		or type(opts.titleKey) ~= "string" or opts.module ~= nil
		or opts.buildPanel ~= nil or opts.layout ~= nil or opts.refresh ~= nil
		or (opts.builder ~= nil and type(opts.builder) ~= "function")
		or (opts.isVisible ~= nil and type(opts.isVisible) ~= "function")
		or (opts.enabledStateKey ~= nil and type(opts.enabledStateKey) ~= "string") then
		return false
	end
	local generation = allocateGeneration()
	GlobalStorageSiK.TerminalExtensions._definitions[tabKey] = {
		generation = generation,
		surface = opts.surface,
		builder = opts.builder or SiK.UI.SurfaceHost.mount,
		contextFactory = opts.contextFactory,
		titleKey = opts.titleKey,
		iconPath = opts.iconPath,
		panelField = opts.panelField,
		isVisible = opts.isVisible,
		enabledStateKey = opts.enabledStateKey,
		refreshIntervalMs = tonumber(opts.refreshIntervalMs),
		order = tonumber(opts.order) or 100,
	}
	return true, generation
end

function GlobalStorageSiK.TerminalExtensions.syncVisibilityAll(terminal)
	local definitions = {}
	for tabKey, definition in pairs(GlobalStorageSiK.TerminalExtensions._definitions) do
		definitions[#definitions + 1] = { key = tabKey, definition = definition }
	end
	table.sort(definitions, function(left, right)
		if left.definition.order == right.definition.order then
			return left.key < right.key
		end
		return left.definition.order < right.definition.order
	end)
	for index = 1, #definitions do
		local definition = definitions[index].definition
		local visible = nil
		if type(definition.isVisible) == "function" then
			local ok, result = pcall(definition.isVisible, terminal)
			visible = ok and result == true
		elseif definition.enabledStateKey then
			local state = terminal and terminal.terminalState or nil
			visible = type(state) == "table"
				and state[definition.enabledStateKey] == true
		end
		if visible ~= nil then
			GlobalStorageSiK.TerminalExtensions.setTabVisible(terminal,
				definitions[index].key, visible)
		end
	end
end

function GlobalStorageSiK.TerminalExtensions.removeDefinitionIfGeneration(tabKey, generation)
	local current = GlobalStorageSiK.TerminalExtensions._definitions[tabKey]
	if not current or current.generation ~= generation then return false end
	GlobalStorageSiK.TerminalExtensions._definitions[tabKey] = nil
	return true
end

--- Registra una pestaña extra en un terminal ya construido.
---@param terminal GS_TerminalUI
---@param tabKey string
---@param opts table { panel, host, titleKey, iconPath }
function GlobalStorageSiK.TerminalExtensions.registerTab(terminal, tabKey, opts)
	if not terminal or not tabKey or not opts or not opts.panel then
		return false
	end
	terminal.extraTabs = terminal.extraTabs or {}
	local existing = terminal.extraTabs[tabKey]
	if existing and existing.panel ~= opts.panel then
		return false
	end
	terminal.extraTabs[tabKey] = existing or {
		panel = opts.panel,
	}
	local entry = terminal.extraTabs[tabKey]
	entry.host = opts.host or entry.host
	entry.titleKey = opts.titleKey or entry.titleKey
	entry.iconPath = opts.iconPath or entry.iconPath
	if GlobalStorageSiK.TerminalTabs then
		GlobalStorageSiK.TerminalTabs.registerPanel(terminal, tabKey, opts.panel)
	end
	return true
end

--- Materializa exactamente una instancia del panel definido para este terminal.
--- El addon aporta contenido; el Core crea y registra la superficie.
---@param terminal GS_TerminalUI
---@param tabKey string
---@return ISPanel|nil panel
function GlobalStorageSiK.TerminalExtensions.ensureTab(terminal, tabKey)
	if not terminal or not tabKey then
		return nil
	end
	local existing = terminal.extraTabs and terminal.extraTabs[tabKey]
	if existing and existing.panel then
		GlobalStorageSiK.Log.debug("SiKUITabs", "ensureTab reuse", "tabKey=" .. tostring(tabKey))
		return existing.panel
	end
	local def = GlobalStorageSiK.TerminalExtensions._definitions[tabKey]
	if not def then
		GlobalStorageSiK.Log.debug("SiKUITabs", "ensureTab sin definicion registrada", "tabKey=" .. tostring(tabKey))
		return nil
	end
	GlobalStorageSiK.Log.debug("SiKUITabs", "ensureTab build (primera vez para este terminal)", "tabKey=" .. tostring(tabKey))
	-- The navigation destination is the real parent. It must exist and have
	-- completed its own layout before any product widget is constructed.
	GlobalStorageSiK.TerminalTabs.setDynamicVisible(terminal, true, {
		key = tabKey,
		titleKey = def.titleKey,
		panelField = nil,
		iconPath = def.iconPath,
	})
	local parent = terminal.navigationContainer:getContentHost(tabKey)
	if not parent or (tonumber(parent.width) or 0) <= 1
		or (tonumber(parent.height) or 0) <= 1 then
		GlobalStorageSiK.Log.error("SiKUITabs", "destino sin geometria final",
			"tabKey=" .. tostring(tabKey))
		return nil
	end
	local panel = UI.Controls.panel(parent, {
		x = 0, y = 0, w = parent.width, h = parent.height, drawBackground = false,
		backgroundColor = { r = 0, g = 0, b = 0, a = 0 },
		borderColor = { r = 0, g = 0, b = 0, a = 0 },
		controlId = "addonTabHost", playerNum = terminal.playerNum,
	})
	panel.clipChildren = true
	panel:setScrollWithParent(false)
	if panel.setScrollChildren then
		panel:setScrollChildren(false)
	end
	panel:setVisible(false)
	local registered = GlobalStorageSiK.TerminalExtensions.registerTab(terminal, tabKey, {
		panel = panel,
		titleKey = def.titleKey,
		iconPath = def.iconPath,
	})
	if not registered then
		return nil
	end
	local context, contextReason = def.contextFactory(terminal)
	if type(context) ~= "table" then
		GlobalStorageSiK.Log.error("SiKUITabs", "contextFactory invalido",
			"tabKey=" .. tostring(tabKey) .. " reason=" .. tostring(contextReason))
		return nil
	end
	local host, hostReason = def.builder(panel, def.surface, {
		context = context,
		contextProvider = function()
			return def.contextFactory(terminal)
		end,
		followParent = true,
		onError = function(payload)
			GlobalStorageSiK.Log.error("SiKUITabs", "surface host",
				"tabKey=" .. tostring(tabKey) .. " reason=" .. tostring(payload and payload.reason))
		end,
	})
	if not host then
		GlobalStorageSiK.Log.error("SiKUITabs", "surface mount fallo",
			"tabKey=" .. tostring(tabKey) .. " reason=" .. tostring(hostReason))
		return nil
	end
	panel._sikSurfaceHost = host
	terminal.extraTabs[tabKey].host = host
	if def.panelField then
		terminal[def.panelField] = panel
	end
	return panel
end

--- Muestra/oculta una pestaña extra ya registrada en la navegación del Container.
---@param terminal GS_TerminalUI
---@param tabKey string
---@param visible boolean
function GlobalStorageSiK.TerminalExtensions.setTabVisible(terminal, tabKey, visible)
	if not terminal or not terminal.navigationContainer then
		return false
	end
	if visible then
		GlobalStorageSiK.TerminalExtensions.ensureTab(terminal, tabKey)
	end
	local entry = terminal.extraTabs and terminal.extraTabs[tabKey]
	if not entry then
		return false
	end
	GlobalStorageSiK.Log.debug("SiKUITabs", "setTabVisible", "tabKey=" .. tostring(tabKey) .. " visible=" .. tostring(visible))
	GlobalStorageSiK.TerminalTabs.setDynamicVisible(terminal, visible, {
		key = tabKey,
		titleKey = entry.titleKey,
		panelField = nil,
		iconPath = entry.iconPath,
	})
	return true
end

--- Refresca la pestaña extra activa, si "tab" coincide con alguna registrada.
---@param terminal GS_TerminalUI
---@param tab string
---@return boolean handled
function GlobalStorageSiK.TerminalExtensions.refreshActive(terminal, tab)
	local entry = terminal and terminal.extraTabs and terminal.extraTabs[tab]
	if not entry or not entry.host then
		return false
	end
	local updated = entry.host:refresh()
	return updated ~= nil
end

--- Aplica layout a todas las pestañas extra registradas.
---@param terminal GS_TerminalUI
---@param innerW number
---@param innerH number
function GlobalStorageSiK.TerminalExtensions.layoutAll(terminal, innerW, innerH)
	if not terminal or not terminal.extraTabs then
		return
	end
	for _, entry in pairs(terminal.extraTabs) do
		if entry.host then
			entry.host:reflow({ x = 0, y = 0, w = innerW, h = innerH })
		end
	end
end

function GlobalStorageSiK.TerminalExtensions.layoutActive(terminal, tabKey, innerW, innerH)
	local entry = terminal and terminal.extraTabs and terminal.extraTabs[tabKey]
	if entry and entry.host then
		entry.host:reflow({ x = 0, y = 0, w = innerW, h = innerH })
	end
end
