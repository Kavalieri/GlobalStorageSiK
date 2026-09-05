--[[
	GlobalStorageSiK - Panel de bloqueo (sin terminal cercano)
	Autor: SiK
	Fecha: 2025-06-23
	Descripción: Aviso + receta craft; pestaña integrada en GS_TerminalUI.
]]

require "GS_I18n"
require "GS_NetClient"
require "GS_TerminalRecipes"
require "GS_CraftUtils"
require "GS_WorldHighlight"
require "GS_UI_Feedback"
require "GS_TerminalAccess"
require "GS_TerminalInstallReaderChoice"
require "GS_InstallTerminalReader"
require "GS_Config"
require "GS_Sandbox"
require "GS_PCAcquireUI"
require "GS_ReaderAcquireUI"

local UI = require "GS_UI_Framework"

GlobalStorageSiK.TerminalBlockedPanel = {}

local T = GlobalStorageSiK.I18n.text
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local LINE_GAP = 4
local CARD_GAP = 12
local CONTENT_PAD = 10
local CONTROL_METRICS = UI.Controls.metrics("standard")
local CRAFT_BTN_H = CONTROL_METRICS.buttonHeight
local REFRESH_TICKS = 8
-- Declaración adelantada: la función real se define más abajo (junto al
-- resto de la lógica del lector), pero stateSignature (justo debajo)
-- necesita poder llamarla. Un "local function" normal no sirve aquí porque
-- solo ve locales ya declaradas ANTES de su propio cuerpo en el código
-- fuente - con "local X" + "X = function()..." más abajo, la clausura
-- captura la variable (upvalue) y ve el valor real en cuanto se ejecuta,
-- no en cuanto se define.
local installReaderStatus

local function captureScrollState(scroll)
	return UI.State.snapshot({
		scrollY = UI.Scroll.getScrollOffset(scroll),
		selectedKey = scroll._sikSelectedKey,
		focusedKey = scroll._sikFocusedKey,
	})
end

local function restoreScrollState(scroll, snapshot)
	local state = UI.State.snapshot(snapshot or {})
	scroll._sikSelectedKey = state.selectedKey
	scroll._sikFocusedKey = state.focusedKey
	UI.Scroll.setScrollOffset(scroll, state.scrollY)
end

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
	-- Motivo nuevo (2026-08-26, ver GS_Permissions.lua canAccess): misma
	-- categoria que "denied"/"network_vacant" - la tarjeta de lector tampoco
	-- se pinta con este motivo, excluir desde el primer momento evita
	-- repetir el bug real ya cerrado el 2026-08-25 (escaneo de proximidad
	-- recalculandose sin parar para un motivo que nunca pinta nada).
	identity_rotation_unproven = true,
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

local function resolveReqIcon(spec)
	if spec.icon then
		return spec.icon
	end
	if spec.itemType and GlobalStorageSiK.CraftUtils.getItemIconTexture then
		return GlobalStorageSiK.CraftUtils.getItemIconTexture(spec.itemType)
	end
	return nil
end

local function cardHost(scroll)
	return UI.Scroll.childHost(scroll)
end

local function createStaticBlock(scroll, y, width, height, title, tooltip)
	return assert(UI.Block.create({
		parent = cardHost(scroll), x = CONTENT_PAD, y = y,
		w = width, h = height, title = title, variant = "section",
		tooltip = tooltip,
	}))
end

