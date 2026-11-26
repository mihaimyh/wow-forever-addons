local addonName, ns = ...

local UI = ns:NewModule("UI")

local GOLD = { 0.94, 0.78, 0.38 }
local IVORY = { 0.96, 0.95, 0.91 }
local MUTED = { 0.70, 0.68, 0.64 }
local READY = { 0.45, 0.90, 0.40 }
local WARN = { 1.00, 0.62, 0.22 }
local OOR = { 1.00, 0.42, 0.38 }

local PANEL_W, PANEL_H = 360, 320
local ROW_H = 18
local VISIBLE_ROWS = 12

local function SetPixelSize(region, w, h)
	if PixelUtil and PixelUtil.SetSize then
		PixelUtil.SetSize(region, w, h)
	else
		region:SetSize(w, h)
	end
end

local ADVICE_COLOR = {
	sell = READY,
	hold = MUTED,
	vendor = WARN,
	flip = GOLD,
}

local function AdviceLabel(advice, flip)
	if flip and advice ~= "sell" then return "FLIP?", GOLD end
	if advice == "sell" then return "SELL", READY end
	if advice == "vendor" then return "VENDOR", WARN end
	return "HOLD", MUTED
end

function UI:OnLogin()
	local ok, err = pcall(function()
		self:Build()
		self:ApplyScale()
		self:ApplyPosition()
		self:ApplyLock()
	end)
	if not ok then
		ns:RecordError("UI:Build", err)
		ns:Print("|cffff5555UI build failed|r", err)
		return
	end

	ns:On("PLAYER_ENTERING_WORLD", function()
		if self.frame and self.frame:IsShown() then
			self:Refresh(true)
		end
	end)

	-- Auto-refresh while shown: immediate on bag dirty, periodic full rescan.
	if self.frame then
		self.dirtyAccum = 0
		self.periodicAccum = 0
		self.frame:SetScript("OnUpdate", function(_, elapsed)
			if not self.frame:IsShown() then return end
			if not ns.db or not ns.db.enabled then return end
			if ns.db.autoRefresh == false then return end

			local bags = ns:GetModule("Bags")
			if bags and bags.dirty then
				self.dirtyAccum = (self.dirtyAccum or 0) + elapsed
				-- Debounce bag spam (~0.4s) then rescan.
				if self.dirtyAccum >= 0.4 then
					self.dirtyAccum = 0
					bags.dirty = false
					self.periodicAccum = 0
					self:Refresh(true)
				end
				return
			end

			self.dirtyAccum = 0
			local interval = tonumber(ns.db.autoRefreshSeconds) or 15
			if interval < 5 then interval = 5 end
			if interval > 120 then interval = 120 end
			self.periodicAccum = (self.periodicAccum or 0) + elapsed
			if self.periodicAccum >= interval then
				self.periodicAccum = 0
				self:Refresh(true)
			end
		end)
	end
end

