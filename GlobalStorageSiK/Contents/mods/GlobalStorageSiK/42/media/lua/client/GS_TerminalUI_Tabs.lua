--[[

	GlobalStorageSiK - Pestañas laterales (delega en GS_TerminalTabRail)

	Autor: SiK

	Fecha: 2025-06-25

]]



require "ISUI/ISPanel"

require "GS_I18n"

require "GS_Sandbox"

require "GS_TerminalUI_TabRail"



GlobalStorageSiK.TerminalTabs = {}



---@param host ISPanel

---@param panel ISPanel|nil

-- Comprueba pertenencia real en childrenInOrder (array que PZ renderiza).
-- NO usar getParent(): PZ removeChild NO limpia .parent, queda stale y rompe
-- la re-adición (inventario vacío al volver de otra pestaña).
---@param host ISPanel
---@param panel ISPanel
---@return boolean
local function isChildOf(host, panel)

	local ch = host and host.childrenInOrder

	if type(ch) ~= "table" then

		return false

	end

	for i = 1, #ch do

		if ch[i] == panel then

			return true

		end

	end

	return false

end



---@param host ISPanel

---@param panel ISPanel|nil

local function detachPanel(host, panel)

	if not host or not panel then

		return

	end

	if isChildOf(host, panel) then

		host:removeChild(panel)

	end

	panel:setVisible(false)

end



---@param host ISPanel

---@param panel ISPanel|nil

local function attachPanel(host, panel)

	if not host or not panel then

		return

	end

	panel:setX(0)

	panel:setY(0)

	panel:setVisible(true)

	-- Evitar doble-add: addChild hace table.insert(childrenInOrder,...) SIN comprobar
	-- duplicados. Comprobamos pertenencia real, no getParent() (queda stale).
	if isChildOf(host, panel) then

		return

	end

	host:addChild(panel)

end



--- Construye la columna lateral SiK UI y el área de contenido.

---@param terminal GS_TerminalUI

---@param tabDefs table[]

function GlobalStorageSiK.TerminalTabs.build(terminal, tabDefs)

	terminal.tabViews = {}

	terminal.tabDefs = tabDefs



	terminal.contentHost = ISPanel:new(0, 0, 10, 10)

	terminal.contentHost:initialise()

	terminal.contentHost.drawBackground = false

	terminal.contentHost.clipChildren = true

	terminal.contentHost:setScrollWithParent(false)

	if terminal.contentHost.setScrollChildren then

		terminal.contentHost:setScrollChildren(false)

	end

	terminal:addChild(terminal.contentHost)



	for i = 1, #tabDefs do

		local def = tabDefs[i]

		local panel = terminal[def.panelField]

		if panel then

			panel:setX(0)

			panel:setY(0)

			panel:setVisible(false)

			panel.clipChildren = true

			terminal.tabViews[def.key] = panel

		end

	end



	if terminal.footerTabDef then

		local fdef = terminal.footerTabDef

		local fpanel = terminal[fdef.panelField]

		if fpanel then

			fpanel:setX(0)

			fpanel:setY(0)

			fpanel:setVisible(false)

			fpanel.clipChildren = true

			terminal.tabViews[fdef.key] = fpanel

		end

	end



	GlobalStorageSiK.TerminalTabRail.build(terminal, tabDefs, terminal.footerTabDef)

	terminal.activeTabKey = "items"

	attachPanel(terminal.contentHost, terminal.tabViews.items)

end



--- Ancho de columna lateral.

---@param terminal GS_TerminalUI

---@return number

function GlobalStorageSiK.TerminalTabs.measureRailWidth(terminal)

	return GlobalStorageSiK.TerminalTabRail.measureWidth(terminal.tabDefs)

end



--- Reposiciona columna lateral.

---@param terminal GS_TerminalUI

function GlobalStorageSiK.TerminalTabs.layoutRail(terminal)

	GlobalStorageSiK.TerminalTabRail.layout(terminal)

end



--- Compatibilidad.

---@param terminal GS_TerminalUI

function GlobalStorageSiK.TerminalTabs.layoutBar(terminal)

	GlobalStorageSiK.TerminalTabs.layoutRail(terminal)

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
	if terminal.tabRail then
		if blocked then
			if terminal.tabRail.hideFlyout then
				terminal.tabRail:hideFlyout()
			end
			terminal.tabRail:setVisible(false)
			terminal.tabRail:setX(-4096)
			terminal.tabRail:setWidth(1)
			if terminal.tabRail.setMouseTransparent then
				terminal.tabRail:setMouseTransparent(true)
			end
		else
			terminal.tabRail:setVisible(true)
			terminal.tabRail:setX(0)
			if terminal.tabRail.setMouseTransparent then
				terminal.tabRail:setMouseTransparent(false)
			end
		end
	end
	if blocked and terminal.contentHost then
		terminal.contentHost:bringToTop()
	end
	if terminal.closeBtn then
		terminal.closeBtn:bringToTop()
	end
end



--- Activa pestaña por clave.

