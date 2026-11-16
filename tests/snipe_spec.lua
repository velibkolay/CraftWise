-- The snipe list and the keys (#315, part 2): his typed max price (equal is allowed), the quantity limit, his
-- value over the defaults, the toast finds, one action per key press, nothing on a held key, nothing queued
-- while the server is busy, and every safety check on the key path too.
local NOW = 1794000000
local HORDE = "PvP|H"
local CLOTH, SWORD = 100, 300

local function Setup()
	local ns, stub = LoadAddon()
	stub.clock = NOW
	time = function() return stub.clock end
	stub.items[CLOTH] = { name = "Linen Cloth", sellPrice = 100 }
	stub.items[SWORD] = { name = "Test Sword", sellPrice = 0 }
	stub.money = 10000000
	AuctionHouseFrame = CreateFrame("Frame", "AuctionHouseFrame")
	local ah = { calls = {}, searches = {}, popups = {}, quote = 10 }
	local C = C_AuctionHouse
	C.MakeItemKey = function(id) return { itemID = id, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 } end
	C.GetItemKeyInfo = function(key) return ah.info and ah.info[key.itemID] end
	C.SendSearchQuery = function(key, sorts, sep) ah.searches[#ah.searches + 1] = { key = key, sorts = sorts, sep = sep } end
	C.PlaceBid = function(id, amount) ah.calls[#ah.calls + 1] = "bid:" .. id .. ":" .. amount end
	C.StartCommoditiesPurchase = function(id, q) ah.calls[#ah.calls + 1] = "start:" .. id .. ":" .. q end
	C.ConfirmCommoditiesPurchase = function(id, q) ah.calls[#ah.calls + 1] = "confirm:" .. id .. ":" .. q end
	C.CancelCommoditiesPurchase = function() ah.calls[#ah.calls + 1] = "cancel" end
	C.GetQuoteDurationRemaining = function() return ah.quote end
	StaticPopupDialogs = StaticPopupDialogs or {}
	StaticPopup_Show = function(which, a1, a2, data) ah.popups[#ah.popups + 1] = { which = which, a1 = a1, a2 = a2, data = data } end
	stub.Fire("AUCTION_HOUSE_SHOW")
	return ns, stub, ah
end

local function Commodity(stub, rows)
	local list = {}
	for i, r in ipairs(rows) do
		list[i] = { itemID = CLOTH, quantity = r[2], unitPrice = r[1], auctionID = 1000 + i, owners = {}, containsOwnerItem = false }
	end
	stub.commodity[CLOTH] = { rows = list, total = 99 }
end
local function ItemAuctions(stub, rows)
	local list = {}
	for i, r in ipairs(rows) do
		list[i] = { itemKey = { itemID = SWORD }, auctionID = r[3] or 500 + i, quantity = 1, buyoutAmount = r[1], containsOwnerItem = false }
	end
	stub.itemSearch[SWORD] = { rows = list }
end

local function Seed(ns, itemID, o)
	local db = CraftWiseMarketDB
	local t = o.t or NOW
	local entry = { raw = { { t = t, total = o.total or 0, listings = 1, tiers = o.tiers } }, days = {},
		last = { t = t, min = o.tiers[1], qty = o.total, listings = 1 } }
	db.items[itemID] = db.items[itemID] or {}
	db.items[itemID][HORDE] = entry
	db.houses[HORDE] = db.houses[HORDE] or { realm = "PvP", kind = "faction", faction = "Horde", label = "Horde AH" }
	db.scans[HORDE] = { { t = NOW, kind = "scan", items = 1, source = "ui" } }
end

-- One full key press: the key goes down and up.
local function Press(fn)
	local r1, r2 = fn("down")
	fn("up")
	return r1, r2
end

----------------------------------------------------------------------------------------------- the list

it("ParsePrice: gold, silver and copper, a bare number is gold; nothing else is a price", function()
	local ns = Setup()
	local P = ns.Snipe.ParsePrice
	eq(P("3g 40s 5c"), 34005); eq(P("40s"), 4000); eq(P("12c"), 12); eq(P("3.5g"), 35000); eq(P("3"), 30000)
	eq(P(" 1G 2S "), 10200); eq(P("5c 1g"), 10005)
	local v, why = P("abc"); eq(v, nil); assert(why)
	eq(P(""), nil); eq(P("0"), nil); eq(P("0g 0s"), nil); eq(P("1g 2g"), nil); eq(P("5x"), nil); eq(P("3g junk"), nil)
	eq(ns.Snipe.PriceText(34005), "3g 40s 5c"); eq(ns.Snipe.PriceText(4000), "40s"); eq(ns.Snipe.PriceText(12), "12c")
	eq(ns.Snipe.ParsePrice(ns.Snipe.PriceText(10005)), 10005)
end)

it("Snipe list: add, change, remove; only a whole max price above 0 and a whole limit; saved per account", function()
	local ns = Setup()
	local S = ns.Snipe
	eq(S.Set(CLOTH, 50, 20), true)
	eq(#ns.db.snipe, 1); eq(ns.db.snipe[1].itemID, CLOTH); eq(ns.db.snipe[1].max, 50); eq(ns.db.snipe[1].upTo, 20)
	eq(S.Set(CLOTH, 60, nil), true); eq(#ns.db.snipe, 1, "the same item changes, it is not added twice"); eq(ns.db.snipe[1].max, 60)
	eq(ns.db.snipe[1].upTo, nil)
	local ok, why = S.Set(CLOTH, 0, nil); eq(ok, false); assert(why)
	eq(S.Set(CLOTH, 1.5, nil), false); eq(S.Set(CLOTH, 5, 0), false); eq(S.Set(CLOTH, 5, 2.5), false); eq(S.Set(CLOTH, 5, 5000), false)
	eq(S.Set("x", 5), false); eq(S.Set(-3, 5), false)
	eq(ns.db.snipe[1].max, 60, "a refused change leaves the entry as it was")
	eq(S.ItemFromText("|cff1eff00|Hitem:300::::::::|h[Test Sword]|h|r"), SWORD); eq(S.ItemFromText("100"), CLOTH); eq(S.ItemFromText(""), nil)
	eq(S.Remove(CLOTH), true); eq(#ns.db.snipe, 0); eq(S.Remove(CLOTH), false)
	for i = 1, S.MAX_ENTRIES do eq(S.Set(1000 + i, 5), true) end
	eq(S.Set(5000, 5), false, "a full list refuses another item")
end)

it("Lines: his typed max price wins over a flip's and a basket line's default, the snipes come first", function()
	local ns = Setup()
	ns.db.flips = { items = { { itemID = CLOTH, units = 15, atLeast = false, profit = 400, price = 40, sell = 100, maxUnit = 99 } } }
	local plan = { split = { auction = { { itemID = SWORD, quantity = 3 } } } }
	local lines = ns.AHBuy.Lines(plan)
	eq(#lines, 2); eq(lines[1].maxUnit, 99); eq(lines[2].maxUnit, nil)
	ns.Snipe.Set(SWORD, 700, nil)
	lines = ns.AHBuy.Lines(plan)
	eq(lines[1].itemID, SWORD, "the snipe list first"); eq(lines[1].kind, "basket"); eq(lines[1].maxUnit, 700); eq(lines[1].need, 3, "no limit of his own: the line's quantity")
	eq(lines[1].snipe, true); eq(lines[2].itemID, CLOTH); eq(lines[2].maxUnit, 99)
	ns.Snipe.Set(CLOTH, 60, 7)
	lines = ns.AHBuy.Lines(plan)
	local flip
	for _, l in ipairs(lines) do if l.itemID == CLOTH then flip = l end end
	eq(flip.kind, "flip"); eq(flip.maxUnit, 60, "his value is lower than the default and still wins"); eq(flip.need, 7, "and so does his limit"); eq(flip.sell, 100)
	ns.Snipe.Set(1234, 42, nil)
	lines = ns.AHBuy.Lines({ split = { auction = {} } })
	local own
	for _, l in ipairs(lines) do if l.itemID == 1234 then own = l end end
	eq(own.kind, "snipe"); eq(own.maxUnit, 42); eq(own.need, ns.Snipe.UPTO, "no line, no limit: the default limit")
end)

----------------------------------------------------------------------------------------------- the keys

it("Search key: one search per press, walking the lines and round to the first; a held key does nothing extra", function()
	local ns, stub, ah = Setup()
	ns.Snipe.Set(CLOTH, 50, nil); ns.Snipe.Set(SWORD, 700, nil)
	local K = ns.AHBuy.KeySearch
	eq(Press(K), true); eq(#ah.searches, 1); eq(ah.searches[1].key.itemID, CLOTH, "no line picked: the first")
	eq(Press(K), true); eq(#ah.searches, 2); eq(ah.searches[2].key.itemID, SWORD)
	eq(Press(K), true); eq(#ah.searches, 3); eq(ah.searches[3].key.itemID, CLOTH, "round to the first")
	eq(K("down"), true); eq(#ah.searches, 4)
	eq(K("down"), false); eq(K("down"), false); eq(#ah.searches, 4, "the key is still down: no repeat")
	K("up")
	eq(K("down"), true); eq(#ah.searches, 5, "a fresh press searches again")
	K("up")
	-- a macro or a call without a key state is one press
	eq(CraftWise_AHSearchKey(), true); eq(#ah.searches, 6)
end)

it("Search key: nothing to search, a closed auction house, a busy server: nothing is sent and nothing is queued", function()
	local ns, stub, ah = Setup()
	local ok, why = ns.AHBuy.KeySearch("down"); ns.AHBuy.KeySearch("up")
	eq(ok, false); assert(why:find("Nothing to search"), why); eq(#ah.searches, 0)
	ns.Snipe.Set(CLOTH, 50, nil)
	stub.throttleReady = false
	ok, why = ns.AHBuy.KeySearch("down"); ns.AHBuy.KeySearch("up")
	eq(ok, false); assert(why:find("Wait"), why); eq(#ah.searches, 0)
	stub.throttleReady = true
	stub.Fire("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
	eq(#ah.searches, 0, "the press is not remembered: the ready event searches nothing")
	stub.Fire("AUCTION_HOUSE_CLOSED")
	ok, why = ns.AHBuy.KeySearch("down"); ns.AHBuy.KeySearch("up")
	eq(ok, false); eq(why, "Open the auction house first"); eq(#ah.searches, 0)
end)

it("Search key: after a purchase it searches the same line again; during a started commodity purchase it drops the quote", function()
	local ns, stub, ah = Setup()
	ns.Snipe.Set(CLOTH, 100, 5); ns.Snipe.Set(SWORD, 700, nil)
	Commodity(stub, { { 40, 5 } })
	Press(ns.AHBuy.KeySearch); stub.Fire("COMMODITY_SEARCH_RESULTS_UPDATED", CLOTH)
	Press(ns.AHBuy.KeyBuy); stub.Fire("COMMODITY_PRICE_UPDATED", 40, 200)
	eq(ns.AHBuy.state.phase, "confirm")
	Press(ns.AHBuy.KeySearch) -- the next line while a quote is open
	eq(ah.calls[#ah.calls], "cancel", "the open quote is given up, not left hanging"); eq(ah.searches[#ah.searches].key.itemID, SWORD)
	-- finish a purchase, then the key searches the same line, not the next
	ItemAuctions(stub, { { 700, 1, 77 } })
	stub.Fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = SWORD })
	Press(ns.AHBuy.KeyBuy); stub.Fire("AUCTION_HOUSE_PURCHASE_COMPLETED")
	eq(ns.AHBuy.state.phase, "stale")
	local n = #ah.searches
	Press(ns.AHBuy.KeySearch)
	eq(#ah.searches, n + 1); eq(ah.searches[n + 1].key.itemID, SWORD, "the same line again: the results were old")
end)

it("Buy key: an item auction at or below his max is one press; a held key and the next presses buy nothing more", function()
	local ns, stub, ah = Setup()
	ns.Snipe.Set(SWORD, 700, nil) -- equal to the cheapest auction: allowed
	ItemAuctions(stub, { { 700, 1, 77 }, { 900, 1, 78 } })
	Press(ns.AHBuy.KeySearch); stub.Fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = SWORD })
	eq(#ah.calls, 0, "searching buys nothing")
	local K = ns.AHBuy.KeyBuy
	eq(K("down"), true); eq(table.concat(ah.calls, ","), "bid:77:700")
	eq(K("down"), false); eq(K("down"), false); eq(#ah.calls, 1, "held: no repeat")
	K("up")
	local ok = K("down"); K("up")
	eq(ok, false); eq(#ah.calls, 1, "a fresh press while the result is out buys nothing")
	stub.Fire("AUCTION_HOUSE_PURCHASE_COMPLETED")
	ok = Press(K)
	eq(ok, false); eq(#ah.calls, 1, "after the result the list is old: the press buys nothing until a search")
end)

it("Buy key: above his max nothing is bought; the quantity limit caps a commodity purchase", function()
	local ns, stub, ah = Setup()
	ns.Snipe.Set(CLOTH, 90, 12)
	Commodity(stub, { { 40, 5 }, { 90, 10 }, { 91, 50 } })
	Press(ns.AHBuy.KeySearch); stub.Fire("COMMODITY_SEARCH_RESULTS_UPDATED", CLOTH)
	local plan = ns.AHBuy.Refresh()
	eq(plan.units, 12, "up to his limit"); eq(plan.total, 40 * 5 + 90 * 7); eq(plan.unitMax, 90, "a unit at the max is allowed")
	eq(Press(ns.AHBuy.KeyBuy), true); eq(table.concat(ah.calls, ","), "start:100:12")
	-- below the max everywhere: nothing listed that he wants
	local ns2, stub2, ah2 = Setup()
	ns2.Snipe.Set(CLOTH, 39, nil)
	Commodity(stub2, { { 40, 5 } })
	Press(ns2.AHBuy.KeySearch); stub2.Fire("COMMODITY_SEARCH_RESULTS_UPDATED", CLOTH)
	local ok, why = Press(ns2.AHBuy.KeyBuy)
	eq(ok, false); assert(why:find("max price"), why); eq(#ah2.calls, 0)
end)

it("Buy key: a commodity takes two presses (start, then confirm); a price above his max or the shown total is cancelled", function()
	local ns, stub, ah = Setup()
	ns.Snipe.Set(CLOTH, 90, 6)
	Commodity(stub, { { 40, 5 }, { 90, 10 } })
	Press(ns.AHBuy.KeySearch); stub.Fire("COMMODITY_SEARCH_RESULTS_UPDATED", CLOTH)
	local K = ns.AHBuy.KeyBuy
	eq(K("down"), true); eq(table.concat(ah.calls, ","), "start:100:6")
	eq(K("down"), false, "the start key is still down: it does not confirm"); eq(#ah.calls, 1)
	K("up")
	eq(Press(K), false, "no quote yet: a press while the server has not answered confirms nothing"); eq(#ah.calls, 1)
	stub.Fire("COMMODITY_PRICE_UPDATED", 40, 5 * 40 + 90)
	eq(ns.AHBuy.state.phase, "confirm")
	eq(Press(K), true); eq(table.concat(ah.calls, ","), "start:100:6,confirm:100:6")
	stub.Fire("COMMODITY_PURCHASE_SUCCEEDED")
	-- the price rises above his max between start and confirm: cancelled, never confirmed
	local ns2, stub2, ah2 = Setup()
	ns2.Snipe.Set(CLOTH, 90, 6)
	Commodity(stub2, { { 40, 5 }, { 90, 10 } })
	Press(ns2.AHBuy.KeySearch); stub2.Fire("COMMODITY_SEARCH_RESULTS_UPDATED", CLOTH)
	Press(ns2.AHBuy.KeyBuy)
	stub2.Fire("COMMODITY_PRICE_UPDATED", 95, 6 * 95)
	eq(table.concat(ah2.calls, ","), "start:100:6,cancel"); eq(ns2.AHBuy.state.phase, "stale")
	eq(Press(ns2.AHBuy.KeyBuy), false); eq(#ah2.calls, 2, "nothing confirms it afterwards")
end)

it("Buy key: the same checks as the button (price rose, auction gone, not enough gold, snipe list changed)", function()
	-- the price rose after the panel showed it
	local ns, stub, ah = Setup()
	ns.Snipe.Set(SWORD, 800, nil)
	ItemAuctions(stub, { { 700, 1, 77 } })
	Press(ns.AHBuy.KeySearch); stub.Fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = SWORD })
	ns.AHBuy.Refresh()
	ItemAuctions(stub, { { 790, 1, 77 } })
	local ok, why = Press(ns.AHBuy.KeyBuy)
	eq(ok, false); assert(why:find("price changed"), why); eq(#ah.calls, 0)
	-- the auction is gone
	local ns2, stub2, ah2 = Setup()
	ns2.Snipe.Set(SWORD, 800, nil)
	ItemAuctions(stub2, { { 700, 1, 77 } })
	Press(ns2.AHBuy.KeySearch); stub2.Fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = SWORD })
	ns2.AHBuy.Refresh()
	ItemAuctions(stub2, { { 700, 1, 99 } })
	ok, why = Press(ns2.AHBuy.KeyBuy)
	eq(ok, false); assert(why:find("gone"), why); eq(#ah2.calls, 0)
	-- not enough gold
	local ns3, stub3, ah3 = Setup()
	ns3.Snipe.Set(SWORD, 800, nil)
	ItemAuctions(stub3, { { 700, 1, 77 } })
	Press(ns3.AHBuy.KeySearch); stub3.Fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = SWORD })
	ns3.AHBuy.Refresh()
	stub3.money = 100
	ok, why = Press(ns3.AHBuy.KeyBuy)
	eq(ok, false); assert(why:find("gold"), why); eq(#ah3.calls, 0)
	-- he lowers his max while the results are shown: the line is dropped, the press buys nothing
	local ns4, stub4, ah4 = Setup()
	ns4.Snipe.Set(SWORD, 800, nil)
	ItemAuctions(stub4, { { 700, 1, 77 } })
	Press(ns4.AHBuy.KeySearch); stub4.Fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = SWORD })
	ns4.AHBuy.Refresh()
	ns4.Snipe.Set(SWORD, 600, nil)
	eq(ns4.AHBuy.state.target, nil, "the changed list drops the picked line")
	ok = Press(ns4.AHBuy.KeyBuy)
	eq(ok, false); eq(#ah4.calls, 0)
	-- above the confirm limit the client's dialog asks first, also for the key
	local ns5, stub5, ah5 = Setup()
	ns5.Snipe.Set(SWORD, 500000, nil)
	ItemAuctions(stub5, { { 400000, 1, 77 } })
	Press(ns5.AHBuy.KeySearch); stub5.Fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = SWORD })
	ns5.AHBuy.Refresh()
	eq(Press(ns5.AHBuy.KeyBuy), true); eq(#ah5.calls, 0, "40g is above the limit: asks first"); eq(#ah5.popups, 1)
end)

----------------------------------------------------------------------------------------------- the toast

it("Snipe toast: items at or below his max after a scan, one toast with the flips, again only when cheaper", function()
	local ns, stub, ah = Setup()
	ns.Snipe.Set(SWORD, 90, nil); ns.Snipe.Set(CLOTH, 100, nil)
	Seed(ns, SWORD, { tiers = { 90, 2, 120, 4 }, total = 6 }) -- 90 equals the max: a find
	Seed(ns, CLOTH, { tiers = { 101, 9 }, total = 9 }) -- 1c above the max (and above the vendor price): not a find
	ns.Notify("PRICES_CHANGED"); stub.RunTimers()
	local lines = ns.LootToast.Lines()
	eq(#lines, 1); eq(lines[1].text, "1 snipe under your max"); eq(lines[1].detail, "Test Sword ×2")
	eq(lines[1].sourceText, "Snipe list")
	stub.clock = stub.clock + 10
	ns.Notify("PRICES_CHANGED"); stub.RunTimers()
	eq(#ns.LootToast.Lines(), 1, "the same find: no second toast")
	-- cheaper: new notice
	Seed(ns, SWORD, { tiers = { 80, 2 }, total = 2, t = stub.clock })
	ns.Notify("PRICES_CHANGED"); stub.RunTimers()
	eq(#ns.LootToast.Lines(), 1)
	-- a second snipe with the flips in one toast
	ns.LootToast.Clear()
	Seed(ns, CLOTH, { tiers = { 40, 5 }, total = 5, t = stub.clock }) -- a snipe at 40 <= 50, and a flip (vendor 100)
	ns.Notify("PRICES_CHANGED"); stub.RunTimers()
	lines = ns.LootToast.Lines()
	eq(#lines, 1); eq(lines[1].text, "1 AH → vendor flip · 1 snipe under your max")
	-- the toast buys and searches nothing
	eq(#ah.calls, 0); eq(#ah.searches, 0)
end)

it("Snipe toast: the setting turns it off, no list means no check, a click opens nothing but the panel", function()
	local ns, stub, ah = Setup()
	ns.Snipe.Set(SWORD, 90, nil)
	Seed(ns, SWORD, { tiers = { 90, 2 }, total = 2 })
	ns.db.settings.snipeAlert = false
	ns.Notify("PRICES_CHANGED"); stub.RunTimers()
	eq(#ns.LootToast.Lines(), 0)
	ns.db.settings.snipeAlert = true
	stub.clock = stub.clock + 10
	ns.Notify("PRICES_CHANGED"); stub.RunTimers()
	local lines = ns.LootToast.Lines()
	eq(#lines, 1)
	lines[1].onClick(lines[1])
	eq(#ah.calls, 0); eq(#ah.searches, 0, "the click searches and buys nothing")
	ns.Snipe.Remove(SWORD)
	eq(#ns.Loops.SnipeCheck(), 0)
end)

----------------------------------------------------------------------------------------------- source rules

local function Source(path)
	local f = assert(io.open(path, "rb"))
	local text = f:read("*a")
	f:close()
	return text
end

local function AddonFiles()
	local files = {}
	for line in io.lines("CraftWise/CraftWise.toc") do
		if not line:match("^%s*#") and line:match("%S") then
			files[#files + 1] = "CraftWise/" .. line:gsub("\\", "/"):gsub("%s+$", "")
		end
	end
	return files
end

it("Source: the bindings are two, under the one CraftWise header, each only calls its key function with keystate", function()
	local xml = Source("CraftWise/Bindings.xml")
	local _, headers = xml:gsub('header="', "")
	eq(headers, 1, "the header is declared once")
	local search = xml:match('<Binding name="CRAFTWISE_AH_SEARCH"([^>]*)>%s*(.-)%s*</Binding>')
	local buy = xml:match('<Binding name="CRAFTWISE_AH_BUY"([^>]*)>%s*(.-)%s*</Binding>')
	assert(search and buy, "both bindings exist")
	local sa, sb = xml:match('<Binding name="CRAFTWISE_AH_SEARCH"([^>]*)>%s*(.-)%s*</Binding>')
	assert(sa:find('runOnUp="true"', 1, true)); eq(sb, "CraftWise_AHSearchKey(keystate)")
	local ba, bb = xml:match('<Binding name="CRAFTWISE_AH_BUY"([^>]*)>%s*(.-)%s*</Binding>')
	assert(ba:find('runOnUp="true"', 1, true)); eq(bb, "CraftWise_AHBuyKey(keystate)")
	eq(BINDING_NAME_CRAFTWISE_AH_SEARCH, "AH: search next"); eq(BINDING_NAME_CRAFTWISE_AH_BUY, "AH: buy best")
end)

it("Source: the buy path is reached from the button, the dialog and the buy key only; the keys do nothing on a timer", function()
	local count = 0
	for _, path in ipairs(AddonFiles()) do
		local text = Source(path)
		for n, line in ipairs((function() local t = {} for l in (text .. "\n"):gmatch("(.-)\r?\n") do t[#t + 1] = (l:gsub("%-%-.*$", "")) end return t end)()) do
			if line:find("AHBuy.KeyBuy", 1, true) or line:find("AHBuy.KeySearch", 1, true) then
				assert(path:find("CraftWise/AHBuy.lua", 1, true), path .. ":" .. n .. " reaches a key function from outside AHBuy.lua")
				count = count + 1
			end
			if path:find("CraftWise/AHBuy.lua", 1, true) and line:find("AHBuy.Click", 1, true) and not line:find("^function") then
				assert(line:find("Press(\"buy\"", 1, true), path .. ":" .. n .. " uses Click outside the buy key")
			end
		end
	end
	assert(count >= 2, "the key functions are used by the global wrappers")
	for _, bad in ipairs({ "C_Timer", "OnUpdate", "NewTicker", "NewTimer", "After(" }) do
		assert(not Source("CraftWise/AHBuy.lua"):gsub("%-%-[^\n]*", ""):find(bad, 1, true), "AHBuy.lua uses " .. bad)
		assert(not Source("CraftWise/Snipe.lua"):gsub("%-%-[^\n]*", ""):find(bad, 1, true), "Snipe.lua uses " .. bad)
	end
end)

----------------------------------------------------------------------------------------------- the panel

it("Panel: a snipe line is marked and has an ×, Save writes the typed price, a bad price says why and saves nothing", function()
	local ns, stub, ah = Setup()
	ns.Snipe.Set(SWORD, 700, 3)
	ns.Notify("SNIPE_CHANGED")
	local panel = CraftWiseAHPanel
	local lines = ns.AHPanel.Lines()
	eq(#lines, 1); eq(ns.AHPanel.LineText(lines[1]), "Test Sword ×3 · max " .. ns.FormatMoney(700, true) .. " · snipe")
	-- the form: item, price, limit
	panel.itemBox:SetText("100"); panel.maxBox:SetText("3g 40s"); panel.upToBox:SetText("")
	local ok = ns.AHPanel.Save()
	eq(ok, true); eq(ns.Snipe.Find(CLOTH).max, 34000); eq(ns.Snipe.Find(CLOTH).upTo, nil); eq(panel.itemBox:GetText(), "")
	panel.itemBox:SetText("100"); panel.maxBox:SetText("lots"); panel.upToBox:SetText("")
	local bad, why = ns.AHPanel.Save()
	eq(bad, false); assert(why); eq(ns.Snipe.Find(CLOTH).max, 34000, "a bad price changes nothing")
	panel.itemBox:SetText("nonsense"); panel.maxBox:SetText("5g")
	bad = ns.AHPanel.Save()
	eq(bad, false)
	-- a line fills the form
	ns.AHPanel.Prefill(lines[1])
	eq(panel.itemBox:GetText(), "Test Sword"); eq(panel.maxBox:GetText(), ns.Snipe.PriceText(700)); eq(panel.upToBox:GetText(), "3")
	-- the × removes only the list entry
	local remove
	for _, fr in ipairs(stub.frames) do
		if fr.scripts and fr.scripts.OnClick and fr.GetParent and fr:GetParent() and fr:GetParent().line and fr:GetParent().remove == fr and not remove then remove = fr end
	end
	assert(remove, "the × exists")
	remove.scripts.OnClick(remove)
	eq(ns.Snipe.Find(SWORD), nil); eq(#ah.calls, 0); eq(#ah.searches, 0)
end)

it("Item menu: Add to snipe list fills the form and says where to type the price; nothing is saved", function()
	local ns = Setup()
	local found = false
	for _, o in ipairs(ns.ItemMenuOptions) do found = found or o.key == "snipe" end
	assert(found, "the option is in the menu")
	ns.AHPanel.Prefill(SWORD)
	eq(CraftWiseAHPanel.itemBox:GetText(), "Test Sword"); eq(CraftWiseAHPanel.maxBox:GetText(), "")
	eq(#ns.db.snipe, 0)
end)
