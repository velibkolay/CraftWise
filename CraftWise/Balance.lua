-- Reagent balance for one recipe (#49): how many crafts what you hold allows, which reagent limits
-- it, and what to buy so the other reagents don't sit unused.
--
--   crafts possible  = how many crafts the held reagents cover together. A reagent you can make
--                      with a recipe you know (Light Hide + Salt -> Cured Light Hide, scraps -> Light
--                      Leather) counts with what its held inputs become. Inputs are shared: one Salt
--                      is never counted twice.
--   covers           = crafts one reagent allows on its own (held plus what you can make of it).
--   warning          = the largest reagent covers at least 2x and at least 5 more crafts than the
--                      limiting one (decision 1 on #49).
--   buy list         = per reagent, what is missing for the target count (default: what the largest
--                      reagent covers), after using what you hold and can make. A missing reagent
--                      that a known recipe makes more cheaply (the cost line's decision, #47
--                      Profit.UnitCost, at market prices) is crafted: its inputs go on the list
--                      instead (#60).
-- Balance.Analyze is pure (counts and recipes come in as functions); ns.ReagentBalance wires it to
-- Holdings, your known recipes and prices.
local _, ns = ...

local Balance = {}
ns.Balance = Balance

Balance.WARN_RATIO = 2
Balance.WARN_MORE = 5
Balance.MAX_DEPTH = 2 -- intermediate of an intermediate at most
Balance.MAX_CRAFTS = 1000 -- stop counting there (shown as "1000+")

local function Snapshot(pool)
	local copy = {}
	for k, v in pairs(pool) do
		copy[k] = v
	end
	return copy
end

local function Restore(pool, snap)
	for k in pairs(pool) do
		pool[k] = snap[k]
	end
end

-- A pool of held items, read from held(itemID) on first use.
local function Pool(held)
	local pool = {}
	return pool, function(itemID)
		if pool[itemID] == nil then
			pool[itemID] = held(itemID) or 0
		end
		return pool[itemID]
	end
end

-- Yield of a known recipe per craft; a variable yield counts its stored mean, never less than 1.
local function Yield(maker)
	return math.max(1, math.floor((maker.output and maker.output.quantity) or 1))
end

-- Takes up to `amount` of itemID from the pool: held units first, then crafts from held inputs
-- (one craft at a time, an incomplete craft is undone). Returns the units obtained and how many of
-- them were crafted.
local function Take(pool, get, makers, itemID, amount, depth, visiting)
	local have = get(itemID)
	local got = math.min(have, amount)
	pool[itemID] = have - got
	local crafted = 0
	if got < amount and depth < Balance.MAX_DEPTH and not visiting[itemID] then
		visiting[itemID] = true
		for _, maker in ipairs(makers(itemID) or {}) do
			local yield = Yield(maker)
			local guard = 0
			while got < amount and guard < Balance.MAX_CRAFTS * 10 do
				guard = guard + 1
				local snap = Snapshot(pool)
				local ok = true
				for _, r in ipairs(maker.reagents or {}) do
					local n = Take(pool, get, makers, r.itemID, r.quantity, depth + 1, visiting)
					if n < r.quantity then
						ok = false
						break
					end
				end
				if not ok then
					Restore(pool, snap)
					break
				end
				local use = math.min(yield, amount - got)
				got, crafted = got + use, crafted + use
				pool[itemID] = (pool[itemID] or 0) + yield - use
			end
			if got >= amount then
				break
			end
		end
		visiting[itemID] = nil
	end
	return got, crafted
end

-- One craft from the pool; undone when a reagent is short.
local function CraftOnce(pool, get, makers, reagents)
	local snap = Snapshot(pool)
	for _, r in ipairs(reagents) do
		if Take(pool, get, makers, r.itemID, r.quantity, 0, {}) < r.quantity then
			Restore(pool, snap)
			return false
		end
	end
	return true
end

-- reagents: { { itemID, quantity } }; held(itemID) -> count in the counted places;
-- makers(itemID) -> known recipes that make it { { reagents, output = { itemID, quantity } } } or nil;
-- target: crafts to buy for (nil = what the largest reagent covers).
-- Returns { possible, lines = { { itemID, quantity, held, units, made, covers } }, limiting, largest,
-- warn, target, buy = { { itemID, quantity } }, leftover, capped }. leftover: the counted pool after the
-- buy list took what it could (what Balance.Expand starts from).
function Balance.Analyze(reagents, held, makers, target)
	makers = makers or function() return nil end
	local result = { lines = {}, buy = {} }
	if not reagents or #reagents == 0 then
		result.possible = 0
		return result
	end
	-- Each reagent alone: everything you hold of it or can make of it.
	for _, r in ipairs(reagents) do
		local pool, get = Pool(held)
		local cap = r.quantity * Balance.MAX_CRAFTS
		local units, made = Take(pool, get, makers, r.itemID, cap, 0, {})
		local line = { itemID = r.itemID, quantity = r.quantity, held = held(r.itemID) or 0, units = units, made = made,
			covers = math.floor(units / r.quantity) }
		result.lines[#result.lines + 1] = line
		if not result.limiting or line.covers < result.limiting.covers then
			result.limiting = line
		end
		if not result.largest or line.covers > result.largest.covers then
			result.largest = line
		end
	end
	-- All reagents together, sharing inputs.
	local pool, get = Pool(held)
	local possible = 0
	while possible < Balance.MAX_CRAFTS and CraftOnce(pool, get, makers, reagents) do
		possible = possible + 1
	end
	result.possible, result.capped = possible, possible >= Balance.MAX_CRAFTS or nil
	local low, high = result.limiting.covers, result.largest.covers
	result.warn = #reagents > 1 and high >= low * Balance.WARN_RATIO and high - low >= Balance.WARN_MORE or false
	-- Buy list for the target count: what is left short after holding and making.
	result.target = math.min(target or high, Balance.MAX_CRAFTS)
	if result.target > possible then
		local need = {}
		pool, get = Pool(held)
		for _, r in ipairs(reagents) do
			local want = r.quantity * result.target
			local got = Take(pool, get, makers, r.itemID, want, 0, {})
			if got < want then
				need[r.itemID] = (need[r.itemID] or 0) + want - got
			end
		end
		result.leftover = Snapshot(pool)
		for _, r in ipairs(reagents) do
			if need[r.itemID] then
				result.buy[#result.buy + 1] = { itemID = r.itemID, quantity = need[r.itemID] }
				need[r.itemID] = nil
			end
		end
	end
	return result
end

-- Craft or buy for the buy list (#60). Each missing reagent goes through choose(itemID, depth,
-- visiting) -> recipe, info | nil, the cost line's decision: nil buys it; a recipe crafts it, and that
-- recipe's inputs for the crafts needed are taken from what is left of what you hold (and can make
-- from it), the rest is missing in turn (an input can itself be crafted). visiting holds the items
-- being crafted up the chain (cycle guard; the depth limit is choose's, as in Profit.UnitCost).
-- buy: Analyze's list; leftover: Analyze's pool; held(itemID) for items the pool hasn't read yet.
-- Returns { buy = { { itemID, quantity } }, crafts = { { itemID, quantity, crafts, depth, info } } }.
function Balance.Expand(buy, leftover, held, makers, choose, visiting)
	makers = makers or function() return nil end
	visiting = visiting or {}
	local pool = Snapshot(leftover or {})
	local function get(itemID)
		if pool[itemID] == nil then
			pool[itemID] = held(itemID) or 0
		end
		return pool[itemID]
	end
	local out, buyAt, craftAt = { buy = {}, crafts = {} }, {}, {}
	local function add(list, at, itemID, fields)
		local entry = at[itemID]
		if entry then
			for k, v in pairs(fields) do
				if type(v) == "number" and k ~= "depth" then
					entry[k] = entry[k] + v
				end
			end
		else
			entry = fields
			entry.itemID = itemID
			list[#list + 1] = entry
			at[itemID] = entry
		end
	end
	local function need(itemID, quantity, depth)
		local recipe, info
		if choose and not visiting[itemID] then
			recipe, info = choose(itemID, depth, visiting)
		end
		if not (recipe and recipe.reagents and #recipe.reagents > 0) then
			add(out.buy, buyAt, itemID, { quantity = quantity })
			return
		end
		local yield = Yield(recipe)
		local crafts = math.ceil(quantity / yield)
		add(out.crafts, craftAt, itemID, { quantity = quantity, crafts = crafts, depth = depth, info = info })
		visiting[itemID] = true
		for _, r in ipairs(recipe.reagents) do
			local want = r.quantity * crafts
			local got = Take(pool, get, makers, r.itemID, want, 0, {})
			if got < want then
				need(r.itemID, want - got, depth + 1)
			end
		end
		visiting[itemID] = nil
		pool[itemID] = get(itemID) + crafts * yield - quantity -- spare units of a multi-unit craft
	end
	for _, b in ipairs(buy or {}) do
		need(b.itemID, b.quantity, 0)
	end
	return out
end

----------------------------------------------------------------------------------------------------
-- Wiring: known recipes, holdings, prices
----------------------------------------------------------------------------------------------------

-- Recipes this character knows, by the item they make: [itemID] = { { recipeID, reagents, output } }.
-- Rebuilt when the recipe cache changes.
local makersIndex
local recipesVersion = 0
ns.Listen("RECIPES_CHANGED", function()
	makersIndex = nil
	recipesVersion = recipesVersion + 1
end)

function Balance.Makers()
	if makersIndex then
		return makersIndex
	end
	local index = {}
	for _, prof in pairs(ns.charDB and ns.charDB.professions or {}) do
		for recipeID, recipe in pairs(prof.recipes or {}) do
			if recipe.learned then
				local reagents, output = recipe.reagents, recipe.output
				if not reagents then
					local bundledReagents, bundledOutput = ns.BundledRecipe(recipeID)
					reagents, output = bundledReagents, output or bundledOutput
				end
				if reagents and output and output.itemID then
					index[output.itemID] = index[output.itemID] or {}
					table.insert(index[output.itemID], { recipeID = recipeID, reagents = reagents, output = output })
				end
			end
		end
	end
	for _, list in pairs(index) do
		table.sort(list, function(a, b) return a.recipeID < b.recipeID end)
	end
	makersIndex = index
	return index
end

-- Cheapest way to buy `quantity` units: vendor (recorded or bundled price) or the AH at the profit
-- house from its cheapest tiers (#26 depth). Returns { cost, source = "vendor"|"auction", label,
-- noDepth } or nil plus { listed, house } when the stored tiers hold fewer units.
function ns.BuyQuote(itemID, quantity)
	local best
	local vendor = ns.GetVendorBuyPrice(itemID)
	if vendor then
		best = { cost = vendor * quantity, source = "vendor", label = "vendor" }
	end
	local short
	local house, houseLabel = ns.ProfitHouse()
	local depth = house and ns.Market.Depth(itemID, house)
	if depth and depth[1] then
		local fill = ns.Market.FillBatch(depth, quantity)
		if fill then
			if not best or fill.cost < best.cost then
				best = { cost = fill.cost, source = "auction", label = houseLabel, top = fill.top }
			end
		else
			local listed = 0
			for _, tier in ipairs(depth) do
				listed = listed + tier.qty
			end
			short = { listed = listed, house = houseLabel }
		end
	else
		-- No depth recorded at the profit house: the unit price ns.AuctionQuote has (profit house
		-- browse price or Auctionator), labelled "depth unknown".
		local quote = ns.AuctionQuote(itemID)
		if quote and (not best or quote.copper * quantity < best.cost) then
			best = { cost = quote.copper * quantity, source = "auction", label = quote.label, noDepth = true }
		end
	end
	if best then
		return best
	end
	return nil, short
end

-- Everything the tooltip shows for one recipe's reagents: Balance.Analyze plus the counted places
-- and a priced buy list { { itemID, quantity, quote, short } } with total (nil parts = complete false).
-- Analyses are cached per recipe (reagent list) and target until a counted place or the known
-- recipes change (Holdings.version: bags, bank scan, mail scan; RECIPES_CHANGED), so hovering the
-- same items again doesn't simulate every craft again. Prices and the places text are read fresh.
local cache, cacheStamp = {}, nil

local function CacheKey(reagents, target)
	local parts = { tostring(target or "") }
	for _, r in ipairs(reagents) do
		parts[#parts + 1] = r.itemID .. "x" .. r.quantity
	end
	return table.concat(parts, ",")
end

function Balance.Cached(reagents, target)
	local stamp = ns.Holdings.version .. ":" .. recipesVersion
	if stamp ~= cacheStamp then
		cache, cacheStamp = {}, stamp
	end
	local key = CacheKey(reagents, target)
	local hit = cache[key]
	if hit then
		return hit
	end
	local count = ns.Holdings.Counter()
	local makers = Balance.Makers()
	hit = Balance.Analyze(reagents, count, function(itemID)
		return makers[itemID]
	end, target)
	cache[key] = hit
	return hit
end

-- The cost line's craft-or-buy decision for the buy list (#60): Profit.UnitCost with known recipes
-- and market prices, always the "AH" cost basis (price basis #39, profit house), whatever the view's
-- cost basis: the buy list is about units you don't hold yet, and a paid cost can't apply to units
-- you still have to buy (Scout decision on #60). Crafted -> the recipe it used.
function Balance.Chooser()
	local prices = ns.ReagentPrices(nil, "ah")
	return function(itemID, depth, visiting)
		local unit = ns.Profit.UnitCost(itemID, prices, depth, visiting)
		if unit and unit.crafted and unit.recipe then
			return unit.recipe, unit
		end
	end
end

-- outputItemID: the item the recipe makes, never crafted inside its own buy list. Prices and
-- craft-or-buy decisions are read fresh.
function ns.ReagentBalance(reagents, target, outputItemID)
	local analysis = Balance.Cached(reagents, target)
	local result = setmetatable({ buy = {}, crafts = {} }, { __index = analysis })
	result.counted, result.notCounted = ns.Holdings.PlacesText()
	result.total, result.complete = 0, true
	local buy = analysis.buy
	if #buy > 0 then
		local count
		local function held(itemID)
			count = count or ns.Holdings.Counter()
			return count(itemID)
		end
		local makers = Balance.Makers()
		local expanded = Balance.Expand(buy, analysis.leftover, held, function(itemID)
			return makers[itemID]
		end, Balance.Chooser(), outputItemID and { [outputItemID] = true } or {})
		buy, result.crafts = expanded.buy, expanded.crafts
	end
	for i, b in ipairs(buy) do
		local line = { itemID = b.itemID, quantity = b.quantity }
		line.quote, line.short = ns.BuyQuote(line.itemID, line.quantity)
		if line.quote then
			result.total = result.total + line.quote.cost
		else
			result.complete = false
		end
		result.buy[i] = line
	end
	return result
end

-- Tooltip lines { left, right } for a recipe's reagents; empty when none of them is held (directly
-- or through what you can make), so recipes you have nothing for stay short.
function ns.BalanceLines(reagents, target, outputItemID)
	if not reagents or #reagents == 0 then
		return {}
	end
	local b = ns.ReagentBalance(reagents, target, outputItemID)
	local any = false
	for _, l in ipairs(b.lines) do
		if l.units > 0 then
			any = true
		end
	end
	if not any then
		return {}
	end
	local C = ns.Style.colors
	local money = ns.FormatMoney
	local function name(itemID)
		return (C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)) or ("item " .. itemID)
	end
	local function crafts(n)
		return n >= Balance.MAX_CRAFTS and (Balance.MAX_CRAFTS .. "+") or tostring(n)
	end
	local lines = {}
	local function add(l, r)
		lines[#lines + 1] = { l, r }
	end
	add("|cffffd100Your reagents|r", "")
	for _, l in ipairs(b.lines) do
		local held = ("hold %d"):format(l.units)
		if l.made > 0 then
			held = ("hold %d %s"):format(l.units, C.muted .. ("(%d made from what you hold)|r"):format(l.made))
		end
		local color = l == b.limiting and b.warn and C.warn or ""
		add(("  %d × %s"):format(l.quantity, name(l.itemID)), ("%s  %s%s crafts|r"):format(held, color, crafts(l.covers)))
	end
	add("  Crafts possible", (b.warn and C.warn or C.good) .. crafts(b.possible) .. "|r")
	if b.warn then
		add(C.warn .. ("  %s limits you to %s crafts; you hold %s for %s.|r"):format(name(b.limiting.itemID), crafts(b.limiting.covers),
			name(b.largest.itemID), crafts(b.largest.covers)), "")
	end
	if #b.buy > 0 or #b.crafts > 0 then
		add(("|cffffd100To buy for %s crafts|r"):format(crafts(b.target)), "")
		-- Intermediates cheaper to craft (#60): what to make, with both unit values as the cost line.
		for _, c in ipairs(b.crafts) do
			local left = ("  %sCraft %d × %s"):format(string.rep("  ", c.depth), c.quantity, name(c.itemID))
			if c.crafts ~= c.quantity then
				left = left .. (" (%d crafts)"):format(c.crafts)
			end
			local right = ""
			local u = c.info
			if u and u.craftUnit then
				local bought = u.buyUnit and (money(u.buyUnit) .. " " .. (u.buySource == "vendor" and "vendor" or (u.buyLabel or "AH")))
					or ns.Market.NO_DATA
				right = C.muted .. "each: crafted " .. money(u.craftUnit) .. " · bought " .. bought .. "|r"
			end
			add(left, right)
		end
		for _, line in ipairs(b.buy) do
			local right
			if line.quote then
				local where = line.quote.source == "vendor" and "vendor"
					or line.quote.noDepth and (line.quote.label .. ", depth unknown")
					or ("AH · " .. (line.quote.label or "?"))
				right = money(line.quote.cost) .. "  " .. C.muted .. where .. "|r"
			elseif line.short then
				right = C.warn .. ("only %d listed at %s|r"):format(line.short.listed, line.short.house or "?")
			else
				right = C.muted .. ns.Market.NO_DATA .. "|r"
			end
			add(("  %d × %s"):format(line.quantity, name(line.itemID)), right)
		end
		add("  Total", money(b.total) .. (b.complete and "" or (C.warn .. " + ?|r")))
	end
	add(C.muted .. "  Counted: " .. b.counted .. "|r", "")
	if b.notCounted then
		add(C.muted .. "  Not counted: " .. b.notCounted .. "|r", "")
	end
	return lines, b
end
