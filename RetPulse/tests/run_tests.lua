-- Offline unit & integration test suite for RetPulse (WoW: Forever 16001)
-- Not listed in RetPulse.toc, so WoW never loads this file.

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

-------------------------------------------------------------------------------
-- Mock WoW: Forever (Mainline 12.x / Camelot 16001) runtime
-------------------------------------------------------------------------------
local function CreateEnv(opts)
	opts = opts or {}
	local now = opts.now or 1000.0
	local inCombat = opts.inCombat or false
	local playerClass = opts.playerClass or "PALADIN"
	local weaponSpeed = opts.weaponSpeed or 2.87
	local meleeHaste = opts.meleeHaste or 0
	local weaponSpeedSecret = opts.weaponSpeedSecret or false
	local weaponItemID = opts.weaponItemID or 279864
	local targetExists = opts.targetExists ~= false
	local targetHostile = opts.targetHostile ~= false
	local targetDead = opts.targetDead or false
	local targetType = opts.targetType or "Humanoid"
	local swingInRange = opts.swingInRange
	if swingInRange == nil then swingInRange = true end

	local knownSpells = opts.knownSpells or {
		["Judgement"] = 20271,
		["Holy Strike"] = 678,
		["Seal of Righteousness"] = 20288,
		["Seal of Fury"] = 1311656,
	}
	local usableSpells = opts.usableSpells or {
		["Judgement"] = true,
		["Holy Strike"] = true,
		["Seal of Righteousness"] = true,
		["Seal of Fury"] = true,
	}
	local inRangeSpells = opts.inRangeSpells or {
		["Judgement"] = true,
		["Holy Strike"] = true,
		["Exorcism"] = true,
		["Hammer of Wrath"] = true,
	}
	local actionSlots = opts.actionSlots or {}
	local bindings = opts.bindings or {}

	local SECRET_TAG = {}
	local function MakeSecret(v)
		return setmetatable({ __secret = true, val = v }, {
			__tostring = function() error("secret value converted to string") end,
		})
	end

	local function IsSecretValue(v)
		return type(v) == "table" and rawget(v, "__secret") == true
	end

	local spellById = {}
	for name, id in pairs(knownSpells) do
		spellById[id] = name
	end
	spellById[1310735] = "Unsealed Wrath"
	spellById[20375] = "Seal of Command"
	spellById[20271] = "Judgement"
	spellById[678] = "Holy Strike"
	spellById[20288] = "Seal of Righteousness"
	spellById[1311656] = "Seal of Fury"
	spellById[26573] = "Consecration"
	spellById[879] = "Exorcism"
	spellById[24275] = "Hammer of Wrath"
	spellById[20473] = "Holy Shock"
	spellById[2812] = "Holy Wrath"
	spellById[853] = "Hammer of Justice"
	spellById[21082] = "Seal of the Crusader"
	spellById[20217] = "Blessing of Kings"
	spellById[19834] = "Blessing of Might"
	spellById[19850] = "Blessing of Wisdom"
	spellById[7294] = "Retribution Aura"
	spellById[465] = "Devotion Aura"
	spellById[1953] = "Blink"
	spellById[2061] = "Flash Heal"
	spellById[20066] = "Repentance"
	spellById[1044] = "Blessing of Freedom"
	spellById[642] = "Divine Shield"
	spellById[498] = "Divine Protection"
	spellById[1022] = "Blessing of Protection"
	spellById[7744] = "Will of the Forsaken"
	spellById[59752] = "Every Man for Himself"
	spellById[31884] = "Avenging Wrath"
	spellById[20164] = "Seal of Justice"

	local registeredFrames = {}
	local timers = {}

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
		function r:SetTexture(t) self._tex = t end
		function r:SetTexCoord() end
		function r:SetRotation() end
		function r:SetBlendMode() end
		function r:SetVertexColor() end
		function r:SetDesaturated() end
		function r:SetAlpha(a) self._alpha = a end
		function r:GetAlpha() return self._alpha end
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

	local function MakeFrame(frameType)
		local f = MakeRegion()
		f._events = {}
		f._scripts = {}
		f._children = {}
		f._level = 1
		f._scale = 1
		function f:RegisterEvent(ev) self._events[ev] = true end
		function f:UnregisterEvent(ev) self._events[ev] = nil end
		function f:UnregisterAllEvents() self._events = {} end
		function f:SetScript(name, fn) self._scripts[name] = fn end
		function f:GetScript(name) return self._scripts[name] end
		function f:CreateTexture() return MakeRegion() end
		function f:CreateFontString() return MakeRegion() end
		function f:SetBackdrop() end
		function f:SetBackdropColor() end
		function f:SetBackdropBorderColor() end
		function f:SetMovable() end
		function f:EnableMouse() end
		function f:RegisterForDrag() end
		function f:SetClampedToScreen() end
		function f:SetClipsChildren() end
		function f:StartMoving() end
		function f:StopMovingOrSizing() end
		function f:SetScale(s) self._scale = s end
		function f:GetScale() return self._scale end
		function f:GetFrameLevel() return self._level end
		function f:SetFrameLevel(l) self._level = l end
		function f:SetStatusBarTexture() end
		function f:SetStatusBarColor() end
		function f:SetMinMaxValues(lo, hi) self._min, self._max = lo, hi end
		function f:SetValue(v) self._val = v end
		function f:SetDrawEdge() end
		function f:SetDrawBling() end
		function f:SetHideCountdownNumbers() end
		function f:SetSwipeColor() end
		function f:SetReverse() end
		function f:SetCooldown(start, dur) self._cdStart, self._cdDur = start, dur end
		function f:SetCooldownFromDurationObject(durObj, clearIfZero)
			self._cdDurObj, self._clearIfZero = durObj, clearIfZero
		end
		function f:Clear() self._cdStart, self._cdDur, self._cdDurObj = nil, nil, nil end
		function f:IsForbidden() return false end
		function f:RegisterForClicks() end
		function f:HookScript(name, fn) self._scripts["hook_" .. name] = fn end
		function f:SetAttribute(k, v) self._attrs = self._attrs or {}; self._attrs[k] = v end
		function f:GetAttribute(k) return self._attrs and self._attrs[k] end
		function f:SetParent(p) self._parent = p end
		function f:GetParent() return self._parent end
		function f:GetFrameStrata() return self._strata or "MEDIUM" end
		function f:SetFrameStrata(s) self._strata = s end
		function f:GetChildren() return table.unpack(self._children) end
		registeredFrames[#registeredFrames + 1] = f
		return f
	end

	local env = {
		WOW_PROJECT_ID = 18,
		WOW_PROJECT_CAMELOT = 18,
		Enum = { PlayerSwingType = { MainHand = 0, OffHand = 1 } },
		SOUNDKIT = { IG_MAINMENU_OPTION_CHECKBOX_ON = 856 },
		SlashCmdList = {},
		UIParent = MakeFrame("Frame"),
		GameTooltip = MakeFrame("GameTooltip"),
		RetPulseDB = opts.savedDB,
		BuffIconCooldownViewer = nil,
		BuffBarCooldownViewer = nil,
		EssentialCooldownViewer = nil,
		UtilityCooldownViewer = nil,
	}

	function env.strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
	function env.date() return "2026-11-22 02:00:00" end
	function env.GetTime() return now end
	function env.time() return math.floor(now) end
	function env.GetBuildInfo() return "1.60.1", "70938", "Nov 12 2026", 16001 end
	function env.InCombatLockdown() return inCombat end
	function env.IsInInstance() return false end
	function env.issecretvalue(v) return IsSecretValue(v) end
	function env.issecrettable(v) return IsSecretValue(v) end
	function env.CreateFrame(ft, _name, parent, _template)
		local f = MakeFrame(ft)
		f._parent = parent
		if parent and parent._children then
			parent._children[#parent._children + 1] = f
		end
		return f
	end
	function env.PlaySound() end
	function env.UnitClass() return "Paladin", playerClass, 2 end
	-- Classic/Mainline class colors used by HUD BUFF:/DISPEL: name tinting.
	env.RAID_CLASS_COLORS = {
		WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
		PALADIN = { r = 0.96, g = 0.55, b = 0.73 },
		HUNTER = { r = 0.67, g = 0.83, b = 0.45 },
		ROGUE = { r = 1.00, g = 0.96, b = 0.41 },
		PRIEST = { r = 1.00, g = 1.00, b = 1.00 },
		DEATHKNIGHT = { r = 0.77, g = 0.12, b = 0.23 },
		SHAMAN = { r = 0.00, g = 0.44, b = 0.87 },
		MAGE = { r = 0.25, g = 0.78, b = 0.92 },
		WARLOCK = { r = 0.53, g = 0.53, b = 0.93 },
		MONK = { r = 0.00, g = 1.00, b = 0.59 },
		DRUID = { r = 1.00, g = 0.49, b = 0.04 },
		DEMONHUNTER = { r = 0.64, g = 0.19, b = 0.79 },
		EVOKER = { r = 0.20, g = 0.58, b = 0.50 },
	}
	function env.UnitLevel() return opts.playerLevel or 20 end
	function env.UnitName() return targetExists and "Test Mob" or nil end
	function env.UnitIsDeadOrGhost() return false end
	function env.UnitExists(u) return u == "target" and targetExists or true end
	local nameplates = opts.nameplates or {}
	function env.UnitCanAttack(_, u)
		if u == "target" then return targetExists and targetHostile end
		for _, np in ipairs(nameplates) do
			if np.unit == u then return np.hostile ~= false end
		end
		return false
	end
	function env.UnitIsDead(u)
		if u == "target" then return targetDead end
		for _, np in ipairs(nameplates) do
			if np.unit == u then return np.dead == true end
		end
		return false
	end
	function env.UnitAffectingCombat(u)
		if u == "player" then return inCombat end
		for _, np in ipairs(nameplates) do
			if np.unit == u then return np.inCombat ~= false end
		end
		return false
	end
	env.C_NamePlate = {
		GetNamePlates = function()
			local list = {}
			for _, np in ipairs(nameplates) do
				list[#list + 1] = { namePlateUnitToken = np.unit }
			end
			return list
		end,
	}
	local targetClassification = opts.targetClassification or "normal"
	local targetCastName, targetCastNotInt = nil, false
	function env.UnitCreatureType() return targetExists and targetType or nil end
	function env.UnitClassification() return targetClassification end
	function env.UnitCastingInfo(u)
		if u == "target" and targetCastName then
			return targetCastName, targetCastName, 0, now * 1000, (now + 2) * 1000, false, "cast1", targetCastNotInt
		end
		return nil
	end
	function env.UnitChannelInfo() return nil end
	function env.UnitPower() return MakeSecret(500) end
	function env.UnitPowerMax() return MakeSecret(1000) end
	function env.UnitHealth() return MakeSecret(1000) end
	function env.GetInventoryItemID() return weaponItemID end
	function env.UnitAttackSpeed()
		if weaponSpeedSecret then return MakeSecret(weaponSpeed) end
		return weaponSpeed
	end
	function env.GetMeleeHaste()
		if weaponSpeedSecret then return MakeSecret(meleeHaste) end
		return meleeHaste
	end
	function env.GetActionInfo(slot)
		local entry = actionSlots[slot]
		if not entry then return nil end
		return entry.type, entry.id
	end
	function env.GetBindingKey(cmd) return bindings[cmd] end
	function env.print() end

	env.C_Spell = {
		GetSpellIDForSpellIdentifier = function(name)
			return knownSpells[name]
		end,
		GetSpellInfo = function(idOrName)
			if type(idOrName) == "number" then
				local nm = spellById[idOrName]
				if nm then return { name = nm, spellID = idOrName } end
				return nil
			elseif type(idOrName) == "string" then
				return { name = idOrName, spellID = knownSpells[idOrName] or 0 }
			end
		end,
		GetSpellTexture = function(name) return name and ("tex:" .. name) or nil end,
		IsSpellUsable = function(name)
			local noMana = opts.noManaSpells and opts.noManaSpells[name] == true or false
			if noMana then return false, true end
			return usableSpells[name] == true, false
		end,
		IsSpellInRange = function(name, unit)
			if unit and unit ~= "target" then
				for _, np in ipairs(nameplates) do
					if np.unit == unit then return np.inRange ~= false end
				end
				return false
			end
			return inRangeSpells[name] == true
		end,
		GetSpellCooldown = function(name)
			if inCombat then
				return { startTime = MakeSecret(0), duration = MakeSecret(0), isEnabled = true }
			end
			return { startTime = 0, duration = 0, isEnabled = true }
		end,
		GetSpellCooldownDuration = function(name)
			if opts.cooldownDurations then
				return opts.cooldownDurations[name]
			end
			return nil
		end,
	}

	env.C_SpellBook = {
		IsSpellKnown = function(id)
			for _, knownId in pairs(knownSpells) do
				if knownId == id then return true end
			end
			return false
		end,
	}

	local playerAuras = opts.playerAuras or {}
	env.C_UnitAuras = {
		GetAuraDataByIndex = function(unit, idx)
			if inCombat then error("Auras cannot be accessed when secret") end
			if unit == "player" then return playerAuras[idx] end
			return nil
		end,
		GetPlayerAuraBySpellID = function()
			if inCombat then error("Auras cannot be accessed when secret") end
			return nil
		end,
	}

	local rangeCheckEnabled = {}
	env.C_SwingTimer = {
		EnableRangeCheck = function(swingType, enabled)
			rangeCheckEnabled[swingType] = enabled
		end,
		IsTargetWithinSwingRange = function() return swingInRange end,
	}

	env.C_CooldownViewer = opts.cdmAPI or {
		GetCooldownViewerCategorySet = function() return {} end,
		GetCooldownViewerCooldownInfo = function() return nil end,
	}

	env.C_Timer = {
		After = function(delay, fn)
			timers[#timers + 1] = { at = now + delay, fn = fn, cancelled = false }
		end,
		NewTicker = function(interval, fn)
			local t = { cancelled = false }
			function t:Cancel() self.cancelled = true end
			return t
		end,
	}

	env.Settings = {
		VarType = { Boolean = "boolean", String = "string", Number = "number" },
		RegisterVerticalLayoutCategory = function(name)
			local cat = { _id = 1, GetID = function(self) return self._id end }
			local layout = { AddInitializer = function() end }
			return cat, layout
		end,
		RegisterAddOnSetting = function(cat, name, var, tbl, varType, label, default)
			local s = { _var = var, _tbl = tbl }
			function s:SetValueChangedCallback(cb) self._cb = cb end
			function s:SetValue(v) self._tbl[self._var] = v end
			return s
		end,
		CreateCheckbox = function() end,
		CreateDropdown = function() end,
		CreateControlTextContainer = function()
			return { Add = function() end, GetData = function() return {} end }
		end,
		CreateSliderOptions = function()
			return { SetLabelFormatter = function() end }
		end,
		CreateSlider = function() end,
		RegisterAddOnCategory = function() end,
		OpenToCategory = function() end,
	}

	-- Populate globals onto _G for the loaded chunks
	setmetatable(env, { __index = _G })
	env._G = env

	local ns = {}
	local files = {
		"Core.lua",
		"Keybinds.lua",
		"WeaponEngine.lua",
		"CombatTracker.lua",
		"PvPEngine.lua",
		"PriorityQueue.lua",
		"Talents.lua",
		"Diag.lua",
		"Trace.lua",
		"UITheme.lua",
		"FX.lua",
		"UI.lua",
		"Config.lua",
	}

	for _, file in ipairs(files) do
		local chunk, err = loadfile(file, "t", env)
		if not chunk then
			error("Failed to load " .. file .. ": " .. tostring(err))
		end
		chunk("RetPulse", ns)
	end

	local ctrl
	ctrl = {
		env = env,
		ns = ns,
		Fire = function(event, ...)
			for _, f in ipairs(registeredFrames) do
				if f._events[event] and f._scripts.OnEvent then
					f._scripts.OnEvent(f, event, ...)
				end
			end
		end,
		Advance = function(dt)
			now = now + dt
			local due = {}
			local keep = {}
			for _, t in ipairs(timers) do
				if not t.cancelled and t.at <= now then
					due[#due + 1] = t
				elseif not t.cancelled then
					keep[#keep + 1] = t
				end
			end
			timers = keep
			for _, t in ipairs(due) do t.fn() end
		end,
		SetCombat = function(v)
			inCombat = v
			ctrl.Fire(v and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED")
		end,
		SetWeaponSpeedSecret = function(v) weaponSpeedSecret = v end,
		SetSwingInRange = function(v) swingInRange = v end,
		SetTargetType = function(t) targetType = t end,
		SetWeaponItemID = function(id) weaponItemID = id end,
		SetNameplates = function(list) nameplates = list end,
		SetTargetClassification = function(cls) targetClassification = cls end,
		SetTargetCasting = function(name, notInt)
			targetCastName = name
			targetCastNotInt = notInt == true
		end,
		SetPlayerAuras = function(list) playerAuras = list end,
		GetRangeCheckEnabled = function(st) return rangeCheckEnabled[st] end,
		MakeFrame = MakeFrame,
	}

	ctrl.Fire("ADDON_LOADED", "RetPulse")
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
-- Test cases
-------------------------------------------------------------------------------

Test("1. Non-Paladin class gating skips initialization", function()
	local c = CreateEnv({ playerClass = "WARRIOR" })
	AssertEq(c.ns.IsPaladin, false, "IsPaladin should be false for Warrior")
	AssertEq(c.ns.db, nil, "db should not be initialized for Warrior")
	local ui = c.ns:GetModule("UI")
	AssertEq(ui.frame, nil, "UI frame should not be created for Warrior")
end)

Test("2. Level 20 Ret vs Humanoid never recommends unlearned Exorcism or HoW", function()
	local c = CreateEnv({
		playerLevel = 20,
		targetType = "Humanoid",
		knownSpells = {
			["Judgement"] = 20271,
			["Holy Strike"] = 678,
			["Seal of Righteousness"] = 20288,
			["Seal of Fury"] = 1311656,
		},
		usableSpells = {
			["Judgement"] = true,
			["Holy Strike"] = true,
			["Seal of Righteousness"] = true,
			["Seal of Fury"] = true,
		},
	})
	c.SetCombat(true)
	-- Cast Seal of Righteousness, Judgement, Holy Strike so both are on CD and GCD is active
	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast1", 20288)
	c.Advance(1.6)
	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast2", 20271)
	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast3", 678)

	local pq = c.ns:GetModule("PriorityQueue")
	local cur = pq:Evaluate()
	Assert(cur ~= "Exorcism", "Must NEVER recommend unlearned Exorcism on Humanoid, got: " .. tostring(cur))
	Assert(cur ~= "Hammer of Wrath", "Must NEVER recommend unlearned Hammer of Wrath, got: " .. tostring(cur))
	Assert(cur == "Judgement" or cur == "Holy Strike", "Fallback countdown should be Judgement or Holy Strike, got: " .. tostring(cur))
end)

Test("3. Exorcism recommended on Undead when known", function()
	local c = CreateEnv({
		playerLevel = 40,
		targetType = "Undead",
		knownSpells = {
			["Judgement"] = 20271,
			["Holy Strike"] = 678,
			["Exorcism"] = 879,
			["Seal of Righteousness"] = 20288,
		},
		usableSpells = {
			["Judgement"] = true,
			["Holy Strike"] = true,
			["Exorcism"] = true,
			["Seal of Righteousness"] = true,
		},
	})
	c.SetCombat(true)
	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "c1", 20288)
	c.Advance(1.6)
	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "c2", 20271)
	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "c3", 678)
	c.Advance(1.6)

	local pq = c.ns:GetModule("PriorityQueue")
	local cur = pq:Evaluate()
	AssertEq(cur, "Exorcism", "Exorcism should be recommended on Undead when J & HS are on CD")
end)

Test("4. Safety: Judgement is NEVER recommended while Seal of Fury is up", function()
	local c = CreateEnv({
		playerLevel = 20,
		knownSpells = {
			["Judgement"] = 20271,
			["Holy Strike"] = 678,
			["Seal of Fury"] = 1311656,
			["Seal of Righteousness"] = 20288,
		},
		usableSpells = {
			["Judgement"] = true,
			["Holy Strike"] = true,
			["Seal of Fury"] = true,
			["Seal of Righteousness"] = true,
		},
	})
	c.SetCombat(true)
	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "c1", 1311656) -- Seal of Fury
	c.Advance(1.6)

	local pq = c.ns:GetModule("PriorityQueue")
	local cur = pq:Evaluate()
	Assert(cur ~= "Judgement", "Judgement must NEVER be recommended while Seal of Fury is active")
	AssertEq(cur, "Holy Strike", "Should recommend Holy Strike instead of Judgement")

	-- Put Holy Strike on CD too: fallback countdown must STILL not recommend Judgement!
	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "c2", 678)
	local cur2 = pq:Evaluate()
	Assert(cur2 ~= "Judgement", "Judgement must NEVER appear in countdown fallback while Seal of Fury is active")
end)

Test("5. WeaponEngine keeps last readable weaponSpeed when secret in combat", function()
	local c = CreateEnv({ weaponSpeed = 3.5 })
	local engine = c.ns:GetModule("WeaponEngine")
	AssertEq(engine.weaponSpeed, 3.5, "Initial weaponSpeed should be 3.5")
	AssertEq(engine:GetBracket(), "slow", "Initial bracket should be slow")

	c.SetCombat(true)
	c.SetWeaponSpeedSecret(true)
	c.Fire("UNIT_ATTACK_SPEED", "player")
	AssertEq(engine.weaponSpeed, 3.5, "weaponSpeed must not be wiped to nil when secret in combat")
	AssertEq(engine:GetBracket(), "slow", "Bracket must remain slow in combat")
end)

Test("6. RefreshCdm survives forbidden frames and finds BuffIconCooldownViewer child", function()
	local forbiddenFrame = {
		IsForbidden = function() return true end,
		GetChildren = function() error("forbidden!") end,
	}
	setmetatable(forbiddenFrame, {
		__index = function(_, k)
			if k == "IsForbidden" then return function() return true end end
			error("attempt to index forbidden frame: " .. tostring(k))
		end,
	})

	local cdmChild = {
		cooldownID = 42,
		IsForbidden = function() return false end,
		itemData = {
			cooldownID = 42,
			auraDataCached = { applications = 2, expirationTime = 1015 },
		},
	}

	local c = CreateEnv({
		cdmAPI = {
			GetCooldownViewerCategorySet = function(cat)
				if cat == 0 then return { 42 } end
				return {}
			end,
			GetCooldownViewerCooldownInfo = function(id)
				if id == 42 then return { spellID = 1310735 } end
				return nil
			end,
		},
	})

	local viewer = c.MakeFrame("Frame")
	viewer._children = { forbiddenFrame, cdmChild }
	c.env.BuffIconCooldownViewer = viewer

	local tracker = c.ns:GetModule("CombatTracker")
	tracker:RefreshCdm()
	Assert(tracker.cdmReport:find("ok=true") ~= nil, "cdmReport should be ok=true, got: " .. tostring(tracker.cdmReport))
	AssertEq(#tracker.cdmFrames, 1, "Should find the 1 Cooldown Manager frame")
	AssertEq(tracker:ReadCdmEchoes(), 2, "Should read 2 echoes from Cooldown Manager frame")
end)

Test("7. IsInSwingRange updates dynamically without changing targets", function()
	local c = CreateEnv({ swingInRange = false })
	local tracker = c.ns:GetModule("CombatTracker")
	AssertEq(tracker:IsInSwingRange(), false, "Initially out of melee range")

	c.SetSwingInRange(true)
	c.Advance(0.2)
	AssertEq(tracker:IsInSwingRange(), true, "Should update to in-range once player closes distance")
end)

Test("8. Unsealed Wrath echoes: miss ignored, weapon swap clears, 3 stacks triggers twist", function()
	local c = CreateEnv({
		playerLevel = 60,
		weaponSpeed = 3.6,
		knownSpells = {
			["Unsealed Wrath"] = 1310735,
			["Seal of Command"] = 20375,
			["Seal of Righteousness"] = 20288,
			["Judgement"] = 20271,
			["Holy Strike"] = 678,
		},
		usableSpells = {
			["Seal of Command"] = true,
			["Seal of Righteousness"] = true,
			["Judgement"] = true,
			["Holy Strike"] = true,
		},
	})
	local tracker = c.ns:GetModule("CombatTracker")
	local pq = c.ns:GetModule("PriorityQueue")
	c.SetCombat(true)

	-- Cast primary seal (Seal of Command for slow 3.6 weapon)
	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "s1", 20375)
	c.Advance(1.6)

	-- Swing 1: lands -> 1 echo
	c.Fire("PLAYER_SWING", 3.6, 0)
	-- Duplicate mid-cycle swing must be rejected
	c.Advance(0.5)
	c.Fire("PLAYER_SWING", 3.6, 0)
	AssertEq(tracker.swingRejected, 1, "Mid-cycle duplicate swing should be rejected")
	c.Advance(0.5) -- > MISS_WINDOW
	AssertEq(tracker:GetEchoes(), 1, "1st landed swing -> 1 echo")

	-- Swing 2: missed (DODGE) -> still 1 echo
	c.Advance(3.0)
	c.Fire("PLAYER_SWING", 3.6, 0)
	c.Advance(0.1)
	c.Fire("UNIT_COMBAT", "target", "DODGE")
	c.Advance(1.0)
	AssertEq(tracker:GetEchoes(), 1, "Dodged swing must not add an echo")

	-- Swings 3 & 4: land -> 3 echoes
	c.Advance(3.0)
	c.Fire("PLAYER_SWING", 3.6, 0)
	c.Advance(1.0)
	AssertEq(tracker:GetEchoes(), 2, "2 echoes")

	c.Advance(3.0)
	c.Fire("PLAYER_SWING", 3.6, 0)
	c.Advance(1.0)
	AssertEq(tracker:GetEchoes(), 3, "3 echoes")

	-- Remaining swing time is 2.6s (> 1.5s GCD) -> should recommend twist to Seal of Righteousness!
	local cur = pq:Evaluate()
	AssertEq(cur, "Seal of Righteousness", "At 3 echoes with open swing window, must recommend secondary seal")

	-- Weapon swap wipes echoes
	c.SetWeaponItemID(999999)
	c.Fire("UNIT_INVENTORY_CHANGED", "player")
	AssertEq(tracker:GetEchoes(), 0, "Main-hand weapon swap must clear all echoes")
end)

Test("9. Keybinds module scans action bars and formats short labels", function()
	local c = CreateEnv({
		actionSlots = {
			[1] = { type = "spell", id = 20271 }, -- Judgement
			[2] = { type = "spell", id = 678 },   -- Holy Strike
			[61] = { type = "spell", id = 20288 }, -- Seal of Righteousness
		},
		bindings = {
			ACTIONBUTTON1 = "SHIFT-1",
			ACTIONBUTTON2 = "MOUSEWHEELDOWN",
			MULTIACTIONBAR1BUTTON1 = "CTRL-R",
		},
	})
	local kb = c.ns:GetModule("Keybinds")
	AssertEq(kb:GetForSpell("Judgement"), "S1", "SHIFT-1 -> S1")
	AssertEq(kb:GetForSpell("Holy Strike"), "MWD", "MOUSEWHEELDOWN -> MWD")
	AssertEq(kb:GetForSpell("Seal of Righteousness"), "CR", "CTRL-R -> CR")
end)

Test("10. UI visibility modes, unlock reveal, and single enabled state", function()
	local c = CreateEnv({ inCombat = false, targetExists = false })
	local ui = c.ns:GetModule("UI")
	AssertEq(c.ns.db.visibility, "combat", "Default visibility is combat")
	AssertEq(ui.frame:IsShown(), false, "Hidden out of combat by default")

	-- Combat starts -> HUD shows immediately
	c.SetCombat(true)
	AssertEq(ui.frame:IsShown(), true, "HUD must show immediately on PLAYER_REGEN_DISABLED")

	-- Combat ends -> fades out and hides
	c.SetCombat(false)
	ui:StepFade(1.0)
	AssertEq(ui.frame:IsShown(), false, "HUD hides after fade-out")

	-- Slash /rp unlock reveals HUD even out of combat
	c.ns:HandleSlash("unlock")
	AssertEq(ui.frame:IsShown(), true, "Unlocking must reveal HUD for placement")

	-- Addon compartment toggle disables cleanly via ns.db.enabled
	c.ns.ToggleVisibility()
	AssertEq(c.ns.db.enabled, false, "ToggleVisibility toggles ns.db.enabled")
	AssertEq(ui.frame:IsShown(), false, "Disabling hides HUD immediately")
end)

Test("11. Trace defaults off and flushes on PLAYER_LOGOUT", function()
	local c = CreateEnv({})
	AssertEq(c.ns.db.traceEnabled, false, "traceEnabled should default to false")
	AssertEq(c.ns.db.logEnabled, false, "logEnabled should default to false")

	c.ns:HandleSlash("trace on")
	local trace = c.ns:GetModule("Trace")
	AssertEq(trace.enabled, true, "trace should start on /rp trace on")
	c.Fire("PLAYER_LOGOUT")
	Assert(c.ns.db.traceLog and #c.ns.db.traceLog > 0, "PLAYER_LOGOUT must flush traceLog to SavedVariables")
end)

Test("12. Cooldown swipe matches spell cooldown (10s), never weapon swing speed (2.87s)", function()
	local c = CreateEnv({
		playerLevel = 20,
		weaponSpeed = 2.87,
		knownSpells = {
			["Judgement"] = 20271,
			["Holy Strike"] = 678,
			["Seal of Righteousness"] = 20288,
		},
		usableSpells = {
			["Judgement"] = true,
			["Holy Strike"] = true,
			["Seal of Righteousness"] = true,
		},
	})
	c.SetCombat(true)
	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "s1", 20288) -- Seal of Righteousness
	c.Advance(1.6)
	c.Fire("PLAYER_SWING", 2.87, 0)
	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "c1", 20271) -- Judgement (10s CD)
	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "c2", 678)   -- Holy Strike (10s CD)

	local ui = c.ns:GetModule("UI")
	ui:Refresh()

	AssertEq(ui.cooldown:IsShown(), true, "Cooldown swipe should be shown while waiting on spell CD")
	AssertEq(ui.cooldown._cdDur, 10, "Cooldown swipe duration must match spell cooldown (10s), not swing (2.87s)")
	AssertEq(ui.swingBar:IsShown(), true, "Swing timer bar should be shown on the Command Plate")
	Assert(ui.dial ~= nil, "Main icon hub frame should exist")
	Assert(ui.swingRing ~= nil, "Swing bar alias should exist")
end)

