local addonName, ns = ...

local UI = ns:NewModule("UI")

-------------------------------------------------------------------------------
-- DungeonJournal-Style Modern HUD & Food Guide for WoW: Forever (16001)
--   * Main HUD ("LevelPulseFrame"):
--       - Rounded bronze-gold UI-Tooltip-Border card + warm header strip
--       - 3-Column live telemetry (XP BONUS | SPEED / PROGRESS | NEXT LVL / RESTED)
--       - 3 Rounded visual buff pills with icons (Food · Bag · Camp)
--       - Expandable 1-Click Action Callout tray when a buff needs activation
--       - Inset smooth XP progress bar + bottom-right drag-resize corner grip
--   * Food Guide Window ("LevelPulseFoodFrame"):
--       - Authentic ForeverDungeonJournal dialog chrome (rock + DialogBox border,
--         parchment inner panel, spellbook page arrows, loot-card food rows,
--         Ctrl+C Copy Box, 1-Click Auction House search & Cooking filter)
--   * Zero combat taint: clickBtn is BOTH parented AND anchored directly to UIParent.
-------------------------------------------------------------------------------

local T = ns.UITheme
local GOLD, GOLD_BRIGHT = T.GOLD, T.GOLD_BRIGHT
local IVORY, TEXT_WARM, MUTED = T.IVORY, T.TEXT_WARM, T.MUTED
local READY, WARN, RESTED, CAMP = T.READY, T.WARN, T.RESTED, T.CAMP
local SetPixelSize = T.SetPixelSize
local SetPixelHeight = T.SetPixelHeight

local FOOD_ICON_DEFAULT = "Interface\\Icons\\INV_Misc_Food_15"
local BAG_ICON_DEFAULT  = "Interface\\Icons\\INV_Misc_Bag_CoreFelclothBag"
local CAMP_ICON_DEFAULT = "Interface\\Icons\\Spell_Fire_Fire"
local BOOK_ICON_DEFAULT = "Interface\\Icons\\INV_Misc_Book_09"

local function CanDragHUD()
	if InCombatLockdown and InCombatLockdown() then return false end
	if ns.db and not ns.db.locked then return true end
	if IsShiftKeyDown and IsShiftKeyDown() then return true end
	return false
end

local function PlayJournalSound(isPage)
	if not PlaySound then return end
	local kit = isPage
		and ((SOUNDKIT and SOUNDKIT.IG_ABILITY_PAGE_TURN) or 836)
		or ((SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) or 856)
	pcall(PlaySound, kit)
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
		ns:Print("UI error:", err)
		return
	end

	ns:On("PLAYER_REGEN_DISABLED", function()
		self.combatFlag = true
		self:Refresh()
	end)
	ns:On("PLAYER_REGEN_ENABLED", function()
		self.combatFlag = false
		self:Refresh()
	end)
	ns:On("UNIT_AURA", function(_, unit)
		if unit == "player" and not (InCombatLockdown and InCombatLockdown()) then
			self:Refresh()
		end
	end)
	ns:On("BAG_UPDATE", function()
		if not (InCombatLockdown and InCombatLockdown()) then self:Refresh() end
	end)
	ns:On("PLAYER_XP_UPDATE", function() self:Refresh() end)
	ns:On("PLAYER_LEVEL_UP", function() self:Refresh() end)
	ns:On("UPDATE_EXHAUSTION", function() self:Refresh() end)
	ns:On("PLAYER_UPDATE_RESTING", function() self:Refresh() end)
	ns:On("PLAYER_MOUNT_DISPLAY_CHANGED", function() self:Refresh() end)
	ns:On("PLAYER_ENTERING_WORLD", function() self:Refresh() end)

	self:Refresh()
end

-------------------------------------------------------------------------------
-- Rich Status Tooltip
-------------------------------------------------------------------------------
function UI:ShowStatusTooltip(anchorFrame)
	if not GameTooltip then return end
	local scanner = ns:GetModule("Scanner")
	local tel = ns:GetModule("Telemetry")
	local adv = ns:GetModule("Advisor")
	if not scanner or not tel or not adv then return end

	local a = scanner.auras
	local Fmt = T.FmtDuration
	local bonusPct = scanner:GetActiveXPBonusPercent()

	GameTooltip:SetOwner(anchorFrame or self.frame, "ANCHOR_BOTTOM")
	GameTooltip:AddLine(string.format("LevelPulse  |cff6be86b+%d%% XP Bonus|r", bonusPct), GOLD[1], GOLD[2], GOLD[3])

	local pauseTag = adv:GetPauseTag()
	if pauseTag == "IN INN" then
		GameTooltip:AddLine("Smart Filter: Paused in Inn/City (step outside for 1-Click prompts)", RESTED[1], RESTED[2], RESTED[3])
	elseif pauseTag == "MOUNTED" then
		GameTooltip:AddLine("Smart Filter: Paused while Mounted (dismount to use XP items)", WARN[1], WARN[2], WARN[3])
	elseif pauseTag == "FLIGHT" then
		GameTooltip:AddLine("Smart Filter: Paused on Flight Path", MUTED[1], MUTED[2], MUTED[3])
	end

	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("XP Buff Checklist:", GOLD[1], GOLD[2], GOLD[3])

	local food = scanner:GetSelectedFood()
	if a.wellFed then
		GameTooltip:AddLine(string.format("  |cff6be86b[ACTIVE]|r %s (+%d%% Kill XP) — %s left",
			a.wellFedName or "Well Fed", a.wellFedXP > 0 and a.wellFedXP or 5, Fmt(a.wellFedRemaining)), 1, 1, 1)
	elseif food then
		GameTooltip:AddLine(string.format("  |cffffb038[READY]|r Well Fed (+5%% Kill XP) — %s (x%d in bags)",
			food.name, food.count), 1, 1, 1)
	elseif (scanner.items.plainFoodCount or 0) > 0 then
		GameTooltip:AddLine("  |cffff6666[MISSING]|r Well Fed (+5% XP) — Only plain food in bags (cook any recipe!)", 0.9, 0.9, 0.9)
	else
		GameTooltip:AddLine("  |cff9a9284[MISSING]|r Well Fed (+5% XP) — 0 cooked XP food in bags", 0.85, 0.85, 0.85)
	end

	if a.wellRested then
		GameTooltip:AddLine(string.format("  |cff6be86b[ACTIVE]|r %s (+%d%% XP, %d/3) — %s left",
			a.wellRestedName or "Well-Rested", math.min(3, a.wellRestedStacks or 1), a.wellRestedStacks or 1, Fmt(a.wellRestedRemaining)), 1, 1, 1)
	elseif scanner.items.sleepingBag then
		GameTooltip:AddLine("  |cffffb038[READY]|r Cozy Sleeping Bag (+3% XP, 2h) — Ready in bags", 1, 1, 1)
	else
		GameTooltip:AddLine("  |cff9a9284[NONE]|r Cozy Sleeping Bag (+3% XP) — Item not in bags", 0.78, 0.78, 0.78)
	end

	if a.campBuff then
		GameTooltip:AddLine(string.format("  |cff6be86b[ACTIVE]|r Camp Buff (%s) — %s left",
			a.campBuffName or "Camp Benefits", Fmt(a.campBuffRemaining)), 1, 1, 1)
	elseif a.campfireNearby then
		GameTooltip:AddLine("  |cffff9944[NEARBY]|r Campfire Nearby! Sit 60s for 1h Camp Buffs", 1, 1, 1)
	elseif scanner.campfireSpell then
		GameTooltip:AddLine(string.format("  |cffffb038[READY]|r %s — Ready to place outdoors", scanner.campfireSpell.name), 1, 1, 1)
	else
		GameTooltip:AddLine("  |cff9a9284[NONE]|r Campfire Buff (1h Stats / Rested Tent) — Not active", 0.78, 0.78, 0.78)
	end

	if a.extraXPBonus and a.extraXPBonus > 0 then
		GameTooltip:AddLine(string.format("  |cff6be86b[BONUS]|r %s (+%d%% XP)", a.extraXPName or "Extra Buff", a.extraXPBonus), 1, 1, 1)
	end

	local fg = ns:GetModule("FoodGuide")
	if fg and fg.GetRecommendations then
		local rec = fg:GetRecommendations(tel.level, 3)
		if rec and rec.picks and #rec.picks > 0 then
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine(string.format("Recommended Food (%s):", rec.bracketTitle), GOLD[1], GOLD[2], GOLD[3])
			for _, p in ipairs(rec.picks) do
				local bagBadge = (p.inBags and p.inBags > 0) and string.format(" |cff6be86b(x%d in bags)|r", p.inBags) or ""
				GameTooltip:AddLine(string.format("  • |cfff5f0e6%s|r [Cook %d] — %s%s",
					p.name, p.skill, p.stats, bagBadge), 0.88, 0.84, 0.76)
			end
			if rec.nextPreview then
				GameTooltip:AddLine(string.format("  Next tier at Lvl %d: %s (%s)",
					rec.nextPreview.unlockLevel, rec.nextPreview.topFood, rec.nextPreview.topStats), MUTED[1], MUTED[2], MUTED[3])
			end
		end
	end

	GameTooltip:AddLine(" ")
	local progPct = math.floor(tel:GetXPProgress() * 100 + 0.5)
	local xph = tel:GetXPPerHour()
	local eta = tel:GetETASeconds()
	GameTooltip:AddLine(string.format("Level %d Progress: %d / %d XP (%d%%) • Rested: %d%%",
		tel.level or 1, tel.xp or 0, tel.maxXP or 1, progPct, tel:GetRestedPercent()), RESTED[1], RESTED[2], RESTED[3])
	if xph > 0 then
		GameTooltip:AddLine(string.format("Session Speed: %d XP/hr%s",
			xph, eta and (" • Next level in ~" .. Fmt(eta)) or ""), IVORY[1], IVORY[2], IVORY[3])
	else
		GameTooltip:AddLine("Session Speed: Gain XP to calculate XP/hr & ETA", MUTED[1], MUTED[2], MUTED[3])
	end

	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("Click Book / Bar: Food Guide (Copy / AH / Cooking)", 0.42, 0.94, 0.42)
	GameTooltip:AddLine("Shift+Drag: Move  •  Corner Grip: Resize  •  Right-Click: Options", 0.72, 0.67, 0.58)
	GameTooltip:Show()
