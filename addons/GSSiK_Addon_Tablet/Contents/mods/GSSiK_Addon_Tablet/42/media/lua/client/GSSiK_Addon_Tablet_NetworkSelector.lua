--[[
	GSSiK Addon Tablet - selector remoto de red
	El addon posee la presentacion; Core conserva descubrimiento y autoridad.
]]

require "GSSiK_Addon_Tablet_Access"
require "GS_TerminalUI_Api"
require "GS_PlayerUtils"
require "GS_I18n"
require "GS_SiK_UI_Modal"
require "GS_SiK_UI_Controls"
pcall(require, "GS_SiK_UI_Block")
pcall(require, "GS_SiK_UI_List")

GSSiK_Addon_Tablet = GSSiK_Addon_Tablet or {}
GSSiK_Addon_Tablet.NetworkSelector = GSSiK_Addon_Tablet.NetworkSelector or {}

local Selector = GSSiK_Addon_Tablet.NetworkSelector
Selector.instances = Selector.instances or {}
local SiK_UI = GlobalStorageSiK.SiK_UI
local Modal = SiK_UI.Modal
local Controls = SiK_UI.Controls
local Block = SiK_UI.Block
local List = SiK_UI.List
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
		feedbackKind = "error",
	},
}

local function T(key, ...)
	if GlobalStorageSiK.I18n and GlobalStorageSiK.I18n.text then
		return GlobalStorageSiK.I18n.text(key, ...)
	end
	if getText then return getText(key) end
	return key
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

local function clearRows(panel)
	panel.optionRows = {}
	if List and List.clearScrollable and panel.list then
		List.clearScrollable(panel.list, false)
	elseif panel.list and panel.list.clear then
		panel.list:clear()
	end
end

local function removeStateWidgets(panel)
	clearRows(panel)
	local body = panel._stateBody
	for i = #panel._stateWidgets, 1, -1 do
		local widget = panel._stateWidgets[i]
		if body and body.removeChild then body:removeChild(widget) end
		if widget and widget.removeFromUIManager then widget:removeFromUIManager() end
	end
	panel._stateWidgets = {}
	panel.list = nil
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

local function onSelectOption(target, _, selected)
	target:selectNetwork(selected and selected.networkId)
end

local function refreshRows(panel)
	clearRows(panel)
	if not panel.list then return end
	local y = 0
	local contentW = panel.list.width or (panel.list.getWidth and panel.list:getWidth()) or 0
	if List and List.finishScrollable then
		local rect = List.finishScrollable(panel.list, 0)
		contentW = rect and rect.w or contentW
	end
	for i = 1, #panel.networks do
		local candidate = panel.networks[i]
		local data = {
			text = candidateLabel(candidate),
			networkId = candidate.networkId,
			enabled = candidate.selectable ~= false,
			selected = candidate.networkId == panel.selectedNetworkId,
		}
		local row
		if List and List.addScrollableOption then
			row = List.addScrollableOption(panel.list, {
				x = 0, y = y, w = contentW, data = data,
				target = panel,
				callback = onSelectOption,
			})
		elseif panel.list.addItem then
			panel.list:addItem(data.text, data)
		end
		if row then
			panel.optionRows[#panel.optionRows + 1] = row
			y = y + (row.height or 34) + 8
		end
	end
	if List and List.finishScrollable then
		local rect = List.finishScrollable(panel.list, math.max(0, y - 8))
		if rect and rect.w ~= contentW and #panel.optionRows > 0 then
			y = 0
			for i = 1, #panel.optionRows do
				local row = panel.optionRows[i]
				if row.setX then row:setX(0) end
				if row.setY then row:setY(y) end
				local height = row.setOptionWidth and row:setOptionWidth(rect.w)
					or row.height or 34
				y = y + height + 8
			end
			List.finishScrollable(panel.list, math.max(0, y - 8))
		end
	end
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
				providerLabel(selected)), "ok"
		end
	end
	return T("IGUI_GSSiK_RemoteChoose"), "info"
end

local function renderBlockBackground(block)
	ISPanel.prerender(block)
	SiK_UI.drawCardBackground(block, 0)
end

local function createStateBlock(panel, y, height)
	local content = panel._stateContent
	local block = ISPanel:new(content.x, y, content.w, height)
	if block.initialise then block:initialise() end
	block.drawBackground = false
	block.prerender = renderBlockBackground
	panel._stateBody:addChild(block)
	trackStateWidget(panel, block)
	return block
