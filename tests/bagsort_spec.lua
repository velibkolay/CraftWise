local function setup()
	local ns, stub = LoadAddon({ auctionator = true })
	stub.items[100] = { name = "Linen Cloth", sellPrice = 13 }
	stub.items[200] = { name = "Green Sword", sellPrice = 500 }
	stub.items[400] = { name = "Grey Junk", sellPrice = 7 }
	stub.items[500] = { name = "Quest Thing" }
	stub.itemClass[100], stub.itemClass[200], stub.itemClass[500] = 7, 2, 12
	stub.ah[100], stub.ah[200] = 50, 400
	stub.bags[0] = {
		{ itemID = 400, stackCount = 3, quality = 0 },
		false,
		{ itemID = 500, stackCount = 1, quality = 1 },
		{ itemID = 100, stackCount = 20, quality = 1 },
	}
	stub.bags[1] = {
		{ itemID = 200, stackCount = 1, quality = 2 },
		false,
		{ itemID = 100, stackCount = 5, quality = 1 },
	}
	return ns, stub
end

local function layout(stub)
	local out = {}
	for bag = 0, 1 do
		for slot = 1, #stub.bags[bag] do
			local it = stub.bags[bag][slot]
			out[#out + 1] = it and it.itemID or 0
		end
	end
	return table.concat(out, ",")
end

it("plans keep items first, free slots, then items to sell by value", function()
	local ns = setup()
	ns.ToggleKeep(100) -- linen kept for crafting
	local target = ns.BagSort.Target(ns.BagSort.Slots())
	local ids = {}
	for _, t in ipairs(target) do ids[#ids + 1] = t and t.itemID or 0 end
	-- kept: Linen x2 (20 first), Quest Thing; empties; sell: Green Sword (380) > Grey Junk (21)
	eq(table.concat(ids, ","), "100,100,500,0,0,200,400")
end)

it("sorts the bags with swaps, one per frame while slots are unlocked", function()
	local ns, stub = setup()
	ns.ToggleKeep(100)
	assert(ns.BagSort.Start(), "started")
	for _ = 1, 20 do
		if not ns.BagSort.Running() then break end
		ns.BagSort.frame.scripts.OnUpdate()
	end
	eq(ns.BagSort.Running(), false)
	eq(layout(stub), "100,100,500,0,0,200,400")
	eq(stub.cursor, nil)
	eq(ns.BagSort.Start(), false) -- already in order
end)

it("doesn't start in combat, leaves profession bags alone and stops if a slot stays locked", function()
	local ns, stub = setup()
	stub.Fire("PLAYER_REGEN_DISABLED")
	eq(ns.BagSort.Start(), false)
	stub.Fire("PLAYER_REGEN_ENABLED")
	stub.bagFamily[1] = 8 -- leatherworking bag: not part of the sort
	local slots = ns.BagSort.Slots()
	eq(#slots, 4)
	stub.bagFamily[1] = nil
	stub.bags[0][1].isLocked = true
	assert(ns.BagSort.Start())
	stub.now = stub.now + 5
	ns.BagSort.frame.scripts.OnUpdate()
	eq(ns.BagSort.Running(), false)
end)

it("waits for item data after login before sorting, and sorts the same way every time", function()
	local ns, stub = setup()
	ns.ToggleKeep(100)
	local cached = false
	C_Item.IsItemDataCachedByID = function() return cached end
	local timers = {}
	C_Timer.After = function(_, fn) timers[#timers + 1] = fn end
	assert(ns.BagSort.Start(), "waiting")
	eq(ns.BagSort.Running(), false) -- nothing moved yet
	cached = true
	timers[1]()
	for _ = 1, 20 do
		if not ns.BagSort.Running() then break end
		ns.BagSort.frame.scripts.OnUpdate()
	end
	local first = {}
	for slot = 1, #stub.bags[0] do first[slot] = stub.bags[0][slot] and stub.bags[0][slot].itemID or 0 end
	eq(ns.BagSort.Start(), false) -- second click: already in order
end)