end

-------------------------------------------------------------------------------
-- DungeonJournal-Styled Interactive Food Guide Window ("LevelPulseFoodFrame")
-------------------------------------------------------------------------------
function UI:BuildFoodDrawer(parentFrame)
	local W = T.DRAWER_W
	local drawer = CreateFrame("Frame", "LevelPulseFoodFrame", UIParent, "BackdropTemplate")
	SetPixelSize(drawer, W, 326)
	T.ApplyJournalWindowBackdrop(drawer)
	drawer:SetFrameStrata("DIALOG")
	drawer:SetClampedToScreen(true)
	drawer:SetMovable(true)
	drawer:EnableMouse(true)
	drawer:RegisterForDrag("LeftButton")
	drawer:SetScript("OnDragStart", function(d)
		d.userMoved = true
		d:StartMoving()
	end)
	drawer:SetScript("OnDragStop", function(d)
		d:StopMovingOrSizing()
	end)
	drawer:Hide()

	if UISpecialFrames then
		table.insert(UISpecialFrames, "LevelPulseFoodFrame")
	end

	-- Top Header Strip (matches ForeverDungeonJournalFrame.topStrip)
	local topStrip = drawer:CreateTexture(nil, "BACKGROUND")
	topStrip:SetTexture(T.SOLID)
	topStrip:SetColorTexture(T.BG_HEADER[1], T.BG_HEADER[2], T.BG_HEADER[3], T.BG_HEADER[4])
	topStrip:SetPoint("TOPLEFT", 10, -9)
	topStrip:SetPoint("TOPRIGHT", -10, -9)
	SetPixelHeight(topStrip, 30)

	local topLine = drawer:CreateTexture(nil, "ARTWORK")
	topLine:SetTexture(T.SOLID)
	topLine:SetPoint("TOPLEFT", topStrip, "TOPLEFT", 0, 0)
	topLine:SetPoint("TOPRIGHT", topStrip, "TOPRIGHT", 0, 0)
	SetPixelHeight(topLine, 1)
	topLine:SetColorTexture(T.GOLD_LINE[1], T.GOLD_LINE[2], T.GOLD_LINE[3], 0.65)

	local botLine = drawer:CreateTexture(nil, "ARTWORK")
	botLine:SetTexture(T.SOLID)
	botLine:SetPoint("BOTTOMLEFT", topStrip, "BOTTOMLEFT", 0, 0)
	botLine:SetPoint("BOTTOMRIGHT", topStrip, "BOTTOMRIGHT", 0, 0)
	SetPixelHeight(botLine, 1)
	botLine:SetColorTexture(T.GOLD_LINE[1], T.GOLD_LINE[2], T.GOLD_LINE[3], 0.45)

	local hdrIcon = drawer:CreateTexture(nil, "ARTWORK")
	hdrIcon:SetTexture(BOOK_ICON_DEFAULT)
	hdrIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	SetPixelSize(hdrIcon, 18, 18)
	hdrIcon:SetPoint("LEFT", topStrip, "LEFT", 10, 0)

	local hdrTitle = T.MakeFontString(drawer, "OVERLAY", "Header", "GameFontNormal")
	hdrTitle:SetPoint("LEFT", hdrIcon, "RIGHT", 7, 0)
	hdrTitle:SetText("Well Fed Food Guide")
	hdrTitle:SetTextColor(0.96, 0.79, 0.25)

	local okClose, closeBtn = pcall(CreateFrame, "Button", "LevelPulseFoodFrameCloseButton", drawer, "UIPanelCloseButton")
	if not okClose or not closeBtn then
		closeBtn = CreateFrame("Button", nil, drawer)
		local ct = T.MakeFontString(closeBtn, "OVERLAY", "Body", "GameFontNormalSmall")
		ct:SetPoint("CENTER")
		ct:SetText("X")
	end
	SetPixelSize(closeBtn, 24, 24)
	closeBtn:SetPoint("TOPRIGHT", drawer, "TOPRIGHT", -3, -3)
	closeBtn:SetScript("OnClick", function()
		PlayJournalSound(false)
		drawer:Hide()
	end)

	-- Bracket Selector Bar with Blizzard Spellbook Page Arrows
	local tierBtn = CreateFrame("Button", nil, drawer, "BackdropTemplate")
	SetPixelSize(tierBtn, W - 96, 24)
	tierBtn:SetPoint("TOP", topStrip, "BOTTOM", 0, -6)
	T.ApplyPillBackdrop(tierBtn, 12, 3)
	tierBtn:SetBackdropColor(0.12, 0.115, 0.105, 0.98)
	tierBtn:SetBackdropBorderColor(T.BORDER[1], T.BORDER[2], T.BORDER[3], 1)
	if tierBtn.SetHighlightTexture then
		tierBtn:SetHighlightTexture(T.QUEST_HL, "ADD")
	end

	local tierTxt = T.MakeFontString(tierBtn, "OVERLAY", "Body", "GameFontHighlightSmall")
	tierTxt:SetPoint("CENTER", 0, 0)
	tierTxt:SetTextColor(1.00, 0.82, 0.27)

	tierBtn:SetScript("OnClick", function()
		PlayJournalSound(true)
		self.drawerBracketOverride = nil
		self:RefreshFoodDrawer()
	end)

	local prevBtn = CreateFrame("Button", nil, drawer)
	SetPixelSize(prevBtn, 24, 24)
	prevBtn:SetPoint("RIGHT", tierBtn, "LEFT", -4, 0)
	T.StylePageArrow(prevBtn, true)
	prevBtn:SetScript("OnClick", function()
		local fg = ns:GetModule("FoodGuide")
		if not fg then return end
		PlayJournalSound(true)
		local cur = self.drawerBracketOverride or fg:GetRecommendations().bracketID
		self.drawerBracketOverride = math.max(1, cur - 1)
		self:RefreshFoodDrawer()
	end)

	local nextBtn = CreateFrame("Button", nil, drawer)
	SetPixelSize(nextBtn, 24, 24)
	nextBtn:SetPoint("LEFT", tierBtn, "RIGHT", 4, 0)
	T.StylePageArrow(nextBtn, false)
	nextBtn:SetScript("OnClick", function()
		local fg = ns:GetModule("FoodGuide")
		if not fg then return end
		PlayJournalSound(true)
		local cur = self.drawerBracketOverride or fg:GetRecommendations().bracketID
		self.drawerBracketOverride = math.min(fg:GetBracketCount(), cur + 1)
		self:RefreshFoodDrawer()
	end)

	-- Inner Parchment Content Well (matches ForeverDungeonJournal.homePanel)
	local bodyWell = CreateFrame("Frame", nil, drawer, "BackdropTemplate")
	bodyWell:SetPoint("TOPLEFT", drawer, "TOPLEFT", 12, -74)
	bodyWell:SetPoint("BOTTOMRIGHT", drawer, "BOTTOMRIGHT", -12, 54)
	T.ApplyPillBackdrop(bodyWell, 14, 4)
	bodyWell:SetBackdropColor(T.BG_PARCHMENT[1], T.BG_PARCHMENT[2], T.BG_PARCHMENT[3], T.BG_PARCHMENT[4])
	bodyWell:SetBackdropBorderColor(0.47, 0.34, 0.16, 1)
	T.AddParchmentOverlay(bodyWell, 0.16)

	-- Loot-Card Style Food Rows (5 slots, modeled after MakeLootRow)
	local rows = {}
	for i = 1, 5 do
		local row = CreateFrame("Button", nil, bodyWell, "BackdropTemplate")
		SetPixelHeight(row, 38)
		row:SetPoint("TOPLEFT", bodyWell, "TOPLEFT", 7, -7 - ((i - 1) * 41))
		row:SetPoint("TOPRIGHT", bodyWell, "TOPRIGHT", -7, -7 - ((i - 1) * 41))
		row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		T.ApplyPillBackdrop(row, 10, 2)
		row:SetBackdropColor(T.BG_ROW[1], T.BG_ROW[2], T.BG_ROW[3], T.BG_ROW[4])
		row:SetBackdropBorderColor(0.46, 0.30, 0.12, 1)

		local icBorder = row:CreateTexture(nil, "BORDER")
		SetPixelSize(icBorder, 28, 28)
		icBorder:SetPoint("LEFT", row, "LEFT", 7, 0)
		icBorder:SetColorTexture(0.58, 0.44, 0.20, 0.90)

		local ic = row:CreateTexture(nil, "ARTWORK")
		SetPixelSize(ic, 26, 26)
		ic:SetPoint("CENTER", icBorder, "CENTER", 0, 0)
		ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)

		local skillBadge = T.MakeFontString(row, "OVERLAY", "Label", "GameFontNormalSmall")
		skillBadge:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -6)
		skillBadge:SetJustifyH("RIGHT")
		skillBadge:SetTextColor(1.00, 0.82, 0.27)

		local nameTxt = T.MakeFontString(row, "OVERLAY", "Title", "GameFontNormal")
		nameTxt:SetPoint("TOPLEFT", icBorder, "TOPRIGHT", 8, -4)
		nameTxt:SetPoint("RIGHT", skillBadge, "LEFT", -6, 0)
		nameTxt:SetJustifyH("LEFT")
		nameTxt:SetWordWrap(false)

		local subTxt = T.MakeFontString(row, "OVERLAY", "Label", "GameFontHighlightSmall")
		subTxt:SetPoint("TOPLEFT", nameTxt, "BOTTOMLEFT", 0, -2)
		subTxt:SetPoint("RIGHT", row, "RIGHT", -8, 0)
		subTxt:SetJustifyH("LEFT")
		subTxt:SetWordWrap(false)
		subTxt:SetTextColor(TEXT_WARM[1], TEXT_WARM[2], TEXT_WARM[3])

		row:SetScript("OnEnter", function(r)
			r:SetBackdropColor(T.BG_ROW_HOVER[1], T.BG_ROW_HOVER[2], T.BG_ROW_HOVER[3], T.BG_ROW_HOVER[4])
			r:SetBackdropBorderColor(1.00, 0.80, 0.24, 1)
			if not r.food or not GameTooltip then return end
			GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
			if r.food.itemID and GameTooltip.SetHyperlink then
				pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. tostring(r.food.itemID))
			else
				GameTooltip:AddLine(r.food.name, GOLD[1], GOLD[2], GOLD[3])
			end
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine(string.format("Cooking %d • %s • %s", r.food.skill or 1, r.food.stats or "+5% XP", r.food.source or ""), 0.90, 0.86, 0.76)
			GameTooltip:AddLine("Click: Select name to Copy (Ctrl+C) or Search open AH / Cooking", 0.42, 0.94, 0.42)
			GameTooltip:AddLine("Shift-Click: Link to Auction House / Cooking / Chat", GOLD[1], GOLD[2], GOLD[3])
			GameTooltip:Show()
		end)
		row:SetScript("OnLeave", function(r)
			r:SetBackdropColor(T.BG_ROW[1], T.BG_ROW[2], T.BG_ROW[3], T.BG_ROW[4])
			r:SetBackdropBorderColor(0.46, 0.30, 0.12, 1)
			if GameTooltip then GameTooltip:Hide() end
		end)
		row:SetScript("OnClick", function(r)
			if not r.food then return end
			PlayJournalSound(false)
			self:OnFoodRowClick(r.food, IsShiftKeyDown and IsShiftKeyDown() or false)
		end)

		row.icon = ic
		row.nameTxt = nameTxt
		row.metaTxt = skillBadge
		row.subTxt = subTxt
		rows[i] = row
	end

	-- Bottom Copy Box + Action Hint
	local copyBox = CreateFrame("EditBox", nil, drawer, "BackdropTemplate")
	SetPixelHeight(copyBox, 24)
	copyBox:SetPoint("BOTTOMLEFT", drawer, "BOTTOMLEFT", 12, 24)
	copyBox:SetPoint("BOTTOMRIGHT", drawer, "BOTTOMRIGHT", -12, 24)
	T.ApplyPillBackdrop(copyBox, 10, 3)
	copyBox:SetBackdropColor(0.03, 0.03, 0.04, 0.98)
	copyBox:SetBackdropBorderColor(T.BORDER[1], T.BORDER[2], T.BORDER[3], 1)
	if copyBox.SetAutoFocus then copyBox:SetAutoFocus(false) end
	if copyBox.SetFontObject then
		pcall(copyBox.SetFontObject, copyBox, (T.Fonts and T.Fonts.Body) or "ChatFontNormal")
	end
	if copyBox.SetTextInsets then copyBox:SetTextInsets(8, 8, 2, 2) end
	copyBox:SetScript("OnEscapePressed", function(eb)
		if eb.ClearFocus then eb:ClearFocus() end
	end)
	copyBox:SetScript("OnEditFocusGained", function(eb)
		if eb.HighlightText then eb:HighlightText() end
	end)
	copyBox:SetScript("OnTextChanged", function(eb, userInput)
		if userInput and self.selectedCopyName and eb:GetText() ~= self.selectedCopyName then
			eb:SetText(self.selectedCopyName)
			if eb.HighlightText then eb:HighlightText() end
		end
	end)

	local hintTxt = T.MakeFontString(drawer, "OVERLAY", "Label", "GameFontNormalSmall")
	hintTxt:SetPoint("BOTTOMLEFT", drawer, "BOTTOMLEFT", 14, 9)
	hintTxt:SetPoint("BOTTOMRIGHT", drawer, "BOTTOMRIGHT", -14, 9)
	hintTxt:SetJustifyH("LEFT")
	hintTxt:SetWordWrap(false)
	hintTxt:SetTextColor(MUTED[1], MUTED[2], MUTED[3])
	hintTxt:SetText("Click card: Ctrl+C or Search AH / Cooking • Shift-Click: Link")

	self.foodDrawer = drawer
	self.drawerBodyWell = bodyWell
	self.drawerTierTxt = tierTxt
	self.drawerRows = rows
	self.drawerCopyBox = copyBox
	self.drawerHintTxt = hintTxt
	self.parentForDrawer = parentFrame
