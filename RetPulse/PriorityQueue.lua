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
}

-- Judgement is off the global cooldown in Forever, so it never blocks the queue.
local GCD = 1.5
local OFF_GCD = { ["Judgement"] = true }
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
			end
		end
		return nil, nil
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
		return 0, "idle"
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
	if not tracker:IsSealAvailable(primaryName) then
		if tracker:IsSealAvailable(ns.SPELLS.SEAL_RIGHT) or not tracker:IsSealAvailable(ns.SPELLS.SEAL_COMMAND) then
			primaryName = ns.SPELLS.SEAL_RIGHT
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

-- True when the echoes are at the cap of the active primary seal and a
-- secondary seal exists to detonate them (timing windows are checked by the
-- caller). Shared by the queue and the HUD so the rule lives in one place.
function PriorityQueue:IsTwistReady(hasUnsealedWrath)
	if not hasUnsealedWrath then return false end
	local tracker = ns:GetModule("CombatTracker")
	local primaryName, primaryStacks, secondaryName = self:GetSealPair()
	return secondaryName ~= nil
		and tracker:GetActiveSeal() == primaryName
		and tracker:GetEchoes() >= primaryStacks
end

function PriorityQueue:Evaluate()
	local tracker = ns:GetModule("CombatTracker")
	local engine = ns:GetModule("WeaponEngine")
	local db = ns.db or {}
	local hasUnsealedWrath = (engine and engine.hasUnsealedWrath == true) or (db.twistWithoutTalent == true)

	local primaryName, primaryStacks, secondaryName = self:GetSealPair()
	local activeSeal = tracker:GetActiveSeal()
	local echoes = tracker:GetEchoes()
	local swingsWithSeal = tracker:GetSwingsWithSeal()

	local hasTarget = UnitExists("target") and UnitCanAttack("player", "target")
	local creatureType = hasTarget and UnitCreatureType("target") or nil
	if creatureType ~= nil and ns.IsSecret(creatureType) then creatureType = nil end
	local exorcismTarget = creatureType == "Undead" or creatureType == "Demon"
	local swingOpen = tracker:IsSwingWindowOpen(GCD)
	local gcdReady = self:GetGcdRemaining() <= 0.15

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
		}
	end

	-- -1. Interrupt: if the target is casting an interruptible spell and
	--     Hammer of Justice is ready & in range, prioritize the interrupt.
	if hasTarget and (db.suggestInterrupt ~= false) and gcdReady
		and tracker and tracker.IsTargetCastingInterruptible and tracker:IsTargetCastingInterruptible()
		and IsKnown(ns.SPELLS.HAMMER_OF_JUSTICE) and IsUsable(ns.SPELLS.HAMMER_OF_JUSTICE)
		and self:IsReady(ns.SPELLS.HAMMER_OF_JUSTICE) and InRange(ns.SPELLS.HAMMER_OF_JUSTICE) then
		Add(ns.SPELLS.HAMMER_OF_JUSTICE, true, { isInterrupt = true })
	end

	-- 0a. Boss / Elite opener: apply Judgement of the Crusader once per target.
	local cls = hasTarget and UnitClassification and UnitClassification("target") or nil
	if cls ~= nil and ns.IsSecret(cls) then cls = nil end
	local isBossOrElite = (cls == "worldboss" or cls == "elite" or cls == "rareelite")
	local needCrusader = hasTarget and (db.crusaderOnBoss ~= false) and isBossOrElite
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

	-- 1. Twist: echoes are at the cap for the active seal, so change seals.
	--    A seal swap is a global: it must fit before the next swing.
	if hasUnsealedWrath and secondaryName and activeSeal == primaryName and echoes >= primaryStacks and swingOpen and gcdReady then
		Add(secondaryName, false)
	end

	-- 1.5. Glowing procs (Blizzard SpellActivationOverlay): react immediately to
	--      any combat proc that lights up a known rotational spell.
	local furyUp = activeSeal == ns.SPELLS.SEAL_FURY
	if hasTarget and tracker and tracker.IsSpellGlowing then
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

	-- 2. Judgement. Never while Seal of Fury is up: its Judgement is a taunt.
	if hasTarget and not furyUp and IsUsable(ns.SPELLS.JUDGEMENT) and self:IsReady(ns.SPELLS.JUDGEMENT) then
		Add(ns.SPELLS.JUDGEMENT, true)
	end

	-- 3. Hammer of Wrath (execute <= 20%, only in an open swing window so it
	--    does not clip a white hit). Higher priority than Holy Strike / Exorcism.
	if hasTarget and swingOpen and gcdReady and IsUsable(ns.SPELLS.HAMMER_OF_WRATH) and self:IsReady(ns.SPELLS.HAMMER_OF_WRATH) then
		Add(ns.SPELLS.HAMMER_OF_WRATH, true)
	end

	-- 4. AoE priority when manual AoE is on OR Auto-AoE detects 2+ hostile mobs
	--    in melee range via nameplates.
	local autoAoeActive = (db.autoAoe ~= false) and tracker and tracker.GetMeleeEnemyCount and (tracker:GetMeleeEnemyCount() >= 2)
	local aoeActive = (db.aoe == true) or autoAoeActive
	if aoeActive and gcdReady and IsUsable(ns.SPELLS.CONSECRATION) and self:IsReady(ns.SPELLS.CONSECRATION) then
		Add(ns.SPELLS.CONSECRATION, false)
	end
	if aoeActive and hasTarget and exorcismTarget and gcdReady and IsUsable(ns.SPELLS.HOLY_WRATH) and self:IsReady(ns.SPELLS.HOLY_WRATH) then
		Add(ns.SPELLS.HOLY_WRATH, false)
	end

	-- 5. Holy Strike, core melee rotational ability.
	if hasTarget and gcdReady and IsUsable(ns.SPELLS.HOLY_STRIKE) and self:IsReady(ns.SPELLS.HOLY_STRIKE) then
		Add(ns.SPELLS.HOLY_STRIKE, true)
	end

	-- 6. Exorcism, only against Undead and Demons: UnitCreatureType is readable.
	if hasTarget and exorcismTarget and gcdReady and IsUsable(ns.SPELLS.EXORCISM) and self:IsReady(ns.SPELLS.EXORCISM) then
		Add(ns.SPELLS.EXORCISM, true)
	end

	-- 7. Holy Shock, for hybrid/Shockadin builds when talented.
	if hasTarget and gcdReady and IsKnown(ns.SPELLS.HOLY_SHOCK) and IsUsable(ns.SPELLS.HOLY_SHOCK) and self:IsReady(ns.SPELLS.HOLY_SHOCK) then
		Add(ns.SPELLS.HOLY_SHOCK, true)
	end

	-- 8. Seal upkeep (return to primary after the detonating swing landed).
	if hasUnsealedWrath and primaryName and secondaryName and activeSeal == secondaryName and gcdReady then
		if swingsWithSeal >= 1 and echoes < primaryStacks then
			Add(primaryName, false)
		end
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
		if swingOpen and IsUsable(ns.SPELLS.HAMMER_OF_WRATH) then
			ConsiderUpcoming(ns.SPELLS.HAMMER_OF_WRATH, true)
		end
		ConsiderUpcoming(ns.SPELLS.HOLY_SHOCK, true)
	end
	if aoeActive then
		ConsiderUpcoming(ns.SPELLS.CONSECRATION, false)
		if hasTarget and exorcismTarget then
			ConsiderUpcoming(ns.SPELLS.HOLY_WRATH, false)
		end
	end

	table.sort(upcoming, function(a, b)
		return a.remaining < b.remaining
	end)

	self.countdown = nil
	self.currentNoMana = false
	if not current then
		-- Nothing castable right now: first check if a ready spell is blocked
		-- specifically by insufficient mana (insufficientPower from IsSpellUsable),
		-- otherwise show what comes off cooldown first.
		if InCombatLockdown() then
			for _, item in ipairs(upcoming) do
				if item.remaining <= 0.2 and IsNoMana(item.name) then
					Add(item.name, item.requiresRange)
					self.currentNoMana = true
					current = candidates[1]
					break
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
	self.currentInRange = current and current.inRange or nil
	self.currentIsProc = current and current.isProc == true or false
	self.currentIsInterrupt = current and current.isInterrupt == true or false
	self.hasTarget = hasTarget and true or false

	return self.current, self.next
end
