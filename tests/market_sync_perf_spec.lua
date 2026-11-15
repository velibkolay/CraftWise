-- #241: the sync merge of a 40,000 entry file stays cheap. Veli's PC stuttered after #248: the companion
-- writes the whole market (42,531 items) and nearly every entry equals one already in CraftWiseMarketDB, but
-- each was decoded (about 20 KB of garbage) and merged at 4 ms of every frame. Invented data only.
local NOW = 1794000000
local DAY = 86400
local TODAY = math.floor(NOW / DAY)
local HORDE = "PvP|H"
local SCOPE, OTHERS = 2700, 37300 -- the market as it is: a few thousand with history, the rest last only

local function Entry(seed, older)
	local raw, days = {}, {}
	for i = 1, 4 do
		raw[i] = { t = NOW - i * 5 * 3600 + seed % 7, total = 40 + i, listings = 5, tiers = { 100 + i, 10, 120 + i, 20, 140, 30, 160, 40 } }
	end
	table.sort(raw, function(a, b) return a.t < b.t end)
	for d = 0, 29 do
		days[TODAY - d] = { lo = 90 + d, typ = 100 + d, hi = 150, qtyMax = 80, listMax = 9, n = 4 + seed % 3, gone = d % 5 }
	end
	local e = { last = { t = NOW - 100 + seed % 7, min = 100, qty = 40, listings = 5 }, raw = raw, days = days }
	if older then -- the file's copy lacks the newest point: ours is newer, the text differs, nothing to take
		table.remove(e.raw)
		e.last.t = e.last.t - 600
	end
	return e
end

-- Our data (mode "same"/"older") and the file for it. mode "new": we have nothing.
local function Setup(mode)
	local ns, stub = LoadAddon()
	time = function() return stub.clock end
	stub.clock = NOW
	local M, db = ns.Market, CraftWiseMarketDB
	db.houses[HORDE] = { realm = "PvP", kind = "faction", faction = "Horde", label = "Horde AH" }
	local own = {}
	for id = 1, SCOPE + OTHERS do
		local text
		if id <= SCOPE then
			db.scope.items[id] = true
			text = M.EncodeEntry(Entry(id))
		else
			text = M.EncodeEntry({ last = { t = NOW - 50, min = 9, qty = 2, listings = 1 } })
		end
		own[id] = text
		if mode ~= "new" then db.items[id] = { [HORDE] = text } end
	end
	local function File(written)
		local items = {}
		for id = 1, SCOPE + OTHERS do
			items[id] = { [HORDE] = (mode == "older" and id <= SCOPE) and M.EncodeEntry(Entry(id, true)) or own[id] }
		end
		return { v = 1, written = written, machine = "PC", market = { houses = { [HORDE] = {} }, items = items } }, items
	end
	return ns, stub, M, File, own
end

