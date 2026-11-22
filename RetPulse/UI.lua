local addonName, ns = ...

local UI = ns:NewModule("UI")

-- Modern Retribution Paladin HUD:
--   glass plate : deep obsidian gradient with razor-thin top sheen + state-reactive accent
--   top row     : three diamond echo pips, smooth 60 FPS decay bar, status/caption
--   left        : main action icon with spell-change pulse, real CD swipe, keybind pill
--   center      : bold spell title + clean status/countdown line
--   right       : subtle chevron + next action icon with keybind pill
--   bottom edge : 60 FPS auto-attack swing bar with a 1.5s GCD twist-window tick

local GOLD       = { 0.94, 0.78, 0.38 }
local GOLD_DIM   = { 0.94, 0.78, 0.38, 0.32 }
local IVORY      = { 0.96, 0.95, 0.91 }
local MUTED      = { 0.72, 0.70, 0.65 }
local READY      = { 0.62, 1.00, 0.32 }
local WARN       = { 1.00, 0.60, 0.20 }
local OOR        = { 1.00, 0.42, 0.38 }
local OOM        = { 0.38, 0.68, 1.00 }

local PANEL_W, PANEL_H = 266, 90
local PANEL_H_COMPACT = 68
local MAIN_SIZE = 46
local NEXT_SIZE = 32
local PIP_SIZE = 8
local FADE_SPEED = 8.0
local IDLE_ALPHA = 0.38
local POP_DURATION = 0.16
local FLASH_DURATION = 0.20
local MAX_CONSECUTIVE_ERRORS = 5

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

local function SetPixelSize(region, w, h)
	if PixelUtil and PixelUtil.SetSize then
		PixelUtil.SetSize(region, w, h)
	else
		region:SetSize(w, h)
	end
end

local function SetPixelHeight(region, h)
	if PixelUtil and PixelUtil.SetHeight then
		PixelUtil.SetHeight(region, h)
	else
		region:SetHeight(h)
	end
end

local function CreateKeybindPill(parent)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -1, -1)
	SetPixelSize(holder, 20, 13)
	holder:Hide()

	local bg = holder:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0.02, 0.02, 0.04, 0.78)

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

	-- A hidden frame gets no OnUpdate, so visibility must also be event driven,
	-- otherwise the HUD never learns that combat started. The flag mirrors the
	-- events because InCombatLockdown can still report false inside them.
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

