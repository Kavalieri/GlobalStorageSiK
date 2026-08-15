--[[
	GlobalStorageSiK - Panel de bloqueo (sin terminal cercano)
	Autor: SiK
	Fecha: 2025-06-23
	Descripción: Aviso + receta craft; pestaña integrada en GS_TerminalUI.
]]

require "ISUI/ISPanel"
require "ISUI/ISLabel"
require "GS_I18n"
require "GS_NetClient"
require "GS_TerminalRecipes"
require "GS_CraftUtils"
require "GS_TerminalUI_Chrome"
require "GS_TerminalUI_Scroll"
require "GS_WorldHighlight"
require "GS_TerminalAccess"
require "GS_TerminalInstallReaderChoice"
require "GS_InstallTerminalReader"
require "GS_Config"
require "GS_Sandbox"
require "GS_PCAcquireUI"
require "GS_ReaderAcquireUI"

GlobalStorageSiK.TerminalBlockedPanel = {}

local T = GlobalStorageSiK.I18n.text
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local LINE_GAP = 4
local CARD_GAP = 12
local INTRO_PAD = 10
local CONTENT_PAD = 10
local CRAFT_BTN_H = FONT_HGT_SMALL + 10
local REFRESH_TICKS = 8
local REQ_ICON = 20
local REQ_ICON_GAP = 6
-- Recetas que se muestran como tarjeta en la pantalla de bloqueo: el
-- terminal antiguo (compatibilidad) y el PC vanilla liso (para quien no
-- encuentre uno en el mundo - ver GS_TerminalRecipes.LIST "vanilla_pc").
local BLOCKED_WINDOW_RECIPE_IDS = { terminal_unit = true, vanilla_pc = true }

-- Declaración adelantada: la función real se define más abajo (junto al
-- resto de la lógica del lector), pero stateSignature (justo debajo)
-- necesita poder llamarla. Un "local function" normal no sirve aquí porque
-- solo ve locales ya declaradas ANTES de su propio cuerpo en el código
-- fuente - con "local X" + "X = function()..." más abajo, la clausura
-- captura la variable (upvalue) y ve el valor real en cuanto se ejecuta,
-- no en cuanto se define.
local installReaderStatus

--- Firma del estado bloqueado para decidir si hace falta reconstruir el
--- panel. ANTES solo miraba `state.recipes` (el catálogo de recetas
--- internas) - desde que ese catálogo se vació (v1.2.58, retirada de las
--- recetas antiguas) la firma daba SIEMPRE la misma cadena vacía, así que
--- `applyRefreshIfNeeded` nunca detectaba ningún cambio real y el panel se
--- quedaba con contenido/checklist desactualizados tras el primer render
--- (coger el lector, encontrar un ordenador, etc. no refrescaba nada hasta
--- forzar un rebuild por otra vía). Ahora se basa en lo que de verdad
--- determina qué se ve en pantalla: motivo de bloqueo, rango, y estado del
--- lector/disquete/ordenador.
local function stateSignature(state)
	if not state then
		return ""
	end
	local player = GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer() or getPlayer()
	local rs = installReaderStatus and installReaderStatus(player) or {}
	return table.concat({
		tostring(state.reason),
		tostring(state.proximityRange),
		tostring(rs.hasReader),
		tostring(rs.hasDisk),
		tostring(rs.computerState),
	}, "|")
end

local function buildClientBlockedState(ui, player)
	if not player or not GlobalStorageSiK.TerminalRecipes then
		return ui.blockedState or {}
	end
	local ok, state = pcall(GlobalStorageSiK.TerminalRecipes.serializeForClient, player, { blockedOnly = true })
	if not ok or not state then
		return ui.blockedState or {}
	end
	local prev = ui.blockedState or {}
	state.reason = prev.reason
	state.proximityRange = prev.proximityRange or state.proximityRange
	state.wirelessRange = prev.wirelessRange or state.wirelessRange
	return state
end

local function blockedWindowRecipes(recipes)
	local out = {}
	if not recipes then
		return out
	end
	for i = 1, #recipes do
		if recipes[i].id == BLOCKED_TERMINAL_RECIPE_ID then
			table.insert(out, recipes[i])
		end
	end
	return out
end

