--[[
	GlobalStorageSiK - Trazas de red cliente/servidor (DebugMode)
	Autor: SiK
	Fecha: 2026-06-28
	Descripción: Timestamps y catálogo de redes/terminales en cada consulta al servidor.
]]

require "GS_Sandbox"
require "GS_Log"
require "GS_Network"
require "GS_TerminalCatalog"

GlobalStorageSiK.NetTrace = GlobalStorageSiK.NetTrace or {}

GlobalStorageSiK.NetTrace._seqClientSend = 0
GlobalStorageSiK.NetTrace._seqClientRecv = 0
GlobalStorageSiK.NetTrace._seqServerRecv = 0
GlobalStorageSiK.NetTrace._seqServerSend = 0

--- Comandos de polling/keepalive sin valor diagnostico: se repiten cada
--- pocos segundos mientras el terminal esta abierto y solo generan ruido
--- (no aportan nada para depurar rename/prioridad/reorganizar). Se excluyen
--- de la traza para poder leer con claridad lo que si importa.
local NOISY_COMMANDS = {
	pingTerminalAccess = true,
	-- debugEcho es el propio mecanismo de relay servidor->cliente de las
	-- lineas de log (ver GS_Log._echoHook) - trazarlo tambien genera una
	-- linea de NetTrace POR CADA linea de log ya reenviada, multiplicando
	-- el volumen y empujando fuera del buffer del panel las lineas reales
	-- que se estan buscando (confirmado: una sesion de depuracion real
	-- perdio la unica linea que importaba, "C<-S ... cmd=terminalState",
	-- enterrada bajo el eco de si misma).
	debugEcho = true,
}

---@param command string|nil
---@return boolean
local function isNoisy(command)
	return command ~= nil and NOISY_COMMANDS[command] == true
end

---@return boolean
function GlobalStorageSiK.NetTrace.isEnabled()
	return GlobalStorageSiK.Sandbox and GlobalStorageSiK.Sandbox.debugMode()
		and GlobalStorageSiK.Sandbox.debugMode() == true
end

--- Escribe traza NetTrace (INFO en servidor dedicado; DEBUG en cliente).
---@param line string
---@param detail string|nil
function GlobalStorageSiK.NetTrace.write(line, detail)
	if not GlobalStorageSiK.NetTrace.isEnabled() then
		return
	end
	-- Categoria "Network" tambien aqui, no solo en el branch DEBUG de abajo:
	-- en servidor dedicado esta traza sale por Log.info (siempre visible,
	-- no depende de DebugMode) para que aparezca en consola sin cliente
	-- conectado - pero debe seguir respetando el interruptor de categoria,
	-- si no, apagar "Red" en el sandbox no calla nada en ese caso concreto.
	if GlobalStorageSiK.Sandbox and GlobalStorageSiK.Sandbox.debugCategoryEnabled
			and not GlobalStorageSiK.Sandbox.debugCategoryEnabled("Network") then
		return
	end
	GlobalStorageSiK.Log.detail("NetTrace", line, detail)
end

--- Milisegundos monótonos para medir latencia.
---@return number
function GlobalStorageSiK.NetTrace.nowMs()
	if getTimestampMs then
		local ok, value = pcall(getTimestampMs)
		if ok and value then
			return tonumber(value) or 0
		end
	end
	return (os.time() or 0) * 1000
end

--- Marca temporal legible.
---@return string
function GlobalStorageSiK.NetTrace.ts()
	return tostring(GlobalStorageSiK.NetTrace.nowMs())
end

