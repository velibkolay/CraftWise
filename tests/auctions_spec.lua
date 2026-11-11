-- Issue #81: auction tracker (posts, owned list, sold/expired messages, inferred outcomes, mail
-- settlement into the ledger with a cut sample, snapshot section, /craftwise auctions).
local NOW = os.time({ year = 2026, month = 11, day = 11, hour = 18 })
local HORDE, BOOTY = "PvP|H", "PvP|N:BootyBay"
local LEATHER, HIDE, PANTS, CLOAK = 2318, 783, 7280, 15000

local function Link(id, name)
	return ("|cffffffff|Hitem:%d::::::::20:::::::::|h[%s]|h|r"):format(id, name)
end

local function Load()
	local ns, stub = LoadAddon()
	stub.clock = NOW
	time = function(t)
		if t then return os.time(t) end
		return stub.clock
	end
	stub.names.player = "Veli"
	stub.surnames.player = "Tanner"
	stub.items[LEATHER] = { name = "Light Leather", stack = 200 }
	stub.items[HIDE] = { name = "Light Hide", stack = 200 }
	stub.items[PANTS] = { name = "Rugged Leather Pants", stack = 1 }
	stub.items[CLOAK] = { name = "Bandit Cloak", stack = 1 }
	stub.deposit = 100
	stub.money = 50000
	-- Client strings as the English client has them (the code builds every pattern from these).
	ERR_AUCTION_SOLD_S = "A buyer has been found for your auction of %s."
	ERR_AUCTION_EXPIRED_S = "Your auction of %s has expired."
	AUCTION_EXPIRED_MAIL_SUBJECT = "Auction expired: %s"
	AUCTION_REMOVED_MAIL_SUBJECT = "Auction cancelled: %s"
	AUCTION_DURATION_ONE, AUCTION_DURATION_TWO, AUCTION_DURATION_THREE = "12 Hours", "24 Hours", "48 Hours"
	stub.bagCount = {}
	C_Item.GetItemCount = function(id) return stub.bagCount[id] or 0 end
	function GetInboxItem(i, a)
		local item = stub.inbox[i] and stub.inbox[i].items and stub.inbox[i].items[a]
		if item then return "name", item[1], nil, item[2] end
	end
	stub.Fire("PLAYER_LOGIN")
	stub.Fire("PLAYER_ENTERING_WORLD", true, false)
	return ns, stub
end

local function AtHouse(stub, zone)
	stub.zone, stub.subzone = zone or "Orgrimmar", ""
	stub.Fire("AUCTION_HOUSE_SHOW")
end

