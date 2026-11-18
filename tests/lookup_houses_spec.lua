-- Look up › Items (#350): the card's "Auction houses" section and the "Cheaper elsewhere" list. Prices per
-- house, the net after the profit house's measured cut (never a constant), ages, items listed at one house
-- only, `off` items, the list's order and its cache. Invented data only; the numbers of the first two
-- recipes are the ones from the issue.
local NOW = os.time({ year = 2026, month = 11, day = 18, hour = 16 })
local HORDE, GADGET = "PvP|H", "PvP|N:Gadgetzan"
local STAMINA, THORIUM, SAME, GONE, ONLYGAD, ONLYHORDE = 990201, 990202, 990203, 990204, 990205, 990206

local function Load()
	local ns, stub = LoadAddon()
	stub.clock = NOW
	time = function(t)
		if t then return os.time(t) end
		return stub.clock
	end
	local names = { [STAMINA] = "Formula: Enchant Chest - Major Stamina", [THORIUM] = "Schematic: Thorium Shells",
		[SAME] = "Recipe: Same Price", [GONE] = "Recipe: Gone Again", [ONLYGAD] = "Recipe: Only Gadgetzan",
		[ONLYHORDE] = "Recipe: Only Horde" }
	for id, name in pairs(names) do
		stub.items[id] = { name = name, sellPrice = 0, stack = 1 }
		CraftWiseMarketDB.names[id] = name
	end
	CraftWiseMarketDB.houses[HORDE] = { realm = "PvP", kind = "faction", faction = "Horde", label = "Horde AH",
		cut = { samples = 4, rate = 0.05 } }
	CraftWiseMarketDB.houses[GADGET] = { realm = "PvP", kind = "neutral", label = "Gadgetzan", cut = { samples = 0 } }
	CraftWiseMarketDB.scans[HORDE] = { { t = NOW - 15 * 3600, kind = "full", items = 500, source = "replicate" } }
	CraftWiseMarketDB.scans[GADGET] = { { t = NOW - 3600, kind = "full", items = 500, source = "replicate" } }
	stub.Fire("PLAYER_LOGIN")
	return ns, stub, ns.Main
end

-- One price at a house: the latest observation seen `age` seconds ago, `qty` units from `min`.
local function Put(itemID, house, min, qty, age)
	local db = CraftWiseMarketDB
	db.items[itemID] = db.items[itemID] or {}
	db.items[itemID][house] = { raw = {}, days = {}, last = { t = NOW - age, min = min, qty = qty, listings = 1 } }
end

local function Seed()
	Put(STAMINA, HORDE, 3500, 2, 15 * 3600); Put(STAMINA, GADGET, 1456, 1, 3600)
	Put(THORIUM, HORDE, 1200, 5, 15 * 3600); Put(THORIUM, GADGET, 250, 12, 3600)
	Put(SAME, HORDE, 1000, 3, 15 * 3600); Put(SAME, GADGET, 1000, 3, 3600) -- the cut leaves a loss
	Put(GONE, HORDE, 1200, 3, 15 * 3600); Put(GONE, GADGET, 100, 3, 3600)
	CraftWiseMarketDB.items[GONE][GADGET].last.off = NOW - 1800 -- a later full scan didn't list it
	Put(ONLYGAD, GADGET, 800, 4, 3600)
	Put(ONLYHORDE, HORDE, 900, 4, 15 * 3600)
end

local function has(text, s) assert(tostring(text):find(s, 1, true), ("missing %q in:\n%s"):format(s, tostring(text))) end
local function joined(lines)
	local out = {}
	for _, l in ipairs(lines) do out[#out + 1] = (l.left or "") .. " | " .. (l.right or "") end
	return table.concat(out, "\n")
end

it("Auction houses section: the profit house first, each house's lowest, units and age; net after the measured cut", function()
	local ns, _, M = Load()
	Seed()
	local sec = M.Items.Card(THORIUM, NOW).houses
	eq(sec.title, "Auction houses")
	eq(#sec.rows, 2)
	eq(sec.rows[1].profit, true); eq(sec.rows[1].label, "Horde AH"); eq(sec.rows[1].lowest, 1200); eq(sec.rows[1].qty, 5)
	eq(sec.rows[2].label, "Gadgetzan"); eq(sec.rows[2].lowest, 250); eq(sec.rows[2].qty, 12)
	-- 1200 x (1 - 5 %) - 250 = 890 (8g 90s)
	eq(sec.rows[2].diff.copper, 890); eq(sec.rows[2].diff.measured, true)
	local text = joined(sec.lines)
	has(text, "Horde AH · profit house"); has(text, ns.FormatCoins(1200)); has(text, ns.FormatCoins(250))
	has(text, "12 listed"); has(text, "seen 15 h ago"); has(text, "seen 1 h ago")
	has(text, "sell at Horde AH (seen 15 h ago), after the 5 % cut")
	has(text, "+" .. ns.FormatCoins(890))
	has(table.concat(sec.tip, "\n"), "no auction house is queried")
	has(table.concat(sec.tip, "\n"), "Deposits are not counted")
	-- Major Stamina: 3500 x 0.95 - 1456 = 1869 (18g 69s)
	eq(M.Items.Card(STAMINA, NOW).houses.rows[2].diff.copper, 1869)
end)

it("Auction houses section: an unmeasured cut shows the gross difference and says so; the cut is never a constant", function()
	local ns, _, M = Load()
	Seed()
	CraftWiseMarketDB.houses[HORDE].cut = { samples = 0 }
	local sec = M.Items.Card(THORIUM, NOW).houses
	eq(sec.rows[2].diff.measured, false); eq(sec.rows[2].diff.copper, 950, "1200 - 250")
	local text = joined(sec.lines)
	has(text, "cut not measured"); has(text, "+" .. ns.FormatCoins(950) .. " gross")
	-- a measured 10 % cut changes the figure: 1200 x 0.9 - 250
	CraftWiseMarketDB.houses[HORDE].cut = { samples = 2, rate = 0.10 }
	eq(M.Items.Card(THORIUM, NOW).houses.rows[2].diff.copper, 830)
end)

it("Auction houses section: listed only at the other house says it isn't listed at the profit house; one house gives no section", function()
	local _, _, M = Load()
	Seed()
	local sec = M.Items.Card(ONLYGAD, NOW).houses
	eq(sec.rows[1].profit, true); eq(sec.rows[1].lowest, nil)
	eq(sec.rows[2].lowest, 800); eq(sec.rows[2].diff.none, true)
	has(joined(sec.lines), "Not listed at Horde AH: nothing to sell against.")
	eq(M.Items.Card(ONLYHORDE, NOW).houses, nil, "no other house has it: no section")
end)

it("Cheaper elsewhere: items whose net is above zero, best first; an `off` item and a loss are left out", function()
	local ns, _, M = Load()
	Seed()
	local I = M.Items
	I.ElseWarmNow()
	local rows = I.ElseItems()
	eq(#rows, 2)
	eq(rows[1].itemID, STAMINA); eq(rows[1].copper, 1869)
	eq(rows[2].itemID, THORIUM); eq(rows[2].copper, 890)
	eq(rows[2].buyLabel, "Gadgetzan"); eq(rows[2].buyMin, 250); eq(rows[2].buyQty, 12); eq(rows[2].sellMin, 1200)
	local row = I.ElseRow(rows[2], NOW)
	has(row.note, "Gadgetzan"); has(row.note, ns.FormatCoins(250)); has(row.note, "×12"); has(row.note, "1 h")
	has(row.priceText, "+" .. ns.FormatCoins(890))
	has(row.changeText, "Horde AH"); has(row.changeText, ns.FormatCoins(1200)); has(row.changeText, "15 h")
	has(table.concat(row.tip, "\n"), "Net per unit after the 5 % cut")
	-- an unmeasured cut: the gross difference qualifies and is marked
	CraftWiseMarketDB.houses[HORDE].cut = { samples = 0 }
	I.ElseWarmNow()
	local gross = I.ElseItems()
	eq(gross[1].itemID, STAMINA); eq(gross[1].copper, 2044); eq(gross[1].measured, false)
	eq(#gross, 2, "equal prices gain nothing gross either; the `off` item stays out")
	has(I.ElseRow(gross[1], NOW).priceText, "*")
end)

it("Cheaper elsewhere: the chip shows only with another house's data and lists on the page", function()
	local _, _, M = Load()
	Seed()
	local I = M.Items
	local keys = {}
	for _, c in ipairs(I.Chips()) do keys[#keys + 1] = c.key end
	eq(table.concat(keys, ","), "watched,recipes,recent,elsewhere")
	I.SetChip("elsewhere")
	eq(I.Chip(), "elsewhere")
	I.ElseWarmNow()
	local list = I.ListModel(NOW)
	eq(#list.rows, 2); eq(list.rows[1].itemID, STAMINA); eq(list.chip, "elsewhere")
	M.Open("items")
	local body = M.SlotsOf("items").body
	local first = body.left.box.frames[1]
	eq(first.row.itemID, STAMINA)
	first.scripts.OnEnter(first)
	eq(CraftWiseInverseTip.title.text, "Formula: Enchant Chest - Major Stamina", "a row's tip gives both prices and the net")
	-- without another house's data the chip is gone and the list falls back
	CraftWiseMarketDB.scans[GADGET] = nil
	eq(#I.OtherHouses(), 0)
	eq(I.Chip(), "recipes")
end)

it("Cheaper elsewhere: built once per data version and scan stamp, not per refresh; a new scan rebuilds it", function()
	local ns, _, M = Load()
	Seed()
	local I = M.Items
	I.ElseWarmNow()
	local builds, indexBuilds = I.elseBuilds, ns.Market.indexBuilds
	for _ = 1, 5 do I.ElseItems(); I.ListModel(NOW) end
	eq(I.elseBuilds, builds, "refreshes read the cache")
	eq(ns.Market.indexBuilds, indexBuilds, "and the key index isn't built again")
	-- a scan at Gadgetzan moves the stamp although no key changed: the list is rebuilt
	table.insert(CraftWiseMarketDB.scans[GADGET], { t = NOW - 60, kind = "full", items = 500, source = "replicate" })
	Put(SAME, GADGET, 100, 3, 60)
	I.ElseWarmNow()
	eq(I.elseBuilds, builds + 1)
	eq(#I.ElseItems(), 3, "the item that had no gain now has one")
end)

it("Items page: the card draws the Auction houses block and scrolls; one-house items hide it", function()
	local _, _, M = Load()
	Seed()
	local I = M.Items
	I.Select(THORIUM)
	M.Open("items")
	local body = M.SlotsOf("items").body
	local card = body.card
	eq(card.houses.shown, true); eq(card.housesHit.shown, true)
	eq(#card.houses.lines, 5, "profit house: price and detail; Gadgetzan: price, detail and the net line")
	has(card.houses.rows[1].left.text, "Horde AH · profit house")
	eq(card.contentHeight > 0, true); eq(body.dscroll.shown, true)
	card.housesHit.scripts.OnEnter(card.housesHit)
	eq(CraftWiseInverseTip.title.text, "Auction houses")
	I.Select(ONLYHORDE)
	M.Refresh()
	eq(card.houses.shown, false)
end)
