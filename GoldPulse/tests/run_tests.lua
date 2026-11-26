-- Offline unit tests for GoldPulse price advice (fengari / Lua 5.1).
-- Run from GoldPulse/:
--   npx --yes --package=fengari-node-cli fengari tests/run_tests.lua

local passed, failed = 0, 0

local function Assert(cond, msg)
	if cond then
		passed = passed + 1
		print("[PASS]", msg)
	else
		failed = failed + 1
		print("[FAIL]", msg)
	end
end

local function AssertEq(a, b, msg)
	Assert(a == b, string.format("%s (got %s, want %s)", msg, tostring(a), tostring(b)))
end

-- Load PricesLogic by executing the classify section without WoW globals.
local ns = { IsSecret = function() return false end }
ns.NewModule = function(_, name)
	local m = { name = name }
	return m
end
package = package or {}
-- Minimal stub of Prices.lua logic (mirror of ns.PricesLogic in Prices.lua).
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
	return "sell", "liquid AH mat"
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

-- 1. Sell liquid mat
do
	local advice = ns.PricesLogic.ClassifyBag({
		market = 200, minBuyout = 190, saleRate = 80, vendorSell = 5, historical = 180,
	}, 20, {})
	AssertEq(advice, "sell", "1. Liquid mat with good sale rate -> sell")
end

-- 2. Vendor when AH floor near vendor
do
	local advice = ns.PricesLogic.ClassifyBag({
		market = 10, minBuyout = 10, saleRate = 90, vendorSell = 10,
	}, 5, { vendorRatio = 0.90 })
	AssertEq(advice, "vendor", "2. Vendor price near AH floor -> vendor")
end

-- 3. Hold when no market
do
	local advice = ns.PricesLogic.ClassifyBag({ vendorSell = nil }, 1, {})
	AssertEq(advice, "hold", "3. No market and no vendor -> hold")
end

-- 4. Hold slow sales
do
	local advice = ns.PricesLogic.ClassifyBag({
		market = 500, minBuyout = 480, saleRate = 10, vendorSell = 1, historical = 500,
	}, 10, { minSaleRate = 40 })
	AssertEq(advice, "hold", "4. Slow sale rate -> hold")
end

-- 5. Hold soft market vs historical
do
	local advice = ns.PricesLogic.ClassifyBag({
		market = 100, minBuyout = 90, saleRate = 90, vendorSell = 1, historical = 400,
	}, 10, { holdMarketVsHist = 0.55 })
	AssertEq(advice, "hold", "5. Market << historical -> hold")
end

-- 6. Flip candidate under threshold
do
	local ok, disc = ns.PricesLogic.IsFlipCandidate({
		market = 1000, minBuyout = 600, saleRate = 70,
	}, { buyPct = 0.70, minSaleRate = 40 })
	Assert(ok == true, "6. 40% under market is a flip")
	Assert(disc and disc > 0.39 and disc < 0.41, "6b. discount ~0.40")
end

-- 7. Reject flip without market
do
	local ok = ns.PricesLogic.IsFlipCandidate({ minBuyout = 100 }, {})
	Assert(ok == false, "7. Missing market rejects flip")
end

-- 8. Reject flip above buy threshold
do
	local ok = ns.PricesLogic.IsFlipCandidate({
		market = 1000, minBuyout = 900, saleRate = 80,
	}, { buyPct = 0.70 })
	Assert(ok == false, "8. Only 10% under market rejects flip at 70% threshold")
end

-- 9. Reject flip with slow sales
do
	local ok = ns.PricesLogic.IsFlipCandidate({
		market = 1000, minBuyout = 500, saleRate = 5,
	}, { buyPct = 0.70, minSaleRate = 40 })
	Assert(ok == false, "9. Slow sale rate rejects flip")
end

-- 10. Tiny stack hold
do
	local advice = ns.PricesLogic.ClassifyBag({
		market = 20, minBuyout = 20, saleRate = 90, vendorSell = 1,
	}, 1, { minStackValue = 100 })
	AssertEq(advice, "hold", "10. Tiny stack value -> hold")
end

