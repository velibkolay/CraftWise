-- Buying at the auction house from CraftWise (#315, part 1): search a line (a flip or an AH line of the basket),
-- read what is listed, buy with a click. Auctionator is not needed; it stays a second way (Basket.lua).
--
-- Safety (Veli's rules, #315). Gold is at stake, so the buying is kept small and in one place:
--   * C_AuctionHouse.PlaceBid, StartCommoditiesPurchase and ConfirmCommoditiesPurchase are each called once, in
--     this file (AHBuy.Execute and AHBuy.Confirm), and these two are reached only from AHBuy.Click and
--     AHBuy.Accept, which only the panel's Buy button (OnClick), the client's confirm dialog (OnAccept) and,
--     since part 2, the "AH: buy best" key (AHBuy.KeyBuy) call. All three are a click or a key press. There is no
--     timer, no loop, no retry and no queue. One exception, #408: the quote of a commodity purchase that a click
--     started on a line with a max price confirms itself (see below). A spec reads the source and fails if the
--     calls or their callers appear anywhere else.
--   * Right before each call the auction is read again: same item, unit price at most the line's max, total
--     at most what the button showed, enough gold. If anything differs nothing is bought and the panel says
--     why (the shown plan is replaced by the live one).
--   * The button shows the exact total ("Buy 12 for 3g 40s"). A total above Settings "Ask above" (default 10g)
--     asks once more with the client's confirm dialog (StaticPopup, as Blizzard's BUYOUT_AUCTION does).
--   * One purchase per click: after a call the button stays disabled until its result arrives (success or an
--     error). There is no timeout that frees it; closing the auction house does.
--   * A commodity on a line WITH a max price is one click (#408): the click starts the purchase and arms
--     S.armed for that purchase only. When the server's quote (COMMODITY_PRICE_UPDATED) arrives and a purchase
--     is armed, the quote is confirmed right away (AHBuy.Confirm, from the event handler, once) if the unit price
--     is at most the max AND the total is at most units x max; otherwise it is cancelled and the panel says why.
--     The arm is used up by the first quote, and cleared by a new pick, a search, an error, a failed or finished
--     purchase and by closing the auction house. A quote that no click armed is never confirmed. If the client
--     refuses a confirm made outside a click (ADDON_ACTION_BLOCKED, or a Lua error), the panel falls back to the
--     old second click ("Confirm: buy ...").
--   * A commodity on a line WITHOUT a max price needs two clicks: the first starts the purchase and the server
--     answers with the price (COMMODITY_PRICE_UPDATED), the second (a button of its own showing that price)
--     confirms it. A price above what the first click showed is never confirmed: it is cancelled and shown.
--   * The units of a commodity purchase are what is listed at or below the max, at most the line's need; for
--     a line with a limit of its own ("up to N", the snipe list) what this run bought already is taken off N.
--   * After a purchase the results are old, with one exception (#335, item auctions only): the client sends the
--     item's results again after a purchase (ITEM_SEARCH_RESULTS_UPDATED); a list that arrives AFTER the purchase
--     completed (or, when it came first, one that no longer holds the bought auction) marks the list fresh and
--     the next press can buy the next auction. Every press still reads the auction again and applies all the
--     checks above, once, for one auction; an event only marks the list fresh and never buys; auction IDs bought
--     this session are skipped; an error or a commodity purchase leaves the list old (search again). No fresh
--     list: the button stays off until the player searches again, as before.
--
-- Keys (#315, part 2): two key bindings, "AH: search next" and "AH: buy best" (Bindings.xml, runOnUp so the body
-- also hears the release). A press is one action: the search key is AHBuy.Next (one search), the buy key is
-- AHBuy.Click, the same path as the button, with the same checks. A commodity needs two presses (start, then
-- confirm), an item auction one. A press while the key is still held down is ignored (there is no repeat);
-- nothing is queued: a press while the server is busy says "wait" and does nothing. The press is the hardware
-- event the restricted calls need (Blizzard's docs mark PlaceBid and StartCommoditiesPurchase restricted).
--
-- Does the client resend item results after PlaceBid? Blizzard's UI code (Blizzard_AuctionHouseUI/Shared/) only
-- reacts to ITEM_SEARCH_RESULTS_UPDATED(itemKey, newAuctionID) / ITEM_SEARCH_RESULTS_ADDED by redrawing its list
-- (Blizzard_AuctionHouseItemBuyFrame.lua OnEvent, lines 60-73); it never sends the query again after a purchase
-- (the BUYOUT_AUCTION dialog only waits for AUCTION_HOUSE_PURCHASE_COMPLETED(auctionID) or AUCTION_HOUSE_SHOW_ERROR,
-- Frame.lua lines 10-27), so a refreshed list after a purchase comes from the client itself, not from Lua code we
-- can read. Whether and when it comes is checked in game (docs/ingame-checks.md, #335); if it does not, nothing
-- changes: the list stays old.
--
-- How Blizzard's Forever AH UI does it (wow-ui-source, branch forever, Blizzard_AuctionHouseUI/Shared/):
--   Blizzard_AuctionHouseFrame.lua QueryItem: C_AuctionHouse.SendSearchQuery(itemKey, sorts, separateOwnerItems)
--   with sorts from GetSortTypes (Price then Name for commodities; Buyout then Bid for items, lines 199-203);
--   itemKeyInfo.isCommodity (GetItemKeyInfo) picks the commodity path (lines 684-692). Commodity results:
--   GetNumCommoditySearchResults / GetCommoditySearchResultInfo (CommoditiesList.lua); items:
--   GetNumItemSearchResults / GetItemSearchResultInfo (ItemBuyFrame.lua). Item buy: StaticPopup BUYOUT_AUCTION whose
--   OnAccept calls PlaceBid(auctionID, buyout) and waits for AUCTION_HOUSE_PURCHASE_COMPLETED or
--   AUCTION_HOUSE_SHOW_ERROR (Frame.lua lines 10-40). Commodity buy: StartCommoditiesPurchase, then
--   COMMODITY_PRICE_UPDATED / COMMODITY_PRICE_UNAVAILABLE, then ConfirmCommoditiesPurchase on the dialog's Buy
--   Now, ending in COMMODITY_PURCHASE_SUCCEEDED / COMMODITY_PURCHASE_FAILED (BuyDialog.lua). Errors:
--   AUCTION_HOUSE_SHOW_ERROR with AuctionHouseUtil.GetErrorText (Frame.lua line 437).
-- Pure parts (Plan, Describe) take plain data so the specs can feed them.
local addonName, ns = ...

local AHBuy = {}
ns.AHBuy = AHBuy

AHBuy.CONFIRM_ABOVE = 100000 -- copper: a total above this asks once more (Settings, default 10g)
AHBuy.MAX_ROWS = 50 -- results read per search (the client sends 50 at a time)

local S = {
	open = false, -- the auction house window is open
	target = nil, -- { kind = "flip" | "basket", itemID, need, maxUnit, sell }
	phase = "idle", -- idle | searching | ready | quoting | confirm | buying | stale
	busy = false, -- a purchase call is out and its result has not arrived
	isCommodity = nil, -- from the item key info or from the kind of result that arrived
	shown = nil, -- the plan the button showed last
	quote = nil, -- { unit, total } the server's price of a started commodity purchase
	armed = nil, -- { itemID, units, maxUnit }: a click started this commodity purchase; its quote is confirmed once (#408)
	message = nil, -- what the panel says
	bought = {}, -- [auctionID] = true: item auctions bought since the AH opened; never planned again (#335)
	errored = nil, -- { auctionID, units, total, err }: an item buy the server answered with an error; it can still complete (#340)
	run = nil, -- { units, total } bought on the picked line in this run (item auctions, #335)
	afterBuy = false, -- an item purchase just finished: the next item list that arrives is fresh (#335)
	listSeq = 0, -- counts item result events; bidSeq = its value when PlaceBid went out
	bidSeq = 0,
}
AHBuy.state = S
local held = {} -- [key] = true from a key press until its release (#315 part 2)

local function Settings()
	return ns.db and ns.db.settings or {}
end

local function Changed()
	ns.Notify("AHBUY_CHANGED")
end

local function Say(text)
	S.message = text
	Changed()
	return text
end

function AHBuy.ConfirmAbove()
	local v = tonumber(Settings().ahBuyConfirm)
	return v or AHBuy.CONFIRM_ABOVE
end

local function Money(copper)
	return ns.FormatMoney(copper, true)
end

local function ItemName(itemID)
	local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)
	return name or ("item " .. tostring(itemID))
end

----------------------------------------------------------------------------------------------------
-- Plan (pure)
----------------------------------------------------------------------------------------------------

-- What to buy from sorted rows ({ unit (copper per unit), qty, auctionID, own, left }, cheapest first).
-- Commodities: the cheapest units up to `need` that are not above maxUnit (a purchase takes the cheapest
-- units, so the total is the sum). Items: the cheapest single auction at or below maxUnit (one auction per
-- purchase). Own auctions are skipped. Returns nil when nothing qualifies, else
-- { units, total, unitMax (the dearest unit used), partial (fewer than need), auctionID }.
function AHBuy.Plan(rows, isCommodity, need, maxUnit)
	need = math.max(1, math.floor(tonumber(need) or 1))
	local units, total, top, id = 0, 0, 0, nil
	rows = rows or {}
	for i, r in ipairs(rows) do
		if not r.own then
			if maxUnit and r.unit > maxUnit then
				break
			end
			if not isCommodity then
				-- `more`: the auctions after this one that are also at or below the max price (#335)
				local more = 0
				for j = i + 1, maxUnit and #rows or 0 do
					local q = rows[j]
					if not q.own then
						if q.unit > maxUnit then
							break
						end
						more = more + 1
					end
				end
				return { units = r.qty, total = r.unit * r.qty, unitMax = r.unit, partial = r.qty < need, auctionID = r.auctionID,
					buyout = r.buyout or r.unit * r.qty, more = more }
			end
			local take = math.min(r.qty, need - units)
			units, total, top = units + take, total + take * r.unit, r.unit
			if units >= need then
				break
			end
		end
	end
	if units == 0 then
		return nil
	end
	return { units = units, total = total, unitMax = top, partial = units < need }
end

-- The button: its text and whether it can be pressed, from the shown plan (nil, why without one), the phase,
-- whether a purchase call is out, and the gold the player has.
function AHBuy.Describe(plan, why, phase, busy, money, oneClickMax)
	if busy then
		return "Waiting for the auction house...", false
	end
	if not plan then
		return why or "Search", false
	end
	if money and money < plan.total then
		return "Not enough gold: " .. Money(plan.total), false
	end
	if phase == "confirm" then
		return ("Confirm: buy %d for %s"):format(plan.units, Money(plan.total)), true
	end
	if oneClickMax and not plan.auctionID then -- #408: one click buys up to this many at or below the max (ASCII: the font has no <=)
		return ("Buy up to %d at <= %s"):format(plan.units, ns.Snipe and ns.Snipe.PriceText(oneClickMax) or tostring(oneClickMax)), true
	end
	local more = plan.more and plan.more > 0 and (" (%d more under max)"):format(plan.more) or ""
	return ("Buy %d for %s%s"):format(plan.units, Money(plan.total), more), true
end

----------------------------------------------------------------------------------------------------
-- Reading the auction house
----------------------------------------------------------------------------------------------------

AHBuy.IDLE_SECONDS = 15 -- the panel counts as in use this long after a pick, search or buy press (#427)
local function Touch()
	S.usedAt = GetTime()
end

local function Throttled()
	return C_AuctionHouse and C_AuctionHouse.IsThrottledMessageSystemReady and not C_AuctionHouse.IsThrottledMessageSystemReady()
end

-- The listed rows of an item now, sorted as the client sends them, up to MAX_ROWS: { unit, qty, auctionID, own, left }.
-- An ITEM row is not a stack (#343, gold safety): in Forever a search row groups identical auctions, `quantity` is
-- how many are listed and `buyoutAmount` is the price of ONE purchase; one PlaceBid(auctionID, buyoutAmount) buys one.
-- Blizzard's UI never divides it: the buyout column shows buyoutAmount as is and the quantity column shows only the
-- count of auctions (Blizzard_AuctionHouseTableBuilder.lua, AuctionHouseTableCellItemQuantityMixin:Populate and
-- AuctionHouseTableCellBuyoutMixin; Blizzard_AuctionHouseItemBuyFrame.lua OnAuctionSelected passes
-- auctionData.buyoutAmount to the BUYOUT_AUCTION dialog, Frame.lua lines 10-12). So an item row is priced at its
-- buyout for one unit: unit = buyoutAmount, qty = 1 (an item that does not stack is one unit per purchase; for any
-- other item the units per purchase are not known and one is the gold-safe reading: the max check never lets a
-- purchase through that costs more than the max). `listed` keeps the count the client reported, for display only.
function AHBuy.ReadRows(itemID, isCommodity)
	local rows = {}
	if not (C_AuctionHouse and itemID) then
		return rows
	end
	if isCommodity then
		for i = 1, math.min(C_AuctionHouse.GetNumCommoditySearchResults(itemID) or 0, AHBuy.MAX_ROWS) do
			local info = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, i)
			if info and info.unitPrice and info.quantity and info.quantity > 0 then
				rows[#rows + 1] = { unit = info.unitPrice, qty = info.quantity, auctionID = info.auctionID,
					own = info.containsOwnerItem or false, left = info.timeLeftSeconds }
			end
		end
	else
		local key = C_AuctionHouse.MakeItemKey(itemID)
		for i = 1, math.min(C_AuctionHouse.GetNumItemSearchResults(key) or 0, AHBuy.MAX_ROWS) do
			local info = C_AuctionHouse.GetItemSearchResultInfo(key, i)
			if info and info.buyoutAmount and info.buyoutAmount > 0 and (info.quantity or 1) > 0 then
				rows[#rows + 1] = { unit = info.buyoutAmount, qty = 1, listed = info.quantity or 1, auctionID = info.auctionID,
					buyout = info.buyoutAmount, own = info.containsOwnerItem or false, left = info.timeLeftSeconds, band = info.timeLeft }
			end
		end
	end
	return rows
end

-- The plan for the target from the live results; nil, why when there is none.
function AHBuy.Live()
	local t = S.target
	if not t then
		return nil, "Pick a line first"
	end
	if S.isCommodity == nil then
		return nil, "Search first"
	end
	local rows = AHBuy.ReadRows(t.itemID, S.isCommodity)
	if next(S.bought) then -- an auction bought this session is never planned again, even if the list still shows it
		local keep = {}
		for _, r in ipairs(rows) do
			if not (r.auctionID and S.bought[r.auctionID]) then
				keep[#keep + 1] = r
			end
		end
		rows = keep
	end
	local need = t.need
	if t.fixed and S.run then -- an "up to N" of his own: what this run bought already comes off it (#408)
		need = need - (S.run.units or 0)
		if need < 1 then
			return nil, ("Already bought %d: that is your limit"):format(S.run.units)
		end
	end
	local plan = AHBuy.Plan(rows, S.isCommodity, need, t.maxUnit)
	if not plan then
		return nil, t.maxUnit and "Nothing is listed at or below the max price" or "Nothing is listed"
	end
	plan.itemID = t.itemID
	if t.kind == "flip" and t.sell then
		plan.profit = t.sell * plan.units - plan.total
	end
	return plan
end

-- Recomputes what the button shows; the panel calls it on every change. Returns the plan or nil, why.
function AHBuy.Refresh()
	if S.phase == "confirm" and S.quote then
		return { itemID = S.target.itemID, units = S.shown.units, total = S.quote.total, unitMax = S.quote.unit }
	end
	if S.phase == "quoting" or S.phase == "buying" then
		return S.shown -- a purchase is out: what it was bought for stays
	end
	if S.phase == "stale" or S.phase == "searching" or S.phase == "idle" then
		S.shown = nil
		return nil, S.phase == "searching" and "Searching..." or S.phase == "stale" and "Search again" or "Pick a line"
	end
	local plan, why = AHBuy.Live()
	S.shown = plan
	return plan, why
end

----------------------------------------------------------------------------------------------------
-- Search
----------------------------------------------------------------------------------------------------

-- Sorts as Blizzard's UI asks for them (Blizzard_AuctionHouseFrame.lua lines 199-203).
local function Sorts(isCommodity)
	local O = Enum and Enum.AuctionHouseSortOrder or {}
	if isCommodity == false then
		return { { sortOrder = O.Buyout, reverseSort = false }, { sortOrder = O.Bid, reverseSort = false } }
	end
	return { { sortOrder = O.Price, reverseSort = false }, { sortOrder = O.Name, reverseSort = false } }
end

-- Gives up a commodity quote that was started and not confirmed (a new pick or search replaces it).
local function DropQuote()
	S.armed = nil
	if S.phase == "confirm" or S.phase == "quoting" then
		C_AuctionHouse.CancelCommoditiesPurchase()
	end
end

-- Picks a line to buy; nothing is sent.
function AHBuy.Pick(line)
	Touch()
	if S.busy then
		return false
	end
	AHBuy.SweepStop() -- a pick ends a price refresh (#388)
	DropQuote()
	local t = S.target
	if not (t and line and t.itemID == line.itemID and t.kind == line.kind) then
		S.run = nil -- another line: a new run
	end
	S.target, S.shown, S.quote, S.phase, S.isCommodity, S.afterBuy = line, nil, nil, "idle", nil, false
	S.message = nil
	Changed()
	return true
end

-- One search of the picked line (a click, or the key later). Returns true or false, why.
function AHBuy.Search()
	Touch()
	AHBuy.SweepStop() -- a search of a line ends a price refresh (#388)
	local t = S.target
	if not t then
		return false, Say("Pick a line first")
	end
	if not S.open then
		return false, Say("Open the auction house first")
	end
	if S.busy then
		return false, Say("Wait for the purchase")
	end
	if Throttled() then
		return false, Say("Wait: the auction house is busy")
	end
	DropQuote()
	local key = C_AuctionHouse.MakeItemKey(t.itemID)
	local info = C_AuctionHouse.GetItemKeyInfo and C_AuctionHouse.GetItemKeyInfo(key)
	S.isCommodity = info and info.isCommodity or nil -- unknown until the answer says which kind it is
	S.phase, S.shown, S.quote, S.message, S.afterBuy = "searching", nil, nil, nil, false
	C_AuctionHouse.SendSearchQuery(key, Sorts(S.isCommodity), false)
	Changed()
	return true
end

-- The next line to search (a key press, #315 part 2): one line further down the lines (snipes, flips, basket),
-- round to the first; the picked line again after a purchase or an error (its results are old), when it was
-- picked and not searched yet, or when it is the only one. One search, nothing more. Returns true or false, why.
function AHBuy.Next()
	Touch()
	AHBuy.SweepStop() -- the search key ends a price refresh (#388)
	if S.busy then
		return false, Say("Wait for the purchase")
	end
	if not S.open then
		return false, Say("Open the auction house first")
	end
	if Throttled() then
		return false, Say("Wait: the auction house is busy")
	end
	local list = AHBuy.Lines()
	if #list == 0 then
		return false, Say("Nothing to search: add a snipe, or a flip or basket line")
	end
	local t = S.target
	local index
	for i, l in ipairs(list) do
		if t and l.itemID == t.itemID and l.kind == t.kind then
			index = i
		end
	end
	local pick
	if not index then
		pick = list[1]
	elseif S.phase == "stale" or S.phase == "idle" then
		pick = list[index]
	else
		pick = list[index % #list + 1]
	end
	if not AHBuy.Pick(pick) then
		return false, Say("Wait for the purchase")
	end
	return AHBuy.Search()
end

----------------------------------------------------------------------------------------------------
-- Refreshing the prices of a craft run's plan (#388): the run itself (searches, timers) is Market.lua's
----------------------------------------------------------------------------------------------------

function AHBuy.SweepRunning()
	return ns.Market.SweepRunning() and not ns.Market.SweepQuiet()
end

-- True while a purchase is out or asked, a search of the panel is in flight, or the panel was used a moment ago
-- (#427): the undercut watch sends no search then, its answer would replace the results the next buy reads.
function AHBuy.Occupied(ignoreRecent)
	if S.busy or S.asking or S.phase == "quoting" or S.phase == "confirm" or S.phase == "buying" or S.phase == "searching" then
		return true
	end
	return not ignoreRecent and S.usedAt ~= nil and GetTime() - S.usedAt < AHBuy.IDLE_SECONDS
end

function AHBuy.SweepStop(text)
	return ns.Market.SweepStop(text)
end

-- Starts a price refresh of item IDs on a click; refused while a purchase is out or being asked. Returns true, or false and why.
function AHBuy.SweepStart(items)
	if S.busy or S.asking or S.phase == "quoting" or S.phase == "confirm" or S.phase == "buying" then
		return false, Say("Finish or cancel the purchase first")
	end
	if not S.open then
		return false, Say("Open the auction house first")
	end
	local ok, why = ns.Market.SweepStart(items)
	if not ok then
		return false, Say(why)
	end
	S.message = nil
	Changed()
	return true
end

-- The run ended (done, stopped, or the auction house closed): its last words go to the panel's line.
ns.Listen("SWEEP_DONE", function(_, _, _, text, quiet)
	if not quiet then
		Say(text)
	end
end)
ns.Listen("SWEEP_STEP", Changed)

----------------------------------------------------------------------------------------------------
-- Buying: the only code that calls PlaceBid, StartCommoditiesPurchase and ConfirmCommoditiesPurchase
----------------------------------------------------------------------------------------------------

-- Is the live auction still what the button showed? Returns the live plan or nil, why.
local function Recheck(shown)
	local plan, why = AHBuy.Live()
	if not plan then
		return nil, why or "Nothing to buy"
	end
	local t = S.target
	if plan.itemID ~= shown.itemID or t.itemID ~= shown.itemID then
		return nil, "The item changed"
	end
	if t.maxUnit and plan.unitMax > t.maxUnit then
		return nil, "A unit costs more than your max price"
	end
	-- A line with a max price (#408): a total that moved is fine while every unit is at or below the max (the plan
	-- only holds such units). Without a max the total must not rise above what the button showed.
	if plan.total > shown.total and not (S.isCommodity and t.maxUnit) then
		return nil, ("The price changed: %s now, the button showed %s"):format(Money(plan.total), Money(shown.total))
	end
	if not S.isCommodity and (plan.auctionID ~= shown.auctionID or plan.total ~= shown.total) then
		return nil, "That auction is gone or changed"
	end
	if GetMoney and GetMoney() < plan.total then
		return nil, "Not enough gold"
	end
	return plan
end

-- A refusal: nothing was bought; the panel shows the live plan and why.
local function Refuse(why)
	if S.phase ~= "confirm" then
		S.shown = nil
	end
	Say(why)
	return false, why
end

-- Starts a purchase of the shown plan after the checks. Called only by Click and Accept. One call at most.
function AHBuy.Execute(shown)
	Touch()
	if S.busy then
		return Refuse("Wait for the purchase")
	end
	if not (S.open and shown) then
		return Refuse("Search again")
	end
	if Throttled() then
		return Refuse("Wait: the auction house is busy")
	end
	local plan, why = Recheck(shown)
	if not plan then
		return Refuse(why)
	end
	if not S.isCommodity and S.bought[plan.auctionID] then
		return Refuse("That auction was already bought")
	end
	S.busy = true
	S.message, S.errored = nil, nil
	if S.isCommodity then
		S.shown, S.phase = plan, "quoting"
		S.armed = S.target.maxUnit and { itemID = plan.itemID, units = plan.units, maxUnit = S.target.maxUnit } or nil -- #408
		C_AuctionHouse.StartCommoditiesPurchase(plan.itemID, plan.units)
	else
		S.shown, S.phase, S.bidSeq = plan, "buying", S.listSeq
		C_AuctionHouse.PlaceBid(plan.auctionID, plan.buyout)
	end
	Changed()
	return true
end

-- Is the server's quote one to confirm? nil when it is, else why not. A line with a max price (#408): the unit
-- price at most the max and the total at most units x max. Without a max: the total at most what the button showed.
local function QuoteWhy(t, q, shown)
	if t.maxUnit then
		if q.unit > t.maxUnit then
			return ("The price is %s a unit, above your max %s: not bought"):format(Money(q.unit), Money(t.maxUnit))
		end
		if q.total > shown.units * t.maxUnit then
			return ("The total %s is above %d x your max %s: not bought"):format(Money(q.total), shown.units, Money(t.maxUnit))
		end
	elseif q.total > shown.total then
		return ("The price rose to %s (you saw %s): not bought"):format(Money(q.total), Money(shown.total))
	end
end

-- The second click of a commodity purchase (or, #408, the quote of a purchase a click started on a line with a
-- max price; `auto`): confirms the price the server quoted, if it is still what the
-- button showed. Called only by Click.
function AHBuy.Confirm(auto)
	local t, q, shown = S.target, S.quote, S.shown
	if S.busy or S.phase ~= "confirm" or not (t and q and shown) then
		return Refuse("Search again")
	end
	local why = QuoteWhy(t, q, shown)
	if why then
		C_AuctionHouse.CancelCommoditiesPurchase()
		S.phase, S.quote = "stale", nil
		return Refuse(why)
	end
	if C_AuctionHouse.GetQuoteDurationRemaining and C_AuctionHouse.GetQuoteDurationRemaining() <= 0 then
		S.phase, S.quote = "stale", nil
		return Refuse("The price offer ran out: search again")
	end
	if GetMoney and GetMoney() < q.total then
		return Refuse("Not enough gold")
	end
	S.busy, S.phase, S.message, S.autoConfirm = true, "buying", nil, auto or nil
	local ok = pcall(function()
		C_AuctionHouse.ConfirmCommoditiesPurchase(shown.itemID, shown.units)
	end)
	if not ok then
		AHBuy.ConfirmRefused() -- the client did not take it: the old second click stays
		return false
	end
	Changed()
	return true
end

-- A confirm the client did not take (an error, or ADDON_ACTION_BLOCKED for a call without a fresh click): nothing
-- was bought; the quote stays and the button asks for the second click, as before #408.
function AHBuy.ConfirmRefused()
	if S.phase == "buying" and S.quote and S.autoConfirm then
		S.busy, S.phase, S.autoConfirm = false, "confirm", nil
		Say("The client wants a click to confirm: click Confirm")
	end
end

local EnsureDialog -- below

-- The click on the Buy button (or the key later). Below the confirm limit it buys; above, it asks the client's
-- confirm dialog first, whose Accept calls AHBuy.Accept. Returns true, or false and why.
function AHBuy.Click()
	Touch()
	ns.Market.SweepStopQuiet() -- the undercut watch's run gives way to a buy (#427); a run of ours is refused below
	if S.busy then
		return false, Say("Wait for the purchase")
	end
	if AHBuy.SweepRunning() then
		return false, Say("A price refresh is running: stop it first")
	end
	if S.phase == "confirm" then
		return AHBuy.Confirm()
	end
	if not S.shown then
		local _, why = AHBuy.Refresh()
		return Refuse(why or "Search first")
	end
	local plan, why = Recheck(S.shown)
	if not plan then
		return Refuse(why)
	end
	if plan.total > AHBuy.ConfirmAbove() and StaticPopup_Show then
		S.asking = plan
		EnsureDialog()
		StaticPopup_Show("CRAFTWISE_AH_BUY", ("%d × %s"):format(plan.units, ItemName(plan.itemID)), Money(plan.total), { plan = plan })
		return true
	end
	return AHBuy.Execute(S.shown)
end

-- Accept in the client's confirm dialog: buys what the dialog showed, if it is still so.
function AHBuy.Accept(data)
	S.asking = nil
	return AHBuy.Execute(data and data.plan)
end

-- The client's confirm dialog for a total above the limit. Registered when the file loads, or just before the
-- first time it is shown (the client's own table may not exist earlier).
function EnsureDialog()
	if not StaticPopupDialogs or StaticPopupDialogs["CRAFTWISE_AH_BUY"] then
		return
	end
	StaticPopupDialogs["CRAFTWISE_AH_BUY"] = {
		text = "CraftWise: buy %s for %s from the auction house?",
		button1 = ACCEPT or "Accept",
		button2 = CANCEL or "Cancel",
		OnAccept = function(_, data)
			AHBuy.Accept(data)
		end,
		OnCancel = function()
			S.asking = nil
			Say("Not bought")
		end,
		timeout = 0,
		exclusive = 1,
		hideOnEscape = 1,
		showAlert = 1,
	}
end
EnsureDialog()

----------------------------------------------------------------------------------------------------
-- Events: results, quotes, the end of a purchase
----------------------------------------------------------------------------------------------------

local function Results(isCommodity, itemID)
	local t = S.target
	if not (t and (itemID == nil or itemID == t.itemID)) then
		return
	end
	S.isCommodity = isCommodity
	S.listSeq = S.listSeq + 1
	if S.phase == "searching" then
		S.phase = "ready"
	elseif S.phase == "stale" and S.afterBuy and not isCommodity then
		-- The client sent the item's results again after our purchase completed (#335): the list is fresh. This
		-- only marks it; the next press buys (or not) after the same checks as any press.
		S.phase, S.afterBuy = "ready", false
		if S.run then
			S.message = ("Bought %d for %s"):format(S.run.units, Money(S.run.total))
		end
	end
	Changed()
end

ns.On("AUCTION_HOUSE_SHOW", function()
	S.open = true
	Changed()
end)
ns.On("AUCTION_HOUSE_CLOSED", function()
	S.open, S.busy, S.phase, S.shown, S.quote, S.asking, S.armed, S.autoConfirm = false, false, "idle", nil, nil, nil, nil, nil
	S.bought, S.run, S.afterBuy, S.errored = {}, nil, false, nil
	held.search, held.buy = nil, nil
	Changed()
end)
ns.On("COMMODITY_SEARCH_RESULTS_RECEIVED", function()
	Results(true)
end)
ns.On("COMMODITY_SEARCH_RESULTS_UPDATED", function(_, itemID)
	Results(true, itemID)
end)
ns.On("COMMODITY_SEARCH_RESULTS_ADDED", function(_, itemID)
	Results(true, itemID)
end)
ns.On("ITEM_SEARCH_RESULTS_UPDATED", function(_, itemKey)
	Results(false, itemKey and itemKey.itemID)
end)
ns.On("ITEM_SEARCH_RESULTS_ADDED", function(_, itemKey)
	Results(false, itemKey and itemKey.itemID)
end)
ns.On("AUCTION_HOUSE_THROTTLED_SYSTEM_READY", Changed)

-- The server's price for a started commodity purchase. On a line with a max price a click armed it (#408): the
-- quote is confirmed at once when it is within the max, else cancelled. Nothing armed (no max price, or a quote
-- that no click asked for): never confirmed from here, a price within what the button showed waits for the
-- player's second click and a higher one is cancelled and shown.
local function OnQuote(_, unit, total)
	local t, shown = S.target, S.shown
	if S.phase ~= "quoting" or not (t and shown) then
		return
	end
	S.busy = false
	local armed = S.armed
	S.armed = nil -- used up by the first quote
	local q = { unit = unit, total = total }
	local why = QuoteWhy(t, q, shown)
	if why then
		C_AuctionHouse.CancelCommoditiesPurchase()
		S.phase, S.quote = "stale", nil
		Say(why .. ". Search again.")
		return
	end
	S.phase, S.quote = "confirm", q
	S.message = nil
	if armed and armed.itemID == t.itemID and armed.units == shown.units and armed.maxUnit == t.maxUnit then
		AHBuy.Confirm(true)
		return
	end
	Changed()
end
ns.On("COMMODITY_PRICE_UPDATED", OnQuote)
ns.On("ADDON_ACTION_BLOCKED", function(_, blamed, fn)
	if blamed == addonName and tostring(fn):find("ConfirmCommoditiesPurchase", 1, true) then
		AHBuy.ConfirmRefused()
	end
end)
ns.On("COMMODITY_PRICE_UNAVAILABLE", function()
	if S.phase ~= "quoting" then
		return
	end
	S.busy, S.phase, S.quote, S.armed = false, "stale", nil, nil
	C_AuctionHouse.CancelCommoditiesPurchase()
	Say("The auction house has no price for that any more. Search again.")
end)

-- A commodity purchase that went through counts toward the run (#408: an "up to N" limit).
local function CountCommodity()
	if S.phase == "buying" and S.isCommodity and S.shown and S.quote then
		local run = S.run or { units = 0, total = 0 }
		run.units, run.total = run.units + S.shown.units, run.total + S.quote.total
		S.run = run
	end
end

local function Done(text)
	S.busy, S.phase, S.quote, S.shown, S.afterBuy, S.armed, S.autoConfirm = false, "stale", nil, nil, false, nil, nil
	Say(text)
end
ns.On("COMMODITY_PURCHASE_SUCCEEDED", function()
	if S.phase == "buying" then
		CountCommodity()
		Done("Bought. The list is old: search again.")
	end
end)
ns.On("COMMODITY_PURCHASE_FAILED", function()
	if S.phase == "buying" or S.phase == "quoting" then
		Done("The purchase failed. Search again.")
	end
end)
ns.On("AUCTION_HOUSE_PURCHASE_COMPLETED", function(_, auctionID)
	local shown = S.shown
	local late = S.errored -- an error came first, the purchase still completed (Forever sends error 10 before it, #340)
	if late and auctionID == late.auctionID and S.phase ~= "buying" then
		S.errored = nil
		S.bought[late.auctionID] = true
		local run = S.run or { units = 0, total = 0 }
		run.units, run.total = run.units + late.units, run.total + late.total
		S.run = run
		local text = ("Bought %d for %s (the server also sent error %s)"):format(run.units, Money(run.total), tostring(late.err))
		Say(text .. ". The list is old: search again.")
		-- The #336 flow as after a normal buy: the next fresh list makes the panel ready, or the one that
		-- already arrived does when it no longer holds this auction.
		S.afterBuy = true
		if S.target and S.listSeq > S.bidSeq then
			for _, r in ipairs(AHBuy.ReadRows(S.target.itemID, false)) do
				if r.auctionID == late.auctionID then
					return
				end
			end
			S.phase, S.afterBuy = "ready", false
			Say(text)
		end
		return
	end
	if S.phase ~= "buying" then
		return
	end
	if S.isCommodity or not (shown and shown.auctionID) then
		CountCommodity()
		Done("Bought. The list is old: search again.")
		return
	end
	if auctionID and auctionID ~= shown.auctionID then
		return -- another purchase finished (Blizzard's own window); not ours
	end
	-- An item auction: remember it, count the run, and wait for the client's new list (#335).
	S.bought[shown.auctionID] = true
	local run = S.run or { units = 0, total = 0 }
	run.units, run.total = run.units + shown.units, run.total + shown.total
	S.run = run
	local came = S.listSeq > S.bidSeq -- a list arrived between PlaceBid and this event
	Done(("Bought %d for %s. The list is old: search again."):format(run.units, Money(run.total)))
	S.afterBuy = true
	if came then
		for _, r in ipairs(AHBuy.ReadRows(S.target.itemID, false)) do
			if r.auctionID == shown.auctionID then
				return -- that list still holds the bought auction: it is the old one
			end
		end
		S.phase, S.afterBuy = "ready", false
		S.message = ("Bought %d for %s"):format(run.units, Money(run.total))
		Changed()
	end
end)
-- An error never retries anything. While a purchase is out or a search is waiting it frees the panel and says
-- which error it was; at any other time it belongs to something else and is ignored.
ns.On("AUCTION_HOUSE_SHOW_ERROR", function(_, err)
	if not (S.busy or S.phase == "quoting" or S.phase == "searching") then
		return
	end
	local text
	if AuctionHouseUtil and AuctionHouseUtil.GetErrorText then
		local ok, res = pcall(AuctionHouseUtil.GetErrorText, err)
		text = ok and res or nil
	end
	if S.phase == "buying" and not S.isCommodity and S.shown and S.shown.auctionID then
		S.errored = { auctionID = S.shown.auctionID, units = S.shown.units, total = S.shown.total, err = err }
	end
	if S.phase == "quoting" and C_AuctionHouse.CancelCommoditiesPurchase then
		C_AuctionHouse.CancelCommoditiesPurchase()
	end
	Done(("%s (error %s). Search again."):format(text or "The auction house refused", tostring(err)))
end)

----------------------------------------------------------------------------------------------------
-- The lines: flips first, then the AH lines of the basket
----------------------------------------------------------------------------------------------------

-- { { kind, itemID, need, maxUnit, sell } }. A flip is bought up to the units still missing (bags count) at
-- its max price (vendor price - 1c); a basket line up to its quantity, no max price.
function AHBuy.Lines(plan)
	local out = {}
	if not ns.Basket then
		return out
	end
	for _, f in ipairs(ns.Basket.Flips()) do
		local missing = f.units - ns.Basket.FlipHeld(f)
		if missing > 0 then
			out[#out + 1] = { kind = "flip", itemID = f.itemID, need = missing, maxUnit = f.maxUnit, sell = f.sell,
				each = f.each, buys = f.single and missing or f.buys, single = f.single } -- #339: shown on the line only
		end
	end
	for _, l in ipairs((plan or ns.Basket.Plan()).split.auction) do
		out[#out + 1] = { kind = "basket", itemID = l.itemID, need = l.quantity }
	end
	if ns.Snipe then
		out = ns.Snipe.Merge(out) -- his typed max price wins; the snipe list comes first
	end
	return out
end

----------------------------------------------------------------------------------------------------
-- The keys (#315, part 2)
----------------------------------------------------------------------------------------------------

-- One press = one action: runs fn on "down" only, and ignores a "down" while the key is still held. keystate is
-- nil when something calls the global without a key (a macro): that is a press too and keeps no state.
local function Press(key, keystate, fn)
	if keystate == "up" then
		held[key] = nil
		return false
	end
	if keystate ~= nil and keystate ~= "down" then
		return false
	end
	if keystate == "down" then
		if held[key] then
			return false
		end
		held[key] = true
	end
	return fn()
end

function AHBuy.KeySearch(keystate)
	return Press("search", keystate, AHBuy.Next)
end

function AHBuy.KeyBuy(keystate)
	return Press("buy", keystate, AHBuy.Click)
end

_G.BINDING_NAME_CRAFTWISE_AH_SEARCH = "AH: search next"
_G.BINDING_NAME_CRAFTWISE_AH_BUY = "AH: buy best"
_G.BINDING_NAME_CRAFTWISE_AH_CHECK = "AH: check my auctions now"
function CraftWise_AHSearchKey(keystate)
	return AHBuy.KeySearch(keystate)
end
function CraftWise_AHBuyKey(keystate)
	return AHBuy.KeyBuy(keystate)
end

-- The snipe list changed (a max price, a limit or a removal): what the picked line was bought for is out of date,
-- so it is dropped and has to be picked and searched again. A purchase that is already out is left alone.
ns.Listen("SNIPE_CHANGED", function()
	if S.busy or not S.target then
		return
	end
	DropQuote()
	S.target, S.shown, S.quote, S.phase, S.isCommodity = nil, nil, nil, "idle", nil
	S.message = "The snipe list changed: pick the line again"
	Changed()
end)
