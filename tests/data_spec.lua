-- Integration with the bundled Data/*.lua (real files).
local function lw(stub, recipes)
	stub.profession = { id = 165, name = "Leatherworking", skill = 60, max = 75, recipes = recipes }
	stub.Fire("TRADE_SKILL_SHOW")
end

it("bundled data loads and has the expected tables", function()
	local ns = LoadAddon({ data = true })
	assert(ns.RecipeData[2149], "RecipeData")
	assert(ns.RecipeSources and ns.TrainerFees and ns.VendorPrices and ns.ItemSellPrices and ns.RecipeNames)
	eq(ns.ProfessionSkillLines["Leatherworking"], 165)
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

it("trainer fee and required skill come from bundled data before visiting a trainer", function()
	local ns, stub = LoadAddon({ data = true })
	lw(stub, { [2149] = { info = { name = "Handstitched Leather Boots", learned = true }, schematic = stub.Schematic({ { 2318, 2 } }, 2302) } })
	local prof = ns.charDB.professions[165]
	local s, req, tooLow = ns.RecipeStatus(prof, 2159, { learned = false })
	eq(s, "trainable"); eq(req, ns.TrainerFees[2159][2]); eq(tooLow, req > 60)
	eq((ns.LearnCost(2159)), ns.TrainerFees[2159][1])
end)

it("recipe items: vendor price as learn cost, AH price when not sold by vendors", function()
	local ns, stub = LoadAddon({ data = true, auctionator = true })
	local s = ns.RecipeSources[2542]
	eq(ns.RecipeStatus({ skill = 300 }, 2542, { learned = false }), "vendor")
	local cost, src = ns.LearnCost(2542)
	eq(cost, s.price); eq(src, "vendor")
	local drop = ns.RecipeSources[2158]
	stub.ah[drop.item] = 12345
	cost, src = ns.LearnCost(2158)
	eq(cost, 12345); eq(src, "auction")
	eq(ns.RecipeStatus({ skill = 300 }, 2158, { learned = false }), "drop")
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

it("vendors: own faction and neutral first, other faction after, ownOnly drops them", function()
	local ns = LoadAddon({ data = true })
	-- find a vendor recipe with vendors of both factions
	local pick
	for id, s in pairs(ns.RecipeSources) do
		if s.vendors then
			local a, h = false, false
			for _, npc in ipairs(s.vendors) do
				local info = ns.SourceNPCs[npc]
				if info and info[2] == "A" then a = true end
				if info and info[2] == "H" then h = true end
			end
			if a and h then pick = id break end
		end
	end
	assert(pick, "no mixed-faction vendor recipe in data")
	UnitFactionGroup = function() return "Horde" end
	local all = ns.RecipeVendors(pick)
	local sawOther = false
	for _, v in ipairs(all) do
		if v.own then assert(not sawOther, "own vendor after other faction") else sawOther = true; eq(v.faction, "Alliance") end
	end
	assert(sawOther)
	for _, v in ipairs(ns.RecipeVendors(pick, true)) do assert(v.own) end
	UnitFactionGroup = function() return "Alliance" end
	for _, v in ipairs(ns.RecipeVendors(pick, true)) do assert(v.faction ~= "Horde") end
end)

it("other-faction-only vendor recipes are flagged and hidden by the filter", function()
	local ns, stub = LoadAddon({ data = true })
	UnitFactionGroup = function() return "Horde" end
	local pick
	for id, s in pairs(ns.RecipeSources) do
		if s.vendors and ns.RecipeData[id] and ns.RecipeData[id].skillLine == 165 and not ns.TrainerFees[id] then
			local allA = true
			for _, npc in ipairs(s.vendors) do
				local info = ns.SourceNPCs[npc]
				if not info or info[2] ~= "A" then allA = false end
			end
			if allA then pick = id break end
		end
	end
	assert(pick, "no alliance-only leatherworking vendor recipe")
	stub.profession = { id = 165, name = "Leatherworking", skill = 1, max = 75, recipes = {
		[2149] = { info = { name = "Boots", learned = true }, schematic = stub.Schematic({ { 2318, 2 } }, 2302) } } }
	stub.Fire("TRADE_SKILL_SHOW")
	local function find(rows)
		for _, r in ipairs(rows) do if r.recipeID == pick then return r end end
	end
	local r = find(ns.BuildRows(165, true, false))
	eq(r.otherFactionOnly, true); eq(r.vendorFaction, "Alliance")
	eq(find(ns.BuildRows(165, true, true)), nil)
end)

it("skill-up colour: client colour for learned, requirement + thresholds for unlearned", function()
	local ns = LoadAddon({ data = true })
	ns.Thresholds[9000001] = { 50, 70, 80, 90 } -- real orange
	ns.Thresholds[9000002] = { 1, 310, 320, 330 } -- DB2 placeholder orange
	eq(ns.SkillUpColor(9000001, { learned = true, difficulty = 1 }, 60), "yellow")
	eq(ns.SkillUpColor(9000001, { learned = false }, 49), "red")
	eq(ns.SkillUpColor(9000001, { learned = false }, 69), "orange")
	eq(ns.SkillUpColor(9000001, { learned = false }, 79), "yellow")
	eq(ns.SkillUpColor(9000001, { learned = false }, 89), "green")
	eq(ns.SkillUpColor(9000001, { learned = false }, 90), "grey")
	eq(ns.SkillUpColor(9000002, { learned = false }, 97), "red")
	local req, est = ns.RequiredSkill(9000002)
	eq(req, 300); eq(est, true)
	req, est = ns.RequiredSkill(9000001)
	eq(req, 50); eq(est, false)
	eq(ns.SkillUpColor(99999999, { learned = false }, 50), nil)
end)

it("unlearned recipes with an estimated requirement above the skill are flagged tooLow", function()
	local ns = LoadAddon({ data = true })
	ns.Thresholds[9000002] = { 1, 310, 320, 330 }
	local s, req, tooLow, est = ns.RecipeStatus({ skill = 97 }, 9000002, { learned = false })
	eq(s, "unlearned"); eq(req, 300); eq(tooLow, true); eq(est, true)
end)
