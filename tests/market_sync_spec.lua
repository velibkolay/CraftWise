-- Two machines (#241, part of #237): the CraftWise_Sync file the companion writes is merged into
-- CraftWiseMarketDB. Entries in the packed format, invented data only.
local NOW = 1794000000
local DAY = 86400
local HORDE, BOOTY = "H", "N:BootyBay"
local TODAY = math.floor(NOW / DAY)

local function Market(opts)
	local ns, stub = LoadAddon(opts)
	time = function() return stub.clock end
	stub.clock = NOW
	return ns.Market, stub, ns
end

local function InScope(items)
	for _, id in ipairs(items) do CraftWiseMarketDB.scope.items[id] = true end
end

local function Point(t, price, qty)
	return { t = t, total = qty, listings = 2, tiers = { price, qty } }
end

local function Day(lo, n, gone)
	return { lo = lo, typ = lo + 5, hi = lo + 20, qtyMax = 50, listMax = 4, n = n, gone = gone }
end

-- The house record the sync file carries (the addon makes its own from the key).
local FACTION = { realm = "PvP", kind = "faction", faction = "Horde", label = "Horde AH" }

local function File(items, extra)
	local file = { v = 1, written = NOW - 60, machine = "MacBook", market = { houses = { [HORDE] = FACTION }, items = items } }
	for k, v in pairs(extra or {}) do file.market[k] = v end
	return file
end

local function Merge(M, file)
	CraftWiseSync = file
	return M.StartSync()
end

local function Stored(M, itemKey, house)
	local e = CraftWiseMarketDB.items[itemKey] and CraftWiseMarketDB.items[itemKey][house or HORDE]
	if type(e) == "string" then return M.DecodeEntry(e) end
	return e
end

-- Everything stored, as one comparable text.
local function Dump(M)
	local keys = {}
	for key in pairs(CraftWiseMarketDB.items) do keys[#keys + 1] = key end
	table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
	local out = {}
	for _, key in ipairs(keys) do
		local houses = {}
		for house in pairs(CraftWiseMarketDB.items[key]) do houses[#houses + 1] = house end
		table.sort(houses)
		for _, house in ipairs(houses) do
			local e = CraftWiseMarketDB.items[key][house]
			out[#out + 1] = tostring(key) .. "@" .. house .. "=" .. (type(e) == "string" and e or M.EncodeEntry(e))
		end
	end
	return table.concat(out, "\n")
end

local function Printed(fn)
	local lines, realPrint = {}, print
	print = function(s) lines[#lines + 1] = tostring(s) end
	local ok, err = pcall(fn)
	print = realPrint
	assert(ok, err)
	return table.concat(lines, "\n")
end

------------------------------------------------------------------------------------- the file

it("#241: no CraftWise_Sync addon: nothing happens, no error, the login timer is harmless", function()
	local M, stub = Market()
	local before = M.DataVersion()
	eq(M.StartSync(), "none")
	stub.Fire("PLAYER_LOGIN")
	stub.RunTimers()
	eq(M.SyncStatus().state, "none")
	eq(next(CraftWiseMarketDB.items), nil)
	eq(M.DataVersion(), before)
	CraftWiseSync = {} -- the addon is there but holds no market
	eq(M.StartSync(), "none")
	CraftWiseSync = { v = 1, written = NOW, market = "junk" }
	eq(M.StartSync(), "none")
end)

it("#241: another format version is left alone", function()
	local M = Market()
	InScope({ 100 })
	local file = File({ [100] = { [HORDE] = M.EncodeEntry({ last = { t = NOW, min = 5, qty = 1 } }) } })
	file.v = 2
	eq(Merge(M, file), "unsupported")
	eq(next(CraftWiseMarketDB.items), nil)
	eq(CraftWiseMarketDB.sync, nil)
end)

it("#241: the file is merged at login, while the loading screen is up: nothing is left for the world, the other windows are told once", function()
	local M, stub, ns = Market()
	InScope({ 100 })
	local seen = 0
	ns.Listen("PRICES_CHANGED", function(source) if source == "sync" then seen = seen + 1 end end)
	local full = 0
	ns.Listen("FULL_PRICES", function() full = full + 1 end) -- #345: the check Loops runs after a sync
	CraftWiseSync = File({ [100] = { [HORDE] = M.EncodeEntry({ last = { t = NOW - 100, min = 90, qty = 12, listings = 3 } }) } })
	local v0 = M.DataVersion()
	local hooks = {}
	ns.SetRecorder(function(kind, _, label) hooks[#hooks + 1] = kind .. "|" .. label end)
	stub.Fire("PLAYER_LOGIN")
	local labelled = false
	for _, line in ipairs(hooks) do labelled = labelled or line == "hook|Market: sync merge (login)" end
	eq(labelled, true, "Settings > Debug lists it under its own label")
	eq(Stored(M, 100).last.min, 90, "there when the login handlers return")
	eq(M.Current(100, HORDE).min, 90)
	assert(M.DataVersion() ~= v0, "caches keyed on the data version restart")
	eq(seen, 1)
	eq(full, 1, "a sync is a full price set: FULL_PRICES once")
	eq(M.SyncStatus().state, "done")
	eq(M.SyncStatus().machine, "MacBook")
	eq(M.SyncBusy(), false)
	eq(CraftWiseSync.market, nil, "the strings are let go once merged")
end)

------------------------------------------------------------------------------------- the merge rules

it("#241: an entry the other machine has and this one doesn't is added with its history, packed", function()
	local M = Market()
	InScope({ 100 })
	local theirs = { last = { t = NOW - 100, min = 90, qty = 12, listings = 3 },
		raw = { Point(NOW - 3600, 95, 10), Point(NOW - 100, 90, 12) },
		days = { [TODAY] = Day(88, 2, 7), [TODAY - 3] = Day(70, 4, 11) } }
	eq(Merge(M, File({ [100] = { [HORDE] = M.EncodeEntry(theirs) } })), "done")
	eq(type(CraftWiseMarketDB.items[100][HORDE]), "string", "stored packed")
	local e = Stored(M, 100)
	eq(e.last.min, 90); eq(#e.raw, 2); eq(e.raw[1].t, NOW - 3600); eq(e.days[TODAY].n, 2); eq(e.days[TODAY - 3].lo, 70)
	eq(M.Disappeared(100, HORDE), 18, "the disappeared counts of the last 7 days come along (7 today, 11 three days ago)")
	eq(CraftWiseMarketDB.houses[HORDE].label, "Horde AH", "the house is made")
	eq(CraftWiseMarketDB.houses[HORDE].faction, "Horde")
	eq(M.ItemKeys(100)[1], 100, "the key index knows it")
	eq(CraftWiseMarketDB.sync.written, NOW - 60)
	eq(CraftWiseMarketDB.sync.machine, "MacBook")
end)

it("#241: last: the newer t wins, own or synced, own on a tie", function()
	local M = Market()
	InScope({ 100, 101, 102 })
	local function Own(id, t, min)
		CraftWiseMarketDB.houses[HORDE] = FACTION
		CraftWiseMarketDB.items[id] = { [HORDE] = M.EncodeEntry({ last = { t = t, min = min, qty = 1 } }) }
	end
	local function Theirs(t, min) return { [HORDE] = M.EncodeEntry({ last = { t = t, min = min, qty = 2 } }) } end
	Own(100, NOW - 1000, 50); Own(101, NOW - 1000, 50); Own(102, NOW - 1000, 50)
	Merge(M, File({ [100] = Theirs(NOW - 10, 40), [101] = Theirs(NOW - 2000, 40), [102] = Theirs(NOW - 1000, 40) }))
	eq(Stored(M, 100).last.min, 40, "theirs is newer")
	eq(Stored(M, 101).last.min, 50, "own is newer")
	eq(Stored(M, 102).last.min, 50, "a tie keeps own")
end)

it("#241: raw: union by t, kept to 48 h, in order", function()
	local M = Market()
	InScope({ 100 })
	CraftWiseMarketDB.houses[HORDE] = FACTION
	local mine = { last = { t = NOW - 1000, min = 50, qty = 5 }, raw = { Point(NOW - 7200, 55, 5), Point(NOW - 1000, 50, 5) }, days = {} }
	CraftWiseMarketDB.items[100] = { [HORDE] = M.EncodeEntry(mine) }
	local theirs = { last = { t = NOW - 300, min = 45, qty = 9 },
		raw = { Point(NOW - 50 * 3600, 99, 1), Point(NOW - 7200, 55, 5), Point(NOW - 3600, 52, 7), Point(NOW - 300, 45, 9) }, days = {} }
	Merge(M, File({ [100] = { [HORDE] = M.EncodeEntry(theirs) } }))
	local e = Stored(M, 100)
	eq(#e.raw, 4, "the point both have counts once, the one older than 48 h is not taken")
	local ts = {}
	for i, p in ipairs(e.raw) do ts[i] = p.t end
	eq(table.concat(ts, ","), table.concat({ NOW - 7200, NOW - 3600, NOW - 1000, NOW - 300 }, ","))
	eq(e.last.min, 45)
end)

it("#241: days: union; the same day on both keeps the aggregate with more points, own on a tie", function()
	local M = Market()
	InScope({ 100 })
	CraftWiseMarketDB.houses[HORDE] = FACTION
	local mine = { last = { t = NOW, min = 50, qty = 5 }, raw = {}, days = {
		[TODAY - 1] = Day(10, 3, 0), -- more points on this machine
		[TODAY - 2] = Day(20, 2, 1), -- fewer
		[TODAY - 3] = Day(30, 4, 2), -- the same count
		[TODAY - 4] = Day(40, 6, 3), -- only here
	} }
	CraftWiseMarketDB.items[100] = { [HORDE] = M.EncodeEntry(mine) }
	local theirs = { last = { t = NOW - 5000, min = 60, qty = 5 }, raw = {}, days = {
		[TODAY - 1] = Day(11, 2, 9),
		[TODAY - 2] = Day(21, 5, 8),
		[TODAY - 3] = Day(31, 4, 7),
		[TODAY - 5] = Day(51, 3, 6), -- only there
		[TODAY - 40] = Day(99, 9, 9), -- older than 30 days
	} }
	Merge(M, File({ [100] = { [HORDE] = M.EncodeEntry(theirs) } }))
	local d = Stored(M, 100).days
	eq(d[TODAY - 1].lo, 10); eq(d[TODAY - 1].gone, nil)
	eq(d[TODAY - 2].lo, 21); eq(d[TODAY - 2].n, 5); eq(d[TODAY - 2].gone, 8, "the whole aggregate comes over, gone included")
	eq(d[TODAY - 3].lo, 30, "a tie keeps own")
	eq(d[TODAY - 4].lo, 40)
	eq(d[TODAY - 5].lo, 51)
	eq(d[TODAY - 40], nil)
	eq(Stored(M, 100).last.min, 50, "own last is newer")
end)

it("#241: an item outside the scope keeps last only, an own last-only entry gets the history of an item in it", function()
	local M = Market()
	InScope({ 100 })
	CraftWiseMarketDB.houses[HORDE] = FACTION
	local full = { last = { t = NOW - 10, min = 70, qty = 3 }, raw = { Point(NOW - 10, 70, 3) }, days = { [TODAY] = Day(70, 1, 0) } }
	CraftWiseMarketDB.items[100] = { [HORDE] = M.EncodeEntry({ last = { t = NOW - 5000, min = 80, qty = 1 } }) }
	Merge(M, File({ [100] = { [HORDE] = M.EncodeEntry(full) }, [200] = { [HORDE] = M.EncodeEntry(full) } }))
	local inScope, outside = Stored(M, 100), Stored(M, 200)
	eq(#inScope.raw, 1); eq(inScope.days[TODAY].lo, 70); eq(inScope.last.min, 70)
	eq(M.IsLastOnly(CraftWiseMarketDB.items[200][HORDE]), true)
	eq(outside.last.min, 70); eq(#outside.raw, 0); eq(next(outside.days), nil)
end)

it("#241: a suffix variant key and a second house merge like any other", function()
	local M = Market()
	InScope({ 100 })
	local light = M.EncodeEntry({ last = { t = NOW - 20, min = 1234, qty = 1 } })
	local file = File({ ["100:-5"] = { [HORDE] = light }, [100] = { [BOOTY] = light } })
	file.market.houses[BOOTY] = { realm = "PvP", kind = "neutral", label = "whatever the file says" }
	Merge(M, file)
	eq(Stored(M, "100:-5").last.min, 1234)
	eq(Stored(M, 100, BOOTY).last.min, 1234)
	eq(CraftWiseMarketDB.houses[BOOTY].label, "Booty Bay", "made from the key, not from the file's text")
	eq(CraftWiseMarketDB.houses[BOOTY].kind, "neutral")
	eq(#M.ItemKeys(100), 2)
end)

------------------------------------------------------------------------------------- again, and wrong input

it("#241: the same file again changes nothing, a rewritten file with the same data changes nothing either", function()
	local M = Market()
	InScope({ 100, 101 })
	CraftWiseMarketDB.houses[HORDE] = FACTION
	CraftWiseMarketDB.items[100] = { [HORDE] = M.EncodeEntry({ last = { t = NOW - 90, min = 99, qty = 5 }, raw = { Point(NOW - 90, 99, 5) }, days = { [TODAY] = Day(99, 1, 0) } }) }
	local theirs = { last = { t = NOW - 10, min = 90, qty = 8 }, raw = { Point(NOW - 3600, 91, 9), Point(NOW - 10, 90, 8) },
		days = { [TODAY] = Day(90, 4, 6), [TODAY - 2] = Day(80, 3, 2) } }
	local function Build(written)
		local f = File({ [100] = { [HORDE] = M.EncodeEntry(theirs) }, [101] = { [HORDE] = M.EncodeEntry(theirs) },
			[300] = { [HORDE] = M.EncodeEntry({ last = { t = NOW - 5, min = 7, qty = 1 } }) } })
		f.written = written
		return f
	end
	Merge(M, Build(NOW - 60))
	local first = Dump(M)
	eq(M.SyncStatus().changed > 0, true)
	-- the very same file (same `written`)
	eq(Merge(M, Build(NOW - 60)), "unchanged")
	eq(Dump(M), first)
	-- the file was written again and holds the same market
	local v = M.DataVersion()
	eq(Merge(M, Build(NOW - 30)), "done")
	eq(Dump(M), first, "nothing changed")
	eq(M.SyncStatus().changed, 0)
	eq(M.DataVersion(), v, "no cache restarts for nothing")
	eq(CraftWiseMarketDB.sync.written, NOW - 30)
end)

it("#241: an entry of the other machine that is older than ours leaves ours as it was", function()
	local M = Market()
	InScope({ 100 })
	CraftWiseMarketDB.houses[HORDE] = FACTION
	local mine = M.EncodeEntry({ last = { t = NOW - 10, min = 99, qty = 5 }, raw = { Point(NOW - 10, 99, 5) }, days = { [TODAY] = Day(99, 3, 4) } })
	CraftWiseMarketDB.items[100] = { [HORDE] = mine }
	Merge(M, File({ [100] = { [HORDE] = M.EncodeEntry({ last = { t = NOW - 500, min = 10, qty = 1 }, raw = {}, days = { [TODAY] = Day(10, 2, 1) } }) } }))
	eq(CraftWiseMarketDB.items[100][HORDE], mine)
end)

it("#241: malformed entries are skipped, not a Lua error, and the good ones still arrive", function()
	local M = Market()
	InScope({ 100, 101 })
	local good = M.EncodeEntry({ last = { t = NOW - 10, min = 90, qty = 8 }, raw = { Point(NOW - 10, 90, 8) }, days = {} })
	local items = {
		[100] = { [HORDE] = good },
		[101] = { [HORDE] = "not an entry at all" },
		[102] = { [HORDE] = "zz,zz,zz|1,2,3,4,5|" },
		[103] = { [HORDE] = 12345 },
		[104] = { [HORDE] = M.EncodeEntry({ last = { t = 5, min = 90, qty = 8 } }) }, -- a time before the game
		[105] = { [HORDE] = M.EncodeEntry({ last = { t = NOW + 10 * DAY, min = 90, qty = 8 } }) }, -- from the future
		[106] = { [HORDE] = "||" },
		[107] = "a string where the houses should be",
		["junk"] = { [HORDE] = good },
		["12:x"] = { [HORDE] = good },
		[0] = { [HORDE] = good },
		[108] = { ["Nowhere|X"] = good },
		[109] = { [HORDE] = (good:gsub("|.*", "|1,2,3|")) }, -- a point with an odd tier list
	}
	items[100]["not a house"] = good
	eq(Merge(M, File(items)), "done")
	eq(Stored(M, 100).last.min, 90)
	eq(Stored(M, 101), nil); eq(Stored(M, 102), nil); eq(Stored(M, 103), nil); eq(Stored(M, 104), nil)
	eq(Stored(M, 105), nil); eq(Stored(M, 106), nil); eq(Stored(M, 108), nil)
	eq(#Stored(M, 109).raw, 0, "the bad point is left out, the good last stays")
	eq(Stored(M, 109).last.min, 90)
	eq(CraftWiseMarketDB.items.junk, nil); eq(CraftWiseMarketDB.items["12:x"], nil); eq(CraftWiseMarketDB.items[0], nil)
	assert(M.SyncStatus().bad >= 10, "counted: " .. tostring(M.SyncStatus().bad))
	eq(M.SyncStatus().state, "done")
end)

it("#241: a table in the file that is not a table, a house key that is no house and names of the wrong type are skipped too", function()
	local M = Market()
	local file = File({ [100] = { [HORDE] = M.EncodeEntry({ last = { t = NOW - 10, min = 90, qty = 8 } }) } }, {
		names = { [1] = "Real Name", [2] = 77, [3] = "", ["x"] = "Bad Key", [4] = ("n"):rep(500) },
		itemInfo = { [1] = "1,2,3,4,5,6", [2] = "not info", [3] = 5, ["y"] = "1,2,3,4,5,6" },
		classNames = { [7] = "Trade Goods", [8] = 9, [999999] = "Out of range" },
		subclassNames = { [7] = { [5] = "Cloth", [6] = 4 }, [8] = "junk" },
		scans = { [HORDE] = { { t = NOW - 100, kind = "full", items = 10 }, "junk", { t = 1, kind = "full" }, { t = NOW - 5, kind = "weird" } }, ["No|H"] = {} },
	})
	file.market.houses["not a house"] = FACTION
	file.market.houses[""] = {}
	Merge(M, file)
	local db = CraftWiseMarketDB
	eq(db.names[1], "Real Name"); eq(db.names[2], nil); eq(db.names[3], nil); eq(db.names[4], nil)
	eq(db.itemInfo[1], "1,2,3,4,5,6"); eq(db.itemInfo[2], nil); eq(db.itemInfo[3], nil)
	eq(db.classNames[7], "Trade Goods"); eq(db.classNames[8], nil); eq(db.classNames[999999], nil)
	eq(db.subclassNames[7][5], "Cloth"); eq(db.subclassNames[7][6], nil); eq(db.subclassNames[8], nil)
	eq(#db.syncScans[HORDE], 1)
	eq(db.houses["not a house"], nil)
	eq(M.SyncStatus().state, "done")
end)

------------------------------------------------------------------------------------- names, item info, scans

it("#241: names and class names are filled in, never replaced; item info: the newer read wins, a complete one beats a partial", function()
	local M = Market()
	local db = CraftWiseMarketDB
	db.names[1] = "My Name"
	db.classNames[7] = "Mein Handelswaren"
	db.itemInfo[10] = M.EncodeItemInfo({ q = 1, i = 100, c = 7, s = 5, p = 13 }, NOW - 5000)
	db.itemInfo[11] = M.EncodeItemInfo({ q = 1, i = 100, c = 7, s = 5, p = 13 }, NOW - 100)
	db.itemInfo[12] = "1,2,3,4,5" -- a format 1 string: no sell price
	local info = function(t) return M.EncodeItemInfo({ q = 2, i = 200, c = 7, s = 5, p = 14 }, t) end
	Merge(M, File({}, {
		names = { [1] = "Their Name", [2] = "Other Name" },
		classNames = { [7] = "Trade Goods", [9] = "Weapon" },
		itemInfo = { [10] = info(NOW - 100), [11] = info(NOW - 5000), [12] = info(NOW - 7000), [13] = info(NOW - 1) },
	}))
	eq(db.names[1], "My Name"); eq(db.names[2], "Other Name")
	eq(db.classNames[7], "Mein Handelswaren"); eq(db.classNames[9], "Weapon")
	eq(M.ItemInfo(10).q, 2, "newer read")
	eq(M.ItemInfo(11).q, 1, "own is newer")
	eq(M.ItemInfo(12).p, 14, "a complete string replaces one without a sell price")
	eq(M.ItemInfo(13).i, 200, "new")
end)

it("#241: the other machine's scans are kept apart: never a scan of this machine, own ones that come back are not doubled", function()
	local M = Market()
	local db = CraftWiseMarketDB
	db.houses[HORDE] = FACTION
	db.scans[HORDE] = { { t = NOW - 4000, kind = "full", items = 100, source = "own" } }
	local scans = { { t = NOW - 4000, kind = "full", items = 100, source = "own" }, -- this machine's, back from the site
		{ t = NOW - 900, kind = "full", items = 1500, lastOnly = 8000, source = "auctionator", machine = "MacBook" },
		{ t = NOW - 500, kind = "search", items = 3 } }
	Merge(M, File({}, { scans = { [HORDE] = scans } }))
	eq(#db.scans[HORDE], 1, "the own list is untouched")
	eq(M.LastRecorded(HORDE), NOW - 4000, "last scanned by you is still your scan")
	eq(#db.syncScans[HORDE], 2)
	local t, machine = M.LastSynced(HORDE)
	eq(t, NOW - 500); eq(machine, nil)
	eq(db.syncScans[HORDE][1].machine, "MacBook")
	-- again: nothing is added twice
	local f = File({}, { scans = { [HORDE] = scans } })
	f.written = NOW - 1
	Merge(M, f)
	eq(#db.syncScans[HORDE], 2)
	eq(M.SnapshotSummary().houses[HORDE].lastRecorded, NOW - 4000)
	eq(M.SnapshotSummary().houses[HORDE].lastSynced, NOW - 500)
end)

it("#241: at most 30 scans of the other machine are kept", function()
	local M = Market()
	CraftWiseMarketDB.houses[HORDE] = FACTION
	local scans = {}
	for i = 1, 45 do scans[i] = { t = NOW - i * 100, kind = "full", items = i } end
	Merge(M, File({}, { scans = { [HORDE] = scans } }))
	eq(#CraftWiseMarketDB.syncScans[HORDE], 30)
	eq(CraftWiseMarketDB.syncScans[HORDE][30].t, NOW - 100)
	eq(CraftWiseMarketDB.syncScans[HORDE][1].t, NOW - 3000)
end)

------------------------------------------------------------------------------------- the loading screen's time

-- A clock that moves 1 ms per look at it; any use of a frame or timer for the merge is an error.
local function LoadingClock()
	local looks = 0
	debugprofilestop = function() looks = looks + 1; return looks * 1.0 end
	C_Timer.After = function() error("no frame is used for the merge") end
	C_Timer.NewTimer = function() error("no timer is used for the merge") end
end

local function Count(t)
	local n = 0
	for _ in pairs(t) do n = n + 1 end
	return n
end

local function Entries(M, ids)
	local entries = {}
	for id = 1, 1500 do
		ids[id] = id
		entries[id] = { [HORDE] = M.EncodeEntry({ last = { t = NOW - id, min = 100 + id, qty = 5 }, raw = { Point(NOW - id, 100 + id, 5) }, days = { [TODAY] = Day(100 + id, 1, 0) } }) }
	end
	return entries
end

it("#241: a file bigger than the loading screen's time is finished at logout, before the file is saved, with the same result", function()
	local M, stub, ns = Market()
	local ids = {}
	InScope((function() Entries(M, ids) return ids end)())
	LoadingClock()
	M.SYNC_LOGIN_MS = 50 -- ms; one look at the clock is 1 ms here and it looks every M.SYNC_CHECK entries
	CraftWiseSync = File(Entries(M, {}), { names = { [1] = "One", [2] = "Two" } })
	eq(M.StartSync(), "partial") -- what the login handler calls
	eq(M.SyncBusy(), true)
	local part = Count(CraftWiseMarketDB.items)
	assert(part > 0 and part < 1500 and part <= 50 * M.SYNC_CHECK + M.SYNC_CHECK, "the loading screen's budget was used: " .. part)
	eq(CraftWiseMarketDB.sync, nil, "written is only recorded when it is all merged")
	stub.Fire("PLAYER_LOGOUT")
	eq(M.SyncBusy(), false)
	eq(Count(CraftWiseMarketDB.items), 1500)
	eq(CraftWiseMarketDB.sync.atLogout, true)
	eq(CraftWiseMarketDB.names[2], "Two")
	-- the same file merged in one go
	local whole = Dump(M)
	local M2 = Market()
	InScope(ids)
	CraftWiseSync = File(Entries(M2, {}))
	eq(M2.StartSync(), "done")
	eq(whole, Dump(M2), "the same entries")
end)

it("#241: a game that closes before the merge is finished doesn't mark it done, the next login does it again", function()
	local M, stub = Market()
	InScope({ 1, 2, 3 })
	LoadingClock()
	M.SYNC_LOGIN_MS = 5
	local entries = {}
	for id = 1, 300 do entries[id] = { [HORDE] = M.EncodeEntry({ last = { t = NOW - id, min = 10, qty = 1 } }) } end
	eq(Merge(M, File(entries)), "partial")
	eq(CraftWiseMarketDB.sync, nil)
	local partial = Count(CraftWiseMarketDB.items)
	assert(partial > 0 and partial < 300, "part way: " .. partial)
	-- a crash or a kill: no logout. The next login reads the file again.
	local again = {}
	for id = 1, 300 do again[id] = { [HORDE] = M.EncodeEntry({ last = { t = NOW - id, min = 10, qty = 1 } }) } end
	M.SYNC_LOGIN_MS = 10 ^ 9
	CraftWiseSync = File(again)
	-- (a new Lua state would have no job; here the old one is finished first)
	stub.Fire("PLAYER_LOGOUT")
	eq(Count(CraftWiseMarketDB.items), 300)
end)

------------------------------------------------------------------------------------- what the rest of the addon sees

it("#241: merged prices are the prices: Current, Typical's days and the status line say synced, never scanned", function()
	local M, _, ns = Market()
	InScope({ 100 })
	local theirs = { last = { t = NOW - 100, min = 90, qty = 12, listings = 3 }, raw = { Point(NOW - 100, 90, 12) },
		days = { [TODAY - 1] = Day(80, 3, 0), [TODAY - 2] = Day(82, 3, 0), [TODAY - 3] = Day(84, 3, 0) } }
	Merge(M, File({ [100] = { [HORDE] = M.EncodeEntry(theirs) } }, { scans = { [HORDE] = { { t = NOW - 100, kind = "full", items = 5 } } } }))
	eq(M.Current(100, HORDE).min, 90)
	local typical = M.Typical(100, HORDE)
	eq(typical.status, "ok"); eq(typical.days, 3, "today and the two merged days before it fall in the 3-day window, built from the merged point")
	eq(M.LastRecorded(HORDE), nil, "nobody scanned here")
	local shell = ns.Main
	ns.ProfitHouse = function() return HORDE, "Horde AH" end
	local s = shell.PriceStatus()
	eq(s.hasData, true); eq(s.at, NOW - 100); eq(s.synced.machine, nil)
	local text = shell.StatusText(s)
	assert(text:find("synced", 1, true) and not text:find("scanned", 1, true), text)
	CraftWiseMarketDB.syncScans[HORDE][1].machine = "MacBook"
	assert(shell.StatusText(shell.PriceStatus()):find("synced from MacBook", 1, true))
	-- an own scan that is newer takes the line back
	CraftWiseMarketDB.scans[HORDE] = { { t = NOW - 10, kind = "full" } }
	local own = shell.PriceStatus()
	eq(own.synced, nil)
	assert(not shell.StatusText(own):find("synced", 1, true))
	local _, lines = shell.ScanSummary(NOW)
	assert(table.concat(lines, "\n"):find("scan from MacBook 1 min ago", 1, true), table.concat(lines, "\n"))
	assert(not table.concat(lines, "\n"):find("synced from", 1, true), "an old scan entry is not the current sync")
end)

-- #423: is the companion's add-on loaded for this character, and when was its file last merged.
local function AddOns(exists, loaded)
	C_AddOns = { DoesAddOnExist = function(n) return n == "CraftWise_Sync" and exists end,
		IsAddOnLoaded = function(n) return n == "CraftWise_Sync" and loaded end }
end

it("#423: CraftWise_Sync installed but not loaded for this character: one warning line, never enabled", function()
	local M, stub, ns = Market()
	local enabled = false
	AddOns(true, false)
	C_AddOns.EnableAddOn = function() enabled = true end
	eq(M.SyncAddonState(), "disabled")
	assert(ns.Main.SyncNotice():find("is not loaded", 1, true), ns.Main.SyncNotice())
	local chat = Printed(function() stub.Fire("PLAYER_LOGIN") end)
	assert(chat:find("CraftWise_Sync is not loaded", 1, true), tostring(chat))
	local _, lines = ns.Main.ScanSummary(NOW)
	assert(lines[1]:find("/reload", 1, true), "the warning comes first")
	eq(lines[2], "", "then an empty line")
	local debug = Printed(function() SlashCmdList.CRAFTWISE("debug") end)
	assert(debug:find("CraftWise_Sync: disabled", 1, true), tostring(debug))
	eq(enabled, false)
end)

it("#423: not installed or enabled: no warning anywhere", function()
	local M, stub, ns = Market()
	AddOns(false, false)
	eq(M.SyncAddonState(), "missing"); eq(ns.Main.SyncNotice(), nil)
	local chat = Printed(function() stub.Fire("PLAYER_LOGIN") end)
	assert(not tostring(chat):find("is not loaded", 1, true), tostring(chat))
	AddOns(true, true)
	eq(M.SyncAddonState(), "loaded"); eq(ns.Main.SyncNotice(), nil)
	chat = Printed(function() stub.Fire("PLAYER_LOGIN") end)
	assert(not tostring(chat):find("is not loaded", 1, true), tostring(chat))
	C_AddOns = nil
	eq(M.SyncAddonState(), "unknown"); eq(ns.Main.SyncNotice(), nil)
end)

it("#423: the tooltip says when the companion file was last merged", function()
	local M, stub, ns = Market()
	AddOns(true, true)
	eq(ns.Main.SyncMergedText(NOW), nil, "never merged: no line")
	CraftWiseSync = File({})
	eq(M.StartSync(), "done")
	eq(M.SyncMergedAt(), NOW)
	eq(ns.Main.SyncMergedText(NOW + 12 * DAY), "Companion file merged 12 days ago")
	local _, lines = ns.Main.ScanSummary(NOW + 2 * 3600)
	assert(table.concat(lines, "\n"):find("Companion file merged 2 h ago", 1, true), table.concat(lines, "\n"))
end)

it("#241: after a merge a scan of this machine still records on top of it, and Prune keeps the merged entries", function()
	local M, stub = Market()
	InScope({ 100 })
	local theirs = { last = { t = NOW - 100, min = 90, qty = 12, listings = 3 }, raw = { Point(NOW - 100, 90, 12) }, days = { [TODAY] = Day(90, 1, 0) } }
	Merge(M, File({ [100] = { [HORDE] = M.EncodeEntry(theirs) } }))
	stub.zone, stub.subzone = "Orgrimmar", ""
	stub.Fire("AUCTION_HOUSE_SHOW")
	stub.clock = NOW + 600
	stub.replicate = { { itemID = 100, count = 4, buyout = 400, link = "item:100", owner = "Seller" } }
	stub.Fire("REPLICATE_ITEM_LIST_UPDATE")
	local e = Stored(M, 100)
	eq(#e.raw, 2, "their point and ours")
	eq(e.last.min, 100)
	M.Prune()
	eq(Stored(M, 100).days[TODAY].lo <= 100, true)
	eq(#Stored(M, 100).raw, 2)
	local text = Printed(function() M.Slash("") end)
	eq(type(text), "string")
end)

it("#423: the login chat line comes once per character until the state changes", function()
	local M, stub, ns = Market()
	local function Login() return Printed(function() M.WarnSyncOff() end) end
	AddOns(true, false)
	assert(Login():find("is not loaded", 1, true), "first login")
	eq(ns.charDB.syncWarned, "disabled")
	eq(Login(), "", "a /reload or the next login: silent")
	AddOns(true, true)
	eq(Login(), "", "loaded again: silent, flag cleared")
	eq(ns.charDB.syncWarned, nil)
	AddOns(true, false)
	assert(Login():find("is not loaded", 1, true), "off again: warned again")
	C_AddOns = nil
	eq(Login(), "", "unknown state keeps the flag and says nothing")
	eq(ns.charDB.syncWarned, "disabled")
end)

it("#423: the tooltip lists the merge age right after the house lines, before Auctionator", function()
	local M, stub, ns = Market()
	AddOns(true, true)
	CraftWiseSync = File({})
	M.StartSync()
	local _, lines = ns.Main.ScanSummary(NOW)
	assert(lines[#lines]:find("Companion file merged", 1, true), lines[#lines])
end)
