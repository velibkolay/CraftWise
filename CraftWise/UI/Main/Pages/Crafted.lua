-- Main window, Make › Crafted (#205): how many times each recipe was crafted, from the craft log
-- (Crafts.lua, ns.CraftLog). One row per logged recipe: crafts today, in the last 7 days and in total over
-- every character of this account. The total includes the undated crafts counted before the log existed
-- (the tooltip says how many). Hover a row for the split per character. Not tied to the Make profession:
-- the filter box is Make's (one query for all its pages), the profession chip and the character chip
-- choose "all" or one (this session); the headers sort (Recipe, Today, 7 days, Total) and the shell
-- remembers the choice like Craft's (db.settings.ui.sort).
local _, ns = ...
local M = ns.Main
local MK = M.Make
local Style, L = ns.Style, ns.L
local CL = ns.CraftLog

local P = {}
M.CraftedPage = P

-- Eight columns that fit the window at its default width (the shell's ColumnLayout: 836 inside the padding, 12
-- between columns): the recipe name takes what the fixed ones leave (at least 180). Speed merges seconds per craft
-- and crafts per hour ("3.1 s · 1,168/h") and sorts by crafts per hour. Profit 7 days is not a column: it is in the
-- hero card and the tooltip.
local COLUMNS = {
	{ key = "icon", icon = true, width = 22 },
	MK.Column("name", L["Recipe"], nil, "LEFT", "Body", true),
	MK.Column("today", L["Today"], 52, "RIGHT", "Figure", true),
	MK.Column("week", L["7 days"], 52, "RIGHT", "Figure", true),
	MK.Column("total", L["Total"], 66, "RIGHT", "FigureBold", true),
	MK.Column("speed", L["Speed"], 104, "RIGHT", "Figure", true),
	MK.Column("profitHour", L["Profit/h"], 84, "RIGHT", "Figure", true),
	MK.Column("profitToday", L["Profit today"], 84, "RIGHT", "Figure", true),
	MK.Column("profitTotal", L["Profit total"], 96, "RIGHT", "FigureBold", true),
}
P.COLUMNS = COLUMNS
P.MIN_NAME = 180 -- the narrowest the flexible recipe column may get at the default width
-- Dragged wider (#280) the columns that are cut at their width get room first, the recipe name the rest.
COLUMNS[2].min = P.MIN_NAME
for key, grow in pairs({ speed = 140, profitHour = 100, profitToday = 100, profitTotal = 116 }) do
	for _, col in ipairs(COLUMNS) do
		if col.key == key then
			col.grow = grow
		end
	end
end

-- Sorting keys that sort by another field: the merged Speed column sorts by crafts per hour.
local SORT_FIELD = { speed = "perHour" }

-- The filters of this session: line = a profession's skill line (nil = all), char = a character key (nil = all).
P.state = { line = nil, char = nil }

-- Sort (pure): the chosen column (rows without a figure last), then today, 7 days and total (largest first),
-- then the name. desc as the shell passes it (a click on the chosen column again flips it).
local FALLBACK = { "today", "week", "total" }

local function ByName(a, b)
	local na, nb = (a.name or ""):lower(), (b.name or ""):lower()
	if na ~= nb then
		return na < nb
	end
end

function P.Compare(key, desc)
	return function(a, b)
		if key == "name" then
			local na, nb = (a.name or ""):lower(), (b.name or ""):lower()
			if na ~= nb then
				if desc then
					return na > nb
				end
				return na < nb
			end
		else
			local va, vb = a[key], b[key]
			if (va == nil) ~= (vb == nil) then
				return va ~= nil -- a missing figure (no speed measured yet) sorts last either way
			end
			va, vb = va or 0, vb or 0
			if va ~= vb then
				if desc then
					return va > vb
				end
				return va < vb
			end
		end
		for _, k in ipairs(FALLBACK) do
			if k ~= key and (a[k] or 0) ~= (b[k] or 0) then
				return (a[k] or 0) > (b[k] or 0)
			end
		end
		local byName = ByName(a, b)
		if byName ~= nil then
			return byName
		end
		return a.recipeID < b.recipeID
	end
end

function P.SortRows(rows, key, desc)
	key = key or "today"
	table.sort(rows, P.Compare(SORT_FIELD[key] or key, desc ~= false))
	return rows
end

-- Profession name of a skill line: the bundled name -> line table, else a profession of this character.
local function LineName(line)
	for name, id in pairs(ns.ProfessionSkillLines or {}) do
		if id == line then
			return name
		end
	end
	for id, prof in pairs(ns.charDB and ns.charDB.professions or {}) do
		if prof.name and ns.SkillLineOf(id) == line then
			return prof.name
		end
	end
	return (L["Profession %d"]):format(line)
end
P.LineName = LineName

-- Name and icon of a recipe from anything this account has seen: a profession's cache, the client, the
-- recipe's output item.
local function Identify(recipeID)
	local name, icon
	for _, prof in pairs(ns.charDB and ns.charDB.professions or {}) do
		local recipe = prof.recipes and prof.recipes[recipeID]
		if recipe then
			name, icon = recipe.name, recipe.icon
			break
		end
	end
	local _, output = ns.RecipeFallback(recipeID)
	local itemID = output and output.itemID
	if not name and C_Spell and C_Spell.GetSpellName then
		name = C_Spell.GetSpellName(recipeID)
	end
	if not icon and itemID and C_Item and C_Item.GetItemIconByID then
		icon = C_Item.GetItemIconByID(itemID)
	end
	return name or ("Recipe #" .. recipeID), icon, itemID
end

-- Profit per craft of the recipes in `ids`: the same figure as Make › Craft's row, so it follows the Profit
-- view's reagent cost basis (paid cost or AH, #47). Built from the rows of the profession of this character that
-- knows each recipe, once per profession. Returns profit[recipeID], basis[recipeID] (MK.ProfitBasis of the row) and
-- figures[recipeID] = the per-craft figures behind the profit: { sale, source, marked, cut, cost, profit } (#265).
local function Profits(ids)
	local byProfession, profit, basis, figures = {}, {}, {}, {}
	for _, recipeID in ipairs(ids) do
		for professionID, prof in pairs(ns.charDB and ns.charDB.professions or {}) do
			if prof.recipes and prof.recipes[recipeID] then
				if not byProfession[professionID] then
					byProfession[professionID] = {}
					for _, row in ipairs(ns.BuildRows(professionID, false, "profit")) do
						byProfession[professionID][row.recipeID] = { row.profit, MK.ProfitBasis(row),
							{ sale = row.sellsFor, source = row.sellSource, marked = row.sellMarked, cut = row.sellCut, cost = row.cost,
								profit = row.profit } }
					end
				end
				local found = byProfession[professionID][recipeID]
				profit[recipeID], basis[recipeID], figures[recipeID] = found and found[1], found and found[2], found and found[3]
				break
			end
		end
	end
	return profit, basis, figures
end

-- Which sale a figure used (#265), in words: the vendor or Junk value has no AH cut; the AH value is after the cut.
function P.SaleBasisText(f)
	if not (f and f.sale) then
		return nil
	end
	if f.marked then
		return L["vendor price (Junk mark), no AH cut"]
	elseif f.source == "vendor" then
		return L["vendor price, no AH cut"]
	elseif f.cut then
		return (L["AH after the %s%% cut"]):format(CL.FormatSeconds(f.cut * 100))
	end
	return L["AH"]
end

-- The Profit/h tooltip's second text (#265): what one craft is worth now, so a figure that differs from the profit
-- logged at craft time can be explained: "One craft now: sale 25c (vendor price, no AH cut) - reagents 17c = +8c".
function P.FiguresText(f)
	if not (f and f.sale and f.cost and f.profit) then
		return nil
	end
	return (L["One craft now: sale %s (%s) - reagents %s = %s"]):format(MK.PlainMoney(f.sale), P.SaleBasisText(f),
		MK.PlainMoney(f.cost), (f.profit < 0 and "-" or "+") .. MK.PlainMoney(math.abs(f.profit)))
end
P.Profits = Profits

-- Rows of the log behind the filters (filters = { line, char }, default the page's; the query is Make's):
-- cells in the window layout, view fields for the docked one. Unsorted: the shell sorts.
function P.Rows(now, filters)
	filters = filters or P.state
	local rows = {}
	local query = (MK.state.query or ""):lower()
	local speeds, measured = {}, {}
	for _, e in ipairs(CL.List(now, filters.char)) do
		local name, icon, itemID = Identify(e.recipeID)
		local line = ns.RecipeLine and ns.RecipeLine(e.recipeID)
		if (not filters.line or line == filters.line) and MK.Matches({ name = name }, query) then
			local view = { name = name, nameColor = "text", icon = icon, itemID = itemID, cells = {}, colors = {}, tips = {} }
			local r = { recipeID = e.recipeID, key = e.recipeID, name = name, icon = icon, itemID = itemID, view = view,
				today = e.today, week = e.week, total = e.total, before = e.before, line = line, dated = e.dated, known = e.known }
			-- Profit recorded at craft time (#215): a window shows a figure only when some craft in it had one.
			r.profitToday = e.knownToday > 0 and e.profitToday or nil
			r.profitWeek = e.knownWeek > 0 and e.profitWeek or nil
			r.profitTotal = e.known > 0 and e.profitTotal or nil
			r.knownToday, r.knownWeek = e.knownToday, e.knownWeek
			r.activeToday, r.activeWeek = e.activeToday, e.activeWeek -- active seconds (#251), nil on days without time
			r.timedToday, r.timedWeek, r.timedProfitToday = e.timedToday, e.timedWeek, e.timedProfitToday -- #273
			if e.activeToday then
				view.tips.today = { L["Today"], L["Active time: the time between crafts up to 30 s; longer pauses don't count."] }
			end
			view.cells.name, view.colors.name = name, "text"
			view.cells.today, view.colors.today = CL.Format(e.today), e.today > 0 and "text" or "text3"
			view.cells.week, view.colors.week = CL.Format(e.week), e.week > 0 and "text" or "text3"
			view.cells.total, view.colors.total = CL.Format(e.total), "text"
			view.result, view.resultColor = CL.Format(e.total), "text"
			view.sub = (L["today %s"]):format(CL.Format(e.today)) -- the docked line; the profit joins it below
			local speed = CL.Speed(e.recipeID)
			if speed then
				r.speed, r.sec, r.perHour = speed, speed.sec, speed.perHour
				-- Estimate for today's untimed crafts (#273): their count times this recipe's measured median gap. Kept
				-- apart from the measured active time, only with a median (CL.MIN_GAPS gaps), never mixed in.
				local untimed = e.today - (e.timedToday or 0)
				if untimed > 0 then
					r.untimedToday, r.estToday = untimed, untimed * speed.sec
				end
				measured[#measured + 1] = e.recipeID
			end
			speeds[e.recipeID] = r
			rows[#rows + 1] = r
		end
	end
	-- Profit per hour needs the prices: only for the recipes with a measured speed.
	if #measured > 0 then
		local profits, bases, figures = Profits(measured)
		for _, recipeID in ipairs(measured) do
			local r = speeds[recipeID]
			r.profit, r.basis, r.figures = profits[recipeID], bases[recipeID], figures[recipeID]
			r.profitHour = CL.ProfitPerHour(r.speed, r.profit)
		end
	end
	local note = L["Estimated profit at craft time: reagents at the Profit view's cost basis then, the sale at the price then. Not money received."]
	for _, r in ipairs(rows) do
		local v = r.view
		for _, w in ipairs({ { "profitToday", r.today, r.knownToday }, { "profitWeek", r.week, r.knownWeek }, { "profitTotal", r.dated, r.known } }) do
			local key, crafts, known = w[1], w[2], w[3]
			local value = r[key]
			if value ~= nil then
				local text, color = MK.Signed(value)
				v.cells[key], v.colors[key] = text .. (known < crafts and "*" or ""), color
				v.tips[key] = { L["Profit"] .. " (" .. L["est."] .. ")", note .. " " .. (L["Profit known for %d of %d crafts."]):format(known, crafts) }
			else
				v.cells[key], v.colors[key] = M.DASH, "text3"
				v.tips[key] = { L["Profit"] .. " (" .. L["est."] .. ")", note }
			end
		end
		v.cells.speed = r.speed and ((L["%s s · %s/h"]):format(CL.FormatSeconds(r.sec), CL.Format(r.perHour))) or M.DASH
		local incomplete = r.profitHour and r.basis and (r.basis.partial or r.basis.fallback)
		v.cells.profitHour = r.profitHour and ((MK.Signed(r.profitHour)) .. (incomplete and "*" or "")) or M.DASH
		v.colors.speed = r.speed and "text" or "text3"
		v.colors.profitHour = r.profitHour and select(2, MK.Signed(r.profitHour)) or "text3"
		v.tips.speed = r.speed and { L["Speed"], (L["Median of the measured gaps between two crafts, and crafts per hour, measured over %d crafts."]):format(r.speed.n) }
			or { L["Speed"], (L["Shown after %d measured crafts in a row (gaps over %d s are breaks)."]):format(CL.MIN_GAPS, CL.BREAK_SECONDS) }
		-- Docked line 2: what you made today and the profit of it (the key figures next to the total).
		v.sub = (L["today %s"]):format(CL.Format(r.today)) .. (r.profitToday and (" · " .. MK.PlainMoney(math.abs(r.profitToday))
			.. (r.profitToday < 0 and " " .. L["loss"] or "")) or "")
		local basis = r.basis or MK.ProfitBasis()
		local figures = P.FiguresText(r.figures)
		v.tips.profitHour = { L["Profit/h"] .. " " .. basis.label, L["Crafts per hour times the profit per craft (approx.): not what was earned."]
			.. (r.profitHour and basis.note and (" " .. basis.note .. " (*)") or "")
			.. (figures and ("\n" .. figures .. " " .. L["Profit today uses the prices at craft time."]) or "") }
	end
	return rows
end

-- Skill lines present in the log (unfiltered), by name: the profession menu's choices.
function P.Lines()
	local seen, out = {}, {}
	for _, e in ipairs(CL.List()) do
		local line = ns.RecipeLine and ns.RecipeLine(e.recipeID)
		if line and not seen[line] then
			seen[line] = true
			out[#out + 1] = { line, LineName(line) }
		end
	end
	table.sort(out, function(a, b)
		return a[2] < b[2]
	end)
	return out
end

local function Filtered()
	return P.state.line or P.state.char or (MK.state.query or "") ~= ""
end

local function FilterNote()
	local parts = {}
	if P.state.line then
		parts[#parts + 1] = LineName(P.state.line)
	end
	if P.state.char then
		parts[#parts + 1] = CL.CharLabel(P.state.char)
	end
	if (MK.state.query or "") ~= "" then
		parts[#parts + 1] = "\"" .. MK.state.query .. "\""
	end
	return table.concat(parts, " · ")
end

-- One short line, never longer than the footer can show (the docked footer shares its line with the filter note).
function P.Footer(docked)
	if docked then
		return L["Counts from craft events"]
	end
	local note = P.state.char and L["Undated crafts have no character: left out"]
		or L["Counts from craft events; undated in Total only"]
	return note .. " · " .. L["Profit/h"] .. " " .. MK.ProfitBasis().label .. ", " .. L["vendor/Junk sales: no cut"]
end

local SORT_NOTES = { name = L["by name"], today = L["by crafts today"], week = L["by crafts in 7 days"], total = L["by total crafts"],
	speed = L["by crafts per hour"], profitHour = L["by profit per hour"],
	profitToday = L["by profit today"], profitWeek = L["by profit in 7 days"], profitTotal = L["by total profit"] }

-- Hero tooltip (#378): the estimated profit today, over 7 days and in total (the sum of the rows, so it follows the
-- page's filters), how many crafts have a price, and what the figures are. {title, line...} or nil with no figure.
function P.HeroTip(today, anyToday, week, anyWeek, all, anyAll, priced, dated)
	if not (anyToday or anyWeek or anyAll) then
		return nil
	end
	local function Money(any, v)
		if not any then
			return M.DASH
		end
		return (v < 0 and "-" or "+") .. MK.PlainMoney(math.abs(v))
	end
	return { L["Estimated profit"],
		(L["Today %s · 7 days %s · total %s"]):format(Money(anyToday, today), Money(anyWeek, week), Money(anyAll, all)),
		(L["Total: %s of %s crafts priced (crafts with no price add nothing)."]):format(CL.Format(priced), CL.Format(dated)),
		L["Estimated: each craft valued at craft time (reagents at the Profit view's cost basis, the sale at the price then). Not money received; Sell > Ledger has the real money."] }
end

function P.Model(ctx)
	local docked = M.IsDocked(ctx)
	local rows = P.Rows()
	local today, week, total = 0, 0, 0
	local profitToday, profitWeek, anyToday, anyWeek = 0, 0, false, false
	local profitAll, anyAll, datedCrafts, pricedCrafts = 0, false, 0, 0
	local activeToday, activeWeek -- active crafting seconds (#251); nil while no day in the window was timed
	local timedToday, timedWeek, timedProfitToday = 0, 0, 0 -- crafts measured and their profit (#273)
	local untimedToday, estToday = 0, 0 -- untimed crafts that have a measured median, and their estimated seconds
	for _, r in ipairs(rows) do
		today, week, total = today + r.today, week + r.week, total + r.total
		if r.estToday then
			untimedToday, estToday = untimedToday + r.untimedToday, estToday + r.estToday
		end
		if r.activeToday then
			activeToday = (activeToday or 0) + r.activeToday
			timedToday, timedProfitToday = timedToday + r.timedToday, timedProfitToday + (r.timedProfitToday or 0)
		end
		if r.activeWeek then
			activeWeek = (activeWeek or 0) + r.activeWeek
			timedWeek = timedWeek + r.timedWeek
		end
		if r.profitToday then
			profitToday, anyToday = profitToday + r.profitToday, true
		end
		if r.profitWeek then
			profitWeek, anyWeek = profitWeek + r.profitWeek, true
		end
		-- Total: the rows' Profit total, over the dated crafts (r.dated) of which r.known had a price (#378).
		datedCrafts, pricedCrafts = datedCrafts + (r.dated or 0), pricedCrafts + (r.known or 0)
		if r.profitTotal then
			profitAll, anyAll = profitAll + r.profitTotal, true
		end
	end
	-- Active time (#251, #273): only the crafts measured count. The gold per hour is their profit over their time, never the
	-- profit of all of today's crafts; when only some crafts of the window were measured the card says how many.
	local timedText = ""
	if activeToday and activeToday >= 1 then
		timedText = " · " .. (L["%s active"]):format(CL.FormatDuration(activeToday))
		if timedToday < today then
			timedText = timedText .. " (" .. (docked and (L["%s timed"]):format(CL.Format(timedToday))
				or (L["%s of %s crafts timed"]):format(CL.Format(timedToday), CL.Format(today))) .. ")"
		end
		if timedProfitToday ~= 0 then
			timedText = timedText .. " · " .. (L["%s/h"]):format(MK.PlainMoney(math.abs(timedProfitToday) * 3600 / activeToday)
				.. (timedProfitToday < 0 and " " .. L["loss"] or ""))
		end
	end
	if estToday >= 1 and not docked then -- clearly marked, apart from the measured time (never added into it)
		timedText = timedText .. (activeToday and activeToday >= 1 and " + " or " · ") .. (L["≈ %s est. for %s untimed crafts"]):format(
			CL.FormatDuration(estToday), CL.Format(untimedToday))
		if profitToday ~= 0 then
			local seconds = (activeToday or 0) + estToday
			timedText = timedText .. " · ≈ " .. (L["%s/h"]):format(MK.PlainMoney(math.abs(profitToday) * 3600 / seconds)
				.. (profitToday < 0 and " " .. L["loss"] or "")) .. " " .. L["est."]
		end
	end
	local weekText = ""
	if not docked and activeWeek and activeWeek >= 1 then
		weekText = " (" .. (L["%s active"]):format(CL.FormatDuration(activeWeek))
			.. (timedWeek < week and (", " .. (L["%s of %s crafts timed"]):format(CL.Format(timedWeek), CL.Format(week))) or "") .. ")"
	end
	local hero
	if #rows == 0 then
		hero = MK.NoHero(L["Crafted"], Filtered() and L["nothing matches the filters."]
			or L["no crafts logged yet. Craft something and it shows here."])
	else
		hero = {
			label = L["Crafted"], name = (L["today %s"]):format(CL.Format(today)) .. timedText,
			nameColor = "text",
			-- One line: the docked layout keeps it short (no total), the window adds the total crafts.
			sub = (L["7 days %s"]):format(CL.Format(week))
				.. weekText
				.. (docked and "" or (" · " .. (L["%s crafts in total"]):format(CL.Format(total))))
				.. (anyWeek and (" · " .. (L["profit 7 days %s"]):format(MK.PlainMoney(math.abs(profitWeek)) .. (profitWeek < 0 and " " .. L["loss"] or ""))) or "")
				.. (anyAll and not docked and (" · " .. (L["total %s"]):format(MK.PlainMoney(math.abs(profitAll)) .. (profitAll < 0 and " " .. L["loss"] or ""))
					.. (pricedCrafts < datedCrafts and (" (" .. (L["%s of %s priced"]):format(CL.Format(pricedCrafts), CL.Format(datedCrafts)) .. ")") or "")) or ""),
			figureLabel = L["Estimated profit today"],
			tip = P.HeroTip(profitToday, anyToday, profitWeek, anyWeek, profitAll, anyAll, pricedCrafts, datedCrafts),
		}
		if anyToday then
			hero.figure, hero.figureColor = MK.Signed(profitToday)
		else
			hero.figure, hero.figureColor = M.DASH, "text3"
		end
	end
	return {
		rows = rows,
		hero = hero,
		listTitle = #rows == 1 and L["1 recipe"] or (L["%d recipes"]):format(#rows),
		listNote = MK.SortNote(M.Page("crafted"), SORT_NOTES),
		empty = Filtered() and L["No logged recipe matches. Clear the filter box, the profession or the character."]
			or L["No crafts logged yet. Every craft you make is counted here, per day and character."],
		footer = P.Footer(docked),
		footerRight = FilterNote(),
	}
end

----------------------------------------------------------------------------------------------------
-- Share card (#416): today's craft profit as a clean picture to screenshot. The model is pure (rows in,
-- lines out); the drawing is below. ASCII only. Same figures as the hero: the sum of the rows' profit, so
-- it follows the page's filters; active time and gold per hour only from measured crafts (a dash otherwise).
----------------------------------------------------------------------------------------------------

P.CARD_TOP = 5
local DASH = "-" -- ASCII: the page's dash is not in every font

local function SignedText(copper)
	if copper == nil then
		return DASH
	end
	return (copper < 0 and "-" or "+") .. (MK.PlainMoney(math.abs(copper)) or "0c")
end

-- Card-local compact duration for the mono face: "1h 07m", "45m", "38s" (CL.FormatDuration is spaced for body text).
function P.CompactDuration(sec)
	sec = math.floor(sec + 0.5)
	if sec >= 3600 then
		return ("%dh %02dm"):format(math.floor(sec / 3600), math.floor(sec % 3600 / 60))
	elseif sec >= 60 then
		return ("%dm"):format(math.floor(sec / 60))
	end
	return ("%ds"):format(sec)
end

-- ctx = { name, level, now, profession, char, query (filter names, nil = all), ledgerChange (copper or nil) }.
-- Returns { title, who, date, filters, empty, emptyText, figure = { value, text, negative }, figureLabel,
-- figureNote, stats = { crafts, active, perHour, timedNote }, top = { { icon, name, count, profit, text } },
-- week = { value, text }, total = { value, text }, money = { value, text, label } or nil }.
function P.CardModel(rows, ctx)
	ctx = ctx or {}
	local today, profitToday, anyToday = 0, 0, false
	local profitWeek, anyWeek, profitAll, anyAll = 0, false, 0, false
	local activeToday, timedToday, timedProfit = nil, 0, 0
	local priced = {}
	for _, r in ipairs(rows) do
		today = today + (r.today or 0)
		if r.profitToday then
			profitToday, anyToday = profitToday + r.profitToday, true
		end
		if r.profitWeek then
			profitWeek, anyWeek = profitWeek + r.profitWeek, true
		end
		if r.profitTotal then
			profitAll, anyAll = profitAll + r.profitTotal, true
		end
		if r.activeToday then
			activeToday = (activeToday or 0) + r.activeToday
			timedToday, timedProfit = timedToday + (r.timedToday or 0), timedProfit + (r.timedProfitToday or 0)
		end
		if (r.today or 0) > 0 and r.profitToday then
			priced[#priced + 1] = r
		end
	end
	table.sort(priced, function(a, b)
		if a.profitToday ~= b.profitToday then
			return a.profitToday > b.profitToday
		end
		if (a.name or "") ~= (b.name or "") then
			return (a.name or "") < (b.name or "")
		end
		return a.recipeID < b.recipeID
	end)
	local top = {}
	for i = 1, math.min(P.CARD_TOP, #priced) do
		local r = priced[i]
		top[i] = { icon = r.icon, name = r.name, count = r.today, countText = "x" .. CL.Format(r.today),
			profit = r.profitToday, text = SignedText(r.profitToday) }
	end
	local function Fig(any, v)
		return { value = any and v or nil, text = any and SignedText(v) or DASH }
	end
	-- Scope line: the profession and the search; the character is the who line.
	local scope = { ctx.profession or L["all professions"] }
	if ctx.query and ctx.query ~= "" then
		scope[#scope + 1] = "\"" .. ctx.query .. "\""
	end
	-- Who: the chosen character; with "all characters" the logged-in name and "(all characters)", because the figures
	-- cover the account and must not read as one character's.
	local who
	if ctx.char then
		who = ctx.char
	else
		who = ctx.name or ""
		if ctx.level then
			who = who .. (who ~= "" and " " or "") .. (L["level %d"]):format(ctx.level)
		end
		who = who .. (who ~= "" and " " or "") .. "(" .. L["all characters"] .. ")"
	end
	local m = {
		title = "CraftWise",
		who = who,
		date = ctx.now and date("%Y-%m-%d", ctx.now) or "",
		scope = table.concat(scope, ", "),
		empty = today == 0,
		figure = Fig(anyToday, profitToday),
		figureLabel = L["Estimated craft profit today"],
		figureNote = L["Estimated at AH prices, not money received"],
		top = top,
		week = Fig(anyWeek, profitWeek),
		total = Fig(anyAll, profitAll),
	}
	m.figure.negative = anyToday and profitToday < 0 or false
	if today == 0 then
		m.emptyText = #rows == 0 and L["Nothing crafted yet."] or L["Nothing crafted today."]
	end
	local hasActive = activeToday and activeToday >= 1
	m.stats = {
		crafts = CL.Format(today),
		active = hasActive and P.CompactDuration(activeToday) or DASH,
		perHour = (hasActive and timedProfit ~= 0) and (SignedText(timedProfit * 3600 / activeToday) .. "/h") or DASH,
		perHourValue = (hasActive and timedProfit ~= 0) and timedProfit or nil,
	}
	if hasActive and timedToday < today then
		m.stats.timedNote = (L["%s of %s crafts timed"]):format(CL.Format(timedToday), CL.Format(today))
	end
	if ctx.ledgerChange ~= nil then
		m.money = { value = ctx.ledgerChange, text = SignedText(ctx.ledgerChange), label = L["Gold change today"] }
	end
	return m
end

-- The context of the live card: this character, the page's filters, the ledger's day.
function P.CardContext(now)
	local ctx = { now = now or time(), query = MK.state.query }
	ctx.name = UnitName and UnitName("player")
	ctx.level = UnitLevel and UnitLevel("player")
	ctx.profession = P.state.line and LineName(P.state.line) or nil
	ctx.char = P.state.char and CL.CharLabel(P.state.char) or nil
	local sum = ns.Ledger and ns.Ledger.Summary and ns.Ledger.Summary("today")
	ctx.ledgerChange = sum and sum.change or nil
	return ctx
end

-- Layout (#418, pure): y (down from the card's top) and height of every element, from the model. One rhythm: 16 above
-- and below every rule, 4 from a label to its value, 20 between the hero and the stats, 10 from the list label to its
-- first row. The card is as tall as its content. Numbers agreed with the design review (2026-11-23): with n recipe
-- rows and the timed note t = 16, the height is 371 + t + 26 n.
local CARD = { W = 440, PAD = 24, ROW = 26, ROW_H = 24, RULE_GAP = 16 }
P.CARD = CARD

function P.CardLayout(m)
	local E, order, rules = {}, {}, {}
	local function Put(name, y, h)
		E[name] = { y = y, h = h }
		order[#order + 1] = name
	end
	local pad, g = CARD.PAD, CARD.RULE_GAP
	Put("title", pad, 19)
	Put("who", pad + 25, 14)
	Put("scope", pad + 41, 12)
	rules[1] = 93
	local y, bottom = rules[1] + g, nil
	local rows = 0
	if m.empty then
		Put("empty", y, 16)
		bottom = y + 16
	else
		Put("heroLabel", y, 12)
		Put("hero", y + 16, 40)
		Put("heroNote", y + 60, 12)
		local s = y + 72 + 20
		Put("statCaps", s, 12)
		Put("statVals", s + 16, 15)
		bottom = s + 31
		if m.stats.timedNote then
			Put("timedNote", bottom + 4, 12)
			bottom = bottom + 16
		end
		rows = #m.top
		if rows > 0 then
			rules[#rules + 1] = bottom + g
			local ly = bottom + g + g
			Put("listLabel", ly, 12)
			local first = ly + 12 + 10
			for i = 1, rows do
				Put("row" .. i, first + (i - 1) * CARD.ROW, CARD.ROW_H)
			end
			bottom = first + (rows - 1) * CARD.ROW + CARD.ROW_H
		end
	end
	rules[#rules + 1] = bottom + g
	Put("bottomCaps", bottom + 2 * g, 12)
	Put("bottomVals", bottom + 2 * g + 16, 15)
	return { width = CARD.W, height = bottom + 2 * g + 16 + 15 + pad, elements = E, order = order, rules = rules, rows = rows }
end

local GOLD, SILVER = 10000, 100

-- A copper amount as its two largest units: "75g", "5s" (nil when there is no second one). Plain text; positive amounts
-- get the coin colours as everywhere else, a loss stays plain (drawn in the danger colour).
local function Units(copper, colored)
	copper = math.floor(math.abs(copper) + 0.5)
	local units = { { math.floor(copper / GOLD), "g", "coinGold" }, { math.floor((copper % GOLD) / SILVER), "s", "coinSilver" },
		{ copper % SILVER, "c", "coinCopper" } }
	local first = 3
	for i = 1, 3 do
		if units[i][1] > 0 then
			first = i
			break
		end
	end
	local parts = {}
	for i = first, math.min(first + 1, 3) do
		local u = units[i]
		if i == first or u[1] > 0 then
			local text = u[1] .. u[2]
			parts[#parts + 1] = colored and (Style.Hex(u[3]) .. text .. "|r") or text
		end
	end
	return parts[1], parts[2]
end

-- Signed money like MK.Signed: a gain "+" in coin colours, a loss ASCII "-" in the danger colour; a dash without a value.
local function Money(fs, v)
	local name = "text"
	if v == nil then
		fs:SetText(DASH)
		name = "text3"
	elseif v < 0 then
		fs:SetText("-" .. (MK.PlainMoney(-v) or "0c"))
		name = "danger"
	else
		fs:SetText("+" .. (ns.FormatCoins(v) or "0c"))
	end
	local c = Style.Color(name)
	fs:SetTextColor(c[1], c[2], c[3], 1)
end

local function BuildCard()
	local f = CreateFrame("Frame", "CraftWiseShareCard", UIParent)
	-- No cwWindow: the card stays opaque, whatever Settings > Look gives the main window.
	f:SetWidth(CARD.W)
	f:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
	f:SetFrameStrata("DIALOG")
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	Style.Sheet(f, Style.C.sheet, Style.C.flap, 22, true)
	local inner = CARD.W - 2 * CARD.PAD
	f.key = Style.KeyIcon(f, 20)
	f.title = Style.Text(f, "Brand", "text")
	f.title:SetPoint("LEFT", f.key, "RIGHT", 8, 0)
	-- The Close chip only shows while the mouse is over the card, so it is not in the screenshot. Esc closes too.
	f.close = Style.Chip(f, L["Close"])
	f.close:Hide()
	f.close:SetScript("OnClick", function()
		f:Hide()
	end)
	local function Leave()
		if not f:IsMouseOver() then
			f.close:Hide()
		end
	end
	f:SetScript("OnEnter", function()
		f.close:Show()
	end)
	f:SetScript("OnLeave", Leave)
	f.close:HookScript("OnLeave", Leave)
	f:SetScript("OnHide", function()
		f.close:Hide()
	end)
	f.who = Style.Text(f, "Body", "text2")
	f.scope = Style.Text(f, "Caption", "text3")
	for _, fs in ipairs({ f.who, f.scope }) do
		fs:SetWidth(inner)
		fs:SetWordWrap(false)
		fs:SetJustifyH("LEFT")
	end
	f.heroLabel = Style.Text(f, "Label", "text3")
	f.hero = Style.Text(f, "FigureXL", "text")
	f.heroSub = Style.Text(f, "FigureL", "text") -- the second unit, smaller: no wide gap of the mono face
	f.heroSub:SetPoint("BOTTOMLEFT", f.hero, "BOTTOMRIGHT", 6, 3)
	f.heroNote = Style.Text(f, "Caption", "text3")
	f.statCaps, f.stats = {}, {}
	for i, label in ipairs({ L["Crafts today"], L["Active time"], L["Gold per active hour"] }) do
		f.statCaps[i] = Style.Text(f, "Caption", "text3")
		f.statCaps[i]:SetText(label)
		f.stats[i] = Style.Text(f, "FigureBold", "text")
	end
	f.timedNote = Style.Text(f, "Caption", "text3")
	f.rules = {}
	f.listLabel = Style.Text(f, "Label", "text3")
	f.listLabel:SetText(L["Top recipes today"])
	f.empty = Style.Text(f, "Section", "text2")
	f.rows = {}
	for i = 1, P.CARD_TOP do
		local row = CreateFrame("Frame", nil, f)
		row:SetHeight(CARD.ROW_H)
		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(20, 20)
		row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
		row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		row.profit = Style.Text(row, "FigureBold", "text")
		row.profit:SetPoint("RIGHT", row, "RIGHT", 0, 0)
		row.profit:SetJustifyH("RIGHT")
		row.count = Style.Text(row, "Figure", "text2")
		row.count:SetJustifyH("RIGHT")
		row.name = Style.Text(row, "Body", "text")
		row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
		row.name:SetJustifyH("LEFT")
		row.name:SetWordWrap(false)
		f.rows[i] = row
	end
	f.bottomCaps, f.bottom = {}, {}
	for i, label in ipairs({ L["Profit, last 7 days"], L["Profit, total"], L["Gold change today"] }) do
		f.bottomCaps[i] = Style.Text(f, "Caption", "text3")
		f.bottomCaps[i]:SetText(label)
		f.bottom[i] = Style.Text(f, "FigureBold", "text")
	end
	if UISpecialFrames then
		table.insert(UISpecialFrames, "CraftWiseShareCard") -- Escape closes it
	end
	f:Hide()
	return f
end

local function Width(fs)
	return fs.GetStringWidth and fs:GetStringWidth() or 0
end

function P.PaintCard(f, m)
	local lay = P.CardLayout(m)
	local E, pad = lay.elements, CARD.PAD
	local colW = math.floor((CARD.W - 2 * pad) / 3)
	local function At(region, name, x, dy)
		region:ClearAllPoints()
		region:SetPoint("TOPLEFT", f, "TOPLEFT", pad + (x or 0), -(E[name].y + (dy or 0)))
	end
	f:SetHeight(lay.height)
	f.key:ClearAllPoints()
	f.key:SetPoint("TOPLEFT", f, "TOPLEFT", pad, -E.title.y)
	f.title:SetText(m.title)
	f.close:ClearAllPoints()
	f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -pad, -E.title.y)
	At(f.who, "who")
	f.who:SetText(m.who)
	At(f.scope, "scope")
	f.scope:SetText(m.scope .. "  -  " .. m.date)
	for i, y in ipairs(lay.rules) do
		if not f.rules[i] then
			f.rules[i] = Style.Rule(f, "H")
		end
		local rule = f.rules[i]
		rule:ClearAllPoints()
		rule:SetPoint("TOPLEFT", f, "TOPLEFT", pad, -y)
		rule:SetPoint("TOPRIGHT", f, "TOPRIGHT", -pad, -y)
		rule:Show()
	end
	for i = #lay.rules + 1, #f.rules do
		f.rules[i]:Hide()
	end
	-- Hero, stats and the list; an empty day shows one sentence in their place.
	local live = not m.empty
	for _, region in ipairs({ f.heroLabel, f.hero, f.heroSub, f.heroNote, f.timedNote, f.listLabel }) do
		region:SetShown(live)
	end
	for i = 1, 3 do
		f.statCaps[i]:SetShown(live)
		f.stats[i]:SetShown(live)
	end
	f.empty:SetShown(m.empty)
	if m.empty then
		At(f.empty, "empty")
		f.empty:SetText(m.emptyText)
	else
		At(f.heroLabel, "heroLabel")
		f.heroLabel:SetText(m.figureLabel)
		At(f.hero, "hero")
		local v = m.figure.value
		local main, sub = DASH, nil
		local color = "text3"
		if v ~= nil then
			main, sub = Units(v, v >= 0)
			main = (v < 0 and "-" or "+") .. main
			color = v < 0 and "danger" or "text"
		end
		f.hero:SetText(main)
		f.heroSub:SetText(sub or "")
		local c = Style.Color(color)
		f.hero:SetTextColor(c[1], c[2], c[3], 1)
		f.heroSub:SetTextColor(c[1], c[2], c[3], 1)
		At(f.heroNote, "heroNote")
		f.heroNote:SetText(m.figureNote)
		for i = 1, 3 do
			At(f.statCaps[i], "statCaps", (i - 1) * colW)
			At(f.stats[i], "statVals", (i - 1) * colW)
		end
		f.stats[1]:SetText(m.stats.crafts)
		f.stats[2]:SetText(m.stats.active)
		f.stats[3]:SetText(m.stats.perHour)
		local pc = Style.Color(m.stats.perHourValue and m.stats.perHourValue < 0 and "danger" or m.stats.perHourValue and "text" or "text3")
		f.stats[3]:SetTextColor(pc[1], pc[2], pc[3], 1)
		f.timedNote:SetShown(m.stats.timedNote ~= nil)
		if m.stats.timedNote then
			At(f.timedNote, "timedNote", colW)
			f.timedNote:SetText(m.stats.timedNote)
		end
		f.listLabel:SetShown(lay.rows > 0)
		if lay.rows > 0 then
			At(f.listLabel, "listLabel")
		end
	end
	-- Rows: the profit and count columns are as wide as the widest value on screen, right-aligned.
	local profitW, countW = 0, 0
	for i, row in ipairs(f.rows) do
		local t = live and m.top[i]
		row:SetShown(t and true or false)
		if t then
			row.name:SetText(t.name)
			row.count:SetText(t.countText)
			Money(row.profit, t.profit)
			profitW, countW = math.max(profitW, Width(row.profit)), math.max(countW, Width(row.count))
		end
	end
	for i, row in ipairs(f.rows) do
		local t = live and m.top[i]
		if t then
			local e = E["row" .. i]
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", f, "TOPLEFT", pad, -e.y)
			row:SetPoint("TOPRIGHT", f, "TOPRIGHT", -pad, -e.y)
			row.icon:SetTexture(t.icon)
			row.profit:SetWidth(profitW)
			row.count:ClearAllPoints()
			row.count:SetPoint("RIGHT", row, "RIGHT", -(profitW + 12), 0)
			row.count:SetWidth(countW)
			row.name:ClearAllPoints()
			row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
			row.name:SetPoint("RIGHT", row, "RIGHT", -(profitW + 12 + countW + 10), 0) -- cut before the count and the profit
		end
	end
	-- Bottom row on the stats' columns: 7 days, total, and the real money change of today (apart from the estimates).
	local figures = { m.week.value, m.total.value, m.money and m.money.value or nil }
	for i = 1, 3 do
		local show = i < 3 or m.money ~= nil
		f.bottomCaps[i]:SetShown(show)
		f.bottom[i]:SetShown(show)
		if show then
			At(f.bottomCaps[i], "bottomCaps", (i - 1) * colW)
			At(f.bottom[i], "bottomVals", (i - 1) * colW)
			Money(f.bottom[i], figures[i])
		end
	end
end

function P.ShowCard()
	if not P.card then
		P.card = BuildCard()
	end
	P.PaintCard(P.card, P.CardModel(P.Rows(time()), P.CardContext(time())))
	P.card:Show()
	P.card:Raise()
end
ns.OpenShareCard = P.ShowCard

-- Row tooltip: the crafted item, then the log lines (per character, undated part).
function P.RowTooltip(owner, r)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	if r.itemID and GameTooltip.SetItemByID then
		GameTooltip:SetItemByID(r.itemID)
		GameTooltip:AddLine(" ")
	else
		GameTooltip:AddLine(r.name)
	end
	local lines = CL.Lines(r.recipeID)
	if lines then
		GameTooltip:AddLine(lines.headline, 1, 1, 1)
		for _, ch in ipairs(lines.chars) do
			GameTooltip:AddDoubleLine("  " .. ch.name, ch.text, 0.8, 0.8, 0.8, 1, 1, 1)
		end
		if lines.earlier then
			GameTooltip:AddLine("  " .. lines.earlier, 0.6, 0.6, 0.6)
		end
		if lines.before then
			GameTooltip:AddLine("  " .. lines.before .. " - " .. L["counted before the log, no date, no character"], 0.6, 0.6, 0.6, true)
		end
		MK.AddProfitLines(lines)
		MK.AddSpeedLines(lines.speed, r.profit, r.basis)
	end
	GameTooltip:Show()
end

----------------------------------------------------------------------------------------------------
-- Tools: Make's filter box with the profession chip choosing "all" or one profession, and a character chip
----------------------------------------------------------------------------------------------------

local ALL = "all"

function P.SetLine(id)
	P.state.line = id ~= ALL and id or nil
	M.Refresh()
end

function P.SetChar(id)
	P.state.char = id ~= ALL and id or nil
	M.Refresh()
end

local function Toggle(chip, build, current, onPick)
	local menu = MK.Menu()
	if menu and menu:IsShown() and menu.anchor == chip then
		menu:Hide()
		return
	end
	MK.ShowChoiceMenu(chip, build(), current, onPick)
end

function P.BuildTools(slot)
	MK.BuildTools(slot)
	slot.profession:SetScript("OnClick", function(self)
		Toggle(self, function()
			local entries = { { ALL, L["All professions"] } }
			for _, e in ipairs(P.Lines()) do
				entries[#entries + 1] = e
			end
			return entries
		end, P.state.line or ALL, P.SetLine)
	end)
	slot.profession:HookScript("OnEnter", function(self)
		Style.ShowTip(self, L["Profession"], L["Show the crafts of one profession, or all."])
	end)
end

function P.UpdateTools(slot)
	local chip, box = slot.profession, slot.filter
	chip:SetLabel((P.state.line and LineName(P.state.line) or L["All professions"]) .. " " .. Style.Glyph("down", 9, "text2"))
	chip.label:SetTextColor(Style.C.text[1], Style.C.text[2], Style.C.text[3], 1)
	if (box:GetText() or "") ~= MK.state.query then
		box.cwSetting = true
		box:SetText(MK.state.query)
		box.cwSetting = false
	end
	box.hint:SetShown(MK.state.query == "")
end

function P.ListTools(slot)
	local chip = Style.Chip(slot, "")
	slot.char = chip
	chip:SetPoint("RIGHT", slot, "RIGHT", 0, 0)
	local share = Style.Chip(slot, L["Share card"])
	slot.share = share
	share:SetPoint("RIGHT", chip, "LEFT", -8, 0)
	share:SetScript("OnClick", function()
		P.ShowCard()
	end)
	share:HookScript("OnEnter", function(self)
		Style.ShowTip(self, L["Share card"], L["A clean picture of today's craft profit to screenshot. Also /craftwise card."])
	end)
	share:HookScript("OnLeave", function(self)
		Style.HideTip(self)
	end)
	chip:SetScript("OnClick", function(self)
		Toggle(self, function()
			local entries = { { ALL, L["All characters"] } }
			for _, key in ipairs(CL.Characters()) do
				entries[#entries + 1] = { key, CL.CharLabel(key) }
			end
			return entries
		end, P.state.char or ALL, P.SetChar)
	end)
	chip:HookScript("OnEnter", function(self)
		Style.ShowTip(self, L["Character"], L["Count the crafts of one character, or all. Crafts counted before the log have no character."])
	end)
	chip:HookScript("OnLeave", function(self)
		Style.HideTip(self)
	end)
end

function P.UpdateListTools(slot)
	slot.char:SetLabel((P.state.char and CL.CharLabel(P.state.char) or L["All characters"]) .. " " .. Style.Glyph("down", 9, "text2"))
end

M.RegisterPage({
	key = "crafted", section = "make", label = L["Crafted"], order = 5, title = L["Crafted"],
	events = { "CRAFTLOG_CHANGED", "BAGS_CHANGED" }, -- BAGS_CHANGED: an item mark changed (#214)
	columns = COLUMNS,
	rowHeight = 34,
	sort = { key = "today", desc = true },
	Model = P.Model,
	SortRows = P.SortRows,
	Tools = P.BuildTools,
	UpdateTools = P.UpdateTools,
	ListTools = P.ListTools,
	UpdateListTools = P.UpdateListTools,
	RowTooltip = P.RowTooltip,
})