function UI:Build()
	local frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
	SetPixelSize(frame, PANEL_W, PANEL_H)
	frame:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8X8",
		edgeFile = "Interface\\Buttons\\WHITE8X8",
		tile = false,
		edgeSize = 1,
	})
	frame:SetBackdropColor(0.05, 0.05, 0.07, 0.86)
	frame:SetBackdropBorderColor(GOLD_DIM[1], GOLD_DIM[2], GOLD_DIM[3], GOLD_DIM[4])
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetClampedToScreen(true)
	frame:SetClipsChildren(true)

	frame:SetScript("OnDragStart", function(f)
		if ns.db and not ns.db.locked then f:StartMoving() end
	end)
	frame:SetScript("OnDragStop", function(f)
		f:StopMovingOrSizing()
		UI:SavePosition()
	end)

	-- Subtle vertical glass gradient plate
	local bgGrad = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
	bgGrad:SetPoint("TOPLEFT", 1, -1)
	bgGrad:SetPoint("BOTTOMRIGHT", -1, 1)
	bgGrad:SetColorTexture(1, 1, 1, 1)
	if CreateColor and bgGrad.SetGradient then
		bgGrad:SetGradient("VERTICAL",
			CreateColor(0.03, 0.03, 0.05, 0.70),
			CreateColor(0.11, 0.10, 0.13, 0.45))
	else
		bgGrad:SetColorTexture(0.04, 0.04, 0.06, 0.45)
	end

	-- Razor-thin top sheen for modern depth
	local topSheen = frame:CreateTexture(nil, "BORDER", nil, 1)
	topSheen:SetPoint("TOPLEFT", 1, -1)
	topSheen:SetPoint("TOPRIGHT", -1, -1)
	SetPixelHeight(topSheen, 1)
	topSheen:SetColorTexture(1.0, 0.94, 0.78, 0.16)

	-- Left-edge state accent bar (gold idle, lime on SWAP NOW, amber on seal warning)
	local accent = frame:CreateTexture(nil, "BORDER", nil, 2)
	accent:SetPoint("TOPLEFT", 1, -1)
	accent:SetPoint("BOTTOMLEFT", 1, 4)
	accent:SetWidth(2)
	accent:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.85)

	-- Caption
	local caption = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	caption:SetPoint("TOPRIGHT", -8, -6)
	caption:SetText("RETPULSE")
	caption:SetTextColor(GOLD[1], GOLD[2], GOLD[3], 0.45)

	-- Diamond echo pips
	local pips = {}
	for i = 1, 3 do
		local pip = frame:CreateTexture(nil, "OVERLAY")
		SetPixelSize(pip, PIP_SIZE, PIP_SIZE)
		pip:SetPoint("TOPLEFT", 11 + (i - 1) * 13, -10)
		pip:SetRotation(math.rad(45))
		pip:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.16)
		pips[i] = pip
	end

	-- Echo decay bar
	local echoBar = CreateFrame("StatusBar", nil, frame)
	SetPixelSize(echoBar, 86, 4)
	echoBar:SetPoint("LEFT", pips[3], "RIGHT", 9, 0)
	echoBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
	echoBar:SetStatusBarColor(GOLD[1], GOLD[2], GOLD[3], 0.95)
	echoBar:SetMinMaxValues(0, 1)
	echoBar:SetValue(0)

	local echoTrack = echoBar:CreateTexture(nil, "BACKGROUND")
	echoTrack:SetAllPoints()
	echoTrack:SetColorTexture(1, 1, 1, 0.08)

	local echoText = echoBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	echoText:SetPoint("LEFT", echoBar, "RIGHT", 6, 0)
	echoText:SetTextColor(IVORY[1], IVORY[2], IVORY[3], 0.75)

	-- Main action icon
	local main = CreateFrame("Frame", nil, frame)
	SetPixelSize(main, MAIN_SIZE, MAIN_SIZE)
	main:SetPoint("BOTTOMLEFT", 10, 11)

	local mainBorder = main:CreateTexture(nil, "BACKGROUND")
	mainBorder:SetPoint("TOPLEFT", -1, 1)
	mainBorder:SetPoint("BOTTOMRIGHT", 1, -1)
	mainBorder:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.72)

	local mainIcon = main:CreateTexture(nil, "ARTWORK")
	mainIcon:SetAllPoints()
	mainIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	-- Subtle spell-change flash overlay
	local flash = main:CreateTexture(nil, "OVERLAY", nil, 5)
	flash:SetAllPoints()
	flash:SetColorTexture(1, 0.95, 0.75, 0)
	flash:SetBlendMode("ADD")

	-- Spell cooldown / GCD swipe over the main icon, synced to the actual
	-- recommended spell's cooldown (never the weapon swing timer).
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

	-- Auto-attack swing bar along the bottom edge of the panel (60 FPS smooth)
	local swingBar = CreateFrame("StatusBar", nil, frame)
	SetPixelHeight(swingBar, 3)
	swingBar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1, 1)
	swingBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
	swingBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
	swingBar:SetStatusBarColor(GOLD[1], GOLD[2], GOLD[3], 0.85)
	swingBar:SetMinMaxValues(0, 1)
	swingBar:SetValue(0)
	swingBar:Hide()

	local swingTrack = swingBar:CreateTexture(nil, "BACKGROUND")
	swingTrack:SetAllPoints()
	swingTrack:SetColorTexture(1, 1, 1, 0.07)

	-- 1.5s GCD twist-window marker on the swing bar
	local swingTick = swingBar:CreateTexture(nil, "OVERLAY", nil, 3)
	SetPixelSize(swingTick, 1, 5)
	swingTick:SetColorTexture(1, 1, 1, 0.65)
	swingTick:Hide()

	-- Razor-thin secret-safe mana bar (2px sapphire strip right above swingBar).
	-- Pipes raw UnitPower/UnitPowerMax straight into StatusBar without Lua math.
	local manaBar = CreateFrame("StatusBar", nil, frame)
	SetPixelHeight(manaBar, 2)
	manaBar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1, 5)
	manaBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 5)
	manaBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
	manaBar:SetStatusBarColor(0.24, 0.56, 0.96, 0.85)
	manaBar:SetMinMaxValues(0, 1)
	manaBar:SetValue(1)

	local manaTrack = manaBar:CreateTexture(nil, "BACKGROUND")
	manaTrack:SetAllPoints()
	manaTrack:SetColorTexture(1, 1, 1, 0.06)

	-- Holy glow behind the icon, used for SWAP NOW and for a seal about to expire.
	local glow = main:CreateTexture(nil, "BACKGROUND", nil, 2)
	glow:SetPoint("TOPLEFT", -6, 6)
	glow:SetPoint("BOTTOMRIGHT", 6, -6)
	glow:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0)
	glow:SetBlendMode("ADD")

	-- Spell title (prominent) + secondary status/timer line
	local label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	label:SetPoint("TOPLEFT", main, "TOPRIGHT", 10, -5)
	label:SetWidth(134)
	label:SetJustifyH("LEFT")
	label:SetWordWrap(false)
	label:SetTextColor(IVORY[1], IVORY[2], IVORY[3])
	if label.SetShadowOffset then
		label:SetShadowOffset(1, -1)
		label:SetShadowColor(0, 0, 0, 0.9)
	end
	label:SetText("")

	local status = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	status:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -4)
	status:SetWidth(134)
	status:SetJustifyH("LEFT")
	status:SetWordWrap(false)
	status:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
	status:SetText("")

	-- Subtle flow chevron between current action and NEXT
	local chevron = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	chevron:SetPoint("RIGHT", frame, "BOTTOMRIGHT", -46, 33)
	chevron:SetTextColor(GOLD[1], GOLD[2], GOLD[3], 0.45)
	chevron:SetText(">")
	chevron:Hide()

	-- Next action
	local nextFrame = CreateFrame("Frame", nil, frame)
	SetPixelSize(nextFrame, NEXT_SIZE, NEXT_SIZE)
	nextFrame:SetPoint("BOTTOMRIGHT", -10, 18)

	local nextBorder = nextFrame:CreateTexture(nil, "BACKGROUND")
	nextBorder:SetPoint("TOPLEFT", -1, 1)
	nextBorder:SetPoint("BOTTOMRIGHT", 1, -1)
	nextBorder:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.32)

	local nextIcon = nextFrame:CreateTexture(nil, "ARTWORK")
	nextIcon:SetAllPoints()
	nextIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	nextIcon:SetAlpha(0.88)

	local nextKeyHolder, nextKey = CreateKeybindPill(nextFrame)

	local nextLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	nextLabel:SetPoint("TOP", nextFrame, "BOTTOM", 0, -3)
	nextLabel:SetTextColor(MUTED[1], MUTED[2], MUTED[3], 0.7)
	nextLabel:SetText("NEXT")

	self.frame = frame
	local okClick, errClick = pcall(self.BuildClickCast, self, frame, main, cooldown)
	if not okClick then ns:RecordError("BuildClickCast", errClick) end
	self.caption = caption
	self.accent = accent
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
	self.swingBar = swingBar
	self.swingTick = swingTick
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

	local fx = ns:GetModule("FX")
	if fx then fx:Attach(main, MAIN_SIZE) end

	self.lastMainTexture = false
	self.lastNextTexture = false
	self.lastRefresh = 0
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

