-- Purchase and sale log (issue #46): what this account bought and sold, at the AH and at vendors.
-- Only transactions made in game; nothing is estimated. Feeds the "paid cost" basis (#47) and
-- `/craftwise ledger` (start money, spent and received per item, net, checked against GetMoney()).
--
-- Storage: CraftWiseMarketDB.ledger (decision 4 on #46: no new SavedVariables)
--   entries = { { t, c = charKey, k = kind, i = itemID, q = quantity, m = copper (total), w = where,
--                 n = item name, l = item link (both when the client had them at record time, #59) }, ... }
--     kind: "ahbuy" (w = house key), "vbuy" (w = merchant name), "vsell" (w = merchant name),
--           "buyback" (w = merchant name; takes back a vendor sale). Kept 30 days (decision 3).
--     AH sales arrive by mail; they are #26 phase 3 and will be added here as kind "ahsell".
--   chars[charKey] = {          charKey = ns.CharKey(), "<realm>-<name> <surname>" (#77)
--     reset   = { t, money },   since the last `/craftwise ledger reset` (or since the log started)
--     session = { t, money },   since login (kept across /reload)
--     days    = { ["YYYY-MM-DD"] = money at the start of that day },  30 days
--     pos     = { [itemID] = { held, known, cost, transit, ahKnown, ahCost } },  paid cost of the units still held
--               (ahKnown and ahCost: the part of known and cost that came from AH purchases, for the flips, #330)
--   }
--
-- Paid cost (decision 2): quantity-weighted average of what was paid for the units still held.
-- held = units in bags and bank when last counted; transit = bought units not counted yet (AH
-- purchases are delivered later); known = units with a recorded price, cost = what they cost.
-- Units that leave (crafted, sold, mailed) take the average with them, so the average stays. Units
-- that arrive without a logged purchase (loot, mail, units from before the log) have no price: while
-- any are held, the paid cost is the average of the logged units only, flagged partial with known
-- and units ("4 of 6 units", decision 2 on #47). Never extrapolated to the other units.
--
-- Vendor trades are read from bag and money changes while a merchant is open, so every way of
-- buying (right-click, drag to a bag, split stack) and selling (right-click, drag, Sell junk) counts.
-- BuyMerchantItem would miss the drag purchase (Blizzard's MerchantItemButton_OnClick picks the
-- item up with PickupMerchantItem). Money without item changes is a repair (or other cost), items
-- without money are no trade; a buyback is told apart by the buyback list getting shorter.
local _, ns = ...

local L = {}
ns.Ledger = L

local KEEP_DAYS = 30
local DAY_SECONDS = 86400
local SETTLE_SECONDS = 0.5 -- bag and money events of one trade arrive close together
local SETTLE_TRIES = 3 -- money without items (or items without money) waits this many rounds for the other half
local DAY_ROWS = 7

L.VIEWS = { "reset", "today", "login" }
L.VIEW_LABELS = { reset = "since last reset", today = "today", login = "since login" }
L.KIND_LABELS = { ahbuy = "AH", vbuy = "vendor", vsell = "vendor", buyback = "buyback" }

local store -- CraftWiseMarketDB.ledger

----------------------------------------------------------------------------------------------------
-- Keys and time
----------------------------------------------------------------------------------------------------

-- "<realm>-<name> <surname>" (#77, ns.CharKey in Core.lua).
function L.CharKey()
	return ns.CharKey()
end

function L.DayKey(t)
	return date("%Y-%m-%d", t or time())
end

local function Char(key)
	key = key or L.CharKey()
	if not (store and key) then
		return nil
	end
	local c = store.chars[key]
	if not c then
		c = { days = {}, pos = {} }
		store.chars[key] = c
	end
	c.days, c.pos = c.days or {}, c.pos or {}
	return c
end

-- Money carried now. At logout the client returns 0 (#123): then the money last seen in the world,
-- nil when none was seen (ns.PlayerValue in Core.lua).
local function CurrentMoney()
	return ns.PlayerValue("money", GetMoney())
end
L.CurrentMoney = CurrentMoney

-- Money right now; also notes the start of the day the first time a day is seen.
local lastMoney
local function NoteMoney(before)
	local c = Char()
	if not c then
		return
	end
	local now = CurrentMoney()
	if now == nil then
		return -- logout without money ever seen: nothing is written
	end
	local today = L.DayKey()
	if c.days[today] == nil then
		c.days[today] = before or now
	end
	if not c.reset then
		c.reset = { t = time(), money = before or now }
	end
	lastMoney = now
end

----------------------------------------------------------------------------------------------------
-- Positions: paid cost of the units still held
----------------------------------------------------------------------------------------------------

-- Units of an item this character holds (bags, reagent bag and bank).
function L.HeldCount(itemID)
	return C_Item.GetItemCount(itemID, true, false, true) or 0
end

local busy = {} -- [itemID] = true while an AH purchase of it is on its way (counts wait)
local merchant -- open merchant window, see below

-- Brings a position up to `count` units held. Arrivals first fill the bought units in transit; the
-- rest have no price. Departures take the average paid cost with them.
local function Sync(p, count)
	local held = p.held or 0
	if count > held then
		local arrived = count - held
		p.transit = math.max((p.transit or 0) - arrived, 0)
	elseif count < held then
		local knownHeld = math.max(p.known - (p.transit or 0), 0)
		local leaving = knownHeld * (held - count) / held
		if p.known > 0 then
			p.cost = p.cost * (p.known - leaving) / p.known
			local keep = (p.known - leaving) / p.known
			p.ahKnown, p.ahCost = (p.ahKnown or 0) * keep, (p.ahCost or 0) * keep
		end
		p.known = p.known - leaving
	end
	p.held = count
end

local function Position(c, itemID, before)
	local p = c.pos[itemID]
	if not p then
		p = { held = before or 0, known = 0, cost = 0, transit = 0, ahKnown = 0, ahCost = 0 }
		c.pos[itemID] = p
	elseif before then
		Sync(p, before)
	end
	return p
end

-- Counts every item with a position again (after bag changes).
-- While a merchant is open, the trade settle counts (force) so purchases aren't taken for loot.
function L.SyncAll(force)
	local c = Char()
	if not c or (merchant and not force) then
		return
	end
	for itemID, p in pairs(c.pos) do
		if not busy[itemID] then
			Sync(p, L.HeldCount(itemID))
			if p.held == 0 and (p.transit or 0) == 0 then
				c.pos[itemID] = nil
			end
		end
	end
end

-- The units of a vendor sale that have a logged AH cost (#330): `quantity` units leave, the position says how
-- many of them were bought at the AH and what those cost (the average of the AH purchases still held). Read
-- only (the position itself moves with the next count). Returns units, cost; nil when none has an AH cost.
function L.FlipShare(itemID, quantity, charKey)
	local c = store and store.chars[charKey or L.CharKey() or ""]
	local p = c and c.pos and c.pos[itemID]
	if not (p and quantity and quantity > 0) or (p.ahKnown or 0) <= 1e-6 or p.known <= 1e-6 or (p.held or 0) <= 0 then
		return nil
	end
	local leaving = math.max(p.known - (p.transit or 0), 0) * math.min(quantity, p.held) / p.held
	local units = math.min(math.floor(p.ahKnown * leaving / p.known + 0.5), quantity)
	if units <= 0 then
		return nil
	end
	return units, math.floor(p.ahCost / p.ahKnown * units + 0.5)
end

-- Puts units with a known AH cost back into the position (a buyback of a sale that was a flip, #330).
function L.RestoreAH(itemID, units, cost, before)
	local c = Char()
	if not (c and units and units > 0 and cost) then
		return
	end
	local p = Position(c, itemID, before or L.HeldCount(itemID))
	p.known, p.cost, p.transit = p.known + units, p.cost + cost, (p.transit or 0) + units
	p.ahKnown, p.ahCost = (p.ahKnown or 0) + units, (p.ahCost or 0) + cost
	Sync(p, L.HeldCount(itemID))
end

-- Paid cost of one unit: { copper, known, units, complete, partial } or nil when nothing logged is
-- held. copper is the average of the logged units; partial (= not complete) while units without a
-- recorded price are held too: then it covers `known` of the `units` held.
function L.PaidCost(itemID, charKey)
	local c = store and store.chars[charKey or L.CharKey() or ""]
	local p = c and c.pos and c.pos[itemID]
	if not p or p.known <= 1e-6 then
		return nil
	end
	local units = (p.held or 0) + (p.transit or 0)
	local known = math.min(p.known, units)
	local complete = known >= units - 1e-6
	return { copper = p.cost / p.known, known = known, units = units, complete = complete, partial = not complete }
end

----------------------------------------------------------------------------------------------------
-- Log
----------------------------------------------------------------------------------------------------

-- Adds one transaction. before: units held before it (positions start there); nil = count now.
function L.Record(kind, itemID, quantity, copper, where, before)
	local charKey = L.CharKey()
	local c = Char(charKey)
	if not (c and itemID and quantity and quantity > 0 and copper) then
		return nil
	end
	local name, link = ns.ItemInfoNow(itemID) -- kept so later prints don't depend on the item cache (#59)
	local entry = { t = time(), c = charKey, k = kind, i = itemID, q = quantity, m = copper, w = where, n = name, l = link }
	store.entries[#store.entries + 1] = entry
	if kind == "ahbuy" or kind == "vbuy" then
		local p = Position(c, itemID, before or L.HeldCount(itemID))
		p.known, p.cost, p.transit = p.known + quantity, p.cost + copper, (p.transit or 0) + quantity
		if kind == "ahbuy" then
			p.ahKnown, p.ahCost = (p.ahKnown or 0) + quantity, (p.ahCost or 0) + copper
		end
		if not busy[itemID] then
			Sync(p, L.HeldCount(itemID))
		end
	end
	ns.Notify("LEDGER_CHANGED", entry)
	return entry
end

function L.Entries()
	return store and store.entries or {}
end

function L.Prune(now)
	if not store then
		return
	end
	now = now or time()
	local cutoff = now - KEEP_DAYS * DAY_SECONDS
	local kept = {}
	for _, e in ipairs(store.entries) do
		if e.t >= cutoff then
			kept[#kept + 1] = e
		end
	end
	store.entries = kept
	local oldestDay = L.DayKey(cutoff)
	for _, c in pairs(store.chars) do
		for day in pairs(c.days or {}) do
			if day < oldestDay then
				c.days[day] = nil
			end
		end
	end
end

----------------------------------------------------------------------------------------------------
-- Summaries
----------------------------------------------------------------------------------------------------

-- Totals of the current character's entries from `since` (time) to `untilT` (exclusive, nil = now).
local function Totals(since, untilT)
	local charKey = L.CharKey()
	local items, order = {}, {}
	local spent, received = 0, 0
	for _, e in ipairs(L.Entries()) do
		if e.c == charKey and e.t >= since and (not untilT or e.t < untilT) then
			local row = items[e.i]
			if not row then
				row = { itemID = e.i, bought = 0, spent = 0, sold = 0, received = 0, sources = {} }
				items[e.i] = row
				order[#order + 1] = row
			end
			row.name, row.link = e.n or row.name, e.l or row.link -- the newest entry that has them
			if e.k == "ahbuy" or e.k == "vbuy" then
				row.bought, row.spent = row.bought + e.q, row.spent + e.m
				row.sources[L.KIND_LABELS[e.k]] = true
				spent = spent + e.m
			elseif e.k == "vsell" or e.k == "ahsell" then
				row.sold, row.received = row.sold + e.q, row.received + e.m
				received = received + e.m
			elseif e.k == "buyback" then -- a sale taken back
				row.sold, row.received = row.sold - e.q, row.received - e.m
				received = received - e.m
			end
		end
	end
	table.sort(order, function(a, b)
		return (a.spent + a.received) > (b.spent + b.received)
	end)
	return { items = order, spent = spent, received = received, net = received - spent }
end

local function DayStart(day)
	local y, m, d = day:match("^(%d+)-(%d+)-(%d+)$")
	return time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 0 })
end

-- One view: { view, label, since, startMoney, money, change, spent, received, net, other, items, days }.
-- other = money change not explained by logged trades (loot, quests, repairs, fees, AH sales by mail).
function L.Summary(view)
	local c = Char()
	if not c then
		return nil
	end
	NoteMoney()
	if not c.reset then
		return nil -- money never seen (logout before it was): no ledger for this character yet
	end
	view = view or L.View()
	local since, startMoney
	if view == "login" then
		local s = c.session or c.reset
		since, startMoney = s.t, s.money
	elseif view == "today" then
		local today = L.DayKey()
		since, startMoney = DayStart(today), c.days[today]
	else
		view = "reset"
		since, startMoney = c.reset.t, c.reset.money
	end
	local sum = Totals(since)
	sum.view, sum.label, sum.since, sum.startMoney = view, L.VIEW_LABELS[view], since, startMoney
	sum.money = CurrentMoney()
	if startMoney and sum.money then
		sum.change = sum.money - startMoney
		sum.other = sum.change - sum.net
	end
	if view == "today" then
		sum.days = L.Days()
	end
	return sum
end

-- Per-day rows, newest first: { day, startMoney, endMoney, change, spent, received, net, other }.
-- A day ends with the money the next recorded day started with (money doesn't change offline).
function L.Days(limit)
	local c = Char()
	if not c then
		return {}
	end
	local keys = {}
	for day in pairs(c.days) do
		keys[#keys + 1] = day
	end
	table.sort(keys)
	local rows = {}
	for i, day in ipairs(keys) do
		local nextDay = keys[i + 1]
		local sum = Totals(DayStart(day), nextDay and DayStart(nextDay) or nil)
		local endMoney = nextDay and c.days[nextDay] or CurrentMoney()
		local row = { day = day, startMoney = c.days[day], endMoney = endMoney, spent = sum.spent, received = sum.received, net = sum.net }
		if endMoney then
			row.change = endMoney - row.startMoney
			row.other = row.change - row.net
		end
		table.insert(rows, 1, row)
	end
	while limit and #rows > limit do
		table.remove(rows)
	end
	return rows
end

function L.View()
	local v = ns.db and ns.db.settings.ledgerView
	return L.VIEW_LABELS[v] and v or "reset"
end

function L.Reset()
	local c = Char()
	if not c then
		return
	end
	c.reset = { t = time(), money = GetMoney() }
end

----------------------------------------------------------------------------------------------------
-- /craftwise ledger [reset | login | today | all]
----------------------------------------------------------------------------------------------------

local function Money(copper)
	if copper == nil then
		return "unknown"
	end
	return ns.FormatMoney(copper)
end

local function Signed(copper)
	if copper == nil then
		return "unknown"
	end
	return (copper > 0 and "+" or "") .. ns.FormatMoney(copper)
end

-- Entries recorded without a name (item not cached then, or logged before #59) get it once known.
local function RememberNames(itemID)
	local name, link = ns.ItemInfoNow(itemID)
	if not name then
		return
	end
	for _, e in ipairs(L.Entries()) do
		if e.i == itemID and not e.n then
			e.n, e.l = name, e.l or link
		end
	end
end

local function PrintSummary(sum)
	ns.Print(("Ledger, %s: start %s, now %s, money change %s"):format(sum.label, Money(sum.startMoney),
		Money(sum.money), Signed(sum.change)))
	for _, row in ipairs(sum.items) do
		local parts = {}
		if row.bought > 0 then
			local where = {}
			for label in pairs(row.sources) do
				where[#where + 1] = label
			end
			table.sort(where)
			parts[#parts + 1] = ("bought %d for %s (%s)"):format(row.bought, Money(row.spent), table.concat(where, ", "))
		end
		if row.sold ~= 0 or row.received ~= 0 then
			parts[#parts + 1] = ("sold %d for %s"):format(row.sold, Money(row.received))
		end
		ns.Print(("  %s: %s"):format(ns.ItemChatText(row.itemID, { name = row.name, link = row.link }), table.concat(parts, "; ")))
	end
	ns.Print(("  spent %s, received %s, net %s"):format(Money(sum.spent), Money(sum.received), Signed(sum.net)))
	if sum.other then
		if sum.other == 0 then
			ns.Print("  net matches the money change")
		else
			ns.Print(("  not from logged trades: %s (loot, quests, repairs, fees, AH sales by mail)"):format(Signed(sum.other)))
		end
	end
	if sum.days then
		ns.Print("  per day:")
		for i, d in ipairs(sum.days) do
			if i > DAY_ROWS then
				break
			end
			ns.Print(("  %s: start %s, spent %s, received %s, net %s, money change %s"):format(d.day, Money(d.startMoney),
				Money(d.spent), Money(d.received), Signed(d.net), Signed(d.change)))
		end
	end
end

-- Prints the view as it is now; items whose name isn't known yet are loaded first (#59).
function L.Print(view)
	local sum = L.Summary(view)
	if not sum then
		ns.Print("ledger: character not known yet")
		return
	end
	local ids, stored = {}, {}
	for _, row in ipairs(sum.items) do
		ids[#ids + 1] = row.itemID
		stored[row.itemID] = row.name ~= nil
	end
	ns.WithItemNames(ids, function()
		for _, itemID in ipairs(ids) do
			if not stored[itemID] then
				RememberNames(itemID)
			end
		end
		PrintSummary(sum)
	end, function(itemID)
		return stored[itemID]
	end)
end

function L.Slash(arg)
	arg = (arg or ""):match("^%s*(.-)%s*$")
	if arg == "reset" then
		L.Reset()
		ns.Print("ledger reset: the \"since last reset\" view starts now")
		return
	end
	local view = ({ login = "login", session = "login", today = "today", day = "today", all = "reset", since = "reset" })[arg]
	if arg ~= "" and not view then
		ns.Print("usage: /craftwise ledger [login | today | all | reset]")
		return
	end
	if view and ns.db then
		ns.db.settings.ledgerView = view
	end
	L.Print(view)
end

----------------------------------------------------------------------------------------------------
-- Auction house purchases: the price comes from the purchase the player started (the events carry
-- none). Commodities: StartCommoditiesPurchase -> COMMODITY_PRICE_UPDATED (quote for exactly that
-- quantity) -> ConfirmCommoditiesPurchase -> COMMODITY_PURCHASE_SUCCEEDED | _FAILED. Items:
-- PlaceBid at the buyout -> AUCTION_HOUSE_PURCHASE_COMPLETED. Bids below the buyout are no
-- purchase; a won bid arrives by mail (#26 phase 3).
----------------------------------------------------------------------------------------------------

local commodity -- { itemID, quantity, total, before, money, confirmed }
local bids = {} -- [auctionID] = { itemID, quantity, copper, before }

local function House()
	local key = ns.Market and ns.Market.DetectHouse()
	return key
end

function L.OnStartCommodities(itemID, quantity)
	commodity = { itemID = itemID, quantity = quantity }
end

function L.OnCommodityPrice(_, unitPrice, totalPrice)
	if commodity and not commodity.confirmed then
		commodity.total = totalPrice
	end
end

function L.OnConfirmCommodities(itemID, quantity)
	if not commodity or commodity.itemID ~= itemID then
		commodity = { itemID = itemID }
	end
	commodity.quantity, commodity.confirmed = quantity, true
	commodity.before, commodity.money = L.HeldCount(itemID), GetMoney()
	busy[itemID] = true
end

function L.OnCommoditySucceeded()
	local p = commodity
	commodity = nil
	if not (p and p.confirmed) then
		return
	end
	busy[p.itemID] = nil
	-- The quote is the server's price for exactly this quantity; without one, the money that left.
	local total = p.total
	if not total and p.money and GetMoney() < p.money then
		total = p.money - GetMoney()
	end
	if total then
		L.Record("ahbuy", p.itemID, p.quantity, total, House(), p.before)
	end
end

function L.OnCommodityFailed()
	if commodity then
		busy[commodity.itemID] = nil
	end
	commodity = nil
end

-- Trace of the item purchase path (#337): every step of a buy is kept (newest last) so the next buy in game
-- shows which step failed. `/craftwise debug` prints it, `/craftwise debug ledger` echoes new lines live.
local TRACE_LINES = 40

function L.Trace(...)
	local d = ns.db and ns.db.debug
	if not d then
		return
	end
	local parts = {}
	for i = 1, select("#", ...) do
		parts[i] = tostring((select(i, ...)))
	end
	local line = date("%H:%M:%S ") .. table.concat(parts, " ")
	d.ledgerTrace = d.ledgerTrace or {}
	d.ledgerTrace[#d.ledgerTrace + 1] = line
	while #d.ledgerTrace > TRACE_LINES do
		table.remove(d.ledgerTrace, 1)
	end
	if d.ledgerLive then
		ns.Print("ledger: " .. line)
	end
end

function L.TraceLines()
	local d = ns.db and ns.db.debug
	return d and d.ledgerTrace or {}
end

function L.ToggleTraceLive()
	local d = ns.db and ns.db.debug
	if not d then
		return nil
	end
	d.ledgerLive = not d.ledgerLive
	return d.ledgerLive
end

-- Where an item buyout's price comes from: the item search rows. Blizzard's ItemBuyFrame lists
-- GetItemSearchResultInfo rows (auctionID, quantity, buyoutAmount) and calls PlaceBid with the selected
-- row's auctionID and buyoutAmount (Blizzard_AuctionHouseBuyDialog / Frame.lua, BUYOUT_AUCTION). The
-- keys to read them with: CraftWise's own buy target, Blizzard's ItemBuyFrame key, the latest searches.
local recentKeys = {} -- item keys of the latest ITEM_SEARCH_RESULTS_UPDATED / _ADDED, newest first
local MAX_KEYS = 8

local function SameKey(a, b)
	return a.itemID == b.itemID and (a.itemLevel or 0) == (b.itemLevel or 0) and (a.itemSuffix or 0) == (b.itemSuffix or 0)
end

local function NoteKey(_, key)
	if type(key) ~= "table" or not key.itemID then
		return
	end
	for i, k in ipairs(recentKeys) do
		if SameKey(k, key) then
			table.remove(recentKeys, i)
			break
		end
	end
	table.insert(recentKeys, 1, key)
	while #recentKeys > MAX_KEYS do
		table.remove(recentKeys)
	end
end

local function Candidates()
	local out = {}
	local target = ns.AHBuy and ns.AHBuy.state and ns.AHBuy.state.target
	if target and target.itemID and C_AuctionHouse.MakeItemKey then
		out[#out + 1] = { src = "CraftWise buy target", key = C_AuctionHouse.MakeItemKey(target.itemID) }
	end
	local frame = _G.AuctionHouseFrame and _G.AuctionHouseFrame.ItemBuyFrame
	if frame and frame.itemKey then
		out[#out + 1] = { src = "Blizzard ItemBuyFrame", key = frame.itemKey }
	end
	for _, key in ipairs(recentKeys) do
		out[#out + 1] = { src = "last item search", key = key }
	end
	return out
end

local function RowIn(key, auctionID)
	for i = 1, C_AuctionHouse.GetNumItemSearchResults(key) or 0 do
		local row = C_AuctionHouse.GetItemSearchResultInfo(key, i)
		if row and row.auctionID == auctionID then
			return row
		end
	end
end

-- The auction row the player bought from: itemID, quantity, buyout, where it was found. The search rows
-- come first; GetAuctionInfoByID is the fallback (it has no quantity: the row of its key supplies it).
local function FindAuction(auctionID)
	for _, c in ipairs(Candidates()) do
		local row = RowIn(c.key, auctionID)
		L.Trace("auction", auctionID, "in", c.src, "item", c.key.itemID, row and "found" or "not found")
		if row and row.quantity and row.buyoutAmount then
			return c.key.itemID, row.quantity, row.buyoutAmount, c.src
		end
	end
	local info = C_AuctionHouse.GetAuctionInfoByID and C_AuctionHouse.GetAuctionInfoByID(auctionID)
	local key = info and info.itemKey
	L.Trace("auction", auctionID, "GetAuctionInfoByID", key and ("item " .. tostring(key.itemID)) or "nil")
	if not key then
		return nil
	end
	local row = RowIn(key, auctionID)
	return key.itemID, row and row.quantity, info.buyoutAmount or (row and row.buyoutAmount), "GetAuctionInfoByID"
end

-- Pending bids older than this are dropped (clean-up only: a bid is logged when its completion arrives).
local BID_TIMEOUT = 60

function L.ExpireBids()
	for id, b in pairs(bids) do
		if GetTime() - (b.at or 0) > BID_TIMEOUT then
			L.Trace("pending purchase of auction", id, "dropped after", BID_TIMEOUT, "s")
			busy[b.itemID] = nil
			bids[id] = nil
		end
	end
end

function L.OnPlaceBid(auctionID, bidAmount)
	L.Trace("PlaceBid", auctionID, "bid", bidAmount)
	local itemID, rowQuantity, buyout, src = FindAuction(auctionID)
	-- One PlaceBid buys ONE purchase and pays the row's buyoutAmount, whatever the row's `quantity` says: in
	-- Forever a row groups identical auctions and `quantity` counts how many are listed at that price (#343,
	-- Plans: Shadow Crescent Axe, row 26, one PlaceBid, one plan). Blizzard's list shows the same number in
	-- its own Quantity column beside the buyout (Blizzard_AuctionHouseTableBuilder.lua, ItemQuantity cell).
	-- An item that doesn't stack is 1 unit; for a stackable the units of one purchase are unknown: not logged.
	local quantity
	if itemID and rowQuantity then
		local stack = C_Item and C_Item.GetItemMaxStackSizeByID and C_Item.GetItemMaxStackSizeByID(itemID)
		if stack == 1 then
			quantity = 1
		else
			L.Trace("PlaceBid", auctionID, "item", itemID, "max stack", stack, ": units of one purchase unknown")
		end
	end
	if not (itemID and quantity and buyout and bidAmount and bidAmount >= buyout) then
		-- a bid, or the auction isn't in any results we can read: nothing to log, no price is guessed
		L.Trace("PlaceBid", auctionID, "not logged: item", itemID, "quantity", quantity, "buyout", buyout)
		return
	end
	-- The row's buyout is what the server takes for a bid at or above it.
	L.ExpireBids()
	bids[auctionID] = { itemID = itemID, quantity = quantity, copper = buyout, before = L.HeldCount(itemID), at = GetTime() }
	busy[itemID] = true
	L.Trace("PlaceBid", auctionID, "pending: item", itemID, "x", quantity, "for", buyout, "from", src)
end

function L.OnPurchaseCompleted(_, auctionID)
	L.ExpireBids()
	local b = bids[auctionID]
	if not b then
		L.Trace("AUCTION_HOUSE_PURCHASE_COMPLETED", auctionID, "no pending PlaceBid for it")
		return
	end
	bids[auctionID] = nil
	busy[b.itemID] = nil
	L.Record("ahbuy", b.itemID, b.quantity, b.copper, House(), b.before)
	L.Trace("AUCTION_HOUSE_PURCHASE_COMPLETED", auctionID, "logged ahbuy item", b.itemID, "x", b.quantity, "for", b.copper)
end

----------------------------------------------------------------------------------------------------
-- Vendor trades
----------------------------------------------------------------------------------------------------

local function BagCounts()
	local counts = {}
	for bag = 0, ns.LAST_BAG do
		for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
			local item = C_Container.GetContainerItemInfo(bag, slot)
			if item and item.itemID then
				counts[item.itemID] = (counts[item.itemID] or 0) + (item.stackCount or 1)
			end
		end
	end
	return counts
end

local function Changes(before, after)
	local gains, losses = {}, {}
	for itemID, n in pairs(after) do
		local d = n - (before[itemID] or 0)
		if d > 0 then
			gains[#gains + 1] = { itemID = itemID, quantity = d }
		end
	end
	for itemID, n in pairs(before) do
		local d = n - (after[itemID] or 0)
		if d > 0 then
			losses[#losses + 1] = { itemID = itemID, quantity = d }
		end
	end
	table.sort(gains, function(a, b) return a.itemID < b.itemID end)
	table.sort(losses, function(a, b) return a.itemID < b.itemID end)
	return gains, losses
end

-- Splits the money of one settle over the items. One item gets its listed price when known (the
-- rest of the money, e.g. a repair in the same moment, is no trade), else all of it. Several items
-- need every price, and the prices must add up to the money; otherwise nothing is logged.
function L.Attribute(changes, total, unitPrice)
	if #changes == 1 then
		local ch = changes[1]
		local unit = unitPrice(ch.itemID)
		local amount = unit and math.floor(unit * ch.quantity + 0.5)
		if not amount or amount > total then
			amount = total
		end
		ch.copper = amount
		return changes
	end
	local sum = 0
	for _, ch in ipairs(changes) do
		local unit = unitPrice(ch.itemID)
		if not unit then
			return nil
		end
		ch.copper = math.floor(unit * ch.quantity + 0.5)
		sum = sum + ch.copper
	end
	if math.abs(sum - total) > #changes then
		return nil
	end
	return changes
end

local function BuybackCount()
	return GetNumBuybackItems and GetNumBuybackItems() or 0
end

local function Snapshot(m)
	m.money, m.counts, m.buyback, m.tries = GetMoney(), BagCounts(), BuybackCount(), 0
end

local function Settle()
	local m = merchant
	if not m then
		return
	end
	m.timer = nil
	local money, counts = GetMoney(), BagCounts()
	local dMoney = money - m.money
	local gains, losses = Changes(m.counts, counts)
	local itemsChanged = #gains > 0 or #losses > 0
	if (dMoney ~= 0) ~= itemsChanged and m.tries < SETTLE_TRIES and not m.closing then
		m.tries = m.tries + 1 -- one half of a trade is here; wait for the other
		m.timer = C_Timer.NewTimer(SETTLE_SECONDS, Settle)
		return
	end
	local logged
	if dMoney < 0 and #gains > 0 and #losses == 0 then
		local buyback = BuybackCount() < m.buyback
		if buyback then
			logged = L.Attribute(gains, -dMoney, ns.GetVendorSellPrice)
		else
			logged = L.Attribute(gains, -dMoney, function(itemID)
				return m.prices[itemID]
			end)
		end
		for _, ch in ipairs(logged or {}) do
			if buyback or not m.extended[ch.itemID] then -- items paid with currency or tokens are no gold trade
				local before = L.HeldCount(ch.itemID) - ch.quantity
				L.Record(buyback and "buyback" or "vbuy", ch.itemID, ch.quantity, ch.copper, m.name, before)
				if buyback and ns.Flips then -- a flip taken back is no flip (#330)
					local units, cost = ns.Flips.Undo(ch.itemID, ch.quantity)
					if units then
						L.RestoreAH(ch.itemID, units, cost, before)
					end
				end
			end
		end
	elseif dMoney > 0 and #losses > 0 and #gains == 0 then
		logged = L.Attribute(losses, dMoney, ns.GetVendorSellPrice)
		for _, ch in ipairs(logged or {}) do
			if ns.Flips then -- before the record: the position still holds the units (#330)
				local units, cost = L.FlipShare(ch.itemID, ch.quantity)
				if units then
					ns.Flips.Record(ch.itemID, ch.quantity, ch.copper, m.name, units, cost)
				end
			end
			L.Record("vsell", ch.itemID, ch.quantity, ch.copper, m.name)
		end
	end
	Snapshot(m)
	L.SyncAll(true)
end

local function Schedule()
	if not merchant then
		return
	end
	if merchant.timer then
		merchant.timer:Cancel()
	end
	merchant.tries = 0
	merchant.timer = C_Timer.NewTimer(SETTLE_SECONDS, Settle)
end

function L.OnMerchantShow()
	if not store then
		return
	end
	if merchant and merchant.timer then
		merchant.timer:Cancel()
	end
	local prices, extended = ns.MerchantUnitPrices()
	merchant = { name = UnitName("npc"), prices = prices, extended = extended }
	Snapshot(merchant)
end

function L.OnMerchantUpdate()
	if merchant then
		merchant.prices, merchant.extended = ns.MerchantUnitPrices()
	end
end

function L.OnMerchantClosed()
	if not merchant then
		return
	end
	if merchant.timer then
		merchant.timer:Cancel()
	end
	merchant.closing = true
	Settle()
	merchant = nil
	L.SyncAll()
end

----------------------------------------------------------------------------------------------------
-- Events
----------------------------------------------------------------------------------------------------

ns.Listen("DB_READY", function()
	CraftWiseMarketDB = CraftWiseMarketDB or {}
	local db = CraftWiseMarketDB
	db.ledger = db.ledger or {}
	store = db.ledger
	store.entries = store.entries or {}
	store.chars = store.chars or {}
end)

-- #343, one time: from #338 (merged 2026-11-16 15:21 UTC) an item PlaceBid logged the row's `quantity` as
-- units; the row groups identical auctions, so one purchase of a non-stackable item was logged as many.
-- Sets those `ahbuy` entries to 1 unit, removes the phantom units still in transit from the position, and
-- re-prices the flip rows recorded from them at the corrected cost. Touches nothing else.
-- An entry is repaired when its item's stack size is known and 1; a repaired entry has q = 1 and is no longer
-- a candidate, so position and flips are corrected once per entry. An item whose stack size the client
-- doesn't know yet is requested and the pass runs again on ITEM_DATA_LOAD_RESULT or at the next login; the
-- flag is set only when no candidate was left undecided.
local FIX343_SINCE = 1794842474
local pending343 = false
local asked343 = {} -- items already asked for this session: an answer re-runs the pass, it must not ask again

function L.Migrate343()
	if not store or store.fix343 then
		return nil
	end
	local fixed = {} -- [charKey][itemID] = { phantom, units, copper, since }
	local entries, unknown = 0, {}
	for _, e in ipairs(store.entries) do
		local candidate = e.k == "ahbuy" and e.q > 1 and e.t >= FIX343_SINCE
		local stack = candidate and C_Item and C_Item.GetItemMaxStackSizeByID and C_Item.GetItemMaxStackSizeByID(e.i)
		if candidate and not stack then
			unknown[e.i] = true
		end
		if stack == 1 then
			local per = fixed[e.c] or {}
			fixed[e.c] = per
			local f = per[e.i] or { phantom = 0, units = 0, copper = 0, since = e.t }
			per[e.i] = f
			f.phantom, f.units, f.copper = f.phantom + e.q - 1, f.units + 1, f.copper + e.m
			f.since = math.min(f.since, e.t)
			e.q = 1
			entries = entries + 1
		end
	end
	local positions, rows = 0, 0
	for charKey, per in pairs(fixed) do
		local c = store.chars[charKey]
		for itemID, f in pairs(per) do
			local p = c and c.pos and c.pos[itemID]
			if p then
				local d = math.min(f.phantom, p.transit or 0)
				p.transit, p.known = (p.transit or 0) - d, math.max(p.known - d, 0)
				p.ahKnown = math.max((p.ahKnown or 0) - d, 0)
				if p.known <= 1e-6 then
					p.known, p.cost, p.ahKnown, p.ahCost = 0, 0, 0, 0
				end
				if d > 0 then
					positions = positions + 1
				end
				if p.held == 0 and (p.transit or 0) <= 1e-6 then
					c.pos[itemID] = nil
				end
			end
			if ns.Flips and ns.Flips.Reprice then
				rows = rows + ns.Flips.Reprice(itemID, charKey, f.since, f.copper / f.units)
			end
		end
	end
	pending343 = next(unknown) ~= nil
	if pending343 then
		for itemID in pairs(unknown) do
			if not asked343[itemID] then
				asked343[itemID] = true
				ns.RequestItemData(itemID, "Ledger.lua #343", true)
			end
		end
		L.Trace("migration #343: stack size not known yet for", (function() local n = 0 for _ in pairs(unknown) do n = n + 1 end return n end)(), "items, asked the client")
	else
		store.fix343 = true
	end
	if entries > 0 then
		L.Trace("migration #343: ahbuy entries set to 1 unit", entries, "positions fixed", positions, "flip rows re-priced", rows)
		ns.Print(("Ledger repair (#343): %d AH purchases set to 1 unit, %d positions, %d flips re-priced."):format(entries, positions, rows))
		ns.Notify("LEDGER_CHANGED")
	end
	return entries, positions, rows
end

ns.On("ITEM_DATA_LOAD_RESULT", function()
	if pending343 then
		L.Migrate343()
	end
end)

ns.On("PLAYER_ENTERING_WORLD", function(_, isInitialLogin)
	L.Migrate343()
	local c = Char()
	if not c then
		return
	end
	if isInitialLogin or not c.session then -- zone changes and /reload keep the session
		c.session = { t = time(), money = GetMoney() }
	end
	NoteMoney()
	L.Prune()
	L.SyncAll()
end)

ns.On("PLAYER_MONEY", function()
	NoteMoney(lastMoney)
	Schedule()
end)

ns.On("BAG_UPDATE_DELAYED", function()
	if merchant then
		Schedule()
	else
		L.SyncAll()
	end
end)

ns.On("MERCHANT_SHOW", L.OnMerchantShow)
ns.On("MERCHANT_UPDATE", L.OnMerchantUpdate)
ns.On("MERCHANT_CLOSED", L.OnMerchantClosed)
ns.On("COMMODITY_PRICE_UPDATED", L.OnCommodityPrice)
ns.On("COMMODITY_PURCHASE_SUCCEEDED", L.OnCommoditySucceeded)
ns.On("COMMODITY_PURCHASE_FAILED", L.OnCommodityFailed)
ns.On("AUCTION_HOUSE_PURCHASE_COMPLETED", L.OnPurchaseCompleted)
ns.On("ITEM_SEARCH_RESULTS_UPDATED", NoteKey)
ns.On("ITEM_SEARCH_RESULTS_ADDED", NoteKey)
-- The AH closed with a purchase unanswered: forget what was pending.
local function ForgetPending()
	for auctionID, b in pairs(bids) do
		L.Trace("pending purchase of auction", auctionID, "forgotten (error or AH closed)")
		busy[b.itemID] = nil
		bids[auctionID] = nil
	end
end
-- An error does not forget a pending bid: Forever sends error 10 (Enum.AuctionHouseError.DatabaseError,
-- "Internal auction error") between PlaceBid and AUCTION_HOUSE_PURCHASE_COMPLETED and the purchase still
-- completes (#340). The bid is logged only when its completion arrives with its auctionID.
ns.On("AUCTION_HOUSE_SHOW_ERROR", function(_, err)
	local ids = {}
	for id in pairs(bids) do
		ids[#ids + 1] = id
	end
	table.sort(ids)
	L.Trace("AUCTION_HOUSE_SHOW_ERROR error", err, #ids > 0 and ("pending bids kept: " .. table.concat(ids, ",")) or "no bid pending")
end)
ns.On("AUCTION_HOUSE_CLOSED", function()
	ForgetPending()
	L.OnCommodityFailed()
	L.SyncAll()
end)

-- The purchase calls the player starts (Blizzard's AH UI or another addon). Hooks only read the
-- arguments; nothing is called on the player's behalf.
if C_AuctionHouse and hooksecurefunc then
	hooksecurefunc(C_AuctionHouse, "StartCommoditiesPurchase", function(...) L.OnStartCommodities(...) end)
	hooksecurefunc(C_AuctionHouse, "ConfirmCommoditiesPurchase", function(...) L.OnConfirmCommodities(...) end)
	hooksecurefunc(C_AuctionHouse, "PlaceBid", function(...) L.OnPlaceBid(...) end)
end
