-- Fixtures for the companion's Go packages (#93), written by the addon's own Lua code.
--
--   lua5.1 tests/companion_fixtures.lua     (repo root) rewrites both files below
--
-- 1. companion/market/testdata/golden.lua: entries packed by Market.lua's EncodeEntry and unpacked by
--    its DecodeEntry (hand-made edge cases and seeded random entries), item info (EncodeItemInfo,
--    ItemInfo, #92) and Auctionator prices (ExportAuctionator, AuctionatorExport, #90). The Go port
--    must produce the same strings and the same values. tests/companion_fixtures_spec.lua (in tests/run.lua) fails when
--    Market.lua's format changes and this file wasn't regenerated.
-- 2. companion/savedvars/testdata/CraftWise.lua: a synthetic SavedVariables file (stub items, stub
--    realm, no game data) made by running the addon headless: full scans at two houses on three days,
--    a browse list, a commodity search, Auctionator prices, ledger trades, two auctions, a fishing log,
--    a character with gear, quests, reputations, a pet and flight paths, then logout (names, item
--    info, packing, snapshot). Only the tables the companion reads are written. It is
--    not checked by the spec, so changes elsewhere in the addon don't force a regeneration; rerun this
--    script when one of those tables changes shape.
--
-- Written as the game writes SavedVariables: tab per depth, ["key"] = value, list items with -- [n].
-- Keys are sorted so the output only changes when the data does.
local G = {}

G.GOLDEN = "companion/market/testdata/golden.lua"
G.SAVED = "companion/savedvars/testdata/CraftWise.lua"

local NOW = 1794000000 -- 2026-11-06 (UTC); every time in the fixtures is relative to it
local DAY = 86400

----------------------------------------------------------------------------------------------------
-- Writer
----------------------------------------------------------------------------------------------------

local function Quote(s)
	return '"' .. s:gsub('[%c"\\]', function(c)
		if c == "\n" then
			return "\\n"
		elseif c == "\r" then
			return "\\r"
		elseif c == '"' or c == "\\" then
			return "\\" .. c
		end
		return ("\\%03d"):format(c:byte())
	end) .. '"'
end

local function Number(n)
	if n == math.floor(n) and math.abs(n) < 2 ^ 53 then
		return ("%d"):format(n)
	end
	for digits = 14, 17 do -- the shortest text that reads back as the same number
		local text = ("%." .. digits .. "g"):format(n)
		if tonumber(text) == n then
			return text
		end
	end
	return ("%.17g"):format(n)
end

local function Scalar(v)
	if type(v) == "string" then
		return Quote(v)
	elseif type(v) == "number" then
		return Number(v)
	end
	return tostring(v)
end

local function SortedKeys(t, n)
	local keys = {}
	for k in pairs(t) do
		if not (type(k) == "number" and k >= 1 and k <= n and k == math.floor(k)) then
			keys[#keys + 1] = k
		end
	end
	table.sort(keys, function(a, b)
		if type(a) ~= type(b) then
			return type(a) == "number"
		end
		return a < b
	end)
	return keys
end

local function Write(v, indent, out)
	if type(v) ~= "table" then
		out[#out + 1] = Scalar(v)
		return
	end
	out[#out + 1] = "{\n"
	local n = #v
	for i = 1, n do
		out[#out + 1] = indent .. "\t"
		Write(v[i], indent .. "\t", out)
		out[#out + 1] = ", -- [" .. i .. "]\n"
	end
	for _, k in ipairs(SortedKeys(v, n)) do
		out[#out + 1] = indent .. "\t[" .. Scalar(k) .. "] = "
		Write(v[k], indent .. "\t", out)
		out[#out + 1] = ",\n"
	end
	out[#out + 1] = indent .. "}"
end

-- "Name = value" lines for { { name, value }, ... }, with a header comment.
function G.SavedVariablesText(header, globals)
	local out = { "-- " .. header .. "\n" }
	for _, g in ipairs(globals) do
		out[#out + 1] = g[1] .. " = "
		Write(g[2], "", out)
		out[#out + 1] = "\n"
	end
	return table.concat(out)
end

----------------------------------------------------------------------------------------------------
-- 1. Golden entries
----------------------------------------------------------------------------------------------------

-- Seeded generator (Lua's math.random differs between platforms).
local function Rand(seed)
	local state = seed
	return function(lo, hi)
		state = (state * 1103515245 + 12345) % 2147483648
		return lo + state % (hi - lo + 1)
	end
end

local function Maybe(rand, value)
	if rand(1, 5) == 1 then
		return nil
	end
	return value
end

local function RandomEntry(rand)
	local e = { raw = {}, days = {} }
	if rand(1, 6) > 1 then
		e.last = { t = Maybe(rand, NOW - rand(0, 30 * DAY)), min = Maybe(rand, rand(1, 2000000000)),
			qty = Maybe(rand, rand(1, 100000)), listings = Maybe(rand, rand(1, 500)) }
		if rand(1, 3) == 1 then
			e.last.off = rand(0, 3) == 0 and 0 or NOW - rand(0, DAY)
		end
	end
	local t = NOW - 2 * DAY
	for _ = 1, rand(0, 4) do
		t = t + rand(-600, 20000) -- a clock step back gives a negative delta
		local p = { t = t, total = Maybe(rand, rand(0, 50000)), listings = Maybe(rand, rand(0, 300)),
			m = rand(1, 3) == 1 and rand(1, 900000) or nil, tiers = {} }
		local price = rand(1, 5000)
		for _ = 1, rand(0, 8) do
			p.tiers[#p.tiers + 1] = price
			p.tiers[#p.tiers + 1] = rand(1, 2000)
			price = price + rand(0, 100000)
		end
		e.raw[#e.raw + 1] = p
	end
	local day = math.floor(NOW / DAY) - 30
	for _ = 1, rand(0, 6) do
		day = day + rand(1, 5)
		local lo = Maybe(rand, rand(1, 1000000))
		e.days[day] = { lo = lo, typ = Maybe(rand, (lo or 0) + rand(-5000, 300000)), hi = Maybe(rand, (lo or 0) + rand(-10, 900000)),
			qtyMax = Maybe(rand, rand(0, 9000)), listMax = Maybe(rand, rand(0, 400)), n = Maybe(rand, rand(1, 40)),
			gone = rand(1, 3) == 1 and rand(0, 500) or nil }
	end
	return e
end

local function Cases()
	local cases = {
		{ "empty entry", { raw = {}, days = {} } },
		{ "last only, from a full scan", { last = { t = NOW, min = 80, qty = 26, listings = 3 }, raw = {}, days = {} } },
		{ "last only, browse row without listings", { last = { t = NOW, min = 1234567, qty = 1 } } },
		{ "last only, off the market since a later scan", { last = { t = NOW - DAY, min = 99, qty = 2, listings = 1, off = NOW } } },
		{ "last with off = 0", { last = { t = NOW, min = 5, qty = 5, listings = 5, off = 0 } } },
		{ "last with only a price", { last = { min = 42 } } },
		{ "zero values", { last = { t = 0, min = 0, qty = 0, listings = 0 },
			raw = { { t = 0, total = 0, listings = 0, tiers = {} } } } },
		{ "negative numbers are written as 0", { last = { t = NOW, min = -5, qty = -1, listings = -9 },
			raw = { { t = NOW, total = -3, listings = -2, m = -1, tiers = { 10, -4 } } } } },
		{ "history without last", { raw = { { t = NOW, total = 10, listings = 2, tiers = { 100, 4, 120, 6 } } } } },
		{ "full point: 8 tiers and the cheapest-15% median", { last = { t = NOW, min = 100, qty = 500, listings = 40 },
			raw = { { t = NOW, total = 500, listings = 40, m = 150,
				tiers = { 100, 1, 110, 2, 120, 3, 130, 4, 140, 5, 150, 6, 160, 7, 170, 8 } } } } },
		{ "points out of order in time and price", { raw = {
			{ t = NOW, total = 5, listings = 1, tiers = { 500, 5 } },
			{ t = NOW - 3600, total = 7, listings = 2, tiers = { 900, 1, 300, 6 } },
			{ t = NOW + 60, total = 0, listings = 0, tiers = {} } } } },
		{ "day aggregates with typ and hi below lo", { days = {
			[20700] = { lo = 1000, typ = 900, hi = 800, qtyMax = 10, listMax = 2, n = 3, gone = 4 },
			[20701] = { lo = 1000, typ = 1000, hi = 5000, qtyMax = 0, listMax = 0, n = 1, gone = 0 },
			[20690] = { typ = 70, hi = 90, n = 2 },
			[20705] = {} } } },
		{ "big numbers", { last = { t = 4102444800, min = 99999999999, qty = 2147483647, listings = 65535 },
			days = { [47482] = { lo = 99999999999, typ = 99999999998, hi = 199999999999, qtyMax = 2147483647, n = 1 } } } },
	}
	local rand = Rand(93)
	for i = 1, 80 do
		cases[#cases + 1] = { ("random %d"):format(i), RandomEntry(rand) }
	end
	return cases
end

-- Item info (#92): { name, info given to EncodeItemInfo, time }.
local ITEM_INFO_CASES = {
	{ "everything known", { q = 1, i = 134190, c = 7, s = 9 }, 1792115136 },
	{ "no icon", { q = 1, c = 7, s = 9 }, 1792115136 },
	{ "quality only", { q = 4 }, NOW },
	{ "zeros", { q = 0, i = 0, c = 0, s = 0 }, 0 },
	{ "negative fields stay unknown", { q = 2, i = -1, c = -5, s = 3 }, NOW },
	{ "big icon ID", { q = 3, i = 4294967295, c = 15, s = 0 }, NOW + 1 },
	{ "no time", { q = 1, i = 1, c = 2, s = 3 } },
}

-- Auctionator prices (#90): { name, copper, age, time read }.
local AUCTIONATOR_CASES = {
	{ "with age", 12345, 3, NOW },
	{ "age unknown", 7, nil, NOW - DAY },
	{ "age 0", 999999999, 0, NOW },
	{ "copper with a fraction is floored", 150.75, 2.9, NOW },
}

-- The golden file's text. M = ns.Market of a loaded addon (its CraftWiseMarketDB is used as scratch).
function G.Golden(M)
	local entries = {}
	for _, case in ipairs(Cases()) do
		local packed = M.EncodeEntry(case[2])
		entries[#entries + 1] = { name = case[1], input = case[2], packed = packed, decoded = M.DecodeEntry(packed) }
	end
	local db = CraftWiseMarketDB
	local itemInfo = {}
	for i, case in ipairs(ITEM_INFO_CASES) do
		local packed = M.EncodeItemInfo(case[2], case[3])
		db.itemInfo[i] = packed
		local decoded = M.ItemInfo(i)
		itemInfo[#itemInfo + 1] = { name = case[1], input = case[2], t = case[3], packed = packed,
			decoded = { q = decoded.q, i = decoded.i, c = decoded.c, s = decoded.s, t = decoded.t } }
	end
	local auctionator = {}
	local realTime = time
	for i, case in ipairs(AUCTIONATOR_CASES) do
		time = function() return case[4] end
		M.ExportAuctionator(i, case[2], case[3])
		local decoded = M.AuctionatorExport(i)
		auctionator[#auctionator + 1] = { name = case[1], copper = case[2], age = case[3], t = case[4],
			packed = db.auctionator.items[i], decoded = { t = decoded.t, copper = decoded.copper, age = decoded.age } }
	end
	time = realTime
	return G.SavedVariablesText("Generated by tests/companion_fixtures.lua from CraftWise/Market.lua (EncodeEntry, DecodeEntry, "
		.. "EncodeItemInfo, ItemInfo, ExportAuctionator, AuctionatorExport). Do not edit.",
		{ { "CraftWiseMarketGolden", entries }, { "CraftWiseItemInfoGolden", itemInfo }, { "CraftWiseAuctionatorGolden", auctionator } })
end

----------------------------------------------------------------------------------------------------
-- 2. Synthetic SavedVariables
----------------------------------------------------------------------------------------------------

-- Unix time of a UTC date table, so the ledger's day keys don't depend on the machine's time zone.
local function TimeUTC(t)
	local y, m = t.year, t.month
	if m <= 2 then
		y, m = y - 1, m + 12
	end
	local days = 365 * y + math.floor(y / 4) - math.floor(y / 100) + math.floor(y / 400) + math.floor((153 * (m - 3) + 2) / 5) + t.day - 719469
	return days * DAY + (t.hour or 12) * 3600 + (t.min or 0) * 60 + (t.sec or 0)
end

-- Stub items (IDs and names are made up, not game data).
local CLOTH, HIDE, ORE, POTION, GEAR, GEM, FISH, OIL, RECIPE = 9001, 9002, 9003, 9004, 9005, 9006, 9007, 9008, 9009
local ITEMS = {
	[CLOTH] = { name = "Test Cloth", sellPrice = 13, stack = 200, quality = 1, icon = 100001 },
	[HIDE] = { name = "Test Hide", sellPrice = 50, stack = 200, quality = 1, icon = 100002 },
	[ORE] = { name = "Test Ore", sellPrice = 5, stack = 200 },
	[POTION] = { name = "Test Potion", sellPrice = 25, stack = 20 },
	[GEAR] = { name = "Test Boots of the Owl", sellPrice = 300, stack = 1, quality = 2, icon = 100005 },
	[GEM] = { name = "Test \"Quoted\" Gem", sellPrice = 900, stack = 20 },
	[FISH] = { name = "Test Fish", sellPrice = 6, stack = 20 },
	[OIL] = { name = "Test Oil", sellPrice = 20, stack = 20 },
	[RECIPE] = { name = "Test Recipe", sellPrice = 100, stack = 1 },
}

local function Link(id, suffix)
	return ("|cffffffff|Hitem:%d::::::%s::20:::::::::|h[%s]|h|r"):format(id, suffix and tostring(suffix) or "", ITEMS[id].name)
end

local function Rows(list)
	local out = {}
	for _, r in ipairs(list) do
		out[#out + 1] = { itemID = r[1], count = r[2], buyout = r[3], link = Link(r[1], r[4]), owner = "Seller",
			name = ITEMS[r[1]].name }
	end
	return out
end

local function Scan(stub, zone, rows)
	stub.zone, stub.subzone = zone, ""
	stub.Fire("AUCTION_HOUSE_SHOW")
	stub.replicate = Rows(rows)
	stub.Fire("REPLICATE_ITEM_LIST_UPDATE")
	stub.RunTimers()
end

local function Close(stub)
	stub.Fire("AUCTION_HOUSE_CLOSED")
	stub.RunTimers()
end

-- The client APIs the snapshot reads that the shared stub doesn't have (as tests/snapshot_spec.lua
-- stubs them): race, class, XP, guild, map and position, gear, quest log, reputations, hunter pet,
-- a flight master map. Names and IDs are made up.
local function SnapshotClient(stub)
	function UnitRace() return "Orc", "Orc", 2 end
	function UnitClass() return "Hunter", "HUNTER", 3 end
	function UnitXP() return 12000 end
	function UnitXPMax() return 18600 end
	function GetXPExhaustion() return 4200 end
	function IsInGuild() return true end
	function GetGuildInfo() return "Test Guild", "Member", 3 end
	function IsResting() return true end
	C_Map = {
		GetBestMapForUnit = function() return 1411 end,
		GetMapInfo = function(id) return { mapID = id, name = ({ [1411] = "Test Map", [1414] = "Test Continent" })[id] } end,
		GetPlayerMapPosition = function() return { x = 0.523456, y = 0.30111 } end,
	}
	stub.items[GEAR].stats = { RESISTANCE0_NAME = 35, ITEM_MOD_INTELLECT_SHORT = 3, ITEM_MOD_SPIRIT_SHORT = 3 }
	stub.items[GEAR].level = 18
	stub.equipped.FEETSLOT = GEAR
	function GetInventoryItemLink(_, slot)
		local id = GetInventoryItemID("player", slot)
		return id and Link(id, 1234)
	end
	function GetInventoryItemDurability(slot)
		if slot == 8 then return 31, 40 end
	end
	local quests = {
		{ title = "Test Zone", isHeader = true },
		{ questID = 901, title = "Test Quest", level = 20, objectives = {
			{ text = "Test Hides: 2/6", numFulfilled = 2, numRequired = 6, finished = false } } },
		{ questID = 902, title = "Test Group Quest", level = 22, suggestedGroup = 3, complete = true, objectives = {} },
		{ title = "Collapsed Zone", isHeader = true, isCollapsed = true },
	}
	C_QuestLog = {
		GetNumQuestLogEntries = function() return #quests, 3 end,
		GetInfo = function(i)
			local q = quests[i]
			return q and { title = q.title, questID = q.questID, level = q.level, suggestedGroup = q.suggestedGroup or 0,
				isHeader = q.isHeader or false, isCollapsed = q.isCollapsed or false, isHidden = false }
		end,
		IsComplete = function(id) return id == 902 end,
		IsFailed = function() return false end,
		GetQuestObjectives = function(id)
			for _, q in ipairs(quests) do
				if q.questID == id then return q.objectives end
			end
		end,
	}
	local factions = {
		{ factionID = 0, name = "Test Header", isHeader = true, isCollapsed = false },
		{ factionID = 9101, name = "Test Faction", reaction = 6, currentStanding = 9500, currentReactionThreshold = 9000,
			nextReactionThreshold = 21000, isHeader = false, atWarWith = false },
		{ factionID = 9102, name = "Test Rivals", reaction = 2, currentStanding = -5000, currentReactionThreshold = -6000,
			nextReactionThreshold = -3000, isHeader = false, atWarWith = true },
	}
	C_Reputation = {
		GetNumFactions = function() return #factions end,
		GetFactionDataByIndex = function(i) return factions[i] end,
	}
	for i, label in ipairs({ "Hated", "Hostile", "Unfriendly", "Neutral", "Friendly", "Honored", "Revered", "Exalted" }) do
		_G["FACTION_STANDING_LABEL" .. i] = label
	end
	stub.names.pet = "Test Wolf"
	function HasPetUI() return true, true end
	function UnitCreatureFamily() return "Wolf", 1 end
	C_PetInfo = { GetPetHappiness = function() return 3, 125, 20 end, GetPetLoyalty = function() return "Loyalty Level 3" end }
	local function node(id, name, x, y, state)
		return { nodeID = id, name = name, state = state, slotIndex = id, textureKit = "", useSpecialIcon = false,
			isMapLayerTransition = false, position = { x = x, y = y, GetXY = function(self) return self.x, self.y end } }
	end
	function GetTaxiMapID() return 1414 end
	C_TaxiMap = {
		GetAllTaxiNodes = function() return { node(1, "Test Town", 0.5165, 0.5512, 0), node(2, "Test Port", 0.5531, 0.3634, 1) } end,
		GetTaxiNodesForMap = function()
			return { { nodeID = 1, name = "Test Town", isUndiscovered = false }, { nodeID = 2, name = "Test Port", isUndiscovered = false } }
		end,
	}
	stub.Fire("TAXIMAP_OPENED", 1)
	stub.bags[0] = { { itemID = CLOTH, stackCount = 40 }, { itemID = HIDE, stackCount = 5 } }
	stub.profession = { id = 165, name = "Leatherworking", skill = 120, max = 150, recipes = {
		[1] = { info = { name = "Test Armor Kit", learned = true }, schematic = stub.Schematic({ { HIDE, 1 } }, POTION) },
	} }
	stub.Fire("TRADE_SKILL_SHOW")
end

-- Loads the addon (loadAddon = run.lua's LoadAddon), plays the scenario, returns the file's text.
function G.SavedVariables(loadAddon)
	local ns, stub = loadAddon({ auctionator = true })
	stub.clock = NOW - 2 * DAY
	time = function(t)
		if t then
			return TimeUTC(t)
		end
		return stub.clock
	end
	date = function(fmt, t)
		return os.date("!" .. fmt, t)
	end
	stub.realm, stub.faction = "Stub Realm", "Horde"
	stub.names.player, stub.surnames.player = "Veli", "Tanner"
	stub.level, stub.money = 23, 250000
	for id, item in pairs(ITEMS) do
		stub.items[id] = { name = item.name, sellPrice = item.sellPrice, stack = item.stack, quality = item.quality, icon = item.icon }
	end
	stub.itemClass[GEAR] = 4 -- armour: rows are read with their link (random suffix)
	stub.itemClass[CLOTH], stub.itemSubclass[CLOTH] = 7, 5
	stub.itemSubclass[GEAR] = 2
	stub.counts = { [CLOTH] = 40, [HIDE] = 5 }
	stub.deposit = 60
	ERR_AUCTION_SOLD_S = "A buyer has been found for your auction of %s."
	ERR_AUCTION_EXPIRED_S = "Your auction of %s has expired."
	AUCTION_DURATION_ONE, AUCTION_DURATION_TWO, AUCTION_DURATION_THREE = "12 Hours", "24 Hours", "48 Hours"
	stub.Fire("PLAYER_LOGIN")
	stub.Fire("PLAYER_ENTERING_WORLD", true, false)
	for _, id in ipairs({ CLOTH, HIDE, POTION }) do
		CraftWiseMarketDB.scope.items[id] = true
	end

	-- Day 1: full scan at the faction house. Cloth has more than 8 price levels.
	local clothRows = {}
	for i = 1, 11 do
		clothRows[#clothRows + 1] = { CLOTH, i * 3, (100 + i * 7) * i * 3 }
	end
	local day1 = { { HIDE, 20, 6000 }, { HIDE, 5, 1600 }, { POTION, 5, 25000 }, { ORE, 20, 1000 }, { ORE, 10, 600 },
		{ GEAR, 1, 150000, 1234 }, { GEAR, 1, 99000, 1234 }, { GEAR, 1, 80000, 5678 }, { GEM, 2, 30000 } }
	for _, r in ipairs(day1) do
		clothRows[#clothRows + 1] = r
	end
	Scan(stub, "Orgrimmar", clothRows)
	-- A commodity search for the potion and a browse list while the AH is open.
	stub.commodity[POTION] = { rows = { { unitPrice = 4800, quantity = 3 }, { unitPrice = 5100, quantity = 9 } }, total = 12, full = true }
	stub.clock = stub.clock + 120
	stub.Fire("COMMODITY_SEARCH_RESULTS_UPDATED", POTION)
	stub.RunTimers()
	stub.browse = { { itemKey = { itemID = OIL }, totalQuantity = 7, minPrice = 345 } }
	stub.Fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
	Close(stub)

	-- Day 2: Booty Bay, then the faction house again without the ore and the gem.
	stub.clock = stub.clock + DAY
	Scan(stub, "Booty Bay", { { CLOTH, 20, 3000 }, { HIDE, 2, 900 }, { ORE, 5, 400 } })
	Close(stub)
	stub.clock = stub.clock + 3600
	Scan(stub, "Orgrimmar", { { CLOTH, 10, 1300 }, { CLOTH, 30, 4200 }, { HIDE, 15, 4800 }, { GEAR, 1, 95000, 1234 } })
	-- An auction posted and one item auction that sells.
	C_AuctionHouse.PostCommodity({ itemID = HIDE, link = Link(HIDE) }, 2, 5, 330)
	stub.Fire("AUCTION_HOUSE_AUCTION_CREATED", 7001)
	C_AuctionHouse.PostItem({ itemID = POTION, link = Link(POTION) }, 1, 1, nil, 5500)
	stub.Fire("AUCTION_HOUSE_AUCTION_CREATED", 7002)
	Close(stub)
	stub.clock = stub.clock + 1800
	stub.Fire("AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION", Enum.AuctionHouseNotification.AuctionSold, ITEMS[POTION].name, 7002)

	-- Ledger: vendor and AH trades.
	ns.Ledger.Record("vbuy", OIL, 4, 120, "Test Vendor")
	ns.Ledger.Record("ahbuy", HIDE, 5, 1500, "Stub Realm|H")
	ns.Ledger.Record("vsell", ORE, 10, 50, "Test Vendor")

	-- Day 3: the faction house once more; Auctionator prices for items without one.
	stub.clock = stub.clock + DAY
	Scan(stub, "Orgrimmar", { { CLOTH, 12, 1400 }, { HIDE, 10, 3100 }, { POTION, 4, 19600 } })
	Close(stub)
	ns.Market.ExportAuctionator(FISH, 7, 2)
	ns.Market.ExportAuctionator(RECIPE, 25000, nil)

	-- A fishing log: open water and one pool, minutes apart.
	local key = ns.CharKey()
	local log = ns.Fishing.Log(key)
	local t = stub.clock - 3000
	for i = 1, 6 do
		local pool = i > 3
		log.catches[#log.catches + 1] = { t = t + i * 40, zone = "Test Zone", sub = pool and "Test Cove" or "", map = 1,
			x = 25.4, y = 60.1, obj = pool and 6001 or 5001, spawn = pool and "0000AB" or ("00000" .. i),
			clk = pool and "GameObject-0-1-2-3-5001-0000FF" or nil, same = not pool or nil, items = { [FISH] = 1, [OIL] = i % 2 } }
	end

	SnapshotClient(stub)
	stub.clock = stub.clock + 600
	stub.Fire("PLAYER_LOGOUT")

	local m = CraftWiseMarketDB
	local market = { v = m.v, houses = m.houses, scans = m.scans, items = m.items, names = m.names, itemInfo = m.itemInfo,
		auctionator = m.auctionator,
		ledger = m.ledger, auctions = m.auctions, cutSamples = m.cutSamples, scope = m.scope, prunedAt = m.prunedAt }
	return G.SavedVariablesText("Synthetic SavedVariables generated by tests/companion_fixtures.lua (stub items and realm, no game data). Do not edit.",
		{ { "CraftWiseDB", { snapshots = CraftWiseDB.snapshots } }, { "CraftWiseMarketDB", market } })
end

----------------------------------------------------------------------------------------------------
-- Command line: lua5.1 tests/companion_fixtures.lua
----------------------------------------------------------------------------------------------------

local function Standalone()
	package.path = "./tests/?.lua;" .. package.path
	local baseline = {}
	for k in pairs(_G) do
		baseline[k] = true
	end
	-- A fresh stub and addon, as tests/run.lua's LoadAddon does.
	local function loadAddon(opts)
		for k in pairs(_G) do
			if not baseline[k] then
				_G[k] = nil
			end
		end
		package.loaded.wowstub = nil
		local stub = require("wowstub")
		if opts and opts.auctionator then
			stub.EnableAuctionator()
		end
		local ns = {}
		for line in io.lines("CraftWise/CraftWise.toc") do
			if not line:match("^%s*#") and line:match("%S") then
				local path = "CraftWise/" .. line:gsub("\\", "/"):gsub("%s+$", "")
				if not path:match("/Data/") then
					assert(loadfile(path))("CraftWise", ns)
				end
			end
		end
		stub.Fire("ADDON_LOADED", "CraftWise")
		return ns, stub
	end
	local function save(path, text)
		local f = assert(io.open(path, "wb"))
		f:write(text)
		f:close()
		print(("wrote %s (%d bytes)"):format(path, #text))
	end
	save(G.GOLDEN, G.Golden(loadAddon().Market))
	save(G.SAVED, G.SavedVariables(loadAddon))
end

if arg and arg[0] and arg[0]:match("companion_fixtures%.lua$") then
	Standalone()
end

return G