function UI:StepAnimations(elapsed)
	local dt = elapsed or 0
	self:StepFade(dt)

	-- Smooth spell-change scale pop & flash
	if self.popTime and self.popTime > 0 then
		self.popTime = math.max(0, self.popTime - dt)
		local t = self.popTime / POP_DURATION
		local scale = 1.0 + 0.08 * (t * t)
		if self.main then self.main:SetScale(scale) end
	elseif self.main and self.main:GetScale() ~= 1 then
		self.main:SetScale(1)
	end

	if self.flashTime and self.flashTime > 0 then
		self.flashTime = math.max(0, self.flashTime - dt)
		local alpha = 0.42 * (self.flashTime / FLASH_DURATION)
		if self.flash then self.flash:SetColorTexture(1, 0.95, 0.78, alpha) end
	elseif self.flash and self.flashTime == 0 then
		self.flashTime = -1
		self.flash:SetColorTexture(1, 0.95, 0.78, 0)
	end

	-- Smooth 60 FPS echo pip alpha transitions
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

	-- 60 FPS smooth swing bar and echo decay bar
	local tracker = ns:GetModule("CombatTracker")
	if not tracker then return end

	local inCombat = self.combatFlag == true or InCombatLockdown()
	local swingProgress = inCombat and tracker:GetSwingProgress() or nil
	if swingProgress ~= nil and self.swingBar then
		self.swingBar:SetValue(swingProgress)
		if not self.swingBar:IsShown() then self.swingBar:Show() end

		local dur = tracker.swingDuration
		if dur and dur > 1.5 and self.swingTick then
			local barWidth = self.swingBar:GetWidth()
			if barWidth and barWidth > 10 then
				local frac = 1 - (1.5 / dur)
				self.swingTick:SetPoint("CENTER", self.swingBar, "LEFT", barWidth * frac, 0)
				self.swingTick:Show()
			end
		elseif self.swingTick then
			self.swingTick:Hide()
		end
	elseif self.swingBar and self.swingBar:IsShown() then
		self.swingBar:SetValue(0)
		self.swingBar:Hide()
		if self.swingTick then self.swingTick:Hide() end
	end

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
	self.echoBar:SetShown(visible)
	self.echoText:SetShown(visible)

	-- Without echoes the widget collapses: no dead space above the icon.
	SetPixelHeight(self.frame, visible and PANEL_H or PANEL_H_COMPACT)
	self.main:ClearAllPoints()
	self.main:SetPoint("BOTTOMLEFT", 10, visible and 11 or 10)
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

	-- Fallback for any unmigrated profile
	if db.combatOnly ~= false then return inCombat end
	return db.showOutOfCombat or inCombat or hasHostile
