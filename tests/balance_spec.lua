-- Issue #49: reagent imbalance warning with a buy list. Example from Veli's run: 60 Cured Light
-- Hide, but Light Leather for only 8 Light Leather Pants.
local Make = dofile("tests/make_helpers.lua")
local NOW = 1794000000
local DAY = 86400
local HORDE = "PvP|H"
local LEATHER, SCRAPS, THREAD, CURED, HIDE, SALT, PANTS = 2318, 2934, 2321, 4231, 783, 4289, 7282
-- Light Leather Pants (9068): 10 Light Leather, 1 Fine Thread, 1 Cured Light Hide (bundled DB2 data).
local PANTS_REAGENTS = { { itemID = LEATHER, quantity = 10 }, { itemID = THREAD, quantity = 1 }, { itemID = CURED, quantity = 1 } }
local SCRAPS_TO_LEATHER = { reagents = { { itemID = SCRAPS, quantity = 3 } }, output = { itemID = LEATHER, quantity = 1 } } -- 2881
local CURE_HIDE = { reagents = { { itemID = HIDE, quantity = 1 }, { itemID = SALT, quantity = 1 } }, output = { itemID = CURED, quantity = 1 } } -- 3816

local function Load(opts)
	local ns, stub = LoadAddon(opts)
	stub.clock = NOW
	time = function() return stub.clock end
	return ns, stub
end

local function Held(t) return function(id) return t[id] or 0 end end
local function Makers(t) return function(id) return t[id] end end

local function Plain(text)
	text = text:gsub("|T[^|]*UI%-GoldIcon[^|]*|t", "g"):gsub("|T[^|]*UI%-SilverIcon[^|]*|t", "s"):gsub("|T[^|]*UI%-CopperIcon[^|]*|t", "c")
	return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

local function has(text, s) assert(text:find(s, 1, true), ("missing %q in:\n%s"):format(s, text)) end

local function LinesText(lines)
	local out = {}
	for i, l in ipairs(lines) do out[i] = Plain(l[1]) .. " | " .. Plain(l[2]) end
	return table.concat(out, "\n")
end

------------------------------------------------------------------------------------- pure maths

