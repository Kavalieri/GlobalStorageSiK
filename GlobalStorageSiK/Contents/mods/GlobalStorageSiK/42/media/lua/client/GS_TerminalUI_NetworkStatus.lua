--[[
	GlobalStorageSiK - Pestaña Red: bloque 1 (estado + estadísticas)
	Autor: SiK
	Fecha: 2025-06-26
]]

require "ISUI/ISPanel"
require "ISUI/ISLabel"
require "ISUI/ISTextEntryBox"
require "ISUI/ISTextBox"
require "GS_I18n"
require "GS_Config"
require "GS_Sandbox"
require "GS_NetClient"
require "GS_TerminalRegistry"
require "GS_TerminalUI_Scroll"
require "GS_SiK_UI_Core"
require "GS_SiK_UI_Palette"
require "GS_TerminalUI_BlockedPanel"

GlobalStorageSiK.TerminalNetworkStatus = {}

local T = GlobalStorageSiK.I18n.text
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local ENTRY_H = FONT_HGT_SMALL + 6
local ROW_GAP = 6
local SECTION_GAP = 12

---@param scroll ISPanel
---@param ui table
---@param key string
---@param x number
---@param y number
---@param text string
---@param r number|nil
---@param g number|nil
---@param b number|nil
---@return number
local function addStat(scroll, ui, key, x, y, text, r, g, b)
	local lbl = ISLabel:new(x, y, FONT_HGT_SMALL, text, r or 0.88, g or 0.9, b or 0.94, 1, UIFont.Small, true)
	lbl:initialise()
	GlobalStorageSiK.TerminalScroll.addChild(scroll, lbl)
	ui.stats[key] = lbl
	return y + FONT_HGT_SMALL + ROW_GAP
end

local function addIndicator(scroll, ui, key, x, y, colW)
	local rowH = FONT_HGT_SMALL + 4
	local row = GlobalStorageSiK.SiK_UI.createStatusIndicatorRow(x, y, colW, rowH)
	GlobalStorageSiK.TerminalScroll.addChild(scroll, row)
	ui.stats[key] = row
	return y + rowH + 2
end

local function setText(lbl, text, r, g, b, maxW)
	if not GlobalStorageSiK.TerminalScroll.isLiveWidget(lbl) then return end
	if maxW and maxW > 40 then
		text = GlobalStorageSiK.SiK_UI.truncateText(text or "", maxW, UIFont.Small)
	end
	if lbl.setName then lbl:setName(text) elseif lbl.name ~= nil then lbl.name = text end
	if r then lbl.r = r end
	if g then lbl.g = g end
	if b then lbl.b = b end
end

