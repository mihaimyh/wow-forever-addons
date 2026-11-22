local addonName, ns = ...

local Config = ns:NewModule("Config")

-- One panel, one source of truth: every control writes a key in RetPulseDB.
-- Slash commands update the same keys and sync back via SyncSetting, so the
-- Settings UI and slash commands never drift apart.

function Config:OnInitialize()
	self.settings = {}

	if not Settings or not Settings.RegisterVerticalLayoutCategory then
		ns:Print("Settings API missing, options panel skipped")
		return
	end

	local ok, err = pcall(function()
		local category, layout = Settings.RegisterVerticalLayoutCategory(addonName)

		self:AddCheckbox(category, "RetPulse_Enabled", "enabled",
			"Enable RetPulse", "Turn the whole addon on or off.", function()
				local ui = ns:GetModule("UI")
				if ui then ui:Refresh() end
			end)

		self:AddCheckbox(category, "RetPulse_Locked", "locked",
			"Lock frames", "Unlock to drag the HUD into place.", function()
				ns.SetLocked(ns.db.locked)
			end)

		if Settings.CreateDropdown and Settings.CreateControlTextContainer then
			local visSetting = Settings.RegisterAddOnSetting(category, "RetPulse_Visibility", "visibility", ns.db,
				Settings.VarType.String, "HUD visibility", "combat")
			self.settings["visibility"] = visSetting
			Settings.CreateDropdown(category, visSetting, function()
				local container = Settings.CreateControlTextContainer()
				container:Add("combat", "Combat only", "Show the HUD only while in combat.")
				container:Add("target", "Combat or hostile target", "Show in combat or when targeting a hostile unit.")
				container:Add("always", "Always", "Keep the HUD visible even out of combat.")
				return container:GetData()
			end, "Controls when the RetPulse HUD is displayed.")
			visSetting:SetValueChangedCallback(function()
				ns:SyncVisibilityFields()
				local ui = ns:GetModule("UI")
				if ui then ui:Refresh() end
			end)
		else
			self:AddCheckbox(category, "RetPulse_CombatOnly", "combatOnly",
				"Show only in combat", "The HUD appears when combat starts and hides when it ends.", function()
					ns.db.visibility = ns.db.combatOnly and "combat" or "always"
					ns:SyncVisibilityFields()
					local ui = ns:GetModule("UI")
					if ui then ui:Refresh() end
				end)
		end

		self:AddCheckbox(category, "RetPulse_ShowKeybinds", "showKeybinds",
			"Show keybinds", "Display action-bar keybind badges on the main and next icons.", function()
				local ui = ns:GetModule("UI")
				if ui then ui:Refresh() end
			end)

		self:AddCheckbox(category, "RetPulse_Effects", "effects",
			"Holy effects", "Aura, sparks and burst around the action icon.")

		self:AddCheckbox(category, "RetPulse_Sound", "sound",
			"SWAP NOW sound", "One click when echoes reach the target.")

		self:AddCheckbox(category, "RetPulse_Auto", "auto",
			"Pair seals from weapon speed", "Hint only. Weapon speed never changes the 3-echo cap.")

		if Settings.CreateDropdown and Settings.CreateControlTextContainer then
			local bracketSetting = Settings.RegisterAddOnSetting(category, "RetPulse_BracketMode", "bracketMode", ns.db,
				Settings.VarType.String, "Weapon speed brackets", "video")
			self.settings["bracketMode"] = bracketSetting
			Settings.CreateDropdown(category, bracketSetting, function()
				local container = Settings.CreateControlTextContainer()
				container:Add("video", "Three brackets (Deep dive)", "Fast <= 2.5, Medium 2.6-3.2, Slow >= 3.3.")
				container:Add("icy", "Two brackets (Icy Veins)", "Fast < 3.0, Slow >= 3.0.")
				return container:GetData()
			end, "Choose how weapon speed maps to seal pairs.")
			bracketSetting:SetValueChangedCallback(function()
				ns.db.bracketsIcy = (ns.db.bracketMode == "icy")
			end)
		else
			self:AddCheckbox(category, "RetPulse_BracketsIcy", "bracketsIcy",
				"Two brackets (Icy Veins)", "Off uses the three weapon-speed brackets from the deep dive.", function()
					ns.db.bracketMode = ns.db.bracketsIcy and "icy" or "video"
				end)
		end

		self:AddCheckbox(category, "RetPulse_AoE", "aoe",
			"Always include Consecration", "Force Consecration and Holy Wrath into single-target rotation too.")

		self:AddCheckbox(category, "RetPulse_AutoAoE", "autoAoe",
			"Auto-AoE from nameplates", "Automatically switch to AoE when 2+ hostile enemies are in melee range.")

		self:AddCheckbox(category, "RetPulse_Interrupt", "suggestInterrupt",
			"Interrupt alerts (Hammer of Justice)", "Prioritize Hammer of Justice when your target casts an interruptible spell.")

		self:AddCheckbox(category, "RetPulse_CrusaderBoss", "crusaderOnBoss",
			"Crusader opener on Boss/Elite", "Recommend Seal of the Crusader + Judgement once per Boss/Elite target.")

		if Settings.CreateDropdown and Settings.CreateControlTextContainer then
			local blessSetting = Settings.RegisterAddOnSetting(category, "RetPulse_PreferredBlessing", "preferredBlessing", ns.db,
				Settings.VarType.String, "Missing Blessing reminder", "auto")
			self.settings["preferredBlessing"] = blessSetting
			Settings.CreateDropdown(category, blessSetting, function()
				local container = Settings.CreateControlTextContainer()
				container:Add("auto", "Auto (Kings -> Might -> Wisdom)", "Remind out of combat if no Blessing is active on you.")
				container:Add("kings", "Blessing of Kings", "Remind out of combat if Blessing of Kings is missing.")
				container:Add("might", "Blessing of Might", "Remind out of combat if Blessing of Might is missing.")
				container:Add("wisdom", "Blessing of Wisdom", "Remind out of combat if Blessing of Wisdom is missing.")
				container:Add("off", "Off", "Disable missing Blessing reminders.")
				return container:GetData()
			end, "Remind you out of combat when your Paladin Blessing expires.")
			blessSetting:SetValueChangedCallback(function()
				local ui = ns:GetModule("UI")
				if ui then ui:Refresh() end
			end)
		end

		self:AddCheckbox(category, "RetPulse_RemindAura", "remindAura",
			"Remind missing Aura", "Remind out of combat if no Paladin Aura is active.", function()
				local ui = ns:GetModule("UI")
				if ui then ui:Refresh() end
			end)

		self:AddCheckbox(category, "RetPulse_TalentAdvisor", "talentAdvisor",
			"Show talent recommendations", "Display RP NEXT / RP X/Y badges on the left side of talent buttons (does not overlap Zygor).", function()
				local talents = ns:GetModule("Talents")
				if talents then talents:RefreshOverlay() end
			end)

		if Settings.CreateDropdown and Settings.CreateControlTextContainer then
			local buildSetting = Settings.RegisterAddOnSetting(category, "RetPulse_TalentBuild", "talentBuild", ns.db,
				Settings.VarType.String, "Talent build preset", "dps")
			self.settings["talentBuild"] = buildSetting
			Settings.CreateDropdown(category, buildSetting, function()
				local container = Settings.CreateControlTextContainer()
				container:Add("dps", "Unsealed Wrath (DPS / Benediction)", "5/5 Benediction into 31 Retribution / 20 Holy.")
				container:Add("leveling", "Retribution (Leveling / Deflection)", "5/5 Deflection into 31 Retribution / 20 Holy.")
				return container:GetData()
			end, "Choose which RetPulse talent build to highlight in the Talent window.")
			buildSetting:SetValueChangedCallback(function()
				local talents = ns:GetModule("Talents")
				if talents then talents:RefreshOverlay() end
			end)
		end

		self:AddCheckbox(category, "RetPulse_Twist", "twistWithoutTalent",
			"Twist without Unsealed Wrath", "Below level 40 the echoes do not exist; this follows the video literally.")

		self:AddCheckbox(category, "RetPulse_ForceUW", "forceUnsealedWrath",
			"Force Unsealed Wrath tracking", "Use when the passive talent stays invisible to the client.", function()
				local engine = ns:GetModule("WeaponEngine")
				if engine then engine:RefreshTalents() end
			end)

		local scale = Settings.RegisterAddOnSetting(category, "RetPulse_Scale", "scale", ns.db,
			Settings.VarType.Number, "Scale", 1.0)
		self.settings["scale"] = scale
		local sliderOptions = Settings.CreateSliderOptions(0.5, 2.0, 0.05)
		if MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label then
			sliderOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
		end
		Settings.CreateSlider(category, scale, sliderOptions, "HUD scale.")
		scale:SetValueChangedCallback(function()
			ns.ApplyScale()
		end)

		if layout and CreateSettingsButtonInitializer then
			pcall(function()
				local resetInit = CreateSettingsButtonInitializer(
					"HUD Position",
					"Reset Position",
					function()
						ns.db.position = { point = "BOTTOM", relativePoint = "BOTTOM", x = 0, y = 220 }
						ns.ApplyPosition()
						ns:Print("position reset")
					end,
					"Move the RetPulse HUD back to its default position.",
					true
				)
				layout:AddInitializer(resetInit)
			end)
		end

		self:AddCheckbox(category, "RetPulse_Log", "logEnabled",
			"Record combat log (debug)", "Writes swings, casts and advice into RetPulseDB for review.")

		self:AddCheckbox(category, "RetPulse_Trace", "traceEnabled",
			"Flight recorder trace (debug)", "Samples addon state into RetPulseDB.traceLog.", function()
				local trace = ns:GetModule("Trace")
				if not trace then return end
				if ns.db.traceEnabled then
					trace:Start()
				else
					trace:Stop()
				end
			end)

		Settings.RegisterAddOnCategory(category)
		self.category = category
	end)

	if not ok then
		ns:Print("|cffff5555options panel failed|r", tostring(err))
		ns:RecordError("Config:OnInitialize", err)
	end
end

function Config:AddCheckbox(category, name, variable, label, tooltip, onChange)
	local defaultValue = ns.DEFAULTS and ns.DEFAULTS[variable]
	if defaultValue == nil then defaultValue = false end
	local setting = Settings.RegisterAddOnSetting(category, name, variable, ns.db,
		Settings.VarType.Boolean, label, defaultValue == true)
	self.settings[variable] = setting
	Settings.CreateCheckbox(category, setting, tooltip)
	if onChange then
		setting:SetValueChangedCallback(function()
			onChange()
		end)
	end
	return setting
end

function Config:SyncSetting(variable, value)
	local setting = self.settings and self.settings[variable]
	if setting and setting.SetValue then
		pcall(setting.SetValue, setting, value)
	end
end

function ns:OpenOptions()
	ns:RunOutOfCombat(function()
		local config = ns:GetModule("Config")
		if config and config.category then
			Settings.OpenToCategory(config.category:GetID())
		else
			ns:Print("options panel is not available")
		end
	end)
end
