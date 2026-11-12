-- Main window, Make › Learn (#154; spec in #150 "Make", board "Make › Learn"): recipes you don't know yet,
-- where to get them and when they pay off. Hero: the recipe you can learn now that pays off in the fewest
-- crafts, ties to the higher profit (ns.HeroCards.BestToLearn). Columns: Recipe (white: not learned yet),
-- Skill (orange when above yours), Where to get it, To learn, Profit/craft, Pays off. Chips: Fits my skill,
-- Hide unpriced. A missing learn cost says "unknown" and Pays off shows "—".
local _, ns = ...
local M = ns.Main
local MK = M.Make
local Style, L = ns.Style, ns.L

local LearnPage = {}
M.LearnPage = LearnPage

local COLUMNS = {
	{ key = "icon", icon = true, width = 22 },
	MK.Column("name", L["Recipe"], 200, "LEFT", "Body", true),
	MK.Column("required", L["Skill"], 56, "RIGHT", "Figure", true),
	MK.Column("where", L["Where to get it"], nil, "LEFT", "Small"),
	MK.Column("learnCost", L["To learn"], 80, "RIGHT", "Figure", true),
	MK.Column("profit", L["Profit/craft"], 92, "RIGHT", "Figure", true),
	MK.Column("breakEven", L["Pays off"], 70, "RIGHT", "Figure", true),
}
LearnPage.COLUMNS = COLUMNS

-- "Trainer · Una, Thunder Bluff [seen] +2": the first source, its label when seen in game, how many more.
function LearnPage.WhereText(r)
	if not r.whereText then
		return nil
	end
	local more = r.where and #r.where > 1 and (" " .. Style.Hex("text3") .. "+" .. (#r.where - 1) .. "|r") or ""
	return r.whereText .. (r.whereLabel and (" " .. Style.Hex("text3") .. r.whereLabel .. "|r") or "") .. more
end

function LearnPage.View(r, ctx)
	local view = MK.NewView(r, r.outputItemID)
	view.nameColor = "text" -- white: not learned yet
	local c, k, t = view.cells, view.colors, view.tips
	if r.required then
		c.required, k.required = tostring(r.required), r.tooLow and "skill.orange" or "text"
		if r.tooLow then
			t.required = { L["Above your skill"], (L["Needs %d."]):format(r.required) }
		end
	else
		c.required, k.required = L["unknown"], "text3"
		t.required = { L["Required skill unknown"], L["Not in the recipe data and not seen at a trainer yet."] }
	end
	c.where = LearnPage.WhereText(r) or L["Not known yet"]
	k.where = r.whereText and "text2" or "text3"
	if r.learnCost then
		c.learnCost, k.learnCost = ns.FormatCoins(r.learnCost), "text"
	else
		c.learnCost, k.learnCost = L["unknown"], "text3"
		t.learnCost = { L["Learn cost unknown"], L["No trainer fee, vendor price or AH price recorded for it yet."] }
	end
	if r.profit then
		c.profit, k.profit = MK.Signed(r.profit)
	else
		c.profit, k.profit = M.NoPriceText(), "text3"
		t.profit = MK.WhyNoPrice(r, ctx)
	end
	if r.breakEven then
		c.breakEven, k.breakEven = (r.breakEven == 1 and L["1 craft"] or (L["%d crafts"]):format(r.breakEven)), "text2"
	else
		c.breakEven, k.breakEven = M.DASH, "text3"
	end
	view.rail = r.profit and { value = r.profit, zeroAt = 0.18 } or nil
	view.result, view.resultColor = c.profit, k.profit
	view.sub = c.breakEven
	return MK.Attach(r, view)
end

local SORT_NOTES = { profit = L["by profit"], name = L["by name"], required = L["by skill"],
	learnCost = L["by learn cost"], breakEven = L["by crafts to pay off"] }

function LearnPage.Hero(all, ctx)
	local h, why = ns.HeroCards.BestToLearn(all)
	local label = L["Best recipe to learn"]
	if not h then
		return MK.NoHero(label, why)
	end
	local sub = {}
	if h.whereText then
		sub[#sub + 1] = h.whereText
	end
	sub[#sub + 1] = (L["you meet skill %d"]):format(h.required)
	return {
		label = label, name = h.name, nameColor = "text", sub = table.concat(sub, " · "),
		figureLabel = L["Pays off after"], figure = tostring(h.breakEven),
		figureUnit = h.breakEven == 1 and L["craft"] or L["crafts"], data = h,
	}
end

-- The middle: "Learn cost" and the fee.
local function DrawHero(_, hero, _, slot)
	local frame = slot
	if not frame then
		return
	end
	if not frame.cw then
		frame.cw = true
		frame.label = Style.Text(frame, "Label", "text3")
		frame.label:SetPoint("LEFT", frame, "LEFT", 0, 8)
		frame.label:SetText(L["Learn cost"])
		frame.value = Style.Text(frame, "FigureBold", "text")
		frame.value:SetPoint("TOPLEFT", frame.label, "BOTTOMLEFT", 0, -2)
	end
	local h = hero and hero.data
	frame.label:SetShown(h ~= nil)
	frame.value:SetShown(h ~= nil)
	if h then
		frame.value:SetText(ns.FormatCoins(h.learnCost))
	end
end

function LearnPage.Model(ctx)
	local s = ns.db.settings
	local rows, hidden, all = MK.LearnRows(ctx.professionID, s)
	local values = {}
	for i, r in ipairs(rows) do
		LearnPage.View(r, ctx)
		values[i] = r.profit
	end
	ctx.railMax = Style.SharedScale(values)
	return {
		rows = rows,
		hero = LearnPage.Hero(all, ctx),
		listTitle = (L["%d recipes you don't know"]):format(#rows),
		listNote = MK.SortNote(M.Page("learn"), SORT_NOTES),
		empty = L["No recipes match. Clear the filter or turn off Fits my skill."],
		footer = L["Sources: bundled data + what CraftWise recorded at trainers and vendors · skill shown orange when you are below it"],
		footerRight = (hidden > 0 and ((L["%d hidden by the chips"]):format(hidden) .. " · ") or "") .. MK.BasisNote("learn", rows),
	}
end

M.RegisterPage({
	key = "learn", section = "make", label = L["Learn"], order = 2, title = L["Learn"],
	profession = true, prices = true,
	events = { "LEDGER_CHANGED" },
	columns = COLUMNS,
	sort = { key = "profit", desc = true },
	Model = LearnPage.Model,
	Hero = DrawHero,
	Tools = MK.BuildTools,
	UpdateTools = MK.UpdateTools,
	ListTools = function(slot)
		slot.chips = {
			MK.SettingChip(slot, L["Fits my skill"], "learnFitsSkill", L["Only recipes whose required skill is known and at or below yours."]),
			MK.SettingChip(slot, L["Hide unpriced"], "hideUnpriced", L["Leave out recipes without a profit; the footer counts them."]),
		}
		MK.LayoutChips(slot, slot.chips)
	end,
	UpdateListTools = function(slot)
		MK.UpdateChips(slot.chips)
	end,
	Open = function(content, r, ctx)
		local where = {}
		for i, w in ipairs(r.where or {}) do
			if i > 6 then
				break
			end
			where[i] = { text = w.text, label = w.label }
		end
		MK.DrawOpen(content, r, { where = where }, ctx)
	end,
	OpenHeight = function(r, ctx)
		return MK.OpenHeight(r, math.min(#(r.where or {}), 6), ctx)
	end,
	RowTooltip = function(owner, r)
		MK.ShowRecipeTooltip(owner, r, "learn")
	end,
})
