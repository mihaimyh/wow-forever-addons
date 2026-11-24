local addonName, ns = ...

local PvPEngine = ns:NewModule("PvPEngine")

-- Situational PvP intelligence module for WoW: Forever (Interface 16001).
-- Strictly isolated from PvE: every offensive/tactical rule runs ONLY when
-- targeting an attackable enemy player, and defensive rules run ONLY against
-- enemy players or inside Battlegrounds/Arenas.
-- Compatible with all Paladin levels via runtime spell-known & usability checks.

local IsKnown = ns.IsSpellKnownByName
local SafeBool = ns.SafeBool

local HEAL_SPELLS = {
	["Flash Heal"] = true,
	["Greater Heal"] = true,
	["Heal"] = true,
	["Lesser Heal"] = true,
	["Binding Heal"] = true,
	["Prayer of Healing"] = true,
	["Holy Light"] = true,
	["Flash of Light"] = true,
	["Healing Touch"] = true,
	["Regrowth"] = true,
	["Healing Wave"] = true,
	["Lesser Healing Wave"] = true,
	["Chain Heal"] = true,
}

local CASTER_HEALER_CLASSES = {
	PRIEST = true,
	MAGE = true,
	WARLOCK = true,
	DRUID = true,
	SHAMAN = true,
}

local PHYSICAL_CLASSES = {
	WARRIOR = true,
	ROGUE = true,
	HUNTER = true,
	PALADIN = true,
}

local STUN_DR_DURATION = { 6.0, 3.0, 1.5, 0 }

function PvPEngine:OnLogin()
	self.stunDR = {}
	self.knownHealers = {}
	self.targetImmuneUntil = nil
	self.hojActiveUntil = nil
	self.hojTargetKey = nil
	self.repActiveUntil = nil
	self.repTargetKey = nil
	self.targetBlinkedUntil = nil
	self.stealthVanishUntil = nil
	self.burstActiveUntil = nil
	self.offTargetAlert = nil
	self.lastPvpTargetClass = nil
	self.lastPvpTargetWasMelee = false
	self.lastPvpTargetDead = false

	ns:On("UNIT_COMBAT", function(_, unit, action)
		if unit ~= "target" or ns.IsSecret(action) or type(action) ~= "string" then return end
		if not self:IsPvpTarget() then return end
		if action == "IMMUNE" then
			self.targetImmuneUntil = GetTime() + 8.0
		elseif action == "WOUND" then
			self.targetImmuneUntil = nil
		end
	end)

	ns:On("UI_ERROR_MESSAGE", function(_, _, message)
		if type(message) ~= "string" or ns.IsSecret(message) then return end
		if not self:IsPvpTarget() then return end
		local isImmune = (SPELL_FAILED_IMMUNE and message == SPELL_FAILED_IMMUNE)
			or message:lower():find("immune", 1, true) ~= nil
		if isImmune then
			self.targetImmuneUntil = GetTime() + 8.0
		end
	end)

	ns:On("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, _, spellID)
		local name = ns.GetSpellNameByID(spellID)
		if not name then return end
		local now = GetTime()

		if unit == "player" then
			if name == ns.SPELLS.HAMMER_OF_JUSTICE and self:IsPvpTarget() then
				local key = self:GetTargetKey()
				local entry = self.stunDR[key]
				local level = 1
				if entry and now < entry.resetAt then
					level = math.min(4, entry.level + 1)
				end
				local dur = STUN_DR_DURATION[level] or 0
				self.stunDR[key] = { level = level, resetAt = now + 18.0 }
				if dur > 0 then
					self.hojActiveUntil = now + dur
					self.hojTargetKey = key
				else
					self.hojActiveUntil = nil
				end
				self.repActiveUntil = nil
			elseif name == ns.SPELLS.REPENTANCE and self:IsPvpTarget() then
				local key = self:GetTargetKey()
				self.repActiveUntil = now + 6.0
				self.repTargetKey = key
			elseif name == ns.SPELLS.CONSECRATION then
				self.stealthVanishUntil = nil
			elseif name == ns.SPELLS.AVENGING_WRATH or name == ns.SPELLS.BLOOD_FURY or name == ns.SPELLS.BERSERKING then
				self.burstActiveUntil = now + 15.0
			end
		elseif unit == "target" and self:IsPvpTarget() then
			if name == "Blink" then
				self.hojActiveUntil = nil
				self.targetBlinkedUntil = now + 4.0
			end
		end
	end)

	local function OnTargetCast(_, unit, _, spellID)
		if unit ~= "target" or not self:IsPvpTarget() then return end
		self.hojActiveUntil = nil
		self.repActiveUntil = nil
		local name = ns.GetSpellNameByID(spellID)
		if name and HEAL_SPELLS[name] then
			local key = self:GetTargetKey()
			if key then
				self.knownHealers[key] = true
			end
		end
	end
	ns:On("UNIT_SPELLCAST_START", OnTargetCast)
	ns:On("UNIT_SPELLCAST_CHANNEL_START", OnTargetCast)

	ns:On("PLAYER_TARGET_CHANGED", function()
		local exists = SafeBool(UnitExists, "target") == true
		if InCombatLockdown()
			and (self.lastPvpTargetClass == "ROGUE" or self.lastPvpTargetClass == "DRUID")
			and self.lastPvpTargetWasMelee
			and not self.lastPvpTargetDead
			and not exists then
			self.stealthVanishUntil = GetTime() + 2.5
		end

		self.targetImmuneUntil = nil
		self.hojActiveUntil = nil
		self.hojTargetKey = nil
		self.repActiveUntil = nil
		self.repTargetKey = nil
		self.targetBlinkedUntil = nil
		self.lastPvpTargetClass = nil
		self.lastPvpTargetWasMelee = false
		self.lastPvpTargetDead = false
	end)

	ns:On("PLAYER_REGEN_ENABLED", function()
		self.targetImmuneUntil = nil
		self.hojActiveUntil = nil
		self.hojTargetKey = nil
		self.repActiveUntil = nil
		self.repTargetKey = nil
		self.targetBlinkedUntil = nil
		self.stealthVanishUntil = nil
		self.burstActiveUntil = nil
		self.lastPvpTargetClass = nil
		self.lastPvpTargetWasMelee = false
		self.lastPvpTargetDead = false
		self.offTargetAlert = nil
	end)
