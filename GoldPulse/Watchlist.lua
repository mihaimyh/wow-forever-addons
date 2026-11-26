local addonName, ns = ...

local Watchlist = ns:NewModule("Watchlist")

-- Curated Classic / Forever trade goods for leveling + early gold making.
-- Expand later via SavedVariables; keep v1 static and small enough to scan.

local ITEMS = {
	-- Herbs
	{ id = 765, name = "Silverleaf", cat = "herb" },
	{ id = 2447, name = "Peacebloom", cat = "herb" },
	{ id = 2449, name = "Earthroot", cat = "herb" },
	{ id = 2450, name = "Briarthorn", cat = "herb" },
	{ id = 2452, name = "Swiftthistle", cat = "herb" },
	{ id = 2453, name = "Bruiseweed", cat = "herb" },
	{ id = 785, name = "Mageroyal", cat = "herb" },
	{ id = 3355, name = "Wild Steelbloom", cat = "herb" },
	{ id = 3356, name = "Kingsblood", cat = "herb" },
	{ id = 3357, name = "Liferoot", cat = "herb" },
	{ id = 3358, name = "Khadgar's Whisker", cat = "herb" },
	{ id = 3818, name = "Fadeleaf", cat = "herb" },
	{ id = 3821, name = "Goldthorn", cat = "herb" },
	{ id = 4625, name = "Firebloom", cat = "herb" },
	{ id = 8838, name = "Sungrass", cat = "herb" },
	{ id = 13468, name = "Black Lotus", cat = "herb" },
	-- Ore / stone / bars
	{ id = 2770, name = "Copper Ore", cat = "ore" },
	{ id = 2771, name = "Tin Ore", cat = "ore" },
	{ id = 2772, name = "Iron Ore", cat = "ore" },
	{ id = 2775, name = "Silver Ore", cat = "ore" },
	{ id = 2776, name = "Gold Ore", cat = "ore" },
	{ id = 3858, name = "Mithril Ore", cat = "ore" },
	{ id = 10620, name = "Thorium Ore", cat = "ore" },
	{ id = 11370, name = "Dark Iron Ore", cat = "ore" },
	{ id = 2835, name = "Rough Stone", cat = "ore" },
	{ id = 2836, name = "Coarse Stone", cat = "ore" },
	{ id = 2838, name = "Heavy Stone", cat = "ore" },
	{ id = 2840, name = "Copper Bar", cat = "bar" },
	{ id = 3576, name = "Tin Bar", cat = "bar" },
	{ id = 2841, name = "Bronze Bar", cat = "bar" },
	{ id = 3575, name = "Iron Bar", cat = "bar" },
	{ id = 2842, name = "Silver Bar", cat = "bar" },
	{ id = 3577, name = "Gold Bar", cat = "bar" },
	{ id = 3860, name = "Mithril Bar", cat = "bar" },
	{ id = 12359, name = "Thorium Bar", cat = "bar" },
	{ id = 12360, name = "Arcanite Bar", cat = "bar" },
	-- Leather
	{ id = 2318, name = "Light Leather", cat = "leather" },
	{ id = 2319, name = "Medium Leather", cat = "leather" },
	{ id = 4234, name = "Heavy Leather", cat = "leather" },
	{ id = 4304, name = "Thick Leather", cat = "leather" },
	{ id = 8170, name = "Rugged Leather", cat = "leather" },
	{ id = 783, name = "Light Hide", cat = "leather" },
	{ id = 4232, name = "Medium Hide", cat = "leather" },
	{ id = 4235, name = "Heavy Hide", cat = "leather" },
	{ id = 2934, name = "Ruined Leather Scraps", cat = "leather" },
	-- Cloth
	{ id = 2589, name = "Linen Cloth", cat = "cloth" },
	{ id = 2592, name = "Wool Cloth", cat = "cloth" },
	{ id = 4306, name = "Silk Cloth", cat = "cloth" },
	{ id = 4338, name = "Mageweave Cloth", cat = "cloth" },
	{ id = 14047, name = "Runecloth", cat = "cloth" },
	-- Potions / PvP consumables
	{ id = 929, name = "Healing Potion", cat = "potion" },
	{ id = 1710, name = "Greater Healing Potion", cat = "potion" },
	{ id = 3385, name = "Lesser Mana Potion", cat = "potion" },
	{ id = 3827, name = "Mana Potion", cat = "potion" },
	{ id = 2459, name = "Swiftness Potion", cat = "potion" },
	{ id = 5634, name = "Free Action Potion", cat = "potion" },
	-- Misc high-value
	{ id = 14342, name = "Mooncloth", cat = "craft" },
	{ id = 12811, name = "Righteous Orb", cat = "craft" },
	{ id = 12363, name = "Arcane Crystal", cat = "craft" },
	{ id = 14344, name = "Large Brilliant Shard", cat = "craft" },
}

local byId = {}
for _, row in ipairs(ITEMS) do
	byId[row.id] = row
end

function Watchlist:GetAll()
	return ITEMS
end

function Watchlist:Get(id)
	return byId[id]
end

function Watchlist:IsTracked(id)
	return byId[id] ~= nil
end

function Watchlist:Iterator()
	local i = 0
	return function()
		i = i + 1
		return ITEMS[i]
	end
end
