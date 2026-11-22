local addonName, ns = ...

local CombatTracker = ns:NewModule("CombatTracker")

-- Two independent things live here:
--   1. swing timing, from the client's own PLAYER_SWING event (real, not estimated)
--   2. Unsealed Wrath echo state.
--
-- Unsealed Wrath (spell 1310735) is a passive talent whose own aura is flagged
-- hidden, so the stacks are most likely counted server-side and never exposed.
-- We therefore read the aura when the client happens to expose it, and otherwise
-- keep our own count of swings that landed. Misses cannot be detected: the
-- combat log does not exist on this client, so the model can over-count.

local ECHO_DURATION = 15
local MAX_ECHOES = 3
local ECHO_AURA_ID = 1310735
local SEAL_DURATION = 30
local MISS_WINDOW = 0.9

CombatTracker.echoes = 0
CombatTracker.activeSeal = nil
CombatTracker.lastEchoAt = nil
CombatTracker.lastSealAtSwing = nil
CombatTracker.auraReadable = nil
CombatTracker.seenSeals = {}
CombatTracker.swingsTotal = 0
CombatTracker.swingsMissed = 0

CombatTracker.swingStart = nil
CombatTracker.swingDuration = nil
CombatTracker.swingKnown = false



function CombatTracker:OnLogin()
	self:Reset()
	local engine = ns:GetModule("WeaponEngine")
	self.lastWeaponItemID = engine and engine.weaponItemID or nil

	ns:On("PLAYER_SWING", function(_, duration, swingType)
		self:OnSwing(duration, swingType)
	end)

	ns:On("UNIT_ATTACK_SPEED", function(_, unit)
		if unit == "player" then self:ResetSwing() end
	end)

	ns:On("WEAPON_SLOT_CHANGED", function()
		self:ResetSwing()
	end)

	ns:On("UNIT_INVENTORY_CHANGED", function(_, unit)
		if unit == "player" then self:OnWeaponChanged() end
	end)

	ns:On("UNIT_AURA", function(_, unit)
		if unit == "player" then self:RefreshSeal() end
	end)

	ns:On("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, _, spellID)
		if unit == "player" then self:OnSpellCast(spellID) end
	end)

	ns:On("PLAYER_REGEN_DISABLED", function()
		self.swingsWithSeal = 0
	end)

	ns:On("UNIT_COMBAT", function(_, unit, action)
		self:OnUnitCombat(unit, action)
	end)

	ns:On("COOLDOWN_VIEWER_DATA_LOADED", function()
		self.cdmAttempts = 0
		self:RefreshCdm()
	end)

	ns:On("PLAYER_REGEN_ENABLED", function()
		-- No swings outside combat: drop the ring instead of leaving a finished
		-- cooldown on the icon, which is what made it flash.
		self:ResetSwing()
		self.lastSwingEventAt = nil
		self.glowingSpells = {}
		self.targetCasting = false
		self.judgedCrusader = false
		-- Retry the Cooldown Manager scan a few times, then stop walking UIParent.
		if (not self.cdmFrames or #self.cdmFrames == 0) and (self.cdmAttempts or 0) < 4 then
			self:RefreshCdm()
		end
	end)

	self.glowingSpells = {}
	ns:On("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", function(_, spellID)
		self:SetSpellGlow(spellID, true)
	end)
	ns:On("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", function(_, spellID)
		self:SetSpellGlow(spellID, false)
	end)

	C_Timer.After(8, function()
		if (not self.cdmFrames or #self.cdmFrames == 0) and (self.cdmAttempts or 0) < 4 then
			self:RefreshCdm()
		end
	end)

	ns:On("PLAYER_TARGET_CHANGED", function()
		self.targetInRange = nil
		self.targetInRangeAt = nil
		self.targetRangeFromEvent = false
		self.targetCasting = false
		self.judgedCrusader = false
	end)

	local function OnTargetCastStart(_, unit)
		if unit == "target" then self.targetCasting = true end
	end
	local function OnTargetCastEnd(_, unit)
		if unit == "target" then self.targetCasting = false end
	end
	ns:On("UNIT_SPELLCAST_START", OnTargetCastStart)
	ns:On("UNIT_SPELLCAST_CHANNEL_START", OnTargetCastStart)
	ns:On("UNIT_SPELLCAST_STOP", OnTargetCastEnd)
	ns:On("UNIT_SPELLCAST_INTERRUPTED", OnTargetCastEnd)
	ns:On("UNIT_SPELLCAST_FAILED", OnTargetCastEnd)
	ns:On("UNIT_SPELLCAST_CHANNEL_STOP", OnTargetCastEnd)
	ns:On("UNIT_SPELLCAST_SUCCEEDED", function(_, unit)
		if unit == "target" then self.targetCasting = false end
	end)

	if C_SwingTimer and C_SwingTimer.EnableRangeCheck and Enum and Enum.PlayerSwingType then
		pcall(C_SwingTimer.EnableRangeCheck, Enum.PlayerSwingType.MainHand, true)
	end

	ns:On("PLAYER_SWING_RANGE_UPDATE", function(_, swingType, isInRange, checksRange)
		local mainHand = Enum and Enum.PlayerSwingType and Enum.PlayerSwingType.MainHand
		if mainHand ~= nil and swingType ~= nil and swingType ~= mainHand then return end
		if not ns.IsReadable(checksRange) or not checksRange then return end
		if not ns.IsReadable(isInRange) then return end
		self.targetInRange = isInRange and true or false
		self.targetInRangeAt = GetTime()
		self.targetRangeFromEvent = true
	end)

	self:RefreshSeal()
end

function CombatTracker:Reset()
	self.echoes = 0
	self.activeSeal = nil
	self.activeSealID = nil
	self.sealExpiresAt = nil
	self.lastEchoAt = nil
	self.lastSealAtSwing = nil
	self.swingsWithSeal = 0
	self:ResetSwing()
end

-------------------------------------------------------------------------------
-- Swing timing
-------------------------------------------------------------------------------
local MISS_EVENTS = {
	MISS = true,
	DODGE = true,
	PARRY = true,
	IMMUNE = true,
	DEFLECT = true,
	EVADE = true,
}

function CombatTracker:OnSwing(duration, swingType)
	-- A swing event that lands after the fight is over (the client sends one when
	-- a swing finishes) would draw a timer on an idle icon.
	if not InCombatLockdown() then return end

	local mainHand = Enum and Enum.PlayerSwingType and Enum.PlayerSwingType.MainHand
	if mainHand ~= nil and swingType ~= nil and swingType ~= mainHand then
		return
	end

	local now = GetTime()

	-- The client sometimes fires a second swing event mid-cycle. If the current
	-- swing has not finished, the event cannot be a new swing, so drop it:
	-- restarting the ring there is exactly what made it look faster.
	local remaining = self:GetSwingRemaining()
	if self.swingKnown and remaining and remaining > 0.25 then
		self.swingRejected = (self.swingRejected or 0) + 1
		return
	end

	self.lastSwingEventAt = now
	self.swingAccepted = (self.swingAccepted or 0) + 1

	if ns.IsReadable(duration) then
		self.swingStart = now
		self.swingDuration = duration
		self.swingKnown = true
	end

	self.swingEvents = (self.swingEvents or 0) + 1

	-- An echo is only stored by a swing that lands, and the outcome arrives as a
	-- UNIT_COMBAT event a moment later. Count on confirmation, not on the swing.
	local pending = { at = GetTime(), seal = self:GetActiveSeal(), missed = false }
	self.pendingSwing = pending
	C_Timer.After(MISS_WINDOW, function()
		self:ConfirmSwing(pending)
	end)
end

-- Target-side combat result. Only misses matter here: a landed hit is the
-- absence of a miss event, so this is a one-way flag.
function CombatTracker:OnUnitCombat(unit, action)
	if unit ~= "target" or not MISS_EVENTS[action] then return end
	local pending = self.pendingSwing
	if pending and not pending.missed and (GetTime() - pending.at) <= MISS_WINDOW then
		pending.missed = true
	end
end

function CombatTracker:ConfirmSwing(pending)
	if self.pendingSwing ~= pending then return end
	self.pendingSwing = nil

	self.swingsTotal = (self.swingsTotal or 0) + 1
	if pending.missed then
		self.swingsMissed = (self.swingsMissed or 0) + 1
	end

	if not pending.missed then
		self:CountEcho()
	end

	local diag = ns:GetModule("Diag")
	if diag and diag.t0 then
		diag:Add("SWINGRESULT",
			pending.missed and "no-echo" or "echo",
			"seal=" .. tostring(pending.seal or "none"),
			"model=" .. tostring(self.echoes),
			"total=" .. tostring(self.swingsTotal),
			"missed=" .. tostring(self.swingsMissed))
	end
end

function CombatTracker:ResetSwing()
	self.swingStart = nil
	self.swingDuration = nil
	self.swingKnown = false
end

function CombatTracker:GetSwingRemaining()
	if not self.swingKnown or not self.swingStart or not self.swingDuration then
		return nil
	end
	local remaining = self.swingStart + self.swingDuration - GetTime()
	if remaining < 0 then return 0 end
	return remaining
end

-- A global can still finish before the next white swing.
function CombatTracker:IsSwingWindowOpen(gcd)
	local remaining = self:GetSwingRemaining()
	if remaining == nil then return true end
	return remaining > (gcd or 1.5)
end

function CombatTracker:GetSwingProgress()
	local remaining = self:GetSwingRemaining()
	if not remaining or not self.swingDuration or self.swingDuration <= 0 then return nil end
	local progress = 1 - (remaining / self.swingDuration)
	if progress < 0 then return 0 end
	if progress > 1 then return 1 end
	return progress
end

-------------------------------------------------------------------------------
-- Active seal
-------------------------------------------------------------------------------
function CombatTracker:RefreshSeal()
	if InCombatLockdown() then
		-- Auras are unreadable while tainted in combat; cast tracking covers this.
		return
	end
	if not C_UnitAuras or not C_UnitAuras.GetAuraDataByIndex then return end

	-- Rank-proof: the buff's spell ID changes per rank, its name does not.
	-- In combat the client may hand back secret aura data; then this scan proves
	-- nothing and must not wipe what the cast tracker already knows.
	local sawReadable = false
	local foundSeal = false
	local foundBlessings = {}
	for i = 1, 40 do
		local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
		if not ok or not aura then break end

		local name = aura.name
		if name ~= nil and not ns.IsSecret(name) then
			sawReadable = true
			if self:IsBlessingName(name) then
				foundBlessings[name] = true
			elseif not foundSeal and self:IsSealName(name) then
				foundSeal = true
				self.activeSeal = name
				self.activeSealID = aura.spellId
				self.seenSeals[name] = true
				local expiry = aura.expirationTime
				if ns.IsReadable(expiry) and expiry > GetTime() then
					self.sealExpiresAt = expiry
				else
					-- Auras may report 0 for "no expiration"; never treat that as expired.
					self.sealExpiresAt = GetTime() + SEAL_DURATION
				end
			end
		end
	end

	-- Out of combat we scanned the full player buff list: update blessings map.
	if not InCombatLockdown() then
		self.activeBlessings = foundBlessings
		if not foundSeal and sawReadable then
			self.activeSeal = nil
			self.activeSealID = nil
			self.sealExpiresAt = nil
		end
	end
end

-- Cast tracking is the in-combat fallback: cast events and spell IDs stay
-- readable even when aura names are secret.
function CombatTracker:OnSpellCast(spellID)
	if type(spellID) ~= "number" then return end
	if not C_Spell or not C_Spell.GetSpellInfo then return end

	local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
	if not ok or type(info) ~= "table" or type(info.name) ~= "string" then return end

	local name = info.name
	if name == ns.SPELLS.JUDGEMENT and self:GetActiveSeal() == ns.SPELLS.SEAL_CRUSADER then
		self.judgedCrusader = true
	end
	if self:IsBlessingName(name) then
		self.activeBlessings = self.activeBlessings or {}
		self.activeBlessings[name] = true
		return
	end
	if not self:IsSealName(name) then return end

	self.sealCasts = (self.sealCasts or 0) + 1
	self.lastCastName = name
	self.activeSeal = name
	self.activeSealID = spellID
	self.seenSeals[name] = true
	self.sealExpiresAt = GetTime() + SEAL_DURATION
end

-- Any damage-dealing seal counts, plus any other seal, so the HUD never nags
-- the player to cast a seal that is already up.
function CombatTracker:IsSealName(name)
	return type(name) == "string" and name:find("^Seal of ") ~= nil
end

function CombatTracker:IsBlessingName(name)
	return type(name) == "string" and (name:find("^Blessing of ") ~= nil or name:find("^Greater Blessing of ") ~= nil)
end

local function IsSpellKnownByName(name)
	if not name then return false end
	if C_Spell and C_Spell.GetSpellIDForSpellIdentifier and C_SpellBook and C_SpellBook.IsSpellKnown then
		local okId, id = pcall(C_Spell.GetSpellIDForSpellIdentifier, name)
		if okId and type(id) == "number" and not ns.IsSecret(id) then
			local okK, known = pcall(C_SpellBook.IsSpellKnown, id)
			return okK and known and true or false
		end
	end
	return false
end

function CombatTracker:GetMissingBlessing()
	if InCombatLockdown() then return nil end
	if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then return nil end

	local pref = (ns.db and ns.db.preferredBlessing) or "auto"
	if pref == "off" then return nil end

	local active = self.activeBlessings or {}

	if pref == "auto" then
		-- Satisfied if any Blessing (or Greater Blessing) is already on the player.
		for _ in pairs(active) do return nil end
		local order = {
			ns.SPELLS.BLESSING_KINGS,
			ns.SPELLS.BLESSING_MIGHT,
			ns.SPELLS.BLESSING_WISDOM,
		}
		for _, spellName in ipairs(order) do
			if IsSpellKnownByName(spellName) then
				return spellName
			end
		end
		return nil
	end

	local map = {
		kings = ns.SPELLS.BLESSING_KINGS,
		might = ns.SPELLS.BLESSING_MIGHT,
		wisdom = ns.SPELLS.BLESSING_WISDOM,
	}
	local desired = map[pref]
	if not desired or not IsSpellKnownByName(desired) then return nil end
	if active[desired] or active["Greater " .. desired] then return nil end
	return desired
end

function CombatTracker:IsSealAvailable(name)
	if not name then return false end
	if self.seenSeals[name] then return true end
	if C_Spell and C_Spell.GetSpellIDForSpellIdentifier and C_SpellBook and C_SpellBook.IsSpellKnown then
		local id = C_Spell.GetSpellIDForSpellIdentifier(name)
		if type(id) == "number" then
			return C_SpellBook.IsSpellKnown(id) and true or false
		end
	end
	return false
end

function CombatTracker:GetActiveSeal()
	if self.activeSeal and self.sealExpiresAt and GetTime() > self.sealExpiresAt then
		self.activeSeal = nil
		self.activeSealID = nil
		self.sealExpiresAt = nil
	end
	return self.activeSeal
end

function CombatTracker:GetActiveSealID()
	return self.activeSealID
end

-- Swings landed since the active seal last changed. The detonation swing is the
-- first one, so the queue waits for it before sending the player back.
function CombatTracker:GetSwingsWithSeal()
	return self.swingsWithSeal or 0
end

-------------------------------------------------------------------------------
-- Weapon swap: a main-hand change wipes every echo
-------------------------------------------------------------------------------
function CombatTracker:OnWeaponChanged()
	local engine = ns:GetModule("WeaponEngine")
	local previous = self.lastWeaponItemID
	engine:ReadWeapon()
	local current = engine.weaponItemID
	self.lastWeaponItemID = current

	self:ResetSwing()

	if previous ~= nil and current ~= previous then
		self.echoes = 0
		self.lastEchoAt = nil
		self.lastSealAtSwing = nil
		self.swingsWithSeal = 0
	end
end

-------------------------------------------------------------------------------
-- Echoes
-------------------------------------------------------------------------------
-- The client's own stacks, when it exposes them. Returns nil when unreadable.
function CombatTracker:ReadAuraEchoes()
	-- Best source: Blizzard's Cooldown Manager, which keeps aura data for the
	-- talent and exposes it through its own widgets (readable where raw auras
	-- are blocked to tainted code in combat).
	local cdmStacks = self:ReadCdmEchoes()
	if cdmStacks then
		self.auraReadable = true
		if cdmStacks > MAX_ECHOES then cdmStacks = MAX_ECHOES end
		return cdmStacks
	end

	if not C_UnitAuras or not C_UnitAuras.GetPlayerAuraBySpellID then return nil end

	local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, ECHO_AURA_ID)
	if not ok or not aura then
		self.auraReadable = false
		return nil
	end

	local stacks = aura.applications
	if not ns.IsReadable(stacks) then
		self.auraReadable = false
		return nil
	end

	self.auraReadable = true
	if stacks < 0 then stacks = 0 end
	if stacks > MAX_ECHOES then stacks = MAX_ECHOES end
	return stacks
end

-------------------------------------------------------------------------------
-- Cooldown Manager bridge
-------------------------------------------------------------------------------
local CDM_VIEWER_NAMES = {
	"BuffIconCooldownViewer",
	"BuffBarCooldownViewer",
	"EssentialCooldownViewer",
	"UtilityCooldownViewer",
}

local function IsFrameForbidden(frame)
	if type(frame) ~= "table" then return true end
	if type(frame.IsForbidden) == "function" then
		local ok, forbidden = pcall(frame.IsForbidden, frame)
		if not ok or forbidden then return true end
	end
	return false
end

local function ReadFieldSafe(obj, key)
	local ok, val = pcall(function() return obj[key] end)
	if not ok then return nil end
	return val
end

function CombatTracker:RefreshCdm()
	self.cdmAttempts = (self.cdmAttempts or 0) + 1

	if not C_CooldownViewer or not C_CooldownViewer.GetCooldownViewerCategorySet then
		self.cdmReport = "C_CooldownViewer missing"
		return
	end

	local ids = {}
	for category = 0, 8 do
		local ok, list = pcall(C_CooldownViewer.GetCooldownViewerCategorySet, category, true)
		if ok and type(list) == "table" then
			for _, cooldownID in ipairs(list) do
				local okInfo, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cooldownID)
				if okInfo and type(info) == "table" then
					local match = info.spellID == ECHO_AURA_ID
					if not match and type(info.linkedSpellIDs) == "table" then
						for _, linked in ipairs(info.linkedSpellIDs) do
							if linked == ECHO_AURA_ID then
								match = true
								break
							end
						end
					end
					if match then ids[cooldownID] = true end
				end
			end
		end
	end

	local idCount = 0
	for _ in pairs(ids) do idCount = idCount + 1 end
	if idCount == 0 then
		self.cdmReport = "no cooldown id for the talent"
		return
	end

	local frames = {}
	local seen = {}
	local scanned = 0

	local function Scan(frame, depth)
		if depth > 6 or scanned > 2500 then return end
		if IsFrameForbidden(frame) or seen[frame] then return end
		seen[frame] = true
		scanned = scanned + 1

		local cooldownID = ReadFieldSafe(frame, "cooldownID")
		if type(cooldownID) == "number" and ids[cooldownID] then
			frames[#frames + 1] = frame
		else
			local item = ReadFieldSafe(frame, "itemData")
			if type(item) == "table" then
				local itemCdID = ReadFieldSafe(item, "cooldownID")
				if type(itemCdID) == "number" and ids[itemCdID] then
					frames[#frames + 1] = frame
				end
			end
		end

		local getChildren = ReadFieldSafe(frame, "GetChildren")
		if type(getChildren) ~= "function" then return end
		local okChildren, children = pcall(function() return { getChildren(frame) } end)
		if not okChildren or type(children) ~= "table" then return end
		for i = 1, #children do
			Scan(children[i], depth + 1)
		end
	end

	-- Prefer Blizzard's dedicated Cooldown Viewer containers before touching UIParent.
	local roots = {}
	for _, name in ipairs(CDM_VIEWER_NAMES) do
		local viewer = _G[name]
		if viewer then roots[#roots + 1] = viewer end
	end
	if #roots == 0 and UIParent then
		roots[1] = UIParent
	end

	local okScan = true
	for _, root in ipairs(roots) do
		local ok = pcall(Scan, root, 0)
		if not ok then okScan = false end
	end

	self.cdmFrames = frames
	self.cdmReport = string.format("ids=%d frames=%d scanned=%d ok=%s",
		idCount, #frames, scanned, tostring(okScan))
end

function CombatTracker:ReadCdmEchoes()
	if not self.cdmFrames then self:RefreshCdm() end
	if not self.cdmFrames or #self.cdmFrames == 0 then return nil end

	for _, frame in ipairs(self.cdmFrames) do
		if not IsFrameForbidden(frame) then
			local item = ReadFieldSafe(frame, "itemData")
			local aura = type(item) == "table" and ReadFieldSafe(item, "auraDataCached") or nil
			if type(aura) == "table" then
				local stacks = ReadFieldSafe(aura, "applications")
				if ns.IsReadable(stacks) then
					local expiry = ReadFieldSafe(aura, "expirationTime")
					self.cdmExpiresAt = ns.IsReadable(expiry) and expiry or nil
					return stacks
				end
			end

			local charge = ReadFieldSafe(frame, "ChargeCount")
			if type(charge) == "table" and type(charge.GetText) == "function" then
				local ok, text = pcall(charge.GetText, charge)
				if ok and text and not ns.IsSecret(text) then
					local value = tonumber(text)
					if value then return value end
				end
			end
		end
	end

	return nil
end

function CombatTracker:IsInSwingRange()
	if self.targetRangeFromEvent and self.targetInRange ~= nil then
		return self.targetInRange
	end
	local now = GetTime()
	if self.targetInRange ~= nil and self.targetInRangeAt and (now - self.targetInRangeAt) < 0.15 then
		return self.targetInRange
	end

	local ok, inRange = pcall(function()
		if C_SwingTimer and C_SwingTimer.IsTargetWithinSwingRange and Enum and Enum.PlayerSwingType then
			return C_SwingTimer.IsTargetWithinSwingRange(Enum.PlayerSwingType.MainHand)
		end
		return nil
	end)

	self.targetInRangeAt = now
	if ok and inRange ~= nil and ns.IsReadable(inRange) then
		self.targetInRange = inRange and true or false
	else
		-- No answer: assume a target we can hit, the model is best-effort anyway.
		self.targetInRange = UnitExists("target") and not UnitIsDead("target") or false
	end
	return self.targetInRange
end

function CombatTracker:CountEcho()
	local engine = ns:GetModule("WeaponEngine")
	local db = ns.db or {}
	local hasUnsealedWrath = (engine and engine.hasUnsealedWrath == true) or (db.twistWithoutTalent == true)

	-- Without the talent there are no echoes at all; do not invent them.
	if not hasUnsealedWrath then
		self.echoes = 0
		self.lastEchoAt = nil
		return
	end

	local seal = self:GetActiveSeal()
	if not seal then
		self.echoes = 0
		return
	end

	-- A different seal than the one on the previous swing consumed every echo.
	if self.lastSealAtSwing ~= nil and self.lastSealAtSwing ~= seal then
		self.echoes = 0
		self.swingsWithSeal = 0
	else
		self.swingsWithSeal = (self.swingsWithSeal or 0) + 1
	end
	self.lastSealAtSwing = seal

	local auraStacks = self:ReadAuraEchoes()
	if auraStacks then
		self.echoes = auraStacks
		if auraStacks > 0 then self.lastEchoAt = GetTime() end
		return
	end

	if not self:IsInSwingRange() then return end
	if self.echoes >= MAX_ECHOES then return end

	self.echoes = self.echoes + 1
	self.lastEchoAt = GetTime()
end

function CombatTracker:GetEchoes()
	if self.lastEchoAt and (GetTime() - self.lastEchoAt) > ECHO_DURATION then
		self.echoes = 0
		self.lastEchoAt = nil
		self.lastSealAtSwing = nil
		self.swingsWithSeal = 0
	end
	return self.echoes
end

function CombatTracker:GetMaxEchoes()
	return MAX_ECHOES
end

function CombatTracker:GetEchoDuration()
	return ECHO_DURATION
end

function CombatTracker:GetEchoRemaining()
	if not self.lastEchoAt then return nil end
	local remaining = ECHO_DURATION - (GetTime() - self.lastEchoAt)
	if remaining < 0 then return 0 end
	return remaining
end

function CombatTracker:GetSealRemaining()
	if not self.sealExpiresAt then return nil end
	local remaining = self.sealExpiresAt - GetTime()
	if remaining < 0 then return 0 end
	return remaining
end

function CombatTracker:SetSpellGlow(spellID, glowing)
	if not ns.IsReadable(spellID) or type(spellID) ~= "number" then return end
	if not C_Spell or not C_Spell.GetSpellInfo then return end
	local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
	if not ok or type(info) ~= "table" or type(info.name) ~= "string" or ns.IsSecret(info.name) then return end
	self.glowingSpells = self.glowingSpells or {}
	self.glowingSpells[info.name] = glowing and true or nil
end

function CombatTracker:IsSpellGlowing(name)
	if not name then return false end
	if self.glowingSpells and self.glowingSpells[name] then return true end
	if C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed
		and C_Spell and C_Spell.GetSpellIDForSpellIdentifier then
		local okId, id = pcall(C_Spell.GetSpellIDForSpellIdentifier, name)
		if okId and type(id) == "number" and not ns.IsSecret(id) then
			local okOv, ov = pcall(C_SpellActivationOverlay.IsSpellOverlayed, id)
			if okOv and ns.IsReadable(ov) and ov then return true end
		end
	end
	return false
end

function CombatTracker:GetMeleeEnemyCount()
	local now = GetTime()
	if self.meleeEnemyCount ~= nil and self.meleeEnemyCountAt and (now - self.meleeEnemyCountAt) < 0.2 then
		return self.meleeEnemyCount
	end

	local count = 0
	if C_NamePlate and C_NamePlate.GetNamePlates then
		local ok, plates = pcall(C_NamePlate.GetNamePlates)
		if ok and type(plates) == "table" then
			for _, plate in ipairs(plates) do
				local unit = type(plate) == "table" and ReadFieldSafe(plate, "namePlateUnitToken") or nil
				if type(unit) == "string" and not ns.IsSecret(unit) then
					local hostile = UnitCanAttack and UnitCanAttack("player", unit)
					local dead = UnitIsDead and UnitIsDead(unit)
					local fighting = (not UnitAffectingCombat) or UnitAffectingCombat(unit)
					if hostile and not dead and fighting then
						local inMelee = false
						if C_Spell and C_Spell.IsSpellInRange then
							local okR, r = pcall(C_Spell.IsSpellInRange, ns.SPELLS.HOLY_STRIKE, unit)
							if okR and ns.IsReadable(r) and r then inMelee = true end
						end
						if inMelee then
							count = count + 1
						end
					end
				end
			end
		end
	end

	self.meleeEnemyCount = count
	self.meleeEnemyCountAt = now
	return count
end

function CombatTracker:IsTargetCastingInterruptible()
	if not UnitExists("target") or not UnitCanAttack("player", "target") then
		return false
	end
	if UnitCastingInfo then
		local ok, castName, _, _, _, _, _, _, notInterruptible = pcall(UnitCastingInfo, "target")
		if ok and castName ~= nil then
			if ns.IsReadable(notInterruptible) and notInterruptible == true then
				return false
			end
			return true
		end
	end
	if UnitChannelInfo then
		local ok, chanName, _, _, _, _, _, notInterruptible = pcall(UnitChannelInfo, "target")
		if ok and chanName ~= nil then
			if ns.IsReadable(notInterruptible) and notInterruptible == true then
				return false
			end
			return true
		end
	end
	if not UnitCastingInfo and not UnitChannelInfo then
		return self.targetCasting == true
	end
	return false
end

function CombatTracker:HasJudgedCrusader()
	return self.judgedCrusader == true
end

function CombatTracker:DebugLine()
	local sealLeft = self:GetSealRemaining()
	return string.format("trk seal=%s left=%s echoes=%d swings=%d missed=%d aura=%s cdm=%s",
		tostring(self:GetActiveSeal()),
		sealLeft and string.format("%.1f", sealLeft) or "?",
		self:GetEchoes(),
		self.swingsTotal or 0,
		self.swingsMissed or 0,
		tostring(self.auraReadable),
		tostring(self.cdmReport))
end
