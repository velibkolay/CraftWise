-- Item mark Junk (#214, #227): a Junk item is valued at its vendor price wherever CraftWise picks between the AH
-- and a vendor (ns.GetSellValue, once), with the AH price still shown; "Sell junk" sells it. The old "Sell to
-- vendor" mark moves to Junk once.
local function setup()
	local ns, stub = LoadAddon({ auctionator = true })
	stub.items[100] = { name = "Linen Cloth", sellPrice = 13 }
	stub.items[200] = { name = "Spider Kabob", sellPrice = 40 }
	stub.items[300] = { name = "No Vendor Thing" } -- vendors don't buy it
	stub.ah[100] = 50
	stub.ah[200] = 900
	stub.ah[300] = 700
	stub.bags[0] = {
		{ itemID = 100, stackCount = 20, quality = 1 },
		{ itemID = 200, stackCount = 5, quality = 1 },
	}
	stub.sold = {}
	C_Container.UseContainerItem = function(bag, slot)
		table.insert(stub.sold, stub.bags[bag][slot].itemID)
		stub.bags[bag][slot] = false
	end
	MerchantFrame = CreateFrame("Frame", "MerchantFrame")
	return ns, stub
end

it("GetSellValue: unmarked picks the better of AH and vendor; Junk is the vendor price, tagged", function()
	local ns = setup()
	local v = ns.GetSellValue(200)
	eq(v.source, "auction")
	assert(v.copper > 40, "the AH wins unmarked")
	ns.SetItemState(200, "junk")
	eq(ns.db.junk[200], true)
	v = ns.GetSellValue(200)
	eq(v.source, "vendor"); eq(v.copper, 40); eq(v.marked, true); eq(v.label, "vendor (junk)")
	ns.SetItemState(200, "normal")
	eq(ns.GetSellValue(200).source, "auction")
end)

it("GetSellValue: Junk without a vendor price has no value, never the AH silently", function()
	local ns = setup()
	assert(ns.GetSellValue(300), "unmarked: the AH value")
	ns.SetItemState(300, "junk")
	eq(ns.GetSellValue(300), nil)
	local o = ns.SaleOptions(300, 2)
	eq(o.chosen, nil); assert(o.auction, "the AH price is still shown")
end)

it("SaleOptions: shows both prices, chosen is the vendor and marked", function()
	local ns = setup()
	ns.SetItemState(200, "junk")
	local o = ns.SaleOptions(200, 3)
	eq(o.chosen, "vendor"); eq(o.marked, true); eq(o.vendor, 120)
	assert(o.auction and o.auction.gross == 2700, "AH price still there")
end)

it("Junk excludes the other marks, quest items can't take it, the menu has no separate vendor mark", function()
	local ns = setup()
	ns.SetItemState(200, "auction")
	ns.SetItemState(200, "junk")
	eq(ns.db.junk[200], true); eq(ns.db.sellAH[200], nil)
	ns.ToggleKeep(200)
	eq(ns.db.junk[200], nil); eq(ns.db.keep[200], true)
	local rows = table.concat(ns.ItemMenuRows(false, false), ",")
	assert(rows:find("junk,auction,normal", 1, true), rows)
	assert(not rows:find("vendor", 1, true), "no Sell to vendor entry")
	assert(not table.concat(ns.ItemMenuRows(true, false), ","):find("junk", 1, true), "quest items: no junk mark")
	ns.SetItemState(200, "normal")
	ns.ShowItemMenu(200)
	local menu = CraftWiseItemMenu
	eq(menu.buttons.vendor, nil)
	menu.buttons.junk.scripts.OnClick(menu.buttons.junk)
	eq(ns.db.junk[200], true)
	ns.ShowItemMenu(200)
	eq(menu.buttons.junk.current, true)
end)

it("the old Sell to vendor marks move to Junk once when the data loads; Keep wins; the table goes", function()
	local ns = LoadAddon({ savedDB = { sellVendor = { [200] = true, [300] = true }, keep = { [300] = true }, junk = { [100] = true } } })
	eq(ns.db.junk[200], true); eq(ns.db.junk[100], true); eq(ns.db.junk[300], nil, "a kept item stays kept")
	eq(ns.db.sellVendor, nil)
end)

it("Profit: a craft's sale and profit use the vendor price when the output is Junk, tagged vendor (junk)", function()
	local ns = setup()
	ns.db.vendor[2318] = 5
	local recipe = { reagents = { { itemID = 2318, quantity = 2 } }, output = { itemID = 200, quantity = 1 } }
	local ah = ns.Profit.Evaluate(recipe, ns.ReagentPrices("profit"))
	eq(ah.sellSource, "auction"); eq(ah.sellMarked, nil)
	ns.SetItemState(200, "junk")
	local v = ns.Profit.Evaluate(recipe, ns.ReagentPrices("profit"))
	eq(v.sellSource, "vendor"); eq(v.sellMarked, true); eq(v.sellsFor, 40)
	assert(v.profit < ah.profit, "the vendor price is the lower value here")
	eq(ns.Main.Make.SaleTag("vendor", nil, true), "vendor (junk)")
	eq(ns.Main.Make.SaleTag("vendor"), "vendor")
	ns.SetItemState(300, "junk")
	local none = ns.Profit.Evaluate({ reagents = { { itemID = 2318, quantity = 2 } }, output = { itemID = 300, quantity = 1 } }, ns.ReagentPrices("profit"))
	eq(none.sellsFor, nil); eq(none.profit, nil, "a dash: no vendor price")
end)

it("Craft log profit per hour follows the mark (Make › Crafted)", function()
	local ns, stub = setup()
	stub.profession = { id = 165, name = "Leatherworking", skill = 50, max = 75, recipes = {
		[2149] = { info = { name = "Kabob", learned = true, relativeDifficulty = 1 }, schematic = stub.Schematic({ { 2318, 2 } }, 200) } } }
	stub.Fire("TRADE_SKILL_SHOW")
	ns.db.vendor[2318] = 5
	local now = os.time({ year = 2026, month = 11, day = 15, hour = 12 })
	time = function() return now end
	ns.db.crafted = { seeded = true, before = {}, chars = { [ns.CharKey() or "R-X Y"] = {
		[2149] = { days = { [20261115] = { 6, 6 } }, speed = { n = 5, sum = 10, gaps = { 2, 2, 2, 2, 2 } } } } } }
	ns.Main.Make.state.query = ""
	local function row()
		for _, r in ipairs(ns.Main.CraftedPage.Rows(now, {})) do
			if r.recipeID == 2149 then return r end
		end
	end
	local ah = row()
	assert(ah.profitHour, "profit per hour at AH")
	ns.SetItemState(200, "junk")
	local v = row()
	eq(v.profit, 30); eq(v.profitHour, 1800 * 30)
	assert(v.profitHour < ah.profitHour, "valued at the vendor price")
end)

it("Farm and loot value use the vendor price for a marked item (they call ns.GetSellValue)", function()
	local ns = setup()
	local before = ns.LootValue and ns.LootValue(200, 5) -- not every build has it
	ns.SetItemState(200, "junk")
	eq(ns.GetSellValue(200).copper * 5, 200)
	if before then
		eq(ns.LootValue(200, 5), 200)
	end
end)

it("Sell › Bags: a Junk item is advised at the vendor with the AH value still shown", function()
	local ns = setup()
	ns.SetItemState(200, "junk")
	local row
	for _, r in ipairs(ns.BagRows()) do if r.itemID == 200 then row = r end end
	eq(row.junk, true); eq(row.best, "junk"); eq(row.bestValue, row.vendorValue)
	assert(row.ahValue and row.ahValue > row.vendorValue, "AH value still there")
	local vendor, ahNet, best = ns.ItemAdvice(200, 5)
	eq(best, "vendor"); assert(ahNet, "the tooltip still has the AH number")
	ns.SetItemState(300, "junk")
	local _, _, best300 = ns.ItemAdvice(300, 1)
	eq(best300, nil, "no vendor price: no advice, not the AH")
end)

it("Sell junk sells Junk items, Keep wins; the tooltip says they are valued at the vendor price", function()
	local ns, stub = setup()
	ns.SetItemState(200, "junk")
	stub.Fire("MERCHANT_SHOW")
	eq(ns.Junk.button.count, 1)
	assert(ns.Junk.Sell())
	for _ = 1, 5 do
		if not ns.Junk.Running() then break end
		ns.Junk.button.scripts.OnUpdate(ns.Junk.button, 0.3)
	end
	eq(table.concat(stub.sold, ","), "200")
	stub.bags[0][2] = { itemID = 200, stackCount = 1, quality = 1 }
	ns.db.keep[200] = true -- a Keep set directly still wins
	stub.Fire("BAG_UPDATE_DELAYED")
	eq(#ns.Junk.Slots(), 0)
	local shown
	ns.Style.ShowTip = function(_, _, ...) shown = table.concat({ ... }, "\n") end
	ns.Junk.button.scripts.OnEnter(ns.Junk.button)
	assert(shown and shown:find("vendor price", 1, true), shown)
end)
