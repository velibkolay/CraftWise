-- Hero card models (#152, spec in epic #150): the single answer at the top of the Make and Sell
-- pages. Pure functions over rows the existing models already built; no frames, no client calls.
-- The maths stays where it is (Profit.Evaluate, Leveling, Bags, Auctions, Holdings): this file only
-- picks the row, names the figures and says why when there is no answer.
--
-- Every function returns a table, or nil plus a reason (a short sentence the page can show as the
-- matching empty state). A missing value is nil, never 0 and never a guess. Copper everywhere.
local _, ns = ...

local Hero = {}
ns.HeroCards = Hero

local function ByName(a, b)
	local na, nb = (a.name or ""):lower(), (b.name or ""):lower()
	if na ~= nb then
		return na < nb
	end
	return (a.recipeID or 0) < (b.recipeID or 0)
end

-- Skill-up chance for the card: p (nil without a chance or when 0), kind, estimate (the formula, "~").
local function ChanceOf(row, opts)
	if not (ns.Leveling and row.recipeID) then
		return nil
	end
	local skill = opts.skill
	if skill == nil and opts.professionID and ns.ProfessionSkill then
		skill = ns.ProfessionSkill(opts.professionID)
	end
	local p, info = ns.Leveling.Chance(row.recipeID, row.difficulty, skill, opts.pools or ns.Leveling.CachedPools())
	if not p or p <= 0 then
		return nil, info and info.kind
	end
	return p, info.kind, info.kind == "formula"
end

----------------------------------------------------------------------------------------------------
-- Make > Craft: best craft
----------------------------------------------------------------------------------------------------

-- rows: ns.BuildRows(professionID, includeUnlearned, "profit") rows, filtered or not.
-- opts: professionID or skill (for the chance), counter (fn(itemID) -> held; default
--       Holdings.Counter()), pools (Leveling.CachedPools()).
-- Best profit among known recipes with a profit (priced output and reagents, verified AH cut).
-- Returns {
--   recipeID, name, icon, outputItemID, outputQuantity,
--   color          skill-up colour word ("orange" | "yellow" | "green" | "grey") or nil,
--   profit, cost, sale     copper; the rail runs cost (grey) then profit (white) along sale,
--   sellSource, sellLabel, thin, oldestAge   how the sale price was found,
--   chance (0..1, nil when none), chanceKind, chanceEstimate (true = formula, show "~"),
--   short          { { itemID, quantity (per craft), have, missing } } reagents the holdings lack
--                  for one craft, in reagent order; empty when nothing is short,
--   candidates     how many known, priced recipes were compared,
-- } or nil, reason.
function Hero.BestCraft(rows, opts)
	opts = opts or {}
	if not rows or #rows == 0 then
		return nil, "no recipes yet"
	end
	local known, best, priced = 0, nil, 0
	for _, r in ipairs(rows) do
		if r.status == "known" then
			known = known + 1
			if r.profit ~= nil then
				priced = priced + 1
				if not best or r.profit > best.profit or (r.profit == best.profit and ByName(r, best)) then
					best = r
				end
			end
		end
	end
	if known == 0 then
		return nil, "no known recipe"
	elseif not best then
		return nil, "no known recipe has a price yet"
	end

	local counter = opts.counter or (ns.Holdings and ns.Holdings.Counter())
	local short = {}
	for _, line in ipairs(best.reagents or {}) do
		local have = counter and counter(line.itemID) or 0
		if have < line.quantity then
			short[#short + 1] = { itemID = line.itemID, quantity = line.quantity, have = have, missing = line.quantity - have }
		end
	end
	local chance, kind, estimate = ChanceOf(best, opts)
	return {
		recipeID = best.recipeID, name = best.name, icon = best.icon,
		outputItemID = best.outputItemID, outputQuantity = best.outputQuantity,
		color = best.skillColor,
		profit = best.profit, cost = best.cost, sale = best.sellsFor,
		sellSource = best.sellSource, sellLabel = best.sellLabel, thin = best.thin, oldestAge = best.oldestAge,
		chance = chance, chanceKind = kind, chanceEstimate = estimate or false,
		short = short, candidates = priced,
	}
end

----------------------------------------------------------------------------------------------------
-- Make > Level up: best skill-up
----------------------------------------------------------------------------------------------------

-- rows: ns.LevelingRows(professionID) (grey recipes are already left out).
-- The Level up list's default order: per skill-up ascending (recipes that earn are negative, so they
-- come first, then the cheapest), rows without a per skill-up figure last. The hero is the first row
-- that has the figure. Returns {
--   recipeID, name, icon, color, chance (0..1), chanceKind, chanceEstimate (true = formula, "~"),
--   perPoint (copper per skill-up, negative = earns), craftsPerPoint, earns (bool),
--   cost, sale, saleSource, net (cost - sale per craft),
-- } or nil, reason.
function Hero.BestSkillUp(rows)
	if not rows or #rows == 0 then
		return nil, "no recipe at your skill gives skill-ups"
	end
	local sorted = {}
	for _, r in ipairs(rows) do
		sorted[#sorted + 1] = r
	end
	table.sort(sorted, ns.Profit.Comparator("perPoint", false))
	local best = sorted[1]
	if best.perPoint == nil then
		return nil, "no recipe has a price and a chance yet"
	end
	local info = best.chanceInfo or {}
	return {
		recipeID = best.recipeID, name = best.name, icon = best.icon, color = best.skillColor,
		chance = best.chance, chanceKind = info.kind, chanceEstimate = info.kind == "formula",
		perPoint = best.perPoint, craftsPerPoint = best.craftsPerPoint, earns = best.perPoint < 0,
		cost = best.cost, sale = best.saleValue, saleSource = best.saleSource, net = best.net,
	}
end

----------------------------------------------------------------------------------------------------
-- Make > Learn: best recipe to learn
----------------------------------------------------------------------------------------------------

-- rows: ns.BuildRows(professionID, true, "learn") rows (unfiltered; the page's chips don't change the
-- hero). Learnable now = not known, requirement known and met (the "Fits my skill" rule). Among
-- those with a known learn cost and a profit (Profit.Evaluate's breakEven): fewest crafts to pay
-- off, ties to the higher profit, then name. Returns {
--   recipeID, name, icon, status, required, learnCost, learnSource, learnLabel,
--   profit, breakEven (crafts), whereText (first line of ns.RecipeWhere or nil),
--   candidates     learnable-now recipes, unknownCost  of those without a learn cost,
-- } or nil, reason.
function Hero.BestToLearn(rows)
	if not rows or #rows == 0 then
		return nil, "no recipes yet"
	end
	local learnable, unknownCost, best = 0, 0, nil
	for _, r in ipairs(rows) do
		if r.status ~= "known" and r.required ~= nil and not r.tooLow then
			learnable = learnable + 1
			if r.learnCost == nil then
				unknownCost = unknownCost + 1
			elseif r.breakEven then
				if not best or r.breakEven < best.breakEven
					or (r.breakEven == best.breakEven and (r.profit > best.profit
						or (r.profit == best.profit and ByName(r, best)))) then
					best = r
				end
			end
		end
	end
	if learnable == 0 then
		return nil, "no recipe to learn at your skill"
	elseif not best then
		return nil, unknownCost == learnable and "no learn cost known yet"
			or "no learnable recipe makes a profit"
	end
	local where = best.whereText
	if not where and ns.RecipeWhere then
		local lines = ns.RecipeWhere(best.recipeID)
		where = lines and lines[1] and lines[1].text or nil
	end
	return {
		recipeID = best.recipeID, name = best.name, icon = best.icon, status = best.status,
		required = best.required, learnCost = best.learnCost, learnSource = best.learnSource, learnLabel = best.learnLabel,
		profit = best.profit, breakEven = best.breakEven, whereText = where,
		candidates = learnable, unknownCost = unknownCost,
	}
end

----------------------------------------------------------------------------------------------------
-- Sell > Bags: bag value
----------------------------------------------------------------------------------------------------

-- rows: ns.BagRows(), all of them (the page's search and tool filters don't change the hero).
-- Sums each item's best value (row.bestValue, set by ns.BagRows). Kept items are not for sale and
-- are left out; items with no value at all are counted in `uncounted`. Returns {
--   total,                      copper
--   parts = { auction, vendor, junk, disenchant },  copper each (auction is after the cut)
--   shares = { auction, vendor, junk, disenchant }, fractions of total for the three-part bar
--   items = { auction, vendor, junk, disenchant },  rows counted in each
--   uncounted      rows that are for sale but have no value (no price, unverified cut)
--   kept           rows left out because they are kept
-- } or nil, reason. Disenchant is 0 until the verified disenchant table exists (#11).
function Hero.BagValue(rows)
	if not rows or #rows == 0 then
		return nil, "nothing in your bags"
	end
	local parts = { auction = 0, vendor = 0, junk = 0, disenchant = 0 }
	local items = { auction = 0, vendor = 0, junk = 0, disenchant = 0 }
	local uncounted, kept, total = 0, 0, 0
	for _, r in ipairs(rows) do
		if r.kept then
			kept = kept + 1
		elseif r.best and parts[r.best] and r.bestValue then
			parts[r.best] = parts[r.best] + r.bestValue
			items[r.best] = items[r.best] + 1
			total = total + r.bestValue
		else
			uncounted = uncounted + 1
		end
	end
	if total == 0 then
		return nil, kept == #rows and "everything in your bags is kept" or "no item in your bags has a known value"
	end
	local shares = {}
	for key, copper in pairs(parts) do
		shares[key] = copper / total
	end
	return { total = total, parts = parts, shares = shares, items = items, uncounted = uncounted, kept = kept }
end

----------------------------------------------------------------------------------------------------
-- Sell > Auctions: totals
----------------------------------------------------------------------------------------------------

-- summary: ns.Auctions.Summary() (default) for this character. Returns {
--   onItsWay   = { copper, count, notCounted },   sold, money still in the mail; copper nil when no
--                                                  sale has a known payout
--   ifAllSell  = { copper, count, notCounted, note, noBuyout, notRecorded, unknownCut },
--                                                  every listing sold at its buyout after the cut;
--                                                  notCounted = noBuyout + notRecorded + unknownCut
--   returning  = { count, units },                 expired or cancelled, items on their way back
--   ownedListAt    when the client's owned list was last read (nil = never)
-- } or nil, reason.
function Hero.AuctionTotals(summary)
	if summary == nil and ns.Auctions then
		local reason
		summary, reason = ns.Auctions.Summary()
		if not summary then
			return nil, reason or "character not known yet"
		end
	end
	if not summary then
		return nil, "character not known yet"
	end
	local sold, active, returning = #summary.sold, #summary.active, #summary.returning
	if sold + active + returning == 0 then
		return nil, "no auction listed, sold or returning"
	end
	local soldCounted = sold - (summary.expectedMissing or 0)
	local units = 0
	for _, row in ipairs(summary.returning) do
		units = units + (row.q or 0)
	end
	local notCounted = (summary.listedNoBuyout or 0) + (summary.listedUnpriced or 0) + (summary.listedUnknownCut or 0)
	return {
		onItsWay = { copper = soldCounted > 0 and summary.expectedTotal or nil, count = sold,
			notCounted = summary.expectedMissing or 0 },
		ifAllSell = { copper = (summary.listedCounted or 0) > 0 and summary.listedTotal or nil, count = active,
			notCounted = notCounted, note = summary.listedNote, noBuyout = summary.listedNoBuyout or 0,
			notRecorded = summary.listedUnpriced or 0, unknownCut = summary.listedUnknownCut or 0 },
		returning = { count = returning, units = units },
		ownedListAt = summary.ownedListAt,
	}
end
