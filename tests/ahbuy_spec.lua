-- Buying at the AH from CraftWise (#315, part 1): the plan, the search, one purchase per click, the checks
-- right before a call, the commodity price guard, the confirm limit, and the rule that the three buy calls
-- live in one file and are reached from clicks only.
local NOW = 1794000000
local DAY = 86400
local CLOTH, SWORD = 100, 300

-- A fake auction house in the client's shape. ah.calls records every call that spends gold.
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

-- Commodity rows: { unit, qty } each; items: { buyout, qty, id }.
local function Commodity(stub, rows)
	local list = {}
	for i, r in ipairs(rows) do
		list[i] = { itemID = CLOTH, quantity = r[2], unitPrice = r[1], auctionID = 1000 + i, owners = {}, containsOwnerItem = r.own or false }
	end
	stub.commodity[CLOTH] = { rows = list, total = 99 }
end
local function ItemAuctions(stub, rows)
	local list = {}
	for i, r in ipairs(rows) do
		list[i] = { itemKey = { itemID = SWORD }, auctionID = r[3] or 500 + i, quantity = r[2] or 1, buyoutAmount = r[1], containsOwnerItem = r.own or false }
	end
	stub.itemSearch[SWORD] = { rows = list }
end

local function PickAndSearch(ns, stub, line, kind)
	ns.AHBuy.Pick(line)
	local ok = ns.AHBuy.Search()
	assert(ok, "the search went out")
	if kind == "commodity" then
		stub.Fire("COMMODITY_SEARCH_RESULTS_UPDATED", line.itemID)
	else
		stub.Fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = line.itemID })
	end
end

local FLIP = { kind = "flip", itemID = CLOTH, need = 12, maxUnit = 99, sell = 100 }

----------------------------------------------------------------------------------------------- plan

it("Plan: commodities take the cheapest units up to the need and the max price (equal is allowed)", function()
	local ns = Setup()
	local P = ns.AHBuy.Plan
	local rows = { { unit = 40, qty = 5 }, { unit = 90, qty = 10 }, { unit = 99, qty = 4 }, { unit = 100, qty = 50 } }
	local plan = P(rows, true, 12, 99)
	eq(plan.units, 12); eq(plan.total, 40 * 5 + 90 * 7); eq(plan.unitMax, 90); eq(plan.partial, false)
	plan = P(rows, true, 30, 99)
	eq(plan.units, 19); eq(plan.total, 40 * 5 + 90 * 10 + 99 * 4); eq(plan.partial, true, "only 19 are at or below 99")
	eq(plan.unitMax, 99, "a unit at the max price is allowed")
	eq(P(rows, true, 5, 39), nil, "nothing at or below the max price")
	plan = P(rows, true, 3, nil)
	eq(plan.units, 3); eq(plan.total, 120, "no max price: the cheapest units")
	eq(P({ { unit = 5, qty = 3, own = true } }, true, 3, 99), nil, "own auctions are skipped")
	eq(P({}, true, 3, 99), nil)
end)

it("Plan: items are bought one auction per purchase, the cheapest at or below the max price", function()
	local ns = Setup()
	local plan = ns.AHBuy.Plan({ { unit = 700, qty = 1, auctionID = 7, buyout = 700 }, { unit = 900, qty = 1, auctionID = 8, buyout = 900 } }, false, 1, 800)
	eq(plan.auctionID, 7); eq(plan.total, 700); eq(plan.units, 1)
	eq(ns.AHBuy.Plan({ { unit = 900, qty = 1, auctionID = 8, buyout = 900 } }, false, 1, 800), nil)
end)

----------------------------------------------------------------------------------------------- search

