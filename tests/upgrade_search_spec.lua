-- Issue #50: General / AH section of the Upgrades view. On-demand AH search per equipment slot.
local NOW = 1794000000

local function setup()
	local ns, stub = LoadAddon()
	time = function() return stub.clock end
	stub.clock = NOW
	stub.items[1001] = { name = "Old Cloak", level = 10, equipLoc = "INVTYPE_CLOAK", stats = { RESISTANCE0_NAME = 10 } }
	stub.items[1002] = { name = "Old Helm", level = 10, equipLoc = "INVTYPE_HEAD", stats = { RESISTANCE0_NAME = 40 } }
	stub.items[6001] = { name = "AH Cloak", level = 1, equipLoc = "INVTYPE_CLOAK", stats = { RESISTANCE0_NAME = 12, ITEM_MOD_AGILITY_SHORT = 3 } }
	stub.items[6002] = { name = "Weak Helm", level = 1, equipLoc = "INVTYPE_HEAD", stats = { RESISTANCE0_NAME = 50 } }
	stub.items[6003] = { name = "Plate Helm", level = 1, equipLoc = "INVTYPE_HEAD", stats = { RESISTANCE0_NAME = 90 } }
	stub.items[6004] = { name = "Ring of the Monkey", level = 1, equipLoc = "INVTYPE_FINGER" }
	stub.equipped.BACKSLOT, stub.equipped.HEADSLOT = 1001, 1002
	stub.noProficiency[6003] = true
	return ns, stub
end

local function OpenAH(stub)
	stub.zone = "Orgrimmar"
	stub.Fire("AUCTION_HOUSE_SHOW")
end

local function Row(itemID, level, minPrice, qty, suffix)
	return { itemKey = { itemID = itemID, itemLevel = level, itemSuffix = suffix or 0, battlePetSpeciesID = 0 },
		totalQuantity = qty, minPrice = minPrice, containsOwnerItem = false }
end

-- Answers every outstanding query with the results for its first filter's inventory type.
local function Answer(stub, byType)
	local answered = 0
	while #stub.browseQueries > answered do
		answered = answered + 1
		local q = stub.browseQueries[answered]
		stub.browse = byType[q.itemClassFilters[1].inventoryType] or {}
		stub.Fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
	end
	return answered
end

local function byItem(rows)
	local t = {}
	for _, row in ipairs(rows) do t[row.itemID] = row end
	return t
end

