--[[
	GlobalStorageSiK - Utilidades compartidas de UI para el motor de reglas
	AND/OR/NOT (dev26, ronda 2)
	Descripción: piezas de presentación/edición de reglas {op, condition}
	reutilizadas TANTO por el editor de contenedor (GS_TerminalUI_NodeEditor.lua)
	COMO por el editor de zona (GS_TerminalUI_ZoneEditor.lua) - etiquetas
	legibles, resumen en prosa, clonado, migración legacy y el detector
	general de contradicciones. Sin esto, cada editor duplicaría la misma
	lógica de interpretación de reglas. Ver Documentacion/GS_FilterRedesign_Plan.md.
]]

require "GS_I18n"
require "GS_NativeProduct"
require "GS_CategoryResolution"
require "GS_RuleSanitizer"
require "GS_RuleIdentity"
require "GS_NodeFilters"

local UI = require "GS_UI_Framework"

GlobalStorageSiK.RulesUI = {}

local T = GlobalStorageSiK.I18n.text

GlobalStorageSiK.RulesUI.OPS = { "OR", "AND", "NOT" }
GlobalStorageSiK.RulesUI.OP_TITLE_KEY = { OR = "IGUI_GS_NodeRulesOrTitle", AND = "IGUI_GS_NodeRulesAndTitle", NOT = "IGUI_GS_NodeRulesNotTitle" }
GlobalStorageSiK.RulesUI.OP_ADD_KEY   = { OR = "IGUI_GS_NodeRulesAddOr",   AND = "IGUI_GS_NodeRulesAddAnd",   NOT = "IGUI_GS_NodeRulesAddNot" }

--- Etiqueta legible de una clave de categoria. Las rutas nativas se resuelven
--- mediante el contrato comun; las claves historicas externas se conservan
--- como texto visible para poder sustituirlas, pero no se interpretan.
---@param key string
---@return string
function GlobalStorageSiK.RulesUI.categoryLabel(key, condition)
	if not key or key == "" then return "?" end
	local nativePath = GlobalStorageSiK.NativeProduct.decodePath(key)
	if nativePath then return GlobalStorageSiK.NativeProduct.getView(nativePath).fullLabel end
	local status = GlobalStorageSiK.CategoryResolution.classifyStoredRule(condition or { value = key })
	if status == "ORPHANED_NATIVE" or status == "DEPRECATED_EXTERNAL" then
		return GlobalStorageSiK.I18n.text("IGUI_GS_RuleDeprecatedExternal", key)
	end
	if status == "TECHNICAL_RESIDUE" then return GlobalStorageSiK.I18n.text("IGUI_GS_RuleTechnicalResidue", key) end
	if GlobalStorageSiK.CategoryResolution.isVanillaKey(key) then
		return GlobalStorageSiK.CategoryResolution.label({ effective = "vanilla", vanillaKey = key })
	end
	return key
end

--- Etiqueta legible de UNA condicion de regla: tipo "category" usa
--- categoryLabel de arriba; el resto (name/weight/tag/item) reutiliza
--- GS_NodeFilters.describe tal cual.
---@param condition table
---@return string
function GlobalStorageSiK.RulesUI.describeCondition(condition)
	if not condition then return "?" end
	if condition.type == "category" then
		return GlobalStorageSiK.RulesUI.categoryLabel(condition.nativePath or condition.value, condition)
	end
	return GlobalStorageSiK.NodeFilters.describe(condition)
end

