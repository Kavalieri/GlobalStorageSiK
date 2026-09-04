local CLIENT = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/"
local CALLER_PATH = CLIENT .. "GS_TerminalUI_Options.lua"
local GENERATED_PATH = CLIENT .. "GlobalStorageSiK/UI/Generated/TabOptions.lua"
local CONTEXT_PATH = CLIENT .. "GlobalStorageSiK/UI/TabOptionsContext.lua"

local function read(path)
	local handle = assert(io.open(path, "rb"), "missing required tab-options module: " .. path)
	local source = handle:read("*a")
	handle:close()
	return source
end

local function contains(source, literal)
	return string.find(source, literal, 1, true) ~= nil
end

local callerSource = read(CALLER_PATH)
local generatedSource = read(GENERATED_PATH)

assert(contains(generatedSource, '["id"] = "tab-options"'),
	"the caller must consume the generated tab-options artifact")
assert(contains(callerSource, 'require "GlobalStorageSiK/UI/Generated/TabOptions"'),
	"GS_TerminalUI_Options must require the generated visual artifact")
assert(contains(callerSource, 'require "GlobalStorageSiK/UI/TabOptionsContext"'),
	"GS_TerminalUI_Options must require its product context adapter")
assert(contains(callerSource, "SiK.UI.SurfaceHost.mount"),
	"tab-options must be composed by the public SiK.UI SurfaceHost")
assert(contains(callerSource, "followParent = true"),
	"tab-options must follow its final parent geometry")
assert(contains(callerSource, "TabOptionsContext.create"),
	"the real caller owns one context adapter instance")
assert(contains(callerSource, ":snapshot("),
	"the caller updates the surface from immutable context snapshots")
assert(contains(callerSource, ":dispose("),
	"the caller must release its context with the surface")

local FORBIDDEN_CALLER = {
	"GS_TerminalUI_Scroll",
	"TerminalScroll.",
	"TerminalNetworkList.build",
	"TerminalNetworkList.layout",
	"TerminalNetworkStatus.build",
	"TerminalNetworkStatus.layout",
	"TerminalNetworkTerminals.build",
	"TerminalNetworkTerminals.layout",
	"TerminalPermissions.ensureInNetworkScroll",
	"TerminalPermissions.repositionBlock",
	"UI.Controls.",
	"UI.Tabs.create",
	"UI.Table.create",
	"ISPanel:new",
}
for index = 1, #FORBIDDEN_CALLER do
	local symbol = FORBIDDEN_CALLER[index]
	assert(not contains(callerSource, symbol),
		"caller still constructs tab-options manually: " .. symbol)
end

local contextSource = read(CONTEXT_PATH)

local FORBIDDEN_CONTEXT_RENDERING = {
	"ISPanel", "ISLabel", "ISButton", "ISComboBox", "ISScrollingListBox",
	"UI.Controls", "UI.Table", "UI.Tabs", "UI.Block", "UI.Scroll",
	"addChild", "drawText", "drawRect", "prerender", "render =",
	"setX(", "setY(", "setWidth(", "setHeight(",
}
for index = 1, #FORBIDDEN_CONTEXT_RENDERING do
	local symbol = FORBIDDEN_CONTEXT_RENDERING[index]
	assert(not contains(contextSource, symbol),
		"TabOptionsContext must prepare data, never render: " .. symbol)
end

assert(contains(contextSource, "function TabOptionsContext.create")
	or contains(contextSource, "TabOptionsContext.create = function"),
	"TabOptionsContext.create is required")
assert(contains(contextSource, "function context:snapshot")
	or contains(contextSource, "function instance:snapshot"),
	"context handle must expose snapshot")
assert(contains(contextSource, "function context:dispose")
	or contains(contextSource, "function instance:dispose"),
	"context handle must expose dispose")

local previousRequire = require
local previousGlobalStorageSiK = GlobalStorageSiK
local previousSiK = SiK
GlobalStorageSiK = {
	UI = {},
	I18n = { text = function(key) return key end },
	NetClient = {
		sendCommand = function() return true end,
		sendNetworkCommand = function() return true end,
	},
	TerminalPermissions = {
		shouldShowTab = function() return true end,
	},
	Log = { error = function() end },
}

