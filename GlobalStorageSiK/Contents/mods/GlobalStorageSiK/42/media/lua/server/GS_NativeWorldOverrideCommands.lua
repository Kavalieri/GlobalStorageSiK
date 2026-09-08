-- RPC adapter for world taxonomy. No network session is required for public data.
require "GS_NativeWorldOverridesServer"
GlobalStorageSiK.NativeWorldOverrideCommands = {}
local Commands = GlobalStorageSiK.NativeWorldOverrideCommands
local World = GlobalStorageSiK.NativeWorldOverrides
local lastRead = {}
local publications = {}

-- Bounded outbox: retry delivery, never the already committed mutation.
-- The existing server tick calls this; an empty outbox does no clock work.
function Commands.flushPublications(publish)
	local job = publications[1]
	if not job then return end
	local now = getTimestampMs and getTimestampMs()
	if type(now) ~= "number" or now ~= now or now < 0 or now >= math.huge then return end
	if job.nextAt and now >= job.lastAt and now < job.nextAt then return end
	local ok, result = pcall(publish, job.fullType, job.revision, job)
	if ok and result ~= false then
		job.pending = false
		table.remove(publications, 1)
	else
		job.delay = math.min((job.delay or 500) * 2, 30000)
		job.lastAt, job.nextAt = now, now + job.delay
	end
end

local function permitRead(player)
	local name = player and player.getUsername and player:getUsername()
	local now = getTimestampMs and getTimestampMs()
	if type(name) ~= "string" or #name == 0 or #name > 128 or type(now) ~= "number"
		or now ~= now or now < 0 or now >= math.huge then return false end
	local count, expired = 0, {}
	for key, timestamp in pairs(lastRead) do
		if now < timestamp or now - timestamp >= 30000 then expired[#expired + 1] = key
		else count = count + 1 end
	end
	for i = 1, #expired do lastRead[expired[i]] = nil end
	if lastRead[name] and now - lastRead[name] < 1000 then return false end
	if not lastRead[name] and count >= 256 then return false end
	lastRead[name] = now
	return true
end

function Commands.dispatch(command, player, args, requireStaff, send, publish)
	if command ~= "getTaxonomyOverrides" and command ~= "changeTaxonomyOverride" then return false end
	if not GlobalStorageSiK.isAuthoritative() then return true end
	if type(args) ~= "table" or not World.validRevision(args.requestId) or args.requestId == 0 then return true end
	if command == "getTaxonomyOverrides" then
		if not permitRead(player) then
			send(player, "taxonomyOverrideError", { requestId = args.requestId, reason = "busy" })
			return true
		end
		local pages, reason = GlobalStorageSiK.NativeWorldOverridesServer.publicPages(args.requestId)
		if not pages then
			send(player, "taxonomyOverrideError", { requestId = args.requestId, reason = reason })
			return true
		end
		for i = 1, #pages do send(player, "taxonomyOverridePage", pages[i]) end
		return true
	end
	if #publications >= 128 then
		send(player, "taxonomyOverrideResult", { requestId = args.requestId, ok = false, reason = "sync_busy" })
		return true
	end
	local ok, reason, revision, fullType = GlobalStorageSiK.NativeWorldOverridesServer.change(player, args, requireStaff)
	local syncPending = false
	if ok then
		local store = World.getAuthoritativeStore()
		local entry = store and store.entries[fullType]
		local job = { fullType = fullType, revision = revision, pending = true,
			nativePath = entry and World.decodePath(entry.nativePath) and entry.nativePath or false }
		publications[#publications + 1] = job
		Commands.flushPublications(publish)
		syncPending = job.pending
	end
	send(player, "taxonomyOverrideResult", { requestId = args.requestId, ok = ok,
		reason = reason, revision = revision, fullType = fullType or (World.validFullType(args.fullType) and args.fullType or nil),
		syncPending = syncPending })
	return true
end

return Commands