end

function UI:AnchorFoodDrawer()
	if not self.foodDrawer or not self.frame then return end
	if self.foodDrawer.userMoved then return end
	self.foodDrawer:ClearAllPoints()
	local cy = self.frame.GetCenter and select(2, self.frame:GetCenter()) or nil
	if cy and cy < 320 then
		self.foodDrawer:SetPoint("BOTTOM", self.frame, "TOP", 0, 6)
	else
		self.foodDrawer:SetPoint("TOP", self.frame, "BOTTOM", 0, -6)
	end
end

function UI:OnFoodRowClick(food, isShiftClick)
	if not food then return end
	self.selectedCopyName = food.name
	if self.drawerCopyBox then
		self.drawerCopyBox:SetText(food.name)
	end

	local fg = ns:GetModule("FoodGuide")
	local target = fg and fg:TrySendToActiveUI(food, isShiftClick) or nil

	if target == "ah" then
		if self.drawerHintTxt then
			self.drawerHintTxt:SetText("|cff6be86bSearching Auction House:|r " .. food.name)
		end
	elseif target == "cooking" then
		if self.drawerHintTxt then
			self.drawerHintTxt:SetText("|cff6be86bFiltered in Cooking:|r " .. food.name)
		end
	elseif target == "chat" then
		if self.drawerHintTxt then
			self.drawerHintTxt:SetText("|cff6be86bLinked in Chat:|r " .. food.name)
		end
	else
		if self.drawerCopyBox then
			if self.drawerCopyBox.SetFocus then self.drawerCopyBox:SetFocus() end
			if self.drawerCopyBox.HighlightText then self.drawerCopyBox:HighlightText() end
		end
		if self.drawerHintTxt then
			self.drawerHintTxt:SetText("|cffffc933Selected! Press Ctrl+C|r (or open AH / Cooking & click again)")
		end
	end
