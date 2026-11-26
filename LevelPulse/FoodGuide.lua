local addonName, ns = ...

local FoodGuide = ns:NewModule("FoodGuide")

-- Dynamic Level-Scaling & Class-Aware Well Fed (+5% Kill XP) Food Guide for WoW: Forever.
-- Includes verified itemIDs for clickable [Item Links], preloading, 1-Click / Shift-Click
-- Auction House search, Cooking recipe filtering/opening, Chat linking, and Ctrl+C copy.

local CLASS_PROFILES = {
	PALADIN = { role = "melee_str", label = "Str / AP / Sta" },
	WARRIOR = { role = "melee_str", label = "Str / AP / Sta" },
	SHAMAN  = { role = "melee_str", label = "Str / AP / Int" },
	ROGUE   = { role = "melee_agi", label = "Agi / Crit / AP" },
	HUNTER  = { role = "melee_agi", label = "Agi / Crit / AP" },
	DRUID   = { role = "melee_agi", label = "Agi / Str / Int" },
	MAGE    = { role = "caster",    label = "Spell Power / Int / MP5" },
	PRIEST  = { role = "caster",    label = "Spell Power / Spirit / MP5" },
	WARLOCK = { role = "caster",    label = "Spell Power / Sta / Int" },
}

local BRACKETS = {
	{
		id = 1,
		minLevel = 1,
		maxLevel = 9,
		shortTitle = "Lvl 1–9",
		title = "Lvl 1–9 • Apprentice Cooking (Skill 1–50)",
		milestone = "Learn Cooking + Basic Campfire at lvl 1; fish or buy Small Eggs / Boar Meat.",
		foods = {
			{ itemID = 6888,  name = "Herb Baked Egg",      skill = 1,  stats = "+5% Kill XP + Early Stat", source = "Trainer (Small Egg)",       roles = { all = true } },
			{ itemID = 6290,  name = "Brilliant Smallfish", skill = 1,  stats = "+5% Kill XP (Cheap Fish)", source = "Vendor / Fishing 1",        roles = { all = true } },
			{ itemID = 2679,  name = "Charred Wolf Meat",   skill = 1,  stats = "+5% Kill XP",              source = "Trainer (Stringy Wolf)",    roles = { melee_str = true, melee_agi = true } },
			{ itemID = 2681,  name = "Roasted Boar Meat",   skill = 1,  stats = "+5% Kill XP",              source = "Trainer (Chunk of Boar)",   roles = { caster = true, all = true } },
		},
	},
	{
		id = 2,
		minLevel = 10,
		maxLevel = 14,
		shortTitle = "Lvl 10–14",
		title = "Lvl 10–14 • Journeyman Unlock (Skill 50–100)",
		milestone = "Train Journeyman Cooking at Skill 50 (Lvl 10) to raise cap to 150.",
		foods = {
			{ itemID = 4592,  name = "Longjaw Mud Snapper",    skill = 50, stats = "+5% Kill XP (Cheap Fish)", source = "Vendor / Fishing 50",        roles = { all = true } },
			{ itemID = 5473,  name = "Scorpid Surprise",       skill = 20, stats = "+5% XP + Sta",             source = "Durotar / Barrens Vendor",   roles = { melee_str = true, caster = true } },
			{ itemID = 5472,  name = "Kaldorei Spider Kabob",  skill = 10, stats = "+5% XP + Early Stats",     source = "Quest / Early Spider Drops", roles = { melee_agi = true, caster = true } },
			{ itemID = 2684,  name = "Coyote Steak",           skill = 50, stats = "+5% XP + Str/Sta",         source = "Westfall / Trainer",         roles = { melee_str = true, melee_agi = true } },
		},
	},
	{
		id = 3,
		minLevel = 15,
		maxLevel = 24,
		shortTitle = "Lvl 15–24",
		title = "Lvl 15–24 • Journeyman Tier (Skill 75–150)",
		milestone = "Lvl 14+: Also unlock Cozy Sleeping Bag (+3% XP) to stack with +5% Food!",
		foods = {
			{ itemID = 4593,  name = "Bristle Whisker Catfish", skill = 100, stats = "+5% Kill XP (Bulk Fish)",    source = "Vendor / Fishing 100 / AH", roles = { all = true } },
			{ itemID = 3726,  name = "Big Bear Steak",          skill = 110, stats = "+5% XP + Str / Melee",       source = "Hillsbrad / Ashenvale",     roles = { melee_str = true } },
			{ itemID = 5479,  name = "Crispy Lizard Tail",      skill = 100, stats = "+5% XP + Agi / Ranged",      source = "Barrens / Stonetalon",      roles = { melee_agi = true } },
			{ itemID = 21217, name = "Sagefish Delight",        skill = 80,  stats = "+5% XP + Mana Regen (MP5)",  source = "Fishing (Sagefish) / AH",   roles = { caster = true, melee_str = true } },
			{ itemID = 724,   name = "Goretusk Liver Pie",      skill = 50,  stats = "+5% XP + Sta / Survival",    source = "Westfall / Cities Vendor",  roles = { all = true } },
		},
	},
	{
		id = 4,
		minLevel = 25,
		maxLevel = 34,
		shortTitle = "Lvl 25–34",
		title = "Lvl 25–34 • Expert Cooking (Skill 150–200)",
		milestone = "Skill 125+: Buy Expert Cookbook (Shandrina in Ashenvale [A] / Wulan in Desolace [H]).",
		foods = {
			{ itemID = 12210, name = "Roast Raptor",            skill = 175, stats = "+5% XP + Str / Melee",       source = "STV / Arathi Vendor & AH",  roles = { melee_str = true } },
			{ itemID = 3727,  name = "Hot Lion Chops",          skill = 175, stats = "+5% XP + Str / AP",          source = "Hillsbrad / Alterac Lions", roles = { melee_str = true, melee_agi = true } },
			{ itemID = 3665,  name = "Curiously Tasty Omelet",  skill = 130, stats = "+5% XP + Agi / AP",          source = "Raptor Eggs (Arathi/STV)",  roles = { melee_agi = true } },
			{ itemID = 3729,  name = "Soothing Turtle Bisque",  skill = 175, stats = "+5% XP + Caster / Spirit",   source = "Hillsbrad Quest / Turtles", roles = { caster = true } },
			{ itemID = 8364,  name = "Mithril Head Trout",      skill = 175, stats = "+5% Kill XP (Bulk Fish)",    source = "Vendor / Fishing 175 / AH", roles = { all = true } },
			{ itemID = 20074, name = "Heavy Crocolisk Stew",    skill = 150, stats = "+5% XP + Stamina",           source = "Dustwallow / STV Vendor",   roles = { all = true } },
		},
	},
	{
		id = 5,
		minLevel = 35,
		maxLevel = 44,
		shortTitle = "Lvl 35–44",
		title = "Lvl 35–44 • Artisan Unlock (Skill 200–250)",
		milestone = "Lvl 35 + Skill 225: Complete 'Clamlette Surprise' in Gadgetzan for Artisan (300).",
		foods = {
			{ itemID = 13928, name = "Grilled Squid",        skill = 240, stats = "+5% XP + Crit / Agility",      source = "Gadgetzan Vendor / AH",      roles = { melee_str = true, melee_agi = true } },
			{ itemID = 6887,  name = "Spotted Yellowtail",   skill = 225, stats = "+5% XP + Spell Power / Stats", source = "Steamwheedle (Gikkix) / AH", roles = { caster = true, all = true } },
			{ itemID = 21072, name = "Smoked Sagefish",      skill = 200, stats = "+5% XP + Mana Regen (MP5)",    source = "Greater Sagefish / AH",      roles = { caster = true, melee_str = true } },
			{ itemID = 17222, name = "Spider Sausage",       skill = 200, stats = "+5% XP + High Stamina",        source = "Cooking Trainer (Skill 200)", roles = { all = true } },
			{ itemID = 18045, name = "Tender Wolf Steak",    skill = 225, stats = "+5% XP + Solid Stats",         source = "Gadgetzan / Feralas Vendor", roles = { melee_str = true, melee_agi = true } },
		},
	},
	{
		id = 6,
		minLevel = 45,
		maxLevel = 60,
		shortTitle = "Lvl 45–59",
		title = "Lvl 45–59 • Endgame Leveling (Skill 250–300)",
		milestone = "Final stretch to 60: pair Artisan stat food (+5% XP) with 3/3 Sleeping Bag (+3% XP).",
		foods = {
			{ itemID = 20452, name = "Smoked Desert Dumplings",  skill = 285, stats = "+5% XP + Top Strength",        source = "Silithus Quest / AH",        roles = { melee_str = true } },
			{ itemID = 13934, name = "Mightfish Steak",          skill = 275, stats = "+5% XP + Attack Power / Sta",  source = "Steamwheedle / AH",          roles = { melee_str = true, melee_agi = true } },
			{ itemID = 13928, name = "Grilled Squid",            skill = 240, stats = "+5% XP + 1% Crit / Agility",   source = "Azshara / Tanaris / AH",     roles = { melee_agi = true, melee_str = true } },
			{ itemID = 6887,  name = "Spotted Yellowtail",       skill = 225, stats = "+5% XP + Spell Power",         source = "Steamwheedle (Gikkix) / AH", roles = { caster = true } },
			{ itemID = 13931, name = "Nightfin Soup",            skill = 250, stats = "+5% XP + 8 MP5",               source = "Steamwheedle / AH",          roles = { caster = true, melee_str = true } },
			{ itemID = 18254, name = "Runn Tum Tuber Surprise",  skill = 275, stats = "+5% XP + Intellect",           source = "Dire Maul / AH",             roles = { caster = true } },
			{ itemID = 13932, name = "Poached Sunscale Salmon",  skill = 250, stats = "+5% XP + Attack Power / Regen", source = "Steamwheedle / AH",         roles = { all = true } },
		},
	},
}

