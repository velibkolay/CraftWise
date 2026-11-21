-- Main window, Sell › Flips (#330): what the AH -> vendor flips actually earned. Stats on top (the hero: profit
-- of the chosen period, flips and units, what the units cost at the AH and what the vendors paid, the average
-- per flip, the best items), the history under it, newest first, one row per flip. Period chips: Today, 7
-- days, 30 days, All. Sources: Flips.lua (F.Stats, F.History); this file only draws them. Row data is kept
-- apart from the drawing. New design choices here are provisional (the page reuses the Ledger page's look).
local _, ns = ...
local M = ns.Main
local S = M.Sell
local Style, L = ns.Style, ns.L

local P = {}

P.HISTORY_ROWS = 500
P.BEST_SHOWN = 3
P.PERIODS = {
	{ key = "today", label = L["Today"] },
	{ key = "d7", label = L["7 days"] },
	{ key = "d30", label = L["30 days"] },
	{ key = "all", label = L["All"] },
}
local PERIOD_LABEL = {}
for _, p in ipairs(P.PERIODS) do
	PERIOD_LABEL[p.key] = p.label
end

function P.Period()
	local v = ns.db.settings.flipsPeriod
	return PERIOD_LABEL[v] and v or "d7"
end

function P.SetPeriod(key)
	ns.db.settings.flipsPeriod = key
	M.Refresh()
end

----------------------------------------------------------------------------------------------------
-- Rows (data)
----------------------------------------------------------------------------------------------------

-- "03 Nov 14:20" for a flip, "03 Nov" for a folded day.
function P.WhenText(h)
	return h.day and date("%d %b", h.t) or date("%d %b %H:%M", h.t)
end

-- History rows of a period, newest first: { key, itemID, name, quality, when, units, cost, got, profit, note }.
function P.Rows(period, now)
	local since = ns.Flips.Since(period, now or time())
	local rows, ids = {}, {}
	for i, h in ipairs(ns.Flips.History(P.HISTORY_ROWS)) do
		if not since or h.t >= since then
			local name, quality = S.ItemName(h.itemID, { name = h.name, link = h.link })
			local note
			if h.notFlip then
				note = L["Not a flip: left out of the totals. Click the row to count it again."]
			elseif h.day then
				note = (L["%d flips that day"]):format(h.flips)
			elseif h.skip > 0 then
				note = (L["%d more units had no logged AH cost: left out"]):format(h.skip)
			end
			if not h.day and not h.notFlip then
				note = (note and note .. " " or "") .. L["Click the row if you bought it to use, not to flip."]
			end
			rows[#rows + 1] = { key = i, itemID = h.itemID, name = name, quality = quality, when = P.WhenText(h),
				units = h.units, cost = h.cost, got = h.got, profit = h.profit, note = note, ref = h.row,
				notFlip = h.notFlip }
			if not (h.name or h.link) then
				ids[#ids + 1] = h.itemID
			end
		end
	end
	return rows, ids
end

-- The hero: { label, profit, caption, spent, got, avg }.
function P.HeroData(stats)
	local best = {}
	for i = 1, math.min(#stats.best, P.BEST_SHOWN) do
		local b = stats.best[i]
		best[#best + 1] = ("%s %s"):format(S.ItemName(b.itemID, { name = b.name, link = b.link }), S.Signed(b.profit))
	end
	local caption = S.Count(stats.flips, L["flip"], L["flips"]) .. " · " .. S.Count(stats.units, L["unit"], L["units"])
	if #best > 0 then
		caption = caption .. " · " .. L["best"] .. ": " .. table.concat(best, ", ")
	end
	return { label = PERIOD_LABEL[stats.window], profit = stats.profit, caption = caption, spent = stats.spent,
		got = stats.got, avg = stats.avg, flips = stats.flips }
end

P.DOCKED_HERO_MIDDLE = 28 + 14 + 6 + 3 * 16

function P.Model()
	local period = P.Period()
	local stats = ns.Flips.Stats(period)
	local rows, ids = P.Rows(period)
	S.LoadNames(ids)
	local hero = P.HeroData(stats)
	hero.full, hero.height, hero.middle = true, 80, P.DOCKED_HERO_MIDDLE
	return { rows = rows, hero = hero,
		footer = L["Profit = what the vendor paid minus what the same units cost at the AH. Units without a logged AH cost are left out. Items you equipped and rows you marked \"not a flip\" are not counted."],
		empty = L["No flip recorded in this period. A flip is units bought at the AH and sold to a vendor."] }
end

----------------------------------------------------------------------------------------------------
-- Drawing
----------------------------------------------------------------------------------------------------

local function ProfitColor(v, r)
	if r and r.notFlip then
		return "text3"
	end
	return v and v < 0 and "danger" or "text"
end

-- #384: a click on a flip row marks it "not a flip" (bought to use), a second click counts it again.
function P.OnClick(row)
	if row and row.ref then
		ns.Flips.SetNotFlip(row.ref, not row.notFlip)
	end
end

local function Grey(r, normal)
	return r.notFlip and "text3" or normal
end

P.COLUMNS = {
	{ key = "when", label = L["When"], width = 100, font = "Small", color = function(r) return Grey(r, "text2") end },
	{ key = "icon", icon = true, width = 22 },
	{ key = "name", label = L["Item"], color = function(r) return r.notFlip and "text3" or S.QualityColor(r.quality) end,
		tip = function(r) if r.note then return { r.name, r.note } end end },
	{ key = "units", label = L["Units"], width = 60, align = "RIGHT", font = "Figure", color = function(r) return Grey(r, "text") end, text = function(r) return tostring(r.units) end },
	{ key = "cost", label = L["AH cost"], width = 100, align = "RIGHT", font = "Figure", color = function(r) return Grey(r, "text2") end,
		text = function(r) return S.Coins(r.cost) end },
	{ key = "got", label = L["Vendor paid"], width = 100, align = "RIGHT", font = "Figure", color = function(r) return Grey(r, "text") end,
		text = function(r) return S.Coins(r.got) end },
	{ key = "profit", label = L["Profit"], width = 100, align = "RIGHT", font = "FigureBold",
		color = function(r) return ProfitColor(r.profit, r) end,
		text = function(r) return r.notFlip and L["not a flip"] or S.Signed(r.profit) end },
}

function P.Columns()
	return P.COLUMNS
end

function P.Hero(card, hero, ctx, slot)
	if not slot.change then
		slot.change = S.Stat(slot, true)
		slot.change.label:Hide()
		slot.change:SetPoint("TOPLEFT", slot, "TOPLEFT", 0, 0)
		slot.change:SetSize(360, 56)
		slot.parts = {}
		for i = 1, 3 do
			slot.parts[i] = S.Stat(slot)
			slot.parts[i]:SetSize(110, 40)
		end
		slot.parts[3]:SetPoint("TOPRIGHT", slot, "TOPRIGHT", 0, -14)
		slot.parts[2]:SetPoint("TOPRIGHT", slot.parts[3], "TOPLEFT", -20, 0)
		slot.parts[1]:SetPoint("TOPRIGHT", slot.parts[2], "TOPLEFT", -20, 0)
	end
	slot.change:Set(nil, S.Signed(hero.profit), hero.caption)
	slot.parts[1]:Set(L["AH cost"], S.Coins(hero.spent))
	slot.parts[2]:Set(L["Vendor paid"], S.Coins(hero.got))
	slot.parts[3]:Set(L["Average per flip"], S.Signed(hero.avg))
end

function P.DockedRow(data)
	return {
		icon = data.itemID and C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(data.itemID) or nil,
		name = data.name, nameColor = data.notFlip and "text3" or S.QualityColor(data.quality),
		note = data.when .. " · " .. data.units .. "×",
		result = data.notFlip and L["not a flip"] or S.Signed(data.profit), resultColor = ProfitColor(data.profit, data),
		sub = L["AH cost"] .. " " .. (S.Coins(data.cost) or M.DASH) .. "  " .. L["Vendor paid"] .. " " .. (S.Coins(data.got) or M.DASH),
		tip = data.note and { data.name, data.note } or nil,
	}
end

function P.DockedHero(card, hero, ctx, slot)
	if not slot.change then
		slot.change = Style.Text(slot, "FigureL", "text")
		slot.change:SetPoint("TOPLEFT", slot, "TOPLEFT", 0, 0)
		slot.caption = Style.Text(slot, "Caption", "text3")
		slot.caption:SetPoint("TOPLEFT", slot, "TOPLEFT", 0, -28)
	end
	slot.change:SetText(S.Signed(hero.profit) or M.DASH)
	local c = Style.Color(ProfitColor(hero.profit))
	slot.change:SetTextColor(c[1], c[2], c[3], 1)
	slot.caption:SetText(hero.caption or "")
	M.Docked.StatLines(slot, {
		{ label = L["AH cost"], value = S.Coins(hero.spent) },
		{ label = L["Vendor paid"], value = S.Coins(hero.got) },
		{ label = L["Average per flip"], value = S.Signed(hero.avg) },
	}, 48)
end

function P.Tools(slot)
	slot.chips = {}
	local right
	for i = #P.PERIODS, 1, -1 do
		local p = P.PERIODS[i]
		local chip = Style.Chip(slot, p.label)
		chip.key = p.key
		chip:SetScript("OnClick", function()
			P.SetPeriod(p.key)
		end)
		if right then
			chip:SetPoint("RIGHT", right, "LEFT", -8, 0)
		else
			chip:SetPoint("RIGHT", slot, "RIGHT", 0, 0)
		end
		right = chip
		slot.chips[p.key] = chip
	end
end

function P.UpdateTools(slot)
	local period = P.Period()
	for key, chip in pairs(slot.chips) do
		chip:SetOn(key == period)
	end
end

M.RegisterPage({
	key = "flips", section = "sell", label = L["Flips"], order = 4, events = { "FLIPS_CHANGED", "LEDGER_CHANGED" },
	columns = P.Columns, Model = P.Model, Hero = P.Hero, OnClick = P.OnClick,
	DockedRow = P.DockedRow, DockedHero = P.DockedHero,
	Tools = P.Tools, UpdateTools = P.UpdateTools,
	P = P,
})
