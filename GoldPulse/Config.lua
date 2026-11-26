local addonName, ns = ...

local Config = ns:NewModule("Config")

function Config:OnLogin()
	if not Settings or not Settings.RegisterVerticalLayoutCategory then
		return
	end

	local ok, err = pcall(function()
		local category = Settings.RegisterVerticalLayoutCategory("GoldPulse")
		self.category = category

		ns.db.buyPctPercent = math.floor(((ns.db.buyPct or 0.70) * 100) + 0.5)

		local enabledSetting = Settings.RegisterAddOnSetting(
			category, "GoldPulse_enabled", "enabled", ns.db, Settings.VarType.Boolean,
			"Enable GoldPulse", ns.DEFAULTS.enabled
		)
		enabledSetting:SetValueChangedCallback(function(_, value)
			ns.db.enabled = value and true or false
			local ui = ns:GetModule("UI")
			if ui then
				if not ns.db.enabled and ui.Hide then ui:Hide() end
				if ui.Refresh then ui:Refresh() end
			end
		end)
		Settings.CreateCheckbox(category, enabledSetting, "Master toggle for the advice panel.")

		local lockedSetting = Settings.RegisterAddOnSetting(
			category, "GoldPulse_locked", "locked", ns.db, Settings.VarType.Boolean,
			"Lock panel", ns.DEFAULTS.locked
		)
		lockedSetting:SetValueChangedCallback(function(_, value)
			ns.db.locked = value and true or false
			local ui = ns:GetModule("UI")
			if ui and ui.ApplyLock then ui:ApplyLock() end
		end)
		Settings.CreateCheckbox(category, lockedSetting, "Prevent dragging the GoldPulse window.")

		local autoSetting = Settings.RegisterAddOnSetting(
			category, "GoldPulse_autoRefresh", "autoRefresh", ns.db, Settings.VarType.Boolean,
			"Auto-refresh while open", ns.DEFAULTS.autoRefresh
		)
		autoSetting:SetValueChangedCallback(function(_, value)
			ns.db.autoRefresh = value and true or false
		end)
		Settings.CreateCheckbox(category, autoSetting,
			"Rescan bags/flips automatically while the panel is open (also refreshes soon after loot).")

		local tipSetting = Settings.RegisterAddOnSetting(
			category, "GoldPulse_tooltip", "tooltip", ns.db, Settings.VarType.Boolean,
			"Show advice on tooltips", ns.DEFAULTS.tooltip
		)
		tipSetting:SetValueChangedCallback(function(_, value)
			ns.db.tooltip = value and true or false
		end)
		Settings.CreateCheckbox(category, tipSetting,
			"Append SELL / HOLD / VENDOR / FLIP advice when you hover an item.")

		local intervalSetting = Settings.RegisterAddOnSetting(
			category, "GoldPulse_autoRefreshSeconds", "autoRefreshSeconds", ns.db, Settings.VarType.Number,
			"Auto-refresh interval (sec)", ns.DEFAULTS.autoRefreshSeconds
		)
		intervalSetting:SetValueChangedCallback(function(_, value)
			ns.db.autoRefreshSeconds = value
		end)
		local intervalOpts = Settings.CreateSliderOptions(5, 60, 5)
		if MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label then
			intervalOpts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
		end
		Settings.CreateSlider(category, intervalSetting, intervalOpts,
			"How often to fully rescan while the panel is open.")

		local buySetting = Settings.RegisterAddOnSetting(
			category, "GoldPulse_buyPctPercent", "buyPctPercent", ns.db, Settings.VarType.Number,
			"Flip buy under market (%)", 70
		)
		buySetting:SetValueChangedCallback(function(_, value)
			ns.db.buyPctPercent = value
			ns.db.buyPct = value / 100
			local ui = ns:GetModule("UI")
			if ui and ui.Refresh then ui:Refresh() end
		end)
		local buyOpts = Settings.CreateSliderOptions(50, 95, 1)
		if MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label then
			buyOpts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
		end
		Settings.CreateSlider(category, buySetting, buyOpts,
			"Suggest flips when min buyout is at or below this percent of dbmarket.")

		local saleSetting = Settings.RegisterAddOnSetting(
			category, "GoldPulse_minSaleRate", "minSaleRate", ns.db, Settings.VarType.Number,
			"Minimum sale rate (%)", ns.DEFAULTS.minSaleRate
		)
		saleSetting:SetValueChangedCallback(function(_, value)
			ns.db.minSaleRate = value
			local ui = ns:GetModule("UI")
			if ui and ui.Refresh then ui:Refresh() end
		end)
		local saleOpts = Settings.CreateSliderOptions(0, 100, 5)
		if MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label then
			saleOpts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
		end
		Settings.CreateSlider(category, saleSetting, saleOpts,
			"Ignore items slower than this region sale rate.")

		local stackSetting = Settings.RegisterAddOnSetting(
			category, "GoldPulse_minStackValue", "minStackValue", ns.db, Settings.VarType.Number,
			"Minimum stack value (copper)", ns.DEFAULTS.minStackValue
		)
		stackSetting:SetValueChangedCallback(function(_, value)
			ns.db.minStackValue = value
			local ui = ns:GetModule("UI")
			if ui and ui.Refresh then ui:Refresh() end
		end)
		local stackOpts = Settings.CreateSliderOptions(0, 5000, 50)
		if MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label then
			stackOpts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
		end
		Settings.CreateSlider(category, stackSetting, stackOpts,
			"Hold bag advice for stacks worth less than this (copper).")

		local autoPostSetting = Settings.RegisterAddOnSetting(
			category, "GoldPulse_autoPostWhenAH", "autoPostWhenAH", ns.db, Settings.VarType.Boolean,
			"Auto-post when AH opens", ns.DEFAULTS.autoPostWhenAH
		)
		autoPostSetting:SetValueChangedCallback(function(_, value)
			ns.db.autoPostWhenAH = value and true or false
		end)
		Settings.CreateCheckbox(category, autoPostSetting,
			"Start the deposit-aware post queue automatically when you open the Auction House.")

		local autoDurSetting = Settings.RegisterAddOnSetting(
			category, "GoldPulse_autoDuration", "autoDuration", ns.db, Settings.VarType.Boolean,
			"Auto duration from sale rate", ns.DEFAULTS.autoDuration
		)
		autoDurSetting:SetValueChangedCallback(function(_, value)
			ns.db.autoDuration = value and true or false
		end)
		Settings.CreateCheckbox(category, autoDurSetting,
			"High sale rate → 12h (cheaper deposit). Slow items → 24h/48h.")

		local coverSetting = Settings.RegisterAddOnSetting(
			category, "GoldPulse_depositCover", "depositCover", ns.db, Settings.VarType.Number,
			"Deposit cover ratio", ns.DEFAULTS.depositCover
		)
		coverSetting:SetValueChangedCallback(function(_, value)
			ns.db.depositCover = value
		end)
		local coverOpts = Settings.CreateSliderOptions(1, 5, 0.5)
		if MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label then
			coverOpts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
		end
		Settings.CreateSlider(category, coverSetting, coverOpts,
			"Require net-if-sold (after 5% AH cut) >= deposit × this. Higher = safer vs expire risk.")

		local minDepSetting = Settings.RegisterAddOnSetting(
			category, "GoldPulse_minDepositCopper", "minDepositCopper", ns.db, Settings.VarType.Number,
			"Min deposit floor (copper)", ns.DEFAULTS.minDepositCopper
		)
		minDepSetting:SetValueChangedCallback(function(_, value)
			ns.db.minDepositCopper = value
		end)
		local minDepOpts = Settings.CreateSliderOptions(1, 500, 1)
		if MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label then
			minDepOpts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
		end
		Settings.CreateSlider(category, minDepSetting, minDepOpts,
			"Forever often floors deposits (e.g. 1s=100c). Set 1 if Blizzard hotfixes the floor to 1c.")

		Settings.RegisterAddOnCategory(category)
		ns.db.buyPct = (ns.db.buyPctPercent or 70) / 100
	end)
	if not ok then
		ns:RecordError("Config:OnLogin", err)
		ns:Print("|cffff5555options panel skipped|r", err)
	end
end

function Config:SyncSetting(variable, value)
	if variable == "buyPct" and ns.db then
		ns.db.buyPctPercent = math.floor((value or 0.7) * 100 + 0.5)
	end
end

function ns:OpenOptions()
	local config = ns:GetModule("Config")
	if config and config.category and Settings and Settings.OpenToCategory then
		Settings.OpenToCategory(config.category:GetID())
	else
		ns:Print("options unavailable on this build — use /gp")
	end
end
