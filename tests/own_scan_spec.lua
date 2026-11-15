-- Our own full AH scan (#6, step 1 of #253): a click asks for the whole list (ReplicateItems), the reader
-- that exists reads and stores it with source "own", a saved account-wide 15 minute cooldown with a
-- countdown, the states requested > waiting > reading > storing > done | failed, timeouts, the header
-- button, and frames bounded by time (debugprofilestop). Invented data only.
local NOW = 1794000000
local HORDE = "PvP|H"

local function Load()
	local ns, stub = LoadAddon()
	time = function() return stub.clock end
	stub.clock = NOW
	stub.printed = {}
	ns.Print = function(m) stub.printed[#stub.printed + 1] = tostring(m) end
	return ns, stub, ns.Market
end

local function OpenAH(stub)
	stub.zone, stub.subzone = "Orgrimmar", ""
	stub.Fire("AUCTION_HOUSE_SHOW")
end

local function Rows(list)
	local out = {}
	for _, r in ipairs(list) do
		out[#out + 1] = { itemID = r[1], count = r[2], buyout = r[3], link = "item:" .. r[1], owner = "Seller", name = r[4] }
	end
	return out
end

-- The states the scan went through, in order.
local function Watch(ns)
	local seen = {}
	ns.Listen("OWN_SCAN_CHANGED", function(state) seen[#seen + 1] = state end)
	return seen
end

local function Join(t) return table.concat(t, ",") end

local LIST = { { 1, 10, 1000 }, { 7, 20, 2000 }, { 7, 5, 400 }, { 8, 1, 50 } }

it("#6 the click: ReplicateItems once, saved as asked, states requested then waiting, busy while it runs", function()
	local ns, stub, M = Load()
	local seen = Watch(ns)
	eq(M.ScanBlock(), "closed", "no auction house open")
	eq(select(2, M.RequestScan()), "closed"); eq(stub.replicateRequests, nil)
	OpenAH(stub)
	eq(M.ScanBlock(), nil)
	eq(M.RequestScan(), true)
	eq(stub.replicateRequests, 1)
	eq(Join(seen), "requested,waiting")
	eq(CraftWiseMarketDB.ownScan.requested, NOW, "saved account-wide, in the market file")
	eq(CraftWiseMarketDB.ownScan.house, HORDE)
	eq(M.OwnScan().state, "waiting")
	local again, why = M.RequestScan()
	eq(again, false); eq(why, "busy"); eq(stub.replicateRequests, 1, "no second request while one is out")
end)

it("#6 the list: read, stored and logged with source own; states reading, storing, done; what it cost is saved", function()
	local ns, stub, M = Load()
	local seen = Watch(ns)
	OpenAH(stub)
	M.RequestScan()
	stub.clock = NOW + 7
	stub.replicate = Rows(LIST)
	stub.Fire("REPLICATE_ITEM_LIST_UPDATE")
	eq(Join(seen), "requested,waiting,reading,storing,done")
	local log = CraftWiseMarketDB.scans[HORDE]
	local last = log[#log]
	eq(last.kind, "full"); eq(last.source, "own")
	eq(M.Current(7, HORDE).min, 80)
	local s = M.OwnScan()
	eq(s.state, "done")
	local r = CraftWiseMarketDB.ownScan.last
	eq(r.rows, 4); eq(r.waited, 7, "seconds from the click to the list"); eq(r.t, NOW + 7); eq(r.house, HORDE)
	eq(r.lastOnly, 3); eq(r.items, 0)
	assert(r.readFrames >= 1 and r.storeFrames >= 1, "frames counted")
	eq(M.ScanProgress(), nil)
	assert(stub.printed[#stub.printed]:find("Scan finished: 4 rows", 1, true), stub.printed[#stub.printed])
end)

it("#6 a list nobody asked for is not ours: source stays as before, and it starts the cooldown too", function()
	local _, stub, M = Load()
	OpenAH(stub)
	stub.replicate = Rows(LIST)
	stub.Fire("REPLICATE_ITEM_LIST_UPDATE")
	local log = CraftWiseMarketDB.scans[HORDE]
	eq(log[#log].source, "ui")
	eq(M.OwnScan().state, "idle")
	eq(M.ScanCooldown(), 900, "the server's limit is the account's: whoever asked, we wait")
	eq(M.ScanBlock(), "cooldown")
	stub.clock = NOW + 899
	eq(M.ScanCooldown(), 1)
	stub.clock = NOW + 900
	eq(M.ScanCooldown(), 0); eq(M.ScanBlock(), nil)
end)

it("#6 cooldown: 15 minutes from the click, kept in the saved file, never longer than 15 minutes (a clock that went back)", function()
	local _, stub, M = Load()
	OpenAH(stub)
	eq(M.ScanCooldown(), 0)
	M.RequestScan()
	eq(M.ScanCooldown(), 900)
	stub.clock = NOW + 300
	eq(M.ScanCooldown(), 600)
	stub.clock = NOW - 5000
	eq(M.ScanCooldown(), 900, "a saved time in the future can't lock the button for hours")
	CraftWiseMarketDB.ownScan.requested = "junk"; CraftWiseMarketDB.ownScan.list = nil
	eq(M.ScanCooldown(), 0, "a damaged value is no cooldown")
end)

it("#6 no list arrives: the timeout says so, nothing is stored, the cooldown stays", function()
	local ns, stub, M = Load()
	local seen = Watch(ns)
	OpenAH(stub)
	M.RequestScan()
	eq(M.OWN_WAIT_SECONDS, 120)
	stub.RunTimers()
	eq(Join(seen), "requested,waiting,failed")
	local s = M.OwnScan()
	eq(s.state, "failed"); eq(s.error, "timeout")
	assert(stub.printed[#stub.printed]:find("No list arrived within 120 s", 1, true), stub.printed[#stub.printed])
	assert(stub.printed[#stub.printed]:find("Another addon may have scanned", 1, true))
	eq(CraftWiseMarketDB.scans[HORDE], nil, "nothing logged")
	eq(M.ScanCooldown(), 900)
	-- a late list after the timeout is read like any list, not claimed as ours
	stub.replicate = Rows(LIST)
	stub.Fire("REPLICATE_ITEM_LIST_UPDATE")
	eq(CraftWiseMarketDB.scans[HORDE][1].source, "ui")
	eq(M.OwnScan().state, "failed")
end)

it("#6 the timeout does not fire for a scan that got its list", function()
	local _, stub, M = Load()
	OpenAH(stub)
	M.RequestScan()
	stub.replicate = Rows(LIST)
	stub.Fire("REPLICATE_ITEM_LIST_UPDATE")
	stub.RunTimers()
	eq(M.OwnScan().state, "done")
end)

it("#6 the auction house closing: while waiting or reading it fails with a message; while storing it goes on", function()
	local ns, stub, M = Load()
	OpenAH(stub)
	M.RequestScan()
	stub.Fire("AUCTION_HOUSE_CLOSED")
	eq(M.OwnScan().state, "failed"); eq(M.OwnScan().error, "closed")
	assert(stub.printed[#stub.printed]:find("closed before the list was read", 1, true))
	-- reading: the frames are held back, the house closes in between
	stub.clock = NOW + 2000
	OpenAH(stub)
	eq(M.RequestScan(), true)
	local held = {}
	local after = C_Timer.After
	C_Timer.After = function(_, fn) held[#held + 1] = fn end
	stub.replicate = Rows(LIST)
	for i = 1, 1200 do stub.replicate[#stub.replicate + 1] = { itemID = 100 + i, count = 1, buyout = 10, link = "item:" .. i } end
	stub.Fire("REPLICATE_ITEM_LIST_UPDATE")
	eq(M.OwnScan().state, "reading")
	local p = M.ScanProgress()
	assert(p and p.total == 1204, "progress for the header")
	stub.Fire("AUCTION_HOUSE_CLOSED")
	eq(M.OwnScan().state, "failed"); eq(M.OwnScan().error, "closed")
	eq(CraftWiseMarketDB.scans[HORDE] and #CraftWiseMarketDB.scans[HORDE] or 0, 0, "nothing stored from a half-read list")
	C_Timer.After = after
	-- storing: every row was read, closing the house doesn't stop it
	stub.clock = NOW + 4000
	OpenAH(stub)
	M.RequestScan()
	held = {}
	C_Timer.After = function(_, fn) held[#held + 1] = fn end
	stub.replicate = Rows(LIST)
	stub.replicate[5] = nil
	for i = 1, 3000 do stub.replicate[#stub.replicate + 1] = { itemID = 5000 + i, count = 1, buyout = 10, link = "item:" .. i } end
	stub.Fire("REPLICATE_ITEM_LIST_UPDATE")
	while M.OwnScan().state == "reading" and #held > 0 do
		local fn = table.remove(held, 1)
		fn()
	end
	eq(M.OwnScan().state, "storing")
	stub.Fire("AUCTION_HOUSE_CLOSED")
	eq(M.OwnScan().state, "storing", "the rows were all read")
	while #held > 0 do table.remove(held, 1)() end
	C_Timer.After = after
	eq(M.OwnScan().state, "done")
end)

it("#6 a list that changes while it is read fails the scan", function()
	local _, stub, M = Load()
	OpenAH(stub)
	M.RequestScan()
	local held = {}
	local after = C_Timer.After
	C_Timer.After = function(_, fn) held[#held + 1] = fn end
	stub.replicate = Rows(LIST)
	for i = 1, 1200 do stub.replicate[#stub.replicate + 1] = { itemID = 100 + i, count = 1, buyout = 10, link = "item:" .. i } end
	stub.Fire("REPLICATE_ITEM_LIST_UPDATE")
	stub.replicate[#stub.replicate + 1] = { itemID = 99999, count = 1, buyout = 10, link = "item:99999" }
	while #held > 0 do table.remove(held, 1)() end
	C_Timer.After = after
	eq(M.OwnScan().state, "failed"); eq(M.OwnScan().error, "changed")
	assert(stub.printed[#stub.printed]:find("The list changed", 1, true))
end)

it("#6 the client refuses the request: a message with its text, and no cooldown for a request never sent", function()
	local _, stub, M = Load()
	OpenAH(stub)
	stub.replicateError = "not allowed now"
	local ok, why = M.RequestScan()
	eq(ok, false); eq(why, "error")
	eq(M.OwnScan().state, "failed"); eq(M.OwnScan().error, "error")
	assert(stub.printed[#stub.printed]:find("not allowed now", 1, true), stub.printed[#stub.printed])
	eq(M.ScanCooldown(), 0)
	stub.replicateError = nil
	eq(M.RequestScan(), true, "a new try is possible at once")
end)

it("#6 without C_AuctionHouse.ReplicateItems the scan is unsupported and the button stays hidden", function()
	local ns, stub, M = Load()
	OpenAH(stub)
	local real = C_AuctionHouse.ReplicateItems
	C_AuctionHouse.ReplicateItems = nil
	eq(M.ScanBlock(), "unsupported")
	eq(ns.Main.ScanButton().show, false)
	C_AuctionHouse.ReplicateItems = real
end)

it("#6 frames are bounded by time: a slow row stops the frame at the budget, the saved numbers show the longest", function()
	local _, stub, M = Load()
	OpenAH(stub)
	local clock = 0
	debugprofilestop = function() return clock end
	local info = C_AuctionHouse.GetReplicateItemInfo
	C_AuctionHouse.GetReplicateItemInfo = function(i) clock = clock + 0.1; return info(i) end -- 0.1 ms a row
	M.SLICE_MS = 5
	M.RequestScan()
	stub.replicate = {}
	for i = 1, 400 do stub.replicate[i] = { itemID = 1000 + i, count = 1, buyout = 10, link = "item:" .. i } end
	stub.Fire("REPLICATE_ITEM_LIST_UPDATE")
	C_AuctionHouse.GetReplicateItemInfo = info
	local r = CraftWiseMarketDB.ownScan.last
	assert(r, "scan finished")
	assert(r.readFrames >= 7, "400 rows at 0.1 ms in 5 ms frames: " .. r.readFrames)
	assert(r.readWorstMs <= 5.5, "the longest reading frame: " .. r.readWorstMs)
	eq(r.rows, 400)
end)

it("#6 the unit budgets stay as the cap when the clock doesn't move", function()
	local _, stub, M = Load()
	OpenAH(stub)
	M.RequestScan()
	stub.replicate = {}
	for i = 1, 1200 do stub.replicate[i] = { itemID = 1000 + i, count = 1, buyout = 10, link = "item:" .. i } end
	stub.Fire("REPLICATE_ITEM_LIST_UPDATE")
	local r = CraftWiseMarketDB.ownScan.last
	eq(r.readFrames, 3, "500 rows a frame")
end)

----------------------------------------------------------------------------------------------------
-- The window
----------------------------------------------------------------------------------------------------

it("#6 the button model: hidden without an auction house, 'Scan AH' ready, waiting seconds, countdown, failure text", function()
	local ns, stub, M = Load()
	local Main = ns.Main
	eq(Main.ScanButton().show, false)
	OpenAH(stub)
	local b = Main.ScanButton()
	eq(b.show, true); eq(b.label, "Scan AH"); eq(b.enabled, true)
	M.RequestScan()
	stub.clock = NOW + 8
	b = Main.ScanButton()
	eq(b.label, "Waiting for the list · 8 s"); eq(b.enabled, false)
	stub.RunTimers()
	stub.clock = NOW + 100
	stub.RunTimers()
	-- failed: the button counts down
	b = Main.ScanButton()
	eq(b.label, "Scan AH · 13:20"); eq(b.enabled, false)
	assert(b.tip[2]:find("next scan in 13:20", 1, true), b.tip[2])
	eq(Main.Countdown(754), "12:34"); eq(Main.Countdown(0), "0:00"); eq(Main.Countdown(59.2), "1:00")
	eq(Main.ScanFailText("closed"), "The auction house closed before the list was read. Nothing was stored.")
	assert(Main.ScanFailText("error", "boom"):find("boom", 1, true))
end)

it("#6 the header button: shown while an auction house is open, a click requests, the label ticks, it hides on close", function()
	local ns, stub, M = Load()
	local Main = ns.Main
	Main.Open()
	local f = Main.Frame()
	eq(f.head.scan:IsShown(), false)
	OpenAH(stub)
	eq(f.head.scan:IsShown(), true, "AH_STATE_CHANGED redraws")
	eq(f.head.scan.label.text, "Scan AH"); eq(f.head.scan.enabled, true)
	f.head.scan.scripts.OnClick(f.head.scan)
	eq(stub.replicateRequests, 1)
	eq(f.head.scan.label.text, "Waiting for the list · 0 s"); eq(f.head.scan.enabled, false)
	stub.clock = NOW + 5
	f.scripts.OnUpdate(f, 0.3)
	eq(f.head.scan.label.text, "Waiting for the list · 5 s", "the poll ticks it")
	stub.replicate = Rows(LIST)
	stub.Fire("REPLICATE_ITEM_LIST_UPDATE")
	eq(f.head.scan.label.text, "Scan AH · 15:00", "done: the cooldown")
	eq(f.head.scan.enabled, false)
	stub.clock = NOW + 905
	f.scripts.OnUpdate(f, 0.3)
	eq(f.head.scan.label.text, "Scan AH"); eq(f.head.scan.enabled, true)
	stub.Fire("AUCTION_HOUSE_CLOSED")
	eq(f.head.scan:IsShown(), false)
	-- hover: the tooltip is the model's
	OpenAH(stub)
	local tip = f.head.scan.hooks.OnEnter
	assert(tip and #tip >= 1, "tooltip hooked")
end)

it("#6 the window layout puts the button left of the status; docked it sits in the header corner", function()
	local ns, stub = Load()
	local Main = ns.Main
	Main.Open("craft")
	local f = Main.Frame()
	OpenAH(stub)
	local pts = f.head.scan.points
	eq(pts[#pts][2], f.head.gear); eq(pts[#pts][1], "RIGHT")
	local sp = f.head.status.points
	eq(sp[#sp][2], f.head.scan, "the status follows the button")
	Main.SetLayout("dockLeft")
	pts = f.head.scan.points
	eq(pts[#pts][1], "BOTTOMRIGHT"); eq(f.head.scan:IsShown(), true)
	Main.SetLayout("window")
	sp = f.head.status.points
	eq(sp[#sp][2], f.head.scan)
	stub.Fire("AUCTION_HOUSE_CLOSED")
	sp = f.head.status.points
	eq(sp[#sp][2], f.head.gear, "without the button the status goes back to the gear")
end)
