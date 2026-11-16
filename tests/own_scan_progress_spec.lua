-- Own AH scan: what it says while it runs (#285). The phases (waiting for the server, reading, storing, done,
-- failed) with their numbers, bars and hints in the header and on the bar under the auction house, the
-- estimate that is only worked out from measured progress, and the button that counts down to the next
-- scan with a tooltip that says why. Invented data only.
local NOW = 1794000000

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

local function Items(n)
	local rows = {}
	for i = 1, n do rows[i] = { itemID = 1000 + i, count = 1, buyout = 10, link = "item:" .. i } end
	return rows
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

local function Tip(model) return table.concat(model.tip, "\n") end

it("#285 waiting: the seconds and the timeout, a bar that fills towards it, keep the AH open", function()
	local _, stub, M, Main = Load()
	OpenAH(stub)
	eq(Main.ScanModel(), nil, "nothing to show before a click")
	M.RequestScan()
	stub.clock = NOW + 23
	local m = Main.ScanModel()
	eq(m.kind, "scanning"); eq(m.state, "waiting")
	eq(m.text, "Waiting for the server · 0:23 / 2:00")
	assert(math.abs(m.fraction - 23 / 120) < 1e-9)
	eq(m.hint, "Keep the auction house open.")
	eq(Main.ScanButton().label, "Waiting · 0:23 / 2:00")
	eq(Main.Clock(119.9), "1:59"); eq(Main.Clock(0), "0:00")
end)

it("#285 reading: rows read of rows, the percentage, a bar; header status and progress line follow", function()
	local ns, stub, M, Main = Load()
	Main.Open("craft")
	local f = Main.Frame()
	OpenAH(stub)
	M.RequestScan()
	local hold = Hold()
	stub.replicate = Items(1200)
	stub.Fire("REPLICATE_ITEM_LIST_UPDATE")
	local p = M.ScanProgress()
	eq(p.phase, "read"); eq(p.done, 500); eq(p.total, 1200)
	local m = Main.ScanModel()
	eq(m.text, "Reading the list · 500 of 1 200 · 41 %")
	assert(math.abs(m.fraction - 500 / 1200) < 1e-9)
	eq(m.hint, "Keep the auction house open.")
	eq(Main.ScanButton().label, "Reading · 41 %")
	Main.Refresh()
	eq(f.head.status.text, ns.Style.Hex("live") .. "Reading the list · 500 of 1 200 · 41 %|r")
	eq(f.progress.shown, true)
	assert(math.abs(f.progress.fill.width - 880 * 500 / 1200) < 1e-6, f.progress.fill.width)
	hold.step()
	eq(Main.ScanModel().text, "Reading the list · 1 000 of 1 200 · 83 %")
	hold.release()
end)

it("#285 storing: items stored of items to store with a bar, and closing the auction house is safe", function()
	local _, stub, M, Main = Load()
	OpenAH(stub)
	M.RequestScan()
	local hold = Hold()
	stub.replicate = Items(2400)
	stub.Fire("REPLICATE_ITEM_LIST_UPDATE")
	while M.OwnScan().state == "reading" and hold.pending() > 0 do hold.step() end
	eq(M.OwnScan().state, "storing")
	local p = M.ScanProgress()
	eq(p.phase, "store"); eq(p.total, 2400, "items to store, not rows")
	assert(p.done >= 1 and p.done <= 1000, "first frame stored up to 1000: " .. p.done)
	local m = Main.ScanModel()
	assert(m.text:find("^Storing prices · "), m.text)
	assert(m.text:find(" of 2 400 · ", 1, true), m.text)
	eq(m.hint, "Closing the auction house is safe now.")
	eq(Main.ScanButton().label, ("Storing · %d %%"):format(math.floor(m.fraction * 100)))
	local before = m.fraction
	hold.step()
	assert(Main.ScanModel().fraction > before, "the bar moves while it stores")
	while hold.pending() > 0 do hold.step() end
	hold.release()
	eq(M.OwnScan().state, "done")
end)

