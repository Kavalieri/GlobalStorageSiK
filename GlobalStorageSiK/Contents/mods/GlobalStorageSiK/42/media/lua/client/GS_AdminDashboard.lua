--[[
	GlobalStorageSiK - Panel de soporte GM/moderación (staff del servidor)
	Autor: SiK
	Fecha: 2026-08-22
	Descripción: Ventana independiente (NO requiere estar cerca de ningún
	terminal) que lista TODAS las redes del servidor y permite gestionar su
	identidad técnica - miembros, roles, propietario, historial de auditoría -
	para desatascar casos rotos (propietario fantasma, redes huérfanas de
	pruebas, etc.). NUNCA da acceso al almacén/inventario de la red, solo a
	su gestión de permisos.

	Toda acción se revalida en servidor vía GlobalStorageSiK.Permissions.
	isServerStaff() (GS_Server.lua: requireServerMod) - esta ventana solo
	decide qué MOSTRAR, nunca qué se PERMITE; un cliente modificado que
	llamara a estos comandos sin ser staff sería rechazado igual.

	Reglas de permisos DE RED que este panel expone/gestiona (independientes
	del rango de staff del servidor, ya vigentes en GS_Server.lua antes de
	este panel, confirmadas sin cambios necesarios 2026-08-22): un único
	propietario; el propietario gestiona quién es admin; los admins gestionan
	miembros (añadir/quitar) pero nunca a otro admin ni al propietario; los
	miembros no gestionan nada, solo acceden. El panel de soporte es la única
	vía que se salta esto, y solo para staff, de forma explícita y auditada.
]]

require "ISUI/ISPanel"
require "ISUI/ISLabel"
require "ISUI/ISComboBox"
require "GS_I18n"
require "GS_NetClient"
require "GS_Permissions"
require "GS_SiK_UI_Core"
require "GS_SiK_UI_Table"
require "GS_SiK_UI_Window"
require "GS_TerminalUI_Scroll"
require "GS_TerminalUI_Extensions"
require "GS_AdminDashboard_Audit"
require "GS_AdminDashboard_Corpus"

GlobalStorageSiK.AdminDashboard = GlobalStorageSiK.AdminDashboard or {}
GlobalStorageSiK.AdminDashboard.instance = nil

local T = GlobalStorageSiK.I18n.text
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local FONT_HGT_MEDIUM = getTextManager():getFontHeight(UIFont.Medium)
local PAD = 14
local LINE_GAP = 4
local BTN_H = FONT_HGT_SMALL + 8
local TABLE_METRICS = GlobalStorageSiK.SiK_UI.Table.metrics({ rowVerticalPadding = 14 })
local ROW_H = math.max(TABLE_METRICS.rowHeight, BTN_H + 4)
local ROW_GAP = 4
local ENTRY_H = FONT_HGT_SMALL + 8
local WINDOW_W = 860
local WINDOW_H = 780
local INFO_LINE_COUNT = 6
local MIN_VISIBLE_ROWS = 5
-- Columna "Conexion" de la lista de miembros - "Conectado" en verde para
-- quien sigue en linea, "Desconectado hace X" para el resto. Medida con el
-- peor caso ("99d") igual criterio que el resto de columnas del mod.
local COL_SEEN_W = math.max(
	getTextManager():MeasureStringX(UIFont.Small, GlobalStorageSiK.I18n.text("IGUI_GS_AdminOnline")),
	getTextManager():MeasureStringX(UIFont.Small, GlobalStorageSiK.I18n.text("IGUI_GS_AdminOffline", "99d"))
) + 14
local ADMIN_MEMBER_TABLE_COLUMNS = {
	{ key = "member", titleKey = "IGUI_GS_PermColMemberName", flex = 1, minWidth = 100, pad = 6 },
	{ key = "connection", titleKey = "IGUI_GS_PermColConnection", width = COL_SEEN_W, pad = 0 },
	{ key = "actions", titleKey = "IGUI_GS_ColZoneActions", align = "right", width = 96, pad = 0 },
}
local ADMIN_MEMBER_TABLE_OPTIONS = { left = 0, right = 0, gap = 6 }

local function staffActionCallback(action, dashboard)
	return function()
		action.invoke(dashboard)
	end
end

---@param kind string
---@return string
local function roleLabel(kind)
	if kind == "owner" then return T("IGUI_GS_PermRoleOwner") end
	if kind == "admin" then return T("IGUI_GS_PermRoleAdmin") end
	if kind == GlobalStorageSiK.Permissions.ROLE_DEAD then return T("IGUI_GS_PermRoleDead") end
	return T("IGUI_GS_PermRoleMember")
end

--- Etiqueta de un miembro: nombre del personaje SIN traducir (evita
--- problemas ya vistos con idiomas como el chino si se intentara adaptar el
--- texto) seguido de la cuenta del servidor entre parentesis - pedido
--- explicito 2026-08-22, para poder distinguir a simple vista dos personajes
--- de la MISMA cuenta (p.ej. Kava/Kalva, mismo "admin").
---@param m table
---@return string
local function memberLabel(m)
	-- Prioridad unica compartida con GS_TerminalUI_Permissions.lua - ver
	-- GlobalStorageSiK.Permissions.resolveMemberDisplayName (2026-08-26,
	-- revision tecnica: las 2 interfaces tenian antes un orden de campos
	-- distinto, podian mostrar un nombre diferente para el mismo miembro).
	local resolved = GlobalStorageSiK.Permissions.resolveMemberDisplayName(m)
	local name = resolved ~= "" and resolved or "?"
	local account = (m.username and m.username ~= "") and m.username or "?"
	return name .. " (" .. account .. ")"
end

-- relativeAge() vive en GlobalStorageSiK.SiK_UI (GS_SiK_UI_Core.lua)
-- - compartida con GS_TerminalUI_Permissions.lua, no duplicar aqui.
local relativeAge = GlobalStorageSiK.SiK_UI.relativeAge

