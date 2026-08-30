--[[
	GlobalStorageSiK - Pestaña Programación del terminal
	Autor: SiK
	Fecha: 2026-08-12
	Descripción: Graba disquetes (red, desinstalación, instalación de
	disquetera, y los que registren otros addons) desde el terminal, sin
	necesidad de cargar la disquetera encima. Solo visible si el periférico
	Reader está instalado en esta red - si no lo está, la vía existente sigue
	intacta: clic derecho en el disquete en blanco + disquetera encima + rango
	de un terminal (ver GS_ItemActions.lua / GS_ProgramDiskAction.lua), NO
	tocada por este fichero.
]]

require "ISUI/ISPanel"
require "ISUI/ISLabel"
require "GS_I18n"
require "GS_TerminalUI_Scroll"
require "GS_SiK_UI_Core"
require "GS_SiK_UI_Controls"
require "GS_DiskProgramming"
require "GS_CraftUtils"
require "GS_NetClient"

GlobalStorageSiK.TerminalProgramming = GlobalStorageSiK.TerminalProgramming or {}

local T = GlobalStorageSiK.I18n.text
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local CONTENT_PAD = 8
local BLOCK_GAP = 8
local BTN_H = GlobalStorageSiK.SiK_UI.Controls.metrics("standard").buttonHeight

-- Orden estable de programas conocidos por el Core; cualquier otro que un
-- addon registre via DiskProgramming.registerProgram() se añade detrás, en
-- el orden en que aparezca al iterar (no crítico, son pocos).
local KNOWN_PROGRAM_ORDER = { "network", "uninstall", "driveinstall" }

