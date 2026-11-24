local addonName, ns = ...

local UI = ns:NewModule("UI")

-- Command Plate HUD (Forever-safe, Interface 16001):
--   left     : main spell icon + keybind pill + soft glow (no SetMask)
--   mid      : spell name + status line
--   right    : NEXT preview dock
--   top rail : Unsealed Wrath echo pips + decay bar (when talent active)
--   bottom   : weapon swing StatusBar + secret-safe mana rail
-- Visual tokens live in UITheme.lua. Queue / FX / click-to-cast behaviour unchanged.

local T = ns.UITheme
local GOLD, GOLD_DIM = T.GOLD, T.GOLD_DIM
local IVORY, MUTED = T.IVORY, T.MUTED
local READY, WARN, OOR, OOM = T.READY, T.WARN, T.OOR, T.OOM
local MEDIA = T.MEDIA
local PANEL_W, PANEL_H = T.PANEL_W, T.PANEL_H
local PANEL_H_COMPACT = T.PANEL_H_COMPACT
local MAIN_SIZE, NEXT_SIZE, PIP_SIZE = T.MAIN_SIZE, T.NEXT_SIZE, T.PIP_SIZE
local FADE_SPEED, IDLE_ALPHA = T.FADE_SPEED, T.IDLE_ALPHA
local POP_DURATION, FLASH_DURATION = T.POP_DURATION, T.FLASH_DURATION
local MAX_CONSECUTIVE_ERRORS = 5

local SetPixelSize = T.SetPixelSize
local SetPixelHeight = T.SetPixelHeight

local function Icon(spell)
	if not spell or not C_Spell or not C_Spell.GetSpellTexture then return nil end
	local ok, texture = pcall(C_Spell.GetSpellTexture, spell)
	if ok and not ns.IsSecret(texture) then return texture end
	return nil
end

local function SpellName(spell)
	if not spell or not C_Spell or not C_Spell.GetSpellInfo then return "" end
	local ok, info = pcall(C_Spell.GetSpellInfo, spell)
	if ok and type(info) == "table" and type(info.name) == "string" and not ns.IsSecret(info.name) then
		return info.name
	end
	return ""
end

local function Fmt(value)
	if not value then return "" end
	if value >= 10 then return string.format("%.0fs", value) end
	return string.format("%.1fs", value)
end

local function CreateKeybindPill(parent)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 2, 2)
	SetPixelSize(holder, 20, 13)
	holder:Hide()

	local bg = holder:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0.02, 0.02, 0.04, 0.86)

	local edge = holder:CreateTexture(nil, "BORDER")
	edge:SetPoint("TOPLEFT", -1, 1)
	edge:SetPoint("BOTTOMRIGHT", 1, -1)
	edge:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.35)
	holder.edge = edge

	local text = holder:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmallGray")
	text:SetPoint("CENTER", holder, "CENTER", 0, 0)
	text:SetJustifyH("CENTER")
	text:SetTextColor(1, 0.98, 0.92, 1)
	if text.SetShadowOffset then
		text:SetShadowOffset(1, -1)
		text:SetShadowColor(0, 0, 0, 1)
	end
	text:SetText("")

	return holder, text
end