--- Columna "Conexion" de un miembro: 3 estados posibles, nunca solo 2 -
--- "Desconectado" no tiene sentido para alguien fallecido (pedido explicito
--- 2026-08-22: "no tiene sentido que diga desconectado, está muerto, pero sí
--- cuándo se detectó su muerte"). Puramente informativo, igual que el resto
--- de esta columna - nunca se usa para inferir ni marcar nada.
---@param m table
---@return string text, number r, number g, number b
local function connectionLabel(m)
	local pal = GlobalStorageSiK.SiK_UI.PALETTE
	if m.online then
		return T("IGUI_GS_AdminOnline"), pal.statusOk[1], pal.statusOk[2], pal.statusOk[3]
	end
	if m.role == GlobalStorageSiK.Permissions.ROLE_DEAD then
		return T("IGUI_GS_AdminDeathDetected", relativeAge(m.diedAt)), pal.statusWarn[1], pal.statusWarn[2], pal.statusWarn[3]
	end
	return T("IGUI_GS_AdminOffline", relativeAge(m.lastSeenAt)), 0.6, 0.63, 0.66
end

-- ============================================================================
-- Modal pequeño: historial de auditoria de UNA red (solo lectura).
-- ============================================================================
GS_AdminHistoryUI = ISPanel:derive("GS_AdminHistoryUI")

local HISTORY_RESIZE_GRAB = 14
local HISTORY_MIN_W = 420
local HISTORY_MIN_H = 320
-- Cuantas entradas recientes copia "Copiar reciente" al portapapeles (pedido
-- explicito: "un margen razonable para cubrir el rango de tiempo que nos
-- interesa" - los eventos ya vienen mas-reciente-primero desde el servidor,
-- HISTORY_MAX_ENTRIES en GS_Permissions.lua acota a 40 por red como maximo
-- real, asi que 100 ya cubre TODO el historial disponible de cualquier red).
local HISTORY_COPY_COUNT = 100

--- Redimensionado en esquina inferior derecha, arrastre por cabecera - mismo
--- patron ya usado en GS_TerminalUI.lua/NodeEditor/ZoneEditor (2026-08-26,
--- primera vez que se aplica a una ventana del panel de soporte, pedido
--- explicito: "la ventana de staff/historial debe ser tambien
--- redimensionable").
function GS_AdminHistoryUI:installMouseHandlers()
	self.onMouseDown = function(me, x, y)
		if x >= me.width - HISTORY_RESIZE_GRAB and y >= me.height - HISTORY_RESIZE_GRAB then
			me.resizing = true
			me:setCapture(true)
			return true
		end
		if y >= 0 and y < me.headerHeight and x < me.width - 36 then
			me.moving = true
			me:setCapture(true)
			return true
		end
		return ISPanel.onMouseDown(me, x, y)
	end
	self.onMouseUp = function(me, x, y)
		if me.resizing or me.moving then
			me.resizing = false
			me.moving = false
			me:setCapture(false)
			me:refreshEvents()
			return true
		end
		return ISPanel.onMouseUp(me, x, y)
	end
	self.onMouseUpOutside = self.onMouseUp
	self.onMouseMove = function(me, dx, dy)
		if me.resizing then
			me:setWidth(math.max(me.minimumWidth, me.width + dx))
			me:setHeight(math.max(me.minimumHeight, me.height + dy))
			GlobalStorageSiK.TerminalScroll.resize(me.eventScroll,
				me.width - PAD * 2, me.height - me.scrollTopY - PAD)
			return true
		end
		if me.moving then
			me:setX(me.x + dx)
			me:setY(me.y + dy)
			return true
		end
		return ISPanel.onMouseMove(me, dx, dy)
	end
	self.onMouseMoveOutside = self.onMouseMove
end

function GS_AdminHistoryUI:initialise()
	ISPanel.initialise(self)
	self.backgroundColor = { r = 0.06, g = 0.06, b = 0.06, a = 0.98 }
	self.borderColor = { r = 0.55, g = 0.3, b = 0.2, a = 0.95 }
	self:setAlwaysOnTop(true)
	self.headerHeight = FONT_HGT_MEDIUM + PAD + LINE_GAP
	self.minimumWidth = HISTORY_MIN_W
	self.minimumHeight = HISTORY_MIN_H
	self.resizable = true
	self.resizing = false
	self.moving = false
	GlobalStorageSiK.SiK_UI.setupModalPanel(self, function()
		self:destroy()
	end, PAD)
	local title = ISLabel:new(PAD, PAD, FONT_HGT_MEDIUM, T("IGUI_GS_AdminHistoryTitle"),
		0.95, 0.75, 0.6, 1, UIFont.Medium, true)
	title:initialise()
	self:addChild(title)
	local scrollY = self.headerHeight + 4
	-- Identificar la red en la propia cabecera (pedido explicito 2026-08-22:
	-- "por si nos hacen capturas, poder ver a que red pertenece ese
	-- historial") - mismo label que el combo de red, envuelto (regla del
	-- proyecto: texto de longitud variable siempre con wrap real).
	if self.networkLabel and self.networkLabel ~= "" then
		local labelW = self.width - PAD * 2
		for _, line in ipairs(GlobalStorageSiK.SiK_UI.wrapTextLines(self.networkLabel, labelW, UIFont.Small)) do
			local netLbl = ISLabel:new(PAD, scrollY, FONT_HGT_SMALL, line, 0.65, 0.68, 0.72, 1, UIFont.Small, true)
			netLbl:initialise()
			self:addChild(netLbl)
			scrollY = scrollY + FONT_HGT_SMALL + 2
		end
		scrollY = scrollY + 4
	end
	-- Fila de acciones (2026-08-26, pedido explicito): copiar el historial
	-- reciente al portapapeles y borrarlo si se quiere empezar de cero -
	-- ninguna de las dos toca redes/permisos, solo el registro de auditoria.
	local actionBtnW = math.floor((self.width - PAD * 2 - 8) / 2)
	self.copyBtn = GlobalStorageSiK.SiK_UI.createButton(
		PAD, scrollY, actionBtnW, BTN_H, T("IGUI_GS_AdminHistoryCopy"), self, function()
			self:onCopyRecent()
		end)
	self:addChild(self.copyBtn)
	self.clearBtn = GlobalStorageSiK.SiK_UI.createButton(
		PAD + actionBtnW + 8, scrollY, actionBtnW, BTN_H, T("IGUI_GS_AdminHistoryClear"), self, function()
			self:onClearHistory()
		end)
	GlobalStorageSiK.SiK_UI.applyDangerButton(self.clearBtn)
	self:addChild(self.clearBtn)
	scrollY = scrollY + BTN_H + LINE_GAP
	self.scrollTopY = scrollY
	self.eventScroll = GlobalStorageSiK.TerminalScroll.create(
		self, PAD, scrollY, self.width - PAD * 2, self.height - scrollY - PAD)
	self:refreshEvents()
	self:installMouseHandlers()
	GlobalStorageSiK.SiK_UI.centerModal(self)
end

--- Copia al portapapeles las HISTORY_COPY_COUNT entradas mas recientes (ya
--- vienen mas-reciente-primero) en texto plano, una linea por evento -
--- pedido explicito 2026-08-26 para poder pegar el rango de tiempo que
--- interesa en un reporte/chat sin tener que hacer capturas de pantalla.
function GS_AdminHistoryUI:onCopyRecent()
	local events = self.events or {}
	local lines = {}
	local count = math.min(#events, HISTORY_COPY_COUNT)
	for i = 1, count do
		local ev = events[i]
		lines[#lines + 1] = os.date("%Y-%m-%d %H:%M:%S", math.floor((ev.ts or 0) / 1000))
			.. " - " .. tostring(ev.type) .. ": " .. tostring(ev.detail or "")
	end
	Clipboard.setClipboard(table.concat(lines, "\n"))
	local player = GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer and GlobalStorageSiK.NetClient.getPlayer()
	if player and player.setHaloNote then
		player:setHaloNote(T("IGUI_GS_AdminHistoryCopied", count), 180, 220, 160, 350)
	end
end

--- Vacia el historial de auditoria de la red actual (nunca toca miembros,
--- roles ni ownership) - pedido explicito 2026-08-26, "por si el usuario
--- quiere iniciar un historial nuevo, efectivo". Revalidado en servidor
--- (isServerStaff), igual que el resto de acciones de este panel.
function GS_AdminHistoryUI:onClearHistory()
	if not self.networkId or not GlobalStorageSiK.NetClient or not GlobalStorageSiK.NetClient.sendCommand then
		return
	end
	GlobalStorageSiK.NetClient.sendCommand("adminClearNetworkHistory", { networkId = self.networkId })
	self.events = {}
	self:refreshEvents()
end

function GS_AdminHistoryUI:destroy()
	GlobalStorageSiK.AdminDashboard.historyInstance = nil
	self:setVisible(false)
	if self.removeFromUIManager then self:removeFromUIManager() end
end

function GS_AdminHistoryUI:onKeyRelease(key)
	if key == Keyboard.KEY_ESCAPE then self:destroy(); return true end
	return ISPanel.onKeyRelease(self, key)
end

---@param events table[]
function GS_AdminHistoryUI:refreshEvents()
	local scroll = self.eventScroll
	GlobalStorageSiK.TerminalScroll.clear(scroll)
	local w = GlobalStorageSiK.TerminalScroll.contentWidth(scroll)
	local y = 4
	local events = self.events or {}
	if #events == 0 then
		local lbl = ISLabel:new(6, y, FONT_HGT_SMALL, T("IGUI_GS_AdminHistoryEmpty"), 0.6, 0.63, 0.66, 1, UIFont.Small, true)
		lbl:initialise()
		GlobalStorageSiK.TerminalScroll.addChild(scroll, lbl)
		y = y + FONT_HGT_SMALL + LINE_GAP
	else
		-- Mas reciente primero.
		for i = #events, 1, -1 do
			local ev = events[i]
			local header = relativeAge(ev.ts) .. " - " .. tostring(ev.type)
			local hLbl = ISLabel:new(6, y, FONT_HGT_SMALL, header, 0.85, 0.75, 0.6, 1, UIFont.Small, true)
			hLbl:initialise()
			GlobalStorageSiK.TerminalScroll.addChild(scroll, hLbl)
			y = y + FONT_HGT_SMALL + 2
			local lines = GlobalStorageSiK.SiK_UI.wrapTextLines(ev.detail or "", w - 12, UIFont.Small)
			for j = 1, #lines do
				local lbl = ISLabel:new(12, y, FONT_HGT_SMALL, lines[j], 0.78, 0.8, 0.84, 1, UIFont.Small, true)
				lbl:initialise()
				GlobalStorageSiK.TerminalScroll.addChild(scroll, lbl)
				y = y + FONT_HGT_SMALL + 2
			end
			y = y + ROW_GAP
		end
	end
	GlobalStorageSiK.TerminalScroll.setContentHeight(scroll, y)
	GlobalStorageSiK.TerminalScroll.ensureScrollBars(scroll)
end

---@param events table[]
---@param networkLabel string|nil
---@param networkId string|nil
function GlobalStorageSiK.AdminDashboard.showHistory(events, networkLabel, networkId)
	if GlobalStorageSiK.AdminDashboard.historyInstance then
		GlobalStorageSiK.AdminDashboard.historyInstance:destroy()
	end
	local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
	-- Tamano por defecto ampliado (2026-08-26, pedido explicito: "debe ser
	-- mas grande") - sigue redimensionable a mano por si hace falta mas.
	local w, h = math.min(720, sw - 60), math.min(760, sh - 60)
	local ui = GS_AdminHistoryUI:new((sw - w) / 2, (sh - h) / 2, w, h)
	ui.events = events or {}
	ui.networkLabel = networkLabel or ""
	ui.networkId = networkId
	ui:initialise()
	ui:addToUIManager()
	GlobalStorageSiK.AdminDashboard.historyInstance = ui
end

-- ============================================================================
-- Modal pequeño: ajuste fino de UN miembro (rol / propietario / quitar).
-- Mismo patron visual que GS_TerminalUI_MemberEditor.lua, pero las acciones
-- van contra los comandos admin* (staff), no los del propietario normal.
-- ============================================================================
GS_AdminMemberEditorUI = ISPanel:derive("GS_AdminMemberEditorUI")

function GS_AdminMemberEditorUI:initialise()
	ISPanel.initialise(self)
	self.backgroundColor = { r = 0.06, g = 0.06, b = 0.06, a = 0.98 }
	self.borderColor = { r = 0.55, g = 0.3, b = 0.2, a = 0.95 }
	self:setAlwaysOnTop(true)
	self.headerHeight = FONT_HGT_MEDIUM + PAD + LINE_GAP
	GlobalStorageSiK.SiK_UI.setupModalPanel(self, function()
		self:destroy()
	end, PAD)
	self:buildLayout()
end

function GS_AdminMemberEditorUI:destroy()
	GlobalStorageSiK.AdminDashboard.memberEditorInstance = nil
	self:setVisible(false)
	if self.removeFromUIManager then self:removeFromUIManager() end
end

function GS_AdminMemberEditorUI:onKeyRelease(key)
	if key == Keyboard.KEY_ESCAPE then self:destroy(); return true end
	return ISPanel.onKeyRelease(self, key)
end

function GS_AdminMemberEditorUI:buildLayout()
	local pad = PAD
	local y = pad
	local textW = self.width - pad * 2
	local m = self.member

	local title = GlobalStorageSiK.SiK_UI.createWindowTitleLabel(pad, y, T("IGUI_GS_AdminMemberEditorTitle"))
	self:addChild(title)
	y = y + FONT_HGT_MEDIUM + LINE_GAP

	-- El rol es la unica fuente de verdad, incluido "muerto" (ROLE_DEAD, ver
	-- GS_Permissions.lua) - ya no hace falta un sufijo aparte basado en
	-- diedAt, roleLabel(m.role) ya dice "Muerto"/"Dead" por si solo.
	local isDead = (m.role == GlobalStorageSiK.Permissions.ROLE_DEAD)
	local nameText = "[" .. roleLabel(m.role) .. "] " .. memberLabel(m)
	for _, line in ipairs(GlobalStorageSiK.SiK_UI.wrapTextLines(nameText, textW, UIFont.Small)) do
		local lbl = ISLabel:new(pad, y, FONT_HGT_SMALL, line, 0.78, 0.82, 0.88, 1, UIFont.Small, true)
		lbl:initialise()
		self:addChild(lbl)
		y = y + FONT_HGT_SMALL + 2
	end
	-- Conexion: a nivel informativo unicamente (pedido explicito 2026-08-22),
	-- nunca se usa para inferir ni marcar nada automaticamente - solo ayuda a
	-- staff a diagnosticar un caso "colgado" (diedAt nunca llegado a marcar
	-- por un crash, desconexion sucia, etc.).
	local seenText, sr, sg, sb = connectionLabel(m)
	local seenLbl = ISLabel:new(pad, y, FONT_HGT_SMALL, seenText, sr, sg, sb, 1, UIFont.Small, true)
	seenLbl:initialise()
	self:addChild(seenLbl)
	y = y + FONT_HGT_SMALL + LINE_GAP + 4

	local dashboard = self.dashboard
	local btnW = textW
	local isOwnerRow = (m.role == "owner")

	if isDead then
		-- Un miembro fallecido no admite ninguna accion desde aqui (nada de
		-- marcado manual, ver rechazo explicito 2026-08-22) - de solo lectura,
		-- se conserva unicamente como registro consultable/auditable.
		local hint = ISLabel:new(pad, y, FONT_HGT_SMALL, T("IGUI_GS_AdminMemberEditorDeadHint"),
			0.6, 0.63, 0.66, 1, UIFont.Small, true)
		hint:initialise()
		self:addChild(hint)
		y = y + FONT_HGT_SMALL + ROW_GAP
	elseif not isOwnerRow then
		local toggleTo = (m.role == "admin") and "member" or "admin"
		local roleBtn = GlobalStorageSiK.SiK_UI.createButton(
			pad, y, btnW, BTN_H, T(toggleTo == "admin" and "IGUI_GS_AdminMakeAdmin" or "IGUI_GS_AdminMakeMember"),
			self, function()
				dashboard:onSetMemberRole(m.id, toggleTo)
				self:destroy()
			end)
		self:addChild(roleBtn)
		y = y + BTN_H + ROW_GAP

		local ownerBtn = GlobalStorageSiK.SiK_UI.createButton(
			pad, y, btnW, BTN_H, T("IGUI_GS_AdminSetOwner"), self, function()
				dashboard:onSetOwner(m.id)
				self:destroy()
			end)
		self:addChild(ownerBtn)
		y = y + BTN_H + ROW_GAP

		local removeBtn = GlobalStorageSiK.SiK_UI.createButton(
			pad, y, btnW, BTN_H, T("IGUI_GS_AdminRemoveMember"), self, function()
				dashboard:onRemoveMember(m.id)
				self:destroy()
			end)
		GlobalStorageSiK.SiK_UI.applyDangerButton(removeBtn)
		self:addChild(removeBtn)
		y = y + BTN_H + ROW_GAP
	else
		local hint = ISLabel:new(pad, y, FONT_HGT_SMALL, T("IGUI_GS_AdminMemberEditorOwnerHint"),
			0.6, 0.63, 0.66, 1, UIFont.Small, true)
		hint:initialise()
		self:addChild(hint)
		y = y + FONT_HGT_SMALL + ROW_GAP
	end

	local closeBtn = GlobalStorageSiK.SiK_UI.createButton(
		pad, y, btnW, BTN_H, T("IGUI_GS_Close"), self, function()
			self:destroy()
		end)
	self:addChild(closeBtn)
	y = y + BTN_H + pad

	self:setHeight(y)
	GlobalStorageSiK.SiK_UI.centerModal(self)
end

---@param dashboard table
---@param member table
function GlobalStorageSiK.AdminDashboard.openMemberEditor(dashboard, member)
	if GlobalStorageSiK.AdminDashboard.memberEditorInstance then
		GlobalStorageSiK.AdminDashboard.memberEditorInstance:destroy()
	end
	local w = GlobalStorageSiK.SiK_UI.STANDARD_MODAL_W
	local ui = GS_AdminMemberEditorUI:new(0, 0, w, 100)
	ui.dashboard = dashboard
	ui.member = member
	ui:initialise()
	ui:addToUIManager()
	GlobalStorageSiK.AdminDashboard.memberEditorInstance = ui
end

-- ============================================================================
-- Ventana principal.
-- ============================================================================
GS_AdminDashboardUI = ISPanel:derive("GS_AdminDashboardUI")

local ADMIN_RESIZE_GRAB = 14
local ADMIN_MIN_W = 520
local ADMIN_MIN_H = 480

--- Redimensionado en esquina + arrastre por cabecera, mismo patron ya
--- probado en GS_TerminalUI.lua/NodeEditor/ZoneEditor (2026-08-26, pedido
--- explicito: "el panel de staff debe ser tambien redimensionable"). Este
--- panel construye TODO su contenido de una vez en buildStaticFrame() con
--- anchos derivados de self.width en el momento de construir - en vez de
--- reflow parcial (arriesgado con tantos widgets encadenados por posicion Y
--- acumulada), se reconstruye entero (rebuildAfterResize, reutiliza los
--- datos ya cacheados _networks/_members, sin llamada a servidor ni
--- parpadeo de "vacio").
--- BUG REAL DE UX cerrado (2026-08-26, "no escala en tiempo real y se
--- actualiza luego. Arreglar para no dificultar procedimientos"): antes solo
--- se reconstruia al SOLTAR el arrastre - la ventana se quedaba con el
--- tamano viejo mientras se arrastraba, dando la sensacion de que el
--- redimensionado no respondia. rebuildAfterResize() ya era seguro de llamar
--- repetidamente (nunca golpea el servidor), asi que ahora tambien se llama
--- DURANTE el arrastre, con un debounce de ADMIN_REFLOW_DEBOUNCE_MS para no
--- reconstruir en cada pixel de movimiento del raton (decenas de veces por
--- segundo) - el reflow se ve fluido sin recalcular el layout mas de lo
--- necesario. El mouseUp final SIEMPRE reconstruye sin condicion, para que
--- el ultimo delta (que pudo caer dentro de la ventana de debounce) nunca se
--- pierda.
local ADMIN_REFLOW_DEBOUNCE_MS = 100
function GS_AdminDashboardUI:installMouseHandlers()
	self.onMouseDown = function(me, x, y)
		if x >= me.width - ADMIN_RESIZE_GRAB and y >= me.height - ADMIN_RESIZE_GRAB then
			me.resizing = true
			me._lastReflowMs = nil
			me:setCapture(true)
			return true
		end
		if y >= 0 and y < me.headerHeight and x < me.width - 36 then
			me.moving = true
			me:setCapture(true)
			return true
		end
		return ISPanel.onMouseDown(me, x, y)
	end
	self.onMouseUp = function(me, x, y)
		if me.resizing then
			me.resizing = false
			me:setCapture(false)
			me:rebuildAfterResize()
			return true
		end
		if me.moving then
			me.moving = false
			me:setCapture(false)
			return true
		end
		return ISPanel.onMouseUp(me, x, y)
	end
	self.onMouseUpOutside = self.onMouseUp
	self.onMouseMove = function(me, dx, dy)
		if me.resizing then
			me:setWidth(math.max(me.minimumWidth, me.width + dx))
			me:setHeight(math.max(me.minimumHeight, me.height + dy))
			local nowMs = getTimestampMs and getTimestampMs() or 0
			if not me._lastReflowMs or (nowMs - me._lastReflowMs) >= ADMIN_REFLOW_DEBOUNCE_MS then
				me._lastReflowMs = nowMs
				me:rebuildAfterResize()
			end
			return true
		end
		if me.moving then
			me:setX(me.x + dx)
			me:setY(me.y + dy)
			return true
		end
		return ISPanel.onMouseMove(me, dx, dy)
	end
	self.onMouseMoveOutside = self.onMouseMove
end

--- Reconstruye el marco entero al tamano nuevo (ver comentario de
--- installMouseHandlers) conservando posicion en pantalla - buildStaticFrame
--- llama a centerModal al final (pensado para la construccion inicial), asi
--- que aqui se restaura la posicion previa despues para no "saltar" al
--- centro cada vez que se suelta el asa de redimensionado.
function GS_AdminDashboardUI:rebuildAfterResize()
	local x, y = self:getX(), self:getY()
	self:clearChildren()
	self:buildStaticFrame()
	-- BUG REAL cerrado (2026-08-26, reportado en pruebas reales: "no tenemos
	-- como cerrar la ventana, el boton desaparece al reescalar"): el boton de
	-- cerrar lo crea/posiciona setupModalPanel() UNA vez en initialise() como
	-- hijo directo del panel, FUERA de buildStaticFrame() - clearChildren()
	-- lo borraba junto con todo lo demas y nunca se recreaba. No se puede
	-- volver a llamar setupModalPanel() entero aqui (tambien reinstalaria
	-- setupHeaderDrag(), que chocaria con los manejadores de arrastre/resize
	-- propios de installMouseHandlers) - se recrea solo el boton
	-- (createCloseButton) y se reposiciona con layoutModalFrame(), las 2
	-- unicas funciones responsables de el.
	GlobalStorageSiK.SiK_UI.createCloseButton(self, self, function() self:destroy() end)
	GlobalStorageSiK.SiK_UI.layoutModalFrame(self, self.padding)
	self:setX(x)
	self:setY(y)
	if self._networks then
		self:refreshNetworkList(self._networks)
	end
	if self._selectedNetworkId then
		self:refreshInfoLines()
	end
	if self._members then
		self:refreshMemberPanel(self._members)
	end
end

--- Recalcula en un unico punto los limites de las dos suites de Taxonomia.
--- Es idempotente y se ejecuta siempre despues de que ambas secciones hayan
--- sido pobladas, tanto en apertura como en cada reconstruccion por resize.
function GS_AdminDashboardUI:layoutTaxonomyTab()
	if not self._taxonomyTabY then return end
	local bottomY = self.height - PAD
	local midY = self._taxonomyTabY + math.floor((bottomY - self._taxonomyTabY) / 2)
	self._auditBottomLimit = midY - 4
	self._corpusBottomLimit = bottomY
	GlobalStorageSiK.AdminDashboardAudit.refreshSummary(self)
	GlobalStorageSiK.AdminDashboardCorpus.refreshSummary(self)
end

function GS_AdminDashboardUI:initialise()
	ISPanel.initialise(self)
	self.backgroundColor = { r = 0.05, g = 0.05, b = 0.05, a = 0.98 }
	self.borderColor = { r = 0.55, g = 0.3, b = 0.2, a = 0.95 }
	self:setAlwaysOnTop(true)
	self.headerHeight = FONT_HGT_MEDIUM + PAD + LINE_GAP
	self.minimumWidth = ADMIN_MIN_W
	self.minimumHeight = ADMIN_MIN_H
	self.resizable = true
	self.resizing = false
	self.moving = false
	GlobalStorageSiK.SiK_UI.setupModalPanel(self, function()
		self:destroy()
	end, PAD)
	self:buildStaticFrame()
	self:installMouseHandlers()
	self:requestNetworkList()
	self:requestOnlinePlayers()
end

--- Mantiene vivo el texto relativo de las dos suites mientras la ventana
--- permanece abierta. Solo reconstruye el bloque cuyo texto cambia y como
--- maximo una vez por segundo; no envia ninguna peticion de red.
function GS_AdminDashboardUI:prerender()
	ISPanel.prerender(self)
	local nowMs = getTimestampMs and tonumber(getTimestampMs()) or 0
	if nowMs <= 0 then return end
	if self._lastTaxonomyAgeRefreshMs and (nowMs - self._lastTaxonomyAgeRefreshMs) < 1000 then return end
	self._lastTaxonomyAgeRefreshMs = nowMs

	if self._nativeAuditLastReport then
		local auditText = GlobalStorageSiK.SiK_UI.relativeAge(self._nativeAuditFinishedAtMs)
		if auditText ~= self._nativeAuditFinishedAtText then
			self._nativeAuditFinishedAtText = auditText
			GlobalStorageSiK.AdminDashboardAudit.refreshSummary(self)
		end
	end
	if self._nativeCorpusLastReport then
		local corpusText = GlobalStorageSiK.SiK_UI.relativeAge(self._nativeCorpusFinishedAtMs)
		if corpusText ~= self._nativeCorpusFinishedAtText then
			self._nativeCorpusFinishedAtText = corpusText
			GlobalStorageSiK.AdminDashboardCorpus.refreshSummary(self)
		end
	end
end

function GS_AdminDashboardUI:destroy()
	GlobalStorageSiK.AdminDashboard.instance = nil
	self:setVisible(false)
	if self.removeFromUIManager then
		self:removeFromUIManager()
	end
end

function GS_AdminDashboardUI:onKeyRelease(key)
	if key == Keyboard.KEY_ESCAPE then
		self:destroy()
		return true
	end
	return ISPanel.onKeyRelease(self, key)
end

function GS_AdminDashboardUI:requestNetworkList()
	if GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.sendCommand then
		GlobalStorageSiK.NetClient.sendCommand("adminListNetworks", {})
	end
end

function GS_AdminDashboardUI:requestMembers(networkId)
	if GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.sendCommand then
		GlobalStorageSiK.NetClient.sendCommand("adminGetNetworkMembers", { networkId = networkId })
	end
end

function GS_AdminDashboardUI:requestHistory()
	if not self._selectedNetworkId then return end
	if GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.sendCommand then
		GlobalStorageSiK.NetClient.sendCommand("adminGetNetworkHistory", { networkId = self._selectedNetworkId })
	end
end

--- Pedido explicito 2026-08-22: añadir miembros desde el panel de staff,
--- igual que el desplegable de la pestaña normal de admin pero SIN tener en
--- cuenta facción - solo gente conectada ahora mismo (el staff gestiona
--- cualquier red, no solo la suya, la facción del jugador no pinta nada aqui).
function GS_AdminDashboardUI:requestOnlinePlayers()
	if GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.sendCommand then
		GlobalStorageSiK.NetClient.sendCommand("adminListOnlinePlayers", {})
	end
end

function GS_AdminDashboardUI:onAddMember()
	if not self._selectedNetworkId or not self.addMemberCombo then return end
	local idx = self.addMemberCombo.selected or 1
	local entry = self._addMemberOptions and self._addMemberOptions[idx]
	if not entry or not entry.characterId then return end
	if GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.sendCommand then
		GlobalStorageSiK.NetClient.sendCommand("adminAddMember",
			{ networkId = self._selectedNetworkId, characterId = entry.characterId })
	end
end

---@param players table[]
function GS_AdminDashboardUI:refreshOnlinePlayersCombo()
	if not self.addMemberCombo then return end
	local prevSelected = self._addMemberOptions and self.addMemberCombo.selected
		and self._addMemberOptions[self.addMemberCombo.selected]
	local prevCharacterId = prevSelected and prevSelected.characterId
	self.addMemberCombo:clear()
	self._addMemberOptions = {}
	local currentIds = {}
	for i = 1, #(self._members or {}) do
		local m = self._members[i]
		if m.id and m.id ~= "" then currentIds[m.id] = true end
	end
	local players = self._onlinePlayers or {}
	local newSelected = 1
	for i = 1, #players do
		local p = players[i]
		if p.characterId and not currentIds[p.characterId] then
			self._addMemberOptions[#self._addMemberOptions + 1] = p
			self.addMemberCombo:addOption(memberLabel({ displayName = p.name, username = p.username }))
			if p.characterId == prevCharacterId then newSelected = #self._addMemberOptions end
		end
	end
	if #self._addMemberOptions == 0 then
		self.addMemberCombo:addOption(T("IGUI_GS_AdminNoOnlinePlayers"))
		self._addMemberOptions[1] = nil
	end
	self.addMemberCombo.selected = newSelected
	if self.addMemberBtn then
		local hasOptions = #self._addMemberOptions > 0
		-- _sikUiLocked (auditoria de botones, 2026-08-26): aspecto atenuado
		-- del proyecto en vez de la textura gris generica de setEnable.
		self.addMemberBtn._sikUiLocked = not hasOptions
		self.addMemberBtn:setEnable(hasOptions)
		if not hasOptions and self.addMemberBtn.setTooltip then
			self.addMemberBtn:setTooltip(T("IGUI_GS_AdminNoPlayersOnline"))
		end
	end
end

--- Todo lo fijo de la ventana: combo de red (arriba, como el resto de
--- selectores de red del mod - ver GS_TerminalInstallReaderChoice.lua),
--- bloque de info envuelta (nunca texto truncado a una linea, regla del
--- proyecto para texto de longitud variable), lista de miembros con scroll,
--- y la barra de acciones de red. Se llama UNA vez; lo que cambia con los
--- datos vive dentro de cada refresh*.
--- Registra un widget ya añadido a `self` como propio de la pestaña
--- "Soporte de redes" - dev22 (dashboard reorganizado en pestañas, pedido
--- explicito de sistemas): permite mostrar/ocultar por pestaña sin
--- reconstruir nada, self:selectStaffTab() solo alterna setVisible().
---@param widget ISUIElement
local function trackNetworkTabWidget(self, widget)
	self._networkTabWidgets[#self._networkTabWidgets + 1] = widget
end

--- Cambia la pestaña activa del panel de staff (Soporte de redes / Taxonomia)
--- mostrando/ocultando los paneles ya construidos - NUNCA reconstruye la
--- pestaña que deja de verse (pedido explicito de sistemas: "la pestaña no
--- visible no debe reconstruirse en cada refresh de la visible").
---@param tabKey string "network"|"taxonomy"
function GS_AdminDashboardUI:selectStaffTab(tabKey)
	self._activeStaffTab = tabKey
	local showNetwork = tabKey ~= "taxonomy"
	for i = 1, #(self._networkTabWidgets or {}) do
		local w = self._networkTabWidgets[i]
		if w and w.setVisible then w:setVisible(showNetwork) end
	end
	for i = 1, #(self._taxonomyTabWidgets or {}) do
		local w = self._taxonomyTabWidgets[i]
		if w and w.setVisible then w:setVisible(not showNetwork) end
	end
	if self.staffTabNetworkBtn then
		self.staffTabNetworkBtn._sikUiActive = showNetwork
	end
	if self.staffTabTaxonomyBtn then
		self.staffTabTaxonomyBtn._sikUiActive = not showNetwork
	end
end

function GS_AdminDashboardUI:buildStaticFrame()
	local pad = PAD
	local textW = self.width - pad * 2
	local y = pad
	self._networkTabWidgets = {}
	self._taxonomyTabWidgets = {}

	local title = ISLabel:new(pad, y, FONT_HGT_MEDIUM, T("IGUI_GS_AdminDashboardTitle"),
		0.95, 0.75, 0.6, 1, UIFont.Medium, true)
	title:initialise()
	self:addChild(title)
	y = self.headerHeight + 4

	-- dev22: pestañas del panel de staff (Soporte de redes / Taxonomia) -
	-- controlador pequeño y explicito, 2 botones que alternan visibilidad de
	-- los widgets ya construidos (ver selectStaffTab arriba), nunca
	-- reconstruyen ni destruyen nada.
	local tabW = math.floor((textW - 8) / 2)
	self.staffTabNetworkBtn = GlobalStorageSiK.SiK_UI.createButton(
		pad, y, tabW, BTN_H, T("IGUI_GS_AdminTabNetwork"), self, function()
			self:selectStaffTab("network")
		end)
	self:addChild(self.staffTabNetworkBtn)
	self.staffTabTaxonomyBtn = GlobalStorageSiK.SiK_UI.createButton(
		pad + tabW + 8, y, tabW, BTN_H, T("IGUI_GS_AdminTabTaxonomy"), self, function()
			self:selectStaffTab("taxonomy")
		end)
	self:addChild(self.staffTabTaxonomyBtn)
	y = y + BTN_H + LINE_GAP + 4
	-- Ambas pestañas arrancan en la MISMA Y (justo debajo de la barra de
	-- pestañas) - son una superposicion mostrar/ocultar, no un flujo
	-- secuencial. Guardada aparte porque `y` sigue avanzando mas abajo con
	-- el contenido propio de Soporte de redes.
	local taxonomyTabY = y
	self._taxonomyTabY = taxonomyTabY

	self.networkCombo = ISComboBox:new(pad, y, textW, ENTRY_H, self, nil)
	self.networkCombo:initialise()
	GlobalStorageSiK.SiK_UI.styleComboBox(self.networkCombo)
	self.networkCombo.onChange = function() self:onComboChanged() end
	self:addChild(self.networkCombo)
	trackNetworkTabWidget(self, self.networkCombo)
	y = y + ENTRY_H + LINE_GAP + 2

	self.infoLbls = {}
	for i = 1, INFO_LINE_COUNT do
		local lbl = ISLabel:new(pad, y, FONT_HGT_SMALL, "", 0.78, 0.82, 0.88, 1, UIFont.Small, true)
		lbl:initialise()
		self:addChild(lbl)
		trackNetworkTabWidget(self, lbl)
		self.infoLbls[i] = lbl
		y = y + FONT_HGT_SMALL + 2
	end
	y = y + LINE_GAP + 4

	local reloadW = math.floor(textW / 2) - 4
	self.reloadBtn = GlobalStorageSiK.SiK_UI.createButton(
		pad, y, reloadW, BTN_H, T("IGUI_GS_AdminReload"), self, function()
			self:requestNetworkList()
			if self._selectedNetworkId then self:requestMembers(self._selectedNetworkId) end
		end)
	self:addChild(self.reloadBtn)
	trackNetworkTabWidget(self, self.reloadBtn)

	self.historyBtn = GlobalStorageSiK.SiK_UI.createButton(
		pad + reloadW + 8, y, reloadW, BTN_H, T("IGUI_GS_AdminHistoryButton"), self, function()
			self:requestHistory()
		end)
	self:addChild(self.historyBtn)
	trackNetworkTabWidget(self, self.historyBtn)
	y = y + BTN_H + LINE_GAP

	-- Diagnostico DEV puntual (2026-08-22, ver comentario en GS_Server.lua,
	-- scanContainerForBrokenItems): boton temporal para localizar el item con
	-- fullType roto que provoca el spam de consola - escanea el inventario
	-- de QUIEN pulsa el boton (no de la red), el resultado sale por chat y
	-- por console.txt (Log.error, siempre visible). Quitar cuando ya no haga
	-- falta.
	self.diagBtn = GlobalStorageSiK.SiK_UI.createButton(
		pad, y, textW, BTN_H, T("IGUI_GS_AdminFindBrokenItems"), self, function()
			if GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.sendCommand then
				GlobalStorageSiK.NetClient.sendCommand("gsDiagFindBrokenItems", {})
			end
		end)
	self:addChild(self.diagBtn)
	trackNetworkTabWidget(self, self.diagBtn)
	y = y + BTN_H + LINE_GAP + 6

	-- dev22 (pedido explicito de sistemas: "Auditar catalogo, trasladado
	-- desde Soporte de redes... su unico hogar sera Taxonomia, no duplicar
	-- el boton en ambas pestañas"): construccion completa de la pestaña
	-- Taxonomia extraida a GS_AdminDashboard_Audit.lua (mismo motivo que la
	-- extraccion de runNativeAudit a GS_NativeAuditServer.lua en dev14 - no
	-- seguir haciendo crecer este fichero/buildStaticFrame).
	-- dev24: la pestaña Taxonomia ahora reparte su alto disponible entre 2
	-- suites INDEPENDIENTES (Auditar catalogo / Validar corpus, pedido
	-- explicito de sistemas: "cada suite conserva estado, requestId, ultima
	-- ejecucion y resumen propios") - mitad superior para auditoria, mitad
	-- inferior para el corpus, cada una con su propio scroll.
	local taxonomyBottomY = self.height - pad
	local taxonomyMidY = taxonomyTabY + math.floor((taxonomyBottomY - taxonomyTabY) / 2)
	GlobalStorageSiK.AdminDashboardAudit.build(self, pad, taxonomyTabY, textW, taxonomyMidY - 4)
	GlobalStorageSiK.AdminDashboardCorpus.build(self, pad, taxonomyMidY + 4, textW, taxonomyBottomY)
	self:layoutTaxonomyTab()

	-- Herramientas internas aportadas por los addons. El Dashboard solo pinta
	-- el registro neutral; cada addon conserva la responsabilidad de abrir su
	-- ruta vanilla y de decidir como se integra con una sesion de red activa.
	local staffActions = GlobalStorageSiK.TerminalExtensions.getStaffActions()
	if #staffActions > 0 then
		local toolsTitle = GlobalStorageSiK.SiK_UI.createSectionLabel(pad, y, T("IGUI_GS_AdminInternalTests"))
		self:addChild(toolsTitle)
		trackNetworkTabWidget(self, toolsTitle)
		y = y + FONT_HGT_SMALL + LINE_GAP

		local actionGap = 8
		local actionW = math.floor((textW - actionGap) / 2)
		for i = 1, #staffActions do
			local action = staffActions[i]
			local column = (i - 1) % 2
			local row = math.floor((i - 1) / 2)
			local buttonW = (#staffActions == 1) and textW or actionW
			local buttonX = pad + column * (actionW + actionGap)
			local actionBtn = GlobalStorageSiK.SiK_UI.createButton(
				buttonX, y + row * (BTN_H + LINE_GAP), buttonW, BTN_H, T(action.labelKey), self,
				staffActionCallback(action, self))
			self:addChild(actionBtn)
			trackNetworkTabWidget(self, actionBtn)
		end
		local actionRows = math.ceil(#staffActions / 2)
		y = y + actionRows * (BTN_H + LINE_GAP) + 6
	end

	self.membersTitle = ISLabel:new(pad, y, FONT_HGT_SMALL, T("IGUI_GS_AdminMembersTitle"),
		0.7, 0.72, 0.76, 1, UIFont.Small, true)
	self.membersTitle:initialise()
	self:addChild(self.membersTitle)
	trackNetworkTabWidget(self, self.membersTitle)
	y = y + FONT_HGT_SMALL + LINE_GAP

	-- Añadir miembro (pedido explicito 2026-08-22): desplegable de jugadores
	-- CONECTADOS ahora mismo, sin facción - el staff gestiona cualquier red.
	local addBtnW = 90
	self.addMemberCombo = ISComboBox:new(pad, y, textW - addBtnW - 8, ENTRY_H, self, nil)
	self.addMemberCombo:initialise()
	GlobalStorageSiK.SiK_UI.styleComboBox(self.addMemberCombo)
	self:addChild(self.addMemberCombo)
	trackNetworkTabWidget(self, self.addMemberCombo)
	self.addMemberBtn = GlobalStorageSiK.SiK_UI.createButton(
		pad + textW - addBtnW, y, addBtnW, ENTRY_H, T("IGUI_GS_AdminAddMember"), self, function()
			self:onAddMember()
		end)
	self:addChild(self.addMemberBtn)
	trackNetworkTabWidget(self, self.addMemberBtn)
	y = y + ENTRY_H + LINE_GAP + 6

	-- Texto de longitud variable SIEMPRE con wrap real (regla del proyecto) -
	-- antes era un ISLabel de una sola linea y se salia/cortaba por el borde
	-- de la ventana (confirmado en pruebas reales).
	local hintLines = GlobalStorageSiK.SiK_UI.wrapTextLines(T("IGUI_GS_AdminDashboardHint"), textW, UIFont.Small)
	local actionsH = BTN_H + ROW_GAP
	local hintH = (#hintLines * (FONT_HGT_SMALL + 2)) + ROW_GAP
	local memberH = math.max(MIN_VISIBLE_ROWS * (ROW_H + ROW_GAP), self.height - y - actionsH - hintH - pad)
	self.memberScroll = GlobalStorageSiK.TerminalScroll.create(self, pad, y, textW, memberH)
	trackNetworkTabWidget(self, self.memberScroll)
	local actionsY = y + memberH + ROW_GAP

	self.releaseBtn = GlobalStorageSiK.SiK_UI.createButton(
		pad, actionsY, reloadW, BTN_H, T("IGUI_GS_AdminReleaseOwnership"), self, function()
			self:onReleaseOwnership()
		end, nil, true)
	self:addChild(self.releaseBtn)
	trackNetworkTabWidget(self, self.releaseBtn)

	self.deleteBtn = GlobalStorageSiK.SiK_UI.createButton(
		pad + reloadW + 8, actionsY, reloadW, BTN_H, T("IGUI_GS_AdminDeleteNetwork"), self, function()
			self:onDeleteNetworkConfirm()
		end, nil, true)
	GlobalStorageSiK.SiK_UI.applyDangerButton(self.deleteBtn)
	self:addChild(self.deleteBtn)
	trackNetworkTabWidget(self, self.deleteBtn)

	local hintY = actionsY + BTN_H + ROW_GAP
	for _, line in ipairs(hintLines) do
		local hintLbl = ISLabel:new(pad, hintY, FONT_HGT_SMALL, line, 0.55, 0.57, 0.6, 1, UIFont.Small, true)
		hintLbl:initialise()
		self:addChild(hintLbl)
		trackNetworkTabWidget(self, hintLbl)
		hintY = hintY + FONT_HGT_SMALL + 2
	end

	-- El bloque de abajo (acciones + hint) puede quedar mas bajo que la
	-- altura fija de la ventana si el scroll de miembros se alargo para
	-- garantizar MIN_VISIBLE_ROWS - crecer la ventana en vez de solapar.
	local neededHeight = hintY + pad
	if neededHeight > self.height then
		self:setHeight(neededHeight)
	end

	GlobalStorageSiK.SiK_UI.centerModal(self)
	-- dev22: recuerda la pestaña activa SOLO durante la sesion de la ventana
	-- (pedido explicito de sistemas, no hace falta persistirla) - por
	-- defecto "network" en la apertura inicial, conservada tras un resize
	-- (rebuildAfterResize llama a buildStaticFrame de nuevo).
	self:selectStaffTab(self._activeStaffTab or "network")
end

---@param networks table[]
function GS_AdminDashboardUI:refreshNetworkList(networks)
	self._networks = networks or {}
	local selectedIndex = nil
	local prevSelectedId = self._selectedNetworkId
	self.networkCombo:clear()
	for i = 1, #self._networks do
		local net = self._networks[i]
		-- net.label ya incluye "(cuenta del propietario)" o "(VACANTE)" y el
		-- id interno, construido en adminListNetworks - no duplicar aqui.
		self.networkCombo:addOption(net.label or net.networkId or "?")
		if net.networkId == prevSelectedId then selectedIndex = i end
	end
	if #self._networks == 0 then
		self._selectedNetworkId = nil
		self._selectedNetwork = nil
		self:refreshInfoLines()
		self:refreshMemberPanel({})
		return
	end
	self.networkCombo.selected = selectedIndex or 1
	self:onComboChanged()
end

function GS_AdminDashboardUI:onComboChanged()
	local idx = self.networkCombo.selected or 1
	local net = self._networks and self._networks[idx]
	if not net then return end
	self._selectedNetworkId = net.networkId
	self._selectedNetwork = net
	self:refreshInfoLines()
	self:requestMembers(net.networkId)
end

--- Bloque de info con wrap real (regla del proyecto: nunca truncar texto de
--- longitud variable en un ISLabel de una sola linea) - antes esto vivia en
--- filas de tabla truncadas y se solapaba visualmente entre redes.
function GS_AdminDashboardUI:refreshInfoLines()
	local net = self._selectedNetwork
	local lines = {}
	if net then
		lines[#lines + 1] = net.label .. "  [" .. net.networkId .. "]"
		if net.vacant then
			lines[#lines + 1] = T("IGUI_GS_AdminInfoVacant")
		else
			lines[#lines + 1] = T("IGUI_GS_AdminInfoOwner", net.owner or "?")
		end
		lines[#lines + 1] = T("IGUI_GS_AdminInfoAccount", (net.ownerAccountLogin ~= "" and net.ownerAccountLogin) or "?")
		-- BUG REAL COSMETICO cerrado (2026-08-26, hallazgo de Desarrollo -
		-- "N miembros" incluia fichas ROLE_DEAD conservadas a proposito, dando
		-- la impresion de mas gente con acceso real de la que hay): separa
		-- activos de historico en 2 numeros explicitos en vez de sumarlos.
		local deadRecords = math.max(0, (net.memberCount or 0) - (net.activeMemberCount or net.memberCount or 0))
		lines[#lines + 1] = T("IGUI_GS_AdminNetworkCounts",
			net.activeMemberCount or net.memberCount or 0, deadRecords, net.terminalCount or 0)
	end
	for i = 1, INFO_LINE_COUNT do
		self.infoLbls[i]:setName(lines[i] or "")
	end
end

---@param members table[]
function GS_AdminDashboardUI:refreshMemberPanel(members)
	self._members = members or {}
	self:refreshOnlinePlayersCombo()
	local scroll = self.memberScroll
	GlobalStorageSiK.TerminalScroll.clear(scroll)
	local w = GlobalStorageSiK.TerminalScroll.contentWidth(scroll)
	local cols = GlobalStorageSiK.SiK_UI.Table.resolveColumns(w, ADMIN_MEMBER_TABLE_COLUMNS, ADMIN_MEMBER_TABLE_OPTIONS)
	local btnW = cols[3].width
	local nameMaxW = cols[1].width - cols[1].pad * 2
	local seenX = cols[2].x
	local headerMetrics = GlobalStorageSiK.SiK_UI.Table.metrics()
	local header = ISPanel:new(0, 0, w, headerMetrics.headerHeight)
	header:initialise()
	header.drawBackground = false
	header.prerender = function(target)
		ISPanel.prerender(target)
		GlobalStorageSiK.SiK_UI.Table.drawHeader(target, ADMIN_MEMBER_TABLE_COLUMNS,
			 nil, true, 2, UIFont.Small, ADMIN_MEMBER_TABLE_OPTIONS)
	end
	GlobalStorageSiK.SiK_UI.Table.attachHeaderResize(
		header, ADMIN_MEMBER_TABLE_COLUMNS, ADMIN_MEMBER_TABLE_OPTIONS)
	GlobalStorageSiK.TerminalScroll.addChild(scroll, header)
	local y = headerMetrics.headerHeight + 2
	local dashboard = self
	if #self._members == 0 then
		local lbl = ISLabel:new(6, y, FONT_HGT_SMALL, T("IGUI_GS_AdminNoMembers"), 0.6, 0.63, 0.66, 1, UIFont.Small, true)
		lbl:initialise()
		GlobalStorageSiK.TerminalScroll.addChild(scroll, lbl)
		y = y + FONT_HGT_SMALL + LINE_GAP
	end
	for i = 1, #self._members do
		local m = self._members[i]
		local row = ISPanel:new(0, y, w, ROW_H)
		row:initialise()
		row.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
		row.borderColor = { r = 0, g = 0, b = 0, a = 0 }
		row.prerender = function(self)
			ISPanel.prerender(self)
			GlobalStorageSiK.SiK_UI.drawTableRowBackground(self, i, self:isMouseOver(), false)
			-- Rol como fuente unica de verdad (incluido "Muerto" = ROLE_DEAD, ver
			-- GS_Permissions.lua). Columna de conexion aparte, puramente
			-- informativa (pedido explicito 2026-08-22, nunca se infiere ni se
			-- marca nada desde aqui): "Conectado" en verde para quien sigue en
			-- linea ahora mismo, "Desconectado hace X" para el resto.
			local label = "[" .. roleLabel(m.role) .. "] " .. memberLabel(m)
			local yMid = math.floor((self.height - FONT_HGT_SMALL) / 2)
			self:drawText(GlobalStorageSiK.SiK_UI.truncateText(label, nameMaxW, UIFont.Small),
				cols[1].x + cols[1].pad, yMid, 0.85, 0.87, 0.9, 1, UIFont.Small)
			local seenText, sr, sg, sb = connectionLabel(m)
			self:drawText(GlobalStorageSiK.SiK_UI.truncateText(seenText, COL_SEEN_W, UIFont.Small),
				seenX, yMid, sr, sg, sb, 1, UIFont.Small)
		end
		GlobalStorageSiK.TerminalScroll.addChild(scroll, row)
		local editBtn = GlobalStorageSiK.SiK_UI.createButton(
			cols[3].x, math.floor((ROW_H - BTN_H) / 2), btnW, BTN_H, T("IGUI_GS_AdminEditMember"), row, function()
				GlobalStorageSiK.AdminDashboard.openMemberEditor(dashboard, m)
			end)
		row:addChild(editBtn)
		y = y + ROW_H + ROW_GAP
	end
	GlobalStorageSiK.TerminalScroll.setContentHeight(scroll, y)
	GlobalStorageSiK.TerminalScroll.ensureScrollBars(scroll)
end

function GS_AdminDashboardUI:onSetMemberRole(characterId, role)
	if not self._selectedNetworkId then return end
	if GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.sendCommand then
		GlobalStorageSiK.NetClient.sendCommand("adminSetMemberRole",
			{ networkId = self._selectedNetworkId, characterId = characterId, role = role })
	end
end

function GS_AdminDashboardUI:onRemoveMember(characterId)
	if not self._selectedNetworkId then return end
	if GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.sendCommand then
		GlobalStorageSiK.NetClient.sendCommand("adminRemoveMember",
			{ networkId = self._selectedNetworkId, characterId = characterId })
	end
end

function GS_AdminDashboardUI:onSetOwner(characterId)
	if not self._selectedNetworkId then return end
	if GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.sendCommand then
		GlobalStorageSiK.NetClient.sendCommand("adminSetOwner",
			{ networkId = self._selectedNetworkId, characterId = characterId })
	end
end

--- BUG REAL encontrado (auditoria de botones, 2026-08-26): sin red
--- seleccionada, este boton no hacia absolutamente nada al pulsarlo - ni
--- aviso, ni bloqueo visual, un boton "muerto" en la practica. Ahora avisa
--- con un halo note, mismo patron ya usado en el resto del proyecto para
--- "revalida y avisa" en vez de fallar en silencio.
function GS_AdminDashboardUI:onReleaseOwnership()
	if not self._selectedNetworkId then
		local player = GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer()
		if player and player.setHaloNote then
			player:setHaloNote(T("IGUI_GS_AdminNoNetworkSelected"), 220, 180, 100, 300)
		end
		return
	end
	if GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.sendCommand then
		GlobalStorageSiK.NetClient.sendCommand("adminReleaseOwnership", { networkId = self._selectedNetworkId })
	end
end

--- Borrar red: SOLO quita el registro de permisos/miembros/zonas propias del
--- registro del mod. NUNCA toca objetos fisicos del mundo - cualquier
--- GS_TerminalUnit que apuntara a esta red queda "desvinculado" (mismo
--- estado que ya existe hoy si una red se rompe por otra via), ofreciendo la
--- tarjeta de "instalar aqui" para re-vincularlo. Confirmacion obligatoria.
function GS_AdminDashboardUI:onDeleteNetworkConfirm()
	if not self._selectedNetworkId then
		local player = GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer()
		if player and player.setHaloNote then
			player:setHaloNote(T("IGUI_GS_AdminNoNetworkSelected"), 220, 180, 100, 300)
		end
		return
	end
	local networkId = self._selectedNetworkId
	local dashboard = self
	GlobalStorageSiK.SiK_UI.Modal.confirm(T("IGUI_GS_AdminDeleteNetworkConfirm", networkId), function()
		if GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.sendCommand then
			GlobalStorageSiK.NetClient.sendCommand("adminDeleteNetwork", { networkId = networkId, confirm = true })
		end
		dashboard._selectedNetworkId = nil
		dashboard._selectedNetwork = nil
	end)
end

--- Reenganchado desde GS_Client.lua al recibir cada comando del servidor.
---@param networks table[]
function GlobalStorageSiK.AdminDashboard.onNetworkList(networks)
	local ui = GlobalStorageSiK.AdminDashboard.instance
	if ui then
		ui:refreshNetworkList(networks)
	end
end

---@param players table[]
function GlobalStorageSiK.AdminDashboard.onOnlinePlayers(players)
	local ui = GlobalStorageSiK.AdminDashboard.instance
	if ui then
		ui._onlinePlayers = players or {}
		ui:refreshOnlinePlayersCombo()
	end
end

---@param networkId string
---@param members table[]
function GlobalStorageSiK.AdminDashboard.onNetworkMembers(networkId, members)
	local ui = GlobalStorageSiK.AdminDashboard.instance
	if ui and ui._selectedNetworkId == networkId then
		ui:refreshMemberPanel(members)
	end
end

---@param networkId string
---@param events table[]
function GlobalStorageSiK.AdminDashboard.onNetworkHistory(networkId, events)
	local ui = GlobalStorageSiK.AdminDashboard.instance
	if ui and ui._selectedNetworkId == networkId then
		-- Pedido explicito 2026-08-22 ("por si nos hacen capturas, poder ver a
		-- que red pertenece ese historial"): el mismo label que ya usa el
		-- combo de red (nombre + cuenta del propietario + id interno).
		local label = (ui._selectedNetwork and ui._selectedNetwork.label) or networkId
		GlobalStorageSiK.AdminDashboard.showHistory(events, label, networkId)
	end
end

---@param report table
function GlobalStorageSiK.AdminDashboard.onNativeAuditSummary(report)
	local ui = GlobalStorageSiK.AdminDashboard.instance
	if ui then
		GlobalStorageSiK.AdminDashboardAudit.onSummary(ui, report)
	end
end

---@param report table
function GlobalStorageSiK.AdminDashboard.onNativeCorpusSummary(report)
	local ui = GlobalStorageSiK.AdminDashboard.instance
	if ui then
		GlobalStorageSiK.AdminDashboardCorpus.onSummary(ui, report)
	end
end

---@param args table|nil
function GlobalStorageSiK.AdminDashboard.onActionResult(args)
	local ui = GlobalStorageSiK.AdminDashboard.instance
	-- dev22: cualquier actionResult (exito o fallo) libera el estado
	-- "ejecutando" del boton de auditoria, independientemente de si hay una
	-- red seleccionada - la guarda de abajo es solo para el refresco de
	-- redes/miembros, no debe bloquear esto. dev24: mismo trato para la
	-- suite de corpus, aislada de la de auditoria (action/requestId propios).
	if ui then
		GlobalStorageSiK.AdminDashboardAudit.onActionResult(ui, args)
		GlobalStorageSiK.AdminDashboardCorpus.onActionResult(ui, args)
	end
	if not ui or not ui._selectedNetworkId then return end
	-- Refresco simple tras cualquier accion: repedir ambas listas en vez de
	-- intentar diferenciar que comando disparo el actionResult - el coste es
	-- 2 peticiones pequeñas, la alternativa es logica de correlacion fragil.
	-- No hace falta un "difundir a todos los clientes conectados" aparte:
	-- ModData.transmit(MODDATA_KEY), ya llamado por cada comando admin* que
	-- muta datos, empuja el registro completo a TODOS los clientes conectados
	-- automaticamente (confirmado, ver GS_Server.lua) - cualquier jugador con
	-- su propia pestaña Red abierta ya se actualiza solo sin nada extra aqui.
	ui:requestNetworkList()
	ui:requestMembers(ui._selectedNetworkId)
end

local function requestLatestTaxonomySummaries()
	if not GlobalStorageSiK.NetClient or not GlobalStorageSiK.NetClient.sendCommand then return end
	GlobalStorageSiK.NetClient.sendCommand("getLastNativeAuditSummary", {})
	GlobalStorageSiK.NetClient.sendCommand("getLastNativeCorpusSummary", {})
end

--- Abre (o trae al frente) el panel. Solo se llama desde un punto ya gateado
--- por isServerStaff en el CLIENTE (icono lateral) - la autorizacion real
--- vuelve a comprobarse en servidor en cada comando, esto es solo UX.
function GlobalStorageSiK.AdminDashboard.show()
	if GlobalStorageSiK.AdminDashboard.instance then
		GlobalStorageSiK.AdminDashboard.instance:setVisible(true)
		GlobalStorageSiK.AdminDashboard.instance:bringToTop()
		GlobalStorageSiK.AdminDashboard.instance:requestNetworkList()
		requestLatestTaxonomySummaries()
		return
	end
	local sw = getCore():getScreenWidth()
	local sh = getCore():getScreenHeight()
	local w = math.min(WINDOW_W, sw - 40)
	local h = math.min(WINDOW_H, sh - 40)
	local ui = GS_AdminDashboardUI:new((sw - w) / 2, (sh - h) / 2, w, h)
	ui:initialise()
	ui:addToUIManager()
	GlobalStorageSiK.AdminDashboard.instance = ui
	requestLatestTaxonomySummaries()
end
