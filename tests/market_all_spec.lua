-- Issue #90: every item of a full scan (last only outside the scope), Auctionator fallback export.
local NOW = 1794000000
local DAY = 86400
local HORDE, BOOTY = "PvP|H", "PvP|N:BootyBay"

local function Market(opts)
	local ns, stub = LoadAddon(opts)
	time = function() return stub.clock end
	stub.clock = NOW
	return ns.Market, stub, ns
end

local function InScope(items)
	for _, id in ipairs(items) do CraftWiseMarketDB.scope.items[id] = true end
end

local function OpenAH(stub, zone)
	stub.zone, stub.subzone = zone or "Orgrimmar", ""
	stub.Fire("AUCTION_HOUSE_SHOW")
end

local function Rows(list)
	local out = {}
	for _, r in ipairs(list) do
		out[#out + 1] = { itemID = r[1], count = r[2], buyout = r[3], link = "item:" .. r[1], owner = "Seller", name = r[4] }
	end
	return out
end

local function Scan(stub, list)
	stub.replicate = Rows(list)
	stub.Fire("REPLICATE_ITEM_LIST_UPDATE")
end

local function Printed(fn)
	local lines, realPrint = {}, print
	print = function(s) lines[#lines + 1] = tostring(s) end
	local ok, err = pcall(fn)
	print = realPrint
	assert(ok, err)
	return table.concat(lines, "\n")
end

------------------------------------------------------------------------------------- every item

it("#90: an item outside the scope is stored with last only: lowest unit price, units, listings", function()
	local M, stub = Market()
	InScope({ 1 })
	OpenAH(stub)
	Scan(stub, { { 1, 10, 1000 }, { 7, 20, 2000 }, { 7, 5, 400 }, { 7, 1, 300 } })
	local stored = CraftWiseMarketDB.items[7][HORDE]
	eq(type(stored), "string", "written packed, never decoded")
	eq(M.IsLastOnly(stored), true)
	local e = M.DecodeEntry(stored)
	eq(#e.raw, 0); eq(next(e.days), nil)
	eq(e.last.t, NOW); eq(e.last.min, 80); eq(e.last.qty, 26); eq(e.last.listings, 3)
	local current = M.Current(7, HORDE)
	eq(current.min, 80); eq(current.listed, true)
	eq(M.Depth(7, HORDE), nil, "no tiers outside the scope")
	eq(M.InScope(7), false, "seeing an item in a scan isn't interacting with it")
end)

it("#90: a scope item is recorded exactly as before, whatever else the scan holds", function()
	local function scopeEntry(extra)
		local M, stub = Market()
		InScope({ 1 })
		OpenAH(stub)
		local list = { { 1, 3, 300 }, { 1, 10, 1500 }, { 1, 2, 300 } }
		for _, row in ipairs(extra) do list[#list + 1] = row end
		Scan(stub, list)
		return M.EncodeEntry(M.DecodeEntry(M.EncodeEntry(CraftWiseMarketDB.items[1][HORDE]))), CraftWiseMarketDB.scans[HORDE][1].items
	end
	local alone, n1 = scopeEntry({})
	local mixed, n2 = scopeEntry({ { 2, 1, 50 }, { 3, 4, 4000 }, { 4, 1, 10 } })
	eq(mixed, alone)
	eq(n1, 1); eq(n2, 1, "the log's items still counts the scope")
end)

it("#90: outside the scope stays last only over many scans, and a later scan replaces last", function()
	local M, stub = Market()
	OpenAH(stub)
	for i = 0, 5 do
		stub.clock = NOW + i * 3600
		Scan(stub, { { 7, 1, 100 + i } })
	end
	local e = M.DecodeEntry(CraftWiseMarketDB.items[7][HORDE])
	eq(#e.raw, 0); eq(next(e.days), nil)
	eq(e.last.min, 105); eq(e.last.t, NOW + 5 * 3600)
	stub.Fire("AUCTION_HOUSE_CLOSED")
	eq(M.IsLastOnly(CraftWiseMarketDB.items[7][HORDE]), true, "pruning makes no history either")
end)

it("#90: an item outside the scope missing from a finished full scan shows as not listed", function()
	local M, stub = Market()
	OpenAH(stub)
	Scan(stub, { { 7, 4, 400 }, { 8, 1, 50 } })
	stub.clock = NOW + 3600
	Scan(stub, { { 8, 1, 50 } })
	local current = M.Current(7, HORDE)
	eq(current.listed, false); eq(current.min, 100); eq(current.t, NOW, "last seen stays")
	eq(M.IsLastOnly(CraftWiseMarketDB.items[7][HORDE]), true)
	local quote, why = M.Quote(7, HORDE, "current")
	eq(quote, nil); eq(why, "not listed")
	stub.clock = NOW + 7200
	Scan(stub, { { 7, 1, 90 } })
	current = M.Current(7, HORDE)
	eq(current.listed, true); eq(current.min, 90)
end)

it("#90: an item whose rows couldn't be read isn't marked as gone", function()
	local M, stub = Market()
	stub.itemClass[7] = 4 -- armor: needs its link
	OpenAH(stub)
	Scan(stub, { { 7, 1, 900 } })
	stub.clock = NOW + 3600
	stub.replicate = Rows({ { 7, 1, 900 }, { 8, 1, 50 } })
	stub.replicate[1].link = nil
	stub.Fire("REPLICATE_ITEM_LIST_UPDATE")
	eq(M.Current(7, HORDE).listed, true)
	eq(M.Current(7, HORDE).t, NOW)
end)

it("#90: Booty Bay and the Horde AH stay apart for items outside the scope too", function()
	local M, stub = Market()
	OpenAH(stub)
	Scan(stub, { { 7, 1, 100 } })
	stub.Fire("AUCTION_HOUSE_CLOSED")
	stub.clock = NOW + 600
	OpenAH(stub, "Booty Bay")
	Scan(stub, { { 7, 1, 5000 } })
	eq(M.Current(7, HORDE).min, 100); eq(M.Current(7, HORDE).listed, true)
	eq(M.Current(7, BOOTY).min, 5000)
end)

it("#90: storing a large scan takes several frames; last-only items cost less per frame", function()
	local _, stub = Market()
	InScope({ 1 })
	OpenAH(stub)
	stub.replicate = { { itemID = 1, count = 1, buyout = 100, link = "item:1" } }
	for i = 2, 3001 do stub.replicate[i] = { itemID = 10000 + i, count = 1, buyout = 100, link = "item:" .. i } end
	local frames, run = 0, nil
	local after = C_Timer.After
	C_Timer.After = function(_, fn) frames = frames + 1; run = fn end
	stub.Fire("REPLICATE_ITEM_LIST_UPDATE")
	while run do
		local go = run
		run = nil
		go()
	end
	C_Timer.After = after
	eq(CraftWiseMarketDB.scans[HORDE][1].lastOnly, 3000)
	-- reading: 3001 rows at 500 a frame (7 frames); storing: 3000 light + 1 full entry at 1000 a frame (4);
	-- item info (#92): 3001 items at 500 a frame (7)
	assert(frames >= 14 and frames <= 18, "frames: " .. frames)
end)

it("#90: pruning checks the age of last-only entries without decoding them; 30 days kept", function()
	local M, stub = Market()
	OpenAH(stub)
	Scan(stub, { { 7, 1, 100 } })
	stub.Fire("AUCTION_HOUSE_CLOSED")
	local decode, calls = M.DecodeEntry, 0
	M.DecodeEntry = function(...) calls = calls + 1; return decode(...) end
	stub.clock = NOW + 29 * DAY
	M.Prune()
	eq(calls, 0)
	eq(type(CraftWiseMarketDB.items[7][HORDE]), "string")
	stub.clock = NOW + 31 * DAY
	M.Prune()
	eq(calls, 0)
	eq(CraftWiseMarketDB.items[7], nil, "older than 30 days: dropped")
	M.DecodeEntry = decode
end)

it("#90: names come from the scan rows and the client cache; the file keeps IDs only in records", function()
	local M, stub = Market()
	OpenAH(stub)
	Scan(stub, { { 7, 1, 100, "Waylaid Crate" }, { 8, 1, 100 } })
	eq(CraftWiseMarketDB.names[7], "Waylaid Crate")
	eq(CraftWiseMarketDB.names[8], nil, "the row had no name")
	stub.items[8] = { name = "Silverleaf" } -- the client loads it later
	stub.Fire("PLAYER_LOGOUT")
	eq(CraftWiseMarketDB.names[8], "Silverleaf", "filled from the client at logout")
	assert(not CraftWiseMarketDB.items[7][HORDE]:find("Waylaid", 1, true))
	stub.clock = NOW + 31 * DAY
	CraftWiseMarketDB.prunedAt = nil
	M.Prune()
	eq(CraftWiseMarketDB.names[7], nil, "dropped with its records")
end)

it("#90: /craftwise market for an item outside the scope says it has no history", function()
	local _, stub = Market()
	OpenAH(stub)
	Scan(stub, { { 7, 3, 300, "Earthroot" } })
	local text = Printed(function() SlashCmdList.CRAFTWISE("market 7"); stub.RunTimers() end)
	assert(text:find("Earthroot", 1, true), text)
	assert(text:find("Horde AH: last", 1, true), text)
	assert(text:find("outside the market scope, latest price only", 1, true), text)
	assert(not text:find("too little history", 1, true), text)
end)

it("#90: the snapshot names where the market data is, per house", function()
	local M, stub, ns = Market()
	InScope({ 1 })
	OpenAH(stub)
	Scan(stub, { { 1, 1, 100 }, { 7, 1, 100 }, { 8, 1, 100 } })
	local summary = ns.Snapshot.Build().market
	eq(summary.where, "CraftWiseMarketDB")
	local h = summary.houses[HORDE]
	eq(h.label, "Horde AH"); eq(h.items, 3); eq(h.withHistory, 1)
	eq(h.lastFullScan, NOW); eq(h.lastFullScanItems, 1); eq(h.lastFullScanLastOnly, 2)
	eq(summary.auctionator.items, 0); eq(summary.auctionator.house, "unknown")
	eq(M.SnapshotSummary().houses[HORDE].items, 3)
end)

------------------------------------------------------------------------------ Auctionator export

it("#90: a lookup that falls back to Auctionator stores its price apart, labelled house unknown", function()
	local M, stub, ns = Market({ auctionator = true })
	stub.ah[5], stub.ahAge[5] = 777, 2
	local quote = ns.AuctionQuote(5)
	eq(quote.source, "auctionator")
	local e = M.AuctionatorExport(5)
	eq(e.copper, 777); eq(e.age, 2); eq(e.t, NOW)
	eq(e.house, "unknown"); eq(e.label, "Auctionator (house unknown)")
	eq(CraftWiseMarketDB.auctionator.source, "auctionator")
	eq(CraftWiseMarketDB.auctionator.house, "unknown")
	eq(CraftWiseMarketDB.items[5], nil, "never in the per-house data")
	eq(M.Current(5, HORDE), nil)
end)

it("#90: Auctionator never overrides CraftWise's own price", function()
	local M, stub, ns = Market({ auctionator = true })
	InScope({ 5 })
	stub.ah[5] = 777
	OpenAH(stub)
	Scan(stub, { { 5, 1, 100 } })
	local quote = ns.AuctionQuote(5)
	eq(quote.source, "market"); eq(quote.copper, 100)
	eq(M.AuctionatorExport(5), nil, "CraftWise has a price, so nothing is exported")
	-- An export from before stays apart and changes nothing.
	M.ExportAuctionator(5, 999, 0)
	eq(ns.AuctionQuote(5).copper, 100)
	eq(M.Current(5, HORDE).min, 100)
	stub.Fire("AUCTION_HOUSE_CLOSED")
	eq(M.Current(5, HORDE).min, 100)
end)

it("#90: the scope is exported after login and AH close, only items without a price at the profit house", function()
	local M, stub = Market({ auctionator = true })
	InScope({ 5, 6, 7 })
	stub.ah[5], stub.ah[6], stub.ah[7] = 500, 600, 700
	OpenAH(stub, "Booty Bay")
	Scan(stub, { { 6, 1, 6000 } }) -- 6 has a price only at Booty Bay
	stub.Fire("AUCTION_HOUSE_CLOSED")
	eq(M.AuctionatorExport(5).copper, 500)
	eq(M.AuctionatorExport(6).copper, 600, "no price at the Horde AH, the profit house")
	eq(M.AuctionatorExport(7).copper, 700)
	stub.clock = NOW + 7200
	OpenAH(stub)
	Scan(stub, { { 7, 1, 70 } })
	stub.Fire("AUCTION_HOUSE_CLOSED")
	eq(M.AuctionatorExport(5).t, NOW + 7200, "refreshed")
	eq(M.AuctionatorExport(7).t, NOW, "own price at the profit house now: not exported again")

	local M2, stub2 = Market({ auctionator = true })
	InScope({ 9 })
	stub2.ah[9] = 900
	stub2.Fire("PLAYER_LOGIN")
	CraftWiseMarketDB.auctionator.items = {} -- lookups at login export on their own; the pass waits
	stub2.RunTimers()
	eq(M2.AuctionatorExport(9).copper, 900)
end)

it("#90: without Auctionator nothing is exported; an unchanged price is rewritten at most hourly", function()
	local M, stub, ns = Market()
	InScope({ 5 })
	stub.Fire("AUCTION_HOUSE_CLOSED")
	eq(next(CraftWiseMarketDB.auctionator.items), nil)
	eq(M.ExportAuctionator(5, 100, 1), true)
	eq(M.ExportAuctionator(5, 100, 1), false, "same price within the hour")
	stub.clock = NOW + 3600
	eq(M.ExportAuctionator(5, 100, 1), true)
	eq(M.ExportAuctionator(5, 120, 1), true, "a new price at once")
	eq(M.ExportAuctionator(5, 0, 1), false)
	eq(M.ExportAuctionator("5:1", 100, 1), false)
	eq(ns.AuctionQuote(5), nil, "the export is never read back as a price")
end)

it("#90: exports older than 30 days are dropped", function()
	local M, stub = Market()
	M.ExportAuctionator(5, 100, 1)
	stub.clock = NOW + 31 * DAY
	M.Prune()
	eq(M.AuctionatorExport(5), nil)
end)

it("#90: /craftwise market shows the Auctionator export with its label", function()
	local M, stub = Market()
	M.ExportAuctionator(5, 12345, 3)
	stub.clock = NOW + 1800
	local text = Printed(function() SlashCmdList.CRAFTWISE("market 5"); stub.RunTimers() end)
	assert(text:find("no price data", 1, true), text)
	assert(text:find("Auctionator (house unknown): ", 1, true), text)
	assert(text:find("read 30m ago, Auctionator saw it 3 days ago", 1, true), text)
end)

----------------------------------------------------------------------------------------- size

-- WoW's SavedVariables writer: tabs per depth, ["key"] = value, array items with -- [n].
local function SerializedSize(value)
	local size = 0
	local function write(v, depth)
		local kind = type(v)
		if kind == "string" then
			size = size + #v + 2
		elseif kind ~= "table" then
			size = size + #tostring(v)
		else
			size = size + 2
			local n = #v
			for i = 1, n do
				size = size + depth + 1
				write(v[i], depth + 1)
				size = size + #(", -- [" .. i .. "]\n")
			end
			for k, x in pairs(v) do
				if not (type(k) == "number" and k >= 1 and k <= n) then
					size = size + depth + 1 + #tostring(k) + (type(k) == "string" and 8 or 6)
					write(x, depth + 1)
					size = size + 2
				end
			end
			size = size + depth + 1
		end
	end
	write(value, 0)
	return size
end

local MB = 1000 * 1000
local ZONES = { "Orgrimmar", "Booty Bay", "Gadgetzan", "Everlook" }

-- A full scan of 10,000 items through the real event path: 1,100 in the scope (Veli's professions,
-- #26), the rest outside it; 1 to 5 listings each, about 30,000 rows; every item named by its row.
-- Stored at `houses` houses, pruned and packed as at logout.
local function ScanSize(houses)
	local M, stub = Market()
	local scope = {}
	for i = 1, 1100 do scope[i] = 20000 + i * 3 end
	InScope(scope)
	local rows = {}
	for i = 1, 10000 do
		local itemID = 20000 + i * 3
		local base = 50 + (i * 7919) % 300000
		for k = 1, 1 + i % 5 do
			local count = 1 + (i * k) % 20
			rows[#rows + 1] = { itemID = itemID, count = count, buyout = (base + k * 13) * count, link = "item:" .. itemID,
				name = ("Item Name Number %d"):format(i) }
		end
	end
	for h = 1, houses do
		OpenAH(stub, ZONES[h])
		stub.replicate = rows
		stub.Fire("REPLICATE_ITEM_LIST_UPDATE")
		stub.Fire("AUCTION_HOUSE_CLOSED")
		stub.clock = stub.clock + 600
	end
	stub.Fire("PLAYER_LOGOUT")
	return SerializedSize(CraftWiseMarketDB), #rows, M
end

it("#90 size: one full scan of 10,000 items at one house", function()
	local size, rows, M = ScanSize(1)
	print(("       measured: 10,000 items (%d rows, 1,100 in scope), 1 house, one scan = %.2f MB"):format(rows, size / MB))
	local light = 0
	for _, perItem in pairs(CraftWiseMarketDB.items) do
		if M.IsLastOnly(perItem[HORDE]) then light = light + 1 end
	end
	eq(light, 8900)
	assert(size < 1.5 * MB, ("%.2f MB"):format(size / MB))
end)

it("#90 size: the same scan at all 4 houses", function()
	local size = ScanSize(4)
	print(("       measured: 10,000 items, 4 houses, one scan each = %.2f MB"):format(size / MB))
	assert(size < 4 * MB, ("%.2f MB"):format(size / MB))
end)
