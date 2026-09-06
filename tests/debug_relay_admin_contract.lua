-- DEV32.4.3 contract for admin-only debug relay subscription and replay safety.
--
-- It validates server relay files in:
--  - GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/server/GS_DebugRelayServer.lua
--  - ../ManureManagerSiK-Repo/Contents/mods/ManureManagerSiK/42/media/lua/server/MM_DebugRelayServer.lua
--  - ../SiKCorpseLootGuard-Repo/Contents/mods/SiKCorpseLootGuard/42/media/lua/server/SCLG_DebugRelayServer.lua

local now = 1000
local onlinePlayers = {}
local sentPackets = {}
local events = {}

isServer = function() return true end
isClient = function() return false end
getTimestampMs = function() return now end

local function resetTime()
        now = 1000
end

local function eventList()
        local handlers = {}
        return {
                handlers = handlers,
                Add = function(fn)
                        handlers[#handlers + 1] = fn
                end,
        }
end

local function refreshEventBus()
        events = {
                OnClientCommand = eventList(),
                OnTick = eventList(),
        }
        Events = events
end

local function setOnlinePlayers(players)
        onlinePlayers = players or {}
end

getOnlinePlayers = function()
        return {
                size = function() return #onlinePlayers end,
                get = function(_, idx)
                        return onlinePlayers[idx + 1]
                end,
        }
end

sendServerCommand = function(_, module, command, payload)
        sentPackets[#sentPackets + 1] = {
                module = module,
                command = command,
                payload = payload,
        }
end

local function fireClientCommand(module, command, player, args)
        for i = 1, #events.OnClientCommand.handlers do
                events.OnClientCommand.handlers[i](module, command, player, args)
        end
end

local function runTick()
        now = now + 400
        for i = 1, #events.OnTick.handlers do
                events.OnTick.handlers[i]()
        end
end

local function clearPackets()
        sentPackets = {}
end

local function makePlayer(username, onlineId, accessLevel)
        return {
                _username = username,
                _onlineId = onlineId,
                _accessLevel = accessLevel,
                getUsername = function(self) return self._username end,
                getOnlineID = function(self) return self._onlineId end,
                getAccessLevel = function(self) return self._accessLevel end,
        }
end

local function assertEqual(actual, expected, message)
        if actual ~= expected then
                error((message or "assertEqual failed") .. ": expected=" .. tostring(expected) .. " actual=" .. tostring(actual), 2)
        end
end

local function assertTrue(value, message)
        if not value then
                error(message or "assertTrue failed", 2)
        end
end

local function loadRelay(relay)
        refreshEventBus()
        clearPackets()
        resetTime()

        local capturedSink
        if relay.id == "GS" then
                package.loaded["GS_Config"] = nil
                package.loaded["GS_Sandbox"] = nil
                package.loaded["GS_DebugRelay"] = nil
                GlobalStorageSiK = {
                        MOD_ID = "GlobalStorageSiK",
                        Sandbox = {
                                debugRelayToClients = function() return true end,
                        },
                        DebugRelay = {
                                setServerSink = function(fn) capturedSink = fn end,
                        },
                }
                package.loaded["GS_Config"] = GlobalStorageSiK
                package.loaded["GS_Sandbox"] = GlobalStorageSiK.Sandbox
                package.loaded["GS_DebugRelay"] = GlobalStorageSiK.DebugRelay
        elseif relay.id == "MM" then
                package.loaded["MM_Sandbox"] = nil
                package.loaded["MM_Log"] = nil
                MM_Sandbox = {
                        isConsoleLogEnabled = function() return true end,
                        relayServerLogsToClients = function() return true end,
                }
                MM_Log = {
                        setRelaySink = function(fn) capturedSink = fn end,
                }
                package.loaded["MM_Sandbox"] = MM_Sandbox
                package.loaded["MM_Log"] = MM_Log
        elseif relay.id == "SCLG" then
                package.loaded["SCLG_Config"] = nil
                package.loaded["SCLG_Sandbox"] = nil
                package.loaded["SCLG_Log"] = nil
                SCLG_Sandbox = {
                        isConsoleLogEnabled = function() return true end,
                        relayServerLogsToClients = function() return true end,
                }
                SCLG_Log = {
                        setRelaySink = function(fn) capturedSink = fn end,
                }
                package.loaded["SCLG_Config"] = true
                package.loaded["SCLG_Sandbox"] = SCLG_Sandbox
                package.loaded["SCLG_Log"] = SCLG_Log
        end

        dofile(relay.path)
        if not capturedSink then
                error("relay did not register a server sink: " .. relay.id, 2)
        end
        return capturedSink
end

local function runRelayContract(relay)
        local sink = loadRelay(relay)
        setOnlinePlayers({})
        clearPackets()

        local normal = makePlayer("alice", 1001, "normal")
        local moderator = makePlayer("boris", 1002, "moderator")
        local admin1 = makePlayer("admin", 2001, "admin")
        local admin2 = makePlayer("admin", 2001, "admin")

        setOnlinePlayers({ normal })
        fireClientCommand(relay.module, relay.subscribeCommand, normal, { enabled = true })
        assertEqual(sink("normal-line"), false, relay.id .. " normal user no debe entrar en cola")
        assertEqual(#sentPackets, 0, relay.id .. " normal user no recibe payload/ack al suscribir")

        clearPackets()
        setOnlinePlayers({ moderator })
        fireClientCommand(relay.module, relay.subscribeCommand, moderator, { enabled = true })
        assertEqual(sink("moderator-line"), false, relay.id .. " moderator no debe entrar en cola")
        assertEqual(#sentPackets, 0, relay.id .. " moderator no recibe payload/ack al suscribir")

        clearPackets()
        setOnlinePlayers({ admin1 })
        fireClientCommand(relay.module, relay.subscribeCommand, admin1, { enabled = true })
        assertTrue(relay.id == "GS" and #sentPackets == 1 or relay.id ~= "GS" and #sentPackets == 0,
                relay.id .. " admin sí suscribe y opcionalmente ACK")
        clearPackets()

        assertTrue(sink("trace-admin-1"), relay.id .. " admin suscripto sí entra en cola")
        runTick()
        assertEqual(#sentPackets, 1, relay.id .. " admin recibe lote mientras mantiene suscripción")
        assertEqual(sentPackets[1].command, relay.batchCommand, relay.id .. " usa comando de lote esperado")
        assertEqual(sentPackets[1].payload.payload, "trace-admin-1", relay.id .. " payload llega al admin")

        admin1._accessLevel = "normal"
        local beforeLoss = #sentPackets
        assertTrue(sink("trace-after-perm-loss"), relay.id .. " admin desconectado de permisos puede seguir intentando enviar")
        runTick()
        assertEqual(#sentPackets, beforeLoss, relay.id .. " al perder permiso no debe llegar ningún batch")

        setOnlinePlayers({})
        runTick()

        setOnlinePlayers({ admin2 })
        assertEqual(sink("trace-reconnect-id-recycled"), false, relay.id .. " reconexión con mismo username+onlineId no reabre sesión automática")
        runTick()
        assertEqual(#sentPackets, beforeLoss, relay.id .. " sin re-suscripción no hay replay")

        fireClientCommand(relay.module, relay.subscribeCommand, admin2, { enabled = true })
        clearPackets()
        assertTrue(sink("trace-admin-2"), relay.id .. " admin reconectado vuelve a entrar en cola tras subscribe")
        runTick()
        assertEqual(#sentPackets, 1, relay.id .. " admin2 recibe lote tras re-suscripción")
end

local relays = {
        {
                id = "GS",
                path = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/server/GS_DebugRelayServer.lua",
                module = "GlobalStorageSiK",
                subscribeCommand = "debugTraceSubscribe",
                batchCommand = "debugTraceBatch",
        },
        {
                id = "MM",
                path = "../ManureManagerSiK-Repo/Contents/mods/ManureManagerSiK/42/media/lua/server/MM_DebugRelayServer.lua",
                module = "ManureManagerSiK.Debug",
                subscribeCommand = "subscribe",
                batchCommand = "batch",
        },
        {
                id = "SCLG",
                path = "../SiKCorpseLootGuard-Repo/Contents/mods/SiKCorpseLootGuard/42/media/lua/server/SCLG_DebugRelayServer.lua",
                module = "SiKCorpseLootGuard.Debug",
                subscribeCommand = "subscribe",
                batchCommand = "batch",
        },
}

for i = 1, #relays do
        runRelayContract(relays[i])
end

print("debug_relay_admin_contract: OK")
