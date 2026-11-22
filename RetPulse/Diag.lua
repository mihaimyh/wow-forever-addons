local addonName, ns = ...

local Diag = ns:NewModule("Diag")

-- The client gives addons no combat log, so the rotation has to be audited from
-- the events that stay readable: swings, successful casts, target changes, and
-- the advice this addon produced at that moment.
--
-- Everything lands in RetPulseDB.combatLog and is flushed by /reload.
-- Values the client marks as secret are written as the word "secret", never
-- passed to tostring.

local MAX_LINES = 900

local function Safe(value, fallback)
	if value == nil then return fallback end
	if ns.IsSecret(value) then return "secret" end
	return tostring(value)
end

function Diag:OnInitialize()
	self.session = {}
	self.t0 = nil
	self.ticker = nil
	self.lastSuggestion = nil
	self.lastInRange = nil
	self.pulls = 0
end

function Diag:OnLogin()
	ns:On("PLAYER_REGEN_DISABLED", function()
		self:Start()
	end)

	ns:On("PLAYER_REGEN_ENABLED", function()
		self:Flush()
	end)

	ns:On("PLAYER_LOGOUT", function()
		self:Flush()
	end)

	ns:On("PLAYER_TARGET_CHANGED", function()
		if not self.t0 then return end
		self:Add("TARGET",
			"name=" .. Safe(UnitName("target"), "none"),
			"lvl=" .. Safe(UnitLevel("target"), "?"),
			"type=" .. Safe(UnitCreatureType("target"), "?"),
			"class=" .. Safe(UnitClassification("target"), "?"))
	end)

	ns:On("PLAYER_SWING", function(_, duration, swingType)
		if not self.t0 then return end
		local tracker = ns:GetModule("CombatTracker")
		self:Add("SWING",
			"d=" .. Safe(duration, "secret"),
			"type=" .. Safe(swingType, "?"),
			"seal=" .. Safe(tracker:GetActiveSeal(), "none"),
			"echoes=" .. tostring(tracker:GetEchoes()),
			"swings=" .. tostring(tracker:GetSwingsWithSeal()))
	end)

	ns:On("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, _, spellID)
		if not self.t0 or unit ~= "player" then return end

		local spellName = "?"
		if C_Spell and C_Spell.GetSpellInfo then
			local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
			if ok and type(info) == "table" and type(info.name) == "string" then
				spellName = info.name
			end
		end

		local pq = ns:GetModule("PriorityQueue")
		self:Add("CAST",
			"spell=" .. spellName,
			"suggested=" .. Safe(pq and pq.current, "none"),
			"match=" .. tostring(pq and pq.current == spellName),
			"range=" .. Safe(pq and pq.currentInRange, "?"))
	end)

	ns:On("WEAPON_SLOT_CHANGED", function()
		if not self.t0 then return end
		local engine = ns:GetModule("WeaponEngine")
		self:Add("WEAPON", "speed=" .. Safe(engine and engine.weaponSpeed, "secret"),
			"bracket=" .. Safe(engine and engine:GetBracket(), "?"))
	end)
end

function Diag:Add(kind, ...)
	if not self.t0 then return end
	local stamp = string.format("%7.2f", GetTime() - self.t0)
	local parts = {}
	for i = 1, select("#", ...) do
		local value = select(i, ...)
		if ns.IsSecret(value) then
			parts[i] = "secret"
		else
			parts[i] = tostring(value)
		end
	end
	self.session[#self.session + 1] = stamp .. " " .. kind .. " " .. table.concat(parts, " ")
end

function Diag:Start()
	local db = ns.db
	if not db or db.logEnabled == false then
		if self.ticker then
			self.ticker:Cancel()
			self.ticker = nil
		end
		self.t0 = nil
		return
	end

	self:Flush()

	self.t0 = GetTime()
	self.pulls = (self.pulls or 0) + 1
	self.session = {}
	self.lastSuggestion = nil
	self.lastInRange = nil

	local engine = ns:GetModule("WeaponEngine")
	local tracker = ns:GetModule("CombatTracker")
	self:Add("PULL", "n=" .. self.pulls,
		"lvl=" .. tostring(UnitLevel("player")),
		"speed=" .. Safe(engine and engine.weaponSpeed, "secret"),
		"bracket=" .. Safe(engine and engine:GetBracket(), "?"),
		"uw=" .. Safe(engine and engine.hasUnsealedWrath, "?"),
		"seal=" .. Safe(tracker and tracker:GetActiveSeal(), "none"),
		"target=" .. Safe(UnitName("target"), "none"))

	self:Add("TARGET",
		"name=" .. Safe(UnitName("target"), "none"),
		"lvl=" .. Safe(UnitLevel("target"), "?"),
		"type=" .. Safe(UnitCreatureType("target"), "?"))

	if self.ticker then self.ticker:Cancel() end
	self.ticker = C_Timer.NewTicker(0.5, function() self:Tick() end)
end

function Diag:Tick()
	if not self.t0 then return end
	local pq = ns:GetModule("PriorityQueue")
	if not pq then return end

	if pq.current ~= self.lastSuggestion or pq.currentInRange ~= self.lastInRange then
		self.lastSuggestion = pq.current
		self.lastInRange = pq.currentInRange

		local jr, js = pq:GetRemainingInfo(ns.SPELLS.JUDGEMENT)
		local hr, hs = pq:GetRemainingInfo(ns.SPELLS.HOLY_STRIKE)
		local tracker = ns:GetModule("CombatTracker")
		local sealLeft = tracker and tracker:GetSealRemaining()

		self:Add("NEXT",
			"sug=" .. Safe(pq.current, "none"),
			"range=" .. Safe(pq.currentInRange, "?"),
			"cd=" .. string.format("%.1f", pq.countdown or 0),
			"J=" .. string.format("%.1f%s", jr or 0, js or "?"),
			"HS=" .. string.format("%.1f%s", hr or 0, hs or "?"),
			"gcd=" .. string.format("%.1f", pq:GetGcdRemaining()),
			"seal=" .. Safe(tracker and tracker:GetActiveSeal(), "none"),
			"s=" .. (sealLeft and string.format("%.1f", sealLeft) or "?"))
	end
end

function Diag:Flush()
	if not self.t0 then return end

	self:Add("END", "dur=" .. string.format("%.1f", GetTime() - self.t0))

	if self.ticker then
		self.ticker:Cancel()
		self.ticker = nil
	end
	self.t0 = nil

	local db = ns.db
	if db then
		db.combatLog = db.combatLog or {}
		for _, line in ipairs(self.session) do
			db.combatLog[#db.combatLog + 1] = line
		end
		while #db.combatLog > MAX_LINES do
			table.remove(db.combatLog, 1)
		end
		db.logLines = #db.combatLog
	end

	self.session = {}
end
