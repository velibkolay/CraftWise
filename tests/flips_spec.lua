-- AH → vendor flips (#312): items whose cheapest buyouts at the profit house are below what a vendor pays,
-- found after each scan, announced once, put into the basket and the Auctionator list "CraftWise vendor flips".
local Make = dofile("tests/make_helpers.lua")
local NOW = 1794000000
local HORDE = "PvP|H"
local CLOTH, SILK, JUNKY, FREE = 100, 200, 300, 400

local function Load(opts)
	local ns, stub = LoadAddon(opts)
	stub.clock = NOW
	time = function() return stub.clock end
	stub.items[CLOTH] = { name = "Linen Cloth", sellPrice = 100 }
	stub.items[SILK] = { name = "Silk Cloth", sellPrice = 1000 }
	stub.items[JUNKY] = { name = "Odd Thing" } -- sellPrice unknown
	stub.items[FREE] = { name = "Worthless Thing", sellPrice = 0 }
	return ns, stub, ns.Main
end

-- o.tiers = { p1, q1, ... } ascending, o.total; o.t = when seen; o.off = a later full scan found none;
-- o.lastT = `last.t` when a browse updated only the price later; o.packed = store it as the saved string.
local function Seed(ns, itemID, o)
	local db = CraftWiseMarketDB
	local t = o.t or NOW
	local entry = { raw = { { t = t, total = o.total or 0, listings = 1, tiers = o.tiers } }, days = {},
		last = { t = o.lastT or t, min = o.tiers[1], qty = o.total, listings = 1, off = o.off } }
	db.items[itemID] = db.items[itemID] or {}
	db.items[itemID][HORDE] = o.packed and ns.Market.EncodeEntry(entry) or entry
	db.houses[HORDE] = db.houses[HORDE] or { realm = "PvP", kind = "faction", faction = "Horde", label = "Horde AH" }
	db.scans[HORDE] = { { t = NOW, kind = "scan", items = 1, source = "ui" } }
end

----------------------------------------------------------------------------------------------- maths

it("Flip: units and profit from the tiers below the vendor price; at the price or above is no flip", function()
	local ns = Load()
	local f = ns.Loops.Flip({ 40, 5, 90, 10, 100, 3, 150, 2 }, 20, 100)
	eq(f.units, 15); eq(f.profit, 60 * 5 + 10 * 10); eq(f.price, 40); eq(f.sell, 100); eq(f.maxUnit, 99)
	eq(f.atLeast, false, "tiers above the vendor price show the list goes past it")
	eq(ns.Loops.Flip({ 100, 5, 120, 1 }, 6, 100), nil, "at the vendor price earns nothing")
	eq(ns.Loops.Flip({ 150, 5 }, 5, 100), nil)
	eq(ns.Loops.Flip({ 40, 5 }, 5, nil), nil, "unknown vendor price")
	eq(ns.Loops.Flip({ 40, 5 }, 5, 0), nil, "vendors don't buy it")
	eq(ns.Loops.Flip({}, 0, 100), nil)
end)

it("Flip: every stored tier below the vendor price (eight) or more units listed than stored: at least", function()
	local ns = Load()
	local eight = {}
	for i = 1, 8 do
		eight[#eight + 1] = i * 10
		eight[#eight + 1] = 2
	end
	local f = ns.Loops.Flip(eight, 16, 100)
	eq(f.units, 16); eq(f.atLeast, true)
	f = ns.Loops.Flip({ 10, 2, 20, 3 }, 5, 100)
	eq(f.atLeast, false, "the whole list is below, nothing more exists")
	f = ns.Loops.Flip({ 10, 2, 20, 3 }, 9, 100)
	eq(f.atLeast, true, "the list holds more units than the tiers")
end)

it("FlipFinds: smallest total profit and best first; FlipFresh announces new or clearly better ones only", function()
	local ns = Load()
	local L = ns.Loops
	local rows = {
		{ itemID = CLOTH, total = 5, tiers = { 40, 5 } }, -- 300
		{ itemID = SILK, total = 2, tiers = { 500, 2 } }, -- 1000
		{ itemID = 9, total = 1, tiers = { 99, 1 } }, -- 1
	}
	local sell = function(id) return ({ [CLOTH] = 100, [SILK] = 1000, [9] = 100 })[id] end
	local finds = L.FlipFinds(rows, sell, 100)
	eq(#finds, 2); eq(finds[1].itemID, SILK); eq(finds[2].itemID, CLOTH)
	eq(#L.FlipFinds(rows, sell, 0), 3, "0 allows anything above 0")
	local fresh, keep = L.FlipFresh(finds, {})
	eq(#fresh, 2)
	fresh, keep = L.FlipFresh(finds, keep)
	eq(#fresh, 0, "same again: no toast")
	finds[2] = { itemID = CLOTH, profit = 440 }
	fresh, keep = L.FlipFresh(finds, keep)
	eq(#fresh, 0, "+47 % is not clearly better")
	finds[2] = { itemID = CLOTH, profit = 460 }
	fresh = L.FlipFresh(finds, keep)
	eq(#fresh, 1); eq(fresh[1].itemID, CLOTH)
	eq(L.FlipSummary(fresh), "1 AH → vendor flip"); eq(L.FlipSummary({ {}, {} }), "2 AH → vendor flips"); eq(L.FlipSummary({}), nil)
end)

----------------------------------------------------------------------------------------------- Market

it("Market.FreshBelow: this scan's listings at the house only; stale, off, newer-price-only, no tiers are skipped", function()
	local ns = Load()
	Seed(ns, CLOTH, { tiers = { 40, 5 }, total = 5 })
	Seed(ns, SILK, { tiers = { 500, 2 }, total = 2, packed = true })
	Seed(ns, JUNKY, { tiers = { 5, 1 }, total = 1, t = NOW - 3600 }) -- stale
	Seed(ns, FREE, { tiers = { 5, 1 }, total = 1, off = NOW + 5 }) -- a later scan didn't list it
	Seed(ns, 500, { tiers = { 5, 1 }, total = 1, lastT = NOW + 600 }) -- a browse updated only the price later
	Seed(ns, 501, { tiers = { 5000, 1 }, total = 1 }) -- above the limit
	CraftWiseMarketDB.items[502] = { [HORDE] = ns.Market.EncodeEntry({ last = { t = NOW, min = 5, qty = 1, listings = 1 }, raw = {}, days = {} }) }
	CraftWiseMarketDB.items[CLOTH]["PvP|A"] = CraftWiseMarketDB.items[CLOTH][HORDE] -- another house: never read
	local rows = ns.Market.FreshBelow(HORDE, NOW + 10, 1800, function(id) return id == 501 and 100 or 1100 end)
	table.sort(rows, function(a, b) return a.itemID < b.itemID end)
	local ids = {}
	for _, r in ipairs(rows) do ids[#ids + 1] = r.itemID end
	eq(table.concat(ids, ","), "100,200", "last-only records have no tiers: not read")
	eq(rows[1].tiers[1], 40); eq(rows[2].tiers[1], 500); eq(rows[2].total, 2)
	eq(#ns.Market.FreshBelow("PvP|N:BootyBay", NOW, 1800, function() return 1100 end), 0, "no data at that house")
end)

----------------------------------------------------------------------------------------------- the check

local function Scan(ns, stub)
	stub.clock = stub.clock + 10
	ns.Notify("PRICES_CHANGED"); ns.Notify("PRICES_CHANGED")
	stub.RunTimers()
end

it("Loops: a scan puts flips into the basket, one toast, the same flips again no second toast", function()
	local ns, stub, M = Load()
	Seed(ns, CLOTH, { tiers = { 40, 5, 90, 10 }, total = 15 }) -- +400, 15 units
	Seed(ns, SILK, { tiers = { 990, 1 }, total = 1 }) -- +10: below the smallest profit (1s)
	ns.Notify("PRICES_CHANGED")
	eq(#ns.LootToast.Lines(), 0, "nothing before the debounce ends")
	stub.RunTimers()
	local lines = ns.LootToast.Lines()
	eq(#lines, 1); eq(lines[1].text, "1 AH → vendor flip"); eq(lines[1].detail, "Linen Cloth ×15"); eq(lines[1].copper, 400)
	eq(ns.LootToast.LineParts(lines[1]).source, "AH → vendor")
	local flips = ns.Basket.Flips()
	eq(#flips, 1); eq(flips[1].itemID, CLOTH); eq(flips[1].units, 15); eq(flips[1].maxUnit, 99); eq(flips[1].profit, 400)
	Scan(ns, stub)
	eq(#ns.LootToast.Lines(), 1, "the same flips: no second toast")
	-- the section is replaced per scan: a flip that was bought out drops away
	Seed(ns, CLOTH, { tiers = { 120, 4 }, total = 4, t = stub.clock })
	Scan(ns, stub)
	eq(#ns.Basket.Flips(), 0)
	-- it comes back: new again
	ns.LootToast.Clear()
	Seed(ns, CLOTH, { tiers = { 40, 5 }, total = 5, t = stub.clock })
	Scan(ns, stub)
	eq(#ns.LootToast.Lines(), 1); eq(#ns.Basket.Flips(), 1)
	-- the toast opens the basket
	lines = ns.LootToast.Lines()
	lines[1].onClick(lines[1])
	eq(M.CurrentPage().key, "basket")
end)

it("Loops: loops and flips of one scan share one toast", function()
	local ns, stub = Load()
	Seed(ns, CLOTH, { tiers = { 40, 5 }, total = 5 })
	ns.Loops.Check = function() return { { recipeID = 1, professionID = 1, name = "Test Gloves", profit = 21, loop = true } } end
	ns.Notify("PRICES_CHANGED"); stub.RunTimers()
	local lines = ns.LootToast.Lines()
	eq(#lines, 1); eq(lines[1].text, "1 vendor loop · 1 AH → vendor flip"); eq(lines[1].detail, "Test Gloves")
end)

it("Loops: Settings switch the flips off, and a higher smallest profit hides them", function()
	local ns, stub = Load()
	Seed(ns, CLOTH, { tiers = { 40, 5 }, total = 5 }) -- +300
	ns.db.settings.flipAlert = false
	ns.Notify("PRICES_CHANGED"); stub.RunTimers()
	eq(#ns.LootToast.Lines(), 0); eq(#ns.Basket.Flips(), 0)
	ns.db.settings.flipAlert = true
	ns.db.settings.flipAlertMin = 301
	Scan(ns, stub)
	eq(#ns.Basket.Flips(), 0); eq(#ns.LootToast.Lines(), 0)
	ns.db.settings.flipAlertMin = 300
	Scan(ns, stub)
	eq(#ns.Basket.Flips(), 1)
	eq(ns.Loops.FlipMin(), 300)
end)

it("Loops: unknown or 0 vendor price, no prices known: never a flip", function()
	local ns, stub = Load()
	Seed(ns, JUNKY, { tiers = { 5, 1 }, total = 1 })
	Seed(ns, FREE, { tiers = { 5, 1 }, total = 1 })
	ns.Notify("PRICES_CHANGED"); stub.RunTimers()
	eq(#ns.Basket.Flips(), 0); eq(#ns.LootToast.Lines(), 0)
end)

----------------------------------------------------------------------------------------------- basket

it("Basket: a dismissed flip stays away until it gets clearly better or goes away and comes back", function()
	local ns, stub = Load()
	Seed(ns, CLOTH, { tiers = { 40, 5 }, total = 5 }) -- 300
	Scan(ns, stub)
	ns.Basket.DismissFlip(CLOTH)
	eq(#ns.Basket.Flips(), 0); eq(ns.db.flipDismissed[CLOTH], 300)
	Seed(ns, CLOTH, { tiers = { 40, 6 }, total = 6, t = stub.clock + 1 }) -- 360: not 1.5 x
	Scan(ns, stub)
	eq(#ns.Basket.Flips(), 0, "still dismissed")
	Seed(ns, CLOTH, { tiers = { 40, 8 }, total = 8, t = stub.clock + 1 }) -- 480 >= 450
	Scan(ns, stub)
	eq(#ns.Basket.Flips(), 1); eq(ns.db.flipDismissed[CLOTH], nil)
	ns.Basket.DismissFlip(CLOTH)
	Seed(ns, CLOTH, { tiers = { 500, 1 }, total = 1, t = stub.clock + 1 }) -- gone
	Scan(ns, stub)
	eq(ns.db.flipDismissed[CLOTH], nil, "forgotten when it is no flip any more")
	Seed(ns, CLOTH, { tiers = { 40, 5 }, total = 5, t = stub.clock + 1 })
	Scan(ns, stub)
	eq(#ns.Basket.Flips(), 1, "and back as new")
end)

it("Basket: the Auctionator list gets a max price per unit and the units; without Auctionator a search string to copy", function()
	local ns, stub = Load()
	Seed(ns, CLOTH, { tiers = { 40, 5, 90, 10 }, total = 15 })
	Scan(ns, stub)
	local line = ns.Basket.Flips()[1]
	eq(ns.Basket.HasAuctionator(), false)
	eq(ns.Basket.RefreshFlipList(), nil, "no Auctionator: nothing to do")
	eq(ns.Basket.FlipSearchString(line), '"Linen Cloth";;;;;;;;;0.0099;;;;15', "Auctionator's fields: max price in gold, quantity last")
	local made, terms = {}, {}
	Auctionator = { API = { v1 = {
		ConvertToSearchString = function(_, term)
			terms[#terms + 1] = term
			return term.searchString .. "|" .. tostring(term.maxPrice) .. "|" .. term.quantity
		end,
		CreateShoppingList = function(caller, name, list) made[#made + 1] = { caller, name, list } end } } }
	eq(ns.Basket.RefreshFlipList(), 1)
	eq(made[1][1], "CraftWise"); eq(made[1][2], "CraftWise vendor flips"); eq(made[1][3][1], "Linen Cloth|99|15")
	eq(terms[1].isExact, true)
	-- the next scan rebuilds it; a dismissed line leaves it; an empty section empties the list once it exists
	Scan(ns, stub)
	eq(#made, 2)
	ns.Basket.DismissFlip(CLOTH)
	eq(#made[#made][3], 0, "the list follows the section")
end)

it("Basket: no list is made while there are no flips; the bags tick a line off", function()
	local ns, stub = Load({ auctionator = true })
	local made = 0
	Auctionator.API.v1.ConvertToSearchString = function() return "x" end
	Auctionator.API.v1.CreateShoppingList = function() made = made + 1 end
	Seed(ns, CLOTH, { tiers = { 500, 1 }, total = 1 })
	Scan(ns, stub)
	eq(made, 0)
	Seed(ns, CLOTH, { tiers = { 40, 5 }, total = 5, t = stub.clock + 1 })
	Scan(ns, stub)
	eq(made, 1)
	local line = ns.Basket.Flips()[1]
	eq(ns.Basket.FlipHeld(line), 0)
	stub.bags[0] = { { itemID = CLOTH, stackCount = 5, quality = 1 } }
	stub.Fire("BAG_UPDATE_DELAYED")
	eq(ns.Basket.FlipHeld(line), 5)
end)

it("Basket page: the AH → vendor section with units, max price and profit; bought lines dim", function()
	local ns, stub, M = Load()
	Seed(ns, CLOTH, { tiers = { 40, 5 }, total = 5 })
	Seed(ns, SILK, { tiers = { 100, 1, 200, 1, 300, 1, 400, 1, 500, 1, 600, 1, 700, 1, 800, 1 }, total = 20 })
	Scan(ns, stub)
	M.Open("basket")
	local rows = Make.Rows(ns, "basket")
	eq(#rows, 2); eq(rows[1].kind, "flip"); eq(rows[1].itemID, SILK, "best profit first")
	local plain = function(s) return (tostring(s):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
	eq(plain(rows[1].view.cells.qty), "8 or more", "all eight tiers below: written out")
	eq(plain(rows[1].view.cells.where), "AH → vendor")
	eq(plain(rows[2].view.cells.qty), "×5")
	eq(M.Frame().hero.name.text, "2 AH → vendor flips")
	stub.bags[0] = { { itemID = CLOTH, stackCount = 5, quality = 1 } }
	stub.Fire("BAG_UPDATE_DELAYED")
	rows = Make.Rows(ns, "basket")
	local cloth
	for _, r in ipairs(rows) do
		if r.itemID == CLOTH then cloth = r end
	end
	eq(plain(cloth.view.cells.where), "in bags")
end)

----------------------------------------------------------------------------------------------- #314

local function Bags(stub, n)
	stub.bags[0] = n > 0 and { { itemID = CLOTH, stackCount = n, quality = 1 } } or {}
	stub.Fire("BAG_UPDATE_DELAYED")
end

local function FlipScan(ns, stub)
	Seed(ns, CLOTH, { tiers = { 40, 5 }, total = 5, t = stub.clock + 1 })
	Scan(ns, stub)
end

it("Junk (#314): units that arrive in the bags while the item is a flip get the junk mark", function()
	local ns, stub = Load()
	FlipScan(ns, stub)
	eq(ns.db.flipRecent[CLOTH].held0, 0)
	eq(ns.db.junk[CLOTH], nil)
	Bags(stub, 5)
	eq(ns.db.junk[CLOTH], true); eq(ns.db.flipMarked[CLOTH], true); eq(ns.db.flipRecent[CLOTH], nil)
end)

it("Junk (#314): a purchase that comes by mail: the flip left the list, the arrival still counts for a day", function()
	local ns, stub = Load()
	FlipScan(ns, stub)
	Seed(ns, CLOTH, { tiers = { 500, 1 }, total = 1, t = stub.clock + 1 }) -- bought out: no flip any more
	Scan(ns, stub)
	eq(#ns.Basket.Flips(), 0)
	stub.clock = stub.clock + 3600 -- the mail is taken an hour later
	Bags(stub, 5)
	eq(ns.db.junk[CLOTH], true)
	-- ...but not weeks later
	local ns2, stub2 = Load()
	FlipScan(ns2, stub2)
	Seed(ns2, CLOTH, { tiers = { 500, 1 }, total = 1, t = stub2.clock + 1 })
	Scan(ns2, stub2)
	stub2.clock = stub2.clock + 2 * 86400
	Seed(ns2, JUNKY, { tiers = { 500, 1 }, total = 1, t = stub2.clock })
	Scan(ns2, stub2) -- the check prunes it
	Bags(stub2, 5)
	eq(ns2.db.junk[CLOTH], nil)
end)

it("Junk (#314): never an item that was in the bags already, one marked otherwise, or a watched one", function()
	local ns, stub = Load()
	stub.bags[0] = { { itemID = CLOTH, stackCount = 3, quality = 1 } }
	FlipScan(ns, stub)
	eq(ns.db.flipRecent[CLOTH].held0, 3)
	Bags(stub, 8)
	eq(ns.db.junk[CLOTH], nil, "it was in the bags before: kept as it is")
	for _, state in ipairs({ "keep", "auction" }) do
		local n, s = Load()
		FlipScan(n, s)
		n.SetItemState(CLOTH, state)
		Bags(s, 5)
		eq(n.db.junk[CLOTH], nil, state); eq(n.db.flipMarked[CLOTH], nil)
	end
	local n, s = Load()
	n.ItemWatch.Set(CLOTH, true)
	FlipScan(n, s)
	Bags(s, 5)
	eq(n.db.junk[CLOTH], nil, "watched")
	eq(next(n.db.flipMarked or {}), nil)
	n, s = Load()
	n.db.settings.flipJunk = false
	FlipScan(n, s)
	Bags(s, 5)
	eq(n.db.junk[CLOTH], nil, "switched off in Settings")
end)

it("Junk (#314): a mark the player takes off stays off", function()
	local ns, stub = Load()
	FlipScan(ns, stub)
	Bags(stub, 5)
	eq(ns.db.junk[CLOTH], true)
	ns.SetItemState(CLOTH, "normal") -- middle click
	Bags(stub, 0)
	FlipScan(ns, stub) -- a flip again, nothing in the bags
	Bags(stub, 5)
	eq(ns.db.junk[CLOTH], nil, "no re-mark")
	eq(ns.db.flipNoMark[CLOTH], true)
	FlipScan(ns, stub)
	Bags(stub, 9)
	eq(ns.db.junk[CLOTH], nil)
end)

it("Junk (#314): a dismissed flip is not marked when it arrives", function()
	local ns, stub = Load()
	FlipScan(ns, stub)
	ns.Basket.DismissFlip(CLOTH)
	Bags(stub, 5)
	eq(ns.db.junk[CLOTH], nil)
end)

it("Basket page (#314): the count is written out and the line has a tooltip", function()
	local ns, stub, M = Load()
	Seed(ns, SILK, { tiers = { 100, 1, 200, 1, 300, 1, 400, 1, 500, 1, 600, 1, 700, 1, 800, 1 }, total = 20 })
	Seed(ns, CLOTH, { tiers = { 40, 5 }, total = 5 })
	Scan(ns, stub)
	M.Open("basket")
	local rows = Make.Rows(ns, "basket")
	local tip = rows[1].ownTip
	eq(tip[1], "Silk Cloth")
	assert(tip[2]:find("8 or more units are listed below the vendor price", 1, true), tip[2])
	eq(rows[2].ownTip[2], "5 units are listed below the vendor price.")
	eq(ns.LootToast.Lines()[1].detail, "Silk Cloth, 8 or more")
end)
