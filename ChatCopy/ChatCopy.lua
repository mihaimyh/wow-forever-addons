local addonName, ns = ...

-- ChatCopy: lightweight, secret-safe chat copy button + /copy popup for WoW: Forever (16001).
-- Zero external libraries, zero taint, works on all classes and chat tabs.

local GOLD  = { 0.94, 0.78, 0.38 }
local IVORY = { 0.96, 0.95, 0.91 }

local function IsSecret(value)
	if value == nil then return false end
	if issecretvalue ~= nil and issecretvalue(value) then return true end
	if issecrettable ~= nil and issecrettable(value) then return true end
	return false
end

local function CleanLine(text)
	if type(text) ~= "string" or IsSecret(text) then return nil end

	-- Replace hyperlinks |H...|h[Label]|h with their readable label.
	local clean = text:gsub("|H.-|h(.-)|h", "%1")
	-- Strip color tags, textures, atlases, and formatting codes.
	clean = clean:gsub("|c%x%x%x%x%x%x%x%x", "")
	clean = clean:gsub("|r", "")
	clean = clean:gsub("|T.-|t", "")
	clean = clean:gsub("|A.-|a", "")
	clean = clean:gsub("|K.-|k", "[BNet]")
	clean = clean:gsub("|n", "\n")
	clean = clean:gsub("||", "|")
	return clean
end

local function CollectMessages(chatFrame)
	if not chatFrame or not chatFrame.GetNumMessages or not chatFrame.GetMessageInfo then
		return ""
	end

	local okCount, count = pcall(chatFrame.GetNumMessages, chatFrame)
	if not okCount or type(count) ~= "number" or IsSecret(count) or count <= 0 then
		return ""
	end

	local lines = {}
	for i = 1, count do
		local okMsg, msg = pcall(chatFrame.GetMessageInfo, chatFrame, i)
		if okMsg and msg ~= nil and not IsSecret(msg) then
			local cleaned = CleanLine(msg)
			if cleaned and cleaned ~= "" then
				lines[#lines + 1] = cleaned
			end
		end
	end

	return table.concat(lines, "\n")
end

-------------------------------------------------------------------------------
-- Copy popup window (dark glass, Esc to close, text pre-selected for Ctrl+C)
-------------------------------------------------------------------------------
local copyFrame

local function GetCopyFrame()
	if copyFrame then return copyFrame end

	local frame = CreateFrame("Frame", "ChatCopyPopupFrame", UIParent, "BackdropTemplate")
	frame:SetSize(560, 340)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("DIALOG")
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetClampedToScreen(true)
	frame:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8X8",
		edgeFile = "Interface\\Buttons\\WHITE8X8",
		tile = false,
		edgeSize = 1,
	})
	frame:SetBackdropColor(0.05, 0.05, 0.07, 0.94)
	frame:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.55)
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:Hide()

	-- Register with UISpecialFrames so pressing Esc closes the popup.
	if UISpecialFrames then
		table.insert(UISpecialFrames, "ChatCopyPopupFrame")
	end

	-- Top highlight sheen
	local sheen = frame:CreateTexture(nil, "BORDER")
	sheen:SetPoint("TOPLEFT", 1, -1)
	sheen:SetPoint("TOPRIGHT", -1, -1)
	sheen:SetHeight(1)
	sheen:SetColorTexture(1, 0.94, 0.78, 0.16)

	-- Title
	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", 12, -10)
	title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
	title:SetText("ChatCopy")

	local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	hint:SetPoint("LEFT", title, "RIGHT", 10, 0)
	hint:SetTextColor(IVORY[1], IVORY[2], IVORY[3], 0.65)
	hint:SetText("Ctrl+C to copy  |  Esc to close")

	-- Close button
	local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	closeBtn:SetPoint("TOPRIGHT", -2, -2)

	-- Scrollable EditBox
	local scroll = CreateFrame("ScrollFrame", "ChatCopyScrollFrame", frame, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 12, -32)
	scroll:SetPoint("BOTTOMRIGHT", -32, 12)

	local editBox = CreateFrame("EditBox", nil, scroll)
	editBox:SetMultiLine(true)
	editBox:SetAutoFocus(false)
	editBox:SetFontObject("ChatFontNormal")
	editBox:SetWidth(508)
	editBox:SetScript("OnEscapePressed", function()
		frame:Hide()
	end)
	editBox:SetScript("OnTextChanged", function(self)
		scroll:UpdateScrollChildRect()
	end)

	scroll:SetScrollChild(editBox)

	-- Clicking anywhere in the scroll area focuses & highlights the editBox.
	scroll:EnableMouse(true)
	scroll:SetScript("OnMouseDown", function()
		editBox:SetFocus()
	end)

	frame.editBox = editBox
	frame.scroll = scroll
	copyFrame = frame
	return frame
