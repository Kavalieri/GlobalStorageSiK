-- Options adapts the same editor model as Staff. The world store never has a
-- network scope; this additional entry point is strictly singleplayer-only.
local Model = require "GS_NativeWorldEditorModel"
local Context = {}
local T = GlobalStorageSiK.I18n.text

function Context.available()
	return not (isClient and isClient()) and not (isServer and isServer())
end

function Context.i18n(target)
	for _, key in ipairs({ "Title", "Help", "Type", "Choice", "Reason", "Consult", "Apply", "Restore" }) do
		target["options.taxonomy." .. string.lower(key)] = T("IGUI_GS_WorldTax_" .. key)
	end
	target["options.taxonomy.help"] = T("IGUI_GS_WorldTax_HelpSP")
	return target
end

local function value(envelope)
	local payload = type(envelope) == "table" and envelope.payload or envelope
	if type(payload) == "table" then
		local selected = payload.value
		return type(selected) == "table" and selected.value or selected
	end
	return payload
end

function Context.create(playerNum, actions, refresh)
	local model = Context.available() and Model.create(playerNum) or nil
	local function action(id, fn)
		actions["options.taxonomy." .. id] = function(envelope)
			if not model or not Context.available() then return false, "singleplayer_only" end
			local ok, reason = fn(value(envelope))
			refresh()
			return ok ~= false, reason
		end
	end
	action("type", function(text) return model:setFullType(text) end)
	action("reason", function(text) return model:setReason(text) end)
	for i = 1, 3 do
		local level = i
		action("choice" .. level, function(id) return model:select(level, id) end)
	end
	action("consult", function() return model:lookup() end)
	action("apply", function() return model:submit("apply") end)
	action("restore", function() return model:submit("restore") end)
	return model
end

function Context.snapshot(model)
	if not model or not Context.available() then return {} end
	local state = model:snapshot()
	local data = {
		labelStyle = { wrap = true, tone = "text" },
		fullType = { text = state.fullType, enabled = not state.busy, maxLength = 160 },
		reason = { text = state.reason, enabled = not state.busy, maxLength = 512 },
		current = { text = state.current.text, tone = state.current.tone, wrap = true, framed = true },
		feedback = { text = state.feedback.text, tone = state.feedback.tone, wrap = true },
		consult = { enabled = not state.busy },
		apply = { enabled = state.canApply }, restore = { enabled = state.canRestore },
	}
	for i, key in ipairs({ "l1", "l2", "l3" }) do
		data["choice" .. i] = { items = state.choices[i], selected = state.selected[key],
			enabled = not state.busy and state.selected[key] ~= nil }
	end
	return data
end

return Context