it("#285 the estimate: only from progress measured so far, after 3 s and 5 %, labelled with the approx sign", function()
	local _, stub, M, Main = Load()
	OpenAH(stub)
	M.RequestScan()
	local hold = Hold()
	stub.replicate = Items(1200)
	stub.Fire("REPLICATE_ITEM_LIST_UPDATE") -- 500 of 1 200 read
	eq(Main.ScanModel().eta, nil, "no time has passed: no estimate")
	stub.clock = NOW + 2
	eq(Main.ScanModel().eta, nil, "under 3 s")
	stub.clock = NOW + 10
	eq(Main.ScanModel().eta, 14, "10 s for 500 rows: 700 more take 14 s")
	assert(Tip(Main.ScanButton()):find("≈ 0:14 left (worked out from the progress so far)", 1, true), Tip(Main.ScanButton()))
	hold.release()
	-- a waiting scan has none: the server's time is unknown
	local _, stub2, M2, Main2 = Load()
	OpenAH(stub2)
	M2.RequestScan()
	stub2.clock = NOW + 60
	eq(Main2.ScanModel().eta, nil)
end)

it("#285 done: one line (rows, items, time) that stays 10 s; the button counts down as Next scan in", function()
	local ns, stub, M, Main = Load()
	Main.Open("craft")
	local f = Main.Frame()
	OpenAH(stub)
	M.RequestScan()
	stub.clock = NOW + 7
	stub.replicate = Items(1200)
	stub.Fire("REPLICATE_ITEM_LIST_UPDATE")
	eq(M.OwnScan().state, "done")
	local m = Main.ScanModel()
	eq(m.kind, "done"); eq(m.text, "Scan done · 1 200 rows · 1 200 items · 0:07")
	eq(m.fraction, 1)
	eq(m.hint, "Everything is stored. The button now counts down to the next scan.")
	Main.Refresh()
	eq(f.head.status.text, "Scan done · 1 200 rows · 1 200 items · 0:07")
	eq(f.head.status.textColor[1], ns.Style.C.text[1], "not the grey of the age line")
	eq(f.head.status.fontObject, ns.Style.Fonts.Label)
	eq(f.progress.shown, false)
	stub.clock = NOW + 7 + 10
	assert(Main.ScanModel(), "still there at 10 s")
	stub.clock = NOW + 7 + 11
	eq(Main.ScanModel(), nil, "gone after 10 s")
	Main.Refresh()
	assert(f.head.status.text:find("Horde AH", 1, true) and f.head.status.text:find("ago", 1, true), f.head.status.text)
	-- the countdown is labelled and explained (it restarted when the list arrived, 7 s in)
	local b = Main.ScanButton()
	eq(b.label, "Next scan in 14:49"); eq(b.enabled, false)
	assert(Tip(b):find("Next scan in 14:49.", 1, true), Tip(b))
	assert(Tip(b):find("starts when the request is sent, not when the list arrives", 1, true), Tip(b))
	assert(Tip(b):find("runs after a failed scan or a closed auction house too", 1, true), Tip(b))
	assert(Tip(b):find("Last own scan", 1, true))
end)

