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
	return result
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
