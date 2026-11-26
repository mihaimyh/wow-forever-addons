local addonName, ns = ...

local Flips = ns:NewModule("Flips")

Flips.lastRows = {}
Flips.lastScanAt = 0
Flips.ahOpen = false

-- Flip radar uses TSM snapshot (dbminbuyout vs dbmarket). Live AH undercuts
-- are confirmed manually: click a row to search that item at the auctioneer.

function Flips:Scan()
	local prices = ns:GetModule("Prices")
	local watchlist = ns:GetModule("Watchlist")
	local db = ns.db or {}
	local rows = {}

	if not prices:IsTSMAvailable() then
		self.lastRows = {}
		self.lastScanAt = GetTime and GetTime() or 0
		return self.lastRows
	end

	for entry in watchlist:Iterator() do
		local snap = prices:Snapshot(entry.id)
		local ok, discount = ns.PricesLogic.IsFlipCandidate(snap, db)
		if ok and discount then
			local profit = (snap.market - snap.minBuyout)
			rows[#rows + 1] = {
				id = entry.id,
				name = entry.name,
				cat = entry.cat,
				snap = snap,
				discount = discount,
				profit = profit,
				score = discount * (snap.saleRate or 50),
			}
		end
	end

	table.sort(rows, function(a, b)
		if a.score ~= b.score then return a.score > b.score end
		return (a.profit or 0) > (b.profit or 0)
	end)

	local maxRows = db.maxFlipRows or 25
	if #rows > maxRows then
		for i = #rows, maxRows + 1, -1 do
			rows[i] = nil
		end
	end

	self.lastRows = rows
	self.lastScanAt = GetTime and GetTime() or 0
	return rows
end

function Flips:GetRows()
	return self.lastRows or {}
end

function Flips:FocusSearch(itemId, itemName)
	if InCombatLockdown and InCombatLockdown() then
		ns:Print("cannot search AH in combat")
		return
	end

	-- Prefer Mainline AH search box if present.
	if AuctionHouseFrame and AuctionHouseFrame.SearchBar and AuctionHouseFrame.SearchBar.SearchBox then
		local box = AuctionHouseFrame.SearchBar.SearchBox
		if box.SetText then
			box:SetText(itemName or tostring(itemId))
		end
		if AuctionHouseFrame.SearchBar.SearchButton and AuctionHouseFrame.SearchBar.SearchButton.Click then
			pcall(AuctionHouseFrame.SearchBar.SearchButton.Click, AuctionHouseFrame.SearchBar.SearchButton)
		end
		ns:Print("AH search:", itemName or itemId)
		return
	end

	-- Classic-style browse name field.
	if BrowseName and BrowseName.SetText then
		BrowseName:SetText(itemName or "")
		if BrowseSearchButton and BrowseSearchButton.Click then
			pcall(BrowseSearchButton.Click, BrowseSearchButton)
		elseif QueryAuctionItems then
			pcall(QueryAuctionItems, itemName or "", 0, 0, 0, false, 0, false, 0, 0)
		end
		ns:Print("AH search:", itemName or itemId)
		return
	end

	ns:Print("open the Auction House, then click a flip row (or search:", itemName or itemId, ")")
end

function Flips:OnLogin()
	ns:On("AUCTION_HOUSE_SHOW", function()
		self.ahOpen = true
		self:Scan()
		local ui = ns:GetModule("UI")
		if ui and ui.OnAuctionHouseShow then ui:OnAuctionHouseShow() end
	end)
	ns:On("AUCTION_HOUSE_CLOSED", function()
		self.ahOpen = false
		local ui = ns:GetModule("UI")
		if ui and ui.OnAuctionHouseClosed then ui:OnAuctionHouseClosed() end
	end)
end
