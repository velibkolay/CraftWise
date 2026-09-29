-- Pure profit maths; no client calls except through the price functions passed in.
local _, ns = ...

local Profit = {}
ns.Profit = Profit

-- recipe: { reagents = { { itemID, quantity } }, output = { itemID, quantity } | nil,
--           learned = bool, learnCost = copper | nil }
-- prices: { buy = fn(itemID) -> { copper, source, age } | nil,
--           sell = fn(itemID) -> { copper, source, age } | nil }
-- Returns a result table. A missing price never counts as 0: the result is marked incomplete.
function Profit.Evaluate(recipe, prices)
	local result = {
		cost = 0,
		complete = true,
		costComplete = true, -- every reagent priced
		missing = {}, -- itemIDs without any price
		reagents = {}, -- per reagent: { itemID, quantity, unit, total, source, age }
		oldestAge = nil,
	}

	local function noteAge(age)
		if age and (not result.oldestAge or age > result.oldestAge) then
			result.oldestAge = age
		end
	end

	for _, r in ipairs(recipe.reagents or {}) do
		local price = prices.buy(r.itemID)
		local line = { itemID = r.itemID, quantity = r.quantity }
		if price then
			line.unit, line.source, line.age = price.copper, price.source, price.age
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
			noteAge(value.age)
		else
			result.complete = false
			table.insert(result.missing, recipe.output.itemID)
		end
	else
		result.noItemOutput = true -- enchants and similar: no market value
	end

	if result.sellsFor and result.complete then
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
