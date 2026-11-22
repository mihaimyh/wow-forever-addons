local addonName, ns = ...

-------------------------------------------------------------------------------
-- Client facts
-------------------------------------------------------------------------------
-- WoW: Forever is the Camelot game type inside the Mainline client family.
-- Midnight's addon restrictions apply: no combat log, secret values in combat.
ns.addonName = addonName
ns.IsForever = WOW_PROJECT_ID == (WOW_PROJECT_CAMELOT or 18)

-- Rank-independent spell names. IDs differ per rank, so we resolve by name.
ns.SPELLS = {
	JUDGEMENT       = "Judgement",
	HOLY_STRIKE     = "Holy Strike",
	EXORCISM        = "Exorcism",
	CONSECRATION    = "Consecration",
	HAMMER_OF_WRATH = "Hammer of Wrath",
	HAMMER_OF_JUSTICE = "Hammer of Justice",
	HOLY_SHOCK      = "Holy Shock",
	HOLY_WRATH      = "Holy Wrath",
	SEAL_COMMAND    = "Seal of Command",
	SEAL_RIGHT      = "Seal of Righteousness",
	SEAL_FURY       = "Seal of Fury",
	SEAL_CRUSADER   = "Seal of the Crusader",
	BLESSING_KINGS  = "Blessing of Kings",
	BLESSING_MIGHT  = "Blessing of Might",
	BLESSING_WISDOM = "Blessing of Wisdom",
	AURA_RETRIBUTION = "Retribution Aura",
	AURA_SANCTITY    = "Sanctity Aura",
	AURA_DEVOTION    = "Devotion Aura",
	UNSEALED_WRATH  = "Unsealed Wrath",
}

-------------------------------------------------------------------------------
-- Saved variables
-------------------------------------------------------------------------------
local DEFAULTS = {
	enabled = true,
	locked = true,
	scale = 1.0,
	auto = true,          -- auto seal pairing from weapon speed (hint only)
	aoe = false,          -- always include Consecration / Holy Wrath
	autoAoe = true,       -- auto-enable AoE when 2+ hostile mobs are in melee range
	suggestInterrupt = true, -- suggest Hammer of Justice when target casts an interruptible spell
	crusaderOnBoss = true,   -- recommend Seal of the Crusader opener on Elites/Bosses
	talentAdvisor = true,    -- highlight RetPulse talents on PlayerSpellsFrame.TalentsFrame
	talentBuild = "dps",     -- "dps" (Benediction) or "leveling" (Deflection)
	preferredBlessing = "auto", -- "auto" (Kings->Might->Wisdom) | "kings" | "might" | "wisdom" | "off"
	remindAura = true,          -- remind out of combat if no Paladin Aura is active
	learnedCooldowns = {},      -- persisted talented/set-reduced spell cooldowns
	sound = true,         -- one click on SWAP NOW
	visibility = "combat",       -- "combat" | "target" | "always"
	showOutOfCombat = false,     -- legacy mirror of visibility
	combatOnly = true,           -- legacy mirror of visibility
	showKeybinds = true,         -- show action-bar keybind badges on icons
	schema = 5,
	twistWithoutTalent = false, -- twist below 40, as the sim video advises
	bracketMode = "video",       -- "video" (3 brackets, per the deep dive) or "icy" (2)
	bracketsIcy = false,         -- legacy mirror of bracketMode
	traceEnabled = false,        -- opt-in flight recorder (/rp trace on)
	logEnabled = false,          -- opt-in combat log (/rp log)
	forceUnsealedWrath = false,  -- manual override when the passive stays invisible
	effects = true,             -- holy aura, sparks and burst around the icon
	position = { point = "BOTTOM", relativePoint = "BOTTOM", x = 0, y = 220 },
	manual = {
		sealA = "Seal of Command",
		stacksA = 3,
		sealB = "Seal of Righteousness",
		stacksB = 1,
	},
}

local function ApplyDefaults(db, defaults)
	for k, v in pairs(defaults) do
		if type(v) == "table" then
			if type(db[k]) ~= "table" then db[k] = {} end
			ApplyDefaults(db[k], v)
		elseif db[k] == nil then
			db[k] = v
		end
	end
	return db
end

