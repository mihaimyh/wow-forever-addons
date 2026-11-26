local addonName, ns = ...

-------------------------------------------------------------------------------
-- LevelPulse — Smart XP Buff & Leveling Telemetry Advisor for WoW: Forever
-------------------------------------------------------------------------------
ns.addonName = addonName
ns.IsForever = WOW_PROJECT_ID == (WOW_PROJECT_CAMELOT or 18)
ns.MAX_LEVEL = 60

local DEFAULTS = {
	enabled = true,
	locked = true,
	scale = 1.0,
	visibility = "pill",         -- "pill" (Adaptive Command Pill) | "alerts" (hide when fully buffed) | "always"
	smartContext = true,         -- suppress consumable nags in Inns/Cities, Mounted, and on Flight Paths
	earlyRefreshSeconds = 90,    -- remind when < 90s remain on Well Fed / Camp / Well-Rested
	snoozeMinutes = 15,          -- Right-click snooze duration (minutes)
	foodMode = "best",           -- "best" (highest usable level/stats) | "cheapest" (lowest vendor price / biggest stack)
	foodTierAlerts = true,       -- announce newly unlocked Well Fed food bracket on level-up
	trackFood = true,            -- Well Fed (+5% kill XP)
	trackCampfireSit = true,     -- /sit when Campfire Nearby (1283391) is detected
	trackCampfirePlace = true,   -- place own Basic/Journeyman/Expert Campfire outdoors
	trackSleepingBag = true,     -- Cozy Sleeping Bag (+1..3% XP, 2h)
	trackStudentFodder = true,   -- Student Fodder (Rested XP chunk)
	trackElixirs = false,        -- opt-in: suggest stat Elixirs carried in bags
	trackWeaponStones = false,   -- opt-in: suggest Sharpening / Weightstones carried in bags
	readySound = true,           -- subtle chime when eating / camping / 3/3 sleeping bag completes
	promptSound = false,         -- optional sound when a new XP buff becomes missing
	forceAtMaxLevel = false,     -- allow testing HUD at level 60
	position = { point = "TOP", relativePoint = "TOP", x = 0, y = -110 },
}

local CHAR_DEFAULTS = {
	lastCampCompletedAt = 0,
	snoozedUntil = {},
}

ns.DEFAULTS = DEFAULTS
ns.CHAR_DEFAULTS = CHAR_DEFAULTS

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
-- Secret-value & safety helpers (Forever 16001)
-------------------------------------------------------------------------------
function ns.IsSecret(value)
	if value == nil then return false end
	if issecretvalue ~= nil and issecretvalue(value) then return true end
	if issecrettable ~= nil and issecrettable(value) then return true end
	return false
end

function ns.IsReadable(value)
	if value == nil then return false end
	if ns.IsSecret(value) then return false end
	local t = type(value)
	return t == "number" or t == "string" or t == "boolean"
end

function ns.SafeBool(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, val = pcall(fn, ...)
	if not ok or not ns.IsReadable(val) then return nil end
	return val and true or false
end

function ns.AreAurasSecret()
	if C_Secrets and C_Secrets.ShouldAurasBeSecret then
		local ok, secret = pcall(C_Secrets.ShouldAurasBeSecret)
		if ok and not ns.IsSecret(secret) and secret == true then
			return true
		end
	end
	return false
end

function ns.DefaultPosition()
	return { point = "TOP", relativePoint = "TOP", x = 0, y = -110 }
end

function ns:Print(...)
	local count = select("#", ...)
	local parts = {}
	for i = 1, count do
		local v = select(i, ...)
		parts[i] = ns.IsSecret(v) and "SECRET" or tostring(v)
	end
	print("|cffefc761" .. addonName .. "|r:", table.concat(parts, " "))
end

function ns:RecordError(where, err)
	if ns.db then
		ns.db.lastError = tostring(where) .. ": " .. tostring(err) .. " @ " .. tostring(date("%H:%M:%S"))
	end
end

-------------------------------------------------------------------------------
-- Event dispatcher & Out-of-Combat queue
-------------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local handlers = {}

function ns:On(event, fn)
	if not handlers[event] then
		handlers[event] = {}
		pcall(eventFrame.RegisterEvent, eventFrame, event)
	end
	table.insert(handlers[event], fn)
end

function ns:Off(event, fn)
	local list = handlers[event]
	if not list then return end
	for i = #list, 1, -1 do
		if list[i] == fn then table.remove(list, i) end
	end
	if #list == 0 then
		handlers[event] = nil
		pcall(eventFrame.UnregisterEvent, eventFrame, event)
	end
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
	local list = handlers[event]
	if not list then return end
	for _, fn in ipairs(list) do
		fn(event, ...)
	end
end)

local outOfCombatQueue = {}

function ns:RunOutOfCombat(fn)
	if InCombatLockdown and InCombatLockdown() then
		table.insert(outOfCombatQueue, fn)
	else
		fn()
	end
end

ns:On("PLAYER_REGEN_ENABLED", function()
	local queue = outOfCombatQueue
	outOfCombatQueue = {}
	for _, fn in ipairs(queue) do fn() end
end)

-------------------------------------------------------------------------------
-- Module registry & lifecycle
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

function ns:NotifySetting()
	local ui = ns:GetModule("UI")
	if ui and ui.Refresh then ui:Refresh() end
end

