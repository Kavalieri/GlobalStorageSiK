--[[
	GSSiK Addon Tablet - selector remoto de red
	El addon posee la presentacion; Core conserva descubrimiento y autoridad.
]]

require "GSSiK_Addon_Tablet_Access"
local ProductAPI = require "GSSiK_API_Client"
local UI = require "SiK_UI"

GSSiK_Addon_Tablet = GSSiK_Addon_Tablet or {}
GSSiK_Addon_Tablet.NetworkSelector = GSSiK_Addon_Tablet.NetworkSelector or {}

local Selector = GSSiK_Addon_Tablet.NetworkSelector
Selector.instances = Selector.instances or {}
local RemoteAccess = ProductAPI.RemoteAccess
local Modal = UI.Modal
local Controls = UI.Controls
local Block = UI.Block
local Card = UI.Card
local Scroll = UI.Scroll
local REQUEST_TIMEOUT_MS = 12000

local STATE_COPY = {
	loading = {
		titleKey = "IGUI_GSSiK_RemoteLoadingTitle",
		helpKey = "IGUI_GSSiK_RemoteLoadingHelp",
		feedbackKey = "IGUI_GSSiK_RemoteLoading",
		feedbackKind = "info",
	},
	empty = {
		titleKey = "IGUI_GSSiK_RemoteEmptyTitle",
		helpKey = "IGUI_GSSiK_RemoteEmptyHelp",
		feedbackKey = "IGUI_GSSiK_RemoteEmpty",
		feedbackKind = "warning",
	},
	outdated = {
		titleKey = "IGUI_GSSiK_RemoteOutdatedTitle",
		helpKey = "IGUI_GSSiK_RemoteOutdatedHelp",
		feedbackKey = "IGUI_GSSiK_RemoteOutdated",
		feedbackKind = "warning",
	},
	error = {
		titleKey = "IGUI_GSSiK_RemoteErrorTitle",
		helpKey = "IGUI_GSSiK_RemoteErrorHelp",
		feedbackKey = "IGUI_GSSiK_RemoteError",
		feedbackKind = "danger",
	},
}

local function T(key, ...)
	if getText then return getText(key, ...) end
	return key
end

local function resolvePlayer(playerArg)
	if type(playerArg) == "number" and getSpecificPlayer then
		return getSpecificPlayer(math.max(0, math.floor(playerArg)))
	end
	if playerArg and playerArg.getPlayerNum then return playerArg end
	if getSpecificPlayer then return getSpecificPlayer(0) end
	return nil
end

local function rounded(value)
	value = tonumber(value)
	if not value then return nil end
	return math.floor(value + 0.5)
end

local function antennaTier(wirelessRange)
	local range = tonumber(wirelessRange) or 0
	local sandbox = GSSiK_Addon_Tablet.Sandbox
	if not sandbox or range <= 0 then return nil end
	local t3 = tonumber(sandbox.getTier3Range and sandbox.getTier3Range()) or -1
	local t2 = tonumber(sandbox.getTier2Range and sandbox.getTier2Range()) or -1
	if t3 > 0 and range >= t3 then return 3 end
	if t2 > 0 and range >= t2 then return 2 end
	return 1
end

local function providerLabel(candidate)
	local tier = antennaTier(candidate.wirelessRange)
	if tier then return T("IGUI_GSSiK_RemoteAntennaTier", tier) end
	if candidate.providerId and candidate.providerId ~= "" then
		return tostring(candidate.providerId)
	end
	return T("IGUI_GSSiK_RemoteNoAntenna")
end

local function reasonLabel(reason)
	local keys = {
		antenna_out_of_range = "IGUI_GSSiK_RemoteOutOfRange",
		tablet_out_of_range = "IGUI_GSSiK_RemoteOutOfRange",
		wireless_provider_unavailable = "IGUI_GSSiK_RemoteUnavailable",
		no_terminal = "IGUI_GSSiK_RemoteNoTerminal",
		no_permission = "IGUI_GSSiK_RemoteNoPermission",
	}
	return T(keys[reason] or "IGUI_GSSiK_RemoteUnavailable")
end