-------------------------------------------------------------------------------
-- Event dispatcher (many handlers per event, one frame)
-------------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local handlers = {}
local blockedEvents = {}

function ns:On(event, fn)
	if not handlers[event] then
		handlers[event] = {}
		local ok = pcall(eventFrame.RegisterEvent, eventFrame, event)
		if not ok then
			blockedEvents[event] = true
			ns:Print("|cffff5555event blocked on this client|r", event)
		end
	end
	table.insert(handlers[event], fn)
end

function ns:IsEventBlocked(event)
	return blockedEvents[event] == true
end

function ns:Off(event, fn)
	local list = handlers[event]
	if not list then return end
	for i = #list, 1, -1 do
		if list[i] == fn then table.remove(list, i) end
	end
	if #list == 0 then
		handlers[event] = nil
		eventFrame:UnregisterEvent(event)
	end
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
	local list = handlers[event]
	if not list then return end
	for _, fn in ipairs(list) do
		fn(event, ...)
	end
end)

-- Debug output is written into RetPulseDB.debugLog and flushed to disk by the
-- next /reload, so nothing has to be copied out of the game client.
local debugBuffer

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------
function ns:Print(...)
	local count = select("#", ...)
	local parts = {}
	for i = 1, count do
		local v = select(i, ...)
		parts[i] = ns.IsSecret(v) and "SECRET" or tostring(v)
	end
	local line = table.concat(parts, " ")
	print("|cffc8a44a" .. addonName .. "|r:", line)
	if debugBuffer then
		table.insert(debugBuffer, line)
	end
end

-- Errors are recorded in the SavedVariables, because chat is not readable here.
function ns:RecordError(where, err)
	if ns.db then
		ns.db.lastError = tostring(where) .. ": " .. tostring(err) .. " @ " .. tostring(date("%H:%M:%S"))
	end
end

function ns.IsSecret(value)
	if value == nil then return false end
	if issecretvalue ~= nil and issecretvalue(value) then return true end
	if issecrettable ~= nil and issecrettable(value) then return true end
	return false
end

-- True only when a value can be used for arithmetic and comparisons.
function ns.IsReadable(value)
	if value == nil then return false end
	if ns.IsSecret(value) then return false end
	local t = type(value)
	return t == "number" or t == "string" or t == "boolean"
end

-- Work that touches secure frames must wait for combat to end.
local outOfCombatQueue = {}

function ns:RunOutOfCombat(fn)
	if InCombatLockdown() then
		table.insert(outOfCombatQueue, fn)
	else
		fn()
	end
end

-------------------------------------------------------------------------------
-- Modules
-------------------------------------------------------------------------------
ns.modules = {}

function ns:NewModule(name)
	local module = { name = name }
	ns.modules[name] = module
	table.insert(ns.modules, module)
	return module
end

function ns:GetModule(name)
	return ns.modules[name]
end

function ns:SyncVisibilityFields()
	if not ns.db then return end
	local vis = ns.db.visibility
	if vis ~= "combat" and vis ~= "target" and vis ~= "always" then
		if ns.db.combatOnly ~= false then
			vis = "combat"
		elseif ns.db.showOutOfCombat then
			vis = "always"
		else
			vis = "target"
		end
		ns.db.visibility = vis
	end
	ns.db.combatOnly = (vis == "combat")
	ns.db.showOutOfCombat = (vis == "always")
end

function ns:NotifySetting(variable, value)
	local config = ns:GetModule("Config")
	if config and config.SyncSetting then
		config:SyncSetting(variable, value)
	end
	local ui = ns:GetModule("UI")
	if ui and ui.Refresh then
		ui:Refresh()
	end
end

local function IsPlayerPaladin()
	if not UnitClass then return true end
	local _, classFile = UnitClass("player")
	return classFile == "PALADIN"
end

