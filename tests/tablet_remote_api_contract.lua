-- Author contract for the final remote-terminal API and Tablet item callbacks.
-- Pure Lua 5.1: no Project Zomboid client or dedicated server is opened.

local coreClient = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/"
local coreServer = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/server/"
local tabletClient = "addons/GSSiK_Addon_Tablet/Contents/mods/GSSiK_Addon_Tablet/42/media/lua/client/"

local failures = {}
local passCount = 0
local function check(name, callback)
	local ok, err = pcall(callback)
	if ok then
		passCount = passCount + 1
		print("PASS " .. name)
	else
		failures[#failures + 1] = name .. ": " .. tostring(err)
		print("FAIL " .. failures[#failures])
	end
end

local function read(path)
	local handle = assert(io.open(path, "rb"), "cannot read " .. path)
	local source = handle:read("*a")
	handle:close()
	return source
end

local function contains(source, needle, message)
	assert(source:find(needle, 1, true) ~= nil, message .. ": " .. needle)
end

for _, name in ipairs({
	"GS_Sandbox", "GS_Network", "GS_TerminalAccess", "GS_PlayerUtils",
	"GS_UIDebug", "GS_Log", "GS_SiK_UI_Window",
}) do
	package.loaded[name] = true
end

local sent = {}
local defaultPlayer = { getPlayerNum = function() return 0 end }
GlobalStorageSiK = {
	TerminalUI = {},
	Client = { pendingTerminalOpen = false, terminalOpenSeq = 0 },
	Log = { error = function() end },
	Sandbox = {},
	Network = {},
	TerminalAccess = {},
	PlayerUtils = { resolve = function(value) return value or defaultPlayer end },
	SiK_UI = {
		Viewport = { resolve = function() return { profile = "standard" } end },
		Window = { recall = function() return nil end, resolveProfile = function() return {} end },
	},
	NetClient = {},
}

function GlobalStorageSiK.NetClient.sendCommand(command, args)
	sent[#sent + 1] = { command = command, args = args }
	return true
end

function GlobalStorageSiK.NetClient.sendNetworkCommand(command, networkId, args)
	args = args or {}
	args.networkId = networkId
	args._gsExplicitNetwork = true
	return GlobalStorageSiK.NetClient.sendCommand(command, args)
end

dofile(coreClient .. "GS_TerminalUI_Api.lua")

check("remote candidate callbacks are correlated, one-shot, cancellable and stale-safe", function()
	local calls = {}
	local first = GlobalStorageSiK.TerminalUI.requestRemoteNetworks(function(networks, reason)
		calls[#calls + 1] = { owner = "first", networks = networks, reason = reason }
	end)
	local second = GlobalStorageSiK.TerminalUI.requestRemoteNetworks(function(networks, reason)
		calls[#calls + 1] = { owner = "second", networks = networks, reason = reason }
	end)
	assert(first and second == first + 1, "request ids are not monotonic")
	assert(sent[#sent].command == "getRemoteNetworkCandidates"
		and sent[#sent].args.requestId == second, "candidate request lost requestId")
	GlobalStorageSiK.TerminalUI.onRemoteNetworkCandidates({
		requestId = first, networks = { { networkId = "stale" } },
	})
	assert(#calls == 0, "stale response invoked the replacement callback")
	GlobalStorageSiK.TerminalUI.onRemoteNetworkCandidates({
		requestId = second, networks = { { networkId = "live" } }, reason = "ok",
	})
	assert(#calls == 1 and calls[1].owner == "second"
		and calls[1].networks[1].networkId == "live", "current response was not delivered")
	GlobalStorageSiK.TerminalUI.onRemoteNetworkCandidates({ requestId = second, networks = {} })
	assert(#calls == 1, "same response invoked a one-shot callback twice")
	local cancelled = GlobalStorageSiK.TerminalUI.requestRemoteNetworks(function()
		calls[#calls + 1] = { owner = "cancelled" }
	end)
	GlobalStorageSiK.TerminalUI.cancelRemoteNetworkRequest(cancelled)
	GlobalStorageSiK.TerminalUI.onRemoteNetworkCandidates({ requestId = cancelled, networks = {} })
	assert(#calls == 1, "cancelled request accepted a late response")
	local playerOne = { getPlayerNum = function() return 1 end }
	local isolated = {}
	local p0Request = GlobalStorageSiK.TerminalUI.requestRemoteNetworks(function()
		isolated[#isolated + 1] = "p0"
	end, defaultPlayer)
	local p1Request = GlobalStorageSiK.TerminalUI.requestRemoteNetworks(function()
		isolated[#isolated + 1] = "p1"
	end, playerOne)
	GlobalStorageSiK.TerminalUI.onRemoteNetworkCandidates({
		playerNum = 0, requestId = p0Request, networks = {},
	})
	GlobalStorageSiK.TerminalUI.onRemoteNetworkCandidates({
		playerNum = 1, requestId = p1Request, networks = {},
	})
	assert(#isolated == 2 and isolated[1] == "p0" and isolated[2] == "p1",
		"one player's request replaced or consumed another player's callback")
	local originalSend = GlobalStorageSiK.NetClient.sendCommand
	GlobalStorageSiK.NetClient.sendCommand = function() return false end
	local failed = GlobalStorageSiK.TerminalUI.requestRemoteNetworks(function()
		calls[#calls + 1] = { owner = "failed-send" }
	end)
	GlobalStorageSiK.NetClient.sendCommand = originalSend
	assert(failed == nil, "failed network send returned an active request id")
	GlobalStorageSiK.TerminalUI.onRemoteNetworkCandidates({
		playerNum = 0,
		requestId = GlobalStorageSiK.TerminalUI._remoteNetworkRequestSeq,
		networks = {},
	})
	assert(#calls == 1, "failed send retained a callback")
end)

check("remote open sends explicit network intent without a client terminal hint", function()
	local before = #sent
	local results = {}
	local openId = GlobalStorageSiK.TerminalUI.requestOpenNetwork("net-safe", defaultPlayer,
		function(ok, reason) results[#results + 1] = { ok = ok, reason = reason } end)
	assert(type(openId) == "number",
		"valid remote open was not sent")
	assert(#sent == before + 1, "remote open emitted an unexpected number of commands")
	local call = sent[#sent]
	assert(call.command == "openTerminal" and call.args.networkId == "net-safe",
		"remote open lost its selected network")
	assert(call.args.remoteAccess == true and call.args._gsExplicitNetwork == true,
		"remote open lost remote or explicit-network intent")
	assert(call.args.openSeq == openId, "remote open lost its correlation id")
	assert(call.args.terminalHint == nil, "remote open sent client coordinates")
	assert(GlobalStorageSiK.TerminalUI.onRemoteOpenResult({
		playerNum = 1, openSeq = openId, reason = "no_terminal",
	}, false) == false, "another local player consumed the open result")
	assert(#results == 0, "cross-player open result invoked the callback")
	assert(GlobalStorageSiK.TerminalUI.onRemoteOpenResult({
		playerNum = 0, openSeq = openId, networkId = "net-safe",
	}, true) == true, "exact remote open result was not correlated")
	assert(#results == 1 and results[1].ok == true, "accepted open was not delivered once")
	assert(GlobalStorageSiK.TerminalUI.onRemoteOpenResult({
		playerNum = 0, openSeq = openId,
	}, true) == false, "one-shot remote open callback was reused")
	assert(GlobalStorageSiK.TerminalUI.requestOpenNetwork("") == nil,
		"empty network id was transmitted")
	assert(#sent == before + 1, "invalid network id emitted a command")
end)

check("server candidate route is bounded, rate-limited and request-correlated", function()
	local source = read(coreServer .. "GS_Server.lua")
	local first = assert(source:find("local remoteNetworkCandidateLastMs", 1, true))
	local last = assert(source:find("local function handleInstallTerminalReader", first, true))
	local body = source:sub(first, last - 1)
	contains(body, "REMOTE_NETWORK_CANDIDATE_COOLDOWN_MS = 500", "missing finite cooldown")
	contains(body, "MAX_REMOTE_NETWORK_CANDIDATES = 64", "missing response cardinality cap")
	contains(body, "MAX_REMOTE_NETWORK_RATE_KEYS = 256", "missing rate-state cap")
	contains(body, "REMOTE_NETWORK_RATE_TTL_MS = 60000", "missing rate-state TTL")
	contains(body, "requestId < 1 or requestId > 2147483647", "requestId is not bounded")
	contains(body, "reason = \"rate_limited\"", "rate limit has no correlated response")
	contains(body, "if #candidates >= MAX_REMOTE_NETWORK_CANDIDATES", "candidate list is not capped")
	contains(body, "TerminalAccess.evaluateWireless(", "candidate route bypasses wireless evaluation")
	contains(body, "selectable = ok == true and terminal ~= nil",
		"unavailable member networks are not serialized as disabled choices")
	contains(body, "reason = ok and nil or reason",
		"disabled choices do not preserve their authoritative reason")
	contains(body, "requestId = requestId", "responses do not echo requestId")
	contains(body, "serializeWirelessCapabilities", "capabilities are not bounded/serialized")
end)

check("remote server open has no physical or default-network fallback", function()
	local source = read(coreServer .. "GS_Server.lua")
	local first = assert(source:find("local function handleOpenTerminal", 1, true))
	local last = assert(source:find("local remoteNetworkCandidateLastMs", first, true))
	local body = source:sub(first, last - 1)
	local remoteStart = assert(body:find("if remoteAccess then", 1, true))
	local physicalStart = assert(body:find("else", remoteStart, true))
	local remoteBranch = body:sub(remoteStart, physicalStart - 1)
	contains(remoteBranch, "Network.resolveNetworkId(args.networkId)",
		"remote branch does not resolve the selected id")
	contains(remoteBranch, "TerminalAccess.evaluateWireless(player, networkId)",
		"remote branch does not revalidate wireless access")
	assert(remoteBranch:find("resolveOpenTerminal", 1, true) == nil,
		"remote branch falls back to physical terminal resolution")
	local denyAt = assert(body:find("if remoteAccess and not accessOk then", physicalStart, true))
	local defaultAt = assert(body:find("Network.getDefaultNetworkId()", denyAt, true))
	assert(denyAt < defaultAt, "remote denial can fall through to default network")
	contains(body:sub(denyAt, defaultAt - 1), "return",
		"remote denial does not return before default fallback")
end)

check("ItemActions keeps exact fullType callbacks with a compatible default", function()
	for _, name in ipairs({
		"GS_I18n", "GS_NetClient", "GS_TerminalUI_Api", "GS_TerminalAccess",
		"GS_PlayerUtils", "GS_DepositClient", "GS_DepositSources", "GS_TransferMenu",
		"GS_ContextMenu", "GS_TerminalInstallReaderChoice", "GS_KeyBinding", "GS_Log",
		"GS_InstallTerminalReader", "GS_Config", "GS_Sandbox", "GS_CraftUtils",
		"GS_DiskProgramming", "TimedActions/GS_ProgramDiskAction",
		"TimedActions/GS_AddonInstallAction", "TimedActions/ISTimedActionQueue",
		"GS_AddonRegistry", "GS_Network", "GS_Addons", "ISUI/ISContextMenu",
		"ISUI/ISInventoryPaneContextMenu",
	}) do
		package.loaded[name] = true
	end
	GlobalStorageSiK.I18n = { text = function(key) return key end }
	Events = { OnPreFillInventoryObjectContextMenu = { Add = function() end } }
	dofile(coreClient .. "GS_ItemActions.lua")
	local customCalls = 0
	local custom = function() customCalls = customCalls + 1 end
	GlobalStorageSiK.ItemActions.registerTabletItem("Contract.Default", "label.default")
	GlobalStorageSiK.ItemActions.registerTabletItem("Contract.Custom", "label.custom", custom)
	assert(GlobalStorageSiK.ItemActions._tabletItemLabels["Contract.Default"] == "label.default"
		and GlobalStorageSiK.ItemActions._tabletItemLabels["Contract.Custom"] == "label.custom",
		"labels are not keyed by exact fullType")
	assert(GlobalStorageSiK.ItemActions._tabletItemActions["Contract.Default"]
		== GlobalStorageSiK.ItemActions.onUseTerminalTablet,
		"registration without callback lost the compatible default")
	assert(GlobalStorageSiK.ItemActions._tabletItemActions["Contract.Custom"] == custom,
		"custom fullType callback was not preserved")
	GlobalStorageSiK.ItemActions._tabletItemActions["Contract.Custom"]()
	assert(customCalls == 1, "custom callback was not invocable")
	local source = read(coreClient .. "GS_ItemActions.lua")
	contains(source, "_tabletItemActions[fullType]", "menu does not resolve callback by fullType")
	contains(source, "or GlobalStorageSiK.ItemActions.onUseTerminalTablet",
		"menu lost default callback fallback")
	local registrations = read(tabletClient .. "GSSiK_Addon_Tablet_Client.lua")
	for _, fullTypeSymbol in ipairs({
		"ITEM_TABLET", "ITEM_TABLET_CRAFT", "ITEM_TABLET_BUILDER", "ITEM_TABLET_MASTER",
	}) do
		contains(registrations, "registerTabletItem(GSSiK_Addon_Tablet." .. fullTypeSymbol,
			"Tablet client does not register " .. fullTypeSymbol)
	end
end)

print(string.format("tablet_remote_api_contract: pass=%d fail=%d", passCount, #failures))
if #failures > 0 then error(table.concat(failures, "\n")) end
