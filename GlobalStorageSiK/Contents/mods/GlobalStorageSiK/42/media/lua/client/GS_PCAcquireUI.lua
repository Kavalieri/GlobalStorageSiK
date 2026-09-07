--[[
	GlobalStorageSiK - Ventana "Conseguir PC"
	Descripción: Interfaz propia (no receta vanilla) para fabricar un
	Base.Mov_DesktopComputer a partir de las 4 piezas GS + manual leído.
	Accesible desde la ventana de bloqueo (sin terminal cerca) Y desde la
	pestaña Red (con terminal). Ver GS_PCAcquire.lua para la lógica/estado.
]]

require "GS_I18n"
require "GS_NetClient"
require "GS_Sandbox"
require "GS_PCAcquire"
local UI = require "GS_UI_Framework"
require "TimedActions/GS_AcquirePCAction"

GlobalStorageSiK.PCAcquireUI = {}
GlobalStorageSiK.PCAcquireUI.instance = nil

local T = GlobalStorageSiK.I18n.text
local PAD = 14
local BLOCK_GAP = 8
local CONTROL_METRICS = UI.Controls.metrics("task")
local PANEL_W = math.max(UI.Modal.STANDARD_MODAL_W, 640)

GS_PCAcquireUI = UI.Window.derive("GS_PCAcquireUI")

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
		text = T("IGUI_GS_ProgrammingRecipeRequirement", GlobalStorageSiK.I18n.typeDisplayName(GlobalStorageSiK.PCAcquire.MANUAL_ITEM)),
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
	UI.Window.callBase(self, "initialise")
	-- Mismo fondo que la ventana principal del terminal (GS_TerminalUI.lua),
	-- no el tono azulado que usaban antes las ventanas propias sueltas.
	self.backgroundColor = { r = 0.06, g = 0.06, b = 0.06, a = 0.98 }
	self.borderColor = { r = 0, g = 0, b = 0, a = 1 }
	UI.Modal.apply(self, {
		kind = "task", padding = PAD, playerNum = self.playerNum,
		owner = self.modalOwner, resizable = false,
		title = T("IGUI_GS_PCAcquireOpenBtn"),
		onClose = function()
			GlobalStorageSiK.PCAcquireUI.instance = nil
		end,
	})
	self:buildLayout()
end

function GS_PCAcquireUI:destroy()
	GlobalStorageSiK.PCAcquireUI.instance = nil
	if self._sikWindowApplied and not self._sikDisposed then
		UI.Modal.close(self, "destroy")
	elseif self.removeFromUIManager then self:removeFromUIManager() end
end

local function clearContent(panel)
	for i = #(panel._contentWidgets or {}), 1, -1 do
		local child = panel._contentWidgets[i]
		if child and child.dispose then child:dispose()
		elseif child then
			panel:removeChild(child)
			if child.removeFromUIManager then child:removeFromUIManager() end
		end
	end
	panel._contentWidgets = {}
end

