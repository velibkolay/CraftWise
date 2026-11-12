-- Main window, Make › Level up (#154; spec in #150 "Make", board "Make › Level up"): which known recipe
-- gets the next skill point for the least money. Rows from ns.LevelingRows (grey recipes are left out;
-- the footer says so). Columns: Recipe, Chance (60 unit bar + percent; white when measured, grey with "~"
-- for the community formula), Cost, Sale, Net/craft, Per skill-up. Sort: value per skill-up, recipes that
-- earn first, then the cheapest. Hero = the first row with its chance and per skill-up figure
-- (ns.HeroCards.BestSkillUp). Money that earns shows "+", money it costs "−" in C.danger.
local _, ns = ...
local M = ns.Main
local MK = M.Make
local Style, L = ns.Style, ns.L
local C = Style.C

local CHANCE_BAR = 60
local CHANCE_COLUMN, PER_COLUMN = 3, 7

local LevelPage = {}
M.LevelPage = LevelPage

local COLUMNS = {
	{ key = "icon", icon = true, width = 22 },
	MK.Column("name", L["Recipe"], 200, "LEFT", "Body", true),
	{ key = "chance", label = L["Chance"], width = 130, sort = true, text = function() return "" end,
		tip = function(r) return r.view and r.view.tips.chance end },
	MK.Column("cost", L["Cost"], 80, "RIGHT", "Figure", true),
	MK.Column("saleValue", L["Sale"], 80, "RIGHT", "Figure", true),
	MK.Column("netEarn", L["Net/craft"], 84, "RIGHT", "Figure", true),
	MK.Column("perSkill", L["Per skill-up"], nil, "RIGHT", "FigureBold", true),
}
LevelPage.COLUMNS = COLUMNS

-- "measured · 12 of your crafts", "estimate · community formula", "orange · every craft".
function LevelPage.ChanceNote(info)
	info = info or {}
	if info.kind == "orange" then
		return L["orange · every craft gives a point"]
	elseif info.kind == "formula" then
		return L["estimate · community formula"]
	elseif info.n then
		return (L["measured · %d of your crafts"]):format(info.n)
	end
	return nil
end

function LevelPage.View(r, ctx)
	local view = MK.NewView(r, r.outputItemID)
	local c, k, t = view.cells, view.colors, view.tips
	local info = r.chanceInfo or {}
	view.chanceText, view.chanceColor = MK.ChanceText(r.chance, info.kind)
	if not view.chanceText then
		view.chanceText, view.chanceColor = L["no data"], "text3"
		t.chance = { L["No chance yet"], (L["Not enough crafts recorded yet (%d, need %d), and no yellow/grey thresholds for an estimate."])
			:format(info.n or 0, ns.Leveling.MIN_CRAFTS) }
	end
	if r.costComplete then
		c.cost, k.cost = ns.FormatCoins(r.cost), "text"
	elseif (r.cost or 0) > 0 then
		c.cost, k.cost = ns.FormatCoins(r.cost) .. Style.Hex("danger") .. " +?|r", "text"
		t.cost = MK.WhyNoPrice(r, ctx)
	else
		c.cost, k.cost = M.NoPriceText(), "text3"
		t.cost = MK.WhyNoPrice(r, ctx)
	end
	if r.saleSource == "none" then
		c.saleValue, k.saleValue = L["no item"], "text3"
	elseif r.saleValue then
		c.saleValue, k.saleValue = ns.FormatCoins(r.saleValue) .. (r.saleSource == "auction" and MK.StaleAge(ctx) or ""), "text"
	else
		c.saleValue, k.saleValue = M.NoPriceText(), "text3"
		t.saleValue = { L["No sale price"], L["Counted as 0: no AH price at the profit house and no vendor price."] }
	end
	r.netEarn = r.net and -r.net or nil
	r.perSkill = r.perPoint and -r.perPoint or nil
	c.netEarn, k.netEarn = MK.Signed(r.netEarn)
	if not r.net then
		t.netEarn = MK.WhyNoPrice(r, ctx)
	end
	c.perSkill, k.perSkill = MK.Signed(r.perSkill)
	if not r.perPoint then
		t.perSkill = not r.net and MK.WhyNoPrice(r, ctx) or t.chance
	end
	view.rail = r.perSkill and { value = r.perSkill, zeroAt = 0.18 } or nil
	view.result, view.resultColor = c.perSkill, k.perSkill
	view.sub = view.chanceText
	view.missing = r.net == nil
	return MK.Attach(r, view)
end

-- The chance cell: a 60 unit bar (white measured, grey estimate) and the percent after it.
local function DrawChance(b, r, ctx)
	local pos = MK.ColumnAt(COLUMNS, CHANCE_COLUMN, ctx)
	if not b.cwChance then
		local track = b:CreateTexture(nil, "ARTWORK")
		Style.Fill(track, C.rule)
		local fill = b:CreateTexture(nil, "ARTWORK", nil, 1)
		fill:SetTexture(Style.WHITE)
		local text = Style.Text(b, "Figure", "text")
		b.cwChance = { track = track, fill = fill, text = text }
	end
	local ch = b.cwChance
	ch.track:ClearAllPoints()
	ch.track:SetPoint("LEFT", b, "LEFT", pos.x, 0)
	ch.track:SetSize(CHANCE_BAR, 6)
	local p = r.chance or 0
	ch.fill:ClearAllPoints()
	ch.fill:SetPoint("LEFT", ch.track, "LEFT", 0, 0)
	ch.fill:SetSize(math.max(CHANCE_BAR * math.min(p, 1), 0.01), 6)
	local estimate = r.chanceInfo and r.chanceInfo.kind == "formula"
	local fc = estimate and C.text3 or C.text
	ch.fill:SetVertexColor(fc[1], fc[2], fc[3], 1)
	ch.fill:SetShown(p > 0)
	ch.text:ClearAllPoints()
	ch.text:SetPoint("LEFT", b, "LEFT", pos.x + CHANCE_BAR + 8, 0)
	ch.text:SetText(r.view.chanceText)
	local tc = Style.Color(r.view.chanceColor)
	ch.text:SetTextColor(tc[1], tc[2], tc[3], 1)
end

local SORT_NOTES = {
	perSkill = L["best value per skill-up first: earning, then cheapest"],
	name = L["by name"], chance = L["by chance"], cost = L["by cost"], saleValue = L["by sale"], netEarn = L["by net per craft"],
}

function LevelPage.Hero(rows)
	local h, why = ns.HeroCards.BestSkillUp(rows)
	local label = L["Best skill-up right now"]
	if not h then
		return MK.NoHero(label, why)
	end
	local row
	for _, r in ipairs(rows) do
		if r.recipeID == h.recipeID then
			row = r
		end
	end
	local parts = { MK.ColorWord(h.color) }
	if h.net and h.net <= 0 then
		parts[#parts + 1] = (L["earns %s per craft after selling it"]):format("+" .. ns.FormatCoins(-h.net))
	elseif h.net then
		parts[#parts + 1] = (L["costs %s per craft"]):format(ns.FormatCoins(h.net))
	end
	local figure, color = MK.Signed(-h.perPoint)
	return {
		label = label, name = h.name, nameColor = "text", sub = table.concat(parts, " · "),
		figureLabel = L["Per skill-up"], figure = figure, figureColor = color,
		data = h, chanceNote = LevelPage.ChanceNote(row and row.chanceInfo),
		middle = 42, -- docked: the chance, its bar and how it was found
	}
end

-- The middle: "Skill-up chance" and the percent, an 8 unit bar, how the chance was found.
local function DrawHero(slot, hero)
	local frame = slot
	if not frame then
		return
	end
	if not frame.cw then
		frame.cw = true
		frame.label = Style.Text(frame, "Label", "text3")
		frame.label:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -2)
		frame.label:SetText(L["Skill-up chance"])
		frame.pct = Style.Text(frame, "Figure", "text")
		frame.pct:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
		frame.track = frame:CreateTexture(nil, "ARTWORK")
		Style.Fill(frame.track, C.rule)
		frame.track:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -17)
		frame.track:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -17)
		frame.track:SetHeight(8)
		frame.fill = frame:CreateTexture(nil, "ARTWORK", nil, 1)
		frame.fill:SetTexture(Style.WHITE)
		frame.fill:SetPoint("TOPLEFT", frame.track, "TOPLEFT", 0, 0)
		frame.note = Style.Text(frame, "Caption", "text3")
		frame.note:SetPoint("TOPLEFT", frame.track, "BOTTOMLEFT", 0, -4)
	end
	local h = hero and hero.data
	for _, region in ipairs({ frame.label, frame.pct, frame.track, frame.fill, frame.note }) do
		region:SetShown(h ~= nil)
	end
	if not h then
		return
	end
	local text, color = MK.ChanceText(h.chance, h.chanceKind)
	frame.pct:SetText(text or "")
	local tc = Style.Color(color or "text")
	frame.pct:SetTextColor(tc[1], tc[2], tc[3], 1)
	local width = frame.barWidth or 300
	frame.fill:SetSize(math.max(width * math.min(h.chance or 0, 1), 0.01), 8)
	local fc = h.chanceEstimate and C.text3 or C.text
	frame.fill:SetVertexColor(fc[1], fc[2], fc[3], 1)
	frame.note:SetText(hero.chanceNote or "")
