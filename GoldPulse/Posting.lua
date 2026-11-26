local addonName, ns = ...

local Posting = ns:NewModule("Posting")

Posting.queue = {}
Posting.running = false
Posting.lastError = nil
Posting.posted = 0
Posting.skipped = 0
Posting.ahOpen = false

-- Forever/Mainline duration index: 1=12h, 2=24h, 3=48h
local DURATION_RATE = {
	[1] = 0.15, -- ~12h faction AH
	[2] = 0.30, -- 24h
	[3] = 0.60, -- 48h
}

local STACK_CANDIDATES = { 1, 5, 10, 20 }

ns.PricesLogic = ns.PricesLogic or {}

--- Estimate deposit when live AH APIs are unavailable.
--- Classic/Forever: scales with vendor * stack * duration rate, then min-deposit floor.
function ns.PricesLogic.EstimateDeposit(vendorSell, stackSize, duration, db)
	db = db or {}
	vendorSell = vendorSell or 0
	stackSize = stackSize or 1
	duration = duration or 2
	local rate = DURATION_RATE[duration] or DURATION_RATE[2]
	local raw = math.ceil(vendorSell * stackSize * rate)
	local minDep = db.minDepositCopper
	if minDep == nil then minDep = 100 end -- Forever launch floor was 1s; set 1 if hotfixed
	if raw < 1 then raw = 1 end
	if minDep > 0 and raw < minDep then
		return minDep, true -- floored
	end
	return raw, false
end

function ns.PricesLogic.PickDuration(saleRate, db)
	if db and db.autoDuration == false and db.postDuration then
		return db.postDuration
	end
	saleRate = saleRate or 50
	-- High liquidity → shorter listing → cheaper deposit risk.
	if saleRate >= 75 then return 1 end
	if saleRate >= 45 then return 2 end
	return 3
end

--- Choose stack size that keeps deposit risk profitable after AH cut + expire risk.
--- Returns stackSize, deposit, duration, expectedNet (or nil).
function ns.PricesLogic.RecommendStack(cat, count, maxStack, snap, unitBuyout, db)
	db = db or {}
	count = count or 1
	maxStack = maxStack or 20
	if count <= 0 or not unitBuyout or unitBuyout <= 0 then return nil end

	local vendor = (snap and snap.vendorSell) or 0
	local saleRate = (snap and snap.saleRate) or 50
	local duration = ns.PricesLogic.PickDuration(saleRate, db)
	local ahCutKeep = db.ahCutKeep or 0.95 -- faction AH
	local cover = db.depositCover or 2.0   -- net-if-sold must cover deposit this many times
	local minExpected = db.minExpectedCopper or 0

	local pref = ({ herb = 20, ore = 20, bar = 20, leather = 20, cloth = 20, potion = 5, craft = 1 })[cat or ""] or 20
	local candidates = {}
	local function add(n)
		n = math.floor(n)
		if n >= 1 and n <= count and n <= maxStack then
			candidates[n] = true
		end
	end
	for _, n in ipairs(STACK_CANDIDATES) do add(n) end
	add(pref)
	add(count)
	add(math.min(count, maxStack))

	local best, bestScore, bestDep, bestDur = nil, -math.huge, nil, duration
	for n in pairs(candidates) do
		local dep = ns.PricesLogic.EstimateDeposit(vendor, n, duration, db)
		local gross = unitBuyout * n * ahCutKeep -- deposit refunded on sale
		local p = math.max(0, math.min(1, saleRate / 100))
		-- EV: sell → +gross; expire → -deposit
		local expected = p * gross - (1 - p) * dep
		local okCover = gross >= dep * cover
		if okCover and expected >= minExpected and expected > bestScore then
			best, bestScore, bestDep, bestDur = n, expected, dep, duration
		end
	end

	if not best then
		return nil, nil, duration, nil, "deposit kills profit"
	end
	return best, bestDep, bestDur, bestScore
end

--- Per-item buyout before stack math; enforces market floor / undercut.
function ns.PricesLogic.ComputePostBuyout(snap, db)
	db = db or {}
	local minPostPct = db.minPostPct or 0.80
	local undercut = db.undercutCopper or 1
	if not snap or not snap.market or snap.market <= 0 then
		return nil, "no market"
	end

	local vendor = snap.vendorSell or 0
	local floor = math.max(math.ceil(vendor * 1.5), math.floor(snap.market * minPostPct))
	if floor < 1 then floor = 1 end

	local buyout
	if snap.minBuyout and snap.minBuyout > 0 then
		buyout = snap.minBuyout - undercut
		if buyout < 1 then buyout = 1 end
	else
		buyout = snap.market
	end

	if buyout < floor then
		return nil, "below market cutoff", floor
	end
	return buyout, nil, floor
