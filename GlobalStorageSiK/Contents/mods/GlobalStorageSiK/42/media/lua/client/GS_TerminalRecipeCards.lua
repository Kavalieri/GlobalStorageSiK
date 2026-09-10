--[[
	GlobalStorageSiK - Tarjetas de receta del terminal (cliente)
	Autor: SiK
	Fecha: 2025-06-25
	Descripción: UI compartida para recetas del mod (terminal, tableta).
]]

require "GS_I18n"
require "GS_CraftUtils"

local UI = require "GS_UI_Framework"

GlobalStorageSiK.TerminalRecipeCards = GlobalStorageSiK.TerminalRecipeCards or {}

local T = GlobalStorageSiK.I18n.text
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local LINE_GAP = 4
local REQ_ICON = 28
local REQ_ICON_GAP = 8
local REQ_ICON_FRAME_PAD = 3
local CRAFT_BTN_W = 148
local CRAFT_BTN_H = FONT_HGT_SMALL + 10

--- Envuelve texto en líneas de dibujo.
---@param out table
---@param text string
---@param maxWidth number
---@param r number
---@param g number
---@param b number
local function pushWrappedLines(out, text, maxWidth, r, g, b, met)
	for _, line in ipairs(UI.Controls.wrapText(text, maxWidth, UIFont.Small)) do
		table.insert(out, { text = line, r = r, g = g, b = b, ok = met == true })
	end
end

--- Mide altura del cuerpo de una tarjeta.
--- IMPORTANTE: las filas con icono tambien envuelven su texto en varias
--- lineas si no cabe en el ancho reservado (ver createBodyControls) — antes esta
--- funcion solo reservaba UNA linea fija para esas filas, asi que un texto
--- largo (ej. titulo de revista) se dibujaba en 2+ lineas pero el panel
--- media solo 1, y el contenido siguiente (materiales, botones) quedaba
--- solapado. Ahora mide el mismo envoltorio que realmente se dibuja.
---@param bodyLines table
---@param textW number
---@return number
function GlobalStorageSiK.TerminalRecipeCards.measureBodyHeight(bodyLines, textW)
	local h = 0
	local lh = FONT_HGT_SMALL + LINE_GAP
	local iconRowH = math.max(lh, REQ_ICON + LINE_GAP)
	local textWIcon = math.max(120, textW - REQ_ICON - REQ_ICON_GAP)
	for i = 1, #bodyLines do
		local spec = bodyLines[i]
		if spec.icon or spec.itemType then
			local wrappedH = #UI.Controls.wrapText(spec.text, textWIcon, UIFont.Small)
				* (FONT_HGT_SMALL + LINE_GAP)
			h = h + math.max(iconRowH, wrappedH)
		else
			h = h + #UI.Controls.wrapText(spec.text, textW, UIFont.Small)
				* (FONT_HGT_SMALL + LINE_GAP)
		end
	end
	return h
end

