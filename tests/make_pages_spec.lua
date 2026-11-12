-- Make › Craft, Learn, Level up (#154; spec in #150 "Make", boards "Window layout", "Make › Learn",
-- "Make › Level up", "States"): rows from the existing models, hero cards, chips, the profession dropdown
-- and filter box, opened rows, tooltips and the six states. Invented data only.
local Make = dofile("tests/make_helpers.lua")
local NOW = 1794000000
local DAY = 86400
local HORDE = "PvP|H"
local PROF = 165 -- a profession id the addon knows as a skill line; its name and recipes are invented
local HIDE, THREAD = 990001, 990002 -- reagents
local BELT, GLOVES, BRACERS, CLOAK, CAP, HAT = 990101, 990102, 990103, 990104, 990105, 990106 -- outputs
local R_BELT, R_GLOVES, R_BRACERS, R_CLOAK, R_CAP, R_HAT = 990201, 990202, 990203, 990204, 990205, 990206

local Schematic -- stub.Schematic of the loaded addon

-- typs: typical per day (today first); tiers = { price, qty, ... } of the latest look.
local function Seed(itemID, typ, at)
	local db = CraftWiseMarketDB
	local today = math.floor((at or NOW) / DAY)
	db.items[itemID] = db.items[itemID] or {}
	db.items[itemID][HORDE] = { raw = { { t = at or NOW, total = 50, tiers = { typ, 50 } } },
		days = { [today] = { lo = typ, typ = typ, hi = typ, n = 1 }, [today - 1] = { lo = typ, typ = typ, hi = typ, n = 1 },
			[today - 2] = { lo = typ, typ = typ, hi = typ, n = 1 } },
		last = { t = at or NOW, min = typ, qty = 50 } }
	db.houses[HORDE] = db.houses[HORDE] or { realm = "PvP", kind = "faction", faction = "Horde", label = "Horde AH", cut = { samples = 0 } }
	db.scans[HORDE] = { { t = at or NOW, kind = "search", items = 1, source = "ui" } }
end

