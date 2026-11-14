-- Performance recorder (#194): Core.lua reports handler run times while Settings > Debug > Record is on,
-- Perf.lua keeps the numbers and builds the report. Invented numbers only (stub.clock moves the clock).
local function Load()
	local ns, stub = LoadAddon()
	stub.printed = {}
	ns.Print = function(m) stub.printed[#stub.printed + 1] = tostring(m) end
	stub.Fire("PLAYER_LOGIN")
	return ns, stub, ns.Main
end

local function has(text, part)
	assert(text and text:find(part, 1, true), "missing '" .. part .. "' in: " .. tostring(text))
end

it("recording off: handlers run, nothing is timed or kept", function()
	local ns, stub = Load()
	local ran = 0
	ns.On("PERF_TEST", function() ran = ran + 1; stub.clock = stub.clock + 50 end)
	ns.Fire("PERF_TEST")
	eq(ran, 1)
	eq(ns.Perf.IsRecording(), false)
	eq(ns.Perf.Text(), nil)
end)

it("recording: each handler's time, count and longest run per event, with its registration label", function()
	local ns, stub = Load()
	stub.stack = 'Interface\\AddOns\\CraftWise\\Core.lua:30: in function <Interface\\AddOns\\CraftWise\\Core.lua:29>\n'
		.. 'Interface\\AddOns\\CraftWise\\UI\\Main\\Pages\\Bags.lua:41: in main chunk'
	ns.On("PERF_TEST", function() stub.clock = stub.clock + 12 end)
	stub.stack = 'Interface\\AddOns\\CraftWise\\Holdings.lua:77: in main chunk'
	ns.On("PERF_TEST", function() stub.clock = stub.clock + 3 end)
	ns.Perf.Start()
	eq(ns.Perf.IsRecording(), true)
	ns.Fire("PERF_TEST")
	ns.Fire("PERF_TEST")
	stub.clock = stub.clock + 1000
	local lines = ns.Perf.Stop()
	eq(ns.Perf.IsRecording(), false)
	local text = table.concat(lines, "\n")
	has(text, "PERF_TEST Main/Pages/Bags.lua:41: 24.0 ms | 2x | 12.0 ms")
	has(text, "PERF_TEST Holdings.lua:77: 6.0 ms | 2x | 3.0 ms")
	has(text, "PERF_TEST: 30.0 ms | 4x | 12.0 ms") -- the event, all its handlers together
	has(text, "recorded 1.0 s")
	eq(ns.Perf.Text(), text)
	-- once stopped, nothing more is kept
	ns.Fire("PERF_TEST")
	eq(ns.Perf.Text(), text)
end)

it("module callbacks and timed hooks are listed; a timed hook passes its result on", function()
	local ns, stub = Load()
	ns.Listen("PERF_NOTE", function() stub.clock = stub.clock + 7 end)
	local hook = ns.Timed("BagIcons: test hook", function(a) stub.clock = stub.clock + 4; return a * 2 end)
	eq(hook(5), 10, "not recording")
	ns.Perf.Start()
	ns.Notify("PERF_NOTE")
	eq(hook(21), 42, "recording")
	local text = table.concat(ns.Perf.Stop(), "\n")
	has(text, "Module callbacks")
	has(text, "PERF_NOTE")
	has(text, "7.0 ms | 1x | 7.0 ms")
	has(text, "Hooks on bag frames")
	has(text, "BagIcons: test hook: 4.0 ms | 1x | 4.0 ms")
end)

it("slow frames: logged with the CraftWise time inside them and the slowest handler", function()
	local ns, stub = Load()
	ns.On("PERF_TEST", function() stub.clock = stub.clock + 20 end)
	ns.Perf.Start()
	local tick = ns.Perf.ticker.scripts.OnUpdate
	stub.clock = stub.clock + 16
	tick(ns.Perf.ticker, 0.016) -- the first frame (the click) is ignored
	stub.clock = stub.clock + 16
	tick(ns.Perf.ticker, 0.016)
	ns.Fire("PERF_TEST")
	stub.clock = stub.clock + 60
	tick(ns.Perf.ticker, 0.08) -- an 80 ms frame with 20 ms of CraftWise in it
	local text = table.concat(ns.Perf.Stop(), "\n")
	has(text, "Frames: worst 80.0 ms; over 33 ms: 1, over 50 ms: 1, over 100 ms: 0")
	has(text, "Slowest frames")
	has(text, "80.0 ms | 20.0 ms | PERF_TEST")
end)

it("other addons: slow ticks during the recording, top addons by metric; missing profiler API does not raise", function()
	local ns, stub = Load()
	local over10 = { CraftWise = 0, Auctionator = 2 }
	C_AddOns = {
		GetNumAddOns = function() return 2 end,
		GetAddOnName = function(i) return ({ "CraftWise", "Auctionator" })[i] end,
		IsAddOnLoaded = function() return true end,
	}
	C_AddOnProfiler = {
		GetAddOnMetric = function(name, metric)
			if metric == 7 then return over10[name] end
			if metric == 1 then return name == "Auctionator" and 1.5 or 0.5 end
			return 0
		end,
		GetTopKAddOnsForMetric = function(metric, k)
			return { { addOnName = "Auctionator", metricValue = 1.5 }, { addOnName = "CraftWise", metricValue = 0.5 } }
		end,
	}
	ns.Perf.Start()
	over10.Auctionator = 5 -- three more slow ticks while recording
	local text = table.concat(ns.Perf.Stop(), "\n")
	has(text, "Auctionator: 0 / 3 / 0 / 0; 1.5 ms")
	has(text, "CraftWise: 0 / 0 / 0 / 0; 0.5 ms")
	has(text, "Top addons by recent average")
	has(text, "1. Auctionator  1.5 ms")
	C_AddOnProfiler, C_AddOns = nil, nil
	ns.Perf.Start()
	ns.Perf.Stop()
end)

it("Settings > Debug: Record toggles, Copy report opens the box with the text, Clear empties it", function()
	local ns, stub, M = Load()
	M.Open("settings")
	M.Settings.SelectGroup("debug")
	local row = M.Settings.RowOf("debug", "buttons")
	local rec, copy, clear = row.holder.buttons[1], row.holder.buttons[2], row.holder.buttons[3]
	eq(rec.label.text, "Record")
	rec.scripts.OnClick(rec)
	eq(ns.Perf.IsRecording(), true)
	eq(M.Settings.RowOf("debug", "buttons").holder.buttons[1].label.text, "Stop")
	has(ns.Perf.Status(), "Recording")
	rec.scripts.OnClick(rec)
	eq(ns.Perf.IsRecording(), false)
	has(ns.Perf.Status(), "CraftWise performance")
	copy.scripts.OnClick(copy)
	local box = CraftWisePerfCopy.box
	has(box.text, "CraftWise performance")
	eq(CraftWisePerfCopy.shown, true)
	clear.scripts.OnClick(clear)
	eq(ns.Perf.Text(), nil)
	has(ns.Perf.Status(), "Nothing recorded")
end)
