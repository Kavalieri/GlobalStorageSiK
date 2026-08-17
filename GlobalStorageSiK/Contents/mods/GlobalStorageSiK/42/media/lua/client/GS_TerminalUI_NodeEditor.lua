--[[
	GlobalStorageSiK - Editor modal de contenedor
	Autor: SiK
	Fecha: 2025-06-25
	Descripción: Ventana separada para editar un contenedor de red.
	Formulario fijo (no se reconstruye al recibir contenidos); solo se refresca el bloque de ítems.
]]

require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISLabel"
require "ISUI/ISTextEntryBox"
require "ISUI/ISComboBox"
require "GS_I18n"
require "GS_TerminalUI_Scroll"
require "GS_TerminalUI_Chrome"
require "GS_TerminalUI_Config"
require "GS_NetClient"
require "GS_NodeHighlight"
require "GS_NodeFilters"
require "GS_FilterEditor"
require "GS_CompatMods"

GlobalStorageSiK.TerminalNodeEditor = {}
GlobalStorageSiK.TerminalNodeEditor.instance = nil
-- Plantilla puramente temporal de esta sesion de cliente. No contiene
-- identidad fisica ni permisos: solo las reglas de destino que tiene sentido
-- repetir en muchos contenedores de una red grande.
GlobalStorageSiK.TerminalNodeEditor.configTemplate = nil

GS_NodeEditorUI = ISPanel:derive("GS_NodeEditorUI")

local T = GlobalStorageSiK.I18n.text
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local FONT_HGT_MEDIUM = getTextManager():getFontHeight(UIFont.Medium)
local ENTRY_H = FONT_HGT_SMALL + 6
local BTN_H = FONT_HGT_SMALL + 10
local PAD = 10
local RESIZE_GRAB = 12
local CONTENTS_TAG = "_gsNodeEditorContents"

local function cloneArray(source)
	local result = {}
	for i = 1, #(source or {}) do
		result[i] = source[i]
	end
	return result
end

local function cloneFilters(source)
	local result = {}
	for i = 1, #(source or {}) do
		local original = source[i]
		local copy = {}
		for key, value in pairs(original or {}) do
			copy[key] = value
		end
		result[i] = copy
	end
	return result
end

---@param x number
---@param y number
---@param w number
---@param title string
---@param target any
---@param onClick function
---@return ISButton
local function createBtn(x, y, w, title, target, onClick)
	return GlobalStorageSiK.TerminalChrome.createNeatButton(x, y, w, BTN_H, title, target, onClick)
end

function GS_NodeEditorUI:new(x, y, w, h)
	local o = ISPanel:new(x, y, w, h)
	setmetatable(o, self)
	self.__index = self
	o.moveWithMouse = false
	o.minimumWidth = 560
	o.minimumHeight = 480
	o.resizable = true
	o.resizing = false
	o.moving = false
	o.drawBackground = false
	o.backgroundColor = { r = 0.06, g = 0.06, b = 0.06, a = 0.98 }
	o.borderColor = { r = 0, g = 0, b = 0, a = 1 }
	o.padding = PAD
	o.headerHeight = math.floor(FONT_HGT_MEDIUM * 1.4)
	o._formBuilt = false
	o._contentsStartY = 0
	return o
end

function GS_NodeEditorUI:installMouseHandlers()
	self.onMouseDown = function(me, x, y)
		if x >= me.width - RESIZE_GRAB and y >= me.height - RESIZE_GRAB then
			me.resizing = true
			me:setCapture(true)
			return true
		end
		if y >= 0 and y < me.headerHeight and x < me.width - (me.closeBtn and me.closeBtn.width or 36) then
			me.moving = true
			me:setCapture(true)
			return true
		end
		return ISPanel.onMouseDown(me, x, y)
	end
	self.onMouseUp = function(me, x, y)
		if me.resizing or me.moving then
			me.resizing = false
			me.moving = false
			me:setCapture(false)
			me:calculateLayout()
			return true
		end
		return ISPanel.onMouseUp(me, x, y)
	end
	self.onMouseUpOutside = self.onMouseUp
	self.onMouseMove = function(me, dx, dy)
		if me.resizing then
			me:setWidth(math.max(me.minimumWidth, me.width + dx))
			me:setHeight(math.max(me.minimumHeight, me.height + dy))
			me:calculateLayout()
			return true
		end
		if me.moving then
			me:setX(me.x + dx)
			me:setY(me.y + dy)
			return true
		end
		return ISPanel.onMouseMove(me, dx, dy)
	end
	self.onMouseMoveOutside = self.onMouseMove
end

function GS_NodeEditorUI:initialise()
	ISPanel.initialise(self)
	self.clipChildren = true
	self:installMouseHandlers()
	self:setVisible(true)
	self:setAlwaysOnTop(true)
	self:createChildren()
	self:calculateLayout()
end

function GS_NodeEditorUI:createChildren()
	-- PZ llama createChildren desde instantiate() y nuestro initialise() también:
    -- guard para construir una sola vez (evita elementos huérfanos duplicados).
	if self._gsChildrenBuilt then return end
	self._gsChildrenBuilt = true
	self.closeBtn = GlobalStorageSiK.TerminalChrome.createCloseButton(self, self, function()
		GlobalStorageSiK.TerminalNodeEditor.close()
	end)
end

--- Actualiza título de ventana con el nombre del nodo en red.
function GS_NodeEditorUI:syncTitleFromName()
	local name = self.node and (self.node.displayName or self.node.name) or "?"
	self._titleText = T("IGUI_GS_NodeEditorTitle") .. ": " .. name
end

--- Envía cambios de nodo al servidor.
---@param nodeId string
---@param opts table  { displayName, categories, filters, enabled, membership, priority, notes }
--- Manda SOLO los campos presentes en opts (todos opcionales). Cada campo del
--- formulario tiene su propio boton "Aplicar" que llama esto con un unico
--- campo; nunca se resetean sin querer los demas (antes `categories` se
--- mandaba siempre, incluso vacio, si no se incluia explicitamente).
function GlobalStorageSiK.TerminalNodeEditor.sendNodeUpdate(nodeId, opts)
	local searchQuery = ""
	local ui = GlobalStorageSiK.TerminalUI and GlobalStorageSiK.TerminalUI.instance
	if ui and ui.searchEntry and ui.searchEntry.getText then
		searchQuery = ui.searchEntry:getText() or ""
	end
	local payload = { nodeId = nodeId, searchQuery = searchQuery }
	if opts.displayName ~= nil then payload.displayName = opts.displayName end
	if opts.categories  ~= nil then payload.categories  = opts.categories  end
	if opts.filters     ~= nil then payload.filters     = opts.filters     end
	if opts.enabled     ~= nil then payload.enabled     = opts.enabled     end
	if opts.membership  ~= nil then payload.membership  = opts.membership end
	if opts.priority    ~= nil then payload.priority    = opts.priority   end
	if opts.notes       ~= nil then payload.notes       = opts.notes      end
	GlobalStorageSiK.NetClient.sendCommand("updateNode", payload)
end