---@param terminal GS_TerminalUI

---@param tabKey string

function GlobalStorageSiK.TerminalTabs.activate(terminal, tabKey)

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
		and not (terminal.tabViews and terminal.tabViews[tabKey]) then
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
	if (tabKey == "items" or tabKey == "addons")
		and GlobalStorageSiK.Sandbox.requiresPower()
		and terminal.terminalState and terminal.terminalState.powered == false then
		tabKey = "config"
		if terminal.configPanel then
			terminal.configPanel.activeSubTab = "estado"
		end
	end

	if not terminal.tabViews or not terminal.tabViews[tabKey] or not terminal.contentHost then

		return

	end

	if terminal.activeTabKey == "network" and tabKey ~= "network" then

		if GlobalStorageSiK.NodeHighlight and GlobalStorageSiK.NodeHighlight.clear then

			GlobalStorageSiK.NodeHighlight.clear()

		end

	end

	local activePanel = terminal.tabViews[tabKey]

	for _, panel in pairs(terminal.tabViews) do

		if panel ~= activePanel then

			detachPanel(terminal.contentHost, panel)

		end

	end

	attachPanel(terminal.contentHost, activePanel)

	terminal.activeTabKey = tabKey



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

	if tabKey == "addons" and terminal.onAddonsTabActivated then

		terminal:onAddonsTabActivated()

	end

	if terminal.refreshActiveTabContent then

		terminal:refreshActiveTabContent()

	end

	GlobalStorageSiK.TerminalScroll.stripTerminalTree(terminal)

	if terminal.tabRail and terminal.accessMode ~= "blocked" then

		terminal.tabRail:bringToTop()

		terminal.tabRail:syncSelection()

	end

	GlobalStorageSiK.TerminalTabs.syncBlockedFrame(terminal)

	-- DIAGNÓSTICO doble-interfaz (temporal v0.10.18.83)
	if GlobalStorageSiK.TerminalUI and GlobalStorageSiK.TerminalUI.debugDumpTree then
		GlobalStorageSiK.TerminalUI.debugDumpTree("activate->" .. tostring(tabKey))
	end

	-- Volcado completo del arbol + solapes en CUALQUIER pestaña activada, no
	-- solo la de bloqueo (sandbox DebugCatSiKUI, dev36, antes DebugModeUI) - a peticion expresa: poder
	-- evaluar cualquier ventana/pestaña del mod, y como se puede desactivar,
	-- no representa ruido cuando no se necesita.
	if GlobalStorageSiK.UIDebug and GlobalStorageSiK.UIDebug.enabled and GlobalStorageSiK.UIDebug.enabled() then
		GlobalStorageSiK.UIDebug.dumpTree(terminal, "activate->" .. tostring(tabKey))
		GlobalStorageSiK.UIDebug.checkOverlaps(terminal, "activate->" .. tostring(tabKey))
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

	terminal.accessMode = mode or "full"

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

		-- BUG REAL cerrado (2026-08-26, reportado con capturas: "la ventana
		-- se pinta pequeña y hay texto que sobresale... creo que hereda
		-- tamaños de la de bloqueo"): la ventana es un singleton compartido
		-- entre modo bloqueo y modo completo (GS_TerminalUI_Blocked.lua/
		-- GS_TerminalUI_Api.lua reutilizan la MISMA instancia) - el modo
		-- bloqueo la crea mas pequeña a proposito (820-960px de ancho) que el
		-- modo completo (900-1200px). Si la instancia se creo primero en modo
		-- bloqueo (jugador sin terminal/red cerca) y luego pasa a modo
		-- completo (ya con acceso real), esta funcion nunca habia
		-- redimensionado la ventana - se quedaba con el tamaño pequeño del
		-- bloqueo para siempre, con la interfaz completa (mas columnas,
		-- riel de pestañas, cabeceras) intentando caber ahi y desbordando
		-- texto - justo la norma de diseño prohibida de "texto que sobresale".
		-- Se fuerza aqui el minimo ya usado por el redimensionado manual
		-- (installMouseHandlers: minimumWidth/minimumHeight=900/720) antes de
		-- activar ninguna pestaña, recentrada en pantalla igual que hace la
		-- apertura inicial en modo completo (GS_TerminalUI_Api.lua).
		if terminal.width < terminal.minimumWidth or terminal.height < terminal.minimumHeight then
			local sw = getCore():getScreenWidth()
			local sh = getCore():getScreenHeight()
			local w = math.max(terminal.minimumWidth, math.min(1200, math.floor(sw * 0.85)))
			local h = math.max(terminal.minimumHeight, math.min(1000, math.floor(sh * 0.90)))
			terminal:setWidth(w)
			terminal:setHeight(h)
			terminal:setX(math.floor((sw - w) / 2))
			terminal:setY(math.floor((sh - h) / 2))
		end

		local tab = terminal.activeTabKey or "items"

		if tab == "blocked" or not terminal.tabViews or not terminal.tabViews[tab] then

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

