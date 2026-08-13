--[[
	GlobalStorageSiK - Ventana "Fabricar lector" (SiK Disk Reader)
	Descripción: Interfaz propia (no receta vanilla) para montar un SiK Disk
	Reader a partir de sus 3 piezas GS + manual leído. Accesible desde la
	ventana de bloqueo cuando falta el lector, junto al botón "Instalar
	aquí". Ver GS_ReaderAcquire.lua para la lógica/estado. Mismo patrón que
	GS_PCAcquireUI.lua, incluido el refresco en vivo de bajo coste.
]]

require "ISUI/ISPanel"
require "ISUI/ISLabel"
require "GS_I18n"
require "GS_NetClient"
require "GS_ReaderAcquire"
require "GS_TerminalUI_Chrome"
require "TimedActions/GS_AcquireReaderAction"

GlobalStorageSiK.ReaderAcquireUI = {}
GlobalStorageSiK.ReaderAcquireUI.instance = nil

local T = GlobalStorageSiK.I18n.text
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local FONT_HGT_MEDIUM = getTextManager():getFontHeight(UIFont.Medium)
local PAD = 14
local LINE_GAP = 4
local BTN_H = FONT_HGT_SMALL + 10
local PANEL_W = 640

GS_ReaderAcquireUI = ISPanel:derive("GS_ReaderAcquireUI")

---@return string[]
local function itemDisplayNames()
	local out = {}
	for i = 1, #GlobalStorageSiK.ReaderAcquire.REQUIRED_ITEMS do
		local ft = GlobalStorageSiK.ReaderAcquire.REQUIRED_ITEMS[i]
		out[i] = GlobalStorageSiK.I18n.typeDisplayName and GlobalStorageSiK.I18n.typeDisplayName(ft) or ft
	end
	return out
end

-- Item vanilla real usado solo para mostrar un icono representativo de
-- "cualquier destornillador" - la validacion real sigue siendo por tag
-- (GlobalStorageSiK.CraftUtils.hasScrewdriver), no por este tipo exacto.
local SCREWDRIVER_ICON_TYPE = "Base.Screwdriver"

---@param player IsoPlayer|nil
---@return table[] lines { text=string, ok=boolean, icon=string|nil }
local function buildStatusLines(player)
	local status = GlobalStorageSiK.ReaderAcquire.status(player)
	local lines = {}
	lines[#lines + 1] = {
		text = (status.manual and T("IGUI_GS_ReaderAcquireHasManual") or T("IGUI_GS_ReaderAcquireNeedManual")),
		ok = status.manual,
		icon = GlobalStorageSiK.ReaderAcquire.MANUAL_ITEM,
	}
	lines[#lines + 1] = {
		text = T("IGUI_GS_CraftSkillReqLine", status.skillHave or 0, status.skillRequired or 0),
		ok = status.skillOk,
		icon = Perks and Perks.Electricity and GlobalStorageSiK.CraftUtils.getPerkTexture(Perks.Electricity) or nil,
	}
	local names = itemDisplayNames()
	-- Orden alfabetico por nombre mostrado (idioma actual), no el orden fijo
	-- de REQUIRED_ITEMS - misma razon que GS_PCAcquireUI.lua: las listas
	-- vanilla siempre ordenan alfabetico, un orden distinto aqui da mala
	-- impresion aunque no tenga impacto funcional.
	local order = {}
	for i = 1, #GlobalStorageSiK.ReaderAcquire.REQUIRED_ITEMS do order[i] = i end
	table.sort(order, function(a, b) return string.lower(names[a]) < string.lower(names[b]) end)
	for _, i in ipairs(order) do
		local ft = GlobalStorageSiK.ReaderAcquire.REQUIRED_ITEMS[i]
		local has = status.items[ft]
		lines[#lines + 1] = {
			text = (has and T("IGUI_GS_ReaderAcquireHasItem", names[i]) or T("IGUI_GS_ReaderAcquireNeedItem", names[i])),
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

function GS_ReaderAcquireUI:initialise()
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

function GS_ReaderAcquireUI:destroy()
	GlobalStorageSiK.ReaderAcquireUI.instance = nil
	self:setVisible(false)
	if self.removeFromUIManager then
		self:removeFromUIManager()
	end
end

function GS_ReaderAcquireUI:onKeyRelease(key)
	if key == Keyboard.KEY_ESCAPE then
		self:destroy()
	end
end

--- (Re)construye todo el contenido a partir del estado actual.
function GS_ReaderAcquireUI:buildLayout()
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

	local introLines = GlobalStorageSiK.TerminalChrome.wrapTextLines(T("IGUI_GS_ReaderAcquireIntro"), textW, UIFont.Small)
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

	self.craftBtn = GlobalStorageSiK.TerminalChrome.createNeatButton(pad, y, textW, BTN_H, T("IGUI_GS_ReaderAcquireCraftBtn"), self, function()
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
		ISTimedActionQueue.add(GS_AcquireReaderAction:new(self.player))
		self:destroy()
	end)
	self:addChild(self.craftBtn)
	y = y + BTN_H + pad

	self:setHeight(y)
	GlobalStorageSiK.TerminalChrome.layoutModalChrome(self, pad)
	-- Centrar verticalmente SOLO la primera vez (apertura inicial): ver
	-- comentario equivalente en GS_PCAcquireUI.lua:buildLayout(). Mismo bug,
	-- mismo fix - refresh() reconstruia el layout en cada cambio de
	-- inventario y la ventana saltaba al centro, perdiendo la posicion
	-- arrastrada por el jugador.
	if not self._positioned then
		self:setY(math.floor((getCore():getScreenHeight() - self.height) / 2))
		self._positioned = true
	end
	if GlobalStorageSiK.UIDebug and GlobalStorageSiK.UIDebug.enabled and GlobalStorageSiK.UIDebug.enabled() then
		GlobalStorageSiK.UIDebug.dumpTree(self, "ReaderAcquireUI")
		GlobalStorageSiK.UIDebug.checkOverlaps(self, "ReaderAcquireUI")
	end
end

--- Refresca sin reabrir. Mismas guardas que GS_PCAcquireUI:refresh() - firma
--- de requisitos (evita reconstruir si no cambió nada) y nunca reconstruir
--- con el ratón pulsado.
---@param force boolean|nil
function GS_ReaderAcquireUI:refresh(force)
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
function GlobalStorageSiK.ReaderAcquireUI.show(player)
	player = player or (GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer()) or getPlayer()
	if not player then
		return
	end
	if GlobalStorageSiK.ReaderAcquireUI.instance then
		GlobalStorageSiK.ReaderAcquireUI.instance:destroy()
	end
	local ui = GS_ReaderAcquireUI:new(0, 0, PANEL_W, 200)
	ui.player = player
	ui:initialise()
	ui:addToUIManager()
	ui:setX(math.floor((getCore():getScreenWidth() - PANEL_W) / 2))
	GlobalStorageSiK.TerminalChrome.finalizeModalShow(ui)
	GlobalStorageSiK.ReaderAcquireUI.instance = ui
end

local function onInventoryChanged()
	if GlobalStorageSiK.ReaderAcquireUI.instance then
		GlobalStorageSiK.ReaderAcquireUI.instance:refresh()
	end
end

local function onRecipeLearned()
	if GlobalStorageSiK.ReaderAcquireUI.instance then
		GlobalStorageSiK.ReaderAcquireUI.instance:refresh()
	end
end

local REFRESH_TICKS = 30
local function onTick()
	local ui = GlobalStorageSiK.ReaderAcquireUI.instance
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
