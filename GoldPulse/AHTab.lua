local addonName, ns = ...

local AHTab = ns:NewModule("AHTab")

AHTab.tab = nil
AHTab.content = nil
AHTab.selected = false

local ROW_H = 18
local VISIBLE = 12
local GOLD = { 0.94, 0.78, 0.38 }
local IVORY = { 0.96, 0.95, 0.91 }
local MUTED = { 0.70, 0.68, 0.64 }
local READY = { 0.45, 0.90, 0.40 }

local function SafeHide(name)
	local f = _G[name]
	if f and f.Hide then f:Hide() end
end

local function HideLegacyAHPages()
	SafeHide("AuctionFrameBrowse")
	SafeHide("AuctionFrameBid")
	SafeHide("AuctionFrameAuctions")
end

--- Rightmost Blizzard/addon AH tab button (AuctionFrameTab1..N).
local function FindLastAuctionTab()
	local last, lastId = nil, 0
	for i = 1, 32 do
		local t = _G["AuctionFrameTab" .. i]
		if t and t.IsObjectType and t:IsObjectType("Button") then
			last, lastId = t, i
		end
	end
	return last, lastId
end

local function NukeBrokenFrames()
	-- Previous 1.0.5 attempt could leave a stretched tab / content frame.
	for _, name in ipairs({ "GoldPulseAHContent", "GoldPulseAHTab", "GoldPulseAHTabButton" }) do
		local f = _G[name]
		if f then
			f:Hide()
			f:SetParent(nil)
			f:ClearAllPoints()
			f:SetSize(1, 1)
			_G[name] = nil
		end
	end
	-- Orphan AuctionFrameTab* named GoldPulse from prior build.
	for i = 1, 32 do
		local t = _G["AuctionFrameTab" .. i]
		if t and t.GetText and t:GetText() == "GoldPulse" then
			t:Hide()
			t:SetParent(nil)
			t:ClearAllPoints()
			t:SetSize(1, 1)
			_G["AuctionFrameTab" .. i] = nil
		end
	end
end

function AHTab:BuildContent(parent)
	if self.content then return self.content end

	local content = CreateFrame("Frame", "GoldPulseAHContent", parent)
	content:Hide()
	content:SetFrameStrata("DIALOG")
	content:SetFrameLevel((parent.GetFrameLevel and parent:GetFrameLevel() or 0) + 20)
	content:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, -74)
	content:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -10, 40)

	local bg = content:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0.06, 0.06, 0.07, 0.96)

	local title = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 12, -10)
	title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
	title:SetText("GoldPulse")

	local status = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	status:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
	status:SetPoint("RIGHT", content, "RIGHT", -200, 0)
	status:SetJustifyH("LEFT")
	status:SetTextColor(MUTED[1], MUTED[2], MUTED[3])

	local postBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
	postBtn:SetSize(90, 22)
	postBtn:SetPoint("TOPRIGHT", -12, -10)
	postBtn:SetText("AutoPost")
	postBtn:SetScript("OnClick", function()
		local posting = ns:GetModule("Posting")
		if not posting then return end
		if posting.running then
			posting:StopAuto("ah-tab")
		else
			posting:StartAuto()
		end
		self:Refresh()
	end)

	local scanBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
	scanBtn:SetSize(70, 22)
	scanBtn:SetPoint("RIGHT", postBtn, "LEFT", -4, 0)
	scanBtn:SetText("Refresh")
	scanBtn:SetScript("OnClick", function()
		local posting = ns:GetModule("Posting")
		if posting then posting:BuildQueue() end
		self:Refresh()
	end)

	local panelBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
	panelBtn:SetSize(70, 22)
	panelBtn:SetPoint("RIGHT", scanBtn, "LEFT", -4, 0)
	panelBtn:SetText("Panel")
	panelBtn:SetScript("OnClick", function()
		local ui = ns:GetModule("UI")
		if ui then
			ui.tab = "post"
			ui:Show()
		end
	end)

	local header = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	header:SetPoint("TOPLEFT", 12, -52)
	header:SetPoint("RIGHT", content, "RIGHT", -12, 0)
	header:SetJustifyH("LEFT")
	header:SetTextColor(MUTED[1], MUTED[2], MUTED[3])
	header:SetText("Post queue")

	local rows = {}
	for i = 1, VISIBLE do
		local row = CreateFrame("Frame", nil, content)
		row:SetHeight(ROW_H)
		row:SetPoint("TOPLEFT", 12, -70 - (i - 1) * ROW_H)
		row:SetPoint("TOPRIGHT", -12, -70 - (i - 1) * ROW_H)

		local tag = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		tag:SetPoint("LEFT", 0, 0)
		tag:SetWidth(48)
		tag:SetJustifyH("LEFT")

		local name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		name:SetPoint("LEFT", tag, "RIGHT", 6, 0)
		name:SetPoint("RIGHT", row, "RIGHT", -140, 0)
		name:SetJustifyH("LEFT")
		name:SetWordWrap(false)

		local detail = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		detail:SetPoint("RIGHT", 0, 0)
		detail:SetJustifyH("RIGHT")
		detail:SetTextColor(MUTED[1], MUTED[2], MUTED[3])

		row.tag, row.name, row.detail = tag, name, detail
		rows[i] = row
	end

	local empty = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	empty:SetPoint("TOPLEFT", 16, -80)
	empty:SetPoint("TOPRIGHT", -16, -80)
	empty:SetJustifyH("LEFT")
	empty:SetTextColor(IVORY[1], IVORY[2], IVORY[3])
	empty:Hide()

	self.content = content
	self.status = status
	self.header = header
	self.rows = rows
	self.empty = empty
	self.postBtn = postBtn
	return content