-------------------------------------------------------------------------------
-- Lifecycle
-------------------------------------------------------------------------------
ns:On("ADDON_LOADED", function(_, loadedName)
	if loadedName ~= addonName then return end
	ns.IsPaladin = IsPlayerPaladin()
	if not ns.IsPaladin then return end

	local isFresh = (RetPulseDB == nil)
	RetPulseDB = RetPulseDB or {}
	if isFresh then
		RetPulseDB.schema = DEFAULTS.schema
	else
		local schema = RetPulseDB.schema or 1
		if schema < 2 then
			RetPulseDB.showOutOfCombat = true
			schema = 2
		end
		if schema < 3 then
			RetPulseDB.position = { point = "BOTTOM", relativePoint = "BOTTOM", x = 0, y = 220 }
			schema = 3
		end
		if schema < 4 then
			RetPulseDB.bracketMode = "video"
			schema = 4
		end
		if schema < 5 then
			if RetPulseDB.combatOnly ~= false then
				RetPulseDB.visibility = "combat"
			elseif RetPulseDB.showOutOfCombat then
				RetPulseDB.visibility = "always"
			else
				RetPulseDB.visibility = "target"
			end
			RetPulseDB.traceEnabled = false
			RetPulseDB.logEnabled = false
			schema = 5
		end
		RetPulseDB.schema = schema
	end
	RetPulseDB = ApplyDefaults(RetPulseDB, DEFAULTS)
	ns.db = RetPulseDB
	ns:SyncVisibilityFields()
	ns.db.bracketsIcy = (ns.db.bracketMode == "icy")
	ns.db.lastLoad = date("%Y-%m-%d %H:%M:%S")

	for _, module in ipairs(ns.modules) do
		if module.OnInitialize then
			local ok, err = pcall(module.OnInitialize, module)
			if not ok then
				ns:Print("|cffff5555" .. module.name .. ":OnInitialize|r", err)
				ns:RecordError(module.name .. ":OnInitialize", err)
			end
		end
	end
end)

ns:On("PLAYER_LOGIN", function()
	if not ns.IsPaladin then return end
	for _, module in ipairs(ns.modules) do
		if module.OnLogin then
			local ok, err = pcall(module.OnLogin, module)
			if not ok then
				ns:Print("|cffff5555" .. module.name .. ":OnLogin|r", err)
				ns:RecordError(module.name .. ":OnLogin", err)
			end
		end
	end
end)

ns:On("PLAYER_REGEN_ENABLED", function()
	local queue = outOfCombatQueue
	outOfCombatQueue = {}
	for _, fn in ipairs(queue) do fn() end
end)

-------------------------------------------------------------------------------
-- Slash commands
-------------------------------------------------------------------------------
local function ClampScale(value)
	if not value then return nil end
	if value < 0.5 then return 0.5 end
	if value > 2.0 then return 2.0 end
	return value
end

