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
