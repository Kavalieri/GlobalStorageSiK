-- Private authoritative recovery journal. It records physical identities, not
-- reservations or permissions, and never creates, finds or transfers an item.
GlobalStorageSiK = GlobalStorageSiK or {}
local Loans = {}
GlobalStorageSiK.NetworkReadLoans = Loans
local KEY = "GlobalStorageSiK_ReadLoans_v1"
local MAX_PENDING = 64
local MAX_RECEIPTS = 32

local function textValue(value, maximum)
	return type(value) == "string" and value ~= "" and #value <= maximum
end

local function itemId(value)
	return type(value) == "number" and value >= 0 and value < math.huge
		and value == math.floor(value)
end

local function bucket(player, create)
	if not GlobalStorageSiK.isAuthoritative() or not player or not ModData then return nil end
	local character = GlobalStorageSiK.Permissions.getCharacterId(player)
	if not textValue(character, 240) then return nil end
	local store = ModData.getOrCreate(KEY)
	local value = store[character]
	if not value and create then
		value = { loans = {}, receipts = {} }
		store[character] = value
	end
	return value
end

function Loans.prepare(player, loanId, networkId, exactId, fullType)
	if not textValue(loanId, 96) or not textValue(networkId, 160)
		or not textValue(fullType, 160) or not itemId(exactId) then
		return false, "invalid_read_loan"
	end
	local state = bucket(player, true)
	if not state then return false, "read_identity_unavailable" end
	if state.loans[loanId] then return false, "read_loan_exists" end
	local count = 0
	for _, record in pairs(state.loans) do
		if record.state ~= "settled" then
			count = count + 1
			if record.itemId == exactId then return false, "read_item_already_borrowed" end
		end
	end
	if count >= MAX_PENDING then return false, "read_recovery_limit" end
	state.loans[loanId] = {
		loanId = loanId, networkId = networkId, itemId = exactId,
		fullType = fullType, state = "prepared",
	}
	return true
end

function Loans.confirm(player, loanId, item, sourceNodeId)
	local state = bucket(player, false)
	local record = state and state.loans[loanId]
	if not record or record.state ~= "prepared" or not item
		or tostring(item:getID()) ~= tostring(record.itemId)
		or item:getFullType() ~= record.fullType then return false end
	local data = item.getModData and item:getModData() or nil
	local title = data and data.literatureTitle
	if type(title) == "string" then record.literatureTitle = title end
	if textValue(sourceNodeId, 240) then record.preferredNodeId = sourceNodeId end
	record.state = "pending"
	return true
end

function Loans.abandon(player, loanId)
	local state = bucket(player, false)
	local record = state and state.loans[loanId]
	if record and record.state == "prepared" then state.loans[loanId] = nil; return true end
	return false
end

function Loans.pending(player, networkId)
	local state = bucket(player, false)
	local result = {}
	if not state then return result end
	for _, record in pairs(state.loans) do
		if record.state ~= "settled" and (networkId == nil or record.networkId == networkId) then
			result[#result + 1] = {
				loanId = record.loanId, networkId = record.networkId,
				itemId = record.itemId, fullType = record.fullType,
				preferredNodeId = record.preferredNodeId, state = record.state,
			}
		end
	end
	table.sort(result, function(a, b) return a.loanId < b.loanId end)
	return result
end

function Loans.matchReturn(player, loanId, networkId, ids)
	if not textValue(loanId, 96) or type(ids) ~= "table" or #ids ~= 1
		or not itemId(ids[1]) then return nil end
	for key in pairs(ids) do if key ~= 1 then return nil end end
	local state = bucket(player, false)
	local record = state and state.loans[loanId]
	if not record or record.networkId ~= networkId or record.itemId ~= ids[1] then return nil end
	if record.state == "settled" then return "settled" end
	return "pending"
end

function Loans.isKnown(player, loanId)
	if not textValue(loanId, 96) then return false end
	local state = bucket(player, false)
	return state ~= nil and state.loans[loanId] ~= nil
end

function Loans.settle(player, loanId, networkId, ids, moved)
	local match = Loans.matchReturn(player, loanId, networkId, ids)
	if match == "settled" then return true end
	if match ~= "pending" or moved ~= 1 then return false end
	local state = bucket(player, false)
	state.loans[loanId].state = "settled"
	state.receipts[#state.receipts + 1] = loanId
	-- Only completed receipts are bounded. An unresolved physical identity is
	-- never erased by age; reaching the recovery limit rejects a new borrow.
	while #state.receipts > MAX_RECEIPTS do
		local expired = table.remove(state.receipts, 1)
		state.loans[expired] = nil
	end
	return true
end

-- Called only after an authoritative physical deposit, including ordinary
-- player/bulk returns. Counters or a missing item never constitute proof.
function Loans.settleByExactItem(player, networkId, item)
	local state = bucket(player, false)
	if not state or not item then return false end
	local exactId, fullType = tonumber(tostring(item:getID())), item:getFullType()
	if not itemId(exactId) then return false end
	local matches = {}
	for loanId, record in pairs(state.loans) do
		if record.state ~= "settled" and record.networkId == networkId
			and record.itemId == exactId and record.fullType == fullType then
			matches[#matches + 1] = loanId
		end
	end
	for i = 1, #matches do Loans.settle(player, matches[i], networkId, { exactId }, 1) end
	return #matches > 0
end

-- Explicit authorized opening only. A vanilla/manual return by another actor
-- bypasses our deposit path; inspect live registered containers, never a cache.
-- At most MAX_PENDING identities; no work at all without debt for this network.
function Loans.reconcileStored(player, networkId)
	local records = Loans.pending(player, networkId)
	if #records == 0 then return end
	local live = GlobalStorageSiK.Network.getLiveContainers(networkId)
	for i = 1, #records do
		local record = records[i]
		for j = 1, #live do
			local container = live[j].container
			local item = container and container:getItemById(record.itemId)
			if item and item:getFullType() == record.fullType then
				Loans.settleByExactItem(player, networkId, item)
				break
			end
		end
	end
end

return Loans
