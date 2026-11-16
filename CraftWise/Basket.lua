-- Basket (#186): the crafts the player wants to do (from Make › Craft or the vendor loop toast), and what
-- to buy for them. Data: db.basket.entries = { { recipeID, professionID, count } }.
--   * What to buy = the reagents of all crafts added together, minus what is in the bags and what can be
--     made of it, through the same buy list as the reagent tooltips (Balance.lua #49/#60), each line at
--     its cheaper source: the AH at the profit house (cheapest tiers) or a vendor (ns.BuyQuote).
--   * Expected: vendor sale and vendor profit of the crafts (#185 vendorSale/vendorProfit x count).
--   * Lines tick off by themselves: the list is recomputed from the bags (BAGS_CHANGED), so what is in
--     the bags drops out of "to buy" and shows as "in bags".
--   * Auctionator: one button builds the shopping list "CraftWise basket" from the AH lines (its API
--     v1: ConvertToSearchString, CreateShoppingList). Without Auctionator each AH line has a search string.
--   * Vendor: Basket.Buy(line) buys one line's quantity from the open merchant; the merchant window's
--     control (UI/MerchantBuy.lua, #201) buys a typed quantity through the same Basket.Purchase. Both run
--     only from a click on a Buy button; nothing here buys, lists or confirms on its own.
--   * AH → vendor flips (#312): the section "AH → vendor" (Loops.lua finds items whose cheapest AH buyouts are
--     below what a vendor pays and hands them to Basket.SetFlips after each scan). db.flips = { t, items =
--     { { itemID, units, atLeast, profit, price, sell, maxUnit } } } is replaced on every scan; a line the
--     player dismisses (db.flipDismissed[itemID] = its profit then) stays away until it gets clearly better
--     (Loops.BETTER) or goes away and comes back. Lines tick off from the bags. The Auctionator list "CraftWise
--     vendor flips" is rebuilt with each check, a max price per unit in every search string. Nothing is bought,
--     bid on or confirmed here.
-- Pure parts (Add, Remove, Combine, Split, Expected) take plain data so the specs can feed them.
local _, ns = ...

local Basket = {}
ns.Basket = Basket

Basket.LIST_NAME = "CraftWise basket"
Basket.FLIP_LIST_NAME = "CraftWise vendor flips"
Basket.CALLER = "CraftWise"
Basket.MAX_COUNT = 9999

local function Entries()
	ns.db.basket = ns.db.basket or { entries = {} }
	ns.db.basket.entries = ns.db.basket.entries or {}
	return ns.db.basket.entries
end

function Basket.Entries()
	return ns.db and Entries() or {}
end

local function Changed()
	ns.Notify("BASKET_CHANGED")
	if ns.Main and ns.Main.Refresh then
		ns.Main.Refresh()
	end
end

local function Clamp(n)
	n = math.floor(tonumber(n) or 1)
	return math.max(1, math.min(Basket.MAX_COUNT, n))
end

function Basket.Find(recipeID)
	for i, e in ipairs(Entries()) do
		if e.recipeID == recipeID then
			return e, i
		end
	end
end

-- Adds `count` crafts of a recipe (default 1); the same recipe again adds to its count.
function Basket.Add(recipeID, professionID, count)
	if not (ns.db and recipeID) then
		return nil
	end
	count = Clamp(count)
	local e = Basket.Find(recipeID)
	if e then
		e.count = Clamp(e.count + count)
	else
		e = { recipeID = recipeID, professionID = professionID, count = count }
		table.insert(Entries(), e)
	end
	Changed()
	return e
end

function Basket.SetCount(recipeID, count)
	local e = Basket.Find(recipeID)
	if not e then
		return
	end
	if (tonumber(count) or 0) < 1 then
		return Basket.Remove(recipeID)
	end
	e.count = Clamp(count)
	Changed()
end

function Basket.Remove(recipeID)
	local _, i = Basket.Find(recipeID)
	if i then
		table.remove(Entries(), i)
		Changed()
	end
end

function Basket.Clear()
	if ns.db then
		ns.db.basket = { entries = {} }
		Changed()
	end
end

----------------------------------------------------------------------------------------------------
-- Maths (pure)
----------------------------------------------------------------------------------------------------

-- items: { { reagents = { { itemID, quantity } }, count } } -> the reagents of all of them, summed per item
-- (itemID order), quantity = quantity x count.
function Basket.Combine(items)
	local sum, order = {}, {}
	for _, it in ipairs(items) do
		for _, r in ipairs(it.reagents or {}) do
			if not sum[r.itemID] then
				sum[r.itemID] = 0
				order[#order + 1] = r.itemID
			end
			sum[r.itemID] = sum[r.itemID] + r.quantity * it.count
		end
	end
	table.sort(order)
	local out = {}
	for i, id in ipairs(order) do
		out[i] = { itemID = id, quantity = sum[id] }
	end
	return out
end

-- Buy lines { { itemID, quantity, quote = { cost, source } | nil } } split by where each is cheaper:
-- { auction = {...}, vendor = {...}, unknown = {...} (no price), auctionCost, vendorCost }.
function Basket.Split(buy)
	local out = { auction = {}, vendor = {}, unknown = {}, auctionCost = 0, vendorCost = 0 }
	for _, l in ipairs(buy or {}) do
		if not l.quote then
			table.insert(out.unknown, l)
		elseif l.quote.source == "vendor" then
			table.insert(out.vendor, l)
			out.vendorCost = out.vendorCost + l.quote.cost
		else
			table.insert(out.auction, l)
			out.auctionCost = out.auctionCost + l.quote.cost
		end
	end
	return out
end

-- Expected result of the crafts: rows = { { count, vendorSale, vendorProfit } }. A craft without a vendor
-- sale or profit makes the figure unknown (nil), never 0.
function Basket.Expected(rows)
	if #rows == 0 then
		return nil, nil
	end
	local sale, profit = 0, 0
	for _, r in ipairs(rows) do
		sale = sale and r.vendorSale and (sale + r.vendorSale * r.count) or nil
		profit = profit and r.vendorProfit and (profit + r.vendorProfit * r.count) or nil
	end
	return sale, profit
end

-- How many crafts the reagents already held allow, counting only the reagents that have no vendor
-- source (the ones with a vendor price are what the player buys at the vendor, so they don't limit it).
-- reagents: { { itemID, quantity } }; held(itemID) -> count; hasVendor(itemID) -> boolean.
-- nil when every reagent has a vendor source (nothing to count); 0 when a limiting reagent is missing.
function Basket.MaxCrafts(reagents, held, hasVendor)
	local max
	for _, r in ipairs(reagents or {}) do
		if not hasVendor(r.itemID) and (r.quantity or 0) > 0 then
			local n = math.floor((held(r.itemID) or 0) / r.quantity)
			max = max and math.min(max, n) or n
		end
	end
	return max and math.min(max, Basket.MAX_COUNT) or nil
end

-- MaxCrafts for the player's bags (and the other holdings Holdings.Counter counts) and the known vendor prices.
function Basket.Max(reagents)
	if not (ns.Holdings and ns.GetVendorBuyPrice) then
		return nil
	end
	return Basket.MaxCrafts(reagents, ns.Holdings.Counter(), function(itemID)
		return ns.GetVendorBuyPrice(itemID) ~= nil
	end)
end

----------------------------------------------------------------------------------------------------
-- Plan: wiring to recipes, bags and prices
----------------------------------------------------------------------------------------------------

-- The row (ns.BuildRows) of an entry; nil when its recipe isn't known to the addon any more.
local function RowOf(e, cache, wanted)
	local rows = cache[e.professionID]
	if not rows then
		rows = {}
		for _, r in ipairs(ns.BuildRows(e.professionID, true, "profit", wanted[e.professionID])) do
			rows[r.recipeID] = r
		end
		cache[e.professionID] = rows
	end
	return rows[e.recipeID]
end

-- Everything the page shows:
-- { crafts = { { entry, row, count } }, need = combined reagents, buy = lines, split, done = { { itemID,
--   quantity, held } } (needed and already in the bags), sale, profit, missing = entries without a row }
function Basket.Plan()
	local plan = { crafts = {}, missing = {}, need = {}, buy = {}, done = {}, flips = {} }
	if not ns.db then
		return plan
	end
	local cache, items, expected = {}, {}, {}
	-- Only the basket's own recipes get a row (a profession has hundreds; building them all was the cost).
	local wanted = {}
	for _, e in ipairs(Entries()) do
		wanted[e.professionID] = wanted[e.professionID] or {}
		wanted[e.professionID][e.recipeID] = true
	end
	for _, e in ipairs(Entries()) do
		local row = RowOf(e, cache, wanted)
		if row then
			plan.crafts[#plan.crafts + 1] = { entry = e, row = row, count = e.count,
				pct = row.costComplete and ns.Profit.Percent(row.vendorProfit, row.cost) or nil }
			items[#items + 1] = { reagents = row.reagents, count = e.count }
			expected[#expected + 1] = { count = e.count, vendorSale = row.vendorSale, vendorProfit = row.vendorProfit }
		else
			plan.missing[#plan.missing + 1] = e
		end
	end
	-- Best return per gold first (#197); the sort is stable on the entry order for equal rows.
	for i, c in ipairs(plan.crafts) do
		c.i = i
	end
	local cmp = ns.Profit.ByPercent(true)
	table.sort(plan.crafts, function(a, b)
		local x, y = { pct = a.pct, profit = a.row.vendorProfit, name = a.row.name }, { pct = b.pct, profit = b.row.vendorProfit, name = b.row.name }
		if cmp(x, y) then
			return true
		elseif cmp(y, x) then
			return false
		end
		return a.i < b.i
	end)
	plan.need = Basket.Combine(items)
	if #plan.need > 0 then
		plan.balance = ns.ReagentBalance(plan.need, 1)
		plan.buy = plan.balance.buy
		local counter = ns.Holdings.Counter()
		local toBuy = {}
		for _, l in ipairs(plan.buy) do
			toBuy[l.itemID] = true
		end
		for _, n in ipairs(plan.need) do
			if not toBuy[n.itemID] then
				plan.done[#plan.done + 1] = { itemID = n.itemID, quantity = n.quantity, held = counter(n.itemID) }
			end
		end
	end
	plan.split = Basket.Split(plan.buy)
	plan.flips = Basket.Flips()
	plan.sale, plan.profit = Basket.Expected(expected)
	return plan
end

----------------------------------------------------------------------------------------------------
-- Auctionator shopping list (AH lines)
----------------------------------------------------------------------------------------------------

local function AuctionatorAPI()
	local api = Auctionator and Auctionator.API and Auctionator.API.v1
	if api and api.CreateShoppingList and api.ConvertToSearchString then
		return api
	end
end

function Basket.HasAuctionator()
	return AuctionatorAPI() ~= nil
end

-- Name of an item as Auctionator searches it; nil while the client hasn't loaded it.
local function SearchName(itemID)
	return C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID) or nil
end

-- The term of one AH line: { searchString = name, isExact = true, quantity }.
function Basket.Term(line)
	local name = SearchName(line.itemID)
	if not name then
		return nil
	end
	return { searchString = name, isExact = true, quantity = line.quantity }
end

-- Search string of one AH line, in the format Auctionator reads: "Name";;;;;;;;;;;;;qty (exact name,
-- quantity in the 14th field, tier empty), to type or paste into its search when its API isn't there.
function Basket.SearchString(line)
	local t = Basket.Term(line)
	if not t then
		return nil
	end
	return ('"%s";;;;;;;;;;;;;%d'):format(t.searchString, t.quantity)
end

-- Builds (replaces) an Auctionator shopping list from lines through `term(line)`. Returns the number of lines
-- or nil, why (allowEmpty: no lines at all empties the list). It only creates the list, searching and buying stay with the player.
local function CreateList(name, lines, term, allowEmpty)
	local api = AuctionatorAPI()
	if not api then
		return nil, "Auctionator isn't loaded"
	end
	local strings = {}
	for _, l in ipairs(lines or {}) do
		local t = term(l)
		if t then
			strings[#strings + 1] = api.ConvertToSearchString(Basket.CALLER, t)
		end
	end
	if #strings == 0 and not (allowEmpty and #(lines or {}) == 0) then
		return nil, "No AH lines with a known item name yet"
	end
	local ok, err = pcall(api.CreateShoppingList, Basket.CALLER, name, strings)
	if not ok then
		return nil, tostring(err)
	end
	return #strings
end

-- Builds (replaces) the shopping list "CraftWise basket" from the AH lines. Called from a button.
function Basket.CreateAuctionatorList(lines)
	return CreateList(Basket.LIST_NAME, lines, Basket.Term)
end

----------------------------------------------------------------------------------------------------
-- AH → vendor flips (#312)
----------------------------------------------------------------------------------------------------

function Basket.ItemName(itemID)
	return SearchName(itemID) or ("item:" .. tostring(itemID))
end

-- The lines of the section: the flips of the last check that are not dismissed.
function Basket.Flips()
	local flips = ns.db and ns.db.flips
	return flips and flips.items or {}
end

-- Replaces the section with the flips of a check (Loops.FlipCheck order). Dismissals of items that are no
-- flip any more are forgotten; a dismissed one comes back when it is clearly better. Returns the lines shown.
function Basket.SetFlips(finds)
	if not ns.db then
		return {}
	end
	local dismissed = ns.db.flipDismissed or {}
	local isFlip, shown = {}, {}
	local now = time()
	local recent, carried = ns.db.flipRecent or {}, ns.Holdings and ns.Holdings.Carried() or {}
	for itemID, r in pairs(recent) do
		if now - r.t > Basket.FLIP_RECENT then
			recent[itemID] = nil
		end
	end
	for _, f in ipairs(finds or {}) do
		isFlip[f.itemID] = true
		local was = dismissed[f.itemID]
		if was and f.profit >= was * (ns.Loops and ns.Loops.BETTER or 1.5) then
			dismissed[f.itemID] = nil
			was = nil
		end
		if not was then
			shown[#shown + 1] = f
			-- What the bags held when it first was a flip (kept while it stays one or was one lately).
			local r = recent[f.itemID]
			recent[f.itemID] = { held0 = r and r.held0 or carried[f.itemID] or 0, t = now }
		else
			recent[f.itemID] = nil
		end
	end
	ns.db.flipRecent = recent
	for itemID in pairs(dismissed) do
		if not isFlip[itemID] then
			dismissed[itemID] = nil
		end
	end
	ns.db.flipDismissed = dismissed
	ns.db.flips = { t = now, items = shown }
	Changed()
	return shown
end

----------------------------------------------------------------------------------------------------
-- Bought flips become junk (#314)
----------------------------------------------------------------------------------------------------
-- An item that arrives in the bags while it is on the flip list (or was within Basket.FLIP_RECENT: the
-- scan after a purchase drops it, and a purchase that comes by mail arrives later) gets the junk mark, so
-- "Sell junk" sells it at a merchant. How a purchase arrives on Forever is not told by Blizzard's API docs
-- (they list COMMODITY_PURCHASED / ITEM_PURCHASED / AUCTION_HOUSE_PURCHASE_COMPLETED but not where the item
-- goes), so the arrival in the bags is the signal, which covers both ways (taking it from the mail
-- counts). Never marked: an item the bags held when it became a flip, one the player marked otherwise
-- (Junk already, Sell on AH, Keep) or watches, one whose mark the player took away again, a setting off.

Basket.FLIP_RECENT = 24 * 3600 -- seconds a flip that left the list still counts for arrivals (provisional)

function Basket.MarkEnabled()
	return not (ns.db and ns.db.settings and ns.db.settings.flipJunk == false)
end

-- Is the item free to be marked? The player's own marks win.
local function Markable(itemID, held0)
	local db = ns.db
	if (held0 or 0) > 0 or (db.flipNoMark and db.flipNoMark[itemID]) then
		return false
	end
	if db.flipMarked and db.flipMarked[itemID] and not (db.junk and db.junk[itemID]) then
		db.flipNoMark[itemID] = true -- the player took our mark away: it stays away
		db.flipMarked[itemID] = nil
		return false
	end
	if (db.junk and db.junk[itemID]) or (db.sellAH and db.sellAH[itemID]) or (db.keep and db.keep[itemID]) then
		return false
	end
	if ns.ItemWatch and ns.ItemWatch.IsWatched and ns.ItemWatch.IsWatched(itemID) then
		return false
	end
	return true
end

-- Marks the flip items that arrived in the bags; returns their item IDs.
function Basket.MarkArrived()
	local db = ns.db
	local marked = {}
	if not (db and db.flipRecent and next(db.flipRecent) and Basket.MarkEnabled() and ns.Holdings and ns.SetItemState) then
		return marked
	end
	db.flipMarked, db.flipNoMark = db.flipMarked or {}, db.flipNoMark or {}
	local carried = ns.Holdings.Carried()
	for itemID, r in pairs(db.flipRecent) do
		if (carried[itemID] or 0) > (r.held0 or 0) then
			if Markable(itemID, r.held0) then
				ns.SetItemState(itemID, "junk")
				db.flipMarked[itemID] = true
				marked[#marked + 1] = itemID
				ns.Print(("%s is marked as junk: bought as an AH → vendor flip. Middle-click it to take the mark off."):format(Basket.ItemName(itemID)))
			end
			db.flipRecent[itemID] = nil
		end
	end
	return marked
end
ns.Listen("BAGS_CHANGED", Basket.MarkArrived)

-- Takes a line out until it gets clearly better, and rebuilds the Auctionator list without it.
function Basket.DismissFlip(itemID)
	local flips = ns.db and ns.db.flips
	if not flips then
		return
	end
	for i, f in ipairs(flips.items) do
		if f.itemID == itemID then
			ns.db.flipDismissed = ns.db.flipDismissed or {}
			ns.db.flipDismissed[itemID] = f.profit
			table.remove(flips.items, i)
			if ns.db.flipRecent then
				ns.db.flipRecent[itemID] = nil
			end
			break
		end
	end
	Basket.RefreshFlipList()
	Changed()
end

-- Units still to buy of a flip line: what is listed below the vendor price minus what the bags hold.
function Basket.FlipHeld(line)
	return ns.Holdings and ns.Holdings.Counter()(line.itemID) or 0
end

-- The term of a flip line: its name, a max price per unit (what still earns) and the units.
function Basket.FlipTerm(line)
	local name = SearchName(line.itemID)
	if not name then
		return nil
	end
	return { searchString = name, isExact = true, maxPrice = line.maxUnit, quantity = line.units }
end

-- Search string of a flip line, for when Auctionator's API isn't there. Auctionator's fields (Source/Search/
-- Advanced.lua SplitAdvancedSearch): name; category; item level min, max; level min, max; crafted level min,
-- max; price min, max (in gold, as Auctionator writes them); quality; tier; expansion; quantity.
function Basket.FlipSearchString(line)
	local t = Basket.FlipTerm(line)
	if not t then
		return nil
	end
	return ('"%s";;;;;;;;;%s;;;;%d'):format(t.searchString, tostring(t.maxPrice / 10000), t.quantity)
end

-- Builds (replaces) the shopping list "CraftWise vendor flips" from the flip lines.
function Basket.CreateFlipList(lines, allowEmpty)
	return CreateList(Basket.FLIP_LIST_NAME, lines, Basket.FlipTerm, allowEmpty)
end

-- After each check: the list follows the section when Auctionator is there (the list exists once it was
-- made, so it is also emptied of flips that are gone; nothing is made while there are none yet).
function Basket.RefreshFlipList()
	if not (ns.db and Basket.HasAuctionator() and ns.db.settings.flipList ~= false) then
		return nil
	end
	local lines = Basket.Flips()
	if #lines == 0 and not ns.db.flipListMade then
		return nil
	end
	local n = Basket.CreateFlipList(lines, true)
	if n then
		ns.db.flipListMade = true
	end
	return n
end

----------------------------------------------------------------------------------------------------
-- Vendor lines: the open merchant
----------------------------------------------------------------------------------------------------

local merchantOpen = false
ns.On("MERCHANT_SHOW", function()
	merchantOpen = true
	ns.Notify("BASKET_CHANGED")
end)
ns.On("MERCHANT_CLOSED", function()
	merchantOpen = false
	ns.Notify("BASKET_CHANGED")
end)

function Basket.MerchantOpen()
	return merchantOpen
end

-- The open merchant's slot for an item: { index, stack (items per purchase), available (-1 unlimited), price,
-- extended (costs more than gold) } or nil when it doesn't sell it.
function Basket.MerchantSlot(itemID)
	if not (merchantOpen and GetMerchantNumItems) then
		return nil
	end
	for index = 1, GetMerchantNumItems() do
		if GetMerchantItemID(index) == itemID then
			local info = ns.MerchantItemInfo(index)
			if not info then
				return nil
			end
			return { index = index, stack = info.stack or 1, available = info.available or -1, price = info.price, extended = info.extended and true or false }
		end
	end
end

-- Can this line be bought here? Returns true, nil, slot, quantity, or false, why.
-- Only plain gold items are bought by the button. An item sold in lots (stack > 1: Mild Spices x5) is
-- bought in whole lots: BuyMerchantItem's quantity is in items and Blizzard's merchant frame only offers
-- multiples of the lot (StackSplitFrame minSplit = stackCount, MerchantFrame.lua MerchantItemButton_
-- BuyMultipleStacks). A typed quantity (strict) must be a multiple; a basket line is rounded up to whole lots.
-- The merchant's stock (numAvailable) counts lots (it is shown on the lot's button).
function Basket.CanBuy(line, strict)
	if not merchantOpen then
		return false, "Open a merchant that sells it"
	end
	local slot = Basket.MerchantSlot(line.itemID)
	if not slot then
		return false, "This merchant doesn't sell it"
	end
	if slot.extended then
		return false, "Costs more than gold: buy it by hand"
	end
	local lot = math.max(1, slot.stack or 1)
	local quantity = line.quantity
	if lot > 1 then
		if strict and quantity % lot ~= 0 then
			return false, (ns.L["Type a multiple of %d"]):format(lot), slot
		end
		quantity = math.ceil(quantity / lot) * lot
	end
	if slot.available >= 0 then
		quantity = math.min(quantity, slot.available * lot)
	end
	if quantity < 1 then
		return false, "Sold out"
	end
	return true, nil, slot, quantity
end

-- The quantity a player typed: a whole number from 1 to MAX_COUNT, nil for empty or nonsense.
function Basket.ParseQuantity(text)
	local n = tonumber(text)
	if not n or n < 1 then
		return nil
	end
	return math.min(Basket.MAX_COUNT, math.floor(n))
end

-- A quantity split into purchase-sized calls: Chunks(50, 20) = { 20, 20, 10 }.
function Basket.Chunks(quantity, maxStack)
	maxStack = math.max(1, math.floor(tonumber(maxStack) or 1))
	local out, left = {}, math.floor(tonumber(quantity) or 0)
	while left > 0 do
		local n = math.min(left, maxStack)
		out[#out + 1] = n
		left = left - n
	end
	return out
end

-- Room in the bags for an item: free ordinary slots x its stack size, plus what the partial stacks of it
-- can still take. nil when the client hasn't told the stack size yet (then the check is skipped, nothing
-- is guessed). Slots of special bags (profession bags etc.) are not counted.
function Basket.BagSpace(itemID)
	local size = C_Item and C_Item.GetItemMaxStackSizeByID and C_Item.GetItemMaxStackSizeByID(itemID)
	if not (size and size > 0 and C_Container) then
		return nil
	end
	local space = 0
	for bag = 0, ns.LAST_BAG do
		local free, family = C_Container.GetContainerNumFreeSlots(bag)
		if (family or 0) == 0 then
			space = space + (free or 0) * size
		end
		for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.itemID == itemID then
				space = space + math.max(0, size - (info.stackCount or 1))
			end
		end
	end
	return space
end

-- Everything that must hold before one click buys: CanBuy, then gold and bag room for the whole quantity.
-- strict (the merchant window's typed quantity): more than the merchant has left is a refusal, buy nothing.
-- Not strict (the basket line): the quantity is cut to what is left. Returns true, nil, slot, quantity,
-- total price, or false, why.
function Basket.Check(line, strict)
	local ok, why, slot, quantity = Basket.CanBuy(line, strict)
	if not ok then
		return false, why
	end
	if strict and quantity < line.quantity then
		return false, (ns.L["Only %d left at this merchant"]):format(quantity)
	end
	-- The price is per lot, the quantity in items.
	local total = (slot.price or 0) * (quantity / math.max(1, slot.stack or 1))
	if GetMoney and slot.price and GetMoney() < total then
		return false, ns.L["Not enough gold"], slot, quantity, total
	end
	local space = Basket.BagSpace(line.itemID)
	if space and space < quantity then
		return false, (ns.L["Bags have room for %d"]):format(space), slot, quantity, total
	end
	return true, nil, slot, quantity, total
end

-- The one shared purchase: buys `line.quantity` of an item from the open merchant in stack-sized calls
-- (BuyMerchantItem takes at most GetMerchantItemMaxStack per call, Blizzard's merchant frame splits
-- larger amounts the same way, MerchantFrame.lua). It runs only from the click handler of a Buy button
-- (the basket's line or the merchant window's control): never more than the quantity, and it stops when
-- the merchant closes. Returns the quantity bought or nil, why (a partial purchase returns what went
-- through).
function Basket.Purchase(line, strict)
	local ok, why, slot, quantity = Basket.Check(line, strict)
	if not ok then
		return nil, why
	end
	local maxStack = GetMerchantItemMaxStack and GetMerchantItemMaxStack(slot.index) or 1
	local lot = math.max(1, slot.stack or 1)
	-- Every call is whole lots: the largest multiple of the lot that fits the per-call maximum (one lot at least).
	maxStack = math.max(lot, math.floor(maxStack / lot) * lot)
	local bought = 0
	for _, n in ipairs(Basket.Chunks(quantity, maxStack)) do
		if not merchantOpen then
			return bought > 0 and bought or nil, ns.L["The merchant closed"]
		end
		BuyMerchantItem(slot.index, n)
		bought = bought + n
	end
	return bought
end

-- A basket line: the quantity is cut to the stock.
function Basket.Buy(line)
	return Basket.Purchase(line, false)
end
