-- Issue #26 phase 2: price basis and house for profit, fallback order and labels, depth figures,
-- thin market, best house to buy and sell, "cut unverified", tooltip lines.
local Make = dofile("tests/make_helpers.lua")
local NOW = 1794000000
local DAY = 86400
local HORDE, BOOTY, GADGET, ALLIANCE = "PvP|H", "PvP|N:BootyBay", "PvP|N:Gadgetzan", "PvP|A"
local HOUSES = {
	[HORDE] = { realm = "PvP", kind = "faction", faction = "Horde", label = "Horde AH" },
	[ALLIANCE] = { realm = "PvP", kind = "faction", faction = "Alliance", label = "Alliance AH" },
	[BOOTY] = { realm = "PvP", kind = "neutral", label = "Booty Bay", cut = { samples = 0 } },
	[GADGET] = { realm = "PvP", kind = "neutral", label = "Gadgetzan", cut = { samples = 0 } },
}

local function Load(opts)
	local ns, stub = LoadAddon(opts)
	stub.clock = NOW
	time = function() return stub.clock end
	return ns, stub
end

-- o.typs: typ per day, today first. o.tiers = { p1, q1, ... } latest point; o.min/o.total without
-- tiers = a browse-only price. o.gone = a later full scan found none.
local function Seed(itemID, house, o)
	local db = CraftWiseMarketDB
	local today = math.floor(NOW / DAY)
	local days = {}
	for i, typ in ipairs(o.typs or {}) do
		days[today - i + 1] = { lo = typ, typ = typ, hi = typ, n = 1 }
	end
	local t = o.t or NOW
	local raw = {}
	if o.tiers then
		raw[1] = { t = t, total = o.total, listings = o.listings, tiers = o.tiers }
	end
	local min = o.tiers and o.tiers[1] or o.min
	if o.gone then
		raw[#raw + 1] = { t = t + 10, total = 0, listings = 0, tiers = {} }
	end
	db.items[itemID] = db.items[itemID] or {}
	db.items[itemID][house] = { raw = raw, days = days,
		last = min and { t = t, min = min, qty = o.total, listings = o.listings } or nil }
	if not db.houses[house] then
		local h = HOUSES[house]
		db.houses[house] = { realm = h.realm, kind = h.kind, faction = h.faction, label = h.label, cut = h.cut and { samples = 0 } }
	end
	db.scans[house] = { { t = NOW, kind = "search", items = 1, source = "ui" } }
end

local function Money(ns) return function(c) return ns.FormatMoney(c, true) end end

----------------------------------------------------------------------------------- basis and house

it("defaults: typical basis at the own faction house", function()
	local ns = Load()
	eq(ns.db.settings.priceBasis, "typical"); eq(ns.db.settings.priceHouse, "faction")
	local key, label, kind = ns.ProfitHouse()
	eq(key, HORDE); eq(label, "Horde AH"); eq(kind, "faction")
	ns.db.settings.priceHouse = "Gadgetzan"
	eq((ns.ProfitHouse()), GADGET)
end)

it("profit price follows the basis and house settings, each labelled", function()
	local ns = Load()
	Seed(5, HORDE, { typs = { 200, 210, 190 }, tiers = { 150, 10 }, total = 10 })
	Seed(5, BOOTY, { typs = { 80 }, tiers = { 90, 40 }, total = 40 })
	local q = ns.AuctionQuote(5)
	eq(q.copper, 200); eq(q.source, "market"); eq(q.label, "typical · Horde AH")
	ns.db.settings.priceBasis = "current"
	q = ns.AuctionQuote(5)
	eq(q.copper, 150); eq(q.label, "current lowest · Horde AH")
	ns.db.settings.priceHouse = "BootyBay"
	eq(ns.AuctionQuote(5).copper, 90)
	ns.db.settings.priceBasis = "typical"
	q = ns.AuctionQuote(5)
	eq(q.copper, 90, "too little history: current lowest at that house")
	eq(q.fallback, "too little history"); eq(q.label, "current lowest, too little history · Booty Bay")
	eq(ns.GetBuyPrice(5).label, "current lowest, too little history · Booty Bay")
end)

it("fallback order: market, then Auctionator labelled house unknown, then no price data", function()
	local ns, stub = Load({ auctionator = true })
	stub.ah[5], stub.ah[6] = 777, 888
	Seed(5, HORDE, { typs = { 200, 200, 200 }, tiers = { 150, 10 }, total = 10 })
	eq(ns.AuctionQuote(5).copper, 200)
	local q = ns.AuctionQuote(6)
	eq(q.copper, 888); eq(q.source, "auctionator"); eq(q.label, "Auctionator (house unknown)")
	eq(ns.GetBuyPrice(6).label, "Auctionator (house unknown)")
	eq(ns.AuctionQuote(7), nil)
	stub.DisableAuctionator()
	eq(ns.AuctionQuote(6), nil)
	eq(ns.GetBuyPrice(6), nil)
end)

it("an item a full scan found absent has no current price; its typical still counts", function()
	local ns, stub = Load({ auctionator = true })
	stub.ah[5] = 777
	Seed(5, HORDE, { typs = { 200 }, tiers = { 150, 10 }, total = 10, gone = true })
	eq(ns.AuctionQuote(5).copper, 777, "typical has too little history, current is gone: Auctionator")
	ns.db.settings.priceBasis = "current"
	eq(ns.AuctionQuote(5).source, "auctionator")
	Seed(5, HORDE, { typs = { 200, 200, 200 }, tiers = { 150, 10 }, total = 10, gone = true })
	ns.db.settings.priceBasis = "typical"
	eq(ns.AuctionQuote(5).copper, 200)
	local _, why = ns.Market.Quote(5, HORDE, "current")
	eq(why, "not listed")
end)

it("prices of the other faction or another realm are never used", function()
	local ns, stub = Load()
	Seed(5, ALLIANCE, { typs = { 50, 50, 50 }, tiers = { 50, 100 }, total = 100 })
	eq(ns.AuctionQuote(5), nil)
	eq(#ns.Market.UsableHouses(5), 0)
	stub.faction = "Alliance"
	eq(ns.AuctionQuote(5).copper, 50)
	stub.realm = "PvE"
	eq(ns.AuctionQuote(5), nil)
end)

----------------------------------------------------------------------------------------- the cut

it("sale: 5% at the own faction house, cut unverified at a neutral house, measured cut when known", function()
	local ns, stub = Load()
	stub.items[5] = { name = "Vest", sellPrice = 10 }
	Seed(5, HORDE, { tiers = { 1000, 5 }, total = 5 })
	Seed(5, BOOTY, { tiers = { 2000, 5 }, total = 5 })
	ns.db.settings.priceBasis = "current"
	local v = ns.GetSellValue(5)
	eq(v.copper, 950); eq(v.cut, 0.05); eq(v.cutUnverified, nil)
	ns.db.settings.priceHouse = "BootyBay"
	v = ns.GetSellValue(5)
	eq(v.copper, 2000); eq(v.gross, 2000); eq(v.cutUnverified, true); eq(v.cut, nil)
	stub.items[5].sellPrice = 2500
	eq(ns.GetSellValue(5).source, "vendor", "a vendor paying more than the gross wins")
	stub.items[5].sellPrice = 10
	CraftWiseMarketDB.houses[BOOTY].cut = { rate = 0.15, samples = 4 }
	v = ns.GetSellValue(5)
	eq(v.copper, 1700); eq(v.cutUnverified, nil)
end)

it("profit is not computed from a sale whose cut is unverified", function()
	local ns = Load()
	local r = ns.Profit.Evaluate({ reagents = { { itemID = 1, quantity = 2 } }, output = { itemID = 2, quantity = 3 } }, {
		buy = function() return { copper = 10, source = "auction", label = "typical · Horde AH", thin = true } end,
		sell = function() return { copper = 100, gross = 100, source = "auction", cutUnverified = true, label = "typical · Booty Bay" } end,
	})
	eq(r.sellsFor, 300); eq(r.sellGross, 300); eq(r.cutUnverified, true); eq(r.profit, nil)
	eq(r.complete, true, "every price is there; only the cut is missing")
	eq(r.reagents[1].label, "typical · Horde AH"); eq(r.reagents[1].thin, true); eq(r.thin, true)
	eq(r.sellLabel, "typical · Booty Bay")
	r = ns.Profit.Evaluate({ reagents = { { itemID = 1, quantity = 2 } }, output = { itemID = 2, quantity = 1 } }, {
		buy = function() return { copper = 10, source = "vendor" } end,
		sell = function() return { copper = 95, gross = 100, cut = 0.05, source = "auction" } end,
	})
	eq(r.profit, 75); eq(r.thin, nil)
end)

it("profit rows and the level view follow the house; neutral sales say cut unverified", function()
	local ns, stub = Load()
	stub.profession = { id = 165, name = "Leatherworking", skill = 60, max = 75, recipes = {
		[3763] = { info = { name = "Belt", learned = true }, schematic = stub.Schematic({ { 2318, 2 } }, 4246) } } }
	stub.Fire("TRADE_SKILL_SHOW")
	ns.db.settings.priceBasis = "current"
	Seed(2318, HORDE, { tiers = { 30, 100 }, total = 100 })
	Seed(4246, HORDE, { tiers = { 1000, 3 }, total = 3 })
	Seed(4246, BOOTY, { tiers = { 1500, 3 }, total = 3 })
	local row = ns.BuildRows(165, false)[1]
	eq(row.cost, 60); eq(row.sellsFor, 950); eq(row.profit, 890)
	local sale, source, details = ns.Leveling.Sale({ itemID = 4246, quantity = 1 })
	eq(sale, 950); eq(source, "auction"); eq(details.label, "current lowest · Horde AH")
	ns.db.settings.priceHouse = "BootyBay"
	row = ns.BuildRows(165, false)[1]
	eq(row.cutUnverified, true); eq(row.profit, nil); eq(row.sellsFor, 1500)
	eq(row.reagents[1].total, nil, "no Light Leather recorded at Booty Bay, no Auctionator: no price")
	sale, source, details = ns.Leveling.Sale({ itemID = 4246, quantity = 1 })
	eq(sale, nil); eq(details.cutUnverified, true); eq(details.ahGross, 1500)
end)

---------------------------------------------------------------------------------- depth figures

it("depth text: quantity @ price, cheapest first", function()
	local ns = Load()
	local depth = { { price = 250, qty = 3 }, { price = 1000, qty = 25 }, { price = 1200, qty = 7 } }
	eq(ns.Market.DepthText(depth, 2, Money(ns)), "3 @ 2s 50c · 25 @ 10s")
	eq(ns.Market.DepthText(depth, 9, Money(ns)), "3 @ 2s 50c · 25 @ 10s · 7 @ 12s")
	eq(ns.Market.DepthText({}, 2, Money(ns)), "")
end)

it("units within +10% of min, a lower bound when the stored tiers end inside it", function()
	local M = Load().Market
	local units, partial = M.NearMin({ total = 100, { price = 100, qty = 3 }, { price = 110, qty = 7 }, { price = 111, qty = 90 } })
	eq(units, 10); eq(partial, false)
	units, partial = M.NearMin({ total = 500, { price = 100, qty = 3 }, { price = 105, qty = 7 } })
	eq(units, 10); eq(partial, true)
	eq(M.NearMin({}), nil)
end)

it("thin market: cheapest tier under one stack, or under 10% of the units within +10%", function()
	local M = Load().Market
	local function D(...)
		local d, a = { total = 0 }, { ... }
		for i = 1, #a, 2 do d[#d + 1] = { price = a[i], qty = a[i + 1] }; d.total = d.total + a[i + 1] end
		return d
	end
	local thin, why = M.IsThin(D(250, 3, 1000, 25), 20)
	eq(thin, true); eq(why, "stack")
	eq((M.IsThin(D(250, 20, 1000, 25), 20)), false, "a full stack, and the next tier is beyond +10%")
	thin, why = M.IsThin(D(100, 2, 105, 30), nil)
	eq(thin, true); eq(why, "share")
	eq((M.IsThin(D(100, 4, 105, 30), nil)), false, "4 of 34 is over 10%")
	eq((M.IsThin(D(100, 1), 1)), false, "one unsellable-in-stacks item is a full stack")
	eq((M.IsThin(nil, 20)), false); eq((M.IsThin({}, 20)), false)
end)

it("best to buy: lowest cost for one craft batch, else lowest; only usable houses", function()
	local ns = Load()
	local M = ns.Market
	Seed(5, HORDE, { tiers = { 30, 3, 100, 25 }, total = 28 })
	Seed(5, BOOTY, { tiers = { 50, 6 }, total = 6 })
	Seed(5, ALLIANCE, { tiers = { 1, 1000 }, total = 1000 })
	local best = M.BestToBuy(5, 6)
	eq(best.label, "Booty Bay"); eq(best.cost, 300); eq(best.unit, 50)
	best = M.BestToBuy(5, 3)
	eq(best.label, "Horde AH"); eq(best.cost, 90)
	best = M.BestToBuy(5, 1)
	eq(best.label, "Horde AH"); eq(best.unit, 30); eq(best.atPrice, 3); eq(best.qty, 28)
	local none, cheapest = M.BestToBuy(5, 100)
	eq(none, nil); eq(cheapest.label, "Horde AH"); eq(cheapest.unit, 30)
	eq(M.FillBatch({ { price = 3, qty = 1 }, { price = 4, qty = 2 } }, 2).unit, 4, "average rounded up")
end)

it("best to sell: highest gross while no cut is measured, then highest net among measured", function()
	local ns = Load()
	local M = ns.Market
	Seed(5, HORDE, { typs = { 1000, 1000, 1000 }, tiers = { 900, 4 }, total = 4 })
	Seed(5, BOOTY, { tiers = { 1200, 2 }, total = 2 })
	local best = M.BestToSell(5, "typical")
	eq(best.label, "Booty Bay"); eq(best.gross, 1200); eq(best.cutUnverified, true); eq(best.net, nil)
	eq(best.fallback, "too little history")
	CraftWiseMarketDB.houses[HORDE].cut = { rate = 0.05, samples = 2 }
	best = M.BestToSell(5, "typical")
	eq(best.label, "Horde AH"); eq(best.net, 950); eq(best.cutUnverified, nil); eq(best.unverifiedLeft, 1); eq(best.qty, 4)
	eq(M.BestToSell(6, "typical"), nil)
end)

------------------------------------------------------------------------------------------ tooltips

local function TooltipText(ns, itemID)
	local tip = { lines = {} }
	function tip:AddLine(t) table.insert(self.lines, t) end
	function tip:AddDoubleLine(l, r) table.insert(self.lines, l .. " | " .. r) end
	function tip:Show() end
	ns.AddTooltipLines(tip, itemID)
	return table.concat(tip.lines, "\n")
end

local function has(text, s) assert(text:find(s, 1, true), ("missing %q in:\n%s"):format(s, text)) end

it("item tooltip: profit house in detail, best to buy and sell, other houses", function()
	local ns, stub = Load()
	stub.items[5] = { name = "Light Leather", stack = 20 }
	Seed(5, HORDE, { typs = { 300, 320, 310 }, tiers = { 250, 3, 1000, 25 }, total = 28, listings = 2, t = NOW - 180 })
	Seed(5, BOOTY, { typs = { 200 }, tiers = { 200, 40 }, total = 40, t = NOW - 7200 })
	local t = TooltipText(ns, 5)
	has(t, "Horde AH | typical ")
	has(t, "(3 days)")
	has(t, "Current | min ")
	has(t, "28 units · 2 price levels · seen 3m ago")
	has(t, "Cheapest | 3 @ ")
	has(t, "Within +10% of min | 3 units")
	has(t, "Last 7 days | ")
	has(t, "Thin market")
	has(t, "under one stack (20)")
	has(t, "Best to buy | Booty Bay")
	has(t, "(40 at that price)")
	has(t, "Best to sell | Horde AH")
	has(t, "gross (typical) · cut unverified · 28 listed there")
	has(t, "  Booty Bay | min ")
	has(t, "too little history · 2h ago")
	assert(not t:find("PvP|", 1, true), "labels, not keys")
end)

it("item tooltip: gear counts listings, unknown stack sizes show no count", function()
	local ns, stub = Load()
	stub.items[5] = { name = "Belt", stack = 1 }
	Seed(5, HORDE, { tiers = { 900, 1 }, total = 1, listings = 1 })
	has(TooltipText(ns, 5), "1 listings")
	stub.items[5] = { name = "Belt" }
	local t = TooltipText(ns, 5)
	assert(not t:find("listings", 1, true) and not t:find("price levels", 1, true), t)
end)

it("item tooltip: no data says so at the profit house; nothing without any house; line can be off", function()
	local ns = Load()
	assert(not TooltipText(ns, 5):find("Best to", 1, true))
	Seed(5, BOOTY, { tiers = { 200, 40 }, total = 40 })
	local t = TooltipText(ns, 5)
	has(t, "Horde AH | no price data")
	has(t, "Best to buy | Booty Bay")
	ns.db.tooltip.lines.market = false
	assert(not TooltipText(ns, 5):find("Horde AH", 1, true))
end)

it("buy lines for a reagent: profit house figures and the best house for one craft", function()
	local ns = Load()
	Seed(5, HORDE, { tiers = { 30, 3, 100, 25 }, total = 28 })
	Seed(5, BOOTY, { tiers = { 50, 6 }, total = 6 })
	local lines = ns.MarketLines(5, { mode = "buy", need = 6, name = "Light Leather" })
	eq(#lines, 2)
	eq(lines[1][1], "  Light Leather")
	has(lines[1][2], "Horde AH: min ")
	eq(lines[2][1], "    best for 6")
	has(lines[2][2], "Booty Bay  6 for ")
	lines = ns.MarketLines(5, { mode = "buy", need = 50 })
	has(lines[2][2], "no house shows 50 units; lowest ")
end)

----------------------------------------------------------------------------------- window + settings

it("Make › Craft: rows flag a thin market, tooltips show labels and the market section", function()
	local ns, stub = Load()
	stub.items[2318] = { name = "Light Leather", stack = 20 }
	stub.items[4246] = { name = "Belt", sellPrice = 1 }
	stub.profession = { id = 165, name = "Leatherworking", skill = 60, max = 75, recipes = {
		[3763] = { info = { name = "Belt", learned = true }, schematic = stub.Schematic({ { 2318, 6 } }, 4246) } } }
	stub.Fire("TRADE_SKILL_SHOW")
	Seed(2318, HORDE, { tiers = { 30, 3, 32, 100 }, total = 103 })
	Seed(4246, BOOTY, { tiers = { 1500, 3 }, total = 3 })
	ns.db.settings.priceBasis = "current"
	local row = ns.BuildRows(165, false)[1]
	eq(row.thin, true)
	local lines = {}
	GameTooltip.AddLine = function(_, t) lines[#lines + 1] = t end
	GameTooltip.AddDoubleLine = function(_, l, r) lines[#lines + 1] = l .. " | " .. r end
	Make.Open(ns, "craft", 165)
	assert(Make.Hover(ns, "craft", 3763), "a row rendered")
	local t = table.concat(lines, "\n")
	has(t, "current lowest · Horde AH")
	has(t, "Auction houses")
	has(t, "Reagents, one craft")
	has(t, "best for 6")
	has(t, "Crafted item")
	has(t, "Horde AH | no price data")
	has(t, "Best to sell | Booty Bay")
	eq(Make.Rows(ns, "craft")[1].view.sellsText, "1c vendor · thin", "the row is marked thin")
	local foot = ns.Main.Frame().foot
	assert(foot.left.text:find("Prices: current lowest · Horde AH", 1, true), foot.left.text)
	-- Light Leather at Booty Bay too, so only the sale's cut is missing there.
	Seed(2318, BOOTY, { tiers = { 30, 100 }, total = 100 })
	ns.db.settings.priceHouse = "BootyBay"
	ns.Main.Refresh()
	local r = Make.Rows(ns, "craft")[1]
	eq(r.view.cells.profit, "—", "no profit while the cut is unverified")
	eq(r.view.tips.profit[1], "AH cut not verified at Booty Bay")
	assert(r.view.sellsText:find("15s AH gross", 1, true), r.view.sellsText)
	assert(foot.right.text:find("1 sell where the AH cut is unverified", 1, true), foot.right.text)
end)

it("settings: basis and house buttons; houses without data can't be picked", function()
	local ns = Load()
	Seed(5, BOOTY, { tiers = { 200, 40 }, total = 40 })
	ns.ToggleSettings() -- the old panel, until #157 part 2 (the Settings page: tests/settings_page_spec.lua)
	local p = CraftWiseSettings
	p.basis.current.scripts.OnClick(p.basis.current)
	eq(ns.db.settings.priceBasis, "current")
	p.basis.typical.scripts.OnClick(p.basis.typical)
	eq(ns.db.settings.priceBasis, "typical")
	eq(p.houses.faction.label.text, "Horde AH")
	p.houses.Gadgetzan.scripts.OnClick(p.houses.Gadgetzan)
	eq(ns.db.settings.priceHouse, "faction", "no data at Gadgetzan")
	p.houses.BootyBay.scripts.OnClick(p.houses.BootyBay)
	eq(ns.db.settings.priceHouse, "BootyBay")
	assert(p.houseHint.text:find("No data yet: Horde AH, Gadgetzan, Everlook", 1, true), p.houseHint.text)
	p.houses.faction.scripts.OnClick(p.houses.faction)
	eq(ns.db.settings.priceHouse, "faction", "the own faction house is always selectable")
end)
