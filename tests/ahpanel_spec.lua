-- The CraftWise panel next to the auction house (#328): what a line costs, what a vendor pays, the profit,
-- the totals on top with the scan age, the groups in order. Display only: nothing here searches or buys.
local NOW = 1794000000
local HORDE = "H"
local CLOTH, SILK, SWORD, GEM = 100, 200, 300, 400

local function Setup()
	local ns, stub = LoadAddon()
	stub.clock = NOW
	time = function() return stub.clock end
	stub.items[CLOTH] = { name = "Linen Cloth", sellPrice = 100 }
	stub.items[SILK] = { name = "Silk Cloth", sellPrice = 1000 }
	stub.items[SWORD] = { name = "Test Sword", sellPrice = 0 }
	stub.items[GEM] = { name = "Test Gem", sellPrice = 0 }
	AuctionHouseFrame = CreateFrame("Frame", "AuctionHouseFrame")
	stub.Fire("AUCTION_HOUSE_SHOW")
	return ns, stub
end

local function Seed(ns, itemID, tiers, total)
	local db = CraftWiseMarketDB
	local entry = { raw = { { t = NOW, total = total, listings = 1, tiers = tiers } }, days = {},
		last = { t = NOW, min = tiers[1], qty = total, listings = 1 } }
	db.items[itemID] = db.items[itemID] or {}
	db.items[itemID][HORDE] = entry
	db.houses[HORDE] = db.houses[HORDE] or { realm = "PvP", kind = "faction", faction = "Horde", label = "Horde AH" }
end

----------------------------------------------------------------------------------------------- maths

it("TierCost: the cheapest units first; fewer units in the tiers than asked says how many it covered", function()
	local ns = LoadAddon()
	local cost, got = ns.Loops.TierCost({ 40, 5, 90, 10 }, 8)
	eq(cost, 5 * 40 + 3 * 90); eq(got, 8)
	cost, got = ns.Loops.TierCost({ 40, 5, 90, 10 }, 20)
	eq(cost, 5 * 40 + 10 * 90); eq(got, 15)
	cost, got = ns.Loops.TierCost({}, 3)
	eq(cost, 0); eq(got, 0)
end)

it("FlipLine: need below the units listed (the bags hold some) costs only the cheapest need units", function()
	local ns = LoadAddon()
	local L = ns.Loops
	-- 15 units listed under 100 (5 at 40, 10 at 90); the bags hold 7, so 8 are still to buy
	local f = L.FlipLine(8, { 40, 5, 90, 10, 150, 4 }, 100, false)
	eq(f.cost, 5 * 40 + 3 * 90); eq(f.vendor, 800); eq(f.profit, 800 - 470)
	eq(f.costMark, nil); eq(f.profitMark, nil)
	f = L.FlipLine(15, { 40, 5, 90, 10 }, 100, false)
	eq(f.cost, 200 + 900); eq(f.vendor, 1500); eq(f.profit, 400)
end)

it("FlipLine: atLeast marks every figure with >=; tiers shorter than need make the cost >= and the profit <=; no tiers, no figure", function()
	local ns = LoadAddon()
	local L = ns.Loops
	local f = L.FlipLine(5, { 40, 5 }, 100, true)
	eq(f.costMark, "≥"); eq(f.profitMark, "≥"); eq(f.vendorMark, "≥"); eq(f.profit, 300)
	f = L.FlipLine(9, { 40, 5 }, 100, false)
	eq(f.cost, 200); eq(f.costMark, "≥"); eq(f.profitMark, "≤"); eq(f.vendor, 900)
	eq(L.FlipLine(5, {}, 100, false), nil); eq(L.FlipLine(5, nil, 100, false), nil)
	eq(L.FlipLine(0, { 40, 5 }, 100, false), nil); eq(L.FlipLine(5, { 40, 5 }, nil, false), nil)
end)

it("FlipTotals: cost, vendor and profit added up; bounds carry; a line without figures leaves the profit unknown", function()
	local ns = LoadAddon()
	local L = ns.Loops
	local a = L.FlipLine(5, { 40, 5 }, 100, false) -- cost 200, vendor 500, profit 300
	local b = L.FlipLine(2, { 90, 2 }, 1000, false) -- cost 180, vendor 2000, profit 1820
	local t = L.FlipTotals({ { need = 5, sell = 100, figures = a }, { need = 2, sell = 1000, figures = b } })
	eq(t.cost, 380); eq(t.vendor, 2500); eq(t.profit, 2120); eq(t.costMark, nil); eq(t.profitMark, nil); eq(t.unknown, 0)
	local c = L.FlipLine(5, { 40, 5 }, 100, true)
	t = L.FlipTotals({ { need = 5, sell = 100, figures = c }, { need = 2, sell = 1000, figures = b } })
	eq(t.profit, 2120); eq(t.costMark, "≥"); eq(t.profitMark, "≥"); eq(t.vendorMark, "≥")
	local d = L.FlipLine(9, { 40, 5 }, 100, false) -- profit is an upper bound
	t = L.FlipTotals({ { need = 9, sell = 100, figures = d }, { need = 2, sell = 1000, figures = b } })
	eq(t.profitMark, "≤")
	t = L.FlipTotals({ { need = 9, sell = 100, figures = d }, { need = 5, sell = 100, figures = c } })
	eq(t.profit, nil, "a lower bound and an upper bound together say nothing")
	t = L.FlipTotals({ { need = 5, sell = 100, figures = a }, { need = 3, sell = 100, figures = nil } })
	eq(t.profit, nil); eq(t.unknown, 1); eq(t.cost, 200); eq(t.costMark, "≥"); eq(t.vendor, 800, "the vendor price is known without tiers")
end)

it("BasketLine: the quantity at the market price, marked as one price for all; without a price no figure", function()
	local ns = LoadAddon()
	local b = ns.Loops.BasketLine(3, 700)
	eq(b.cost, 2100); eq(b.mark, "~")
	eq(ns.Loops.BasketLine(3, nil), nil); eq(ns.Loops.BasketLine(3, 0), nil); eq(ns.Loops.BasketLine(0, 700), nil)
end)

----------------------------------------------------------------------------------------------- the panel

it("Panel model: a flip line with bags holding some is priced for the units still missing, the totals add the flip lines, the scan age shows", function()
	local ns, stub = Setup()
	Seed(ns, CLOTH, { 40, 5, 90, 10 }, 15)
	Seed(ns, SILK, { 500, 2 }, 2)
	stub.bags[0] = { { itemID = CLOTH, stackCount = 7, quality = 1 } }
	ns.db.flips = { t = NOW - 720, items = {
		{ itemID = CLOTH, units = 15, atLeast = false, profit = 400, price = 40, sell = 100, maxUnit = 99, t = NOW },
		{ itemID = SILK, units = 2, atLeast = false, profit = 1000, price = 500, sell = 1000, maxUnit = 999, t = NOW },
	} }
	local list = ns.AHBuy.Lines({ split = { auction = {} } })
	eq(#list, 2); eq(list[1].need, 8)
	local m = ns.AHPanel.Model(list)
	local cloth = m.groups.flip[1]
	eq(cloth.figures.cost, 5 * 40 + 3 * 90, "the cheapest 8 of 15 units")
	eq(cloth.figures.vendor, 800); eq(cloth.figures.profit, 330)
	eq(m.totals.cost, 470 + 1000); eq(m.totals.vendor, 800 + 2000); eq(m.totals.profit, 330 + 1000)
	eq(m.scanT, NOW - 720)
	local sum, age = ns.AHPanel.SummaryText(m.totals, m.scanT, NOW)
	assert(sum:find("Flips: cost", 1, true) and sum:find(ns.FormatMoney(1470, true), 1, true), sum)
	assert(age:find("12m", 1, true), age)
	eq(ns.AHPanel.RowName(cloth), "Linen Cloth ×8")
	local detail = ns.AHPanel.RowDetail(cloth)
	assert(detail:find("cost " .. ns.FormatMoney(470, true), 1, true) and detail:find("vendor " .. ns.FormatMoney(800, true), 1, true)
		and detail:find("profit +" .. ns.FormatMoney(330, true), 1, true), detail)
	-- #402: the row shows one figure, the profit; the cost, vendor price and buys are in the tooltip
	eq(ns.AHPanel.RowRight(cloth), "+" .. ns.FormatMoney(330, true))
	local tip = ns.AHPanel.RowTipLines(cloth)
	eq(tip[1], detail)
	eq(tip[2], ns.AHPanel.RowEach(cloth), "the price step and the buys are kept in the tooltip")
end)

it("Panel (#402): at most 8 rows of a group are drawn, the rest is counted", function()
	local ns = Setup()
	local items = {}
	for i = 1, 11 do
		Seed(ns, 5000 + i, { 40, 5 }, 5)
		items[i] = { itemID = 5000 + i, units = 5, atLeast = false, profit = 300, price = 40, sell = 100, maxUnit = 99, t = NOW }
	end
	ns.db.flips = { t = NOW, items = items }
	ns.Notify("PRICES_CHANGED")
	local P = ns.AHPanel
	assert(P.panel.flipMore:IsShown(), "a +N more line")
	assert(P.panel.flipMore:GetText():find("+3 more", 1, true), P.panel.flipMore:GetText())
end)

it("Panel model: a flip that lists N or more shows >= on the name and every figure and the totals", function()
	local ns = Setup()
	Seed(ns, CLOTH, { 40, 5 }, 9)
	ns.db.flips = { t = NOW, items = { { itemID = CLOTH, units = 5, atLeast = true, profit = 300, price = 40, sell = 100, maxUnit = 99, t = NOW } } }
	local m = ns.AHPanel.Model(ns.AHBuy.Lines({ split = { auction = {} } }))
	local row = m.groups.flip[1]
	eq(ns.AHPanel.RowName(row), "Linen Cloth ×≥5")
	local detail = ns.AHPanel.RowDetail(row)
	assert(detail:find("cost ≥ ", 1, true) and detail:find("vendor ≥ ", 1, true) and detail:find("profit ≥ +", 1, true), detail)
	eq(m.totals.profitMark, "≥"); eq(m.totals.costMark, "≥")
	local sum = ns.AHPanel.SummaryText(m.totals, m.scanT, NOW)
	assert(sum:find("cost ≥ ", 1, true) and sum:find("profit ≥ +", 1, true), sum)
end)

it("Panel model: a flip without stored tiers shows no cost and no profit, only what a vendor pays; nothing is invented", function()
	local ns = Setup()
	ns.db.flips = { t = NOW, items = { { itemID = CLOTH, units = 5, atLeast = false, profit = 300, price = 40, sell = 100, maxUnit = 99, t = NOW } } }
	local m = ns.AHPanel.Model(ns.AHBuy.Lines({ split = { auction = {} } }))
	local row = m.groups.flip[1]
	eq(row.figures, nil)
	local detail = ns.AHPanel.RowDetail(row)
	assert(not detail:find("profit", 1, true) and detail:find("vendor " .. ns.FormatMoney(500, true), 1, true), detail)
	eq(m.totals.profit, nil)
	local sum = ns.AHPanel.SummaryText(m.totals, m.scanT, NOW)
	assert(sum:find("profit ?", 1, true), sum)
end)

it("Panel model: a basket line without a market price shows no figure; with one it shows the cost marked as one price", function()
	local ns = Setup()
	local list = { { kind = "basket", itemID = SWORD, need = 3 } }
	local row = ns.AHPanel.Model(list).groups.basket[1]
	eq(row.figures, nil); eq(ns.AHPanel.RowDetail(row), "no market price")
	ns.AuctionQuote = function(id) return id == SWORD and { copper = 700 } or nil end
	row = ns.AHPanel.Model(list).groups.basket[1]
	eq(row.figures.cost, 2100)
	assert(ns.AHPanel.RowDetail(row):find("about " .. ns.FormatMoney(2100, true), 1, true), ns.AHPanel.RowDetail(row))
	eq(ns.AHPanel.Model(list).totals, nil, "the totals are the flips'")
end)

it("Panel model: snipes first, then flips, then the basket; a snipe line shows its max and its limit", function()
	local ns = Setup()
	Seed(ns, CLOTH, { 40, 5 }, 5)
	ns.db.flips = { t = NOW, items = { { itemID = CLOTH, units = 5, atLeast = false, profit = 300, price = 40, sell = 100, maxUnit = 99, t = NOW } } }
	ns.Snipe.Set(GEM, 700, 4)
	local list = ns.AHBuy.Lines({ split = { auction = { { itemID = SWORD, quantity = 3 } } } })
	local m = ns.AHPanel.Model(list)
	eq(#m.groups.snipe, 1); eq(#m.groups.flip, 1); eq(#m.groups.basket, 1)
	eq(table.concat(ns.AHPanel.GROUPS, ","), "snipe,flip,basket")
	eq(ns.AHPanel.GroupHeading("flip", 1), "Flips (1)")
	local detail = ns.AHPanel.RowDetail(m.groups.snipe[1])
	assert(detail:find("max " .. ns.FormatMoney(700, true), 1, true) and detail:find("up to 4", 1, true), detail)
	ns.Notify("SNIPE_CHANGED")
	assert(CraftWiseAHPanel.summary:IsShown(), "the summary is shown with flips")
end)

it("Listed now: a result row shows units x price = the row total", function()
	local ns = Setup()
	local text = ns.AHPanel.ResultText({ qty = 12, unit = 340 }, true)
	assert(text:find("12 × " .. ns.FormatMoney(340, true) .. " = " .. ns.FormatMoney(4080, true), 1, true), text)
end)

----------------------------------------------------------------------------------------------- names and status

it("Names: an item the client hasn't cached never shows its ID; it is requested once and the row redraws when the name arrives", function()
	local ns, stub = Setup()
	local ID = 5964
	ns.Snipe.Set(ID, 700, 4)
	ns.Notify("SNIPE_CHANGED")
	local panel = CraftWiseAHPanel
	local function Texts()
		local out = {}
		for _, fr in ipairs(stub.frames) do
			if fr.line and fr.text and fr.text.text then out[#out + 1] = fr.text.text end
		end
		return out
	end
	local before = Texts()
	eq(#before, 1)
	assert(not before[1]:find("5964", 1, true) and not before[1]:find("item ", 1, true), before[1])
	assert(before[1]:find(ns.AHPanel.PLACEHOLDER, 1, true), before[1])
	local asked = 0
	for _, id in ipairs(stub.loadRequests) do if id == ID then asked = asked + 1 end end
	assert(asked >= 1, "the name was requested")
	ns.Notify("SNIPE_CHANGED")
	local again = 0
	for _, id in ipairs(stub.loadRequests) do if id == ID then again = again + 1 end end
	eq(again, asked, "drawing again doesn't ask again (the shared throttle)")
	-- the name arrives
	stub.items[ID] = { name = "Barbaric Shoulders", sellPrice = 0 }
	stub.Fire("ITEM_DATA_LOAD_RESULT", ID, true)
	local after = Texts()
	assert(after[1]:find("Barbaric Shoulders", 1, true), after[1])
end)

it("Status line: no line picked says so; a searched item with nothing listed says why; a message wins", function()
	local ns = Setup()
	local P = ns.AHPanel
	eq(P.StatusText({ target = nil }, nil, "Pick a line"), "Click a line to search it first")
	eq(P.StatusText({ target = { itemID = 1 } }, nil, "Nothing is listed"), "Nothing is listed")
	eq(P.StatusText({ target = { itemID = 1 } }, nil, "Searching..."), "Searching...")
	eq(P.StatusText({ target = { itemID = 1 }, message = "Wait: the auction house is busy" }, nil, "x"), "Wait: the auction house is busy")
	eq(P.StatusText({ target = { itemID = 1 } }, { profit = 330 }, nil), "Profit " .. ns.FormatMoney(330, true))
end)

it("Buy button: its text is what AHBuy.Describe says, and it looks disabled when it is off", function()
	local ns, stub = Setup()
	ns.db.flips = { t = NOW, items = { { itemID = CLOTH, units = 5, atLeast = false, profit = 300, price = 40, sell = 100, maxUnit = 99, t = NOW } } }
	ns.Notify("BASKET_CHANGED")
	local buy = CraftWiseAHPanel.buy
	eq(buy.enabled, false)
	eq(buy.face.alpha, 0.4, "a disabled button fades")
	eq(buy.label.text, "Pick a line", "the label is what Describe returns for no plan")
	eq(CraftWiseAHPanel.status.text, "Click a line to search it first")
end)
