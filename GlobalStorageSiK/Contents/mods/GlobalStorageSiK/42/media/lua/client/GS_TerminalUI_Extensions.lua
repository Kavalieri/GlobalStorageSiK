--[[
	GlobalStorageSiK - Extensiones de pestaña para addons
	Autor: SiK
	Fecha: 2026-08-04
	Descripción: Punto único data-driven que el Core expone para que un addon
	registre contenido de pestaña sin construir ni adjuntar paneles por su
	cuenta. El Core conserva una sola instancia por terminal y tabKey.
]]

require "ISUI/ISPanel"

GlobalStorageSiK.TerminalExtensions = GlobalStorageSiK.TerminalExtensions or {}
GlobalStorageSiK.TerminalExtensions._definitions = GlobalStorageSiK.TerminalExtensions._definitions or {}
GlobalStorageSiK.TerminalExtensions._staffActions = GlobalStorageSiK.TerminalExtensions._staffActions or {}

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
	GlobalStorageSiK.TerminalExtensions._staffActions[actionKey] = {
		key = actionKey,
		labelKey = opts.labelKey,
		order = tonumber(opts.order) or 100,
		invoke = opts.invoke,
		isAvailable = opts.isAvailable,
	}
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
---@param opts table { module, titleKey, iconPath, panelField, buildPanel?, setupPanel? }
---@return boolean ok
function GlobalStorageSiK.TerminalExtensions.registerDefinition(tabKey, opts)
	if type(tabKey) ~= "string" or tabKey == "" or type(opts) ~= "table" then
		return false
	end
	local module = opts.module
	local buildPanel = opts.buildPanel or (module and module.buildPanel)
	if type(buildPanel) ~= "function" or type(opts.titleKey) ~= "string" then
		return false
	end
	GlobalStorageSiK.TerminalExtensions._definitions[tabKey] = {
		module = module,
		titleKey = opts.titleKey,
		iconPath = opts.iconPath,
		panelField = opts.panelField,
		buildPanel = buildPanel,
		setupPanel = opts.setupPanel,
	}
	return true
end

--- Registra una pestaña extra en un terminal ya construido.
---@param terminal GS_TerminalUI
---@param tabKey string
---@param opts table { panel, module, titleKey, iconPath } - module expone
--- .refresh(panel, terminal) y opcionalmente .layout(panel, innerW, innerH)
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
	entry.module = opts.module or entry.module
	entry.titleKey = opts.titleKey or entry.titleKey
	entry.iconPath = opts.iconPath or entry.iconPath
	terminal.tabViews = terminal.tabViews or {}
	terminal.tabViews[tabKey] = opts.panel
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
	local fieldPanel = def.panelField and terminal[def.panelField] or nil
	if fieldPanel then
		local registered = GlobalStorageSiK.TerminalExtensions.registerTab(terminal, tabKey, {
			panel = fieldPanel,
			module = def.module,
			titleKey = def.titleKey,
			iconPath = def.iconPath,
		})
		return registered and fieldPanel or nil
	end
	local panel = ISPanel:new(0, 0, 10, 10)
	panel:initialise()
	panel.drawBackground = false
	panel.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
	panel.borderColor = { r = 0, g = 0, b = 0, a = 0 }
	panel.clipChildren = true
	panel:setScrollWithParent(false)
	if panel.setScrollChildren then
		panel:setScrollChildren(false)
	end
	panel:setVisible(false)
	def.buildPanel(panel, terminal)
	if type(def.setupPanel) == "function" then
		def.setupPanel(panel, terminal)
	end
	if def.panelField then
		terminal[def.panelField] = panel
	end
	local registered = GlobalStorageSiK.TerminalExtensions.registerTab(terminal, tabKey, {
		panel = panel,
		module = def.module,
		titleKey = def.titleKey,
		iconPath = def.iconPath,
	})
	if not registered then
		return nil
	end
	return panel
end

--- Muestra/oculta una pestaña extra ya registrada (delega en el tabRail).
---@param terminal GS_TerminalUI
---@param tabKey string
---@param visible boolean
function GlobalStorageSiK.TerminalExtensions.setTabVisible(terminal, tabKey, visible)
	if not terminal or not terminal.tabRail then
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
	terminal.tabRail:setDynamicTabVisible(visible, {
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
	if not entry or not entry.panel or not entry.module or not entry.module.refresh then
		return false
	end
	entry.module.refresh(entry.panel, terminal)
	return true
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
		if entry.panel then
			entry.panel:setX(0)
			entry.panel:setWidth(innerW)
			entry.panel:setHeight(innerH)
		end
		if entry.panel and entry.module and entry.module.layout then
			entry.module.layout(entry.panel, innerW, innerH)
		end
	end
end
