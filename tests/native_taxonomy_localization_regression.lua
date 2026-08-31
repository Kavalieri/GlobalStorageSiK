-- Registro -> traducciones: cada segmento L1/L2/L3 registrado tiene una clave
-- IGUI_GS_NativeTax_ en todos los idiomas que publica el Core.
-- Run: lua51.exe tests/native_taxonomy_localization_regression.lua

GlobalStorageSiK = {}
dofile("GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/GS_NativeTaxonomyRegistry.lua")

local ROOT = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/Translate/"
local LANGUAGES = { "EN", "ES", "FR", "DE", "IT", "PTBR", "PL", "RU", "CN", "CH" }

local function readAll(path)
	local file = assert(io.open(path, "rb"), "missing translation file: " .. path)
	local text = file:read("*a")
	file:close()
	return text
end

local tokens = {}
local function include(token)
	if token and token ~= "" then tokens[token] = true end
end
for l1, groups in pairs(GlobalStorageSiK.NativeTaxonomyRegistry.getTree()) do
	include(l1)
	for l2, leaves in pairs(groups) do
		include(l2)
		for i = 1, #leaves do include(leaves[i]) end
	end
end

local missing = {}
for i = 1, #LANGUAGES do
	local language = LANGUAGES[i]
	local text = readAll(ROOT .. language .. "/IG_UI.json")
	for token in pairs(tokens) do
		local key = "\"IGUI_GS_NativeTax_" .. token .. "\""
		if not text:find(key, 1, true) then
			missing[#missing + 1] = language .. ":" .. token
		end
	end
end

if #missing > 0 then
	table.sort(missing)
	error("missing native taxonomy translations: " .. table.concat(missing, ", "))
end

-- Regresion observada: la ruta de muebles registrada caia al humanize() y
-- exponia "Furnishing > Storage" en cliente ES. Estas etiquetas forman parte
-- del contrato visible de las tres superficies que consumen la fachada.
local spanish = readAll(ROOT .. "ES/IG_UI.json")
for key, value in pairs({
	IGUI_GS_NativeTax_home_leisure_collection = "Hogar, ocio y colección",
	IGUI_GS_NativeTax_furnishing = "Mobiliario",
	IGUI_GS_NativeTax_storage = "Almacenamiento",
}) do
	local expected = '"' .. key .. '": "' .. value .. '"'
	assert(spanish:find(expected, 1, true), "invalid ES native taxonomy label: " .. key)
end

print("native_taxonomy_localization_regression: OK")
