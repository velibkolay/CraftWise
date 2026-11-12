-- Look up › Items (#157, spec in #150 "Look up, Music, Settings"): search, the left list and its chips, the
-- card with its figures, the chart (Line objects, else day bars), "latest only" outside the market scope,
-- Used in, Where to buy, and the ways in (item menu, Shift-click). Invented data only.
local NOW = os.time({ year = 2026, month = 11, day = 12, hour = 15 })
local DAY = 86400
local HORDE, BOOTY = "PvP|H", "PvP|N:BootyBay"
local LEATHER, SALT, BOOTS, DYE, SCALE = 990101, 990102, 990103, 990104, 990105

local function Load(opts)
	local ns, stub = LoadAddon(opts)
	stub.clock = NOW
	time = function(t)
		if t then return os.time(t) end
		return stub.clock
	end
	stub.names.player, stub.surnames.player = "Testperson", "Tanner"
	stub.items[LEATHER] = { name = "Testleather", sellPrice = 150, stack = 20 }
	stub.items[SALT] = { name = "Testsalt", sellPrice = 12, stack = 20 }
	stub.items[BOOTS] = { name = "Testboots", sellPrice = 70, stack = 1 }
	stub.items[DYE] = { name = "Testdye", sellPrice = 25, stack = 20 }
	stub.items[SCALE] = { name = "Testscale", sellPrice = 0, stack = 20 }
	stub.Fire("PLAYER_LOGIN")
	return ns, stub, ns.Main
end

-- o.typs: typ per day, today first (a day without a price: false); o.tiers = { p1, q1, ... } of the
-- latest point (now - 1 h); o.min / o.total without tiers = a browse price; o.lastOnly = `last` only.
local function Seed(itemID, house, o)
	local db = CraftWiseMarketDB
	local today = math.floor(NOW / DAY)
	local days = {}
	for i, typ in ipairs(o.typs or {}) do
		if typ then
			days[today - i + 1] = { lo = o.los and o.los[i] or typ, typ = typ, hi = typ, n = 1 }
		end
	end
	local raw = {}
	if o.tiers then
		raw[1] = { t = NOW - 3600, total = o.total, listings = o.listings, tiers = o.tiers }
	end
	db.items[itemID] = db.items[itemID] or {}
	db.items[itemID][house] = { raw = o.lastOnly and {} or raw, days = o.lastOnly and {} or days,
		last = { t = NOW - 3600, min = o.tiers and o.tiers[1] or o.min, qty = o.total, listings = o.listings } }
	db.houses[house] = db.houses[house] or (house == HORDE and { realm = "PvP", kind = "faction", faction = "Horde", label = "Horde AH" }
		or { realm = "PvP", kind = "neutral", label = "Booty Bay", cut = { samples = 0 } })
	db.scans[house] = { { t = NOW - 7200, kind = "full", items = 500, source = "replicate" } }
end

-- Testleather: in scope, five days of history (typical 9s 50c, latest tiers from 8s 50c), 214 listed.
local function SeedLeather()
	Seed(LEATHER, HORDE, { typs = { 900, 920, 950, 980, 1020 }, los = { 850, 880, 900, 950, 1000 },
		tiers = { 850, 40, 900, 174 }, total = 214, listings = 9 })
	CraftWiseMarketDB.scope.items[LEATHER] = true
end

local function has(text, s) assert(tostring(text):find(s, 1, true), ("missing %q in:\n%s"):format(s, tostring(text))) end

----------------------------------------------------------------------------------------------------
-- Model
----------------------------------------------------------------------------------------------------

it("Items: search by name (AH or merchant records), item ID or link; exact names first; nothing found says so", function()
	local ns, _, M = Load()
	SeedLeather()
	Seed(BOOTS, HORDE, { min = 9000, total = 1 }) -- outside the scope: found by name
	CraftWiseMarketDB.names[BOOTS] = "Testboots"
	ns.db.merchants[3001] = { name = "Test Merchant", zone = "Testzone", t = NOW - 60,
		items = { [SALT] = { name = "Testsalt", p = 40, s = 1, n = -1, t = NOW - 60 } } }
	local I = M.Items
	local ids = I.Search("test")
	eq(#ids, 3)
	ids = I.Search("testboots")
	eq(ids[1], BOOTS)
	eq(I.Search("salt")[1], SALT, "merchant item")
	eq(I.Search(tostring(LEATHER))[1], LEATHER)
	eq(I.Search("|cffffffff|Hitem:" .. BOOTS .. "::::|h[Testboots]|h|r")[1], BOOTS)
	eq(#I.Search("nothing like it"), 0)
	I.state.query = "nothing like it"
	local list = I.ListModel(NOW)
	eq(#list.rows, 0); has(list.empty, "No recorded item matches")
	eq(list.searching, true)
end)

it("Items: chips Watched, Your recipes (scope) and Recent", function()
	local ns, _, M = Load()
	SeedLeather()
	Seed(BOOTS, HORDE, { min = 9000, total = 1 })
	local I = M.Items
	local chips = {}
	for _, c in ipairs(I.Chips()) do chips[#chips + 1] = c.key end
	eq(table.concat(chips, ","), "watched,recipes,recent")
	eq(I.Chip(), "recipes", "a fresh list does not open on the empty Watched chip")
	local list = I.ListModel(NOW)
	eq(#list.rows, 1); eq(list.rows[1].itemID, LEATHER)
	I.Select(BOOTS); I.Select(LEATHER); I.Select(BOOTS)
	I.SetChip("recent")
	list = I.ListModel(NOW)
	eq(list.rows[1].itemID, BOOTS); eq(list.rows[2].itemID, LEATHER); eq(#list.rows, 2)
	eq(ns.db.settings.ui.lookup.item, BOOTS, "the item shown is kept")
	-- the Watched chip lists ns.ItemWatch (#165)
	ns.ItemWatch.Set(LEATHER, true)
	I.SetChip("watched")
	eq(I.ListModel(NOW).rows[1].itemID, LEATHER)
	eq(I.Card(LEATHER, NOW).watched, true)
	eq(I.Card(BOOTS, NOW).watched, false)
end)

it("Items: rows say how many are listed (thin, vendor only), the typical price and the 7-day change with a sign", function()
	local ns, stub, M = Load()
	SeedLeather()
	Seed(SALT, HORDE, { typs = { 50, 50, 40 }, tiers = { 50, 3, 60, 30 }, total = 33, listings = 2 })
	ns.db.vendor[DYE] = 1000 -- bought at a vendor, never seen at the AH
	local I = M.Items
	local leather = I.Row(LEATHER, NOW)
	eq(leather.note, "214 listed")
	eq(leather.priceText, ns.FormatCoins(950), "typical: median of the days")
	-- first day 10s 20c, today 8s 50c (the latest point counts for today): -17 %
	eq(leather.change, -17)
	has(leather.changeText, "−17 %"); eq(leather.changeColor, "nokta")
	local salt = I.Row(SALT, NOW)
	eq(salt.note, "33 listed · thin", "the cheapest tier holds less than a stack")
	eq(salt.change, 25); has(salt.changeText, "+25 %"); eq(salt.changeColor, "danger")
	local dye = I.Row(DYE, NOW)
	eq(dye.note, "vendor only"); eq(dye.priceText, ns.FormatCoins(1000)); eq(dye.changeText, "vendor")
	local none = I.Row(BOOTS, NOW)
	eq(none.note, "no AH data"); has(none.priceText, "no price"); eq(none.change, nil)
	eq(I.Change({ { typ = 100 } }), nil, "one day is no change")
	eq(I.ChangeText(0), "±0 %")
end)

it("Items: the card's figures, chart series, Used in and Where to buy", function()
	local ns, stub, M = Load()
	SeedLeather()
	Seed(LEATHER, BOOTY, { typs = { 1100, 1100, 1100 }, min = 1150, total = 12 })
	ns.db.merchants[3001] = { name = "Test Merchant", zone = "Testzone", t = NOW - 60,
		items = { [LEATHER] = { name = "Testleather", p = 2000, s = 1, n = -1, t = NOW - 60 } } }
	stub.bags[0] = { { itemID = LEATHER, stackCount = 6 } }
	local I = M.Items
	local card = I.Card(LEATHER, NOW)
	eq(card.name, "Testleather")
	has(card.sub, "stacks of 20"); has(card.sub, "you have 6 in bags")
	eq(card.subTip[1]:sub(1, 8), "Counted:")
	eq(card.figures.typical.text, ns.FormatCoins(950))
	has(table.concat(card.figures.typical.tip, "\n"), "Booty Bay: ")
	eq(card.figures.lowest.text, ns.FormatCoins(850))
	has(table.concat(card.figures.lowest.tip, "\n"), "Cheapest: 40 @")
	eq(card.figures.listed.text, "214")
	has(card.figures.change.text, "−17 %")
	eq(card.chart.mode, "chart")
	eq(#card.chart.series, 7); eq(card.chart.last, "Today")
	eq(card.chart.series[7].typ, 850); eq(card.chart.series[7].lo, 850)
	eq(card.chart.series[3].typ, 1020); eq(card.chart.series[1].typ, nil, "no price that day")
	eq(card.where[1].left, "Test Merchant")
	eq(card.where[#card.where - 1].left, "Vendor sell price"); eq(card.where[#card.where - 1].right, ns.FormatCoins(150))
	eq(card.where[#card.where].left, "Your last purchase"); eq(card.where[#card.where].right, "none logged")
	has(card.whereTip[1], "Test Merchant")
	eq(card.usedIn[1].left, "No recipe uses it.")
	-- a purchase in the ledger
	ns.Ledger.Record("ahbuy", LEATHER, 5, 4400, HORDE, 0)
	card = I.Card(LEATHER, NOW)
	has(card.where[#card.where].right, ns.FormatCoins(880) .. " each")
	-- no merchant
	eq(I.Card(SALT, NOW).where[1].left, "No merchant you opened sells it.")
end)

it("Items: outside the market scope only the latest price is kept: 'latest only' and no chart", function()
	local ns, _, M = Load()
	Seed(SCALE, HORDE, { lastOnly = true, min = 12000, total = 3, listings = 3 })
	local I = M.Items
	local row = I.Row(SCALE, NOW)
	eq(row.changeText, "latest only"); eq(row.note, "3 listed")
	local card = I.Card(SCALE, NOW)
	eq(card.chart.mode, "latest"); has(card.chart.note, "Latest price only")
	has(card.figures.typical.text, "latest only")
	eq(card.figures.lowest.text, ns.FormatCoins(12000))
	-- once it is in the scope, history is kept from then on: no chart until a day has a price
	CraftWiseMarketDB.scope.items[SCALE] = true
	eq(I.Card(SCALE, NOW).chart.mode, "none")
end)

it("Items: chart geometry, dashes and the mode", function()
	local _, _, M = Load()
	local I = M.Items
	local g = I.ChartGeometry({ { typ = 100, lo = 80 }, {}, { typ = 120, lo = 100 } }, 200, 120, 8)
	eq(g.max, 120); eq(g.min, 80)
	eq(#g.typ, 2); eq(g.typ[1].x, 0); eq(g.typ[2].x, 200)
	eq(g.typ[2].y, 112, "the top value sits pad below the top"); eq(g.lo[1].y, 8)
	eq(g.latest, g.typ[2])
	eq(I.ChartGeometry({ {}, {} }, 200, 120), nil)
	local d = I.Dashes(0, 0, 10, 0, 3, 3)
	eq(#d, 2); eq(d[1][3], 3); eq(d[2][1], 6); eq(d[2][3], 9)
	eq(I.ChartMode({ CreateLine = function() end }), "lines")
	eq(I.ChartMode({ CreateLine = false }), "bars")
end)

----------------------------------------------------------------------------------------------------
-- Page
----------------------------------------------------------------------------------------------------

local function OpenItems(M)
	M.Open("items")
	return M.SlotsOf("items").body
end

it("Items page: the list and the card draw; Line objects for the chart with the nokta on the latest point", function()
	local ns, stub, M = Load()
	SeedLeather()
	M.Items.Select(LEATHER)
	local body = OpenItems(M)
	eq(M.shown.page, "items"); eq(M.shown.state, "custom")
	eq(M.Frame().head.status.shown, true, "the AH status shows")
	local left = body.left
	eq(left.chips[1].label.text, "Watched"); eq(left.chips[1].on, false)
	eq(left.chips[2].label.text, "Your recipes"); eq(left.chips[2].on, true)
	local row = left.box.frames[1]
	eq(row.name.text, "Testleather"); eq(row.note.text, "214 listed"); eq(row.bg.shown, true)
	local card = body.card
	eq(card.name.text, "Testleather")
	eq(card.figs[1].value.text, ns.FormatCoins(950))
	eq(card.chart.mode, "lines")
	-- typical: 4 days with a price, 3 segments; lowest: dashed
	local solid, dashed = 0, 0
	for _, l in ipairs(card.chart.lines) do
		if l.shown ~= false then
			if l.thickness == 2 then solid = solid + 1 else dashed = dashed + 1 end
		end
	end
	eq(solid, 4) -- days -4..0 have a typical: 5 points, 4 segments
	assert(dashed > 4, "dashes for the lowest price")
	eq(card.chart.nokta.shown, true)
	eq(card.chart.first.text ~= "", true); eq(card.chart.last.text, "Today")
	-- hovering the figures shows their reason
	card.figs[2].scripts.OnEnter(card.figs[2])
	eq(CraftWiseInverseTip.title.text, "Lowest now")
	eq(card.watch.shown, true, "the Watched toggle (#165)")
end)

it("Items page: chart fallback: seven 4 unit day bars where the client has no CreateLine", function()
	local ns, stub, M = Load()
	SeedLeather()
	M.Items.Select(LEATHER)
	M.Open("items")
	local body = M.SlotsOf("items").body
	body.card.chart.CreateLine = false
	M.Refresh()
	local chart = body.card.chart
	eq(chart.mode, "bars")
	local bars = 0
	for _, b in ipairs(chart.bars) do
		if b.shown ~= false then
			bars = bars + 1
			eq(b.width, 4)
		end
	end
	eq(bars, 5, "one per day with a typical price")
	for _, l in ipairs(chart.lines) do eq(l.shown, false) end
end)

it("Items page: works without AH data (merchant prices); no item chosen asks for one", function()
	local ns, stub, M = Load()
	local body = OpenItems(M)
	eq(M.shown.state, "custom", "No prices doesn't replace this page")
	eq(body.card.empty.shown, true)
	has(body.left.empty.text, "No recorded item of your recipes yet")
end)

it("Items page: search box, row clicks (select, item menu, chat link), Shift-click fills the box", function()
	local ns, stub, M = Load()
	SeedLeather()
	Seed(SALT, HORDE, { typs = { 50 }, tiers = { 50, 30 }, total = 30, listings = 1 })
	local body = OpenItems(M)
	local box = M.Items.searchBox
	box:SetText("testsalt")
	box.scripts.OnTextChanged(box)
	eq(M.Items.state.query, "testsalt")
	local row = body.left.box.frames[1]
	eq(row.row.itemID, SALT)
	eq(body.left.chips[1].on, false, "a search replaces the chip's list")
	box.scripts.OnEnterPressed(box)
	eq(M.Items.Selected(), SALT)
	eq(M.Items.ClickRow(row.row, "RightButton", row), "menu")
	eq(CraftWiseItemMenu.itemID, SALT)
	stub.shift = true
	stub.items[SALT].link = "|cffffffff|Hitem:" .. SALT .. "::::|h[Testsalt]|h|r"
	eq(M.Items.ClickRow(row.row, "LeftButton", row), "link")
	eq(stub.chatLinks[#stub.chatLinks], stub.items[SALT].link)
	stub.shift = false
	-- a chip clears the search
	body.left.chips[1].scripts.OnClick(body.left.chips[1])
	eq(M.Items.state.query, ""); eq(box:GetText(), "")
	-- Shift-clicking an item while the box has focus puts the link there
	box.HasFocus = function() return true end
	ChatFrameUtil.InsertLink(stub.items[SALT].link)
	eq(box:GetText(), stub.items[SALT].link)
	box.scripts.OnTextChanged(box)
	eq(body.left.box.frames[1].row.itemID, SALT)
	box.HasFocus = function() return false end
	eq(M.Items.InsertLink("x"), false)
end)

it("Items page: the item menu's Where to buy and Price history open it on the item", function()
	local ns, stub, M = Load()
	SeedLeather()
	ns.ShowItemMenu(LEATHER)
	local where = CraftWiseItemMenu.buttons.where
	where.scripts.OnClick(where)
	eq(M.shown.page, "items"); eq(M.Items.Selected(), LEATHER); eq(M.Items.state.focus, "where")
	eq(M.Frame():IsShown(), true)
	ns.ShowItemMenu(SALT)
	local history = CraftWiseItemMenu.buttons.history
	history.scripts.OnClick(history)
	eq(M.Items.Selected(), SALT); eq(M.Items.state.focus, "history")
	eq(M.Items.ChipItems("recent")[1], SALT)
	ns.ShowWhereToBuy(LEATHER)
	eq(M.Items.Selected(), LEATHER)
	ns.ShowMarketPrices(SALT)
	eq(M.Items.Selected(), SALT)
	eq(ns.RW.Market, nil, "Records › Market is gone"); eq(ns.RW.Where, nil, "Records › Where to buy is gone")
end)