local function Recipe(name, learned, difficulty, reagents, out)
	return { info = { name = name, learned = learned, relativeDifficulty = difficulty }, schematic = (function()
		local list = {}
		for _, r in ipairs(reagents) do list[#list + 1] = { r[1], r[2] } end
		return Schematic(list, out)
	end)() }
end

-- Testworking at skill 100:
--   Test Belt     2 Testhide + 1 Testthread -> belt (AH 200, net 190)       cost 40, profit +150, yellow
--   Test Gloves   4 Testhide -> gloves (AH 20 net 19 < vendor 25)          cost 40, profit -15, green
--   Test Bracers  1 Testthread -> bracers (no AH, vendors don't buy it)    cost 20, no profit, orange
--   Test Cloak    3 Testhide (unlearned, trainer 500 at 90)                cost 30, sale 95, profit +65, pays off in 8
--   Test Cap      1 Testhide (unlearned, trainer 300 at 140: above 100)    cost 10, sale 47.5
--   Test Hat      1 Testthread (unlearned, no source known; no sale price)
local function Load(opts)
	opts = opts or {}
	local ns, stub = LoadAddon()
	stub.clock = NOW
	time = function() return stub.clock end
	stub.names.player = "Testperson"
	Schematic = stub.Schematic
	stub.items[HIDE] = { name = "Testhide" }
	stub.items[THREAD] = { name = "Testthread" }
	stub.items[BELT] = { name = "Test Belt", sellPrice = 30 }
	stub.items[GLOVES] = { name = "Test Gloves", sellPrice = 25 }
	stub.items[BRACERS] = { name = "Test Bracers", sellPrice = 0 }
	stub.items[CLOAK] = { name = "Test Cloak", sellPrice = 5 }
	stub.items[CAP] = { name = "Test Cap", sellPrice = 1 }
	stub.items[HAT] = { name = "Test Hat", sellPrice = 0 }
	stub.profession = { id = PROF, name = "Testworking", skill = 100, max = 150, recipes = {
		[R_BELT] = Recipe("Test Belt", true, 1, { { HIDE, 2 }, { THREAD, 1 } }, BELT),
		[R_GLOVES] = Recipe("Test Gloves", true, 2, { { HIDE, 4 } }, GLOVES),
		[R_BRACERS] = Recipe("Test Bracers", true, 0, { { THREAD, 1 } }, BRACERS),
		[R_CLOAK] = Recipe("Test Cloak", false, nil, { { HIDE, 3 } }, CLOAK),
		[R_CAP] = Recipe("Test Cap", false, nil, { { HIDE, 1 } }, CAP),
		[R_HAT] = Recipe("Test Hat", false, nil, { { THREAD, 1 } }, HAT),
	} }
	stub.Fire("TRADE_SKILL_SHOW")
	ns.Thresholds = { [R_BELT] = { 95, 125 }, [R_GLOVES] = { 85, 115 } }
	ns.db.vendor[THREAD] = 20
	ns.db.trainer[R_CLOAK] = { fee = 500, required = 90 }
	ns.db.trainer[R_CAP] = { fee = 300, required = 140 }
	ns.db.settings.includeUnlearned = opts.unlearned or false
	if opts.prices ~= false then
		local at = opts.scannedAt or NOW
		Seed(HIDE, 10, at); Seed(BELT, 200, at); Seed(GLOVES, 20, at); Seed(CLOAK, 100, at); Seed(CAP, 50, at)
	end
	return ns, stub, ns.Main
end

local function Plain(s)
	s = tostring(s or ""):gsub("|T.-|t", "")
	return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

local function Row(ns, page, recipeID)
	local f = Make.Frame(ns, page, recipeID)
	return f and f.elementData.row, f
end

----------------------------------------------------------------------------------------------------
-- Pages and the old window
----------------------------------------------------------------------------------------------------

it("Make: Craft, Learn and Level up are real pages in Make (one file each, in the TOC after the shell)", function()
	local _, _, M = Load()
	local keys = {}
	for _, p in ipairs(M.SectionPages("make")) do
		keys[#keys + 1] = p.key
		eq(p.bridge, nil, p.key); eq(p.profession, true, p.key); eq(p.prices, true, p.key)
	end
	eq(table.concat(keys, ","), "craft,learn,level")
	eq(M.Page("level").label, "Level up")
	local toc = io.open("CraftWise/CraftWise.toc"):read("*a")
	local last = 0
	for _, file in ipairs({ "Frame", "Pages\\Make", "Pages\\MakeTooltips", "Pages\\Craft", "Pages\\Learn", "Pages\\LevelUp" }) do
		local at = toc:find("UI\\Main\\" .. file .. ".lua", 1, true)
		assert(at and at > last, file .. " in the TOC, in order")
		last = at
	end
end)

----------------------------------------------------------------------------------------------------
-- Craft
----------------------------------------------------------------------------------------------------

it("Craft rows: icon, name in its skill colour, rail of profit (zero at 18 %), cost → sells with the tag, ± profit", function()
	local ns, _, M = Load()
	local list = Make.Open(ns, "craft", PROF, false)
	eq(M.shown.state, "list")
	eq(Make.Names(ns, "craft"), "Test Belt,Test Gloves,Test Bracers", "profit, highest first; no price last")
	local belt, beltFrame = Row(ns, "craft", R_BELT)
	local v = belt.view
	eq(v.name, "Test Belt"); eq(v.nameColor, "skill.yellow"); eq(belt.itemID, BELT, "the output item")
	eq(Plain(v.cells.cost), "40c  1s 90c AH", "cost → sells (the arrow is a texture)")
	eq(Plain(v.sellsText), "1s 90c AH")
	eq(v.cells.profit, "+" .. ns.FormatCoins(150)); eq(v.colors.profit, "text")
	eq(v.rail.value, 150); eq(v.rail.zeroAt, 0.18)
	eq(beltFrame.extent, 38, "Craft rows are 38 tall")
	local rail = beltFrame.rails[3]
	eq(rail.value, 150); eq(rail.maxAbs, 150, "one shared scale: the largest |profit|")
	eq(rail.zeroAt, 0.18)
	local railPos = M.ColumnLayout(M.CraftPage.COLUMNS, 880, 22)[3]
	eq(rail.points[1][4], railPos.x); eq(rail.width, railPos.width)
	local gloves, glovesFrame = Row(ns, "craft", R_GLOVES)
	eq(gloves.view.nameColor, "skill.green")
	eq(gloves.view.cells.profit, "−15c"); eq(gloves.view.colors.profit, "danger", "loss in red")
	eq(Plain(gloves.view.sellsText), "25c vendor")
	eq(glovesFrame.rails[3].value, -15, "loss: left of the zero line")
	local bracers = Row(ns, "craft", R_BRACERS)
	eq(bracers.view.nameColor, "skill.orange")
	eq(bracers.view.cells.profit, "—"); eq(bracers.view.colors.profit, "text3")
	eq(Plain(bracers.view.sellsText), "no price")
	eq(bracers.view.rail, nil)
	eq(bracers.view.tips.profit[1], "No sale price")
	-- the cell's own tip on hover
	local _, bf = Row(ns, "craft", R_BRACERS)
	local hit = bf.hits[5]
	hit.scripts.OnEnter(hit)
	eq(CraftWiseInverseTip.title.text, "No sale price")
	hit.scripts.OnLeave(hit)
	eq(list.headers[2].label.text, "Recipe"); eq(list.headers[5].col.key, "profit")
	-- the row data keeps what the docked layout needs: name over rail, result right, sub-figure under it
	for _, r in ipairs(Make.Rows(ns, "craft")) do
		assert(r.view.name and r.view.result and r.view.sub and r.view.nameColor and r.view.resultColor, r.name)
	end
end)

it("Craft hero: best profit among known priced recipes, colour word, skill-up chance, what is short; rail cost then profit", function()
	local ns, stub, M = Load()
	stub.bags[0] = { { itemID = HIDE, stackCount = 1, quality = 1 } }
	Make.Open(ns, "craft", PROF)
	local f = M.Frame()
	eq(f.hero.shown, true)
	eq(f.hero.label.text, "Best craft right now"); eq(f.hero.name.text, "Test Belt")
	eq(Plain(f.hero.sub.text), "Yellow · skill-up ~83% · short 1 Testhide +1 more")
	eq(f.hero.figure.text, "+" .. ns.FormatCoins(150))
	local slot = M.SlotsOf("craft").hero
	local width = 880 - 44 - 32 - 240 - 170 - 48
	eq(slot.barWidth, width)
	assert(math.abs(slot.cost.width - 40 / 190 * width) < 1e-6, "cost along the sale")
	assert(math.abs(slot.gain.width - 150 / 190 * width) < 1e-6, "then the profit")
	eq(slot.gain.points[1][4], slot.cost.width, "profit starts where the cost ends")
	eq(slot.gain.vertexColor[1], ns.Style.C.text[1], "profit in white")
	eq(Plain(slot.left.text), "cost 40c"); eq(Plain(slot.right.text), "sells 1s 90c · AH")
	-- another page's hero drawings stay hidden
	Make.Open(ns, "learn")
	eq(slot.shown, false)
end)

it("Craft hero without an answer: a dash and the reason", function()
	local ns, _, M = Load({ prices = false })
	Make.Open(ns, "craft", PROF)
	local f = M.Frame()
	eq(f.hero.name.text, "—"); eq(f.hero.sub.text, "No known recipe has a price yet.")
	eq(M.SlotsOf("craft").hero.cost.shown, false)
end)

it("Craft chips: Unlearned adds recipes you don't know; Hide unpriced leaves rows out and the footer counts them", function()
	local ns, _, M = Load()
	Make.Open(ns, "craft", PROF)
	local f = M.Frame()
	eq(f.listBar.title.text, "3 recipes"); eq(f.listBar.note.text, "by profit")
	local chips = M.SlotsOf("craft").listTools.chips
	eq(chips[1].label.text, "Unlearned"); eq(chips[2].label.text, "Hide unpriced")
	eq(chips[1].on, false); eq(chips[2].on, false)
	eq(chips[2].points[1][1], "RIGHT"); eq(chips[1].points[1][2], chips[2], "chips from the right, 8 apart")
	chips[1].scripts.OnClick(chips[1])
	eq(ns.db.settings.includeUnlearned, true); eq(chips[1].on, true)
	eq(#Make.Rows(ns, "craft"), 6)
	eq(Row(ns, "craft", R_CLOAK).view.nameColor, "text", "white: not learned yet")
	chips[2].scripts.OnClick(chips[2])
	eq(ns.db.settings.hideUnpriced, true)
	eq(Make.Names(ns, "craft"), "Test Belt,Test Cloak,Test Cap,Test Gloves")
	eq(f.foot.right.text, "2 hidden: no price")
	assert(f.foot.left.text:find("Prices: typical · Horde AH · reagents: AH", 1, true), f.foot.left.text)
	-- sorting by name changes the note
	local list = M.ListOf("craft")
	list.headers[2].scripts.OnClick(list.headers[2])
	eq(f.listBar.note.text, "by name")
end)

it("Craft opened row: each reagent with quantity, total, source and have N; Price history opens Look up › Items", function()
	local ns, stub, M = Load()
	stub.bags[0] = { { itemID = HIDE, stackCount = 6, quality = 1 } }
	local list = Make.Open(ns, "craft", PROF)
	local _, beltFrame = Row(ns, "craft", R_BELT)
	beltFrame.scripts.OnClick(beltFrame, "LeftButton")
	local detail = list.box.frames[2]
	eq(detail.elementData.open, true)
	eq(beltFrame.nokta.shown, true); eq(beltFrame.bg.shown, true)
	eq(list.box.frames[1].rails[3].selected, true, "the opened row's bar in C.text")
	local lines = detail.content.reagentLines
	eq(#lines, 2)
	eq(Plain(lines[1].head), "2 Testhide"); eq(lines[1].total, ns.FormatCoins(20)); eq(lines[1].note, "AH · have 6")
	eq(Plain(lines[2].head), "1 Testthread"); eq(lines[2].note, "vendor")
	local cells = detail.content.reagentCells
	eq(cells[2].x, ns.Main.Make.REAGENT_WIDTH + ns.Main.Make.REAGENT_GAP, "side by side")
	eq(cells[1].hit.cwData.itemID, HIDE, "hover and right-click work on a reagent")
	eq(detail.extent, ns.Main.Make.OpenHeight((Row(ns, "craft", R_BELT))) + 20 + 8)
	local history = detail.content.history
	eq(history.label.text, "Price history"); eq(history.shown, true)
	local looked
	ns.ShowItemLookup = function(id, focus) looked = { id, focus } end -- Look up › Items (#157)
	history.scripts.OnClick(history)
	eq(looked[1], BELT); eq(looked[2], "history")
end)

it("Opened row: Open in profession window under Price history on Craft, Learn and Level up (#157)", function()
	local ns, stub, M = Load()
	local opened = {}
	C_TradeSkillUI.OpenRecipe = function(id) opened[#opened + 1] = id end
	local MK = M.Make
	for _, page in ipairs({ "craft", "learn", "level" }) do
		local recipeID = page == "learn" and R_CLOAK or R_BELT
		local list = Make.Open(ns, page, PROF)
		local row, fr = Row(ns, page, recipeID)
		fr.scripts.OnClick(fr, "LeftButton")
		local content = list.box.frames[2].content
		local b, h = content.openRecipe, content.history
		eq(b.label.text, "Open in profession window", page); eq(b.shown, true, page)
		eq(b.height, MK.BUTTON_HEIGHT)
		local p, hp = b.points[1], h.points[1]
		eq(p[1], "TOPRIGHT"); eq(p[4], 0)
		eq(p[5], hp[5] - MK.BUTTON_HEIGHT - MK.BUTTON_GAP, page .. ": under Price history")
		assert(MK.OpenHeight(row, page == "learn" and math.min(#(row.where or {}), 6) or nil) >= -p[5] + MK.BUTTON_HEIGHT,
			page .. ": the opened part fits both buttons")
		b.scripts.OnClick(b)
		eq(opened[#opened], recipeID, page)
		-- hover: what it does
		b.scripts.OnEnter(b)
		eq(CraftWiseInverseTip.title.text, "Open in profession window")
		b.scripts.OnLeave(b)
	end
	eq(#opened, 3)
	-- a client without the function: no button, and the call says it couldn't
	C_TradeSkillUI.OpenRecipe = nil
	local list = Make.Open(ns, "craft", PROF)
	local _, fr = Row(ns, "craft", R_BELT)
	fr.scripts.OnClick(fr, "LeftButton"); fr.scripts.OnClick(fr, "LeftButton")
	eq(list.box.frames[2].content.openRecipe.shown, false)
	eq(MK.OpenRecipe(R_BELT), false)
	-- an error in the client's call is swallowed
	C_TradeSkillUI.OpenRecipe = function() error("not now") end
	eq(MK.OpenRecipe(R_BELT), false)
end)

it("Craft hover: the crafted item's tooltip with the CraftWise recipe lines, once", function()
	local ns, _, M = Load()
	Make.Open(ns, "craft", PROF)
	local item
	GameTooltip.SetItemByID = function(_, id) item = id end
	local text = Make.CaptureTooltip(function()
		assert(Make.Hover(ns, "craft", R_BELT))
	end)
	eq(item, BELT)
	assert(text:find("Sells for | 1s 90c  AH", 1, true), text)
	assert(text:find("2 × Testhide | 20c  typical · Horde AH", 1, true), text)
	local _, fr = Row(ns, "craft", R_BELT)
	eq(fr.cwOwnTooltip, true)
	eq(ns.InOwnWindow(fr), true, "Tooltip.lua adds no second CraftWise section")
	-- right-click: the item menu for the crafted item
	local menu
	ns.ShowItemMenu = function(id) menu = id end
	eq(M.ListOf("craft"):Click(fr, "RightButton"), "menu"); eq(menu, BELT)
end)

----------------------------------------------------------------------------------------------------
-- Profession dropdown and filter box
----------------------------------------------------------------------------------------------------

it("Profession dropdown: name and current skill; the menu lists crafting professions, the nokta on the current one", function()
	local ns, _, M = Load()
	ns.charDB.professions[171] = { name = "Testbrewing", skill = 40, maxSkill = 75, recipes = {
		[990301] = { name = "Test Brew", learned = true, reagents = { { itemID = HIDE, quantity = 1 } }, output = { itemID = BELT, quantity = 1 } },
	} }
	Make.Open(ns, "craft", PROF)
	local tools = Make.Tools(ns, "craft")
	eq(Plain(tools.profession.label.text), "Testworking 100 ")
	eq(tools.profession.points[1][2], tools.filter, "left of the filter box")
	eq(tools.filter.width, 160); eq(tools.filter.hint.text, "Filter recipes")
	tools.profession.scripts.OnClick(tools.profession)
	local menu = CraftWiseProfessionMenu
	eq(menu.shown, true)
	eq(Plain(menu.buttons[1].label.text), "Testbrewing 40"); eq(Plain(menu.buttons[2].label.text), "Testworking 100")
	eq(menu.nokta.points[1][2], menu.buttons[2], "nokta on the current profession")
	eq(menu.buttons[2].bg.shown, true)
	menu.buttons[1].scripts.OnClick(menu.buttons[1])
	eq(menu.shown, false)
	eq(M.Profession(), 171); eq(M.UI().profession, 171, "remembered")
	eq(Make.Names(ns, "craft"), "Test Brew")
	Make.Open(ns, "level")
	eq(Plain(Make.Tools(ns, "level").profession.label.text), "Testbrewing 40 ", "one choice for the three pages")
end)

it("Filter box: recipe or reagent names, the same query on all three pages", function()
	local ns = Load({ unlearned = true })
	Make.Open(ns, "craft", PROF)
	Make.Filter(ns, "craft", "testthread")
	eq(Make.Names(ns, "craft"), "Test Belt,Test Bracers,Test Hat", "by reagent name; no price last, by name")
	Make.Open(ns, "learn")
	eq(Make.Names(ns, "learn"), "Test Hat")
	Make.Filter(ns, "learn", "cloak")
	eq(Make.Names(ns, "learn"), "Test Cloak")
	Make.Open(ns, "craft")
	eq(Make.Tools(ns, "craft").filter.text, "cloak")
	eq(Make.Tools(ns, "craft").filter.hint.shown, false)
end)

----------------------------------------------------------------------------------------------------
-- Learn
----------------------------------------------------------------------------------------------------

it("Learn rows: white names, skill orange above yours, where to get it, to learn, profit per craft, pays off", function()
	local ns, _, M = Load()
	local list = Make.Open(ns, "learn", PROF)
	local f = M.Frame()
	eq(Make.Names(ns, "learn"), "Test Cloak,Test Cap,Test Hat", "by profit; no price last")
	eq(f.listBar.title.text, "3 recipes you don't know"); eq(f.listBar.note.text, "by profit")
	local labels = {}
	for i = 2, 7 do labels[#labels + 1] = list.headers[i].label.text:gsub(" |T.*$", "") end
	eq(table.concat(labels, ","), "Recipe,Skill,Where to get it,To learn,Profit/craft,Pays off")
	local cloak = Row(ns, "learn", R_CLOAK).view
	eq(cloak.nameColor, "text")
	eq(cloak.cells.required, "90"); eq(cloak.colors.required, "text")
	assert(cloak.cells.where:find("^Trainer"), cloak.cells.where)
	eq(cloak.cells.learnCost, ns.FormatCoins(500))
	eq(cloak.cells.profit, "+" .. ns.FormatCoins(65))
	eq(cloak.cells.breakEven, "8 crafts")
	local cap = Row(ns, "learn", R_CAP).view
	eq(cap.cells.required, "140"); eq(cap.colors.required, "skill.orange", "above your skill")
	local hat = Row(ns, "learn", R_HAT).view
	eq(hat.cells.required, "unknown"); eq(hat.cells.learnCost, "unknown"); eq(hat.colors.learnCost, "text3")
	eq(hat.cells.breakEven, "—"); eq(hat.cells.where, "Not known yet")
	eq(Plain(hat.cells.profit), "no price")
	eq(hat.tips.learnCost[1], "Learn cost unknown")
	assert(f.foot.left.text:find("Sources: bundled data", 1, true))
end)

it("Learn hero: the recipe you can learn now that pays off in the fewest crafts; Fits my skill hides the rest", function()
	local ns, _, M = Load()
	Make.Open(ns, "learn", PROF)
	local f = M.Frame()
	eq(f.hero.label.text, "Best recipe to learn"); eq(f.hero.name.text, "Test Cloak")
	assert(f.hero.sub.text:find("you meet skill 90", 1, true), f.hero.sub.text)
	eq(f.hero.figureLabel.text, "Pays off after"); eq(f.hero.figureLabel.shown, true)
	eq(f.hero.figure.text, "8"); eq(f.hero.figureUnit.text, "crafts")
	eq(M.SlotsOf("learn").hero.value.text, ns.FormatCoins(500))
	eq(M.SlotsOf("learn").hero.label.text, "Learn cost")
	local chips = M.SlotsOf("learn").listTools.chips
	eq(chips[1].label.text, "Fits my skill"); eq(chips[2].label.text, "Hide unpriced")
	chips[1].scripts.OnClick(chips[1])
	eq(ns.db.settings.learnFitsSkill, true)
	eq(Make.Names(ns, "learn"), "Test Cloak")
	assert(f.foot.right.text:find("2 hidden by the chips", 1, true), f.foot.right.text)
	-- Craft's hero has no label over its figure
	Make.Open(ns, "craft")
	eq(f.hero.figureLabel.shown, false); eq(f.hero.figureUnit.shown, false)
end)

it("Learn opened row: where to get it above the reagents", function()
	local ns = Load()
	local list = Make.Open(ns, "learn", PROF)
	local _, fr = Row(ns, "learn", R_CLOAK)
	fr.scripts.OnClick(fr, "LeftButton")
	local content = list.box.frames[2].content
	local where = content.cwPool.kinds.text[1]
	assert(Plain(where.text):find("^Trainer"), where.text)
	eq(Plain(content.reagentLines[1].head), "3 Testhide")
	local text = Make.CaptureTooltip(function() assert(Make.Hover(ns, "learn", R_CLOAK)) end)
	assert(text:find("To learn | 5s (trainer)", 1, true) or text:find("To learn |", 1, true), text)
end)

----------------------------------------------------------------------------------------------------
-- Level up
----------------------------------------------------------------------------------------------------

it("Level up rows: chance bar and percent (~ for the formula), cost, sale, net and per skill-up; best first", function()
	local ns, _, M = Load()
	local list = Make.Open(ns, "level", PROF)
	eq(Make.Names(ns, "level"), "Test Belt,Test Bracers,Test Gloves")
	local labels = {}
	for i = 2, 7 do labels[#labels + 1] = list.headers[i].label.text:gsub(" |T.*$", "") end
	eq(table.concat(labels, ","), "Recipe,Chance,Cost,Sale,Net/craft,Per skill-up")
	local belt, bf = Row(ns, "level", R_BELT)
	eq(belt.view.chanceText, "~83%"); eq(belt.view.chanceColor, "text2")
	eq(bf.cwChance.text.text, "~83%"); eq(bf.cwChance.track.width, 60)
	eq(bf.cwChance.fill.vertexColor[1], ns.Style.C.text3[1], "estimate: grey bar")
	eq(belt.view.cells.netEarn, "+" .. ns.FormatCoins(150))
	assert(belt.view.cells.perSkill:find("^%+"), "earns: +")
	local bracers, brf = Row(ns, "level", R_BRACERS)
	eq(bracers.view.chanceText, "100%"); eq(bracers.view.chanceColor, "text", "orange: measured, white")
	eq(brf.cwChance.fill.vertexColor[1], ns.Style.C.text[1])
	eq(Plain(bracers.view.cells.saleValue), "no price")
	eq(bracers.view.cells.perSkill, "−20c"); eq(bracers.view.colors.perSkill, "danger")
	local gloves = Row(ns, "level", R_GLOVES)
	eq(gloves.view.chanceText, "~50%")
	eq(M.Frame().listBar.note.text, "best value per skill-up first: earning, then cheapest")
	eq(M.SlotsOf("level").listTools.note.text, "Sale: AH after cut when it passes your AH rule, else vendor")
	assert(M.Frame().foot.left.text:find("Grey recipes are left out.", 1, true))
	local text = Make.CaptureTooltip(function() assert(Make.Hover(ns, "level", R_BELT)) end)
	assert(text:find("Estimate: (grey - skill) / (grey - yellow) = (125 - 100) / (125 - 95) = 83%.", 1, true), text)
end)

it("Level up hero: the first row with its chance and per skill-up", function()
	local ns, _, M = Load()
	Make.Open(ns, "level", PROF)
	local f = M.Frame()
	eq(f.hero.label.text, "Best skill-up right now"); eq(f.hero.name.text, "Test Belt")
	assert(Plain(f.hero.sub.text):find("Yellow · earns +1s 50c per craft after selling it", 1, true), f.hero.sub.text)
	eq(f.hero.figureLabel.text, "Per skill-up")
	local slot = M.SlotsOf("level").hero
	eq(slot.pct.text, "~83%"); eq(slot.note.text, "estimate · community formula")
	assert(math.abs(slot.fill.width - slot.barWidth * 25 / 30) < 1e-6)
end)

----------------------------------------------------------------------------------------------------
-- States
----------------------------------------------------------------------------------------------------

it("States: First run on every Make page when the profession has no recipes cached", function()
	local ns, _, M = Load()
	ns.charDB.professions[PROF].recipes = {}
	for _, page in ipairs({ "craft", "learn", "level" }) do
		Make.Open(ns, page, PROF)
		eq(M.shown.state, "firstRun", page)
		eq(M.Frame().panel.title.text, "Open your Testworking window once.")
		eq(M.Frame().panel.icon.shown, true)
		eq(Make.Tools(ns, page).profession:IsShown(), true, "the dropdown stays to pick another profession")
	end
end)

it("States: No prices until an AH is visited; Show vendor-only profits shows vendor prices", function()
	local ns, _, M = Load({ prices = false })
	Make.Open(ns, "craft", PROF, false)
	eq(M.shown.state, "noPrices")
	local f = M.Frame()
	eq(f.panel.title.text, "No auction house visited yet.")
	f.panel.buttons[1].scripts.OnClick(f.panel.buttons[1])
	eq(M.shown.state, "list")
	local gloves = Row(ns, "craft", R_GLOVES)
	eq(Plain(gloves.view.sellsText), "25c vendor")
	eq(gloves.view.cells.profit, "—", "Testhide has no price without the AH")
	eq(gloves.view.tips.profit[1], "A reagent has no price")
end)

it("States: Stale prices: the card, and each AH figure carries its age in red", function()
	local ns, _, M = Load({ scannedAt = NOW - 3 * DAY - 60 })
	Make.Open(ns, "craft", PROF)
	local f = M.Frame()
	eq(M.shown.state, "list")
	eq(f.notice.shown, true); eq(f.notice.title.text, "Prices are 3 days old.")
	local belt = Row(ns, "craft", R_BELT)
	assert(belt.view.sellsText:find(ns.Style.Hex("danger") .. "3 d|r", 1, true), belt.view.sellsText)
	assert(not Row(ns, "craft", R_GLOVES).view.sellsText:find("3 d", 1, true), "vendor figures have no age")
	Make.Open(ns, "level")
	assert(Row(ns, "level", R_BELT).view.cells.saleValue:find("3 d", 1, true))
end)

it("States: Scanning: rows keep their prices, missing figures are skeleton bars", function()
	local ns, _, M = Load()
	ns.Market.ScanProgress = function() return { done = 1240, total = 3800, label = "Horde AH" } end
	Make.Open(ns, "craft", PROF)
	local _, bracers = Row(ns, "craft", R_BRACERS)
	local _, belt = Row(ns, "craft", R_BELT)
	eq(bracers.cwSkeleton.shown, true); eq(bracers.cells[5].text, "")
	eq(belt.cwSkeleton == nil or belt.cwSkeleton.shown == false, true, "a priced row keeps its figure")
	eq(belt.cells[5].text, "+" .. ns.FormatCoins(150))
	ns.Market.ScanProgress = function() return nil end
	M.Refresh()
	_, bracers = Row(ns, "craft", R_BRACERS)
	eq(bracers.cwSkeleton.shown, false); eq(bracers.cells[5].text, "—")
end)

it("States: a Make model that raises shows Error; the other Make pages still work", function()
	local ns, _, M = Load()
	local build = ns.BuildRows
	ns.BuildRows = function(id, unlearned, view)
		if view == "profit" then error("Recipes.lua:1: boom", 0) end
		return build(id, unlearned, view)
	end
	Make.Open(ns, "craft", PROF)
	eq(M.shown.state, "error")
	eq(M.Frame().panel.title.text, "Craft could not be built.")
	Make.Open(ns, "learn")
	eq(M.shown.state, "list")
end)