end

function UI:ResetFoodDrawerToAuto()
	self.drawerBracketOverride = nil
	if self.foodDrawer and self.foodDrawer:IsShown() then
		self:RefreshFoodDrawer()
	end
end

function UI:RefreshFoodDrawer()
	if not self.foodDrawer then return end
	local fg = ns:GetModule("FoodGuide")
	local tel = ns:GetModule("Telemetry")
	if not fg then return end

	local rec = fg:GetRecommendations(tel and tel.level or 1, 5, self.drawerBracketOverride)
	local modeTag = self.drawerBracketOverride and " • Manual (click for Auto)" or string.format(" • Auto (%s Lvl %d)", rec.className, rec.level)
	self.drawerTierTxt:SetText((rec.shortTitle or rec.bracketTitle) .. modeTag)

	local shownCount = 0
	for i = 1, 5 do
		local row = self.drawerRows[i]
		local p = rec.picks[i]
		if p then
			shownCount = shownCount + 1
			row.food = p
			row.icon:SetTexture(p.icon or FOOD_ICON_DEFAULT)
			local bagBadge = (p.inBags and p.inBags > 0) and string.format(" |cff6be86b(x%d)|r", p.inBags) or ""
			row.nameTxt:SetText((p.link or ("|cffffd100" .. p.name .. "|r")) .. bagBadge)
			row.metaTxt:SetText(string.format("Cook %d", p.skill or 1))
			row.subTxt:SetText(string.format("%s  •  %s", p.stats or "+5% XP", p.source or ""))
			row:Show()
		else
			row.food = nil
			row:Hide()
		end
	end

	local wellH = 14 + (shownCount * 41) - 3
	SetPixelSize(self.foodDrawer, T.DRAWER_W, 74 + wellH + 56)
	if not self.selectedCopyName and rec.picks[1] then
		self.selectedCopyName = rec.picks[1].name
		self.drawerCopyBox:SetText(rec.picks[1].name)
	end
	self:AnchorFoodDrawer()
end

function UI:ToggleFoodDrawer(forceOpen)
	if InCombatLockdown and InCombatLockdown() then return end
	if not self.foodDrawer then return end
	local show = (forceOpen == true) or (not self.foodDrawer:IsShown())
	if show then
		self.foodDrawer.userMoved = false
		self:RefreshFoodDrawer()
		self.foodDrawer:Show()
	else
		self.foodDrawer:Hide()
	end
end

-------------------------------------------------------------------------------
-- Main Modern HUD Card ("LevelPulseFrame" — DungeonJournal RunTracker Style)
-------------------------------------------------------------------------------
local function CreateSlotPill(parent, width, defaultIcon)
	local pill = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	SetPixelSize(pill, width, 24)
	T.ApplyPillBackdrop(pill, 9, 2)

	local ic = pill:CreateTexture(nil, "ARTWORK")
	SetPixelSize(ic, 14, 14)
	ic:SetPoint("LEFT", pill, "LEFT", 5, 0)
	ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	ic:SetTexture(defaultIcon)

	local txt = T.MakeFontString(pill, "OVERLAY", "Small", "GameFontHighlightSmall")
	txt:SetPoint("LEFT", ic, "RIGHT", 4, 0)
	txt:SetPoint("RIGHT", pill, "RIGHT", -4, 0)
	txt:SetJustifyH("LEFT")
	txt:SetWordWrap(false)

	pill.icon = ic
	pill.text = txt
	return pill
end

