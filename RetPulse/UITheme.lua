local addonName, ns = ...

-- RetPulse UI theme tokens for WoW: Forever (16001 / Mainline 12.x).
-- Keep visual constants here so UI.lua / FX.lua stay consistent and Forever-safe:
--   * PixelUtil for sharp 1px borders under UI scale
--   * BackdropTemplate + WHITE8X8 (no NineSlice fighting)
--   * never SetMask spell icons (corrupts textures on Forever)
--   * StatusBar / Cooldown accept secret values for display pass-through
--   * no Classic-era globals

ns.UITheme = ns.UITheme or {}
local T = ns.UITheme

T.MEDIA = "Interface\\AddOns\\RetPulse\\Media\\"
T.SOLID = "Interface\\Buttons\\WHITE8X8"

-- Palette: holy gold on obsidian glass (one accent family, high combat contrast).
T.GOLD       = { 0.94, 0.78, 0.38 }
T.GOLD_DIM   = { 0.94, 0.78, 0.38, 0.32 }
T.IVORY      = { 0.96, 0.95, 0.91 }
T.MUTED      = { 0.72, 0.70, 0.65 }
T.READY      = { 0.62, 1.00, 0.32 }
T.WARN       = { 1.00, 0.60, 0.20 }
T.OOR        = { 1.00, 0.42, 0.38 }
T.OOM        = { 0.38, 0.68, 1.00 }
T.MANA       = { 0.24, 0.56, 0.96 }
T.PLATE_BG   = { 0.05, 0.05, 0.07, 0.90 }
T.TRACK      = { 1, 1, 1, 0.08 }

-- Spacing / sizing (explicit; zero hidden padding).
-- Bottom rail stack needs ~10px inset so StatusBars never sit on the border.
T.PANEL_W = 268
T.PANEL_H = 92
T.PANEL_H_COMPACT = 74
T.MAIN_SIZE = 44
T.NEXT_SIZE = 30
T.PIP_SIZE = 8
T.BORDER_PX = 1
T.ACCENT_W = 2
T.SWING_H = 3
T.MANA_H = 2
T.RAIL_PAD = 10 -- content clears swing+mana rails
T.INSET = 8
T.GAP = 10

T.FADE_SPEED = 8.0
T.IDLE_ALPHA = 0.38
T.POP_DURATION = 0.16
T.FLASH_DURATION = 0.20

T.BACKDROP = {
	bgFile = T.SOLID,
	edgeFile = T.SOLID,
	tile = false,
	edgeSize = T.BORDER_PX,
}

function T.SetPixelSize(region, w, h)
	if PixelUtil and PixelUtil.SetSize then
		PixelUtil.SetSize(region, w, h)
	else
		region:SetSize(w, h)
	end
end

function T.SetPixelHeight(region, h)
	if PixelUtil and PixelUtil.SetHeight then
		PixelUtil.SetHeight(region, h)
	else
		region:SetHeight(h)
	end
end

function T.SetPixelWidth(region, w)
	if PixelUtil and PixelUtil.SetWidth then
		PixelUtil.SetWidth(region, w)
	else
		region:SetWidth(w)
	end
end

function T.ApplyPlateBackdrop(frame)
	frame:SetBackdrop(T.BACKDROP)
	frame:SetBackdropColor(T.PLATE_BG[1], T.PLATE_BG[2], T.PLATE_BG[3], T.PLATE_BG[4])
	frame:SetBackdropBorderColor(T.GOLD_DIM[1], T.GOLD_DIM[2], T.GOLD_DIM[3], T.GOLD_DIM[4])
end

function T.ColorBorder(frame, rgb, a)
	frame:SetBackdropBorderColor(rgb[1], rgb[2], rgb[3], a or 0.85)
end

function T.SetSolid(tex, rgb, a)
	tex:SetColorTexture(rgb[1], rgb[2], rgb[3], a or 1)
end