local function UpdateKeybindPill(holder, textRegion, value)
	if value and value ~= "" then
		textRegion:SetText(value)
		local width = math.max(14, (#value * 6) + 6)
		SetPixelSize(holder, width, 13)
		holder:Show()
	else
		textRegion:SetText("")
		holder:Hide()
	end
end

function UI:OnLogin()
	self.consecutiveErrors = 0
	self.targetAlpha = 0
	self.currentAlpha = 0
	self.popTime = 0
	self.flashTime = 0
	self.pipAlphas = { 0.16, 0.16, 0.16 }

	local ok, err = pcall(function()
		self:Build()
		self:ApplyScale()
		self:ApplyPosition()
		self:ApplyLock()
	end)
	if ns.db then ns.db.uiBuilt = ok end
	if not ok then ns:RecordError("UI:Build", err) end

	-- Hidden frames skip OnUpdate; visibility must also be event-driven.
	ns:On("PLAYER_REGEN_DISABLED", function()
		self.combatFlag = true
		self.consecutiveErrors = 0
		self:Refresh()
	end)
	ns:On("PLAYER_REGEN_ENABLED", function()
		self.combatFlag = false
		self:Refresh()
	end)
	ns:On("PLAYER_TARGET_CHANGED", function() self:Refresh() end)
	ns:On("NAME_PLATE_UNIT_ADDED", function()
		if ns.db and ns.db.nameplateMode then self:Refresh() end
	end)
	ns:On("NAME_PLATE_UNIT_REMOVED", function()
		if ns.db and ns.db.nameplateMode then self:Refresh() end
	end)
	ns:On("UNIT_POWER_UPDATE", function(_, unit)
		if unit == "player" then self:UpdateManaBar() end
	end)
	ns:On("UNIT_AURA", function(_, unit)
		if unit == "player" and not InCombatLockdown() then self:Refresh() end
	end)
	ns:On("PLAYER_ENTERING_WORLD", function()
		self.consecutiveErrors = 0
		self:Refresh()
	end)

	self:Refresh()
end

function UI:LayoutMidband()
	-- Keep icon + text + NEXT on one mid-row above the bottom rails.
	local rail = T.RAIL_PAD or 10
	local inset = T.INSET or 8
	if self.dial then
		self.dial:ClearAllPoints()
		self.dial:SetPoint("LEFT", inset + 2, rail / 2)
	end
	if self.nextFrame then
		self.nextFrame:ClearAllPoints()
		self.nextFrame:SetPoint("RIGHT", -inset, rail / 2 + 4)
	end
	if self.chevron then
		self.chevron:ClearAllPoints()
		self.chevron:SetPoint("RIGHT", self.nextFrame, "LEFT", -6, 0)
	end
	if self.label then
		self.label:ClearAllPoints()
		local topNudge = self.trackerVisible and -16 or -4
		self.label:SetPoint("LEFT", self.dial, "RIGHT", T.GAP, topNudge)
		self.label:SetPoint("RIGHT", self.nextFrame, "LEFT", -18, topNudge)
	end
	if self.status then
		self.status:ClearAllPoints()
		self.status:SetPoint("TOPLEFT", self.label, "BOTTOMLEFT", 0, -2)
		self.status:SetPoint("RIGHT", self.nextFrame, "LEFT", -18, 0)
	end
	if self.pipRow then
		self.pipRow:ClearAllPoints()
		self.pipRow:SetPoint("BOTTOMLEFT", self.label, "TOPLEFT", 0, 4)
	end
end

function UI:Build()
	local frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
	SetPixelSize(frame, PANEL_W, PANEL_H)
	T.ApplyPlateBackdrop(frame)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetClampedToScreen(true)
	-- Do not clip children: keybind pills and NEXT label sit slightly outside icon bounds.
	frame:SetClipsChildren(false)

	frame:SetScript("OnDragStart", function(f)
		if ns.db and not ns.db.locked then f:StartMoving() end
	end)
	frame:SetScript("OnDragStop", function(f)
		f:StopMovingOrSizing()
		UI:SavePosition()
	end)

	local bgGrad = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
	bgGrad:SetPoint("TOPLEFT", 1, -1)
	bgGrad:SetPoint("BOTTOMRIGHT", -1, 1)
	bgGrad:SetColorTexture(1, 1, 1, 1)
	if CreateColor and bgGrad.SetGradient then
		bgGrad:SetGradient("VERTICAL",
			CreateColor(0.03, 0.03, 0.05, 0.72),
			CreateColor(0.10, 0.09, 0.12, 0.42))
	else
		bgGrad:SetColorTexture(0.04, 0.04, 0.06, 0.45)
	end

	-- Short accent on the left edge only (stops above the rails so it doesn't thicken the corner).
	local accent = frame:CreateTexture(nil, "BORDER", nil, 2)
	accent:SetPoint("TOPLEFT", 1, -1)
	accent:SetPoint("BOTTOMLEFT", 1, (T.RAIL_PAD or 10) + 2)
	T.SetPixelWidth(accent, T.ACCENT_W)
	accent:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.75)

	-- Caption top-left so it never fights the NEXT dock.
	local caption = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	caption:SetPoint("TOPLEFT", 8, -4)
	caption:SetText("RETPULSE")
	caption:SetTextColor(GOLD[1], GOLD[2], GOLD[3], 0.35)

	-- Main icon hub (kept as `dial` for tests / debug). Never SetMask on Forever.
	local dial = CreateFrame("Frame", nil, frame)
	SetPixelSize(dial, MAIN_SIZE + 6, MAIN_SIZE + 6)
	dial:SetPoint("LEFT", (T.INSET or 8) + 2, (T.RAIL_PAD or 10) / 2)

	local glow = dial:CreateTexture(nil, "BACKGROUND", nil, 1)
	glow:SetTexture(MEDIA .. "glow")
	SetPixelSize(glow, MAIN_SIZE * 1.45, MAIN_SIZE * 1.45)
	glow:SetPoint("CENTER")
	glow:SetBlendMode("ADD")
	glow:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 0)

	local main = CreateFrame("Frame", nil, dial)
	SetPixelSize(main, MAIN_SIZE, MAIN_SIZE)
	main:SetPoint("CENTER")

	local mainBorder = main:CreateTexture(nil, "BACKGROUND")
	mainBorder:SetPoint("TOPLEFT", -1, 1)
	mainBorder:SetPoint("BOTTOMRIGHT", 1, -1)
	mainBorder:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.80)

	local mainIcon = main:CreateTexture(nil, "ARTWORK")
	mainIcon:SetAllPoints()
	mainIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	local flash = main:CreateTexture(nil, "OVERLAY", nil, 5)
	flash:SetAllPoints()
	flash:SetColorTexture(1, 0.95, 0.75, 0)
	flash:SetBlendMode("ADD")

	local cooldown = CreateFrame("Cooldown", nil, main, "CooldownFrameTemplate")
	cooldown:SetAllPoints(main)
	cooldown:SetDrawEdge(true)
	cooldown:SetDrawBling(false)
	cooldown:SetHideCountdownNumbers(true)
	cooldown:SetSwipeColor(0, 0, 0, 0.65)
	cooldown:Hide()

	local mainKeyOverlay = CreateFrame("Frame", nil, main)
	mainKeyOverlay:SetAllPoints(main)
	mainKeyOverlay:SetFrameLevel(cooldown:GetFrameLevel() + 2)
	local mainKeyHolder, mainKey = CreateKeybindPill(mainKeyOverlay)

	-- Echo pips (row above the spell name when Unsealed Wrath tracker is on).
	local pips = {}
	local pipRow = CreateFrame("Frame", nil, frame)
	SetPixelSize(pipRow, (PIP_SIZE * 3) + 8, PIP_SIZE)
	for i = 1, 3 do
		local pip = pipRow:CreateTexture(nil, "OVERLAY")
		SetPixelSize(pip, PIP_SIZE, PIP_SIZE)
		pip:SetPoint("LEFT", (i - 1) * (PIP_SIZE + 4), 0)
		pip:SetRotation(math.rad(45))
		pip:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.16)
		pips[i] = pip
	end

	local echoBar = CreateFrame("StatusBar", nil, frame)
	SetPixelSize(echoBar, 72, 3)
	echoBar:SetPoint("LEFT", pipRow, "RIGHT", 6, 0)
	echoBar:SetStatusBarTexture(T.SOLID)
	echoBar:SetStatusBarColor(GOLD[1], GOLD[2], GOLD[3], 0.95)
	echoBar:SetMinMaxValues(0, 1)
	echoBar:SetValue(0)

	local echoTrack = echoBar:CreateTexture(nil, "BACKGROUND")
	echoTrack:SetAllPoints()
	echoTrack:SetColorTexture(T.TRACK[1], T.TRACK[2], T.TRACK[3], T.TRACK[4])

	local echoText = echoBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	echoText:SetPoint("LEFT", echoBar, "RIGHT", 6, 0)
	echoText:SetTextColor(IVORY[1], IVORY[2], IVORY[3], 0.70)

	local nextFrame = CreateFrame("Frame", nil, frame)
	SetPixelSize(nextFrame, NEXT_SIZE, NEXT_SIZE)
	nextFrame:SetPoint("RIGHT", -(T.INSET or 8), (T.RAIL_PAD or 10) / 2 + 4)

	local nextBorder = nextFrame:CreateTexture(nil, "BACKGROUND")
	nextBorder:SetPoint("TOPLEFT", -1, 1)
	nextBorder:SetPoint("BOTTOMRIGHT", 1, -1)
	nextBorder:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.40)

	local nextIcon = nextFrame:CreateTexture(nil, "ARTWORK")
	nextIcon:SetAllPoints()
	nextIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	nextIcon:SetAlpha(0.90)

	local nextKeyHolder, nextKey = CreateKeybindPill(nextFrame)

	local nextLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	nextLabel:SetPoint("TOP", nextFrame, "BOTTOM", 0, -1)
	nextLabel:SetTextColor(MUTED[1], MUTED[2], MUTED[3], 0.70)
	nextLabel:SetText("NEXT")

	local chevron = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	chevron:SetPoint("RIGHT", nextFrame, "LEFT", -6, 0)
	chevron:SetTextColor(GOLD[1], GOLD[2], GOLD[3], 0.45)
	chevron:SetText(">")
	chevron:Hide()

	local label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	label:SetPoint("LEFT", dial, "RIGHT", T.GAP, -4)
	label:SetPoint("RIGHT", nextFrame, "LEFT", -18, -4)
	label:SetJustifyH("LEFT")
	label:SetWordWrap(false)
	label:SetTextColor(IVORY[1], IVORY[2], IVORY[3])
	if label.SetShadowOffset then
		label:SetShadowOffset(1, -1)
		label:SetShadowColor(0, 0, 0, 0.9)
	end
	label:SetText("")

	local status = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	status:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -2)
	status:SetPoint("RIGHT", nextFrame, "LEFT", -18, 0)
	status:SetJustifyH("LEFT")
	status:SetWordWrap(false)
	status:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
	status:SetText("")

	pipRow:SetPoint("BOTTOMLEFT", label, "TOPLEFT", 0, 4)

	-- Bottom rails inset from the border (StatusBar — Forever-safe; no circular Cooldown mask).
	local swingBar = CreateFrame("StatusBar", nil, frame)
	SetPixelHeight(swingBar, T.SWING_H)
	swingBar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 2, 5)
	swingBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 5)
	swingBar:SetStatusBarTexture(T.SOLID)
	swingBar:SetStatusBarColor(GOLD[1], GOLD[2], GOLD[3], 0.90)
	swingBar:SetMinMaxValues(0, 1)
	swingBar:SetValue(0)
	swingBar:Hide()

	local swingTrack = swingBar:CreateTexture(nil, "BACKGROUND")
	swingTrack:SetAllPoints()
	swingTrack:SetColorTexture(1, 1, 1, 0.06)

	-- Alias for tests that still look for the dial-era name.
	local swingRing = swingBar

	local manaBar = CreateFrame("StatusBar", nil, frame)
	SetPixelHeight(manaBar, T.MANA_H)
	manaBar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 2, 2)
	manaBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
	manaBar:SetStatusBarTexture(T.SOLID)
	manaBar:SetStatusBarColor(T.MANA[1], T.MANA[2], T.MANA[3], 0.85)
	manaBar:SetMinMaxValues(0, 1)
	manaBar:SetValue(1)

	local manaTrack = manaBar:CreateTexture(nil, "BACKGROUND")
	manaTrack:SetAllPoints()
	manaTrack:SetColorTexture(1, 1, 1, 0.06)

	self.frame = frame
	local okClick, errClick = pcall(self.BuildClickCast, self, frame, main, cooldown)
	if not okClick then ns:RecordError("BuildClickCast", errClick) end
	local okNp, errNp = pcall(self.BuildNameplateWidget, self, frame)
	if not okNp then ns:RecordError("BuildNameplateWidget", errNp) end
	self.caption = caption
	self.accent = accent
	self.dial = dial
	self.pipRow = pipRow
	self.pips = pips
	self.echoBar = echoBar
	self.echoText = echoText
	self.main = main
	self.mainBorder = mainBorder
	self.mainIcon = mainIcon
	self.flash = flash
	self.mainKeyHolder = mainKeyHolder
	self.mainKey = mainKey
	self.cooldown = cooldown
	self.swingRing = swingRing
	self.swingBar = swingBar
	self.swingTick = nil
	self.manaBar = manaBar
	self.glow = glow
	self.status = status
	self.label = label
	self.chevron = chevron
	self.nextIcon = nextIcon
	self.nextKeyHolder = nextKeyHolder
	self.nextKey = nextKey
	self.nextFrame = nextFrame
	self.nextLabel = nextLabel
	self.nextBorder = nextBorder

	self:LayoutMidband()

	local fx = ns:GetModule("FX")
	if fx then fx:Attach(main, MAIN_SIZE) end

	self.lastMainTexture = false
	self.lastNextTexture = false
	self.lastRefresh = 0
	self.lastSwingStart = nil
	frame:SetScript("OnUpdate", function(_, elapsed)
		self:StepAnimations(elapsed)

		local fxMod = ns:GetModule("FX")
		if fxMod then fxMod:Update(elapsed) end

		self.lastRefresh = self.lastRefresh + elapsed
		if self.lastRefresh >= 0.08 then
			self.lastRefresh = 0
			self:Refresh()
		end
	end)

	frame:Hide()
