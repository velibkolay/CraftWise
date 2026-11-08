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
	C_SpellBook = { IsSpellKnown = function(id) return id == 9146 end }
	stub.Fire("TRAINER_UPDATE")
	eq(ns.charDB.professions[165].recipes[9146].learned, true)
end)

it("profession IDs are used as skill lines directly, so non-English clients work", function()
	local ns, stub = LoadAddon()
	stub.profession = { id = 165, name = "Lederverarbeitung", skill = 50, max = 75, recipes = {
		[2149] = { info = { name = "Stiefel", learned = true }, schematic = stub.Schematic({ { 2318, 2 } }, 2302) } } }
	stub.Fire("TRADE_SKILL_SHOW")
	eq(ns.SkillLineOf(165), 165)
	eq(ns.IsGathering(393), true)
	eq(ns.L["Profit"], "Profit") -- untranslated text falls back to English
end)

-- Issue #44: recipes filed under the wrong profession, and the "?" tab.
local function cooking(stub)
	stub.profession = { id = 185, name = "Cooking", skill = 77, max = 150, recipes = {
		[2538] = { info = { name = "Charred Wolf Meat", learned = true, relativeDifficulty = 2 }, schematic = stub.Schematic({ { 2672, 1 } }, 2679) },
		[2540] = { info = { name = "Roasted Kodo Meat", learned = true, relativeDifficulty = 1 }, schematic = stub.Schematic({ { 5469, 1 } }, 5472) },
	} }
end

local function bundled(ns)
	ns.RecipeData = {
		[2149] = { skillLine = 165 }, [3760] = { skillLine = 165 }, [7000] = { skillLine = 165 }, [7001] = { skillLine = 165 },
		[2538] = { skillLine = 185 }, [2540] = { skillLine = 185 },
		[3275] = { skillLine = 129 }, -- First Aid
	}
end

it("a scan whose recipe list belongs to another profession than the open one files nothing", function()
	local ns, stub = LoadAddon()
	bundled(ns)
	leatherworking(stub)
	stub.Fire("TRADE_SKILL_SHOW")
	cooking(stub)
	local base = C_TradeSkillUI.GetBaseProfessionInfo
	-- the window still says Leatherworking while the list is already Cooking's
	C_TradeSkillUI.GetBaseProfessionInfo = function() return { professionID = 165, professionName = "Leatherworking", skillLevel = 77, maxSkillLevel = 150 } end
	local prof, why = ns.ScanProfession()
	eq(prof, nil); eq(why, "mismatch")
	eq(ns.charDB.professions[165].recipes[2538], nil)
	eq(ns.charDB.professions[165].skill, 100) -- skill untouched too
	C_TradeSkillUI.GetBaseProfessionInfo = base
	stub.Fire("TRADE_SKILL_LIST_UPDATE") -- next event: list and base agree again
	eq(ns.charDB.professions[185].recipes[2540].learned, true)
	eq(ns.charDB.professions[165].recipes[2540], nil)
end)

it("a mismatching first scan creates no profession entry (no '?' tab)", function()
	local ns, stub = LoadAddon()
	bundled(ns)
	cooking(stub)
	C_TradeSkillUI.GetBaseProfessionInfo = function() return { professionID = 165, professionName = "Leatherworking" } end
	ns.ScanProfession()
	eq(next(ns.charDB.professions), nil)
end)

it("a mixed list only files the recipes of the open profession", function()
	local ns, stub = LoadAddon()
	bundled(ns)
	leatherworking(stub)
	stub.profession.recipes[2540] = { info = { name = "Roasted Kodo Meat", learned = true }, schematic = stub.Schematic({ { 5469, 1 } }, 5472) }
	stub.Fire("TRADE_SKILL_SHOW")
	eq(ns.charDB.professions[165].recipes[2540], nil)
	eq(ns.charDB.professions[165].recipes[2149].learned, true)
end)

it("recipes the bundled data doesn't know are still filed (nothing is guessed)", function()
	local ns, stub = LoadAddon()
	bundled(ns)
	leatherworking(stub)
	stub.profession.recipes[880001] = { info = { name = "Unknown To Data", learned = true }, schematic = stub.Schematic({ { 1, 1 } }, 2) }
	stub.Fire("TRADE_SKILL_SHOW")
	eq(ns.charDB.professions[165].recipes[880001].learned, true)
end)