local nextID = 500
-- Posts through the hooked client call and lets the client confirm it.
local function Post(stub, itemID, q, unit, opts)
	opts = opts or {}
	local loc = { itemID = itemID, link = Link(itemID, stub.items[itemID].name) }
	if opts.item then
		C_AuctionHouse.PostItem(loc, opts.dur or 3, q, opts.bid, unit)
	else
		C_AuctionHouse.PostCommodity(loc, opts.dur or 3, q, unit)
	end
	local ids = {}
	for _ = 1, opts.created or 1 do
		nextID = nextID + 1
		ids[#ids + 1] = nextID
		stub.Fire("AUCTION_HOUSE_AUCTION_CREATED", nextID)
	end
	return ids[1], ids
end

local function Recs(ns)
	return ns.Auctions.List()
end

local function Find(ns, test)
	for _, rec in ipairs(Recs(ns)) do
		if test(rec) then return rec end
	end
end

local function Sold(stub, name, auctionID)
	stub.Fire("AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION", Enum.AuctionHouseNotification.AuctionSold, name, auctionID)
end

local function Printed(fn)
	local lines = {}
	local orig = print
	print = function(s) lines[#lines + 1] = tostring(s) end
	local ok, err = pcall(fn)
	print = orig
	assert(ok, err)
	return table.concat(lines, "\n")
end

it("records a post only when the client confirms it, with price, deposit, duration and house", function()
	local ns, stub = Load()
	AtHouse(stub)
	C_AuctionHouse.PostCommodity({ itemID = LEATHER }, 3, 20, 150)
	eq(#Recs(ns), 0, "nothing before AUCTION_HOUSE_AUCTION_CREATED")
	stub.Fire("AUCTION_HOUSE_POST_ERROR")
	stub.Fire("AUCTION_HOUSE_AUCTION_CREATED", 1)
	eq(#Recs(ns), 0, "a failed post records nothing")
	local id = Post(stub, LEATHER, 20, 150)
	local rec = Recs(ns)[1]
	eq(rec.id, id); eq(rec.i, LEATHER); eq(rec.q, 20); eq(rec.unit, 150); eq(rec.kind, "commodity")
	eq(rec.dep, 100); eq(rec.h, HORDE); eq(rec.st, "active"); eq(rec.t, NOW)
	eq(rec.durText, "48 Hours"); eq(rec.exp, NOW + 48 * 3600)
	eq(ns.Auctions.NameOf(rec), "Light Leather")
	-- Needs a confirmation: PostItem, then ConfirmPostItem with the same details.
	local loc = { itemID = CLOAK, link = Link(CLOAK, "Bandit Cloak of the Monkey") }
	C_AuctionHouse.PostItem(loc, 1, 1, 5000, 9000)
	C_AuctionHouse.ConfirmPostItem(loc, 1, 1, 5000, 9000)
	stub.Fire("AUCTION_HOUSE_AUCTION_CREATED", 77)
	local cloak = Recs(ns)[2]
	eq(cloak.bid, 5000); eq(cloak.unit, 9000); eq(cloak.kind, "item"); eq(cloak.exp, NOW + 12 * 3600)
	eq(ns.Auctions.NameOf(cloak), "Bandit Cloak of the Monkey", "name from the link keeps the suffix")
	eq(#Recs(ns), 2, "one created event, one auction")
end)

it("a multisell of a non-stacking item gives one auction per item", function()
	local ns, stub = Load()
	AtHouse(stub)
	Post(stub, PANTS, 3, 4000, { item = true, created = 3 })
	eq(#Recs(ns), 3)
	for _, rec in ipairs(Recs(ns)) do
		eq(rec.q, 1); eq(rec.unit, 4000); eq(rec.postSize, 3); eq(rec.dep, nil)
	end
	stub.Fire("AUCTION_HOUSE_AUCTION_CREATED", 999)
	eq(#Recs(ns), 3, "the post is used up")
end)

it("duration hours only from an English client's text; other clients wait for the owned list", function()
	local ns, stub = Load()
	AtHouse(stub)
	stub.locale = "deDE"
	AUCTION_DURATION_THREE = "48 Stunden"
	Post(stub, LEATHER, 5, 150)
	eq(Recs(ns)[1].exp, nil)
	eq(Recs(ns)[1].durText, "48 Stunden")
end)

it("owned list: expiry from time left, status sold, adoption, untracked auctions, commodity units bought", function()
	local ns, stub = Load()
	AtHouse(stub)
	local id = Post(stub, LEATHER, 20, 150)
	-- A post the client never named (no created event for it is simulated by clearing the ID).
	local hide = Post(stub, HIDE, 10, 300)
	Find(ns, function(r) return r.id == hide end).id = nil
	stub.clock = NOW + 600
	stub.owned = {
		{ auctionID = id, itemKey = { itemID = LEATHER }, quantity = 15, status = 0, timeLeftSeconds = 3600 },
		{ auctionID = 900, itemKey = { itemID = HIDE }, quantity = 10, status = 0, timeLeftSeconds = 7200 },
		{ auctionID = 901, itemKey = { itemID = PANTS }, quantity = 1, status = 1, buyoutAmount = 4000, itemLink = Link(PANTS, "Rugged Leather Pants") },
	}
	stub.Fire("OWNED_AUCTIONS_UPDATED")
	local leather = Find(ns, function(r) return r.id == id end)
	eq(leather.q, 15); eq(leather.st, "active"); eq(leather.exp, NOW + 600 + 3600)
	local part = Find(ns, function(r) return r.i == LEATHER and r.st == "sold" end)
	eq(part.q, 5, "5 units bought from the commodity auction"); eq(part.unit, 150); eq(part.soldVia, "owned list (quantity dropped)")
	eq(Find(ns, function(r) return r.i == HIDE end).id, 900, "the unnamed post is adopted")
	local pants = Find(ns, function(r) return r.id == 901 end)
	eq(pants.untracked, true); eq(pants.st, "sold"); eq(pants.ownedBuyout, 4000); eq(pants.h, HORDE)
	local expected, why = ns.Auctions.Expected(pants)
	eq(expected, nil); eq(why, "price not recorded (listed before tracking)")
	eq(#Recs(ns), 4)
	-- The same list again changes nothing.
	stub.Fire("OWNED_AUCTIONS_UPDATED")
	eq(#Recs(ns), 4)
end)

it("sold message: marks the auction, expected payout after the confirmed cut", function()
	local ns, stub = Load()
	AtHouse(stub)
	Post(stub, LEATHER, 20, 150)
	stub.clock = NOW + 300
	Sold(stub, "Light Leather")
	local rec = Recs(ns)[1]
	eq(rec.st, "sold"); eq(rec.soldT, NOW + 300); eq(rec.soldVia, "message")
	eq(rec.qtyUnknown, true, "a commodity message doesn't say how many units")
	eq(ns.Auctions.Expected(rec), nil)
	-- A buyout-only item: 9000 - 5% = 8550.
	local id = Post(stub, PANTS, 1, 9000, { item = true })
	Sold(stub, "Rugged Leather Pants", id)
	local pants = Find(ns, function(r) return r.id == id end)
	local expected, note, price = ns.Auctions.Expected(pants)
	eq(expected, 8550); eq(price, 9000); eq(note, "5% cut (confirmed)")
	eq(pants.uncertain, nil)
end)

it("sold message for one of two auctions of an item: oldest open one, flagged uncertain", function()
	local ns, stub = Load()
	AtHouse(stub)
	local first = Post(stub, PANTS, 1, 4000, { item = true })
	stub.clock = NOW + 60
	local second = Post(stub, PANTS, 1, 3800, { item = true })
	Sold(stub, "Rugged Leather Pants")
	local a = Find(ns, function(r) return r.id == first end)
	local b = Find(ns, function(r) return r.id == second end)
	eq(a.st, "sold"); eq(a.uncertain, true); eq(a.candidates, 2); eq(b.st, "active")
	local row = ns.Auctions.Row(a)
	eq(row.uncertain, "matched by name among 2 auctions of this item")
	-- The next message takes the other one, now the only candidate.
	stub.now = stub.now + 10
	Sold(stub, "Rugged Leather Pants")
	eq(b.st, "sold"); eq(b.uncertain, nil)
end)

it("sold message from the chat text built from ERR_AUCTION_SOLD_S; event and chat count once", function()
	local ns, stub = Load()
	AtHouse(stub)
	Post(stub, PANTS, 1, 4000, { item = true })
	Post(stub, PANTS, 1, 4000, { item = true })
	Sold(stub, "Rugged Leather Pants")
	stub.Fire("CHAT_MSG_SYSTEM", "A buyer has been found for your auction of Rugged Leather Pants.")
	local sold = 0
	for _, r in ipairs(Recs(ns)) do if r.st == "sold" then sold = sold + 1 end end
	eq(sold, 1, "the same sale from two sources")
	-- Chat alone (a client where only the system message comes).
	stub.now = stub.now + 10
	stub.Fire("CHAT_MSG_SYSTEM", "A buyer has been found for your auction of Rugged Leather Pants.")
	sold = 0
	for _, r in ipairs(Recs(ns)) do if r.st == "sold" then sold = sold + 1 end end
	eq(sold, 2)
	-- Text with pattern characters in the item name.
	stub.items[50] = { name = "Elixir (Minor)", stack = 20 }
	Post(stub, 50, 1, 100, { item = true })
	stub.Fire("CHAT_MSG_SYSTEM", "A buyer has been found for your auction of Elixir (Minor).")
	eq(Find(ns, function(r) return r.i == 50 end).st, "sold")
end)

it("a later source naming the auction corrects a match made by name", function()
	local ns, stub = Load()
	AtHouse(stub)
	local first = Post(stub, PANTS, 1, 4000, { item = true })
	stub.clock = NOW + 60
	local second = Post(stub, PANTS, 1, 3800, { item = true })
	stub.Fire("CHAT_MSG_SYSTEM", "A buyer has been found for your auction of Rugged Leather Pants.")
	eq(Find(ns, function(r) return r.id == first end).st, "sold")
	Sold(stub, "Rugged Leather Pants", second)
	local a, b = Find(ns, function(r) return r.id == first end), Find(ns, function(r) return r.id == second end)
	eq(a.st, "active"); eq(a.uncertain, nil); eq(a.soldT, nil)
	eq(b.st, "sold"); eq(b.uncertain, nil)
end)

it("expected payout: cut unverified at a neutral house, unknown for bid and buyout", function()
	local ns, stub = Load()
	AtHouse(stub, "Booty Bay")
	local id = Post(stub, PANTS, 1, 9000, { item = true })
	Sold(stub, "Rugged Leather Pants", id)
	local rec = Find(ns, function(r) return r.id == id end)
	eq(rec.h, BOOTY)
	local expected, note, price = ns.Auctions.Expected(rec)
	eq(expected, nil); eq(note, "cut unverified"); eq(price, 9000)
	AtHouse(stub)
	local bid = Post(stub, PANTS, 1, 9000, { item = true, bid = 6000 })
	Sold(stub, "Rugged Leather Pants", bid)
	local expected2, why = ns.Auctions.Expected(Find(ns, function(r) return r.id == bid end))
	eq(expected2, nil); eq(why, "bid and buyout: sale price unknown")
end)

it("inferred: missing from a full owned list at the same house is sold or cancelled (uncertain)", function()
	local ns, stub = Load()
	AtHouse(stub)
	local gone = Post(stub, LEATHER, 20, 150)
	local listed = Post(stub, HIDE, 10, 300)
	AtHouse(stub, "Booty Bay")
	local elsewhere = Post(stub, PANTS, 1, 9000, { item = true })
	AtHouse(stub)
	-- A partial list proves nothing.
	stub.clock = NOW + 600
	stub.owned = { { auctionID = listed, itemKey = { itemID = HIDE }, quantity = 10, status = 0, timeLeftSeconds = 3600 } }
	stub.ownedFull = false
	stub.Fire("OWNED_AUCTIONS_UPDATED")
	eq(Find(ns, function(r) return r.id == gone end).st, "active")
	stub.ownedFull = true
	stub.Fire("OWNED_AUCTIONS_UPDATED")
	local g = Find(ns, function(r) return r.id == gone end)
	eq(g.st, "gone"); eq(g.why, "missing from the owned list before its expiry, no message seen")
	eq(Find(ns, function(r) return r.id == listed end).st, "active")
	eq(Find(ns, function(r) return r.id == elsewhere end).st, "active", "another house's list says nothing about it")
	-- Back in the list (the client's list was stale): active again.
	stub.owned[2] = { auctionID = gone, itemKey = { itemID = LEATHER }, quantity = 20, status = 0, timeLeftSeconds = 100 }
	stub.Fire("OWNED_AUCTIONS_UPDATED")
	eq(g.st, "active")
	-- Missing after its time ran out: expired, inferred.
	stub.owned[2] = nil
	stub.clock = NOW + 600 + 200
	stub.Fire("OWNED_AUCTIONS_UPDATED")
	eq(g.st, "expired"); eq(g.why, "missing from the owned list after its expiry, no message seen")
	-- A sold message turns an uncertain one into sold.
	local h = Find(ns, function(r) return r.id == listed end)
	stub.owned = {}
	stub.Fire("OWNED_AUCTIONS_UPDATED")
	eq(h.st, "gone")
	Sold(stub, "Light Hide")
	eq(h.st, "sold")
end)

it("a post newer than a minute isn't inferred from an older list", function()
	local ns, stub = Load()
	AtHouse(stub)
	local id = Post(stub, LEATHER, 20, 150)
	stub.owned = {}
	stub.clock = NOW + 30
	stub.Fire("OWNED_AUCTIONS_UPDATED")
	eq(Find(ns, function(r) return r.id == id end).st, "active")
end)

it("expired: notification, chat text and the expired event; cancelled by AUCTION_CANCELED", function()
	local ns, stub = Load()
	AtHouse(stub)
	local a = Post(stub, PANTS, 1, 9000, { item = true })
	local b = Post(stub, LEATHER, 5, 150)
	local c = Post(stub, HIDE, 5, 300)
	local d = Post(stub, CLOAK, 1, 9000, { item = true })
	stub.Fire("AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION", Enum.AuctionHouseNotification.AuctionExpired, "Rugged Leather Pants", nil)
	eq(Find(ns, function(r) return r.id == a end).st, "expired")
	stub.Fire("CHAT_MSG_SYSTEM", "Your auction of Light Leather has expired.")
	eq(Find(ns, function(r) return r.id == b end).st, "expired")
	stub.Fire("AUCTION_HOUSE_AUCTIONS_EXPIRED", c)
	eq(Find(ns, function(r) return r.id == c end).st, "expired")
	stub.Fire("AUCTION_CANCELED", d)
	local rec = Find(ns, function(r) return r.id == d end)
	eq(rec.st, "cancelled")
	eq(ns.Auctions.Row(rec).statusText, "cancelled, returned via mail")
end)

it("sale mail: settles on the money, writes an ahsell ledger entry and a cut sample", function()
	local ns, stub = Load()
	AtHouse(stub)
	local id = Post(stub, PANTS, 1, 9000, { item = true })
	Sold(stub, "Rugged Leather Pants", id)
	stub.Fire("AUCTION_HOUSE_CLOSED")
	stub.inbox = { { subject = "Auction successful: Rugged Leather Pants", money = 8650,
		invoice = { type = "seller", itemName = "Rugged Leather Pants", buyer = "Someone Else", bid = 9000, buyout = 9000, deposit = 100, consignment = 450, count = 1 } } }
	TakeInboxMoney(1)
	eq(Find(ns, function(r) return r.id == id end).st, "sold", "nothing until the money is here")
	stub.clock = NOW + 4000
	stub.money = stub.money + 8650
	stub.Fire("PLAYER_MONEY")
	local rec = Find(ns, function(r) return r.id == id end)
	eq(rec.st, "settled"); eq(rec.received, 8650); eq(rec.sale, 9000); eq(rec.cut, 450); eq(rec.saleDeposit, 100)
	eq(rec.settledT, NOW + 4000)
	local e = ns.Ledger.Entries()[#ns.Ledger.Entries()]
	eq(e.k, "ahsell"); eq(e.i, PANTS); eq(e.q, 1); eq(e.m, 8650); eq(e.w, HORDE)
	local s = CraftWiseMarketDB.cutSamples[#CraftWiseMarketDB.cutSamples]
	eq(s.house, HORDE); eq(s.listed, 9000); eq(s.received, 8650); eq(s.cut, 450); eq(s.deposit, 100); eq(s.q, 1)
	-- Nothing about the buyer is kept.
	local function Holds(t, text, seen)
		seen = seen or {}
		if seen[t] then return false end
		seen[t] = true
		for k, v in pairs(t) do
			if v == text or k == text or (type(v) == "table" and Holds(v, text, seen)) then return true end
		end
		return false
	end
	eq(Holds(CraftWiseMarketDB, "Someone Else"), false)
	-- The ledger counts it as received.
	eq(ns.Ledger.Summary("reset").received, 8650)
end)

it("sale mail of a commodity part: splits the auction; offline sale settles an active one", function()
	local ns, stub = Load()
	AtHouse(stub)
	local id = Post(stub, LEATHER, 20, 150)
	local hide = Post(stub, HIDE, 4, 300)
	Sold(stub, "Light Leather")
	stub.inbox = {
		{ money = 712, invoice = { type = "seller", itemName = "Light Leather", bid = 750, deposit = 0, consignment = 38, count = 5 } },
		{ money = 1140, invoice = { type = "seller", itemName = "Light Hide", bid = 1200, deposit = 0, consignment = 60, count = 4 } },
		{ money = 500, invoice = { type = "seller_temp_invoice", itemName = "Light Hide", bid = 500, count = 1 } },
	}
	TakeInboxMoney(1)
	AutoLootMailItem(2)
	TakeInboxMoney(3) -- a pending-funds invoice: nothing to settle
	stub.money = stub.money + 712
	stub.Fire("PLAYER_MONEY")
	stub.money = stub.money + 1140
	stub.Fire("PLAYER_MONEY")
	local rest = Find(ns, function(r) return r.id == id end)
	eq(rest.q, 15); eq(rest.st, "sold"); eq(rest.qtyUnknown, true)
	local part = Find(ns, function(r) return r.i == LEATHER and r.st == "settled" end)
	eq(part.q, 5); eq(part.received, 712)
	local h = Find(ns, function(r) return r.id == hide end)
	eq(h.st, "settled"); eq(h.soldVia, "mail", "sold while offline, no message")
	eq(#CraftWiseMarketDB.cutSamples, 2)
	local kinds = {}
	for _, e in ipairs(ns.Ledger.Entries()) do kinds[#kinds + 1] = e.k .. " " .. e.i .. " x" .. e.q .. " " .. e.m end
	eq(table.concat(kinds, " | "), "ahsell 2318 x5 712 | ahsell 783 x4 1140")
end)

it("sale mail for an item with no tracked auction is kept by name, without ledger entry or cut sample", function()
	local ns, stub = Load()
	stub.inbox = { { money = 950, invoice = { type = "seller", itemName = "Mystery Item", bid = 1000, deposit = 0, consignment = 50, count = 1 } } }
	TakeInboxMoney(1)
	stub.money = stub.money + 950
	stub.Fire("PLAYER_MONEY")
	local rec = Recs(ns)[1]
	eq(rec.st, "settled"); eq(rec.n, "Mystery Item"); eq(rec.untracked, true)
	eq(#ns.Ledger.Entries(), 0)
	eq(#CraftWiseMarketDB.cutSamples, 0)
end)

it("money that never arrives settles nothing (take failed)", function()
	local ns, stub = Load()
	AtHouse(stub)
	local id = Post(stub, PANTS, 1, 9000, { item = true })
	Sold(stub, "Rugged Leather Pants", id)
	stub.inbox = { { money = 8650, invoice = { type = "seller", itemName = "Rugged Leather Pants", bid = 9000, deposit = 100, consignment = 450, count = 1 } } }
	TakeInboxMoney(1)
	stub.now = stub.now + 60
	stub.money = stub.money + 8650 -- money from somewhere else, much later
	stub.Fire("PLAYER_MONEY")
	eq(Find(ns, function(r) return r.id == id end).st, "sold")
end)

it("returned item: expired or cancelled mail settles when the item is in the bags", function()
	local ns, stub = Load()
	AtHouse(stub)
	local id = Post(stub, PANTS, 1, 9000, { item = true })
	local cloak = Post(stub, CLOAK, 1, 9000, { item = true })
	stub.Fire("AUCTION_HOUSE_AUCTIONS_EXPIRED", id)
	stub.Fire("AUCTION_CANCELED", cloak)
	stub.inbox = {
		{ subject = "Auction expired: Rugged Leather Pants", items = { { PANTS, 1 } } },
		{ subject = "Auction cancelled: Bandit Cloak", items = { { CLOAK, 1 } } },
		{ subject = "Hello from a friend", items = { { PANTS, 1 } } },
	}
	TakeInboxItem(1, 1)
	AutoLootMailItem(2)
	TakeInboxItem(3, 1)
	stub.Fire("BAG_UPDATE_DELAYED")
	eq(Find(ns, function(r) return r.id == id end).st, "expired", "not in the bags yet")
	stub.bagCount[PANTS], stub.bagCount[CLOAK] = 1, 1
	stub.Fire("BAG_UPDATE_DELAYED")
	local p = Find(ns, function(r) return r.id == id end)
	eq(p.st, "returned"); eq(p.returnKind, "expired")
	local c = Find(ns, function(r) return r.id == cloak end)
	eq(c.st, "returned"); eq(c.returnKind, "cancelled")
	eq(#ns.Ledger.Entries(), 0, "a returned item is no trade")
end)

it("snapshot section and /craftwise auctions: listed, sold with expected total, returning", function()
	local ns, stub = Load()
	AtHouse(stub)
	Post(stub, LEATHER, 20, 150)
	local p1 = Post(stub, PANTS, 1, 9000, { item = true })
	local p2 = Post(stub, PANTS, 1, 8000, { item = true })
	local c = Post(stub, CLOAK, 1, 9000, { item = true, bid = 5000 })
	local h = Post(stub, HIDE, 5, 300)
	Sold(stub, "Rugged Leather Pants", p1)
	Sold(stub, "Rugged Leather Pants", p2)
	Sold(stub, "Bandit Cloak", c)
	stub.Fire("AUCTION_HOUSE_AUCTIONS_EXPIRED", h)
	stub.Fire("PLAYER_LOGOUT")
	local snap = CraftWiseDB.snapshots["PvP-Veli Tanner"]
	eq((snap.skipped or {}).auctions, nil); eq((snap.errors or {}).auctions, nil)
	local s = snap.auctions
	eq(#s.active, 1); eq(#s.sold, 3); eq(#s.returning, 1); eq(#s.uncertain, 0)
	eq(s.expectedTotal, 8550 + 7600); eq(s.expectedMissing, 1)
	eq(s.active[1].name, "Light Leather"); eq(s.active[1].houseLabel, "Horde AH"); eq(s.active[1].unitBuyout, 150)
	eq(s.returning[1].statusText, "expired, returned via mail")
	local out = Printed(function() SlashCmdList.CRAFTWISE("auctions") end)
	assert(out:find("1 listed, 3 sold awaiting mail, 1 returning by mail, 0 uncertain", 1, true), out)
	assert(out:find("on its way: 1|TInterface", 1, true) and out:find("plus 1 sale with unknown payout", 1, true), out)
	assert(out:find("expected unknown: bid and buyout: sale price unknown", 1, true), out)
end)

it("a character without auctions has an empty section; prune drops finished records after 30 days", function()
	local ns, stub = Load()
	stub.Fire("PLAYER_LOGOUT")
	local s = CraftWiseDB.snapshots["PvP-Veli Tanner"].auctions
	eq(#s.active, 0); eq(s.expectedTotal, 0)
	AtHouse(stub)
	local id = Post(stub, PANTS, 1, 9000, { item = true })
	Post(stub, LEATHER, 5, 150)
	stub.Fire("AUCTION_CANCELED", id)
	ns.Auctions.Prune(NOW + 31 * 86400)
	eq(#Recs(ns), 1, "the cancelled one is dropped")
	ns.Auctions.Prune(NOW + 2 * 86400 + 31 * 86400)
	eq(#Recs(ns), 0, "listed one dropped 30 days after its expiry")
end)

it("auctions are kept per character", function()
	local ns, stub = Load()
	AtHouse(stub)
	Post(stub, LEATHER, 5, 150)
	stub.surnames.player = "Smith"
	eq(#ns.Auctions.List(), 0)
	eq(#ns.Auctions.List("PvP-Veli Tanner"), 1)
end)
