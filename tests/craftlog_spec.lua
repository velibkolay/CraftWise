-- Craft log (#205): every craft counted per character, recipe and day from the skill-up recorder's own
-- craft detection; 90 days of daily buckets, older days folded; one-time seed from skillups; the counts
-- the Make tooltip and the Crafted page show. Invented recipes only.
local R_BOOTS, R_CLAMS = 2149, 2150

local function T(y, m, d, h)
	return os.time({ year = y, month = m, day = d, hour = h or 12 })
end

local function setup(saved)
	local ns, stub = LoadAddon({ savedDB = saved })
	stub.profession = { id = 165, name = "Leatherworking", skill = 50, max = 75, recipes = {
		[R_BOOTS] = { info = { name = "Handstitched Leather Boots", learned = true, relativeDifficulty = 1 }, schematic = stub.Schematic({ { 2318, 2 } }, 2302) },
		[R_CLAMS] = { info = { name = "Deviled Clams", learned = true, relativeDifficulty = 1 }, schematic = stub.Schematic({ { 2318, 1 } }, 2303) },
	} }
	stub.Fire("TRADE_SKILL_SHOW")
	stub.Fire("SKILL_LINES_CHANGED")
	stub.names.player, stub.realm = "Velikopter", "TestRealm"
	return ns, stub
end

local function craft(stub, id)
	stub.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", id)
end

it("day numbers count calendar days, across months, years and leap days", function()
	local ns = setup()
	local D = ns.CraftLog.DayNumber
	eq(D(19700101), 0)
	eq(D(20260301) - D(20260228), 1)
	eq(D(20240301) - D(20240228), 2) -- leap year
	eq(D(20270101) - D(20261231), 1)
	eq(D(20261115) - D(20260817), 90)
end)

it("every craft is counted in today's bucket: one table write, also without a skill-up", function()
	local ns, stub = setup()
	local now = T(2026, 11, 15)
	time = function() return now end
	craft(stub, R_BOOTS); craft(stub, R_BOOTS); craft(stub, R_CLAMS)
	local key = ns.CharKey()
	eq(key, "TestRealm-Velikopter")
	local day = ns.db.crafted.chars[key][R_BOOTS].days[20261115]
	eq(day[1], 2)
	eq(ns.db.crafted.chars[key][R_CLAMS].days[20261115][1], 1)
	eq(next(ns.db.skillups), nil, "the skill-up record is untouched until a craft settles")
	local c = ns.CraftLog.Counts(R_BOOTS, now)
	eq(c.today, 2); eq(c.week, 2); eq(c.total, 2)
end)

it("items made: crafts times an exact yield; a yield range adds crafts only", function()
	local ns, stub = setup()
	time = function() return T(2026, 11, 15) end
	ns.charDB.professions[165].recipes[R_BOOTS].output = { itemID = 2302, quantity = 3 }
	ns.charDB.professions[165].recipes[R_CLAMS].output = { itemID = 2303, quantity = 1.5 }
	craft(stub, R_BOOTS); craft(stub, R_BOOTS); craft(stub, R_CLAMS)
	eq(ns.CraftLog.Counts(R_BOOTS).items, 6)
	local clams = ns.CraftLog.Counts(R_CLAMS)
	eq(clams.total, 1); eq(clams.items, 0)
end)

it("today and the last 7 days: today and the six days before count, the eighth day does not", function()
	local ns, stub = setup()
	local key = ns.CharKey()
	ns.db.crafted = { seeded = true, before = {}, chars = { [key] = { [R_BOOTS] = { days = {
		[20261115] = { 5, 5 }, [20261109] = { 3, 3 }, [20261108] = { 7, 7 }, [20261001] = { 11, 11 } } } } } }
	local c = ns.CraftLog.Counts(R_BOOTS, T(2026, 11, 15))
	eq(c.today, 5); eq(c.week, 8); eq(c.total, 26)
	eq(c.chars[1].today, 5); eq(c.chars[1].week, 8); eq(c.chars[1].total, 26)
end)

it("counts are split per character, the larger total first", function()
	local ns = setup()
	ns.db.crafted = { seeded = true, before = {}, chars = {
		["TestRealm-Alt Mage"] = { [R_BOOTS] = { days = { [20261115] = { 2, 2 } } } },
		["TestRealm-Main Tanner"] = { [R_BOOTS] = { days = { [20261115] = { 1, 1 }, [20261110] = { 9, 9 } } } },
	} }
	local c = ns.CraftLog.Counts(R_BOOTS, T(2026, 11, 15))
	eq(#c.chars, 2)
	eq(c.chars[1].key, "TestRealm-Main Tanner"); eq(c.chars[1].total, 10); eq(c.chars[1].week, 10); eq(c.chars[1].today, 1)
	eq(c.chars[2].key, "TestRealm-Alt Mage"); eq(c.chars[2].total, 2)
	eq(c.total, 12); eq(c.today, 3)
	eq(ns.CraftLog.CharLabel("TestRealm-Main Tanner"), "Main Tanner")
end)

it("the 90-day fold: day 89 stays, day 90 and older go into the per-recipe earlier total", function()
	local ns = setup()
	local key = ns.CharKey()
	ns.db.crafted = { seeded = true, before = {}, chars = { [key] = { [R_BOOTS] = { days = {
		[20261115] = { 1, 1 }, [20260818] = { 4, 8 }, [20260817] = { 10, 20 }, [20260101] = { 100, 200 } } } } } }
	eq(ns.CraftLog.Fold(T(2026, 11, 15)), 2)
	local entry = ns.db.crafted.chars[key][R_BOOTS]
	eq(entry.days[20260817], nil); eq(entry.days[20260101], nil)
	eq(entry.days[20260818][1], 4); eq(entry.days[20261115][1], 1)
	eq(entry.earlier[1], 110); eq(entry.earlier[2], 220)
	eq(ns.CraftLog.Fold(T(2026, 11, 15)), 0, "folding again changes nothing")
	local c = ns.CraftLog.Counts(R_BOOTS, T(2026, 11, 15))
	eq(c.total, 115); eq(c.items, 229); eq(c.earlier, 110)
	local lines = ns.CraftLog.Lines(R_BOOTS, T(2026, 11, 15))
	eq(lines.earlier, "Older than 90 days: 110")
end)

it("entering the world folds old days", function()
	local ns, stub = setup()
	time = function() return T(2026, 11, 15) end
	ns.db.crafted = { seeded = true, before = {}, chars = { [ns.CharKey()] = { [R_BOOTS] = { days = { [20260101] = { 5, 5 } } } } } }
	stub.Fire("PLAYER_ENTERING_WORLD")
	eq(ns.db.crafted.chars[ns.CharKey()][R_BOOTS].earlier[1], 5)
end)

it("the seed: skillups become an undated bucket once, with no character", function()
	local ns, stub = setup({ skillups = { [R_CLAMS] = { [50] = { n = 1000, ups = 3 }, [60] = { n = 532, ups = 0 } }, [R_BOOTS] = { [10] = { n = 2, ups = 2 } } } })
	time = function() return T(2026, 11, 15) end
	craft(stub, R_CLAMS) -- the first use seeds
	eq(ns.db.crafted.seeded, true)
	eq(ns.db.crafted.before[R_CLAMS], 1532); eq(ns.db.crafted.before[R_BOOTS], 2)
	eq(ns.CraftLog.Counts(R_CLAMS).before, 1532)
	local c = ns.CraftLog.Counts(R_CLAMS)
	eq(c.total, 1, "dated crafts only")
	-- the craft's own skill-up record arrives later and must not be counted again
	stub.now = stub.now + 3
	ns.SettleCrafts()
	eq(ns.SkillUpStats(R_CLAMS), 1533)
	ns.db.crafted.seeded = true
	ns.CraftLog.Store()
	eq(ns.db.crafted.before[R_CLAMS], 1532, "seeded once")
	local lines = ns.CraftLog.Lines(R_CLAMS)
	eq(lines.total, 1533)
	eq(lines.headline, "Crafted 1,533 \194\183 today 1")
	eq(lines.before, "Before the log (undated): 1,532")
end)

it("the tooltip and row lines: nothing for a recipe never crafted, a headline and a line per character", function()
	local ns = setup()
	eq(ns.CraftLog.Lines(R_BOOTS), nil)
	ns.db.crafted = { seeded = true, before = { [R_BOOTS] = 1500 }, chars = { ["TestRealm-Main Tanner"] = { [R_BOOTS] = { days = { [20261115] = { 120, 120 }, [20261110] = { 32, 32 } } } } } }
	local lines = ns.CraftLog.Lines(R_BOOTS, T(2026, 11, 15))
	eq(lines.headline, "Crafted 1,652 \194\183 today 120")
	eq(lines.chars[1].name, "Main Tanner")
	eq(lines.chars[1].text, "today 120 \194\183 7 days 152 \194\183 total 152")
	eq(lines.before, "Before the log (undated): 1,500")
	eq(ns.CraftLog.Format(1234567), "1,234,567"); eq(ns.CraftLog.Format(12), "12")
end)

it("Make tooltip: Crafted lines and the profit at today's prices, labelled approximate", function()
	local ns = setup()
	time = function() return T(2026, 11, 15) end
	ns.db.crafted = { seeded = true, before = { [R_BOOTS] = 10 }, chars = { [ns.CharKey()] = { [R_BOOTS] = { days = { [ns.CraftLog.Today()] = { 2, 2 } } } } } }
	local shown = {}
	GameTooltip = GameTooltip or {}
	GameTooltip.AddLine = function(_, text) shown[#shown + 1] = tostring(text) end
	GameTooltip.AddDoubleLine = function(_, l, r) shown[#shown + 1] = tostring(l) .. " | " .. tostring(r) end
	ns.Main.Make.AddCraftLog({ recipeID = R_BOOTS, profit = 500 })
	local text = table.concat(shown, "\n")
	assert(text:find("Crafted", 1, true), text)
	assert(text:find("today 2", 1, true), text)
	assert(text:find("counted before the log", 1, true), text)
	assert(text:find("at today's prices", 1, true), text)
	assert(text:find("(approx.)", 1, true), text)
end)

it("Make › Crafted lists logged recipes by crafts today, then 7 days, with undated crafts in the total", function()
	local ns, stub = setup()
	time = function() return T(2026, 11, 15) end
	local key = ns.CharKey()
	ns.db.crafted = { seeded = true, before = { [R_CLAMS] = 1500 }, chars = { [key] = {
		[R_BOOTS] = { days = { [20261115] = { 3, 3 }, [20261112] = { 4, 4 } } },
		[R_CLAMS] = { days = { [20261113] = { 9, 9 } } } } } }
	local rows = ns.Main.CraftedPage.Rows(T(2026, 11, 15))
	eq(#rows, 2)
	eq(rows[1].recipeID, R_BOOTS); eq(rows[1].today, 3); eq(rows[1].week, 7); eq(rows[1].total, 7)
	eq(rows[2].recipeID, R_CLAMS); eq(rows[2].today, 0); eq(rows[2].total, 1509); eq(rows[2].before, 1500)
	eq(rows[2].view.cells.total, "1,509"); eq(rows[1].view.cells.today, "3")
	local model = ns.Main.CraftedPage.Model()
	eq(#model.rows, 2)
	ns.Main.Open("crafted")
	assert(ns.Main.Frame(), "page opens")
end)

it("Make › Crafted with an empty log says so", function()
	local ns = setup()
	local model = ns.Main.CraftedPage.Model()
	eq(#model.rows, 0)
	eq(model.hero.name, "—")
end)

-- Make › Crafted: search, filters, sorting (#205 follow-up)
local function seedLog(ns)
	time = function() return T(2026, 11, 15) end
	ns.db.crafted = { seeded = true, before = { [R_CLAMS] = 1500, [R_BOOTS] = 20 }, chars = {
		["TestRealm-Main Tanner"] = { [R_BOOTS] = { days = { [20261110] = { 5, 5 } } }, [R_CLAMS] = { days = { [20261115] = { 2, 2 } } } },
		["TestRealm-Alt Mage"] = { [R_BOOTS] = { days = { [20261115] = { 3, 3 } } } } } }
end

it("Crafted default order: today, then 7 days, then total (undated included), then name", function()
	local ns = setup()
	seedLog(ns)
	local P = ns.Main.CraftedPage
	local rows = P.SortRows(P.Rows(T(2026, 11, 15)), "today", true)
	local names = {}
	for _, r in ipairs(rows) do names[#names + 1] = r.recipeID .. ":" .. r.today .. "/" .. r.week .. "/" .. r.total end
	eq(table.concat(names, " "), R_BOOTS .. ":3/8/28 " .. R_CLAMS .. ":2/2/1502")
end)

it("Crafted with nothing today or this week falls back to the total, not the alphabet", function()
	local ns = setup()
	time = function() return T(2026, 11, 15) end
	local list = { { name = "Barbaric Harness", recipeID = 1, today = 0, week = 0, total = 25 },
		{ name = "Goblin Deviled Clams", recipeID = 2, today = 0, week = 0, total = 1532 },
		{ name = "Alpha", recipeID = 3, today = 0, week = 0, total = 25 } }
	ns.Main.CraftedPage.SortRows(list, "today", true)
	eq(list[1].name, "Goblin Deviled Clams"); eq(list[2].name, "Alpha"); eq(list[3].name, "Barbaric Harness")
end)

it("Crafted sorting by a column: desc then asc, ties by the default order; by name A-Z", function()
	local ns = setup()
	local P = ns.Main.CraftedPage
	local function ids(rows) local t = {} for _, r in ipairs(rows) do t[#t + 1] = r.name end return table.concat(t, ",") end
	local rows = { { name = "B", recipeID = 1, today = 1, week = 5, total = 50 }, { name = "A", recipeID = 2, today = 1, week = 9, total = 10 },
		{ name = "C", recipeID = 3, today = 0, week = 5, total = 70 } }
	eq(ids(P.SortRows(rows, "total", true)), "C,B,A")
	eq(ids(P.SortRows(rows, "total", false)), "A,B,C")
	eq(ids(P.SortRows(rows, "week", true)), "A,B,C", "week 9 first, then the tie at 5 goes to the larger today")
	eq(ids(P.SortRows(rows, "name", false)), "A,B,C")
	eq(ids(P.SortRows(rows, "name", true)), "C,B,A")
end)

it("Crafted header clicks sort and flip, and the shell remembers the choice", function()
	local ns = setup()
	local M = ns.Main
	local page = M.Page("crafted")
	for _, col in ipairs(page.columns) do
		if col.key ~= "icon" then eq(col.sort, true, col.key) end
	end
	local key, desc = M.Sort(page)
	eq(key, "today"); eq(desc, true)
	M.ClickSort(page, "total")
	key, desc = M.Sort(page)
	eq(key, "total"); eq(desc, true)
	M.ClickSort(page, "total")
	key, desc = M.Sort(page)
	eq(key, "total"); eq(desc, false)
	eq(M.UI().sort.crafted.key, "total"); eq(M.UI().sort.crafted.desc, false)
	M.state.sort.crafted = nil -- a new session reads the saved choice
	key, desc = M.Sort(page)
	eq(key, "total"); eq(desc, false)
end)

it("Crafted search filters by recipe name through Make's filter box", function()
	local ns = setup()
	seedLog(ns)
	local P = ns.Main.CraftedPage
	ns.Main.Make.state.query = ""
	eq(#P.Rows(T(2026, 11, 15)), 2)
	ns.Main.Make.state.query = "BOOT"
	local rows = P.Rows(T(2026, 11, 15))
	eq(#rows, 1); eq(rows[1].recipeID, R_BOOTS)
	ns.Main.Make.state.query = "zzz"
	eq(#P.Rows(T(2026, 11, 15)), 0)
	ns.Main.Make.state.query = ""
end)

it("Crafted character filter: one character's dated crafts only, undated crafts drop out", function()
	local ns = setup()
	seedLog(ns)
	local P = ns.Main.CraftedPage
	local rows = P.SortRows(P.Rows(T(2026, 11, 15), { char = "TestRealm-Alt Mage" }), "today", true)
	eq(#rows, 1); eq(rows[1].recipeID, R_BOOTS); eq(rows[1].total, 3); eq(rows[1].before, 0)
	rows = P.SortRows(P.Rows(T(2026, 11, 15), { char = "TestRealm-Main Tanner" }), "today", true)
	eq(#rows, 2); eq(rows[1].recipeID, R_CLAMS); eq(rows[1].total, 2); eq(rows[2].total, 5)
	eq(table.concat(ns.CraftLog.Characters(), ","), "TestRealm-Alt Mage,TestRealm-Main Tanner")
	rows = P.Rows(T(2026, 11, 15), {})
	eq(#rows, 2, "all characters")
end)

it("Crafted profession filter: by the recipe's skill line", function()
	local ns = setup()
	seedLog(ns)
	local P = ns.Main.CraftedPage
	local ok = ns.RecipeLine(R_BOOTS)
	eq(ok, 165)
	eq(#P.Rows(T(2026, 11, 15), { line = 165 }), 2)
	eq(#P.Rows(T(2026, 11, 15), { line = 171 }), 0)
	local lines = P.Lines()
	eq(#lines, 1); eq(lines[1][1], 165)
end)

it("Crafted page draws its filter tools and the chips choose all or one", function()
	local ns = setup()
	seedLog(ns)
	local M = ns.Main
	M.Open("crafted")
	local P = M.CraftedPage
	P.SetChar("TestRealm-Alt Mage")
	eq(P.state.char, "TestRealm-Alt Mage")
	P.SetChar("all")
	eq(P.state.char, nil)
	P.SetLine(165)
	eq(P.state.line, 165)
	P.SetLine("all")
	eq(P.state.line, nil)
end)

it("the craft log's lines go through the locale table", function()
	local ns = setup()
	seedLog(ns)
	ns.L["Crafted %s \194\183 today %s"] = "Hergestellt %s \194\183 heute %s"
	ns.L["Before the log (undated): %s"] = "Vor dem Log (ohne Datum): %s"
	local lines = ns.CraftLog.Lines(R_BOOTS, T(2026, 11, 15))
	eq(lines.headline, "Hergestellt 28 \194\183 heute 3")
	eq(lines.before, "Vor dem Log (ohne Datum): 20")
end)

-- Craft speed (#209)
local function craftAt(stub, id, t)
	stub.now = t
	craft(stub, id)
end

local function entryOf(ns, id)
	return ns.db.crafted.chars[ns.CharKey()][id]
end

it("speed: the first craft of a run measures nothing, then each gap up to 30 s counts", function()
	local ns, stub = setup()
	time = function() return T(2026, 11, 15) end
	craftAt(stub, R_BOOTS, 100)
	eq(entryOf(ns, R_BOOTS).speed, nil, "first craft: no gap")
	craftAt(stub, R_BOOTS, 102.5)
	craftAt(stub, R_BOOTS, 105)
	local s = entryOf(ns, R_BOOTS).speed
	eq(s.n, 2); eq(s.sum, 5); eq(s.gaps[1], 2.5); eq(s.gaps[2], 2.5)
end)

it("speed: a gap over 30 s is a break and starts a new run; exactly 30 s counts", function()
	local ns, stub = setup()
	time = function() return T(2026, 11, 15) end
	craftAt(stub, R_BOOTS, 100)
	craftAt(stub, R_BOOTS, 130) -- 30 s: counts
	craftAt(stub, R_BOOTS, 200) -- 70 s: break
	craftAt(stub, R_BOOTS, 202) -- 2 s: counts, measured from the craft after the break
	local s = entryOf(ns, R_BOOTS).speed
	eq(s.n, 2); eq(s.sum, 32)
end)

it("speed: gaps are per recipe, another recipe in between does not end the run of the first", function()
	local ns, stub = setup()
	time = function() return T(2026, 11, 15) end
	craftAt(stub, R_BOOTS, 100)
	craftAt(stub, R_CLAMS, 101)
	craftAt(stub, R_BOOTS, 104)
	eq(entryOf(ns, R_BOOTS).speed.n, 1); eq(entryOf(ns, R_BOOTS).speed.sum, 4)
	eq(entryOf(ns, R_CLAMS).speed, nil)
end)

it("speed: the median of an odd and an even count, without changing the list", function()
	local ns = setup()
	local list = { 5, 1, 3 }
	eq(ns.CraftLog.Median(list), 3); eq(list[1], 5)
	eq(ns.CraftLog.Median({ 4, 1, 2, 3 }), 2.5)
	eq(ns.CraftLog.Median({}), nil)
end)

it("speed: nothing shows below 5 gaps; from 5 on the median, crafts per hour and the count", function()
	local ns, stub = setup()
	time = function() return T(2026, 11, 15) end
	local t = 100
	craftAt(stub, R_BOOTS, t)
	for i = 1, 4 do t = t + 2; craftAt(stub, R_BOOTS, t) end
	eq(entryOf(ns, R_BOOTS).speed.n, 4)
	eq(ns.CraftLog.Speed(R_BOOTS), nil, "4 gaps")
	eq(ns.CraftLog.Lines(R_BOOTS).speed, nil)
	t = t + 2; craftAt(stub, R_BOOTS, t)
	local sp = ns.CraftLog.Speed(R_BOOTS)
	eq(sp.n, 5); eq(sp.sec, 2); eq(sp.perHour, 1800); eq(sp.mean, 2)
	eq(ns.CraftLog.Lines(R_BOOTS).speed.n, 5)
end)

it("speed: the median ignores a few slow gaps; the ring keeps the last 50 and the count keeps counting", function()
	local ns, stub = setup()
	time = function() return T(2026, 11, 15) end
	local t = 100
	craftAt(stub, R_BOOTS, t)
	local gaps = { 2, 2, 2, 2, 2, 20, 25 }
	for _, g in ipairs(gaps) do t = t + g; craftAt(stub, R_BOOTS, t) end
	eq(ns.CraftLog.Speed(R_BOOTS).sec, 2)
	for i = 1, 60 do t = t + 3; craftAt(stub, R_BOOTS, t) end
	local s = entryOf(ns, R_BOOTS).speed
	eq(#s.gaps, 50, "bounded")
	eq(s.n, 67)
	eq(ns.CraftLog.Speed(R_BOOTS).sec, 3, "the last 50 are all 3 s")
end)

it("speed: profit per hour is crafts per hour times the profit per craft, a dash without a profit", function()
	local ns = setup()
	local sp = { sec = 2, perHour = 1800, n = 5 }
	eq(ns.CraftLog.ProfitPerHour(sp, 150), 270000)
	eq(ns.CraftLog.ProfitPerHour(sp, -10), -18000)
	eq(ns.CraftLog.ProfitPerHour(sp, nil), nil)
	eq(ns.CraftLog.ProfitPerHour(nil, 150), nil)
	eq(ns.CraftLog.FormatSeconds(2), "2"); eq(ns.CraftLog.FormatSeconds(2.46), "2.5")
end)

it("speed: the speed pools every character's gaps of a recipe", function()
	local ns = setup()
	ns.db.crafted = { seeded = true, before = {}, chars = {
		["R-A One"] = { [R_BOOTS] = { days = {}, speed = { n = 3, sum = 6, gaps = { 2, 2, 2 } } } },
		["R-B Two"] = { [R_BOOTS] = { days = {}, speed = { n = 3, sum = 12, gaps = { 4, 4, 4 } } } } } }
	local sp = ns.CraftLog.Speed(R_BOOTS)
	eq(sp.n, 6); eq(sp.sec, 3); eq(sp.mean, 3)
end)

it("Crafted page: speed columns are sortable, rows without a speed sort last either way", function()
	local ns, stub = setup()
	time = function() return T(2026, 11, 15) end
	local P = ns.Main.CraftedPage
	local rows = { { name = "A", recipeID = 1, today = 0, week = 0, total = 5 }, { name = "B", recipeID = 2, today = 0, week = 0, total = 9, sec = 3, perHour = 1200, profitHour = 500 },
		{ name = "C", recipeID = 3, today = 0, week = 0, total = 7, sec = 2, perHour = 1800, profitHour = 900 } }
	local function ids(r) local t = {} for _, x in ipairs(r) do t[#t + 1] = x.name end return table.concat(t, ",") end
	eq(ids(P.SortRows(rows, "profitHour", true)), "C,B,A")
	eq(ids(P.SortRows(rows, "profitHour", false)), "B,C,A")
	eq(ids(P.SortRows(rows, "sec", false)), "C,B,A")
	for _, key in ipairs({ "sec", "perHour", "profitHour" }) do
		local found
		for _, col in ipairs(P.COLUMNS) do if col.key == key then found = col.sort end end
		eq(found, true, key)
	end
end)

it("Crafted page: a recipe with a measured speed shows sec/craft, crafts/h and profit/h, others a dash", function()
	local ns, stub = setup()
	time = function() return T(2026, 11, 15) end
	local key = ns.CharKey()
	ns.db.crafted = { seeded = true, before = {}, chars = { [key] = {
		[R_BOOTS] = { days = { [20261115] = { 6, 6 } }, speed = { n = 5, sum = 10, gaps = { 2, 2, 2, 2, 2 } } },
		[R_CLAMS] = { days = { [20261115] = { 1, 1 } } } } } }
	ns.Main.Make.state.query = ""
	local rows = ns.Main.CraftedPage.Rows(T(2026, 11, 15), {})
	local byId = {}
	for _, r in ipairs(rows) do byId[r.recipeID] = r end
	eq(byId[R_BOOTS].view.cells.sec, "2"); eq(byId[R_BOOTS].view.cells.perHour, "1,800")
	eq(byId[R_BOOTS].sec, 2)
	eq(byId[R_CLAMS].view.cells.sec, ns.Main.DASH); eq(byId[R_CLAMS].profitHour, nil)
	ns.Main.Open("crafted")
end)

it("speed: the Make tooltip shows the figures and 'measured over N crafts', a dash without a profit", function()
	local ns = setup()
	local shown = {}
	GameTooltip = GameTooltip or {}
	GameTooltip.AddLine = function(_, text) shown[#shown + 1] = tostring(text) end
	GameTooltip.AddDoubleLine = function(_, l, r) shown[#shown + 1] = tostring(l) .. " | " .. tostring(r) end
	ns.Main.Make.AddSpeedLines(nil, 100)
	eq(#shown, 0, "nothing without a speed")
	ns.Main.Make.AddSpeedLines({ sec = 2, perHour = 1800, n = 7 }, nil)
	local text = table.concat(shown, "\n")
	assert(text:find("2 sec per craft", 1, true) and text:find("1,800 per hour", 1, true), text)
	assert(text:find("measured over 7 crafts", 1, true), text)
	assert(text:find("at today's prices | " .. ns.Main.DASH, 1, true), text)
end)
