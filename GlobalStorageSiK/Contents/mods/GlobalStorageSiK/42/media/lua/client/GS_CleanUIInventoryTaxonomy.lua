--[[
	GlobalStorageSiK - Adaptador opcional CleanUI 42.19

	Decora exclusivamente el texto de categoria que CleanUI ya va a dibujar.
	No sustituye su renderer, no clasifica en render y no muta items, scripts,
	seleccion, orden, drag/drop, rareza ni columnas del proveedor.
]]

require "ISUI/ISInventoryPane"
require "GS_VanillaInventoryTaxonomy"
require "GS_Log"

GlobalStorageSiK.CleanUIInventoryTaxonomy = GlobalStorageSiK.CleanUIInventoryTaxonomy or {}
local Adapter = GlobalStorageSiK.CleanUIInventoryTaxonomy
local Projection = GlobalStorageSiK.VanillaInventoryTaxonomy
local rendering = setmetatable({}, { __mode = "k" })

local function isCleanUIActive()
	local mods = getActivatedMods and getActivatedMods()
	if not mods or not mods.contains then return false end
	return mods:contains("CleanUI")
end

function Adapter.install()
	if Adapter._installed or not isCleanUIActive() then return Adapter._installed == true end
	-- CleanUI ya estaba cargado cuando Core instalo su wrapper generico: ese
	-- wrapper soporta drawText y drawTextRight, por lo que no hace falta una
	-- segunda capa.
	if Projection.isRenderHookActive and Projection.isRenderHookActive() then
		Adapter._installed = true
		return true
	end
	if not ISInventoryPane or type(ISInventoryPane.renderdetails) ~= "function"
		or type(ISUIElement.drawText) ~= "function" or type(ISUIElement.drawTextRight) ~= "function"
		or not Projection or type(Projection.decorateDraw) ~= "function" then
		GlobalStorageSiK.Log.warn("CleanUITaxonomy", "adaptador desactivado: firma 42.19 no disponible")
		return false
	end

	local providerRender = ISInventoryPane.renderdetails
	local wrapper = function(pane, doDragged)
		if rendering[pane] then return providerRender(pane, doDragged) end
		rendering[pane] = true
		local drawText = pane.drawText
		local drawTextRight = pane.drawTextRight
		pane.drawText = function(self, text, x, y, r, g, b, a, font)
			return Projection.decorateDraw(self, drawText, false,
				text, x, y, r, g, b, a, font, doDragged)
		end
		pane.drawTextRight = function(self, text, x, y, r, g, b, a, font)
			return Projection.decorateDraw(self, drawTextRight, true,
				text, x, y, r, g, b, a, font, doDragged)
		end
		local ok, err = pcall(providerRender, pane, doDragged)
		pane.drawText = drawText
		pane.drawTextRight = drawTextRight
		rendering[pane] = nil
		if not ok then error(err) end
		if not doDragged and Projection.queueVisibleRows then Projection.queueVisibleRows(pane) end
	end

	Adapter._providerRender = providerRender
	Adapter._renderHook = wrapper
	ISInventoryPane.renderdetails = wrapper
	Adapter._installed = true
	GlobalStorageSiK.Log.debug("CleanUITaxonomy", "adaptador CleanUI 42.19 instalado")
	return true
end

local function installAfterMods()
	Adapter.install()
end

Events.OnGameStart.Add(installAfterMods)
Events.OnCreatePlayer.Add(installAfterMods)
