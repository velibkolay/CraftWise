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
-- Craft run (#388): the AH panel's "Craft run" section plans crafts from what the character knows (Profit.RunPlan,
-- fed by Basket.RunCandidates) under a gold budget and a time limit and "Use plan" (Basket.UsePlan) puts them here.
--   * An entry made from a plan carries three more fields, which the craft list (#389) and the sell lists (#390) read:
--       channel    "vendor" | "AH": where the planned craft sells for more (or "vendor" under the Vendor-only filter)
--       profitEach expected profit per craft in copper (sale after the cut or at the vendor, minus the reagents at their
--                  buy value: what the bags hold counts at that value too, only the budget counts cash)
--       secEach    crafting seconds per craft, the crafts of its intermediates included (measured median, else the
--                  recipe's cast time from the client)
--     Entries added by hand have none of the three (nil: nothing is guessed). Adding a recipe again keeps its count
--     sum and takes the newer three.
--   * Demand cap: an AH craft is planned at most as often as the item sells (his own AH sales of it, else the units
--     observed leaving the profit house between scans, else Settings "Max per item without sales data", default 2);
--     the source is told in the plan. Vendor sales have no cap.
-- Craft list (#389): the run as a list to work through, in the profession window's side panel (UI/Main/Pages/Basket.lua)
-- and in Make > Basket. Basket.CraftList(plan, bags) makes it from Basket.Plan():
--   * lines: the crafts of intermediates first (the buy list's "craft instead of buy", deepest first), then the entries by
--     profit per craft-second (profitEach / secEach; entries without both keep the plan's order after those that have them),
--     an entry whose product is a reagent of another entry before that one; then the lines that are made.
--   * a line: { kind = "intermediate" | "craft" | "made", recipeID, name, left, planned, made, channel, label, profitEach,
--     secEach, pps, can (crafts the bags allow now), missing = { { itemID, short } } (for the next craft), state =
--     "ready" | "partly" | "missing" | "made" }. Reagents are counted from the bags only (Holdings.Carried): what is in the
--     bank cannot be crafted from.
--   * Crafts tick by themselves: ns.OnCraft (Crafts.lua, the craft log's event, #205) calls Basket.OnCrafted(recipeID, name):
--     an entry's count goes down by one (at zero it leaves the list) and db.basket.made[recipeID] = { n, profit, name,
--     channel, profitEach, professionID } counts what was made, profit = the plan's profit per craft summed (nil when an
--     entry had none: nothing is guessed). So an entry's count is the crafts LEFT; "left of planned" is count of count + made.
--     Intermediates tick through the bags (BAGS_CHANGED): what is made leaves the needs. A new run (an empty basket gets an
--     entry, "Use plan" with replace, Clear) forgets what was made. Nothing is crafted from here: the player presses Create.
--   * summary: { left, madeTotal, madeProfit (nil when unknown), profitLeft, done = nothing left and something made }.
-- Pure parts (Add, Remove, Combine, Split, Expected, DemandCap, SaleOf, CraftList) take plain data so the specs can feed them.
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

-- An empty basket that still remembers a finished run (db.basket.made) starts a new run: the old tally goes.
function Basket.FreshRun()
	if ns.db and ns.db.basket and #Entries() == 0 then
		ns.db.basket.made = nil
	end
end

-- Adds `count` crafts of a recipe (default 1); the same recipe again adds to its count.
-- extra (#388, optional): { channel, profitEach, secEach } of a planned craft, stored on the entry.
function Basket.Add(recipeID, professionID, count, extra)
	if not (ns.db and recipeID) then
		return nil
	end
	count = Clamp(count)
	Basket.FreshRun()
	local e = Basket.Find(recipeID)
	if e then
		e.count = Clamp(e.count + count)
	else
		e = { recipeID = recipeID, professionID = professionID, count = count }
		table.insert(Entries(), e)
	end
	if extra then
		e.channel, e.profitEach, e.secEach = extra.channel, extra.profitEach, extra.secEach
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
-- Craft list (#389)
----------------------------------------------------------------------------------------------------

Basket.CHANNEL_LABELS = { vendor = "Vendor", AH = "AH" }

local function MadeTable()
	ns.db.basket = ns.db.basket or { entries = {} }
	ns.db.basket.made = ns.db.basket.made or {}
	return ns.db.basket.made
end

-- Crafts of a recipe that its reagents allow from `bags` (itemID -> count), at most `left`; missing = what the next
-- craft lacks, { { itemID, short } }.
function Basket.CanCraft(reagents, bags, left)
	local can, missing = nil, {}
	for _, r in ipairs(reagents or {}) do
		local q = r.quantity or 0
		if q > 0 then
			local held = bags[r.itemID] or 0
			can = can and math.min(can, math.floor(held / q)) or math.floor(held / q)
			if held < q then
				missing[#missing + 1] = { itemID = r.itemID, short = q - held }
			end
		end
	end
	return math.min(can or 0, left or 0), missing
end

local function StateOf(can, left)
	if can >= left then
		return "ready"
	end
	return can > 0 and "partly" or "missing"
end

-- One craft succeeded (ns.OnCraft): the entry of that recipe has one craft less and the run's tally one more. At zero the
-- entry leaves the basket (the tally keeps its line). Crafts of recipes that are not in the basket change nothing.
function Basket.OnCrafted(recipeID, name)
	local e = ns.db and Basket.Find(recipeID)
	if not e then
		return
	end
	local made = MadeTable()
	local m = made[recipeID]
	if not m then
		m = { n = 0, profit = 0 }
		made[recipeID] = m
	end
	m.n = m.n + 1
	m.profit = m.profit and e.profitEach and (m.profit + e.profitEach) or nil
	m.name, m.channel, m.profitEach, m.professionID = name or m.name, e.channel, e.profitEach, e.professionID
	if e.count <= 1 then
		local _, i = Basket.Find(recipeID)
		table.remove(Entries(), i)
	else
		e.count = e.count - 1
	end
	Changed()
end

-- Pure: the crafts of intermediates that a list of needs asks for. need = { { itemID, quantity } }; counted(itemID) = units held;
-- makers[itemID] = { { recipeID, reagents, output } }; chooser(itemID, depth, visiting) -> recipe | nil, the craft-or-buy
-- decision at market prices (nil = buy). A reagent that is short is crafted when the chooser says so, or when its first maker's
-- inputs are all held anyway; one level of intermediates under another at most (Balance.MAX_DEPTH). Returns { { itemID, recipeID,
-- crafts, depth, reagents } }; units a craft makes beyond the need stay in the pool.
function Basket.Intermediates(need, counted, makers, chooser)
	local pool, out, at = {}, {}, {}
	local function held(itemID)
		if pool[itemID] == nil then
			pool[itemID] = counted(itemID) or 0
		end
		return pool[itemID]
	end
	local maxDepth = ns.Balance and ns.Balance.MAX_DEPTH or 2
	local function want(itemID, quantity, depth)
		local have = held(itemID)
		local take = math.min(have, quantity)
		pool[itemID] = have - take
		local short = quantity - take
		if short <= 0 or depth >= maxDepth then
			return
		end
		local recipe
		for _, maker in ipairs(makers[itemID] or {}) do
			local picked = chooser and chooser(itemID, depth, {})
			recipe = picked and picked.recipeID == maker.recipeID and maker or recipe
		end
		if not recipe then
			local first = (makers[itemID] or {})[1]
			if first then
				local yield = math.max(1, math.floor(first.output and first.output.quantity or 1))
				local crafts, all = math.ceil(short / yield), true
				for _, r in ipairs(first.reagents or {}) do
					all = all and held(r.itemID) >= r.quantity * crafts
				end
				recipe = all and first or nil
			end
		end
		if not recipe then
			return
		end
		local yield = math.max(1, math.floor(recipe.output and recipe.output.quantity or 1))
		local crafts = math.ceil(short / yield)
		local line = at[itemID]
		if line then
			line.crafts = line.crafts + crafts
		else
			line = { itemID = itemID, recipeID = recipe.recipeID, crafts = crafts, depth = depth, reagents = recipe.reagents }
			at[itemID] = line
			out[#out + 1] = line
		end
		pool[itemID] = held(itemID) + crafts * yield - short
		for _, r in ipairs(recipe.reagents or {}) do
			want(r.itemID, r.quantity * crafts, depth + 1)
		end
	end
	for _, n in ipairs(need or {}) do
		want(n.itemID, n.quantity, 0)
	end
	return out
end

-- Profit per craft-second of an entry's planned figures, nil when either is missing.
local function PerSecond(profitEach, secEach)
	if profitEach and secEach and secEach > 0 then
		return profitEach / secEach
	end
end

-- The entries (plan.crafts) in craft order: best profit per second first, those without it after in the plan's order, an
-- entry whose product another entry needs before that one.
local function RunOrder(crafts)
	local sorted = {}
	for i, c in ipairs(crafts) do
		c.pos, c.pps = i, PerSecond(c.entry.profitEach, c.entry.secEach)
		sorted[i] = c
	end
	table.sort(sorted, function(a, b)
		if (a.pps ~= nil) ~= (b.pps ~= nil) then
			return a.pps ~= nil
		end
		if a.pps and a.pps ~= b.pps then
			return a.pps > b.pps
		end
		return a.pos < b.pos
	end)
	local producer = {}
	for _, c in ipairs(sorted) do
		if c.row.outputItemID then
			producer[c.row.outputItemID] = c
		end
	end
	local out, placed = {}, {}
	while #sorted > 0 do
		local pick = 1
		for i, c in ipairs(sorted) do
			local blocked = false
			for _, r in ipairs(c.row.reagents or {}) do
				local p = producer[r.itemID]
				if p and p ~= c and not placed[p] then
					blocked = true
					break
				end
			end
			if not blocked then
				pick = i
				break
			end
		end
		local c = table.remove(sorted, pick) -- a cycle (nothing unblocked) takes the first
		placed[c] = true
		out[#out + 1] = c
	end
	return out
end

-- The craft list of a plan (Basket.Plan()); bags = itemID -> count of what is carried. opts (specs): { counted = fn(itemID)
-- -> units held in the counted places, makers = Balance.Makers() form, chooser = Balance.Chooser() form }. See the header.
function Basket.CraftList(plan, bags, opts)
	bags = bags or {}
	local made = ns.db and ns.db.basket and ns.db.basket.made or {}
	local lines, isEntry = {}, {}
	for _, c in ipairs(plan.crafts or {}) do
		isEntry[c.entry.recipeID] = true
	end
	-- Intermediates: the reagents of the crafts that the bags (and the other counted places) do not hold and a known recipe
	-- makes, crafted from bought or held inputs, deepest first: they come before what uses them.
	opts = opts or {}
	local inter = {}
	if #(plan.need or {}) > 0 then
		local counted = opts.counted or (ns.Holdings and ns.Holdings.Counter()) or function(id) return bags[id] or 0 end
		local makers = opts.makers or (ns.Balance and ns.Balance.Makers()) or {}
		local chooser = opts.chooser or (ns.Balance and ns.Balance.Chooser())
		for _, m in ipairs(Basket.Intermediates(plan.need, counted, makers, chooser)) do
			if not isEntry[m.recipeID] then
				local can, missing = Basket.CanCraft(m.reagents, bags, m.crafts)
				inter[#inter + 1] = { kind = "intermediate", recipeID = m.recipeID, outputItemID = m.itemID, name = Basket.ItemName(m.itemID),
					left = m.crafts, planned = m.crafts, made = 0, can = can, missing = missing, state = StateOf(can, m.crafts),
					depth = m.depth }
			end
		end
	end
	table.sort(inter, function(a, b)
		if a.depth ~= b.depth then
			return a.depth > b.depth
		end
		return a.name < b.name
	end)
	for _, l in ipairs(inter) do
		lines[#lines + 1] = l
	end
	for _, c in ipairs(RunOrder(plan.crafts or {})) do
		local e, id = c.entry, c.entry.recipeID
		local done = made[id] and made[id].n or 0
		local can, missing = Basket.CanCraft(c.row.reagents, bags, c.count)
		lines[#lines + 1] = { kind = "craft", recipeID = id, professionID = e.professionID, name = c.row.name,
			outputItemID = c.row.outputItemID, icon = c.row.icon, left = c.count, planned = c.count + done, made = done,
			channel = e.channel, label = e.channel and Basket.CHANNEL_LABELS[e.channel], profitEach = e.profitEach,
			secEach = e.secEach, pps = c.pps, can = can, missing = missing, state = StateOf(can, c.count), craft = c }
	end
	-- What is made and has no craft left: ticked and last.
	local finished = {}
	for id, m in pairs(made) do
		if not isEntry[id] then
			finished[#finished + 1] = { kind = "made", recipeID = id, professionID = m.professionID, name = m.name or ("recipe " .. id),
				left = 0, planned = m.n, made = m.n, channel = m.channel, label = m.channel and Basket.CHANNEL_LABELS[m.channel],
				profitEach = m.profitEach, can = 0, missing = {}, state = "made" }
		end
	end
	table.sort(finished, function(a, b)
		return a.name < b.name
	end)
	for _, l in ipairs(finished) do
		lines[#lines + 1] = l
	end
	local sum = { left = 0, madeTotal = 0, madeProfit = 0, profitLeft = 0 }
	for _, m in pairs(made) do
		sum.madeTotal = sum.madeTotal + m.n
		sum.madeProfit = sum.madeProfit and m.profit and (sum.madeProfit + m.profit) or nil
	end
	for _, l in ipairs(lines) do
		if l.kind == "craft" then
			sum.left = sum.left + l.left
			sum.profitLeft = sum.profitLeft and l.profitEach and (sum.profitLeft + l.profitEach * l.left) or nil
		end
	end
	sum.done = sum.left == 0 and #(plan.crafts or {}) == 0 and #(plan.missing or {}) == 0 and sum.madeTotal > 0
	return { lines = lines, summary = sum }
end

----------------------------------------------------------------------------------------------------
-- Craft run (#388)
----------------------------------------------------------------------------------------------------

Basket.RUN_MAX_DEFAULT = 2 -- crafts of an AH item without any sales data (Veli, #387), Settings "Max per item without sales data"
Basket.SALES_DAYS = 14 -- the window of his own sales that sets the demand: provisional, labelled in the plan
Basket.LISTING_DEFAULT = 8 -- hours one listing runs (#399): he posts everything at once as 8-hour auctions (confirmed in game)

-- The listing durations the sell frame offers, in hours (#399). Blizzard's Forever sell frame has three (the dropdown
-- AUCTION_DURATION_ONE..THREE, index 1-3); their hours are only in the client's own text, so they are read from it
-- (Auctions.DurationHours, English clients). Where the text can't be read, only the confirmed 8 h is offered.
function Basket.ListingOptions()
	local out = {}
	for i = 1, 3 do
		local h = ns.Auctions and ns.Auctions.DurationHours and ns.Auctions.DurationHours(i)
		if h and h > 0 then
			out[#out + 1] = h
		end
	end
	if #out == 0 then
		out[1] = Basket.LISTING_DEFAULT
	end
	return out
end

-- The chosen listing hours: the setting when the sell frame offers it, else 8 when offered, else the first offered.
function Basket.ListingHours()
	local options = Basket.ListingOptions()
	local want = ns.db and ns.db.settings and tonumber(ns.db.settings.craftRunHours) or Basket.LISTING_DEFAULT
	for _, h in ipairs(options) do
		if h == want then
			return h
		end
	end
	for _, h in ipairs(options) do
		if h == Basket.LISTING_DEFAULT then
			return h
		end
	end
	return options[1]
end

function Basket.MaxWithoutData()
	local n = ns.db and ns.db.settings and tonumber(ns.db.settings.craftRunMax)
	return n and n >= 1 and math.floor(n) or Basket.RUN_MAX_DEFAULT
end

-- Crafting seconds of one craft: the measured median of the craft log (#251, #273), else the recipe's cast time from
-- the client, said so. nil without either: the recipe is left out of the plan (a time is never made up).
function Basket.CraftSeconds(recipeID)
	local speed = ns.CraftLog and ns.CraftLog.Speed and ns.CraftLog.Speed(recipeID)
	if speed then
		return speed.sec, "measured"
	end
	local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(recipeID)
	local ms = info and tonumber(info.castTime)
	if ms and ms > 0 then
		return ms / 1000, "cast time, not measured"
	end
	return nil
end

-- Pure: the most crafts of an AH item one listing can sell (#399). sold = { units, days } | nil (his own AH sales),
-- drops = { units, days } | nil (the units seen leaving the market: information only, they also count cancels, expiries
-- and other sellers, so they never set the cap), outQty = units one craft makes, fallback = the setting, hours = the
-- listing duration. With own sales: sales a day x hours / 24, divided by outQty, rounded down, at least 1. Without:
-- the fallback. Returns cap (crafts), perDay, source ("sales" | "default") and the text the plan shows.
function Basket.DemandCap(sold, drops, outQty, fallback, hours)
	outQty = math.max(1, outQty or 1)
	hours = hours or Basket.LISTING_DEFAULT
	local info = ""
	if drops and drops.units > 0 and drops.days > 0 then
		info = (" · observed drops: %d units in %d days, %.1f a day (not used: a cancel looks the same)"):format(drops.units,
			drops.days, drops.units / math.max(1, drops.days))
	end
	if sold and sold.units > 0 then
		local perDay = sold.units / math.max(1, sold.days)
		local expected = perDay * hours / 24
		local cap = math.max(1, math.floor(expected / outQty + 1e-9))
		return cap, perDay, "sales", ("your sales: %d in %d days, %.1f in %d h: %d"):format(sold.units, sold.days, expected, hours, cap) .. info
	end
	return fallback, nil, "default", ("no sales data: at most %d"):format(fallback) .. info
end

-- Pure: how a craft sells. options = ns.SaleOptions(item, units one craft makes): { vendor, auction = { net }, chosen }.
-- vendorOnly takes the vendor price for every craft. The AH only counts with a known cut (net): an unverified cut
-- gives a gross price that is not a profit. Returns channel ("vendor" | "AH"), copper per craft; nil, why without one.
function Basket.SaleOf(options, vendorOnly)
	local vendor = options and options.vendor
	local hasVendor = vendor and vendor > 0
	if vendorOnly then
		if hasVendor then
			return "vendor", vendor
		end
		return nil, "no vendor price"
	end
	local ah = options and options.auction and options.auction.net
	if options and options.chosen == "auction" and ah then
		return "AH", ah
	end
	if hasVendor then
		return "vendor", vendor
	end
	if options and options.chosen == "auction" then
		return nil, "the AH cut is not known"
	end
	return nil, "no price"
end

-- His own AH sales of an item over the window, and the units the profit house lost to drops: { units, days } each.
local function SoldOf(itemID, now)
	local units = ns.Auctions and ns.Auctions.SoldUnits and ns.Auctions.SoldUnits(itemID, now - Basket.SALES_DAYS * 86400) or 0
	return { units = units, days = Basket.SALES_DAYS }
end
local function DropsOf(itemID, now)
	local house = ns.ProfitHouse and ns.ProfitHouse()
	if not (house and ns.Market and ns.Market.DropRate) then
		return nil
	end
	return ns.Market.DropRate(itemID, house, now)
end

local function BuyValue(buy)
	local cost = 0
	for _, l in ipairs(buy) do
		local q = ns.BuyQuote(l.itemID, l.quantity)
		if not q then
			return nil
		end
		cost = cost + q.cost
	end
	return cost
end

-- The candidates of the planner (see Profit.RunPlan): one per known recipe that makes an item, with its sale, its
-- time, its demand cap and quote(n). skipped counts what was left out and why ({ noTime, noSale, noPrice }).
function Basket.RunCandidates(opts)
	opts = opts or {}
	local cands, skipped = {}, { noTime = 0, noSale = 0, noPrice = 0 }
	if not (ns.db and ns.charDB) then
		return cands, skipped
	end
	local now = time()
	local makers, chooser = ns.Balance.Makers(), ns.Balance.Chooser()
	local function makersOf(itemID)
		return makers[itemID]
	end
	local function none()
		return 0
	end
	for professionID in pairs(ns.charDB.professions or {}) do
		for _, row in ipairs(ns.BuildRows(professionID, false, "profit")) do
			local out, qty = row.outputItemID, row.outputQuantity
			if row.status == "known" and out and qty and qty > 0 and #(row.reagents or {}) > 0 then
				local seconds, timeLabel = Basket.CraftSeconds(row.recipeID)
				local channel, each = Basket.SaleOf(ns.SaleOptions(out, qty), opts.vendorOnly)
				if not seconds then
					skipped.noTime = skipped.noTime + 1
				elseif not channel then
					skipped.noSale = skipped.noSale + 1
				else
					local c = { recipeID = row.recipeID, professionID = professionID, name = row.name, outputItemID = out,
						seconds = seconds, timeLabel = timeLabel, channel = channel, each = each, reagents = row.reagents }
					if channel == "AH" then
						local cap, _, _, text = Basket.DemandCap(SoldOf(out, now), DropsOf(out, now), qty, Basket.MaxWithoutData(), Basket.ListingHours())
						c.cap, c.capText = cap, text
					end
					c.quote = function(n)
						local need = {}
						for i, r in ipairs(row.reagents) do
							need[i] = { itemID = r.itemID, quantity = r.quantity * n }
						end
						-- Worth: every reagent bought, none held, intermediates crafted where that is cheaper (the
						-- bags hold things worth money: a craft is not free because the mats are in the bank).
						local worth = BuyValue(ns.Balance.Expand(need, {}, none, makersOf, chooser, { [out] = true }).buy)
						-- Cash: the same after the bags, which is what the budget counts.
						local b = ns.ReagentBalance(need, 1, out)
						if not (worth and b.complete) then
							if n == 1 then
								c.noPrice = true
							end
							return nil
						end
						local extra = 0
						for _, made in ipairs(b.crafts) do
							local id = made.info and made.info.recipe and made.info.recipe.recipeID
							local sec = id and Basket.CraftSeconds(id)
							if not sec then
								return nil
							end
							extra = extra + made.crafts * sec
						end
						return { cost = worth, cash = b.total, seconds = extra }
					end
					cands[#cands + 1] = c
				end
			end
		end
	end
	return cands, skipped
end

-- What a plan shows besides its lines (what to buy, the intermediates to craft, the items to search again): from the
-- combined reagents of all its lines, through the same buy list as the basket's.
local function FillPlanBuy(plan, reagentsOf)
	local items = {}
	for _, l in ipairs(plan.lines) do
		items[#items + 1] = { reagents = reagentsOf[l.recipeID], count = l.count }
	end
	plan.need = Basket.Combine(items)
	plan.buy, plan.crafts = {}, {}
	if #plan.need > 0 then
		local b = ns.ReagentBalance(plan.need, 1)
		plan.buy, plan.crafts = b.buy, b.crafts
	end
	plan.split = Basket.Split(plan.buy)
	-- The prices worth a fresh look: every reagent that is not a sure vendor buy and, unless everything sells to
	-- vendors, the products (they decide AH or vendor).
	local seen, search = {}, {}
	local function add(itemID)
		if itemID and not seen[itemID] then
			seen[itemID] = true
			search[#search + 1] = itemID
		end
	end
	for _, l in ipairs(plan.buy) do
		if not (l.quote and l.quote.source == "vendor") then
			add(l.itemID)
		end
	end
	if not (plan.opts and plan.opts.vendorOnly) then
		for _, l in ipairs(plan.lines) do
			add(l.outputItemID)
		end
	end
	plan.search = search
end

-- The plan. opts: { budget = copper | nil, seconds = crafting time | nil, vendorOnly = bool }. Reads prices, recipes,
-- bags and the sales records; changes nothing. Returns { lines, cost (cash to buy), profit, seconds, limit, opts,
-- skipped, need, buy, crafts, split, search, t }.
function Basket.BuildRun(opts)
	opts = opts or {}
	local cands, skipped = Basket.RunCandidates(opts)
	local reagentsOf = {}
	for _, c in ipairs(cands) do
		reagentsOf[c.recipeID] = c.reagents
	end
	local plan = ns.Profit.RunPlan(cands, { budget = opts.budget, seconds = opts.seconds, total = function(lines)
		local items = {}
		for _, l in ipairs(lines) do
			items[#items + 1] = { reagents = reagentsOf[l.recipeID], count = l.count }
		end
		local need = Basket.Combine(items)
		if #need == 0 then
			return 0
		end
		local b = ns.ReagentBalance(need, 1)
		return b.complete and b.total or nil
	end })
	for _, c in ipairs(cands) do
		if c.noPrice then
			skipped.noPrice = skipped.noPrice + 1
		end
	end
	plan.opts = { budget = opts.budget, seconds = opts.seconds, vendorOnly = opts.vendorOnly and true or false }
	plan.skipped, plan.t = skipped, time()
	FillPlanBuy(plan, reagentsOf)
	return plan
end
if ns.Timed then
	Basket.BuildRun = ns.Timed("Basket.lua craft run", Basket.BuildRun)
end

-- "Use plan": the plan's crafts into the basket, replacing what is there or added to it. One BASKET_CHANGED.
-- Returns the number of crafts put in.
function Basket.UsePlan(plan, replace)
	if not (ns.db and plan) then
		return 0
	end
	if replace then
		ns.db.basket = { entries = {} }
	end
	Basket.FreshRun()
	local n = 0
	for _, l in ipairs(plan.lines or {}) do
		local e = Basket.Find(l.recipeID)
		if e then
			e.count = Clamp(e.count + l.count)
		else
			e = { recipeID = l.recipeID, professionID = l.professionID, count = Clamp(l.count) }
			table.insert(Entries(), e)
		end
		e.channel, e.profitEach, e.secEach = l.channel, l.profitEach, l.secEach
		n = n + l.count
	end
	Changed()
	return n
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