end

function UI:UpdateManaBar()
	if not self.manaBar or not UnitPower or not UnitPowerMax then return end
	local okMax, maxMana = pcall(UnitPowerMax, "player", 0)
	local okCur, curMana = pcall(UnitPower, "player", 0)
	if okMax and okCur and maxMana ~= nil and curMana ~= nil then
		pcall(self.manaBar.SetMinMaxValues, self.manaBar, 0, maxMana)
		pcall(self.manaBar.SetValue, self.manaBar, curMana)
		self.manaBar:Show()
	end
end

function UI:TriggerSpellPop()
	self.popTime = POP_DURATION
	self.flashTime = FLASH_DURATION
end

function UI:UpdateSwingRing(tracker, inCombat)
	local swingBar = self.swingBar or self.swingRing
	if not swingBar then return end

	local progress = inCombat and tracker and tracker:GetSwingProgress() or nil
	local known = tracker and tracker.swingKnown

	if inCombat and known and progress ~= nil then
		swingBar:SetMinMaxValues(0, 1)
		swingBar:SetValue(progress)
		if tracker:IsSwingWindowOpen(1.5) then
			swingBar:SetStatusBarColor(GOLD[1], GOLD[2], GOLD[3], 0.95)
		else
			swingBar:SetStatusBarColor(WARN[1], WARN[2], WARN[3], 0.85)
		end
		swingBar:Show()
	else
		swingBar:SetValue(0)
		swingBar:Hide()
	end
