-- Integration with the bundled Data/*.lua (real files).
local function lw(stub, recipes)
	stub.profession = { id = 165, name = "Leatherworking", skill = 60, max = 75, recipes = recipes }
	stub.Fire("TRADE_SKILL_SHOW")
end

it("bundled data loads and has the expected tables", function()
	local ns = LoadAddon({ data = true })
	assert(ns.RecipeData[2149], "RecipeData")
	assert(ns.VendorPrices and ns.ItemSellPrices and ns.RecipeNames)
	eq(ns.RecipeSources, nil); eq(ns.TrainerFees, nil) -- unverified data removed (#11)
	-- Thresholds: only yellow and grey, client DB2 (#15)
	eq(#ns.Thresholds[2149], 2); eq(ns.Thresholds[2149][1], 40); eq(ns.Thresholds[2149][2], 70)
	eq(ns.ProfessionSkillLines["Leatherworking"], 165)
end)

it("required skills hold only real client values, not the placeholder 1 (#23)", function()
	local ns = LoadAddon({ data = true })
	eq(ns.RequiredSkills[2665], 75) -- Coarse Sharpening Stone
	eq(ns.RequiredSkills[2149], nil) -- Handstitched Leather Boots: placeholder in the client
	for recipeID, skill in pairs(ns.RequiredSkills) do
		assert(skill > 1, "placeholder for " .. recipeID)
		assert(ns.Thresholds[recipeID], "no thresholds for " .. recipeID)
	end
end)

it("source data holds only the client's skill and recipe item, per known recipe (#11)", function()
	local ns = LoadAddon({ data = true })
	local count = 0
	for recipeID, source in pairs(ns.SourceData) do
		count = count + 1
		eq(type(recipeID), "number")
		assert(ns.RecipeData[recipeID], "no RecipeData for " .. recipeID)
		eq(type(source.skill), "number", "skill of " .. recipeID)
		eq(type(source.item), "number", "item of " .. recipeID)
		assert(source.skill > 1, "placeholder or missing skill for " .. recipeID)
		assert(source.item > 0, "no recipe item for " .. recipeID)
		for field in pairs(source) do
			assert(field == "skill" or field == "item", "unverified field " .. field .. " for " .. recipeID)
		end
	end
	assert(count > 1000, "expected over a thousand item-taught recipes, got " .. count)
	-- Checked against ItemSparse in 1.60.1.70790
	eq(ns.SourceData[2158].skill, 65); eq(ns.SourceData[2158].item, 2406) -- Fine Leather Boots <- Pattern: Fine Leather Boots
	eq(ns.SourceData[2333].skill, 140); eq(ns.SourceData[2333].item, 3396) -- Elixir of Lesser Agility <- Recipe: Elixir of Lesser Agility
	eq(ns.SourceData[2149], nil) -- Handstitched Leather Boots: a trainer recipe, no item teaches it
end)

it("recipes the game retired stay out of the bundled data (#23)", function()
	local ns = LoadAddon({ data = true })
	eq(ns.RecipeData[1226206], nil) -- Tinkerbox
	eq(ns.Thresholds[1226206], nil)
end)

it("vendor reagent priced from bundled list without visiting a merchant", function()
	local ns = LoadAddon({ data = true })
	eq(ns.GetVendorBuyPrice(2320), 10) -- Coarse Thread
	ns.db.vendor[2320] = 8 -- seen at a merchant wins
	eq(ns.GetVendorBuyPrice(2320), 8)
end)

it("vendor sell price falls back to bundled ItemSellPrices", function()
	local ns = LoadAddon({ data = true })
	local id = next(ns.ItemSellPrices)
	eq(ns.GetVendorSellPrice(id), ns.ItemSellPrices[id])
end)

it("unlearned rows include bundled recipes the client never listed", function()
	local ns, stub = LoadAddon({ data = true })
	lw(stub, { [2149] = { info = { name = "Handstitched Leather Boots", learned = true }, schematic = stub.Schematic({ { 2318, 2 } }, 2302) } })
	local known = ns.BuildRows(165, false)
	eq(#known, 1)
	local all = ns.BuildRows(165, true)
	assert(#all > 100, "expected many leatherworking recipes, got " .. #all)
	local seen = {}
	for _, r in ipairs(all) do
		assert(not seen[r.recipeID], "duplicate row " .. r.recipeID)
		seen[r.recipeID] = true
		assert(r.name, "row without name")
	end
end)

it("cached recipe without schematic gets bundled reagents", function()
	local ns, stub = LoadAddon({ data = true })
	lw(stub, { [2149] = { info = { name = "Handstitched Leather Boots", learned = false }, schematic = nil } })
	local rows = ns.BuildRows(165, true)
	local boots
	for _, r in ipairs(rows) do if r.recipeID == 2149 then boots = r end end
	eq(#boots.reagents, #ns.RecipeData[2149].reagents)
	-- the cache itself is untouched
	eq(ns.charDB.professions[165].recipes[2149].reagents, nil)
end)

