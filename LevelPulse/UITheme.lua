local addonName, ns = ...

-------------------------------------------------------------------------------
-- DungeonJournal-inspired visual theme for WoW: Forever (Interface 16001)
-- Matches ForeverDungeonJournal's warm obsidian-stone, bronze-gold rounded
-- UI-Tooltip-Border / UI-DialogBox-Border chrome, parchment accents, and own fonts.
-------------------------------------------------------------------------------
local UITheme = {
	-- Palette aligned with ForeverDungeonJournal & RunTracker
	GOLD         = { 1.00, 0.78, 0.20 },
	GOLD_BRIGHT  = { 1.00, 0.84, 0.32 },
	GOLD_LINE    = { 0.68, 0.52, 0.20, 0.60 },
	BORDER       = { 0.48, 0.40, 0.27, 1.00 },
	BORDER_WARM  = { 0.54, 0.39, 0.17, 1.00 },
	BORDER_READY = { 0.32, 0.66, 0.26, 1.00 },
	BORDER_WARN  = { 0.78, 0.50, 0.16, 1.00 },
	BORDER_CAMP  = { 0.82, 0.44, 0.16, 1.00 },

	BG_TRACKER   = { 0.068, 0.062, 0.054, 0.93 },
	BG_HEADER    = { 0.140, 0.100, 0.055, 0.94 },
	BG_STONE     = { 0.045, 0.042, 0.037, 0.99 },
	BG_PARCHMENT = { 0.150, 0.115, 0.070, 0.96 },
	BG_ROW       = { 0.220, 0.150, 0.070, 0.93 },
	BG_ROW_HOVER = { 0.350, 0.230, 0.090, 0.98 },
	BG_PILL      = { 0.115, 0.105, 0.095, 0.94 },
	BG_PILL_OK   = { 0.080, 0.170, 0.075, 0.95 },
	BG_PILL_WARN = { 0.210, 0.135, 0.055, 0.95 },
	BG_ACTION    = { 0.200, 0.135, 0.055, 0.96 },

	IVORY        = { 0.96, 0.94, 0.89 },
	TEXT_WARM    = { 0.93, 0.86, 0.72 },
	MUTED        = { 0.72, 0.67, 0.58 },
	READY        = { 0.42, 0.94, 0.42 },
	WARN         = { 1.00, 0.68, 0.22 },
	RESTED       = { 0.38, 0.74, 1.00 },
	CAMP         = { 1.00, 0.58, 0.24 },
	TRACK        = { 0.02, 0.02, 0.03, 0.85 },

	SOLID          = "Interface\\Buttons\\WHITE8X8",
	ROCK_BG        = "Interface\\FrameGeneral\\UI-Background-Rock",
	PARCHMENT_TEX  = "Interface\\QuestFrame\\QuestBG",
	BORDER_TOOLTIP = "Interface\\Tooltips\\UI-Tooltip-Border",
	BORDER_DIALOG  = "Interface\\DialogFrame\\UI-DialogBox-Border",
	STATUSBAR_TEX  = "Interface\\TargetingFrame\\UI-StatusBar",
	QUEST_HL       = "Interface\\QuestFrame\\UI-QuestTitleHighlight",

	-- HUD dimensions (compact RunTracker-style card + expandable 1-Click action tray)
	PILL_W   = 288,
	PILL_H   = 98,
	ACTION_W = 288,
	ACTION_H = 148,
	ICON_SZ  = 36,
	ACCENT_W = 2,

	DRAWER_W = 368,
}

-------------------------------------------------------------------------------
-- Dedicated Font Objects (prevents ElvUI/Tukui font-replacement smudges)
-------------------------------------------------------------------------------
UITheme.Fonts = {}

local FONT_SPECS = {
	Title  = { file = "Fonts\\FRIZQT__.TTF", size = 12, flags = "", shadow = { 1, -1 }, color = { 1.00, 0.78, 0.20 } },
	Header = { file = "Fonts\\FRIZQT__.TTF", size = 14, flags = "", shadow = { 1, -1 }, color = { 0.96, 0.79, 0.25 } },
	Metric = { file = "Fonts\\FRIZQT__.TTF", size = 15, flags = "", shadow = { 1, -1 }, color = { 1.00, 1.00, 1.00 } },
	Body   = { file = "Fonts\\FRIZQT__.TTF", size = 11, flags = "", shadow = { 1, -1 }, color = { 0.95, 0.92, 0.86 } },
	Label  = { file = "Fonts\\FRIZQT__.TTF", size = 10, flags = "", shadow = { 1, -1 }, color = { 0.72, 0.67, 0.58 } },
	Small  = { file = "Fonts\\FRIZQT__.TTF", size = 10, flags = "", shadow = { 1, -1 }, color = { 0.92, 0.88, 0.80 } },
}

local function InitOwnFonts()
	if type(CreateFont) ~= "function" then return end
	for key, spec in pairs(FONT_SPECS) do
		local globalName = "LevelPulseFont_" .. key
		local f = _G[globalName]
		if not f then
			local ok, created = pcall(CreateFont, globalName)
			if ok and created then
				f = created
				if f.SetFont then pcall(f.SetFont, f, spec.file, spec.size, spec.flags) end
				if spec.color and f.SetTextColor then
					pcall(f.SetTextColor, f, spec.color[1], spec.color[2], spec.color[3], 1)
				end
				if spec.shadow and f.SetShadowOffset and f.SetShadowColor then
					pcall(f.SetShadowOffset, f, spec.shadow[1], spec.shadow[2])
					pcall(f.SetShadowColor, f, 0, 0, 0, 0.95)
				end
			end
		end
		UITheme.Fonts[key] = f
	end
