--[[
	GlobalStorageSiK - Ventana "Conseguir PC"
	Descripción: Interfaz propia (no receta vanilla) para fabricar un
	Base.Mov_DesktopComputer a partir de las 4 piezas GS + manual leído.
	Accesible desde la ventana de bloqueo (sin terminal cerca) Y desde la
	pestaña Red (con terminal). Ver GS_PCAcquire.lua para la lógica/estado.
]]

require "ISUI/ISPanel"
require "ISUI/ISLabel"
require "GS_I18n"
require "GS_NetClient"
require "GS_PCAcquire"
require "GS_TerminalUI_Chrome"
require "TimedActions/GS_AcquirePCAction"

GlobalStorageSiK.PCAcquireUI = {}
GlobalStorageSiK.PCAcquireUI.instance = nil

local T = GlobalStorageSiK.I18n.text
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local FONT_HGT_MEDIUM = getTextManager():getFontHeight(UIFont.Medium)
local PAD = 14
local LINE_GAP = 4
local BTN_H = FONT_HGT_SMALL + 10
local PANEL_W = 640

GS_PCAcquireUI = ISPanel:derive("GS_PCAcquireUI")

---@return string[]
local function itemDisplayNames()
	local out = {}
	for i = 1, #GlobalStorageSiK.PCAcquire.REQUIRED_ITEMS do
		local ft = GlobalStorageSiK.PCAcquire.REQUIRED_ITEMS[i]
		out[i] = GlobalStorageSiK.I18n.typeDisplayName and GlobalStorageSiK.I18n.typeDisplayName(ft) or ft
	end
	return out
end

---@param player IsoPlayer|nil
---@return table[] lines { text=string, ok=boolean }
-- Item vanilla real usado solo para mostrar un icono representativo de
-- "cualquier destornillador" - la validacion real sigue siendo por tag
-- (GlobalStorageSiK.CraftUtils.hasScrewdriver), no por este tipo exacto.
local SCREWDRIVER_ICON_TYPE = "Base.Screwdriver"

local function buildStatusLines(player)
	local status = GlobalStorageSiK.PCAcquire.status(player)
	local lines = {}
	lines[#lines + 1] = {
		text = (status.manual and T("IGUI_GS_PCAcquireHasManual") or T("IGUI_GS_PCAcquireNeedManual")),
		ok = status.manual,
		icon = GlobalStorageSiK.PCAcquire.MANUAL_ITEM,
	}
	lines[#lines + 1] = {
		text = T("IGUI_GS_CraftSkillReqLine", status.skillHave or 0, status.skillRequired or 0),
		ok = status.skillOk,
		icon = Perks and Perks.Electricity and GlobalStorageSiK.CraftUtils.getPerkTexture(Perks.Electricity) or nil,
	}
	local names = itemDisplayNames()
	-- Orden alfabetico por nombre mostrado (idioma actual), no el orden fijo
	-- de REQUIRED_ITEMS - las listas vanilla (menu de crafteo) siempre
	-- ordenan alfabetico, y ver un orden distinto aqui da mala impresion aunque
	-- no tenga impacto funcional.
	local order = {}
	for i = 1, #GlobalStorageSiK.PCAcquire.REQUIRED_ITEMS do order[i] = i end
	table.sort(order, function(a, b) return string.lower(names[a]) < string.lower(names[b]) end)
	for _, i in ipairs(order) do
		local ft = GlobalStorageSiK.PCAcquire.REQUIRED_ITEMS[i]
		local has = status.items[ft]
		lines[#lines + 1] = {
			text = (has and T("IGUI_GS_PCAcquireHasItem", names[i]) or T("IGUI_GS_PCAcquireNeedItem", names[i])),
			ok = has,
			icon = ft,
		}
	end
	lines[#lines + 1] = {
		text = (status.tools.soldering and T("IGUI_GS_AcquireHasSolderingIron") or T("IGUI_GS_AcquireNeedSolderingIron")),
		ok = status.tools.soldering,
		icon = GlobalStorageSiK.CraftUtils.SOLDERING_IRON_TYPE,
	}
	lines[#lines + 1] = {
		text = (status.tools.screwdriver and T("IGUI_GS_AcquireHasScrewdriver") or T("IGUI_GS_AcquireNeedScrewdriver")),
		ok = status.tools.screwdriver,
		icon = SCREWDRIVER_ICON_TYPE,
	}
	return lines, status.allReady