end

local function onCancelAction(panel)
	panel:close()
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
			target = panel, onClick = onCancelAction,
		}))
		return y + metrics.buttonHeight
	end
	local leftText, rightText = actionLabels(panel.state)
	local half = math.floor((content.w - metrics.controlGap) / 2)
	panel.cancelButton = trackStateWidget(panel, Controls.button(panel._stateBody, {
		x = content.x, y = y, w = half, text = leftText, fullWidth = true,
		target = panel, onClick = onCancelAction,
	}))
	panel.openButton = trackStateWidget(panel, Controls.button(panel._stateBody, {
		x = content.x + half + metrics.controlGap, y = y, w = half,
		text = rightText, fullWidth = true,
		target = panel, onClick = onPrimaryAction,
	}))
	setButtonEnabled(panel.openButton, panel.state ~= "available"
		or (panel.selectedNetworkId ~= nil and panel.openRequestId == nil))
	return y + metrics.buttonHeight
end

local function createHeader(parent, x, y, width, titleKey, helpKey)
	if not Controls.blockHeader then
		return { height = controlMetrics().sectionHeight }
	end
	return Controls.blockHeader(parent, {
		x = x, y = y, w = width,
		text = T(titleKey), tooltip = T(helpKey),
	})
end

local function resolveBlockRect(block)
	if Block and Block.resolveContentRect then
		return Block.resolveContentRect({ x = 0, y = 0, w = block.width, h = block.height })
	end
	return { x = 8, y = 8, w = math.max(0, (block.width or 0) - 16),
		h = math.max(0, (block.height or 0) - 16) }
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
	local tokens = SiK_UI.Metrics and SiK_UI.Metrics.tokens and SiK_UI.Metrics.tokens() or {}
	local pad = tonumber(tokens.blockPaddingX) or 8
	local y = content.y

	if panel.state == "available" then
		local blockH = pad * 2 + metrics.sectionHeight + metrics.rowGap + 176
		local block = createStateBlock(panel, y, blockH)
		local rect = resolveBlockRect(block)
		local header = createHeader(block, rect.x, rect.y, rect.w,
			"IGUI_GSSiK_RemoteNetworksTitle", "IGUI_GSSiK_RemoteNetworksHelp")
		local listY = rect.y + (header.height or metrics.sectionHeight) + metrics.rowGap
		if List and List.createScrollable then
			panel.list = List.createScrollable(block, rect.x, listY, rect.w, 176)
		elseif ISScrollingListBox and ISScrollingListBox.new then
			panel.list = ISScrollingListBox:new(rect.x, listY, rect.w, 176)
			if panel.list.initialise then panel.list:initialise() end
			block:addChild(panel.list)
		end
		refreshRows(panel)
		y = y + blockH + metrics.rowGap
		local feedbackText, feedbackKind = feedbackFor(panel)
		if Controls.feedback then
			panel.feedback = trackStateWidget(panel, Controls.feedback(panel._stateBody, {
				x = content.x, y = y, w = content.w,
				text = feedbackText, kind = feedbackKind,
			}))
		end
		y = y + metrics.statusHeight + 8 + metrics.rowGap
	else
		local copy = STATE_COPY[panel.state] or STATE_COPY.error
		local feedbackH = metrics.statusHeight + 8
		local blockH = pad * 2 + metrics.sectionHeight + metrics.rowGap + feedbackH
		local block = createStateBlock(panel, y, blockH)
		local rect = resolveBlockRect(block)
		local header = createHeader(block, rect.x, rect.y, rect.w, copy.titleKey, copy.helpKey)
		local feedbackY = rect.y + (header.height or metrics.sectionHeight) + metrics.rowGap
		if Controls.feedback then
			panel.feedback = Controls.feedback(block, {
				x = rect.x, y = feedbackY, w = rect.w,
				text = T(copy.feedbackKey), kind = copy.feedbackKind,
			})
		end
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
	if panel.closed or panel.openRequestId or type(networkId) ~= "string" then return false end
	local found = findSelectable(panel, networkId)
	if not found then return false end
	panel.selectedNetworkId = found.networkId
	Selector.setState(panel, "available")
	return true
end

