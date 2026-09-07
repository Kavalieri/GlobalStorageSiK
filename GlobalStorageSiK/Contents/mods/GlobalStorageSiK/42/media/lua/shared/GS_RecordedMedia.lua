--[[
	GlobalStorageSiK - contrato compartido de RecordedMedia
	Una sola interpretacion de los codigos vanilla para taxonomia y tooltip.
]]

GlobalStorageSiK = GlobalStorageSiK or {}
GlobalStorageSiK.RecordedMedia = GlobalStorageSiK.RecordedMedia or {}

local RecordedMedia = GlobalStorageSiK.RecordedMedia

local function normalizedIndex(value)
	local index = tonumber(value)
	if index == nil or index < 0 or index > 32767 then return nil end
	return math.floor(index)
end

local function scriptMediaCategory(fullType)
	if type(fullType) ~= "string" or fullType == "" or not getScriptManager then return nil end
	local ok, script = pcall(function()
		local manager = getScriptManager()
		return manager and manager.getItem and manager:getItem(fullType) or nil
	end)
	if not ok or not script or not script.getRecordedMediaCat then return nil end
	local okCategory, category = pcall(function() return script:getRecordedMediaCat() end)
	if not okCategory or category == nil or tostring(category) == "" then return nil end
	return tostring(category)
end

local function mediaIndex(data)
	if not data or not data.getIndexForLua then return nil end
	local ok, value = pcall(function() return data:getIndexForLua() end)
	return ok and normalizedIndex(value) or nil
end

local function mediaFromList(list, wanted)
	if not list or not list.size or not list.get then return nil end
	local okSize, size = pcall(function() return list:size() end)
	if not okSize or type(size) ~= "number" then return nil end
	for i = 0, math.max(0, math.floor(size) - 1) do
		local okData, data = pcall(function() return list:get(i) end)
		if okData and data and mediaIndex(data) == wanted then return data end
	end
	return nil
end

--- Resolves the exact vanilla MediaData entry without invoking the Java short
--- overload of RecordedMedia.getMediaDataFromIndex from Kahlua. Vanilla exposes
--- the same catalogue as a category list whose entries provide getIndexForLua.
---@param value number
---@param fullType string|nil
---@return MediaData|nil
function RecordedMedia.dataFromIndex(value, fullType)
	local wanted = normalizedIndex(value)
	if wanted == nil or not getZomboidRadio then return nil end
	local okCatalogue, catalogue = pcall(function()
		local radio = getZomboidRadio()
		return radio and radio.getRecordedMedia and radio:getRecordedMedia() or nil
	end)
	if not okCatalogue or not catalogue or not catalogue.getAllMediaForCategory then return nil end
	local category = scriptMediaCategory(fullType)
	if category then
		local okList, list = pcall(function() return catalogue:getAllMediaForCategory(category) end)
		local exact = okList and mediaFromList(list, wanted) or nil
		if exact then return exact end
	end
	-- Compatibility for persisted rows created before the carrier fullType was
	-- retained correctly, and for third-party carriers that expose a mediaIndex
	-- but no ScriptItem category. The index is the canonical vanilla identity;
	-- scan the finite category catalogue without ever coercing Lua numbers to
	-- Java's short overload.
	if not catalogue.getCategories then return nil end
	local okCategories, categories = pcall(function() return catalogue:getCategories() end)
	if not okCategories or not categories or not categories.size or not categories.get then return nil end
	local okSize, size = pcall(function() return categories:size() end)
	if not okSize or type(size) ~= "number" then return nil end
	for i = 0, math.max(0, math.floor(size) - 1) do
		local okCategory, fallbackCategory = pcall(function() return categories:get(i) end)
		if okCategory and fallbackCategory and tostring(fallbackCategory) ~= tostring(category or "") then
			local okList, list = pcall(function()
				return catalogue:getAllMediaForCategory(tostring(fallbackCategory))
			end)
			local exact = okList and mediaFromList(list, wanted) or nil
			if exact then return exact end
		end
	end
	return nil
end

---@param value number
---@param fullType string|nil
---@return string|nil
function RecordedMedia.titleFromIndex(value, fullType)
	local data = RecordedMedia.dataFromIndex(value, fullType)
	if not data or not data.getTranslatedItemDisplayName then return nil end
	local ok, title = pcall(function() return data:getTranslatedItemDisplayName() end)
	if not ok or type(title) ~= "string" or title == "" then return nil end
	return title
end

RecordedMedia.SKILL_CODE_TO_PERK_KEY = {
	SPR = "IGUI_perks_Sprinting", LFT = "IGUI_perks_Lightfooted", NIM = "IGUI_perks_Nimble",
	SNE = "IGUI_perks_Sneaking", BAA = "IGUI_perks_Axe", BUA = "IGUI_perks_Blunt",
	CRP = "IGUI_perks_Carpentry", COO = "IGUI_perks_Cooking", FRM = "IGUI_perks_Farming",
	DOC = "IGUI_perks_Doctor", ELC = "IGUI_perks_Electricity", MTL = "IGUI_perks_MetalWelding",
	FKN = "IGUI_perks_FlintKnapping", CRV = "IGUI_perks_Carving", AIM = "IGUI_perks_Aiming",
	REL = "IGUI_perks_Reloading", FIS = "IGUI_perks_Fishing", TRA = "IGUI_perks_Trapping",
	FOR = "IGUI_perks_Foraging", TAI = "IGUI_perks_Tailoring", MEC = "IGUI_perks_Mechanics",
	CMB = "IGUI_perks_Combat", SPE = "IGUI_perks_Spear", SBU = "IGUI_perks_SmallBlunt",
	LBA = "IGUI_perks_LongBlade", SBA = "IGUI_perks_SmallBlade", MAS = "IGUI_perks_Masonry",
	POT = "IGUI_perks_Pottery", BLA = "IGUI_perks_Blacksmith", GLA = "IGUI_perks_Glassmaking",
	HUS = "IGUI_perks_Husbandry", BUT = "IGUI_perks_Butchering", TRK = "IGUI_perks_Tracking",
}

---@param codes string[]|nil
---@return string[]|nil perkKeys; nil significa metadatos no resueltos
function RecordedMedia.perkKeysFromCodes(codes)
	if type(codes) ~= "table" then return nil end
	local result, seen = {}, {}
	for i = 1, math.min(#codes, 64) do
		for segment in tostring(codes[i]):gmatch("[^,]+") do
			local trigram = segment:match("^%u+")
			local key = trigram and RecordedMedia.SKILL_CODE_TO_PERK_KEY[trigram]
			if key and not seen[key] then
				seen[key] = true
				result[#result + 1] = key
			end
		end
	end
	return result
end

---@param mediaIndex number|nil
---@param codes string[]|nil
---@return table|nil
function RecordedMedia.nativePath(mediaIndex, codes)
	if tonumber(mediaIndex) == nil or type(codes) ~= "table" then return nil end
	local perkKeys = RecordedMedia.perkKeysFromCodes(codes)
	return {
		l1 = "knowledge_media",
		l2 = "recorded_media",
		l3 = perkKeys and #perkKeys > 0 and "with_learning" or "leisure",
	}
end
