-- Author adversarial contract for Tablet capabilities and authoritative access.
-- Pure Lua 5.1: no Project Zomboid world, client or dedicated server is opened.

for _, name in ipairs({
	"GS_Config", "GS_Sandbox", "GS_Network", "GS_TerminalManifest",
	"GS_Permissions", "GS_Debug", "GS_Addons", "GS_TerminalRegistry",
	"GS_TerminalRecord",
	"GSSiK_Addon_Tablet_ItemHooks", "GSSiK_Addon_Tablet_Sandbox",
	"GSSiK_Addon_Tablet_Log", "GS_TerminalAccess",
}) do
	package.loaded[name] = true
end

SandboxVars = { GlobalStorageSiK = { AccessHysteresisTiles = 1 } }
local antennaByNetwork = {}
local registry = { networks = {} }

GlobalStorageSiK = {
	Config = {},
	Sandbox = {
		requireTerminalAccess = function() return true end,
		getTerminalProximityRange = function() return 2 end,
		getWirelessRange = function() return 0 end,
		debugMode = function() return false end,
	},
	Network = {
		getRegistry = function() return registry end,
		ensureRegistry = function() end,
		resolveNetworkId = function(networkId)
			return registry.networks[networkId] and networkId or nil
		end,
		getDefaultNetworkId = function() return nil end,
		findNetworkIdAtTerminal = function(x, y, z)
			for networkId, network in pairs(registry.networks) do
				for i = 1, #(network.terminals or {}) do
					local terminal = network.terminals[i]
					if terminal.active ~= false and terminal.x == x and terminal.y == y
						and (terminal.z or 0) == (z or 0) then return networkId end
				end
			end
			return nil
		end,
	},
	TerminalManifest = {
		getEffectiveManifest = function() return nil end,
	},
	Permissions = {
		canAccess = function(player, networkId)
			return player and player.allowed and player.allowed[networkId] == true,
				"no_permission"
		end,
	},
	Debug = { log = function() end },
	Addons = {},
}

