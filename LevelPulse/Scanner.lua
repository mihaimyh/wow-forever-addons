local addonName, ns = ...

local Scanner = ns:NewModule("Scanner")

-- Out-of-combat scanner for:
--   1. Active XP & Camping auras on "player" (Well Fed, Well-Rested, Campfire Nearby,
--      Camp Benefits, Eating/Sleeping states, Elixirs)
--   2. Bag consumables & leveling tools (Well Fed foods, Cozy Sleeping Bag,
--      Student Fodder, Campfire Kits, Elixirs, Sharpening/Weightstones)
--   3. Known Campfire spells (Expert / Journeyman / Basic Campfire) & Weapon Enchants

local CAMPFIRE_NEARBY_ID = 1283391
local SLEEPING_BAG_ID = 216645
local STUDENT_FODDER_ID = 216619

local CAMPFIRE_SPELLS = {
	"Expert Campfire",
	"Journeyman Campfire",
	"Basic Campfire",
}

local CAMP_BUFF_KEYWORDS = {
	"camp chair",
	"camp tent",
	"fish bowl",
	"sharpening wheel",
	"incense candle",
	"first aid kit",
	"camp benefit",
	"campfire",
	"cozy fire",
}

function Scanner:OnInitialize()
	self.itemMetaCache = {}
	self.auraTipCache = {}
	self.auras = {
		wellFed = false,
		wellFedXP = 0,
		wellFedName = nil,
		wellFedRemaining = 0,
		eating = false,
		eatingRemaining = 0,
		wellRested = false,
		wellRestedName = nil,
		wellRestedStacks = 0,
		wellRestedRemaining = 0,
		inSleepingBag = false,
		campfireNearby = false,
		campBuff = false,
		campBuffName = nil,
		campBuffTip = nil,
		campBuffRemaining = 0,
		elixirActive = false,
		elixirRemaining = 0,
		extraXPBonus = 0,
		extraXPName = nil,
	}
	self.items = {
		bestFood = nil,
		cheapestFood = nil,
		plainFoodCount = 0,
		foodCountsByName = {},
		sleepingBag = nil,
		studentFodder = nil,
		campfireKit = nil,
		elixir = nil,
		weaponStone = nil,
	}
	self.campfireSpell = nil
	self.hasMainHandEnchant = false
	self.mainHandEnchantRemaining = 0
	self.hasTwoHandOrMeleeWeapon = false
	self.bagsDirty = true
	self.retryScheduled = false
end

function Scanner:ScheduleTooltipRetry()
	if self.retryScheduled then return end
	if not C_Timer or not C_Timer.After then return end
	self.retryScheduled = true
	C_Timer.After(1.5, function()
		self.retryScheduled = false
		if InCombatLockdown and InCombatLockdown() then return end
		self.bagsDirty = true
		self:ScanAll()
		local ui = ns:GetModule("UI")
		if ui and ui.Refresh then ui:Refresh() end
	end)
end

function Scanner:OnLogin()
	self:ScanAll()
	self:ScheduleTooltipRetry()

	ns:On("UNIT_AURA", function(_, unit)
		if unit == "player" and not (InCombatLockdown and InCombatLockdown()) then
			self:ScanAuras()
		end
	end)
	ns:On("BAG_UPDATE", function()
		self.bagsDirty = true
	end)
	ns:On("SPELLS_CHANGED", function()
		self.bagsDirty = true
	end)
	ns:On("UNIT_INVENTORY_CHANGED", function(_, unit)
		if unit == "player" then
			self.bagsDirty = true
			self:ScanWeaponEnchant()
		end
	end)
	ns:On("PLAYER_LEVEL_UP", function()
		self.itemMetaCache = {}
		self.bagsDirty = true
	end)
	ns:On("PLAYER_ENTERING_WORLD", function()
		self.bagsDirty = true
		self:ScanAll()
		self:ScheduleTooltipRetry()
	end)
end