--- Captura la configuracion visible del editor. El nombre, la etiqueta, la
--- zona, el estado y la identidad del contenedor quedan fuera a proposito.
function GS_NodeEditorUI:copyConfigTemplate()
	if not self.node then return end
	local priority = tonumber(self.priorityEntry and self.priorityEntry:getText() or "")
		or self._editPriority or self.node.priority or 50
	priority = math.floor(priority + 0.5)
	if priority < 1 then priority = 1 elseif priority > 100 then priority = 100 end
	GlobalStorageSiK.TerminalNodeEditor.configTemplate = {
		sourceNodeId = self.node.id,
		sourceName = self.node.displayName or self.node.name or "?",
		categories = cloneArray(self._editCategories or self.node.categories),
		filters = cloneFilters(self.node.filters),
		priority = priority,
	}
	self:rebuildForm()
end

--- Sustituye de una vez las reglas de destino del nodo abierto. Se envia un
--- unico update acotado; el servidor vuelve a validar categorias, filtros y
--- prioridad y conserva intacta toda la metadata fisica/administrativa.
function GS_NodeEditorUI:pasteConfigTemplate()
	if not self.node then return end
	local template = GlobalStorageSiK.TerminalNodeEditor.configTemplate
	if not template then return end
	local categories = cloneArray(template.categories)
	local filters = cloneFilters(template.filters)
	local priority = tonumber(template.priority) or 50
	self._editCategories = categories
	self._editPriority = priority
	self.node.categories = cloneArray(categories)
	self.node.filters = cloneFilters(filters)
	self.node.priority = priority
	self:requestNodeUpdate({
		categories = categories,
		filters = filters,
		priority = priority,
	})
	self:rebuildForm()
end

--- Aplica y persiste inmediatamente un unico campo del formulario.
---@param field string "displayName"|"categories"|"priority"|"notes"
---@param value any
function GS_NodeEditorUI:applyField(field, value)
	if not self.node then return end
	GlobalStorageSiK.TerminalNodeEditor.sendNodeUpdate(self.node.id, { [field] = value })
end

function GS_NodeEditorUI:requestNodeUpdate(opts)
	if not self.node or not opts then return end
	GlobalStorageSiK.TerminalNodeEditor.sendNodeUpdate(self.node.id, opts)
end

function GS_NodeEditorUI:requestNodeContents(nodeId)
	if self.terminal and self.terminal.onRequestNodeContents then
		self.terminal:onRequestNodeContents(nodeId)
	else
		GlobalStorageSiK.NetClient.sendCommand("getNodeContents", { nodeId = nodeId })
	end
end

--- Ajusta el formulario al ancho actual. Con parejas campo+Aplicar y combos a
--- medias/tercios, replicar el calculo de anchos aqui duplicaria ensureForm();
--- mas simple y correcto reconstruir completo (rebuildForm ya preserva
--- nombre/notas/prioridad/categorias pendientes y el offset del scroll).
--- Guardia por ancho: durante un arrastre de redimensionado, calculateLayout
--- se llama en cada frame; sin esto reconstruiria todo el formulario cada
--- frame aunque solo cambiase el alto.
function GS_NodeEditorUI:layoutForm()
	if not self._formBuilt or not self.editorScroll then
		return
	end
	local innerW = GlobalStorageSiK.TerminalScroll.contentWidth(self.editorScroll)
	if self._lastLayoutW == innerW then
		return
	end
	self._lastLayoutW = innerW
	self:rebuildForm()
end

function GS_NodeEditorUI:calculateLayout()
	local w = self.width
	local h = self.height
	local pad = self.padding
	local closeSize = math.max(FONT_HGT_MEDIUM, 24)

	if self.closeBtn then
		self.closeBtn:setX(w - closeSize - pad)
		self.closeBtn:setY(math.floor((self.headerHeight - closeSize) / 2))
		self.closeBtn:setWidth(closeSize)
		self.closeBtn:setHeight(closeSize)
		self.closeBtn:bringToTop()
	end

	local bodyY = self.headerHeight + pad
	local bodyH = math.max(120, h - bodyY - pad - GlobalStorageSiK.TerminalScroll.listBottomGap())
	if self.editorScroll then
		self.editorScroll:setX(pad)
		self.editorScroll:setY(bodyY)
		GlobalStorageSiK.TerminalScroll.resize(self.editorScroll, w - pad * 2, bodyH)
		self:layoutForm()
		self:updateScrollHeight()
	end
end

function GS_NodeEditorUI:prerender()
	ISPanel.prerender(self)
	GlobalStorageSiK.TerminalChrome.renderPanelBackground(self)
	local title = self._titleText or T("IGUI_GS_NodeEditorTitle")
	local textX = self.padding + 2
	local titleY = math.floor((self.headerHeight - getTextManager():getFontHeight(UIFont.Medium)) / 2)
	self:drawText(title, textX, titleY, 1, 1, 1, 1, UIFont.Medium)
	if self.closeBtn then
		self.closeBtn:bringToTop()
	end
end

-- Los 5 huecos de joyeria reales (ver GS_Subcategories.lua:JEWELRY_SLOT_BUCKET) -
-- mismo enum ya establecido, no una lista nueva. Sirve para distinguir un
-- combo "categoria::hueco" de joyeria (necesita GSSub.jewelrySlotLabel) de
-- uno generico basado en BodyLocation cruda (necesita translateSubKey).
local JEWELRY_SLOT_KEYS = { ring = true, necklace = true, wrist = true, earring = true, nose = true }

