local addonName, ns = ...

local PriorityQueue = ns:NewModule("PriorityQueue")

-- Returns the single best action right now plus a preview of the next one.
--
-- Every spell API is called with the spell NAME, never an ID: this client resolves
-- a name to the rank the player actually owns, while an ID is one fixed rank.
-- The earlier probes proved name-based calls work (IsSpellUsable("Holy Strike")
-- returned true) and ID-based ones return false for ranks the player lacks.
--
-- Seal pairs come from measured weapon-speed brackets (Unsealed Wrath sims):
--   fast   <= 2.5 : 3x Righteousness -> 1x Fury
--   medium 2.6-3.2: 2x Righteousness -> 1x Command
--   slow   >= 3.3 : 3x Command -> 1x Righteousness
-- Without the Seal of Command talent every weapon uses the fast pairing, which
-- is what makes the addon usable while leveling.
--
-- Deliberately absent, because this client hides the input:
--   * Hammer of Wrath is never gated on target health (UnitHealth is secret)
--   * Consecration is never gated on mana (UnitPower is secret)
--   * Exorcism is never gated on Undead/Demon (UnitCreatureType is empty)
-- A seal counts as available once it has been seen active on the player.

local IsKnown = ns.IsSpellKnownByName

local function IsUsable(name)
	if not name or not C_Spell or not C_Spell.IsSpellUsable then return false end
	local ok, usable = pcall(C_Spell.IsSpellUsable, name)
	if not ok or usable == nil or ns.IsSecret(usable) then return false end
	return usable and true or false
end

local function IsNoMana(name)
	if not name or not C_Spell or not C_Spell.IsSpellUsable then return false end
	local ok, _, insufficientPower = pcall(C_Spell.IsSpellUsable, name)
	if not ok or insufficientPower == nil or ns.IsSecret(insufficientPower) then return false end
	return insufficientPower and true or false
end

local function InRange(name)
	if not name or not C_Spell or not C_Spell.IsSpellInRange then return false end
	local ok, inRange = pcall(C_Spell.IsSpellInRange, name, "target")
	if not ok or inRange == nil then return false end
	if ns.IsSecret(inRange) then return true end
	return inRange and true or false
end

local function GetCastTimeSeconds(name)
	if not name or not C_Spell or not C_Spell.GetSpellInfo then return nil end
	local ok, info = pcall(C_Spell.GetSpellInfo, name)
	if not ok or type(info) ~= "table" or ns.IsSecret(info) then return nil end
	local okCt, ct = pcall(function() return info.castTime end)
	if not okCt or not ns.IsReadable(ct) or type(ct) ~= "number" then return nil end
	if ct <= 0 then return 0 end
	return (ct > 20) and (ct / 1000) or ct
end

-- In combat the client reports cooldowns as secret values, so the queue keeps
-- its own clock from the cast events it can read.
local BASE_COOLDOWN = {
	["Judgement"] = 10,
	["Holy Strike"] = 10,
	["Exorcism"] = 15,
	["Hammer of Wrath"] = 6,
	["Hammer of Justice"] = 60,
	["Consecration"] = 8,
	["Holy Shock"] = 30,
	["Holy Wrath"] = 60,
	["Avenging Wrath"] = 180,
	["Blood Fury"] = 120,
	["Berserking"] = 180,
	["Blessing of Freedom"] = 25,
	["Repentance"] = 60,
	["Will of the Forsaken"] = 120,
	["Divine Shield"] = 300,
	["Divine Protection"] = 300,
	["Blessing of Protection"] = 300,
	["Every Man for Himself"] = 120,
}

-- Judgement and major offensive cooldowns are off the global cooldown.
local GCD = 1.5
local OFF_GCD = {
	["Judgement"] = true,
	["Avenging Wrath"] = true,
	["Blood Fury"] = true,
	["Berserking"] = true,
	["Will of the Forsaken"] = true,
	["Every Man for Himself"] = true,
}
local GCD_SPELLS = {
	["Holy Strike"] = true,
	["Exorcism"] = true,
	["Hammer of Wrath"] = true,
	["Hammer of Justice"] = true,
	["Consecration"] = true,
	["Holy Shock"] = true,
	["Holy Wrath"] = true,
	["Blessing of Kings"] = true,
	["Blessing of Might"] = true,
	["Blessing of Wisdom"] = true,
	["Blessing of Freedom"] = true,
	["Blessing of Protection"] = true,
	["Repentance"] = true,
	["Divine Shield"] = true,
	["Divine Protection"] = true,
}

function PriorityQueue:OnLogin()
	self.current = nil
	self.next = nil
	self.cdUntil = {}
	self.cdStart = {}
	self.cdDuration = {}
	if ns.db then
		ns.db.learnedCooldowns = ns.db.learnedCooldowns or {}
		self.learned = ns.db.learnedCooldowns
	else
		self.learned = {}
	end

	ns:On("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, _, spellID)
		if unit == "player" then self:NoteCast(spellID) end
	end)

	-- Per-pull reset: intervals never span two fights.
	ns:On("PLAYER_REGEN_DISABLED", function()
		self.lastCastAt = {}
		self.gcdStart = nil
		self.gcdUntil = nil
	end)

	-- Reset learned cooldowns if talents or gear (set bonuses) change.
	local function ResetLearned()
		if ns.db then
			ns.db.learnedCooldowns = {}
			self.learned = ns.db.learnedCooldowns
		else
			self.learned = {}
		end
	end
	ns:On("PLAYER_EQUIPMENT_CHANGED", ResetLearned)
	ns:On("TRAIT_NODE_CHANGED", ResetLearned)
