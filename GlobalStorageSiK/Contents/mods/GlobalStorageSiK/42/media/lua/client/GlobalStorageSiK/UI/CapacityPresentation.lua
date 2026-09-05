-- Global Storage SiK - one product adapter for every SiK.UI capacity meter.
-- The framework owns the progress widget; this module only converts the
-- authoritative capacity envelope into a stable, localized presentation.

require "GS_I18n"

GlobalStorageSiK = GlobalStorageSiK or {}
GlobalStorageSiK.UI = GlobalStorageSiK.UI or {}

local CapacityPresentation = {}
GlobalStorageSiK.UI.CapacityPresentation = CapacityPresentation

local function text(key, ...)
	local i18n = GlobalStorageSiK.I18n
	if i18n and type(i18n.text) == "function" then return i18n.text(key, ...) end
	return tostring(key or "")
end

local function numberText(value)
	local numeric = tonumber(value) or 0
	if math.abs(numeric - math.floor(numeric + 0.5)) < 0.001 then
		return tostring(math.floor(numeric + 0.5))
	end
	return string.format("%.1f", numeric)
end

function CapacityPresentation.fromState(capacity, options)
	local cap = type(capacity) == "table" and capacity or {}
	options = options or {}
	local used = tonumber(cap.usedWeight) or 0
	local total = tonumber(cap.effectiveCapacity) or tonumber(cap.totalCapacity)
		or tonumber(cap.capacity) or 0
	local percent = tonumber(cap.percent)
	if percent == nil and total > 0 then
		percent = math.min(100, math.floor((used / total) * 100 + 0.5))
	end
	percent = math.max(0, math.min(100, percent or 0))
	local status = tostring(cap.status or "ok")
	local tone = "success"
	if status == "warning" then tone = "warning"
	elseif status == "critical" or status == "full" then tone = "danger" end

	local label
	if total > 0 then
		label = text("IGUI_GS_CapacityUsage", numberText(used), numberText(total),
			tostring(math.floor(percent + 0.5)) .. "%")
	else
		label = text("IGUI_GS_WeightUsedOnly", numberText(used))
	end
	local count = tonumber(options.count)
	local containers = options.kind == "containers"
	if count == nil then count = tonumber(containers and cap.containerCount or cap.itemCount) end
	if count ~= nil then
		local key = containers and "IGUI_GS_CapacityContainerCount" or "IGUI_GS_CapacityItemCount"
		label = text(key, tostring(math.max(0, math.floor(count)))) .. " · " .. label
	end
	local personalBonus = tonumber(cap.personalBonus) or 0
	if personalBonus > 0 then
		label = label .. " " .. text("IGUI_GS_WeightPersonalBonus", numberText(personalBonus))
	end
	if cap.partialEstimate == true then
		-- A leading approximation mark is compact, locale-neutral and keeps the
		-- same capacity widget usable when unloaded nodes make the total partial.
		label = "~ " .. label
	end

	return {
		value = total > 0 and percent / 100 or 0,
		label = label,
		text = label,
		status = status,
		tone = tone,
		usedWeight = used,
		effectiveCapacity = total,
		percent = percent,
		personalBonus = personalBonus,
		partialEstimate = cap.partialEstimate == true,
	}
end

return CapacityPresentation
