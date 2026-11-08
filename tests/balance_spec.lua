-- Issue #49: reagent imbalance warning with a buy list. Example from Veli's run: 60 Cured Light
-- Hide, but Light Leather for only 8 Light Leather Pants.
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
	for _, view in ipairs({ "profit", "level" }) do
		seen = {}
		ns.db.settings.view = view
		if ns.PF and ns.PF.frame and ns.PF.frame:IsShown() then ns.RefreshProfitFrame() else ns.ToggleProfitFrame() end
		local hovered = false
		for _, f in ipairs(stub.frames) do
			if f.data and f.data.recipeID == 9068 and f.scripts.OnEnter and f:IsShown() then
				f.scripts.OnEnter(f); hovered = true
				break
			end
		end
		assert(hovered, "no pants row in the " .. view .. " view")
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
