--[[
	GlobalStorageSiK - Permisos de red (bloque en pestaña Red)
	Autor: SiK
	Fecha: 2025-06-27
	Descripción: Tabla de miembros (sin scroll) + añadir acceso; transferencia en menú contextual.
]]

require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISLabel"
require "ISUI/ISComboBox"
require "GS_I18n"
require "GS_Permissions"
require "GS_NetClient"
require "GS_TerminalUI_Scroll"
require "GS_TerminalUI_Chrome"
require "GS_UILayout"
require "GS_TerminalUI_MemberEditor"

GlobalStorageSiK.TerminalPermissions = {}

local T = GlobalStorageSiK.I18n.text
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local ROW_H = FONT_HGT_SMALL + 10
local HEADER_H = FONT_HGT_SMALL + 8
local ENTRY_H = FONT_HGT_SMALL + 6
local ROW_GAP = 6
local BLOCK_GAP = 10
local TAG_MEMBER_ROW = "_gsNetMemberRow"
local POOL = 4
local COL_ROLE_X = 4
-- Ancho suficiente para el rol mas largo ("Propietario"/"Owner" y
-- equivalentes en los 9 idiomas) sin truncar - medido en vez de fijo a
-- ciegas, igual criterio que la tabla de "Gestion de terminales".
local COL_ROLE_W = math.max(
	getTextManager():MeasureStringX(UIFont.Small, GlobalStorageSiK.I18n.text("IGUI_GS_PermRoleOwner")),
	getTextManager():MeasureStringX(UIFont.Small, GlobalStorageSiK.I18n.text("IGUI_GS_PermRoleAdmin")),
	getTextManager():MeasureStringX(UIFont.Small, GlobalStorageSiK.I18n.text("IGUI_GS_PermRoleMember")),
	getTextManager():MeasureStringX(UIFont.Small, GlobalStorageSiK.I18n.text("IGUI_GS_PermRoleFaction"))
) + 14
local COL_NAME_X = COL_ROLE_X + COL_ROLE_W + 12
local ADD_W = 72
-- v20: fila de miembro simplificada (sin botones "Quitar"/"Roles" inline) -
-- un clic en la fila abre GS_TerminalUI_MemberEditor.lua, igual patron que
-- la tabla de "Gestion de terminales" (clic en fila -> ventana modal con
-- TODAS las acciones validadas por permiso, desplegable de rol incluido).
local PERM_UI_VERSION = 20

local function truncate(text, maxW)
	return GlobalStorageSiK.TerminalChrome.truncateText(text, maxW, UIFont.Small)
end

local function createRowButton(x, y, w, h, title, target, onClick)
	return GlobalStorageSiK.TerminalChrome.createNeatButton(x, y, w, h, title, target, onClick)
end

---@param kind string|nil owner|admin|user|faction
---@return string
local function memberRoleLabel(kind)
	if kind == "owner" then
		return T("IGUI_GS_PermRoleOwner")
	end
	if kind == "admin" then
		return T("IGUI_GS_PermRoleAdmin")
	end
	if kind == "faction" then
		return T("IGUI_GS_PermRoleFaction")
	end
	return T("IGUI_GS_PermRoleMember")
end

--- Indica si mostrar bloque de permisos.
---@return boolean
function GlobalStorageSiK.TerminalPermissions.shouldShowTab()
	return GlobalStorageSiK.isMultiplayerActive()
end