it("example: 60 Cured Light Hide, Light Leather (50 + 90 scraps) for 8 pants: 8 possible, leather limits, warn", function()
	local ns = Load()
	local b = ns.Balance.Analyze(PANTS_REAGENTS, Held({ [CURED] = 60, [LEATHER] = 50, [SCRAPS] = 90, [THREAD] = 40 }),
		Makers({ [LEATHER] = { SCRAPS_TO_LEATHER } }))
	eq(b.possible, 8)
	eq(b.limiting.itemID, LEATHER); eq(b.limiting.covers, 8)
	eq(b.lines[1].units, 80); eq(b.lines[1].made, 30); eq(b.lines[1].held, 50)
	eq(b.largest.itemID, CURED); eq(b.largest.covers, 60)
	eq(b.warn, true)
	-- Buy list for the default target, what the largest reagent covers: 60 crafts.
	eq(b.target, 60)
	eq(#b.buy, 2)
	eq(b.buy[1].itemID, LEATHER); eq(b.buy[1].quantity, 520)
	eq(b.buy[2].itemID, THREAD); eq(b.buy[2].quantity, 20)
end)

it("intermediates: Light Hide + Salt count as Cured Light Hide; scarce salt limits them", function()
	local ns = Load()
	local makers = Makers({ [CURED] = { CURE_HIDE }, [LEATHER] = { SCRAPS_TO_LEATHER } })
	local b = ns.Balance.Analyze(PANTS_REAGENTS, Held({ [CURED] = 40, [HIDE] = 20, [SALT] = 30, [LEATHER] = 600, [THREAD] = 60 }), makers)
	eq(b.lines[3].units, 60); eq(b.lines[3].made, 20)
	eq(b.possible, 60); eq(b.warn, false); eq(#b.buy, 0)
	b = ns.Balance.Analyze(PANTS_REAGENTS, Held({ [CURED] = 40, [HIDE] = 20, [SALT] = 5, [LEATHER] = 600, [THREAD] = 60 }), makers)
	eq(b.lines[3].units, 45)
	eq(b.possible, 45)
	eq(b.target, 60); eq(b.buy[1].itemID, CURED); eq(b.buy[1].quantity, 15)
end)

it("shared inputs are not counted twice", function()
	local ns = Load()
	local X = 900
	local reagents = { { itemID = 901, quantity = 1 }, { itemID = 902, quantity = 1 } }
	local makers = Makers({
		[901] = { { reagents = { { itemID = X, quantity = 1 } }, output = { itemID = 901, quantity = 1 } } },
		[902] = { { reagents = { { itemID = X, quantity = 1 } }, output = { itemID = 902, quantity = 1 } } },
	})
	local b = ns.Balance.Analyze(reagents, Held({ [X] = 10 }), makers)
	eq(b.lines[1].covers, 10); eq(b.lines[2].covers, 10)
	eq(b.possible, 5, "10 X make 5 of each, not 10 crafts")
end)

it("warning threshold: at least 2x and at least 5 more crafts (decision 1 on #49)", function()
	local ns = Load()
	local r = { { itemID = 1, quantity = 1 }, { itemID = 2, quantity = 1 } }
	local function warn(a, b) return ns.Balance.Analyze(r, Held({ [1] = a, [2] = b })).warn end
	eq(warn(8, 60), true)
	eq(warn(5, 10), true)
	eq(warn(6, 11), false, "under 2x")
	eq(warn(2, 6), false, "only 4 more")
	eq(warn(0, 5), true)
	eq(warn(0, 4), false)
	eq(ns.Balance.Analyze({ { itemID = 1, quantity = 2 } }, Held({ [1] = 50 })).warn, false, "one reagent can't be imbalanced")
end)

it("balanced holdings: nothing to buy; explicit target buys for that many", function()
	local ns = Load()
	local b = ns.Balance.Analyze(PANTS_REAGENTS, Held({ [LEATHER] = 100, [THREAD] = 10, [CURED] = 10 }))
	eq(b.possible, 10); eq(b.warn, false); eq(#b.buy, 0)
	b = ns.Balance.Analyze(PANTS_REAGENTS, Held({ [LEATHER] = 100, [THREAD] = 10, [CURED] = 10 }), nil, 12)
	eq(b.buy[1].quantity, 20); eq(b.buy[2].quantity, 2); eq(b.buy[3].quantity, 2)
end)

-------------------------------------------------------------------------------- places and prices

local function SetupPants(ns, stub)
	stub.profession = { id = 165, name = "Leatherworking", skill = 100, max = 150, recipes = {
		[9068] = { info = { name = "Light Leather Pants", learned = true }, schematic = stub.Schematic({ { LEATHER, 10 }, { THREAD, 1 }, { CURED, 1 } }, PANTS) },
		[2881] = { info = { name = "Light Leather", learned = true }, schematic = stub.Schematic({ { SCRAPS, 3 } }, LEATHER) },
	} }
	stub.Fire("TRADE_SKILL_SHOW")
	stub.items[LEATHER] = { name = "Light Leather" }
	stub.items[THREAD] = { name = "Fine Thread" }
	stub.items[CURED] = { name = "Cured Light Hide" }
	stub.items[SCRAPS] = { name = "Ruined Leather Scraps" }
	-- Bags: 50 leather, 40 thread. Bank tab: 90 scraps. Mail: 60 Cured Light Hide.
	stub.bags[0] = { { itemID = LEATHER, stackCount = 20 }, { itemID = LEATHER, stackCount = 20 }, false, { itemID = THREAD, stackCount = 40 } }
	stub.bags[5] = { { itemID = LEATHER, stackCount = 10 } } -- reagent bag
	Enum.BagIndex.CharacterBankTab_1 = 6
	stub.bags[6] = { { itemID = SCRAPS, stackCount = 90 } }
	local mail = { { { CURED, 20 }, { CURED, 20 } }, { { CURED, 20 } } }
	GetInboxNumItems = function() return #mail, #mail end
	GetInboxItem = function(i, j)
		local a = mail[i] and mail[i][j]
		if a then return "item", a[1], 0, a[2] end
	end
	-- Prices: Light Leather from the Horde AH's cheapest tiers, Fine Thread from a vendor.
	local db = CraftWiseMarketDB
	db.items[LEATHER] = { [HORDE] = { raw = { { t = NOW, total = 700, tiers = { 50, 300, 60, 400 } } }, days = {},
		last = { t = NOW, min = 50, qty = 700 } } }
	db.houses[HORDE] = { realm = "PvP", kind = "faction", faction = "Horde", label = "Horde AH", cut = { samples = 0 } }
	db.scans[HORDE] = { { t = NOW, kind = "search", items = 1, source = "ui" } }
	ns.db.vendor[THREAD] = 100
end

it("holdings: bags and reagent bag live, bank and mail from what CraftWise saw, places listed", function()
	local ns, stub = Load()
	SetupPants(ns, stub)
	local count = ns.Holdings.Counter()
	eq(count(LEATHER), 50); eq(count(SCRAPS), 0, "bank not seen yet"); eq(count(CURED), 0, "mail not seen yet")
	local counted, missing = ns.Holdings.PlacesText()
	eq(counted, "bags and reagent bag"); eq(missing, "bank (open it once), mail (open your mailbox once)")
	stub.Fire("BANKFRAME_OPENED")
	stub.Fire("MAIL_SHOW")
	stub.Fire("BANKFRAME_CLOSED")
	stub.clock = NOW + 2 * 3600
	stub.bags[6] = {} -- bank changes while closed are not seen: the snapshot stays
	count = ns.Holdings.Counter()
	local total, parts = count(SCRAPS)
	eq(total, 90); eq(parts.bank, 90); eq(parts.bags, 0)
	eq(count(CURED), 60)
	counted, missing = ns.Holdings.PlacesText()
	eq(counted, "bags and reagent bag, bank (2h ago), mail (2h ago)"); eq(missing, nil)
end)

it("buy quotes: AH from the profit house's depth, vendor when cheaper, short when the tiers run out", function()
	local ns, stub = Load()
	SetupPants(ns, stub)
	local q = ns.BuyQuote(LEATHER, 520)
	eq(q.source, "auction"); eq(q.cost, 300 * 50 + 220 * 60); eq(q.label, "Horde AH")
	q = ns.BuyQuote(THREAD, 20)
	eq(q.source, "vendor"); eq(q.cost, 2000)
	local none, short = ns.BuyQuote(LEATHER, 800)
	eq(none, nil); eq(short.listed, 700); eq(short.house, "Horde AH")
	eq((ns.BuyQuote(SCRAPS, 3)), nil)
end)

it("tooltip lines: the example with counted places, warning and buy list for 60", function()
	local ns, stub = Load()
	SetupPants(ns, stub)
	stub.Fire("BANKFRAME_OPENED"); stub.Fire("BANKFRAME_CLOSED"); stub.Fire("MAIL_SHOW")
	local lines, b = ns.BalanceLines(PANTS_REAGENTS)
	eq(b.possible, 8); eq(b.total, 300 * 50 + 220 * 60 + 2000); eq(b.complete, true)
	local text = LinesText(lines)
	has(text, "10 × Light Leather | hold 80 (30 made from what you hold)  8 crafts")
	has(text, "1 × Cured Light Hide | hold 60  60 crafts")
	has(text, "Crafts possible | 8")
	has(text, "Light Leather limits you to 8 crafts; you hold Cured Light Hide for 60.")
	has(text, "To buy for 60 crafts")
	has(text, "520 × Light Leather | 2g 82s  AH · Horde AH")
	has(text, "20 × Fine Thread | 20s  vendor")
	has(text, "Total | 3g 2s")
	has(text, "Counted: bags and reagent bag, bank (0m ago), mail (0m ago)")
	assert(not text:find("Not counted", 1, true), text)
end)

it("nothing held: no balance lines; missing prices make the total incomplete", function()
	local ns, stub = Load()
	SetupPants(ns, stub)
	stub.bags[0], stub.bags[5] = {}, {}
	eq(#ns.BalanceLines(PANTS_REAGENTS), 0)
	stub.bags[0] = { { itemID = CURED, stackCount = 30 } }
	stub.Fire("BAG_UPDATE_DELAYED")
	ns.db.vendor[THREAD] = nil
	local lines, b = ns.BalanceLines(PANTS_REAGENTS)
	eq(b.complete, false)
	local text = LinesText(lines)
	has(text, "30 × Fine Thread | no price data")
	has(text, "Total | 1g 50s + ?")
	has(text, "Not counted: bank (open it once), mail (open your mailbox once)")
end)

it("profit and level tooltips and the tracked recipe's item tooltip show the balance", function()
	local ns, stub = Load()
	SetupPants(ns, stub)
	stub.Fire("BANKFRAME_OPENED"); stub.Fire("BANKFRAME_CLOSED"); stub.Fire("MAIL_SHOW")
	local seen = {}
	local add, add2 = GameTooltip.AddLine, GameTooltip.AddDoubleLine
	GameTooltip.AddLine = function(self, l, ...) seen[#seen + 1] = Plain(tostring(l)); return add(self, l, ...) end
	GameTooltip.AddDoubleLine = function(self, l, r, ...) seen[#seen + 1] = Plain(l) .. " | " .. Plain(r); return add2(self, l, r, ...) end
	for _, page in ipairs({ "craft", "level" }) do
		seen = {}
		Make.Open(ns, page, 165)
		local hovered = Make.Hover(ns, page, 9068)
		assert(hovered, "no pants row on the " .. page .. " page")
		has(table.concat(seen, "\n"), "Light Leather limits you to 8 crafts; you hold Cured Light Hide for 60.")
	end
	GameTooltip.AddLine, GameTooltip.AddDoubleLine = add, add2
	-- Tracked recipe: hovering Cured Light Hide anywhere.
	C_TradeSkillUI.GetRecipesTracked = function() return { 9068 } end
	local tip = { lines = {} }
	function tip:AddLine(t) table.insert(self.lines, Plain(t)) end
	function tip:AddDoubleLine(l, r) table.insert(self.lines, Plain(l) .. " | " .. Plain(r)) end
	function tip:Show() end
	ns.AddTooltipLines(tip, CURED)
	local text = table.concat(tip.lines, "\n")
	has(text, "Tracked | Light Leather Pants")
	has(text, "Crafts possible | 8")
	-- Untracked items get nothing extra.
	tip.lines = {}
	ns.AddTooltipLines(tip, 12345)
	assert(not table.concat(tip.lines, "\n"):find("Tracked", 1, true))
	ns.db.tooltip.lines.tracked = false
	tip.lines = {}
	ns.AddTooltipLines(tip, CURED)
	assert(not table.concat(tip.lines, "\n"):find("Tracked", 1, true), "the line can be turned off")
end)

it("cache: hovering again doesn't recompute; bags, bank, mail and recipe changes do", function()
	local ns, stub = Load()
	SetupPants(ns, stub)
	local calls = 0
	local analyze = ns.Balance.Analyze
	ns.Balance.Analyze = function(...) calls = calls + 1; return analyze(...) end
	C_TradeSkillUI.GetRecipesTracked = function() return { 9068 } end
	local function hover(itemID)
		local tip = { lines = {} }
		function tip:AddLine(t) table.insert(self.lines, Plain(t)) end
		function tip:AddDoubleLine(l, r) table.insert(self.lines, Plain(l) .. " | " .. Plain(r)) end
		function tip:Show() end
		ns.AddTooltipLines(tip, itemID)
		return table.concat(tip.lines, "\n")
	end
	has(hover(CURED), "Crafts possible | 0")
	hover(CURED); hover(LEATHER); ns.BalanceLines(PANTS_REAGENTS)
	eq(calls, 1, "same recipe, nothing changed: one analysis")
	ns.BalanceLines(PANTS_REAGENTS, 12)
	eq(calls, 2, "another target is another entry")
	stub.bags[0][3] = { itemID = CURED, stackCount = 5 }
	hover(CURED)
	eq(calls, 2, "no bag event yet: still cached")
	stub.Fire("BAG_UPDATE_DELAYED")
	has(hover(CURED), "Crafts possible | 5")
	eq(calls, 3)
	stub.Fire("MAIL_SHOW")
	has(hover(CURED), "Crafts possible | 5")
	eq(calls, 4, "mail scan invalidates")
	stub.Fire("BANKFRAME_OPENED"); stub.Fire("BANKFRAME_CLOSED")
	has(hover(CURED), "Crafts possible | 8")
	eq(calls, 5, "bank scan invalidates")
	ns.Notify("RECIPES_CHANGED")
	hover(CURED)
	eq(calls, 6, "recipe changes invalidate")
	-- Prices are read fresh even from a cached analysis.
	ns.db.vendor[THREAD] = 200
	has(hover(CURED), "25 × Fine Thread | 50s  vendor")
	eq(calls, 6)
	ns.Balance.Analyze = analyze
end)

it("account bank tabs are listed as not counted", function()
	local ns, stub = Load()
	SetupPants(ns, stub)
	stub.Fire("BANKFRAME_OPENED"); stub.Fire("BANKFRAME_CLOSED"); stub.Fire("MAIL_SHOW")
	eq(select(2, ns.Holdings.PlacesText()), nil)
	Enum.BagIndex.AccountBankTab_1 = 15
	stub.bags[15] = { { itemID = CURED, stackCount = 99 } }
	local counted, missing = ns.Holdings.PlacesText()
	eq(missing, "account bank (not read)")
	eq(ns.Holdings.Counter()(CURED), 60, "account bank items are not counted")
	has(LinesText(ns.BalanceLines(PANTS_REAGENTS)), "Not counted: account bank (not read)")
end)

------------------------------------------------------------------- craft or buy in the buy list (#60)

local CURE_HIDE_ID = 3816

it("expand (pure): a missing intermediate the chooser crafts is replaced by its inputs, held inputs first", function()
	local ns = Load()
	local craft = function(id) if id == CURED then return CURE_HIDE, { craftUnit = 150 } end end
	local e = ns.Balance.Expand({ { itemID = THREAD, quantity = 1 }, { itemID = CURED, quantity = 2 } }, {}, Held({ [HIDE] = 1 }), nil, craft)
	eq(#e.crafts, 1); eq(e.crafts[1].itemID, CURED); eq(e.crafts[1].quantity, 2); eq(e.crafts[1].crafts, 2); eq(e.crafts[1].depth, 0)
	eq(#e.buy, 3)
	eq(e.buy[1].itemID, THREAD); eq(e.buy[1].quantity, 1)
	eq(e.buy[2].itemID, HIDE); eq(e.buy[2].quantity, 1, "one Light Hide held")
	eq(e.buy[3].itemID, SALT); eq(e.buy[3].quantity, 2)
	-- the leftover pool counts, not the raw holdings: hides used up by the analysis are gone
	e = ns.Balance.Expand({ { itemID = CURED, quantity = 2 } }, { [HIDE] = 0 }, Held({ [HIDE] = 5 }), nil, craft)
	eq(e.buy[1].itemID, HIDE); eq(e.buy[1].quantity, 2)
	-- no chooser decision: the list is unchanged
	e = ns.Balance.Expand({ { itemID = CURED, quantity = 2 } }, {}, Held({}), nil, function() end)
	eq(#e.crafts, 0); eq(e.buy[1].itemID, CURED); eq(e.buy[1].quantity, 2)
end)

it("expand (pure): nested intermediates, multi-unit yields, merged inputs and the cycle guard", function()
	local ns = Load()
	local A, B, X = 801, 802, 803
	local recipes = {
		[A] = { reagents = { { itemID = B, quantity = 3 }, { itemID = X, quantity = 1 } }, output = { itemID = A, quantity = 1 } },
		[B] = { reagents = { { itemID = X, quantity = 1 } }, output = { itemID = B, quantity = 2 } },
	}
	local e = ns.Balance.Expand({ { itemID = A, quantity = 1 } }, {}, Held({}), nil, function(id) return recipes[id] end)
	-- A: 3 B + 1 X; B yields 2 per craft -> 2 crafts -> 2 X.
	eq(#e.crafts, 2)
	eq(e.crafts[1].itemID, A); eq(e.crafts[2].itemID, B); eq(e.crafts[2].quantity, 3); eq(e.crafts[2].crafts, 2); eq(e.crafts[2].depth, 1)
	eq(#e.buy, 1); eq(e.buy[1].itemID, X); eq(e.buy[1].quantity, 3, "2 for B + 1 for A, one line")
	-- Cycle: A from B, B from A. A is being crafted, so the A that B needs is bought.
	local cycle = {
		[A] = { reagents = { { itemID = B, quantity = 1 } }, output = { itemID = A, quantity = 1 } },
		[B] = { reagents = { { itemID = A, quantity = 1 } }, output = { itemID = B, quantity = 1 } },
	}
	e = ns.Balance.Expand({ { itemID = A, quantity = 2 } }, {}, Held({}), nil, function(id) return cycle[id] end)
	eq(#e.crafts, 2); eq(#e.buy, 1); eq(e.buy[1].itemID, A); eq(e.buy[1].quantity, 2)
end)

-- The report from Veli's game (2026-11-09): Light Leather Pants, Cured Light Hide on the Horde AH at
-- 1s80-1s99, crafted for 1s50 from Light Hide (1s AH) + Salt (50c vendor). Leather and thread for 2 crafts.
local function SetupCure(ns, stub, opts)
	opts = opts or {}
	local recipes = {
		[9068] = { info = { name = "Light Leather Pants", learned = true }, schematic = stub.Schematic({ { LEATHER, 10 }, { THREAD, 1 }, { CURED, 1 } }, PANTS) },
	}
	if not opts.noCure then
		recipes[CURE_HIDE_ID] = { info = { name = "Cured Light Hide", learned = true }, schematic = stub.Schematic({ { HIDE, 1 }, { SALT, 1 } }, CURED) }
	end
	stub.profession = { id = 165, name = "Leatherworking", skill = 100, max = 150, recipes = recipes }
	stub.Fire("TRADE_SKILL_SHOW")
	for id, name in pairs({ [LEATHER] = "Light Leather", [THREAD] = "Fine Thread", [CURED] = "Cured Light Hide", [HIDE] = "Light Hide",
		[SALT] = "Salt", [PANTS] = "Light Leather Pants" }) do
		stub.items[id] = { name = name }
	end
	stub.bags[0] = { { itemID = LEATHER, stackCount = 20 }, { itemID = THREAD, stackCount = 2 } }
	if opts.hides then
		stub.bags[0][3] = { itemID = HIDE, stackCount = opts.hides }
	end
	stub.Fire("BAG_UPDATE_DELAYED")
	local db = CraftWiseMarketDB
	local function listed(itemID, tiers)
		local total = 0
		for i = 2, #tiers, 2 do total = total + tiers[i] end
		db.items[itemID] = { [HORDE] = { raw = { { t = NOW, total = total, tiers = tiers } }, days = {},
			last = { t = NOW, min = tiers[1], qty = total } } }
	end
	listed(CURED, { opts.curedAt or 180, 1, 199, 20 })
	listed(HIDE, { 100, 50 })
	db.houses[HORDE] = { realm = "PvP", kind = "faction", faction = "Horde", label = "Horde AH", cut = { samples = 0 } }
	db.scans[HORDE] = { { t = NOW, kind = "search", items = 2, source = "ui" } }
	ns.db.vendor[THREAD] = 100
	ns.db.vendor[SALT] = 50
end

it("buy list crafts a cheaper intermediate: craft 2 Cured Light Hide, buy 2 Light Hide (AH) + 2 Salt (vendor)", function()
	local ns, stub = Load()
	SetupCure(ns, stub)
	local lines, b = ns.BalanceLines(PANTS_REAGENTS, nil, PANTS)
	eq(b.target, 2); eq(b.possible, 0)
	eq(#b.crafts, 1); eq(b.crafts[1].itemID, CURED); eq(b.crafts[1].quantity, 2)
	eq(#b.buy, 2)
	eq(b.buy[1].itemID, HIDE); eq(b.buy[1].quantity, 2); eq(b.buy[1].quote.source, "auction")
	eq(b.buy[2].itemID, SALT); eq(b.buy[2].quantity, 2); eq(b.buy[2].quote.source, "vendor")
	eq(b.total, 2 * 150, "the crafted cost of 2 Cured Light Hide"); eq(b.complete, true)
	local text = LinesText(lines)
	has(text, "To buy for 2 crafts")
	has(text, "Craft 2 × Cured Light Hide | each: crafted 1s 50c · bought 1s 80c")
	has(text, "2 × Light Hide | 2s  AH · Horde AH")
	has(text, "2 × Salt | 1s  vendor")
	has(text, "Total | 3s")
	assert(not text:find("\n  2 × Cured Light Hide |", 1, true), "Cured Light Hide itself is not bought:\n" .. text)
	-- the cost line of the same recipe makes the same decision
	local row
	for _, r in ipairs(ns.BuildRows(165, false, "profit")) do
		if r.recipeID == 9068 then row = r end
	end
	for _, l in ipairs(row.reagents) do
		if l.itemID == CURED then eq(l.source, "crafted"); eq(l.unit, 150) end
	end
end)

it("buy list craft: held Light Hide is used first", function()
	local ns, stub = Load()
	SetupCure(ns, stub, { hides = 1 })
	local lines, b = ns.BalanceLines(PANTS_REAGENTS, nil, PANTS)
	eq(b.crafts[1].quantity, 2)
	eq(b.buy[1].itemID, HIDE); eq(b.buy[1].quantity, 1)
	eq(b.buy[2].itemID, SALT); eq(b.buy[2].quantity, 2)
	eq(b.total, 100 + 2 * 50)
	has(LinesText(lines), "1 × Light Hide | 1s  AH · Horde AH")
end)

it("buy list unchanged when buying the intermediate is cheaper or no known recipe makes it", function()
	local ns, stub = Load()
	SetupCure(ns, stub, { curedAt = 140 })
	local lines, b = ns.BalanceLines(PANTS_REAGENTS, nil, PANTS)
	eq(#b.crafts, 0); eq(#b.buy, 1); eq(b.buy[1].itemID, CURED); eq(b.buy[1].quantity, 2)
	local text = LinesText(lines)
	has(text, "2 × Cured Light Hide | 3s 39c  AH · Horde AH")
	assert(not text:find("  Craft ", 1, true), text)
	ns, stub = Load()
	SetupCure(ns, stub, { noCure = true })
	lines, b = ns.BalanceLines(PANTS_REAGENTS, nil, PANTS)
	eq(#b.crafts, 0); eq(#b.buy, 1); eq(b.buy[1].itemID, CURED); eq(b.total, 180 + 199)
end)

it("buy list decides at market prices whatever the view's cost basis (Scout decision on #60)", function()
	local ns, stub = Load()
	SetupCure(ns, stub)
	stub.bags[0][3] = { itemID = CURED, stackCount = 1 }
	stub.names.player = "Veli"
	stub.counts[CURED] = 1
	stub.Fire("BAG_UPDATE_DELAYED")
	ns.Ledger.Record("ahbuy", CURED, 1, 120, HORDE, 0) -- 1s20 paid
	eq(ns.Ledger.PaidCost(CURED).copper, 120)
	ns.db.settings.costBasis.level = "paid"
	ns.db.settings.costBasis.profit = "paid"
	-- The cost line keeps following the setting: the held Cured Light Hide at its paid cost.
	local checked = false
	for _, r in ipairs(ns.BuildRows(165, false, "level")) do
		if r.recipeID == 9068 then
			for _, l in ipairs(r.reagents) do
				if l.itemID == CURED then eq(l.source, "paid"); eq(l.unit, 120); checked = true end
			end
		end
	end
	assert(checked, "no Cured Light Hide cost line in the level view")
	-- The one missing unit is crafted: 1s50 at market beats 1s80 on the AH.
	local _, b = ns.BalanceLines(PANTS_REAGENTS, nil, PANTS)
	eq(#b.crafts, 1); eq(b.crafts[1].itemID, CURED); eq(b.crafts[1].quantity, 1)
	eq(b.crafts[1].info.craftUnit, 150); eq(b.crafts[1].info.buyUnit, 180)
	eq(#b.buy, 2); eq(b.buy[1].itemID, HIDE); eq(b.buy[1].quantity, 1); eq(b.buy[2].itemID, SALT); eq(b.buy[2].quantity, 1)
	eq(b.total, 150)
end)

it("Make › Craft row tooltip shows the crafted buy list", function()
	local ns, stub = Load()
	SetupCure(ns, stub)
	local seen = {}
	local add, add2 = GameTooltip.AddLine, GameTooltip.AddDoubleLine
	GameTooltip.AddLine = function(self, l, ...) seen[#seen + 1] = Plain(tostring(l)); return add(self, l, ...) end
	GameTooltip.AddDoubleLine = function(self, l, r, ...) seen[#seen + 1] = Plain(l) .. " | " .. Plain(r); return add2(self, l, r, ...) end
	Make.Open(ns, "craft", 165)
	local hovered = Make.Hover(ns, "craft", 9068)
	GameTooltip.AddLine, GameTooltip.AddDoubleLine = add, add2
	assert(hovered, "no pants row")
	local text = table.concat(seen, "\n")
	has(text, "Craft 2 × Cured Light Hide | each: crafted 1s 50c · bought 1s 80c")
	has(text, "2 × Salt | 1s  vendor")
	has(text, "Total | 3s")
end)