it("#285 failed: the reason in red until the next click; the countdown after a closed house is explained", function()
	local ns, stub, M, Main = Load()
	Main.Open("craft")
	local f = Main.Frame()
	OpenAH(stub)
	M.RequestScan()
	stub.Fire("AUCTION_HOUSE_CLOSED")
	OpenAH(stub)
	local m = Main.ScanModel()
	eq(m.kind, "failed"); eq(m.text, "Scan failed · the auction house was closed")
	eq(m.hint, "The auction house closed before the list was read. Nothing was stored.")
	Main.Refresh()
	eq(f.head.status.text, "Scan failed · the auction house was closed")
	eq(f.head.status.textColor[1], ns.Style.C.danger[1])
	stub.clock = NOW + 600
	assert(Main.ScanModel(), "no timer on a failure: it stays")
	local b = Main.ScanButton()
	eq(b.label, "Next scan in 5:00")
	local tip = Tip(b)
	assert(tip:find("The countdown starts when the request is sent, not when the list arrives", 1, true), tip)
	assert(tip:find(ns.Style.Hex("danger") .. "The auction house closed before the list was read.", 1, true), tip)
	-- cooldown over: the failure is still said, the button is ready, the next click clears it
	stub.clock = NOW + 901
	b = Main.ScanButton()
	eq(b.label, "Scan AH"); eq(b.enabled, true)
	assert(Tip(b):find("The auction house closed before the list was read.", 1, true))
	M.RequestScan()
	eq(Main.ScanModel().kind, "scanning")
	-- a timeout, short
	stub.RunTimers()
	eq(Main.ScanModel().text, "Scan failed · no list within 2:00")
end)

it("#285 the bar under the auction house: text, bar, hint; done stays 10 s; hidden with the auction house", function()
	local _, stub, M, Main = Load()
	_G.AuctionHouseFrame = CreateFrame("Frame", "AuctionHouseFrame", UIParent)
	OpenAH(stub)
	eq(Main.AHBar(), nil, "nothing is built before a scan was asked for")
	M.RequestScan()
	local bar = Main.AHBar()
	assert(bar and bar:IsShown(), "bar shown while waiting")
	eq(bar.text.text, "Waiting for the server · 0:00 / 2:00")
	eq(bar.hint.text, "Keep the auction house open.")
	eq(bar.track.shown, true)
	local hold = Hold()
	stub.clock = NOW + 4
	stub.replicate = Items(1200)
	stub.Fire("REPLICATE_ITEM_LIST_UPDATE")
	bar.scripts.OnUpdate(bar, 0.3) -- the bar polls itself while it is shown
	eq(bar.text.text, "Reading the list · 500 of 1 200 · 41 %")
	assert(math.abs(bar.fill.width - 612 * 500 / 1200) < 1e-6, bar.fill.width)
	stub.clock = NOW + 14
	bar.scripts.OnUpdate(bar, 0.3)
	assert(bar.hint.text:find("≈ 0:14 left", 1, true), bar.hint.text)
	while hold.pending() > 0 do hold.step() end
	hold.release()
	bar.scripts.OnUpdate(bar, 0.3)
	eq(bar.text.text, "Scan done · 1 200 rows · 1 200 items · 0:14")
	eq(bar.fill.width, 612)
	stub.clock = stub.clock + 11
	bar.scripts.OnUpdate(bar, 0.3)
	eq(bar:IsShown(), false, "the summary went")
	-- failed: shown until the next click; the house's frame hidden hides it
	stub.clock = stub.clock + 2000
	M.RequestScan()
	stub.RunTimers()
	assert(bar:IsShown(), "failure stays")
	eq(bar.text.text, "Scan failed · no list within 2:00")
	eq(bar.track.shown, false, "no bar for a failure")
	_G.AuctionHouseFrame:Hide()
	Main.UpdateAHBar()
	eq(bar:IsShown(), false)
	_G.AuctionHouseFrame = nil
end)

----------------------------------------------------------------------------------------------------
-- The bar must not cover the auction house's tabs (#297)
----------------------------------------------------------------------------------------------------

local function Host(stub)
	local host = CreateFrame("Frame", "AuctionHouseFrame", UIParent)
	_G.AuctionHouseFrame = host
	-- the tabs, Blizzard's and the ones addons add, hang below the frame
	host.tabs = {}
	for i = 1, 8 do host.tabs[i] = CreateFrame("Button", nil, host) end
	return host
end

