-- Bounded, language-independent comparison token; never an authorization token.
-- Unknown persisted conditions remain removable without interpreting their path.
GlobalStorageSiK = GlobalStorageSiK or {}
local Identity = {}
GlobalStorageSiK.RuleIdentity = Identity

function Identity.signature(rule)
	if type(rule) ~= "table" or type(rule.condition) ~= "table" then return nil end
	local parts, size, entries, seen = {}, 0, 0, {}
	local function append(value)
		size = size + #value
		if size > 8192 then return false end
		parts[#parts + 1] = value
		return true
	end
	local encode
	encode = function(value, depth)
		local kind = type(value)
		if kind == "string" then return append("s" .. tostring(#value) .. ":" .. value) end
		if kind == "boolean" then return append(value and "b1" or "b0") end
		if kind == "number" then
			if value ~= value or value == math.huge or value == -math.huge then return false end
			return append("n" .. tostring(value) .. ";")
		end
		if kind ~= "table" or depth > 4 or seen[value] or getmetatable(value) ~= nil then return false end
		seen[value] = true
		local keys = {}
		for key in pairs(value) do
			if type(key) ~= "string" and (type(key) ~= "number" or key ~= math.floor(key)
				or key < 1 or key > 128) then return false end
			entries = entries + 1
			if entries > 128 then return false end
			keys[#keys + 1] = key
		end
		table.sort(keys, function(a, b)
			if type(a) ~= type(b) then return type(a) < type(b) end
			return a < b
		end)
		if not append("{") then return false end
		for index = 1, #keys do
			local key = keys[index]
			if not encode(key, depth + 1) or not encode(value[key], depth + 1) then return false end
		end
		seen[value] = nil
		return append("}")
	end
	if not encode({ op = rule.op, condition = rule.condition }, 0) then return nil end
	return table.concat(parts)
end

function Identity.matches(rules, index, expected)
	if type(index) ~= "number" or index ~= math.floor(index) or index < 1 or index > 20
		or type(expected) ~= "string" or #expected == 0 or #expected > 8192 then return false end
	local actual = rules and Identity.signature(rules[index])
	return actual ~= nil and actual == expected
end

return Identity