end

function UI:StepAnimations(elapsed)
	local dt = elapsed or 0
	self:StepFade(dt)

	if self.popTime and self.popTime > 0 then
		self.popTime = math.max(0, self.popTime - dt)
		local t = self.popTime / POP_DURATION
		-- Zoom the texture via SetTexCoord instead of Frame:SetScale() so
		-- frames anchored to the secure click-to-cast button never taint in combat.
		local inset = 0.08 + 0.04 * (t * t)
		if self.mainIcon then self.mainIcon:SetTexCoord(inset, 1 - inset, inset, 1 - inset) end
		self.popActive = true
	elseif self.popActive and self.mainIcon then
		self.popActive = false
		self.mainIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	end

	if self.flashTime and self.flashTime > 0 then
		self.flashTime = math.max(0, self.flashTime - dt)
		local alpha = 0.42 * (self.flashTime / FLASH_DURATION)
		if self.flash then self.flash:SetColorTexture(1, 0.95, 0.78, alpha) end
	elseif self.flash and self.flashTime == 0 then
		self.flashTime = -1
		self.flash:SetColorTexture(1, 0.95, 0.78, 0)
	end

	local targetEchoes = self.targetEchoes or 0
	if self.pips and self.trackerVisible then
		for i = 1, 3 do
			local target = (i <= targetEchoes) and 1.0 or 0.16
			local cur = self.pipAlphas[i] or 0.16
			if math.abs(target - cur) > 0.01 then
				local step = math.min(1, dt * 10)
				cur = cur + (target - cur) * step
				self.pipAlphas[i] = cur
				self.pips[i]:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], cur)
			end
		end
	end

	local tracker = ns:GetModule("CombatTracker")
	if not tracker then return end

	local inCombat = self.combatFlag == true or InCombatLockdown()
	self:UpdateSwingRing(tracker, inCombat)

	if self.trackerVisible and self.echoBar then
		local remaining = tracker:GetEchoRemaining()
		local duration = tracker:GetEchoDuration()
		if remaining and duration and duration > 0 then
			self.echoBar:SetValue(remaining / duration)
		else
			self.echoBar:SetValue(0)
		end
	end
end

function UI:StepFade(elapsed)
	if not self.frame then return end
	local target = self.targetAlpha or 0
	local current = self.currentAlpha or 0
	if current == target then
		if target <= 0 and self.frame:IsShown() then
			self.frame:Hide()
		end
		return
	end

	local delta = (elapsed or 0) * FADE_SPEED
	if current < target then
		current = math.min(target, current + delta)
	else
		current = math.max(target, current - delta)
	end
	self.currentAlpha = current
	self.frame:SetAlpha(current)

	if target <= 0 and current <= 0.01 then
		self.currentAlpha = 0
		self.frame:SetAlpha(0)
		self.frame:Hide()
	end
end

function UI:SetDesiredVisible(visible, immediate, targetAlpha)
	if not self.frame then return end
	if visible then
		local desired = targetAlpha or 1
		self.targetAlpha = desired
		if not self.frame:IsShown() then
			self.currentAlpha = immediate and desired or math.max(self.currentAlpha or 0, math.min(0.05, desired))
			self.frame:SetAlpha(self.currentAlpha)
			self.frame:Show()
		elseif immediate then
			self.currentAlpha = desired
			self.frame:SetAlpha(desired)
		end
	else
		self.targetAlpha = 0
		if immediate or not self.frame:IsShown() then
			self.currentAlpha = 0
			self.frame:SetAlpha(0)
			self.frame:Hide()
		end
	end
end

function UI:SetTrackerVisible(visible)
	local wasVisible = self.trackerVisible
	if wasVisible == visible then return end
	self.trackerVisible = visible

	for _, pip in ipairs(self.pips) do
		pip:SetShown(visible)
	end
	if self.pipRow then self.pipRow:SetShown(visible) end
	self.echoBar:SetShown(visible)
	self.echoText:SetShown(visible)

	SetPixelHeight(self.frame, visible and PANEL_H or PANEL_H_COMPACT)
	self:LayoutMidband()
end

function UI:Refresh()
	if (self.consecutiveErrors or 0) >= MAX_CONSECUTIVE_ERRORS then return end
	local ok, err = pcall(self.RefreshInner, self)
	if not ok then
		self.consecutiveErrors = (self.consecutiveErrors or 0) + 1
		if self.consecutiveErrors == 1 then
			ns:RecordError("UI:Refresh", err)
		end
		return
	end
	self.consecutiveErrors = 0
	if ns.db and self.frame then ns.db.uiShown = self.frame:IsShown() end
end

