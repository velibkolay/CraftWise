-- Own AH scan and the client's request throttle (#291). Veli's click at 18:36 got no list in 120 s while
-- Auctionator, Mastercraft and CraftWise's own browse recording query the house the moment it opens. The click
-- now waits until IsThrottledMessageSystemReady() (nothing sent, no cooldown), counts the throttle events after
-- the call, treats a drop before anything was sent as "the server never got it" (no cooldown, retry at once),
-- shows a queued request as such, and records what happened. Invented data only.
local NOW = 1794000000
local HORDE = "PvP|H"
local EVENTS = {
	sent = "AUCTION_HOUSE_THROTTLED_MESSAGE_SENT", queued = "AUCTION_HOUSE_THROTTLED_MESSAGE_QUEUED",
	dropped = "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED", response = "AUCTION_HOUSE_THROTTLED_MESSAGE_RESPONSE_RECEIVED",
}

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

local function Rows(n)
	local rows = {}
	for i = 1, n do rows[i] = { itemID = 1000 + i, count = 1, buyout = 10, link = "item:" .. i } end
	return rows
end

local function Throttle(stub, kind) stub.Fire(EVENTS[kind]) end

it("#291 ready at the click: the request goes out at once, as before", function()
	local _, stub, M = Load()
	OpenAH(stub)
	eq(M.RequestScan(), true)
	eq(stub.replicateRequests, 1)
	eq(M.OwnScan().state, "waiting")
	eq(CraftWiseMarketDB.ownScan.requested, NOW)
end)