end

-------------------------------------------------------------------------------
-- Strict PvP Firewall
-------------------------------------------------------------------------------
function PvPEngine:IsPvpTarget()
	if ns.db and ns.db.pvpEnabled == false then return false end
	local tracker = ns:GetModule("CombatTracker")
	return tracker and tracker.IsPvpTarget and tracker:IsPvpTarget() or false
end

function PvPEngine:IsPvpContext()
	if ns.db and ns.db.pvpEnabled == false then return false end
	if self:IsPvpTarget() or self:IsStealthVanishActive() then return true end
	local tracker = ns:GetModule("CombatTracker")
	return tracker and tracker.IsInBattleground and tracker:IsInBattleground() or false
end

-------------------------------------------------------------------------------
-- Target Inspection Helpers (Secret-safe)
-------------------------------------------------------------------------------
function PvPEngine:GetTargetKey()
	if SafeBool(UnitExists, "target") ~= true then return nil end
	if UnitGUID then
		local ok, guid = pcall(UnitGUID, "target")
		if ok and ns.IsReadable(guid) and guid ~= "" then
			return guid
		end
	end
	if UnitName then
		local ok, name = pcall(UnitName, "target")
		if ok and ns.IsReadable(name) and name ~= "" then
			return name
		end
	end
	return "target"
end

function PvPEngine:GetTargetClass()
	if SafeBool(UnitExists, "target") ~= true or not UnitClass then return nil end
	local ok, _, token = pcall(UnitClass, "target")
	if ok and ns.IsReadable(token) and type(token) == "string" then
		return token
	end
	return nil
end

function PvPEngine:NoteTargetObservation(tracker)
	if not self:IsPvpTarget() then return end
	local cls = self:GetTargetClass()
	if cls then self.lastPvpTargetClass = cls end
	if tracker then
		self.lastPvpTargetWasMelee = (tracker.hadMeleeWithTarget == true) or (tracker.IsInSwingRange and tracker:IsInSwingRange() == true)
	end
	if UnitIsDead then
		local ok, dead = pcall(UnitIsDead, "target")
		self.lastPvpTargetDead = (ok and ns.IsReadable(dead) and dead == true) or false
	end
end

function PvPEngine:IsTargetImmune()
	if ns.db and ns.db.pvpAntiImmune == false then return false end
	return self.targetImmuneUntil ~= nil and GetTime() < self.targetImmuneUntil
end

function PvPEngine:IsTargetStunnedByUs()
	if not self.hojActiveUntil or GetTime() >= self.hojActiveUntil then return false end
	local key = self:GetTargetKey()
	return key ~= nil and self.hojTargetKey == key
