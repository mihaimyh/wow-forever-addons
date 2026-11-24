local addonName, ns = ...

local Config = ns:NewModule("Config")

-- Native Settings API panel, organized into subcategories (like Spoken) with
-- section headers inside each page. Works identically on Mainline 12.x and Forever 16001.

function Config:OnInitialize()
	self.settings = {}
	self.subcategories = {}
	if not Settings or not Settings.RegisterVerticalLayoutCategory or not Settings.RegisterAddOnSetting then
		return
	end

	local ok, err = pcall(function()
		local category, layout = Settings.RegisterVerticalLayoutCategory(addonName)

		local function AddSection(targetLayout, title)
			if targetLayout and CreateSettingsListSectionHeaderInitializer then
				pcall(function()
					targetLayout:AddInitializer(CreateSettingsListSectionHeaderInitializer(title))
				end)
			end
		end

		local function MakeSubcategory(name)
			if Settings.RegisterVerticalLayoutSubcategory then
				local sub, subLayout = Settings.RegisterVerticalLayoutSubcategory(category, name)
				if sub then
					self.subcategories[name] = sub
					return sub, subLayout
				end
			end
			return category, layout
		end

		-----------------------------------------------------------------------
		-- Main page: General & HUD
		-----------------------------------------------------------------------
		AddSection(layout, "General")

		self:AddCheckbox(category, "RetPulse_Enabled", "enabled",
			"Enable RetPulse", "Turn the whole addon on or off.", function()
				local ui = ns:GetModule("UI")
				if ui then ui:Refresh() end
			end)

		self:AddCheckbox(category, "RetPulse_Locked", "locked",
			"Lock frames", "Unlock to drag the HUD into place.", function()
				ns.SetLocked(ns.db.locked)
			end)

		self:AddCheckbox(category, "RetPulse_ClickToCast", "clickToCast",
			"Click-to-cast out of combat", "Click the main HUD icon to cast the recommended spell (Blessing, Aura, Seal). Disabled in combat.", function()
				local ui = ns:GetModule("UI")
				if ui then ui:Refresh() end
			end)

		if Settings.CreateDropdown and Settings.CreateControlTextContainer then
			local visSetting = Settings.RegisterAddOnSetting(category, "RetPulse_Visibility", "visibility", ns.db,
				Settings.VarType.String, "HUD visibility", "combat")
			self.settings["visibility"] = visSetting
			Settings.CreateDropdown(category, visSetting, function()
				local container = Settings.CreateControlTextContainer()
				container:Add("combat", "In combat only", "Show the HUD only while fighting.")
				container:Add("target", "When targeting an enemy", "Show when you have an attackable target or are in combat.")
				container:Add("always", "Always", "Keep the HUD visible at all times.")
				return container:GetData()
			end, "Choose when the RetPulse HUD appears on screen.")
			visSetting:SetValueChangedCallback(function()
				ns:SyncVisibilityFields()
			end)
		else
			self:AddCheckbox(category, "RetPulse_CombatOnly", "combatOnly",
				"Show only in combat", "Hide the HUD when not fighting.", function()
					ns.db.visibility = ns.db.combatOnly and "combat" or "always"
					ns:SyncVisibilityFields()
				end)
		end

		AddSection(layout, "HUD & Visuals")

		self:AddCheckbox(category, "RetPulse_NameplateMode", "nameplateMode",
			"Attach to target nameplate", "Show compact spell + NEXT icons to the left of your target's nameplate; falls back to the classic HUD when no nameplate is visible.", function()
				local ui = ns:GetModule("UI")
				if ui then ui:Refresh() end
			end)

		self:AddCheckbox(category, "RetPulse_NameplateBars", "nameplateBars",
			"Nameplate swing bar & echoes", "Show a mini swing bar and 3 Echo pips on the compact nameplate widget.", function()
				local ui = ns:GetModule("UI")
				if ui then ui:Refresh() end
			end)

		local npOffset = Settings.RegisterAddOnSetting(category, "RetPulse_NameplateOffsetX", "nameplateOffsetX", ns.db,
			Settings.VarType.Number, "Nameplate X offset", -4)
		self.settings["nameplateOffsetX"] = npOffset
		local npOffsetOptions = Settings.CreateSliderOptions(-40, 40, 2)
		if MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label then
			npOffsetOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
		end
		Settings.CreateSlider(category, npOffset, npOffsetOptions, "Horizontal distance (px) from the target nameplate. Increase toward + to move closer.")
		npOffset:SetValueChangedCallback(function()
			local ui = ns:GetModule("UI")
			if ui then ui:Refresh() end
		end)

		local npOffsetY = Settings.RegisterAddOnSetting(category, "RetPulse_NameplateOffsetY", "nameplateOffsetY", ns.db,
			Settings.VarType.Number, "Nameplate Y offset", 0)
		self.settings["nameplateOffsetY"] = npOffsetY
		local npOffsetYOptions = Settings.CreateSliderOptions(-40, 40, 2)
		if MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label then
			npOffsetYOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
		end
		Settings.CreateSlider(category, npOffsetY, npOffsetYOptions, "Vertical offset (px) relative to the target nameplate.")
		npOffsetY:SetValueChangedCallback(function()
			local ui = ns:GetModule("UI")
			if ui then ui:Refresh() end
		end)

		self:AddCheckbox(category, "RetPulse_ShowKeybinds", "showKeybinds",
			"Show keybinds", "Display action-bar keybind badges on the main and next icons.", function()
				local ui = ns:GetModule("UI")
				if ui then ui:Refresh() end
			end)

		self:AddCheckbox(category, "RetPulse_Effects", "effects",
			"Holy effects", "Holy aura, ring and sparks around the icon.")

		self:AddCheckbox(category, "RetPulse_Sound", "sound",
			"SWAP NOW sound", "Soft click when echoes hit cap and it is time to twist.")

		self:AddCheckbox(category, "RetPulse_AlertSounds", "alertSounds",
			"Alert sounds (Interrupt / Proc / Face)", "Play subtle audio cues on FACE!, INTERRUPT, and PROC! alerts.")

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
						ns.db.position = ns.DefaultPosition()
						ns.ApplyPosition()
						ns:Print("position reset")
					end,
					"Move the RetPulse HUD back to its default position.",
					true
				)
				layout:AddInitializer(resetInit)
			end)
		end

		-----------------------------------------------------------------------
		-- Subcategory 1: Rotation & Mana
		-----------------------------------------------------------------------
		local rotCat, rotLayout = MakeSubcategory("Rotation & Mana")
		AddSection(rotLayout, "Seals & Weapon Speed")

		self:AddCheckbox(rotCat, "RetPulse_Auto", "auto",
			"Pair seals from weapon speed", "Suggests primary/secondary seals based on weapon speed.")

		if Settings.CreateDropdown and Settings.CreateControlTextContainer then
			local bracketSetting = Settings.RegisterAddOnSetting(rotCat, "RetPulse_BracketMode", "bracketMode", ns.db,
				Settings.VarType.String, "Weapon speed brackets", "video")
			self.settings["bracketMode"] = bracketSetting
			Settings.CreateDropdown(rotCat, bracketSetting, function()
				local container = Settings.CreateControlTextContainer()
				container:Add("video", "Three brackets (Deep dive)", "Fast <= 2.5, Medium 2.6-3.2, Slow >= 3.3.")
				container:Add("icy", "Two brackets (Icy Veins)", "Fast < 3.0, Slow >= 3.0.")
				return container:GetData()
			end, "Choose how weapon speed maps to seal pairs.")
			bracketSetting:SetValueChangedCallback(function()
				ns.db.bracketsIcy = (ns.db.bracketMode == "icy")
			end)
		else
			self:AddCheckbox(rotCat, "RetPulse_BracketsIcy", "bracketsIcy",
				"Two brackets (Icy Veins)", "Off uses the three weapon-speed brackets from the deep dive.", function()
					ns.db.bracketMode = ns.db.bracketsIcy and "icy" or "video"
				end)
		end

		self:AddCheckbox(rotCat, "RetPulse_Twist", "twistWithoutTalent",
			"Twist without Unsealed Wrath", "Below level 40 the echoes do not exist; this follows the video literally.")

		self:AddCheckbox(rotCat, "RetPulse_ForceUW", "forceUnsealedWrath",
			"Force Unsealed Wrath tracking", "Use when the passive talent stays invisible to the client.", function()
				local engine = ns:GetModule("WeaponEngine")
				if engine then engine:RefreshTalents() end
			end)

		AddSection(rotLayout, "AoE & Mana Saving")

		self:AddCheckbox(rotCat, "RetPulse_AoE", "aoe",
			"Always include Consecration", "Force Consecration and Holy Wrath into single-target rotation too.")

		self:AddCheckbox(rotCat, "RetPulse_AutoAoE", "autoAoe",
			"Auto-AoE from nameplates", "Automatically switch to AoE when enough hostile enemies are in melee range.")

		if Settings.CreateDropdown and Settings.CreateControlTextContainer then
			local aoeThresholdSetting = Settings.RegisterAddOnSetting(rotCat, "RetPulse_AutoAoeThreshold", "autoAoeThreshold", ns.db,
				Settings.VarType.Number, "Auto-AoE enemy threshold", 2)
			self.settings["autoAoeThreshold"] = aoeThresholdSetting
			Settings.CreateDropdown(rotCat, aoeThresholdSetting, function()
				local container = Settings.CreateControlTextContainer()
				container:Add(2, "2+ enemies", "Use Consecration when 2 or more enemies are in melee range.")
				container:Add(3, "3+ enemies (Mana friendly)", "Save mana in dungeons by waiting for 3+ melee enemies.")
				container:Add(4, "4+ enemies (Big pulls)", "Only use Auto-AoE on large packs of 4+ enemies.")
				return container:GetData()
			end, "Minimum melee enemies needed before Auto-AoE switches to Consecration.")
		end

		self:AddCheckbox(rotCat, "RetPulse_ManaSaver", "manaSaver",
			"Low-mana guard (combat)", "Skip expensive openers when Consecration hits insufficient mana, keeping Judgement and Holy Strike flowing.")

		AddSection(rotLayout, "Combat Utility")

		self:AddCheckbox(rotCat, "RetPulse_Interrupt", "suggestInterrupt",
			"Interrupt alerts (Hammer of Justice)", "Prioritize Hammer of Justice when your target casts an interruptible spell.")

		self:AddCheckbox(rotCat, "RetPulse_FacingAlert", "facingAlert",
			"Facing target alert", "Show FACE TARGET / FACE! warning when an attack or spell fails because you are not facing your target.")

		self:AddCheckbox(rotCat, "RetPulse_SuggestBurst", "suggestBurst",
			"Burst cooldowns on Boss", "Suggest ready Avenging Wrath, offensive racials, or on-use trinkets on worldboss targets.")

		self:AddCheckbox(rotCat, "RetPulse_CrusaderBoss", "crusaderOnBoss",
			"Crusader opener on Boss/Elite", "Recommend Seal of the Crusader + Judgement once per Boss/Elite pull.")

		self:AddCheckbox(rotCat, "RetPulse_CrusaderBossOnly", "crusaderBossOnly",
			"Crusader opener: Boss only", "Skip dungeon trash elites and only use Seal of the Crusader opener on worldbosses.")

		-----------------------------------------------------------------------
		-- Subcategory 1b: PvP
		-----------------------------------------------------------------------
		local pvpCat, pvpLayout = MakeSubcategory("PvP")
		AddSection(pvpLayout, "PvP Intelligence (Hostile Players Only)")

		self:AddCheckbox(pvpCat, "RetPulse_PvpEnabled", "pvpEnabled",
			"Enable PvP mode", "Activates smart PvP rotation and alerts only against hostile players or in Battlegrounds. Never affects PvE.")

		self:AddCheckbox(pvpCat, "RetPulse_PvpStunCombo", "pvpStunCombo",
			"Stun burst combo (HoJ -> Judgement)", "Suggests Hammer of Justice before Judgement of Command for double damage on stunned players.")

		self:AddCheckbox(pvpCat, "RetPulse_PvpCcBreaker", "pvpCcBreaker",
			"CC breaker (Will of the Forsaken / Freedom)", "Suggests Will of the Forsaken when CC'd and Blessing of Freedom when slowed/rooted out of melee.")

		self:AddCheckbox(pvpCat, "RetPulse_PvpGapCloser", "pvpGapCloser",
			"Gap closer & 2nd interrupt (Repentance)", "Uses Repentance at range to stop fleeing players or interrupt casts when Hammer of Justice is unavailable.")

		self:AddCheckbox(pvpCat, "RetPulse_PvpAntiRunner", "pvpAntiRunner",
			"Anti-runner (Seal of Justice)", "Swaps to Seal of Justice + Judgement when a mobile enemy player (Druid/Shaman/Hunter/Rogue) escapes melee.")

		-----------------------------------------------------------------------
		-- Subcategory 2: Buffs & Talents
		-----------------------------------------------------------------------
		local buffCat, buffLayout = MakeSubcategory("Buffs & Talents")
		AddSection(buffLayout, "Blessings & Auras (Out of Combat)")

		if Settings.CreateDropdown and Settings.CreateControlTextContainer then
			local blessSetting = Settings.RegisterAddOnSetting(buffCat, "RetPulse_PreferredBlessing", "preferredBlessing", ns.db,
				Settings.VarType.String, "Missing Blessing reminder", "auto")
			self.settings["preferredBlessing"] = blessSetting
			Settings.CreateDropdown(buffCat, blessSetting, function()
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

		self:AddCheckbox(buffCat, "RetPulse_RemindAura", "remindAura",
			"Remind missing Aura", "Remind out of combat if no Paladin Aura is active.", function()
				local ui = ns:GetModule("UI")
				if ui then ui:Refresh() end
			end)

		self:AddCheckbox(buffCat, "RetPulse_RemindGroupBlessings", "remindGroupBlessings",
			"Buff party/raid & friendly target", "Remind out of combat to cast the best missing Blessing on party/raid members or your friendly player target (click icon to cast).", function()
				local ui = ns:GetModule("UI")
				if ui then ui:Refresh() end
			end)

		self:AddCheckbox(buffCat, "RetPulse_BuffRefreshEarly", "buffRefreshEarly",
			"Refresh blessings early (< 60s)", "Remind out of combat to refresh your Blessings when less than 60 seconds remain.", function()
				local ui = ns:GetModule("UI")
				if ui then ui:Refresh() end
			end)

		self:AddCheckbox(buffCat, "RetPulse_PreferGreaterBlessings", "preferGreaterBlessings",
			"Prefer Greater Blessings in raid", "Suggest Greater Blessings in raids when learned and usable (falls back to regular if out of reagents).", function()
				local ui = ns:GetModule("UI")
				if ui then ui:Refresh() end
			end)

		self:AddCheckbox(buffCat, "RetPulse_RemindDispel", "remindDispel",
			"Dispel reminder (Purify / Cleanse)", "Remind out of combat to cleanse lingering Poison, Disease, or Magic debuffs on you, your target, or group (click to cast).", function()
				local ui = ns:GetModule("UI")
				if ui then ui:Refresh() end
			end)

		self:AddCheckbox(buffCat, "RetPulse_WarnRighteousFury", "warnRighteousFury",
			"Warn Righteous Fury in group", "Warn out of combat if Righteous Fury is active while you are not assigned as Tank.", function()
				local ui = ns:GetModule("UI")
				if ui then ui:Refresh() end
			end)

		AddSection(buffLayout, "Talent Advisor")

		self:AddCheckbox(buffCat, "RetPulse_TalentAdvisor", "talentAdvisor",
			"Show talent recommendations", "Display RP NEXT / RP X/Y badges on the left side of talent buttons (does not overlap Zygor).", function()
				local talents = ns:GetModule("Talents")
				if talents then talents:RefreshOverlay() end
			end)

		if Settings.CreateDropdown and Settings.CreateControlTextContainer then
			local buildSetting = Settings.RegisterAddOnSetting(buffCat, "RetPulse_TalentBuild", "talentBuild", ns.db,
				Settings.VarType.String, "Talent build preset", "dps")
			self.settings["talentBuild"] = buildSetting
			Settings.CreateDropdown(buffCat, buildSetting, function()
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

		-----------------------------------------------------------------------
		-- Subcategory 3: Debug
		-----------------------------------------------------------------------
		local dbgCat, dbgLayout = MakeSubcategory("Debug")
		AddSection(dbgLayout, "Diagnostics & Logging")

		self:AddCheckbox(dbgCat, "RetPulse_Log", "logEnabled",
			"Record combat log (debug)", "Writes swings, casts and advice into RetPulseDB for review.")

		self:AddCheckbox(dbgCat, "RetPulse_Trace", "traceEnabled",
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

function Config:Sync(variable)
	local setting = self.settings and self.settings[variable]
	if setting and setting.SetValue then
		pcall(setting.SetValue, setting, ns.db[variable], true)
	end
end

function Config:Open()
	if InCombatLockdown() then
		ns:Print("options open after combat")
		return
	end
	if self.category and Settings and Settings.OpenToCategory then
		Settings.OpenToCategory(self.category:GetID())
	end
end

function ns:OpenOptions()
	Config:Open()
end
