-- Issue #91: Waylaid crates (tooltip fill options and reward), cost per Merchant's Favor, best crate,
-- Favor balance and the Favor merchants in the snapshot.
-- Tooltip texts are the ones the Forever client showed for these items (248682, 248703), kept by
-- another addon in Veli's SavedVariables on 2026-11-11. Reward lines were not seen on a crate tooltip
-- yet; the reward fixtures below test the parser only.
local HERBS, INGOTS, OTHER = 248682, 248703, 248690
local PEACE, SILVER, EARTH, MAGE, BRIAR = 2447, 765, 2449, 785, 2450
local COPPER, TIN, BRONZE = 2840, 3576, 2841
local FAVOR = 3402

local HERBS_LINES = {
	{ leftText = "Waylaid Crate: Apprentice Herbs" },
	{ leftText = "Use: Fill the crate with any bundle from the following list:|cnIQ1:\n- 20 Peacebloom\n- 20 Silverleaf\n- 10 Earthroot\n- 10 Mageroyal\n- 10 Briarthorn|r" },
}
local INGOTS_LINES = {
	{ leftText = "Waylaid Crate: Apprentice Ingots" },
	{ leftText = "Use: Fill the crate with any bundle from the following list:|cnIQ1:\n- 20 Copper Bar\n- 20 Tin Bar\n- 10 Bronze Bar" },
}

local function setup()
	local ns, stub = LoadAddon({ auctionator = true })
	stub.items[HERBS] = { name = "Waylaid Crate: Apprentice Herbs" }
	stub.items[INGOTS] = { name = "Waylaid Crate: Apprentice Ingots" }
	stub.items[OTHER] = { name = "Linen Cloth" }
	for id, name in pairs({ [PEACE] = "Peacebloom", [SILVER] = "Silverleaf", [EARTH] = "Earthroot", [MAGE] = "Mageroyal",
		[BRIAR] = "Briarthorn", [COPPER] = "Copper Bar", [TIN] = "Tin Bar", [BRONZE] = "Bronze Bar" }) do
		stub.items[id] = { name = name }
	end
	-- The bundled recipe data is not loaded in specs: a tiny table gives the name index its item IDs.
	ns.RecipeData = { [1] = { reagents = { { itemID = PEACE }, { itemID = SILVER }, { itemID = EARTH }, { itemID = MAGE },
		{ itemID = BRIAR }, { itemID = COPPER }, { itemID = TIN } }, output = { itemID = BRONZE, quantity = 2 } } }
	stub.tooltips = { [HERBS] = HERBS_LINES, [INGOTS] = INGOTS_LINES, [OTHER] = { { leftText = "Linen Cloth" } } }
	stub.tooltipReads = 0
	C_TooltipInfo.GetItemByID = function(id)
		stub.tooltipReads = stub.tooltipReads + 1
		return stub.tooltips[id] and { lines = stub.tooltips[id] } or { lines = {} }
	end
	stub.favor = { name = "Merchant's Favor", quantity = 45, maxQuantity = 0, totalEarned = 120 }
	C_CurrencyInfo = { GetCurrencyInfo = function(id)
		if id == FAVOR then return stub.favor end
	end }
	stub.bags = { [0] = {} }
	return ns, stub
end

