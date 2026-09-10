local API = require "GSSiK_API_Client"
require "GSSiK_Addon_Multimedia_Runtime"
local Metadata = require "GSSiK_Addon_Multimedia_Metadata"
local Host = require "GSSiK_Addon_Multimedia_Host"
local Log = require "GSSiK_Addon_Multimedia_Log"
local M = GSSiK_Addon_Multimedia
if M.Client then return M.Client end
local Client = { sessions = {} }
M.Client = Client
local serial, LIMIT = 0, 16384
local function T(key, ...) return getText("IGUI_GSSiK_Multimedia_" .. key, ...) end
Client.text = T
local function fail(session, reason)
	Log.debug("Playback", "client command=" .. tostring(session.command)
		.. " ok=false reason=" .. tostring(reason or "unknown"))
	session.pending, session.loading, session.upload = nil, false, nil
	session.status = { ok = false, reason = reason or "unknown" }
	session.generation = session.generation + 1
end
local function request(session, command, args)
	serial = serial + 1
	args = args or {}
	args.requestId, args.networkId = serial, session.networkId
	args.anchor = { x = session.anchor.x, y = session.anchor.y, z = session.anchor.z }
	if command == "stop" or command == "recover" or command == "control" then
		args.expectedSequence = session.status.sequence or 0
	end
	session.requestId, session.pending, session.command = serial, getTimestampMs(), command
	session.nextRequestAt = getTimestampMs() + 125
	session.generation = session.generation + 1
	if isClient() then sendClientCommand(session.player, "GSSiK_Multimedia", command, args)
	else
		local ok, reason = M[command](session.player, args)
		if ok == false then fail(session, reason) end
	end
end

function Client.session(terminal)
	local player, state = API.Terminal.player(terminal), API.Terminal.state(terminal)
	if not player or not state or not state.networkId or not state.terminalAnchor
		or not API.Terminal.isAddonInstalled(terminal, "Multimedia") then return nil end
	local index = player:getPlayerNum()
	local session = Client.sessions[index]
	if session and (session.terminal ~= terminal or session.networkId ~= state.networkId
		or session.player ~= player or session.onlineId ~= player:getOnlineID()
		or session.anchor.x ~= state.terminalAnchor.x or session.anchor.y ~= state.terminalAnchor.y
		or session.anchor.z ~= state.terminalAnchor.z) then
		Client.release(session); session = nil
	end
	if not session then
		session = { player = player, onlineId = player:getOnlineID(), terminal = terminal, networkId = state.networkId,
			anchor = { x = state.terminalAnchor.x, y = state.terminalAnchor.y, z = state.terminalAnchor.z }, rows = {}, filtered = {}, selected = {}, metadata = {},
			status = {}, mediaCategories = {}, generation = 0, query = "", skill = "", sort = "title", complete = false }
		Client.sessions[index] = session
	end
	return session
end
function Client.release(session)
	if not session or Client.sessions[session.player:getPlayerNum()] ~= session then return end
	-- Closing the view abandons only its upload/cache. The terminal owns any
	-- committed playlist; uncommitted drafts expire without touching playback.
	session.upload, session.loading, session.pending = nil, false, nil
	Client.sessions[session.player:getPlayerNum()] = nil
	session.rows, session.filtered, session.metadata, session.selected = {}, {}, {}, {}
	session.mediaCategories = {}
end