-- A count alone cannot detect moving a rule between OR/AND/NOT or replacing
-- its label with a longer one. Both change the measured editor layout.
function GlobalStorageSiK.RulesUI.layoutSignature(rules)
	local parts = {}
	for index = 1, #(rules or {}) do
		local rule = rules[index]
		local op = tostring(rule.op or "OR")
		local label = tostring(GlobalStorageSiK.RulesUI.describeCondition(rule.condition))
		parts[#parts + 1] = tostring(#op) .. ":" .. op .. tostring(#label) .. ":" .. label
	end
	return table.concat(parts)
end

function GlobalStorageSiK.RulesUI.stateSignature(rules)
	local parts = {}
	for index = 1, #(rules or {}) do
		local token = GlobalStorageSiK.RuleIdentity.signature(rules[index])
		if not token then return nil end
		parts[#parts + 1] = tostring(#token) .. ":" .. token
	end
	return table.concat(parts)
end

local function ruleGestureActive(editor)
	for _, host in pairs(editor._ruleChipsHosts or {}) do
		for _, row in ipairs(host.childrenInOrder or {}) do
			-- Empty groups contain labels inheriting ISUIElement.close (a method),
			-- whereas a dismissible row owns an actual close-button table.
			local closeButton = rawget(row, "close")
			if type(closeButton) == "table" and closeButton._sikPressed == true then return true end
		end
	end
	return false
end

-- Network sync is event driven. Only an in-flight chip press postpones it;
-- the existing visible editor update applies the latest snapshot once on release.
local function flushRuleSync(editor)
	local pending = editor._pendingRuleSync
	editor._pendingRuleSync = nil
	if not pending then return end
	if pending.model then pending.model() end
	if pending.content then pending.content() end
end

function GlobalStorageSiK.RulesUI.applyWhenIdle(editor, callback, kind)
	editor._pendingRuleSync = editor._pendingRuleSync or {}
	editor._pendingRuleSync[kind == "content" and "content" or "model"] = callback
	if not ruleGestureActive(editor) then flushRuleSync(editor); return end
	if editor._ruleSyncUpdateInstalled then return end
	editor._ruleSyncUpdateInstalled = true
	local rawUpdate, previous = rawget(editor, "update"), editor.update
	editor.update = function(self, ...)
		if previous then previous(self, ...) end
		if not self._pendingRuleSync or not ruleGestureActive(self) then
			self._ruleSyncUpdateInstalled = nil
			self.update = rawUpdate
			if not self.getIsVisible or self:getIsVisible() then flushRuleSync(self)
			else self._pendingRuleSync = nil end
		end
	end
end

function GlobalStorageSiK.RulesUI.refreshEditorRules(editor, rules)
	local signature = GlobalStorageSiK.RulesUI.stateSignature(rules)
	if signature ~= nil and editor._rulesIdentityAtBuild == signature then return false end
	for _, op in ipairs(GlobalStorageSiK.RulesUI.OPS) do editor:rebuildRuleChips(op) end
	editor._rulesIdentityAtBuild = signature
	editor._rulesLayoutAtBuild = GlobalStorageSiK.RulesUI.layoutSignature(rules)
	if editor.rulesBlock and editor.rulesBlock.refreshLayout then editor.rulesBlock:refreshLayout() end
	editor._lastLayoutW = nil
	editor:layoutForm()
	return true
end

--- Rewrap a passive rule summary only when its text or available width changes.
function GlobalStorageSiK.RulesUI.refreshSummary(host, rules, width, font, color)
	if not host then return 0 end
	width = math.max(1, tonumber(width) or host.width)
	font = font or UIFont.Small
	local signature = tostring(width) .. ":" .. GlobalStorageSiK.RulesUI.layoutSignature(rules)
	if host._summarySignature == signature then return host.height end
	host._summarySignature = signature
	for index = #(host.childrenInOrder or {}), 1, -1 do
		local child = host.childrenInOrder[index]
		host:removeChild(child)
		if child.dispose then child:dispose() end
	end
	local layout = GlobalStorageSiK.RulesUI.layoutSummary(rules, width, font, color)
	local fontHeight = getTextManager():getFontHeight(font)
	host:setWidth(width)
	host:setHeight(math.max(fontHeight, layout.lineCount * (fontHeight + 2)))
	for index = 1, #(layout.runs or {}) do
		local run = layout.runs[index]
		local tint = run.color
		local copy = UI.Controls.copyText(host, {
			x = run.x, y = (run.line - 1) * (fontHeight + 2),
			w = math.max(1, width - run.x), text = run.text, font = font,
			lineGap = 0, noWrap = true,
			tone = run.fallback and "textMuted" or "ruleSummary",
			theme = not run.fallback and { ruleSummary = {
				r = tint[1], g = tint[2], b = tint[3], a = tint[4] or 1 } } or nil,
		})
		if copy.setMouseTransparent then copy:setMouseTransparent(true) end
	end
	return host.height
end

---@param condition table|nil
---@param fallback table|false|nil false requests only a native category colour
---@return table|nil RGB
function GlobalStorageSiK.RulesUI.conditionColor(condition, fallback)
	if type(condition) == "table" and condition.type == "category" then
		local nativePath = condition.nativePath
		if nativePath == nil and type(condition.value) == "string"
			and condition.value:sub(1, 7) == "native:" then
			nativePath = condition.value
		end
		if GlobalStorageSiK.NativeProduct.decodePath(nativePath) then
			return GlobalStorageSiK.NativeProduct.getColor(nativePath)
		end
	end
	if fallback == false then return nil end
	return fallback or { 0.72, 0.75, 0.78 }
end

-- Preserve extension metadata without sharing mutable tables with the source.
-- Iterative copying also tolerates repeated references without recursive depth.
local function cloneCondition(source)
	local result = {}
	local copies = { [source] = result }
	local pending = { source }
	local index = 1
	while index <= #pending do
		local current = pending[index]
		local target = copies[current]
		for key, value in pairs(current) do
			if type(value) == "table" then
				if not copies[value] then
					copies[value] = {}
					pending[#pending + 1] = value
				end
				target[key] = copies[value]
			else
				target[key] = value
			end
		end
		index = index + 1
	end
	return result
end

--- Copia profunda de una lista de reglas {op, condition}.
---@param source table
---@return table
function GlobalStorageSiK.RulesUI.cloneRules(source)
	local result = {}
	for i = 1, #(source or {}) do
		local rule = source[i]
		if not GlobalStorageSiK.RuleSanitizer.isJunkCategoryCondition(rule.condition) then
			local copy = cloneCondition(rule)
			copy.condition = copy.condition or {}
			result[#result + 1] = copy
		end
	end
	return result
end

--- Categoria legacy "basura": un codigo tecnico de una sola letra (B/F/W...)
--- filtrado por metadata vanilla, suelto o como sub-nivel de un "main::sub"
--- (ej. "Arma::W") - el resolvedor común descarta este mismo patrón al leer
--- datos en vivo,
--- pero una categoria legacy ya guardada en node.categories de una sesion
--- ANTERIOR a esa proteccion podia arrastrar uno de estos codigos sueltos.
--- Sin este mismo filtro aqui, la migracion los convertia en una regla real
--- que ni siquiera existe como opcion en el desplegable de categorias - bug
--- real reportado por el usuario con captura ("Arma - W" duplicado, dev26
--- ronda 4bis).
---@param cat string|nil
---@return boolean
local function isJunkLegacyCategory(cat)
	return GlobalStorageSiK.RuleSanitizer.isJunkCategoryCondition({ type = "category", value = cat })
end

--- Migra categorias/filtros legacy (pre-dev26) a la lista unificada de
--- reglas, todas como OR - reproduce EXACTAMENTE la semantica anterior de
--- GS_Router.matchSpecificity.
---@param categories table|nil
---@param filters table|nil
---@return table
function GlobalStorageSiK.RulesUI.migrateLegacyToRules(categories, filters)
	local rules = {}
	for _, cat in ipairs(categories or {}) do
		if not isJunkLegacyCategory(cat) then
			rules[#rules + 1] = { op = "OR", condition = { type = "category", value = cat } }
		end
	end
	for _, filter in ipairs(filters or {}) do
		local condition = {}
		for k, v in pairs(filter or {}) do condition[k] = v end
		rules[#rules + 1] = { op = "OR", condition = condition }
	end
	return rules
end

--- Frase-resumen legible de un protocolo de aceptacion completo.
---@param rules table
---@return string
function GlobalStorageSiK.RulesUI.buildSummary(rules)
	local orParts, andParts, notParts = {}, {}, {}
	for i = 1, #(rules or {}) do
		local rule = rules[i]
		if not GlobalStorageSiK.RuleSanitizer.isJunkCategoryCondition(rule.condition) then
			local label = GlobalStorageSiK.RulesUI.describeCondition(rule.condition)
			if rule.op == "AND" then andParts[#andParts + 1] = label
			elseif rule.op == "NOT" then notParts[#notParts + 1] = label
			else orParts[#orParts + 1] = label end
		end
	end
	if #orParts == 0 and #andParts == 0 and #notParts == 0 then
		return T("IGUI_GS_NodeRulesSummaryUnrestricted")
	end
	local sentence = ""
	if #orParts > 0 then
		sentence = T("IGUI_GS_NodeRulesSummaryAccepts", table.concat(orParts, T("IGUI_GS_NodeRulesJoinOr")))
	end
	if #andParts > 0 then
		sentence = sentence .. T("IGUI_GS_NodeRulesSummaryAlso", table.concat(andParts, T("IGUI_GS_NodeRulesJoinAnd")))
	end
	if #notParts > 0 then
		sentence = sentence .. T("IGUI_GS_NodeRulesSummaryNever", table.concat(notParts, T("IGUI_GS_NodeRulesJoinNot")))
	end
	sentence = sentence:gsub("^%s+", "")
	if sentence == "" then
		return T("IGUI_GS_NodeRulesSummaryUnrestricted")
	end
	return sentence
end

local SUMMARY_MARKER = "__GS_RULE_SUMMARY_VALUE__"

local function appendSummaryText(segments, text, condition)
	if text and text ~= "" then
		segments[#segments + 1] = { text = text, condition = condition }
	end
end

---@param rules table
---@return table[] {text=string,condition=table|nil}
function GlobalStorageSiK.RulesUI.buildSummarySegments(rules)
	local grouped = { OR = {}, AND = {}, NOT = {} }
	for i = 1, #(rules or {}) do
		local rule = rules[i]
		if type(rule) == "table" and type(rule.condition) == "table"
			and not GlobalStorageSiK.RuleSanitizer.isJunkCategoryCondition(rule.condition) then
			local op = grouped[rule.op] and rule.op or "OR"
			grouped[op][#grouped[op] + 1] = rule.condition
		end
	end
	if #grouped.OR == 0 and #grouped.AND == 0 and #grouped.NOT == 0 then
		return { { text = T("IGUI_GS_NodeRulesSummaryUnrestricted") } }
	end

	local segments = {}
	local function appendGroup(conditions, templateKey, joinKey)
		if #conditions == 0 then return end
		local template = T(templateKey, SUMMARY_MARKER)
		local markerStart = template:find(SUMMARY_MARKER, 1, true)
		if not markerStart then
			appendSummaryText(segments, template)
			return
		end
		appendSummaryText(segments, template:sub(1, markerStart - 1))
		local joinText = T(joinKey)
		for i = 1, #conditions do
			if i > 1 then appendSummaryText(segments, joinText) end
			appendSummaryText(segments,
				GlobalStorageSiK.RulesUI.describeCondition(conditions[i]), conditions[i])
		end
		appendSummaryText(segments, template:sub(markerStart + #SUMMARY_MARKER))
	end
	appendGroup(grouped.OR, "IGUI_GS_NodeRulesSummaryAccepts", "IGUI_GS_NodeRulesJoinOr")
	appendGroup(grouped.AND, "IGUI_GS_NodeRulesSummaryAlso", "IGUI_GS_NodeRulesJoinAnd")
	appendGroup(grouped.NOT, "IGUI_GS_NodeRulesSummaryNever", "IGUI_GS_NodeRulesJoinNot")
	return segments
end

---@param rules table
---@param maxWidth number
---@param font UIFont
---@param fallbackColor table
---@return table layout {runs=table[],lineCount=number,text=string}
function GlobalStorageSiK.RulesUI.layoutSummary(rules, maxWidth, font, fallbackColor)
	local segments = GlobalStorageSiK.RulesUI.buildSummarySegments(rules)
	local tm = getTextManager()
	local runs, plain = {}, ""
	local x, line, pendingWhitespace = 0, 1, ""
	maxWidth = math.max(40, tonumber(maxWidth) or 200)
	font = font or UIFont.Small
	fallbackColor = fallbackColor or { 0.72, 0.75, 0.78 }

	local function nextLine()
		x = 0
		line = line + 1
	end
	local function addRun(text, color)
		if text == "" then return end
		runs[#runs + 1] = { text = text, x = x, line = line, color = color,
			fallback = color == fallbackColor }
		x = x + tm:MeasureStringX(font, text)
	end
	local function addWord(word, color)
		local space = pendingWhitespace ~= "" and " " or ""
		pendingWhitespace = ""
		local wordWidth = tm:MeasureStringX(font, word)
		if wordWidth > maxWidth then
			if x > 0 then nextLine() end
			local chunks = UI.Controls.wrapText(word, maxWidth, font)
			for i = 1, #chunks do
				addRun(chunks[i], color)
				if i < #chunks then nextLine() end
			end
			return
		end
		local prefix = x > 0 and space or ""
		if x > 0 and space ~= ""
			and x + tm:MeasureStringX(font, prefix .. word) > maxWidth then
			nextLine()
			prefix = ""
		end
		addRun(prefix .. word, color)
	end

	for i = 1, #segments do
		local segment = segments[i]
		local text = tostring(segment.text or "")
		plain = plain .. text
		local color = GlobalStorageSiK.RulesUI.conditionColor(segment.condition, fallbackColor)
		local pos = 1
		while pos <= #text do
			local wordStart, wordEnd = text:find("%S+", pos)
			if not wordStart then
				pendingWhitespace = pendingWhitespace .. text:sub(pos)
				break
			end
			pendingWhitespace = pendingWhitespace .. text:sub(pos, wordStart - 1)
			addWord(text:sub(wordStart, wordEnd), color)
			pos = wordEnd + 1
		end
	end
	return { runs = runs, lineCount = math.max(1, line), text = plain }
end

--- Convierte un filtro de tipo "weight" en un rango [lo, hi] (nil = sin
--- limite en ese extremo), para poder comparar solapamiento entre dos
--- condiciones de peso distintas (detector de contradicciones).
---@param condition table
---@return number|nil lo, number|nil hi
local function weightRange(condition)
	local v1 = tonumber(condition.value)
	if not v1 then return nil, nil end
	local mode = condition.mode or "eq"
	if mode == "gt" then return v1, nil
	elseif mode == "gte" then return v1, nil
	elseif mode == "lt" then return nil, v1
	elseif mode == "lte" then return nil, v1
	elseif mode == "between" then
		local v2 = tonumber(condition.value2) or v1
		return math.min(v1, v2), math.max(v1, v2)
	end
	return v1, v1 -- eq
end

--- true si una clave de regla de categoria es de nivel 1 (EXT_GROUP_PREFIX,
--- ej. "Comida" entera) o nivel 2 (SUBGROUP_PREFIX, ej. "Comida > Perecedero"):
--- ambas son mas AMPLIAS que una hoja exacta de nivel 3, y por tanto cubren
--- (contienen) cualquier hoja mas especifica del mismo grupo.
---@param key string
---@return boolean
local function isBroadCategoryRule(key)
	if not key or key == "" then return false end
	local nativePath = GlobalStorageSiK.NativeProduct.decodePath(key)
	return nativePath and nativePath.l3 == nil
end

--- Resuelve el nivel superior de una ruta nativa de regla.
---@param key string
---@return string|nil
local function categoryRuleGroupKey(key)
	if not key or key == "" then return nil end
	local nativePath = GlobalStorageSiK.NativeProduct.decodePath(key)
	if nativePath then return nativePath.l1 end
	return nil
end

--- true si dos condiciones del MISMO tipo se solapan (misma categoria/tag/
--- item exacto, jerarquia de categoria compartida, substring de nombre
--- compartido, o rango de peso que se cruza). No es un detector
--- matematicamente exhaustivo (ej. dos hojas exactas hermanas del mismo
--- grupo, sin relacion padre/hijo entre ellas, no cuentan como solape) -
--- cubre los casos directos y reales descritos en el plan de diseño
--- (§4.4-quinquies).
---@param a table condicion
---@param b table condicion
---@return boolean
local function conditionsOverlap(a, b)
	if not a or not b or a.type ~= b.type then return false end
	if a.type == "category" then
		local aValue, bValue = a.nativePath or a.value, b.nativePath or b.value
		local av, bv = string.lower(tostring(aValue or "")), string.lower(tostring(bValue or ""))
		if av == bv then return true end
		local aPath = GlobalStorageSiK.NativeProduct.decodePath(aValue)
		local bPath = GlobalStorageSiK.NativeProduct.decodePath(bValue)
		if aPath and bPath then
			return GlobalStorageSiK.NativeProduct.pathMatches(aPath, bPath)
				or GlobalStorageSiK.NativeProduct.pathMatches(bPath, aPath)
		end
		-- Jerarquia: un NOT/OR/AND de Nivel 1 o 2 (ej. "Comida" o "Comida >
		-- Perecedero") cubre cualquier hoja mas especifica del MISMO grupo -
		-- solo cuenta si al menos una de las dos reglas es "amplia" (Nivel
		-- 1/2), nunca entre dos hojas exactas hermanas sin relacion.
		if isBroadCategoryRule(aValue) or isBroadCategoryRule(bValue) then
			local ga, gb = categoryRuleGroupKey(aValue), categoryRuleGroupKey(bValue)
			if ga and gb and string.lower(ga) == string.lower(gb) then
				return true
			end
		end
		return false
	end
	if a.type == "tag" then
		return string.lower(tostring(a.value or "")) == string.lower(tostring(b.value or ""))
	end
	if a.type == "item" then
		return tostring(a.itemType or "") == tostring(b.itemType or "")
	end
	if a.type == "name" then
		local av, bv = string.lower(tostring(a.value or "")), string.lower(tostring(b.value or ""))
		if av == "" or bv == "" then return false end
		return av:find(bv, 1, true) ~= nil or bv:find(av, 1, true) ~= nil
	end
	if a.type == "weight" then
		local aLo, aHi = weightRange(a)
		local bLo, bHi = weightRange(b)
		local lo = math.max(aLo or -math.huge, bLo or -math.huge)
		local hi = math.min(aHi or math.huge, bHi or math.huge)
		return lo <= hi
	end
	return false
end

--- Resumen compacto de un protocolo de reglas para una celda de tabla
--- estrecha (columna "Protocolo" de la lista de contenedores/zonas, dev26
--- ronda 3). Prioridad para elegir QUE regla mostrar como texto: primera
--- OR > primera AND > primera NOT - coherente con que OR define la
--- aceptacion base, AND la restringe y NOT la excluye. hasOr/hasAnd/hasNot
--- reflejan la composicion COMPLETA (para los 3 puntos de color), no solo
--- la regla elegida como texto.
---@param rules table|nil
---@return table|nil { hasOr, hasAnd, hasNot, label, opKey, extraCount } - opKey "OR"|"AND"|"NOT"; nil si no hay ninguna regla
function GlobalStorageSiK.RulesUI.compactSummary(rules)
	rules = rules or {}
	if #rules == 0 then return nil end
	local hasOr, hasAnd, hasNot = false, false, false
	local visibleCount = 0
	local firstOr, firstAnd, firstNot = nil, nil, nil
	for i = 1, #rules do
		local rule = rules[i]
		if type(rule) == "table" and type(rule.condition) == "table"
			and not GlobalStorageSiK.RuleSanitizer.isJunkCategoryCondition(rule.condition) then
			visibleCount = visibleCount + 1
			if rule.op == "OR" then
				hasOr = true
				firstOr = firstOr or rule
			elseif rule.op == "AND" then
				hasAnd = true
				firstAnd = firstAnd or rule
			elseif rule.op == "NOT" then
				hasNot = true
				firstNot = firstNot or rule
			end
		end
	end
	local primary, opKey = firstOr, "OR"
	if not primary then primary, opKey = firstAnd, "AND" end
	if not primary then primary, opKey = firstNot, "NOT" end
	if not primary then return nil end
	return {
		hasOr = hasOr, hasAnd = hasAnd, hasNot = hasNot,
		label = GlobalStorageSiK.RulesUI.describeCondition(primary.condition),
		condition = primary.condition,
		opKey = opKey,
		extraCount = visibleCount - 1,
	}
end

--- Detector general de contradicciones (§4.4-quinquies del plan): busca, en
--- una lista de reglas YA GUARDADAS, alguna que quede neutralizada por
--- newRule (un NOT contra un OR/AND que se solapa, o viceversa). Devuelve la
--- PRIMERA regla en conflicto encontrada (o nil si ninguna).
---@param existingRules table
---@param newRule table {op, condition}
---@return table|nil conflictingRule
function GlobalStorageSiK.RulesUI.detectContradiction(existingRules, newRule)
	if not newRule or not newRule.condition then return nil end
	local newIsExclusion = newRule.op == "NOT"
	for i = 1, #(existingRules or {}) do
		local existing = existingRules[i]
		local existingIsExclusion = existing.op == "NOT"
		if existingIsExclusion ~= newIsExclusion and conditionsOverlap(existing.condition, newRule.condition) then
			return existing
		end
	end
	return nil
end

--- Version CRUZADA del detector (§4.4-quinquies: "cambiar la categoria de
--- zona deriva en cambio de contenedores que contiene"): busca si una regla
--- de ZONA nueva neutraliza alguna regla YA guardada de cualquier contenedor
--- de esa zona. Devuelve el nombre del PRIMER contenedor en conflicto y su
--- regla, o nil si ninguno.
---@param newRule table {op, condition} - regla de zona a punto de guardarse
---@param containerGroups table[] { name=string, rules=table } - un grupo por contenedor de la zona
---@return string|nil containerName, table|nil conflictingRule
function GlobalStorageSiK.RulesUI.detectCrossLevelContradiction(newRule, containerGroups)
	for i = 1, #(containerGroups or {}) do
		local group = containerGroups[i]
		local conflict = GlobalStorageSiK.RulesUI.detectContradiction(group.rules, newRule)
		if conflict then
			return group.name, conflict
		end
	end
	return nil, nil
end
