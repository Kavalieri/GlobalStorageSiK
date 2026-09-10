-- Read-only catalogue labels. The engine remains the only owner of learning.
-- Codes/labels follow B42 RadioCom/ISRadioInteractions.lua. Its checkPlayer
-- cannot be used here: merely inspecting a tape must never teach its contents.
local Metadata = {}
-- Kahlua numbers are Double; RecordedMedia.getMediaDataFromIndex expects short.
-- Use the same category entries as vanilla's Change recording menu. The caller
-- owns this bounded cache for one catalogue refresh, never for a saved world.
function Metadata.resolve(catalog, index, category, cache)
	index = tonumber(index)
	if not catalog or not index or index ~= math.floor(index) or index < 0 or index > 32767
		or type(category) ~= "string" or category == "" then return nil end
	local entries = cache[category]
	if not entries then
		local list = catalog:getAllMediaForCategory(category)
		if not list or list:size() > 32768 then return nil end
		entries = {}
		for i = 0, list:size() - 1 do
			local media = list:get(i)
			entries[media:getIndexForLua()] = media
		end
		cache[category] = entries
	end
	return entries[index]
end
local skills = {
	SPR = "Sprinting", LFT = "Lightfooted", NIM = "Nimble", SNE = "Sneaking",
	BAA = "Axe", BUA = "Blunt", CRP = "Carpentry", COO = "Cooking",
	FRM = "Farming", DOC = "Doctor", ELC = "Electricity", MTL = "MetalWelding",
	FKN = "FlintKnapping", CRV = "Carving", AIM = "Aiming", REL = "Reloading",
	FIS = "Fishing", TRA = "Trapping", FOR = "Foraging", TAI = "Tailoring",
	MEC = "Mechanics", CMB = "Combat", SPE = "Spear", SBU = "SmallBlunt",
	LBA = "LongBlade", SBA = "SmallBlade", MAS = "Masonry", POT = "Pottery",
	BLA = "Blacksmith", GLA = "Glassmaking", HUS = "Husbandry",
	BUT = "Butchering", TRK = "Tracking",
}

local function read(media, translate)
	local result = { skills = {}, skillSet = {}, recipes = {}, complete = false }
	if not media or not media.getLineCount or not media.getLine then return result end
	local count = media:getLineCount()
	if type(count) ~= "number" or count < 0 or count > 4096 or count ~= math.floor(count) then
		return result
	end
	local recipes = {}
	for index = 0, count - 1 do
		local line = media:getLine(index)
		local codes = line and line.getCodes and line:getCodes()
		if type(codes) == "string" then
			-- Same comma token boundaries as vanilla's split; no case folding or
			-- invented interpretation of unknown mod codes.
			for token in string.gmatch(codes, "[^,]+") do
				if #token > 4 then
					local code, op = string.sub(token, 1, 3), string.sub(token, 4, 4)
					if code == "RCP" then
						local name = string.sub(token, 5)
						if not recipes[name] then
							recipes[name] = true
							result.recipes[#result.recipes + 1] = name
						end
					elseif skills[code] then
						local amount = tonumber(string.sub(token, 5))
						if amount and op == "-" then amount = -amount end
						if amount and amount > 0 and not result.skillSet[code] then
							local key = "IGUI_perks_" .. skills[code]
							local label = translate and translate(key) or key
							result.skillSet[code] = true
							result.skills[#result.skills + 1] = { code = code, key = key, label = label or key }
						end
					end
				end
			end
		end
	end
	table.sort(result.skills, function(a, b)
		if a.label == b.label then return a.code < b.code end
		return a.label < b.label
	end)
	table.sort(result.recipes)
	result.complete = true
	return result
end

function Metadata.read(media, translate)
	local ok, result = pcall(read, media, translate)
	if ok then return result end
	-- Discard any partial scan if a modded/native descriptor fails mid-read.
	return { skills = {}, skillSet = {}, recipes = {}, complete = false }
end

return Metadata
