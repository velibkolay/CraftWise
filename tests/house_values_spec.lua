-- Issue #40: every AH value uses the profit house and price basis (Bags view, item tooltip advice,
-- AH rule, AH learn cost, disenchant value) and the cut source is shown ("confirmed" / "measured" /
-- "unverified").
local Make = dofile("tests/make_helpers.lua")
local NOW = 1794000000
local DAY = 86400
local HORDE, BOOTY = "PvP|H", "PvP|N:BootyBay"
local HOUSES = {
	[HORDE] = { realm = "PvP", kind = "faction", faction = "Horde", label = "Horde AH" },
	[BOOTY] = { realm = "PvP", kind = "neutral", label = "Booty Bay" },
}

local function Load(opts)
	local ns, stub = LoadAddon(opts)
	stub.clock = NOW
	time = function() return stub.clock end
	return ns, stub
end

-- typs: typical per day (today first); tiers = { price, qty, ... } latest scan.
local function Seed(itemID, house, o)
	local db = CraftWiseMarketDB
	local today = math.floor(NOW / DAY)
	local days = {}
	for i, typ in ipairs(o.typs or {}) do
		days[today - i + 1] = { lo = typ, typ = typ, hi = typ, n = 1 }
	end
	db.items[itemID] = db.items[itemID] or {}
	db.items[itemID][house] = { raw = { { t = NOW, total = o.total, tiers = o.tiers } }, days = days,
		last = { t = NOW, min = o.tiers[1], qty = o.total } }
	if not db.houses[house] then
		local h = HOUSES[house]
		db.houses[house] = { realm = h.realm, kind = h.kind, faction = h.faction, label = h.label, cut = { samples = 0 } }
	end
	db.scans[house] = { { t = NOW, kind = "search", items = 1, source = "ui" } }
end

local function has(text, s) assert(text:find(s, 1, true), ("missing %q in:\n%s"):format(s, text)) end