function ns:HandleSlash(msg)
	if not ns.IsPaladin then
		ns:Print("RetPulse only runs on Paladins.")
		return
	end
	if not ns.db then return end

	ns.db.lastSlash = tostring(msg)
	msg = strtrim(msg or "")
	local cmd, rest = msg:match("^(%S*)%s*(.-)$")
	cmd = (cmd or ""):lower()

	if cmd == "" or cmd == "config" then
		if ns.OpenOptions then
			ns:OpenOptions()
		else
			ns:Print("the options panel is not built yet")
		end
		return
	elseif cmd == "lock" then
		ns.db.locked = true
		if ns.SetLocked then ns.SetLocked(true) end
		ns:NotifySetting("locked", true)
		ns:Print("frames locked")
		return
	elseif cmd == "unlock" then
		ns.db.locked = false
		if ns.SetLocked then ns.SetLocked(false) end
		ns:NotifySetting("locked", false)
		ns:Print("frames unlocked, drag them into place")
		return
	elseif cmd == "auto" then
		ns.db.auto = not ns.db.auto
		ns:NotifySetting("auto", ns.db.auto)
		ns:Print("auto seal pairing:", ns.db.auto and "on" or "off, using manual pair")
		return
	elseif cmd == "aoe" then
		ns.db.aoe = not ns.db.aoe
		ns:NotifySetting("aoe", ns.db.aoe)
		ns:Print("Consecration:", ns.db.aoe and "in rotation" or "off")
		return
	elseif cmd == "keybinds" or cmd == "keys" then
		ns.db.showKeybinds = not (ns.db.showKeybinds ~= false)
		ns:NotifySetting("showKeybinds", ns.db.showKeybinds)
		ns:Print("keybind badges:", ns.db.showKeybinds and "on" or "off")
		return
	elseif cmd == "visibility" or cmd == "vis" then
		rest = (rest or ""):lower()
		if rest == "combat" or rest == "target" or rest == "always" then
			ns.db.visibility = rest
			ns:SyncVisibilityFields()
			ns:NotifySetting("visibility", rest)
			ns:Print("visibility:", rest)
		else
			ns:Print("usage: /retpulse visibility combat | target | always")
		end
		return
	elseif cmd == "log" then
		rest = (rest or ""):lower()
		if rest == "clear" then
			ns.db.combatLog = {}
			ns.db.logLines = 0
			ns:Print("combat log cleared")
		else
			ns.db.logEnabled = not (ns.db.logEnabled == true)
			ns:NotifySetting("logEnabled", ns.db.logEnabled)
			ns:Print("combat log recording:", ns.db.logEnabled and "on" or "off")
		end
		return
	elseif cmd == "trace" then
		local trace = ns:GetModule("Trace")
		rest = (rest or ""):lower()
		if rest == "on" then
			ns.db.traceEnabled = true
			if trace then trace:Start() end
			ns:NotifySetting("traceEnabled", true)
			ns:Print("trace on")
		elseif rest == "off" then
			ns.db.traceEnabled = false
			if trace then trace:Stop() end
			ns:NotifySetting("traceEnabled", false)
			ns:Print("trace off,", ns.db.traceLines or 0, "lines saved")
		elseif rest == "clear" then
			if trace then trace:Clear() end
			ns:Print("trace cleared")
		elseif rest == "dump" then
			if trace then trace:Dump() end
		else
			ns:Print("usage: /retpulse trace on | off | clear | dump")
		end
		return
	elseif cmd == "combat" then
		ns.db.visibility = (ns.db.visibility == "combat") and "always" or "combat"
		ns:SyncVisibilityFields()
		ns:NotifySetting("visibility", ns.db.visibility)
		ns:Print("show only in combat:", ns.db.combatOnly and "on" or "off")
		return
	elseif cmd == "uw" then
		rest = (rest or ""):lower()
		if rest == "on" then
			ns.db.forceUnsealedWrath = true
		elseif rest == "off" then
			ns.db.forceUnsealedWrath = false
		else
			ns.db.forceUnsealedWrath = not ns.db.forceUnsealedWrath
		end
		local engine = ns:GetModule("WeaponEngine")
		if engine then engine:RefreshTalents() end
		ns:NotifySetting("forceUnsealedWrath", ns.db.forceUnsealedWrath)
		ns:Print("Unsealed Wrath tracking:", ns.db.forceUnsealedWrath and "forced on" or "auto detect")
		return
	elseif cmd == "effects" then
		ns.db.effects = not (ns.db.effects ~= false)
		ns:NotifySetting("effects", ns.db.effects)
		ns:Print("holy effects:", ns.db.effects and "on" or "off")
		return
	elseif cmd == "brackets" then
		rest = (rest or ""):lower()
		if rest == "video" or rest == "icy" then
			ns.db.bracketMode = rest
			ns.db.bracketsIcy = (rest == "icy")
			ns:NotifySetting("bracketMode", rest)
			ns:Print("weapon brackets:", rest)
		else
			ns:Print("usage: /retpulse brackets icy | video")
		end
		return
	elseif cmd == "twist" then
		ns.db.twistWithoutTalent = not ns.db.twistWithoutTalent
		ns:NotifySetting("twistWithoutTalent", ns.db.twistWithoutTalent)
		ns:Print("twist without Unsealed Wrath:", ns.db.twistWithoutTalent and "on" or "off")
		return
	elseif cmd == "sound" then
		ns.db.sound = not ns.db.sound
		ns:NotifySetting("sound", ns.db.sound)
		ns:Print("SWAP NOW sound:", ns.db.sound and "on" or "off")
		return
	elseif cmd == "scale" then
		local value = ClampScale(tonumber(rest))
		if not value then
			ns:Print("usage: /retpulse scale 0.5 - 2.0")
			return
		end
		ns.db.scale = value
		if ns.ApplyScale then ns.ApplyScale() end
		ns:NotifySetting("scale", value)
		ns:Print("scale set to", value)
		return
	elseif cmd == "reset" then
		ns.db.position = { point = "BOTTOM", relativePoint = "BOTTOM", x = 0, y = 220 }
		if ns.ApplyPosition then ns.ApplyPosition() end
		ns:Print("position reset")
		return
	elseif cmd == "debug" then
		ns:RunDebug()
		return
	end

	ns:Print("commands: config | lock | unlock | visibility combat|target|always | keybinds | combat | trace on|off|dump | auto | aoe | twist | uw | brackets | log | effects | sound | scale | reset | debug")
