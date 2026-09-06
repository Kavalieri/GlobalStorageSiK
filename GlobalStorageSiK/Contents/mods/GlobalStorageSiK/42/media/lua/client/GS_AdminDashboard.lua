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

require "GS_UI_Feedback"

require "GS_I18n"
require "GS_NetClient"
require "GS_Permissions"
require "GS_TerminalUI_Extensions"
require "GS_AdminDashboard_Audit"
require "GS_AdminDashboard_Corpus"

local UI = require "GS_UI_Framework"
local Confirmation = require "GS_Confirmation"

GlobalStorageSiK.AdminDashboard = GlobalStorageSiK.AdminDashboard or {}
GlobalStorageSiK.AdminDashboard.instance = nil

local T = GlobalStorageSiK.I18n.text
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local FONT_HGT_MEDIUM = getTextManager():getFontHeight(UIFont.Medium)
local CONTROL_METRICS = UI.Controls.metrics("staff")
local PAD = 14
local LINE_GAP = 4
local BTN_H = CONTROL_METRICS.buttonHeight
local TABLE_METRICS = UI.Table.metrics()
local ROW_H = TABLE_METRICS.rowHeight
local ROW_GAP = 4
local ENTRY_H = CONTROL_METRICS.inputHeight
local WINDOW_W = 860
local WINDOW_H = 780
local INFO_LINE_COUNT = 12
local INFO_BASE_LINES = 2
local MIN_VISIBLE_ROWS = 3
-- Columna "Conexion" de la lista de miembros - "Conectado" en verde para
-- quien sigue en linea, "Desconectado hace X" para el resto. Medida con el
-- peor caso ("99d") igual criterio que el resto de columnas del mod.
local COL_SEEN_W = math.max(
	getTextManager():MeasureStringX(UIFont.Small, GlobalStorageSiK.I18n.text("IGUI_GS_AdminOnline")),
	getTextManager():MeasureStringX(UIFont.Small, GlobalStorageSiK.I18n.text("IGUI_GS_AdminOffline", "99d"))
) + 14
local ADMIN_MEMBER_TABLE_COLUMNS = {
	{ key = "member", titleKey = "IGUI_GS_PermColMemberName", flex = 1, minWidth = 100, pad = 6 },
	{ key = "connection", titleKey = "IGUI_GS_PermColConnection", width = COL_SEEN_W, align = "right", pad = 4 },
}
-- El ScrollableRegion ya entrega el contentRect útil; la tabla no reserva una
-- segunda vez el scrollbar a la derecha.
local ADMIN_MEMBER_TABLE_OPTIONS = { left = 0, right = 0 }

local function createButton(x, y, w, h, text, onClick, danger)
	return UI.Controls.button(nil, {
		x = x, y = y, w = w, h = h, text = text,
		onClick = onClick, danger = danger == true, fullWidth = true,
	})
end

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

local function relativeAge(tsMs)
	tsMs = tonumber(tsMs) or 0
	if tsMs <= 0 then return "?" end
	local nowTs = getTimestampMs and tonumber(getTimestampMs()) or 0
	if nowTs <= 0 then return "?" end
	local deltaMs = nowTs - tsMs
	if deltaMs < -5000 then return "?" end
	local deltaS = math.max(0, math.floor(deltaMs / 1000))
	if deltaS < 2 then return T("IGUI_GS_AdminAgeNow") end
	if deltaS < 60 then return T("IGUI_GS_AdminAgeSeconds", deltaS) end
	if deltaS < 3600 then return T("IGUI_GS_AdminAgeMinutes", math.floor(deltaS / 60)) end
	if deltaS < 86400 then return T("IGUI_GS_AdminAgeHours", math.floor(deltaS / 3600)) end
	return T("IGUI_GS_AdminAgeDays", math.floor(deltaS / 86400))
end

GlobalStorageSiK.AdminDashboard.relativeAge = relativeAge

