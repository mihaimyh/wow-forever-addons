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
		if unit == "player" then
			self.notFacingUntil = nil
			self:OnSpellCast(spellID)
		end
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
		self.notFacingUntil = nil
		if not InCombatLockdown() then
			self.judgedCrusader = false
		end
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
		self.notFacingUntil = nil
		if not InCombatLockdown() then
			self.judgedCrusader = false
		end
	end)

	ns:On("UI_ERROR_MESSAGE", function(_, _, message)
		if ns.db and ns.db.facingAlert == false then return end
		if type(message) ~= "string" or ns.IsSecret(message) then return end
		local lower = message:lower()
		local isFacingErr = (ERR_ATTACK_FACING and message == ERR_ATTACK_FACING)
			or (SPELL_FAILED_UNIT_NOT_INFRONT and message == SPELL_FAILED_UNIT_NOT_INFRONT)
			or lower:find("facing", 1, true) ~= nil
			or lower:find("in front of you", 1, true) ~= nil
		if isFacingErr then
			self.notFacingUntil = GetTime() + 2.0
		end
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
		if mainHand ~= nil and swingType ~= nil and not ns.IsSecret(swingType) and swingType ~= mainHand then return end
		if not ns.IsReadable(checksRange) or not checksRange then return end
		if not ns.IsReadable(isInRange) then return end
		self.targetInRange = isInRange and true or false
		self.targetInRangeAt = GetTime()
		self.targetRangeFromEvent = true
	end)

	self.activeNameplates = {}
	ns:On("NAME_PLATE_UNIT_ADDED", function(_, unit)
		if type(unit) == "string" and not ns.IsSecret(unit) then
			self.activeNameplates[unit] = true
			self.meleeEnemyCountAt = nil
		end
	end)
	ns:On("NAME_PLATE_UNIT_REMOVED", function(_, unit)
		if type(unit) == "string" and not ns.IsSecret(unit) then
			self.activeNameplates[unit] = nil
			self.meleeEnemyCountAt = nil
		end
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
	if mainHand ~= nil and swingType ~= nil and not ns.IsSecret(swingType) and swingType ~= mainHand then
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
	self.notFacingUntil = nil

	if ns.IsReadable(duration) then
		self.swingStart = now
		self.swingDuration = duration
		self.swingKnown = true
	end

	self.swingEvents = (self.swingEvents or 0) + 1

	-- An echo is only stored by a swing that lands, and the outcome arrives as a
	-- UNIT_COMBAT event a moment later. Count on confirmation, not on the swing.
	-- A faster-than-window swing would overwrite the pending one and lose its
	-- echo: settle the previous swing first.
	if self.pendingSwing then
		self:ConfirmSwing(self.pendingSwing)
	end

	local pending = { at = GetTime(), seal = self:GetActiveSeal(), missed = false }
	self.pendingSwing = pending
	C_Timer.After(MISS_WINDOW, function()
		self:ConfirmSwing(pending)
	end)
end

-- Target-side combat result. Only misses matter here: a landed hit is the
-- absence of a miss event, so this is a one-way flag.
function CombatTracker:OnUnitCombat(unit, action)
	if unit ~= "target" or ns.IsSecret(action) or type(action) ~= "string" or not MISS_EVENTS[action] then return end
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
		self:CountEcho(pending.seal)
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
	local scanComplete = false
	local foundOwnAura = false
	local foundAuras = {}
	local foundBlessings = {}
	local foundOwnBlessings = {}
	for i = 1, 40 do
		local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
		if not ok then break end
		if not aura then
			-- A clean, readable end of the list (even an empty one) proves the
			-- player has no further buffs, so a cancelled seal can be cleared.
			scanComplete = true
			break
		end

		local name = aura.name
		if name ~= nil and not ns.IsSecret(name) then
			sawReadable = true
			local src = aura.sourceUnit
			local fromPlayer = (src ~= nil and not ns.IsSecret(src) and src == "player")
			if self:IsBlessingName(name) then
				foundBlessings[name] = true
				if fromPlayer then foundOwnBlessings[name] = true end
			elseif self:IsAuraName(name) then
				foundAuras[name] = true
				if fromPlayer then foundOwnAura = true end
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

	-- Out of combat we scanned the full player buff list: update blessings & aura state.
	if not InCombatLockdown() then
		self.activeBlessings = foundBlessings
		self.ownBlessings = foundOwnBlessings
		self.activeAuras = foundAuras
		self.hasOwnAura = foundOwnAura
		if not foundSeal and (sawReadable or scanComplete) then
			self.activeSeal = nil
			self.activeSealID = nil
			self.sealExpiresAt = nil
		end
	end
end

-- Cast tracking is the in-combat fallback: cast events and spell IDs stay
-- readable even when aura names are secret.
function CombatTracker:OnSpellCast(spellID)
	local name = ns.GetSpellNameByID(spellID)
	if not name then return end

	if name == ns.SPELLS.JUDGEMENT and self:GetActiveSeal() == ns.SPELLS.SEAL_CRUSADER then
		self.judgedCrusader = true
	end
	if self:IsBlessingName(name) then
		self.activeBlessings = self.activeBlessings or {}
		self.ownBlessings = self.ownBlessings or {}
		self.activeBlessings[name] = true
		self.ownBlessings[name] = true
		return
	end
	if not self:IsSealName(name) then return end

	self.sealCasts = (self.sealCasts or 0) + 1
	self.lastCastName = name
	-- Swapping seals starts a fresh "swings with this seal" count: the
	-- detonation swing has not happened yet.
	if self.activeSeal ~= name then
		self.swingsWithSeal = 0
	end
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

function CombatTracker:IsAuraName(name)
	return type(name) == "string" and name:find(" Aura$") ~= nil
end

local IsSpellKnownByName = ns.IsSpellKnownByName

function CombatTracker:GetMissingBlessing()
	if InCombatLockdown() then return nil end
	if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then return nil end

	local pref = (ns.db and ns.db.preferredBlessing) or "auto"
	if pref == "off" then return nil end

	local active = self.activeBlessings or {}
	local own = self.ownBlessings or {}

	if pref == "auto" then
		-- Satisfied only once YOU have your own Blessing active on yourself.
		-- Another Paladin's Blessing (e.g. Wisdom) does not block your own Kings/Might,
		-- and we skip whichever Blessing another Paladin already gave you.
		for _ in pairs(own) do return nil end
		local order = {
			ns.SPELLS.BLESSING_KINGS,
			ns.SPELLS.BLESSING_MIGHT,
			ns.SPELLS.BLESSING_WISDOM,
		}
		for _, spellName in ipairs(order) do
			if IsSpellKnownByName(spellName) and not active[spellName] and not active["Greater " .. spellName] then
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

local CASTER_CLASSES = { MAGE = true, PRIEST = true, WARLOCK = true }
local PHYSICAL_CLASSES = { WARRIOR = true, ROGUE = true }

local function BlessingOrderForUnit(unit)
	local okC, _, classToken = pcall(UnitClass, unit)
	classToken = okC and ns.IsReadable(classToken) and classToken or nil

	local powerType
	if UnitPowerType then
		local okP, pt = pcall(UnitPowerType, unit)
		if okP and ns.IsReadable(pt) and type(pt) == "number" then
			powerType = pt
		end
	end

	-- Casters always prefer Kings -> Wisdom (never Might).
	if classToken and CASTER_CLASSES[classToken] then
		return { ns.SPELLS.BLESSING_KINGS, ns.SPELLS.BLESSING_WISDOM }
	end
	-- Pure rage/energy melee prefer Kings -> Might (never Wisdom).
	if classToken and PHYSICAL_CLASSES[classToken] then
		return { ns.SPELLS.BLESSING_KINGS, ns.SPELLS.BLESSING_MIGHT }
	end
	-- Bear/Cat Druids (rage/energy) prefer Might; mana hybrids prefer Wisdom/Might.
	if powerType == 1 or powerType == 3 then
		return { ns.SPELLS.BLESSING_KINGS, ns.SPELLS.BLESSING_MIGHT }
	end
	if classToken == "HUNTER" then
		return { ns.SPELLS.BLESSING_KINGS, ns.SPELLS.BLESSING_MIGHT, ns.SPELLS.BLESSING_WISDOM }
	end
	if powerType == 0 then
		return { ns.SPELLS.BLESSING_KINGS, ns.SPELLS.BLESSING_WISDOM, ns.SPELLS.BLESSING_MIGHT }
	end
	return { ns.SPELLS.BLESSING_KINGS, ns.SPELLS.BLESSING_MIGHT, ns.SPELLS.BLESSING_WISDOM }
end

function CombatTracker:FindMissingBlessingForUnit(unit)
	local exists = UnitExists and UnitExists(unit)
	local connected = (not UnitIsConnected) or UnitIsConnected(unit)
	local dead = UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit)
	local isSelf = UnitIsUnit and UnitIsUnit(unit, "player")
	if not (exists and connected and not dead and not isSelf) then
		return nil
	end

	local hasOwn = false
	local active = {}
	for i = 1, 40 do
		local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HELPFUL")
		if not ok or not aura then break end
		local name = aura.name
		if name ~= nil and not ns.IsSecret(name) and self:IsBlessingName(name) then
			active[name] = true
			local src = aura.sourceUnit
			if src ~= nil and not ns.IsSecret(src) and src == "player" then
				hasOwn = true
				break
			end
		end
	end

	if hasOwn then return nil end

	for _, spellName in ipairs(BlessingOrderForUnit(unit)) do
		if IsSpellKnownByName(spellName) and not active[spellName] and not active["Greater " .. spellName] then
			local inRange = true
			if C_Spell and C_Spell.IsSpellInRange then
				local okR, r = pcall(C_Spell.IsSpellInRange, spellName, unit)
				if okR and ns.IsReadable(r) and r == false then
					inRange = false
				end
			end
			if inRange then
				local okN, unitName = pcall(UnitName, unit)
				if not okN or not ns.IsReadable(unitName) or unitName == "" then
					unitName = unit
				end
				return spellName, unit, unitName
			end
			break
		end
	end
	return nil
