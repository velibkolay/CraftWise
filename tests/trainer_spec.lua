local Make = dofile("tests/make_helpers.lua")
local function setup()
	local ns, stub = LoadAddon()
	stub.profession = { id = 165, name = "Leatherworking", skill = 100, max = 150, recipes = {
		[3760] = { info = { name = "Hillman's Cloak", learned = false }, schematic = stub.Schematic({ { 2319, 5 } }, 3719) },
		[3761] = { info = { name = "Fine Leather Tunic", learned = false }, schematic = stub.Schematic({ { 2318, 6 } }, 3761) },
	} }
	stub.Fire("TRADE_SKILL_SHOW")
	return ns, stub
end

it("maps services to recipes by tooltip id, then by name", function()
	local ns, stub = setup()
	stub.trainer = {
		{ name = "Hillman's Cloak", kind = "available", fee = 450, required = 90, tooltipID = 3760 },
		{ name = "Fine Leather Tunic", kind = "unavailable", fee = 900, required = 120 },
		{ name = "Unknown Thing", kind = "available", fee = 1, required = 1 },
		{ name = "Header", kind = "header" },
	}
	stub.Fire("TRAINER_SHOW")
	eq(ns.db.trainer[3760].fee, 450); eq(ns.db.trainer[3760].required, 90)
	eq(ns.db.trainer[3761].fee, 900)
	local n = 0
	for _ in pairs(ns.db.trainer) do n = n + 1 end
	eq(n, 2)
end)

it("ignores tooltip ids that are not cached recipes and falls back to name", function()
	local ns, stub = setup()
	stub.trainer = { { name = "Hillman's Cloak", kind = "available", fee = 450, required = 90, tooltipID = 99999 } }
	stub.Fire("TRAINER_SHOW")
	eq(ns.db.trainer[3760].fee, 450); eq(ns.db.trainer[99999], nil)
end)

it("records every service even when the trainer filter hides some, then restores the filter", function()
	local ns, stub = setup()
	stub.trainer = {
		{ name = "Hillman's Cloak", kind = "used", fee = 450, required = 90, tooltipID = 3760 },
		{ name = "Fine Leather Tunic", kind = "unavailable", fee = 900, required = 120, tooltipID = 3761 },
	}
	stub.trainerFilter = { available = 1, unavailable = 0, used = 0 } -- default-like: nothing visible
	stub.Fire("TRAINER_SHOW")
	eq(ns.db.trainer[3760].fee, 450); eq(ns.db.trainer[3761].fee, 900)
	eq(stub.trainerFilter.unavailable, 0); eq(stub.trainerFilter.used, 0); eq(stub.trainerFilter.available, 1)
end)

-- #83: recipes the bundled data lacks are built from what the trainer shows. Item IDs are the
-- Mender's Leather Belt ones from the issue; reagent IDs are stub data.
local BELT_SPELL, BELT, HIDE, THREAD = 1255075, 252459, 4234, 2321

local function trainerWithBelt()
	local ns, stub = setup()
	ns.RecipeData = {} -- the bundled export (build 1.60.1.70790) has no entry for the belt
	stub.schematics[BELT_SPELL] = stub.Schematic({ { HIDE, 6 }, { THREAD, 2 } }, BELT)
	stub.trainer = {
		{ name = "Mender's Leather Belt", kind = "unavailable", fee = 1800, required = 150, tooltipID = BELT_SPELL, icon = 132500 },
		{ name = "Hillman's Cloak", kind = "available", fee = 450, required = 90, tooltipID = 3760 },
	}
	stub.Fire("TRAINER_SHOW")
	return ns, stub
end

