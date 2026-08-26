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
	local name = m.displayName or m.name or "?"
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

function GS_AdminHistoryUI:initialise()
	ISPanel.initialise(self)
	self.backgroundColor = { r = 0.06, g = 0.06, b = 0.06, a = 0.98 }
	self.borderColor = { r = 0.55, g = 0.3, b = 0.2, a = 0.95 }
	self:setAlwaysOnTop(true)
	self.headerHeight = FONT_HGT_MEDIUM + PAD + LINE_GAP
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
	self.eventScroll = GlobalStorageSiK.TerminalScroll.create(
		self, PAD, scrollY, self.width - PAD * 2, self.height - scrollY - PAD)
	self:refreshEvents()
	GlobalStorageSiK.SiK_UI.centerModal(self)
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
function GlobalStorageSiK.AdminDashboard.showHistory(events, networkLabel)
	if GlobalStorageSiK.AdminDashboard.historyInstance then
		GlobalStorageSiK.AdminDashboard.historyInstance:destroy()
	end
	local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
	local w, h = math.min(520, sw - 60), math.min(560, sh - 60)
	local ui = GS_AdminHistoryUI:new((sw - w) / 2, (sh - h) / 2, w, h)
	ui.events = events or {}
	ui.networkLabel = networkLabel or ""
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

	local title = ISLabel:new(pad, y, FONT_HGT_MEDIUM, T("IGUI_GS_AdminMemberEditorTitle"),
		0.95, 0.95, 0.95, 1, UIFont.Medium, true)
	title:initialise()
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