end

SLASH_RETPULSE1 = "/retpulse"
SLASH_RETPULSE2 = "/rp"
SlashCmdList.RETPULSE = function(msg)
	ns:HandleSlash(msg)
end

-------------------------------------------------------------------------------
-- Addon compartment (names must match the TOC)
-------------------------------------------------------------------------------
function RetPulse_OnCompartmentClick(_, mouseButton)
	if not ns.IsPaladin then
		ns:Print("RetPulse only runs on Paladins.")
		return
	end
	if mouseButton == "RightButton" then
		if ns.OpenOptions then ns:OpenOptions() end
	elseif ns.ToggleVisibility then
		ns.ToggleVisibility()
	end
end

function RetPulse_OnCompartmentEnter(_, buttonFrame)
	GameTooltip:SetOwner(buttonFrame, "ANCHOR_LEFT")
	GameTooltip:AddLine(addonName)
	if not ns.IsPaladin then
		GameTooltip:AddLine("Paladin only", 0.7, 0.7, 0.7)
	else
		local state = (ns.db and ns.db.enabled) and "|cff33ff99Enabled|r" or "|cffff5555Disabled|r"
		GameTooltip:AddLine("Status: " .. state, 1, 1, 1)
		GameTooltip:AddLine("Left-click: toggle\nRight-click: options", 0.9, 0.9, 0.9)
	end
	GameTooltip:Show()
end

function RetPulse_OnCompartmentLeave()
	GameTooltip:Hide()
end

