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

-- #65: skill and max skill of every profession from the client's profession list, no window needed.
-- clientProfs = list in GetProfessions order (prof1, prof2, archaeology, fishing, cooking, first aid):
-- { [slot] = { name, icon, skill, max, line } }.
local function ClientProfessions(clientProfs)
	GetProfessions = function()
		local out = {}
		for slot = 1, 6 do out[slot] = clientProfs[slot] and slot or nil end
		return out[1], out[2], out[3], out[4], out[5], out[6]
	end
	GetProfessionInfo = function(index)
		local p = clientProfs[index]
		if p then return p.name, p.icon, p.skill, p.max, 0, 0, p.line end
	end
end

local function cooking(stub)
	stub.profession = { id = 185, name = "Cooking", skill = 150, max = 150, recipes = {
		[2538] = { info = { name = "Charred Wolf Meat", learned = true }, schematic = stub.Schematic({ { 2672, 1 } }, 2679) },
		[2541] = { info = { name = "Coyote Steak", learned = false }, schematic = stub.Schematic({ { 2673, 1 } }, 2684) },
	} }
end

it("refreshes skill and max skill of every profession without a window, Fishing included (#65)", function()
	local ns, stub = LoadAddon()
	cooking(stub)
	stub.Fire("TRADE_SKILL_SHOW") -- the Cooking window was opened once, at 150/150
	stub.profession = nil -- window closed
	local client = {
		[4] = { name = "Fishing", icon = 136245, skill = 149, max = 150, line = 356 },
		[5] = { name = "Cooking", icon = 133971, skill = 150, max = 150, line = 185 },
	}
	ClientProfessions(client)
	local notified = 0
	ns.Listen("PROFESSIONS_CHANGED", function() notified = notified + 1 end)
	stub.Fire("PLAYER_LOGIN")
	local profs = ns.charDB.professions
	eq(profs[356].name, "Fishing"); eq(profs[356].skill, 149); eq(profs[356].maxSkill, 150)
	eq(profs[356].icon, 136245); eq(next(profs[356].recipes), nil, "no recipes for Fishing")
	eq(notified, 1)
	local cookingRecipes = profs[185].recipes
	-- Expert learned at the trainer (no window opened) and a fish caught: the client's list changes.
	client[4].skill, client[4].max, client[5].max = 150, 225, 225
	stub.Fire("SKILL_LINES_CHANGED")
	eq(profs[185].maxSkill, 225, "Cooking cap"); eq(profs[185].skill, 150)
	eq(profs[356].maxSkill, 225, "Fishing cap"); eq(profs[356].skill, 150, "Fishing skill")
	eq(notified, 2)
	-- recipe cache untouched
	assert(profs[185].recipes == cookingRecipes, "same recipe table")
	eq(profs[185].recipes[2538].learned, true); eq(profs[185].recipes[2541].learned, false)
	eq(profs[185].recipes[2538].reagents[1].itemID, 2672)
	-- nothing new: no notification, no UI refresh
	stub.Fire("SKILL_LINES_CHANGED")
	eq(notified, 2)
	local n = 0
	for _ in pairs(profs) do n = n + 1 end
	eq(n, 2, "one entry per profession")
end)

