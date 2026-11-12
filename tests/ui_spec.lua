local Make = dofile("tests/make_helpers.lua")
it("Make › Craft builds and renders rows without errors", function()
	local ns, stub = LoadAddon({ auctionator = true })
	stub.profession = { id = 165, name = "Leatherworking", skill = 100, max = 150, recipes = {
		[2149] = { info = { name = "Boots", learned = true }, schematic = stub.Schematic({ { 2318, 2 } }, 2302) },
		[3760] = { info = { name = "Cloak", learned = false }, schematic = stub.Schematic({ { 2319, 5 } }, 3719) },
		[7000] = { info = { name = "Enchant", learned = true }, schematic = stub.Schematic({ { 1, 1 } }, nil) },
	} }
	stub.Fire("TRADE_SKILL_SHOW")
	stub.ah[2318], stub.ah[2302] = 10, 100
	local rows = ns.BuildRows(165, true)
	eq(#rows, 3)
	Make.Open(ns, "craft", 165)
	ns.Main.Toggle() -- hide
	ns.Main.Toggle() -- show again
	ns.Main.Refresh()
	eq(#Make.Rows(ns, "craft"), 3)
end)

it("Make pages: tooltips, sorting and opened rows render for known, trainer, vendor and bundled-only rows", function()
	local ns, stub = LoadAddon({ data = true, auctionator = true })
	stub.profession = { id = 165, name = "Leatherworking", skill = 60, max = 75, recipes = {
		[2149] = { info = { name = "Handstitched Leather Boots", learned = true }, schematic = stub.Schematic({ { 2318, 2 } }, 2302) },
	} }
	stub.Fire("TRADE_SKILL_SHOW")
	UnitFactionGroup = function() return "Horde" end
	for _, page in ipairs({ "craft", "learn", "level" }) do
		local list = Make.Open(ns, page, 165)
		local frames = Make.Frames(ns, page)
		assert(#frames > 0, "rows on " .. page)
		for _, f in ipairs(frames) do
			f.scripts.OnEnter(f)
			f.scripts.OnLeave(f)
		end
		-- sort by every column without errors
		for _, h in ipairs(list.headers) do
			if h.col and h.col.sort then h.scripts.OnClick(h) end
		end
		-- open the first row: reagents and Price history
		local first = Make.Frames(ns, page)[1]
		first.scripts.OnClick(first, "LeftButton")
		assert(list.box.frames[2].elementData.open, "opened in place on " .. page)
		eq(ns.Main.shown.state, "list")
	end
	assert(#Make.Rows(ns, "learn") > 5, "bundled unlearned recipes on Learn")
end)

it("minimap button: click opens the main window, right-click the farm tracker, drag moves it, /craftwise minimap hides it", function()
	local ns, stub = LoadAddon()
	local btn = CraftWiseMinimapButton
	assert(btn, "minimap button not created at login")
	btn.scripts.OnClick(btn, "LeftButton") -- opens the main window (#153)
	assert(CraftWiseMainFrame and CraftWiseMainFrame:IsShown(), "main window open")
	btn.scripts.OnEnter(btn); btn.scripts.OnLeave(btn)
	btn.scripts.OnDragStart(btn)
	btn.scripts.OnUpdate(btn)
	eq(math.floor(ns.db.minimap.angle + 0.5), 0) -- cursor to the right of the minimap centre
	btn.scripts.OnDragStop(btn)
	btn.scripts.OnClick(btn, "RightButton")
	eq(ns.FarmFrame.IsShown(), true, "right-click opens the farm tracker")
	eq(ns.db.minimap.hide, false, "and no longer hides the button")
	SlashCmdList.CRAFTWISE("minimap")
	eq(ns.db.minimap.hide, true); eq(btn:IsShown(), false)
	SlashCmdList.CRAFTWISE("minimap")
	eq(ns.db.minimap.hide, false); eq(btn:IsShown(), true)
	CraftWise_OnAddonCompartmentClick()
end)

it("the slash command is /craftwise, with no /cw alias (#34: /cw hijacks whispers)", function()
	LoadAddon()
	eq(SLASH_CRAFTWISE1, "/craftwise")
	local i = 1
	while _G["SLASH_CRAFTWISE" .. i] do
		assert(_G["SLASH_CRAFTWISE" .. i] ~= "/cw", "SLASH_CRAFTWISE" .. i .. " must not be /cw")
		i = i + 1
	end
end)

it("the filter box filters the Make rows by name, the same query on all three pages", function()
	local ns, stub = LoadAddon({ data = true })
	stub.profession = { id = 165, name = "Leatherworking", skill = 60, max = 75, recipes = {
		[2149] = { info = { name = "Handstitched Leather Boots", learned = true }, schematic = stub.Schematic({ { 2318, 2 } }, 2302) } } }
	stub.Fire("TRADE_SKILL_SHOW")
	Make.Open(ns, "craft", 165)
	local before = #Make.Rows(ns, "craft")
	Make.Filter(ns, "craft", "boots")
	local rows = Make.Rows(ns, "craft")
	assert(#rows > 0 and #rows < before, ("%d of %d"):format(#rows, before))
	for _, r in ipairs(rows) do
		assert(r.name:lower():find("boots"), "unfiltered row " .. r.name)
	end
	Make.Open(ns, "learn")
	eq(Make.Tools(ns, "learn").filter.text, "boots", "one query for the Make pages")
	for _, r in ipairs(Make.Rows(ns, "learn")) do assert(r.name:lower():find("boots"), r.name) end
	Make.Filter(ns, "learn", "")
	eq(ns.Main.Make.state.query, "")
end)

it("gathering professions are not in the profession dropdown; icons come from the client or fallbacks", function()
	local ns, stub = LoadAddon()
	GetProfessions = function() return 1, 2 end
	GetProfessionInfo = function(i) if i == 1 then return "Leatherworking", 136247 end return "Skinning", 134366 end
	stub.profession = { id = 165, name = "Leatherworking", skill = 60, max = 75, recipes = {
		[2149] = { info = { name = "Boots", learned = true }, schematic = stub.Schematic({ { 2318, 2 } }, 2302) } } }
	stub.Fire("TRADE_SKILL_SHOW")
	stub.profession = { id = 393, name = "Skinning", skill = 60, max = 75, recipes = {
		[9999] = { info = { name = "Skin", learned = true }, schematic = stub.Schematic({ { 1, 1 } }, 2) } } }
	stub.Fire("TRADE_SKILL_SHOW")
	eq(ns.charDB.professions[165].icon, 136247)
	eq(ns.IsGathering(393), true); eq(ns.IsGathering(165), false)
	eq(ns.ProfessionIcon(12345), 134400)
	Make.Open(ns, "craft")
	local chip = Make.Tools(ns, "craft").profession
	chip.scripts.OnClick(chip)
	local menu = CraftWiseProfessionMenu
	eq(menu.shown, true)
	local shown = 0
	for _, b in ipairs(menu.buttons) do if b.shown ~= false then shown = shown + 1 end end
	eq(shown, 1)
	assert(menu.buttons[1].label.text:find("Leatherworking", 1, true), menu.buttons[1].label.text)
end)

it("Craft: the Unlearned chip adds unlearned recipes to the list", function()
	local ns, stub = LoadAddon({ savedDB = { settings = { includeUnlearned = false } } })
	stub.profession = { id = 165, name = "Leatherworking", skill = 60, max = 75, recipes = {
		[2149] = { info = { name = "Boots", learned = true }, schematic = stub.Schematic({ { 2318, 2 } }, 2302) },
		[3760] = { info = { name = "Cloak", learned = false }, schematic = stub.Schematic({ { 2319, 5 } }, 3719) } } }
	stub.Fire("TRADE_SKILL_SHOW")
	Make.Open(ns, "craft", 165)
	eq(Make.Names(ns, "craft"), "Boots")
	local chip = ns.Main.SlotsOf("craft").listTools.chips[1]
	eq(chip.label.text, "Unlearned"); eq(chip.on, false)
	chip.scripts.OnClick(chip)
	eq(ns.db.settings.includeUnlearned, true); eq(chip.on, true)
	eq(#Make.Rows(ns, "craft"), 2)
	local cloak = Make.Frame(ns, "craft", 3760).elementData.row
	eq(cloak.view.nameColor, "text", "white: not learned yet")
end)


local function lwWithTrainer()
	local ns, stub = LoadAddon({ auctionator = true })
	stub.profession = { id = 165, name = "Leatherworking", skill = 100, max = 150, recipes = {
		[2149] = { info = { name = "Boots", learned = true }, schematic = stub.Schematic({ { 2318, 2 } }, 2302) },
		[3760] = { info = { name = "Cloak", learned = false }, schematic = stub.Schematic({ { 2319, 5 } }, 3719) },
		[3761] = { info = { name = "Tunic", learned = false }, schematic = stub.Schematic({ { 2319, 5 } }, 3720) },
		[3762] = { info = { name = "Pants", learned = false }, schematic = stub.Schematic({ { 2319, 5 } }, 3721) } } }
	stub.Fire("TRADE_SKILL_SHOW")
	ns.db.trainer[3760] = { fee = 500, required = 90 }
	ns.db.trainer[3761] = { fee = 900, required = 120 }
	return ns, stub
end

it("Hide unpriced on Craft leaves out rows without a profit; the footer counts them", function()
	local ns, stub = lwWithTrainer()
	stub.ah[2318], stub.ah[2302] = 10, 100
	ns.db.settings.hideUnpriced = true
	Make.Open(ns, "craft", 165)
	local rows = Make.Rows(ns, "craft")
	assert(#rows >= 1)
	for _, r in ipairs(rows) do assert(r.profit, "unpriced row shown") end
	assert(ns.Main.Frame().foot.right.text:find("hidden: no price", 1, true), ns.Main.Frame().foot.right.text)
end)

it("Learn lists every unlearned recipe with where-to-get text; sorted by skill, unknown last", function()
	local ns = lwWithTrainer()
	local list = Make.Open(ns, "learn", 165)
	local rows = Make.Rows(ns, "learn")
	eq(#rows, 3)
	for _, r in ipairs(rows) do assert(r.status ~= "known") end
	local skill = list.headers[3]
	eq(skill.col.key, "required")
	skill.scripts.OnClick(skill) -- highest first
	skill.scripts.OnClick(skill) -- again: lowest first
	eq(Make.Names(ns, "learn"), "Cloak,Tunic,Pants")
	rows = Make.Rows(ns, "learn")
	eq(rows[1].whereText, "Trainer"); assert(rows[1].view.cells.where:find("^Trainer"), rows[1].view.cells.where)
	eq(rows[3].whereText, nil); eq(rows[3].view.cells.where, "Not known yet") -- Pants: source not known yet
	eq(rows[3].view.cells.required, "unknown"); eq(rows[3].view.colors.required, "text3")
	eq(rows[2].view.colors.required, "skill.orange", "Tunic needs 120, above 100")
	eq(rows[1].view.cells.learnCost, ns.FormatCoins(500))
	eq(rows[3].view.cells.learnCost, "unknown"); eq(rows[3].view.cells.breakEven, "—")
end)

it("Learn 'Fits my skill' keeps only known requirements at or below the skill", function()
	local ns = lwWithTrainer()
	ns.db.settings.learnFitsSkill = true
	Make.Open(ns, "learn", 165)
	eq(Make.Names(ns, "learn"), "Cloak")
	assert(ns.Main.Frame().foot.right.text:find("2 hidden by the chips", 1, true), ns.Main.Frame().foot.right.text)
end)

it("learn view uses bundled source data when present: vendors own faction first, AH price, required skill", function()
	local ns, stub = lwWithTrainer()
	UnitFactionGroup = function() return "Horde" end
	ns.SourceData = { [3762] = { skill = 95, item = 5555,
		vendors = { { name = "Alliance Guy", zone = "Stormwind", faction = "A", price = 2000 },
			{ name = "Goblin", zone = "Booty Bay", price = 2500 } } } }
	stub.ah[5555] = 1800
	local where = ns.RecipeWhere(3762)
	eq(where[1].text, "Vendor: Goblin (Booty Bay) - " .. ns.FormatMoney(2500))
	eq(where[2].own, false)
	eq(where[3].text, "AH: " .. ns.FormatMoney(1800))
	local s, req, tooLow = ns.RecipeStatus({ skill = 100 }, 3762, { learned = false })
	eq(s, "vendor"); eq(req, 95); eq(tooLow, false)
	local cost, how = ns.LearnCost(3762)
	eq(cost, 2000); eq(how, "vendor")
	Make.Open(ns, "learn", 165)
	for _, f in ipairs(Make.Frames(ns, "learn")) do f.scripts.OnEnter(f) end
end)

it("the profit window is gone (#154): Profit, Learn and Level were its last views", function()
	local ns = lwWithTrainer()
	eq(ns.PF, nil); eq(ns.ToggleProfitFrame, nil); eq(ns.RefreshProfitFrame, nil)
	SlashCmdList.CRAFTWISE("")
	eq(CraftWiseMainFrame:IsShown(), true, "/craftwise opens the main window")
end)
