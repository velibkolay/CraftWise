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