function UI:ShouldBeVisible(db, inCombat, hasHostile, placing)
	if not db or not db.enabled then return false end
	if placing then return true end

	local vis = db.visibility
	if vis == "always" then return true end
	if vis == "target" then return inCombat or hasHostile end
	if vis == "combat" then return inCombat end

	if db.combatOnly ~= false then return inCombat end
	return db.showOutOfCombat or inCombat or hasHostile
end

-- Click-to-cast: a secure button anchored over the main icon, parented to
-- UIParent (NEVER to main/frame, otherwise main:SetScale() in StepAnimations
-- and frame:Show/Hide become protected in combat and trigger taint blocks).
function UI:BuildClickCast(frame, main, cooldown)
	local ok, btn = pcall(CreateFrame, "Button", nil, UIParent, "SecureActionButtonTemplate")
	if not ok or not btn then return end
	btn:SetAllPoints(main)
	if frame.GetFrameStrata then btn:SetFrameStrata(frame:GetFrameStrata()) end
	btn:SetFrameLevel(cooldown:GetFrameLevel() + 4)
	btn:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
	btn:RegisterForDrag("LeftButton")
	btn:EnableMouse(false)
	btn:HookScript("OnDragStart", function()
		if ns.db and not ns.db.locked then frame:StartMoving() end
	end)
	btn:HookScript("OnDragStop", function()
		frame:StopMovingOrSizing()
		UI:SavePosition()
	end)
	btn:HookScript("OnEnter", function(b)
		if not UI.clickSpell or not GameTooltip then return end
		GameTooltip:SetOwner(b, "ANCHOR_TOP")
		local text = "Click to cast " .. UI.clickSpell
		if UI.clickUnitName then
			text = text .. " on " .. UI.clickUnitName
		end
		GameTooltip:SetText(text)
		GameTooltip:Show()
	end)
	btn:HookScript("OnLeave", function()
		if GameTooltip then GameTooltip:Hide() end
	end)
	if RegisterStateDriver then
		pcall(RegisterStateDriver, btn, "visibility", "[combat] hide; show")
	end
	self.clickBtn = btn
end

-- Compact nameplate widget: main icon (34x34) + tiny NEXT icon (22x22) to its
-- left, anchored to the left of the selected enemy's nameplate. Parented to
-- UIParent so Blizzard nameplate taint/lockdown never blocks updates.
function UI:BuildNameplateWidget(classicFrame)
	local npFrame = CreateFrame("Frame", nil, UIParent)
	if classicFrame and classicFrame.GetFrameStrata then
		npFrame:SetFrameStrata(classicFrame:GetFrameStrata())
	end
	SetPixelSize(npFrame, 60, 34)
	npFrame:Hide()

	local npMain = CreateFrame("Frame", nil, npFrame)
	SetPixelSize(npMain, 34, 34)
	npMain:SetPoint("RIGHT", npFrame, "RIGHT", 0, 0)

	local npMainBorder = npMain:CreateTexture(nil, "BACKGROUND")
	npMainBorder:SetPoint("TOPLEFT", -1, 1)
	npMainBorder:SetPoint("BOTTOMRIGHT", 1, -1)
	npMainBorder:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.80)

	local npMainIcon = npMain:CreateTexture(nil, "ARTWORK")
	npMainIcon:SetAllPoints()
	npMainIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	local npCooldown = CreateFrame("Cooldown", nil, npMain, "CooldownFrameTemplate")
	npCooldown:SetAllPoints(npMain)
	npCooldown:SetDrawEdge(true)
	npCooldown:SetDrawBling(false)
	npCooldown:SetHideCountdownNumbers(true)
	npCooldown:SetSwipeColor(0, 0, 0, 0.65)
	npCooldown:Hide()

	local npMainKeyOverlay = CreateFrame("Frame", nil, npMain)
	npMainKeyOverlay:SetAllPoints(npMain)
	npMainKeyOverlay:SetFrameLevel(npCooldown:GetFrameLevel() + 2)
	local npMainKeyHolder, npMainKey = CreateKeybindPill(npMainKeyOverlay)

	local npNext = CreateFrame("Frame", nil, npFrame)
	SetPixelSize(npNext, 22, 22)
	npNext:SetPoint("RIGHT", npMain, "LEFT", -4, 0)

	local npNextBorder = npNext:CreateTexture(nil, "BACKGROUND")
	npNextBorder:SetPoint("TOPLEFT", -1, 1)
	npNextBorder:SetPoint("BOTTOMRIGHT", 1, -1)
	npNextBorder:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.38)

	local npNextIcon = npNext:CreateTexture(nil, "ARTWORK")
	npNextIcon:SetAllPoints()
	npNextIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	npNextIcon:SetAlpha(0.90)

	local npNextKeyHolder, npNextKey = CreateKeybindPill(npNext)

	local npRefresh = 0
	npFrame:SetScript("OnUpdate", function(_, elapsed)
		npRefresh = npRefresh + (elapsed or 0)
		if npRefresh >= 0.08 then
			npRefresh = 0
			self:Refresh()
		end
	end)

	self.npFrame = npFrame
	self.npMain = npMain
	self.npMainBorder = npMainBorder
	self.npMainIcon = npMainIcon
	self.npCooldown = npCooldown
	self.npMainKeyHolder = npMainKeyHolder
	self.npMainKey = npMainKey
	self.npNext = npNext
	self.npNextIcon = npNextIcon
	self.npNextKeyHolder = npNextKeyHolder
	self.npNextKey = npNextKey
end

function UI:GetTargetNameplate(db, hasHostile)
	if not db or not db.nameplateMode or not hasHostile then return nil end
	if not C_NamePlate or not C_NamePlate.GetNamePlateForUnit then return nil end
	local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, "target", false)
	if not ok or not plate or type(plate) ~= "table" then return nil end
	if type(plate.IsForbidden) == "function" then
		local okF, forbidden = pcall(plate.IsForbidden, plate)
		if not okF or forbidden then return nil end
	end
	if type(plate.IsVisible) == "function" then
		local okV, shown = pcall(plate.IsVisible, plate)
		if not okV or not shown then return nil end
	end
	return plate
