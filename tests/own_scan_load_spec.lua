-- Own AH scan: item data for the rows whose link wasn't there (#286). On Veli's first scan 3,901 of about 5,000
-- items were left unread: gear without a link was tried again every half second for 5 s, every row each
-- time. Now the distinct items are asked for in batches while the list is kept, their rows are read once their
-- data is there, there is a phase with progress, and what stays unread is counted by reason and category.
-- Invented data only.
local NOW = 1794000000
local HORDE = "H"
local ARMOR, WEAPON = 4, 2

local function Load()
	local ns, stub = LoadAddon()
	time = function() return stub.clock end
	stub.clock = NOW
	stub.printed = {}
	ns.Print = function(m) stub.printed[#stub.printed + 1] = tostring(m) end
	return ns, stub, ns.Market, ns.Main
end

local function OpenAH(stub)
	stub.zone, stub.subzone = "Orgrimmar", ""
	stub.Fire("AUCTION_HOUSE_SHOW")
end

-- Holds the scan's frames back: step() runs the next one.
local function Hold()
	local held, real = {}, C_Timer.After
	C_Timer.After = function(_, fn) held[#held + 1] = fn end
	return {
		step = function() local fn = table.remove(held, 1); if fn then fn() end end,
		release = function() C_Timer.After = real end,
		pending = function() return #held end,
	}
end

-- n gear items 5000+i, two rows each, none of their data there; plus 3 trade goods with links.
local function Gear(stub, n, class)
	stub.replicate = {}
	for i = 1, n do
		local id = 5000 + i
		stub.itemClass[id] = class or ARMOR
		stub.uncached[id] = true
		for _ = 1, 2 do
			stub.replicate[#stub.replicate + 1] = { itemID = id, count = 1, buyout = 100 + i, link = nil, owner = "S" }
		end
	end
	for i = 1, 3 do
		stub.replicate[#stub.replicate + 1] = { itemID = 100 + i, count = 5, buyout = 50, link = "item:" .. (100 + i), owner = "S" }
	end
end

local function Requested(stub)
	local set, n = {}, 0
	for _, id in ipairs(stub.loadRequests) do
		if not set[id] then set[id] = true; n = n + 1 end
	end
	return n, set
end

it("#286 no link, no wait per row: the items are asked for once each, in a window, and read when their data is there", function()
	local ns, stub, M = Load()
	OpenAH(stub)
	M.RequestScan()
	M.LOAD_WINDOW = 10
	Gear(stub, 30)
	local hold = Hold()
	stub.Fire("REPLICATE_ITEM_LIST_UPDATE")
	eq(M.OwnScan().state, "loading")
	local p = M.ScanProgress()
	eq(p.phase, "load"); eq(p.total, 30); eq(p.done, 0)
	eq(#stub.loadRequests, 10, "the window: 10 requests wait for an answer, one per item")
	-- five arrive: their rows are read, the window is filled up again
	for id = 5001, 5005 do stub.ArriveItem(id) end
	hold.step()
	p = M.ScanProgress()
	eq(p.done, 5)
	eq(#stub.loadRequests, 15)
	eq(select(1, Requested(stub)), 15, "no item twice")
	eq(M.OwnScan().state, "loading")
	-- all the rest
	for round = 1, 20 do
		for id = 5001, 5030 do
			if stub.uncached[id] then
				local _, asked = Requested(stub)
				if asked[id] then stub.ArriveItem(id) end
			end
		end
		hold.step()
		if M.OwnScan().state ~= "loading" then break end
	end
	hold.release()
	eq(M.OwnScan().state, "done")
	local last = CraftWiseMarketDB.ownScan.last
	eq(last.needed, 30); eq(last.loaded, 30); eq(last.unread, 0)
	eq(last.lastOnly, 33, "all 30 gear items and the 3 trade goods are stored")
	eq(M.Current(5017, HORDE).min, 117)
end)

it("#286 the rows are read again only for the item whose data arrived, with the suffix of its link", function()
	local _, stub, M = Load()
	OpenAH(stub)
	M.RequestScan()
	Gear(stub, 2)
	stub.replicate[1].linkAfter = "item:5001:0:0:0:0:0:-17:0"
	stub.replicate[2].linkAfter = "item:5001:0:0:0:0:0:-17:0"
	local hold = Hold()
	stub.Fire("REPLICATE_ITEM_LIST_UPDATE")
	local reads = 0
	local info = C_AuctionHouse.GetReplicateItemInfo
	C_AuctionHouse.GetReplicateItemInfo = function(i) reads = reads + 1; return info(i) end
	stub.ArriveItem(5001)
	hold.step()
	eq(reads, 2, "the two rows of the item that arrived, not the whole list")
	C_AuctionHouse.GetReplicateItemInfo = info
	stub.ArriveItem(5002)
	hold.step()
	hold.release()
	eq(M.OwnScan().state, "done")
	assert(CraftWiseMarketDB.items["5001:-17"], "stored under its suffix key, never under the plain item")
	eq(CraftWiseMarketDB.items[5001], nil)
	assert(CraftWiseMarketDB.items[5002], "an item without suffix under its id")
end)

it("#286 an item the client says doesn't exist is given up at once; the others go on; counted as failed", function()
	local _, stub, M = Load()
	OpenAH(stub)
	M.RequestScan()
	Gear(stub, 3, WEAPON)
	local hold = Hold()
	stub.Fire("REPLICATE_ITEM_LIST_UPDATE")
	stub.ArriveItem(5002, false)
	stub.ArriveItem(5001); stub.ArriveItem(5003)
	hold.step()
	hold.release()
	eq(M.OwnScan().state, "done")
	local last = CraftWiseMarketDB.ownScan.last
	eq(last.unread, 1); eq(last.unreadFailed, 1); eq(last.unreadWeapon, 1); eq(last.unreadArmor, 0)
	eq(CraftWiseMarketDB.items[5002], nil, "nothing stored for it, and nothing marked gone")
	assert(CraftWiseMarketDB.items[5001] and CraftWiseMarketDB.items[5003])
end)

it("#286 data there but still no link: given up after three looks as nolink", function()
	local _, stub, M = Load()
	OpenAH(stub)
	M.RequestScan()
	Gear(stub, 1)
	stub.uncached[5001] = nil -- the client has it, the list still has no link
	stub.Fire("REPLICATE_ITEM_LIST_UPDATE")
	eq(M.OwnScan().state, "done")
	local last = CraftWiseMarketDB.ownScan.last
	eq(last.unread, 1); eq(last.unreadNoLink, 1); eq(last.unreadArmor, 1)
	eq(last.needed, 1); eq(last.loaded, 0)
end)

it("#286 nothing new for LOAD_STALL_SECONDS: the rest is given up as timeout, the scan still stores what it has", function()
	local _, stub, M = Load()
	OpenAH(stub)
	M.RequestScan()
	M.LOAD_STALL_SECONDS = 20
	Gear(stub, 6)
	local hold = Hold()
	stub.Fire("REPLICATE_ITEM_LIST_UPDATE")
	stub.ArriveItem(5001); stub.ArriveItem(5002)
	stub.now = stub.now + 5
	hold.step()
	eq(M.OwnScan().state, "loading")
	stub.now = stub.now + 19
	hold.step()
	eq(M.OwnScan().state, "loading", "19 s after the last arrival")
	stub.now = stub.now + 2
	hold.step()
	while hold.pending() > 0 do hold.step() end
	hold.release()
	eq(M.OwnScan().state, "done")
	local last = CraftWiseMarketDB.ownScan.last
	eq(last.loaded, 2); eq(last.unread, 4); eq(last.unreadTimeout, 4); eq(last.stalled, true)
	assert(last.loadSeconds >= 26, last.loadSeconds)
	eq(last.lastOnly, 5, "two gear items and the three trade goods")
end)

it("#286 an item asked for and still missing is asked again after 10 s, not every tick", function()
	local _, stub, M = Load()
	OpenAH(stub)
	M.RequestScan()
	M.LOAD_STALL_SECONDS = 1000; M.LOAD_MAX_SECONDS = 1000
	Gear(stub, 2)
	local hold = Hold()
	stub.Fire("REPLICATE_ITEM_LIST_UPDATE")
	eq(#stub.loadRequests, 2)
	stub.now = stub.now + 4; hold.step(); hold.step()
	eq(#stub.loadRequests, 2, "not again yet")
	stub.now = stub.now + 7; hold.step()
	eq(#stub.loadRequests, 4, "again after 10 s")
	stub.ArriveItem(5001); stub.ArriveItem(5002)
	hold.step()
	hold.release()
	eq(M.OwnScan().state, "done")
end)

it("#286 the list changing or the house closing while the data loads stops the scan; nothing is stored", function()
	local _, stub, M = Load()
	OpenAH(stub)
	M.RequestScan()
	Gear(stub, 3)
	local hold = Hold()
	stub.Fire("REPLICATE_ITEM_LIST_UPDATE")
	eq(M.OwnScan().state, "loading")
	stub.Fire("AUCTION_HOUSE_CLOSED")
	eq(M.OwnScan().state, "failed"); eq(M.OwnScan().error, "closed")
	stub.ArriveItem(5001)
	while hold.pending() > 0 do hold.step() end
	hold.release()
	eq(next(CraftWiseMarketDB.items), nil, "a half-read list stores nothing")
	-- a changing list
	stub.clock = NOW + 5000
	OpenAH(stub)
	M.RequestScan()
	Gear(stub, 3)
	hold = Hold()
	stub.Fire("REPLICATE_ITEM_LIST_UPDATE")
	stub.replicate[#stub.replicate + 1] = { itemID = 1, count = 1, buyout = 5, link = "item:1" }
	stub.ArriveItem(5001)
	while hold.pending() > 0 do hold.step() end
	hold.release()
	eq(M.OwnScan().state, "failed"); eq(M.OwnScan().error, "changed")
end)

it("#286 the window shows the phase: text, bar, hint, button; the done line says how many items were not read", function()
	local _, stub, M, Main = Load()
	OpenAH(stub)
	M.RequestScan()
	M.LOAD_WINDOW = 4
	Gear(stub, 8)
	local hold = Hold()
	stub.Fire("REPLICATE_ITEM_LIST_UPDATE")
	stub.ArriveItem(5001); stub.ArriveItem(5002)
	hold.step()
	local m = Main.ScanModel()
	eq(m.kind, "scanning"); eq(m.state, "loading")
	eq(m.text, "Loading item data · 2 of 8 · 25 %")
	eq(m.fraction, 0.25)
	eq(m.hint, "Keep the auction house open.")
	eq(Main.ScanButton().label, "Loading · 25 %")
	stub.ArriveItem(5003, false)
	hold.step()
	eq(Main.ScanModel().text, "Loading item data · 3 of 8 · 37 %", "a failed item counts as dealt with")
	for id = 5004, 5008 do stub.ArriveItem(id) end
	hold.step()
	hold.release()
	eq(M.OwnScan().state, "done")
	local done = Main.ScanModel()
	assert(done.text:find("Scan done · ", 1, true), done.text)
	assert(done.text:find(" · 1 items not read", 1, true), done.text)
end)

it("#286 a scan without missing links has no loading phase, and a list nobody asked for gets the same load phase", function()
	local _, stub, M = Load()
	OpenAH(stub)
	M.RequestScan()
	stub.replicate = { { itemID = 7, count = 1, buyout = 100, link = "item:7", owner = "S" } }
	stub.Fire("REPLICATE_ITEM_LIST_UPDATE")
	eq(M.OwnScan().state, "done")
	eq(CraftWiseMarketDB.ownScan.last.needed, 0); eq(CraftWiseMarketDB.ownScan.last.unread, 0)
	-- somebody else's list: the same loading, source stays theirs
	stub.clock = NOW + 3000
	Gear(stub, 2)
	local hold = Hold()
	stub.Fire("REPLICATE_ITEM_LIST_UPDATE")
	eq(M.ScanProgress().phase, "load")
	stub.ArriveItem(5001); stub.ArriveItem(5002)
	hold.step()
	hold.release()
	local log = CraftWiseMarketDB.scans[HORDE]
	eq(log[#log].source, "ui"); eq(log[#log].kind, "full")
	assert(CraftWiseMarketDB.items[5001] and CraftWiseMarketDB.items[5002])
end)
