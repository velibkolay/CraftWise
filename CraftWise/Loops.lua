-- Vendor loop alert (#186): after prices change, look for crafts that earn when sold to a vendor
-- (the #185 vendor check, ns.BuildRows rows: vendorProfit, vendorLoop) and tell the player once.
--   * A find = vendor profit above the minimum (Settings; default anything above 0) with the reagents at
--     today's prices; a loop = every reagent can be bought from a vendor. Known recipes, plus unlearned ones
--     when Make › Craft's Unlearned setting is on. An unknown price is never a find.
--   * One toast per check, for finds that are new or clearly better since the last notice: not announced
--     before, a loop that was not one before, or a profit at least 50 % above the announced one. What was
--     announced is kept in db.loopNotice; a find that goes away is forgotten, so it counts as new if it
--     comes back.
--   * Triggers: PRICES_CHANGED (a full scan ends, a search or browse updated prices, a merchant was seen),
--     debounced so a run of page reads gives one check. The check only reads prices and recipes.
--   * Click on the toast: Make › Craft with the Vendor check chip on (and the best find's profession).
-- Pure parts (Finds, Fresh, Summary) take plain data so the specs can feed them.
--
-- Snipes (#315, part 2): the same check for the snipe list (Snipe.lua). Items on it whose cheapest listings at the
-- profit house, in our own fresh data, are at or below his max price (equal counts) go into the same toast
-- ("3 snipes under your max"); a click opens the AH panel when the auction house is open. What was announced is
-- kept in db.snipeNotice: an item is announced again only when it is new or its cheapest price fell. Nothing is
-- bought or searched by the toast.
--
-- AH → vendor flips (#312): the item version of the same check. After the same triggers, items whose cheapest
-- buyouts at the profit house are below what a vendor pays for one unit (ns.GetVendorSellPrice).
--   * Only this account's own listings at the profit house, from Market.FreshBelow: the stored tiers (first 8
--     prices) of an observation not older than Loops.FLIP_FRESH, not marked off by a later full scan. Never
--     Auctionator's mixed-house prices. An unknown or 0 vendor price, or no tiers, is never a flip.
--   * units = the units in the tiers priced below the vendor price; profit = sum of (vendor price - tier
--     price) x units (vendors take no cut). "at least": every stored tier is below, so more may be listed.
--   * The toast is shared with the loop alert (one line per check); what was announced is kept in
--     db.flipNotice (same Loops.BETTER rule). The flips are put into the basket (Basket.SetFlips) and the
--     Auctionator list "CraftWise vendor flips" is refreshed from them (Basket.CreateFlipList). Nothing is
--     bought, bid on or confirmed: that stays the player's click.
local _, ns = ...

local Loops = {}
ns.Loops = Loops

Loops.DEBOUNCE = 4 -- seconds after the last price change before the check runs
Loops.BETTER = 1.5 -- announced again when the profit is at least this times the announced one

local function Settings()
	return ns.db and ns.db.settings or {}
end

function Loops.Enabled()
	return Settings().loopAlert ~= false
end

function Loops.MinProfit()
	return tonumber(Settings().loopAlertMin) or 0
end

Loops.FLIP_FRESH = 30 * 60 -- seconds: an observation older than this is not "this scan" (#312)
Loops.FLIP_MIN = 100 -- copper: default smallest total profit per item (provisional, #312)

function Loops.FlipEnabled()
	return Settings().flipAlert ~= false
end

Loops.FLIP_EACH_MIN = 100 -- copper: default smallest profit per purchase of a one-at-a-time item (provisional, #339)

-- The smallest margin (vendor price - the auction's unit price) an auction of a one-at-a-time item needs to count
-- as a flip: each such auction is one purchase (one PlaceBid per press), so a few copper is not worth the press.
function Loops.FlipEachMin()
	local min = tonumber(Settings().flipEachMin)
	return min or Loops.FLIP_EACH_MIN
end

-- The most units an item stacks to, from the client's item info; nil while the item is not cached. 1 = it does not
-- stack: every auction of it is one unit and one purchase.
function Loops.StackOf(itemID)
	if not (C_Item and C_Item.GetItemInfo and itemID) then
		return nil
	end
	local stack = select(8, C_Item.GetItemInfo(itemID))
	return tonumber(stack)
end

function Loops.SnipeEnabled()
	return Settings().snipeAlert ~= false
end

function Loops.FlipMin()
	local min = tonumber(Settings().flipAlertMin)
	return min or Loops.FLIP_MIN
end

-- The flip in stored tiers: tiers = { p1, q1, ... } ascending, total = units listed, sell = what a vendor pays
-- per unit. nil when no tier is below it. { units, profit, atLeast, price (cheapest), sell, maxUnit }: maxUnit
-- is the highest unit price that still earns (one copper under the vendor price).
-- Purchases (#339): `stack` is the item's stack size. An item that does not stack (stack 1) is bought one auction
-- (= one unit) per purchase, so only the tiers whose own margin reaches `minEach` count (default 1c), maxUnit is
-- the vendor price minus that margin, `each` is the best margin and `buys` the units. Anything else (stack above
-- 1: a commodity, one purchase for any quantity; stack nil: not known) keeps the rule above, `each` is the total
-- profit and `buys` is 1 for a known stack above 1, nil when unknown (nothing is guessed). `single` marks the
-- one-at-a-time items.
function Loops.Flip(tiers, total, sell, stack, minEach)
	if not (sell and sell > 0 and tiers) then
		return nil
	end
	local single = stack == 1
	local margin = single and math.max(1, minEach or 1) or 1
	local units, profit, n = 0, 0, 0
	for i = 1, #tiers, 2 do
		local price, qty = tiers[i], tiers[i + 1]
		if not (price and qty and price <= sell - margin) then
			break
		end
		units = units + qty
		profit = profit + (sell - price) * qty
		n = n + 1
	end
	if units == 0 then
		return nil
	end
	-- Every stored tier is below the vendor price and the list may go on: eight tiers are all that is stored,
	-- or the units listed are more than the tiers hold.
	local atLeast = n * 2 == #tiers and (#tiers >= 16 or units < (total or 0))
	local f = { units = units, profit = profit, atLeast = atLeast, price = tiers[1], sell = sell, maxUnit = sell - margin }
	f.single = single
	f.each = single and sell - tiers[1] or profit
	f.buys = single and units or (stack and stack > 1 and 1 or nil)
	return f
end

-- The buying panel's figures (#328). Pure: they read nothing and only add up what the stored tiers say.
-- Cost of the cheapest `need` units from tiers = { p1, q1, ... } ascending: returns the copper and the units
-- the tiers covered (less than `need` when the stored tiers end first).
function Loops.TierCost(tiers, need)
	local cost, got = 0, 0
	for i = 1, #(tiers or {}), 2 do
		local price, qty = tiers[i], tiers[i + 1]
		if not (price and qty) or got >= need then
			break
		end
		local take = math.min(qty, need - got)
		cost, got = cost + price * take, got + take
	end
	return cost, got
end

-- Stored depth rows ({ price, qty } ...) as the flat tier list.
function Loops.TiersOf(depth)
	local tiers = {}
	for _, d in ipairs(depth or {}) do
		tiers[#tiers + 1], tiers[#tiers + 2] = d.price, d.qty
	end
	return tiers
end

-- The figures of a flip line for `need` units (what is still missing: the bags count) at `sell` per unit from a
-- vendor. { cost, vendor, profit, costMark, profitMark }; a mark is "≥" or "≤" where the figure is only a bound:
--   * atLeast (the flip lists "N or more" units): more units only add profit, so all three are "≥";
--   * the tiers hold fewer than `need` units: the cost is a lower bound ("≥") and so the profit an upper one ("≤").
-- nil without tiers or need: nothing is guessed.
function Loops.FlipLine(need, tiers, sell, atLeast)
	if not (need and need > 0 and sell and tiers and #tiers >= 2) then
		return nil
	end
	local cost, got = Loops.TierCost(tiers, need)
	local f = { cost = cost, vendor = sell * need, profit = sell * need - cost }
	if got < need then
		f.costMark, f.profitMark = "≥", "≤"
	elseif atLeast then
		f.costMark, f.profitMark, f.vendorMark = "≥", "≥", "≥"
	end
	return f
end

-- "+3c each · 52 buys" for a one-at-a-time item, "1 buy" for a commodity (stack above 1), "buys not known" when the
-- stack size was not cached; nil for a flip stored before the figures existed. f: a flip or a line made from one.
function Loops.EachText(f)
	if not (f and f.each) then
		return nil
	end
	if f.single then
		return ("+%s each · %d %s"):format(ns.FormatMoney(f.each, true), f.buys or 0, (f.buys or 0) == 1 and "buy" or "buys")
	end
	return f.buys == 1 and "1 buy" or "buys not known"
end

-- Totals of the flip lines: figures = FlipLine results (false/nil for a line without figures). Returns
-- { cost, vendor, profit, costMark, profitMark, unknown }. `vendor` needs no tiers (the vendor price is known) so
-- it is passed in with the line's units: lines = { { need, sell, figures } }. The profit is nil when a line has
-- no figures or the lines' bounds point both ways.
function Loops.FlipTotals(lines)
	local t = { cost = 0, vendor = 0, profit = 0, unknown = 0 }
	local ge, le, anyCost, anyVendor = false, false, false, false
	t.buys, t.buysKnown = 0, true
	for _, l in ipairs(lines or {}) do
		t.vendor = t.vendor + l.sell * l.need
		if l.buys then
			t.buys = t.buys + l.buys
		else
			t.buysKnown = false -- a line whose purchases are not known: the count is a lower bound
		end
		local f = l.figures
		if f then
			t.cost, t.profit = t.cost + f.cost, t.profit + f.profit
			anyCost = anyCost or f.costMark ~= nil
			anyVendor = anyVendor or f.vendorMark ~= nil
			ge = ge or f.profitMark == "≥"
			le = le or f.profitMark == "≤"
		else
			t.unknown = t.unknown + 1
		end
	end
	if t.unknown > 0 then
		t.costMark = "≥" -- the lines without figures add cost that is not in the sum
		t.profit = nil
	elseif ge and le then
		t.profit = nil
	elseif le then
		t.profitMark = "≤"
	elseif ge then
		t.profitMark = "≥"
	end
	if anyCost then
		t.costMark = "≥"
	end
	if anyVendor then
		t.vendorMark = "≥"
	end
	return t
end

-- A basket line: `need` units at one known unit price (the market price CraftWise has). No price, no figure.
-- The mark is "about": one price for every unit, the listing's depth is not looked at.
function Loops.BasketLine(need, unit)
	if not (need and need > 0 and unit and unit > 0) then
		return nil
	end
	return { cost = need * unit, mark = "~" }
end

-- rows: Market.FreshBelow rows. Returns the flips (Flip plus itemID), those with a total profit of at least `min`
-- (and above 0), best first: by profit per purchase (`each`), ties by the higher total (#339). stackOf(itemID) is
-- the item's stack size and minEach the smallest margin of a one-at-a-time auction (both optional).
function Loops.FlipFinds(rows, sellOf, min, stackOf, minEach)
	local out = {}
	for _, r in ipairs(rows or {}) do
		local f = Loops.Flip(r.tiers, r.total, sellOf(r.itemID), stackOf and stackOf(r.itemID), minEach)
		if f and f.profit > 0 and f.profit >= (min or 0) then
			f.itemID, f.t = r.itemID, r.t
			out[#out + 1] = f
		end
	end
	table.sort(out, function(a, b)
		if a.each ~= b.each then
			return a.each > b.each
		end
		if a.profit ~= b.profit then
			return a.profit > b.profit
		end
		return a.itemID < b.itemID
	end)
	return out
end

-- Flips worth a notice against `notice` ([itemID] = { profit } announced before), and the notice to keep.
function Loops.FlipFresh(finds, notice)
	local fresh, keep = {}, {}
	for _, f in ipairs(finds) do
		local old = notice and notice[f.itemID]
		if not old or f.profit >= (old.profit or 0) * Loops.BETTER then
			fresh[#fresh + 1] = f
			keep[f.itemID] = { profit = f.profit }
		else
			keep[f.itemID] = old
		end
	end
	return fresh, keep
end

-- "5 AH → vendor flips"; nil without any.
function Loops.FlipSummary(fresh)
	if #fresh == 0 then
		return nil
	end
	return ("%d AH → vendor %s"):format(#fresh, #fresh == 1 and "flip" or "flips")
end

-- The flips at the profit house right now, best first. Read only.
function Loops.FlipCheck()
	local house = ns.ProfitHouse and ns.ProfitHouse()
	if not (house and ns.Market and ns.Market.FreshBelow) then
		return {}
	end
	local rows = ns.Market.FreshBelow(house, time(), Loops.FLIP_FRESH, ns.GetVendorSellPrice)
	return Loops.FlipFinds(rows, ns.GetVendorSellPrice, Loops.FlipMin(), Loops.StackOf, Loops.FlipEachMin())
end

-- The snipes at the profit house right now, in list order. Read only.
function Loops.SnipeCheck()
	local house = ns.ProfitHouse and ns.ProfitHouse()
	if not (house and ns.Snipe and ns.Market and ns.Market.FreshBelow and #ns.Snipe.Entries() > 0) then
		return {}
	end
	return ns.Snipe.Finds(ns.Market.FreshBelow(house, time(), Loops.FLIP_FRESH, ns.Snipe.LimitOf))
end

-- Snipes worth a notice against `notice` ([itemID] = { price } announced before): new, or cheaper than announced.
-- Returns them and the notice to keep (what is not listed cheap any more is forgotten).
function Loops.SnipeFresh(finds, notice)
	local fresh, keep = {}, {}
	for _, f in ipairs(finds) do
		local old = notice and notice[f.itemID]
		if not old or f.price < (old.price or 0) then
			fresh[#fresh + 1] = f
			keep[f.itemID] = { price = f.price }
		else
			keep[f.itemID] = old
		end
	end
	return fresh, keep
end

-- "3 snipes under your max"; nil without any.
function Loops.SnipeSummary(fresh)
	if #fresh == 0 then
		return nil
	end
	return ("%d %s under your max"):format(#fresh, #fresh == 1 and "snipe" or "snipes")
end

-- rows: ns.BuildRows rows. Returns the finds, best first: { recipeID, professionID, name, profit, loop,
-- outputItemID }. Rows of unlearned recipes only with includeUnlearned.
function Loops.Finds(rows, opts)
	opts = opts or {}
	local min = opts.min or 0
	local out = {}
	for _, r in ipairs(rows or {}) do
		if (r.status == "known" or opts.includeUnlearned) and r.vendorProfit and r.vendorProfit > min then
			out[#out + 1] = { recipeID = r.recipeID, professionID = opts.professionID, name = r.name,
				profit = r.vendorProfit, loop = r.vendorLoop and true or false, outputItemID = r.outputItemID,
				pct = r.costComplete and ns.Profit.Percent(r.vendorProfit, r.cost) or nil }
		end
	end
	return out
end

function Loops.Sort(finds)
	table.sort(finds, ns.Profit.ByPercent(true)) -- best return per gold first (#197)
	return finds
end

-- The finds worth a notice against `notice` ([recipeID] = { profit, loop } announced before), and the
-- notice to keep: every current find as it is now, nothing of what went away.
function Loops.Fresh(finds, notice)
	local fresh, keep = {}, {}
	for _, f in ipairs(finds) do
		local old = notice and notice[f.recipeID]
		if not old or (f.loop and not old.loop) or f.profit >= (old.profit or 0) * Loops.BETTER then
			fresh[#fresh + 1] = f
			keep[f.recipeID] = { profit = f.profit, loop = f.loop }
		else
			keep[f.recipeID] = old
		end
	end
	return fresh, keep
end

-- "2 vendor loops · 3 vendor profits": the counts of fresh finds (loops, then the rest); nil without any.
function Loops.Summary(fresh)
	local loops, profits = 0, 0
	for _, f in ipairs(fresh) do
		if f.loop then
			loops = loops + 1
		else
			profits = profits + 1
		end
	end
	local parts = {}
	if loops > 0 then
		parts[#parts + 1] = ("%d vendor %s"):format(loops, loops == 1 and "loop" or "loops")
	end
	if profits > 0 then
		parts[#parts + 1] = ("%d vendor %s"):format(profits, profits == 1 and "profit" or "profits")
	end
	if #parts == 0 then
		return nil
	end
	return table.concat(parts, " · ")
end

-- (ordered by profit %, rows without one last)
-- Every profession of this character: the finds, best first.
function Loops.Check()
	local all = {}
	local settings = Settings()
	for professionID in pairs(ns.charDB and ns.charDB.professions or {}) do
		local rows = ns.BuildRows(professionID, settings.includeUnlearned, "profit")
		for _, f in ipairs(Loops.Finds(rows, { includeUnlearned = settings.includeUnlearned, min = Loops.MinProfit(),
			professionID = professionID })) do
			all[#all + 1] = f
		end
	end
	return Loops.Sort(all)
end

-- Opens Make › Craft with the Vendor check chip on, on the profession of the find.
function Loops.Open(find)
	Settings().vendorCheck = true
	if find and find.professionID and ns.Main and ns.Main.UI then
		ns.Main.UI().profession = find.professionID
	end
	if ns.Main and ns.Main.Open then
		ns.Main.Open("craft")
	end
end

-- Checks the flips, puts them into the basket and refreshes the Auctionator list; returns the fresh ones
-- (new or clearly better, and not dismissed).
function Loops.RunFlips()
	if not (ns.db and Loops.FlipEnabled()) then
		return {}
	end
	local ok, finds = pcall(Loops.FlipCheck)
	if not ok then
		return {}
	end
	local shown = ns.Basket and ns.Basket.SetFlips(finds) or finds
	local fresh, keep = Loops.FlipFresh(shown, ns.db.flipNotice)
	ns.db.flipNotice = keep
	if ns.Basket then
		ns.Basket.RefreshFlipList()
	end
	return fresh
end

-- Checks the snipe list; returns the fresh finds (new or cheaper than announced).
function Loops.RunSnipes()
	if not (ns.db and Loops.SnipeEnabled()) then
		return {}
	end
	local ok, finds = pcall(Loops.SnipeCheck)
	if not ok then
		return {}
	end
	local fresh, keep = Loops.SnipeFresh(finds, ns.db.snipeNotice)
	ns.db.snipeNotice = keep
	return fresh
end

-- Runs the checks and shows one toast for what is fresh. Returns the fresh crafts, the fresh flips and the
-- fresh snipes.
function Loops.Run()
	if not ns.db then
		return {}, {}, {}
	end
	local fresh, flips, snipes = {}, Loops.RunFlips(), Loops.RunSnipes()
	if Loops.Enabled() then
		local ok, finds = pcall(Loops.Check)
		if ok then
			local keep
			fresh, keep = Loops.Fresh(finds, ns.db.loopNotice)
			ns.db.loopNotice = keep
		end
	end
	local parts = {}
	for _, t in ipairs({ Loops.Summary(fresh) or false, Loops.FlipSummary(flips) or false, Loops.SnipeSummary(snipes) or false }) do
		if t then
			parts[#parts + 1] = t
		end
	end
	local text = #parts > 0 and table.concat(parts, " · ") or nil
	if text and ns.LootToast and ns.LootToast.ShowCustom then
		local best, flip, snipe = fresh[1], flips[1], snipes[1]
		local other = flip or snipe -- the item shown when there is no craft
		local itemID = best and best.outputItemID or other and other.itemID
		local detail = best and best.name
		if not detail then
			local name = ns.Basket and ns.Basket.ItemName(other.itemID) or tostring(other.itemID)
			detail = (other.atLeast and "%s, %d or more" or "%s ×%d"):format(name, other.units)
		end
		ns.LootToast.ShowCustom({
			key = "loops", icon = itemID and C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID) or nil,
			itemID = not best and other.itemID or nil, text = text, detail = detail,
			copper = best and best.profit or flip and flip.profit or nil,
			sourceText = not best and (flip and "AH → vendor" or "Snipe list") or nil, duration = 10,
			onClick = function()
				if not best and not flip then
					-- Only snipes: the list is in the AH panel, next to the open auction house.
					if not (ns.AHPanel and ns.AHPanel.Show and ns.AHPanel.Show()) then
						ns.Print("Open the auction house: the snipe list is in CraftWise's panel next to it.")
					end
				elseif not best then
					-- Only flips (and maybe snipes): the list is in the basket.
					if ns.Main and ns.Main.Open then
						ns.Main.Open("basket")
					end
				elseif IsShiftKeyDown and IsShiftKeyDown() and ns.Basket then
					-- Shift-click puts the best find into the basket (one craft) and opens Make › Basket.
					ns.Basket.Add(best.recipeID, best.professionID, 1)
					if ns.Main and ns.Main.Open then
						ns.Main.Open("basket")
					end
				else
					Loops.Open(best)
				end
			end,
		})
	end
	return fresh, flips, snipes
end

local pending = false
local function Schedule()
	if pending or not (ns.db and (Loops.Enabled() or Loops.FlipEnabled() or Loops.SnipeEnabled())) then
		return
	end
	pending = true
	C_Timer.NewTimer(Loops.DEBOUNCE, ns.Timed("Loops.lua check", function()
		pending = false
		Loops.Run()
	end))
end
Loops.Schedule = Schedule

ns.Listen("PRICES_CHANGED", Schedule)
