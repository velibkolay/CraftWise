local function leatherworking(stub)
	stub.profession = { id = 165, name = "Leatherworking", skill = 100, max = 150, recipes = {
		[2149] = { info = { name = "Handstitched Leather Boots", learned = true, icon = 1, relativeDifficulty = 2 },
			schematic = stub.Schematic({ { 2318, 2 }, { 2320, 1 } }, 2302) },
		[3760] = { info = { name = "Hillman's Cloak", learned = false },
			schematic = stub.Schematic({ { 2319, 5 } }, 3719), source = "Trainer" },
		[7000] = { info = { name = "Some Enchant", learned = true }, schematic = stub.Schematic({ { 1, 1 } }, nil) },
		[7001] = { info = { name = "Unreadable", learned = false }, schematic = nil },
	} }
end

it("caches learned and unlearned recipes with reagents and output", function()
	local ns, stub = LoadAddon()
	leatherworking(stub)
	stub.Fire("TRADE_SKILL_SHOW")
	local prof = ns.charDB.professions[165]
	eq(prof.name, "Leatherworking"); eq(prof.skill, 100)
	eq(prof.recipes[2149].learned, true); eq(#prof.recipes[2149].reagents, 2)
	eq(prof.recipes[2149].output.itemID, 2302)
	eq(prof.recipes[3760].learned, false); eq(prof.recipes[3760].source, "Trainer")
	eq(prof.recipes[7000].output, nil); eq(prof.recipes[7000].noItemOutput, true)
	eq(prof.recipes[7001].reagents, nil)
end)

it("a later scan without schematic keeps cached reagents", function()
	local ns, stub = LoadAddon()
	leatherworking(stub)
	stub.Fire("TRADE_SKILL_SHOW")
	stub.profession.recipes[2149].schematic = nil
	stub.Fire("TRADE_SKILL_LIST_UPDATE")
	eq(#ns.charDB.professions[165].recipes[2149].reagents, 2)
end)

it("a schematic with an unreadable slot is rejected, not under-priced", function()
	local ns, stub = LoadAddon()
	leatherworking(stub)
	local s = stub.Schematic({ { 2318, 2 } }, 2302)
	table.insert(s.reagentSlotSchematics, { reagentType = 1, quantityRequired = 1, reagents = {} })
	stub.profession.recipes[2149].schematic = s
	stub.Fire("TRADE_SKILL_SHOW")
	eq(ns.charDB.professions[165].recipes[2149].reagents, nil)
end)

it("linked professions are not scanned", function()
	local ns, stub = LoadAddon()
	leatherworking(stub)
	C_TradeSkillUI.IsTradeSkillLinked = function() return true end
	stub.Fire("TRADE_SKILL_SHOW")
	eq(ns.charDB.professions[165], nil)
end)

it("builds profit rows, filtering unlearned on request", function()
	local ns, stub = LoadAddon({ auctionator = true })
	leatherworking(stub)
	stub.Fire("TRADE_SKILL_SHOW")
	stub.ah[2318], stub.ah[2320], stub.ah[2302] = 10, 5, 100
	local rows = ns.BuildRows(165, false)
	eq(#rows, 2)
	local all = ns.BuildRows(165, true)
	eq(#all, 4)
	local boots
	for _, r in ipairs(all) do if r.recipeID == 2149 then boots = r end end
	eq(boots.cost, 25); eq(boots.profit, 100 * 0.95 - 25); eq(boots.status, "known")
end)

it("status uses trainer records against current skill", function()
	local ns, stub = LoadAddon()
	leatherworking(stub)
	stub.Fire("TRADE_SKILL_SHOW")
	local prof = ns.charDB.professions[165]
	eq(ns.RecipeStatus(prof, 3760, prof.recipes[3760]), "unlearned")
	ns.db.trainer[3760] = { fee = 500, required = 110 }
	local s, req, tooLow = ns.RecipeStatus(prof, 3760, prof.recipes[3760])
	eq(s, "trainable"); eq(req, 110); eq(tooLow, true)
	ns.db.trainer[3760].required = 90
	s, req, tooLow = ns.RecipeStatus(prof, 3760, prof.recipes[3760])
	eq(s, "trainable"); eq(tooLow, false)
end)

it("skill colour: client colour for learned, red only when a trainer says the skill is too low", function()
	local ns = LoadAddon()
	eq(ns.SkillUpColor({ learned = true, difficulty = 0 }), "orange")
	eq(ns.SkillUpColor({ learned = true, difficulty = 3 }), "grey")
	eq(ns.SkillUpColor({ learned = false }, true), "red")
	eq(ns.SkillUpColor({ learned = false }, false), nil)
	eq(ns.SkillUpColor({ learned = false }), nil)
end)

it("a recipe learned at the trainer leaves the learn list right away", function()
	local ns, stub = LoadAddon()
	stub.profession = { id = 165, name = "Leatherworking", skill = 100, max = 150, recipes = {
		[9145] = { info = { name = "Fletcher's Gloves", learned = false }, schematic = stub.Schematic({ { 2318, 4 } }, 7348) },
		[9146] = { info = { name = "Other", learned = false }, schematic = stub.Schematic({ { 2318, 4 } }, 7349) },
	} }
	stub.Fire("TRADE_SKILL_SHOW")
	local changed = 0
	ns.Listen("RECIPES_CHANGED", function() changed = changed + 1 end)
	stub.Fire("NEW_RECIPE_LEARNED", 9145)
	eq(ns.charDB.professions[165].recipes[9145].learned, true)
	eq(changed, 1)
	-- learned spells reported by the spellbook are picked up on trainer updates too
	IsPlayerSpell = function(id) return id == 9146 end
	stub.Fire("TRAINER_UPDATE")
	eq(ns.charDB.professions[165].recipes[9146].learned, true)
end)