end

function GS_PCAcquireUI:initialise()
	ISPanel.initialise(self)
	-- Mismo fondo que la ventana principal del terminal (GS_TerminalUI.lua),
	-- no el tono azulado que usaban antes las ventanas propias sueltas.
	self.backgroundColor = { r = 0.06, g = 0.06, b = 0.06, a = 0.98 }
	self.borderColor = { r = 0, g = 0, b = 0, a = 1 }
	self:setAlwaysOnTop(true)
	self.headerHeight = FONT_HGT_MEDIUM + PAD + LINE_GAP
	GlobalStorageSiK.TerminalChrome.setupModalPanel(self, function()
		self:destroy()
	end, PAD)
	self:buildLayout()
end

function GS_PCAcquireUI:destroy()
	GlobalStorageSiK.PCAcquireUI.instance = nil
	self:setVisible(false)
	if self.removeFromUIManager then
		self:removeFromUIManager()
	end
end

function GS_PCAcquireUI:onKeyRelease(key)
	if key == Keyboard.KEY_ESCAPE then
		self:destroy()
	end
end

--- (Re)construye todo el contenido a partir del estado actual. Se llama al
--- abrir y cada vez que cambia el inventario/se termina de leer el manual
--- mientras la ventana está abierta (ver ensureEvents más abajo).
function GS_PCAcquireUI:buildLayout()
	for i = #(self.childrenInOrder or {}), 1, -1 do
		local child = self.childrenInOrder[i]
		if child ~= self.closeBtn then
			self:removeChild(child)
			if child.removeFromUIManager then child:removeFromUIManager() end
		end
	end

	local pad = self.padding
	local textW = self.width - pad * 2
	local y = self.headerHeight + pad

	local introLines = GlobalStorageSiK.TerminalChrome.wrapTextLines(T("IGUI_GS_PCAcquireIntro"), textW, UIFont.Small)
	for _, line in ipairs(introLines) do
		local lbl = ISLabel:new(pad, y, FONT_HGT_SMALL, line, 0.75, 0.78, 0.82, 1, UIFont.Small, true)
		lbl:initialise()
		self:addChild(lbl)
		y = y + FONT_HGT_SMALL + 2
	end
	y = y + 6

	local lines, allReady = buildStatusLines(self.player)
	local sigParts = {}
	for _, spec in ipairs(lines) do
		sigParts[#sigParts + 1] = spec.ok and "1" or "0"
		y = GlobalStorageSiK.TerminalChrome.addRequirementLine(self, pad, y, textW, spec.icon, spec.text, spec.ok)
		y = y + 2
	end
	self._lastSig = table.concat(sigParts, "")
	y = y + 10

	self.craftBtn = GlobalStorageSiK.TerminalChrome.createNeatButton(pad, y, textW, BTN_H, T("IGUI_GS_PCAcquireCraftBtn"), self, function()
		if not self.player then return end
		-- Nunca deshabilitar: revalida en el momento del clic y avisa si
		-- falta algo, en vez de dejar el boton muerto sin explicacion.
		local _, ready = buildStatusLines(self.player)
		if not ready then
			if self.player.setHaloNote then
				self.player:setHaloNote(T("IGUI_GS_CraftMissing"), 220, 180, 100, 300)
			end
			return
		end
		ISTimedActionQueue.add(GS_AcquirePCAction:new(self.player))
		self:destroy()
	end)
	self:addChild(self.craftBtn)
	y = y + BTN_H + pad

	self:setHeight(y)
	GlobalStorageSiK.TerminalChrome.layoutModalChrome(self, pad)
	-- Centrar verticalmente SOLO la primera vez (apertura inicial): refresh()
	-- llama a buildLayout() cada vez que cambia el inventario (ej. al
	-- terminar de craftear una pieza), y sin esta guarda la ventana volvia
	-- a saltar al centro de la pantalla en cada refresco, perdiendo
	-- cualquier posicion a la que el jugador la hubiera arrastrado.
	if not self._positioned then
		self:setY(math.floor((getCore():getScreenHeight() - self.height) / 2))
		self._positioned = true
	end
	if GlobalStorageSiK.UIDebug and GlobalStorageSiK.UIDebug.enabled and GlobalStorageSiK.UIDebug.enabled() then
		GlobalStorageSiK.UIDebug.dumpTree(self, "PCAcquireUI")
		GlobalStorageSiK.UIDebug.checkOverlaps(self, "PCAcquireUI")
	end
end

--- Refresca sin reabrir (mientras la ventana esta abierta y algo cambia).
--- Coste bajo a propósito: compara una firma de los requisitos (3-4 bits) y
--- solo reconstruye si de verdad cambió algo, y nunca mientras el ratón está
--- pulsado (mismo fix que el panel bloqueado - reconstruir a mitad de un
--- clic pierde el clic sin avisar). Se llama tanto desde eventos puntuales
--- (inventario, receta aprendida) como desde un sondeo periódico de bajo
--- coste más abajo, para detectar "leíste la revista" sin tener que cerrar
--- y volver a abrir la ventana.
---@param force boolean|nil
function GS_PCAcquireUI:refresh(force)
	if not self.getIsVisible or not self:getIsVisible() then
		return
	end
	if not force and isMouseButtonDown and isMouseButtonDown(0) then
		self._refreshPending = true
		return
	end
	local lines = buildStatusLines(self.player)
	local sigParts = {}
	for i = 1, #lines do
		sigParts[#sigParts + 1] = lines[i].ok and "1" or "0"
	end
	local sig = table.concat(sigParts, "")
	if not force and sig == self._lastSig then
		return
	end
	self._lastSig = sig
	self._refreshPending = false
	self:buildLayout()
end

---@param player IsoPlayer|nil
function GlobalStorageSiK.PCAcquireUI.show(player)
	player = player or (GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer()) or getPlayer()
	if not player then
		return
	end
	if GlobalStorageSiK.PCAcquireUI.instance then
		GlobalStorageSiK.PCAcquireUI.instance:destroy()
	end
	local ui = GS_PCAcquireUI:new(0, 0, PANEL_W, 200)
	ui.player = player
	ui:initialise()
	ui:addToUIManager()
	GlobalStorageSiK.TerminalChrome.centerModal(ui)
	GlobalStorageSiK.TerminalChrome.finalizeModalShow(ui)
	GlobalStorageSiK.PCAcquireUI.instance = ui
end

local function onInventoryChanged()
	if GlobalStorageSiK.PCAcquireUI.instance then
		GlobalStorageSiK.PCAcquireUI.instance:refresh()
	end
end

--- La receta se aprende por el mecanismo vanilla (LearnedRecipes del manual,
--- ver GS_PCAcquire.RECIPE_NAME) - aqui solo refrescamos la ventana si esta
--- abierta cuando el juego dispara cualquiera de los eventos de "receta
--- aprendida" disponibles (varian segun version/mod, de ahi probar varios).
local function onRecipeLearned()
	if GlobalStorageSiK.PCAcquireUI.instance then
		GlobalStorageSiK.PCAcquireUI.instance:refresh()
	end
end

-- Sondeo periódico de bajo coste (respaldo por si el evento de "receta
-- aprendida" del motor no dispara para este caso concreto): cada
-- REFRESH_TICKS ticks, con la ventana visible, refresh() ya se encarga de no
-- hacer nada si la firma no cambió. Sin esto, leer la revista solo se
-- detectaría si además coincide con un OnContainerUpdate.
local REFRESH_TICKS = 30
local function onTick()
	local ui = GlobalStorageSiK.PCAcquireUI.instance
	if not ui or not ui.getIsVisible or not ui:getIsVisible() then
		return
	end
	ui._tick = (ui._tick or 0) + 1
	if ui._refreshPending or (ui._tick % REFRESH_TICKS == 0) then
		ui:refresh()
	end
end

if Events then
	if Events.OnContainerUpdate then
		Events.OnContainerUpdate.Add(onInventoryChanged)
	end
	local recipeLearnEvents = { "OnPlayerLearnRecipe", "OnLearnRecipe", "OnRecipeLearned", "OnNewRecipe" }
	for i = 1, #recipeLearnEvents do
		local ev = Events[recipeLearnEvents[i]]
		if ev and ev.Add then
			ev.Add(onRecipeLearned)
		end
	end
	if Events.OnTick then
		Events.OnTick.Add(onTick)
	end
end