local function SliceClock(step)
	local queue, looks = {}, 0
	C_Timer.After = function(_, fn) queue[#queue + 1] = fn end
	debugprofilestop = function() looks = looks + 1; return looks * step end
	return function()
		local fn = table.remove(queue, 1)
		if fn then fn() end
		return fn ~= nil
	end
end

local function CountDecodes(M)
	local n, real = { count = 0 }, M.DecodeEntry
	M.DecodeEntry = function(s) n.count = n.count + 1; return real(s) end
	return n
end

local function Run(M, file, step)
	CraftWiseSync = file
	local slices, versions = 0, {}
	local v0 = M.DataVersion()
	M.StartSync()
	while step() do
		slices = slices + 1
		versions[M.DataVersion()] = true
	end
	return slices, v0, versions
end

it("#241: a file that equals what we have costs no decoding, no allocation worth the name, no cache restarts", function()
	local _, _, M, File, own = Setup("same")
	local decodes = CountDecodes(M)
	local step = SliceClock(0.25)
	local file, items = File(NOW - 10)
	collectgarbage("collect"); collectgarbage("stop")
	local k0 = collectgarbage("count")
	local slices, v0, versions = Run(M, file, step)
	local garbage = collectgarbage("count") - k0
	collectgarbage("restart")
	eq(decodes.count, 0, "nothing was decoded")
	local sync = CraftWiseMarketDB.sync
	eq(sync.same, SCOPE + OTHERS, "what it cost is kept in the saved file: all identical text"); eq(sync.skipped, 0); eq(sync.decoded, 0)
	assert(sync.slices > 0 and sync.ms >= 0 and sync.worst >= 0)
	eq(M.SyncStatus().state, "done"); eq(M.SyncStatus().changed, 0); eq(M.SyncStatus().entries, SCOPE + OTHERS)
	assert(garbage < 20000, "garbage while merging unchanged entries: " .. math.floor(garbage) .. " KB")
	eq(next(versions) == v0 and next(versions, v0) == nil, true, "DataVersion never moved, so no cache restarts per slice")
	eq(next(items), nil, "the file's strings are let go as they are merged")
	for _, id in ipairs({ 1, SCOPE, SCOPE + 1, SCOPE + OTHERS }) do
		eq(CraftWiseMarketDB.items[id][HORDE], own[id])
	end
end)

it("#241: an entry of ours that is newer than the file's (the text differs) is told apart without decoding it", function()
	local _, _, M, File, own = Setup("older")
	local decodes = CountDecodes(M)
	local step = SliceClock(0.25)
	local file = File(NOW - 10) -- built before the count: only the merge is measured
	collectgarbage("collect"); collectgarbage("stop")
	local k0 = collectgarbage("count")
	local slices, v0, versions = Run(M, file, step)
	local garbage = collectgarbage("count") - k0
	collectgarbage("restart")
	eq(decodes.count, 0, "the old version decoded 5,400 entries here (132 MB of garbage)")
	eq(M.SyncStatus().changed, 0)
	eq(M.SyncStatus().skipped, SCOPE, "read from the text"); eq(M.SyncStatus().same, OTHERS); eq(M.SyncStatus().decoded, 0)
	assert(garbage < 30000, "garbage: " .. math.floor(garbage) .. " KB")
	eq(next(versions) == v0 and next(versions, v0) == nil, true)
	for id = 1, SCOPE do eq(CraftWiseMarketDB.items[id][HORDE], own[id], "ours is untouched") end
	-- the companion rewrites the file after every upload: the same again, a new `written`, is as cheap
	decodes.count = 0
	local again = File(NOW - 5)
	Run(M, again, step)
	eq(decodes.count, 0)
	eq(M.SyncStatus().state, "done"); eq(M.SyncStatus().changed, 0)
end)

it("#241: a slice is about a millisecond: the clock is looked at after every entry, nothing in the frame that starts it", function()
	local _, _, M, File = Setup("older")
	local step = SliceClock(0.25) -- every look at the clock costs 0.25 ms
	local file = File(NOW - 10)
	CraftWiseSync = file
	local steps = 0
	local real = M.EncodeEntry
	M.StartSync()
	eq(M.SyncStatus().entries, nil, "nothing merged in the frame that starts it")
	local worst, last = 0, 0
	while step() do
		local seen = M.SyncStatus().entries or last
		worst = math.max(worst, seen - last)
		last = seen
		steps = steps + 1
	end
	assert(worst <= M.SYNC_SLICE_MS / 0.25 + 2, "a slice merged " .. worst .. " entries")
	assert(M.SYNC_SLICE_MS <= 1.5, "budget " .. M.SYNC_SLICE_MS)
	eq(M.SYNC_CHECK, 1)
	assert(steps > 1000, "spread over many frames: " .. steps)
end)

it("#241: a file the PC has nothing of (40,000 new entries) still merges in the same small slices and ends with one cache bump", function()
	local ns, _, M, File = Setup("new")
	local step = SliceClock(0.25)
	local file = File(NOW - 10)
	local seen = 0
	ns.Listen("PRICES_CHANGED", function(source) if source == "sync" then seen = seen + 1 end end)
	local slices = Run(M, file, step)
	local count = 0
	for _ in pairs(CraftWiseMarketDB.items) do count = count + 1 end
	eq(count, SCOPE + OTHERS)
	eq(M.SyncStatus().state, "done")
	eq(seen, 1, "the other windows are told once, at the end")
	assert(slices > 1000, "slices: " .. slices)
end)

it("#241: Look up's prebuild waits for a running merge instead of restarting on every key it adds", function()
	local ns, stub = LoadAddon()
	time = function() return stub.clock end
	stub.clock = NOW
	local M = ns.Market
	CraftWiseMarketDB.houses[HORDE] = { realm = "PvP", kind = "faction", faction = "Horde", label = "Horde AH" }
	CraftWiseMarketDB.scope.items[100] = true
	local entries = {}
	for id = 1, 300 do entries[id] = { [HORDE] = M.EncodeEntry({ last = { t = NOW - id, min = 10, qty = 1 } }) } end
	CraftWiseSync = { v = 1, written = NOW - 10, machine = "PC", market = { houses = { [HORDE] = {} }, items = entries } }
	stub.Fire("PLAYER_LOGIN") -- the sync start and the prebuild are waiting as timers
	local step = SliceClock(0.25)
	local Items = ns.Main.Items
	stub.RunTimers() -- both fire: the merge starts, the prebuild finds it running
	eq(M.SyncBusy(), true)
	eq(Items.cacheBuilds, 0)
	while M.SyncBusy() do assert(step(), "the merge ends") end
	while step() do end
	eq(Items.cacheBuilds, 0, "the prebuild has not started while the merge ran")
	stub.RunTimers() -- the prebuild looks again
	while step() do end
	eq(Items.cacheBuilds, 1, "and builds once it is over")
end)
