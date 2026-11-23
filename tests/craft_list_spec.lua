-- Craft run 2 (#389): the craft list (intermediates first, profit per craft-second, an entry whose product another needs
-- first), craftable vs missing reagents from the bags, ticking from the craft event, the Done summary, the Make > Basket
-- rows and the panel next to the profession window. Invented data only.
local NOW = 1794000000
local DAY = 86400
local HORDE = "H"
local PROF = 165
local HIDE, THREAD, SALT, CURED = 990001, 990002, 990003, 990004
local BELT, GLOVES, SHIRT, CLOAK = 990101, 990102, 990103, 990104
local R_BELT, R_GLOVES, R_SHIRT, R_CLOAK, R_CURE = 990201, 990202, 990203, 990204, 990205

local Schematic

-- tiers = { price, qty, ... } of the latest look; typ = typical per day (3 days of it); gone = units seen leaving today.
local function Seed(itemID, typ, tiers, gone)
	local db = CraftWiseMarketDB
	local today = math.floor(NOW / DAY)
	local total = 0
	for i = 2, #tiers, 2 do total = total + tiers[i] end
	local day = function() return { lo = typ, typ = typ, hi = typ, n = 1 } end
	db.items[itemID] = db.items[itemID] or {}
	db.items[itemID][HORDE] = { raw = { { t = NOW, total = total, tiers = tiers } },
		days = { [today] = day(), [today - 1] = day(), [today - 2] = day() }, last = { t = NOW, min = tiers[1], qty = total } }
	if gone then db.items[itemID][HORDE].days[today].gone = gone end
	db.houses[HORDE] = db.houses[HORDE] or { realm = "PvP", kind = "faction", faction = "Horde", label = "Horde AH", cut = { samples = 0 } }
	db.scans[HORDE] = { { t = NOW, kind = "search", items = 1, source = "ui" } }
end

