--[[
	GlobalStorageSiK - Selector de zona con ratón (estilo Home Inventory)
	Autor: SiK
	Fecha: 2025-06-25
	Descripción: Dos clics en el mundo definen un rectángulo de zona manual.
	             Input capturado mediante el WorldPicker neutral de SiK.UI
	             (Events.OnMouseUp no dispara para clics en el mundo en B42).
]]

require "GS_I18n"
require "GS_NetClient"
require "GS_WorldHighlight"
require "GS_UI_Feedback"
local UI = require "GS_UI_Framework"
require "GS_Network"

GlobalStorageSiK.ZonePicker = GlobalStorageSiK.ZonePicker or {}

local T = GlobalStorageSiK.I18n.text
local active = false
local corner1 = nil
local terminalRef = nil
local overlay = nil
--- Ultima casilla bajo el raton en la que se reconstruyo el preview -
--- revisado 2026-08-14 junto al fix de parpadeo/FPS de GS_NodeHighlight.lua:
--- mismo patron (clearAll + reconstruccion completa, hasta 400 casillas con
--- registro FBO cada una) pero disparado en CADA TICK mientras se dibuja una
--- zona, sin comprobar si el raton se habia movido. Ahora solo se reconstruye
--- cuando la casilla bajo el raton cambia de verdad.
local lastPreviewHover = nil

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
	if player then
		GlobalStorageSiK.UIFeedback.halo(player, text, 200, 210, 220, duration or 700,
			{ channel = "zone-picker" })
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

--- Vuelve a pintar los contenedores ya adscritos a la red que se está
--- editando. El picker no consulta ni modifica red: consume el snapshot del
--- terminal y se actualiza solo cuando se reconstruye el preview por una
--- acción real del jugador.
local function highlightExistingNetworkNodes()
	local nodes = terminalRef and terminalRef.terminalState and terminalRef.terminalState.nodes or nil
	if type(nodes) ~= "table" or not GlobalStorageSiK.WorldHighlight
		or not GlobalStorageSiK.Network or not GlobalStorageSiK.Network.findWorldObject then
		return
	end
	for i = 1, #nodes do
		local node = nodes[i]
		local object = node and node.offline ~= true
			and GlobalStorageSiK.Network.findWorldObject(node) or nil
		if object then
			-- Mismo verde de pertenencia de red usado por el resaltado de nodos.
			GlobalStorageSiK.WorldHighlight.highlightObject(object, 0.35, 0.88, 0.42)
		end
	end
end

--- Actualiza preview visual de la selección (esquina 1 + hover + rectángulo).
local function updatePreviewHighlights()
	clearPreviewHighlights()
	if not active then
		return
	end
	-- Primero la pertenencia persistente; esquina, hover y rectángulo del
	-- picker se dibujan encima para que la selección actual siga siendo clara.
	highlightExistingNetworkNodes()

	local hover = squareUnderMouse()
	lastPreviewHover = hover
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
		local current = overlay
		overlay = nil
		if current.dispose then
			current:dispose()
		elseif current.removeFromUIManager then
			current:removeFromUIManager()
		end
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

--- Procesa un clic resuelto por el picker neutral.
---@param sq IsoGridSquare|nil
local function selectSquare(sq)
	if not active then
		return
	end
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

--- Crea el picker del viewport del jugador para capturar clics.
local function createOverlay()
	if overlay then
		removeOverlay()
	end
	local player = GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer
		and GlobalStorageSiK.NetClient.getPlayer() or nil
	local playerNum = terminalRef and terminalRef.playerNum
		or (player and player.getPlayerNum and player:getPlayerNum()) or 0
	local bounds = UI.Viewport.resolve(playerNum)
	overlay = UI.WorldPicker.create({
		playerNum = playerNum,
		bounds = bounds,
		multiStep = true,
		keepOpen = true,
		resolvePoint = function(point)
			local sx = tonumber(point and point.screenX)
			local sy = tonumber(point and point.screenY)
			if sx == nil or sy == nil then
				sx = getMouseX()
				sy = getMouseY()
			else
				sx = bounds.x + sx
				sy = bounds.y + sy
			end
			return squareAtScreen(sx, sy)
		end,
		onStep = function(context)
			local value = context and context.value or nil
			selectSquare(value and value.point or nil)
			if not active then
				return "complete"
			end
		end,
		onCancel = function()
			GlobalStorageSiK.ZonePicker.cancel()
		end,
		onRender = function(context)
			if not active then
				return
			end
			local hover = context and context.value or nil
			if hover ~= lastPreviewHover then
				updatePreviewHighlights()
			end
		end,
	})
	-- WorldPicker ya gestiona UI.FocusStack.PRIORITY.TRANSIENT, captura y lifecycle.
	-- Conservamos el
	-- consumo del down derecho para que el clic de cancelación no alcance el mundo.
	overlay.onRightMouseDown = function()
		return true
	end
end

--- Inicia modo selección (oculta terminal temporalmente).
---@param terminal GS_TerminalUI|nil
function GlobalStorageSiK.ZonePicker.start(terminal)
	if active then
		GlobalStorageSiK.ZonePicker.cancel()
	end
	active = true
	corner1 = nil
	lastPreviewHover = nil
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
end
