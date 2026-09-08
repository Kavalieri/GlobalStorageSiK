-- Compact Staff taxonomy composition; audit/corpus retain independent requests.
require "GS_I18n"
local UI = require "GS_UI_Framework"
local View = {}
local T = GlobalStorageSiK.I18n.text
local GAP = 8
local BTN_H = UI.Controls.metrics().buttonHeight

local function prefix(kind) return kind == "audit" and "_nativeAudit" or "_nativeCorpus" end

local function state(ui, kind)
	local key = prefix(kind)
	if ui[key .. "Running"] then return T("IGUI_GS_TaxonomyStateRunning"), "warning" end
	if ui[key .. "LastFailed"] then return T("IGUI_GS_TaxonomyStateError"), "danger" end
	if ui[key .. "LastReport"] then
		local age = GlobalStorageSiK.AdminDashboard.relativeAge(ui[key .. "FinishedAtMs"])
		ui[key .. "FinishedAtText"] = age
		return T("IGUI_GS_TaxonomyStateDone", age), "success"
	end
	return T("IGUI_GS_TaxonomyStateIdle"), "info"
end

local function summary(kind, report)
	if not report then return T("IGUI_GS_TaxonomyNoRunYet"), "" end
	if kind == "audit" then
		local text = T("IGUI_GS_TaxonomySummaryLine", tostring(report.totalTypes), tostring(report.pending),
			tostring(report.unclassified), tostring(report.excludedInternal or 0), tostring(report.invalidPath),
			tostring(report.classifierErrors), tostring(report.timeMs))
		local details = {
			T("IGUI_GS_TaxonomyEpochLine", tostring(report.catalogEpoch), tostring(report.gameBuildVersion),
				tostring(report.activeModCount), tostring(report.catalogFingerprintDigest)),
			T("IGUI_GS_TaxonomyTierVariantLine", tostring(report.tierVariantMatched), tostring(report.tierVariantTotal)),
			T("IGUI_GS_TaxonomyRunLine", tostring(report.sessionId or "?"), tostring(report.runId or "?")),
		}
		for _, file in ipairs({ { "IGUI_GS_TaxonomyFileReport", report.fileName },
			{ "IGUI_GS_TaxonomyFileUnclassified", report.unclassifiedFileName },
			{ "IGUI_GS_TaxonomyFileExcludedInternal", report.excludedInternalFileName } }) do
			if file[2] then details[#details + 1] = T(file[1], tostring(file[2])) end
		end
		return text, table.concat(details, "\n")
	end
	local text = T("IGUI_GS_TaxonomyRunLine", tostring(report.sessionId or "?"), tostring(report.runId or "?"))
	local details = {
		T("IGUI_GS_TaxonomyCorpusVersionLine", tostring(report.corpusVersion)),
		T("IGUI_GS_TaxonomyCorpusCountsLine", tostring(report.totalCases), tostring(report.applicableCases),
			tostring(report.absentCases), tostring(report.skippedCases), tostring(report.passedCases), tostring(report.failedCases)),
		T("IGUI_GS_TaxonomyCorpusAccuracyLine", tostring(report.l1CorrectCount), tostring(report.l1Total),
			tostring(report.l2CorrectCount), tostring(report.l2Total), tostring(report.l3CorrectCount), tostring(report.l3Total)),
		T("IGUI_GS_TaxonomyCorpusFailureKindsLine", tostring(report.classificationFailures), tostring(report.evidenceFailures),
			tostring(report.facetAttributeFailures), tostring(report.requiredMissingFailures)),
	}
	for _, block in ipairs({
		{ "globalstoragesik", "ownBlockStatus", "ownBlockReasons" }, { "tools", "toolsBlockStatus", "toolsBlockReasons" },
		{ "combat", "combatBlockStatus", "combatBlockReasons" }, { "clothing_protection", "clothingBlockStatus", "clothingBlockReasons" },
		{ "containers", "containersBlockStatus", "containersBlockReasons" },
	}) do
		if report[block[2]] then
			details[#details + 1] = T("IGUI_GS_TaxonomyCorpusBlockStatusLine", block[1], tostring(report[block[2]]))
			if report[block[3]] and report[block[3]] ~= "" then
				details[#details + 1] = T("IGUI_GS_TaxonomyCorpusBlockReasonsLine", tostring(report[block[3]]))
			end
		end
	end
	if report.fileName then details[#details + 1] = T("IGUI_GS_TaxonomyFileCorpus", tostring(report.fileName)) end
	return text, table.concat(details, "\n")
end

function View.build(ui, kind)
	if not ui.taxonomyScroll then
		ui.taxonomyScroll = UI.Scroll.create(ui.taxonomyTabRoot, 0, 0, ui.taxonomyTabRoot.width, ui.taxonomyTabRoot.height)
		UI.Scroll.setOnContentRectChanged(ui.taxonomyScroll, function() View.reflow(ui) end)
	end
	ui.taxonomyViews = ui.taxonomyViews or {}
	if ui.taxonomyViews[kind] then return end
	local audit = kind == "audit"
	local frame, reason = UI.Block.create({ parent = UI.Scroll.childHost(ui.taxonomyScroll), x = 0, y = 0, w = 400, h = 160,
		title = T(audit and "IGUI_GS_AdminCatalogAuditTitle" or "IGUI_GS_AdminContractCorpusTitle"),
		tooltip = T(audit and "IGUI_GS_AdminCatalogAuditHelp" or "IGUI_GS_AdminContractCorpusHelp") })
	if not frame then error("Staff Taxonomy Block: " .. tostring(reason)) end
	local parent = frame.childParent
	local button = UI.Controls.button(parent, { x = 0, y = 0, w = 200, h = BTN_H,
		text = T(audit and "IGUI_GS_NativeAuditBtn" or "IGUI_GS_NativeCorpusBtn"), fullWidth = true,
		onClick = function()
			if audit then GlobalStorageSiK.AdminDashboardAudit.runNativeAudit(ui)
			else GlobalStorageSiK.AdminDashboardCorpus.runNativeCorpus(ui) end
		end })
	ui[audit and "nativeAuditBtn" or "nativeCorpusBtn"] = button
	ui.taxonomyViews[kind] = { frame = frame, button = button,
		status = UI.Controls.status(parent, { wrap = true, indicator = true, text = "", w = 200 }),
		summary = UI.Controls.status(parent, { wrap = true, framed = true, text = "", tone = "text", w = 200 }),
	}
	View.refresh(ui, kind)
end

function View.refresh(ui, kind)
	local view = ui.taxonomyViews and ui.taxonomyViews[kind]
	if not view then return end
	local text, tone = state(ui, kind)
	view.status:setStatus(text, tone)
	local report = ui[prefix(kind) .. "LastReport"]
	local textSummary, details = summary(kind, report)
	view.summary:setStatus(textSummary)
	UI.Controls.setTooltip(view.summary, details ~= "" and details or nil, { kind = "descriptive", profile = "informational" })
	local locked = ui[prefix(kind) .. "Running"] == true
	view.button._sikUiLocked = locked
	view.button:setEnable(not locked)
	View.reflow(ui)
end

function View.reflow(ui)
	if not ui.taxonomyScroll or ui._taxonomyLayoutActive then return end
	ui._taxonomyLayoutActive = true
	UI.Scroll.resize(ui.taxonomyScroll, ui.taxonomyTabRoot.width, ui.taxonomyTabRoot.height)
	for pass = 1, 2 do
		local width, y = UI.Scroll.contentWidth(ui.taxonomyScroll), 0
		for _, kind in ipairs({ "audit", "corpus" }) do
			local view = ui.taxonomyViews and ui.taxonomyViews[kind]
			if view then
				view.frame:setBounds(0, y, width, 160)
				local rect = view.frame:getContentRect()
				UI.Layout.apply(view.button, { x = rect.x, y = rect.y, w = rect.w, h = BTN_H })
				view.status:reflow(rect.w)
				view.status:setX(rect.x); view.status:setY(rect.y + BTN_H + GAP)
				view.summary:reflow(rect.w)
				view.summary:setX(rect.x); view.summary:setY(view.status.y + view.status.height + GAP)
				local height = UI.Block.intrinsicHeight(view.summary.y + view.summary.height - rect.y,
					{ headerHeight = view.frame.headerHeight, headerGap = GAP })
				view.frame:setBounds(0, y, width, height)
				y = y + height + GAP
			end
		end
		UI.Scroll.setContentHeight(ui.taxonomyScroll, math.max(0, y - GAP))
		if UI.Scroll.contentWidth(ui.taxonomyScroll) == width then break end
	end
	ui._taxonomyLayoutActive = nil
end

function View.dispose(ui)
	for _, kind in ipairs({ "audit", "corpus" }) do
		local view = ui.taxonomyViews and ui.taxonomyViews[kind]
		if view then view.frame:dispose() end
	end
	ui.taxonomyViews = nil
end

return View