end

-- Click-to-cast: a secure button over the main icon. Secure attributes cannot
-- change in combat, so the button is hidden by a state driver while in combat
-- (the HUD stays informative only) and re-armed out of combat.
function UI:BuildClickCast(frame, main, cooldown)
	local ok, btn = pcall(CreateFrame, "Button", nil, main, "SecureActionButtonTemplate")
	if not ok or not btn then return end
	btn:SetAllPoints(main)
	btn:SetFrameLevel(cooldown:GetFrameLevel() + 4)
	-- Register both edges: with the ActionButtonUseKeyDown CVar on, the secure
	-- handler only fires on the down edge and ignores an up-only registration.
	btn:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
	btn:RegisterForDrag("LeftButton")
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
		GameTooltip:SetText("Click to cast " .. UI.clickSpell)
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

function UI:UpdateClickCast(spell)
	local btn = self.clickBtn
	if not btn or InCombatLockdown() then return end
	local db = ns.db or {}
	local want = nil
	if spell and db.clickToCast ~= false then
		want = spell
	end
	if want == self.clickSpell then return end
	self.clickSpell = want
	btn:SetAttribute("type", want and "spell" or nil)
	btn:SetAttribute("spell", want)
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

	-- Unlocking reveals the HUD for a minute so it can be dragged even in combat-only mode.
	local placing = (not db.locked) and GetTime() < (self.revealUntil or 0)
	local hasReminder = (missingBlessing ~= nil) or (missingAura ~= nil)
	local visible = self:ShouldBeVisible(db, inCombat, hasHostile, placing) or hasReminder
	local desiredAlpha = (inCombat or placing or hasReminder) and 1.0 or IDLE_ALPHA

	self:SetDesiredVisible(visible, placing, desiredAlpha)
	if not visible then return end

	self:UpdateManaBar()

	if self.lastPlacing ~= placing then
		self.lastPlacing = placing
		if placing then
			self.caption:SetText("UNLOCKED - DRAG")
			self.caption:SetTextColor(READY[1], READY[2], READY[3], 0.9)
		else
			self.caption:SetText("RETPULSE")
			self.caption:SetTextColor(GOLD[1], GOLD[2], GOLD[3], 0.45)
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
	end

	-- With no hostile target the panel falls back to the active seal instead of
	-- an anonymous shield, so the HUD keeps telling you something useful.
	local displayName = current
	self:UpdateClickCast(current)	if not displayName and not queue.hasTarget then
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

	-- Keybind pills
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

	-- Tracker row visibility
	local trackerOn = (engine and engine.hasUnsealedWrath) or (db.twistWithoutTalent == true)
	self:SetTrackerVisible(trackerOn and true or false)

	local echoes = tracker:GetEchoes()
	self.targetEchoes = echoes
	local sealLeft = tracker:GetSealRemaining()

	local primaryName, primaryStacks, secondaryName = queue:GetSealPair()
	local activeSeal = tracker:GetActiveSeal()
	local ready = trackerOn and secondaryName ~= nil and echoes >= primaryStacks and activeSeal == primaryName
	local warnSeal = activeSeal ~= nil and sealLeft ~= nil and sealLeft <= 3

	-- Main spell title & clean secondary status line
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

	-- Echo text & color (bar value itself updates at 60 FPS in StepAnimations)
	local maxEchoes = tracker:GetMaxEchoes()
	local remaining = tracker:GetEchoRemaining()
	local duration = tracker:GetEchoDuration()
	if remaining and duration > 0 then
		self.echoBar:SetStatusBarColor(GOLD[1], GOLD[2], GOLD[3], remaining < 4 and 0.55 or 0.95)
		self.echoText:SetText(string.format("%d/%d  %s", echoes, maxEchoes, Fmt(remaining)))
	else
		self.echoText:SetText(string.format("%d/%d", echoes, maxEchoes))
	end

	-- Spell cooldown / GCD swipe: prefer the server's exact LuaDurationObject
	-- (C_Spell.GetSpellCooldownDuration -> SetCooldownFromDurationObject),
	-- falling back to the local cooldown clock when unavailable.
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

	-- Swing bar color & immediate visibility sync (value animates at 60 FPS in StepAnimations)
	local swingProgress = inCombat and tracker:GetSwingProgress() or nil
	if swingProgress ~= nil then
		self.swingBar:SetValue(swingProgress)
		if tracker:IsSwingWindowOpen(1.5) then
			self.swingBar:SetStatusBarColor(GOLD[1], GOLD[2], GOLD[3], 0.9)
		else
			self.swingBar:SetStatusBarColor(WARN[1], WARN[2], WARN[3], 0.8)
		end
		self.swingBar:Show()
	else
		self.swingBar:SetValue(0)
		self.swingBar:Hide()
		self.swingTick:Hide()
	end

	-- One click on the transition into SWAP NOW, not every frame.
	if ready and not self.wasReady and db.sound ~= false then
		local kit = SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
		if kit then pcall(PlaySound, kit) end
	end
	self.wasReady = ready

	local fx = ns:GetModule("FX")
	if fx then
		-- Effects live only while something is happening: no pulsing HUD in town.
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

	-- Visual alert state: border & accent update on state change; glow pulses smoothly.
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
			self.mainBorder:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.72)
		end
	end

	if visualState == "ready" then
		self.glow:SetColorTexture(READY[1], READY[2], READY[3], 0.12 + 0.24 * phase)
	elseif visualState == "warn" then
		self.glow:SetColorTexture(1.0, 0.45, 0.15, 0.08 + 0.18 * phase)
	else
		self.glow:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.04 + 0.05 * phase)
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
	local pos = ns.db and ns.db.position or { point = "BOTTOM", relativePoint = "BOTTOM", x = 0, y = 220 }
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
	return string.format("ui shown=%s vis=%s combatFlag=%s locked=%s placing=%s reveal=%.0f scale=%.2f h=%d",
		tostring(self.frame and self.frame:IsShown()), tostring(db.visibility),
		tostring(self.combatFlag), tostring(db.locked),
		tostring(placing), (self.revealUntil or 0) - GetTime(),
		db.scale or 1, math.floor((self.frame and self.frame:GetHeight()) or 0))
end

-- Thin call-throughs so slash commands and the options panel stay decoupled
-- from the UI module name.
function ns.SetLocked(locked)
	local ui = ns:GetModule("UI")
	if not locked and ui then
		-- Reveal the HUD for a minute so it can be dragged, even in combat-only mode.
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