end

function PvPEngine:IsTargetRepentancedByUs()
	if not self.repActiveUntil or GetTime() >= self.repActiveUntil then return false end
	local key = self:GetTargetKey()
	return key ~= nil and self.repTargetKey == key
end

function PvPEngine:IsStunOnDR()
	local key = self:GetTargetKey()
	if not key or not self.stunDR then return false end
	local entry = self.stunDR[key]
	if not entry or GetTime() >= entry.resetAt then return false end
	return entry.level >= 1
end

function PvPEngine:IsTargetHealer()
	if self:GetTargetClass() == "PRIEST" then return true end
	local key = self:GetTargetKey()
	return key ~= nil and self.knownHealers and self.knownHealers[key] == true or false
end

function PvPEngine:IsTargetBlinked()
	return self.targetBlinkedUntil ~= nil and GetTime() < self.targetBlinkedUntil
end

function PvPEngine:IsStealthVanishActive()
	if ns.db and ns.db.pvpAntiStealth == false then return false end
	return self.stealthVanishUntil ~= nil and GetTime() < self.stealthVanishUntil
end

-------------------------------------------------------------------------------
-- Loss of Control, Trinkets & Focused Survival
-------------------------------------------------------------------------------
function PvPEngine:GetLossOfControlInfo()
	local info = {
		hasAny = false,
		hasFearCharmSleep = false,
		hasHardCC = false,
		hasRoot = false,
		hasSnare = false,
		maxRemaining = nil,
	}

	if C_LossOfControl and C_LossOfControl.GetActiveLossOfControlDataCount then
		local okC, count = pcall(C_LossOfControl.GetActiveLossOfControlDataCount)
		if okC and ns.IsReadable(count) and type(count) == "number" and count > 0 then
			info.hasAny = true
			if not C_LossOfControl.GetActiveLossOfControlData then
				-- Minimal client/test mock fallback: treat unknown active LoC safely as Fear/CC.
				info.hasFearCharmSleep = true
				info.hasHardCC = true
			else
				for i = 1, count do
					local okD, data = pcall(C_LossOfControl.GetActiveLossOfControlData, i)
					if okD and type(data) == "table" and not ns.IsSecret(data) and ns.IsReadable(data.locType) then
						local t = data.locType
						local rem = ns.IsReadable(data.timeRemaining) and type(data.timeRemaining) == "number" and data.timeRemaining or nil
						if t == "FEAR" or t == "FEAR_MECHANIC" or t == "CHARM" or t == "POSSESS" or t == "SLEEP" or t == "HORROR" then
							info.hasFearCharmSleep = true
							info.hasHardCC = true
							if rem and (not info.maxRemaining or rem > info.maxRemaining) then info.maxRemaining = rem end
						elseif t == "STUN" or t == "STUN_MECHANIC" or t == "CONFUSE" or t == "INCAPACITATE" or t == "POLYMORPH" then
							info.hasHardCC = true
							if rem and (not info.maxRemaining or rem > info.maxRemaining) then info.maxRemaining = rem end
						elseif t == "ROOT" then
							info.hasRoot = true
						elseif t == "SNARE" then
							info.hasSnare = true
						end
					end
				end
			end
		end
	end

	if GetUnitSpeed then
		local okS, speed = pcall(GetUnitSpeed, "player")
		if okS and ns.IsReadable(speed) and type(speed) == "number" and speed > 0 and speed < 6.5 then
			info.hasSnare = true
		end
	end

	return info
end

function PvPEngine:IsPvpTrinketSpellName(spellName)
	if type(spellName) ~= "string" then return false end
	local lower = spellName:lower()
	return lower:find("pvp trinket", 1, true) ~= nil
		or lower:find("insignia", 1, true) ~= nil
		or lower:find("medallion", 1, true) ~= nil
		or lower:find("will to survive", 1, true) ~= nil
end

function PvPEngine:FindReadyPvpTrinket()
	if not GetInventoryItemID or not C_Item or not C_Item.GetItemSpell or not C_Item.GetItemCooldown then
		return nil
	end
	for _, slot in ipairs({ 13, 14 }) do
		local okI, itemID = pcall(GetInventoryItemID, "player", slot)
		if okI and type(itemID) == "number" and not ns.IsSecret(itemID) then
			local okS, spellName = pcall(C_Item.GetItemSpell, itemID)
			if okS and type(spellName) == "string" and not ns.IsSecret(spellName) and self:IsPvpTrinketSpellName(spellName) then
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