-------------------------------------------------------------------------------
-- Debug probe: the only thing that can settle what this client allows.
-------------------------------------------------------------------------------
local function Report(label, ...)
	local parts = {}
	local args = { ... }
	for i = 1, 3 do
		local v = args[i]
		if v ~= nil then
			if ns.IsSecret(v) then
				parts[#parts + 1] = "|cffff5555SECRET|r"
			else
				parts[#parts + 1] = tostring(v)
			end
		end
	end
	ns:Print(label .. ":", table.concat(parts, " | "))
end

local function Probe(label, fn)
	local ok, a, b, c = pcall(fn)
	if not ok then
		ns:Print(label .. ":", "|cffff5555error|r", tostring(a))
		return
	end
	Report(label, a, b, c)
end

local function AuraProbe()
	if not C_UnitAuras or not C_UnitAuras.GetAuraDataByIndex then
		ns:Print("auras:", "|cffff5555C_UnitAuras.GetAuraDataByIndex unavailable|r")
		return
	end

	local found = {}
	for i = 1, 40 do
		local callOk, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
		if not callOk then
			found[#found + 1] = "|cffff5555error: " .. tostring(aura) .. "|r"
			break
		end
		if not aura then break end

		local name = aura.name
		local stacks = "--"
		if aura.applications ~= nil then
			stacks = ns.IsSecret(aura.applications) and "SECRET" or tostring(aura.applications)
		end

		if name ~= nil and not ns.IsSecret(name) then
			found[#found + 1] = name .. "[" .. tostring(aura.spellId) .. "] x" .. stacks
		else
			found[#found + 1] = "|cffff5555SECRET|r[" .. tostring(aura.spellId) .. "] x" .. stacks
		end
		if #found >= 12 then break end
	end

	ns:Print("auras:", #found > 0 and table.concat(found, ", ") or "none")
end

function ns:RunDebug()
	debugBuffer = {}
	ns:Print("=== RetPulse debug ===")

	local ok, err = pcall(function()
	local version, build, buildDate, toc = GetBuildInfo()
	ns:Print("client:", tostring(version), tostring(build), tostring(buildDate), "toc", tostring(toc))
	ns:Print("project:", tostring(WOW_PROJECT_ID), "camelot", tostring(WOW_PROJECT_CAMELOT), "IsForever", tostring(ns.IsForever))

	Probe("SpellIDs", function()
		if not C_Spell or not C_Spell.GetSpellIDForSpellIdentifier then return "missing" end
		local parts = {}
		for key, name in pairs(ns.SPELLS) do
			local id = C_Spell.GetSpellIDForSpellIdentifier(name)
			parts[#parts + 1] = key .. "=" .. tostring(id)
		end
		return table.concat(parts, " ")
	end)

	Probe("KnownByID", function()
		if not C_SpellBook or not C_SpellBook.IsSpellKnown then return "missing" end
		local ids = {
			1310735, -- Unsealed Wrath
			20375,   -- Seal of Command
			20271,   -- Judgement
			678,     -- Holy Strike
			20288,   -- Seal of Righteousness
			1311656, -- Seal of Fury
			26573,   -- Consecration
			20473,   -- Holy Shock
			24275,   -- Hammer of Wrath
			879,     -- Exorcism
		}
		local parts = {}
		for _, id in ipairs(ids) do
			local info = C_Spell.GetSpellInfo(id)
			local nm = (type(info) == "table" and info.name) and info.name or "?"
			local known = C_SpellBook.IsSpellKnown(id)
			parts[#parts + 1] = id .. ":" .. nm .. "=" .. (known and "Y" or "n")
		end
		return table.concat(parts, " ")
	end)

	Probe("UnitLevel", function() return UnitLevel("player") end)
	Probe("UnitClass", function() return UnitClass("player") end)
	Probe("UnitAttackSpeed", function() return UnitAttackSpeed("player") end)
	Probe("UnitPower(player)", function() return UnitPower("player") end)
	Probe("UnitHealth(target)", function() return UnitHealth("target") end)
	Probe("UnitCreatureType", function() return UnitCreatureType("target") end)
	Probe("GetInventoryItemID", function() return GetInventoryItemID("player", 16) end)

	Probe("C_Spell.GetSpellCooldown(Judgement)", function()
		local info = C_Spell.GetSpellCooldown(ns.SPELLS.JUDGEMENT)
		if type(info) ~= "table" then return tostring(info) end
		return info.startTime, info.duration, info.isEnabled
	end)

	Probe("C_Spell.IsSpellUsable(Holy Strike)", function()
		if not C_Spell or not C_Spell.IsSpellUsable then return "missing" end
		return C_Spell.IsSpellUsable(ns.SPELLS.HOLY_STRIKE)
	end)

	Probe("C_SpellBook.IsSpellKnown(Unsealed Wrath)", function()
		if not C_SpellBook or not C_SpellBook.IsSpellKnown then return "missing" end
		local id = C_Spell.GetSpellIDForSpellIdentifier(ns.SPELLS.UNSEALED_WRATH)
		if type(id) ~= "number" then return "no spell id" end
		return id, C_SpellBook.IsSpellKnown(id)
	end)

	Probe("Unsealed Wrath aura", function()
		if not C_UnitAuras or not C_UnitAuras.GetPlayerAuraBySpellID then return "missing" end
		local id = C_Spell.GetSpellIDForSpellIdentifier(ns.SPELLS.UNSEALED_WRATH)
		if type(id) ~= "number" then return "no spell id" end
		local aura = C_UnitAuras.GetPlayerAuraBySpellID(id)
		if not aura then return "not on player", id end
		return "stacks", aura.applications, aura.expirationTime
	end)

	Probe("C_Secrets.ShouldAurasBeSecret", function()
		if not C_Secrets or not C_Secrets.ShouldAurasBeSecret then return "missing" end
		return C_Secrets.ShouldAurasBeSecret()
	end)

	Probe("PLAYER_SWING registrable", function()
		local probe = CreateFrame("Frame")
		local ok = pcall(probe.RegisterEvent, probe, "PLAYER_SWING")
		probe:UnregisterAllEvents()
		return ok and "yes" or "blocked"
	end)

	Probe("C_Spell.IsSpellInRange(Judgement)", function()
		if not C_Spell or not C_Spell.IsSpellInRange then return "missing" end
		return C_Spell.IsSpellInRange(ns.SPELLS.JUDGEMENT, "target")
	end)

	Probe("RangeByName", function()
		if not C_Spell or not C_Spell.IsSpellInRange then return "missing" end
		local j = C_Spell.IsSpellInRange(ns.SPELLS.JUDGEMENT, "target")
		local h = C_Spell.IsSpellInRange(ns.SPELLS.HOLY_STRIKE, "target")
		return "judgement", j, h
	end)

	Probe("CombatState", function()
		local inCombat = InCombatLockdown()
		local hasTarget = UnitExists("target") and UnitCanAttack("player", "target")
		local j = C_Spell.IsSpellInRange and C_Spell.IsSpellInRange(ns.SPELLS.JUDGEMENT, "target")
		local h = C_Spell.IsSpellInRange and C_Spell.IsSpellInRange(ns.SPELLS.HOLY_STRIKE, "target")
		return "combat", tostring(inCombat), "target " .. tostring(hasTarget), "J " .. tostring(j) .. " HS " .. tostring(h)
	end)

	Probe("Secrecy", function()
		if not C_Secrets or not C_Secrets.ShouldAurasBeSecret then return "missing" end
		return "aurasSecret", tostring(C_Secrets.ShouldAurasBeSecret()),
			"cooldownSecret", tostring(C_Secrets.ShouldCooldownsBeSecret and C_Secrets.ShouldCooldownsBeSecret())
	end)

	Probe("C_SwingTimer", function()
		if not C_SwingTimer then return "missing" end
		return C_SwingTimer.IsTargetWithinSwingRange(Enum.PlayerSwingType.MainHand)
	end)

	local tracker = ns:GetModule("CombatTracker")
	local engine = ns:GetModule("WeaponEngine")
	ns:Print("tracker:", "seal", tostring(tracker and tracker:GetActiveSeal()),
		"echoes", tostring(tracker and tracker:GetEchoes()),
		"auraReadable", tostring(tracker and tracker.auraReadable),
		"swings", tostring(tracker and tracker.swingsTotal), "missed", tostring(tracker and tracker.swingsMissed),
		"missRate", tostring(tracker and tracker.swingsTotal and tracker.swingsTotal > 0
			and string.format("%.1f%%", 100 * (tracker.swingsMissed or 0) / tracker.swingsTotal) or "0%"),
		"unsealedWrath", tostring(engine and engine.hasUnsealedWrath),
		"bracket", tostring(engine and engine:GetBracket()),
		"sealCasts", tostring(tracker and tracker.sealCasts),
		"lastCast", tostring(tracker and tracker.lastCastName),
		"cdm", tostring(tracker and tracker.cdmReport),
		"expiresIn", tostring(tracker and tracker.sealExpiresAt and (tracker.sealExpiresAt - GetTime())))

	ns:Print("swing:", tostring(tracker and tracker:GetSwingRemaining()), "progress", tostring(tracker and tracker:GetSwingProgress()),
		"events", tostring(tracker and tracker.swingEvents),
		"accepted", tostring(tracker and tracker.swingAccepted),
		"rejected", tostring(tracker and tracker.swingRejected))

	local db = ns.db
	if db then
		local pos = db.position or {}
		ns:Print("ui:", "built", tostring(db.uiBuilt), "shown", tostring(db.uiShown),
			"scale", tostring(db.scale), "point", tostring(pos.point), "y", tostring(pos.y))
		ns:Print("lastError:", tostring(db.lastError or "none"))
	end

	AuraProbe()
	end)
	if not ok then
		ns:Print("ERROR:", tostring(err))
	end

	local diag = ns:GetModule("Diag")
	if diag then diag:Flush() end
	if ns.db then ns:Print("combatLog:", tostring(ns.db.logLines or 0), "lines saved") end

	ns:Print("=== end ===")

	local db = ns.db
	if db then
		db.debugLog = debugBuffer
		db.debugAt = date("%Y-%m-%d %H:%M:%S")
	end
	debugBuffer = nil

	ns:Print("|cff33ff99saved to RetPulseDB.debugLog|r. Type |cffffffff/reload|r to flush it to disk, then tell the agent it is ready.")
end
