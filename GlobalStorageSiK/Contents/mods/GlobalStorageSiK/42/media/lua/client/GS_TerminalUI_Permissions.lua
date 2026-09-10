--[[
	GlobalStorageSiK - Permisos de red (bloque en pestaña Red)
	Autor: SiK
	Fecha: 2025-06-27
	Descripción: Tabla de miembros (sin scroll) + añadir acceso; transferencia en menú contextual.
]]

require "GS_I18n"
require "GS_Permissions"
require "GS_NetClient"
require "GS_TerminalUI_MemberEditor"

local UI = require "GS_UI_Framework"

GlobalStorageSiK.TerminalPermissions = {}

local T = GlobalStorageSiK.I18n.text
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local CONTROL_METRICS = UI.Controls.metrics("standard")
local ENTRY_H = CONTROL_METRICS.inputHeight
local ROW_GAP = CONTROL_METRICS.controlGap
local BLOCK_GAP = CONTROL_METRICS.rowGap
local MEMBER_TABLE_COLUMNS = {
	{ key = "role", titleKey = "IGUI_GS_PermColRole", width = 120, pad = 6 },
	{ key = "name", titleKey = "IGUI_GS_PermColMemberName", flex = 1, minWidth = 160, pad = 6 },
	{ key = "connection", titleKey = "IGUI_GS_PermColConnection", width = 140, align = "right", pad = 6 },
}
local MEMBER_TABLE_OPTIONS = { left = 0, right = 0, gap = 8, rowHeight = 40 }
local ROW_H = UI.Table.metrics(MEMBER_TABLE_OPTIONS).rowHeight
-- v20: fila de miembro simplificada (sin botones "Quitar"/"Roles" inline) -
-- un clic en la fila abre GS_TerminalUI_MemberEditor.lua, igual patron que
-- la tabla de "Gestion de terminales" (clic en fila -> ventana modal con
-- TODAS las acciones validadas por permiso, desplegable de rol incluido).
local PERM_UI_VERSION = 23

local function createRowButton(x, y, w, h, title, target, onClick)
        return UI.Controls.button(nil, {
		x = x, y = y, w = w, h = h, text = title,
		target = target, onClick = onClick, fullWidth = true,
	})
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

local function memberIdentityKey(value)
	value = tostring(value or "")
	value = string.gsub(value, "^%s*(.-)%s*$", "%1")
	return string.lower(value)
end

--- Etiqueta humana separada de la identidad operativa. El nombre exacto del
--- personaje es lo que ve el jugador; cuenta e ID nunca sustituyen esa etiqueta.
--- Los homónimos del selector se desambiguan después con un sufijo de ID.
--- Prioridad unica compartida con GS_AdminDashboard.lua - ver
--- GlobalStorageSiK.Permissions.resolveMemberDisplayName (2026-08-26,
--- revision tecnica: las 2 interfaces tenian antes un orden de campos
--- distinto, podian mostrar un nombre diferente para el mismo miembro).
local function memberDisplayLabel(entry)
	return GlobalStorageSiK.Permissions.resolveMemberDisplayName(entry)
end

