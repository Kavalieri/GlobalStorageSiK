local API = require "GSSiK_API_Client"
local Client = require "GSSiK_Addon_Multimedia_Client"
require "SiK_UI"
local UI, T = SiK.UI, Client.text
local Module = {}

local function visible(panel)
	while panel do
		if panel.isVisible and not panel:isVisible() then return false end
		panel = panel.parent
	end
	return true
end

-- The terminal owns the lifecycle; its installed peripheral owns the native
-- receiver. The table uses the same geometry and selection chrome as storage.
function Module.mount(parent, _, options)
	local session = options.context.session
	local playerNum = session.player:getPlayerNum()
	local block = UI.Block.create({ parent = parent, w = parent.width, h = parent.height,
		title = T("Title"), tooltip = T("CatalogHelp"), scrollable = true, playerNum = playerNum })
	local scroll = UI.Scroll.create({ parent = block.panel, viewportRect = block:getContentRect(), playerNum = playerNum })
	block:attachScroll(scroll, true)
	local host = { block = block, generation = -1, disposed = false }
	local metrics, gap = UI.Controls.metrics(), block.metrics.spacing.sm
	local function button(key, action)
		return UI.Controls.button(scroll.host, { text = T(key), playerNum = playerNum,
			onClick = function() action(); host:refresh() end })
	end
	host.refreshButton = button("Refresh", function() Client.catalog(session, true) end)
	host.nextButton = button("NextPage", function() host.table:nextPage(); host:layout() end)
	host.previousButton = button("PreviousPage", function() host.table:previousPage(); host:layout() end)
	host.playButton = button("Play", function()
		if host.radio then Client.control(session, "power", true) else Client.play(session, false) end
	end)
	host.allButton = button("All", function() Client.play(session, true) end)
	host.stopButton = button("Stop", function() Client.stop(session) end)
	host.recoverButton = button("Recover", function() Client.recover(session) end)
	local function volume(delta)
		Client.control(session, "volume", math.max(0, math.min(1, ((session.deviceState or {}).volume or 0.3) + delta)))
	end
	host.volumeDown = button("VolumeDown", function() volume(-0.1) end)
	host.volumeLabel = button("Volume", function() end); host.volumeLabel:setEnabled(false)
	host.volumeUp = button("VolumeUp", function() volume(0.1) end)
	host.source = UI.Controls.combo(scroll.host, { playerNum = playerNum,
		items = { { text = T("VHS"), value = "vhs" }, { text = T("Radio"), value = "radio" } }, selected = 1,
		onChange = function(context)
			if context.value then Client.control(session, "mode", context.value.value); host:refresh() end
		end })
	host.status = UI.Controls.status(scroll.host, { text = T("Ready"), wrap = true, playerNum = playerNum })
	host.scope = UI.Controls.status(scroll.host, { text = "", wrap = true, playerNum = playerNum })
	host.search = UI.Controls.field(scroll.host, { text = session.query, placeholder = T("Search"),
		maxLength = 128, playerNum = playerNum,
		onChange = function(context) Client.filter(session, context.value); host:refresh() end })
	host.skill = UI.Controls.combo(scroll.host, { playerNum = playerNum,
		items = { { text = T("AllSkills"), value = "" } }, selected = 1,
		onChange = function(context)
			if context.value then Client.filter(session, nil, context.value.value); host:refresh() end
		end })
	host.sort = UI.Controls.combo(scroll.host, { playerNum = playerNum,
		items = { { text = T("SortTitle"), value = "title" }, { text = T("SortSkill"), value = "skill" } }, selected = 1,
		onChange = function(context)
			if context.value then Client.filter(session, nil, nil, context.value.value); host:refresh() end
		end })
	host.frequency = UI.Controls.field(scroll.host, { text = "98.4", placeholder = T("Frequency"),
		maxLength = 8, playerNum = playerNum })
	host.tune = button("Tune", function()
		local value = tonumber((host.frequency:getText():gsub(",", ".")))
		if value then Client.control(session, "channel", math.floor(value * 1000 + 0.5)) end
	end)
	host.inventory = API.InventoryView.create(scroll.host, {
		terminal = session.terminal,
		onChanged = function() Client.inventoryChanged(session) end,
		onSelectionChanged = function(rows) Client.select(session, rows); host:refresh() end,
		onLayoutChanged = function() host:layout() end,
		acceptItem = function(item)
			local script = item and item.getScriptItem and item:getScriptItem()
			local category = script and script:getRecordedMediaCat()
			return category == "Retail-VHS" or category == "Home-VHS"
		end,
	})
	local rowAdapter = host.inventory.row
	local describeRow = rowAdapter.describe
	rowAdapter.describe = function(context)
		local descriptor = describeRow(context)
		local title, learned, meta = Client.describe(session, context.item.reference)
		descriptor.cells = {
			title = { text = title }, skill = { text = meta.skillText },
			state = { text = learned and T("Learned") or T("Available") },
			count = { text = tostring(context.item.count) },
		}
		return descriptor
	end
	host.table = UI.Table.create({ parent = scroll.host, embedded = true, directBlock = false,
		w = block:getContentRect().w, h = 1, playerNum = playerNum,
		pagination = { pageSize = 15 }, selectionMode = "multiple",
		keyOf = function(row) return row.rowKey end,
		expansion = { childrenOf = function(row) return row._sikChildren or {} end,
			hasChildren = function(row) return row.expandable == true end,
			keyOf = function(row) return row.rowKey end },
		onExpansionChange = function(context)
			host.inventory:expand(context.key, context.expanded)
			host:layout()
		end,
		columns = {
			{ key = "title", title = T("TapeTitle"), flex = 1.5, minWidth = 220 },
			{ key = "skill", title = T("Skill"), flex = 1, minWidth = 150 },
			{ key = "state", title = T("State"), width = 110, align = "right" },
			{ key = "count", title = T("Count"), width = 70, align = "right" },
		},
		row = rowAdapter,
	})
	host.inventory:setTable(host.table)
	local function place(widget, x, y, w, h)
		UI.Layout.apply(widget, { x = x, y = y, w = math.max(1, w), h = h or widget.height })
	end
	local function buttonRow(buttons, width, y)
		local maximum = 0
		for i = 1, #buttons do maximum = math.max(maximum,
			UI.Controls.measureButtonWidth(buttons[i].title or buttons[i].text, UIFont.Small)) end
		local columns = math.max(1, math.min(#buttons, math.floor((width + gap) / (maximum + gap))))
		local w = (width - gap * (columns - 1)) / columns
		for i = 1, #buttons do
			place(buttons[i], ((i - 1) % columns) * (w + gap), y + math.floor((i - 1) / columns) * (metrics.buttonHeight + gap), w, metrics.buttonHeight)
		end
		return y + math.ceil(#buttons / columns) * (metrics.buttonHeight + gap)
	end
	function host:layout()
		for pass = 1, 2 do
			local width = block:getContentRect().w
			local page = self.table:getPageState()
			local showPager = not self.radio and page and page.pageCount > 1
			self.previousButton:setVisible(showPager == true)
			self.nextButton:setVisible(showPager == true)
			local y = buttonRow(showPager and { self.refreshButton, self.previousButton, self.nextButton }
				or { self.refreshButton }, width, 0)
			place(self.source, 0, y, width, metrics.inputHeight); y = y + metrics.inputHeight + gap
			self.status:reflow(width); place(self.status, 0, y, width); y = y + self.status.height + gap
			y = buttonRow({ self.playButton, self.allButton, self.stopButton, self.recoverButton }, width, y)
			y = buttonRow({ self.volumeDown, self.volumeLabel, self.volumeUp }, width, y)
			self.search:setVisible(not self.radio); self.skill:setVisible(not self.radio); self.sort:setVisible(not self.radio)
			self.table.panel:setVisible(not self.radio); self.scope:setVisible(not self.radio)
			self.frequency:setVisible(self.radio == true); self.tune:setVisible(self.radio == true)
			if self.radio then
				local tuneWidth = math.min(width, UI.Controls.measureButtonWidth(T("Tune"), UIFont.Small))
				local stacked = width < tuneWidth + 180 + gap
				place(self.frequency, 0, y, stacked and width or width - tuneWidth - gap, metrics.inputHeight)
				if stacked then y = y + metrics.inputHeight + gap end
				place(self.tune, stacked and 0 or width - tuneWidth, y, stacked and width or tuneWidth, metrics.buttonHeight)
				y = y + math.max(metrics.inputHeight, metrics.buttonHeight) + gap
			else
				place(self.search, 0, y, width, metrics.inputHeight); y = y + metrics.inputHeight + gap
				local stacked, half = width < 520, (width - gap) / 2
				place(self.skill, 0, y, stacked and width or half, metrics.inputHeight)
				if stacked then y = y + metrics.inputHeight + gap end
				place(self.sort, stacked and 0 or half + gap, y, stacked and width or half, metrics.inputHeight)
				y = y + metrics.inputHeight + gap
				self.scope:reflow(width)
				local available = math.max(self.table:getRequiredHeight(3),
					block:getContentRect().h - y - self.scope.height - gap)
				self.table:setBounds(0, y, width, math.min(self.table:getIntrinsicHeight(), available))
				y = y + self.table:getHeight() + gap
				self.scope:reflow(width); place(self.scope, 0, y, width); y = y + self.scope.height + gap
			end
			block:setContentHeight(math.max(0, y - gap))
			if block:getContentRect().w == width then break end
		end
		local page = self.table:getPageState()
		self.nextButton:setEnabled(not self.radio and page and page.hasNext == true)
		self.previousButton:setEnabled(not self.radio and page and page.hasPrevious == true)
	end
	function host:refresh()
		if self.disposed then return end
		if self.inventory:isInteracting() then return end
		local state, device = session.status or {}, session.deviceState or {}
		local active = state.state and state.state ~= "settled"
		local busy = session.upload ~= nil or (session.pending ~= nil and session.command ~= "state")
		self.radio = device.mode == "radio"
		if self.mode ~= device.mode then
			self.mode = device.mode
			self.source:setItems({ { text = T("VHS"), value = "vhs" }, { text = T("Radio"), value = "radio" } }, self.radio and 2 or 1)
		end
		local key, tone = "Ready", "textMuted"
		if session.loading then key = "Loading"
		elseif busy then key = "Pending"
		elseif state.ok == false then key, tone = "Failed", "warning"
		elseif state.state == "active" or device.powered then key, tone = "Active", "success"
		elseif active then key, tone = "Recovery", "warning" end
		self.status:setStatus(key == "Failed" and T(key, tostring(state.reason or "unknown")) or T(key), tone)
		self.refreshButton:setEnabled(not busy and not session.loading)
		self.source:setEnabled(not busy)
		self.volumeDown:setEnabled(not busy); self.volumeUp:setEnabled(not busy); self.tune:setEnabled(not busy)
		self.volumeLabel:setText(T("Volume") .. " " .. tostring(math.floor((device.volume or 0.3) * 100 + 0.5)) .. "%")
		self.playButton:setEnabled(not busy and not active and not device.mediaPending and (self.radio or (session.complete and session.nextSequence ~= nil and #session.filtered > 0)))
		self.allButton:setEnabled(not self.radio and not busy and not active and not device.mediaPending and session.complete and session.nextSequence ~= nil and #session.rows > 0)
		self.stopButton:setEnabled(active == true or device.powered == true or session.upload ~= nil)
		self.recoverButton:setEnabled((active == true or device.mediaPending == true) and not busy)
		if self.filtered ~= session.filtered and session.complete and not session.loading then
			local accepted = self.inventory:setGroups(Client.groups(session), session.catalogRevision)
			if accepted then
				self.filtered = session.filtered
				self.inventory:selectItems(session.selected)
				self.table:setRows(self.inventory.roots, true)
				Client.select(session, self.inventory:selectedItems())
			end
		end
		self.inventory:setEnabled(not self.radio and session.complete and not session.catalogDirty and not session.loading)
		if self.selected ~= session.selected or self.generation ~= session.generation then
			self.selected = session.selected
			local keys = {}; for keyValue in pairs(session.selected) do keys[#keys + 1] = keyValue end
			self.table:setSelectedKeys(self.inventory:selectionKeys())
			self.scope:setStatus(#session.filtered == 0 and T("Empty") or T("Scope", #session.filtered, #keys, #keys > 0 and #keys or #session.filtered), "textMuted")
		end
		if self.rowCount ~= #session.rows then
			self.rowCount = #session.rows
			local skills, seen = {}, {}
			for _, meta in pairs(session.metadata) do
				for i = 1, #meta.skills do
					local skill = meta.skills[i]
					if not seen[skill.code] then seen[skill.code] = true; skills[#skills + 1] = { text = skill.label, value = skill.code } end
				end
			end
			table.sort(skills, function(a, b) return a.text < b.text end)
			local items, selected = { { text = T("AllSkills"), value = "" } }, 1
			for i = 1, #skills do items[#items + 1] = skills[i]; if skills[i].value == session.skill then selected = #items end end
			self.skill:setItems(items, selected)
		end
		self.generation = session.generation; self:layout()
	end
	function host:reflow(bounds)
		if self.disposed then return end
		block:reflow(bounds); self:layout(); return true
	end
	function host:dispose()
		if self.disposed then return end
		self.disposed = true
		self.inventory:dispose()
		self.table:dispose()
		Client.release(session); parent.update = self.previousUpdate; block:dispose()
	end
	host.previousUpdate = parent.update
	parent.update = function(panel)
		if host.previousUpdate then host.previousUpdate(panel) end
		if host.disposed then return end
		if not visible(panel) then
			if not host.hidden then host.inventory:hide(); host.hidden = true end
			return
		end
		host.hidden = false
		if not host.opened then host.opened = true; Client.catalog(session) end
		local revision = (API.Terminal.state(session.terminal) or {}).inventoryRevision
		if host.observedRevision ~= revision then
			if host.observedRevision ~= nil and type(revision) == "number"
				and revision > (session.catalogRevision or -1) then Client.inventoryChanged(session) end
			host.observedRevision = revision
		end
		if host.inventory:isInteracting() then return end
		Client.update(session)
		if host.generation ~= session.generation then host:refresh() end
	end
	host:refresh()
	return host
end

API.Terminal.registerTab({ key = "multimedia", titleKey = "IGUI_GSSiK_Multimedia_Title",
	iconPath = "media/ui/GSSiK_Addon_Multimedia/sik-rail-multimedia.png",
	surface = { surface = { id = "tab-multimedia", kind = "embedded" } }, builder = Module.mount,
	contextFactory = function(terminal)
		local session = Client.session(terminal)
		return session and { session = session } or nil
	end,
	isVisible = function(terminal) return API.Terminal.isAddonInstalled(terminal, "Multimedia") end, order = 60,
})
API.ItemActions.registerProvider({ id = "multimedia.item-actions", addonId = "Multimedia",
	capabilities = { "media" }, actions = { { id = "open", labelKey = "IGUI_GSSiK_Multimedia_Open" } },
	appliesTo = function(context)
		local terminal = context.extra and context.extra.terminal
		if not terminal or not API.Terminal.isAddonInstalled(terminal, "Multimedia") then return false end
		for i = 1, #(context.items or {}) do
			local row = context.items[i]
			if type(row) == "table" and tonumber(row.mediaIndex) and tonumber(row.mediaIndex) >= 0 then return true end
		end
		return false
	end,
	buildRequest = function(_, context) return { terminal = context.extra.terminal } end,
	executeRequest = function(request) return API.Terminal.activate(request.terminal, "multimedia") end,
})
return Module
