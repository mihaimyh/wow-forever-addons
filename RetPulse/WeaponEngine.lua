local addonName, ns = ...

local WeaponEngine = ns:NewModule("WeaponEngine")

-- Reads the equipped main-hand and turns weapon speed into a seal-pairing hint.
-- Weapon speed never changes the echo cap (always 3): it only decides which seal
-- is the better primary. Nothing here is a recommendation on its own.

function WeaponEngine:OnLogin()
	self:ReadWeapon()

	ns:On("UNIT_INVENTORY_CHANGED", function(_, unit)
		if unit == "player" then self:ReadWeapon() end
	end)
	ns:On("PLAYER_EQUIPMENT_CHANGED", function()
		self:ReadWeapon()
	end)
	ns:On("UNIT_ATTACK_SPEED", function(_, unit)
		if unit == "player" then self:ReadWeapon() end
	end)
	ns:On("SPELLS_CHANGED", function()
		self:RefreshTalents()
	end)
	self:RefreshTalents()
end

local function ParseSpeedFromText(text)
	if type(text) ~= "string" or ns.IsSecret(text) then return nil end
	local speedLabel = (type(SPEED) == "string" and not ns.IsSecret(SPEED) and SPEED ~= "") and SPEED or nil
	local raw
	if speedLabel then
		raw = text:match(speedLabel .. "%s+(%d+[%.%,]%d+)")
	end
	if not raw then
		raw = text:match("[Ss]peed%s+(%d+[%.%,]%d+)")
	end
	if not raw then return nil end
	local val = tonumber((raw:gsub(",", ".")))
	if val and val >= 1.0 and val <= 5.0 then
		return math.floor(val * 100 + 0.5) / 100
	end
	return nil
end

local function ReadTooltipWeaponSpeed()
	if InCombatLockdown and InCombatLockdown() then return nil end
	if not C_TooltipInfo or not C_TooltipInfo.GetInventoryItem then return nil end
	local ok, data = pcall(C_TooltipInfo.GetInventoryItem, "player", 16)
	if not ok or type(data) ~= "table" or ns.IsSecret(data) then return nil end
	local lines = data.lines
	if type(lines) ~= "table" or ns.IsSecret(lines) then return nil end
	for _, line in ipairs(lines) do
		if type(line) == "table" and not ns.IsSecret(line) then
			local okR, rightText = pcall(function() return line.rightText end)
			if okR then
				local sp = ParseSpeedFromText(rightText)
				if sp then return sp end
			end
			local okL, leftText = pcall(function() return line.leftText end)
			if okL then
				local sp = ParseSpeedFromText(leftText)
				if sp then return sp end
			end
		end
	end
	return nil
end

