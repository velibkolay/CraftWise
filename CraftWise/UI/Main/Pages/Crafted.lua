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

local COLUMNS = {
	{ key = "icon", icon = true, width = 22 },
	MK.Column("name", L["Recipe"], 210, "LEFT", "Body", true),
	MK.Column("today", L["Today"], 62, "RIGHT", "Figure", true),
	MK.Column("week", L["7 days"], 62, "RIGHT", "Figure", true),
	MK.Column("total", L["Total"], 80, "RIGHT", "FigureBold", true),
	MK.Column("sec", L["Sec/craft"], 76, "RIGHT", "Figure", true),
	MK.Column("perHour", L["Crafts/h"], 70, "RIGHT", "Figure", true),
	MK.Column("profitHour", L["Profit/h"], 96, "RIGHT", "Figure", true),
}
P.COLUMNS = COLUMNS

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
	table.sort(rows, P.Compare(key or "today", desc ~= false))
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
-- knows each recipe, once per profession. Returns profit[recipeID] and basis[recipeID] (MK.ProfitBasis of the row).
local function Profits(ids)
	local byProfession, profit, basis = {}, {}, {}
	for _, recipeID in ipairs(ids) do
		for professionID, prof in pairs(ns.charDB and ns.charDB.professions or {}) do
			if prof.recipes and prof.recipes[recipeID] then
				if not byProfession[professionID] then
					byProfession[professionID] = {}
					for _, row in ipairs(ns.BuildRows(professionID, false, "profit")) do
						byProfession[professionID][row.recipeID] = { row.profit, MK.ProfitBasis(row) }
					end
				end
				local found = byProfession[professionID][recipeID]
				profit[recipeID], basis[recipeID] = found and found[1], found and found[2]
				break
			end
		end
	end
	return profit, basis
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
				today = e.today, week = e.week, total = e.total, before = e.before, line = line }
			view.cells.name, view.colors.name = name, "text"
			view.cells.today, view.colors.today = CL.Format(e.today), e.today > 0 and "text" or "text3"
			view.cells.week, view.colors.week = CL.Format(e.week), e.week > 0 and "text" or "text3"
			view.cells.total, view.colors.total = CL.Format(e.total), "text"
			view.result, view.resultColor = CL.Format(e.total), "text"
			view.sub = (L["today %s"]):format(CL.Format(e.today)) .. " · " .. (L["7 days %s"]):format(CL.Format(e.week))
			local speed = CL.Speed(e.recipeID)
			if speed then
				r.speed, r.sec, r.perHour = speed, speed.sec, speed.perHour
				measured[#measured + 1] = e.recipeID
			end
			speeds[e.recipeID] = r
			rows[#rows + 1] = r
		end
	end
	-- Profit per hour needs the prices: only for the recipes with a measured speed.
	if #measured > 0 then
		local profits, bases = Profits(measured)
		for _, recipeID in ipairs(measured) do
			local r = speeds[recipeID]
			r.profit, r.basis = profits[recipeID], bases[recipeID]
			r.profitHour = CL.ProfitPerHour(r.speed, r.profit)
		end
	end
	for _, r in ipairs(rows) do
		local v = r.view
		v.cells.sec = r.speed and CL.FormatSeconds(r.sec) or M.DASH
		v.cells.perHour = r.speed and CL.Format(r.perHour) or M.DASH
		local incomplete = r.profitHour and r.basis and (r.basis.partial or r.basis.fallback)
		v.cells.profitHour = r.profitHour and ((MK.Signed(r.profitHour)) .. (incomplete and "*" or "")) or M.DASH
		v.colors.sec, v.colors.perHour = r.speed and "text" or "text3", r.speed and "text" or "text3"
		v.colors.profitHour = r.profitHour and select(2, MK.Signed(r.profitHour)) or "text3"
		v.tips.sec = r.speed and { L["Sec/craft"], (L["Median of the measured gaps between two crafts, measured over %d crafts."]):format(r.speed.n) }
			or { L["Sec/craft"], (L["Shown after %d measured crafts in a row (gaps over %d s are breaks)."]):format(CL.MIN_GAPS, CL.BREAK_SECONDS) }
		local basis = r.basis or MK.ProfitBasis()
		v.tips.profitHour = { L["Profit/h"] .. " " .. basis.label, L["Crafts per hour times the profit per craft (approx.): not what was earned."]
			.. (r.profitHour and basis.note and (" " .. basis.note .. " (*)") or "") }
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

local SORT_NOTES = { name = L["by name"], today = L["by crafts today"], week = L["by crafts in 7 days"], total = L["by total crafts"],
	sec = L["by seconds per craft"], perHour = L["by crafts per hour"], profitHour = L["by profit per hour"] }

function P.Model()
	local rows = P.Rows()
	local today, week, total = 0, 0, 0
	for _, r in ipairs(rows) do
		today, week, total = today + r.today, week + r.week, total + r.total
	end
	local hero
	if #rows == 0 then
		hero = MK.NoHero(L["Crafted"], Filtered() and L["nothing matches the filters."]
			or L["no crafts logged yet. Craft something and it shows here."])
	else
		hero = {
			label = L["Crafted"], name = (L["today %s"]):format(CL.Format(today)), nameColor = "text",
			sub = (L["7 days %s"]):format(CL.Format(week)) .. " · " .. (L["%s crafts in total"]):format(CL.Format(total)),
		}
	end
	return {
		rows = rows,
		hero = hero,
		listTitle = #rows == 1 and L["1 recipe"] or (L["%d recipes"]):format(#rows),
		listNote = MK.SortNote(M.Page("crafted"), SORT_NOTES),
		empty = Filtered() and L["No logged recipe matches. Clear the filter box, the profession or the character."]
			or L["No crafts logged yet. Every craft you make is counted here, per day and character."],
		footer = L["Counts come from craft events. Crafts counted before the log existed have no date and show in the total only."]
			.. " · " .. L["Profit/h"] .. " " .. MK.ProfitBasis().label
			.. (P.state.char and (" · " .. L["The undated crafts have no character: they are left out while one character is chosen."]) or ""),
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
	events = { "CRAFTLOG_CHANGED" },
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