it("#297 the bar sits above the auction house window, never over its tabs, and takes no mouse input", function()
	local _, stub, M, Main = Load()
	local host = Host(stub)
	OpenAH(stub)
	M.RequestScan()
	local bar = Main.AHBar()
	assert(bar and bar:IsShown())
	for _, p in ipairs(bar.points) do
		assert(p[2] == host, "anchored to the auction house frame")
		assert(p[3] == "TOPLEFT" or p[3] == "TOPRIGHT", "to its top edge, not its bottom where the tabs are: " .. tostring(p[3]))
		assert(p[1] == "BOTTOMLEFT" or p[1] == "BOTTOMRIGHT", "the bar's own bottom edge touches it: " .. tostring(p[1]))
		assert(p[5] > 0, "a few units above")
	end
	eq(#bar.points, 2)
	eq(bar.mouseEnabled, false, "mouse-transparent: clicks go through, even where it is pushed over the frame")
	eq(bar:IsMouseEnabled(), false)
	-- nothing in it takes the mouse either
	for _, region in ipairs({ bar.text, bar.hint, bar.fill, bar.track }) do
		assert(not region.mouseEnabled, "no mouse on its parts")
	end
	-- the bar is the only thing CraftWise anchors to the AH frame
	for _, fr in ipairs(stub.frames) do
		if fr ~= bar and fr ~= _G.CraftWiseAHPanel then -- the buy panel (#315) docks to it by design
			for _, p in ipairs(fr.points or {}) do
				assert(p[2] ~= host or fr == bar, "only the scan bar is anchored to the AH frame")
			end
		end
	end
	_G.AuctionHouseFrame = nil
end)

it("#297 a done or failed line leaves the bar after M.AH_BAR_LINGER seconds; the header keeps it", function()
	local _, stub, M, Main = Load()
	Host(stub)
	OpenAH(stub)
	eq(Main.AH_BAR_LINGER, 6)
	M.RequestScan()
	stub.clock = NOW + 3
	stub.replicate = Items(20)
	stub.Fire("REPLICATE_ITEM_LIST_UPDATE")
	local bar = Main.AHBar()
	eq(M.OwnScan().state, "done")
	stub.clock = NOW + 3 + 5
	bar.scripts.OnUpdate(bar, 0.3)
	eq(bar:IsShown(), true, "still there after 5 s")
	stub.clock = NOW + 3 + 7
	bar.scripts.OnUpdate(bar, 0.3)
	eq(bar:IsShown(), false, "gone after 6 s")
	assert(Main.ScanModel(), "the header's summary stays 10 s")
	-- failed: the same, while the header keeps the failure until the next click
	stub.clock = NOW + 3000
	M.RequestScan()
	stub.RunTimers()
	eq(M.OwnScan().error, "timeout")
	assert(bar:IsShown(), "shown when it failed")
	stub.clock = NOW + 3000 + 7
	bar.scripts.OnUpdate(bar, 0.3)
	eq(bar:IsShown(), false)
	eq(Main.ScanModel().kind, "failed", "the header still says it")
	_G.AuctionHouseFrame = nil
end)

it("#297 Settings > Look: the scan bar can be switched off; on by default", function()
	local _, stub, M, Main = Load()
	Host(stub)
	eq(Main.UI().ahBar, true)
	OpenAH(stub)
	M.RequestScan()
	local bar = Main.AHBar()
	eq(bar:IsShown(), true)
	Main.Open("settings")
	Main.Settings.SelectGroup("look")
	local row = Main.Settings.RowOf("look", "ahBar")
	assert(row, "the row")
	local box = row.holder.control
	box.scripts.OnClick(box)
	eq(Main.UI().ahBar, false)
	eq(bar:IsShown(), false, "off: gone at once")
	stub.clock = NOW + 5
	Main.UpdateAHBar()
	eq(bar:IsShown(), false)
	box.scripts.OnClick(box)
	eq(Main.UI().ahBar, true)
	eq(bar:IsShown(), true)
	_G.AuctionHouseFrame = nil
end)
