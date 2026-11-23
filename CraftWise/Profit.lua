-- Pure profit maths; no client calls except through the price functions passed in.
local _, ns = ...

local Profit = {}
ns.Profit = Profit

Profit.MAX_DEPTH = 4 -- crafted intermediates inside crafted intermediates, at most this deep

local function Copy(t)
	local out = {}
	for k, v in pairs(t) do
		out[k] = v
	end
	return out
end

-- Cost of one unit made by `recipe` ({ reagents, output = { itemID, quantity } }): its reagents'
-- unit costs times their quantities, divided by the output quantity. nil when a reagent has no price.
function Profit.CraftCost(recipe, prices, depth, visiting)
	local qty = recipe.output and recipe.output.quantity
	if not (qty and qty > 0 and recipe.reagents and #recipe.reagents > 0) then
		return nil
	end
	local total, age, thin, fallback = 0, nil, nil, nil
	for _, r in ipairs(recipe.reagents) do
		local unit = Profit.UnitCost(r.itemID, prices, depth, visiting)
		if not unit then
			return nil
		end
		total = total + unit.copper * r.quantity
		if unit.age and (not age or unit.age > age) then
			age = unit.age
		end
		thin = thin or unit.thin
		fallback = fallback or unit.paidFallback
	end
	return { copper = total / qty, age = age, thin = thin, paidFallback = fallback }
end

-- Cost of one unit of a reagent (#47): the buy price (prices.buy) or, when a recipe this character
-- knows makes it (prices.recipesFor), the craft cost if that is lower. Recursive up to MAX_DEPTH, and
-- an item already being priced up the chain is never crafted again (cycle guard). The result says
-- which won: crafted = true ("crafted") or false ("bought"), with both unit values (craftUnit,
-- buyUnit, buyLabel); crafted is nil when no known recipe makes the item. nil = no price at all.
-- A buy price marked noCraft is used as is, without looking at recipes. A crafted result carries the
-- cheapest recipe (recipe), so the buy list (#60) crafts with the same one.
function Profit.UnitCost(itemID, prices, depth, visiting)
	depth, visiting = depth or 0, visiting or {}
	local bought = prices.buy(itemID)
	if bought and bought.noCraft then
		return bought -- a price that stands as is (paid cost of what you hold, #47 decision 1)
	end
	local craft, craftRecipe
	if prices.recipesFor and depth < Profit.MAX_DEPTH and not visiting[itemID] then
		visiting[itemID] = true
		for _, recipe in ipairs(prices.recipesFor(itemID) or {}) do
			local c = Profit.CraftCost(recipe, prices, depth + 1, visiting)
			if c and (not craft or c.copper < craft.copper) then
				craft, craftRecipe = c, recipe
			end
		end
		visiting[itemID] = nil
	end
	if craft and (not bought or craft.copper < bought.copper) then
		return { copper = craft.copper, source = "crafted", label = "crafted", crafted = true, craftUnit = craft.copper,
			recipe = craftRecipe, buyUnit = bought and bought.copper, buyLabel = bought and bought.label, buySource = bought and bought.source,
			age = craft.age, thin = craft.thin, paidFallback = craft.paidFallback,
			paidNote = craft.paidFallback and "some of its reagents have no paid cost (AH)" or nil }
	end
	if not bought then
		return nil
	end
	if craft then
		bought = Copy(bought)
		bought.crafted, bought.craftUnit, bought.buyUnit = false, craft.copper, bought.copper
		bought.buyLabel, bought.buySource = bought.label, bought.source
	end
	return bought
end

-- Highest unit price of each AH-bought reagent that still breaks even (#261): (what one craft sells for - the cost
-- of every other reagent at the cost basis in `result`) / (units of the reagent one craft uses), rounded down.
-- Only for lines priced from the AH (source "auction": vendor, crafted and paid lines are not bought at an AH price),
-- and only when the sale (after the cut, or at the vendor/Junk value) and every other reagent's cost are known:
-- else nothing, never a guess. Sets on the line: maxBuy (copper, >= 0) or maxBuyLoss = true when even free the
-- craft loses money (the other reagents cost more than the sale), and overMax = true when the current unit price
-- is above maxBuy.
function Profit.MaxBuy(result)
	for _, line in ipairs(result.reagents or {}) do
		line.maxBuy, line.maxBuyLoss, line.overMax = nil, nil, nil
		if line.source == "auction" and line.total and result.sellsFor and result.costComplete and not result.cutUnverified
			and line.quantity and line.quantity > 0 then
			local room = result.sellsFor - (result.cost - line.total)
			if room <= 0 then
				line.maxBuyLoss = true
			else
				line.maxBuy = math.floor(room / line.quantity)
				if line.maxBuy <= 0 then
					line.maxBuy, line.maxBuyLoss = nil, true
				else
					line.overMax = line.unit > line.maxBuy or nil
				end
			end
		end
	end
	return result
end

-- recipe: { reagents = { { itemID, quantity } }, output = { itemID, quantity } | nil,
--           learned = bool, learnCost = copper | nil }
-- prices: { buy = fn(itemID) -> { copper, source, age, label, thin } | nil,
--           sell = fn(itemID) -> { copper, source, age, label, thin, gross, cut, cutUnverified } | nil,
--           recipesFor = fn(itemID) -> { recipe, ... } | nil (optional: craft-or-buy for intermediates) }
-- Returns a result table. A missing price never counts as 0: the result is marked incomplete.
-- A sale whose AH cut is unverified (#26) has a gross value only, so no profit is computed from it.
function Profit.Evaluate(recipe, prices)
	local result = {
		cost = 0,
		complete = true,
		costComplete = true, -- every reagent priced
		missing = {}, -- itemIDs without any price
		reagents = {}, -- per reagent: { itemID, quantity, unit, total, source, age, label, thin }
		oldestAge = nil,
	}

	local function noteAge(age)
		if age and (not result.oldestAge or age > result.oldestAge) then
			result.oldestAge = age
		end
	end

	-- The item this recipe makes is never priced by crafting it again inside its own reagents.
	local visiting = {}
	if recipe.output then
		visiting[recipe.output.itemID] = true
	end
	for _, r in ipairs(recipe.reagents or {}) do
		local price
		if prices.recipesFor then
			price = Profit.UnitCost(r.itemID, prices, 0, visiting)
		else
			price = prices.buy(r.itemID)
		end
		local line = { itemID = r.itemID, quantity = r.quantity }
		if price then
			line.unit, line.source, line.age, line.label, line.thin = price.copper, price.source, price.age, price.label, price.thin
			line.crafted, line.craftUnit, line.buyUnit = price.crafted, price.craftUnit, price.buyUnit
			line.buyLabel, line.buySource = price.buyLabel, price.buySource
			line.paidFallback, line.paidNote, line.paidPartial = price.paidFallback, price.paidNote, price.paidPartial
			if price.paidFallback then
				result.paidFallbacks = (result.paidFallbacks or 0) + 1
			end
			result.thin = result.thin or price.thin or nil
			line.total = price.copper * r.quantity
			result.cost = result.cost + line.total
			noteAge(price.age)
		else
			result.complete = false
			result.costComplete = false
			table.insert(result.missing, r.itemID)
		end
		table.insert(result.reagents, line)
	end
	if not recipe.reagents or #recipe.reagents == 0 then
		result.complete = false
		result.costComplete = false
	end

	if recipe.output then
		local value = prices.sell(recipe.output.itemID)
		if value then
			result.sellsFor = value.copper * recipe.output.quantity
			result.sellSource = value.source
			result.sellMarked = value.marked or nil -- Junk mark (#214, #227)
			result.sellLabel, result.sellThin, result.sellCut = value.label, value.thin, value.cut
			result.sellCutText, result.sellCutDiffers = value.cutText, value.cutDiffers
			result.sellGross = value.gross and value.gross * recipe.output.quantity
			result.cutUnverified = value.cutUnverified or nil
			result.thin = result.thin or value.thin or nil
			noteAge(value.age)
		else
			result.complete = false
			table.insert(result.missing, recipe.output.itemID)
		end
	else
		result.noItemOutput = true -- enchants and similar: no market value
	end

	if result.sellsFor and result.complete and not result.cutUnverified then
		result.profit = result.sellsFor - result.cost
	end

	if not recipe.learned and recipe.learnCost then
		result.learnCost = recipe.learnCost
		if result.profit and result.profit > 0 then
			result.breakEven = math.ceil(recipe.learnCost / result.profit)
		end
	end
	return Profit.MaxBuy(result)
end

-- Vendor check (#185): `result` is Profit.Evaluate's result for `recipe`; vendor = {
--   buy = fn(itemID) -> copper | nil   (vendor buy price of one unit),
--   sell = fn(itemID) -> copper | nil  (vendor sell price of one unit; 0 or nil = no value),
--   auction = fn(itemID) -> copper | nil (optional: AH unit price, only to show next to the vendor's) }.
-- Adds to result and to each reagent line (nothing is ever guessed, a missing price is nil):
--   vendorSale    product vendor sell price x output quantity (nil: no output, or no price)
--   vendorProfit  vendorSale - result.cost (reagents each where cheaper, as today); nil when either is missing
--   vendorCost    reagents at vendor buy prices x quantities; nil unless every reagent has one
--   vendorLoop    true when vendorCost and vendorSale exist and vendorSale - vendorCost > 0: buy, craft, sell,
--                 no AH involved
--   line.vendorBuy, line.ahUnit   the two unit prices per reagent, for the breakdown
function Profit.VendorCheck(result, recipe, vendor)
	local cost, all = 0, #(result.reagents or {}) > 0
	for _, line in ipairs(result.reagents or {}) do
		local buy = vendor.buy(line.itemID)
		line.vendorBuy = buy and buy > 0 and buy or nil
		line.ahUnit = vendor.auction and vendor.auction(line.itemID) or nil
		if line.vendorBuy then
			cost = cost + line.vendorBuy * line.quantity
		else
			all = false
		end
	end
	result.vendorCost = all and cost or nil
	result.vendorSale, result.vendorProfit, result.vendorLoop = nil, nil, nil
	local out = recipe.output
	if out and out.quantity and out.quantity > 0 then
		local sell = vendor.sell(out.itemID)
		if sell and sell > 0 then
			result.vendorSale = sell * out.quantity
		end
	end
	if result.vendorSale and result.costComplete then
		result.vendorProfit = result.vendorSale - result.cost
	end
	if result.vendorSale and result.vendorCost and result.vendorSale - result.vendorCost > 0 then
		result.vendorLoop = true
	end
	return result
end

-- Crafts a day of a cooldown-limited recipe (#413), pure. c = { kind = "spell" | "item", ms (the cooldown), perCraft (item
-- kind: units of the cooldown-made reagent one craft uses), quantity (item kind: units one use makes), toolHeld (item
-- kind: the character has the item that makes it) }; demand = crafts a day the market takes, nil when the sale has no
-- limit (a vendor).
--   spell  one craft per cooldown is all there is: crafts = min(demand, 1 per cooldown). A hard cap.
--   item   the own cooldown makes quantity units per cooldown (when the tool is held), the AH sells the rest of what the
--          demand needs: crafts = demand, split in own (cheap, limited) and ah (bought). No demand, no figure: the
--          AH could sell any number. Self-made units are costed at their AH value, so profit per craft is unchanged.
-- Returns { crafts, own, ah (crafts a day, own + ah = crafts), cap (spell kind: the cooldown's crafts a day), limit =
-- "cooldown" | "demand" | nil } or nil when there is no figure.
function Profit.CooldownDay(c, demand)
	local days = c.ms / 86400000
	if c.kind == "spell" then
		local cap = 1 / days
		if demand and demand < cap then
			return { crafts = demand, own = demand, ah = 0, cap = cap, limit = "demand" }
		end
		return { crafts = cap, own = cap, ah = 0, cap = cap, limit = "cooldown" }
	end
	if not demand then
		return nil
	end
	local own = c.toolHeld and (c.quantity / days) / math.max(c.perCraft, 1) or 0
	own = math.min(own, demand)
	return { crafts = demand, own = own, ah = demand - own, limit = "demand" }
end

-- Return on the gold put in (#197): profit / cost x 100. nil unless both are known and the cost is above
-- zero (a free craft has no ratio), so such rows can go last.
function Profit.Percent(profit, cost)
	if profit == nil or cost == nil or cost <= 0 then
		return nil
	end
	return profit / cost * 100
end

-- Comparator for rows { pct, profit, name }: highest % first (desc) or lowest first; rows without a % last
-- either way (among themselves by profit, desc, then name); equal % by absolute profit, then name.
function Profit.ByPercent(desc)
	return function(a, b)
		local pa, pb = a.pct, b.pct
		if (pa == nil) ~= (pb == nil) then
			return pa ~= nil
		end
		if pa ~= nil and pa ~= pb then
			if desc then
				return pa > pb
			end
			return pa < pb
		end
		local fa, fb = a.profit, b.profit
		if (fa == nil) ~= (fb == nil) then
			return fa ~= nil
		end
		if fa ~= nil and fa ~= fb then
			return fa > fb
		end
		return tostring(a.name or "") < tostring(b.name or "")
	end
end

-- Sort comparator factory. Rows without the key sort last regardless of direction.
function Profit.Comparator(key, desc)
	return function(a, b)
		local va, vb = a[key], b[key]
		if va == nil and vb == nil then
			return (a.name or "") < (b.name or "")
		elseif va == nil then
			return false
		elseif vb == nil then
			return true
		elseif va == vb then
			return (a.name or "") < (b.name or "")
		end
		if type(va) == "string" then
			va, vb = va:lower(), vb:lower()
		end
		if desc then
			return va > vb
		end
		return va < vb
	end
end

----------------------------------------------------------------------------------------------------
-- Craft run planner (#388): which crafts to make, how many, under a gold budget and a time limit
----------------------------------------------------------------------------------------------------

Profit.RUN_MAX_STEPS = 3000 -- crafts one plan can hold at most (a guard, not a limit anyone should meet)

-- Pure: takes candidates with their figures already worked out (Basket.RunCandidates), reads nothing from the client.
-- cands: { { recipeID, professionID, name, outputItemID, seconds (per craft), timeLabel, channel ("vendor" | "AH"),
--            each (what one craft sells for after the cut or at the vendor), cap (most crafts the demand allows, nil =
--            no cap), capText (where the cap comes from), quote(n) } }
--   quote(n) -> { cost (what n crafts' reagents are worth at the cheaper of vendor and AH, the depth tiers walked for
--                 n crafts, intermediates min(buy, craft), what the bags hold counted at that value too: profit),
--                 cash (what is still to be bought after the bags: the budget), seconds (the crafts of intermediates
--                 on top of the n crafts) } | nil when a price or a time is missing.
-- opts: { budget = copper | nil, seconds = crafting time | nil, total = fn(lines) -> copper (the cash of all lines
--         together, so reagents shared between two crafts and the bags count once) | nil }
-- The best craft per crafting second is taken one craft at a time (the next craft's own profit, so the dearer depth tiers
-- of a 40-unit purchase count) until the budget or the time is used or the demand cap is met.
-- Returns { lines = { { recipeID, ..., count, profit, profitEach, seconds, secEach, cost, cash, channel, cap, capText,
--           capped } } best first, cost (cash), profit, seconds, limit = "budget" | "time" | "supply" | "demand" | nil (what
--           stopped the plan) }.
function Profit.RunPlan(cands, opts)
	opts = opts or {}
	local state = {}
	for i, c in ipairs(cands or {}) do
		state[i] = { cand = c, n = 0, cost = 0, cash = 0, extra = 0 }
	end
	local limits = {}
	local spent, secs, steps = 0, 0, 0
	local picks = {} -- the states in the order their crafts were taken

	-- The next craft of a state: { dCost, dCash, dSec, dProfit, pps } or nil (nothing more to take, limits[...] set).
	local function Next(s)
		local c = s.cand
		if c.cap and s.n >= c.cap then
			limits.demand = true
			return nil
		end
		local q = c.quote(s.n + 1)
		if not (q and q.cost and q.cash) then
			if s.n > 0 then
				limits.supply = true -- the first craft was priced, the next is not: the stored tiers hold no more
			end
			return nil
		end
		local dSec = (c.seconds or 0) + ((q.seconds or 0) - s.extra)
		local dProfit = c.each - (q.cost - s.cost)
		if dSec <= 0 or dProfit <= 0 then
			return nil
		end
		return { dCost = q.cost - s.cost, dCash = q.cash - s.cash, dSec = dSec, dProfit = dProfit, pps = dProfit / dSec,
			q = q }
	end
	for _, s in ipairs(state) do
		s.next = Next(s)
	end

	while steps < Profit.RUN_MAX_STEPS do
		local best
		for _, s in ipairs(state) do
			local nx = s.next
			if nx then
				if opts.budget and spent + nx.dCash > opts.budget then
					limits.budget = true
					s.next = nil
				elseif opts.seconds and secs + nx.dSec > opts.seconds then
					limits.time = true
					s.next = nil
				elseif not best or nx.pps > best.next.pps
					or (nx.pps == best.next.pps and (nx.dProfit > best.next.dProfit
						or (nx.dProfit == best.next.dProfit and tostring(s.cand.name or "") < tostring(best.cand.name or "")))) then
					best = s
				end
			end
		end
		if not best then
			break
		end
		local nx = best.next
		best.n, best.cost, best.cash, best.extra = best.n + 1, nx.q.cost, nx.q.cash, nx.q.seconds or 0
		spent, secs, steps = spent + nx.dCash, secs + nx.dSec, steps + 1
		picks[#picks + 1] = best
		best.next = Next(best)
	end

	local function Lines()
		local out = {}
		for _, s in ipairs(state) do
			if s.n > 0 then
				local c = s.cand
				local seconds = s.n * (c.seconds or 0) + s.extra
				local profit = s.n * c.each - s.cost
				out[#out + 1] = { recipeID = c.recipeID, professionID = c.professionID, name = c.name, outputItemID = c.outputItemID,
					count = s.n, channel = c.channel, profit = profit, profitEach = profit / s.n, seconds = seconds,
					secEach = seconds / s.n, cost = s.cost, cash = s.cash, cap = c.cap, capText = c.capText, timeLabel = c.timeLabel,
					capped = c.cap ~= nil and s.n >= c.cap, cooldown = c.cooldown, sales = s.n * c.each, pps = seconds > 0 and profit / seconds or 0 }
			end
		end
		table.sort(out, function(a, b)
			if a.pps ~= b.pps then
				return a.pps > b.pps
			end
			if a.profit ~= b.profit then
				return a.profit > b.profit
			end
			return tostring(a.name or "") < tostring(b.name or "")
		end)
		return out
	end

	-- The independent sums can spend a shared reagent or a held stack twice: the cash of all the lines together decides.
	-- It is nil when the lines together need more than the AH lists (two crafts sharing a reagent whose tiers run out):
	-- crafts come off the end of the plan until it can be bought, in steps while it is far off.
	local lines = Lines()
	local cash
	if opts.total and #lines > 0 then
		cash = opts.total(lines)
		local guard = 0
		while #picks > 0 and guard < 400 and (cash == nil or (opts.budget and cash > opts.budget)) do
			guard = guard + 1
			for _ = 1, cash == nil and math.ceil(#picks / 20) or 1 do
				local s = table.remove(picks)
				if not s then
					break
				end
				s.n = s.n - 1
				local q = s.n > 0 and s.cand.quote(s.n) or nil
				if q then
					s.cost, s.cash, s.extra = q.cost, q.cash, q.seconds or 0
				else
					s.n, s.cost, s.cash, s.extra = 0, 0, 0, 0
				end
			end
			if cash == nil then
				limits.supply = true
			else
				limits.budget = true
			end
			lines = Lines()
			cash = 0
			if #lines > 0 then
				cash = opts.total(lines)
			end
		end
	end
	local plan = { lines = lines, cost = 0, profit = 0, seconds = 0, sales = 0 }
	for _, l in ipairs(lines) do
		plan.cost, plan.profit, plan.seconds, plan.sales = plan.cost + l.cash, plan.profit + l.profit, plan.seconds + l.seconds, plan.sales + l.sales
	end
	if cash then
		plan.cost = cash
	end
	plan.limit = (limits.budget and "budget") or (limits.time and "time") or (limits.supply and "supply")
		or (limits.demand and "demand") or nil
	return plan
end
