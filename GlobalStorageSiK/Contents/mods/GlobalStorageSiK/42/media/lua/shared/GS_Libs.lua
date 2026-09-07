--[[
	GlobalStorageSiK - Carga segura de librerías externas
	Autor: SiK
	Fecha: 2025-06-23
	Descripción: Detección de integraciones funcionales de crafteo, construcción y cocina.
]]

GlobalStorageSiK.Libs = GlobalStorageSiK.Libs or {}

--- BUG REAL DE ARQUITECTURA cerrado (2026-08-26, revision tecnica de
--- Desarrollo tras el banco CJK de 4 vidas en DEV15 - "los valores de DEV15
--- son en realidad compatibles con longitudes UTF-16"): TODA cadena Lua en
--- Kahlua/PZ esta respaldada por un java.lang.String, no por un buffer de
--- bytes UTF-8 - `#text` cuenta UNIDADES UTF-16 (chars de Java), y
--- `string.byte(text, i)` devuelve directamente el valor de esa unidad de 16
--- bits (para un caracter del BMP, ES el propio punto de codigo Unicode; un
--- caracter fuera del BMP como 𠮷 ocupa DOS unidades, un par subrogado alto+
--- bajo). La primera version de este fichero (DEV15) trataba ese valor como
--- un byte UTF-8 0-255 y lo hacia pasar por un decodificador multibyte -
--- para "风 。" (3 unidades: 风=U+98CE, espacio=U+0020, 。=U+3002) el
--- resultado eran los 3 valores combinados como si fueran continuacion de
--- una sola secuencia de 3 bytes UTF-8, dando el codepoint falso U+E802
--- (verificado a mano: coincide exactamente con la aritmetica del bug).
--- Nunca asumir aqui ninguna API Java directa (String.codePointAt() etc.) -
--- Kahlua no expone metodos Java arbitrarios sobre valores string, solo la
--- libreria string de Lua actuando sobre las unidades UTF-16 subyacentes.
---@param text string
---@param maxChars number|nil tope de caracteres a decodificar (por defecto 16)
---@return number[] codepoints puntos de codigo Unicode reales (ya con pares subrogados combinados)
function GlobalStorageSiK.Libs.unicodeCodepoints(text, maxChars)
	text = tostring(text or "")
	maxChars = tonumber(maxChars) or 16
	local codepoints = {}
	local i = 1
	local len = #text
	while i <= len and #codepoints < maxChars do
		local unit = string.byte(text, i)
		if unit >= 0xD800 and unit <= 0xDBFF then
			local low = string.byte(text, i + 1)
			if low and low >= 0xDC00 and low <= 0xDFFF then
				codepoints[#codepoints + 1] = 0x10000 + (unit - 0xD800) * 0x400 + (low - 0xDC00)
				i = i + 2
			else
				-- Alto subrogado huerfano (cadena truncada a mitad de par) -
				-- se vuelca tal cual en vez de abortar el resto del texto.
				codepoints[#codepoints + 1] = unit
				i = i + 1
			end
		else
			codepoints[#codepoints + 1] = unit
			i = i + 1
		end
	end
	return codepoints
end

--- true si la unidad UTF-16 en la posicion `i` (1-indexado) es la mitad baja
--- de un par subrogado - usado para no partir un caracter fuera del BMP al
--- truncar/trocear texto (`i` NUNCA debe quedar justo despues de un alto
--- subrogado sin su bajo correspondiente).
---@param text string
---@param i number
---@return boolean
function GlobalStorageSiK.Libs.isLowSurrogateAt(text, i)
	local unit = string.byte(text, i)
	return unit ~= nil and unit >= 0xDC00 and unit <= 0xDFFF
end

--- Devuelve el PRIMER caracter Unicode completo de una cadena (1 unidad, o 2
--- si empieza por un par subrogado) - pedido explicito (2026-08-26, revision
--- tecnica de Desarrollo tras dev16): `string.sub(text, 1, 1)` corta solo la
--- primera unidad UTF-16, partiendo por la mitad cualquier nombre que
--- empiece por un caracter fuera del BMP (p.ej. `𠮷`) y dejando un subrogado
--- huerfano (glifo roto) - usar esta funcion en cualquier sitio que necesite
--- "la inicial" de un nombre para un icono/avatar.
---@param text string
---@return string
function GlobalStorageSiK.Libs.firstCodepointText(text)
	text = tostring(text or "")
	if text == "" then return "" end
	local charLen = 1
	local unit = string.byte(text, 1)
	if unit >= 0xD800 and unit <= 0xDBFF and GlobalStorageSiK.Libs.isLowSurrogateAt(text, 2) then
		charLen = 2
	end
	return string.sub(text, 1, charLen)
end

--- Numero de caracteres Unicode "reales" de una cadena (un par subrogado
--- cuenta como 1, no como 2) - NUNCA usar `#text` para esto, ver comentario
--- de unicodeCodepoints() arriba.
---@param text string
---@return number
function GlobalStorageSiK.Libs.unicodeLength(text)
	text = tostring(text or "")
	local count = 0
	local i = 1
	local len = #text
	while i <= len do
		-- BUG REAL cerrado (2026-08-26, revision tecnica de Desarrollo tras
		-- dev16): un bajo subrogado HUERFANO (sin alto subrogado justo antes -
		-- nunca deberia pasar con un nombre valido, pero una cadena corrupta o
		-- cortada a medias no puede asumirse imposible) se saltaba en
		-- silencio, SIN contarlo, infracontando la longitud real. Ahora
		-- cuenta como 1 caracter invalido/de reemplazo en vez de desaparecer.
		local unit = string.byte(text, i)
		if unit >= 0xD800 and unit <= 0xDBFF and GlobalStorageSiK.Libs.isLowSurrogateAt(text, i + 1) then
			i = i + 2
		else
			i = i + 1
		end
		count = count + 1
	end
	return count
end

-- dev24.1 (hallazgo bloqueante de sistemas: GlobalStorageSiK_NativeCorpus.log
-- contenia U+FFFD literal - "señal"/"§2" llegaban ya sustituidos ANTES o
-- durante getFileWriter:write(), bytes reales EF BF BD en el fichero). Sin
-- poder reproducir el proceso Java real fuera del juego, se aplica la
-- correccion segura pedida explicitamente por sistemas en vez de adivinar
-- una conversion dependiente de locale: nunca pasar NADA fuera de ASCII a
-- getFileWriter - cualquier caracter fuera de 0x20-0x7E se escapa de forma
-- REVERSIBLE y EXPLICITA como \uXXXX (o \u{XXXXX} para fuera del BMP, ya
-- resuelto correctamente por unicodeCodepoints - pares subrogados incluidos,
-- cubre CJK igual que acentos, una unica politica para ambos casos).
---@param text string
---@return string escapado, seguro de escribir con getFileWriter sin riesgo de U+FFFD
function GlobalStorageSiK.Libs.asciiSafeEscape(text)
	text = tostring(text or "")
	if text == "" then return "" end
	local codepoints = GlobalStorageSiK.Libs.unicodeCodepoints(text, 100000)
	local out = {}
	for i = 1, #codepoints do
		local cp = codepoints[i]
		if cp == 0x0A or cp == 0x0D or cp == 0x09 or (cp >= 0x20 and cp <= 0x7E) then
			out[#out + 1] = string.char(cp)
		elseif cp <= 0xFFFF then
			out[#out + 1] = string.format("\\u%04X", cp)
		else
			out[#out + 1] = string.format("\\u{%05X}", cp)
		end
	end
	return table.concat(out)
end

--- Formatea los puntos de codigo de una cadena como "U+98CE U+3002" (formato
--- pedido explicitamente para el diagnostico CJK) - vacio si el texto esta
--- vacio, nunca falla sobre entrada corrupta (usa unicodeCodepoints, que ya
--- degrada unidad a unidad en vez de abortar).
---@param text string
---@param maxChars number|nil
---@return string
function GlobalStorageSiK.Libs.formatCodepoints(text, maxChars)
	local codepoints = GlobalStorageSiK.Libs.unicodeCodepoints(text, maxChars)
	if #codepoints == 0 then return "" end
	local parts = {}
	for i = 1, #codepoints do
		parts[i] = string.format("U+%04X", codepoints[i])
	end
	return table.concat(parts, " ")
end

--- Trunca texto mediante el proveedor propio.
---@param text string
---@param maxWidth number
---@param font UIFont|nil
---@param suffix string|nil
---@return string
function GlobalStorageSiK.Libs.truncateText(text, maxWidth, font, suffix)
	font = font or UIFont.Small
	suffix = suffix or ".."
	maxWidth = math.floor(tonumber(maxWidth) or 0)
	if maxWidth <= 0 or not text or text == "" then
		return ""
	end
	local tm = getTextManager()
	if tm:MeasureStringX(font, text) <= maxWidth then
		return text
	end
	local suffixW = tm:MeasureStringX(font, suffix)
	if suffixW >= maxWidth then
		return suffix
	end
	local budget = maxWidth - suffixW
	local left, right, best = 1, #text, 0
	while left <= right do
		local mid = math.floor((left + right) / 2)
		-- BUG REAL DE ARQUITECTURA cerrado (2026-08-26, revision tecnica de
		-- Desarrollo tras el banco CJK de DEV15): esto trataba `mid` como un
		-- indice de BYTE UTF-8 y retrocedia sobre "bytes de continuacion"
		-- 0x80-0xBF - pero en Kahlua/PZ las cadenas son unidades UTF-16
		-- (java.lang.String), no bytes. Para el BMP (chino/japones/coreano
		-- comun) cada unidad YA es un caracter completo, asi que el corte
		-- funcionaba por COINCIDENCIA; para un caracter fuera del BMP (p.ej.
		-- 𠮷, par subrogado alto+bajo) `mid` podia caer justo entre las 2
		-- unidades, partiendolo y dejando un subrogado huerfano (glifo roto).
		-- Ahora se retrocede solo si la unidad siguiente es la mitad BAJA de
		-- un par subrogado (GS_Libs.isLowSurrogateAt) - nunca deja el corte
		-- justo despues de un alto subrogado sin su bajo correspondiente.
		local cut = mid
		while cut > 0 and GlobalStorageSiK.Libs.isLowSurrogateAt(text, cut + 1) do
			cut = cut - 1
		end
		local part = string.sub(text, 1, cut)
		if tm:MeasureStringX(font, part) <= budget then
			best = cut
			left = mid + 1
		else
			right = mid - 1
		end
	end
	if best == 0 then
		return suffix
	end
	return string.sub(text, 1, best) .. suffix
end

--- Indica si Neat Crafting está activo en la partida.
---@return boolean
function GlobalStorageSiK.Libs.hasNeatCrafting()
	if GlobalStorageSiK.Libs._neatCrafting ~= nil then
		return GlobalStorageSiK.Libs._neatCrafting
	end
	local active = false
	if getActivatedMods and getActivatedMods():contains("Neat_Crafting") then
		active = true
	end
	GlobalStorageSiK.Libs._neatCrafting = active
	return active
end

--- Indica si Neat Building está activo en la partida.
---@return boolean
function GlobalStorageSiK.Libs.hasNeatBuilding()
	if GlobalStorageSiK.Libs._neatBuilding ~= nil then
		return GlobalStorageSiK.Libs._neatBuilding
	end
	local active = false
	if getActivatedMods and getActivatedMods():contains("Neat_Building") then
		active = true
	end
	GlobalStorageSiK.Libs._neatBuilding = active
	return active
end

--- Indica si Project Cook (mod de cocina de terceros, addon opcional
--- consumido por GSSiK_Addon_Craft) está activo en la partida.
---@return boolean
function GlobalStorageSiK.Libs.hasProjectCook()
	if GlobalStorageSiK.Libs._projectCook ~= nil then
		return GlobalStorageSiK.Libs._projectCook
	end
	local active = false
	if getActivatedMods and getActivatedMods():contains("Project_Cook") then
		active = true
	end
	GlobalStorageSiK.Libs._projectCook = active
	return active
end

--- Resuelve apertura de crafteo según mods Neat instalados.
---@param mode string|nil "auto"|"vanilla"|"neat"
---@return function|nil
function GlobalStorageSiK.Libs.resolveHandcraftOpener(mode)
	mode = mode or "auto"
	if not ISEntityUI then
		return nil
	end
	if mode == "vanilla" and ISEntityUI._NC_old_OpenHandcraftWindow then
		return ISEntityUI._NC_old_OpenHandcraftWindow
	end
	if mode == "neat" and ISEntityUI._NC_new_OpenHandcraftWindow then
		return ISEntityUI._NC_new_OpenHandcraftWindow
	end
	if mode == "auto" and GlobalStorageSiK.Libs.hasNeatCrafting() and ISEntityUI._NC_new_OpenHandcraftWindow then
		return ISEntityUI._NC_new_OpenHandcraftWindow
	end
	return ISEntityUI.OpenHandcraftWindow
end

--- Resuelve apertura de construcción según mods Neat instalados.
---@param mode string|nil "auto"|"vanilla"|"neat"
---@return function|nil
function GlobalStorageSiK.Libs.resolveBuildOpener(mode)
	mode = mode or "auto"
	if not ISEntityUI or not ISEntityUI.OpenBuildWindow then
		return nil
	end
	if mode == "vanilla" and ISEntityUI._NB_old_OpenBuildWindow then
		return ISEntityUI._NB_old_OpenBuildWindow
	end
	if mode == "neat" or mode == "auto" then
		if GlobalStorageSiK.Libs.hasNeatBuilding() then
			return ISEntityUI.OpenBuildWindow
		end
	end
	return ISEntityUI._NB_old_OpenBuildWindow or ISEntityUI.OpenBuildWindow
end