end

function CombatTracker:GetMissingTargetBlessing()
	if InCombatLockdown() then return nil end
	if ns.db and ns.db.remindGroupBlessings == false then return nil end
	if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then return nil end
	if not C_UnitAuras or not C_UnitAuras.GetAuraDataByIndex then return nil end
	if not UnitExists or not UnitExists("target") then return nil end
	if UnitIsPlayer and not UnitIsPlayer("target") then return nil end
	if UnitCanAttack and UnitCanAttack("player", "target") then return nil end
	if UnitIsFriend and not UnitIsFriend("player", "target") then return nil end
	return self:FindMissingBlessingForUnit("target")
end

function CombatTracker:GetMissingGroupBlessing()
	if InCombatLockdown() then return nil end
	if ns.db and ns.db.remindGroupBlessings == false then return nil end
	if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then return nil end
	if not C_UnitAuras or not C_UnitAuras.GetAuraDataByIndex then return nil end
	if not IsInGroup or not IsInGroup() then return nil end

	local inRaid = IsInRaid and IsInRaid() or false
	local total = GetNumGroupMembers and GetNumGroupMembers() or 0
	local prefix = inRaid and "raid" or "party"
	local maxUnits = inRaid and math.min(total, 40) or math.min(total, 4)

	for idx = 1, maxUnits do
		local spellName, unit, unitName = self:FindMissingBlessingForUnit(prefix .. idx)
		if spellName then
			return spellName, unit, unitName
		end
	end
	return nil