it("First Aid under either skill line ID is one profession", function()
	local ns, stub = LoadAddon()
	bundled(ns)
	eq(ns.SkillLineOf(2942), 129); eq(ns.SkillLineOf(129), 129)
	ns.RecipeData[3276] = { skillLine = 2942 }
	eq(ns.RecipeSkillLine(3276), 129)
	for _, id in ipairs({ 129, 2942 }) do
		eq(ns.RecipeBelongs(id, 3275), true); eq(ns.RecipeBelongs(id, 3276), true); eq(ns.RecipeBelongs(id, 2149), false)
	end
	stub.profession = { id = 2942, name = "First Aid", skill = 10, max = 75, recipes = {
		[3275] = { info = { name = "Linen Bandage", learned = true }, schematic = stub.Schematic({ { 2589, 1 } }, 1251) },
	} }
	stub.Fire("TRADE_SKILL_SHOW")
	eq(ns.charDB.professions[2942].recipes[3275].learned, true)
end)

it("BuildRows skips misfiled recipes already in the cache", function()
	local ns, stub = LoadAddon()
	bundled(ns)
	leatherworking(stub)
	stub.Fire("TRADE_SKILL_SHOW")
	ns.charDB.professions[165].recipes[2540] = { name = "Roasted Kodo Meat", learned = true, reagents = { { itemID = 5469, quantity = 1 } } }
	local ids = {}
	for _, r in ipairs(ns.BuildRows(165, true)) do ids[r.recipeID] = true end
	eq(ids[2540], nil); eq(ids[2149], true)
	for _, r in ipairs(ns.LevelingRows(165)) do eq(r.recipeID == 2540, false) end
end)

it("login clean-up moves misfiled recipes to their cached profession, drops the rest, removes '?' entries, keeps crafts", function()
	local ns, stub = LoadAddon()
	bundled(ns)
	ns.charDB.professions = {
		[165] = { name = "Leatherworking", skill = 77, maxSkill = 150, recipes = {
			[2149] = { name = "Boots", learned = true },
			[2538] = { name = "Charred Wolf Meat", learned = true },
			[2540] = { name = "Roasted Kodo Meat", learned = true, difficulty = 1 },
			[3275] = { name = "Linen Bandage", learned = true }, -- First Aid is not cached: dropped
		} },
		[185] = { name = "Cooking", skill = 50, maxSkill = 75, recipes = { [2538] = { name = "Charred Wolf Meat", learned = true, difficulty = 3 } } },
		[999] = { recipes = {} }, -- nameless and empty: the "?" 0/0 tab
		[998] = { name = "Kept Empty", recipes = {} }, -- named: stays
	}
	ns.db.skillups = { [2540] = { [60] = { n = 3, ups = 1, d = 1 } } }
	local notified = 0
	ns.Listen("RECIPES_CHANGED", function() notified = notified + 1 end)
	ns.CleanProfessions()
	local p = ns.charDB.professions
	eq(p[165].recipes[2538], nil); eq(p[165].recipes[2540], nil); eq(p[165].recipes[3275], nil)
	eq(p[165].recipes[2149].learned, true)
	eq(p[185].recipes[2540].difficulty, 1) -- moved
	eq(p[185].recipes[2538].difficulty, 3) -- the cooking cache's own entry wins
	eq(p[999], nil); eq(p[998].name, "Kept Empty")
	eq(ns.db.skillups[2540][60].n, 3) -- recorded crafts survive
	eq(notified, 1)
	eq(ns.CleanProfessions(), 0) -- idempotent
end)

it("clean-up runs once the saved data is loaded", function()
	local ns = LoadAddon()
	ns.charDB.professions[7] = { recipes = {} }
	ns.Notify("DB_READY")
	eq(ns.charDB.professions[7], nil)
end)

it("the profession tab list ignores nameless entries", function()
	local ns, stub = LoadAddon()
	leatherworking(stub)
	stub.Fire("TRADE_SKILL_SHOW")
	ns.charDB.professions[999] = { recipes = { [1] = { learned = true } } }
	ns.db.settings.view = "profit"
	ns.ToggleProfitFrame()
	local ids = ns.PF.ProfessionIDs()
	eq(#ids, 1); eq(ids[1], 165)
end)
