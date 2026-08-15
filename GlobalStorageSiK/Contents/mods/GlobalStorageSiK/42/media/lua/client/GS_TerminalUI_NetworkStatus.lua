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
require "GS_TerminalUI_Chrome"
require "GS_TerminalUI_BlockedPanel"
require "GS_PCAcquireUI"

GlobalStorageSiK.TerminalNetworkStatus = {}

local T = GlobalStorageSiK.I18n.text
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local ENTRY_H = FONT_HGT_SMALL + 6
local ROW_GAP = 6
local COL_GAP = 12
local ACTION_BTN_MAX_W = 220

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
	local row = GlobalStorageSiK.TerminalChrome.createStatusIndicatorRow(x, y, colW, rowH)
	GlobalStorageSiK.TerminalScroll.addChild(scroll, row)
	ui.stats[key] = row
	return y + rowH + 2
end

local function setText(lbl, text, r, g, b, maxW)
	if not GlobalStorageSiK.TerminalScroll.isLiveWidget(lbl) then return end
	if maxW and maxW > 40 then
		text = GlobalStorageSiK.TerminalChrome.truncateText(text or "", maxW, UIFont.Small)
	end
	if lbl.setName then lbl:setName(text) elseif lbl.name ~= nil then lbl.name = text end
	if r then lbl.r = r end
	if g then lbl.g = g end
	if b then lbl.b = b end
end

