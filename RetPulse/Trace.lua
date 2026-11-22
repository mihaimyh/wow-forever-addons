local addonName, ns = ...

local Trace = ns:NewModule("Trace")

-- Flight recorder for the addon.
--
-- The client gives us no debugger, so every question ("why is the HUD hidden",
-- "why was Holy Strike greyed", "did the ring restart") has to be answerable
-- from a file we can read afterwards. This module records:
--   * discrete events with decoded payloads
--   * a periodic full snapshot of every module's state
--   * one-shot deep dumps
-- and writes them into RetPulseDB.traceLog / RetPulseDB.dump, flushed by
-- /reload exactly like SavedVariables.

local MAX_LINES = 4000
local SAMPLE_COMBAT = 0.5
local SAMPLE_IDLE = 2.0

local Safe = ns.Safe

function Trace:OnInitialize()
	self.buffer = {}
	self.enabled = false
	self.ticker = nil
	self.lastVisible = nil
	self.lastCurrent = nil
	self.lastSeal = nil
	self.lastEchoes = nil
end

function Trace:OnLogin()
	ns:On("PLAYER_REGEN_DISABLED", function() self:Record("COMBAT", "start") end)
	ns:On("PLAYER_REGEN_ENABLED", function() self:Record("COMBAT", "end") end)

	ns:On("PLAYER_TARGET_CHANGED", function()
		self:Record("TARGET",
			"name=" .. Safe(UnitName("target"), "none"),
			"exists=" .. Safe(UnitExists("target"), "?"),
			"hostile=" .. Safe(UnitCanAttack("player", "target"), "?"))
	end)

	ns:On("PLAYER_SWING", function(_, duration, swingType)
		self:Record("EVENT", "PLAYER_SWING",
			"duration=" .. Safe(duration, "?"),
			"type=" .. Safe(swingType, "?"))
	end)

	ns:On("UNIT_COMBAT", function(_, unit, action)
		if unit ~= "target" then return end
		self:Record("EVENT", "UNIT_COMBAT",
			"unit=" .. Safe(unit, "?"),
			"action=" .. Safe(action, "?"))
	end)

	ns:On("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, _, spellID)
		if unit ~= "player" then return end
		local name = ns.GetSpellNameByID(spellID) or "?"
		self:Record("EVENT", "CAST", "spell=" .. name, "id=" .. Safe(spellID, "?"))
	end)

	ns:On("UNIT_AURA", function(_, unit)
		if unit == "player" then self:Record("EVENT", "UNIT_AURA", "player") end
	end)

	ns:On("WEAPON_SLOT_CHANGED", function() self:Record("EVENT", "WEAPON_SLOT_CHANGED") end)
	ns:On("UNIT_ATTACK_SPEED", function(_, unit)
		if unit == "player" then self:Record("EVENT", "UNIT_ATTACK_SPEED") end
	end)
	ns:On("COOLDOWN_VIEWER_DATA_LOADED", function()
		self:Record("EVENT", "COOLDOWN_VIEWER_DATA_LOADED")
	end)

	ns:On("PLAYER_LOGOUT", function()
		self:Flush()
	end)

	if ns.db and ns.db.traceEnabled then
		self:Start()
	end
end

