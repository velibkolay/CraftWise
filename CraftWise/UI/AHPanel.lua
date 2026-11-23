-- The CraftWise panel next to the auction house window (#315, part 1): the flips and the basket's AH lines, a
-- search per line, the listed results, and one Buy button that shows what it will spend. All the buying is in
-- AHBuy.lua; this file only draws and forwards the clicks:
--   * a click on a line picks it and searches it (one search, nothing else);
--   * the Search button searches the picked line again;
--   * the Buy button's OnClick calls AHBuy.Click: the one place a purchase can start from this panel.
-- Nothing here buys, searches or lists on an event or a timer.
-- Craft run (#388, #403): the section at the top takes a budget and a time; "Build plan" makes a list of suggested crafts to
-- pick from in the main window (Make › Basket, Basket.SuggestStart) and "Refresh prices" searches the plan's items one by
-- one (AHBuy.SweepStart). Each starts from a click.
-- Part 2 (#315): the snipe list lives here too. Lines of the list are marked "snipe" and have a × to remove them;
-- a click on any line also fills the form below (item, max price per unit, "up to"), where Veli types his
-- max price (3g 40s 5c) and saves it. The two keys (AHBuy.lua) walk and buy these same lines.
local _, ns = ...
local L, Style = ns.L, ns.Style

local P = {}
ns.AHPanel = P

P.WIDTH = 340
P.GROUP_LINES = 8 -- rows drawn per group; the rest is counted ("+31 more", #402)
P.RESULTS = 6
P.ROW = 18 -- a row is one line: the item and its quantity, the one figure on the right; the rest is in its tooltip (#402)
P.FIGURE_W = 96 -- the figure on the right of a row

local panel
local lines = {} -- the line rows
local results = {} -- the result texts
local headings = {} -- the group headings (snipes, flips, basket)
local cached -- AHBuy.Lines(), kept until the basket, the bags or the prices change

local function Money(copper)
	return ns.FormatMoney(copper, true)
end

----------------------------------------------------------------------------------------------------
-- Closed or open, and the sections (#402): saved in settings.ahPanel = { closed, sections = { run, post, flips, snipes } }.
-- A section never opened or closed by hand is open when it has something to do now (P.defaultOpen, set by Update).
----------------------------------------------------------------------------------------------------
P.SECTIONS = { "run", "post", "flips", "snipes" }
P.defaultOpen = {}

function P.Saved()
	if not ns.db then
		return { closed = false, sections = {} }
	end
	local s = ns.db.settings
	s.ahPanel = s.ahPanel or {}
	s.ahPanel.sections = s.ahPanel.sections or {}
	return s.ahPanel
end

function P.Closed()
	return P.Saved().closed and true or false
end

-- Hides or shows the panel (the X, the button on the auction house, `/craftwise buy`); the choice is kept.
function P.SetClosed(closed)
	P.Saved().closed = closed and true or false
	if panel then
		panel:SetShown(not closed)
	end
	if P.toggle then
		P.toggle:SetLabel(closed and L["CraftWise >"] or L["CraftWise <"])
	end
	if not closed then
		P.Update()
	end
end

function P.Toggle()
	P.SetClosed(not P.Closed())
	return not P.Closed()
end

function P.SectionOpen(key)
	if key == "run" then
		return P.RunState().open and true or false
	end
	local saved = P.Saved().sections[key]
	if saved ~= nil then
		return saved
	end
	return P.defaultOpen[key] and true or false
end

function P.SetSection(key, open)
	if key == "run" then
		P.RunState().open = open and true or false
	else
		P.Saved().sections[key] = open and true or false
	end
	P.Update()
end

-- "- Flips (3)" / "+ Flips (3)".
function P.HeadLabel(key, text)
	return (P.SectionOpen(key) and "- " or "+ ") .. text
end

-- Shows a tooltip of ours on a row: the title and the lines; nothing when there are none.
local function RowTip(r, fn)
	r:SetScript("OnEnter", function(self)
		local title, tipLines = fn(self)
		if title then
			Style.ShowTip(self, title, unpack(tipLines or {}))
		end
	end)
	r:SetScript("OnLeave", function(self)
		Style.HideTip(self)
	end)
end

-- The item's name, never its ID (#328): an item the client hasn't cached is asked for (one load request, the
-- shared throttle in ns.RequestItemData) and shows "…" until ITEM_DATA_LOAD_RESULT redraws the panel.
P.PLACEHOLDER = "…"
local function ItemName(itemID)
	local name = ns.ItemInfoNow and ns.ItemInfoNow(itemID)
	if name then
		return name
	end
	if ns.RequestItemData then
		ns.RequestItemData(itemID, "AHPanel")
	end
	return P.PLACEHOLDER
end

function P.Lines()
	if not cached then
		cached = ns.AHBuy.Lines()
	end
	return cached
end

-- The text of a line row: "Linen Cloth ×15 · max 99c" ("snipe" in front when it is on the snipe list).
function P.LineText(l)
	local t = ("%s ×%d"):format(ItemName(l.itemID), l.need)
	if l.maxUnit then
		t = t .. " · max " .. Money(l.maxUnit)
	end
	if l.snipe then
		t = t .. " · " .. L["snipe"]
	end
	return t
end

-- What a line is: "snipe" (his list), "flip" (AH → vendor) or "basket"; the group a row sits under.
function P.GroupOf(l)
	return l.snipe and "snipe" or l.kind
end

P.GROUPS = { "snipe", "flip", "basket" }

local function Mark(mark, text)
	return (mark and (mark .. " ") or "") .. text
end

-- The model of the panel from the lines (pure reads: the stored tiers, the vendor price kept on the line, the
-- market price): { groups = { snipe = { row... }, flip = {...}, basket = {...} }, totals, scanT }. A row is
-- { line, group, figures } with figures = Loops.FlipLine for a flip, Loops.BasketLine for a basket line, none
-- for a snipe (its max price and limit are the line itself). Nothing is guessed: a figure the data can't give is nil.
function P.Model(list)
	local model = { groups = { snipe = {}, flip = {}, basket = {} } }
	local house = ns.ProfitHouse and ns.ProfitHouse()
	local atLeast = {}
	for _, f in ipairs(ns.Basket and ns.Basket.Flips() or {}) do
		atLeast[f.itemID] = f.atLeast
	end
	local flipLines = {}
	for _, l in ipairs(list or {}) do
		local group = P.GroupOf(l)
		local row = { line = l, group = group }
		if group == "flip" then
			row.sub = l.single and "one" or "bulk" -- two headings: bulk flips first, then one by one (#344)
		end
		if group == "flip" then
			local depth = house and ns.Market and ns.Market.Depth and ns.Market.Depth(l.itemID, house, 8)
			row.atLeast = atLeast[l.itemID] and true or false
			row.figures = ns.Loops.FlipLine(l.need, ns.Loops.TiersOf(depth), l.sell, row.atLeast)
			flipLines[#flipLines + 1] = { need = l.need, sell = l.sell or 0, figures = row.figures, buys = l.buys }
		elseif group == "basket" then
			local quote = ns.AuctionQuote and ns.AuctionQuote(l.itemID)
			row.figures = ns.Loops.BasketLine(l.need, quote and quote.copper)
		end
		local g = model.groups[group]
		g[#g + 1] = row
	end
	if #flipLines > 0 then
		model.totals = ns.Loops.FlipTotals(flipLines)
	end
	local flips = ns.db and ns.db.flips
	model.scanT = flips and flips.t
	return model
end

local function Gain(profit, mark)
	if profit == nil then
		return "?"
	end
	return Mark(mark, (profit < 0 and "-" or "+") .. Money(math.abs(profit)))
end

-- The summary at the top of the panel: "Flips: cost 12g · vendor 20g · profit +8g" and, second, where the figures
-- come from ("from the scan 12m ago"). nil when there are no flip lines.
function P.SummaryText(totals, scanT, now)
	if not totals then
		return nil
	end
	local t = L["Flips"] .. ": " .. L["cost"] .. " " .. Mark(totals.costMark, Money(totals.cost)) .. " · " .. L["vendor"] .. " "
		.. Mark(totals.vendorMark, Money(totals.vendor)) .. " · " .. L["profit"] .. " " .. Gain(totals.profit, totals.profitMark)
	local buys = totals.buys and totals.buys > 0 and ((totals.buysKnown and "" or "≥ ") .. totals.buys .. (totals.buys == 1 and " buy" or " buys") .. " · ") or ""
	local age
	if scanT and ns.Market and ns.Market.FormatAge then
		age = (L["from the scan %s ago; the live search may differ"]):format(ns.Market.FormatAge(math.max(0, (now or time()) - scanT)))
	else
		age = L["scan age unknown; the live search may differ"]
	end
	return t, buys .. age
end

-- The heading of a group: "Flips (3)".
function P.GroupHeading(group, n)
	local name = ({ snipe = L["Snipes"], flip = L["Flips"], basket = L["Basket"] })[group]
	return ("%s (%d)"):format(name, n)
end

-- The heading of a flip sub-group: "Flips · bulk (3)" and "Flips · one by one (2)".
function P.FlipHeading(sub, n)
	return ("%s · %s (%d)"):format(L["Flips"], sub == "one" and L["one by one"] or L["bulk"], n)
end

-- Right end of a flip's first line (#339): "+3c each · 52 buys" or "1 buy"; nil for other rows.
function P.RowEach(row)
	return row.group == "flip" and ns.Loops.EachText(row.line) or nil
end

-- First line of a row: "Linen Cloth ×15" (≥ when the flip lists more than the tiers show).
function P.RowName(row)
	local l = row.line
	return ("%s ×%s%d"):format(ItemName(l.itemID), row.atLeast and "≥" or "", l.need)
end

-- Second line of a row: what it costs, what a vendor pays and the profit (flip); the max per unit and "up to"
-- (snipe); the quantity's cost from the market price, or nothing (basket).
function P.RowDetail(row)
	local l, f = row.line, row.figures
	if row.group == "flip" then
		if not f then
			return L["no stored prices for the cost"] .. " · " .. L["vendor"] .. " " .. Money((l.sell or 0) * l.need)
		end
		return L["cost"] .. " " .. Mark(f.costMark, Money(f.cost)) .. " · " .. L["vendor"] .. " " .. Mark(f.vendorMark, Money(f.vendor))
			.. " · " .. L["profit"] .. " " .. Gain(f.profit, f.profitMark)
	elseif row.group == "snipe" then
		return L["max"] .. " " .. Money(l.maxUnit) .. " " .. L["each"] .. " · " .. L["up to"] .. " " .. l.need
	end
	if not f then
		return L["no market price"]
	end
	return L["cost"] .. " " .. L["about"] .. " " .. Money(f.cost) .. " (" .. L["market price"] .. ")"
end

-- The one figure at the right of a row (#402): the profit of a flip ("+2s 65c"), the max price of a snipe, the market
-- cost of a basket line. The rest of RowDetail and RowEach is in the tooltip.
function P.RowRight(row)
	local f = row.figures
	if row.group == "flip" then
		return f and Gain(f.profit, f.profitMark) or "?"
	elseif row.group == "snipe" then
		return L["max"] .. " " .. Money(row.line.maxUnit)
	end
	return f and (L["about"] .. " " .. Money(f.cost)) or ""
end

-- The tooltip of a row: its name, then the cost, the vendor price and the profit (flip), the max and the limit
-- (snipe), the market cost (basket), and for a flip the price steps and the number of buys.
function P.RowTipLines(row)
	local lines = { P.RowDetail(row) }
	local each = P.RowEach(row)
	if each then
		lines[#lines + 1] = each
	end
	return lines
end

-- The text of a result row: "12 × 3s 40c = 40s 80c" is built by ResultText below.

-- What the line under the buttons says: AHBuy's message first, else the profit of the plan, else why there is no
-- plan (a button that is off must say why): no line picked, searching, nothing listed.
function P.StatusText(S, plan, why)
	if S.message then
		return S.message
	end
	if plan then
		return plan.profit and (L["Profit %s"]):format(Money(plan.profit)) or nil
	end
	if not S.target then
		return L["Click a line to search it first"]
	end
	return why
end

-- The form below the lines: fills it from a line or an item ID (nothing is saved or searched).
function P.Prefill(what)
	local itemID = type(what) == "table" and what.itemID or what
	local entry = itemID and ns.Snipe.Find(itemID)
	local max = entry and entry.max or type(what) == "table" and what.maxUnit or nil
	P.form = { item = itemID and tostring(itemID) or "", max = max and ns.Snipe.PriceText(max) or "",
		upTo = entry and entry.upTo and tostring(entry.upTo) or "" }
	if itemID then
		local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)
		P.form.item = name or tostring(itemID)
	end
	if P.panel and P.panel.itemBox then
		P.panel.itemBox:SetText(P.form.item)
		P.panel.maxBox:SetText(P.form.max)
		P.panel.upToBox:SetText(P.form.upTo)
		P.form = nil
	end
end

-- Saves the form into the snipe list. Returns true, or false and why (the panel shows it).
function P.Save()
	local panel = P.panel
	if not (panel and panel.itemBox) then
		return false
	end
	local itemID = ns.Snipe.ItemFromText(panel.itemBox:GetText())
	local max, why = ns.Snipe.ParsePrice(panel.maxBox:GetText())
	local upTo
	local upText = (panel.upToBox:GetText() or ""):gsub("%s+", "")
	if upText ~= "" then
		upTo = tonumber(upText)
		if not upTo then
			why = "Buy up to: a whole number"
		end
	end
	local ok
	if not itemID then
		ok, why = false, "Paste an item link or an item ID, or type a name the game knows"
	elseif max and not why then
		ok, why = ns.Snipe.Set(itemID, max, upTo)
	else
		ok = false
	end
	panel.formStatus:SetText(ok and L["Saved to the snipe list"] or why or "")
	if ok then
		panel.itemBox:SetText("")
		panel.maxBox:SetText("")
		panel.upToBox:SetText("")
	end
	return ok, why
end

-- Is the panel there to see (the auction house is open)? Drawn again so it is current.
function P.Show()
	if panel and AuctionHouseFrame and AuctionHouseFrame:IsShown() then
		P.Update()
		return true
	end
	return false
end

-- The text of a result row: "12 × 3s 40c · 2h" (units, price per unit, time left when the client says).
function P.ResultText(r, isCommodity)
	local t = ("%d × %s = %s"):format(r.qty, Money(r.unit), Money(r.qty * r.unit))
	if r.listed and r.listed > 1 then
		t = t .. " · " .. (L["%d listed, one per purchase"]):format(r.listed) -- an item row groups identical auctions (#343)
	end
	if r.left and ns.Market and ns.Market.FormatAge then
		t = t .. " · " .. ns.Market.FormatAge(r.left)
	end
	if r.own then
		t = t .. " · " .. L["yours"]
	end
	return t
end

----------------------------------------------------------------------------------------------------
-- Craft run (#388): plan from the known crafts under a budget and a time, then "Use plan" into the basket
----------------------------------------------------------------------------------------------------
-- The section at the top of the panel. Building the plan, using it and refreshing prices each start from a click here;
-- the buying is the Buy panel's and the key's (AHBuy.lua), the searching of the refresh is AHBuy.SweepStart.

P.RUN_MODE_W = 170 -- width of the budget mode button
P.runPlan = nil -- the last plan built (kept until the next one)
P.runStatus = nil -- what the section says under its buttons

function P.RunState()
	if not ns.db then
		return { open = false, mode = "none", budgetText = "", minutes = "", vendorOnly = false }
	end
	ns.db.craftRun = ns.db.craftRun or { open = false, mode = "none", budgetText = "", minutes = "", vendorOnly = false }
	return ns.db.craftRun
end

P.MODES = { "none", "bags", "typed" }

function P.RunModeText(st)
	if st.mode == "bags" then
		return L["Budget: gold in bags"] .. (GetMoney and (" " .. Money(GetMoney())) or "")
	elseif st.mode == "typed" then
		return L["Budget: typed"]
	end
	return L["Budget: no limit"]
end

-- The budget in copper from the mode: nil = no limit. A typed budget that does not read gives nil and why.
function P.RunBudget()
	local st = P.RunState()
	if st.mode == "bags" then
		return GetMoney and GetMoney() or nil
	elseif st.mode == "typed" then
		local copper = ns.Snipe.ParsePrice(st.budgetText)
		if not copper then
			return nil, L["Budget: type it like 50g or 12g 50s"]
		end
		return copper
	end
	return nil
end

-- The crafting time in seconds from the minutes box: nil = no limit. A box that does not read gives nil and why.
function P.RunSeconds()
	local text = tostring(P.RunState().minutes or ""):gsub("%s+", "")
	if text == "" then
		return nil
	end
	local n = tonumber(text)
	if not (n and n > 0) then
		return nil, L["Minutes: a number above 0, or empty for no limit"]
	end
	return n * 60
end

local function Minutes(seconds)
	return ns.CraftLog.FormatDuration(seconds)
end

local function PerMinute(profit, seconds)
	if not (profit and seconds and seconds > 0) then
		return nil
	end
	return Money(math.floor(profit / seconds * 60)) .. "/" .. L["min"]
end

-- First line of a plan line: "6 × Leather Gloves · AH".
function P.RunLineName(l)
	return ("%d × %s · %s"):format(l.count, l.name or ItemName(l.outputItemID), l.channel)
end

-- Second line: "profit 12g (2g each) · 4 min · 3g/min", and "(cast time, not measured)" when the time is not measured.
function P.RunLineDetail(l)
	local t = L["profit"] .. " " .. Money(math.floor(l.profit)) .. " (" .. Money(math.floor(l.profitEach)) .. " " .. L["each"] .. ") · "
		.. Minutes(l.seconds)
	local pm = PerMinute(l.profit, l.seconds)
	if pm then
		t = t .. " · " .. pm
	end
	if l.timeLabel and l.timeLabel ~= "measured" then
		t = t .. " (" .. L[l.timeLabel] .. ")"
	end
	return t
end

-- Third line: where the demand cap comes from, "vendor: no limit" for a vendor sale.
function P.RunLineSource(l)
	if l.channel == "vendor" then
		return L["sells to a vendor: no demand limit"]
	end
	return (l.capText or "") .. (l.capped and (" · " .. L["limit reached"]) or "")
end

-- "Cost 45g · profit 80g · 38 min · 2g/min" (cost = what is still to be bought after the bags).
function P.RunTotals(plan)
	local t = L["Cost"] .. " " .. Money(plan.cost) .. " · " .. L["profit"] .. " " .. Money(math.floor(plan.profit)) .. " · " .. Minutes(plan.seconds)
	local pm = PerMinute(plan.profit, plan.seconds)
	return pm and (t .. " · " .. pm) or t
end

-- Why the plan stops where it does, and what was left out.
function P.RunLimitText(plan)
	local parts = {}
	if plan.limit == "budget" then
		parts[#parts + 1] = L["Stopped by the budget"]
	elseif plan.limit == "time" then
		parts[#parts + 1] = L["Stopped by the time"]
	elseif plan.limit == "demand" then
		parts[#parts + 1] = L["Stopped by the demand: more would not sell"]
	elseif plan.limit == "supply" then
		parts[#parts + 1] = L["Stopped by the AH supply: not enough is listed"]
	end
	local s = plan.skipped or {}
	if (s.noTime or 0) > 0 then
		parts[#parts + 1] = (L["%d without a craft time"]):format(s.noTime)
	end
	if (s.noSale or 0) > 0 then
		parts[#parts + 1] = (L["%d with no sale price"]):format(s.noSale)
	end
	if (s.noPrice or 0) > 0 then
		parts[#parts + 1] = (L["%d with a reagent price missing"]):format(s.noPrice)
	end
	return #parts > 0 and table.concat(parts, " · ") or nil
end

-- A buy line: "40 × Linen Cloth · AH 12g" or "· vendor 3g".
function P.RunBuyText(l)
	local where
	if not l.quote then
		where = L["no price"]
	elseif l.quote.source == "vendor" then
		where = L["vendor"] .. " " .. Money(l.quote.cost)
	else
		where = "AH " .. Money(l.quote.cost)
	end
	return ("%d × %s · %s"):format(l.quantity, ItemName(l.itemID), where)
end

-- The line under the section's buttons after a build.
function P.RunSummary(plan)
	if #plan.lines == 0 then
		return L["Nothing earns under these limits"]
	end
	return (L["%d suggestions: pick them in Make › Basket"]):format(#plan.lines)
end

-- What the basket holds, as the section's one summary line: "6 recipes · 14 crafts in the basket".
function P.BasketSummary()
	local recipes, crafts = 0, 0
	for _, e in ipairs(ns.Basket.Entries()) do
		recipes, crafts = recipes + 1, crafts + (e.count or 0)
	end
	if recipes == 0 then
		return L["Nothing in the basket"]
	end
	return (L["%d recipes · %d crafts in the basket"]):format(recipes, crafts)
end

-- Build plan (#403): a suggestion list to pick from, in the main window (Make › Basket). Nothing is ticked; "Tick best
-- within budget" there ticks what the limits here would have planned. `open` shows the window (a click, not a refresh).
function P.RunBuild(open)
	local st = P.RunState()
	local budget, why = P.RunBudget()
	local seconds, why2 = P.RunSeconds()
	if why or why2 then
		P.runStatus = why or why2
		P.Update()
		return nil
	end
	local limits = { budget = budget, seconds = seconds, vendorOnly = st.vendorOnly }
	local all = ns.Basket.BuildRun({ vendorOnly = st.vendorOnly })
	local best = all
	if budget or seconds then
		best = ns.Basket.BuildRun(limits)
	end
	P.runPlan = best -- the plan the limits give: its items are the ones "Refresh prices" searches
	ns.Basket.SuggestStart(all, best, limits)
	P.runStatus = P.RunSummary(all)
	if open and #all.lines > 0 and ns.OpenMainWindow then
		ns.OpenMainWindow("basket")
	end
	P.Update()
	return all
end

function P.RunRefresh()
	if ns.AHBuy.SweepRunning() then
		ns.AHBuy.SweepStop()
		return
	end
	local plan = P.runPlan
	if not (plan and #plan.search > 0) then
		P.runStatus = L["Build a plan first"]
		P.Update()
		return
	end
	ns.AHBuy.SweepStart(plan.search)
end

-- A finished or stopped refresh rebuilds the plan from the new prices (a plan was there, same limits).
ns.Listen("SWEEP_DONE", function()
	if P.runPlan and ns.db and ns.Basket.suggest then -- the list is open: it follows the new prices, ticks and counts kept
		P.RunBuild()
	end
end)

local function Put(frame, x, y)
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", panel, "TOPLEFT", x, y)
end

-- Puts the strings one under the other from y, each as tall as its (wrapped) text, so a long line pushes the next one down
-- instead of being drawn over it (#397). Returns the y under the last one.
function P.Stack(strings, x, y)
	for _, fs in ipairs(strings) do
		Put(fs, x, y)
		y = y - math.max(fs:GetStringHeight() or 0, 0) - 1
	end
	return y
end

-- Draws the section from y; returns the y below it: the controls (budget, minutes, vendor only, Build plan, Refresh
-- prices) and one summary line of what the basket holds (#403). The suggestions themselves are in Make › Basket.
local function DrawRun(y)
	local st = P.RunState()
	local run = panel.run
	Put(run.head, 12, y)
	run.head:SetLabel(P.HeadLabel("run", L["Craft run"]))
	y = y - 28
	local widgets = { run.mode, run.budget, run.minutes, run.minLabel, run.vendor, run.build, run.refresh, run.summary, run.status }
	for _, w in ipairs(widgets) do
		w:SetShown(false)
	end
	if not st.open then
		return y
	end
	local sweeping = ns.AHBuy.SweepRunning()
	Put(run.mode, 12, y)
	run.mode:SetLabel(P.RunModeText(st))
	run.mode:SetShown(true)
	run.budget:SetShown(st.mode == "typed")
	if st.mode == "typed" then
		Put(run.budget, 12 + P.RUN_MODE_W + 6, y)
		if run.budget:GetText() ~= (st.budgetText or "") then
			run.budget:SetText(st.budgetText or "")
		end
	end
	y = y - 28
	Put(run.minutes, 12, y)
	run.minutes:SetShown(true)
	if run.minutes:GetText() ~= (st.minutes or "") then
		run.minutes:SetText(st.minutes or "")
	end
	Put(run.minLabel, 12 + 44, y - 6)
	run.minLabel:SetShown(true)
	Put(run.vendor, 12 + 44 + 60, y - 4)
	run.vendor:SetChecked(st.vendorOnly)
	run.vendor:SetShown(true)
	y = y - 30
	Put(run.build, 12, y)
	run.build:SetShown(true)
	Put(run.refresh, 12 + 86, y)
	run.refresh:SetLabel(sweeping and L["Stop"] or L["Refresh prices"])
	run.refresh:SetShown(true)
	run.refresh:SetEnabled(sweeping or (P.runPlan ~= nil and #P.runPlan.search > 0))
	y = y - 30
	run.summary:SetText(P.BasketSummary())
	Put(run.summary, 12, y)
	run.summary:SetShown(true)
	y = y - 16
	local text = (sweeping and ns.Market.SweepText()) or P.runStatus
	if text then
		run.status:SetText(text)
		Put(run.status, 12, y)
		run.status:SetShown(true)
		y = y - 18
	end
	return y - 6
end

-- The section's widgets (Create passes its edit box maker).
local function CreateRun(Box)
	local run = {}
	panel.run = run
	run.head = Style.LineButton(panel, L["Craft run"], 110)
	run.head:SetScript("OnClick", function()
		P.SetSection("run", not P.SectionOpen("run"))
	end)
	run.mode = Style.LineButton(panel, L["Budget: no limit"], P.RUN_MODE_W)
	run.mode:SetScript("OnClick", function()
		local st = P.RunState()
		local at = 1
		for i, m in ipairs(P.MODES) do
			if m == st.mode then
				at = i
			end
		end
		st.mode = P.MODES[at % #P.MODES + 1]
		P.Update()
	end)
	run.budget = Box(80)
	run.budget:SetScript("OnTextChanged", function(self, user)
		if user then
			P.RunState().budgetText = self:GetText()
		end
	end)
	run.minutes = Box(40, true)
	run.minutes:SetScript("OnTextChanged", function(self, user)
		if user then
			P.RunState().minutes = self:GetText()
		end
	end)
	run.minLabel = Style.Text(panel, "Small", "text2")
	run.minLabel:SetText(L["minutes"])
	run.vendor = Style.Checkbox(panel, L["Vendor only"], false, function(checked)
		P.RunState().vendorOnly = checked and true or false
	end)
	run.build = Style.ActionButton(panel, L["Build plan"], 80, 24)
	run.build:SetScript("OnClick", function()
		P.RunBuild(true)
	end)
	run.build:HookScript("OnEnter", function(self)
		Style.ShowTip(self, L["Build plan"], L["Opens a list of suggested crafts in the main window (Make › Basket). Nothing is ticked: you pick."])
	end)
	run.build:HookScript("OnLeave", function(self)
		Style.HideTip(self)
	end)
	run.refresh = Style.LineButton(panel, L["Refresh prices"], 110)
	run.refresh:SetScript("OnClick", function()
		P.RunRefresh()
	end)
	run.summary = Style.Text(panel, "Small", "text")
	run.status = Style.Text(panel, "Small", "text2")
	for _, fs in ipairs({ run.summary, run.status }) do
		fs:SetWidth(P.WIDTH - 24)
		fs:SetJustifyH("LEFT")
		fs:SetWordWrap(false)
	end
end

local function LineRow(i)
	local r = lines[i]
	if r then
		return r
	end
	r = CreateFrame("Button", nil, panel)
	r:SetSize(P.WIDTH - 24, P.ROW)
	r.text = Style.Text(r, "Small", "text")
	r.text:SetPoint("TOPLEFT", r, "TOPLEFT", 4, -3)
	r.text:SetWidth(P.WIDTH - 24 - P.FIGURE_W - 28)
	r.text:SetJustifyH("LEFT")
	r.text:SetWordWrap(false)
	r.each = Style.Text(r, "Small", "text2")
	r.each:SetPoint("TOPRIGHT", r, "TOPRIGHT", -4, -3)
	r.each:SetWidth(P.FIGURE_W)
	r.each:SetJustifyH("RIGHT")
	r.each:SetWordWrap(false)
	r.mark = r:CreateTexture(nil, "BACKGROUND")
	r.mark:SetAllPoints(r)
	Style.Fill(r.mark, Style.C.selected)
	r:SetScript("OnClick", function(self)
		if self.line and ns.AHBuy.Pick(self.line) then
			P.Prefill(self.line) -- the form below shows this line's item and max price
			ns.AHBuy.Search() -- one click: pick and search this line, nothing more
		end
	end)
	RowTip(r, function(self)
		if self.row then
			return P.RowName(self.row), P.RowTipLines(self.row)
		end
	end)
	-- The × of a snipe line takes it off the list (nothing else; no search, no purchase).
	r.remove = CreateFrame("Button", nil, r)
	r.remove:SetSize(22, 22)
	r.remove:SetPoint("TOPRIGHT", r, "TOPRIGHT", 0, 0)
	r.remove.text = Style.Text(r.remove, "Small", "text3")
	r.remove.text:SetPoint("CENTER")
	r.remove.text:SetText("×")
	r.remove:SetScript("OnClick", function(self)
		local line = self:GetParent().line
		if line and line.snipe then
			ns.Snipe.Remove(line.itemID)
		end
	end)
	lines[i] = r
	return r
end

-- A row is one line, never shorter than P.ROW (the name does not wrap, so rows never overlap).
function P.LineHeight(r)
	local top = math.max(r.text:GetStringHeight() or 0, r.each:GetStringHeight() or 0)
	return math.max(P.ROW, 3 + top + 4)
end

local function ResultText(i)
	local fs = results[i]
	if not fs then
		fs = Style.Text(panel, "Small", "text2")
		fs:SetWidth(P.WIDTH - 24)
		fs:SetJustifyH("LEFT")
		results[i] = fs
	end
	return fs
end

----------------------------------------------------------------------------------------------------
-- Craft run (#390, #399): post the run's AH items all at once. A line says how many to post now and for how long (the
-- listing duration setting, 8 h by default); the posting is the player's click on Blizzard's sell frame (nothing here
-- posts, and nothing runs on a timer). The cap of the plan is what one such listing sells, so there are no batches.
----------------------------------------------------------------------------------------------------

P.POST_LINES = 10
local postRows = {}

-- The state of an item in full, for its tooltip: "Leather Gloves: post all 5 now (8 h)" ("post 2 now" when part of it
-- is listed or not in the bags; nothing to post: "none in the bags" or "listed 3 of 3").
function P.PostStateText(l, name)
	if l.postNow > 0 then
		if l.postNow >= l.units then
			return (L["%s: post all %d now (%d h)"]):format(name, l.postNow, l.hours)
		end
		return (L["%s: post %d now (%d h)"]):format(name, l.postNow, l.hours)
	end
	if l.bags == 0 then
		return (L["%s: none in the bags"]):format(name)
	end
	return (L["%s: listed %d of %d"]):format(name, l.listed, l.units)
end

-- The line of an item (#402): "Wild Leather Shoulders  post 1 · 76s 99c"; "Deviate Scale Belt  craft first" when none is
-- in the bags; "... listed 3 of 3" when it is all up. Everything else is in the tooltip (P.PostTipLines).
function P.PostLineText(l, name)
	if l.postNow > 0 then
		local t = (L["%s  post %d"]):format(name, l.postNow)
		return l.price and (t .. " · " .. Money(l.price)) or t
	end
	if l.bags == 0 then
		return (L["%s  craft first"]):format(name)
	end
	return (L["%s  listed %d of %d"]):format(name, l.listed, l.units)
end

-- "bags 5 · listed 1 · sold 3 today · lowest 3g 40s".
function P.PostDetail(l)
	local parts = { (L["bags %d"]):format(l.bags), (L["listed %d"]):format(l.listed) }
	if l.sold and l.sold > 0 then
		parts[#parts + 1] = (L["sold %d today"]):format(l.sold)
	end
	parts[#parts + 1] = l.price and (L["lowest %s"]):format(Money(l.price)) or L["no listing seen"]
	return table.concat(parts, " · ")
end

-- Where the plan's amount comes from (the cap text of the plan: your sales in one listing).
function P.PostSource(l)
	return l.demandText or ""
end

-- The tooltip of an item: the full state, the numbers, where the amount comes from, and how to post.
function P.PostTipLines(l, name)
	local lines = { P.PostStateText(l, name), P.PostDetail(l) }
	local source = P.PostSource(l)
	if source ~= "" then
		lines[#lines + 1] = source
	end
	lines[#lines + 1] = L["Post with the auction house's own Sell tab, with the duration shown; the lowest price is the last one seen."]
	return lines
end

local function PostRow(i)
	local r = postRows[i]
	if r then
		return r
	end
	r = CreateFrame("Button", nil, panel)
	r:SetSize(P.WIDTH - 24, 16)
	r.text = Style.Text(r, "Small", "text")
	r.text:SetPoint("TOPLEFT", r, "TOPLEFT", 0, -1)
	r.text:SetWidth(P.WIDTH - 24)
	r.text:SetJustifyH("LEFT")
	r.text:SetWordWrap(false)
	RowTip(r, function(self)
		local l = self.entry
		if l then
			return self.name, P.PostTipLines(l, self.name)
		end
	end)
	postRows[i] = r
	return r
end

function P.PostLines()
	return ns.Auctions.RunPostLines()
end

-- Draws the section from y; returns the y below it.
local function DrawPost(y, list)
	P.postLines = list
	panel.postHead:SetShown(#list > 0)
	panel.postMore:SetShown(false)
	local shown = 0
	if #list > 0 then
		Put(panel.postHead, 12, y)
		panel.postHead:SetLabel(P.HeadLabel("post", (L["Post (%d)"]):format(#list)))
		y = y - 28
		if P.SectionOpen("post") then
			for i = 1, math.min(#list, P.POST_LINES) do
				local l, r = list[i], PostRow(i)
				r.entry, r.name = l, ItemName(l.itemID)
				r.text:SetText(P.PostLineText(l, r.name))
				local c = Style.Color(l.postNow > 0 and "text" or "text3") -- nothing to post now: muted
				r.text:SetTextColor(c[1], c[2], c[3], 1)
				Put(r, 12, y)
				r:Show()
				y = y - 18
				shown = i
			end
			if #list > shown then
				panel.postMore:SetText((L["+%d more"]):format(#list - shown))
				Put(panel.postMore, 12, y)
				panel.postMore:SetShown(true)
				y = y - 16
			end
		end
	end
	for i = shown + 1, #postRows do
		postRows[i]:Hide()
	end
	return y
end

-- The rows of a model, one line each, under their small headings (flip sub-groups, the basket). At most P.GROUP_LINES per
-- group; the number left out is returned. `st` counts the row and heading frames used so far (the pools are shared).
local function DrawRows(y, rows, model, S, st)
	local sizes, counts, last, hidden = {}, {}, nil, 0
	for _, row in ipairs(rows) do
		local key = row.group .. (row.sub or "")
		sizes[key] = (sizes[key] or 0) + 1
	end
	for _, row in ipairs(rows) do
		local key = row.group .. (row.sub or "")
		counts[key] = (counts[key] or 0) + 1
		if counts[key] > P.GROUP_LINES then
			hidden = hidden + 1
		else
			if key ~= last and row.group ~= "snipe" then
				st.h = st.h + 1
				local fs = headings[st.h]
				if not fs then
					fs = Style.Text(panel, "Small", "text3")
					headings[st.h] = fs
				end
				fs:SetText(row.sub and P.FlipHeading(row.sub, sizes[key]) or P.GroupHeading(row.group, #model.groups[row.group]))
				fs:ClearAllPoints()
				fs:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, y)
				fs:Show()
				y = y - 16
			end
			last = key
			local l = row.line
			st.i = st.i + 1
			local r = LineRow(st.i)
			r.line, r.row = l, row
			r:Show()
			r.text:SetText(P.RowName(row))
			r.each:SetText(P.RowRight(row))
			r.remove:SetShown(l.snipe and true or false)
			r.mark:SetShown(S.target and S.target.itemID == l.itemID and S.target.kind == l.kind)
			r:ClearAllPoints()
			r:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, y)
			local h = P.LineHeight(r)
			r:SetHeight(h)
			y = y - h
		end
	end
	return y, hidden
end

-- A collapsible section's head button; `more` is its "+N more" line.
local function Head(key, button, text, y)
	Put(button, 12, y)
	button:SetLabel(P.HeadLabel(key, text))
	button:SetShown(true)
	return y - 28
end

local function Foot(fs, hidden, y)
	fs:SetShown(hidden > 0)
	if hidden > 0 then
		fs:SetText((L["+%d more: the search key walks them all"]):format(hidden))
		Put(fs, 12, y)
		y = y - 16
	end
	return y
end

local FORM_WIDGETS = { "formTitle", "itemBox", "maxBox", "upToBox", "saveButton", "formStatus", "keys" }

-- Draws everything from AHBuy's state: the sections (Craft run, Post, Flips), the search and the Buy button, then the
-- Snipe list (its lines, the form and the key hint).
function P.Update()
	if not (panel and panel:IsShown()) then
		return
	end
	local AB, S = ns.AHBuy, ns.AHBuy.state
	local list = P.Lines()
	local model = P.Model(list)
	local postList = ns.Auctions.RunPostLines()
	local postNow = false
	for _, l in ipairs(postList) do
		if l.postNow > 0 then
			postNow = true
		end
	end
	local nFlips = #model.groups.flip + #model.groups.basket
	P.defaultOpen.post = postNow
	P.defaultOpen.flips = nFlips > 0 and not postNow
	P.defaultOpen.snipes = #model.groups.snipe > 0 and not postNow and nFlips == 0
	local y = DrawRun(-30)
	y = DrawPost(y, postList)
	local st = { i = 0, h = 0 }
	panel.linesTitle:SetShown(#list > 0)
	panel.empty:SetShown(#list == 0)
	-- Flips (and the basket's AH lines): the totals, then the rows
	panel.flipHead:SetShown(nFlips > 0)
	panel.summary:SetShown(false)
	panel.flipMore:SetShown(false)
	P.flipTip = nil
	if nFlips > 0 then
		y = Head("flips", panel.flipHead, (L["Flips (%d)"]):format(nFlips), y)
		local sum, age = P.SummaryText(model.totals, model.scanT)
		P.flipTip = age
		if P.SectionOpen("flips") then
			if sum then
				panel.summary:SetText(sum)
				panel.summary:ClearAllPoints()
				panel.summary:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, y)
				panel.summary:SetShown(true)
				y = y - 18
			end
			local rows = {}
			for _, g in ipairs({ "flip", "basket" }) do
				for _, row in ipairs(model.groups[g]) do
					rows[#rows + 1] = row
				end
			end
			local hidden
			y, hidden = DrawRows(y, rows, model, S, st)
			y = Foot(panel.flipMore, hidden, y)
		end
	end
	if #list == 0 then
		panel.empty:ClearAllPoints()
		panel.empty:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, y)
		y = y - 20
	end
	y = y - 8
	local plan, why = AB.Refresh()
	local shown = 0
	if S.target and S.isCommodity ~= nil and S.phase ~= "idle" and S.phase ~= "searching" then
		local rows = AB.ReadRows(S.target.itemID, S.isCommodity)
		for i = 1, math.min(#rows, P.RESULTS) do
			local fs = ResultText(i)
			fs:SetText(P.ResultText(rows[i], S.isCommodity))
			fs:ClearAllPoints()
			fs:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, y)
			fs:Show()
			y = y - 16
			shown = i
		end
	end
	panel.listed:SetShown(shown > 0)
	for i = shown + 1, #results do
		results[i]:Hide()
	end
	y = y - 6
	panel.search:ClearAllPoints()
	panel.search:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, y)
	panel.search:SetEnabled(S.target ~= nil and not S.busy)
	panel.buy:ClearAllPoints()
	panel.buy:SetPoint("LEFT", panel.search, "RIGHT", 8, 0)
	local text, enabled = AB.Describe(plan, why, S.phase, S.busy, GetMoney and GetMoney() or nil,
		S.isCommodity and S.target and S.target.maxUnit or nil)
	panel.buy:SetLabel(text) -- the folded button's label: SetText alone would leave "Buy" on the face
	panel.buy:SetText(text)
	panel.buy:SetEnabled(enabled)
	y = y - 30
	local status = P.StatusText(S, plan, why)
	panel.status:ClearAllPoints()
	panel.status:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, y)
	panel.status:SetText(status or "")
	y = y - 28
	-- Snipe list: its lines, then the form (item, max price per unit, "up to", Save) and the key hint; folded by default.
	y = Head("snipes", panel.snipeHead, (L["Snipe list (%d)"]):format(#model.groups.snipe), y)
	panel.snipeMore:SetShown(false)
	local open = P.SectionOpen("snipes")
	for _, k in ipairs(FORM_WIDGETS) do
		panel[k]:SetShown(open)
	end
	if open then
		local hidden
		y, hidden = DrawRows(y, model.groups.snipe, model, S, st)
		y = Foot(panel.snipeMore, hidden, y)
		y = y - 4
		panel.formTitle:ClearAllPoints()
		panel.formTitle:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, y)
		y = y - 16
		local x = 12
		for _, f in ipairs({ { panel.itemBox, 100 }, { panel.maxBox, 76 }, { panel.upToBox, 36 }, { panel.saveButton, 48 } }) do
			f[1]:ClearAllPoints()
			f[1]:SetPoint("TOPLEFT", panel, "TOPLEFT", x, y)
			x = x + f[2] + 5
		end
		y = y - 28
		panel.formStatus:ClearAllPoints()
		panel.formStatus:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, y)
		y = y - 18
		panel.keys:ClearAllPoints()
		panel.keys:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, y)
		y = y - 30
	end
	for i = st.i + 1, #lines do
		lines[i].line, lines[i].row = nil, nil
		lines[i]:Hide()
	end
	for i = st.h + 1, #headings do
		headings[i]:Hide()
	end
	panel:SetHeight(-y + 12)
end

local function Create()
	if panel or not AuctionHouseFrame then
		return
	end
	panel = CreateFrame("Frame", "CraftWiseAHPanel", AuctionHouseFrame)
	panel:SetSize(P.WIDTH, 200)
	panel:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPRIGHT", 4, -30)
	panel:SetFrameLevel((AuctionHouseFrame:GetFrameLevel() or 1) + 5)
	panel.sheet = Style.Sheet(panel, nil, nil, 10, true)
	panel.title = Style.Text(panel, "Small", "text3")
	panel.title:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -10)
	panel.title:SetText("CraftWise · " .. L["Buy"])
	panel.linesTitle = Style.Text(panel, "Small", "text3")
	panel.linesTitle:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -36, -10)
	panel.linesTitle:SetText(L["Click a line to search it"])
	-- The X closes the panel until it is opened again (the button under the auction house, `/craftwise buy`, #402).
	panel.close = Style.ActionButton(panel, "x", 22, 18)
	panel.close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -8)
	panel.close:SetScript("OnClick", function()
		P.SetClosed(true)
	end)
	panel.summary = Style.Text(panel, "Small", "text")
	panel.summary:SetWidth(P.WIDTH - 24)
	panel.summary:SetJustifyH("LEFT")
	panel.summary:SetWordWrap(false)
	panel.listed = Style.Text(panel, "Small", "text3")
	panel.listed:SetText(L["Listed now (units × price = row total)"])
	panel.empty = Style.Text(panel, "Small", "text3")
	panel.empty:SetText(L["No flips or basket AH lines."])
	panel.search = Style.ActionButton(panel, L["Search"], 70, 24)
	panel.search:SetScript("OnClick", function()
		ns.AHBuy.Search()
	end)
	panel.buy = Style.ActionButton(panel, L["Buy"], P.WIDTH - 24 - 78, 24)
	panel.buy:SetScript("OnClick", function()
		ns.AHBuy.Click()
	end)
	panel.status = Style.Text(panel, "Small", "text2")
	panel.status:SetWidth(P.WIDTH - 24)
	panel.status:SetJustifyH("LEFT")
	panel.more = Style.Text(panel, "Small", "text3")
	-- The snipe list's form (part 2). The boxes are plain edit boxes; Save is the only thing that writes.
	local function Box(width, numeric)
		local box = CreateFrame("EditBox", nil, panel)
		box:SetSize(width, 24)
		box:SetAutoFocus(false)
		box:SetFontObject(Style.Fonts.Small)
		box:SetTextInsets(6, 6, 0, 0)
		box.border = Style.Border(box, Style.C.ruleStrong)
		if numeric then
			box:SetNumeric(true)
			box:SetMaxLetters(4)
		end
		box:SetScript("OnEnterPressed", function(self)
			self:ClearFocus()
		end)
		box:SetScript("OnEscapePressed", function(self)
			self:ClearFocus()
		end)
		return box
	end
	panel.formTitle = Style.Text(panel, "Small", "text3")
	panel.formTitle:SetText(L["Snipe list: item · max per unit · up to"])
	panel.itemBox = Box(100)
	panel.maxBox = Box(76)
	panel.upToBox = Box(36, true)
	panel.saveButton = Style.ActionButton(panel, L["Save"], 48, 24)
	panel.saveButton:SetScript("OnClick", function()
		P.Save()
	end)
	CreateRun(Box)
	panel.postHead = Style.LineButton(panel, L["Post"], 150)
	panel.postHead:SetScript("OnClick", function()
		P.SetSection("post", not P.SectionOpen("post"))
	end)
	panel.postMore = Style.Text(panel, "Small", "text3")
	panel.flipHead = Style.LineButton(panel, L["Flips"], 150)
	panel.flipHead:SetScript("OnClick", function()
		P.SetSection("flips", not P.SectionOpen("flips"))
	end)
	panel.flipHead:HookScript("OnEnter", function(self) -- where the flip figures come from
		if P.flipTip then
			Style.ShowTip(self, L["Flips"], P.flipTip)
		end
	end)
	panel.flipHead:HookScript("OnLeave", function(self)
		Style.HideTip(self)
	end)
	panel.flipMore = Style.Text(panel, "Small", "text3")
	panel.snipeHead = Style.LineButton(panel, L["Snipe list"], 150)
	panel.snipeHead:SetScript("OnClick", function()
		P.SetSection("snipes", not P.SectionOpen("snipes"))
	end)
	panel.snipeMore = Style.Text(panel, "Small", "text3")
	panel.formStatus = Style.Text(panel, "Small", "text2")
	panel.formStatus:SetWidth(P.WIDTH - 24)
	panel.formStatus:SetJustifyH("LEFT")
	panel.keys = Style.Text(panel, "Small", "text3")
	panel.keys:SetWidth(P.WIDTH - 24)
	panel.keys:SetJustifyH("LEFT")
	panel.keys:SetText(L["Keys: set \"AH: search next\" and \"AH: buy best\" under Key Bindings › AddOns › CraftWise."])
	panel:SetScript("OnShow", function()
		cached = nil
		P.Update()
	end)
	P.panel = panel
	-- The button under the auction house frame shows and hides the panel (#402).
	if not P.toggle then
		P.toggle = Style.LineButton(AuctionHouseFrame, L["CraftWise <"], 110)
		P.toggle.cwAHDock = true -- docked to the AH frame by design, like the panel (tests/own_scan_progress_spec.lua)
		P.toggle:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPRIGHT", 4, -4) -- above the panel, which starts 30 down; not the bottom, where the tabs are
		P.toggle:SetScript("OnClick", function()
			P.Toggle()
		end)
	end
	P.SetClosed(P.Closed())
	if P.form then -- filled from the item menu before the auction house was opened
		panel.itemBox:SetText(P.form.item)
		panel.maxBox:SetText(P.form.max)
		panel.upToBox:SetText(P.form.upTo)
		P.form = nil
	end
end

ns.On("AUCTION_HOUSE_SHOW", function()
	Create()
	cached = nil
	P.Update()
end)
ns.Listen("AHBUY_CHANGED", P.Update)
-- The basket, the bags or the prices changed: the kept lines are out of date.
-- An item name that was not cached arrived: draw the rows again (only the rows' own items).
local function NameArrived(_, itemID)
	if not (panel and panel:IsShown()) then
		return
	end
	for _, l in ipairs(P.Lines()) do
		if l.itemID == itemID then
			P.Update()
			return
		end
	end
end
ns.On("ITEM_DATA_LOAD_RESULT", NameArrived)
ns.On("GET_ITEM_INFO_RECEIVED", NameArrived)
for _, name in ipairs({ "BASKET_CHANGED", "BAGS_CHANGED", "PRICES_CHANGED", "SNIPE_CHANGED", "AUCTIONS_CHANGED" }) do
	ns.Listen(name, function()
		cached = nil
		P.Update()
	end)
end