end

function LevelPage.Model(ctx)
	local rows = MK.LevelRows(ctx.professionID)
	local values = {}
	for i, r in ipairs(rows) do
		LevelPage.View(r, ctx)
		values[i] = r.perSkill
	end
	ctx.railMax = Style.SharedScale(values)
	local crafts = ns.CraftsRecorded and ns.CraftsRecorded() or 0
	return {
		rows = rows,
		hero = LevelPage.Hero(rows),
		listTitle = L["Known recipes that still give skill"],
		-- docked: the sale note of the list header (no room right of the title) joins the note
		listNote = MK.SortNote(M.Page("level"), SORT_NOTES)
			.. (M.IsDocked(ctx) and (" · " .. L["Sale: AH after cut when it passes your AH rule, else vendor"]) or ""),
		empty = L["No known recipe at your skill gives skill-ups. Learn new ones on the Learn page."],
		footer = L["Chance: your own crafts at this colour; ~ marks the community formula while you have too few. Grey recipes are left out."],
		footerRight = MK.BasisNote("level", rows) .. " · " .. (L["%d crafts recorded"]):format(crafts),
	}
end

M.RegisterPage({
	key = "level", section = "make", label = L["Level up"], order = 3, title = L["Level up"],
	profession = true, prices = true,
	events = { "SKILLUPS_CHANGED", "BAGS_CHANGED", "LEDGER_CHANGED" },
	columns = COLUMNS,
	sort = { key = "perSkill", desc = true },
	Model = LevelPage.Model,
	Hero = function(_, hero, ctx, slot)
		local m = ctx.metrics or M.WINDOW_METRICS
		if slot then
			slot.barWidth = (m.width or 880) - 2 * m.pad - 2 * m.heroPadX - m.heroLeft - m.heroRight - 2 * m.heroGap
		end
		DrawHero(slot, hero)
	end,
	Tools = MK.BuildTools,
	UpdateTools = MK.UpdateTools,
	ListTools = function(slot)
		slot.note = Style.Text(slot, "Caption", "text3")
		slot.note:SetPoint("RIGHT", slot, "RIGHT", 0, 0)
		slot.note:SetJustifyH("RIGHT")
		slot.note:SetText(L["Sale: AH after cut when it passes your AH rule, else vendor"])
	end,
	UpdateListTools = function(slot, ctx)
		slot.note:SetShown(not M.IsDocked(ctx))
	end,
	dockedListToolsWidth = 0,
	InitRow = function(b, r, ctx)
		DrawChance(b, r, ctx)
		MK.DrawSkeleton(b, PER_COLUMN, MK.ColumnAt(COLUMNS, PER_COLUMN, ctx), r.net == nil, ctx)
	end,
	Open = function(content, r, ctx)
		MK.DrawOpen(content, r, nil, ctx)
	end,
	OpenHeight = function(r, ctx)
		return MK.OpenHeight(r, nil, ctx)
	end,
	RowTooltip = function(owner, r, ctx)
		MK.ShowLevelTooltip(owner, r, ctx and ctx.professionID and ns.ProfessionSkill(ctx.professionID))
	end,
})