function Trace:Record(kind, ...)
	if not self.enabled then return end
	local parts = { string.format("%8.2f", GetTime()), kind }
	for i = 1, select("#", ...) do
		parts[#parts + 1] = Safe((select(i, ...)), "?")
	end
	self.buffer[#self.buffer + 1] = table.concat(parts, " ")
end

function Trace:Sample()
	local ui = ns:GetModule("UI")
	local tracker = ns:GetModule("CombatTracker")
	local queue = ns:GetModule("PriorityQueue")
	local fx = ns:GetModule("FX")

	local line = {}
	line[#line + 1] = "STATE"
	if ui then line[#line + 1] = ui:DebugLine() end
	if tracker then line[#line + 1] = tracker:DebugLine() end
	if queue then line[#line + 1] = queue:DebugLine() end
	if fx then line[#line + 1] = fx:DebugLine() end

	local text = table.concat(line, " | ")
	self:Record(text)

	-- Discrete transitions are easier to spot than a full timeline.
	if ui then
		local visible = (ui.frame and ui.frame:IsShown()) and true or false
		if self.lastVisible ~= visible then
			self.lastVisible = visible
			self:Record("VISIBILITY", "shown=" .. Safe(visible, "?"),
				"combat=" .. Safe(InCombatLockdown(), "?"),
				"target=" .. Safe(UnitCanAttack("player", "target"), "?"))
		end
	end
end

function Trace:Start()
	if self.enabled then return end
	self.enabled = true
	self.lastSampleAt = 0
	self.ticker = C_Timer.NewTicker(SAMPLE_COMBAT, function()
		local now = GetTime()
		local interval = InCombatLockdown() and SAMPLE_COMBAT or SAMPLE_IDLE
		if (now - (self.lastSampleAt or 0)) < (interval - 0.05) then return end
		self.lastSampleAt = now
		self:Sample()
	end)
	self:Record("TRACE", "started")
end

function Trace:Stop()
	if not self.enabled then return end
	self:Record("TRACE", "stopped")
	self.enabled = false
	if self.ticker then
		self.ticker:Cancel()
		self.ticker = nil
	end
	self:Flush()
end

function Trace:Flush()
	local db = ns.db
	if not db then return end

	db.traceLog = db.traceLog or {}
	for _, line in ipairs(self.buffer) do
		db.traceLog[#db.traceLog + 1] = line
	end
	while #db.traceLog > MAX_LINES do
		table.remove(db.traceLog, 1)
	end
	db.traceLines = #db.traceLog
	self.buffer = {}
end

function Trace:Clear()
	if ns.db then
		ns.db.traceLog = {}
		ns.db.traceLines = 0
	end
	self.buffer = {}
end

-- One-shot deep dump: everything the addon believes, in key=value form.
function Trace:Dump()
	local out = {}
	local function add(section, ...)
		out[#out + 1] = "[" .. section .. "]"
		for i = 1, select("#", ...) do
			out[#out + 1] = Safe((select(i, ...)), "?")
		end
	end

	local db = ns.db or {}
	for key, value in pairs(db) do
		if key ~= "traceLog" and key ~= "combatLog" and key ~= "debugLog" then
			out[#out + 1] = "db." .. key .. " = " .. Safe(value, "nil")
		end
	end

	local ui = ns:GetModule("UI")
	local tracker = ns:GetModule("CombatTracker")
	local queue = ns:GetModule("PriorityQueue")
	local engine = ns:GetModule("WeaponEngine")
	local fx = ns:GetModule("FX")

	add("ui", ui and ui:DebugLine() or "missing")
	add("tracker", tracker and tracker:DebugLine() or "missing")
	add("queue", queue and queue:DebugLine() or "missing")
	add("weapon", engine and engine:DebugLine() or "missing")
	add("fx", fx and fx:DebugLine() or "missing")

	add("frame",
		"shown=" .. Safe(ui and ui.frame and ui.frame:IsShown(), "?"),
		"scale=" .. Safe(ui and ui.frame and ui.frame:GetScale(), "?"),
		"width=" .. Safe(ui and ui.frame and ui.frame:GetWidth(), "?"),
		"height=" .. Safe(ui and ui.frame and ui.frame:GetHeight(), "?"))

	local point, relativePoint, x, y
	if ui and ui.frame and ui.frame:GetPoint(1) then
		point, _, relativePoint, x, y = ui.frame:GetPoint(1)
	end
	add("anchor", "point=" .. Safe(point, "?"), "relative=" .. Safe(relativePoint, "?"),
		"x=" .. Safe(x, "?"), "y=" .. Safe(y, "?"))

	add("client",
		"version=" .. Safe(select(1, GetBuildInfo()), "?"),
		"build=" .. Safe(select(2, GetBuildInfo()), "?"),
		"project=" .. Safe(WOW_PROJECT_ID, "?"),
		"combat=" .. Safe(InCombatLockdown(), "?"),
		"inInstance=" .. Safe(IsInInstance(), "?"))

	if ns.db then
		ns.db.dump = out
		ns.db.dumpAt = date("%Y-%m-%d %H:%M:%S")
	end
	ns:Print("dump written:", #out, "lines")
end