function GS_AdminDashboardUI:initialise()
	ISPanel.initialise(self)
	self.backgroundColor = { r = 0.05, g = 0.05, b = 0.05, a = 0.98 }
	self.borderColor = { r = 0.55, g = 0.3, b = 0.2, a = 0.95 }
	self:setAlwaysOnTop(true)
	self.headerHeight = FONT_HGT_MEDIUM + PAD + LINE_GAP
	GlobalStorageSiK.SiK_UI.setupModalPanel(self, function()
		self:destroy()
	end, PAD)
	self:buildStaticFrame()
	self:requestNetworkList()
	self:requestOnlinePlayers()
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
		self.addMemberBtn:setEnable(#self._addMemberOptions > 0)
	end
end

--- Todo lo fijo de la ventana: combo de red (arriba, como el resto de
--- selectores de red del mod - ver GS_TerminalInstallReaderChoice.lua),
--- bloque de info envuelta (nunca texto truncado a una linea, regla del
--- proyecto para texto de longitud variable), lista de miembros con scroll,
--- y la barra de acciones de red. Se llama UNA vez; lo que cambia con los
--- datos vive dentro de cada refresh*.
function GS_AdminDashboardUI:buildStaticFrame()
	local pad = PAD
	local textW = self.width - pad * 2
	local y = pad

	local title = ISLabel:new(pad, y, FONT_HGT_MEDIUM, T("IGUI_GS_AdminDashboardTitle"),
		0.95, 0.75, 0.6, 1, UIFont.Medium, true)
	title:initialise()
	self:addChild(title)
	y = self.headerHeight + 4

	self.networkCombo = ISComboBox:new(pad, y, textW, ENTRY_H, self, nil)
	self.networkCombo:initialise()
	GlobalStorageSiK.SiK_UI.styleComboBox(self.networkCombo)
	self.networkCombo.onChange = function() self:onComboChanged() end
	self:addChild(self.networkCombo)
	y = y + ENTRY_H + LINE_GAP + 2

	self.infoLbls = {}
	for i = 1, INFO_LINE_COUNT do
		local lbl = ISLabel:new(pad, y, FONT_HGT_SMALL, "", 0.78, 0.82, 0.88, 1, UIFont.Small, true)
		lbl:initialise()
		self:addChild(lbl)
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

	self.historyBtn = GlobalStorageSiK.SiK_UI.createButton(
		pad + reloadW + 8, y, reloadW, BTN_H, T("IGUI_GS_AdminHistoryButton"), self, function()
			self:requestHistory()
		end)
	self:addChild(self.historyBtn)
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
	y = y + BTN_H + LINE_GAP + 6

	-- Herramientas internas aportadas por los addons. El Dashboard solo pinta
	-- el registro neutral; cada addon conserva la responsabilidad de abrir su
	-- ruta vanilla y de decidir como se integra con una sesion de red activa.
	local staffActions = GlobalStorageSiK.TerminalExtensions.getStaffActions()
	if #staffActions > 0 then
		local toolsTitle = GlobalStorageSiK.SiK_UI.createSectionLabel(pad, y, T("IGUI_GS_AdminInternalTests"))
		self:addChild(toolsTitle)
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
		end
		local actionRows = math.ceil(#staffActions / 2)
		y = y + actionRows * (BTN_H + LINE_GAP) + 6
	end

	self.membersTitle = ISLabel:new(pad, y, FONT_HGT_SMALL, T("IGUI_GS_AdminMembersTitle"),
		0.7, 0.72, 0.76, 1, UIFont.Small, true)
	self.membersTitle:initialise()
	self:addChild(self.membersTitle)
	y = y + FONT_HGT_SMALL + LINE_GAP

	-- Añadir miembro (pedido explicito 2026-08-22): desplegable de jugadores
	-- CONECTADOS ahora mismo, sin facción - el staff gestiona cualquier red.
	local addBtnW = 90
	self.addMemberCombo = ISComboBox:new(pad, y, textW - addBtnW - 8, ENTRY_H, self, nil)
	self.addMemberCombo:initialise()
	GlobalStorageSiK.SiK_UI.styleComboBox(self.addMemberCombo)
	self:addChild(self.addMemberCombo)
	self.addMemberBtn = GlobalStorageSiK.SiK_UI.createButton(
		pad + textW - addBtnW, y, addBtnW, ENTRY_H, T("IGUI_GS_AdminAddMember"), self, function()
			self:onAddMember()
		end)
	self:addChild(self.addMemberBtn)
	y = y + ENTRY_H + LINE_GAP + 6

	-- Texto de longitud variable SIEMPRE con wrap real (regla del proyecto) -
	-- antes era un ISLabel de una sola linea y se salia/cortaba por el borde
	-- de la ventana (confirmado en pruebas reales).
	local hintLines = GlobalStorageSiK.SiK_UI.wrapTextLines(T("IGUI_GS_AdminDashboardHint"), textW, UIFont.Small)
	local actionsH = BTN_H + ROW_GAP
	local hintH = (#hintLines * (FONT_HGT_SMALL + 2)) + ROW_GAP
	local memberH = math.max(MIN_VISIBLE_ROWS * (ROW_H + ROW_GAP), self.height - y - actionsH - hintH - pad)
	self.memberScroll = GlobalStorageSiK.TerminalScroll.create(self, pad, y, textW, memberH)
	local actionsY = y + memberH + ROW_GAP

	self.releaseBtn = GlobalStorageSiK.SiK_UI.createButton(
		pad, actionsY, reloadW, BTN_H, T("IGUI_GS_AdminReleaseOwnership"), self, function()
			self:onReleaseOwnership()
		end)
	self:addChild(self.releaseBtn)

	self.deleteBtn = GlobalStorageSiK.SiK_UI.createButton(
		pad + reloadW + 8, actionsY, reloadW, BTN_H, T("IGUI_GS_AdminDeleteNetwork"), self, function()
			self:onDeleteNetworkConfirm()
		end)
	GlobalStorageSiK.SiK_UI.applyDangerButton(self.deleteBtn)
	self:addChild(self.deleteBtn)

	local hintY = actionsY + BTN_H + ROW_GAP
	for _, line in ipairs(hintLines) do
		local hintLbl = ISLabel:new(pad, hintY, FONT_HGT_SMALL, line, 0.55, 0.57, 0.6, 1, UIFont.Small, true)
		hintLbl:initialise()
		self:addChild(hintLbl)
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
		lines[#lines + 1] = T("IGUI_GS_AdminNetworkCounts", net.memberCount or 0, net.terminalCount or 0)
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

function GS_AdminDashboardUI:onReleaseOwnership()
	if not self._selectedNetworkId then return end
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
	if not self._selectedNetworkId then return end
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
		GlobalStorageSiK.AdminDashboard.showHistory(events, label)
	end
end

---@param args table|nil
function GlobalStorageSiK.AdminDashboard.onActionResult(args)
	local ui = GlobalStorageSiK.AdminDashboard.instance
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

--- Abre (o trae al frente) el panel. Solo se llama desde un punto ya gateado
--- por isServerStaff en el CLIENTE (icono lateral) - la autorizacion real
--- vuelve a comprobarse en servidor en cada comando, esto es solo UX.
function GlobalStorageSiK.AdminDashboard.show()
	if GlobalStorageSiK.AdminDashboard.instance then
		GlobalStorageSiK.AdminDashboard.instance:setVisible(true)
		GlobalStorageSiK.AdminDashboard.instance:bringToTop()
		GlobalStorageSiK.AdminDashboard.instance:requestNetworkList()
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
end
