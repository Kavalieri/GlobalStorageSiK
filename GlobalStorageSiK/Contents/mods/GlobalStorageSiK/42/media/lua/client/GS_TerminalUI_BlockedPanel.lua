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
require "GS_SiK_UI_Core"
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
--
-- BUG REAL confirmado (2026-08-25, investigacion del cuelgue de cliente al
-- morir y reclamar): con estos motivos la tarjeta de lector/disco/ordenador
-- NUNCA se pinta (ver el mismo filtro en rebuildContent mas abajo), asi que
-- calcular installReaderStatus() para ellos era trabajo tirado - pero esta
-- firma lo hacia SIEMPRE, cada 8 ticks (REFRESH_TICKS), mientras la pantalla
-- de bloqueo estuviera abierta, sin mirar el motivo. installReaderStatus
-- llama a TerminalAccess.findNearestKnownComputer(), un escaneo cuadrado
-- completo (getGridSquare + iterar objetos de cada casilla) del rango de
-- proximidad configurado - con "red vacante" (el estado exacto reproducido:
-- 3 redes reconciliadas tras morir, sin haber reclamado todavia) ese escaneo
-- se repetia unas 7-8 veces por segundo de forma indefinida solo para
-- alimentar una firma cuyo resultado nunca se pintaba en pantalla.
-- Reproduccion real del usuario: el cuelgue ocurrio con la pantalla de
-- bloqueo abierta, ANTES de reclamar, justo al cruzar el rango de proximidad
-- ("a unas 8-9 celdas la ventana cambio... al alejarme, ya estaba colgado").
local READER_STATUS_EXCLUDED_REASONS = {
	tablet_out_of_range = true,
	antenna_out_of_range = true,
	tablet_addon_required = true,
	network_vacant = true,
	denied = true,
	no_permission = true,
}

local function reasonNeedsReaderStatus(reason)
	return not READER_STATUS_EXCLUDED_REASONS[reason]
end