it("Search: one query per call, only with the AH open, a picked line and a ready throttle; nothing is queued", function()
	local ns, stub, ah = Setup()
	local AB = ns.AHBuy
	local ok, why = AB.Search()
	eq(ok, false); eq(why, "Pick a line first"); eq(#ah.searches, 0)
	AB.Pick(FLIP)
	stub.throttleReady = false
	ok, why = AB.Search()
	eq(ok, false); assert(why:find("Wait"), why); eq(#ah.searches, 0)
	stub.Fire("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
	eq(#ah.searches, 0, "the ready event does not search by itself")
	stub.throttleReady = true
	eq(AB.Search(), true); eq(#ah.searches, 1); eq(ah.searches[1].key.itemID, CLOTH)
	eq(AB.state.phase, "searching")
	stub.Fire("AUCTION_HOUSE_CLOSED")
	ok, why = AB.Search()
	eq(ok, false); eq(why, "Open the auction house first"); eq(#ah.searches, 1)
end)

it("Search: the kind of result that arrives tells commodity from item when the client has no key info", function()
	local ns, stub = Setup()
	Commodity(stub, { { 40, 5 } })
	PickAndSearch(ns, stub, FLIP, "commodity")
	eq(ns.AHBuy.state.isCommodity, true); eq(ns.AHBuy.state.phase, "ready")
	ItemAuctions(stub, { { 700 } })
	PickAndSearch(ns, stub, { kind = "basket", itemID = SWORD, need = 1 }, "item")
	eq(ns.AHBuy.state.isCommodity, false)
end)

----------------------------------------------------------------------------------------------- buying

it("Buy an item: one PlaceBid per click, the button is off until the result arrives, then the list is old", function()
	local ns, stub, ah = Setup()
	local AB = ns.AHBuy
	ItemAuctions(stub, { { 700, 1, 77 }, { 900, 1, 78 } })
	local line = { kind = "basket", itemID = SWORD, need = 1 }
	PickAndSearch(ns, stub, line, "item")
	local plan = AB.Refresh()
	eq(plan.total, 700)
	local text, enabled = AB.Describe(plan, nil, AB.state.phase, AB.state.busy, GetMoney())
	eq(text, "Buy 1 for " .. ns.FormatMoney(700, true)); eq(enabled, true)
	eq(AB.Click(), true)
	eq(table.concat(ah.calls, ","), "bid:77:700")
	text, enabled = AB.Describe(AB.Refresh(), nil, AB.state.phase, AB.state.busy, GetMoney())
	eq(enabled, false, "disabled until the result")
	local again, why = AB.Click()
	eq(again, false); eq(why, "Wait for the purchase"); eq(#ah.calls, 1, "a second click does not buy")
	stub.Fire("AUCTION_HOUSE_PURCHASE_COMPLETED", 77)
	eq(AB.state.busy, false); eq(AB.state.phase, "stale")
	eq(AB.Click(), false); eq(#ah.calls, 1, "after a purchase the results are old: search again first")
	AB.Search()
	stub.Fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = SWORD })
	eq(AB.Click(), true); eq(#ah.calls, 2)
end)

it("Buy: an error frees the button and is not retried", function()
	local ns, stub, ah = Setup()
	local AB = ns.AHBuy
	ItemAuctions(stub, { { 700, 1, 77 } })
	PickAndSearch(ns, stub, { kind = "basket", itemID = SWORD, need = 1 }, "item")
	AB.Refresh()
	AB.Click()
	stub.Fire("AUCTION_HOUSE_SHOW_ERROR", 1)
	eq(AB.state.busy, false); assert(AB.state.message:find("Search again"), AB.state.message)
	eq(#ah.calls, 1, "nothing retried")
	stub.Fire("AUCTION_HOUSE_SHOW_ERROR", 1)
	eq(#ah.calls, 1)
end)

it("Buy: error 10 first, then the completion for the same auction still counts as bought (#340)", function()
	local ns, stub, ah = Setup()
	local AB = ns.AHBuy
	ItemAuctions(stub, { { 700, 1, 77 }, { 800, 1, 78 } })
	PickAndSearch(ns, stub, { kind = "basket", itemID = SWORD, need = 2 }, "item")
	AB.Refresh()
	AB.Click()
	stub.Fire("AUCTION_HOUSE_SHOW_ERROR", 10)
	eq(AB.state.busy, false)
	stub.Fire("AUCTION_HOUSE_PURCHASE_COMPLETED", 78) -- not the shown auction: ignored
	eq(AB.state.bought[78], nil)
	stub.Fire("AUCTION_HOUSE_PURCHASE_COMPLETED", 77)
	eq(AB.state.bought[77], true)
	eq(AB.state.run.units, 1); eq(AB.state.run.total, 700)
	assert(AB.state.message:find("Bought 1", 1, true) and AB.state.message:find("error 10", 1, true), AB.state.message)
	eq(#ah.calls, 1, "nothing retried")
	stub.Fire("AUCTION_HOUSE_PURCHASE_COMPLETED", 77) -- a second event counts nothing more
	eq(AB.state.run.units, 1)
end)

it("Buy: an error with no completion buys nothing and counts nothing", function()
	local ns, stub, ah = Setup()
	local AB = ns.AHBuy
	ItemAuctions(stub, { { 700, 1, 77 } })
	PickAndSearch(ns, stub, { kind = "basket", itemID = SWORD, need = 1 }, "item")
	AB.Refresh()
	AB.Click()
	stub.Fire("AUCTION_HOUSE_SHOW_ERROR", 10)
	stub.Fire("AUCTION_HOUSE_CLOSED")
	stub.Fire("AUCTION_HOUSE_PURCHASE_COMPLETED", 77)
	eq(next(AB.state.bought), nil); eq(AB.state.run, nil)
end)

----------------------------------------------------------------------------------------------- fresh list (#335)

local FLIPSWORD = { kind = "flip", itemID = SWORD, need = 3, maxUnit = 800, sell = 1000 }

it("Fresh list: after a purchase the client's new item list lets the next press buy the next auction, no search in between", function()
	local ns, stub, ah = Setup()
	local AB = ns.AHBuy
	ItemAuctions(stub, { { 700, 1, 77 }, { 720, 1, 78 }, { 740, 1, 79 } })
	PickAndSearch(ns, stub, FLIPSWORD, "item")
	local plan = AB.Refresh()
	eq(plan.more, 2)
	eq((AB.Describe(plan, nil, AB.state.phase, AB.state.busy, GetMoney())), "Buy 1 for " .. ns.FormatMoney(700, true) .. " (2 more under max)")
	eq(AB.Click(), true); eq(table.concat(ah.calls, ","), "bid:77:700")
	stub.Fire("AUCTION_HOUSE_PURCHASE_COMPLETED", 77)
	eq(AB.state.phase, "stale"); eq(AB.Click(), false); eq(#ah.calls, 1, "no list yet: nothing is bought")
	ItemAuctions(stub, { { 720, 1, 78 }, { 740, 1, 79 } })
	stub.Fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = SWORD }, 78)
	eq(AB.state.phase, "ready")
	eq(AB.state.message, "Bought 1 for " .. ns.FormatMoney(700, true))
	plan = AB.Refresh()
	eq(plan.auctionID, 78); eq(plan.more, 1)
	eq(#ah.searches, 1, "no second search")
	eq(AB.Click(), true); eq(ah.calls[2], "bid:78:720")
	stub.Fire("AUCTION_HOUSE_PURCHASE_COMPLETED", 78)
	ItemAuctions(stub, { { 740, 1, 79 } })
	stub.Fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = SWORD })
	plan = AB.Refresh()
	eq((AB.Describe(plan, nil, AB.state.phase, AB.state.busy, GetMoney())), "Buy 1 for " .. ns.FormatMoney(740, true), "the last one: no more")
	eq(AB.Click(), true); eq(ah.calls[3], "bid:79:740")
	stub.Fire("AUCTION_HOUSE_PURCHASE_COMPLETED", 79)
	ItemAuctions(stub, {})
	stub.Fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = SWORD })
	eq(AB.state.message, "Bought 3 for " .. ns.FormatMoney(2160, true))
	local p, why = AB.Refresh()
	eq(p, nil); eq(why, "Nothing is listed at or below the max price")
	eq(AB.Click(), false); eq(#ah.calls, 3); eq(#ah.searches, 1)
end)

it("Fresh list: a list from before the purchase is not fresh; one that arrived during it counts only without the bought auction", function()
	local ns, stub, ah = Setup()
	local AB = ns.AHBuy
	ItemAuctions(stub, { { 700, 1, 77 }, { 720, 1, 78 } })
	PickAndSearch(ns, stub, FLIPSWORD, "item")
	AB.Refresh(); AB.Click()
	-- a list during the purchase that still holds auction 77: the old one
	stub.Fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = SWORD })
	stub.Fire("AUCTION_HOUSE_PURCHASE_COMPLETED", 77)
	eq(AB.state.phase, "stale", "that list still held the bought auction")
	eq(AB.Click(), false); eq(#ah.calls, 1)
	-- a list that came during the purchase and no longer holds the bought auction
	AB.state.bought = {}
	AB.Search(); stub.Fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = SWORD })
	AB.Refresh(); AB.Click()
	eq(#ah.calls, 2)
	ItemAuctions(stub, { { 720, 1, 78 } })
	stub.Fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = SWORD })
	eq(AB.state.phase, "buying", "events never buy and never end the purchase")
	stub.Fire("AUCTION_HOUSE_PURCHASE_COMPLETED", 77)
	eq(AB.state.phase, "ready"); eq(AB.Refresh().auctionID, 78)
	-- another item's list does not make a finished purchase fresh
	AB.Click(); stub.Fire("AUCTION_HOUSE_PURCHASE_COMPLETED", 78)
	eq(AB.state.phase, "stale")
	stub.Fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = CLOTH })
	eq(AB.state.phase, "stale")
	-- a purchase finishing in Blizzard's own window is not ours
	AB.state.phase, AB.state.busy = "buying", true
	AB.state.shown = { auctionID = 78, units = 1, total = 720, itemID = SWORD }
	stub.Fire("AUCTION_HOUSE_PURCHASE_COMPLETED", 999)
	eq(AB.state.phase, "buying")
end)

it("Fresh list: an auction bought this session is skipped even when the list still shows it; a price above the max is refused", function()
	local ns, stub, ah = Setup()
	local AB = ns.AHBuy
	ItemAuctions(stub, { { 700, 1, 77 }, { 720, 1, 78 } })
	PickAndSearch(ns, stub, FLIPSWORD, "item")
	AB.Refresh(); AB.Click()
	stub.Fire("AUCTION_HOUSE_PURCHASE_COMPLETED", 77)
	stub.Fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = SWORD }) -- the server still listed 77
	eq(AB.state.phase, "ready")
	eq(AB.Refresh().auctionID, 78, "77 was bought: skipped")
	-- the next list holds only an auction above his max
	ItemAuctions(stub, { { 900, 1, 90 } })
	stub.Fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = SWORD })
	AB.Refresh()
	local ok = AB.Click()
	eq(ok, false); eq(#ah.calls, 1, "above his max: nothing bought")
	-- a bought id is never sent again, even through Execute
	ItemAuctions(stub, { { 720, 1, 78 } })
	stub.Fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = SWORD })
	AB.Refresh()
	AB.state.bought[78] = true
	ok = AB.Execute({ itemID = SWORD, units = 1, total = 720, unitMax = 720, auctionID = 78, buyout = 720 })
	eq(ok, false); eq(#ah.calls, 1)
	-- closing the AH forgets the run
	stub.Fire("AUCTION_HOUSE_CLOSED")
	eq(next(AB.state.bought), nil); eq(AB.state.run, nil)
end)