local KNOWN_XP_FOOD_NAMES = {
	-- Include common spelling alias just in case
	["mithril headed trout"] = true,
}
for _, b in ipairs(BRACKETS) do
	for _, f in ipairs(b.foods) do
		KNOWN_XP_FOOD_NAMES[f.name:lower()] = true
	end
end

function FoodGuide:OnInitialize()
	self.classToken = "PALADIN"
	self.className = "Paladin"
	self.lastBracketID = nil
end

function FoodGuide:DetectPlayerClass()
	if UnitClass then
		local ok, locName, engClass = pcall(UnitClass, "player")
		if ok and ns.IsReadable(engClass) and type(engClass) == "string" and engClass ~= "" then
			self.classToken = engClass:upper()
			self.className = (ns.IsReadable(locName) and type(locName) == "string" and locName ~= "") and locName or engClass
		end
	end
end

function FoodGuide:PreloadBracketItems()
	if not C_Item or not C_Item.RequestLoadItemDataByID then return end
	for _, b in ipairs(BRACKETS) do
		for _, f in ipairs(b.foods) do
			if f.itemID then
				pcall(C_Item.RequestLoadItemDataByID, f.itemID)
			end
		end
	end
end

function FoodGuide:ResolveItemDisplay(food)
	if not food then return nil, "Interface\\Icons\\INV_Misc_Food_15" end
	local link, icon
	if food.itemID and C_Item and C_Item.GetItemInfo then
		local ok, name, itemLink, _, _, _, _, _, _, _, tex = pcall(C_Item.GetItemInfo, food.itemID)
		if ok and ns.IsReadable(name) and type(name) == "string" and name:lower() == food.name:lower() then
			if ns.IsReadable(itemLink) and type(itemLink) == "string" and itemLink ~= "" then
				link = itemLink
			end
			if ns.IsReadable(tex) and tex then
				icon = tex
			end
		elseif C_Item.RequestLoadItemDataByID then
			pcall(C_Item.RequestLoadItemDataByID, food.itemID)
		end
	end
	if not icon and food.itemID and C_Item and C_Item.GetItemIconByID then
		local okI, tex = pcall(C_Item.GetItemIconByID, food.itemID)
		if okI and ns.IsReadable(tex) and tex then icon = tex end
	end
	return link, icon or "Interface\\Icons\\INV_Misc_Food_15"
