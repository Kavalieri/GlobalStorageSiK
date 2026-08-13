--[[
	GlobalStorageSiK - Selector de zona con ratón (estilo Home Inventory)
	Autor: SiK
	Fecha: 2025-06-25
	Descripción: Dos clics en el mundo definen un rectángulo de zona manual.
	             Input capturado mediante ISPanel overlay (Events.OnMouseUp no
	             dispara para clics en el mundo en B42).
]]

require "GS_I18n"
require "GS_NetClient"
require "GS_WorldHighlight"

GlobalStorageSiK.ZonePicker = GlobalStorageSiK.ZonePicker or {}

local T = GlobalStorageSiK.I18n.text
local active = false
local corner1 = nil
local terminalRef = nil
local overlay = nil

--- Normaliza objeto o casilla a IsoGridSquare.
---@param objOrSq any
---@return IsoGridSquare|nil
local function asGridSquare(objOrSq)
	if not objOrSq then
		return nil
	end
	if objOrSq.getZ and objOrSq.getX and objOrSq.getY and not objOrSq.getSquare then
		return objOrSq
	end
	if objOrSq.getSquare then
		return objOrSq:getSquare()
	end
	return nil
end

--- Convierte coordenadas de pantalla a casilla del mundo.
--- Usa screenToIsoX/screenToIsoY(playerNum, screenX, screenY, z), el MISMO
--- patron que usa el propio selector de zona por arrastre vanilla
--- (ISUI/Animal/ISAddDesignationAnimalZoneUI.lua:pickSquare, verificado
--- contra la instalacion local del juego) -- referencia mas directa que
--- ISCoordConversion/IsoUtils (que usa FireBrushUI, pensado para pintar un
--- tile puntual, no para arrastrar un rectangulo de zona). screenToIsoX/Y
--- toma playerNum explicito (splitscreen) y se llama con getMouseX/Y SIN
--- escalar (no getMouseXScaled/YScaled: eso era del patron equivocado).
--- La formula manual anterior aproximaba la camara con la posicion del
--- jugador (player:getX()/getY()), que se desincroniza en cuanto la camara
--- no esta pegada al jugador (scroll, movimiento, zoom) -- de ahi que el
--- marcador no siguiera al raton de forma coherente. `cell:getGridSquareFromScreenPos`
--- (intento anterior de API nativa) no existe en ningun Lua vanilla B42.
---@param sx number coordenada X en pantalla (getMouseX(), SIN escalar)
---@param sy number coordenada Y en pantalla (getMouseY(), SIN escalar)
---@return IsoGridSquare|nil
local function squareAtScreen(sx, sy)
	local player = GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer() or getSpecificPlayer(0)
	if not player then
		return nil
	end
	local cell = getCell and getCell() or nil
	if not cell then
		return player:getCurrentSquare()
	end
	local playerNum = player.getPlayerNum and player:getPlayerNum() or 0
	local z = player:getZ()
	local ok, wx, wy = pcall(function()
		return screenToIsoX(playerNum, sx, sy, z), screenToIsoY(playerNum, sx, sy, z)
	end)
	if not ok or not wx or not wy then
		return player:getCurrentSquare()
	end
	local sq = cell:getGridSquare(math.floor(wx), math.floor(wy), z)
	if sq then
		return sq
	end
	return player:getCurrentSquare()
end

--- Obtiene la casilla bajo el cursor del mundo (para preview en OnTick).
---@return IsoGridSquare|nil
local function squareUnderMouse()
	return squareAtScreen(getMouseX(), getMouseY())
end

--- Muestra instrucción al jugador.
---@param text string
---@param duration number|nil
local function showHint(text, duration)
	local player = GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer() or getSpecificPlayer(0)
	if player and player.setHaloNote then
		player:setHaloNote(text, 200, 210, 220, duration or 700)
	end
end