GlobalStorageSiK.TerminalRegistry = {
	getAllTerminals = function(network)
		local out = {}
		for i = 1, #(network and network.terminals or {}) do
			local terminal = network.terminals[i]
			if terminal.active ~= false then out[#out + 1] = terminal end
		end
		return out
	end,
	getActiveAnchor = function(network)
		for i = 1, #(network and network.terminals or {}) do
			if network.terminals[i].active ~= false then return network.terminals[i] end
		end
		return nil
	end,
}

GlobalStorageSiK.TerminalRecord = {
	collectActiveAnchors = function(network)
		local out = {}
		for i = 1, #(network and network.terminals or {}) do
			local terminal = network.terminals[i]
			if terminal.active ~= false then out[#out + 1] = terminal end
		end
		return out
	end,
}

local coreShared = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/"
dofile(coreShared .. "GS_TerminalAccess.lua")
package.loaded["GS_TerminalAccess"] = true

GSSiK_Addon_Tablet = {
	Sandbox = {
		getTier1Range = function() return 25 end,
		getTier2Range = function() return 50 end,
		getTier3Range = function() return 100 end,
	},
	Log = { debug = function() end },
}

GlobalStorageSiK.Addons.isInstalled = function(networkId)
	return antennaByNetwork[networkId] ~= nil
end
GlobalStorageSiK.Addons.serializeForTerminal = function(networkId)
	local itemType = antennaByNetwork[networkId]
	return { TabletLink = itemType and { itemType = itemType } or nil }
end
GlobalStorageSiK.Addons.canUseTabletWireless = function(networkId)
	local itemType = antennaByNetwork[networkId]
	return itemType == "GSSiK_Addon_Tablet.GS_WifiAntenna"
		or itemType == "GSSiK_Addon_Tablet.GS_WifiAntenna_T2"
		or itemType == "GSSiK_Addon_Tablet.GS_WifiAntenna_T3"
end

local tabletShared = "addons/GSSiK_Addon_Tablet/Contents/mods/GSSiK_Addon_Tablet/42/media/lua/shared/"
dofile(tabletShared .. "GSSiK_Addon_Tablet_Access.lua")

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

local function player(name, playerNum, x, y, z, itemCounts, allowed)
	local inventory = {
		getItemCountRecurse = function(_, fullType) return itemCounts[fullType] or 0 end,
	}
	return {
		allowed = allowed or {},
		getUsername = function() return name end,
		getPlayerNum = function() return playerNum end,
		getInventory = function() return inventory end,
		getX = function() return x end,
		getY = function() return y end,
		getZ = function() return z end,
	}
end

local base = "GSSiK_Addon_Tablet.GS_Tablet"
local craft = "GSSiK_Addon_Tablet.GS_TabletCraft"
local builder = "GSSiK_Addon_Tablet.GS_TabletBuilder"
local master = "GSSiK_Addon_Tablet.GS_TabletMaster"
local t1 = "GSSiK_Addon_Tablet.GS_WifiAntenna"
local t2 = "GSSiK_Addon_Tablet.GS_WifiAntenna_T2"
local t3 = "GSSiK_Addon_Tablet.GS_WifiAntenna_T3"

check("each tablet fullType exposes its exact capability set", function()
	local fixtures = {
		{ base, "access", false, false },
		{ craft, "craft", true, false },
		{ builder, "builder", false, true },
		{ master, "master", true, true },
	}
	for i = 1, #fixtures do
		local fixture = fixtures[i]
		local value = player("cap" .. i, i, 0, 0, 0, { [fixture[1]] = 1 })
		assert(GlobalStorageSiK.TerminalAccess.hasAccessTablet(value), "access " .. fixture[1])
		assert(GlobalStorageSiK.TerminalAccess.hasCraftTablet(value) == fixture[3], "craft " .. fixture[1])
		assert(GlobalStorageSiK.TerminalAccess.hasBuilderTablet(value) == fixture[4], "builder " .. fixture[1])
		assert(GlobalStorageSiK.TerminalAccess.getTabletKind(value) == fixture[2], "kind " .. fixture[1])
	end
end)

check("wireless providers are replaced by id instead of duplicated", function()
	local before = #GlobalStorageSiK.TerminalAccess._wirelessProviders
	local first = { id = "contract-dedupe", hasAccess = function() return false end }
	local second = { id = "contract-dedupe", hasAccess = function() return false end,
		capabilities = { replacement = true } }
	GlobalStorageSiK.TerminalAccess.registerWirelessProvider(first)
	assert(#GlobalStorageSiK.TerminalAccess._wirelessProviders == before + 1,
		"first provider registration was not appended")
	GlobalStorageSiK.TerminalAccess.registerWirelessProvider(second)
	assert(#GlobalStorageSiK.TerminalAccess._wirelessProviders == before + 1,
		"same provider id was duplicated")
	local found = nil
	for i = 1, #GlobalStorageSiK.TerminalAccess._wirelessProviders do
		local provider = GlobalStorageSiK.TerminalAccess._wirelessProviders[i]
		if provider.id == "contract-dedupe" then found = provider end
	end
	assert(found == second and found.capabilities.replacement == true,
		"same provider id did not replace its definition")
end)

check("evaluateWireless uses only active same-floor authoritative anchors", function()
	registry.networks = { net = { terminals = {
		{ x = 1, y = 0, z = 0, active = false },
		{ x = 2, y = 0, z = 1, active = true },
		{ x = 25, y = 0, z = 0, active = true },
	} } }
	antennaByNetwork.net = t1
	local value = player("wireless", 0, 0, 0, 0, { [base] = 1 }, { net = true })
	local ok, mode, anchor, reason = GlobalStorageSiK.TerminalAccess.evaluateWireless(value, "net")
	assert(ok == true and mode == "wireless_access" and reason == nil,
		"eligible wireless access was rejected")
	assert(anchor and anchor.x == 25 and anchor.z == 0,
		"inactive or different-floor anchor was selected")
	assert(anchor.providerId == "TabletLink" and anchor.capabilities
		and anchor.capabilities.remoteTerminal == true,
		"provider identity or capabilities were not propagated")
	registry.networks.net.terminals[3].active = false
	ok, _, _, reason = GlobalStorageSiK.TerminalAccess.evaluateWireless(value, "net")
	assert(ok == false,
		"different-floor active anchor granted wireless access: " .. tostring(reason))
	registry.networks.net.terminals[2].active = false
	ok, _, _, reason = GlobalStorageSiK.TerminalAccess.evaluateWireless(value, "net")
	assert(ok == false and reason == "no_terminal",
		"inactive-only topology remained remotely eligible")
end)

check("T1 T2 T3 ranges and invalid antenna states are exact", function()
	local value = player("tiers", 0, 0, 0, 0, { [base] = 1 })
	local expected = { [t1] = 25, [t2] = 50, [t3] = 100 }
	for itemType, range in pairs(expected) do
		antennaByNetwork.net = itemType
		assert(GSSiK_Addon_Tablet.getWirelessRangeForNetwork(value, "net", {}) == range,
			itemType .. " range")
	end
	antennaByNetwork.net = nil
	assert(GSSiK_Addon_Tablet.getWirelessRangeForNetwork(value, "net", {}) == 0,
		"missing antenna granted range")
	antennaByNetwork.net = "Other.InvalidAntenna"
	assert(GSSiK_Addon_Tablet.getWirelessRangeForNetwork(value, "net", {}) == 0,
		"invalid installed tier must not fall back to T1")
end)

local function evaluateAt(itemType, distance, playerZ, anchorZ)
	antennaByNetwork.net = itemType
	registry.networks = { net = { terminals = {
		{ x = 0, y = 0, z = anchorZ or 0, active = true },
	} } }
	local value = player("edge", 0, distance, 0, playerZ or 0, { [base] = 1 }, { net = true })
	return GlobalStorageSiK.TerminalAccess.evaluate(value, "net",
		{ x = 0, y = 0, z = anchorZ or 0, networkId = "net" },
		{ ignoreSession = true, strictDistance = true })
end

check("tier edges are inclusive and immediately outside is rejected", function()
	for _, fixture in ipairs({ { t1, 25 }, { t2, 50 }, { t3, 100 } }) do
		local ok, mode = evaluateAt(fixture[1], fixture[2], 0, 0)
		assert(ok and mode == "wireless_access", "inclusive edge rejected for " .. fixture[1])
		ok = evaluateAt(fixture[1], fixture[2] + 0.01, 0, 0)
		assert(ok == false, "just-outside edge accepted for " .. fixture[1])
	end
end)

check("different z and absent or invalid antennas deny wireless", function()
	local ok = evaluateAt(t3, 1, 1, 0)
	assert(ok == false, "wireless crossed floors")
	ok = evaluateAt(nil, 3, 0, 0)
	assert(ok == false, "wireless succeeded without an antenna")
	ok = evaluateAt("Other.InvalidAntenna", 3, 0, 0)
	assert(ok == false, "wireless succeeded with an invalid antenna tier")
end)

check("multiple-network discovery filters permissions and inactive terminals", function()
	registry.networks = {
		nearDenied = { terminals = { { x = 1, y = 0, z = 0, active = true } } },
		nearInactive = { terminals = { { x = 2, y = 0, z = 0, active = false } } },
		farAllowed = { terminals = { { x = 10, y = 0, z = 0, active = true } } },
	}
	local value = player("member", 0, 0, 0, 0, { [base] = 1 }, { farAllowed = true })
	local terminal = GlobalStorageSiK.TerminalAccess.findNearestRegisteredTerminal(value, nil, 100)
	assert(terminal and terminal.networkId == "farAllowed" and terminal.x == 10,
		"discovery selected a denied or inactive network")
	value.allowed.farAllowed = false
	assert(GlobalStorageSiK.TerminalAccess.findNearestRegisteredTerminal(value, nil, 100) == nil,
		"discovery returned a network without membership")
end)

check("terminal active and absent states remain distinct", function()
	registry.networks = { net = { terminals = { { x = 4, y = 0, z = 0, active = true } } } }
	local value = player("terminal", 0, 0, 0, 0, { [base] = 1 }, { net = true })
	assert(GlobalStorageSiK.TerminalAccess.findNearestRegisteredTerminal(value, "net", 10) ~= nil,
		"active terminal was not found")
	registry.networks.net.terminals[1].active = false
	assert(GlobalStorageSiK.TerminalAccess.findNearestRegisteredTerminal(value, "net", 10) == nil,
		"inactive/absent terminal remained a candidate")
end)

check("antenna removal or downgrade between listing and click is revalidated", function()
	registry.networks = { net = { terminals = { { x = 90, y = 0, z = 0, active = true } } } }
	local value = player("stale", 0, 0, 0, 0, { [base] = 1 }, { net = true })
	antennaByNetwork.net = t3
	local ok = GlobalStorageSiK.TerminalAccess.evaluateWireless(value, "net")
	assert(ok == true, "T3 candidate was not initially eligible")
	antennaByNetwork.net = nil
	ok = GlobalStorageSiK.TerminalAccess.evaluateWireless(value, "net")
	assert(ok == false, "removed antenna retained stale eligibility")
	antennaByNetwork.net = t1
	ok = GlobalStorageSiK.TerminalAccess.evaluateWireless(value, "net")
	assert(ok == false, "downgraded antenna retained the old T3 range")
end)

check("sessions are isolated by local player, not only username", function()
	local p0 = player("local", 0, 0, 0, 0, { [base] = 1 }, { a = true })
	local p1 = player("local", 1, 0, 0, 0, { [base] = 1 }, { b = true })
	GlobalStorageSiK.TerminalAccess.setSessionAnchor(p0, { x = 1, y = 2, z = 0 }, "wireless", "a")
	GlobalStorageSiK.TerminalAccess.setSessionAnchor(p1, { x = 8, y = 9, z = 1 }, "wireless", "b")
	assert(GlobalStorageSiK.TerminalAccess.getSessionNetworkId(p0) == "a", "p0 session was overwritten")
	assert(GlobalStorageSiK.TerminalAccess.getSessionNetworkId(p1) == "b", "p1 session was overwritten")
	assert(GlobalStorageSiK.TerminalAccess.getSessionAnchor(p0).x == 1, "p0 anchor was overwritten")
	assert(GlobalStorageSiK.TerminalAccess.getSessionAnchor(p1).x == 8, "p1 anchor was overwritten")
end)

check("server resolution rejects manipulated coordinates and accepts the registered anchor", function()
	registry.networks = {
		net = { terminals = { { x = 50, y = 0, z = 0, active = true } } },
	}
	package.loaded["GS_TerminalRecord"] = true
	GlobalStorageSiK.TerminalRecord = {
		getPrimaryAnchor = function(network) return network.terminals[1] end,
	}
	GlobalStorageSiK.TerminalAccess.probeNearbyTerminal = function()
		return { x = 50, y = 0, z = 0, networkId = "net" }
	end
	dofile(coreShared .. "GS_NetworkResolve.lua")
	local value = player("attacker", 0, 0, 0, 0, { [base] = 1 }, { net = true })
	local networkId, probe, reason = GlobalStorageSiK.NetworkResolve.resolveOpenTerminal(value, {
		networkId = "net",
		terminalHint = { x = 0, y = 0, z = 0, networkId = "net" },
	})
	assert(networkId == nil and probe == nil and reason == "terminal_unlinked",
		"server accepted or silently rewrote manipulated client coordinates")
	networkId, probe, reason = GlobalStorageSiK.NetworkResolve.resolveOpenTerminal(value, {
		networkId = "net",
		terminalHint = { x = 50, y = 0, z = 0, networkId = "net" },
	})
	assert(networkId == "net" and reason == nil, "server rejected the registered terminal anchor")
	assert(probe and probe.x == 50 and probe.y == 0,
		"server did not preserve the authoritative registered coordinates")
end)

check("openTerminal source revalidates topology, permissions and distance", function()
	local path = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/server/GS_Server.lua"
	local handle = assert(io.open(path, "rb"))
	local source = handle:read("*a")
	handle:close()
	local first = assert(source:find("local function handleOpenTerminal", 1, true))
	local last = assert(source:find("local function handleInstallTerminalReader", first, true))
	local body = source:sub(first, last - 1)
	assert(body:find("NetworkResolve.resolveOpenTerminal(player, args)", 1, true), "missing server topology resolution")
	assert(body:find("TerminalAccess.evaluate(", 1, true), "missing authoritative range revalidation")
	assert(body:find("Permissions.canAccess(player, networkId)", 1, true), "missing membership revalidation")
	assert(body:find("activeOnly = true", 1, true), "terminal coordinate is not revalidated as active")
end)

print(string.format("tablet_remote_access_adversarial: pass=%d fail=%d", passCount, #failures))
if #failures > 0 then error(table.concat(failures, "\n")) end
