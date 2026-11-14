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

-- rows: ns.BuildRows rows. Returns the finds, best first: { recipeID, professionID, name, profit, loop,
-- outputItemID }. Rows of unlearned recipes only with includeUnlearned.
function Loops.Finds(rows, opts)
	opts = opts or {}
	local min = opts.min or 0
	local out = {}
	for _, r in ipairs(rows or {}) do
		if (r.status == "known" or opts.includeUnlearned) and r.vendorProfit and r.vendorProfit > min then
			out[#out + 1] = { recipeID = r.recipeID, professionID = opts.professionID, name = r.name,
				profit = r.vendorProfit, loop = r.vendorLoop and true or false, outputItemID = r.outputItemID }
		end
	end
	return out
end

function Loops.Sort(finds)
	table.sort(finds, function(a, b)
		if a.profit ~= b.profit then
			return a.profit > b.profit
		end
		return (a.name or "") < (b.name or "")
	end)
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

-- Runs a check and shows the toast for what is fresh. Returns the fresh finds.
function Loops.Run()
	if not (ns.db and Loops.Enabled()) then
		return {}
	end
	local ok, finds = pcall(Loops.Check)
	if not ok then
		return {}
	end
	local fresh, keep = Loops.Fresh(finds, ns.db.loopNotice)
	ns.db.loopNotice = keep
	local text = Loops.Summary(fresh)
	if text and ns.LootToast and ns.LootToast.ShowCustom then
		local best = fresh[1]
		ns.LootToast.ShowCustom({
			key = "loops", icon = best.outputItemID and C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(best.outputItemID) or nil,
			text = text, detail = best.name, copper = best.profit, duration = 10,
			onClick = function()
				-- Shift-click puts the best find into the basket (one craft) and opens Make › Basket.
				if IsShiftKeyDown and IsShiftKeyDown() and ns.Basket then
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
	return fresh
end

local pending = false
local function Schedule()
	if pending or not (ns.db and Loops.Enabled()) then
		return
	end
	pending = true
	C_Timer.NewTimer(Loops.DEBOUNCE, function()
		pending = false
		Loops.Run()
	end)
end
Loops.Schedule = Schedule

ns.Listen("PRICES_CHANGED", Schedule)
