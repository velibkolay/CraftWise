-- #202: Look up › Items opens with bounded work whatever the size of the market data, and Price history
-- goes to the site. Invented data only.
local NOW = 1794000000
local DAY = 86400
local HORDE = "PvP|H"

local function Load()
	local ns, stub = LoadAddon()
	stub.clock = NOW
	time = function() return stub.clock end
	stub.Fire("PLAYER_LOGIN")
	return ns, stub, ns.Main
end

-- n items 200001..: every third in the market scope with a month of history, the rest `last` only; all
-- packed as strings the way the saved file holds them. named = false leaves db.names empty. The names run
-- against the item IDs, so the list order shows it comes from the names.
local function SeedMarket(ns, n, named)
	local Mk, db = ns.Market, CraftWiseMarketDB
	db.houses[HORDE] = { realm = "PvP", kind = "faction", faction = "Horde", label = "Horde AH" }
	local today = math.floor(NOW / DAY)
	local scoped = 0
	for i = 1, n do
		local id = 200000 + i
		local entry = { last = { t = NOW - 3600, min = 850, qty = 20, listings = 3 }, raw = {}, days = {} }
		if i % 3 == 0 then
			for d = 0, 29 do
				entry.days[today - d] = { lo = 800, typ = 900 + d, hi = 1000, qtyMax = 50, listMax = 9, n = 4, gone = 1 }
			end
			entry.raw[1] = { t = NOW - 3600, total = 20, listings = 3, tiers = { 850, 5, 900, 15 } }
			db.scope.items[id] = true
			scoped = scoped + 1
		end
		db.items[id] = { [HORDE] = Mk.EncodeEntry(entry) }
		if named ~= false then
			db.names[id] = ("Synthetic %05d"):format(n - i)
		end
	end
	return scoped
end

it("ItemSiteURL: https://wow.velikopter.com/item/<itemID> for a whole item ID, nil for anything else", function()
	local ns = Load()
	eq(ns.ItemSiteURL(19019), "https://wow.velikopter.com/item/19019")
	eq(ns.ItemSiteURL("19019"), "https://wow.velikopter.com/item/19019")
	eq(ns.ItemSiteURL(nil), nil); eq(ns.ItemSiteURL(0), nil); eq(ns.ItemSiteURL(-5), nil)
	eq(ns.ItemSiteURL(12.5), nil); eq(ns.ItemSiteURL("sword"), nil)
end)

it("Price history popup: the address selected in an edit box, Ctrl+C line, Escape closes, the address can't be edited", function()
	local ns = Load()
	eq(ns.ShowPriceHistory(nil), nil)
	eq(ns.ShowPriceHistory(19019), "https://wow.velikopter.com/item/19019")
	local f = CraftWiseSiteLink
	eq(f.shown, true); eq(f.url, "https://wow.velikopter.com/item/19019")
	eq(f.box:GetText(), f.url)
	assert(f.hint.text:find("Ctrl+C", 1, true), "tells to copy with Ctrl+C: " .. tostring(f.hint.text))
	local found = false
	for _, name in ipairs(UISpecialFrames) do found = found or name == "CraftWiseSiteLink" end
	assert(found, "Escape closes it")
	-- selected: on show and whenever the box gets focus
	local selected = 0
	f.box.HighlightText = function() selected = selected + 1 end
	f.box.scripts.OnEditFocusGained(f.box)
	eq(selected, 1)
	f.box:SetText("something typed")
	f.box.scripts.OnTextChanged(f.box)
	eq(f.box:GetText(), f.url, "put back")
	assert(selected >= 2, "and selected again")
	-- another item changes the address
	ns.ShowPriceHistory(6948)
	eq(CraftWiseSiteLink.box:GetText(), "https://wow.velikopter.com/item/6948")
	f.box.scripts.OnEscapePressed(f.box)
	eq(f.shown, false)
end)

it("every Price history entry point shows the popup: the item menu and the opened Make row go through ns.OpenItemLookup", function()
	local ns = Load()
	local looked = false
	ns.ShowItemLookup = function() looked = true end
	eq(ns.OpenItemLookup(19019, "history"), true)
	eq(CraftWiseSiteLink.url, "https://wow.velikopter.com/item/19019")
	eq(looked, false)
	eq(ns.OpenItemLookup(nil, "history"), false)
	ns.OpenItemLookup(19019, "where")
	eq(looked, true, "Where to buy still opens Look up › Items")
end)

it("market index: ItemKeys and RecordedItemIDs follow the keys (added by a scan, dropped by prune) and the index is built once", function()
	local ns, stub = Load()
	local Mk = ns.Market
	CraftWiseMarketDB.scope.items[5] = true
	stub.zone, stub.subzone = "Orgrimmar", ""
	stub.Fire("AUCTION_HOUSE_SHOW")
	eq(Mk.ItemKeys(5)[1], nil)
	local v0 = Mk.DataVersion()
	stub.commodity[5] = { rows = { { unitPrice = 100, quantity = 3 } }, total = 3 }
	stub.Fire("COMMODITY_SEARCH_RESULTS_UPDATED", 5)
	stub.RunTimers()
	assert(Mk.DataVersion() ~= v0, "a new key changes the data version")
	eq(Mk.ItemKeys(5)[1], 5); eq(Mk.RecordedItemIDs()[5] ~= nil, true)
	local at = Mk.indexBuilds
	for _ = 1, 200 do Mk.ItemKeys(5); Mk.RecordedItemIDs() end
	eq(Mk.indexBuilds, at, "no rebuild while the keys stay")
	stub.Fire("AUCTION_HOUSE_CLOSED")
	local v1 = Mk.DataVersion()
	stub.clock = NOW + 32 * DAY
	Mk.Prune()
	eq(CraftWiseMarketDB.items[5], nil)
	assert(Mk.DataVersion() ~= v1, "a dropped key changes the data version")
	eq(Mk.ItemKeys(5)[1], nil); eq(Mk.RecordedItemIDs()[5], nil)
end)

