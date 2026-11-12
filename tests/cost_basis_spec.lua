-- Issue #47: reagent cost basis per view (AH or paid cost) and craft-or-buy for intermediate reagents.
-- Recipes from the client's data: Light Leather Pants (9068) = 10 Light Leather, 1 Fine Thread,
-- 1 Cured Light Hide; Cured Light Hide (3816) = 1 Light Hide, 1 Salt.
local Make = dofile("tests/make_helpers.lua")
local LL, THREAD, CLH, HIDE, SALT, PANTS = 2318, 2321, 4231, 783, 4289, 7282

local function has(text, s) if not text:find(s, 1, true) then error("missing [" .. s .. "] in:\n" .. text, 2) end end
local function plain(s)
	return (s:gsub("|TInterface\\MoneyFrame\\UI%-(%a)%a*Icon:[^|]*|t", function(u) return u:lower() end):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- Pure maths: buy prices as given, recipes by output.
local function Prices(buy, recipes)
	return {
		buy = function(id) return buy[id] or nil end,
		sell = function() return nil end,
		recipesFor = function(id) return recipes[id] end,
	}
end
local CLH_RECIPE = { reagents = { { itemID = HIDE, quantity = 1 }, { itemID = SALT, quantity = 1 } }, output = { itemID = CLH, quantity = 1 } }
local PANTS_RECIPE = { reagents = { { itemID = LL, quantity = 10 }, { itemID = THREAD, quantity = 1 }, { itemID = CLH, quantity = 1 } },
	output = { itemID = PANTS, quantity = 1 } }
local BUY = {
	[CLH] = { copper = 200, source = "auction", label = "typical · Horde AH" },
	[HIDE] = { copper = 105, source = "auction", label = "typical · Horde AH" },
	[SALT] = { copper = 50, source = "vendor", label = "vendor" },
	[LL] = { copper = 30, source = "auction", label = "typical · Horde AH" },
	[THREAD] = { copper = 100, source = "vendor", label = "vendor" },
}

local function Line(result, itemID)
	for _, l in ipairs(result.reagents) do
		if l.itemID == itemID then return l end
	end
end

it("an intermediate a known recipe makes costs min(buy, craft): Cured Light Hide 1s55 crafted, not 2s00", function()
	local ns = LoadAddon()
	local r = ns.Profit.Evaluate(PANTS_RECIPE, Prices(BUY, { [CLH] = { CLH_RECIPE } }))
	local line = Line(r, CLH)
	eq(line.unit, 155); eq(line.total, 155); eq(line.source, "crafted"); eq(line.crafted, true)
	eq(line.craftUnit, 155); eq(line.buyUnit, 200); eq(line.buyLabel, "typical · Horde AH")
	eq(r.cost, 10 * 30 + 100 + 155)
	eq(Line(r, LL).crafted, nil) -- no known recipe makes it: plain buy price
	-- without the recipe it is bought at the AH
	r = ns.Profit.Evaluate(PANTS_RECIPE, Prices(BUY, {}))
	eq(Line(r, CLH).unit, 200); eq(Line(r, CLH).crafted, nil)
end)

it("buying wins when it is cheaper, and the line keeps both values", function()
	local ns = LoadAddon()
	local buy = setmetatable({ [CLH] = { copper = 140, source = "auction", label = "typical · Horde AH" } }, { __index = BUY })
	local line = Line(ns.Profit.Evaluate(PANTS_RECIPE, Prices(buy, { [CLH] = { CLH_RECIPE } })), CLH)
	eq(line.unit, 140); eq(line.crafted, false); eq(line.source, "auction"); eq(line.craftUnit, 155); eq(line.buyUnit, 140)
end)

it("crafting fills in when nothing sells it; a reagent without any price leaves the craft unpriced", function()
	local ns = LoadAddon()
	local buy = setmetatable({ [CLH] = false }, { __index = BUY })
	local line = Line(ns.Profit.Evaluate(PANTS_RECIPE, Prices(buy, { [CLH] = { CLH_RECIPE } })), CLH)
	eq(line.unit, 155); eq(line.buyUnit, nil)
	buy = setmetatable({ [CLH] = false, [SALT] = false }, { __index = BUY })
	local r = ns.Profit.Evaluate(PANTS_RECIPE, Prices(buy, { [CLH] = { CLH_RECIPE } }))
	eq(r.costComplete, false); eq(Line(r, CLH).unit, nil)
end)

it("output quantity divides the craft cost; the cheapest of several recipes wins", function()
	local ns = LoadAddon()
	local two = { reagents = { { itemID = HIDE, quantity = 2 }, { itemID = SALT, quantity = 1 } }, output = { itemID = CLH, quantity = 2 } }
	local u = ns.Profit.UnitCost(CLH, Prices(BUY, { [CLH] = { CLH_RECIPE, two } }))
	eq(u.copper, (2 * 105 + 50) / 2); eq(u.crafted, true)
end)

it("recursion has a depth limit and a cycle guard", function()
	local ns = LoadAddon()
	-- A <- B <- A: never loops, falls back to buying
	local A, B = 1, 2
	local recipes = {
		[A] = { { reagents = { { itemID = B, quantity = 1 } }, output = { itemID = A, quantity = 1 } } },
		[B] = { { reagents = { { itemID = A, quantity = 1 } }, output = { itemID = B, quantity = 1 } } },
	}
	local buy = { [A] = { copper = 100, source = "vendor" }, [B] = { copper = 80, source = "vendor" } }
	local u = ns.Profit.UnitCost(A, Prices(buy, recipes))
	eq(u.copper, 80); eq(u.crafted, true)
	-- a chain longer than MAX_DEPTH: the deepest level is bought
	local chain, cheap = {}, {}
	for i = 10, 20 do
		chain[i] = { { reagents = { { itemID = i + 1, quantity = 1 } }, output = { itemID = i, quantity = 1 } } }
		cheap[i] = { copper = 1000 - i, source = "vendor" }
	end
	u = ns.Profit.UnitCost(10, Prices(cheap, chain))
	eq(u.copper, 1000 - (10 + ns.Profit.MAX_DEPTH))
	-- the recipe being evaluated never prices its reagents by crafting its own output
	local loop = { reagents = { { itemID = B, quantity = 1 } }, output = { itemID = A, quantity = 1 } }
	local r = ns.Profit.Evaluate(loop, Prices(buy, recipes))
	eq(Line(r, B).unit, 80); eq(Line(r, B).crafted, false); eq(Line(r, B).craftUnit, 100) -- B from bought A, A not crafted
end)

-- In the addon: profession cache, Auctionator prices, vendor Salt and Thread from Data/Vendor.lua.
local function Leatherworking()
	local ns, stub = LoadAddon({ auctionator = true })
	stub.names.player = "Veli"
	ns.VendorPrices = { [SALT] = 50, [THREAD] = 100 }
	stub.items[LL] = { name = "Light Leather" }
	stub.items[THREAD] = { name = "Fine Thread" }
	stub.items[CLH] = { name = "Cured Light Hide" }
	stub.items[HIDE] = { name = "Light Hide" }
	stub.items[SALT] = { name = "Salt" }
	stub.items[PANTS] = { name = "Light Leather Pants", sellPrice = 300 }
	stub.ah[LL], stub.ah[CLH], stub.ah[HIDE], stub.ah[PANTS] = 30, 200, 105, 1000
	stub.profession = { id = 165, name = "Leatherworking", skill = 100, max = 150, recipes = {
		[9068] = { info = { name = "Light Leather Pants", learned = true }, schematic = stub.Schematic({ { LL, 10 }, { THREAD, 1 }, { CLH, 1 } }, PANTS) },
		[3816] = { info = { name = "Cured Light Hide", learned = true }, schematic = stub.Schematic({ { HIDE, 1 }, { SALT, 1 } }, CLH) },
	} }
	stub.Fire("TRADE_SKILL_SHOW")
	return ns, stub
end

local function Row(ns, view, recipeID)
	for _, r in ipairs(ns.BuildRows(165, false, view)) do
		if r.recipeID == recipeID then return r end
	end
end

local function TooltipOf(ns, stub, name)
	local lines = {}
	GameTooltip.AddLine = function(_, t) lines[#lines + 1] = t end
	GameTooltip.AddDoubleLine = function(_, l, r) lines[#lines + 1] = l .. " | " .. r end
	Make.Open(ns, "craft", 165) -- Make › Craft (#154)
	for _, f in ipairs(Make.Frames(ns, "craft")) do
		if f.elementData.row.name == name then
			f.scripts.OnEnter(f)
			return plain(table.concat(lines, "\n"))
		end
	end
	error("row not shown: " .. name)
end

it("profit rows use craft-or-buy with the character's known recipes; the tooltip says crafted and shows both", function()
	local ns, stub = Leatherworking()
	local row = Row(ns, "profit", 9068)
	local line = Line(row, CLH)
	eq(line.unit, 155); eq(line.source, "crafted"); eq(line.buyUnit, 200)
	eq(row.cost, 300 + 100 + 155)
	eq(ns.CostBasis("profit"), "ah")
	local t = TooltipOf(ns, stub, "Light Leather Pants")
	has(t, "Reagents | reagents: AH")
	has(t, "1 × Cured Light Hide | 1s 55c  crafted")
	has(t, "each: crafted 1s 55c · bought 2s Auctionator (house unknown)")
	has(t, "1 × Fine Thread | 1s  vendor")
	-- the CLH recipe's own row prices its reagents normally
	eq(Row(ns, "profit", 3816).cost, 155)
	-- an unlearned maker doesn't count (decision 1: this character's known recipes)
	stub.profession.recipes[3816].info.learned = false
	stub.Fire("TRADE_SKILL_LIST_UPDATE")
	ns.charDB.professions[165].recipes[3816].learned = false
	ns.Notify("RECIPES_CHANGED")
	eq(Line(Row(ns, "profit", 9068), CLH).unit, 200)
end)

it("paid cost basis per view: recorded paid cost is used, other reagents fall back to AH and say so", function()
	local ns, stub = Leatherworking()
	stub.counts[HIDE] = 10
	ns.Ledger.Record("vbuy", HIDE, 10, 900, "Tanner", 0) -- 90c each
	eq(ns.Ledger.PaidCost(HIDE).copper, 90)
	ns.db.settings.costBasis.profit = "paid"
	local row = Row(ns, "profit", 9068)
	-- Cured Light Hide has no paid cost: craft-or-buy, crafted from paid Light Hide + Salt at AH/vendor
	local clh = Line(row, CLH)
	eq(clh.unit, 140); eq(clh.crafted, true); eq(clh.paidFallback, true) -- Salt has no paid cost
	eq(Line(row, THREAD).paidFallback, true); eq(Line(row, THREAD).paidNote, "no paid cost")
	eq(Line(row, THREAD).unit, 100)
	assert(row.paidFallbacks >= 2, "row counts its fallbacks")
	local hide = Line(Row(ns, "profit", 3816), HIDE)
	eq(hide.source, "paid"); eq(hide.unit, 90); eq(hide.label, "paid cost, 10 held"); eq(hide.paidFallback, nil)
	-- other views keep their own basis
	eq(Line(Row(ns, "level", 9068), CLH).unit, 155)
	local t = TooltipOf(ns, stub, "Light Leather Pants")
	has(t, "Reagents | reagents: paid cost, else AH")
	has(t, "1 × Cured Light Hide | 1s 40c  crafted\n")
	has(t, "each: crafted 1s 40c · bought 2s Auctionator (house unknown) · some of its reagents have no paid cost (AH)")
	has(t, "1 × Fine Thread | 1s  vendor no paid cost")
end)

it("an intermediate with a paid cost uses it, even when crafting is cheaper (decision 1 on #47)", function()
	local ns, stub = Leatherworking()
	ns.db.settings.costBasis.profit = "paid"
	stub.counts[HIDE] = 10
	ns.Ledger.Record("vbuy", HIDE, 10, 900, "Tanner", 0)
	stub.counts[CLH] = 2
	ns.Ledger.Record("ahbuy", CLH, 2, 360, "PvP|H", 0) -- 1s80 each, crafting would be 1s40
	local clh = Line(Row(ns, "profit", 9068), CLH)
	eq(clh.unit, 180); eq(clh.source, "paid"); eq(clh.crafted, nil); eq(clh.craftUnit, nil); eq(clh.paidFallback, nil)
	local t = TooltipOf(ns, stub, "Light Leather Pants")
	has(t, "1 × Cured Light Hide | 1s 80c  paid cost, 2 held")
	assert(not t:find("each: crafted", 1, true), "no craft-or-buy line for a paid intermediate:\n" .. t)
	-- the AH basis still crafts it
	ns.db.settings.costBasis.profit = "ah"
	eq(Line(Row(ns, "profit", 9068), CLH).unit, 155)
end)

it("a partial paid cost (some held units predate the log) is the logged average, shown as N of M units", function()
	local ns, stub = Leatherworking()
	ns.db.settings.costBasis.profit = "paid"
	stub.counts[HIDE] = 2 -- held before the log
	ns.Ledger.Record("vbuy", HIDE, 10, 900, "Tanner", 2)
	stub.counts[HIDE] = 12
	stub.Fire("BAG_UPDATE_DELAYED")
	local paid = ns.Ledger.PaidCost(HIDE)
	eq(paid.partial, true); eq(paid.known, 10); eq(paid.units, 12); eq(paid.copper, 90)
	local hide = Line(Row(ns, "profit", 3816), HIDE)
	eq(hide.unit, 90); eq(hide.source, "paid"); eq(hide.paidPartial, true); eq(hide.paidFallback, nil)
	eq(hide.label, "paid cost, 10 of 12 units")
	eq(hide.paidNote, "average of the 10 units you bought; 2 held have no recorded price")
	local t = TooltipOf(ns, stub, "Cured Light Hide")
	has(t, "1 × Light Hide | 90c  paid cost, 10 of 12 units")
	has(t, "average of the 10 units you bought; 2 held have no recorded price")
end)

it("Settings switch the basis per view and the Make page footer shows it", function()
	local ns, stub = Leatherworking()
	local M = ns.Main -- Settings › Prices (#157)
	M.Open("settings")
	M.Settings.SelectGroup("prices")
	local paid = M.Settings.RowOf("prices", "cost_level").holder.control.buttons[2]
	paid.scripts.OnClick(paid)
	eq(ns.db.settings.costBasis.level, "paid")
	eq(ns.CostBasis("level"), "paid"); eq(ns.CostBasis("profit"), "ah"); eq(ns.CostBasis("bags"), "ah")
	Make.Open(ns, "level", 165)
	local foot = ns.Main.Frame().foot
	has(plain(foot.right.text), "reagents: paid cost, else AH")
	Make.Open(ns, "craft", 165)
	has(plain(foot.left.text), "reagents: AH")
end)
