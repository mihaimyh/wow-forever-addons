local addonName, ns = ...

local Advisor = ns:NewModule("Advisor")

-- Smart Context & Priority Engine for LevelPulse:
--   1. Sit by active Campfire Nearby (1283391) -> 1h Camp Benefits / Tent Rested XP
--   2. Eat Well Fed Food (+5% kill XP, works in Dungeons & Open World)
--   3. Use Cozy Sleeping Bag (+3% XP, 2h) or Student Fodder (Open World only)
--   4. Place own Campfire (Expert/Journeyman/Basic Campfire or Kit, Outdoors only)
--   5. Optional Elixirs & Sharpening/Weightstones from bags
-- Tracks active eating / camping / sleeping-bag progress and fires a Ready Chime
-- the moment the buff completes so the player never sits a second longer than needed.

local SafeBool = ns.SafeBool
local CAMP_SIT_SECONDS = 60
local FOOD_SIT_SECONDS = 10
local SLEEPING_STACK_SECONDS = 60
local CAMP_COOLDOWN_FALLBACK = 2700 -- 45m guard when class buffs hide 1h camp stat auras

local function WallClock()
	if time then return time() end
	if os and os.time then return os.time() end
	return math.floor(GetTime and GetTime() or 0)
end

function Advisor:OnInitialize()
	self.current = nil
	self.statusLine = ""
	self.campSitStartedAt = nil
	self.eatingStartedAt = nil
	self.bagSitStartedAt = nil
	self.bagInitialStacks = 0
	self.readyFlashUntil = nil
	self.readyFlashText = nil
	self.prevWellFed = false
	self.prevWellFedRem = 0
	self.prevCampBuff = false
	self.prevBagStacks = 0
end

function Advisor:OnLogin()
	local scanner = ns:GetModule("Scanner")
	if scanner and scanner.auras then
		self.prevWellFed = scanner.auras.wellFed == true
		self.prevWellFedRem = scanner.auras.wellFedRemaining or 0
		self.prevCampBuff = scanner.auras.campBuff == true
		self.prevBagStacks = scanner.auras.wellRestedStacks or 0
	end

	-- Moving cancels sitting/camping timers cleanly.
	ns:On("PLAYER_STARTED_MOVING", function()
		self.campSitStartedAt = nil
		self.eatingStartedAt = nil
		self.bagSitStartedAt = nil
	end)

	ns:On("PLAYER_REGEN_DISABLED", function()
		self.campSitStartedAt = nil
		self.eatingStartedAt = nil
		self.bagSitStartedAt = nil
	end)
end

function Advisor:PlayReadyChime()
	if ns.db and ns.db.readySound == false then return end
	if not PlaySound or not SOUNDKIT then return end
	local kit = SOUNDKIT.READY_CHECK or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
	if kit then pcall(PlaySound, kit) end
end

function Advisor:NoteActionClicked(action)
	if not action then return end
	local now = GetTime and GetTime() or 0
	if action.key == "campfire_sit" or action.key == "campfire_place" then
		self.campSitStartedAt = now
	elseif action.key == "food" then
		self.eatingStartedAt = now
	elseif action.key == "sleeping_bag" then
		self.bagSitStartedAt = now
		local scanner = ns:GetModule("Scanner")
		self.bagInitialStacks = (scanner and scanner.auras and scanner.auras.wellRestedStacks) or 0
	end
end

function Advisor:Snooze(key)
	if not key or not ns.char then return end
	ns.char.snoozedUntil = ns.char.snoozedUntil or {}
	local mins = (ns.db and tonumber(ns.db.snoozeMinutes)) or 15
	if mins < 1 then mins = 1 end
	ns.char.snoozedUntil[key] = WallClock() + (mins * 60)
	if key == "campfire_sit" then self.campSitStartedAt = nil end
	if key == "food" then self.eatingStartedAt = nil end
	if key == "sleeping_bag" then self.bagSitStartedAt = nil end
end

function Advisor:IsSnoozed(key)
	if not key or not ns.char or type(ns.char.snoozedUntil) ~= "table" then return false end
	local untilAt = ns.char.snoozedUntil[key]
	if type(untilAt) ~= "number" then return false end
	if WallClock() >= untilAt then
		ns.char.snoozedUntil[key] = nil
		return false
	end
	return true