end

function PriorityQueue:NoteCast(spellID)
	local name = ns.GetSpellNameByID(spellID)
	if not name then return end

	local now = GetTime()

	-- Only on-GCD rotation spells and seals spend the global; trinkets, racials
	-- and cooldowns such as Avenging Wrath are off the global cooldown.
	if GCD_SPELLS[name] or name:find("^Seal of ") then
		self.gcdStart = now
		self.gcdUntil = now + GCD
	end

	local base = BASE_COOLDOWN[name]
	if not base then return end

	self.lastCastAt = self.lastCastAt or {}
	self.learned = self.learned or {}

	-- Learn the real cooldown from play, but only from intervals that are
	-- shorter than the base value: talents such as Improved Judgement lower it,
	-- while downtime between pulls would inflate it.
	local previous = self.lastCastAt[name]
	if previous then
		local interval = now - previous
		if interval > 2 and interval <= base then
			-- Keep the shortest interval seen: a delayed cast must not inflate it.
			local known = self.learned[name]
			if not known or interval < known then
				self.learned[name] = interval
			end
		end
	end
	self.lastCastAt[name] = now

	local duration = self.learned[name] or base
	self.cdStart = self.cdStart or {}
	self.cdDuration = self.cdDuration or {}
	self.cdStart[name] = now
	self.cdDuration[name] = duration
	self.cdUntil[name] = now + duration
end

-- Returns (startTime, duration) for the active cooldown or GCD swipe on the
-- recommended spell icon, or (nil, nil) when the spell is ready to cast.
function PriorityQueue:GetCooldownWindow(name)
	if not name then return nil, nil end
	local now = GetTime()

	if not InCombatLockdown() then
		if C_Spell and C_Spell.GetSpellCooldown then
			local ok, info = pcall(C_Spell.GetSpellCooldown, name)
			if ok and type(info) == "table" and ns.IsReadable(info.startTime) and ns.IsReadable(info.duration) then
				if info.duration > 0 and (info.startTime + info.duration) > now then
					return info.startTime, info.duration
				end
				return nil, nil
			end
		end
		-- Fall through to cast-tracked cooldown model when client cooldowns are secret (e.g. Battlegrounds).
	end

	local bestStart, bestDuration, bestEnd

	local cdUntil = self.cdUntil and self.cdUntil[name]
	local cdStart = self.cdStart and self.cdStart[name]
	local cdDuration = self.cdDuration and self.cdDuration[name]
	if cdUntil and cdStart and cdDuration and cdUntil > now then
		bestStart, bestDuration, bestEnd = cdStart, cdDuration, cdUntil
	end

	if not OFF_GCD[name] and self.gcdUntil and self.gcdStart and self.gcdUntil > now then
		if not bestEnd or self.gcdUntil > bestEnd then
			bestStart, bestDuration, bestEnd = self.gcdStart, GCD, self.gcdUntil
		end
	end

	return bestStart, bestDuration
end

function PriorityQueue:GetGcdRemaining()
	if not self.gcdUntil then return 0 end
	local remaining = self.gcdUntil - GetTime()
	if remaining < 0 then return 0 end
	return remaining
end

function PriorityQueue:GetRemainingInfo(name)
	if not name then return nil, "none" end

	-- Out of combat the client's cooldowns are readable and accurate, and the
	-- local model is only debris from the last fight. Never show a countdown
	-- from stale combat state while looting or walking around.
	if not InCombatLockdown() then
		if C_Spell and C_Spell.GetSpellCooldown then
			local ok, info = pcall(C_Spell.GetSpellCooldown, name)
			if ok and type(info) == "table" and ns.IsReadable(info.startTime) and ns.IsReadable(info.duration) then
				local base = BASE_COOLDOWN[name]
				if base and info.duration > 2 and info.duration <= base then
					self.learned = self.learned or {}
					self.learned[name] = info.duration
				end
				local remaining = (info.startTime + info.duration) - GetTime()
				if remaining < 0 then remaining = 0 end
				return remaining, "client"
			end
		end
		if not (self.cdUntil and self.cdUntil[name]) then
			return 0, "idle"
		end
	end

	local untilAt = self.cdUntil and self.cdUntil[name]
	if untilAt then
		local remaining = untilAt - GetTime()
		if remaining < 0 then remaining = 0 end
		return remaining, "model"
	end
	return 0, "none"
end

function PriorityQueue:GetRemaining(name)
	local remaining = self:GetRemainingInfo(name)
	return remaining
end

function PriorityQueue:DebugLine()
	local jr, js = self:GetRemainingInfo(ns.SPELLS.JUDGEMENT)
	local hr, hs = self:GetRemainingInfo(ns.SPELLS.HOLY_STRIKE)
	return string.format("q cur=%s next=%s range=%s cd=%.1f gcd=%.1f J=%.1f%s HS=%.1f%s",
		tostring(self.current), tostring(self.next), tostring(self.currentInRange),
		self.countdown or 0, self:GetGcdRemaining(),
		jr or 0, js or "?", hr or 0, hs or "?")
end

function PriorityQueue:IsReady(name)
	local remaining = self:GetRemaining(name)
	if remaining == nil then return false end
	return remaining <= 0.2
end