require = function(name)
	if name == "GlobalStorageSiK/UI/CapacityPresentation" then
		return dofile(CLIENT .. "GlobalStorageSiK/UI/CapacityPresentation.lua")
	end
	return true
end

local ok, loaded = pcall(dofile, CONTEXT_PATH)
require = previousRequire
assert(ok, loaded)
local TabOptionsContext = type(loaded) == "table" and loaded
	or GlobalStorageSiK.UI.TabOptionsContext
assert(type(TabOptionsContext) == "table" and type(TabOptionsContext.create) == "function",
	"context module must return or publish TabOptionsContext")

local terminal = {
	playerNum = 1,
	activeTabKey = "config",
	terminalState = {},
}
local context, createReason = TabOptionsContext.create(terminal)
assert(type(context) == "table", createReason)
assert(type(context.snapshot) == "function" and type(context.dispose) == "function")

local snapshot, snapshotReason = context:snapshot({
	networks = {
		{ id = "network-a", name = "Alpha", nodes = 2, zones = 1 },
	},
	activeNetworkId = "network-a",
	permissions = { role = "owner", members = {} },
})
assert(type(snapshot) == "table", snapshotReason)
assert(type(snapshot.data) == "table", "snapshot.data is required")
assert(type(snapshot.state) == "table", "snapshot.state is required")
assert(type(snapshot.conditions) == "table", "snapshot.conditions is required")
assert(type(snapshot.actions) == "table", "snapshot.actions is required")

local FORBIDDEN_PURE_KEYS = {
	component = true, widget = true, panel = true, control = true,
}
local function assertPlain(value, path, leafType, seen)
	local valueType = type(value)
	if valueType ~= "table" then
		if leafType then
			assert(valueType == leafType, path .. " must contain only " .. leafType)
		else
			assert(valueType == "string" or valueType == "number" or valueType == "boolean"
				or valueType == "nil", path .. " must contain only plain data")
		end
		return
	end
	seen = seen or {}
	assert(not seen[value], path .. " contains a cycle")
	seen[value] = true
	for key, child in pairs(value) do
		assert(type(key) == "string" or type(key) == "number",
			path .. " has a non-plain key")
		assert(not FORBIDDEN_PURE_KEYS[key], path .. " leaked product/UI owner key " .. tostring(key))
		assertPlain(child, path .. "." .. tostring(key), leafType, seen)
	end
	seen[value] = nil
end

assertPlain(snapshot.data, "snapshot.data")
assertPlain(snapshot.state, "snapshot.state")
assertPlain(snapshot.conditions, "snapshot.conditions", "boolean")
assertPlain(snapshot.actions, "snapshot.actions", "function")

assert(context:dispose() == true, "first context dispose releases resources")
assert(context:dispose() == false, "context dispose is idempotent")
GlobalStorageSiK = previousGlobalStorageSiK

-- Execute the real caller against narrow public doubles. This verifies the
-- adapter lifecycle rather than merely accepting the right symbol names.
local calls = {
	build = 0, create = 0, snapshot = 0, update = 0, reflow = 0,
	surfaceDispose = 0, contextDispose = 0,
}
local lastSnapshot, lastReflow
local surfaceDouble = {
	nodes = {
		["options-tabs"] = {
			setActive = function(_, key, notify)
				calls.activeKey, calls.activeNotify = key, notify
				return true
			end,
		},
	},
}
function surfaceDouble:refresh(snapshot)
	calls.update = calls.update + 1
	lastSnapshot = snapshot
	return true
end
function surfaceDouble:getTree()
	return self
end
function surfaceDouble:reflow(bounds)
	calls.reflow = calls.reflow + 1
	lastReflow = bounds
	return true
end
function surfaceDouble:dispose()
	calls.surfaceDispose = calls.surfaceDispose + 1
	return calls.surfaceDispose == 1
end

