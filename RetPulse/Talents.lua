local addonName, ns = ...

local Talents = ns:NewModule("Talents")

-- RetPulse Talent Advisor for WoW: Forever (16001).
-- Hooks PlayerSpellsFrame.TalentsFrame (zero taint, read-only) and attaches
-- clearly branded "RP NEXT" / "RP X/Y" badges on the LEFT side of talent nodes
-- so they never overlap with Zygor's TOPRIGHT icon.

local GOLD  = { 0.94, 0.78, 0.38 }
local READY = { 0.62, 1.00, 0.32 }
local DONE  = { 0.38, 0.85, 0.52 }
local DARK  = { 0.04, 0.04, 0.06 }
local DONE_TEXT = "RP |TInterface\\RaidFrame\\ReadyCheck-Ready:10:10|t"

-- Ordered 51-point builds (Retribution 31 -> Unsealed Wrath + Holy 20).
local BUILDS = {
	dps = {
		label = "Unsealed Wrath (DPS)",
		order = {
			"Benediction", "Benediction", "Benediction", "Benediction", "Benediction",
			"Improved Judgement", "Improved Judgement",
			"Conviction", "Conviction", "Conviction",
			"Pursuit of Justice", "Pursuit of Justice",
			"Seal of Command",
			"Sanctified Judgement", "Sanctified Judgement",
			"Sacred Arbiter",
			"Two-Handed Weapon Specialization", "Two-Handed Weapon Specialization", "Two-Handed Weapon Specialization",
			"Sanctified Judgement",
			"Vengeance", "Vengeance", "Vengeance",
			"Repentance",
			"Vindication",
			"Champion of the Light", "Champion of the Light", "Champion of the Light", "Champion of the Light", "Champion of the Light",
			"Unsealed Wrath",
			"Divine Strength", "Divine Strength", "Divine Strength", "Divine Strength", "Divine Strength",
			"Reverence", "Reverence",
			"Improved Seals", "Improved Seals", "Improved Seals",
			"Holy Conduit", "Holy Conduit",
			"Improved Seals", "Improved Seals",
			"Purifying Power", "Purifying Power",
			"Divine Precision", "Divine Precision",
			"Vindication", "Vindication",
		},
	},
	leveling = {
		label = "Retribution (Leveling)",
		order = {
			"Deflection", "Deflection", "Deflection", "Deflection", "Deflection",
			"Improved Judgement", "Improved Judgement",
			"Conviction", "Conviction", "Conviction",
			"Pursuit of Justice", "Pursuit of Justice",
			"Seal of Command",
			"Sanctified Judgement", "Sanctified Judgement",
			"Sacred Arbiter",
			"Two-Handed Weapon Specialization", "Two-Handed Weapon Specialization", "Two-Handed Weapon Specialization",
			"Sanctified Judgement",
			"Vengeance", "Vengeance", "Vengeance",
			"Repentance",
			"Vindication",
			"Champion of the Light", "Champion of the Light", "Champion of the Light", "Champion of the Light", "Champion of the Light",
			"Unsealed Wrath",
			"Divine Strength", "Divine Strength", "Divine Strength", "Divine Strength", "Divine Strength",
			"Reverence", "Reverence",
			"Improved Seals", "Improved Seals", "Improved Seals",
			"Holy Conduit", "Holy Conduit",
			"Improved Seals", "Improved Seals",
			"Purifying Power", "Purifying Power",
			"Divine Precision", "Divine Precision",
			"Vindication", "Vindication",
		},
	},
}

Talents.BUILDS = BUILDS

function Talents:OnInitialize()
	self.hooked = false
	self.overlayPool = {}
	self.activeOverlays = {}
	self.headerFrame = nil
end

function Talents:OnLogin()
	self:TryHook()

	ns:On("ADDON_LOADED", function(_, loadedName)
		if loadedName == "Blizzard_PlayerSpells" then
			self:TryHook()
		end
	end)

	local function ScheduleRefresh()
		if not (PlayerSpellsFrame and PlayerSpellsFrame.TalentsFrame and PlayerSpellsFrame.TalentsFrame:IsVisible()) then
			return
		end
		if C_Timer and C_Timer.After then
			C_Timer.After(0, function() self:RefreshOverlay() end)
		else
			self:RefreshOverlay()
		end
	end

	ns:On("TRAIT_TREE_CURRENCY_INFO_UPDATED", ScheduleRefresh)
	ns:On("TRAIT_NODE_CHANGED", ScheduleRefresh)