end
InitOwnFonts()

function UITheme.Font(key, fallback)
	local globalName = "LevelPulseFont_" .. tostring(key)
	if _G[globalName] then
		return globalName
	end
	return fallback or "GameFontHighlightSmall"
end

function UITheme.MakeFontString(parent, layer, fontKey, fallbackTemplate)
	local fs = parent:CreateFontString(nil, layer or "OVERLAY", fallbackTemplate or "GameFontHighlightSmall")
	local fontObj = UITheme.Fonts and UITheme.Fonts[fontKey]
	if fontObj and fs and fs.SetFontObject then
		pcall(fs.SetFontObject, fs, fontObj)
	end
	return fs
end

-------------------------------------------------------------------------------
-- Pixel & Backdrop Helpers (DungeonJournal Chrome)
-------------------------------------------------------------------------------
function UITheme.SetPixelSize(region, w, h)
	if PixelUtil and PixelUtil.SetSize then
		PixelUtil.SetSize(region, w, h)
	else
		region:SetSize(w, h)
	end
end

function UITheme.SetPixelWidth(region, w)
	if PixelUtil and PixelUtil.SetWidth then
		PixelUtil.SetWidth(region, w)
	else
		region:SetWidth(w)
	end
end

function UITheme.SetPixelHeight(region, h)
	if PixelUtil and PixelUtil.SetHeight then
		PixelUtil.SetHeight(region, h)
	else
		region:SetHeight(h)
	end
end

-- Rounded bronze-bordered tracker backdrop (identical to ForeverDungeonJournalRunTracker)
function UITheme.ApplyTrackerBackdrop(frame)
	if not frame or not frame.SetBackdrop then return end
	frame:SetBackdrop({
		bgFile = UITheme.SOLID,
		edgeFile = UITheme.BORDER_TOOLTIP,
		tile = true,
		tileSize = 16,
		edgeSize = 14,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	local bg, bd = UITheme.BG_TRACKER, UITheme.BORDER
	frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
	frame:SetBackdropBorderColor(bd[1], bd[2], bd[3], bd[4])
end

-- Rounded pill / mini-card backdrop (used for Food/Bag/Camp pills, action card, buttons)
function UITheme.ApplyPillBackdrop(frame, edgeSize, inset)
	if not frame or not frame.SetBackdrop then return end
	local ins = inset or 2
	frame:SetBackdrop({
		bgFile = UITheme.SOLID,
		edgeFile = UITheme.BORDER_TOOLTIP,
		tile = true,
		tileSize = 16,
		edgeSize = edgeSize or 10,
		insets = { left = ins, right = ins, top = ins, bottom = ins },
	})
	local bg, bd = UITheme.BG_PILL, UITheme.BORDER
	frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
	frame:SetBackdropBorderColor(bd[1], bd[2], bd[3], bd[4])
end

-- Full DungeonJournal dialog chrome (rock background + ornate dialog border)
function UITheme.ApplyJournalWindowBackdrop(frame)
	if not frame or not frame.SetBackdrop then return end
	frame:SetBackdrop({
		bgFile = UITheme.ROCK_BG,
		edgeFile = UITheme.BORDER_DIALOG,
		tile = true,
		tileSize = 16,
		edgeSize = 22,
		insets = { left = 5, right = 5, top = 5, bottom = 5 },
	})
	local bg = UITheme.BG_STONE
	frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
end

-- Legacy alias kept for compatibility
UITheme.ApplyPlateBackdrop = UITheme.ApplyTrackerBackdrop

function UITheme.AddParchmentOverlay(frame, alpha)
	local tex = frame:CreateTexture(nil, "BACKGROUND", nil, -1)
	tex:SetPoint("TOPLEFT", 3, -3)
	tex:SetPoint("BOTTOMRIGHT", -3, 3)
	tex:SetTexture(UITheme.PARCHMENT_TEX)
	tex:SetTexCoord(0, 1, 0, 1)
	if tex.SetVertexColor then
		tex:SetVertexColor(1.00, 0.95, 0.84)
	end
	tex:SetAlpha(alpha or 0.15)
	return tex
end

function UITheme.StylePageArrow(button, isLeft)
	local dir = isLeft and "Prev" or "Next"
	if button.SetNormalTexture then
		button:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. dir .. "Page-Up")
	end
	if button.SetPushedTexture then
		button:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. dir .. "Page-Down")
	end
	if button.SetDisabledTexture then
		button:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. dir .. "Page-Disabled")
	end
	if button.SetHighlightTexture then
		button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
	end
end

function UITheme.FmtDuration(seconds)
	if not seconds or seconds <= 0 then return "0s" end
	if seconds >= 3600 then
		local h = math.floor(seconds / 3600)
		local m = math.floor((seconds % 3600) / 60)
		return m > 0 and string.format("%dh%dm", h, m) or string.format("%dh", h)
	elseif seconds >= 60 then
		local m = math.floor(seconds / 60)
		local s = math.floor(seconds % 60)
		return m >= 10 and string.format("%dm", m) or string.format("%dm%02ds", m, s)
	end
	return string.format("%.0fs", seconds)
end

ns.UITheme = UITheme
