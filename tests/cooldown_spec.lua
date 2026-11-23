-- Cooldown-limited crafts (#413): the bundled data, the pure maths (Profit.CooldownDay, Cooldown.*), the planner (a recipe
-- on cooldown is not planned, one that is ready is capped at one craft) and the suggestion text ("Buy 2 Refined Deeprock
-- Salt and make 2 Cured Rugged Hide"). Real data for the data checks, invented items for the planner.
local MS_HOUR = 3600000

---------------------------------------------------------------------------------------- the bundled data

it("data: Salt Shaker makes Refined Deeprock Salt, 71 h, and Cured Rugged Hide uses it (DB2, not hand-written)", function()
	local ns = LoadAddon({ data = true })
	local salt = ns.CooldownItems[15409]
	assert(salt, "Refined Deeprock Salt")
	eq(salt.tool, 15846, "Salt Shaker"); eq(salt.spell, 19566); eq(salt.ms, 255600000); eq(salt.quantity, 1)
	eq(salt.reagents[1].itemID, 8150, "Deeprock Salt"); eq(salt.reagents[1].quantity, 1)
	eq(ns.Cooldown.Hours(salt.ms), "71h")
	local cured = ns.RecipeData[19047]
	local info = ns.Cooldown.Of(19047, cured.reagents)
	assert(info, "Cured Rugged Hide is cooldown-limited")
	eq(info.kind, "item"); eq(info.item, 15409); eq(info.perCraft, 1); eq(info.tool, 15846)
	eq(ns.RecipeFocus[19047], "Tanning Rack", "needs a Tanning Rack, from the spell's required focus object")
end)

it("data: recipes with their own cooldown are the transmutes and Mooncloth; the tables only name known recipes", function()
	local ns = LoadAddon({ data = true })
	eq(ns.RecipeCooldowns[17187], 169200000, "Transmute: Arcanite, 47 h")
	eq(ns.RecipeCooldowns[18560], 342000000, "Mooncloth, 95 h")
	local info = ns.Cooldown.Of(17187, ns.RecipeData[17187].reagents)
	eq(info.kind, "spell"); eq(ns.Cooldown.Label(info), "cd 47h")
	for spell, ms in pairs(ns.RecipeCooldowns) do
		assert(ns.RecipeData[spell], "recipe " .. spell)
		assert(ms >= MS_HOUR, "an hour or more")
	end
	for spell in pairs(ns.RecipeFocus) do
		assert(ns.RecipeData[spell], "focus of recipe " .. spell)
	end
	for item, e in pairs(ns.CooldownItems) do
		assert(e.tool and e.spell and e.ms >= MS_HOUR and e.quantity >= 1 and #e.reagents > 0, "complete entry " .. item)
	end
	eq(ns.Cooldown.Of(2149, ns.RecipeData[2149].reagents), nil, "an ordinary recipe has none")
end)

---------------------------------------------------------------------------------------- the pure parts

it("Remaining, ReadyText, Hours: from the client's start and duration", function()
	local C = LoadAddon().Cooldown
	eq(C.Remaining(100, 50, 120), 30); eq(C.Remaining(100, 50, 200), 0, "over"); eq(C.Remaining(0, 0, 200), 0, "no cooldown running")
	eq(C.Remaining(nil, 50, 120), nil, "no numbers, no answer"); eq(C.Remaining(100, "x", 120), nil)
	eq(C.ReadyText(0), "ready"); eq(C.ReadyText(nil), "ready")
	eq(C.ReadyText(2 * 86400 + 5 * 3600 + 120), "ready in 2d 5h")
	eq(C.ReadyText(5 * 3600 + 10 * 60), "ready in 5h 10m")
	eq(C.ReadyText(12 * 60 - 20), "ready in 12m")
	eq(C.Hours(255600000), "71h"); eq(C.Hours(3600000), "1h")
end)

it("Profit.CooldownDay: a spell cooldown is a hard cap, an item cooldown splits the demand into own and AH crafts", function()
	local ns = LoadAddon()
	local P = ns.Profit
	-- Transmute: Arcanite, 47 h: 0.51 crafts a day however big the demand
	local d = P.CooldownDay({ kind = "spell", ms = 169200000 }, 5)
	eq(d.limit, "cooldown"); assert(math.abs(d.crafts - 24 / 47) < 1e-9)
	-- a market that takes less is the limit
	d = P.CooldownDay({ kind = "spell", ms = 169200000 }, 0.2)
	eq(d.limit, "demand"); eq(d.crafts, 0.2)
	-- no demand (a vendor takes everything): the cooldown alone
	d = P.CooldownDay({ kind = "spell", ms = 86400000 }, nil)
	eq(d.crafts, 1); eq(d.limit, "cooldown")
	-- Salt Shaker, 71 h, 1 salt per craft, demand 2 a day: own 24/71 a day, the rest from the AH
	d = P.CooldownDay({ kind = "item", ms = 255600000, quantity = 1, perCraft = 1, toolHeld = true }, 2)
	eq(d.crafts, 2); assert(math.abs(d.own - 24 / 71) < 1e-9); assert(math.abs(d.ah - (2 - 24 / 71)) < 1e-9)
	-- without a Salt Shaker everything is bought; the profit per day does not drop, the AH sells it
	d = P.CooldownDay({ kind = "item", ms = 255600000, quantity = 1, perCraft = 1, toolHeld = false }, 2)
	eq(d.own, 0); eq(d.ah, 2)
	-- a demand below what the own cooldown makes: own is the demand, nothing is bought
	d = P.CooldownDay({ kind = "item", ms = 255600000, quantity = 1, perCraft = 1, toolHeld = true }, 0.1)
	eq(d.own, 0.1); eq(d.ah, 0)
	eq(P.CooldownDay({ kind = "item", ms = 255600000, quantity = 1, perCraft = 1, toolHeld = true }, nil), nil, "no demand: no figure")
	-- two units a craft halve the crafts the own units make
	d = P.CooldownDay({ kind = "item", ms = 86400000, quantity = 1, perCraft = 2, toolHeld = true }, 3)
	eq(d.own, 0.5)
end)

it("Cooldown.Split, RowText, DayLines, ShowFocus", function()
	local ns = LoadAddon()
	local C = ns.Cooldown
	local info = { kind = "item", ms = 255600000, item = 15409, perCraft = 1, tool = 15846, spell = 19566, quantity = 1 }
	local s = C.Split(info, 3, 1)
	eq(s.units, 3); eq(s.own, 1); eq(s.buy, 2)
	s = C.Split(info, 2, 5)
	eq(s.own, 2); eq(s.buy, 0, "the bags hold more than needed")
	eq(C.Split(info, 2, nil).buy, 2)
	eq(C.RowText({ cooldown = info, cdState = { toolHeld = true, remaining = 2 * 86400 + 5 * 3600, ready = false }, focus = "Tanning Rack" }),
		"cd 71h, ready in 2d 5h, needs Tanning Rack")
	eq(C.RowText({ cooldown = info, cdState = { toolHeld = false }, focus = "Tanning Rack" }), "cd 71h, needs Tanning Rack",
		"no Salt Shaker: nothing to say about its readiness")
	eq(C.RowText({ cooldown = { kind = "spell", ms = 169200000, spell = 1 }, cdState = { remaining = 0, ready = true } }), "cd 47h, ready")
	eq(C.RowText({ focus = "Tanning Rack" }), "needs Tanning Rack")
	eq(C.RowText({ focus = "Anvil" }), nil, "an Anvil recipe says nothing in the list")
	eq(C.RowText({}), nil)
	assert(C.ShowFocus("Crusader's Tanning Rack", nil) and not C.ShowFocus("Loom", nil) and C.ShowFocus("Loom", info))
	local lines = C.DayLines({ own = 24 / 71, ah = 2 - 24 / 71, crafts = 2 }, info, "Refined Deeprock Salt")
	eq(lines[1], "Own cooldown 71h: 0.34 crafts a day, costed at the AH value of the Refined Deeprock Salt.")
	eq(lines[2], "Bought at the AH: 1.66 crafts a day more, as many as the market takes (2 a day in all).")
	lines = C.DayLines({ cap = 24 / 47, crafts = 24 / 47, limit = "cooldown" }, { kind = "spell", ms = 169200000 })
	eq(lines[1], "Cooldown 47h: one craft every 47h = 0.51 crafts a day at most, nothing can be bought instead.")
end)

it("State: the spell cooldown and the Salt Shaker's item cooldown come from the client; no tool, no readiness", function()
	local ns, stub = LoadAddon()
	local C = ns.Cooldown
	stub.now = 5000
	C_Spell.GetSpellCooldown = function() return { startTime = 4000, duration = 3000, isEnabled = true, modRate = 1 } end
	local st = C.State({ kind = "spell", spell = 17187 }, 5000)
	eq(st.remaining, 2000); eq(st.ready, false)
	C_Spell.GetSpellCooldown = function() return { startTime = 0, duration = 0, isEnabled = true, modRate = 1 } end
	eq(C.State({ kind = "spell", spell = 17187 }, 5000).ready, true)
	C_Spell.GetSpellCooldown = nil
	eq(C.State({ kind = "spell", spell = 17187 }, 5000).ready, false, "no answer is never ready")
	local info = { kind = "item", item = 15409, tool = 15846, quantity = 1 }
	stub.counts[15409] = 1
	st = C.State(info, 5000)
	eq(st.toolHeld, false); eq(st.ownUnits, 1, "the salt in the bags"); eq(st.remaining, nil)
	stub.counts[15846] = 1
	C_Container.GetItemCooldown = function(id) return id == 15846 and 4000 or 0, 3000, 1 end
	st = C.State(info, 5000)
	eq(st.toolHeld, true); eq(st.remaining, 2000); eq(st.ownUnits, 1, "the shaker is not ready yet")
	C_Container.GetItemCooldown = function() return 0, 0, 1 end
	st = C.State(info, 5000)
	eq(st.ready, true); eq(st.ownUnits, 2, "the salt in the bags and the one the shaker makes now")
end)

---------------------------------------------------------------------------------------- the planner and the suggestions

it("RunPlan keeps the cooldown of a candidate on its line", function()
	local ns = LoadAddon()
	local cd = { info = { kind = "item" }, ready = "ready" }
	local c = { recipeID = 1, name = "Cured Rugged Hide", seconds = 5, channel = "vendor", each = 100, cooldown = cd,
		quote = function(n) return { cost = n * 10, cash = n * 10, seconds = 0 } end }
	eq(ns.Profit.RunPlan({ c }, { seconds = 10 }).lines[1].cooldown, cd)
end)

it("SuggestAction: 'Buy 2 Refined Deeprock Salt and make 2 Cured Rugged Hide', with own units used first", function()
	local ns = LoadAddon()
	local info = { kind = "item", ms = 255600000, item = 15409, perCraft = 1, tool = 15846, spell = 19566, quantity = 1 }
	ns.Basket.ItemName = function(id) return id == 15409 and "Refined Deeprock Salt" or "?" end
	local row = { name = "Cured Rugged Hide", count = 2, cooldown = { info = info, state = { ownUnits = 0 } } }
	eq(ns.Basket.SuggestAction(row), "Buy 2 Refined Deeprock Salt and make 2 Cured Rugged Hide")
	row.cooldown.state.ownUnits = 1
	eq(ns.Basket.SuggestAction(row), "Use 1 Refined Deeprock Salt you have, buy 1 and make 2 Cured Rugged Hide")
	row.cooldown.state.ownUnits = 4
	eq(ns.Basket.SuggestAction(row), "Use the 2 Refined Deeprock Salt you have and make 2 Cured Rugged Hide")
	eq(ns.Basket.SuggestAction(row, 1), "Use the 1 Refined Deeprock Salt you have and make 1 Cured Rugged Hide")
	eq(ns.Basket.SuggestAction({ name = "x", count = 1 }), nil, "an ordinary row has no action")
	eq(ns.Basket.SuggestAction({ name = "x", count = 1, cooldown = { info = { kind = "spell" } } }), nil, "a spell cooldown has nothing to buy")
	row.channel, row.capText, row.capped = "AH", "your sales: 4 in 14 days", true
	eq(ns.Basket.SuggestReason(row), "Use the 2 Refined Deeprock Salt you have and make 2 Cured Rugged Hide; your sales: 4 in 14 days · limit reached")
end)

-- A planner fixture: Test Belt (2 Testhide + 1 Testthread, AH 200) with an own cooldown set on its recipe.
local NOW, DAY = 1794000000, 86400
local HIDE, THREAD, BELT, R_BELT = 990001, 990002, 990101, 990201
local function Load(cooldown)
	local ns, stub = LoadAddon()
	stub.clock = NOW
	time = function() return stub.clock end
	stub.names.player = "Testperson"
	stub.items[HIDE] = { name = "Testhide" }
	stub.items[THREAD] = { name = "Testthread" }
	stub.items[BELT] = { name = "Test Belt", sellPrice = 30 }
	local list = { { HIDE, 2 }, { THREAD, 1 } }
	stub.profession = { id = 165, name = "Testworking", skill = 100, max = 150, recipes = {
		[R_BELT] = { info = { name = "Test Belt", learned = true, relativeDifficulty = 1 }, schematic = stub.Schematic(list, BELT) } } }
	ns.RecipeCooldowns = { [R_BELT] = 24 * MS_HOUR } -- a daily cooldown on the invented recipe
	stub.Fire("TRADE_SKILL_SHOW")
	ns.db.vendor[THREAD] = 20
	local db, today = CraftWiseMarketDB, math.floor(NOW / DAY)
	local function Seed(itemID, typ, tiers)
		local total = 0
		for i = 2, #tiers, 2 do total = total + tiers[i] end
		local day = function() return { lo = typ, typ = typ, hi = typ, n = 1 } end
		db.items[itemID] = db.items[itemID] or {}
		db.items[itemID].H = { raw = { { t = NOW, total = total, tiers = tiers } }, days = { [today] = day(), [today - 1] = day(), [today - 2] = day() },
			last = { t = NOW, min = tiers[1], qty = total } }
	end
	db.houses.H = { realm = "PvP", kind = "faction", faction = "Horde", label = "Horde AH", cut = { samples = 0 } }
	db.scans.H = { { t = NOW, kind = "search", items = 1, source = "ui" } }
	Seed(HIDE, 10, { 10, 5, 30, 100 }); Seed(BELT, 200, { 200, 4 })
	C_Spell.GetSpellInfo = function() return { name = "x", castTime = 2000 } end
	C_Spell.GetSpellCooldown = function() return cooldown end
	ns.db.settings.craftRunMax = 5
	return ns, stub
end

it("BuildRun: a recipe whose cooldown is running is not planned, one that is ready is planned once", function()
	local ns = Load({ startTime = 0, duration = 0, isEnabled = true, modRate = 1 })
	local plan = ns.Basket.BuildRun({})
	eq(#plan.lines, 1); eq(plan.lines[1].count, 1, "one craft per cooldown, not the 5 the demand allows")
	eq(plan.lines[1].capped, true); eq(plan.lines[1].capText, "cooldown: one craft every 24h")
	eq(plan.lines[1].cooldown.info.kind, "spell"); eq(plan.lines[1].cooldown.ready, "ready")
	eq(plan.skipped.cooldown, 0)
	ns = Load({ startTime = GetTime() - 100, duration = 86400, isEnabled = true, modRate = 1 })
	plan = ns.Basket.BuildRun({})
	eq(#plan.lines, 0, "on cooldown"); eq(plan.skipped.cooldown, 1)
	ns = Load(nil)
	eq(#ns.Basket.BuildRun({}).lines, 0, "the client did not say: nothing is planned")
end)

it("a plain recipe is not touched: no cooldown on the row, none on its plan line", function()
	local ns = Load({ startTime = 0, duration = 0, isEnabled = true, modRate = 1 })
	ns.RecipeCooldowns = {}
	ns.Notify("PROFESSIONS_CHANGED")
	local row
	for _, r in ipairs(ns.BuildRows(165, false, "profit")) do row = r end
	eq(row.cooldown, nil)
	local plan = ns.Basket.BuildRun({})
	eq(plan.lines[1].count, 5); eq(plan.lines[1].cooldown, nil); eq(plan.skipped.cooldown, 0)
end)