--- Columna "Conexion" de un miembro: 3 estados posibles, nunca solo 2 -
--- "Desconectado" no tiene sentido para alguien fallecido (pedido explicito
--- 2026-08-22: "no tiene sentido que diga desconectado, está muerto, pero sí
--- cuándo se detectó su muerte"). Puramente informativo, igual que el resto
--- de esta columna - nunca se usa para inferir ni marcar nada.
---@param m table
---@return string text, number r, number g, number b
local function connectionLabel(m)
	local ok = UI.Theme.color("success")
	local warn = UI.Theme.color("warning")
	if m.online then
		return T("IGUI_GS_AdminOnline"), ok.r, ok.g, ok.b
	end
	if m.role == GlobalStorageSiK.Permissions.ROLE_DEAD then
		return T("IGUI_GS_AdminDeathDetected", relativeAge(m.diedAt)), warn.r, warn.g, warn.b
	end
	return T("IGUI_GS_AdminOffline", relativeAge(m.lastSeenAt)), 0.6, 0.63, 0.66
end

-- La tabla comun recibe datos semanticos; ella es la unica propietaria del
-- chrome, columnas, truncado, hover, clipping y resize. Admin no vuelve a
-- pintar una segunda implementacion local de esas piezas.
ADMIN_MEMBER_TABLE_COLUMNS[1].value = function(member)
	return {
		text = "[" .. roleLabel(member and member.role) .. "] " .. memberLabel(member),
		color = UI.Theme.color("text"),
	}
end
ADMIN_MEMBER_TABLE_COLUMNS[2].value = function(member)
	local text, r, g, b = connectionLabel(member or {})
	return { text = text, color = { r, g, b } }
end

-- ============================================================================
-- Modal pequeño: historial de auditoria de UNA red (solo lectura).
-- ============================================================================
GS_AdminHistoryUI = UI.Window.derive("GS_AdminHistoryUI")

local HISTORY_MIN_W = 420
local HISTORY_MIN_H = 320
-- Cuantas entradas recientes copia "Copiar reciente" al portapapeles (pedido
-- explicito: "un margen razonable para cubrir el rango de tiempo que nos
-- interesa" - los eventos ya vienen mas-reciente-primero desde el servidor,
-- HISTORY_MAX_ENTRIES en GS_Permissions.lua acota a 40 por red como maximo
-- real, asi que 100 ya cubre TODO el historial disponible de cualquier red).
local HISTORY_COPY_COUNT = 100

function GS_AdminHistoryUI:initialise()
	UI.Window.callBase(self, "initialise")
	self:setAlwaysOnTop(true)
	self.headerHeight = FONT_HGT_MEDIUM + PAD + LINE_GAP
	UI.Modal.apply(self, {
		kind = "task", title = T("IGUI_GS_AdminHistoryTitle"),
		scroll = false,
		playerNum = self.playerNum or 0, x = self.x, y = self.y,
		width = self.width, height = self.height, minWidth = HISTORY_MIN_W,
		minHeight = HISTORY_MIN_H, headerHeight = self.headerHeight,
		padding = PAD, resizable = true,
		onResize = function()
			if self.eventScroll then
				local content = self.contentBlock:getContentRect()
				UI.Scroll.resize(self.eventScroll,
					content.w, math.max(1, content.y + content.h - self.scrollTopY))
			end
		end,
		onResizeEnd = function()
			if self.eventScroll then self:refreshEvents() end
		end,
		onClose = function()
			GlobalStorageSiK.AdminDashboard.historyInstance = nil
		end,
	})
	local host = self.contentHost or self
	local content = self.contentBlock and self.contentBlock:getContentRect()
		or { x = PAD, y = self.headerHeight + PAD, w = self.width - PAD * 2,
			h = self.height - self.headerHeight - PAD * 2 }
	local scrollY = content.y
	-- Identificar la red en la propia cabecera (pedido explicito 2026-08-22:
	-- "por si nos hacen capturas, poder ver a que red pertenece ese
	-- historial") - mismo label que el combo de red, envuelto (regla del
	-- proyecto: texto de longitud variable siempre con wrap real).
	if self.networkLabel and self.networkLabel ~= "" then
		local labelW = content.w
				for _, line in ipairs(UI.Controls.wrapText(self.networkLabel, labelW, UIFont.Small)) do
						UI.Controls.copyText(host, {
								x = content.x, y = scrollY, w = labelW, text = line,
                                tone = "textMuted", font = UIFont.Small, lineGap = 2,
                        })
                        scrollY = scrollY + FONT_HGT_SMALL + 2
		end
		scrollY = scrollY + 4
	end
	-- Fila de acciones (2026-08-26, pedido explicito): copiar el historial
	-- reciente al portapapeles y borrarlo si se quiere empezar de cero -
	-- ninguna de las dos toca redes/permisos, solo el registro de auditoria.
	local actionBtnW = math.floor((content.w - 8) / 2)
	self.copyBtn = createButton(
		content.x, scrollY, actionBtnW, BTN_H, T("IGUI_GS_AdminHistoryCopy"), function()
			self:onCopyRecent()
		end)
	host:addChild(self.copyBtn)
	self.clearBtn = createButton(
		content.x + actionBtnW + 8, scrollY, actionBtnW, BTN_H, T("IGUI_GS_AdminHistoryClear"), function()
			self:onClearHistory()
		end, true)
	host:addChild(self.clearBtn)
	scrollY = scrollY + BTN_H + LINE_GAP
	self.scrollTopY = scrollY
	self.eventScroll = UI.Scroll.create(
		host, content.x, scrollY, content.w, content.y + content.h - scrollY)
	UI.Scroll.setOnContentRectChanged(self.eventScroll, function()
		if self._historyRelayout then return end
		self._historyRelayout = true
		self:refreshEvents()
		self._historyRelayout = false
	end)
	self:refreshEvents()
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
	if player then
		GlobalStorageSiK.UIFeedback.halo(player, T("IGUI_GS_AdminHistoryCopied", count),
			180, 220, 160, 350, { tone = "success" })
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
	UI.Modal.close(self, "destroy")
end

function GS_AdminHistoryUI:onKeyRelease(key)
	if key == Keyboard.KEY_ESCAPE then self:destroy(); return true end
	return UI.Window.callBase(self, "onKeyRelease", key)
end

---@param events table[]
function GS_AdminHistoryUI:refreshEvents()
	local scroll = self.eventScroll
	UI.Scroll.clear(scroll, true)
	local w = UI.Scroll.contentWidth(scroll)
	local y = 4
	local events = self.events or {}
	if #events == 0 then
                UI.Controls.copyText(UI.Scroll.childHost(scroll), {
                        x = 6, y = y, w = math.max(1, w - 12),
                        text = T("IGUI_GS_AdminHistoryEmpty"), tone = "textMuted",
                        font = UIFont.Small, lineGap = 2,
                })
                y = y + FONT_HGT_SMALL + LINE_GAP
	else
		-- Mas reciente primero.
		for i = #events, 1, -1 do
			local ev = events[i]
			local header = relativeAge(ev.ts) .. " - " .. tostring(ev.type)
                        UI.Controls.copyText(UI.Scroll.childHost(scroll), {
                                x = 6, y = y, w = math.max(1, w - 12), text = header,
                                tone = "warning", font = UIFont.Small, lineGap = 2,
                        })
                        y = y + FONT_HGT_SMALL + 2
			local lines = UI.Controls.wrapText(ev.detail or "", w - 12, UIFont.Small)
			for j = 1, #lines do
                                UI.Controls.copyText(UI.Scroll.childHost(scroll), {
                                        x = 12, y = y, w = math.max(1, w - 18), text = lines[j],
                                        tone = "text", font = UIFont.Small, lineGap = 2,
                                })
                                y = y + FONT_HGT_SMALL + 2
			end
			y = y + ROW_GAP
		end
	end
	UI.Scroll.setContentHeight(scroll, y)
	UI.Scroll.ensureScrollBars(scroll)
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
        local dashboard = GlobalStorageSiK.AdminDashboard.instance
        ui.playerNum = dashboard and dashboard.playerNum or 0
        ui.events = events or {}
	ui.networkLabel = networkLabel or ""
	ui.networkId = networkId
	ui:initialise()
	UI.Modal.setOwner(ui, dashboard)
	UI.Modal.show(ui)
	GlobalStorageSiK.AdminDashboard.historyInstance = ui
end

-- ============================================================================
-- Modal pequeño: ajuste fino de UN miembro (rol / propietario / quitar).
-- Mismo patron visual que GS_TerminalUI_MemberEditor.lua, pero las acciones
-- van contra los comandos admin* (staff), no los del propietario normal.
-- ============================================================================
GS_AdminMemberEditorUI = UI.Window.derive("GS_AdminMemberEditorUI")

function GS_AdminMemberEditorUI:initialise()
	UI.Window.callBase(self, "initialise")
	self:setAlwaysOnTop(true)
	self.headerHeight = FONT_HGT_MEDIUM + PAD + LINE_GAP
	UI.Modal.apply(self, {
		kind = "compact", title = T("IGUI_GS_AdminMemberEditorTitle"),
		playerNum = self.playerNum or 0, x = self.x, y = self.y,
		width = self.width, height = self.height, headerHeight = self.headerHeight,
		padding = PAD, resizable = false,
		onClose = function()
			GlobalStorageSiK.AdminDashboard.memberEditorInstance = nil
		end,
	})
	self:buildLayout()
end

function GS_AdminMemberEditorUI:destroy()
	UI.Modal.close(self, "destroy")
end

function GS_AdminMemberEditorUI:onKeyRelease(key)
	if key == Keyboard.KEY_ESCAPE then self:destroy(); return true end
	return UI.Window.callBase(self, "onKeyRelease", key)
end

function GS_AdminMemberEditorUI:buildLayout()
	local host = self.contentHost or self
	local pad = 0
	local y = 0
	local textW = host.width or 0
	local m = self.member

	-- El rol es la unica fuente de verdad, incluido "muerto" (ROLE_DEAD, ver
	-- GS_Permissions.lua) - ya no hace falta un sufijo aparte basado en
	-- diedAt, roleLabel(m.role) ya dice "Muerto"/"Dead" por si solo.
        local isDead = (m.role == GlobalStorageSiK.Permissions.ROLE_DEAD)
        local nameText = "[" .. roleLabel(m.role) .. "] " .. memberLabel(m)
        for _, line in ipairs(UI.Controls.wrapText(nameText, textW, UIFont.Small)) do
				UI.Controls.copyText(host, {
                        x = pad, y = y, w = textW, text = line,
                        tone = "text", font = UIFont.Small, lineGap = 2,
                })
                y = y + FONT_HGT_SMALL + 2
        end
	-- Conexion: a nivel informativo unicamente (pedido explicito 2026-08-22),
	-- nunca se usa para inferir ni marcar nada automaticamente - solo ayuda a
	-- staff a diagnosticar un caso "colgado" (diedAt nunca llegado a marcar
	-- por un crash, desconexion sucia, etc.).
        local seenText = connectionLabel(m)
		UI.Controls.copyText(host, {
                x = pad, y = y, w = textW, text = seenText,
                tone = m.online and "success"
                        or (isDead and "warning" or "textMuted"),
                font = UIFont.Small, lineGap = 2,
        })
	y = y + FONT_HGT_SMALL + LINE_GAP + 4

	local dashboard = self.dashboard
	local btnW = textW
	local isOwnerRow = (m.role == "owner")

	if isDead then
		-- Un miembro fallecido no admite ninguna accion desde aqui (nada de
		-- marcado manual, ver rechazo explicito 2026-08-22) - de solo lectura,
		-- se conserva unicamente como registro consultable/auditable.
				UI.Controls.copyText(host, {
                        x = pad, y = y, w = textW,
                        text = T("IGUI_GS_AdminMemberEditorDeadHint"),
                        tone = "textMuted", font = UIFont.Small, lineGap = 2,
                })
		y = y + FONT_HGT_SMALL + ROW_GAP
	elseif not isOwnerRow then
		local toggleTo = (m.role == "admin") and "member" or "admin"
		local roleBtn = createButton(
			pad, y, btnW, BTN_H, T(toggleTo == "admin" and "IGUI_GS_AdminMakeAdmin" or "IGUI_GS_AdminMakeMember"),
			function()
				dashboard:onSetMemberRole(m.id, toggleTo)
				self:destroy()
			end)
		host:addChild(roleBtn)
		y = y + BTN_H + ROW_GAP

		local ownerBtn = createButton(
			pad, y, btnW, BTN_H, T("IGUI_GS_AdminSetOwner"), function()
				dashboard:onSetOwner(m.id)
				self:destroy()
			end)
		host:addChild(ownerBtn)
		y = y + BTN_H + ROW_GAP

		local removeBtn = createButton(
			pad, y, btnW, BTN_H, T("IGUI_GS_AdminRemoveMember"), function()
				dashboard:onRemoveMember(m.id)
				self:destroy()
			end, true)
		host:addChild(removeBtn)
		y = y + BTN_H + ROW_GAP
	else
				UI.Controls.copyText(host, {
                        x = pad, y = y, w = textW,
                        text = T("IGUI_GS_AdminMemberEditorOwnerHint"),
                        tone = "textMuted", font = UIFont.Small, lineGap = 2,
                })
		y = y + FONT_HGT_SMALL + ROW_GAP
	end

	local closeBtn = createButton(
		pad, y, btnW, BTN_H, T("IGUI_GS_Close"), function()
			self:destroy()
		end)
	host:addChild(closeBtn)
	y = y + BTN_H + pad

	UI.Modal.fitContent(self, y, { contentBottom = true, bottomPadding = 0, center = true })
end

---@param dashboard table
---@param member table
function GlobalStorageSiK.AdminDashboard.openMemberEditor(dashboard, member)
	if GlobalStorageSiK.AdminDashboard.memberEditorInstance then
		GlobalStorageSiK.AdminDashboard.memberEditorInstance:destroy()
	end
        local w = UI.Modal.STANDARD_MODAL_W
        local ui = GS_AdminMemberEditorUI:new(0, 0, w, 100)
        ui.playerNum = dashboard and dashboard.playerNum or 0
        ui.dashboard = dashboard
	ui.member = member
	ui:initialise()
	UI.Modal.setOwner(ui, dashboard)
	UI.Modal.show(ui)
	GlobalStorageSiK.AdminDashboard.memberEditorInstance = ui
end

-- ============================================================================
-- Ventana principal.
-- ============================================================================
GS_AdminDashboardUI = UI.Window.derive("GS_AdminDashboardUI")

local ADMIN_MIN_W = 720
local ADMIN_MIN_H = 520

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

--- Reconstruye el marco entero al tamano nuevo (ver comentario de
--- installMouseHandlers) conservando posicion en pantalla - buildStaticFrame
--- llama a centerModal al final (pensado para la construccion inicial), asi
--- que aqui se restaura la posicion previa despues para no "saltar" al
--- centro cada vez que se suelta el asa de redimensionado.
function GS_AdminDashboardUI:rebuildAfterResize()
	UI.Window.reflow(self)
	local textW = math.max(240, self.width - PAD * 2)
	local tabW = math.floor((textW - 8) / 2)
	if self.staffTabNetworkBtn then self.staffTabNetworkBtn:setWidth(tabW) end
	if self.staffTabTaxonomyBtn then self.staffTabTaxonomyBtn:setX(PAD + tabW + 8); self.staffTabTaxonomyBtn:setWidth(tabW) end
	if self.networkCombo then self.networkCombo:setWidth(textW) end
	self:refreshInfoLines()
	local halfW = math.floor(textW / 2) - 4
	if self.reloadBtn then self.reloadBtn:setWidth(halfW) end
	if self.historyBtn then self.historyBtn:setX(PAD + halfW + 8); self.historyBtn:setWidth(halfW) end
	local staffMinW = 0
	for i = 1, #(self.staffActionButtons or {}) do
		UI.Controls.fitButtonToContent(self.staffActionButtons[i])
		staffMinW = math.max(staffMinW, self.staffActionButtons[i]:getWidth())
	end
	-- El numero de filas forma parte de la geometria creada por buildStaticFrame.
	-- Conservarlo durante resize evita que cambiar 2->1 columnas desplace solo X
	-- y deje los botones solapados con el contenido posterior.
	local staffColumns = self._staffActionColumns or 2
	for i = 1, #(self.staffActionButtons or {}) do
		local button = self.staffActionButtons[i]
		local column = staffColumns == 2 and ((i - 1) % 2) or 0
		button:setX(PAD + column * (halfW + 8))
		button:setWidth(staffColumns == 2 and halfW or textW)
	end
	if self.addMemberBtn then UI.Controls.fitButtonToContent(self.addMemberBtn) end
	local addBtnW = self.addMemberBtn and math.min(textW, math.max(90, self.addMemberBtn:getWidth())) or 90
	if self.addMemberCombo then self.addMemberCombo:setWidth(math.max(100, textW - addBtnW - 8)) end
	if self.addMemberBtn then
		self.addMemberBtn:setX(PAD + textW - addBtnW)
		self.addMemberBtn:setWidth(addBtnW)
	end

	local hintLines = UI.Controls.wrapText(T("IGUI_GS_AdminDashboardHint"), textW, UIFont.Small)
	local hintPool = self.dashboardHintLabels or {}
	local hintH = math.max(1, #hintPool) * (FONT_HGT_SMALL + 2) + ROW_GAP
	local memberTop = self.memberScrollTopY or (self.memberScroll and self.memberScroll:getY()) or 200
	local memberH = math.max(3 * (ROW_H + ROW_GAP), self.height - memberTop - BTN_H - hintH - PAD - ROW_GAP)
	if self.memberScroll then
		UI.Scroll.resize(self.memberScroll, textW, memberH)
	end
	local actionsY = memberTop + memberH + ROW_GAP
	if self.releaseBtn then self.releaseBtn:setY(actionsY); self.releaseBtn:setWidth(halfW) end
	if self.deleteBtn then self.deleteBtn:setX(PAD + halfW + 8); self.deleteBtn:setY(actionsY); self.deleteBtn:setWidth(halfW) end
	local hintY = actionsY + BTN_H + ROW_GAP
        for i = 1, #hintPool do
                local label = hintPool[i]
                label:setY(hintY)
                label:setText(hintLines[i] or (i == #hintPool and table.concat(hintLines, " ") or ""))
                label:setVisible((hintLines[i] or "") ~= "")
		hintY = hintY + FONT_HGT_SMALL + 2
	end
	if self._members then self:refreshMemberPanel(self._members) end
	self:layoutTaxonomyTab()
	self:selectStaffTab(self._activeStaffTab or "network")
end

--- Recalcula en un unico punto los limites de las dos suites de Taxonomia.
--- Es idempotente y se ejecuta siempre despues de que ambas secciones hayan
--- sido pobladas, tanto en apertura como en cada reconstruccion por resize.
function GS_AdminDashboardUI:layoutTaxonomyTab()
	if not self._taxonomyTabY then return end
	local textW = math.max(200, self.width - PAD * 2)
	self._auditContentW = textW
	self._corpusContentW = textW
	if self.nativeAuditBtn then self.nativeAuditBtn:setWidth(textW) end
	if self.nativeCorpusBtn then self.nativeCorpusBtn:setWidth(textW) end
	if self.nativeAuditSummaryScroll then
		self.nativeAuditSummaryScroll:setWidth(textW)
	end
	if self.nativeCorpusSummaryScroll then
		self.nativeCorpusSummaryScroll:setWidth(textW)
	end
	local bottomY = self.height - PAD
	local midY = self._taxonomyTabY + math.floor((bottomY - self._taxonomyTabY) / 2)
	self._auditBottomLimit = midY - 4
	self._corpusBottomLimit = bottomY
	GlobalStorageSiK.AdminDashboardAudit.refreshSummary(self)
	GlobalStorageSiK.AdminDashboardCorpus.refreshSummary(self)
end

function GS_AdminDashboardUI:initialise()
	UI.Window.callBase(self, "initialise")
	self:setAlwaysOnTop(true)
	self.headerHeight = FONT_HGT_MEDIUM + PAD + LINE_GAP
	UI.Window.apply(self, {
		profile = "staff", title = T("IGUI_GS_AdminDashboardTitle"),
		playerNum = self.playerNum or 0, x = self.x, y = self.y,
		width = self.width, height = self.height,
		minWidth = ADMIN_MIN_W, minHeight = ADMIN_MIN_H,
		headerHeight = self.headerHeight, padding = PAD, resizable = true,
		focusPriority = UI.FocusStack.PRIORITY.STAFF,
		onResize = function()
			local nowMs = getTimestampMs and getTimestampMs() or 0
			if not self._lastReflowMs or (nowMs - self._lastReflowMs) >= ADMIN_REFLOW_DEBOUNCE_MS then
				self._lastReflowMs = nowMs
				self:rebuildAfterResize()
			end
		end,
		onResizeEnd = function()
			self._lastReflowMs = nil
			self:rebuildAfterResize()
		end,
                onClose = function()
                        GlobalStorageSiK.AdminDashboard.instance = nil
                        if self._relativeAgeBinding then
                                self._relativeAgeBinding:dispose()
                                self._relativeAgeBinding = nil
                        end
                        if self.memberTableBlock then
				self.memberTableBlock:dispose()
				self.memberTableBlock = nil
			end
			if self.memberTableFrame then
				self.memberTableFrame:dispose()
				self.memberTableFrame = nil
			end
		end,
        })
        self._relativeAgeBinding = UI.Lifecycle.bindVisibleRefresh(self, {
                intervalTicks = 15,
                refresh = function() self:refreshRelativeAges() end,
        })
        self:buildStaticFrame()
	self:requestNetworkList()
	self:requestOnlinePlayers()
end

--- Mantiene vivo el texto relativo de las dos suites mientras la ventana
--- permanece abierta. Solo reconstruye el bloque cuyo texto cambia y como
--- maximo una vez por segundo; no envia ninguna peticion de red.
function GS_AdminDashboardUI:refreshRelativeAges()
        local nowMs = getTimestampMs and tonumber(getTimestampMs()) or 0
	if nowMs <= 0 then return end
	if self._lastTaxonomyAgeRefreshMs and (nowMs - self._lastTaxonomyAgeRefreshMs) < 1000 then return end
	self._lastTaxonomyAgeRefreshMs = nowMs

	if self._nativeAuditLastReport then
		local auditText = relativeAge(self._nativeAuditFinishedAtMs)
		if auditText ~= self._nativeAuditFinishedAtText then
			self._nativeAuditFinishedAtText = auditText
			GlobalStorageSiK.AdminDashboardAudit.refreshSummary(self)
		end
	end
	if self._nativeCorpusLastReport then
		local corpusText = relativeAge(self._nativeCorpusFinishedAtMs)
		if corpusText ~= self._nativeCorpusFinishedAtText then
			self._nativeCorpusFinishedAtText = corpusText
			GlobalStorageSiK.AdminDashboardCorpus.refreshSummary(self)
		end
	end
end

function GS_AdminDashboardUI:destroy()
	self:close("destroy")
end

function GS_AdminDashboardUI:onKeyRelease(key)
	if key == Keyboard.KEY_ESCAPE then
		self:destroy()
		return true
	end
	return UI.Window.callBase(self, "onKeyRelease", key)
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
        self._addMemberOptions = {}
        local comboItems = {}
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
                        comboItems[#comboItems + 1] = {
                                text = memberLabel({ displayName = p.name, username = p.username }),
                                value = p.characterId,
                        }
                        if p.characterId == prevCharacterId then newSelected = #self._addMemberOptions end
                end
        end
        if #self._addMemberOptions == 0 then
                comboItems[1] = { text = T("IGUI_GS_AdminNoOnlinePlayers"), value = "" }
                self._addMemberOptions[1] = nil
        end
        self.addMemberCombo:setItems(comboItems, newSelected)
	if self.addMemberBtn then
		local hasOptions = #self._addMemberOptions > 0
		-- _sikUiLocked (auditoria de botones, 2026-08-26): aspecto atenuado
		-- del proyecto en vez de la textura gris generica de setEnable.
		self.addMemberBtn._sikUiLocked = not hasOptions
		self.addMemberBtn:setEnable(hasOptions)
		if not hasOptions then
			UI.Controls.setTooltip(self.addMemberBtn, T("IGUI_GS_AdminNoPlayersOnline"))
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
	self._networkBaseY = self._networkBaseY or {}
	if widget and widget.getY then self._networkBaseY[widget] = widget:getY() end
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
	local y = self.headerHeight + 4
	self._networkTabWidgets = {}
	self._networkBaseY = {}
	self._taxonomyTabWidgets = {}

	-- dev22: pestañas del panel de staff (Soporte de redes / Taxonomia) -
	-- controlador pequeño y explicito, 2 botones que alternan visibilidad de
	-- los widgets ya construidos (ver selectStaffTab arriba), nunca
	-- reconstruyen ni destruyen nada.
	local tabW = math.floor((textW - 8) / 2)
	self.staffTabNetworkBtn = createButton(
		pad, y, tabW, BTN_H, T("IGUI_GS_AdminTabNetwork"), function()
			self:selectStaffTab("network")
		end)
	self:addChild(self.staffTabNetworkBtn)
	self.staffTabTaxonomyBtn = createButton(
		pad + tabW + 8, y, tabW, BTN_H, T("IGUI_GS_AdminTabTaxonomy"), function()
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

        self.networkCombo = UI.Controls.combo(self, {
                x = pad, y = y, w = textW, h = ENTRY_H,
                onChange = function() self:onComboChanged() end,
        })
	trackNetworkTabWidget(self, self.networkCombo)
	y = y + ENTRY_H + LINE_GAP + 2

        self.infoLbls = {}
        self._infoStartY = y
        for i = 1, INFO_LINE_COUNT do
                local lbl = UI.Controls.copyText(self, {
                        x = pad, y = y, w = textW, text = "",
                        tone = "text", font = UIFont.Small, lineGap = 2,
                })
                lbl:setVisible(false)
                trackNetworkTabWidget(self, lbl)
		self.infoLbls[i] = lbl
	end
	local infoLineH = FONT_HGT_SMALL + 2
	y = y + INFO_BASE_LINES * infoLineH
	self._infoBaseEndY = y
	y = y + LINE_GAP + 4

	local reloadW = math.floor(textW / 2) - 4
	self.reloadBtn = createButton(
		pad, y, reloadW, BTN_H, T("IGUI_GS_AdminReload"), function()
			self:requestNetworkList()
			if self._selectedNetworkId then self:requestMembers(self._selectedNetworkId) end
		end)
	self:addChild(self.reloadBtn)
	trackNetworkTabWidget(self, self.reloadBtn)

	self.historyBtn = createButton(
		pad + reloadW + 8, y, reloadW, BTN_H, T("IGUI_GS_AdminHistoryButton"), function()
			self:requestHistory()
		end)
	self:addChild(self.historyBtn)
	trackNetworkTabWidget(self, self.historyBtn)
	y = y + BTN_H + LINE_GAP

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
	self.staffActionButtons = {}
	if #staffActions > 0 then
		local toolsTitle = UI.Controls.sectionTitle(self, {
			x = pad, y = y, w = textW, text = T("IGUI_GS_AdminInternalTests"),
		})
		trackNetworkTabWidget(self, toolsTitle)
		y = y + FONT_HGT_SMALL + LINE_GAP

		local actionGap = 8
		local actionW = math.floor((textW - actionGap) / 2)
		local actionMinW = 0
		for i = 1, #staffActions do
			local action = staffActions[i]
			local actionBtn = createButton(
				pad, y, textW, BTN_H, T(action.labelKey),
				staffActionCallback(action, self))
			UI.Controls.fitButtonToContent(actionBtn)
			actionMinW = math.max(actionMinW, actionBtn:getWidth())
			self:addChild(actionBtn)
			trackNetworkTabWidget(self, actionBtn)
			self.staffActionButtons[#self.staffActionButtons + 1] = actionBtn
		end
		local actionColumns = actionW >= actionMinW and 2 or 1
		self._staffActionColumns = actionColumns
		for i = 1, #self.staffActionButtons do
			local column = actionColumns == 2 and ((i - 1) % 2) or 0
			local row = math.floor((i - 1) / actionColumns)
			self.staffActionButtons[i]:setX(pad + column * (actionW + actionGap))
			self.staffActionButtons[i]:setY(y + row * (BTN_H + LINE_GAP))
			self.staffActionButtons[i]:setWidth(actionColumns == 2 and actionW or textW)
		end
		local actionRows = math.ceil(#staffActions / actionColumns)
		y = y + actionRows * (BTN_H + LINE_GAP) + 6
	end

	self.membersTitle = UI.Controls.sectionTitle(self, {
		x = pad, y = y, text = T("IGUI_GS_AdminMembersTitle"),
	})
	trackNetworkTabWidget(self, self.membersTitle)
	y = y + FONT_HGT_SMALL + LINE_GAP

	-- Añadir miembro (pedido explicito 2026-08-22): desplegable de jugadores
	-- CONECTADOS ahora mismo, sin facción - el staff gestiona cualquier red.
	local addBtnW = 90
        self.addMemberCombo = UI.Controls.combo(self, {
                x = pad, y = y, w = textW, h = ENTRY_H,
        })
	trackNetworkTabWidget(self, self.addMemberCombo)
	self.addMemberBtn = createButton(
		pad + textW - addBtnW, y, addBtnW, ENTRY_H, T("IGUI_GS_AdminAddMember"), function()
			self:onAddMember()
		end)
	self:addChild(self.addMemberBtn)
	trackNetworkTabWidget(self, self.addMemberBtn)
	UI.Controls.fitButtonToContent(self.addMemberBtn)
	addBtnW = math.min(textW, math.max(90, self.addMemberBtn:getWidth()))
	self.addMemberCombo:setWidth(math.max(100, textW - addBtnW - 8))
	self.addMemberBtn:setX(pad + textW - addBtnW)
	self.addMemberBtn:setWidth(addBtnW)
	y = y + ENTRY_H + LINE_GAP + 6

	-- Texto de longitud variable SIEMPRE con wrap real (regla del proyecto) -
	-- antes era un ISLabel de una sola linea y se salia/cortaba por el borde
	-- de la ventana (confirmado en pruebas reales).
	local hintLines = UI.Controls.wrapText(T("IGUI_GS_AdminDashboardHint"), textW, UIFont.Small)
	local actionsH = BTN_H + ROW_GAP
	local hintH = (#hintLines * (FONT_HGT_SMALL + 2)) + ROW_GAP
	local memberH = math.max(MIN_VISIBLE_ROWS * (ROW_H + ROW_GAP), self.height - y - actionsH - hintH - pad)
	self.memberScroll = UI.Scroll.create(self, pad, y, textW, memberH)
	UI.Scroll.setOnContentRectChanged(self.memberScroll, function()
		if self._memberRelayout then return end
		self._memberRelayout = true
		self:refreshMemberPanel(self._members)
		self._memberRelayout = false
	end)
	self.memberScrollTopY = y
	trackNetworkTabWidget(self, self.memberScroll)
	local actionsY = y + memberH + ROW_GAP

	self.releaseBtn = createButton(
		pad, actionsY, reloadW, BTN_H, T("IGUI_GS_AdminReleaseOwnership"), function()
			self:onReleaseOwnership()
		end)
	self:addChild(self.releaseBtn)
	trackNetworkTabWidget(self, self.releaseBtn)

	self.deleteBtn = createButton(
		pad + reloadW + 8, actionsY, reloadW, BTN_H, T("IGUI_GS_AdminDeleteNetwork"), function()
			self:onDeleteNetworkConfirm()
		end, true)
	self:addChild(self.deleteBtn)
	trackNetworkTabWidget(self, self.deleteBtn)

	local hintY = actionsY + BTN_H + ROW_GAP
        self.dashboardHintLabels = {}
        for _, line in ipairs(hintLines) do
                local hintLbl = UI.Controls.copyText(self, {
                        x = pad, y = hintY, w = textW, text = line,
                        tone = "textMuted", font = UIFont.Small, lineGap = 2,
                })
                trackNetworkTabWidget(self, hintLbl)
		self.dashboardHintLabels[#self.dashboardHintLabels + 1] = hintLbl
		hintY = hintY + FONT_HGT_SMALL + 2
	end

	-- El bloque de abajo (acciones + hint) puede quedar mas bajo que la
	-- altura fija de la ventana si el scroll de miembros se alargo para
	-- garantizar MIN_VISIBLE_ROWS - crecer la ventana en vez de solapar.
	local neededHeight = hintY + pad
	if neededHeight > self.height then
		self:setHeight(math.min(neededHeight, self.maximumHeight or neededHeight))
	end

	self:refreshInfoLines()
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
        local comboItems = {}
        for i = 1, #self._networks do
                local net = self._networks[i]
                -- net.label ya incluye "(cuenta del propietario)" o "(VACANTE)" y el
                -- id interno, construido en adminListNetworks - no duplicar aqui.
                comboItems[#comboItems + 1] = {
                        text = net.label or net.networkId or "?",
                        value = net.networkId,
                }
                if net.networkId == prevSelectedId then selectedIndex = i end
        end
        self.networkCombo:setItems(comboItems, selectedIndex or 1)
	if #self._networks == 0 then
		self._selectedNetworkId = nil
		self._selectedNetwork = nil
		self:refreshInfoLines()
		self:refreshMemberPanel({})
		return
	end
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
	local sourceLines = {}
	if net then
		sourceLines[#sourceLines + 1] = net.label .. "  [" .. net.networkId .. "]"
		if net.vacant then
			sourceLines[#sourceLines + 1] = T("IGUI_GS_AdminInfoVacant")
		else
			sourceLines[#sourceLines + 1] = T("IGUI_GS_AdminInfoOwner", net.owner or "?")
		end
		sourceLines[#sourceLines + 1] = T("IGUI_GS_AdminInfoAccount", (net.ownerAccountLogin ~= "" and net.ownerAccountLogin) or "?")
		-- BUG REAL COSMETICO cerrado (2026-08-26, hallazgo de Desarrollo -
		-- "N miembros" incluia fichas ROLE_DEAD conservadas a proposito, dando
		-- la impresion de mas gente con acceso real de la que hay): separa
		-- activos de historico en 2 numeros explicitos en vez de sumarlos.
		local deadRecords = math.max(0, (net.memberCount or 0) - (net.activeMemberCount or net.memberCount or 0))
		sourceLines[#sourceLines + 1] = T("IGUI_GS_AdminNetworkCounts",
			net.activeMemberCount or net.memberCount or 0, deadRecords, net.terminalCount or 0)
	end
	local lines = {}
	local textW = math.max(120, self.width - PAD * 2)
	for i = 1, #sourceLines do
		local wrapped = UI.Controls.wrapText(sourceLines[i], textW, UIFont.Small)
		for j = 1, #wrapped do
			if #lines < INFO_LINE_COUNT then lines[#lines + 1] = wrapped[j] end
		end
	end
	local lineH = FONT_HGT_SMALL + 2
	local visibleCount = math.max(1, #lines)
	for i = 1, INFO_LINE_COUNT do
		local label = self.infoLbls[i]
		label:setY((self._infoStartY or label:getY()) + (i - 1) * lineH)
                label:setText(lines[i] or "")
		label:setVisible(lines[i] ~= nil)
	end
	local infoEndY = (self._infoStartY or 0) + visibleCount * lineH
	local delta = infoEndY - (self._infoBaseEndY or infoEndY)
	for i = 1, #(self._networkTabWidgets or {}) do
		local widget = self._networkTabWidgets[i]
		local baseY = self._networkBaseY and self._networkBaseY[widget]
		if widget and baseY and baseY >= (self._infoBaseEndY or 0) then
			widget:setY(baseY + delta)
		end
	end
	if self.memberScroll then
		self.memberScrollTopY = self.memberScroll:getY()
		local hintH = math.max(1, #(self.dashboardHintLabels or {})) * (FONT_HGT_SMALL + 2) + ROW_GAP
		local memberH = math.max(3 * (ROW_H + ROW_GAP),
			self.height - self.memberScrollTopY - BTN_H - hintH - PAD - ROW_GAP)
		UI.Scroll.resize(self.memberScroll,
			math.max(120, self.width - PAD * 2), memberH)
		local actionsY = self.memberScrollTopY + memberH + ROW_GAP
		local textW = math.max(120, self.width - PAD * 2)
		local halfW = math.floor((textW - 8) / 2)
		if self.releaseBtn then self.releaseBtn:setY(actionsY); self.releaseBtn:setWidth(halfW) end
		if self.deleteBtn then
			self.deleteBtn:setX(PAD + halfW + 8)
			self.deleteBtn:setY(actionsY)
			self.deleteBtn:setWidth(halfW)
		end
		local hintY = actionsY + BTN_H + ROW_GAP
		for i = 1, #(self.dashboardHintLabels or {}) do
			self.dashboardHintLabels[i]:setY(hintY)
			hintY = hintY + FONT_HGT_SMALL + 2
		end
	end
end

---@param members table[]
function GS_AdminDashboardUI:refreshMemberPanel(members)
	self._members = members or {}
	self:refreshOnlinePlayersCombo()
	local scroll = self.memberScroll
	if not scroll then return end
	local w = UI.Scroll.contentWidth(scroll)
	local tableHeight = math.max(ROW_H + TABLE_METRICS.headerHeight + 48, scroll.height or 0)
	if not self.memberTableBlock or self.memberTableBlock.disposed then
		local dashboard = self
		local frame, frameReason = UI.Block.create({
			parent = UI.Scroll.childHost(scroll), x = 0, y = 0, w = w, h = tableHeight,
			title = T("IGUI_GS_AdminMembersTitle"),
			tooltip = T("IGUI_GS_AdminMembersTitle"),
		})
		if not frame then error("SiK.UI.Block.create(staff.members): " .. tostring(frameReason)) end
		self.memberTableFrame = frame
		local content = frame:getContentRect()
		local tableInstance, reason = UI.Table.create({
			parent = frame.childParent, embedded = true,
			x = content.x, y = content.y, w = content.w,
			h = content.h,
			emptyText = T("IGUI_GS_AdminNoMembers"),
			columns = ADMIN_MEMBER_TABLE_COLUMNS,
			left = ADMIN_MEMBER_TABLE_OPTIONS.left,
			right = ADMIN_MEMBER_TABLE_OPTIONS.right,
			onRowClick = function(context)
				local member = context.item
				if not member then return false end
				GlobalStorageSiK.AdminDashboard.openMemberEditor(dashboard, member)
				return true
			end,
		})
		if not tableInstance then
			frame:dispose()
			self.memberTableFrame = nil
			error("SiK.UI.Table.create(staff.members): " .. tostring(reason))
		end
		self.memberTableBlock = tableInstance
	end
	self.memberTableFrame:setBounds(0, 0, w, tableHeight)
	local content = self.memberTableFrame:getContentRect()
	self.memberTableBlock:layout({
		x = content.x, y = content.y, w = content.w, h = content.h,
		rows = self._members, preserveOffset = true,
	})
	UI.Scroll.setContentHeight(scroll, self.memberTableFrame.h)
	UI.Scroll.ensureScrollBars(scroll)
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
		if player then
			GlobalStorageSiK.UIFeedback.halo(player, T("IGUI_GS_AdminNoNetworkSelected"),
				220, 180, 100, 300, { tone = "warning" })
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
		if player then
			GlobalStorageSiK.UIFeedback.halo(player, T("IGUI_GS_AdminNoNetworkSelected"),
				220, 180, 100, 300, { tone = "warning" })
		end
		return
	end
	local networkId = self._selectedNetworkId
	local dashboard = self
	Confirmation.show({
		owner = self,
		title = T("IGUI_GS_AdminDeleteNetwork"),
		question = T("IGUI_GS_AdminDeleteNetworkQuestion", networkId),
		consequences = T("IGUI_GS_AdminDeleteNetworkConsequences"),
		playerNum = self.playerNum or 0,
		onAccept = function()
			if GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.sendCommand then
				GlobalStorageSiK.NetClient.sendCommand("adminDeleteNetwork", { networkId = networkId, confirm = true })
			end
			dashboard._selectedNetworkId = nil
			dashboard._selectedNetwork = nil
		end,
	})
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
	local player = GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer
		and GlobalStorageSiK.NetClient.getPlayer() or nil
	local playerNum = player and player.getPlayerNum and player:getPlayerNum() or 0
	local rect = UI.Window.resolveBounds({
		profile = "staff", width = WINDOW_W, height = WINDOW_H,
		playerNum = playerNum, minWidth = ADMIN_MIN_W, minHeight = ADMIN_MIN_H,
	})
	local ui = GS_AdminDashboardUI:new(rect.x, rect.y, rect.w, rect.h)
	ui.playerNum = playerNum
	ui:initialise()
	ui:show()
	GlobalStorageSiK.AdminDashboard.instance = ui
	requestLatestTaxonomySummaries()
end
