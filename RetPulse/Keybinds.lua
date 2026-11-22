local addonName, ns = ...

local Keybinds = ns:NewModule("Keybinds")

-- Maps spell names to short, readable keybind labels from the player's action bars.
-- Uses only public, non-secret action bar and binding APIs, rebuilt only on
-- bar/binding events (never inside OnUpdate).

local BAR_BINDINGS = {
	{ start = 1,   stop = 12,  prefix = "ACTIONBUTTON" },
	{ start = 61,  stop = 72,  prefix = "MULTIACTIONBAR1BUTTON" },
	{ start = 49,  stop = 60,  prefix = "MULTIACTIONBAR2BUTTON" },
	{ start = 25,  stop = 36,  prefix = "MULTIACTIONBAR3BUTTON" },
	{ start = 37,  stop = 48,  prefix = "MULTIACTIONBAR4BUTTON" },
	{ start = 145, stop = 156, prefix = "MULTIACTIONBAR5BUTTON" },
	{ start = 157, stop = 168, prefix = "MULTIACTIONBAR6BUTTON" },
	{ start = 169, stop = 180, prefix = "MULTIACTIONBAR7BUTTON" },
}

local function FormatKey(key)
	if type(key) ~= "string" or key == "" then return nil end

	local text = key:upper()
	text = text:gsub("SHIFT%-", "S")
	text = text:gsub("CTRL%-", "C")
	text = text:gsub("ALT%-", "A")
	text = text:gsub("NUMPAD", "N")
	text = text:gsub("MOUSEWHEELUP", "MWU")
	text = text:gsub("MOUSEWHEELDOWN", "MWD")
	text = text:gsub("MIDDLEMOUSE", "M3")
	text = text:gsub("BUTTON(%d+)", "M%1")
	text = text:gsub("SPACE", "SPC")
	text = text:gsub("BACKSPACE", "BS")
	text = text:gsub("CAPSLOCK", "CAP")
	text = text:gsub("PAGEUP", "PU")
	text = text:gsub("PAGEDOWN", "PD")
	text = text:gsub("INSERT", "INS")
	text = text:gsub("DELETE", "DEL")

	if #text > 4 then
		text = text:sub(1, 4)
	end
	return text
end

local function SpellNameFromSlot(slot)
	if not GetActionInfo then return nil end
	local ok, actionType, id = pcall(GetActionInfo, slot)
	if not ok or not actionType then return nil end

	local spellID
	if actionType == "spell" then
		spellID = id
	elseif actionType == "macro" and GetMacroSpell then
		local okM, macroSpell = pcall(GetMacroSpell, id)
		if okM then spellID = macroSpell end
	end

	if not spellID or ns.IsSecret(spellID) then return nil end

	if C_Spell and C_Spell.GetSpellInfo then
		local okS, info = pcall(C_Spell.GetSpellInfo, spellID)
		if okS and type(info) == "table" and type(info.name) == "string" and not ns.IsSecret(info.name) then
			return info.name
		end
	end
	return nil
end

function Keybinds:OnInitialize()
	self.bySpell = {}
	self.pendingRefresh = false
end

function Keybinds:OnLogin()
	self:Rebuild()

	local function ScheduleRebuild()
		if self.pendingRefresh then return end
		self.pendingRefresh = true
		if C_Timer and C_Timer.After then
			C_Timer.After(0.1, function()
				self.pendingRefresh = false
				self:Rebuild()
			end)
		else
			self.pendingRefresh = false
			self:Rebuild()
		end
	end

	ns:On("ACTIONBAR_SLOT_CHANGED", ScheduleRebuild)
	ns:On("UPDATE_BINDINGS", ScheduleRebuild)
	ns:On("SPELLS_CHANGED", ScheduleRebuild)
	ns:On("PLAYER_ENTERING_WORLD", ScheduleRebuild)
end

function Keybinds:Rebuild()
	local map = {}
	if not GetBindingKey or not GetActionInfo then
		self.bySpell = map
		return
	end

	for _, bar in ipairs(BAR_BINDINGS) do
		for slot = bar.start, bar.stop do
			local spellName = SpellNameFromSlot(slot)
			if spellName and not map[spellName] then
				local index = slot - bar.start + 1
				local key = GetBindingKey(bar.prefix .. index)
				local formatted = FormatKey(key)
				if formatted then
					map[spellName] = formatted
				end
			end
		end
	end

	self.bySpell = map
end

function Keybinds:GetForSpell(spellName)
	if not spellName or not self.bySpell then return nil end
	return self.bySpell[spellName]
end

-- Exposed for unit testing.
Keybinds.FormatKey = FormatKey