end

function Advisor:ClearSnoozes()
	if ns.char then
		ns.char.snoozedUntil = {}
	end
end

function Advisor:GetContext()
	local inCombat = (InCombatLockdown and InCombatLockdown()) or false
	local dead = (UnitIsDeadOrGhost and SafeBool(UnitIsDeadOrGhost, "player") == true) or false
	local onTaxi = (UnitOnTaxi and SafeBool(UnitOnTaxi, "player") == true) or false
	local mounted = (IsMounted and SafeBool(IsMounted) == true) or false
	local resting = (IsResting and SafeBool(IsResting) == true) or false
	local outdoors = (not IsOutdoors) or (SafeBool(IsOutdoors) ~= false)
	local inInstance = false
	if IsInInstance then
		local ok, inInst, instType = pcall(IsInInstance)
		if ok and ns.IsReadable(inInst) and inInst == true then
			if not ns.IsReadable(instType) or instType ~= "none" then
				inInstance = true
			end
		end
	end
	return {
		inCombat = inCombat,
		dead = dead,
		onTaxi = onTaxi,
		mounted = mounted,
		resting = resting,
		outdoors = outdoors,
		inInstance = inInstance,
	}
end

function Advisor:CheckCompletions(auras, now)
	-- 1. Well Fed newly gained or refreshed while eating
	local gainedWellFed = auras.wellFed and (not self.prevWellFed or (auras.wellFedRemaining - (self.prevWellFedRem or 0)) > 60)
	if gainedWellFed and (self.eatingStartedAt ~= nil or auras.eating) then
		self.eatingStartedAt = nil
		self.readyFlashUntil = now + 3.0
		self.readyFlashText = "WELL FED READY! (+5% XP)"
		self:PlayReadyChime()
	end

	-- 2. Cozy Sleeping Bag reached 3/3 stacks while resting in the bag
	local wasBuildingBag = (self.bagSitStartedAt ~= nil) or auras.inSleepingBag or ((self.prevBagStacks or 0) > 0 and (self.prevBagStacks or 0) < 3)
	if wasBuildingBag and auras.wellRested and (auras.wellRestedStacks or 0) >= 3 and (self.prevBagStacks or 0) < 3 then
		self.bagSitStartedAt = nil
		self.readyFlashUntil = now + 3.5
		self.readyFlashText = "SLEEPING BAG 3/3! (+3% XP)"
		self:PlayReadyChime()
	end

	-- 3. Campfire sit completed (either 1h Camp buff appeared near fire, or 60s sit finished)
	local campCompleted = false
	if auras.campBuff and not self.prevCampBuff and (self.campSitStartedAt ~= nil or auras.campfireNearby) then
		campCompleted = true
	elseif self.campSitStartedAt and auras.campfireNearby and (now - self.campSitStartedAt) >= CAMP_SIT_SECONDS then
		campCompleted = true
	end
	if campCompleted then
		self.campSitStartedAt = nil
		if ns.char then
			ns.char.lastCampCompletedAt = WallClock()
		end
		self.readyFlashUntil = now + 3.5
		self.readyFlashText = "CAMP BUFF READY! (Stand up)"
		self:PlayReadyChime()
	end

	self.prevWellFed = auras.wellFed == true
	self.prevWellFedRem = auras.wellFedRemaining or 0
	self.prevCampBuff = auras.campBuff == true
	self.prevBagStacks = auras.wellRestedStacks or 0
end

local function NeedsRefresh(active, remaining, earlySec)
	if not active then return true end
	return (remaining or 0) <= earlySec
end

