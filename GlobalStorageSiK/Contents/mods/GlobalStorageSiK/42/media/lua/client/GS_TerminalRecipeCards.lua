--[[
	GlobalStorageSiK - Tarjetas de receta del terminal (cliente)
	Autor: SiK
	Fecha: 2025-06-25
	Descripción: UI compartida para recetas del mod (terminal, tableta).
]]

require "ISUI/ISPanel"
require "GS_I18n"
require "GS_CraftUtils"
require "GS_TerminalUI_Chrome"
require "GS_TerminalUI_Scroll"

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
local function pushWrappedLines(out, text, maxWidth, r, g, b)
	for _, line in ipairs(GlobalStorageSiK.TerminalChrome.wrapTextLines(text, maxWidth, UIFont.Small)) do
		table.insert(out, { text = line, r = r, g = g, b = b })
	end
end

--- Mide altura del cuerpo de una tarjeta.
--- IMPORTANTE: las filas con icono tambien envuelven su texto en varias
--- lineas si no cabe en el ancho reservado (ver drawBodyLines) — antes esta
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
			local wrappedH = GlobalStorageSiK.TerminalChrome.countWrappedLines(spec.text, textWIcon, UIFont.Small, LINE_GAP)
			h = h + math.max(iconRowH, wrappedH)
		else
			h = h + GlobalStorageSiK.TerminalChrome.countWrappedLines(spec.text, textW, UIFont.Small, LINE_GAP)
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
		local bookLine = recipe.knowsBook and T("IGUI_GS_ReqBookOk", recipe.manualDisplay or "?")
			or T("IGUI_GS_ReqBookMissing", recipe.manualDisplay or "?")
		table.insert(lines, { text = bookLine, r = bookR, g = bookG, b = bookB, itemType = recipe.manualItem })
	end
	if (recipe.skillLevel or 0) > 0 then
		local skillLine = T("IGUI_GS_CraftSkillReqLine", recipe.skillHave or 0, recipe.skillLevel or 0)
		local skR, skG, skB = recipe.skillOk and 0.5 or 0.82, recipe.skillOk and 0.78 or 0.32, recipe.skillOk and 0.5 or 0.32
		local skillIcon = Perks and Perks.Electricity and GlobalStorageSiK.CraftUtils.getPerkTexture(Perks.Electricity) or nil
		table.insert(lines, { text = skillLine, r = skR, g = skG, b = skB, icon = skillIcon })
	end
	if recipe.requireWorkbench then
		local wbR, wbG, wbB = recipe.nearWorkbench and 0.5 or 0.82, recipe.nearWorkbench and 0.78 or 0.32, recipe.nearWorkbench and 0.5 or 0.32
		local wbLine = recipe.nearWorkbench and T("IGUI_GS_ReqWorkbenchOk") or T("IGUI_GS_ReqWorkbenchMissing")
		pushWrappedLines(lines, wbLine, textWIcon, wbR, wbG, wbB)
	end
	if recipe.requireLight then
		local _lp = GlobalStorageSiK.TerminalChrome.PALETTE
		local ltR = recipe.hasCraftLight and _lp.statusOk[1] or _lp.statusDanger[1]
		local ltG = recipe.hasCraftLight and _lp.statusOk[2] or _lp.statusDanger[2]
		local ltB = recipe.hasCraftLight and _lp.statusOk[3] or _lp.statusDanger[3]
		local ltLine = recipe.hasCraftLight and T("IGUI_GS_ReqLightOk") or T("IGUI_GS_ReqLightMissing")
		pushWrappedLines(lines, ltLine, textWIcon, ltR, ltG, ltB)
	end
	local _ip = GlobalStorageSiK.TerminalChrome.PALETTE
	for j = 1, #(recipe.ingredients or {}) do
		local ing = recipe.ingredients[j]
		local colorR, colorG, colorB = _ip.statusDanger[1], _ip.statusDanger[2], _ip.statusDanger[3]
		if ing.ok or recipe.freeCraft then
			colorR, colorG, colorB = _ip.statusOk[1], _ip.statusOk[2], _ip.statusOk[3]
		end
		local line = string.format("%s  %d/%d", ing.displayName or ing.item, ing.have or 0, ing.count or 0)
		table.insert(lines, { text = line, r = colorR, g = colorG, b = colorB, itemType = ing.item })
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