local function stateSignature(state)
	if not state then
		return ""
	end
	local rs = {}
	if reasonNeedsReaderStatus(state.reason) then
		local player = GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer() or getPlayer()
		rs = installReaderStatus and installReaderStatus(player) or {}
	end
	return table.concat({
		tostring(state.reason),
		tostring(state.proximityRange),
		tostring(rs.hasReader),
		tostring(rs.hasDisk),
		tostring(rs.computerState),
		tostring(state.canClaimOwnership),
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
	state.networkId = prev.networkId
	state.canClaimOwnership = prev.canClaimOwnership
	state.claimTier = prev.claimTier
	state.canRecoverRole = prev.canRecoverRole
	state.recoverableRole = prev.recoverableRole
	return state
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
	elseif state and state.reason == "network_vacant" then
		hintKey = "IGUI_GS_NetworkVacantBlocked"
	elseif state and (state.reason == "denied" or state.reason == "no_permission") then
		hintKey = "IGUI_GS_BlockedNoAccess"
	end
	local wrapW = math.max(260, panelWidth - INTRO_PAD * 2)
	local lines = GlobalStorageSiK.SiK_UI.wrapTextLines(T(hintKey, prox), wrapW, UIFont.Small)
	if extraKey then
		for _, line in ipairs(GlobalStorageSiK.SiK_UI.wrapTextLines(T(extraKey, prox), wrapW, UIFont.Small)) do
			lines[#lines + 1] = line
		end
	end
	return lines
end

local function measureIntroHeight(panelWidth, state)
	local wrapW = math.max(260, panelWidth - INTRO_PAD * 2)
	local lines = GlobalStorageSiK.SiK_UI.wrapTextLines(T("IGUI_GS_BlockedMessage"), wrapW, UIFont.Small)
	local lh = FONT_HGT_SMALL + LINE_GAP
	local hintLines = introApproachHintLines(panelWidth, state)
	-- Version del mod visible aqui (pedido 2026-08-15, ronda de pruebas
	-- -devN del equipo): la pantalla de bloqueo es la que ven SIEMPRE al
	-- entrar sin terminal a mano, asi confirman de un vistazo que build
	-- cargo el juego sin tener que abrir consola ni preguntar por chat.
	return INTRO_PAD + #lines * lh + 8 + #hintLines * lh + 8 + lh + INTRO_PAD
end

--- Color ok/falta de un requisito - antes cada sitio repetia el mismo
--- literal (0.5/0.78/0.5 vs 0.82/0.32/0.32) 6 veces en este fichero, sin
--- relacion con la paleta compartida (pedido 2026-08-26: "ajustarse a la
--- nueva UI y las herramientas ya generadas"). Los valores de PALETTE son
--- casi identicos (diferencia solo de matiz), asi que no cambia el aspecto
--- de forma perceptible, solo deja de duplicar el color a mano.
---@param ok boolean
---@return number r
---@return number g
---@return number b
local function reqColor(ok)
	local pal = GlobalStorageSiK.SiK_UI.PALETTE
	local c = ok and pal.statusOk or pal.statusDanger
	return c[1], c[2], c[3]
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


local function drawIntroBlock(panel)
	local state = panel.blockedState or {}
	local y = INTRO_PAD
	local lh = FONT_HGT_SMALL + LINE_GAP
	local wrapW = math.max(260, panel.width - INTRO_PAD * 2)
	local pal = GlobalStorageSiK.SiK_UI.PALETTE
	for _, line in ipairs(GlobalStorageSiK.SiK_UI.wrapTextLines(T("IGUI_GS_BlockedMessage"), wrapW, UIFont.Small)) do
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
	panel:drawText(versionLine, INTRO_PAD, y, pal.textMuted[1], pal.textMuted[2], pal.textMuted[3], 0.55, UIFont.Small)
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
	-- Rediseño 2026-08-26 (maqueta validada, "revisar bloqueo/reclamar/sin
	-- red para que se ajusten a la nueva UI"): "Conseguir PC" vivia como
	-- boton suelto FUERA de esta tarjeta aunque es la misma pregunta ("como
	-- consigo acceso fisico") - ahora entra en la misma tarjeta, debajo de
	-- Instalar aqui/Fabricar lector, solo cuando no se ha detectado ningun
	-- ordenador cerca.
	local showPcBtn = status.computerState == "none"
	local cardH = titleH + pad + bodyH + CRAFT_BTN_H + 12
	if showPcBtn then
		cardH = cardH + CRAFT_BTN_H + 6
	end

	local card = ISPanel:new(CONTENT_PAD, y, cardW, cardH)
	card:initialise()
	card.drawBackground = false
	card.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
	card.prerender = function(panel)
		ISPanel.prerender(panel)
		GlobalStorageSiK.SiK_UI.drawCardBackground(panel, titleH)
		local pal = GlobalStorageSiK.SiK_UI.PALETTE
		panel:drawText(T("IGUI_GS_InstallReaderCardTitle"), pad, 3, pal.textPrimary[1], pal.textPrimary[2], pal.textPrimary[3], 1, UIFont.Small)
		local ly = titleH + pad
		local textX = pad + REQ_ICON + REQ_ICON_GAP
		for i = 1, #lines do
			local spec = lines[i]
			local r, g, b = reqColor(spec.ok)
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

	-- BUG REAL reportado por el usuario con captura (2026-08-26): btnY se
	-- calculaba como "cardH - CRAFT_BTN_H - 6" - correcto SOLO cuando la
	-- tarjeta terminaba justo despues de esta fila de botones. Al añadir el
	-- boton "Conseguir PC" (que amplia cardH con un CRAFT_BTN_H+6 extra), ese
	-- mismo calculo desplazaba la fila "Instalar aqui/Fabricar lector" hacia
	-- ABAJO (dejando un hueco vacio de sobra) y empujaba "Conseguir PC" fuera
	-- del borde de la tarjeta, solapando la siguiente ("Tus redes"). btnY
	-- debe anclarse al final del CUERPO (titulo+lineas), nunca al final de
	-- la tarjeta completa, para no depender de cuantos botones vengan despues.
	local btnY = titleH + pad + bodyH + 6
	-- Si falta el lector, se lo ponemos fácil: un botón "Fabricar lector" al
	-- lado de "Instalar aquí" que abre la misma ventana propia que ya usa
	-- "Conseguir PC" (validar requisitos, esperar el tiempo de crafteo,
	-- añadir el resultado al inventario) en vez de mandar al jugador al menú
	-- vanilla a craftear 3 piezas por separado.
	local installBtnW = textW
	if not status.hasReader then
		installBtnW = math.floor((textW - 8) / 2)
	end

	local btn = GlobalStorageSiK.SiK_UI.createButton(
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
		end, nil, true)
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
		local buildReaderBtn = GlobalStorageSiK.SiK_UI.createButton(
			pad + installBtnW + 8, btnY, installBtnW, CRAFT_BTN_H, T("IGUI_GS_ReaderAcquireOpenBtn"), card, function()
				GlobalStorageSiK.ReaderAcquireUI.show(GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer() or getPlayer())
			end, nil, true)
		card.buildReaderBtn = buildReaderBtn
		card:addChild(buildReaderBtn)
	end

	if showPcBtn then
		local pcBtn = GlobalStorageSiK.SiK_UI.createButton(
			pad, btnY + CRAFT_BTN_H + 6, textW, CRAFT_BTN_H, T("IGUI_GS_PCAcquireOpenBtn"), card, function()
				GlobalStorageSiK.PCAcquireUI.show(GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer() or getPlayer())
			end, nil, true)
		card.pcBtn = pcBtn
		card:addChild(pcBtn)
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
		GlobalStorageSiK.SiK_UI.drawCardBackground(panel, 0)
		drawIntroBlock(panel)
	end
	GlobalStorageSiK.TerminalScroll.addChild(scroll, intro)
	y = y + introH + CARD_GAP

	-- Rediseño 2026-08-26 (maqueta validada, "revisar bloqueo/reclamar/sin
	-- red para que se ajusten a la nueva UI"): antes cada bloque vivia
	-- suelto directamente sobre el fondo del scroll, sin ningun tratamiento
	-- de tarjeta salvo la de instalar lector - ahora los 4 bloques (Estado,
	-- Recuperar acceso, Instalar terminal, Tus redes) comparten la misma
	-- tarjeta con borde/cabecera (drawCardBackground), agrupados por
	-- intencion en vez de por orden de aparicion historico. Ningun cambio de
	-- condicion de visibilidad ni de texto - solo el contenedor visual.
	local claimEligible = terminal.blockedState and terminal.blockedState.reason == "network_vacant"
		and terminal.blockedState.canClaimOwnership
	-- Diseño "recuperacion de rol propio" (2026-08-23): independiente del
	-- de arriba (canClaimOwnership decide QUIEN se convierte en el nuevo
	-- propietario; esto es "esta cuenta ya tenia SU PROPIO rol aqui, se lo
	-- devolvemos") - no depende de reason=="network_vacant", un ex-admin/
	-- member muerto ante una red que SIGUE teniendo dueño (reason=="denied")
	-- tambien debe poder recuperar su acceso. Pueden aparecer los dos
	-- botones a la vez si el jugador es elegible para ambos.
	local recoverEligible = terminal.blockedState and terminal.blockedState.canRecoverRole
	if claimEligible or recoverEligible then
		local pad = 10
		local titleH = FONT_HGT_SMALL + 10
		local btnCount = (claimEligible and 1 or 0) + (recoverEligible and 1 or 0)
		local cardH = titleH + pad + btnCount * (CRAFT_BTN_H + 6)
		local card = ISPanel:new(CONTENT_PAD, y, cardW, cardH)
		card:initialise()
		card.drawBackground = false
		card.prerender = function(panel)
			ISPanel.prerender(panel)
			GlobalStorageSiK.SiK_UI.drawCardBackground(panel, titleH)
			local pal = GlobalStorageSiK.SiK_UI.PALETTE
			panel:drawText(T("IGUI_GS_RecoverAccessTitle"), pad, 3, pal.textPrimary[1], pal.textPrimary[2], pal.textPrimary[3], 1, UIFont.Small)
		end
		local by = titleH + pad
		if claimEligible then
			local claimNetworkId = terminal.blockedState.networkId
			local claimBtn = GlobalStorageSiK.SiK_UI.createButton(
				pad, by, cardW - pad * 2, CRAFT_BTN_H, T("IGUI_GS_ClaimOwnershipButton"), card, function()
					if GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.sendCommand and claimNetworkId then
						GlobalStorageSiK.NetClient.sendCommand("reclaimOwnership", { networkId = claimNetworkId })
					end
				end, nil, true)
			card:addChild(claimBtn)
			by = by + CRAFT_BTN_H + 6
		end
		if recoverEligible then
			local recoverNetworkId = terminal.blockedState.networkId
			local recoverBtn = GlobalStorageSiK.SiK_UI.createButton(
				pad, by, cardW - pad * 2, CRAFT_BTN_H, T("IGUI_GS_RecoverRoleButton"), card, function()
					if GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.sendCommand and recoverNetworkId then
						GlobalStorageSiK.NetClient.sendCommand("recoverOwnRole", { networkId = recoverNetworkId })
					end
				end, nil, true)
			card:addChild(recoverBtn)
		end
		GlobalStorageSiK.TerminalScroll.addChild(scroll, card)
		y = y + cardH + CARD_GAP
	end

	-- Unico camino para conseguir un terminal: lector + disquete sobre un
	-- ordenador ya en el mapa. "Conseguir PC" (ventana propia, ver
	-- GS_PCAcquireUI.lua) vive ahora DENTRO de esta misma tarjeta (ver
	-- buildInstallReaderCard) cuando no se ha detectado ningun ordenador
	-- cerca, en vez de flotar suelto debajo como antes.
	-- Motivos de PERMISOS (ya hay terminal, ya estas cerca - lo que falta es
	-- acceso, no hardware): ofrecer "instalar terminal aqui"/"conseguir PC" es
	-- enganoso, ya existe un terminal funcional al lado. Excluidos junto con
	-- los de proximidad/hardware de siempre.
	if terminal.blockedState and reasonNeedsReaderStatus(terminal.blockedState.reason) then
		local cardH = buildInstallReaderCard(scroll, terminal, y, cardW)
		y = y + cardH + CARD_GAP
	end

	-- Boton "mostrar cobertura" RETIRADO de aqui (2026-08-17, pedido
	-- explicito): la cobertura ahora se marca por terminal concreto, desde
	-- el modal de ese terminal (GS_TerminalUI_TerminalEditor.lua,
	-- toggleSingleTerminalCoverage) - este visualizador generico "todas las
	-- redes conocidas" queda descartado por ahora, sin borrar el motor
	-- compartido de resaltado (toggleMarkKnownTerminals/redrawMarkers, mas
	-- arriba en este fichero) por si se retoma mas adelante.

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
	do
		local pad = 10
		local titleH = FONT_HGT_SMALL + 10
		local textW = math.max(120, cardW - pad * 2)
		local netLines = GlobalStorageSiK.SiK_UI.wrapTextLines(networksText, textW, UIFont.Small)
		local lh = FONT_HGT_SMALL + LINE_GAP
		local cardH = titleH + pad + #netLines * lh + 4
		local card = ISPanel:new(CONTENT_PAD, y, cardW, cardH)
		card:initialise()
		card.drawBackground = false
		card.prerender = function(panel)
			ISPanel.prerender(panel)
			GlobalStorageSiK.SiK_UI.drawCardBackground(panel, titleH)
			local pal = GlobalStorageSiK.SiK_UI.PALETTE
			panel:drawText(T("IGUI_GS_YourNetworksTitle"), pad, 3, pal.textPrimary[1], pal.textPrimary[2], pal.textPrimary[3], 1, UIFont.Small)
			local ly = titleH + pad
			for i = 1, #netLines do
				panel:drawText(netLines[i], pad, ly, pal.textMuted[1], pal.textMuted[2], pal.textMuted[3], 1, UIFont.Small)
				ly = ly + lh
			end
		end
		GlobalStorageSiK.TerminalScroll.addChild(scroll, card)
		y = y + cardH + CARD_GAP
	end

	GlobalStorageSiK.TerminalScroll.setContentHeight(scroll, y + CONTENT_PAD)
	GlobalStorageSiK.TerminalScroll.ensureScrollBars(scroll)
	GlobalStorageSiK.TerminalScroll.setScrollBarsVisible(
		scroll, (scroll._gsContentHeight or 0) > (scroll.height or 0) + 2)
	terminal.lastBlockedLayoutWidth = terminal.width
	if GlobalStorageSiK.TerminalTabs and GlobalStorageSiK.TerminalTabs.syncBlockedFrame then
		GlobalStorageSiK.TerminalTabs.syncBlockedFrame(terminal)
	end
	-- Diagnostico dedicado (sandbox DebugCatSiKUI, dev36 antes DebugModeUI, separado del ruido de red):
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
