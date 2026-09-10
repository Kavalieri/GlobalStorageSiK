--[[
	GlobalStorageSiK - Instalar terminal SiK con el lector (método nuevo)
	Autor: SiK
	Descripción: Diálogo único: red nueva (con nombre) o vincular a una
	existente, sobre un ordenador ya localizado en el mundo (obj/x/y/z ya
	resueltos por el menú contextual del disquete, ver GS_ItemActions.lua).
	No usa cursor de colocación: el ordenador ya está en su sitio, solo
	falta instalar el programa sobre él y registrar la posición. El
	registro final lo hace el mismo comando "registerTerminal" que ya usa
	el método antiguo (vía GS_InstallTerminalReaderAction), reaprovechando
	toda la autoridad de servidor / validación de distancia / mensajes de
	error ya existentes - no se duplica esa lógica aquí.

	Rediseño (feedback directo): las dos opciones (crear / vincular) están
	SIEMPRE visibles a la vez, cada una en su propio bloque, y cada una se
	ejecuta con UN SOLO clic - nada de elegir modo primero y confirmar
	despues. "Crear" es el campo de nombre + su botón; "Vincular" es una
	lista de redes ya existentes, cada una su propio botón que instala de
	inmediato al pulsarla. Si no hay redes accesibles, se explica con
	texto en vez de dejar un combo vacío.
]]

require "GS_I18n"
require "GS_NetClient"
require "GS_TerminalAccess"
local UI = require "GS_UI_Framework"
require "GS_Config"
require "GS_Sandbox"

GlobalStorageSiK.TerminalInstallReaderChoice = {}
GlobalStorageSiK.TerminalInstallReaderChoice.instance = nil

local T = GlobalStorageSiK.I18n.text
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local CONTROL_METRICS = UI.Controls.metrics("task")
local PAD = 14
local LINE_GAP = 4
local WINDOW_PROFILE = "task-requirements"
local SECTION_GAP = 16
local NETWORK_INFO_LINE_COUNT = 8

GS_TerminalInstallReaderChoice = UI.Window.derive("GS_TerminalInstallReaderChoice")

---@return table[]
local function networkRows()
	local serverList = GlobalStorageSiK.Client and GlobalStorageSiK.Client.recoveryNetworks
	return serverList or {}
end

local function recoveryLocationText(row)
	local p = row and (row.lastLocation or row.anchor)
	if not p or p.x == nil or p.y == nil then
		return T("IGUI_GS_NetLocationUnknown")
	end
	return string.format("%d, %d, %d", math.floor(p.x), math.floor(p.y), math.floor(p.z or 0))
end

---@param row table
---@param textW number
---@return string[]
local function recoverySummaryLines(row, textW)
	local status = (row.activeTerminals or 0) > 0
		and T("IGUI_GS_NetStatusActive") or T("IGUI_GS_NetStatusSuspended")
	local texts = {
		T("IGUI_GS_RecoveryNetworkStatusLine", row.label or row.name or row.networkId or "?", status),
		T("IGUI_GS_NetCounts", row.zoneCount or 0, row.nodeCount or 0),
		T("IGUI_GS_NetLastLocation", recoveryLocationText(row)),
	}
	local lines = {}
	for i = 1, #texts do
		local wrapped = UI.Controls.wrapText(texts[i], textW, UIFont.Small)
		for j = 1, #wrapped do lines[#lines + 1] = wrapped[j] end
	end
	return lines
end

--- Crea una o varias ISLabel (una por linea, con salto cuando no cabe en w)
--- para un texto de longitud variable (traduccion) - evita el desbordamiento
--- visto con "IGUI_GS_InstallReaderNoNetworks" (frase larga dibujada antes
--- como una unica ISLabel sin ajuste, que se salia del panel).
---@param panel ISPanel
---@param x number
---@param y number
---@param w number
---@param text string
---@param r number
---@param g number
---@param b number
---@return table[] labels, number yAfter
local function addWrappedLabel(panel, x, y, w, text, tone)
	local label = UI.Controls.copyText(panel, {
		x = x, y = y, w = w, text = text, tone = tone or "textMuted",
		lineGap = LINE_GAP, playerNum = panel.playerNum,
	})
	return { label }, y + label.height
end

local function selectedRecoveryRow(panel)
	local index = panel.networkCombo and panel.networkCombo.selected or 1
	return panel.networkRows and panel.networkRows[index] or nil
end