-- 11. Tooltip label prefers FLIP when undercut exists
do
	local snap = { market = 1000, minBuyout = 600, saleRate = 70, vendorSell = 1, historical = 900 }
	local advice = ns.PricesLogic.ClassifyBag(snap, 5, {})
	local flip = ns.PricesLogic.IsFlipCandidate(snap, { buyPct = 0.70, minSaleRate = 40 })
	Assert(advice == "sell" or advice == "hold", "11. classify still returns bag advice")
	Assert(flip == true, "11b. flip flag true for tooltip FLIP? line")
end

-- Mirror deposit helpers from Posting.lua for offline tests.
function ns.PricesLogic.EstimateDeposit(vendorSell, stackSize, duration, db)
	db = db or {}
	local rate = ({ [1] = 0.15, [2] = 0.30, [3] = 0.60 })[duration or 2] or 0.30
	local raw = math.ceil((vendorSell or 0) * (stackSize or 1) * rate)
	local minDep = db.minDepositCopper
	if minDep == nil then minDep = 100 end
	if raw < 1 then raw = 1 end
	if minDep > 0 and raw < minDep then return minDep, true end
	return raw, false
end

function ns.PricesLogic.PickDuration(saleRate, db)
	if db and db.autoDuration == false and db.postDuration then return db.postDuration end
	saleRate = saleRate or 50
	if saleRate >= 75 then return 1 end
	if saleRate >= 45 then return 2 end
	return 3
end

function ns.PricesLogic.RecommendStack(cat, count, maxStack, snap, unitBuyout, db)
	db = db or {}
	count = count or 1
	maxStack = maxStack or 20
	if count <= 0 or not unitBuyout or unitBuyout <= 0 then return nil end
	local vendor = (snap and snap.vendorSell) or 0
	local saleRate = (snap and snap.saleRate) or 50
	local duration = ns.PricesLogic.PickDuration(saleRate, db)
	local ahCutKeep = db.ahCutKeep or 0.95
	local cover = db.depositCover or 2.0
	local candidates = {}
	local function add(n)
		n = math.floor(n)
		if n >= 1 and n <= count and n <= maxStack then candidates[n] = true end
	end
	for _, n in ipairs({ 1, 5, 10, 20 }) do add(n) end
	add(count)
	local best, bestScore, bestDep = nil, -math.huge, nil
	for n in pairs(candidates) do
		local dep = ns.PricesLogic.EstimateDeposit(vendor, n, duration, db)
		local gross = unitBuyout * n * ahCutKeep
		local p = math.max(0, math.min(1, saleRate / 100))
		local expected = p * gross - (1 - p) * dep
		if gross >= dep * cover and expected > bestScore then
			best, bestScore, bestDep = n, expected, dep
		end
	end
	if not best then return nil, nil, duration, nil, "deposit kills profit" end
	return best, bestDep, duration, bestScore
end

-- 12. Min deposit floor forces larger stacks for cheap mats
do
	local snap = { vendorSell = 1, saleRate = 90, market = 200 }
	-- With 1s floor, stack of 1 is often unprofitable; stack of 20 should win.
	local stack, dep = ns.PricesLogic.RecommendStack("cloth", 20, 20, snap, 200, {
		minDepositCopper = 100, depositCover = 2, ahCutKeep = 0.95,
	})
	Assert(stack ~= nil and stack >= 5, "12. cheap mat picks larger stack under 1s deposit floor")
	Assert(dep ~= nil and dep >= 100, "12b. deposit at least min floor")
end

-- 13. High sale rate picks shorter duration
do
	AssertEq(ns.PricesLogic.PickDuration(90, { autoDuration = true }), 1, "13. hot item → 12h")
	AssertEq(ns.PricesLogic.PickDuration(50, { autoDuration = true }), 2, "13b. medium → 24h")
	AssertEq(ns.PricesLogic.PickDuration(20, { autoDuration = true }), 3, "13c. slow → 48h")
end

-- 14. Skip when deposit eats profit even at full stack
do
	local snap = { vendorSell = 5000, saleRate = 30, market = 100 }
	local stack = ns.PricesLogic.RecommendStack("ore", 20, 20, snap, 100, {
		minDepositCopper = 100, depositCover = 3, ahCutKeep = 0.95,
	})
	Assert(stack == nil, "14. high vendor + low price → skip (deposit kills profit)")
end

print(string.format("\nResults: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