local function own(panel, child)
	panel._contentWidgets[#panel._contentWidgets + 1] = child
	return child
end

local function requirementTexture(icon)
	if type(icon) == "string" and GlobalStorageSiK.CraftUtils
	and GlobalStorageSiK.CraftUtils.getItemIconTexture then
		return GlobalStorageSiK.CraftUtils.getItemIconTexture(icon)
	end
	return icon
end

local function requirementsSignature(lines)
	local parts = {}
	for _, spec in ipairs(lines) do
		parts[#parts + 1] = table.concat({ spec.text or "", spec.ok and "1" or "0" }, "|")
	end
	return table.concat(parts, "")
end

--- (Re)construye todo el contenido a partir del estado actual. Se llama al
--- abrir y cada vez que cambia el inventario/se termina de leer el manual
--- mientras la ventana está abierta (ver ensureEvents más abajo).
function GS_PCAcquireUI:buildLayout()
	clearContent(self)
	local host = self.contentHost or self
	local rect = { x = 0, y = 0, w = host.width or 0, h = host.height or 0 }
	local textW = rect.w
	local requirements = own(self, UI.Block.create({
		parent = host, x = rect.x, y = rect.y, w = textW,
		title = T("IGUI_GS_AcquireRequirements"),
		tooltip = not GlobalStorageSiK.Sandbox.isSolderingIronCraftEnabled()
			and T("IGUI_GS_SolderingIronFindHint") or T("IGUI_GS_AcquireRequirements"), playerNum = self.playerNum,
	}))
	local requirementColumn = requirements:beginColumn()

	local lines, allReady = buildStatusLines(self.player)
	local reqRect = requirements:getContentRect()
	local function row(spec) return { text = spec.text, texture = requirementTexture(spec.icon),
		tone = spec.ok and "success" or "danger" } end
	local groups = { { rows = { row(lines[1]), row(lines[2]), row(lines[#lines - 1]), row(lines[#lines]) } },
		{ rows = {} } }
	for i = 3, #lines - 2 do groups[2].rows[#groups[2].rows + 1] = row(lines[i]) end
	self.requirementsHandle = UI.Requirements.create({ parent = requirementColumn.parent,
		x = 0, y = 0, w = reqRect.w, groups = groups, playerNum = self.playerNum })
	requirementColumn:block(self.requirementsHandle.panel, self.requirementsHandle.height)
	self._lastSig = requirementsSignature(lines)
	self._layoutWidth = textW

	requirementColumn:finish()

	local actions = own(self, UI.Block.create({
		parent = host, x = rect.x, y = requirements.y + requirements.h + BLOCK_GAP,
		w = textW, title = T("IGUI_GS_PermColActions"),
		tooltip = T("IGUI_GS_PermColActions"), playerNum = self.playerNum,
	}))
	local actionColumn = actions:beginColumn()

	-- Decision revertida (2026-08-26, pedido explicito del usuario, mismo
	-- criterio aplicado a Programacion/disquetera): antes el boton se dejaba
	-- SIEMPRE activo y solo avisaba con un halo note al pulsar si faltaba
	-- algo - no era ni ancho completo (sin fullWidth, se encogia al texto)
	-- ni "claramente bloqueado". Ahora ocupa toda la fila y se pinta
	-- bloqueado de verdad mientras falte cualquier requisito, con el motivo
	-- en el tooltip - la revalidacion en el momento del clic deja de hacer
	-- falta porque un boton bloqueado no puede pulsarse.
	self.craftBtn = UI.Controls.button(actionColumn.parent, {
		x = 0, y = 0, w = textW, h = CONTROL_METRICS.buttonHeight,
		text = T("IGUI_GS_PCAcquireCraftBtn"), fullWidth = true,
		enabled = allReady, locked = not allReady,
		tooltip = not allReady and T("IGUI_GS_CraftMissing") or nil,
		playerNum = self.playerNum, onClick = function()
		if not self.player then return end
		ISTimedActionQueue.add(GS_AcquirePCAction:new(self.player))
		self:destroy()
	end,
	})
	actionColumn:block(self.craftBtn, CONTROL_METRICS.buttonHeight)
	actionColumn:finish()

	-- fitContent resuelve el viewport una vez; los refrescos conservan la
	-- posicion a la que el jugador haya arrastrado la ventana.
	local previousX = self:getX()
	local previousY = self:getY()
	local wasPositioned = self._positioned == true
	UI.Modal.fitContent(self, actions.y + actions.h, {
		contentBottom = true, bottomPadding = 0, center = not wasPositioned,
	})
	if wasPositioned then
		self:setX(previousX)
		self:setY(previousY)
	else
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
	local sig = requirementsSignature(lines)
	local host = self.contentHost or self
	local widthChanged = self._layoutWidth ~= (host.width or 0)
	if not force and not widthChanged and sig == self._lastSig then
		return
	end
	self._lastSig = sig
	self._refreshPending = false
	self:buildLayout()
end

---@param player IsoPlayer|nil
---@param owner ISPanel|nil
function GlobalStorageSiK.PCAcquireUI.show(player, owner)
	player = player or (GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer()) or getPlayer()
	if not player then
		return
	end
	if GlobalStorageSiK.PCAcquireUI.instance then
		GlobalStorageSiK.PCAcquireUI.instance:destroy()
	end
	local ui = GS_PCAcquireUI:new(0, 0, PANEL_W, 200)
	ui.player = player
	ui.playerNum = player.getPlayerNum and player:getPlayerNum() or 0
	ui.modalOwner = owner
	ui:initialise()
	if owner then UI.Modal.presentChild(owner, ui)
	else UI.Modal.show(ui) end
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
