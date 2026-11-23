-- Main window, Make › Craft (#154; spec in #150 "Make", board "Window layout"): what to craft for profit.
-- Hero: the best profit among known, priced recipes (ns.HeroCards.BestCraft). List: one row per recipe
-- from ns.BuildRows behind the filter box and the chips Unlearned and Hide unpriced: output icon, name in
-- its skill colour, a rail of profit per craft on the list's shared axis (zero at 18 %), "cost → sells"
-- with the sale's tag (AH / vendor / AH gross) and the profit. A click opens the reagents and Price
-- history; hover shows the crafted item with the CraftWise recipe lines.
local _, ns = ...
local M = ns.Main
local MK = M.Make
local Style, L = ns.Style, ns.L
local C = Style.C

local ZERO_AT = 0.18

local CraftPage = {}
M.CraftPage = CraftPage

local COLUMNS = {
	{ key = "icon", icon = true, width = 22 },
	MK.Column("name", L["Recipe"], 188, "LEFT", "Body", true),
	-- The shell's rail column: profit per craft on the list's shared axis, zero at 18 %; the opened row's
	-- bar in C.text, the others C.text2, losses in C.danger left of zero.
	{ key = "rail", label = L["Profit per craft"], rail = function(r, ctx)
		local d = r.view and r.view.rail
		return { value = d and d.value, max = ctx.railMax, zeroAt = ZERO_AT }
	end },
	MK.Column("cost", L["Cost"] .. " " .. Style.Glyph("arrow", 10, "text3") .. " " .. L["sells"], 172, "RIGHT", "Figure"),
	MK.Column("pct", L["Return"], 56, "RIGHT", "Figure", true),
	MK.Column("daily", L["Per day"], 92, "RIGHT", "Figure", true),
	MK.Column("profit", L["Profit"], 96, "RIGHT", "Figure", true), -- one figure size for every money column (#412)
	MK.Column("now", L["Now"], 76, "RIGHT", "Figure"), -- #376: the profit at the current lowest prices; hidden when the profit prices are
}
CraftPage.COLUMNS = COLUMNS

-- The columns on show: without Now while the profit prices are the current lowest anyway (#376).
function CraftPage.Columns()
	if ns.NowDiffers() then
		return COLUMNS
	end
	local out = {}
	for _, col in ipairs(COLUMNS) do
		if col.key ~= "now" then
			out[#out + 1] = col
		end
	end
	return out
end
COLUMNS[2].grow = 300 -- dragged wider (#280) the recipe name gets room before the profit rail does

----------------------------------------------------------------------------------------------------
-- Per day (#231): the profit the market can absorb
----------------------------------------------------------------------------------------------------

-- Units that disappeared at the profit house over the last 7 days at prices up to the typical (ns.Market.
-- Disappeared: sold or expired, never "sold") and how many of those 7 days have market data at all. The per day
-- figure divides by the days with data, not by 7, so a short history doesn't understate it; below
-- Market.MIN_HISTORY_DAYS days of data there is no figure. Returns { gone, days } or nil without any history for the
-- product at the house. Reads the saved market data only.
CraftPage.WINDOW_DAYS = 7

function CraftPage.MarketInfo(itemID)
	local Mk = ns.Market
	local house = ns.ProfitHouse and ns.ProfitHouse()
	if not (itemID and Mk and Mk.IsLastOnlyAt and house) or Mk.IsLastOnlyAt(itemID, house) == nil then
		return nil
	end
	local entry = CraftWiseMarketDB and CraftWiseMarketDB.items and CraftWiseMarketDB.items[itemID]
	entry = entry and entry[house]
	local today, days = math.floor(time() / 86400), 0
	for day = today - CraftPage.WINDOW_DAYS + 1, today do
		if entry and entry.days and entry.days[day] then
			days = days + 1
		end
	end
	return { gone = Mk.Disappeared(itemID, house), days = days }
end

-- The daily figure of a row (pure over the row and the market info): profit per craft times the crafts a day the
-- market takes = (units disappeared per day) / (items per craft). Returns
--   { daily = copper, crafts = crafts a day, perDay = units a day, gone, days }                 a figure
--   { noLimit = true }                                  sold to a vendor (Junk counts as vendor): no market limit
--   { reason = "profit" | "item" | "other" | "history" | "short", days = n }                    no figure, and why
-- Vendor rows are not ranked by this figure: a vendor takes everything, the limit is your crafting time (see
-- Speed and Profit/h on Make > Crafted), so they sort after the rows with a figure.
function CraftPage.Daily(r, info)
	if r.noItemOutput then
		return { reason = "item" }
	elseif r.profit == nil then
		return { reason = "profit" }
	elseif r.sellSource == "vendor" then
		local cd = r.cooldown and r.cooldown.kind == "spell" and CraftPage.CooldownDay(r, nil)
		if cd then
			return { daily = r.profit * cd.crafts, crafts = cd.crafts, cooldown = cd, lines = CraftPage.CooldownLines(r, cd) } -- the cooldown is the limit (#413)
		end
		return { noLimit = true }
	elseif r.sellSource ~= "auction" then
		return { reason = "other" }
	elseif not info then
		return { reason = "history" }
	elseif info.days < ns.Market.MIN_HISTORY_DAYS then
		return { reason = "short", days = info.days }
	end
	local perDay = info.gone / info.days
	local crafts = perDay / math.max(r.outputQuantity or 1, 1)
	local cd = r.cooldown and CraftPage.CooldownDay(r, crafts)
	if cd then
		crafts = cd.crafts -- a cooldown caps it (a transmute) or splits it into own and AH units (#413)
	end
	return { daily = r.profit * crafts, crafts = crafts, perDay = perDay, gone = info.gone, days = info.days, cooldown = cd,
		lines = cd and CraftPage.CooldownLines(r, cd) or nil }
end

function CraftPage.CooldownLines(r, cd)
	local item = r.cooldown.kind == "item" and ns.Basket.ItemName(r.cooldown.item) or nil
	return ns.Cooldown.DayLines(cd, r.cooldown, item)
end

-- The cooldown part of a daily figure (#413, Profit.CooldownDay over the row's cooldown and what the client says now).
function CraftPage.CooldownDay(r, demand)
	local c = r.cooldown
	local cd = ns.Profit.CooldownDay({ kind = c.kind, ms = c.ms, perCraft = c.perCraft, quantity = c.quantity,
		toolHeld = r.cdState and r.cdState.toolHeld }, demand)
	if cd then
		cd.kind, cd.demand = c.kind, demand
	end
	return cd
end

local DAILY_REASONS = {
	profit = L["No profit yet: a price is missing."],
	item = L["This recipe makes no item."],
	other = L["Its sale isn't an auction price."],
	history = L["No market history for the product at the profit house."],
}

-- Cell text, colour and tip of the Per day column for a Daily() result.
function CraftPage.DailyCell(d)
	if d.daily then
		local text, color = MK.Signed(d.daily)
		local tip = { L["Per day"], d.gone and (L["Profit per craft times the crafts a day the market takes: %s units disappeared in %d days at prices up to the typical (sold or expired). Approx."]):format(
			ns.CraftLog.Format(d.gone), d.days) or L["Profit per craft times the crafts the cooldown allows a day."] }
		for _, line in ipairs(d.lines or {}) do
			tip[#tip + 1] = line
		end
		return text, color, tip
	elseif d.noLimit then
		return L["no limit"], "text3", { L["Per day"], L["Sold to a vendor: no market limit. See Make › Crafted for profit per hour."] }
	elseif d.reason == "short" then
		return M.DASH, "text3", { L["Per day"], (L["Market history too short: %d of %d days."]):format(d.days, ns.Market.MIN_HISTORY_DAYS) }
	end
	return M.DASH, "text3", { L["Per day"], DAILY_REASONS[d.reason] or "" }
end

-- "1g 50s → 2g 70s AH": cost, sale and its tag; a missing figure says why (pure). Also returns the
-- two halves.
-- short = the list cell: the common "AH" tag is left out (the footer says prices are AH prices), so the
-- price is not cut off; vendor, disenchant and "AH gross" stay (#412).
function CraftPage.Caption(r, ctx, short)
	local cost
	if r.costComplete then
		cost = MK.PlainMoney(r.cost)
	elseif (r.cost or 0) > 0 then
		cost = MK.PlainMoney(r.cost) .. " +?"
	else
		cost = L["no price"]
	end
	local sells
	if r.noItemOutput then
		sells = L["no item"]
	elseif r.sellsFor then
		local tag = MK.SaleTag(r.sellSource, r.cutUnverified, r.sellMarked)
		if short and tag == "AH" then
			tag = nil
		end
		sells = MK.PlainMoney(r.sellsFor) .. (tag and (" " .. tag) or "")
		if r.disenchantView and r.deShort then
			sells = sells .. " · " .. r.deShort
		end
		if r.vendorLoop then
			sells = sells .. " · " .. L["loop"] -- every reagent from a vendor, product to a vendor (#185)
		end
		if r.sellSource == "auction" then
			sells = sells .. MK.StaleAge(ctx)
		end
	else
		sells = L["no price"]
	end
	if r.thin then
		sells = sells .. " · " .. L["thin"] -- a price behind the row comes from a thin market
	end
	return cost .. " " .. Style.Glyph("arrow", 10, "text3") .. " " .. sells, cost, sells
end

-- The row's view (see Make.lua): name, rail = profit per craft, result = ± profit, sub = the caption.
function CraftPage.View(r, ctx)
	local view = MK.NewView(r, r.outputItemID)
	view.rail = r.profit and { value = r.profit, zeroAt = ZERO_AT } or nil
	view.sub, view.costText, view.sellsText = CraftPage.Caption(r, ctx)
	view.cells.cost, view.colors.cost = (CraftPage.Caption(r, ctx, true)), "text3"
	if r.profit then
		view.result, view.resultColor = MK.Signed(r.profit)
	else
		view.result, view.resultColor = M.DASH, "text3"
		view.tips.profit = MK.WhyNoPrice(r, ctx)
		view.tips.cost = view.tips.profit
	end
	view.cells.profit, view.colors.profit = view.result, view.resultColor
	r.now = MK.Now(r, "craft")
	if r.now then
		view.cells.now, view.colors.now, view.tips.now = MK.NowCell(r.now, r, r.profit)
		if r.now.net then
			view.sub = view.sub .. " · " .. L["now"] .. " " .. (MK.Signed(r.now.net)) -- docked: no Now column (#376)
		end
	end
	view.cells.pct, view.colors.pct = MK.PercentText(r.pct), r.pct and r.pct < 0 and "danger" or "text2"
	view.tips.pct = { L["Return"], L["Profit divided by the cost to craft."] }
	r.cdState = r.cooldown and ns.Cooldown.State(r.cooldown) or nil
	view.cooldownText = ns.Cooldown.RowText(r)
	if view.cooldownText then
		view.sub = view.sub .. ", " .. view.cooldownText -- docked: the caption (#413)
	end
	r.daily = CraftPage.Daily(r, CraftPage.MarketInfo(r.outputItemID))
	r.dailyProfit = r.daily.daily
	view.cells.daily, view.colors.daily, view.tips.daily = CraftPage.DailyCell(r.daily)
	view.missing = r.profit == nil and not r.noItemOutput -- a skeleton while scanning (both layouts)
	MK.Attach(r, view)
	if ctx.all and r.professionName then
		-- All professions (#211): the profession next to the name, muted (the docked layout's tag chip).
		view.cells.name = view.name .. "  " .. Style.Hex("text3") .. r.professionName .. "|r"
		view.tag = r.professionName
	end
	if view.cooldownText then
		-- Window layout: "cd 71h, ready, needs Tanning Rack" muted behind the name.
		view.cells.name = view.cells.name .. "  " .. Style.Hex("text3") .. view.cooldownText .. "|r"
	end
	return r
end

local SORT_NOTES = { profit = L["by profit"], pct = L["by profit %"], name = L["by name"], daily = L["by profit per day"] }

-- By the daily figure: rows without one last either way; among those the vendor rows (no limit) first, by profit.
function CraftPage.ByDaily(desc)
	return function(a, b)
		local da, db = a.dailyProfit, b.dailyProfit
		if da ~= nil and db ~= nil and da ~= db then
			if desc then
				return da > db
			end
			return da < db
		elseif (da == nil) ~= (db == nil) then
			return da ~= nil
		elseif da == nil then
			local va, vb = a.daily and a.daily.noLimit or false, b.daily and b.daily.noLimit or false
			if va ~= vb then
				return va
			end
		end
		local pa, pb = a.profit, b.profit
		if (pa == nil) ~= (pb == nil) then
			return pa ~= nil
		elseif pa ~= pb then
			return pa > pb
		end
		return (a.name or "") < (b.name or "")
	end
end

-- The list's own order: by % or by the daily figure (rows without one last), else the shell's.
function CraftPage.SortRows(rows, key, desc)
	if key == "daily" then
		table.sort(rows, CraftPage.ByDaily(desc))
		return rows
	end
	if key == "pct" then
		table.sort(rows, ns.Profit.ByPercent(desc))
		return rows
	end
	table.sort(rows, ns.Profit.Comparator(key, desc))
	return rows
end

-- Hero card (spec: best profit among known, priced recipes): name, colour word, skill-up chance,
-- "short N <reagent>", profit; the rail runs cost (grey) then profit (white) along the sale price.
function CraftPage.Hero(rows, ctx)
	local h, why = ns.HeroCards.BestCraft(rows, { professionID = not ctx.all and ctx.professionID or nil, sort = (M.Sort(M.Page("craft"))) })
	local label = ctx.vendorCheck and L["Best vendor craft right now"] or ctx.disenchantCheck and L["Best disenchant craft right now"]
		or L["Best craft right now"]
	if not h then
		return MK.NoHero(label, why)
	end
	local parts = {}
	-- The recipe's skill colour in words: grey gives no skill-up (#412).
	parts[#parts + 1] = h.color == "grey" and (Style.Hex("text3") .. L["no skill-up"] .. "|r") or MK.ColorWord(h.color)
	local chance = MK.ChanceText(h.chance, h.chanceEstimate and "formula" or h.chanceKind)
	if chance then
		parts[#parts + 1] = (L["skill-up %s"]):format(chance)
	end
	local short = h.short and h.short[1]
	local tip
	if short then
		parts[#parts + 1] = (L["missing %d %s"]):format(short.missing, MK.ItemName(short.itemID))
			.. (#h.short > 1 and (" " .. (L["+%d more"]):format(#h.short - 1)) or "")
		tip = { L["Missing reagents"] }
		for _, s2 in ipairs(h.short) do
			tip[#tip + 1] = (L["%d x %s"]):format(s2.missing, MK.ItemName(s2.itemID))
		end
	end
	if h.pct then
		parts[#parts + 1] = MK.PercentText(h.pct)
	end
	-- "cd 71h, ready, needs Tanning Rack" (#413)
	local cdText = ns.Cooldown.RowText({ cooldown = h.cooldown, focus = h.focus, cdState = h.cooldown and ns.Cooldown.State(h.cooldown) })
	if cdText then
		parts[#parts + 1] = cdText
	end
	local figure, color = MK.Signed(h.profit)
	return {
		label = label, name = h.name, nameColor = "text", sub = table.concat(parts, " · "),
		figure = figure, figureColor = color, data = h, tip = tip,
	}
end

-- The hero card's middle: a bar of cost then profit along the sale (loss in C.danger along the cost),
-- with "cost …" and "sells … AH" under it.
local function DrawHero(_, hero, ctx, slot)
	local frame = slot
	if not frame then
		return
	end
	if not frame.cw then
		frame.cw = true
		frame.cost = frame:CreateTexture(nil, "ARTWORK")
		frame.cost:SetTexture(Style.WHITE)
		frame.gain = frame:CreateTexture(nil, "ARTWORK")
		frame.gain:SetTexture(Style.WHITE)
		frame.left = Style.Text(frame, "Caption", "text3")
		frame.right = Style.Text(frame, "Caption", "text3")
		frame.right:SetJustifyH("RIGHT")
	end
	local h = hero and hero.data
	for _, region in ipairs({ frame.cost, frame.gain, frame.left, frame.right }) do
		region:SetShown(h ~= nil)
	end
	if not h then
		return
	end
	local m = ctx.metrics or M.WINDOW_METRICS
	local width = (m.width or 880) - 2 * m.pad - 2 * m.heroPadX - m.heroLeft - m.heroRight - 2 * m.heroGap
	frame.barWidth = width
	local whole = math.max(h.sale or 0, h.cost or 0)
	local costW = whole > 0 and math.min(h.cost, h.sale) / whole * width or 0
	local gainW = whole > 0 and math.abs(h.profit) / whole * width or 0
	frame.cost:ClearAllPoints()
	frame.cost:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -9)
	frame.cost:SetSize(math.max(costW, 0.01), 4)
	Style.Fill(frame.cost, C.text3)
	frame.gain:ClearAllPoints()
	frame.gain:SetPoint("TOPLEFT", frame, "TOPLEFT", costW, -8)
	frame.gain:SetSize(math.max(gainW, 0.01), 6)
	Style.Fill(frame.gain, h.profit < 0 and C.danger or C.text)
	frame.left:ClearAllPoints()
	frame.left:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -20)
	frame.left:SetText(L["cost"] .. " " .. ns.FormatCoins(h.cost))
	frame.right:ClearAllPoints()
	frame.right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -20)
	local tag = MK.SaleTag(h.sellSource, nil, h.sellMarked)
	frame.right:SetText(L["sells"] .. " " .. ns.FormatCoins(h.sale) .. (tag and (" · " .. tag) or ""))
end

-- The rail's scale: one outlier (a +67g row among rows of a few silver) must not shrink every other bar to
-- a tick, so the scale is the 90th percentile of the absolute profits, never above the largest; bars beyond it
-- run to the end of the rail (Style.RailGeometry clamps). Up to 5 rows the largest sets it (#412).
function CraftPage.RailScale(values)
	local abs = {}
	for _, v in pairs(values) do
		if type(v) == "number" then
			abs[#abs + 1] = math.abs(v)
		end
	end
	if #abs <= 5 then
		return Style.SharedScale(abs)
	end
	table.sort(abs)
	return abs[math.ceil(#abs * 0.9)]
end

function CraftPage.Model(ctx)
	local s = ns.db.settings
	local rows, hidden
	if ctx.all then
		rows, hidden = MK.CraftRowsAll(s)
	else
		rows, hidden = MK.CraftRows(ctx.professionID, s)
	end
	ctx.vendorCheck = s.vendorCheck and true or false
	ctx.disenchantCheck = s.disenchantCheck and not s.vendorCheck and true or false
	local values = {}
	for i, r in ipairs(rows) do
		CraftPage.View(r, ctx)
		values[i] = r.profit
	end
	ctx.railMax = CraftPage.RailScale(values)
	local right, uncut = {}, 0
	for _, r in ipairs(rows) do
		if r.cutUnverified then
			uncut = uncut + 1
		end
	end
	if uncut > 0 then
		right[#right + 1] = (L["%d sell where the AH cut is unverified"]):format(uncut)
	end
	if ctx.disenchantCheck then
		right[#right + 1] = (L["%d hidden: not disenchantable or no price"]):format(hidden)
	elseif s.vendorCheck then
		right[#right + 1] = (L["%d hidden: no vendor profit"]):format(hidden)
	elseif hidden > 0 then
		right[#right + 1] = (L["%d hidden: no price"]):format(hidden)
	end
	return {
		rows = rows,
		hero = CraftPage.Hero(rows, ctx),
		listTitle = #rows == 1 and L["1 recipe"] or (L["%d recipes"]):format(#rows),
		listNote = MK.SortNote(M.Page("craft"), SORT_NOTES),
		empty = ctx.disenchantCheck and L["No craft here makes something you can disenchant. Clear the filter or turn on Unlearned."]
			or s.vendorCheck and L["No craft earns when sold to a vendor. Clear the filter, turn on Unlearned or turn off Vendor check."]
			or L["No recipes match. Clear the filter or turn on Unlearned."],
		footer = (ctx.disenchantCheck and (L["Disenchant check: profit = expected disenchant value - reagents; measured samples from Disenchantry, else pooled, else the Classic table (guide)"] .. " · ") or "")
			.. (s.vendorCheck and (L["Vendor check: sells to a vendor, profit = vendor price - reagents; loop = every reagent from a vendor"] .. " · ") or "")
			.. MK.FooterPrices("profit", rows),
		footerRight = table.concat(right, " · "),
	}
end

M.RegisterPage({
	key = "craft", section = "make", label = L["Craft"], order = 1, title = L["Craft"],
	profession = true, prices = true, allowAll = true,
	events = { "BAGS_CHANGED", "LEDGER_CHANGED", "SKILLUPS_CHANGED" },
	columns = CraftPage.Columns,
	columnsAll = COLUMNS,
	rowHeight = 38,
	sort = { key = "profit", desc = true },
	SortRows = CraftPage.SortRows,
	Model = CraftPage.Model,
	Hero = DrawHero,
	Tools = function(slot)
		MK.BuildTools(slot)
		slot.profession.allowAll = true -- the dropdown starts with All professions (#211)
	end,
	UpdateTools = MK.UpdateTools,
	ListTools = function(slot)
		slot.chips = {
			MK.SettingChip(slot, L["Unlearned"], "includeUnlearned", L["Also list recipes you don't know yet."]),
			MK.SettingChip(slot, L["Hide unpriced"], "hideUnpriced", L["Leave out recipes without a profit; the footer counts them."]),
			MK.SettingChip(slot, L["Vendor check"], "vendorCheck", L["Sell the product to a vendor: list the crafts that earn that way, best first. Loop = all reagents from vendors too."], "disenchantCheck"),
			MK.SettingChip(slot, L["Disenchant check"], "disenchantCheck", L["Disenchant the product: list crafts of uncommon or better armour and weapons by expected disenchant value minus reagents. Measured values need Disenchantry's records; without them the Classic table (guide) is used."], "vendorCheck"),
		}
		MK.LayoutChips(slot, slot.chips)
	end,
	UpdateListTools = function(slot)
		MK.UpdateChips(slot.chips)
	end,
	InitRow = function(b, r, ctx)
		local columns = CraftPage.Columns()
		local at = #columns - (ns.NowDiffers() and 1 or 0) -- the Profit column
		MK.DrawSkeleton(b, at, MK.ColumnAt(columns, at, ctx), r.profit == nil and not r.noItemOutput, ctx)
	end,
	Open = function(content, r, ctx)
		MK.DrawOpen(content, r, { basket = true }, ctx)
	end,
	OpenHeight = function(r, ctx)
		return MK.OpenHeight(r, nil, ctx, { basket = true })
	end,
	RowTooltip = function(owner, r)
		MK.ShowRecipeTooltip(owner, r, "profit")
	end,
})

-- "Recipes using this" (item menu): Make › Craft on the profession of yours that uses the item most,
-- filtered by the item's name, with unlearned recipes shown.
function ns.ShowRecipesUsing(itemID)
	local counts = {}
	for _, e in ipairs(ns.UsedIn(itemID)) do
		if e.professionID then
			counts[e.professionID] = (counts[e.professionID] or 0) + 1
		end
	end
	local best, most = nil, 0
	for id, n in pairs(counts) do
		if n > most or (n == most and best and id < best) then
			best, most = id, n
		end
	end
	if not best then
		ns.WithItemNames({ itemID }, function()
			ns.Print(ns.ItemChatText(itemID) .. " is not used by your professions.")
		end)
		return false
	end
	ns.db.settings.includeUnlearned = true
	M.UI().profession = best
	MK.state.query = MK.ItemName(itemID)
	M.Open("craft")
	return true
end
