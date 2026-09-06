-- Snapshot-only presentation. Never invent state by calling DoTooltip on a
-- freshly constructed InventoryItem. This module neither requests nor mutates.
require "GS_I18n"

local Presentation = {}
GlobalStorageSiK.RemoteTooltipPresentation = Presentation
local function text(key, ...) return GlobalStorageSiK.I18n.text(key, ...) end
local function finite(value)
	local number = tonumber(value)
	if number and number == number and number ~= math.huge and number ~= -math.huge then return number end
end
local function numberText(value)
	return (string.format("%.2f", value):gsub("0+$", ""):gsub("%.$", ""))
end

function Presentation.fluidQuantity(row, aggregate)
	local amount = finite(aggregate and row.totalFluidAmount or row.fluidAmount)
	local capacity = finite(aggregate and row.totalFluidCapacity or row.fluidCapacity)
	if not amount or not capacity or amount < 0 or capacity <= 0 then return nil end
	-- Never round a partially filled container up to 100%.
	local percent = math.floor(amount / capacity * 100)
	return numberText(amount) .. " / " .. numberText(capacity) .. " L · " .. tostring(percent) .. "%"
end

local function fluidName(state, amount)
	if amount == 0 then return getText("Fluid_Empty") end
	if state.mixture == true then return getText("Fluid_Mixture") end
	local raw = tostring(state.rawType or state.canonicalType or "")
	if raw == "" then return getText("Fluid_Unknown") end
	local token = raw:match("[^:]+$") or raw
	local key = "Fluid_Name_" .. token
	local translated = getText(key)
	return translated ~= key and translated or raw
end

function Presentation.blocks(context)
	local row = context.row or {}
	local exact = row._gsRowKind == "child"
	local detail = type(context.detail) == "table" and context.detail or nil
	local source = exact and detail and detail.ok == true and detail or row
	local title = source.displayName or row.displayName or row.fullType or ""
	local lines = { tostring(title) }
	if exact and not (detail and detail.ok == true) then
		lines[#lines + 1] = text(context.loading and "IGUI_GS_RemoteDetailLoading" or "IGUI_GS_RemoteDetailUnavailable")
		return { { lines = lines, color = { 0.9, 0.9, 0.9, 1 } } }
	end
	if not exact then lines[#lines + 1] = text("IGUI_GS_RemoteGroupTotal", math.max(0, finite(row.count) or 0)) end
	local weight = finite(exact and source.weight or row.totalWeight)
	if weight then lines[#lines + 1] = getText("Tooltip_item_Weight") .. ": " .. numberText(weight) end
	if exact and finite(source.condition) and finite(source.conditionMax) then
		lines[#lines + 1] = getText("Tooltip_weapon_Condition") .. ": " .. tostring(source.condition) .. " / " .. tostring(source.conditionMax)
	end
	local food = GlobalStorageSiK.I18n.foodStateLabel(source)
	if food ~= "" then lines[#lines + 1] = food end
	local quantity = Presentation.fluidQuantity(source, not exact)
	local fluid = type(source.fluidState) == "table" and source.fluidState or nil
	if exact and fluid then
		lines[#lines + 1] = getText("Fluid_Fluids") .. ": " .. fluidName(fluid, finite(source.fluidAmount))
		if fluid.tainted == true then lines[#lines + 1] = getText("Fluid_Tainted") end
		if fluid.poisonous == true then lines[#lines + 1] = getText("Tooltip_food_Poisonous") end
	end
	if quantity then lines[#lines + 1] = getText("Fluid_Amount") .. ": " .. quantity end
	return { { lines = lines, color = { 0.9, 0.9, 0.9, 1 } } }
end

return Presentation