end

function UI:UpdateClickCast(spell, targetUnit, targetName)
	local btn = self.clickBtn
	if not btn or InCombatLockdown() then return end
	local db = ns.db or {}
	local want = nil
	local wantUnit = nil
	if spell and db.clickToCast ~= false then
		want = spell
		wantUnit = targetUnit
	end
	self.clickUnitName = want and targetName or nil
	local active = (want ~= nil) and (self.frame and self.frame.IsShown and self.frame:IsShown() ~= false)
	if btn.EnableMouse then
		btn:EnableMouse(active and true or false)
	end
	if want == self.clickSpell and wantUnit == self.clickUnit then return end
	self.clickSpell = want
	self.clickUnit = wantUnit
	btn:SetAttribute("type", want and "spell" or nil)
	btn:SetAttribute("spell", want)
	btn:SetAttribute("unit", wantUnit)
end

function UI:RefreshInner()
	if not self.frame then return end

	local db = ns.db
	if not db or not db.enabled then
		self:SetDesiredVisible(false, true)
		return
	end

	local inCombat = self.combatFlag == true or InCombatLockdown()
	local hasHostile = UnitExists("target") and UnitCanAttack("player", "target") and true or false

	local tracker = ns:GetModule("CombatTracker")
	local queue = ns:GetModule("PriorityQueue")
	local engine = ns:GetModule("WeaponEngine")
	local keybinds = ns:GetModule("Keybinds")

	if not inCombat and tracker and GetTime() - (self.lastSealScan or 0) > 0.5 then
		self.lastSealScan = GetTime()
		tracker:RefreshSeal()
	end

	local missingBlessing = (not inCombat) and tracker and tracker.GetMissingBlessing and tracker:GetMissingBlessing() or nil
	local missingAura = (not inCombat) and tracker and tracker.GetMissingAura and tracker:GetMissingAura() or nil
	local missingGroupSpell, missingGroupUnit, missingGroupName
	if not inCombat and not missingBlessing and not missingAura and tracker and tracker.GetMissingGroupBlessing then
		missingGroupSpell, missingGroupUnit, missingGroupName = tracker:GetMissingGroupBlessing()
	end

	local placing = (not db.locked) and GetTime() < (self.revealUntil or 0)
	local hasReminder = (missingBlessing ~= nil) or (missingAura ~= nil) or (missingGroupSpell ~= nil)
	local targetPlate = (not hasReminder) and self:GetTargetNameplate(db, hasHostile) or nil
	local useNameplate = (targetPlate ~= nil) and (self.npFrame ~= nil)

	if useNameplate then
		self:SetDesiredVisible(false, true)
		self:UpdateClickCast(nil)
		if self.lastNpPlate ~= targetPlate then
			self.lastNpPlate = targetPlate
			self.npFrame:ClearAllPoints()
			self.npFrame:SetPoint("RIGHT", targetPlate, "LEFT", -8, 0)
		end
		self.npFrame:SetScale(db.scale or 1.0)
		self.npFrame:Show()
	else
		if self.npFrame then
			self.npFrame:Hide()
			self.lastNpPlate = nil
		end
		local visible = self:ShouldBeVisible(db, inCombat, hasHostile, placing) or hasReminder
		local desiredAlpha = (inCombat or placing or hasReminder) and 1.0 or IDLE_ALPHA

		self:SetDesiredVisible(visible, placing, desiredAlpha)
		if not visible then
			self:UpdateClickCast(nil)
			return
		end
	end

	self:UpdateManaBar()

	if self.lastPlacing ~= placing then
		self.lastPlacing = placing
		if placing then
			self.caption:SetText("UNLOCKED - DRAG")
			self.caption:SetTextColor(READY[1], READY[2], READY[3], 0.9)
		else
			self.caption:SetText("RETPULSE")
			self.caption:SetTextColor(GOLD[1], GOLD[2], GOLD[3], 0.40)
		end
	end

	local current, nextAction = queue:Evaluate()
	if missingBlessing then
		if missingAura then
			nextAction = missingAura
		elseif current and current ~= missingBlessing then
			nextAction = current
		end
		current = missingBlessing
	elseif missingAura then
		if current and current ~= missingAura then
			nextAction = current
		end
		current = missingAura
	elseif missingGroupSpell then
		if current and current ~= missingGroupSpell then
			nextAction = current
		end
		current = missingGroupSpell
	end

	local displayName = current
	if not useNameplate then
		self:UpdateClickCast(current, missingGroupSpell and missingGroupUnit or nil, missingGroupSpell and missingGroupName or nil)
	end
	if not displayName and not queue.hasTarget then
		displayName = tracker:GetActiveSeal()
	end

	local mainTex = displayName and Icon(displayName) or "Interface\\Icons\\INV_Shield_06"
	if self.lastMainTexture ~= mainTex then
		local hadPrev = self.lastMainTexture and self.lastMainTexture ~= false
		self.lastMainTexture = mainTex
		self.mainIcon:SetTexture(mainTex)
		if hadPrev and inCombat and current then
			self:TriggerSpellPop()
		end
	end

	local nextTexture = Icon(nextAction)
	if self.lastNextTexture ~= nextTexture then
		self.lastNextTexture = nextTexture
		self.nextIcon:SetTexture(nextTexture)
		local hasNext = nextTexture ~= nil
		self.nextFrame:SetShown(hasNext)
		self.nextLabel:SetShown(hasNext)
		self.chevron:SetShown(hasNext)
	end

	local showKeys = db.showKeybinds ~= false and keybinds ~= nil
	local mainKeyText = (showKeys and current) and (keybinds:GetForSpell(current) or "") or ""
	if self.lastMainKey ~= mainKeyText then
		self.lastMainKey = mainKeyText
		UpdateKeybindPill(self.mainKeyHolder, self.mainKey, mainKeyText)
	end
	local nextKeyText = (showKeys and nextAction) and (keybinds:GetForSpell(nextAction) or "") or ""
	if self.lastNextKey ~= nextKeyText then
		self.lastNextKey = nextKeyText
		UpdateKeybindPill(self.nextKeyHolder, self.nextKey, nextKeyText)
	end

	local trackerOn = (engine and engine.hasUnsealedWrath) or (db.twistWithoutTalent == true)
	self:SetTrackerVisible(trackerOn and true or false)

	local echoes = tracker:GetEchoes()
	self.targetEchoes = echoes
	local sealLeft = tracker:GetSealRemaining()

	local activeSeal = tracker:GetActiveSeal()
	local ready = queue:IsTwistReady(trackerOn)
	local warnSeal = activeSeal ~= nil and sealLeft ~= nil and sealLeft <= 3

	if current then
		self.label:SetText(SpellName(current))
	elseif displayName then
		self.label:SetText(SpellName(displayName))
	elseif not queue.hasTarget then
		self.label:SetText("No target")
	else
		self.label:SetText("")
	end

	local iconAlpha = 1
	local desaturate = false
	local statusText = ""
	local statusColor = GOLD

	local passiveStatus = (current == nil and displayName ~= nil)

	if missingBlessing and current == missingBlessing then
		statusText = "BUFF MISSING"
		statusColor = WARN
	elseif missingAura and current == missingAura then
		statusText = "AURA MISSING"
		statusColor = WARN
	elseif missingGroupSpell and current == missingGroupSpell then
		statusText = "BUFF: " .. tostring(missingGroupName or missingGroupUnit)
		statusColor = WARN
	elseif queue.currentIsInterrupt then
		statusText = "INTERRUPT"
		statusColor = WARN
	elseif ready then
		statusText = "SWAP NOW"
		statusColor = READY
	elseif warnSeal then
		statusText = string.format("SEAL %s", Fmt(sealLeft))
		statusColor = WARN
	elseif queue.currentIsProc then
		statusText = "PROC!"
		statusColor = READY
	elseif queue.currentNoMana then
		statusText = "Low mana"
		statusColor = OOM
	elseif queue.currentInRange == false then
		statusText = "Out of range"
		statusColor = OOR
	elseif queue.countdown and queue.countdown > 0 then
		statusText = string.format("Ready in %s", Fmt(queue.countdown))
		statusColor = MUTED
	elseif passiveStatus and sealLeft then
		statusText = string.format("Active  %s", Fmt(sealLeft))
		statusColor = { 0.45, 0.85, 0.55 }
	elseif activeSeal and sealLeft then
		statusText = string.format("%s  %s", activeSeal:gsub("^Seal of ", ""), Fmt(sealLeft))
		statusColor = MUTED
	end

	self.status:SetText(statusText)
	self.status:SetTextColor(statusColor[1], statusColor[2], statusColor[3])

	if not displayName then
		desaturate = true
		iconAlpha = 0.35
	elseif passiveStatus then
		iconAlpha = 0.55
	elseif queue.currentNoMana then
		iconAlpha = 0.72
	elseif queue.countdown and queue.countdown > 1.6 then
		desaturate = true
		iconAlpha = 0.6
	elseif queue.currentInRange == false then
		desaturate = true
		iconAlpha = 0.55
	end
	self.mainIcon:SetDesaturated(desaturate)
	self.mainIcon:SetAlpha(iconAlpha)
	if queue.currentNoMana then
		self.mainIcon:SetVertexColor(0.50, 0.70, 1.0, 1)
	else
		self.mainIcon:SetVertexColor(1, 1, 1, 1)
	end

	local maxEchoes = tracker:GetMaxEchoes()
	local remaining = tracker:GetEchoRemaining()
	local duration = tracker:GetEchoDuration()
	if remaining and duration > 0 then
		self.echoBar:SetStatusBarColor(GOLD[1], GOLD[2], GOLD[3], remaining < 4 and 0.55 or 0.95)
		self.echoText:SetText(string.format("%d/%d  %s", echoes, maxEchoes, Fmt(remaining)))
	else
		self.echoText:SetText(string.format("%d/%d", echoes, maxEchoes))
	end

	local appliedDurationObj = false
	if current and C_Spell and C_Spell.GetSpellCooldownDuration and self.cooldown.SetCooldownFromDurationObject then
		local okDur, durObj = pcall(C_Spell.GetSpellCooldownDuration, current, false)
		if okDur and durObj ~= nil then
			local okSet = pcall(self.cooldown.SetCooldownFromDurationObject, self.cooldown, durObj, true)
			if okSet then
				appliedDurationObj = true
				self.lastCdStart = nil
				self.lastCdDuration = nil
				self.lastCdSpell = current
				self.cooldown:Show()
			end
		end
	end

	if not appliedDurationObj then
		local cdStart, cdDuration = queue:GetCooldownWindow(current)
		if cdStart and cdDuration and cdDuration > 0 then
			if self.lastCdStart ~= cdStart or self.lastCdDuration ~= cdDuration or self.lastCdSpell ~= current then
				self.lastCdStart = cdStart
				self.lastCdDuration = cdDuration
				self.lastCdSpell = current
				self.cooldown:SetCooldown(cdStart, cdDuration)
			end
			self.cooldown:Show()
		else
			if self.lastCdStart ~= nil or self.lastCdSpell ~= nil then
				self.lastCdStart = nil
				self.lastCdDuration = nil
				self.lastCdSpell = nil
				self.cooldown:Clear()
			end
			self.cooldown:Hide()
		end
	end

	-- Mirror compact state onto the nameplate widget when active
	if useNameplate and self.npFrame then
		self.npMainIcon:SetTexture(mainTex)
		self.npMainIcon:SetDesaturated(desaturate)
		self.npMainIcon:SetAlpha(iconAlpha)
		if queue.currentNoMana then
			self.npMainIcon:SetVertexColor(0.50, 0.70, 1.0, 1)
		else
			self.npMainIcon:SetVertexColor(1, 1, 1, 1)
		end

		local borderCol = GOLD
		if queue.currentIsInterrupt or warnSeal then
			borderCol = WARN
		elseif ready or queue.currentIsProc then
			borderCol = READY
		elseif queue.currentNoMana then
			borderCol = OOM
		end
		self.npMainBorder:SetColorTexture(borderCol[1], borderCol[2], borderCol[3], 0.90)

		UpdateKeybindPill(self.npMainKeyHolder, self.npMainKey, mainKeyText)
		if nextTexture then
			self.npNextIcon:SetTexture(nextTexture)
			self.npNext:Show()
			UpdateKeybindPill(self.npNextKeyHolder, self.npNextKey, nextKeyText)
		else
			self.npNext:Hide()
		end

		if appliedDurationObj and current and C_Spell and C_Spell.GetSpellCooldownDuration and self.npCooldown.SetCooldownFromDurationObject then
			local okDur, durObj = pcall(C_Spell.GetSpellCooldownDuration, current, false)
			if okDur and durObj ~= nil then
				pcall(self.npCooldown.SetCooldownFromDurationObject, self.npCooldown, durObj, true)
				self.npCooldown:Show()
			end
		elseif self.lastCdStart and self.lastCdDuration and self.lastCdDuration > 0 then
			self.npCooldown:SetCooldown(self.lastCdStart, self.lastCdDuration)
			self.npCooldown:Show()
		else
			self.npCooldown:Clear()
			self.npCooldown:Hide()
		end
	end

	self:UpdateSwingRing(tracker, inCombat)

	if ready and not self.wasReady and db.sound ~= false then
		local kit = SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
		if kit then pcall(PlaySound, kit) end
	end
	self.wasReady = ready

	local fx = ns:GetModule("FX")
	if fx then
		fx:SetVisible(inCombat or hasHostile)
		if ready then
			fx:SetState("ready")
		elseif warnSeal then
			fx:SetState("warn")
		else
			fx:SetState("idle")
		end
		if echoes > (self.lastEchoes or 0) then
			fx:Spark(2)
		end
	end
	self.lastEchoes = echoes

	local phase = math.abs(math.sin(GetTime() * 4))
	local visualState = ready and "ready" or (warnSeal and "warn" or "idle")
	if self.lastVisualState ~= visualState then
		self.lastVisualState = visualState
		if visualState == "ready" then
			self.frame:SetBackdropBorderColor(READY[1], READY[2], READY[3], 0.85)
			self.accent:SetColorTexture(READY[1], READY[2], READY[3], 0.95)
			self.mainBorder:SetColorTexture(READY[1], READY[2], READY[3], 0.95)
		elseif visualState == "warn" then
			self.frame:SetBackdropBorderColor(WARN[1], WARN[2], WARN[3], 0.70)
			self.accent:SetColorTexture(WARN[1], WARN[2], WARN[3], 0.90)
			self.mainBorder:SetColorTexture(WARN[1], WARN[2], WARN[3], 0.85)
		else
			self.frame:SetBackdropBorderColor(GOLD_DIM[1], GOLD_DIM[2], GOLD_DIM[3], GOLD_DIM[4])
			self.accent:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.80)
			self.mainBorder:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.85)
		end
	end

	if visualState == "ready" then
		self.glow:SetVertexColor(READY[1], READY[2], READY[3], 0.16 + 0.24 * phase)
	elseif visualState == "warn" then
		self.glow:SetVertexColor(1.0, 0.45, 0.15, 0.10 + 0.18 * phase)
	else
		self.glow:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 0.05 + 0.07 * phase)
	end