end

function FoodGuide:OnLogin()
	self:DetectPlayerClass()
	self:PreloadBracketItems()
	local tel = ns:GetModule("Telemetry")
	local curLvl = (tel and tel.level) or (UnitLevel and UnitLevel("player")) or 1
	local b = self:GetBracketForLevel(curLvl)
	self.lastBracketID = b and b.id or 1
	if ns.char and ns.char.lastSeenFoodBracket == nil then
		ns.char.lastSeenFoodBracket = self.lastBracketID
	end

	ns:On("PLAYER_LEVEL_UP", function(_, newLevel)
		local lvl = tonumber(newLevel)
		if not lvl then
			local t = ns:GetModule("Telemetry")
			lvl = (t and t.level) or 1
		end
		self:OnPlayerLevelUp(lvl)
	end)
end

function FoodGuide:IsKnownXPFoodName(lowerName)
	if type(lowerName) ~= "string" then return false end
	return KNOWN_XP_FOOD_NAMES[lowerName] == true
end

function FoodGuide:GetClassProfile()
	self:DetectPlayerClass()
	return CLASS_PROFILES[self.classToken] or { role = "melee_str", label = "Stats" }
end

function FoodGuide:GetBracketCount()
	return #BRACKETS
end

function FoodGuide:GetBracketByID(id)
	return BRACKETS[tonumber(id) or 1] or BRACKETS[1]