--- Construye la sub-pestaña "Estado": 4 tarjetas independientes en una sola
--- columna (Identidad, Estado, Estadísticas, Alcance), cada una con una
--- responsabilidad clara y ningún dato repetido dos veces - rediseño
--- 2026-08-26, pedido explícito del usuario ("2 columnas raras que nadie
--- entiende... información duplicada... botón de renombrar perdido").
--- Antes era UN bloque de 2 columnas donde "Acceso: Físico" aparecía a la
--- vez como indicador Y como estadística de texto, y "Renombrar" vivía a
--- media altura de la columna izquierda en vez de junto al nombre.
--- "Conseguir PC" se MUDA fuera de aquí a la sub-pestaña Admin, bajo el
--- bloque de terminales (pedido explícito: "es donde lo podemos necesitar") -
--- ver GS_TerminalUI_NetworkTerminals.lua.
---@param scroll ISPanel
---@param terminal GS_TerminalUI
---@param ui table
---@param y number
---@param innerW number
---@return number
function GlobalStorageSiK.TerminalNetworkStatus.build(scroll, terminal, ui, y, innerW)
	local pad = 8
	local cardX = pad - 4
	local cardW = innerW - (pad - 4) * 2
	local leftX = pad + 6
	local contentW = math.max(120, innerW - leftX - pad)
	ui.leftX = leftX
	ui.contentW = contentW

	-- ── Identidad: nombre + renombrar, lo primero que se ve ─────────────
	ui.identityY = y
	local identityCard = GlobalStorageSiK.SiK_UI.createSectionCard(cardX, y - 2, cardW, 10)
	identityCard._gsNetStatic = true
	GlobalStorageSiK.TerminalScroll.addChild(scroll, identityCard)
	ui.identityCard = identityCard

	local identityTitle = GlobalStorageSiK.SiK_UI.createSectionLabel(leftX, y + 2, T("IGUI_GS_NetBlockIdentity"))
	ui.identityTitle = identityTitle
	GlobalStorageSiK.TerminalScroll.addChild(scroll, identityTitle)
	y = y + FONT_HGT_SMALL + 8

	local renameW = 90
	local nameW = math.max(60, contentW - renameW - 8)
	ui.nameW = nameW
	ui.networkNameLbl = ISLabel:new(leftX, y, FONT_HGT_SMALL, "", 0.88, 0.9, 0.94, 1, UIFont.Small, true)
	ui.networkNameLbl:initialise()
	GlobalStorageSiK.TerminalScroll.addChild(scroll, ui.networkNameLbl)
	ui.networkRenameBtn = GlobalStorageSiK.SiK_UI.createButton(
		leftX + nameW + 8, y,
		renameW, ENTRY_H, T("IGUI_GS_Rename"), scroll, function()
			local player = GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer and GlobalStorageSiK.NetClient.getPlayer()
			local playerNum = player and player.getPlayerNum and player:getPlayerNum() or 0
			local current = ui.networkNameLbl and ui.networkNameLbl.name or ""
			local function onRename(_, button)
				if button and button.internal == "OK" and terminal.onRenameNetwork then
					local text = button.parent and button.parent.entry and button.parent.entry:getText()
					if text and text ~= "" then
						terminal:onRenameNetwork(text)
					end
				end
			end
			local bw, bh = 320, 180
			local bx = math.floor((getCore():getScreenWidth() - bw) / 2)
			local by = math.floor((getCore():getScreenHeight() - bh) / 2)
			local box = ISTextBox:new(bx, by, bw, bh, T("IGUI_GS_NetworkNameSection"), current, nil, onRename, playerNum)
			box:initialise()
			box:addToUIManager()
			box:bringToTop()
		end
	)
	GlobalStorageSiK.TerminalScroll.addChild(scroll, ui.networkRenameBtn)
	y = y + ENTRY_H + 6
	ui.identityEndY = y
	GlobalStorageSiK.SiK_UI.resizeSectionCard(identityCard, cardX, ui.identityY - 2, cardW, ui.identityEndY - ui.identityY + 4)
	y = y + SECTION_GAP

	-- ── Estado: los 4 indicadores, ahora en grid 2x2 a ancho completo ───
	-- "Acceso: Físico" existe SOLO aquí (valAccess) - antes se repetía
	-- también como estadística de texto en la columna derecha (statAccess),
	-- eliminada por completo, nunca aportó un dato distinto.
	ui.statusY = y
	local statusCard = GlobalStorageSiK.SiK_UI.createSectionCard(cardX, y - 2, cardW, 10)
	statusCard._gsNetStatic = true
	GlobalStorageSiK.TerminalScroll.addChild(scroll, statusCard)
	ui.statusCard = statusCard

	-- Reutiliza IGUI_GS_NetBlockOverview ("Estado de la red") - encaja
	-- exactamente con este bloque, sin crear una clave nueva para lo mismo.
	local statusTitle = GlobalStorageSiK.SiK_UI.createSectionLabel(leftX, y + 2, T("IGUI_GS_NetBlockOverview"))
	ui.statusTitle = statusTitle
	GlobalStorageSiK.TerminalScroll.addChild(scroll, statusTitle)
	y = y + FONT_HGT_SMALL + 8

	-- Grid 2x2: mismo alto de fila que ya calcula addIndicator internamente
	-- (FONT_HGT_SMALL + 4, + 2 de separacion) - se replica aqui como
	-- constante en vez de usar el valor de retorno (pensado para apilado
	-- vertical de una sola columna, no para 2 columnas a la misma fila).
	local indGap = 10
	local indColW = math.floor((contentW - indGap) / 2)
	ui.indColW = indColW
	local rightColX = leftX + indColW + indGap
	local indRowStep = (FONT_HGT_SMALL + 4) + 2
	local row1Y, row2Y = y, y + indRowStep
	addIndicator(scroll, ui, "valPower", leftX, row1Y, indColW)
	addIndicator(scroll, ui, "valTerminal", rightColX, row1Y, indColW)
	addIndicator(scroll, ui, "valZones", leftX, row2Y, indColW)
	addIndicator(scroll, ui, "valAccess", rightColX, row2Y, indColW)
	ui.statusEndY = row2Y + indRowStep
	GlobalStorageSiK.SiK_UI.resizeSectionCard(statusCard, cardX, ui.statusY - 2, cardW, ui.statusEndY - ui.statusY + 4)
	y = ui.statusEndY + SECTION_GAP

	-- ── Estadísticas: nodos/tipos/consumo/peso + último escaneo + accion ─
	ui.statsY = y
	local statsCard = GlobalStorageSiK.SiK_UI.createSectionCard(cardX, y - 2, cardW, 10)
	statsCard._gsNetStatic = true
	GlobalStorageSiK.TerminalScroll.addChild(scroll, statsCard)
	ui.statsCard = statsCard

	local statsTitle = GlobalStorageSiK.SiK_UI.createSectionLabel(leftX, y + 2, T("IGUI_GS_NetBlockStats"))
	ui.statsTitle = statsTitle
	GlobalStorageSiK.TerminalScroll.addChild(scroll, statsTitle)
	y = y + FONT_HGT_SMALL + 8

	y = addStat(scroll, ui, "statNodes", leftX, y, "")
	y = addStat(scroll, ui, "statItems", leftX, y, "")
	y = addStat(scroll, ui, "statAccess", leftX, y, "")
	y = addStat(scroll, ui, "statFuel",  leftX, y, "")

	-- Widget combinado: label de peso + barra de progreso en un único hijo del scroll.
	-- Un solo hijo mantiene estable la X al actualizar el ancho del contenido.
	local barH = math.max(10, math.floor(FONT_HGT_SMALL * 0.85))
	local statBarH = FONT_HGT_SMALL + ROW_GAP + barH
	local statWeightRow = ISPanel:new(leftX, y, contentW, statBarH)
	statWeightRow:initialise()
	statWeightRow.drawBackground = false
	statWeightRow.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
	statWeightRow.borderColor    = { r = 0, g = 0, b = 0, a = 0 }
	statWeightRow.capacityPercent = 0
	statWeightRow.capacityStatus  = "ok"
	statWeightRow._barH = barH
	statWeightRow.r = 0.72
	statWeightRow.g = 0.88
	statWeightRow.b = 0.72
	statWeightRow.prerender = function(b)
		ISPanel.prerender(b)
		local lbl = b.name or ""
		b:drawText(lbl, 0, 0, b.r or 0.88, b.g or 0.9, b.b or 0.94, 1, UIFont.Small)
		local fill = math.max(0, math.min(1, (b.capacityPercent or 0) / 100))
		local fr, fg, fb
		if b.capacityStatus == "warning" then
			fr, fg, fb = 0.95, 0.7, 0.2
		elseif b.capacityStatus == "critical" or b.capacityStatus == "full" then
			fr, fg, fb = 0.9, 0.3, 0.25
		else
			fr, fg, fb = GlobalStorageSiK.SiK_UI.getBarColor(fill)
		end
		local bh = b._barH or 10
		GlobalStorageSiK.SiK_UI.drawProgressBar(b, 0, FONT_HGT_SMALL + ROW_GAP, b.width, bh, fill, fr, fg, fb)
	end
	GlobalStorageSiK.TerminalScroll.addChild(scroll, statWeightRow)
	ui.stats.statWeight = statWeightRow
	ui.weightBar = statWeightRow
	y = y + statBarH + ROW_GAP

	-- Antes era UNA sola linea con las 3 cifras separadas por coma ("Último
	-- escaneo: +0 nuevos, 3 actualizados, 0 offline"), que en una ISLabel de
	-- una sola linea se salia del ancho de la columna y quedaba truncada
	-- ("...actualizados,.."), sin poder leerse. Ahora cada dato va en su
	-- propia linea.
	y = addStat(scroll, ui, "scanNew",      leftX, y, "", 0.82, 0.86, 0.92)
	y = addStat(scroll, ui, "scanUpdated",  leftX, y, "", 0.82, 0.86, 0.92)
	y = addStat(scroll, ui, "scanOffline",  leftX, y, "", 0.82, 0.86, 0.92)
	y = addStat(scroll, ui, "scanOutOfRange", leftX, y, "", 0.9, 0.7, 0.3)
	-- El control manual global pertenece a Red/Nodos, junto a las zonas que
	-- afecta. Estado conserva únicamente el resultado del último escaneo.
	-- Boton "Auto-ordenar" MOVIDO (2026-08-17, pedido explicito) a la
	-- pestaña Items/almacén, arriba a la derecha del título
	-- (GS_TerminalUI.lua:buildItemsToolbar) - ya no vive aquí.
	ui.statsEndY = y
	GlobalStorageSiK.SiK_UI.resizeSectionCard(statsCard, cardX, ui.statsY - 2, cardW, ui.statsEndY - ui.statsY + 4)
	y = ui.statsEndY + SECTION_GAP

	-- ── Alcance: solo las 2 distancias - "Conseguir PC" mudado a Admin ──
	-- SOLO 2 distancias, unica fuente de verdad (GS_Sandbox), sin duplicar
	-- "realidades": antes habia HASTA 3 lineas (uso/vinculo/deteccion) con
	-- DOS valores distintos que en la practica significaban casi lo mismo
	-- ("vinculo" y "deteccion" son ahora el mismo numero, ver
	-- GS_Sandbox.getTerminalLinkMaxDistance) - confuso y no unificado.
	--  1) Alcance de uso: a que distancia se puede abrir/operar un terminal.
	--  2) Alcance de la red: hasta donde, desde un terminal activo, un
	--     contenedor se une a la red O un terminal nuevo se vincula a ella
	--     (mismo numero para ambos casos - ver "Mostrar cobertura de red").
	ui.reachY = y
	local reachCard = GlobalStorageSiK.SiK_UI.createSectionCard(cardX, y - 2, cardW, 10)
	reachCard._gsNetStatic = true
	GlobalStorageSiK.TerminalScroll.addChild(scroll, reachCard)
	ui.reachCard = reachCard

	local reachTitle = GlobalStorageSiK.SiK_UI.createSectionLabel(leftX, y + 2, T("IGUI_GS_NetBlockReach"))
	ui.reachTitle = reachTitle
	GlobalStorageSiK.TerminalScroll.addChild(scroll, reachTitle)
	y = y + FONT_HGT_SMALL + 8

	local proxRange = GlobalStorageSiK.Sandbox.getTerminalProximityRange()
	local reachRange = GlobalStorageSiK.Sandbox.getContainerMaxDistance()
	local rangeTexts = {
		T("IGUI_GS_DistTerminalUse", proxRange),
		T("IGUI_GS_DistNetworkReach", reachRange),
	}
	for i = 1, #rangeTexts do
		for _, line in ipairs(GlobalStorageSiK.SiK_UI.wrapTextLines(rangeTexts[i], contentW, UIFont.Small)) do
			local lbl = ISLabel:new(leftX, y, FONT_HGT_SMALL, line, 0.7, 0.74, 0.78, 1, UIFont.Small, true)
			lbl:initialise()
			GlobalStorageSiK.TerminalScroll.addChild(scroll, lbl)
			y = y + FONT_HGT_SMALL + 2
		end
	end
	-- Boton "mostrar cobertura" RETIRADO de aqui (2026-08-17, pedido
	-- explicito): pasa a marcarse por terminal concreto desde su propio
	-- modal (GS_TerminalUI_TerminalEditor.lua) - este visualizador generico
	-- de "todas las redes conocidas" queda descartado por ahora.
	ui.reachEndY = y + 4
	GlobalStorageSiK.SiK_UI.resizeSectionCard(reachCard, cardX, ui.reachY - 2, cardW, ui.reachEndY - ui.reachY + 4)
	ui.block1EndY = ui.reachEndY + 8

	-- dev40 (pedido explicito del usuario): selector de paleta de interfaz,
	-- movido aqui desde la pestaña Addons (alli "no tenia mucho sentido") -
	-- ubicacion provisional dentro de Opciones -> Estado, se movera de nuevo
	-- cuando se rediseñe esta pestaña a fondo (pendiente, no es el momento).
	-- FUERA de las 4 tarjetas a proposito - su propio ancho/alto se calcula
	-- solo con block1EndY, nunca con esto.
	local paletteY = ui.block1EndY + 8
	local player = GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer
		and GlobalStorageSiK.NetClient.getPlayer()
	ui.paletteSelector = GlobalStorageSiK.SiK_UI.Palette.createSelector(
		leftX, paletteY, contentW, player, function()
			if terminal and terminal.setDirty then terminal:setDirty(true) end
		end)
	GlobalStorageSiK.TerminalScroll.addChild(scroll, ui.paletteSelector)
	ui.paletteEndY = paletteY + ui.paletteSelector.height + 8
	return ui.paletteEndY