--- Oculta terminal para capturar clics del mundo.
---@param terminal GS_TerminalUI|nil
local function suspendTerminal(terminal)
	if not terminal then
		return
	end
	terminal._gsZonePickWasVisible = terminal:isVisible()
	if terminal.setMouseTransparent then
		terminal:setMouseTransparent(true)
	end
	if terminal.setCapture then
		terminal:setCapture(false)
	end
	terminal:setVisible(false)
	if terminal.removeFromUIManager then
		terminal:removeFromUIManager()
		terminal._gsZonePickRemoved = true
	end
end

--- Restaura terminal tras selección o cancelación.
---@param terminal GS_TerminalUI|nil
local function resumeTerminal(terminal)
	if not terminal then
		return
	end
	if terminal._gsZonePickRemoved and terminal.addToUIManager then
		terminal:addToUIManager()
		terminal._gsZonePickRemoved = nil
	end
	if terminal.setMouseTransparent then
		terminal:setMouseTransparent(false)
	end
	if terminal._gsZonePickWasVisible ~= false then
		terminal:setVisible(true)
	end
	terminal._gsZonePickWasVisible = nil
	if terminal.bringToTop then
		terminal:bringToTop()
	end
end

--- Quita resaltado de preview en suelos.
local function clearPreviewHighlights()
	if GlobalStorageSiK.WorldHighlight and GlobalStorageSiK.WorldHighlight.clearAll then
		GlobalStorageSiK.WorldHighlight.clearAll()
	end
end

--- Actualiza preview visual de la selección (esquina 1 + hover + rectángulo).
local function updatePreviewHighlights()
	clearPreviewHighlights()
	if not active then
		return
	end

	local hover = squareUnderMouse()
	if corner1 and GlobalStorageSiK.WorldHighlight then
		GlobalStorageSiK.WorldHighlight.highlightSquare(corner1, 0.2, 0.85, 0.35)
	end
	if hover and GlobalStorageSiK.WorldHighlight then
		GlobalStorageSiK.WorldHighlight.highlightSquare(hover, 0.25, 0.55, 0.95)
	end

	if not corner1 or not hover then
		return
	end

	local z = corner1:getZ()
	local x1 = math.min(corner1:getX(), hover:getX())
	local x2 = math.max(corner1:getX(), hover:getX())
	local y1 = math.min(corner1:getY(), hover:getY())
	local y2 = math.max(corner1:getY(), hover:getY())
	local cell = getCell and getCell() or nil
	if not cell or not GlobalStorageSiK.WorldHighlight then
		return
	end

	local count = 0
	for x = x1, x2 do
		for y = y1, y2 do
			if count >= 400 then
				return
			end
			local sq = cell:getGridSquare(x, y, z)
			if sq and sq ~= corner1 and sq ~= hover then
				GlobalStorageSiK.WorldHighlight.highlightSquare(sq, 0.15, 0.65, 0.35)
				count = count + 1
			end
		end
	end
end

--- Elimina el overlay de pantalla completa.
local function removeOverlay()
	if overlay then
		if overlay.removeFromUIManager then
			overlay:removeFromUIManager()
		end
		overlay = nil
	end
end

--- Cancela la selección y restaura el terminal.
function GlobalStorageSiK.ZonePicker.cancel()
	if not active then
		return
	end
	active = false
	corner1 = nil
	clearPreviewHighlights()
	removeOverlay()
	local term = terminalRef
	terminalRef = nil
	resumeTerminal(term)
	showHint(T("IGUI_GS_ZonePickCancelled"))
end