function UI:Build()
	local W = T.PILL_W
	local frame = CreateFrame("Frame", "LevelPulseFrame", UIParent, "BackdropTemplate")
	SetPixelSize(frame, W, T.PILL_H)
	T.ApplyTrackerBackdrop(frame)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetClampedToScreen(true)
	frame:SetFrameStrata("MEDIUM")

	frame:SetScript("OnDragStart", function(f)
		if CanDragHUD() then
			self.isDragging = true
			f:StartMoving()
		end
	end)
	frame:SetScript("OnDragStop", function(f)
		self.isDragging = false
		f:StopMovingOrSizing()
		self:SavePosition()
		self:AnchorClickButton()
		self:AnchorFoodDrawer()
	end)
	frame:SetScript("OnEnter", function(f)
		self:ShowStatusTooltip(f)
	end)
	frame:SetScript("OnLeave", function()
		if GameTooltip then GameTooltip:Hide() end
	end)
	frame:SetScript("OnMouseUp", function(_, mouseButton)
		if self.isDragging then return end
		if mouseButton == "RightButton" then
			if ns.OpenOptions then ns:OpenOptions() end
		elseif mouseButton == "LeftButton" and not (IsShiftKeyDown and IsShiftKeyDown()) then
			if not ns.db or ns.db.locked ~= false then
				PlayJournalSound(false)
				if GameTooltip then GameTooltip:Hide() end
				self:ToggleFoodDrawer()
			end
		end
	end)

	-- 1. Warm Header Strip + Gold Hairline Divider (DungeonJournal signature)
	local headerBg = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
	headerBg:SetTexture(T.SOLID)
	headerBg:SetColorTexture(T.BG_HEADER[1], T.BG_HEADER[2], T.BG_HEADER[3], 0.88)
	headerBg:SetPoint("TOPLEFT", 4, -4)
	headerBg:SetPoint("TOPRIGHT", -4, -4)
	SetPixelHeight(headerBg, 22)

	local headerLine = frame:CreateTexture(nil, "ARTWORK", nil, 2)
	headerLine:SetTexture(T.SOLID)
	headerLine:SetColorTexture(0.54, 0.39, 0.17, 0.60)
	headerLine:SetPoint("TOPLEFT", 6, -26)
	headerLine:SetPoint("TOPRIGHT", -6, -26)
	SetPixelHeight(headerLine, 1)

	local logo = frame:CreateTexture(nil, "ARTWORK", nil, 3)
	logo:SetTexture(FOOD_ICON_DEFAULT)
	logo:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	SetPixelSize(logo, 15, 15)
	logo:SetPoint("TOPLEFT", 9, -7)

	local headerTitle = T.MakeFontString(frame, "OVERLAY", "Title", "GameFontNormal")
	headerTitle:SetPoint("LEFT", logo, "RIGHT", 5, 0)
	headerTitle:SetText("LevelPulse")
	headerTitle:SetTextColor(GOLD[1], GOLD[2], GOLD[3])

	-- Native Square Food Guide Button in top-right (just like RunTracker's square LFG/Reset button!)
	local guideBtn = CreateFrame("Button", nil, frame)
	SetPixelSize(guideBtn, 22, 22)
	guideBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, -4)
	guideBtn:SetFrameLevel((frame:GetFrameLevel() or 5) + 4)
	if guideBtn.SetNormalTexture then guideBtn:SetNormalTexture("Interface\\Buttons\\UI-SquareButton-Up") end
	if guideBtn.SetPushedTexture then guideBtn:SetPushedTexture("Interface\\Buttons\\UI-SquareButton-Down") end
	if guideBtn.SetHighlightTexture then guideBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD") end
	local guideIcon = guideBtn:CreateTexture(nil, "ARTWORK", nil, 5)
	guideIcon:SetTexture(BOOK_ICON_DEFAULT)
	guideIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	SetPixelSize(guideIcon, 12, 12)
	guideIcon:SetPoint("CENTER", 0, 0)
	guideBtn:SetScript("OnEnter", function(b)
		if not GameTooltip then return end
		GameTooltip:SetOwner(b, "ANCHOR_BOTTOM")
		GameTooltip:AddLine("Recommended Food Guide", GOLD[1], GOLD[2], GOLD[3])
		GameTooltip:AddLine("Click: Open Food List (Copy Ctrl+C, Shift-Click AH & Cooking)", 1, 1, 1)
		GameTooltip:Show()
	end)
	guideBtn:SetScript("OnLeave", function()
		if GameTooltip then GameTooltip:Hide() end
	end)
	guideBtn:SetScript("OnClick", function()
		PlayJournalSound(false)
		self:ToggleFoodDrawer()
	end)

	-- Header Status Badge ("+8% XP", "IN INN", "MOUNTED", "UNLOCKED")
	local statusChip = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	SetPixelSize(statusChip, 68, 17)
	statusChip:SetPoint("RIGHT", guideBtn, "LEFT", -3, 0)
	T.ApplyPillBackdrop(statusChip, 8, 2)
	local tagRight = T.MakeFontString(statusChip, "OVERLAY", "Label", "GameFontNormalSmall")
	tagRight:SetPoint("CENTER", 0, 0)
	tagRight:SetText("HUD")

	-- 2. Three-Column Telemetry Strip (RunTracker style: crisp muted label + bold white metric)
	local colW = math.floor((W - 20) / 3)
	local function MakeMetricCol(idx, labelText)
		local xOff = 10 + ((idx - 1) * colW)
		local lbl = T.MakeFontString(frame, "OVERLAY", "Label", "GameFontNormalSmall")
		lbl:SetPoint("TOPLEFT", frame, "TOPLEFT", xOff, -31)
		lbl:SetTextColor(MUTED[1], MUTED[2], MUTED[3])
		lbl:SetText(labelText)

		local val = T.MakeFontString(frame, "OVERLAY", "Metric", "GameFontHighlightLarge")
		val:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", 0, -2)
		val:SetTextColor(IVORY[1], IVORY[2], IVORY[3])
		return lbl, val
	end

	local col1Lbl, col1Val = MakeMetricCol(1, "XP BONUS")
	local col2Lbl, col2Val = MakeMetricCol(2, "XP / HOUR")
	local col3Lbl, col3Val = MakeMetricCol(3, "NEXT LVL")

	-- 3. Three Rounded Buff Slot Pills (Food · Bag · Camp)
	local pillGap = 4
	local pillW = math.floor((W - 18 - (pillGap * 2)) / 3)
	local foodPill = CreateSlotPill(frame, pillW, FOOD_ICON_DEFAULT)
	foodPill:SetPoint("TOPLEFT", frame, "TOPLEFT", 9, -62)

	local bagPill = CreateSlotPill(frame, pillW, BAG_ICON_DEFAULT)
	bagPill:SetPoint("LEFT", foodPill, "RIGHT", pillGap, 0)

	local campPill = CreateSlotPill(frame, pillW, CAMP_ICON_DEFAULT)
	campPill:SetPoint("LEFT", bagPill, "RIGHT", pillGap, 0)

	-- 4. Expandable 1-Click Action Callout Card (shown only when an XP buff needs clicking)
	local actionTray = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	SetPixelHeight(actionTray, 46)
	actionTray:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -90)
	actionTray:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -90)
	T.ApplyPillBackdrop(actionTray, 11, 2)
	actionTray:SetBackdropColor(T.BG_ACTION[1], T.BG_ACTION[2], T.BG_ACTION[3], T.BG_ACTION[4])
	actionTray:SetBackdropBorderColor(T.BORDER_WARN[1], T.BORDER_WARN[2], T.BORDER_WARN[3], 1)
	local traySheen = actionTray:CreateTexture(nil, "BACKGROUND", nil, 2)
	traySheen:SetAllPoints()
	traySheen:SetTexture(T.QUEST_HL)
	if traySheen.SetBlendMode then traySheen:SetBlendMode("ADD") end
	traySheen:SetAlpha(0.16)
	actionTray:Hide()

	local iconHolder = CreateFrame("Frame", nil, actionTray)
	SetPixelSize(iconHolder, T.ICON_SZ, T.ICON_SZ)
	iconHolder:SetPoint("LEFT", actionTray, "LEFT", 6, 0)
	iconHolder:Hide()

	local iconBorder = iconHolder:CreateTexture(nil, "BACKGROUND")
	iconBorder:SetPoint("TOPLEFT", -1, 1)
	iconBorder:SetPoint("BOTTOMRIGHT", 1, -1)
	iconBorder:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.95)

	local iconTex = iconHolder:CreateTexture(nil, "ARTWORK")
	iconTex:SetAllPoints()
	iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	local topLine = T.MakeFontString(actionTray, "OVERLAY", "Title", "GameFontHighlightSmall")
	topLine:SetPoint("TOPLEFT", iconHolder, "TOPRIGHT", 8, -3)
	topLine:SetPoint("RIGHT", actionTray, "RIGHT", -8, 0)
	topLine:SetJustifyH("LEFT")
	topLine:SetWordWrap(false)

	local subLine = T.MakeFontString(actionTray, "OVERLAY", "Label", "GameFontNormalSmall")
	subLine:SetPoint("TOPLEFT", topLine, "BOTTOMLEFT", 0, -3)
	subLine:SetPoint("RIGHT", actionTray, "RIGHT", -8, 0)
	subLine:SetJustifyH("LEFT")
	subLine:SetWordWrap(false)

	-- 5. Bottom Inset Smooth XP Bar + Tick Marks + Corner Resize Grip
	local xpBar = CreateFrame("StatusBar", nil, frame)
	SetPixelHeight(xpBar, 5)
	xpBar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 9, 5)
	xpBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 5)
	xpBar:SetStatusBarTexture(T.STATUSBAR_TEX)
	xpBar:SetStatusBarColor(GOLD[1], GOLD[2], GOLD[3], 0.92)
	xpBar:SetMinMaxValues(0, 1)
	xpBar:SetValue(0)

	local xpTrack = xpBar:CreateTexture(nil, "BACKGROUND")
	xpTrack:SetAllPoints()
	xpTrack:SetColorTexture(T.TRACK[1], T.TRACK[2], T.TRACK[3], T.TRACK[4])

	for _, pct in ipairs({ 0.25, 0.50, 0.75 }) do
		local tick = xpBar:CreateTexture(nil, "OVERLAY")
		SetPixelSize(tick, 1, 5)
		tick:SetPoint("LEFT", xpBar, "LEFT", (W - 25) * pct, 0)
		tick:SetColorTexture(0, 0, 0, 0.55)
	end

	-- Corner Resize Grip (identical to ForeverDungeonJournalRunTracker: drag to scale, R-Click = 100%)
	local grip = CreateFrame("Button", nil, frame)
	SetPixelSize(grip, 13, 13)
	grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
	grip:SetFrameLevel((frame:GetFrameLevel() or 5) + 10)
	if grip.SetNormalTexture then grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up") end
	if grip.SetHighlightTexture then grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight") end
	if grip.SetPushedTexture then grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down") end
	grip:RegisterForClicks("RightButtonUp")
	grip:SetScript("OnClick", function()
		if InCombatLockdown and InCombatLockdown() then return end
		if ns.db then ns.db.scale = 1.0 end
		self:ApplyScale()
		local cfg = ns:GetModule("Config")
		if cfg and cfg.Sync then cfg:Sync("scale") end
	end)
	grip:SetScript("OnMouseDown", function(_, button)
		if button ~= "LeftButton" or (InCombatLockdown and InCombatLockdown()) then return end
		if not GetCursorPosition then return end
		local startX = GetCursorPosition()
		local startScale = (ns.db and ns.db.scale) or 1.0
		grip:SetScript("OnUpdate", function()
			if InCombatLockdown and InCombatLockdown() then
				grip:SetScript("OnUpdate", nil)
				return
			end
			local curX = GetCursorPosition()
			local delta = (curX - startX) / 260
			local nextScale = math.max(0.65, math.min(1.85, math.floor((startScale + delta) * 20 + 0.5) / 20))
			if ns.db and ns.db.scale ~= nextScale then
				ns.db.scale = nextScale
				self:ApplyScale()
			end
		end)
	end)
	grip:SetScript("OnMouseUp", function()
		grip:SetScript("OnUpdate", nil)
		local cfg = ns:GetModule("Config")
		if cfg and cfg.Sync then cfg:Sync("scale") end
	end)

	self.frame = frame
	self.accent = headerLine
	self.statusChip = statusChip
	self.col1Lbl, self.col1Val = col1Lbl, col1Val
	self.col2Lbl, self.col2Val = col2Lbl, col2Val
	self.col3Lbl, self.col3Val = col3Lbl, col3Val
	self.foodPill = foodPill
	self.bagPill = bagPill
	self.campPill = campPill
	self.actionTray = actionTray
	self.iconHolder = iconHolder
	self.iconBorder = iconBorder
	self.iconTex = iconTex
	self.topLine = topLine
	self.subLine = subLine
	self.tagRight = tagRight
	self.xpBar = xpBar
	self.grip = grip

	self:BuildClickButton(frame, iconHolder)
	self:BuildFoodDrawer(frame)
	self:InitMasque()
	self:ApplyModeLayout(false)

	local accum = 0
	frame:SetScript("OnUpdate", function(_, elapsed)
		accum = accum + (elapsed or 0)
		if accum >= 0.20 then
			accum = 0
			self:Refresh()
		end
	end)

	frame:Hide()
