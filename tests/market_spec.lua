-- Issue #26 phase 1: recorder, storage, house detection, pruning.
local NOW = 1794000000 -- fixed clock; a whole number of days plus 21600 s
local DAY = 86400
local HORDE, BOOTY, GADGET = "PvP|H", "PvP|N:BootyBay", "PvP|N:Gadgetzan"

local function Market(opts)
	local ns, stub = LoadAddon(opts)
	time = function() return stub.clock end
	stub.clock = NOW
	return ns.Market, stub, ns
end

local function InScope(items)
	for _, id in ipairs(items) do CraftWiseMarketDB.scope.items[id] = true end
end

local function OpenAH(stub, zone, subzone)
	stub.zone, stub.subzone = zone or "Orgrimmar", subzone or ""
	stub.Fire("AUCTION_HOUSE_SHOW")
end

local function CommoditySearch(stub, itemID, rows, total, full)
	stub.commodity[itemID] = { rows = rows, total = total, full = full }
	stub.Fire("COMMODITY_SEARCH_RESULTS_UPDATED", itemID)
	stub.RunTimers()
end

local function ListEq(actual, expected, msg)
	eq(table.concat(actual, ","), table.concat(expected, ","), msg)
end

-- Mimics WoW's SavedVariables writer: tabs per depth, ["key"] = value, array items with -- [n].
local function SerializedSize(value)
	local size = 0
	local function write(v, depth)
		local kind = type(v)
		if kind == "string" then
			size = size + #v + 2
		elseif kind ~= "table" then
			size = size + #tostring(v)
		else
			size = size + 2
			local n = #v
			for i = 1, n do
				size = size + depth + 1
				write(v[i], depth + 1)
				size = size + #(", -- [" .. i .. "]\n")
			end
			for k, x in pairs(v) do
				if not (type(k) == "number" and k >= 1 and k <= n) then
					size = size + depth + 1 + #tostring(k) + (type(k) == "string" and 8 or 6)
					write(x, depth + 1)
					size = size + 2
				end
			end
			size = size + depth + 1
		end
	end
	write(value, 0)
	return size
end

------------------------------------------------------------------------------------------- houses

it("detects the house from faction and zone text", function()
	local M, stub = Market()
	stub.zone, stub.subzone = "Orgrimmar", "Valley of Strength"
	eq((M.DetectHouse()), HORDE)
	stub.zone, stub.subzone = "Booty Bay", ""
	eq((M.DetectHouse()), BOOTY)
	stub.zone, stub.subzone = "Stranglethorn Vale", "The Salty Sailor Tavern"
	eq((M.DetectHouse()), BOOTY)
	stub.zone, stub.subzone = "Tanaris", "Gadgetzan"
	eq((M.DetectHouse()), GADGET)
	stub.zone, stub.subzone = "Winterspring", "Everlook"
	eq((M.DetectHouse()), "PvP|N:Everlook")
	stub.faction, stub.zone, stub.subzone = "Alliance", "Ironforge", ""
	eq((M.DetectHouse()), "PvP|A")
end)

it("records nothing when the house can't be told", function()
	local M, stub = Market()
	stub.zone, stub.subzone = "", ""
	eq(M.DetectHouse(), nil)
	stub.zone, stub.faction = "Orgrimmar", "Neutral"
	eq(M.DetectHouse(), nil)
	stub.faction, stub.realm = "Horde", ""
	eq(M.DetectHouse(), nil)
	stub.realm, stub.locale = "PvP", "deDE" -- a German Booty Bay must not land in the faction house
	eq(M.DetectHouse(), nil)

	InScope({ 1 })
	OpenAH(stub)
	CommoditySearch(stub, 1, { { unitPrice = 100, quantity = 5 } }, 5)
	eq(next(CraftWiseMarketDB.items), nil)
end)

it("stores house records with an unmeasured cut", function()
	local _, stub = Market()
	OpenAH(stub, "Booty Bay")
	local house = CraftWiseMarketDB.houses[BOOTY]
	eq(house.kind, "neutral"); eq(house.label, "Booty Bay"); eq(house.realm, "PvP")
	eq(house.cut.rate, nil); eq(house.cut.samples, 0)
	OpenAH(stub, "Orgrimmar")
	eq(CraftWiseMarketDB.houses[HORDE].faction, "Horde")
	eq(CraftWiseMarketDB.houses[HORDE].label, "Horde AH")
end)

