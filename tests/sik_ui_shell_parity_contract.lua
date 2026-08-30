-- Generic author contract for the responsive SiK UI terminal shell.
-- Static checks guard wiring/chrome; pure checks guard player viewport,
-- profile geometry and per-player remembered bounds without starting PZ.

local Support = dofile("tests/helpers/sik_ui_contract_support.lua")
local suite = Support.newSuite("sik_ui_shell_parity_contract")

local CLIENT = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/"
local SHARED = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/"

local function read(path)
	local file = assert(io.open(path, "rb"), path)
	local text = file:read("*a")
	file:close()
	return text
end

local function contains(text, needle, label)
	assert(text:find(needle, 1, true), label or ("missing " .. needle))
end

local function excludes(text, needle, label)
	assert(not text:find(needle, 1, true), label or ("unexpected " .. needle))
end

local function countPlain(text, needle)
	local count, cursor = 0, 1
	while true do
		local at = text:find(needle, cursor, true)
		if not at then return count end
		count = count + 1
		cursor = at + #needle
	end
end

local function ordered(text, needles, label)
	local cursor = 1
	for i = 1, #needles do
		local at = text:find(needles[i], cursor, true)
		assert(at, (label or "ordered contract") .. " missing/out of order: " .. needles[i])
		cursor = at + #needles[i]
	end
end


