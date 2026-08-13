--[[
	GlobalStorageSiK - Atajo de teclado para abrir el terminal
	Autor: SiK
	Fecha: 2026-08-02
	Descripción: registra una entrada en la tabla global "keyBinding" (definida
	en keyBinding.lua, vanilla) para que aparezca en Opciones > Atajos de
	teclado como cualquier otro atajo del juego, completamente reconfigurable
	por el jugador desde ahi - no es un atajo fijo nuestro por fuera del
	sistema del juego.

	Tecla por defecto: F9. Ninguna de las teclas F1-F6, F10, F11 vanilla la usa
	(ver keyBinding.lua), y F7/F8/F9/F12 no aparecen usadas en ningun sitio del
	juego base - la mas segura frente a los mods que ya hemos revisado esta
	sesion (Extended Categories, Customizable Containers, Magic Accessories:
	ninguno registra atajos propios). No hay garantia absoluta frente a
	CUALQUIER mod de terceros, pero es una eleccion razonable y facil de
	cambiar por el jugador si choca con algo.
]]

GlobalStorageSiK.KeyBinding = {}

local BINDING_NAME = "GlobalStorageSiK Open Terminal"
GlobalStorageSiK.KeyBinding.NAME = BINDING_NAME

--- Nombre legible de la tecla asignada actualmente (refleja lo que el
--- jugador haya configurado en Opciones, no siempre F9).
---@return string
function GlobalStorageSiK.KeyBinding.getKeyLabel()
	if not getCore or not getCore() or not getCore().getKey then
		return "F9"
	end
	local ok, keyCode = pcall(function() return getCore():getKey(BINDING_NAME) end)
	if not ok or not keyCode or keyCode < 0 then
		return "F9"
	end
	local nameOk, name = pcall(function() return getKeyName(keyCode) end)
	if nameOk and name and name ~= "" then
		return name
	end
	return "F9"
end

if _G.keyBinding and not _G.GS_KeyBindingRegistered then
	_G.GS_KeyBindingRegistered = true

	local header = {}
	header.value = "[GlobalStorageSiK]"
	table.insert(keyBinding, header)

	local bind = {}
	bind.value = BINDING_NAME
	bind.key = Keyboard.KEY_F9
	table.insert(keyBinding, bind)
end

--- Pulsar el atajo intenta abrir el terminal exactamente igual que hacer clic
--- en un ordenador ya instalado (misma API que usa el menu contextual del
--- item) - respeta el mismo control de acceso/rango en el servidor, no es un
--- acceso "magico" sin restricciones.
local function onKeyStartPressed(key)
	if not getCore or not getCore() or not getCore().getKey then
		return
	end
	local boundKey = getCore():getKey(BINDING_NAME)
	if not boundKey or boundKey < 0 or key ~= boundKey then
		return
	end
	if GlobalStorageSiK.TerminalUI and GlobalStorageSiK.TerminalUI.requestOpen then
		GlobalStorageSiK.TerminalUI.requestOpen()
	end
end

if Events and Events.OnKeyStartPressed then
	Events.OnKeyStartPressed.Add(onKeyStartPressed)
end