end

--- Actualiza bloque 1.
---@param ui table
---@param state table
function GlobalStorageSiK.TerminalNetworkStatus.sync(ui, state)
	state = state or {}
	local setInd = GlobalStorageSiK.SiK_UI.setStatusIndicatorRow
	local colW = ui.indColW or 120

	local powered = state.powered ~= false
	setInd(ui.stats.valPower,
		powered and T("IGUI_GS_ValPowerOk") or T("IGUI_GS_ValPowerOff"),
		powered and "ok" or "error", colW)

	-- El registro de red del cliente (GlobalStorageSiK.Network.getRegistry())
	-- es solo una cache local casi siempre vacia (confirmado en NetTrace:
	-- "C LOCAL CATALOG ... networks=0" tras cada terminalState) — los datos
	-- reales de la red viven en el servidor. Usar ese registro aqui hacia
	-- que el piloto mostrara "no detectado" en rojo aunque el terminal
	-- estuviera claramente detectado y en uso: state.terminals ya trae el
	-- recuento autoritativo enviado por el servidor en cada terminalState.
	-- state.terminals es una TABLA (lista de terminales serializados por el
	-- servidor, ver serializeTerminals en GS_Server.lua), no un numero — el
	-- NetTrace lo resume como "terminals=1" (con # ya aplicado) por su propio
	-- formato de log, lo cual induce a pensar que es un contador directo.
	local hasTerminal = #(state.terminals or {}) > 0
	if state.terminalAnchor and state.terminalAnchor.x then
		hasTerminal = true
	end
	setInd(ui.stats.valTerminal,
		hasTerminal and T("IGUI_GS_ValTerminalOk") or T("IGUI_GS_ValTerminalMissing"),
		hasTerminal and "ok" or "error", colW)

	local zones = state.zones or {}
	local hasZones = #zones > 0
	setInd(ui.stats.valZones,
		hasZones and T("IGUI_GS_ValZonesOk", #zones) or T("IGUI_GS_ValZonesMissing"),
		hasZones and "ok" or "warn", colW)

	local accessible = powered and hasZones
	setInd(ui.stats.valAccess,
		accessible and T("IGUI_GS_ValNetworkReady") or T("IGUI_GS_ValNetworkBlocked"),
		accessible and "ok" or "error", colW)

	setText(ui.stats.statNodes, T("IGUI_GS_StatsNodes", #(state.nodes or {})))
	setText(ui.stats.statItems, T("IGUI_GS_StatsItems", state.itemTypeCount or 0))

	-- OJO: statAccess (Físico/Inalámbrico/Bypass, el MEDIO de acceso) NO es
	-- lo mismo que el indicador valAccess de arriba (si la red está
	-- operativa/bloqueada, según energía+zonas) - se confundieron como
	-- duplicados en la maqueta inicial y se corrigió antes de tocar Lua:
	-- son 2 datos distintos, los 2 se conservan (statAccess vive ahora en el
	-- bloque Estadísticas, ver build()).
	local mode = state.accessMode
	local accessText = T("IGUI_GS_NetAccessPhysical")
	if mode == "wireless" then accessText = T("IGUI_GS_NetAccessWireless")
	elseif mode == "bypass" then accessText = T("IGUI_GS_NetAccessBypass") end
	setText(ui.stats.statAccess, accessText)

	-- Consumo de combustible (opcional, ver GS_FuelConsumption.lua): "0" si
	-- esta desactivado en el sandbox, la red sigue funcionando igual, solo
	-- no gasta nada. El desglose completo (base + por contenedor x N) va en
	-- el tooltip al pasar el raton, no en la propia linea, para no saturar.
	local fuel = state.fuelConsumption or {}
	local fuelTotal = tonumber(fuel.total) or 0
	setText(ui.stats.statFuel, T("IGUI_GS_StatsFuel", string.format("%.2f", fuelTotal)))
	if GlobalStorageSiK.TerminalScroll.isLiveWidget(ui.stats.statFuel) and ui.stats.statFuel.setTooltip then
		if fuel.enabled then
			ui.stats.statFuel:setTooltip(T("IGUI_GS_StatsFuelTooltipOn",
				string.format("%.2f", tonumber(fuel.base) or 0),
				string.format("%.2f", tonumber(fuel.perContainer) or 0),
				tostring(fuel.containerCount or 0),
				string.format("%.2f", fuelTotal)))
		else
			ui.stats.statFuel:setTooltip(T("IGUI_GS_StatsFuelTooltipOff"))
		end
	end

	local cap = state.capacity or {}
	local used = string.format("%.1f", tonumber(cap.usedWeight) or 0)
	local total = string.format("%.1f", tonumber(cap.totalCapacity) or 0)
	local pct = tonumber(cap.percent) or 0
	local wt = (cap.totalCapacity or 0) > 0 and T("IGUI_GS_WeightUsage", used, total, tostring(pct) .. "%") or T("IGUI_GS_WeightUsedOnly", used)
	setText(ui.stats.statWeight, wt)
	if GlobalStorageSiK.TerminalScroll.isLiveWidget(ui.weightBar) then
		ui.weightBar.capacityPercent = pct
		ui.weightBar.capacityStatus = cap.status or "ok"
	end

	local scan = state.scan or {}
	local scanStatus = state.scanStatus or {}
	local scanState = scanStatus.state or (state.scanActive == true and "RUNNING" or "IDLE")
	local scanRunning = scanState == "RUNNING"
	local progressText = T("IGUI_GS_ScanRunning")
	if scanRunning and (scanStatus.zonesTotal or 0) > 0 then
		progressText = T("IGUI_GS_ScanProgress", scanStatus.zonesDone or 0, scanStatus.zonesTotal or 0,
			scanStatus.zoneName or "?")
	end
	local stateLabel = T("IGUI_GS_ScanState_" .. tostring(scanState))
	local terminalText = scanRunning and progressText or T("IGUI_GS_ScanState", stateLabel)
	local reason = scanStatus.reason
	local reasonCode = scanStatus.reasonCode or (GlobalStorageSiK.I18n
		and GlobalStorageSiK.I18n.scanReasonCode and GlobalStorageSiK.I18n.scanReasonCode(reason)) or "UNKN"
	if scanState == "FAILED" or scanState == "TIMED_OUT" then
		terminalText = "ERR · " .. reasonCode .. " · " .. terminalText
	end
	if not scanRunning and reason and reason ~= "" and reason ~= "complete" then
		terminalText = terminalText .. " · " .. T("IGUI_GS_ScanReason_" .. tostring(reason))
	end
	if not scanRunning and (scanStatus.failedZones or 0) > 0 then
		terminalText = terminalText .. " · " .. T("IGUI_GS_ScanFailedZones", scanStatus.failedZones)
	end
	setText(ui.stats.scanNew, terminalText,
		scanRunning and 0.95 or 0.82, scanRunning and 0.75 or 0.86,
		scanRunning and 0.3 or 0.92, ui.contentW)
	if GlobalStorageSiK.TerminalScroll.isLiveWidget(ui.stats.scanNew) and ui.stats.scanNew.setTooltip then
		if scanState == "FAILED" or scanState == "TIMED_OUT" then
			local reasonText = T("IGUI_GS_ScanReason_" .. tostring(reason))
			local codeName = T("IGUI_GS_ScanCode_" .. tostring(reasonCode))
			ui.stats.scanNew:setTooltip(codeName .. " (" .. reasonCode .. ")\n"
				.. reasonText .. "\n" .. T("IGUI_GS_ScanState_" .. scanState))
		else
			ui.stats.scanNew:setTooltip(nil)
		end
	end
	setText(ui.stats.scanUpdated, T("IGUI_GS_ScanUpdated", scan.updated or 0), 0.82, 0.86, 0.92, ui.contentW)
	local offlineText = T("IGUI_GS_ScanOffline", scan.offline or 0)
	if scan.limitHit then offlineText = offlineText .. T("IGUI_GS_ScanLimitHit") end
	setText(ui.stats.scanOffline, offlineText, 0.82, 0.86, 0.92, ui.contentW)
	if GlobalStorageSiK.TerminalScroll.isLiveWidget(ui.stats.scanOutOfRange) then
		local outOfRange = scan.outOfRange or 0
		if outOfRange > 0 then
			setText(ui.stats.scanOutOfRange, T("IGUI_GS_ScanOutOfRange", outOfRange), 0.9, 0.7, 0.3, ui.contentW)
		else
			setText(ui.stats.scanOutOfRange, "", 0.9, 0.7, 0.3, ui.contentW)
		end
	end

	local name = state.networkName
	local display = name and name ~= "" and name or T("IGUI_GS_NetworkDefaultName")
	setText(ui.networkNameLbl, display, 0.88, 0.9, 0.94, ui.nameW or 180)

end

--- Reposiciona las 4 tarjetas (ancho/X) al redimensionar - las Y de cada
--- bloque se quedan fijas (ver comentario en build(): un cambio de ancho
--- real dispara una reconstrucción completa desde GS_TerminalUI_Options.lua,
--- esto solo afina geometría dentro de un ancho ya estable).
---@param scroll ISPanel
---@param ui table
---@param innerW number
function GlobalStorageSiK.TerminalNetworkStatus.layout(scroll, ui, innerW)
	if not ui or not ui.identityY then return end
	local pad = 8
	local cardX = pad - 4
	local cardW = innerW - (pad - 4) * 2
	local leftX = pad + 6
	local contentW = math.max(120, innerW - leftX - pad)
	ui.leftX = leftX
	ui.contentW = contentW

	local function resizeCard(card, startY, endY)
		if card and GlobalStorageSiK.TerminalScroll.isLiveWidget(card) then
			card:setX(cardX)
			card:setWidth(cardW)
			if startY and endY then
				card:setHeight(math.max(24, endY - startY + 4))
			end
		end
	end

	-- Identidad
	if ui.identityTitle then GlobalStorageSiK.TerminalScroll.setContentX(scroll, ui.identityTitle, leftX) end
	local renameW = 90
	local nameW = math.max(60, contentW - renameW - 8)
	ui.nameW = nameW
	if GlobalStorageSiK.TerminalScroll.isLiveWidget(ui.networkNameLbl) then
		ui.networkNameLbl:setWidth(nameW)
		GlobalStorageSiK.TerminalScroll.setContentX(scroll, ui.networkNameLbl, leftX)
	end
	if GlobalStorageSiK.TerminalScroll.isLiveWidget(ui.networkRenameBtn) then
		GlobalStorageSiK.TerminalScroll.setContentX(scroll, ui.networkRenameBtn, leftX + nameW + 8)
	end
	resizeCard(ui.identityCard, ui.identityY, ui.identityEndY)

	-- Estado (grid 2x2)
	if ui.statusTitle then GlobalStorageSiK.TerminalScroll.setContentX(scroll, ui.statusTitle, leftX) end
	local indGap = 10
	local indColW = math.floor((contentW - indGap) / 2)
	ui.indColW = indColW
	local rightColX = leftX + indColW + indGap
	local indKeysLeft = { "valPower", "valZones" }
	local indKeysRight = { "valTerminal", "valAccess" }
	for i = 1, #indKeysLeft do
		local row = ui.stats[indKeysLeft[i]]
		if row and GlobalStorageSiK.TerminalScroll.isLiveWidget(row) then
			GlobalStorageSiK.TerminalScroll.setContentX(scroll, row, leftX)
			row:setWidth(indColW)
		end
	end
	for i = 1, #indKeysRight do
		local row = ui.stats[indKeysRight[i]]
		if row and GlobalStorageSiK.TerminalScroll.isLiveWidget(row) then
			GlobalStorageSiK.TerminalScroll.setContentX(scroll, row, rightColX)
			row:setWidth(indColW)
		end
	end
	resizeCard(ui.statusCard, ui.statusY, ui.statusEndY)

	-- Estadísticas
	if ui.statsTitle then GlobalStorageSiK.TerminalScroll.setContentX(scroll, ui.statsTitle, leftX) end
	local statKeys = { "statNodes", "statItems", "statAccess", "statFuel", "scanNew", "scanUpdated", "scanOffline", "scanOutOfRange" }
	for i = 1, #statKeys do
		local lbl = ui.stats[statKeys[i]]
		if lbl and GlobalStorageSiK.TerminalScroll.isLiveWidget(lbl) then
			GlobalStorageSiK.TerminalScroll.setContentX(scroll, lbl, leftX)
		end
	end
	if ui.weightBar and GlobalStorageSiK.TerminalScroll.isLiveWidget(ui.weightBar) then
		GlobalStorageSiK.TerminalScroll.setContentX(scroll, ui.weightBar, leftX)
		ui.weightBar:setWidth(contentW)
	end
	resizeCard(ui.statsCard, ui.statsY, ui.statsEndY)

	-- Alcance
	if ui.reachTitle then GlobalStorageSiK.TerminalScroll.setContentX(scroll, ui.reachTitle, leftX) end
	resizeCard(ui.reachCard, ui.reachY, ui.reachEndY)

	if ui.paletteSelector and GlobalStorageSiK.TerminalScroll.isLiveWidget(ui.paletteSelector) then
		GlobalStorageSiK.TerminalScroll.setContentX(scroll, ui.paletteSelector, leftX)
		GlobalStorageSiK.SiK_UI.Palette.layoutSelector(ui.paletteSelector, contentW)
	end
end