function Selector.close(panel)
	if not panel or panel.closed then return end
	panel.closed = true
	if panel.requestId then
		GlobalStorageSiK.TerminalUI.cancelRemoteNetworkRequest(panel.requestId, panel.player)
		panel.requestId = nil
	end
	if panel.openRequestId then
		if GlobalStorageSiK.TerminalUI.cancelOpenNetworkRequest then
			GlobalStorageSiK.TerminalUI.cancelOpenNetworkRequest(panel.openRequestId, panel.player)
		end
		panel.openRequestId = nil
	end
	panel.requestDeadlineMs = nil
	panel.openRequestDeadlineMs = nil
	if Selector.instances[panel.playerNum or 0] == panel then
		Selector.instances[panel.playerNum or 0] = nil
	end
	if Selector.instance == panel then Selector.instance = nil end
	Modal.close(panel)
end

function Selector.confirmSelection(panel)
	if panel.closed or panel.openRequestId or not panel.selectedNetworkId then return false end
	local selected = panel.selectedNetworkId
	if not findSelectable(panel, selected) then return false end
	local completed = false
	local requestId = GlobalStorageSiK.TerminalUI.requestOpenNetwork(selected, panel.player,
		function(accepted, reason, payload)
			completed = true
			if panel.closed then return end
			panel.openRequestId = nil
			panel.openRequestDeadlineMs = nil
			if accepted == true then
				panel:close()
				return
			end
			panel.selectedNetworkId = nil
			Selector.setState(panel, accepted == false and "outdated" or "error")
		end)
	if requestId then
		if not completed and not panel.closed then
			panel.openRequestId = requestId
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
	if panel.openRequestId then
		if GlobalStorageSiK.TerminalUI.cancelOpenNetworkRequest then
			GlobalStorageSiK.TerminalUI.cancelOpenNetworkRequest(panel.openRequestId, panel.player)
		end
		panel.openRequestId = nil
		panel.openRequestDeadlineMs = nil
	end
	if panel.requestId then
		GlobalStorageSiK.TerminalUI.cancelRemoteNetworkRequest(panel.requestId, panel.player)
		panel.requestId = nil
	end
	panel.networks = {}
	panel.selectedNetworkId = nil
	panel.requestDeadlineMs = nowMs() + REQUEST_TIMEOUT_MS
	Selector.setState(panel, "loading")
	panel.requestId = GlobalStorageSiK.TerminalUI.requestRemoteNetworks(function(networks, reason)
		if panel.closed then return end
		panel.requestId = nil
		panel.requestDeadlineMs = nil
		if reason then
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
	end, panel.player)
	if not panel.requestId then
		panel.requestDeadlineMs = nil
		Selector.setState(panel, "error")
	end
	return panel.requestId ~= nil
end

function Selector.update(panel)
	if panel.closed or not getTimestampMs then return end
	local now = nowMs()
	if panel.openRequestId and panel.openRequestDeadlineMs
		and now >= panel.openRequestDeadlineMs then
		if GlobalStorageSiK.TerminalUI.cancelOpenNetworkRequest then
			GlobalStorageSiK.TerminalUI.cancelOpenNetworkRequest(panel.openRequestId, panel.player)
		end
		panel.openRequestId = nil
		panel.openRequestDeadlineMs = nil
		panel.selectedNetworkId = nil
		Selector.setState(panel, "error")
		return
	end
	if panel.state == "loading" and panel.requestDeadlineMs
		and now >= panel.requestDeadlineMs then
		if panel.requestId then
			GlobalStorageSiK.TerminalUI.cancelRemoteNetworkRequest(panel.requestId, panel.player)
			panel.requestId = nil
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
	local client = GlobalStorageSiK.Client
	if not client or type(client.registerTransientCleanup) ~= "function" then return false end
	client.registerTransientCleanup("TabletNetworkSelector", function(playerNum)
		if playerNum == nil then Selector.closeAll()
		else Selector.closeForPlayer(playerNum) end
	end)
	Selector._cleanupRegistered = true
	return true
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
	local player = GlobalStorageSiK.PlayerUtils.resolve(playerArg)
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
		onClose = function(target) target:close() end,
		buildContent = buildContent,
	})
	panel.player = player
	panel.playerNum = playerNum
	panel.networks = {}
	panel.optionRows = {}
	panel.selectedNetworkId = nil
	panel.requestId = nil
	panel.openRequestId = nil
	panel.requestDeadlineMs = nil
	panel.openRequestDeadlineMs = nil
	panel.closed = false
	panel.state = "loading"
	panel.setState = Selector.setState
	panel.selectNetwork = Selector.selectNetwork
	panel.confirmSelection = Selector.confirmSelection
	panel.close = Selector.close
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