--- Envía bounds al servidor y reabre el terminal.
---@param sq1 IsoGridSquare
---@param sq2 IsoGridSquare
local function finishSelection(sq1, sq2)
	if sq1:getZ() ~= sq2:getZ() then
		showHint(T("IGUI_GS_ZonePickSameFloor"))
		showHint(T("IGUI_GS_ZonePickStart"))
		updatePreviewHighlights()
		return
	end

	local bounds = {
		x1 = math.min(sq1:getX(), sq2:getX()),
		y1 = math.min(sq1:getY(), sq2:getY()),
		x2 = math.max(sq1:getX(), sq2:getX()),
		y2 = math.max(sq1:getY(), sq2:getY()),
		z = sq1:getZ(),
		zMax = sq1:getZ(),
	}

	active = false
	corner1 = nil
	clearPreviewHighlights()
	removeOverlay()

	local searchQuery = ""
	local term = terminalRef
	if term and term.getSearchQuery then
		searchQuery = term:getSearchQuery() or ""
	end

	if not GlobalStorageSiK.NetClient or not GlobalStorageSiK.NetClient.sendCommand then
		resumeTerminal(term)
		terminalRef = nil
		showHint(T("IGUI_GS_ZonePickFailed"))
		return
	end

	GlobalStorageSiK.NetClient.sendCommand("createZoneSelection", {
		bounds = bounds,
		searchQuery = searchQuery,
	})

	resumeTerminal(term)
	terminalRef = nil
	showHint(T("IGUI_GS_ZonePickDone"))
end

--- Crea el panel overlay de pantalla completa para capturar clics.
local function createOverlay()
	if overlay then
		removeOverlay()
	end
	local sw = getCore():getScreenWidth()
	local sh = getCore():getScreenHeight()
	overlay = ISPanel:new(0, 0, sw, sh)
	overlay.drawBackground = false
	overlay.drawBorder = false
	overlay.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
	overlay.borderColor = { r = 0, g = 0, b = 0, a = 0 }

	-- Captura clic izquierdo
	overlay.onMouseDown = function(self, x, y)
		return true
	end
	overlay.onMouseUp = function(self, x, y)
		if not active then return end
		local sq = squareAtScreen(x, y)
		if not sq then
			showHint(T("IGUI_GS_ZonePickNoSquare"))
			return
		end
		if not corner1 then
			corner1 = sq
			showHint(T("IGUI_GS_ZonePickFirstStored", sq:getX(), sq:getY(), sq:getZ()), 900)
			showHint(T("IGUI_GS_ZonePickSecond"), 900)
			updatePreviewHighlights()
			return
		end
		finishSelection(corner1, sq)
	end

	-- Captura clic derecho → cancelar
	overlay.onRightMouseDown = function(self, x, y)
		return true
	end
	overlay.onRightMouseUp = function(self, x, y)
		if not active then return end
		GlobalStorageSiK.ZonePicker.cancel()
	end

	overlay:initialise()
	overlay:addToUIManager()
	overlay:bringToTop()
end

--- Inicia modo selección (oculta terminal temporalmente).
---@param terminal GS_TerminalUI|nil
function GlobalStorageSiK.ZonePicker.start(terminal)
	if active then
		GlobalStorageSiK.ZonePicker.cancel()
	end
	active = true
	corner1 = nil
	clearPreviewHighlights()
	terminalRef = terminal
	suspendTerminal(terminal)
	createOverlay()
	showHint(T("IGUI_GS_ZonePickStart"), 900)
end

--- True si el picker está activo.
---@return boolean
function GlobalStorageSiK.ZonePicker.isActive()
	return active == true
end

--- Registra eventos globales (una sola vez).
function GlobalStorageSiK.ZonePicker.install()
	if GlobalStorageSiK.ZonePicker._installed then
		return
	end
	GlobalStorageSiK.ZonePicker._installed = true

	local function onKeyPressed(key)
		if not active then
			return
		end
		if key == Keyboard.KEY_ESCAPE then
			GlobalStorageSiK.ZonePicker.cancel()
		end
	end

	local function onTick()
		if active then
			updatePreviewHighlights()
		end
	end

	if Events and Events.OnKeyPressed then
		Events.OnKeyPressed.Add(onKeyPressed)
	end
	if Events and Events.OnTick then
		Events.OnTick.Add(onTick)
	end
end
