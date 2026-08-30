-- Clasificación dinámica de contenedores de fluido B42.
-- La forma vacía se conserva como Contenedores > Líquidos. Cualquier cantidad
-- real mayor que cero adopta la ruta de su contenido; litros y capacidad son
-- estado de la unidad, nunca identidad taxonómica.

GlobalStorageSiK.FluidTaxonomy = GlobalStorageSiK.FluidTaxonomy or {}
local FluidTaxonomy = GlobalStorageSiK.FluidTaxonomy

local function safeCall(fn)
	local ok, value = pcall(fn)
	if ok then return value end
	return nil
end

local function fluidContainer(item)
	if not item or not item.getFluidContainer then return nil end
	return safeCall(function() return item:getFluidContainer() end)
end

local function hasCategory(fluid, category)
	return fluid and category and fluid.isCategory
		and safeCall(function() return fluid:isCategory(category) end) == true
end

local function normalizeFluidId(value)
	value = string.lower(tostring(value or ""))
	value = value:gsub("[^a-z0-9_:.-]+", "_")
	value = value:gsub("^_+", ""):gsub("_+$", "")
	return value ~= "" and value or nil
end

local function kindToken(value)
	value = normalizeFluidId(value)
	if not value then return nil end
	value = value:gsub("^.-:", ""):gsub("[^a-z0-9_]+", "_")
	return value ~= "" and value or nil
end

local function rounded(value, places)
	if type(value) ~= "number" then return nil end
	local scale = 10 ^ (places or 4)
	return math.floor(value * scale + 0.5) / scale
end

local function fluidShape(item, container, capacity)
	local fullType = item and item.getFullType
		and safeCall(function() return item:getFullType() end) or ""
	local containerName = container and container.getContainerName
		and safeCall(function() return container:getContainerName() end) or ""
	local ft = string.lower(tostring(fullType or ""))
	local cn = string.lower(tostring(containerName or ""))
	local family = nil
	if ft == "base.bag_hydrationbackpack" or ft == "base.bag_hydrationbackpack_camo" then
		family = "hydration_backpack"
	elseif ft == "base.petrolcan" or ft == "base.jerrycan"
		or cn == "gascan" or cn == "jerrycan" then
		family = "fuel_can"
	elseif ft == "base.waterdispenserbottle" then
		family = "water_dispenser_bottle"
	elseif cn:find("bottle", 1, true) ~= nil or ft:find("bottle", 1, true) ~= nil then
		family = "bottle"
	elseif cn ~= "" then
		family = cn:gsub("[^a-z0-9_]+", "_")
	else
		family = "fluid_container"
	end
	local shapeKey = table.concat({ tostring(fullType or ""), tostring(containerName or ""),
		tostring(rounded(capacity, 4) or "") }, "\31")
	return family, shapeKey, tostring(containerName or "")
end

