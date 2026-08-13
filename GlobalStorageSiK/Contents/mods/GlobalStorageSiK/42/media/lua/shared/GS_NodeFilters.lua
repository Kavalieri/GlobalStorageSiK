--[[
	GlobalStorageSiK - Filtros personalizados de contenedor
	Descripción: Además de categorías/subcategorías, un nodo puede tener
	filtros propios (nombre, peso, tag vanilla, ítem exacto). Un ítem que
	coincide con CUALQUIER filtro del nodo se trata como coincidencia de
	máxima especificidad (mismo nivel que una subcategoría GS exacta) en
	GS_Router.matchSpecificity - ver ahí la integración.
]]

GlobalStorageSiK.NodeFilters = {}

---@param item InventoryItem
---@return string
local function itemDisplayName(item)
	if item.getDisplayName then
		local ok, name = pcall(function() return item:getDisplayName() end)
		if ok and name then return name end
	end
	if item.getName then
		local ok, name = pcall(function() return item:getName() end)
		if ok and name then return name end
	end
	return ""
end

---@param item InventoryItem
---@return number
local function itemWeight(item)
	if item.getActualWeight then
		local ok, w = pcall(function() return item:getActualWeight() end)
		if ok and w then return w end
	end
	if item.getWeight then
		local ok, w = pcall(function() return item:getWeight() end)
		if ok and w then return w end
	end
	return 0
end

--- Comprueba un único filtro contra un ítem.
---@param filter table { type="name"|"weight"|"tag"|"item", mode, value, value2, itemType }
---@param item InventoryItem
---@return boolean
function GlobalStorageSiK.NodeFilters.matchesOne(filter, item)
	if not filter or not item then
		return false
	end

	if filter.type == "name" then
		local val = string.lower(tostring(filter.value or ""))
		if val == "" then
			return false
		end
		local name = string.lower(itemDisplayName(item))
		local mode = filter.mode or "contains"
		if mode == "exact" then
			return name == val
		elseif mode == "startsWith" then
			return name:sub(1, #val) == val
		elseif mode == "endsWith" then
			return #val > 0 and name:sub(-#val) == val
		end
		return name:find(val, 1, true) ~= nil

	elseif filter.type == "weight" then
		local w = itemWeight(item)
		local v1 = tonumber(filter.value)
		if not v1 then
			return false
		end
		local mode = filter.mode or "eq"
		if mode == "gt" then
			return w > v1
		elseif mode == "lt" then
			return w < v1
		elseif mode == "gte" then
			return w >= v1
		elseif mode == "lte" then
			return w <= v1
		elseif mode == "between" then
			local v2 = tonumber(filter.value2) or v1
			local lo, hi = math.min(v1, v2), math.max(v1, v2)
			return w >= lo and w <= hi
		end
		-- eq: comparación con tolerancia (pesos flotantes)
		return math.abs(w - v1) < 0.001

	elseif filter.type == "tag" then
		local val = tostring(filter.value or "")
		if val == "" or not item.getTags then
			return false
		end
		local ok, tags = pcall(function() return item:getTags() end)
		if not ok or not tags then
			return false
		end
		for i = 0, tags:size() - 1 do
			if tostring(tags:get(i)) == val then
				return true
			end
		end
		return false

	elseif filter.type == "item" then
		if not filter.itemType or not item.getFullType then
			return false
		end
		return item:getFullType() == filter.itemType
	end

	return false
end

--- true si el ítem coincide con AL MENOS UNO de los filtros de la lista.
---@param filters table[]|nil
---@param item InventoryItem
---@return boolean
function GlobalStorageSiK.NodeFilters.matchesAny(filters, item)
	if not filters or #filters == 0 or not item then
		return false
	end
	for i = 1, #filters do
		if GlobalStorageSiK.NodeFilters.matchesOne(filters[i], item) then
			return true
		end
	end
	return false
end

--- Etiqueta legible de un filtro, para mostrarlo como "chip" en el editor.
---@param filter table
---@return string
function GlobalStorageSiK.NodeFilters.describe(filter)
	local T = GlobalStorageSiK.I18n and GlobalStorageSiK.I18n.text or getText
	if not filter then
		return "?"
	end
	if filter.type == "name" then
		local modeKey = "IGUI_GS_FilterModeContains"
		if filter.mode == "exact" then modeKey = "IGUI_GS_FilterModeExact"
		elseif filter.mode == "startsWith" then modeKey = "IGUI_GS_FilterModeStartsWith"
		elseif filter.mode == "endsWith" then modeKey = "IGUI_GS_FilterModeEndsWith" end
		return T("IGUI_GS_FilterDescName", T(modeKey), tostring(filter.value or ""))
	elseif filter.type == "weight" then
		local modeKey = "IGUI_GS_FilterModeEq"
		if filter.mode == "gt" then modeKey = "IGUI_GS_FilterModeGt"
		elseif filter.mode == "lt" then modeKey = "IGUI_GS_FilterModeLt"
		elseif filter.mode == "gte" then modeKey = "IGUI_GS_FilterModeGte"
		elseif filter.mode == "lte" then modeKey = "IGUI_GS_FilterModeLte"
		elseif filter.mode == "between" then modeKey = "IGUI_GS_FilterModeBetween" end
		if filter.mode == "between" then
			return T("IGUI_GS_FilterDescWeightBetween", tostring(filter.value or 0), tostring(filter.value2 or 0))
		end
		return T("IGUI_GS_FilterDescWeight", T(modeKey), tostring(filter.value or 0))
	elseif filter.type == "tag" then
		return T("IGUI_GS_FilterDescTag", tostring(filter.value or ""))
	elseif filter.type == "item" then
		local label = filter.itemDisplay or filter.itemType or "?"
		return T("IGUI_GS_FilterDescItem", label)
	end
	return "?"
end
