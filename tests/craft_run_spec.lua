-- Craft run 1 (#388): the planner (budget, time, both, demand cap, depth walk, intermediates, bags at their value,
-- vendor only), the demand cap's three sources, the entry fields "Use plan" stores, the panel section, and the
-- price refresh that searches item by item and never asks for the whole list. Invented data only.
local NOW = 1794000000
local DAY = 86400
local HORDE = "H"
local PROF = 165 -- a profession id the addon knows as a skill line; its recipes are invented
local HIDE, THREAD, SALT, CURED = 990001, 990002, 990003, 990004 -- reagents; CURED is made from HIDE + SALT
local BELT, GLOVES, SHIRT, CLOAK = 990101, 990102, 990103, 990104 -- outputs
local R_BELT, R_GLOVES, R_SHIRT, R_CLOAK, R_CURE = 990201, 990202, 990203, 990204, 990205

---------------------------------------------------------------------------------------- the pure planner

-- A candidate with a linear cost: n crafts cost n * unit (cash the same), `extra` seconds per craft of intermediates.
local function Cand(name, o)
	local c = { recipeID = o.id or #name, name = name, seconds = o.sec, channel = o.channel or "vendor", each = o.each,
		cap = o.cap, capText = o.capText, timeLabel = "measured" }
	c.quote = o.quote or function(n)
		return { cost = n * o.unit, cash = n * (o.cash or o.unit), seconds = 0 }
	end
	return c
end

it("RunPlan: crafts are taken best profit per crafting second first, not best total profit", function()
	local ns = LoadAddon()
	-- slow: 100 profit in 100 s (1/s), fast: 20 profit in 5 s (4/s)
	local slow = Cand("Slow", { id = 1, sec = 100, each = 150, unit = 50 })
	local fast = Cand("Fast", { id = 2, sec = 5, each = 30, unit = 10, cap = 3 })
	local plan = ns.Profit.RunPlan({ slow, fast }, { seconds = 220 })
	eq(plan.lines[1].name, "Fast"); eq(plan.lines[1].count, 3, "its cap")
	eq(plan.lines[2].name, "Slow"); eq(plan.lines[2].count, 2, "220 - 15 s leaves room for two slow crafts")
	eq(plan.seconds, 3 * 5 + 2 * 100); eq(plan.profit, 3 * 20 + 2 * 100); eq(plan.limit, "time")
end)