function PriorityQueue:GetSealPair()
	local db = ns.db
	local manual = db and db.manual or {}
	local tracker = ns:GetModule("CombatTracker")
	local engine = ns:GetModule("WeaponEngine")

	local primaryName, primaryStacks, secondaryName, secondaryStacks

	if db and db.auto and engine then
		local rotation = engine:GetRotation()
		primaryName = rotation.primary
		primaryStacks = rotation.primaryStacks
		secondaryName = rotation.secondary
		secondaryStacks = rotation.secondaryStacks
	else
		primaryName = manual.sealA or ns.SPELLS.SEAL_COMMAND
		primaryStacks = manual.stacksA or 3
		secondaryName = manual.sealB or ns.SPELLS.SEAL_RIGHT
		secondaryStacks = manual.stacksB or 1
	end

	-- Never ask for a seal the player does not have.
	if primaryName and not tracker:IsSealAvailable(primaryName) then
		if tracker:IsSealAvailable(ns.SPELLS.SEAL_RIGHT) then
			primaryName = ns.SPELLS.SEAL_RIGHT
		elseif tracker:IsSealAvailable(ns.SPELLS.SEAL_COMMAND) then
			primaryName = ns.SPELLS.SEAL_COMMAND
		elseif tracker:IsSealAvailable(ns.SPELLS.SEAL_CRUSADER) then
			primaryName = ns.SPELLS.SEAL_CRUSADER
		else
			primaryName = nil
		end
	end
	if not tracker:IsSealAvailable(secondaryName) then
		secondaryName = nil
	end
	if secondaryName == primaryName then
		secondaryName = nil
	end

	return primaryName, primaryStacks, secondaryName, secondaryStacks
end

function PriorityQueue:GetEchoTarget()
	local _, primaryStacks = self:GetSealPair()
	return primaryStacks or 3
end

-- True when Unsealed Wrath twisting is active and the currently recommended
-- action is the seal swap itself (never over Judgement or Holy Strike).
function PriorityQueue:IsTwistReady(hasUnsealedWrath)
	if not hasUnsealedWrath then return false end
	if self.currentIsTwist ~= nil then
		return self.currentIsTwist == true
	end
	local tracker = ns:GetModule("CombatTracker")
	local primaryName, primaryStacks, secondaryName = self:GetSealPair()
	return secondaryName ~= nil
		and tracker:GetActiveSeal() == primaryName
		and tracker:GetEchoes() >= (primaryStacks or 3)
end

