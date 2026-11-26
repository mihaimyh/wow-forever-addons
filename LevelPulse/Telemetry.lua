local addonName, ns = ...

local Telemetry = ns:NewModule("Telemetry")

-- Tracks player level, XP, Rested XP exhaustion, XP/hour, and ETA to next level.
-- UnitXP, UnitXPMax, UnitLevel, and GetXPExhaustion have no secret restrictions on 16001,
-- though all reads remain guarded with ns.IsReadable for absolute safety.

local function ReadNumber(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, val = pcall(fn, ...)
	if not ok or not ns.IsReadable(val) or type(val) ~= "number" then return nil end
	return val
end

function Telemetry:OnInitialize()
	self.level = 1
	self.xp = 0
	self.maxXP = 1
	self.restedXP = 0
	self.sessionStartAt = nil
	self.sessionGainedXP = 0
	self.lastXP = nil
	self.lastMaxXP = nil
	self.lastLevel = nil
end

function Telemetry:OnLogin()
	self:ResetSession()
	self:Update()

	ns:On("PLAYER_XP_UPDATE", function() self:Update() end)
	ns:On("PLAYER_LEVEL_UP", function(_, newLevel)
		self:Update(tonumber(newLevel))
	end)
	ns:On("UPDATE_EXHAUSTION", function() self:Update() end)
	ns:On("PLAYER_ENTERING_WORLD", function() self:Update() end)
end

function Telemetry:ResetSession()
	self.sessionStartAt = GetTime and GetTime() or 0
	self.sessionGainedXP = 0
	self.lastXP = ReadNumber(UnitXP, "player")
	self.lastMaxXP = ReadNumber(UnitXPMax, "player")
	self.lastLevel = ReadNumber(UnitLevel, "player")
end

function Telemetry:Update(overrideLevel)
	local lvl = overrideLevel or ReadNumber(UnitLevel, "player") or self.level or 1
	local curXP = ReadNumber(UnitXP, "player")
	local maxXP = ReadNumber(UnitXPMax, "player")
	local rested = ReadNumber(GetXPExhaustion) or 0

	if curXP ~= nil and maxXP ~= nil and maxXP > 0 then
		if self.lastXP ~= nil and self.lastLevel ~= nil then
			if lvl > self.lastLevel and self.lastMaxXP and self.lastMaxXP > self.lastXP then
				local carry = (self.lastMaxXP - self.lastXP) + curXP
				if carry > 0 then
					self.sessionGainedXP = (self.sessionGainedXP or 0) + carry
				end
			elseif lvl == self.lastLevel and curXP > self.lastXP then
				self.sessionGainedXP = (self.sessionGainedXP or 0) + (curXP - self.lastXP)
			end
		end
		self.xp = curXP
		self.maxXP = maxXP
		self.lastXP = curXP
		self.lastMaxXP = maxXP
	end

	self.level = lvl
	self.lastLevel = lvl
	self.restedXP = math.max(0, rested)
end

function Telemetry:IsMaxLevel()
	if ns.db and ns.db.forceAtMaxLevel then return false end
	return (self.level or 1) >= (ns.MAX_LEVEL or 60)
end

function Telemetry:GetXPProgress()
	if not self.maxXP or self.maxXP <= 0 then return 0 end
	local p = (self.xp or 0) / self.maxXP
	if p < 0 then return 0 end
	if p > 1 then return 1 end
	return p
end

function Telemetry:GetRestedPercent()
	if not self.maxXP or self.maxXP <= 0 then return 0 end
	return math.floor(((self.restedXP or 0) / self.maxXP) * 100 + 0.5)
end

function Telemetry:GetXPPerHour()
	if not self.sessionStartAt or (self.sessionGainedXP or 0) <= 0 then
		return 0
	end
	local now = GetTime and GetTime() or 0
	local elapsed = now - self.sessionStartAt
	if elapsed < 5 then return 0 end
	return math.floor((self.sessionGainedXP / elapsed) * 3600 + 0.5)
end

function Telemetry:GetETASeconds()
	local xph = self:GetXPPerHour()
	if xph <= 0 or not self.maxXP or self.maxXP <= (self.xp or 0) then
		return nil
	end
	local remXP = self.maxXP - (self.xp or 0)
	return math.floor((remXP / xph) * 3600 + 0.5)
end

function Telemetry:FormatCompact(xpBonusPct)
	local bonus = tonumber(xpBonusPct) or 0
	local lvl = self.level or 1
	local progPct = math.floor(self:GetXPProgress() * 100 + 0.5)
	local restedPct = self:GetRestedPercent()
	local xph = self:GetXPPerHour()
	local eta = self:GetETASeconds()

	local parts = {}
	if xph > 0 then
		parts[#parts + 1] = string.format("L%d", lvl)
	else
		parts[#parts + 1] = string.format("Lvl %d (%d%%)", lvl, progPct)
	end
	parts[#parts + 1] = string.format("+%d%% XP", bonus)
	if restedPct > 0 and xph <= 0 then
		parts[#parts + 1] = string.format("Rest %d%%", restedPct)
	end
	if xph >= 1000 then
		parts[#parts + 1] = string.format("%.1fk/h", xph / 1000)
	elseif xph > 0 then
		parts[#parts + 1] = string.format("%d/h", xph)
	end
	if eta and eta > 0 and lvl < (ns.MAX_LEVEL or 60) then
		parts[#parts + 1] = "L" .. tostring(lvl + 1) .. " " .. ns.UITheme.FmtDuration(eta)
	end
	return table.concat(parts, " • ")
end

function Telemetry:DebugLine()
	return string.format("lvl=%d xp=%d/%d rested=%d%% xph=%d",
		self.level or 0, self.xp or 0, self.maxXP or 0,
		self:GetRestedPercent(), self:GetXPPerHour())
end
