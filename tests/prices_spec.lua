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
	eq(ns.db.vendor[5], 3); eq(ns.db.settings.includeUnlearned, false); eq(ns.db.settings.sortKey, "profit")
end)
