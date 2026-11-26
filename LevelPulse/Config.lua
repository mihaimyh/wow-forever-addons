local addonName, ns = ...

local Config = ns:NewModule("Config")

-- Native Settings API panel for WoW: Forever (Interface 16001).

function Config:OnInitialize()
	self.settings = {}
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

		local function AddCheck(var, label, tooltip, onChange)
			local def = ns.DEFAULTS and ns.DEFAULTS[var]
			local setting = Settings.RegisterAddOnSetting(category, "LevelPulse_" .. var, var, ns.db,
				Settings.VarType.Boolean, label, def == true)
			self.settings[var] = setting
			Settings.CreateCheckbox(category, setting, tooltip)
			setting:SetValueChangedCallback(function()
				if onChange then onChange() end
				ns:NotifySetting()
			end)
			return setting
		end

		AddSection(layout, "General & HUD")

		AddCheck("enabled", "Enable LevelPulse", "Turn the XP buff advisor and telemetry HUD on or off.")
		AddCheck("locked", "Lock HUD position", "Unlock to drag the LevelPulse Command Pill on screen.", function()
			if ns.SetLocked then ns.SetLocked(ns.db.locked) end
		end)

		if Settings.CreateDropdown and Settings.CreateControlTextContainer then
			local visSetting = Settings.RegisterAddOnSetting(category, "LevelPulse_Visibility", "visibility", ns.db,
				Settings.VarType.String, "HUD display mode", "pill")
			self.settings["visibility"] = visSetting
			Settings.CreateDropdown(category, visSetting, function()
				local c = Settings.CreateControlTextContainer()
				c:Add("pill", "Adaptive Command Pill", "Compact telemetry pill when buffed; expands with 1-Click icon when a buff is needed.")
				c:Add("alerts", "Alerts only (hide when buffed)", "Completely invisible while all XP buffs are active; pops up only when action is needed.")
				c:Add("always", "Always show pill", "Keep the HUD visible out of combat.")
				return c:GetData()
			end, "Choose how the LevelPulse HUD behaves when all XP buffs are active.")
			visSetting:SetValueChangedCallback(function() ns:NotifySetting() end)
		end

		AddCheck("smartContext", "Smart context filter (Inns / Mount / Flight)",
			"Suppress consumable prompts in Resting Cities/Inns, on Mounts, and on Flight Paths so buffs are never wasted (still alerts for nearby Campfires outdoors).")

		AddCheck("readySound", "Play chime when buff completes",
			"Play a subtle audio cue the instant Well Fed, Campfire 60s sit, or 3/3 Cozy Sleeping Bag finishes so you can stand up immediately.")

		local scaleSetting = Settings.RegisterAddOnSetting(category, "LevelPulse_Scale", "scale", ns.db,
			Settings.VarType.Number, "HUD scale", 1.0)
		local scaleOpts = Settings.CreateSliderOptions(0.5, 2.0, 0.05)
		if MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label then
			scaleOpts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
		end
		Settings.CreateSlider(category, scaleSetting, scaleOpts, "Adjust the size of the LevelPulse HUD.")
		scaleSetting:SetValueChangedCallback(function()
			if ns.ApplyScale then ns.ApplyScale() end
		end)

		local earlySetting = Settings.RegisterAddOnSetting(category, "LevelPulse_EarlyRefresh", "earlyRefreshSeconds", ns.db,
			Settings.VarType.Number, "Early refresh warning (sec)", 90)
		local earlyOpts = Settings.CreateSliderOptions(0, 300, 15)
		if MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label then
			earlyOpts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
		end
		Settings.CreateSlider(category, earlySetting, earlyOpts, "Seconds remaining before suggesting to refresh expiring buffs.")
		earlySetting:SetValueChangedCallback(function() ns:NotifySetting() end)

		AddSection(layout, "XP Buffs & Consumables")

		AddCheck("trackFood", "Well Fed food (+5% Kill XP)",
			"Scan bags for Well Fed / XP cooked food and offer 1-Click eating.")
		AddCheck("foodTierAlerts", "Announce new Well Fed food tier on level-up",
			"Print recommended class & level foods in chat whenever leveling up unlocks a new Cooking food bracket.")

		if Settings.CreateDropdown and Settings.CreateControlTextContainer then
			local foodSetting = Settings.RegisterAddOnSetting(category, "LevelPulse_FoodMode", "foodMode", ns.db,
				Settings.VarType.String, "Preferred Well Fed food", "best")
			self.settings["foodMode"] = foodSetting
			Settings.CreateDropdown(category, foodSetting, function()
				local c = Settings.CreateControlTextContainer()
				c:Add("best", "Best usable food (highest stats + 5% XP)", "Eat the highest-level Well Fed food your character can use.")
				c:Add("cheapest", "Cheapest / largest stack first", "Use cheap fish/food first while questing to save top stat food.")
				return c:GetData()
			end, "Choose which Well Fed food in your bags is used on 1-Click.")
			foodSetting:SetValueChangedCallback(function() ns:NotifySetting() end)
		end

		AddCheck("trackCampfireSit", "Opportunistic Campfire (/sit near fire)",
			"Prompt 1-Click /sit whenever Campfire Nearby is detected and you lack 1h Camp Benefits.")
		AddCheck("trackCampfirePlace", "Place own Campfire (outdoors)",
			"Suggest placing your known Basic/Journeyman/Expert Campfire or Campfire Kit when outdoors without Camp buffs.")
		AddCheck("trackSleepingBag", "Cozy Sleeping Bag (+3% XP)",
			"Prompt 1-Click Cozy Sleeping Bag in the open world when stacks are below 3/3 or expiring.")
		AddCheck("trackStudentFodder", "Student Fodder (+Rested XP)",
			"Prompt 1-Click Student Fodder when in bags and Rested XP is below cap.")
		AddCheck("trackElixirs", "Track stat Elixirs in bags (optional)",
			"Also suggest drinking stat Elixirs currently carried in your bags.")
		AddCheck("trackWeaponStones", "Track Sharpening / Weightstones (optional)",
			"Also suggest applying Sharpening Stones or Weightstones from your bags to your main-hand weapon.")

		if layout and CreateSettingsButtonInitializer then
			pcall(function()
				layout:AddInitializer(CreateSettingsButtonInitializer(
					"Recommended Food Guide", "Open Food List",
					function()
						local fg = ns:GetModule("FoodGuide")
						local ui = ns:GetModule("UI")
						if fg and fg.PrintGuide then fg:PrintGuide() end
						if ui and ui.ToggleFoodDrawer then ui:ToggleFoodDrawer(true) end
					end,
					"Open the interactive Recommended Food list (Copy Ctrl+C, Shift-Click into Auction House & Cooking).", true
				))
				layout:AddInitializer(CreateSettingsButtonInitializer(
					"HUD Position", "Reset Position",
					function()
						ns.db.position = ns.DefaultPosition()
						if ns.ApplyPosition then ns.ApplyPosition() end
						ns:Print("position reset")
					end,
					"Move the LevelPulse HUD back to its default top-center position.", true
				))
				layout:AddInitializer(CreateSettingsButtonInitializer(
					"Snoozed Reminders", "Clear Snoozes",
					function()
						local adv = ns:GetModule("Advisor")
						if adv then adv:ClearSnoozes() end
						ns:NotifySetting()
						ns:Print("snoozed reminders cleared")
					end,
					"Restore any buff reminders you right-clicked to snooze.", true
				))
			end)
		end

		Settings.RegisterAddOnCategory(category)
		self.category = category
	end)

	if not ok then
		ns:RecordError("Config:OnInitialize", err)
	end
end

function Config:Sync(variable)
	local setting = self.settings and self.settings[variable]
	if setting and setting.SetValue and ns.db then
		pcall(setting.SetValue, setting, ns.db[variable], true)
	end
end

function ns:OpenOptions()
	ns:RunOutOfCombat(function()
		if Config.category and Settings and Settings.OpenToCategory then
			Settings.OpenToCategory(Config.category:GetID())
		end
	end)
end