it("#291 not ready: the click waits, sends nothing and uses no cooldown; the READY event sends it", function()
	local _, stub, M, Main = Load()
	OpenAH(stub)
	stub.throttleReady = false
	eq(M.RequestScan(), true)
	local s = M.OwnScan()
	eq(s.state, "ready"); eq(stub.replicateRequests, nil, "nothing sent")
	eq(CraftWiseMarketDB.ownScan.requested, nil, "no cooldown used")
	eq(M.ScanCooldown(), 0)
	eq(M.ScanBlock(), "busy", "a second click does nothing")
	stub.clock = NOW + 7
	local m = Main.ScanModel()
	eq(m.kind, "scanning"); eq(m.text, "Waiting for the auction house to be ready · 0:07 / 0:30")
	eq(m.hint, "The game is still answering other addons' queries. Nothing has been sent yet.")
	eq(Main.ScanButton().label, "Getting ready · 0:07"); eq(Main.ScanButton().enabled, false)
	stub.throttleReady = true
	stub.Fire("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
	eq(stub.replicateRequests, 1)
	eq(M.OwnScan().state, "waiting")
	eq(CraftWiseMarketDB.ownScan.requested, NOW + 7, "the cooldown counts from the moment it was sent")
	-- the wait for the server starts then
	stub.clock = NOW + 10
	eq(Main.ScanModel().text, "Waiting for the server · 0:03 / 2:00")
	stub.replicate = Rows(10)
	stub.Fire("REPLICATE_ITEM_LIST_UPDATE")
	eq(M.OwnScan().state, "done")
	local req = CraftWiseMarketDB.ownScan.lastRequest
	eq(req.outcome, "list"); eq(req.readyAtClick, false); eq(req.readyWait, 7)
	eq(CraftWiseMarketDB.ownScan.last.readyWait, 7); eq(CraftWiseMarketDB.ownScan.last.readyAtClick, false)
end)

it("#291 not ready: a poll catches a READY event that never came", function()
	local _, stub, M = Load()
	OpenAH(stub)
	stub.throttleReady = false
	M.RequestScan()
	stub.timers[2].cancelled = true -- the click's own timeout (OWN_READY_SECONDS) isn't under test here
	local function Poll() -- the half second poll
		for _, t in ipairs(stub.timers) do
			if not t.cancelled and not t.ran then t.ran = true; t.fn(); return end
		end
	end
	Poll() -- it finds the system still not ready and looks again later
	eq(stub.replicateRequests, nil)
	stub.throttleReady = true
	for _ = 1, 3 do if not stub.replicateRequests then Poll() end end
	eq(stub.replicateRequests, 1)
	eq(M.OwnScan().state, "waiting")
end)

it("#291 never ready: after OWN_READY_SECONDS it fails with a message, nothing sent, no cooldown, retry at once", function()
	local _, stub, M, Main = Load()
	OpenAH(stub)
	stub.throttleReady = false
	M.RequestScan()
	stub.RunTimers()
	local s = M.OwnScan()
	eq(s.state, "failed"); eq(s.error, "notready")
	assert(stub.printed[#stub.printed]:find("wasn't ready for a request within 30 s", 1, true), stub.printed[#stub.printed])
	eq(Main.ScanModel().text, "Scan failed · the auction house wasn't ready")
	eq(stub.replicateRequests, nil)
	eq(M.ScanCooldown(), 0)
	eq(Main.ScanButton().label, "Scan AH"); eq(Main.ScanButton().enabled, true)
	stub.RunTimers() -- the poll is gone with the failure
	eq(stub.replicateRequests, nil)
	stub.throttleReady = true
	eq(M.RequestScan(), true)
	eq(stub.replicateRequests, 1)
end)

it("#291 closing the house while waiting for the throttle fails the click without sending anything", function()
	local _, stub, M = Load()
	OpenAH(stub)
	stub.throttleReady = false
	M.RequestScan()
	stub.Fire("AUCTION_HOUSE_CLOSED")
	eq(M.OwnScan().state, "failed"); eq(M.OwnScan().error, "closed")
	stub.throttleReady = true
	stub.Fire("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
	stub.RunTimers()
	eq(stub.replicateRequests, nil)
end)

it("#291 dropped before anything was sent: the server never got it; no cooldown, a retry at once, said so", function()
	local _, stub, M, Main = Load()
	OpenAH(stub)
	M.RequestScan()
	eq(M.ScanCooldown(), 900)
	Throttle(stub, "dropped")
	local s = M.OwnScan()
	eq(s.state, "failed"); eq(s.error, "dropped")
	eq(M.ScanCooldown(), 0, "the 15 minutes weren't used")
	eq(CraftWiseMarketDB.ownScan.requested, nil)
	assert(stub.printed[#stub.printed]:find("The game dropped the request before it was sent", 1, true), stub.printed[#stub.printed])
	assert(stub.printed[#stub.printed]:find("click again", 1, true))
	eq(Main.ScanModel().text, "Scan failed · the game dropped the request")
	eq(Main.ScanButton().label, "Scan AH"); eq(Main.ScanButton().enabled, true)
	local req = CraftWiseMarketDB.ownScan.lastRequest
	eq(req.outcome, "dropped"); eq(req.dropped, 1); eq(req.sent, 0); eq(req.readyAtClick, true)
	eq(M.RequestScan(), true)
	eq(stub.replicateRequests, 2)
	-- the earlier cooldown stays when there was one: a drop gives back only this click's
	stub.replicate = Rows(5)
	stub.Fire("REPLICATE_ITEM_LIST_UPDATE")
	eq(M.OwnScan().state, "done")
	eq(M.ScanCooldown(), 900)
end)

it("#291 a drop after the request was sent is somebody else's message: ignored", function()
	local _, stub, M = Load()
	OpenAH(stub)
	M.RequestScan()
	Throttle(stub, "sent")
	Throttle(stub, "dropped")
	eq(M.OwnScan().state, "waiting")
	eq(M.ScanCooldown(), 900)
	stub.replicate = Rows(5)
	stub.Fire("REPLICATE_ITEM_LIST_UPDATE")
	local last = CraftWiseMarketDB.ownScan.last
	eq(last.thrSent, 1); eq(last.thrDropped, 1); eq(last.thrQueued, 0)
	eq(last.rows, 5)
end)

it("#291 queued by the game: shown as queued, then sent restarts the wait for the server", function()
	local _, stub, M, Main = Load()
	OpenAH(stub)
	M.RequestScan()
	stub.clock = NOW + 3
	Throttle(stub, "queued")
	local m = Main.ScanModel()
	eq(m.text, "Queued by the game, not sent yet · 0:03 / 2:00")
	eq(m.hint, "The game's request throttle is holding it back. Keep the auction house open.")
	eq(M.OwnScan().queued, true)
	local timers = #stub.timers
	stub.clock = NOW + 40
	Throttle(stub, "sent")
	eq(M.OwnScan().queued, false)
	eq(Main.ScanModel().text, "Waiting for the server · 0:40 / 2:00")
	eq(#stub.timers, timers + 1, "a new timeout, the old one cancelled")
	assert(stub.timers[timers].cancelled, "old timeout cancelled")
	Throttle(stub, "response")
	stub.replicate = Rows(5)
	stub.Fire("REPLICATE_ITEM_LIST_UPDATE")
	local last = CraftWiseMarketDB.ownScan.last
	eq(last.thrQueued, 1); eq(last.thrSent, 1); eq(last.thrResponse, 1)
	eq(CraftWiseMarketDB.ownScan.lastRequest.outcome, "list")
end)

it("#291 queued and then dropped, never sent: the queued request was dropped, the cooldown is given back", function()
	local _, stub, M = Load()
	OpenAH(stub)
	M.RequestScan()
	Throttle(stub, "queued")
	Throttle(stub, "dropped")
	eq(M.OwnScan().error, "dropped")
	eq(M.ScanCooldown(), 0)
	eq(CraftWiseMarketDB.ownScan.lastRequest.queued, 1)
end)

it("#291 the timeout names the throttle and the events seen; the cooldown stays", function()
	local _, stub, M, Main = Load()
	OpenAH(stub)
	M.RequestScan()
	Throttle(stub, "queued")
	Throttle(stub, "response")
	stub.RunTimers()
	local s = M.OwnScan()
	eq(s.state, "failed"); eq(s.error, "timeout")
	local msg = stub.printed[#stub.printed]
	assert(msg:find("No list arrived within 120 s", 1, true), msg)
	assert(msg:find("throttle held the request back", 1, true), msg)
	assert(msg:find("Throttle events after the request: sent 0, queued 1, dropped 0.", 1, true), msg)
	eq(M.ScanCooldown(), 900)
	local req = CraftWiseMarketDB.ownScan.lastRequest
	eq(req.outcome, "timeout"); eq(req.queued, 1); eq(req.response, 1)
	assert(Main.ScanButton().tip[3]:find("Throttle events after the request", 1, true) or table.concat(Main.ScanButton().tip, "\n"):find("Throttle events", 1, true))
end)

it("#291 throttle events with no request out change nothing", function()
	local _, stub, M = Load()
	OpenAH(stub)
	Throttle(stub, "dropped"); Throttle(stub, "queued"); Throttle(stub, "sent")
	eq(M.OwnScan().state, "idle")
	eq(CraftWiseMarketDB.ownScan.lastRequest, nil)
end)

----------------------------------------------------------------------------------------------------
-- After a timeout: a late list, Try again anyway, the slow connection in the message (#291, Veli's addition)
----------------------------------------------------------------------------------------------------

it("#291 a list that comes after the timeout, inside the 15 minutes of the request, is stored as ours", function()
	local _, stub, M, Main = Load()
	OpenAH(stub)
	M.RequestScan()
	stub.RunTimers()
	eq(M.OwnScan().state, "failed"); eq(M.OwnScan().error, "timeout")
	stub.clock = NOW + 200
	stub.replicate = Rows(40)
	stub.Fire("REPLICATE_ITEM_LIST_UPDATE")
	eq(M.OwnScan().state, "done")
	eq(M.OwnScan().error, nil)
	local log = CraftWiseMarketDB.scans[HORDE]
	eq(log[#log].source, "own"); eq(log[#log].kind, "full")
	local last = CraftWiseMarketDB.ownScan.last
	eq(last.late, true); eq(last.waited, 200); eq(last.rows, 40)
	eq(CraftWiseMarketDB.ownScan.lastRequest.outcome, "list")
	eq(Main.ScanModel().kind, "done")
	assert(stub.printed[#stub.printed]:find("Scan finished: 40 rows", 1, true))
	eq(Main.ScanButton().retry, nil, "nothing to retry any more")
end)

it("#291 a list after the 15 minutes, with the house closed meanwhile, or for another failure is not claimed", function()
	local _, stub, M = Load()
	OpenAH(stub)
	M.RequestScan()
	stub.RunTimers()
	stub.clock = NOW + 901
	stub.replicate = Rows(10)
	stub.Fire("REPLICATE_ITEM_LIST_UPDATE")
	eq(CraftWiseMarketDB.scans[HORDE][1].source, "ui", "outside the window of the request")
	eq(M.OwnScan().state, "failed")
	-- a drop is no timeout: the server never got it, a list is somebody else's
	stub.clock = NOW + 5000
	OpenAH(stub)
	M.RequestScan()
	Throttle(stub, "dropped")
	stub.replicate = Rows(11)
	stub.Fire("REPLICATE_ITEM_LIST_UPDATE")
	local log = CraftWiseMarketDB.scans[HORDE]
	eq(log[#log].source, "ui")
	eq(M.OwnScan().error, "dropped")
end)

it("#291 Try again anyway: only after a timeout, bypasses the countdown once, sends again", function()
	local _, stub, M, Main = Load()
	OpenAH(stub)
	M.RequestScan()
	eq(Main.ScanButton().retry, nil, "not while the request is out")
	stub.RunTimers()
	stub.clock = NOW + 130
	local b = Main.ScanButton()
	eq(b.label, "Next scan in 12:50"); eq(b.enabled, false)
	assert(b.retry, "offered after a timeout")
	eq(b.retry.label, "Try again anyway")
	assert(table.concat(b.retry.tip, "\n"):find("The server may send nothing if it counted the first request", 1, true))
	eq(select(2, M.RequestScan()), "cooldown", "the plain click is still blocked")
	eq(M.RequestScan(true), true)
	eq(stub.replicateRequests, 2)
	eq(M.OwnScan().state, "waiting")
	eq(CraftWiseMarketDB.ownScan.requested, NOW + 130, "the cooldown counts from the new request")
	-- the first request's list arrives now: it is ours too
	stub.replicate = Rows(8)
	stub.Fire("REPLICATE_ITEM_LIST_UPDATE")
	eq(M.OwnScan().state, "done")
	-- other failures, and a cooldown that has run out, offer nothing
	stub.clock = NOW + 5000
	eq(Main.ScanButton().retry, nil)
	local _, stub2, M2, Main2 = Load()
	OpenAH(stub2)
	M2.RequestScan()
	stub2.Fire("AUCTION_HOUSE_CLOSED")
	OpenAH(stub2)
	eq(Main2.ScanButton().retry, nil, "closed is not a timeout")
	eq(M2.RequestScan(true), false, "force only works after a timeout")
end)

it("#291 the header shows Try again anyway next to Scan AH after a timeout, and the click sends", function()
	local _, stub, M, Main = Load()
	Main.Open("craft")
	local f = Main.Frame()
	OpenAH(stub)
	eq(f.head.retry:IsShown(), false)
	M.RequestScan()
	stub.RunTimers()
	Main.Refresh()
	eq(f.head.scan.label.text, "Next scan in 15:00")
	eq(f.head.retry:IsShown(), true)
	eq(f.head.retry.label.text, "Try again anyway")
	local pts = f.head.retry.points
	eq(pts[#pts][2], f.head.scan); eq(pts[#pts][1], "RIGHT")
	local sp = f.head.status.points
	eq(sp[#sp][2], f.head.retry, "the status makes room")
	f.head.retry.scripts.OnClick(f.head.retry)
	eq(stub.replicateRequests, 2)
	Main.Refresh()
	eq(f.head.retry:IsShown(), false)
	sp = f.head.status.points
	eq(sp[#sp][2], f.head.scan)
end)

it("#291 the timeout message names a slow connection and that a late list is stored", function()
	local _, stub, M = Load()
	OpenAH(stub)
	M.RequestScan()
	stub.RunTimers()
	local msg = stub.printed[#stub.printed]
	assert(msg:find("a slow or busy connection delayed the list", 1, true), msg)
	assert(msg:find("a list that still arrives within 15 minutes of the request is read and stored", 1, true), msg)
	assert(msg:find("Try again anyway", 1, true), msg)
end)