end

function AHTab:Refresh()
	if not self.content or not self.content:IsShown() then return end
	local posting = ns:GetModule("Posting")
	local prices = ns:GetModule("Prices")
	if not posting then return end

	local list = posting:GetQueue()
	if #list == 0 then
		posting:BuildQueue()
		list = posting:GetQueue()
	end

	local run = posting.running and "RUNNING" or "idle"
	self.status:SetText(posting:DescribeLastBuild() or "")
	self.header:SetText(string.format("Post queue (%d) · %s · skip %d", #list, run, posting.skipped or 0))
	if self.postBtn then
		self.postBtn:SetText(posting.running and "Stop" or "AutoPost")
	end

	local durLabel = { [1] = "12h", [2] = "24h", [3] = "48h" }
	if #list == 0 then
		for _, row in ipairs(self.rows) do row:Hide() end
		self.empty:Show()
		self.empty:SetText("Nothing to post yet.\n" .. (posting:DescribeLastBuild() or "")
			.. "\n\nRefresh after TSM App sync, or loosen depositCover / minDeposit.")
		return
	end

	self.empty:Hide()
	for i, row in ipairs(self.rows) do
		local data = list[i]
		if not data then
			row:Hide()
		else
			row:Show()
			row.tag:SetText(string.format("x%d", data.stackSize or 1))
			row.tag:SetTextColor(READY[1], READY[2], READY[3])
			row.name:SetText(data.name or "?")
			local money = prices and prices:FormatMoney((data.buyout or 0) * (data.stackSize or 1)) or "?"
			local dep = prices and prices:FormatMoney(data.deposit or 0) or "?"
			row.detail:SetText(string.format("%s · %s · dep %s",
				durLabel[data.duration or 2] or "?", money, dep))
		end
	end
end

function AHTab:Select()
	self.selected = true
	HideLegacyAHPages()
	if self.content then self.content:Show() end
	local posting = ns:GetModule("Posting")
	if posting then posting:BuildQueue() end
	self:Refresh()
	if self.tab then
		-- Visual selected state without Blizzard PanelTemplates stretch.
		if self.tab.LockHighlight then self.tab:LockHighlight() end
	end
end

function AHTab:Deselect()
	self.selected = false
	if self.content then self.content:Hide() end
	if self.tab and self.tab.UnlockHighlight then
		self.tab:UnlockHighlight()
	end
end

function AHTab:Ensure()
	if self.tab then return true end
	if not AuctionFrame then return false end
	if InCombatLockdown and InCombatLockdown() then return false end

	NukeBrokenFrames()

	local last = FindLastAuctionTab()
	-- Fixed-size button only — never AuctionTabTemplate / CharacterFrameTab /
	-- PanelTemplates_TabResize (those stretched a red middle texture across UI).
	local tab = CreateFrame("Button", "GoldPulseAHTabButton", AuctionFrame, "UIPanelButtonTemplate")
	tab:SetSize(88, 22)
	tab:SetText("GoldPulse")
	tab:SetFrameLevel((AuctionFrame.GetFrameLevel and AuctionFrame:GetFrameLevel() or 0) + 50)

	if last then
		tab:SetPoint("LEFT", last, "RIGHT", -4, 0)
	else
		tab:SetPoint("BOTTOMLEFT", AuctionFrame, "BOTTOMLEFT", 180, -22)
	end

	tab:SetScript("OnClick", function()
		if PlaySound and SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON then
			PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		end
		if self.selected then
			-- Toggle off → back to Buy.
			self:Deselect()
			if AuctionFrameTab_OnClick and AuctionFrameTab1 then
				pcall(AuctionFrameTab_OnClick, AuctionFrameTab1, AuctionFrameTab1:GetID())
			elseif AuctionFrameTab1 and AuctionFrameTab1.Click then
				AuctionFrameTab1:Click()
			end
		else
			self:Select()
		end
	end)

	self.tab = tab
	self:BuildContent(AuctionFrame)

	if not self.hookedBrowse then
		self.hookedBrowse = true
		local function deselect()
			if self.selected then self:Deselect() end
		end
		if AuctionFrameBrowse then AuctionFrameBrowse:HookScript("OnShow", deselect) end
		if AuctionFrameBid then AuctionFrameBid:HookScript("OnShow", deselect) end
		if AuctionFrameAuctions then AuctionFrameAuctions:HookScript("OnShow", deselect) end
		if AuctionFrameTab_OnClick then
			hooksecurefunc("AuctionFrameTab_OnClick", function(tabButton)
				if tabButton ~= self.tab then deselect() end
			end)
		end
	end

	return true
end

function AHTab:OnLogin()
	NukeBrokenFrames()
	ns:On("AUCTION_HOUSE_SHOW", function()
		C_Timer.After(0.2, function()
			self:Ensure()
		end)
		-- After Auctionator/TSM finish their tabs, re-anchor to the real last tab.
		C_Timer.After(1.0, function()
			if not self.tab or not AuctionFrame then return end
			local last = FindLastAuctionTab()
			if last and last ~= self.tab then
				self.tab:ClearAllPoints()
				self.tab:SetSize(88, 22)
				self.tab:SetPoint("LEFT", last, "RIGHT", -4, 0)
			end
		end)
	end)
	ns:On("AUCTION_HOUSE_CLOSED", function()
		self:Deselect()
	end)
end
