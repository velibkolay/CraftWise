-- Issue #259: class trainer spells (recorded first-hand), the planner, Train all and the cross-check
-- against What's Training?. Invented spells and prices only.
local NOW = os.time({ year = 2026, month = 11, day = 15, hour = 12 })

local function Load()
	local ns, stub = LoadAddon()
	stub.clock = NOW
	time = function(t)
		if t then return os.time(t) end
		return stub.clock
	end
	stub.level = 12
	stub.names.npc = "Test Trainer"
	stub.money = 5000
	stub.trainerType = 0
	stub.class = "MAGE"
	stub.trainer = {
		{ name = "Header", kind = "header" },
		{ name = "Spark", kind = "available", fee = 100, level = 1, rank = "Rank 1", tooltipID = 1001, skill = false },
		{ name = "Spark", kind = "available", fee = 600, level = 8, rank = "Rank 2", tooltipID = 1002, skill = false, abilities = { "Spark" } },
		{ name = "Chill", kind = "available", fee = 400, level = 10, tooltipID = 1003, skill = false },
		{ name = "Gust", kind = "unavailable", fee = 900, level = 14, tooltipID = 1004, skill = false },
		{ name = "Blink", kind = "used", fee = 0, level = 4, tooltipID = 1005, skill = false },
	}
	stub.knownSpells = { [1005] = true } -- Blink, which the trainer lists as known
	stub.Fire("PLAYER_LOGIN")
	stub.Fire("PLAYER_ENTERING_WORLD", true, false)
	return ns, stub
end

local function Visit(stub)
	stub.Fire("TRAINER_SHOW")
end

it("records every class trainer service per class: level, rank, cost, spell, abilities, trainer, time", function()
	local ns, stub = Load()
	Visit(stub)
	local data = ns.db.classSpells.MAGE
	assert(data, "recorded under the class")
	eq(data.npc, "Test Trainer"); eq(data.at, NOW); eq(data.visitLevel, 12)
	local spark2 = data.services["Spark|Rank 2"]
	eq(spark2.name, "Spark"); eq(spark2.rank, "Rank 2"); eq(spark2.level, 8); eq(spark2.cost, 600)
	eq(spark2.id, 1002); eq(spark2.kind, "available"); eq(spark2.abilities[1], "Spark"); eq(spark2.npc, "Test Trainer")
	eq(data.services["Chill|"].level, 10, "no rank text: the key ends with the bar")
	eq(data.services["Chill|"].rank, nil)
	eq(data.services["Blink|"].kind, "used")
	local n = 0
	for _ in pairs(data.services) do n = n + 1 end
	eq(n, 5, "the header is not a service")
end)

it("a profession trainer or a pet trainer is not a class trainer: nothing is recorded", function()
	local ns, stub = Load()
	stub.trainerType = 2
	Visit(stub)
	eq(ns.db.classSpells.MAGE, nil)
	stub.trainerType = 3
	stub.Fire("TRAINER_UPDATE")
	eq(ns.db.classSpells.MAGE, nil)
end)

it("a later visit updates what it sees and keeps the rest; a known spell's missing price keeps the old one", function()
	local ns, stub = Load()
	Visit(stub)
	stub.level = 14
	stub.clock = NOW + 3600
	stub.trainer = {
		{ name = "Gust", kind = "available", fee = 850, level = 14, tooltipID = 1004, skill = false },
		{ name = "Spark", kind = "used", fee = 0, level = 8, rank = "Rank 2", tooltipID = 1002, skill = false },
	}
	Visit(stub)
	local data = ns.db.classSpells.MAGE
	eq(data.visitLevel, 14); eq(data.at, NOW + 3600)
	eq(data.services["Gust|"].cost, 850); eq(data.services["Gust|"].kind, "available")
	eq(data.services["Spark|Rank 2"].kind, "used"); eq(data.services["Spark|Rank 2"].cost, 600, "the price seen before stays")
	eq(data.services["Chill|"].cost, 400, "not shown this time: kept")
end)

