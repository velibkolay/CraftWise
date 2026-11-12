it("no Auctionator: no auction price, no error", function()
	local ns = LoadAddon()
	eq(ns.HasAuctionator(), false)
	eq(ns.GetAuctionPrice(1), nil)
	eq(ns.GetBuyPrice(1), nil)
end)

it("reads Auctionator price and age", function()
	local ns, stub = LoadAddon({ auctionator = true })
	stub.ah[1], stub.ahAge[1] = 250, 2
	local copper, age = ns.GetAuctionPrice(1)
	eq(copper, 250); eq(age, 2)
end)

it("Auctionator errors are swallowed", function()
	local ns = LoadAddon({ auctionator = true })
	Auctionator.API.v1.GetAuctionPriceByItemID = function() error("boom") end
	eq(ns.GetAuctionPrice(1), nil)
end)

it("buy price prefers the cheaper of vendor and AH", function()
	local ns, stub = LoadAddon({ auctionator = true })
	stub.ah[1], stub.ah[2] = 100, 30
	ns.db.vendor[1], ns.db.vendor[2] = 50, 50
	eq(ns.GetBuyPrice(1).source, "vendor"); eq(ns.GetBuyPrice(1).copper, 50)
	eq(ns.GetBuyPrice(2).source, "auction"); eq(ns.GetBuyPrice(2).copper, 30)
end)

it("sell value applies the AH cut and falls back to vendor sell price", function()
	local ns, stub = LoadAddon({ auctionator = true })
	stub.ah[9] = 1000
	stub.items[9] = { name = "Vest", sellPrice = 100 }
	stub.items[8] = { name = "Belt", sellPrice = 70 }
	local v = ns.GetSellValue(9)
	eq(v.source, "auction"); eq(v.copper, 950)
	local w = ns.GetSellValue(8)
	eq(w.source, "vendor"); eq(w.copper, 70)
end)

it("vendor sell beats a worse AH price", function()
	local ns, stub = LoadAddon({ auctionator = true })
	stub.ah[9] = 100
	stub.items[9] = { name = "Vest", sellPrice = 200 }
	eq(ns.GetSellValue(9).source, "vendor")
end)

it("records merchant unit prices, skipping extended-cost items", function()
	local ns, stub = LoadAddon()
	stub.merchant = { { itemID = 2320, price = 10, stack = 1 }, { itemID = 2324, price = 50, stack = 5 },
		{ itemID = 777, price = 0, stack = 1 }, { itemID = 888, price = 100, extended = true } }
	stub.Fire("MERCHANT_SHOW")
	eq(ns.db.vendor[2320], 10); eq(ns.db.vendor[2324], 10); eq(ns.db.vendor[777], nil); eq(ns.db.vendor[888], nil)
end)

it("saved settings survive and defaults fill in", function()
	local ns = LoadAddon({ savedDB = { vendor = { [5] = 3 }, settings = { includeUnlearned = false } } })
	eq(ns.db.vendor[5], 3); eq(ns.db.settings.includeUnlearned, false); eq(ns.db.settings.hideUnpriced, false)
end)

-- #83: the vendor floor survives an item the client hasn't cached this session.
it("vendor sell price: the client's value is kept and used when the item isn't cached", function()
	local ns, stub = LoadAddon()
	ns.ItemSellPrices = { [700] = 5 }
	stub.items[700] = { name = "Thing", sellPrice = 37 }
	eq(ns.GetVendorSellPrice(700), 37)
	eq(ns.db.sellPrices[700], 37)
	stub.items[700] = nil -- next session, not in the client cache yet
	eq(ns.GetVendorSellPrice(700), 37, "persisted price before the bundled table")
	ns.db.sellPrices[700] = nil
	eq(ns.GetVendorSellPrice(700), 5, "bundled table last")
	eq(ns.GetVendorSellPrice(701), nil, "never seen: missing")
end)

it("vendor sell price: zero (vendors don't buy it) is kept as zero", function()
	local ns, stub = LoadAddon()
	stub.items[702] = { name = "Quest thing", sellPrice = 0 }
	eq(ns.GetVendorSellPrice(702), 0)
	stub.items[702] = nil
	eq(ns.GetVendorSellPrice(702), 0)
end)

it("scope items get their sell price stored: cached now, the rest when the client loads them", function()
	local ns, stub = LoadAddon()
	local requested = {}
	C_Item.RequestLoadItemDataByID = function(id) requested[id] = true end
	ns.charDB.professions[165] = { name = "Leatherworking", recipes = {
		[1] = { learned = true, reagents = { { itemID = 710, quantity = 1 } }, output = { itemID = 711, quantity = 1 } },
	} }
	stub.items[710] = { name = "Cached reagent", sellPrice = 12 }
	stub.Fire("PLAYER_LOGIN")
	eq(ns.db.sellPrices[710], 12)
	eq(ns.db.sellPrices[711], nil); eq(requested[711], true)
	stub.items[711] = { name = "Loaded output", sellPrice = 250 }
	stub.Fire("GET_ITEM_INFO_RECEIVED", 711, true)
	eq(ns.db.sellPrices[711], 250)
	stub.items[711] = nil
	eq(ns.GetVendorSellPrice(711), 250)
end)