Test("13. NEXT spell preview populates when current is ready or on cooldown", function()
	local c = CreateEnv({
		playerLevel = 20,
		knownSpells = {
			["Judgement"] = 20271,
			["Holy Strike"] = 678,
			["Seal of Righteousness"] = 20288,
		},
		usableSpells = {
			["Judgement"] = false, -- not usable until seal is cast
			["Holy Strike"] = true,
			["Seal of Righteousness"] = true,
		},
	})
	local pq = c.ns:GetModule("PriorityQueue")
	c.SetCombat(true)

	-- No seal up: current = Seal of Righteousness, next = Judgement (or Holy Strike)
	local cur, nxt = pq:Evaluate()
	AssertEq(cur, "Seal of Righteousness", "Missing seal should be current")
	Assert(nxt == "Judgement" or nxt == "Holy Strike", "Next should preview upcoming combat spell, got: " .. tostring(nxt))

	-- Cast Seal, then Judgement (10s CD), advance 2s, cast Holy Strike (10s CD):
	-- Judgement comes up first (8s left), Holy Strike is second (10s left)
	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "s1", 20288)
	c.Advance(1.6)
	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "c1", 20271)
	c.Advance(2.0)
	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "c2", 678)

	local cur2, nxt2 = pq:Evaluate()
	AssertEq(cur2, "Judgement", "Judgement should be soonest off CD")
	AssertEq(nxt2, "Holy Strike", "Holy Strike should be shown in NEXT slot")
end)

Test("14. Execute (HoW) > AoE (Consecration/Holy Wrath) > Holy Strike > Holy Shock", function()
	local c = CreateEnv({
		playerLevel = 60,
		targetType = "Undead",
		knownSpells = {
			["Judgement"] = 20271,
			["Holy Strike"] = 678,
			["Hammer of Wrath"] = 24275,
			["Consecration"] = 26573,
			["Holy Wrath"] = 2812,
			["Holy Shock"] = 20473,
			["Seal of Righteousness"] = 20288,
		},
		usableSpells = {
			["Judgement"] = true,
			["Holy Strike"] = true,
			["Hammer of Wrath"] = true,
			["Consecration"] = true,
			["Holy Wrath"] = true,
			["Holy Shock"] = true,
			["Seal of Righteousness"] = true,
		},
	})
	local pq = c.ns:GetModule("PriorityQueue")
	c.SetCombat(true)
	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "s1", 20288) -- Seal
	c.Advance(1.6)
	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "j1", 20271) -- Judgement on CD

	-- Hammer of Wrath must beat Holy Strike in execute range
	local cur1 = pq:Evaluate()
	AssertEq(cur1, "Hammer of Wrath", "Hammer of Wrath should outrank Holy Strike when usable")

	-- Put HoW on CD, enable AoE -> Consecration must beat Holy Strike
	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "h1", 24275)
	c.Advance(1.6)
	c.ns.db.aoe = true
	local cur2 = pq:Evaluate()
	AssertEq(cur2, "Consecration", "Consecration should outrank Holy Strike when AoE is enabled")

	-- Put Consecration on CD -> Holy Wrath on Undead should beat Holy Strike
	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "c1", 26573)
	c.Advance(1.6)
	local cur3 = pq:Evaluate()
	AssertEq(cur3, "Holy Wrath", "Holy Wrath should be recommended on Undead packs in AoE")

	-- Put Holy Wrath & Holy Strike on CD (and refresh HoW CD) -> Holy Shock fills when known
	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "w1", 2812)
	c.Advance(1.6)
	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "h2", 24275)
	c.Advance(1.6)
	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "hs1", 678)
	c.Advance(1.6)
	local cur4 = pq:Evaluate()
	AssertEq(cur4, "Holy Shock", "Holy Shock should fill when talented and other spells are on CD")
end)

Test("15. Swing range uses C_SwingTimer.EnableRangeCheck and PLAYER_SWING_RANGE_UPDATE", function()
	local c = CreateEnv({ swingInRange = true })
	local tracker = c.ns:GetModule("CombatTracker")

	AssertEq(c.GetRangeCheckEnabled(0), true, "MainHand range check should be enabled on login")

	-- Event pushes out-of-range immediately without waiting for TTL
	c.Fire("PLAYER_SWING_RANGE_UPDATE", 0, false, true)
	AssertEq(tracker:IsInSwingRange(), false, "PLAYER_SWING_RANGE_UPDATE(false, true) sets out of range")

	-- Event pushes back in-range immediately
	c.Fire("PLAYER_SWING_RANGE_UPDATE", 0, true, true)
	AssertEq(tracker:IsInSwingRange(), true, "PLAYER_SWING_RANGE_UPDATE(true, true) sets in range")

	-- checksRange == false must NOT overwrite range with false (per SwingTimerDocumentation.lua)
	c.Fire("PLAYER_SWING_RANGE_UPDATE", 0, false, false)
	AssertEq(tracker:IsInSwingRange(), true, "checksRange=false must not mark target out of range")
end)

Test("16. Cooldown swipe uses C_Spell.GetSpellCooldownDuration via SetCooldownFromDurationObject", function()
	local fakeDurationObj = { __durationObject = true, id = "judgement_cd" }
	local c = CreateEnv({
		playerLevel = 20,
		knownSpells = {
			["Judgement"] = 20271,
			["Holy Strike"] = 678,
			["Seal of Righteousness"] = 20288,
		},
		usableSpells = {
			["Judgement"] = true,
			["Holy Strike"] = true,
			["Seal of Righteousness"] = true,
		},
		cooldownDurations = {
			["Judgement"] = fakeDurationObj,
		},
	})
	c.SetCombat(true)
	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "s1", 20288)
	c.Advance(1.6)
	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "j1", 20271)
	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "hs1", 678)

	local ui = c.ns:GetModule("UI")
	ui:Refresh()

	AssertEq(ui.cooldown:IsShown(), true, "Cooldown frame should be shown")
	AssertEq(ui.cooldown._cdDurObj, fakeDurationObj, "Should pass server LuaDurationObject directly to SetCooldownFromDurationObject")
	AssertEq(ui.cooldown._clearIfZero, true, "Should pass clearIfZero=true")
end)

