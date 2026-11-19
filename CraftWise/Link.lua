local addonName, ns = ...

----------------------------------------------------------------------------------------------------
-- Linked characters (#356): live sync of the market data between your own characters of two WoW accounts
-- that are online at the same time (one PC, two clients). The SavedVariables of the two accounts stay
-- apart (sharing them loses a scan: the last client to write wins); the new prices go over addon messages.
--
-- Trust: only characters you listed (Settings › Linked characters, or /craftwise link add <name>) are
-- heard. A message from anyone else is dropped before it is read. The client can't prove two accounts
-- belong to one person, so the list is the boundary. Same realm and faction (WHISPER).
--
-- Wire format (prefix "CWSync", WHISPER, fields separated by a tab, at most 255 bytes a message):
--   H 2 <realm> {<house> <since>}...   "send me what you have newer than `since` at these houses"
--                                      (since = the newer of what I got from you and my own last full scan)
--   P 2                                "I have new prices": answered with an H
--   B <xid> <batch> <seq> <total> <payload>   chunk `seq` of `total` of batch `batch` of transfer `xid`
--   K <xid> <batch>                    batch merged
--   R <xid> <batch> <seq,seq,...>      these chunks of the batch are missing: send them again
--   E <xid> <batches>                  the transfer is complete
-- A batch is records joined by "~" (see Market.DeltaNext), about BATCH_BYTES of them, then deflated (LibDeflate,
-- Libs/LibDeflate.lua), prefixed with the Adler-32 of the records and encoded for the addon channel (#360); a
-- corrupt or truncated batch is dropped, never merged, and the sender sends it again when no K comes. One batch is in
-- flight at a time, the next goes out when the last one is acknowledged, so a lost chunk costs one batch.
-- Everything sent leaves through one queue and a byte bucket (RATE bytes a second, BURST at most), and a
-- throttle answer of the client pauses it. Merging a batch is what the companion's file merge does
-- (Market.MergeIncoming), a few dozen entries at a time as they arrive, so nothing is merged in one go.
----------------------------------------------------------------------------------------------------

local Link = {}
ns.Link = Link

Link.PREFIX = "CWSync"
Link.PROTO = 2 -- 2: batches are deflated (#360); a version 1 client is told apart and left alone
Link.LEVEL = 6 -- LibDeflate level of a batch
Link.CHUNK = 200 -- payload bytes of a chunk; the header stays well under the 255 of a message
Link.BATCH_BYTES = 3000
Link.RATE = 800 -- bytes a second, the figure ChatThrottleLib starts from (the client's own limit is not documented)
Link.BURST = 2400
Link.PAUSE = 3 -- seconds the queue waits after the client answers "throttled"
Link.ACK_WAIT = 25 -- seconds to a batch's K before it is sent again
Link.TRIES = 3
Link.RECV_WAIT = 10 -- seconds without a chunk before the missing ones are asked for
Link.NAGS = 3
Link.ONLINE = 300 -- heard from within this many seconds = online
Link.HELLO_OFFLINE = 120 -- seconds between hellos to a character not heard from
Link.HELLO_ONLINE = 600
Link.LOGIN_DELAY = 10
Link.MAX_CHUNKS = 120 -- a batch of more chunks than this is not accepted (deflated it is a few KB)
Link.MAX_NAMES = 8

local SEP = "\t"
local MSG_MAX = 255
local THROTTLED = { [3] = true, [8] = true, [10] = true } -- AddonMessageThrottle, ChannelThrottle, ChatThrottle

local db -- ns.db.link
local Runtime
local rt = {} -- per peer key: seen, helloAt, out (transfer being sent), inc (transfer being received)
local queue = {} -- messages waiting: { to, target, text, ctl, onSent }
local bucket, refilledAt = Link.BURST, nil
local pausedUntil = 0
local xidCounter = 0
local stats = { sent = 0, rejected = 0, received = 0, resent = 0, throttled = 0 }
local ticker

local function Now()
	return GetTime and GetTime() or 0
end

local function Group(n)
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1 "):reverse()
	return (out:gsub("^ ", ""))
end

----------------------------------------------------------------------------------------------------
-- Names. "Velikopter Kitchenchant" is name and surname (#77). A name typed without the first name is
-- expanded with the player's own first name: names are unique on a realm, so a stranger can't carry it.
----------------------------------------------------------------------------------------------------

local function Norm(name)
	name = tostring(name or ""):gsub("%-.*$", ""):lower():gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
	return name
end

local function OwnNames()
	local name, surname = UnitName("player")
	return name, surname
end

local function Expand(name)
	name = tostring(name or ""):gsub("%-.*$", ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
	if name == "" or #name > 60 then
		return nil
	end
	if not name:find(" ", 1, true) then
		local first = OwnNames()
		if first and first ~= "" then
			name = first .. " " .. name
		end
	end
	return name
end

local function IsSelf(name)
	local first, surname = OwnNames()
	if not first then
		return false
	end
	return Norm(name) == Norm(surname and (first .. " " .. surname) or first)
end

local function Peers()
	return db and db.peers or {}
end

local function PeerByKey(key)
	for _, p in ipairs(Peers()) do
		if Norm(p.name) == key then
			return p
		end
	end
	return nil
end

-- Adds a character to the list. Returns the stored name, or nil and why ("empty", "self", "known").
function Link.Add(name)
	if not db then
		return nil, "not ready"
	end
	local full = Expand(name)
	if not full then
		return nil, "empty"
	end
	if IsSelf(full) then
		return nil, "self"
	end
	if PeerByKey(Norm(full)) then
		return nil, "known"
	end
	db.peers[#db.peers + 1] = { name = full, got = {}, received = 0 }
	Runtime(Norm(full)).started = true
	Link.Hello(Norm(full))
	return full
end

function Link.Remove(name)
	local key = Norm(Expand(name) or name)
	for i, p in ipairs(Peers()) do
		if Norm(p.name) == key then
			table.remove(db.peers, i)
			rt[key] = nil
			for j = #queue, 1, -1 do
				if queue[j].to == key then
					table.remove(queue, j)
				end
			end
			return true
		end
	end
	return false
end

function Link.List()
	local out = {}
	for i, p in ipairs(Peers()) do
		out[i] = p.name
	end
	return out
end

-- The listed character a sender is, by the name the client gives in CHAT_MSG_ADDON; nil for anyone else.
local function Trusted(sender)
	if type(sender) ~= "string" then
		return nil
	end
	local key = Norm(sender)
	return PeerByKey(key) and key or nil
end

function Runtime(key)
	rt[key] = rt[key] or {}
	return rt[key]
end

function Link.Online(key, now)
	local r = rt[key]
	return r ~= nil and r.seen ~= nil and (now or Now()) - r.seen < Link.ONLINE
end

----------------------------------------------------------------------------------------------------
-- Sending: one queue, one byte bucket.
----------------------------------------------------------------------------------------------------

local function Enqueue(item, front)
	if front then
		table.insert(queue, 1, item)
	else
		queue[#queue + 1] = item
	end
	Link.Wake()
end

-- Control messages (small, they unblock the other side) go before data.
local function Control(key, text)
	local peer = PeerByKey(key)
	if not peer then
		return
	end
	local item = { to = key, target = peer.name, text = text, ctl = true }
	local at = 1
	while queue[at] and queue[at].ctl do
		at = at + 1
	end
	table.insert(queue, at, item)
	Link.Wake()
end

local function Data(key, text, onSent)
	local peer = PeerByKey(key)
	if peer then
		Enqueue({ to = key, target = peer.name, text = text, onSent = onSent })
	end
end

-- The client's answer to a send: nothing, true or 0 is sent; 3, 8 and 10 are throttle; the rest failed.
local function Sent(result)
	if result == nil or result == true or result == 0 then
		return "sent"
	end
	if THROTTLED[result] then
		return "throttled"
	end
	return "failed"
end

local function Refill(now)
	if refilledAt then
		bucket = math.min(Link.BURST, bucket + (now - refilledAt) * Link.RATE)
	end
	refilledAt = now
end

-- Sends what the bucket allows. Returns how many messages went out.
local function Drain(now)
	Refill(now)
	if now < pausedUntil then
		return 0
	end
	local n = 0
	while queue[1] do
		local item = queue[1]
		local cost = #item.text + #Link.PREFIX
		if bucket < cost then
			break
		end
		local ok, result = pcall(C_ChatInfo.SendAddonMessage, Link.PREFIX, item.text, "WHISPER", item.target)
		local state = ok and Sent(result) or "failed"
		if state == "throttled" then
			stats.throttled = stats.throttled + 1
			pausedUntil = now + Link.PAUSE
			break
		end
		table.remove(queue, 1)
		bucket = bucket - cost
		if state == "sent" then
			n = n + 1
			stats.sent = stats.sent + 1
			if item.onSent then
				item.onSent(now)
			end
		end
	end
	return n
end

----------------------------------------------------------------------------------------------------
-- Hello and poll
----------------------------------------------------------------------------------------------------

-- What I have from this peer and from my own scans, per house of this realm: send me what is newer.
local function HelloText(key)
	local peer = PeerByKey(key)
	local realm = GetRealmName() or ""
	local parts = { "H", tostring(Link.PROTO), realm }
	local market = ns.Market
	local houses = {}
	for houseKey in pairs(market and market.HouseKeys and market.HouseKeys() or {}) do
		houses[#houses + 1] = houseKey
	end
	table.sort(houses)
	local prefix = realm .. "|"
	for _, houseKey in ipairs(houses) do
		if houseKey:sub(1, #prefix) == prefix then
			local since = math.max(peer.got[houseKey] or 0, market.LastFullScan(houseKey) or 0)
			local field = houseKey .. SEP .. tostring(since)
			if #table.concat(parts, SEP) + #field + 1 < MSG_MAX - 20 then
				parts[#parts + 1] = houseKey
				parts[#parts + 1] = tostring(since)
			end
		end
	end
	return table.concat(parts, SEP)
end

-- Asks a peer for what is new (and, by its answer, tells it what I have).
function Link.Hello(key)
	local r = Runtime(key)
	r.helloAt = Now()
	for _, item in ipairs(queue) do
		if item.to == key and item.text:sub(1, 2) == "H" .. SEP then
			return false -- one is waiting already
		end
	end
	Control(key, HelloText(key))
	return true
end

-- "Sync now": a hello to every listed character, at once.
function Link.SyncNow()
	local n = 0
	for _, p in ipairs(Peers()) do
		if Link.Hello(Norm(p.name)) then
			n = n + 1
		end
	end
	return n
end

-- After an own scan: tell the online characters (each asks for what it lacks).
function Link.Push()
	for _, p in ipairs(Peers()) do
		local key = Norm(p.name)
		if Link.Online(key) then
			Control(key, "P" .. SEP .. Link.PROTO)
		end
	end
end

----------------------------------------------------------------------------------------------------
-- Sending a transfer
----------------------------------------------------------------------------------------------------

local function NewXid()
	xidCounter = xidCounter + 1
	return ("%x%x"):format(time() % 0xFFFFF, xidCounter % 0xFFF)
end

local function SendChunk(key, out, batch, seq)
	local payload = batch.chunks[seq]
	local text = table.concat({ "B", out.xid, tostring(batch.n), tostring(seq), tostring(#batch.chunks), payload }, SEP)
	batch.pending = batch.pending + 1
	Data(key, text, function(now)
		batch.pending = batch.pending - 1
		if batch.pending <= 0 then
			batch.sentAt = now
		end
	end)
end

local function SendBatch(key, out, batch)
	batch.pending, batch.sentAt = 0, nil
	for seq = 1, #batch.chunks do
		SendChunk(key, out, batch, seq)
	end
end

-- The next batch of the delta: records up to BATCH_BYTES. nil when the delta is finished and nothing is left.
-- The wire form of a batch's records: "<adler32 as 8 hex digits><deflated, encoded for the addon channel>".
function Link.Pack(raw)
	local lib = ns.LibDeflate
	return ("%08x"):format(lib:Adler32(raw)) .. lib:EncodeForWoWAddonChannel(lib:CompressDeflate(raw, { level = Link.LEVEL }))
end

-- The records of a wire batch; nil for anything that is not exactly what Pack made (bad checksum, truncated,
-- not deflate).
function Link.Unpack(wire)
	local lib = ns.LibDeflate
	if type(wire) ~= "string" or #wire < 10 or not wire:sub(1, 8):match("^%x+$") then
		return nil
	end
	local packed = lib:DecodeForWoWAddonChannel(wire:sub(9))
	local raw = packed and lib:DecompressDeflate(packed)
	if not raw or lib:Adler32(raw) ~= tonumber(wire:sub(1, 8), 16) then
		return nil
	end
	return raw
end

local function NextBatch(out)
	local records, bytes = {}, 0
	local done = false
	while bytes < Link.BATCH_BYTES do
		local list
		list, done = ns.Market.DeltaNext(out.delta, 1)
		for _, rec in ipairs(list) do
			records[#records + 1] = rec
			bytes = bytes + #rec + 1
		end
		if done then
			break
		end
	end
	out.finished = done
	if #records == 0 then
		return nil
	end
	table.insert(records, 1, "r" .. SEP .. (GetRealmName() or ""))
	local payload = Link.Pack(table.concat(records, "~"))
	local chunks = {}
	for at = 1, #payload, Link.CHUNK do
		chunks[#chunks + 1] = payload:sub(at, at + Link.CHUNK - 1)
	end
	out.nBatches = out.nBatches + 1
	return { n = out.nBatches, chunks = chunks, entries = #records, tries = 1, pending = 0 }
end

local function StartTransfer(key, realm, since)
	local r = Runtime(key)
	if r.out then
		return false
	end
	r.out = { xid = NewXid(), delta = ns.Market.DeltaStart(since, realm), nBatches = 0, sentEntries = 0, startedAt = Now() }
	Link.Wake()
	return true
end

local function PumpOut(key, r, now)
	local out = r.out
	if not out then
		return
	end
	local batch = out.batch
	if batch then
		if batch.pending == 0 and batch.sentAt and now - batch.sentAt > Link.ACK_WAIT then
			if batch.tries >= Link.TRIES then
				r.out = nil -- the other side is gone; the next hello starts again
				r.lastError = "no answer"
				return
			end
			batch.tries = batch.tries + 1
			stats.resent = stats.resent + 1
			SendBatch(key, out, batch)
		end
		return
	end
	if out.finished and out.sentEnd then
		r.out = nil
		return
	end
	if out.finished then
		Control(key, table.concat({ "E", out.xid, tostring(out.nBatches) }, SEP))
		out.sentEnd = true
		r.out = nil
		return
	end
	out.batch = NextBatch(out)
	if out.batch then
		SendBatch(key, out, out.batch)
	elseif out.finished then
		PumpOut(key, r, now)
	end
end

----------------------------------------------------------------------------------------------------
-- Receiving
----------------------------------------------------------------------------------------------------

local function Fields(text, count)
	local out, at = {}, 1
	for _ = 1, count - 1 do
		local s = text:find(SEP, at, true)
		if not s then
			break
		end
		out[#out + 1] = text:sub(at, s - 1)
		at = s + 1
	end
	out[#out + 1] = text:sub(at)
	return out
end

-- Connected realms share an auction house but each keeps its own realm name in the house keys (#358). A house
-- key of the other character's realm is rewritten to mine, and only to a key I would record myself: the
-- faction house of my own faction ("<realm>|H" or "|A"), or a neutral house ("<realm>|N:<Zone>"). nil for
-- anything else (another realm, the other faction's house, junk).
function Link.MapHouse(house, fromRealm)
	if type(house) ~= "string" or type(fromRealm) ~= "string" or fromRealm == "" then
		return nil
	end
	local head = fromRealm .. "|"
	if house:sub(1, #head) ~= head then
		return nil
	end
	local rest = house:sub(#head + 1)
	local letter = rest:match("^([HA])$")
	if letter then
		local faction = UnitFactionGroup and UnitFactionGroup("player")
		if letter ~= (faction == "Horde" and "H" or faction == "Alliance" and "A" or nil) then
			return nil
		end
	elseif not rest:match("^N:%w+$") then
		return nil
	end
	return (GetRealmName() or "") .. "|" .. rest
end

-- The records of a merged batch, turned into what Market.MergeIncoming takes. The sender's realm comes in the
-- batch's first record ("r"), else what its hello said; its house keys are mapped to mine here.
local function Parse(payload, maxT, peerRealm)
	local source = { houses = {}, items = {}, names = {}, itemInfo = {}, scans = {} }
	for record in payload:gmatch("[^~]+") do
		local kind = record:sub(1, 1)
		local f = Fields(record, kind == "e" and 4 or 6)
		if kind == "r" and f[2] and #f[2] <= 64 then
			peerRealm = f[2]
		elseif kind == "e" and f[4] and Link.MapHouse(f[2], peerRealm) then
			local house, key, packed = Link.MapHouse(f[2], peerRealm), f[3], f[4]
			source.houses[house] = true
			source.items[key] = source.items[key] or {}
			source.items[key][house] = packed
			local t = ns.Market.EntryTime(packed)
			if t and t > (maxT[house] or 0) then
				maxT[house] = t
			end
		elseif kind == "s" and f[5] and Link.MapHouse(f[2], peerRealm) then
			local house = Link.MapHouse(f[2], peerRealm)
			source.houses[house] = true
			source.scans[house] = source.scans[house] or {}
			table.insert(source.scans[house], { t = tonumber(f[3]), kind = f[4], items = tonumber(f[5]),
				lastOnly = tonumber(f[6]) })
		elseif kind == "f" and f[3] then
			source.itemInfo[f[2]] = f[3]
		elseif kind == "n" and f[3] then
			source.names[f[2]] = ns.Market.UnescapeText(f[3])
		end
	end
	return source
end

local function Missing(asm)
	local out = {}
	for seq = 1, asm.total do
		if not asm.chunks[seq] then
			out[#out + 1] = seq
			if #out >= 30 then
				break
			end
		end
	end
	return out
end

local function OnChunk(key, f, now)
	local r = Runtime(key)
	local xid, n, seq, total, payload = f[2], tonumber(f[3]), tonumber(f[4]), tonumber(f[5]), f[6]
	if not (xid and n and seq and total and payload) or total < 1 or total > Link.MAX_CHUNKS or seq < 1 or seq > total then
		return
	end
	local inc = r.inc
	if not inc or inc.xid ~= xid then
		inc = { xid = xid, asm = {}, merged = {}, priced = 0, entries = 0, maxT = {} }
		r.inc = inc
	end
	if inc.merged[n] then
		Control(key, table.concat({ "K", xid, tostring(n) }, SEP)) -- the K got lost: say it again
		return
	end
	local asm = inc.asm[n]
	if not asm or asm.total ~= total then
		asm = { chunks = {}, total = total, have = 0, nags = 0 }
		inc.asm[n] = asm
	end
	asm.lastAt = now
	if not asm.chunks[seq] then
		asm.chunks[seq] = payload
		asm.have = asm.have + 1
	end
	if asm.have < asm.total then
		return
	end
	local raw = Link.Unpack(table.concat(asm.chunks))
	if not raw then
		inc.asm[n] = nil -- corrupt or truncated: nothing is merged, no K, the sender sends the batch again
		stats.corrupt = (stats.corrupt or 0) + 1
		return
	end
	local job = ns.Market.MergeIncoming(Parse(raw, inc.maxT, (PeerByKey(key) or {}).realm), Link.DisplayName(key))
	inc.merged[n] = true
	inc.asm[n] = nil
	inc.priced = inc.priced + (job.priced or 0)
	inc.entries = inc.entries + (job.entries or 0)
	stats.received = stats.received + 1
	Control(key, table.concat({ "K", xid, tostring(n) }, SEP))
end

local function OnEnd(key, f)
	local r = Runtime(key)
	local inc = r.inc
	local peer = PeerByKey(key)
	if not (inc and peer and inc.xid == f[2]) then
		return
	end
	r.inc = nil
	for house, t in pairs(inc.maxT) do
		if t > (peer.got[house] or 0) then
			peer.got[house] = t
		end
	end
	peer.lastSync = time()
	peer.received = (peer.received or 0) + inc.priced
	peer.lastPriced = inc.priced
	if inc.priced > 0 then
		ns.Print(("Synced %s prices from %s"):format(Group(inc.priced), peer.name))
		ns.Notify("FULL_PRICES", "link") -- the vendor/flip/snipe check may run; not a reason to push back
	end
	ns.Notify("LINK_CHANGED")
end

local function OnHello(key, f, now)
	local r = Runtime(key)
	if tonumber(f[2]) ~= Link.PROTO or not f[3] or f[3] == "" or #f[3] > 64 then
		return
	end
	-- A listed character that answers a whisper is on a connected realm, whatever its name (#358).
	local peer = PeerByKey(key)
	if peer then
		peer.realm = f[3]
		peer.proto = nil
	end
	local since = {}
	for i = 4, #f - 1, 2 do
		local mine = Link.MapHouse(f[i], f[3])
		if mine then
			since[mine] = tonumber(f[i + 1]) or 0
		end
	end
	StartTransfer(key, GetRealmName() or "", since)
	if not r.helloAt or now - r.helloAt > 20 then
		Link.Hello(key) -- answer with what I lack
	end
end

-- CHAT_MSG_ADDON. Anything not from a listed character is dropped here.
function Link.OnMessage(prefix, text, channel, sender)
	if prefix ~= Link.PREFIX or type(text) ~= "string" then
		return
	end
	if channel ~= "WHISPER" then
		return
	end
	local key = Trusted(sender)
	if not key or IsSelf(sender) then
		stats.rejected = stats.rejected + 1
		return
	end
	local now = Now()
	local r = Runtime(key)
	r.seen = now
	local kind = text:sub(1, 1)
	if kind == "B" then
		OnChunk(key, Fields(text, 6), now)
		return
	end
	local f = Fields(text, 64)
	if (kind == "H" or kind == "P") and tonumber(f[2]) ~= Link.PROTO then
		local peer = PeerByKey(key)
		if peer then
			peer.proto = tonumber(f[2]) or 0 -- shown on the Status line; nothing is sent or read
		end
		return
	end
	if kind == "H" then
		OnHello(key, f, now)
	elseif kind == "P" then
		if tonumber(f[2]) == Link.PROTO and now - (r.helloAt or -1e9) >= 20 then
			Link.Hello(key)
		end
	elseif kind == "K" then
		local out = r.out
		local batch = out and out.batch
		if batch and out.xid == f[2] and batch.n == tonumber(f[3]) then
			out.sentEntries = out.sentEntries + batch.entries
			out.batch = nil
			Link.Wake()
		end
	elseif kind == "R" then
		local out = r.out
		local batch = out and out.batch
		if batch and out.xid == f[2] and batch.n == tonumber(f[3]) and f[4] then
			for seq in f[4]:gmatch("%d+") do
				seq = tonumber(seq)
				if batch.chunks[seq] then
					stats.resent = stats.resent + 1
					SendChunk(key, out, batch, seq)
				end
			end
		end
	elseif kind == "E" then
		OnEnd(key, f)
	end
end

----------------------------------------------------------------------------------------------------
-- The pump: everything that happens over time, with the clock given (the specs drive it).
----------------------------------------------------------------------------------------------------

local function PumpIn(key, r, now)
	local inc = r.inc
	if not inc then
		return
	end
	for n, asm in pairs(inc.asm) do
		if asm.lastAt and now - asm.lastAt > Link.RECV_WAIT then
			if asm.nags >= Link.NAGS then
				inc.asm[n] = nil -- given up; the sender sends the batch again after its own wait
			else
				asm.nags = asm.nags + 1
				asm.lastAt = now
				Control(key, table.concat({ "R", inc.xid, tostring(n), table.concat(Missing(asm), ",") }, SEP))
			end
		end
	end
end

function Link.Pump(now)
	now = now or Now()
	if not db then
		return
	end
	for _, p in ipairs(db.peers) do
		local key = Norm(p.name)
		local r = Runtime(key)
		if r.started and now - (r.helloAt or -1e9) >= (Link.Online(key, now) and Link.HELLO_ONLINE or Link.HELLO_OFFLINE) then
			Link.Hello(key)
		end
		PumpOut(key, r, now)
		PumpIn(key, r, now)
	end
	Drain(now)
end

local function Busy()
	if queue[1] then
		return true
	end
	for _, r in pairs(rt) do
		if r.out or r.inc then
			return true
		end
	end
	return false
end

-- A frame ticks the pump while there is anything to do, and every few seconds otherwise (hellos).
local acc = 0
function Link.Wake()
	if ticker or not CreateFrame or not db then
		return
	end
	ticker = CreateFrame("Frame")
	ticker:SetScript("OnUpdate", function(_, elapsed)
		acc = acc + elapsed
		if acc < (Busy() and 0.2 or 5) then
			return
		end
		acc = 0
		pcall(Link.Pump)
	end)
end

----------------------------------------------------------------------------------------------------
-- Status for Settings
----------------------------------------------------------------------------------------------------

function Link.DisplayName(key)
	local peer = PeerByKey(key)
	return peer and peer.name or key
end

local function Ago(seconds)
	return ns.Market.FormatAge(math.max(0, seconds)) .. " ago"
end

-- One entry per listed character: { name, online, lastSync, received, state }.
function Link.Status(now)
	local out = {}
	now = now or Now()
	for _, p in ipairs(Peers()) do
		local key = Norm(p.name)
		local r = rt[key] or {}
		local state
		if r.out then
			state = "sending"
		elseif r.inc then
			state = "receiving"
		end
		out[#out + 1] = { name = p.name, realm = p.realm, proto = p.proto, online = Link.Online(key, now), lastSync = p.lastSync, received = p.received or 0,
			state = state, error = r.lastError }
	end
	return out
end

function Link.StatusText()
	local list = Link.Status()
	if #list == 0 then
		return "No linked characters. Add the other account's characters by name; each side lists the other."
	end
	local lines = {}
	for _, s in ipairs(list) do
		local parts = { s.online and "online" or "not heard from (offline, other realm or faction, or no CraftWise)" }
		if s.proto then
			parts[#parts + 1] = ("other side runs an older CraftWise: sync version %d, this one is %d"):format(s.proto, Link.PROTO)
		end
		if s.state then
			parts[#parts + 1] = s.state
		end
		if s.lastSync then
			parts[#parts + 1] = "last sync " .. Ago(time() - s.lastSync)
		else
			parts[#parts + 1] = "not synced yet"
		end
		parts[#parts + 1] = Group(s.received) .. " prices received"
		local realm = s.realm and s.realm ~= (GetRealmName() or "") and (" (" .. (s.realm:match("Realm %d+") or s.realm) .. ")") or ""
		lines[#lines + 1] = s.name .. realm .. ": " .. table.concat(parts, " · ")
	end
	return table.concat(lines, "\n")
end

function Link.Stats()
	return stats
end

function Link.QueueLength()
	return #queue
end

----------------------------------------------------------------------------------------------------
-- Popup to type a name (the client has no clipboard or prompt API of its own)
----------------------------------------------------------------------------------------------------

local popup

function Link.Prompt()
	if not popup then
		local Style = ns.Style
		local f = CreateFrame("Frame", "CraftWiseLinkPrompt", UIParent)
		f:SetSize(360, 96)
		f:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
		f:SetFrameStrata("DIALOG")
		f:EnableMouse(true)
		local bg = f:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints(f)
		Style.Fill(bg, Style.C.sheet)
		Style.Border(f, Style.C.ruleStrong)
		local title = Style.Text(f, "Small", "text2")
		title:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -10)
		title:SetText("Character of your other account (name or surname), Enter adds it, Esc closes")
		local box = CreateFrame("EditBox", nil, f)
		box:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -40)
		box:SetSize(336, 24)
		box:SetAutoFocus(false)
		box:SetFontObject(Style.Fonts.Body or Style.Fonts.Small)
		box:SetTextColor(Style.C.text[1], Style.C.text[2], Style.C.text[3], 1)
		box:SetScript("OnEscapePressed", function()
			f:Hide()
		end)
		box:SetScript("OnEnterPressed", function(self)
			local name, why = Link.Add(self:GetText())
			if name then
				ns.Print("linked " .. name)
				ns.Notify("LINK_CHANGED")
			elseif why == "known" then
				ns.Print("already linked")
			elseif why == "self" then
				ns.Print("that is this character")
			end
			self:SetText("")
			f:Hide()
		end)
		f.box = box
		f:Hide()
		popup = f
	end
	popup:Show()
	popup.box:SetFocus()
end

----------------------------------------------------------------------------------------------------
-- Slash: /craftwise link [add <name> | remove <name> | sync]
----------------------------------------------------------------------------------------------------

function Link.Slash(arg)
	local verb, rest = (arg or ""):match("^(%S*)%s*(.-)$")
	verb = verb:lower()
	if verb == "add" then
		local name, why = Link.Add(rest)
		if name then
			ns.Print("linked " .. name .. ". Add this character on the other account too.")
		else
			ns.Print(why == "known" and "already linked" or why == "self" and "that is this character" or "usage: /craftwise link add <name>")
		end
	elseif verb == "remove" then
		ns.Print(Link.Remove(rest) and "unlinked" or "not on the list")
	elseif verb == "sync" then
		ns.Print(("asked %d linked character(s) for new prices"):format(Link.SyncNow()))
	else
		for line in Link.StatusText():gmatch("[^\n]+") do
			ns.Print(line)
		end
	end
	ns.Notify("LINK_CHANGED")
end

----------------------------------------------------------------------------------------------------
-- Events
----------------------------------------------------------------------------------------------------

ns.Listen("DB_READY", function()
	ns.db.link = type(ns.db.link) == "table" and ns.db.link or {}
	db = ns.db.link
	db.peers = type(db.peers) == "table" and db.peers or {}
	for _, p in ipairs(db.peers) do
		p.got = type(p.got) == "table" and p.got or {}
	end
	if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
		pcall(C_ChatInfo.RegisterAddonMessagePrefix, Link.PREFIX)
	end
end)

ns.On("CHAT_MSG_ADDON", function(_, prefix, text, channel, sender)
	if prefix == Link.PREFIX and db then
		pcall(Link.OnMessage, prefix, text, channel, sender)
	end
end)

-- The first hello a few seconds after login (the other client may still be loading); after that the pump
-- repeats it.
ns.On("PLAYER_LOGIN", function()
	if not db then
		return
	end
	local function start()
		for _, p in ipairs(db.peers) do
			Runtime(Norm(p.name)).started = true
		end
		Link.SyncNow()
	end
	C_Timer.NewTimer(Link.LOGIN_DELAY, start)
	Link.Wake()
end)

-- An own full scan was stored: tell the online characters.
ns.Listen("FULL_PRICES", function(source)
	if source ~= "link" and db and #db.peers > 0 then
		Link.Push()
	end
end)
