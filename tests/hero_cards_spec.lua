-- Issue #152: hero card models (best craft, best skill-up, best recipe to learn, bag value, auction totals).
-- Invented rows in the shape the existing models produce.
local function Load()
	local ns, stub = LoadAddon()
	return ns, stub
end

local function Counter(held)
	return function(id) return held[id] or 0 end
end

it("best craft: highest profit among known, priced recipes, with colour, chance and shortages", function()
	local ns = Load()
	local rows = {
		{ recipeID = 1, name = "Alpha", status = "known", profit = 500, cost = 100, sellsFor = 600, skillColor = "yellow",
			difficulty = 1, outputItemID = 11, sellSource = "auction", reagents = { { itemID = 70, quantity = 2 }, { itemID = 71, quantity = 1 } } },
		{ recipeID = 2, name = "Beta", status = "known", profit = 900, cost = 100, sellsFor = 1000, skillColor = "green",
			difficulty = 2, reagents = { { itemID = 70, quantity = 3 }, { itemID = 71, quantity = 5 }, { itemID = 72, quantity = 1 } } },
		{ recipeID = 3, name = "Gamma", status = "trainable", profit = 5000, reagents = {} },
		{ recipeID = 4, name = "Delta", status = "known", profit = nil, reagents = {} },
	}
	local hero = ns.HeroCards.BestCraft(rows, { counter = Counter({ [70] = 3, [71] = 2 }), skill = 100 })
	eq(hero.recipeID, 2); eq(hero.profit, 900); eq(hero.cost, 100); eq(hero.sale, 1000); eq(hero.color, "green")
	eq(hero.candidates, 2)
	eq(#hero.short, 2); eq(hero.short[1].itemID, 71); eq(hero.short[1].missing, 3); eq(hero.short[2].itemID, 72); eq(hero.short[2].missing, 1)
	eq(hero.chance, nil, "no thresholds and no measured crafts: no chance, not 0")
end)

it("best craft: a tie goes to the name, nothing short gives an empty list, reasons without an answer", function()
	local ns = Load()
	local rows = {
		{ recipeID = 2, name = "Zed", status = "known", profit = 10, reagents = { { itemID = 70, quantity = 1 } } },
		{ recipeID = 1, name = "Abe", status = "known", profit = 10, reagents = { { itemID = 70, quantity = 1 } } },
	}
	local hero = ns.HeroCards.BestCraft(rows, { counter = Counter({ [70] = 1 }) })
	eq(hero.recipeID, 1); eq(#hero.short, 0)
	local none, why = ns.HeroCards.BestCraft({})
	eq(none, nil); eq(why, "no recipes yet")
	none, why = ns.HeroCards.BestCraft({ { status = "trainable", profit = 5 } })
	eq(none, nil); eq(why, "no known recipe")
	none, why = ns.HeroCards.BestCraft({ { status = "known" } })
	eq(none, nil); eq(why, "no known recipe has a price yet")
end)

it("best craft: the chance comes from Leveling.Chance, formula marked as an estimate", function()
	local ns = Load()
	ns.Thresholds = { [6702] = { 95, 125 } }
	local rows = { { recipeID = 6702, name = "Belt", status = "known", profit = 1, difficulty = 1, reagents = {} } }
	local hero = ns.HeroCards.BestCraft(rows, { skill = 110, counter = Counter({}) })
	eq(hero.chanceKind, "formula"); eq(hero.chanceEstimate, true); eq(hero.chance, (125 - 110) / (125 - 95))
	hero = ns.HeroCards.BestCraft(rows, { skill = 90, counter = Counter({}) })
	eq(hero.chanceKind, "orange"); eq(hero.chance, 1); eq(hero.chanceEstimate, false)
end)

it("best skill-up: first by per skill-up, earners first, rows without the figure last", function()
	local ns = Load()
	local rows = {
		{ recipeID = 1, name = "Cheap", perPoint = 50, chance = 0.5, chanceInfo = { kind = "recipe" }, cost = 25, saleValue = 0, net = 25, craftsPerPoint = 2 },
		{ recipeID = 2, name = "Earner", perPoint = -30, chance = 0.4, chanceInfo = { kind = "formula" }, cost = 10, saleValue = 22, net = -12, craftsPerPoint = 2.5 },
		{ recipeID = 3, name = "Unpriced", chance = 1, chanceInfo = { kind = "orange" } },
	}
	local hero = ns.HeroCards.BestSkillUp(rows)
	eq(hero.recipeID, 2); eq(hero.perPoint, -30); eq(hero.earns, true); eq(hero.chanceEstimate, true); eq(hero.chance, 0.4)
	eq(rows[1].recipeID, 1, "the caller's list keeps its order")
	local none, why = ns.HeroCards.BestSkillUp({ rows[3] })
	eq(none, nil); eq(why, "no recipe has a price and a chance yet")
	none, why = ns.HeroCards.BestSkillUp({})
	eq(none, nil); eq(why, "no recipe at your skill gives skill-ups")
end)

it("best to learn: learnable now, fewest crafts to pay off, ties to the higher profit, unknown cost never guessed", function()
	local ns = Load()
	local rows = {
		{ recipeID = 1, name = "A", status = "trainable", required = 50, learnCost = 1000, profit = 100, breakEven = 10, learnSource = "trainer" },
		{ recipeID = 2, name = "B", status = "trainable", required = 60, learnCost = 500, profit = 200, breakEven = 3 },
		{ recipeID = 3, name = "C", status = "vendor", required = 60, learnCost = 900, profit = 300, breakEven = 3, whereText = "Vendor: Invented Vendor" },
		{ recipeID = 4, name = "D", status = "trainable", required = 400, tooLow = true, learnCost = 1, profit = 9999, breakEven = 1 },
		{ recipeID = 5, name = "E", status = "known", profit = 9999 },
		{ recipeID = 6, name = "F", status = "unlearned", learnCost = 1, profit = 9999, breakEven = 1 }, -- requirement unknown
		{ recipeID = 7, name = "G", status = "trainable", required = 10, profit = 9999 }, -- cost unknown
	}
	local hero = ns.HeroCards.BestToLearn(rows)
	eq(hero.recipeID, 3); eq(hero.breakEven, 3); eq(hero.whereText, "Vendor: Invented Vendor")
	eq(hero.candidates, 4); eq(hero.unknownCost, 1)
	local none, why = ns.HeroCards.BestToLearn({ rows[7] })
	eq(none, nil); eq(why, "no learn cost known yet")
	none, why = ns.HeroCards.BestToLearn({ rows[5] })
	eq(none, nil); eq(why, "no recipe to learn at your skill")
	none, why = ns.HeroCards.BestToLearn({ { status = "trainable", required = 1, learnCost = 5, profit = -3 } })
	eq(none, nil); eq(why, "no learnable recipe makes a profit")
end)

it("bag value: sums the best value into AH / vendor / junk, leaves kept out, counts what has no value", function()
	local ns = Load()
	local rows = {
		{ best = "auction", bestValue = 6000 },
		{ best = "vendor", bestValue = 1500 },
		{ best = "vendor", bestValue = 500 },
		{ best = "junk", bestValue = 500 },
		{ kept = true },
		{ best = nil, bestValue = nil },
		{ best = "auction", bestValue = nil },
	}
	local v = ns.HeroCards.BagValue(rows)
	eq(v.total, 8500); eq(v.parts.auction, 6000); eq(v.parts.vendor, 2000); eq(v.parts.junk, 500); eq(v.parts.disenchant, 0)
	eq(v.items.vendor, 2); eq(v.uncounted, 2); eq(v.kept, 1)
	eq(v.shares.auction, 6000 / 8500)
	local none, why = ns.HeroCards.BagValue({})
	eq(none, nil); eq(why, "nothing in your bags")
	none, why = ns.HeroCards.BagValue({ { kept = true } })
	eq(why, "everything in your bags is kept")
	none, why = ns.HeroCards.BagValue({ { best = nil } })
	eq(why, "no item in your bags has a known value")
end)

it("auction totals: from a summary, with what was not counted", function()
	local ns = Load()
	local summary = { active = { {}, {}, {}, {} }, sold = { {}, {} }, returning = { { q = 3 }, { q = 1 } },
		expectedTotal = 1900, expectedMissing = 1, listedTotal = 7000, listedCounted = 2, listedNoBuyout = 1,
		listedUnpriced = 1, listedUnknownCut = 0, listedNote = "5% cut (confirmed)", ownedListAt = 123 }
	local t = ns.HeroCards.AuctionTotals(summary)
	eq(t.onItsWay.copper, 1900); eq(t.onItsWay.count, 2); eq(t.onItsWay.notCounted, 1)
	eq(t.ifAllSell.copper, 7000); eq(t.ifAllSell.count, 4); eq(t.ifAllSell.notCounted, 2); eq(t.ifAllSell.noBuyout, 1)
	eq(t.ifAllSell.note, "5% cut (confirmed)")
	eq(t.returning.count, 2); eq(t.returning.units, 4); eq(t.ownedListAt, 123)
	-- nothing counted: nil, never 0
	summary.expectedMissing, summary.listedCounted = 2, 0
	t = ns.HeroCards.AuctionTotals(summary)
	eq(t.onItsWay.copper, nil); eq(t.ifAllSell.copper, nil)
	local none, why = ns.HeroCards.AuctionTotals({ active = {}, sold = {}, returning = {} })
	eq(none, nil); eq(why, "no auction listed, sold or returning")
end)

it("auction totals: reads the tracker's own summary", function()
	local ns, stub = Load()
	stub.names.player = "Veli"
	stub.surnames.player = "Tanner"
	local none, why = ns.HeroCards.AuctionTotals()
	-- no listings recorded yet
	eq(none, nil); assert(why, "a reason")
	local list = ns.Auctions.List()
	assert(list, "tracker has a list for the character")
	list[#list + 1] = { i = 1, q = 2, unit = 100, st = "active", h = "PvP|H" }
	list[#list + 1] = { i = 1, q = 1, st = "active", h = "PvP|H" } -- no buyout
	list[#list + 1] = { i = 1, q = 5, st = "expired", h = "PvP|H" }
	local t = ns.HeroCards.AuctionTotals()
	eq(t.ifAllSell.count, 2); eq(t.ifAllSell.noBuyout, 1); eq(t.returning.units, 5)
	eq(t.ifAllSell.copper, 190, "200 less the 5% cut")
end)
