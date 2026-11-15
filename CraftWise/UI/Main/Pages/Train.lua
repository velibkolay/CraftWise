-- Main window, Make › Train (#259): the class spells this character can learn from its trainer, recorded
-- first-hand (ClassSpells.lua), grouped by when: Learn now (level met, not known), then the spells of
-- higher levels, then what you know. Hero: how many you can learn now and what they cost together.
-- A trainer lists only the band that fits your level, so the list grows as you level and visit; the
-- footer says how far the record reaches and that anything beyond needs a trainer visit. Nothing is
-- guessed: a level with no recorded spells is not in the list.
-- Home of the feature: the page replaces What's Training?'s spell list; "Train all" itself is on the
-- trainer window (UI/TrainAll.lua).
local _, ns = ...
local M = ns.Main
local MK = M.Make
local Style, L = ns.Style, ns.L

local P = {}
M.TrainPage = P

local STATE = {
	now = { key = "now", text = L["Learn now"], color = "live", order = 1 },
	later = { key = "later", text = L["Later"], color = "text2", order = 2 },
	known = { key = "known", text = L["Known"], color = "text3", order = 3 },
}

local COLUMNS = {
	{ key = "icon", icon = true, width = 22 },
	MK.Column("name", L["Spell"], 230, "LEFT", "Body", true),
	MK.Column("state", L["Status"], 90, "LEFT", "Small"),
	MK.Column("level", L["Level"], 56, "RIGHT", "Figure", true),
	MK.Column("needs", L["Needs"], nil, "LEFT", "Small"),
	MK.Column("cost", L["Cost"], 90, "RIGHT", "Figure", true),
}
P.COLUMNS = COLUMNS

-- One row from a planner entry (pure): view carries the cells for the window and the docked layout.
function P.Row(rec, state)
	local st = STATE[state]
	local label = rec.rank and (rec.name .. " " .. rec.rank) or rec.name
	local view = { name = label, nameColor = state == "known" and "text3" or "text", icon = rec.icon,
		cells = {}, colors = {}, tips = {} }
	local c, k, t = view.cells, view.colors, view.tips
	c.name, k.name = label, view.nameColor
	c.state, k.state = st.text, st.color
	c.level, k.level = (rec.level and rec.level > 0) and tostring(rec.level) or M.DASH, "text2"
	local needs = {}
	if rec.skill then
		needs[#needs + 1] = rec.skillRank and (rec.skill .. " " .. rec.skillRank) or rec.skill
	end
	for _, ability in ipairs(rec.abilities or {}) do
		needs[#needs + 1] = ability
	end
	c.needs, k.needs = table.concat(needs, ", "), "text2"
	if state == "known" then
		c.cost, k.cost = "", "text3"
	elseif rec.cost then
		c.cost, k.cost = rec.cost > 0 and ns.FormatCoins(rec.cost) or L["free"], "text"
		t.cost = { L["Cost seen at the trainer"], L["The price the trainer showed on your last visit, with your reputation discount."] }
	else
		c.cost, k.cost = L["unknown"], "text3"
	end
	view.result, view.resultColor = c.cost, k.cost
	view.sub = st.text .. (rec.level and rec.level > 1 and (" · " .. (L["level %d"]):format(rec.level)) or "")
	return { key = rec.key, name = label, icon = rec.icon, state = state, order = st.order, level = rec.level or 0,
		cost = rec.cost, rec = rec, view = view }
end

function P.Rows(plan)
	local rows = {}
	for _, pair in ipairs({ { "now", plan.learnNow }, { "later", plan.later }, { "known", plan.known } }) do
		for _, rec in ipairs(pair[2]) do
			local row = P.Row(rec, pair[1])
			row.order = row.order * 10000 + #rows -- the planner's order (level, name) inside each group
			rows[#rows + 1] = row
		end
	end
	return rows
end

function P.Hero(plan)
	local label = L["Class spells to learn"]
	if plan.empty then
		return MK.NoHero(label, L["nothing recorded yet. Visit your class trainer once and the spells it teaches are kept."])
	end
	local n = #plan.learnNow
	local sub = {}
	if plan.unpriced > 0 then
		sub[#sub + 1] = (L["%d without a price seen"]):format(plan.unpriced)
	end
	sub[#sub + 1] = (L["%d later"]):format(#plan.later)
	return {
		label = label, name = n == 1 and L["1 spell now"] or (L["%d spells now"]):format(n), nameColor = n > 0 and "text" or "text3",
		sub = table.concat(sub, " · "),
		figureLabel = L["Total cost"], figure = ns.FormatCoins(plan.total), figureColor = "text",
	}
end

-- "Recorded up to level 24 · Kimlee in Orgrimmar, 2 days ago": how far the record reaches.
function P.CoverageText(plan, now)
	if plan.empty then
		return L["No trainer visited yet"]
	end
	local where = plan.npc and (" · " .. plan.npc) or ""
	return (L["Recorded at level %d"]):format(plan.visitLevel or 0) .. where
end

function P.Model(ctx)
	local data = ns.ClassSpells.Data()
	local level = UnitLevel and UnitLevel("player") or 1
	local plan = ns.ClassSpells.Plan(data, level)
	local rows = P.Rows(plan)
	return {
		rows = rows,
		hero = P.Hero(plan),
		listTitle = (L["%d class spells recorded"]):format(#rows),
		listNote = L["learn now, later, known"],
		empty = L["No class spells recorded. Open your class trainer once; what it teaches is kept here."],
		footer = L["Recorded at your class trainer, nothing assumed. A trainer lists only the spells near your level: levels above what you saw there need a visit."],
		footerRight = P.CoverageText(plan),
		plan = plan,
	}
end

M.RegisterPage({
	key = "train", section = "make", label = L["Train"], order = 6, title = L["Train"],
	events = { "CLASSSPELLS_CHANGED" },
	columns = COLUMNS,
	sort = { key = "order", desc = false },
	Model = P.Model,
	P = P,
})
