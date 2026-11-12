-- Issue #48: Make › Craft's "cost → sells" (the profit view's "Sells for" before #154) shows a source tag (vendor / AH) and the recipe tooltip
-- always lists both sale options, the chosen one marked.
local NOW = 1794000000
local DAY = 86400
local HORDE, BOOTY = "PvP|H", "PvP|N:BootyBay"
local HOUSES = {
	[HORDE] = { realm = "PvP", kind = "faction", faction = "Horde", label = "Horde AH" },
	[BOOTY] = { realm = "PvP", kind = "neutral", label = "Booty Bay" },
}
local PANTS, LEATHER = 4239, 2318 -- output and reagent ids used only as keys here

local function Load(opts)
	local ns, stub = LoadAddon(opts)
	stub.clock = NOW
	time = function() return stub.clock end
	return ns, stub
end

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

local function Plain(text)
	text = text:gsub("|T[^|]*UI%-GoldIcon[^|]*|t", "g"):gsub("|T[^|]*UI%-SilverIcon[^|]*|t", "s"):gsub("|T[^|]*UI%-CopperIcon[^|]*|t", "c")
	return (text:gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- One known recipe: 2 reagents -> `quantity` pants.
local function Profession(stub, quantity)
	stub.profession = { id = 165, name = "Leatherworking", skill = 60, max = 75, recipes = {
		[3759] = { info = { name = "Light Leather Pants", learned = true }, schematic = stub.Schematic({ { LEATHER, 2 } }, PANTS, quantity) } } }
	stub.Fire("TRADE_SKILL_SHOW")
end

local function Row(ns)
	return ns.BuildRows(165, false)[1]
end

local Make = dofile("tests/make_helpers.lua")

local function Lines(ns, r)
	local out = {}
	for i, l in ipairs(ns.Main.Make.SaleOptionLines(r)) do
		out[i] = { Plain(l[1]), Plain(l[2]), l[3] }
	end
	return out
end

-- What Make › Craft's "cost → sells" caption says after the arrow for the first row (#154).
local function SellsForCell(ns)
	Make.Open(ns, "craft", 165)
	local r = Make.Rows(ns, "craft")[1]
	return r and Plain(r.view.sellsText)
end

it("sale tag: vendor, AH, AH gross when the cut is unverified, nothing without a sale", function()
	local ns = Load()
	local MK = ns.Main.Make
	eq(MK.SaleTag("vendor"), "vendor")
	eq(MK.SaleTag("auction"), "AH")
	eq(MK.SaleTag("auction", true), "AH gross")
	eq(MK.SaleTag(nil), nil)
end)

it("vendor wins: row tagged vendor, tooltip shows both with vendor marked (Light Leather Pants 5s99)", function()
	local ns, stub = Load()
	Profession(stub, 1)
	stub.items[PANTS] = { name = "Light Leather Pants", sellPrice = 599 }
	Seed(PANTS, HORDE, { typs = { 600, 600, 600 }, tiers = { 600, 5 }, total = 5 })
	local r = Row(ns)
	eq(r.sellSource, "vendor"); eq(r.sellsFor, 599)
	local o = ns.SaleOptions(PANTS, 1)
	eq(o.chosen, "vendor"); eq(o.vendor, 599); eq(o.auction.gross, 600); eq(o.auction.net, 570)
	local lines = Lines(ns, r)
	eq(lines[1][1], "  Vendor (used)"); eq(lines[1][2], "5s 99c (no cut)"); eq(lines[1][3], true)
	eq(lines[2][1], "  AH net"); eq(lines[2][3], false)
	eq(lines[2][2], "5s 70c (gross 6s, 5% cut (confirmed), typical · Horde AH)")
	eq(SellsForCell(ns, stub), "5s 99c vendor")
end)

it("AH wins: row tagged AH, both lines, AH marked; quantities follow the recipe's output count", function()
	local ns, stub = Load()
	Profession(stub, 2)
	stub.items[PANTS] = { name = "Light Leather Pants", sellPrice = 599 }
	Seed(PANTS, HORDE, { typs = { 2000, 2000, 2000 }, tiers = { 2000, 5 }, total = 5 })
	local r = Row(ns)
	eq(r.sellSource, "auction"); eq(r.sellsFor, 3800); eq(r.outputQuantity, 2)
	local lines = Lines(ns, r)
	eq(lines[1][1], "  Vendor"); eq(lines[1][2], "11s 98c (no cut)"); eq(lines[1][3], false)
	eq(lines[2][1], "  AH net (used)"); eq(lines[2][3], true)
	eq(lines[2][2], "38s (gross 40s, 5% cut (confirmed), typical · Horde AH)")
	eq(SellsForCell(ns, stub), "38s AH")
end)

it("unverified cut: AH line shows the gross and says cut unverified; tag says AH gross", function()
	local ns, stub = Load()
	Profession(stub, 1)
	ns.db.settings.priceHouse = "BootyBay"
	stub.items[PANTS] = { name = "Light Leather Pants", sellPrice = 599 }
	Seed(PANTS, BOOTY, { tiers = { 1500, 3 }, total = 3 })
	local r = Row(ns)
	eq(r.sellSource, "auction"); eq(r.cutUnverified, true)
	local lines = Lines(ns, r)
	eq(lines[1][2], "5s 99c (no cut)"); eq(lines[1][3], false)
	eq(lines[2][1], "  AH (used)"); eq(lines[2][2], "gross 15s, cut unverified, current lowest, too little history · Booty Bay")
	eq(SellsForCell(ns, stub), "15s AH gross")
end)

it("missing values stay missing: no AH data, vendor price not loaded or zero", function()
	local ns, stub = Load()
	Profession(stub, 1)
	stub.items[PANTS] = { name = "Light Leather Pants", sellPrice = 0 }
	local r = Row(ns)
	eq(r.sellsFor, nil)
	local lines = Lines(ns, r)
	eq(lines[1][2], "vendors don't buy it"); eq(lines[2][2], "no price data")
	eq(lines[1][3], false); eq(lines[2][3], false)
	stub.items[PANTS] = nil
	-- The price the client returned earlier is kept (#83); never seen at all, it stays missing.
	eq(Lines(ns, Row(ns))[1][2], "vendors don't buy it")
	ns.db.sellPrices[PANTS] = nil
	eq(Lines(ns, Row(ns))[1][2], "sell price not loaded yet")
end)

it("the recipe tooltip renders the sale options", function()
	local ns, stub = Load()
	Profession(stub, 1)
	stub.items[PANTS] = { name = "Light Leather Pants", sellPrice = 599 }
	Seed(PANTS, HORDE, { typs = { 600, 600, 600 }, tiers = { 600, 5 }, total = 5 })
	local seen = {}
	local add = GameTooltip.AddDoubleLine
	GameTooltip.AddDoubleLine = function(self, l, r, ...)
		seen[#seen + 1] = Plain(l) .. " | " .. Plain(r)
		return add(self, l, r, ...)
	end
	Make.Open(ns, "craft", 165)
	assert(Make.Hover(ns, "craft", 3759), "pants row shown")
	GameTooltip.AddDoubleLine = add
	local text = table.concat(seen, "\n")
	assert(text:find("Sells for | 5s 99c  vendor", 1, true), text)
	assert(text:find("  Vendor (used) | 5s 99c (no cut)", 1, true), text)
	assert(text:find("  AH net | 5s 70c (gross 6s", 1, true), text)
end)