local function candidateLabel(candidate)
	local name = candidate.label or candidate.name
	if type(name) ~= "string" or name == "" then
		name = T("IGUI_GSSiK_RemoteUnnamedNetwork")
	end
	local available = candidate.selectable ~= false
	local distance = rounded(candidate.distance)
	local range = rounded(candidate.wirelessRange)
	local status = available and T("IGUI_GSSiK_RemoteAvailable")
		or reasonLabel(candidate.reason)
	if distance and range and range > 0 then
		return T("IGUI_GSSiK_RemoteNetworkRow", name, providerLabel(candidate),
			distance, range, status)
	end
	return T("IGUI_GSSiK_RemoteNetworkRowShort", name, providerLabel(candidate), status)
end

local function setButtonEnabled(button, enabled)
	if not button then return end
	if button.setEnable then button:setEnable(enabled == true)
	else button.enable = enabled == true end
end

local function controlMetrics()
	local source = Controls.metrics("standard") or {}
	return {
		buttonHeight = tonumber(source.buttonHeight) or 34,
		sectionHeight = tonumber(source.sectionHeight) or tonumber(source.buttonHeight) or 34,
		statusHeight = tonumber(source.statusHeight) or tonumber(source.buttonHeight) or 34,
		rowGap = tonumber(source.rowGap) or 8,
		controlGap = tonumber(source.controlGap) or 8,
	}
end

local function nowMs()
	return getTimestampMs and tonumber(getTimestampMs()) or 0
end

