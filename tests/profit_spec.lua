local ns = LoadAddon()
local P = ns.Profit

local function prices(buy, sell)
	return {
		buy = function(id) return buy[id] and { copper = buy[id], source = "auction", age = 1 } end,
		sell = function(id) return sell[id] and { copper = sell[id], source = "auction", age = 3 } end,
	}
end

it("sums reagent cost and computes profit", function()
	local r = P.Evaluate({ learned = true,
		reagents = { { itemID = 1, quantity = 2 }, { itemID = 2, quantity = 1 } },
		output = { itemID = 9, quantity = 1 } }, prices({ [1] = 100, [2] = 50 }, { [9] = 400 }))
	eq(r.cost, 250); eq(r.sellsFor, 400); eq(r.profit, 150); eq(r.complete, true)
	eq(r.oldestAge, 3)
end)

it("never treats a missing reagent price as free", function()
	local r = P.Evaluate({ learned = true,
		reagents = { { itemID = 1, quantity = 2 }, { itemID = 2, quantity = 1 } },
		output = { itemID = 9, quantity = 1 } }, prices({ [1] = 100 }, { [9] = 400 }))
	eq(r.complete, false); eq(r.profit, nil); eq(#r.missing, 1); eq(r.missing[1], 2)
end)

it("missing output price leaves profit nil", function()
	local r = P.Evaluate({ learned = true, reagents = { { itemID = 1, quantity = 1 } },
		output = { itemID = 9, quantity = 1 } }, prices({ [1] = 100 }, {}))
	eq(r.profit, nil); eq(r.complete, false)
end)

it("multiplies by average output quantity", function()
	local r = P.Evaluate({ learned = true, reagents = { { itemID = 1, quantity = 1 } },
		output = { itemID = 9, quantity = 1.5 } }, prices({ [1] = 100 }, { [9] = 100 }))
	eq(r.sellsFor, 150); eq(r.profit, 50)
end)

it("enchant-style recipes without item output have no profit", function()
	local r = P.Evaluate({ learned = true, reagents = { { itemID = 1, quantity = 1 } } }, prices({ [1] = 100 }, {}))
	eq(r.noItemOutput, true); eq(r.profit, nil); eq(r.cost, 100)
end)

it("recipe without reagent data is incomplete", function()
	local r = P.Evaluate({ learned = false, output = { itemID = 9, quantity = 1 } }, prices({}, { [9] = 100 }))
	eq(r.complete, false); eq(r.profit, nil)
end)

it("learn cost and break-even for unlearned recipes", function()
	local r = P.Evaluate({ learned = false, learnCost = 1000, reagents = { { itemID = 1, quantity = 1 } },
		output = { itemID = 9, quantity = 1 } }, prices({ [1] = 100 }, { [9] = 400 }))
	eq(r.learnCost, 1000); eq(r.breakEven, 4) -- 1000 / 300 -> 3.33 -> 4 crafts
end)

it("no break-even when the craft loses money", function()
	local r = P.Evaluate({ learned = false, learnCost = 1000, reagents = { { itemID = 1, quantity = 1 } },
		output = { itemID = 9, quantity = 1 } }, prices({ [1] = 500 }, { [9] = 400 }))
	eq(r.profit, -100); eq(r.breakEven, nil)
end)

it("learned recipes ignore learn cost", function()
	local r = P.Evaluate({ learned = true, learnCost = 1000, reagents = { { itemID = 1, quantity = 1 } },
		output = { itemID = 9, quantity = 1 } }, prices({ [1] = 100 }, { [9] = 400 }))
	eq(r.learnCost, nil); eq(r.breakEven, nil)
end)

it("comparator sorts nil values last in both directions", function()
	local rows = { { name = "a", profit = 5 }, { name = "b" }, { name = "c", profit = 10 } }
	table.sort(rows, P.Comparator("profit", true))
	eq(rows[1].name, "c"); eq(rows[2].name, "a"); eq(rows[3].name, "b")
	table.sort(rows, P.Comparator("profit", false))
	eq(rows[1].name, "a"); eq(rows[2].name, "c"); eq(rows[3].name, "b")
end)

----------------------------------------------------------------------------------------------------
-- Vendor check (#185)
----------------------------------------------------------------------------------------------------

local function Vendor(buy, sell, ah)
	return { buy = function(id) return buy[id] end, sell = function(id) return sell[id] end,
		auction = function(id) return ah and ah[id] end }
end

local function Check(recipe, ahBuy, vendorBuy, vendorSell)
	local r = P.Evaluate(recipe, prices(ahBuy, {}))
	return P.VendorCheck(r, recipe, Vendor(vendorBuy, vendorSell, ahBuy))
end

local TWO = { learned = true, reagents = { { itemID = 1, quantity = 2 }, { itemID = 2, quantity = 1 } },
	output = { itemID = 9, quantity = 1 } }

it("vendor check: sale = vendor sell x output quantity, profit = sale - reagent cost, loop when all reagents are vendor goods", function()
	local r = Check({ learned = true, reagents = { { itemID = 1, quantity = 2 }, { itemID = 2, quantity = 1 } },
		output = { itemID = 9, quantity = 3 } }, { [1] = 100, [2] = 50 }, { [1] = 20, [2] = 30 }, { [9] = 40 })
	eq(r.vendorSale, 120); eq(r.cost, 250); eq(r.vendorProfit, -130)
	eq(r.vendorCost, 70); eq(r.vendorLoop, true) -- at vendor prices 120 - 70 > 0, whatever the AH says
	eq(r.reagents[1].vendorBuy, 20); eq(r.reagents[1].ahUnit, 100)
end)

it("vendor check: reagent cost is each reagent where cheaper, vendor profit uses it", function()
	local r = P.Evaluate(TWO, { buy = function(id) return { copper = id == 1 and 10 or 50, source = id == 1 and "vendor" or "auction" } end,
		sell = function() return nil end })
	P.VendorCheck(r, TWO, Vendor({ [1] = 10 }, { [9] = 100 }))
	eq(r.cost, 70); eq(r.vendorProfit, 30)
	eq(r.vendorCost, nil); eq(r.vendorLoop, nil) -- reagent 2 has no vendor price: no loop
end)

it("vendor check: no vendor sell price (nil or 0) means no vendor sale and no vendor profit, never 0", function()
	for _, sell in ipairs({ {}, { [9] = 0 } }) do
		local r = Check(TWO, { [1] = 1, [2] = 1 }, { [1] = 1, [2] = 1 }, sell)
		eq(r.vendorSale, nil); eq(r.vendorProfit, nil); eq(r.vendorLoop, nil)
		eq(r.vendorCost, 3) -- the cost side is still known
	end
end)

it("vendor check: a reagent without any price gives no vendor profit; a loop needs every vendor buy price", function()
	local r = Check(TWO, { [1] = 100 }, { [1] = 5, [2] = 5 }, { [9] = 500 })
	eq(r.vendorSale, 500); eq(r.vendorProfit, nil) -- reagent 2 has no AH price, cost incomplete
	eq(r.vendorCost, 15); eq(r.vendorLoop, true) -- but both are vendor goods
	r = Check(TWO, { [1] = 100, [2] = 100 }, { [1] = 5 }, { [9] = 500 })
	eq(r.vendorProfit, 200); eq(r.vendorLoop, nil)
end)

it("vendor check: a vendor sale that does not beat the vendor cost is no loop", function()
	local r = Check(TWO, { [1] = 1, [2] = 1 }, { [1] = 10, [2] = 10 }, { [9] = 30 })
	eq(r.vendorCost, 30); eq(r.vendorLoop, nil)
end)

it("vendor check: recipes without an item or without reagents have no sale and no loop", function()
	local r = Check({ learned = true, reagents = { { itemID = 1, quantity = 1 } } }, { [1] = 1 }, { [1] = 1 }, {})
	eq(r.vendorSale, nil); eq(r.vendorLoop, nil)
	r = Check({ learned = true, reagents = {}, output = { itemID = 9, quantity = 1 } }, {}, {}, { [9] = 10 })
	eq(r.vendorCost, nil); eq(r.vendorLoop, nil)
end)

it("vendor check: multi-output recipes use the average output quantity", function()
	local r = Check({ learned = true, reagents = { { itemID = 1, quantity = 1 } }, output = { itemID = 9, quantity = 1.5 } },
		{ [1] = 10 }, { [1] = 10 }, { [9] = 20 })
	eq(r.vendorSale, 30); eq(r.vendorProfit, 20); eq(r.vendorLoop, true)
end)
