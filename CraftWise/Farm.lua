-- Farm tracker (#126): a farming session's time, looted coin and items, valued with CraftWise prices,
-- gold per hour, the priciest drop and a zone split; finished sessions are kept as history and exported
-- in the character snapshot. The window is UI/FarmFrame.lua.
--
--   * What was looted comes from the loot feed (LootFeed.lua): the same items and coin the loot toast
--     shows. Coin counts once it is paired with CHAT_MSG_MONEY, so vendor sales, mail and quest
--     rewards never count.
--   * Values are worked out when shown, from the counts, so a price that arrives later (an AH scan, an
--     item the client loads) is used at once. Per unit: ns.GetSellValue (AH at the profit house after
--     the cut, or vendor, whichever the addon uses); bind on pickup and quest items (bindType 1 and 4,
--     C_Item.GetItemInfo) can't go to the AH, so vendor only. An item with no price at all stays
--     unknown: it is counted apart and never valued. Totals: the best way to sell (`items`), vendor only
--     (`vendor`), the part that rests on AH prices (`ah`) and of that the part from AH prices older than
--     STALE_DAYS (`stale`, the age the price came with; the profit window warns from the same age).
--     A finished session keeps the values it had when it ended.
--   * Time: wall clock (time()), so a session survives /reload and relogs. Elapsed = time while
--     running; pauses don't count. At logout a running session stops counting and goes on at the next
--     login (time offline is not counted). With no loot for idleMinutes it pauses on its own as of the
--     last loot (the idle stretch doesn't count) and goes on with the next loot.
--   * Containers opened from the bags (#135, the loot feed's "opened"): their contents are loot like any
--     other. A container counted in this session leaves the list when it is opened (one unit, from the zone
--     it was looted in, the current zone first), so it is replaced by its contents and nothing counts twice;
--     a container from before the session was never counted, its contents are new loot of this session.
--     The loot log keeps the container's line (it did drop) and adds the contents' lines.
--   * A session starts with the first loot (autoStart) or the Start button. While paused by hand,
--     loot is not counted. Removing an item from the list drops it from the session and ignores it for
--     the rest of the session (a quest item, something you keep).
--   * Fishing (#130): catches come from Fishing.lua's own catch record (Fishing.Subscribe), never detected
--     again here. Per zone: catches, the catch's items (as the loot window held them), coin from a catch
--     window that had a coin slot (the next coin loot within FISH_COIN_SECONDS), containers caught this
--     session and opened (from the loot feed, #135: the container leaves the fishing items, its contents and
--     coin join them as they are looted, so nothing counts twice; containers caught before the session are
--     left out of fishing). Fishing time: the session time between two
--     catches when they are at most FISH_GAP apart (casts in a row); rates use only the catches that time
--     was measured for (`timed`). Valued like the rest of the window, unknown values apart.
--   * Loot log (#130): one line per counted drop, in order: item and count or coin, zone, from a catch or
--     not, time. Packed strings in session.log (oldest first, at most LOG_MAX; older lines are dropped and
--     counted in logDropped): "<seconds since start>,<itemID>,<count>,<zone>[,f]" or
--     "<seconds since start>,c,<copper>,<zone>[,f]", zone = index into session.logZones, f = from a catch.
--     Valued when shown, like the list. Kept with the session in the history for the newest HISTORY_LOGS
--     finished sessions; older ones keep only logLines (a full log is about 20 KB in the SavedVariables).
--   * Storage: CraftWiseDB.farm = settings (Core.lua defaults); CraftWiseDB.farmLog[ns.CharKey()] =
--     { current = session, history = finished sessions, newest first, at most HISTORY_MAX }.
local _, ns = ...

local F = {}
ns.Farm = F

F.HISTORY_MAX = 50
F.TOP_ITEMS = 3 -- items kept per finished session
F.MAX_ZONES = 3 -- zones kept per finished session (most time first; the rest summed into zonesMore)
F.SNAPSHOT_SESSIONS = 10 -- finished sessions in the snapshot (the rest stay in CraftWiseDB.farmLog)
F.STALE_DAYS = 1
F.MIN_RATE_SECONDS = 60 -- no per-hour figure from less than a minute
F.MIN_SCALE, F.MAX_SCALE = 0.5, 2
F.MAX_IDLE = 120
F.UNKNOWN_ZONE = "unknown zone"
F.FISH_GAP = 120 -- seconds: two catches at most this far apart (session time) are casts in a row
F.LOG_MAX = 500 -- loot log lines kept per session (newest)
F.HISTORY_LOGS = 10 -- finished sessions that keep their loot log (older ones keep the line count only)
F.SNAPSHOT_LOG = 20 -- loot log lines of the open session in the snapshot (newest)
F.FISH_COIN_SECONDS = 5 -- a catch window with coin: the coin loot that follows within this time is fishing coin

local function Settings()
	return ns.db and ns.db.farm
end

function F.Enabled()
	local s = Settings()
	return s ~= nil and s.enabled ~= false
end

function F.AutoStart()
	local s = Settings()
	return s ~= nil and s.autoStart ~= false
end

-- Minutes without loot before a running session pauses itself; 0 = never.
function F.IdleMinutes()
	local s = Settings()
	return s and tonumber(s.idleMinutes) or 5
end

function F.Now()
	return time()
end

local function UI()
	return ns.FarmFrame
end

local function Changed()
	ns.Notify("FARM_CHANGED")
end

----------------------------------------------------------------------------------------------------
-- Storage
----------------------------------------------------------------------------------------------------

-- This character's { current, history }; nil before the DB or the character is known.
function F.Log()
	local key = ns.db and ns.CharKey()
	if not key then
		return nil
	end
	ns.db.farmLog = ns.db.farmLog or {}
	local log = ns.db.farmLog[key]
	if not log then
		log = { history = {} }
		ns.db.farmLog[key] = log
	end
	log.history = log.history or {}
	return log
end

function F.Current()
	local log = F.Log()
	return log and log.current
end

function F.History()
	local log = F.Log()
	return log and log.history or {}
end

local function ZoneNow()
	local z = GetRealZoneText and GetRealZoneText()
	if z == nil or (issecretvalue and issecretvalue(z)) or type(z) ~= "string" or z == "" then
		return nil
	end
	return z
end

----------------------------------------------------------------------------------------------------
-- Session maths (pure: a session table and the time)
----------------------------------------------------------------------------------------------------

function F.New(now, zone)
	return { start = now, active = 0, resumedAt = now, zone = zone or F.UNKNOWN_ZONE, coin = 0,
		zones = {}, links = {}, ignored = {} }
end

local function Zone(s, name)
	local z = s.zones[name]
	if not z then
		z = { seconds = 0, coin = 0, items = {} }
		s.zones[name] = z
	end
	return z
end

function F.Running(s)
	return s ~= nil and s.resumedAt ~= nil
end

-- Counts the running time up to `upTo` (into the session and its current zone); keeps running.
function F.Fold(s, upTo)
	if not s.resumedAt then
		return
	end
	local d = math.max(0, upTo - s.resumedAt)
	s.active = (s.active or 0) + d
	local z = Zone(s, s.zone)
	z.seconds = z.seconds + d
	s.resumedAt = math.max(s.resumedAt, upTo)
end

-- Idle auto-pause: a running session without loot for idleMinutes stops as of its last activity (the
-- last loot, or when it started running if later). Returns true when it paused.
function F.Update(s, now, idleMinutes)
	if not (s and s.resumedAt) then
		return false
	end
	idleMinutes = idleMinutes or F.IdleMinutes()
	if not idleMinutes or idleMinutes <= 0 then
		return false
	end
	local last = math.max(s.resumedAt, s.lastLoot or 0)
	if now - last < idleMinutes * 60 then
		return false
	end
	F.Fold(s, last)
	s.resumedAt, s.autoPaused = nil, true
	return true
end

-- Seconds counted so far (running time only).
function F.Elapsed(s, now)
	if not s then
		return 0
	end
	local running = s.resumedAt and math.max(0, now - s.resumedAt) or 0
	return (s.active or 0) + running
end

function F.Pause(s, now)
	if not s.resumedAt then
		s.paused, s.autoPaused = true, nil
		return
	end
	F.Fold(s, now)
	s.resumedAt, s.paused, s.autoPaused = nil, true, nil
end

function F.Resume(s, now, zone)
	if s.resumedAt then
		return
	end
	s.resumedAt, s.paused, s.autoPaused, s.resumeOnLogin = now, nil, nil, nil
	s.zone = zone or s.zone
end

-- The player is in `zone` now: the running time so far goes to the zone left.
function F.SetZone(s, zone, now)
	if not zone or zone == s.zone then
		return
	end
	F.Fold(s, now)
	s.zone = zone
end

function F.AddItem(s, itemID, count, link)
	if s.ignored[itemID] then
		return false
	end
	local z = Zone(s, s.zone)
	z.items[itemID] = (z.items[itemID] or 0) + (count or 1)
	if link then
		s.links[itemID] = link
	end
	return true
end

function F.AddCoin(s, copper)
	local z = Zone(s, s.zone)
	z.coin = z.coin + copper
	s.coin = (s.coin or 0) + copper
end

-- A container opened (#135): when counted in this session, one unit leaves the list, from the current zone
-- if it was looted there, else from the first zone (by name) that has it. Returns that zone, or nil.
function F.OpenContainer(s, containerID)
	if not containerID then
		return nil
	end
	local name
	local here = s.zones[s.zone]
	if here and (here.items[containerID] or 0) > 0 then
		name = s.zone
	else
		local names = {}
		for zoneName, z in pairs(s.zones) do
			if (z.items[containerID] or 0) > 0 then
				names[#names + 1] = zoneName
			end
		end
		table.sort(names)
		name = names[1]
	end
	if not name then
		return nil
	end
	local items = s.zones[name].items
	items[containerID] = items[containerID] - 1
	if items[containerID] <= 0 then
		items[containerID] = nil
	end
	return name
end

-- Drops an item from the session and ignores it from now on.
function F.Remove(s, itemID)
	for _, z in pairs(s.zones) do
		z.items[itemID] = nil
		if z.fish then
			z.fish.items[itemID] = nil
		end
	end
	s.links[itemID] = nil
	s.ignored[itemID] = true
	if s.log then
		local kept = {}
		for _, line in ipairs(s.log) do
			if F.UnpackLog(line).itemID ~= itemID then
				kept[#kept + 1] = line
			end
		end
		s.log = kept
	end
end

-- { [itemID] = units } over all zones.
function F.Counts(s)
	local counts = {}
	for _, z in pairs(s.zones) do
		for id, n in pairs(z.items) do
			counts[id] = (counts[id] or 0) + n
		end
	end
	return counts
end

function F.HasLoot(s)
	return s ~= nil and ((s.coin or 0) > 0 or next(F.Counts(s)) ~= nil)
end

-- Loot log (#130): appends one drop. kind "item" (a = itemID, b = count) or "coin" (a = copper).
function F.LogDrop(s, now, kind, a, b, fishing)
	s.log, s.logZones = s.log or {}, s.logZones or {}
	local zone = s.zone or F.UNKNOWN_ZONE
	local zi
	for i, name in ipairs(s.logZones) do
		if name == zone then
			zi = i
			break
		end
	end
	if not zi then
		s.logZones[#s.logZones + 1] = zone
		zi = #s.logZones
	end
	local dt = math.max(0, now - (s.start or now))
	local line
	if kind == "coin" then
		line = ("%d,c,%d,%d"):format(dt, a, zi)
	else
		line = ("%d,%d,%d,%d"):format(dt, a, b or 1, zi)
	end
	s.log[#s.log + 1] = fishing and (line .. ",f") or line
	while #s.log > F.LOG_MAX do
		table.remove(s.log, 1)
		s.logDropped = (s.logDropped or 0) + 1
	end
end

-- One packed log line: { dt, itemID, n } or { dt, copper }, plus zi (zone index) and fish.
function F.UnpackLog(line)
	local dt, what, amount, zi, flag = line:match("^(%d+),(%w+),(%d+),(%d+),?(%a*)$")
	local e = { dt = tonumber(dt), zi = tonumber(zi), fish = flag == "f" or nil }
	if what == "c" then
		e.copper = tonumber(amount)
	else
		e.itemID, e.n = tonumber(what), tonumber(amount)
	end
	return e
end

-- The log, newest first, valued now: { t (Unix time), itemID, n, link, copper, zone, fish, value, unit,
-- source, stale, age, label, noAuction } (value nil = unknown; coin lines: copper = value).
function F.LogEntries(s)
	local out, values = {}, {}
	local log, zones = s.log or {}, s.logZones or {}
	for i = #log, 1, -1 do
		local e = F.UnpackLog(log[i])
		e.t, e.zone = (s.start or 0) + (e.dt or 0), zones[e.zi] or F.UNKNOWN_ZONE
		if e.itemID then
			values[e.itemID] = values[e.itemID] or F.UnitValue(e.itemID)
			local v = values[e.itemID]
			e.link, e.unit, e.source, e.stale, e.age, e.label, e.noAuction = s.links and s.links[e.itemID], v.best,
				v.source, v.stale, v.age, v.label, v.noAuction
			e.value = v.best and math.floor(v.best * e.n + 0.5) or nil
		else
			e.value = e.copper
		end
		out[#out + 1] = e
	end
	return out
end

-- Fishing of one zone, created on first use: { catches, timed, seconds, coin, items = { [itemID] = units }, opened }.
local function Fish(s, name)
	local z = Zone(s, name)
	if not z.fish then
		z.fish = { catches = 0, timed = 0, seconds = 0, coin = 0, items = {}, opened = 0 }
	end
	return z.fish
end

-- A catch (Fishing.lua's record: its items) in the session's current zone at `now`.
function F.AddCatch(s, items, now)
	local f = Fish(s, s.zone)
	f.catches = f.catches + 1
	local el = F.Elapsed(s, now)
	if s.fishAt and el - s.fishAt <= F.FISH_GAP then
		f.seconds = f.seconds + (el - s.fishAt)
		f.timed = f.timed + 1
	end
	s.fishAt = el
	for id, n in pairs(items or {}) do
		if not s.ignored[id] then
			f.items[id] = (f.items[id] or 0) + n
		end
	end
end

function F.AddFishCoin(s, zone, copper)
	local f = Fish(s, zone or s.zone)
	f.coin = f.coin + copper
end

-- A container opened: when one of this session's catches, it leaves the fishing items of the zone it was
-- caught in (the current zone first) and `items` (if given) join them; the farm tracker passes none and adds
-- the contents as they are looted (F.AddFishItem). Returns that zone, or nil (not caught in this session:
-- left out).
function F.OpenCatch(s, containerID, items)
	local name
	local here = s.zones[s.zone]
	if here and here.fish and (here.fish.items[containerID] or 0) > 0 then
		name = s.zone
	else
		local names = {}
		for zoneName, z in pairs(s.zones) do
			if z.fish and (z.fish.items[containerID] or 0) > 0 then
				names[#names + 1] = zoneName
			end
		end
		table.sort(names)
		name = names[1]
	end
	if not name then
		return nil
	end
	local f = s.zones[name].fish
	f.items[containerID] = f.items[containerID] - 1
	if f.items[containerID] <= 0 then
		f.items[containerID] = nil
	end
	f.opened = f.opened + 1
	for id, n in pairs(items or {}) do
		if not s.ignored[id] then
			f.items[id] = (f.items[id] or 0) + n
		end
	end
	return name
end

-- An item from a caught container, into the fishing items of the zone the container was caught in.
function F.AddFishItem(s, zone, itemID, count)
	if s.ignored[itemID] then
		return
	end
	local f = Fish(s, zone or s.zone)
	f.items[itemID] = (f.items[itemID] or 0) + (count or 1)
end

function F.Catches(s)
	local n = 0
	for _, z in pairs(s and s.zones or {}) do
		n = n + (z.fish and z.fish.catches or 0)
	end
	return n
end

----------------------------------------------------------------------------------------------------
-- Values
----------------------------------------------------------------------------------------------------

-- bindType (GetItemInfo's 14th value): 1 bind on pickup, 4 quest item; neither can be auctioned.
local function NoAuction(itemID)
	local getInfo = C_Item and C_Item.GetItemInfo
	local bind = getInfo and select(14, getInfo(itemID))
	return bind == 1 or bind == 4
end

-- One unit: { best (copper, nil = unknown), source "auction"|"vendor", age (days), stale, label,
-- cutUnverified, vendor (copper; nil = unknown, 0 = vendors don't buy it), noAuction }.
function F.UnitValue(itemID)
	local vendor = ns.GetVendorSellPrice and ns.GetVendorSellPrice(itemID)
	local v = { vendor = vendor, noAuction = NoAuction(itemID) or nil }
	if v.noAuction then
		if vendor and vendor > 0 then
			v.best, v.source, v.label = vendor, "vendor", "vendor"
		end
	else
		local sell = ns.GetSellValue and ns.GetSellValue(itemID)
		if sell and sell.copper and sell.copper > 0 then
			v.best, v.source, v.age, v.label, v.cutUnverified = sell.copper, sell.source, sell.age, sell.label, sell.cutUnverified
		end
	end
	v.stale = (v.source == "auction" and v.age ~= nil and v.age > F.STALE_DAYS) or nil
	return v
end

local function Rate(copper, seconds)
	if not seconds or seconds < F.MIN_RATE_SECONDS then
		return nil
	end
	return math.floor(copper * 3600 / seconds + 0.5)
end
F.Rate = Rate

local function Stack(unit, n)
	return math.floor(unit * n + 0.5)
end

local function ItemName(itemID, link)
	local name = ns.ItemInfoNow and ns.ItemInfoNow(itemID)
	return name or (type(link) == "string" and link:match("%[(.-)%]")) or nil
end

-- Everything the window and the history show, valued now:
-- { seconds, coin, items, vendor, vendorUnknown, ah, stale, unknownUnits, unknownItems, total, gph,
--   coinGph, priciest = row, rows = { itemID, n, link, unit, value, source, stale, age, label } (best
--   value first, unknown last), zones = { zone, seconds, coin, items, unknownUnits, gph } (most time first) }
function F.Totals(s, now)
	local t = { seconds = F.Elapsed(s, now), coin = s.coin or 0, items = 0, vendor = 0, vendorUnknown = 0, ah = 0,
		stale = 0, unknownUnits = 0, unknownItems = 0, rows = {}, zones = {} }
	local values = {}
	local function Value(id)
		values[id] = values[id] or F.UnitValue(id)
		return values[id]
	end
	for id, n in pairs(F.Counts(s)) do
		local v = Value(id)
		local row = { itemID = id, n = n, link = s.links[id], unit = v.best, source = v.source, stale = v.stale,
			age = v.age, label = v.label, cutUnverified = v.cutUnverified, noAuction = v.noAuction }
		if v.best then
			row.value = Stack(v.best, n)
			t.items = t.items + row.value
			if v.source == "auction" then
				t.ah = t.ah + row.value
				if v.stale then
					t.stale = t.stale + row.value
				end
			end
			local p = t.priciest
			if not p or v.best > p.unit or (v.best == p.unit and id < p.itemID) then
				t.priciest = row
			end
		else
			t.unknownUnits, t.unknownItems = t.unknownUnits + n, t.unknownItems + 1
		end
		if v.vendor then
			t.vendor = t.vendor + Stack(v.vendor, n)
		else
			t.vendorUnknown = t.vendorUnknown + n
		end
		t.rows[#t.rows + 1] = row
	end
	table.sort(t.rows, function(a, b)
		if (a.value ~= nil) ~= (b.value ~= nil) then
			return a.value ~= nil
		end
		if a.value and a.value ~= b.value then
			return a.value > b.value
		end
		return a.itemID < b.itemID
	end)
	t.total = t.coin + t.items
	t.gph, t.coinGph = Rate(t.total, t.seconds), Rate(t.coin, t.seconds)
	for name, z in pairs(s.zones) do
		local seconds = z.seconds
		if s.resumedAt and name == s.zone then
			seconds = seconds + math.max(0, now - s.resumedAt)
		end
		local zone = { zone = name, seconds = seconds, coin = z.coin, items = 0, unknownUnits = 0 }
		for id, n in pairs(z.items) do
			local v = Value(id)
			if v.best then
				zone.items = zone.items + Stack(v.best, n)
			else
				zone.unknownUnits = zone.unknownUnits + n
			end
		end
		zone.gph = Rate(zone.coin + zone.items, seconds)
		t.zones[#t.zones + 1] = zone
	end
	table.sort(t.zones, function(a, b)
		if a.seconds ~= b.seconds then
			return a.seconds > b.seconds
		end
		return a.zone < b.zone
	end)
	t.fish = F.FishTotals(s, Value)
	return t
end

-- Rates of a fishing block: catches per hour and gold per hour, from the timed catches and their time.
local function FishRates(f)
	f.value = f.coin + f.items
	f.perCatch = f.catches > 0 and math.floor(f.value / f.catches + 0.5) or nil
	if f.timed > 0 and f.seconds >= F.MIN_RATE_SECONDS then
		f.cph = math.floor(f.timed * 36000 / f.seconds + 0.5) / 10
		f.gph = math.floor(f.value * f.timed * 3600 / (f.catches * f.seconds) + 0.5)
	end
end

-- The session's fishing, valued now; nil without catches:
-- { catches, timed, seconds, coin, items, unknownUnits, value, perCatch, cph, gph, opened,
--   best = { itemID, unit, n, link } (caught item with the highest value per unit),
--   zones = { { zone, catches, timed, seconds, coin, items, unknownUnits, value, perCatch, cph, gph, opened } }
--   (most catches first) }
function F.FishTotals(s, Value)
	Value = Value or F.UnitValue
	local t = { catches = 0, timed = 0, seconds = 0, coin = 0, items = 0, unknownUnits = 0, opened = 0, zones = {} }
	for name, z in pairs(s.zones) do
		local f = z.fish
		if f and (f.catches > 0 or f.opened > 0) then
			local zone = { zone = name, catches = f.catches, timed = f.timed, seconds = f.seconds, coin = f.coin, items = 0,
				unknownUnits = 0, opened = f.opened }
			for id, n in pairs(f.items) do
				local v = Value(id)
				if v.best then
					zone.items = zone.items + Stack(v.best, n)
					local b = t.best
					if not b or v.best > b.unit or (v.best == b.unit and id < b.itemID) then
						t.best = { itemID = id, unit = v.best, link = s.links[id], source = v.source }
					end
				else
					zone.unknownUnits = zone.unknownUnits + n
				end
			end
			FishRates(zone)
			for _, k in ipairs({ "catches", "timed", "seconds", "coin", "items", "unknownUnits", "opened" }) do
				t[k] = t[k] + zone[k]
			end
			t.zones[#t.zones + 1] = zone
		end
	end
	if t.catches == 0 then
		return nil
	end
	FishRates(t)
	table.sort(t.zones, function(a, b)
		if a.catches ~= b.catches then
			return a.catches > b.catches
		end
		return a.zone < b.zone
	end)
	return t
end

-- A session as history keeps it (and the snapshot exports it): values as of `now`.
-- { start, stop, seconds, zone, coin, items, vendor, ah, stale, unknown, gph, coinGph,
--   zones = { { zone, seconds, coin, items, gph } } (MAX_ZONES), zonesMore, top = { { id, name, n, value, source } },
--   fish = { catches, timed, seconds, coin, items, unknown, opened, perCatch, cph, gph, best = { id, name, value },
--   zones = { { zone, catches, timed, seconds, coin, items, unknown, opened } } (MAX_ZONES), zonesMore } (with catches),
--   log, logZones, logDropped, logLines (the loot log as the session had it, #130) }
function F.Summary(s, now)
	local t = F.Totals(s, now)
	local sum = { start = s.start, stop = now, seconds = t.seconds, coin = t.coin, items = t.items, vendor = t.vendor,
		ah = t.ah, stale = t.stale, unknown = t.unknownUnits, gph = t.gph, coinGph = t.coinGph, zones = {}, top = {} }
	if t.vendorUnknown > 0 then
		sum.vendorUnknown = t.vendorUnknown
	end
	for i, z in ipairs(t.zones) do
		if i <= F.MAX_ZONES then
			sum.zones[i] = { zone = z.zone, seconds = z.seconds, coin = z.coin, items = z.items, gph = z.gph }
		else
			sum.zonesMore = (sum.zonesMore or 0) + 1
		end
	end
	sum.zone = sum.zones[1] and sum.zones[1].zone or s.zone
	for i = 1, math.min(F.TOP_ITEMS, #t.rows) do
		local r = t.rows[i]
		if r.value then
			sum.top[#sum.top + 1] = { id = r.itemID, name = ItemName(r.itemID, r.link), n = r.n, value = r.value, source = r.source }
		end
	end
	if s.log and #s.log > 0 then
		sum.log, sum.logZones, sum.logDropped, sum.logLines = {}, {}, s.logDropped, #s.log
		for i, line in ipairs(s.log) do
			sum.log[i] = line
		end
		for i, z in ipairs(s.logZones or {}) do
			sum.logZones[i] = z
		end
	end
	local f = t.fish
	if f then
		sum.fish = { catches = f.catches, timed = f.timed, seconds = f.seconds, coin = f.coin, items = f.items,
			unknown = f.unknownUnits, opened = f.opened, perCatch = f.perCatch, cph = f.cph, gph = f.gph, zones = {} }
		if f.best then
			sum.fish.best = { id = f.best.itemID, name = ItemName(f.best.itemID, f.best.link), value = f.best.unit }
		end
		for i, z in ipairs(f.zones) do
			if i <= F.MAX_ZONES then
				sum.fish.zones[i] = { zone = z.zone, catches = z.catches, timed = z.timed, seconds = z.seconds, coin = z.coin,
					items = z.items, unknown = z.unknownUnits, opened = z.opened }
			else
				sum.fish.zonesMore = (sum.fish.zonesMore or 0) + 1
			end
		end
	end
	return sum
end

----------------------------------------------------------------------------------------------------
-- Actions (the current session of this character)
----------------------------------------------------------------------------------------------------

-- Applies the idle pause to the current session; returns it.
function F.Tick(now)
	local s = F.Current()
	if s and F.Update(s, now or F.Now()) then
		Changed()
	end
	return s
end

function F.Start(now)
	local log = F.Log()
	if not log then
		return nil
	end
	now = now or F.Now()
	if log.current then
		F.Resume(log.current, now, ZoneNow())
	else
		log.current = F.New(now, ZoneNow())
	end
	Changed()
	return log.current
end

-- Pause or resume (Start when there is no session).
function F.TogglePause(now)
	now = now or F.Now()
	local s = F.Tick(now)
	if not s then
		return F.Start(now)
	end
	if F.Running(s) then
		F.Pause(s, now)
	else
		F.Resume(s, now, ZoneNow())
	end
	Changed()
	return s
end

-- Ends the current session: kept in the history when anything was looted. Returns its summary.
function F.Reset(now)
	local log = F.Log()
	local s = log and log.current
	if not s then
		return nil
	end
	now = now or F.Now()
	F.Update(s, now)
	F.Fold(s, now)
	local sum
	if F.HasLoot(s) then
		sum = F.Summary(s, now)
		table.insert(log.history, 1, sum)
		while #log.history > F.HISTORY_MAX do
			table.remove(log.history)
		end
		local older = log.history[F.HISTORY_LOGS + 1]
		if older and older.log then
			older.logLines, older.log, older.logZones = older.logLines or #older.log, nil, nil
		end
	end
	log.current = nil
	Changed()
	return sum
end

function F.RemoveItem(itemID)
	local s = F.Current()
	if s then
		F.Remove(s, itemID)
		Changed()
	end
end

-- The session a loot at `now` counts in: started on the first loot (autoStart; not when `noStart`),
-- resumed after an idle or logout pause, nil while paused by hand or off.
local function Accept(now, noStart)
	if not F.Enabled() then
		return nil
	end
	local log = F.Log()
	if not log then
		return nil
	end
	local s = log.current
	if s then
		F.Update(s, now)
	end
	if not s then
		if noStart or not F.AutoStart() then
			return nil
		end
		s = F.New(now, ZoneNow())
		log.current = s
		local st = Settings()
		if st and st.shown ~= false and UI() then
			UI().Show()
		end
	elseif s.paused then
		return nil -- paused by hand: not counted
	elseif not s.resumedAt then
		F.Resume(s, now, ZoneNow()) -- auto-paused (idle, logout): the next loot goes on
	end
	F.SetZone(s, ZoneNow(), now)
	return s
end

local fishCoin -- { zone, at (GetTime) }: a catch or caught container window had coin; the next coin loot is fishing's
local fishItems -- { items = { [itemID] = units }, at }: the last catch's items, to mark their loot lines in the log
local opening -- { id, fishZone }: the last container opened (#135); fishZone when it was this session's catch

-- A container opened from the bags (#135): it leaves the session when it was counted in it.
local function OnOpened(data)
	fishCoin, fishItems, opening = nil, nil, nil
	local now = F.Now()
	local s = Accept(now, true)
	if not s then
		return
	end
	local zone = F.OpenContainer(s, data.container)
	local fishZone = data.container and F.OpenCatch(s, data.container) or nil
	opening = { id = data.opening, fishZone = fishZone }
	if fishZone and data.coin then
		fishCoin = { zone = fishZone, at = GetTime() }
	end
	if zone or fishZone then
		Changed()
	end
end

-- A loot from the feed.
function F.OnFeed(kind, data)
	if kind == "opened" then
		return OnOpened(data)
	end
	local now = F.Now()
	local s = Accept(now)
	if not s then
		return
	end
	if kind == "item" then
		if not F.AddItem(s, data.itemID, data.count, data.link) then
			return
		end
		-- An item of the catch just recorded, or of a container caught this session: marked in the log.
		local fish = false
		if fishItems and GetTime() - fishItems.at <= F.FISH_COIN_SECONDS and (fishItems.items[data.itemID] or 0) > 0 then
			fishItems.items[data.itemID] = fishItems.items[data.itemID] - (data.count or 1)
			fish = true
		elseif data.opening and opening and opening.id == data.opening and opening.fishZone then
			F.AddFishItem(s, opening.fishZone, data.itemID, data.count)
			fish = true
		end
		F.LogDrop(s, now, "item", data.itemID, data.count or 1, fish)
	elseif kind == "money" then
		F.AddCoin(s, data.copper)
		local fish = false
		if fishCoin then
			if GetTime() - fishCoin.at <= F.FISH_COIN_SECONDS then
				F.AddFishCoin(s, fishCoin.zone, data.copper)
				fish = true
			end
			fishCoin = nil
		end
		F.LogDrop(s, now, "coin", data.copper, nil, fish)
	else
		return
	end
	s.lastLoot = now
	Changed()
end

-- Fishing.lua's catch record (#130). Caught containers opened come from the loot feed (OnOpened).
function F.OnFishing(kind, data)
	if kind ~= "catch" then
		return
	end
	local now = F.Now()
	fishCoin, fishItems, opening = nil, nil, nil
	local s = Accept(now)
	if not s then
		return
	end
	local items = data.catch and data.catch.items or {}
	F.AddCatch(s, items, now)
	local copy = {}
	for id, n in pairs(items) do
		copy[id] = n
	end
	fishItems = { items = copy, at = GetTime() }
	if data.coin then
		fishCoin = { zone = s.zone, at = GetTime() }
	end
	s.lastLoot = now
	Changed()
end

ns.LootFeed.Subscribe(F.OnFeed)
if ns.Fishing and ns.Fishing.Subscribe then
	ns.Fishing.Subscribe(F.OnFishing)
end

ns.On("ZONE_CHANGED_NEW_AREA", function()
	local s = F.Tick()
	if s and F.Running(s) then
		F.SetZone(s, ZoneNow(), F.Now())
		Changed()
	end
end)

-- Logout, /reload, quit: a running session stops counting and goes on at the next login.
ns.On("PLAYER_LOGOUT", function()
	local s = F.Current()
	if not s then
		return
	end
	local now = F.Now()
	F.Update(s, now)
	if F.Running(s) then
		F.Fold(s, now)
		s.resumedAt, s.resumeOnLogin = nil, true
	end
end)

ns.On("PLAYER_ENTERING_WORLD", function()
	local s = F.Current()
	if not s then
		return
	end
	if s.resumeOnLogin then
		F.Resume(s, F.Now(), ZoneNow())
	end
	local st = Settings()
	if st and st.shown ~= false and F.Enabled() and UI() then
		UI().Show()
	end
end)

----------------------------------------------------------------------------------------------------
-- Snapshot (#126): the current session and the latest finished ones
----------------------------------------------------------------------------------------------------

-- A summary as the snapshot carries it: rates left out (they are (coin + items) * 3600 / seconds), item
-- names moved into the section's `names`, no zone list for a session in one zone, so a long history
-- stays small.
local function Export(sum, names)
	local out = { start = sum.start, stop = sum.stop, seconds = sum.seconds, zone = sum.zone, coin = sum.coin,
		items = sum.items, vendor = sum.vendor, vendorUnknown = sum.vendorUnknown, ah = sum.ah, stale = sum.stale,
		unknown = sum.unknown, zonesMore = sum.zonesMore, zones = {}, top = {} }
	-- One zone: the session's own totals, so no list.
	if #(sum.zones or {}) > 1 or sum.zonesMore then
		for i, z in ipairs(sum.zones) do
			out.zones[i] = { zone = z.zone, seconds = z.seconds, coin = z.coin, items = z.items }
		end
	else
		out.zones = nil
	end
	for i, item in ipairs(sum.top or {}) do
		out.top[i] = { id = item.id, n = item.n, value = item.value, source = item.source }
		if item.id and item.name and not names[item.id] then
			names[item.id] = item.name
		end
	end
	if sum.log or sum.logLines then
		out.logLines, out.logDropped = sum.logLines or #sum.log, sum.logDropped
	end
	local f = sum.fish
	if f then
		out.fish = { catches = f.catches, timed = f.timed, seconds = f.seconds, coin = f.coin, items = f.items,
			unknown = f.unknown, opened = f.opened, zonesMore = f.zonesMore }
		if f.best then
			out.fish.best = { id = f.best.id, value = f.best.value }
			if f.best.id and f.best.name and not names[f.best.id] then
				names[f.best.id] = f.best.name
			end
		end
		-- One zone: the block's own totals are that zone's.
		if #(f.zones or {}) > 1 or f.zonesMore then
			out.fish.zones = {}
			for i, z in ipairs(f.zones) do
				out.fish.zones[i] = { zone = z.zone, catches = z.catches, timed = z.timed, seconds = z.seconds, coin = z.coin,
					items = z.items, unknown = z.unknown, opened = z.opened }
			end
		end
	end
	return out
end

-- { current (running, paused = "manual" | "idle"; no stop), sessions (finished, newest first,
--   SNAPSHOT_SESSIONS), names = { [itemID] = name } of their top items and best catches, saved (finished sessions kept),
--   more (kept but not in the snapshot), historyMax }
function F.SnapshotSummary(now)
	local log = F.Log()
	if not log then
		return nil, "character not known yet"
	end
	now = now or F.Now()
	local names = {}
	local out = { sessions = {}, names = names, saved = #log.history, historyMax = F.HISTORY_MAX }
	local s = log.current
	if s then
		F.Update(s, now)
		local cur = Export(F.Summary(s, now), names)
		cur.stop = nil
		-- The newest SNAPSHOT_LOG lines of the loot log, zone indexes renumbered into their own logZones.
		local log = s.log or {}
		if #log > 0 then
			cur.log, cur.logZones = {}, {}
			local renum = {}
			for i = math.max(1, #log - F.SNAPSHOT_LOG + 1), #log do
				local e = F.UnpackLog(log[i])
				local zone = (s.logZones or {})[e.zi] or F.UNKNOWN_ZONE
				if not renum[zone] then
					cur.logZones[#cur.logZones + 1] = zone
					renum[zone] = #cur.logZones
				end
				cur.log[#cur.log + 1] = (log[i]:gsub(",(%d+)(,?%a*)$", "," .. renum[zone] .. "%2"))
			end
		end
		cur.running = (F.Running(s) or s.resumeOnLogin) and true or false
		cur.paused = s.paused and "manual" or (s.autoPaused and "idle") or nil
		out.current = cur
	end
	for i = 1, math.min(F.SNAPSHOT_SESSIONS, #log.history) do
		out.sessions[i] = Export(log.history[i], names)
	end
	if #log.history > F.SNAPSHOT_SESSIONS then
		out.more = #log.history - F.SNAPSHOT_SESSIONS
	end
	return out
end

----------------------------------------------------------------------------------------------------
-- Text and slash command
----------------------------------------------------------------------------------------------------

function F.FormatTime(seconds)
	seconds = math.max(0, math.floor(seconds or 0))
	return ("%02d:%02d:%02d"):format(math.floor(seconds / 3600), math.floor(seconds % 3600 / 60), seconds % 60)
end

local function Money(copper)
	return copper and ns.FormatMoney(copper) or "-"
end

local function PrintHistory()
	local history = F.History()
	if #history == 0 then
		ns.Print("No finished farm sessions yet (/craftwise farm reset ends one).")
		return
	end
	ns.Print(("Farm sessions (%d kept, newest first):"):format(#history))
	for i = 1, math.min(10, #history) do
		local h = history[i]
		local top = h.top and h.top[1]
		ns.Print(("%s  %s  %s  coin %s + items %s  %s/h%s%s"):format(date("%m-%d %H:%M", h.start), F.FormatTime(h.seconds),
			h.zone or "?", Money(h.coin), Money(h.items), Money(h.gph),
			(h.unknown or 0) > 0 and ("  (" .. h.unknown .. " unpriced)") or "",
			top and ("  best: " .. (top.name or ("item " .. top.id))) or ""))
		local f = h.fish
		if f then
			ns.Print(("    fishing: %d catches, %s per catch%s, %s/h, %d containers opened%s"):format(f.catches, Money(f.perCatch),
				(f.unknown or 0) > 0 and (" (" .. f.unknown .. " unpriced)") or "", Money(f.gph), f.opened or 0,
				f.best and ("  best catch: " .. (f.best.name or ("item " .. f.best.id))) or ""))
		end
	end
end

local function Status()
	local st = Settings() or {}
	ns.Print(("Farm tracker %s, start on first loot %s, idle pause %s, window %s, %s, scale %g."):format(
		F.Enabled() and "on" or "off", F.AutoStart() and "on" or "off",
		F.IdleMinutes() > 0 and (F.IdleMinutes() .. " min") or "off", st.shown == false and "hidden" or "shown",
		st.locked and "locked" or "unlocked", tonumber(st.scale) or 1))
	ns.Print("/craftwise farm show | hide | start | pause | reset | lock | unlock | scale <0.5-2> | idle <minutes, 0 = off> | autostart on|off | on | off | history")
end

-- Key binding (Bindings.xml, #130); the header is Music.lua's BINDING_HEADER_CRAFTWISE.
_G.BINDING_NAME_CRAFTWISE_FARM = "Toggle CraftWise farm tracker"
function CraftWise_FarmToggle()
	F.Slash("toggle")
end

function F.Slash(arg)
	local st = Settings()
	if not st then
		return
	end
	arg = (arg or ""):lower():match("^%s*(.-)%s*$")
	local ui = UI()
	if arg == "" or arg == "toggle" then
		if ui and ui.IsShown() then
			arg = "hide"
		else
			arg = "show"
		end
	end
	if arg == "show" then
		st.shown = true
		if ui then
			ui.Show()
		end
	elseif arg == "hide" then
		st.shown = false
		if ui then
			ui.Hide()
		end
	elseif arg == "start" or arg == "resume" then
		local s = F.Tick()
		if s and F.Running(s) then
			ns.Print("The farm session is already running.")
		else
			F.Start()
		end
	elseif arg == "pause" then
		F.TogglePause()
	elseif arg == "reset" then
		local sum = F.Reset()
		ns.Print(sum and ("Farm session saved: %s, coin %s + items %s, %s/h."):format(F.FormatTime(sum.seconds),
			Money(sum.coin), Money(sum.items), Money(sum.gph)) or "Farm session cleared (nothing looted, not saved).")
	elseif arg == "lock" or arg == "unlock" then
		st.locked = arg == "lock"
		if ui then
			ui.ApplyLock()
		end
		ns.Print(arg == "lock" and "Farm window locked." or "Farm window unlocked: drag it by its title.")
	elseif arg == "on" or arg == "off" then
		st.enabled = arg == "on"
		if not st.enabled then
			local s = F.Current()
			if s and F.Running(s) then
				F.Pause(s, F.Now())
			end
			if ui then
				ui.Hide()
			end
		end
		Changed()
		ns.Print("Farm tracker " .. arg .. ".")
	elseif arg == "history" then
		PrintHistory()
	elseif arg:match("^scale") then
		local v = tonumber(arg:match("^scale%s+([%d%.]+)$"))
		if not v or v < F.MIN_SCALE or v > F.MAX_SCALE then
			ns.Print(("Usage: /craftwise farm scale <%g to %g>"):format(F.MIN_SCALE, F.MAX_SCALE))
			return
		end
		st.scale = v
		if ui then
			ui.ApplyScale()
		end
		ns.Print(("Farm window scale %g."):format(v))
	elseif arg:match("^idle") then
		local v = tonumber(arg:match("^idle%s+(%d+)$"))
		if not v or v > F.MAX_IDLE then
			ns.Print(("Usage: /craftwise farm idle <minutes, 0 to %d; 0 = never pause>"):format(F.MAX_IDLE))
			return
		end
		st.idleMinutes = v
		ns.Print(v > 0 and ("Farm sessions pause after %d minutes without loot."):format(v) or "Farm sessions never pause on their own.")
	elseif arg:match("^autostart") then
		local v = arg:match("^autostart%s+(%a+)$")
		if v ~= "on" and v ~= "off" then
			ns.Print("Usage: /craftwise farm autostart on | off")
			return
		end
		st.autoStart = v == "on"
		ns.Print(v == "on" and "A farm session starts with the first loot." or "Farm sessions start only with Start.")
	else
		Status()
	end
	Changed()
end
