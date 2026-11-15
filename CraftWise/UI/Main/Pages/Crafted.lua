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

function P.Model(ctx)
	local docked = M.IsDocked(ctx)
	local rows = P.Rows()
	local today, week, total = 0, 0, 0
	local profitToday, profitWeek, anyToday, anyWeek = 0, 0, false, false
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
				.. (anyWeek and (" · " .. (L["profit 7 days %s"]):format(MK.PlainMoney(math.abs(profitWeek)) .. (profitWeek < 0 and " " .. L["loss"] or ""))) or ""),
			figureLabel = L["Estimated profit today"],
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