local function carry(stub, items)
	local slots = {}
	for id, n in pairs(items) do
		if n > 0 then slots[#slots + 1] = { itemID = id, stackCount = n } end
	end
	stub.bags[0] = slots
	stub.Fire("BAG_UPDATE_DELAYED")
end

local function has(text, s) if not text:find(s, 1, true) then error("missing [" .. s .. "] in:\n" .. text, 2) end end

it("parses fill options from the tooltip, keeps the raw lines and splits the name", function()
	local ns = setup()
	local p = ns.Crates.Parse(HERBS_LINES, "Merchant's Favor")
	eq(#p.fill, 5); eq(p.fill[1].n, 20); eq(p.fill[1].name, "Peacebloom"); eq(p.fill[5].n, 10); eq(p.fill[5].name, "Briarthorn")
	eq(p.reward, nil)
	eq(#p.raw, 2); eq(p.raw[2], HERBS_LINES[2].leftText)
	local label, tier = ns.Crates.NameParts("Waylaid Crate: Apprentice Herbs")
	eq(label, "Apprentice Herbs"); eq(tier, "Apprentice")
end)

it("reads a reward only where a line names the Favor currency with an amount", function()
	local ns = setup()
	local R = ns.Crates.RewardIn
	eq(R("30 Merchant's Favor", "Merchant's Favor"), 30)
	eq(R("Reward: 1,200 Merchant's Favor", "Merchant's Favor"), 1200)
	eq(R("Merchant's Favor: 45", "Merchant's Favor"), 45)
	eq(R("You have a 5% chance to receive 100% increased Merchant's Favor when you turn in a crate.", "Merchant's Favor"), nil)
	eq(R("30 Honor", "Merchant's Favor"), nil)
	eq(R("30 Merchant's Favor", nil), nil)
	local p = ns.Crates.Parse({ { leftText = "Waylaid Crate: X" }, { leftText = "Use: Fill the crate:\n- 4 Copper Bar" },
		{ leftText = "Rewards 30 Merchant's Favor", rightText = "x" } }, "Merchant's Favor")
	eq(p.reward.n, 30); eq(p.reward.text, "Rewards 30 Merchant's Favor"); eq(p.raw[3], "Rewards 30 Merchant's Favor\tx")
end)

it("finds crates in the bags by name, stores them and leaves other items alone", function()
	local ns, stub = setup()
	carry(stub, { [HERBS] = 2, [OTHER] = 10 })
	local rec = ns.db.crates[HERBS]
	eq(rec.name, "Waylaid Crate: Apprentice Herbs"); eq(rec.label, "Apprentice Herbs"); eq(rec.tier, "Apprentice")
	eq(#rec.fill, 5); eq(rec.fill[2].name, "Silverleaf"); eq(rec.seen.bags, true); eq(#rec.lines, 2)
	eq(ns.db.crates[OTHER], nil)
	-- Read once per session.
	local reads = stub.tooltipReads
	carry(stub, { [HERBS] = 2, [OTHER] = 9 })
	eq(stub.tooltipReads, reads)
end)

it("finds crates among the auction house items and at merchants", function()
	local ns, stub = setup()
	CraftWiseMarketDB.items = CraftWiseMarketDB.items or {}
	CraftWiseMarketDB.items[INGOTS] = {}
	ns.Crates.ScanMarket()
	eq(ns.db.crates[INGOTS].seen.ah, true); eq(#ns.db.crates[INGOTS].fill, 3)
	stub.merchant = { { itemID = HERBS, price = 900 } }
	stub.Fire("MERCHANT_SHOW")
	eq(ns.db.crates[HERBS].seen.merchant, true)
end)

it("retries a crate whose tooltip came back without the list", function()
	local ns, stub = setup()
	stub.tooltips[HERBS] = { { leftText = "Waylaid Crate: Apprentice Herbs" }, { leftText = "Retrieving item information" } }
	carry(stub, { [HERBS] = 1 })
	eq(#ns.db.crates[HERBS].fill, 0)
	stub.tooltips[HERBS] = HERBS_LINES
	stub.Fire("GET_ITEM_INFO_RECEIVED", HERBS, true)
	eq(#ns.db.crates[HERBS].fill, 5)
end)

it("cost per Favor: crate price plus the cheapest bundle, divided by the reward", function()
	local ns, stub = setup()
	stub.tooltips[HERBS] = { HERBS_LINES[1], HERBS_LINES[2], { leftText = "30 Merchant's Favor" } }
	carry(stub, { [HERBS] = 1 })
	stub.ah[HERBS] = 5000
	stub.ah[PEACE], stub.ah[SILVER], stub.ah[EARTH], stub.ah[MAGE] = 40, 30, 200, 150
	-- Briarthorn has no price: that option is left out, not counted as 0.
	local e = ns.Crates.Evaluate(HERBS, ns.ReagentPrices("profit", "ah"), ns.Crates.NameIndex(), { [HERBS] = 1 })
	eq(e.crate, 5000); eq(e.crateLabel, "Auctionator (house unknown)")
	eq(e.fill.name, "Silverleaf"); eq(e.fill.total, 600); eq(e.options[5].total, nil); eq(e.options[5].id, BRIAR)
	eq(e.reward, 30); eq(e.rewardFrom, "tooltip")
	eq(e.fillCost, 600); eq(e.total, 5600); eq(e.perFavor, 5600 / 30); eq(e.fillPerFavor, 20)
	eq(#e.missing, 0)
	-- The resolved item IDs are kept in the store.
	eq(ns.db.crates[HERBS].fill[2].id, SILVER)
end)

it("a bundle item a known recipe makes cheaper is costed crafted (#47)", function()
	local ns, stub = setup()
	stub.tooltips[INGOTS] = { INGOTS_LINES[1], INGOTS_LINES[2], { leftText = "20 Merchant's Favor" } }
	carry(stub, { [INGOTS] = 1 })
	stub.ah[COPPER], stub.ah[TIN], stub.ah[BRONZE] = 100, 100, 500
	ns.charDB.professions[186] = { name = "Mining", recipes = { [2659] = { learned = true,
		reagents = { { itemID = COPPER, quantity = 1 }, { itemID = TIN, quantity = 1 } }, output = { itemID = BRONZE, quantity = 2 } } } }
	ns.Notify("RECIPES_CHANGED")
	local e = ns.Crates.Evaluate(INGOTS, ns.ReagentPrices("profit", "ah"), ns.Crates.NameIndex(), {})
	-- 10 Bronze Bar crafted at 100 each = 1000, cheaper than 20 Copper Bar (2000) or bought Bronze (5000).
	eq(e.fill.name, "Bronze Bar"); eq(e.fill.total, 1000); eq(e.fill.crafted, true); eq(e.fill.label, "crafted")
	eq(e.crate, nil); eq(e.perFavor, nil); eq(e.fillPerFavor, 50)
	has(table.concat(e.missing, ","), "no crate price")
end)

it("measures the reward when a Favor gain comes with one crate leaving the bags, either order", function()
	local ns, stub = setup()
	carry(stub, { [HERBS] = 3, [INGOTS] = 1 })
	eq(ns.Crates.Reward(HERBS), nil)
	-- Gain first, then the bags.
	stub.now = 100
	stub.Fire("CURRENCY_DISPLAY_UPDATE", FAVOR, 75, 30, 0)
	carry(stub, { [HERBS] = 2, [INGOTS] = 1 })
	-- Bags first, then the gain; this one was doubled (5% chance).
	stub.now = 200
	carry(stub, { [HERBS] = 1, [INGOTS] = 1 })
	stub.Fire("CURRENCY_DISPLAY_UPDATE", FAVOR, 135, 60, 0)
	stub.now = 300
	carry(stub, { [HERBS] = 0, [INGOTS] = 1 })
	stub.Fire("CURRENCY_DISPLAY_UPDATE", FAVOR, 165, 30, 0)
	local got = ns.db.crates[HERBS].got
	eq(#got, 3); eq(got[1].n, 30); eq(got[2].n, 60); eq(got[3].n, 30)
	local n, from, obs = ns.Crates.Reward(HERBS)
	eq(n, 30); eq(from, "seen"); eq(obs, 3)
	eq(ns.db.crates[INGOTS].got, nil)
end)

it("does not take a gain without a crate leaving (or too late, or another currency) as a reward", function()
	local ns, stub = setup()
	carry(stub, { [HERBS] = 2, [INGOTS] = 2 })
	stub.now = 100
	stub.Fire("CURRENCY_DISPLAY_UPDATE", FAVOR, 75, 30, 0)
	stub.now = 110
	carry(stub, { [HERBS] = 1, [INGOTS] = 2 }) -- 10 s later: a crate used to fill, not a turn-in
	stub.Fire("CURRENCY_DISPLAY_UPDATE", 1234, 5, 5, 0)
	-- Two crate types leaving at once can't be told apart.
	stub.now = 200
	carry(stub, { [HERBS] = 0, [INGOTS] = 1 })
	stub.Fire("CURRENCY_DISPLAY_UPDATE", FAVOR, 105, 30, 0)
	eq(ns.db.crates[HERBS].got, nil); eq(ns.db.crates[INGOTS].got, nil)
end)

it("ranks crates by cost per Favor, names the best and the best of those held, and says what is missing", function()
	local ns, stub = setup()
	stub.tooltips[HERBS] = { HERBS_LINES[1], HERBS_LINES[2], { leftText = "30 Merchant's Favor" } }
	stub.tooltips[INGOTS] = { INGOTS_LINES[1], INGOTS_LINES[2], { leftText = "20 Merchant's Favor" } }
	carry(stub, { [HERBS] = 1, [INGOTS] = 2 })
	stub.ah[HERBS], stub.ah[INGOTS] = 5000, 1000
	stub.ah[PEACE], stub.ah[SILVER] = 40, 30
	stub.ah[COPPER], stub.ah[TIN], stub.ah[BRONZE] = 100, 100, 500
	local list, best, bestHeld = ns.Crates.Ranked()
	-- Ingots: (1000 + 2000) / 20 = 150 per Favor; Herbs: (5000 + 600) / 30 = 186.7.
	eq(#list, 2); eq(list[1].id, INGOTS); eq(best.id, INGOTS); eq(list[1].perFavor, 150)
	-- Held: fill only. Herbs 600/30 = 20, Ingots 2000/20 = 100.
	eq(bestHeld.id, HERBS)
	local printed, realPrint = {}, print
	print = function(s) printed[#printed + 1] = s end
	local ok, err = pcall(ns.Crates.Slash)
	print = realPrint
	assert(ok, err)
	local text = table.concat(printed, "\n")
	has(text, "Merchant's Favor: 45 on this character")
	has(text, "1. Waylaid Crate: Apprentice Ingots")
	has(text, "fill 20 Copper Bar")
	has(text, "20 Merchant's Favor (tooltip)")
	has(text, "you hold 1: fill only")
	has(text, "best to buy and fill: Waylaid Crate: Apprentice Ingots")
	has(text, "best of the crates you hold: Waylaid Crate: Apprentice Herbs")
	-- Without a reward the crate is listed with the reason, never with a guessed figure.
	ns.db.crates[HERBS].reward = nil
	stub.tooltips[HERBS] = HERBS_LINES
	list = ns.Crates.Ranked()
	eq(list[2].id, HERBS); eq(list[2].perFavor, nil); has(table.concat(list[2].missing, ","), "reward not seen")
end)

it("snapshot sections crates and favor: ranking, balance, Favor merchants with costs and requirements", function()
	local ns, stub = setup()
	stub.tooltips[HERBS] = { HERBS_LINES[1], HERBS_LINES[2], { leftText = "30 Merchant's Favor" } }
	carry(stub, { [HERBS] = 1 })
	stub.ah[HERBS], stub.ah[SILVER] = 5000, 30
	ns.db.merchants[248201] = { name = "Pawani", zone = "The Barrens", map = 1413, x = 49.6, y = 29.6, t = 1794413475,
		faction = { id = 2587, name = "Durotar Supply and Logistics" }, standing = 4, items = {
			[252800] = { name = "Pattern: Defender's Leather Hood", p = 0, s = 1, n = -1,
				c = { { currency = FAVOR, name = "Merchant's Favor", amount = 30 } },
				req = { faction = "Durotar Supply and Logistics", standing = 6, text = "Requires Durotar Supply and Logistics - Honored" } },
			[252864] = { name = "Pattern: Mender's Leather Boots", p = 0, s = 1, n = -1, unusable = true,
				c = { { currency = FAVOR, name = "Merchant's Favor", amount = 90 } } },
		} }
	ns.db.merchants[3027] = { name = "Sewa Mistrunner", items = { [6530] = { name = "Nightcrawlers", p = 90, s = 1 } } }
	C_Reputation = { GetFactionDataByID = function(id)
		if id == 2587 then return { factionID = 2587, reaction = 4, currentStanding = 250, currentReactionThreshold = 0, nextReactionThreshold = 3000 } end
	end }
	stub.names.player = "Veli"
	stub.Fire("PLAYER_LOGOUT")
	local snap = CraftWiseDB.snapshots[ns.CharKey()]
	eq(snap.errors, nil); eq(snap.skipped.crates, nil); eq(snap.skipped.favor, nil)
	local c = snap.crates
	eq(c.best, HERBS); eq(c.bestHeld, HERBS); eq(#c.list, 1)
	local row = c.list[1]
	eq(row.name, "Waylaid Crate: Apprentice Herbs"); eq(row.tier, "Apprentice"); eq(row.held, 1)
	eq(row.crate, 5000); eq(row.fillCost, 600); eq(row.total, 5600); eq(row.reward, 30); eq(row.rewardFrom, "tooltip")
	eq(row.perFavor, 187); eq(row.fillPerFavor, 20); eq(#row.options, 5); eq(row.options[2].best, true); eq(row.options[1].cost, nil)
	local f = snap.favor
	eq(f.id, FAVOR); eq(f.name, "Merchant's Favor"); eq(f.balance, 45); eq(f.max, nil); eq(f.earned, 120)
	eq(#f.vendors, 1)
	local v = f.vendors[1]
	eq(v.npc, 248201); eq(v.name, "Pawani"); eq(v.faction, "Durotar Supply and Logistics"); eq(v.standing, "Neutral")
	eq(v.standingNow, "Neutral"); eq(v.rep.value, 250); eq(v.rep.max, 3000)
	eq(#v.items, 2); eq(v.items[1].favor, 30); eq(v.items[1].req, "Honored")
	eq(v.items[2].favor, 90); eq(v.items[2].unusable, true); eq(v.items[2].req, nil)
end)

it("without the currency API the Favor section keeps the recorded name and no balance", function()
	local ns, stub = setup()
	C_CurrencyInfo = nil
	ns.db.merchants[1] = { name = "V", items = { [5] = { name = "X", p = 0, c = { { currency = FAVOR, name = "Merchant's Favor", amount = 1 } } } } }
	local f = ns.Crates.SnapshotFavor()
	eq(f.name, "Merchant's Favor"); eq(f.balance, nil); eq(#f.vendors, 1)
	eq(ns.Crates.Balance(), nil)
	stub.Fire("PLAYER_LOGOUT")
end)

it("parses every crate tooltip text the client showed so far (both forms of the Use line)", function()
	local ns = setup()
	local seen = {
		{ "Use: Fill the crate with any bundle from the following list:|cnIQ1:\n- 20 Copper Ore\n- 20 Tin Ore|r", 2, "Tin Ore" },
		{ "Use: Fill the crate with any bundle from the following list:|cnIQ1:\n- 40 Linen Cloth\n- 20 Light Leather", 2, "Light Leather" },
		{ "Use: |cnIQ1:\n- 20 Strange Dust\n- 4 Greater Magic Essence\n- 6 Small Glimmering Shard\n- 2 Large Glimmering Shard|r", 4, "Large Glimmering Shard" },
		{ "Use: Fill the crate with any bundle from the following list:|cnIQ1:\n- 10 Stranglekelp\n- 10 Bruiseweed\n- 10 Wild Steelbloom\n- 10 Grave Moss\n- 10 Kingsblood", 5, "Kingsblood" },
		{ "Use: Fill the crate with any bundle from the following list:|cnIQ1:\n- 2 Cured Light Hide\n- 20 Bolt of Linen Cloth", 2, "Bolt of Linen Cloth" },
		{ "Use: Fill the crate with any bundle from the following list:|cnIQ1:\n- 16 Handful of Copper Bolts\n- 16 Copper Tube\n- 4 Copper Modulator", 3, "Copper Modulator" },
		{ "Use: Fill the crate with any bundle from the following list:|cnIQ1:\n- 8 Bronze Tube\n- 7 Whirring Bronze Gizmo\n- 4 Bronze Framework\n- 45 Gold Power Core", 4, "Gold Power Core" },
	}
	for _, s in ipairs(seen) do
		local p = ns.Crates.Parse({ { leftText = "Waylaid Crate" }, { leftText = s[1] } }, "Merchant's Favor")
		eq(#p.fill, s[2], s[1]); eq(p.fill[#p.fill].name, s[3]); eq(p.reward, nil)
	end
	local p = ns.Crates.Parse({ { leftText = seen[6][1] } }, "Merchant's Favor")
	eq(p.fill[1].n, 16); eq(p.fill[1].name, "Handful of Copper Bolts")
end)

it("after an AH full scan (#90): a crate the client hasn't cached is found by the scan's name, priced from the scan", function()
	local ns, stub = setup()
	stub.clock = 1794000000
	time = function() return stub.clock end
	stub.items[HERBS], stub.items[SILVER] = nil, nil -- neither in the client cache
	stub.tooltips[HERBS] = { HERBS_LINES[1], HERBS_LINES[2], { leftText = "30 Merchant's Favor" } }
	stub.zone, stub.subzone = "Orgrimmar", ""
	stub.Fire("AUCTION_HOUSE_SHOW")
	stub.replicate = {
		{ itemID = HERBS, count = 1, buyout = 4000, link = "item:" .. HERBS, owner = "Seller", name = "Waylaid Crate: Apprentice Herbs" },
		{ itemID = HERBS, count = 1, buyout = 4500, link = "item:" .. HERBS, owner = "Seller", name = "Waylaid Crate: Apprentice Herbs" },
		{ itemID = SILVER, count = 20, buyout = 500, link = "item:" .. SILVER, owner = "Seller", name = "Silverleaf" },
	}
	stub.Fire("REPLICATE_ITEM_LIST_UPDATE")
	eq(CraftWiseMarketDB.names[HERBS], "Waylaid Crate: Apprentice Herbs")
	ns.Crates.ScanMarket()
	eq(ns.db.crates[HERBS], nil, "tooltip waits for the item to load")
	stub.items[HERBS] = { name = "Waylaid Crate: Apprentice Herbs" }
	stub.Fire("GET_ITEM_INFO_RECEIVED", HERBS, true)
	eq(ns.db.crates[HERBS].seen.ah, true); eq(#ns.db.crates[HERBS].fill, 5)
	local list = ns.Crates.Ranked()
	local e = list[1]
	-- Crate: lowest of the scan (40s); Silverleaf resolved by the scan's name, 25c each.
	eq(e.crate, 4000); eq(e.fill.name, "Silverleaf"); eq(e.fill.id, SILVER); eq(e.fill.total, 500)
	eq(e.perFavor, 4500 / 30)
end)
