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

require "ISUI/ISPanel"
require "ISUI/ISLabel"
require "ISUI/ISTextEntryBox"
require "GS_I18n"
require "GS_NetClient"
require "GS_TerminalAccess"
require "GS_TerminalUI_Chrome"
require "GS_Config"
require "GS_Sandbox"

GlobalStorageSiK.TerminalInstallReaderChoice = {}
GlobalStorageSiK.TerminalInstallReaderChoice.instance = nil

local T = GlobalStorageSiK.I18n.text
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local FONT_HGT_MEDIUM = getTextManager():getFontHeight(UIFont.Medium)
local PAD = 14
local LINE_GAP = 4
local BTN_H = FONT_HGT_SMALL + 10
local ENTRY_H = FONT_HGT_SMALL + 8
local PANEL_W = 480
local SECTION_GAP = 16
local NETWORK_ROW_MAX = 6

GS_TerminalInstallReaderChoice = ISPanel:derive("GS_TerminalInstallReaderChoice")

---@return table[]
local function networkRows()
	local serverList = GlobalStorageSiK.Client and GlobalStorageSiK.Client.recoveryNetworks
	return serverList or {}
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
local function addWrappedLabel(panel, x, y, w, text, r, g, b)
	local labels = {}
	local lines = GlobalStorageSiK.TerminalChrome.wrapTextLines(text, w, UIFont.Small)
	for i = 1, #lines do
		local lbl = ISLabel:new(x, y, FONT_HGT_SMALL, lines[i], r, g, b, 1, UIFont.Small, true)
		lbl:initialise()
		panel:addChild(lbl)
		labels[#labels + 1] = lbl
		y = y + FONT_HGT_SMALL + LINE_GAP
	end
	return labels, y
end

---@param rows table[]
---@return number
local function measurePanelHeight(rows)
	local textW = PANEL_W - PAD * 2
	local introLines = GlobalStorageSiK.TerminalChrome.wrapTextLines(
		T("IGUI_GS_InstallReaderIntro", GlobalStorageSiK.Sandbox.getTerminalNetworkRange()),
		textW, UIFont.Small)
	local h = PAD
	h = h + FONT_HGT_MEDIUM + LINE_GAP
	h = h + #introLines * (FONT_HGT_SMALL + LINE_GAP) + PAD
	-- Bloque "Red nueva": titulo + entry+boton
	h = h + FONT_HGT_SMALL + 4 + ENTRY_H + SECTION_GAP
	-- Separador
	h = h + 1 + SECTION_GAP
	-- Bloque "Red existente": titulo + N filas, o el aviso "sin redes" (con
	-- ajuste de linea - puede ocupar mas de 1 linea segun idioma/longitud).
	h = h + FONT_HGT_SMALL + 6
	if #rows == 0 then
		local noNetLines = GlobalStorageSiK.TerminalChrome.wrapTextLines(
			T("IGUI_GS_InstallReaderNoNetworks"), textW, UIFont.Small)
		h = h + #noNetLines * (FONT_HGT_SMALL + LINE_GAP) + 4
	else
		local rowCount = math.min(#rows, NETWORK_ROW_MAX)
		h = h + rowCount * (BTN_H + 6)
	end
	h = h + PAD
	return math.max(320, h)
end

function GS_TerminalInstallReaderChoice:initialise()
	ISPanel.initialise(self)
	-- Mismo fondo neutro que la ventana principal del terminal y las de
	-- Conseguir PC/Fabricar lector (GS_PCAcquireUI.lua/GS_ReaderAcquireUI.lua):
	-- el valor anterior (0.08, 0.09, 0.11) tenia el azul mas alto que el
	-- rojo/verde, un tinte azulado sutil pero visible frente al resto de
	-- nuestras ventanas, que son gris neutro.
	self.backgroundColor = { r = 0.06, g = 0.06, b = 0.06, a = 0.98 }
	self.borderColor = { r = 0.35, g = 0.38, b = 0.42, a = 0.95 }
	self:setAlwaysOnTop(true)
	self.headerHeight = FONT_HGT_MEDIUM + PAD + LINE_GAP
	GlobalStorageSiK.TerminalChrome.setupModalPanel(self, function()
		self:destroy()
	end, PAD)
	self.statusMsg = nil
	self.busy = false
	self:buildLayout()
end

function GS_TerminalInstallReaderChoice:destroy()
	GlobalStorageSiK.TerminalInstallReaderChoice.instance = nil
	self:setVisible(false)
	if self.removeFromUIManager then
		self:removeFromUIManager()
	end
end

function GS_TerminalInstallReaderChoice:onKeyRelease(key)
	if key == Keyboard.KEY_ESCAPE then
		self:destroy()
		return true
	end
	return ISPanel.onKeyRelease(self, key)
end

---@param msg string
function GS_TerminalInstallReaderChoice:setStatus(msg)
	self.statusMsg = msg
	if self.statusLabel then
		self.statusLabel.name = msg or ""
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
	local pad = PAD
	local rows = self.networkRows or {}

	self.linkTitle = ISLabel:new(pad, y, FONT_HGT_SMALL, T("IGUI_GS_InstallReaderLinkTitle"), 0.88, 0.9, 0.94, 1, UIFont.Small, true)
	self.linkTitle:initialise()
	self:addChild(self.linkTitle)
	y = y + FONT_HGT_SMALL + 6

	self.networkBtns = {}
	if #rows == 0 then
		self.noNetworksLbls, y = addWrappedLabel(self, pad, y, textW, T("IGUI_GS_InstallReaderNoNetworks"), 0.7, 0.55, 0.4)
		y = y + 4
	else
		for i = 1, #rows do
			local row = rows[i]
			local btn = GlobalStorageSiK.TerminalChrome.createNeatButton(
				pad, y, textW, BTN_H, row.label or row.networkId, self, function()
					self:onLinkTo(row)
				end)
			self:addChild(btn)
			self.networkBtns[#self.networkBtns + 1] = btn
			y = y + BTN_H + 6
		end
	end
	return y
end

function GS_TerminalInstallReaderChoice:buildLayout()
	local pad = PAD
	local y = pad
	local textW = self.width - pad * 2

	local title = ISLabel:new(pad, y, FONT_HGT_MEDIUM, T("IGUI_GS_InstallReaderTitle"), 0.95, 0.95, 0.95, 1, UIFont.Medium, true)
	title:initialise()
	self:addChild(title)
	y = y + FONT_HGT_MEDIUM + LINE_GAP

	local introLabels = {}
	local linkRange = GlobalStorageSiK.Sandbox.getTerminalNetworkRange()
	local introLines = GlobalStorageSiK.TerminalChrome.wrapTextLines(
		T("IGUI_GS_InstallReaderIntro", linkRange), textW, UIFont.Small)
	for i = 1, #introLines do
		local lbl = ISLabel:new(pad, y, FONT_HGT_SMALL, introLines[i], 0.78, 0.82, 0.88, 1, UIFont.Small, true)
		lbl:initialise()
		self:addChild(lbl)
		introLabels[#introLabels + 1] = lbl
		y = y + FONT_HGT_SMALL + LINE_GAP
	end
	y = y + 6

	-- ── Bloque "Red nueva": nombre + Crear, un solo clic ────────────────────
	self.newTitle = ISLabel:new(pad, y, FONT_HGT_SMALL, T("IGUI_GS_InstallReaderNewTitle"), 0.88, 0.9, 0.94, 1, UIFont.Small, true)
	self.newTitle:initialise()
	self:addChild(self.newTitle)
	y = y + FONT_HGT_SMALL + 4

	local createW = GlobalStorageSiK.TerminalChrome.measureNeatButtonWidth(
		T("IGUI_GS_InstallReaderCreateBtn"), UIFont.Small, 14, 100, math.floor(textW * 0.4))
	self.nameEntry = ISTextEntryBox:new(T("IGUI_GS_InstallReaderNameDefault"), pad, y, textW - createW - 6, ENTRY_H)
	self.nameEntry:initialise()
	GlobalStorageSiK.TerminalChrome.styleTextEntry(self.nameEntry)
	self.nameEntry:instantiate()
	self:addChild(self.nameEntry)

	self.createBtn = GlobalStorageSiK.TerminalChrome.createNeatButton(
		pad + textW - createW, y, createW, ENTRY_H, T("IGUI_GS_InstallReaderCreateBtn"), self, function()
			self:onCreateNew()
		end)
	self:addChild(self.createBtn)
	y = y + ENTRY_H + SECTION_GAP

	-- ── Separador visual entre los dos bloques ──────────────────────────────
	self.sepLine = ISPanel:new(pad, y, textW, 1)
	self.sepLine:initialise()
	self.sepLine.backgroundColor = { r = 0.3, g = 0.32, b = 0.36, a = 0.6 }
	self:addChild(self.sepLine)
	y = y + 1 + SECTION_GAP

	-- ── Bloque "Red existente": una red por fila, un solo clic ──────────────
	self.networkRows = networkRows()
	y = self:buildLinkSection(y, textW)
	y = y + 6

	self.statusLabel = ISLabel:new(pad, y, FONT_HGT_SMALL, self.statusMsg or "", 0.95, 0.75, 0.35, 1, UIFont.Small, true)
	self.statusLabel:initialise()
	self:addChild(self.statusLabel)
	y = y + FONT_HGT_SMALL + pad

	self:setHeight(y)
	GlobalStorageSiK.TerminalChrome.setMouseTransparentAll(introLabels)
	GlobalStorageSiK.TerminalChrome.makeMousePassthrough(title)
	GlobalStorageSiK.TerminalChrome.makeMousePassthrough(self.statusLabel)
	GlobalStorageSiK.TerminalChrome.makeMousePassthrough(self.newTitle)
	GlobalStorageSiK.TerminalChrome.makeMousePassthrough(self.linkTitle)
	GlobalStorageSiK.TerminalChrome.setMouseTransparentAll(self.noNetworksLbls or {})
	if GlobalStorageSiK.UIDebug and GlobalStorageSiK.UIDebug.enabled and GlobalStorageSiK.UIDebug.enabled() then
		GlobalStorageSiK.UIDebug.dumpTree(self, "TerminalInstallReaderChoice")
		GlobalStorageSiK.UIDebug.checkOverlaps(self, "TerminalInstallReaderChoice")
	end
end

--- Reconstruye solo el bloque "Red existente" al llegar datos del servidor
--- (mantiene el nombre ya escrito en el campo "Red nueva").
function GS_TerminalInstallReaderChoice:rebuildLinkSection()
	local pad = PAD
	local textW = self.width - pad * 2
	local startY = self.sepLine and (self.sepLine:getY() + 1 + SECTION_GAP) or nil
	if not startY then
		return
	end
	local toRemove = { self.linkTitle }
	for _, lbl in ipairs(self.noNetworksLbls or {}) do
		toRemove[#toRemove + 1] = lbl
	end
	for _, w in ipairs(toRemove) do
		if w then
			self:removeChild(w)
			if w.removeFromUIManager then w:removeFromUIManager() end
		end
	end
	for _, btn in ipairs(self.networkBtns or {}) do
		self:removeChild(btn)
		if btn.removeFromUIManager then btn:removeFromUIManager() end
	end
	self.linkTitle, self.noNetworksLbls, self.networkBtns = nil, nil, {}
	local y = self:buildLinkSection(startY, textW)
	y = y + 6
	if self.statusLabel then
		self.statusLabel:setY(y)
	end
	y = y + FONT_HGT_SMALL + pad
	self:setHeight(y)
	GlobalStorageSiK.TerminalChrome.makeMousePassthrough(self.linkTitle)
	GlobalStorageSiK.TerminalChrome.setMouseTransparentAll(self.noNetworksLbls or {})
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
	local panelH = measurePanelHeight(networkRows())
	local ui = GS_TerminalInstallReaderChoice:new(0, 0, PANEL_W, panelH)
	ui.player = player
	ui.target = target
	ui:initialise()
	ui:addToUIManager()
	GlobalStorageSiK.TerminalChrome.centerModal(ui)
	GlobalStorageSiK.TerminalChrome.finalizeModalShow(ui)
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