end

function UI:SavePosition()
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
	local pos = ns.db and ns.db.position or ns.DefaultPosition()
	self.frame:ClearAllPoints()
	self.frame:SetPoint(pos.point or "BOTTOM", UIParent, pos.relativePoint or pos.point or "BOTTOM", pos.x or 0, pos.y or 220)
end

function UI:ApplyScale()
	if ns.db and ns.db.scale then self.frame:SetScale(ns.db.scale) end
end

function UI:ApplyLock()
	if not self.frame or not ns.db then return end
	self.frame:EnableMouse(not ns.db.locked)
end

function UI:ToggleVisibility()
	if not ns.db then return end
	ns.db.enabled = not ns.db.enabled
	self.consecutiveErrors = 0
	ns:NotifySetting("enabled", ns.db.enabled)
	if ns.db.enabled then
		ns:Print("HUD on")
	else
		ns:Print("HUD off")
	end
end

function UI:DebugLine()
	local db = ns.db or {}
	local placing = (not db.locked) and GetTime() < (self.revealUntil or 0)
	return string.format("ui shown=%s vis=%s combatFlag=%s locked=%s placing=%s reveal=%.0f scale=%.2f h=%d plate=1",
		tostring(self.frame and self.frame:IsShown()), tostring(db.visibility),
		tostring(self.combatFlag), tostring(db.locked),
		tostring(placing), (self.revealUntil or 0) - GetTime(),
		db.scale or 1, math.floor((self.frame and self.frame:GetHeight()) or 0))
end

function ns.SetLocked(locked)
	local ui = ns:GetModule("UI")
	if not locked and ui then
		ui.revealUntil = GetTime() + 60
	elseif locked and ui then
		ui.revealUntil = 0
	end
	if ui and ui.ApplyLock then ui:ApplyLock() end
	if ui and ui.Refresh then ui:Refresh() end
end

function ns.ApplyScale()
	local ui = ns:GetModule("UI")
	if ui and ui.ApplyScale then ui:ApplyScale() end
end

function ns.ApplyPosition()
	local ui = ns:GetModule("UI")
	if ui and ui.ApplyPosition then ui:ApplyPosition() end
end

function ns.ToggleVisibility()
	local ui = ns:GetModule("UI")
	if ui and ui.ToggleVisibility then ui:ToggleVisibility() end
end
