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

it("tooltips render for known, trainer, vendor and bundled-only rows", function()
	local ns, stub = LoadAddon({ data = true, auctionator = true })
	stub.profession = { id = 165, name = "Leatherworking", skill = 60, max = 75, recipes = {
		[2149] = { info = { name = "Handstitched Leather Boots", learned = true }, schematic = stub.Schematic({ { 2318, 2 } }, 2302) },
	} }
	stub.Fire("TRADE_SKILL_SHOW")
	UnitFactionGroup = function() return "Horde" end
	ns.ToggleProfitFrame()
	local rendered = 0
	for _, f in ipairs(stub.frames) do
		if f.data and f.scripts.OnEnter then
			f.scripts.OnEnter(f)
			f.scripts.OnLeave(f)
			rendered = rendered + 1
		end
	end
	assert(rendered > 5, "expected visible rows, got " .. rendered)
	-- sort by every column without errors
	for _, f in ipairs(stub.frames) do
		if f.scripts.OnClick and not f.data then f.scripts.OnClick(f) end
	end
	-- scroll
	for _, f in ipairs(stub.frames) do
		if f.scripts.OnMouseWheel then f.scripts.OnMouseWheel(f, -1) end
	end
end)
