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
	assert(text:find("Profit of all crafts at today's AH prices", 1, true), text)
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
	eq(ids(P.SortRows(rows, "speed", false)), "B,C,A") -- by crafts per hour, the unmeasured one last
	for _, key in ipairs({ "speed", "profitHour" }) do
		local found
		for _, col in ipairs(P.COLUMNS) do if col.key == key then found = col.sort end end
		eq(found, true, key)
	end
end)

it("Crafted page: a recipe with a measured speed shows its speed and profit/h, others a dash", function()
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
	eq(byId[R_BOOTS].view.cells.speed, "2 s · 1,800/h")
	eq(byId[R_BOOTS].sec, 2)
	eq(byId[R_CLAMS].view.cells.speed, ns.Main.DASH); eq(byId[R_CLAMS].profitHour, nil)
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
	assert(text:find("Profit per hour at today's AH prices | " .. ns.Main.DASH, 1, true), text)
end)

it("profit per hour follows the Profit view's cost basis: paid cost or today's AH, labelled, partial flagged", function()
	local ns = setup()
	time = function() return T(2026, 11, 15) end
	ns.GetBuyPrice = function() return { copper = 100, source = "auction", label = "AH" } end
	ns.GetPaidBuyPrice = function() return { copper = 40, source = "paid", label = "paid cost, 1 of 2 units", paidPartial = true, paidNote = "x", noCraft = true } end
	ns.GetSellValue = function() return { copper = 1000, source = "auction", label = "AH" } end
	ns.db.crafted = { seeded = true, before = {}, chars = { [ns.CharKey()] = {
		[R_BOOTS] = { days = { [20261115] = { 6, 6 } }, speed = { n = 5, sum = 10, gaps = { 2, 2, 2, 2, 2 } } } } } }
	ns.Main.Make.state.query = ""
	local P = ns.Main.CraftedPage
	local function row()
		for _, r in ipairs(P.Rows(T(2026, 11, 15), {})) do
			if r.recipeID == R_BOOTS then return r end
		end
	end
	ns.db.settings.costBasis.profit = "ah"
	local ah = row()
	assert(ah.profit, "the row has a profit at AH prices")
	eq(ah.profitHour, 1800 * ah.profit)
	eq(ah.basis.label, "at today's AH prices"); eq(ah.basis.partial, false)
	ns.db.settings.costBasis.profit = "paid"
	local paid = row()
	assert(paid.profit > ah.profit, "cheaper paid reagents: more profit per craft")
	eq(paid.profitHour, 1800 * paid.profit)
	assert(paid.profitHour > ah.profitHour, "profit per hour changes with the basis")
	eq(paid.basis.label, "at paid cost"); eq(paid.basis.partial, true)
	assert(paid.view.cells.profitHour:find("*", 1, true), "partial paid cost is starred")
	assert(paid.view.tips.profitHour[1]:find("at paid cost", 1, true))
	eq(ns.Main.Make.ProfitBasis().label, "at paid cost")
end)