local function Recipe(name, reagents, out, qty)
	local list = {}
	for _, r in ipairs(reagents) do list[#list + 1] = { r[1], r[2] } end
	return { info = { name = name, learned = true, relativeDifficulty = 1 }, schematic = Schematic(list, out) }
end

-- Craft Testworking at skill 100:
--   Test Belt    2 Testhide + 1 Testthread -> belt, AH 200 (net 190), vendor 30      2 s
--   Test Gloves  4 Testhide -> gloves, AH 20 (net 19) vendor 25                      2 s: loses money
--   Test Shirt   1 Cured Testhide + 1 Testthread -> shirt, vendor 100, AH none       1 s
--   Cure         1 Testhide + 1 Testsalt -> Cured Testhide (AH 80)                    3 s
--   Test Cloak   1 Testthread -> cloak, vendor 60                                     no craft time known
-- Testhide at the AH: 5 at 10, then 100 at 30; Testthread (vendor 20), Testsalt (vendor 10).
local function Load(opts)
	opts = opts or {}
	local ns, stub = LoadAddon()
	stub.clock = NOW
	time = function() return stub.clock end
	stub.names.player = "Testperson"
	Schematic = stub.Schematic
	stub.items[HIDE] = { name = "Testhide" }
	stub.items[THREAD] = { name = "Testthread" }
	stub.items[SALT] = { name = "Testsalt" }
	stub.items[CURED] = { name = "Cured Testhide" }
	stub.items[BELT] = { name = "Test Belt", sellPrice = 30 }
	stub.items[GLOVES] = { name = "Test Gloves", sellPrice = 25 }
	stub.items[SHIRT] = { name = "Test Shirt", sellPrice = 100 }
	stub.items[CLOAK] = { name = "Test Cloak", sellPrice = 60 }
	stub.profession = { id = PROF, name = "Testworking", skill = 100, max = 150, recipes = {
		[R_BELT] = Recipe("Test Belt", { { HIDE, 2 }, { THREAD, 1 } }, BELT),
		[R_GLOVES] = Recipe("Test Gloves", { { HIDE, 4 } }, GLOVES),
		[R_SHIRT] = Recipe("Test Shirt", { { CURED, 1 }, { THREAD, 1 } }, SHIRT),
		[R_CURE] = Recipe("Cure Testhide", { { HIDE, 1 }, { SALT, 1 } }, CURED),
		[R_CLOAK] = Recipe("Test Cloak", { { THREAD, 1 } }, CLOAK),
	} }
	if opts.only then -- keep just these recipes (a plan of one craft is easier to check by hand)
		for id in pairs(stub.profession.recipes) do
			if not opts.only[id] then stub.profession.recipes[id] = nil end
		end
	end
	stub.Fire("TRADE_SKILL_SHOW")
	ns.db.vendor[THREAD], ns.db.vendor[SALT] = 20, 10
	Seed(HIDE, 10, { 10, 5, 30, 100 }); Seed(BELT, 200, { 200, 4 }); Seed(GLOVES, 20, { 20, 4 }); Seed(CURED, 80, { 80, 50 })
	local cast = { [R_BELT] = 2000, [R_GLOVES] = 2000, [R_SHIRT] = 1000, [R_CURE] = 3000 } -- the cloak has none
	C_Spell.GetSpellInfo = function(id) return { name = "x", castTime = cast[id] } end
	if opts.cap then ns.db.settings.craftRunMax = opts.cap end
	return ns, stub
end


local function Bags(stub, items)
	stub.bags[0] = {}
	for i, it in ipairs(items) do stub.bags[0][i] = { itemID = it[1], stackCount = it[2] } end
end

local function Names(list)
	local out = {}
	for _, l in ipairs(list.lines) do out[#out + 1] = l.name end
	return table.concat(out, ",")
end

local function Craft(ns, stub, recipeID)
	stub.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", recipeID)
end

local function ListOf(ns)
	return ns.Basket.CraftList(ns.Basket.Plan(), ns.Holdings.Carried())
end

local function Entry(id, o)
	return { entry = { recipeID = id, professionID = PROF, profitEach = o.profit, secEach = o.sec, channel = o.channel },
		row = { name = o.name, reagents = o.reagents or {}, outputItemID = o.out }, count = o.count or 1 }
end

it("CraftList: crafts in profit per craft-second order; entries without the figures after, in the plan's order", function()
	local ns = LoadAddon()
	local plan = { crafts = {
		Entry(1, { name = "Plain", count = 1 }), -- by hand: no figures
		Entry(2, { name = "Slow", profit = 1000, sec = 100, channel = "AH", count = 2 }), -- 10/s
		Entry(3, { name = "Fast", profit = 300, sec = 5, channel = "vendor", count = 3 }), -- 60/s
		Entry(4, { name = "Also plain", count = 1 }),
	}, missing = {} }
	local list = ns.Basket.CraftList(plan, {})
	eq(Names(list), "Fast,Slow,Plain,Also plain")
	eq(list.lines[1].label, "Vendor"); eq(list.lines[2].label, "AH"); eq(list.lines[3].label, nil, "no channel known: no label")
	eq(list.lines[1].pps, 60)
end)

it("CraftList: an entry whose product another entry needs comes first, however slow", function()
	local ns = LoadAddon()
	local plan = { crafts = {
		Entry(1, { name = "Shirt", profit = 900, sec = 10, out = 801, reagents = { { itemID = 700, quantity = 1 } } }),
		Entry(2, { name = "Cured", profit = 50, sec = 50, out = 700, reagents = { { itemID = 600, quantity = 1 } } }),
	}, missing = {} }
	eq(Names(ns.Basket.CraftList(plan, {})), "Cured,Shirt")
end)

it("CraftList: craftable from the bags (not the bank): ready, partly, missing with what is short", function()
	local ns = LoadAddon()
	local reagents = { { itemID = 600, quantity = 2 }, { itemID = 601, quantity = 1 } }
	local plan = { crafts = { Entry(1, { name = "Belt", profit = 10, sec = 1, reagents = reagents, count = 3 }) }, missing = {} }
	local l = ns.Basket.CraftList(plan, { [600] = 6, [601] = 3 }).lines[1]
	eq(l.state, "ready"); eq(l.can, 3)
	l = ns.Basket.CraftList(plan, { [600] = 4, [601] = 3 }).lines[1]
	eq(l.state, "partly"); eq(l.can, 2); eq(#l.missing, 0)
	l = ns.Basket.CraftList(plan, { [600] = 1 }).lines[1]
	eq(l.state, "missing"); eq(l.can, 0); eq(#l.missing, 2)
	eq(l.missing[1].itemID, 600); eq(l.missing[1].short, 1); eq(l.missing[2].itemID, 601); eq(l.missing[2].short, 1)
end)

---------------------------------------------------------------------------------------- with real recipes

it("CraftList: the intermediate the buy list crafts comes first and leaves when it is in the bags", function()
	local ns, stub = Load()
	ns.Basket.Add(R_SHIRT, PROF, 2)
	Bags(stub, { { THREAD, 2 }, { HIDE, 2 }, { SALT, 2 } })
	local list = ListOf(ns)
	eq(Names(list), "Cured Testhide,Test Shirt")
	eq(list.lines[1].kind, "intermediate"); eq(list.lines[1].left, 2); eq(list.lines[1].state, "ready", "hide and salt are in the bags")
	eq(list.lines[2].state, "missing", "no cured hide yet"); eq(list.lines[2].missing[1].itemID, CURED)
	Bags(stub, { { THREAD, 2 }, { CURED, 2 } })
	list = ListOf(ns)
	eq(Names(list), "Test Shirt"); eq(list.lines[1].state, "ready")
end)

it("OnCrafted: a craft event ticks the entry, at zero it leaves the list as a made line, then Done", function()
	local ns, stub = Load({ cap = 3, only = { [R_BELT] = true } })
	ns.Basket.UsePlan(ns.Basket.BuildRun({}), true)
	local belt = ns.Basket.Find(R_BELT)
	eq(belt.count, 3)
	local each = belt.profitEach
	Craft(ns, stub, R_BELT)
	eq(ns.Basket.Find(R_BELT).count, 2)
	local line
	for _, x in ipairs(ListOf(ns).lines) do if x.recipeID == R_BELT then line = x end end
	eq(line.left, 2); eq(line.planned, 3); eq(line.made, 1)
	eq(ListOf(ns).summary.madeTotal, 1); eq(ListOf(ns).summary.done, false)
	Craft(ns, stub, R_BELT); Craft(ns, stub, R_BELT)
	eq(ns.Basket.Find(R_BELT), nil, "no crafts left: out of the basket")
	local list = ListOf(ns)
	eq(list.lines[#list.lines].kind, "made"); eq(list.lines[#list.lines].made, 3)
	eq(list.summary.done, true); eq(list.summary.madeTotal, 3); eq(list.summary.madeProfit, 3 * each)
	Craft(ns, stub, R_GLOVES) -- not in the basket: nothing changes
	eq(ListOf(ns).summary.madeTotal, 3)
end)

it("OnCrafted: made lines move down below the crafts left; an entry without a plan profit makes the tally's profit unknown", function()
	local ns, stub = Load()
	ns.Basket.Add(R_BELT, PROF, 1, { channel = "AH", profitEach = 100, secEach = 2 })
	ns.Basket.Add(R_GLOVES, PROF, 2) -- by hand
	Craft(ns, stub, R_BELT); Craft(ns, stub, R_GLOVES)
	local list = ListOf(ns)
	eq(list.lines[1].name, "Test Gloves"); eq(list.lines[1].left, 1); eq(list.lines[1].planned, 2)
	eq(list.lines[2].kind, "made"); eq(list.lines[2].name, "Test Belt")
	eq(list.summary.madeTotal, 2); eq(list.summary.madeProfit, nil, "the made gloves had no profit figure: unknown, not 0")
	eq(list.summary.done, false)
end)

it("A new run forgets the tally: an entry added to an empty basket, Clear", function()
	local ns, stub = Load()
	ns.Basket.Add(R_BELT, PROF, 1, { channel = "AH", profitEach = 100, secEach = 2 })
	Craft(ns, stub, R_BELT)
	eq(ListOf(ns).summary.done, true)
	ns.Basket.Add(R_GLOVES, PROF, 1)
	eq(ListOf(ns).summary.madeTotal, 0); eq(Names(ListOf(ns)), "Test Gloves")
	Craft(ns, stub, R_GLOVES)
	ns.Basket.Clear()
	eq(#ListOf(ns).lines, 0)
end)

it("Make > Basket: the craft list rows (label, crafts left of planned, state, profit) and the Done hero", function()
	local ns, stub = Load()
	local B = ns.Main.BasketPage
	ns.Basket.Add(R_BELT, PROF, 2, { channel = "AH", profitEach = 1100, secEach = 2 })
	Bags(stub, { { HIDE, 4 }, { THREAD, 2 } })
	local rows = B.Rows(ns.Basket.Plan())
	eq(rows[1].kind, "craft"); eq(rows[1].name, "Test Belt")
	eq(rows[1].view.cells.qty, "2 crafts"); eq(rows[1].view.cells.where, "AH, ready")
	Craft(ns, stub, R_BELT)
	rows = B.Rows(ns.Basket.Plan())
	eq(rows[1].view.cells.qty, "1 of 2 crafts")
	Craft(ns, stub, R_BELT)
	local plan = ns.Basket.Plan()
	rows = B.Rows(plan)
	eq(rows[1].kind, "made"); eq(rows[1].view.cells.where, "AH, made")
	local hero = B.Hero(plan)
	eq(hero.name, "Done"); eq(hero.sub, "2 crafts made")
	ns.Main.Open("basket") -- draws without an error
end)

it("Make > Basket: Open recipe opens the recipe in the profession window and nothing is crafted", function()
	local ns, stub = Load()
	local opened, cast = {}, 0
	C_TradeSkillUI.OpenRecipe = function(id) opened[#opened + 1] = id return true end
	C_TradeSkillUI.CraftRecipe = function() cast = cast + 1 end
	ns.Main.Make.OpenRecipe(R_BELT)
	eq(opened[1], R_BELT); eq(cast, 0)
end)

it("Panel: it sits on the profession window, lists the crafts, and a click opens the recipe", function()
	local ns, stub = Load()
	local B = ns.Main.BasketPage
	ProfessionsFrame = CreateFrame("Frame", "ProfessionsFrame")
	ProfessionsFrame.CraftingPage = {}
	stub.Fire("TRADE_SKILL_SHOW")
	assert(B.panel, "the panel is made when the profession window opens")
	ns.Basket.Add(R_SHIRT, PROF, 1, { channel = "vendor", profitEach = 60, secEach = 1 })
	Bags(stub, { { THREAD, 1 } })
	B.DrawPanel()
	local rows = B.panel.rows
	-- #402: one line per craft: the name, the crafts made of those planned, the one thing to do; the rest is in the tooltip
	eq(rows[1].name:GetText(), "Cured Testhide  0/1  needs 1 Testhide, 1 Testsalt")
	assert(rows[2].name:GetText():find("^Test Shirt  0/1  needs "), rows[2].name:GetText())
	assert(not rows[2].name:GetText():find("\n", 1, true))
	assert(rows[2].detail:find("Vendor", 1, true), rows[2].detail)
	assert(rows[2].detail:find("missing reagents", 1, true))
	eq(rows[2].title, "Test Shirt")
	rows[2]:GetScript("OnEnter")(rows[2]) -- the tooltip draws without error
	rows[2]:GetScript("OnLeave")(rows[2])
	local opened = {}
	C_TradeSkillUI.OpenRecipe = function(id) opened[#opened + 1] = id return true end
	rows[2]:GetScript("OnClick")(rows[2])
	eq(opened[1], R_SHIRT)
	local model = B.PanelModel(ns.Basket.CraftList(ns.Basket.Plan(), ns.Holdings.Carried()))
	eq(model.sub, "1 crafts left, expected profit " .. ns.FormatCoins(60))
	ns.Basket.Clear()
	B.DrawPanel()
	eq(B.panel:IsShown(), false, "nothing to craft: no panel")
end)

it("Panel position (#397): dragging by the title saves it account-wide, a reload puts it back, right-click resets", function()
	local ns, stub = Load()
	local B = ns.Main.BasketPage
	ProfessionsFrame = CreateFrame("Frame", "ProfessionsFrame")
	ProfessionsFrame.CraftingPage = {}
	stub.Fire("TRADE_SKILL_SHOW")
	local panel = B.panel
	local p1, rel = panel:GetPoint(1)
	eq(p1, "TOPLEFT"); eq(rel, ProfessionsFrame, "beside the profession window until it is moved")
	eq(panel.movable ~= false, true)
	local handle = panel.handle
	handle:GetScript("OnDragStart")(handle)
	panel:ClearAllPoints(); panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", 120, 640) -- where the client left it
	handle:GetScript("OnDragStop")(handle)
	local pos = ns.db.settings.craftListPos
	eq(pos.point, "TOPLEFT"); eq(pos.relPoint, "BOTTOMLEFT"); eq(pos.x, 120); eq(pos.y, 640)
	-- a new session (the same saved data) opens it there
	local ns2, stub2 = LoadAddon({ savedDB = ns.db })
	ProfessionsFrame = CreateFrame("Frame", "ProfessionsFrame")
	ProfessionsFrame.CraftingPage = {}
	stub2.Fire("TRADE_SKILL_SHOW")
	local p2, rel2, rp2, x2, y2 = ns2.Main.BasketPage.panel:GetPoint(1)
	eq(p2, "TOPLEFT"); eq(rel2, UIParent); eq(rp2, "BOTTOMLEFT"); eq(x2, 120); eq(y2, 640)
	-- right-click on the title: back beside the profession window, and nothing is saved
	local h2 = ns2.Main.BasketPage.panel.handle
	h2:GetScript("OnClick")(h2)
	local p3, rel3 = ns2.Main.BasketPage.panel:GetPoint(1)
	eq(rel3, ProfessionsFrame); eq(ns2.db.settings.craftListPos.point, nil)
	-- Settings > Look > Reset window positions does the same
	panel = ns2.Main.BasketPage.panel
	panel:ClearAllPoints(); panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", 5, 5)
	ns2.Main.Settings.ResetPositions()
	eq(({ panel:GetPoint(1) })[2], ProfessionsFrame)
end)

it("Panel position (#397): only the title strip takes the mouse for the drag, and the panel is clamped to the screen", function()
	local ns, stub = Load()
	local B = ns.Main.BasketPage
	ProfessionsFrame = CreateFrame("Frame", "ProfessionsFrame")
	ProfessionsFrame.CraftingPage = {}
	stub.Fire("TRADE_SKILL_SHOW")
	eq(B.panel.handle:GetParent(), B.panel)
	assert(B.panel.handle.scripts.OnDragStart and B.panel.handle.scripts.OnDragStop)
	eq(B.panel.scripts.OnDragStart, nil, "the sheet itself is not a drag handle")
end)