end

function CombatTracker:GetMissingAura()
	if InCombatLockdown() then return nil end
	if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then return nil end
	if ns.db and ns.db.remindAura == false then return nil end

	if self.hasOwnAura then return nil end
	if GetShapeshiftForm then
		local okF, form = pcall(GetShapeshiftForm)
		if okF and ns.IsReadable(form) and type(form) == "number" and form > 0 then
			return nil
		end
	end

	local activeAuras = self.activeAuras or {}
	local order = {
		ns.SPELLS.AURA_RETRIBUTION,
		ns.SPELLS.AURA_SANCTITY,
		ns.SPELLS.AURA_DEVOTION,
	}
	for _, auraName in ipairs(order) do
		if IsSpellKnownByName(auraName) and not activeAuras[auraName] then
			return auraName
		end
	end
	return nil
end

function CombatTracker:IsSealAvailable(name)
	if not name then return false end
	if self.seenSeals[name] then return true end
	return ns.IsSpellKnownByName(name)
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

	-- Raw player auras throw while tainted in combat; the Cooldown Manager above
	-- is the only in-combat source. Fall back to the cast model otherwise.
	if InCombatLockdown() then
		self.auraReadable = false
		return nil
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

	-- The Unsealed Wrath fallback depends on the CDM frames: tell the engine.
	local engine = ns:GetModule("WeaponEngine")
	if engine and engine.RefreshTalents and #frames > 0 and not engine.hasUnsealedWrath then
		engine:RefreshTalents()
	end
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