---@return table[] ids en orden estable
local function orderedProgramIds()
	local out = {}
	local seen = {}
	for i = 1, #KNOWN_PROGRAM_ORDER do
		local id = KNOWN_PROGRAM_ORDER[i]
		if GlobalStorageSiK.DiskProgramming.PROGRAMS[id] then
			out[#out + 1] = id
			seen[id] = true
		end
	end
	for id in pairs(GlobalStorageSiK.DiskProgramming.PROGRAMS) do
		if not seen[id] then
			out[#out + 1] = id
			seen[id] = true
		end
	end
	return out
end

local function addWrappedLabel(scroll, x, y, text, maxW, r, g, b)
	local lines = GlobalStorageSiK.SiK_UI.wrapTextLines(text, maxW, UIFont.Small)
	for i = 1, #lines do
		local lbl = ISLabel:new(x, y, FONT_HGT_SMALL, lines[i], r, g, b, 1, UIFont.Small, true)
		lbl:initialise()
		GlobalStorageSiK.TerminalScroll.addChild(scroll, lbl)
		y = y + FONT_HGT_SMALL + 2
	end
	return y
end

-- Icono grande de la tarjeta de cada programa (pedido explicito 2026-08-21:
-- "tarjetas" visuales con el icono de su disquete correspondiente). Panel
-- propio con prerender, mismo patron que GS_TerminalUI_AddonBay.lua para el
-- icono del periferico - drawTextureScaledAspect conserva proporcion, nunca
-- deforma un icono cuadrado en un hueco no cuadrado.
local ICON_SIZE = 40
local function addProgramIcon(scroll, x, y, iconPath, size)
	size = size or ICON_SIZE
	local icon = ISPanel:new(x, y, size, size)
	icon:initialise()
	icon.drawBackground = false
	icon.prerender = function(panel)
		ISPanel.prerender(panel)
		local tex = iconPath and getTexture(iconPath) or nil
		if tex then
			panel:drawTextureScaledAspect(tex, 0, 0, panel.width, panel.height, 1, 1, 1, 1)
		end
	end
	GlobalStorageSiK.TerminalScroll.addChild(scroll, icon)
end

--- Cuenta disquetes en blanco accesibles ahora mismo (inventario del
--- jugador + contenedores de ingredientes cercanos, mismo criterio que
--- programReadiness/hasDisk) - a diferencia de findItemTypeNearby (solo
--- existencia), este recorrido suma unidades reales para el contador
--- "X/Y" pedido explicitamente (2026-08-23: el requisito de disquete en
--- blanco no quedaba claro, solo un texto de aviso sin cantidad).
---@param player IsoPlayer|nil
---@return number
local function countBlankDisksNearby(player)
	if not player or not GlobalStorageSiK.CraftUtils.collectIngredientContainers then
		return 0
	end
	local containers = GlobalStorageSiK.CraftUtils.collectIngredientContainers(player)
	local total = 0
	for i = 1, #containers do
		local ok, count = pcall(function()
			return containers[i]:getItemCountRecurse(GlobalStorageSiK.DiskProgramming.BLANK_DISK)
		end)
		if ok and count then
			total = total + count
		end
	end
	return total
end

--- Bloque de cabecera (pedido explicito 2026-08-23): antes cada tarjeta de
--- programa repetia "requiere el periferico instalado" pese a que la
--- pestaña Programacion SOLO es visible si ya esta instalado (syncTabVisibility
--- mas abajo) - mensaje redundante y confuso. Ahora un unico bloque arriba
--- de todo confirma el estado real una sola vez (icono + linea verde,
--- siempre verde porque si no lo estuviera esta pestaña ni existiria) y
--- añade el contador de disquetes en blanco disponibles ahora mismo.
--- Enmarcado en su propia tarjeta (pedido explicito 2026-08-23: "separar
--- claramente el bloque de requisitos globales... del resto de
--- programaciones de disquetes individuales, enmarcarlos, dividir con algún
--- separador") - mismo componente `createSectionCard`/`resizeSectionCard`
--- que ya usa GS_AddonManageUI.lua para requisitos de instalación, así que
--- sigue el mismo lenguaje visual del resto del terminal, no uno nuevo.
---@param scroll table
---@param x number
---@param y number
---@param innerW number
---@param player IsoPlayer|nil
---@return number nextY
local function addStatusHeader(scroll, x, y, innerW, player)
	local blankCount = countBlankDisksNearby(player)
	local text = T("IGUI_GS_ProgrammingReaderInstalled") .. " · "
		.. T("IGUI_GS_ProgrammingBlankDiskCount", tostring(blankCount), "1")
	local feedback = GlobalStorageSiK.SiK_UI.Controls.feedback(nil, {
		x = x, y = y, w = math.max(80, innerW - x * 2), text = text,
		kind = blankCount > 0 and "success" or "warning",
	})
	GlobalStorageSiK.TerminalScroll.addChild(scroll, feedback)
	return y + feedback.height
end

local function addSectionTitle(scroll, x, y, titleKey, innerW)
	local title = T(titleKey)
	local titleH = GlobalStorageSiK.SiK_UI.Controls.metrics("standard").sectionHeight
	local hdr = GlobalStorageSiK.SiK_UI.Controls.sectionTitle(nil, {
		x = x, y = y, text = title,
	})
	GlobalStorageSiK.TerminalScroll.addChild(scroll, hdr)
	return y + titleH
end

---@param panel ISPanel
---@param terminal GS_TerminalUI
function GlobalStorageSiK.TerminalProgramming.buildPanel(panel, terminal)
	if panel.programmingBuilt then
		return
	end
	panel.programmingBuilt = true
	panel.drawBackground = false
	panel.terminalRef = terminal
	panel.programmingScroll = GlobalStorageSiK.TerminalScroll.create(panel, 0, 0, 280, 120)
end

---@param panel ISPanel
---@param innerW number
---@param innerH number
function GlobalStorageSiK.TerminalProgramming.layout(panel, innerW, innerH)
	if not panel or not panel.programmingScroll then
		return
	end
	panel.programmingScroll:setX(0)
	panel.programmingScroll:setY(0)
	GlobalStorageSiK.TerminalScroll.resize(panel.programmingScroll, innerW, math.max(120, innerH))
end

---@param player IsoPlayer|nil
---@param id string
---@return boolean known
---@return boolean hasDisk
local function programReadiness(player, id)
	local known = GlobalStorageSiK.DiskProgramming.knowsProgram(player, id)
	local hasDisk = player ~= nil and GlobalStorageSiK.CraftUtils.findItemTypeNearby(player, GlobalStorageSiK.DiskProgramming.BLANK_DISK) ~= nil
	return known, hasDisk
end

---@param panel ISPanel
---@param terminal GS_TerminalUI|nil
function GlobalStorageSiK.TerminalProgramming.refresh(panel, terminal)
	if not panel or not panel.programmingScroll then
		return
	end
	local scroll = panel.programmingScroll
	if not scroll._gsProgrammingContentRectBound then
		scroll._gsProgrammingContentRectBound = true
		GlobalStorageSiK.TerminalScroll.setOnContentRectChanged(scroll, function()
			if panel._gsProgrammingRelayout then return end
			panel._gsProgrammingRelayout = true
			GlobalStorageSiK.TerminalProgramming.refresh(panel, terminal or panel.terminalRef)
			panel._gsProgrammingRelayout = false
		end)
	end
	local savedOffset = GlobalStorageSiK.TerminalScroll.getScrollOffset(scroll)
	GlobalStorageSiK.TerminalScroll.clear(scroll, true)

	local pad = CONTENT_PAD
	local innerW = GlobalStorageSiK.TerminalScroll.contentWidth(scroll)
	local cardW = math.max(80, innerW - pad * 2)
	local y = pad

	local player = GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer() or nil

	y = addSectionTitle(scroll, pad, y, "IGUI_GS_SectionProgramming", innerW)
	y = addStatusHeader(scroll, pad, y, innerW, player)
	y = y + BLOCK_GAP
	-- Cada programa en su propia tarjeta enmarcada (pedido explicito
	-- 2026-08-23: "separar estos también claramente, enmarcarlos, dividir
	-- con algún separador") - antes eran bloques de texto sueltos sin borde
	-- ni fondo propio, dificiles de distinguir uno de otro al desplazarse.
	local ids = orderedProgramIds()
	for i = 1, #ids do
		local id = ids[i]
		local def = GlobalStorageSiK.DiskProgramming.PROGRAMS[id]
		local cardTop = y
		local innerPad = 8
		local card = GlobalStorageSiK.SiK_UI.createSectionCard(pad, cardTop, cardW, 10)
		GlobalStorageSiK.TerminalScroll.addChild(scroll, card)

		local blockY = y + innerPad
		local blockTop = blockY
		addProgramIcon(scroll, pad + innerPad, blockY, def.iconPath)

		local cardTextX = pad + innerPad + ICON_SIZE + 8
		local cardTextW = math.max(80, cardW - innerPad * 2 - ICON_SIZE - 8)
		local textY = blockY
		local title = T(def.menuTextKey or id)
		textY = addWrappedLabel(scroll, cardTextX, textY, title, cardTextW, 0.88, 0.9, 0.94)
		if def.descKey then
			textY = addWrappedLabel(scroll, cardTextX, textY, T(def.descKey), cardTextW, 0.62, 0.68, 0.72)
		end

		-- La tarjeta baja hasta lo mas alto entre el bloque de texto y el
		-- icono (un texto largo puede superar los 40px del icono; un icono
		-- sin descripcion nunca debe dejar la tarjeta mas corta que el).
		blockY = math.max(textY, blockTop + ICON_SIZE) + 4

		local known, hasDisk = programReadiness(player, id)
		local statusKey, sr, sg, sb
		if not known then
			statusKey, sr, sg, sb = "IGUI_GS_ProgrammingNeedsBook", 0.85, 0.4, 0.35
		elseif not hasDisk then
			statusKey, sr, sg, sb = "IGUI_GS_ProgrammingNeedsBlankDisk", 0.85, 0.7, 0.3
		else
			statusKey, sr, sg, sb = "IGUI_GS_ProgrammingReady", 0.5, 0.72, 0.55
		end
		blockY = addWrappedLabel(scroll, pad + innerPad, blockY, T(statusKey), cardW - innerPad * 2, sr, sg, sb)
		blockY = blockY + 4

		-- Decision revertida (2026-08-26, pedido explicito del usuario): el
		-- boton ya NO se oculta segun se cumplan los requisitos (2026-08-23,
		-- ver historial) - ocultar/mostrar movia el resto de la tarjeta y de
		-- la pestaña cada vez que cambiaba el estado. Ahora el boton SIEMPRE
		-- se crea, a ancho completo como el resto del proyecto, y se pinta
		-- "bloqueado" (atenuado, sin click) mientras falte receta o disco -
		-- reserva siempre el mismo hueco, sin saltos de layout.
		local ready = known and hasDisk
		local btn = GlobalStorageSiK.SiK_UI.Controls.button(nil, {
			x = pad + innerPad, y = blockY, w = cardW - innerPad * 2, h = BTN_H,
			text = T("IGUI_GS_ProgrammingButton"), target = scroll, onClick = function()
				GlobalStorageSiK.NetClient.sendCommand("programDisk", { programId = id })
			end, fullWidth = true, locked = not ready,
		})
		if not ready then
			btn:setTooltip(T(statusKey))
		end
		GlobalStorageSiK.TerminalScroll.addChild(scroll, btn)
		blockY = blockY + BTN_H + innerPad

		GlobalStorageSiK.SiK_UI.resizeSectionCard(card, pad, cardTop, cardW, blockY - cardTop)
		y = blockY + BLOCK_GAP
	end

	GlobalStorageSiK.TerminalScroll.setContentHeight(scroll, y + pad)
	GlobalStorageSiK.TerminalScroll.setScrollOffset(scroll, savedOffset)
	GlobalStorageSiK.TerminalScroll.applyPanelOffset(scroll)
end

--- Configuracion adicional del panel de Programacion creado por el proveedor
--- data-driven del Core.
---@param panel ISPanel
---@param terminal GS_TerminalUI
local function setupProgrammingPanel(panel, terminal)
	-- BUG REAL cerrado (2026-08-23, pedido explicito del usuario): el estado
	-- de cada tarjeta (¿conoce ya la receta? ¿tiene disquete en blanco?) se
	-- calcula por completo en cliente (programReadiness/countBlankDisksNearby,
	-- ninguna llamada a servidor) pero refresh() SOLO se disparaba al activar
	-- la pestaña o al llegar un terminalState nuevo - leer una revista o
	-- gastar el ultimo disquete en blanco no provoca ninguno de los dos, asi
	-- que la tarjeta se quedaba obsoleta hasta cambiar de pestaña o reabrir
	-- la ventana. Auto-refresco ligero mientras esta pestaña este realmente
	-- visible (prerender no se dispara para paneles ocultos, ver ISUIElement
	-- vanilla) - los dos chequeos que refresca son baratos (inventario local),
	-- nunca una reconstruccion de red.
	local REFRESH_INTERVAL_MS = 1000
	panel._gsLastRefreshMs = 0
	panel.prerender = function(p)
		ISPanel.prerender(p)
		local now = (getTimestampMs and getTimestampMs()) or 0
		if now - (p._gsLastRefreshMs or 0) >= REFRESH_INTERVAL_MS then
			p._gsLastRefreshMs = now
			GlobalStorageSiK.TerminalProgramming.refresh(p, p.terminalRef)
		end
	end
end

GlobalStorageSiK.TerminalExtensions.registerDefinition("programming", {
	module = GlobalStorageSiK.TerminalProgramming,
	titleKey = "IGUI_GS_TabProgramming",
	iconPath = "media/ui/GS/GS_TabProgramming.png",
	panelField = "programmingPanel",
	setupPanel = setupProgrammingPanel,
})

--- Muestra/oculta la pestaña Programación según si el periférico Reader
--- está instalado en esta red - sin él, la vía de siempre (disquetera
--- encima + rango de terminal, por menú contextual) sigue funcionando igual.
--- CRITICO: esto vivía como "function GS_TerminalUI:syncProgrammingTabVisibility()"
--- directamente en este fichero, que se requiere (GS_TerminalUI.lua) ANTES
--- de que la clase GS_TerminalUI exista (se define mucho más abajo en ese
--- mismo fichero) - crasheaba "attempted index of non-table" para TODO
--- jugador al conectar (reportado por Mad Man). Ningún otro fichero
--- GS_TerminalUI_*.lua hace esto: todos exponen su lógica en su propio
--- namespace (GlobalStorageSiK.TerminalXxx.*) y es GS_TerminalUI.lua quien,
--- YA con la clase definida, añade el método fino que delega aquí - mismo
--- patrón que Addons/Extensions/Network, ahora replicado.
---@param terminal GS_TerminalUI
function GlobalStorageSiK.TerminalProgramming.syncTabVisibility(terminal)
	local state = terminal.terminalState or {}
	local show = GlobalStorageSiK.Addons and GlobalStorageSiK.Addons.isInstalled(
		state.networkId, state.terminalAnchor, "Reader"
	)
	if GlobalStorageSiK.TerminalExtensions then
		GlobalStorageSiK.TerminalExtensions.setTabVisible(terminal, "programming", show == true)
	end
end