function WeaponEngine:ReadWeapon()
	local ok, itemID = pcall(GetInventoryItemID, "player", 16)
	if ok then
		self.weaponItemID = itemID
	end

	local tracker = ns:GetModule("CombatTracker")
	-- Ensure player seal state is scanned before reading UnitAttackSpeed on login/reload,
	-- because WeaponEngine loads before CombatTracker in the TOC.
	if not InCombatLockdown() and tracker and tracker.RefreshSeal and tracker.activeSeal == nil then
		tracker:RefreshSeal()
	end

	local speedOk, speed = pcall(function()
		return select(1, UnitAttackSpeed("player"))
	end)
	if speedOk and ns.IsReadable(speed) and speed > 0 then
		self.hastedSpeed = speed
	end

	-- Best source out of combat: printed weapon speed from tooltip data, completely
	-- immune to melee haste buffs and Seal of the Crusader (+40% attack speed).
	local tooltipSpeed = ReadTooltipWeaponSpeed()
	if tooltipSpeed then
		self.weaponSpeed = tooltipSpeed
		self.speedItemID = self.weaponItemID
		if ns.db and type(self.weaponItemID) == "number" and not ns.IsSecret(self.weaponItemID) then
			ns.db.weaponSpeedCache = ns.db.weaponSpeedCache or {}
			ns.db.weaponSpeedCache[self.weaponItemID] = self.weaponSpeed
		end
		return
	end

	-- UnitAttackSpeed returns the hasted swing speed (e.g. 2.87s for a 3.30s
	-- weapon under 15% haste like Warchief's Blessing) and becomes secret in
	-- combat. Convert back to the weapon's base speed via GetMeleeHaste() so
	-- haste buffs never downgrade a slow 2H weapon into a faster seal bracket.
	-- Seal of the Crusader also speeds swings by 40% outside GetMeleeHaste():
	-- preserve the already-known base speed for the equipped weapon, or undo 1.4x.
	if speedOk and ns.IsReadable(speed) and speed > 0 then
		local crusaderUp = tracker and tracker.GetActiveSeal and tracker:GetActiveSeal() == ns.SPELLS.SEAL_CRUSADER
		if crusaderUp then
			if self.weaponSpeed and self.speedItemID == self.weaponItemID then
				return
			end
			if ns.db and type(ns.db.weaponSpeedCache) == "table"
				and type(self.weaponItemID) == "number" and not ns.IsSecret(self.weaponItemID) then
				local cached = ns.db.weaponSpeedCache[self.weaponItemID]
				if type(cached) == "number" and cached > 0 then
					self.weaponSpeed = cached
					self.speedItemID = self.weaponItemID
					return
				end
			end
		end

		local baseSpeed = speed
		if GetMeleeHaste then
			local hasteOk, haste = pcall(GetMeleeHaste)
			if hasteOk and ns.IsReadable(haste) and haste > -100 then
				baseSpeed = speed * (1 + haste / 100)
			elseif self.weaponSpeed and self.speedItemID == self.weaponItemID then
				return
			end
		end
		if crusaderUp then
			baseSpeed = baseSpeed * 1.4
		end
		self.weaponSpeed = math.floor(baseSpeed * 100 + 0.5) / 100
		self.speedItemID = self.weaponItemID
		if (not crusaderUp) and ns.db and type(self.weaponItemID) == "number" and not ns.IsSecret(self.weaponItemID) then
			ns.db.weaponSpeedCache = ns.db.weaponSpeedCache or {}
			ns.db.weaponSpeedCache[self.weaponItemID] = self.weaponSpeed
		end
	elseif (not self.weaponSpeed or self.speedItemID ~= self.weaponItemID)
		and ns.db and type(ns.db.weaponSpeedCache) == "table"
		and type(self.weaponItemID) == "number" and not ns.IsSecret(self.weaponItemID) then
		local cached = ns.db.weaponSpeedCache[self.weaponItemID]
		if type(cached) == "number" and cached > 0 then
			self.weaponSpeed = cached
			self.speedItemID = self.weaponItemID
		end
	end
end

function WeaponEngine:RefreshTalents()
	local tracker = ns:GetModule("CombatTracker")

	-- Rank-independent: the talent's own spell is 1310735. A passive talent can
	-- also be invisible to IsSpellKnown, so accept it when the Cooldown Manager
	-- exposes it, and always allow a manual override.
	local known = false
	if C_SpellBook and C_SpellBook.IsSpellKnown then
		local okK, isKnown = pcall(C_SpellBook.IsSpellKnown, 1310735)
		known = okK and not ns.IsSecret(isKnown) and isKnown and true or false
	end
	if not known and tracker and tracker.cdmFrames and #tracker.cdmFrames > 0 then
		known = true
	end
	if ns.db and ns.db.forceUnsealedWrath then
		known = true
	end
	self.hasUnsealedWrath = known

	self.hasSealOfCommand = (tracker and tracker:IsSealAvailable(ns.SPELLS.SEAL_COMMAND))
		or ns.IsSpellKnownByName(ns.SPELLS.SEAL_COMMAND)
end

function WeaponEngine:GetBracket()
	local speed = self.weaponSpeed
	if not speed then return "unknown" end

	local mode = (ns.db and ns.db.bracketMode) or "video"

	if mode == "video" then
		-- Three brackets from the Unsealed Wrath deep dive, with 0.05s float
		-- tolerance so de-hasting a 2.50s or 3.20s weapon never drifts up a tier.
		if speed <= 2.55 then return "fast" end
		if speed <= 3.25 then return "medium" end
		return "slow"
	end

	-- Two brackets: Icy Veins treats 2.9 and faster as fast, 3.0+ as slow.
	if speed < 2.95 then return "fast" end
	return "slow"
end

-- The hint, not the rotation: fast weapons lean Righteousness, slow ones Command.
function WeaponEngine:GetPrimarySealHint()
	local rot = self:GetRotation()
	return rot and rot.primary or nil
end

-- Seal pairs by weapon speed, from the Unsealed Wrath simulations.
-- Every pair is "build N in the primary seal, detonate with 1 in the secondary".
local ROTATIONS = {
	fast   = { primary = ns.SPELLS.SEAL_RIGHT, primaryStacks = 3,
	           secondary = ns.SPELLS.SEAL_FURY, secondaryStacks = 1 },
	medium = { primary = ns.SPELLS.SEAL_RIGHT, primaryStacks = 2,
	           secondary = ns.SPELLS.SEAL_COMMAND, secondaryStacks = 1 },
	slow   = { primary = ns.SPELLS.SEAL_COMMAND, primaryStacks = 3,
	           secondary = ns.SPELLS.SEAL_RIGHT, secondaryStacks = 1 },
}

-- Single-seal selections when Unsealed Wrath is not learned (e.g. Level 20-39
-- leveling with Seal of Command, or Level 60 non-Unsealed-Wrath / Holy Shock).
local SINGLE_SEAL = {
	right   = { primary = ns.SPELLS.SEAL_RIGHT, primaryStacks = 3,
	            secondary = nil, secondaryStacks = 1 },
	command = { primary = ns.SPELLS.SEAL_COMMAND, primaryStacks = 3,
	            secondary = nil, secondaryStacks = 1 },
}

local FALLBACK = ROTATIONS.fast

function WeaponEngine:HasSealOfCommand()
	return self.hasSealOfCommand == true
end

function WeaponEngine:GetRotation()
	local hasUW = (self.hasUnsealedWrath == true) or (ns.db and ns.db.twistWithoutTalent == true)

	-- Without Seal of Command (levels 1-19 or untalented), Righteousness is primary
	-- (and if Unsealed Wrath / twistWithoutTalent is active, twists with Fury).
	if not self:HasSealOfCommand() then
		return hasUW and FALLBACK or SINGLE_SEAL.right
	end

	-- With Seal of Command but WITHOUT Unsealed Wrath (levels 20-39 leveling or
	-- non-UW builds): no echoes exist to justify the 2x SoR -> 1x SoC medium twist,
	-- so two-handed weapons (>= 2.6s in default mode, >= 3.0s in Icy mode) stay on
	-- Seal of Command while fast 1H weapons stay on Seal of Righteousness.
	local bracket = self:GetBracket()
	if not hasUW then
		if bracket == "fast" then
			return SINGLE_SEAL.right
		end
		return SINGLE_SEAL.command
	end

	return ROTATIONS[bracket] or FALLBACK
end

function WeaponEngine:DebugLine()
	local rotation = self:GetRotation()
	local speed = self.weaponSpeed
	if speed == nil or ns.IsSecret(speed) then
		speed = "?"
	else
		speed = string.format("%.2f", speed)
	end
	return string.format("wpn speed=%s bracket=%s mode=%s uw=%s soc=%s pair=%s/%d+%s",
		speed,
		tostring(self:GetBracket()),
		tostring(ns.db and ns.db.bracketMode),
		tostring(self.hasUnsealedWrath),
		tostring(self.hasSealOfCommand),
		tostring(rotation and rotation.primary),
		rotation and rotation.primaryStacks or 0,
		tostring(rotation and rotation.secondary))
end
