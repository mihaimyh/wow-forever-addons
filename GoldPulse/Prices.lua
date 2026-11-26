local addonName, ns = ...

local Prices = ns:NewModule("Prices")

-- Thin wrappers around TSM_API. Never invent prices when sources are missing.

local function SafeNumber(v)
	if type(v) ~= "number" then return nil end
	if ns:IsSecret(v) then return nil end
	if v ~= v or v <= 0 then return nil end
	return v
end

function Prices:IsTSMAvailable()
	return type(TSM_API) == "table"
		and type(TSM_API.GetCustomPriceValue) == "function"
		and type(TSM_API.ToItemString) == "function"
end

function Prices:ToItemString(item)
	if not self:IsTSMAvailable() then return nil end
	if type(item) == "number" then
		item = "i:" .. item
	end
	if type(item) ~= "string" then return nil end
	local ok, result = pcall(TSM_API.ToItemString, item)
	if ok and type(result) == "string" then return result end
	-- Fallback for plain numeric ids when ToItemString fails pre-cache.
	local id = item:match("^i:(%d+)$") or item:match("^(%d+)$")
	if id then return "i:" .. id end
	return nil
end

function Prices:GetCustom(customPriceStr, itemString)
	if not self:IsTSMAvailable() or not itemString or not customPriceStr then return nil end
	local ok, value, err = pcall(TSM_API.GetCustomPriceValue, customPriceStr, itemString)
	if not ok then return nil end
	return SafeNumber(value), err
end

function Prices:GetMarket(itemString)
	local v = self:GetCustom("dbmarket", itemString)
	if v then return v, "dbmarket" end
	v = self:GetCustom("dbregionmarketavg", itemString)
	if v then return v, "dbregionmarketavg" end
	return nil, nil
end

function Prices:GetMinBuyout(itemString)
	return self:GetCustom("dbminbuyout", itemString)
end

function Prices:GetHistorical(itemString)
	return self:GetCustom("dbhistorical", itemString)
end

function Prices:GetSaleRate(itemString)
	-- TSM region sale rate is typically 0-100 (percent) or 0-1 depending on source.
	local v = self:GetCustom("dbregionsalerate", itemString)
	if not v then return nil end
	if v > 0 and v <= 1 then
		return v * 100
	end
	return v
end

function Prices:GetSoldPerDay(itemString)
	return self:GetCustom("dbregionsoldperday", itemString)
end

function Prices:GetVendorSell(itemString)
	return self:GetCustom("vendorsell", itemString)
end

function Prices:FormatMoney(copper)
	if type(TSM_API) == "table" and type(TSM_API.FormatMoneyString) == "function" and type(copper) == "number" then
		local ok, s = pcall(TSM_API.FormatMoneyString, copper)
		if ok and type(s) == "string" then return s end
	end
	if type(copper) ~= "number" or copper <= 0 then return "-" end
	local g = math.floor(copper / 10000)
	local s = math.floor((copper % 10000) / 100)
	local c = copper % 100
	if g > 0 then return string.format("%dg%02ds", g, s) end
	if s > 0 then return string.format("%ds%02dc", s, c) end
	return string.format("%dc", c)
end

function Prices:Snapshot(item)
	local itemString = self:ToItemString(item)
	if not itemString then
		return { itemString = nil, ok = false, reason = "bad_item" }
	end
	local market, marketSrc = self:GetMarket(itemString)
	local minBuyout = self:GetMinBuyout(itemString)
	local historical = self:GetHistorical(itemString)
	local saleRate = self:GetSaleRate(itemString)
	local soldPerDay = self:GetSoldPerDay(itemString)
	local vendorSell = self:GetVendorSell(itemString)
	local hasMarket = market ~= nil
	return {
		itemString = itemString,
		ok = hasMarket or minBuyout ~= nil or vendorSell ~= nil,
		market = market,
		marketSrc = marketSrc,
		minBuyout = minBuyout,
		historical = historical,
		saleRate = saleRate,
		soldPerDay = soldPerDay,
		vendorSell = vendorSell,
	}
end

function Prices:GetStatus()
	if not self:IsTSMAvailable() then
		return {
			tsm = false,
			hasData = false,
			detail = "TradeSkillMaster not loaded — install TSM + Desktop App",
		}
	end
	-- Probe a common cloth item; if market is nil, AuctionDB likely empty/stale.
	local probe = self:Snapshot(2589) -- Linen Cloth
	local hasData = probe.market ~= nil or probe.minBuyout ~= nil
	local detail
	if hasData then
		detail = "AuctionDB reachable (probe: Linen Cloth)"
	else
		detail = "TSM loaded but no AuctionDB — run Desktop App, pick Forever ruleset, /reload"
	end
	return { tsm = true, hasData = hasData, detail = detail, probe = probe }
end

-- Pure helpers (also used by offline tests via ns.PricesLogic).
ns.PricesLogic = {}

function ns.PricesLogic.ClassifyBag(snap, count, db)
	db = db or {}
	local buyPct = db.buyPct or 0.70
	local minSaleRate = db.minSaleRate or 40
	local minStackValue = db.minStackValue or 100
	local vendorRatio = db.vendorRatio or 0.90
	local holdMarketVsHist = db.holdMarketVsHist or 0.55

	count = count or 1
	local market = snap and snap.market
	local minBuyout = snap and snap.minBuyout
	local historical = snap and snap.historical
	local saleRate = snap and snap.saleRate
	local vendorSell = snap and snap.vendorSell
	local floor = minBuyout or market

	if vendorSell and vendorSell > 0 then
		if not floor then
			return "vendor", "no AH price — vendor"
		end
		if vendorSell >= vendorRatio * floor then
			return "vendor", "vendor near AH floor"
		end
	end

	if not market then
		if vendorSell and vendorSell > 0 then
			return "vendor", "no market — vendor"
		end
		return "hold", "no TSM market data"
	end

	local unit = minBuyout or market
	local stackValue = unit * count
	if stackValue < minStackValue then
		return "hold", "stack too small"
	end

	if historical and market < holdMarketVsHist * historical then
		return "hold", "market soft vs historical"
	end

	if saleRate ~= nil and saleRate < minSaleRate then
		return "hold", string.format("slow sales (%.0f%%)", saleRate)
	end

	local reason = "liquid AH mat"
	if saleRate then
		reason = string.format("sale rate %.0f%%", saleRate)
	end
	return "sell", reason
end

function ns.PricesLogic.IsFlipCandidate(snap, db)
	db = db or {}
	local buyPct = db.buyPct or 0.70
	local minSaleRate = db.minSaleRate or 40
	if not snap or not snap.market or not snap.minBuyout then
		return false, nil
	end
	if snap.minBuyout <= 0 or snap.market <= 0 then
		return false, nil
	end
	if snap.minBuyout > buyPct * snap.market then
		return false, nil
	end
	if snap.saleRate ~= nil and snap.saleRate < minSaleRate then
		return false, nil
	end
	local discount = 1 - (snap.minBuyout / snap.market)
	return true, discount
end