--- Construye líneas de requisitos para una receta serializada.
---@param recipe table
---@param textW number
---@return table
function GlobalStorageSiK.TerminalRecipeCards.buildBodyLines(recipe, textW)
	local lines = {}
	local textWIcon = math.max(120, textW - REQ_ICON - REQ_ICON_GAP)
	if recipe.requireBooks then
		local bookR, bookG, bookB = recipe.knowsBook and 0.5 or 0.82, recipe.knowsBook and 0.78 or 0.32, recipe.knowsBook and 0.5 or 0.32
		local bookLine = T("IGUI_GS_ProgrammingRecipeRequirement", recipe.manualDisplay or "?")
		table.insert(lines, { text = bookLine, r = bookR, g = bookG, b = bookB,
			itemType = recipe.manualItem, ok = recipe.knowsBook == true })
	end
	if (recipe.skillLevel or 0) > 0 then
		local skillLine = T("IGUI_GS_CraftSkillReqLine", recipe.skillHave or 0, recipe.skillLevel or 0)
		local skR, skG, skB = recipe.skillOk and 0.5 or 0.82, recipe.skillOk and 0.78 or 0.32, recipe.skillOk and 0.5 or 0.32
		local skillIcon = Perks and Perks.Electricity and GlobalStorageSiK.CraftUtils.getPerkTexture(Perks.Electricity) or nil
		table.insert(lines, { text = skillLine, r = skR, g = skG, b = skB,
			icon = skillIcon, ok = recipe.skillOk == true })
	end
	if recipe.requireWorkbench then
		local wbR, wbG, wbB = recipe.nearWorkbench and 0.5 or 0.82, recipe.nearWorkbench and 0.78 or 0.32, recipe.nearWorkbench and 0.5 or 0.32
		local wbLine = recipe.nearWorkbench and T("IGUI_GS_ReqWorkbenchOk") or T("IGUI_GS_ReqWorkbenchMissing")
		pushWrappedLines(lines, wbLine, textWIcon, wbR, wbG, wbB, recipe.nearWorkbench)
	end
	if recipe.requireLight then
		local _lp = UI.Theme.palette()
		local ltR = recipe.hasCraftLight and _lp.statusOk[1] or _lp.statusDanger[1]
		local ltG = recipe.hasCraftLight and _lp.statusOk[2] or _lp.statusDanger[2]
		local ltB = recipe.hasCraftLight and _lp.statusOk[3] or _lp.statusDanger[3]
		local ltLine = recipe.hasCraftLight and T("IGUI_GS_ReqLightOk") or T("IGUI_GS_ReqLightMissing")
		pushWrappedLines(lines, ltLine, textWIcon, ltR, ltG, ltB, recipe.hasCraftLight)
	end
	local _ip = UI.Theme.palette()
	for j = 1, #(recipe.ingredients or {}) do
		local ing = recipe.ingredients[j]
		local colorR, colorG, colorB = _ip.statusDanger[1], _ip.statusDanger[2], _ip.statusDanger[3]
		if ing.ok or recipe.freeCraft then
			colorR, colorG, colorB = _ip.statusOk[1], _ip.statusOk[2], _ip.statusOk[3]
		end
		local line = string.format("%s  %d/%d", ing.displayName or ing.item, ing.have or 0, ing.count or 0)
		table.insert(lines, { text = line, r = colorR, g = colorG, b = colorB, itemType = ing.item,
			material = true, ok = ing.ok or recipe.freeCraft })
	end
	return lines
end

--- Resuelve icono de requisito.
---@param spec table
---@return userdata|nil
local function resolveReqIcon(spec)
	if spec.icon then
		return spec.icon
	end
	if spec.itemType and GlobalStorageSiK.CraftUtils.getItemIconTexture then
		return GlobalStorageSiK.CraftUtils.getItemIconTexture(spec.itemType)
	end
	return nil
end

--- Product classification only; shared framework owns subgroup layout.
function GlobalStorageSiK.TerminalRecipeCards.createRequirements(parent, recipe, width, playerNum)
	local groups = { { rows = {} }, { rows = {} } }
	for _, spec in ipairs(GlobalStorageSiK.TerminalRecipeCards.buildBodyLines(recipe, width)) do
		local rows = groups[spec.material and 2 or 1].rows
		rows[#rows + 1] = { text = spec.text, texture = resolveReqIcon(spec),
			-- Requirement truth is product state, independent of palette RGB.
			-- The shared row inherits its live semantic colour from parent.
			state = spec.ok == true and "met" or "missing" }
	end
	return UI.Requirements.create({ parent = parent, w = width, groups = groups, playerNum = playerNum })
end

local function lineTheme(spec)
	return {
		recipeLine = {
			r = spec.r or 1, g = spec.g or 1, b = spec.b or 1, a = 1,
		},
	}
end

local function disposeControls(controls)
	for i = #controls, 1, -1 do
		local control = controls[i]
		if control and control.dispose then control:dispose() end
		controls[i] = nil
	end
end

