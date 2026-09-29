it("window builds and renders rows without errors", function()
	local ns, stub = LoadAddon({ auctionator = true })
	stub.profession = { id = 165, name = "Leatherworking", skill = 100, max = 150, recipes = {
		[2149] = { info = { name = "Boots", learned = true }, schematic = stub.Schematic({ { 2318, 2 } }, 2302) },
		[3760] = { info = { name = "Cloak", learned = false }, schematic = stub.Schematic({ { 2319, 5 } }, 3719) },
		[7000] = { info = { name = "Enchant", learned = true }, schematic = stub.Schematic({ { 1, 1 } }, nil) },
	} }
	stub.Fire("TRADE_SKILL_SHOW")
	stub.ah[2318], stub.ah[2302] = 10, 100
	ns.ToggleProfitFrame()
	local rows = ns.BuildRows(165, true)
	eq(#rows, 3)
	ns.ToggleProfitFrame() -- hide
	ns.ToggleProfitFrame() -- show again
	ns.RefreshProfitFrame()
end)