function UI:Build()
	local frame = CreateFrame("Frame", "GoldPulseFrame", UIParent, "BackdropTemplate")
	SetPixelSize(frame, PANEL_W, PANEL_H)
	frame:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8X8",
		edgeFile = "Interface\\Buttons\\WHITE8X8",
		tile = false,
		edgeSize = 1,
	})
	frame:SetBackdropColor(0.05, 0.05, 0.07, 0.94)
	frame:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.45)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetClampedToScreen(true)
	frame:SetFrameStrata("MEDIUM")
	frame:Hide()

	frame:SetScript("OnDragStart", function(f)
		if ns.db and not ns.db.locked then f:StartMoving() end
	end)
	frame:SetScript("OnDragStop", function(f)
		f:StopMovingOrSizing()
		UI:SavePosition()
	end)

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	title:SetPoint("TOPLEFT", 10, -8)
	title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
	title:SetText("GOLDPULSE")

	local status = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	status:SetPoint("TOPRIGHT", -10, -10)
	status:SetTextColor(MUTED[1], MUTED[2], MUTED[3])
	status:SetText("")

	local tabBags = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	tabBags:SetSize(58, 22)
	tabBags:SetPoint("TOPLEFT", 8, -28)
	tabBags:SetText("Bags")

	local tabFlips = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	tabFlips:SetSize(58, 22)
	tabFlips:SetPoint("LEFT", tabBags, "RIGHT", 3, 0)
	tabFlips:SetText("Flips")

	local tabPost = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	tabPost:SetSize(58, 22)
	tabPost:SetPoint("LEFT", tabFlips, "RIGHT", 3, 0)
	tabPost:SetText("Post")

	local tabStatus = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	tabStatus:SetSize(58, 22)
	tabStatus:SetPoint("LEFT", tabPost, "RIGHT", 3, 0)
	tabStatus:SetText("Status")

	local scanBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	scanBtn:SetSize(52, 22)
	scanBtn:SetPoint("TOPRIGHT", -8, -28)
	scanBtn:SetText("Scan")
	scanBtn:SetScript("OnClick", function()
		ns:HandleSlash("scan")
	end)

	local postBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	postBtn:SetSize(70, 22)
	postBtn:SetPoint("RIGHT", scanBtn, "LEFT", -4, 0)
	postBtn:SetText("AutoPost")
	postBtn:SetScript("OnClick", function()
		local posting = ns:GetModule("Posting")
		if not posting then return end
		if posting.running then
			posting:StopAuto("ui")
			postBtn:SetText("AutoPost")
		else
			self.tab = "post"
			posting:StartAuto()
			postBtn:SetText("Stop")
			self:Refresh(false)
		end
	end)
	self.postBtn = postBtn

	local header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	header:SetPoint("TOPLEFT", 10, -56)
	header:SetPoint("TOPRIGHT", -10, -56)
	header:SetJustifyH("LEFT")
	header:SetTextColor(MUTED[1], MUTED[2], MUTED[3])
	header:SetText("")

	local body = CreateFrame("Frame", nil, frame)
	body:SetPoint("TOPLEFT", 8, -72)
	body:SetPoint("BOTTOMRIGHT", -8, 10)

	local rows = {}
	for i = 1, VISIBLE_ROWS do
		local row = CreateFrame("Button", nil, body)
		row:SetHeight(ROW_H)
		row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
		row:SetPoint("TOPRIGHT", 0, -(i - 1) * ROW_H)
		row:EnableMouse(true)

		local tag = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		tag:SetPoint("LEFT", 2, 0)
		tag:SetWidth(52)
		tag:SetJustifyH("LEFT")

		local name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		name:SetPoint("LEFT", tag, "RIGHT", 4, 0)
		name:SetPoint("RIGHT", row, "RIGHT", -90, 0)
		name:SetJustifyH("LEFT")
		name:SetWordWrap(false)

		local detail = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		detail:SetPoint("RIGHT", -2, 0)
		detail:SetJustifyH("RIGHT")
		detail:SetTextColor(MUTED[1], MUTED[2], MUTED[3])

		row.tag, row.name, row.detail = tag, name, detail
		row:SetScript("OnEnter", function(self)
			if self.tip then
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:SetText(self.tipTitle or "GoldPulse")
				GameTooltip:AddLine(self.tip, 0.9, 0.9, 0.9, true)
				GameTooltip:Show()
			end
		end)
		row:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)
		rows[i] = row
	end

	local statusText = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	statusText:SetPoint("TOPLEFT", 4, -4)
	statusText:SetPoint("BOTTOMRIGHT", -4, 4)
	statusText:SetJustifyH("LEFT")
	statusText:SetJustifyV("TOP")
	statusText:SetTextColor(IVORY[1], IVORY[2], IVORY[3])
	statusText:Hide()

	self.frame = frame
	self.title = title
	self.status = status
	self.header = header
	self.rows = rows
	self.statusText = statusText
	self.tab = "bags"
	self.tabBags = tabBags
	self.tabFlips = tabFlips
	self.tabPost = tabPost
	self.tabStatus = tabStatus

	tabBags:SetScript("OnClick", function()
		self.tab = "bags"
		self:Refresh(true)
	end)
	tabFlips:SetScript("OnClick", function()
		self.tab = "flips"
		self:Refresh(true)
	end)
	tabPost:SetScript("OnClick", function()
		self.tab = "post"
		self:Refresh(true)
	end)
	tabStatus:SetScript("OnClick", function()
		self.tab = "status"
		self:Refresh(false)
	end)
end

function UI:ClearRows()
	for _, row in ipairs(self.rows) do
		row:Hide()
		row.tip = nil
		row:SetScript("OnClick", nil)
	end
end

