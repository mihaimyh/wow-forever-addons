local addonName, ns = ...

local Tooltip = ns:NewModule("Tooltip")

local READY = { 0.45, 0.90, 0.40 }
local WARN = { 1.00, 0.62, 0.22 }
local MUTED = { 0.72, 0.70, 0.65 }
local GOLD = { 0.94, 0.78, 0.38 }
local OOR = { 1.00, 0.42, 0.38 }

local function ColorForAdvice(advice, flip)
	if flip then return GOLD end
	if advice == "sell" then return READY end
	if advice == "vendor" then return WARN end
	if advice == "hold" then return MUTED end
	return MUTED
end

local function ItemIdFromTooltip(tooltip, data)
	-- Modern TooltipDataProcessor payload.
	if type(data) == "table" then
		local id = data.id
		if type(id) == "number" and not ns:IsSecret(id) then
			return id
		end
		if type(data.guid) == "string" then
			local fromGuid = data.guid:match("item:(%d+)")
			if fromGuid then return tonumber(fromGuid) end
		end
	end

	if not tooltip then return nil end
	if tooltip.GetItem then
		local ok, name, link = pcall(tooltip.GetItem, tooltip)
		if ok and type(link) == "string" and not ns:IsSecret(link) then
			local id = link:match("item:(%d+)")
			if id then return tonumber(id) end
		end
	end
	return nil
end

local function StackCountHint(data)
	-- Bag hover: resolve stack size from item GUID location (Forever/Mainline).
	if type(data) == "table" and type(data.guid) == "string"
		and C_Item and C_Item.GetItemLocation and C_Container and C_Container.GetContainerItemInfo then
		local okLoc, loc = pcall(C_Item.GetItemLocation, data.guid)
		if okLoc and loc and loc.IsBagAndSlot and loc:IsBagAndSlot() then
			local okInfo, info = pcall(C_Container.GetContainerItemInfo, loc.bagID, loc.slotIndex)
			if okInfo and type(info) == "table" and type(info.stackCount) == "number"
				and not ns:IsSecret(info.stackCount) and info.stackCount > 0 then
				return info.stackCount
			end
		end
	end
	return 1
end

function Tooltip:BuildLines(itemId, count)
	local prices = ns:GetModule("Prices")
	local watchlist = ns:GetModule("Watchlist")
	local db = ns.db or {}

	if not prices or not prices:IsTSMAvailable() then
		return {
			{ text = "GoldPulse: TSM required", r = OOR[1], g = OOR[2], b = OOR[3] },
		}
	end

	local snap = prices:Snapshot(itemId)
	if not snap or not snap.ok then
		return {
			{ text = "GoldPulse: no AuctionDB price", r = MUTED[1], g = MUTED[2], b = MUTED[3] },
		}
	end

	local advice, reason = ns.PricesLogic.ClassifyBag(snap, count or 1, db)
	local flip, discount = ns.PricesLogic.IsFlipCandidate(snap, db)
	local c = ColorForAdvice(advice, flip)

	local label = string.upper(advice or "hold")
	if flip then
		label = string.format("FLIP? (-%d%%)", math.floor((discount or 0) * 100 + 0.5))
	elseif advice == "sell" then
		label = "SELL"
	elseif advice == "vendor" then
		label = "VENDOR"
	else
		label = "HOLD"
	end

	local lines = {
		{ text = " ", r = 1, g = 1, b = 1 }, -- spacer
		{ text = "GoldPulse", r = GOLD[1], g = GOLD[2], b = GOLD[3] },
		{ text = string.format("  %s — %s", label, reason or ""), r = c[1], g = c[2], b = c[3] },
	}

	local unit = snap.minBuyout or snap.market
	if unit then
		local extra = string.format("  Floor %s", prices:FormatMoney(unit))
		if snap.market and snap.minBuyout and snap.market ~= snap.minBuyout then
			extra = extra .. string.format(" · Market %s", prices:FormatMoney(snap.market))
		end
		if snap.saleRate then
			extra = extra .. string.format(" · Sale %.0f%%", snap.saleRate)
		end
		lines[#lines + 1] = { text = extra, r = MUTED[1], g = MUTED[2], b = MUTED[3] }
	end

	if watchlist and not watchlist:IsTracked(itemId) then
		lines[#lines + 1] = {
			text = "  (not on GoldPulse watchlist — advice still from TSM)",
			r = MUTED[1], g = MUTED[2], b = MUTED[3],
		}
	end

	return lines
end

function Tooltip:Append(tooltip, data)
	if not ns.db or ns.db.enabled == false then return end
	if ns.db.tooltip == false then return end
	if not tooltip or not tooltip.AddLine then return end

	local itemId = ItemIdFromTooltip(tooltip, data)
	if not itemId then return end

	local lines = self:BuildLines(itemId, StackCountHint(data))
	for _, line in ipairs(lines) do
		tooltip:AddLine(line.text, line.r, line.g, line.b)
	end
	if tooltip.Show then
		tooltip:Show()
	end
end

function Tooltip:OnLogin()
	local function handler(tooltip, data)
		local ok, err = pcall(function()
			Tooltip:Append(tooltip, data)
		end)
		if not ok then
			ns:RecordError("Tooltip:Append", err)
		end
	end

	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
		and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, handler)
		self.mode = "TooltipDataProcessor"
		return
	end

	-- Legacy fallback (older Mainline / odd builds).
	if GameTooltip and GameTooltip.HookScript then
		GameTooltip:HookScript("OnTooltipSetItem", function(tt)
			handler(tt, nil)
		end)
	end
	if ItemRefTooltip and ItemRefTooltip.HookScript then
		ItemRefTooltip:HookScript("OnTooltipSetItem", function(tt)
			handler(tt, nil)
		end)
	end
	self.mode = "HookScript"
end
