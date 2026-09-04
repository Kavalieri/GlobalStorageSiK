-- Authorial contract for the server-staff support panel.  The fixture loads
-- the real module with neutral PZ/SiK.UI doubles, then exercises lifecycle and
-- member-table composition instead of certifying migration by text counts.

local SOURCE_PATH = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/GS_AdminDashboard.lua"

local function read(path)
	local file = assert(io.open(path, "rb"))
	local value = assert(file:read("*a"))
	file:close()
	return value
end

local function executableSource(value)
	value = value:gsub("%-%-%[%[.-%]%]", "")
	local lines = {}
	for line in (value .. "\n"):gmatch("(.-)\n") do
		lines[#lines + 1] = line:gsub("%-%-.*$", "")
	end
	return table.concat(lines, "\n")
end

local source = read(SOURCE_PATH)
local code = executableSource(source)

assert(code:find('local UI = require "GS_UI_Framework"', 1, true),
	"Admin Dashboard must load the public SiK.UI framework facade")
assert(not code:find('require "ISUI/ISLabel"', 1, true), "Admin Dashboard must not require ISLabel")
assert(not code:find('require "ISUI/ISComboBox"', 1, true), "Admin Dashboard must not require ISComboBox")
assert(not code:match("ISLabel%s*[:.]"), "Admin Dashboard must not instantiate or mutate ISLabel")
assert(not code:match("ISComboBox%s*[:.]"), "Admin Dashboard must not instantiate or mutate ISComboBox")
assert(not code:match("function%s+GS_AdminDashboardUI:prerender"), "Admin Dashboard must not own manual chrome rendering")
assert(not code:match("function%s+GS_AdminDashboardUI:render"), "Admin Dashboard must not own manual row rendering")
assert(not code:match(":drawText"), "Admin Dashboard must not paint table headers or rows manually")
assert(not code:match(":drawRect"), "Admin Dashboard must not paint table headers or rows manually")

local requiredFrameworkCalls = {
	"UI.Window.derive", "UI.Window.callBase", "UI.Window.apply", "UI.Window.resolveBounds",
	"UI.Modal.apply", "UI.Modal.confirm",
	"UI.Controls.button", "UI.Controls.combo", "UI.Table.create", "UI.Scroll.create",
	"UI.Lifecycle.bindVisibleRefresh",
}
for i = 1, #requiredFrameworkCalls do
	assert(code:find(requiredFrameworkCalls[i], 1, true),
		"Admin Dashboard lost framework primitive " .. requiredFrameworkCalls[i])
end

local capturedTableOptions = nil
local tableCreateCount = 0
local tableLayoutCalls = {}
local scrollState = { contentHeight = nil, ensureCount = 0 }
local capturedWindowOptions = nil
local lifecycleBindOptions = nil

local tableInstance = {
	disposed = false,
	height = 244,
	layout = function(self, options)
		tableLayoutCalls[#tableLayoutCalls + 1] = options
		self.height = options.h
		return true
	end,
	getHeight = function(self) return self.height end,
	dispose = function(self) self.disposed = true; self.disposeCount = (self.disposeCount or 0) + 1 end,
}

local UI = {
	Controls = {
		metrics = function() return { buttonHeight = 28, inputHeight = 28 } end,
	},
	Table = {
		metrics = function() return { rowHeight = 28, headerHeight = 30 } end,
		create = function(options)
			tableCreateCount = tableCreateCount + 1
			capturedTableOptions = options
			return tableInstance
		end,
	},
	Scroll = {
		contentWidth = function(scroll) return scroll.contentWidth end,
		childHost = function(scroll) return scroll.childHost end,
		setContentHeight = function(_, height) scrollState.contentHeight = height end,
		ensureScrollBars = function() scrollState.ensureCount = scrollState.ensureCount + 1 end,
	},
	Window = {
		derive = function(name) return ISPanel:derive(name) end,
		callBase = function(panel, method, ...)
			return ISPanel[method](panel, ...)
		end,
		apply = function(_, options) capturedWindowOptions = options; return true end,
	},
	Modal = { STANDARD_MODAL_W = 460 },
	Lifecycle = {
		bindVisibleRefresh = function(_, options)
			lifecycleBindOptions = options
			return {
				disposeCount = 0,
				dispose = function(self) self.disposeCount = self.disposeCount + 1 end,
			}
		end,
	},
	Theme = {
		color = function(name)
			if name == "success" then return { r = 0.2, g = 0.8, b = 0.3 } end
			if name == "warning" then return { r = 0.9, g = 0.7, b = 0.2 } end
			return { r = 1, g = 1, b = 1 }
		end,
	},
	FocusStack = { PRIORITY = { STAFF = 40 } },
}

ISPanel = {}
function ISPanel:derive()
	local child = {}
	child.__index = child
	setmetatable(child, { __index = self })
	return child
end
function ISPanel.initialise() end
function ISPanel.onKeyRelease() return false end

UIFont = { Small = 1, Medium = 2 }
Keyboard = { KEY_ESCAPE = 1 }
function getTextManager()
	return {
		getFontHeight = function(_, font) return font == UIFont.Medium and 20 or 14 end,
		MeasureStringX = function(_, _, text) return #tostring(text) * 7 end,
	}
end

local function translated(key, ...)
	local values = { ... }
	for i = 1, #values do values[i] = tostring(values[i]) end
	return key .. (#values > 0 and (":" .. table.concat(values, ",")) or "")
end

GlobalStorageSiK = {
	I18n = { text = translated },
	NetClient = {},
	Permissions = {
		ROLE_DEAD = "dead",
		resolveMemberDisplayName = function(member) return member.displayName or member.name or "" end,
	},
	TerminalExtensions = {},
	AdminDashboardAudit = {},
	AdminDashboardCorpus = {},
}

package.preload["ISUI/ISPanel"] = function() return ISPanel end
package.preload["GS_I18n"] = function() return GlobalStorageSiK.I18n end
package.preload["GS_NetClient"] = function() return GlobalStorageSiK.NetClient end
package.preload["GS_Permissions"] = function() return GlobalStorageSiK.Permissions end
package.preload["GS_TerminalUI_Extensions"] = function() return GlobalStorageSiK.TerminalExtensions end
package.preload["GS_AdminDashboard_Audit"] = function() return GlobalStorageSiK.AdminDashboardAudit end
package.preload["GS_AdminDashboard_Corpus"] = function() return GlobalStorageSiK.AdminDashboardCorpus end
package.preload["GS_UI_Framework"] = function() return UI end
dofile("tests/helpers/gs_ui_feedback_stub.lua").install()

assert(dofile(SOURCE_PATH) == nil, "Admin Dashboard module did not load under neutral framework doubles")

local lifecycleHost = {
	x = 10, y = 20, width = 860, height = 780, playerNum = 2,
	setAlwaysOnTop = function(self, value) self.alwaysOnTop = value end,
	buildStaticFrame = function(self) self.buildCount = (self.buildCount or 0) + 1 end,
	requestNetworkList = function(self) self.networkRequests = (self.networkRequests or 0) + 1 end,
	requestOnlinePlayers = function(self) self.playerRequests = (self.playerRequests or 0) + 1 end,
	refreshRelativeAges = function(self) self.ageRefreshes = (self.ageRefreshes or 0) + 1 end,
}
GS_AdminDashboardUI.initialise(lifecycleHost)
assert(capturedWindowOptions and capturedWindowOptions.profile == "staff",
	"staff panel must be owned by SiK.UI.Window")
assert(lifecycleBindOptions and lifecycleBindOptions.intervalTicks == 15
	and type(lifecycleBindOptions.refresh) == "function",
	"visible relative-age refresh must be registered through SiK.UI.Lifecycle")
lifecycleBindOptions.refresh()
assert(lifecycleHost.ageRefreshes == 1, "visible refresh callback must target the active dashboard")

local refreshHandle = lifecycleHost._relativeAgeBinding
lifecycleHost.memberTableBlock = tableInstance
GlobalStorageSiK.AdminDashboard.instance = lifecycleHost
capturedWindowOptions.onClose()
assert(refreshHandle.disposeCount == 1 and lifecycleHost._relativeAgeBinding == nil,
	"window close must dispose and release the visible-refresh binding")
assert(tableInstance.disposeCount == 1 and lifecycleHost.memberTableBlock == nil,
	"window close must dispose and release the member table")
assert(GlobalStorageSiK.AdminDashboard.instance == nil, "window close must clear the singleton")

tableInstance.disposed = false
tableInstance.disposeCount = 0
local hostWidget = { id = "member-scroll-host" }
local memberHost = {
	memberScroll = { height = 210, contentWidth = 640, childHost = hostWidget },
	refreshOnlinePlayersCombo = function(self) self.comboRefreshes = (self.comboRefreshes or 0) + 1 end,
}
local members = {
	{ id = "owner-1", role = "owner", displayName = "Kava", username = "admin", online = true },
	{ id = "member-2", role = "member", displayName = "Rook", username = "rook", online = false },
}
GS_AdminDashboardUI.refreshMemberPanel(memberHost, members)
assert(tableCreateCount == 1 and capturedTableOptions.parent == hostWidget,
	"member panel must create one SiK.UI.Table inside the SiK.UI.Scroll host")
assert(#capturedTableOptions.columns == 2, "member table must expose semantic member and connection columns only")
assert(capturedTableOptions.columns[1].key == "member"
	and capturedTableOptions.columns[2].key == "connection"
	and capturedTableOptions.columns[2].align == "right",
	"member table semantic columns or right-aligned connection contract changed")
assert(capturedTableOptions.left == 0 and capturedTableOptions.right == 0,
	"member table must not duplicate the Scroll gutter")
assert(tableLayoutCalls[1].rows == members and tableLayoutCalls[1].preserveOffset == true,
	"member refresh must update table data while preserving viewport state")
assert(scrollState.contentHeight == tableInstance:getHeight() and scrollState.ensureCount == 1,
	"member refresh must publish table height and let Scroll resolve overflow")

local memberCell = capturedTableOptions.columns[1].value(members[1])
local connectionCell = capturedTableOptions.columns[2].value(members[1])
assert(type(memberCell) == "table" and memberCell.text:find("Kava %(admin%)"),
	"member column must compose role, character and account semantically")
assert(type(connectionCell) == "table" and connectionCell.text:find("IGUI_GS_AdminOnline", 1, true),
	"connection column must expose semantic online state")

local openedMember = nil
GlobalStorageSiK.AdminDashboard.openMemberEditor = function(dashboard, member)
	assert(dashboard == memberHost, "row action lost its dashboard owner")
	openedMember = member
end
assert(capturedTableOptions.onRowClick({ item = members[2] }) == true and openedMember == members[2],
	"member row must open its semantic editor without a local action column")

local replacement = { members[2] }
GS_AdminDashboardUI.refreshMemberPanel(memberHost, replacement)
assert(tableCreateCount == 1, "visible member refresh must reuse, not reconstruct, the table")
assert(tableLayoutCalls[2].rows == replacement and tableLayoutCalls[2].preserveOffset == true,
	"reused member table must receive the new semantic rows and preserve offset")
assert(scrollState.ensureCount == 2, "each visible refresh must recompute Scroll overflow exactly once")

print("admin_dashboard_framework_contract: OK")