it("planner: learn now, later and known, priced total, unpriced counted; known by spell id when there is one", function()
	local ns, stub = Load()
	Visit(stub)
	stub.knownSpells[1001] = true -- Spark Rank 1 learned since
	local plan = ns.ClassSpells.Plan(ns.ClassSpells.Data(), 12)
	local function names(list)
		local out = {}
		for _, r in ipairs(list) do out[#out + 1] = r.name .. (r.rank and (" " .. r.rank) or "") end
		return table.concat(out, ",")
	end
	eq(names(plan.learnNow), "Spark Rank 2,Chill")
	eq(names(plan.later), "Gust")
	eq(names(plan.known), "Spark Rank 1,Blink", "by id for Spark, by what the trainer showed for Blink: ordered by level")
	eq(plan.total, 1000); eq(plan.unpriced, 0)
	eq(plan.visitLevel, 12); eq(plan.npc, "Test Trainer")
	-- A level up moves Gust to learn now; a service without a price is counted, not guessed.
	ns.db.classSpells.MAGE.services["Gust|"].cost = nil
	plan = ns.ClassSpells.Plan(ns.ClassSpells.Data(), 14)
	eq(names(plan.learnNow), "Spark Rank 2,Chill,Gust"); eq(plan.total, 1000); eq(plan.unpriced, 1)
	-- No record: empty, no invented list.
	local empty = ns.ClassSpells.Plan(nil, 20)
	eq(empty.empty, true); eq(#empty.learnNow + #empty.later + #empty.known, 0)
end)

it("Train all plan: only what the trainer marks available, in list order, while the money lasts", function()
	local ns, stub = Load()
	Visit(stub)
	stub.money = 800
	local plan = ns.ClassSpells.TrainPlan()
	eq(#plan.lines, 2); eq(plan.lines[1].name, "Spark"); eq(plan.lines[1].rank, "Rank 1"); eq(plan.lines[1].cost, 100)
	eq(plan.lines[2].name, "Spark"); eq(plan.lines[2].rank, "Rank 2")
	eq(plan.total, 700); eq(plan.skipped, 1, "Chill (400) doesn't fit in the 100 left")
	-- The confirmation lists them with the cost.
	local lines = ns.ClassSpells.ConfirmLines(plan)
	eq(#lines, 2); eq(lines[1]:find("Spark Rank 1", 1, true), 1)
	stub.money = 50
	local none, why = ns.ClassSpells.TrainPlan()
	eq(none, nil); eq(why, "You can't afford any of the available spells")
	stub.money = 5000
	stub.trainerType = 2
	none, why = ns.ClassSpells.TrainPlan()
	eq(none, nil); eq(why, "Train all works at class trainers")
	stub.Fire("TRAINER_CLOSED")
	stub.trainerType = 0
	none, why = ns.ClassSpells.TrainPlan()
	eq(why, "Open a class trainer first")
end)

it("Train all: one BuyTrainerService per listed spell, last to first, each re-checked", function()
	local ns, stub = Load()
	Visit(stub)
	local plan = ns.ClassSpells.TrainPlan()
	eq(#plan.lines, 3)
	local bought, spent, why = ns.ClassSpells.TrainAll(plan)
	eq(bought, 3); eq(spent, 1100); eq(why, nil)
	eq(table.concat(stub.buyTrainer, ","), "4,3,2", "indexes 2,3,4 (the header is 1), highest first")
	-- The list changed under the plan: stops before buying the wrong thing.
	stub.buyTrainer = {}
	stub.trainer[3].name = "Other"
	bought, spent, why = ns.ClassSpells.TrainAll(plan)
	eq(bought, 1); eq(why, "The trainer's list changed"); eq(table.concat(stub.buyTrainer, ","), "4")
	-- Money gone before the end.
	stub.buyTrainer = {}
	stub.trainer[3].name = "Spark"
	stub.money = 450
	bought, spent, why = ns.ClassSpells.TrainAll(plan)
	eq(bought, 1); eq(why, "Not enough money"); eq(table.concat(stub.buyTrainer, ","), "4")
end)

it("Train all stops when the trainer closes between purchases", function()
	local ns, stub = Load()
	Visit(stub)
	local plan = ns.ClassSpells.TrainPlan()
	local real = BuyTrainerService
	BuyTrainerService = function(i)
		real(i)
		stub.Fire("TRAINER_CLOSED")
	end
	local bought, _, why = ns.ClassSpells.TrainAll(plan)
	eq(bought, 1); eq(why, "The trainer closed")
end)

it("the button: shown at a class trainer only, opens a confirmation, and only its Train button buys", function()
	ClassTrainerFrame = CreateFrame("Frame", "ClassTrainerFrame", UIParent)
	local ns, stub = Load()
	ClassTrainerFrame = ClassTrainerFrame or CreateFrame("Frame", "ClassTrainerFrame", UIParent)
	Visit(stub)
	local TA = ns.TrainAll
	assert(TA.button, "button on the trainer window")
	eq(TA.button:IsShown(), true)
	eq(#stub.buyTrainer, 0, "opening a trainer buys nothing")
	TA.button.scripts.OnClick(TA.button)
	eq(TA.panel:IsShown(), true); eq(#stub.buyTrainer, 0, "the first click only asks")
	assert(TA.panel.lines:GetText():find("Spark Rank 2", 1, true), TA.panel.lines:GetText())
	assert(TA.panel.total:GetText():find("3 spells", 1, true), TA.panel.total:GetText())
	TA.panel.cancel.scripts.OnClick(TA.panel.cancel)
	eq(TA.panel:IsShown(), false); eq(#stub.buyTrainer, 0)
	TA.button.scripts.OnClick(TA.button)
	TA.panel.go.scripts.OnClick(TA.panel.go)
	eq(table.concat(stub.buyTrainer, ","), "4,3,2"); eq(TA.panel:IsShown(), false)
	-- Not at a profession trainer, and not with the setting off.
	stub.trainerType = 2
	stub.Fire("TRAINER_SHOW")
	eq(TA.button:IsShown(), false)
	stub.trainerType = 0
	ns.db.settings.trainAll = false
	stub.Fire("TRAINER_SHOW")
	eq(TA.button:IsShown(), false)
end)

it("cross-check: costs and levels that differ, spells only one side has; quest spells and higher levels left out", function()
	local ns, stub = Load()
	Visit(stub)
	local data = ns.ClassSpells.Data()
	local spells = {
		{ id = 1001, name = "Spark", subText = "Rank 1", level = 1, cost = 100, baseCost = 100 },
		{ id = 1002, name = "Spark", subText = "Rank 2", level = 8, cost = 700, baseCost = 700 },
		{ id = 1003, name = "Chill", level = 12, cost = 400, baseCost = 450 },
		{ id = 1004, name = "Gust", level = 14, cost = 900, baseCost = 900 },
		{ id = 2001, name = "Frost", level = 6, cost = 300, baseCost = 300 },
		{ id = 2002, name = "Quest Spell", level = 5, cost = 0, quest = true },
		{ id = 2003, name = "High", level = 30, cost = 5000, baseCost = 5000 },
	}
	local r = ns.ClassSpells.CrossCheck(data, spells)
	eq(r.matched, 4)
	eq(#r.differ, 2)
	assert(r.differ[1]:find("Chill: level recorded 10, What's Training? 12", 1, true), r.differ[1])
	assert(r.differ[2]:find("Spark Rank 2: cost recorded", 1, true), r.differ[2])
	eq(#r.onlyWT, 1); assert(r.onlyWT[1]:find("Frost (level 6)", 1, true), r.onlyWT[1])
	eq(#r.onlyOurs, 1); eq(r.onlyOurs[1], "Blink")
	-- A price that matches WT's base price is not a difference (WT's own faction pricing).
	spells[2].cost, spells[2].baseCost = 540, 600
	r = ns.ClassSpells.CrossCheck(data, spells)
	eq(#r.differ, 1)
end)

it("trainercheck: says so without What's Training? and prints the report with it", function()
	local ns, stub = Load()
	local printed = {}
	ns.Print = function(s) printed[#printed + 1] = s end
	eq(ns.ClassSpells.PrintCrossCheck(), nil)
	assert(printed[1]:find("isn't loaded", 1, true), printed[1])
	Visit(stub)
	WT_API = { IsReady = function() return true end, GetSpells = function() return {
		{ id = 1001, name = "Spark", subText = "Rank 1", level = 1, cost = 100, baseCost = 100 } } end }
	printed = {}
	local r = ns.ClassSpells.PrintCrossCheck()
	eq(r.matched, 1)
	assert(printed[1]:find("1 recorded spells matched", 1, true), printed[1])
	WT_API = nil
end)

it("Make > Train: rows learn now, later, known; the hero counts and prices; empty without a visit", function()
	local ns, stub = Load()
	local M = ns.Main
	M.Open("train")
	local model = M.Page("train").Model({})
	eq(#model.rows, 0); eq(model.hero.name, "—")
	Visit(stub)
	model = M.Page("train").Model({})
	eq(#model.rows, 5)
	local got = {}
	for _, r in ipairs(model.rows) do got[#got + 1] = r.state .. ":" .. r.name end
	eq(table.concat(got, ","), "now:Spark Rank 1,now:Spark Rank 2,now:Chill,later:Gust,known:Blink")
	eq(model.hero.name, "3 spells now"); eq(model.hero.figure, ns.FormatCoins(1100))
	eq(model.rows[2].view.cells.needs, "Spark"); eq(model.rows[2].view.cells.cost, ns.FormatCoins(600))
	eq(model.rows[4].view.cells.level, "14"); eq(model.rows[4].view.cells.state, "Later")
	assert(model.footer:find("need a visit", 1, true), model.footer)
	eq(M.Page("train").section, "make")
end)