function Client.describe(session, row)
	local key = tostring(row.fingerprint)
	local cached = session.metadata[key]
	local catalog = getZomboidRadio():getRecordedMedia()
	if not cached then
		local script = getScriptManager():getItem(row.fullType)
		local category = script and script:getRecordedMediaCat()
		local media = Metadata.resolve(catalog, row.fingerprint, category, session.mediaCategories)
		local details = Metadata.read(media, getText)
		local labels = {}
		for i = 1, #details.skills do labels[i] = details.skills[i].label end
		cached = { media = media, title = media and media:getTranslatedItemDisplayName()
			or (script and script:getDisplayName()) or row.fullType,
			skills = details.skills, skillSet = details.skillSet,
			skillText = #labels > 0 and table.concat(labels, ", ") or T("NoSkill") }
		session.metadata[key] = cached
	end
	-- Native knowledge is read afresh for a visible row; never grant XP or
	-- persist a per-player learned bit in a shared metadata cache.
	local media = cached.media
	local learned = media and media:getLineCount() > 0 and catalog:hasListenedToAll(session.player, media) == true
	return cached.title, learned, cached
end

function Client.filter(session, query, skill, sort)
	if query ~= nil then session.query = tostring(query) end
	if skill ~= nil then session.skill = skill end
	if sort ~= nil then session.sort = sort end
	local rows, allowed = {}, {}
	local search = string.lower(session.query)
	for i = 1, #session.rows do
		local row = session.rows[i]
		local meta = session.metadata[tostring(row.fingerprint)]
		if meta and (search == "" or string.find(string.lower(meta.title), search, 1, true))
			and (session.skill == "" or meta.skillSet[session.skill]) then
			rows[#rows + 1] = row; allowed[tostring(row.itemId)] = true
		end
	end
	table.sort(rows, function(a, b)
		local aa, bb = session.metadata[tostring(a.fingerprint)], session.metadata[tostring(b.fingerprint)]
		if session.sort == "skill" and aa.skillText ~= bb.skillText then return aa.skillText < bb.skillText end
		if aa.title ~= bb.title then return aa.title < bb.title end
		return a.itemId < b.itemId
	end)
	local selected = {}
	for key in pairs(session.selected) do if allowed[key] then selected[key] = true end end
	session.filtered, session.selected = rows, selected
	session.generation = session.generation + 1
end

function Client.toggle(session, row)
	local key = tostring(row.itemId)
	session.selected[key] = not session.selected[key] or nil
	session.generation = session.generation + 1
end
function Client.select(session, rows)
	local selected = {}
	for i = 1, #rows do selected[tostring(rows[i].itemId)] = true end
	session.selected = selected
	session.generation = session.generation + 1
end

-- Presentation groups never replace physical identity in a playlist/transfer.
-- They contain only matching filtered units, across all source nodes/pages.
function Client.groups(session)
	local groups, byKey = {}, {}
	for i = 1, #session.filtered do
		local row = session.filtered[i]
		local key = row.fullType .. ":" .. tostring(row.fingerprint)
		local group = byKey[key]
		if not group then
			group = { key = key, items = {} }; byKey[key] = group; groups[#groups + 1] = group
		end
		row.mediaIndex, row.displayName = tonumber(row.fingerprint), Client.describe(session, row)
		group.items[#group.items + 1] = row
	end
	return groups
end

function Client.inventoryChanged(session)
	if Client.sessions[session.player:getPlayerNum()] ~= session then return end
	session.catalogDirty = true
	session.generation = session.generation + 1
end

function Client.selection(session, all)
	local result, selected = {}, false
	if not all then
		for i = 1, #session.filtered do
			if session.selected[tostring(session.filtered[i].itemId)] then selected = true; break end
		end
	end
	local rows = all and session.rows or session.filtered
	for i = 1, #rows do
		local row = rows[i]
		if all or not selected or session.selected[tostring(row.itemId)] then
			result[#result + 1] = { itemId = row.itemId, fullType = row.fullType, sourceNodeId = row.sourceNodeId }
		end
	end
	if all then
		table.sort(result, function(a, b)
			local aa, bb = session.byId[tostring(a.itemId)], session.byId[tostring(b.itemId)]
			local am, bm = session.metadata[tostring(aa.fingerprint)], session.metadata[tostring(bb.fingerprint)]
			if session.sort == "skill" and am.skillText ~= bm.skillText then return am.skillText < bm.skillText end
			if am.title ~= bm.title then return am.title < bm.title end
			return a.itemId < b.itemId
		end)
	end
	return result, selected
end

function Client.catalog(session, preserveSelection)
	if (session.pending and session.command ~= "state") or session.upload then return false end
	session.selectionRestore = preserveSelection and session.selected or nil
	session.catalogDirty = false
	session.loading, session.complete, session.page = true, false, nil
	session.rows, session.filtered, session.byId, session.selected, session.metadata = {}, {}, {}, {}, {}
	session.mediaCategories = {}
	session.catalogRevision = nil
	request(session, "catalog", { node = 1, offset = 0 })
	return true
end
function Client.play(session, all)
	if (session.pending and session.command ~= "state") or session.upload or not session.complete or not session.nextSequence then return false end
	local rows = Client.selection(session, all)
	if #rows == 0 then return false end
	if #rows > LIMIT then fail(session, "catalog_limit"); return false end
	session.upload = { items = rows, sequence = session.nextSequence, offset = 1 }
	request(session, "prepare", { total = #rows, sequence = session.nextSequence })
	return true
end
function Client.stop(session)
	session.upload, session.loading = nil, false
	request(session, "stop")
end
function Client.recover(session) request(session, "recover") end
function Client.control(session, action, value)
	if (session.pending and session.command ~= "state") or session.upload then return false end
	request(session, "control", { action = action, value = value })
	return true
end

-- The visible host drives one bounded page/chunk per update, never a recursive
-- SP call chain or a permanent OnTick scan. Hidden UI performs no catalogue work.
function Client.update(session)
	local now = getTimestampMs()
	if session.pending then
		if now - session.pending >= 10000 then fail(session, "request_timeout") end
		return
	end
	if now < (session.nextRequestAt or 0) then return end
	if session.loading and session.page and session.page.hasMore then
		request(session, "catalog", { node = session.page.node, offset = session.page.offset })
	elseif session.upload and session.upload.token then
		local upload = session.upload
		if upload.offset <= #upload.items then
			local chunk = {}
			for i = upload.offset, math.min(#upload.items, upload.offset + 63) do chunk[#chunk + 1] = upload.items[i] end
			request(session, "append", { token = upload.token, offset = upload.offset, items = chunk })
		else
			session.upload = nil
			request(session, "start", { token = upload.token, sequence = upload.sequence })
		end
	elseif session.catalogDirty then
		Client.catalog(session, true)
	elseif now >= (session.nextStateAt or 0) then
		-- No authoritative push event covers another user's radio changes and
		-- engine power changes together. Backstop only for the visible consumer.
		session.nextStateAt = now + 2000
		request(session, "state")
	end
end

local function received(player, result, catalog)
	local session = player and Client.sessions[player:getPlayerNum()]
	if not session or type(result) ~= "table" or type(result.stateRevision) ~= "number" then return end
	if result.requestId and result.requestId ~= session.requestId then return end
	if result.networkId and result.networkId ~= session.networkId then return end
	if result.requestId == session.requestId then
		Log.debug("Playback", "client command=" .. tostring(session.command)
			.. " ok=" .. tostring(result.ok) .. " reason=" .. tostring(result.reason or "none")
			.. " state=" .. tostring(result.state or "none"))
	end
	if result.originalItemId and result.returnedItemId then
		local before, after = tostring(result.originalItemId), tostring(result.returnedItemId)
		if session.selected[before] then session.selected[before] = nil; session.selected[after] = true end
		if session.selectionRestore and session.selectionRestore[before] then
			session.selectionRestore[before] = nil; session.selectionRestore[after] = true
		end
		session.catalogDirty = true
	end
	if catalog then
		if result.requestId ~= session.requestId or not session.loading then return end
		if not result.ok or type(result.page) ~= "table" then fail(session, result.reason or "catalog_failed"); return end
		local page = result.page
		if session.catalogRevision ~= nil and page.inventoryRevision ~= session.catalogRevision then
			fail(session, "catalog_changed"); return
		end
		if session.page and page.hasMore and page.node == session.page.node and page.offset == session.page.offset then
			fail(session, "catalog_stalled"); return
		end
		session.catalogRevision, session.page = page.inventoryRevision, page
		for i = 1, #(page.rows or {}) do
			local row = page.rows[i]
			local key = tostring(row.itemId)
			if not session.byId[key] then
				if #session.rows >= LIMIT then fail(session, "catalog_limit"); return end
				session.byId[key] = row; session.rows[#session.rows + 1] = row
				Client.describe(session, row)
			end
		end
		session.complete, session.loading = page.hasMore ~= true, page.hasMore == true
		if session.complete and session.selectionRestore then
			session.selected, session.selectionRestore = session.selectionRestore, nil
		end
		Client.filter(session)
	end
	if result.requestId == session.requestId then
		session.pending = nil
		if result.ok == false then fail(session, result.reason); return end
		if session.upload and result.queueToken then
			session.upload.token, session.upload.offset = result.queueToken, result.nextOffset
		end
	end
	if result.stateRevision > (session.stateRevision or 0) then
		session.stateRevision, session.status = result.stateRevision, result
		if result.device and (result.device.revision or -1) >= ((session.deviceState or {}).revision or -1) then
			session.deviceState = result.device; Host.apply(result.device)
		end
		if result.nextSequence then session.nextSequence = result.nextSequence end
	end
	session.generation = session.generation + 1
end
M.onState = function(player, result) received(player, result, false) end
M.onCatalog = function(player, result) received(player, result, true) end
M.onReturn = function(result)
	if type(result) ~= "table" or not result.originalItemId or not result.returnedItemId then return end
	local before, after = tostring(result.originalItemId), tostring(result.returnedItemId)
	for _, session in pairs(Client.sessions) do
		if session.networkId == result.networkId then
			if session.selected[before] then session.selected[before] = nil; session.selected[after] = true end
			if session.selectionRestore and session.selectionRestore[before] then
				session.selectionRestore[before] = nil; session.selectionRestore[after] = true
			end
			session.catalogDirty = true; session.generation = session.generation + 1
		end
	end
end
local function serverCommand(module, command, result)
	if module ~= "GSSiK_Multimedia" or type(result) ~= "table" then return end
	if command == "returned" then M.onReturn(result); return end
	if command == "device" then
		Host.apply(result)
		for _, session in pairs(Client.sessions) do
			if session.networkId == result.networkId and session.anchor.x == result.x
				and session.anchor.y == result.y and session.anchor.z == result.z
				and type(result.revision) == "number" and result.revision > ((session.deviceState or {}).revision or -1) then
				session.deviceState = result; session.generation = session.generation + 1
			end
		end
		return
	end
	for i = 0, getNumActivePlayers() - 1 do
		local player = getSpecificPlayer(i)
		if player and player:getOnlineID() == result.playerOnlineId then received(player, result, command == "catalog") end
	end
end
Events.OnServerCommand.Add(serverCommand)
API.RemoteAccess.registerCleanup("multimedia.client", function(playerNum)
	Client.release(Client.sessions[playerNum])
end)
return Client