function Advisor:Evaluate()
	local db = ns.db or {}
	local scanner = ns:GetModule("Scanner")
	local tel = ns:GetModule("Telemetry")
	if not db.enabled or not scanner or not tel then
		self.current = nil
		return nil
	end

	if scanner.bagsDirty and not (InCombatLockdown and InCombatLockdown()) then
		scanner:ScanBagsAndSpells()
	end

	local ctx = self:GetContext()
	if ctx.inCombat or ctx.dead or tel:IsMaxLevel() then
		self.current = nil
		return nil
	end

	local now = GetTime and GetTime() or 0
	local auras = scanner.auras
	self:CheckCompletions(auras, now)

	-- Brief celebration banner right when a sit/eat buff completes so you know to stand up.
	if self.readyFlashUntil and now < self.readyFlashUntil then
		self.current = {
			key = "ready_flash",
			kind = "info",
			title = self.readyFlashText or "BUFF READY!",
			subtitle = "You can move now",
			icon = "Interface\\Icons\\Spell_Holy_BorrowedTime",
			progress = 1,
			isReadyFlash = true,
		}
		return self.current
	else
		self.readyFlashUntil = nil
	end

	-- Active sitting / channeling states take visual priority so the player sees live countdown.
	if auras.eating or (self.eatingStartedAt and (now - self.eatingStartedAt) < FOOD_SIT_SECONDS and not auras.wellFed) then
		local start = self.eatingStartedAt or now
		if not self.eatingStartedAt then self.eatingStartedAt = now end
		local elapsed = math.max(0, now - start)
		local rem = math.max(0, FOOD_SIT_SECONDS - elapsed)
		local food = scanner:GetSelectedFood()
		self.current = {
			key = "food",
			kind = "channel",
			title = "Eating for Well Fed (+5% XP)",
			subtitle = string.format("Stay seated %.0fs...", rem),
			icon = (food and food.icon) or "Interface\\Icons\\INV_Misc_Food_15",
			progress = math.min(1, elapsed / FOOD_SIT_SECONDS),
		}
		return self.current
	end

	if (auras.inSleepingBag or self.bagSitStartedAt) and (auras.wellRestedStacks or 0) < 3 then
		local start = self.bagSitStartedAt or now
		if not self.bagSitStartedAt then self.bagSitStartedAt = now end
		local stacks = auras.wellRestedStacks or 0
		if stacks > (self.bagInitialStacks or 0) then
			self.bagInitialStacks = stacks
			self.bagSitStartedAt = now
			start = now
		end
		local elapsed = math.max(0, now - start)
		local rem = math.max(0, SLEEPING_STACK_SECONDS - elapsed)
		self.current = {
			key = "sleeping_bag",
			kind = "channel",
			title = string.format("Resting in Sleeping Bag (%d/3)", stacks),
			subtitle = string.format("Next +1%% XP stack in %.0fs", rem),
			icon = "Interface\\Icons\\INV_Misc_Bag_CoreFelclothBag",
			progress = math.min(1, (stacks + math.min(1, elapsed / SLEEPING_STACK_SECONDS)) / 3),
		}
		return self.current
	end

	if self.campSitStartedAt and auras.campfireNearby then
		local elapsed = math.max(0, now - self.campSitStartedAt)
		if elapsed < CAMP_SIT_SECONDS then
			local rem = math.max(0, CAMP_SIT_SECONDS - elapsed)
			self.current = {
				key = "campfire_sit",
				kind = "channel",
				title = "Camping near Fire (+Buffs)",
				subtitle = string.format("Stay /sit for %.0fs...", rem),
				icon = "Interface\\Icons\\Spell_Fire_Fire",
				progress = math.min(1, elapsed / CAMP_SIT_SECONDS),
			}
			return self.current
		end
	end

	local earlySec = tonumber(db.earlyRefreshSeconds) or 90
	local smartCtx = (db.smartContext ~= false)

	-- Always suppress prompts on Taxi (Flight Paths).
	if ctx.onTaxi then
		self.current = nil
		return nil
	end

	-- 1. Opportunistic Campfire Nearby: even in Smart Context (except when mounted),
	--    walking past an active campfire outdoors prompts 1-click /sit!
	local lastCampAt = ns.char and tonumber(ns.char.lastCampCompletedAt) or 0
	local recentlyCamped = (lastCampAt > 0) and ((WallClock() - lastCampAt) < CAMP_COOLDOWN_FALLBACK)
	local needCamp = NeedsRefresh(auras.campBuff, auras.campBuffRemaining, earlySec) and not recentlyCamped
	if (db.trackCampfireSit ~= false) and auras.campfireNearby and needCamp
		and (not smartCtx or not ctx.mounted) and not self:IsSnoozed("campfire_sit") then
		self.current = {
			key = "campfire_sit",
			kind = "macro",
			macrotext = "/sit",
			title = "Campfire Nearby! (/sit 60s)",
			subtitle = "Click: /sit for 1h Camp Buffs • R-Click: Skip",
			icon = "Interface\\Icons\\Spell_Fire_Fire",
			isCamp = true,
		}
		return self.current
	end

	-- Smart Context: suppress consumable spending in Resting Cities/Inns or while Mounted.
	if smartCtx and (ctx.resting or ctx.mounted) then
		self.current = nil
		return nil
	end

	-- 2. Well Fed (+5% kill XP) — active in both Open World and Dungeons!
	if (db.trackFood ~= false) and NeedsRefresh(auras.wellFed, auras.wellFedRemaining, earlySec)
		and not self:IsSnoozed("food") then
		local food = scanner:GetSelectedFood()
		if food then
			local sub = auras.wellFed
				and string.format("Click icon: Refresh (%s left, x%d) • R-Click: Skip", ns.UITheme.FmtDuration(auras.wellFedRemaining), food.count)
				or string.format("Click icon: +5%% Kill XP (x%d in bags) • R-Click: Skip", food.count)
			self.current = {
				key = "food",
				kind = "item",
				itemID = food.id,
				bag = food.bag,
				slot = food.slot,
				title = food.name,
				subtitle = sub,
				icon = food.icon,
			}
			return self.current
		end
	end

	-- 3. Cozy Sleeping Bag (+3% XP, 2h) & Student Fodder (Open World only, never mid-dungeon).
	if not ctx.inInstance then
		local bagItem = scanner.items.sleepingBag
		local needBag = (not auras.wellRested)
			or ((auras.wellRestedStacks or 0) < 3)
			or ((auras.wellRestedRemaining or 0) <= earlySec)
		if (db.trackSleepingBag ~= false) and bagItem and needBag and not self:IsSnoozed("sleeping_bag") then
			local curStacks = auras.wellRested and (auras.wellRestedStacks or 0) or 0
			self.current = {
				key = "sleeping_bag",
				kind = "item",
				itemID = bagItem.id,
				bag = bagItem.bag,
				slot = bagItem.slot,
				title = bagItem.name,
				subtitle = string.format("Click icon: +3%% XP (%d/3 active) • R-Click: Skip", curStacks),
				icon = bagItem.icon,
			}
			return self.current
		end

		local fodder = scanner.items.studentFodder
		if (db.trackStudentFodder ~= false) and fodder and tel:GetRestedPercent() < 145
			and not self:IsSnoozed("student_fodder") then
			self.current = {
				key = "student_fodder",
				kind = "item",
				itemID = fodder.id,
				bag = fodder.bag,
				slot = fodder.slot,
				title = fodder.name,
				subtitle = string.format("Click icon: +Rested XP (%d%% now, x%d)", tel:GetRestedPercent(), fodder.count),
				icon = fodder.icon,
			}
			return self.current
		end

		-- 4. Place own Campfire (Outdoors, Open World, non-Resting only).
		if (db.trackCampfirePlace ~= false) and ctx.outdoors and (not auras.campfireNearby) and needCamp
			and not self:IsSnoozed("campfire_place") then
			local spell = scanner.campfireSpell
			local kit = scanner.items.campfireKit
			if spell then
				self.current = {
					key = "campfire_place",
					kind = "spell",
					spellName = spell.name,
					title = spell.name,
					subtitle = "Click icon: Place Campfire (1h Buff) • R-Click: Skip",
					icon = spell.icon,
					isCamp = true,
				}
				return self.current
			elseif kit then
				self.current = {
					key = "campfire_place",
					kind = "item",
					itemID = kit.id,
					bag = kit.bag,
					slot = kit.slot,
					title = kit.name,
					subtitle = string.format("Click icon: Place Campfire (x%d) • R-Click: Skip", kit.count),
					icon = kit.icon,
					isCamp = true,
				}
				return self.current
			end
		end
	end

	-- 5. Optional Elixirs & Weapon Stones from bags.
	if db.trackElixirs == true and NeedsRefresh(auras.elixirActive, auras.elixirRemaining, earlySec)
		and not self:IsSnoozed("elixir") then
		local elix = scanner.items.elixir
		if elix then
			self.current = {
				key = "elixir",
				kind = "item",
				itemID = elix.id,
				bag = elix.bag,
				slot = elix.slot,
				title = elix.name,
				subtitle = string.format("Click icon: Drink Elixir (x%d) • R-Click: Skip", elix.count),
				icon = elix.icon,
			}
			return self.current
		end
	end

	if db.trackWeaponStones == true and scanner.hasTwoHandOrMeleeWeapon
		and NeedsRefresh(scanner.hasMainHandEnchant, scanner.mainHandEnchantRemaining, earlySec)
		and not self:IsSnoozed("weapon_stone") then
		local stone = scanner.items.weaponStone
		if stone and stone.bag ~= nil and stone.slot ~= nil then
			self.current = {
				key = "weapon_stone",
				kind = "macro",
				macrotext = string.format("/use %d %d\n/use 16", stone.bag, stone.slot),
				title = stone.name,
				subtitle = string.format("Click icon: Apply to Weapon (x%d) • R-Click: Skip", stone.count),
				icon = stone.icon,
			}
			return self.current
		end
	end

	self.current = nil
	return nil