end

-- Anchor clickBtn directly to UIParent (NEVER to frame/iconHolder!) so self.frame
-- never becomes an anchor parent of a protected frame and never taints in combat.
function UI:AnchorClickButton()
	local btn = self.clickBtn
	if not btn or (InCombatLockdown and InCombatLockdown()) then return end

	local scale = (ns.db and ns.db.scale) or 1.0
	btn:SetScale(scale)
	SetPixelSize(btn, T.ICON_SZ, T.ICON_SZ)
	btn:ClearAllPoints()

	local cx, cy
	if self.iconHolder and self.iconHolder.GetCenter then
		cx, cy = self.iconHolder:GetCenter()
	end
	if cx and cy and self.iconHolder.GetEffectiveScale and btn.GetEffectiveScale then
		local eff = self.iconHolder:GetEffectiveScale() / (btn:GetEffectiveScale() or 1)
		btn:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx * eff, cy * eff)
	else
		local pos = (ns.db and ns.db.position) or ns.DefaultPosition()
		local ox = (pos.x or 0) - (T.ACTION_W * 0.5) + 14 + (T.ICON_SZ * 0.5)
		local oy = (pos.y or -110) - 40
		btn:SetPoint(pos.point or "TOP", UIParent, pos.relativePoint or pos.point or "TOP", ox, oy)
	end
end

function UI:BuildClickButton(frame, iconHolder)
	local ok, btn = pcall(CreateFrame, "Button", "LevelPulseActionButton", UIParent, "SecureActionButtonTemplate")
	if not ok or not btn then return end
	SetPixelSize(btn, T.ICON_SZ, T.ICON_SZ)
	if frame.GetFrameStrata then btn:SetFrameStrata(frame:GetFrameStrata()) end
	btn:SetFrameLevel((iconHolder:GetFrameLevel() or 5) + 10)
	btn:RegisterForClicks("AnyDown", "AnyUp")
	btn:RegisterForDrag("LeftButton")
	btn:EnableMouse(false)

	btn:HookScript("OnDragStart", function()
		if CanDragHUD() then
			self.isDragging = true
			frame:StartMoving()
		end
	end)
	btn:HookScript("OnDragStop", function()
		self.isDragging = false
		frame:StopMovingOrSizing()
		self:SavePosition()
		self:AnchorClickButton()
		self:AnchorFoodDrawer()
	end)
	btn:HookScript("PreClick", function(_, mouseButton)
		if InCombatLockdown and InCombatLockdown() then return end
		if mouseButton == "LeftButton" and self.boundAction then
			local now = GetTime and GetTime() or 0
			if (now - (self.lastLeftClickAt or 0)) > 0.25 then
				self.lastLeftClickAt = now
				local adv = ns:GetModule("Advisor")
				if adv and adv.NoteActionClicked then
					adv:NoteActionClicked(self.boundAction)
				end
			end
		end
	end)
	btn:HookScript("PostClick", function(_, mouseButton)
		if InCombatLockdown and InCombatLockdown() then return end
		if mouseButton == "RightButton" and self.boundAction and self.boundAction.key then
			local now = GetTime and GetTime() or 0
			if (now - (self.lastSnoozeClickAt or 0)) > 0.35 then
				self.lastSnoozeClickAt = now
				local adv = ns:GetModule("Advisor")
				if adv and adv.Snooze then
					adv:Snooze(self.boundAction.key)
					self:Refresh()
				end
			end
		end
	end)
	btn:HookScript("OnEnter", function(b)
		if not self.boundAction or not GameTooltip then return end
		GameTooltip:SetOwner(b, "ANCHOR_BOTTOM")
		GameTooltip:AddLine(self.boundAction.title or "LevelPulse", GOLD[1], GOLD[2], GOLD[3])
		GameTooltip:AddLine("Left-Click Icon: Activate buff now", 0.42, 0.94, 0.42)
		local mins = (ns.db and tonumber(ns.db.snoozeMinutes)) or 15
		GameTooltip:AddLine(string.format("Right-Click Icon: Snooze reminder %dm", mins), 0.88, 0.84, 0.76)
		GameTooltip:Show()
	end)
	btn:HookScript("OnLeave", function()
		if GameTooltip then GameTooltip:Hide() end
	end)

	if RegisterStateDriver then
		pcall(RegisterStateDriver, btn, "visibility", "[combat] hide; show")
	end
	self.clickBtn = btn
	self:AnchorClickButton()