Test("17. Low mana detection uses insufficientPower from C_Spell.IsSpellUsable", function()
	local c = CreateEnv({
		playerLevel = 20,
		knownSpells = {
			["Judgement"] = 20271,
			["Holy Strike"] = 678,
			["Seal of Righteousness"] = 20288,
		},
		usableSpells = {
			["Judgement"] = true,
			["Holy Strike"] = true,
			["Seal of Righteousness"] = true,
		},
		noManaSpells = {
			["Holy Strike"] = true,
		},
	})
	c.SetCombat(true)
	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "s1", 20288)
	c.Advance(1.6)
	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "j1", 20271) -- Judgement on CD, Holy Strike OOM

	local pq = c.ns:GetModule("PriorityQueue")
	local cur = pq:Evaluate()
	AssertEq(cur, "Holy Strike", "OOM ready spell should still surface as current when nothing else is ready")
	AssertEq(pq.currentNoMana, true, "PriorityQueue should flag currentNoMana=true")

	local ui = c.ns:GetModule("UI")
	ui:Refresh()
	AssertEq(ui.status:GetText(), "Low mana", "HUD status line should display 'Low mana'")
end)

Test("18. Secret-safe mana bar passes raw UnitPower/UnitPowerMax straight to StatusBar", function()
	local c = CreateEnv({ inCombat = true })
	local ui = c.ns:GetModule("UI")
	c.SetCombat(true)
	ui:Refresh()

	Assert(ui.manaBar ~= nil, "UI should create a manaBar StatusBar")
	AssertEq(ui.manaBar:IsShown(), true, "manaBar should be shown in combat")
	Assert(c.env.issecretvalue(ui.manaBar._val), "manaBar should accept raw secret UnitPower without Lua arithmetic")
	Assert(c.env.issecretvalue(ui.manaBar._max), "manaBar should accept raw secret UnitPowerMax without Lua arithmetic")
	AssertEq(c.ns.db.lastError, nil, "Secret-safe mana bar must produce zero errors")
end)

Test("19. Proc detection via SPELL_ACTIVATION_OVERLAY_GLOW_SHOW bumps spell to top with PROC! status", function()
	local c = CreateEnv({
		playerLevel = 40,
		targetType = "Humanoid",
		knownSpells = {
			["Judgement"] = 20271,
			["Holy Strike"] = 678,
			["Exorcism"] = 879,
			["Seal of Righteousness"] = 20288,
		},
		usableSpells = {
			["Judgement"] = true,
			["Holy Strike"] = true,
			["Exorcism"] = true,
			["Seal of Righteousness"] = true,
		},
	})
	c.SetCombat(true)
	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "s1", 20288)
	c.Advance(1.6)
	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "j1", 20271) -- Judgement on CD

	-- Exorcism procs via Blizzard SpellActivationOverlay glow
	c.Fire("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 879)

	local tracker = c.ns:GetModule("CombatTracker")
	AssertEq(tracker:IsSpellGlowing("Exorcism"), true, "Exorcism should be tracked as glowing")

	local pq = c.ns:GetModule("PriorityQueue")
	local cur = pq:Evaluate()
	AssertEq(cur, "Exorcism", "Glowing proc spell should take priority over Holy Strike")
	AssertEq(pq.currentIsProc, true, "PriorityQueue should flag currentIsProc=true")

	local ui = c.ns:GetModule("UI")
	ui:Refresh()
	AssertEq(ui.status:GetText(), "PROC!", "HUD status should show PROC!")

	c.Fire("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", 879)
	AssertEq(tracker:IsSpellGlowing("Exorcism"), false, "Glow hide should clear proc state")
end)

Test("20. Auto-AoE senses >= 2 hostile melee nameplates and switches to Consecration automatically", function()
	local c = CreateEnv({
		playerLevel = 30,
		knownSpells = {
			["Judgement"] = 20271,
			["Holy Strike"] = 678,
			["Consecration"] = 26573,
			["Seal of Righteousness"] = 20288,
		},
		usableSpells = {
			["Judgement"] = true,
			["Holy Strike"] = true,
			["Consecration"] = true,
			["Seal of Righteousness"] = true,
		},
		nameplates = {
			{ unit = "nameplate1", hostile = true, inCombat = true, inRange = true },
			{ unit = "nameplate2", hostile = true, inCombat = true, inRange = true },
		},
	})
	c.SetCombat(true)
	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "s1", 20288)
	c.Advance(1.6)
	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "j1", 20271) -- Judgement on CD

	local tracker = c.ns:GetModule("CombatTracker")
	AssertEq(tracker:GetMeleeEnemyCount(), 2, "Should count 2 hostile in-combat melee nameplates")

	-- Manual aoe is OFF, but autoAoe is ON by default -> Consecration should outrank Holy Strike
	AssertEq(c.ns.db.aoe, false, "Manual aoe flag is off")
	local pq = c.ns:GetModule("PriorityQueue")
	AssertEq(pq:Evaluate(), "Consecration", "Auto-AoE should recommend Consecration with 2+ melee enemies")

	-- Drop down to 1 enemy -> returns to single-target Holy Strike
	c.SetNameplates({ { unit = "nameplate1", hostile = true, inCombat = true, inRange = true } })
	c.Advance(0.3)
	AssertEq(tracker:GetMeleeEnemyCount(), 1, "Should update to 1 melee enemy")
	AssertEq(pq:Evaluate(), "Holy Strike", "Should return to Holy Strike with 1 enemy")
end)

Test("21. Interrupt sensing recommends Hammer of Justice when target casts an interruptible spell", function()
	local c = CreateEnv({
		playerLevel = 20,
		knownSpells = {
			["Judgement"] = 20271,
			["Holy Strike"] = 678,
			["Hammer of Justice"] = 853,
			["Seal of Righteousness"] = 20288,
		},
		usableSpells = {
			["Judgement"] = true,
			["Holy Strike"] = true,
			["Hammer of Justice"] = true,
			["Seal of Righteousness"] = true,
		},
		inRangeSpells = {
			["Judgement"] = true,
			["Holy Strike"] = true,
			["Hammer of Justice"] = true,
		},
	})
	c.SetCombat(true)
	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "s1", 20288)
	c.Advance(1.6)

	-- Target starts casting an interruptible spell
	c.SetTargetCasting("Fireball", false)
	c.Fire("UNIT_SPELLCAST_START", "target", "e1", 133)

	local pq = c.ns:GetModule("PriorityQueue")
	local cur = pq:Evaluate()
	AssertEq(cur, "Hammer of Justice", "Should recommend Hammer of Justice to interrupt enemy cast")
	AssertEq(pq.currentIsInterrupt, true, "PriorityQueue should flag currentIsInterrupt=true")

	local ui = c.ns:GetModule("UI")
	ui:Refresh()
	AssertEq(ui.status:GetText(), "INTERRUPT", "HUD status should show INTERRUPT")

	-- Cast stops -> returns to normal rotation (Judgement)
	c.SetTargetCasting(nil, false)
	c.Fire("UNIT_SPELLCAST_STOP", "target", "e1", 133)
	AssertEq(pq:Evaluate(), "Judgement", "Should return to Judgement once enemy cast stops")
end)

Test("22. Boss/Elite opener recommends Seal of the Crusader -> Judgement once per target, skipped on normal mobs", function()
	local c = CreateEnv({
		playerLevel = 60,
		targetClassification = "worldboss",
		knownSpells = {
			["Judgement"] = 20271,
			["Holy Strike"] = 678,
			["Seal of Righteousness"] = 20288,
			["Seal of the Crusader"] = 21082,
		},
		usableSpells = {
			["Judgement"] = true,
			["Holy Strike"] = true,
			["Seal of Righteousness"] = true,
			["Seal of the Crusader"] = true,
		},
	})
	c.SetCombat(true)
	local pq = c.ns:GetModule("PriorityQueue")

	-- On worldboss with no Crusader judged yet: recommend Seal of the Crusader
	AssertEq(pq:Evaluate(), "Seal of the Crusader", "Should open with Seal of the Crusader on boss")

	-- Cast Seal of the Crusader -> next recommend Judgement
	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "sc1", 21082)
	c.Advance(1.6)
	AssertEq(pq:Evaluate(), "Judgement", "Should Judge Seal of the Crusader on boss")

	-- Cast Judgement -> Crusader debuff is now tracked as active on this boss; swap to normal primary seal!
	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "j1", 20271)
	AssertEq(pq:Evaluate(), "Seal of Righteousness", "After judging Crusader, should switch to primary DPS seal")

	-- Normal mob: never recommends Seal of the Crusader
	c.SetTargetClassification("normal")
	c.Fire("PLAYER_TARGET_CHANGED")
	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "clear", 20288)
	c.Advance(1.6)
	local curNormal = pq:Evaluate()
	Assert(curNormal ~= "Seal of the Crusader", "Must not recommend Seal of the Crusader on normal mobs")
end)

Test("23. Missing seal during active GCD previews primary seal instead of flashing long spell CD", function()
	local c = CreateEnv({
		playerLevel = 21,
		knownSpells = {
			["Judgement"] = 20271,
			["Holy Strike"] = 678,
			["Seal of Righteousness"] = 20288,
		},
		usableSpells = {
			["Judgement"] = false, -- no seal up
			["Holy Strike"] = true,
			["Seal of Righteousness"] = true,
		},
	})
	c.SetCombat(true)
	-- Cast Holy Strike while no seal is active -> GCD is active (~1.5s), HS is on 10s CD
	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "hs1", 678)
	c.Advance(0.5) -- 1.0s left on GCD

	local pq = c.ns:GetModule("PriorityQueue")
	local cur = pq:Evaluate()
	AssertEq(cur, "Seal of Righteousness", "During GCD with no seal up, must preview primary seal instead of Holy Strike")
	Assert(pq.countdown and pq.countdown <= 1.1, "Countdown should reflect remaining GCD (~1.0s), got: " .. tostring(pq.countdown))
end)

Test("24. TalentAdvisor computes exact next talent and 51-point targets for DPS and Leveling presets", function()
	local c = CreateEnv({})
	local talents = c.ns:GetModule("Talents")
	Assert(talents ~= nil, "Talents module should exist")

	-- Fresh character (0 points): DPS preset starts with Benediction, Leveling starts with Deflection
	local planDps = talents:ComputePlan({}, "dps")
	AssertEq(planDps.totalPoints, 51, "DPS build should have exactly 51 points")
	AssertEq(planDps.nextTalent, "Benediction", "DPS build starts with Benediction")
	AssertEq(planDps.targets["Unsealed Wrath"], 1, "DPS build includes Unsealed Wrath (1/1)")
	AssertEq(planDps.targets["Seal of Command"], 1, "DPS build includes Seal of Command (1/1)")
	AssertEq(planDps.targets["Improved Seals"], 5, "DPS build includes Improved Seals (5/5)")

	-- After 5/5 Benediction and 1/2 Improved Judgement -> next must be Improved Judgement
	local planMid = talents:ComputePlan({ ["Benediction"] = 5, ["Improved Judgement"] = 1 }, "dps")
	AssertEq(planMid.nextTalent, "Improved Judgement", "Should recommend 2nd rank of Improved Judgement")
	AssertEq(planMid.investedInBuild, 6, "Should count 6 invested points")

	-- Leveling preset starts with Deflection
	local planLvl = talents:ComputePlan({}, "leveling")
	AssertEq(planLvl.totalPoints, 51, "Leveling build should have exactly 51 points")
	AssertEq(planLvl.nextTalent, "Deflection", "Leveling build starts with Deflection")
end)

Test("25. TalentAdvisor attaches RP NEXT badge on PlayerSpellsFrame.TalentsFrame without overlapping Zygor", function()
	local c = CreateEnv({})
	local talents = c.ns:GetModule("Talents")

	local btnBenediction = c.MakeFrame("Button")
	btnBenediction.nodeInfo = { ranksPurchased = 0, maxRanks = 5, entryIDs = { 101 } }
	btnBenediction.CanAfford = function() return true end

	local btnJudgement = c.MakeFrame("Button")
	btnJudgement.nodeInfo = { ranksPurchased = 0, maxRanks = 2, entryIDs = { 102 } }
	btnJudgement.CanAfford = function() return false end

	local btnPursuit = c.MakeFrame("Button")
	btnPursuit.nodeInfo = { ranksPurchased = 2, maxRanks = 2, entryIDs = { 103 } }
	btnPursuit.CanAfford = function() return false end

	local talentsFrame = c.MakeFrame("Frame")
	talentsFrame._shown = true
	talentsFrame.IsVisible = function() return true end
	talentsFrame.configurationInfo = { ID = 1 }
	talentsFrame.nodeIDToButton = { [1] = btnBenediction, [2] = btnJudgement, [3] = btnPursuit }
	c.env.PlayerSpellsFrame = { TalentsFrame = talentsFrame }

	c.env.C_Traits = {
		GetEntryInfo = function(_, entryID) return { definitionID = entryID } end,
		GetDefinitionInfo = function(defID)
			if defID == 101 then return { spellID = 9001 } end
			if defID == 102 then return { spellID = 9002 } end
			return { spellID = 9003 }
		end,
	}
	local origGetSpellInfo = c.env.C_Spell.GetSpellInfo
	c.env.C_Spell.GetSpellInfo = function(id)
		if id == 9001 then return { name = "Benediction" } end
		if id == 9002 then return { name = "Improved Judgement" } end
		if id == 9003 then return { name = "Pursuit of Justice" } end
		return origGetSpellInfo(id)
	end

	talents:RefreshOverlay()
	local overlayNext = talents.activeOverlays["Benediction"]
	local overlayPlanned = talents.activeOverlays["Improved Judgement"]
	local overlayDone = talents.activeOverlays["Pursuit of Justice"]

	Assert(overlayNext ~= nil, "Should attach RP overlay to next recommended talent")
	AssertEq(overlayNext.badgeText:GetText(), "RP NEXT", "Next talent badge must be clearly branded 'RP NEXT'")
	Assert(overlayPlanned ~= nil, "Should attach RP overlay to future planned talent")
	AssertEq(overlayPlanned.badgeText:GetText(), "RP 0/2", "Planned talent badge must show 'RP 0/2'")
	Assert(overlayDone ~= nil, "Should attach RP checkmark overlay to completed talent in build")
	Assert(overlayDone.badgeText:GetText():find("ReadyCheck%-Ready") ~= nil, "Completed badge must render WoW native checkmark icon")
end)

Test("25b. TalentAdvisor overlays stay parented under TalentsFrame (not UIParent) so badges stay visible", function()
	-- Regression guard for 3681140: parenting badges to UIParent puts them behind
	-- PlayerSpellsFrame, so leveling/DPS recommendations vanish even though the plan
	-- still computes correctly.
	local c = CreateEnv({})
	local talents = c.ns:GetModule("Talents")

	local btnBenediction = c.MakeFrame("Button")
	btnBenediction.nodeInfo = { ranksPurchased = 0, maxRanks = 5, entryIDs = { 101 } }
	btnBenediction._level = 120

	local talentsFrame = c.MakeFrame("Frame")
	talentsFrame._shown = true
	talentsFrame._level = 100
	talentsFrame.IsVisible = function() return true end
	talentsFrame.configurationInfo = { ID = 1 }
	talentsFrame.nodeIDToButton = { [1] = btnBenediction }
	c.env.PlayerSpellsFrame = { TalentsFrame = talentsFrame }

	c.env.C_Traits = {
		GetEntryInfo = function(_, entryID) return { definitionID = entryID } end,
		GetDefinitionInfo = function() return { spellID = 9001 } end,
	}
	c.env.C_Spell.GetSpellInfo = function(id)
		if id == 9001 then return { name = "Benediction" } end
		return nil
	end

	talents:RefreshOverlay()
	Assert(talents.overlayRoot ~= nil, "Overlay root must exist after refresh")
	AssertEq(talents.overlayRoot:GetParent(), talentsFrame, "Overlay root must be parented to TalentsFrame, not UIParent")
	Assert(talents.overlayRoot ~= c.env.UIParent, "Overlay root must not be UIParent itself")
	Assert(talents.activeOverlays["Benediction"] ~= nil, "RP NEXT badge must still attach")
	AssertEq(talents.activeOverlays["Benediction"]:GetParent(), talents.overlayRoot, "Badge frames live under the TalentsFrame overlay root")
end)

Test("26. Passive out-of-combat seal display dims icon and shows 'Active' status", function()
	local c = CreateEnv({
		inCombat = false,
		targetExists = false,
		knownSpells = {
			["Seal of Righteousness"] = 20288,
			["Judgement"] = 20271,
			["Holy Strike"] = 678,
		},
		usableSpells = {
			["Seal of Righteousness"] = true,
			["Judgement"] = true,
			["Holy Strike"] = true,
		},
	})
	c.ns.db.visibility = "always"
	c.SetPlayerAuras({ { name = "Seal of Righteousness", spellId = 20288, sourceUnit = "player", expirationTime = 1000 + 30 * 60 } })
	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "s1", 20288)
	c.Advance(5.0)

	local ui = c.ns:GetModule("UI")
	ui:Refresh()

	Assert(ui.status:GetText():find("^Active") ~= nil, "Passive seal status should start with 'Active', got: " .. tostring(ui.status:GetText()))
	Assert(ui.mainIcon:GetAlpha() < 0.7, "Passive seal icon should be dimmed to distinguish from cast prompts")
end)

Test("27. Missing Blessing reminder surfaces Blessing of Kings out of combat and clears when buffed", function()
	local c = CreateEnv({
		inCombat = false,
		targetExists = false,
		knownSpells = {
			["Blessing of Kings"] = 20217,
			["Blessing of Might"] = 19834,
			["Seal of Righteousness"] = 20288,
		},
		usableSpells = {
			["Blessing of Kings"] = true,
			["Blessing of Might"] = true,
			["Seal of Righteousness"] = true,
		},
		playerAuras = {},
	})
	local tracker = c.ns:GetModule("CombatTracker")
	local ui = c.ns:GetModule("UI")

	-- No blessing active out of combat -> suggests Blessing of Kings and shows HUD
	AssertEq(tracker:GetMissingBlessing(), "Blessing of Kings", "Auto mode should prefer Blessing of Kings over Might")
	ui:Refresh()
	AssertEq(ui.frame:IsShown(), true, "HUD should reveal out of combat when a Blessing is missing")
	AssertEq(ui.label:GetText(), "Blessing of Kings", "HUD should show Blessing of Kings")
	AssertEq(ui.status:GetText(), "BUFF MISSING", "HUD status should show BUFF MISSING")

	-- Buff applied by player -> reminder clears and HUD fades out
	c.SetPlayerAuras({ { name = "Blessing of Kings", spellId = 20217, sourceUnit = "player", expirationTime = 4600 } })
	c.Fire("UNIT_AURA", "player")
	AssertEq(tracker:GetMissingBlessing(), nil, "Missing blessing should clear once Blessing of Kings is active")
	ui:Refresh()
	ui:StepFade(1.0)
	AssertEq(ui.frame:IsShown(), false, "HUD should hide again once Blessing is active in combat-only mode")
end)