local function mixtureComposition(container, totalAmount)
	if not container or not Fluid or not Fluid.getAllFluids then return nil, false end
	local all = safeCall(function() return Fluid.getAllFluids() end)
	if not all or not all.size or not all.get or type(totalAmount) ~= "number" or totalAmount <= 0 then
		return nil, false
	end
	local tuples = {}
	local size = tonumber(safeCall(function() return all:size() end)) or 0
	for i = 0, size - 1 do
		local fluid = safeCall(function() return all:get(i) end)
		local amount = fluid and container.getSpecificFluidAmount
			and safeCall(function() return container:getSpecificFluidAmount(fluid) end) or nil
		if type(amount) == "number" and amount > 0.000001 then
			local rawId = fluid.getFluidTypeString
				and safeCall(function() return fluid:getFluidTypeString() end) or nil
			local id = normalizeFluidId(rawId)
			if id then tuples[#tuples + 1] = id .. "=" .. tostring(rounded(amount / totalAmount, 6)) end
		end
	end
	if #tuples == 0 then return nil, false end
	table.sort(tuples)
	return table.concat(tuples, ","), true
end

local function readFluid(item)
	local fluid = fluidContainer(item)
	if not fluid then return nil end
	local amount = fluid.getAmount and safeCall(function() return fluid:getAmount() end) or nil
	local capacity = fluid.getCapacity and safeCall(function() return fluid:getCapacity() end) or nil
	local mixture = fluid.isMixture and safeCall(function() return fluid:isMixture() end) == true
	local empty = fluid.isEmpty and safeCall(function() return fluid:isEmpty() end) or nil
	-- La cantidad real prevalece sobre un flag/categoría auxiliar: cualquier
	-- valor positivo representa contenido, incluso en capacidades o colores de
	-- envase que B42 no asocie correctamente a FluidCategory.
	if type(amount) == "number" then empty = amount <= 0 end
	local primary = fluid.getPrimaryFluid and safeCall(function() return fluid:getPrimaryFluid() end) or nil
	local rawType = primary and primary.getFluidTypeString
		and safeCall(function() return primary:getFluidTypeString() end) or nil
	local primaryAmount = fluid.getPrimaryFluidAmount
		and safeCall(function() return fluid:getPrimaryFluidAmount() end) or nil
	local tainted = fluid.isTainted and safeCall(function() return fluid:isTainted() end) == true
	local poisonous = fluid.isPoisonous and safeCall(function() return fluid:isPoisonous() end) == true
	local poisonRatio = fluid.getPoisonRatio
		and safeCall(function() return fluid:getPoisonRatio() end) or nil
	local composition, compositionExact = nil, not mixture
	if mixture then composition, compositionExact = mixtureComposition(fluid, amount) end
	local shapeFamily, shapeKey, containerName = fluidShape(item, fluid, capacity)
	return {
		fluid = fluid, amount = amount, capacity = capacity, empty = empty,
		mixture = mixture, rawType = rawType, canonicalType = normalizeFluidId(rawType),
		kindToken = kindToken(rawType), primaryAmount = primaryAmount,
		tainted = tainted, poisonous = poisonous, poisonRatio = rounded(poisonRatio, 4),
		composition = composition, compositionExact = compositionExact,
		shapeFamily = shapeFamily, shapeKey = shapeKey, containerName = containerName,
		productFamilyKey = shapeFamily,
	}
end

local function typeContains(value, token)
	return value and value:find(token, 1, true) ~= nil
end

local function pathForContent(data)
	local kind = data.kindToken
	-- El tipo Java real es la señal primaria. FluidCategory se usa solo como
	-- evidencia adicional/fallback porque TEST confirmó variantes de bidón que
	-- no coincidían de forma uniforme por categoría.
	if typeContains(kind, "petrol") or typeContains(kind, "gasoline")
		or typeContains(kind, "diesel") or typeContains(kind, "kerosene")
		or typeContains(kind, "fuel") then
		return { l1 = "vehicles", l2 = "consumable", l3 = "fuel" }
	end
	if typeContains(kind, "water") then
		return { l1 = "food_drink", l2 = "non_perishable", l3 = "water" }
	end
	if typeContains(kind, "beer") or typeContains(kind, "wine")
		or typeContains(kind, "soda") or typeContains(kind, "juice")
		or typeContains(kind, "milk") or typeContains(kind, "coffee")
		or typeContains(kind, "tea") or typeContains(kind, "beverage") then
		return { l1 = "food_drink", l2 = "non_perishable", l3 = "beverage" }
	end
	if FluidCategory and hasCategory(data.fluid, FluidCategory.Fuel) then
		return { l1 = "vehicles", l2 = "consumable", l3 = "fuel" }
	end
	if FluidCategory and hasCategory(data.fluid, FluidCategory.Water) then
		return { l1 = "food_drink", l2 = "non_perishable", l3 = "water" }
	end
	if FluidCategory and hasCategory(data.fluid, FluidCategory.Beverage) then
		return { l1 = "food_drink", l2 = "non_perishable", l3 = "beverage" }
	end
	return { l1 = "containers", l2 = "liquid", l3 = "other_fluid" }
end

function FluidTaxonomy.canonicalType(item)
	local data = readFluid(item)
	return data and data.canonicalType or nil
end

local function hazardSignature(data)
	return string.format("tainted=%d;poisonous=%d;poison=%s",
		data.tainted and 1 or 0, data.poisonous and 1 or 0,
		tostring(data.poisonRatio or ""))
end

local function contentSignature(data)
	local fluidId = data.canonicalType or "other_fluid"
	if data.mixture then
		if data.compositionExact and data.composition then
			return "mixture:components=" .. data.composition .. ";" .. hazardSignature(data)
		end
		local primaryRatio = nil
		if type(data.primaryAmount) == "number" and type(data.amount) == "number" and data.amount > 0 then
			primaryRatio = rounded(data.primaryAmount / data.amount, 4)
		end
		return "mixture:composition=unresolved;primary=" .. fluidId .. ";ratio=" .. tostring(primaryRatio or "")
			.. ";" .. hazardSignature(data)
	end
	return "fluid:" .. fluidId .. ";" .. hazardSignature(data)
end

local function resolveFromData(data)
	if not data then return nil, nil end
	if data.empty == true then
		return { l1 = "containers", l2 = "liquid", l3 = "empty" }, "empty"
	end
	if data.empty ~= false then return nil, "unknown" end
	if data.mixture then
		return { l1 = "containers", l2 = "liquid", l3 = "mixture" }, contentSignature(data)
	end
	return pathForContent(data), contentSignature(data)
end

local function detailFromData(data)
	if not data then return nil end
	return {
		canonicalType = data.canonicalType,
		amount = data.amount,
		capacity = data.capacity,
		empty = data.empty,
		mixture = data.mixture,
		primaryAmount = data.primaryAmount,
		tainted = data.tainted,
		poisonous = data.poisonous,
		poisonRatio = data.poisonRatio,
		composition = data.composition,
		compositionExact = data.compositionExact,
		shapeFamily = data.shapeFamily,
		productFamilyKey = data.productFamilyKey,
		shapeKey = data.shapeKey,
		containerName = data.containerName,
	}
end

-- Una sola inspección por unidad durante el snapshot. Antes cada helper volvía
-- a cruzar Java y, para mezclas, recorría el catálogo completo de fluidos hasta
-- cinco veces. El resultado es plano/serializable y puede reutilizarse en la
-- fila, tooltip y detalle por itemId sin mantener referencias Java vivas.
function FluidTaxonomy.inspect(item)
	local data = readFluid(item)
	if not data then return nil end
	local path, signature = resolveFromData(data)
	local percent = nil
	if type(data.amount) == "number" and type(data.capacity) == "number" and data.capacity > 0 then
		percent = math.max(0, math.min(100, math.floor((data.amount / data.capacity) * 100 + 0.5)))
	end
	local stateKey = data.empty == true and "empty"
		or (data.empty ~= false and "unknown" or contentSignature(data))
	return {
		path = path, signature = signature, stateKey = stateKey, fillPercent = percent,
		amount = data.amount, capacity = data.capacity, canonicalType = data.canonicalType,
		detail = detailFromData(data),
	}
end

function FluidTaxonomy.stateKey(item)
	local data = readFluid(item)
	if not data then return nil end
	if data.empty == true then return "empty" end
	if data.empty ~= false then return "unknown" end
	return contentSignature(data)
end

function FluidTaxonomy.detail(item)
	return detailFromData(readFluid(item))
end

function FluidTaxonomy.amountAndCapacity(item)
	local data = readFluid(item)
	return data and data.amount or nil, data and data.capacity or nil
end

function FluidTaxonomy.fillPercent(item)
	local amount, capacity = FluidTaxonomy.amountAndCapacity(item)
	if type(amount) ~= "number" or type(capacity) ~= "number" or capacity <= 0 then return nil end
	return math.max(0, math.min(100, math.floor((amount / capacity) * 100 + 0.5)))
end

---@param item InventoryItem|nil
---@return table|nil nativePath
---@return string|nil signature estable, sin cantidad/capacidad
function FluidTaxonomy.resolve(item)
	return resolveFromData(readFluid(item))
end
