--[[
	GlobalStorageSiK - Pestaña de ítems del terminal (iconos, orden, menú contextual)
	Autor: SiK
	Fecha: 2025-06-24
	Descripción: Lista virtual propia SiK UI con pool reutilizable.
]]

require "ISUI/ISContextMenu"
require "GS_CatalogManager"
require "GS_I18n"
require "GS_ItemSnapshot"
require "GS_RecordedMedia"
require "GS_UI_Feedback"
require "GS_NativeProduct"
require "GS_CategoryResolution"
require "GS_Libs"
require "GS_BulkFilters"
require "GS_DepositSources"
require "GS_TerminalWithdrawDrag"
require "GS_WithdrawMenu"
require "GS_QuantityPrompt"
require "GS_Log"
require "GS_ContextMenuUi"
require "GS_NodeHighlight"
require "GS_ContainerTargets"
local UI = require "GS_UI_Framework"
local TabWarehouseSpec = require "GlobalStorageSiK/UI/Generated/TabWarehouse"
local TabWarehouseContext = require "GlobalStorageSiK/UI/TabWarehouseContext"
require "GS_ItemNetworkTooltip"
require "GS_NetworkReadAction"
require "GS_NetClient"
require "GS_RemoteItemDetail"
local LocalItemTooltip = require "GS_LocalItemTooltip"
require "GS_UIDebug"

GlobalStorageSiK.TerminalItems = {}

local function detailPagesByRowKey()
	local client = GlobalStorageSiK.Client
	return client and client.itemDetailsCache or nil
end

-- Una cabecera agregada no lleva itemIds por contrato: antes de retirarla se
-- resuelve su pagina de instancias y se envia exclusivamente la seleccion
-- exacta. Es estado efimero de cliente, ligado a una sola operacion de drop.
local T = GlobalStorageSiK.I18n.text
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local ICON_SIZE = 32
local TABLE_METRICS = UI.Table.metrics()
local ROW_H = math.max(TABLE_METRICS.rowHeight, ICON_SIZE + 8)
local HEADER_H = TABLE_METRICS.headerHeight
local DRAG_THRESHOLD = 6
local ITEM_TEXTURE_CACHE = {}
-- Las dos columnas de la derecha no participan en el reparto flexible:
-- Table.resolveColumns las coloca desde right hacia la izquierda. Así Cant.
-- queda anclada al borde y Zona a su lado en cabecera, filas y hitboxes.
local ITEM_TABLE_COLUMNS = {
	{ key = "name", titleKey = "IGUI_GS_ColName", flex = 1, minWidth = 130, pad = 6 },
	{ key = "category", titleKey = "IGUI_GS_ColCategory", flex = 1.4, minWidth = 180, pad = 6 },
	{ key = "zone", titleKey = "IGUI_GS_ColZone", width = 110, pad = 6 },
	{ key = "count", titleKey = "IGUI_GS_ColCount", width = 70, align = "right", pad = 6 },
}
local ITEM_TABLE_OPTIONS = { left = 0, right = 0, gap = 8 }
local MOVABLE_PRESENTATION_CACHE = GlobalStorageSiK.CatalogManager
	and GlobalStorageSiK.CatalogManager.createEpochCache() or {}

function GlobalStorageSiK.TerminalItems.requestDetails(terminal, row, page)
	if terminal and terminal.requestInventoryDetails then return terminal:requestInventoryDetails(row, page) end
	if not terminal or not row or not row.rowKey or not row.expandable then return false end
	local state = terminal.terminalState or {}
	if not state.networkId then return false end
	local sent = GlobalStorageSiK.NetClient.sendCommand("getItemDetails", {
		networkId = state.networkId,
		rowKey = row.rowKey,
		inventoryRevision = state.inventoryRevision,
		page = math.max(1, math.floor(tonumber(page) or 1)),
		pageSize = 15,
	})
	return sent
end

function GlobalStorageSiK.TerminalItems.onDetailsReceived(args, accepted)
	if not args or not args.rowKey or accepted ~= true then return end
	local terminal = GlobalStorageSiK.TerminalUI and GlobalStorageSiK.TerminalUI.instance
	if terminal and terminal.itemsListPanel and terminal.refreshItemsTab then
		local panel = terminal.itemsListPanel
		panel._detailPending = panel._detailPending or {}
		panel._detailPending[args.rowKey] = nil
		terminal:refreshItemsTab()
	end
end

function GlobalStorageSiK.TerminalItems.getDetails(rowKey, panel)
	local pages = panel and panel._detailPages or detailPagesByRowKey()
	return rowKey and pages and pages[rowKey] or nil
end

--- Contrato común para tooltips de filas virtualizadas: son ornamentales y
--- nunca participan en hit-testing, captura ni diferimiento de refresh.
function GlobalStorageSiK.TerminalItems.makePassiveTooltip(tooltip)
	return UI.Tooltip.makePassive(tooltip)
end

function GlobalStorageSiK.TerminalItems.hideRowTooltip(row)
	if not row then return end
	if GlobalStorageSiK.RemoteItemDetail then
		GlobalStorageSiK.RemoteItemDetail.deactivate(row)
	end
	local tooltip = row._gsTooltip
	if not tooltip then return end
	if row._gsTooltipHandle then row._gsTooltipHandle:hide()
	else UI.Tooltip.hide(tooltip) end
	if GlobalStorageSiK.RemoteItemDetail and GlobalStorageSiK.RemoteItemDetail.unbindProbe then
		GlobalStorageSiK.RemoteItemDetail.unbindProbe(tooltip.item)
	end
	tooltip._gsItemKey, tooltip._gsRemoteRow = nil, nil
	row._gsLocalTooltip = nil
	tooltip:setItem(nil)
end

function GlobalStorageSiK.TerminalItems.disposeRowTooltip(row)
        if not row then return false end
        GlobalStorageSiK.TerminalItems.hideRowTooltip(row)
        if row._gsTooltipHandle then
                row._gsTooltipHandle:dispose()
                row._gsTooltipHandle = nil
        end
        return true
end

local function hideVirtualRowTooltips(panel)
	local pool = panel and panel.itemTable and panel.itemTable.list and panel.itemTable.list.pool or {}
	for i = 1, #pool do
		GlobalStorageSiK.TerminalItems.hideRowTooltip(pool[i])
	end
end

--- Restablece por completo el estado transitorio del pool virtual. Es la única
--- salida compartida tras drag, expansión y reciclado: ninguna fila puede
--- conservar hover/captura/tooltip de una identidad o interacción anterior.
---@param panel ISPanel|nil
function GlobalStorageSiK.TerminalItems.resetVirtualInteraction(panel)
	local pool = panel and panel.itemTable and panel.itemTable.list and panel.itemTable.list.pool or {}
	for i = 1, #pool do
		local row = pool[i]
		if row then
			GlobalStorageSiK.TerminalItems.hideRowTooltip(row)
			if GlobalStorageSiK.RemoteItemDetail then
				GlobalStorageSiK.RemoteItemDetail.deactivate(row)
			end
			row._gsExpandPressed = nil
			row._gsDragPending = false
			row._gsDragAccum = 0
			if row.setCapture then row:setCapture(false) end
		end
	end
end

-- Los tooltips de fila son una prolongacion visual del inventario vanilla,
-- nunca otra capa de input. Mantener este contrato en un unico helper evita
-- que una fila reciclada deje un ISToolTipInv capturando el expansor o drag.
function GlobalStorageSiK.TerminalItems.showRowTooltip(row)
	if not row or not row._gsTooltip then return false end
	local tooltip = GlobalStorageSiK.TerminalItems.makePassiveTooltip(row._gsTooltip)
	if not tooltip then return false end
	if not row._gsTooltipHandle or row._gsTooltipHandle.disposed then
		row._gsTooltipHandle = UI.Tooltip.attach(row, {
			kind = "object",
			variant = "transient",
			playerNum = row.terminal and row.terminal.playerNum or 0,
			channel = "warehouse-item",
			placement = { anchor = "pointer", gap = 24 },
			timeoutMs = 250,
		})
	end
	local shown = row._gsTooltipHandle:show(tooltip)
	if shown and shown.bringToTop then shown:bringToTop() end
	return shown ~= nil
end

--- Ningun refresh recicla una fila mientras click, drag o tooltip la poseen.
function GlobalStorageSiK.TerminalItems.isInteractionActive(panel)
	if not panel then return false end
	if GlobalStorageSiK.TerminalWithdrawDrag
		and GlobalStorageSiK.TerminalWithdrawDrag.isActiveForPanel
		and GlobalStorageSiK.TerminalWithdrawDrag.isActiveForPanel(panel) then
		return true
	end
	local pool = panel.itemTable and panel.itemTable.list and panel.itemTable.list.pool or {}
	for i = 1, #pool do
		local row = pool[i]
		if row and (row._gsDragPending or row._gsExpandPressed) then
			-- Una transferencia vanilla (incluidos los paneles de vehiculo) puede
			-- reconstruir la lista entre mouseDown y mouseUp. Nunca retenemos una
			-- pulsacion que ya no existe: sin boton izquierdo real, se libera todo
			-- el estado local antes de decidir diferir un refresh.
			local leftDown = isMouseButtonDown and isMouseButtonDown(0)
			if leftDown then return true end
			GlobalStorageSiK.TerminalItems.hideRowTooltip(row)
			row._gsExpandPressed = nil
			row._gsDragPending = false
			row._gsDragAccum = 0
			if row.setCapture then row:setCapture(false) end
		end
	end
	return false
end

function GlobalStorageSiK.TerminalItems.deferRefresh(panel, terminal)
	if not panel then return false end
	panel._deferredRefresh = { terminal = terminal }
	return true
end

function GlobalStorageSiK.TerminalItems.flushDeferredRefresh(panel)
	if not panel or not panel._deferredRefresh
		or GlobalStorageSiK.TerminalItems.isInteractionActive(panel) then return false end
	local deferred = panel._deferredRefresh
	panel._deferredRefresh = nil
	local terminal = deferred.terminal or panel.terminal
	if terminal and terminal.refreshItemsTab then
		terminal:refreshItemsTab()
		return true
	end
	return false
end

function GlobalStorageSiK.TerminalItems.onInteractionFinished(panel)
	if panel then return GlobalStorageSiK.TerminalItems.flushDeferredRefresh(panel) end
	local terminal = GlobalStorageSiK.TerminalUI and GlobalStorageSiK.TerminalUI.instance
	return terminal and GlobalStorageSiK.TerminalItems.flushDeferredRefresh(
		terminal.itemsListPanel) or false
end

function GlobalStorageSiK.TerminalItems.onInventoryRevisionChanged(networkId)
	local terminal = GlobalStorageSiK.TerminalUI and GlobalStorageSiK.TerminalUI.instance
	local panel = terminal and terminal.itemsListPanel or nil
	if not panel then return end
	local activeNetwork = terminal.terminalState and terminal.terminalState.networkId
	if networkId and activeNetwork and networkId ~= activeNetwork then return end
	-- Una pagina de detalle contiene itemIds fisicos ligados a una revision. No
	-- puede conservarse ni pintarse tras una mutacion: aunque el pager estuviera
	-- deshabilitado, sus filas seguian teniendo drag/click y reutilizaban IDs ya
	-- retirados. Invalida la presentacion y el fallback global de forma atomica.
	panel._detailPages, panel._detailPending = nil, {}
	panel._detailPageByKey = {}
	if GlobalStorageSiK.Client then GlobalStorageSiK.Client.itemDetailsCache = {} end
	local dragging = GlobalStorageSiK.TerminalWithdrawDrag
		and GlobalStorageSiK.TerminalWithdrawDrag.isActive
		and GlobalStorageSiK.TerminalWithdrawDrag.isActive()
	if not dragging and not (isMouseButtonDown and isMouseButtonDown(0)) then
		-- La transferencia desde/hacia un inventario vanilla no es una
		-- interaccion de fila SiK. Al llegar su revision liberamos cualquier
		-- captura/tooltip residual antes de que el refresh virtual recicle filas.
		GlobalStorageSiK.TerminalItems.resetVirtualInteraction(panel)
	end
end

-- Cierre comun de cualquier retirada iniciada desde la tabla principal. La
-- sincronizacion autoritativa sigue perteneciendo a TerminalSync; aqui solo se
-- retiran inmediatamente filas exactas que ya no son seguras para interactuar.
function GlobalStorageSiK.TerminalItems.onWithdrawCompleted(panel, terminal, ok, result)
	if not panel then return end
	panel._detailPages, panel._detailPending = nil, {}
	panel._detailPageByKey = {}
	if GlobalStorageSiK.Client then GlobalStorageSiK.Client.itemDetailsCache = {} end
	local revision = result and tonumber(result.inventoryRevision)
	if revision and terminal and terminal.terminalState then
		terminal.terminalState.inventoryRevision = revision
	end
	GlobalStorageSiK.TerminalItems.resetVirtualInteraction(panel)
	if terminal and terminal.refreshItemsTab then terminal:refreshItemsTab() end
	GlobalStorageSiK.Log.debug("ExactWithdraw", "detail-cache invalidated surface=warehouse"
		.. " ok=" .. tostring(ok == true) .. " revision=" .. tostring(revision))
end

---@param panel ISPanel
---@param fullType string|nil
---@return number|nil
local function rowIdentity(row)
	return row and (row.rowKey or row.fullType) or nil
end