Test("28. Missing Paladin Aura reminder surfaces Retribution Aura out of combat and clears when any Aura is up", function()
	local c = CreateEnv({
		inCombat = false,
		targetExists = false,
		knownSpells = {
			["Retribution Aura"] = 7294,
			["Devotion Aura"] = 465,
			["Blessing of Kings"] = 20217,
		},
		usableSpells = {
			["Retribution Aura"] = true,
			["Devotion Aura"] = true,
			["Blessing of Kings"] = true,
		},
		playerAuras = {
			{ name = "Blessing of Kings", spellId = 20217, sourceUnit = "player", expirationTime = 4600 },
		},
	})
	local tracker = c.ns:GetModule("CombatTracker")
	local ui = c.ns:GetModule("UI")

	-- Blessing is up, but NO Aura -> suggests Retribution Aura with AURA MISSING
	AssertEq(tracker:GetMissingAura(), "Retribution Aura", "Should recommend Retribution Aura when no Aura is active")
	ui:Refresh()
	AssertEq(ui.frame:IsShown(), true, "HUD should reveal out of combat when Paladin Aura is missing")
	AssertEq(ui.label:GetText(), "Retribution Aura", "HUD should show Retribution Aura")
	AssertEq(ui.status:GetText(), "AURA MISSING", "HUD status should show AURA MISSING")

	-- Any Aura active (e.g. Devotion Aura) -> reminder clears
	c.SetPlayerAuras({
		{ name = "Blessing of Kings", spellId = 20217, sourceUnit = "player", expirationTime = 4600 },
		{ name = "Devotion Aura", spellId = 465, sourceUnit = "player", expirationTime = 0 },
	})
	c.Fire("UNIT_AURA", "player")
	AssertEq(tracker:GetMissingAura(), nil, "Any active Paladin Aura should satisfy the reminder")
	ui:Refresh()
	ui:StepFade(1.0)
	AssertEq(ui.frame:IsShown(), false, "HUD should hide once both Blessing and Aura are active")
end)

Test("29. Another Paladin's Blessing of Wisdom does not suppress your own Blessing reminder", function()
	local c = CreateEnv({
		inCombat = false,
		targetExists = false,
		knownSpells = {
			["Blessing of Kings"] = 20217,
			["Blessing of Might"] = 19834,
			["Blessing of Wisdom"] = 19850,
		},
		usableSpells = {
			["Blessing of Kings"] = true,
			["Blessing of Might"] = true,
			["Blessing of Wisdom"] = true,
		},
		playerAuras = {
			-- Buffed by another Paladin, NOT by player!
			{ name = "Blessing of Wisdom", spellId = 19850, sourceUnit = "party1", expirationTime = 4600 },
		},
	})
	local tracker = c.ns:GetModule("CombatTracker")
	AssertEq(tracker:GetMissingBlessing(), "Blessing of Kings", "Should still suggest your own Blessing (Kings) when only another Paladin's Wisdom is up")

	-- If another Paladin gave Kings, suggest Might instead (don't overwrite Kings!)
	c.SetPlayerAuras({
		{ name = "Blessing of Kings", spellId = 20217, sourceUnit = "party1", expirationTime = 4600 },
	})
	c.Fire("UNIT_AURA", "player")
	AssertEq(tracker:GetMissingBlessing(), "Blessing of Might", "Should skip Kings from another Paladin and suggest Might")

	-- Once player casts their own Might -> reminder clears
	c.SetPlayerAuras({
		{ name = "Blessing of Kings", spellId = 20217, sourceUnit = "party1", expirationTime = 4600 },
		{ name = "Blessing of Might", spellId = 19834, sourceUnit = "player", expirationTime = 4600 },
	})
	c.Fire("UNIT_AURA", "player")
	AssertEq(tracker:GetMissingBlessing(), nil, "Reminder clears once player has their own Blessing active")
end)

Test("30. Another Paladin's Devotion Aura does not suppress your own Aura reminder", function()
	local c = CreateEnv({
		inCombat = false,
		targetExists = false,
		knownSpells = {
			["Retribution Aura"] = 7294,
			["Devotion Aura"] = 465,
			["Blessing of Kings"] = 20217,
		},
		usableSpells = {
			["Retribution Aura"] = true,
			["Devotion Aura"] = true,
			["Blessing of Kings"] = true,
		},
		playerAuras = {
			{ name = "Blessing of Kings", spellId = 20217, sourceUnit = "player", expirationTime = 4600 },
			-- Devotion Aura from another Paladin, player has NO Aura of their own!
			{ name = "Devotion Aura", spellId = 465, sourceUnit = "party1", expirationTime = 0 },
		},
	})
	local tracker = c.ns:GetModule("CombatTracker")
	AssertEq(tracker:GetMissingAura(), "Retribution Aura", "Another Paladin's Devotion Aura must not suppress your own Retribution Aura")

	-- If another Paladin already runs Retribution Aura, suggest Devotion Aura instead of duplicating
	c.SetPlayerAuras({
		{ name = "Blessing of Kings", spellId = 20217, sourceUnit = "player", expirationTime = 4600 },
		{ name = "Retribution Aura", spellId = 7294, sourceUnit = "party1", expirationTime = 0 },
	})
	c.Fire("UNIT_AURA", "player")
	AssertEq(tracker:GetMissingAura(), "Devotion Aura", "Should skip Retribution Aura from another Paladin and suggest Devotion Aura")

	-- Once player activates their own Aura -> reminder clears
	c.SetPlayerAuras({
		{ name = "Blessing of Kings", spellId = 20217, sourceUnit = "player", expirationTime = 4600 },
		{ name = "Retribution Aura", spellId = 7294, sourceUnit = "party1", expirationTime = 0 },
		{ name = "Devotion Aura", spellId = 465, sourceUnit = "player", expirationTime = 0 },
	})
	c.Fire("UNIT_AURA", "player")
	AssertEq(tracker:GetMissingAura(), nil, "Reminder clears once player has their own Aura active")
end)

Test("31. Always-visible mode softly fades HUD out of combat and restores full alpha on combat start", function()
	local c = CreateEnv({
		inCombat = false,
		targetExists = false,
		knownSpells = {
			["Blessing of Kings"] = 20217,
			["Retribution Aura"] = 7294,
			["Seal of Righteousness"] = 20288,
		},
		usableSpells = {
			["Blessing of Kings"] = true,
			["Retribution Aura"] = true,
			["Seal of Righteousness"] = true,
		},
		playerAuras = {
			{ name = "Blessing of Kings", spellId = 20217, sourceUnit = "player", expirationTime = 4600 },
			{ name = "Retribution Aura", spellId = 7294, sourceUnit = "player", expirationTime = 0 },
		},
	})
	c.ns.db.visibility = "always"
	local ui = c.ns:GetModule("UI")
	ui:Refresh()
	ui:StepFade(1.0)

	AssertEq(ui.frame:IsShown(), true, "HUD stays shown in always mode")
	Assert(ui.frame:GetAlpha() <= 0.45 and ui.frame:GetAlpha() >= 0.25,
		"Out-of-combat always-mode HUD should be softly faded (~0.38), got: " .. tostring(ui.frame:GetAlpha()))

	-- Entering combat immediately targets full opacity (1.0)
	c.SetCombat(true)
	ui:StepFade(1.0)
	AssertEq(ui.frame:GetAlpha(), 1, "HUD must return to full alpha (1.0) in combat")
end)

Test("32. Learned cooldowns persist in RetPulseDB and reset on talent or gear changes", function()
	local c1 = CreateEnv({
		knownSpells = { ["Judgement"] = 20271, ["Seal of Righteousness"] = 20288 },
		usableSpells = { ["Judgement"] = true, ["Seal of Righteousness"] = true },
	})
	c1.SetCombat(true)
	c1.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "j1", 20271)
	c1.Advance(8.0) -- Improved Judgement 2/2 -> 8s cooldown
	c1.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "j2", 20271)

	AssertEq(c1.ns.db.learnedCooldowns["Judgement"], 8.0, "Learned 8s Judgement CD should be stored in RetPulseDB")

	-- Simulate /reload with the same SavedVariables
	local c2 = CreateEnv({
		savedDB = c1.ns.db,
		knownSpells = { ["Judgement"] = 20271, ["Seal of Righteousness"] = 20288 },
		usableSpells = { ["Judgement"] = true, ["Seal of Righteousness"] = true },
	})
	local pq2 = c2.ns:GetModule("PriorityQueue")
	c2.SetCombat(true)
	c2.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "j3", 20271)
	AssertEq(pq2.cdDuration["Judgement"], 8.0, "Persisted 8s CD should apply immediately on first cast after /reload")

	-- Gear swap (e.g. unequipping a set bonus) resets learned cooldowns
	c2.Fire("PLAYER_EQUIPMENT_CHANGED")
	AssertEq(c2.ns.db.learnedCooldowns["Judgement"], nil, "Equipment change should clear learned cooldowns")
end)

Test("33. WeaponEngine strips melee haste to classify base weapon speed (e.g. 3.30s sword under 15% Warchief's Blessing)", function()
	local c = CreateEnv({
		weaponSpeed = 3.30 / 1.15, -- ~2.8696s hasted attack speed
		meleeHaste = 15,
		knownSpells = {
			["Judgement"] = 20271,
			["Seal of Righteousness"] = 20288,
			["Seal of Command"] = 20375,
		},
		usableSpells = {
			["Judgement"] = true,
			["Seal of Righteousness"] = true,
			["Seal of Command"] = true,
		},
	})
	local engine = c.ns:GetModule("WeaponEngine")
	AssertEq(engine.weaponSpeed, 3.3, "Base weapon speed should be restored to 3.30s despite 15% melee haste")
	AssertEq(engine:GetBracket(), "slow", "3.30s weapon under Warchief's Blessing must stay in slow bracket")
	local rot = engine:GetRotation()
	AssertEq(rot.primary, "Seal of Command", "Slow 3.30s weapon with SoC talent must recommend Seal of Command")
end)

Test("34. Seal swap makes the first swing the detonation swing (swingsWithSeal 3+1, not 3+2)", function()
	local c = CreateEnv({})
	c.ns.db.twistWithoutTalent = true
	local tracker = c.ns:GetModule("CombatTracker")

	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "a", 20288) -- Righteousness
	tracker:CountEcho()
	tracker:CountEcho()
	tracker:CountEcho()
	AssertEq(tracker.swingsWithSeal, 3, "Three swings in the primary seal")

	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "b", 1311656) -- Fury
	AssertEq(tracker.swingsWithSeal, 0, "Casting a new seal resets the swing count before the detonation")

	tracker:CountEcho()
	AssertEq(tracker.swingsWithSeal, 1, "The detonation swing is the first swing with the new seal")
	AssertEq(tracker.echoes, 1, "Detonation consumes the old echoes; the swing itself starts a new one")
end)

Test("35. ConfirmSwing credits the seal that was active when the swing happened", function()
	local c = CreateEnv({})
	c.ns.db.twistWithoutTalent = true
	local tracker = c.ns:GetModule("CombatTracker")

	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "a", 1311656) -- Fury
	tracker:CountEcho()
	tracker:CountEcho()
	AssertEq(tracker.echoes, 2, "Two echoes built under Fury")
	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "b", 20288) -- back to Righteousness
	tracker:CountEcho("Seal of Fury") -- late confirmation of a swing made under Fury
	AssertEq(tracker.echoes, 3, "A late swing under Fury must not be judged against the new seal")
end)

Test("36. Learned cooldown never inflates from a delayed cast", function()
	local c = CreateEnv({
		knownSpells = { ["Judgement"] = 20271, ["Seal of Righteousness"] = 20288 },
		usableSpells = { ["Judgement"] = true, ["Seal of Righteousness"] = true },
	})
	c.SetCombat(true)
	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "j1", 20271)
	c.Advance(8.0)
	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "j2", 20271)
	c.Advance(9.5)
	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "j3", 20271)
	AssertEq(c.ns.db.learnedCooldowns["Judgement"], 8.0, "A 9.5s delayed cast must not raise the learned 8s cooldown")
end)

Test("37. Off-GCD casts do not start a false global cooldown", function()
	local c = CreateEnv({
		knownSpells = { ["Holy Strike"] = 678, ["Avenging Wrath"] = 31884, ["Seal of Righteousness"] = 20288 },
	})
	local pq = c.ns:GetModule("PriorityQueue")
	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "w", 31884)
	AssertEq(pq.gcdUntil, nil, "Avenging Wrath is off the global cooldown")
	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "h", 678)
	Assert(pq.gcdUntil ~= nil, "Holy Strike spends the global cooldown")
end)

Test("38. Click-to-cast arms the secure button out of combat only, and not while unlocked", function()
	local c = CreateEnv({ inCombat = false, targetExists = false })
	local ui = c.ns:GetModule("UI")
	AssertEq(ui.clickBtn ~= nil, true, "Secure click button must exist")

	local attrs = {}
	ui.clickBtn.SetAttribute = function(_, k, v) attrs[k] = v end

	c.ns.db.locked = true
	ui:UpdateClickCast("Blessing of Kings")
	AssertEq(attrs.type, "spell", "Out of combat the button casts a spell")
	AssertEq(attrs.spell, "Blessing of Kings", "Out of combat the button targets the recommended spell")

	c.SetCombat(true)
	ui:UpdateClickCast("Holy Strike")
	AssertEq(attrs.spell, "Blessing of Kings", "Attributes must never change in combat")

	c.SetCombat(false)
	c.ns.db.locked = false
	ui:UpdateClickCast("Holy Strike")
	AssertEq(attrs.spell, "Holy Strike", "A click casts even while unlocked; dragging still moves the HUD")

	c.ns.db.locked = true
	c.ns.db.clickToCast = false
	ui:UpdateClickCast("Holy Strike")
	AssertEq(attrs.type, nil, "Disabled option must clear the button")
end)

Test("39. Auto-AoE detects 2+ melee enemies via Blizzard unitToken and NAME_PLATE_UNIT_ADDED", function()
	local plates = {
		{ unitToken = "nameplate1", IsForbidden = function() return false end },
		{ unitToken = "nameplate2", IsForbidden = function() return false end },
	}
	local c = CreateEnv({
		inCombat = true,
		knownSpells = {
			["Judgement"] = 20271,
			["Holy Strike"] = 678,
			["Consecration"] = 26573,
			["Seal of Righteousness"] = 20288,
		},
		usableSpells = {
			["Judgement"] = true,
			["Holy Strike"] = true,
			["Consecration"] = true,
			["Seal of Righteousness"] = true,
		},
		nameplates = {
			{ unit = "nameplate1", hostile = true, inCombat = true, inRange = true },
			{ unit = "nameplate2", hostile = true, inCombat = true, inRange = true },
			{ unit = "nameplate3", hostile = true, inCombat = true, inRange = true },
			{ unit = "nameplate4", hostile = true, inCombat = true, inRange = true },
		},
	})
	c.env.C_NamePlate.GetNamePlates = function() return plates end
	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "s1", 20288)
	c.Advance(2.0)

	local pq = c.ns:GetModule("PriorityQueue")
	pq.cdUntil["Judgement"] = c.env.GetTime() + 5.0
	local cur = pq:Evaluate()
	AssertEq(cur, "Consecration", "2+ enemies on plate.unitToken must trigger Consecration")

	-- Also works via NAME_PLATE_UNIT_ADDED/REMOVED even if GetNamePlates is empty
	plates = {}
	c.Advance(0.5)
	c.Fire("NAME_PLATE_UNIT_ADDED", "nameplate3")
	c.Fire("NAME_PLATE_UNIT_ADDED", "nameplate4")
	cur = pq:Evaluate()
	AssertEq(cur, "Consecration", "NAME_PLATE_UNIT_ADDED must trigger Consecration")

	c.Fire("NAME_PLATE_UNIT_REMOVED", "nameplate4")
	c.Advance(0.5)
	cur = pq:Evaluate()
	AssertEq(cur, "Holy Strike", "Removing a nameplate below 2 enemies must return to Holy Strike")
end)

Test("40. WeaponEngine ignores Seal of the Crusader +40% swing speed distortion", function()
	local c = CreateEnv({
		weaponSpeed = 3.30,
		knownSpells = {
			["Judgement"] = 20271,
			["Seal of Righteousness"] = 20288,
			["Seal of Command"] = 20375,
			["Seal of the Crusader"] = 21082,
		},
		usableSpells = {
			["Judgement"] = true,
			["Seal of Righteousness"] = true,
			["Seal of Command"] = true,
			["Seal of the Crusader"] = true,
		},
	})
	local engine = c.ns:GetModule("WeaponEngine")
	AssertEq(engine.weaponSpeed, 3.3, "Initial base speed is 3.30s")

	-- Casting Seal of the Crusader speeds swings by 40% (3.30 / 1.40 = 2.36s),
	-- which must NOT downgrade the slow 3.30s weapon into the fast bracket.
	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "sc1", 21082)
	c.env.UnitAttackSpeed = function() return 3.30 / 1.40 end
	c.Fire("UNIT_ATTACK_SPEED", "player")
	AssertEq(engine.weaponSpeed, 3.3, "Known weaponSpeed must stay 3.30s while Seal of the Crusader is active")
	AssertEq(engine:GetBracket(), "slow", "3.30s weapon must remain slow under Seal of the Crusader")
end)

Test("41. Crusader opener fires once per pull in combat (not on every tab-target between elites)", function()
	local c = CreateEnv({
		targetClassification = "elite",
		knownSpells = {
			["Judgement"] = 20271,
			["Holy Strike"] = 678,
			["Seal of Righteousness"] = 20288,
			["Seal of the Crusader"] = 21082,
		},
		usableSpells = {
			["Judgement"] = true,
			["Holy Strike"] = true,
			["Seal of Righteousness"] = true,
			["Seal of the Crusader"] = true,
		},
	})
	c.SetCombat(true)
	local pq = c.ns:GetModule("PriorityQueue")

	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "sc1", 21082)
	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "j1", 20271)
	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "sr1", 20288)
	c.Advance(1.6)
	pq.cdUntil["Judgement"] = c.env.GetTime() + 5.0

	-- Tab-target to a second elite in the same dungeon pack: must NOT re-prompt Crusader
	c.Fire("PLAYER_TARGET_CHANGED")
	AssertEq(pq:Evaluate(), "Holy Strike", "Tab-targeting another elite in the same pull must not re-trigger Crusader opener")

	-- Combat ends -> next pull resets judgedCrusader
	c.SetCombat(false)
	c.Fire("PLAYER_REGEN_ENABLED")
	c.SetCombat(true)
	AssertEq(pq:Evaluate(), "Seal of the Crusader", "New pull after leaving combat resets Crusader opener")