local function trackStateWidget(panel, widget)
	if widget then
		panel._stateWidgets[#panel._stateWidgets + 1] = widget
	end
	return widget
end

local disposeRows

local function removeStateWidgets(panel)
	disposeRows(panel)
	if panel.listBlock then panel.listBlock:dispose() end
	panel.listBlock = nil
	panel.listScroll = nil
	for i = #panel._stateWidgets, 1, -1 do
		local widget = panel._stateWidgets[i]
		if widget and widget.dispose then widget:dispose() end
	end
	panel._stateWidgets = {}
	panel.stateCard = nil
	panel.feedback = nil
	panel.cancelButton = nil
	panel.openButton = nil
end

local function findSelectable(panel, networkId)
	for i = 1, #panel.networks do
		local candidate = panel.networks[i]
		if candidate.networkId == networkId and candidate.selectable ~= false then
			return candidate
		end
	end
	return nil
end

disposeRows = function(panel)
	local rows = panel.optionRows or {}
	for index = #rows, 1, -1 do
		if rows[index] and rows[index].dispose then rows[index]:dispose() end
	end
	panel.optionRows = {}
end

local function layoutRows(panel)
	if not panel.listBlock or not panel.listScroll then return 0 end
	local rect = panel.listBlock:getContentRect()
	local y = 0
	for index = 1, #panel.optionRows do
		local row = panel.optionRows[index]
		row:setX(0)
		row:setY(y)
		row:reflow(rect.w)
		y = y + row.height + 8
	end
	local height = math.max(0, y - 8)
	if panel.listBlock.contentHeight ~= height then
		panel.listBlock:setContentHeight(height)
		return layoutRows(panel)
	end
	return height
end

local function refreshRows(panel)
	disposeRows(panel)
	if not panel.listScroll then return end
	for index = 1, #panel.networks do
		local candidate = panel.networks[index]
		local row = Controls.listOption(panel.listScroll.host, {
			x = 0, y = 0, w = panel.listBlock:getContentRect().w,
			text = candidateLabel(candidate),
			payload = candidate,
			selected = candidate.networkId == panel.selectedNetworkId,
			enabled = candidate.selectable ~= false,
			onClick = function(context)
				local selected = context and context.payload
				if selected then panel:selectNetwork(selected.networkId) end
			end,
		})
		panel.optionRows[#panel.optionRows + 1] = row
	end
	layoutRows(panel)
end

local function feedbackFor(panel)
	local copy = STATE_COPY[panel.state]
	if copy then
		return T(copy.feedbackKey), copy.feedbackKind
	elseif panel.state == "available" and panel.selectedNetworkId then
		local selected
		for i = 1, #panel.networks do
			if panel.networks[i].networkId == panel.selectedNetworkId then
				selected = panel.networks[i]
				break
			end
		end
		if selected then
			return T("IGUI_GSSiK_RemoteSelected", selected.label or selected.name,
			providerLabel(selected)), "success"
		end
	end
	return T("IGUI_GSSiK_RemoteChoose"), "info"
end

local function onCancelAction(panel)
	Selector.close(panel)
end

local function onPrimaryAction(panel)
	if panel.state == "available" then
		panel:confirmSelection()
	else
		panel:beginRequest()
	end
end

local function actionLabels(state)
	if state == "empty" then
		return T("IGUI_GSSiK_RemoteClose"), T("IGUI_GSSiK_RemoteSearchAgain")
	elseif state == "outdated" then
		return T("IGUI_GSSiK_RemoteCancel"), T("IGUI_GSSiK_RemoteRefresh")
	elseif state == "error" then
		return T("IGUI_GSSiK_RemoteCancel"), T("IGUI_GSSiK_RemoteRetry")
	end
	return T("IGUI_GSSiK_RemoteCancel"), T("IGUI_GSSiK_RemoteOpen")
end

local function createActions(panel, y)
	local content = panel._stateContent
	local metrics = controlMetrics()
	if panel.state == "loading" then
		panel.cancelButton = trackStateWidget(panel, Controls.button(panel._stateBody, {
			x = content.x, y = y, w = content.w,
			text = T("IGUI_GSSiK_RemoteCancel"), fullWidth = true,
			onClick = function() onCancelAction(panel) end,
		}))
		return y + metrics.buttonHeight
	end
	local leftText, rightText = actionLabels(panel.state)
	local half = math.floor((content.w - metrics.controlGap) / 2)
	panel.cancelButton = trackStateWidget(panel, Controls.button(panel._stateBody, {
		x = content.x, y = y, w = half, text = leftText, fullWidth = true,
		onClick = function() onCancelAction(panel) end,
	}))
	panel.openButton = trackStateWidget(panel, Controls.button(panel._stateBody, {
		x = content.x + half + metrics.controlGap, y = y, w = half,
		text = rightText, fullWidth = true,
		onClick = function() onPrimaryAction(panel) end,
	}))
	setButtonEnabled(panel.openButton, panel.state ~= "available"
		or (panel.selectedNetworkId ~= nil and panel.openRequestHandle == nil))
	return y + metrics.buttonHeight
end

local function createHeader(parent, x, y, width, titleKey, helpKey)
	return Controls.blockHeader(parent, {
		x = x, y = y, w = width,
		text = T(titleKey), tooltip = T(helpKey),
	})
end

local function fitStateContent(panel, bottom)
	local body = panel._stateBody
	if body and body.setHeight then body:setHeight(bottom) end
	if Modal.fitContent and body then
		Modal.fitContent(panel, (body.y or 0) + bottom, {
			kind = "compact", playerNum = panel.playerNum,
		})
	end
end

function Selector.renderState(panel)
	if not panel._stateBody or not panel._stateContent then return end
	removeStateWidgets(panel)
	local content = panel._stateContent
	local metrics = controlMetrics()
	local pad = 8
	local y = content.y

	if panel.state == "available" then
		local blockH = pad * 2 + metrics.sectionHeight + metrics.rowGap + 176
		panel.stateCard = trackStateWidget(panel, Card.create({
			parent = panel._stateBody, x = content.x, y = y,
			w = content.w, h = blockH, scrollable = false,
		}))
		local host = panel.stateCard.content
		local rect = { x = 0, y = 0, w = host.width, h = host.height }
		local header = createHeader(host, rect.x, rect.y, rect.w,
			"IGUI_GSSiK_RemoteNetworksTitle", "IGUI_GSSiK_RemoteNetworksHelp")
		local listY = rect.y + (header.height or metrics.sectionHeight) + metrics.rowGap
		trackStateWidget(panel, header)
		panel.listBlock = Block.create({ parent = host, x = rect.x, y = listY,
			w = rect.w, h = 176, contentHeight = 0,
			metrics = { block = { padding = 0 } },
		})
		panel.listScroll = Scroll.create({ parent = panel.listBlock.panel,
			viewportRect = panel.listBlock:getContentRect(),
			trackRect = panel.listBlock:getTrackRect(), contentHeight = 0,
			playerNum = panel.playerNum,
		})
		panel.listBlock:attachScroll(panel.listScroll, true)
		panel.listBlock:subscribe(function() layoutRows(panel) end)
		refreshRows(panel)
		y = y + blockH + metrics.rowGap
		local feedbackText, feedbackKind = feedbackFor(panel)
		panel.feedback = trackStateWidget(panel, Controls.feedback(panel._stateBody, {
			x = content.x, y = y, w = content.w,
			text = feedbackText, tone = feedbackKind,
		}))
		y = y + metrics.statusHeight + 8 + metrics.rowGap
	else
		local copy = STATE_COPY[panel.state] or STATE_COPY.error
		local feedbackH = metrics.statusHeight + 8
		local blockH = pad * 2 + metrics.sectionHeight + metrics.rowGap + feedbackH
		panel.stateCard = trackStateWidget(panel, Card.create({
			parent = panel._stateBody, x = content.x, y = y,
			w = content.w, h = blockH, scrollable = false,
		}))
		local host = panel.stateCard.content
		local rect = { x = 0, y = 0, w = host.width, h = host.height }
		local header = trackStateWidget(panel,
			createHeader(host, rect.x, rect.y, rect.w, copy.titleKey, copy.helpKey))
		local feedbackY = rect.y + (header.height or metrics.sectionHeight) + metrics.rowGap
		panel.feedback = trackStateWidget(panel, Controls.feedback(host, {
			x = rect.x, y = feedbackY, w = rect.w,
			text = T(copy.feedbackKey), tone = copy.feedbackKind,
		}))
		y = y + blockH + metrics.rowGap
	end

	y = createActions(panel, y)
	fitStateContent(panel, y + content.y)
end

function Selector.setState(panel, state)
	panel.state = STATE_COPY[state] and state or (state == "available" and state or "error")
	if panel.state ~= "available" then panel.selectedNetworkId = nil end
	Selector.renderState(panel)
	return panel.state
end

function Selector.selectNetwork(panel, networkId)
	if panel.closed or panel.openRequestHandle or type(networkId) ~= "string" then return false end
	local found = findSelectable(panel, networkId)
	if not found then return false end
	panel.selectedNetworkId = found.networkId
	Selector.setState(panel, "available")
	return true
end

local function cleanupSelector(panel)
	if not panel or panel.closed then return false end
	panel.closed = true
	if panel.requestHandle then
		panel.requestHandle:dispose()
		panel.requestHandle = nil
	end
	if panel.openRequestHandle then
		panel.openRequestHandle:dispose()
		panel.openRequestHandle = nil
	end
	panel.requestDeadlineMs = nil
	panel.openRequestDeadlineMs = nil
	if Selector.instances[panel.playerNum or 0] == panel then
		Selector.instances[panel.playerNum or 0] = nil
	end
	if Selector.instance == panel then Selector.instance = nil end
	removeStateWidgets(panel)
	return true
end

function Selector.close(panel)
	if not panel or panel.closed then return false end
	return Modal.close(panel, "selector")
end

function Selector.confirmSelection(panel)
	if panel.closed or panel.openRequestHandle or not panel.selectedNetworkId then return false end
	local selected = panel.selectedNetworkId
	if not findSelectable(panel, selected) then return false end
	local completed = false
	local ok, code, handle = RemoteAccess.open(selected, panel.player,
		function(accepted, reason, payload)
			completed = true
			if panel.closed then return end
			panel.openRequestHandle = nil
			panel.openRequestDeadlineMs = nil
			if accepted == true then
				panel:close()
				return
			end
			panel.selectedNetworkId = nil
			Selector.setState(panel, accepted == false and "outdated" or "error")
		end)
	if ok and handle then
		if not completed and not panel.closed then
			panel.openRequestHandle = handle
			panel.openRequestDeadlineMs = nowMs() + REQUEST_TIMEOUT_MS
			setButtonEnabled(panel.openButton, false)
		end
		return true
	end
	if not completed and not panel.closed then
		panel.selectedNetworkId = nil
		Selector.setState(panel, "error")
	end
	return false
end

function Selector.beginRequest(panel)
	if panel.closed then return false end
	if panel.openRequestHandle then
		panel.openRequestHandle:dispose()
		panel.openRequestHandle = nil
		panel.openRequestDeadlineMs = nil
	end
	if panel.requestHandle then
		panel.requestHandle:dispose()
		panel.requestHandle = nil
	end
	panel.networks = {}
	panel.selectedNetworkId = nil
	panel.requestDeadlineMs = nowMs() + REQUEST_TIMEOUT_MS
	Selector.setState(panel, "loading")
	local completed = false
	local ok, code, handle = RemoteAccess.list(panel.player, function(accepted, reason, networks)
		completed = true
		if panel.closed then return end
		panel.requestHandle = nil
		panel.requestDeadlineMs = nil
		if accepted ~= true then
			Selector.setState(panel, reason == "outdated" and "outdated" or "error")
			return
		end
		local seen = {}
		for i = 1, #(networks or {}) do
			local candidate = networks[i]
			local id = candidate and candidate.networkId
			if type(id) == "string" and id ~= "" and #id <= 128 and not seen[id] then
				seen[id] = true
				candidate.selectable = candidate.selectable ~= false
				panel.networks[#panel.networks + 1] = candidate
				if not panel.selectedNetworkId and candidate.selectable then
					panel.selectedNetworkId = id
				end
			end
		end
		Selector.setState(panel, #panel.networks > 0 and "available" or "empty")
	end)
	if ok and handle and not completed and not panel.closed then
		panel.requestHandle = handle
		return true
	end
	if not completed then
		panel.requestDeadlineMs = nil
		Selector.setState(panel, "error")
	end
	return ok == true
end

function Selector.update(panel)
	if panel.closed or not getTimestampMs then return end
	local now = nowMs()
	if panel.openRequestHandle and panel.openRequestDeadlineMs
		and now >= panel.openRequestDeadlineMs then
		panel.openRequestHandle:dispose()
		panel.openRequestHandle = nil
		panel.openRequestDeadlineMs = nil
		panel.selectedNetworkId = nil
		Selector.setState(panel, "error")
		return
	end
	if panel.state == "loading" and panel.requestDeadlineMs
		and now >= panel.requestDeadlineMs then
		if panel.requestHandle then
			panel.requestHandle:dispose()
			panel.requestHandle = nil
		end
		panel.requestDeadlineMs = nil
		Selector.setState(panel, "error")
	end
end

function Selector.panelUpdate(panel)
	if panel._selectorBaseUpdate then panel._selectorBaseUpdate(panel) end
	Selector.update(panel)
end

function Selector.closeForPlayer(playerNum)
	local key = math.max(0, math.floor(tonumber(playerNum) or 0))
	local panel = Selector.instances[key]
	if panel then panel:close() end
end

function Selector.closeAll()
	local keys = {}
	for playerNum, _ in pairs(Selector.instances) do keys[#keys + 1] = playerNum end
	for i = 1, #keys do Selector.closeForPlayer(keys[i]) end
end

function Selector.ensureTransientCleanup()
	if Selector._cleanupRegistered then return true end
	local ok, code, registration = RemoteAccess.registerCleanup("TabletNetworkSelector", function(playerNum)
		if playerNum == nil then Selector.closeAll()
		else Selector.closeForPlayer(playerNum) end
	end)
	if not ok then return false end
	Selector._cleanupRegistration = registration
	Selector._cleanupRegistered = true
	return registration ~= nil
end

local function buildContent(body, content, panel)
	panel._contentWidth = content.w
	panel._stateBody = body
	panel._stateContent = content
	panel._stateWidgets = panel._stateWidgets or {}
	panel.networks = panel.networks or {}
	panel.optionRows = panel.optionRows or {}
	panel.state = panel.state or "loading"
	Selector.renderState(panel)
end

function Selector.show(playerArg)
	Selector.ensureTransientCleanup()
	local player = resolvePlayer(playerArg)
	if not player then return nil end
	local playerNum = player.getPlayerNum and player:getPlayerNum() or 0
	local existing = Selector.instances[playerNum]
	if existing and not existing.closed then existing:close() end
	local panel = Modal.create({
		kind = "compact",
		title = T("IGUI_GSSiK_RemoteSelectorTitle"),
		contentWidth = 432,
		contentHeight = 326,
		playerNum = playerNum,
		resizable = false,
		onClose = function(context)
			cleanupSelector(context and context.component)
		end,
		buildContent = buildContent,
	})
	panel.player = player
	panel.playerNum = playerNum
	panel.networks = {}
	panel.optionRows = {}
	panel.selectedNetworkId = nil
	panel.requestHandle = nil
	panel.openRequestHandle = nil
	panel.requestDeadlineMs = nil
	panel.openRequestDeadlineMs = nil
	panel.closed = false
	panel.state = "loading"
	panel.setState = Selector.setState
	panel.selectNetwork = Selector.selectNetwork
	panel.confirmSelection = Selector.confirmSelection
	panel.beginRequest = Selector.beginRequest
	panel._selectorBaseUpdate = panel.update
	panel.update = Selector.panelUpdate
	Selector.instances[playerNum] = panel
	Selector.instance = panel
	Modal.show(panel)
	Selector.beginRequest(panel)
	return panel
end

function Selector.onUseTablet(playerArg)
	return Selector.show(playerArg)
end

Selector.ensureTransientCleanup()

return Selector