local function blockChildArea(block)
	return block.panel, block:getContentRect()
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
	local gap = CONTROL_METRICS.controlGap
	local player = GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer() or getPlayer()
	local status = installReaderStatus(player)

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

	-- Rediseño 2026-08-26 (maqueta validada, "revisar bloqueo/reclamar/sin
	-- red para que se ajusten a la nueva UI"): "Conseguir PC" vivia como
	-- boton suelto FUERA de esta tarjeta aunque es la misma pregunta ("como
	-- consigo acceso fisico") - ahora entra en la misma tarjeta, debajo de
	-- Instalar aqui/Fabricar lector, solo cuando no se ha detectado ningun
	-- ordenador cerca.
	local showPcBtn = status.computerState == "none"
	local card = createStaticBlock(scroll, y, cardW, 1000,
		T("IGUI_GS_InstallReaderCardTitle"),
		T("IGUI_GS_BlockedApproachReader"))
	local body, content = blockChildArea(card)
	local rowY = 0
	for i = 1, #lines do
		local spec = lines[i]
		local row = UI.Controls.requirementRow(body, {
			x = content.x, y = content.y + rowY, w = content.w, text = spec.text,
			texture = resolveReqIcon(spec), state = spec.ok,
		})
		rowY = rowY + row.height + gap
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
	local btnY = rowY + 2
	-- Si falta el lector, se lo ponemos fácil: un botón "Fabricar lector" al
	-- lado de "Instalar aquí" que abre la misma ventana propia que ya usa
	-- "Conseguir PC" (validar requisitos, esperar el tiempo de crafteo,
	-- añadir el resultado al inventario) en vez de mandar al jugador al menú
	-- vanilla a craftear 3 piezas por separado.
	local installBtnW = content.w
	if not status.hasReader then
		installBtnW = math.floor((content.w - gap) / 2)
	end
	local primaryActions = assert(UI.ActionGroup.create({
		parent = body, x = content.x, y = content.y + btnY, w = content.w, h = CRAFT_BTN_H,
		mode = "equal", gap = gap, padding = 0,
	}))

	-- Decision revertida (2026-08-26, pedido explicito del usuario, mismo
	-- criterio ya aplicado a Programacion/PC/disquetera): antes este boton se
	-- dejaba SIEMPRE activo y solo avisaba con un halo note al pulsar si
	-- faltaba algo (comentario historico: un boton desactivado no procesaba
	-- el clic en absoluto en PZ, asi que un jugador con requisitos en verde
	-- podia ver el boton "sin efecto" sin explicacion). El nuevo patron
	-- "locked" ya resuelve eso con un tooltip explicito en vez de necesitar
	-- el clic para avisar - se pinta bloqueado de verdad mientras falte algo,
	-- y se refresca solo cuando cambia el estado real (stateSignature/
	-- applyRefreshIfNeeded, cada REFRESH_TICKS), igual de "tiempo real" que
	-- el resto de indicadores de esta misma tarjeta.
	local btn = UI.Controls.button(primaryActions.panel, {
		x = 0, y = 0, w = installBtnW, h = CRAFT_BTN_H,
		text = T("IGUI_GS_InstallReaderCardBtn"), locked = not status.allReady,
		onClick = function()
			local p = GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer() or getPlayer()
			local st = installReaderStatus(p)
			if st.allReady then
				-- Igual que el menu contextual del disquete: inicia la
				-- instalacion directamente, sin abrir ningun dialogo antes.
				-- El dialogo de red nueva/existente se abre solo al terminar.
				GlobalStorageSiK.InstallTerminalReader.begin(p, st.target)
			end
		end,
	})
	if not status.allReady then
		local msg
		if not status.hasReader then
			msg = T("IGUI_GS_InstallReaderNeedReaderShort")
		elseif not status.hasDisk then
			msg = T("IGUI_GS_InstallReaderNeedDiskShort")
		elseif status.computerState == "installed" then
			msg = T("IGUI_GS_InstallReaderComputerInstalledShort")
		else
			msg = T("IGUI_GS_InstallReaderComputerNoneShort")
		end
		UI.Controls.setTooltip(btn, msg)
	end
	card.panel.installBtn = btn
	primaryActions:add(btn, { width = installBtnW, height = CRAFT_BTN_H })

	if not status.hasReader then
		local buildReaderBtn = UI.Controls.button(primaryActions.panel, {
			x = 0, y = 0, w = installBtnW, h = CRAFT_BTN_H,
			text = T("IGUI_GS_ReaderAcquireOpenBtn"), onClick = function()
				GlobalStorageSiK.ReaderAcquireUI.show(
					GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer() or getPlayer(),
					terminal
				)
			end,
		})
		card.panel.buildReaderBtn = buildReaderBtn
		primaryActions:add(buildReaderBtn, { width = installBtnW, height = CRAFT_BTN_H })
	end
	primaryActions:reflow({ x = content.x, y = content.y + btnY, w = content.w, h = CRAFT_BTN_H })
	card.panel.primaryActions = primaryActions

	local contentBottom = btnY + CRAFT_BTN_H
	if showPcBtn then
		local pcY = contentBottom + gap
		local pcBtn = UI.Controls.button(body, {
			x = content.x, y = content.y + pcY, w = content.w, h = CRAFT_BTN_H,
			text = T("IGUI_GS_PCAcquireOpenBtn"), onClick = function()
				GlobalStorageSiK.PCAcquireUI.show(
					GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer() or getPlayer(),
					terminal
				)
			end,
		})
		card.panel.pcBtn = pcBtn
		contentBottom = pcY + CRAFT_BTN_H
	end

	local cardH = 16 + CONTROL_METRICS.rowHeight + 8 + contentBottom
	card:reflow({ x = CONTENT_PAD, y = y, w = cardW, h = cardH })
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
	terminal.blockedScroll = UI.Scroll.create(terminal.blockedPanel, 0, 0, 100, 100)
	UI.Scroll.setOnContentRectChanged(terminal.blockedScroll,
		function(_, current, previous)
			if terminal.accessMode ~= "blocked" or not terminal.blockedState then return end
			if not previous or not current or current.w ~= previous.w then
				GlobalStorageSiK.TerminalBlockedPanel.rebuildContent(terminal)
			end
		end)
end

---@param terminal GS_TerminalUI
---@param innerW number
---@param innerH number
function GlobalStorageSiK.TerminalBlockedPanel.layout(terminal, innerW, innerH)
	if not terminal or not terminal.blockedScroll then
		return
	end
	-- CRITICO: terminal.blockedPanel (el contenedor con clipChildren=true que
	-- envuelve blockedScroll, creado por el shell de GS_TerminalUI) SOLO se
	-- redimensiona a traves
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
	UI.Scroll.resize(terminal.blockedScroll, innerW, innerH)
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
	if player then
		if marked == 0 then
			GlobalStorageSiK.UIFeedback.halo(player, T("IGUI_GS_CoverageNoneMarked"),
				220, 180, 100, 300, { tone = "warning", channel = "coverage" })
		else
			GlobalStorageSiK.UIFeedback.halo(player,
				T("IGUI_GS_CoverageMarkedCount", tostring(marked)),
				140, 220, 160, 300, { tone = "success", channel = "coverage" })
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

--- Resuelve todos los motivos internos como datos de una única composición.
local function resolveBlockedPresentation(state, status)
        local reason = state and state.reason or "no_terminal"
        if reason == "network_vacant" and state and state.canClaimOwnership then
                return "IGUI_GS_BlockedVacantTitle", "IGUI_GS_BlockedVacantMessage",
                        "IGUI_GS_RecoverAccessTitle", "recover"
        end
	if reason == "network_vacant" then
		return "IGUI_GS_BlockedDeniedTitle", "IGUI_GS_BlockedDeniedMessage",
			"IGUI_GS_BlockedNextStepTitle", "denied"
	end
        if state and state.canRecoverRole then
                return "IGUI_GS_BlockedRecoverTitle", "IGUI_GS_BlockedRecoverMessage",
                        "IGUI_GS_RecoverAccessTitle", "recover"
        end
        if reason == "denied" or reason == "no_permission" or reason == "identity_rotation_unproven" then
                return "IGUI_GS_BlockedDeniedTitle", "IGUI_GS_BlockedDeniedMessage",
                        "IGUI_GS_BlockedNextStepTitle", "denied"
        end
        if reason == "terminal_missing_here" then
                return "IGUI_GS_BlockedMissingTitle", "IGUI_GS_BlockedMissingMessage",
                        "IGUI_GS_BlockedNextStepTitle", "missing"
        end
        if reason == "tablet_out_of_range" or reason == "antenna_out_of_range"
                        or reason == "tablet_addon_required" then
                return "IGUI_GS_BlockedRemoteTitle", "IGUI_GS_BlockedRemoteMessage",
                        "IGUI_GS_BlockedNextStepTitle", "remote"
        end
        if not status or status.computerState == "none" then
                return "IGUI_GS_BlockedNoTerminalTitle", "IGUI_GS_BlockedNoTerminalMessage",
                        "IGUI_GS_BlockedRequirementsTitle", "install"
        end
        -- terminal_unlinked no mantiene una superficie propia: si ya no hay
        -- red activa, el ordenador vuelve al flujo normal de instalación.
        return "IGUI_GS_BlockedInstallTitle", "IGUI_GS_BlockedInstallMessage",
                "IGUI_GS_BlockedRequirementsTitle", "install"
end

local function addBlockedButton(parent, x, y, w, text, callback, locked)
        return UI.Controls.button(parent, {
                x = x, y = y, w = w, h = CRAFT_BTN_H, text = text,
                locked = locked == true, onClick = callback,
        })
end

local function buildUnifiedBlockedCard(scroll, terminal, y, cardW)
        local state = terminal.blockedState or {}
        local player = GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer() or getPlayer()
        local status = reasonNeedsReaderStatus(state.reason) and installReaderStatus(player) or nil
        local titleKey, messageKey, nestedTitleKey, mode = resolveBlockedPresentation(state, status)
        local gap = CONTROL_METRICS.controlGap
        local outer = createStaticBlock(scroll, y, cardW, 1000, T(titleKey), T(messageKey))
        local outerBody, outerContent = blockChildArea(outer)
        local messageLines = UI.Controls.wrapText(T(messageKey), math.max(120, outerContent.w), UIFont.Small)
        local message = UI.Controls.copyText(outerBody, {
                x = outerContent.x, y = outerContent.y, w = outerContent.w,
                text = table.concat(messageLines, "\n"), tone = "text",
        })
        local nestedY = outerContent.y + message.height + gap
        local nested = assert(UI.Block.create({
                parent = outerBody, x = outerContent.x, y = nestedY,
                w = outerContent.w, h = 1000, title = T(nestedTitleKey), variant = "section",
        }))
        local body, content = blockChildArea(nested)
        local rowY = 0

        if mode == "recover" then
                if state.reason == "network_vacant" and state.canClaimOwnership then
                        local claimNetworkId = state.networkId
                        local button = addBlockedButton(body, content.x, content.y + rowY, content.w,
                                T("IGUI_GS_ClaimOwnershipButton"), function()
                                        if GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.sendCommand and claimNetworkId then
                                                GlobalStorageSiK.NetClient.sendCommand("reclaimOwnership", { networkId = claimNetworkId })
                                        end
                                end)
                        rowY = rowY + button.height
                end
                if state.canRecoverRole then
                        if rowY > 0 then rowY = rowY + gap end
                        local recoverNetworkId = state.networkId
                        local button = addBlockedButton(body, content.x, content.y + rowY, content.w,
                                T("IGUI_GS_RecoverRoleButton"), function()
                                        if GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.sendCommand and recoverNetworkId then
                                                GlobalStorageSiK.NetClient.sendCommand("recoverOwnRole", { networkId = recoverNetworkId })
                                        end
                                end)
                        rowY = rowY + button.height
                end
        elseif mode == "denied" or mode == "remote" then
                local key = mode == "denied" and "IGUI_GS_BlockedDeniedNextStep" or "IGUI_GS_BlockedRemoteNextStep"
                local lines = UI.Controls.wrapText(T(key), math.max(120, content.w), UIFont.Small)
                local copy = UI.Controls.copyText(body, {
                        x = content.x, y = content.y, w = content.w,
                        text = table.concat(lines, "\n"), tone = "text",
                })
                rowY = copy.height
        elseif mode == "missing" then
                local button = addBlockedButton(body, content.x, content.y, content.w,
                        T("IGUI_GS_PCAcquireOpenBtn"), function()
                                GlobalStorageSiK.PCAcquireUI.show(
                                        GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer() or getPlayer(), terminal)
                        end)
                rowY = button.height
        else
                local requirements = {
                        { ok = status.hasReader, itemType = GlobalStorageSiK.Config.ITEM_TERMINAL_READER,
                                key = status.hasReader and "IGUI_GS_InstallReaderHasReaderShort" or "IGUI_GS_InstallReaderNeedReaderShort" },
                        { ok = status.hasDisk, itemType = "GlobalStorageSiK.GS_FloppyDisk",
                                key = status.hasDisk and "IGUI_GS_InstallReaderHasDiskShort" or "IGUI_GS_InstallReaderNeedDiskShort" },
                        { ok = status.computerState == "ready", itemType = "Base.MagnifyingGlass",
                                key = status.computerState == "ready" and "IGUI_GS_InstallReaderComputerReadyShort"
                                        or "IGUI_GS_InstallReaderComputerNoneShort" },
                }
                for i = 1, #requirements do
                        local spec = requirements[i]
                        local row = UI.Controls.requirementRow(body, {
                                x = content.x, y = content.y + rowY, w = content.w,
                                text = T(spec.key), texture = resolveReqIcon(spec), state = spec.ok,
                        })
                        rowY = rowY + row.height + gap
                end
                local acquire = {}
                if not status.hasReader then acquire[#acquire + 1] = "reader" end
                if status.computerState == "none" then acquire[#acquire + 1] = "computer" end
                if #acquire > 0 then
                        local buttonW = math.floor((content.w - gap * (#acquire - 1)) / #acquire)
                        for i = 1, #acquire do
                                local kind = acquire[i]
                                addBlockedButton(body, content.x + (i - 1) * (buttonW + gap), content.y + rowY,
                                        buttonW, T(kind == "reader" and "IGUI_GS_ReaderAcquireOpenBtn" or "IGUI_GS_PCAcquireOpenBtn"),
                                        function()
                                                local p = GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer() or getPlayer()
                                                if kind == "reader" then GlobalStorageSiK.ReaderAcquireUI.show(p, terminal)
                                                else GlobalStorageSiK.PCAcquireUI.show(p, terminal) end
                                        end)
                        end
                        rowY = rowY + CRAFT_BTN_H + gap
                end
                local installButton = addBlockedButton(body, content.x, content.y + rowY, content.w,
                        T("IGUI_GS_InstallReaderCardTitle"), function()
                                local p = GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer() or getPlayer()
                                local current = installReaderStatus(p)
                                if current.allReady then GlobalStorageSiK.InstallTerminalReader.begin(p, current.target) end
                        end, not status.allReady)
                if not status.allReady then
                        UI.Controls.setTooltip(installButton, T("IGUI_GS_InstallReaderMissingItems"))
                end
                rowY = rowY + installButton.height
        end

        local nestedH = 16 + CONTROL_METRICS.rowHeight + 8 + math.max(rowY, FONT_HGT_SMALL)
        nested:reflow({ x = outerContent.x, y = nestedY, w = outerContent.w, h = nestedH })
        local outerH = 16 + CONTROL_METRICS.rowHeight + 8 + message.height + gap + nestedH
        outer:reflow({ x = CONTENT_PAD, y = y, w = cardW, h = outerH })
        return outerH
end

---@param terminal GS_TerminalUI
local function rebuildContentBody(terminal)
	local scroll = terminal.blockedScroll
	local preservedState = captureScrollState(scroll)
	UI.Scroll.clear(scroll)
	-- Consume the Block-owned content rectangle. This changes immediately when
	-- resize or scrollbar overflow changes, instead of waiting for the periodic
	-- product refresh and rebuilding against the stale outer scroll width.
	local cardW = math.max(260, UI.Scroll.contentWidth(scroll) - CONTENT_PAD * 2)
	local y = CONTENT_PAD

        local blockedH = buildUnifiedBlockedCard(scroll, terminal, y, cardW)
        y = y + blockedH + CARD_GAP

	UI.Scroll.setContentHeight(scroll, y + CONTENT_PAD)
	UI.Scroll.ensureScrollBars(scroll)
	UI.Scroll.setScrollBarsVisible(
		scroll, (scroll._gsContentHeight or 0) > (scroll.height or 0) + 2)
	restoreScrollState(scroll, preservedState)
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
function GlobalStorageSiK.TerminalBlockedPanel.rebuildContent(terminal)
	if not terminal or not terminal.blockedScroll or terminal._gsBlockedGeometryReflow then
		return
	end
	terminal._gsBlockedGeometryReflow = true
	local ok, reason = pcall(rebuildContentBody, terminal)
	terminal._gsBlockedGeometryReflow = false
	if not ok then error(reason, 0) end
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