end)

Test("42. Group buff advisor detects missing party/raid blessings by class and arms click-to-cast on unit", function()
	local partyAuras = {
		party1 = {}, -- Warrior with no buffs
		party2 = { { name = "Greater Blessing of Kings", spellId = 25898, sourceUnit = "party3", expirationTime = 4000 } }, -- Mage with Kings from another paladin
	}
	local partyClasses = { party1 = "WARRIOR", party2 = "MAGE" }
	local partyNames = { party1 = "Grom", party2 = "Jaina" }

	local c = CreateEnv({
		inCombat = false,
		targetExists = false,
		knownSpells = {
			["Blessing of Kings"] = 20217,
			["Blessing of Might"] = 19740,
			["Blessing of Wisdom"] = 19742,
			["Retribution Aura"] = 7294,
			["Seal of Righteousness"] = 20288,
		},
		playerAuras = {
			{ name = "Blessing of Kings", spellId = 20217, sourceUnit = "player", expirationTime = 4000 },
			{ name = "Retribution Aura", spellId = 7294, sourceUnit = "player", expirationTime = 0 },
		},
	})
	c.env.IsInGroup = function() return true end
	c.env.IsInRaid = function() return false end
	c.env.GetNumGroupMembers = function() return 3 end
	c.env.UnitExists = function(u)
		if u == "target" then return false end
		return partyAuras[u] ~= nil
	end
	c.env.UnitIsConnected = function() return true end
	c.env.UnitIsDeadOrGhost = function() return false end
	c.env.UnitIsUnit = function(a, b) return a == b end
	c.env.UnitClass = function(u)
		local cls = partyClasses[u] or "PALADIN"
		return cls, cls
	end
	c.env.UnitName = function(u) return partyNames[u] or u end
	c.env.UnitPowerType = function(u) return (partyClasses[u] == "MAGE") and 0 or 1 end
	c.env.C_Spell.IsSpellInRange = function(_, u) return u == "party1" or u == "party2" end
	c.env.C_UnitAuras.GetAuraDataByIndex = function(u, idx)
		if u == "player" then
			return (idx == 1 and { name = "Blessing of Kings", spellId = 20217, sourceUnit = "player", expirationTime = 4000 })
				or (idx == 2 and { name = "Retribution Aura", spellId = 7294, sourceUnit = "player", expirationTime = 0 })
				or nil
		end
		return partyAuras[u] and partyAuras[u][idx] or nil
	end

	local tracker = c.ns:GetModule("CombatTracker")
	tracker:RefreshSeal()

	local spell, unit, unitName = tracker:GetMissingGroupBlessing()
	AssertEq(spell, "Blessing of Kings", "Unbuffed party warrior should get Blessing of Kings")
	AssertEq(unit, "party1", "Target unit should be party1")
	AssertEq(unitName, "Grom", "Target name should be Grom")

	local ui = c.ns:GetModule("UI")
	local attrs = {}
	ui.clickBtn.SetAttribute = function(_, k, v) attrs[k] = v end
	ui:Refresh()
	AssertEq(attrs.spell, "Blessing of Kings", "Click-to-cast must arm Blessing of Kings")
	AssertEq(attrs.unit, "party1", "Click-to-cast must target party1")
	AssertEq(ui.status:GetText(), "BUFF: |cffc79c6eGrom|r", "HUD status must show class-colored buff target name")

	-- Buff party1 -> now party2 (Mage with Kings) should get Blessing of Wisdom
	partyAuras.party1 = { { name = "Blessing of Kings", spellId = 20217, sourceUnit = "player", expirationTime = 4000 } }
	spell, unit, unitName = tracker:GetMissingGroupBlessing()
	AssertEq(spell, "Blessing of Wisdom", "Mage with Kings from another paladin should get Blessing of Wisdom")
	AssertEq(unit, "party2", "Target unit should be party2")

	-- Buff party2 -> all party members covered, unit attribute clears
	partyAuras.party2[2] = { name = "Blessing of Wisdom", spellId = 19742, sourceUnit = "player", expirationTime = 4000 }
	spell = tracker:GetMissingGroupBlessing()
	AssertEq(spell, nil, "No missing group blessings once all members are buffed")
	ui:Refresh()
	AssertEq(attrs.unit, nil, "Click-to-cast unit attribute must clear when no group buff is pending")
end)

Test("43. Click-to-cast button is not parented under main/frame so StepAnimations SetScale never taints in combat", function()
	local c = CreateEnv({ inCombat = false, targetExists = false })
	local ui = c.ns:GetModule("UI")
	Assert(ui.clickBtn ~= nil, "clickBtn must exist")
	Assert(ui.clickBtn:GetParent() == c.env.UIParent, "clickBtn must parent to UIParent so main:SetScale and frame:Show/Hide never become protected in combat")

	local mouseEnabled = true
	ui.clickBtn.EnableMouse = function(_, v) mouseEnabled = v end
	ui:UpdateClickCast(nil)
	AssertEq(mouseEnabled, false, "clickBtn must be click-through when no spell is armed")

	ui.frame:Show()
	ui:UpdateClickCast("Blessing of Kings")
	AssertEq(mouseEnabled, true, "clickBtn must accept clicks when HUD is shown and spell is armed out of combat")

	-- Spell pop animation must never call main:SetScale() in combat
	local scaled = false
	ui.main.SetScale = function() scaled = true end
	ui:TriggerSpellPop()
	ui:StepAnimations(0.05)
	AssertEq(scaled, false, "StepAnimations must not call main:SetScale() (uses SetTexCoord zoom)")
end)

Test("44. Mana-saving options: Auto-AoE threshold, Boss-only Crusader opener, and low-mana fallback", function()
	local c = CreateEnv({
		targetClassification = "elite",
		knownSpells = {
			["Judgement"] = 20271,
			["Holy Strike"] = 678,
			["Consecration"] = 26573,
			["Seal of Righteousness"] = 20288,
			["Seal of the Crusader"] = 21082,
		},
		usableSpells = {
			["Judgement"] = true,
			["Holy Strike"] = true,
			["Consecration"] = true,
			["Seal of Righteousness"] = true,
			["Seal of the Crusader"] = true,
		},
		nameplates = {
			{ unit = "nameplate1", hostile = true, inCombat = true, inRange = true },
			{ unit = "nameplate2", hostile = true, inCombat = true, inRange = true },
			{ unit = "nameplate3", hostile = true, inCombat = true, inRange = true },
		},
	})
	c.SetCombat(true)
	local pq = c.ns:GetModule("PriorityQueue")

	-- 1. Boss-only Crusader opener skips dungeon trash elites
	c.ns.db.crusaderBossOnly = true
	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "s1", 20288)
	c.Advance(1.6)
	pq.cdUntil["Judgement"] = c.env.GetTime() + 5.0
	c.ns.db.autoAoeThreshold = 3
	AssertEq(pq:Evaluate(), "Consecration", "3+ enemies meets threshold=3 and skips elite Crusader opener")

	-- 2. Raising threshold to 4 keeps Holy Strike on 3-mob pack
	c.ns.db.autoAoeThreshold = 4
	AssertEq(pq:Evaluate(), "Holy Strike", "3 enemies below threshold=4 must stay on Holy Strike to save mana")

	-- 3. Low-mana guard (insufficientPower on Consecration) skips expensive Crusader opener even on worldboss
	c.SetTargetClassification("worldboss")
	c.ns.db.crusaderBossOnly = false
	c.env.C_Spell.IsSpellUsable = function(name)
		if name == "Consecration" then return false, true end
		return (name == "Holy Strike" or name == "Judgement" or name == "Seal of Righteousness" or name == "Seal of the Crusader"), false
	end
	AssertEq(pq:Evaluate(), "Holy Strike", "When Consecration hits insufficientPower, skip Crusader opener and stay on core DPS")
end)

Test("45. /rp config opens the Settings panel via ns:OpenOptions", function()
	local openedCategoryID
	local c = CreateEnv({})
	c.env.Settings = {
		VarType = { Boolean = "boolean", String = "string", Number = "number" },
		RegisterVerticalLayoutCategory = function(name)
			local cat = { _id = 777, GetID = function(self) return self._id end }
			local layout = { AddInitializer = function() end }
			return cat, layout
		end,
		RegisterVerticalLayoutSubcategory = function(parent, name)
			local cat = { _id = 778, GetID = function(self) return self._id end }
			local layout = { AddInitializer = function() end }
			return cat, layout
		end,
		RegisterAddOnSetting = function()
			return { SetValueChangedCallback = function() end }
		end,
		CreateCheckbox = function() end,
		CreateDropdown = function() end,
		CreateControlTextContainer = function()
			return { Add = function() end, GetData = function() return {} end }
		end,
		CreateSliderOptions = function()
			return { SetLabelFormatter = function() end }
		end,
		CreateSlider = function() end,
		RegisterAddOnCategory = function() end,
		OpenToCategory = function(id) openedCategoryID = id end,
	}
	c.ns:GetModule("Config"):OnInitialize()
	Assert(c.ns.OpenOptions ~= nil, "Config must define ns:OpenOptions for /rp config")
	c.env.SlashCmdList.RETPULSE("config")
	AssertEq(openedCategoryID, 777, "/rp config must open the RetPulse Settings category")
end)

Test("46. Nameplate mode attaches compact icons to target nameplate, follows target switches, and falls back to HUD", function()
	local plateA = {
		IsForbidden = function() return false end,
		IsVisible = function() return true end,
		_points = {},
		SetPoint = function() end,
	}
	local plateB = {
		IsForbidden = function() return false end,
		IsVisible = function() return true end,
		_points = {},
		SetPoint = function() end,
	}
	local currentPlate = plateA

	local c = CreateEnv({
		inCombat = true,
		targetExists = true,
		targetHostile = true,
		knownSpells = {
			["Judgement"] = 20271,
			["Holy Strike"] = 678,
			["Seal of Righteousness"] = 20288,
		},
		usableSpells = {
			["Judgement"] = true,
			["Holy Strike"] = true,
			["Seal of Righteousness"] = true,
		},
	})
	c.env.C_NamePlate.GetNamePlateForUnit = function(unit)
		if unit == "target" then return currentPlate end
		return nil
	end
	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "s1", 20288)
	c.Advance(1.6)

	local ui = c.ns:GetModule("UI")
	c.ns.db.nameplateMode = true
	ui:Refresh()

	Assert(ui.npFrame ~= nil, "Compact nameplate frame must be created")
	AssertEq(ui.npFrame:IsShown(), true, "Compact nameplate frame must show when target nameplate is visible")
	AssertEq(ui.frame:IsShown(), false, "Classic HUD must hide while compact nameplate frame is active")
	AssertEq(ui.lastNpPlate, plateA, "Compact widget must attach to target plateA")

	-- Switching target moves compact widget automatically to plateB
	currentPlate = plateB
	c.Fire("PLAYER_TARGET_CHANGED")
	AssertEq(ui.lastNpPlate, plateB, "Switching target must move compact widget to new target nameplate")
	AssertEq(ui.npFrame:IsShown(), true, "Compact widget stays shown on new target")

	-- Adjusting nameplateOffsetX / Y updates the stored offsets immediately
	c.ns.db.nameplateOffsetX = 12
	c.ns.db.nameplateOffsetY = -6
	ui:Refresh()
	AssertEq(ui.lastNpOffsetX, 12, "Nameplate X offset slider value must apply immediately")
	AssertEq(ui.lastNpOffsetY, -6, "Nameplate Y offset slider value must apply immediately")

	-- No visible nameplate (e.g. off-screen or out of combat) -> falls back to classic HUD
	currentPlate = nil
	c.Fire("PLAYER_TARGET_CHANGED")
	AssertEq(ui.npFrame:IsShown(), false, "Compact widget hides when target has no visible nameplate")
	AssertEq(ui.frame:IsShown(), true, "Classic HUD returns as fallback in combat when nameplate is missing")
end)