it("the search needs the auction house open", function()
	local ns, stub = setup()
	local ok, why = ns.UpgradeSearch.Start()
	eq(ok, false); eq(why, "closed"); eq(#stub.browseQueries, 0)
end)

it("one browse search per slot for gear you can wear now, highest level first", function()
	local ns, stub = setup()
	OpenAH(stub)
	eq(ns.UpgradeSearch.Start(), true)
	eq(#stub.browseQueries, 1) -- one at a time, the next after the answer
	local q = stub.browseQueries[1]
	eq(q.maxLevel, 20); eq(q.minLevel, nil); eq(q.searchString, "")
	eq(q.itemClassFilters[1].classID, 4); eq(q.itemClassFilters[1].inventoryType, 1)
	eq(q.sorts[1].sortOrder, 2); eq(q.sorts[1].reverseSort, true); eq(q.sorts[2].sortOrder, 0)
	eq(ns.UpgradeSearch.Running(), true)
	local n = Answer(stub, {})
	eq(n, 15); eq(ns.UpgradeSearch.Running(), false)
	local chest, weapons
	for _, query in ipairs(stub.browseQueries) do
		if query.itemClassFilters[1].inventoryType == 5 then chest = query end
		if query.itemClassFilters[1].inventoryType == 13 then weapons = query end
	end
	eq(#chest.itemClassFilters, 2); eq(chest.itemClassFilters[2].inventoryType, 20) -- robes too
	eq(weapons.itemClassFilters[1].classID, 2); eq(#weapons.itemClassFilters, 4)
	local last = ns.UpgradeSearch.LastRun()
	eq(last.complete, true); eq(last.searched, 15); eq(last.slots, 15); eq(last.houseLabel, "Horde AH")
end)

it("waits for the AH throttle before each search", function()
	local ns, stub = setup()
	OpenAH(stub)
	stub.throttleReady = false
	ns.UpgradeSearch.Start()
	eq(#stub.browseQueries, 0)
	stub.throttleReady = true
	stub.Fire("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
	eq(#stub.browseQueries, 1)
	stub.throttleReady = false
	stub.browse = {}
	stub.Fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
	eq(#stub.browseQueries, 1)
	stub.throttleReady = true
	stub.Fire("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
	eq(#stub.browseQueries, 2)
end)

it("asks for more result pages up to a limit, reading added results", function()
	local ns, stub = setup()
	OpenAH(stub)
	ns.UpgradeSearch.Start()
	stub.browseFull = false
	stub.browse = {}
	stub.Fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
	eq(stub.moreRequests, 1); eq(#stub.browseQueries, 1)
	stub.Fire("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", { Row(6002, 30, 500, 1) })
	stub.Fire("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", {})
	stub.Fire("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", {})
	eq(stub.moreRequests, 3); eq(#stub.browseQueries, 2) -- 3 more pages, then the next slot
	stub.browseFull = true
	Answer(stub, {})
	eq(ns.charDB.ahGear.items[6002].level, 30); eq(ns.charDB.ahGear.items[6002].slot, "Head")
end)

it("rows: upgrades by the #16 rule, lowest buyout at the profit house with depth and age", function()
	local ns, stub = setup()
	OpenAH(stub)
	ns.UpgradeSearch.Start()
	Answer(stub, {
		[1] = { Row(6002, 9, 400, 2), Row(6003, 20, 900, 1) }, -- lower ilvl; plate the class can't wear
		[16] = { Row(6001, 12, 2500, 4) },
		[11] = { Row(6004, 14, 700, 1, 77) },
	})
	stub.clock = NOW + 7200
	local rows = byItem(ns.UpgradeSearch.Rows())
	eq(rows[6002], nil); eq(rows[6003], nil)
	local cloak = rows[6001]
	eq(cloak.section, "ah"); eq(cloak.level, 12); eq(cloak.ilvlGain, 2); eq(cloak.slotLabel, "Back")
	eq(cloak.cost, 2500); eq(cloak.costComplete, true); eq(cloak.qty, 4); eq(cloak.priceAge, 7200)
	eq(cloak.mainStats, "+3 AGI"); eq(cloak.houseLabel, "Horde AH")
	local ring = rows[6004]
	eq(ring.emptySlot, true); eq(ring.suffix, 77); eq(ring.mainStats, nil); eq(ring.itemKey, "6004:77")
end)

it("prices outside the market scope are stored as last only", function()
	local ns, stub = setup()
	CraftWiseMarketDB.scope.items[6002] = true
	OpenAH(stub)
	ns.UpgradeSearch.Start()
	Answer(stub, { [1] = { Row(6002, 30, 400, 2) }, [16] = { Row(6001, 12, 2500, 4) } })
	local entry = CraftWiseMarketDB.items[6001]["PvP|H"]
	eq(entry.last.min, 2500); eq(entry.last.qty, 4); eq(#entry.raw, 0); eq(next(entry.days), nil)
	eq(CraftWiseMarketDB.items[6002]["PvP|H"].last.min, 400) -- in scope: Market's own browse recorder
	-- Market's browse recorder stores every row since #90, the gear recorder whatever it missed.
	local inScope, lastOnly = 0, 0
	for _, scan in ipairs(CraftWiseMarketDB.scans["PvP|H"]) do
		if scan.kind == "gear" then lastOnly = lastOnly + scan.items else
			inScope, lastOnly = inScope + scan.items, lastOnly + (scan.lastOnly or 0) end
	end
	eq(inScope, 1); eq(lastOnly, 1)
	ns.Market.Prune()
	eq(CraftWiseMarketDB.items[6001]["PvP|H"] ~= nil, true)
end)

it("a price seen at another house shows as not seen at the profit house", function()
	local ns, stub = setup()
	stub.zone = "Booty Bay"
	stub.Fire("AUCTION_HOUSE_SHOW")
	ns.UpgradeSearch.Start()
	Answer(stub, { [16] = { Row(6001, 12, 2500, 4) } })
	local cloak = byItem(ns.UpgradeSearch.Rows())[6001]
	eq(cloak.cost, nil); eq(cloak.costComplete, false); eq(cloak.notAtHouse, true)
	eq(ns.UpgradeSearch.LastRun().houseLabel, "Booty Bay")
end)

it("closing the AH stops the search and keeps what was found", function()
	local ns, stub = setup()
	OpenAH(stub)
	ns.UpgradeSearch.Start()
	stub.browse = { Row(6002, 30, 400, 2) }
	stub.Fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
	stub.Fire("AUCTION_HOUSE_CLOSED")
	eq(ns.UpgradeSearch.Running(), false)
	local last = ns.UpgradeSearch.LastRun()
	eq(last.complete, false); eq(last.searched, 1)
	eq(ns.charDB.ahGear.items[6002] ~= nil, true)
	local before = #stub.browseQueries
	stub.Fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
	eq(#stub.browseQueries, before)
	eq(ns.UpgradeSearch.Start(), false)
end)

it("a search without an answer or a failed one is skipped and reported", function()
	local ns, stub = setup()
	OpenAH(stub)
	ns.UpgradeSearch.Start()
	stub.RunTimers() -- the head search times out
	eq(#stub.browseQueries, 2)
	stub.Fire("AUCTION_HOUSE_BROWSE_FAILURE")
	eq(#stub.browseQueries, 3)
	stub.timers = {}
	Answer(stub, {})
	local failed = ns.UpgradeSearch.LastRun().failed
	eq(#failed, 2); eq(failed[1], "Head"); eq(failed[2], "Neck")
end)

it("Look up › Upgrades: the AH group, Search AH for these (disabled while the AH is closed), rows, dismiss", function()
	local ns, stub = setup()
	local M = ns.Main
	M.Open("upgrades")
	local function frames()
		local out = { items = {} }
		for _, fr in ipairs(M.ListOf("upgrades").box.frames) do
			local r = fr.element and fr.element.row
			if r and r.search then out.search = fr
			elseif r and r.header and r.group == "ah" then out.header = r
			elseif r and r.emptyLine and r.group == "ah" then out.empty = r
			elseif r and r.itemID then out.items[#out.items + 1] = r end
		end
		return out
	end
	local f = frames()
	eq(f.header.title, "From the auction house"); eq(f.header.note, "no search yet")
	eq(f.header.right, "open the auction house to search")
	assert(f.empty.emptyLine:find("Open the auction house and search", 1, true), f.empty.emptyLine)
	local chip = f.search.cwUp.chip
	eq(chip.label.text, "Search AH for these"); eq(chip.disabled, true)
	eq(chip.cwTip, "open the auction house to search")
	OpenAH(stub)
	f = frames()
	chip = f.search.cwUp.chip
	eq(f.header.right, nil); eq(chip.disabled, false)
	chip.scripts.OnClick(chip)
	eq(#stub.browseQueries, 1)
	eq(frames().search.cwUp.chip.label.text, "Searching 1 of 15 · Head")
	Answer(stub, { [16] = { Row(6001, 12, 2500, 4) } })
	f = frames()
	eq(#f.items, 1); eq(f.items[1].itemID, 6001); eq(f.items[1].group, "ah")
	assert(f.items[1].how:find("4 listed", 1, true), f.items[1].how)
	eq(f.items[1].gainText, "+3 AGI · +2 armor")
	eq(f.items[1].costText, ns.FormatCoins(2500))
	assert(f.header.note:find("searched", 1, true), f.header.note)
	ns.ToggleDismissed(6001)
	eq(#frames().items, 0)
	ns.db.settings.showDismissed = true
	ns.Notify("UPGRADES_CHANGED")
	eq(frames().items[1].dismissed, true)
end)