-- ISToolTipInv vive como UI de raiz. Aunque sea mouse-transparent, usar
-- isMouseOver() de la fila deja que el z-order temporal del tooltip alterne
-- entre fila/tooltip y produzca el parpadeo observado tras expandir o soltar.
-- El hover de una fila virtual se decide exclusivamente por su rectangulo real.
local function pointerInsideRow(row)
	if not row or not row.getAbsoluteX or not row.getAbsoluteY then return false end
	local mx = getMouseX and getMouseX() or -1
	local my = getMouseY and getMouseY() or -1
	local x, y = row:getAbsoluteX(), row:getAbsoluteY()
	local w = row.width or (row.getWidth and row:getWidth()) or 0
	local h = row.height or (row.getHeight and row:getHeight()) or 0
	return mx >= x and my >= y and mx < x + w and my < y + h
end

local function findItemIndex(panel, key)
	local items = panel and panel._lastItems
	if not items or not key then
		return nil
	end
	for i = 1, #items do
		if rowIdentity(items[i]) == key then
			return i
		end
	end
	return nil
end

---@param panel ISPanel
---@return table[]
local function getSelectedRows(panel)
	local out = {}
	local items = panel and panel._lastItems
	if not items or not panel._selectedKeys then
		return out
	end
	for i = 1, #items do
		local row = items[i]
		local key = rowIdentity(row)
		if key and row.fullType and panel._selectedKeys[key] then
			out[#out + 1] = row
		end
	end
	return out
end

---@param panel ISPanel
---@param fullType string|nil
---@param index number|nil
local function selectSingleRow(panel, fullType, index)
	if not panel or not fullType then
		return
	end
	panel._selectedKeys = { [fullType] = true }
	panel._selectionAnchor = index or findItemIndex(panel, fullType) or 1
end

---@param panel ISPanel
---@param fullType string|nil
local function toggleRowSelection(panel, fullType)
	if not panel or not fullType then
		return
	end
	panel._selectedKeys = panel._selectedKeys or {}
	if panel._selectedKeys[fullType] then
		panel._selectedKeys[fullType] = nil
	else
		panel._selectedKeys[fullType] = true
		panel._selectionAnchor = findItemIndex(panel, fullType) or panel._selectionAnchor
	end
end

---@param panel ISPanel
---@param toIndex number
local function selectRangeTo(panel, toIndex)
	local items = panel._lastItems
	if not items or #items == 0 then
		return
	end
	local anchor = panel._selectionAnchor or toIndex
	local lo = math.max(1, math.min(anchor, toIndex))
	local hi = math.min(#items, math.max(anchor, toIndex))
	panel._selectedKeys = panel._selectedKeys or {}
	for i = lo, hi do
		local row = items[i]
		local key = rowIdentity(row)
		if key and row.fullType then
			panel._selectedKeys[key] = true
		end
	end
end

---@param panel ISPanel
---@param row ISPanel
local function handleRowClick(panel, row)
	local data = row.itemData
	if not data or not data.fullType then
		return
	end
	-- BUG REAL (auditoria post-migracion SiK_UI, dev35): `row.rowIndex` es el
	-- indice visual reasignado por VirtualList en cada refresh. Si un scroll o
	-- refresco de datos ocurre entre el
	-- mousedown y el mouseup de un clic (o durante un Shift-click posterior),
	-- puede quedar apuntando a un dato distinto del que el usuario clico de
	-- verdad, descuadrando el ancla de rango Shift. `findItemIndex` busca por
	-- identidad real (`fullType`) en el dataset actual `panel._lastItems`,
	-- siempre correcto independientemente del reciclado - preferirlo siempre;
	-- `row.rowIndex` queda solo como reserva si la busqueda no encuentra nada.
	local key = rowIdentity(data)
	local idx = findItemIndex(panel, key) or row.rowIndex or 1
	if isCtrlKeyDown and isCtrlKeyDown() then
		toggleRowSelection(panel, key)
	elseif isShiftKeyDown and isShiftKeyDown() then
		if not panel._selectionAnchor then
			panel._selectionAnchor = idx
		end
		selectRangeTo(panel, idx)
	else
		selectSingleRow(panel, key, idx)
	end
end

--- Trunca texto al ancho máximo en píxeles.
---@param text string
---@param maxW number
---@param font UIFont|nil
---@return string
local function truncateText(text, maxW, font)
	text, font, maxW = tostring(text or ""), font or UIFont.Small, math.max(0, tonumber(maxW) or 0)
	local manager = getTextManager()
	if manager:MeasureStringX(font, text) <= maxW then return text end
	local suffix, low, high, best = "...", 0, string.len(text), ""
	while low <= high do
		local middle = math.floor((low + high) / 2)
		local candidate = string.sub(text, 1, middle) .. suffix
		if manager:MeasureStringX(font, candidate) <= maxW then
			best, low = candidate, middle + 1
		else high = middle - 1 end
	end
	return best
end

GlobalStorageSiK.TerminalItems.ROW_H = ROW_H

-- BUG REAL cerrado (2026-08-22, misma clase que GS_Categories.lua/
-- GS_NetworkCapacity.lua/GS_ItemTaxonomy.lua - sm:getItem(fullType) SIN
-- CACHE, aqui llamado al construir cada fila de la tabla de items del
-- terminal): usar el cache de sesion compartido en vez de consultar
-- ScriptManager a pelo.
---@param fullType string|nil
---@return any|nil
local function scriptItem(fullType)
	if not fullType or not GlobalStorageSiK.I18n or not GlobalStorageSiK.I18n.getScriptItem then return nil end
	return GlobalStorageSiK.I18n.getScriptItem(fullType)
end

-- BUG REAL cerrado (2026-08-22, "crece sin parar" - spam de "Couldn't find
-- item X" confirmado en pruebas reales mientras el raton quedaba sobre una
-- fila con fullType corrupto): itemProbe() nunca cacheaba el caso de
-- fallo - para un item que NUNCA logra resolverse (nuestro caso real,
-- "Base.carpentry_01_16"), tanto itemTexture() como el tooltip de
-- GS_TerminalUI_Items.lua (mas abajo, prerender de la fila) volvian a
-- llamar a props:instanceItem()/instanceItem() EN CADA FRAME mientras la
-- fila seguia dibujandose/bajo el raton - sin cache posible de exito
-- porque nunca habia exito, el intento (y el log vanilla incondicional que
-- dispara) se repetia sin limite. Cachear tambien el fallo, una vez por
-- fila distinta (fullType+worldSprite) durante toda la sesion.
local PROBE_FAIL_CACHE = {}

local function applyProbeIdentity(probe, row)
	if not probe or not row then return probe end
	local mediaIndex = tonumber(row.mediaIndex)
	if mediaIndex and mediaIndex >= 0 and mediaIndex <= 32767
		and probe.setRecordedMediaIndexInteger then
		-- Wrapper vanilla Kahlua-safe (InventoryItem expone tambien un setter
		-- short que no debe invocarse directamente desde Lua). Esto hace que el
		-- nombre y MediaData del probe se resuelvan en el idioma del cliente.
		pcall(function() probe:setRecordedMediaIndexInteger(math.floor(mediaIndex)) end)
	end
	return probe
end

--- Crea una instancia de tooltip válida sin consultar como ScriptItem los
--- tokens de muebles recogidos.
---@param row table|nil
---@return InventoryItem|nil
local function itemProbe(row)
	if not row then return nil end
	local probeCacheKey = tostring(row.fullType or "") .. "\31" .. tostring(row.worldSprite or "")
	if PROBE_FAIL_CACHE[probeCacheKey] then
		return nil
	end
	-- Los muebles recogidos suelen compartir un fullType generico. Vanilla
	-- reconstruye el InventoryItem desde el sprite del mundo; hacerlo primero
	-- conserva su icono de inventario, nombre y propiedades reales.
	if row.worldSprite then
		if not ISMoveableSpriteProps then
			pcall(require, "Moveables/ISMoveableSpriteProps")
		end
		if ISMoveableSpriteProps and ISMoveableSpriteProps.new then
			local ok, probe = pcall(function()
				local props = ISMoveableSpriteProps.new(row.worldSprite)
				return props and props.instanceItem and props:instanceItem(row.worldSprite) or nil
			end)
			if ok and probe then return applyProbeIdentity(probe, row) end
		end
	end
	if scriptItem(row.fullType) and instanceItem then
		local ok, probe = pcall(instanceItem, row.fullType)
		if ok and probe then return applyProbeIdentity(probe, row) end
	end
	PROBE_FAIL_CACHE[probeCacheKey] = true
	return nil
end

local MEDIA_TITLE_CACHE = {}
local LAST_MEDIA_DIAGNOSTIC_SIGNATURE = nil

local function recordedMediaCacheKey(row, playerNum)
	local language = ""
	if getCore then
		local ok, value = pcall(function()
			local core = getCore()
			return core and core.getOptionLanguage and core:getOptionLanguage() or nil
		end)
		if ok and value then language = tostring(value) end
	end
	return table.concat({ tostring(row and row.fullType or ""), tostring(row and row.mediaIndex or ""),
		tostring(tonumber(playerNum) or 0), language }, "\31")
end

--- El nombre base de una cinta (`VHS comercial`) describe el tipo de ítem,
--- no su edición. El único fallback genérico fiable es el nombre localizado
--- del tipo: `displayName` también puede contener ya el título vanilla exacto
--- recibido del catálogo y nunca debe invalidarlo.
local function isGenericRecordedMediaTitle(title, row)
        if type(title) ~= "string" or title == "" then return true end
        local generic = row and row.fullType and GlobalStorageSiK.I18n.typeDisplayName
                and GlobalStorageSiK.I18n.typeDisplayName(row.fullType) or nil
        if generic ~= nil and title == generic then return true end
        return false
end

local function resolveRecordedMediaVanillaName(row, playerNum)
	local mediaIndex = row and tonumber(row.mediaIndex)
	if not mediaIndex or mediaIndex < 0 or mediaIndex > 32767 then return nil end
	mediaIndex = math.floor(mediaIndex)
	local cacheKey = recordedMediaCacheKey(row, playerNum)
	local cached = MEDIA_TITLE_CACHE[cacheKey]
	if cached ~= nil then return cached or nil end
	-- Primary source: the same global RecordedMedia catalogue vanilla uses for
	-- its literature/media lists. This avoids depending on a synthetic item
	-- accepting the recorded-media index during UI reconstruction.
	local title = GlobalStorageSiK.RecordedMedia
		and GlobalStorageSiK.RecordedMedia.titleFromIndex
		and GlobalStorageSiK.RecordedMedia.titleFromIndex(mediaIndex, row.fullType) or nil
	if title and not isGenericRecordedMediaTitle(title, row) then
		MEDIA_TITLE_CACHE[cacheKey] = title
		return title
	end
	local probe = itemProbe(row)
	if probe and probe.getRecordedMediaIndex then
		local ok, appliedIndex = pcall(function() return probe:getRecordedMediaIndex() end)
		if not ok or tonumber(appliedIndex) ~= mediaIndex then
			-- RecordedMedia puede no estar listo todavía durante la carga. No
			-- convertir el nombre genérico de la cinta en la identidad cacheada de
			-- esta edición: se conserva el fallback remoto y se podrá resolver tras
			-- reconstruir la superficie/sesión.
			return nil
		end
	end
	title = nil
	-- `getName(player)` es la proyección vanilla de una instancia RecordedMedia.
	-- `getDisplayName()` es el nombre estático del script ("VHS comercial") y
	-- queda expresamente fuera: no identifica la edición ni debe llegar a una fila.
	if probe and probe.getName then
		local player = getSpecificPlayer and getSpecificPlayer(tonumber(playerNum) or 0) or nil
		local ok, value = pcall(function() return probe:getName(player) end)
		if ok and not isGenericRecordedMediaTitle(value, row) then title = value end
	end
	-- Fallback localizado de MediaData para runtimes que todavía no exponen el
	-- nombre de instancia; jamás se acepta el nombre genérico como éxito.
	if not title and probe and probe.getMediaData then
		local okData, mediaData = pcall(function() return probe:getMediaData() end)
		if okData and mediaData and mediaData.getTranslatedItemDisplayName then
			local okTitle, value = pcall(function() return mediaData:getTranslatedItemDisplayName() end)
			if okTitle and not isGenericRecordedMediaTitle(value, row) then title = value end
		end
	end
	-- Si RecMedia aún no está listo, no cacheamos ni el fallo ni una etiqueta
	-- genérica: un refresh explícito podrá resolver la edición exacta.
	if title then MEDIA_TITLE_CACHE[cacheKey] = title end
	return title
end

GlobalStorageSiK.TerminalItems.resolveRecordedMediaVanillaName = resolveRecordedMediaVanillaName
GlobalStorageSiK.TerminalItems.probeForRow = itemProbe

local function localizeRecordedMediaRows(rows, playerNum)
	local total, exact, unresolved, withLearning, leisure = 0, 0, 0, 0, 0
	local samples = {}
	for i = 1, #(rows or {}) do
		local row = rows[i]
		-- mediaIndex is the canonical B42 identity. Do not make presentation
		-- depend on detailKind: older persisted snapshots and mixed-version MP
		-- rows may carry the exact index before that presentation hint.
		local isMedia = row and tonumber(row.mediaIndex) ~= nil
		local title = isMedia and resolveRecordedMediaVanillaName(row, playerNum) or nil
		if isMedia then
			total = total + 1
			if title then exact = exact + 1 else unresolved = unresolved + 1 end
			local path = tostring(row.nativePath or "")
			if path:match("/with_learning$") then withLearning = withLearning + 1 end
			if path:match("/leisure$") then leisure = leisure + 1 end
			if #samples < 5 then
				samples[#samples + 1] = tostring(row.mediaIndex) .. "=" .. tostring(title or "<unresolved>")
			end
		end
		if title then row.displayName = title; row.mediaTitle = title end
		for j = 1, #(row.variantSummary or {}) do
			local summary = row.variantSummary[j]
			local variantTitle = resolveRecordedMediaVanillaName(summary, playerNum)
			if variantTitle then
				summary.displayName = variantTitle
				summary.mediaTitle = variantTitle
			end
		end
	end
	if total > 0 then
		local signature = table.concat({ total, exact, unresolved, withLearning, leisure,
			table.concat(samples, "|") }, ":")
		if signature ~= LAST_MEDIA_DIAGNOSTIC_SIGNATURE then
			LAST_MEDIA_DIAGNOSTIC_SIGNATURE = signature
			GlobalStorageSiK.Log.debug("RecordedMediaRuntime", "projection",
				"rows=" .. tostring(total) .. " exact=" .. tostring(exact)
				.. " unresolved=" .. tostring(unresolved)
				.. " learning=" .. tostring(withLearning)
				.. " leisure=" .. tostring(leisure)
				.. " samples=" .. table.concat(samples, ";"))
		end
	end
end

--- Proyeccion visible unica de una fila. RecordedMedia conserva la identidad
--- de su edicion; el resto sigue usando exactamente el resolvedor i18n comun.
---@param row table|nil
---@return string
local function displayNameForRow(row)
	if not row then return "" end
	if tonumber(row.mediaIndex)
		and type(row.mediaTitle) == "string" and row.mediaTitle ~= "" then
		return row.mediaTitle
	end
	return GlobalStorageSiK.I18n.itemDisplayName(row.fullType, row.displayName, row.worldSprite)
end

GlobalStorageSiK.TerminalItems.prepareRecordedMediaRows = localizeRecordedMediaRows
GlobalStorageSiK.TerminalItems.displayNameForRow = displayNameForRow

local function foodIconVariantForRow(row)
	local variant = row.foodState and row.foodState.iconVariant or row.foodIconVariant
	if variant == "base" or variant == "cooked" or variant == "rotten" or variant == "burnt" then
		return variant
	end
	return nil
end

-- This ephemeral probe is for getTex only, not a hydrated tooltip instance.
-- Set every participating field so script defaults cannot override the selector.
local function applyFoodIconVariant(probe, variant)
	if not variant then return true end
	local ok = pcall(function()
		if not instanceof or not instanceof(probe, "Food") then error("not a Food probe") end
		probe:setBurnt(variant == "burnt")
		probe:setCooked(variant == "cooked")
		local threshold = probe:getOffAgeMax()
		if type(threshold) ~= "number" or threshold ~= threshold
			or math.abs(threshold) == math.huge then error("invalid food icon threshold") end
		probe:setAge(variant == "rotten" and threshold or math.min(0, threshold - 1))
	end)
	return ok
end

--- Textura de inventario resuelta como vanilla (`InventoryItem:getTex()`).
--- El resultado se cachea porque la lista virtual puede redibujar la misma
--- fila muchas veces. ScriptItem y sprite del mundo son solo fallbacks.
---@param row table|nil
---@return Texture|nil
local function itemTexture(row)
	if not row or not row.fullType then
		return nil
	end
	local variant = foodIconVariantForRow(row)
	local cacheKey = tostring(row.fullType) .. "\31" .. tostring(row.worldSprite or "")
		.. "\31" .. tostring(variant or "")
	local cached = ITEM_TEXTURE_CACHE[cacheKey]
	if cached ~= nil then
		return cached or nil
	end

	local probe = itemProbe(row)
	if probe and probe.getTex and applyFoodIconVariant(probe, variant) then
		local ok, tex = pcall(function() return probe:getTex() end)
		if ok and tex then
			ITEM_TEXTURE_CACHE[cacheKey] = tex
			return tex
		end
	end

	local script = scriptItem(row.fullType)
	if script and script.getNormalTexture then
		local ok, tex = pcall(function() return script:getNormalTexture() end)
		if ok and tex then
			ITEM_TEXTURE_CACHE[cacheKey] = tex
			return tex
		end
	end
	if row.worldSprite and getSprite then
		local ok, tex = pcall(function()
			local sprite = getSprite(row.worldSprite)
			return sprite and sprite.getTexture and sprite:getTexture() or nil
		end)
		if ok and tex then
			ITEM_TEXTURE_CACHE[cacheKey] = tex
			return tex
		end
	end
	ITEM_TEXTURE_CACHE[cacheKey] = false
	return nil
end

--- Version PUBLICA de itemTexture, para cualquier otro fichero que necesite
--- el icono real de una fila del Almacen (fullType + worldSprite) - unica
--- ruta "robusta" del mod: reconstruye el item real desde el worldSprite via
--- ISMoveableSpriteProps antes de caer a ScriptItem/sprite crudo, para que
--- items derivados de un Moveable (p.ej. una caja recogida) muestren su
--- icono de inventario real, no un "?" (bug real cerrado 2026-08-23: el
--- "fantasma" de arrastre de GS_TerminalWithdrawDrag.lua mantenia su PROPIA
--- cadena de fallback, mas corta, que nunca llegaba a ISMoveableSpriteProps -
--- unificado aqui, la unica fuente, en vez de mantener dos caminos que
--- pueden divergir).
---@param row table|nil
---@return Texture|nil
GlobalStorageSiK.TerminalItems.textureForRow = itemTexture

-- Cache de respaldo cliente (ver clientLearnedRecipeNames abajo): solo se
-- escribe en exito, nunca en fallo, para no envenenar la entrada como paso
-- el bug ya corregido de -dev17.
local CLIENT_LEARNED_RECIPES_CACHE = {}

-- Cache de respaldo cliente para NumberOfPages (ver numberOfPagesFromItem en
-- GS_ItemSnapshot.lua para la explicacion completa de por que este dato NO
-- esta en el script de una revista de receta, solo en la instancia real).
local CLIENT_NUMBER_OF_PAGES_CACHE = {}

--- Respaldo INSTANTANEO en cliente del numero real de paginas de una revista
--- de receta (row.numberOfPages, capturado por el servidor, puede tardar
--- hasta el proximo reescaneo de zona en llegar). instanceItem() SI dispara
--- OnCreate (ItemCodeOnCreate.onCreateRecipeMagazine es un hook de
--- construccion del motor, no un evento scripted que dependa de estar en el
--- mundo), asi que da el mismo NumberOfPages real que tendria cualquier
--- instancia del mismo fullType.
---@param fullType string
---@return integer|nil
local function clientNumberOfPages(fullType)
	local cached = CLIENT_NUMBER_OF_PAGES_CACHE[fullType]
	if cached ~= nil then return cached or nil end
	-- BUG REAL cerrado (2026-08-23, misma clase exacta que itemProbe en este
	-- mismo fichero - ver comentario mas abajo, "2026-08-22"): esta funcion
	-- SOLO cacheaba el EXITO. Para un fullType que nunca resuelve (item
	-- corrupto/movable mal escaneado), instanceItem(fullType) - funcion
	-- vanilla que imprime su propio log incondicional si el fullType no
	-- existe - se repetia SIN CACHE en cada llamada. isLiteratureReadSafe
	-- (mas abajo) llama a esta funcion desde el render() de CADA fila del
	-- Almacen, en CADA fotograma - con una fila rota simplemente VISIBLE en
	-- la lista (sin necesidad de pasar el raton ni arrastrarla), el fallo se
	-- repetia 30-60 veces/segundo de forma continua. Cachear tambien el
	-- fallo (como `false`) para que la consulta ocurra como mucho una vez
	-- por fullType distinto.
	if not instanceItem then
		CLIENT_NUMBER_OF_PAGES_CACHE[fullType] = false
		return nil
	end
	local ok, probe = pcall(instanceItem, fullType)
	if not ok or not probe or not probe.getNumberOfPages then
		CLIENT_NUMBER_OF_PAGES_CACHE[fullType] = false
		return nil
	end
	local okPages, pages = pcall(function() return probe:getNumberOfPages() end)
	if not okPages or not pages or pages <= 0 then
		CLIENT_NUMBER_OF_PAGES_CACHE[fullType] = false
		return nil
	end
	CLIENT_NUMBER_OF_PAGES_CACHE[fullType] = pages
	return pages
end

--- Respaldo INSTANTANEO en cliente cuando la fila todavia no trae
--- learnedRecipeNames del servidor (nodo sin reescanear desde -dev19).
--- Pedido explicito (2026-08-21): "da igual la recarga, si lo acabo de leer
--- debe marchar el check YA" - el vanilla de verdad es instantaneo, asi que
--- nuestro respaldo tambien debe serlo.
---
--- BUG REAL corregido (2026-08-21, log real: "ok=true known=false" siempre,
--- para 3 revistas confirmadas leidas por el propio tick de vanilla): la
--- sonda SI funcionaba, el fallo estaba en convertir la lista a texto Lua
--- (tostring) y comparar luego contra getKnownRecipes(). Vanilla NUNCA hace
--- esa conversion (ISInventoryPane.lua:2597, ISLiteratureUI.lua:391) -
--- siempre pasa la lista/valor Java ORIGINAL, sin tocar, a containsAll()/
--- contains(). Aqui SI tenemos ese valor original (probe:getLearnedRecipes()
--- es la lista Java real) - se cachea y se compara TAL CUAL, igual que
--- vanilla, sin convertir a string en ningun punto.
---@param fullType string
---@return any|nil recipes lista Java original, o nil si no aplica
local function clientLearnedRecipesRaw(fullType)
	local cached = CLIENT_LEARNED_RECIPES_CACHE[fullType]
	if cached ~= nil then return cached or nil end
	local debugOn = GlobalStorageSiK.Sandbox.debugMode() and GlobalStorageSiK.Sandbox.debugCategoryEnabled("LiteratureRead")
	-- BUG REAL cerrado (2026-08-23, misma clase exacta que clientNumberOfPages
	-- arriba y que itemProbe mas abajo): SOLO se cacheaba el EXITO. Para un
	-- fullType que nunca resuelve, instanceItem() se repetia sin cache en
	-- cada llamada de isLiteratureReadSafe - una vez por fotograma por cada
	-- fila visible del Almacen, sin necesitar interaccion del jugador.
	if not instanceItem then
		if debugOn then
			GlobalStorageSiK.Log.debug("LiteratureRead", "clientLearnedRecipesRaw",
				"fullType=" .. tostring(fullType) .. " SIN instanceItem global en este cliente")
		end
		CLIENT_LEARNED_RECIPES_CACHE[fullType] = false
		return nil
	end
	local ok, probe = pcall(instanceItem, fullType)
	if not ok or not probe or not probe.getLearnedRecipes then
		if debugOn then
			GlobalStorageSiK.Log.debug("LiteratureRead", "clientLearnedRecipesRaw",
				"fullType=" .. tostring(fullType) .. " instanceItem FALLO ok=" .. tostring(ok)
					.. " probe=" .. tostring(probe ~= nil) .. " err=" .. tostring(not ok and probe or nil))
		end
		CLIENT_LEARNED_RECIPES_CACHE[fullType] = false
		return nil
	end
	local okRecipes, recipes = pcall(function() return probe:getLearnedRecipes() end)
	local size = okRecipes and recipes and recipes.size and recipes:size() or -1
	if debugOn then
		GlobalStorageSiK.Log.debug("LiteratureRead", "clientLearnedRecipesRaw",
			"fullType=" .. tostring(fullType) .. " instanceItem OK getLearnedRecipesOk=" .. tostring(okRecipes)
				.. " size=" .. tostring(size))
	end
	if not okRecipes or not recipes or size <= 0 then
		CLIENT_LEARNED_RECIPES_CACHE[fullType] = false
		return nil
	end
	CLIENT_LEARNED_RECIPES_CACHE[fullType] = recipes
	return recipes
end

-- Tick de "ya leído" en el Almacen (pedido explicito 2026-08-21): ahora que
-- se puede leer directamente desde la red (GS_NetworkReadAction.lua), saber
-- de un vistazo cual ya se leyo evita reservarlo/pedirlo prestado sin falta.
-- Replica ISInventoryPane:isLiteratureRead (vanilla, ISUI/ISInventoryPane.lua)
-- - nuestras propias revistas (GS_Manual_*) son literatura vanilla real
-- (ItemType=base:literature, LearnedRecipes en su script), deben funcionar
-- exactamente igual que cualquier revista del juego, no con un mecanismo aparte.
---@param player IsoPlayer|nil
---@param row table|nil fila del Almacén (fullType + learnedRecipeNames del snapshot)
---@return boolean
local function isLiteratureReadSafe(player, row)
	local fullType = row and row.fullType
	if not player or not fullType then return false end
	local debugOn0 = GlobalStorageSiK.Sandbox.debugMode() and GlobalStorageSiK.Sandbox.debugCategoryEnabled("LiteratureRead")

	-- Camino REAL de vanilla (ISInventoryPane.lua:2585-2599, leido del .lua
	-- real del juego instalado, no supuesto): el PRIMER chequeo, antes que
	-- cualquier receta o pagina, es item:getModData().literatureTitle contra
	-- playerObj:isLiteratureRead(literatureTitle). Es el mecanismo que usa
	-- tambien ContextMenu_RecentlyRead (ISInventoryPaneContextMenu.lua:1079).
	-- Las recetas/paginas de mas abajo son solo los FALLBACKS que vanilla
	-- prueba despues si esto no aplica - no el camino principal como se
	-- asumio en rondas anteriores.
	if row.literatureTitle and player.isLiteratureRead then
		local ok, read = pcall(function() return player:isLiteratureRead(row.literatureTitle) end)
		if debugOn0 then
			GlobalStorageSiK.Log.debug("LiteratureRead", "isLiteratureReadSafe (literatureTitle)",
				"fullType=" .. tostring(fullType) .. " literatureTitle=" .. tostring(row.literatureTitle)
					.. " ok=" .. tostring(ok) .. " read=" .. tostring(read))
		end
		if ok and read == true then return true end
	elseif debugOn0 then
		GlobalStorageSiK.Log.debug("LiteratureRead", "isLiteratureReadSafe (literatureTitle)",
			"fullType=" .. tostring(fullType) .. " SIN literatureTitle en la fila (nodo sin reescanear tras leer)")
	end

	local si = scriptItem(fullType)
	if si then
		local ok1, isBook = pcall(function()
			if si.getSkillTrained then
				local skill = si:getSkillTrained()
				local skillBook = skill and SkillBook and SkillBook[skill]
				if skillBook and si.getMaxLevelTrained and player.getPerkLevel
					and si:getMaxLevelTrained() < player:getPerkLevel(skillBook.perk) + 1 then
					return true
				end
			end
			if si.getNumberOfPages and si:getNumberOfPages() > 0 and player.getAlreadyReadPages then
				if player:getAlreadyReadPages(fullType) == si:getNumberOfPages() then return true end
			end
			return false
		end)
		if ok1 and isBook == true then return true end
	end
	local debugOn = GlobalStorageSiK.Sandbox.debugMode() and GlobalStorageSiK.Sandbox.debugCategoryEnabled("LiteratureRead")

	-- Revistas de receta (Base.HuntingMag*, GS_Manual_*, etc.): mismo
	-- mecanismo de "paginas ya leidas" que el chequeo de libro de arriba, NO
	-- las recetas - la diferencia real encontrada 2026-08-21: su
	-- NumberOfPages lo asigna el motor en tiempo de ejecucion via OnCreate
	-- (ItemCodeOnCreate.onCreateRecipeMagazine), no esta en el script como en
	-- un libro de habilidad, asi que scriptItem():getNumberOfPages() daba
	-- siempre 0 y el chequeo de arriba nunca se disparaba para ellas. row.
	-- numberOfPages es el valor real, capturado por el servidor desde una
	-- instancia viva (GS_ItemSnapshot.lua); clientNumberOfPages() es el
	-- respaldo instantaneo via instanceItem() (que SI dispara OnCreate) para
	-- cuando el nodo todavia no trajo ese dato del servidor.
	if player.getAlreadyReadPages then
		local pages = row.numberOfPages or clientNumberOfPages(fullType)
		if pages and pages > 0 then
			local ok, alreadyRead = pcall(function() return player:getAlreadyReadPages(fullType) end)
			if debugOn then
				GlobalStorageSiK.Log.debug("LiteratureRead", "isLiteratureReadSafe (paginas revista)",
					"fullType=" .. tostring(fullType) .. " pages=" .. tostring(pages)
						.. " fromRow=" .. tostring(row.numberOfPages ~= nil)
						.. " ok=" .. tostring(ok) .. " alreadyRead=" .. tostring(alreadyRead))
			end
			if ok and alreadyRead == pages then return true end
		end
	end

	-- "Camino 0" (comparar scriptItem(fullType):getLearnedRecipes() contra
	-- player:getKnownRecipes() via containsAll()/contains(), SIN convertir a
	-- string) ELIMINADO (2026-08-21) - causa raiz real, encontrada leyendo el
	-- .lua real de vanilla instalado: ISInventoryPane.lua:2597 e
	-- ISLiteratureUI.lua:373-374/391 NUNCA llaman getLearnedRecipes() sobre un
	-- scriptItem (plantilla de definicion), SIEMPRE sobre la INSTANCIA REAL
	-- del item mostrado/leido. Un scriptItem() es una plantilla distinta -
	-- comparar sus objetos Receta en bruto contra getKnownRecipes() (misma
	-- familia de bug que el intento anterior con instanceItem(), tambien
	-- descartado) daba "ok=true known=false" SIEMPRE pese a nombres
	-- correctos, confirmado con log real en produccion (build -dev27:
	-- perRecipe=[Program GS Floppy Drive Network Disk=false] pese a que esa
	-- receta la enseña justo ese manual). La comparacion en bruto (sin
	-- tostring) solo es fiable cuando el objeto Receta viene de la instancia
	-- real igual que hace vanilla - los caminos A/B de abajo ya cubren esto,
	-- comparando por NOMBRE (tostring) en vez de por identidad de objeto,
	-- que es robusto sea cual sea el origen del objeto Receta.

	-- Camino A (preferido cuando existe): recetas capturadas por el SERVIDOR
	-- desde un item REAL durante el escaneo (GS_ItemSnapshot.lua), pero
	-- viajaron por red como texto Lua (un valor Java vivo no se puede
	-- serializar) - se comparan normalizando AMBOS lados con tostring().
	-- El camino B de abajo usa el mismo patron por nombre, sobre una fuente
	-- distinta (sonda cliente en vez de captura de servidor).
	if row.learnedRecipeNames and #row.learnedRecipeNames > 0 and player.getKnownRecipes then
		local recipes = row.learnedRecipeNames
		local ok, known = pcall(function()
			local knownSet = {}
			local knownRecipes = player:getKnownRecipes()
			for i = 0, knownRecipes:size() - 1 do
				knownSet[tostring(knownRecipes:get(i))] = true
			end
			for i = 1, #recipes do
				if not knownSet[tostring(recipes[i])] then
					return false
				end
			end
			return true
		end)
		if debugOn then
			GlobalStorageSiK.Log.debug("LiteratureRead", "isLiteratureReadSafe (red)",
				"fullType=" .. tostring(fullType) .. " recipes=" .. table.concat(recipes, ",")
					.. " ok=" .. tostring(ok) .. " known=" .. tostring(known))
		end
		if ok and known == true then return true end
	end

	-- Camino B: respaldo instantaneo en cliente cuando la fila todavia no
	-- trae el dato del servidor (nodo sin reescanear desde -dev19). Fuente:
	-- instanceItem(fullType) - una sonda SINTETICA, no la instancia real que
	-- el jugador tiene/lee. Por eso NO se compara en bruto con containsAll()/
	-- contains() (bug real encontrado 2026-08-21, misma familia que el
	-- "Camino 0" ya eliminado mas arriba: un objeto Receta obtenido de una
	-- fuente que no es la instancia real del item mostrado/leido no es
	-- reconocido como igual por Java aunque su nombre imprima identico) -
	-- se compara por NOMBRE (tostring), igual que el Camino A, que es
	-- robusto sea cual sea el origen del objeto Receta.
	local rawRecipes = clientLearnedRecipesRaw(fullType)
	if rawRecipes and player.getKnownRecipes then
		local ok, known = pcall(function()
			local knownSet = {}
			local knownRecipes = player:getKnownRecipes()
			for i = 0, knownRecipes:size() - 1 do
				knownSet[tostring(knownRecipes:get(i))] = true
			end
			for i = 0, rawRecipes:size() - 1 do
				if not knownSet[tostring(rawRecipes:get(i))] then
					return false
				end
			end
			return true
		end)
		if debugOn then
			GlobalStorageSiK.Log.debug("LiteratureRead", "isLiteratureReadSafe (cliente, por nombre)",
				"fullType=" .. tostring(fullType) .. " ok=" .. tostring(ok) .. " known=" .. tostring(known))
		end
		if ok and known == true then return true end
	end
	return false
end

--- Nombre de zona del nodo indicado, ya sincronizado en terminalState.nodes
--- (cada nodo ya trae zoneName, ver GS_Server.lua:serializeNodes) - sin
--- llamada de red aparte.
---@param nodes table[]
---@param nodeId string
---@return string|nil
local function findNodeZoneName(nodes, nodeId)
	for i = 1, #nodes do
		if nodes[i].id == nodeId then
			-- "or nil" en vez de devolver zoneName tal cual: una cadena
			-- vacia es VERDADERA en Lua (solo nil/false son falsy), asi que
			-- un "zoneName or T(...)" en el llamante NUNCA caeria al
			-- fallback "Global" si zoneName llegara como "" en vez de nil -
			-- se quedaria en blanco de verdad, sin mostrar nada.
			local zn = nodes[i].zoneName
			if zn == "" then return nil end
			return zn
		end
	end
	return nil
end

--- Columna "Zona" (dev26 ronda 4quinquies, pedido explicito del usuario):
--- nombre de la zona donde esta almacenado este tipo de item. Un fullType
--- agregado puede repartirse en VARIOS contenedores (ver data.locations,
--- GS_Index.lua) - si todos caen en la misma zona se muestra su nombre, si
--- no se muestra un aviso generico en vez de elegir una zona al azar.
---@param terminal GS_TerminalUI|nil
---@param data table|nil
---@return string
-- BUG REAL DE RENDIMIENTO cerrado (2026-08-26, propuesta de mejora futura de
-- Desarrollo tras validar dev20 - "cachear resolveZoneLabel() por fila y
-- referencia de terminalState.nodes; la ordenacion por zona todavia puede
-- recorrer ubicaciones y nodos por cada fila"): memorizado por fila, con
-- INVALIDACION explicita contra la referencia de `nodes` usada - la lista de
-- nodos puede cambiar (renombrar zona, mover terminal) SIN que la fila del
-- item se reemplace (a diferencia de items/precio, que si generan filas
-- nuevas en cada sync) - cachear solo por fila sin comprobar `nodes` daria
-- una zona obsoleta tras ese tipo de cambio.
local zoneLabelCache = setmetatable({}, { __mode = "k" })
local function resolveZoneLabel(terminal, data)
	local locations = data and data.locations
	if not terminal or not locations or #locations == 0 then
		return T("IGUI_GS_PunctuationEmDash")
	end
	local nodes = terminal.terminalState and terminal.terminalState.nodes or {}
	local cached = zoneLabelCache[data]
	if cached and cached.nodes == nodes then
		return cached.label
	end
	local zoneName, multiple = nil, false
	for i = 1, #locations do
		local zn = findNodeZoneName(nodes, locations[i].nodeId) or T("IGUI_GS_ProtocolGlobal")
		if zoneName == nil then
			zoneName = zn
		elseif zoneName ~= zn then
			multiple = true
		end
	end
	local label = multiple and T("IGUI_GS_ColZoneMultiple") or (zoneName or T("IGUI_GS_PunctuationEmDash"))
	zoneLabelCache[data] = { nodes = nodes, label = label }
	return label
end

--- Ordena filas según clave y dirección.
---@param rows table[]
---@param sortKey string
---@param ascending boolean
---@return table[]
-- BUG REAL DE RENDIMIENTO cerrado (2026-08-26, propuesta de mejora futura de
-- Desarrollo tras validar dev20 - "mantener claves de ordenacion estables por
-- fila para displayName/category; sus resoluciones profundas ya estan
-- cacheadas (dev20), pero la propia tabla de claves se reconstruye en cada
-- ordenacion"): "displayName"/"category" son puras por fila (dependen solo
-- de row.fullType/row.displayName/row.worldSprite/row.category/
-- row.subCategory, que nunca cambian sin que el servidor entregue una fila
-- NUEVA - ver comentario de itemSearchHaystackCache en GS_I18n.lua sobre esta
-- misma invariante) - memorizadas de forma persistente por fila+clave, no
-- solo dentro de una llamada a sortRows. "zone" NO se memoriza aqui (tiene su
-- propia cache con invalidacion por referencia de nodos, ver
-- resolveZoneLabel) y "count" es ya trivial (lectura directa de campo, cachearla
-- no aportaria nada).
-- BUG REAL DE RENDIMIENTO #2 cerrado (2026-08-27, informe de telemetria de
-- Simucad tras dev19: mismo hallazgo que itemSearchHaystackCache en
-- GS_I18n.lua - "el snapshot del servidor entrega tablas de fila nuevas
-- aproximadamente cada dos segundos", la clave por REFERENCIA de `row`
-- (`__mode="k"`) pierde efectividad entre snapshots aunque el tipo/nombre/
-- categoria de la fila no haya cambiado. Cambiada a clave por COMPUESTO de
-- los campos intrinsecos de los que depende (fullType/worldSprite/
-- displayName/category/subCategory/gsSubKeysStr) + sortKey - mismo patron
-- ya usado por itemSearchHaystackCache/itemTaxonomyResolveCache. `count` y
-- `zone` siguen fuera de esta cache (ya lo estaban: count es lectura
-- directa, zone tiene su propia invalidacion por referencia de nodos).
local sortKeyValueCache = GlobalStorageSiK.CatalogManager
	and GlobalStorageSiK.CatalogManager.createEpochCache() or {}
if GlobalStorageSiK.CatalogManager and GlobalStorageSiK.CatalogManager.registerFullTypeCache then
	GlobalStorageSiK.CatalogManager.registerFullTypeCache("terminal-item-sort", sortKeyValueCache, 1)
end
local function sortRowCacheKey(row)
	return tostring(row.fullType or "") .. "\1" .. tostring(row.worldSprite or "")
		.. "\1" .. tostring(row.displayName or "") .. "\1" .. tostring(row.category or "")
		.. "\1" .. tostring(row.subCategory or "") .. "\1" .. tostring(row.gsSubKeysStr or "")
		.. "\1" .. tostring(row.nativePath or "")
end
local function sortKeyValue(row, sortKey, terminal)
	if sortKey == "count" then
		return row.count or 0
	end
	if sortKey == "zone" then
		return string.lower(resolveZoneLabel(terminal, row))
	end
	local cacheKey = sortRowCacheKey(row) .. "\1" .. sortKey
	local cached = sortKeyValueCache[cacheKey]
	if cached ~= nil then
		return cached
	end
	local value
	if sortKey == "category" then
		value = string.lower(GlobalStorageSiK.CategoryResolution.label(
			GlobalStorageSiK.CategoryResolution.resolve(row.fullType, row, nil)) or "")
	else
		local name = displayNameForRow(row)
		value = string.lower(tostring(name or row.fullType or ""))
	end
	sortKeyValueCache[cacheKey] = value
	return value
end

--- Ordena filas según clave y dirección.
---@param rows table[]
---@param sortKey string
---@param ascending boolean
---@param terminal GS_TerminalUI|nil solo lo necesita sortKey=="zone"
---@return table[]
local function sortRows(rows, sortKey, ascending, terminal)
	local sorted = {}
	local values = {}
	for i = 1, #rows do
		sorted[i] = rows[i]
		-- DEV30: fuerza cualquier traduccion/resolucion en una pasada lineal.
		-- El comparador de table.sort queda reducido a lecturas de tabla: cero
		-- clasificador, i18n o ScriptManager durante sus O(n log n) llamadas.
		values[rows[i]] = sortKeyValue(rows[i], sortKey, terminal)
	end
	-- BUG REAL DE RENDIMIENTO cerrado (2026-08-26, reportado por un miembro de
	-- la comunidad con telemetria real de servidor dedicado: red de 1286
	-- tipos/188 nodos, refreshItemsTab en 1157ms, 1069ms solo del sort -
	-- "displayName", la clave POR DEFECTO, resolvia I18n.itemDisplayName() DOS
	-- VECES POR COMPARACION, ~26000 llamadas para 1286 filas). Cerrado en 2
	-- pasos: primero (dev18) un cache local de UNA pasada por sortRows;
	-- despues (dev20/dev21), sortKeyValue() paso a memorizar sus resultados de
	-- forma persistente por fila. DEV30 conserva esa cache y recupera ademas
	-- la tabla intermedia por ordenacion: incluso el primer sort queda libre
	-- de traducciones o resoluciones dentro del comparador.
	table.sort(sorted, function(a, b)
		local av = values[a]
		local bv = values[b]
		if av == bv then
			return (a.fullType or "") < (b.fullType or "")
		end
		if ascending then
			return av < bv
		end
		return av > bv
	end)
	return sorted
end

local function buildDisplayRows(panel, terminal, parents)
	panel._expandedKeys = panel._expandedKeys or {}
	panel._detailPageByKey = panel._detailPageByKey or {}
	panel._detailPending = panel._detailPending or {}
	local liveParents = {}
	local out = {}
	local revision = terminal and terminal.terminalState and terminal.terminalState.inventoryRevision or 0
	local networkId = terminal and terminal.terminalState and terminal.terminalState.networkId or nil
	for i = 1, #parents do
		local parent = parents[i]
		local key = rowIdentity(parent)
		liveParents[key] = true
		-- Every aggregate is a hierarchy root, including aggregates with one
		-- physical item.  Keep the disclosure affordance and lazy detail path
		-- identical instead of changing the row contract with the item count.
		parent.expandable = true
		parent._gsRowKind = "parent"
		parent._gsDepth = 0
		out[#out + 1] = parent
		if parent.expandable and panel._expandedKeys[key] then
			local wantedPage = panel._detailPageByKey[key] or 1
			local pages = panel._detailPages or detailPagesByRowKey()
			local detailPage = pages and pages[key] or nil
			local stale = not detailPage or detailPage.page ~= wantedPage
				or detailPage.networkId ~= networkId
				or tonumber(detailPage.inventoryRevision or -1) ~= tonumber(revision)
			if stale and not panel._detailPending[key] then
				panel._detailPending[key] = true
				GlobalStorageSiK.TerminalItems.requestDetails(terminal, parent, wantedPage)
			end
			local displayable = detailPage and detailPage.page == wantedPage
				and detailPage.networkId == networkId
				and tonumber(detailPage.inventoryRevision or -1) == tonumber(revision)
			if displayable then
				panel._detailRendered = panel._detailRendered or {}
				local renderedKey = tostring(key) .. "\31" .. tostring(wantedPage) .. "\31" .. tostring(revision)
				if panel._detailRendered[renderedKey] ~= true
					and GlobalStorageSiK.UIDebug and GlobalStorageSiK.UIDebug.log then
					panel._detailRendered[renderedKey] = true
					GlobalStorageSiK.UIDebug.log("TerminalItems", "detailsRendered %s", tostring(key))
				end
				local pageStale = tonumber(detailPage.inventoryRevision or -1) ~= tonumber(revision)
				for j = 1, #(detailPage.items or {}) do
					local child = detailPage.items[j]
					-- Las unidades llegan bajo demanda: no pasan por la localización
					-- inicial de padres. Resolver aquí hace que el título de VHS que
					-- ya conoce la instancia se pinte también en la fila hija.
					local mediaTitle = resolveRecordedMediaVanillaName(child,
						terminal and terminal.playerNum or 0)
					if mediaTitle then
						child.mediaTitle = mediaTitle
						child.displayName = mediaTitle
					end
					child._gsRowKind = "child"
					child._gsDepth = 1
					child.parentRowKey = key
					child._gsStale = pageStale
					child.locations = child.locations or (child.nodeId and { { nodeId = child.nodeId, count = child.count or 1 } } or nil)
					out[#out + 1] = child
				end
			end
		end
	end
	local expandedKeys = {}
	for key in pairs(panel._expandedKeys) do
		if liveParents[key] then expandedKeys[key] = true end
	end
	panel._expandedKeys = expandedKeys
	return out
end

--- Taxonomía vanilla resuelta de una fila.
---@param row table|nil
---@return table
function GlobalStorageSiK.TerminalItems.rowTaxonomy(row)
	if not row then
		return { mainKey = "", subKey = "", mainLabel = "", subLabel = "", fullLabel = "",
			groupKey = "", subGroupKey = nil, groupLabel = "", subGroupLabel = nil, leafLabel = nil }
	end
	local resolution = GlobalStorageSiK.CategoryResolution.resolve(row.fullType, row, nil)
	if resolution.effective == "variants" then
		local label = GlobalStorageSiK.CategoryResolution.label(resolution)
		return { mainKey = "variants", subKey = nil, mainLabel = label,
			fullLabel = label, groupKey = "variants", groupLabel = label,
			nativePaths = resolution.nativePaths }
	end
	local path = resolution.effective == "native" and resolution.nativePath or nil
	if path then
		local view = GlobalStorageSiK.NativeProduct.getView(path)
		return {
			mainKey = view.key, subKey = view.key, mainLabel = view.l1Label,
			subLabel = view.l2Label, fullLabel = view.fullLabel,
			groupKey = path.l1, subGroupKey = path.l2, categoryLeafKey = path.l3,
			groupLabel = view.l1Label, subGroupLabel = view.l2Label, leafLabel = view.l3Label,
			nativePath = path,
		}
	end
	return { mainKey = resolution.vanillaKey, subKey = nil,
		mainLabel = GlobalStorageSiK.CategoryResolution.label(resolution),
		fullLabel = GlobalStorageSiK.CategoryResolution.label(resolution),
		groupKey = resolution.vanillaKey, groupLabel = GlobalStorageSiK.CategoryResolution.label(resolution) }
end

-- El mismo snapshot de filas alimenta L1/L2/L3 durante un refresh. Mantener
-- un unico indice inverso por referencia evita volver a recorrer el stock
-- para cada opcion de cada nivel.
local nativeIndexRows = nil
local nativeIndex = nil
local nativeIndexEpoch = nil
local function indexForRows(rows)
	local epoch = GlobalStorageSiK.CatalogManager.getEpoch()
	if rows ~= nativeIndexRows or epoch ~= nativeIndexEpoch then
		nativeIndexRows = rows
		nativeIndexEpoch = epoch
		nativeIndex = GlobalStorageSiK.NativeProduct.buildIndex(rows)
	end
	return nativeIndex
end

local function nativeOptionsPresent(rows, parent)
	local options = GlobalStorageSiK.NativeProduct.listOptions(parent)
	local result = {}
	local index = indexForRows(rows)
	for o = 1, #options do
		local count = #GlobalStorageSiK.NativeProduct.rowsForPath(index, options[o].key)
		if count > 0 then
			result[#result + 1] = { key = options[o].key, label = options[o].label, typeCount = count }
		end
	end
	return result
end

local function appendUniqueOptions(target, seen, options)
	for i = 1, #options do
		local sig = string.lower(tostring(options[i].key or ""))
		if sig ~= "" and not seen[sig] then
			seen[sig] = true
			target[#target + 1] = options[i]
		end
	end
end

local function filterByNativePath(rows, key)
	if not key or key == "" then return rows end
	if not GlobalStorageSiK.NativeProduct.decodePath(key) then return nil end
	local filtered = {}
	for i = 1, #rows do
		local matches = GlobalStorageSiK.NativeProduct.pathMatches(key, rows[i].nativePath)
		for p = 1, #(rows[i].nativePaths or {}) do
			if GlobalStorageSiK.NativeProduct.pathMatches(key, rows[i].nativePaths[p]) then matches = true break end
		end
		if matches then
			filtered[#filtered + 1] = rows[i]
		end
	end
	return filtered
end

--- Recopila categorías principales únicas del catálogo.
---@param rows table[]
---@return table[] { key: string, label: string, typeCount: number }
function GlobalStorageSiK.TerminalItems.collectMainCategoryFilters(rows)
	rows = rows or {}
	local result, seen = {}, {}
	appendUniqueOptions(result, seen, nativeOptionsPresent(rows, nil))
	table.sort(result, function(a, b) return string.lower(a.label) < string.lower(b.label) end)
	return result
end

--- Recopila subcategorías únicas (opcionalmente restringidas a una categoría principal).
---@param rows table[]
---@param mainKey string|nil
---@return table[] { key: string, label: string, typeCount: number }
function GlobalStorageSiK.TerminalItems.collectSubCategoryFilters(rows, mainKey)
	if not mainKey or mainKey == "" then return {} end
	return GlobalStorageSiK.NativeProduct.decodePath(mainKey)
		and nativeOptionsPresent(rows or {}, mainKey) or {}
end

--- Filtra filas por categoría principal (vacío = todas).
---@param rows table[]
---@param mainKey string|nil
---@return table[]
function GlobalStorageSiK.TerminalItems.filterByMainCategory(rows, mainKey)
	if not mainKey or mainKey == "" then
		return rows
	end
	local native = filterByNativePath(rows, mainKey)
	if native then return native end
	return rows
end

--- Recopila sub-subcategorías (Nivel 3) únicas, restringidas a Nivel 1 (y
--- Nivel 2, si se eligió).
---@param rows table[]
---@param mainKey string|nil
---@param subKey string|nil
---@return table[] { key: string, label: string, typeCount: number }
function GlobalStorageSiK.TerminalItems.collectLeafCategoryFilters(rows, mainKey, subKey)
	if not subKey or subKey == "" then return {} end
	return GlobalStorageSiK.NativeProduct.decodePath(subKey)
		and nativeOptionsPresent(rows or {}, subKey) or {}
end

--- Filtra filas por Nivel 2 (subcategoría, ej. "Perecedero" - vacío = todas).
--- Acepta CUALQUIER hoja de Nivel 3 dentro de ese subgrupo (fruta, queso,
--- carne perecederos...), no solo coincidencia exacta - misma fuente unica
--- (tax.groupKey/subGroupKey) que usa GS_Router.lua al depositar.
---@param rows table[]
---@param subKey string|nil clave con prefijo SUBGROUP_PREFIX
---@return table[]
function GlobalStorageSiK.TerminalItems.filterBySubCategory(rows, subKey)
	if not subKey or subKey == "" then
		return rows
	end
	local native = filterByNativePath(rows, subKey)
	return native or rows
end

--- Filtra filas por Nivel 3 (hoja final: tipo de comida, hueco de
--- joyeria/ropa, o tercer segmento con guion de un mod de categorias
--- extendidas - vacío = todas). Coincidencia EXACTA, es el nivel mas especifico.
---@param rows table[]
---@param leafKey string|nil
---@return table[]
function GlobalStorageSiK.TerminalItems.filterByLeafCategory(rows, leafKey)
	if not leafKey or leafKey == "" then
		return rows
	end
	local native = filterByNativePath(rows, leafKey)
	return native or rows
end

---@param panel ISPanel
---@param fullType string|nil
---@return boolean
local function isRowSelected(panel, key)
	if not panel or not key or not panel._selectedKeys then
		return false
	end
	return panel._selectedKeys[key] == true
end

---@param panel ISPanel
local function clearRowSelection(panel)
	if panel then
		panel._selectedKeys = {}
		panel._selectionAnchor = nil
	end
end

--- Menú contextual de fila de ítem de la red.
---@param terminal GS_TerminalUI
---@param data table
---@param amount number
---@param targetKey string|nil
local function withdrawFromRowData(terminal, data, amount, targetKey)
	if terminal and data then
		terminal:onWithdrawRow(data, amount, targetKey)
	end
end

--- Retira usando inventario activo o bajo el ratón.
---@param terminal GS_TerminalUI
---@param data table
---@param amount number
local function withdrawRowWithActiveTarget(terminal, data, amount)
	if not terminal or not data then
		return
	end
	terminal:onWithdrawRow(data, amount, nil)
end

--- Construye titulo + descripcion (multi-linea, separador <LINE>) con los
--- datos utiles de un item de la red: tipo, categoria, peso unitario y
--- cantidad en esta red. Sin informacion de debug (no fullType interno de
--- Java, no ModData, etc.), solo lo que le interesa al jugador.
---@param fullType string
---@param data table|nil fila con count/category/subCategory
---@return string title
---@return string[] lines
local function buildItemDetailLines(fullType, data)
	local name = GlobalStorageSiK.I18n.itemDisplayName(fullType, data and data.displayName)
	local weightText = "?"
	-- Igual que GlobalStorageSiK.NetworkCapacity.estimateSnapshotWeight: prueba
	-- getActualWeight() primero, getWeight() como respaldo (en 42.20 no todos
	-- los script items resuelven getWeight() de forma fiable).
	-- Cache de sesion compartido (GlobalStorageSiK.I18n.getScriptItem) en vez
	-- de sm:getItem() a pelo - mismo bug de spam ya cerrado en los demas
	-- sitios de este fichero.
	if GlobalStorageSiK.I18n and GlobalStorageSiK.I18n.getScriptItem then
		local ok, w = pcall(function()
			local script = GlobalStorageSiK.I18n.getScriptItem(fullType)
			if script and script.getActualWeight then
				return script:getActualWeight()
			end
			if script and script.getWeight then
				return script:getWeight()
			end
			return nil
		end)
		if ok and w then
			weightText = string.format("%.2f", w)
		end
	end
	local cat = GlobalStorageSiK.I18n.itemCategoryDisplay(fullType, data and data.category, data and data.subCategory, data and data.gsSubKeysStr)
	local count = data and data.count or 0
	local lines = {
		T("IGUI_GS_DetailType", fullType),
		T("IGUI_GS_DetailCategory", cat),
		T("IGUI_GS_DetailWeight", weightText),
		T("IGUI_GS_DetailCount", tostring(count)),
	}
	-- Desglose de OTRAS redes del jugador que tambien tengan este fullType
	-- (misma cache/fuente que el tooltip global vanilla, filtrada por
	-- Permissions.canAccess en el servidor: solo redes propias/con acceso,
	-- nunca de otros jugadores o facciones). La red activa ya se muestra
	-- arriba via "Cant." con el dato instantaneo del estado del terminal;
	-- aqui solo se añaden las DEMAS, para no duplicar la misma cifra.
	if GlobalStorageSiK.ItemNetworkTooltip and GlobalStorageSiK.ItemNetworkTooltip.getCachedCounts then
		local activeId = GlobalStorageSiK.Client and GlobalStorageSiK.Client.activeNetworkId
		local networks = GlobalStorageSiK.ItemNetworkTooltip.getCachedCounts(fullType)
		if networks then
			for i = 1, #networks do
				local n = networks[i]
				if n.id ~= activeId then
					lines[#lines + 1] = T("IGUI_GS_NetworkCountLine", n.name, tostring(n.count))
				end
			end
		end
	end
	return name, lines
end

--- Añade opción Examinar para ítems de la red (sin invocar menú vanilla).
---@param cm ISContextMenu
---@param player IsoPlayer|nil
---@param fullType string
local function addNetworkItemExamine(cm, player, fullType)
	if not cm or not fullType or not instanceItem then
		return
	end
	local probe = instanceItem(fullType)
	if not probe then
		return
	end
	local label = T("IGUI_GS_Examine")
	if getText then
		local ok, examine = pcall(getText, "ContextMenu_examine")
		if ok and examine and examine ~= "ContextMenu_examine" then
			label = examine
		else
			ok, examine = pcall(getText, "IGUI_invpanel_Inspect")
			if ok and examine and examine ~= "IGUI_invpanel_Inspect" then
				label = examine
			end
		end
	end
	cm:addOption(label, player, function(target)
		local p = target or player
		if not p then
			return
		end
		local sample = instanceItem(fullType)
		local text = sample and sample:getName() or fullType
		if sample and sample.getDescription then
			local desc = sample:getDescription()
			if desc and desc ~= "" then
				text = desc
			end
		end
		pcall(function()
			GlobalStorageSiK.UIFeedback.halo(p, text, 220, 220, 200, 450,
				{ channel = "item-details" })
		end)
	end)
end

--- Menú contextual de fila de ítem.
---@param listPanel ISPanel
---@param terminal GS_TerminalUI
---@param data table
local function openItemContextMenu(listPanel, terminal, data)
	if not terminal or not data then
		return
	end
	local playerNum = terminal.playerNum or 0
	local player = GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer(playerNum)
		or getSpecificPlayer(playerNum)
	if player and player.getPlayerNum then
		playerNum = player:getPlayerNum()
	end

	-- El menú debe superar la ventana que contiene realmente la tabla. En los
	-- editores el controlador es un adaptador y la terminal principal puede estar
	-- detrás; bajar esa terminal dejaba el menú bajo el editor always-on-top.
	local ui = terminal.contextMenuOwner or terminal._gsContextMenuOwner
		or (GlobalStorageSiK.TerminalUI and GlobalStorageSiK.TerminalUI.instance)
		or terminal
	GlobalStorageSiK.Log.debug("ExactWithdraw", "contextMenu.prepare owner="
		.. tostring(ui) .. " row=" .. tostring(data.rowKey or data.fullType))
	local menuState = GlobalStorageSiK.ContextMenuUi.prepareTerminal(ui)

	local ok, err = pcall(function()
		local cm = ISContextMenu.get(playerNum, getMouseX(), getMouseY())
		addNetworkItemExamine(cm, player, data.fullType)
		GlobalStorageSiK.NetworkReadAction.addToContext(cm, player, data, terminal)
		local providerRows = getSelectedRows(listPanel)
		if #providerRows == 0 then providerRows = { data } end
		if GlobalStorageSiK.ItemActions and GlobalStorageSiK.ItemActions.addProviderOptions then
			GlobalStorageSiK.ItemActions.addProviderOptions(cm, player, providerRows, {
				source = "warehouse",
				terminal = terminal,
				row = data,
			})
		end
		cm:addOption(T("IGUI_GS_ViewDetails"), player, function(target)
			local p = target or player
			if not p then return end
			local name, lines = buildItemDetailLines(data.fullType, data)
			pcall(function()
				GlobalStorageSiK.UIFeedback.halo(p,
					name .. " | " .. table.concat(lines, " | "),
					220, 220, 200, 600, { channel = "item-details" })
			end)
		end)

		-- BUG REAL reportado por el usuario (2026-08-26): "el menu contextual
		-- del almacen es muy grande... las opciones de transferencia deben ir
		-- dentro del submenu de Retirar". addFlatToContext volcaba TODAS las
		-- opciones de retiro (destino, cantidades, seleccion) sueltas en la
		-- raiz del menu - GlobalStorageSiK.WithdrawMenu.addToContext YA
		-- construia exactamente el submenu "Retirar" agrupado que hacia
		-- falta (usado en otro punto del proyecto), simplemente no se llamaba
		-- aqui todavia. Cero codigo nuevo, solo la llamada correcta.
		if data.aggregateAllowed ~= false or (data.itemIds and #data.itemIds > 0) then
			GlobalStorageSiK.WithdrawMenu.addToContext(cm, player, data, function(rowData, amount, targetKey)
				withdrawFromRowData(terminal, rowData, amount, targetKey)
			end, getSelectedRows(listPanel), function(rows, amount, targetKey)
				GlobalStorageSiK.WithdrawClient.sendWithdrawBatch(rows, amount, targetKey,
					terminal.getSearchQuery and terminal:getSearchQuery() or "", {
						playerNum = playerNum,
						networkId = terminal.terminalState and terminal.terminalState.networkId,
						onComplete = function(ok, result)
							if type(terminal.onWithdrawCompleted) == "function" then
								terminal:onWithdrawCompleted(ok, result)
							else
								GlobalStorageSiK.TerminalItems.onWithdrawCompleted(listPanel, terminal, ok, result)
							end
						end,
					})
			end)
		end

		-- "Localizar objeto" (dev26 ronda 4quinquies, ver Documentacion/
		-- pending-work/DEFERRED.md): ilumina TODOS los contenedores reales que
		-- aportan a esta fila agregada (data.locations, ver GS_Index.lua) con
		-- el mismo sistema seguro ya usado en la pestaña Nodos
		-- (GS_NodeHighlight.highlightNodes) - nunca un resaltado propio nuevo,
		-- misma proteccion contra parpadeo/coste de render repetido.
		if data.locations and #data.locations > 0 then
			cm:addOption(T("IGUI_GS_LocateItem"), player, function()
				local nodeIds = {}
				for i = 1, #data.locations do
					nodeIds[#nodeIds + 1] = data.locations[i].nodeId
				end
				local allNodes = terminal.terminalState and terminal.terminalState.nodes or {}
				GlobalStorageSiK.NodeHighlight.highlightNodes(nodeIds, allNodes)
			end)
		end

		GlobalStorageSiK.ContextMenuUi.raiseMenu(cm)
		GlobalStorageSiK.Log.debug("ExactWithdraw", "contextMenu.raised row="
			.. tostring(data.rowKey or data.fullType))
	end)

	if not ok then
		GlobalStorageSiK.Log.error("TerminalUI", "openItemContextMenu failed", err)
		if menuState and menuState.ui then
			if menuState.wasVisible then
				menuState.ui:setVisible(true)
			end
			if menuState.wasAlwaysOnTop then
				menuState.ui:setAlwaysOnTop(true)
			end
		end
		return
	end

	GlobalStorageSiK.ContextMenuUi.scheduleTerminalRestore(menuState)
end

local function presentationProjection(data)
	local projection = GlobalStorageSiK.NativeProduct.getRowProjection(data)
	if projection.mode ~= "vanilla" or projection.vanillaKey ~= "Misc"
		or not data or not data.worldSprite then
		return projection
	end
	local cacheKey = tostring(data.fullType or "") .. "\31" .. tostring(data.worldSprite)
	local cached = MOVABLE_PRESENTATION_CACHE[cacheKey]
	if cached ~= nil then return cached or projection end
	-- Fallback exclusivamente visual: un Moveable puede llegar con el
	-- DisplayCategory generico "Misc" aunque su instancia reconstruida tenga
	-- una familia concreta. No se modifica snapshot, indice, routing ni red.
	local probe = itemProbe(data)
	local presentation = probe and GlobalStorageSiK.CategoryResolution.presentation(data.fullType, data, probe) or nil
	local resolved = presentation and presentation.resolution or nil
	if resolved and resolved.effective ~= "vanilla" then
		local fallback = {
			mode = resolved.effective,
			key = resolved.routingIdentity,
			fullLabel = presentation.labels.full,
			color = presentation.color,
			nativePath = resolved.nativePath,
		}
		MOVABLE_PRESENTATION_CACHE[cacheKey] = fallback
		return fallback
	end
	MOVABLE_PRESENTATION_CACHE[cacheKey] = false
	return projection
end

--- Descriptor visual canonico compartido por la fila y su DragGhost.
---@param data table
---@param listPanel ISPanel|nil
---@param terminal GS_TerminalUI|nil
---@param zoneLabel string|nil
---@return table
function GlobalStorageSiK.TerminalItems.describeRow(data, listPanel, terminal, zoneLabel)
	local expanded = data and data.expandable and listPanel and listPanel._expandedKeys
		and listPanel._expandedKeys[rowIdentity(data)] == true
	local hierarchy = {
		kind = data and data._gsRowKind or "leaf", depth = data and data._gsDepth or 0,
		hasChildren = data and data.expandable == true, expanded = expanded,
	}
	local name = displayNameForRow(data)
	local projection = presentationProjection(data)
	local muted = UI.Theme.tokens().textMuted
	local pal = { textMuted = { muted.r, muted.g, muted.b } }
	local playerNum = terminal and terminal.playerNum or 0
	local player = GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer(playerNum)
		or getSpecificPlayer(playerNum)
	return {
		identity = rowIdentity(data), data = data, hierarchy = hierarchy,
		texture = itemTexture(data), name = name,
		category = projection.fullLabel ~= "" and projection.fullLabel
			or GlobalStorageSiK.I18n.itemCategoryDisplay(data.fullType, data.category, data.subCategory, data.gsSubKeysStr),
		categoryColor = projection.color or pal.textMuted,
		zone = zoneLabel or resolveZoneLabel(terminal, data) or T("IGUI_GS_PunctuationEmDash"),
		count = tostring(data.count or 0), depth = data._gsDepth or 0,
		rowKind = data._gsRowKind, expanded = expanded,
		literatureRead = GlobalStorageSiK.RecordedMedia.hasBeenConsumed(player, data)
			or isLiteratureReadSafe(player, data), stale = data._gsStale == true,
		iconSize = ICON_SIZE, iconGap = 8,
	}
end

function GlobalStorageSiK.TerminalItems.rowHeight()
	return ROW_H
end

--- Separa la representacion del fantasma del contrato que se envia al servidor.
--- La cabecera conserva siempre la misma seleccion semantica, este abierta,
--- cerrada o paginada; solo el fantasma incorpora los hijos visibles.
function GlobalStorageSiK.TerminalItems.buildDragState(listPanel, rowData, selectionRows)
	local displayed = listPanel and listPanel._lastItems or {}
	local selected = {}
	local sourceRows = selectionRows and #selectionRows > 1 and selectionRows or { rowData }
	for i = 1, #sourceRows do
		local key = rowIdentity(sourceRows[i])
		if key then selected[key] = true end
	end
	local payloadRows, visualRows, payloadSeen, visualSeen, coveredParents = {}, {}, {}, {}, {}
	local function addPayload(row)
		local key = rowIdentity(row)
		if row and not row._gsStale and row.fullType and key and not payloadSeen[key] then
			payloadSeen[key] = true
			payloadRows[#payloadRows + 1] = row
		end
	end
	local function addVisual(row)
		local key = rowIdentity(row)
		if row and key and not visualSeen[key] then
			visualSeen[key] = true
			visualRows[#visualRows + 1] = row
		end
	end
	for i = 1, #displayed do
		local row = displayed[i]
		local key = rowIdentity(row)
		if key and selected[key] then
			if row._gsRowKind == "child" and row.parentRowKey and selected[row.parentRowKey] then
				coveredParents[row.parentRowKey] = true
			else
                                addVisual(row)
                                if row._gsRowKind == "parent" and row.expandable and listPanel._expandedKeys
                                        and listPanel._expandedKeys[key] then
                                        -- El fantasma representa lo que el jugador ve: cabecera y
                                        -- únicamente los hijos de la página visible. La transferencia,
                                        -- en cambio, conserva la identidad y el recuento TOTAL de la
                                        -- cabecera; usar aquí los hijos paginados limitaba el movimiento
                                        -- a las primeras 15 filas y convertía la presentación en payload.
                                        addPayload(row)
                                        local j = i + 1
                                        while j <= #displayed and displayed[j]._gsRowKind == "child"
                                                and displayed[j].parentRowKey == key do
                                                addVisual(displayed[j])
                                                j = j + 1
                                        end
                                else
                                        addPayload(row)
                                end
			end
		end
	end
	if #payloadRows == 0 then addPayload(rowData) end
	if #visualRows == 0 then addVisual(rowData) end
	return { payloadRows = payloadRows, visualRows = visualRows }
end

--- Adapta la interacción de producto a filas que pertenecen por completo a
--- Table/VirtualList. Almacén no crea paneles, pools, fondos ni hitboxes.
local function selectedKeysAsList(panel)
	local out = {}
	for key, selected in pairs(panel._selectedKeys or {}) do
		if selected then out[#out + 1] = key end
	end
	return out
end

local function syncTableSelection(panel)
	if panel and panel.itemTable then
		panel.itemTable:setSelectedKeys(selectedKeysAsList(panel))
	end
end

local function updateRemoteMediaTitle(row, detail, listPanel, terminal)
	if not row._gsTooltip or not row.itemData or row.itemData._gsStale
		or not pointerInsideRow(row) then return end
	if tostring(detail and detail.itemId) ~= tostring(row.itemData.itemId) then return end
	local mediaTitle = detail and (detail.mediaTitle or detail.displayName) or nil
	local mediaIndex = tonumber(row.itemData.mediaIndex or (detail and detail.mediaIndex))
	if mediaIndex and mediaIndex >= 0 and mediaIndex <= 32767
		and not isGenericRecordedMediaTitle(mediaTitle, row.itemData) then
		local function applyToRows(rows)
			for i = 1, #(rows or {}) do
				local candidate = rows[i]
				if tonumber(candidate.mediaIndex) == mediaIndex then
					candidate.mediaTitle = mediaTitle
					candidate.displayName = mediaTitle
					if type(detail.mediaCodes) == "table" then candidate.mediaCodes = detail.mediaCodes end
				end
				applyToRows(candidate.variantSummary)
			end
		end
		applyToRows(listPanel and listPanel._itemsCatalog)
		applyToRows(listPanel and listPanel._lastItems)
		local pages = listPanel and listPanel._detailPages or detailPagesByRowKey()
		for _, page in pairs(pages or {}) do applyToRows(page.items) end
		if mediaIndex then
			MEDIA_TITLE_CACHE[recordedMediaCacheKey(row.itemData,
				terminal and terminal.playerNum or 0)] = mediaTitle
		end
		if listPanel and listPanel.itemTable and listPanel.itemTable.list then
			listPanel.itemTable.list:refresh()
		end
	end
	local probe = row._gsTooltip.item
	if probe then GlobalStorageSiK.RemoteItemDetail.bindProbe(probe, row.itemData, detail, false) end
end

local function updateFrameworkRow(context, listPanel, terminal)
	local row, data = context.row, context.item
	if rowIdentity(row.itemData) ~= rowIdentity(data) then
		GlobalStorageSiK.TerminalItems.hideRowTooltip(row)
		row._gsExpandPressed, row._gsDragPending, row._gsDragAccum = nil, false, 0
		if row.setCapture then row:setCapture(false) end
	end
	row.itemData, row.listPanel, row.terminal = data, listPanel, terminal
	row.rowIndex = context.visibleIndex
	row._gsZoneLabel = data and resolveZoneLabel(terminal, data) or nil
	row.onRemoteItemDetail = function(target, detail)
		updateRemoteMediaTitle(target, detail, listPanel, terminal)
	end
end

local function describeFrameworkRow(context, listPanel, terminal)
	local row, data = context.row, context.item
	if not data then return nil end
	local descriptor = GlobalStorageSiK.TerminalItems.describeRow(data, listPanel, terminal, row._gsZoneLabel)
	local theme = UI.Theme.tokens()
	descriptor.alpha = descriptor.stale and 0.45 or 1
	descriptor.overlayTexture = descriptor.literatureRead and getTexture("media/ui/Tick_Mark-10.png") or nil
	descriptor.cells = {
		name = { text = descriptor.name, pad = 0, color = theme.text },
		category = { text = descriptor.category, color = descriptor.categoryColor },
		zone = { text = descriptor.zone, color = theme.textMuted },
		count = { text = descriptor.count, color = theme.text },
	}
	return descriptor
end

local function afterRenderFrameworkRow(context, listPanel, terminal)
	local row, data = context.row, context.item
	if not data then return end
	local hovering = pointerInsideRow(row)
	if not data._gsStale and hovering and not GlobalStorageSiK.TerminalWithdrawDrag.isActive() then
		local tooltipKey = rowIdentity(data) or (tostring(data.fullType) .. "\31" .. tostring(data.worldSprite or ""))
		if row._gsLocalTooltip and not LocalItemTooltip.isCurrent(row._gsLocalTooltip, data, terminal) then
			GlobalStorageSiK.TerminalItems.hideRowTooltip(row)
		end
		if not row._gsTooltip or row._gsTooltip._gsItemKey ~= tooltipKey then
			GlobalStorageSiK.RemoteItemDetail.deactivate(row)
			row._gsLocalTooltip = LocalItemTooltip.resolve(data, terminal)
			local probe = row._gsLocalTooltip and row._gsLocalTooltip.item or itemProbe(data)
			if probe then
				if row._gsTooltip then row._gsTooltip:setItem(probe) else
					row._gsTooltip = ISToolTipInv:new(probe)
					row._gsTooltip:initialise()
					row._gsTooltip:setOwner(row)
					GlobalStorageSiK.TerminalItems.makePassiveTooltip(row._gsTooltip)
				end
				local playerNum = terminal and terminal.playerNum or 0
				local player = GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer(playerNum)
					or getSpecificPlayer(playerNum)
				row._gsTooltip:setCharacter(player)
				row._gsTooltip._gsItemKey = tooltipKey
				local detail, loading = nil, false
				if data._gsRowKind == "child" and not row._gsLocalTooltip then
					detail, loading = GlobalStorageSiK.RemoteItemDetail.activate(row, data, terminal)
				end
				if not row._gsLocalTooltip then
					GlobalStorageSiK.RemoteItemDetail.bindProbe(probe, data, detail, loading)
				end
			end
		end
		if row._gsTooltip then
			row._gsTooltip._gsRemoteRow = data
			GlobalStorageSiK.TerminalItems.showRowTooltip(row)
		end
	else
		GlobalStorageSiK.TerminalItems.hideRowTooltip(row)
		if listPanel._deferredRefresh then
			GlobalStorageSiK.TerminalItems.flushDeferredRefresh(listPanel)
		end
	end
end

local function itemRowAdapter(listPanel, terminal)
	return {
		update = function(context) updateFrameworkRow(context, listPanel, terminal) end,
		describe = function(context) return describeFrameworkRow(context, listPanel, terminal) end,
		afterRender = function(context) afterRenderFrameworkRow(context, listPanel, terminal) end,
		dispose = function(context) GlobalStorageSiK.TerminalItems.disposeRowTooltip(context.row) end,
		onMouseDown = function(context)
			local row, data = context.row, context.item
			if data._gsStale then return true end
			if isRightMouseButtonDown and isRightMouseButtonDown() then return false end
			row._gsDragPending, row._gsDragAccum = true, 0
			return false
		end,
		onMouseMove = function(context)
			local row, data, event = context.row, context.item, context.event
			if GlobalStorageSiK.TerminalWithdrawDrag.isActive() then
				GlobalStorageSiK.TerminalWithdrawDrag.moveToPointer()
				return true
			end
			if not row._gsDragPending then return false end
			row._gsDragAccum = (row._gsDragAccum or 0) + math.abs(event.dx or 0) + math.abs(event.dy or 0)
			if row._gsDragAccum < DRAG_THRESHOLD then return false end
			row._gsDragPending = false
			GlobalStorageSiK.TerminalItems.hideRowTooltip(row)
			local selection = getSelectedRows(listPanel)
			local multi = #selection > 1 and isRowSelected(listPanel, rowIdentity(data))
			local dragState = GlobalStorageSiK.TerminalItems.buildDragState(
				listPanel, data, multi and selection or nil)
			-- `begin` recibe cantidad, no playerNum. Pasar el jugador 0 producía un
			-- payload de retirada de cero unidades aunque el ghost fuese correcto.
			GlobalStorageSiK.TerminalWithdrawDrag.begin(data, 1,
				dragState.payloadRows, dragState.visualRows, row)
			return true
		end,
		onMouseUpOutside = function(context)
			local row = context.row
			row._gsDragPending = false
			if GlobalStorageSiK.TerminalWithdrawDrag.isActive() then
				return GlobalStorageSiK.TerminalWithdrawDrag.finishAtPointer()
			end
			GlobalStorageSiK.TerminalItems.onInteractionFinished(listPanel)
			return true
		end,
		onMouseUp = function(context)
			local row, data = context.row, context.item
			if data._gsStale then return true end
			if GlobalStorageSiK.TerminalWithdrawDrag.isActive() then
				return GlobalStorageSiK.TerminalWithdrawDrag.finishAtPointer()
			end
			if row._gsDragPending then
				row._gsDragPending = false
				handleRowClick(listPanel, row)
				syncTableSelection(listPanel)
				GlobalStorageSiK.TerminalItems.onInteractionFinished(listPanel)
				return true
			end
			return false
		end,
		onDoubleClick = function(context)
			local data = context.item
			if not data or data._gsStale then return true end
			withdrawRowWithActiveTarget(terminal, data, 1)
			return true
		end,
		onRightClick = function(context)
			local data = context.item
			if data._gsStale then return true end
			GlobalStorageSiK.TerminalItems.hideRowTooltip(context.row)
			if not isRowSelected(listPanel, rowIdentity(data)) then
				selectSingleRow(listPanel, rowIdentity(data), context.visibleIndex)
				syncTableSelection(listPanel)
			end
			openItemContextMenu(listPanel, terminal, data)
			return true
		end,
	}
end

local function splitDisplayRows(rows)
	local roots, parentByKey = {}, {}
	for index = 1, #(rows or {}) do
		local row = rows[index]
		if row._gsRowKind == "parent" or not row.parentRowKey then
			row._sikChildren = {}
			roots[#roots + 1] = row
			parentByKey[rowIdentity(row)] = row
		else
			local parent = parentByKey[row.parentRowKey]
			if parent then parent._sikChildren[#parent._sikChildren + 1] = row end
		end
	end
	return roots
end

local function itemTableOptions(panel, terminal)
	return {
		rowHeight = ROW_H, headerHeight = HEADER_H,
		gap = ITEM_TABLE_OPTIONS.gap, left = 0, right = 0,
		playerNum = terminal and terminal.playerNum or 0,
		selectionMode = "multiple", row = itemRowAdapter(panel, terminal),
		keyOf = function(row) return rowIdentity(row) end,
		expansion = {
			childrenOf = function(row) return row._sikChildren or {} end,
			hasChildren = function(row) return row.expandable == true end,
			keyOf = function(row) return rowIdentity(row) end,
		},
		-- Las filas hijas son una pagina remota ya materializada. Table pinta
		-- ese conjunto completo y conserva el pager generico; nunca vuelve a
		-- paginar la pagina ni introduce una fila-pager de producto.
		pagination = {
			pageSize = 15,
			external = true,
			labelOf = function(state)
				return T("IGUI_GS_ItemDetailPage", tostring(state.first), tostring(state.last),
					tostring(state.totalRows or state.total), tostring(state.totalUnits or 0))
			end,
			stateOf = function(parent, key)
				local detailPage = GlobalStorageSiK.TerminalItems.getDetails(key, panel)
				local wantedPage = panel._detailPageByKey and panel._detailPageByKey[key] or 1
				local revision = terminal and terminal.terminalState
					and terminal.terminalState.inventoryRevision or 0
				local networkId = terminal and terminal.terminalState
					and terminal.terminalState.networkId or nil
				local pageStale = not detailPage or detailPage.page ~= wantedPage
					or detailPage.networkId ~= networkId
					or tonumber(detailPage.inventoryRevision or -1) ~= tonumber(revision)
				local pending = panel._detailPending and panel._detailPending[key] == true
				return {
				-- El paginador cuenta exclusivamente filas hijas renderizadas. La
				-- fila padre/cabecera aporta unidades, pero nunca una fila de detalle.
				total = detailPage and (detailPage.totalRows or detailPage.total) or 0,
					totalRows = detailPage and (detailPage.totalRows or detailPage.total) or nil,
					totalUnits = detailPage and detailPage.totalUnits
						or tonumber(parent and parent.count) or 0,
					page = detailPage and detailPage.page or wantedPage,
					pageSize = detailPage and detailPage.pageSize or 15,
					pending = pending, stale = pageStale,
					disabled = pending or pageStale,
					disabledReason = pending and "page_request_pending" or "page_stale",
				}
			end,
			onPageChange = function(context)
				panel._detailPageByKey = panel._detailPageByKey or {}
				panel._detailPending = panel._detailPending or {}
				panel._detailPageByKey[context.parentKey] = context.page
				panel._detailPending[context.parentKey] = true
				local sent = GlobalStorageSiK.TerminalItems.requestDetails(
					terminal, context.parent, context.page)
				if not sent then panel._detailPending[context.parentKey] = nil end
				if terminal.refreshItemsTab then terminal:refreshItemsTab() end
				return sent
			end,
		},
		onExpansionChange = function(context)
			panel._expandedKeys = panel._expandedKeys or {}
			panel._expandedKeys[context.key] = context.expanded and true or nil
			if context.expanded then
				local page = panel._detailPageByKey and panel._detailPageByKey[context.key] or 1
				local cached = GlobalStorageSiK.TerminalItems.getDetails(context.key, panel)
				if not cached and not (panel._detailPending and panel._detailPending[context.key]) then
					panel._detailPending = panel._detailPending or {}
					panel._detailPending[context.key] = true
					GlobalStorageSiK.TerminalItems.requestDetails(terminal, context.item, page)
				end
			end
			if terminal.refreshItemsTab then terminal:refreshItemsTab() end
		end,
		onSort = function(context)
			panel.itemsSortKey, panel.itemsSortAsc = context.key, context.ascending
			panel._itemsScrollOffset = 0
			if terminal.refreshItemsTab then terminal:refreshItemsTab() end
		end,
		sortKey = panel.itemsSortKey or "category", sortAsc = panel.itemsSortAsc ~= false,
		emptyText = T("IGUI_GS_NoItems"),
	}
end

--- Runtime adapter for a declarative SiK.UI Table node. The framework owns
--- construction and geometry; Almacen supplies only item behaviour/data.
---@param panel table
---@param terminal GS_TerminalUI
---@return table
function GlobalStorageSiK.TerminalItems.tableOptions(panel, terminal)
	return itemTableOptions(panel, terminal)
end

function GlobalStorageSiK.TerminalItems.columns(options)
	local columns = {}
	for i = 1, #ITEM_TABLE_COLUMNS do
		local source = ITEM_TABLE_COLUMNS[i]
		if not (options and options.hideZone and source.key == "zone") then
			local column = {}
			for key, value in pairs(source) do column[key] = value end
			columns[#columns + 1] = column
		end
	end
	return columns
end

local function warehouseBounds(panel, width, height)
	local w = width or (panel and panel.getWidth and panel:getWidth()) or (panel and panel.width) or 1
	local h = height or (panel and panel.getHeight and panel:getHeight()) or (panel and panel.height) or 1
	return { x = 0, y = 0, w = math.max(1, tonumber(w) or 1), h = math.max(1, tonumber(h) or 1) }
end

local function bindWarehouseAliases(panel, terminal)
	local surface = panel and panel._sikWarehouseSurface
	local tree = surface and surface.getTree and surface:getTree() or surface
	local nodes = tree and tree.nodes or {}
	panel.itemTable = nodes["warehouse-table"] or panel.itemTable
	terminal.itemsListPanel = panel
	terminal.searchEntry = nodes["warehouse-search-field"]
	terminal.searchBox = terminal.searchEntry
	terminal.searchBtn = nodes["warehouse-search-button"]
	terminal.mainCategoryFilterCombo = nodes["warehouse-family-filter"]
	terminal.subCategoryFilterCombo = nodes["warehouse-group-filter"]
	terminal.leafCategoryFilterCombo = nodes["warehouse-detail-filter"]
	terminal.autoSortStatusRow = nodes["warehouse-status"]
	terminal.itemsWeightLbl = nodes["warehouse-capacity"]
	terminal.depositDropHint = nodes["warehouse-drop-hint"]
	local root = nodes["warehouse-root"]
	terminal.itemsTitleLbl = root and root.headerControl or nil
	terminal.autoSortBtn = terminal.itemsTitleLbl and terminal.itemsTitleLbl.action or nil
	return panel.itemTable ~= nil
end

local function releaseWarehouse(panel, terminal)
	if not panel then return false end
	local released = false
	if GlobalStorageSiK.TerminalDrop and GlobalStorageSiK.TerminalDrop.disposePanel then
		GlobalStorageSiK.TerminalDrop.disposePanel(panel, terminal)
	end
	if panel._sikWarehouseSurface then
		panel._sikWarehouseSurface:dispose()
		panel._sikWarehouseSurface = nil
		released = true
	end
	if panel._sikWarehouseContext then
		panel._sikWarehouseContext:dispose()
		panel._sikWarehouseContext = nil
		released = true
	end
	if panel.itemTable and panel.itemTableFrame then panel.itemTable:dispose() end
	if panel.itemTableFrame then
		panel.itemTableFrame:dispose()
		panel.itemTableFrame = nil
		released = true
	end
	panel.itemTable = nil
	if terminal then
		terminal.itemsListPanel, terminal.searchBox, terminal.searchEntry, terminal.searchBtn = nil, nil, nil, nil
		terminal.mainCategoryFilterCombo, terminal.subCategoryFilterCombo = nil, nil
		terminal.leafCategoryFilterCombo, terminal.itemsTitleLbl, terminal.autoSortBtn = nil, nil, nil
		terminal.autoSortStatusRow, terminal.itemsWeightLbl, terminal.depositDropHint = nil, nil, nil
	end
	return released
end

--- Construye la superficie declarativa validada de Almacen una sola vez.
function GlobalStorageSiK.TerminalItems.buildSection(panel, terminal)
	if not panel or not terminal then return nil, "invalid_warehouse_parent" end
	releaseWarehouse(panel, terminal)
	local context, contextReason = TabWarehouseContext.create(terminal, panel)
	if not context then return nil, contextReason end
	panel._sikWarehouseContext = context
	local snapshot, snapshotReason = context:snapshot((terminal.terminalState or {}).items)
	if not snapshot then releaseWarehouse(panel, terminal); return nil, snapshotReason end
	snapshot.viewport = warehouseBounds(panel)
	local surface, surfaceReason = SiK.UI.SurfaceHost.mount(panel, TabWarehouseSpec, {
		context = snapshot,
		bounds = snapshot.viewport,
		followParent = true,
	})
	if not surface then releaseWarehouse(panel, terminal); return nil, surfaceReason end
	panel._sikWarehouseSurface = surface
	bindWarehouseAliases(panel, terminal)
	if GlobalStorageSiK.TerminalDrop then GlobalStorageSiK.TerminalDrop.setupPanel(panel, terminal) end
	return surface
end

--- Actualiza datos/estado sin recrear widgets y conserva la presentacion exacta
--- de filas, tooltip, seleccion, expansion y drag aportada por tableOptions.
function GlobalStorageSiK.TerminalItems.refreshSection(panel, terminal, items)
	if not panel or not terminal then return false, "invalid_warehouse_parent" end
	local surface = panel._sikWarehouseSurface
	if not surface then
		local built, reason = GlobalStorageSiK.TerminalItems.buildSection(panel, terminal)
		if not built then return false, reason end
		surface = built
	end
	local context = panel._sikWarehouseContext
	local snapshot, reason = context and context:snapshot(items)
	if not snapshot then return false, reason or "warehouse_context_unavailable" end
	snapshot.viewport = warehouseBounds(panel)
	local updated, updateReason = surface:refresh(snapshot)
	if not updated then return false, updateReason end
	bindWarehouseAliases(panel, terminal)
	return true
end

function GlobalStorageSiK.TerminalItems.layoutSection(panel, terminal, width, height)
	local surface = panel and panel._sikWarehouseSurface
	if not surface then return false end
	local result = surface:reflow(warehouseBounds(panel, width, height))
	bindWarehouseAliases(panel, terminal)
	return result
end

function GlobalStorageSiK.TerminalItems.disposeSection(panel, terminal)
	return releaseWarehouse(panel, terminal)
end

local function ensureItemTable(panel, terminal)
	if panel.itemTable then return panel.itemTable end
	local options = itemTableOptions(panel, terminal)
	local frame, frameReason = UI.Block.create({
		parent = panel, x = 0, y = 0,
		w = panel.width, h = math.max(120, panel.height),
		title = T("IGUI_GS_TabItems"), tooltip = T("IGUI_GS_TabItems"),
	})
	if not frame then
		GlobalStorageSiK.Log.error("TerminalItems", "block_create_failed", tostring(frameReason))
		return nil
	end
	panel.itemTableFrame = frame
	local content = frame:getContentRect()
	options.parent, options.embedded = frame.childParent, true
	options.x, options.y, options.w, options.h = content.x, content.y, content.w, content.h
	options.columns, options.rows = ITEM_TABLE_COLUMNS, {}
	local tableInstance, reason = UI.Table.create(options)
	if not tableInstance then
		frame:dispose()
		panel.itemTableFrame = nil
		GlobalStorageSiK.Log.error("TerminalItems", "table_create_failed", tostring(reason))
		return nil
	end
	panel.itemTable = tableInstance
	return tableInstance
end

--- Lista opciones de depósito (jugador + contenedores cercanos).
---@param player IsoPlayer|nil
---@return table[]
function GlobalStorageSiK.TerminalItems.buildDepositSources(player)
	return GlobalStorageSiK.DepositSources.buildList(player)
end

--- Rellena combo de origen de depósito.
---@param combo ISComboBox
---@param player IsoPlayer|nil
function GlobalStorageSiK.TerminalItems.fillDepositCombo(combo, player)
	if not combo then
		return
	end
	combo:clear()
	local ok, sources = pcall(GlobalStorageSiK.TerminalItems.buildDepositSources, player)
	combo.depositSources = ok and sources or {}
	for i = 1, #combo.depositSources do
		combo:addOption(combo.depositSources[i].label)
	end
	combo.selected = 1
end

--- Obtiene índice de opción de depósito (1-based).
---@param combo ISComboBox
---@return number sourceIndex
function GlobalStorageSiK.TerminalItems.getDepositSelection(combo)
	if not combo then
		return 1
	end
	return combo.selected or 1
end

--- Refresca la única tabla pública de Almacén.
---@param panel ISPanel
---@param terminal GS_TerminalUI
---@param items table[]
function GlobalStorageSiK.TerminalItems.presentationModel(panel, terminal, items)
	if not panel then return end
	if GlobalStorageSiK.TerminalItems.isInteractionActive(panel) then
		GlobalStorageSiK.TerminalItems.deferRefresh(panel, terminal)
		return { rows = panel._lastItemRoots or {}, emptyText = "" }
	end
	panel._deferredRefresh = nil
	hideVirtualRowTooltips(panel)
	items = items or {}
	localizeRecordedMediaRows(items, terminal and terminal.playerNum or 0)
	panel._itemsCatalog = items
	panel.itemsSortKey = panel.itemsSortKey or "category"
	panel.itemsSortAsc = panel.itemsSortAsc ~= false
	panel._selectedKeys = panel._selectedKeys or {}
	items = sortRows(items, panel.itemsSortKey, panel.itemsSortAsc, terminal)
	local displayRows = buildDisplayRows(panel, terminal, items)
	panel._lastItems = displayRows
	local roots = splitDisplayRows(displayRows)
	panel._lastItemRoots = roots
	local state = terminal and terminal.terminalState or nil
	local allItems = state and state.items or {}
	-- An absent item snapshot is not an empty inventory.  The terminal opens
	-- before a dedicated server completes its first inventory response, so the
	-- table must remain honestly in a loading state until the authoritative
	-- snapshot is present.  Empty/filter messages are only valid afterwards.
	local hasSnapshot = type(state) == "table" and type(state.items) == "table"
	local scanState = state and type(state.scanStatus) == "table" and state.scanStatus.state or nil
	local capturePending = state and (state.scanActive == true or state.reconcilePending == true
		or scanState == "RUNNING" or scanState == "STALE_RETRY")
	-- An initial response can contain items={} before its first scan finishes.
	-- Keep prior nonempty rows/filter results visible, but do not claim that a
	-- provisional empty capture proves the network contains no physical items.
	local pendingEmpty = capturePending and #allItems == 0
	local expanded = {}
	for key in pairs(panel._expandedKeys or {}) do expanded[key] = true end
	return {
		rows = roots,
		-- Scan progress has one canonical, permanently visible owner: the shell
		-- status indicator. Repeating it as an empty-table message created the
		-- overlapping duplicate observed at runtime.
		emptyText = (not hasSnapshot or pendingEmpty) and ""
			or T(#allItems > 0 and "IGUI_GS_NoFilterMatches" or "IGUI_GS_NoItems"),
		sortKey = panel.itemsSortKey,
		sortAsc = panel.itemsSortAsc,
		expanded = expanded,
		selectedKeys = selectedKeysAsList(panel),
		scrollOffset = panel._itemsScrollOffset,
	}
end

-- Compatibilidad de llamada durante la migracion: refrescar nunca vuelve a
-- pintar ni posicionar widgets. La superficie declarativa es la unica autora.
function GlobalStorageSiK.TerminalItems.refresh(panel, terminal, items)
	return GlobalStorageSiK.TerminalItems.refreshSection(panel, terminal, items)
end

function GlobalStorageSiK.TerminalItems.updateVirtualRows(panel)
	if panel and panel.itemTable and panel.itemTable.list then panel.itemTable.list:refresh() end
end

--- Solo geometría de la tabla de ítems; Table/Block poseen header, scroll y gutter.
---@param panel ISPanel|nil
---@param terminal GS_TerminalUI|nil
function GlobalStorageSiK.TerminalItems.syncLayout(panel, terminal)
        if not panel then return end
        -- The warehouse now owns a declarative surface.  Repositioning its table
        -- directly after Builder has laid out title, search and filters resets the
        -- table to (0,0), leaving its header over unrelated controls.  Keep the
        -- old fallback only for an unmigrated panel.
        if panel._sikWarehouseSurface then
                return GlobalStorageSiK.TerminalItems.layoutSection(panel, terminal, panel.width, panel.height)
        end
        local tableInstance = ensureItemTable(panel, terminal)
	if not tableInstance then return end
	local savedOffset = panel._itemsScrollOffset or tableInstance:getScrollOffset()
	tableInstance:setBounds(0, 0, panel.width, math.max(120, panel.height))
	tableInstance:setScrollOffset(savedOffset)
	panel._itemsScrollOffset = tableInstance:getScrollOffset()
end
