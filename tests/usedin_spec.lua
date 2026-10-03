local function setup()
	local ns, stub = LoadAddon({ auctionator = true })
	ns.RecipeData = {
		[2149] = { skillLine = 165, reagents = { { itemID = 2318, quantity = 2 } }, output = { itemID = 2302, quantity = 1 } },
		[3763] = { skillLine = 165, reagents = { { itemID = 2318, quantity = 6 } }, output = { itemID = 4246, quantity = 1 } },
		[2387] = { skillLine = 197, reagents = { { itemID = 2318, quantity = 1 } }, output = { itemID = 2569, quantity = 1 } },
		[9999] = { skillLine = 165, reagents = { { itemID = 4234, quantity = 4 } }, output = false },
	}
	ns.ProfessionSkillLines = { Leatherworking = 165, Tailoring = 197 }
	stub.items[2318] = { name = "Light Leather", sellPrice = 15 }
	stub.items[4306] = { name = "Grey Rock", sellPrice = 5 }
	stub.profession = { id = 165, name = "Leatherworking", skill = 60, max = 75, recipes = {
		[2149] = { info = { name = "Handstitched Leather Boots", learned = true }, schematic = stub.Schematic({ { 2318, 2 } }, 2302) },
		[3763] = { info = { name = "Fine Leather Belt", learned = false }, schematic = stub.Schematic({ { 2318, 6 } }, 4246) },
	} }
	stub.Fire("TRADE_SKILL_SHOW")
	stub.bags[0] = { { itemID = 2318, stackCount = 10, quality = 1 }, { itemID = 4306, stackCount = 1, quality = 0 } }
	return ns, stub
end

it("lists recipes using an item: known, then learnable, then other professions", function()
	local ns = setup()
	local used = ns.UsedIn(2318)
	eq(#used, 3)
	eq(used[1].name, "Handstitched Leather Boots"); eq(used[1].state, "known"); eq(used[1].quantity, 2)
	eq(used[2].name, "Fine Leather Belt"); eq(used[2].state, "learnable")
	eq(used[3].profession, "Tailoring"); eq(used[3].state, "other")
	local summary = ns.UsedInSummary(2318)
	eq(summary[1].profession, "Leatherworking"); eq(summary[1].count, 2); eq(summary[1].known, 1)
	eq(summary[2].profession, "Tailoring"); eq(summary[2].mine, false)
	eq(#ns.UsedIn(4306), 0)
end)

it("bags view shows a Used in column, filters to my crafting materials, and jumps to the recipes", function()
	local ns, stub = setup()
	ns.db.settings.view = "bags"
	ns.ToggleProfitFrame()
	local leather
	for _, f in ipairs(stub.frames) do
		if f.data and f.shown ~= false and f.data.itemID == 2318 then leather = f end
	end
	assert(leather.cells.usedCount.text:find("Leatherworking 2"), leather.cells.usedCount.text)
	leather.scripts.OnEnter(leather)
	ns.db.settings.bagsMatsOnly = true
	ns.RefreshProfitFrame()
	for _, f in ipairs(stub.frames) do
		if f.data and f.shown ~= false and f.data.itemID then assert(f.data.itemID ~= 4306, "rock hidden") end
	end
	-- menu: Recipes using this -> Profit view, Leatherworking, search by reagent name
	ns.ShowItemMenu(2318)
	CraftWiseItemMenu.buttons.recipes.scripts.OnClick(CraftWiseItemMenu.buttons.recipes)
	eq(ns.db.settings.view, "profit")
	local names = {}
	for _, f in ipairs(stub.frames) do
		if f.data and f.shown ~= false and f.data.recipeID then names[#names + 1] = f.data.name end
	end
	table.sort(names)
	eq(table.concat(names, ","), "Fine Leather Belt,Handstitched Leather Boots")
	eq(ns.ShowRecipesUsing(4306), false)
end)