Test("47. Optional Masque integration registers Nameplate Icons and HUD Icons groups when LibStub Masque is present", function()
	local added = {}
	local groups = {}
	local c = CreateEnv({})
	c.env.LibStub = function(name, silent)
		if name == "Masque" then
			return {
				Group = function(_, addon, groupName)
					local g = {
						AddButton = function(_, btn, data)
							added[groupName] = added[groupName] or {}
							added[groupName][#added[groupName] + 1] = { btn = btn, data = data }
						end,
					}
					groups[groupName] = g
					return g
				end,
			}
		end
		return nil
	end

	local ui = c.ns:GetModule("UI")
	ui:InitMasque()
	Assert(groups["Nameplate Icons"] ~= nil, "Masque must register 'Nameplate Icons' group")
	Assert(groups["HUD Icons"] ~= nil, "Masque must register 'HUD Icons' group")
	AssertEq(#added["Nameplate Icons"], 2, "Nameplate Icons group must register npMain and npNext")
	AssertEq(added["Nameplate Icons"][1].data.Icon, ui.npMainIcon, "npMainIcon passed to Masque")
	AssertEq(added["Nameplate Icons"][1].data.Cooldown, ui.npCooldown, "npCooldown passed to Masque")
	AssertEq(#added["HUD Icons"], 2, "HUD Icons group must register main and nextFrame")
end)

Test("48. Friendly non-party target gets optimal missing Blessing (skipping other Paladin buffs) and arms click-to-cast on target", function()
	local targetAuras = {
		{ name = "Blessing of Kings", spellId = 20217, sourceUnit = "other", expirationTime = 4000 },
	}
	local c = CreateEnv({
		inCombat = false,
		targetExists = true,
		targetHostile = false,
		knownSpells = {
			["Blessing of Kings"] = 20217,
			["Blessing of Might"] = 19740,
			["Blessing of Wisdom"] = 19742,
			["Retribution Aura"] = 7294,
			["Seal of Righteousness"] = 20288,
		},
		playerAuras = {
			{ name = "Blessing of Kings", spellId = 20217, sourceUnit = "player", expirationTime = 4000 },
			{ name = "Retribution Aura", spellId = 7294, sourceUnit = "player", expirationTime = 0 },
		},
	})
	c.env.IsInGroup = function() return false end
	c.env.UnitIsPlayer = function(u) return u == "target" end
	c.env.UnitIsFriend = function(_, u) return u == "target" end
	c.env.UnitIsConnected = function() return true end
	c.env.UnitIsDeadOrGhost = function() return false end
	c.env.UnitIsUnit = function(a, b) return a == b end
	c.env.UnitClass = function() return "Warrior", "WARRIOR" end
	c.env.UnitPowerType = function() return 1 end
	c.env.UnitName = function(u) return u == "target" and "Garrosh" or u end
	c.env.C_Spell.IsSpellInRange = function(_, u) return u == "target" end
	c.env.C_UnitAuras.GetAuraDataByIndex = function(u, idx)
		if u == "player" then
			return (idx == 1 and { name = "Blessing of Kings", spellId = 20217, sourceUnit = "player", expirationTime = 4000 })
				or (idx == 2 and { name = "Retribution Aura", spellId = 7294, sourceUnit = "player", expirationTime = 0 })
				or nil
		end
		if u == "target" then return targetAuras[idx] end
		return nil
	end

	local tracker = c.ns:GetModule("CombatTracker")
	tracker:RefreshSeal()

	-- Warrior already has Kings from another Paladin -> must suggest next best (Blessing of Might)
	local spell, unit, unitName = tracker:GetMissingTargetBlessing()
	AssertEq(spell, "Blessing of Might", "Friendly warrior with another Paladin's Kings must get Blessing of Might")
	AssertEq(unit, "target", "Target unit must be 'target'")
	AssertEq(unitName, "Garrosh", "Target name must be Garrosh")

	local ui = c.ns:GetModule("UI")
	local attrs = {}
	ui.clickBtn.SetAttribute = function(_, k, v) attrs[k] = v end
	ui:Refresh()
	AssertEq(attrs.spell, "Blessing of Might", "Click-to-cast must arm Blessing of Might")
	AssertEq(attrs.unit, "target", "Click-to-cast must target 'target'")
	AssertEq(ui.status:GetText(), "BUFF: |cffc79c6eGarrosh|r", "HUD status must show class-colored BUFF: Garrosh")

	-- Once player casts their own Blessing on target, no further buff is suggested
	targetAuras[2] = { name = "Blessing of Might", spellId = 19740, sourceUnit = "player", expirationTime = 4000 }
	AssertEq(tracker:GetMissingTargetBlessing(), nil, "Target with player's own Blessing must not be prompted again")
end)

Test("49. Facing alert triggers on UI_ERROR_MESSAGE and clears on swing, cast, target change, or timeout", function()
	local c = CreateEnv({
		inCombat = true,
		knownSpells = { ["Judgement"] = 20271, ["Holy Strike"] = 678, ["Seal of Righteousness"] = 20288 },
		usableSpells = { ["Judgement"] = true, ["Holy Strike"] = true, ["Seal of Righteousness"] = true },
	})
	local tracker = c.ns:GetModule("CombatTracker")
	local ui = c.ns:GetModule("UI")

	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "s1", 20288)
	c.Advance(1.6)
	AssertEq(tracker:IsNotFacing(), false, "Facing alert starts false")

	c.Fire("UI_ERROR_MESSAGE", 1, "You are facing the wrong way!")
	AssertEq(tracker:IsNotFacing(), true, "UI_ERROR_MESSAGE facing error activates alert")

	ui:Refresh()
	AssertEq(ui.status:GetText(), "FACE TARGET", "HUD status must show FACE TARGET")

	-- Also works on Nameplate mode (shows npFaceTag)
	local plate = { IsForbidden = function() return false end, IsVisible = function() return true end, SetPoint = function() end }
	c.env.C_NamePlate.GetNamePlateForUnit = function() return plate end
	c.ns.db.nameplateMode = true
	ui:Refresh()
	AssertEq(ui.npFaceTag:IsShown(), true, "Nameplate FACE! badge must show when not facing")

	-- A landed swing or successful cast clears the alert immediately
	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "j1", 20271)
	AssertEq(tracker:IsNotFacing(), false, "Successful cast clears facing alert")
	ui:Refresh()
	AssertEq(ui.npFaceTag:IsShown(), false, "Nameplate FACE! badge hides once facing is fixed")

	-- Timeout after 2s clears it too
	c.Fire("UI_ERROR_MESSAGE", 1, "Target needs to be in front of you.")
	AssertEq(tracker:IsNotFacing(), true, "Second facing error activates alert")
	c.Advance(2.1)
	AssertEq(tracker:IsNotFacing(), false, "Facing alert expires after 2 seconds")
end)

Test("50. Nameplate mode renders mini swing bar and 3 Echo pips when enabled", function()
	local plate = { IsForbidden = function() return false end, IsVisible = function() return true end, SetPoint = function() end }
	local c = CreateEnv({
		inCombat = true,
		knownSpells = { ["Judgement"] = 20271, ["Holy Strike"] = 678, ["Seal of Righteousness"] = 20288 },
		usableSpells = { ["Judgement"] = true, ["Holy Strike"] = true, ["Seal of Righteousness"] = true },
	})
	c.env.C_NamePlate.GetNamePlateForUnit = function() return plate end
	c.ns.db.nameplateMode = true
	c.ns.db.nameplateBars = true
	c.ns.db.twistWithoutTalent = true

	local tracker = c.ns:GetModule("CombatTracker")
	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "s1", 20288)
	c.Fire("PLAYER_SWING", 3.0, 0)
	tracker.echoes = 2
	c.Advance(1.5)

	local ui = c.ns:GetModule("UI")
	ui:Refresh()
	Assert(ui.npSwingBar ~= nil, "Nameplate swing bar must exist")
	AssertEq(ui.npSwingBar:IsShown(), true, "Nameplate swing bar must show in combat")
	Assert(ui.npPips ~= nil and #ui.npPips == 3, "Nameplate must have 3 echo pips")
	AssertEq(ui.npPips[1]:IsShown(), true, "Echo pips must show when Unsealed Wrath / twist is active")

	c.ns.db.nameplateBars = false
	ui:Refresh()
	AssertEq(ui.npSwingBar:IsShown(), false, "Disabling nameplateBars must hide nameplate swing bar")
	AssertEq(ui.npPips[1]:IsShown(), false, "Disabling nameplateBars must hide nameplate echo pips")
end)

Test("51. Early Blessing refresh (<60s) and Greater Blessing preference in raid", function()
	local now = 1000
	local c = CreateEnv({
		now = now,
		inCombat = false,
		targetExists = false,
		knownSpells = {
			["Blessing of Kings"] = 20217,
			["Greater Blessing of Kings"] = 25898,
			["Retribution Aura"] = 7294,
		},
		usableSpells = {
			["Blessing of Kings"] = true,
			["Greater Blessing of Kings"] = true,
			["Retribution Aura"] = true,
		},
		playerAuras = {
			{ name = "Blessing of Kings", spellId = 20217, sourceUnit = "player", expirationTime = now + 45 },
			{ name = "Retribution Aura", spellId = 7294, sourceUnit = "player", expirationTime = 0 },
		},
	})
	c.env.IsInRaid = function() return true end
	local tracker = c.ns:GetModule("CombatTracker")
	tracker:RefreshSeal()

	AssertEq(tracker:GetMissingBlessing(), "Greater Blessing of Kings", "Expiring blessing (<60s) in raid should suggest Greater Blessing")

	c.env.C_Spell.IsSpellUsable = function(name)
		if name == "Greater Blessing of Kings" then return false, false end
		return true, false
	end
	AssertEq(tracker:GetMissingBlessing(), "Blessing of Kings", "Unusable Greater Blessing falls back to regular Blessing")

	c.ns.db.buffRefreshEarly = false
	AssertEq(tracker:GetMissingBlessing(), nil, "Disabling buffRefreshEarly suppresses reminder while buff is still active")
end)

Test("52. Alert sounds fire once per rising edge for FACE!, INTERRUPT, and PROC!, and respect alertSounds=false", function()
	local played = {}
	local c = CreateEnv({
		inCombat = true,
		knownSpells = { ["Judgement"] = 20271, ["Holy Strike"] = 678, ["Hammer of Justice"] = 853, ["Seal of Righteousness"] = 20288 },
		usableSpells = { ["Judgement"] = true, ["Holy Strike"] = true, ["Hammer of Justice"] = true, ["Seal of Righteousness"] = true },
	})
	c.env.PlaySound = function(kit) played[#played + 1] = kit end
	c.env.SOUNDKIT.RAID_WARNING = 8959
	c.env.SOUNDKIT.READY_CHECK = 8960
	c.env.SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF = 857

	local ui = c.ns:GetModule("UI")
	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "s1", 20288)
	c.Advance(1.6)
	ui:Refresh()
	local before = #played

	c.Fire("UI_ERROR_MESSAGE", 1, "You are facing the wrong way!")
	ui:Refresh()
	ui:Refresh()
	AssertEq(#played, before + 1, "Facing alert sound must fire once per rising edge")

	c.ns.db.alertSounds = false
	c.SetTargetCasting("Fireball", false)
	c.Fire("UNIT_SPELLCAST_START", "target", "e1", 133)
	ui:Refresh()
	AssertEq(#played, before + 1, "alertSounds=false must suppress interrupt alert sound")
end)

Test("53. Out-of-combat Dispel reminder surfaces Cleanse/Purify for harmful debuffs and arms click-to-cast", function()
	local partyHarmful = {
		party1 = { { name = "Venom Spit", spellId = 6917, dispelName = "Poison" } },
	}
	local c = CreateEnv({
		inCombat = false,
		targetExists = false,
		knownSpells = {
			["Purify"] = 1152,
			["Blessing of Kings"] = 20217,
			["Retribution Aura"] = 7294,
		},
		playerAuras = {
			{ name = "Blessing of Kings", spellId = 20217, sourceUnit = "player", expirationTime = 4000 },
			{ name = "Retribution Aura", spellId = 7294, sourceUnit = "player", expirationTime = 0 },
		},
	})
	c.env.IsInGroup = function() return true end
	c.env.IsInRaid = function() return false end
	c.env.GetNumGroupMembers = function() return 2 end
	c.env.UnitExists = function(u) return u == "party1" end
	c.env.UnitIsConnected = function() return true end
	c.env.UnitIsDeadOrGhost = function() return false end
	c.env.UnitIsUnit = function(a, b) return a == b end
	c.env.UnitName = function(u) return u == "party1" and "Thrall" or u end
	c.env.UnitClass = function(u)
		if u == "party1" then return "Shaman", "SHAMAN" end
		return "Paladin", "PALADIN"
	end
	c.env.C_Spell.IsSpellInRange = function(_, u) return u == "party1" end
	c.env.C_UnitAuras.GetAuraDataByIndex = function(u, idx, filter)
		if filter == "HARMFUL" then
			return partyHarmful[u] and partyHarmful[u][idx] or nil
		end
		if u == "player" then
			return (idx == 1 and { name = "Blessing of Kings", spellId = 20217, sourceUnit = "player", expirationTime = 4000 })
				or (idx == 2 and { name = "Retribution Aura", spellId = 7294, sourceUnit = "player", expirationTime = 0 })
				or nil
		end
		return nil
	end

	local tracker = c.ns:GetModule("CombatTracker")
	tracker:RefreshSeal()
	local spell, unit, unitName = tracker:GetMissingDispel()
	AssertEq(spell, "Purify", "Poison on party1 should suggest Purify")
	AssertEq(unit, "party1", "Dispel target must be party1")
	AssertEq(unitName, "Thrall", "Dispel target name must be Thrall")

	local ui = c.ns:GetModule("UI")
	local attrs = {}
	ui.clickBtn.SetAttribute = function(_, k, v) attrs[k] = v end
	ui:Refresh()
	AssertEq(attrs.spell, "Purify", "Click-to-cast must arm Purify")
	AssertEq(attrs.unit, "party1", "Click-to-cast must target party1")
	AssertEq(ui.status:GetText(), "DISPEL: |cff0070deThrall|r", "HUD status must show class-colored DISPEL: Thrall")

	partyHarmful.party1 = { { name = "Polymorph", spellId = 118, dispelName = "Magic" } }
	AssertEq(tracker:GetMissingDispel(), nil, "Purify alone must not suggest dispelling Magic")
end)

Test("54. Righteous Fury anti-aggro warning triggers in group for DPS and stays silent for Tanks", function()
	local role = "DAMAGER"
	local c = CreateEnv({
		inCombat = false,
		targetExists = false,
		knownSpells = { ["Blessing of Kings"] = 20217, ["Retribution Aura"] = 7294 },
		playerAuras = {
			{ name = "Righteous Fury", spellId = 25780, sourceUnit = "player", expirationTime = 4000 },
			{ name = "Blessing of Kings", spellId = 20217, sourceUnit = "player", expirationTime = 4000 },
			{ name = "Retribution Aura", spellId = 7294, sourceUnit = "player", expirationTime = 0 },
		},
	})
	c.env.IsInGroup = function() return true end
	c.env.UnitGroupRolesAssigned = function() return role end

	local tracker = c.ns:GetModule("CombatTracker")
	tracker:RefreshSeal()
	AssertEq(tracker:GetThreatBuffWarning(), "Righteous Fury", "DPS in group with Righteous Fury must be warned")

	local ui = c.ns:GetModule("UI")
	ui:Refresh()
	AssertEq(ui.status:GetText(), "THREAT BUFF ON!", "HUD status must show THREAT BUFF ON!")

	role = "TANK"
	AssertEq(tracker:GetThreatBuffWarning(), nil, "Assigned Tank must not be warned about Righteous Fury")
end)

Test("55. Boss burst prompt recommends Avenging Wrath or ready on-use trinket on worldboss only", function()
	local c = CreateEnv({
		inCombat = true,
		targetClassification = "worldboss",
		knownSpells = {
			["Judgement"] = 20271,
			["Holy Strike"] = 678,
			["Seal of Righteousness"] = 20288,
			["Avenging Wrath"] = 31884,
		},
		usableSpells = {
			["Judgement"] = true,
			["Holy Strike"] = true,
			["Seal of Righteousness"] = true,
			["Avenging Wrath"] = true,
		},
	})
	c.ns.db.crusaderOnBoss = false
	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "s1", 20288)
	c.Advance(1.6)

	local pq = c.ns:GetModule("PriorityQueue")
	AssertEq(pq:Evaluate(), "Avenging Wrath", "Ready Avenging Wrath should surface as BURST! on worldboss")
	AssertEq(pq.currentIsBurst, true, "PriorityQueue must set currentIsBurst=true")

	c.SetTargetClassification("normal")
	AssertEq(pq:Evaluate(), "Judgement", "Burst cooldown must not be recommended on normal mobs")

	c.SetTargetClassification("worldboss")
	c.ns.db.suggestBurst = false
	AssertEq(pq:Evaluate(), "Judgement", "suggestBurst=false must disable Boss burst prompt")
end)

Test("56. PvE isolation: NPC targets never trigger PvP stun combo, Freedom, Repentance gap-close, or Seal of Justice", function()
	local c = CreateEnv({
		inCombat = true,
		targetClassification = "normal",
		knownSpells = {
			["Judgement"] = 20271,
			["Holy Strike"] = 678,
			["Hammer of Justice"] = 853,
			["Seal of Command"] = 20375,
			["Seal of Righteousness"] = 20288,
			["Blessing of Freedom"] = 1044,
			["Repentance"] = 20066,
			["Seal of Justice"] = 20164,
		},
		usableSpells = {
			["Judgement"] = true,
			["Holy Strike"] = true,
			["Hammer of Justice"] = true,
			["Seal of Command"] = true,
			["Seal of Righteousness"] = true,
			["Blessing of Freedom"] = true,
			["Repentance"] = true,
			["Seal of Justice"] = true,
		},
	})
	c.env.UnitIsPlayer = function() return false end
	c.env.GetUnitSpeed = function() return 3.5 end
	c.env.UnitClass = function(u) return u == "target" and "Druid" or "Paladin", u == "target" and "DRUID" or "PALADIN" end
	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "sc", 20375)
	c.Advance(1.6)

	local pq = c.ns:GetModule("PriorityQueue")
	AssertEq(pq:Evaluate(), "Judgement", "PvE target must go straight to Judgement, never HoJ stun combo or Freedom")
	AssertEq(pq.currentIsPvp, false, "PvE evaluation must keep currentIsPvp=false")
end)

Test("57. Low-level PvP: hostile player triggers Seal of Command, Stun Combo, and Blessing of Freedom", function()
	local swingRange = true
	local speed = 7.0
	local c = CreateEnv({
		playerLevel = 24,
		inCombat = true,
		swingInRange = true,
		knownSpells = {
			["Judgement"] = 20271,
			["Holy Strike"] = 678,
			["Hammer of Justice"] = 853,
			["Seal of Command"] = 20375,
			["Seal of Righteousness"] = 20288,
			["Blessing of Freedom"] = 1044,
		},
		usableSpells = {
			["Judgement"] = true,
			["Holy Strike"] = true,
			["Hammer of Justice"] = true,
			["Seal of Command"] = true,
			["Seal of Righteousness"] = true,
			["Blessing of Freedom"] = true,
		},
		inRangeSpells = {
			["Judgement"] = true,
			["Holy Strike"] = true,
			["Hammer of Justice"] = true,
		},
	})
	c.env.UnitIsPlayer = function(u) return u == "target" end
	c.env.GetUnitSpeed = function() return speed end
	c.env.C_SwingTimer.IsTargetWithinSwingRange = function() return swingRange end

	local pq = c.ns:GetModule("PriorityQueue")
	local cur, nxt = pq:Evaluate()
	AssertEq(cur, "Seal of Command", "PvP target with no seal must open with Seal of Command (skipping Crusader)")

	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "sc", 20375)
	c.Advance(1.6)
	cur, nxt = pq:Evaluate()
	AssertEq(cur, "Hammer of Justice", "HoJ + Judgement + SoC ready on hostile player must recommend STUN COMBO!")
	AssertEq(nxt, "Judgement", "NEXT must preview Judgement right after Hammer of Justice")
	AssertEq(pq.currentPvpLabel, "STUN COMBO!", "Status label must be STUN COMBO!")

	-- Slowed out of melee -> Blessing of Freedom!
	swingRange = false
	speed = 3.5
	c.Advance(0.2)
	cur = pq:Evaluate()
	AssertEq(cur, "Blessing of Freedom", "Slowed out of melee in PvP must prioritize Blessing of Freedom")
	AssertEq(pq.currentPvpLabel, "FREEDOM!", "Status label must be FREEDOM!")
end)

Test("58. Will of the Forsaken triggers BREAK CC! when C_LossOfControl reports active CC in PvP", function()
	local ccCount = 0
	local c = CreateEnv({
		inCombat = true,
		knownSpells = {
			["Will of the Forsaken"] = 7744,
			["Judgement"] = 20271,
			["Seal of Righteousness"] = 20288,
		},
		usableSpells = {
			["Will of the Forsaken"] = true,
			["Judgement"] = true,
			["Seal of Righteousness"] = true,
		},
	})
	c.env.UnitIsPlayer = function(u) return u == "target" end
	c.env.C_LossOfControl = {
		GetActiveLossOfControlDataCount = function() return ccCount end,
	}
	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "sr", 20288)
	c.Advance(1.6)

	local pq = c.ns:GetModule("PriorityQueue")
	AssertEq(pq:Evaluate(), "Judgement", "Without CC, Judgement runs normally")

	ccCount = 1
	AssertEq(pq:Evaluate(), "Will of the Forsaken", "Active CC in PvP must surface Will of the Forsaken")
	AssertEq(pq.currentPvpLabel, "BREAK CC!", "Status label must be BREAK CC!")
end)

Test("59. Repentance acts as GAP CLOSE out of melee and 2nd INTERRUPT when HoJ is on CD", function()
	local swingRange = false
	local c = CreateEnv({
		inCombat = true,
		swingInRange = false,
		knownSpells = {
			["Judgement"] = 20271,
			["Holy Strike"] = 678,
			["Hammer of Justice"] = 853,
			["Repentance"] = 20066,
			["Seal of Command"] = 20375,
		},
		usableSpells = {
			["Judgement"] = true,
			["Holy Strike"] = true,
			["Hammer of Justice"] = true,
			["Repentance"] = true,
			["Seal of Command"] = true,
		},
	})
	c.env.UnitIsPlayer = function(u) return u == "target" end
	c.env.C_SwingTimer.IsTargetWithinSwingRange = function() return swingRange end
	c.env.C_Spell.IsSpellInRange = function(name)
		if name == "Holy Strike" or name == "Hammer of Justice" then return false end
		if name == "Repentance" then return true end
		return false
	end

	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "sc", 20375)
	c.Advance(1.6)

	local pq = c.ns:GetModule("PriorityQueue")
	AssertEq(pq:Evaluate(), "Repentance", "Out of melee/HoJ range on hostile player must recommend Repentance GAP CLOSE")
	AssertEq(pq.currentPvpLabel, "GAP CLOSE", "Status label must be GAP CLOSE")

	-- Casting player when HoJ is on CD/out of range -> Repentance acts as INTERRUPT
	c.SetTargetCasting("Polymorph", false)
	c.Fire("UNIT_SPELLCAST_START", "target", "e1", 118)
	AssertEq(pq:Evaluate(), "Repentance", "Repentance must act as secondary interrupt when HoJ is unavailable")
	AssertEq(pq.currentIsInterrupt, true, "Secondary Repentance interrupt must set currentIsInterrupt=true")
end)

Test("60. Seal of Justice anti-runner triggers when mobile enemy player escapes melee range", function()
	local swingRange = true
	local c = CreateEnv({
		inCombat = true,
		swingInRange = true,
		knownSpells = {
			["Judgement"] = 20271,
			["Holy Strike"] = 678,
			["Seal of Command"] = 20375,
			["Seal of Justice"] = 20164,
		},
		usableSpells = {
			["Judgement"] = true,
			["Holy Strike"] = true,
			["Seal of Command"] = true,
			["Seal of Justice"] = true,
		},
	})
	c.env.UnitIsPlayer = function(u) return u == "target" end
	c.env.UnitClass = function(u) return u == "target" and "Druid" or "Paladin", u == "target" and "DRUID" or "PALADIN" end
	c.env.C_SwingTimer.IsTargetWithinSwingRange = function() return swingRange end
	c.env.C_Spell.IsSpellInRange = function(name)
		if name == "Judgement" then return true end
		return false
	end

	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "sc", 20375)
	c.Advance(1.6)
	local tracker = c.ns:GetModule("CombatTracker")
	tracker:IsInSwingRange() -- records hadMeleeWithTarget=true while in melee

	-- Druid shifts and runs out of melee (still in Judgement 10yd range)
	swingRange = false
	c.Advance(0.2)
	local pq = c.ns:GetModule("PriorityQueue")
	AssertEq(pq:Evaluate(), "Seal of Justice", "Escaping Druid must trigger Seal of Justice")
	AssertEq(pq.currentPvpLabel, "STOP RUNNER", "Status label must be STOP RUNNER")