--- Dibuja líneas del cuerpo de la tarjeta.
---@param panel ISPanel
---@param bodyLines table
---@param textW number
---@param startY number
---@param pad number
function GlobalStorageSiK.TerminalRecipeCards.drawBodyLines(panel, bodyLines, textW, startY, pad)
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
			panel:drawRect(pad - fp, iconY - fp, REQ_ICON + fp * 2, REQ_ICON + fp * 2, 0.9, 0.08, 0.08, 0.08)
			panel:drawRectBorder(pad - fp, iconY - fp, REQ_ICON + fp * 2, REQ_ICON + fp * 2, 0.8, spec.r or 1, spec.g or 1, spec.b or 1)
			panel:drawTextureScaledAspect(icon, pad, iconY, REQ_ICON, REQ_ICON, 1, 1, 1, 1)
			for _, line in ipairs(GlobalStorageSiK.TerminalChrome.wrapTextLines(spec.text, textWIcon, UIFont.Small)) do
				panel:drawText(line, textX, y, spec.r, spec.g, spec.b, 1, UIFont.Small)
				y = y + lh
			end
			if y < rowStart + iconRowH then
				y = rowStart + iconRowH
			end
		else
			for _, line in ipairs(GlobalStorageSiK.TerminalChrome.wrapTextLines(spec.text, textW, UIFont.Small)) do
				panel:drawText(line, pad, y, spec.r, spec.g, spec.b, 1, UIFont.Small)
				y = y + lh
			end
		end
	end
	return y
end

--- Añade tarjeta de receta al scroll.
---@param scroll ISPanel
---@param recipe table
---@param y number
---@param cardW number
---@param owner table UI con craftRecipesState y onCraftModRecipe
---@return number cardHeight
function GlobalStorageSiK.TerminalRecipeCards.addCard(scroll, recipe, y, cardW, owner)
	local pad = 10
	local textW = math.max(220, cardW - pad * 2)
	local titleH = FONT_HGT_SMALL + 10
	local bodyH = GlobalStorageSiK.TerminalRecipeCards.measureBodyHeight(
		GlobalStorageSiK.TerminalRecipeCards.buildBodyLines(recipe, textW),
		textW
	)
	local cardH = titleH + pad + bodyH + CRAFT_BTN_H + 12

	local card = ISPanel:new(pad, y, cardW, cardH)
	card:initialise()
	card.drawBackground = false
	card.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
	card.textW = textW
	card.contentPad = pad
	card.titleHeight = titleH
	card.recipeId = recipe.id
	card.ownerUI = owner
	card.clipChildren = true

	card.prerender = function(panel)
		ISPanel.prerender(panel)
		local liveRecipe = recipe
		local ui = panel.ownerUI
		if ui and ui.craftRecipesState and ui.craftRecipesState.recipes then
			for i = 1, #ui.craftRecipesState.recipes do
				local candidate = ui.craftRecipesState.recipes[i]
				if candidate.id == panel.recipeId then
					liveRecipe = candidate
					break
				end
			end
		end
		if ui and ui.addonRecipesState and ui.addonRecipesState.recipes then
			for i = 1, #ui.addonRecipesState.recipes do
				local candidate = ui.addonRecipesState.recipes[i]
				if candidate.id == panel.recipeId then
					liveRecipe = candidate
					break
				end
			end
		end
		local title = liveRecipe.outputDisplay or liveRecipe.id
		local bodyLines = GlobalStorageSiK.TerminalRecipeCards.buildBodyLines(liveRecipe, panel.textW)
		GlobalStorageSiK.TerminalChrome.drawCardBackground(panel, panel.titleHeight)
		local _rcp = GlobalStorageSiK.TerminalChrome.PALETTE
		panel:drawText(title, panel.contentPad, 3, _rcp.textPrimary[1], _rcp.textPrimary[2], _rcp.textPrimary[3], 1, UIFont.Small)
		GlobalStorageSiK.TerminalRecipeCards.drawBodyLines(panel, bodyLines, panel.textW, panel.titleHeight + panel.contentPad, panel.contentPad)
		if panel.craftBtn then
			local canCraft = liveRecipe.canCraft == true
			local newTitle = canCraft and T("IGUI_GS_CraftNow") or T("IGUI_GS_CraftMissing")
			panel.craftBtn._gsNeatLabel = newTitle
			panel.craftBtn:setEnable(canCraft)
		end
	end

	local btnTitle = recipe.canCraft and T("IGUI_GS_CraftNow") or T("IGUI_GS_CraftMissing")
	local craftBtn = GlobalStorageSiK.TerminalChrome.createNeatButton(
		pad, cardH - CRAFT_BTN_H - 6, 220, CRAFT_BTN_H, btnTitle, card, function()
		if owner and owner.onCraftModRecipe then
			owner:onCraftModRecipe(recipe.id)
		end
	end)
	craftBtn:setEnable(recipe.canCraft == true)
	card.craftBtn = craftBtn
	card:addChild(craftBtn)

	GlobalStorageSiK.TerminalScroll.addChild(scroll, card)
	return cardH
end