it("keeps Booty Bay and Horde prices apart", function()
	local M, stub = Market()
	InScope({ 7 })
	OpenAH(stub, "Orgrimmar")
	CommoditySearch(stub, 7, { { unitPrice = 300, quantity = 10 } }, 10)
	stub.Fire("AUCTION_HOUSE_CLOSED")
	stub.clock = NOW + 3600
	OpenAH(stub, "Booty Bay")
	CommoditySearch(stub, 7, { { unitPrice = 50300, quantity = 2 } }, 2)
	eq(M.Current(7, HORDE).min, 300)
	eq(M.Current(7, HORDE).t, NOW)
	eq(M.Current(7, BOOTY).min, 50300)
	local houses = M.Houses(7)
	eq(#houses, 2); eq(houses[1].key, HORDE); eq(houses[2].key, BOOTY)
end)

it("holds the house until the AH closes, and records nothing after", function()
	local M, stub = Market()
	InScope({ 7 })
	OpenAH(stub, "Gadgetzan")
	stub.zone = "Orgrimmar" -- zone text changing while the window is open changes nothing
	CommoditySearch(stub, 7, { { unitPrice = 10, quantity = 1 } }, 1)
	eq(M.Current(7, GADGET).min, 10)
	eq(M.Current(7, HORDE), nil)
	stub.Fire("AUCTION_HOUSE_CLOSED")
	stub.clock = NOW + 100
	CommoditySearch(stub, 7, { { unitPrice = 99, quantity = 1 } }, 1)
	eq(M.Current(7, GADGET).min, 10)
end)

-------------------------------------------------------------------------------------- search results

it("records commodity tiers: merged, sorted, first 8, with total and listings", function()
	local M, stub = Market()
	InScope({ 5 })
	OpenAH(stub)
	local rows = {}
	for i = 10, 1, -1 do rows[#rows + 1] = { unitPrice = i * 100, quantity = 2, owners = { "Seller" } } end
	rows[#rows + 1] = { unitPrice = 100, quantity = 3, owners = { "Other" } } -- same price, second row
	CommoditySearch(stub, 5, rows, 23)
	local depth = M.Depth(5, HORDE)
	eq(#depth, 8); eq(depth.total, 23)
	eq(depth[1].price, 100); eq(depth[1].qty, 5)
	eq(depth[8].price, 800)
	local current = M.Current(5, HORDE)
	eq(current.min, 100); eq(current.qty, 23); eq(current.listings, 11); eq(current.t, NOW)
	eq(#M.Depth(5, HORDE, 2), 2)
end)

it("never stores seller names", function()
	local _, stub = Market()
	InScope({ 5 })
	OpenAH(stub)
	CommoditySearch(stub, 5, { { unitPrice = 100, quantity = 1, owners = { "SellerName" } } }, 1)
	stub.Fire("PLAYER_LOGOUT")
	local function check(t)
		for k, v in pairs(t) do
			assert(k ~= "owners" and k ~= "owner", "seller key stored")
			if type(v) == "string" then assert(not v:find("SellerName"), "seller name stored") end
			if type(v) == "table" then check(v) end
		end
	end
	check(CraftWiseMarketDB)
end)

it("one result set is one point, however many events it fires", function()
	local M, stub = Market()
	InScope({ 5 })
	OpenAH(stub)
	local rows = { { unitPrice = 100, quantity = 3 } }
	stub.commodity[5] = { rows = rows, total = 3 }
	stub.Fire("COMMODITY_SEARCH_RESULTS_UPDATED", 5)
	stub.Fire("COMMODITY_SEARCH_RESULTS_ADDED", 5)
	stub.Fire("COMMODITY_SEARCH_RESULTS_UPDATED", 5)
	stub.RunTimers()
	stub.clock = NOW + 30
	stub.Fire("COMMODITY_SEARCH_RESULTS_UPDATED", 5) -- settled already, identical
	stub.RunTimers()
	eq(#CraftWiseMarketDB.items[5][HORDE].raw, 1)
	eq(#CraftWiseMarketDB.scans[HORDE], 1)
	eq(CraftWiseMarketDB.scans[HORDE][1].kind, "search")

	stub.clock = NOW + 61 -- same market a minute later is a new observation
	stub.Fire("COMMODITY_SEARCH_RESULTS_UPDATED", 5)
	stub.RunTimers()
	eq(#CraftWiseMarketDB.items[5][HORDE].raw, 2)
	stub.clock = NOW + 65 -- changed market is a new point at once
	CommoditySearch(stub, 5, { { unitPrice = 90, quantity = 3 } }, 3)
	eq(#M.Depth(5, HORDE, 1), 1); eq(M.Depth(5, HORDE)[1].price, 90)
	eq(#CraftWiseMarketDB.items[5][HORDE].raw, 3)
end)

it("reads waiting searches when the AH closes before they settle", function()
	local M, stub = Market()
	InScope({ 5 })
	OpenAH(stub)
	stub.commodity[5] = { rows = { { unitPrice = 100, quantity = 3 } }, total = 3 }
	stub.Fire("COMMODITY_SEARCH_RESULTS_UPDATED", 5)
	stub.Fire("AUCTION_HOUSE_CLOSED")
	eq(M.Current(5, HORDE).min, 100)
	stub.RunTimers() -- the cancelled timer does nothing more
	eq(#M.Houses(5), 1)
end)

it("an empty search proves nothing", function()
	local M, stub = Market()
	InScope({ 5 })
	OpenAH(stub)
	CommoditySearch(stub, 5, { { unitPrice = 100, quantity = 3 } }, 3)
	stub.clock = NOW + 100
	CommoditySearch(stub, 5, {}, 0)
	eq(#CraftWiseMarketDB.items[5][HORDE].raw, 1)
	eq(M.Current(5, HORDE).listed, true)
end)

it("item searches: suffix gets its own key, bid-only rows are skipped", function()
	local M, stub = Market()
	OpenAH(stub)
	stub.itemSearch["9:1205"] = { rows = {
		{ buyoutAmount = 500, quantity = 1 },
		{ buyoutAmount = nil, quantity = 1 },
		{ buyoutAmount = 700, quantity = 1 },
	}, total = 3 }
	stub.Fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = 9, itemSuffix = 1205, itemLevel = 20 })
	stub.RunTimers()
	eq(M.Current("9:1205", HORDE).min, 500)
	eq(M.Current("9:1205", HORDE).listings, 2)
	eq(M.Current(9, HORDE), nil)
	eq(M.InScope(9), true, "searching for an item is interacting with it")
end)

it("a partial list is used only when it runs from the cheapest row", function()
	local M, stub = Market()
	OpenAH(stub)
	stub.itemSearch[9] = { rows = { { buyoutAmount = 900, quantity = 1 }, { buyoutAmount = 500, quantity = 1 } }, total = 40, full = false }
	stub.Fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = 9, itemSuffix = 0 })
	stub.RunTimers()
	eq(M.Current(9, HORDE), nil)
	stub.itemSearch[9] = { rows = { { buyoutAmount = 500, quantity = 1 }, { buyoutAmount = 900, quantity = 1 } }, total = 40, full = false }
	stub.Fire("ITEM_SEARCH_RESULTS_ADDED", { itemID = 9, itemSuffix = 0 })
	stub.RunTimers()
	eq(M.Current(9, HORDE).min, 500)
	eq(M.Current(9, HORDE).qty, 40)
	eq(M.Depth(9, HORDE).total, 40)
end)

it("browse rows update the latest price only, in scope only", function()
	local M, stub = Market()
	InScope({ 5 })
	OpenAH(stub)
	stub.browse = {
		{ itemKey = { itemID = 5, itemSuffix = 0 }, minPrice = 250, totalQuantity = 28 },
		{ itemKey = { itemID = 6, itemSuffix = 0 }, minPrice = 1, totalQuantity = 1 },
	}
	stub.Fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
	eq(M.Current(5, HORDE).min, 250)
	eq(M.Current(5, HORDE).qty, 28)
	eq(M.Current(5, HORDE).listings, nil)
	eq(#CraftWiseMarketDB.items[5][HORDE].raw, 0, "no tiers, so no raw point")
	eq(CraftWiseMarketDB.items[6], nil)
	eq(M.InScope(6), false, "seeing an item in a browse list isn't interacting with it")
	stub.Fire("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", { { itemKey = { itemID = 5, itemSuffix = 0 }, minPrice = 240, totalQuantity = 30 } })
	eq(M.Current(5, HORDE).min, 240)
	eq(#CraftWiseMarketDB.scans[HORDE], 2)
	stub.Fire("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", { { itemKey = { itemID = 5, itemSuffix = 0 }, minPrice = 240, totalQuantity = 30 } })
	eq(#CraftWiseMarketDB.scans[HORDE], 2, "repeated row")
end)

------------------------------------------------------------------------------------------ full scan

local function Rows(list)
	local out = {}
	for _, r in ipairs(list) do
		out[#out + 1] = { itemID = r[1], count = r[2], buyout = r[3], link = r[4] or ("item:" .. r[1]), owner = "Seller" }
	end
	return out
end

it("full scan: unit price per stack, scope filter, tiers, source, log", function()
	local M, stub = Market({ auctionator = true })
	InScope({ 1, 2 })
	OpenAH(stub)
	stub.replicate = Rows({
		{ 1, 20, 2000 }, -- 100 each
		{ 1, 5, 500 }, -- same price, second listing
		{ 1, 3, 450 }, -- 150 each
		{ 2, 1, 7 },
		{ 3, 1, 1 }, -- out of scope
		{ 1, 1, 0 }, -- bid only
		{ 1, 0, 100 }, -- the client sometimes returns 0 available
	})
	stub.Fire("REPLICATE_ITEM_LIST_UPDATE")
	local depth = M.Depth(1, HORDE)
	eq(#depth, 2); eq(depth.total, 28)
	eq(depth[1].price, 100); eq(depth[1].qty, 25)
	eq(depth[2].price, 150); eq(depth[2].qty, 3)
	eq(M.Current(1, HORDE).listings, 3)
	eq(M.Current(2, HORDE).min, 7)
	eq(CraftWiseMarketDB.items[3], nil)
	local log = CraftWiseMarketDB.scans[HORDE][1]
	eq(log.kind, "full"); eq(log.items, 2); eq(log.source, "auctionator"); eq(log.t, NOW)
end)

it("full scan reads across frames, not all at once", function()
	local _, stub = Market()
	InScope({ 1 })
	OpenAH(stub)
	stub.replicate = {}
	for i = 1, 2600 do stub.replicate[i] = { itemID = 1, count = 1, buyout = i, link = "item:1" } end
	local waits, run = 0, nil
	C_Timer.After = function(_, fn) waits = waits + 1; run = fn end
	stub.Fire("REPLICATE_ITEM_LIST_UPDATE")
	eq(waits, 1, "the first frame must stop after one chunk")
	eq(CraftWiseMarketDB.items[1], nil, "nothing stored before every row was read")
	for _ = 1, 10 do
		if CraftWiseMarketDB.scans[HORDE] then break end
		run()
	end
	assert(waits >= 5, "expected at least 5 frames, got " .. waits)
	assert(CraftWiseMarketDB.items[1][HORDE].raw[1].total == 2600, "all rows counted")
end)

it("full scan is discarded when the AH closes during reading", function()
	local _, stub = Market()
	InScope({ 1 })
	OpenAH(stub)
	stub.replicate = {}
	for i = 1, 1200 do stub.replicate[i] = { itemID = 1, count = 1, buyout = 100, link = "item:1" } end
	local run
	local after = C_Timer.After
	C_Timer.After = function(_, fn) run = fn end
	stub.Fire("REPLICATE_ITEM_LIST_UPDATE")
	stub.Fire("AUCTION_HOUSE_CLOSED")
	C_Timer.After = after -- every remaining frame runs now
	run()
	eq(CraftWiseMarketDB.items[1], nil)
	eq(CraftWiseMarketDB.scans[HORDE], nil)
end)

it("full scan is discarded when the list changes under it", function()
	local _, stub = Market()
	InScope({ 1 })
	OpenAH(stub)
	stub.replicate = {}
	for i = 1, 1200 do stub.replicate[i] = { itemID = 1, count = 1, buyout = 100, link = "item:1" } end
	local run
	local after = C_Timer.After
	C_Timer.After = function(_, fn) run = fn end
	stub.Fire("REPLICATE_ITEM_LIST_UPDATE")
	stub.replicate[1200] = nil
	C_Timer.After = after -- every remaining frame runs now
	run()
	eq(CraftWiseMarketDB.items[1], nil)
	eq(CraftWiseMarketDB.scans[HORDE], nil)
end)

it("the same list firing twice is one scan", function()
	local _, stub = Market()
	InScope({ 1 })
	OpenAH(stub)
	stub.replicate = Rows({ { 1, 1, 100 } })
	stub.Fire("REPLICATE_ITEM_LIST_UPDATE")
	stub.Fire("REPLICATE_ITEM_LIST_UPDATE")
	eq(#CraftWiseMarketDB.items[1][HORDE].raw, 1)
	eq(#CraftWiseMarketDB.scans[HORDE], 1)
end)

it("full scan: skips rows with no item data", function()
	local M, stub = Market()
	InScope({ 1, 2 })
	OpenAH(stub)
	stub.missingItems[2] = true
	stub.replicate = Rows({ { 1, 1, 100 }, { 2, 1, 100 } })
	stub.Fire("REPLICATE_ITEM_LIST_UPDATE")
	eq(M.Current(1, HORDE).min, 100)
	eq(M.Current(2, HORDE), nil)
end)

it("full scan: gear waits for its link, reagents don't need one", function()
	local M, stub = Market()
	InScope({ 1, 2 })
	stub.itemClass[1] = 7 -- trade goods: no suffix possible, no link needed
	stub.itemClass[2] = 4 -- armor
	OpenAH(stub)
	stub.replicate = Rows({ { 1, 1, 100 }, { 2, 1, 900 } })
	stub.replicate[1].link = nil
	stub.replicate[2].link = nil
	C_Item.RequestLoadItemDataByID = function(id)
		if id == 2 then stub.replicate[2].link = "|cff|Hitem:2:0:0:0:0:0:-77:123:20|h[Pants of the Bear]|h|r" end
	end
	stub.Fire("REPLICATE_ITEM_LIST_UPDATE")
	eq(M.Current(1, HORDE).min, 100)
	eq(M.Current("2:-77", HORDE).min, 900)
	eq(M.Current(2, HORDE), nil)
end)

it("full scan: items whose links never load are left out, not guessed or counted as gone", function()
	local M, stub = Market()
	InScope({ 1, 2 })
	stub.itemClass[1], stub.itemClass[2] = 7, 4
	OpenAH(stub)
	stub.replicate = Rows({ { 2, 1, 900 } })
	stub.Fire("REPLICATE_ITEM_LIST_UPDATE")
	stub.Fire("AUCTION_HOUSE_CLOSED")
	stub.clock = NOW + 3600
	OpenAH(stub)
	stub.replicate = Rows({ { 1, 1, 100 }, { 2, 1, 900 } })
	stub.replicate[2].link = nil
	stub.Fire("REPLICATE_ITEM_LIST_UPDATE")
	eq(M.Current(1, HORDE).min, 100)
	eq(#M.DecodeEntry(CraftWiseMarketDB.items[2][HORDE]).raw, 1, "no point for the unread item")
	eq(M.Current(2, HORDE).t, NOW)
end)

it("an item missing from a finished full scan is off the market", function()
	local M, stub = Market()
	InScope({ 1, 2 })
	stub.itemClass[1], stub.itemClass[2] = 7, 7
	OpenAH(stub)
	stub.replicate = Rows({ { 1, 10, 1000 }, { 2, 1, 50 } })
	stub.Fire("REPLICATE_ITEM_LIST_UPDATE")
	stub.clock = NOW + 3600
	stub.replicate = Rows({ { 2, 1, 50 } })
	stub.Fire("REPLICATE_ITEM_LIST_UPDATE")
	local current = M.Current(1, HORDE)
	eq(current.listed, false); eq(current.min, 100); eq(current.t, NOW, "last seen stays")
	eq(M.Depth(1, HORDE).total, 0)
	eq(M.Disappeared(1, HORDE), 10)
	stub.clock = NOW + 7200
	stub.replicate = Rows({ { 2, 1, 51 } })
	stub.Fire("REPLICATE_ITEM_LIST_UPDATE")
	eq(#CraftWiseMarketDB.items[1][HORDE].raw, 2, "one absent point, not one per scan")
	eq(M.Disappeared(1, HORDE), 10)
end)

---------------------------------------------------------------------------------------------- scope

it("scope: bags, bank, own loot; not other players' loot", function()
	local M, stub = Market()
	stub.bags[0] = { { itemID = 11 }, false }
	stub.Fire("BAG_UPDATE_DELAYED")
	eq(M.InScope(11), true)

	stub.bags[-1] = { { itemID = 12 } }
	eq(M.InScope(12), false)
	Enum.BagIndex.Bank = -1
	stub.Fire("BANKFRAME_OPENED")
	eq(M.InScope(12), true)

	local function loot(text, guid)
		stub.Fire("CHAT_MSG_LOOT", text, "", "", "", "", "", 0, 0, "", 0, 1, guid)
	end
	loot("You receive loot: |cff|Hitem:13::::::::20:::::|h[Thing]|h|r.", "Player-1-SELF")
	eq(M.InScope(13), true)
	loot("Someone receives loot: |cff|Hitem:14::::::::20:::::|h[Other]|h|r.", "Player-1-OTHER")
	eq(M.InScope(14), false)
	loot(nil, "Player-1-SELF") -- a secret or odd payload must not raise an error
end)

it("scope: the character's recipe cache, known and learnable", function()
	local M, stub, ns = Market()
	ns.charDB.professions[165] = { name = "Leatherworking", recipes = {
		[1] = { learned = true, reagents = { { itemID = 21, quantity = 1 } }, output = { itemID = 22, quantity = 1 } },
		[2] = { learned = false, reagents = { { itemID = 23, quantity = 1 } } },
	} }
	stub.Fire("PLAYER_LOGIN")
	eq(M.InScope(21), true); eq(M.InScope(22), true); eq(M.InScope(23), true)
	eq(M.InScope(99), false)
	ns.charDB.professions[165].recipes[3] = { reagents = { { itemID = 24, quantity = 1 } } }
	ns.Notify("RECIPES_CHANGED", 165)
	eq(M.InScope(24), true)
end)

it("scope: bundled recipes of own professions plus the alt's, nothing else", function()
	local M, stub, ns = Market({ data = true })
	ns.charDB.professions[165] = { name = "Leatherworking", recipes = {} }
	stub.Fire("PLAYER_LOGIN")
	local function sample(skillLine)
		for _, data in pairs(ns.RecipeData) do
			if data.skillLine == skillLine and data.output then return data.reagents[1].itemID, data.output.itemID end
		end
	end
	local reagent, output = sample(165)
	eq(M.InScope(reagent), true); eq(M.InScope(output), true)
	reagent, output = sample(202) -- Engineering, the alt's
	eq(M.InScope(reagent), true); eq(M.InScope(output), true)
	reagent, output = sample(186) -- Mining, the alt's
	eq(M.InScope(reagent), true); eq(M.InScope(output), true)
	local lines = CraftWiseMarketDB.scope.skillLines
	eq(lines[165], true); eq(lines[202], true); eq(lines[186], true); eq(lines[197], nil)
	-- A Tailoring-only output stays out.
	local own = {}
	for _, data in pairs(ns.RecipeData) do
		if lines[data.skillLine] then
			own[data.output and data.output.itemID or 0] = true
			for _, r in ipairs(data.reagents or {}) do own[r.itemID] = true end
		end
	end
	for _, data in pairs(ns.RecipeData) do
		if data.skillLine == 197 and data.output and not own[data.output.itemID] then
			eq(M.InScope(data.output.itemID), false)
			break
		end
	end
end)

it("scope survives a reload and remembers another character's professions", function()
	Market()
	CraftWiseMarketDB.scope.skillLines[197] = true
	local M, stub, ns = Market({ data = true, savedMarket = CraftWiseMarketDB })
	stub.Fire("PLAYER_LOGIN")
	for _, data in pairs(ns.RecipeData) do
		if data.skillLine == 197 and data.output then
			eq(M.InScope(data.output.itemID), true)
			break
		end
	end
end)

---------------------------------------------------------------------------------------------- maths

it("cheapest median: Veli's Crawler Meat example and the 7.5% point", function()
	local Market_ = Market()
	eq(Market_.CheapestMedian({ 250, 3, 1000, 25 }, 28), 250) -- 3 @ 2s50, 25 @ 10s
	eq(Market_.CheapestMedian({ 100, 5, 200, 95 }, 100), 200) -- 7.5 units in: past the 5 at 100
	eq(Market_.CheapestMedian({ 100, 8, 200, 92 }, 100), 100)
	eq(Market_.CheapestMedian({ 100, 2 }, 100), nil, "tiers end before the 7.5% point")
	eq(Market_.CheapestMedian({}, 0), nil)
end)

it("m is stored only when the stored tiers don't hold all units, from all rows", function()
	local M = Market()
	local prices = {}
	for i = 1, 8 do prices[i * 100] = 2 end
	local whole = M.BuildObservation(prices, 8)
	eq(whole.m, nil); eq(whole.total, 16)
	prices[900] = 400 -- 16 units in 8 tiers, then the mass: position 31.2 is at 900
	local deep = M.BuildObservation(prices, 9)
	eq(#deep.tiers, 16); eq(deep.total, 416); eq(deep.m, 900)
	local partial = M.BuildObservation({ [100] = 2 }, 1, 1000) -- rows end early: unknown, not guessed
	eq(partial.total, 1000); eq(partial.m, nil)
end)

it("day typical pools the day's observations by quantity", function()
	local M = Market()
	eq(M.DayTypical({ { total = 10, tiers = { 100, 10 } }, { total = 10, tiers = { 300, 10 } } }), 100)
	eq(M.DayTypical({ { total = 100, tiers = { 100, 7, 200, 93 } } }), 200)
	eq(M.DayTypical({ { total = 0, tiers = {} } }), nil)
	eq(M.DayTypical({ { total = 0, tiers = {} }, { total = 10, tiers = { 50, 10 } } }), 50)
end)

it("day typical uses m past the stored tiers, never the top tier", function()
	local M = Market()
	local cut = { total = 1000, tiers = { 100, 1, 110, 1, 120, 1, 130, 1, 140, 1, 150, 1, 160, 1, 170, 1 }, m = 900 }
	eq(M.DayTypical({ cut }), 900)
	eq(M.DayTypical({ cut, { total = 3000, tiers = { 800, 3000 } } }), 800, "weighted by units")
	eq(M.DayTypical({ { total = 1000, tiers = { 100, 1 } } }), nil, "no m and no reach: no value")
	-- The pooled tiers reach the point only at 900, but the cut-off point may hide cheaper units
	-- above its last stored price (170), so 900 can't be trusted.
	eq(M.DayTypical({ cut, { total = 100, tiers = { 900, 100 } } }), 900, "m 900 weighs most")
	local cheaper = { total = 1000, tiers = cut.tiers, m = 500 }
	eq(M.DayTypical({ cheaper, { total = 100, tiers = { 900, 100 } } }), 500, "not the 900 from the pool")
end)

it("gone: units missing at prices up to the limit; new listings don't hide them", function()
	local M = Market()
	local prev = { total = 40, tiers = { 100, 10, 200, 10, 900, 20 } }
	eq(M.GoneUnits(prev, { total = 25, tiers = { 100, 4, 200, 1, 900, 20 } }, 300), 15)
	eq(M.GoneUnits(prev, { total = 100, tiers = { 50, 70, 100, 10, 900, 20 } }, 300), 10, "cheaper new stock hides nothing")
	eq(M.GoneUnits(prev, { total = 0, tiers = {} }, 300), 20, "above the limit doesn't count")
	eq(M.GoneUnits(prev, { total = 0, tiers = {} }, nil), 0, "no reference price, no count")
	eq(M.GoneUnits(prev, { total = 900, tiers = { 100, 10 } }, 300), 0, "200 is beyond what the new point stores")
end)

it("gone adds up between consecutive scans at the same house only", function()
	local M, stub = Market()
	InScope({ 5 })
	OpenAH(stub)
	CommoditySearch(stub, 5, { { unitPrice = 100, quantity = 10 }, { unitPrice = 200, quantity = 90 } }, 100)
	stub.clock = NOW + 3600
	CommoditySearch(stub, 5, { { unitPrice = 100, quantity = 6 }, { unitPrice = 200, quantity = 90 } }, 96)
	eq(M.Disappeared(5, HORDE), 4)
	stub.Fire("AUCTION_HOUSE_CLOSED")
	stub.clock = NOW + 7200
	OpenAH(stub, "Booty Bay")
	CommoditySearch(stub, 5, { { unitPrice = 100, quantity = 1 } }, 1)
	eq(M.Disappeared(5, BOOTY), 0, "another house's first scan compares to nothing")
	eq(M.Disappeared(5, HORDE), 4)
end)

---------------------------------------------------------------------------------- aggregation, pruning

local function Entry(M, key, house)
	local e = CraftWiseMarketDB.items[key][house]
	return type(e) == "string" and M.DecodeEntry(e) or e
end

it("aggregates a day: lo, typ, hi, qtyMax, listMax, n", function()
	local M = Market()
	local today = math.floor(NOW / DAY)
	local entry = { raw = {
		{ t = NOW - 100, total = 100, listings = 4, tiers = { 100, 10, 500, 90 } },
		{ t = NOW - 50, total = 120, listings = 6, tiers = { 90, 20, 700, 100 } },
		{ t = NOW - 10, total = 0, listings = 0, tiers = {} },
	}, days = {} }
	eq(M.AggregateEntry(entry, NOW), true)
	local d = entry.days[today]
	eq(d.lo, 90); eq(d.hi, 700); eq(d.qtyMax, 120); eq(d.listMax, 6); eq(d.n, 3)
	eq(d.typ, 90) -- 220 units: 16.5 in, the 20 at 90 cover it
	eq(#entry.raw, 3, "younger than 48 h stays")
end)

it("raw goes after 48 h, days after 30, and their aggregate stays", function()
	local M = Market()
	local today = math.floor(NOW / DAY)
	local entry = { last = { t = NOW - 40 * DAY, min = 1, qty = 1 }, raw = {
		{ t = NOW - 49 * 3600, total = 10, listings = 1, tiers = { 100, 10 } },
		{ t = NOW - 47 * 3600, total = 10, listings = 1, tiers = { 200, 10 } },
	}, days = { [today - 31] = { lo = 1, n = 1 }, [today - 30] = { lo = 2, n = 1 } } }
	eq(M.AggregateEntry(entry, NOW), true)
	eq(#entry.raw, 1); eq(entry.raw[1].tiers[1], 200)
	eq(entry.days[today - 31], nil)
	eq(entry.days[today - 30].lo, 2)
	eq(entry.days[math.floor((NOW - 49 * 3600) / DAY)].lo, 100)
end)

it("a day partly past 48 h keeps the aggregate made while it was whole", function()
	local M = Market()
	local start = (math.floor(NOW / DAY) - 2) * DAY
	local entry = { raw = {
		{ t = start + 100, total = 10, listings = 1, tiers = { 100, 10 } },
		{ t = start + 80000, total = 10, listings = 1, tiers = { 300, 10 } },
	}, days = {} }
	local day = math.floor(start / DAY)
	M.AggregateEntry(entry, start + 86399) -- still whole
	eq(entry.days[day].n, 2); eq(entry.days[day].lo, 100); eq(entry.days[day].hi, 300)
	M.AggregateEntry(entry, start + 100 + 48 * 3600 + 1) -- the first point expired
	eq(#entry.raw, 1)
	M.AggregateEntry(entry, start + 100 + 48 * 3600 + 2)
	eq(entry.days[day].n, 2, "not rebuilt from the part that is left")
	eq(entry.days[day].lo, 100)
	eq(entry.days[day].hi, 300)
end)

it("gone stays with its day through aggregation", function()
	local M = Market()
	local today = math.floor(NOW / DAY)
	local entry = { raw = { { t = NOW - 5, total = 1, listings = 1, tiers = { 100, 1 } } }, days = { [today] = { gone = 7 } } }
	M.AggregateEntry(entry, NOW)
	eq(entry.days[today].gone, 7); eq(entry.days[today].lo, 100)
end)

it("entries with nothing left are removed", function()
	local M, stub = Market()
	InScope({ 5 })
	OpenAH(stub)
	CommoditySearch(stub, 5, { { unitPrice = 100, quantity = 3 } }, 3)
	stub.Fire("AUCTION_HOUSE_CLOSED")
	eq(type(CraftWiseMarketDB.items[5][HORDE]), "string")
	stub.clock = NOW + 32 * DAY
	M.Prune()
	eq(CraftWiseMarketDB.items[5], nil)
end)

it("packed entries are left alone for an hour; entries in use are pruned every time", function()
	local M, stub = Market()
	InScope({ 5, 6 })
	OpenAH(stub)
	CommoditySearch(stub, 5, { { unitPrice = 100, quantity = 3 } }, 3)
	stub.Fire("AUCTION_HOUSE_CLOSED")
	local packed = CraftWiseMarketDB.items[5][HORDE]
	eq(type(packed), "string")
	local aggregate, calls = M.AggregateEntry, 0
	M.AggregateEntry = function(...) calls = calls + 1; return aggregate(...) end

	stub.clock = NOW + 600
	OpenAH(stub)
	CommoditySearch(stub, 6, { { unitPrice = 200, quantity = 3 } }, 3)
	stub.Fire("AUCTION_HOUSE_CLOSED")
	eq(calls, 1, "only the entry that was recorded")
	eq(CraftWiseMarketDB.items[5][HORDE], packed)
	eq(type(CraftWiseMarketDB.items[6][HORDE]), "string")

	stub.clock = NOW + 3600
	M.Prune()
	eq(calls, 3, "after an hour, all of them")
	M.AggregateEntry = aggregate
end)

it("prunes on login and on AH close, a few entries per frame", function()
	local M0 = Market()
	local saved = { items = {} }
	for id = 1, 120 do
		saved.items[id] = { [HORDE] = M0.EncodeEntry({
			raw = { { t = NOW - 50 * 3600, total = 5, listings = 1, tiers = { 100, 5 } } }, days = {},
		}) }
	end
	local M, stub = Market({ savedMarket = saved })
	local waits, run = 0, nil
	local after = C_Timer.After
	C_Timer.After = function(_, fn) waits = waits + 1; run = fn end
	stub.Fire("PLAYER_LOGIN")
	eq(waits, 1, "one frame's worth, then wait")
	while true do
		local before = waits
		run()
		if waits == before then break end
	end
	eq(waits, 5) -- 120 entries at 20 per frame: six frames
	C_Timer.After = after
	local e = Entry(M, 1, HORDE)
	eq(#e.raw, 0)
	eq(e.days[math.floor((NOW - 50 * 3600) / DAY)].lo, 100)

	InScope({ 500 })
	OpenAH(stub)
	CommoditySearch(stub, 500, { { unitPrice = 100, quantity = 3 } }, 3)
	eq(type(CraftWiseMarketDB.items[500][HORDE]), "table", "in use while the AH is open")
	stub.Fire("AUCTION_HOUSE_CLOSED")
	eq(type(CraftWiseMarketDB.items[500][HORDE]), "string")
	eq(M.Depth(500, HORDE)[1].price, 100, "reads back after packing")
end)

it("a full scan still being stored at AH close prunes when it ends", function()
	local M, stub = Market()
	InScope({ 1, 2 })
	stub.itemClass[1], stub.itemClass[2] = 7, 7
	OpenAH(stub)
	stub.replicate = Rows({ { 1, 1, 100 }, { 2, 1, 200 } })
	local run
	local after = C_Timer.After
	C_Timer.After = function(_, fn) run = fn end
	for i = 3, 150 do
		stub.itemClass[i] = 7
		InScope({ i })
		stub.replicate[i] = { itemID = i, count = 1, buyout = 100, link = "item:" .. i }
	end
	stub.Fire("REPLICATE_ITEM_LIST_UPDATE") -- first commit chunk done, the rest waits
	eq(CraftWiseMarketDB.scans[HORDE], nil, "storing takes several frames")
	stub.Fire("AUCTION_HOUSE_CLOSED")
	C_Timer.After = after
	run()
	eq(#CraftWiseMarketDB.scans[HORDE], 1, "kept: every row had been read")
	eq(M.Current(150, HORDE).min, 100)
	eq(type(CraftWiseMarketDB.items[1][HORDE]), "string")
end)

it("logout packs every entry; a saved file with tables and strings both loads", function()
	local M, stub = Market()
	InScope({ 5 })
	OpenAH(stub)
	CommoditySearch(stub, 5, { { unitPrice = 100, quantity = 3 } }, 3)
	stub.Fire("PLAYER_LOGOUT")
	eq(type(CraftWiseMarketDB.items[5][HORDE]), "string")
	eq(M.Current(5, HORDE).min, 100)

	local saved = CraftWiseMarketDB
	saved.items[6] = { [HORDE] = { last = { t = NOW, min = 7, qty = 1 }, raw = {}, days = {} } }
	local M2 = Market({ savedMarket = saved })
	eq(M2.Current(5, HORDE).min, 100)
	eq(M2.Current(6, HORDE).min, 7)
end)

it("storage round trip keeps every field, nil and zero included", function()
	local M = Market()
	local today = math.floor(NOW / DAY)
	local entry = {
		last = { t = NOW, min = 250, qty = 28 },
		raw = {
			{ t = NOW - 200, total = 1000, listings = 12, m = 900, tiers = { 250, 3, 1000, 25 } },
			{ t = NOW - 300, total = 0, listings = 0, tiers = {} }, -- clock stepped back
			{ t = NOW - 100, total = 5, tiers = { 1, 5 } },
		},
		days = {
			[today] = { lo = 90, typ = 95, hi = 700, qtyMax = 120, listMax = 6, n = 3, gone = 7 },
			[today - 1] = { gone = 2 },
			[today - 4] = { lo = 5, hi = 5, qtyMax = 0, listMax = 0, n = 1 },
			[today - 5] = { lo = 100, typ = 90, hi = 100, n = 1 }, -- typ below lo can't break it
		},
	}
	local back = M.DecodeEntry(M.EncodeEntry(entry))
	eq(back.last.t, NOW); eq(back.last.min, 250); eq(back.last.qty, 28); eq(back.last.listings, nil)
	eq(#back.raw, 3)
	eq(back.raw[1].t, NOW - 200); eq(back.raw[1].m, 900); eq(back.raw[1].listings, 12)
	ListEq(back.raw[1].tiers, { 250, 3, 1000, 25 })
	eq(back.raw[2].t, NOW - 300); eq(back.raw[2].total, 0); eq(#back.raw[2].tiers, 0); eq(back.raw[2].m, nil)
	eq(back.raw[3].listings, nil); ListEq(back.raw[3].tiers, { 1, 5 })
	local d = back.days[today]
	eq(d.lo, 90); eq(d.typ, 95); eq(d.hi, 700); eq(d.qtyMax, 120); eq(d.listMax, 6); eq(d.n, 3); eq(d.gone, 7)
	eq(back.days[today - 1].gone, 2); eq(back.days[today - 1].lo, nil); eq(back.days[today - 1].typ, nil)
	eq(back.days[today - 4].qtyMax, 0); eq(back.days[today - 4].gone, nil)
	eq(back.days[today - 5].typ, 90)
	local empty = M.DecodeEntry(M.EncodeEntry({ raw = {}, days = {} }))
	eq(empty.last, nil); eq(#empty.raw, 0); eq(next(empty.days), nil)
end)

------------------------------------------------------------------------------------------- read API

local function WithDays(typs)
	local today, days = math.floor(NOW / DAY), {}
	for offset, typ in pairs(typs) do days[today - offset] = { lo = typ, typ = typ, hi = typ, n = 1 } end
	CraftWiseMarketDB.items[5] = { [HORDE] = { raw = {}, days = days, last = { t = NOW, min = 1, qty = 1 } } }
end

it("typical: too little history under 3 days, no data without any", function()
	local M = Market()
	eq(M.Typical(5, HORDE).status, M.NO_DATA)
	WithDays({ [0] = 100, [1] = 200 })
	local t = M.Typical(5, HORDE)
	eq(t.status, M.TOO_LITTLE_HISTORY); eq(t.days, 2); eq(t.price, nil)
	WithDays({})
	eq(M.Typical(5, HORDE).status, M.TOO_LITTLE_HISTORY)
end)

it("typical: median of the last 7 days' typ only", function()
	local M = Market()
	WithDays({ [0] = 100, [1] = 900, [2] = 200 })
	local t = M.Typical(5, HORDE)
	eq(t.status, "ok"); eq(t.price, 200); eq(t.days, 3)
	WithDays({ [0] = 100, [1] = 200, [2] = 300, [3] = 401 })
	eq(M.Typical(5, HORDE).price, 250)
	WithDays({ [0] = 100, [1] = 100, [2] = 100, [6] = 100, [7] = 99999, [8] = 99999, [9] = 99999 })
	eq(M.Typical(5, HORDE).price, 100, "older than 7 days doesn't count")
	eq(M.Typical(5, HORDE).days, 4)
	WithDays({ [8] = 100, [9] = 100, [10] = 100 })
	eq(M.Typical(5, HORDE).status, M.TOO_LITTLE_HISTORY, "old history isn't current")
	WithDays({ [0] = 100, [1] = 300 })
	CraftWiseMarketDB.items[5][HORDE].days[math.floor(NOW / DAY) - 2] = { lo = 1, n = 1 } -- day without typ
	eq(M.Typical(5, HORDE).status, M.TOO_LITTLE_HISTORY)
end)

it("typical is built from recorded scans end to end, per house", function()
	local M, stub = Market()
	InScope({ 5 })
	for d = 2, 0, -1 do
		stub.clock = NOW - d * DAY
		OpenAH(stub)
		CommoditySearch(stub, 5, { { unitPrice = 100 + d, quantity = 50 } }, 50)
		stub.Fire("AUCTION_HOUSE_CLOSED")
	end
	eq(M.Typical(5, HORDE).status, "ok")
	eq(M.Typical(5, HORDE).price, 101)
	eq(M.Typical(5, BOOTY).status, M.NO_DATA)
end)

it("disappeared counts the last 7 days only", function()
	local M = Market()
	local today = math.floor(NOW / DAY)
	CraftWiseMarketDB.items[5] = { [HORDE] = { raw = {}, days = {
		[today] = { gone = 1 }, [today - 6] = { gone = 2 }, [today - 7] = { gone = 40 },
	} } }
	eq(M.Disappeared(5, HORDE), 3)
end)

it("Current, Depth and Houses for unknown items", function()
	local M = Market()
	eq(M.Current(1, HORDE), nil)
	eq(M.Depth(1, HORDE), nil)
	eq(#M.Houses(1), 0)
	eq(M.Disappeared(1, HORDE), 0)
end)

it("recording leaves Auctionator's price alone; profit reads the recording (phase 2)", function()
	local M, stub, ns = Market({ auctionator = true })
	InScope({ 5 })
	stub.ah[5] = 777
	OpenAH(stub)
	CommoditySearch(stub, 5, { { unitPrice = 100, quantity = 3 } }, 3)
	eq(M.Current(5, HORDE).min, 100)
	eq(ns.GetAuctionPrice(5), 777)
	eq(ns.GetBuyPrice(5).copper, 100)
end)

--------------------------------------------------------------------------------------------- /craftwise market

local function Printed(fn)
	local lines, realPrint = {}, print
	print = function(s) lines[#lines + 1] = tostring(s) end
	local ok, err = pcall(fn)
	print = realPrint
	assert(ok, err)
	return table.concat(lines, "\n")
end

it("/craftwise market prints every house with depth, typical and last seen", function()
	local _, stub = Market()
	InScope({ 5 })
	OpenAH(stub)
	CommoditySearch(stub, 5, { { unitPrice = 250, quantity = 3 }, { unitPrice = 1000, quantity = 25 } }, 28)
	stub.Fire("AUCTION_HOUSE_CLOSED")
	stub.clock = NOW + 1800
	OpenAH(stub, "Booty Bay")
	CommoditySearch(stub, 5, { { unitPrice = 5000, quantity = 1 } }, 1)
	local text = Printed(function() SlashCmdList.CRAFTWISE("market 5") end)
	assert(text:find("Horde AH: last", 1, true), text)
	assert(text:find("Booty Bay: last", 1, true), text)
	assert(text:find("3 @ ", 1, true) and text:find("25 @ ", 1, true), text)
	assert(text:find("too little history", 1, true), text)
	assert(text:find("seen 30m ago", 1, true), text)
	assert(text:find(HORDE, 1, true) == nil, "shows the label, not the key")
end)

it("/craftwise market takes a link (lower-cased by the slash handler) and finds suffix variants", function()
	local _, stub = Market()
	OpenAH(stub)
	stub.itemSearch["9:1205"] = { rows = { { buyoutAmount = 500, quantity = 1 } }, total = 1 }
	stub.Fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = 9, itemSuffix = 1205 })
	stub.RunTimers()
	local link = "|cff1eff00|Hitem:9:0:0:0:0:0:1205:0:20|h[Thing of the Bear]|h|r"
	local text = Printed(function() SlashCmdList.CRAFTWISE("market " .. link) end)
	assert(text:find("item 9:1205:", 1, true), text)
	assert(text:find("Horde AH: last", 1, true), text)
	text = Printed(function() SlashCmdList.CRAFTWISE("market 9") end)
	assert(text:find("item 9:1205:", 1, true), text)
end)

it("/craftwise market: no data, unknown item, usage, disappeared label", function()
	local _, stub = Market()
	InScope({ 5 })
	local text = Printed(function() SlashCmdList.CRAFTWISE("market 5") end)
	assert(text:find("no price data", 1, true), text)
	text = Printed(function() SlashCmdList.CRAFTWISE("market 77") end)
	assert(text:find("not a recorded item", 1, true), text)
	text = Printed(function() SlashCmdList.CRAFTWISE("market") end)
	assert(text:find("usage", 1, true), text)

	OpenAH(stub)
	CommoditySearch(stub, 5, { { unitPrice = 100, quantity = 10 }, { unitPrice = 200, quantity = 90 } }, 100)
	stub.clock = NOW + 3600
	CommoditySearch(stub, 5, { { unitPrice = 100, quantity = 6 }, { unitPrice = 200, quantity = 90 } }, 96)
	text = Printed(function() SlashCmdList.CRAFTWISE("market 5") end)
	assert(text:find("disappeared in 7 days: 4 units (sold or expired)", 1, true), text)
	assert(not text:lower():find("sales", 1, true), text)
end)

---------------------------------------------------------------------------------------- size budget

-- Same style of numbers a live market gives, from a fixed seed. Entries are packed one by one, as
-- they are on disk, so the test needs little memory.
local function SeedEntry(M, tiers, rawPoints, seed)
	local base = 50 + (seed * 7919) % 300000
	local step = math.floor(base * 0.04) + 1
	local entry = { last = { t = NOW, min = base, qty = 100, listings = 12 }, raw = {}, days = {} }
	local today = math.floor(NOW / DAY)
	for i = 1, rawPoints do
		local list, price = {}, base
		for k = 1, tiers do
			price = price + (seed * k * 31 + i * 17) % step
			list[#list + 1] = price
			list[#list + 1] = 1 + (seed + k * i * 13) % 60
		end
		entry.raw[i] = {
			t = NOW - (rawPoints - i) * math.floor(2 * DAY / rawPoints),
			total = tiers * 30 + (seed + i) % 300,
			listings = tiers + (seed + i) % 15,
			tiers = list,
		}
	end
	for d = 0, 29 do
		local low = base + (seed * (d + 3)) % step
		entry.days[today - d] = {
			lo = low,
			typ = low + (seed + d) % (step * 2),
			hi = low + math.floor(low * 0.4),
			qtyMax = 20 + (seed + d * 11) % 900,
			listMax = 2 + (seed + d) % 60,
			n = rawPoints / 2,
			gone = (seed + d) % 80,
		}
	end
	return entry
end

local function SeedSize(M, items, houses, tiers, rawPoints)
	local keys = { "PvP|H", "PvP|N:BootyBay", "PvP|N:Gadgetzan", "PvP|N:Everlook" }
	local db = {
		v = 1,
		houses = {},
		scans = {},
		cutSamples = {},
		scope = { items = {}, skillLines = { [165] = true, [393] = true, [202] = true, [186] = true } },
		items = {},
	}
	for h = 1, houses do
		db.houses[keys[h]] = { realm = "PvP", kind = "neutral", label = keys[h], cut = { samples = 0 } }
		db.scans[keys[h]] = {}
		for i = 1, 30 do db.scans[keys[h]][i] = { t = NOW, kind = "full", items = items, source = "auctionator" } end
	end
	local itemID = 2000
	for i = 1, items do
		itemID = itemID + 7
		db.scope.items[itemID] = true
		local perItem = {}
		for h = 1, houses do
			perItem[keys[h]] = M.EncodeEntry(SeedEntry(M, tiers, rawPoints, i * 4 + h))
		end
		db.items[itemID] = perItem
	end
	return SerializedSize(db), db
end

local MB = 1000 * 1000

it("size: packed entries read back the same as the seed", function()
	local M = Market()
	local entry = SeedEntry(M, 8, 20, 3)
	local back = M.DecodeEntry(M.EncodeEntry(entry))
	eq(#back.raw, 20)
	ListEq(back.raw[20].tiers, entry.raw[20].tiers)
	eq(back.days[math.floor(NOW / DAY) - 29].typ, entry.days[math.floor(NOW / DAY) - 29].typ)
end)

-- Budget from the issue, at the load Veli decided on 2026-11-07: his professions' scope (1057 items,
-- rounded up for interacted items) at all 4 houses, 30 days, 2 scans a day, 5 tiers.
it("size: expected load stays under 5 MB", function()
	local M = Market()
	local size = SeedSize(M, 1100, 4, 5, 4)
	print(("       measured: 1100 items x 4 houses, 30 days, 2 scans/day, 5 tiers = %.2f MB"):format(size / MB))
	assert(size < 5 * MB, ("%.2f MB is over the 5 MB budget"):format(size / MB))
end)

-- All professions at every house, 10 scans a day, 8 tiers. Can't fit 5 MB with this retention
-- (decision on #26); this only stops it from growing unnoticed.
it("size: worst case is known and has a ceiling", function()
	local M = Market()
	local size = SeedSize(M, 2500, 4, 8, 20)
	print(("       measured: 2500 items x 4 houses, 30 days, 10 scans/day, 8 tiers = %.2f MB"):format(size / MB))
	assert(size < 25 * MB, ("%.2f MB is over the 25 MB ceiling"):format(size / MB))
end)

it("the TOC declares the market SavedVariables and loads Market after Prices", function()
	local f = assert(io.open("CraftWise/CraftWise.toc"))
	local toc = f:read("*a")
	f:close()
	assert(toc:find("## SavedVariables: CraftWiseDB, CraftWiseMarketDB", 1, true), "SavedVariables line")
	assert(toc:find("Prices.lua", 1, true) < toc:find("Market.lua", 1, true), "load order")
end)