end

local function BagRange()
	local bags = {}
	local maxBag = (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4)
	for bag = 0, maxBag do
		bags[#bags + 1] = bag
	end
	return bags
end

local function ItemIdFromLink(link)
	if type(link) ~= "string" or ns:IsSecret(link) then return nil end
	local id = link:match("item:(%d+)")
	return id and tonumber(id) or nil
end

--- Forever may hide/secret itemID on some bag slots; fall back to hyperlink like Bags.lua.
local function ReadBagSlot(bag, slot)
	if not C_Container or not C_Container.GetContainerItemInfo then return nil end
	local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
	if not ok or type(info) ~= "table" then return nil end
	local itemID = info.itemID
	local count = info.stackCount
	if ns:IsSecret(itemID) then itemID = nil end
	if ns:IsSecret(count) then count = nil end
	if type(itemID) ~= "number" then
		itemID = ItemIdFromLink(info.hyperlink)
	end
	if type(itemID) ~= "number" then return nil end
	if type(count) ~= "number" or count < 1 then count = 1 end
	return itemID, count, info.hyperlink
end

local function MaxStack(itemID)
	if C_Item and C_Item.GetItemMaxStackSizeByID then
		local ok, n = pcall(C_Item.GetItemMaxStackSizeByID, itemID)
		if ok and type(n) == "number" and n > 0 and not ns:IsSecret(n) then return n end
	end
	return 20
end

--- Live deposit from AH APIs when possible (most accurate on Forever).
function Posting:GetLiveDeposit(bag, slot, stackSize, duration, itemID)
	duration = duration or 2
	stackSize = stackSize or 1

	if C_AuctionHouse then
		if ItemLocation and ItemLocation.CreateFromBagAndSlot and C_AuctionHouse.CalculateItemDeposit then
			local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
			if loc and C_Item and C_Item.DoesItemExist and C_Item.DoesItemExist(loc) then
				local status = C_AuctionHouse.GetItemCommodityStatus and C_AuctionHouse.GetItemCommodityStatus(loc)
				local commodity = Enum and Enum.ItemCommodityStatus
				if commodity and status == commodity.Commodity and C_AuctionHouse.CalculateCommodityDeposit and itemID then
					local ok, dep = pcall(C_AuctionHouse.CalculateCommodityDeposit, itemID, duration, stackSize)
					if ok and type(dep) == "number" and not ns:IsSecret(dep) and dep >= 0 then
						return dep, "api"
					end
				end
				local ok, dep = pcall(C_AuctionHouse.CalculateItemDeposit, loc, duration, stackSize)
				if ok and type(dep) == "number" and not ns:IsSecret(dep) and dep >= 0 then
					return dep, "api"
				end
			end
		elseif C_AuctionHouse.CalculateCommodityDeposit and itemID then
			local ok, dep = pcall(C_AuctionHouse.CalculateCommodityDeposit, itemID, duration, stackSize)
			if ok and type(dep) == "number" and not ns:IsSecret(dep) and dep >= 0 then
				return dep, "api"
			end
		end
	end

	if GetAuctionDeposit and ClickAuctionSellItemButton and C_Container and C_Container.PickupContainerItem then
		-- Classic AH path — only while sell UI exists.
		if AuctionsItemButton then
			ClearCursor()
			C_Container.PickupContainerItem(bag, slot)
			pcall(ClickAuctionSellItemButton, AuctionsItemButton, "LeftButton")
			ClearCursor()
			local ok, dep = pcall(GetAuctionDeposit, duration, 0, 0, stackSize, 1)
			pcall(ClickAuctionSellItemButton, AuctionsItemButton, "LeftButton")
			ClearCursor()
			if ok and type(dep) == "number" and not ns:IsSecret(dep) then
				return dep, "classic"
			end
		end
	end

	return nil, nil
end

function Posting:BuildQueue()
	local prices = ns:GetModule("Prices")
	local watchlist = ns:GetModule("Watchlist")
	local db = ns.db or {}
	local queue = {}
	local stats = {
		slots = 0,
		tracked = 0,
		vendor = 0,
		noMarket = 0,
		cutoff = 0,
		deposit = 0,
		queued = 0,
		noTsm = false,
	}
	self.skipped = 0
	self.lastStats = stats

	if not prices or not prices:IsTSMAvailable() then
		stats.noTsm = true
		self.queue = {}
		return self.queue
	end

	for _, bag in ipairs(BagRange()) do
		local okNum, numSlots = pcall(C_Container.GetContainerNumSlots, bag)
		if okNum and type(numSlots) == "number" and not ns:IsSecret(numSlots) then
			for slot = 1, numSlots do
				local itemID, count = ReadBagSlot(bag, slot)
				if itemID then
					stats.slots = stats.slots + 1
					if watchlist:IsTracked(itemID) then
						stats.tracked = stats.tracked + 1
						local meta = watchlist:Get(itemID)
						local snap = prices:Snapshot(itemID)
						local advice = ns.PricesLogic.ClassifyBag(snap, count, db)

						-- Vendor trash stays vendor. Hold still posts if deposit EV clears.
						if advice == "vendor" then
							stats.vendor = stats.vendor + 1
							self.skipped = self.skipped + 1
						elseif not snap or not snap.market then
							stats.noMarket = stats.noMarket + 1
							self.skipped = self.skipped + 1
						else
							local buyout, reason, floor = ns.PricesLogic.ComputePostBuyout(snap, db)
							if not buyout then
								stats.cutoff = stats.cutoff + 1
								self.skipped = self.skipped + 1
							else
								local stack, estDep, duration = ns.PricesLogic.RecommendStack(
									meta and meta.cat, count, MaxStack(itemID), snap, buyout, db
								)
								if not stack then
									stats.deposit = stats.deposit + 1
									self.skipped = self.skipped + 1
								else
									local liveDep = self:GetLiveDeposit(bag, slot, stack, duration, itemID)
									local deposit = liveDep or estDep or 0
									local ahKeep = db.ahCutKeep or 0.95
									local cover = db.depositCover or 2.0
									local gross = buyout * stack * ahKeep
									local p = math.max(0, math.min(1, ((snap.saleRate or 50) / 100)))
									local expectedLive = p * gross - (1 - p) * deposit
									if gross < deposit * cover or expectedLive < (db.minExpectedCopper or 0) then
										stats.deposit = stats.deposit + 1
										self.skipped = self.skipped + 1
									else
										stats.queued = stats.queued + 1
										queue[#queue + 1] = {
											bag = bag,
											slot = slot,
											id = itemID,
											name = meta and meta.name or ("item:" .. itemID),
											cat = meta and meta.cat,
											stackSize = stack,
											buyout = buyout,
											bid = math.max(1, math.floor(buyout * 0.95)),
											floor = floor,
											deposit = deposit,
											duration = duration,
											expected = expectedLive,
											advice = advice,
											snap = snap,
										}
									end
								end
							end
						end
					end
				end
			end
		end
	end

	table.sort(queue, function(a, b)
		return (a.expected or 0) > (b.expected or 0)
	end)

	self.queue = queue
	return queue
end

function Posting:DescribeLastBuild()
	local s = self.lastStats
	if not s then return "no scan yet" end
	if s.noTsm then return "TSM missing — install TradeSkillMaster + App" end
	return string.format(
		"bags %d · tracked %d · queued %d · skip vendor %d / noAH %d / cutoff %d / deposit %d",
		s.slots or 0, s.tracked or 0, s.queued or 0,
		s.vendor or 0, s.noMarket or 0, s.cutoff or 0, s.deposit or 0
	)
end

function Posting:GetQueue()
	return self.queue or {}
end

function Posting:IsAHOpen()
	if AuctionHouseFrame and AuctionHouseFrame.IsShown and AuctionHouseFrame:IsShown() then
		return true
	end
	if AuctionFrame and AuctionFrame.IsShown and AuctionFrame:IsShown() then
		return true
	end
	return self.ahOpen == true
end

local function TryPostRetail(entry)
	if not C_AuctionHouse or not ItemLocation or not ItemLocation.CreateFromBagAndSlot then
		return false, "no C_AuctionHouse"
	end
	local loc = ItemLocation:CreateFromBagAndSlot(entry.bag, entry.slot)
	if not loc or (C_Item and C_Item.DoesItemExist and not C_Item.DoesItemExist(loc)) then
		return false, "item gone"
	end

	local duration = entry.duration or (ns.db and ns.db.postDuration) or 2
	local status = Enum and Enum.ItemCommodityStatus and C_AuctionHouse.GetItemCommodityStatus and C_AuctionHouse.GetItemCommodityStatus(loc)
	local commodity = Enum and Enum.ItemCommodityStatus

	if commodity and status == commodity.Commodity and C_AuctionHouse.PostCommodity then
		local ok, err = pcall(C_AuctionHouse.PostCommodity, loc, duration, entry.stackSize, entry.buyout)
		if not ok then return false, tostring(err) end
		return true
	end

	if C_AuctionHouse.PostItem then
		local bid = entry.bid
		local buyout = entry.buyout
		if bid and buyout and bid >= buyout then bid = nil end
		local ok, err = pcall(C_AuctionHouse.PostItem, loc, duration, entry.stackSize, bid, buyout)
		if not ok then return false, tostring(err) end
		return true
	end

	return false, "no post API"
end

local function TryPostClassic(entry)
	if not PostAuction or not ClickAuctionSellItemButton then
		return false, "no classic PostAuction"
	end
	if not C_Container or not C_Container.PickupContainerItem then
		return false, "no PickupContainerItem"
	end
	ClearCursor()
	C_Container.PickupContainerItem(entry.bag, entry.slot)
	if AuctionsItemButton then
		ClickAuctionSellItemButton(AuctionsItemButton, "LeftButton")
	else
		ClickAuctionSellItemButton()
	end
	local duration = entry.duration or (ns.db and ns.db.postDuration) or 2
	local ok, err = pcall(PostAuction, entry.bid * entry.stackSize, entry.buyout * entry.stackSize, duration, entry.stackSize, 1)
	ClearCursor()
	if not ok then return false, tostring(err) end
	return true
end

function Posting:PostNext()
	if InCombatLockdown and InCombatLockdown() then
		return false, "combat"
	end
	if not self:IsAHOpen() then
		return false, "AH closed"
	end

	if not self.queue or #self.queue == 0 then
		self:BuildQueue()
	end
	local entry = self.queue and self.queue[1]
	if not entry then
		return false, "empty"
	end

	local ok, err = TryPostRetail(entry)
	if not ok then
		ok, err = TryPostClassic(entry)
	end

	table.remove(self.queue, 1)
	if ok then
		self.posted = (self.posted or 0) + 1
		C_Timer.After(0.2, function()
			if self.running then
				self:BuildQueue()
			end
		end)
		return true
	end

	self.lastError = err
	self.skipped = (self.skipped or 0) + 1
	return false, err
end

function Posting:StartAuto()
	if self.running then return end
	if not self:IsAHOpen() then
		ns:Print("open the Auction House first")
		return
	end
	self.running = true
	self.posted = 0
	self.skipped = 0
	self:BuildQueue()
	ns:Print(string.format("auto-post started (%d queued)", #self.queue))
	ns:Print(self:DescribeLastBuild())

	local interval = tonumber(ns.db and ns.db.postInterval) or 0.75
	if interval < 0.4 then interval = 0.4 end

	self.ticker = C_Timer.NewTicker(interval, function()
		if not self.running then return end
		if not self:IsAHOpen() then
			self:StopAuto("AH closed")
			return
		end
		if InCombatLockdown and InCombatLockdown() then
			self:StopAuto("combat")
			return
		end
		local ok, err = self:PostNext()
		local ui = ns:GetModule("UI")
		if ui and ui.Refresh then ui:Refresh(false) end
		if not ok and err == "empty" then
			self:StopAuto("queue empty")
		end
	end)
end

function Posting:StopAuto(reason)
	self.running = false
	if self.ticker then
		self.ticker:Cancel()
		self.ticker = nil
	end
	ns:Print(string.format("auto-post stopped (%s) — posted %d, skipped %d",
		reason or "manual", self.posted or 0, self.skipped or 0))
	local ui = ns:GetModule("UI")
	if ui and ui.Refresh then ui:Refresh(false) end
end

function Posting:OnLogin()
	ns:On("AUCTION_HOUSE_SHOW", function()
		self.ahOpen = true
		self:BuildQueue()
		if ns.db and ns.db.autoPostWhenAH and ns.db.enabled ~= false then
			C_Timer.After(0.5, function()
				if self.ahOpen and ns.db.autoPostWhenAH then
					self:StartAuto()
				end
			end)
		end
		local ui = ns:GetModule("UI")
		if ui and ui.OnAuctionHouseShow then ui:OnAuctionHouseShow() end
	end)
	ns:On("AUCTION_HOUSE_CLOSED", function()
		self.ahOpen = false
		if self.running then self:StopAuto("AH closed") end
		local ui = ns:GetModule("UI")
		if ui and ui.OnAuctionHouseClosed then ui:OnAuctionHouseClosed() end
	end)
end
