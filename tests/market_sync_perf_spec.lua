-- #241: the sync merge of a 40,000 entry file stays cheap. Veli's PC stuttered after #248: the companion
-- writes the whole market (42,531 items) and nearly every entry equals one already in CraftWiseMarketDB, but
-- each was decoded (about 20 KB of garbage) and merged at 4 ms of every frame in world. Now it is merged while
-- the loading screen is up, and an entry that changes nothing is read from its text. Invented data only.
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

local function CountDecodes(M)
	local n, real = { count = 0 }, M.DecodeEntry
	M.DecodeEntry = function(s) n.count = n.count + 1; return real(s) end
	return n
end

-- The merge as the login handler runs it: one call, no frame and no timer of its own (the windows that listen
-- to PRICES_CHANGED may use theirs: `listeners`).
local function Login(M, file, listeners)
	local after, timer = C_Timer.After, C_Timer.NewTimer
	if not listeners then
		C_Timer.After = function() error("the merge asked for a frame") end
		C_Timer.NewTimer = function() error("the merge asked for a timer") end
	end
	CraftWiseSync = file
	local t = os.clock()
	local state = M.StartSync()
	local took = os.clock() - t
	C_Timer.After, C_Timer.NewTimer = after, timer
	return state, took
end

it("#241: a file that equals what we have costs no decoding, no allocation worth the name, no cache restarts", function()
	local _, _, M, File, own = Setup("same")
	local decodes = CountDecodes(M)
	local file, items = File(NOW - 10)
	local v0 = M.DataVersion()
	collectgarbage("collect"); collectgarbage("stop")
	local k0 = collectgarbage("count")
	local state, took = Login(M, file)
	local garbage = collectgarbage("count") - k0
	collectgarbage("restart")
	eq(state, "done")
	eq(decodes.count, 0, "nothing was decoded")
	local sync = CraftWiseMarketDB.sync
	eq(sync.same, SCOPE + OTHERS, "what it cost is kept in the saved file: all identical text"); eq(sync.skipped, 0); eq(sync.decoded, 0)
	eq(M.SyncStatus().changed, 0); eq(M.SyncStatus().entries, SCOPE + OTHERS)
	assert(garbage < 20000, "garbage while merging unchanged entries: " .. math.floor(garbage) .. " KB")
	assert(took < 3, "seconds: " .. took)
	eq(M.DataVersion(), v0, "DataVersion never moved, so no cache restarts")
	eq(next(items), nil, "the file's strings are let go as they are merged")
	for _, id in ipairs({ 1, SCOPE, SCOPE + 1, SCOPE + OTHERS }) do
		eq(CraftWiseMarketDB.items[id][HORDE], own[id])
	end
end)

it("#241: an entry of ours that is newer than the file's (the text differs) is told apart without decoding it", function()
	local _, _, M, File, own = Setup("older")
	local decodes = CountDecodes(M)
	local file = File(NOW - 10) -- built before the count: only the merge is measured
	local v0 = M.DataVersion()
	collectgarbage("collect"); collectgarbage("stop")
	local k0 = collectgarbage("count")
	local state, took = Login(M, file)
	local garbage = collectgarbage("count") - k0
	collectgarbage("restart")
	eq(state, "done")
	eq(decodes.count, 0, "the old version decoded 5,400 entries here (132 MB of garbage)")
	eq(M.SyncStatus().changed, 0)
	eq(M.SyncStatus().skipped, SCOPE, "read from the text"); eq(M.SyncStatus().same, OTHERS); eq(M.SyncStatus().decoded, 0)
	assert(garbage < 30000, "garbage: " .. math.floor(garbage) .. " KB")
	assert(took < 3, "seconds: " .. took) -- about 0.3 s headless; the loading screen's budget is M.SYNC_LOGIN_MS
	eq(M.DataVersion(), v0)
	for id = 1, SCOPE do eq(CraftWiseMarketDB.items[id][HORDE], own[id], "ours is untouched") end
	-- the companion rewrites the file after every upload: the same again, a new `written`, is as cheap
	decodes.count = 0
	local again = File(NOW - 5)
	eq(Login(M, again), "done")
	eq(decodes.count, 0)
	eq(M.SyncStatus().changed, 0)
end)

it("#241: a file the PC has nothing of (40,000 new entries) merges in one call and ends with one cache bump", function()
	local ns, _, M, File = Setup("new")
	local file = File(NOW - 10)
	local seen = 0
	ns.Listen("PRICES_CHANGED", function(source) if source == "sync" then seen = seen + 1 end end)
	M.SYNC_LOGIN_MS = 10 ^ 9 -- the loading screen's budget is for real clocks
	local state = Login(M, file, true)
	local count = 0
	for _ in pairs(CraftWiseMarketDB.items) do count = count + 1 end
	eq(state, "done")
	eq(count, SCOPE + OTHERS)
	eq(seen, 1, "the other windows are told once, at the end")
end)

it("#241: with no file there is nothing to do, and a /reload without a new file costs nothing", function()
	local _, _, M, File = Setup("same")
	eq(M.StartSync(), "none")
	local file = File(NOW - 10)
	eq(Login(M, file), "done")
	local again = File(NOW - 10) -- the same `written`: not even looked at
	local decodes = CountDecodes(M)
	local state, took = Login(M, again)
	eq(state, "unchanged"); eq(decodes.count, 0)
	assert(took < 0.05, "seconds: " .. took)
end)