--- Etiqueta traducida de una clave de categoria/subcategoria/hoja de
--- cualquier nivel (1, 2 o 3) - entiende los 2 prefijos de familia
--- (EXT_GROUP_PREFIX, SUBGROUP_PREFIX) y las claves combinadas "::" (hueco
--- de joyeria o de cualquier subcategoria vanilla, ej. Ropa por prenda).
---@param key string
---@return string
local function categoryDisplayLabel(key)
	if not key or key == "" then return "?" end
	local EXT = GlobalStorageSiK.ItemTaxonomy.EXT_GROUP_PREFIX
	local SUB = GlobalStorageSiK.ItemTaxonomy.SUBGROUP_PREFIX
	if key:sub(1, #EXT) == EXT then
		return GlobalStorageSiK.ItemTaxonomy.hierarchyLabel(key:sub(#EXT + 1), nil)
	end
	if key:sub(1, #SUB) == SUB then
		-- Nivel 2 completo: "groupKey::subGroupKey" canonicos.
		local rest = key:sub(#SUB + 1)
		local sepPos = rest:find("::", 1, true)
		if sepPos then
			local groupKey = rest:sub(1, sepPos - 1)
			local subKey = rest:sub(sepPos + 2)
			return GlobalStorageSiK.ItemTaxonomy.hierarchyLabel(groupKey, nil) .. " - "
				.. GlobalStorageSiK.ItemTaxonomy.hierarchyLabel(subKey, groupKey)
		end
		return rest
	end
	local sepPos = key:find("::", 1, true)
	if sepPos then
		-- Nivel 3 por combo (hueco de joyeria o subcategoria vanilla cruda,
		-- ej. la prenda exacta de Ropa) - ver GS_ItemTaxonomy.collectLeafFilters.
		local mainPart = key:sub(1, sepPos - 1)
		local slotPart = key:sub(sepPos + 2)
		local mainLabel = GlobalStorageSiK.ItemTaxonomy.translateMainKey(mainPart)
		local slotLower = string.lower(slotPart)
		local slotLabel
		if JEWELRY_SLOT_KEYS[slotLower] and GlobalStorageSiK.Subcategories and GlobalStorageSiK.Subcategories.jewelrySlotLabel then
			slotLabel = GlobalStorageSiK.Subcategories.jewelrySlotLabel(slotLower)
		else
			slotLabel = GlobalStorageSiK.ItemTaxonomy.translateSubKey(slotPart, mainPart, nil) or slotPart
		end
		return mainLabel .. " - " .. slotLabel
	end
	local GSSub = GlobalStorageSiK.Subcategories
	if GSSub and GSSub.isSubcategoryKey and GSSub.isSubcategoryKey(key) then
		return GSSub.label(key)
	end
	return GlobalStorageSiK.ItemTaxonomy.translateMainKey(key)
end

--- Construye el formulario de edición una sola vez (o reconstruye si _formBuilt=false).
function GS_NodeEditorUI:ensureForm()
	local terminal = self.terminal
	local node = self.node
	if not terminal or not node or not self.editorScroll then
		return
	end
	if self._formBuilt then
		self:layoutForm()
		return
	end

	local scroll = self.editorScroll
	GlobalStorageSiK.TerminalScroll.clear(scroll, false)

	local pad = 8
	local y = pad
	local innerW = GlobalStorageSiK.TerminalScroll.contentWidth(scroll)
	local currentlyEnabled = node.enabled ~= false
	local isExcluded       = node.membership == "excluded"

	-- Usar estado de edición pendiente si existe (sobrevive a rebuildForm)
	local editName     = self._editName     or node.displayName or node.name or ""
	local editNotes    = self._editNotes    or node.notes or ""
	local editPriority = self._editPriority or node.priority or 50

	-- Con Customizable Containers instalado, nuestro campo "Etiqueta" ES su
	-- etiqueta (una sola fuente de verdad, no dos campos "sincronizados"): al
	-- abrir el editor, su etiqueta manda si existe. Si CC no tiene aun
	-- etiqueta para este contenedor, partimos de nuestra nota guardada.
	if self._editNotes == nil then
		local ccLabel = GlobalStorageSiK.CompatMods.getContainerLabelText(node, getSpecificPlayer(0))
		if ccLabel and ccLabel ~= "" then
			editNotes = ccLabel
			self._editNotes = ccLabel
		end
	end
	if not self._editCategories then
		self._editCategories = {}
		for i, cat in ipairs(node.categories or {}) do self._editCategories[i] = cat end
	end

	-- ── Hint ─────────────────────────────────────────────────────────────
	local hintLbl = ISLabel:new(pad, y, FONT_HGT_SMALL, T("IGUI_GS_NodeEditorHint"), 0.5, 0.54, 0.58, 1, UIFont.Small, true)
	hintLbl:initialise()
	GlobalStorageSiK.TerminalScroll.addChild(scroll, hintLbl)
	y = y + FONT_HGT_SMALL + 8

	-- ── Plantilla rapida de configuracion ─────────────────────────────────
	local templateTitle = ISLabel:new(pad, y, FONT_HGT_SMALL, T("IGUI_GS_NodeConfigTemplateTitle"), 0.68, 0.72, 0.76, 1, UIFont.Small, true)
	templateTitle:initialise()
	GlobalStorageSiK.TerminalScroll.addChild(scroll, templateTitle)
	y = y + FONT_HGT_SMALL + 3
	local template = GlobalStorageSiK.TerminalNodeEditor.configTemplate
	local templateStatus = template
		and T("IGUI_GS_NodeConfigTemplateReady", template.sourceName or "?", #(template.categories or {}), #(template.filters or {}), template.priority or 50)
		or T("IGUI_GS_NodeConfigTemplateEmpty")
	local statusText = GlobalStorageSiK.TerminalChrome.truncateText(templateStatus, innerW, UIFont.Small)
	self.configTemplateStatusLbl = ISLabel:new(pad, y, FONT_HGT_SMALL, statusText, 0.5, 0.54, 0.58, 1, UIFont.Small, true)
	self.configTemplateStatusLbl:initialise()
	GlobalStorageSiK.TerminalScroll.addChild(scroll, self.configTemplateStatusLbl)
	y = y + FONT_HGT_SMALL + 4
	local templateGap = 4
	local templateBtnW = math.floor((innerW - templateGap) / 2)
	self.copyConfigBtn = createBtn(pad, y, templateBtnW, T("IGUI_GS_NodeConfigCopy"), scroll, function()
		self:copyConfigTemplate()
	end)
	if self.copyConfigBtn.setToolTipMap then
		self.copyConfigBtn:setToolTipMap({ toolTip = T("IGUI_GS_NodeConfigCopyTooltip") })
	end
	GlobalStorageSiK.TerminalScroll.addChild(scroll, self.copyConfigBtn)
	self.pasteConfigBtn = createBtn(pad + templateBtnW + templateGap, y, templateBtnW, T("IGUI_GS_NodeConfigPaste"), scroll, function()
		self:pasteConfigTemplate()
	end)
	self.pasteConfigBtn:setEnable(template ~= nil)
	if self.pasteConfigBtn.setToolTipMap then
		self.pasteConfigBtn:setToolTipMap({ toolTip = T("IGUI_GS_NodeConfigPasteTooltip") })
	end
	GlobalStorageSiK.TerminalScroll.addChild(scroll, self.pasteConfigBtn)
	y = y + BTN_H + 12

	local applyW = 70

	-- ── Nombre (Aplicar unificado mas abajo, junto a Prioridad y Notas) ─────
	self.nameLbl = ISLabel:new(pad, y, FONT_HGT_SMALL, T("IGUI_GS_NodeRenameLabel"), 0.68, 0.72, 0.76, 1, UIFont.Small, true)
	self.nameLbl:initialise()
	GlobalStorageSiK.TerminalScroll.addChild(scroll, self.nameLbl)
	y = y + FONT_HGT_SMALL + 2

	self.nameEntry = ISTextEntryBox:new(editName, pad, y, innerW, ENTRY_H)
	self.nameEntry:initialise()
	GlobalStorageSiK.TerminalChrome.styleTextEntry(self.nameEntry)
	self.nameEntry:instantiate()
	GlobalStorageSiK.TerminalScroll.addChild(scroll, self.nameEntry)
	y = y + ENTRY_H + 10

	-- ── Categorias aceptadas ─────────────────────────────────────────────
	self.catLbl = ISLabel:new(pad, y, FONT_HGT_SMALL, T("IGUI_GS_NodeCategoriesLabel"), 0.68, 0.72, 0.76, 1, UIFont.Small, true)
	self.catLbl:initialise()
	GlobalStorageSiK.TerminalScroll.addChild(scroll, self.catLbl)
	y = y + FONT_HGT_SMALL + 4

	-- Calcular altura de chips ANTES de crear los widgets de abajo
	local CHIP_H   = FONT_HGT_SMALL + 8
	local CHIP_PAD = 3
	local cats = self._editCategories or {}
	local chipsH = (#cats == 0)
		and (CHIP_PAD + FONT_HGT_SMALL + CHIP_PAD * 2)
		or  (CHIP_PAD + #cats * (CHIP_H + CHIP_PAD) + CHIP_PAD)

	-- Panel de chips con altura exacta
	self._chipsStartY = y
	self.catChipsHost = ISPanel:new(pad, y, innerW - pad, chipsH)
	self.catChipsHost:initialise()
	self.catChipsHost.drawBackground = false
	self.catChipsHost.backgroundColor = { r=0,g=0,b=0,a=0 }
	self.catChipsHost.borderColor     = { r=0,g=0,b=0,a=0 }
	GlobalStorageSiK.TerminalScroll.addChild(scroll, self.catChipsHost)
	y = y + chipsH + 4

	-- Categoria > Subcategoria > Sub-subcategoria: 3 desplegables en cascada,
	-- SIEMPRE los 3 visibles (si un nivel no tiene opciones para lo elegido
	-- arriba, solo queda seleccionable "Cualquiera"). A diferencia de Almacen
	-- aqui se listan TODAS las categorias del catalogo del juego, no solo lo
	-- que la red tiene ahora - el jugador debe poder preparar un filtro para
	-- algo que todavia no tiene (ver GS_ItemTaxonomy.lua:getFullCatalogRows).
	local networkItems = (self.terminal and self.terminal.terminalState and self.terminal.terminalState.items) or {}

	local comboGap = 4
	local comboThirdW = math.floor((innerW - pad * 2 - comboGap * 2) / 3)
	local col2X = pad + comboThirdW + comboGap
	local col3X = col2X + comboThirdW + comboGap

	self.catMainCombo = ISComboBox:new(pad, y, comboThirdW, ENTRY_H, scroll, nil)
	self.catMainCombo:initialise()
	GlobalStorageSiK.TerminalChrome.styleComboBox(self.catMainCombo)
	GlobalStorageSiK.TerminalConfig.fillMainCategoryCombo(self.catMainCombo, networkItems, "")
	GlobalStorageSiK.TerminalScroll.addChild(scroll, self.catMainCombo)

	self.catSubCombo = ISComboBox:new(col2X, y, comboThirdW, ENTRY_H, scroll, nil)
	self.catSubCombo:initialise()
	GlobalStorageSiK.TerminalChrome.styleComboBox(self.catSubCombo)
	GlobalStorageSiK.TerminalConfig.fillSubCategoryCombo(self.catSubCombo, "", "", networkItems)
	GlobalStorageSiK.TerminalScroll.addChild(scroll, self.catSubCombo)

	self.catLeafCombo = ISComboBox:new(col3X, y, comboThirdW, ENTRY_H, scroll, nil)
	self.catLeafCombo:initialise()
	GlobalStorageSiK.TerminalChrome.styleComboBox(self.catLeafCombo)
	GlobalStorageSiK.TerminalConfig.fillLeafCategoryCombo(self.catLeafCombo, "", "", "")
	GlobalStorageSiK.TerminalScroll.addChild(scroll, self.catLeafCombo)

	self.catMainCombo.onChange = function()
		local mainKey = GlobalStorageSiK.TerminalConfig.getSelectedCategory(self.catMainCombo)
		GlobalStorageSiK.TerminalConfig.fillSubCategoryCombo(self.catSubCombo, mainKey, "", networkItems)
		GlobalStorageSiK.TerminalConfig.fillLeafCategoryCombo(self.catLeafCombo, mainKey, "", "")
	end
	self.catSubCombo.onChange = function()
		local mainKey = GlobalStorageSiK.TerminalConfig.getSelectedCategory(self.catMainCombo)
		local subKey = GlobalStorageSiK.TerminalConfig.getSelectedCategory(self.catSubCombo)
		GlobalStorageSiK.TerminalConfig.fillLeafCategoryCombo(self.catLeafCombo, mainKey, subKey, "")
	end
	y = y + ENTRY_H + 4

	self.catApplyBtn = createBtn(pad, y, innerW, T("IGUI_GS_Apply"), scroll, function()
		local mainKey = GlobalStorageSiK.TerminalConfig.getSelectedCategory(self.catMainCombo)
		local subKey  = GlobalStorageSiK.TerminalConfig.getSelectedCategory(self.catSubCombo)
		local leafKey = GlobalStorageSiK.TerminalConfig.getSelectedCategory(self.catLeafCombo)
		-- Se guarda SIEMPRE la clave del nivel MAS ESPECIFICO elegido (hoja >
		-- subcategoria > categoria). Elegir un nivel sin bajar a los mas
		-- especificos es valido y util a proposito: la clave de Nivel 1/2
		-- lleva un prefijo (GS_ItemTaxonomy.EXT_GROUP_PREFIX/SUBGROUP_PREFIX)
		-- que GS_Router.lua entiende como "toda la familia"/"todo el
		-- subgrupo" al depositar - sin tener que marcar cada variante a mano.
		local key = (leafKey ~= "" and leafKey) or (subKey ~= "" and subKey) or (mainKey ~= "" and mainKey) or nil
		if not key then return end
		self._editCategories = self._editCategories or {}
		for _, existing in ipairs(self._editCategories) do
			if string.lower(existing) == string.lower(key) then return end
		end
		self._editCategories[#self._editCategories + 1] = key
		self:applyField("categories", self._editCategories)
		self:rebuildForm()
	end)
	if self.catApplyBtn.setToolTipMap then
		self.catApplyBtn:setToolTipMap({ toolTip = "Anadir la categoria/subcategoria/hoja elegida a las aceptadas y guardar en el servidor. Cuanto mas concreto el nivel elegido, mas prioridad tendra este contenedor al depositar ese tipo de item." })
	end
	GlobalStorageSiK.TerminalScroll.addChild(scroll, self.catApplyBtn)
	y = y + BTN_H + 8

	-- ── Categoria sugerida ────────────────────────────────────────────────
	local sugKey = self.node and GlobalStorageSiK.ItemTaxonomy and GlobalStorageSiK.ItemTaxonomy.suggestCategoryForNode
		and GlobalStorageSiK.ItemTaxonomy.suggestCategoryForNode(self.node) or nil
	if sugKey and sugKey ~= "" then
		local sugLabel = T("IGUI_GS_NodeSuggestedCat") .. " " .. categoryDisplayLabel(sugKey)
		local sugLbl = ISLabel:new(pad, y, FONT_HGT_SMALL, sugLabel, 0.35, 0.75, 0.45, 1, UIFont.Small, true)
		sugLbl:initialise()
		GlobalStorageSiK.TerminalScroll.addChild(scroll, sugLbl)
		y = y + FONT_HGT_SMALL + 4
		-- Boton "Aplicar sugerida"
		local applyBtn = createBtn(pad, y, innerW, T("IGUI_GS_NodeApplySuggested"), scroll, function()
			if not sugKey then return end
			for _, existing in ipairs(self._editCategories or {}) do
				if string.lower(existing) == string.lower(sugKey) then return end
			end
			self._editCategories = self._editCategories or {}
			self._editCategories[#self._editCategories + 1] = sugKey
			self:applyField("categories", self._editCategories)
			self:rebuildForm()
		end)
		if applyBtn.setToolTipMap then
			applyBtn:setToolTipMap({ toolTip = "Anadir la categoria sugerida automaticamente basada en el contenido actual del contenedor." })
		end
		GlobalStorageSiK.TerminalScroll.addChild(scroll, applyBtn)
		y = y + BTN_H + 8
	end

	-- ── Filtros personalizados ───────────────────────────────────────────
	-- Ademas de categorias/subcategorias: reglas propias (nombre, peso, tag
	-- vanilla, item exacto) que un item puede cumplir para que este nodo lo
	-- acepte, con la MISMA prioridad que una subcategoria exacta (ver
	-- GS_Router.matchSpecificity). Se listan como chips, igual que las
	-- categorias, con su propio boton de quitar.
	self.filtersLbl = ISLabel:new(pad, y, FONT_HGT_SMALL, T("IGUI_GS_NodeFiltersLabel"), 0.68, 0.72, 0.76, 1, UIFont.Small, true)
	self.filtersLbl:initialise()
	GlobalStorageSiK.TerminalScroll.addChild(scroll, self.filtersLbl)
	y = y + FONT_HGT_SMALL + 4

	local filters = (self.node and self.node.filters) or {}
	local FILTER_CHIP_H = FONT_HGT_SMALL + 8
	local FILTER_CHIP_PAD = 3
	local filtersH = (#filters == 0)
		and (FILTER_CHIP_PAD + FONT_HGT_SMALL + FILTER_CHIP_PAD * 2)
		or  (FILTER_CHIP_PAD + #filters * (FILTER_CHIP_H + FILTER_CHIP_PAD) + FILTER_CHIP_PAD)
	self._filtersStartY = y
	self.filterChipsHost = ISPanel:new(pad, y, innerW - pad, filtersH)
	self.filterChipsHost:initialise()
	self.filterChipsHost.drawBackground = false
	self.filterChipsHost.backgroundColor = { r=0,g=0,b=0,a=0 }
	self.filterChipsHost.borderColor     = { r=0,g=0,b=0,a=0 }
	GlobalStorageSiK.TerminalScroll.addChild(scroll, self.filterChipsHost)
	y = y + filtersH + 4

	self.addFilterBtn = createBtn(pad, y, innerW, T("IGUI_GS_NodeAddFilterBtn"), scroll, function()
		if not self.node then return end
		GlobalStorageSiK.FilterEditor.show(self.node, function()
			self:rebuildForm()
		end)
	end)
	GlobalStorageSiK.TerminalScroll.addChild(scroll, self.addFilterBtn)
	y = y + BTN_H + 8

	-- ── Prioridad de llenado (escala 1-100, 1 = maxima) ────────────────────
	-- Etiqueta + pista en 2 lineas (no concatenadas): en paneles estrechos la
	-- pista desbordaba el ancho disponible en una sola linea.
	self.priorityLbl = ISLabel:new(pad, y, FONT_HGT_SMALL, T("IGUI_GS_NodePriorityLabel"), 0.68, 0.72, 0.76, 1, UIFont.Small, true)
	self.priorityLbl:initialise()
	GlobalStorageSiK.TerminalScroll.addChild(scroll, self.priorityLbl)
	y = y + FONT_HGT_SMALL + 2
	self.priorityHintLbl = ISLabel:new(pad, y, FONT_HGT_SMALL, T("IGUI_GS_NodePriorityHint"), 0.5, 0.54, 0.58, 1, UIFont.Small, true)
	self.priorityHintLbl:initialise()
	GlobalStorageSiK.TerminalScroll.addChild(scroll, self.priorityHintLbl)
	y = y + FONT_HGT_SMALL + 2

	self.priorityEntry = ISTextEntryBox:new(tostring(editPriority), pad, y, innerW, ENTRY_H)
	self.priorityEntry:initialise()
	GlobalStorageSiK.TerminalChrome.styleTextEntry(self.priorityEntry)
	self.priorityEntry:instantiate()
	if self.priorityEntry.setOnlyNumbers then self.priorityEntry:setOnlyNumbers(true) end
	GlobalStorageSiK.TerminalScroll.addChild(scroll, self.priorityEntry)
	y = y + ENTRY_H + 4

	-- Atajos rapidos: fijan el valor Y lo aplican de inmediato (accion
	-- explicita de un solo valor conocido, no arriesga perder otro campo).
	local function applyPriorityValue(n)
		n = math.floor(n + 0.5)
		if n < 1 then n = 1 elseif n > 100 then n = 100 end
		self._editPriority = n
		if self.priorityEntry then self.priorityEntry:setText(tostring(n)) end
		self:applyField("priority", n)
	end
	local presetW = math.floor((innerW - 8) / 3)
	self.priorityPresetHighBtn = createBtn(pad, y, presetW, T("IGUI_GS_NodePriorityPresetHigh"), scroll, function() applyPriorityValue(10) end)
	GlobalStorageSiK.TerminalScroll.addChild(scroll, self.priorityPresetHighBtn)
	self.priorityPresetNormalBtn = createBtn(pad + presetW + 4, y, presetW, T("IGUI_GS_NodePriorityPresetNormal"), scroll, function() applyPriorityValue(50) end)
	GlobalStorageSiK.TerminalScroll.addChild(scroll, self.priorityPresetNormalBtn)
	self.priorityPresetLowBtn = createBtn(pad + (presetW + 4) * 2, y, presetW, T("IGUI_GS_NodePriorityPresetLow"), scroll, function() applyPriorityValue(90) end)
	GlobalStorageSiK.TerminalScroll.addChild(scroll, self.priorityPresetLowBtn)
	y = y + BTN_H + 10

	-- ── Notas / ubicacion (Aplicar unificado mas abajo) ─────────────────────
	self.notesLbl = ISLabel:new(pad, y, FONT_HGT_SMALL, T("IGUI_GS_NodeNotesLabel"), 0.68, 0.72, 0.76, 1, UIFont.Small, true)
	self.notesLbl:initialise()
	GlobalStorageSiK.TerminalScroll.addChild(scroll, self.notesLbl)
	y = y + FONT_HGT_SMALL + 2

	self.notesEntry = ISTextEntryBox:new(editNotes, pad, y, innerW, ENTRY_H)
	self.notesEntry:initialise()
	GlobalStorageSiK.TerminalChrome.styleTextEntry(self.notesEntry)
	self.notesEntry:instantiate()
	if self.notesEntry.setToolTipMap then
		self.notesEntry:setToolTipMap({ toolTip = T("IGUI_GS_NodeNotesHint") })
	end
	GlobalStorageSiK.TerminalScroll.addChild(scroll, self.notesEntry)
	y = y + ENTRY_H + 8

	-- ── Aplicar TODO junto (nombre + prioridad + notas) ─────────────────────
	-- Antes cada campo tenia su propio "Aplicar"; si el jugador cambiaba
	-- varios y solo pulsaba uno, los demas quedaban sin guardar - un solo
	-- boton que manda TODO junto en un unico updateNode evita ese riesgo.
	self.applyAllBtn = createBtn(pad, y, innerW, T("IGUI_GS_ApplyAllChanges"), scroll, function()
		if not self.node then return end
		local name = self.nameEntry and self.nameEntry:getText() or ""
		local notes = self.notesEntry and self.notesEntry:getText() or ""
		local n = tonumber(self.priorityEntry and self.priorityEntry:getText() or "")
		self._editName = name
		self._editNotes = notes
		GlobalStorageSiK.CompatMods.pushContainerLabelText(self.node, getSpecificPlayer(0), notes)
		local opts = { displayName = name, notes = notes }
		if n then
			n = math.floor(n + 0.5)
			if n < 1 then n = 1 elseif n > 100 then n = 100 end
			self._editPriority = n
			self.priorityEntry:setText(tostring(n))
			opts.priority = n
		end
		self:requestNodeUpdate(opts)
		self:syncTitleFromName()
	end)
	if self.applyAllBtn.setToolTipMap then
		self.applyAllBtn:setToolTipMap({ toolTip = "Guarda nombre, prioridad y notas juntos en el servidor." })
	end
	GlobalStorageSiK.TerminalScroll.addChild(scroll, self.applyAllBtn)
	y = y + BTN_H + 12

	-- ── Botones accion ────────────────────────────────────────────────────
	local enabledLabel = currentlyEnabled and T("IGUI_GS_NodeBtnDisable") or T("IGUI_GS_NodeBtnEnable")
	self.toggleBtn = createBtn(pad, y, innerW, enabledLabel, scroll, function()
		local enabled = self.node and self.node.enabled ~= false
		self:requestNodeUpdate({ enabled = not enabled })
	end)
	if self.toggleBtn.setToolTipMap then
		self.toggleBtn:setToolTipMap({ toolTip = "Activar o desactivar este contenedor en la red. Un contenedor desactivado no recibe depositos automaticos." })
	end
	GlobalStorageSiK.TerminalScroll.addChild(scroll, self.toggleBtn)
	y = y + BTN_H + 4

	local membLabel = isExcluded and T("IGUI_GS_NodeBtnInclude") or T("IGUI_GS_NodeBtnExclude")
	self.membBtn = createBtn(pad, y, innerW, membLabel, scroll, function()
		local excluded = self.node and self.node.membership == "excluded"
		self:requestNodeUpdate(excluded and { enabled=true, membership="active" } or { enabled=false, membership="excluded" })
	end)
	if self.membBtn.setToolTipMap then
		self.membBtn:setToolTipMap({ toolTip = "Excluir este contenedor de la red (solo el tuyo). Excluido = invisible para deposito y extraccion desde el terminal." })
	end
	GlobalStorageSiK.TerminalScroll.addChild(scroll, self.membBtn)
	y = y + BTN_H + 12

	-- ── Contenido del contenedor ──────────────────────────────────────────
	local contentsTitle = ISLabel:new(pad, y, FONT_HGT_SMALL, T("IGUI_GS_NodeContentsTitle"), 0.88, 0.9, 0.94, 1, UIFont.Small, true)
	contentsTitle:initialise()
	self.contentsTitleLbl = contentsTitle
	GlobalStorageSiK.TerminalScroll.addChild(scroll, contentsTitle)
	y = y + FONT_HGT_SMALL + 8

	self._contentsStartY = y
	self._contentsFingerprint = nil
	self._formBuilt = true
	self:syncTitleFromName()
	self:rebuildCategoryChips()
	self:rebuildFilterChips()
	self:refreshContents()
end

--- Rellena los chips de categoria dentro de catChipsHost (sin reposicionar widgets externos).
--- La altura del host ya fue calculada correctamente en ensureForm.
function GS_NodeEditorUI:rebuildCategoryChips()
	if not self.catChipsHost then return end
	local host = self.catChipsHost
	for i = #(host.childrenInOrder or {}), 1, -1 do
		local ch = host.childrenInOrder[i]
		host:removeChild(ch)
		if ch.removeFromUIManager then ch:removeFromUIManager() end
	end

	local cats     = self._editCategories or {}
	local CHIP_H   = FONT_HGT_SMALL + 8
	local CHIP_PAD = 3
	local cy       = CHIP_PAD
	local hostW    = host.width
	local removeText = T("IGUI_GS_Remove")
	local removeBtnW = GlobalStorageSiK.TerminalChrome.measureNeatButtonWidth(removeText, UIFont.Small, 20, 52, 120)
	local labelMaxW = math.max(20, hostW - removeBtnW - 12)

	if #cats == 0 then
		local emptyLbl = ISLabel:new(4, cy, FONT_HGT_SMALL, T("IGUI_GS_NodeNoCats"), 0.45, 0.48, 0.52, 1, UIFont.Small, true)
		emptyLbl:initialise()
		host:addChild(emptyLbl)
	else
		for idx, cat in ipairs(cats) do
			local label = categoryDisplayLabel(cat)
			label = GlobalStorageSiK.TerminalChrome.truncateText(label, labelMaxW, UIFont.Small)
			local lbl = ISLabel:new(4, cy + 2, FONT_HGT_SMALL, label, 0.85, 0.9, 0.95, 1, UIFont.Small, true)
			lbl:initialise()
			host:addChild(lbl)

			local capturedIdx = idx
			local removeBtn = GlobalStorageSiK.TerminalChrome.createNeatButton(
				hostW - removeBtnW - 2, cy, removeBtnW, CHIP_H,
				removeText, host,
				function()
					table.remove(self._editCategories, capturedIdx)
					self:applyField("categories", self._editCategories)
					self:rebuildForm()
				end
			)
			if removeBtn.setToolTipMap then
				removeBtn:setToolTipMap({ toolTip = removeText })
			end
			host:addChild(removeBtn)
			cy = cy + CHIP_H + CHIP_PAD
		end
	end
	self:updateScrollHeight()
end

--- Rellena los chips de filtros personalizados dentro de filterChipsHost.
function GS_NodeEditorUI:rebuildFilterChips()
	if not self.filterChipsHost then return end
	local host = self.filterChipsHost
	for i = #(host.childrenInOrder or {}), 1, -1 do
		local ch = host.childrenInOrder[i]
		host:removeChild(ch)
		if ch.removeFromUIManager then ch:removeFromUIManager() end
	end

	local filters = (self.node and self.node.filters) or {}
	local CHIP_H   = FONT_HGT_SMALL + 8
	local CHIP_PAD = 3
	local cy       = CHIP_PAD
	local hostW    = host.width
	local removeText = T("IGUI_GS_Remove")
	local removeBtnW = GlobalStorageSiK.TerminalChrome.measureNeatButtonWidth(removeText, UIFont.Small, 20, 52, 120)
	local labelMaxW = math.max(20, hostW - removeBtnW - 12)

	if #filters == 0 then
		local emptyLbl = ISLabel:new(4, cy, FONT_HGT_SMALL, T("IGUI_GS_NodeNoFilters"), 0.45, 0.48, 0.52, 1, UIFont.Small, true)
		emptyLbl:initialise()
		host:addChild(emptyLbl)
	else
		for idx, filter in ipairs(filters) do
			local label = GlobalStorageSiK.NodeFilters.describe(filter)
			label = GlobalStorageSiK.TerminalChrome.truncateText(label, labelMaxW, UIFont.Small)
			local lbl = ISLabel:new(4, cy + 2, FONT_HGT_SMALL, label, 0.85, 0.9, 0.95, 1, UIFont.Small, true)
			lbl:initialise()
			host:addChild(lbl)

			local capturedIdx = idx
			local removeBtn = GlobalStorageSiK.TerminalChrome.createNeatButton(
				hostW - removeBtnW - 2, cy, removeBtnW, CHIP_H,
				removeText, host,
				function()
					if not self.node then return end
					GlobalStorageSiK.NetClient.sendCommand("updateNode", { nodeId = self.node.id, removeFilterIndex = capturedIdx })
					table.remove(self.node.filters, capturedIdx)
					self:rebuildFilterChips()
				end
			)
			if removeBtn.setToolTipMap then
				removeBtn:setToolTipMap({ toolTip = removeText })
			end
			host:addChild(removeBtn)
			cy = cy + CHIP_H + CHIP_PAD
		end
	end
	self:updateScrollHeight()
end

--- Guarda estado de edición, destruye y reconstruye el formulario.
function GS_NodeEditorUI:rebuildForm()
	if not self.editorScroll then return end
	-- Preservar estado del formulario
	if self.nameEntry  then self._editName  = self.nameEntry:getText()  end
	if self.notesEntry then self._editNotes = self.notesEntry:getText() end
	if self.priorityEntry then
		local n = tonumber(self.priorityEntry:getText())
		if n then self._editPriority = n end
	end
	local savedOffset = GlobalStorageSiK.TerminalScroll.getScrollOffset(self.editorScroll)
	self:resetForm()
	self:ensureForm()
	GlobalStorageSiK.TerminalScroll.setScrollOffset(self.editorScroll, savedOffset)
end

--- Actualiza etiquetas de botones según estado actual del nodo.
--- NO toca nameEntry/notesEntry/priorityEntry: son campos de edicion en curso
--- del jugador, y esta funcion se dispara en cada sync de red desde el
--- servidor (syncNodeData), que puede llegar en cualquier momento mientras el
--- editor esta abierto. Pisarlos aqui perdia silenciosamente texto/valores
--- pendientes de "Aplicar". El refresco real desde servidor ya ocurre en
--- setNode()/rebuildForm() al cambiar de nodo o justo tras aplicar un campo.
function GS_NodeEditorUI:syncFormButtons()
	if not self.node then
		return
	end
	local enabled  = self.node.enabled ~= false
	local excluded = self.node.membership == "excluded"
	if self.toggleBtn and self.toggleBtn.setTitle then
		self.toggleBtn:setTitle(enabled and T("IGUI_GS_NodeBtnDisable") or T("IGUI_GS_NodeBtnEnable"))
	end
	if self.membBtn and self.membBtn.setTitle then
		self.membBtn:setTitle(excluded and T("IGUI_GS_NodeBtnInclude") or T("IGUI_GS_NodeBtnExclude"))
	end
	self:rebuildCategoryChips()
	self:rebuildFilterChips()
end

--- Huella del bloque de contenido para evitar reconstrucciones redundantes.
---@param node table
---@return string
local function contentsFingerprint(node)
	local cache = GlobalStorageSiK.Client and GlobalStorageSiK.Client.nodeContentsCache or {}
	local payload = cache[node.id] or {}
	local rows = payload.rows or {}
	local rowCount = #rows
	local firstType = rowCount > 0 and (rows[1].fullType or "") or ""
	return string.format(
		"%s|%s|%s|%d|%s",
		tostring(payload.source or ""),
		tostring(payload.suggestedCategory or ""),
		tostring(rowCount),
		tostring(node.itemTypeCount or 0),
		firstType
	)
end

--- Actualiza solo el bloque de contenido del contenedor (sin tocar el formulario).
function GS_NodeEditorUI:refreshContents()
	if not self._formBuilt or not self.editorScroll or not self.node or not self.terminal then
		return
	end

	local fp = contentsFingerprint(self.node)
	if self._contentsFingerprint == fp then
		return
	end
	self._contentsFingerprint = fp

	local scroll = self.editorScroll
	local savedOffset = GlobalStorageSiK.TerminalScroll.getScrollOffset(scroll)
	local innerW = GlobalStorageSiK.TerminalScroll.contentWidth(scroll)

	self:ensureContentsHost()
	if not self.contentsHost then
		return
	end

	self.contentsHost:setX(8)
	self.contentsHost:setY(self._contentsStartY or 0)
	self.contentsHost:setWidth(innerW)
	self:clearContentsHost()
	self:syncFormButtons()

	local yEnd = GlobalStorageSiK.TerminalConfig.renderNodeContentsBlock(
		self.contentsHost, self.terminal, self.node, 0, 8, innerW, { plainHost = true }
	)

	self.contentsHost:setHeight(math.max(40, yEnd + 4))
	self._lastContentBottom = (self._contentsStartY or 0) + self.contentsHost:getHeight() + 8
	self:updateScrollHeight(self._lastContentBottom)
	GlobalStorageSiK.TerminalScroll.setScrollOffset(scroll, savedOffset)
end

--- Recalcula altura scrollable del panel.
--- Sin argumento, usa la ultima altura total conocida (self._lastContentBottom),
--- NO self._contentsStartY (que es solo el INICIO del bloque de contenido: usarlo
--- como fallback colapsaba el scroll cada vez que rebuildCategoryChips/syncFormButtons
--- se llamaban solos, p.ej. en cada sync de nodos desde el servidor con el editor abierto).
---@param contentBottom number|nil
function GS_NodeEditorUI:updateScrollHeight(contentBottom)
	if not self.editorScroll then
		return
	end
	local bottom = contentBottom
	if not bottom then
		bottom = self._lastContentBottom or self._contentsStartY or 0
	end
	GlobalStorageSiK.TerminalScroll.setContentHeight(self.editorScroll, bottom)
end

--- Reconstruye formulario al cambiar de nodo (preserva _editCategories, _editName, etc.).
function GS_NodeEditorUI:resetForm()
	if self.contentsHost then
		self:clearContentsHost()
		if self.editorScroll then
			local host = GlobalStorageSiK.TerminalScroll.childHost(self.editorScroll)
			if host and host.removeChild then
				host:removeChild(self.contentsHost)
			end
			if self.contentsHost.destroy then
				self.contentsHost:destroy()
			end
		end
	end
	self._formBuilt = false
	self.nameLbl         = nil
	self.nameEntry       = nil
	self.catLbl          = nil
	self.catChipsHost    = nil
	self.filtersLbl      = nil
	self.filterChipsHost = nil
	self.addFilterBtn    = nil
	self.catMainCombo    = nil
	self.catSubCombo     = nil
	self.catApplyBtn     = nil
	self.toggleBtn       = nil
	self.membBtn         = nil
	self.priorityLbl     = nil
	self.priorityHintLbl = nil
	self.priorityEntry   = nil
	self.priorityPresetHighBtn   = nil
	self.priorityPresetNormalBtn = nil
	self.priorityPresetLowBtn    = nil
	self.notesLbl        = nil
	self.notesEntry      = nil
	self.applyAllBtn     = nil
	self.configTemplateStatusLbl = nil
	self.copyConfigBtn   = nil
	self.pasteConfigBtn  = nil
	self.contentsTitleLbl = nil
	self.contentsHost    = nil
	self._contentsStartY = 0
	self._contentsFingerprint = nil
	self._lastContentBottom = nil
	self._chipsStartY    = 0
end

--- Elimina hijos del panel de contenido dinámico.
function GS_NodeEditorUI:clearContentsHost()
	local host = self.contentsHost
	if not host or not host.childrenInOrder then
		return
	end
	for i = #host.childrenInOrder, 1, -1 do
		local child = host.childrenInOrder[i]
		host:removeChild(child)
		if child.removeFromUIManager then
			child:removeFromUIManager()
		end
		if child.destroy then
			child:destroy()
		end
	end
end

--- Crea panel interno para contenido dinámico (se vacía en cada refresh).
function GS_NodeEditorUI:ensureContentsHost()
	if self.contentsHost and self.contentsHost.parent then
		return
	end
	local scroll = self.editorScroll
	if not scroll then
		return
	end
	local pad = 8
	local innerW = GlobalStorageSiK.TerminalScroll.contentWidth(scroll)
	self.contentsHost = ISPanel:new(pad, self._contentsStartY or 0, innerW, 40)
	self.contentsHost:initialise()
	self.contentsHost.drawBackground = false
	self.contentsHost.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
	self.contentsHost.borderColor = { r = 0, g = 0, b = 0, a = 0 }
	self.contentsHost.clipChildren = false
	GlobalStorageSiK.TerminalScroll.addChild(scroll, self.contentsHost)
end

--- Asigna nodo y reconstruye UI.
---@param terminal GS_TerminalUI
---@param node table
---@param categories string[]
function GS_NodeEditorUI:setNode(terminal, node, categories)
	local sameNode = self.node and node and self.node.id == node.id
	self.terminal = terminal
	self.node = node
	self.categories = categories or {}
	-- Inicializar estado de edición al abrir un nodo nuevo
	if not sameNode then
		self._editCategories = {}
		local migrated = false
		local seen = {}
		local catalog = GlobalStorageSiK.ItemTaxonomy.getFullCatalogRows()
		for _, cat in ipairs(node.categories or {}) do
			local canonical = GlobalStorageSiK.ItemTaxonomy.canonicalizeFilterRule(cat, catalog)
			if canonical ~= cat then migrated = true end
			local sig = string.lower(canonical)
			if not seen[sig] then
				seen[sig] = true
				self._editCategories[#self._editCategories + 1] = canonical
			end
		end
		-- Migracion unica de reglas antiguas que guardaban textos traducidos.
		-- Solo afecta a los prefijos virtuales de Nivel 1/2; las hojas exactas
		-- y categoria::hueco de joyeria/ropa pasan intactas.
		if migrated then
			node.categories = self._editCategories
			GlobalStorageSiK.TerminalNodeEditor.sendNodeUpdate(node.id, { categories = self._editCategories })
		end
		self._editName     = node.displayName or node.name or ""
		self._editNotes    = node.notes or ""
		self._editPriority = node.priority or 50
	end

	if not sameNode then
		self:resetForm()
	end

	if not self.editorScroll then
		self.editorScroll = GlobalStorageSiK.TerminalScroll.create(self, PAD, 0, 400, 200, "panel")
	end

	self:calculateLayout()
	self:ensureForm()
	self:syncTitleFromName()
	if sameNode then
		self._contentsFingerprint = nil
		self:refreshContents()
	end
	self:requestNodeContents(node.id)
end

--- Abre editor modal para un contenedor.
---@param terminal GS_TerminalUI|nil
---@param node table
---@param categories string[]
function GlobalStorageSiK.TerminalNodeEditor.open(terminal, node, categories)
	if not node then
		return
	end

	local existing = GlobalStorageSiK.TerminalNodeEditor.instance
	if existing and existing.node and existing.node.id == node.id then
		existing:bringToTop()
		return
	end

	GlobalStorageSiK.TerminalNodeEditor.close()

	local sw = getCore():getScreenWidth()
	local sh = getCore():getScreenHeight()
	local w = math.min(760, math.max(640, sw * 0.5))
	local h = math.min(820, math.max(600, sh * 0.72))

	-- Se abre superpuesto sobre la ventana del terminal (este donde este en
	-- pantalla), no centrado en toda la pantalla: asi el jugador ve su
	-- personaje/inventario al lado en vez de que el modal los tape.
	local x, y
	if terminal and terminal.getX and terminal.getY and terminal.getWidth and terminal.getHeight then
		x = terminal:getX() + (terminal:getWidth() - w) / 2
		y = terminal:getY() + (terminal:getHeight() - h) / 2
	else
		x = (sw - w) / 2
		y = (sh - h) / 2
	end
	x = math.floor(math.max(0, math.min(x, sw - w)))
	y = math.floor(math.max(0, math.min(y, sh - h)))

	local ui = GS_NodeEditorUI:new(x, y, w, h)
	ui:initialise()
	ui:addToUIManager()
	ui:setNode(terminal, node, categories)
	GlobalStorageSiK.TerminalNodeEditor.instance = ui
	-- Verificación de solapes del modal al abrir (gated por DebugMode).
	if GlobalStorageSiK.UIDebug and GlobalStorageSiK.UIDebug.checkOverlaps then
		GlobalStorageSiK.UIDebug.checkOverlaps(ui, "nodeEditor:open")
		GlobalStorageSiK.UIDebug.dumpTree(ui, "nodeEditor:open")
	end
	local allNodes = terminal and terminal.terminalState and terminal.terminalState.nodes or {}
	if GlobalStorageSiK.NodeHighlight and GlobalStorageSiK.NodeHighlight.highlightNode then
		GlobalStorageSiK.NodeHighlight.highlightNode(node, allNodes)
	end
end

--- Cierra editor si está abierto.
function GlobalStorageSiK.TerminalNodeEditor.close()
	local ui = GlobalStorageSiK.TerminalNodeEditor.instance
	if not ui then
		return
	end
	ui:setVisible(false)
	ui:removeFromUIManager()
	GlobalStorageSiK.TerminalNodeEditor.instance = nil
	if GlobalStorageSiK.NodeHighlight and GlobalStorageSiK.NodeHighlight.clear then
		GlobalStorageSiK.NodeHighlight.clear()
	end
end

--- Refresca contenido tras respuesta del servidor.
---@param args table|nil
function GlobalStorageSiK.TerminalNodeEditor.onContentsReceived(args)
	local ui = GlobalStorageSiK.TerminalNodeEditor.instance
	if not ui or not ui.node then
		return
	end
	local nodeId = args and args.nodeId
	if nodeId and ui.node.id ~= nodeId then
		return
	end
	ui._contentsFingerprint = nil
	ui:refreshContents()
end

--- Actualiza datos del nodo tras cambio de estado del terminal.
---@param terminal GS_TerminalUI
---@param nodes table[]
function GlobalStorageSiK.TerminalNodeEditor.syncNodeData(terminal, nodes)
	local ui = GlobalStorageSiK.TerminalNodeEditor.instance
	if not ui or not ui.node then
		return
	end
	for i = 1, #(nodes or {}) do
		if nodes[i].id == ui.node.id then
			local updated = nodes[i]
			ui.node = updated
			-- Sincronizar estado de edición con datos del servidor
			ui._editCategories = {}
			for j, cat in ipairs(updated.categories or {}) do ui._editCategories[j] = cat end
			ui._editName     = updated.displayName or updated.name or ""
			ui._editNotes    = updated.notes or ""
			ui._editPriority = updated.priority or 50
			ui:syncTitleFromName()
			ui:syncFormButtons()
			if GlobalStorageSiK.NodeNaming and GlobalStorageSiK.NodeNaming.applyToNode then
				GlobalStorageSiK.NodeNaming.applyToNode(updated)
			end
			return
		end
	end
end