--- Recopila nombres de personajes conectados.
---@return string[]
function GlobalStorageSiK.TerminalPermissions.collectOnlineCharacters()
	local names = {}
	local seen = {}
	if getActivePlayers then
		local ok, players = pcall(getActivePlayers)
		if ok and players and players.size then
			for i = 0, players:size() - 1 do
				local p = players:get(i)
				if p then
					local charName = GlobalStorageSiK.Permissions.getCharacterName(p)
					if charName ~= "" and not seen[charName] then
						seen[charName] = true
						names[#names + 1] = charName
					end
				end
			end
		end
	end
	table.sort(names)
	return names
end

--- Opciones del desplegable de facción (miembros + toda la facción).
---@return table[] { kind, value, label }
function GlobalStorageSiK.TerminalPermissions.collectFactionPickerOptions()
	local options = {}
	local player = GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer and GlobalStorageSiK.NetClient.getPlayer()
	if not player then
		return options
	end
	local faction = GlobalStorageSiK.Permissions.getPlayerFaction(player)
	if not faction or not faction.getName then
		return options
	end
	local fname = faction:getName() or ""
	if fname == "" then
		return options
	end
	options[#options + 1] = {
		kind = "whole",
		value = fname,
		label = T("IGUI_GS_PermPickWholeFaction", fname),
	}
	local seen = {}
	local function addMember(charName)
		charName = charName and string.gsub(charName, "^%s*(.-)%s*$", "%1") or ""
		if charName == "" or seen[charName] then
			return
		end
		seen[charName] = true
		options[#options + 1] = {
			kind = "member",
			value = charName,
			label = T("IGUI_GS_PermPickFactionMember", charName),
		}
	end
	if faction.getPlayers then
		local ok, players = pcall(function()
			return faction:getPlayers()
		end)
		if ok and players then
			if players.size then
				for i = 0, players:size() - 1 do
					local uname = players:get(i)
					addMember(GlobalStorageSiK.Permissions.resolveCharacterName(uname))
				end
			elseif type(players) == "table" then
				for i = 1, #players do
					addMember(GlobalStorageSiK.Permissions.resolveCharacterName(players[i]))
				end
			end
		end
	end
	if getActivePlayers then
		local ok, players = pcall(getActivePlayers)
		if ok and players and players.size then
			for i = 0, players:size() - 1 do
				local p = players:get(i)
				if p and p.getUsername and GlobalStorageSiK.Permissions.sameFaction(p:getUsername(), player:getUsername()) then
					addMember(GlobalStorageSiK.Permissions.getCharacterName(p))
				end
			end
		end
	end
	return options
end

---@param ui table
---@param widget any
local function trackPermWidget(ui, widget)
	if widget then
		ui.permWidgets[#ui.permWidgets + 1] = widget
	end
end

---@param scroll ISPanel
---@param ui table
---@param widget any
local function addPermWidget(scroll, ui, widget)
	GlobalStorageSiK.TerminalScroll.addChild(scroll, widget)
	trackPermWidget(ui, widget)
end

---@param ui table
---@return table|nil { kind, value }
local function resolveMemberPick(ui)
	if not ui.memberPickCombo or not ui._memberPickMeta then return nil end
	local idx = ui.memberPickCombo.selected or 1
	local meta = ui._memberPickMeta[idx]
	if not meta or meta.kind == "none" or meta.kind == "header" then return nil end
	return meta
end

---@param perms table|nil
---@return boolean
local function viewerIsOwner(perms, state)
	local player = GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer and GlobalStorageSiK.NetClient.getPlayer()
	if not player or not GlobalStorageSiK.Permissions or not GlobalStorageSiK.Permissions.isOwnerPlayer then
		return false
	end
	local networkId = state and state.networkId
		or (GlobalStorageSiK.Client and GlobalStorageSiK.Client.activeNetworkId)
		or GlobalStorageSiK.Network.getDefaultNetworkId()
	return GlobalStorageSiK.Permissions.isOwnerPlayer(player, networkId)
end

---@param perms table|nil
---@return table[]
local function buildMemberRows(perms)
	perms = perms or {}
	local rows = {}
	local owner = perms.owner
	local adminSet = {}
	for i = 1, #(perms.adminUsers or {}) do
		adminSet[perms.adminUsers[i]] = true
	end
	if owner and owner ~= "" then
		rows[#rows + 1] = { kind = "owner", name = owner }
	end
	local users = perms.allowedUsers or {}
	for i = 1, #users do
		local charName = users[i]
		if charName and charName ~= "" and charName ~= owner then
			local kind = adminSet[charName] and "admin" or "user"
			rows[#rows + 1] = { kind = kind, name = charName }
		end
	end
	local factions = perms.allowedFactions or {}
	for i = 1, #factions do
		local fname = factions[i]
		if fname and fname ~= "" then
			rows[#rows + 1] = { kind = "faction", name = fname }
		end
	end
	return rows
end

--- Rol con color indicativo.
---@param kind string
---@return number r, number g, number b
local function roleColor(kind)
	local pal = GlobalStorageSiK.TerminalChrome.PALETTE
	if kind == "owner" then
		return pal.accent[1], pal.accent[2], pal.accent[3]
	elseif kind == "admin" then
		return pal.statusWarn[1], pal.statusWarn[2], pal.statusWarn[3]
	end
	return pal.textMuted[1], pal.textMuted[2], pal.textMuted[3]
end

--- Crea fila de tabla de miembros: clic en la fila abre el editor modal
--- completo (GS_TerminalUI_MemberEditor.lua) con TODAS las acciones
--- validadas por permiso - mismo patron que "Gestion de terminales", ya no
--- hay botones inline por fila (ni menu contextual aparte).
---@param host ISPanel
---@param terminal GS_TerminalUI
---@param ui table
---@return ISPanel
local function createMemberRow(host, terminal, ui)
	local row = ISPanel:new(0, 0, 200, ROW_H)
	row:initialise()
	row[TAG_MEMBER_ROW] = true
	row.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
	row.borderColor = { r = 0, g = 0, b = 0, a = 0 }

	row.prerender = function(self)
		ISPanel.prerender(self)
		local data = self.memberData
		if not data then return end
		GlobalStorageSiK.TerminalChrome.drawTableRowBackground(self, self.rowIndex, self:isMouseOver(), false)
		local yMid = math.floor((self.height - FONT_HGT_SMALL) / 2)
		local pal = GlobalStorageSiK.TerminalChrome.PALETTE
		local rr, rg, rb = roleColor(data.kind)
		local nameMaxW = math.max(40, self.width - COL_NAME_X - 4)
		self:drawText(truncate(memberRoleLabel(data.kind), COL_ROLE_W), COL_ROLE_X, yMid,
			rr, rg, rb, 1, UIFont.Small)
		self:drawText(truncate(data.name or "?", nameMaxW), COL_NAME_X, yMid,
			pal.textPrimary[1], pal.textPrimary[2], pal.textPrimary[3], 1, UIFont.Small)
	end
	row.onMouseDown = function(self, x, y)
		if self.memberData and self.memberData.kind ~= "empty" then return true end
		return false
	end
	row.onMouseUp = function(self, x, y)
		local data = self.memberData
		if not data or data.kind == "empty" or not terminal then
			return false
		end
		local perms = (ui._permStateRef and ui._permStateRef.permissions) or {}
		GlobalStorageSiK.TerminalMemberEditor.open(terminal, data, perms.playerRole or "member")
		return true
	end
	row.terminal = terminal
	row.uiRef = ui
	return row
end

--- Posiciona todas las filas de miembros (sin scroll interno).
---@param ui table
function GlobalStorageSiK.TerminalPermissions.layoutMemberRows(ui)
	local rows = ui and ui.memberRows
	local host = ui and ui.permTableHost
	if not host or not rows or not ui.memberRowPool then
		return
	end
	local tableW = host.width or 200
	local needed = math.max(1, #rows)
	local term = ui.terminalRef
	while #ui.memberRowPool < needed do
		local row = createMemberRow(host, term, ui)
		row:setVisible(false)
		host:addChild(row)
		ui.memberRowPool[#ui.memberRowPool + 1] = row
	end
	for i = 1, #ui.memberRowPool do
		local row = ui.memberRowPool[i]
		if i <= #rows then
			row.memberData = rows[i]
			row.rowIndex = i
			row.stateRef = ui._permStateRef
			row:setX(0)
			row:setY(HEADER_H + 2 + (i - 1) * ROW_H)
			row:setWidth(tableW)
			row:setHeight(ROW_H)
			row:setVisible(true)
		else
			row.memberData = nil
			row:setVisible(false)
		end
	end
	if #rows == 0 then
		for i = 1, #ui.memberRowPool do
			local row = ui.memberRowPool[i]
			row.memberData = { kind = "empty", name = T("IGUI_GS_NoPermAccess") }
			row.rowIndex = 1
			row:setX(0)
			row:setY(HEADER_H + 2)
			row:setWidth(tableW)
			row:setHeight(ROW_H)
			row:setVisible(i == 1)
		end
		needed = 1
	end
	local bodyH = math.max(ROW_H, needed * ROW_H)
	host:setHeight(HEADER_H + 2 + bodyH + 8)
end

---@param ui table
--- Rellena el combo unificado con grupos: Facción y Servidor.
---@param ui table
function GlobalStorageSiK.TerminalPermissions.refreshMemberPickCombo(ui)
	if not ui or not ui.memberPickCombo then return end
	local selected = ui.memberPickCombo.selected or 1
	ui.memberPickCombo:clear()
	ui._memberPickMeta = {}

	ui._memberPickMeta[1] = { kind = "none" }
	ui.memberPickCombo:addOption(T("IGUI_GS_PickMember"))

	-- Grupo: facción del jugador
	local factionOptions = GlobalStorageSiK.TerminalPermissions.collectFactionPickerOptions()
	if #factionOptions > 0 then
		ui._memberPickMeta[#ui._memberPickMeta + 1] = { kind = "header" }
		ui.memberPickCombo:addOption("[ " .. T("IGUI_GS_PickGroupFaction") .. " ]")
		for i = 1, #factionOptions do
			ui._memberPickMeta[#ui._memberPickMeta + 1] = factionOptions[i]
			ui.memberPickCombo:addOption("  " .. factionOptions[i].label)
		end
	end

	-- Grupo: todos los jugadores online del servidor. Si no hay nadie
	-- conectado en MP/Host, el grupo se muestra igualmente como cabecera no
	-- seleccionable con el motivo inline (antes era una etiqueta aparte
	-- debajo del titulo, que en ventanas estrechas se salia del panel) -
	-- nunca aparece en SP real (isMultiplayerActive() ya oculta toda la
	-- pestaña en ese caso).
	local serverNames = GlobalStorageSiK.TerminalPermissions.collectOnlineCharacters()
	if #serverNames > 0 then
		ui._memberPickMeta[#ui._memberPickMeta + 1] = { kind = "header" }
		ui.memberPickCombo:addOption("[ " .. T("IGUI_GS_PickGroupServer") .. " ]")
		for i = 1, #serverNames do
			ui._memberPickMeta[#ui._memberPickMeta + 1] = { kind = "player", value = serverNames[i], label = serverNames[i] }
			ui.memberPickCombo:addOption("  " .. serverNames[i])
		end
	elseif GlobalStorageSiK.isMultiplayerActive() then
		ui._memberPickMeta[#ui._memberPickMeta + 1] = { kind = "header" }
		ui.memberPickCombo:addOption("[ " .. T("IGUI_GS_PickGroupServerEmpty") .. " ]")
	end

	ui.memberPickCombo.selected = math.min(selected, math.max(1, #ui._memberPickMeta))
end

-- Compatibilidad con llamadas antiguas
function GlobalStorageSiK.TerminalPermissions.refreshOnlineCombo(ui)
	GlobalStorageSiK.TerminalPermissions.refreshMemberPickCombo(ui)
end
function GlobalStorageSiK.TerminalPermissions.refreshFactionCombo(ui)
	-- Vacío: fusionado en refreshMemberPickCombo
end

--- Reposiciona bloque «añadir acceso» tras la tabla de miembros.
---@param scroll ISPanel
---@param ui table
---@param y number
---@return number endY
local function repositionAddBlock(scroll, ui, y)
	local pad = 8
	local titleH = FONT_HGT_SMALL + ROW_GAP
	local rowW = ui._permRowW or 200
	local comboW = rowW - ADD_W - ROW_GAP
	local showAdd = ui.addBlockTitle and ui.addBlockTitle.visible

	if showAdd then
		if ui.addBlockTitle then
			GlobalStorageSiK.TerminalScroll.setContentY(scroll, ui.addBlockTitle, y)
		end
		y = y + titleH
		if ui.memberPickCombo then
			GlobalStorageSiK.TerminalScroll.setContentY(scroll, ui.memberPickCombo, y)
			ui.memberPickCombo:setWidth(comboW)
		end
		if ui.addMemberBtn then
			GlobalStorageSiK.TerminalScroll.setContentY(scroll, ui.addMemberBtn, y)
			GlobalStorageSiK.TerminalScroll.setContentX(scroll, ui.addMemberBtn, pad + comboW + ROW_GAP)
		end
		y = y + ENTRY_H + ROW_GAP
	end
	ui.permEndY = y
	return y
end

--- Construye bloque de permisos (widgets fijos).
---@param scroll ISPanel
---@param terminal GS_TerminalUI
---@param ui table
---@param startY number
function GlobalStorageSiK.TerminalPermissions.buildInNetworkScroll(scroll, terminal, ui, startY)
	local pad = 8
	local y = startY + 8
	local baseY = y
	local innerW = GlobalStorageSiK.TerminalScroll.contentWidth(scroll)
	local titleH = FONT_HGT_SMALL + ROW_GAP
	local rowW = innerW - pad * 2
	local comboW = rowW - ADD_W - ROW_GAP

	ui.permsStartY = y
	ui.permsBuilt = true
	ui.permUiVersion = PERM_UI_VERSION
	ui.permWidgets = ui.permWidgets or {}
	ui.lastPermFingerprint = ""
	ui._permRowW = rowW
	ui.terminalRef = terminal

	local _ppal = GlobalStorageSiK.TerminalChrome.PALETTE
	ui.secLbl = ISLabel:new(pad, y, FONT_HGT_SMALL, T("IGUI_GS_PermSectionTitle"), _ppal.textPrimary[1], _ppal.textPrimary[2], _ppal.textPrimary[3], 1, UIFont.Small, true)
	ui.secLbl:initialise()
	addPermWidget(scroll, ui, ui.secLbl)
	y = y + titleH

	ui.accessTableTitle = ISLabel:new(pad, y, FONT_HGT_SMALL, T("IGUI_GS_PermMembersTableTitle"), _ppal.textPrimary[1], _ppal.textPrimary[2], _ppal.textPrimary[3], 1, UIFont.Small, true)
	ui.accessTableTitle:initialise()
	addPermWidget(scroll, ui, ui.accessTableTitle)
	y = y + titleH

	ui.permTableY = y
	ui.permTableHost = ISPanel:new(pad, y, rowW, HEADER_H + ROW_H + 10)
	ui.permTableHost:initialise()
	ui.permTableHost.drawBackground = false
	ui.permTableHost.clipChildren = true
	ui.permTableHost.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
	ui.permTableHost.borderColor = { r = 0, g = 0, b = 0, a = 0 }
	addPermWidget(scroll, ui, ui.permTableHost)

	ui.permTableHeader = ISPanel:new(0, 0, rowW, HEADER_H)
	ui.permTableHeader:initialise()
	ui.permTableHeader.prerender = function(self)
		ISPanel.prerender(self)
		GlobalStorageSiK.TerminalChrome.drawTableHeaderLine(self)
		local pal = GlobalStorageSiK.TerminalChrome.PALETTE
		self:drawText(T("IGUI_GS_PermColRole"), COL_ROLE_X, 2,
			pal.textSecondary[1], pal.textSecondary[2], pal.textSecondary[3], 1, UIFont.Small)
		self:drawText(T("IGUI_GS_PermColMemberName"), COL_NAME_X, 2,
			pal.textSecondary[1], pal.textSecondary[2], pal.textSecondary[3], 1, UIFont.Small)
		local actionsLabel = T("IGUI_GS_PermColActions")
		local tw = getTextManager():MeasureStringX(UIFont.Small, actionsLabel)
		local ax = math.max(COL_NAME_X + 40, self.width - 2 - tw)
		self:drawText(actionsLabel, ax, 2,
			pal.textSecondary[1], pal.textSecondary[2], pal.textSecondary[3], 1, UIFont.Small)
	end
	ui.permTableHost:addChild(ui.permTableHeader)

	ui.memberRowPool = {}
	for i = 1, POOL do
		local row = createMemberRow(ui.permTableHost, terminal, ui)
		row:setVisible(false)
		ui.permTableHost:addChild(row)
		ui.memberRowPool[i] = row
	end

	y = y + ui.permTableHost:getHeight() + BLOCK_GAP
	ui.permAccessListStartY = ui.permTableY

	-- Avisos de sucesion de propietario (solo visibles para el owner, ver
	-- syncPermsData): explica que pasa al morir para que el jugador conozca
	-- el riesgo, en vez de descubrirlo tras perder acceso.
	ui.successionHintLbl = GlobalStorageSiK.TerminalChrome.createHintLabel(pad, y, T("IGUI_GS_PermSuccessionHint"))
	addPermWidget(scroll, ui, ui.successionHintLbl)
	y = y + FONT_HGT_SMALL + ROW_GAP

	ui.noBackupWarnLbl = ISLabel:new(pad, y, FONT_HGT_SMALL, T("IGUI_GS_PermNoBackupWarn"),
		_ppal.statusWarn[1], _ppal.statusWarn[2], _ppal.statusWarn[3], 1, UIFont.Small, true)
	ui.noBackupWarnLbl:initialise()
	addPermWidget(scroll, ui, ui.noBackupWarnLbl)
	y = y + FONT_HGT_SMALL + BLOCK_GAP

	ui.addBlockTitle = ISLabel:new(pad, y, FONT_HGT_SMALL, T("IGUI_GS_PermAddBlockTitle"), _ppal.textPrimary[1], _ppal.textPrimary[2], _ppal.textPrimary[3], 1, UIFont.Small, true)
	ui.addBlockTitle:initialise()
	addPermWidget(scroll, ui, ui.addBlockTitle)

	-- El motivo de "nadie conectado" ahora vive DENTRO del combo (cabecera
	-- no seleccionable, ver refreshMemberPickCombo) en vez de una etiqueta
	-- aparte: menos texto suelto que se puede salir del panel, y no hace
	-- falta duplicar la explicacion en dos sitios distintos.
	--
	-- Nada de marco "obligatorio" alrededor del picker+boton: el jugador
	-- puede legitimamente no querer añadir a nadie todavia, no es un paso
	-- forzoso. El unico feedback al pulsar "Añadir" sin seleccion es el
	-- aviso breve de abajo (evita el fallo silencioso original).
	ui.memberPickCombo = ISComboBox:new(pad, y, comboW, ENTRY_H, scroll, nil)
	ui.memberPickCombo:initialise()
	GlobalStorageSiK.TerminalChrome.styleComboBox(ui.memberPickCombo)
	addPermWidget(scroll, ui, ui.memberPickCombo)
	ui.addMemberBtn = createRowButton(pad + comboW + ROW_GAP, y, 200, ENTRY_H, T("IGUI_GS_AddMember"), scroll, function()
		local pick = resolveMemberPick(ui)
		if not pick then
			GlobalStorageSiK.TerminalPermissions.flashPickWarning(ui)
			return
		end
		if pick.kind == "whole" then
			terminal:onAddPermissionFaction(pick.value)
		else
			terminal:onAddPermissionUser(pick.value)
		end
	end)
	addPermWidget(scroll, ui, ui.addMemberBtn)

	-- Aviso transitorio cuando se pulsa "Añadir" sin nada seleccionado en el
	-- combo (antes fallaba en silencio - resolveMemberPick devolvia nil y el
	-- boton no hacia nada visible). Se auto-oculta comprobando el timestamp
	-- en su propio render, sin necesitar un tick externo. Texto neutro (no
	-- "primero...") - el combo ya deja claro que hay que elegir algo.
	local pal = GlobalStorageSiK.TerminalChrome.PALETTE
	ui.addMemberWarnLbl = ISLabel:new(pad, y + ENTRY_H + 2, FONT_HGT_SMALL, T("IGUI_GS_PermPickNone"),
		pal.statusWarn[1], pal.statusWarn[2], pal.statusWarn[3], 1, UIFont.Small, true)
	ui.addMemberWarnLbl:initialise()
	ui.addMemberWarnLbl:setVisible(false)
	ui.addMemberWarnLbl.render = function(self)
		if ui._addMemberWarnUntil and getTimestampMs() > ui._addMemberWarnUntil then
			self:setVisible(false)
			ui._addMemberWarnUntil = nil
		end
		if self:isVisible() then
			ISLabel.render(self)
		end
	end
	addPermWidget(scroll, ui, ui.addMemberWarnLbl)

	ui.permEndY = y
	GlobalStorageSiK.TerminalPermissions.refreshMemberPickCombo(ui)
end

--- Muestra un aviso breve junto al boton "Añadir" cuando no hay seleccion
--- valida en el combo (evita el fallo silencioso original).
---@param ui table
function GlobalStorageSiK.TerminalPermissions.flashPickWarning(ui)
	if not ui or not ui.addMemberWarnLbl then return end
	ui.addMemberWarnLbl:setVisible(true)
	ui._addMemberWarnUntil = getTimestampMs() + 2500
end

---@param perms table|nil
---@return string
local function permListFingerprint(perms)
	perms = perms or {}
	local parts = { tostring(perms.owner or ""), tostring(perms.playerRole or "") }
	for i = 1, #(perms.allowedUsers or {}) do
		parts[#parts + 1] = "u:" .. perms.allowedUsers[i]
	end
	for i = 1, #(perms.adminUsers or {}) do
		parts[#parts + 1] = "a:" .. perms.adminUsers[i]
	end
	for i = 1, #(perms.allowedFactions or {}) do
		parts[#parts + 1] = "f:" .. perms.allowedFactions[i]
	end
	return table.concat(parts, "|")
end

--- Actualiza datos (visibilidad, filas de miembros, anchos) sin posicionar nada en Y.
--- El posicionado final lo hace siempre layoutPermsBlock en una sola pasada determinista.
---@param scroll ISPanel
---@param terminal GS_TerminalUI
---@param ui table
---@param state table
local function syncPermsData(scroll, terminal, ui, state)
	local perms = state.permissions or {}
	local innerW = GlobalStorageSiK.TerminalScroll.contentWidth(scroll)
	local pad = 8

	ui._permStateRef = state
	ui._permRowW = innerW - pad * 2

	local playerRole = (perms.playerRole) or "member"
	local isAdmin = playerRole == "admin" or playerRole == "owner"
	local isOwner = playerRole == "owner"

	-- Bloque "Añadir acceso" solo visible para admin/owner
	if ui.addBlockTitle then ui.addBlockTitle:setVisible(isAdmin) end
	if ui.memberPickCombo then ui.memberPickCombo:setVisible(isAdmin) end
	if ui.addMemberBtn then ui.addMemberBtn:setVisible(isAdmin) end

	-- Avisos de sucesion: solo el owner necesita conocer el riesgo. El
	-- backupCount solo cuenta personajes individuales (allowedUsers, que ya
	-- incluye a los admins) - las facciones no se usan en handleOwnerDeath
	-- porque la sucesion promociona a UN personaje, no a una faccion entera.
	local backupCount = #(perms.allowedUsers or {})
	if ui.successionHintLbl then ui.successionHintLbl:setVisible(isOwner) end
	if ui.noBackupWarnLbl then ui.noBackupWarnLbl:setVisible(isOwner and backupCount == 0) end

	if isAdmin then
		GlobalStorageSiK.TerminalPermissions.refreshMemberPickCombo(ui)
	end

	if ui.permTableHost then
		ui.permTableHost:setWidth(innerW - pad * 2)
	end
	if ui.permTableHeader then
		ui.permTableHeader:setWidth(innerW - pad * 2)
	end

	local fp = permListFingerprint(perms)
	if ui.lastPermFingerprint ~= fp or not ui.memberRows then
		ui.lastPermFingerprint = fp
		ui.memberRows = buildMemberRows(perms)
	end
end

--- Posiciona TODO el bloque de permisos en una sola pasada determinista (sin Y relativas
--- guardadas ni heurísticas de reconstrucción): siempre recalcula desde startY hacia abajo
--- usando las alturas reales actuales (tabla de miembros ya redimensionada). Mismo patrón
--- que el editor de nodos: calcular antes de posicionar, nunca reposicionar a ciegas.
---@param scroll ISPanel
---@param ui table
---@param startY number
---@return number endY
--- LAYOUT UNIFICADO del bloque de permisos (X + Y + anchos en UNA pasada).
--- Antes estaba partido en dos fases (Y vs ancho) que se desincronizaban y dejaban
--- el bloque "Añadir acceso" encima de las filas de miembros. Ahora una sola columna
--- cascadea todo desde la altura REAL de la tabla → nunca se solapa, escala completo.
local function layoutPermsBlock(scroll, ui, startY)
	if not ui or not ui.permsBuilt then
		return startY
	end
	ui.permBlockStartY = startY
	local pad = 8
	local titleH = FONT_HGT_SMALL + ROW_GAP
	local innerW = GlobalStorageSiK.TerminalScroll.contentWidth(scroll)
	local rowW = math.max(80, innerW - pad * 2)
	ui._permRowW = rowW
	local comboW = math.max(60, rowW - ADD_W - ROW_GAP)

	local col = GlobalStorageSiK.UILayout.column{
		x = pad, y = startY + 8, width = rowW, scroll = scroll, gap = 0,
	}
	ui.permsStartY = startY + 8

	-- Títulos de sección y de tabla (centrados: solo X/Y, conservan su auto-ancho).
	col:place(ui.secLbl, titleH)
	col:place(ui.accessTableTitle, titleH)

	-- Tabla de miembros: posicionar host, rellenar filas (fija altura real), leerla.
	ui.permTableY = col:y()
	if ui.permTableHost then ui.permTableHost:setWidth(rowW) end
	if ui.permTableHeader then ui.permTableHeader:setWidth(rowW) end
	col:_set(ui.permTableHost, pad, col.cursor, rowW, nil)   -- X/Y/ancho (alto tras filas)
	GlobalStorageSiK.TerminalPermissions.layoutMemberRows(ui) -- posiciona filas y fija host:height
	local tableH = (ui.permTableHost and ui.permTableHost.getHeight and ui.permTableHost:getHeight())
		or (HEADER_H + 2 + ROW_H + 8)
	ui.permAccessListStartY = ui.permTableY
	col.cursor = col.cursor + tableH + BLOCK_GAP

	-- Avisos de sucesion (solo owner, ver syncPermsData): reservan hueco
	-- solo si estan visibles, para no dejar espacio en blanco al resto.
	if ui.successionHintLbl and ui.successionHintLbl.isVisible and ui.successionHintLbl:isVisible() then
		col:place(ui.successionHintLbl, titleH)
	end
	if ui.noBackupWarnLbl and ui.noBackupWarnLbl.isVisible and ui.noBackupWarnLbl:isVisible() then
		col:place(ui.noBackupWarnLbl, titleH)
	end

	-- Bloque "Añadir acceso": SIEMPRE recolocado fresco bajo la tabla (si es visible).
	local addVisible = ui.addBlockTitle
		and ui.addBlockTitle.isVisible and ui.addBlockTitle:isVisible()
	if addVisible then
		col:place(ui.addBlockTitle, titleH)
		local rowY = col.cursor
		if ui.addMemberBtn then
			GlobalStorageSiK.TerminalChrome.fitNeatButtonToLabel(ui.addMemberBtn)
		end
		col:_set(ui.memberPickCombo, pad, rowY, comboW, nil)
		col:_set(ui.addMemberBtn, pad + comboW + ROW_GAP, rowY, nil, nil)
		col.cursor = col.cursor + ENTRY_H + ROW_GAP
		if ui.addMemberWarnLbl then
			col:_set(ui.addMemberWarnLbl, pad, col.cursor, rowW, nil)
		end
		col.cursor = col.cursor + titleH
	elseif ui.addMemberWarnLbl then
		ui.addMemberWarnLbl:setVisible(false)
	end

	ui.permEndY = col:y()
	return ui.permEndY
end

--- Compatibilidad con API anterior (usada por refreshInScroll legacy).
function GlobalStorageSiK.TerminalPermissions.syncInNetworkScroll(scroll, terminal, ui, state)
	syncPermsData(scroll, terminal, ui, state)
	return layoutPermsBlock(scroll, ui, (ui.permsStartY or 8) - 8)
end

--- Asegura bloque de permisos en scroll de red.
---@param scroll ISPanel
---@param terminal GS_TerminalUI
---@param ui table
---@param state table
---@param startY number
---@return number endY
function GlobalStorageSiK.TerminalPermissions.ensureInNetworkScroll(scroll, terminal, ui, state, startY)
	if ui.permsBuilt and ui.permUiVersion ~= PERM_UI_VERSION then
		local host = GlobalStorageSiK.TerminalScroll.childHost(scroll)
		for i = 1, #(ui.permWidgets or {}) do
			GlobalStorageSiK.TerminalScroll.disposeChild(host, ui.permWidgets[i])
		end
		ui.permWidgets = {}
		ui.permsBuilt = false
		ui.permTableHost = nil
		ui.memberRowPool = nil
	end
	if not ui.permsBuilt then
		GlobalStorageSiK.TerminalPermissions.buildInNetworkScroll(scroll, terminal, ui, startY)
	end
	syncPermsData(scroll, terminal, ui, state)
	return layoutPermsBlock(scroll, ui, startY)
end

--- Mueve el bloque de permisos a una nueva Y absoluta y actualiza permEndY.
--- Usar desde layoutUi() cuando termBlockEndY cambia sin reconstruir permisos.
---@param scroll ISPanel
---@param ui table
---@param startY number   nueva Y de inicio del bloque (antes de pad interno de 8)
function GlobalStorageSiK.TerminalPermissions.repositionBlock(scroll, ui, startY)
	if not ui or not ui.permsBuilt then return end
	layoutPermsBlock(scroll, ui, startY)
end

--- Ajusta anchos del bloque de permisos.
---@param scroll ISPanel
---@param ui table
---@param innerW number
--- Ajuste de anchos en resize: delega en la cascada unificada (X+Y+ancho en una
--- sola pasada), evitando la desincronización de fases que causaba solapes.
function GlobalStorageSiK.TerminalPermissions.layoutInNetworkScroll(scroll, ui, innerW)
	if not ui or not ui.permsBuilt then
		return
	end
	layoutPermsBlock(scroll, ui, ui.permBlockStartY or ((ui.permsStartY or 8) - 8))
end

--- Compatibilidad con API anterior.
---@param scroll ISPanel
---@param terminal GS_TerminalUI
---@param perms table|nil
---@param startY number
---@return number endY
function GlobalStorageSiK.TerminalPermissions.refreshInScroll(scroll, terminal, perms, startY)
	local ui = scroll._gsNetUi
	if not ui then
		return startY
	end
	local state = terminal.terminalState or {}
	state.permissions = perms or state.permissions
	return GlobalStorageSiK.TerminalPermissions.ensureInNetworkScroll(scroll, terminal, ui, state, startY)
end