end

function UI:InitMasque()
	if not LibStub then return end
	local ok, MSQ = pcall(LibStub, "Masque", true)
	if not ok or not MSQ or type(MSQ.Group) ~= "function" then return end
	if self.iconHolder and self.iconTex then
		local okG, grp = pcall(MSQ.Group, MSQ, "LevelPulse", "Action Icon")
		if okG and grp and type(grp.AddButton) == "function" then
			pcall(grp.AddButton, grp, self.iconHolder, {
				Icon = self.iconTex,
				Normal = false,
				Highlight = false,
				Pushed = false,
			})
			self.masqued = true
		end
	end
end

function UI:ApplyModeLayout(expanded)
	if self.isExpanded == expanded then return end
	self.isExpanded = expanded

	if expanded then
		SetPixelSize(self.frame, T.ACTION_W, T.ACTION_H)
		self.actionTray:Show()
		self.iconHolder:Show()
	else
		SetPixelSize(self.frame, T.PILL_W, T.PILL_H)
		self.actionTray:Hide()
		self.iconHolder:Hide()
	end
	self:AnchorFoodDrawer()
end

function UI:UpdateSecureAction(action, visible)
	local btn = self.clickBtn
	if not btn or (InCombatLockdown and InCombatLockdown()) then return end

	local locked = (not ns.db) or (ns.db.locked ~= false)
	local actionable = locked and visible and action ~= nil
		and (action.kind == "item" or action.kind == "spell" or action.kind == "macro")

	if not actionable then
		if self.boundSig ~= nil then
			self.boundSig = nil
			self.boundAction = nil
			btn:SetAttribute("type", nil)
			btn:SetAttribute("type1", nil)
			btn:SetAttribute("type2", nil)
			btn:SetAttribute("item1", nil)
			btn:SetAttribute("spell1", nil)
			btn:SetAttribute("macrotext1", nil)
		end
		btn:EnableMouse(false)
		return
	end

	self:AnchorClickButton()

	local sig = string.format("%s:%s:%s:%s",
		tostring(action.kind),
		tostring(action.itemID or ""),
		tostring(action.spellName or ""),
		tostring(action.macrotext or ""))

	self.boundAction = action
	btn:EnableMouse(true)
	if sig == self.boundSig then return end
	self.boundSig = sig

	btn:SetAttribute("type", nil)
	btn:SetAttribute("type2", "")
	btn:SetAttribute("item1", nil)
	btn:SetAttribute("spell1", nil)
	btn:SetAttribute("macrotext1", nil)

	if action.kind == "item" and action.itemID then
		btn:SetAttribute("type1", "item")
		btn:SetAttribute("item1", "item:" .. tostring(action.itemID))
	elseif action.kind == "spell" and action.spellName then
		btn:SetAttribute("type1", "spell")
		btn:SetAttribute("spell1", action.spellName)
	elseif action.kind == "macro" and action.macrotext then
		btn:SetAttribute("type1", "macro")
		btn:SetAttribute("macrotext1", action.macrotext)
	end
end

local function StyleSlotPill(pill, state, text, iconTex)
	if not pill then return end
	if iconTex then pill.icon:SetTexture(iconTex) end
	pill.text:SetText(text)
	if state == "active" then
		pill:SetBackdropColor(T.BG_PILL_OK[1], T.BG_PILL_OK[2], T.BG_PILL_OK[3], T.BG_PILL_OK[4])
		pill:SetBackdropBorderColor(T.BORDER_READY[1], T.BORDER_READY[2], T.BORDER_READY[3], 1)
		pill.text:SetTextColor(READY[1], READY[2], READY[3])
	elseif state == "ready" then
		pill:SetBackdropColor(T.BG_PILL_WARN[1], T.BG_PILL_WARN[2], T.BG_PILL_WARN[3], T.BG_PILL_WARN[4])
		pill:SetBackdropBorderColor(T.BORDER_WARN[1], T.BORDER_WARN[2], T.BORDER_WARN[3], 1)
		pill.text:SetTextColor(GOLD_BRIGHT[1], GOLD_BRIGHT[2], GOLD_BRIGHT[3])
	elseif state == "camp" then
		pill:SetBackdropColor(T.BG_PILL_WARN[1], T.BG_PILL_WARN[2], T.BG_PILL_WARN[3], T.BG_PILL_WARN[4])
		pill:SetBackdropBorderColor(T.BORDER_CAMP[1], T.BORDER_CAMP[2], T.BORDER_CAMP[3], 1)
		pill.text:SetTextColor(CAMP[1], CAMP[2], CAMP[3])
	else
		pill:SetBackdropColor(T.BG_PILL[1], T.BG_PILL[2], T.BG_PILL[3], T.BG_PILL[4])
		pill:SetBackdropBorderColor(0.32, 0.28, 0.22, 0.90)
		pill.text:SetTextColor(MUTED[1], MUTED[2], MUTED[3])
	end
end

function UI:UpdateDashboardWidgets(scanner, tel, adv, bonusPct, placing)
	local a = scanner.auras
	local Fmt = T.FmtDuration
	local xph = tel:GetXPPerHour()
	local eta = tel:GetETASeconds()
	local restedPct = tel:GetRestedPercent()
	local progPct = math.floor(tel:GetXPProgress() * 100 + 0.5)

	-- 3-Column Metrics
	self.col1Lbl:SetText("XP BONUS")
	self.col1Val:SetText(string.format("+%d%%", bonusPct))
	if bonusPct >= 8 then
		self.col1Val:SetTextColor(READY[1], READY[2], READY[3])
	elseif bonusPct > 0 then
		self.col1Val:SetTextColor(GOLD_BRIGHT[1], GOLD_BRIGHT[2], GOLD_BRIGHT[3])
	else
		self.col1Val:SetTextColor(IVORY[1], IVORY[2], IVORY[3])
	end

	if xph > 0 then
		self.col2Lbl:SetText("XP / HOUR")
		self.col2Val:SetText(xph >= 1000 and string.format("%.1fk", xph / 1000) or tostring(xph))
	else
		self.col2Lbl:SetText("LEVEL " .. tostring(tel.level or 1))
		self.col2Val:SetText(string.format("%d%%", progPct))
	end
	self.col2Val:SetTextColor(IVORY[1], IVORY[2], IVORY[3])

	if eta and eta > 0 and (tel.level or 1) < (ns.MAX_LEVEL or 60) then
		self.col3Lbl:SetText("TO LVL " .. tostring((tel.level or 1) + 1))
		self.col3Val:SetText(Fmt(eta))
		self.col3Val:SetTextColor(GOLD_BRIGHT[1], GOLD_BRIGHT[2], GOLD_BRIGHT[3])
	else
		self.col3Lbl:SetText("RESTED XP")
		self.col3Val:SetText(string.format("%d%%", restedPct))
		local rc = restedPct > 0 and RESTED or MUTED
		self.col3Val:SetTextColor(rc[1], rc[2], rc[3])
	end

	-- 3 Rounded Visual Slot Pills (Food · Bag · Camp)
	local food = scanner:GetSelectedFood()
	if a.wellFed then
		StyleSlotPill(self.foodPill, "active", Fmt(a.wellFedRemaining), (food and food.icon) or FOOD_ICON_DEFAULT)
	elseif food then
		StyleSlotPill(self.foodPill, "ready", string.format("x%d", food.count), food.icon or FOOD_ICON_DEFAULT)
	else
		StyleSlotPill(self.foodPill, "idle", "0 Food", FOOD_ICON_DEFAULT)
	end

	if a.wellRested then
		StyleSlotPill(self.bagPill, "active", string.format("%d/3 %s", a.wellRestedStacks or 1, Fmt(a.wellRestedRemaining)), BAG_ICON_DEFAULT)
	elseif scanner.items.sleepingBag then
		StyleSlotPill(self.bagPill, "ready", "Ready", scanner.items.sleepingBag.icon or BAG_ICON_DEFAULT)
	else
		StyleSlotPill(self.bagPill, "idle", "Bag —", BAG_ICON_DEFAULT)
	end

	if a.campBuff then
		StyleSlotPill(self.campPill, "active", Fmt(a.campBuffRemaining), CAMP_ICON_DEFAULT)
	elseif a.campfireNearby then
		StyleSlotPill(self.campPill, "camp", "Fire!", CAMP_ICON_DEFAULT)
	elseif scanner.campfireSpell or scanner.items.campfireKit then
		StyleSlotPill(self.campPill, "ready", "Ready", CAMP_ICON_DEFAULT)
	else
		StyleSlotPill(self.campPill, "idle", "Camp —", CAMP_ICON_DEFAULT)
	end

	-- Top-Right Status Chip
	local pauseTag = adv:GetPauseTag()
	if placing then
		self.tagRight:SetText("UNLOCKED")
		self.tagRight:SetTextColor(READY[1], READY[2], READY[3])
		self.statusChip:SetBackdropColor(T.BG_PILL_OK[1], T.BG_PILL_OK[2], T.BG_PILL_OK[3], 0.96)
		self.statusChip:SetBackdropBorderColor(T.BORDER_READY[1], T.BORDER_READY[2], T.BORDER_READY[3], 1)
	elseif pauseTag ~= nil then
		self.tagRight:SetText(pauseTag)
		local pCol = (pauseTag == "IN INN") and RESTED or WARN
		self.tagRight:SetTextColor(pCol[1], pCol[2], pCol[3])
		self.statusChip:SetBackdropColor(T.BG_PILL[1], T.BG_PILL[2], T.BG_PILL[3], 0.96)
		self.statusChip:SetBackdropBorderColor(pCol[1] * 0.7, pCol[2] * 0.7, pCol[3] * 0.7, 1)
	elseif bonusPct > 0 then
		self.tagRight:SetText(string.format("+%d%% XP", bonusPct))
		self.tagRight:SetTextColor(READY[1], READY[2], READY[3])
		self.statusChip:SetBackdropColor(T.BG_PILL_OK[1], T.BG_PILL_OK[2], T.BG_PILL_OK[3], 0.96)
		self.statusChip:SetBackdropBorderColor(T.BORDER_READY[1], T.BORDER_READY[2], T.BORDER_READY[3], 1)
	else
		self.tagRight:SetText("TRACKING")
		self.tagRight:SetTextColor(GOLD_BRIGHT[1], GOLD_BRIGHT[2], GOLD_BRIGHT[3])
		self.statusChip:SetBackdropColor(T.BG_PILL[1], T.BG_PILL[2], T.BG_PILL[3], 0.96)
		self.statusChip:SetBackdropBorderColor(T.BORDER[1], T.BORDER[2], T.BORDER[3], 1)
	end