local function TooltipText(ns, itemID)
	local tip = { lines = {} }
	function tip:AddLine(t) table.insert(self.lines, t) end
	function tip:AddDoubleLine(l, r) table.insert(self.lines, l .. " | " .. r) end
	function tip:Show() end
	ns.AddTooltipLines(tip, itemID)
	return (table.concat(tip.lines, "\n"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

local function BagRow(ns, itemID)
	for _, r in ipairs(ns.BagRows()) do
		if r.itemID == itemID then return r end
	end
end

local function Bags(stub, items)
	stub.bags[0] = items
end

------------------------------------------------------------------------------------ cut source

it("cut source: confirmed 5% at the own faction house, no warning", function()
	local ns = Load()
	Seed(5, HORDE, { typs = { 200, 200, 200 }, tiers = { 200, 10 }, total = 10 })
	local sale = ns.AuctionSale(5, 10)
	eq(sale.cutInfo.source, "confirmed"); eq(sale.cutText, "5% cut (confirmed)"); eq(sale.cutDiffers, nil)
	eq(sale.gross, 2000); eq(sale.net, 1900)
end)

it("cut source: neutral houses stay unverified with no net value", function()
	local ns = Load()
	ns.db.settings.priceHouse = "BootyBay"
	Seed(5, BOOTY, { tiers = { 300, 10 }, total = 10 })
	local sale = ns.AuctionSale(5, 2)
	eq(sale.cutInfo.source, "unverified"); eq(sale.cutText, "cut unverified")
	eq(sale.cut, nil); eq(sale.net, nil); eq(sale.cutUnverified, true); eq(sale.gross, 600)
end)

it("cut source: a measured cut wins and shows its sales; a differing one shows both and is flagged", function()
	local ns = Load()
	Seed(5, HORDE, { typs = { 200, 200, 200 }, tiers = { 200, 10 }, total = 10 })
	CraftWiseMarketDB.houses[HORDE].cut = { rate = 0.05, samples = 12 }
	local sale = ns.AuctionSale(5, 1)
	eq(sale.cutInfo.source, "measured"); eq(sale.cutText, "5% cut measured (12 sales)"); eq(sale.cutDiffers, nil)
	CraftWiseMarketDB.houses[HORDE].cut = { rate = 0.07, samples = 1 }
	sale = ns.AuctionSale(5, 1)
	eq(sale.cutText, "7% cut measured (1 sale), differs from 5% confirmed"); eq(sale.cutDiffers, true)
	eq(sale.net, 186, "the measured cut is the one applied")
	ns.db.settings.priceHouse = "BootyBay"
	Seed(5, BOOTY, { tiers = { 300, 10 }, total = 10 })
	CraftWiseMarketDB.houses[BOOTY].cut = { rate = 0.15, samples = 4 }
	sale = ns.AuctionSale(5, 1)
	eq(sale.cutText, "15% cut measured (4 sales)"); eq(sale.cutDiffers, nil, "no confirmed value to differ from")
	eq(sale.net, 255)
end)

it("cut source: Auctionator's price keeps its 5% and says the house is unknown", function()
	local ns, stub = Load({ auctionator = true })
	stub.ah[6] = 1000
	local sale = ns.AuctionSale(6, 1)
	eq(sale.label, "Auctionator (house unknown)"); eq(sale.cutText, "5% cut (house unknown)"); eq(sale.net, 950)
	eq(ns.AuctionSale(7, 1), nil)
end)

------------------------------------------------------------------------------------- Bags view

it("bags AH value follows the profit house and basis, with the fallback labels", function()
	local ns, stub = Load({ auctionator = true })
	stub.items[5] = { name = "Linen", sellPrice = 1 }
	Bags(stub, { { itemID = 5, stackCount = 10, quality = 1 } })
	Seed(5, HORDE, { typs = { 200, 200, 200 }, tiers = { 150, 10 }, total = 10 })
	Seed(5, BOOTY, { typs = { 80 }, tiers = { 90, 40 }, total = 40 })
	stub.ah[5] = 777
	local r = BagRow(ns, 5)
	eq(r.ahValue, 1900); eq(r.ahLabel, "typical · Horde AH"); eq(r.ahCutText, "5% cut (confirmed)")
	ns.db.settings.priceBasis = "current"
	r = BagRow(ns, 5)
	eq(r.ahValue, 1425); eq(r.ahLabel, "current lowest · Horde AH")
	ns.db.settings.priceBasis = "typical"
	ns.db.settings.priceHouse = "BootyBay"
	r = BagRow(ns, 5)
	eq(r.ahLabel, "current lowest, too little history · Booty Bay")
	eq(r.ahValue, nil, "neutral house: cut unverified, not counted"); eq(r.ahGross, 900); eq(r.ahCutUnverified, true)
	eq(r.ahCutText, "cut unverified"); eq(r.best, "vendor")
	CraftWiseMarketDB.houses[BOOTY].cut = { rate = 0.1, samples = 3 }
	r = BagRow(ns, 5)
	eq(r.ahValue, 810); eq(r.ahCutText, "10% cut measured (3 sales)"); eq(r.best, "auction")
	Seed(6, HORDE, { typs = { 1 }, tiers = { 1, 1 }, total = 1 }) -- another item, so item 5 is not alone
	stub.items[8] = { name = "Unrecorded", sellPrice = 1 }
	stub.ah[8] = 400
	Bags(stub, { { itemID = 8, stackCount = 2, quality = 1 }, { itemID = 9, stackCount = 1, quality = 1 } })
	stub.items[9] = { name = "Nothing", sellPrice = 1 }
	ns.db.settings.priceHouse = "faction"
	r = BagRow(ns, 8)
	eq(r.ahLabel, "Auctionator (house unknown)"); eq(r.ahValue, 760); eq(r.ahCutText, "5% cut (house unknown)")
	r = BagRow(ns, 9)
	eq(r.ahValue, nil); eq(r.ahLabel, nil); eq(r.ahGross, nil, "no price data")
end)

it("AH rule compares the profit house's net price with the vendor", function()
	local ns, stub = Load()
	stub.items[5] = { name = "Linen", sellPrice = 150 }
	Bags(stub, { { itemID = 5, stackCount = 1, quality = 1 } })
	Seed(5, HORDE, { typs = { 200, 200, 200 }, tiers = { 150, 10 }, total = 10 })
	ns.db.settings.ahMinPercent, ns.db.settings.ahMinCopper = 20, 0
	local r = BagRow(ns, 5)
	eq(r.ahValue, 190); eq(r.best, "auction", "typical 200 - 5% = 190 beats 150 + 20%")
	ns.db.settings.priceBasis = "current"
	r = BagRow(ns, 5)
	eq(r.ahValue, 142); eq(r.best, "vendor")
	local vendor, ahNet, best = ns.ItemAdvice(5, 1)
	eq(vendor, 150); eq(ahNet, 142); eq(best, "vendor")
	ns.db.settings.priceBasis = "typical"
	vendor, ahNet, best = ns.ItemAdvice(5, 1)
	eq(ahNet, 190); eq(best, "auction")
end)

------------------------------------------------------------------------------ item tooltip advice

it("item tooltip advice: AH figure at the profit house with its price label and cut source", function()
	local ns, stub = Load({ auctionator = true })
	stub.items[5] = { name = "Linen", sellPrice = 10 }
	stub.items[6] = { name = "Other", sellPrice = 10 }
	Seed(5, HORDE, { typs = { 200, 200, 200 }, tiers = { 150, 10 }, total = 10 })
	local t = TooltipText(ns, 5)
	has(t, "  AH price | typical · Horde AH")
	has(t, "5% cut (confirmed)")
	ns.db.settings.priceHouse = "BootyBay"
	Seed(5, BOOTY, { tiers = { 300, 10 }, total = 10 })
	t = TooltipText(ns, 5)
	has(t, "  AH price | current lowest, too little history · Booty Bay")
	has(t, "gross ")
	has(t, "cut unverified")
	has(t, "AH ? ")
	ns.db.settings.priceHouse = "faction"
	stub.ah[6] = 500
	t = TooltipText(ns, 6)
	has(t, "  AH price | Auctionator (house unknown)")
	has(t, "5% cut (house unknown)")
	CraftWiseMarketDB.houses[HORDE].cut = { rate = 0.08, samples = 5 }
	has(TooltipText(ns, 5), "8% cut measured (5 sales), differs from 5% confirmed")
	stub.items[7] = { name = "Unpriced", sellPrice = 10 }
	has(TooltipText(ns, 7), "  AH price | no price data")
end)

---------------------------------------------------------------------------------- AH learn cost

it("AH learn cost reads the profit house and basis", function()
	local ns, stub = Load({ auctionator = true })
	ns.SourceData = { [9001] = { item = 555 }, [9002] = { item = 556 } }
	Seed(555, HORDE, { typs = { 400, 400, 400 }, tiers = { 350, 2 }, total = 2 })
	stub.ah[556] = 900
	local cost, source, label = ns.LearnCost(9001)
	eq(cost, 400); eq(source, "auction"); eq(label, "typical · Horde AH")
	ns.db.settings.priceBasis = "current"
	cost, source, label = ns.LearnCost(9001)
	eq(cost, 350); eq(label, "current lowest · Horde AH")
	cost, source, label = ns.LearnCost(9002)
	eq(cost, 900); eq(label, "Auctionator (house unknown)")
	stub.DisableAuctionator()
	eq(ns.LearnCost(9002), nil, "no price data")
	local where
	for _, w in ipairs(ns.RecipeWhere(9001)) do
		if w.kind == "auction" then where = w end
	end
	eq(where.label, "current lowest · Horde AH")
end)

----------------------------------------------------------------------------------- disenchant value

it("disenchant value prices each material at the profit house after its cut", function()
	local ns, stub = Load({ auctionator = true })
	ns.DisenchantData = { Lookup = function() return { { itemID = 7, chance = 0.5, quantity = 2 }, { itemID = 8, chance = 1, quantity = 1 } } end }
	Seed(7, HORDE, { typs = { 100, 100, 100 }, tiers = { 60, 10 }, total = 10 })
	stub.ah[8] = 40
	local value, details = ns.DisenchantValue(1, 2)
	eq(value, 100 * 0.95 * 0.5 * 2 + 40 * 0.95)
	eq(#details.labels, 2); eq(details.labels[1], "typical · Horde AH"); eq(details.labels[2], "Auctionator (house unknown)")
	eq(details.cutTexts[1], "5% cut (confirmed)")
	ns.db.settings.priceBasis = "current"
	eq((ns.DisenchantValue(1, 2)), 60 * 0.95 + 40 * 0.95)
	ns.db.settings.priceBasis = "typical"
	ns.db.settings.priceHouse = "BootyBay"
	Seed(7, BOOTY, { tiers = { 80, 10 }, total = 10 })
	eq(ns.DisenchantValue(1, 2), nil, "a material at a house with an unverified cut: no value, never understated")
	ns.db.settings.priceHouse = "faction"
	stub.DisableAuctionator()
	eq(ns.DisenchantValue(1, 2), nil, "a material without a price")
	-- Through the Bags view.
	stub.items[10] = { name = "Green Sword", sellPrice = 1 }
	stub.itemClass[10] = 2
	Bags(stub, { { itemID = 10, stackCount = 1, quality = 2 } })
	stub.EnableAuctionator()
	stub.ah[8] = 40
	local r = BagRow(ns, 10)
	eq(r.deValue, 100 * 0.95 * 0.5 * 2 + 40 * 0.95); eq(r.deDetails.labels[1], "typical · Horde AH")
end)

----------------------------------------------------------------------------- profit rows and level

it("Craft rows and the level sale carry the cut source", function()
	local ns, stub = Load()
	stub.items[2318] = { name = "Light Leather", stack = 20 }
	stub.items[4246] = { name = "Belt", sellPrice = 1 }
	stub.profession = { id = 165, name = "Leatherworking", skill = 60, max = 75, recipes = {
		[3763] = { info = { name = "Belt", learned = true }, schematic = stub.Schematic({ { 2318, 2 } }, 4246) } } }
	stub.Fire("TRADE_SKILL_SHOW")
	ns.db.settings.priceBasis = "current"
	Seed(2318, HORDE, { tiers = { 30, 100 }, total = 100 })
	Seed(4246, HORDE, { tiers = { 1000, 3 }, total = 3 })
	local row = ns.BuildRows(165, false)[1]
	eq(row.sellCutText, "5% cut (confirmed)")
	local _, _, details = ns.Leveling.Sale({ itemID = 4246, quantity = 1 })
	eq(details.cutText, "5% cut (confirmed)")
	CraftWiseMarketDB.houses[HORDE].cut = { rate = 0.1, samples = 2 }
	row = ns.BuildRows(165, false)[1]
	eq(row.sellCutText, "10% cut measured (2 sales), differs from 5% confirmed"); eq(row.sellCutDiffers, true)
	eq(row.sellsFor, 900)
	-- The row tooltip shows it.
	local lines = {}
	GameTooltip.AddLine = function(_, t) lines[#lines + 1] = t end
	GameTooltip.AddDoubleLine = function(_, l, r) lines[#lines + 1] = l .. " | " .. r end
	Make.Open(ns, "craft", 165) -- Make › Craft (#154)
	assert(Make.Hover(ns, "craft", 3763), "belt row")
	has(table.concat(lines, "\n"), "10% cut measured (2 sales), differs from 5% confirmed")
	CraftWiseMarketDB.houses[HORDE].cut = { samples = 0 }
	lines = {}
	ns.Main.Refresh()
	assert(Make.Hover(ns, "craft", 3763), "belt row")
	has(table.concat(lines, "\n"), "5% cut (confirmed)")
end)
