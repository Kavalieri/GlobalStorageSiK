--[[
	GlobalStorageSiK - Configuración compartida
	Autor: SiK
	Fecha: 2025-06-23
	Descripción: Constantes y claves usadas en cliente y servidor.
]]

GlobalStorageSiK = GlobalStorageSiK or {}

GlobalStorageSiK.MOD_ID = "GlobalStorageSiK"
GlobalStorageSiK.MODDATA_KEY = "GlobalStorageSiK_Network"
GlobalStorageSiK.CONTAINER_MODDATA_KEY = "GlobalStorageSiK"

--- CRITICO: en singleplayer real de PZ B42 (partida "Solo", sin hosting),
--- isClient() E isServer() devuelven AMBOS false - no "ambos true" como
--- asumia buena parte de este codigo (comentario historico en
--- GS_TerminalPlace.registerAtSquare, ya corregido). Confirmado: (1) prueba
--- directa documentada en GS_ItemNetworkTooltip.isTrueSingleplayer, escrita
--- tras comprobar que el tooltip de red nunca funcionaba en SP mientras
--- dependia de isClient(); (2) el motor unifica cliente+"servidor" en el
--- mismo proceso/VM en SP real, no hay ronda de red que journal, encajando
--- con que ninguno de los dos flags de "soy la mitad de una conexion de red"
--- se active. Cualquier gate de la forma "if isServer() then <logica
--- autoritativa> end" (guardar registro, migrar datos, registrar terminal,
--- enviar comando al servidor...) se salta SIEMPRE en SP real, dejando esa
--- logica sin ejecutar nunca - la causa raiz de que instalar terminal, crear
--- zonas, guardar el registro en disco y enviar items a la red no
--- funcionaran en partidas de un jugador (nunca detectado antes porque todo
--- el testing interno del equipo se hizo en MP, donde isClient() SI es true).
---
--- Usar esta funcion en vez de "isServer()" a pelo para decidir si TOCA
--- ejecutar la logica autoritativa (registro, persistencia, migraciones) EN
--- ESTE MISMO PROCESO: verdadero para servidor dedicado, para el host de una
--- partida en LAN/multijugador, y para SP real - falso SOLO para un cliente
--- MP puro hablando con un servidor remoto (ahi la autoridad esta en OTRO
--- proceso, hay que pasar por sendCommand de verdad).
---@return boolean
function GlobalStorageSiK.isAuthoritative()
	local client = isClient and isClient()
	local server = isServer and isServer()
	if client and not server then
		return false
	end
	return true
end

--- Distinta de isAuthoritative(): esta responde "hay mas de un jugador
--- humano compartiendo esta red ahora mismo", no "corre la logica
--- autoritativa en este proceso". En SP real (isClient/isServer ambos
--- false) debe dar false para no aplicar permisos a un jugador solo.
--- Antes duplicada sin querer en GS_Permissions.shouldEnforce() y
--- GS_TerminalUI_Permissions.shouldShowTab() con isServer()/isClient() a
--- pelo; centralizada aqui para evitar que las dos copias diverjan.
---@return boolean
function GlobalStorageSiK.isMultiplayerActive()
	local client = isClient and isClient()
	local server = isServer and isServer()
	if client and not server then
		return true
	end
	if server and not client then
		return true
	end
	if client and server and getNumActivePlayers and getNumActivePlayers() > 1 then
		return true
	end
	return false
end

GlobalStorageSiK.Config = {
	-- Unificada con modversion de mod.info (antes llevaba un esquema interno
	-- 0.10.x-preprod aparte, lo que dificultaba saber que build produjo un
	-- error en el log). A partir de aqui suben siempre juntas.
	MOD_VERSION = "1.3.78",
	ADDON_ID_TABLET = "TabletLink",
	ADDON_ID_CRAFT = "Craft",
	WEIGHT_WARN_PERCENT = 80,
	WEIGHT_CRITICAL_PERCENT = 95,
	MAX_CONTAINERS_PER_NETWORK = 64,
	MAX_TERMINALS_PER_NETWORK = 8,
	SEARCH_RADIUS_TILES = 0,
	-- Lector de terminal SiK: instala el programa GS sobre un ordenador ya
	-- colocado en el mapa (metodo nuevo, ver GS_TerminalAccess.installOnObject)
	-- sin tocar el objeto vanilla ni el metodo antiguo de colocar/craftear
	-- un GS_TerminalUnit propio, que sigue funcionando en paralelo.
	ITEM_TERMINAL_READER = "GlobalStorageSiK.GS_TerminalReader",
	MANUAL_TERMINAL_UNIT = "GlobalStorageSiK.GS_Manual_TerminalUnit",
	-- Disquete que instala el lector (ITEM_TERMINAL_READER) directamente en
	-- la red de un terminal, para no tener que llevarlo encima (ver
	-- GS_FloppyDriveNetwork.lua).
	ITEM_FLOPPY_DRIVE_INSTALL_DISK = "GlobalStorageSiK.GS_FloppyDisk_DriveInstall",
	BULK_SCOPES = {
		MAIN = "main",
		BAG = "bag",
		SELECTION = "selection",
		CATEGORY = "category",
	},
}