--- Construye bloque 1 en dos columnas.
---@param scroll ISPanel
---@param terminal GS_TerminalUI
---@param ui table
---@param y number
---@param innerW number
---@return number
function GlobalStorageSiK.TerminalNetworkStatus.build(scroll, terminal, ui, y, innerW)
	local pad = 8
	local colW = math.floor((innerW - pad * 2 - COL_GAP) / 2)
	local leftX = pad + 6
	local rightX = pad + colW + COL_GAP
	ui.block1Y = y
	ui.colW = colW

	local card = GlobalStorageSiK.TerminalChrome.createSectionCard(pad - 4, y - 2, innerW - (pad - 4) * 2, 10)
	card._gsNetStatic = true
	GlobalStorageSiK.TerminalScroll.addChild(scroll, card)
	ui.block1Card = card

	local title = GlobalStorageSiK.TerminalChrome.createSectionLabel(leftX, y + 2, T("IGUI_GS_NetBlockOverview"))
	ui.block1Title = title
	GlobalStorageSiK.TerminalScroll.addChild(scroll, title)
	y = y + FONT_HGT_SMALL + 8

	local ly, ry = y, y
	ly = addIndicator(scroll, ui, "valPower",    leftX, ly, colW - 6)
	ly = addIndicator(scroll, ui, "valTerminal", leftX, ly, colW - 6)
	ly = addIndicator(scroll, ui, "valZones",    leftX, ly, colW - 6)
	ly = addIndicator(scroll, ui, "valAccess",   leftX, ly, colW - 6)

	local nameW = math.max(60, math.min(colW - 90, 180))
	ui.networkNameLbl = ISLabel:new(leftX, ly, FONT_HGT_SMALL, "", 0.88, 0.9, 0.94, 1, UIFont.Small, true)
	ui.networkNameLbl:initialise()
	GlobalStorageSiK.TerminalScroll.addChild(scroll, ui.networkNameLbl)
	ui.networkRenameBtn = GlobalStorageSiK.TerminalChrome.createNeatButton(
		leftX + nameW + 4, ly,
		84, ENTRY_H, T("IGUI_GS_Rename"), scroll, function()
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
	ly = ly + ENTRY_H + ROW_GAP

	-- "Zonas: N" ya NO se repite aqui: el indicador de la izquierda
	-- (valZones, "Zonas: N configurada(s)") ya cubre lo mismo con mas
	-- contexto (estado OK/error incluido) - mostrarlo dos veces desequilibraba
	-- la columna derecha sin aportar nada nuevo.
	ry = addStat(scroll, ui, "statNodes",  rightX, ry, "")
	ry = addStat(scroll, ui, "statItems",  rightX, ry, "")
	ry = addStat(scroll, ui, "statAccess", rightX, ry, "")
	ry = addStat(scroll, ui, "statFuel",   rightX, ry, "")

	-- Widget combinado: label de peso + barra de progreso en un único hijo del scroll.
	-- Un solo hijo evita que NIScrollView resetee la X al actualizar el ancho.
	local barH = math.max(10, math.floor(FONT_HGT_SMALL * 0.85))
	local statBarH = FONT_HGT_SMALL + ROW_GAP + barH
	local statWeightRow = ISPanel:new(rightX, ry, colW - 8, statBarH)
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
			fr, fg, fb = GlobalStorageSiK.TerminalChrome.getBarColor(fill)
		end
		local bh = b._barH or 10
		GlobalStorageSiK.TerminalChrome.drawProgressBar(b, 0, FONT_HGT_SMALL + ROW_GAP, b.width, bh, fill, fr, fg, fb)
	end
	GlobalStorageSiK.TerminalScroll.addChild(scroll, statWeightRow)
	ui.stats.statWeight = statWeightRow
	ui.weightBar = statWeightRow
	ry = ry + statBarH + ROW_GAP

	-- Antes era UNA sola linea con las 3 cifras separadas por coma ("Último
	-- escaneo: +0 nuevos, 3 actualizados, 0 offline"), que en una ISLabel de
	-- una sola linea se salia del ancho de la columna y quedaba truncada
	-- ("...actualizados,.."), sin poder leerse. Ahora cada dato va en su
	-- propia linea.
	ry = addStat(scroll, ui, "scanNew",      rightX, ry, "", 0.82, 0.86, 0.92)
	ry = addStat(scroll, ui, "scanUpdated",  rightX, ry, "", 0.82, 0.86, 0.92)
	ry = addStat(scroll, ui, "scanOffline",  rightX, ry, "", 0.82, 0.86, 0.92)
	ry = addStat(scroll, ui, "scanOutOfRange", rightX, ry, "", 0.9, 0.7, 0.3)
	local btnH = FONT_HGT_SMALL + 8
	ui.rescanBtn = GlobalStorageSiK.TerminalChrome.createNeatButton(rightX, ry, ACTION_BTN_MAX_W, btnH, T("IGUI_GS_RescanAll"), scroll, function()
		if terminal.onRescanNetwork then terminal:onRescanNetwork() end
	end)
	GlobalStorageSiK.TerminalScroll.addChild(scroll, ui.rescanBtn)
	ry = ry + btnH + ROW_GAP
	-- Boton "Auto-ordenar" MOVIDO (2026-08-17, pedido explicito) a la
	-- pestaña Items/almacén, arriba a la derecha del título
	-- (GS_TerminalUI.lua:buildItemsToolbar) - ya no vive aquí.

	-- SOLO 2 distancias, unica fuente de verdad (GS_Sandbox), sin duplicar
	-- "realidades": antes habia HASTA 3 lineas (uso/vinculo/deteccion) con
	-- DOS valores distintos que en la practica significaban casi lo mismo
	-- ("vinculo" y "deteccion" son ahora el mismo numero, ver
	-- GS_Sandbox.getTerminalLinkMaxDistance) - confuso y no unificado.
	--  1) Alcance de uso: a que distancia se puede abrir/operar un terminal.
	--  2) Alcance de la red: hasta donde, desde un terminal activo, un
	--     contenedor se une a la red O un terminal nuevo se vincula a ella
	--     (mismo numero para ambos casos - ver "Mostrar cobertura de red").
	--
	-- Van a ANCHO COMPLETO debajo de las dos columnas (no metidas en la
	-- columna izquierda con addStat): en paneles de ancho "estandar"
	-- desbordaban colW invadiendo la columna derecha ("Contenedores
	-- nuevos"/"Actualizados"). A ancho completo, con wrapTextLines, nunca
	-- pueden solaparse con la otra columna.
	local dy = math.max(ly, ry) + 4
	local proxRange = GlobalStorageSiK.Sandbox.getTerminalProximityRange()
	local reachRange = GlobalStorageSiK.Sandbox.getContainerMaxDistance()
	local rangeTexts = {
		T("IGUI_GS_DistTerminalUse", proxRange),
		T("IGUI_GS_DistNetworkReach", reachRange),
	}
	local rangeMaxW = innerW - leftX - pad
	for i = 1, #rangeTexts do
		for _, line in ipairs(GlobalStorageSiK.TerminalChrome.wrapTextLines(rangeTexts[i], rangeMaxW, UIFont.Small)) do
			local lbl = ISLabel:new(leftX, dy, FONT_HGT_SMALL, line, 0.7, 0.74, 0.78, 1, UIFont.Small, true)
			lbl:initialise()
			GlobalStorageSiK.TerminalScroll.addChild(scroll, lbl)
			dy = dy + FONT_HGT_SMALL + 2
		end
	end

	-- Boton "mostrar cobertura" RETIRADO de aqui (2026-08-17, pedido
	-- explicito): pasa a marcarse por terminal concreto desde su propio
	-- modal (GS_TerminalUI_TerminalEditor.lua) - este visualizador generico
	-- de "todas las redes conocidas" queda descartado por ahora.
	local coverageBtnH = FONT_HGT_SMALL + 8

	-- "Conseguir PC" tambien disponible aqui (no solo en la ventana de
	-- bloqueo): con terminal a mano igualmente puede faltar un ordenador
	-- libre para instalar un segundo/tercer terminal en otra zona.
	ui.getPCBtn = GlobalStorageSiK.TerminalChrome.createNeatButton(
		leftX, dy, math.min(260, rangeMaxW), coverageBtnH, T("IGUI_GS_PCAcquireOpenBtn"), scroll, function()
			GlobalStorageSiK.PCAcquireUI.show(GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer() or getPlayer())
		end
	)
	GlobalStorageSiK.TerminalScroll.addChild(scroll, ui.getPCBtn)
	dy = dy + coverageBtnH + ROW_GAP

	ui.block1EndY = math.max(ly, ry, dy) + 8
	GlobalStorageSiK.TerminalChrome.resizeSectionCard(card,
		pad - 4, ui.block1Y - 2,
		innerW - (pad - 4) * 2, ui.block1EndY - ui.block1Y + 4)
	return ui.block1EndY
end

--- Actualiza bloque 1.
---@param ui table
---@param state table
function GlobalStorageSiK.TerminalNetworkStatus.sync(ui, state)
	state = state or {}
	local setInd = GlobalStorageSiK.TerminalChrome.setStatusIndicatorRow
	local colW = ui.colW or 120

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
	setText(ui.stats.scanNew, T("IGUI_GS_ScanNew", scan.added or 0), 0.82, 0.86, 0.92, ui.colW)
	setText(ui.stats.scanUpdated, T("IGUI_GS_ScanUpdated", scan.updated or 0), 0.82, 0.86, 0.92, ui.colW)
	local offlineText = T("IGUI_GS_ScanOffline", scan.offline or 0)
	if scan.limitHit then offlineText = offlineText .. T("IGUI_GS_ScanLimitHit") end
	setText(ui.stats.scanOffline, offlineText, 0.82, 0.86, 0.92, ui.colW)
	if GlobalStorageSiK.TerminalScroll.isLiveWidget(ui.stats.scanOutOfRange) then
		local outOfRange = scan.outOfRange or 0
		if outOfRange > 0 then
			setText(ui.stats.scanOutOfRange, T("IGUI_GS_ScanOutOfRange", outOfRange), 0.9, 0.7, 0.3, ui.colW)
		else
			setText(ui.stats.scanOutOfRange, "", 0.9, 0.7, 0.3, ui.colW)
		end
	end

	local name = state.networkName
	local display = name and name ~= "" and name or T("IGUI_GS_NetworkDefaultName")
	setText(ui.networkNameLbl, display, 0.88, 0.9, 0.94, math.min((ui.colW or 200) - 90, 180))

end

--- Reposiciona columnas al redimensionar.
---@param scroll ISPanel
---@param ui table
---@param innerW number
function GlobalStorageSiK.TerminalNetworkStatus.layout(scroll, ui, innerW)
	if not ui or not ui.block1Y then return end
	local pad = 8
	local colW = math.floor((innerW - pad * 2 - COL_GAP) / 2)
	ui.colW = colW
	local leftX = pad + 6
	local rightX = pad + colW + COL_GAP
	if ui.block1Title then
		GlobalStorageSiK.TerminalScroll.setContentX(scroll, ui.block1Title, leftX)
	end
	local leftKeys = { "valPower", "valTerminal", "valZones", "valAccess" }
	for i = 1, #leftKeys do
		local row = ui.stats[leftKeys[i]]
		if row then
			GlobalStorageSiK.TerminalScroll.setContentX(scroll, row, leftX)
			row:setWidth(colW - 6)
		end
	end
	local rightKeys = { "statZones", "statNodes", "statItems", "statAccess", "statWeight", "scan" }
	for i = 1, #rightKeys do
		local lbl = ui.stats[rightKeys[i]]
		if lbl then
			GlobalStorageSiK.TerminalScroll.setContentX(scroll, lbl, rightX)
		end
	end
	if ui.weightBar and GlobalStorageSiK.TerminalScroll.isLiveWidget(ui.weightBar) then
		ui.weightBar:setWidth(colW - 8)
	end
	if ui.rescanBtn and GlobalStorageSiK.TerminalScroll.isLiveWidget(ui.rescanBtn) then
		GlobalStorageSiK.TerminalScroll.setContentX(scroll, ui.rescanBtn, rightX)
		GlobalStorageSiK.TerminalChrome.fitNeatButtonToLabel(ui.rescanBtn)
	end
	if GlobalStorageSiK.TerminalScroll.isLiveWidget(ui.networkNameLbl) then
		local nameW = math.max(60, math.min(colW - 90, 180))
		ui.networkNameLbl:setWidth(nameW)
		GlobalStorageSiK.TerminalScroll.setContentX(scroll, ui.networkNameLbl, leftX)
		if GlobalStorageSiK.TerminalScroll.isLiveWidget(ui.networkRenameBtn) then
			GlobalStorageSiK.TerminalScroll.setContentX(scroll, ui.networkRenameBtn, leftX + nameW + 4)
		end
	end
	if ui.stats.scan and GlobalStorageSiK.TerminalScroll.isLiveWidget(ui.stats.scan) then
		ui.stats.scan:setWidth(colW)
	end
	if ui.block1Card and GlobalStorageSiK.TerminalScroll.isLiveWidget(ui.block1Card) then
		ui.block1Card:setX(pad - 4)
		ui.block1Card:setWidth(innerW - (pad - 4) * 2)
		if ui.block1EndY then
			ui.block1Card:setHeight(ui.block1EndY - ui.block1Y + 4)
		end
	end
end