local function section(text, firstMarker, nextMarker)
	local first = assert(text:find(firstMarker, 1, true), "missing section " .. firstMarker)
	local last = nextMarker and text:find(nextMarker, first + #firstMarker, true) or nil
	return text:sub(first, last and (last - 1) or #text)
end

local terminal = read(CLIENT .. "GS_TerminalUI.lua")
local api = read(CLIENT .. "GS_TerminalUI_Api.lua")
local blocked = read(CLIENT .. "GS_TerminalUI_Blocked.lua")
local tabs = read(CLIENT .. "GS_TerminalUI_Tabs.lua")
local rail = read(CLIENT .. "GS_TerminalUI_TabRail.lua")
local core = read(CLIENT .. "GS_SiK_UI_Core.lua")
local controlsSource = read(CLIENT .. "GS_SiK_UI_Controls.lua")
local windowSource = read(CLIENT .. "GS_SiK_UI_Window.lua")

Support.check(suite, "terminal loads the modular foundation in dependency order", function()
	ordered(terminal, {
		'require "GS_SiK_UI_Metrics"',
		'require "GS_SiK_UI_Viewport"',
		'require "GS_SiK_UI_Controls"',
		'require "GS_SiK_UI_Block"',
		'require "GS_SiK_UI_State"',
		'require "GS_TerminalUI_Scroll"',
		'require "GS_SiK_UI_List"',
		'require "GS_SiK_UI_Table"',
		'require "GS_SiK_UI_Window"',
		'require "GS_SiK_UI_Modal"',
	}, "terminal foundation order")
	return true
end)

Support.check(suite, "public and blocked APIs enter through Window Metrics Viewport chain", function()
	contains(api, 'require "GS_SiK_UI_Window"', "API must load Window")
	contains(blocked, 'require "GS_SiK_UI_Window"', "blocked API must load Window")
	ordered(windowSource, {
		"GS_SiK_UI_Metrics",
		"GS_SiK_UI_Viewport",
	}, "Window dependency order")
	return true
end)

Support.check(suite, "Tabs declares its Metrics dependency", function()
	contains(tabs, 'require "GS_SiK_UI_Metrics"', "Tabs must be independently loadable")
	return true
end)

Support.check(suite, "TabRail declares its Metrics dependency", function()
	contains(rail, 'require "GS_SiK_UI_Metrics"', "TabRail must be independently loadable")
	return true
end)

Support.check(suite, "show blocked and transition paths never read the global screen", function()
	excludes(api, "getCore(", "public show path bypasses Viewport")
	excludes(blocked, "getCore(", "blocked path bypasses Viewport")
	excludes(tabs, "getCore(", "access-mode transition bypasses Viewport")
	return true
end)

Support.check(suite, "full and blocked initial rectangles use recall then resolveProfile", function()
	local fullRect = section(api, "local function resolveShellRect", "local function closeMainTerminal")
	ordered(fullRect, {
		"SiK_UI.Viewport.resolve(playerNum)",
		'SiK_UI.Window.recall("terminal-shell", playerNum, viewport)',
		"SiK_UI.Window.resolveProfile(viewport.profile, viewport",
	}, "full shell rect")
	local blockedShow = section(blocked,
		"function GlobalStorageSiK.TerminalBlockedUI.showFromMain",
		"function GlobalStorageSiK.TerminalBlockedUI.show(state)")
	contains(blockedShow, "SiK_UI.Viewport.resolve(playerNum)", "blocked viewport")
	contains(blockedShow, 'SiK_UI.Window.recall("terminal-shell", playerNum, viewport)',
		"blocked recall")
	contains(blockedShow, "SiK_UI.Window.resolveProfile(viewport.profile, viewport",
		"blocked responsive initial rect")
	return true
end)

Support.check(suite, "terminal owns one contentHost and layout owns its dimensions", function()
	assert(countPlain(tabs, "terminal.contentHost = ISPanel:new") == 1,
		"contentHost must be created exactly once")
	excludes(tabs, "terminal.contentHost:setWidth", "Tabs must not own shell width")
	excludes(tabs, "terminal.contentHost:setHeight", "Tabs must not own shell height")
	contains(terminal, "self.contentHost:setWidth(contentW)", "shell layout owns full width")
	contains(terminal, "self.contentHost:setHeight(bodyH)", "shell layout owns full height")
	return true
end)

Support.check(suite, "footer is rendered every frame rather than during layout", function()
	local prerender = section(terminal, "function GS_TerminalUI:prerender()",
		"function GS_TerminalUI:applyCapacityState")
	contains(prerender, "SiK_UI.renderStatusFooter(self, self.terminalState)",
		"footer missing from prerender")
	local layout = section(terminal, "function GS_TerminalUI:calculateLayout()",
		"function GS_TerminalUI:rebuildScrollContent()")
	excludes(layout, "SiK_UI.renderStatusFooter", "layout must not issue draw calls")
	return true
end)

Support.check(suite, "terminal delegates Escape exclusively to the per-player stack", function()
	excludes(terminal, "function GS_TerminalUI:onKeyRelease",
		"terminal defines a second Escape close path on key release")
	return true
end)

Support.check(suite, "blocked and full modes reuse the same terminal shell", function()
	contains(api, "getInstanceForPlayer(playerNum)",
		"blocked API does not route the shared shell by local player")
	contains(api, 'applyAccessMode(ui, "blocked", payload)', "blocked transition")
	contains(blocked, "ui = GS_TerminalUI:new(rect.x, rect.y, rect.w, rect.h, playerNum)",
		"blocked creates the shared shell class")
	excludes(blocked, "ISPanel:derive", "blocked must not define another window class")
	contains(tabs, "Blocked y full son estados del mismo Shell", "shared-shell invariant")
	return true
end)

Support.check(suite, "close move and resize remember geometry per local player", function()
	assert(countPlain(terminal,
		'SiK_UI.Window.remember(me, "terminal-shell", me.playerNum)') >= 4,
		"mouse handlers do not persist all geometry exits")
	contains(terminal, 'SiK_UI.Window.remember(self, "terminal-shell", self.playerNum)',
		"close does not persist geometry")
	contains(terminal, ":applyResponsiveBounds", "mouse path does not clamp")
	contains(terminal, "Viewport.resolve(self.playerNum or 0)", "clamp ignores local player")
	return true
end)

Support.check(suite, "terminal shell inventory declares all responsive variants", function()
	contains(terminal, 'SurfaceInventory.get("terminal-shell")', "surface lookup")
	contains(terminal, 'id = "terminal-shell"', "surface ID")
	contains(terminal, 'variants = { "compact", "standard", "wide" }', "surface variants")
	return true
end)

Support.check(suite, "header owns only title and fixed close rects", function()
	local header = section(core, "function GlobalStorageSiK.SiK_UI.renderHeader(panel)",
		"function GlobalStorageSiK.SiK_UI.runtimeVersionText()")
	excludes(header, '" - "', "header must not render hyphen separator")
	excludes(header, "MOD_VERSION", "header must not render build version")
	excludes(header, "modversion", "header must not render mod.info version")
	contains(header, "state.networkName", "header must consume authoritative network display name")
	contains(header, "state.networkId ~= nil", "linked network fallback must remain distinct from unlinked terminal")
	contains(header, 'T("IGUI_GS_TerminalTitle")', "unlinked terminal fallback")
	contains(header, "truncateText(title, rects.title.w", "dynamic network name must be clipped to title rect")
	contains(header, "resolveHeaderRects(panel)", "header bypasses its measured title rect")
	contains(terminal, "self._sikHeaderRects.close", "close button bypasses fixed rect")
	contains(terminal, "renderWindowFrame(self)", "frame is not restored after footer chrome")
	return true
end)

Support.check(suite, "Connected footer key exists in English and Spanish", function()
	local en = read(SHARED .. "Translate/EN/IG_UI.json")
	local es = read(SHARED .. "Translate/ES/IG_UI.json")
	contains(en, '"IGUI_GS_Connected": "Connected"', "English Connected key")
	contains(es, '"IGUI_GS_Connected": "Conectado"', "Spanish Connected key")
	contains(core, 'T("IGUI_GS_Connected")', "footer consumes Connected key")
	return true
end)

-- Pure foundation checks. Common support supplies dependency sentinels only;
-- these modules do not instantiate PZ widgets.
Support.loadClientModule(suite, "GS_SiK_UI_Metrics")
Support.loadClientModule(suite, "GS_SiK_UI_Viewport")
Support.loadClientModule(suite, "GS_SiK_UI_Window")
Support.loadClientModule(suite, "GS_SiK_UI_State")

local ui = GlobalStorageSiK.SiK_UI
local Metrics = ui.Metrics
local Viewport = ui.Viewport
local Window = ui.Window
local Inventory = ui.SurfaceInventory

Support.check(suite, "compact standard wide rails and shell chrome are canonical", function()
	local expected = {
		compact = { rail = 76, item = 60, icon = 44 },
		standard = { rail = 96, item = 68, icon = 52 },
		wide = { rail = 104, item = 68, icon = 52 },
	}
	for name, values in pairs(expected) do
		local profile = Metrics.profile(name)
		assert(profile.window.railWidth == values.rail, name .. " rail width")
		assert(profile.window.railItemHeight == values.item, name .. " item height")
		assert(profile.window.railIconSize == values.icon, name .. " rail icon size")
		assert(profile.window.railGap == 4, name .. " rail gap")
		assert(profile.window.headerHeight == 48, name .. " header height")
		assert(profile.window.footerHeight == 48, name .. " footer height")
	end
	assert(Metrics.tokens().resizeHandle == 24, "shared resize handle")
	contains(controlsSource, "resizeHandle = SiK_UI.Metrics.tokens().resizeHandle",
		"Controls duplicates the resize handle instead of consuming Metrics")
	contains(terminal, "SiK_UI.Metrics.tokens().resizeHandle",
		"terminal duplicates the resize handle instead of consuming Metrics")
	return true
end)

Support.check(suite, "shell rectangles and bidirectional resize share one geometry owner", function()
	local boxes = Metrics.shellRects("standard", 1100, 700, false)
	assert(boxes.header.h == 48 and boxes.footer.h == 48, "shell chrome rects")
	assert(boxes.rail.w == 96 and boxes.content.x == 96, "rail/content axis")
	assert(boxes.content.h == 604 and boxes.footer.y == 652, "body/footer partition")
	local panel = {
		x = 100, y = 100, width = 720, height = 480, playerNum = 0,
		_sikWindowProfile = "standard", minimumWidth = 720, minimumHeight = 480,
		maximumWidth = 1168, maximumHeight = 868,
	}
	assert(Window.resizeEdgeAt(panel, 1, 1, Metrics.tokens().resizeHandle) == "top-left",
		"top-left handle")
	assert(Window.resizeEdgeAt(panel, 719, 240, Metrics.tokens().resizeHandle) == "right",
		"right handle")
	local viewport = { x = 16, y = 16, w = 1168, h = 868, profile = "standard", playerNum = 0 }
	local grown = Window.resizeDelta(panel, "bottom-right", 300, 200, viewport)
	assert(grown.w == 1020 and grown.h == 680, "resize does not grow")
	Support.assertWithin(grown, viewport, "bidirectional resize")
	for _, case in ipairs({
		{ profile = "compact", width = 720 },
		{ profile = "standard", width = 1100 },
		{ profile = "wide", width = 1280 },
	}) do
		local header = Metrics.headerRects(case.profile, case.width, 14)
		assert(header.close.w == 28 and header.close.h == 28, case.profile .. " fixed close")
		assert(header.close.x + header.close.w == case.width - 14, case.profile .. " right margin")
		assert(header.title.x + header.title.w + header.gap <= header.close.x,
			case.profile .. " title overlaps close")
		assert(header.version == nil, case.profile .. " header owns a version rect")
	end
	return true
end)

Support.check(suite, "rail consumes profile icon size without changing slot hitboxes", function()
	contains(rail, "profile.window.railIconSize", "rail ignores the profile icon size")
	contains(rail, "profile.window.railItemHeight", "rail slot height left the profile")
	contains(rail, "self.width - self.padding * 2", "rail slot does not consume useful width")
	excludes(rail, "itemHeight = profile.window.railIconSize",
		"visual icon size replaced the validated slot hitbox")
	return true
end)

Support.check(suite, "footer reports Core and active addon versions only in runtime chrome", function()
	local footer = section(core,
		"function GlobalStorageSiK.SiK_UI.runtimeVersionText()",
		"function GlobalStorageSiK.SiK_UI.setupHeaderDrag(panel)")
	contains(footer, "MOD_VERSION", "footer omits the Core runtime version")
	contains(footer, "runtime.VERSION", "footer omits active addon versions")
	contains(footer, "runtimeVersionText", "footer does not consume runtime versions")
	excludes(footer, '" · "', "footer uses a renderer-unsafe separator")
	excludes(terminal, 'drawText("Core ', "version text leaked into a tab body")
	return true
end)

Support.check(suite, "raw local-player viewports select profiles and reserve safe16", function()
	local cases = {
		{ raw = { x = 0, y = 0, w = 800, h = 600 }, profile = "compact" },
		{ raw = { x = 100, y = 40, w = 1280, h = 720 }, profile = "standard" },
		{ raw = { x = 1600, y = 0, w = 1600, h = 900 }, profile = "wide" },
	}
	for index, case in ipairs(cases) do
		local playerNum = index + 2
		local viewport = Viewport.resolve(playerNum, {
			screenW = 3200,
			screenH = 1800,
			playerRect = function(requested)
				assert(requested == playerNum, "wrong player viewport requested")
				return case.raw
			end,
		})
		assert(viewport.x == case.raw.x + 16 and viewport.y == case.raw.y + 16,
			case.profile .. " safe origin")
		assert(viewport.w == case.raw.w - 32 and viewport.h == case.raw.h - 32,
			case.profile .. " safe size")
		assert(viewport.profile == case.profile, case.profile .. " breakpoint")
		assert(viewport.playerNum == playerNum, case.profile .. " player identity")
	end
	return true
end)

Support.check(suite, "window minima degrade inside every player viewport", function()
	local viewports = {
		{ x = 16, y = 16, w = 368, h = 248, profile = "compact", playerNum = 0 },
		{ x = 976, y = 16, w = 928, h = 1048, profile = "standard", playerNum = 1 },
		{ x = 16, y = 16, w = 1568, h = 868, profile = "wide", playerNum = 2 },
	}
	for _, viewport in ipairs(viewports) do
		local rect = Window.resolveProfile(viewport.profile, viewport, {
			minWidth = 720, minHeight = 480,
		})
		Support.assertWithin(rect, viewport, viewport.profile .. " shell")
		assert(rect.w <= viewport.w and rect.h <= viewport.h, "minimum overflow")
	end
	return true
end)

Support.check(suite, "arbitrary resize rectangles clamp to the exact safe player viewport", function()
	local viewport = { x = 816, y = 16, w = 768, h = 868,
		profile = "compact", playerNum = 3 }
	local cases = {
		{ x = -900, y = -700, w = 2400, h = 1600 },
		{ x = 4000, y = 2200, w = 32, h = 24 },
		{ x = 1000, y = 300, w = 720, h = 480 },
	}
	for i = 1, #cases do
		local raw = cases[i]
		raw.profile, raw.playerNum = "compact", 3
		local clamped = Window.clampRect(raw, viewport)
		Support.assertWithin(clamped, viewport, "resize case " .. tostring(i))
		assert(clamped.playerNum == 3, "resize lost local player identity")
	end
	return true
end)

Support.check(suite, "remembered shell geometry is isolated and clamped per player", function()
	Window.forget("terminal-shell", 0)
	Window.forget("terminal-shell", 1)
	local function panel(x, y, w, h, playerNum)
		return {
			playerNum = playerNum,
			_sikWindowProfile = "standard",
			getX = function() return x end,
			getY = function() return y end,
			getWidth = function() return w end,
			getHeight = function() return h end,
		}
	end
	Window.remember(panel(-500, -500, 1000, 700, 0), "terminal-shell", 0)
	Window.remember(panel(1800, 200, 760, 560, 1), "terminal-shell", 1)
	local v0 = { x = 16, y = 16, w = 928, h = 688, profile = "standard", playerNum = 0 }
	local v1 = { x = 976, y = 16, w = 928, h = 688, profile = "standard", playerNum = 1 }
	local r0 = Window.recall("terminal-shell", 0, v0)
	local r1 = Window.recall("terminal-shell", 1, v1)
	Support.assertWithin(r0, v0, "player 0 recalled shell")
	Support.assertWithin(r1, v1, "player 1 recalled shell")
	assert(r0.playerNum == 0 and r1.playerNum == 1, "player memory crossed")
	assert(r0.x ~= r1.x, "players unexpectedly share shell position")
	return true
end)

Support.check(suite, "runtime surface inventory returns the terminal shell variants", function()
	assert(type(Inventory) == "table", "SurfaceInventory missing")
	-- Static registration is not executed in this pure harness; register the
	-- exact public declaration once to verify the inventory contract itself.
	if not Inventory.get("terminal-shell") then
		Inventory.register({ id = "terminal-shell", pack = "terminal-contenedor",
			owner = "GS_TerminalUI", parent = "UIManager",
			variants = { "compact", "standard", "wide" } })
	end
	local surface = Inventory.get("terminal-shell")
	assert(surface and surface.id == "terminal-shell", "terminal shell not inventoried")
	assert(#surface.variants == 3, "terminal shell variants incomplete")
	assert(surface.variants[1] == "compact" and surface.variants[2] == "standard"
		and surface.variants[3] == "wide", "terminal shell variant order")
	return true
end)

Support.finish(suite)
