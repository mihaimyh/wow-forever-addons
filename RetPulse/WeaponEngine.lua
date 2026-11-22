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

function WeaponEngine:ReadWeapon()
	local ok, itemID = pcall(GetInventoryItemID, "player", 16)
	if ok then
		self.weaponItemID = itemID
	end

	local speedOk, speed = pcall(function()
		return select(1, UnitAttackSpeed("player"))
	end)

	-- UnitAttackSpeed returns the hasted swing speed (e.g. 2.87s for a 3.30s
	-- weapon under 15% haste like Warchief's Blessing) and becomes secret in
	-- combat. Convert back to the weapon's base speed via GetMeleeHaste() so
	-- haste buffs never downgrade a slow 2H weapon into a faster seal bracket.
	if speedOk and ns.IsReadable(speed) and speed > 0 then
		self.hastedSpeed = speed
		if GetMeleeHaste then
			local hasteOk, haste = pcall(GetMeleeHaste)
			if hasteOk and ns.IsReadable(haste) and haste > -100 then
				local baseSpeed = speed * (1 + haste / 100)
				self.weaponSpeed = math.floor(baseSpeed * 100 + 0.5) / 100
			elseif not self.weaponSpeed then
				self.weaponSpeed = math.floor(speed * 100 + 0.5) / 100
			end
		else
			self.weaponSpeed = math.floor(speed * 100 + 0.5) / 100
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

	self.hasSealOfCommand = (tracker and tracker:IsSealAvailable(ns.SPELLS.SEAL_COMMAND)) or false
	if not self.hasSealOfCommand and C_Spell and C_Spell.GetSpellIDForSpellIdentifier and C_SpellBook and C_SpellBook.IsSpellKnown then
		local okId, id = pcall(C_Spell.GetSpellIDForSpellIdentifier, ns.SPELLS.SEAL_COMMAND)
		if okId and type(id) == "number" and not ns.IsSecret(id) then
			local okK, isKnown = pcall(C_SpellBook.IsSpellKnown, id)
			self.hasSealOfCommand = okK and not ns.IsSecret(isKnown) and isKnown and true or false
		end
	end
end

function WeaponEngine:GetBracket()
	local speed = self.weaponSpeed
	if not speed then return "unknown" end

	local mode = (ns.db and ns.db.bracketMode) or "video"

	if mode == "video" then
		-- Three brackets, from the Unsealed Wrath deep dive.
		if speed <= 2.5 then return "fast" end
		if speed <= 3.2 then return "medium" end
		return "slow"
	end

	-- Two brackets: Icy Veins treats 2.9 and faster as fast, 3.0+ as slow.
	if speed < 3.0 then return "fast" end
	return "slow"
end

-- The hint, not the rotation: fast weapons lean Righteousness, slow ones Command.
function WeaponEngine:GetPrimarySealHint()
	local bracket = self:GetBracket()
	if bracket == "fast" then return ns.SPELLS.SEAL_RIGHT end
	if bracket == "slow" then return ns.SPELLS.SEAL_COMMAND end
	if bracket == "medium" then return ns.SPELLS.SEAL_RIGHT end
	return nil
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

local FALLBACK = ROTATIONS.fast

function WeaponEngine:HasSealOfCommand()
	return self.hasSealOfCommand == true
end

function WeaponEngine:GetRotation()
	-- Without the Seal of Command talent, every weapon uses the fast pairing.
	if not self:HasSealOfCommand() then
		return FALLBACK
	end
	local bracket = self:GetBracket()
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
