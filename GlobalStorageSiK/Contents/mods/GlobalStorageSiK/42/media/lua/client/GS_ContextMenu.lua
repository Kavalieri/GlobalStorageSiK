--[[
	GlobalStorageSiK - Menú contextual unificado
	Autor: SiK
	Fecha: 2025-06-23
	Descripción: Todas las opciones del mod bajo «Global Storage».
]]

require "GS_Config"
require "GS_Utils"
require "GS_Network"
require "GS_Zones"
require "GS_Categories"
require "GS_ItemTaxonomy"
require "GS_NetClient"
require "GS_I18n"
-- Solo la API ligera (GlobalStorageSiK.TerminalUI.requestOpen/requestOpenAt),
-- no la implementacion GS_TerminalUI completa: esta ultima requiere
-- GS_TerminalUI_Items, que a su vez volvia a requerir este mismo fichero,
-- provocando un "recursive require" en la carga de B42.20.
require "GS_TerminalUI_Api"
require "GS_TerminalAccess"
require "GS_PlayerUtils"
require "GS_TerminalUI_NodeEditor"

require "ISUI/ISContextMenu"

GlobalStorageSiK.ContextMenu = GlobalStorageSiK.ContextMenu or {}

local T = GlobalStorageSiK.I18n.text

--- Crea el submenú raíz del mod en un context menu (sin caché: B42 reutiliza instancias).
---@param context ISContextMenu
---@return ISContextMenu|nil
function GlobalStorageSiK.ContextMenu.ensureRoot(context)
	if not context then
		return nil
	end
	local root
	if context.addOptionOnTop then
		root = context:addOptionOnTop(T("IGUI_GS_ContextMenu"))
	else
		root = context:addOption(T("IGUI_GS_ContextMenu"))
	end
	local subMenu = ISContextMenu:getNew(context)
	context:addSubMenu(root, subMenu)
	return subMenu
end

-- No hay menú contextual sobre objetos del MUNDO (cofres, muebles, ni el
-- propio terminal): clicar un mueble en B42 es incómodo y ya existe acceso
-- directo al mod desde el icono lateral (sidebar), así que no aporta nada.
-- Todo el menú "Global Storage" vive en el menú contextual del INVENTARIO
-- (ver GS_ItemActions.lua: disquete de instalación siempre disponible,
-- transferencia por bloques solo cuando el jugador está a rango de un
-- terminal activo).

