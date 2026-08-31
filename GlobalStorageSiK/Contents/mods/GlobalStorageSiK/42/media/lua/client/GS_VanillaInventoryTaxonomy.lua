--[[
	GlobalStorageSiK - Proyección de taxonomía en ISInventoryPane
	Core 1.4.3-dev31

	DisplayCategory ya se publica canónicamente en ScriptItem mediante
	GS_DisplayCategoryPublisher. Esta capa solo conserva la presentación GS
	(colores y ruta completa) sobre la misma celda vanilla; no decide ni muta
	la categoría pública, InventoryItem, orden, filtros, selección, drag/drop,
	menús ni persistencia. La clasificación nunca ocurre dentro de
	renderdetails(): las filas visibles se encolan y se resuelven con
	presupuesto en OnTick.
]]

require "ISUI/ISInventoryPane"
require "GS_CategoryResolution"
require "GS_FluidTaxonomy"
require "GS_NativeProduct"
require "GS_Sandbox"
require "GS_Log"

GlobalStorageSiK.VanillaInventoryTaxonomy = GlobalStorageSiK.VanillaInventoryTaxonomy or {}

local Projection = GlobalStorageSiK.VanillaInventoryTaxonomy
local statesByPane = setmetatable({}, { __mode = "k" })
local renderingPanes = setmetatable({}, { __mode = "k" })
local MAX_PANE_TYPES = 96
local MAX_QUEUE_PER_TICK = 12
local RECHECK_MS = 500
local INACTIVE_CLEAR_MS = 4000

local function safeCall(fn)
	local ok, value = pcall(fn)
	return ok and value or nil
end

local function nowMs()
	return getTimestampMs and getTimestampMs() or 0
end

local function getFullType(item)
	if not item or not item.getFullType then return nil end
	local value = safeCall(function() return item:getFullType() end)
	return type(value) == "string" and value ~= "" and value or nil
end

local function itemForPaneRow(pane, row)
	local entry = pane and pane.items and pane.items[row]
	if entry and entry.items then return entry.items[1] end
	return entry
end

local function newState()
	return {
		byItem = setmetatable({}, { __mode = "k" }),
		lastQueuedAt = setmetatable({}, { __mode = "k" }),
		probeSignatureByItem = setmetatable({}, { __mode = "k" }),
		queueSet = setmetatable({}, { __mode = "k" }),
		baseByFullType = {}, baseCount = 0, queue = {}, lastRenderedAt = 0, inactive = false,
	}
end

local function stateFor(pane)
	local state = statesByPane[pane]
	if not state then
		state = newState()
		statesByPane[pane] = state
	end
	return state
end

local function clearState(state)
	state.byItem = setmetatable({}, { __mode = "k" })
	state.lastQueuedAt = setmetatable({}, { __mode = "k" })
	state.probeSignatureByItem = setmetatable({}, { __mode = "k" })
	state.queueSet = setmetatable({}, { __mode = "k" })
	state.baseByFullType = {}
	state.baseCount = 0
	state.queue = {}
end

local function safeVanillaKey(item)
	local function read(method)
		if not item or not item[method] then return nil end
		local value = safeCall(function() return item[method](item) end)
		-- Tras DEV32.3 esta clave puede ser la DisplayCategory pública de GS,
		-- no solo una literal vanilla. La etiqueta sigue viniendo de
		-- IGUI_ItemCat_<clave>, igual que en el inventario sin overlay.
		if GlobalStorageSiK.CategoryResolution.isSafeSourceCategory(value) then return value end
		if GlobalStorageSiK.DisplayCategoryPublisher
			and GlobalStorageSiK.DisplayCategoryPublisher.isPublishedKey
			and GlobalStorageSiK.DisplayCategoryPublisher.isPublishedKey(value) then
			return value
		end
		return nil
	end
	return read("getDisplayCategory") or read("getCategory") or "Misc"
end

local function vanillaLabel(item)
	local key = safeVanillaKey(item)
	local text = getText("IGUI_ItemCat_" .. key)
	return text and text ~= "" and text or key
end

