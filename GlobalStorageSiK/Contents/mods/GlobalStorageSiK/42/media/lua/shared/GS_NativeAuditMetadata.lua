-- Diagnostic snapshots only: no live item references or classification changes.
require "GS_NativeClassifierUtils"
require "GS_NativeWorldOverrides"
GlobalStorageSiK.NativeAuditMetadata = {}
local Metadata = GlobalStorageSiK.NativeAuditMetadata
local safeCall = GlobalStorageSiK.NativeClassifierUtils.safeCall

local function rawText(si, method)
	local value = safeCall(function() return si and si[method] and si[method](si) end)
	return value ~= nil and tostring(value) or ""
end

function Metadata.collect(si)
	local row = {
		censusSchemaVersion = 2, scriptModule = rawText(si, "getModuleName"),
		originModId = "", originStatus = "unknown",
		sourceDisplayCategory = GlobalStorageSiK.NativeSourceCategory.get(si) or "",
		scriptType = rawText(si, "getItemType"), scriptTags = "", scriptTagsStatus = "unavailable",
	}
	local tags = safeCall(function() return si and si.getTags and si:getTags() end)
	if not tags then return row end
	local values = {}
	local ok = pcall(function()
		local iterator = tags:iterator()
		row.scriptTagsStatus = "complete"
		while iterator:hasNext() do
			if #values >= 128 then row.scriptTagsStatus = "truncated"; break end
			local value = tostring(iterator:next())
			if #value > 256 then
				-- Do not cut a UTF-8 character or disguise an incomplete tag.
				row.scriptTagsStatus = "truncated"
				break
			end
			values[#values + 1] = value
		end
	end)
	if not ok then row.scriptTagsStatus = "error" end
	table.sort(values)
	row.scriptTags = table.concat(values, "|")
	return row
end

local function samePath(a, b)
	return a and b and a.l1 == b.l1 and a.l2 == b.l2 and a.l3 == b.l3
end

function Metadata.decorate(row, si, result, entry)
	local choice = result and result.primaryPath or {}
	local default = result and (result.defaultPrimaryPath or result.primaryPath) or {}
	row.defaultL1, row.defaultL2, row.defaultL3 = default.l1 or "", default.l2 or "", default.l3 or ""
	row.choiceL1, row.choiceL2, row.choiceL3 = choice.l1 or "", choice.l2 or "", choice.l3 or ""
	row.worldOverrideStatus = "none"
	if type(entry) ~= "table" then return end
	local world = GlobalStorageSiK.NativeWorldOverrides
	local selected = world.decodePath(entry.nativePath)
	if not si then row.worldOverrideStatus = "inactive_source_missing"
	elseif not selected then row.worldOverrideStatus = "inactive_choice_invalid"
	elseif not result or result.classificationScope ~= "world" then row.worldOverrideStatus = "inactive_not_applied"
	else
		row.worldOverrideStatus = "active"
		local previous = type(entry.previous) == "table" and world.decodePath(entry.previous.defaultNativePath)
		if previous and default.l1 and not samePath(previous, default) then
			row.worldOverrideStatus = "review_default_changed"
		end
	end
	-- Preserve an inactive requested path for diagnosis as well as the effective
	-- path above; otherwise a removed mod's override would disappear from export.
	row.overrideNativePath = type(entry.nativePath) == "string" and entry.nativePath or ""
end

return Metadata
