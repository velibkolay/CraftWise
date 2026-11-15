-- Skill-up recorder (issue #15). Every craft is logged with the skill it was made at and whether it
-- gave a point, so skill-up chances can be measured in game instead of taken from the community
-- formula (not official, not verified for Forever). Totals live in CraftWiseDB.skillups:
--   [recipeID] = { [skill] = { n = crafts, ups = skill points gained, d = client difficulty } }
local _, ns = ...

-- Craft log (#205). Every craft is counted per character, recipe and local day, whether or not it gave a
-- skill-up and at any skill, from the same craft detection below (OnCraft). CraftWiseDB.crafted:
--   { seeded = true,
--     before = { [recipeID] = crafts }  crafts counted in skillups before the log existed (undated, no character),
--     chars = { [ns.CharKey()] = { [recipeID] = { days = { [YYYYMMDD] = { crafts, items, profit, known } },
--                                                  earlier = { crafts, items, profit, known }, speed = ... } } } }
-- profit = copper, the profit per craft as computed at craft time (profit view's cost basis, the sale with the
-- Junk mark respected, #227), summed over the crafts that had one; known = how many crafts that is. A
-- craft without a price adds to crafts only. Days from before profit was recorded have neither.
-- Days older than KEEP_DAYS fold into `earlier` (once per session, never on a craft). items = crafts times the
-- recipe's yield when that is one exact number; recipes with a yield range add crafts only (the client's
-- received quantity is not read, see docs/ingame-checks.md).
ns.CraftLog = ns.CraftLog or {}
local CL = ns.CraftLog
CL.KEEP_DAYS = 90

-- Craft speed (#209): the gap between two crafts of the same recipe by the same character, measured with
-- GetTime(). A gap longer than BREAK_SECONDS is a break (so is the first craft of a run) and is not counted.
-- Per character and recipe, entry.speed = { n = gaps counted, sum = their seconds, gaps = the last GAP_KEEP
-- gaps as a ring (position n % GAP_KEEP + 1) for the median }: bounded, one write per craft. The figures show
-- from MIN_GAPS gaps on. Nothing else is measured or assumed (no cast-time table).
CL.BREAK_SECONDS = 30
CL.GAP_KEEP = 50
CL.MIN_GAPS = 5
local lastCraft = {} -- [recipeID] = GetTime() of this session's previous craft of it (this character)

-- The speed table of a log entry, after one craft at clock time `at` (seconds, nil = unknown).
local function AddGap(entry, recipeID, at)
	local before = lastCraft[recipeID]
	lastCraft[recipeID] = at
	if not (at and before) then
		return
	end
	local gap = at - before
	if gap <= 0 or gap > CL.BREAK_SECONDS then
		return
	end
	local speed = entry.speed
	if not speed then
		speed = { n = 0, sum = 0, gaps = {} }
		entry.speed = speed
	end
	gap = math.floor(gap * 100 + 0.5) / 100
	speed.gaps[speed.n % CL.GAP_KEEP + 1] = gap
	speed.n, speed.sum = speed.n + 1, speed.sum + gap
end

-- Median of a list of numbers (does not change it).
function CL.Median(list)
	local n = #list
	if n == 0 then
		return nil
	end
	local sorted = {}
	for i = 1, n do
		sorted[i] = list[i]
	end
	table.sort(sorted)
	if n % 2 == 1 then
		return sorted[(n + 1) / 2]
	end
	return (sorted[n / 2] + sorted[n / 2 + 1]) / 2
end

-- Speed of a recipe over all characters: { sec = median seconds per craft, perHour = crafts per hour, n = gaps
-- counted, mean = sum / n }, nil below MIN_GAPS gaps. perHour is 3600 / sec.
function CL.Speed(recipeID)
	local log = ns.db and ns.db.crafted
	if not log then
		return nil
	end
	local gaps, n, sum = {}, 0, 0
	for _, char in pairs(log.chars or {}) do
		local speed = char[recipeID] and char[recipeID].speed
		if speed then
			n, sum = n + speed.n, sum + speed.sum
			for _, g in ipairs(speed.gaps) do
				gaps[#gaps + 1] = g
			end
		end
	end
	if n < CL.MIN_GAPS then
		return nil
	end
	local sec = CL.Median(gaps)
	if not sec or sec <= 0 then
		return nil
	end
	return { sec = sec, perHour = 3600 / sec, n = n, mean = sum / n }
end

-- Profit per hour at today's prices: crafts per hour times the profit per craft; nil without either.
function CL.ProfitPerHour(speed, profit)
	if not (speed and profit) then
		return nil
	end
	return speed.perHour * profit
end

-- "12.5" (one decimal, none for whole numbers).
function CL.FormatSeconds(sec)
	local s = ("%.1f"):format(sec)
	return (s:gsub("%.0$", ""))
end

-- Days since 1970-01-01 of a YYYYMMDD key (pure calendar maths, no time zone).
function CL.DayNumber(ymd)
	local y, m, d = math.floor(ymd / 10000), math.floor(ymd / 100) % 100, ymd % 100
	if m <= 2 then
		y, m = y - 1, m + 12
	end
	return 365 * y + math.floor(y / 4) - math.floor(y / 100) + math.floor(y / 400) + math.floor((153 * (m - 3) + 2) / 5) + d - 719469
end

function CL.Today(now)
	return tonumber(date("%Y%m%d", now or time()))
end

-- The log table; the first call also seeds the undated bucket from skillups, once.
function CL.Store()
	local db = ns.db
	if not db then
		return nil
	end
	local log = db.crafted
	if not log then
		log = { chars = {}, before = {} }
		db.crafted = log
	end
	log.chars = log.chars or {}
	log.before = log.before or {}
	if not log.seeded then
		log.seeded = true
		for recipeID, bySkill in pairs(db.skillups or {}) do
			local n = 0
			for _, e in pairs(bySkill) do
				n = n + (e.n or 0)
			end
			if n > 0 then
				log.before[recipeID] = n
			end
		end
	end
	return log
end

-- 1532 -> "1,532".
function CL.Format(n)
	local s = tostring(math.floor(n or 0))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

-- Character shown in lists: the key without its realm ("<realm>-<name> <surname>").
function CL.CharLabel(key)
	return key:match("^.-%-(.+)$") or key
end

-- The lines the Make tooltip and the opened row show for one recipe (pure over Counts): nil when nothing
-- was ever logged. { headline = "Crafted 1,532 - today 120", chars = { "Name  today 5 - 7 days 30 - total 200" },
-- before = "Before the log (undated): 1,500", profit = crafts for the "at today's prices" line }.
function CL.Lines(recipeID, now)
	local c = CL.Counts(recipeID, now)
	local total = c.total + c.before
	if total == 0 then
		return nil
	end
	local out = { total = total, today = c.today, chars = {}, dated = c.total }
	local L = ns.L
	out.headline = (L["Crafted %s \194\183 today %s"]):format(CL.Format(total), CL.Format(c.today))
	for _, ch in ipairs(c.chars) do
		out.chars[#out.chars + 1] = { name = CL.CharLabel(ch.key), text = (L["today %s \194\183 7 days %s \194\183 total %s"]):format(
			CL.Format(ch.today), CL.Format(ch.week), CL.Format(ch.total)) }
	end
	if c.before > 0 then
		out.before = (L["Before the log (undated): %s"]):format(CL.Format(c.before))
	end
	if c.earlier > 0 then
		out.earlier = (L["Older than %d days: %s"]):format(CL.KEEP_DAYS, CL.Format(c.earlier))
	end
	out.speed = CL.Speed(recipeID)
	out.profit = c.profit
	out.dated = c.total
	for i, ch in ipairs(c.chars) do
		out.chars[i].profit = ch.profit
		out.chars[i].crafts = ch.total
	end
	out.payback = CL.Payback(recipeID, c.profit.total, c.profit.known)
	return out
end

-- Exact items per craft, or nil for a range or an unknown output.
local function Yield(recipe)
	local q = recipe and recipe.output and recipe.output.quantity
	if q and q >= 1 and q == math.floor(q) then
		return q
	end
end

-- The profit per craft of a recipe right now, in copper, as Make > Craft computes it (the profit view's cost
-- basis, #47; the sale value with the vendor mark, #214): nil when the recipe, a reagent or the sale has no price.
-- Kept for PROFIT_TTL seconds of the game clock per recipe, so Create All evaluates it once.
CL.PROFIT_TTL = 60
local profitMemo = {} -- [recipeID] = { clock, profit or false }

function CL.ProfitNow(recipeID, recipe, clock)
	local memo = profitMemo[recipeID]
	if memo and clock and memo[1] and clock - memo[1] < CL.PROFIT_TTL then
		return memo[2] or nil
	end
	local reagents, output = recipe and recipe.reagents, recipe and recipe.output
	if not reagents and ns.RecipeFallback then
		reagents, output = ns.RecipeFallback(recipeID)
	end
	local profit
	if reagents and ns.Profit and ns.ReagentPrices then
		local result = ns.Profit.Evaluate({ reagents = reagents, output = output, learned = true }, ns.ReagentPrices("profit"))
		profit = result and result.profit
	end
	profitMemo[recipeID] = { clock, profit or false }
	return profit
end

-- One craft: one write into today's bucket.
function CL.Record(recipeID, recipe, now, clock)
	local log = CL.Store()
	local key = log and ns.CharKey()
	if not key then
		return
	end
	local char = log.chars[key]
	if not char then
		char = {}
		log.chars[key] = char
	end
	local entry = char[recipeID]
	if not entry then
		entry = { days = {} }
		char[recipeID] = entry
	end
	local day = CL.Today(now)
	local bucket = entry.days[day]
	if not bucket then
		bucket = { 0, 0, 0, 0 }
		entry.days[day] = bucket
	end
	bucket[1] = bucket[1] + 1
	bucket[2] = bucket[2] + (Yield(recipe) or 0)
	local profit = CL.ProfitNow(recipeID, recipe, clock)
	if profit then
		bucket[3] = (bucket[3] or 0) + math.floor(profit + 0.5)
		bucket[4] = (bucket[4] or 0) + 1
	end
	AddGap(entry, recipeID, clock)
	ns.Notify("CRAFTLOG_CHANGED", recipeID)
end

-- Folds days older than KEEP_DAYS into `earlier`, for every character. Returns the number of days folded.
function CL.Fold(now)
	local log = CL.Store()
	if not log then
		return 0
	end
	local today = CL.DayNumber(CL.Today(now))
	local folded = 0
	for _, char in pairs(log.chars) do
		for _, entry in pairs(char) do
			for day, bucket in pairs(entry.days) do
				if today - CL.DayNumber(day) >= CL.KEEP_DAYS then
					local earlier = entry.earlier or { 0, 0, 0, 0 }
					entry.earlier = earlier
					earlier[1], earlier[2] = earlier[1] + bucket[1], earlier[2] + bucket[2]
					earlier[3], earlier[4] = (earlier[3] or 0) + (bucket[3] or 0), (earlier[4] or 0) + (bucket[4] or 0)
					entry.days[day] = nil
					folded = folded + 1
				end
			end
		end
	end
	return folded
end

-- Sums of one recipe entry of one character: { crafts, profit, known } for today, the last 7 days (today and the
-- 6 days before) and in total (days plus the folded `earlier`), items and the folded crafts. profit is in
-- copper, as recorded at craft time; known = crafts that had a profit.
local function Windows(entry, todayNumber)
	local w = { today = { 0, 0, 0 }, week = { 0, 0, 0 }, total = { 0, 0, 0 }, items = 0, earlier = 0 }
	local function Add(window, b)
		window[1], window[2], window[3] = window[1] + b[1], window[2] + (b[3] or 0), window[3] + (b[4] or 0)
	end
	for day, b in pairs(entry.days) do
		local age = todayNumber - CL.DayNumber(day)
		if age == 0 then
			Add(w.today, b)
		end
		if age >= 0 and age < 7 then
			Add(w.week, b)
		end
		Add(w.total, b)
		w.items = w.items + b[2]
	end
	if entry.earlier then
		Add(w.total, entry.earlier)
		w.items, w.earlier = w.items + entry.earlier[2], entry.earlier[1]
	end
	return w
end

-- Counts of one recipe (reads that recipe only): today, week (today and the 6 days before), total and items
-- over all characters, earlier (folded part), before (undated crafts from skillups, not in total), profit =
-- { today, week, total, known } (copper recorded at craft time; known = crafts of the total with a profit),
-- and chars = { { key, today, week, total, items, profit = { today, week, total, known, knownToday, knownWeek } } }
-- sorted by total.
function CL.Counts(recipeID, now)
	local log = ns.db and ns.db.crafted
	local out = { today = 0, week = 0, total = 0, items = 0, earlier = 0, before = 0, chars = {},
		profit = { today = 0, week = 0, total = 0, known = 0, knownToday = 0, knownWeek = 0 } }
	if not log then
		return out
	end
	out.before = log.before and log.before[recipeID] or 0
	local today = CL.DayNumber(CL.Today(now))
	for key, char in pairs(log.chars or {}) do
		local entry = char[recipeID]
		if entry then
			local w = Windows(entry, today)
			local c = { key = key, today = w.today[1], week = w.week[1], total = w.total[1], items = w.items,
				profit = { today = w.today[2], week = w.week[2], total = w.total[2], known = w.total[3],
					knownToday = w.today[3], knownWeek = w.week[3] } }
			out.earlier = out.earlier + w.earlier
			out.today, out.week, out.total, out.items = out.today + c.today, out.week + c.week, out.total + c.total, out.items + c.items
			for k, v in pairs(c.profit) do
				out.profit[k] = out.profit[k] + v
			end
			out.chars[#out.chars + 1] = c
		end
	end
	table.sort(out.chars, function(a, b)
		if a.total ~= b.total then
			return a.total > b.total
		end
		return a.key < b.key
	end)
	return out
end

-- Characters in the log, sorted.
function CL.Characters()
	local out = {}
	for key in pairs(ns.db and ns.db.crafted and ns.db.crafted.chars or {}) do
		out[#out + 1] = key
	end
	table.sort(out)
	return out
end

-- Every logged recipe for the Crafted page: { recipeID, today, week, total, before, profitToday, profitWeek,
-- profitTotal, knownToday, knownWeek, known, dated } with total = dated plus undated crafts, dated = the dated
-- ones, known = dated crafts with a recorded profit; sorted by today, then week, then total. charKey = only that
-- character's dated crafts (the undated crafts have no character and drop out).
function CL.List(now, charKey)
	local log = CL.Store()
	local list, byRecipe = {}, {}
	if not log then
		return list
	end
	local todayNumber = CL.DayNumber(CL.Today(now))
	local function Row(recipeID)
		local r = byRecipe[recipeID]
		if not r then
			r = { recipeID = recipeID, today = 0, week = 0, total = 0, before = 0, dated = 0,
				profitToday = 0, profitWeek = 0, profitTotal = 0, knownToday = 0, knownWeek = 0, known = 0 }
			byRecipe[recipeID] = r
			list[#list + 1] = r
		end
		return r
	end
	for key, char in pairs(log.chars) do
		if not charKey or key == charKey then
			for recipeID, entry in pairs(char) do
				local r, w = Row(recipeID), Windows(entry, todayNumber)
				r.today, r.week, r.total, r.dated = r.today + w.today[1], r.week + w.week[1], r.total + w.total[1], r.dated + w.total[1]
				r.profitToday, r.profitWeek, r.profitTotal = r.profitToday + w.today[2], r.profitWeek + w.week[2], r.profitTotal + w.total[2]
				r.knownToday, r.knownWeek, r.known = r.knownToday + w.today[3], r.knownWeek + w.week[3], r.known + w.total[3]
			end
		end
	end
	for recipeID, n in pairs(not charKey and log.before or {}) do
		local r = Row(recipeID)
		r.before, r.total = n, r.total + n
	end
	table.sort(list, function(a, b)
		if a.today ~= b.today then
			return a.today > b.today
		end
		if a.week ~= b.week then
			return a.week > b.week
		end
		if a.total ~= b.total then
			return a.total > b.total
		end
		return a.recipeID < b.recipeID
	end)
	return list
end

----------------------------------------------------------------------------------------------------
-- Recipe payback (#215): what the recipe cost, against the profit logged for it
----------------------------------------------------------------------------------------------------

-- What the recipe cost to learn, in copper: the latest AH or vendor purchase of the recipe item in the ledger,
-- else the recipe item's recorded vendor price. The item comes from the bundled data (ns.SourceData, client DB2);
-- nil without a mapping or a price: nothing is guessed. Returns copper, "ledger" | "vendor", itemID.
function CL.RecipeCost(recipeID)
	local data = ns.SourceData and ns.SourceData[recipeID]
	local itemID = data and data.item
	if not itemID then
		return nil
	end
	local latest
	for _, e in ipairs(ns.Ledger and ns.Ledger.Entries() or {}) do
		if e.i == itemID and (e.k == "ahbuy" or e.k == "vbuy") and e.q and e.q > 0 and (not latest or e.t >= latest.t) then
			latest = e
		end
	end
	if latest then
		return latest.m / latest.q, "ledger", itemID
	end
	local unit = ns.db and ns.db.vendor and ns.db.vendor[itemID]
	if unit and unit > 0 then
		return unit, "vendor", itemID
	end
	return nil
end

-- Payback of a recipe from the logged profit (copper, estimated at craft time): nil without a known recipe
-- cost; { cost, source, paidBack = profit >= cost, togo = what is left (0 once paid back), known = false when
-- no craft has a recorded profit yet }.
function CL.Payback(recipeID, profit, known)
	local cost, source = CL.RecipeCost(recipeID)
	if not cost then
		return nil
	end
	local made = (known or 0) > 0 and profit or 0
	return { cost = cost, source = source, paidBack = (known or 0) > 0 and made >= cost, togo = math.max(0, cost - made),
		known = (known or 0) > 0 }
end

local SETTLE = 2.5 -- seconds a craft waits for its skill update before it counts as no skill-up

local tracked = {} -- [professionID] = skill last seen
local pending = {} -- crafts waiting for their skill update, oldest first
local unclaimed -- { prof, amount, time }: a skill update that arrived before its craft event

local function Now()
	return GetTime and GetTime() or 0
end

local function Secret(v)
	return issecretvalue and issecretvalue(v)
end

-- Current skill per profession, from the client's profession list.
local function ClientSkills()
	local skills = {}
	if not (GetProfessions and GetProfessionInfo) then
		return skills
	end
	local list = { GetProfessions() }
	for i = 1, 6 do
		local index = list[i]
		if index then
			local ok, _, _, skill, _, _, _, skillLine = pcall(GetProfessionInfo, index)
			if ok and skillLine and skill and not Secret(skill) then
				skills[skillLine] = skill
			end
		end
	end
	return skills
end

local function RecipeOwner(recipeID)
	for professionID, prof in pairs(ns.charDB and ns.charDB.professions or {}) do
		if prof.recipes[recipeID] then
			return professionID, prof.recipes[recipeID]
		end
	end
end

local function Store(craft, gained)
	if not ns.db then
		return
	end
	ns.db.skillups = ns.db.skillups or {}
	local byRecipe = ns.db.skillups[craft.recipeID] or {}
	ns.db.skillups[craft.recipeID] = byRecipe
	local entry = byRecipe[craft.skill] or { n = 0, ups = 0 }
	byRecipe[craft.skill] = entry
	entry.n = entry.n + 1
	entry.ups = entry.ups + (gained > 0 and 1 or 0)
	entry.d = craft.difficulty or entry.d
	ns.Notify("SKILLUPS_CHANGED", craft.recipeID)
end

-- Compare client skills with what we last saw and hand gains to the oldest waiting craft.
function ns.CheckSkills()
	for prof, skill in pairs(ClientSkills()) do
		local before = tracked[prof]
		tracked[prof] = skill
		if before and skill > before then
			local gain = skill - before
			for i, craft in ipairs(pending) do
				if craft.prof == prof then
					table.remove(pending, i)
					Store(craft, gain)
					gain = 0
					break
				end
			end
			if gain > 0 then
				unclaimed = { prof = prof, amount = gain, time = Now() }
			end
		end
	end
end

-- Crafts older than SETTLE without a skill update gave no point.
function ns.SettleCrafts(now)
	now = now or Now()
	ns.CheckSkills()
	local i = 1
	while pending[i] do
		if now - pending[i].time >= SETTLE then
			Store(table.remove(pending, i), 0)
		else
			i = i + 1
		end
	end
end

function ns.OnCraft(recipeID)
	local prof, recipe = RecipeOwner(recipeID)
	if not prof then
		return
	end
	CL.Record(recipeID, recipe, nil, GetTime and GetTime() or nil) -- every craft counts, with or without a skill update (#205)
	ns.CheckSkills()
	local now = Now()
	local craft = { recipeID = recipeID, prof = prof, skill = tracked[prof], difficulty = recipe.difficulty, time = now }
	if unclaimed and unclaimed.prof == prof and now - unclaimed.time <= SETTLE then
		craft.skill = (craft.skill or 0) - unclaimed.amount
		local amount = unclaimed.amount
		unclaimed = nil
		if craft.skill > 0 then
			Store(craft, amount)
		end
		return
	end
	if not craft.skill then
		return -- skill unknown: can't say at which skill this craft was made
	end
	pending[#pending + 1] = craft
	if C_Timer and C_Timer.After then
		C_Timer.After(SETTLE + 0.1, function()
			ns.SettleCrafts()
		end)
	end
end

ns.On("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, _, spellID)
	if unit ~= "player" or not spellID or Secret(spellID) then
		return
	end
	ns.OnCraft(spellID)
end)

ns.On("PLAYER_ENTERING_WORLD", function()
	CL.Fold()
end)

for _, event in ipairs({ "SKILL_LINES_CHANGED", "TRADE_SKILL_LIST_UPDATE", "CHAT_MSG_SKILL", "PLAYER_ENTERING_WORLD" }) do
	ns.On(event, function()
		ns.CheckSkills()
	end)
end

-- Live skill of a profession as the client reports it (nil until seen).
function ns.LiveSkill(professionID)
	return tracked[professionID] or ClientSkills()[professionID]
end

-- Bundled yellow and grey thresholds (client DB2, Data/Thresholds.lua).
function ns.RecipeThresholds(recipeID)
	local t = ns.Thresholds and ns.Thresholds[recipeID]
	if t then
		return t[1], t[2]
	end
end

-- Recorded crafts of a recipe: at one skill, or all skills added up.
function ns.SkillUpStats(recipeID, skill)
	local byRecipe = ns.db and ns.db.skillups and ns.db.skillups[recipeID]
	if not byRecipe then
		return 0, 0
	end
	if skill then
		local e = byRecipe[skill]
		return e and e.n or 0, e and e.ups or 0
	end
	local n, ups = 0, 0
	for _, e in pairs(byRecipe) do
		n, ups = n + e.n, ups + e.ups
	end
	return n, ups
end

function ns.CraftsRecorded()
	local n = 0
	for recipeID in pairs(ns.db and ns.db.skillups or {}) do
		n = n + (ns.SkillUpStats(recipeID))
	end
	return n
end