function PriorityQueue:Evaluate()
	local tracker = ns:GetModule("CombatTracker")
	local engine = ns:GetModule("WeaponEngine")
	local pvp = ns:GetModule("PvPEngine")
	local db = ns.db or {}
	local hasUnsealedWrath = (engine and engine.hasUnsealedWrath == true) or (db.twistWithoutTalent == true)

	local primaryName, primaryStacks, secondaryName, secondaryStacks = self:GetSealPair()
	local activeSeal = tracker:GetActiveSeal()
	local echoes = tracker:GetEchoes()
	local swingsWithSeal = tracker:GetSwingsWithSeal()

	local isPvpTarget = pvp and pvp.IsPvpTarget and pvp:IsPvpTarget()
		or ((db.pvpEnabled ~= false) and tracker and tracker.IsPvpTarget and tracker:IsPvpTarget() or false)
	local pvpActive = (db.pvpEnabled ~= false) and isPvpTarget
	local pvpContext = pvp and pvp.IsPvpContext and pvp:IsPvpContext()
		or ((db.pvpEnabled ~= false) and (isPvpTarget or (tracker and tracker.IsInBattleground and tracker:IsInBattleground() or false)))

	if pvpActive and pvp and pvp.NoteTargetObservation then
		pvp:NoteTargetObservation(tracker)
	end

	-- Strict PvP seal firewall: force Seal of Command against enemy players and
	-- prevent PvE Unsealed Wrath twists (like Seal of Fury) from leaking into PvP.
	if pvpActive then
		if IsKnown(ns.SPELLS.SEAL_COMMAND) then
			primaryName = ns.SPELLS.SEAL_COMMAND
		end
		secondaryName = nil
	end

	local hasTarget = UnitExists("target") and UnitCanAttack("player", "target")
	local exorcismTarget = false
	if hasTarget then
		if tracker and tracker.IsTargetUndeadOrDemon then
			exorcismTarget = tracker:IsTargetUndeadOrDemon()
		else
			local creatureType = UnitCreatureType and UnitCreatureType("target") or nil
			if creatureType ~= nil and ns.IsSecret(creatureType) then creatureType = nil end
			exorcismTarget = creatureType == "Undead" or creatureType == "Demon"
		end
	end
	local swingOpen = tracker:IsSwingWindowOpen(GCD)
	local gcdReady = self:GetGcdRemaining() <= 0.15
	local inMelee = hasTarget and tracker and tracker.IsInSwingRange and tracker:IsInSwingRange() or false
	local targetImmune = pvpActive and pvp and pvp.IsTargetImmune and pvp:IsTargetImmune() or false

	-- PvE Unsealed Wrath seal-swap state (per Ebon Hold / Icy Veins / Maxroll):
	-- Rotational damage spells fire before seal swaps, EXCEPT when the next white
	-- swing is imminent (spending another 1.5s GCD would miss the swing and waste
	-- echo storage/detonation). Also returns cleanly from secondary -> primary
	-- regardless of extra echoes gained via Windfury.
	local targetPrimaryStacks = primaryStacks or 3
	local targetSecondarySwings = secondaryStacks or 1
	local wantTwistToSecondary = (not pvpActive) and hasUnsealedWrath and (secondaryName ~= nil)
		and (activeSeal == primaryName) and (echoes >= targetPrimaryStacks)
	local wantReturnToPrimary = (not pvpActive) and hasUnsealedWrath and (primaryName ~= nil) and (secondaryName ~= nil)
		and (activeSeal == secondaryName) and (swingsWithSeal >= targetSecondarySwings)
	local pendingTwistSeal = (wantTwistToSecondary and secondaryName) or (wantReturnToPrimary and primaryName) or nil
	local swingRem = tracker and tracker.GetSwingRemaining and tracker:GetSwingRemaining() or nil
	local twistImminent = (pendingTwistSeal ~= nil) and (swingRem == nil or swingRem <= (GCD + 0.25))

	self.currentTargetImmune = targetImmune
	if pvpContext and pvp and pvp.FindOffTargetCast then
		self.currentOffTargetAlert = pvp:FindOffTargetCast(tracker, self, IsUsable)
	else
		self.currentOffTargetAlert = nil
	end

	local candidates = {}

	local function Add(name, requiresRange, meta)
		if not name then return end
		local inRange = true
		if requiresRange then inRange = InRange(name) end
		candidates[#candidates + 1] = {
			name = name,
			inRange = inRange,
			isProc = meta and meta.isProc or false,
			isInterrupt = meta and meta.isInterrupt or false,
			isBurst = meta and meta.isBurst or false,
			isTwist = meta and meta.isTwist or false,
			isPvp = meta and meta.isPvp or false,
			pvpLabel = meta and meta.pvpLabel or nil,
		}
	end

	-- -2. PvP CC Breaker, Survival & Anti-Stealth (strictly gated to PvP/BG).
	if pvpContext then
		local loc = pvp and pvp.GetLossOfControlInfo and pvp:GetLossOfControlInfo() or {
			hasFearCharmSleep = tracker and tracker.HasActiveCC and tracker:HasActiveCC() or false,
			hasHardCC = tracker and tracker.HasActiveCC and tracker:HasActiveCC() or false,
			hasRoot = tracker and tracker.IsPlayerSlowedOrRooted and tracker:IsPlayerSlowedOrRooted() or false,
			hasSnare = tracker and tracker.IsPlayerSlowedOrRooted and tracker:IsPlayerSlowedOrRooted() or false,
		}

		if db.pvpCcBreaker ~= false then
			if loc.hasFearCharmSleep
				and IsKnown(ns.SPELLS.WILL_OF_FORSAKEN) and IsUsable(ns.SPELLS.WILL_OF_FORSAKEN)
				and self:IsReady(ns.SPELLS.WILL_OF_FORSAKEN) then
				Add(ns.SPELLS.WILL_OF_FORSAKEN, false, { isPvp = true, pvpLabel = "BREAK CC!" })
			elseif loc.hasHardCC and (loc.maxRemaining == nil or loc.maxRemaining >= 2.5) then
				if IsKnown(ns.SPELLS.EVERY_MAN) and IsUsable(ns.SPELLS.EVERY_MAN) and self:IsReady(ns.SPELLS.EVERY_MAN) then
					Add(ns.SPELLS.EVERY_MAN, false, { isPvp = true, pvpLabel = "BREAK CC!" })
				elseif db.pvpDefensive ~= false and pvp and pvp.FindReadyPvpTrinket then
					local pvpTrinket = pvp:FindReadyPvpTrinket()
					if pvpTrinket then
						Add(pvpTrinket, false, { isPvp = true, pvpLabel = "TRINKET!" })
					end
				end
			end
		end

		if (db.pvpDefensive ~= false) and InCombatLockdown() and pvp and pvp.CountAttackersOnPlayer then
			local attackers = pvp:CountAttackersOnPlayer(tracker)
			if (loc.hasHardCC and attackers >= 2) or (attackers >= 3) then
				if gcdReady and IsKnown(ns.SPELLS.DIVINE_SHIELD) and IsUsable(ns.SPELLS.DIVINE_SHIELD)
					and self:IsReady(ns.SPELLS.DIVINE_SHIELD) then
					Add(ns.SPELLS.DIVINE_SHIELD, false, { isPvp = true, pvpLabel = "BUBBLE!" })
				elseif gcdReady and not loc.hasHardCC and IsKnown(ns.SPELLS.DIVINE_PROTECTION)
					and IsUsable(ns.SPELLS.DIVINE_PROTECTION) and self:IsReady(ns.SPELLS.DIVINE_PROTECTION) then
					Add(ns.SPELLS.DIVINE_PROTECTION, false, { isPvp = true, pvpLabel = "DEFENSIVE!" })
				end
			end
		end

		if (db.pvpCcBreaker ~= false) and hasTarget and gcdReady
			and IsKnown(ns.SPELLS.BLESSING_FREEDOM) and IsUsable(ns.SPELLS.BLESSING_FREEDOM)
			and self:IsReady(ns.SPELLS.BLESSING_FREEDOM) then
			local targetClass = pvp and pvp.GetTargetClass and pvp:GetTargetClass() or nil
			local needFreedom = loc.hasRoot or (loc.hasSnare and not inMelee)
			if targetClass == "MAGE" and (db.pvpSmartMatchup ~= false) then
				needFreedom = loc.hasRoot or (loc.hasSnare and not inMelee)
			end
			if needFreedom then
				Add(ns.SPELLS.BLESSING_FREEDOM, false, { isPvp = true, pvpLabel = "FREEDOM!" })
			end
		end

		if pvp and pvp.IsStealthVanishActive and pvp:IsStealthVanishActive() and gcdReady
			and IsKnown(ns.SPELLS.CONSECRATION) and IsUsable(ns.SPELLS.CONSECRATION)
			and self:IsReady(ns.SPELLS.CONSECRATION) then
			Add(ns.SPELLS.CONSECRATION, false, { isPvp = true, pvpLabel = "UNSTEALTH!" })
		end
	end

	local function FindReadyTrinketSpell()
		if not GetInventoryItemID or not C_Item or not C_Item.GetItemSpell or not C_Item.GetItemCooldown then
			return nil
		end
		for _, slot in ipairs({ 13, 14 }) do
			local okI, itemID = pcall(GetInventoryItemID, "player", slot)
			if okI and type(itemID) == "number" and not ns.IsSecret(itemID) then
				local okS, spellName = pcall(C_Item.GetItemSpell, itemID)
				if okS and type(spellName) == "string" and not ns.IsSecret(spellName)
					and not (pvp and pvp.IsPvpTrinketSpellName and pvp:IsPvpTrinketSpellName(spellName)) then
					local okC, start, duration, enable = pcall(C_Item.GetItemCooldown, itemID)
					if okC and ns.IsReadable(start) and ns.IsReadable(duration) and ns.IsReadable(enable) and (enable == true or enable == 1) then
						if start == 0 or duration == 0 or (start + duration - GetTime()) <= 0.2 then
							return spellName
						end
					end
				end
			end
		end
		return nil
	end

	-- -1. Interrupt: if the target is casting an interruptible spell and
	--     Hammer of Justice is ready & in range, prioritize the interrupt.
	--     In PvP, fall back to Repentance (20yd) if HoJ is unavailable.
	local addedInterrupt = false
	if hasTarget and (not targetImmune) and (db.suggestInterrupt ~= false) and gcdReady
		and tracker and tracker.IsTargetCastingInterruptible and tracker:IsTargetCastingInterruptible() then
		if IsKnown(ns.SPELLS.HAMMER_OF_JUSTICE) and IsUsable(ns.SPELLS.HAMMER_OF_JUSTICE)
			and self:IsReady(ns.SPELLS.HAMMER_OF_JUSTICE) and InRange(ns.SPELLS.HAMMER_OF_JUSTICE) then
			Add(ns.SPELLS.HAMMER_OF_JUSTICE, true, { isInterrupt = true })
			addedInterrupt = true
		elseif pvpActive and (db.pvpGapCloser ~= false)
			and IsKnown(ns.SPELLS.REPENTANCE) and IsUsable(ns.SPELLS.REPENTANCE)
			and self:IsReady(ns.SPELLS.REPENTANCE) and InRange(ns.SPELLS.REPENTANCE) then
			Add(ns.SPELLS.REPENTANCE, true, { isInterrupt = true, isPvp = true })
			addedInterrupt = true
		end
	end

	-- Detect low mana in combat via insufficientPower on Consecration (our
	-- costliest spell), since UnitPower() is secret in combat.
	local lowMana = (db.manaSaver ~= false) and IsKnown(ns.SPELLS.CONSECRATION) and IsNoMana(ns.SPELLS.CONSECRATION)

	-- 0a. Boss / Elite opener: apply Judgement of the Crusader once per pull (PvE only).
	local cls = hasTarget and UnitClassification and UnitClassification("target") or nil
	if cls ~= nil and ns.IsSecret(cls) then cls = nil end
	local isBossOrElite = (cls == "worldboss") or (not db.crusaderBossOnly and (cls == "elite" or cls == "rareelite"))
	local needCrusader = hasTarget and (not pvpActive) and (db.crusaderOnBoss ~= false) and isBossOrElite
		and (not lowMana or activeSeal == ns.SPELLS.SEAL_CRUSADER)
		and tracker and tracker.HasJudgedCrusader and not tracker:HasJudgedCrusader()
		and IsKnown(ns.SPELLS.SEAL_CRUSADER) and IsUsable(ns.SPELLS.SEAL_CRUSADER)

	if needCrusader then
		if activeSeal ~= ns.SPELLS.SEAL_CRUSADER and gcdReady then
			Add(ns.SPELLS.SEAL_CRUSADER, false)
		elseif activeSeal == ns.SPELLS.SEAL_CRUSADER and IsUsable(ns.SPELLS.JUDGEMENT) and self:IsReady(ns.SPELLS.JUDGEMENT) then
			Add(ns.SPELLS.JUDGEMENT, true)
		end
	elseif activeSeal == ns.SPELLS.SEAL_CRUSADER and primaryName and gcdReady then
		-- Crusader already judged: immediately switch back to primary DPS seal.
		Add(primaryName, false)
	end

	-- 0. No seal up: nothing else matters, every swing is losing seal damage.
	if primaryName and activeSeal == nil and gcdReady then
		Add(primaryName, false)
	end

	-- 1.1. PvP 30yd Execute Snipe & Post-HoJ Double-Damage Judgement.
	local furyUp = activeSeal == ns.SPELLS.SEAL_FURY
	if pvpActive and hasTarget and not targetImmune then
		if (db.pvpExecuteSnipe ~= false) and gcdReady and (not inMelee or swingOpen)
			and IsKnown(ns.SPELLS.HAMMER_OF_WRATH) and IsUsable(ns.SPELLS.HAMMER_OF_WRATH)
			and self:IsReady(ns.SPELLS.HAMMER_OF_WRATH) and InRange(ns.SPELLS.HAMMER_OF_WRATH) then
			Add(ns.SPELLS.HAMMER_OF_WRATH, true, { isPvp = true, pvpLabel = "FINISH!" })
		end
		if (db.pvpStunCombo ~= false) and (not furyUp)
			and pvp and pvp.IsTargetStunnedByUs and pvp:IsTargetStunnedByUs()
			and activeSeal == ns.SPELLS.SEAL_COMMAND
			and IsUsable(ns.SPELLS.JUDGEMENT) and self:IsReady(ns.SPELLS.JUDGEMENT) and InRange(ns.SPELLS.JUDGEMENT) then
			Add(ns.SPELLS.JUDGEMENT, true, { isPvp = true, pvpLabel = "JUDGE STUN!" })
		end
	end

	-- 1.2. Boss / PvP Burst: major offensive cooldowns or ready on-use trinkets.
	local burstAllowed = (cls == "worldboss")
		or (pvpActive and (not pvp or not pvp.IsBurstWindowReady or pvp:IsBurstWindowReady(tracker, activeSeal, self)))
	if hasTarget and (not targetImmune) and InCombatLockdown() and (db.suggestBurst ~= false) and burstAllowed and activeSeal ~= nil then
		local burstSpells = {
			ns.SPELLS.AVENGING_WRATH,
			ns.SPELLS.BLOOD_FURY,
			ns.SPELLS.BERSERKING,
		}
		local addedBurst = false
		for _, burstName in ipairs(burstSpells) do
			if IsKnown(burstName) and IsUsable(burstName) and self:IsReady(burstName) then
				Add(burstName, false, { isBurst = true })
				addedBurst = true
				break
			end
		end
		if not addedBurst then
			local trinketSpell = FindReadyTrinketSpell()
			if trinketSpell then
				Add(trinketSpell, false, { isBurst = true })
			end
		end
	end

	-- 1.3. PvP Anti-Runner, Blink Catch & Gap-Closer (when hostile player escapes melee).
	if pvpActive and (not targetImmune) and hasTarget and not inMelee then
		if (db.pvpAntiRunner ~= false) and InCombatLockdown() and tracker.hadMeleeWithTarget and InRange(ns.SPELLS.JUDGEMENT) then
			local mobileClasses = { DRUID = true, SHAMAN = true, HUNTER = true, ROGUE = true }
			local tClass = pvp and pvp.GetTargetClass and pvp:GetTargetClass() or nil
			if tClass and mobileClasses[tClass] then
				if activeSeal == ns.SPELLS.SEAL_JUSTICE and IsUsable(ns.SPELLS.JUDGEMENT) and self:IsReady(ns.SPELLS.JUDGEMENT) then
					Add(ns.SPELLS.JUDGEMENT, true, { isPvp = true, pvpLabel = "STOP RUNNER" })
				elseif activeSeal ~= ns.SPELLS.SEAL_JUSTICE and gcdReady and IsKnown(ns.SPELLS.SEAL_JUSTICE) and IsUsable(ns.SPELLS.SEAL_JUSTICE) then
					Add(ns.SPELLS.SEAL_JUSTICE, false, { isPvp = true, pvpLabel = "STOP RUNNER" })
				end
			end
		end

		if (db.pvpSmartMatchup ~= false) and gcdReady and not addedInterrupt
			and pvp and pvp.IsTargetBlinked and pvp:IsTargetBlinked()
			and IsKnown(ns.SPELLS.REPENTANCE) and IsUsable(ns.SPELLS.REPENTANCE)
			and self:IsReady(ns.SPELLS.REPENTANCE) and InRange(ns.SPELLS.REPENTANCE) then
			Add(ns.SPELLS.REPENTANCE, true, { isPvp = true, pvpLabel = "CATCH BLINK!" })
		elseif (db.pvpGapCloser ~= false) and gcdReady and not addedInterrupt
			and IsKnown(ns.SPELLS.REPENTANCE) and IsUsable(ns.SPELLS.REPENTANCE)
			and self:IsReady(ns.SPELLS.REPENTANCE) and InRange(ns.SPELLS.REPENTANCE) then
			Add(ns.SPELLS.REPENTANCE, true, { isPvp = true, pvpLabel = "GAP CLOSE" })
		end
	end

	-- 1.4. PvP Teammate Peel (HoJ / Blessing of Protection when attacker hits friendly caster/healer).
	if pvpActive and (not targetImmune) and hasTarget and gcdReady and not addedInterrupt
		and pvp and pvp.FindPeelAction then
		local peelSpell, peelLabel = pvp:FindPeelAction(self, IsUsable, InRange)
		if peelSpell then
			Add(peelSpell, peelSpell == ns.SPELLS.HAMMER_OF_JUSTICE, { isPvp = true, pvpLabel = peelLabel })
		end
	end

	-- 1.5. Glowing procs (Blizzard SpellActivationOverlay): react immediately to
	--      any combat proc that lights up a known rotational spell.
	if hasTarget and (not targetImmune) and tracker and tracker.IsSpellGlowing then
		local procSpells = {
			ns.SPELLS.EXORCISM,
			ns.SPELLS.HAMMER_OF_WRATH,
			ns.SPELLS.HOLY_STRIKE,
			ns.SPELLS.HOLY_SHOCK,
			ns.SPELLS.JUDGEMENT,
		}
		for _, spellName in ipairs(procSpells) do
			local allowed = (spellName ~= ns.SPELLS.JUDGEMENT) or (not furyUp)
			local needsGcd = not OFF_GCD[spellName]
			if allowed and (not needsGcd or gcdReady) and tracker:IsSpellGlowing(spellName)
				and IsKnown(spellName) and IsUsable(spellName) and self:IsReady(spellName) then
				Add(spellName, true, { isProc = true })
			end
		end
	end

	local pvpCtx = {
		gcdReady = gcdReady,
		activeSeal = activeSeal,
		targetImmune = targetImmune,
		pq = self,
		IsUsable = IsUsable,
		InRange = InRange,
	}

	-- 1.9. PvP Stun Burst Combo: Hammer of Justice -> Judgement of Command (double damage).
	if pvpActive and hasTarget and gcdReady and activeSeal == ns.SPELLS.SEAL_COMMAND
		and (not pvp or not pvp.CanRecommendStunCombo or pvp:CanRecommendStunCombo(pvpCtx))
		and IsKnown(ns.SPELLS.HAMMER_OF_JUSTICE) and IsUsable(ns.SPELLS.HAMMER_OF_JUSTICE)
		and self:IsReady(ns.SPELLS.HAMMER_OF_JUSTICE) and InRange(ns.SPELLS.HAMMER_OF_JUSTICE)
		and IsKnown(ns.SPELLS.JUDGEMENT) and IsUsable(ns.SPELLS.JUDGEMENT)
		and self:IsReady(ns.SPELLS.JUDGEMENT) then
		Add(ns.SPELLS.HAMMER_OF_JUSTICE, true, { isPvp = true, pvpLabel = "STUN COMBO!" })
	end

	-- 2. Judgement (off-GCD). Always above PvE seal swaps so Judgement is never
	--    locked out by swapping into Seal of Fury first. Never while Fury is up.
	local holdJudgement = pvpActive and pvp and pvp.ShouldHoldJudgementForStunCombo and pvp:ShouldHoldJudgementForStunCombo(pvpCtx) or false
	if hasTarget and (not targetImmune) and not furyUp and not holdJudgement and IsUsable(ns.SPELLS.JUDGEMENT) and self:IsReady(ns.SPELLS.JUDGEMENT) then
		Add(ns.SPELLS.JUDGEMENT, true)
	end

	-- 2.5. Imminent PvE Seal Twist: jump ahead of on-GCD rotational spells only
	--      when the next white swing is too close to fit another 1.5s GCD first.
	if twistImminent and gcdReady then
		Add(pendingTwistSeal, false, { isTwist = true })
	end

	-- 3. Hammer of Wrath (execute <= 20%). Baseline 1.0s cast requires an open
	--    swing window at lvl 44-48; 5/5 Champion of the Light reduces castTime
	--    to 0 (instant cast) so it can fire freely at lvl 50-60.
	local howCastSec = GetCastTimeSeconds(ns.SPELLS.HAMMER_OF_WRATH)
	local howWindowOpen
	if howCastSec == nil then
		howWindowOpen = swingOpen
	elseif howCastSec <= 0 then
		howWindowOpen = true
	else
		howWindowOpen = tracker:IsSwingWindowOpen(howCastSec + 0.15)
	end
	if hasTarget and (not targetImmune) and howWindowOpen and gcdReady and IsUsable(ns.SPELLS.HAMMER_OF_WRATH) and self:IsReady(ns.SPELLS.HAMMER_OF_WRATH) then
		Add(ns.SPELLS.HAMMER_OF_WRATH, true)
	end

	-- 4. AoE priority when manual AoE is on OR Auto-AoE detects enough hostile
	--    mobs in melee range via nameplates.
	local aoeThreshold = tonumber(db.autoAoeThreshold) or 2
	local autoAoeActive = (db.autoAoe ~= false) and tracker and tracker.GetMeleeEnemyCount and (tracker:GetMeleeEnemyCount() >= aoeThreshold)
	local aoeActive = (not targetImmune) and ((db.aoe == true) or autoAoeActive)
	if aoeActive and gcdReady and IsUsable(ns.SPELLS.CONSECRATION) and self:IsReady(ns.SPELLS.CONSECRATION) then
		Add(ns.SPELLS.CONSECRATION, false)
	end
	if aoeActive and hasTarget and exorcismTarget and gcdReady and IsUsable(ns.SPELLS.HOLY_WRATH) and self:IsReady(ns.SPELLS.HOLY_WRATH) then
		Add(ns.SPELLS.HOLY_WRATH, false)
	end

	-- 5. Holy Strike, core melee rotational ability (skip out-of-range Holy Strike
	--    during PvP range-band checks so 10-20yd ranged spells can surface cleanly).
	local allowHolyStrike = (not pvpActive) or (db.pvpExecuteSnipe == false) or inMelee or InRange(ns.SPELLS.HOLY_STRIKE)
	if hasTarget and (not targetImmune) and allowHolyStrike and gcdReady and IsUsable(ns.SPELLS.HOLY_STRIKE) and self:IsReady(ns.SPELLS.HOLY_STRIKE) then
		Add(ns.SPELLS.HOLY_STRIKE, true)
	end

	-- 6. Exorcism, only against Undead and Demons.
	if hasTarget and (not targetImmune) and exorcismTarget and gcdReady and IsUsable(ns.SPELLS.EXORCISM) and self:IsReady(ns.SPELLS.EXORCISM) then
		Add(ns.SPELLS.EXORCISM, true)
	end

	-- 7. Holy Shock, for hybrid/Shockadin builds when talented.
	if hasTarget and (not targetImmune) and gcdReady and IsKnown(ns.SPELLS.HOLY_SHOCK) and IsUsable(ns.SPELLS.HOLY_SHOCK) and self:IsReady(ns.SPELLS.HOLY_SHOCK) then
		Add(ns.SPELLS.HOLY_SHOCK, true)
	end

	-- 8. Normal PvE Seal Twist / Return: once rotational damage spells are on
	--    cooldown, perform the due twist (primary -> secondary at target stacks,
	--    or secondary -> primary after the detonation swing landed).
	if pendingTwistSeal and (not twistImminent) and gcdReady then
		Add(pendingTwistSeal, false, { isTwist = true })
	end

	local current = candidates[1]
	local nextAction = candidates[2]

	-- Collect eligible spells that are on cooldown (or waiting on the current
	-- action, like Judgement right after casting a seal) so both the fallback
	-- countdown and the NEXT preview always have accurate upcoming actions.
	local upcoming = {}
	local function ConsiderUpcoming(name, requiresRange, assumedRemaining)
		if not name or not IsKnown(name) then return end
		local remaining = assumedRemaining
		if remaining == nil then
			remaining = math.max(self:GetRemaining(name) or 0,
				OFF_GCD[name] and 0 or self:GetGcdRemaining())
		end
		upcoming[#upcoming + 1] = {
			name = name,
			requiresRange = requiresRange,
			remaining = remaining,
		}
	end

	if primaryName and activeSeal == nil then
		ConsiderUpcoming(primaryName, false)
	elseif pendingTwistSeal then
		ConsiderUpcoming(pendingTwistSeal, false, self:GetGcdRemaining())
	end

	if hasTarget then
		local sealAfterCurrent = activeSeal
		if current and current.name == primaryName and activeSeal == nil then
			sealAfterCurrent = primaryName
		end
		if sealAfterCurrent ~= nil and sealAfterCurrent ~= ns.SPELLS.SEAL_FURY then
			ConsiderUpcoming(ns.SPELLS.JUDGEMENT, true)
		end
		ConsiderUpcoming(ns.SPELLS.HOLY_STRIKE, true)
		if exorcismTarget then
			ConsiderUpcoming(ns.SPELLS.EXORCISM, true)
		end
		if howWindowOpen and IsUsable(ns.SPELLS.HAMMER_OF_WRATH) then
			ConsiderUpcoming(ns.SPELLS.HAMMER_OF_WRATH, true)
		end
		ConsiderUpcoming(ns.SPELLS.HOLY_SHOCK, true)
	end
	if aoeActive then
		if not IsNoMana(ns.SPELLS.CONSECRATION) then
			ConsiderUpcoming(ns.SPELLS.CONSECRATION, false)
		end
		if hasTarget and exorcismTarget and not IsNoMana(ns.SPELLS.HOLY_WRATH) then
			ConsiderUpcoming(ns.SPELLS.HOLY_WRATH, false)
		end
	end

	table.sort(upcoming, function(a, b)
		return a.remaining < b.remaining
	end)

	self.countdown = nil
	self.currentNoMana = false
	if not current and not targetImmune then
		-- Nothing castable right now: first check if a ready spell is blocked
		-- specifically by insufficient mana (insufficientPower from IsSpellUsable),
		-- otherwise show what comes off cooldown first.
		if InCombatLockdown() then
			-- STUN COMBO polish: while holding Judgement during the Seal GCD,
			-- preview Hammer of Justice (waiting on GCD) with NEXT = Judgement
			-- instead of falling through to a longer Holy Strike cooldown.
			if holdJudgement then
				local gcdRem = self:GetGcdRemaining()
				if gcdRem > 0.15 then
					Add(ns.SPELLS.HAMMER_OF_JUSTICE, true, { isPvp = true, pvpLabel = "STUN COMBO!" })
					self.countdown = gcdRem
					current = candidates[1]
					if not nextAction then
						nextAction = { name = ns.SPELLS.JUDGEMENT, inRange = InRange(ns.SPELLS.JUDGEMENT) }
					end
				end
			end
			if not current then
				for _, item in ipairs(upcoming) do
					if item.remaining <= 0.2 and IsNoMana(item.name) then
						Add(item.name, item.requiresRange)
						self.currentNoMana = true
						current = candidates[1]
						break
					end
				end
			end
			if not current then
				for _, item in ipairs(upcoming) do
					if item.remaining > 0 then
						Add(item.name, item.requiresRange)
						self.countdown = item.remaining
						current = candidates[1]
						break
					end
				end
			end
		end
	end

	-- Populate NEXT preview with the soonest upcoming spell distinct from current.
	if current and not nextAction then
		for _, item in ipairs(upcoming) do
			if item.name ~= current.name then
				nextAction = { name = item.name, inRange = true }
				break
			end
		end
	end

	self.current = current and current.name or nil
	self.next = nextAction and nextAction.name or nil
	if current then
		self.currentInRange = current.inRange
	else
		self.currentInRange = nil
	end
	self.currentIsProc = current and current.isProc == true or false
	self.currentIsInterrupt = current and current.isInterrupt == true or false
	self.currentIsBurst = current and current.isBurst == true or false
	self.currentIsTwist = current and current.isTwist == true and (self.countdown == nil or self.countdown <= 0) or false
	self.currentIsPvp = current and current.isPvp == true or false
	self.currentPvpLabel = current and current.pvpLabel or nil
	self.hasTarget = hasTarget and true or false

	return self.current, self.next
end