-------------------------------------------------------------------------------
-- 360 Nameplate & Group Awareness
-------------------------------------------------------------------------------
local function IsUnitLivingHostilePlayer(unit)
	if type(unit) ~= "string" or ns.IsSecret(unit) then return false end
	if SafeBool(UnitExists, unit) ~= true then return false end
	if UnitIsDead and SafeBool(UnitIsDead, unit) ~= false then return false end
	if UnitCanAttack and SafeBool(UnitCanAttack, "player", unit) ~= true then return false end
	if UnitIsPlayer and SafeBool(UnitIsPlayer, unit) ~= true then return false end
	return true
end

function PvPEngine:CountAttackersOnPlayer(tracker)
	local now = GetTime()
	if self.attackersCache ~= nil and self.attackersCacheAt and (now - self.attackersCacheAt) < 0.2 then
		return self.attackersCache
	end
	if not tracker or not tracker.GetActiveNameplateUnits then return 0 end

	local count = 0
	for unit in pairs(tracker:GetActiveNameplateUnits()) do
		if IsUnitLivingHostilePlayer(unit) and SafeBool(UnitIsUnit, unit .. "target", "player") == true then
			count = count + 1
		end
	end
	self.attackersCache = count
	self.attackersCacheAt = now
	return count
end

local function IsUnitCastingInterruptible(unit)
	if UnitCastingInfo then
		local ok, castName, _, _, _, _, _, _, notInt = pcall(UnitCastingInfo, unit)
		if ok and castName ~= nil and ns.IsReadable(notInt) and notInt == false then
			return true
		end
	end
	if UnitChannelInfo then
		local ok, chanName, _, _, _, _, _, notInt = pcall(UnitChannelInfo, unit)
		if ok and chanName ~= nil and ns.IsReadable(notInt) and notInt == false then
			return true
		end
	end
	return false
end

local function IsSpellInRangeUnit(spellName, unit)
	if not spellName or not unit or not C_Spell or not C_Spell.IsSpellInRange then return false end
	local ok, r = pcall(C_Spell.IsSpellInRange, spellName, unit)
	if not ok or not ns.IsReadable(r) then return false end
	return r and true or false
end

function PvPEngine:FindOffTargetCast(tracker, pq, IsUsableFn)
	if ns.db and (ns.db.pvpEnabled == false or ns.db.pvpOffTargetAlert == false) then
		self.offTargetAlert = nil
		return nil
	end
	local now = GetTime()
	if self.offTargetCacheAt and (now - self.offTargetCacheAt) < 0.15 then
		return self.offTargetAlert
	end
	self.offTargetCacheAt = now

	if not tracker or not tracker.GetActiveNameplateUnits or not pq then
		self.offTargetAlert = nil
		return nil
	end

	local hojReady = IsKnown(ns.SPELLS.HAMMER_OF_JUSTICE)
		and (not IsUsableFn or IsUsableFn(ns.SPELLS.HAMMER_OF_JUSTICE))
		and pq:IsReady(ns.SPELLS.HAMMER_OF_JUSTICE)
	local repReady = IsKnown(ns.SPELLS.REPENTANCE)
		and (not IsUsableFn or IsUsableFn(ns.SPELLS.REPENTANCE))
		and pq:IsReady(ns.SPELLS.REPENTANCE)

	if not hojReady and not repReady then
		self.offTargetAlert = nil
		return nil
	end

	for unit in pairs(tracker:GetActiveNameplateUnits()) do
		local isCurrentTarget = SafeBool(UnitIsUnit, unit, "target") == true
		if (not isCurrentTarget) and IsUnitLivingHostilePlayer(unit) and IsUnitCastingInterruptible(unit) then
			local kickSpell
			if hojReady and IsSpellInRangeUnit(ns.SPELLS.HAMMER_OF_JUSTICE, unit) then
				kickSpell = ns.SPELLS.HAMMER_OF_JUSTICE
			elseif repReady and IsSpellInRangeUnit(ns.SPELLS.REPENTANCE, unit) then
				kickSpell = ns.SPELLS.REPENTANCE
			end
			if kickSpell then
				local casterName = "Caster"
				if UnitName then
					local okN, n = pcall(UnitName, unit)
					if okN and ns.IsReadable(n) and n ~= "" then casterName = n end
				end
				self.offTargetAlert = { spell = kickSpell, caster = casterName, unit = unit }
				return self.offTargetAlert
			end
		end
	end

	self.offTargetAlert = nil
	return nil
end

