-- Main window, Make › Crafted (#205): how many times each recipe was crafted, from the craft log
-- (Crafts.lua, ns.CraftLog). One row per logged recipe: crafts today, in the last 7 days and in total over
-- every character of this account. The total includes the undated crafts counted before the log existed
-- (the tooltip says how many). Hover a row for the split per character. Not tied to a profession.
local _, ns = ...
local M = ns.Main
local MK = M.Make
local Style, L = ns.Style, ns.L
local CL = ns.CraftLog

local P = {}
M.CraftedPage = P

local COLUMNS = {
	{ key = "icon", icon = true, width = 22 },
	MK.Column("name", L["Recipe"], 300, "LEFT", "Body", false),
	MK.Column("today", L["Today"], 90, "RIGHT", "Figure"),
	MK.Column("week", L["7 days"], 90, "RIGHT", "Figure"),
	MK.Column("total", L["Total"], 110, "RIGHT", "FigureBold"),
}
P.COLUMNS = COLUMNS

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

-- Rows of the log (pure over CL.List): cells in the window layout, view fields for the docked one.
function P.Rows(now)
	local rows = {}
	for _, e in ipairs(CL.List(now)) do
		local name, icon, itemID = Identify(e.recipeID)
		local view = { name = name, nameColor = "text", icon = icon, itemID = itemID, cells = {}, colors = {}, tips = {} }
		local r = { recipeID = e.recipeID, key = e.recipeID, name = name, icon = icon, itemID = itemID, view = view,
			today = e.today, week = e.week, total = e.total, before = e.before }
		view.cells.name, view.colors.name = name, "text"
		view.cells.today, view.colors.today = CL.Format(e.today), e.today > 0 and "text" or "text3"
		view.cells.week, view.colors.week = CL.Format(e.week), e.week > 0 and "text" or "text3"
		view.cells.total, view.colors.total = CL.Format(e.total), "text"
		view.result, view.resultColor = CL.Format(e.total), "text"
		view.sub = (L["today %s"]):format(CL.Format(e.today)) .. " · " .. (L["7 days %s"]):format(CL.Format(e.week))
		rows[#rows + 1] = r
	end
	return rows
end

function P.Model()
	local rows = P.Rows()
	local today, week, total = 0, 0, 0
	for _, r in ipairs(rows) do
		today, week, total = today + r.today, week + r.week, total + r.total
	end
	local hero
	if #rows == 0 then
		hero = MK.NoHero(L["Crafted"], L["no crafts logged yet. Craft something and it shows here."])
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
		listNote = L["by crafts today, then 7 days"],
		empty = L["No crafts logged yet. Every craft you make is counted here, per day and character."],
		footer = L["Counts come from craft events. Crafts counted before the log existed have no date and show in the total only."],
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
			GameTooltip:AddLine("  " .. lines.before .. " - counted before the log, no date, no character", 0.6, 0.6, 0.6, true)
		end
	end
	GameTooltip:Show()
end

M.RegisterPage({
	key = "crafted", section = "make", label = L["Crafted"], order = 5, title = L["Crafted"],
	events = { "CRAFTLOG_CHANGED" },
	columns = COLUMNS,
	rowHeight = 34,
	sort = { key = "today", desc = true },
	Model = P.Model,
	RowTooltip = P.RowTooltip,
})