local function queueVisibleItem(pane, item)
	if not item then return end
	local state = stateFor(pane)
	local now = nowMs()
	local last = state.lastQueuedAt[item] or 0
	if state.queueSet[item] or now - last < RECHECK_MS then return end
	state.lastQueuedAt[item] = now
	state.queueSet[item] = true
	state.queue[#state.queue + 1] = item
end

local function queueVisibleRows(pane)
	if not pane or not pane.items or not pane.itemHgt then return end
	local scroll = pane.getYScroll and pane:getYScroll() or 0
	local height = pane.getHeight and pane:getHeight() or 0
	for row = 1, #pane.items do
		local top = (row - 1) * pane.itemHgt + scroll
		if top + pane.itemHgt >= 0 and top <= height then
			queueVisibleItem(pane, itemForPaneRow(pane, row))
		end
	end
end

local function cachePresentation(state, fullType, item)
	-- Un recipiente no es clasificable solo por fullType: la firma dinamica
	-- forma parte de la clave, pero la ruta/etiqueta siempre procede de la
	-- misma fachada que usan tooltip y filas del almacen.
	local dynamicKey = GlobalStorageSiK.CategoryResolution.dynamicSignature(item)
	local cacheKey = tostring(fullType) .. "\31" .. tostring(dynamicKey or "static")
	local cached = state.baseByFullType[cacheKey]
	if cached ~= nil then return cached or nil end
	local presentation = GlobalStorageSiK.CategoryResolution.presentation(fullType, nil, item)
	if not presentation or not presentation.nativePath then presentation = false end
	if state.baseCount >= MAX_PANE_TYPES then
		state.baseByFullType = {}
		state.baseCount = 0
	end
	state.baseByFullType[cacheKey] = presentation
	state.baseCount = state.baseCount + 1
	return presentation or nil
end

local function resolveQueuedItem(pane, state, item)
	local fullType = getFullType(item)
	if not fullType then return end
	local presentation = cachePresentation(state, fullType, item)
	local resolved = presentation and presentation.resolution or nil
	local nativePath = resolved and resolved.nativePath or nil
	local fluidSignature = presentation and presentation.dynamicSignature or nil
	-- La proyeccion dinamica es estrictamente visual. La fachada compartida
	-- consume la instancia real y nunca muta InventoryItem/ScriptItem.
	state.byItem[item] = { nativePath = nativePath, presentation = presentation,
		fluidSignature = fluidSignature }
	local previousSignature = state.probeSignatureByItem[item]
	state.probeSignatureByItem[item] = fluidSignature
	if fluidSignature and fluidSignature ~= previousSignature and GlobalStorageSiK.Log and GlobalStorageSiK.Log.detail then
		GlobalStorageSiK.Log.detail("VanillaInventoryProjection", "fluid probe",
			"fullType=" .. fullType .. " " .. fluidSignature
				.. " projected=" .. tostring(nativePath or "vanilla"))
	end
end

local function projectionFor(pane, item)
	local state = statesByPane[pane]
	local cached = state and state.byItem[item] or nil
	if cached and cached.nativePath then
		local view = GlobalStorageSiK.NativeProduct.getView(cached.nativePath)
		return view.fullLabel, GlobalStorageSiK.NativeProduct.getColor(cached.nativePath)
	end
	return vanillaLabel(item), nil
end

local function drawProjection(pane, originalDrawText, text, x, y, r, g, b, a, font)
	local row = math.floor((y - pane.headerHgt) / pane.itemHgt) + 1
	local item = itemForPaneRow(pane, row)
	if not item then return originalDrawText(pane, text, x, y, r, g, b, a, font) end
	local label, color = projectionFor(pane, item)
	local maxWidth = math.max(0, pane.column4 - pane.column3 - 16)
	if pane.isVScrollBarVisible and pane:isVScrollBarVisible() then maxWidth = math.max(0, maxWidth - 13) end
	if GlobalStorageSiK.SiK_UI and GlobalStorageSiK.SiK_UI.truncateText then
		label = GlobalStorageSiK.SiK_UI.truncateText(label, maxWidth, font)
	end
	if color then return originalDrawText(pane, label, x, y, color[1], color[2], color[3], a, font) end
	return originalDrawText(pane, label, x, y, r, g, b, a, font)
end

local function isProjectedCategoryText(item, text)
	local expected = vanillaLabel(item)
	if text == expected then return true end
	local prefix = tostring(text or ""):gsub("%.%.%.$", ""):gsub("…$", "")
	return #prefix >= 2 and expected:sub(1, #prefix) == prefix
end

local function isVanillaCategoryDraw(pane, text, x, y, doDragged, rightAligned)
	if doDragged or x < pane.column3 then return false end
	if not rightAligned and x >= pane.column4 then return false end
	local row = math.floor((y - pane.headerHgt) / pane.itemHgt) + 1
	local item = itemForPaneRow(pane, row)
	-- La celda de categoría es la única de esa fila cuyo texto coincide con la
	-- DisplayCategory vanilla. No depende de la coordenada de sangría ni del
	-- RGB del tema, ambos variables entre versiones y proveedores UI.
	return item ~= nil and isProjectedCategoryText(item, text)
end

--- API minima para adaptadores visuales opcionales. No clasifica durante el
--- render: solo lee la cache ya presupuestada y conserva el texto proveedor
--- mientras el item aun esta en cola.
function Projection.decorateDraw(pane, originalDrawText, rightAligned, text, x, y, r, g, b, a, font, doDragged)
	if isVanillaCategoryDraw(pane, text, x, y, doDragged, rightAligned) then
		return drawProjection(pane, originalDrawText, text, x, y, r, g, b, a, font)
	end
	return originalDrawText(pane, text, x, y, r, g, b, a, font)
end

function Projection.queueVisibleRows(pane)
	queueVisibleRows(pane)
end

local originalRenderDetails = nil

function Projection.installHooks()
	if Projection._hooksInstalled or not ISInventoryPane or not ISInventoryPane.renderdetails then
		return Projection._hooksInstalled == true
	end
	originalRenderDetails = ISInventoryPane.renderdetails
	local renderHook = function(pane, doDragged)
		-- No encadenar nuestro propio wrapper si otro proveedor rebota de forma
		-- reentrante sobre el mismo panel durante su render.
		if renderingPanes[pane] then return originalRenderDetails(pane, doDragged) end
		renderingPanes[pane] = true
		local originalDrawText = pane.drawText
		local originalDrawTextRight = pane.drawTextRight
		pane.drawText = function(self, text, x, y, r, g, b, a, font)
			return Projection.decorateDraw(self, originalDrawText, false,
				text, x, y, r, g, b, a, font, doDragged)
		end
		if originalDrawTextRight then
			pane.drawTextRight = function(self, text, x, y, r, g, b, a, font)
				return Projection.decorateDraw(self, originalDrawTextRight, true,
					text, x, y, r, g, b, a, font, doDragged)
			end
		end
		local ok, err = pcall(originalRenderDetails, pane, doDragged)
		pane.drawText = originalDrawText
		pane.drawTextRight = originalDrawTextRight
		renderingPanes[pane] = nil
		if not ok then error(err) end
		if not doDragged then
			local state = stateFor(pane)
			state.lastRenderedAt = nowMs()
			state.inactive = false
			queueVisibleRows(pane)
		end
	end
	Projection._renderHook = renderHook
	ISInventoryPane.renderdetails = renderHook
	Projection._hooksInstalled = true
	GlobalStorageSiK.Log.debug("VanillaInventoryProjection", "ISInventoryPane.renderdetails envuelto una sola vez")
	return true
end

function Projection.isRenderHookActive()
	return ISInventoryPane and ISInventoryPane.renderdetails == Projection._renderHook
end

local function onTick()
	local now = nowMs()
	for pane, state in pairs(statesByPane) do
		if not pane:getIsVisible() or now - state.lastRenderedAt > INACTIVE_CLEAR_MS then
			if not state.inactive then
				clearState(state)
				state.inactive = true
			end
		else
			state.inactive = false
			local processed = 0
			while processed < MAX_QUEUE_PER_TICK and #state.queue > 0 do
				local item = table.remove(state.queue, 1)
				state.queueSet[item] = nil
				resolveQueuedItem(pane, state, item)
				processed = processed + 1
			end
		end
	end
end

function Projection.describeFluidForProbe(item)
	local fullType = getFullType(item)
	local presentation = fullType and GlobalStorageSiK.CategoryResolution.presentation(fullType, nil, item) or nil
	return { nativePath = presentation and presentation.resolution and presentation.resolution.nativePath or nil,
		signature = presentation and presentation.dynamicSignature or nil }
end

if not Projection._tickInstalled then
	Events.OnTick.Add(onTick)
	Projection._tickInstalled = true
end
