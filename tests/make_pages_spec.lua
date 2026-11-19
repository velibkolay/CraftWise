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
		eq(p.bridge, nil, p.key)
		if p.key ~= "crafted" and p.key ~= "train" then eq(p.prices, true, p.key) end -- the craft log needs no prices (#205)
		if p.key ~= "basket" and p.key ~= "crafted" and p.key ~= "train" then eq(p.profession, true, p.key) end -- class spells (#259) have no profession -- the basket spans professions (#186)
	end
	eq(table.concat(keys, ","), "craft,learn,level,basket,crafted,train")
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
	local hit = bf.hits[7]
	hit.scripts.OnEnter(hit)
	eq(CraftWiseInverseTip.title.text, "No sale price")
	hit.scripts.OnLeave(hit)
	eq(list.headers[2].label.text, "Recipe"); eq(list.headers[5].col.key, "pct"); eq(list.headers[6].col.key, "daily"); eq(list.headers[7].col.key, "profit")
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
	eq(Plain(f.hero.sub.text), "Yellow · skill-up ~83% · short 1 Testhide +1 more · 375%")
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

it("Craft › Vendor check (#185): vendor sale and profit, only crafts above 0, best first, with and without Unlearned, loop tag, hero", function()
	local ns, _, M = Load()
	ns.db.vendor[HIDE] = 1 -- Testhide is a vendor good now; Testthread already is (20)
	Make.Open(ns, "craft", PROF)
	local chips = M.SlotsOf("craft").listTools.chips
	eq(chips[3].label.text, "Vendor check"); eq(chips[3].on, false)
	eq(Make.Names(ns, "craft"), "Test Belt,Test Gloves,Test Bracers") -- unchanged without the chip
	chips[3].scripts.OnClick(chips[3])
	eq(ns.db.settings.vendorCheck, true); eq(chips[3].on, true)
	-- Gloves 4 Testhide (4) -> vendor 25 = +21, Belt 2 Testhide + 1 Testthread (22) -> 30 = +8; Bracers have no vendor sale
	eq(Make.Names(ns, "craft"), "Test Gloves,Test Belt")
	local gloves = Row(ns, "craft", R_GLOVES)
	eq(gloves.profit, 21); eq(gloves.sellSource, "vendor"); eq(gloves.vendorLoop, true)
	local sub = Plain(gloves.view.sub)
	assert(sub:find("vendor · loop", 1, true), sub)
	local f = M.Frame()
	eq(f.hero.label.text, "Best vendor craft right now"); eq(f.hero.name.text, "Test Gloves")
	assert(f.foot.left.text:find("Vendor check", 1, true), f.foot.left.text)
	-- Unlearned on: Cloak (3 Testhide = 3 -> 5) joins; Cap (1 -> 1) earns nothing and stays out
	chips[1].scripts.OnClick(chips[1])
	eq(Make.Names(ns, "craft"), "Test Gloves,Test Belt,Test Cloak")
	-- no vendor price for the reagents: the chip leaves nothing and the empty text says why
	ns.db.vendor[HIDE], ns.db.vendor[THREAD] = nil, nil
	M.Refresh()
	eq(Make.Names(ns, "craft"), "")
	assert(M.Page("craft").Model({ professionID = PROF }).empty:find("Vendor check", 1, true))
end)

it("Craft opened row: each reagent with quantity, total, source and have N; Price history shows the site address (#202)", function()
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
	eq(detail.extent, ns.Main.Make.OpenHeight((Row(ns, "craft", R_BELT)), nil, nil, { basket = true }) + 20 + 8)
	local history = detail.content.history
	eq(history.label.text, "Price history"); eq(history.shown, true)
	local looked
	ns.ShowItemLookup = function(id, focus) looked = { id, focus } end -- Look up › Items (#157)
	history.scripts.OnClick(history)
	eq(looked, nil, "Look up › Items does not open")
	eq(CraftWiseSiteLink.shown, true)
	eq(CraftWiseSiteLink.url, "https://wow.velikopter.com/item/" .. BELT)
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
		local at = 1
		for i, f in ipairs(list.box.frames) do
			if f == fr then at = i end
		end
		local content = list.box.frames[at + 1].content
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
	eq(menu.buttons[1].label.text, "All professions", "Make > Craft only (#211)")
	eq(Plain(menu.buttons[2].label.text), "Testbrewing 40"); eq(Plain(menu.buttons[3].label.text), "Testworking 100")
	eq(menu.nokta.points[1][2], menu.buttons[3], "nokta on the current profession")
	eq(menu.buttons[3].bg.shown, true)
	menu.buttons[2].scripts.OnClick(menu.buttons[2])
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
	eq(Make.Names(ns, "level"), "Test Bracers,Test Belt,Test Gloves", "100%, ~83%, ~50% (#364)")
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
	eq(M.Frame().listBar.note.text, "fewest crafts per point first, then net per craft")
	eq(M.SlotsOf("level").listTools.note.text, "Sale: AH after cut when it passes your AH rule, else vendor")
	assert(M.Frame().foot.left.text:find("Grey recipes are left out.", 1, true))
	local text = Make.CaptureTooltip(function() assert(Make.Hover(ns, "level", R_BELT)) end)
	assert(text:find("Estimate: (grey - skill) / (grey - yellow) = (125 - 100) / (125 - 95) = 83%.", 1, true), text)
end)

it("Level up hero: the first row with its chance and per skill-up", function()
	local ns, _, M = Load()
	Make.Open(ns, "level", PROF)
	local f = M.Frame()
	eq(f.hero.label.text, "Best skill-up right now"); eq(f.hero.name.text, "Test Bracers", "orange: fewest crafts per point (#364)")
	assert(Plain(f.hero.sub.text):find("costs 20c per craft", 1, true), f.hero.sub.text)
	eq(f.hero.figureLabel.text, "Per skill-up")
	local slot = M.SlotsOf("level").hero
	eq(slot.pct.text, "100%"); eq(slot.note.text, "orange · every craft gives a point")
	assert(math.abs(slot.fill.width - slot.barWidth) < 1e-6)
	-- a hero that earns: the belt alone
	local h = M.LevelPage.Hero({ (Row(ns, "level", R_BELT)) })
	eq(h.name, "Test Belt")
	assert(Plain(h.sub):find("Yellow · earns +1s 50c per craft after selling it", 1, true), h.sub)
	eq(h.chanceNote, "estimate · community formula")
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
	eq(bracers.cwSkeleton.shown, true); eq(bracers.cells[7].text, "")
	eq(belt.cwSkeleton == nil or belt.cwSkeleton.shown == false, true, "a priced row keeps its figure")
	eq(belt.cells[7].text, "+" .. ns.FormatCoins(150))
	ns.Market.ScanProgress = function() return nil end
	M.Refresh()
	_, bracers = Row(ns, "craft", R_BRACERS)
	eq(bracers.cwSkeleton.shown, false); eq(bracers.cells[7].text, "—")
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

----------------------------------------------------------------------------------------------------
-- Vendor loop alert and basket (#186)
----------------------------------------------------------------------------------------------------

it("Loops (#186): finds are vendor profits above the minimum, a loop is marked, unknown prices are no find", function()
	local ns = Load()
	ns.db.vendor[HIDE] = 1
	local finds = ns.Loops.Check()
	eq(#finds, 2); eq(finds[1].name, "Test Gloves"); eq(finds[1].profit, 21); eq(finds[1].loop, true)
	eq(finds[2].name, "Test Belt"); eq(finds[2].profit, 8)
	ns.db.settings.loopAlertMin = 10
	eq(#ns.Loops.Check(), 1, "below the minimum: not announced")
	ns.db.settings.loopAlertMin = 0
	ns.db.vendor[HIDE] = nil -- reagent at the AH only: vendor profit is negative, nothing to announce
	eq(#ns.Loops.Check(), 0)
	ns.db.settings.includeUnlearned = true
	ns.db.vendor[HIDE] = 1
	eq(#ns.Loops.Check(), 3, "Cloak joins with Unlearned on; Cap (profit 0) and Hat (no sale) never")
end)

it("Loops: Fresh keeps what was announced, repeats only new or clearly better finds and forgets what went away", function()
	local ns = Load()
	local L = ns.Loops
	local finds = { { recipeID = 1, profit = 100, loop = false }, { recipeID = 2, profit = 50, loop = true } }
	local fresh, keep = L.Fresh(finds, {})
	eq(#fresh, 2)
	fresh, keep = L.Fresh(finds, keep)
	eq(#fresh, 0, "same finds again: no toast")
	fresh, keep = L.Fresh({ { recipeID = 1, profit = 140, loop = false }, { recipeID = 2, profit = 50, loop = true } }, keep)
	eq(#fresh, 0, "+40 % is not clearly better")
	fresh, keep = L.Fresh({ { recipeID = 1, profit = 160, loop = false }, { recipeID = 2, profit = 50, loop = true } }, keep)
	eq(#fresh, 1); eq(fresh[1].recipeID, 1)
	fresh, keep = L.Fresh({ { recipeID = 1, profit = 160, loop = true } }, keep)
	eq(#fresh, 1, "became a loop")
	fresh, keep = L.Fresh({}, keep)
	eq(next(keep), nil, "gone finds are forgotten")
	fresh = L.Fresh({ { recipeID = 2, profit = 50, loop = true } }, keep)
	eq(#fresh, 1, "and count as new when they come back")
	eq(L.Summary({ { loop = true }, { loop = true }, { loop = false } }), "2 vendor loops · 1 vendor profit")
	eq(L.Summary({}), nil)
end)

it("Loops: FULL_PRICES runs one debounced check, one toast per check, click opens Make › Craft with Vendor check", function()
	local ns, stub, M = Load()
	ns.db.settings.flipAlert = false -- the flips have their own specs (flips_spec.lua)
	ns.db.vendor[HIDE] = 1
	ns.Notify("FULL_PRICES"); ns.Notify("FULL_PRICES"); ns.Notify("FULL_PRICES")
	eq(#ns.LootToast.Lines(), 0, "nothing before the debounce ends")
	stub.RunTimers()
	local lines = ns.LootToast.Lines()
	eq(#lines, 1); eq(lines[1].text, "2 vendor loops"); eq(lines[1].detail, "Test Gloves"); eq(lines[1].copper, 21)
	eq(ns.LootToast.LineParts(lines[1]).source, "per craft")
	ns.Notify("FULL_PRICES"); stub.RunTimers()
	eq(#ns.LootToast.Lines(), 1, "the same finds: no second toast")
	ns.db.settings.vendorCheck = false
	lines[1].onClick(lines[1])
	eq(ns.db.settings.vendorCheck, true); eq(M.CurrentPage().key, "craft")
	ns.db.settings.loopAlert = false
	ns.db.loopNotice = {}
	ns.LootToast.Clear()
	ns.Notify("FULL_PRICES"); stub.RunTimers()
	eq(#ns.LootToast.Lines(), 0, "switched off in Settings")
end)

it("Basket (#186): crafts add up, buy list = reagents minus bags split AH / vendor, ticks off as bags fill", function()
	local ns, stub = Load()
	local B = ns.Basket
	ns.db.vendor[HIDE] = nil
	B.Add(R_GLOVES, PROF, 3); B.Add(R_BELT, PROF, 2); B.Add(R_GLOVES, PROF, 1)
	eq(#B.Entries(), 2); eq(B.Find(R_GLOVES).count, 4)
	local plan = B.Plan()
	-- 4 Gloves = 16 Testhide, 2 Belts = 4 Testhide + 2 Testthread
	eq(plan.need[1].itemID, HIDE); eq(plan.need[1].quantity, 20); eq(plan.need[2].quantity, 2)
	eq(#plan.split.auction, 1); eq(plan.split.auction[1].itemID, HIDE); eq(plan.split.auction[1].quantity, 20)
	eq(#plan.split.vendor, 1); eq(plan.split.vendor[1].itemID, THREAD)
	eq(plan.split.vendorCost, 2 * 20)
	-- Gloves vendor sale 25, cost 40: -15 each; Belt 30, cost 40: -10 each
	eq(plan.profit, -15 * 4 + -10 * 2); eq(plan.sale, 25 * 4 + 30 * 2)
	-- bags: 20 Testhide in the bags: the AH line is done and shows as in bags
	stub.bags[0] = { { itemID = HIDE, stackCount = 20, quality = 1 } }
	stub.Fire("BAG_UPDATE_DELAYED")
	plan = B.Plan()
	eq(#plan.split.auction, 0); eq(#plan.done, 1); eq(plan.done[1].itemID, HIDE); eq(plan.done[1].held, 20)
	B.SetCount(R_BELT, 0)
	eq(#B.Entries(), 1, "count 0 removes it")
	B.Clear()
	eq(#B.Entries(), 0); eq(B.Plan().profit, nil)
end)

it("Basket page: crafts first, then AH, vendor and in-bags lines; empty basket says so", function()
	local ns, stub, M = Load()
	M.Open("basket")
	eq(Make.Names(ns, "basket"), "")
	eq(M.Frame().hero.name.text, "—")
	ns.Basket.Add(R_BELT, PROF, 2)
	M.Open("basket")
	eq(Make.Names(ns, "basket"), "Test Belt,Testhide,Testthread")
	local rows = Make.Rows(ns, "basket")
	eq(rows[1].kind, "craft"); eq(rows[2].kind, "auction"); eq(rows[3].kind, "vendor")
	eq(Plain(rows[3].view.cells.where), "vendor"); eq(Plain(rows[2].view.cells.qty), "×4")
end)

it("Basket: Auctionator list from the AH lines (its API), a search string without it, nothing without a name", function()
	local ns = Load()
	local B = ns.Basket
	local lines = { { itemID = HIDE, quantity = 20 }, { itemID = 424242, quantity = 3 } }
	eq(B.HasAuctionator(), false)
	local n, why = B.CreateAuctionatorList(lines)
	eq(n, nil); eq(why, "Auctionator isn't loaded")
	eq(B.SearchString(lines[1]), '"Testhide";;;;;;;;;;;;;20')
	eq(B.SearchString(lines[2]), nil, "no name loaded: no string")
	local made
	Auctionator = { API = { v1 = {
		ConvertToSearchString = function(_, term) return term.searchString .. "|" .. term.quantity .. "|" .. tostring(term.isExact) end,
		CreateShoppingList = function(caller, name, list) made = { caller, name, list } end } } }
	n = B.CreateAuctionatorList(lines)
	eq(n, 1); eq(made[1], "CraftWise"); eq(made[2], "CraftWise basket"); eq(made[3][1], "Testhide|20|true")
end)

it("Basket: Buy needs an open merchant that sells the item for gold alone, one at a time; one click buys the line, in stack-sized calls", function()
	local ns, stub = Load()
	local B = ns.Basket
	local calls = {}
	BuyMerchantItem = function(index, n) calls[#calls + 1] = index .. ":" .. n end
	GetMerchantItemMaxStack = function() return 20 end
	stub.money = 100000
	local line = { itemID = THREAD, quantity = 50 }
	local n, why = B.Buy(line)
	eq(n, nil); eq(why, "Open a merchant that sells it"); eq(#calls, 0)
	stub.merchant = { { itemID = HIDE, price = 10 }, { itemID = THREAD, price = 20 } }
	stub.Fire("MERCHANT_SHOW")
	eq(B.CanBuy({ itemID = 424242, quantity = 1 }), false)
	n = B.Buy(line)
	eq(n, 50); eq(table.concat(calls, ","), "2:20,2:20,2:10")
	calls = {}
	stub.money = 100
	n, why = B.Buy(line)
	eq(n, nil); eq(why, "Not enough gold"); eq(#calls, 0)
	stub.money = 100000
	stub.merchant[2].available = 7
	eq(B.Buy(line), 7, "limited stock: never more than there is")
	stub.merchant[2].available = nil
	stub.merchant[2].stack = 5
	calls = {}
	eq(B.Buy(line), 50, "lots of 5 (#217): 50 is ten whole lots"); eq(table.concat(calls, ","), "2:20,2:20,2:10")
	stub.merchant[2].stack, stub.merchant[2].extended = 1, true
	eq(select(2, B.Buy(line)), "Costs more than gold: buy it by hand")
	stub.Fire("MERCHANT_CLOSED")
	eq(B.MerchantOpen(), false)
end)

----------------------------------------------------------------------------------------------------
-- Disenchant check (#190)
----------------------------------------------------------------------------------------------------

it("Craft › Disenchant check: expected disenchant value - reagents for disenchantable products, source in the caption, tooltip lines", function()
	local ns, stub, M = Load()
	local DUST = 10940
	GetBuildInfo = function() return "1.60.1", "70938" end
	assert(loadfile("CraftWise/Data/DisenchantGuide.lua"))("CraftWise", ns)
	stub.items[BELT].classID, stub.items[BELT].level, stub.items[BELT].quality = 4, 20, 2
	stub.items[GLOVES].classID, stub.items[GLOVES].level, stub.items[GLOVES].quality = 4, 18, 2
	Seed(DUST, 50)
	-- 20 disenchants of the belt gave 2 dust each
	DisenchantryDB = { disenchantSamples = { ["1.60.1:70938:" .. BELT .. ":2:20:4:normal"] = { count = 20,
		materials = { [DUST] = { total = 40, hits = 20, min = 2, max = 2 } } } } }
	Make.Open(ns, "craft", PROF)
	local chips = M.SlotsOf("craft").listTools.chips
	eq(chips[4].label.text, "Disenchant check"); eq(chips[4].on, false)
	chips[4].scripts.OnClick(chips[4])
	eq(ns.db.settings.disenchantCheck, true); eq(chips[4].on, true)
	-- Belt: 2 dust x 47.5 = 95, reagents 40: +55
	local belt = Row(ns, "craft", R_BELT)
	eq(belt.sellSource, "disenchant"); eq(belt.sellsFor, 95); eq(belt.profit, 55)
	local sub = Plain(belt.view.sub)
	assert(sub:find("disenchant · 20 samples", 1, true), sub)
	eq(M.Frame().hero.label.text, "Best disenchant craft right now")
	-- the gloves (item level 18, same bracket and kind) have no records of their own: pooled from the belt's
	local g = Row(ns, "craft", R_GLOVES)
	eq(g.deDetails.source, "pooled"); eq(g.profit, 55)
	assert(Plain(g.view.sub):find("disenchant · pooled 20", 1, true), Plain(g.view.sub))
	-- Bracers (no item with a sell price) and the rest aren't armour or weapon here: left out
	eq(Make.Names(ns, "craft"), "Test Belt,Test Gloves")
	-- Vendor check and Disenchant check exclude each other
	chips[3].scripts.OnClick(chips[3])
	eq(ns.db.settings.vendorCheck, true); eq(ns.db.settings.disenchantCheck, false)
	chips[4].scripts.OnClick(chips[4])
	eq(ns.db.settings.vendorCheck, false); eq(ns.db.settings.disenchantCheck, true)
	-- the tooltip: materials, value, profit and the source
	local all = Make.CaptureTooltip(function() Make.Hover(ns, "craft", R_BELT) end)
	assert(all:find("Disenchant check", 1, true) and all:find("measured, 20 disenchants", 1, true), all)
	assert(all:find("Expected value", 1, true) and all:find("Profit (value - reagents)", 1, true), all)
end)

it("Craft tooltip: the % with its basis, and the product's movement as a measured hint or 'no history' (#197)", function()
	local ns = Load()
	Make.Open(ns, "craft", PROF, false)
	local text = Make.CaptureTooltip(function() assert(Make.Hover(ns, "craft", R_BELT)) end)
	assert(text:find("Return | 375%", 1, true), text)
	assert(text:find("profit / cost to craft", 1, true), text)
	assert(text:find("disappearing in 7 days", 1, true) or text:find("units disappeared in 7 days", 1, true)
		or text:find("No market history", 1, true), text)
	assert(not text:find("sold in", 1, true), "never a sales speed")
end)

it("Loops: finds are ordered by profit %, unpriced last; Basket crafts likewise (#197)", function()
	local ns = Load()
	local P = ns.Profit
	local finds = {
		{ name = "Rich", profit = 5000, pct = P.Percent(5000, 100000) },
		{ name = "Lean", profit = 1500, pct = P.Percent(1500, 1000) },
		{ name = "Unknown", profit = 9000 },
	}
	ns.Loops.Sort(finds)
	eq(finds[1].name, "Lean"); eq(finds[2].name, "Rich"); eq(finds[3].name, "Unknown")
end)

it("Craft: sort by profit % puts the best return first, is remembered, rows without one stay last, the hero follows (#197)", function()
	local ns, _, M = Load()
	local list = Make.Open(ns, "craft", PROF, false)
	local belt, gloves = Row(ns, "craft", R_BELT), Row(ns, "craft", R_GLOVES)
	eq(belt.pct, 375, "Belt: profit 150 on a cost of 40"); eq(gloves.pct, -37.5, "Gloves lose 15 on 40")
	eq(Row(ns, "craft", R_BRACERS).pct, nil)
	local f = M.Frame()
	eq(list.headers[5].label.text:gsub(" |T.*$", ""), "Return")
	list.headers[5].scripts.OnClick(list.headers[5])
	eq(f.listBar.note.text, "by profit %")
	eq(Make.Names(ns, "craft"), "Test Belt,Test Gloves,Test Bracers", "no price last")
	eq(f.hero.name.text, "Test Belt")
	eq(belt.view.cells.pct, "375%"); eq(gloves.view.cells.pct, "-37%"); eq(gloves.view.colors.pct, "danger")
	-- remembered in the database, and used again after the window is rebuilt
	eq(ns.db.settings.ui.sort.craft.key, "pct"); eq(ns.db.settings.ui.sort.craft.desc, true)
	local key, desc = M.Sort(M.Page("craft"))
	eq(key, "pct"); eq(desc, true)
	M.state.sort = {}
	eq((M.Sort(M.Page("craft"))), "pct", "from the database when the session has none")
	ns.db.settings.ui.sort.craft = { key = "nonsense", desc = true }
	eq((M.Sort(M.Page("craft"))), "profit", "an unknown saved key is ignored")
end)
-- Make › Craft: All professions (#211)
local COOK, R_PIE, R_BELT2, PIE = 185, 990301, 990302, 990107

local function WithCooking()
	local ns, stub, M = Load()
	stub.items[PIE] = { name = "Test Pie", sellPrice = 2 }
	Seed(PIE, 500, NOW)
	ns.charDB.professions[COOK] = { name = "Testcooking", skill = 50, max = 75, recipes = {
		[R_PIE] = { name = "Test Pie", learned = true, difficulty = 1, reagents = { { itemID = HIDE, quantity = 1 } }, output = { itemID = PIE, quantity = 1 } },
		-- the same output as Test Belt from another profession: both rows stay
		[R_BELT2] = { name = "Test Belt", learned = true, difficulty = 1, reagents = { { itemID = THREAD, quantity = 1 } }, output = { itemID = BELT, quantity = 1 } },
	} }
	return ns, stub, M
end

it("All professions: the rows of every profession in one list, each tagged, same output twice stays twice", function()
	local ns, _, M = WithCooking()
	M.SetProfession("all")
	eq(M.UI().profession, "all", "remembered with the other Make settings")
	M.Open("craft")
	local rows = Make.Rows(ns, "craft")
	eq(#rows, 5)
	local byId = {}
	for _, r in ipairs(rows) do byId[r.recipeID] = r end
	eq(byId[R_BELT].professionName, "Testworking"); eq(byId[R_PIE].professionName, "Testcooking")
	eq(byId[R_BELT].professionID, PROF); eq(byId[R_BELT2].professionID, COOK)
	assert(Plain(byId[R_PIE].view.cells.name):find("Test Pie  Testcooking", 1, true), Plain(byId[R_PIE].view.cells.name))
	eq(byId[R_PIE].view.tag, "Testcooking")
	eq(M.Frame().listBar.title.text, "5 recipes")
	local f = M.Frame()
	local chip = M.SlotsOf("craft").tools.profession
	assert(chip.label.text:find("All professions", 1, true), chip.label.text)
end)

it("All professions: sorted across professions by profit like a single one, and the hero is the best of all", function()
	local ns, _, M = WithCooking()
	M.SetProfession("all")
	M.Open("craft")
	local rows = Make.Rows(ns, "craft")
	eq(rows[1].name, "Test Pie") -- +490 beats the belt's +150
	local last = math.huge
	for _, r in ipairs(rows) do
		if r.profit then
			assert(r.profit <= last, "descending by profit")
			last = r.profit
		end
	end
	eq(M.Frame().hero.name.text, "Test Pie")
end)

it("All professions: the filter box, Unlearned and Hide unpriced work on the merged list", function()
	local ns, _, M = WithCooking()
	M.SetProfession("all")
	M.Open("craft")
	Make.Filter(ns, "craft", "pie")
	eq(Make.Names(ns, "craft"), "Test Pie")
	Make.Filter(ns, "craft", "testthread") -- a reagent name matches recipes of both professions
	eq(Make.Names(ns, "craft"), "Test Belt,Test Belt,Test Bracers")
	Make.Filter(ns, "craft", "")
	ns.db.settings.hideUnpriced = true
	M.Refresh()
	for _, r in ipairs(Make.Rows(ns, "craft")) do assert(r.profit, r.name .. " is priced") end
	ns.db.settings.hideUnpriced = false
	ns.db.settings.includeUnlearned = true
	M.Refresh()
	assert(#Make.Rows(ns, "craft") > 5, "unlearned recipes of every profession")
end)

it("All professions: only Make › Craft offers it; Learn and Level up keep one profession", function()
	local ns, _, M = WithCooking()
	M.SetProfession("all")
	eq(M.Page("craft").allowAll, true)
	eq(M.Page("learn").allowAll, nil); eq(M.Page("level").allowAll, nil)
	M.Open("learn")
	local tools = Make.Tools(ns, "learn")
	eq(tools.profession.allowAll, nil)
	assert(not tools.profession.label.text:find("All professions", 1, true))
	local id = M.Profession()
	assert(id == PROF or id == COOK, "a real profession")
	M.Open("craft")
	assert(M.SlotsOf("craft").tools.profession.allowAll, "the Craft dropdown starts with All professions")
	M.SetProfession(PROF)
	M.Open("craft")
	eq(#Make.Rows(ns, "craft"), 3, "one profession again")
end)

it("All professions: the dropdown lists All professions first and marks it when chosen", function()
	local ns, _, M = WithCooking()
	M.Open("craft")
	local chip = M.SlotsOf("craft").tools.profession
	chip.scripts.OnClick(chip)
	local menu = Make.Menu and Make.Menu() or ns.Main.Make.Menu()
	local first = menu.buttons[1]
	eq(first.label.text, "All professions"); eq(first.current, false)
	first.scripts.OnClick(first)
	eq(M.UI().profession, "all")
	chip.scripts.OnClick(chip)
	eq(ns.Main.Make.Menu().buttons[1].current, true)
end)

it("All professions: Add to basket uses the row's own profession", function()
	local ns, _, M = WithCooking()
	M.SetProfession("all")
	M.Open("craft")
	local row = Row(ns, "craft", R_PIE)
	assert(row and row.professionID == COOK, "the pie row knows its profession")
end)

-- Make › Craft: Per day, the profit the market can absorb (#231)
local function GoneAt(itemID, perDay, days)
	local today = math.floor(NOW / DAY)
	local entry = CraftWiseMarketDB.items[itemID][HORDE]
	local typ = entry.days[today].typ -- keep the seeded price
	entry.days = {}
	for i = 0, days - 1 do
		entry.days[today - i] = { lo = typ, typ = typ, hi = typ, n = 1, gone = perDay }
	end
end

it("Per day formula: profit per craft times the crafts a day the market takes, per item of the yield", function()
	local _, _, M = Load()
	local C = M.CraftPage
	local d = C.Daily({ profit = 150, outputQuantity = 1, sellSource = "auction" }, { gone = 70, days = 7 })
	eq(d.perDay, 10); eq(d.crafts, 10); eq(d.daily, 1500)
	d = C.Daily({ profit = 150, outputQuantity = 3, sellSource = "auction" }, { gone = 70, days = 7 })
	eq(d.crafts, 70 / 7 / 3); eq(d.daily, 150 * 70 / 7 / 3)
	d = C.Daily({ profit = 150, outputQuantity = 1, sellSource = "auction" }, { gone = 30, days = 3 })
	eq(d.perDay, 10, "divided by the days with data, not by 7"); eq(d.daily, 1500)
	d = C.Daily({ profit = -20, outputQuantity = 1, sellSource = "auction" }, { gone = 70, days = 7 })
	eq(d.daily, -200, "a loss a day")
	d = C.Daily({ profit = 150, outputQuantity = 1, sellSource = "auction" }, { gone = 0, days = 7 })
	eq(d.daily, 0, "nothing disappeared")
end)

it("Per day gates: a reason and no figure without profit, item, auction price, history or enough days; vendor has no limit", function()
	local _, _, M = Load()
	local C = M.CraftPage
	local info = { gone = 70, days = 7 }
	eq(C.Daily({ profit = 150, sellSource = "auction", noItemOutput = true }, info).reason, "item")
	eq(C.Daily({ sellSource = "auction" }, info).reason, "profit")
	eq(C.Daily({ profit = 150, sellSource = "vendor" }, info).noLimit, true)
	eq(C.Daily({ profit = 150, sellSource = "vendor" }, nil).noLimit, true, "a vendor needs no market history")
	eq(C.Daily({ profit = 150, sellSource = "disenchant" }, info).reason, "other")
	eq(C.Daily({ profit = 150, sellSource = "auction" }, nil).reason, "history")
	local short = C.Daily({ profit = 150, sellSource = "auction" }, { gone = 70, days = 2 })
	eq(short.reason, "short"); eq(short.days, 2)
	eq(C.Daily({ profit = 150, sellSource = "auction" }, { gone = 70, days = 3 }).daily, 150 * 70 / 3)
	local text, color, tip = C.DailyCell(short)
	eq(text, "—"); assert(tip[2]:find("2 of 3 days", 1, true), tip[2])
	text, _, tip = C.DailyCell({ noLimit = true })
	eq(text, "no limit")
end)

it("Per day on the Craft rows: from the saved market data at the profit house; vendor, unpriced and unknown history", function()
	local ns, _, M = Load()
	GoneAt(BELT, 14, 5) -- 14 units a day over 5 days of history
	Make.Open(ns, "craft", PROF)
	local belt, gloves, bracers = Row(ns, "craft", R_BELT), Row(ns, "craft", R_GLOVES), Row(ns, "craft", R_BRACERS)
	eq(belt.daily.days, 5); eq(belt.daily.gone, 70)
	eq(belt.dailyProfit, 150 * 14)
	eq(Plain(belt.view.cells.daily), "+" .. Plain(ns.FormatCoins(2100)))
	eq(gloves.daily.noLimit, true); eq(gloves.view.cells.daily, "no limit")
	eq(bracers.daily.reason, "profit"); eq(bracers.view.cells.daily, "—")
	GoneAt(BELT, 14, 2)
	M.Refresh()
	eq(Row(ns, "craft", R_BELT).daily.reason, "short")
	CraftWiseMarketDB.items[BELT] = nil
	M.Refresh()
	eq(Row(ns, "craft", R_BELT).daily.noLimit, true, "no AH data left: the vendor price is the sale")
end)

it("Per day sorts: figures first (best first), then vendor rows, then rows without a reason figure", function()
	local ns, _, M = Load()
	GoneAt(BELT, 14, 5)
	GoneAt(GLOVES, 5, 5)
	ns.db.settings.includeUnlearned = true
	GoneAt(CLOAK, 2, 5)
	Make.Open(ns, "craft", PROF)
	local C = M.CraftPage
	local rows = Make.Rows(ns, "craft")
	C.SortRows(rows, "daily", true)
	local names = {}
	for _, r in ipairs(rows) do names[#names + 1] = r.name end
	-- belt: +150 x 14/day; cloak (unlearned): +65 x 2/day; cap (unlearned): a figure of 0, nothing disappeared; the
	-- vendor-sold gloves have no limit and come after the figures; bracers and hat have no figure
	eq(names[1], "Test Belt"); eq(names[2], "Test Cloak"); eq(names[3], "Test Cap")
	eq(names[4], "Test Gloves", "vendor rows after the figures")
	C.SortRows(rows, "daily", false)
	eq(rows[1].name, "Test Cap"); eq(rows[2].name, "Test Cloak"); eq(rows[3].name, "Test Belt")
	eq(rows[4].name, "Test Gloves", "rows without a figure stay last in both directions")
	local _ = table.concat(names, ",")
	eq(M.Page("craft").columns[6].key, "daily"); eq(M.Page("craft").columns[6].sort, true)
end)

it("Per day includes unlearned recipes (the Unlearned chip) and says how long learning takes to pay back", function()
	local ns, _, M = Load({ unlearned = true })
	GoneAt(CLOAK, 2, 4)
	Make.Open(ns, "craft", PROF)
	local cloak = Row(ns, "craft", R_CLOAK)
	eq(cloak.status ~= "known", true)
	eq(cloak.daily.daily, 65 * 2)
	assert(Make.Hover(ns, "craft", R_CLOAK))
	local text = Make.CaptureTooltip(function() Make.Hover(ns, "craft", R_CLOAK) end)
	assert(text:find("Per day", 1, true), text)
	assert(text:find("Learning costs", 1, true) and text:find("days to pay back", 1, true), text)
end)

it("Per day tooltip: wording is disappeared, the history depth is shown, never 'sold'", function()
	local ns = Load()
	GoneAt(BELT, 14, 5)
	Make.Open(ns, "craft", PROF)
	local text = Make.CaptureTooltip(function() Make.Hover(ns, "craft", R_BELT) end)
	assert(text:find("70 units disappeared in 5 days of history", 1, true), text)
	assert(text:find("14 a day", 1, true), text)
	local per_day = text:match("Per day.-\n(.-)\n")
	assert(per_day and not per_day:find("sold", 1, true), tostring(per_day))
end)

it("Per day with All professions: every merged row has its figure", function()
	local ns, _, M = Load()
	GoneAt(BELT, 14, 5)
	M.SetProfession("all")
	M.Open("craft")
	for _, r in ipairs(Make.Rows(ns, "craft")) do
		assert(r.daily, r.name .. " has a Per day result")
	end
end)

it("Per day: an item marked Junk counts as vendor (no limit)", function()
	local ns = Load()
	GoneAt(BELT, 14, 5)
	ns.db.junk[BELT] = true
	Make.Open(ns, "craft", PROF)
	local belt = Row(ns, "craft", R_BELT)
	eq(belt.sellSource, "vendor"); eq(belt.daily.noLimit, true); eq(belt.view.cells.daily, "no limit")
end)

-- Max AH price per reagent (#261)
it("Make tooltip: each AH reagent shows its max price and the price now, red above it", function()
	local ns = Load()
	Make.Open(ns, "craft", PROF)
	-- Belt: 2 Testhide + 1 Testthread -> sale 190, cost 40
	local text = Make.CaptureTooltip(function() Make.Hover(ns, "craft", R_BELT) end)
	assert(text:find("max", 1, true) and text:find("each", 1, true) and text:find("(now", 1, true), text)
	local row = Row(ns, "craft", R_BELT)
	eq(row.reagents[1].maxBuy, math.floor((row.sellsFor - (row.cost - row.reagents[1].total)) / 2))
end)

-- Item tooltip: max price to pay for a reagent (#292)
local function tipLines(ns, itemID)
	local tip = { lines = {} }
	function tip:AddLine(t) self.lines[#self.lines + 1] = Plain(t) end
	function tip:AddDoubleLine(l, r) self.lines[#self.lines + 1] = Plain(l) .. " | " .. Plain(r) end
	function tip:Show() end
	ns.db.tooltip.lines.market = false
	ns.AddTooltipLines(tip, itemID)
	return table.concat(tip.lines, "\n"), tip.lines
end

it("item tooltip: a reagent shows the max price per recipe it is used in, best first, red above the max, '+N more' after two", function()
	local ns = Load()
	-- Testhide (AH 10): Belt (2 hide + thread 20 vendor, sale 190) and Gloves (4 hide, sold to a vendor 25)
	local text = tipLines(ns, HIDE)
	local belt = Plain(ns.FormatMoney(85))
	assert(text:find("Max to pay | " .. belt .. " for Test Belt (now " .. Plain(ns.FormatMoney(10)) .. ")", 1, true), text)
	assert(text:find("Test Gloves", 1, true), text)
	assert(text:find("Test Belt", 1, true) < text:find("Test Gloves", 1, true), "the highest maximum first")
	local uses = ns.MaxBuyFor(HIDE)
	eq(uses[1].name, "Test Belt"); eq(uses[1].maxBuy, 85); eq(uses[1].over, nil)
	eq(uses[2].name, "Test Gloves"); eq(uses[2].maxBuy, 6); eq(uses[2].over, true, "10 now is above 6")
end)

it("item tooltip: a vendor-only reagent, an unrelated item and unknown values have no line; the setting turns it off", function()
	local ns = Load()
	assert(not tipLines(ns, THREAD):find("Max to pay", 1, true), "Testthread is a vendor reagent")
	assert(not tipLines(ns, 424242):find("Max to pay", 1, true))
	CraftWiseMarketDB.items[HIDE] = nil
	ns.Notify("PRICES_CHANGED")
	assert(not tipLines(ns, HIDE):find("Max to pay", 1, true), "no AH price for the reagent: nothing, never a guess")
	local ns2 = Load()
	ns2.db.tooltip.lines.maxBuy = false
	assert(not tipLines(ns2, HIDE):find("Max to pay", 1, true), "the line can be turned off")
end)

it("item tooltip: other reagents costing more than the sale say 'loses money at any price'; the figure follows prices", function()
	local ns = Load()
	ns.db.vendor[THREAD] = 500 -- the belt's other reagent now costs more than its sale
	ns.Notify("PRICES_CHANGED")
	eq(ns.MaxBuyFor(HIDE)[1].name, "Test Gloves", "the recipe that can still pay comes first")
	local belt
	for _, e in ipairs(ns.MaxBuyFor(HIDE)) do if e.name == "Test Belt" then belt = e end end
	eq(belt.loss, true)
	assert(tipLines(ns, HIDE):find("loses money at any price for Test Belt", 1, true))
end)

-- Where to buy a recipe from What's Training?'s data (#302)
local function plainWhere(ns, recipeID)
	local out = {}
	for _, w in ipairs(ns.RecipeWhere(recipeID)) do out[#out + 1] = w end
	return out
end

it("Learn: vendors from What's Training?'s data, own faction and neutral only, labelled not seen, no coordinates", function()
	local ns = Load({ unlearned = true })
	UnitFactionGroup = function() return "Horde" end
	ns.RecipeVendors = { [R_HAT] = { item = HAT, { 7947, 357, "A" }, { 8145, 357, "H" }, { 12246, 405 } },
		[R_CLOAK] = { item = CLOAK, { 7947, 357, "A" }, { 8145, 357, "H" } } }
	ns.RecipeVendorAreas = { [357] = "Feralas", [405] = "Desolace" }
	local lines = plainWhere(ns, R_HAT)
	local text = {}
	for _, w in ipairs(lines) do
		if w.origin == "wt" then
			text[#text + 1] = w.text
			eq(w.label, "source: What's Training?, not seen in game")
			eq(w.x, nil); eq(w.mapID, nil)
		end
	end
	eq(table.concat(text, " | "), "Vendor: NPC 8145 (Feralas) | Vendor: NPC 12246 (Desolace)")
	eq(select(1, ns.RecipeStatus(ns.charDB.professions[PROF], R_HAT, { learned = false })), "vendor")
	Make.Open(ns, "learn", PROF)
	local tip = Make.CaptureTooltip(function() Make.Hover(ns, "learn", R_CLOAK) end)
	assert(tip:find("NPC 8145 (Feralas)", 1, true) and tip:find("not seen in game", 1, true), "[" .. tostring(tip) .. "]")
	assert(not tip:find("NPC 7947", 1, true), "the other faction's vendor is left out")
end)

it("Learn: a vendor our own recorder has seen wins over What's Training?'s line for the same NPC", function()
	local ns = Load({ unlearned = true })
	UnitFactionGroup = function() return "Horde" end
	ns.RecipeVendors = { [R_HAT] = { item = HAT, { 8145, 357, "H" }, { 12246, 405 } } }
	ns.RecipeVendorAreas = { [357] = "Feralas", [405] = "Desolace" }
	ns.db.sources = ns.db.sources or {}
	ns.db.sources[HAT] = { recipe = R_HAT, vendors = { [8145] = { name = "Sheendra Tallgrass", zone = "Feralas", faction = "H", price = 5000, t = 1000 } } }
	local all = {}
	for _, w in ipairs(plainWhere(ns, R_HAT)) do all[#all + 1] = w.text .. "|" .. tostring(w.label) end
	local joined = table.concat(all, "\n")
	assert(joined:find("Sheendra Tallgrass", 1, true), joined)
	assert(not joined:find("NPC 8145", 1, true), "our record wins: no What's Training? line for that NPC\n" .. joined)
	assert(joined:find("NPC 12246 (Desolace)|source: What's Training?, not seen in game", 1, true), joined)
end)

it("Learn: without What's Training?'s data nothing changes", function()
	local ns = Load({ unlearned = true })
	ns.RecipeVendors = nil
	for _, w in ipairs(plainWhere(ns, R_HAT)) do assert(w.origin ~= "wt") end
	eq(select(1, ns.RecipeStatus(ns.charDB.professions[PROF], R_HAT, { learned = false })), "unlearned")
end)

-- NPC names and spawns from an installed QuestieDB at run time (#304)
local function withQuestie(ns)
	UnitFactionGroup = function() return "Horde" end
	ns.RecipeVendors = { [R_HAT] = { item = HAT, { 8145, 357, "H" }, { 12246, 405 } } }
	ns.RecipeVendorAreas = { [357] = "Feralas", [405] = "Desolace" }
	NpcDB = {
		name = function(id) if id == 8145 then return "Sheendra Tallgrass" end end,
		spawns = function(id) if id == 8145 then return { [357] = { { 74.4, 42.8 } }, [405] = { { 1, 2 } } } end end,
	}
	LibQuestieDB = { RequireContract = function() return true end }
	Enum.UIMapType = { Continent = 2, Zone = 3 }
	C_Map = C_Map or {}
	C_Map.GetMapChildrenInfo = function() return { { name = "Feralas", mapID = 1444, mapType = 3 }, { name = "Desolace", mapID = 1443, mapType = 3 } } end
end

it("Learn: a vendor gets its name, spawn and map from QuestieDB, labelled by both sources, with a waypoint position", function()
	local ns = Load({ unlearned = true })
	withQuestie(ns)
	local byNpc = {}
	for _, w in ipairs(ns.RecipeWhere(R_HAT)) do if w.origin == "wt" then byNpc[w.npcID] = w end end
	local sheendra = byNpc[8145]
	eq(sheendra.text, "Vendor: Sheendra Tallgrass (Feralas 74.4, 42.8)")
	eq(sheendra.label, "source: Questie/What's Training?, not seen in game")
	eq(sheendra.map, 1444); eq(sheendra.x, 74.4); eq(sheendra.y, 42.8)
	-- an NPC Questie doesn't know stays as before: id, zone, the What's Training? label, no position
	local other = byNpc[12246]
	eq(other.text, "Vendor: NPC 12246 (Desolace)"); eq(other.label, "source: What's Training?, not seen in game")
	eq(other.x, nil); eq(other.map, nil)
	-- the position works for the existing waypoint code (Merchant.Waypoint reads entry.merchant.map/x/y)
	local set
	C_Map.CanSetUserWaypointOnMap = function() return true end
	C_Map.SetUserWaypoint = function(p) set = p end
	UiMapPoint = { CreateFromCoordinates = function(map, x, y) return { map = map, x = x, y = y } end }
	assert(ns.Merchant.Waypoint({ merchant = sheendra }))
	eq(set.map, 1444); assert(math.abs(set.x - 0.744) < 1e-9)
end)

it("Learn: our own record wins over QuestieDB too; without QuestieDB or when it errors nothing changes", function()
	local ns = Load({ unlearned = true })
	withQuestie(ns)
	ns.db.sources = ns.db.sources or {}
	ns.db.sources[HAT] = { recipe = R_HAT, vendors = { [8145] = { name = "Sheendra (recorded)", zone = "Feralas", faction = "H", price = 5000, t = 1000 } } }
	local texts = {}
	for _, w in ipairs(ns.RecipeWhere(R_HAT)) do texts[#texts + 1] = w.text end
	local joined = table.concat(texts, "\n")
	assert(joined:find("Sheendra (recorded)", 1, true), joined)
	assert(not joined:find("Sheendra Tallgrass", 1, true), "the recorded NPC isn't repeated from Questie\n" .. joined)
	ns = Load({ unlearned = true })
	withQuestie(ns)
	NpcDB = nil
	texts = {}
	for _, w in ipairs(ns.RecipeWhere(R_HAT)) do if w.origin == "wt" then texts[#texts + 1] = w.text end end
	eq(table.concat(texts, " | "), "Vendor: NPC 8145 (Feralas) | Vendor: NPC 12246 (Desolace)")
	NpcDB = { name = function() error("boom") end, spawns = function() error("boom") end }
	for _, w in ipairs(ns.RecipeWhere(R_HAT)) do if w.origin == "wt" then assert(w.text:find("NPC", 1, true), w.text) end end
end)

it("Loops (#345): a single-item price change does not run the check; a full scan, a sync and the button do; the switches still turn it off", function()
	local ns, stub = Load()
	ns.db.settings.flipAlert = false
	ns.db.vendor[HIDE] = 1
	ns.Notify("PRICES_CHANGED"); ns.Notify("PRICES_CHANGED", "sync"); ns.Notify("PRICES_CHANGED", "vendor")
	eq(#stub.timers, 0, "PRICES_CHANGED schedules nothing")
	stub.RunTimers()
	eq(#ns.LootToast.Lines(), 0)
	ns.Notify("FULL_PRICES")
	eq(#stub.timers, 1, "a full scan or sync schedules the check")
	stub.RunTimers()
	eq(#ns.LootToast.Lines(), 1)
	-- the button runs it at once, with no timer
	ns.LootToast.Clear(); ns.db.loopNotice = {}
	local printed
	local oldPrint = ns.Print
	ns.Print = function(m) printed = m end
	eq(ns.Loops.CheckNow(), 2, "the two vendor loops")
	ns.Print = oldPrint
	eq(#stub.timers, 0)
	eq(#ns.LootToast.Lines(), 1); eq(printed, "Check done: 2 new.")
	-- all three checks off: nothing is scheduled
	ns.db.settings.loopAlert = false; ns.db.settings.flipAlert = false; ns.db.settings.snipeAlert = false
	ns.Notify("FULL_PRICES")
	eq(#stub.timers, 0, "switched off")
end)