function UI:ShowBagRows()
	local bags = ns:GetModule("Bags")
	local prices = ns:GetModule("Prices")
	local list = bags:GetRows()
	local auto = (ns.db and ns.db.autoRefresh ~= false) and " · auto" or ""
	self.header:SetText(string.format("Tracked mats in bags (%d)%s", #list, auto))
	self.statusText:Hide()

	if #list == 0 then
		self:ClearRows()
		self.statusText:Show()
		self.statusText:SetText("No watchlist mats in bags.\nGather herbs / ore / leather / cloth, then Scan.")
		return
	end

	self.statusText:Hide()
	for i, row in ipairs(self.rows) do
		local data = list[i]
		if not data then
			row:Hide()
		else
			row:Show()
			local label, color = AdviceLabel(data.advice, data.flip)
			row.tag:SetText(label)
			row.tag:SetTextColor(color[1], color[2], color[3])
			row.name:SetText(string.format("%s x%d", data.name, data.count))
			local unit = data.snap and (data.snap.minBuyout or data.snap.market)
			row.detail:SetText(unit and prices:FormatMoney(unit) or "-")
			row.tipTitle = data.name
			row.tip = string.format("%s — %s\nStack ~ %s", data.advice, data.reason or "", prices:FormatMoney(data.stackValue or 0))
			row:SetScript("OnClick", nil)
		end
	end
end

function UI:ShowFlipRows()
	local flips = ns:GetModule("Flips")
	local prices = ns:GetModule("Prices")
	local list = flips:GetRows()
	local ahNote = flips.ahOpen and "AH open" or "TSM snapshot"
	local auto = (ns.db and ns.db.autoRefresh ~= false) and " · auto" or ""
	self.header:SetText(string.format("Flip candidates (%d) · %s%s", #list, ahNote, auto))
	self.statusText:Hide()

	if #list == 0 then
		self:ClearRows()
		self.statusText:Show()
		self.statusText:SetText("No flips under your buy threshold.\nLower Flip % in settings, or wait for undercuts.")
		return
	end

	for i, row in ipairs(self.rows) do
		local data = list[i]
		if not data then
			row:Hide()
		else
			row:Show()
			row.tag:SetText(string.format("-%d%%", math.floor((data.discount or 0) * 100 + 0.5)))
			row.tag:SetTextColor(READY[1], READY[2], READY[3])
			row.name:SetText(data.name)
			row.detail:SetText(string.format("%s → %s",
				prices:FormatMoney(data.snap.minBuyout),
				prices:FormatMoney(data.snap.market)))
			row.tipTitle = data.name
			row.tip = string.format(
				"Buy near %s, market %s\nSale rate %s · click to search AH",
				prices:FormatMoney(data.snap.minBuyout),
				prices:FormatMoney(data.snap.market),
				data.snap.saleRate and string.format("%.0f%%", data.snap.saleRate) or "?"
			)
			row:SetScript("OnClick", function()
				flips:FocusSearch(data.id, data.name)
			end)
		end
	end
end

function UI:ShowPostRows()
	local posting = ns:GetModule("Posting")
	local prices = ns:GetModule("Prices")
	if not posting then return end
	local list = posting:GetQueue()
	if #list == 0 then
		posting:BuildQueue()
		list = posting:GetQueue()
	end
	local run = posting.running and "RUNNING" or "idle"
	self.header:SetText(string.format("Post queue (%d) · %s · skip %d", #list, run, posting.skipped or 0))
	self.statusText:Hide()

	if self.postBtn then
		self.postBtn:SetText(posting.running and "Stop" or "AutoPost")
	end

	if #list == 0 then
		self:ClearRows()
		self.statusText:Show()
		local why = posting.DescribeLastBuild and posting:DescribeLastBuild() or "empty"
		self.statusText:SetText("Nothing to post.\n" .. why .. "\n\n/gp post queue — recount\nLoosen depositCover / minDeposit in settings if deposit kills stacks.")
		return
	end

	local durLabel = { [1] = "12h", [2] = "24h", [3] = "48h" }
	for i, row in ipairs(self.rows) do
		local data = list[i]
		if not data then
			row:Hide()
		else
			row:Show()
			row.tag:SetText(string.format("x%d", data.stackSize or 1))
			row.tag:SetTextColor(READY[1], READY[2], READY[3])
			row.name:SetText(data.name)
			row.detail:SetText(string.format("%s · dep %s",
				prices:FormatMoney((data.buyout or 0) * (data.stackSize or 1)),
				prices:FormatMoney(data.deposit or 0)))
			row.tipTitle = data.name
			row.tip = string.format(
				"Stack %d · %s · buyout/ea %s\nDeposit %s · EV %s\nCutoff respects deposit + AH cut + expire risk",
				data.stackSize or 1,
				durLabel[data.duration or 2] or "?",
				prices:FormatMoney(data.buyout or 0),
				prices:FormatMoney(data.deposit or 0),
				prices:FormatMoney(math.floor(data.expected or 0))
			)
			row:SetScript("OnClick", nil)
		end
	end
end

function UI:ShowStatus()
	self:ClearRows()
	local prices = ns:GetModule("Prices")
	local st = prices:GetStatus()
	self.header:SetText("Status")
	self.statusText:Show()
	local lines = {
		"TSM API: " .. (st.tsm and "|cff33ff99yes|r" or "|cffff5555no|r"),
		"AuctionDB: " .. (st.hasData and "|cff33ff99ok|r" or "|cffff5555missing/stale|r"),
		st.detail or "",
		"",
		"Posting uses deposit + duration in the cutoff.",
		"AH tab: GoldPulse next to Auctionator / TSM.",
		"",
		"/gp post — start auto-post at AH",
		"/gp post stop | queue",
		"/gp scan | config | lock | unlock",
	}
	self.statusText:SetText(table.concat(lines, "\n"))
end

function UI:Refresh(rescan)
	if not self.frame then return end
	if not ns.db or not ns.db.enabled then
		self.status:SetText("disabled")
		return
	end

	local prices = ns:GetModule("Prices")
	local st = prices:GetStatus()
	if not st.tsm then
		self.status:SetText("no TSM")
	elseif not st.hasData then
		self.status:SetText("no AuctionDB")
	else
		self.status:SetText("ready")
	end

	if rescan then
		local bags = ns:GetModule("Bags")
		local flips = ns:GetModule("Flips")
		local posting = ns:GetModule("Posting")
		if self.tab == "bags" and bags then bags:Scan() end
		if self.tab == "flips" and flips then flips:Scan() end
		if self.tab == "post" and posting then posting:BuildQueue() end
	end

	if self.tab == "bags" then
		self:ShowBagRows()
	elseif self.tab == "flips" then
		self:ShowFlipRows()
	elseif self.tab == "post" then
		self:ShowPostRows()
	else
		self:ShowStatus()
	end
end

function UI:Toggle()
	if not self.frame then return end
	if self.frame:IsShown() then
		self:Hide()
	else
		self:Show()
	end
end

function UI:Show()
	if not self.frame or not ns.db then return end
	if not ns.db.enabled then
		ns:Print("disabled — /gp config or enable in settings")
		return
	end
	self.frame:Show()
	self:Refresh(true)
end

function UI:Hide()
	if self.frame then self.frame:Hide() end
end

function UI:OnAuctionHouseShow()
	if self.frame and self.frame:IsShown() then
		self.tab = "post"
		self:Refresh(true)
	end
end

function UI:OnAuctionHouseClosed()
	if self.frame and self.frame:IsShown() and self.tab == "flips" then
		self:Refresh(false)
	end
end

function UI:SavePosition()
	if not self.frame or not ns.db then return end
	local point, _, relativePoint, x, y = self.frame:GetPoint(1)
	if not point then return end
	ns.db.position = {
		point = point,
		relativePoint = relativePoint or point,
		x = x or 0,
		y = y or 0,
	}
end

function UI:ApplyPosition()
	if not self.frame then return end
	local pos = ns.db and ns.db.position or ns:DefaultPosition()
	self.frame:ClearAllPoints()
	self.frame:SetPoint(pos.point or "CENTER", UIParent, pos.relativePoint or "CENTER", pos.x or 0, pos.y or 120)
end

function UI:ApplyScale()
	if self.frame and ns.db and ns.db.scale then
		self.frame:SetScale(ns.db.scale)
	end
end

function UI:ApplyLock()
	if not self.frame or not ns.db then return end
	self.frame:EnableMouse(true) -- always receive clicks; drag gated in OnDragStart
end
