-- Global Storage adapter for the product-neutral SiK UI diagnostics contract.
-- Widget traversal, geometry and overlap analysis belong to the framework;
-- this module only preserves existing product-facing calls and its Sandbox gate.

require "GS_Sandbox"
require "GS_Log"
local UI = require "GS_UI_Framework"

GlobalStorageSiK.UIDebug = GlobalStorageSiK.UIDebug or {}

function GlobalStorageSiK.UIDebug.enabled()
	return GlobalStorageSiK.Sandbox ~= nil
		and GlobalStorageSiK.Sandbox.debugMode ~= nil
		and GlobalStorageSiK.Sandbox.debugMode() == true
		and GlobalStorageSiK.Sandbox.debugCategoryEnabled("SiKUI") == true
end

local function out(kind, message)
	if UI.Diagnostics and UI.Diagnostics.event then
		UI.Diagnostics.event(kind, message)
	end
end

function GlobalStorageSiK.UIDebug.log(category, message, ...)
	if not GlobalStorageSiK.UIDebug.enabled() then return end
	local text = message
	if select("#", ...) > 0 then
		local ok, formatted = pcall(string.format, message, ...)
		if ok then text = formatted end
	end
	out("product", tostring(category) .. " > " .. tostring(text))
end

function GlobalStorageSiK.UIDebug.dumpTree(root, label)
	if not GlobalStorageSiK.UIDebug.enabled() or not root then return nil end
	return UI.Diagnostics.snapshot(root, label)
end

function GlobalStorageSiK.UIDebug.checkOverlaps(root, label)
	if not GlobalStorageSiK.UIDebug.enabled() or not root then return nil end
	local options = {
		ignore = function(widget)
			return UI.Scroll and UI.Scroll.isScrollBarWidget
				and UI.Scroll.isScrollBarWidget(widget) == true
		end,
	}
	local overlaps = UI.Diagnostics.checkOverlaps(root, label, options)
	local containment = UI.Diagnostics.checkContainment(root, label, options)
	return { overlaps = overlaps, containment = containment }
end

function GlobalStorageSiK.UIDebug.wrapClick(label, onClick)
	if onClick == nil then return nil end
	return function(target, ...)
		if GlobalStorageSiK.UIDebug.enabled() then
			out("interaction", "CLICK > " .. tostring(label))
		end
		return onClick(target, ...)
	end
end

function GlobalStorageSiK.UIDebug.action(what, detail)
	if not GlobalStorageSiK.UIDebug.enabled() then return end
	local message = "ACTION > " .. tostring(what)
	if detail ~= nil then message = message .. " | " .. tostring(detail) end
	out("interaction", message)
end

-- Product-owned sink: the Global Storage option records only integration
-- events through its logger/category. SiK UI keeps a separate self-owned sink
-- and Sandbox page for framework-internal diagnostics.
if UI.Diagnostics and UI.Diagnostics.registerSink then
	UI.Diagnostics.registerSink("GSSiK.UIIntegration", {
		enabled = GlobalStorageSiK.UIDebug.enabled,
		sink = function(event)
			GlobalStorageSiK.Log.debug("TerminalUI",
				tostring(event and event.kind or "event"),
				tostring(event and event.message or ""))
		end,
	})
end