end

function UI:Refresh()
	if not self.frame then return end
	local ok, err = pcall(self.RefreshInner, self)
	if not ok then
		ns:RecordError("UI:Refresh", err)
	end
end

function UI:RefreshInner()
	local db = ns.db or {}
	local inCombat = (self.combatFlag == true) or (InCombatLockdown and InCombatLockdown()) or false
	local placing = (db.locked == false)

	if inCombat then
		self.frame:SetAlpha(0)
		if self.foodDrawer and self.foodDrawer:IsShown() then
			self.foodDrawer:Hide()
		end
		return
	end

	if not db.enabled then
		self.frame:Hide()
		self:UpdateSecureAction(nil, false)
		return
	end

	self.frame:SetAlpha(1)
	self:ApplyLock()

	local scanner = ns:GetModule("Scanner")
	local tel = ns:GetModule("Telemetry")
	local adv = ns:GetModule("Advisor")
	if not scanner or not tel or not adv then return end

	if not placing and tel:IsMaxLevel() then
		self.frame:Hide()
		self:UpdateSecureAction(nil, false)
		return
	end

	local action = adv:Evaluate()
	local visMode = db.visibility or "pill"
	local shouldShow = placing or (action ~= nil) or (visMode == "pill") or (visMode == "always")

	if not shouldShow then
		self.frame:Hide()
		self:UpdateSecureAction(nil, false)
		return
	end

	local bonusPct = scanner:GetActiveXPBonusPercent()
	local telemetryStr = tel:FormatCompact(bonusPct)
	self:UpdateDashboardWidgets(scanner, tel, adv, bonusPct, placing)

	if action then
		self:ApplyModeLayout(true)
		self.iconTex:SetTexture(action.icon or FOOD_ICON_DEFAULT)

		local bCol = WARN
		local bdCol = T.BORDER_WARN
		if action.isReadyFlash then
			bCol = READY
			bdCol = T.BORDER_READY
		elseif action.isCamp then
			bCol = CAMP
			bdCol = T.BORDER_CAMP
		elseif action.kind == "channel" then
			bCol = RESTED
			bdCol = RESTED
		end

		if not self.masqued then
			self.iconBorder:SetColorTexture(bCol[1], bCol[2], bCol[3], 0.95)
		end
		self.actionTray:SetBackdropBorderColor(bdCol[1], bdCol[2], bdCol[3], 1)
		self.frame:SetBackdropBorderColor(bdCol[1], bdCol[2], bdCol[3], 1)

		self.topLine:SetText(action.title or "")
		self.topLine:SetTextColor(IVORY[1], IVORY[2], IVORY[3])
		self.subLine:SetText(action.subtitle or telemetryStr)
		self.subLine:SetTextColor(bCol[1], bCol[2], bCol[3])

		if action.progress ~= nil then
			self.xpBar:SetStatusBarColor(bCol[1], bCol[2], bCol[3], 0.95)
			self.xpBar:SetValue(action.progress)
		else
			local barCol = (tel:GetRestedPercent() > 0) and RESTED or GOLD
			self.xpBar:SetStatusBarColor(barCol[1], barCol[2], barCol[3], 0.92)
			self.xpBar:SetValue(tel:GetXPProgress())
		end

		self.frame:Show()
		self:UpdateSecureAction(action, true)
	else
		self:ApplyModeLayout(false)
		local bd = (bonusPct >= 8) and T.BORDER_READY or T.BORDER
		self.frame:SetBackdropBorderColor(bd[1], bd[2], bd[3], 1)

		-- Keep topLine/subLine populated with compact summary for state inspection
		self.topLine:SetText(telemetryStr)
		self.subLine:SetText(adv:FormatActiveBadges())

		local barCol = (tel:GetRestedPercent() > 0) and RESTED or GOLD
		self.xpBar:SetStatusBarColor(barCol[1], barCol[2], barCol[3], 0.92)
		self.xpBar:SetValue(tel:GetXPProgress())

		self.frame:Show()
		self:UpdateSecureAction(nil, false)
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
		y = y or -110,
	}
end

function UI:ApplyPosition()
	if not self.frame then return end
	local pos = (ns.db and ns.db.position) or ns.DefaultPosition()
	self.frame:ClearAllPoints()
	self.frame:SetPoint(pos.point or "TOP", UIParent, pos.relativePoint or pos.point or "TOP", pos.x or 0, pos.y or -110)
	self:AnchorClickButton()
	self:AnchorFoodDrawer()
end

function UI:ApplyScale()
	if self.frame and ns.db and ns.db.scale then
		self.frame:SetScale(ns.db.scale)
		self:AnchorClickButton()
	end
end

function UI:ApplyLock()
	if not self.frame then return end
	self.frame:EnableMouse(true)
end

function ns.SetLocked(locked)
	local ui = ns:GetModule("UI")
	if not ui then return end
	ui.revealUntil = (not locked) and ((GetTime and GetTime() or 0) + 60) or 0
	ui:ApplyLock()
	ui:Refresh()
end

function ns.ApplyScale()
	local ui = ns:GetModule("UI")
	if ui then ui:ApplyScale() end
end

function ns.ApplyPosition()
	local ui = ns:GetModule("UI")
	if ui then ui:ApplyPosition() end
end
