-- Bounded, deterministic configuration intents. Independent of content revisions.
require "GS_Config"
GlobalStorageSiK.RoutingProtocol = {}
local Protocol = GlobalStorageSiK.RoutingProtocol
Protocol.commands = {
	updateNode = true, updateZoneRules = true, applyNodeTemplateToZone = true,
	setZonePriority = true, moveZonePriority = true, setZoneEnabled = true,
	renameZone = true, updateZoneConfig = true,
}

function Protocol.revision(networkId)
	local registry = GlobalStorageSiK.Network.getRegistry()
	local network = registry.networks and registry.networks[networkId]
	return network and tonumber(network.routingRevision) or 0
end

-- Copies only a bounded plain tree. Also forms an unambiguous request identity;
-- neither table iteration order nor client-owned table references survive.
function Protocol.copy(value)
	local budget = { fields = 0, bytes = 0, seen = {} }
	local function visit(v, depth)
		budget.fields = budget.fields + 1
		if budget.fields > 512 or depth > 6 then return nil end
		local kind = type(v)
		if kind == "string" then
			budget.bytes = budget.bytes + #v
			if #v > 512 or budget.bytes > 16384 then return nil end
			return v, "s" .. #v .. ":" .. v
		elseif kind == "number" then
			if v ~= v or v == math.huge or v == -math.huge then return nil end
			return v, "n" .. tostring(v) .. ";"
		elseif kind == "boolean" then return v, v and "t" or "f"
		elseif kind ~= "table" or budget.seen[v] or getmetatable(v) ~= nil then return nil end
		budget.seen[v] = true
		local entries, result = {}, {}
		for k, item in pairs(v) do
			if type(k) ~= "string" and type(k) ~= "number" then return nil end
			local key, keyId = visit(k, depth + 1)
			local copy, itemId = visit(item, depth + 1)
			if not keyId or not itemId then return nil end
			result[key] = copy
			entries[#entries + 1] = keyId .. itemId
		end
		table.sort(entries)
		budget.seen[v] = nil
		return result, "{" .. table.concat(entries) .. "}"
	end
	return visit(value, 0)
end

return Protocol
