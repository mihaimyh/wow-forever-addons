local addonName, ns = ...

ns.addonName = addonName
ns.IsForever = WOW_PROJECT_ID == (WOW_PROJECT_CAMELOT or 18)

local DEFAULTS = {
	enabled = true,
	locked = false,
	scale = 1.0,
	buyPct = 0.70,          -- flip if minBuyout <= buyPct * market
	minSaleRate = 40,       -- region sale rate percent (0-100)
	minStackValue = 100,    -- copper; ignore tiny stacks
	vendorRatio = 0.90,     -- vendor if vendorsell >= this * AH floor
	holdMarketVsHist = 0.55,-- hold if market < this * historical
	maxFlipRows = 25,
	maxBagRows = 40,
	autoRefresh = true,       -- rescan while panel is open
	autoRefreshSeconds = 15,  -- full rescan interval (bags dirty still refreshes sooner)
	tooltip = true,           -- append GoldPulse advice on item tooltips
	-- Posting (deposit + duration aware)
	autoPostWhenAH = false,   -- opt-in: start queue when AH opens
	postInterval = 0.75,
	postDuration = 2,         -- 1=12h 2=24h 3=48h (overridden when autoDuration)
	autoDuration = true,      -- pick shorter duration when sale rate is high
	minPostPct = 0.80,        -- never undercut below this %% of dbmarket
	undercutCopper = 1,
	minDepositCopper = 100,   -- Forever min deposit floor (1s); set 1 if hotfixed to 1c
	depositCover = 2.0,       -- require net-if-sold >= deposit * cover
	ahCutKeep = 0.95,         -- faction AH keeps 95%
	minExpectedCopper = 0,    -- EV after deposit risk must be >= this
	schema = 1,
	position = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 120 },
}

ns.DEFAULTS = DEFAULTS

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
-- Events
-------------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local handlers = {}

function ns:On(event, fn)
	if not handlers[event] then
		handlers[event] = {}
		pcall(eventFrame.RegisterEvent, eventFrame, event)
	end
	handlers[event][#handlers[event] + 1] = fn
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
	local list = handlers[event]
	if not list then return end
	for i = 1, #list do
		local ok, err = pcall(list[i], event, ...)
		if not ok then
			ns:Print("|cffff5555" .. event .. "|r", err)
			ns:RecordError(event, err)
		end
	end
end)

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

function ns:Print(...)
	local parts = { "|cffc9a227GoldPulse|r" }
	for i = 1, select("#", ...) do
		parts[#parts + 1] = tostring(select(i, ...))
	end
	print(table.concat(parts, " "))
end

function ns:RecordError(where, err)
	if not ns.db then return end
	ns.db.lastError = {
		where = tostring(where),
		err = tostring(err),
		at = date("%Y-%m-%d %H:%M:%S"),
	}
end

function ns:IsSecret(value)
	if value == nil then return false end
	if issecretvalue and issecretvalue(value) then return true end
	if issecrettable and issecrettable(value) then return true end
	return false
end

function ns:DefaultPosition()
	return { point = "CENTER", relativePoint = "CENTER", x = 0, y = 120 }
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

-------------------------------------------------------------------------------
-- Lifecycle
-------------------------------------------------------------------------------
ns:On("ADDON_LOADED", function(_, loadedName)
	if loadedName ~= addonName then return end

	GoldPulseDB = GoldPulseDB or {}
	GoldPulseDB.schema = GoldPulseDB.schema or DEFAULTS.schema
	GoldPulseDB = ApplyDefaults(GoldPulseDB, DEFAULTS)
	ns.db = GoldPulseDB
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

-------------------------------------------------------------------------------
-- Slash
-------------------------------------------------------------------------------
function ns:HandleSlash(msg)
	msg = (msg or ""):match("^%s*(.-)%s*$") or ""
	local cmd, rest = msg:match("^(%S+)%s*(.*)$")
	cmd = cmd and cmd:lower() or "show"

	if cmd == "show" or cmd == "toggle" or cmd == "" then
		local ui = ns:GetModule("UI")
		if ui and ui.Toggle then ui:Toggle() end
		return
	elseif cmd == "scan" then
		local bags = ns:GetModule("Bags")
		local flips = ns:GetModule("Flips")
		if bags then bags:Scan() end
		if flips then flips:Scan() end
		local ui = ns:GetModule("UI")
		if ui and ui.Refresh then ui:Refresh(true) end
		ns:Print("scanned bags + flip watchlist")
		return
	elseif cmd == "lock" then
		ns.db.locked = true
		ns:NotifySetting("locked", true)
		ns:Print("locked")
		return
	elseif cmd == "unlock" then
		ns.db.locked = false
		ns:NotifySetting("locked", false)
		ns:Print("unlocked — drag the panel")
		return
	elseif cmd == "config" or cmd == "options" then
		if ns.OpenOptions then ns:OpenOptions() end
		return
	elseif cmd == "status" then
		local prices = ns:GetModule("Prices")
		local st = prices and prices:GetStatus() or {}
		ns:Print("TSM:", st.tsm and "yes" or "no",
			"| data:", st.hasData and "ok" or "missing",
			"|", st.detail or "")
		return
	elseif cmd == "post" then
		local posting = ns:GetModule("Posting")
		if not posting then return end
		if rest == "stop" then
			posting:StopAuto("slash")
		elseif rest == "queue" then
			local q = posting:BuildQueue()
			ns:Print(string.format("post queue: %d (skipped %d)", #q, posting.skipped or 0))
			ns:Print(posting:DescribeLastBuild())
		else
			posting:StartAuto()
		end
		return
	end

	ns:Print("commands: show | scan | post [stop|queue] | lock | unlock | config | status")
end

SLASH_GOLDPULSE1 = "/goldpulse"
SLASH_GOLDPULSE2 = "/gp"
SlashCmdList.GOLDPULSE = function(msg)
	ns:HandleSlash(msg)
end

-------------------------------------------------------------------------------
-- Addon compartment
-------------------------------------------------------------------------------
function GoldPulse_OnCompartmentClick(_, mouseButton)
	if mouseButton == "RightButton" then
		if ns.OpenOptions then ns:OpenOptions() end
	else
		local ui = ns:GetModule("UI")
		if ui and ui.Toggle then ui:Toggle() end
	end
end

function GoldPulse_OnCompartmentEnter(_, buttonFrame)
	GameTooltip:SetOwner(buttonFrame, "ANCHOR_LEFT")
	GameTooltip:AddLine(addonName)
	GameTooltip:AddLine("Left-click: toggle panel", 1, 1, 1)
	GameTooltip:AddLine("Right-click: options", 0.9, 0.9, 0.9)
	GameTooltip:AddLine("/gp scan — refresh advice", 0.7, 0.7, 0.7)
	GameTooltip:Show()
end

function GoldPulse_OnCompartmentLeave()
	GameTooltip:Hide()
end