end

function Advisor:GetPauseTag()
	local db = ns.db or {}
	local ctx = self:GetContext()
	if ctx.onTaxi then
		return "FLIGHT"
	end
	if db.smartContext ~= false then
		if ctx.mounted then
			return "MOUNTED"
		elseif ctx.resting then
			return "IN INN"
		end
	end
	return nil
end

function Advisor:FormatActiveBadges()
	local db = ns.db or {}
	local scanner = ns:GetModule("Scanner")
	local tel = ns:GetModule("Telemetry")
	if not scanner then return "" end
	local a = scanner.auras
	local Fmt = ns.UITheme.FmtDuration
	local parts = {}

	-- 1. Well Fed (+5% XP)
	if a.wellFed then
		parts[#parts + 1] = "|cff85ef66Food|r " .. Fmt(a.wellFedRemaining)
	elseif db.trackFood ~= false then
		local f = scanner:GetSelectedFood()
		if f then
			parts[#parts + 1] = string.format("|cffffa338Food|r x%d", f.count)
		else
			parts[#parts + 1] = "|cff8a867dFood|r 0"
		end
	end

	-- 2. Cozy Sleeping Bag (+3% XP)
	local showBag = a.wellRested or (scanner.items.sleepingBag ~= nil) or ((tel and (tel.level or 1) >= 14) and db.trackSleepingBag ~= false)
	if showBag then
		if a.wellRested then
			parts[#parts + 1] = string.format("|cff85ef66Bag %d/3|r %s", a.wellRestedStacks or 1, Fmt(a.wellRestedRemaining))
		elseif scanner.items.sleepingBag then
			parts[#parts + 1] = "|cffffa338Bag|r Ready"
		else
			parts[#parts + 1] = "|cff8a867dBag|r —"
		end
	end

	-- 3. Campfire Buff (1h Stats / Rested Tent)
	if a.campBuff then
		parts[#parts + 1] = "|cffff9944Camp|r " .. Fmt(a.campBuffRemaining)
	elseif a.campfireNearby then
		parts[#parts + 1] = "|cffff9944Camp|r Fire!"
	elseif db.trackCampfirePlace ~= false and (scanner.campfireSpell or scanner.items.campfireKit) then
		parts[#parts + 1] = "|cffffa338Camp|r Ready"
	else
		parts[#parts + 1] = "|cff8a867dCamp|r —"
	end

	return table.concat(parts, "  ·  ")
end

function Advisor:DebugLine()
	local cur = self.current or self:Evaluate()
	return string.format("adv cur=%s kind=%s pause=%s",
		tostring(cur and cur.title or "none"),
		tostring(cur and cur.kind or "idle"),
		tostring(self:GetPauseTag() or "none"))
end
