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
--   * Vendor: Basket.Buy(line) buys one line's quantity from the open merchant. It runs only from a click
--     on that line's button; nothing here buys, lists or confirms on its own.
-- Pure parts (Add, Remove, Combine, Split, Expected) take plain data so the specs can feed them.
local _, ns = ...

local Basket = {}
ns.Basket = Basket

Basket.LIST_NAME = "CraftWise basket"
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

----------------------------------------------------------------------------------------------------
-- Plan: wiring to recipes, bags and prices
----------------------------------------------------------------------------------------------------

-- The row (ns.BuildRows) of an entry; nil when its recipe isn't known to the addon any more.
local function RowOf(e, cache)
	local rows = cache[e.professionID]
	if not rows then
		rows = {}
		for _, r in ipairs(ns.BuildRows(e.professionID, true, "profit")) do
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
	local plan = { crafts = {}, missing = {}, need = {}, buy = {}, done = {} }
	if not ns.db then
		return plan
	end
	local cache, items, expected = {}, {}, {}
	for _, e in ipairs(Entries()) do
		local row = RowOf(e, cache)
		if row then
			plan.crafts[#plan.crafts + 1] = { entry = e, row = row, count = e.count }
			items[#items + 1] = { reagents = row.reagents, count = e.count }
			expected[#expected + 1] = { count = e.count, vendorSale = row.vendorSale, vendorProfit = row.vendorProfit }
		else
			plan.missing[#plan.missing + 1] = e
		end
	end
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

-- Builds (replaces) the shopping list "CraftWise basket" from the AH lines. Returns the number of lines
-- or nil, why. Called from a button; it only creates the list, searching and buying stay with the player.
function Basket.CreateAuctionatorList(lines)
	local api = AuctionatorAPI()
	if not api then
		return nil, "Auctionator isn't loaded"
	end
	local strings = {}
	for _, l in ipairs(lines or {}) do
		local term = Basket.Term(l)
		if term then
			strings[#strings + 1] = api.ConvertToSearchString(Basket.CALLER, term)
		end
	end
	if #strings == 0 then
		return nil, "No AH lines with a known item name yet"
	end
	local ok, err = pcall(api.CreateShoppingList, Basket.CALLER, Basket.LIST_NAME, strings)
	if not ok then
		return nil, tostring(err)
	end
	return #strings
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
			local _, _, price, stack, available, _, _, extended = GetMerchantItemInfo(index)
			return { index = index, stack = stack or 1, available = available or -1, price = price, extended = extended and true or false }
		end
	end
end

-- Can this line be bought here? Returns true, nil, slot, quantity, or false, why.
-- Only plain gold items sold one at a time are bought by the button: a merchant that sells lots of 5 has
-- its own quantity rule, which isn't read here, so those stay a purchase by hand.
function Basket.CanBuy(line)
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
	if slot.stack ~= 1 then
		return false, ("Sold in lots of %d: buy it by hand"):format(slot.stack)
	end
	local quantity = line.quantity
	if slot.available >= 0 then
		quantity = math.min(quantity, slot.available)
	end
	if quantity < 1 then
		return false, "Sold out"
	end
	return true, nil, slot, quantity
end

-- Buys one line's quantity from the open merchant. BuyMerchantItem takes at most one stack per call
-- (Blizzard's merchant frame splits larger amounts the same way, MerchantFrame.lua), so a line bigger than
-- a stack is bought in stack-sized calls within this one click: never more than the line's quantity, and
-- only from the click handler of that line's button. Returns the quantity bought or nil, why.
function Basket.Buy(line)
	local ok, why, slot, quantity = Basket.CanBuy(line)
	if not ok then
		return nil, why
	end
	if GetMoney and slot.price and GetMoney() < slot.price * quantity then
		return nil, "Not enough gold"
	end
	local maxStack = GetMerchantItemMaxStack and GetMerchantItemMaxStack(slot.index) or 1
	maxStack = math.max(1, maxStack or 1)
	local left = quantity
	while left > 0 do
		local n = math.min(left, maxStack)
		BuyMerchantItem(slot.index, n)
		left = left - n
	end
	return quantity
end