it("market index: an item's suffix variants come after the plain key, by key", function()
	local ns = Load()
	local db = CraftWiseMarketDB
	db.items[7] = { [HORDE] = "" }; db.items["7:90"] = { [HORDE] = "" }; db.items["7:12"] = { [HORDE] = "" }
	db.items[8] = { [HORDE] = "" }
	local keys = ns.Market.ItemKeys(7)
	eq(#keys, 3); eq(keys[1], 7); eq(keys[2], "7:12"); eq(keys[3], "7:90")
	keys[1] = "changed"
	eq(ns.Market.ItemKeys(7)[1], 7, "a caller gets its own table")
	eq(ns.Market.ItemKeys(9)[1], nil)
end)

it("Look up › Items opens with bounded work: 6,000 items, only the rows drawn are priced, the index and the sort are built once", function()
	local ns, _, M = Load()
	local scoped = SeedMarket(ns, 6000)
	local I = M.Items
	local priced = 0
	local row = I.Row
	I.Row = function(...) priced = priced + 1; return row(...) end
	local built, caches = ns.Market.indexBuilds, I.cacheBuilds
	local list = I.ListModel(NOW)
	eq(#list.rows, I.LIST_MAX); eq(list.more, scoped - I.LIST_MAX)
	eq(priced, 0, "building the list prices no row")
	eq(list.rows[1].itemID, 200000 + 6000 - (6000 % 3), "alphabetical by stored name, not by item ID")
	eq(list.rows[1].name, "Synthetic 00000")
	eq(priced, 1, "the first read fills the row")
	for i = 1, 14 do local _ = list.rows[i].priceText end -- what the scroll box draws
	eq(priced, 14, "one pricing per row, however often it is read")
	for _ = 1, 5 do I.ListModel(NOW) end
	eq(ns.Market.indexBuilds - built, 1, "the market data is walked once")
	eq(I.cacheBuilds - caches, 1, "the sorted list is built once")
	I.Row = row
end)

it("Look up › Items: a scan that adds an item rebuilds the sorted list once", function()
	local ns, stub, M = Load()
	SeedMarket(ns, 300)
	local I = M.Items
	local before = #I.ChipItems("recipes")
	local caches = I.cacheBuilds
	I.ChipItems("recipes")
	eq(I.cacheBuilds, caches, "nothing changed, nothing rebuilt")
	CraftWiseMarketDB.scope.items[5] = true
	stub.zone, stub.subzone = "Orgrimmar", ""
	stub.Fire("AUCTION_HOUSE_SHOW")
	stub.commodity[5] = { rows = { { unitPrice = 100, quantity = 3 } }, total = 3 }
	stub.Fire("COMMODITY_SEARCH_RESULTS_UPDATED", 5)
	stub.RunTimers()
	eq(#I.ChipItems("recipes"), before + 1, "the new item is listed")
	eq(I.cacheBuilds - caches, 1)
	I.ChipItems("recipes")
	eq(I.cacheBuilds - caches, 1)
end)

it("Look up › Items: without stored names the client is asked for a bounded number of items, not every recorded one", function()
	local ns, _, M = Load()
	SeedMarket(ns, 3000, false)
	local calls = 0
	local getInfo = C_Item.GetItemInfo
	C_Item.GetItemInfo = function(...) calls = calls + 1; return getInfo(...) end
	local I = M.Items
	I.state.query = ""
	I.Model(NOW)
	assert(calls <= 40, "opening asked the client for " .. calls .. " items")
	calls = 0
	I.state.query = "synthetic"
	I.Model(NOW)
	assert(calls <= I.UNNAMED_MAX + 40, "a search looked at " .. calls .. " items")
end)

it("Look up › Items: a search reads the stored names, exact names first, and costs one build for many keystrokes", function()
	local ns, _, M = Load()
	SeedMarket(ns, 900)
	local I = M.Items
	local caches = I.cacheBuilds
	local ids = I.Search("synthetic 00005")
	eq(#ids, 1); eq(ids[1], 200000 + 900 - 5)
	local ids2, more = I.Search("synthetic 0001")
	eq(#ids2, 10); eq(more, 0)
	eq(CraftWiseMarketDB.names[ids2[1]], "Synthetic 00010")
	I.Search("synthetic 00"); I.Search("synthetic 000")
	eq(I.cacheBuilds - caches, 1)
	local capped, left = I.Search("synthetic")
	eq(#capped, I.LIST_MAX); eq(left, 900 - I.LIST_MAX)
end)

it("Look up › Items: the page's Refresh is a timed hook in the recorder (Settings > Debug)", function()
	local ns, _, M = Load()
	local seen = {}
	ns.SetRecorder(function(kind, _, label) seen[#seen + 1] = kind .. "|" .. label end)
	M.Open("items")
	M.Refresh()
	local found = false
	for _, line in ipairs(seen) do found = found or line == "hook|Look up › Items: Refresh" end
	assert(found, "recorded: " .. table.concat(seen, ", "))
end)
