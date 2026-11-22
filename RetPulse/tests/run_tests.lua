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
	AssertEq(ui.status:GetText(), "BUFF: Grom", "HUD status must show who needs the buff")

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

print(string.format("\nResults: %d passed, %d failed", passed, failed))
if failed > 0 then
	os.exit(1)
end