it("tabs show the refreshed cap; Fishing gets no tab; Learn uses the new skill (#65)", function()
	local ns, stub = LoadAddon()
	cooking(stub)
	stub.Fire("TRADE_SKILL_SHOW")
	stub.profession = nil
	local client = {
		[4] = { name = "Fishing", icon = 136245, skill = 149, max = 150, line = 356 },
		[5] = { name = "Cooking", icon = 133971, skill = 150, max = 150, line = 185 },
	}
	ClientProfessions(client)
	stub.Fire("PLAYER_LOGIN")
	ns.ToggleProfitFrame()
	local function TabLabels()
		local out = {}
		for _, f in ipairs(stub.frames) do
			if f.label and f.icon and f.shown ~= false and f.label.text then out[#out + 1] = f.label.text end
		end
		return out
	end
	local labels = TabLabels()
	eq(#labels, 1, "one tab: Cooking")
	assert(labels[1]:find("Cooking", 1, true) and labels[1]:find("150/150", 1, true), labels[1])
	client[5].max, client[5].skill = 225, 160
	stub.Fire("SKILL_LINES_CHANGED") -- window open: refreshed without reopening anything
	labels = TabLabels()
	eq(#labels, 1)
	assert(labels[1]:find("160/225", 1, true), labels[1])
	eq(ns.charDB.professions[185].skill, 160) -- RecipeStatus/Learn read prof.skill
end)

it("ignores secret values and entries without a skill line (#65)", function()
	local ns, stub = LoadAddon()
	ClientProfessions({ [1] = { name = "Mining", icon = 1, skill = 30, max = 75, line = 186 },
		[2] = { name = "Herbalism", icon = 2, skill = 10, max = 75 } })
	issecretvalue = function(v) return v == 30 end
	stub.Fire("PLAYER_LOGIN")
	eq(next(ns.charDB.professions), nil, "nothing stored")
	issecretvalue = nil
	stub.Fire("SKILL_LINES_CHANGED")
	eq(ns.charDB.professions[186].skill, 30)
	eq(ns.charDB.professions[186].name, "Mining")
end)

it("a window opened after the refresh takes over its entry instead of listing it twice (#65)", function()
	local ns, stub = LoadAddon()
	ns.ProfessionSkillLines = { Cooking = 185 }
	ClientProfessions({ [5] = { name = "Cooking", icon = 133971, skill = 150, max = 225, line = 185 } })
	stub.Fire("PLAYER_LOGIN")
	eq(ns.charDB.professions[185].maxSkill, 225)
	-- the window reports another profession ID for the same skill line
	cooking(stub)
	stub.profession.id, stub.profession.max = 2548, 225
	stub.Fire("TRADE_SKILL_SHOW")
	eq(ns.charDB.professions[185], nil, "refresh-only entry taken over")
	local prof = ns.charDB.professions[2548]
	eq(prof.name, "Cooking"); eq(prof.icon, 133971); eq(prof.recipes[2538].learned, true)
	stub.Fire("SKILL_LINES_CHANGED") -- refresh now finds the scanned entry
	eq(ns.charDB.professions[185], nil)
	eq(ns.charDB.professions[2548].maxSkill, 225)
end)

-- #78: the client can report skill line 0 with an empty name (Veli's CraftWiseCharDB, scanned
-- 2026-11-02): the "? 0/0" tab. Dropped at login, never created.
it("login clean-up drops skill line 0 and empty-name entries (#78)", function()
	local ns, stub = LoadAddon()
	leatherworking(stub)
	stub.Fire("TRADE_SKILL_SHOW")
	local profs = ns.charDB.professions
	profs[0] = { name = "", skill = 0, maxSkill = 0, scannedAt = 1793577600, recipes = {} }
	profs[777] = { name = "", recipes = { [1] = { learned = true } } }
	ns.Notify("DB_READY")
	eq(profs[0], nil, "line 0"); eq(profs[777], nil, "empty name")
	eq(profs[165].name, "Leatherworking", "real professions stay")
	ns.ToggleProfitFrame()
	local ids = ns.PF.ProfessionIDs()
	eq(#ids, 1); eq(ids[1], 165)
	local snap = ns.Snapshot.Build()
	for _, p in ipairs(snap.professions or {}) do
		assert(p.line ~= 0 and p.name ~= "", "no line-0 profession in the snapshot")
	end
end)

it("never creates a skill line 0 or empty-name entry (#78)", function()
	local ns, stub = LoadAddon()
	ClientProfessions({
		[1] = { name = "", icon = 0, skill = 0, max = 0, line = 0 },
		[4] = { name = "Fishing", icon = 136245, skill = 10, max = 75, line = 356 },
	})
	stub.Fire("PLAYER_LOGIN")
	local profs = ns.charDB.professions
	eq(profs[0], nil); eq(profs[356].name, "Fishing")
	local base = C_TradeSkillUI.GetBaseProfessionInfo
	C_TradeSkillUI.GetBaseProfessionInfo = function() return { professionID = 0, professionName = "", skillLevel = 0, maxSkillLevel = 0 } end
	eq(ns.ScanProfession(), nil, "window reporting line 0 is not scanned")
	C_TradeSkillUI.GetBaseProfessionInfo = function() return { professionID = 165, professionName = "" } end
	eq(ns.ScanProfession(), nil, "nor one without a name")
	C_TradeSkillUI.GetBaseProfessionInfo = base
	eq(profs[0], nil); eq(profs[165], nil)
end)
