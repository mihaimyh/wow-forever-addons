local addonName, ns = ...

local FX = ns:NewModule("FX")

-- Light effects around the main icon, in the spirit of Lueur's layered look:
-- a soft aura, a breathing ring, a burst on SWAP NOW and sparks when an echo is
-- stored. Textures are generated for this addon (Media/*.tga), never borrowed.

local T = ns.UITheme
local MEDIA = (T and T.MEDIA) or "Interface\\AddOns\\RetPulse\\Media\\"
local GOLD = (T and T.GOLD) or { 0.91, 0.76, 0.39 }
local READY = (T and T.READY) or { 0.71, 1.0, 0.24 }
local WARN = (T and T.WARN) or { 1.0, 0.62, 0.18 }

local SPARK_COUNT = 6
local SPARK_LIFE = 0.7
local BURST_LIFE = 0.45

function FX:IsEnabled()
	return ns.db == nil or ns.db.effects ~= false
end

function FX:Attach(anchor, size)
	self.anchor = anchor
	self.size = size
	self.state = "idle"
	self.angle = 0

	local aura = anchor:CreateTexture(nil, "BACKGROUND", nil, 3)
	aura:SetTexture(MEDIA .. "glow")
	aura:SetSize(size * 1.7, size * 1.7)
	aura:SetPoint("CENTER", anchor, "CENTER")
	aura:SetBlendMode("ADD")
	self.aura = aura

	local ring = anchor:CreateTexture(nil, "OVERLAY", nil, 2)
	ring:SetTexture(MEDIA .. "ring")
	ring:SetSize(size * 1.3, size * 1.3)
	ring:SetPoint("CENTER", anchor, "CENTER")
	ring:SetBlendMode("ADD")
	self.ring = ring

	local burst = anchor:CreateTexture(nil, "OVERLAY", nil, 3)
	burst:SetTexture(MEDIA .. "ring")
	burst:SetPoint("CENTER", anchor, "CENTER")
	burst:SetBlendMode("ADD")
	burst:Hide()
	self.burst = burst

	self.sparks = {}
	for i = 1, SPARK_COUNT do
		local spark = anchor:CreateTexture(nil, "OVERLAY", nil, 4)
		spark:SetTexture(MEDIA .. "spark")
		spark:SetSize(size * 0.35, size * 0.35)
		spark:SetBlendMode("ADD")
		spark:Hide()
		self.sparks[i] = { tex = spark, active = false }
	end
end

function FX:SetState(state)
	if self.state == state then return end
	if state == "ready" and self.anchor then
		self:Burst()
	end
	self.state = state
end

function FX:Burst()
	local burst = self.burst
	if not burst or not self.size or not self:IsEnabled() then return end
	burst:SetSize(self.size * 1.2, self.size * 1.2)
	burst:SetAlpha(0.85)
	burst:Show()
	self.burstStart = GetTime()
end

function FX:Spark(count)
	if not self:IsEnabled() or not self.sparks then return end
	local now = GetTime()
	for _ = 1, (count or 1) do
		for _, spark in ipairs(self.sparks) do
			if not spark.active then
				spark.active = true
				spark.start = now
				spark.angle = math.random() * math.pi * 2
				spark.dist = (0.35 + math.random() * 0.45) * (self.size or 40)
				break
			end
		end
	end
end

function FX:SetVisible(visible)
	self.visible = visible
end

function FX:DebugLine()
	local sparks = 0
	for _, spark in ipairs(self.sparks or {}) do
		if spark.active then sparks = sparks + 1 end
	end
	return string.format("fx state=%s visible=%s enabled=%s sparks=%d",
		tostring(self.state), tostring(self.visible), tostring(self:IsEnabled()), sparks)
end

function FX:Update(elapsed)
	if not self.anchor then return end
	local t = GetTime()

	if self.burst and self.burst:IsShown() then
		local progress = (t - (self.burstStart or t)) / BURST_LIFE
		if progress >= 1 then
			self.burst:Hide()
		else
			local scale = 1 + progress * 1.15
			self.burst:SetSize(self.size * 1.2 * scale, self.size * 1.2 * scale)
			self.burst:SetAlpha((1 - progress) * 0.8)
		end
	end

	if not self:IsEnabled() or self.visible == false then
		self.aura:SetAlpha(0)
		self.ring:SetAlpha(0)
		for _, spark in ipairs(self.sparks or {}) do
			spark.active = false
			spark.tex:Hide()
		end
		return
	end

	local color = GOLD
	if self.state == "ready" then
		color = READY
	elseif self.state == "warn" then
		color = WARN
	end

	-- Two breathing rhythms that do not line up, so it never looks like a loop.
	local pulse = 0.5 + 0.5 * math.sin(t * 2.1)
	local slow = 0.5 + 0.5 * math.sin(t * 0.7 + 1.3)

	self.aura:SetAlpha(1)
	self.ring:SetAlpha(1)
	self.aura:SetVertexColor(color[1], color[2], color[3], 0.10 + 0.10 * pulse + 0.06 * slow)
	self.ring:SetVertexColor(color[1], color[2], color[3], 0.09 + 0.09 * pulse)

	for _, spark in ipairs(self.sparks or {}) do
		if spark.active then
			local progress = (t - spark.start) / SPARK_LIFE
			if progress >= 1 then
				spark.active = false
				spark.tex:Hide()
			else
				local distance = spark.dist * (0.35 + progress * 0.9)
				spark.tex:SetPoint("CENTER", self.anchor, "CENTER",
					math.cos(spark.angle) * distance, math.sin(spark.angle) * distance)
				spark.tex:SetVertexColor(color[1], color[2], color[3], (1 - progress) * 0.85)
				spark.tex:Show()
			end
		end
	end
end