--- Construye índices desde memberEntries, que es la lista autoritativa ya
--- serializada por el servidor. Los IDs evitan colisiones entre personajes
--- con el mismo nombre; los nombres solo son fallback para permisos legacy y
--- miembros offline que todavía no tienen characterId.
---@param perms table|nil
---@return table ids, table legacyNames, table allNames
local function buildExistingMemberLookup(perms)
	local ids = {}
	local legacyNames = {}
	local allNames = {}
	local entries = (perms and perms.memberEntries) or nil
	if entries then
		for i = 1, #entries do
			local entry = entries[i]
			-- BUG REAL (2026-08-26): una ficha ROLE_DEAD (vida terminada, real o
			-- por una reconciliacion que despues resulta erronea) NUNCA debe
			-- contar como "ya es miembro" - su nombre/ID quedan huerfanos en
			-- characterPermissions solo para auditoria (ver GS_AdminDashboard).
			-- Sin este filtro, isExistingMember() la trataba como ocupada y
			-- ocultaba a un jugador REALMENTE conectado del selector "añadir
			-- miembro" (aparece "fallecido" para el sistema aunque siga vivo
			-- con un characterId nuevo) - imposible re-añadirlo desde el picker
			-- normal hasta que alguien lo notara y limpiara la ficha a mano.
			if entry and entry.role ~= GlobalStorageSiK.Permissions.ROLE_DEAD then
				local id = tostring(entry.id or "")
				local name = memberIdentityKey(entry.name)
				if id ~= "" then ids[id] = true end
				if name ~= "" then
					allNames[name] = true
					if id == "" or entry.legacy == true then legacyNames[name] = true end
				end
			end
		end
		return ids, legacyNames, allNames
	end

	-- Compatibilidad con un servidor anterior durante un despliegue escalonado.
	local ownerId = perms and tostring(perms.ownerCharacterId or "") or ""
	local ownerName = memberIdentityKey(perms and perms.owner)
	if ownerId ~= "" then ids[ownerId] = true end
	if ownerName ~= "" then
		allNames[ownerName] = true
		if ownerId == "" then legacyNames[ownerName] = true end
	end
	for i = 1, #((perms and perms.allowedUsers) or {}) do
		local name = memberIdentityKey(perms.allowedUsers[i])
		if name ~= "" then
			allNames[name] = true
			legacyNames[name] = true
		end
	end
	return ids, legacyNames, allNames
end

local function countRosterIdentityKeys(entries)
	local counts = {}
	for i = 1, #(entries or {}) do
		local entry = entries[i]
		local perEntry = {}
		for _, value in ipairs({ entry and entry.name, entry and entry.username }) do
			local key = memberIdentityKey(value)
			if key ~= "" and not perEntry[key] then
				perEntry[key] = true
				counts[key] = (counts[key] or 0) + 1
			end
		end
	end
	return counts
end

local function isExistingMember(entry, ids, legacyNames, allNames, rosterCounts)
	local id = entry and tostring(entry.id or "") or ""
	local name = memberIdentityKey(entry and entry.name)
	local username = memberIdentityKey(entry and entry.username)
	if id ~= "" then
		if ids[id] == true then return true end
		-- Un permiso legacy por nombre solo identifica a una persona si ese
		-- valor es único en el roster. Si varios personajes comparten el nombre
		-- (caso observado con nombres chinos mal representados por SurvivorDesc),
		-- deben seguir apareciendo para poder vincular explícitamente su ID.
		local uniqueLegacyName = legacyNames[name] == true and (rosterCounts[name] or 0) <= 1
		local uniqueLegacyUsername = legacyNames[username] == true and (rosterCounts[username] or 0) <= 1
		return uniqueLegacyName or uniqueLegacyUsername
	end
	return allNames[name] == true or allNames[username] == true
end

--- El cliente remoto solo conoce sus jugadores locales; el roster completo
--- debe venir del servidor dentro de permissions.onlineCharacters.
---@param perms table|nil
---@return table[] { id, name, label }
function GlobalStorageSiK.TerminalPermissions.collectOnlineCharacters(perms)
	local rows = {}
	local labelCounts = {}
	local ids, legacyNames, allNames = buildExistingMemberLookup(perms)
	local onlineCharacters = (perms and perms.onlineCharacters) or {}
	local rosterCounts = countRosterIdentityKeys(onlineCharacters)
	for i = 1, #onlineCharacters do
		local entry = onlineCharacters[i]
		if entry and entry.id and entry.id ~= "" and entry.name and entry.name ~= ""
			and not isExistingMember(entry, ids, legacyNames, allNames, rosterCounts) then
			local label = memberDisplayLabel(entry)
			local labelKey = memberIdentityKey(label)
			labelCounts[labelKey] = (labelCounts[labelKey] or 0) + 1
			rows[#rows + 1] = {
				id = entry.id,
				name = entry.name,
				displayName = entry.displayName or "",
				username = entry.username or "",
				label = label,
			}
		end
	end
	for i = 1, #rows do
		local entry = rows[i]
		if (labelCounts[memberIdentityKey(entry.label)] or 0) > 1 then
			entry.label = entry.label .. " [" .. string.sub(entry.id, -6) .. "]"
		end
	end
	return rows
end

