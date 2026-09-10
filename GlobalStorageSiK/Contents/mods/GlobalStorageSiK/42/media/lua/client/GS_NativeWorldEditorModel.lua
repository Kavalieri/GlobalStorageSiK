-- Reusable, UI-agnostic taxonomy-edit model for native world classification.

GlobalStorageSiK = GlobalStorageSiK or {}

local Editor = require "GS_NativeWorldEditor"
local Sync = require "GS_NativeWorldSync"
local World = GlobalStorageSiK.NativeWorldOverrides
local Registry = GlobalStorageSiK.NativeTaxonomyRegistry
local Classifier = GlobalStorageSiK.NativeClassifier
local CatalogManager = GlobalStorageSiK.CatalogManager
local T = GlobalStorageSiK.I18n.text
local WorldText = "IGUI_GS_WorldTax_"
local NativeText = "IGUI_GS_NativeTax_"

local Model = {}
GlobalStorageSiK.NativeWorldEditorModel = Model

local hasL1 = Registry and Registry.hasL1
local hasL2 = Registry and Registry.hasL2
local hasL3 = Registry and Registry.hasL3

local function text(key, ...)
	return T(WorldText .. key, ...)
end

local function label(key)
	return T(NativeText .. tostring(key))
end

local function choices(source, array)
	local result = {}
	for key, entry in pairs(source or {}) do
		local id = array and entry or key
		result[#result + 1] = { value = id, text = label(id) }
	end
	table.sort(result, function(a, b)
		return (a.text == b.text and a.value < b.value) or a.text < b.text
	end)
	return result
end

local function snapshotList(rows)
	local out = {}
	for index = 1, #(rows or {}) do
		out[index] = { value = tostring(rows[index].value or ""), text = tostring(rows[index].text or "") }
	end
	return out
end

local function firstChoice(rows)
	if #(rows or {}) == 0 then return nil end
	local value = rows[1] and rows[1].value
	if value == nil then return nil end
	return tostring(value)
end

local function shallowCopySelected(source)
	return { l1 = source.l1, l2 = source.l2, l3 = source.l3 }
end

local function invalidateSnapshot(view)
	view._snapshotDirty = true
end

local function setStatus(view, kind, reason, tone)
	local msg = text(kind, reason or "")
	local msgTone = tone or "info"
	if view.messageKey == kind and view.feedback and view.feedback.text == msg and view.feedback.tone == msgTone then
		return false
	end
	view.feedback = { text = msg, tone = msgTone }
	view.messageKey = kind
	return true
end

local function setCurrent(view, textValue, tone)
	local currentTone = tone or "text"
	if view.current and view.current.text == textValue and view.current.tone == currentTone then
		return false
	end
	view.current = { text = textValue, tone = currentTone }
	return true
end

local function cascadeChoices(view, level, path)
	local choiceRefs = view._choiceSourceRefs or {}
	local registryTree = (Registry and Registry.getTree and Registry.getTree()) or {}
	local changed = false
	if level == 1 or choiceRefs[1] ~= registryTree then
		if choiceRefs[1] ~= registryTree then
			view.choices[1] = choices(registryTree)
			choiceRefs[1] = registryTree
			changed = true
		end
		local nextL1 = path and path.l1 or view.selected.l1
		if type(nextL1) ~= "string" or not (hasL1 and hasL1(nextL1)) then nextL1 = nil end
		if nextL1 == nil then nextL1 = firstChoice(view.choices[1]) end
		if view.selected.l1 ~= nextL1 then
			view.selected.l1 = nextL1
			changed = true
		end
	end

	local l1 = view.selected.l1
	if l1 == nil then
		view.selected.l2 = nil
		view.selected.l3 = nil
		view._choiceSourceRefs = choiceRefs
		view.choices[2] = {}
		view.choices[3] = {}
		view._choiceSourceRefs[2] = nil
		view._choiceSourceRefs[3] = nil
		return changed
	end

	local sourceL2 = registryTree[l1]
	if (level <= 2) or choiceRefs[2] ~= sourceL2 then
		if choiceRefs[2] ~= sourceL2 then
			view.choices[2] = choices(sourceL2)
			choiceRefs[2] = sourceL2
			changed = true
		end
		local nextL2 = path and path.l2 or view.selected.l2
		if type(nextL2) ~= "string" or not (hasL2 and hasL2(l1, nextL2)) then nextL2 = nil end
		if nextL2 == nil then nextL2 = firstChoice(view.choices[2]) end
		if view.selected.l2 ~= nextL2 then
			view.selected.l2 = nextL2
			changed = true
		end
	end

	local l2 = view.selected.l2
	if l2 == nil then
		view.selected.l3 = nil
		view.choices[3] = {}
		view._choiceSourceRefs = choiceRefs
		view._choiceSourceRefs[3] = nil
		return changed
	end

	local sourceL3 = sourceL2 and sourceL2[l2]
	if (level <= 3) or choiceRefs[3] ~= sourceL3 then
		if choiceRefs[3] ~= sourceL3 then
			view.choices[3] = choices(sourceL3, true)
			choiceRefs[3] = sourceL3
			changed = true
		end
		local nextL3 = path and path.l3 or view.selected.l3
		if type(nextL3) ~= "string" or not (hasL3 and hasL3(l1, l2, nextL3)) then nextL3 = nil end
		if nextL3 == nil then nextL3 = firstChoice(view.choices[3]) end
		if view.selected.l3 ~= nextL3 then
			view.selected.l3 = nextL3
			changed = true
		end
	end

	view._choiceSourceRefs = choiceRefs
	return changed
end

function Model:lookup()
	local hadCapture = self.captured ~= nil
	self.captured = nil
	if hadCapture then invalidateSnapshot(self) end
	if not World.validFullType(self.fullType) then
		if setStatus(self, "InvalidType", nil, "warning") then invalidateSnapshot(self) end
		return false, "invalid_full_type"
	end
	local fullType = self.fullType
	if not (GlobalStorageSiK.I18n and GlobalStorageSiK.I18n.getScriptItem(fullType)) then
		if setStatus(self, "InvalidType", nil, "warning") then invalidateSnapshot(self) end
		return false, "invalid_full_type"
	end

	local revision = World.getRevision()
	if revision == nil then
		Sync.request(true, self.playerNum)
		if setStatus(self, "Sync", nil, "info") then invalidateSnapshot(self) end
		return false, "revision_missing"
	end

	local result = Classifier.classify(fullType)
	if not result or result.pending or not result.primaryPath then
		if setStatus(self, "Sync", nil, "info") then invalidateSnapshot(self) end
		return false, "retry"
	end

	local path = result.primaryPath
	self.captured = {
		fullType = fullType, revision = revision,
		classifierSchema = CatalogManager.getClassifierSchema(),
		catalogFingerprint = CatalogManager.getCatalogFingerprintDigest(),
		worldOverride = result.classificationScope == "world",
	}
	if not hadCapture then
		invalidateSnapshot(self)
	end

	local names = {}
	if type(path.l1) == "string" then names[#names + 1] = label(path.l1) end
	if type(path.l2) == "string" then names[#names + 1] = label(path.l2) end
	if type(path.l3) == "string" then names[#names + 1] = label(path.l3) end
	if setCurrent(self, text("Current", table.concat(names, " > "),
		text(self.captured.worldOverride and "World" or "Automatic"))) then
		invalidateSnapshot(self)
	end
	if cascadeChoices(self, 1, path) then invalidateSnapshot(self) end
	if setStatus(self, "Idle") then invalidateSnapshot(self) end
	self:refresh(true)
	return true
end

function Model:select(level, id)
	if level ~= 1 and level ~= 2 and level ~= 3 then return false, "invalid_level" end
	local value = id
	if value ~= nil and type(value) ~= "string" then value = tostring(value) end
	local previous = shallowCopySelected(self.selected)
	if level == 1 then
		self.selected.l1 = value
		self.selected.l2 = nil
		self.selected.l3 = nil
	elseif level == 2 then
		self.selected.l2 = value
		self.selected.l3 = nil
	else
		self.selected.l3 = value
	end
	local changed = cascadeChoices(self, level, self.selected)
	if changed or previous.l1 ~= self.selected.l1 or previous.l2 ~= self.selected.l2
		or previous.l3 ~= self.selected.l3 then invalidateSnapshot(self) end
	return true
end

function Model:setFullType(textValue)
	local value = tostring(textValue or "")
	if value ~= self.fullType then
		self.fullType = value
		self.captured = nil
		invalidateSnapshot(self)
		if setCurrent(self, text("ConsultFirst")) then invalidateSnapshot(self) end
		if setStatus(self, "ConsultFirst") then invalidateSnapshot(self) end
	end
end

function Model:setReason(reasonText)
	local value = tostring(reasonText or "")
	if value ~= self.reason then
		self.reason = value
		invalidateSnapshot(self)
	end
end

function Model:submit(operation)
	if not self.captured or self.fullType ~= self.captured.fullType then
		if setStatus(self, "ConsultFirst", nil, "warning") then invalidateSnapshot(self) end
		return false, "missing_consult"
	end
	if operation ~= "apply" and operation ~= "restore" then
		return false, "invalid_operation"
	end
	local pathParts = {}
	for level = 1, 3 do
		if type(self.selected["l" .. tostring(level)]) == "string" then
			pathParts[#pathParts + 1] = self.selected["l" .. tostring(level)]
		end
	end
	local nativePath = "native:" .. table.concat(pathParts, "/")
	local ok, reason = Editor.submit(self.playerNum, self.captured, operation,
		operation == "apply" and nativePath or nil, self.reason)
	if not ok then
		if setStatus(self, "Failed", reason, "warning") then invalidateSnapshot(self) end
		return false, reason
	end
	self:refresh(true)
	return true
end

function Model:refresh(force)
	local state = Editor.state(self.playerNum)
	if not state then return self end
	local revision = World.getRevision()
	local stamp = tostring(state.status) .. ":" .. tostring(state.requestId) .. ":" .. tostring(revision)
	local forceStatus = force or self._stateStamp ~= stamp
	self._stateStamp = stamp

	local busy = state.status == "pending" or state.status == "uncertain"
	local busyChanged = self.busy ~= busy
	local canApplyChanged
	local canRestoreChanged
	local captured = self.captured
	local valid = captured and captured.revision == revision and captured.fullType == self.fullType
	local reason = self.reason or ""
	valid = valid and type(reason) == "string" and #reason <= 512 and reason:find("%S") ~= nil and not reason:find("%c")
	local canApply = (not busy and valid == true)
	local canRestore = (not busy and valid == true and captured and captured.worldOverride == true)
	canApplyChanged = self.canApply ~= canApply
	canRestoreChanged = self.canRestore ~= canRestore
	self.canApply = canApply
	self.canRestore = canRestore
	self.busy = busy

	local statusChanged = false
	if forceStatus then
		if state.status == "pending" then
			statusChanged = setStatus(self, "Pending")
		elseif state.status == "uncertain" then
			statusChanged = setStatus(self, "Uncertain", nil, "warning")
		elseif state.status == "success" then
			statusChanged = setStatus(self, (state.syncPending or (state.revision and revision and revision < state.revision)) and "Sync" or "Success", nil, "success")
		elseif state.status == "failed" then
			statusChanged = setStatus(self, "Failed", state.reason, "warning")
		end
	end
	if busyChanged or canApplyChanged or canRestoreChanged or statusChanged then
		invalidateSnapshot(self)
	end
	return self
end

function Model:snapshot()
	self:refresh(false)
	if self._snapshotDirty == false and self._snapshot ~= nil then
		return self._snapshot
	end

	local prevRefs = self._snapshotChoiceRefs or {}
	local prevSnapshot = self._snapshot or {}
	local choicesSnapshot = { {}, {}, {} }
	for level = 1, 3 do
		if prevRefs[level] == self.choices[level] and prevSnapshot.choices and prevSnapshot.choices[level] then
			choicesSnapshot[level] = prevSnapshot.choices[level]
		else
			choicesSnapshot[level] = snapshotList(self.choices[level])
		end
	end

	self._snapshotChoiceRefs = { self.choices[1], self.choices[2], self.choices[3] }
	local captured = self.captured
	self._snapshot = {
		fullType = self.fullType,
		reason = self.reason,
		choices = choicesSnapshot,
		selected = shallowCopySelected(self.selected),
		captured = captured and {
			fullType = captured.fullType,
			revision = captured.revision,
			classifierSchema = captured.classifierSchema,
			catalogFingerprint = captured.catalogFingerprint,
			worldOverride = captured.worldOverride == true,
		},
		current = {
			text = self.current.text,
			tone = self.current.tone,
		},
		feedback = {
			text = self.feedback.text,
			tone = self.feedback.tone,
		},
		busy = self.busy,
		canApply = self.canApply,
		canRestore = self.canRestore,
		messageKey = self.messageKey,
	}
	self._snapshotDirty = false
	return self._snapshot
end

function Model.create(playerNum)
	local model = {
		fullType = "", reason = "", selected = { l1 = nil, l2 = nil, l3 = nil },
		choices = { {}, {}, {} }, captured = nil, playerNum = playerNum or 0,
		current = { text = text("ConsultFirst"), tone = "text" }, messageKey = "ConsultFirst",
		feedback = { text = text("ConsultFirst"), tone = "text" }, _stateStamp = nil,
		_snapshot = nil, _snapshotChoiceRefs = nil, _snapshotDirty = true,
		busy = false, canApply = false, canRestore = false,
	}
	model.refresh = Model.refresh
	model.lookup = Model.lookup
	model.select = Model.select
	model.setFullType = Model.setFullType
	model.setReason = Model.setReason
	model.submit = Model.submit
	model.snapshot = Model.snapshot
	cascadeChoices(model, 1)
	return model
end

return Model
