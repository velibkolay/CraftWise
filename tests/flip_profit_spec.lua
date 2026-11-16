-- Issue #330: realised AH -> vendor flips, the durable history and the stats.
local NOW = os.time({ year = 2026, month = 11, day = 16, hour = 12 })
local DAY = 86400
local LINEN, CLH = 2589, 4231

local function Load()
	local ns, stub = LoadAddon()
	stub.clock = NOW
	time = function(t)
		if t then return os.time(t) end
		return stub.clock
	end
	stub.names.player, stub.names.npc = "Veli", "Tharynn Bouden"
	stub.items[LINEN] = { name = "Linen Cloth", sellPrice = 13 }
	stub.items[CLH] = { name = "Cured Light Hide", sellPrice = 100 }
	stub.bank = {}
	function stub.SetBags(counts)
		local slots, ids = {}, {}
		for id in pairs(counts) do ids[#ids + 1] = id end
		table.sort(ids)
		for _, id in ipairs(ids) do
			if counts[id] > 0 then slots[#slots + 1] = { itemID = id, stackCount = counts[id] } end
		end
		stub.bags[0] = slots
	end
	C_Item.GetItemCount = function(id, includeBank)
		local n = 0
		for _, item in ipairs(stub.bags[0] or {}) do
			if item and item.itemID == id then n = n + item.stackCount end
		end
		return n + (includeBank and stub.bank[id] or 0)
	end
	stub.money = 100000
	stub.SetBags({ [LINEN] = 20 })
	stub.Fire("PLAYER_ENTERING_WORLD", true, false)
	return ns, stub
end

local function Trade(stub, bags, money)
	stub.SetBags(bags)
	stub.Fire("BAG_UPDATE_DELAYED")
	stub.money = money
	stub.Fire("PLAYER_MONEY")
	stub.RunTimers()
end

-- An AH commodity buy of n units for total copper; the units arrive in the bags.
local function AHBuy(stub, n, total, bags)
	stub.Fire("AUCTION_HOUSE_SHOW")
	C_AuctionHouse.StartCommoditiesPurchase(CLH, n)
	stub.Fire("COMMODITY_PRICE_UPDATED", total / n, total)
	C_AuctionHouse.ConfirmCommoditiesPurchase(CLH, n)
	stub.Fire("COMMODITY_PURCHASE_SUCCEEDED")
	stub.SetBags(bags)
	stub.Fire("BAG_UPDATE_DELAYED")
	stub.Fire("AUCTION_HOUSE_CLOSED")
end

local function OpenMerchant(stub)
	stub.merchant = {}
	stub.Fire("MERCHANT_SHOW")
end

it("a buy then a vendor sale gives one flip with the right profit", function()
	local ns, stub = Load()
	AHBuy(stub, 10, 600, { [LINEN] = 20, [CLH] = 10 })
	OpenMerchant(stub)
	Trade(stub, { [LINEN] = 20 }, stub.money + 1000)
	local rows = ns.Flips.Rows()
	eq(#rows, 1)
	eq(rows[1].q, 10); eq(rows[1].cost, 600); eq(rows[1].got, 1000); eq(rows[1].skip, 0)
	eq(rows[1].n, "Cured Light Hide")
	local s = ns.Flips.Stats("today")
	eq(s.profit, 400); eq(s.flips, 1); eq(s.units, 10); eq(s.spent, 600); eq(s.got, 1000); eq(s.avg, 400)
end)

it("a partial sale takes the average cost of the units sold; several buys average", function()
	local ns, stub = Load()
	AHBuy(stub, 10, 600, { [LINEN] = 20, [CLH] = 10 })
	AHBuy(stub, 10, 1000, { [LINEN] = 20, [CLH] = 20 }) -- average 80 each
	OpenMerchant(stub)
	Trade(stub, { [LINEN] = 20, [CLH] = 15 }, stub.money + 500) -- 5 sold
	local r = ns.Flips.Rows()[1]
	eq(r.q, 5); eq(r.cost, 400); eq(r.got, 500)
	Trade(stub, { [LINEN] = 20 }, stub.money + 1500) -- the other 15
	local rows = ns.Flips.Rows()
	eq(#rows, 2)
	eq(rows[2].q, 15); eq(rows[2].cost, 1200)
	eq(ns.Flips.Stats("all").profit, (500 - 400) + (1500 - 1200))
end)

it("units without a known AH cost are left out and the record says so", function()
	local ns, stub = Load()
	AHBuy(stub, 4, 240, { [LINEN] = 20, [CLH] = 4 })
	stub.SetBags({ [LINEN] = 20, [CLH] = 10 }) -- 6 looted: no price
	stub.Fire("BAG_UPDATE_DELAYED")
	OpenMerchant(stub)
	Trade(stub, { [LINEN] = 20 }, stub.money + 1000) -- all 10 sold
	local r = ns.Flips.Rows()[1]
	eq(r.q, 4); eq(r.skip, 6); eq(r.cost, 240); eq(r.got, 400) -- 4 of 10 units: 4/10 of what was paid
	-- a sale of units that never had an AH price is no flip
	stub.SetBags({ [LINEN] = 20, [CLH] = 3 })
	stub.Fire("BAG_UPDATE_DELAYED")
	Trade(stub, { [LINEN] = 20 }, stub.money + 300)
	eq(#ns.Flips.Rows(), 1)
end)

it("units bought at a vendor are no AH flip", function()
	local ns, stub = Load()
	stub.merchant = { { itemID = CLH, price = 50, stack = 1 } }
	stub.Fire("MERCHANT_SHOW")
	Trade(stub, { [LINEN] = 20, [CLH] = 5 }, stub.money - 250)
	Trade(stub, { [LINEN] = 20 }, stub.money + 500)
	eq(#ns.Flips.Rows(), 0)
end)

it("a buyback undoes the flip and gives the AH cost back to the position", function()
	local ns, stub = Load()
	AHBuy(stub, 10, 600, { [LINEN] = 20, [CLH] = 10 })
	OpenMerchant(stub)
	stub.buyback = 1
	Trade(stub, { [LINEN] = 20 }, stub.money + 1000)
	eq(#ns.Flips.Rows(), 1)
	stub.buyback = 0
	Trade(stub, { [LINEN] = 20, [CLH] = 10 }, stub.money - 1000)
	eq(#ns.Flips.Rows(), 0)
	eq(ns.Flips.Stats("all").profit, 0)
	-- sold again: the same cost counts
	stub.buyback = 1
	Trade(stub, { [LINEN] = 20 }, stub.money + 1000)
	eq(ns.Flips.Rows()[1].cost, 600)
end)

it("the stats windows: today, 7 days, 30 days, all, best items", function()
	local ns = Load()
	local rows = ns.Flips.Rows()
	local function row(daysAgo, itemID, q, cost, got)
		rows[#rows + 1] = { t = NOW - daysAgo * DAY, c = ns.CharKey(), i = itemID, q = q, cost = cost, got = got, skip = 0 }
	end
	row(40, LINEN, 1, 10, 20)
	row(20, CLH, 2, 100, 150)
	row(3, CLH, 1, 50, 60)
	row(0, LINEN, 5, 100, 80) -- a loss
	eq(ns.Flips.Stats("today", NOW).profit, -20)
	eq(ns.Flips.Stats("d7", NOW).profit, -10)
	eq(ns.Flips.Stats("d7", NOW).flips, 2)
	eq(ns.Flips.Stats("d30", NOW).profit, 40)
	local all = ns.Flips.Stats("all", NOW)
	eq(all.profit, 50); eq(all.flips, 4); eq(all.units, 9); eq(all.spent, 260); eq(all.got, 310)
	eq(all.avg, 13) -- 50 / 4 rounded
	eq(all.best[1].itemID, CLH); eq(all.best[1].profit, 60)
end)

it("trimming: rows fold into days after 90 days, days into older after a year, totals stay", function()
	local ns = Load()
	local rows = ns.Flips.Rows()
	local function row(daysAgo, q, cost, got)
		rows[#rows + 1] = { t = NOW - daysAgo * DAY, c = ns.CharKey(), i = CLH, q = q, cost = cost, got = got, skip = 0 }
	end
	row(500, 1, 10, 30)
	row(100, 2, 20, 50)
	row(100, 1, 5, 10)
	row(10, 1, 7, 9)
	local before = ns.Flips.Stats("all", NOW)
	ns.Flips.Prune(NOW)
	eq(#ns.Flips.Rows(), 1)
	local store = CraftWiseMarketDB.flips
	local days = 0
	for _ in pairs(store.days) do days = days + 1 end
	eq(days, 1) -- the 100 day old rows share a day; the 500 day old one went to older
	eq(store.older[CLH].q, 1)
	local after = ns.Flips.Stats("all", NOW)
	eq(after.profit, before.profit); eq(after.flips, before.flips); eq(after.units, before.units)
	eq(ns.Flips.Stats("d30", NOW).flips, 1) -- folded data never shows in the short windows
	local hist = ns.Flips.History()
	eq(#hist, 2) -- the row and the folded day
	eq(hist[1].day, nil)
	assert(hist[2].day, "folded day")
end)

it("the Flips page lists newest first with a hero and names, never bare ids", function()
	local ns, stub = Load()
	AHBuy(stub, 10, 600, { [LINEN] = 20, [CLH] = 10 })
	OpenMerchant(stub)
	Trade(stub, { [LINEN] = 20 }, stub.money + 1000)
	local P = ns.Main.Page("flips").P
	local model = P.Model()
	eq(#model.rows, 1)
	eq(model.rows[1].name, "Cured Light Hide")
	eq(model.rows[1].profit, 400)
	eq(model.hero.profit, 400)
	assert(model.hero.caption:find("Cured Light Hide", 1, true), model.hero.caption)
end)
