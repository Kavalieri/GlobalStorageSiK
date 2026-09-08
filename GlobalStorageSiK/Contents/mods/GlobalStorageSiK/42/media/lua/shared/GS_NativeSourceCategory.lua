-- Preserve script evidence across our DisplayCategory publication and epochs.
-- Bounded by catalog fullTypes; strings only, no persistent Java references.
GlobalStorageSiK.NativeSourceCategory = GlobalStorageSiK.NativeSourceCategory or {}
local Source = GlobalStorageSiK.NativeSourceCategory
local originals = {}

local function own(value)
	return type(value) == "string" and value:sub(1, 6) == "GSSiK_"
end

function Source.capture(fullType, category)
	if type(fullType) ~= "string" or fullType == "" or own(category) then return end
	if category == nil or type(category) == "string" then
		originals[fullType] = category or ""
	end
end

function Source.get(scriptItem)
	if not scriptItem or not scriptItem.getDisplayCategory then return nil end
	local ok, category = pcall(function() return scriptItem:getDisplayCategory() end)
	if not ok or (category ~= nil and type(category) ~= "string") then return nil end
	if not own(category) then return category end
	local named, fullType = pcall(function() return scriptItem:getFullName() end)
	if named and type(fullType) == "string" then return originals[fullType] end
	return nil -- Never recycle an output category as source evidence.
end

return Source