end)

Test("61. BG secret auras suppress false BUFF/AURA MISSING spam, remind once after death, and BG secret CDs use cast model", function()
	local dead = false
	local c = CreateEnv({
		inCombat = false,
		targetExists = false,
		knownSpells = {
			["Judgement"] = 20271,
			["Blessing of Kings"] = 20217,
			["Retribution Aura"] = 7294,
		},
		usableSpells = {
			["Judgement"] = true,
			["Blessing of Kings"] = true,
			["Retribution Aura"] = true,
		},
	})
	c.env.IsInInstance = function() return true, "pvp" end
	c.env.C_Secrets = { ShouldAurasBeSecret = function() return true end }
	c.env.C_UnitAuras.GetAuraDataByIndex = function()
		error("GetAuraDataByIndex(): Auras cannot be accessed when secret while tainted by 'RetPulse'")
	end
	c.env.UnitIsDeadOrGhost = function() return dead end
	c.env.C_Spell.GetSpellCooldown = function()
		return { startTime = setmetatable({ __secret = true }, {}), duration = setmetatable({ __secret = true }, {}), isEnabled = true }
	end

	local tracker = c.ns:GetModule("CombatTracker")
	tracker:RefreshSeal()
	AssertEq(tracker:GetMissingBlessing(), nil, "Secret BG auras must NOT trigger false BUFF MISSING when player entered with buffs")
	AssertEq(tracker:GetMissingAura(), nil, "Secret BG auras must NOT trigger false AURA MISSING before dying")

	-- Player dies in BG and resurrects -> buffs were wiped by death, remind once!
	dead = true
	c.Fire("PLAYER_DEAD")
	dead = false
	AssertEq(tracker:GetMissingBlessing(), "Blessing of Kings", "After dying in BG and resurrecting, must remind Blessing")
	AssertEq(tracker:GetMissingAura(), "Retribution Aura", "After dying in BG and resurrecting, must remind Aura")

	-- Casting Blessing of Kings satisfies Blessing reminder while Aura reminder stays until Aura is cast
	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "b1", 20217)
	AssertEq(tracker:GetMissingBlessing(), nil, "Casting Blessing in BG clears post-death Blessing reminder")
	AssertEq(tracker:GetMissingAura(), "Retribution Aura", "Casting Blessing alone does not prematurely clear missing Aura")
	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "a1", 7294)
	AssertEq(tracker:GetMissingAura(), nil, "Casting Aura in BG clears post-death Aura reminder")

	-- Secret BG cooldowns out of combat fall back to cast-tracked model
	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "j1", 20271)
	local pq = c.ns:GetModule("PriorityQueue")
	local rem, src = pq:GetRemainingInfo("Judgement")
	AssertEq(src, "model", "Secret BG cooldown out of combat must fall back to cast model")
	Assert(rem > 9.0, "Judgement cooldown must still read >9s from cast model")
end)

Test("62. PvP anti-immunity holds Burst, HoJ, and Judgement with IMMUNE! status until wound or target change", function()
	local c = CreateEnv({
		inCombat = true,
		swingInRange = true,
		knownSpells = {
			["Judgement"] = 20271,
			["Holy Strike"] = 678,
			["Hammer of Justice"] = 853,
			["Seal of Command"] = 20375,
			["Avenging Wrath"] = 31884,
		},
		usableSpells = {
			["Judgement"] = true,
			["Holy Strike"] = true,
			["Hammer of Justice"] = true,
			["Seal of Command"] = true,
			["Avenging Wrath"] = true,
		},
		inRangeSpells = {
			["Judgement"] = true,
			["Holy Strike"] = true,
			["Hammer of Justice"] = true,
		},
	})
	c.env.UnitIsPlayer = function(u) return u == "target" end
	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "sc", 20375)
	c.Advance(1.6)

	local pq = c.ns:GetModule("PriorityQueue")
	local ui = c.ns:GetModule("UI")
	c.Fire("UNIT_COMBAT", "target", "IMMUNE")
	local cur = pq:Evaluate()
	AssertEq(pq.currentTargetImmune, true, "IMMUNE event must mark currentTargetImmune=true")
	AssertEq(cur, nil, "Must hold all offensive abilities while target is immune")
	ui:Refresh()
	AssertEq(ui.status:GetText(), "IMMUNE!", "HUD status must display IMMUNE!")

	c.Fire("UNIT_COMBAT", "target", "WOUND")
	cur = pq:Evaluate()
	AssertEq(pq.currentTargetImmune, false, "WOUND event clears immunity hold")
	AssertEq(cur, "Avenging Wrath", "Burst/offense resumes once immunity fades")
end)

Test("63. PvP Stun Combo holds Judgement during Seal GCD, triggers JUDGE STUN! #1 after HoJ, respects Repentance overlap and Stun DR", function()
	local c = CreateEnv({
		inCombat = true,
		swingInRange = true,
		knownSpells = {
			["Judgement"] = 20271,
			["Holy Strike"] = 678,
			["Hammer of Justice"] = 853,
			["Repentance"] = 20066,
			["Seal of Command"] = 20375,
		},
		usableSpells = {
			["Judgement"] = true,
			["Holy Strike"] = true,
			["Hammer of Justice"] = true,
			["Repentance"] = true,
			["Seal of Command"] = true,
		},
		inRangeSpells = {
			["Judgement"] = true,
			["Holy Strike"] = true,
			["Hammer of Justice"] = true,
			["Repentance"] = true,
		},
	})
	c.env.UnitIsPlayer = function(u) return u == "target" end
	c.env.UnitGUID = function(u) return "Player-1234" end
	c.ns.db.suggestBurst = false

	-- Right after casting Seal of Command (1.5s GCD active): must wait for HoJ instead of burning Judgement first.
	-- Preview polish: show HoJ (STUN COMBO!) waiting on GCD with NEXT = Judgement, never Holy Strike.
	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "sc", 20375)
	local pq = c.ns:GetModule("PriorityQueue")
	local cur, nxt = pq:Evaluate()
	Assert(cur ~= "Judgement", "Must hold Judgement during Seal of Command GCD when HoJ Stun Combo is ready")
	AssertEq(cur, "Hammer of Justice", "During SoC GCD, HUD must preview Hammer of Justice for STUN COMBO!")
	AssertEq(nxt, "Judgement", "During SoC GCD, NEXT must preview Judgement after HoJ")
	AssertEq(pq.currentPvpLabel, "STUN COMBO!", "During SoC GCD, label must stay STUN COMBO!")
	Assert(type(pq.countdown) == "number" and pq.countdown > 0.5 and pq.countdown <= 1.5,
		"During SoC GCD, countdown must reflect remaining GCD (~1.2s), not Holy Strike CD")

	-- Once GCD ends: HoJ (STUN COMBO!) -> cast HoJ -> Judgement (JUDGE STUN!)
	c.Advance(1.6)
	AssertEq(pq:Evaluate(), "Hammer of Justice", "Ready HoJ must open STUN COMBO!")
	AssertEq(pq.currentPvpLabel, "STUN COMBO!", "Label must be STUN COMBO!")

	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "hoj1", 853)
	c.Advance(1.6)
	AssertEq(pq:Evaluate(), "Judgement", "After HoJ lands with SoC, Judgement must fire as JUDGE STUN!")
	AssertEq(pq.currentPvpLabel, "JUDGE STUN!", "Label must be JUDGE STUN!")

	-- Cast Judgement + advance past HoJ DR window? Wait: reset HoJ CD manually without advancing 18s DR -> STUN DR suppresses 2nd HoJ!
	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "j1", 20271)
	c.Advance(10.5)
	pq.cdUntil["Hammer of Justice"] = nil
	AssertEq(pq:Evaluate(), "Judgement", "Second HoJ within 18s DR window must be suppressed in favor of Judgement")

	-- On fresh target, Repentance active prevents HoJ overlap
	c.env.UnitGUID = function() return "Player-9999" end
	c.Fire("PLAYER_TARGET_CHANGED")
	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "rep1", 20066)
	c.Advance(1.6)
	AssertEq(pq:Evaluate(), "Judgement", "Active Repentance must prevent HoJ stun overlap")
end)

Test("64. PvP Smart Matchup: saves HoJ vs Healers, catches Mage Blink with Repentance, and gates Burst to melee", function()
	local swingRange = false
	local targetClass = "PRIEST"
	local c = CreateEnv({
		inCombat = true,
		swingInRange = false,
		knownSpells = {
			["Judgement"] = 20271,
			["Holy Strike"] = 678,
			["Hammer of Justice"] = 853,
			["Repentance"] = 20066,
			["Seal of Command"] = 20375,
			["Avenging Wrath"] = 31884,
		},
		usableSpells = {
			["Judgement"] = true,
			["Holy Strike"] = true,
			["Hammer of Justice"] = true,
			["Repentance"] = true,
			["Seal of Command"] = true,
			["Avenging Wrath"] = true,
		},
		inRangeSpells = {
			["Judgement"] = true,
			["Holy Strike"] = false,
			["Hammer of Justice"] = true,
			["Repentance"] = true,
		},
	})
	c.env.UnitIsPlayer = function(u) return u == "target" end
	c.env.UnitClass = function(u)
		if u == "target" then return targetClass, targetClass end
		return "Paladin", "PALADIN"
	end
	c.env.C_SwingTimer.IsTargetWithinSwingRange = function() return swingRange end

	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "sc", 20375)
	c.Advance(1.6)

	local pq = c.ns:GetModule("PriorityQueue")
	-- Out of melee: Burst must wait (don't waste Avenging Wrath at range)
	swingRange = true
	-- Target is a Priest (Healer) at full HP with no Burst: save HoJ instead of cold stun!
	c.ns.db.suggestBurst = false
	AssertEq(pq:Evaluate(), "Judgement", "Must save HoJ vs Healer instead of blowing cold stun combo")

	-- Re-enable Burst: in melee with Judgement ready, Avenging Wrath fires
	c.ns.db.suggestBurst = true
	AssertEq(pq:Evaluate(), "Avenging Wrath", "Burst fires once in melee range with SoC & Judgement ready")

	-- Switch to Mage who Blinks out of melee -> Repentance CATCH BLINK!
	targetClass = "MAGE"
	swingRange = false
	c.Fire("PLAYER_TARGET_CHANGED")
	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "target", "b1", 1953)
	AssertEq(pq:Evaluate(), "Repentance", "Mage Blink out of melee must trigger Repentance CATCH BLINK!")
	AssertEq(pq.currentPvpLabel, "CATCH BLINK!", "Label must be CATCH BLINK!")
end)

Test("65. PvP 30yd Execute Snipe prioritizes Hammer of Wrath (FINISH!) when usable at range", function()
	local c = CreateEnv({
		inCombat = true,
		swingInRange = false,
		knownSpells = {
			["Judgement"] = 20271,
			["Holy Strike"] = 678,
			["Hammer of Wrath"] = 24275,
			["Repentance"] = 20066,
			["Seal of Command"] = 20375,
		},
		usableSpells = {
			["Judgement"] = true,
			["Holy Strike"] = true,
			["Hammer of Wrath"] = true,
			["Repentance"] = true,
			["Seal of Command"] = true,
		},
		inRangeSpells = {
			["Judgement"] = false,
			["Holy Strike"] = false,
			["Hammer of Wrath"] = true,
			["Repentance"] = true,
		},
	})
	c.env.UnitIsPlayer = function(u) return u == "target" end
	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "sc", 20375)
	c.Advance(1.6)

	local pq = c.ns:GetModule("PriorityQueue")
	AssertEq(pq:Evaluate(), "Hammer of Wrath", "Usable HoW at 30yd on escaping player must trigger FINISH!")
	AssertEq(pq.currentPvpLabel, "FINISH!", "Label must be FINISH!")
end)

Test("66. PvP targeted CC Breaker: Stun skips WotF -> uses PvP Trinket, and 2+ attackers + Stun prompts Bubble / low-level Divine Protection", function()
	local locList = { { locType = "STUN", timeRemaining = 4.0 } }
	local attackers = { "nameplate1" }
	local c = CreateEnv({
		inCombat = true,
		swingInRange = true,
		knownSpells = {
			["Will of the Forsaken"] = 7744,
			["Divine Shield"] = 642,
			["Judgement"] = 20271,
			["Seal of Command"] = 20375,
		},
		usableSpells = {
			["Will of the Forsaken"] = true,
			["Divine Shield"] = true,
			["Judgement"] = true,
			["Seal of Command"] = true,
		},
	})
	c.env.UnitIsPlayer = function(u) return u == "target" or u:find("^nameplate") ~= nil end
	c.env.UnitExists = function(u) return true end
	c.env.UnitCanAttack = function(_, u) return true end
	c.env.UnitIsDead = function() return false end
	c.env.UnitIsUnit = function(a, b)
		return b == "player" and a:find("target$") ~= nil
	end
	c.env.C_NamePlate.GetNamePlates = function()
		local r = {}
		for _, u in ipairs(attackers) do r[#r + 1] = { unitToken = u } end
		return r
	end
	c.env.C_LossOfControl = {
		GetActiveLossOfControlDataCount = function() return #locList end,
		GetActiveLossOfControlData = function(i) return locList[i] end,
	}
	c.env.GetInventoryItemID = function(_, slot) return slot == 13 and 18854 or 5322 end
	c.env.C_Item = {
		GetItemSpell = function(id) return id == 18854 and "PvP Trinket" or nil end,
		GetItemCooldown = function() return 0, 0, 1 end,
	}

	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "sc", 20375)
	c.Advance(1.6)

	local pq = c.ns:GetModule("PriorityQueue")
	-- 1 attacker + 4s Stun: WotF cannot break Stun, so equipped PvP Trinket triggers!
	AssertEq(pq:Evaluate(), "PvP Trinket", "4s Stun with WotF only must skip WotF and trigger PvP Trinket")
	AssertEq(pq.currentPvpLabel, "TRINKET!", "Label must be TRINKET!")

	-- Put PvP Trinket on CD and add a 2nd attacker -> Divine Shield (BUBBLE!)
	c.env.C_Item.GetItemCooldown = function() return c.env.GetTime() - 5, 120, 1 end
	attackers = { "nameplate1", "nameplate2" }
	c.Advance(0.25)
	AssertEq(pq:Evaluate(), "Divine Shield", "2+ attackers while hard-CC'd must prompt Divine Shield BUBBLE!")
	AssertEq(pq.currentPvpLabel, "BUBBLE!", "Label must be BUBBLE!")
end)

Test("67. PvP 360 nameplate radar alerts OFF-KICK! when another nearby player casts an interruptible spell", function()
	local c = CreateEnv({
		inCombat = true,
		swingInRange = true,
		nameplates = {
			{ unit = "nameplate1", hostile = true, dead = false, inRange = true },
			{ unit = "nameplate2", hostile = true, dead = false, inRange = true },
		},
		knownSpells = {
			["Judgement"] = 20271,
			["Holy Strike"] = 678,
			["Hammer of Justice"] = 853,
			["Seal of Command"] = 20375,
		},
		usableSpells = {
			["Judgement"] = true,
			["Holy Strike"] = true,
			["Hammer of Justice"] = true,
			["Seal of Command"] = true,
		},
	})
	c.env.UnitIsPlayer = function() return true end
	c.env.UnitIsUnit = function(a, b) return a == b or (a == "nameplate1" and b == "target") end
	c.env.UnitName = function(u) return u == "nameplate2" and "EnemyPriest" or "EnemyWarrior" end
	c.env.UnitCastingInfo = function(u)
		if u == "nameplate2" then
			return "Flash Heal", "Flash Heal", 0, 1000, 1002, false, "c2", false
		end
		return nil
	end

	local pq = c.ns:GetModule("PriorityQueue")
	local ui = c.ns:GetModule("UI")
	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "sc", 20375)
	c.Advance(1.6)

	pq:Evaluate()
	Assert(pq.currentOffTargetAlert ~= nil, "Off-target cast on nameplate2 must populate currentOffTargetAlert")
	AssertEq(pq.currentOffTargetAlert.caster, "EnemyPriest", "Off-target alert must identify caster name")
	ui:Refresh()
	AssertEq(ui.status:GetText(), "OFF-KICK: EnemyPriest", "HUD status must show OFF-KICK: EnemyPriest")
end)

Test("68. PvP Teammate Peel and Anti-Stealth Vanish Consecration reflex", function()
	local targetExists = true
	local targetClass = "WARRIOR"
	local c = CreateEnv({
		inCombat = true,
		swingInRange = true,
		knownSpells = {
			["Judgement"] = 20271,
			["Holy Strike"] = 678,
			["Hammer of Justice"] = 853,
			["Consecration"] = 26573,
			["Blessing of Protection"] = 1022,
			["Seal of Command"] = 20375,
		},
		usableSpells = {
			["Judgement"] = true,
			["Holy Strike"] = true,
			["Hammer of Justice"] = true,
			["Consecration"] = true,
			["Blessing of Protection"] = true,
			["Seal of Command"] = true,
		},
		inRangeSpells = {
			["Judgement"] = true,
			["Holy Strike"] = true,
			["Hammer of Justice"] = true,
		},
	})
	c.env.IsInGroup = function() return true end
	c.env.UnitIsPlayer = function() return true end
	c.env.UnitExists = function(u) return targetExists end
	c.env.UnitIsFriend = function(_, u) return u == "targettarget" end
	c.env.UnitIsUnit = function(a, b) return a == b end
	c.env.UnitClass = function(u)
		if u == "targettarget" then return "Priest", "PRIEST" end
		return targetClass, targetClass
	end

	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "sc", 20375)
	c.Advance(1.6)
	local pq = c.ns:GetModule("PriorityQueue")
	c.ns.db.suggestBurst = false

	-- Warrior targeting our Priest -> PEEL!
	AssertEq(pq:Evaluate(), "Hammer of Justice", "Warrior on friendly Priest must trigger Hammer of Justice PEEL!")
	AssertEq(pq.currentPvpLabel, "PEEL!", "Label must be PEEL!")

	-- Switch to Rogue in melee, then Rogue Vanishes (target cleared without dying) -> UNSTEALTH!
	targetClass = "ROGUE"
	c.Fire("PLAYER_TARGET_CHANGED")
	c.env.UnitIsFriend = function() return false end
	pq:Evaluate()
	targetExists = false
	c.Fire("PLAYER_TARGET_CHANGED")
	c.Advance(0.1)
	AssertEq(pq:Evaluate(), "Consecration", "Vanishing melee Rogue must trigger Consecration UNSTEALTH!")
	AssertEq(pq.currentPvpLabel, "UNSTEALTH!", "Label must be UNSTEALTH!")