--- Construye la presentación de requisitos con controles públicos SiK.UI.
---@param card table
---@param bodyLines table
---@param textW number
---@param startY number
---@param pad number
---@return table controls
local function createBodyControls(card, bodyLines, textW, startY, pad)
	local controls = {}
	local y = startY
	local lh = FONT_HGT_SMALL + LINE_GAP
	local iconRowH = math.max(lh, REQ_ICON + LINE_GAP)
	local textX = pad + REQ_ICON + REQ_ICON_GAP
	local textWIcon = math.max(120, textW - REQ_ICON - REQ_ICON_GAP)
	for i = 1, #bodyLines do
		local spec = bodyLines[i]
		local icon = resolveReqIcon(spec)
		if icon then
			local rowStart = y
			local iconY = y + math.floor((iconRowH - REQ_ICON) / 2)
			local fp = REQ_ICON_FRAME_PAD
			local frame = UI.Controls.panel(card, {
				x = pad - fp, y = iconY - fp,
				w = REQ_ICON + fp * 2, h = REQ_ICON + fp * 2,
				drawBackground = true,
				backgroundColor = { r = 0.08, g = 0.08, b = 0.08, a = 0.9 },
				borderColor = {
					r = spec.r or 1, g = spec.g or 1, b = spec.b or 1, a = 0.8,
				},
			})
			controls[#controls + 1] = frame
			controls[#controls + 1] = UI.Controls.icon(frame, {
				x = fp, y = fp, w = REQ_ICON, h = REQ_ICON,
				texture = icon, iconSize = REQ_ICON,
			})
			local copy = UI.Controls.copyText(card, {
				x = textX, y = y, w = textWIcon, text = spec.text,
				font = UIFont.Small, lineGap = LINE_GAP,
				tone = "recipeLine", theme = lineTheme(spec),
			})
			controls[#controls + 1] = copy
			y = y + copy.height
			if y < rowStart + iconRowH then
				y = rowStart + iconRowH
			end
		else
			local copy = UI.Controls.copyText(card, {
				x = pad, y = y, w = textW, text = spec.text,
				font = UIFont.Small, lineGap = LINE_GAP,
				tone = "recipeLine", theme = lineTheme(spec),
			})
			controls[#controls + 1] = copy
			y = y + copy.height
		end
	end
	return controls
end

local function findRecipeInState(state, recipeId)
	for recipeIndex = 1, #(state and state.recipes or {}) do
		local candidate = state.recipes[recipeIndex]
		if candidate.id == recipeId then return candidate end
	end
	return nil
end

local function findLiveRecipe(card, fallback)
	local owner = card.ownerUI
	local live = owner and findRecipeInState(owner.craftRecipesState, card.recipeId) or nil
	if live then return live end
	live = owner and findRecipeInState(owner.addonRecipesState, card.recipeId) or nil
	if live then return live end
	return fallback
end

local function presentationSignature(recipe, bodyLines)
	local values = {
		tostring(recipe.outputDisplay or recipe.id or ""),
		recipe.canCraft == true and "1" or "0",
	}
	for i = 1, #bodyLines do
		local spec = bodyLines[i]
		values[#values + 1] = table.concat({
			tostring(spec.text or ""), tostring(spec.r or ""),
			tostring(spec.g or ""), tostring(spec.b or ""),
			tostring(spec.itemType or spec.icon or ""),
		}, "|")
	end
	return table.concat(values, "\30")
end

local function syncCard(card, fallback)
	local liveRecipe = findLiveRecipe(card, fallback)
	local bodyLines = GlobalStorageSiK.TerminalRecipeCards.buildBodyLines(
		liveRecipe, card.textW)
	local signature = presentationSignature(liveRecipe, bodyLines)
	if signature ~= card._recipePresentationSignature then
		disposeControls(card._recipeBodyControls or {})
		card._recipeBodyControls = createBodyControls(card, bodyLines, card.textW,
			card.titleHeight + card.contentPad, card.contentPad)
		card._recipePresentationSignature = signature
		card.titleControl:setText(liveRecipe.outputDisplay or liveRecipe.id)
	end
	local canCraft = liveRecipe.canCraft == true
	card.craftBtn:setText(canCraft and T("IGUI_GS_CraftNow")
		or T("IGUI_GS_CraftMissing"))
	card.craftBtn:setLocked(not canCraft)
	card.craftBtn:setEnabled(canCraft)
end

--- Añade tarjeta de receta al scroll.
---@param scroll table
---@param recipe table
---@param y number
---@param cardW number
---@param owner table UI con craftRecipesState y onCraftModRecipe
---@param options table|nil { parent=ISUIElement|nil } declarative composition parent
---@return number cardHeight
---@return ISPanel card
function GlobalStorageSiK.TerminalRecipeCards.addCard(scroll, recipe, y, cardW, owner, options)
	options = options or {}
	local pad = 10
	local textW = math.max(220, cardW - pad * 2)
	local titleH = FONT_HGT_SMALL + 10
	local bodyH = GlobalStorageSiK.TerminalRecipeCards.measureBodyHeight(
		GlobalStorageSiK.TerminalRecipeCards.buildBodyLines(recipe, textW),
		textW
	)
	local cardH = titleH + pad + bodyH + CRAFT_BTN_H + 12

	local palette = UI.Theme.palette()
	local card = UI.Controls.panel(nil, {
		x = pad, y = y, w = cardW, h = cardH, drawBackground = true,
		backgroundColor = {
			r = palette.bgCard[1], g = palette.bgCard[2],
			b = palette.bgCard[3], a = 0.94,
		},
		borderColor = {
			r = palette.border[1] * 0.45, g = palette.border[2] * 0.45,
			b = palette.border[3] * 0.45, a = 0.35,
		},
	})
	card.textW = textW
	card.contentPad = pad
	card.titleHeight = titleH
	card.recipeId = recipe.id
	card.ownerUI = owner
	card.clipChildren = true
	local header = UI.Controls.panel(card, {
		x = 1, y = 1, w = math.max(1, cardW - 2), h = math.max(1, titleH - 1),
		drawBackground = true,
		backgroundColor = {
			r = palette.bgHeader[1], g = palette.bgHeader[2],
			b = palette.bgHeader[3], a = 0.98,
		},
		borderColor = { r = 0, g = 0, b = 0, a = 0 },
	})
	header.clipChildren = true
	card.titleControl = UI.Controls.copyText(header, {
		x = pad - 1, y = 2, w = math.max(1, textW),
		text = recipe.outputDisplay or recipe.id, font = UIFont.Small,
		lineGap = 0, tone = "text",
	})

	local btnTitle = recipe.canCraft and T("IGUI_GS_CraftNow") or T("IGUI_GS_CraftMissing")
	local craftBtn = UI.Controls.button(nil, {
		x = pad, y = cardH - CRAFT_BTN_H - 6, w = textW, h = CRAFT_BTN_H,
		text = btnTitle, enabled = recipe.canCraft == true,
		onClick = function()
			if owner and owner.onCraftModRecipe then owner:onCraftModRecipe(recipe.id) end
		end,
	})
	card.craftBtn = craftBtn
	card:addChild(craftBtn)
	card._recipeBodyControls = {}
	local previousUpdate = card.update
	card.update = function(panel)
		if type(previousUpdate) == "function" then previousUpdate(panel) end
		syncCard(panel, recipe)
	end
	local panelDispose = card.dispose
	card.dispose = function(panel)
		if panel._recipeCardDisposed then return false end
		panel._recipeCardDisposed = true
		disposeControls(panel._recipeBodyControls or {})
		if panel.craftBtn then panel.craftBtn:dispose(); panel.craftBtn = nil end
		if panel.titleControl then panel.titleControl:dispose(); panel.titleControl = nil end
		if header then header:dispose(); header = nil end
		return panelDispose(panel)
	end
	syncCard(card, recipe)

	if options.parent and options.parent.addChild then
		options.parent:addChild(card)
	else
		UI.Scroll.addChild(scroll, card)
	end
	return cardH, card
end
