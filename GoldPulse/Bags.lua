local addonName, ns = ...

local Bags = ns:NewModule("Bags")

Bags.lastRows = {}
Bags.lastScanAt = 0

local function ItemIdFromLink(link)
	if type(link) ~= "string" or ns:IsSecret(link) then return nil end
	local id = link:match("item:(%d+)")
	return id and tonumber(id) or nil
end

local function GetBagSlotInfo(bag, slot)
	if not C_Container or not C_Container.GetContainerItemInfo then return nil end
	local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
	if not ok or type(info) ~= "table" then return nil end
	local itemID = info.itemID
	local stackCount = info.stackCount
	local hyperlink = info.hyperlink
	if ns:IsSecret(itemID) or ns:IsSecret(stackCount) then return nil end
	if type(itemID) ~= "number" then
		itemID = ItemIdFromLink(hyperlink)
	end
	if type(itemID) ~= "number" then return nil end
	if type(stackCount) ~= "number" or stackCount < 1 then stackCount = 1 end
	return itemID, stackCount, hyperlink
end

local function BagRange()
	local bags = {}
	-- Forever/Mainline: 0 backpack + 1..NUM_BAG_SLOTS (+ reagent bag if present)
	local maxBag = (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4)
	for bag = 0, maxBag do
		bags[#bags + 1] = bag
	end
	return bags
end

function Bags:Scan()
	local prices = ns:GetModule("Prices")
	local watchlist = ns:GetModule("Watchlist")
	local db = ns.db or {}
	local aggregated = {}

	for _, bag in ipairs(BagRange()) do
		local okNum, numSlots = pcall(C_Container.GetContainerNumSlots, bag)
		if okNum and type(numSlots) == "number" and not ns:IsSecret(numSlots) then
			for slot = 1, numSlots do
				local itemID, count, link = GetBagSlotInfo(bag, slot)
				if itemID and watchlist:IsTracked(itemID) then
					local entry = aggregated[itemID]
					if not entry then
						local meta = watchlist:Get(itemID)
						entry = {
							id = itemID,
							name = meta and meta.name or ("item:" .. itemID),
							cat = meta and meta.cat or "misc",
							count = 0,
							link = link,
						}
						aggregated[itemID] = entry
					end
					entry.count = entry.count + count
					if link and not entry.link then entry.link = link end
				end
			end
		end
	end

	local rows = {}
	for _, entry in pairs(aggregated) do
		local snap = prices:Snapshot(entry.id)
		local advice, reason = ns.PricesLogic.ClassifyBag(snap, entry.count, db)
		local isFlip, discount = ns.PricesLogic.IsFlipCandidate(snap, db)
		local unit = (snap and (snap.minBuyout or snap.market)) or 0
		rows[#rows + 1] = {
			id = entry.id,
			name = entry.name,
			cat = entry.cat,
			count = entry.count,
			link = entry.link,
			advice = advice,
			reason = reason,
			flip = isFlip and true or false,
			discount = discount,
			snap = snap,
			stackValue = unit * entry.count,
		}
	end

	table.sort(rows, function(a, b)
		local order = { sell = 1, flip_candidate = 2, hold = 3, vendor = 4 }
		-- Promote sell, then flip note, then by stack value.
		local aa = a.advice
		if a.flip and aa == "hold" then aa = "flip_candidate" end
		local bb = b.advice
		if b.flip and bb == "hold" then bb = "flip_candidate" end
		local oa, ob = order[aa] or 9, order[bb] or 9
		if oa ~= ob then return oa < ob end
		return (a.stackValue or 0) > (b.stackValue or 0)
	end)

	local maxRows = db.maxBagRows or 40
	if #rows > maxRows then
		for i = #rows, maxRows + 1, -1 do
			rows[i] = nil
		end
	end

	self.lastRows = rows
	self.lastScanAt = GetTime and GetTime() or 0
	return rows
end

function Bags:GetRows()
	return self.lastRows or {}
end

function Bags:OnLogin()
	ns:On("BAG_UPDATE", function()
		if not ns.db or not ns.db.enabled then return end
		-- Debounce via next refresh tick in UI; mark dirty.
		self.dirty = true
	end)
	ns:On("PLAYER_ENTERING_WORLD", function()
		self.dirty = true
	end)
end
