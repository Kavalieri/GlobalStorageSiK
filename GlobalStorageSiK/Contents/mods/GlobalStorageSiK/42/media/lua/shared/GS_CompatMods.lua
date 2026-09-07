--[[
	GlobalStorageSiK - Compatibilidad opcional no taxonómica

	Este módulo no participa en clasificación, filtros, reglas ni routing de
	categorías. Conserva exclusivamente la integración de etiquetas de
	contenedor, que es un contrato distinto de la taxonomía.
]]

GlobalStorageSiK.CompatMods = GlobalStorageSiK.CompatMods or {}

local function safeGet(fn)
	local ok, value = pcall(fn)
	return ok and value or nil
end

function GlobalStorageSiK.CompatMods.hasCustomizableContainers()
	return rawget(_G, "CCLabelRegistry") ~= nil
end

function GlobalStorageSiK.CompatMods.getContainerLabelText(entry, player)
	if not GlobalStorageSiK.CompatMods.hasCustomizableContainers() or not entry or not player then return nil end
	local worldObject = safeGet(function() return GlobalStorageSiK.Network.findWorldObject(entry) end)
	local registry = rawget(_G, "CCLabelRegistry")
	local key = registry and worldObject and safeGet(function() return registry.getWorldObjectKey(worldObject) end) or nil
	if not key then return nil end
	local personal = safeGet(function() return player:getModData()["CCContainerPersonalLabels"] end)
	local personalEntry = personal and personal[key]
	if type(personalEntry) == "table" and type(personalEntry.tagText) == "string" and personalEntry.tagText ~= "" then return personalEntry.tagText end
	local factionName = safeGet(function() return registry.getFactionName(player) end)
	local store = factionName and safeGet(function() return ModData.getOrCreate(registry.FACTION_LABELS_KEY) end) or nil
	local factionEntry = store and store.tags and store.tags[factionName] and store.tags[factionName][key]
	return type(factionEntry) == "table" and type(factionEntry.tagText) == "string" and factionEntry.tagText ~= "" and factionEntry.tagText or nil
end

function GlobalStorageSiK.CompatMods.pushContainerLabelText(entry, player, tagText)
	if not GlobalStorageSiK.CompatMods.hasCustomizableContainers() or not entry or not player then return false end
	tagText = type(tagText) == "string" and tagText:sub(1, 28) or ""
	if tagText == "" then return false end
	local worldObject = safeGet(function() return GlobalStorageSiK.Network.findWorldObject(entry) end)
	local registry = rawget(_G, "CCLabelRegistry")
	local key = registry and worldObject and safeGet(function() return registry.getWorldObjectKey(worldObject) end) or nil
	local modData = safeGet(function() return player:getModData() end)
	local bucket = modData and modData["CCContainerPersonalLabels"]
	local existing = bucket and bucket[key]
	if not key or type(existing) ~= "table" or type(existing.tagText) ~= "string" then return false end
	if existing.tagText == tagText then return true end
	existing.tagText = tagText
	bucket[key] = existing
	safeGet(function() player:transmitModData() end)
	return true
end