it("Fresh list: the buy key takes the same path, one auction per press", function()
	local ns, stub, ah = Setup()
	local AB = ns.AHBuy
	ItemAuctions(stub, { { 700, 1, 77 }, { 720, 1, 78 } })
	PickAndSearch(ns, stub, FLIPSWORD, "item")
	AB.Refresh()
	local K = AB.KeyBuy
	eq(K("down"), true); K("up")
	eq(K("down"), false, "a press while the result is out buys nothing"); K("up")
	stub.Fire("AUCTION_HOUSE_PURCHASE_COMPLETED", 77)
	ItemAuctions(stub, { { 720, 1, 78 } })
	stub.Fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = SWORD })
	AB.Refresh()
	eq(K("down"), true); eq(table.concat(ah.calls, ","), "bid:77:700,bid:78:720")
	eq(K("down"), false); eq(#ah.calls, 2, "held: nothing more")
end)

it("Errors: shown with their number, never retried, and a list after an error is not fresh; a search that errors is freed", function()
	local ns, stub, ah = Setup()
	local AB = ns.AHBuy
	ItemAuctions(stub, { { 700, 1, 77 }, { 720, 1, 78 } })
	PickAndSearch(ns, stub, FLIPSWORD, "item")
	AB.Refresh(); AB.Click()
	stub.Fire("AUCTION_HOUSE_SHOW_ERROR", 5)
	eq(AB.state.phase, "stale"); eq(AB.state.busy, false)
	assert(AB.state.message:find("error 5", 1, true) and AB.state.message:find("Search again", 1, true), AB.state.message)
	stub.Fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = SWORD })
	eq(AB.state.phase, "stale", "after an error the list stays old")
	eq(AB.Click(), false); eq(#ah.calls, 1, "nothing retried"); eq(#ah.searches, 1, "no search by itself")
	-- an error while a search is waiting frees the panel; it does not search again
	AB.Search()
	eq(AB.state.phase, "searching"); eq(#ah.searches, 2)
	stub.Fire("AUCTION_HOUSE_SHOW_ERROR", 12)
	eq(AB.state.phase, "stale"); assert(AB.state.message:find("error 12", 1, true), AB.state.message)
	eq(#ah.searches, 2, "no retry"); eq(#ah.calls, 1)
	-- an error with nothing pending is not ours
	stub.Fire("AUCTION_HOUSE_SHOW_ERROR", 3)
	eq(AB.state.phase, "stale"); assert(AB.state.message:find("error 12", 1, true), AB.state.message)
end)

it("Buy: the auction is read again right before the call: a higher price, a vanished auction, no gold: nothing is bought", function()
	local ns, stub, ah = Setup()
	local AB = ns.AHBuy
	ItemAuctions(stub, { { 700, 1, 77 } })
	local line = { kind = "basket", itemID = SWORD, need = 1, maxUnit = 800 }
	PickAndSearch(ns, stub, line, "item")
	AB.Refresh() -- the button showed 700
	ItemAuctions(stub, { { 790, 1, 77 } }) -- the price moved before the click
	local ok, why = AB.Click()
	eq(ok, false); assert(why:find("price changed"), why); eq(#ah.calls, 0)
	AB.Refresh() -- now it shows 790
	ItemAuctions(stub, { { 790, 1, 99 } }) -- another auction
	ok, why = AB.Click()
	eq(ok, false); assert(why:find("gone or changed"), why); eq(#ah.calls, 0)
	AB.Refresh()
	ItemAuctions(stub, { { 850, 1, 99 } }) -- above the max price too
	ok, why = AB.Click()
	eq(ok, false); eq(#ah.calls, 0)
	ItemAuctions(stub, { { 700, 1, 77 } })
	AB.Refresh()
	stub.money = 100
	ok, why = AB.Click()
	eq(ok, false); eq(why, "Not enough gold"); eq(#ah.calls, 0)
	stub.money = 10000000
	AB.Refresh()
	eq(AB.Click(), true); eq(#ah.calls, 1)
end)

it("Buy a commodity: the first click starts, the quote must not be higher than the button showed, the second click confirms", function()
	local ns, stub, ah = Setup()
	local AB = ns.AHBuy
	Commodity(stub, { { 40, 5 }, { 90, 10 } })
	PickAndSearch(ns, stub, FLIP, "commodity")
	local plan = AB.Refresh()
	eq(plan.units, 12); eq(plan.total, 40 * 5 + 90 * 7)
	eq(AB.Click(), true)
	eq(table.concat(ah.calls, ","), "start:100:12")
	eq(AB.state.busy, true)
	eq(AB.Click(), false); eq(#ah.calls, 1, "no second call while the quote is out")
	stub.Fire("COMMODITY_PRICE_UPDATED", 80, plan.total)
	eq(AB.state.phase, "confirm"); eq(AB.state.busy, false)
	eq(#ah.calls, 1, "the price is never confirmed by itself")
	local text, enabled = AB.Describe(AB.Refresh(), nil, AB.state.phase, AB.state.busy, GetMoney())
	eq(text, "Confirm: buy 12 for " .. ns.FormatMoney(plan.total, true)); eq(enabled, true)
	eq(AB.Click(), true)
	eq(table.concat(ah.calls, ","), "start:100:12,confirm:100:12")
	eq(AB.state.busy, true)
	eq(AB.Click(), false); eq(#ah.calls, 2)
	stub.Fire("COMMODITY_PURCHASE_SUCCEEDED")
	eq(AB.state.busy, false); eq(AB.state.phase, "stale")
end)

it("Buy a commodity: a quote above what the button showed, or above the max price, is cancelled and shown, not confirmed", function()
	local ns, stub, ah = Setup()
	local AB = ns.AHBuy
	Commodity(stub, { { 40, 5 }, { 90, 10 } })
	PickAndSearch(ns, stub, FLIP, "commodity")
	local plan = AB.Refresh()
	AB.Click()
	stub.Fire("COMMODITY_PRICE_UPDATED", 85, plan.total + 5)
	eq(table.concat(ah.calls, ","), "start:100:12,cancel")
	eq(AB.state.phase, "stale"); assert(AB.state.message:find("not bought"), AB.state.message)
	eq(AB.Click(), false); eq(#ah.calls, 2)
	-- the server has no price any more
	AB.Search(); stub.Fire("COMMODITY_SEARCH_RESULTS_UPDATED", CLOTH)
	plan = AB.Refresh()
	AB.Click()
	stub.Fire("COMMODITY_PRICE_UNAVAILABLE")
	eq(ah.calls[#ah.calls], "cancel"); eq(AB.state.busy, false)
	-- a unit above the line's max price
	AB.Search(); stub.Fire("COMMODITY_SEARCH_RESULTS_UPDATED", CLOTH)
	plan = AB.Refresh()
	AB.Click()
	stub.Fire("COMMODITY_PRICE_UPDATED", 100, plan.total - 1)
	eq(ah.calls[#ah.calls], "cancel")
	for _, c in ipairs(ah.calls) do
		assert(not c:find("^confirm"), "nothing was confirmed")
	end
end)

it("Buy a commodity: the confirm click checks the price again, gold and the offer's time", function()
	local ns, stub, ah = Setup()
	local AB = ns.AHBuy
	Commodity(stub, { { 40, 12 } })
	PickAndSearch(ns, stub, FLIP, "commodity")
	local plan = AB.Refresh()
	AB.Click()
	stub.Fire("COMMODITY_PRICE_UPDATED", 40, plan.total)
	stub.money = 10
	local ok, why = AB.Click()
	eq(ok, false); eq(why, "Not enough gold"); eq(#ah.calls, 1)
	stub.money = 10000000
	ah.quote = 0
	ok, why = AB.Click()
	eq(ok, false); assert(why:find("ran out"), why); eq(#ah.calls, 1)
end)

----------------------------------------------------------------------------------------------- confirm limit

it("Confirm limit: a total above the limit asks the client's dialog first, accepting buys once; below it one click buys", function()
	local ns, stub, ah = Setup()
	local AB = ns.AHBuy
	ItemAuctions(stub, { { 150000, 1, 77 } }) -- 15g
	PickAndSearch(ns, stub, { kind = "basket", itemID = SWORD, need = 1 }, "item")
	AB.Refresh()
	eq(AB.Click(), true)
	eq(#ah.calls, 0, "nothing is bought before the dialog is accepted")
	eq(#ah.popups, 1); eq(ah.popups[1].which, "CRAFTWISE_AH_BUY"); eq(ah.popups[1].a2, ns.FormatMoney(150000, true))
	StaticPopupDialogs["CRAFTWISE_AH_BUY"].OnAccept(nil, ah.popups[1].data)
	eq(table.concat(ah.calls, ","), "bid:77:150000")
	-- the dialog's plan is checked again: the auction changed while it was open
	local ns2, stub2, ah2 = Setup()
	ItemAuctions(stub2, { { 150000, 1, 77 } })
	PickAndSearch(ns2, stub2, { kind = "basket", itemID = SWORD, need = 1 }, "item")
	ns2.AHBuy.Refresh()
	ns2.AHBuy.Click()
	ItemAuctions(stub2, { { 170000, 1, 77 } })
	StaticPopupDialogs["CRAFTWISE_AH_BUY"].OnAccept(nil, ah2.popups[1].data)
	eq(#ah2.calls, 0, "the price rose while asking: nothing bought")
	-- the limit is a setting
	local ns3, stub3, ah3 = Setup()
	ns3.db.settings.ahBuyConfirm = 200000
	ItemAuctions(stub3, { { 150000, 1, 77 } })
	PickAndSearch(ns3, stub3, { kind = "basket", itemID = SWORD, need = 1 }, "item")
	ns3.AHBuy.Refresh()
	ns3.AHBuy.Click()
	eq(#ah3.popups, 0); eq(#ah3.calls, 1, "below the limit: one click buys")
end)

----------------------------------------------------------------------------------------------- source rules

local function Source(path)
	local f = assert(io.open(path, "rb"))
	local text = f:read("*a")
	f:close()
	local lines = {}
	for line in (text .. "\n"):gmatch("(.-)\r?\n") do
		lines[#lines + 1] = (line:gsub("%-%-.*$", ""))
	end
	return lines
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

it("Source: PlaceBid, StartCommoditiesPurchase and ConfirmCommoditiesPurchase are called once each, in AHBuy.lua only", function()
	local found = {}
	for _, path in ipairs(AddonFiles()) do
		for n, line in ipairs(Source(path)) do
			for _, name in ipairs({ "PlaceBid", "StartCommoditiesPurchase", "ConfirmCommoditiesPurchase" }) do
				if line:find("C_AuctionHouse." .. name .. "(", 1, true) then -- a call (hooksecurefunc strings are not)
					found[name] = found[name] or {}
					table.insert(found[name], path .. ":" .. n)
				end
			end
		end
	end
	for _, name in ipairs({ "PlaceBid", "StartCommoditiesPurchase", "ConfirmCommoditiesPurchase" }) do
		assert(found[name] and #found[name] == 1, name .. " must appear exactly once: " .. table.concat(found[name] or {}, ", "))
		assert(found[name][1]:find("CraftWise/AHBuy.lua", 1, true), name .. " outside AHBuy.lua: " .. found[name][1])
	end
end)

it("Source: Execute and Confirm are reached only from Click and Accept; those only from a button's OnClick or the dialog's OnAccept", function()
	for _, path in ipairs(AddonFiles()) do
		local lines = Source(path)
		for n, line in ipairs(lines) do
			for _, fn in ipairs({ "Execute", "Confirm" }) do
				if not path:find("CraftWise/AHBuy.lua", 1, true) and not line:find("^function") and (line:find("AHBuy." .. fn .. "(", 1, true) or line:find("AB." .. fn .. "(", 1, true)) then
					error(path .. ":" .. n .. " calls " .. fn .. " from outside AHBuy.Click / AHBuy.Accept")
				end
			end
			if not path:find("CraftWise/AHBuy.lua", 1, true) and (line:find("AHBuy.Click(", 1, true) or line:find("AHBuy.Accept(", 1, true)
				or line:find("AB.Click(", 1, true)) then
				assert(path:find("UI/AHPanel.lua", 1, true), path .. ":" .. n .. " calls the buy path")
				assert((lines[n - 1] or ""):find("OnClick") or (lines[n - 2] or ""):find("OnClick"), path .. ":" .. n .. " is not in an OnClick")
			end
		end
	end
	-- inside AHBuy.lua: Execute is called by Click and Accept, Confirm by Click, nothing else
	local calls = {}
	local current
	for _, line in ipairs(Source("CraftWise/AHBuy.lua")) do
		current = line:match("^function AHBuy%.(%w+)") or line:match("^local function (%w+)") or current
		for _, fn in ipairs({ "Execute", "Confirm" }) do
			if not line:find("^function") and line:find("AHBuy." .. fn .. "(", 1, true) then
				calls[#calls + 1] = fn .. "<-" .. tostring(current)
			end
		end
	end
	table.sort(calls)
	eq(table.concat(calls, ","), "Confirm<-Click,Execute<-Accept,Execute<-Click")
end)

it("Source: nothing in the buying runs on a timer, an update or a ticker, and the panel registers no OnUpdate", function()
	for _, path in ipairs({ "CraftWise/AHBuy.lua", "CraftWise/UI/AHPanel.lua" }) do
		for n, line in ipairs(Source(path)) do
			for _, bad in ipairs({ "C_Timer", "OnUpdate", "NewTicker", "NewTimer", "After(" }) do
				assert(not line:find(bad, 1, true), path .. ":" .. n .. " uses " .. bad)
			end
		end
	end
end)

----------------------------------------------------------------------------------------------- lines and panel

it("Lines: the flips still missing first (the bags count), then the basket's AH lines", function()
	local ns, stub = Setup()
	ns.db.flips = { items = { { itemID = CLOTH, units = 15, atLeast = false, profit = 400, price = 40, sell = 100, maxUnit = 99 } } }
	local lines = ns.AHBuy.Lines({ split = { auction = { { itemID = SWORD, quantity = 3 } } } })
	eq(#lines, 2); eq(lines[1].kind, "flip"); eq(lines[1].need, 15); eq(lines[1].maxUnit, 99); eq(lines[2].kind, "basket"); eq(lines[2].need, 3)
	stub.bags[0] = { { itemID = CLOTH, stackCount = 5, quality = 1 } }
	lines = ns.AHBuy.Lines({ split = { auction = {} } })
	eq(lines[1].need, 10, "units in the bags tick off")
	stub.bags[0] = { { itemID = CLOTH, stackCount = 15, quality = 1 } }
	eq(#ns.AHBuy.Lines({ split = { auction = {} } }), 0, "bought: the line is done")
end)

it("Panel: a click on a line picks and searches it once; Buy shows the exact total and its click is the only way to buy", function()
	local ns, stub, ah = Setup()
	ns.db.flips = { items = { { itemID = CLOTH, units = 12, atLeast = false, profit = 400, price = 40, sell = 100, maxUnit = 99 } } }
	Commodity(stub, { { 40, 5 }, { 90, 10 } })
	local panel = CraftWiseAHPanel
	assert(panel and panel:IsShown(), "the panel is docked to the AH frame")
	ns.Notify("BASKET_CHANGED") -- the kept lines are out of date
	ns.AHPanel.Update()
	local lines = ns.AHPanel.Lines()
	eq(#lines, 1)
	eq(ns.AHPanel.LineText(lines[1]), "Linen Cloth ×12 · max " .. ns.FormatMoney(99, true))
	eq(#ah.searches, 0, "opening the AH and drawing the panel search nothing")
	-- the row button
	local button
	for _, fr in ipairs(stub.frames) do
		if fr.line and fr.scripts and fr.scripts.OnClick then button = fr end
	end
	assert(button, "a line row exists")
	button.scripts.OnClick(button)
	eq(#ah.searches, 1)
	stub.Fire("COMMODITY_SEARCH_RESULTS_UPDATED", CLOTH)
	eq(panel.buy.text, "Buy 12 for " .. ns.FormatMoney(40 * 5 + 90 * 7, true))
	eq(#ah.calls, 0, "nothing is bought by drawing")
	panel.buy.scripts.OnClick(panel.buy)
	eq(table.concat(ah.calls, ","), "start:100:12")
	eq(panel.buy.enabled, false, "off until the result")
end)