-------------------------------------------------------------------------------
-- Aura scanning (Out of combat only; tooltip-driven & secret-safe)
-------------------------------------------------------------------------------
local function ExtractAuraTooltip(index, spellId, stacks, auraCache)
	local cacheKey = spellId and (tostring(spellId) .. ":" .. tostring(stacks or 0)) or nil
	if cacheKey and auraCache and auraCache[cacheKey] then
		return auraCache[cacheKey]
	end
	if not C_TooltipInfo or not C_TooltipInfo.GetUnitBuff then return nil end
	local ok, data = pcall(C_TooltipInfo.GetUnitBuff, "player", index, "HELPFUL")
	if not ok or type(data) ~= "table" or ns.IsSecret(data) or type(data.lines) ~= "table" then
		return nil
	end
	local chunks = {}
	for _, line in ipairs(data.lines) do
		if type(line) == "table" and not ns.IsSecret(line) then
			local okL, lt = pcall(function() return line.leftText end)
			if okL and ns.IsReadable(lt) and type(lt) == "string" and lt ~= "" then
				chunks[#chunks + 1] = lt:lower()
			end
		end
	end
	if #chunks == 0 then return nil end
	local joined = table.concat(chunks, "\n")
	if cacheKey and auraCache then
		auraCache[cacheKey] = joined
	end
	return joined
end

local XP_TOOLTIP_PATTERNS = {
	"(%d+)%%%s+increased%s+experience",
	"experience[^%.%%]-by%s+(%d+)%%",
	"increases%s+experience[^%.%%]-(%d+)%%",
	"(%d+)%%%s+bonus%s+experience",
	"experience%s+gained[^%.%%]-(%d+)%%",
	"(%d+)%%%s+experience",
}

local function ParseXPPercentFromTooltip(tipLower)
	if not tipLower or tipLower:find("experience", 1, true) == nil then
		return nil
	end
	for _, pat in ipairs(XP_TOOLTIP_PATTERNS) do
		local raw = tipLower:match(pat)
		local n = raw and tonumber(raw) or nil
		if n and n >= 1 and n <= 100 then
			return n
		end
	end
	return nil
end

function Scanner:ScanAuras()
	if InCombatLockdown and InCombatLockdown() then return end
	if ns.AreAurasSecret() then return end
	if not C_UnitAuras or not C_UnitAuras.GetAuraDataByIndex then return end

	local now = GetTime and GetTime() or 0
	local nextState = {
		wellFed = false,
		wellFedXP = 0,
		wellFedName = nil,
		wellFedRemaining = 0,
		eating = false,
		eatingRemaining = 0,
		wellRested = false,
		wellRestedName = nil,
		wellRestedStacks = 0,
		wellRestedRemaining = 0,
		inSleepingBag = false,
		campfireNearby = false,
		campBuff = false,
		campBuffName = nil,
		campBuffTip = nil,
		campBuffRemaining = 0,
		elixirActive = false,
		elixirRemaining = 0,
		extraXPBonus = 0,
		extraXPName = nil,
	}

	local sawSecret = false
	local debugAuras = {}
	for i = 1, 40 do
		local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
		if not ok then
			sawSecret = true
			break
		end
		if not aura then break end
		if ns.IsSecret(aura) then
			sawSecret = true
			break
		end

		local okN, name = pcall(function() return aura.name end)
		local okId, spellId = pcall(function() return aura.spellId end)
		local okExp, exp = pcall(function() return aura.expirationTime end)
		local okApp, apps = pcall(function() return aura.applications end)

		if not okN or ns.IsSecret(name) then
			sawSecret = true
			break
		end

		if type(name) == "string" and name ~= "" then
			local lower = name:lower()
			local rem = 0
			if okExp and ns.IsReadable(exp) and type(exp) == "number" and exp > now then
				rem = exp - now
			elseif okExp and ns.IsReadable(exp) and exp == 0 then
				rem = 99999
			end
			local stacks = (okApp and ns.IsReadable(apps) and type(apps) == "number") and apps or 0
			local id = (okId and ns.IsReadable(spellId) and type(spellId) == "number") and spellId or nil
			local tip = ExtractAuraTooltip(i, id, stacks, self.auraTipCache)
			local xpPct = ParseXPPercentFromTooltip(tip)

			debugAuras[#debugAuras + 1] = string.format("%s[%s] rem=%.0fs st=%d xp=%s",
				name, tostring(id or "?"), rem, stacks, tostring(xpPct or 0))

			local isWellFedName = lower:find("well fed", 1, true) ~= nil or lower:find("gourmand", 1, true) ~= nil
			local isWellRestedName = lower:find("well%-rested") ~= nil or lower:find("well rested", 1, true) ~= nil
			local isSleepingBagChannel = (lower:find("sleeping bag", 1, true) ~= nil) and (rem >= 99999 or rem <= 0)
			local isSleepingBagTimed = (lower:find("sleeping bag", 1, true) ~= nil) and rem > 0 and rem < 99999

			if id == CAMPFIRE_NEARBY_ID or lower:find("campfire nearby", 1, true) ~= nil then
				nextState.campfireNearby = true
			elseif lower == "food" or lower == "food & drink" or lower:find("^eating") ~= nil then
				nextState.eating = true
				nextState.eatingRemaining = rem
			elseif isSleepingBagChannel then
				nextState.inSleepingBag = true
			elseif isWellFedName or (xpPct == 5 and tip and tip:find("killing", 1, true) ~= nil and tip:find("quest", 1, true) == nil) then
				nextState.wellFed = true
				nextState.wellFedName = name
				nextState.wellFedXP = math.max(nextState.wellFedXP, xpPct or 5)
				if rem > nextState.wellFedRemaining then
					nextState.wellFedRemaining = rem
				end
			elseif isWellRestedName or isSleepingBagTimed or (xpPct and xpPct >= 1 and xpPct <= 3) then
				nextState.wellRested = true
				nextState.wellRestedName = name
				local effStacks = (xpPct and xpPct >= 1 and xpPct <= 3) and math.max(stacks, xpPct) or (stacks > 0 and stacks or 1)
				nextState.wellRestedStacks = math.max(nextState.wellRestedStacks, effStacks)
				if rem > nextState.wellRestedRemaining then
					nextState.wellRestedRemaining = rem
				end
			elseif lower:find("^elixir of ") ~= nil or lower:find("^flask of ") ~= nil then
				nextState.elixirActive = true
				if rem > nextState.elixirRemaining then
					nextState.elixirRemaining = rem
				end
			else
				local matchedCamp = false
				for _, kw in ipairs(CAMP_BUFF_KEYWORDS) do
					if lower:find(kw, 1, true) ~= nil then
						matchedCamp = true
						nextState.campBuff = true
						nextState.campBuffName = name
						nextState.campBuffTip = tip
						if rem > nextState.campBuffRemaining then
							nextState.campBuffRemaining = rem
						end
						break
					end
				end
				if xpPct and xpPct > 0 then
					nextState.extraXPBonus = (nextState.extraXPBonus or 0) + xpPct
					nextState.extraXPName = name
				elseif not matchedCamp and tip and tip:find("rested experience", 1, true) ~= nil then
					nextState.campBuff = true
					nextState.campBuffName = name
					nextState.campBuffTip = tip
					if rem > nextState.campBuffRemaining then
						nextState.campBuffRemaining = rem
					end
				end
			end
		end
	end

	if not sawSecret then
		self.auras = nextState
		if ns.db then
			ns.db.lastAuraDump = debugAuras
		end
	end
end

-------------------------------------------------------------------------------
-- Weapon Enchant scanning (for optional Sharpening / Weightstones)
-------------------------------------------------------------------------------
function Scanner:ScanWeaponEnchant()
	self.hasMainHandEnchant = false
	self.mainHandEnchantRemaining = 0
	self.hasTwoHandOrMeleeWeapon = false

	if GetInventoryItemID then
		local okW, itemID = pcall(GetInventoryItemID, "player", 16)
		if okW and ns.IsReadable(itemID) and type(itemID) == "number" and itemID > 0 then
			self.hasTwoHandOrMeleeWeapon = true
		end
	end

	if GetWeaponEnchantInfo then
		local ok, hasMH, mhExp = pcall(GetWeaponEnchantInfo)
		if ok and ns.IsReadable(hasMH) and hasMH == true then
			self.hasMainHandEnchant = true
			if ns.IsReadable(mhExp) and type(mhExp) == "number" and mhExp > 0 then
				self.mainHandEnchantRemaining = mhExp / 1000
			end
		end
	end
end

-------------------------------------------------------------------------------
-- Bag & Spell scanning (cached per itemID so BAG_UPDATE stays instant)
-------------------------------------------------------------------------------
local function BagIndices()
	local maxBag = (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4)
	local out = {}
	for b = 0, maxBag do out[#out + 1] = b end
	return out
end

local function IsItemCooldownReady(itemID)
	if not C_Item or not C_Item.GetItemCooldown then
		if C_Container and C_Container.GetItemCooldown then
			local ok, start, dur, enable = pcall(C_Container.GetItemCooldown, itemID)
			if ok and ns.IsReadable(start) and ns.IsReadable(dur) then
				if enable == 0 or enable == false then return false end
				return start == 0 or dur == 0 or (start + dur - GetTime()) <= 1.0
			end
		end
		return true
	end
	local ok, start, dur, enable = pcall(C_Item.GetItemCooldown, itemID)
	if not ok or not ns.IsReadable(start) or not ns.IsReadable(dur) then return true end
	if ns.IsReadable(enable) and (enable == 0 or enable == false) then return false end
	if start == 0 or dur == 0 then return true end
	return (start + dur - GetTime()) <= 1.0
end

local function ExtractTooltipText(bag, slot, itemID)
	if not C_TooltipInfo then return nil end
	local ok, data
	if C_TooltipInfo.GetBagItem and bag ~= nil and slot ~= nil then
		ok, data = pcall(C_TooltipInfo.GetBagItem, bag, slot)
	elseif C_TooltipInfo.GetItemByID and itemID then
		ok, data = pcall(C_TooltipInfo.GetItemByID, itemID)
	end
	if not ok or type(data) ~= "table" or ns.IsSecret(data) or type(data.lines) ~= "table" then
		return nil
	end
	local chunks = {}
	for _, line in ipairs(data.lines) do
		if type(line) == "table" and not ns.IsSecret(line) then
			local okL, lt = pcall(function() return line.leftText end)
			if okL and ns.IsReadable(lt) and type(lt) == "string" and lt ~= "" then
				chunks[#chunks + 1] = lt:lower()
			end
		end
	end
	if #chunks == 0 then return nil end
	return table.concat(chunks, "\n")
end

function Scanner:ClassifyItem(bag, slot, itemID, fallbackIcon)
	local cached = self.itemMetaCache[itemID]
	if cached then return cached end

	local itemName, itemLevel, itemMinLevel, itemTexture, sellPrice, classID
	if C_Item and C_Item.GetItemInfo then
		local ok, name, _, _, ilvl, minLvl, _, _, _, _, tex, price, clsID = pcall(C_Item.GetItemInfo, itemID)
		if ok and ns.IsReadable(name) and type(name) == "string" and name ~= "" then
			itemName = name
			itemLevel = (ns.IsReadable(ilvl) and type(ilvl) == "number") and ilvl or 1
			itemMinLevel = (ns.IsReadable(minLvl) and type(minLvl) == "number") and minLvl or 0
			itemTexture = (ns.IsReadable(tex) and tex) or fallbackIcon
			sellPrice = (ns.IsReadable(price) and type(price) == "number") and price or 0
			classID = (ns.IsReadable(clsID) and type(clsID) == "number") and clsID or nil
		end
	end

	-- Item data not loaded from client cache yet: wait for next scan without poisoning cache.
	if not itemName then
		if C_Item and C_Item.RequestLoadItemDataByID then
			pcall(C_Item.RequestLoadItemDataByID, itemID)
		end
		return nil
	end

	local lowerName = itemName:lower()
	local kind = "other"

	if itemID == SLEEPING_BAG_ID or lowerName:find("cozy sleeping bag", 1, true) ~= nil then
		kind = "sleeping_bag"
	elseif itemID == STUDENT_FODDER_ID or lowerName:find("student fodder", 1, true) ~= nil then
		kind = "student_fodder"
	elseif lowerName:find("campfire kit", 1, true) ~= nil then
		kind = "campfire_kit"
	elseif lowerName:find("^elixir of ") ~= nil then
		kind = "elixir"
	elseif lowerName:find("sharpening stone", 1, true) ~= nil or lowerName:find("weightstone", 1, true) ~= nil then
		kind = "weapon_stone"
	elseif classID == nil or classID == 0 or classID == 15 then
		local fg = ns:GetModule("FoodGuide")
		local isCuratedXPFood = fg and fg.IsKnownXPFoodName and fg:IsKnownXPFoodName(lowerName)
		local tip = ExtractTooltipText(bag, slot, itemID)
		if not tip and not isCuratedXPFood then
			-- Tooltip lines not streamed from client yet: do not poison itemMetaCache with "other".
			if C_Item and C_Item.RequestLoadItemDataByID then
				pcall(C_Item.RequestLoadItemDataByID, itemID)
			end
			self:ScheduleTooltipRetry()
			return nil
		end
		if isCuratedXPFood then
			kind = "xp_food"
		elseif tip then
			local isFoodUse = tip:find("restores", 1, true) ~= nil or tip:find("eating", 1, true) ~= nil or tip:find("well fed", 1, true) ~= nil
			local givesXPOrBuff = tip:find("well fed", 1, true) ~= nil
				or tip:find("experience", 1, true) ~= nil
				or tip:find("if you spend at least", 1, true) ~= nil
				or tip:find("gourmand", 1, true) ~= nil
			if isFoodUse and givesXPOrBuff then
				kind = "xp_food"
			elseif isFoodUse and tip:find("must remain seated while eating", 1, true) ~= nil then
				kind = "plain_food"
			end
		end
	end

	local meta = {
		id = itemID,
		name = itemName,
		icon = itemTexture or fallbackIcon or "Interface\\Icons\\INV_Misc_Food_15",
		itemLevel = itemLevel or 1,
		minLevel = itemMinLevel or 0,
		sellPrice = sellPrice or 0,
		kind = kind,
	}
	self.itemMetaCache[itemID] = meta
	return meta
end

function Scanner:ScanBagsAndSpells()
	if InCombatLockdown and InCombatLockdown() then return end

	local tel = ns:GetModule("Telemetry")
	local playerLevel = (tel and tel.level) or (UnitLevel and UnitLevel("player")) or 1
	if not ns.IsReadable(playerLevel) or type(playerLevel) ~= "number" then
		playerLevel = 1
	end

	local byID = {}
	if C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo then
		for _, bag in ipairs(BagIndices()) do
			local okSlots, numSlots = pcall(C_Container.GetContainerNumSlots, bag)
			if okSlots and ns.IsReadable(numSlots) and type(numSlots) == "number" and numSlots > 0 then
				for slot = 1, numSlots do
					local okInfo, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
					if okInfo and type(info) == "table" and not ns.IsSecret(info) then
						local itemID = info.itemID
						local count = info.stackCount
						local icon = info.iconFileID
						if ns.IsReadable(itemID) and type(itemID) == "number" then
							local n = (ns.IsReadable(count) and type(count) == "number" and count > 0) and count or 1
							local entry = byID[itemID]
							if not entry then
								local meta = self:ClassifyItem(bag, slot, itemID, ns.IsReadable(icon) and icon or nil)
								if meta and meta.kind ~= "other" and playerLevel >= (meta.minLevel or 0) then
									entry = {
										id = itemID,
										name = meta.name,
										icon = meta.icon,
										itemLevel = meta.itemLevel,
										minLevel = meta.minLevel,
										sellPrice = meta.sellPrice,
										kind = meta.kind,
										count = 0,
										bag = bag,
										slot = slot,
									}
									byID[itemID] = entry
								end
							end
							if entry then
								entry.count = entry.count + n
							end
						end
					end
				end
			end
		end
	end

	local foods = {}
	local foodCountsByName = {}
	local plainFoodCount = 0
	local sleepingBag, studentFodder, campfireKit, elixir, weaponStone

	for _, entry in pairs(byID) do
		local ready = IsItemCooldownReady(entry.id)
		entry.ready = ready
		if entry.kind == "xp_food" then
			local ln = entry.name and entry.name:lower()
			if ln then
				foodCountsByName[ln] = (foodCountsByName[ln] or 0) + (entry.count or 0)
			end
			if ready then
				foods[#foods + 1] = entry
			end
		elseif entry.kind == "plain_food" then
			plainFoodCount = plainFoodCount + (entry.count or 0)
		elseif entry.kind == "sleeping_bag" and ready then
			sleepingBag = entry
		elseif entry.kind == "student_fodder" and ready then
			studentFodder = entry
		elseif entry.kind == "campfire_kit" and ready then
			if not campfireKit or entry.itemLevel > campfireKit.itemLevel then
				campfireKit = entry
			end
		elseif entry.kind == "elixir" and ready then
			if not elixir or entry.minLevel > elixir.minLevel or entry.itemLevel > elixir.itemLevel then
				elixir = entry
			end
		elseif entry.kind == "weapon_stone" and ready then
			if not weaponStone or entry.minLevel > weaponStone.minLevel or entry.itemLevel > weaponStone.itemLevel then
				weaponStone = entry
			end
		end
	end

	local bestFood, cheapestFood
	for _, f in ipairs(foods) do
		if not bestFood
			or f.minLevel > bestFood.minLevel
			or (f.minLevel == bestFood.minLevel and f.itemLevel > bestFood.itemLevel)
			or (f.minLevel == bestFood.minLevel and f.itemLevel == bestFood.itemLevel and f.count > bestFood.count) then
			bestFood = f
		end
		if not cheapestFood
			or f.sellPrice < cheapestFood.sellPrice
			or (f.sellPrice == cheapestFood.sellPrice and f.count > cheapestFood.count)
			or (f.sellPrice == cheapestFood.sellPrice and f.count == cheapestFood.count and f.minLevel < cheapestFood.minLevel) then
			cheapestFood = f
		end
	end

	self.items = {
		bestFood = bestFood,
		cheapestFood = cheapestFood,
		plainFoodCount = plainFoodCount,
		foodCountsByName = foodCountsByName,
		sleepingBag = sleepingBag,
		studentFodder = studentFodder,
		campfireKit = campfireKit,
		elixir = elixir,
		weaponStone = weaponStone,
	}

	-- Known Cooking Campfire spells (Expert -> Journeyman -> Basic)
	self.campfireSpell = nil
	if C_Spell and C_Spell.GetSpellIDForSpellIdentifier and C_SpellBook and C_SpellBook.IsSpellKnown then
		for _, spellName in ipairs(CAMPFIRE_SPELLS) do
			local okId, spellID = pcall(C_Spell.GetSpellIDForSpellIdentifier, spellName)
			if okId and ns.IsReadable(spellID) and type(spellID) == "number" then
				local okK, known = pcall(C_SpellBook.IsSpellKnown, spellID)
				if okK and ns.IsReadable(known) and known == true then
					local usable = true
					if C_Spell.IsSpellUsable then
						local okU, u = pcall(C_Spell.IsSpellUsable, spellName)
						if okU and ns.IsReadable(u) then usable = (u == true) end
					end
					local cdReady = true
					if C_Spell.GetSpellCooldown then
						local okC, cd = pcall(C_Spell.GetSpellCooldown, spellName)
						if okC and type(cd) == "table" and ns.IsReadable(cd.startTime) and ns.IsReadable(cd.duration) then
							if cd.duration > 0 and (cd.startTime + cd.duration - GetTime()) > 1.0 then
								cdReady = false
							end
						end
					end
					if usable and cdReady then
						local tex = C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellName) or "Interface\\Icons\\Spell_Fire_Fire"
						self.campfireSpell = {
							name = spellName,
							icon = (ns.IsReadable(tex) and tex) or "Interface\\Icons\\Spell_Fire_Fire",
						}
						break
					end
				end
			end
		end
	end

	self.bagsDirty = false
end

function Scanner:ScanAll()
	self:ScanAuras()
	self:ScanWeaponEnchant()
	self:ScanBagsAndSpells()
end

function Scanner:GetSelectedFood()
	local mode = (ns.db and ns.db.foodMode) or "best"
	if mode == "cheapest" then
		return self.items.cheapestFood or self.items.bestFood
	end
	return self.items.bestFood or self.items.cheapestFood
end

function Scanner:GetActiveXPBonusPercent()
	local a = self.auras
	local bonus = 0
	if a.wellFed then bonus = bonus + (a.wellFedXP and a.wellFedXP > 0 and a.wellFedXP or 5) end
	if a.wellRested then bonus = bonus + math.min(3, math.max(1, a.wellRestedStacks or 1)) end
	if a.extraXPBonus and a.extraXPBonus > 0 then bonus = bonus + a.extraXPBonus end
	return bonus
end

function Scanner:DebugLine()
	local a = self.auras
	local f = self:GetSelectedFood()
	return string.format("xp=+%d%% wellFed=%s(%.0fs) bag=%s(%d/3,%.0fs) campNear=%s campBuff=%s(%s,%.0fs) food=%s(plain=%d)",
		self:GetActiveXPBonusPercent(),
		tostring(a.wellFed), a.wellFedRemaining or 0,
		tostring(a.wellRested), a.wellRestedStacks or 0, a.wellRestedRemaining or 0,
		tostring(a.campfireNearby), tostring(a.campBuff), tostring(a.campBuffName or "-"), a.campBuffRemaining or 0,
		f and (f.name .. "x" .. tostring(f.count)) or "none",
		self.items.plainFoodCount or 0)
end
