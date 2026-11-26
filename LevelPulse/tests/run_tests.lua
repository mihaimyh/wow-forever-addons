-- Offline unit & integration test suite for LevelPulse (WoW: Forever 16001)
-- Not listed in LevelPulse.toc; executed automatically by wow-forever-mcp validate_addon.

local passed = 0
local failed = 0

local function Assert(cond, msg)
	if not cond then
		error("ASSERTION FAILED: " .. tostring(msg), 2)
	end
end

local function AssertEq(actual, expected, msg)
	if actual ~= expected then
		error(string.format("ASSERTION FAILED: %s (expected=%s, actual=%s)",
			tostring(msg), tostring(expected), tostring(actual)), 2)
	end
end

local function CreateEnv(opts)
	opts = opts or {}
	local now = opts.now or 1000.0
	local wallNow = math.floor(now)
	local inCombat = opts.inCombat or false
	local playerLevel = opts.playerLevel or 26
	local curXP = opts.xp or 5000
	local maxXP = opts.maxXP or 20000
	local restedXP = opts.restedXP or 2000
	local isResting = opts.isResting or false
	local isMounted = opts.isMounted or false
	local onTaxi = opts.onTaxi or false
	local outdoors = opts.outdoors ~= false
	local inInstance = opts.inInstance or false
	local dead = opts.dead or false
	local playerAuras = opts.playerAuras or {}
	local bagItems = opts.bagItems or {} -- { [bag] = { [slot] = { itemID=..., count=..., name=..., minLevel=..., itemLevel=..., sellPrice=..., tooltip=... } } }
	local knownSpells = opts.knownSpells or {}
	local hasWeaponEnchant = opts.hasWeaponEnchant or false
	local weaponEnchantMs = opts.weaponEnchantMs or 0
	local mainHandID = opts.mainHandID or 268484
	local playerClass = opts.playerClass or "PALADIN"
	local playerClassName = opts.playerClassName or "Paladin"

	local function MakeSecret(v)
		return setmetatable({ __secret = true, val = v }, {
			__tostring = function() error("secret value converted to string") end,
		})
	end
	local function IsSecretValue(v)
		return type(v) == "table" and rawget(v, "__secret") == true
	end

	local itemCatalog = {}
	for b, slots in pairs(bagItems) do
		for s, item in pairs(slots) do
			itemCatalog[item.itemID] = item
		end
	end

	local frames = {}
	local soundsPlayed = {}

	local function MakeRegion()
		local r = { _shown = true, _alpha = 1, _text = "", _points = {} }
		function r:SetPoint(...) self._points[1] = { ... } end
		function r:ClearAllPoints() self._points = {} end
		function r:GetPoint(i)
			local p = self._points[i or 1]
			if not p then return nil end
			return p[1], p[2], p[3], p[4], p[5]
		end
		function r:SetAllPoints() end
		function r:SetSize(w, h) self._w, self._h = w, h end
		function r:SetWidth(w) self._w = w end
		function r:SetHeight(h) self._h = h end
		function r:GetWidth() return self._w or 0 end
		function r:GetHeight() return self._h or 0 end
		function r:SetColorTexture() end
		function r:SetGradient() end
		function r:SetTexture(t) self._tex = t end
		function r:GetTexture() return self._tex end
		function r:SetTexCoord() end
		function r:SetVertexColor() end
		function r:SetBlendMode() end
		function r:SetAlpha(a) self._alpha = a end
		function r:Show() self._shown = true end
		function r:Hide() self._shown = false end
		function r:SetShown(v) self._shown = v and true or false end
		function r:IsShown() return self._shown end
		function r:SetText(t) self._text = t end
		function r:GetText() return self._text end
		function r:SetTextColor() end
		function r:SetJustifyH() end
		function r:SetWordWrap() end
		function r:SetShadowOffset() end
		function r:SetShadowColor() end
		return r
	end

	local function MakeFrame()
		local f = MakeRegion()
		f._events = {}
		f._scripts = {}
		f._hooks = {}
		f._attrs = {}
		f._level = 5
		function f:RegisterEvent(ev) self._events[ev] = true end
		function f:UnregisterEvent(ev) self._events[ev] = nil end
		function f:SetScript(k, fn) self._scripts[k] = fn end
		function f:HookScript(k, fn)
			self._hooks[k] = self._hooks[k] or {}
			table.insert(self._hooks[k], fn)
		end
		function f:FireHook(k, ...)
			for _, fn in ipairs(self._hooks[k] or {}) do fn(self, ...) end
		end
		function f:CreateTexture() return MakeRegion() end
		function f:CreateFontString(_, _, inherits)
			if inherits ~= nil and type(inherits) ~= "string" then
				error("bad argument #3 to 'CreateFontString' (string expected, got " .. type(inherits) .. ")")
			end
			local fs = MakeRegion()
			function fs:SetFontObject() end
			return fs
		end
		function f:SetBackdrop() end
		function f:SetBackdropColor() end
		function f:SetBackdropBorderColor() end
		function f:SetMovable() end
		function f:EnableMouse(v) self._mouse = v end
		function f:IsMouseEnabled() return self._mouse == true end
		function f:RegisterForDrag() end
		function f:RegisterForClicks(...) self._clicks = { ... } end
		function f:SetClampedToScreen() end
		function f:SetFrameStrata(s) self._strata = s end
		function f:GetFrameStrata() return self._strata or "MEDIUM" end
		function f:SetFrameLevel(l) self._level = l end
		function f:GetFrameLevel() return self._level end
		function f:SetScale(s) self._scale = s end
		function f:GetScale() return self._scale or 1 end
		function f:StartMoving() end
		function f:StopMovingOrSizing() end
		function f:SetStatusBarTexture() end
		function f:SetStatusBarColor() end
		function f:SetMinMaxValues(lo, hi) self._min, self._max = lo, hi end
		function f:SetValue(v) self._val = v end
		function f:SetAutoFocus() end
		function f:SetFontObject() end
		function f:SetTextInsets() end
		function f:HighlightText() self._highlighted = true end
		function f:SetFocus() self._focused = true end
		function f:ClearFocus() self._focused = false end
		function f:Insert(t) self._text = (self._text or "") .. tostring(t) end
		function f:SetNormalTexture() end
		function f:SetPushedTexture() end
		function f:SetDisabledTexture() end
		function f:SetHighlightTexture() end
		function f:Click(btn)
			if self._scripts.OnClick then self._scripts.OnClick(self, btn or "LeftButton") end
		end
		function f:SetAttribute(k, v)
			if inCombat then error("SetAttribute blocked in combat lockdown!") end
			self._attrs[k] = v
		end
		function f:GetAttribute(k) return self._attrs[k] end
		function f:GetParent() return self._parent end
		frames[#frames + 1] = f
		return f
	end

	local env = {
		WOW_PROJECT_ID = 18,
		WOW_PROJECT_CAMELOT = 18,
		NUM_BAG_SLOTS = 4,
		SOUNDKIT = { READY_CHECK = 8960, IG_MAINMENU_OPTION_CHECKBOX_ON = 856 },
		SlashCmdList = {},
		UIParent = MakeFrame(),
		GameTooltip = {
			SetOwner = function() end,
			AddLine = function() end,
			Show = function() end,
			Hide = function() end,
		},
		LevelPulseDB = opts.savedDB,
		LevelPulseCharDB = opts.savedCharDB,
	}

	function env.strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
	function env.date() return "2026-11-26 23:30:00" end
	function env.GetTime() return now end
	function env.time() return wallNow end
	function env.InCombatLockdown() return inCombat end
	function env.issecretvalue(v) return IsSecretValue(v) end
	function env.issecrettable(v) return IsSecretValue(v) end
	function env.print() end
	function env.PlaySound(kit) soundsPlayed[#soundsPlayed + 1] = kit end
	function env.RegisterStateDriver() end
	function env.CreateFont(name)
		local fo = {
			_name = name,
			SetFont = function() end,
			SetTextColor = function() end,
			SetShadowOffset = function() end,
			SetShadowColor = function() end,
		}
		if name then env[name] = fo end
		return fo
	end
	function env.CreateFrame(_, _, parent)
		local f = MakeFrame()
		f._parent = parent
		return f
	end

	function env.UnitLevel() return playerLevel end
	function env.UnitClass() return playerClassName, playerClass, 2 end
	function env.UnitXP() return curXP end
	function env.UnitXPMax() return maxXP end
	function env.GetXPExhaustion() return restedXP end
	function env.IsResting() return isResting end
	function env.IsMounted() return isMounted end
	function env.UnitOnTaxi() return onTaxi end
	function env.IsOutdoors() return outdoors end
	function env.UnitIsDeadOrGhost() return dead end
	function env.IsInInstance() return inInstance, inInstance and "party" or "none" end
	function env.GetInventoryItemID(_, slot) return slot == 16 and mainHandID or nil end
	function env.GetWeaponEnchantInfo() return hasWeaponEnchant, weaponEnchantMs end

	env.C_UnitAuras = {
		GetAuraDataByIndex = function(unit, idx)
			if inCombat then error("Auras cannot be accessed when secret") end
			if unit == "player" then return playerAuras[idx] end
			return nil
		end,
	}

	env.C_Container = {
		GetContainerNumSlots = function(bag)
			return bag == 0 and 16 or 0
		end,
		GetContainerItemInfo = function(bag, slot)
			local it = bagItems[bag] and bagItems[bag][slot]
			if not it then return nil end
			return {
				itemID = it.itemID,
				stackCount = it.count or 1,
				iconFileID = it.icon or "tex:item",
				hyperlink = "item:" .. tostring(it.itemID),
			}
		end,
	}

	env.C_Item = {
		GetItemInfo = function(itemID)
			local it = itemCatalog[itemID]
			if not it then return nil end
			return it.name, "link", 1, it.itemLevel or 10, it.minLevel or 0, "Consumable", "Food & Drink", 20, "", it.icon or "tex:food", it.sellPrice or 10, it.classID or 0, 0
		end,
		GetItemCooldown = function(itemID)
			local it = itemCatalog[itemID]
			if it and it.cdRemaining and it.cdRemaining > 0 then
				return now - 5, it.cdRemaining + 5, 1
			end
			return 0, 0, 1
		end,
	}

	env.C_TooltipInfo = {
		GetBagItem = function(bag, slot)
			local it = bagItems[bag] and bagItems[bag][slot]
			if not it or not it.tooltip then return nil end
			local lines = {}
			for _, l in ipairs(it.tooltip) do lines[#lines + 1] = { leftText = l } end
			return { lines = lines }
		end,
		GetUnitBuff = function(unit, idx)
			if inCombat then error("Tooltips cannot be accessed when secret") end
			if unit ~= "player" then return nil end
			local aura = playerAuras[idx]
			if not aura or not aura.tooltip then return nil end
			local lines = {}
			for _, l in ipairs(aura.tooltip) do lines[#lines + 1] = { leftText = l } end
			return { lines = lines }
		end,
	}

	env.C_Spell = {
		GetSpellIDForSpellIdentifier = function(name) return knownSpells[name] end,
		GetSpellTexture = function(name) return "tex:" .. tostring(name) end,
		IsSpellUsable = function(name) return knownSpells[name] ~= nil end,
		GetSpellCooldown = function() return { startTime = 0, duration = 0 } end,
	}
	env.C_SpellBook = {
		IsSpellKnown = function(id)
			for _, kid in pairs(knownSpells) do
				if kid == id then return true end
			end
			return false
		end,
	}

	env.Settings = {
		VarType = { Boolean = "boolean", String = "string", Number = "number" },
		RegisterVerticalLayoutCategory = function()
			return { _id = 1, GetID = function() return 1 end }, { AddInitializer = function() end }
		end,
		RegisterAddOnSetting = function(_, _, var, tbl, _, _, default)
			if tbl[var] == nil then tbl[var] = default end
			return { SetValueChangedCallback = function() end }
		end,
		CreateCheckbox = function() end,
		CreateDropdown = function() end,
		CreateControlTextContainer = function()
			return { Add = function() end, GetData = function() return {} end }
		end,
		CreateSliderOptions = function() return { SetLabelFormatter = function() end } end,
		CreateSlider = function() end,
		RegisterAddOnCategory = function() end,
		OpenToCategory = function() end,
	}

	setmetatable(env, { __index = _G })
	env._G = env

	local ns = {}
	local files = {
		"Core.lua",
		"UITheme.lua",
		"Telemetry.lua",
		"FoodGuide.lua",
		"Scanner.lua",
		"Advisor.lua",
		"UI.lua",
		"Config.lua",
	}
	for _, file in ipairs(files) do
		local chunk, err = loadfile(file, "t", env)
		if not chunk then error("Load failed " .. file .. ": " .. tostring(err)) end
		chunk("LevelPulse", ns)
	end

	local ctrl
	ctrl = {
		env = env,
		ns = ns,
		sounds = soundsPlayed,
		MakeSecret = MakeSecret,
		Fire = function(ev, ...)
			for _, f in ipairs(frames) do
				if f._events[ev] and f._scripts.OnEvent then
					f._scripts.OnEvent(f, ev, ...)
				end
			end
		end,
		Advance = function(dt)
			now = now + dt
			wallNow = wallNow + math.floor(dt)
		end,
		SetCombat = function(v)
			inCombat = v
			ctrl.Fire(v and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED")
		end,
		SetAuras = function(list)
			playerAuras = list
			if not inCombat then ctrl.Fire("UNIT_AURA", "player") end
		end,
		SetResting = function(v) isResting = v; ctrl.Fire("PLAYER_UPDATE_RESTING") end,
		SetMounted = function(v) isMounted = v; ctrl.Fire("PLAYER_MOUNT_DISPLAY_CHANGED") end,
		SetTaxi = function(v) onTaxi = v end,
		SetInstance = function(v) inInstance = v end,
		SetXP = function(x, m, r)
			curXP = x
			if m then maxXP = m end
			if r then restedXP = r end
			ctrl.Fire("PLAYER_XP_UPDATE")
		end,
	}

	ctrl.Fire("ADDON_LOADED", "LevelPulse")
	ctrl.Fire("PLAYER_LOGIN")
	return ctrl
end

local function Test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		passed = passed + 1
		print("[PASS] " .. name)
	else
		failed = failed + 1
		print("[FAIL] " .. name .. "\n       " .. tostring(err))
	end
end

-------------------------------------------------------------------------------
-- Test Suite
-------------------------------------------------------------------------------

Test("1. Food scanner skips plain bread, picks best usable Well Fed food, and supports cheapest mode", function()
	local c = CreateEnv({
		playerLevel = 26,
		bagItems = {
			[0] = {
				[1] = { itemID = 4541, name = "Tough Hunk of Bread", minLevel = 1, itemLevel = 5, sellPrice = 1, count = 10,
					tooltip = { "Use: Restores 61 health over 18 sec. Must remain seated while eating." } },
				[2] = { itemID = 5476, name = "Brilliant Smallfish", minLevel = 1, itemLevel = 5, sellPrice = 2, count = 18,
					tooltip = { "Use: Restores 61 health over 18 sec. Grants 5% increased experience from killing monsters (Well Fed)." } },
				[3] = { itemID = 12210, name = "Roast Raptor", minLevel = 25, itemLevel = 35, sellPrice = 50, count = 6,
					tooltip = { "Use: Restores 874 health over 27 sec. If you spend at least 10 seconds eating you will become well fed." } },
				[4] = { itemID = 13928, name = "Grilled Squid", minLevel = 35, itemLevel = 45, sellPrice = 80, count = 5,
					tooltip = { "Use: Restores 874 health. If you spend at least 10 seconds eating you will become well fed." } },
			},
		},
	})
	local ui = c.ns:GetModule("UI")
	local adv = c.ns:GetModule("Advisor")

	-- Default mode = "best": skips lvl 35 Grilled Squid (player is lvl 26) & skips plain bread -> picks Roast Raptor!
	local act = adv:Evaluate()
	AssertEq(act.key, "food", "Should prompt Well Fed food")
	AssertEq(act.title, "Roast Raptor", "Best mode must select highest usable Well Fed food (Roast Raptor)")
	ui:Refresh()
	AssertEq(ui.isExpanded, true, "HUD must expand to show 1-Click food icon")
	AssertEq(ui.clickBtn:GetAttribute("type1"), "item", "Secure button must bind type1='item'")
	AssertEq(ui.clickBtn:GetAttribute("item1"), "item:12210", "Secure button must target Roast Raptor item:12210")

	-- Switch to "cheapest" mode -> selects Brilliant Smallfish (sellPrice=2, x18)
	c.ns.db.foodMode = "cheapest"
	local actCheap = adv:Evaluate()
	AssertEq(actCheap.title, "Brilliant Smallfish", "Cheapest mode must select lowest sellPrice Well Fed food")
end)

Test("2. Smart Context suppresses food/bag nags in Inns, Mounted, and Taxi, EXCEPT opportunistic Campfire Nearby!", function()
	local c = CreateEnv({
		isResting = true,
		bagItems = {
			[0] = {
				[1] = { itemID = 5476, name = "Brilliant Smallfish", minLevel = 1, itemLevel = 5, sellPrice = 2, count = 5,
					tooltip = { "Well Fed: +5% experience" } },
				[2] = { itemID = 216645, name = "Cozy Sleeping Bag", minLevel = 14, itemLevel = 20, count = 1 },
			},
		},
	})
	local adv = c.ns:GetModule("Advisor")
	AssertEq(adv:Evaluate(), nil, "In a Resting Inn/City, Smart Context must suppress consumable prompts")

	-- Leave Inn, mount up -> still suppressed while mounted
	c.SetResting(false)
	c.SetMounted(true)
	AssertEq(adv:Evaluate(), nil, "While mounted, Smart Context must suppress consumable prompts")

	-- Dismount outdoors near an active Campfire Nearby (1283391) -> Campfire /sit takes #1 priority even over missing food!
	c.SetMounted(false)
	c.SetAuras({ { name = "Campfire Nearby", spellId = 1283391, expirationTime = 0 } })
	local act = adv:Evaluate()
	AssertEq(act.key, "campfire_sit", "Campfire Nearby must take #1 priority when unmounted")
	AssertEq(act.kind, "macro", "Campfire Nearby binds a macro action")
	AssertEq(act.macrotext, "/sit", "Campfire Nearby 1-Click macro must execute /sit")

	-- Flight path (Taxi) suppresses everything including Campfire
	c.SetTaxi(true)
	AssertEq(adv:Evaluate(), nil, "Taxi flight path must suppress all prompts")
end)

Test("3. Priority Queue & Dungeon Isolation: Dungeons suggest Well Fed food, never Sleeping Bag or Place Campfire", function()
	local c = CreateEnv({
		inInstance = true,
		knownSpells = { ["Basic Campfire"] = 818 },
		bagItems = {
			[0] = {
				[1] = { itemID = 5476, name = "Brilliant Smallfish", minLevel = 1, itemLevel = 5, sellPrice = 2, count = 5,
					tooltip = { "Well Fed: +5% experience" } },
				[2] = { itemID = 216645, name = "Cozy Sleeping Bag", minLevel = 14, itemLevel = 20, count = 1 },
			},
		},
	})
	local adv = c.ns:GetModule("Advisor")
	-- 1. Without Well Fed inside dungeon -> suggests Food!
	AssertEq(adv:Evaluate().key, "food", "Inside dungeon, Well Fed food (+5% XP) must still be suggested")

	-- 2. Gain Well Fed inside dungeon -> must NOT suggest Cozy Sleeping Bag or Basic Campfire inside instance!
	c.SetAuras({ { name = "Well Fed", spellId = 19705, expirationTime = c.env.GetTime() + 900 } })
	AssertEq(adv:Evaluate(), nil, "Inside dungeon with Well Fed up, must NOT suggest Sleeping Bag or placing Campfire")

	-- 3. Step outside into Open World -> now suggests Cozy Sleeping Bag (3) -> then Basic Campfire (4)!
	c.SetInstance(false)
	AssertEq(adv:Evaluate().key, "sleeping_bag", "In Open World, Cozy Sleeping Bag prompts when < 3/3")

	c.SetAuras({
		{ name = "Well Fed", spellId = 19705, expirationTime = c.env.GetTime() + 900 },
		{ name = "Well-Rested", spellId = 436586, applications = 3, expirationTime = c.env.GetTime() + 7200 },
	})
	local campAct = adv:Evaluate()
	AssertEq(campAct.key, "campfire_place", "With Food & 3/3 Bag active outdoors, suggests placing Basic Campfire")
	AssertEq(campAct.spellName, "Basic Campfire", "Uses known Basic Campfire spell")
end)

Test("4. Eating, Camping, and 3/3 Sleeping Bag completion chimes + Adaptive Pill collapse", function()
	local c = CreateEnv({
		bagItems = {
			[0] = {
				[1] = { itemID = 5476, name = "Brilliant Smallfish", minLevel = 1, itemLevel = 5, sellPrice = 2, count = 5,
					tooltip = { "Well Fed: +5% experience" } },
				[2] = { itemID = 216645, name = "Cozy Sleeping Bag", minLevel = 14, itemLevel = 20, count = 1 },
			},
		},
	})
	local ui = c.ns:GetModule("UI")
	local adv = c.ns:GetModule("Advisor")
	ui:Refresh()

	-- Click to eat food -> enters live 10s eating channel
	ui.clickBtn:FireHook("PreClick", "LeftButton")
	c.Advance(4.0)
	local ch = adv:Evaluate()
	AssertEq(ch.kind, "channel", "Clicking food starts live eating countdown")
	Assert(ch.progress > 0.35 and ch.progress < 0.45, "Eating progress bar reflects 4/10s")

	-- Well Fed lands -> fires Ready Chime!
	local beforeSounds = #c.sounds
	c.SetAuras({ { name = "Well Fed", spellId = 19705, expirationTime = c.env.GetTime() + 900 } })
	ui:Refresh()
	AssertEq(#c.sounds, beforeSounds + 1, "Ready chime must play once when Well Fed lands")

	-- Advance past 3s celebration flash, build Sleeping Bag 2/3 -> 3/3 -> chime, then advance 4s -> Compact Pill (+8% XP)!
	c.Advance(4.0)
	c.SetAuras({
		{ name = "Well Fed", spellId = 19705, expirationTime = c.env.GetTime() + 900 },
		{ name = "Well-Rested", spellId = 436586, applications = 2, expirationTime = c.env.GetTime() + 7200 },
	})
	ui:Refresh()
	local beforeBagSound = #c.sounds
	c.SetAuras({
		{ name = "Well Fed", spellId = 19705, expirationTime = c.env.GetTime() + 900 },
		{ name = "Well-Rested", spellId = 436586, applications = 3, expirationTime = c.env.GetTime() + 7200 },
		{ name = "Camp Chair", spellId = 1290001, expirationTime = c.env.GetTime() + 3600 },
	})
	ui:Refresh()
	AssertEq(#c.sounds, beforeBagSound + 1, "Reaching 3/3 Well-Rested from 2/3 must play completion chime")
	c.Advance(4.0)
	ui:Refresh()
	AssertEq(c.ns:GetModule("Scanner"):GetActiveXPBonusPercent(), 8, "5% Well Fed + 3% Well-Rested = +8% XP")
	AssertEq(ui.isExpanded, false, "When fully buffed, HUD must collapse into Compact Telemetry Pill")
	Assert(ui.topLine:GetText():find("%+8%% XP") ~= nil, "Compact Pill top line must display +8% XP")
end)

Test("5. Right-click Snooze skips current reminder once (debounced) and advances to next buff", function()
	local c = CreateEnv({
		bagItems = {
			[0] = {
				[1] = { itemID = 5476, name = "Brilliant Smallfish", minLevel = 1, itemLevel = 5, sellPrice = 2, count = 5,
					tooltip = { "Well Fed: +5% experience" } },
				[2] = { itemID = 216645, name = "Cozy Sleeping Bag", minLevel = 14, itemLevel = 20, count = 1 },
			},
		},
	})
	local ui = c.ns:GetModule("UI")
	local adv = c.ns:GetModule("Advisor")
	ui:Refresh()
	AssertEq(adv.current.key, "food", "Starts on food")

	-- Simulate AnyDown + AnyUp firing PostClick twice rapidly on RightButton: must only snooze food ( NOT sleeping_bag too! )
	ui.clickBtn:FireHook("PostClick", "RightButton")
	ui.clickBtn:FireHook("PostClick", "RightButton")
	AssertEq(adv:IsSnoozed("food"), true, "Food must be snoozed for 15m")
	AssertEq(adv:IsSnoozed("sleeping_bag"), false, "Debounce must prevent double-snoozing Sleeping Bag")
	AssertEq(adv.current.key, "sleeping_bag", "HUD immediately advances to Cozy Sleeping Bag")

	-- Slash /lp unsnooze restores food
	c.env.SlashCmdList.LEVELPULSE("unsnooze")
	AssertEq(adv:Evaluate().key, "food", "/lp unsnooze restores snoozed food reminder")
end)

Test("6. Combat Lockdown & Secret Auras safety: zero taint, clickBtn parented to UIParent, XP/hr & ETA accurate", function()
	local c = CreateEnv({
		xp = 5000,
		maxXP = 20000,
		restedXP = 5000,
		bagItems = {
			[0] = {
				[1] = { itemID = 5476, name = "Brilliant Smallfish", minLevel = 1, itemLevel = 5, sellPrice = 2, count = 5,
					tooltip = { "Well Fed: +5% experience" } },
			},
		},
	})
	local ui = c.ns:GetModule("UI")
	local tel = c.ns:GetModule("Telemetry")
	AssertEq(ui.clickBtn:GetParent(), c.env.UIParent, "clickBtn must parent to UIParent to prevent combat taint")

	-- Gain 3000 XP over 300 seconds (5 minutes) -> 36,000 XP/hr, remaining 12,000 XP -> ETA 1200s (20m)
	c.Advance(300)
	c.SetXP(8000, 20000, 2000)
	AssertEq(tel:GetXPPerHour(), 36000, "3000 XP in 300s = 36,000 XP/hr")
	AssertEq(tel:GetETASeconds(), 1200, "12,000 remaining XP at 36k/hr = 1200s (20m)")

	-- Enter combat -> HUD fades to 0 alpha without calling Hide() or SetAttribute in combat
	c.SetCombat(true)
	AssertEq(ui.frame._alpha, 0, "HUD must fade to 0 alpha in combat without calling Hide()")
	AssertEq(c.ns.db.lastError, nil, "Zero Lua/taint errors in combat")

	-- Secret aura values out of combat never throw
	c.SetCombat(false)
	c.SetAuras({ { name = c.MakeSecret("SecretBuff"), spellId = c.MakeSecret(123) } })
	ui:Refresh()
	AssertEq(c.ns.db.lastError, nil, "Secret auras must be handled with zero errors")
end)

Test("7. Optional Weapon Stone & Elixir tracking generates 1-click apply macro", function()
	local c = CreateEnv({
		bagItems = {
			[0] = {
				[2] = { itemID = 2871, name = "Heavy Sharpening Stone", minLevel = 15, itemLevel = 25, count = 3 },
				[4] = { itemID = 3389, name = "Elixir of Defense", minLevel = 10, itemLevel = 20, count = 2 },
			},
		},
	})
	c.ns.db.trackElixirs = true
	c.ns.db.trackWeaponStones = true
	local ui = c.ns:GetModule("UI")
	local adv = c.ns:GetModule("Advisor")

	AssertEq(adv:Evaluate().key, "elixir", "Elixir prompts when trackElixirs=true")
	adv:Snooze("elixir")

	local stoneAct = adv:Evaluate()
	AssertEq(stoneAct.key, "weapon_stone", "Weapon stone prompts when main hand lacks temporary enchant")
	ui:Refresh()
	AssertEq(ui.clickBtn:GetAttribute("type1"), "macro", "Weapon stone uses 1-click apply macro")
	AssertEq(ui.clickBtn:GetAttribute("macrotext1"), "/use 0 2\n/use 16", "Macro uses bag 0 slot 2 onto main-hand slot 16")
end)

Test("8. Interactive bar tooltip, Shift+Drag, and /lp unlock disabling clickBtn mouse", function()
	local c = CreateEnv({
		bagItems = {
			[0] = {
				[1] = { itemID = 5476, name = "Brilliant Smallfish", minLevel = 1, itemLevel = 5, sellPrice = 2, count = 5,
					tooltip = { "Well Fed: +5% experience" } },
			},
		},
	})
	local ui = c.ns:GetModule("UI")
	ui:Refresh()
	AssertEq(c.ns.db.locked, true, "HUD starts locked by default")
	AssertEq(ui.frame:IsMouseEnabled(), true, "HUD bar keeps mouse enabled out of combat for hover tooltip & Shift+Drag")
	AssertEq(ui.clickBtn:IsMouseEnabled(), true, "Locked HUD action icon accepts 1-Click")
	-- Verify clickBtn is anchored directly to UIParent (zero anchor link to ui.frame/iconHolder!)
	local _, relTo = ui.clickBtn:GetPoint(1)
	AssertEq(relTo, c.env.UIParent, "clickBtn must anchor directly to UIParent so frame never taints in combat")

	-- Unlock via /lp unlock: clickBtn yields mouse so icon area drags too!
	c.env.SlashCmdList.LEVELPULSE("unlock")
	AssertEq(c.ns.db.locked, false, "/lp unlock sets locked=false")
	AssertEq(ui.clickBtn:IsMouseEnabled(), false, "Unlocked HUD disables clickBtn mouse so dragging icon never consumes items")
	AssertEq(ui.tagRight:GetText(), "UNLOCKED", "HUD displays UNLOCKED badge while unlocked")

	-- Lock again via /lp lock: restores 1-Click action icon
	c.env.SlashCmdList.LEVELPULSE("lock")
	AssertEq(c.ns.db.locked, true, "/lp lock sets locked=true")
	AssertEq(ui.clickBtn:IsMouseEnabled(), true, "Re-locked HUD restores 1-Click action icon")
end)

Test("9. Tooltip-driven XP% aura detection, unloaded tooltip retry safety, and explicit checklist/pause tags", function()
	-- Start with an unlisted custom food whose tooltip is nil + a 82m Cozy Fire buff whose tooltip grants +3% XP!
	local bagSlot = { itemID = 991234, name = "Forever Custom Stew", minLevel = 20, itemLevel = 30, sellPrice = 50, count = 6, tooltip = nil }
	local c = CreateEnv({
		isResting = true,
		playerAuras = {
			{
				name = "Cozy Fire",
				spellId = 436586,
				applications = 0,
				expirationTime = 1000 + 4950, -- 82m30s (1h22m)
				tooltip = { "Cozy Fire", "Experience gained from killing monsters and completing quests increased by 3%." },
			},
		},
		bagItems = { [0] = { [1] = bagSlot } },
	})
	local ui = c.ns:GetModule("UI")
	local scan = c.ns:GetModule("Scanner")
	ui:Refresh()

	-- 1. Tooltip-driven aura parser catches +3% XP even when buff is named "Cozy Fire" with 0 applications!
	AssertEq(scan.auras.wellRested, true, "Tooltip +3% XP must classify 82m Cozy Fire as wellRested")
	AssertEq(scan.auras.wellRestedStacks, 3, "Tooltip '3%' sets wellRestedStacks = 3")
	AssertEq(scan:GetActiveXPBonusPercent(), 3, "Active XP bonus must report +3% XP (not +0%)")

	-- 2. In Inn, HUD shows explicit "IN INN" badge + full 3-slot checklist (Food 0 · Bag 3/3 · Camp —)
	AssertEq(ui.tagRight:GetText(), "IN INN", "Paused in Inn must show IN INN badge on HUD")
	Assert(ui.subLine:GetText():find("Food") ~= nil and ui.subLine:GetText():find("Bag 3/3") ~= nil, "Compact checklist must show Food and Bag 3/3")

	-- 3. Unloaded tooltip did NOT poison itemMetaCache: once tooltip streams in, Forever Custom Stew is detected!
	AssertEq(scan:GetSelectedFood(), nil, "Unlisted food with nil tooltip waits for tooltip load")
	bagSlot.tooltip = { "Use: Restores 874 health. If you spend at least 10 seconds eating you will become well fed." }
	scan:ScanBagsAndSpells()
	Assert(scan:GetSelectedFood() ~= nil and scan:GetSelectedFood().name == "Forever Custom Stew",
		"Food must be detected as soon as streamed tooltip loads (no cache poisoning)")
end)

Test("10. Dynamic FoodGuide scales automatically with player level, adapts to class, and updates on PLAYER_LEVEL_UP", function()
	local printed = {}
	local c = CreateEnv({
		playerLevel = 8,
		playerClass = "PALADIN",
		playerClassName = "Paladin",
		bagItems = {
			[0] = {
				[1] = { itemID = 12210, name = "Roast Raptor", minLevel = 25, itemLevel = 35, sellPrice = 50, count = 7 },
			},
		},
	})
	c.env.print = function(...)
		local parts = {}
		for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
		printed[#printed + 1] = table.concat(parts, " ")
	end

	local fg = c.ns:GetModule("FoodGuide")
	local scan = c.ns:GetModule("Scanner")

	-- Level 8 -> Bracket 1 (Lvl 1-9 Apprentice)
	local rec8 = fg:GetRecommendations()
	AssertEq(rec8.bracketID, 1, "Level 8 must map to Bracket 1 (Lvl 1-9)")
	AssertEq(rec8.nextPreview.unlockLevel, 10, "Level 8 previews Level 10 Journeyman unlock")

	-- Level up to 15 -> Bracket 3 (Lvl 15-24), triggers new tier alert in chat!
	local beforePrints = #printed
	c.Fire("PLAYER_LEVEL_UP", 15)
	Assert(#printed > beforePrints, "Crossing into a new food bracket on PLAYER_LEVEL_UP prints tier unlock alert")
	local rec15 = fg:GetRecommendations()
	AssertEq(rec15.bracketID, 3, "Level 15 automatically updates to Bracket 3 (Lvl 15-24)")

	-- Level up to 26 -> Bracket 4 (Lvl 25-34), Roast Raptor now usable & marked inBags=7!
	c.Fire("PLAYER_LEVEL_UP", 26)
	scan:ScanBagsAndSpells()
	local rec26 = fg:GetRecommendations()
	AssertEq(rec26.bracketID, 4, "Level 26 updates to Bracket 4 (Lvl 25-34)")
	AssertEq(rec26.picks[1].name, "Roast Raptor", "Paladin Lvl 26 #1 pick is Roast Raptor")
	AssertEq(rec26.picks[1].inBags, 7, "Roast Raptor shows x7 in bags")
	AssertEq(rec26.nextPreview.unlockLevel, 35, "Level 26 previews Level 35 Artisan unlock")

	-- Level up to 46 -> Bracket 6 (Lvl 45-59 Endgame Leveling)
	c.Fire("PLAYER_LEVEL_UP", 46)
	local rec46 = fg:GetRecommendations()
	AssertEq(rec46.bracketID, 6, "Level 46 updates to Bracket 6 (Lvl 45-59)")
	AssertEq(rec46.picks[1].name, "Smoked Desert Dumplings", "Paladin Lvl 46 #1 pick is Smoked Desert Dumplings")

	-- Caster class (Mage at Lvl 36) -> prioritizes Spell Power / MP5 (Spotted Yellowtail / Smoked Sagefish)
	local cMage = CreateEnv({ playerLevel = 36, playerClass = "MAGE", playerClassName = "Mage" })
	local recMage = cMage.ns:GetModule("FoodGuide"):GetRecommendations()
	AssertEq(recMage.picks[1].name, "Spotted Yellowtail", "Mage Lvl 36 #1 pick is Spotted Yellowtail (+Spell Power)")

	-- Slash command /lp food runs cleanly and opens the interactive Food Drawer
	local beforeCmd = #printed
	c.env.SlashCmdList.LEVELPULSE("food")
	Assert(#printed > beforeCmd, "/lp food prints the recommended food guide")
	AssertEq(c.ns:GetModule("UI").foodDrawer:IsShown(), true, "/lp food opens the interactive Food Drawer")
end)

Test("11. Interactive Food Drawer supports Ctrl+C Copy Box, Auction House search, Cooking filter, and Chat Shift-Click", function()
	local c = CreateEnv({
		playerLevel = 26,
		playerClass = "PALADIN",
		playerClassName = "Paladin",
		knownSpells = { ["Roast Raptor"] = 15856 },
		bagItems = {
			[0] = {
				[1] = { itemID = 12210, name = "Roast Raptor", minLevel = 25, itemLevel = 35, sellPrice = 50, count = 4 },
			},
		},
	})
	local ui = c.ns:GetModule("UI")
	ui:ToggleFoodDrawer(true)
	AssertEq(ui.foodDrawer:IsShown(), true, "Food Drawer opens cleanly")
	AssertEq(ui.drawerRows[1].food.name, "Roast Raptor", "Row 1 is Roast Raptor for Lvl 26 Paladin")

	-- 1. Plain click with no AH/Cooking open -> selects & highlights "Roast Raptor" in Copy Box for Ctrl+C!
	ui.drawerRows[1]:Click()
	AssertEq(ui.drawerCopyBox:GetText(), "Roast Raptor", "Copy Box filled with exact food name")
	AssertEq(ui.drawerCopyBox._focused, true, "Copy Box auto-focused for Ctrl+C")
	AssertEq(ui.drawerCopyBox._highlighted, true, "Copy Box text auto-highlighted for Ctrl+C")

	-- 2. Open AuctionHouseFrame -> clicking row fills AH SearchBox & triggers StartSearch()!
	local ahSearched = false
	local ahBox = { SetText = function(self, t) self._text = t end, ClearFocus = function() end }
	c.env.AuctionHouseFrame = {
		IsShown = function() return true end,
		SearchBar = {
			SearchBox = ahBox,
			StartSearch = function() ahSearched = true end,
		},
	}
	ui.drawerRows[1]:Click()
	AssertEq(ahBox._text, "Roast Raptor", "Auction House SearchBox filled with 'Roast Raptor'")
	AssertEq(ahSearched, true, "Auction House StartSearch() triggered immediately")
	c.env.AuctionHouseFrame = nil

	-- 3. Open ProfessionsFrame (Cooking) -> clicking row filters Cooking SearchBox & opens recipe!
	local openedRecipeID = nil
	local cookBox = { SetText = function(self, t) self._text = t end, ClearFocus = function() end }
	c.env.ProfessionsFrame = {
		IsShown = function() return true end,
		CraftingPage = { RecipeList = { SearchBox = cookBox } },
	}
	c.env.C_TradeSkillUI = {
		OpenRecipe = function(id) openedRecipeID = id end,
	}
	ui.drawerRows[1]:Click()
	AssertEq(cookBox._text, "Roast Raptor", "Cooking SearchBox filtered to 'Roast Raptor'")
	AssertEq(openedRecipeID, 15856, "C_TradeSkillUI.OpenRecipe opened Roast Raptor recipe")
	c.env.ProfessionsFrame = nil

	-- 4. Active Chat EditBox + Shift-Click -> inserts clickable itemLink into chat!
	local insertedLink = nil
	c.env.IsShiftKeyDown = function() return true end
	c.env.ChatEdit_GetActiveWindow = function() return { Insert = function(_, t) insertedLink = t end } end
	c.env.ChatEdit_InsertLink = function(lnk) insertedLink = lnk end
	ui.drawerRows[1]:Click()
	AssertEq(insertedLink, "link", "Shift-Click with open chat inserts the resolved WoW itemLink")
end)

Test("12. DungeonJournal-style HUD renders 3-column metrics, 3 icon buff pills, action tray, and resize grip", function()
	local c = CreateEnv({
		playerLevel = 26,
		xp = 5000,
		maxXP = 20000,
		restedXP = 3000,
		playerAuras = {
			{ name = "Well Fed", spellId = 19705, expirationTime = 1000 + 840 },
			{ name = "Well-Rested", spellId = 436586, applications = 3, expirationTime = 1000 + 5400 },
			{ name = "Camp Benefits", spellId = 1229741, expirationTime = 1000 + 3600 },
		},
	})
	local ui = c.ns:GetModule("UI")
	ui:Refresh()

	AssertEq(ui.col1Val:GetText(), "+8%", "Column 1 displays +8% active XP bonus")
	AssertEq(ui.col2Val:GetText(), "25%", "Column 2 displays 25% level progress before XP/hr starts")
	AssertEq(ui.col3Val:GetText(), "15%", "Column 3 displays 15% Rested XP")
	AssertEq(ui.foodPill.text:GetText(), "14m", "Food pill shows 14m remaining")
	AssertEq(ui.bagPill.text:GetText(), "3/3 1h30m", "Bag pill shows 3/3 1h30m")
	AssertEq(ui.campPill.text:GetText(), "1h", "Camp pill shows 1h remaining")
	AssertEq(ui.actionTray:IsShown(), false, "Action tray collapses when all buffs are active")
	Assert(ui.grip ~= nil, "Corner resize grip is built")
end)

print(string.format("\nResults: %d passed, %d failed", passed, failed))
if failed > 0 then
	os.exit(1)
end
