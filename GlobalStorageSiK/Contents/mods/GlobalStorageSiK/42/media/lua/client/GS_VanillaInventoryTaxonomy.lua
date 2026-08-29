--[[
	GlobalStorageSiK - Proyección de taxonomía en ISInventoryPane
	Core 1.4.3-dev31

	Solo sustituye el TEXTO dibujado en la columna vanilla Categoría. No toca
	InventoryItem, DisplayCategory, orden, filtros, selección, drag/drop, menús
	ni persistencia. La clasificación nunca ocurre dentro de renderdetails():
	las filas visibles se encolan y se resuelven con presupuesto en OnTick.
]]

require "ISUI/ISInventoryPane"
require "GS_CategoryResolution"
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
		return GlobalStorageSiK.CategoryResolution.isVanillaKey(value) and value or nil
	end
	return read("getDisplayCategory") or read("getCategory") or "Misc"
end

local function vanillaLabel(item)
	local key = safeVanillaKey(item)
	local text = getText("IGUI_ItemCat_" .. key)
	return text and text ~= "" and text or key
end

local function getFluidContainer(item)
	if not item or not item.getFluidContainer then return nil end
	local fluid = safeCall(function() return item:getFluidContainer() end)
	if fluid then return fluid end
	local worldItem = item.getWorldItem and safeCall(function() return item:getWorldItem() end) or nil
	if worldItem and worldItem.getFluidContainer then
		return safeCall(function() return worldItem:getFluidContainer() end)
	end
	return nil
end

local function hasFluidCategory(fluid, category)
	if not fluid or not category or not fluid.isCategory then return false end
	return safeCall(function() return fluid:isCategory(category) end) == true
end

--- Lee exclusivamente APIs públicas B42. No modifica amount/capacity/fluido.
--- Si mezcla o identidad no son fiables, devuelve nil y se conserva la forma.
local function dynamicFluidPath(item)
	local fluid = getFluidContainer(item)
	if not fluid or not fluid.isEmpty then return nil, nil end
	local empty = safeCall(function() return fluid:isEmpty() end)
	if empty == true then return nil, "empty" end
	if empty ~= false then return nil, "unknown" end
	local amount = fluid.getAmount and safeCall(function() return fluid:getAmount() end) or nil
	local capacity = fluid.getCapacity and safeCall(function() return fluid:getCapacity() end) or nil
	local mixture = fluid.isMixture and safeCall(function() return fluid:isMixture() end) or nil
	local primary = fluid.getPrimaryFluid and safeCall(function() return fluid:getPrimaryFluid() end) or nil
	local fluidType = primary and primary.getFluidTypeString and safeCall(function() return primary:getFluidTypeString() end) or nil
	local signature = "amount=" .. tostring(amount) .. " capacity=" .. tostring(capacity)
		.. " mixture=" .. tostring(mixture) .. " fluidType=" .. tostring(fluidType)
	if mixture ~= false or not primary then return nil, signature end
	if FluidCategory and (hasFluidCategory(fluid, FluidCategory.Beverage) or hasFluidCategory(fluid, FluidCategory.Water)) then
		return "native:food_drink/beverage", signature
	end
	if FluidCategory and hasFluidCategory(fluid, FluidCategory.Fuel) then
		return "native:vehicles/consumable", signature
	end
	return nil, signature
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

local function cacheBase(state, fullType, item)
	local cached = state.baseByFullType[fullType]
	if cached ~= nil then return cached or nil end
	local resolved = GlobalStorageSiK.CategoryResolution.resolve(fullType, nil, item)
	local path = resolved and resolved.effective == "native" and resolved.nativePath or false
	if state.baseCount >= MAX_PANE_TYPES then
		state.baseByFullType = {}
		state.baseCount = 0
	end
	state.baseByFullType[fullType] = path
	state.baseCount = state.baseCount + 1
	return path or nil
end

local function resolveQueuedItem(pane, state, item)
	local fullType = getFullType(item)
	if not fullType then return end
	local basePath = cacheBase(state, fullType, item)
	local contentPath, fluidSignature = dynamicFluidPath(item)
	local nativePath = contentPath or basePath
	state.byItem[item] = { nativePath = nativePath, facetPath = basePath, fluidSignature = fluidSignature }
	local previousSignature = state.probeSignatureByItem[item]
	state.probeSignatureByItem[item] = fluidSignature
	if fluidSignature and fluidSignature ~= previousSignature and GlobalStorageSiK.Log and GlobalStorageSiK.Log.detail then
		GlobalStorageSiK.Log.detail("VanillaInventoryProjection", "fluid probe",
			"fullType=" .. fullType .. " " .. fluidSignature
				.. " projected=" .. tostring(contentPath or basePath or "vanilla"))
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

local function isVanillaCategoryDraw(pane, x, r, g, b, doDragged)
	return not doDragged and x == pane.column3 + 8 and r == 0.6 and g == 0.6 and b == 0.8
end

local originalRenderDetails = nil

function Projection.installHooks()
	if Projection._hooksInstalled or not ISInventoryPane or not ISInventoryPane.renderdetails then
		return Projection._hooksInstalled == true
	end
	originalRenderDetails = ISInventoryPane.renderdetails
	ISInventoryPane.renderdetails = function(pane, doDragged)
		-- No encadenar nuestro propio wrapper si otro proveedor rebota de forma
		-- reentrante sobre el mismo panel durante su render.
		if renderingPanes[pane] then return originalRenderDetails(pane, doDragged) end
		renderingPanes[pane] = true
		local originalDrawText = pane.drawText
		pane.drawText = function(self, text, x, y, r, g, b, a, font)
			if isVanillaCategoryDraw(self, x, r, g, b, doDragged) then
				return drawProjection(self, originalDrawText, text, x, y, r, g, b, a, font)
			end
			return originalDrawText(self, text, x, y, r, g, b, a, font)
		end
		local ok, err = pcall(originalRenderDetails, pane, doDragged)
		pane.drawText = originalDrawText
		renderingPanes[pane] = nil
		if not ok then error(err) end
		if not doDragged then
			local state = stateFor(pane)
			state.lastRenderedAt = nowMs()
			state.inactive = false
			queueVisibleRows(pane)
		end
	end
	Projection._hooksInstalled = true
	GlobalStorageSiK.Log.debug("VanillaInventoryProjection", "ISInventoryPane.renderdetails envuelto una sola vez")
	return true
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
	local path, signature = dynamicFluidPath(item)
	return { nativePath = path, signature = signature }
end

if not Projection._tickInstalled then
	Events.OnTick.Add(onTick)
	Projection._tickInstalled = true
end