end

function Talents:TryHook()
	if self.hooked then return end
	if not (PlayerSpellsFrame and PlayerSpellsFrame.TalentsFrame) then return end
	if type(PlayerSpellsFrame.TalentsFrame.HookScript) ~= "function" then return end

	self.hooked = true
	PlayerSpellsFrame.TalentsFrame:HookScript("OnShow", function()
		self:RefreshOverlay()
	end)
	PlayerSpellsFrame.TalentsFrame:HookScript("OnHide", function()
		self:ClearOverlays()
	end)
end

-- Pure calculation seam: given { [talentName] = currentRank } and buildId,
-- returns the next recommended talent, target ranks, and invested progress.
function Talents:ComputePlan(currentRanks, buildId)
	local build = BUILDS[buildId or "dps"] or BUILDS.dps
	local ranks = currentRanks or {}
	local targets = {}
	local neededSoFar = {}
	local nextTalent = nil

	for _, name in ipairs(build.order) do
		targets[name] = (targets[name] or 0) + 1
		neededSoFar[name] = (neededSoFar[name] or 0) + 1
		if not nextTalent and (ranks[name] or 0) < neededSoFar[name] then
			nextTalent = name
		end
	end

	local invested = 0
	for name, targetRank in pairs(targets) do
		invested = invested + math.min(ranks[name] or 0, targetRank)
	end

	return {
		buildId = buildId or "dps",
		label = build.label,
		nextTalent = nextTalent,
		targets = targets,
		investedInBuild = invested,
		totalPoints = #build.order,
	}
end

local function ResolveButtonTalentName(configID, button)
	if type(button) ~= "table" then return nil end
	local nodeInfo = button.nodeInfo
	if type(nodeInfo) ~= "table" or type(nodeInfo.entryIDs) ~= "table" then return nil end
	local entryID = nodeInfo.entryIDs[1]
	if not entryID or not C_Traits or not C_Traits.GetEntryInfo or not C_Traits.GetDefinitionInfo then
		return nil
	end

	local okE, entryInfo = pcall(C_Traits.GetEntryInfo, configID, entryID)
	if not okE or type(entryInfo) ~= "table" or not entryInfo.definitionID then return nil end

	local okD, defInfo = pcall(C_Traits.GetDefinitionInfo, entryInfo.definitionID)
	if not okD or type(defInfo) ~= "table" or not defInfo.spellID then return nil end

	if C_Spell and C_Spell.GetSpellInfo then
		local okS, spellInfo = pcall(C_Spell.GetSpellInfo, defInfo.spellID)
		if okS and type(spellInfo) == "table" and type(spellInfo.name) == "string" and not ns.IsSecret(spellInfo.name) then
			return spellInfo.name
		end
	end
	return nil
end

function Talents:AcquireOverlay(parentButton)
	local overlay
	for _, item in ipairs(self.overlayPool) do
		if not item._inUse then
			overlay = item
			break
		end
	end

	if not overlay then
		overlay = CreateFrame("Frame", nil, parentButton, "BackdropTemplate")
		overlay:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8X8",
			edgeFile = "Interface\\Buttons\\WHITE8X8",
			tile = false,
			edgeSize = 2,
		})
		overlay:SetBackdropColor(0, 0, 0, 0)

		local pill = CreateFrame("Frame", nil, overlay, "BackdropTemplate")
		pill:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8X8",
			edgeFile = "Interface\\Buttons\\WHITE8X8",
			tile = false,
			edgeSize = 1,
		})
		pill:SetBackdropColor(DARK[1], DARK[2], DARK[3], 0.92)

		local badgeText = pill:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		badgeText:SetPoint("CENTER", pill, "CENTER", 0, 0)
		badgeText:SetJustifyH("CENTER")
		if badgeText.SetShadowOffset then
			badgeText:SetShadowOffset(1, -1)
			badgeText:SetShadowColor(0, 0, 0, 1)
		end

		overlay.pill = pill
		overlay.badgeText = badgeText
		self.overlayPool[#self.overlayPool + 1] = overlay
	end

	overlay._inUse = true
	if overlay.SetParent then overlay:SetParent(parentButton) end
	overlay:ClearAllPoints()
	overlay:SetPoint("TOPLEFT", parentButton, "TOPLEFT", -2, 2)
	overlay:SetPoint("BOTTOMRIGHT", parentButton, "BOTTOMRIGHT", 2, -2)
	overlay:SetFrameLevel((parentButton:GetFrameLevel() or 10) + 15)
	overlay:Show()
	return overlay
end

function Talents:ClearOverlays()
	for _, overlay in ipairs(self.overlayPool) do
		overlay._inUse = false
		overlay:Hide()
	end
	self.activeOverlays = {}
	if self.headerFrame then
		self.headerFrame:Hide()
	end
end

function Talents:EnsureHeader(talentsFrame)
	if self.headerFrame then
		if self.headerFrame.SetParent then self.headerFrame:SetParent(talentsFrame) end
		return self.headerFrame
	end

	local hdr = CreateFrame("Frame", nil, talentsFrame, "BackdropTemplate")
	hdr:SetSize(268, 22)
	hdr:SetPoint("TOP", talentsFrame, "TOP", 0, -54)
	hdr:SetFrameLevel((talentsFrame:GetFrameLevel() or 10) + 25)
	hdr:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8X8",
		edgeFile = "Interface\\Buttons\\WHITE8X8",
		tile = false,
		edgeSize = 1,
	})
	hdr:SetBackdropColor(DARK[1], DARK[2], DARK[3], 0.90)
	hdr:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.70)

	local text = hdr:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	text:SetPoint("CENTER", hdr, "CENTER", 0, 0)
	text:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
	hdr.text = text

	self.headerFrame = hdr
	return hdr
