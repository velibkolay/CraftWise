-- Linked characters (#356, Link.lua): market data between your own characters of two accounts, over addon
-- messages. Invented prices only. Two clients can't be loaded at once, so the sender's messages are
-- recorded, then a second client is loaded and handed them (the specs play the other side by hand).
local NOW = 1794000000
local DAY = 86400
local TODAY = math.floor(NOW / DAY)
local HORDE = "PvP|H"
local ME = "Velikopter Tanner"
local PEER = "Velikopter Kitchenchant"

local function Load(opts)
	local ns, stub = LoadAddon(opts)
	time = function() return stub.clock end
	stub.clock = NOW
	stub.now = 1000
	stub.names.player, stub.surnames.player = "Velikopter", "Tanner"
	return ns, stub, ns.Market, ns.Link
end

local function House()
	CraftWiseMarketDB.houses[HORDE] = { realm = "PvP", kind = "faction", faction = "Horde", label = "Horde AH" }
end

local function InScope(ids)
	for _, id in ipairs(ids) do CraftWiseMarketDB.scope.items[id] = true end
end

local function Entry(t, price, qty)
	return { last = { t = t, min = price, qty = qty, listings = 3 },
		raw = { { t = t, total = qty, listings = 3, tiers = { price, qty } } },
		days = { [math.floor(t / DAY)] = { lo = price, typ = price + 5, hi = price + 20, qtyMax = qty, listMax = 3, n = 1 } } }
end

local function Put(M, itemKey, entry)
	CraftWiseMarketDB.items[itemKey] = CraftWiseMarketDB.items[itemKey] or {}
	CraftWiseMarketDB.items[itemKey][HORDE] = M.EncodeEntry(entry)
end

local function Stored(M, itemKey)
	local e = CraftWiseMarketDB.items[itemKey] and CraftWiseMarketDB.items[itemKey][HORDE]
	return type(e) == "string" and M.DecodeEntry(e) or e
end

local function Say(stub, from, ...)
	stub.Fire("CHAT_MSG_ADDON", "CWSync", table.concat({ ... }, "\t"), "WHISPER", from)
end

local function Fields(text)
	local out = {}
	for f in (text .. "\t"):gmatch("(.-)\t") do out[#out + 1] = f end
	return out
end

local function Printed(fn)
	local lines, realPrint = {}, print
	print = function(s) lines[#lines + 1] = tostring(s) end
	local ok, err = pcall(fn)
	print = realPrint
	assert(ok, err)
	return table.concat(lines, "\n")
end

-- Runs the pump over `seconds` of game time in 0.25 s steps; `onTick(t)` may answer what was sent.
local function Run(Link, t0, seconds, onTick)
	local t = t0
	while t < t0 + seconds do
		t = t + 0.25
		Link.Pump(t)
		if onTick then onTick(t) end
	end
	return t
end

-- The other side as a script: answers every complete batch with K, up to `limit` seconds. Returns every
-- message sent, in order, and the time.
local function Sender(stub, Link, from, t0, limit)
	local log, seen, t = {}, 0, t0
	Run(Link, t0, limit or 60, function(now)
		t = now
		while seen < #stub.addonSent do
			seen = seen + 1
			local msg = stub.addonSent[seen]
			log[#log + 1] = msg.text
			local f = Fields(msg.text)
			if f[1] == "B" and tonumber(f[4]) == tonumber(f[5]) then
				Say(stub, from, "K", f[2], f[3])
			end
		end
	end)
	return log, t
end

------------------------------------------------------------------------------------- pairing

it("#356: only listed characters are heard; anyone else is dropped before it is read", function()
	local ns, stub, M, Link = Load()
	House()
	InScope({ 100 })
	eq(Link.Add("Kitchenchant"), PEER, "a surname alone becomes name + surname")
	Run(Link, 0, 1)
	stub.addonSent = {}
	local mine = #stub.addonSent
	Say(stub, "Mallory Stranger", "H", "1", "PvP", HORDE, "0")
	Run(Link, 1, 2)
	eq(#stub.addonSent, mine, "a stranger's hello gets no answer and starts no transfer")
	eq(Link.Stats().rejected, 1)
	-- A chunk with data from a stranger is not merged either.
	local packed = M.EncodeEntry(Entry(NOW - 10, 50, 5))
	Say(stub, "Mallory Stranger", "B", "x1", "1", "1", "1", "e\t" .. HORDE .. "\t100\t" .. packed)
	eq(CraftWiseMarketDB.items[100], nil)
	-- Another chat channel, another prefix, our own name: all ignored.
	stub.Fire("CHAT_MSG_ADDON", "CWSync", "H\t1\tPvP", "GUILD", PEER)
	stub.Fire("CHAT_MSG_ADDON", "Other", "H\t1\tPvP", "WHISPER", PEER)
	Say(stub, ME, "H", "1", "PvP", HORDE, "0")
	eq(#stub.addonSent, mine)
	-- The listed one is heard, also with the realm the client appends and another case.
	Say(stub, "velikopter kitchenchant-PvP", "H", "1", "PvP", HORDE, "0")
	Run(Link, 3, 2)
	assert(#stub.addonSent > mine, "the listed character gets its answer")
end)

it("#356: the list: add, expand, no self, no twice, remove", function()
	local ns, stub, M, Link = Load()
	eq(Link.Add("Kitchenchant"), PEER)
	eq(select(2, Link.Add("kitchenchant")), "known")
	eq(select(2, Link.Add("Tanner")), "self")
	eq(select(2, Link.Add("  ")), "empty")
	eq(Link.Add("Other Person-Realm"), "Other Person", "a realm suffix is dropped")
	eq(#Link.List(), 2)
	eq(Link.Remove("Kitchenchant"), true)
	eq(Link.Remove("Kitchenchant"), false)
	eq(Link.List()[1], "Other Person")
	assert(stub.addonPrefixes.CWSync, "the prefix is registered")
end)

------------------------------------------------------------------------------------- hello and delta

it("#356: the hello asks for what is newer than what I got and my own last full scan, per house of the realm", function()
	local ns, stub, M, Link = Load()
	House()
	CraftWiseMarketDB.houses["Other|H"] = { realm = "Other", kind = "faction", faction = "Horde", label = "Horde AH" }
	CraftWiseMarketDB.scans[HORDE] = { { t = NOW - 5000, kind = "full" }, { t = NOW - 100, kind = "search" } }
	Link.Add("Kitchenchant")
	Run(Link, 0, 1)
	local f = Fields(stub.addonSent[1].text)
	eq(f[1], "H")
	eq(f[3], "PvP")
	eq(f[4], HORDE)
	eq(tonumber(f[5]), NOW - 5000, "the own last FULL scan, not a search")
	eq(f[6], nil, "no house of another realm")
	eq(stub.addonSent[1].chatType, "WHISPER")
	eq(stub.addonSent[1].target, PEER)
	CraftWiseDB.link.peers[1].got[HORDE] = NOW - 20
	eq(Fields(Link.__hello and "" or "H")[1], "H")
	Link.Hello("velikopter kitchenchant")
	Run(Link, 1, 1)
	eq(tonumber(Fields(stub.addonSent[#stub.addonSent].text)[5]), NOW - 20, "what I got from it, when that is newer")
end)

local function Fill(M, n)
	local ids = {}
	for i = 1, n do
		ids[i] = 1000 + i
		Put(M, 1000 + i, Entry(NOW - 1000 + i, 100 + i, 5 + i))
		CraftWiseMarketDB.names[1000 + i] = "Item " .. i
	end
	InScope(ids)
	return ids
end

it("#356: the sender sends only entries newer than `since`, one batch at a time, then the end; chunks fit a message", function()
	local ns, stub, M, Link = Load()
	House()
	Fill(M, 40)
	CraftWiseMarketDB.scans[HORDE] = { { t = NOW - 10, kind = "full", items = 40 } }
	Link.Add("Kitchenchant")
	Run(Link, 0, 2)
	stub.addonSent = {}
	Say(stub, PEER, "H", "1", "PvP", HORDE, tostring(NOW - 1000 + 30)) -- entries 31..40 are newer
	local log = Sender(stub, Link, PEER, 2, 60)
	local entries, chunks, batches, ends = 0, 0, {}, 0
	local payload = {}
	for _, text in ipairs(log) do
		local f = Fields(text)
		if f[1] == "B" then
			chunks = chunks + 1
			batches[f[3]] = true
			payload[#payload + 1] = text:match("^B\t[^\t]*\t[^\t]*\t[^\t]*\t[^\t]*\t(.*)$")
		elseif f[1] == "E" then
			ends = ends + 1
		end
	end
	local all = table.concat(payload)
	for _ in all:gmatch("e\t") do entries = entries + 1 end
	eq(entries, 10, "10 entries after the watermark, nothing older")
	assert(not all:find("e\tPvP|H\t1001\t", 1, true), "an old entry is not sent")
	assert(all:find("s\tPvP|H\t", 1, true), "the own scan goes with it")
	assert(all:find("n\t1040\tItem 40", 1, true), "names go with the entries")
	eq(ends, 1)
	eq(Fields(log[#log])[1], "E", "the end comes last")
end)

it("#356: a batch is not followed by the next until the other side said K; no K sends it again, then gives up", function()
	local ns, stub, M, Link = Load()
	House()
	Fill(M, 60)
	Link.Add("Kitchenchant")
	Run(Link, 0, 2)
	stub.addonSent = {}
	Say(stub, PEER, "H", "1", "PvP", HORDE, "0")
	Run(Link, 2, 20)
	local first = {}
	for _, m in ipairs(stub.addonSent) do
		local f = Fields(m.text)
		if f[1] == "B" then first[f[3]] = (first[f[3]] or 0) + 1 end
	end
	eq(first["1"] ~= nil, true)
	eq(first["2"], nil, "batch 2 waits for the K of batch 1")
	local count = #stub.addonSent
	Run(Link, 22, 30)
	assert(#stub.addonSent > count, "no K: batch 1 goes out again")
	assert(Link.Stats().resent > 0)
	Run(Link, 52, 120)
	local before = #stub.addonSent
	Run(Link, 172, 20)
	eq(#stub.addonSent, before, "after three tries it stops; the next hello starts again")
	eq(Link.Status()[1].state, nil)
end)

------------------------------------------------------------------------------------- the whole way

local function Transfer(items, since, opts)
	opts = opts or {}
	local ns, stub, M, Link = Load()
	House()
	Fill(M, items)
	CraftWiseMarketDB.scans[HORDE] = { { t = NOW - 10, kind = "full", items = items } }
	Link.Add("Kitchenchant")
	Run(Link, 0, 1)
	stub.addonSent = {}
	Say(stub, PEER, "H", "1", "PvP", HORDE, tostring(since or 0))
	local log = Sender(stub, Link, PEER, 1, 3000)
	return log
end

it("#356: what one client sends, the other merges: same entries, decoded like local ones, a chat line, the watermark moves", function()
	local log = Transfer(30)
	local ns, stub, M, Link = Load()
	House()
	InScope((function() local ids = {} for i = 1, 30 do ids[i] = 1000 + i end return ids end)())
	Put(M, 1001, Entry(NOW - 5000, 70, 9)) -- an older one of mine: replaced by the newer
	Put(M, 1002, Entry(NOW - 100, 999, 9)) -- a newer one of mine: kept
	Link.Add("Kitchenchant")
	stub.addonSent = {}
	local out = Printed(function()
		for _, text in ipairs(log) do
			Say(stub, PEER, unpack(Fields(text)))
		end
	end)
	assert(out:find("Synced 30 prices from " .. PEER, 1, true), "all 30 merged (1002 keeps its price but gains the history): " .. out)
	local e = Stored(M, 1001)
	eq(e.last.min, 101, "newer last wins")
	eq(e.last.t, NOW - 999)
	eq(#e.raw, 2, "history of both: my older point and the new one")
	eq(Stored(M, 1002).last.min, 999, "an own newer price is kept")
	eq(Stored(M, 1030).last.qty, 35)
	eq(CraftWiseMarketDB.names[1030], "Item 30")
	assert(CraftWiseDB.link.peers[1].got[HORDE] >= NOW - 1000 + 30, "the watermark moved to the newest entry received")
	assert(CraftWiseDB.link.peers[1].lastSync, "last sync is set")
	eq(CraftWiseDB.link.peers[1].received, 30)
	-- A merged entry encodes and decodes exactly like a recorded one.
	local packed = M.EncodeEntry(Stored(M, 1005))
	eq(M.EncodeEntry(M.DecodeEntry(packed)), packed)
	-- And it names its origin (the scan came with it).
	local t = Stored(M, 1005).last.t
	eq(M.SyncedVia(HORDE, t), PEER)
	eq(M.SyncedVia(HORDE, t + 3 * DAY), nil, "a price from some other time is not attributed")
end)

it("#356: a batch's chunks in any order, twice, or with one lost, end up as one merge", function()
	local log = Transfer(12)
	local ns, stub, M, Link = Load()
	House()
	InScope({ 1001, 1002, 1003, 1004, 1005, 1006, 1007, 1008, 1009, 1010, 1011, 1012 })
	stub.now = 0 -- the pump below is driven on the same clock the messages are stamped with
	Link.Add("Kitchenchant")
	Run(Link, 0, 1)
	stub.addonSent = {}
	-- the first batch's chunks, reversed, one of them twice
	local chunks, rest = {}, {}
	for _, text in ipairs(log) do
		local f = Fields(text)
		if f[1] == "B" and f[3] == "1" then chunks[#chunks + 1] = f else rest[#rest + 1] = f end
	end
	assert(#chunks >= 3, "the batch has several chunks: " .. #chunks)
	local function deliver(f) Say(stub, PEER, unpack(f)) end
	local lost = chunks[2]
	for i = #chunks, 1, -1 do
		if chunks[i] ~= lost then
			deliver(chunks[i])
			deliver(chunks[i])
		end
	end
	eq(next(CraftWiseMarketDB.items), nil, "an incomplete batch merges nothing")
	local k = 0
	for _, m in ipairs(stub.addonSent) do if m.text:sub(1, 1) == "K" then k = k + 1 end end
	eq(k, 0)
	-- nothing for a while: the receiver asks for the missing chunk
	Run(Link, 1, 5)
	stub.addonSent = {}
	Run(Link, 6, 8)
	local asked
	for _, m in ipairs(stub.addonSent) do
		local f = Fields(m.text)
		if f[1] == "R" then asked = f end
	end
	assert(asked, "R is sent after the wait")
	eq(asked[3], "1")
	eq(asked[4], lost[4], "it names exactly the missing chunk")
	deliver(lost)
	assert(next(CraftWiseMarketDB.items), "the batch is merged when the last chunk arrives")
	local acked = false
	Run(Link, 14, 2)
	for _, m in ipairs(stub.addonSent) do if m.text == "K\t" .. chunks[1][2] .. "\t1" then acked = true end end
	eq(acked, true, "K goes out")
	-- a chunk of a finished batch again: K again, nothing merged twice
	local before = Link.Stats().received
	deliver(chunks[1])
	eq(Link.Stats().received, before)
end)

it("#356: the sender sends the missing chunks again on R", function()
	local ns, stub, M, Link = Load()
	House()
	Fill(M, 30)
	Link.Add("Kitchenchant")
	Run(Link, 0, 1)
	stub.addonSent = {}
	Say(stub, PEER, "H", "1", "PvP", HORDE, "0")
	Run(Link, 1, 15)
	local xid, total
	for _, m in ipairs(stub.addonSent) do
		local f = Fields(m.text)
		if f[1] == "B" then xid, total = f[2], f[5] end
	end
	assert(xid and tonumber(total) >= 2)
	stub.addonSent = {}
	Say(stub, PEER, "R", xid, "1", "2")
	Run(Link, 16, 4)
	local got = {}
	for _, m in ipairs(stub.addonSent) do
		local f = Fields(m.text)
		if f[1] == "B" then got[#got + 1] = f[4] end
	end
	eq(table.concat(got, ","), "2", "only chunk 2 again")
end)

------------------------------------------------------------------------------------- merge rules

it("#356: merge: newer last wins by its time, days merge by day (more points win), typical is the existing day arithmetic", function()
	local ns, stub, M, Link = Load()
	House()
	InScope({ 7 })
	local mine = Entry(NOW - 600, 80, 10)
	mine.days[TODAY] = { lo = 80, typ = 85, hi = 100, qtyMax = 10, listMax = 3, n = 2 }
	mine.days[TODAY - 1] = { lo = 70, typ = 75, hi = 90, qtyMax = 4, listMax = 2, n = 5 }
	Put(M, 7, mine)
	local theirs = Entry(NOW - 100, 60, 20)
	theirs.days = { [TODAY] = { lo = 60, typ = 70, hi = 95, qtyMax = 20, listMax = 3, n = 3 },
		[TODAY - 1] = { lo = 1, typ = 2, hi = 3, qtyMax = 1, listMax = 1, n = 1 },
		[TODAY - 2] = { lo = 50, typ = 55, hi = 60, qtyMax = 8, listMax = 2, n = 4 } }
	local job = M.MergeIncoming({ houses = { [HORDE] = true }, items = { [7] = { [HORDE] = M.EncodeEntry(theirs) } } }, PEER)
	eq(job.priced, 1)
	local e = Stored(M, 7)
	eq(e.last.t, NOW - 100)
	eq(e.last.min, 60)
	eq(e.days[TODAY].n, 3, "the day with more points wins")
	eq(e.days[TODAY].lo, 60)
	eq(e.days[TODAY - 1].n, 5, "the day with fewer points loses")
	eq(e.days[TODAY - 2].n, 4, "a day only they have is added")
	assert(#e.raw >= 2, "raw points of both (by their time)")
	-- the same batch again changes nothing
	local before = M.EncodeEntry(Stored(M, 7))
	local again = M.MergeIncoming({ houses = { [HORDE] = true }, items = { [7] = { [HORDE] = M.EncodeEntry(theirs) } } }, PEER)
	eq(again.priced, 0)
	eq(M.EncodeEntry(Stored(M, 7)), before)
	-- junk is skipped, not an error
	local junk = M.MergeIncoming({ houses = { [HORDE] = true }, items = { [8] = { [HORDE] = "garbage" }, bad = { [HORDE] = "x" } } }, PEER)
	eq(junk.priced, 0)
end)

it("#356: the delta carries the new part of an entry; merging it gives what a full entry would", function()
	local ns, stub, M, Link = Load()
	House()
	InScope({ 7 })
	local e = Entry(NOW - 30, 50, 5)
	e.raw = { { t = NOW - 3 * 3600, total = 4, listings = 2, tiers = { 55, 4 } }, { t = NOW - 30, total = 5, listings = 3, tiers = { 50, 5 } } }
	e.days[TODAY - 3] = { lo = 40, typ = 45, hi = 50, qtyMax = 3, listMax = 1, n = 2 }
	Put(M, 7, e)
	local state = M.DeltaStart({ [HORDE] = NOW - 2 * 3600 }, "PvP")
	local list = M.DeltaNext(state, 10)
	eq(#list, 1 + 0, "one entry, no scans, no info")
	local packed = list[1]:match("^e\t[^\t]*\t[^\t]*\t(.*)$")
	local d = M.DecodeEntry(packed)
	eq(#d.raw, 1, "only the raw point after the watermark")
	eq(d.days[TODAY - 3], nil, "days before the watermark's day stay home")
	eq(d.last.t, NOW - 30)
end)

------------------------------------------------------------------------------------- the throttle

it("#356: the byte bucket: a burst, then the sustained rate; a client throttle pauses the queue; nothing is lost", function()
	local ns, stub, M, Link = Load()
	House()
	Fill(M, 200)
	Link.Add("Kitchenchant")
	Say(stub, PEER, "H", "1", "PvP", HORDE, "0")
	Link.Pump(0)
	stub.addonSent = {}
	-- a lot is queued by a transfer in flight; count what leaves per second
	for i = 1, 40 do Link.Pump(0.01 * i) end
	local burst = #stub.addonSent
	assert(burst <= math.ceil(Link.BURST / 100) + 1, "a burst is limited: " .. burst)
	local bytes0 = 0
	for _, m in ipairs(stub.addonSent) do bytes0 = bytes0 + #m.text + 6 end
	assert(bytes0 <= Link.BURST + 255, "bytes: " .. bytes0)
	-- the client says throttled: nothing leaves for PAUSE seconds, nothing is dropped
	local queued = Link.QueueLength()
	stub.addonResult = 3
	Link.Pump(10)
	eq(Link.Stats().throttled >= 1, true)
	stub.addonResult = nil
	local sent = #stub.addonSent
	Link.Pump(11)
	eq(#stub.addonSent, sent, "paused")
	Link.Pump(14)
	assert(#stub.addonSent > sent, "after the pause it goes on")
	assert(Link.QueueLength() <= queued, "the throttled message stayed queued")
	-- sustained: over 10 s about RATE * 10 bytes
	stub.addonSent = {}
	local t0 = 100
	Link.Pump(t0)
	local from = #stub.addonSent
	for i = 1, 40 do Link.Pump(t0 + i * 0.25) end
	local bytes = 0
	for i = from + 1, #stub.addonSent do bytes = bytes + #stub.addonSent[i].text + 6 end
	assert(bytes <= Link.RATE * 10 + 255, "sustained rate holds: " .. bytes)
end)

it("#356: a message never goes over 255 bytes, whatever the batch holds", function()
	local ns, stub, M, Link = Load()
	House()
	-- fat entries: many raw points and days
	local ids = {}
	for i = 1, 6 do
		local e = Entry(NOW - 100, 50, 5)
		e.raw = {}
		for p = 1, 40 do e.raw[p] = { t = NOW - 100 - p * 60, total = 5, listings = 3, tiers = { 50 + p, 3, 60 + p, 2 } } end
		table.sort(e.raw, function(a, b) return a.t < b.t end)
		for d = 1, 60 do e.days[TODAY - d] = { lo = 40, typ = 45, hi = 50, qtyMax = 3, listMax = 1, n = 2 } end
		Put(M, 2000 + i, e)
		ids[i] = 2000 + i
	end
	InScope(ids)
	Link.Add("Kitchenchant")
	Run(Link, 0, 1)
	stub.addonSent = {}
	Say(stub, PEER, "H", "1", "PvP", HORDE, "0")
	local log = Sender(stub, Link, PEER, 1, 600)
	assert(#log > 10)
	for _, text in ipairs(log) do assert(#text <= 255, #text) end
end)

------------------------------------------------------------------------------------- cost

it("#356: merging a batch of ~30 entries is small work (the sender paces batches by the rate)", function()
	local log = Transfer(120)
	local ns, stub, M, Link = Load()
	House()
	InScope((function() local ids = {} for i = 1, 120 do ids[i] = 1000 + i end return ids end)())
	Link.Add("Kitchenchant")
	local batches, worst = 0, 0
	local last = 0
	for _, text in ipairs(log) do
		local c = os.clock()
		Say(stub, PEER, unpack(Fields(text)))
		local took = os.clock() - c
		if took > worst then worst = took end
		if Fields(text)[1] == "K" then batches = batches + 1 end
	end
	eq(Stored(M, 1120).last.min, 220)
	assert(worst < 0.25, "the slowest message took " .. worst .. " s")
	print(("       (120 entries: slowest message %.1f ms)"):format(worst * 1000))
end)

------------------------------------------------------------------------------------- the rest

it("#356: after an own full scan the online characters are told; a link-sourced price set is not pushed back", function()
	local ns, stub, M, Link = Load()
	House()
	Link.Add("Kitchenchant")
	Run(Link, 0, 1)
	Say(stub, PEER, "H", "1", "PvP", HORDE, "0") -- now online
	Run(Link, 1, 2)
	stub.addonSent = {}
	ns.Notify("FULL_PRICES")
	Run(Link, 3, 1)
	local p = 0
	for _, m in ipairs(stub.addonSent) do if m.text:sub(1, 1) == "P" then p = p + 1 end end
	eq(p, 1)
	stub.addonSent = {}
	ns.Notify("FULL_PRICES", "link")
	Run(Link, 4, 1)
	eq(#stub.addonSent, 0)
end)

it("#356: status says online, last sync and what was received; offline when nothing was heard", function()
	local ns, stub, M, Link = Load()
	House()
	Link.Add("Kitchenchant")
	assert(Link.StatusText():find("not heard from", 1, true))
	assert(Link.StatusText():find("not synced yet", 1, true))
	eq(Link.Status(1000)[1].online, false)
	Say(stub, PEER, "P", "1")
	eq(Link.Status()[1].online, true)
	assert(Link.StatusText():find("online", 1, true))
	eq(Link.Status(stub.now + 400)[1].online, false, "silent for 5 minutes: offline again")
end)

it("#356: /craftwise link add and remove", function()
	local ns, stub, M, Link = Load()
	SlashCmdList.CRAFTWISE("link add Kitchenchant")
	eq(Link.List()[1], PEER)
	SlashCmdList.CRAFTWISE("link remove Kitchenchant")
	eq(#Link.List(), 0)
end)

------------------------------------------------------------------------------------- connected realms (#358)

local R4, R8 = "CAMWOW EU4 Realm 4 PvP", "CAMWOW EU4 Realm 8 PvP"

it("#358: house keys map to my realm: faction (my faction only) and neutral houses; anything else is nil", function()
	local ns, stub, M, Link = Load()
	stub.realm, stub.faction = R8, "Horde"
	eq(Link.MapHouse(R4 .. "|H", R4), R8 .. "|H")
	eq(Link.MapHouse(R4 .. "|N:Gadgetzan", R4), R8 .. "|N:Gadgetzan")
	eq(Link.MapHouse(R4 .. "|N:BootyBay", R4), R8 .. "|N:BootyBay")
	eq(Link.MapHouse(R4 .. "|A", R4), nil, "the other faction's house is not mine")
	eq(Link.MapHouse("Other|H", R4), nil, "a house of a third realm")
	eq(Link.MapHouse(R4 .. "|X", R4), nil)
	eq(Link.MapHouse(R4 .. "|H", nil), nil)
	stub.faction = "Alliance"
	eq(Link.MapHouse(R4 .. "|H", R4), nil, "opposite factions don't map the faction house")
	eq(Link.MapHouse(R4 .. "|A", R4), R8 .. "|A")
	eq(Link.MapHouse(R4 .. "|N:Gadgetzan", R4), R8 .. "|N:Gadgetzan", "neutral houses are shared by both factions")
end)

it("#358: a hello from a listed character of another realm is accepted; from an unlisted one, on any realm, it is not", function()
	local ns, stub, M, Link = Load()
	stub.realm = R8
	CraftWiseMarketDB.houses[R8 .. "|H"] = { realm = R8, kind = "faction", faction = "Horde", label = "Horde AH" }
	Fill(M, 5)
	Link.Add("Kitchenchant")
	Run(Link, 0, 1)
	stub.addonSent = {}
	Say(stub, "Mallory Stranger", "H", "1", R4, R4 .. "|H", "0")
	Run(Link, 1, 3)
	eq(#stub.addonSent, 0)
	Say(stub, PEER, "H", "1", R4, R4 .. "|H", "0")
	Run(Link, 4, 3)
	assert(#stub.addonSent > 0, "answered")
	eq(CraftWiseDB.link.peers[1].realm, R4)
	assert(Link.StatusText():find("(Realm 4)", 1, true), Link.StatusText())
end)

local function RealmTransfer(n, since)
	local ns, stub, M, Link = Load()
	stub.realm = R4
	local house = R4 .. "|H"
	CraftWiseMarketDB.houses[house] = { realm = R4, kind = "faction", faction = "Horde", label = "Horde AH" }
	CraftWiseMarketDB.houses[R4 .. "|N:Gadgetzan"] = { realm = R4, kind = "neutral", label = "Gadgetzan" }
	for i = 1, n do
		CraftWiseMarketDB.items[1000 + i] = { [house] = M.EncodeEntry(Entry(NOW - 1000 + i, 100 + i, 5 + i)) }
		CraftWiseMarketDB.scope.items[1000 + i] = true
		CraftWiseMarketDB.names[1000 + i] = "Item " .. i
	end
	CraftWiseMarketDB.items[2001] = { [R4 .. "|N:Gadgetzan"] = M.EncodeEntry(Entry(NOW - 50, 777, 3)) }
	CraftWiseMarketDB.scans[house] = { { t = NOW - 10, kind = "full", items = n } }
	Link.Add("Kitchenchant")
	Run(Link, 0, 1)
	stub.addonSent = {}
	-- the asker (realm 8) lists its own keys
	Say(stub, PEER, "H", "1", R8, R8 .. "|H", tostring(since or 0), R8 .. "|A", "5")
	return Sender(stub, Link, PEER, 1, 600)
end

it("#358: a transfer from Realm 4 lands in Realm 8's houses, with the sender's name on the scan; nothing is stored under Realm 4", function()
	local log = RealmTransfer(25)
	local ns, stub, M, Link = Load()
	stub.realm = R8
	CraftWiseMarketDB.houses[R8 .. "|H"] = { realm = R8, kind = "faction", faction = "Horde", label = "Horde AH" }
	CraftWiseMarketDB.scope.items[1001] = true
	Link.Add("Kitchenchant")
	local out = Printed(function()
		for _, text in ipairs(log) do Say(stub, PEER, unpack(Fields(text))) end
	end)
	assert(out:find("prices from " .. PEER, 1, true), out)
	local e = CraftWiseMarketDB.items[1001][R8 .. "|H"]
	assert(e, "stored at my house")
	eq(M.DecodeEntry(e).last.min, 101)
	eq(CraftWiseMarketDB.items[1001][R4 .. "|H"], nil, "no Realm 4 key")
	assert(CraftWiseMarketDB.items[2001][R8 .. "|N:Gadgetzan"], "a neutral house maps by zone")
	for _, house in pairs(CraftWiseMarketDB.houses) do assert(not house.realm or house.realm == R8, house.realm) end
	eq(CraftWiseMarketDB.names[1025], "Item 25")
	eq(CraftWiseDB.link.peers[1].got[R8 .. "|H"] >= NOW - 1000 + 25, true, "the watermark is kept under my key")
	eq(M.SyncedVia(R8 .. "|H", NOW - 1000 + 5), PEER)
end)

it("#358: the hello asks in my keys: the answerer maps them back, so the delta respects the watermark", function()
	local ns, stub, M, Link = Load()
	stub.realm = R8
	CraftWiseMarketDB.houses[R8 .. "|H"] = { realm = R8, kind = "faction", faction = "Horde", label = "Horde AH" }
	CraftWiseMarketDB.scans[R8 .. "|H"] = { { t = NOW - 77, kind = "full" } }
	Link.Add("Kitchenchant")
	Run(Link, 0, 1)
	local f = Fields(stub.addonSent[1].text)
	eq(f[3], R8)
	eq(f[4], R8 .. "|H")
	eq(tonumber(f[5]), NOW - 77)
	-- the answerer on Realm 4 reads it as its own house, and sends only newer entries
	local log = RealmTransfer(5, NOW - 1000 + 3)
	local all = {}
	for _, text in ipairs(log) do all[#all + 1] = text:match("^B\t[^\t]*\t[^\t]*\t[^\t]*\t[^\t]*\t(.*)$") end
	all = table.concat(all)
	local n = 0
	for house in all:gmatch("e\t([^\t]*)\t1%d%d%d\t") do
		n = n + 1
		eq(house, R4 .. "|H", "the sender sends its own keys")
	end
	eq(n, 2, "entries 4 and 5 are newer than the watermark")
end)