end)

Test("69. Strict PvE and AV Boss isolation: NPC target inside Battleground uses pure PvE rotation", function()
	local c = CreateEnv({
		inCombat = true,
		swingInRange = true,
		knownSpells = {
			["Judgement"] = 20271,
			["Holy Strike"] = 678,
			["Hammer of Justice"] = 853,
			["Seal of Command"] = 20375,
			["Seal of Righteousness"] = 20288,
		},
		usableSpells = {
			["Judgement"] = true,
			["Holy Strike"] = true,
			["Hammer of Justice"] = true,
			["Seal of Command"] = true,
			["Seal of Righteousness"] = true,
		},
		inRangeSpells = {
			["Judgement"] = true,
			["Holy Strike"] = true,
			["Hammer of Justice"] = true,
		},
	})
	c.env.IsInInstance = function() return true, "pvp" end
	c.env.UnitIsPlayer = function() return false end
	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "sr", 20288)
	c.Advance(1.6)

	local pq = c.ns:GetModule("PriorityQueue")
	AssertEq(pq:Evaluate(), "Judgement", "NPC boss in AV must stay on pure PvE Judgement, never HoJ stun combo")
	AssertEq(pq.currentIsPvp, false, "NPC target inside BG must keep currentIsPvp=false")
end)

Test("70. Secret booleans from UnitIsUnit / UnitIsFriend / UnitExists on targettarget & nameplates never throw or lock HUD", function()
	local secretTrue = setmetatable({ __secret = true, val = true }, {})
	local secretFalse = setmetatable({ __secret = true, val = false }, {})
	local c = CreateEnv({
		inCombat = true,
		swingInRange = true,
		nameplates = {
			{ unit = "nameplate1", hostile = true, dead = false, inRange = true },
		},
		knownSpells = {
			["Judgement"] = 20271,
			["Holy Strike"] = 678,
			["Hammer of Justice"] = 853,
			["Seal of Command"] = 20375,
		},
		usableSpells = {
			["Judgement"] = true,
			["Holy Strike"] = true,
			["Hammer of Justice"] = true,
			["Seal of Command"] = true,
		},
		inRangeSpells = {
			["Judgement"] = true,
			["Holy Strike"] = true,
			["Hammer of Justice"] = true,
		},
	})
	c.env.IsInGroup = function() return true end
	c.env.UnitIsPlayer = function(u)
		if u == "nameplate1" then return secretTrue end
		return u == "target"
	end
	c.env.UnitExists = function(u)
		if u == "targettarget" then return true end
		return true
	end
	c.env.UnitIsUnit = function() return secretTrue end
	c.env.UnitIsFriend = function() return secretFalse end
	c.env.UnitClass = function(u)
		if u == "targettarget" then return "Priest", "PRIEST" end
		return "Warrior", "WARRIOR"
	end

	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "sc", 20375)
	c.Advance(1.6)

	local ui = c.ns:GetModule("UI")
	local pq = c.ns:GetModule("PriorityQueue")
	local cur = pq:Evaluate()
	Assert(cur ~= nil, "Evaluation with secret unit booleans must succeed")
	Assert(pq.currentPvpLabel ~= "PEEL!", "Secret UnitIsUnit/UnitIsFriend must never trigger false PEEL!")
	ui:Refresh()
	AssertEq(ui.consecutiveErrors, 0, "HUD Refresh must stay at 0 consecutive errors")
	AssertEq(ui.frame:IsShown(), true, "HUD must remain visible when targettarget booleans are secret")
end)

Test("71. Battleground teammate click-to-buff works with secret auras via cast tracking and death reset", function()
	local deadUnits = {}
	local c = CreateEnv({
		inCombat = false,
		targetExists = false,
		knownSpells = {
			["Blessing of Kings"] = 20217,
			["Blessing of Might"] = 19834,
			["Retribution Aura"] = 7294,
		},
		usableSpells = {
			["Blessing of Kings"] = true,
			["Blessing of Might"] = true,
			["Retribution Aura"] = true,
		},
	})
	c.env.IsInInstance = function() return true, "pvp" end
	c.env.C_Secrets = { ShouldAurasBeSecret = function() return true end }
	c.env.C_UnitAuras.GetAuraDataByIndex = function()
		error("GetAuraDataByIndex(): Auras cannot be accessed when secret while tainted by 'RetPulse'")
	end
	c.env.IsInGroup = function() return true end
	c.env.IsInRaid = function() return true end
	c.env.GetNumGroupMembers = function() return 2 end
	c.env.UnitExists = function(u) return u == "raid1" or u == "raid2" end
	c.env.UnitIsConnected = function() return true end
	c.env.UnitIsDeadOrGhost = function(u) return deadUnits[u] == true end
	c.env.UnitIsUnit = function(a, b) return a == b end
	c.env.UnitName = function(u)
		if u == "raid1" then return "Grom" end
		if u == "raid2" then return "Jaina" end
		return "MyPaladin"
	end
	c.env.UnitClass = function(u)
		if u == "raid1" then return "Warrior", "WARRIOR" end
		if u == "raid2" then return "Mage", "MAGE" end
		return "Paladin", "PALADIN"
	end
	c.env.C_Spell.IsSpellInRange = function(_, u) return u == "raid1" or u == "raid2" end

	local tracker = c.ns:GetModule("CombatTracker")
	c.Fire("PLAYER_ENTERING_WORLD")

	-- 1st missing teammate: raid1 (Grom) -> Blessing of Kings
	local spell, unit, uname = tracker:GetMissingGroupBlessing()
	AssertEq(spell, "Blessing of Kings", "BG teammate raid1 should get Blessing of Kings")
	AssertEq(unit, "raid1", "First unit should be raid1")
	AssertEq(uname, "Grom", "First unit name should be Grom")

	-- Cast Blessing of Kings on Grom -> moves automatically to raid2 (Jaina)
	c.Fire("UNIT_SPELLCAST_SENT", "player", "Grom-Realm", "cast-1", 20217)
	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 20217)
	spell, unit, uname = tracker:GetMissingGroupBlessing()
	AssertEq(spell, "Blessing of Kings", "BG teammate raid2 should now be suggested")
	AssertEq(unit, "raid2", "Second unit should be raid2")
	AssertEq(uname, "Jaina", "Second unit name should be Jaina")

	-- Cast Blessing of Kings on Jaina -> all teammates covered, goes silent
	c.Fire("UNIT_SPELLCAST_SENT", "player", "Jaina", "cast-2", 20217)
	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-2", 20217)
	AssertEq(tracker:GetMissingGroupBlessing(), nil, "All buffed BG teammates should stop suggesting")

	-- Grom dies and resurrects -> cast-tracker forgets his old buff and suggests Grom again
	deadUnits["raid1"] = true
	tracker:GetMissingGroupBlessing()
	deadUnits["raid1"] = false
	spell, unit, uname = tracker:GetMissingGroupBlessing()
	AssertEq(spell, "Blessing of Kings", "Resurrected BG teammate should be re-suggested")
	AssertEq(unit, "raid1", "Resurrected unit must be raid1")
	AssertEq(uname, "Grom", "Resurrected unit name must be Grom")
end)

Test("72. BG buff filter skips invisible/dead/unreadable-range teammates, handles secret castGUID & UnitName, and skips failed casts", function()
	local secretVal = setmetatable({ __secret = true }, {
		__tostring = function() error("secret") end,
	})
	local deadMap = { raid1 = true } -- raid1 is dead (UnitIsDead=true even if UnitIsDeadOrGhost=false)
	local visibleMap = { raid1 = true, raid2 = false, raid3 = true, raid4 = true, raid5 = true }
	local c = CreateEnv({
		inCombat = false,
		targetExists = false,
		knownSpells = {
			["Blessing of Kings"] = 20217,
		},
		usableSpells = {
			["Blessing of Kings"] = true,
		},
	})
	c.env.IsInInstance = function() return true, "pvp" end
	c.env.C_Secrets = { ShouldAurasBeSecret = function() return true end }
	c.env.IsInGroup = function() return true end
	c.env.IsInRaid = function() return true end
	c.env.GetNumGroupMembers = function() return 5 end
	c.env.UnitExists = function(u) return u == "raid1" or u == "raid2" or u == "raid3" or u == "raid4" or u == "raid5" end
	c.env.UnitIsConnected = function() return true end
	c.env.UnitIsVisible = function(u) return visibleMap[u] == true end
	c.env.UnitIsDeadOrGhost = function() return false end
	c.env.UnitIsDead = function(u) return deadMap[u] == true end
	c.env.UnitIsGhost = function() return false end
	c.env.UnitIsUnit = function(a, b) return a == b end
	c.env.UnitName = function(u)
		if u == "raid4" then return secretVal end
		if u == "raid5" then return "Thrall" end
		return u
	end
	c.env.UnitClass = function() return "Warrior", "WARRIOR" end
	c.env.C_Spell.IsSpellInRange = function(_, u)
		if u == "raid3" then return nil end -- unknown/nil range must NOT default to inRange=true!
		if u == "raid4" or u == "raid5" then return true end
		return false
	end

	local tracker = c.ns:GetModule("CombatTracker")
	c.Fire("PLAYER_ENTERING_WORLD")

	-- raid1 (dead), raid2 (invisible/far), raid3 (nil range) must ALL be skipped -> goes straight to raid4!
	local spell, unit = tracker:GetMissingGroupBlessing()
	AssertEq(unit, "raid4", "Dead (raid1), invisible (raid2), and unknown-range (raid3) must be skipped -> raid4")
	AssertEq(spell, "Blessing of Kings", "raid4 gets Blessing of Kings")

	-- Secret castGUID + secret targetName must NOT crash and must mark raid4 buffed via lastSuggestedBuffUnit
	c.Fire("UNIT_SPELLCAST_SENT", "player", secretVal, secretVal, 20217)
	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", secretVal, 20217)

	spell, unit = tracker:GetMissingGroupBlessing()
	AssertEq(unit, "raid5", "After casting on raid4 with secret castGUID/name, must advance to raid5 (never repeat raid4)")

	-- If raid5 returns Out of range error, immediately skip raid5 for 10s
	c.Fire("UI_ERROR_MESSAGE", 1, "Out of range.")
	AssertEq(tracker:GetMissingGroupBlessing(), nil, "Failed Out of range cast must skip raid5 immediately")
end)

Test("73. HUD click-to-buff PreClick marks exact teammate even when UNIT_SPELLCAST_SENT says Unknown or cross-realm (*)", function()
	local c = CreateEnv({
		inCombat = false,
		targetExists = false,
		knownSpells = {
			["Blessing of Kings"] = 20217,
		},
		usableSpells = {
			["Blessing of Kings"] = true,
		},
	})
	c.env.IsInInstance = function() return true, "pvp" end
	c.env.C_Secrets = { ShouldAurasBeSecret = function() return true end }
	c.env.IsInGroup = function() return true end
	c.env.IsInRaid = function() return true end
	c.env.GetNumGroupMembers = function() return 2 end
	c.env.UnitExists = function(u) return u == "raid1" or u == "raid2" end
	c.env.UnitIsConnected = function() return true end
	c.env.UnitIsDeadOrGhost = function() return false end
	c.env.UnitIsUnit = function(a, b) return a == b end
	c.env.UnitName = function(u)
		if u == "raid1" then return "Иван" end
		if u == "raid2" then return "Morthor (*)" end
		return "MyPaladin"
	end
	c.env.UnitGUID = function(u) return "Guid-" .. tostring(u) end
	c.env.UnitClass = function() return "Warrior", "WARRIOR" end
	c.env.C_Spell.IsSpellInRange = function(_, u) return u == "raid1" or u == "raid2" end

	local ui = c.ns:GetModule("UI")
	local tracker = c.ns:GetModule("CombatTracker")
	c.ns.db.lastOwnBlessing = { name = "Blessing of Kings", expiresAt = c.env.time() + 300 }
	tracker.ownBlessings = { ["Blessing of Kings"] = true }
	tracker.ownBlessingExpiry = { ["Blessing of Kings"] = c.env.GetTime() + 300 }
	c.Fire("PLAYER_ENTERING_WORLD")
	ui:Refresh()
	AssertEq(ui.status:GetText(), "BUFF: |cffc79c6eИван|r", "Initial HUD must suggest class-colored Иван")
	AssertEq(ui.clickUnit, "raid1", "clickUnit must be raid1")

	-- Simulate clicking HUD (PreClick) + Blizzard reporting "Unknown" in UNIT_SPELLCAST_SENT
	tracker:NoteBuffClick(ui.clickUnit, ui.clickUnitName, ui.clickSpell)
	c.Fire("UNIT_SPELLCAST_SENT", "player", "Unknown", "c1", 20217)
	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "c1", 20217)

	AssertEq(ui.status:GetText(), "BUFF: |cffc79c6eMorthor (*)|r", "After buffing Иван, HUD must immediately advance to class-colored Morthor (*)")
	AssertEq(ui.clickUnit, "raid2", "clickUnit must now be raid2")

	-- Second click with cross-realm "Morthor-Icecrown" in SENT -> advances to no remaining buffs
	tracker:NoteBuffClick(ui.clickUnit, ui.clickUnitName, ui.clickSpell)
	c.Fire("UNIT_SPELLCAST_SENT", "player", "Morthor-Icecrown", "c2", 20217)
	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "c2", 20217)
	AssertEq(tracker:GetMissingGroupBlessing(), nil, "Both Иван and Morthor must stay marked buffed")
end)

Test("74. BG self-buff reminder, self Freedom overwrite, currentInRange=false propagation, and persisted weapon speed", function()
	local savedDB = {}
	local speedSecret = false
	local c = CreateEnv({
		inCombat = false,
		targetExists = false,
		weaponSpeed = 3.50,
		weaponItemID = 19854,
		savedDB = savedDB,
		knownSpells = {
			["Blessing of Kings"] = 20217,
			["Blessing of Freedom"] = 1044,
			["Retribution Aura"] = 7294,
			["Judgement"] = 20271,
			["Holy Strike"] = 678,
			["Seal of Command"] = 20375,
		},
		usableSpells = {
			["Blessing of Kings"] = true,
			["Blessing of Freedom"] = true,
			["Retribution Aura"] = true,
			["Judgement"] = true,
			["Holy Strike"] = true,
			["Seal of Command"] = true,
		},
		inRangeSpells = {
			["Judgement"] = false,
			["Holy Strike"] = false,
		},
	})
	c.env.IsInInstance = function() return true, "pvp" end
	c.env.C_Secrets = { ShouldAurasBeSecret = function() return true end }
	c.env.UnitAttackSpeed = function()
		if speedSecret then return setmetatable({ __secret = true }, {}) end
		return 3.50
	end

	local tracker = c.ns:GetModule("CombatTracker")
	local ui = c.ns:GetModule("UI")
	local engine = c.ns:GetModule("WeaponEngine")
	AssertEq(savedDB.weaponSpeedCache[19854], 3.5, "Readable weapon speed must persist in weaponSpeedCache")

	-- Entering BG unbuffed -> immediately suggests player's own Blessing of Kings on unit="player"
	c.Fire("PLAYER_ENTERING_WORLD")
	ui:Refresh()
	AssertEq(ui.status:GetText(), "BUFF MISSING", "Unbuffed BG entry must prompt BUFF MISSING")
	AssertEq(ui.clickUnit, "player", "Self-buff click-to-cast must force unit='player'")

	-- Clicking BUFF MISSING on HUD (PreClick passes unit="player", unitName="You") clears reminder
	tracker:NoteBuffClick(ui.clickUnit, ui.clickUnitName, ui.clickSpell)
	c.Fire("UNIT_SPELLCAST_SENT", "player", "Unknown", "b1", 20217)
	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "b1", 20217)
	AssertEq(tracker:GetMissingBlessing(), nil, "Clicking BUFF MISSING on HUD in BG must clear self-buff reminder")
	Assert(ui.status:GetText() ~= "BUFF MISSING", "HUD must immediately clear BUFF MISSING after self click-to-cast")
	Assert(savedDB.lastOwnBlessing and savedDB.lastOwnBlessing.name == "Blessing of Kings", "Self-buff must persist in DB")

	-- Advancing 245s (< 60s left on 300s Blessing) triggers early refresh even in BG!
	c.Advance(245)
	AssertEq(tracker:GetMissingBlessing(), "Blessing of Kings", "Own Blessing with <60s left in BG must trigger refresh")

	-- Re-buff, then cast Blessing of Freedom on self -> overwrites own stat Blessing and prompts Kings again!
	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "b2", 20217)
	AssertEq(tracker:GetMissingBlessing(), nil, "Fresh self-blessing clears reminder")
	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "bf1", 1044)
	AssertEq(tracker:GetMissingBlessing(), "Blessing of Kings", "Self Blessing of Freedom must invalidate stat blessing and re-prompt Kings")

	-- Out-of-range spell in PriorityQueue must preserve false (not convert false -> nil)
	c.SetCombat(true)
	c.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "sc", 20375)
	c.Advance(1.6)
	local pq = c.ns:GetModule("PriorityQueue")
	c.env.UnitExists = function(u) return u == "target" end
	c.env.UnitCanAttack = function(_, u) return u == "target" end
	pq:Evaluate()
	AssertEq(pq.currentInRange, false, "Out-of-range ability must set currentInRange=false, never nil")

	-- Simulate /reload inside BG where UnitAttackSpeed is secret -> weaponSpeed restores from weaponSpeedCache
	speedSecret = true
	local c2 = CreateEnv({
		inCombat = false,
		weaponItemID = 19854,
		weaponSpeedSecret = true,
		savedDB = savedDB,
	})
	AssertEq(c2.ns:GetModule("WeaponEngine").weaponSpeed, 3.5, "BG reload with secret weapon speed must restore from cache")
end)

print(string.format("\nResults: %d passed, %d failed", passed, failed))
if failed > 0 then
	os.exit(1)
end