it("RunPlan: the budget stops the plan, counted in cash", function()
	local ns = LoadAddon()
	local a = Cand("A", { id = 1, sec = 10, each = 200, unit = 100 })
	local plan = ns.Profit.RunPlan({ a }, { budget = 350 })
	eq(plan.lines[1].count, 3); eq(plan.cost, 300); eq(plan.limit, "budget")
	plan = ns.Profit.RunPlan({ a }, { budget = 0 })
	eq(#plan.lines, 0, "no gold, nothing to buy")
	-- a craft whose reagents are all in the bags costs no cash but is still worth what they would sell for
	local held = Cand("Held", { id = 2, sec = 10, each = 200, unit = 100, cash = 0 })
	plan = ns.Profit.RunPlan({ held }, { budget = 0, seconds = 35 })
	eq(plan.lines[1].count, 3, "time ends it"); eq(plan.cost, 0); eq(plan.profit, 3 * 100, "profit counts the held reagents at their value")
end)

it("RunPlan: budget and time together: whichever is used up first ends a craft", function()
	local ns = LoadAddon()
	local a = Cand("A", { id = 1, sec = 10, each = 200, unit = 100 }) -- 10 per second
	local b = Cand("B", { id = 2, sec = 20, each = 150, unit = 30 }) -- 6 per second, cheap
	local plan = ns.Profit.RunPlan({ a, b }, { budget = 260, seconds = 60 })
	local counts = {}
	for _, l in ipairs(plan.lines) do counts[l.name] = l.count end
	-- A first (10/s) while it fits both: 2 crafts use 200 gold and 20 s; a third would need 300 gold. B fills the rest: 2 crafts = 40 s, 60 gold
	eq(counts.A, 2); eq(counts.B, 2); eq(plan.cost, 260); eq(plan.seconds, 60)
end)

it("RunPlan: the demand cap ends a craft and is reported when nothing else stopped the plan", function()
	local ns = LoadAddon()
	local a = Cand("A", { id = 1, sec = 10, each = 200, unit = 100, cap = 4, capText = "your sales: 4 sold in 14 days" })
	local plan = ns.Profit.RunPlan({ a }, {})
	eq(plan.lines[1].count, 4); eq(plan.lines[1].capped, true); eq(plan.limit, "demand")
	eq(plan.lines[1].capText, "your sales: 4 sold in 14 days")
end)

it("RunPlan: the depth walk: a dearer tier raises the next craft's cost and the plan stops where it stops paying", function()
	local ns = LoadAddon()
	-- the first two crafts cost 40 each, the next ones 120: the sale is 100, so only two pay
	local walk = Cand("Walk", { id = 1, sec = 10, each = 100, quote = function(n)
		local cost = n <= 2 and n * 40 or 80 + (n - 2) * 120
		return { cost = cost, cash = cost, seconds = 0 }
	end })
	local plan = ns.Profit.RunPlan({ walk }, {})
	eq(plan.lines[1].count, 2); eq(plan.lines[1].cost, 80)
	-- a quote that is missing ends the run of that craft (the stored tiers hold no more units)
	local short = Cand("Short", { id = 2, sec = 10, each = 100, quote = function(n)
		if n > 3 then return nil end
		return { cost = n * 10, cash = n * 10, seconds = 0 }
	end })
	eq(ns.Profit.RunPlan({ short }, {}).lines[1].count, 3)
end)

it("RunPlan: intermediates' crafting seconds count in the time", function()
	local ns = LoadAddon()
	local c = Cand("Shirt", { id = 1, sec = 2, each = 100, quote = function(n)
		return { cost = n * 30, cash = n * 30, seconds = n * 3 } -- one cure craft of 3 s per shirt
	end })
	local plan = ns.Profit.RunPlan({ c }, { seconds = 20 })
	eq(plan.lines[1].count, 4, "4 x (2 + 3) = 20 s"); eq(plan.lines[1].seconds, 20); eq(plan.lines[1].secEach, 5)
end)

it("RunPlan: the cash of all lines together decides, so a shared reagent is not paid for twice", function()
	local ns = LoadAddon()
	local a = Cand("A", { id = 1, sec = 10, each = 200, unit = 100 })
	local b = Cand("B", { id = 2, sec = 20, each = 200, unit = 100 })
	-- alone each craft costs 100; together the lines cost more (the shared reagent's dearer tier): 150 per craft
	local plan = ns.Profit.RunPlan({ a, b }, { budget = 450, total = function(lines)
		local n = 0
		for _, l in ipairs(lines) do n = n + l.count end
		return n * 150
	end })
	local n = 0
	for _, l in ipairs(plan.lines) do n = n + l.count end
	eq(n, 3, "3 x 150 = 450 fits, 4 does not"); eq(plan.cost, 450); eq(plan.limit, "budget")
end)

---------------------------------------------------------------------------------------- the demand cap and the sale

it("DemandCap: own sales first, then observed drops, then the default; each says what it is", function()
	local ns = LoadAddon()
	local B = ns.Basket
	local cap, perDay, source, text = B.DemandCap({ units = 28, days = 14 }, { units = 100, days = 7 }, 1, 2)
	eq(cap, 2); eq(source, "sales"); eq(perDay, 2); eq(text, "your sales: 28 sold in 14 days, 2.0 a day")
	cap, perDay, source, text = B.DemandCap({ units = 0, days = 14 }, { units = 14, days = 7 }, 1, 2)
	eq(cap, 2); eq(source, "drops"); eq(text, "observed drops: 14 units in 7 days, 2.0 a day (a cancel looks the same)")
	cap, _, source, text = B.DemandCap({ units = 0, days = 14 }, { units = 21, days = 7 }, 1, 2)
	eq(cap, 3); eq(source, "drops")
	cap, perDay, source, text = B.DemandCap({ units = 0, days = 14 }, { units = 0, days = 7 }, 1, 2)
	eq(cap, 2); eq(perDay, nil); eq(source, "default"); eq(text, "no sales data: at most 2", "no drops can also mean too few scans: never a rate")
	cap, _, source = B.DemandCap(nil, nil, 1, 5)
	eq(cap, 5); eq(source, "default")
	cap = B.DemandCap({ units = 6, days = 14 }, nil, 1, 2)
	eq(cap, 1, "a slow seller still gets one craft: 6 in 14 days is 0.4 a day")
	cap = B.DemandCap({ units = 28, days = 14 }, nil, 2, 2)
	eq(cap, 1, "a craft makes 2 units: 2 a day is 1 craft")
end)

it("SaleOf: the AH when it pays more and its cut is known, else the vendor; vendor only always the vendor", function()
	local ns = LoadAddon()
	local S = ns.Basket.SaleOf
	local ch, each = S({ vendor = 30, auction = { net = 190 }, chosen = "auction" }, false)
	eq(ch, "AH"); eq(each, 190)
	ch, each = S({ vendor = 30, auction = { net = 190 }, chosen = "auction" }, true)
	eq(ch, "vendor"); eq(each, 30)
	ch, each = S({ vendor = 25, auction = { net = 19 }, chosen = "vendor" }, false)
	eq(ch, "vendor"); eq(each, 25)
	ch, each = S({ vendor = 0, auction = { net = 19 }, chosen = "auction" }, true)
	eq(ch, nil); eq(each, "no vendor price")
	ch, each = S({ vendor = 0, auction = { cutUnverified = true }, chosen = "auction" }, false)
	eq(ch, nil); eq(each, "the AH cut is not known", "an unverified cut gives a gross price, not a profit")
	ch, each = S({ vendor = 30, auction = { cutUnverified = true }, chosen = "auction" }, false)
	eq(ch, "vendor"); eq(each, 30)
	ch = S({}, false)
	eq(ch, nil)
end)

it("CraftSeconds: the measured median, else the cast time from the client, said so, else nothing", function()
	local ns, stub = LoadAddon()
	stub.clock = NOW
	time = function() return stub.clock end
	local real = C_Spell.GetSpellInfo
	C_Spell.GetSpellInfo = function(id) return id == 7 and { name = "x", castTime = 2500 } or id == 8 and { name = "y", castTime = 0 } or nil end
	local sec, label = ns.Basket.CraftSeconds(7)
	eq(sec, 2.5); eq(label, "cast time, not measured")
	eq(ns.Basket.CraftSeconds(8), nil, "an instant or unknown cast is no time")
	eq(ns.Basket.CraftSeconds(9), nil)
	ns.db.crafted.chars["a"] = { [7] = { speed = { n = 6, sum = 30, gaps = { 5, 5, 5, 5, 5, 5 } } } }
	sec, label = ns.Basket.CraftSeconds(7)
	eq(sec, 5); eq(label, "measured")
	C_Spell.GetSpellInfo = real
end)

---------------------------------------------------------------------------------------- the plan from real data

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

local function ByName(plan)
	local out = {}
	for _, l in ipairs(plan.lines) do out[l.name] = l end
	return out
end

it("BuildRun: the belt is capped at the default 2 without sales data; the losing gloves and the cast-less cloak stay out", function()
	local ns = Load()
	local plan = ns.Basket.BuildRun({})
	local by = ByName(plan)
	assert(by["Test Belt"], "the belt is planned")
	eq(by["Test Belt"].count, 2, "no sales data: the setting's default"); eq(by["Test Belt"].channel, "AH")
	eq(by["Test Belt"].capText, "no sales data: at most 2"); eq(by["Test Belt"].timeLabel, "cast time, not measured")
	eq(by["Test Gloves"], nil, "gloves lose money"); eq(by["Test Cloak"], nil, "no craft time: left out")
	eq(plan.skipped.noTime, 1)
	-- 2 belts: 4 hide at 10 + 2 thread at 20 = 80 cost; sale 2 x 190
	eq(by["Test Belt"].cost, 80); eq(by["Test Belt"].profit, 2 * 190 - 80); eq(by["Test Belt"].seconds, 4)
end)

it("BuildRun: a bigger cap walks the depth: the 6th hide costs 30, not 10", function()
	local ns = Load({ cap = 5, only = { [R_BELT] = true } })
	local plan = ns.Basket.BuildRun({})
	local belt = ByName(plan)["Test Belt"]
	eq(belt.count, 5)
	-- 10 hide: 5 at 10 and 5 at 30 = 200, 5 thread = 100
	eq(belt.cost, 300); eq(belt.profit, 5 * 190 - 300); eq(plan.cost, 300)
	local names = {}
	for _, b in ipairs(plan.buy) do names[b.itemID] = b.quantity end
	eq(names[HIDE], 10); eq(names[THREAD], 5)
end)

it("BuildRun: what the bags hold is worth its AH price in the profit; only the budget counts cash", function()
	local ns, stub = Load({ cap = 5, only = { [R_BELT] = true } })
	stub.bags[0] = { { itemID = HIDE, stackCount = 10, quality = 1 } }
	ns.Notify("BAGS_CHANGED")
	local plan = ns.Basket.BuildRun({})
	local belt = ByName(plan)["Test Belt"]
	eq(belt.count, 5)
	eq(belt.cost, 300, "the held hide counts at the price it would cost")
	eq(belt.profit, 5 * 190 - 300)
	eq(plan.cost, 100, "only the thread is bought")
	-- a budget of 0 plans what the bags already hold the reagents for
	plan = ns.Basket.BuildRun({ budget = 100 })
	eq(ByName(plan)["Test Belt"].count, 5)
	plan = ns.Basket.BuildRun({ budget = 40 })
	eq(ByName(plan)["Test Belt"].count, 2, "thread is 20 a craft: 40 gold, 2 belts"); eq(plan.limit, "budget")
end)

it("BuildRun: an intermediate that is cheaper to craft is crafted and its time counts; the buy list has its inputs", function()
	local ns = Load({ only = { [R_SHIRT] = true, [R_CURE] = true } })
	local plan = ns.Basket.BuildRun({ vendorOnly = true, seconds = 4 })
	local shirt = ByName(plan)["Test Shirt"]
	assert(shirt, "the shirt is planned")
	eq(shirt.channel, "vendor"); eq(shirt.count, 1, "4 s: one shirt with its cure")
	-- the cured hide: crafted (1 hide 10 + 1 salt 10 = 20) rather than bought at 80; plus one thread 20
	eq(shirt.cost, 40); eq(shirt.profit, 100 - 40)
	eq(shirt.seconds, 1 + 3, "the shirt's cast and the cure's cast"); eq(shirt.timeLabel, "cast time, not measured")
	local crafts = {}
	for _, c in ipairs(plan.crafts) do crafts[c.itemID] = c.crafts end
	eq(crafts[CURED], shirt.count)
	local buy = {}
	for _, b in ipairs(plan.buy) do buy[b.itemID] = b.quantity end
	eq(buy[CURED], nil, "not bought"); eq(buy[HIDE], shirt.count); eq(buy[SALT], shirt.count)
end)

it("BuildRun: when the AH lists too little for the whole plan the plan is cut to what can be bought", function()
	-- shirts and belts both need hide, 105 listed in all: separately each fits, together they do not
	local ns = Load({ cap = 60, only = { [R_SHIRT] = true, [R_CURE] = true, [R_BELT] = true } })
	local plan = ns.Basket.BuildRun({})
	for _, b in ipairs(plan.buy) do assert(b.quote, "every line of the buy list can be bought: " .. b.itemID) end
	local hide = 0
	for _, b in ipairs(plan.buy) do if b.itemID == HIDE then hide = b.quantity end end
	assert(hide <= 105 and hide > 0, "hide asked for: " .. hide)
	eq(plan.limit, "supply")
end)

it("BuildRun: Vendor only plans every craft at the vendor price and without a cap; the belt then pays 30", function()
	local ns = Load()
	local plan = ns.Basket.BuildRun({ vendorOnly = true })
	local by = ByName(plan)
	eq(by["Test Belt"], nil, "a belt costs 40 and a vendor pays 30")
	assert(by["Test Shirt"], "the shirt sells to a vendor at 100")
	eq(by["Test Shirt"].count > 2, true, "no cap on vendor sales")
	for _, l in ipairs(plan.lines) do eq(l.channel, "vendor") end
	eq(plan.opts.vendorOnly, true)
end)

it("BuildRun: the time limit and the budget limit shrink the plan; both together the smaller", function()
	local ns = Load({ cap = 50 })
	local free = ns.Basket.BuildRun({})
	local timed = ns.Basket.BuildRun({ seconds = 20 })
	assert(timed.seconds <= 20, "the plan fits the time"); assert(timed.seconds < free.seconds)
	eq(timed.limit, "time")
	local poor = ns.Basket.BuildRun({ budget = 150 })
	assert(poor.cost <= 150, "the plan fits the gold"); eq(poor.limit, "budget")
	local both = ns.Basket.BuildRun({ budget = 150, seconds = 10 })
	assert(both.cost <= 150 and both.seconds <= 10)
	assert(both.profit <= timed.profit and both.profit <= poor.profit)
end)

it("Demand: his own AH sales set the cap, else observed drops, each named in the plan's line", function()
	local ns = Load({ cap = 9 })
	ns.Auctions.List()[1] = { i = BELT, n = "Test Belt", q = 28, st = "sold", soldT = NOW - 3 * DAY, kind = "commodity", h = HORDE }
	local belt = ByName(ns.Basket.BuildRun({}))["Test Belt"]
	eq(belt.count, 2, "28 sold in 14 days = 2 a day"); eq(belt.capText, "your sales: 28 sold in 14 days, 2.0 a day")
	-- a sale older than the window, or one whose units are not known, counts for nothing
	ns.Auctions.List()[1] = { i = BELT, q = 28, st = "sold", soldT = NOW - 20 * DAY }
	ns.Auctions.List()[2] = { i = BELT, q = 28, st = "sold", soldT = NOW - DAY, qtyUnknown = true }
	ns.Auctions.List()[3] = { i = BELT, q = 28, st = "gone", soldT = NOW - DAY }
	belt = ByName(ns.Basket.BuildRun({}))["Test Belt"]
	eq(belt.count, 9, "no sales: the setting (9 here)"); eq(belt.capText, "no sales data: at most 9")
	-- observed drops: 21 units left in the 3 days with data = 7 a day
	Seed(BELT, 200, { 200, 4 }, 21)
	belt = ByName(ns.Basket.BuildRun({}))["Test Belt"]
	eq(belt.capText, "observed drops: 21 units in 3 days, 7.0 a day (a cancel looks the same)"); eq(belt.count, 7)
	-- own sales still win over drops
	ns.Auctions.List()[4] = { i = BELT, q = 14, st = "settled", soldT = NOW - DAY }
	belt = ByName(ns.Basket.BuildRun({}))["Test Belt"]
	eq(belt.count, 1); eq(belt.capText, "your sales: 14 sold in 14 days, 1.0 a day")
end)

---------------------------------------------------------------------------------------- Use plan

it("UsePlan: the crafts go into the basket with their channel, profit per craft and seconds per craft; replace or add", function()
	local ns = Load({ cap = 3 })
	local plan = ns.Basket.BuildRun({})
	local belt = ByName(plan)["Test Belt"]
	ns.Basket.Add(R_CLOAK, PROF, 4) -- already there by hand
	local changed = 0
	ns.Listen("BASKET_CHANGED", function() changed = changed + 1 end)
	local n = ns.Basket.UsePlan(plan, false)
	eq(changed, 1, "one BASKET_CHANGED for the whole plan"); assert(n >= 3)
	local e = ns.Basket.Find(R_BELT)
	eq(e.count, 3); eq(e.professionID, PROF); eq(e.channel, "AH"); eq(e.profitEach, belt.profitEach); eq(e.secEach, belt.secEach)
	eq(ns.Basket.Find(R_CLOAK).count, 4, "added to, not replaced"); eq(ns.Basket.Find(R_CLOAK).channel, nil, "by hand: no plan fields")
	ns.Basket.UsePlan(plan, false)
	eq(ns.Basket.Find(R_BELT).count, 6, "again adds")
	ns.Basket.UsePlan(plan, true)
	eq(ns.Basket.Find(R_BELT).count, 3, "replaced"); eq(ns.Basket.Find(R_CLOAK), nil)
	-- Basket.Add keeps its old meaning and can carry the fields too
	ns.Basket.Add(R_GLOVES, PROF, 1, { channel = "vendor", profitEach = 5, secEach = 2 })
	eq(ns.Basket.Find(R_GLOVES).channel, "vendor"); eq(ns.Basket.Find(R_GLOVES).profitEach, 5)
	ns.Basket.Plan() -- the basket's own page still reads the entries
end)

---------------------------------------------------------------------------------------- the panel

local function Panel(ns, stub)
	AuctionHouseFrame = CreateFrame("Frame", "AuctionHouseFrame")
	stub.Fire("AUCTION_HOUSE_SHOW")
	return ns.AHPanel
end

it("Panel: Build plan reads the box and the mode; a typed budget that does not read says so and builds nothing", function()
	local ns, stub = Load({ cap = 5 })
	local P = Panel(ns, stub)
	local st = P.RunState()
	eq(st.open, false, "closed by default: one line")
	st.open, st.mode, st.budgetText, st.minutes = true, "typed", "50", ""
	eq(P.RunBudget(), 50 * 10000)
	st.budgetText = "12g 50s"
	eq(P.RunBudget(), 125000)
	st.budgetText = "lots"
	local b, why = P.RunBudget()
	eq(b, nil); eq(why, "Budget: type it like 50g or 12g 50s")
	eq(P.RunBuild(), nil); eq(P.runPlan, nil); eq(P.runStatus, why)
	st.mode = "bags"; stub.money = 777
	eq(P.RunBudget(), 777)
	st.mode, st.minutes = "none", "10"
	eq(P.RunSeconds(), 600)
	st.minutes = "abc"
	local s, w = P.RunSeconds()
	eq(s, nil); assert(w)
	st.minutes = ""
	eq(P.RunSeconds(), nil)
	local plan = P.RunBuild()
	assert(plan and #plan.lines > 0); eq(P.runStatus, ("%d crafts planned"):format(#plan.lines))
end)

it("Panel: the plan's lines, totals, the stop reason and the buy lines read as text", function()
	local ns, stub = Load({ cap = 5 })
	local P = Panel(ns, stub)
	local st = P.RunState()
	st.open = true
	local plan = P.RunBuild()
	local belt
	for _, l in ipairs(plan.lines) do if l.name == "Test Belt" then belt = l end end
	eq(P.RunLineName(belt), "5 × Test Belt · AH")
	local detail = P.RunLineDetail(belt)
	assert(detail:find("profit ", 1, true) and detail:find("each", 1, true) and detail:find("/min", 1, true), detail)
	assert(detail:find("(cast time, not measured)", 1, true), detail)
	assert(P.RunLineSource(belt):find("no sales data: at most 5", 1, true))
	assert(P.RunTotals(plan):find("Cost ", 1, true))
	eq(P.RunLimitText({ limit = "budget", skipped = { noTime = 2, noSale = 0, noPrice = 1 } }),
		"Stopped by the budget · 2 without a craft time · 1 with a reagent price missing")
	eq(P.RunLimitText({ limit = nil, skipped = {} }), nil)
	local line = P.RunBuyText({ itemID = HIDE, quantity = 10, quote = { source = "auction", cost = 200 } })
	assert(line:find("10 × Testhide · AH ", 1, true), line)
	assert(P.RunBuyText({ itemID = THREAD, quantity = 5, quote = { source = "vendor", cost = 100 } }):find("vendor", 1, true))
	-- drawing it does not fail and a click on Use plan fills the basket
	P.Update()
	eq(P.RunUse(true) > 0, true)
	assert(ns.Basket.Find(R_BELT))
	assert(P.runStatus:find("crafts are in the basket", 1, true), P.runStatus)
end)

---------------------------------------------------------------------------------------- Refresh prices

local function Ah(ns, stub)
	AuctionHouseFrame = CreateFrame("Frame", "AuctionHouseFrame")
	local ah = { searches = {} }
	local C = C_AuctionHouse
	C.MakeItemKey = function(id) return { itemID = id, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 } end
	C.GetItemKeyInfo = function(key) return { isCommodity = key.itemID ~= BELT } end
	C.SendSearchQuery = function(key, sorts, sep) ah.searches[#ah.searches + 1] = key.itemID end
	stub.Fire("AUCTION_HOUSE_SHOW")
	return ah
end

local function Answer(stub, itemID, commodity)
	if commodity then
		stub.commodity[itemID] = stub.commodity[itemID] or { rows = { { itemID = itemID, quantity = 5, unitPrice = 10, auctionID = itemID } }, total = 5 }
		stub.Fire("COMMODITY_SEARCH_RESULTS_UPDATED", itemID)
	else
		stub.itemSearch[itemID] = stub.itemSearch[itemID] or { rows = { { itemKey = { itemID = itemID }, auctionID = 1, quantity = 1, buyoutAmount = 150 } } }
		stub.Fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = itemID })
	end
end

it("Refresh: the plan's items are searched one by one from one click, each after the answer to the one before", function()
	local ns, stub = Load({ cap = 5 })
	local ah = Ah(ns, stub)
	local plan = ns.AHPanel.RunBuild()
	local want = {}
	for _, id in ipairs(plan.search) do want[#want + 1] = id end
	assert(#want >= 2, "reagents and products")
	eq(#ah.searches, 0, "building a plan searches nothing")
	ns.AHPanel.RunRefresh()
	eq(#ah.searches, 1, "the click sends the first search and only that"); eq(ah.searches[1], want[1])
	for i = 1, #want do
		eq(ah.searches[i], want[i], "in the plan's order")
		Answer(stub, want[i], want[i] ~= BELT)
		eq(ns.Market.SweepRunning(), true)
		stub.RunTimers() -- the recorder's settle and ours
	end
	eq(#ah.searches, #want, "each item once"); eq(ns.Market.SweepRunning(), false)
	assert(ns.AHBuy.state.message:find("Refreshed " .. #want .. " of " .. #want, 1, true), tostring(ns.AHBuy.state.message))
	-- the answers were recorded like any search
	assert(ns.Market.Current(HIDE, HORDE).t >= NOW)
end)

it("Refresh: it never asks for the whole list: no replicate, the scan cooldown untouched", function()
	local ns, stub = Load({ cap = 5 })
	local ah = Ah(ns, stub)
	local before = ns.Market.ScanCooldown(NOW)
	ns.AHPanel.RunBuild()
	ns.AHPanel.RunRefresh()
	for _, id in ipairs(ah.searches) do Answer(stub, id, id ~= BELT) end
	stub.RunTimers()
	eq(stub.replicateRequests, nil, "ReplicateItems was never called")
	eq(ns.Market.ScanCooldown(NOW), before); eq(ns.db and CraftWiseMarketDB.ownScan.requested or nil, CraftWiseMarketDB.ownScan.requested)
	-- and the source of the pieces that make the refresh does not name it
	for _, path in ipairs({ "CraftWise/UI/AHPanel.lua", "CraftWise/AHBuy.lua", "CraftWise/Basket.lua" }) do
		local f = assert(io.open(path, "rb")); local text = f:read("*a"); f:close()
		assert(not text:find("ReplicateItems", 1, true), path .. " names ReplicateItems")
	end
end)

it("Refresh: a second click stops it; an item that never answers is skipped after the timeout and counted", function()
	local ns, stub = Load({ cap = 5 })
	local ah = Ah(ns, stub)
	ns.AHPanel.RunBuild()
	ns.AHPanel.RunRefresh()
	eq(ns.Market.SweepRunning(), true)
	ns.AHPanel.RunRefresh()
	eq(ns.Market.SweepRunning(), false); eq(ns.AHBuy.state.message, "Refresh stopped")
	local sent = #ah.searches
	stub.RunTimers()
	eq(#ah.searches, sent, "nothing goes on after a stop")
	-- no answer at all: the timeout of each item moves on
	ns.AHPanel.RunRefresh()
	local n = #ns.AHPanel.runPlan.search
	for _ = 1, n do stub.RunTimers() end
	eq(ns.Market.SweepRunning(), false)
	assert(ns.AHBuy.state.message:find("got no answer", 1, true), tostring(ns.AHBuy.state.message))
end)

it("Refresh: it waits for the client's throttle, and closing the auction house ends it", function()
	local ns, stub = Load({ cap = 5 })
	local ah = Ah(ns, stub)
	ns.AHPanel.RunBuild()
	stub.throttleReady = false
	ns.AHPanel.RunRefresh()
	eq(#ah.searches, 0, "the system is busy: nothing is sent")
	stub.RunTimers()
	eq(#ah.searches, 0)
	stub.throttleReady = true
	stub.RunTimers()
	eq(#ah.searches, 1)
	stub.Fire("AUCTION_HOUSE_CLOSED")
	eq(ns.Market.SweepRunning(), false)
	stub.RunTimers()
	eq(#ah.searches, 1)
end)

it("Refresh: it does not start during a purchase, and a purchase press does not run during it", function()
	local ns, stub = Load({ cap = 5 })
	local ah = Ah(ns, stub)
	ns.AHPanel.RunBuild()
	ns.AHBuy.state.phase = "confirm"
	local ok, why = ns.AHBuy.SweepStart({ HIDE })
	eq(ok, false); eq(why, "Finish or cancel the purchase first"); eq(#ah.searches, 0)
	ns.AHBuy.state.phase = "idle"
	ns.AHPanel.RunRefresh()
	eq(ns.Market.SweepRunning(), true)
	local clicked, w = ns.AHBuy.Click()
	eq(clicked, false); eq(w, "A price refresh is running: stop it first")
	-- picking a line ends it
	ns.AHBuy.Pick({ kind = "basket", itemID = HIDE, need = 1 })
	eq(ns.Market.SweepRunning(), false)
end)

it("Refresh: when the run ends the plan is built again with the new prices", function()
	local ns, stub = Load({ cap = 5 })
	local ah = Ah(ns, stub)
	local first = ns.AHPanel.RunBuild()
	ns.AHPanel.RunRefresh()
	for _, id in ipairs(ah.searches) do Answer(stub, id, id ~= BELT) end
	for _ = 1, #first.search do
		stub.RunTimers()
		local last = ah.searches[#ah.searches]
		if ns.Market.SweepRunning() and last then Answer(stub, last, last ~= BELT) end
	end
	assert(ns.AHPanel.runPlan ~= first, "a new plan after the run")
end)

---------------------------------------------------------------------------------------- row heights (#397)

it("Panel rows (#397): Stack puts each string under the one above, as tall as its wrapped text", function()
	local host = CreateFrame("Frame")
	local function Str(text, width)
		local fs = host:CreateFontString()
		fs:SetWidth(width); fs:SetText(text)
		return fs
	end
	local ns, stub = Load({ cap = 5 })
	local P = Panel(ns, stub)
	local short, long = Str("one line", 316), Str(("word "):rep(120), 316) -- 600 chars = 4 lines at 6 per char over 316
	local third = Str("last", 316)
	assert(long:GetStringHeight() > short:GetStringHeight() * 2, "the stub wraps the long text")
	local y = P.Stack({ short, long, third }, 12, -100)
	local function top(fs) return fs.points[1][5] end
	eq(top(short), -100)
	eq(top(long), -100 - short:GetStringHeight() - 1)
	eq(top(third), top(long) - long:GetStringHeight() - 1)
	eq(y, top(third) - third:GetStringHeight() - 1)
end)

it("Panel rows (#397): a long wrapped line makes the plan line, the Post entry and the section below taller", function()
	local ns, stub = Load({ cap = 5 })
	local P = Panel(ns, stub)
	P.RunState().open = true
	P.RunBuild()
	local base = P.panel.height
	local source = P.RunLineSource
	P.RunLineSource = function() return ("long text "):rep(80) end
	P.Update()
	assert(P.panel.height > base + 24, "the plan lines grew with their text: " .. base .. " -> " .. P.panel.height)
	P.RunLineSource = source
	P.Update()
	eq(P.panel.height, base, "and shrink back")
	-- the Post list: lines of the run's AH items
	local before = P.panel.height
	local pl = P.PostSource
	P.PostLines = function() return { { itemID = BELT, postNow = 2, bags = 3, listed = 0, batch = 2, price = 100, sold = 0, demandText = "" } } end
	ns.Auctions.RunPostLines = P.PostLines
	P.Update()
	local one = P.panel.height
	assert(one > before, "a Post entry adds height")
	P.PostSource = function() return ("batch: about half a day's sales "):rep(20) end
	P.Update()
	assert(P.panel.height > one + 24, "a long batch line pushes the rest down")
	P.PostSource = pl
end)
