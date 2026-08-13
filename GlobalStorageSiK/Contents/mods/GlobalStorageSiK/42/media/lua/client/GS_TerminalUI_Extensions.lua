--[[
	GlobalStorageSiK - Extensiones de pestaña para addons
	Autor: SiK
	Fecha: 2026-08-04
	Descripción: Punto único que el Core expone para que un addon (Craft,
	Builder, o cualquier otro futuro) añada su propia pestaña al terminal sin
	tocar GS_TerminalUI.lua. No sustituye la pestaña "craft" ya cableada a
	mano (se deja intacta por compatibilidad), es la vía para todo lo nuevo.
]]

GlobalStorageSiK.TerminalExtensions = GlobalStorageSiK.TerminalExtensions or {}

--- Registra una pestaña extra en un terminal ya construido.
---@param terminal GS_TerminalUI
---@param tabKey string
---@param opts table { panel, module, titleKey, iconPath } - module expone
--- .refresh(panel, terminal) y opcionalmente .layout(panel, innerW, innerH)
function GlobalStorageSiK.TerminalExtensions.registerTab(terminal, tabKey, opts)
	if not terminal or not tabKey or not opts or not opts.panel then
		return
	end
	terminal.extraTabs = terminal.extraTabs or {}
	terminal.extraTabs[tabKey] = {
		panel = opts.panel,
		module = opts.module,
		titleKey = opts.titleKey,
		iconPath = opts.iconPath,
	}
	terminal.tabViews = terminal.tabViews or {}
	terminal.tabViews[tabKey] = opts.panel
end

--- Muestra/oculta una pestaña extra ya registrada (delega en el tabRail).
---@param terminal GS_TerminalUI
---@param tabKey string
---@param visible boolean
function GlobalStorageSiK.TerminalExtensions.setTabVisible(terminal, tabKey, visible)
	if not terminal or not terminal.tabRail then
		return
	end
	local entry = terminal.extraTabs and terminal.extraTabs[tabKey]
	if not entry then
		return
	end
	terminal.tabRail:setCraftTabVisible(visible, {
		key = tabKey,
		titleKey = entry.titleKey,
		panelField = nil,
		iconPath = entry.iconPath,
	})
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