local function introApproachHintLines(panelWidth, state)
	local prox = tonumber(state and state.proximityRange) or 3
	local hintKey = "IGUI_GS_BlockedApproachHint"
	local extraKey = nil
	if state and state.reason == "tablet_out_of_range" then
		hintKey = "IGUI_GS_BlockedApproachTablet"
	elseif state and state.reason == "antenna_out_of_range" then
		hintKey = "IGUI_GS_BlockedAntennaOutOfRange"
	elseif state and state.reason == "tablet_addon_required" then
		hintKey = "IGUI_GS_BlockedTabletAddon"
	elseif state and state.reason == "no_terminal" then
		-- La tarjeta "Instalar aqui" (metodo nuevo) ya explica el detalle
		-- completo con checklist propio mas abajo - aqui solo un puntero
		-- corto, sin duplicar el texto largo del metodo antiguo.
		hintKey = "IGUI_GS_BlockedApproachShort"
	elseif state and state.reason == "terminal_unlinked" then
		hintKey = "IGUI_GS_BlockedTerminalUnlinked"
	elseif state and state.reason == "terminal_missing_here" then
		hintKey = "IGUI_GS_BlockedTerminalMissingHere"
	end
	local wrapW = math.max(260, panelWidth - INTRO_PAD * 2)
	local lines = GlobalStorageSiK.TerminalChrome.wrapTextLines(T(hintKey, prox), wrapW, UIFont.Small)
	if extraKey then
		for _, line in ipairs(GlobalStorageSiK.TerminalChrome.wrapTextLines(T(extraKey, prox), wrapW, UIFont.Small)) do
			lines[#lines + 1] = line
		end
	end
	return lines
end

local function measureIntroHeight(panelWidth, state)
	local wrapW = math.max(260, panelWidth - INTRO_PAD * 2)
	local lines = GlobalStorageSiK.TerminalChrome.wrapTextLines(T("IGUI_GS_BlockedMessage"), wrapW, UIFont.Small)
	local lh = FONT_HGT_SMALL + LINE_GAP
	local hintLines = introApproachHintLines(panelWidth, state)
	-- Version del mod visible aqui (pedido 2026-08-15, ronda de pruebas
	-- -devN del equipo): la pantalla de bloqueo es la que ven SIEMPRE al
	-- entrar sin terminal a mano, asi confirman de un vistazo que build
	-- cargo el juego sin tener que abrir consola ni preguntar por chat.
	return INTRO_PAD + #lines * lh + 8 + #hintLines * lh + 8 + lh + INTRO_PAD
end

local function pushWrappedLines(out, text, maxWidth, r, g, b)
	for _, line in ipairs(GlobalStorageSiK.TerminalChrome.wrapTextLines(text, maxWidth, UIFont.Small)) do
		table.insert(out, { text = line, r = r, g = g, b = b })
	end
end

local function measureBodyHeight(bodyLines, textW)
	local h = 0
	local iconRowH = math.max(FONT_HGT_SMALL + LINE_GAP, REQ_ICON + LINE_GAP)
	for i = 1, #bodyLines do
		local spec = bodyLines[i]
		if spec.icon or spec.itemType then
			h = h + iconRowH
		else
			h = h + GlobalStorageSiK.TerminalChrome.countWrappedLines(spec.text, textW, UIFont.Small, LINE_GAP)
		end
	end
	return h
end

local function resolveReqIcon(spec)
	if spec.icon then
		return spec.icon
	end
	if spec.itemType and GlobalStorageSiK.CraftUtils.getItemIconTexture then
		return GlobalStorageSiK.CraftUtils.getItemIconTexture(spec.itemType)
	end
	return nil
end

local function buildRecipeBodyLines(recipe, textW)
	local lines = {}
	local textWIcon = math.max(120, textW - REQ_ICON - REQ_ICON_GAP)
	if recipe.requireBooks then
		local bookR, bookG, bookB = recipe.knowsBook and 0.5 or 0.82, recipe.knowsBook and 0.78 or 0.32, recipe.knowsBook and 0.5 or 0.32
		local bookLine = recipe.knowsBook and T("IGUI_GS_ReqBookOk", recipe.manualDisplay or "?")
			or T("IGUI_GS_ReqBookMissing", recipe.manualDisplay or "?")
		table.insert(lines, { text = bookLine, r = bookR, g = bookG, b = bookB, itemType = recipe.manualItem })
	end
	if (recipe.skillLevel or 0) > 0 then
		local skillLine = T("IGUI_GS_CraftSkillReqLine", recipe.skillHave or 0, recipe.skillLevel or 0)
		local skR, skG, skB = recipe.skillOk and 0.5 or 0.82, recipe.skillOk and 0.78 or 0.32, recipe.skillOk and 0.5 or 0.32
		local skillIcon = Perks and Perks.Electricity and GlobalStorageSiK.CraftUtils.getPerkTexture(Perks.Electricity) or nil
		table.insert(lines, { text = skillLine, r = skR, g = skG, b = skB, icon = skillIcon })
	end
	if recipe.requireWorkbench then
		local wbR, wbG, wbB = recipe.nearWorkbench and 0.5 or 0.82, recipe.nearWorkbench and 0.78 or 0.32, recipe.nearWorkbench and 0.5 or 0.32
		local wbLine = recipe.nearWorkbench and T("IGUI_GS_ReqWorkbenchOk") or T("IGUI_GS_ReqWorkbenchMissing")
		pushWrappedLines(lines, wbLine, textWIcon, wbR, wbG, wbB)
	end
	if recipe.requireLight then
		local ltR, ltG, ltB = recipe.hasCraftLight and 0.5 or 0.82, recipe.hasCraftLight and 0.78 or 0.32, recipe.hasCraftLight and 0.5 or 0.32
		local ltLine = recipe.hasCraftLight and T("IGUI_GS_ReqLightOk") or T("IGUI_GS_ReqLightMissing")
		pushWrappedLines(lines, ltLine, textWIcon, ltR, ltG, ltB)
	end
	for j = 1, #(recipe.ingredients or {}) do
		local ing = recipe.ingredients[j]
		local colorR, colorG, colorB = 0.78, 0.38, 0.38
		if ing.ok or recipe.freeBuild then
			colorR, colorG, colorB = 0.5, 0.78, 0.5
		end
		local line = string.format("%s  %d/%d", ing.displayName or ing.item, ing.have or 0, ing.count or 0)
		table.insert(lines, { text = line, r = colorR, g = colorG, b = colorB, itemType = ing.item })
	end
	return lines
end

local function drawBodyLines(panel, bodyLines, textW, startY, pad)
	local y = startY
	local lh = FONT_HGT_SMALL + LINE_GAP
	local iconRowH = math.max(lh, REQ_ICON + LINE_GAP)
	local textX = pad + REQ_ICON + REQ_ICON_GAP
	local textWIcon = math.max(120, textW - REQ_ICON - REQ_ICON_GAP)
	for i = 1, #bodyLines do
		local spec = bodyLines[i]
		local icon = resolveReqIcon(spec)
		if icon then
			-- drawTextureScaled real B42 signature es (tex,x,y,w,h,a,r,g,b), NO
			-- (tex,x,y,w,h,r,g,b,a): pasar el color ok/falta aqui desplazaba los
			-- canales y el azul quedaba siempre a 1 - todo icono salia teñido de
			-- azul sin importar el estado. El icono se dibuja en su color real,
			-- el tinte ok/falta ya lo lleva el texto de al lado.
			panel:drawTextureScaled(icon, pad, y, REQ_ICON, REQ_ICON, 1, 1, 1, 1)
			panel:drawText(spec.text, textX, y, spec.r or 1, spec.g or 1, spec.b or 1, 1, UIFont.Small)
			y = y + iconRowH
		else
			for _, line in ipairs(GlobalStorageSiK.TerminalChrome.wrapTextLines(spec.text, textW, UIFont.Small)) do
				panel:drawText(line, pad, y, spec.r or 1, spec.g or 1, spec.b or 1, 1, UIFont.Small)
				y = y + lh
			end
		end
	end
	return y
end

local function drawIntroBlock(panel)
	local state = panel.blockedState or {}
	local y = INTRO_PAD
	local lh = FONT_HGT_SMALL + LINE_GAP
	local wrapW = math.max(260, panel.width - INTRO_PAD * 2)
	local pal = GlobalStorageSiK.TerminalChrome.PALETTE
	for _, line in ipairs(GlobalStorageSiK.TerminalChrome.wrapTextLines(T("IGUI_GS_BlockedMessage"), wrapW, UIFont.Small)) do
		panel:drawText(line, INTRO_PAD, y, pal.textPrimary[1], pal.textPrimary[2], pal.textPrimary[3], 1, UIFont.Small)
		y = y + lh
	end
	y = y + 8
	for _, line in ipairs(introApproachHintLines(panel.width, state)) do
		panel:drawText(line, INTRO_PAD, y, pal.statusOk[1], pal.statusOk[2], pal.statusOk[3], 1, UIFont.Small)
		y = y + lh
	end
	y = y + 8
	local versionLine = "GlobalStorageSiK v" .. tostring(GlobalStorageSiK.Config.MOD_VERSION)
	panel:drawText(versionLine, INTRO_PAD, y, 0.45, 0.47, 0.5, 1, UIFont.Small)
end

--- Estado del metodo nuevo de instalacion (lector+disquete) para el jugador
--- actual: que le falta, y si ya hay un ordenador SIN instalar a mano para
--- poder ofrecer el boton directo de instalar desde esta misma pantalla,
--- sin tener que salir a buscar el disquete en el inventario y hacer clic
--- derecho - la pantalla de bloqueo es precisamente donde el jugador ya
--- esta pensando "como consigo un terminal", asi que tiene sentido que la
--- via principal este aqui mismo.
---@param player IsoPlayer|nil
---@return table { hasReader, hasDisk, target, allReady }
installReaderStatus = function(player)
	-- computerState: "none" (nada detectado), "installed" (el mas cercano
	-- ya tiene terminal) o "ready" (hay uno libre a mano).
	local out = { hasReader = false, hasDisk = false, target = nil, computerState = "none", allReady = false }
	if not player or not player.getInventory then
		return out
	end
	local inv = player:getInventory()
	out.hasReader = (inv:getItemCount(GlobalStorageSiK.Config.ITEM_TERMINAL_READER) or 0) > 0
	out.hasDisk = (inv:getItemCountRecurse("GlobalStorageSiK.GS_FloppyDisk") or 0) > 0
	local range = GlobalStorageSiK.Sandbox.getTerminalProximityRange()
	local known = GlobalStorageSiK.TerminalAccess.findNearestKnownComputer(player, range)
	if known then
		if known.alreadyInstalled then
			out.computerState = "installed"
		else
			out.computerState = "ready"
			out.target = known
		end
	end
	out.allReady = out.hasReader and out.hasDisk and out.target ~= nil
	return out
end

---@param scroll ISPanel
---@param terminal GS_TerminalUI
---@param y number
---@param cardW number
---@return number cardH
local function buildInstallReaderCard(scroll, terminal, y, cardW)
	local pad = 10
	local textW = math.max(220, cardW - pad * 2)
	local player = GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer() or getPlayer()
	local status = installReaderStatus(player)

	local titleH = FONT_HGT_SMALL + 10
	-- Siempre 3 lineas fijas (lector / disco / ordenador), cada una marcada
	-- ok/falta, para que el jugador vea de un vistazo que tiene y que falta
	-- en vez de una unica linea ambigua que mezclaba varios casos.
	local lines = {
		{ text = T(status.hasReader and "IGUI_GS_InstallReaderHasReaderShort" or "IGUI_GS_InstallReaderNeedReaderShort"), ok = status.hasReader, itemType = GlobalStorageSiK.Config.ITEM_TERMINAL_READER },
		{ text = T(status.hasDisk and "IGUI_GS_InstallReaderHasDiskShort" or "IGUI_GS_InstallReaderNeedDiskShort"), ok = status.hasDisk, itemType = "GlobalStorageSiK.GS_FloppyDisk" },
	}
	-- Base.Mov_DesktopComputer usa Icon = default (generico "?", confirmado en
	-- moveable.txt vanilla) - nunca fue un icono real, asi que esta linea
	-- siempre mostraba el placeholder de "sin icono" en vez del ordenador.
	-- Una lupa encaja mejor con "detectando ordenador cerca" en los 3 estados.
	local COMPUTER_LINE_ICON = "Base.MagnifyingGlass"
	if status.computerState == "installed" then
		lines[#lines + 1] = { text = T("IGUI_GS_InstallReaderComputerInstalledShort"), ok = false, itemType = COMPUTER_LINE_ICON }
	elseif status.computerState == "ready" then
		lines[#lines + 1] = { text = T("IGUI_GS_InstallReaderComputerReadyShort"), ok = true, itemType = COMPUTER_LINE_ICON }
	else
		lines[#lines + 1] = { text = T("IGUI_GS_InstallReaderComputerNoneShort"), ok = false, itemType = COMPUTER_LINE_ICON }
	end

	local lineH = FONT_HGT_SMALL + LINE_GAP
	local iconRowH = math.max(lineH, REQ_ICON + LINE_GAP)
	local bodyH = #lines * iconRowH
	local cardH = titleH + pad + bodyH + CRAFT_BTN_H + 12

	local card = ISPanel:new(CONTENT_PAD, y, cardW, cardH)
	card:initialise()
	card.drawBackground = false
	card.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
	card.prerender = function(panel)
		ISPanel.prerender(panel)
		GlobalStorageSiK.TerminalChrome.drawCardBackground(panel, titleH)
		local pal = GlobalStorageSiK.TerminalChrome.PALETTE
		panel:drawText(T("IGUI_GS_InstallReaderCardTitle"), pad, 3, pal.textPrimary[1], pal.textPrimary[2], pal.textPrimary[3], 1, UIFont.Small)
		local ly = titleH + pad
		local textX = pad + REQ_ICON + REQ_ICON_GAP
		for i = 1, #lines do
			local spec = lines[i]
			local r, g, b = spec.ok and 0.5 or 0.82, spec.ok and 0.78 or 0.32, spec.ok and 0.5 or 0.32
			local icon = resolveReqIcon(spec)
			if icon then
				-- Mismo fix que en drawBodyLines: (a,r,g,b), no (r,g,b,a).
				panel:drawTextureScaled(icon, pad, ly, REQ_ICON, REQ_ICON, 1, 1, 1, 1)
				panel:drawText(spec.text, textX, ly, r, g, b, 1, UIFont.Small)
			else
				panel:drawText(spec.text, pad, ly, r, g, b, 1, UIFont.Small)
			end
			ly = ly + iconRowH
		end
	end

	local btnY = cardH - CRAFT_BTN_H - 6
	-- Si falta el lector, se lo ponemos fácil: un botón "Fabricar lector" al
	-- lado de "Instalar aquí" que abre la misma ventana propia que ya usa
	-- "Conseguir PC" (validar requisitos, esperar el tiempo de crafteo,
	-- añadir el resultado al inventario) en vez de mandar al jugador al menú
	-- vanilla a craftear 3 piezas por separado.
	local installBtnW = textW
	if not status.hasReader then
		installBtnW = math.floor((textW - 8) / 2)
	end

	local btn = GlobalStorageSiK.TerminalChrome.createNeatButton(
		pad, btnY, installBtnW, CRAFT_BTN_H, T("IGUI_GS_InstallReaderCardBtn"), card, function()
			local p = GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer() or getPlayer()
			-- Re-revalida SIEMPRE en el momento del clic (el panel puede llevar
			-- un rato sin refrescarse - ver stateSignature más arriba). Antes,
			-- si algo cambiaba entre que se pintó la tarjeta y el clic (el
			-- jugador se movió un paso, el ordenador dejó de estar "libre"),
			-- el botón simplemente no hacía NADA sin explicar por qué - un
			-- jugador reportó justo esto: los 3 requisitos en verde pero
			-- "Instalar aquí" sin efecto. Ahora siempre hay un aviso.
			local st = installReaderStatus(p)
			if st.allReady then
				-- Igual que el menu contextual del disquete: inicia la
				-- instalacion directamente, sin abrir ningun dialogo antes.
				-- El dialogo de red nueva/existente se abre solo al terminar.
				GlobalStorageSiK.InstallTerminalReader.begin(p, st.target)
			elseif p and p.setHaloNote then
				local msg
				if not st.hasReader then
					msg = T("IGUI_GS_InstallReaderNeedReaderShort")
				elseif not st.hasDisk then
					msg = T("IGUI_GS_InstallReaderNeedDiskShort")
				elseif st.computerState == "installed" then
					msg = T("IGUI_GS_InstallReaderComputerInstalledShort")
				else
					msg = T("IGUI_GS_InstallReaderComputerNoneShort")
				end
				p:setHaloNote(msg, 220, 180, 100, 300)
			end
		end)
	-- NUNCA deshabilitar este boton: un boton desactivado no llega a
	-- procesar el clic en absoluto en PZ, asi que la logica de arriba (que
	-- SI explica con un aviso por que no puede instalar) nunca se ejecutaba
	-- - el jugador solo veia un boton muerto, sin ningun mensaje. Un boton
	-- de la interfaz siempre debe reaccionar al clic; si la accion no puede
	-- completarse, se avisa (ya lo hace el onClick de arriba), nunca se
	-- deja de responder sin mas.
	card.installBtn = btn
	card:addChild(btn)

	if not status.hasReader then
		local buildReaderBtn = GlobalStorageSiK.TerminalChrome.createNeatButton(
			pad + installBtnW + 8, btnY, installBtnW, CRAFT_BTN_H, T("IGUI_GS_ReaderAcquireOpenBtn"), card, function()
				GlobalStorageSiK.ReaderAcquireUI.show(GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer() or getPlayer())
			end)
		card.buildReaderBtn = buildReaderBtn
		card:addChild(buildReaderBtn)
	end

	GlobalStorageSiK.TerminalScroll.addChild(scroll, card)
	return cardH
end

--- Crea scroll del panel bloqueado en el terminal principal.
---@param terminal GS_TerminalUI
function GlobalStorageSiK.TerminalBlockedPanel.build(terminal)
	if not terminal or not terminal.blockedPanel then
		return
	end
	if terminal.blockedScroll then
		return
	end
	terminal.blockedScroll = GlobalStorageSiK.TerminalScroll.createInteractive(terminal.blockedPanel, 0, 0, 100, 100)
end

---@param terminal GS_TerminalUI
---@param innerW number
---@param innerH number
function GlobalStorageSiK.TerminalBlockedPanel.layout(terminal, innerW, innerH)
	if not terminal or not terminal.blockedScroll then
		return
	end
	-- CRITICO: terminal.blockedPanel (el contenedor con clipChildren=true que
	-- envuelve blockedScroll, creado en GS_TerminalUI.createChildren via
	-- createTabPanel = ISPanel:new(0,0,10,10)) SOLO se redimensiona a traves
	-- del bucle de tabPanels en GS_TerminalUI:calculateLayout() - pero ese
	-- bucle se salta si el ancho del terminal no cambio mas de 6px desde el
	-- ultimo layout (ver applyRefreshIfNeeded). Resultado confirmado con
	-- GS_UIDebug.dumpTree: blockedPanel se quedaba en 10x10 para siempre
	-- mientras blockedScroll (su hijo) SI crecia a 920x779 - con
	-- clipChildren=true, cualquier clic fuera de esa caja de 10x10 se
	-- descartaba antes de llegar a los botones, aunque se vieran pintados
	-- perfectamente. Se redimensiona aqui tambien, sin depender de que
	-- calculateLayout() decida ejecutarse.
	terminal.blockedPanel:setWidth(innerW)
	terminal.blockedPanel:setHeight(innerH)
	GlobalStorageSiK.TerminalScroll.resize(terminal.blockedScroll, innerW, innerH)
end

---@param terminal GS_TerminalUI
---@param recipe table
---@param y number
---@param cardW number
---@return number cardH
local function buildRecipeCard(terminal, recipe, y, cardW)
	local pad = 10
	local textW = math.max(220, cardW - pad * 2)
	local titleH = FONT_HGT_SMALL + 10
	local bodyH = measureBodyHeight(buildRecipeBodyLines(recipe, textW), textW)
	local cardH = titleH + pad + bodyH + CRAFT_BTN_H + 12

	local card = ISPanel:new(CONTENT_PAD, y, cardW, cardH)
	card:initialise()
	card.drawBackground = false
	card.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
	card.textW = textW
	card.contentPad = pad
	card.titleHeight = titleH
	card.recipeId = recipe.id
	card.ownerUI = terminal
	card.clipChildren = true

	card.prerender = function(panel)
		ISPanel.prerender(panel)
		local owner = panel.ownerUI
		local liveRecipe = recipe
		if owner and owner.blockedState and owner.blockedState.recipes then
			for i = 1, #owner.blockedState.recipes do
				local candidate = owner.blockedState.recipes[i]
				if candidate.id == panel.recipeId then
					liveRecipe = candidate
					break
				end
			end
		end
		local title = liveRecipe.outputDisplay or liveRecipe.id
		local bodyLines = buildRecipeBodyLines(liveRecipe, panel.textW)
		GlobalStorageSiK.TerminalChrome.drawCardBackground(panel, panel.titleHeight)
		local _bpal = GlobalStorageSiK.TerminalChrome.PALETTE
		panel:drawText(title, panel.contentPad, 3, _bpal.textPrimary[1], _bpal.textPrimary[2], _bpal.textPrimary[3], 1, UIFont.Small)
		drawBodyLines(panel, bodyLines, panel.textW, panel.titleHeight + panel.contentPad, panel.contentPad)
		if panel.craftBtn then
			local canCraft = liveRecipe.canCraft == true
			panel.craftBtn._gsNeatLabel = canCraft and T("IGUI_GS_CraftNow") or T("IGUI_GS_CraftMissing")
			panel.craftBtn:setEnable(canCraft)
		end
	end

	local btnTitle = recipe.canCraft and T("IGUI_GS_CraftNow") or T("IGUI_GS_CraftMissing")
	local craftBtn = GlobalStorageSiK.TerminalChrome.createNeatButton(
		pad, cardH - CRAFT_BTN_H - 6, 220, CRAFT_BTN_H, btnTitle, card, function()
			GlobalStorageSiK.TerminalBlockedPanel.onCraftRecipe(terminal, recipe.id)
		end)
	craftBtn:setEnable(recipe.canCraft == true)
	card.craftBtn = craftBtn
	card:addChild(craftBtn)
	card.onMouseDown = function(panel, x, y)
		if not panel.craftBtn then
			return false
		end
		local btn = panel.craftBtn
		if x >= btn:getX() and x <= btn:getX() + btn.width
			and y >= btn:getY() and y <= btn:getY() + btn.height then
			return true
		end
		return false
	end
	card.onMouseUp = function(panel, x, y, button)
		if button ~= 0 or not panel.craftBtn then
			return false
		end
		local btn = panel.craftBtn
		if not btn.enable then
			return false
		end
		if x >= btn:getX() and x <= btn:getX() + btn.width
			and y >= btn:getY() and y <= btn:getY() + btn.height then
			GlobalStorageSiK.TerminalBlockedPanel.onCraftRecipe(terminal, panel.recipeId)
			return true
		end
		return false
	end

	GlobalStorageSiK.TerminalScroll.addChild(terminal.blockedScroll, card)
	return cardH
end

--- Ilumina en el mundo el ALCANCE de cada red a la que el jugador tiene
--- acceso, usando el ancla ya calculada por el servidor (getRecoveryNetworks
--- - mismos datos que el combo de "vincular a red existente"). Dos capas,
--- no una sola casilla:
---  1) zona rellena (radio = TerminalProximityRange): desde donde se puede
---     USAR un terminal de esa red.
---  2) anillo/perimetro (radio = TerminalLinkMaxDistance, acotado para no
---     generar miles de marcadores): hasta donde se puede colocar OTRO
---     terminal para que cuente como parte de la misma red.
local USE_COLOR = { r = 0.35, g = 0.85, b = 0.45 }
local LINK_COLOR = { r = 0.95, g = 0.7, b = 0.25 }
-- El alcance de vinculacion puede ser enorme por defecto (auto = wireless*12,
-- ej. 480 baldosas) - acotamos el anillo dibujado a un radio razonable para
-- que siga siendo util en pantalla sin generar miles de marcadores.
local LINK_RING_MAX_RADIUS = 40

function GlobalStorageSiK.TerminalBlockedPanel.redrawMarkers()
	GlobalStorageSiK.WorldHighlight.clearAll()
	local rows = GlobalStorageSiK.Client and GlobalStorageSiK.Client.recoveryNetworks or {}
	local cell = getCell and getCell() or nil
	local player = GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer and GlobalStorageSiK.NetClient.getPlayer()
	if not cell then
		return
	end
	local useRadius = GlobalStorageSiK.Sandbox.getTerminalProximityRange()
	local linkRadius = math.min(GlobalStorageSiK.Sandbox.getTerminalLinkMaxDistance(), LINK_RING_MAX_RADIUS)
	local marked = 0
	for i = 1, #rows do
		local anchor = rows[i].anchor
		if anchor and anchor.x then
			local x, y, z = math.floor(anchor.x), math.floor(anchor.y), math.floor(anchor.z or 0)
			GlobalStorageSiK.WorldHighlight.markArea(cell, x, y, z, linkRadius, LINK_COLOR.r, LINK_COLOR.g, LINK_COLOR.b, false)
			GlobalStorageSiK.WorldHighlight.markArea(cell, x, y, z, useRadius, USE_COLOR.r, USE_COLOR.g, USE_COLOR.b, true)
			marked = marked + 1
		end
	end
	-- Aviso inmediato al jugador (halo note): sin esto, si la API de
	-- resaltado del mundo falla en silencio, el botón "Mostrar cobertura"
	-- parece no hacer nada y no hay forma de saber si es un problema de
	-- datos (sin redes/sin ancla) o de renderizado.
	if player and player.setHaloNote then
		if marked == 0 then
			player:setHaloNote(T("IGUI_GS_CoverageNoneMarked"), 220, 180, 100, 300)
		else
			player:setHaloNote(T("IGUI_GS_CoverageMarkedCount", tostring(marked)), 140, 220, 160, 300)
		end
	end
end

---@param rows table[]
function GlobalStorageSiK.TerminalBlockedPanel.onNetworksReceived(rows)
	if not GlobalStorageSiK.Client then
		GlobalStorageSiK.Client = {}
	end
	GlobalStorageSiK.Client.recoveryNetworks = rows or {}
	if GlobalStorageSiK.TerminalBlockedPanel._marking then
		GlobalStorageSiK.TerminalBlockedPanel.redrawMarkers()
	end
end

---@param terminal GS_TerminalUI
function GlobalStorageSiK.TerminalBlockedPanel.toggleMarkKnownTerminals(terminal)
	local marking = not GlobalStorageSiK.TerminalBlockedPanel._marking
	GlobalStorageSiK.TerminalBlockedPanel._marking = marking
	if marking then
		if GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.sendCommand then
			GlobalStorageSiK.NetClient.sendCommand("getRecoveryNetworks", {})
		end
		GlobalStorageSiK.TerminalBlockedPanel.redrawMarkers()
	else
		GlobalStorageSiK.WorldHighlight.clearAll()
	end
	if terminal then
		GlobalStorageSiK.TerminalBlockedPanel.rebuildContent(terminal)
	end
end

--- Muestra/oculta la cobertura de UN terminal concreto (fila x,y,z), pedido
--- explicito (2026-08-17): antes "mostrar cobertura" marcaba TODAS las redes
--- conocidas del jugador (toggleMarkKnownTerminals, arriba) desde 2 sitios
--- genericos (ventana de bloqueo y pestaña Red) - se sustituye por esto,
--- un boton POR TERMINAL en su propio modal de edicion
--- (GS_TerminalUI_TerminalEditor.lua) que solo marca el radio de ESE
--- terminal. Los otros 2 visualizadores quedan descartados por ahora (sin
--- borrar el motor compartido de resaltado, solo sus puntos de entrada).
---@param row table {x, y, z}
---@return boolean marcandoAhora
function GlobalStorageSiK.TerminalBlockedPanel.toggleSingleTerminalCoverage(row)
	if GlobalStorageSiK.TerminalBlockedPanel._singleMarking then
		GlobalStorageSiK.TerminalBlockedPanel._singleMarking = false
		GlobalStorageSiK.TerminalBlockedPanel._singleMarkedRow = nil
		GlobalStorageSiK.WorldHighlight.clearAll()
		return false
	end
	GlobalStorageSiK.TerminalBlockedPanel._singleMarking = true
	GlobalStorageSiK.TerminalBlockedPanel._singleMarkedRow = row
	local cell = getCell and getCell() or nil
	if cell and row and row.x then
		local useRadius = GlobalStorageSiK.Sandbox.getTerminalProximityRange()
		local linkRadius = math.min(GlobalStorageSiK.Sandbox.getTerminalLinkMaxDistance(), LINK_RING_MAX_RADIUS)
		local x, y, z = math.floor(row.x), math.floor(row.y), math.floor(row.z or 0)
		GlobalStorageSiK.WorldHighlight.markArea(cell, x, y, z, linkRadius, LINK_COLOR.r, LINK_COLOR.g, LINK_COLOR.b, false)
		GlobalStorageSiK.WorldHighlight.markArea(cell, x, y, z, useRadius, USE_COLOR.r, USE_COLOR.g, USE_COLOR.b, true)
	end
	return true
end

---@param terminal GS_TerminalUI
function GlobalStorageSiK.TerminalBlockedPanel.rebuildContent(terminal)
	if not terminal or not terminal.blockedScroll then
		return
	end
	GlobalStorageSiK.TerminalScroll.clear(terminal.blockedScroll)
	local scroll = terminal.blockedScroll
	local cardW = math.max(260, scroll.width - CONTENT_PAD * 2)
	local y = CONTENT_PAD

	local introH = measureIntroHeight(cardW, terminal.blockedState)
	local intro = ISPanel:new(CONTENT_PAD, y, cardW, introH)
	intro:initialise()
	intro.drawBackground = false
	intro.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
	intro.blockedState = terminal.blockedState
	if intro.setMouseTransparent then
		intro:setMouseTransparent(true)
	end
	intro.prerender = function(panel)
		ISPanel.prerender(panel)
		panel:drawRect(0, 0, panel.width, panel.height, 0.85, 0.07, 0.07, 0.07)
		drawIntroBlock(panel)
	end
	GlobalStorageSiK.TerminalScroll.addChild(scroll, intro)
	y = y + introH + CARD_GAP

	-- Unico camino para conseguir un terminal: lector + disquete sobre un
	-- ordenador ya en el mapa. Si no hay ninguno detectado cerca, se ofrece
	-- ademas "Conseguir PC" (ventana propia, ver GS_PCAcquireUI.lua) para
	-- fabricar uno sin depender de encontrarlo por el mundo.
	local readerStatus = nil
	if terminal.blockedState and terminal.blockedState.reason ~= "tablet_out_of_range"
		and terminal.blockedState.reason ~= "antenna_out_of_range"
		and terminal.blockedState.reason ~= "tablet_addon_required" then
		local player = GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer() or getPlayer()
		readerStatus = installReaderStatus(player)
		local cardH = buildInstallReaderCard(scroll, terminal, y, cardW)
		y = y + cardH + CARD_GAP

		if readerStatus.computerState == "none" then
			local pcBtn = GlobalStorageSiK.TerminalChrome.createNeatButton(
				CONTENT_PAD, y, math.min(cardW, 260), CRAFT_BTN_H, T("IGUI_GS_PCAcquireOpenBtn"), scroll, function()
					GlobalStorageSiK.PCAcquireUI.show(GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer() or getPlayer())
				end)
			GlobalStorageSiK.TerminalScroll.addChild(scroll, pcBtn)
			y = y + CRAFT_BTN_H + CARD_GAP
		end
	end

	-- Boton "mostrar cobertura" RETIRADO de aqui (2026-08-17, pedido
	-- explicito): la cobertura ahora se marca por terminal concreto, desde
	-- el modal de ese terminal (GS_TerminalUI_TerminalEditor.lua,
	-- toggleSingleTerminalCoverage) - este visualizador generico "todas las
	-- redes conocidas" queda descartado por ahora, sin borrar el motor
	-- compartido de resaltado (toggleMarkKnownTerminals/redrawMarkers, mas
	-- arriba en este fichero) por si se retoma mas adelante.
	y = y + CARD_GAP

	-- Visibilidad minima de "tus redes" sin tener terminal a mano - pide la
	-- lista la primera vez que se construye este panel (mismos datos que ya
	-- usa el dialogo de instalar/el boton de marcar, cacheados en
	-- GlobalStorageSiK.Client.recoveryNetworks).
	if not terminal._blockedRequestedNetworks then
		terminal._blockedRequestedNetworks = true
		if GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.sendCommand then
			GlobalStorageSiK.NetClient.sendCommand("getRecoveryNetworks", {})
		end
	end
	local myNetworks = GlobalStorageSiK.Client and GlobalStorageSiK.Client.recoveryNetworks or {}
	local networksText
	if #myNetworks == 0 then
		networksText = T("IGUI_GS_BlockedNoNetworksYet")
	else
		local names = {}
		for i = 1, #myNetworks do
			names[#names + 1] = myNetworks[i].label or myNetworks[i].networkId
		end
		networksText = T("IGUI_GS_BlockedYourNetworks", table.concat(names, ", "))
	end
	for _, line in ipairs(GlobalStorageSiK.TerminalChrome.wrapTextLines(networksText, cardW - CONTENT_PAD, UIFont.Small)) do
		local lbl = ISLabel:new(CONTENT_PAD, y, FONT_HGT_SMALL, line, 0.62, 0.66, 0.7, 1, UIFont.Small, true)
		lbl:initialise()
		GlobalStorageSiK.TerminalScroll.addChild(scroll, lbl)
		y = y + FONT_HGT_SMALL + LINE_GAP
	end
	y = y + CARD_GAP

	GlobalStorageSiK.TerminalScroll.setContentHeight(scroll, y + CONTENT_PAD)
	GlobalStorageSiK.TerminalScroll.ensureScrollBars(scroll)
	GlobalStorageSiK.TerminalScroll.setScrollBarsVisible(
		scroll, (scroll._gsContentHeight or 0) > (scroll.height or 0) + 2)
	terminal.lastBlockedLayoutWidth = terminal.width
	if GlobalStorageSiK.TerminalTabs and GlobalStorageSiK.TerminalTabs.syncBlockedChrome then
		GlobalStorageSiK.TerminalTabs.syncBlockedChrome(terminal)
	end
	-- Diagnostico dedicado (sandbox DebugModeUI, separado del ruido de red):
	-- vuelca el arbol y comprueba solapes justo tras reconstruir, para poder
	-- ver el estado exacto de los 3 botones en el momento en que el jugador
	-- intenta pulsarlos, no solo en la apertura inicial de la ventana.
	if GlobalStorageSiK.UIDebug and GlobalStorageSiK.UIDebug.enabled and GlobalStorageSiK.UIDebug.enabled() then
		GlobalStorageSiK.UIDebug.dumpTree(terminal, "blockedPanel-rebuild")
		GlobalStorageSiK.UIDebug.checkOverlaps(terminal, "blockedPanel-rebuild")
	end
end

---@param terminal GS_TerminalUI
---@param force boolean|nil
function GlobalStorageSiK.TerminalBlockedPanel.applyRefreshIfNeeded(terminal, force)
	if not terminal or terminal.accessMode ~= "blocked" then
		return
	end
	-- rebuildContent destruye y recrea TODOS los widgets (botones incluidos).
	-- Si eso ocurre entre el mousedown y el mouseup de un boton de este panel
	-- (el estado puede cambiar y disparar un rebuild en cualquier momento:
	-- cada 8 ticks o al vuelo con OnContainerUpdate/OnReadLiterature), el
	-- widget que capturo la pulsacion deja de existir antes de que llegue el
	-- mouseup y el clic se pierde sin ningun error visible - exactamente
	-- "Instalar aqui/Conseguir PC/Mostrar cobertura no reaccionan al clic".
	-- Se difiere el rebuild hasta soltar el raton (refreshPending ya hace que
	-- el propio onTick lo reintente en cuanto pueda).
	if not force and isMouseButtonDown and isMouseButtonDown(0) then
		terminal.refreshPending = true
		return
	end
	local player = GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer() or getPlayer()
	local state = buildClientBlockedState(terminal, player)
	local sig = stateSignature(state)
	if not force and sig == (terminal.lastBlockedSignature or "") then
		return
	end
	terminal.blockedState = state
	terminal.lastBlockedSignature = sig
	terminal.refreshPending = false
	if math.abs((terminal.lastBlockedLayoutWidth or 0) - terminal.width) > 6 and terminal.calculateLayout then
		terminal:calculateLayout()
	end
	GlobalStorageSiK.TerminalBlockedPanel.rebuildContent(terminal)
end

---@param terminal GS_TerminalUI
---@param blockedState table|nil
function GlobalStorageSiK.TerminalBlockedPanel.refresh(terminal, blockedState)
	if not terminal then
		return
	end
	if blockedState then
		terminal.blockedState = blockedState
		terminal.lastBlockedSignature = stateSignature(blockedState)
	end
	GlobalStorageSiK.TerminalBlockedPanel.applyRefreshIfNeeded(terminal, true)
end

---@param terminal GS_TerminalUI
---@param recipeId string
function GlobalStorageSiK.TerminalBlockedPanel.onCraftRecipe(terminal, recipeId)
	local player = GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer() or getPlayer()
	local recipe = GlobalStorageSiK.TerminalRecipes.getById(recipeId)
	if not player or not recipe then
		return
	end
	if ISTimedActionQueue and ISTimedActionQueue.getTimedActionQueue then
		local queue = ISTimedActionQueue.getTimedActionQueue(player)
		if queue and queue.queue then
			for i = 1, #queue.queue do
				if queue.queue[i] and queue.queue[i].Type == "GS_CraftTerminalTimedAction" then
					return
				end
			end
		end
	end
	if not GlobalStorageSiK.TerminalRecipes.canCraft(player, recipe) then
		return
	end
	if not GS_CraftTerminalTimedAction then
		require "TimedActions/GS_CraftTerminalTimedAction"
	end
	if not GS_CraftTerminalTimedAction then
		GlobalStorageSiK.NetClient.sendCommand("craftTerminalRecipe", { recipeId = recipeId })
		return
	end
	ISTimedActionQueue.add(GS_CraftTerminalTimedAction:new(player, recipeId, recipe.time or 100))
end

function GlobalStorageSiK.TerminalBlockedPanel.onLiveStateEvent()
	local ui = GlobalStorageSiK.TerminalUI and GlobalStorageSiK.TerminalUI.instance
	if ui and ui:getIsVisible() and ui.accessMode == "blocked" then
		GlobalStorageSiK.TerminalBlockedPanel.applyRefreshIfNeeded(ui, false)
	end
end

local function installRecipeLearnHooks(hook)
	if not Events then
		return
	end
	local names = { "OnPlayerLearnRecipe", "OnLearnRecipe", "OnRecipeLearned", "OnNewRecipe" }
	for i = 1, #names do
		local ev = Events[names[i]]
		if ev and ev.Add then
			ev.Add(hook)
		end
	end
end

function GlobalStorageSiK.TerminalBlockedPanel.onTick()
	local ui = GlobalStorageSiK.TerminalUI and GlobalStorageSiK.TerminalUI.instance
	if not ui or not ui:getIsVisible() or ui.accessMode ~= "blocked" then
		return
	end
	ui.blockedRefreshTick = (ui.blockedRefreshTick or 0) + 1
	if ui.refreshPending or (ui.blockedRefreshTick % REFRESH_TICKS == 0) then
		GlobalStorageSiK.TerminalBlockedPanel.applyRefreshIfNeeded(ui, false)
	end
end

function GlobalStorageSiK.TerminalBlockedPanel.ensureEvents()
	if GlobalStorageSiK.TerminalBlockedPanel._eventsInstalled then
		return
	end
	GlobalStorageSiK.TerminalBlockedPanel._eventsInstalled = true
	local hook = GlobalStorageSiK.TerminalBlockedPanel.onLiveStateEvent
	if Events and Events.OnContainerUpdate then
		Events.OnContainerUpdate.Add(hook)
	end
	if Events and Events.OnReadLiterature then
		Events.OnReadLiterature.Add(hook)
	end
	installRecipeLearnHooks(hook)
	if Events and Events.OnTick then
		Events.OnTick.Add(GlobalStorageSiK.TerminalBlockedPanel.onTick)
	end
end