--- Opciones del desplegable de facción (miembros online/offline + toda la
--- facción). El roster viene del servidor, que usa Faction:getPlayers(); el
--- cliente no deriva permisos de su lista local.
---@return table[] { kind, value, label }
function GlobalStorageSiK.TerminalPermissions.collectFactionPickerOptions(perms)
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
	local ids, legacyNames, allNames = buildExistingMemberLookup(perms)
	local factionMembers = (perms and perms.factionMembers) or nil
	if not factionMembers then
		-- Compatibilidad con un servidor Core anterior durante un despliegue
		-- escalonado: solo podrá mostrar conectados, como antes.
		factionMembers = {}
		for i = 1, #((perms and perms.onlineCharacters) or {}) do
			local entry = perms.onlineCharacters[i]
			if entry and entry.sameFaction then
				factionMembers[#factionMembers + 1] = entry
			end
		end
	end
	local rosterCounts = countRosterIdentityKeys(factionMembers)
	for i = 1, #factionMembers do
		local entry = factionMembers[i]
		if entry and entry.name and entry.name ~= ""
			and not isExistingMember(entry, ids, legacyNames, allNames, rosterCounts) then
			options[#options + 1] = {
				kind = "member",
				value = entry.name,
				characterId = entry.id or "",
				factionUsername = entry.username or "",
				label = T("IGUI_GS_PermPickFactionMember", memberDisplayLabel(entry)),
			}
		end
	end
	-- "Toda la faccion" solo tiene sentido si queda al menos un miembro por
	-- añadir. Se inserta al principio para conservar el orden visual anterior.
	if #options > 0 then
		table.insert(options, 1, {
			kind = "whole",
			value = fname,
			label = T("IGUI_GS_PermPickWholeFaction", fname),
		})
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
	UI.Scroll.addChild(scroll, widget)
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
	-- En MP manda el rol que el servidor calculó con el UUID autoritativo. El
	-- modData local puede llegar un frame más tarde y no debe ocultar controles.
	if perms and perms.playerRole == "owner" then return true end
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
	if perms.memberEntries and #perms.memberEntries > 0 then
		local seenIds = {}
		local ownerSeen = false
		for i = 1, #perms.memberEntries do
			local entry = perms.memberEntries[i]
			local id = tostring(entry.id or entry.characterId or "")
			local isOwner = entry.role == "owner"
			local isDead = entry.role == GlobalStorageSiK.Permissions.ROLE_DEAD
			local duplicate = (id ~= "" and seenIds[id] == true) or (isOwner and ownerSeen)
			-- Un miembro fallecido ya no gestiona ni accede a nada - no pinta
			-- nada en la pestaña normal de gestion (pedido explicito
			-- 2026-08-22: "desde la pestaña de admin no debemos verlo, ya no
			-- es miembro de la red"). Sigue visible con su marca en el panel
			-- de soporte de staff (GS_AdminDashboard.lua), que si necesita
			-- verlo para gestionar/auditar.
			if not duplicate and not isDead then
				if id ~= "" then seenIds[id] = true end
				if isOwner then ownerSeen = true end
				rows[#rows + 1] = {
					kind = entry.role == "member" and "user" or entry.role,
					name = entry.name,
					displayName = memberDisplayLabel(entry),
					characterId = id,
					username = entry.username or "",
					legacy = entry.legacy == true,
					deniedZoneIds = entry.deniedZoneIds or {},
					diedAt = entry.diedAt,
					lastSeenAt = entry.lastSeenAt,
					online = entry.online == true,
				}
			end
		end
		return rows
	end
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
        if kind == "owner" then
                return UI.Theme.color("accent")
        elseif kind == "admin" then
                return UI.Theme.color("warning")
        end
        return UI.Theme.color("textMuted")
end

MEMBER_TABLE_COLUMNS[1].value = function(data)
	return { text = memberRoleLabel(data.kind), color = roleColor(data.kind) }
end
MEMBER_TABLE_COLUMNS[2].value = function(data)
        return { text = data.displayName or data.name or "?",
                color = UI.Theme.color("text") }
end
MEMBER_TABLE_COLUMNS[3].value = function(data)
        if data.online then
                return { text = T("IGUI_GS_AdminOnline"), color = UI.Theme.color("success") }
        end
        if data.lastSeenAt then
                return { text = T("IGUI_GS_AdminOffline",
                        relativeAge(data.lastSeenAt)), color = UI.Theme.color("textMuted") }
        end
        return { text = "", color = UI.Theme.color("textMuted") }
end

--- Refluye la tabla compuesta de miembros; el bloque posee su scroll interno.
---@param ui table
function GlobalStorageSiK.TerminalPermissions.layoutMemberRows(ui)
        local tableBlock = ui and ui.memberTableBlock
	local frame = ui and ui.memberTableFrame
	if not tableBlock or not frame then return end
        local rows = ui.memberRows or {}
	local frameX, frameY = 8, ui.permTableY or 0
	local frameW = ui._permRowW or frame.w
	frame:setBounds(frameX, frameY, frameW, frame.h)
	local content = frame:getContentRect()
	tableBlock:layout({ x = content.x, y = content.y, w = content.w,
		rows = rows, preserveOffset = true })
	local bottom = math.max(0, frame.h - content.y - content.h)
	frame:setBounds(frameX, frameY, frameW, content.y + tableBlock:getHeight() + bottom)
	content = frame:getContentRect()
	tableBlock:layout({ x = content.x, y = content.y, w = content.w, h = content.h,
		rows = rows, preserveOffset = true })
end

---@param ui table
--- Rellena el combo unificado con grupos: Facción y Servidor.
---@param ui table
function GlobalStorageSiK.TerminalPermissions.refreshMemberPickCombo(ui)
	if not ui or not ui.memberPickCombo then return end
	local selectedMeta = ui._memberPickMeta
		and ui._memberPickMeta[ui.memberPickCombo.selected or 1] or nil
	local selectedKey = selectedMeta and (tostring(selectedMeta.kind or "") .. ":"
		.. tostring(selectedMeta.characterId or selectedMeta.factionUsername or selectedMeta.value or "")) or ""
	ui.memberPickCombo:clear()
	ui._memberPickMeta = {}

	ui._memberPickMeta[1] = { kind = "none" }
	ui.memberPickCombo:addOption(T("IGUI_GS_PickMember"))

	local perms = ui._permStateRef and ui._permStateRef.permissions or {}
	local factionOptions = {}
	local serverCharacters = {}
	local pickerCandidates = perms.pickerCandidates
	if pickerCandidates then
		local labelCounts = {}
		for i = 1, #pickerCandidates do
			local entry = pickerCandidates[i]
			local key = memberIdentityKey(memberDisplayLabel(entry))
			labelCounts[key] = (labelCounts[key] or 0) + 1
		end
		for i = 1, #pickerCandidates do
			local entry = pickerCandidates[i]
			local label = memberDisplayLabel(entry)
			local id = tostring(entry.characterId or entry.id or "")
			if id ~= "" and (labelCounts[memberIdentityKey(label)] or 0) > 1 then
				label = label .. " [" .. string.sub(id, -6) .. "]"
			end
			local option = {
				kind = "member", value = entry.characterName or entry.name,
				characterId = id,
				factionUsername = entry.factionUsername or "",
				label = label,
			}
			if entry.source == "faction" then
				option.label = T("IGUI_GS_PermPickFactionMember", label)
				factionOptions[#factionOptions + 1] = option
			else
				serverCharacters[#serverCharacters + 1] = option
			end
		end
		if #factionOptions > 0 then
			table.insert(factionOptions, 1, {
				kind = "whole", value = perms.playerFactionName or "",
				label = T("IGUI_GS_PermPickWholeFaction", perms.playerFactionName or ""),
			})
		end
	else
		-- Compatibilidad durante un despliegue escalonado con un servidor
		-- anterior que todavía expone ambos rosters por separado.
		factionOptions = GlobalStorageSiK.TerminalPermissions.collectFactionPickerOptions(perms)
		serverCharacters = GlobalStorageSiK.TerminalPermissions.collectOnlineCharacters(perms)
	end

	-- Grupo: facción del jugador
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
	if #serverCharacters > 0 then
		ui._memberPickMeta[#ui._memberPickMeta + 1] = { kind = "header" }
		ui.memberPickCombo:addOption("[ " .. T("IGUI_GS_PickGroupServer") .. " ]")
		for i = 1, #serverCharacters do
			local entry = serverCharacters[i]
			ui._memberPickMeta[#ui._memberPickMeta + 1] = {
				kind = entry.kind or "player", value = entry.value or entry.name,
				characterId = entry.characterId or entry.id,
				factionUsername = entry.factionUsername or "", label = entry.label,
			}
			ui.memberPickCombo:addOption("  " .. entry.label)
		end
	elseif GlobalStorageSiK.isMultiplayerActive()
		and #((perms and perms.onlineCharacters) or {}) == 0 then
		ui._memberPickMeta[#ui._memberPickMeta + 1] = { kind = "header" }
		ui.memberPickCombo:addOption("[ " .. T("IGUI_GS_PickGroupServerEmpty") .. " ]")
	end

	ui.memberPickCombo.selected = 1
	if selectedKey ~= "" then
		for i = 1, #ui._memberPickMeta do
			local meta = ui._memberPickMeta[i]
			local key = tostring(meta.kind or "") .. ":"
				.. tostring(meta.characterId or meta.factionUsername or meta.value or "")
			if key == selectedKey then
				ui.memberPickCombo.selected = i
				break
			end
		end
	end
end

-- Compatibilidad con llamadas antiguas
function GlobalStorageSiK.TerminalPermissions.refreshOnlineCombo(ui)
	GlobalStorageSiK.TerminalPermissions.refreshMemberPickCombo(ui)
end
function GlobalStorageSiK.TerminalPermissions.refreshFactionCombo(ui)
	-- Vacío: fusionado en refreshMemberPickCombo
end

--- Construye bloque de permisos (widgets fijos).
---@param scroll ISPanel
---@param terminal GS_TerminalUI
---@param ui table
---@param startY number
function GlobalStorageSiK.TerminalPermissions.buildInNetworkScroll(scroll, terminal, ui, startY)
	local pad = 8
	local y = startY + 8
        local innerW = UI.Scroll.contentWidth(scroll)
	local titleH = FONT_HGT_SMALL + ROW_GAP
	local rowW = innerW - pad * 2
	local comboW = rowW

	ui.permsStartY = y
	ui.permsBuilt = true
	ui.permUiVersion = PERM_UI_VERSION
	ui.permWidgets = ui.permWidgets or {}
	ui.lastPermFingerprint = ""
	ui._permRowW = rowW
	ui.terminalRef = terminal

        ui.permTableY = y
	local tableFrame, frameError = UI.Block.create({
		parent = UI.Scroll.childHost(scroll), x = pad, y = ui.permTableY,
		w = rowW, h = titleH + ROW_H * 2 + pad * 2,
		-- The Block owns the standard title/help/padding; Table remains the
		-- unframed inner viewport and must not recreate that chrome.
		title = T("IGUI_GS_OptionsMembersTitle"),
		tooltip = T("IGUI_GS_OptionsMembersHelp"),
	})
	if not tableFrame then error("SiK.UI.Block.create(admin.members): " .. tostring(frameError)) end
	ui.memberTableFrame = tableFrame
	local tableContent = tableFrame:getContentRect()
        local tableInstance, tableError = UI.Table.create({
				parent = tableFrame.childParent, embedded = true,
				x = tableContent.x, y = tableContent.y,
				w = tableContent.w, h = tableContent.h,
                emptyText = T("IGUI_GS_NoPermAccess"), columns = MEMBER_TABLE_COLUMNS,
                rowHeight = MEMBER_TABLE_OPTIONS.rowHeight,
                gap = MEMBER_TABLE_OPTIONS.gap,
                autoHeight = true, minRows = 1, maxRows = 8,
                onRowClick = function(context)
                        local data = context.item
                        if not data then return false end
                        local perms = (ui._permStateRef and ui._permStateRef.permissions) or {}
                        GlobalStorageSiK.TerminalMemberEditor.open(terminal, data, perms.playerRole or "member")
                        return true
                end,
        })
        if not tableInstance then
		tableFrame:dispose()
		ui.memberTableFrame = nil
                error("SiK.UI.Table.create(admin.members): " .. tostring(tableError))
        end
        ui.memberTableBlock = tableInstance
        GlobalStorageSiK.TerminalPermissions.layoutMemberRows(ui)
		y = ui.permTableY + ui.memberTableFrame.h + BLOCK_GAP
	ui.permAccessListStartY = ui.permTableY

	-- Avisos de sucesion de propietario (solo visibles para el owner, ver
	-- syncPermsData): explica que pasa al morir para que el jugador conozca
	-- el riesgo, en vez de descubrirlo tras perder acceso.
        ui.successionHintLbl = UI.Controls.copyText(nil, {
                x = pad, y = y, w = rowW, text = T("IGUI_GS_PermSuccessionHint"),
                tone = "textMuted",
        })
        addPermWidget(scroll, ui, ui.successionHintLbl)
        y = y + ui.successionHintLbl:getHeight() + ROW_GAP

        ui.noBackupWarnLbl = UI.Controls.status(nil, {
                x = pad, y = y, text = T("IGUI_GS_PermNoBackupWarn"), tone = "warning",
        })
        addPermWidget(scroll, ui, ui.noBackupWarnLbl)
	y = y + FONT_HGT_SMALL + BLOCK_GAP

	-- Boton "Reclamar propiedad" para un admin VIVO cuyo propietario lleva
	-- demasiado inactivo, o la red esta vacante (2026-08-23, ver
	-- GS_TerminalUI:onClaimAsAdmin / canAdminClaimOwnership) - solo visible
	-- para admin, nunca para member (syncPermsData controla su visibilidad
	-- via perms.canClaimAsAdmin, ya calculado en servidor).
	ui.claimAsAdminBtn = createRowButton(pad, y, 220, ENTRY_H, T("IGUI_GS_ClaimOwnershipButton"), scroll, function()
		terminal:onClaimAsAdmin()
	end)
	addPermWidget(scroll, ui, ui.claimAsAdminBtn)

        ui.addBlockTitle = UI.Controls.sectionTitle(nil, {
		x = pad, y = y, text = T("IGUI_GS_PermAddBlockTitle"),
	})
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
        ui.memberPickCombo = UI.Controls.combo(nil, {
		x = pad, y = y, w = comboW, h = ENTRY_H, target = scroll,
	})
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
			terminal:onAddPermissionUser(pick.value, pick.characterId, pick.factionUsername)
		end
	end)
	addPermWidget(scroll, ui, ui.addMemberBtn)

	-- Aviso transitorio cuando se pulsa "Añadir" sin nada seleccionado en el
	-- combo (antes fallaba en silencio - resolveMemberPick devolvia nil y el
	-- boton no hacia nada visible). Se auto-oculta comprobando el timestamp
	-- en su propio render, sin necesitar un tick externo. Texto neutro (no
	-- "primero...") - el combo ya deja claro que hay que elegir algo.
        ui.addMemberWarnLbl = UI.Controls.status(nil, {
                x = pad, y = y + ENTRY_H + 2,
                text = T("IGUI_GS_PermPickNone"), tone = "warning",
        })
	ui.addMemberWarnLbl:setVisible(false)
	local renderStatus = ui.addMemberWarnLbl.render
	ui.addMemberWarnLbl.render = function(self)
		if ui._addMemberWarnUntil and getTimestampMs() > ui._addMemberWarnUntil then
			self:setVisible(false)
			ui._addMemberWarnUntil = nil
		end
		if self:isVisible() then
			renderStatus(self)
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
	for i = 1, #(perms.memberEntries or {}) do
		local member = perms.memberEntries[i]
		parts[#parts + 1] = "m:" .. tostring(member.id or "") .. ":" .. tostring(member.role or "")
		for j = 1, #(member.deniedZoneIds or {}) do
			parts[#parts + 1] = "z:" .. tostring(member.id or member.name or "")
				.. ":" .. tostring(member.deniedZoneIds[j])
		end
	end
	for _, field in ipairs({ "onlineCharacters", "factionMembers", "pickerCandidates" }) do
		for i = 1, #(perms[field] or {}) do
			local entry = perms[field][i]
			parts[#parts + 1] = field .. ":" .. tostring(entry.characterId or entry.id or "")
				.. ":" .. tostring(entry.username or "")
				.. ":" .. tostring(entry.characterName or entry.name or "")
				.. ":" .. tostring(entry.source or "")
				.. ":" .. tostring(entry.online == true)
		end
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
	local innerW = UI.Scroll.contentWidth(scroll)
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
	-- Calculado SIEMPRE en servidor (GlobalStorageSiK.Permissions.
	-- canAdminClaimOwnership, ver GS_Permissions.lua:serialize) - el cliente
	-- solo pinta el boton segun lo que se le diga, nunca decide por su cuenta.
	if ui.claimAsAdminBtn then ui.claimAsAdminBtn:setVisible(perms.canClaimAsAdmin == true) end

	if isAdmin then
		GlobalStorageSiK.TerminalPermissions.refreshMemberPickCombo(ui)
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
	local innerW = UI.Scroll.contentWidth(scroll)
	local rowW = math.max(80, innerW - pad * 2)
	ui._permRowW = rowW

        local col = UI.Layout.column{
                x = pad, y = startY + 8, width = rowW, gap = 0,
                position = function(widget, x, y, w, h)
                        if x ~= nil then UI.Scroll.setContentX(scroll, widget, x) end
                        if y ~= nil then UI.Scroll.setContentY(scroll, widget, y) end
                        if w ~= nil and widget.setWidth then widget:setWidth(w) end
                        if h ~= nil and widget.setHeight then widget:setHeight(h) end
                end,
        }
	ui.permsStartY = startY + 8

        -- Tabla de miembros completa: el framework reposiciona cabecera, filas,
        -- scrollbar y estado vacío como una sola superficie.
        ui.permTableY = col:y()
        GlobalStorageSiK.TerminalPermissions.layoutMemberRows(ui)
		local tableH = ui.memberTableFrame and ui.memberTableFrame.h or (ROW_H + 16)
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
	if ui.claimAsAdminBtn and ui.claimAsAdminBtn.isVisible and ui.claimAsAdminBtn:isVisible() then
                UI.Controls.fitButtonToContent(ui.claimAsAdminBtn)
		col:place(ui.claimAsAdminBtn, ENTRY_H + ROW_GAP)
	end

	-- Bloque "Añadir acceso": SIEMPRE recolocado fresco bajo la tabla (si es visible).
	local addVisible = ui.addBlockTitle
		and ui.addBlockTitle.isVisible and ui.addBlockTitle:isVisible()
	if addVisible then
		col:place(ui.addBlockTitle, titleH)
		local rowY = col.cursor
		local buttonW = 0
		if ui.addMemberBtn then
                        UI.Controls.fitButtonToContent(ui.addMemberBtn)
			buttonW = math.min(rowW, math.max(72, ui.addMemberBtn:getWidth()))
		end
		local comboMinW = 160
		local stacked = rowW < comboMinW + ROW_GAP + buttonW
		if stacked then
			col:_set(ui.memberPickCombo, pad, rowY, rowW, ENTRY_H)
			col:_set(ui.addMemberBtn, pad, rowY + ENTRY_H + ROW_GAP, rowW, ENTRY_H)
			col.cursor = col.cursor + ENTRY_H * 2 + ROW_GAP * 2
		else
			local comboW = rowW - buttonW - ROW_GAP
			col:_set(ui.memberPickCombo, pad, rowY, comboW, ENTRY_H)
			col:_set(ui.addMemberBtn, pad + comboW + ROW_GAP, rowY, buttonW, ENTRY_H)
			col.cursor = col.cursor + ENTRY_H + ROW_GAP
		end
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
                local host = UI.Scroll.childHost(scroll)
                if ui.memberTableBlock then
                        ui.memberTableBlock:dispose()
                        ui.memberTableBlock = nil
                end
		if ui.memberTableFrame then
			ui.memberTableFrame:dispose()
			ui.memberTableFrame = nil
		end
                for i = 1, #(ui.permWidgets or {}) do
                        UI.Scroll.disposeChild(host, ui.permWidgets[i])
                end
		ui.permWidgets = {}
		ui.permsBuilt = false
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