function PvPEngine:GetOffTargetAlert()
	if ns.db and (ns.db.pvpEnabled == false or ns.db.pvpOffTargetAlert == false) then
		return nil
	end
	return self.offTargetAlert
end

function PvPEngine:FindPeelAction(pq, IsUsableFn, InRangeFn)
	if ns.db and ns.db.pvpPeel == false then return nil end
	if SafeBool(IsInGroup) ~= true then return nil end
	if not self:IsPvpTarget() then return nil end
	if SafeBool(UnitExists, "targettarget") ~= true then return nil end
	if SafeBool(UnitIsUnit, "targettarget", "player") ~= false then return nil end
	if SafeBool(UnitIsFriend, "player", "targettarget") ~= true then return nil end

	local ttClass
	if UnitClass then
		local okC, _, token = pcall(UnitClass, "targettarget")
		if okC and ns.IsReadable(token) then ttClass = token end
	end
	if not ttClass or not CASTER_HEALER_CLASSES[ttClass] then return nil end

	if not self:IsTargetStunnedByUs() and not self:IsTargetRepentancedByUs() and not self:IsStunOnDR()
		and IsKnown(ns.SPELLS.HAMMER_OF_JUSTICE)
		and IsUsableFn(ns.SPELLS.HAMMER_OF_JUSTICE)
		and pq:IsReady(ns.SPELLS.HAMMER_OF_JUSTICE)
		and InRangeFn(ns.SPELLS.HAMMER_OF_JUSTICE) then
		return ns.SPELLS.HAMMER_OF_JUSTICE, "PEEL!"
	end

	local atkClass = self:GetTargetClass()
	if atkClass and PHYSICAL_CLASSES[atkClass]
		and IsKnown(ns.SPELLS.BLESSING_PROTECTION)
		and IsUsableFn(ns.SPELLS.BLESSING_PROTECTION)
		and pq:IsReady(ns.SPELLS.BLESSING_PROTECTION)
		and IsSpellInRangeUnit(ns.SPELLS.BLESSING_PROTECTION, "targettarget") then
		return ns.SPELLS.BLESSING_PROTECTION, "PEEL BoP!"
	end

	return nil
end

-------------------------------------------------------------------------------
-- Matchup & Burst Gating
-------------------------------------------------------------------------------
function PvPEngine:IsBurstWindowReady(tracker, activeSeal, pq)
	if activeSeal == nil or self:IsTargetImmune() then return false end
	if ns.db and ns.db.pvpSmartMatchup == false then
		return true
	end
	if self:GetLossOfControlInfo().hasHardCC then return false end
	local inMelee = tracker and tracker.IsInSwingRange and tracker:IsInSwingRange() or false
	if not inMelee and not self:IsTargetStunnedByUs() then return false end
	if pq and (pq:GetRemaining(ns.SPELLS.JUDGEMENT) or 0) > 2.5 then return false end
	return true
end

function PvPEngine:CanRecommendStunCombo(ctx)
	if ns.db and ns.db.pvpStunCombo == false then return false end
	if ctx.targetImmune or self:IsTargetStunnedByUs() or self:IsTargetRepentancedByUs() or self:IsStunOnDR() then
		return false
	end
	if (not ns.db or ns.db.pvpSmartMatchup ~= false) and self:IsTargetHealer() then
		local inExecute = IsKnown(ns.SPELLS.HAMMER_OF_WRATH) and ctx.IsUsable(ns.SPELLS.HAMMER_OF_WRATH)
		local burstUp = self.burstActiveUntil ~= nil and GetTime() < self.burstActiveUntil
		if not inExecute and not burstUp then
			return false
		end
	end
	return true
end

function PvPEngine:ShouldHoldJudgementForStunCombo(ctx)
	if ctx.gcdReady or ctx.activeSeal ~= ns.SPELLS.SEAL_COMMAND then return false end
	if not self:CanRecommendStunCombo(ctx) then return false end
	return IsKnown(ns.SPELLS.HAMMER_OF_JUSTICE)
		and ctx.IsUsable(ns.SPELLS.HAMMER_OF_JUSTICE)
		and ctx.pq:IsReady(ns.SPELLS.HAMMER_OF_JUSTICE)
		and ctx.InRange(ns.SPELLS.HAMMER_OF_JUSTICE)
		and IsKnown(ns.SPELLS.JUDGEMENT)
		and ctx.IsUsable(ns.SPELLS.JUDGEMENT)
		and ctx.pq:IsReady(ns.SPELLS.JUDGEMENT)
end