end

function ns.OpenCopyWindow(chatFrame)
	local target = chatFrame or SELECTED_CHAT_FRAME or ChatFrame1
	local text = CollectMessages(target)

	local frame = GetCopyFrame()
	frame.editBox:SetText(text)
	frame:Show()
	frame.editBox:SetFocus()
	frame.editBox:HighlightText()

	-- Scroll to the bottom so the newest lines are visible.
	if C_Timer and C_Timer.After then
		C_Timer.After(0, function()
			if frame:IsShown() and frame.scroll and frame.scroll.GetVerticalScrollRange then
				local maxScroll = frame.scroll:GetVerticalScrollRange()
				if maxScroll and maxScroll > 0 then
					frame.scroll:SetVerticalScroll(maxScroll)
				end
			end
		end)
	end
end

-------------------------------------------------------------------------------
-- Discreet bottom-right button on each chat frame
-------------------------------------------------------------------------------
local attached = {}

local function AttachButton(chatFrame)
	if not chatFrame or attached[chatFrame] then return end
	if type(chatFrame.IsForbidden) == "function" then
		local okF, forbidden = pcall(chatFrame.IsForbidden, chatFrame)
		if not okF or forbidden then return end
	end
	attached[chatFrame] = true

	local btn = CreateFrame("Button", nil, chatFrame, "BackdropTemplate")
	btn:SetSize(22, 22)
	btn:SetPoint("BOTTOMRIGHT", chatFrame, "BOTTOMRIGHT", -4, 4)
	btn:SetFrameLevel((chatFrame:GetFrameLevel() or 1) + 5)
	btn:SetAlpha(0.28)
	btn:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8X8",
		edgeFile = "Interface\\Buttons\\WHITE8X8",
		tile = false,
		edgeSize = 1,
	})
	btn:SetBackdropColor(0.05, 0.05, 0.07, 0.85)
	btn:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.5)

	local icon = btn:CreateTexture(nil, "ARTWORK")
	icon:SetPoint("TOPLEFT", 3, -3)
	icon:SetPoint("BOTTOMRIGHT", -3, 3)
	icon:SetTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Up")

	btn:SetScript("OnEnter", function(self)
		self:SetAlpha(1.0)
		self:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.95)
		if GameTooltip then
			GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
			GameTooltip:AddLine("ChatCopy", GOLD[1], GOLD[2], GOLD[3])
			GameTooltip:AddLine("Click to copy chat (Ctrl+C)", 1, 1, 1)
			GameTooltip:Show()
		end
	end)

	btn:SetScript("OnLeave", function(self)
		self:SetAlpha(0.28)
		self:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.5)
		if GameTooltip then GameTooltip:Hide() end
	end)

	btn:SetScript("OnClick", function()
		ns.OpenCopyWindow(chatFrame)
	end)
end

local function AttachAllChatFrames()
	local total = NUM_CHAT_WINDOWS or 10
	for i = 1, total do
		local cf = _G["ChatFrame" .. i]
		if cf then
			AttachButton(cf)
		end
	end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function()
	AttachAllChatFrames()
	if hooksecurefunc and FCF_OpenTemporaryWindow then
		hooksecurefunc("FCF_OpenTemporaryWindow", function()
			if C_Timer and C_Timer.After then
				C_Timer.After(0.1, AttachAllChatFrames)
			end
		end)
	end
end)

-------------------------------------------------------------------------------
-- Slash commands & Addon Compartment
-------------------------------------------------------------------------------
SLASH_CHATCOPY1 = "/copy"
SLASH_CHATCOPY2 = "/chatcopy"
SlashCmdList.CHATCOPY = function()
	ns.OpenCopyWindow(SELECTED_CHAT_FRAME or ChatFrame1)
end

function ChatCopy_OnCompartmentClick()
	ns.OpenCopyWindow(SELECTED_CHAT_FRAME or ChatFrame1)
end

function ChatCopy_OnCompartmentEnter(_, buttonFrame)
	if not GameTooltip then return end
	GameTooltip:SetOwner(buttonFrame, "ANCHOR_LEFT")
	GameTooltip:AddLine(addonName)
	GameTooltip:AddLine("Click: copy active chat tab", 1, 1, 1)
	GameTooltip:Show()
end

function ChatCopy_OnCompartmentLeave()
	if GameTooltip then GameTooltip:Hide() end
end

-- Export CleanLine for unit testing.
ns.CleanLine = CleanLine
