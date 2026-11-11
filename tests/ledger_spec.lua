-- Issue #46: purchase and sale log (AH + vendor), paid cost of the units still held, /craftwise ledger.
local NOW = os.time({ year = 2026, month = 11, day = 9, hour = 12 })
local HORDE = "PvP|H"
local SALT, HIDE, LINEN, BOOTS, CLH = 4289, 783, 2589, 400, 4231

local function Load()
	local ns, stub = LoadAddon()
	stub.clock = NOW
	time = function(t)
		if t then return os.time(t) end
		return stub.clock
	end
	stub.names.player, stub.names.npc = "Veli", "Tharynn Bouden"
	stub.items[SALT] = { name = "Salt", sellPrice = 12 }
	stub.items[HIDE] = { name = "Light Hide", sellPrice = 50 }
	stub.items[LINEN] = { name = "Linen Cloth", sellPrice = 13 }
	stub.items[BOOTS] = { name = "Old Boots", sellPrice = 70 }
	stub.items[CLH] = { name = "Cured Light Hide", sellPrice = 100 }
	stub.bank = {}
	-- Bags as { [itemID] = count }, one stack per item; bank counts in stub.bank.
	function stub.SetBags(counts)
		local slots = {}
		local ids = {}
		for id in pairs(counts) do ids[#ids + 1] = id end
		table.sort(ids)
		for _, id in ipairs(ids) do
			if counts[id] > 0 then slots[#slots + 1] = { itemID = id, stackCount = counts[id] } end
		end
		stub.bags[0] = slots
	end
	C_Item.GetItemCount = function(id, includeBank)
		local n = 0
		for _, item in ipairs(stub.bags[0] or {}) do
			if item and item.itemID == id then n = n + item.stackCount end
		end
		return n + (includeBank and stub.bank[id] or 0)
	end
	stub.money = 100000
	stub.SetBags({ [LINEN] = 20 })
	stub.Fire("PLAYER_ENTERING_WORLD", true, false)
	return ns, stub
end

-- A trade at the open merchant: bags and money change, then the settle timer runs.
local function Trade(stub, bags, money, moneyFirst)
	if moneyFirst then
		stub.money = money
		stub.Fire("PLAYER_MONEY")
		stub.RunTimers()
		stub.SetBags(bags)
		stub.Fire("BAG_UPDATE_DELAYED")
	else
		stub.SetBags(bags)
		stub.Fire("BAG_UPDATE_DELAYED")
		stub.money = money
		stub.Fire("PLAYER_MONEY")
	end
	stub.RunTimers()
end

local function OpenMerchant(stub)
	stub.merchant = {
		{ itemID = SALT, price = 50, stack = 1 },
		{ itemID = HIDE, price = 210, stack = 2 }, -- 2 for 2s10 = 1s05 each
		{ itemID = 9999, price = 0, stack = 1, extended = true },
	}
	stub.Fire("MERCHANT_SHOW")
end

local function Kinds(ns)
	local out = {}
	for _, e in ipairs(ns.Ledger.Entries()) do
		out[#out + 1] = ("%s %d x%d %d %s"):format(e.k, e.i, e.q, e.m, tostring(e.w))
	end
	return table.concat(out, " | ")
end

local function Printed(fn)
	local lines = {}
	local orig = print
	print = function(s) lines[#lines + 1] = s end
	local ok, err = pcall(fn)
	print = orig
	assert(ok, err)
	-- money icons as letters: 2s 50c
	return (table.concat(lines, "\n"):gsub("|TInterface\\MoneyFrame\\UI%-(%a)%a*Icon:[^|]*|t", function(u) return u:lower() end))
end

local function has(text, s) assert(text:find(s, 1, true), ("missing %q in:\n%s"):format(s, text)) end

it("a vendor purchase adds exactly one entry with the merchant's price, whatever event comes first", function()
	local ns, stub = Load()
	OpenMerchant(stub)
	Trade(stub, { [LINEN] = 20, [SALT] = 5 }, 100000 - 250)
	eq(Kinds(ns), "vbuy 4289 x5 250 Tharynn Bouden")
	Trade(stub, { [LINEN] = 20, [SALT] = 5, [HIDE] = 4 }, 100000 - 250 - 420, true)
	eq(Kinds(ns), "vbuy 4289 x5 250 Tharynn Bouden | vbuy 783 x4 420 Tharynn Bouden")
	eq(CraftWiseMarketDB.ledger.entries[2].t, NOW)
end)

it("a repair, a buyback and a currency purchase are no purchases; a buyback takes the sale back", function()
	local ns, stub = Load()
	OpenMerchant(stub)
	Trade(stub, { [LINEN] = 20 }, 100000 - 1234) -- repair: money only
	eq(#ns.Ledger.Entries(), 0)
	Trade(stub, { [LINEN] = 20, [9999] = 1 }, 100000 - 1234) -- paid with a token: items only
	eq(#ns.Ledger.Entries(), 0)
	-- sell 20 linen, then buy them back
	stub.buyback = 1
	Trade(stub, { [9999] = 1 }, 100000 - 1234 + 260)
	eq(Kinds(ns), "vsell 2589 x20 260 Tharynn Bouden")
	stub.buyback = 0
	Trade(stub, { [9999] = 1, [LINEN] = 20 }, 100000 - 1234)
	eq(Kinds(ns), "vsell 2589 x20 260 Tharynn Bouden | buyback 2589 x20 260 Tharynn Bouden")
	local sum = ns.Ledger.Summary("login")
	eq(sum.received, 0); eq(sum.spent, 0); eq(sum.net, 0)
	eq(sum.change, -1234); eq(sum.other, -1234) -- the repair
end)

it("vendor sales: one stack gets the money, several stacks are split by the vendor price", function()
	local ns, stub = Load()
	stub.SetBags({ [LINEN] = 20, [BOOTS] = 2 })
	OpenMerchant(stub)
	Trade(stub, { [LINEN] = 20, [BOOTS] = 1 }, 100070)
	eq(Kinds(ns), "vsell 400 x1 70 Tharynn Bouden")
	Trade(stub, {}, 100070 + 70 + 260) -- Sell junk: several items in one moment
	eq(Kinds(ns), "vsell 400 x1 70 Tharynn Bouden | vsell 400 x1 70 Tharynn Bouden | vsell 2589 x20 260 Tharynn Bouden")
	stub.Fire("MERCHANT_CLOSED")
end)

it("logs nothing when several items change and the prices don't explain the money", function()
	local ns, stub = Load()
	stub.SetBags({ [LINEN] = 20, [BOOTS] = 2 })
	OpenMerchant(stub)
	Trade(stub, {}, 100000 + 999)
	eq(#ns.Ledger.Entries(), 0)
end)

it("an AH commodity purchase takes quantity and price from the purchase the player started", function()
	local ns, stub = Load()
	stub.Fire("AUCTION_HOUSE_SHOW")
	C_AuctionHouse.StartCommoditiesPurchase(CLH, 10)
	stub.Fire("COMMODITY_PRICE_UPDATED", 200, 2000)
	C_AuctionHouse.ConfirmCommoditiesPurchase(CLH, 10)
	stub.money = 98000
	stub.Fire("PLAYER_MONEY")
	stub.Fire("COMMODITY_PURCHASE_SUCCEEDED")
	eq(Kinds(ns), "ahbuy 4231 x10 2000 " .. HORDE)
	-- a failed purchase logs nothing
	C_AuctionHouse.StartCommoditiesPurchase(CLH, 5)
	stub.Fire("COMMODITY_PRICE_UPDATED", 210, 1050)
	C_AuctionHouse.ConfirmCommoditiesPurchase(CLH, 5)
	stub.Fire("COMMODITY_PURCHASE_FAILED")
	stub.Fire("COMMODITY_PURCHASE_SUCCEEDED")
	eq(#ns.Ledger.Entries(), 1)
end)

it("an AH item buyout is logged once; a bid below the buyout is not", function()
	local ns, stub = Load()
	stub.Fire("AUCTION_HOUSE_SHOW")
	local key = { itemID = BOOTS, itemLevel = 5, itemSuffix = 0 }
	stub.auctions[77] = { itemKey = key, buyoutAmount = 5000 }
	stub.auctions[78] = { itemKey = key, buyoutAmount = 6000, minBid = 3000 }
	stub.itemSearch[BOOTS] = { rows = { { auctionID = 77, quantity = 1, buyoutAmount = 5000 }, { auctionID = 78, quantity = 1, buyoutAmount = 6000 } } }
	C_AuctionHouse.PlaceBid(78, 3000)
	stub.Fire("AUCTION_HOUSE_PURCHASE_COMPLETED", 78)
	eq(#ns.Ledger.Entries(), 0)
	C_AuctionHouse.PlaceBid(77, 5000)
	stub.Fire("AUCTION_HOUSE_PURCHASE_COMPLETED", 77)
	stub.Fire("AUCTION_HOUSE_PURCHASE_COMPLETED", 77)
	eq(Kinds(ns), "ahbuy 400 x1 5000 " .. HORDE)
end)

it("paid cost is the average of the units still held, partial while unlogged units are held", function()
	local ns, stub = Load()
	eq(ns.Ledger.PaidCost(SALT), nil)
	OpenMerchant(stub)
	Trade(stub, { [LINEN] = 20, [SALT] = 10 }, 99500) -- 10 at 50c
	stub.Fire("MERCHANT_CLOSED")
	eq(ns.Ledger.PaidCost(SALT).copper, 50)
	stub.SetBags({ [LINEN] = 20, [SALT] = 4 }) -- 6 used in crafts
	stub.Fire("BAG_UPDATE_DELAYED")
	local paid = ns.Ledger.PaidCost(SALT)
	eq(paid.copper, 50); eq(paid.units, 4); eq(paid.complete, true)
	-- 6 more at the AH for 1s20: (4 x 50 + 720) / 10 = 92c
	C_AuctionHouse.StartCommoditiesPurchase(SALT, 6)
	stub.Fire("COMMODITY_PRICE_UPDATED", 120, 720)
	C_AuctionHouse.ConfirmCommoditiesPurchase(SALT, 6)
	stub.Fire("COMMODITY_PURCHASE_SUCCEEDED")
	paid = ns.Ledger.PaidCost(SALT)
	eq(paid.copper, 92); eq(paid.units, 10) -- 6 still on the way
	stub.SetBags({ [LINEN] = 20, [SALT] = 10 }) -- delivered
	stub.Fire("BAG_UPDATE_DELAYED")
	eq(ns.Ledger.PaidCost(SALT).copper, 92); eq(ns.Ledger.PaidCost(SALT).units, 10)
	-- one Salt looted: no price for it, so the paid cost covers 10 of 11 units (never extrapolated)
	stub.SetBags({ [LINEN] = 20, [SALT] = 11 })
	stub.Fire("BAG_UPDATE_DELAYED")
	paid = ns.Ledger.PaidCost(SALT)
	eq(paid.complete, false); eq(paid.partial, true); eq(paid.copper, 92); eq(paid.known, 10); eq(paid.units, 11)
end)

it("units held before the log: the paid cost covers the logged units only (partial); the bank counts as held", function()
	local ns, stub = Load()
	stub.SetBags({ [LINEN] = 20, [HIDE] = 2 })
	OpenMerchant(stub)
	Trade(stub, { [LINEN] = 20, [HIDE] = 6 }, 100000 - 420)
	stub.Fire("MERCHANT_CLOSED")
	local paid = ns.Ledger.PaidCost(HIDE)
	eq(paid.complete, false); eq(paid.partial, true); eq(paid.known, 4); eq(paid.units, 6)
	eq(paid.copper, 105) -- the average of the 4 logged units, not of all 6
	-- all used up, then bought again: known again
	stub.SetBags({ [LINEN] = 20 })
	stub.Fire("BAG_UPDATE_DELAYED")
	eq(ns.Ledger.PaidCost(HIDE), nil)
	OpenMerchant(stub)
	Trade(stub, { [LINEN] = 20, [HIDE] = 2 }, 100000 - 630)
	stub.Fire("MERCHANT_CLOSED")
	eq(ns.Ledger.PaidCost(HIDE).copper, 105)
	stub.SetBags({ [LINEN] = 20 }); stub.bank[HIDE] = 2 -- moved to the bank
	stub.Fire("BAG_UPDATE_DELAYED")
	eq(ns.Ledger.PaidCost(HIDE).copper, 105)
end)

it("/craftwise ledger: start money, spent and received per item, net checked against the money change", function()
	local ns, stub = Load()
	OpenMerchant(stub)
	Trade(stub, { [LINEN] = 20, [SALT] = 5 }, 99750)
	Trade(stub, { [SALT] = 5 }, 99750 + 260)
	stub.Fire("MERCHANT_CLOSED")
	local sum = ns.Ledger.Summary("login")
	eq(sum.startMoney, 100000); eq(sum.spent, 250); eq(sum.received, 260); eq(sum.net, 10)
	eq(sum.change, 10); eq(sum.other, 0)
	local text = Printed(function() SlashCmdList.CRAFTWISE("ledger login") end)
	has(text, "Ledger, since login: start 10g, now 10g 10c"); has(text, "money change +10c")
	has(text, "Salt: bought 5 for 2s 50c (vendor)")
	has(text, "Linen Cloth: sold 20 for 2s 60c")
	has(text, "spent 2s 50c, received 2s 60c, net +10c")
	has(text, "net matches the money change")
	eq(ns.db.settings.ledgerView, "login")
	-- the chosen view is remembered
	has(Printed(function() SlashCmdList.CRAFTWISE("ledger") end), "Ledger, since login")
end)

it("three views: since login survives /reload, today has per-day rows, reset starts a new period", function()
	local ns, stub = Load()
	local DAY = 86400
	-- yesterday: bought salt
	stub.clock = NOW - DAY
	CraftWiseMarketDB.ledger.chars["PvP-Veli"].days = {}
	CraftWiseMarketDB.ledger.chars["PvP-Veli"].reset = { t = NOW - 2 * DAY, money = 100000 }
	stub.Fire("PLAYER_ENTERING_WORLD", true, false)
	OpenMerchant(stub)
	Trade(stub, { [LINEN] = 20, [SALT] = 4 }, 99800)
	stub.Fire("MERCHANT_CLOSED")
	-- today: new login, a quest reward of 1s, then sell the linen
	stub.clock = NOW
	stub.Fire("PLAYER_ENTERING_WORLD", true, false)
	stub.money = 99900
	stub.Fire("PLAYER_MONEY")
	OpenMerchant(stub)
	Trade(stub, { [SALT] = 4 }, 99900 + 260)
	stub.Fire("MERCHANT_CLOSED")
	stub.Fire("PLAYER_ENTERING_WORLD", false, true) -- /reload keeps the session

	local login = ns.Ledger.Summary("login")
	eq(login.startMoney, 99800); eq(login.net, 260); eq(login.change, 360); eq(login.other, 100)
	local today = ns.Ledger.Summary("today")
	eq(today.startMoney, 99800); eq(today.net, 260)
	eq(#today.days, 2)
	eq(today.days[1].day, "2026-11-09"); eq(today.days[1].net, 260); eq(today.days[1].change, 360)
	eq(today.days[2].day, "2026-11-08"); eq(today.days[2].spent, 200); eq(today.days[2].startMoney, 100000)
	eq(today.days[2].endMoney, 99800); eq(today.days[2].other, 0)
	local all = ns.Ledger.Summary("reset")
	eq(all.startMoney, 100000); eq(all.spent, 200); eq(all.received, 260); eq(all.change, 160); eq(all.other, 100)
	local text = Printed(function() SlashCmdList.CRAFTWISE("ledger today") end)
	has(text, "2026-11-09: start 9g 98s, spent 0c, received 2s 60c, net +2s 60c, money change +3s 60c")
	has(text, "2026-11-08: start 10g, spent 2s, received 0c, net -2s")

	stub.clock = NOW + 60
	SlashCmdList.CRAFTWISE("ledger reset")
	all = ns.Ledger.Summary("reset")
	eq(all.startMoney, 100160); eq(all.net, 0); eq(#all.items, 0)
end)

it("keeps 30 days of entries in CraftWiseMarketDB and leaves the market data alone", function()
	local ns, stub = Load()
	local DAY = 86400
	stub.clock = NOW - 31 * DAY
	ns.Ledger.Record("vbuy", SALT, 1, 50, "x")
	stub.clock = NOW - 29 * DAY
	ns.Ledger.Record("vbuy", SALT, 1, 50, "x")
	stub.clock = NOW
	ns.Ledger.Prune()
	eq(#ns.Ledger.Entries(), 1)
	eq(CraftWiseMarketDB.ledger.entries[1].t, NOW - 29 * DAY)
	assert(CraftWiseMarketDB.items and CraftWiseMarketDB.scope, "market tables still there")
end)

----------------------------------------------------------------------------------- item names in chat (#59)

local SALT_LINK = "|cffffffff|Hitem:4289::::::::20:::::|h[Salt]|h|r"

-- Captures prints until the returned function is called (prints may come after an event).
local function Capture()
	local lines, orig = {}, print
	print = function(s) lines[#lines + 1] = tostring(s) end
	return function()
		print = orig
		return (table.concat(lines, "\n"):gsub("|TInterface\\MoneyFrame\\UI%-(%a)%a*Icon:[^|]*|t", function(u) return u:lower() end))
	end
end

local function Requests(stub)
	local asked = {}
	C_Item.RequestLoadItemDataByID = function(id) asked[#asked + 1] = id end
	return asked
end

it("#59: an entry keeps the item's name and link from record time; the ledger prints the link", function()
	local ns, stub = Load()
	stub.items[SALT].link = SALT_LINK
	ns.Ledger.Record("vbuy", SALT, 3, 150, "Tharynn Bouden")
	local e = ns.Ledger.Entries()[1]
	eq(e.n, "Salt"); eq(e.l, SALT_LINK)
	local asked = Requests(stub)
	local stop = Capture()
	SlashCmdList.CRAFTWISE("ledger login")
	local text = stop()
	has(text, SALT_LINK .. ": bought 3 for")
	eq(#asked, 0, "nothing requested when the client has the item")
end)

it("#59: a stored name is printed at once when the item has left the client's cache", function()
	local ns, stub = Load()
	ns.Ledger.Record("vbuy", SALT, 3, 150, "x") -- stub link is no chat link: only the name is kept
	eq(ns.Ledger.Entries()[1].l, nil)
	stub.items[SALT] = nil
	local asked = Requests(stub)
	local stop = Capture()
	SlashCmdList.CRAFTWISE("ledger login")
	local text = stop()
	has(text, "  Salt: bought 3 for")
	eq(#asked, 0)
	assert(not text:find("item 4289", 1, true), text)
end)

it("#59: an uncached item without a stored name is requested; the ledger prints once it arrives", function()
	local ns, stub = Load()
	local GREY = 15003
	stub.items[GREY] = nil
	ns.Ledger.Record("vsell", GREY, 1, 20, "x")
	eq(ns.Ledger.Entries()[1].n, nil)
	local asked = Requests(stub)
	local stop = Capture()
	SlashCmdList.CRAFTWISE("ledger login")
	eq(stop(), "", "nothing printed while the item loads")
	eq(asked[1], GREY)
	stop = Capture()
	stub.items[GREY] = { name = "Grey Thing", link = "|cff9d9d9d|Hitem:15003::::::::20:::::|h[Grey Thing]|h|r" }
	stub.Fire("ITEM_DATA_LOAD_RESULT", GREY, true)
	stub.RunTimers() -- the timeout was cancelled: no second print
	local text = stop()
	has(text, "|h[Grey Thing]|h|r: sold 1 for 20c")
	assert(not text:find("item 15003", 1, true), text)
	local _, n = text:gsub("Ledger, since login", "")
	eq(n, 1, "printed once")
	eq(ns.Ledger.Entries()[1].n, "Grey Thing", "the name is kept for the next print")
end)

it("#59: an item that never arrives prints as item <id> after the timeout; a failed load ends the wait", function()
	local ns, stub = Load()
	stub.items[15003], stub.items[SALT] = nil, nil
	ns.Ledger.Record("vsell", 15003, 1, 20, "x")
	Requests(stub)
	local stop = Capture()
	SlashCmdList.CRAFTWISE("ledger login")
	stub.RunTimers()
	has(stop(), "item 15003: sold 1 for 20c")

	ns.Ledger.Record("vbuy", SALT, 1, 50, "x")
	stop = Capture()
	SlashCmdList.CRAFTWISE("ledger login")
	stub.Fire("ITEM_DATA_LOAD_RESULT", 15003, false)
	eq(stop(), "", "still waiting for Salt")
	stop = Capture()
	stub.Fire("ITEM_DATA_LOAD_RESULT", SALT, false)
	local text = stop()
	has(text, "item 4289: bought 1"); has(text, "item 15003: sold 1")
end)

it("#123: at logout the ledger uses the money last seen; a new day doesn't start at 0", function()
	local ns, stub = Load() -- 100000 on entering the world
	stub.money = 90000
	stub.Fire("PLAYER_MONEY")
	stub.clock = NOW + 86400 -- past midnight, no money change since
	stub.money = 0
	stub.Fire("PLAYER_LOGOUT")
	local today = ns.Ledger.Summary("today")
	eq(today.money, 90000); eq(today.startMoney, 90000); eq(today.change, 0)
	local c = CraftWiseMarketDB.ledger.chars["PvP-Veli"]
	eq(c.days[os.date("%Y-%m-%d", NOW + 86400)], 90000)
	local days = ns.Ledger.Days()
	eq(days[1].endMoney, 90000); eq(days[2].startMoney, 100000); eq(days[2].change, -10000)
	eq(ns.Ledger.Summary("login").money, 90000)
end)
