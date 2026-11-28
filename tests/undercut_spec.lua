-- Undercut watch (#427): the decision (own listings, ties, once per undercut), the rounds on the sweep's queue,
-- the pauses, the alert and the page's marks. Nothing here buys, lists or cancels.
local NOW = os.time({ year = 2026, month = 11, day = 28, hour = 18 })
local RACK, SWORD = 5500, 5501

local function Load()
	local ns, stub = LoadAddon()
	stub.clock = NOW
	time = function(t)
		if t then return os.time(t) end
		return stub.clock
	end
	stub.names.player, stub.surnames.player = "Veli", "Tanner"
	stub.items[RACK] = { name = "Tanning Rack", stack = 200 }
	stub.items[SWORD] = { name = "Test Sword", stack = 1 }
	stub.deposit = 100
	AuctionHouseFrame = CreateFrame("Frame", "AuctionHouseFrame")
	local ah = { searches = {}, calls = {} }
	local C = C_AuctionHouse
	C.MakeItemKey = function(id) return { itemID = id, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 } end
	C.GetItemKeyInfo = function(key) return { isCommodity = key.itemID == RACK } end
	C.SendSearchQuery = function(key) ah.searches[#ah.searches + 1] = key.itemID end
	C.PlaceBid = function() ah.calls[#ah.calls + 1] = "bid" end
	C.StartCommoditiesPurchase = function() ah.calls[#ah.calls + 1] = "start" end
	C.ConfirmCommoditiesPurchase = function() ah.calls[#ah.calls + 1] = "confirm" end
	C.CancelAuction = function() ah.calls[#ah.calls + 1] = "cancel" end
	-- the alert's outside world
	ah.shown, ah.sounds, ah.flashes, ah.chat = {}, {}, 0, {}
	local real = ns.LootToast.ShowCustom
	ns.LootToast.ShowCustom = function(entry) ah.shown[#ah.shown + 1] = entry; return real(entry) end
	SOUNDKIT = { ALARM_CLOCK_WARNING_3 = 4321 }
	PlaySound = function(id, channel) ah.sounds[#ah.sounds + 1] = { id = id, channel = channel } end
	FlashClientIcon = function() ah.flashes = ah.flashes + 1 end
	ns.Print = function(text) ah.chat[#ah.chat + 1] = text end
	ah.restore = function() end
	stub.Fire("PLAYER_LOGIN")
	stub.Fire("PLAYER_ENTERING_WORLD", true, false)
	stub.zone, stub.subzone = "Orgrimmar", ""
	stub.Fire("AUCTION_HOUSE_SHOW")
	return ns, stub, ah
end

local nextID = 900
local function Post(stub, itemID, q, unit, item)
	local loc = { itemID = itemID, link = ("|cffffffff|Hitem:%d::::::::20:::::::::|h[%s]|h|r"):format(itemID, stub.items[itemID].name) }
	if item then C_AuctionHouse.PostItem(loc, 3, q, nil, unit) else C_AuctionHouse.PostCommodity(loc, 3, q, unit) end
	nextID = nextID + 1
	stub.Fire("AUCTION_HOUSE_AUCTION_CREATED", nextID)
	return nextID
end

-- Commodity rows { unit, qty, own, numOwn }.
local function RackRows(stub, rows)
	local list = {}
	for i, r in ipairs(rows) do
		list[i] = { itemID = RACK, quantity = r[2] or 1, unitPrice = r[1], auctionID = 700 + i, owners = {},
			containsOwnerItem = r.own or false, numOwnerItems = r.numOwn }
	end
	stub.commodity[RACK] = { rows = list, total = 99 }
end

-- One round: advance the clock past the next check, tick, answer what was asked and let the queue move on.
local function Round(stub, ah, answer)
	stub.now = stub.now + 200
	local before = #ah.searches
	stub.Tick()
	for _ = 1, 10 do
		for i = before + 1, #ah.searches do
			answer(ah.searches[i])
		end
		before = #ah.searches
		stub.RunTimers()
		if #ah.searches == before then break end
	end
end

------------------------------------------------------------------------------------------ the decision

it("Competitor: a tie and a lower price count; a higher one, nothing and my own row do not", function()
	local W = (LoadAddon()).Auctions.Watch
	eq(W.Competitor({ { unit = 1999, qty = 3 } }, 1999), 1999, "a tie is an undercut")
	eq(W.Competitor({ { unit = 1998, qty = 1 }, { unit = 1999, qty = 5 } }, 1999), 1998)
	eq(W.Competitor({ { unit = 2000, qty = 4 } }, 1999), nil, "dearer than mine")
	eq(W.Competitor({}, 1999), nil)
	eq(W.Competitor({ { unit = 1990, qty = 20, own = true } }, 1999), nil, "my own listing, however cheap")
	eq(W.Competitor({ { unit = 1999, qty = 20, own = true, numOwn = 20 } }, 1999), nil, "all of the row is mine")
	eq(W.Competitor({ { unit = 1999, qty = 25, own = true, numOwn = 20 } }, 1999), 1999, "5 of the row are somebody else's")
end)

it("Judge: one alert per new undercut, again when it gets cheaper or after a re-post, never for a better price", function()
	local W = (LoadAddon()).Auctions.Watch
	local st, alert = W.Judge(nil, 1998, 1999, 100)
	eq(alert, true); eq(st.price, 1998)
	st, alert = W.Judge(st, 1998, 1999, 100); eq(alert, false, "the same undercut again")
	st, alert = W.Judge(st, 1999, 1999, 100); eq(alert, false, "the competitor went up to a tie: nothing new")
	st, alert = W.Judge(st, 1990, 1999, 100); eq(alert, true, "cheaper still")
	st, alert = W.Judge(st, 1990, 1999, 200); eq(alert, true, "I re-posted and I am still behind")
	st, alert = W.Judge(st, 1990, 1980, 200); eq(alert, true, "my price changed")
	st, alert = W.Judge(st, nil, 1980, 200); eq(st, nil); eq(alert, false, "no competitor: nothing kept")
	st, alert = W.Judge(st, 1980, 1980, 200); eq(alert, true, "a new competitor after none is a new undercut")
end)

------------------------------------------------------------------------------------------ rounds

it("round: only active listings of this house are searched, each item once, own listings are ignored", function()
	local ns, stub, ah = Load()
	Post(stub, RACK, 5, 1999); Post(stub, RACK, 5, 2100); Post(stub, SWORD, 1, 9000, true)
	ns.Auctions.Watch.SetEnabled(true)
	RackRows(stub, { { 1999, 10, own = true }, { 2500, 4 } }) -- the cheapest is mine
	stub.itemSearch[SWORD] = { rows = { { itemKey = { itemID = SWORD }, auctionID = 1, quantity = 1, buyoutAmount = 9500 } } }
	local function answer(id)
		if id == RACK then stub.Fire("COMMODITY_SEARCH_RESULTS_UPDATED", RACK)
		else stub.Fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = id }) end
	end
	Round(stub, ah, answer)
	eq(#ah.searches, 2, "one search per distinct item")
	eq(#ah.shown, 0, "my own listing and a dearer one are no undercut")
	eq(ns.Auctions.Watch.Undercut(RACK), nil)
	eq(#ah.calls, 0, "nothing bought, listed or cancelled")
	ah.restore()
end)

it("round: a tie alerts once with the line, the sound on Master, the taskbar flash and a chat line", function()
	local ns, stub, ah = Load()
	Post(stub, RACK, 5, 1999)
	ns.Auctions.Watch.SetEnabled(true)
	RackRows(stub, { { 1999, 3 } })
	local function answer(id) stub.Fire("COMMODITY_SEARCH_RESULTS_UPDATED", id) end
	Round(stub, ah, answer)
	eq(#ah.shown, 1); eq(ah.shown[1].text, "Undercut: Tanning Rack"); eq(ah.shown[1].copper, 1999)
	eq(ah.shown[1].detail, "yours " .. ns.FormatCoins(1999)); eq(ah.shown[1].itemID, RACK)
	eq(#ah.sounds, 1); eq(ah.sounds[1].id, 4321); eq(ah.sounds[1].channel, "Master")
	eq(ah.flashes, 1)
	assert(ah.chat[#ah.chat]:find("Undercut: Tanning Rack", 1, true), tostring(ah.chat[#ah.chat]))
	eq(ns.Auctions.Watch.Undercut(RACK).price, 1999)
	-- the next rounds with the same undercut stay silent
	Round(stub, ah, answer); Round(stub, ah, answer)
	eq(#ah.shown, 1); eq(#ah.sounds, 1); eq(ah.flashes, 1)
	-- cheaper still alerts again
	RackRows(stub, { { 1990, 3 } })
	Round(stub, ah, answer)
	eq(#ah.shown, 2); eq(ah.shown[2].copper, 1990)
	-- the competitor is gone: the mark goes, and a new one later alerts
	RackRows(stub, { { 2500, 3 } })
	Round(stub, ah, answer)
	eq(ns.Auctions.Watch.Undercut(RACK), nil)
	RackRows(stub, { { 1990, 3 } })
	Round(stub, ah, answer)
	eq(#ah.shown, 3)
	ah.restore()
end)

it("round: the sound has its own setting, the line comes with the watch", function()
	local ns, stub, ah = Load()
	Post(stub, RACK, 5, 1999)
	ns.db.settings.undercutSound = false
	ns.Auctions.Watch.SetEnabled(true)
	RackRows(stub, { { 1500, 3 } })
	Round(stub, ah, function(id) stub.Fire("COMMODITY_SEARCH_RESULTS_UPDATED", id) end)
	eq(#ah.shown, 1); eq(#ah.sounds, 0, "sound off"); eq(ah.flashes, 1)
	ah.restore()
end)

it("round: a re-post alerts again while the competitor stays ahead", function()
	local ns, stub, ah = Load()
	Post(stub, RACK, 5, 1999)
	ns.Auctions.Watch.SetEnabled(true)
	RackRows(stub, { { 1999, 3 } })
	local function answer(id) stub.Fire("COMMODITY_SEARCH_RESULTS_UPDATED", id) end
	Round(stub, ah, answer)
	eq(#ah.shown, 1)
	stub.clock = stub.clock + 60
	stub.now = stub.now + 60
	Post(stub, RACK, 5, 1999) -- the player posts again
	Round(stub, ah, answer)
	eq(#ah.shown, 2, "after a re-post the same tie is a new undercut")
	ah.restore()
end)

------------------------------------------------------------------------------------------ pauses

it("pause: no round while a purchase is out or a post is going, nor in the seconds after the Buy panel was used", function()
	local ns, stub, ah = Load()
	Post(stub, RACK, 5, 1999)
	local W = ns.Auctions.Watch
	W.SetEnabled(true)
	stub.now = stub.now + 200
	ns.AHBuy.state.phase = "confirm"
	stub.Tick(); eq(#ah.searches, 0, "a purchase is waiting")
	eq(W.Paused(false), "buying")
	ns.AHBuy.state.phase = "idle"
	ns.AHBuy.Pick({ kind = "basket", itemID = RACK, need = 1 })
	ns.AHBuy.state.phase = "idle"
	stub.Tick(); eq(#ah.searches, 0, "the panel was just used")
	stub.now = stub.now + 20
	-- a post the player started and the client has not confirmed
	local loc = { itemID = RACK, link = "x" }
	C_AuctionHouse.PostCommodity(loc, 3, 5, 1999)
	eq(W.Paused(false), "posting")
	stub.Tick(); eq(#ah.searches, 0, "posting")
	stub.Fire("AUCTION_HOUSE_POST_ERROR")
	stub.now = stub.now + 20
	eq(W.Paused(false), nil)
	stub.Tick(); eq(#ah.searches, 1, "it goes on once nothing is going")
	ah.restore()
end)

it("pause: a price refresh of ours is not interrupted; the watch's own run gives way to the player's refresh and buy", function()
	local ns, stub, ah = Load()
	Post(stub, RACK, 5, 1999)
	local W = ns.Auctions.Watch
	W.SetEnabled(true)
	local ok = ns.Market.SweepStart({ SWORD })
	eq(ok, true)
	stub.now = stub.now + 200
	eq(W.Paused(false), "refresh")
	ns.Market.SweepStop()
	-- the watch's run is on; the player starts their own refresh: theirs wins
	stub.Tick()
	eq(ns.Market.SweepQuiet(), true)
	local started = ns.AHBuy.SweepStart({ SWORD })
	eq(started, true); eq(ns.Market.SweepQuiet(), false)
	ns.Market.SweepStop()
	-- and a buy press stops a quiet run
	stub.now = stub.now + 200
	stub.Tick()
	eq(ns.Market.SweepQuiet(), true)
	ns.AHBuy.Click()
	eq(ns.Market.SweepQuiet(), false)
	ah.restore()
end)

it("pause: closing the window stops the timer and the run; nothing runs with the switch off", function()
	local ns, stub, ah = Load()
	Post(stub, RACK, 5, 1999)
	local W = ns.Auctions.Watch
	stub.now = stub.now + 200
	stub.Tick(); eq(#ah.searches, 0, "off by default")
	W.SetEnabled(true)
	stub.now = stub.now + 200
	stub.Tick(); eq(#ah.searches, 1)
	stub.Fire("AUCTION_HOUSE_CLOSED")
	eq(ns.Market.SweepRunning(), false)
	stub.now = stub.now + 200
	stub.Tick(); eq(#ah.searches, 1, "closed")
	ah.restore()
end)

------------------------------------------------------------------------------------------ the key, the status, the page

it("key: 'check my auctions now' runs one round at once, even with the timer off, and never twice for one press", function()
	local ns, stub, ah = Load()
	Post(stub, RACK, 5, 1999)
	RackRows(stub, { { 1999, 3 } })
	eq(_G.BINDING_NAME_CRAFTWISE_AH_CHECK, "AH: check my auctions now")
	eq(CraftWise_AHCheckKey("down"), true); eq(#ah.searches, 1)
	eq(CraftWise_AHCheckKey("down"), false, "held")
	stub.Fire("COMMODITY_SEARCH_RESULTS_UPDATED", RACK)
	eq(#ah.shown, 1, "same alerting")
	stub.RunTimers()
	CraftWise_AHCheckKey("up")
	ns.AHBuy.state.phase = "buying"
	eq(CraftWise_AHCheckKey("down"), false, "not during a purchase")
	CraftWise_AHCheckKey("up")
	local xml = io.open("CraftWise/Bindings.xml", "rb"):read("*a")
	assert(xml:find('<Binding name="CRAFTWISE_AH_CHECK" category="ADDONS" runOnUp="true">%s*CraftWise_AHCheckKey%(keystate%)'))
	ah.restore()
end)

it("status: the page note counts down, says when it is paused and when the client gave no answer", function()
	local ns, stub, ah = Load()
	Post(stub, RACK, 5, 1999)
	local W = ns.Auctions.Watch
	eq(W.Status(), nil, "off")
	W.SetEnabled(true)
	stub.now = stub.now + W.POST_GRACE + 1 -- the post above is over
	local text, state = W.Status()
	eq(state, "waiting"); assert(text:find("watching · next check in %d+ s"), text)
	ns.AHBuy.state.phase = "confirm"
	text, state = W.Status(); eq(state, "paused"); assert(text:find("paused while you buy", 1, true), text)
	ns.AHBuy.state.phase = "idle"
	-- a round nobody answers: the timeout ends it with no answer
	stub.now = stub.now + 200
	stub.Tick()
	stub.RunTimers() -- the item's timeout
	text, state = W.Status(); eq(state, "silent"); assert(text:find("check my auctions now", 1, true), text)
	stub.Fire("AUCTION_HOUSE_CLOSED")
	text, state = W.Status(); eq(state, "closed")
	ah.restore()
end)

it("page: the listed rows at or above the competitor's price say so, with his price; a cheaper row of mine does not", function()
	local ns, stub, ah = Load()
	local M = ns.Main
	Post(stub, RACK, 5, 1999)
	Post(stub, RACK, 5, 1500)
	Post(stub, SWORD, 1, 9000, true)
	local W = ns.Auctions.Watch
	W.SetEnabled(true)
	RackRows(stub, { { 1600, 3 } })
	local function answer(id)
		if id == RACK then stub.Fire("COMMODITY_SEARCH_RESULTS_UPDATED", id) else stub.Fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = id }) end
	end
	stub.itemSearch[SWORD] = { rows = {} }
	Round(stub, ah, answer)
	eq(W.Undercut(RACK), nil, "1600 is above my lowest price 1500: my priority holds")
	RackRows(stub, { { 1500, 3 } })
	Round(stub, ah, answer)
	eq(W.Undercut(RACK).price, 1500); eq(W.Undercut(RACK).mine, 1500)
	local P = M.Page("auctions").P
	local rows = P.Rows(ns.Auctions.List(), stub.clock)
	local marked, plain = 0, 0
	for _, r in ipairs(rows) do
		if r.itemID == RACK then
			eq(r.undercut, 1500); eq(r.statusColor, "danger")
			assert(r.statusText:find("Undercut 1g", 1, true) == nil and r.statusText:find("Undercut 15s", 1, true), r.statusText)
			marked = marked + 1
		else
			eq(r.undercut, nil); eq(r.statusText, "Listed"); plain = plain + 1
		end
	end
	eq(marked, 2); eq(plain, 1)
	eq(P.NextInterval(45), 60); eq(P.NextInterval(120), 30)
	ah.restore()
end)

it("source: the watch buys, lists, cancels and confirms nothing", function()
	local f = assert(io.open("CraftWise/Auctions.lua", "rb")); local text = f:read("*a"); f:close()
	local from = text:find("Undercut watch (#427)", 1, true)
	local to = text:find("-- Events and hooks", from, true)
	local part = text:sub(from, to)
	for _, name in ipairs({ "PlaceBid", "StartCommoditiesPurchase", "ConfirmCommoditiesPurchase", "CancelAuction", "PostItem", "PostCommodity" }) do
		assert(not part:find(name, 1, true), "the watch names " .. name)
	end
end)