local uiDouble = {
	SurfaceHost = {
		mount = function(parent, spec, options)
		calls.build = calls.build + 1
		calls.buildParent, calls.buildSpec = parent, spec
		lastSnapshot = options and options.context
		calls.buildOptions = options
		return surfaceDouble
		end,
	},
}
local contextModuleDouble = {
	create = function(terminalOwner)
		calls.create = calls.create + 1
		local adapter = { terminal = terminalOwner, disposed = false }
		function adapter:snapshot(state)
			calls.snapshot = calls.snapshot + 1
			return {
				data = { revision = state and state.revision },
				state = {}, conditions = {}, actions = {},
			}
		end
		function adapter:dispose()
			if self.disposed then return false end
			self.disposed = true
			calls.contextDispose = calls.contextDispose + 1
			return true
		end
		return adapter
	end,
}
local generatedDouble = { id = "tab-options" }

previousRequire = require
previousGlobalStorageSiK = GlobalStorageSiK
previousSiK = SiK
GlobalStorageSiK = { TerminalOptions = {} }
SiK = { UI = uiDouble }
require = function(name)
	if name == "GS_UI_Framework" then return uiDouble end
	if name == "GlobalStorageSiK/UI/Generated/TabOptions" then return generatedDouble end
	if name == "GlobalStorageSiK/UI/TabOptionsContext" then return contextModuleDouble end
	return true
end
local callerOk, Options = pcall(dofile, CALLER_PATH)
require = previousRequire
assert(callerOk, Options)

local panel = {
	width = 900, height = 620,
	getWidth = function(self) return self.width end,
	getHeight = function(self) return self.height end,
}
local runtimeTerminal = {
	playerNum = 2, configPanel = panel,
	terminalState = { revision = 10 },
}
local surface, buildReason = Options.buildSection(runtimeTerminal, panel)
assert(surface == surfaceDouble and buildReason == nil,
	"real caller did not return the public surface")
assert(calls.build == 1 and calls.create == 1 and calls.snapshot == 1,
	"one tab-options construction must use one context, snapshot and SiK.UI SurfaceHost")
assert(calls.buildParent == panel and calls.buildSpec == generatedDouble,
	"real caller did not pass the generated spec to the public builder")
assert(calls.buildOptions and calls.buildOptions.followParent == true,
	"real caller did not request final-parent geometry tracking")
assert(lastSnapshot.data.revision == 10 and lastSnapshot.viewport.w == 900
	and lastSnapshot.viewport.h == 620,
	"initial snapshot lost dynamic product data or current panel bounds")
assert(Options.ensureUi(runtimeTerminal) == surfaceDouble and calls.build == 1,
	"ensureUi rebuilt an existing tab-options surface")

local refreshedState = { revision = 11 }
assert(Options.refreshScroll(runtimeTerminal, refreshedState) == true,
	"runtime snapshot update did not reach the existing surface")
assert(calls.build == 1 and calls.snapshot == 2 and calls.update == 1
	and lastSnapshot.data.revision == 11,
	"refresh rebuilt the surface or reused a stale snapshot")

panel.width, panel.height = 960, 640
assert(Options.syncScrollLayout(runtimeTerminal) == true,
	"panel resize did not reflow the existing surface")
assert(calls.reflow == 1 and lastReflow.w == 960 and lastReflow.h == 640,
	"panel resize did not use the live panel bounds")
assert(Options.layout(runtimeTerminal, 1000, 700) == true,
	"explicit layout did not reflow the existing surface")
assert(calls.reflow == 2 and lastReflow.w == 1000 and lastReflow.h == 700
	and calls.build == 1,
	"reflow reconstructed the surface or lost explicit bounds")
assert(Options.activateSubTab(runtimeTerminal, "admin") == true
	and calls.activeKey == "admin" and calls.activeNotify == true,
	"tab activation bypassed the generated surface node")

assert(Options.dispose(runtimeTerminal) == true,
	"first options dispose did not release surface and context")
assert(calls.surfaceDispose == 1 and calls.contextDispose == 1
	and panel._sikOptionsSurface == nil and panel._sikOptionsContext == nil,
	"dispose leaked the built surface or product context")
assert(Options.dispose(runtimeTerminal) == false
	and calls.surfaceDispose == 1 and calls.contextDispose == 1,
	"options dispose is not idempotent")
GlobalStorageSiK = previousGlobalStorageSiK
SiK = previousSiK

print("tab_options_adapter_contract: OK")
