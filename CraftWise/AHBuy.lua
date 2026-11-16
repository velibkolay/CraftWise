-- Buying at the auction house from CraftWise (#315, part 1): search a line (a flip or an AH line of the basket),
-- read what is listed, buy with a click. Auctionator is not needed; it stays a second way (Basket.lua).
--
-- Safety (Veli's rules, #315). Gold is at stake, so the buying is kept small and in one place:
--   * C_AuctionHouse.PlaceBid, StartCommoditiesPurchase and ConfirmCommoditiesPurchase are each called once, in
--     this file (AHBuy.Execute and AHBuy.Confirm), and these two are reached only from AHBuy.Click and
--     AHBuy.Accept, which only the panel's Buy button (OnClick) and the client's confirm dialog (OnAccept)
--     call. Both are clicks. Nothing here runs on an event, a timer or a loop; no retry, no queue. A spec reads
--     the source and fails if the calls or their callers appear anywhere else.
--   * Right before each call the auction is read again: same item, unit price at most the line's max, total
--     at most what the button showed, enough gold. If anything differs nothing is bought and the panel says
--     why (the shown plan is replaced by the live one).
--   * The button shows the exact total ("Buy 12 for 3g 40s"). A total above Settings "Ask above" (default 10g)
--     asks once more with the client's confirm dialog (StaticPopup, as Blizzard's BUYOUT_AUCTION does).
--   * One purchase per click: after a call the button stays disabled until its result arrives (success or an
--     error). There is no timeout that frees it; closing the auction house does.
--   * A commodity needs two clicks: the first starts the purchase and the server answers with the price
--     (COMMODITY_PRICE_UPDATED), the second (a button of its own showing that price) confirms it. A price
--     above what the first click showed, or above the line's max, is never confirmed: it is cancelled and shown.
--   * After a purchase the results are old: the buy button stays off until the player searches again.
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
local _, ns = ...

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
	message = nil, -- what the panel says
}
AHBuy.state = S

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
	for _, r in ipairs(rows or {}) do
		if not r.own then
			if maxUnit and r.unit > maxUnit then
				break
			end
			if not isCommodity then
				return { units = r.qty, total = r.unit * r.qty, unitMax = r.unit, partial = r.qty < need, auctionID = r.auctionID,
					buyout = r.buyout or r.unit * r.qty }
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
function AHBuy.Describe(plan, why, phase, busy, money)
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
	return ("Buy %d for %s"):format(plan.units, Money(plan.total)), true
end

----------------------------------------------------------------------------------------------------
-- Reading the auction house
----------------------------------------------------------------------------------------------------

local function Throttled()
	return C_AuctionHouse and C_AuctionHouse.IsThrottledMessageSystemReady and not C_AuctionHouse.IsThrottledMessageSystemReady()
end