--- Resumen compacto de args/payload (evita volcar inventarios enteros).
---@param value any
---@param depth number|nil
---@return string
function GlobalStorageSiK.NetTrace.summarize(value, depth)
	depth = depth or 0
	if value == nil then
		return "nil"
	end
	local t = type(value)
	if t == "string" or t == "number" or t == "boolean" then
		local text = tostring(value)
		if #text > 120 then
			return text:sub(1, 117) .. "..."
		end
		return text
	end
	if t ~= "table" then
		return tostring(value)
	end
	if depth >= 2 then
		return "{...}"
	end
	local parts = {}
	local count = 0
	for k, v in pairs(value) do
		if type(k) == "string" and k:sub(1, 4) == "_gs" then
			-- omitir metadatos de traza en resumen largo
		else
			count = count + 1
			if count > 12 then
				parts[#parts + 1] = "..."
				break
			end
			if type(v) == "table" and v.x and v.y then
				parts[#parts + 1] = tostring(k) .. "={" .. tostring(v.x) .. "," .. tostring(v.y)
					.. "," .. tostring(v.z or 0) .. "}"
			elseif k == "items" and type(v) == "table" then
				parts[#parts + 1] = "items=" .. tostring(#v)
			elseif k == "terminals" and type(v) == "table" then
				parts[#parts + 1] = "terminals=" .. tostring(#v)
			elseif k == "zones" and type(v) == "table" then
				parts[#parts + 1] = "zones=" .. tostring(#v)
			else
				parts[#parts + 1] = tostring(k) .. "=" .. GlobalStorageSiK.NetTrace.summarize(v, depth + 1)
			end
		end
	end
	return "{" .. table.concat(parts, ", ") .. "}"
end

--- Instantánea de todas las redes y terminales (ModData).
---@return table[]
function GlobalStorageSiK.NetTrace.buildCatalogSnapshot()
	if not GlobalStorageSiK.Network then
		return {}
	end
	local registry = GlobalStorageSiK.Network.getRegistry()
	if not registry or not registry.networks then
		return {}
	end
	GlobalStorageSiK.Network.ensureRegistry(registry)
	local out = {}
	for networkId, net in pairs(registry.networks) do
		local terminals = {}
		if GlobalStorageSiK.TerminalCatalog and GlobalStorageSiK.TerminalCatalog.collectEntries then
			local rows = GlobalStorageSiK.TerminalCatalog.collectEntries(net)
			for i = 1, #rows do
				local row = rows[i]
				terminals[#terminals + 1] = {
					x = row.x,
					y = row.y,
					z = row.z or 0,
					controller = row.controller == true,
					catalogStatus = row.catalogStatus,
					suspended = row.suspended == true,
				}
			end
		end
		local rel = net.relocation
		out[#out + 1] = {
			networkId = networkId,
			name = net.name or "",
			owner = net.owner or "",
			ownerAccount = net.ownerAccount or "",
			terminalCount = #terminals,
			terminals = terminals,
			relocation = rel and {
				status = rel.status,
				lastX = rel.lastX,
				lastY = rel.lastY,
				lastZ = rel.lastZ,
			} or nil,
		}
	end
	table.sort(out, function(a, b)
		return (a.networkId or "") < (b.networkId or "")
	end)
	return out
end

--- Imprime catálogo multilínea en consola debug.
---@param snapshot table[]
---@param header string
function GlobalStorageSiK.NetTrace.logCatalog(snapshot, header)
	if not GlobalStorageSiK.NetTrace.isEnabled() then
		return
	end
	snapshot = snapshot or {}
	GlobalStorageSiK.NetTrace.write(header .. " | networks=" .. tostring(#snapshot), nil)
	for i = 1, #snapshot do
		local net = snapshot[i]
		local termParts = {}
		for j = 1, #(net.terminals or {}) do
			local t = net.terminals[j]
			termParts[#termParts + 1] = string.format(
				"#%d (%d,%d,%d)%s%s",
				j, t.x, t.y, t.z or 0,
				t.controller and " [ctrl]" or "",
				t.suspended and " [susp]" or ""
			)
		end
		local relText = ""
		if net.relocation and net.relocation.lastX then
			relText = string.format(" reloc=%s@(%d,%d,%d)",
				tostring(net.relocation.status or "?"),
				net.relocation.lastX, net.relocation.lastY, net.relocation.lastZ or 0)
		end
		GlobalStorageSiK.NetTrace.write(string.format(
			"  NET [%s] name=%s owner=%s terms=%d%s",
			tostring(net.networkId),
			tostring(net.name),
			tostring(net.owner),
			tonumber(net.terminalCount) or 0,
			relText
		), #termParts > 0 and table.concat(termParts, " | ") or "(sin terminales)")
	end
end

--- Cliente → servidor.
---@param command string
---@param args table|nil
function GlobalStorageSiK.NetTrace.logClientSend(command, args)
	if not GlobalStorageSiK.NetTrace.isEnabled() or isNoisy(command) then
		return
	end
	args = args or {}
	GlobalStorageSiK.NetTrace._seqClientSend = GlobalStorageSiK.NetTrace._seqClientSend + 1
	local ts = GlobalStorageSiK.NetTrace.nowMs()
	args._gsTraceSeq = GlobalStorageSiK.NetTrace._seqClientSend
	args._gsClientTs = ts
	GlobalStorageSiK.NetTrace.write(string.format(
		"C->S #%d ts=%s cmd=%s",
		GlobalStorageSiK.NetTrace._seqClientSend,
		GlobalStorageSiK.NetTrace.ts(),
		tostring(command)
	), GlobalStorageSiK.NetTrace.summarize(args))
end

--- Servidor ← cliente (incluye catálogo completo).
---@param player IsoPlayer|nil
---@param command string
---@param args table|nil
function GlobalStorageSiK.NetTrace.logServerRecv(player, command, args)
	if not GlobalStorageSiK.NetTrace.isEnabled() or isNoisy(command) then
		return
	end
	args = args or {}
	GlobalStorageSiK.NetTrace._seqServerRecv = GlobalStorageSiK.NetTrace._seqServerRecv + 1
	local user = player and player.getUsername and player:getUsername() or "?"
	local clientTs = tonumber(args._gsClientTs)
	local delta = clientTs and (GlobalStorageSiK.NetTrace.nowMs() - clientTs) or nil
	local deltaText = delta and string.format(" deltaMs=%d", delta) or ""
	local traceSeq = args._gsTraceSeq and (" traceSeq=" .. tostring(args._gsTraceSeq)) or ""
	GlobalStorageSiK.NetTrace.write(string.format(
		"S<-C #%d ts=%s user=%s cmd=%s%s%s",
		GlobalStorageSiK.NetTrace._seqServerRecv,
		GlobalStorageSiK.NetTrace.ts(),
		tostring(user),
		tostring(command),
		traceSeq,
		deltaText
	), GlobalStorageSiK.NetTrace.summarize(args))
	local snapshot = GlobalStorageSiK.NetTrace.buildCatalogSnapshot()
	GlobalStorageSiK.NetTrace.logCatalog(snapshot, string.format(
		"S CATALOG ts=%s cmd=%s user=%s",
		GlobalStorageSiK.NetTrace.ts(),
		tostring(command),
		tostring(user)
	))
end

--- Servidor → cliente (solo línea; catálogo ya volcado en S<-C).
---@param player IsoPlayer|nil
---@param command string
---@param payload table|nil
function GlobalStorageSiK.NetTrace.logServerSend(player, command, payload)
	if not GlobalStorageSiK.NetTrace.isEnabled() or isNoisy(command) then
		return
	end
	GlobalStorageSiK.NetTrace._seqServerSend = GlobalStorageSiK.NetTrace._seqServerSend + 1
	local user = player and player.getUsername and player:getUsername() or "?"
	payload = payload or {}
	payload._gsServerTs = GlobalStorageSiK.NetTrace.nowMs()
	payload._gsServerSendSeq = GlobalStorageSiK.NetTrace._seqServerSend
	GlobalStorageSiK.NetTrace.write(string.format(
		"S->C #%d ts=%s user=%s cmd=%s",
		GlobalStorageSiK.NetTrace._seqServerSend,
		GlobalStorageSiK.NetTrace.ts(),
		tostring(user),
		tostring(command)
	), GlobalStorageSiK.NetTrace.summarize(payload))
end

--- Cliente ← servidor.
---@param command string
---@param args table|nil
function GlobalStorageSiK.NetTrace.logClientRecv(command, args)
	if not GlobalStorageSiK.NetTrace.isEnabled() or isNoisy(command) then
		return
	end
	args = args or {}
	GlobalStorageSiK.NetTrace._seqClientRecv = GlobalStorageSiK.NetTrace._seqClientRecv + 1
	local serverTs = tonumber(args._gsServerTs)
	local delta = serverTs and (GlobalStorageSiK.NetTrace.nowMs() - serverTs) or nil
	local deltaText = delta and string.format(" deltaMs=%d", delta) or ""
	local sendSeq = args._gsServerSendSeq and (" srvSeq=" .. tostring(args._gsServerSendSeq)) or ""
	GlobalStorageSiK.NetTrace.write(string.format(
		"C<-S #%d ts=%s cmd=%s%s%s",
		GlobalStorageSiK.NetTrace._seqClientRecv,
		GlobalStorageSiK.NetTrace.ts(),
		tostring(command),
		sendSeq,
		deltaText
	), GlobalStorageSiK.NetTrace.summarize(args))
	if command == "terminalState" or command == "recoveryNetworks" or command == "terminalManifest" then
		local snapshot = GlobalStorageSiK.NetTrace.buildCatalogSnapshot()
		GlobalStorageSiK.NetTrace.logCatalog(snapshot, string.format(
			"C LOCAL CATALOG ts=%s after=%s",
			GlobalStorageSiK.NetTrace.ts(),
			tostring(command)
		))
	end
end