-- Profit at craft time and payback (#215)
local function profitSetup(profit)
	local ns, stub = setup()
	time = function() return T(2026, 11, 15) end
	local calls = 0
	ns.CraftLog.ProfitNow = function() calls = calls + 1; return profit end
	return ns, stub, function() return calls end
end

it("profit is recorded per craft at craft time, in copper, with how many crafts had one", function()
	local ns, stub = profitSetup(150.4)
	craft(stub, R_BOOTS); craft(stub, R_BOOTS)
	local b = entryOf(ns, R_BOOTS).days[20261115]
	eq(b[1], 2); eq(b[3], 300); eq(b[4], 2)
	ns.CraftLog.ProfitNow = function() return 999 end -- later prices don't rewrite the past
	eq(entryOf(ns, R_BOOTS).days[20261115][3], 300)
	craft(stub, R_BOOTS)
	b = entryOf(ns, R_BOOTS).days[20261115]
	eq(b[1], 3); eq(b[3], 1299); eq(b[4], 3)
end)

it("a craft without a known profit adds to the crafts only; losses count", function()
	local ns, stub = profitSetup(nil)
	craft(stub, R_BOOTS)
	ns.CraftLog.ProfitNow = function() return -40 end
	craft(stub, R_BOOTS)
	local b = entryOf(ns, R_BOOTS).days[20261115]
	eq(b[1], 2); eq(b[3], -40); eq(b[4], 1)
	local c = ns.CraftLog.Counts(R_BOOTS, T(2026, 11, 15))
	eq(c.profit.total, -40); eq(c.profit.known, 1); eq(c.total, 2)
end)

it("ProfitNow is Make's profit: it follows the prices at the time, and is looked up once a minute", function()
	local ns, stub = setup()
	time = function() return T(2026, 11, 15) end
	stub.now = 1000
	ns.db.vendor[2318] = 5
	local sale = 100
	local lookups = 0
	ns.GetSellValue = function() lookups = lookups + 1; return { copper = sale, source = "auction", label = "AH" } end
	local recipe = ns.charDB.professions[165].recipes[R_BOOTS]
	eq(ns.CraftLog.ProfitNow(R_BOOTS, recipe, 1000), 90) -- 100 sale minus 2 x 5 reagents
	sale = 500
	eq(ns.CraftLog.ProfitNow(R_BOOTS, recipe, 1010), 90, "within the minute: the same lookup")
	eq(lookups, 1)
	eq(ns.CraftLog.ProfitNow(R_BOOTS, recipe, 1061), 490)
	-- a craft through the real detection writes it
	craftAt(stub, R_BOOTS, 1200)
	eq(entryOf(ns, R_BOOTS).days[20261115][3], 490); eq(entryOf(ns, R_BOOTS).days[20261115][4], 1)
	-- no price: nothing
	ns.GetSellValue = function() return nil end
	eq(ns.CraftLog.ProfitNow(R_BOOTS, recipe, 2000), nil)
end)

it("the 90-day fold carries profit and known into earlier", function()
	local ns = setup()
	ns.db.crafted = { seeded = true, before = {}, chars = { [ns.CharKey()] = { [R_BOOTS] = { days = {
		[20261115] = { 1, 1, 10, 1 }, [20260101] = { 4, 4, 100, 3 }, [20260102] = { 2, 2 } } } } } }
	eq(ns.CraftLog.Fold(T(2026, 11, 15)), 2)
	local e = entryOf(ns, R_BOOTS)
	eq(e.earlier[1], 6); eq(e.earlier[3], 100); eq(e.earlier[4], 3)
	local c = ns.CraftLog.Counts(R_BOOTS, T(2026, 11, 15))
	eq(c.profit.total, 110); eq(c.profit.known, 4); eq(c.total, 7)
end)

it("profit today, 7 days and total per character; older buckets without profit count as unknown", function()
	local ns = setup()
	ns.db.crafted = { seeded = true, before = { [R_BOOTS] = 50 }, chars = {
		["R-Main Tanner"] = { [R_BOOTS] = { days = { [20261115] = { 3, 3, 300, 3 }, [20261110] = { 2, 2, 100, 2 }, [20261001] = { 5, 5, 500, 4 }, [20260901] = { 7, 7 } } } },
		["R-Alt Mage"] = { [R_BOOTS] = { days = { [20261115] = { 1, 1, -20, 1 } } } } } }
	local now = T(2026, 11, 15)
	local c = ns.CraftLog.Counts(R_BOOTS, now)
	eq(c.profit.today, 280); eq(c.profit.week, 380); eq(c.profit.total, 880)
	eq(c.profit.known, 10); eq(c.profit.knownToday, 4); eq(c.profit.knownWeek, 6)
	eq(c.chars[1].key, "R-Main Tanner"); eq(c.chars[1].profit.total, 900); eq(c.chars[2].profit.total, -20)
	local rows = ns.CraftLog.List(now)
	eq(rows[1].profitTotal, 880); eq(rows[1].known, 10); eq(rows[1].dated, 18); eq(rows[1].total, 68)
	local one = ns.CraftLog.List(now, "R-Alt Mage")
	eq(one[1].profitTotal, -20)
	local lines = ns.CraftLog.Lines(R_BOOTS, now)
	eq(lines.profit.total, 880); eq(lines.dated, 18); eq(lines.chars[1].profit.known, 9)
end)

it("Crafted columns: profit today / 7 days / total, estimated, starred when partial, a dash when unknown", function()
	local ns = setup()
	time = function() return T(2026, 11, 15) end
	ns.db.crafted = { seeded = true, before = { [R_CLAMS] = 100 }, chars = { [ns.CharKey()] = {
		[R_BOOTS] = { days = { [20261115] = { 4, 4, 400, 4 }, [20261105] = { 5, 5, 250, 2 } } },
		[R_CLAMS] = { days = { [20261115] = { 2, 2 } } } } } }
	ns.Main.Make.state.query = ""
	local P = ns.Main.CraftedPage
	local rows = P.Rows(T(2026, 11, 15), {})
	local by = {}
	for _, r in ipairs(rows) do by[r.recipeID] = r end
	eq(by[R_BOOTS].profitToday, 400); eq(by[R_BOOTS].profitWeek, 400); eq(by[R_BOOTS].profitTotal, 650)
	assert(not by[R_BOOTS].view.cells.profitToday:find("*", 1, true), "all of today's crafts are priced")
	assert(by[R_BOOTS].view.cells.profitTotal:find("*", 1, true), "6 of 9 crafts have a profit: starred")
	assert(by[R_BOOTS].view.tips.profitTotal[2]:find("known for 6 of 9 crafts", 1, true), by[R_BOOTS].view.tips.profitTotal[2])
	assert(by[R_BOOTS].view.tips.profitTotal[2]:find("Not money received", 1, true))
	eq(by[R_CLAMS].profitTotal, nil); eq(by[R_CLAMS].view.cells.profitTotal, ns.Main.DASH, "undated seed and unpriced: a dash")
	for _, key in ipairs({ "profitToday", "profitTotal" }) do
		local found
		for _, col in ipairs(P.COLUMNS) do if col.key == key then found = col.sort end end
		eq(found, true, key)
	end
	local sorted = P.SortRows({ by[R_CLAMS], by[R_BOOTS] }, "profitTotal", false)
	eq(sorted[1].recipeID, R_BOOTS, "no profit sorts last either way")
	local model = P.Model()
	eq(model.hero.figureLabel, "Estimated profit today")
	assert(model.hero.sub:find("profit 7 days", 1, true), model.hero.sub)
end)

it("recipe payback: from the ledger's latest purchase, else the recipe item's vendor price; nothing without a cost", function()
	local ns = setup()
	ns.SourceData = { [R_BOOTS] = { skill = 10, item = 7777 } }
	eq(ns.CraftLog.RecipeCost(R_BOOTS), nil)
	eq(ns.CraftLog.RecipeCost(R_CLAMS), nil, "no mapping, no guess")
	eq(ns.CraftLog.Payback(R_BOOTS, 100, 1), nil)
	ns.db.vendor[7777] = 500
	local cost, source = ns.CraftLog.RecipeCost(R_BOOTS)
	eq(cost, 500); eq(source, "vendor")
	ns.Ledger.Entries = function() return { { i = 7777, k = "vbuy", q = 1, m = 450, t = 100 }, { i = 7777, k = "ahbuy", q = 2, m = 1000, t = 200 },
		{ i = 7777, k = "vsell", q = 1, m = 9999, t = 300 } } end
	cost, source = ns.CraftLog.RecipeCost(R_BOOTS)
	eq(cost, 500); eq(source, "ledger", "the latest purchase, per unit: 1000 / 2")
	local p = ns.CraftLog.Payback(R_BOOTS, 320, 4)
	eq(p.paidBack, false); eq(p.togo, 180)
	p = ns.CraftLog.Payback(R_BOOTS, 500, 4)
	eq(p.paidBack, true); eq(p.togo, 0)
	p = ns.CraftLog.Payback(R_BOOTS, 0, 0)
	eq(p.known, false); eq(p.paidBack, false)
	local M = ns.Main.Make
	eq(M.PaybackText(ns.CraftLog.Payback(R_BOOTS, 320, 4)), "Recipe cost 5s: 1s 80c to go")
	eq(M.PaybackText(ns.CraftLog.Payback(R_BOOTS, 900, 4)), "Recipe cost 5s: paid back")
	eq(M.PaybackText(ns.CraftLog.Payback(R_BOOTS, 0, 0)), "Recipe cost 5s: no profit logged yet")
	eq(M.PaybackText(nil), nil)
end)

it("the tooltip shows the logged profit, the per-character split and the payback", function()
	local ns = setup()
	time = function() return T(2026, 11, 15) end
	ns.SourceData = { [R_BOOTS] = { skill = 10, item = 7777 } }
	ns.db.vendor[7777] = 500
	ns.db.crafted = { seeded = true, before = {}, chars = {
		["R-Main Tanner"] = { [R_BOOTS] = { days = { [20261115] = { 3, 3, 300, 3 } } } },
		["R-Alt Mage"] = { [R_BOOTS] = { days = { [20261115] = { 1, 1, 50, 1 } } } } } }
	local shown = {}
	GameTooltip = GameTooltip or {}
	GameTooltip.AddLine = function(_, text) shown[#shown + 1] = tostring(text) end
	GameTooltip.AddDoubleLine = function(_, l, r) shown[#shown + 1] = tostring(l) .. " | " .. tostring(r) end
	ns.Main.Make.AddProfitLines(ns.CraftLog.Lines(R_BOOTS))
	local text = table.concat(shown, "\n")
	assert(text:find("Profit at craft time (est.)", 1, true), text)
	assert(text:find("profit known for 4 of 4 crafts", 1, true), text)
	assert(text:find("Main Tanner", 1, true) and text:find("Alt Mage", 1, true), text)
	assert(text:find("Recipe cost 5s: 1s 50c to go", 1, true), text)
end)

-- Make › Crafted fits the window and the docked layout (#228)
local function fitSetup()
	local ns = setup()
	time = function() return T(2026, 11, 15) end
	ns.db.crafted = { seeded = true, before = { [R_CLAMS] = 1500 }, chars = { [ns.CharKey()] = {
		[R_BOOTS] = { days = { [20261115] = { 4, 4, 400, 4 }, [20261105] = { 5, 5, 250, 2 } }, speed = { n = 5, sum = 10, gaps = { 2, 2, 2, 2, 2 } } },
		[R_CLAMS] = { days = { [20261115] = { 2, 2 } } } } } }
	ns.Main.Make.state.query = ""
	return ns
end

it("Crafted window layout: the columns fit the default width, the recipe column keeps at least 180", function()
	local ns = fitSetup()
	local M, P = ns.Main, ns.Main.CraftedPage
	local m = M.WINDOW_METRICS
	local layout = M.ColumnLayout(P.COLUMNS, m.width, m.pad)
	local last = layout[#layout]
	assert(last.x + last.width <= m.width - m.pad, ("the last column ends at %d, the row at %d"):format(last.x + last.width, m.width - m.pad))
	for i = 2, #layout do
		assert(layout[i].x >= layout[i - 1].x + layout[i - 1].width, "columns don't overlap")
	end
	local name
	for i, col in ipairs(P.COLUMNS) do if col.key == "name" then name = layout[i].width end end
	assert(name >= P.MIN_NAME, "recipe column " .. tostring(name))
	eq(#P.COLUMNS, 9)
	-- Sec/craft and Crafts/h are one Speed column; Profit 7 days left the table
	local keys = {}
	for _, col in ipairs(P.COLUMNS) do keys[col.key] = true end
	eq(keys.speed, true); eq(keys.sec, nil); eq(keys.perHour, nil); eq(keys.profitWeek, nil)
end)

it("Crafted Speed column: 'sec · per hour', sorts by crafts per hour, a dash and last without a measurement", function()
	local ns = fitSetup()
	local P = ns.Main.CraftedPage
	local rows = P.Rows(T(2026, 11, 15), {})
	local by = {}
	for _, r in ipairs(rows) do by[r.recipeID] = r end
	eq(by[R_BOOTS].view.cells.speed, "2 s · 1,800/h"); eq(by[R_CLAMS].view.cells.speed, ns.Main.DASH)
	local a = { name = "A", recipeID = 1, today = 0, week = 0, total = 1, perHour = 900 }
	local b = { name = "B", recipeID = 2, today = 0, week = 0, total = 1, perHour = 1800 }
	local c = { name = "C", recipeID = 3, today = 0, week = 0, total = 1 }
	local function ids(r) local t = {} for _, x in ipairs(r) do t[#t + 1] = x.name end return table.concat(t, ",") end
	eq(ids(P.SortRows({ a, b, c }, "speed", true)), "B,A,C")
	eq(ids(P.SortRows({ a, b, c }, "speed", false)), "A,B,C")
	eq(ns.Main.Page("crafted").columns[6].key, "speed")
end)

it("Crafted docked layout: the hero line, the footer and the row lines stay short", function()
	local ns = fitSetup()
	local P = ns.Main.CraftedPage
	local M = ns.Main
	local ctx = { metrics = M.DOCKED_METRICS }
	local CHAR = 6 -- an estimate of a Caption character; the stub has no text widths
	local heroRoom = M.DOCKED_METRICS.width - 2 * M.DOCKED_METRICS.pad - 2 * M.DOCKED_METRICS.heroPadX
	local model = P.Model(ctx)
	assert(#model.hero.sub * CHAR <= heroRoom, ("hero line %d chars for %d px: %s"):format(#model.hero.sub, heroRoom, model.hero.sub))
	-- the footer shares its line with the filter note (at most 160 px) and a gap of 12
	local footRoom = M.DOCKED_METRICS.width - 2 * M.DOCKED_METRICS.pad - 160 - 12
	assert(#model.footer * CHAR <= footRoom, ("footer %d chars for %d px: %s"):format(#model.footer, footRoom, model.footer))
	-- the window keeps the longer texts
	local wide = P.Model({ metrics = M.WINDOW_METRICS })
	assert(#wide.hero.sub > #model.hero.sub and #wide.footer > #model.footer)
	assert(#wide.footer * CHAR <= M.WINDOW_METRICS.width - 2 * M.WINDOW_METRICS.pad - 160 - 12, wide.footer)
	-- a chosen character puts the undated note in the footer, still one line
	P.state.char = ns.CharKey()
	local one = P.Model({ metrics = M.WINDOW_METRICS })
	assert(#one.footer * CHAR <= M.WINDOW_METRICS.width - 2 * M.WINDOW_METRICS.pad - 160 - 12, one.footer)
	P.state.char = nil
	-- rows keep the key figures: total as the result, today and the profit of today on line two
	local rows = P.Rows(T(2026, 11, 15), {})
	local boots
	for _, r in ipairs(rows) do if r.recipeID == R_BOOTS then boots = r end end
	eq(boots.view.result, "9")
	assert(boots.view.sub:find("today 4", 1, true) and boots.view.sub:find("4s", 1, true), boots.view.sub)
	assert(#boots.view.sub * CHAR <= M.DOCKED_METRICS.width - 2 * M.DOCKED_METRICS.pad - M.DOCKED_METRICS.rightColumn, boots.view.sub)
end)

it("Crafted opens in the window and the docked layout without an error", function()
	local ns = fitSetup()
	local M = ns.Main
	M.Open("crafted")
	assert(M.Frame(), "window")
	M.UI().layout = "dockLeft"
	M.Open("crafted")
	assert(M.Frame(), "docked")
	M.UI().layout = "window"
end)

-- Active crafting time (#251)
it("active time: each gap up to 30 s between two crafts is added to the day of the later craft; the first craft adds 0", function()
	local ns, stub = setup()
	time = function() return T(2026, 11, 15) end
	craftAt(stub, R_BOOTS, 100)
	eq(entryOf(ns, R_BOOTS).days[20261115][5], 0, "no gap before the first craft of a run")
	craftAt(stub, R_BOOTS, 102.5)
	craftAt(stub, R_BOOTS, 105)
	eq(entryOf(ns, R_BOOTS).days[20261115][5], 5)
end)

it("active time: a break over 30 s adds nothing, exactly 30 s counts, and the run restarts after it", function()
	local ns, stub = setup()
	time = function() return T(2026, 11, 15) end
	craftAt(stub, R_BOOTS, 100)
	craftAt(stub, R_BOOTS, 130) -- 30 s
	craftAt(stub, R_BOOTS, 200) -- break
	craftAt(stub, R_BOOTS, 203) -- 3 s from after the break
	eq(entryOf(ns, R_BOOTS).days[20261115][5], 33)
end)

it("active time: gaps run across recipes, so alternating recipes are not counted twice", function()
	local ns, stub = setup()
	time = function() return T(2026, 11, 15) end
	craftAt(stub, R_BOOTS, 100)
	craftAt(stub, R_CLAMS, 103) -- 3 s to the clams
	craftAt(stub, R_BOOTS, 106) -- 3 s to the boots
	eq(entryOf(ns, R_CLAMS).days[20261115][5], 3)
	eq(entryOf(ns, R_BOOTS).days[20261115][5], 3)
end)

it("active time: a gap across midnight goes to the day of the later craft", function()
	local ns, stub = setup()
	time = function() return T(2026, 11, 15, 23) end
	craftAt(stub, R_BOOTS, 100)
	time = function() return T(2026, 11, 16, 0) end
	craftAt(stub, R_BOOTS, 104)
	eq(entryOf(ns, R_BOOTS).days[20261115][5], 0)
	eq(entryOf(ns, R_BOOTS).days[20261116][5], 4)
end)

it("active time: today and 7 days per recipe and over the characters; old days without time give nothing", function()
	local ns = setup()
	time = function() return T(2026, 11, 15) end
	ns.db.crafted = { seeded = true, chars = {
		A = { [R_BOOTS] = { days = { [20261115] = { 4, 4, 0, 0, 120, 4, 0 }, [20261112] = { 3, 3, 0, 0, 60, 3, 0 } } } },
		B = { [R_BOOTS] = { days = { [20261115] = { 2, 2, 0, 0, 30, 2, 0 } } }, [R_CLAMS] = { days = { [20261115] = { 1, 1 } } } } } }
	local now = T(2026, 11, 15)
	local byID = {}
	for _, e in ipairs(ns.CraftLog.List(now)) do byID[e.recipeID] = e end
	eq(byID[R_BOOTS].activeToday, 150); eq(byID[R_BOOTS].activeWeek, 210)
	eq(byID[R_CLAMS].activeToday, nil, "a day without time shows nothing")
	byID = {}
	for _, e in ipairs(ns.CraftLog.List(now, "A")) do byID[e.recipeID] = e end
	eq(byID[R_BOOTS].activeToday, 120)
end)

it("the 90-day fold carries the active seconds; days without time stay without", function()
	local ns = setup()
	local now = T(2026, 11, 15)
	ns.db.crafted = { seeded = true, chars = { A = { [R_BOOTS] = { days = { [20260801] = { 2, 2, 0, 0, 40, 2, 0 }, [20260802] = { 1, 1 } } } } } }
	eq(ns.CraftLog.Fold(now), 2)
	eq(ns.db.crafted.chars.A[R_BOOTS].earlier[5], 40)
end)

it("CraftLog.FormatDuration: seconds, minutes, hours", function()
	local F = setup().CraftLog.FormatDuration
	eq(F(45), "45 s"); eq(F(60), "1 min"); eq(F(3600), "1 h"); eq(F(4320), "1 h 12 min"); eq(F(0.2), "0 s")
end)

it("Crafted summary card: today's active time, the 7-day time in the window, follows the character filter; nothing without time", function()
	local ns = setup()
	local M, P = ns.Main, ns.Main.CraftedPage
	time = function() return T(2026, 11, 15) end
	ns.db.crafted = { seeded = true, chars = {
		A = { [R_BOOTS] = { days = { [20261115] = { 4, 4, 43800, 4, 4320, 4, 43800 }, [20261112] = { 3, 3, 0, 0, 600, 3, 0 } } } },
		B = { [R_BOOTS] = { days = { [20261115] = { 2, 2, 0, 0, 60, 2, 0 } } } } } }
	M.Make.state.query = ""
	local hero = P.Model({ metrics = M.WINDOW_METRICS }).hero
	assert(hero.name:find("1 h 13 min active", 1, true), hero.name)
	assert(hero.name:find(ns.Main.Make.PlainMoney(43800 * 3600 / 4380) .. "/h", 1, true), "gold per active hour: " .. hero.name)
	assert(hero.sub:find("(1 h 23 min active)", 1, true), hero.sub)
	assert(not P.Model({ metrics = M.DOCKED_METRICS }).hero.sub:find("active", 1, true), "docked: key figure only")
	P.state.char = "B"
	hero = P.Model({ metrics = M.WINDOW_METRICS }).hero
	assert(hero.name:find("1 min active", 1, true), hero.name)
	assert(not hero.name:find("/h", 1, true), "no profit recorded for B: no rate")
	P.state.char = nil
	ns.db.crafted.chars.A[R_BOOTS].days[20261115][5] = nil
	ns.db.crafted.chars.A[R_BOOTS].days[20261112][5] = nil
	ns.db.crafted.chars.B[R_BOOTS].days[20261115][5] = nil
	hero = P.Model({ metrics = M.WINDOW_METRICS }).hero
	assert(not hero.name:find("active", 1, true) and not hero.sub:find("active", 1, true), "no time recorded: nothing shown")
end)

-- Profit/h and the profit logged at craft time use one valuation (#265)
local function sameSetup(price)
	local ns, stub = setup()
	time = function() return T(2026, 11, 15) end
	ns.db.vendor[2318] = 5 -- reagent: 5c, vendor
	stub.items = stub.items or {}
	ns.GetVendorSellPrice = function() return 25 end
	ns.AuctionQuote = function() return price end
	ns.AuctionCut = function() return 0.05, { text = "5%", source = "confirmed" } end
	ns.db.crafted = { seeded = true, chars = { [ns.CharKey()] = {
		[R_BOOTS] = { days = { [20261115] = { 0, 0 } }, speed = { n = 5, sum = 10, gaps = { 2, 2, 2, 2, 2 } } } } } }
	ns.Main.Make.state.query = ""
	return ns, stub
end

local function bootsRow(ns)
	for _, r in ipairs(ns.Main.CraftedPage.Rows(T(2026, 11, 15), {})) do
		if r.recipeID == R_BOOTS then return r end
	end
end

it("Profit/h: a product sold to a vendor (Junk) has no AH cut; the per-craft profit equals the craft-time snapshot", function()
	local ns, stub = sameSetup({ copper = 40, age = 1, label = "AH" }) -- AH 40 -> 38 after the cut: the AH pays more
	local recipe = ns.charDB.professions[165].recipes[R_BOOTS]
	ns.db.junk = ns.db.junk or {}
	ns.db.junk[2302] = true -- the output item is Junk: valued at the vendor price 25, no cut
	local now = ns.CraftLog.ProfitNow(R_BOOTS, recipe, 5000)
	eq(now, 25 - 2 * 5)
	local r = bootsRow(ns)
	eq(r.profit, now, "Profit/h's per-craft profit is the snapshot's")
	eq(r.profitHour, 1800 * now)
	eq(r.figures.sale, 25); eq(r.figures.marked, true); eq(r.figures.cost, 10); eq(r.figures.cut, nil)
	local tip = r.view.tips.profitHour[2]
	assert(tip:find("sale 25c (vendor price (Junk mark), no AH cut) - reagents 10c = +15c", 1, true) or tip:find("vendor price (Junk mark), no AH cut", 1, true), tip)
end)

it("Profit/h: an AH sale is valued after the cut, named in the tooltip, and equals the snapshot", function()
	local ns = sameSetup({ copper = 100, age = 1, label = "AH" })
	local recipe = ns.charDB.professions[165].recipes[R_BOOTS]
	local now = ns.CraftLog.ProfitNow(R_BOOTS, recipe, 5000)
	eq(now, 95 - 10)
	local r = bootsRow(ns)
	eq(r.profit, now); eq(r.profitHour, 1800 * now)
	eq(r.figures.sale, 95); eq(r.figures.cut, 0.05)
	local tip = r.view.tips.profitHour[2]
	assert(tip:find("AH after the 5% cut", 1, true), tip)
	assert(tip:find("One craft now", 1, true) and tip:find("reagents 10c", 1, true), tip)
end)

it("Profit/h: when the price now makes a loss, the tooltip shows the figures behind it", function()
	local ns = sameSetup({ copper = 100, age = 1, label = "AH" })
	ns.db.vendor[2318] = 60 -- reagents now cost 120 against a sale of 95
	local r = bootsRow(ns)
	assert(r.profit < 0 and r.profitHour < 0)
	assert(r.view.tips.profitHour[2]:find("= -25c", 1, true), r.view.tips.profitHour[2])
end)

it("Crafted footer names the sale basis and still fits one line", function()
	local ns = sameSetup({ copper = 100, age = 1, label = "AH" })
	local f = ns.Main.CraftedPage.Footer(false)
	assert(f:find("vendor/Junk sales: no cut", 1, true), f)
end)

-- Timed crafts and the gold per active hour from them only (#273)
it("timed: every craft recorded with a clock counts as measured, the profit only of those whose gap counted", function()
	local ns, stub = profitSetup(100)
	craftAt(stub, R_BOOTS, 100) -- first of a run: measured, adds 0 s, its profit is not in timedProfit
	craftAt(stub, R_BOOTS, 103) -- gap 3 s
	craftAt(stub, R_BOOTS, 106) -- gap 3 s
	craftAt(stub, R_BOOTS, 200) -- break
	local b = entryOf(ns, R_BOOTS).days[20261115]
	eq(b[1], 4); eq(b[5], 6); eq(b[6], 4); eq(b[7], 200)
end)

it("a day from before timing: its seconds are dropped when this version adds a craft, the count stays honest", function()
	local ns, stub = setup()
	time = function() return T(2026, 11, 15) end
	ns.db.crafted = { seeded = true, chars = { [ns.CharKey()] = { [R_BOOTS] = { days = { [20261115] = { 100, 100, 0, 0, 300 } } } } } }
	craftAt(stub, R_BOOTS, 100)
	craftAt(stub, R_BOOTS, 103)
	local b = entryOf(ns, R_BOOTS).days[20261115]
	eq(b[1], 102); eq(b[5], 3); eq(b[6], 2)
	-- before the first new craft the old seconds are not used either
	ns.db.crafted.chars[ns.CharKey()][R_BOOTS].days[20261114] = { 50, 50, 0, 0, 999 }
	local e
	for _, x in ipairs(ns.CraftLog.List(T(2026, 11, 15))) do if x.recipeID == R_BOOTS then e = x end end
	eq(e.activeWeek, 3)
end)

it("Crafted card: a day half timed says how many crafts were timed, and the gold per hour uses only those", function()
	local ns = setup()
	local M, P = ns.Main, ns.Main.CraftedPage
	time = function() return T(2026, 11, 15) end
	-- 4,000 crafts today with a profit of 10 each (40,000); 400 of them timed: 1,200 s and 4,000 profit
	ns.db.crafted = { seeded = true, chars = { A = { [R_BOOTS] = { days = { [20261115] = { 4000, 4000, 40000, 4000, 1200, 400, 4000 } } } } } }
	M.Make.state.query = ""
	local hero = P.Model({ metrics = M.WINDOW_METRICS }).hero
	assert(hero.name:find("20 min active", 1, true), hero.name)
	assert(hero.name:find("(400 of 4,000 crafts timed)", 1, true), hero.name)
	assert(hero.name:find(M.Make.PlainMoney(4000 * 3600 / 1200) .. "/h", 1, true), "profit of the timed crafts over their time: " .. hero.name)
	assert(not hero.name:find(M.Make.PlainMoney(40000 * 3600 / 1200), 1, true), "never all crafts over the timed seconds")
	assert(hero.sub:find("400 of 4,000 crafts timed", 1, true), hero.sub)
	assert(P.Model({ metrics = M.DOCKED_METRICS }).hero.name:find("(400 timed)", 1, true))
	-- a fully timed day drops the parenthesis
	ns.db.crafted.chars.A[R_BOOTS].days[20261115] = { 100, 100, 1000, 100, 300, 100, 1000 }
	hero = P.Model({ metrics = M.WINDOW_METRICS }).hero
	assert(hero.name:find("5 min active", 1, true) and not hero.name:find("timed", 1, true), hero.name)
	-- the Today cell explains what active means
	local row
	for _, r in ipairs(P.Rows(T(2026, 11, 15), {})) do if r.recipeID == R_BOOTS then row = r end end
	assert(row.view.tips.today[2]:find("up to 30 s", 1, true) and row.view.tips.today[2]:find("longer pauses don't count", 1, true))
end)

it("timed: the measurement replayed: timed crafts times the gap equals the active seconds", function()
	local ns, stub = profitSetup(10)
	local t = 1000
	for _ = 1, 200 do craftAt(stub, R_BOOTS, t); t = t + 3.1 end
	local b = entryOf(ns, R_BOOTS).days[20261115]
	eq(b[6], 200)
	assert(math.abs(b[5] - 199 * 3.1) < 2, "active " .. b[5])
	assert(math.abs(b[5] / (b[6] - 1) - 3.1) < 0.05, "implied seconds per craft")
end)

it("Crafted card: an estimate for the untimed crafts (count x the recipe's median gap), marked and apart from the measured time", function()
	local ns = setup()
	local M, P = ns.Main, ns.Main.CraftedPage
	time = function() return T(2026, 11, 15) end
	-- 4,000 crafts, 400 timed (1,200 s measured); the recipe's median is 3 s (5+ gaps): 3,600 untimed x 3 s = 10,800 s = 3 h
	ns.db.crafted = { seeded = true, chars = { A = { [R_BOOTS] = { days = { [20261115] = { 4000, 4000, 40000, 4000, 1200, 400, 4000 } },
		speed = { n = 5, sum = 15, gaps = { 3, 3, 3, 3, 3 } } } } } }
	M.Make.state.query = ""
	local hero = P.Model({ metrics = M.WINDOW_METRICS }).hero
	assert(hero.name:find("20 min active (400 of 4,000 crafts timed)", 1, true), hero.name)
	assert(hero.name:find("+ ≈ 3 h est. for 3,600 untimed crafts", 1, true), hero.name)
	-- the measured per-hour figure stays; the ≈ figure divides all of today's profit by measured + estimated seconds
	assert(hero.name:find(M.Make.PlainMoney(4000 * 3600 / 1200) .. "/h", 1, true), hero.name)
	assert(hero.name:find("≈ " .. M.Make.PlainMoney(40000 * 3600 / (1200 + 10800)) .. "/h est.", 1, true), hero.name)
	-- without a measured median (under 5 gaps) there is no estimate
	ns.db.crafted.chars.A[R_BOOTS].speed = { n = 2, sum = 6, gaps = { 3, 3 } }
	hero = P.Model({ metrics = M.WINDOW_METRICS }).hero
	assert(not hero.name:find("est.", 1, true), hero.name)
end)

-- Long casts are timed by the cast itself (#295)
local function castAt(stub, id, start, finish)
	stub.now = start
	stub.Fire("UNIT_SPELLCAST_START", "player", "guid", id)
	stub.now = finish
	craft(stub, id)
end

it("long casts: a 60 s recipe is timed from its cast, also when each craft starts after a pause", function()
	local ns, stub = setup()
	time = function() return T(2026, 11, 15) end
	-- five crafts clicked one by one, minutes apart: every gap is a break, but each cast was measured
	for i = 1, 5 do castAt(stub, R_BOOTS, 1000 + i * 300, 1060 + i * 300) end
	local e = entryOf(ns, R_BOOTS)
	eq(e.speed.n, 5); eq(e.speed.sum, 300)
	local s = ns.CraftLog.Speed(R_BOOTS)
	eq(s.sec, 60); eq(s.perHour, 60)
	local b = e.days[20261115]
	eq(b[5], 300, "each craft adds its own cast as active time"); eq(b[6], 5)
end)

it("long casts: a Create All run counts the gap up to the cast plus 30 s, not as a break", function()
	local ns, stub = setup()
	time = function() return T(2026, 11, 15) end
	local t = 1000
	for _ = 1, 6 do castAt(stub, R_BOOTS, t, t + 60); t = t + 60 + 5 end -- 5 s between a success and the next click
	local s = entryOf(ns, R_BOOTS).speed
	-- the first craft has no gap before it: its cast, 60; the later ones 65 s gaps (<= 60 + 30)
	eq(s.n, 6); eq(s.gaps[1], 60); eq(s.gaps[2], 65)
	eq(ns.CraftLog.Speed(R_BOOTS).sec, 65)
end)

it("long casts: a real break after a long cast is still excluded; the craft adds its own cast only", function()
	local ns, stub = setup()
	time = function() return T(2026, 11, 15) end
	castAt(stub, R_BOOTS, 1000, 1060)
	castAt(stub, R_BOOTS, 1065, 1125) -- gap 65 s <= 90: counts
	castAt(stub, R_BOOTS, 1500, 1560) -- gap 435 s: a break
	local e = entryOf(ns, R_BOOTS)
	eq(e.speed.gaps[2], 65); eq(e.speed.gaps[3], 60, "the break's sample is its cast, not 435 s")
	eq(e.days[20261115][5], 60 + 65 + 60)
end)

it("short casts: unchanged, no START seen means the old rules; a cancelled cast is not used", function()
	local ns, stub = setup()
	time = function() return T(2026, 11, 15) end
	craftAt(stub, R_BOOTS, 100); craftAt(stub, R_BOOTS, 102.5)
	eq(entryOf(ns, R_BOOTS).speed.n, 1); eq(entryOf(ns, R_BOOTS).days[20261115][5], 2.5)
	craftAt(stub, R_BOOTS, 140) -- 37.5 s without a measured cast: a break
	eq(entryOf(ns, R_BOOTS).speed.n, 1)
	stub.now = 200
	stub.Fire("UNIT_SPELLCAST_START", "player", "guid", R_BOOTS)
	stub.Fire("UNIT_SPELLCAST_INTERRUPTED", "player", "guid", R_BOOTS)
	craftAt(stub, R_BOOTS, 260) -- no cast measured: 120 s since the last craft is a break, adds 0
	eq(entryOf(ns, R_BOOTS).speed.n, 1)
	eq(entryOf(ns, R_BOOTS).days[20261115][5], 2.5)
end)

-- Make › Crafted hero: the estimated profit in total (#378)
local function seedProfitLog(ns)
	time = function() return T(2026, 11, 15) end
	ns.db.crafted = { seeded = true, before = {}, chars = {
		["TestRealm-Main Tanner"] = { [R_BOOTS] = { days = { [20261110] = { 5, 5, 500, 5 } } }, [R_CLAMS] = { days = { [20261115] = { 2, 2, 0, 0 } } } },
		["TestRealm-Alt Mage"] = { [R_BOOTS] = { days = { [20261115] = { 3, 3, 300, 3 } } } } } }
end

it("Crafted hero: total profit is the sum of the rows, an unpriced recipe adds nothing and is counted", function()
	local ns = setup()
	seedProfitLog(ns)
	local P, MK = ns.Main.CraftedPage, ns.Main.Make
	local hero = P.Model().hero
	assert(hero.sub:find("total " .. MK.PlainMoney(800), 1, true), hero.sub)
	assert(hero.sub:find("8 of 10 priced", 1, true), hero.sub)
	assert(hero.tip and hero.tip[3]:find("8 of 10", 1, true), "tooltip says how many crafts are priced")
	assert(hero.tip[4]:find("Not money received", 1, true) and hero.tip[4]:find("Ledger", 1, true))
end)

it("Crafted hero: total profit follows the character filter and drops the priced note when all are priced", function()
	local ns = setup()
	seedProfitLog(ns)
	local P, MK = ns.Main.CraftedPage, ns.Main.Make
	P.state.char = "TestRealm-Alt Mage"
	local hero = P.Model().hero
	assert(hero.sub:find("total " .. MK.PlainMoney(300), 1, true), hero.sub)
	assert(not hero.sub:find("priced", 1, true), hero.sub)
	P.state.char = nil
	MK.state.query = "clams"
	hero = P.Model().hero
	assert(hero.tip == nil and not hero.sub:find("profit 7 days", 1, true), "no priced craft in the filtered rows: no total")
	MK.state.query = ""
end)