-- The listed rows of an item now, sorted as the client sends them, up to MAX_ROWS: { unit, qty, auctionID, own, left }.
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
			if info and info.buyoutAmount and info.buyoutAmount > 0 and (info.quantity or 0) > 0 then
				rows[#rows + 1] = { unit = math.ceil(info.buyoutAmount / info.quantity), qty = info.quantity, auctionID = info.auctionID,
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
	local plan = AHBuy.Plan(AHBuy.ReadRows(t.itemID, S.isCommodity), S.isCommodity, t.need, t.maxUnit)
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

-- Picks a line to buy; nothing is sent.
function AHBuy.Pick(line)
	if S.busy then
		return false
	end
	S.target, S.shown, S.quote, S.phase, S.isCommodity = line, nil, nil, "idle", nil
	S.message = nil
	Changed()
	return true
end

-- One search of the picked line (a click, or the key later). Returns true or false, why.
function AHBuy.Search()
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
	local key = C_AuctionHouse.MakeItemKey(t.itemID)
	local info = C_AuctionHouse.GetItemKeyInfo and C_AuctionHouse.GetItemKeyInfo(key)
	S.isCommodity = info and info.isCommodity or nil -- unknown until the answer says which kind it is
	S.phase, S.shown, S.quote, S.message = "searching", nil, nil, nil
	C_AuctionHouse.SendSearchQuery(key, Sorts(S.isCommodity), false)
	Changed()
	return true
end

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
	if plan.total > shown.total then
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
	S.busy = true
	S.message = nil
	if S.isCommodity then
		S.shown, S.phase = plan, "quoting"
		C_AuctionHouse.StartCommoditiesPurchase(plan.itemID, plan.units)
	else
		S.shown, S.phase = plan, "buying"
		C_AuctionHouse.PlaceBid(plan.auctionID, plan.buyout)
	end
	Changed()
	return true
end

-- The second click of a commodity purchase: confirms the price the server quoted, if it is still what the
-- button showed. Called only by Click.
function AHBuy.Confirm()
	local t, q, shown = S.target, S.quote, S.shown
	if S.busy or S.phase ~= "confirm" or not (t and q and shown) then
		return Refuse("Search again")
	end
	if t.maxUnit and q.unit > t.maxUnit then
		C_AuctionHouse.CancelCommoditiesPurchase()
		S.phase, S.quote = "stale", nil
		return Refuse("The price rose above your max price: not bought")
	end
	if q.total > shown.total then
		C_AuctionHouse.CancelCommoditiesPurchase()
		S.phase, S.quote = "stale", nil
		return Refuse(("The price rose to %s (you saw %s): not bought"):format(Money(q.total), Money(shown.total)))
	end
	if C_AuctionHouse.GetQuoteDurationRemaining and C_AuctionHouse.GetQuoteDurationRemaining() <= 0 then
		S.phase, S.quote = "stale", nil
		return Refuse("The price offer ran out: search again")
	end
	if GetMoney and GetMoney() < q.total then
		return Refuse("Not enough gold")
	end
	S.busy, S.phase, S.message = true, "buying", nil
	C_AuctionHouse.ConfirmCommoditiesPurchase(shown.itemID, shown.units)
	Changed()
	return true
end

local EnsureDialog -- below

-- The click on the Buy button (or the key later). Below the confirm limit it buys; above, it asks the client's
-- confirm dialog first, whose Accept calls AHBuy.Accept. Returns true, or false and why.
function AHBuy.Click()
	if S.busy then
		return false, Say("Wait for the purchase")
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
	if S.phase == "searching" then
		S.phase = "ready"
	end
	Changed()
end

ns.On("AUCTION_HOUSE_SHOW", function()
	S.open = true
	Changed()
end)
ns.On("AUCTION_HOUSE_CLOSED", function()
	S.open, S.busy, S.phase, S.shown, S.quote, S.asking = false, false, "idle", nil, nil, nil
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

-- The server's price for a started commodity purchase. Never confirmed from here: a price within what the
-- button showed waits for the player's second click, a higher one is cancelled and shown.
ns.On("COMMODITY_PRICE_UPDATED", function(_, unit, total)
	local t, shown = S.target, S.shown
	if S.phase ~= "quoting" or not (t and shown) then
		return
	end
	S.busy = false
	if (t.maxUnit and unit > t.maxUnit) or total > shown.total then
		C_AuctionHouse.CancelCommoditiesPurchase()
		S.phase, S.quote = "stale", nil
		Say(("The price is %s now (you saw %s): not bought. Search again."):format(Money(total), Money(shown.total)))
		return
	end
	S.phase, S.quote = "confirm", { unit = unit, total = total }
	S.message = nil
	Changed()
end)
ns.On("COMMODITY_PRICE_UNAVAILABLE", function()
	if S.phase ~= "quoting" then
		return
	end
	S.busy, S.phase, S.quote = false, "stale", nil
	C_AuctionHouse.CancelCommoditiesPurchase()
	Say("The auction house has no price for that any more. Search again.")
end)

local function Done(text)
	S.busy, S.phase, S.quote, S.shown = false, "stale", nil, nil
	Say(text)
end
ns.On("COMMODITY_PURCHASE_SUCCEEDED", function()
	if S.phase == "buying" then
		Done("Bought. The list is old: search again.")
	end
end)
ns.On("COMMODITY_PURCHASE_FAILED", function()
	if S.phase == "buying" or S.phase == "quoting" then
		Done("The purchase failed. Search again.")
	end
end)
ns.On("AUCTION_HOUSE_PURCHASE_COMPLETED", function()
	if S.phase == "buying" then
		Done("Bought. The list is old: search again.")
	end
end)
ns.On("AUCTION_HOUSE_SHOW_ERROR", function(_, err)
	if not (S.busy or S.phase == "quoting") then
		return
	end
	local text
	if AuctionHouseUtil and AuctionHouseUtil.GetErrorText then
		local ok, res = pcall(AuctionHouseUtil.GetErrorText, err)
		text = ok and res or nil
	end
	if S.phase == "quoting" and C_AuctionHouse.CancelCommoditiesPurchase then
		C_AuctionHouse.CancelCommoditiesPurchase()
	end
	Done((text or ("The auction house refused (error " .. tostring(err) .. ")")) .. ". Search again.")
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
			out[#out + 1] = { kind = "flip", itemID = f.itemID, need = missing, maxUnit = f.maxUnit, sell = f.sell }
		end
	end
	for _, l in ipairs((plan or ns.Basket.Plan()).split.auction) do
		out[#out + 1] = { kind = "basket", itemID = l.itemID, need = l.quantity }
	end
	return out
end