end

function FoodGuide:GetBracketForLevel(level)
	local lvl = tonumber(level) or 1
	if lvl < 1 then lvl = 1 end
	for _, b in ipairs(BRACKETS) do
		if lvl >= b.minLevel and lvl <= b.maxLevel then
			return b
		end
	end
	return BRACKETS[#BRACKETS]
end

function FoodGuide:GetNextBracket(currentBracket)
	if not currentBracket then return nil end
	for i, b in ipairs(BRACKETS) do
		if b.id == currentBracket.id then
			return BRACKETS[i + 1]
		end
	end
	return nil
end

function FoodGuide:GetRecommendations(overrideLevel, maxItems, explicitBracketID)
	local tel = ns:GetModule("Telemetry")
	local scanner = ns:GetModule("Scanner")
	local lvl = tonumber(overrideLevel) or (tel and tel.level) or 1
	local bracket = explicitBracketID and self:GetBracketByID(explicitBracketID) or self:GetBracketForLevel(lvl)
	local nextBracket = self:GetNextBracket(bracket)
	local profile = self:GetClassProfile()
	local role = profile.role
	local bagCounts = (scanner and scanner.items and scanner.items.foodCountsByName) or {}

	local roleMatches = {}
	local universalMatches = {}
	for _, f in ipairs(bracket.foods) do
		local link, icon = self:ResolveItemDisplay(f)
		local copy = {
			itemID = f.itemID,
			name = f.name,
			link = link,
			icon = icon,
			skill = f.skill,
			stats = f.stats,
			source = f.source,
			inBags = bagCounts[f.name:lower()] or 0,
			isRoleBest = (f.roles[role] == true),
		}
		if f.roles[role] then
			roleMatches[#roleMatches + 1] = copy
		elseif f.roles.all then
			universalMatches[#universalMatches + 1] = copy
		end
	end

	local picks = {}
	local limit = maxItems or 4
	for _, item in ipairs(roleMatches) do
		if #picks < limit then picks[#picks + 1] = item end
	end
	for _, item in ipairs(universalMatches) do
		if #picks < limit then picks[#picks + 1] = item end
	end
	if #picks >= limit and #universalMatches > 0 then
		local hasUniversal = false
		for _, p in ipairs(picks) do
			if p.name == universalMatches[1].name then hasUniversal = true; break end
		end
		if not hasUniversal then
			picks[limit] = universalMatches[1]
		end
	end

	local nextPreview = nil
	if nextBracket then
		local nextTop = nextBracket.foods[1]
		for _, nf in ipairs(nextBracket.foods) do
			if nf.roles[role] then nextTop = nf; break end
		end
		local nLink, nIcon = self:ResolveItemDisplay(nextTop)
		nextPreview = {
			unlockLevel = nextBracket.minLevel,
			title = nextBracket.title,
			itemID = nextTop and nextTop.itemID,
			topFood = nextTop and nextTop.name or "Artisan Food",
			link = nLink,
			icon = nIcon,
			topStats = nextTop and nextTop.stats or "+5% XP",
			skill = nextTop and nextTop.skill or 200,
		}
	end

	return {
		level = lvl,
		className = self.className or "Adventurer",
		roleLabel = profile.label,
		bracketID = bracket.id,
		shortTitle = bracket.shortTitle,
		bracketTitle = bracket.title,
		milestone = bracket.milestone,
		picks = picks,
		nextPreview = nextPreview,
	}
end

-------------------------------------------------------------------------------
-- Smart Click / Shift-Click Integration: Auction House, Cooking UI, & Chat
-------------------------------------------------------------------------------
local function SetEditBoxFilter(editBox, text)
	if not editBox or type(editBox.SetText) ~= "function" then return false end
	pcall(editBox.SetText, editBox, text)
	if editBox.ClearFocus then pcall(editBox.ClearFocus, editBox) end
	return true
end

function FoodGuide:TrySendToActiveUI(food, isShiftClick)
	if not food or type(food.name) ~= "string" then return nil end
	local link = food.link
	if not link then
		link = self:ResolveItemDisplay(food)
	end

	-- 1. Active Chat EditBox (Shift-Click inserts clickable itemLink or food name)
	if isShiftClick and ChatEdit_GetActiveWindow then
		local okChat, activeChat = pcall(ChatEdit_GetActiveWindow)
		if okChat and activeChat then
			if ChatEdit_InsertLink and link then
				pcall(ChatEdit_InsertLink, link)
			elseif activeChat.Insert then
				pcall(activeChat.Insert, activeChat, link or food.name)
			end
			return "chat"
		end
	end

	-- 2. Modern Mainline / Forever AuctionHouseFrame (or Classic BrowseName fallback)
	if AuctionHouseFrame and AuctionHouseFrame.IsShown and AuctionHouseFrame:IsShown() then
		local searchBar = AuctionHouseFrame.SearchBar
		if searchBar then
			if searchBar.SearchBox then
				SetEditBoxFilter(searchBar.SearchBox, food.name)
			elseif searchBar.SetSearchText then
				pcall(searchBar.SetSearchText, searchBar, food.name)
			end
			if searchBar.StartSearch then
				pcall(searchBar.StartSearch, searchBar)
				return "ah"
			end
		end
		if C_AuctionHouse and C_AuctionHouse.SendBrowseQuery then
			pcall(C_AuctionHouse.SendBrowseQuery, {
				searchString = food.name,
				sorts = {},
				filters = {},
			})
			return "ah"
		end
	elseif BrowseName and BrowseName.IsVisible and BrowseName:IsVisible() then
		SetEditBoxFilter(BrowseName, food.name)
		if AuctionFrameBrowse_Search then pcall(AuctionFrameBrowse_Search) end
		return "ah"
	end

	-- 3. Modern ProfessionsFrame (Cooking) or Classic TradeSkillFrame
	if ProfessionsFrame and ProfessionsFrame.IsShown and ProfessionsFrame:IsShown() then
		local searchBox = ProfessionsFrame.CraftingPage
			and ProfessionsFrame.CraftingPage.RecipeList
			and ProfessionsFrame.CraftingPage.RecipeList.SearchBox
		local acted = false
		if searchBox then
			acted = SetEditBoxFilter(searchBox, food.name)
		end
		if C_Spell and C_Spell.GetSpellIDForSpellIdentifier and C_TradeSkillUI and C_TradeSkillUI.OpenRecipe then
			local okS, spellID = pcall(C_Spell.GetSpellIDForSpellIdentifier, food.name)
			if okS and ns.IsReadable(spellID) and type(spellID) == "number" then
				pcall(C_TradeSkillUI.OpenRecipe, spellID)
				acted = true
			end
		end
		if acted then return "cooking" end
	elseif TradeSkillFrame and TradeSkillFrame.IsShown and TradeSkillFrame:IsShown() then
		local box = TradeSkillFrameSearchBox or TradeSkillFrameEditBox
		if SetEditBoxFilter(box, food.name) then
			return "cooking"
		end
	end

	-- 4. Native WoW modified-item click hook for 3rd-party addons (Auctionator, TSM, etc.)
	if isShiftClick and link and HandleModifiedItemClick then
		pcall(HandleModifiedItemClick, link)
	end

	return nil
end

function FoodGuide:OnPlayerLevelUp(newLevel)
	local rec = self:GetRecommendations(newLevel, 3)
	local prevID = (ns.char and ns.char.lastSeenFoodBracket) or self.lastBracketID or 1
	self.lastBracketID = rec.bracketID
	if ns.char then
		ns.char.lastSeenFoodBracket = rec.bracketID
	end

	local ui = ns:GetModule("UI")
	if ui and ui.ResetFoodDrawerToAuto then
		ui:ResetFoodDrawerToAuto()
	end

	if rec.bracketID > prevID and (not ns.db or ns.db.foodTierAlerts ~= false) then
		local labels = {}
		for _, p in ipairs(rec.picks) do
			labels[#labels + 1] = p.link or ("|cffffd100[" .. p.name .. "]|r")
		end
		ns:Print(string.format("New Well Fed tier unlocked (%s)! Top picks: %s (Click HUD or /lp food)",
			rec.shortTitle or rec.bracketTitle, table.concat(labels, " ")))
	end
end

function FoodGuide:PrintGuide(overrideLevel)
	local rec = self:GetRecommendations(overrideLevel, 5)
	ns:Print(string.format("=== Recommended Well Fed Food — %s (Lvl %d, %s) ===",
		rec.className, rec.level, rec.roleLabel))
	ns:Print("Tier: " .. rec.bracketTitle .. "  |cffaea99e(Shift-Click links into AH / Cooking / Chat)|r")
	for i, p in ipairs(rec.picks) do
		local display = p.link or ("|cffffd100[" .. p.name .. "]|r")
		local bagTag = (p.inBags and p.inBags > 0) and string.format(" |cff85ef66[x%d in bags]|r", p.inBags) or ""
		ns:Print(string.format("  %d. %s (Cook %d) — %s • %s%s",
			i, display, p.skill, p.stats, p.source, bagTag))
	end
	if rec.milestone then
		ns:Print("Tip: " .. rec.milestone)
	end
	if rec.nextPreview then
		local nDisp = rec.nextPreview.link or ("|cffffd100[" .. rec.nextPreview.topFood .. "]|r")
		ns:Print(string.format("Next unlock at Lvl %d: %s (%s)",
			rec.nextPreview.unlockLevel, nDisp, rec.nextPreview.topStats))
	end
end