function CombatTracker:CountEcho(sealOverride)
	local engine = ns:GetModule("WeaponEngine")
	local db = ns.db or {}
	local hasUnsealedWrath = (engine and engine.hasUnsealedWrath == true) or (db.twistWithoutTalent == true)

	-- Without the talent there are no echoes at all; do not invent them.
	if not hasUnsealedWrath then
		self.echoes = 0
		self.lastEchoAt = nil
		return
	end

	local seal = sealOverride or self:GetActiveSeal()
	if not seal then
		self.echoes = 0
		return
	end

	-- A different seal than the one on the previous swing consumed every echo.
	-- That swing is itself the first swing with the new seal (the detonation).
	if self.lastSealAtSwing ~= nil and self.lastSealAtSwing ~= seal then
		self.echoes = 0
		self.swingsWithSeal = 1
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
	local name = ns.GetSpellNameByID(spellID)
	if not name then return end
	self.glowingSpells = self.glowingSpells or {}
	self.glowingSpells[name] = glowing and true or nil
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

	local units = {}
	if self.activeNameplates then
		for unit in pairs(self.activeNameplates) do
			units[unit] = true
		end
	end
	if C_NamePlate and C_NamePlate.GetNamePlates then
		local ok, plates = pcall(C_NamePlate.GetNamePlates)
		if ok and type(plates) == "table" then
			for _, plate in ipairs(plates) do
				if type(plate) == "table" and not IsFrameForbidden(plate) then
					-- Mainline 12.x / Forever uses plate.unitToken (NamePlateBaseMixin);
					-- keep namePlateUnitToken & UnitFrame.unit as fallbacks.
					local unit = ReadFieldSafe(plate, "unitToken")
						or ReadFieldSafe(plate, "namePlateUnitToken")
					if not unit then
						local uf = ReadFieldSafe(plate, "UnitFrame")
						if type(uf) == "table" then
							unit = ReadFieldSafe(uf, "unit")
						end
					end
					if type(unit) == "string" and not ns.IsSecret(unit) then
						units[unit] = true
					end
				end
			end
		end
	end

	local count = 0
	for unit in pairs(units) do
		local okH, hostile = pcall(UnitCanAttack, "player", unit)
		local okD, dead = pcall(UnitIsDead, unit)
		local okF, fighting = pcall(UnitAffectingCombat, unit)
		hostile = okH and not ns.IsSecret(hostile) and hostile
		dead = okD and not ns.IsSecret(dead) and dead
		fighting = (not okF) or ns.IsSecret(fighting) or fighting
		if hostile and not dead and fighting then
			local inMelee = false
			if C_Spell and C_Spell.IsSpellInRange then
				local okR, r = pcall(C_Spell.IsSpellInRange, ns.SPELLS.HOLY_STRIKE, unit)
				if okR and ns.IsReadable(r) then
					inMelee = r and true or false
				end
			end
			if not inMelee and CheckInteractDistance then
				-- Index 3 (~10 yd) closely matches Consecration's 8 yd radius when
				-- IsSpellInRange returns nil/secret for a nameplate unit.
				local okC, close = pcall(CheckInteractDistance, unit, 3)
				if okC and ns.IsReadable(close) and close then
					inMelee = true
				end
			end
			if inMelee then
				count = count + 1
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
			-- A secret flag cannot be proven interruptible: stay silent rather
			-- than flash a false INTERRUPT on an uninterruptible boss cast.
			if not ns.IsReadable(notInterruptible) or notInterruptible == true then
				return false
			end
			return true
		end
	end
	if UnitChannelInfo then
		local ok, chanName, _, _, _, _, _, notInterruptible = pcall(UnitChannelInfo, "target")
		if ok and chanName ~= nil then
			if not ns.IsReadable(notInterruptible) or notInterruptible == true then
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

function CombatTracker:IsNotFacing()
	if ns.db and ns.db.facingAlert == false then return false end
	return self.notFacingUntil ~= nil and GetTime() < self.notFacingUntil
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