local function refreshRecoverySelection(panel)
	local row = selectedRecoveryRow(panel)
	local lines = row and recoverySummaryLines(row, panel._layoutTextWidth or panel.width - PAD * 2) or {}
	for i = 1, #(panel.networkInfoLbls or {}) do
		local lbl = panel.networkInfoLbls[i]
		lbl:setText(lines[i] or "")
		lbl:setVisible(lines[i] ~= nil)
	end
	if panel.networkActionBtn then
		local label = row and ((row.activeTerminals or 0) > 0
			and T("IGUI_GS_NetLinkAction") or T("IGUI_GS_NetReactivateAction"))
			or T("IGUI_GS_NetLinkAction")
		panel.networkActionBtn:setText(label)
		panel.networkActionBtn:setLocked(row == nil)
		panel.networkActionBtn:setEnabled(row ~= nil)
	end
end

---@param rows table[]
---@return number
local function measurePanelHeight(rows, width)
	local textW = math.max(1, (tonumber(width) or 1) - PAD * 2)
	local introLines = UI.Controls.wrapText(
		T("IGUI_GS_InstallReaderIntro", GlobalStorageSiK.Sandbox.getTerminalNetworkRange()),
		textW, UIFont.Small)
	local h = PAD
	h = h + #introLines * (FONT_HGT_SMALL + LINE_GAP) + PAD
	-- Bloque "Red nueva": titulo + entry+boton
	h = h + FONT_HGT_SMALL + 4 + CONTROL_METRICS.inputHeight + SECTION_GAP
	-- Separador
	h = h + 1 + SECTION_GAP
	-- Bloque "Red existente": titulo + N filas, o el aviso "sin redes" (con
	-- ajuste de linea - puede ocupar mas de 1 linea segun idioma/longitud).
	h = h + FONT_HGT_SMALL + 6
	if #rows == 0 then
		local noNetLines = UI.Controls.wrapText(
			T("IGUI_GS_InstallReaderNoNetworks"), textW, UIFont.Small)
		h = h + #noNetLines * (FONT_HGT_SMALL + LINE_GAP) + 4
	else
		h = h + CONTROL_METRICS.inputHeight + 6
		h = h + NETWORK_INFO_LINE_COUNT * (FONT_HGT_SMALL + LINE_GAP)
		h = h + CONTROL_METRICS.buttonHeight + 10
	end
	h = h + PAD
	return math.max(320, h)
end

function GS_TerminalInstallReaderChoice:initialise()
	UI.Window.callBase(self, "initialise")
	-- Mismo fondo neutro que la ventana principal del terminal y las de
	-- Conseguir PC/Fabricar lector (GS_PCAcquireUI.lua/GS_ReaderAcquireUI.lua):
	-- el valor anterior (0.08, 0.09, 0.11) tenia el azul mas alto que el
	-- rojo/verde, un tinte azulado sutil pero visible frente al resto de
	-- nuestras ventanas, que son gris neutro.
	self.backgroundColor = { r = 0.06, g = 0.06, b = 0.06, a = 0.98 }
	self.borderColor = { r = 0.35, g = 0.38, b = 0.42, a = 0.95 }
	self:setAlwaysOnTop(true)
	UI.Modal.apply(self, {
		kind = "task", profile = WINDOW_PROFILE, padding = PAD, playerNum = self.playerNum,
		width = self.width, height = self.height, resizable = true,
		onReflow = function() self:reflowContent() end,
		title = T("IGUI_GS_InstallReaderTitle"),
		onClose = function()
			GlobalStorageSiK.TerminalInstallReaderChoice.instance = nil
		end,
	})
	self.statusMsg = nil
	self.busy = false
	self:buildLayout()
end

function GS_TerminalInstallReaderChoice:destroy()
	GlobalStorageSiK.TerminalInstallReaderChoice.instance = nil
	if self._sikWindowApplied and not self._sikDisposed then
		UI.Modal.close(self, "destroy")
	elseif self.removeFromUIManager then self:removeFromUIManager() end
end

---@param msg string
function GS_TerminalInstallReaderChoice:setStatus(msg)
	self.statusMsg = msg
	if self.statusLabel then
		self.statusLabel:setStatus(msg or "", "warning")
	end
end

--- Un solo clic: crea red nueva con el nombre del campo. La acción
--- cronometrada YA se completó antes de que este diálogo se abriera (ver
--- GS_InstallTerminalReaderAction:perform) - aquí solo queda mandar el
--- comando de registro al servidor con la coordenada ya instalada.
function GS_TerminalInstallReaderChoice:onCreateNew()
	if self.busy or not self.target then
		return
	end
	local name = self.nameEntry and self.nameEntry:getText() or ""
	self.busy = true
	self:setStatus(T("IGUI_GS_RecoveryWorking"))
	GlobalStorageSiK.NetClient.sendCommand("installTerminalReader", {
		x = self.target.x, y = self.target.y, z = self.target.z,
		mode = "new", networkName = name,
	})
	self:destroy()
