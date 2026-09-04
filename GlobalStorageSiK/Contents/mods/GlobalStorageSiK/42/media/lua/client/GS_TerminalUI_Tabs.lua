--[[

	GlobalStorageSiK - Pestañas laterales (adaptador de SiK.UI.Tabs)

	Autor: SiK

	Fecha: 2025-06-25

]]



local UI = require "GS_UI_Framework"

require "GS_I18n"

require "GS_Sandbox"

local T = GlobalStorageSiK.I18n.text

local function railProfile()
	return UI.Metrics.profile(0, "terminal")
end

local function copyDefinition(definition)
	local copy = {}
	for key, value in pairs(definition or {}) do copy[key] = value end
	return copy
end

local function navigationItem(definition, pinned)
	local title = T(definition.titleKey)
	local item = {
		key = definition.key, text = title, tooltip = title,
		icon = { path = definition.iconPath, width = 72, height = 72 },
		iconSize = 72, iconExact = true, iconOnly = true, payload = definition,
	}
	if pinned then item.pin = "end" end
	return item
end

local function navigationItems(terminal)
	local items = {}
	for i = 1, #(terminal.tabDefs or {}) do
		items[#items + 1] = navigationItem(terminal.tabDefs[i], false)
	end
	for i = 1, #(terminal.dynamicTabDefs or {}) do
		items[#items + 1] = navigationItem(terminal.dynamicTabDefs[i], false)
	end
	if terminal.footerTabDef then items[#items + 1] = navigationItem(terminal.footerTabDef, true) end
	return items
end

local function navigationOptions(terminal, items)
	local profile = railProfile()
	return {
		placement = "left", activeKey = terminal.activeTabKey or "items",
		items = items, extent = profile.window.railWidth,
		iconOnly = true, itemExtent = profile.window.railItemHeight,
		iconSize = profile.window.railIconSize, iconFit = "contain", iconPadding = 0,
		barPadding = profile.window.railPadding, itemGap = profile.window.railGap,
		separator = true, separatorOffset = 6,
		selectionStyle = "border",
		backgroundColor = { r = 0.05, g = 0.05, b = 0.05, a = 0.96 },
		selectedBackgroundColor = { r = 0.12, g = 0.10, b = 0.08, a = 0.96 },
		hoverBackgroundColor = { r = 0.10, g = 0.10, b = 0.10, a = 0.96 },
		pressedBackgroundColor = { r = 0.08, g = 0.07, b = 0.06, a = 0.96 },
		borderColor = { r = 0, g = 0, b = 0, a = 0 },
		selectedBorderColor = { r = 0.95, g = 0.55, b = 0.15, a = 0.90 },
		iconColor = { r = 0.88, g = 0.88, b = 0.88, a = 0.88 },
		hoverIconColor = { r = 0.92, g = 0.92, b = 0.92, a = 1 },
		selectedIconColor = { r = 0.95, g = 0.55, b = 0.15, a = 1 },
		hoverIconScale = 1,
		separatorColor = { r = 0.35, g = 0.35, b = 0.35, a = 0.45 },
		tooltipMode = "flyout", tooltipSide = "before", tooltipGap = 4,
		tooltipBackgroundColor = { r = 0.10, g = 0.10, b = 0.10, a = 0.95 },
		tooltipBorderColor = { r = 0.40, g = 0.40, b = 0.40, a = 0.90 },
		tooltipTextColor = { r = 0.92, g = 0.94, b = 0.96, a = 1 },
		onActivate = function(context)
			local item = context and context.value
			if item and terminal.activateTab then terminal:activateTab(item.key) end
		end,
	}
end

local function syncNavigationSelection(terminal)
	local navigation = terminal.navigationContainer and terminal.navigationContainer.navigation
	if not navigation then return end
	local active = terminal.activeTabKey or "items"
	if not navigation:setActive(active, false) then navigation:setActive("items", false) end
	local incident = terminal.networkIncident
	local alert = false
	if incident and incident.count and incident.count > 0 then
		local danger = incident.level ~= "amber"
		alert = {
			icon = danger and "sik.alert.danger.24" or "sik.alert.warning.24",
			size = 24, margin = 2, severity = danger and "danger" or "warning",
			glow = true, tooltip = incident.tooltip,
		}
	end
	navigation:updateItem("network", { alert = alert })
end

local function buildNavigation(terminal)
	local shell = UI.Window.chromeRects(terminal)
	local container, err = UI.Container.create({ parent = terminal,
		x = shell.content.x, y = shell.content.y,
		w = shell.content.w, h = shell.content.h,
		bounds = { x = shell.content.x, y = shell.content.y,
			w = shell.content.w, h = shell.content.h },
		padding = 0, controlId = "terminal-surface",
		navigation = navigationOptions(terminal, navigationItems(terminal)),
	})
	if not container then error("SiK.UI.Container navigation failed: " .. tostring(err)) end
	terminal.navigationContainer = container
end

local function layoutNavigation(terminal, bounds)
	if not terminal.navigationContainer then return end
	terminal.navigationContainer:reflow(bounds)
	syncNavigationSelection(terminal)
end

GlobalStorageSiK.TerminalTabs = {}



--- Construye la columna lateral SiK UI y el área de contenido.

---@param terminal GS_TerminalUI

---@param tabDefs table[]

function GlobalStorageSiK.TerminalTabs.build(terminal, tabDefs)

	terminal.tabPanels = {}

	terminal.tabDefs = tabDefs
	terminal.dynamicTabDefs = terminal.dynamicTabDefs or {}
	terminal.dynamicTabDefByKey = terminal.dynamicTabDefByKey or {}
	terminal.activeTabKey = "items"
	buildNavigation(terminal)

	for i = 1, #tabDefs do

		local def = tabDefs[i]

		local panel = terminal[def.panelField]

		if panel then

			panel:setX(0)

			panel:setY(0)

			panel.clipChildren = true

			terminal.tabPanels[def.key] = panel
			terminal.navigationContainer:mountContent(def.key, panel)

		end

	end



	if terminal.footerTabDef then

		local fdef = terminal.footerTabDef

		local fpanel = terminal[fdef.panelField]

		if fpanel then

			fpanel:setX(0)

			fpanel:setY(0)

			fpanel.clipChildren = true

			terminal.tabPanels[fdef.key] = fpanel
			terminal.navigationContainer:mountContent(fdef.key, fpanel)

		end

	end



	terminal.navigationContainer:setActive("items", false)

end



--- Ancho de columna lateral.

---@param terminal GS_TerminalUI

---@return number

function GlobalStorageSiK.TerminalTabs.measureRailWidth(terminal)

	return railProfile().window.railWidth

end



--- Reposiciona columna lateral.

---@param terminal GS_TerminalUI

function GlobalStorageSiK.TerminalTabs.layoutRail(terminal)
	local panel = terminal.navigationContainer and terminal.navigationContainer.panel
	if panel then layoutNavigation(terminal, { x = panel.x, y = panel.y, w = panel.width, h = panel.height }) end

end



--- Compatibilidad.

---@param terminal GS_TerminalUI

function GlobalStorageSiK.TerminalTabs.layoutBar(terminal)

	GlobalStorageSiK.TerminalTabs.layoutRail(terminal)

end

function GlobalStorageSiK.TerminalTabs.registerPanel(terminal, tabKey, panel)
	if not terminal or not tabKey or not panel then return false end
	terminal.tabPanels = terminal.tabPanels or {}
	terminal.tabPanels[tabKey] = panel
	if not terminal.navigationContainer then return false end
	return terminal.navigationContainer:mountContent(tabKey, panel) ~= nil
end

function GlobalStorageSiK.TerminalTabs.setDynamicVisible(terminal, visible, definition)
	if not terminal or not terminal.navigationContainer then return false end
	local def = copyDefinition(definition or {})
	local key = def.key or "craft"
	def.key = key
	terminal.dynamicTabDefs = terminal.dynamicTabDefs or {}
	terminal.dynamicTabDefByKey = terminal.dynamicTabDefByKey or {}
	if visible then
		if not terminal.dynamicTabDefByKey[key] then
			terminal.dynamicTabDefByKey[key] = def
			terminal.dynamicTabDefs[#terminal.dynamicTabDefs + 1] = def
		end
	else
		if not terminal.dynamicTabDefByKey[key] then return true end
		terminal.dynamicTabDefByKey[key] = nil
		for index = #terminal.dynamicTabDefs, 1, -1 do
			if terminal.dynamicTabDefs[index].key == key then
				table.remove(terminal.dynamicTabDefs, index)
				break
			end
		end
		if terminal.activeTabKey == key and terminal.activateTab then terminal:activateTab("items") end
	end
	local navigation = terminal.navigationContainer.navigation
	navigation:setItems(navigationItems(terminal))
	for tabKey, panel in pairs(terminal.tabPanels or {}) do
		terminal.navigationContainer:mountContent(tabKey, panel)
	end
	syncNavigationSelection(terminal)
	return true
end



--- Oculta rail lateral en modo bloqueo y restaura orden Z del contenido.
--- CRITICO: esta funcion se llama desde GS_TerminalUI:prerender(), es decir
--- en CADA frame renderizado (30-60+ veces por segundo) mientras la ventana
--- esta abierta. Antes hacia bringToTop() sobre contentHost/closeBtn de forma
--- incondicional en cada llamada - reordenar la pila de hijos constantemente
--- interrumpe cualquier secuencia mousedown->mouseup en curso sobre los
--- botones de la pantalla bloqueada (una pulsacion humana siempre dura mas de
--- un frame), asi que el clic se perdia silenciosamente - "Instalar aqui",
--- "Conseguir PC" y "Mostrar cobertura" no reaccionaban por ESTO, no por
--- estar deshabilitados. Ahora el reordenamiento de capas solo se ejecuta la
--- PRIMERA vez que se entra o se sale del modo bloqueado, no en cada frame.
---@param terminal GS_TerminalUI
function GlobalStorageSiK.TerminalTabs.syncBlockedFrame(terminal)
	if not terminal then
		return
	end
	local blocked = terminal.accessMode == "blocked"
	if terminal._gsBlockedFrameState == blocked then
		return
	end
	terminal._gsBlockedFrameState = blocked
	local navigation = terminal.navigationContainer and terminal.navigationContainer.navigation
	if navigation then navigation:setBarVisible(not blocked) end
	if blocked and terminal.navigationContainer and terminal.navigationContainer.panel then
		terminal.navigationContainer.panel:bringToTop()
	end
	if terminal.closeBtn then
		terminal.closeBtn:bringToTop()
	end
end



--- Activa pestaña por clave.

---@param terminal GS_TerminalUI

---@param tabKey string

function GlobalStorageSiK.TerminalTabs.activate(terminal, tabKey)
	local startedMs = GlobalStorageSiK.UIDebug and GlobalStorageSiK.UIDebug.enabled()
		and type(getTimestampMs) == "function" and getTimestampMs() or nil

	-- BUG REAL DE DISEÑO cerrado (2026-08-26, pedido explicito tras el fix de
	-- fallthrough de clic en GS_TerminalTabSlot: "evitar que cualquier click
	-- no capturado caiga en la pestaña de addon - si tiene que haber una por
	-- defecto, que sea el almacen"): una clave invalida/vacia (nil, o una
	-- pestaña que ya no existe - p.ej. un addon desinstalado entre sync y
	-- clic) caia antes en el `return` silencioso de mas abajo, dejando la
	-- pestaña activa TAL CUAL estuviera - inofensivo en la practica, pero
	-- ninguna garantia explicita de que un futuro bug similar no pudiera
	-- colar "addons" por esa via. Normalizado aqui, ANTES de cualquier otra
	-- logica: una clave que no sea una de las fijas conocidas nunca activa
	-- "addons" por defecto - cae siempre a "items".
	if tabKey ~= "items" and tabKey ~= "network" and tabKey ~= "config" and tabKey ~= "addons"
		and not (terminal.tabPanels and terminal.tabPanels[tabKey]) then
		tabKey = "items"
	end

	-- BUG REAL reportado por el usuario (2026-08-26, captura real: "no hay
	-- electricidad" solo se descubria al fallar una transferencia): sin
	-- energia, el terminal dejaba navegar libremente a Almacen/Addons. Ahora
	-- se redirige siempre a Configuracion -> sub-pestaña "Estado" (que ya
	-- muestra el indicador de energia, ver GS_TerminalUI_NetworkStatus.lua:
	-- valPower - mudada aqui en dev41 desde Red -> Red, que se quedo solo
	-- con "Zonas y nodos") en vez de esas dos pestañas mientras la red no
	-- tenga energia. Diseño pendiente de remodelar mas adelante (ver
	-- comentario del usuario) - por ahora reutiliza el resumen ya
	-- existente, no crea una pantalla nueva.
	local forceStatusTab = false
	if (tabKey == "items" or tabKey == "addons")
		and GlobalStorageSiK.Sandbox.requiresPower()
		and terminal.terminalState and terminal.terminalState.powered == false then
		tabKey = "config"
		forceStatusTab = true
	end
	if terminal.ensureTabBuilt then terminal:ensureTabBuilt(tabKey) end
	if forceStatusTab and terminal.configPanel then terminal.configPanel.activeSubTab = "estado" end

	if not terminal.tabPanels or not terminal.tabPanels[tabKey]
		or not terminal.navigationContainer then

		return

	end
	if terminal.activeTabKey == tabKey and terminal._gsActivatedTabKey == tabKey
		and not forceStatusTab then
		if terminal.accessMode ~= "blocked" then syncNavigationSelection(terminal) end
		GlobalStorageSiK.TerminalTabs.syncBlockedFrame(terminal)
		return tabKey
	end

	if terminal.activeTabKey == "network" and tabKey ~= "network" then

		if GlobalStorageSiK.NodeHighlight and GlobalStorageSiK.NodeHighlight.clear then

			GlobalStorageSiK.NodeHighlight.clear()

		end

	end

	terminal.activeTabKey = tabKey
	terminal._gsActivatedTabKey = tabKey
	local navigation = terminal.navigationContainer.navigation
	navigation:setActive(tabKey, false)



	-- CRITICO: calculateLayout() SIEMPRE antes de rellenar contenido de la
	-- pestaña. Antes, los callbacks concretos de cada pestaña (que llaman a
	-- su refresh()) se ejecutaban aqui, ANTES de calculateLayout() - refresh()
	-- posiciona botones leyendo el ancho ACTUAL del scroll, que en ese
	-- momento todavia era el de construccion (p.ej. 280x120 por defecto),
	-- no el tamaño real de la ventana del terminal. El resultado: la zona
	-- realmente pulsable (el scroll, redimensionado luego por
	-- calculateLayout) no coincidia con donde se habian colocado los
	-- botones - visualmente parecia estar ahi pero el clic no llegaba.
	-- Mismo patron de bug que ya se dio y se arreglo en otras pantallas de
	-- este mod (ver comentario en syncBlockedFrame mas abajo) - la regla
	-- general para CUALQUIER pantalla nueva: dimensionar primero, rellenar
	-- despues, nunca al reves.
	if terminal.calculateLayout then

		terminal:calculateLayout()

	end

	if terminal.refreshActiveTabContent then

		terminal:refreshActiveTabContent()

	end

	if terminal.accessMode ~= "blocked" then syncNavigationSelection(terminal) end

	GlobalStorageSiK.TerminalTabs.syncBlockedFrame(terminal)

	-- Los volcados geometricos completos siguen disponibles mediante
	-- TerminalUI.debugDumpTree(), pero nunca forman parte de la interaccion
	-- ordinaria: recorrer dos veces todo el arbol al cambiar de pestaña
	-- bloqueaba el hilo UI incluso con el diagnostico habilitado.
	if startedMs then
		GlobalStorageSiK.UIDebug.action("tab_activate",
			"tab=" .. tostring(tabKey)
				.. " durationMs=" .. tostring(getTimestampMs() - startedMs))
	end

end



--- Cambia modo de acceso: pestañas completas o solo panel bloqueado.

---@param terminal GS_TerminalUI

---@param mode string "full"|"blocked"

---@param blockedState table|nil

function GlobalStorageSiK.TerminalTabs.applyAccessMode(terminal, mode, blockedState)

	if not terminal then

		return

	end

	local nextMode = mode or "full"
	local previousMode = terminal.accessMode
	terminal.accessMode = nextMode
	if terminal.syncHeaderChrome then terminal:syncHeaderChrome() end
	if previousMode == nextMode and nextMode == "full" then
		GlobalStorageSiK.TerminalTabs.syncBlockedFrame(terminal)
		return
	end

	if blockedState then

		terminal.blockedState = blockedState

	end

	local blocked = terminal.accessMode == "blocked"

	if blocked then

		if GlobalStorageSiK.TerminalBlockedPanel and GlobalStorageSiK.TerminalBlockedPanel.ensureEvents then

			GlobalStorageSiK.TerminalBlockedPanel.ensureEvents()

		end

		GlobalStorageSiK.TerminalTabs.activate(terminal, "blocked")

		if GlobalStorageSiK.TerminalBlockedPanel and GlobalStorageSiK.TerminalBlockedPanel.refresh then

			GlobalStorageSiK.TerminalBlockedPanel.refresh(terminal, terminal.blockedState)

		end

	else

		-- Blocked y full son estados del mismo Shell. La transición solo limita
		-- su geometría al viewport/perfil del jugador; nunca aplica otro tamaño
		-- de ventana ni consulta la pantalla global.
		if terminal.applyResponsiveBounds then
			terminal:applyResponsiveBounds(terminal.x, terminal.y, terminal.width, terminal.height)
		end

		local tab = terminal.activeTabKey or "items"

		if tab == "blocked" or not terminal.tabPanels or not terminal.tabPanels[tab] then

			tab = "items"

		end

		GlobalStorageSiK.TerminalTabs.activate(terminal, tab)

	end

	if terminal.calculateLayout then

		terminal:calculateLayout()

	end

	GlobalStorageSiK.TerminalTabs.syncBlockedFrame(terminal)

	if GlobalStorageSiK.TerminalBlockedUI then

		if blocked then

			GlobalStorageSiK.TerminalBlockedUI.instance = terminal

		elseif GlobalStorageSiK.TerminalBlockedUI.instance == terminal then

			GlobalStorageSiK.TerminalBlockedUI.instance = nil

		end

	end

end