ns:On("ADDON_LOADED", function(_, loadedName)
	if loadedName ~= addonName then return end
	LevelPulseDB = ApplyDefaults(LevelPulseDB or {}, DEFAULTS)
	LevelPulseCharDB = ApplyDefaults(LevelPulseCharDB or {}, CHAR_DEFAULTS)
	ns.db = LevelPulseDB
	ns.char = LevelPulseCharDB
	ns.db.lastLoad = date("%Y-%m-%d %H:%M:%S")

	for _, module in ipairs(ns.modules) do
		if module.OnInitialize then
			local ok, err = pcall(module.OnInitialize, module)
			if not ok then
				ns:RecordError(module.name .. ":OnInitialize", err)
			end
		end
	end
end)

ns:On("PLAYER_LOGIN", function()
	for _, module in ipairs(ns.modules) do
		if module.OnLogin then
			local ok, err = pcall(module.OnLogin, module)
			if not ok then
				ns:RecordError(module.name .. ":OnLogin", err)
			end
		end
	end
end)

-------------------------------------------------------------------------------
-- Slash commands (/levelpulse, /lp) & Addon Compartment
-------------------------------------------------------------------------------
local function ClampScale(value)
	if not value then return nil end
	if value < 0.5 then return 0.5 end
	if value > 2.0 then return 2.0 end
	return value
end

function ns:HandleSlash(msg)
	if not ns.db then return end
	msg = strtrim(msg or "")
	local cmd, rest = msg:match("^(%S*)%s*(.-)$")
	cmd = (cmd or ""):lower()

	if cmd == "" or cmd == "config" or cmd == "options" then
		if ns.OpenOptions then ns:OpenOptions() end
		return
	elseif cmd == "lock" then
		ns.db.locked = true
		local cfg = ns:GetModule("Config")
		if cfg and cfg.Sync then cfg:Sync("locked") end
		if ns.SetLocked then ns.SetLocked(true) end
		ns:Print("HUD locked")
		return
	elseif cmd == "unlock" then
		ns.db.locked = false
		local cfg = ns:GetModule("Config")
		if cfg and cfg.Sync then cfg:Sync("locked") end
		if ns.SetLocked then ns.SetLocked(false) end
		ns:Print("HUD unlocked — drag anywhere on the bar, then type /lp lock")
		return
	elseif cmd == "reset" then
		ns.db.position = ns.DefaultPosition()
		if ns.ApplyPosition then ns.ApplyPosition() end
		ns:Print("HUD position reset")
		return
	elseif cmd == "resetxp" then
		local tel = ns:GetModule("Telemetry")
		if tel and tel.ResetSession then tel:ResetSession() end
		ns:NotifySetting()
		ns:Print("XP/hr session reset")
		return
	elseif cmd == "unsnooze" or cmd == "clear" then
		local adv = ns:GetModule("Advisor")
		if adv and adv.ClearSnoozes then adv:ClearSnoozes() end
		ns:NotifySetting()
		ns:Print("snoozed reminders cleared")
		return
	elseif cmd == "scale" then
		local s = ClampScale(tonumber(rest))
		if not s then
			ns:Print("usage: /lp scale 0.5 - 2.0")
			return
		end
		ns.db.scale = s
		if ns.ApplyScale then ns.ApplyScale() end
		ns:Print("scale set to", s)
		return
	elseif cmd == "food" or cmd == "foods" or cmd == "guide" then
		local fg = ns:GetModule("FoodGuide")
		local ui = ns:GetModule("UI")
		if fg and fg.PrintGuide then fg:PrintGuide(tonumber(rest)) end
		if ui and ui.ToggleFoodDrawer then ui:ToggleFoodDrawer(true) end
		return
	elseif cmd == "status" or cmd == "debug" then
		local scan = ns:GetModule("Scanner")
		local adv = ns:GetModule("Advisor")
		local tel = ns:GetModule("Telemetry")
		if scan and scan.ScanAll then scan:ScanAll() end
		ns:Print("=== LevelPulse status ===")
		if tel and tel.DebugLine then ns:Print(tel:DebugLine()) end
		if scan and scan.DebugLine then ns:Print(scan:DebugLine()) end
		if adv and adv.DebugLine then ns:Print(adv:DebugLine()) end
		return
	end

	ns:Print("commands: config | food | lock | unlock | reset | resetxp | unsnooze | scale <0.5-2.0> | status")
end

SLASH_LEVELPULSE1 = "/levelpulse"
SLASH_LEVELPULSE2 = "/lp"
SlashCmdList.LEVELPULSE = function(msg)
	ns:HandleSlash(msg)
end

function LevelPulse_OnCompartmentClick(_, mouseButton)
	if mouseButton == "RightButton" then
		if ns.OpenOptions then ns:OpenOptions() end
	else
		if not ns.db then return end
		ns.db.enabled = not ns.db.enabled
		ns:NotifySetting()
		ns:Print(ns.db.enabled and "enabled" or "disabled")
	end
end

function LevelPulse_OnCompartmentEnter(_, buttonFrame)
	if not GameTooltip then return end
	GameTooltip:SetOwner(buttonFrame, "ANCHOR_LEFT")
	GameTooltip:AddLine(addonName)
	local state = (ns.db and ns.db.enabled) and "|cff73e666Enabled|r" or "|cffff5555Disabled|r"
	GameTooltip:AddLine("Status: " .. state, 1, 1, 1)
	GameTooltip:AddLine("Left-click: toggle HUD\nRight-click: options", 0.9, 0.9, 0.9)
	GameTooltip:Show()
end

function LevelPulse_OnCompartmentLeave()
	if GameTooltip then GameTooltip:Hide() end
end