local function plain(s)
	return (tostring(s):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

it("records output, reagents, fee, skill and time of a recipe the bundled data lacks", function()
	local ns = trainerWithBelt()
	local rec = ns.db.trainer[BELT_SPELL]
	assert(rec, "belt recorded")
	eq(rec.fee, 1800); eq(rec.required, 150); eq(rec.skill, "Leatherworking"); eq(rec.line, 165)
	eq(rec.name, "Mender's Leather Belt"); eq(rec.icon, 132500)
	eq(rec.output.itemID, BELT); eq(rec.output.quantity, 1)
	eq(#rec.reagents, 2); eq(rec.reagents[1].itemID, HIDE); eq(rec.reagents[1].quantity, 6)
	eq(rec.reagents[2].itemID, THREAD); eq(rec.reagents[2].quantity, 2)
	eq(type(rec.at), "number"); eq(rec.recipeAt, rec.at)
	-- A cached recipe also gets its recipe from the trainer visit.
	eq(ns.db.trainer[3760].output.itemID, 3719)
	eq(ns.db.debug.trainer.withRecipe, 2)
end)

it("a recorded recipe shows in the Learn rows, marked recorded in game, thresholds unknown", function()
	local ns = trainerWithBelt()
	local row
	for _, r in ipairs(ns.BuildRows(165, true, "learn")) do
		if r.recipeID == BELT_SPELL then row = r end
	end
	assert(row, "belt row")
	eq(row.recordedInGame, true); eq(row.bundledOnly, nil)
	eq(row.name, "Mender's Leather Belt"); eq(row.outputItemID, BELT)
	eq(row.status, "trainable"); eq(row.required, 150); eq(row.tooLow, true)
	eq(row.learnCost, 1800); eq(row.learnSource, "trainer")
	eq(row.thresholdsUnknown, true)
	eq(#row.reagents, 2)
	-- Not learned: not in the learned-only rows.
	for _, r in ipairs(ns.BuildRows(165, false, "profit")) do
		assert(r.recipeID ~= BELT_SPELL, "unlearned recipe in learned-only rows")
	end
end)

it("the recipe tooltip says recorded at a trainer and thresholds unknown", function()
	local ns, stub = trainerWithBelt()
	local lines = {}
	GameTooltip.AddLine = function(_, t) lines[#lines + 1] = plain(t) end
	GameTooltip.AddDoubleLine = function(_, l, r) lines[#lines + 1] = plain(l) .. " | " .. plain(r) end
	Make.Open(ns, "learn", 165) -- Make › Learn (#154)
	local shown = Make.Hover(ns, "learn", BELT_SPELL) and table.concat(lines, "\n")
	assert(shown, "belt row shown")
	assert(shown:find("Skill-ups | thresholds unknown", 1, true), shown)
	assert(shown:find("Recorded in game at a trainer", 1, true), shown)
	assert(not shown:find("yellow %d"), "no guessed thresholds")
end)

it("output and reagents of trainer-recorded recipes enter the market scope", function()
	local ns = trainerWithBelt()
	eq(ns.Market.InScope(BELT), true); eq(ns.Market.InScope(HIDE), true); eq(ns.Market.InScope(THREAD), true)
end)

it("a learned recipe the window gave no reagents for uses the trainer record", function()
	local ns = trainerWithBelt()
	ns.charDB.professions[165].recipes[BELT_SPELL] = { name = "Mender's Leather Belt", learned = true }
	ns.Notify("RECIPES_CHANGED")
	local makers = ns.KnownRecipesFor(BELT)
	eq(#makers, 1); eq(makers[1].recipeID, BELT_SPELL); eq(makers[1].reagents[1].itemID, HIDE)
	local reagents, output, _, origin = ns.RecipeFallback(BELT_SPELL)
	eq(origin, "recorded"); eq(output.itemID, BELT); eq(#reagents, 2)
	eq(ns.RecipeLine(BELT_SPELL), 165)
	local row
	for _, r in ipairs(ns.BuildRows(165, false, "profit")) do
		if r.recipeID == BELT_SPELL then row = r end
	end
	eq(row.recordedInGame, true); eq(row.outputItemID, BELT)
end)

it("services without a profession skill (class trainer) are not recorded from their spell", function()
	local ns, stub = setup()
	ns.RecipeData = {}
	stub.schematics[5555] = stub.Schematic({ { HIDE, 1 } }, BELT)
	stub.trainer = { { name = "Arcane Shot", kind = "available", fee = 100, required = 0, tooltipID = 5555, skill = false } }
	stub.Fire("TRAINER_SHOW")
	eq(ns.db.trainer[5555], nil)
end)

it("a spell with no readable reagents is not taken for a recipe", function()
	local ns, stub = setup()
	ns.RecipeData = {}
	stub.schematics[5556] = stub.Schematic({}, nil)
	stub.trainer = { { name = "Something", kind = "available", fee = 100, required = 1, tooltipID = 5556 } }
	stub.Fire("TRAINER_SHOW")
	eq(ns.db.trainer[5556], nil)
end)

it("a later visit whose schematic doesn't read keeps the recorded recipe", function()
	local ns, stub = trainerWithBelt()
	stub.schematics[BELT_SPELL] = nil
	stub.trainer[1].fee = 2000
	stub.Fire("TRAINER_SHOW")
	local rec = ns.db.trainer[BELT_SPELL]
	eq(rec.fee, 2000) -- matched through the earlier record
	eq(rec.output.itemID, BELT); eq(#rec.reagents, 2)
end)

it("a recipe in the bundled data but not in the cache is recorded by its tooltip spell", function()
	local ns, stub = setup()
	ns.RecipeData = { [7777] = { skillLine = 165, reagents = { { itemID = HIDE, quantity = 3 } }, output = { itemID = 7778, quantity = 1 } } }
	stub.trainer = { { name = "Bundled Thing", kind = "unavailable", fee = 600, required = 125, tooltipID = 7777 } }
	stub.Fire("TRAINER_SHOW")
	local rec = ns.db.trainer[7777]
	eq(rec.fee, 600); eq(rec.required, 125); eq(rec.line, 165)
	eq(rec.reagents, nil) -- the client returned no schematic: nothing invented
	local reagents, _, _, origin = ns.RecipeFallback(7777)
	eq(origin, "bundled"); eq(reagents[1].quantity, 3)
end)