end

function Talents:RefreshOverlay()
	self:ClearOverlays()

	local db = ns.db
	if db and db.talentAdvisor == false then return end
	if not (PlayerSpellsFrame and PlayerSpellsFrame.TalentsFrame) then return end

	local tf = PlayerSpellsFrame.TalentsFrame
	if type(tf.IsVisible) == "function" and not tf:IsVisible() then return end
	if type(tf.nodeIDToButton) ~= "table" then return end

	local configID = tf.configurationInfo and tf.configurationInfo.ID or (C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_ClassTalents.GetActiveConfigID()) or 1

	local buttonsByName = {}
	local currentRanks = {}
	for _, btn in pairs(tf.nodeIDToButton) do
		local name = ResolveButtonTalentName(configID, btn)
		if name then
			buttonsByName[name] = btn
			local ranks = btn.nodeInfo and (btn.nodeInfo.ranksPurchased or btn.nodeInfo.currentRank) or 0
			if ns.IsReadable(ranks) then
				currentRanks[name] = ranks
			end
		end
	end

	local buildId = (db and db.talentBuild) or "dps"
	local plan = self:ComputePlan(currentRanks, buildId)

	local hdr = self:EnsureHeader(tf)
	hdr.text:SetText(string.format("RetPulse: %s  (%d/%d)", plan.label, plan.investedInBuild, plan.totalPoints))
	hdr:Show()

	for name, targetRank in pairs(plan.targets) do
		local btn = buttonsByName[name]
		local cur = currentRanks[name] or 0
		if btn then
			local overlay = self:AcquireOverlay(btn)
			overlay.pill:ClearAllPoints()

			if cur >= targetRank then
				overlay:SetBackdropBorderColor(DONE[1], DONE[2], DONE[3], 0.40)
				overlay.pill:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", -4, -6)
				overlay.pill:SetSize(34, 14)
				overlay.pill:SetBackdropBorderColor(DONE[1], DONE[2], DONE[3], 0.65)
				overlay.badgeText:SetTextColor(DONE[1], DONE[2], DONE[3])
				overlay.badgeText:SetText(DONE_TEXT)
			elseif name == plan.nextTalent then
				overlay:SetBackdropBorderColor(READY[1], READY[2], READY[3], 0.95)
				overlay.pill:SetPoint("TOPLEFT", overlay, "TOPLEFT", -6, 10)
				overlay.pill:SetSize(52, 15)
				overlay.pill:SetBackdropBorderColor(READY[1], READY[2], READY[3], 0.95)
				overlay.badgeText:SetTextColor(READY[1], READY[2], READY[3])
				overlay.badgeText:SetText("RP NEXT")
			else
				overlay:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.45)
				overlay.pill:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", -4, -6)
				overlay.pill:SetSize(44, 14)
				overlay.pill:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.75)
				overlay.badgeText:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
				overlay.badgeText:SetText(string.format("RP %d/%d", cur, targetRank))
			end

			self.activeOverlays[name] = overlay
		end
	end
end