end

--- Un solo clic: vincula a la red concreta pulsada. Mismo motivo que
--- onCreateNew - la instalación en sí ya terminó, solo falta el registro.
---@param row table { networkId, label }
function GS_TerminalInstallReaderChoice:onLinkTo(row)
	if self.busy or not self.target or not row or not row.networkId then
		return
	end
	self.busy = true
	self:setStatus(T("IGUI_GS_RecoveryWorking"))
	GlobalStorageSiK.NetClient.sendCommand("installTerminalReader", {
		x = self.target.x, y = self.target.y, z = self.target.z,
		mode = "link", networkId = row.networkId,
	})
	self:destroy()
end

--- Construye (o reconstruye) el bloque "Red existente": una fila-boton por
--- red, o un aviso si el jugador no pertenece a ninguna.
---@param y number
---@param textW number
---@return number y tras el bloque
function GS_TerminalInstallReaderChoice:buildLinkSection(y, textW)
	local host = self.contentHost or self
	local pad = 0
	local rows = self.networkRows or {}

	-- createSectionLabel (pedido 2026-08-26, "ajustarse a la nueva UI y las
	-- herramientas ya generadas") en vez del ISLabel suelto con color a mano
	-- que tenia antes - mismo titulo de bloque que el resto del proyecto.
	self.linkTitle = UI.Controls.sectionTitle(host, {
		x = pad, y = y, w = textW, text = T("IGUI_GS_InstallReaderLinkTitle"),
		playerNum = self.playerNum,
	})
	y = y + self.linkTitle.height + 6

	self.networkBtns = {}
	self.networkInfoLbls = {}
	self.networkCombo = nil
	self.networkActionBtn = nil
	if #rows == 0 then
		self.noNetworksLbls, y = addWrappedLabel(host, pad, y, textW,
			T("IGUI_GS_InstallReaderNoNetworks"), "warning")
		y = y + 4
	else
		local comboItems = {}
		for i = 1, #rows do
			local row = rows[i]
			local status = (row.activeTerminals or 0) > 0
				and T("IGUI_GS_NetStatusActive") or T("IGUI_GS_NetStatusSuspended")
			comboItems[#comboItems + 1] = {
				text = (row.label or row.networkId or "?") .. " - " .. status,
				value = row,
			}
		end
		self.networkCombo = UI.Controls.combo(host, {
			x = pad, y = y, w = textW, h = CONTROL_METRICS.inputHeight, items = comboItems,
			playerNum = self.playerNum,
			onChange = function() refreshRecoverySelection(self) end,
		})
		y = y + CONTROL_METRICS.inputHeight + 6

		for i = 1, NETWORK_INFO_LINE_COUNT do
			local lbl = UI.Controls.copyText(host, {
				x = pad, y = y, w = textW, text = "", tone = "textMuted",
				lineGap = LINE_GAP, playerNum = self.playerNum,
			})
			self.networkInfoLbls[#self.networkInfoLbls + 1] = lbl
			y = y + FONT_HGT_SMALL + LINE_GAP
		end
		self.networkActionBtn = UI.Controls.button(host, {
			x = pad, y = y, w = textW, h = CONTROL_METRICS.buttonHeight,
			text = T("IGUI_GS_NetLinkAction"), fullWidth = true,
			playerNum = self.playerNum, onClick = function()
				self:onLinkTo(selectedRecoveryRow(self))
			end,
		})
		self.networkBtns[1] = self.networkActionBtn
		y = y + CONTROL_METRICS.buttonHeight + 6
		refreshRecoverySelection(self)
	end
	return y
end

function GS_TerminalInstallReaderChoice:buildLayout()
	local host = self.contentHost or self
	local pad = 0
	local rect = { x = 0, y = 0, w = host.width or 0, h = host.height or 0 }
	local y = rect.y
	local textW = rect.w
	self._layoutTextWidth = textW
	local x = rect.x

	local linkRange = GlobalStorageSiK.Sandbox.getTerminalNetworkRange()
	local intro = UI.Controls.copyText(host, {
		x = x, y = y, w = textW,
		text = T("IGUI_GS_InstallReaderIntro", linkRange),
		tone = "textMuted", lineGap = LINE_GAP, playerNum = self.playerNum,
	})
	self.intro = intro
	y = y + intro.height
	y = y + 6

	-- ── Bloque "Red nueva": nombre + Crear, un solo clic ────────────────────
	self.newTitle = UI.Controls.sectionTitle(host, {
		x = x, y = y, w = textW, text = T("IGUI_GS_InstallReaderNewTitle"),
		playerNum = self.playerNum,
	})
	y = y + self.newTitle.height + 4

	self.createBtn = UI.Controls.button(host, {
		x = x + textW - 100, y = y, w = 100, h = CONTROL_METRICS.inputHeight,
		text = T("IGUI_GS_InstallReaderCreateBtn"), playerNum = self.playerNum,
		onClick = function()
			self:onCreateNew()
		end,
	})
	UI.Controls.fitButtonToContent(self.createBtn, {
		text = T("IGUI_GS_InstallReaderCreateBtn"), padding = 14,
		minWidth = 100, maxWidth = math.floor(textW * 0.4),
	})
	local createW = self.createBtn.width
	self.createBtn:setX(x + textW - createW)
	self.nameEntry = UI.Controls.field(host, {
		x = x, y = y, w = textW - createW - 6, h = CONTROL_METRICS.inputHeight,
		text = T("IGUI_GS_InstallReaderNameDefault"), playerNum = self.playerNum,
	})
	y = y + CONTROL_METRICS.inputHeight + SECTION_GAP

	-- ── Separador visual entre los dos bloques ──────────────────────────────
	self.sepLine = UI.Controls.panel(host, {
		x = x, y = y, w = textW, h = 1, drawBackground = true,
		backgroundColor = { r = 0.3, g = 0.32, b = 0.36, a = 0.6 },
		controlId = "readerChoiceSeparator", playerNum = self.playerNum,
	})
	y = y + 1 + SECTION_GAP

	-- ── Bloque "Red existente": una red por fila, un solo clic ──────────────
	self.networkRows = networkRows()
	y = self:buildLinkSection(y, textW)
	y = y + 6

	self.statusLabel = UI.Controls.status(host, {
		x = x, y = y, w = textW, h = FONT_HGT_SMALL,
		text = self.statusMsg or "", tone = "warning", playerNum = self.playerNum,
	})
	y = y + FONT_HGT_SMALL + pad

	if not self._initialLayoutFitted then
		UI.Modal.fitContent(self, y, { contentBottom = true, bottomPadding = 0, center = true })
		self._initialLayoutFitted = true
	elseif self.contentBlock and self.contentBlock.setContentHeight then
		self.contentBlock:setContentHeight(y)
		self:reflow()
	end
	if GlobalStorageSiK.UIDebug and GlobalStorageSiK.UIDebug.enabled and GlobalStorageSiK.UIDebug.enabled() then
		GlobalStorageSiK.UIDebug.dumpTree(self, "TerminalInstallReaderChoice")
		GlobalStorageSiK.UIDebug.checkOverlaps(self, "TerminalInstallReaderChoice")
	end
end

--- Resize existing controls only. The server list and unfinished name remain
--- intact while Window drives this from its lightweight reflow callback.
function GS_TerminalInstallReaderChoice:reflowContent()
	local host = self.contentHost or self
	if not host or not self.intro or not self.newTitle or not self.sepLine then return end
	local x, y, textW = 0, 0, math.max(1, host.width or 0)
	self._layoutTextWidth = textW
	self.intro:setX(x); self.intro:setY(y); self.intro:reflow(textW)
	y = y + self.intro.height + 6
	self.newTitle:setX(x); self.newTitle:setY(y); self.newTitle:reflow(textW)
	y = y + self.newTitle.height + 4
	local createW = self.createBtn and self.createBtn.width or 0
	if self.createBtn then self.createBtn:setX(x + textW - createW); self.createBtn:setY(y) end
	if self.nameEntry then
		self.nameEntry:setX(x); self.nameEntry:setY(y)
		self.nameEntry:setWidth(math.max(1, textW - createW - 6))
	end
	y = y + CONTROL_METRICS.inputHeight + SECTION_GAP
	self.sepLine:setX(x); self.sepLine:setY(y); self.sepLine:setWidth(textW)
	y = y + 1 + SECTION_GAP
	if self.linkTitle then
		self.linkTitle:setX(x); self.linkTitle:setY(y); self.linkTitle:reflow(textW)
		y = y + self.linkTitle.height + 6
	end
	if self.noNetworksLbls then
		for _, label in ipairs(self.noNetworksLbls) do
			label:setX(x); label:setY(y); label:reflow(textW)
			y = y + label.height
		end
		y = y + 4
	elseif self.networkCombo then
		self.networkCombo:setX(x); self.networkCombo:setY(y); self.networkCombo:setWidth(textW)
		y = y + CONTROL_METRICS.inputHeight + 6
		refreshRecoverySelection(self)
		for _, label in ipairs(self.networkInfoLbls or {}) do
			label:setX(x); label:setY(y); label:setWidth(textW)
			y = y + FONT_HGT_SMALL + LINE_GAP
		end
		if self.networkActionBtn then
			self.networkActionBtn:setX(x); self.networkActionBtn:setY(y); self.networkActionBtn:setWidth(textW)
			y = y + CONTROL_METRICS.buttonHeight + 6
		end
	end
	y = y + 6
	if self.statusLabel then self.statusLabel:setX(x); self.statusLabel:setY(y); self.statusLabel:setWidth(textW) end
	y = y + FONT_HGT_SMALL
	if self.contentBlock and self.contentBlock.setContentHeight then self.contentBlock:setContentHeight(y) end
	return y
end

--- Reconstruye solo el bloque "Red existente" al llegar datos del servidor
--- (mantiene el nombre ya escrito en el campo "Red nueva").
function GS_TerminalInstallReaderChoice:rebuildLinkSection()
	local host = self.contentHost or self
	local pad = 0
	local textW = host.width or 0
	local startY = self.sepLine and (self.sepLine:getY() + 1 + SECTION_GAP) or nil
	if not startY then
		return
	end
	local toRemove = { self.linkTitle }
	for _, lbl in ipairs(self.noNetworksLbls or {}) do
		toRemove[#toRemove + 1] = lbl
	end
	for _, lbl in ipairs(self.networkInfoLbls or {}) do
		toRemove[#toRemove + 1] = lbl
	end
	for _, w in ipairs(toRemove) do
		if w and w.dispose then w:dispose()
		elseif w then host:removeChild(w) end
	end
	for _, btn in ipairs(self.networkBtns or {}) do
		if btn.dispose then btn:dispose() else host:removeChild(btn) end
	end
	if self.networkCombo then
		if self.networkCombo.dispose then self.networkCombo:dispose()
		else host:removeChild(self.networkCombo) end
	end
	self.linkTitle, self.noNetworksLbls, self.networkBtns, self.networkInfoLbls = nil, nil, {}, {}
	self.networkCombo, self.networkActionBtn = nil, nil
	local y = self:buildLinkSection(startY, textW)
	y = y + 6
	if self.statusLabel then
		self.statusLabel:setY(y)
	end
	y = y + FONT_HGT_SMALL + pad
	if self.contentBlock and self.contentBlock.setContentHeight then
		self.contentBlock:setContentHeight(y)
		self:reflow()
	end
end

--- Abre el diálogo. `target` = { x, y, z, object } del ordenador ya detectado.
---@param player IsoPlayer|nil
---@param target table
function GlobalStorageSiK.TerminalInstallReaderChoice.show(player, target)
	player = player or (GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer()) or getPlayer()
	if not player or not target then
		return
	end
	if GlobalStorageSiK.TerminalInstallReaderChoice.instance then
		GlobalStorageSiK.TerminalInstallReaderChoice.instance:destroy()
	end
	if GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.sendCommand then
		GlobalStorageSiK.NetClient.sendCommand("getRecoveryNetworks", {})
	end
	local playerNum = player.getPlayerNum and player:getPlayerNum() or 0
	local bounds = UI.Window.resolveBounds({ profile = WINDOW_PROFILE, playerNum = playerNum })
	local panelH = measurePanelHeight(networkRows(), bounds.w)
	local ui = GS_TerminalInstallReaderChoice:new(bounds.x, bounds.y, bounds.w, panelH)
	ui.player = player
	ui.playerNum = playerNum
	ui.target = target
	ui:initialise()
	UI.Modal.show(ui)
	GlobalStorageSiK.TerminalInstallReaderChoice.instance = ui
end

--- Refresca la lista de redes cuando llega la respuesta del servidor
--- (puede llegar despues de abrir el dialogo).
---@param rows table[]
function GlobalStorageSiK.TerminalInstallReaderChoice.onNetworksReceived(rows)
	local ui = GlobalStorageSiK.TerminalInstallReaderChoice.instance
	if not ui then
		return
	end
	ui.networkRows = rows or {}
	ui:rebuildLinkSection()
end
