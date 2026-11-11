-- Fishing loot tables from own catches (issue #86), built from the fishing log (Fishing.lua, #69).
--
--   * Rows per zone, subzone and water type: open water, each pool object (by its object ID, named as the
--     client showed it), or "?" while the water type isn't known yet (Fishing.lua, F.Kinds). Per row:
--     catches, units and share of each item (count of all items caught there), unit value (ns.GetSellValue:
--     AH after the cut, else vendor incl. the remembered sell prices of #83; containers by their logged
--     contents), value per catch and value per hour.
--   * Value per hour: catches less than N minutes apart are one session (N = settings.fishingSessionGap,
--     default 5, `/craftwise fishing gap <minutes>`). A catch's time is the time since the previous catch of
--     its session, counted for the row of that catch; a session's first catch has no time and is left out of
--     the per-hour figure (its row says how many catches were timed).
--   * Pool visits: catches from one pool spawn (same source GUID; without a spawn part: same object ID, within
--     1% of the map and the session gap) are one visit. A visit has ended once a later catch came from
--     elsewhere or the session gap passed; its catch count is how many catches the pool gave before it
--     vanished or the player left it (the client doesn't say which). Visits still going on are counted apart.
--   * Small samples are shown with their count ("n = 7"); shares are of what was caught, not drop rates.
local _, ns = ...

local F = ns.Fishing
if not F then
	return
end

F.SNAP_SPOTS = 8 -- ranked rows in the snapshot (it has a size budget, tests/snapshot_spec.lua)
F.SNAP_POOLS = 5
F.SNAP_TOP = 3 -- items per row in the snapshot

local function Lower(s)
	return s and s:lower() or ""
end

function F.SessionGap()
	local s = ns.db and ns.db.settings
	local gap = s and tonumber(s.fishingSessionGap)
	return gap and gap > 0 and gap or 5
end

local function Near(a, b)
	if not (a.x and a.y and b.x and b.y) then
		return a.x == b.x and a.y == b.y
	end
	return math.abs(a.x - b.x) <= 1 and math.abs(a.y - b.y) <= 1
end

-- The log's catches oldest first, each with dt = seconds since the previous catch of its session (nil for
-- a session's first catch).
local function Timed(log, gap)
	local list = {}
	for i, c in ipairs(log.catches or {}) do
		list[i] = c
	end
	table.sort(list, function(a, b) return (a.t or 0) < (b.t or 0) end)
	local out, prev = {}, nil
	for i, c in ipairs(list) do
		local dt = prev and c.t and prev.t and (c.t - prev.t) or nil
		if dt and (dt < 0 or dt > gap) then
			dt = nil
		end
		out[i] = { c = c, dt = dt }
		prev = c
	end
	return out
end

local function Matches(c, zoneFilter)
	return not zoneFilter or Lower(c.zone) == zoneFilter or Lower(c.sub) == zoneFilter
end

-- Pool visits of one character: { [objID] = { visits, catches, min, max, going, spawns = { [spawn] = true },
-- zones = { [zone] = true } } }, filtered like the tables.
local function Visits(timed, kinds, gap, now, zoneFilter)
	local visits, open = {}, {}
	local lastT = 0
	for _, e in ipairs(timed) do
		local c = e.c
		lastT = math.max(lastT, c.t or 0)
		if c.obj and F.WaterOf(c, kinds) == "pool" then
			local key = c.spawn and (c.obj .. ":" .. c.spawn) or tostring(c.obj)
			local v = open[key]
			if v and ((c.t or 0) - v.last > gap or (not c.spawn and not Near(v, c))) then
				v = nil
			end
			if not v then
				v = { obj = c.obj, spawn = c.spawn, n = 0, first = c.t or 0, last = c.t or 0, x = c.x, y = c.y,
					zone = c.zone, sub = c.sub }
				open[key] = v
				visits[#visits + 1] = v
			end
			v.n, v.last = v.n + 1, c.t or 0
		end
	end
	local byObj = {}
	for _, v in ipairs(visits) do
		if Matches(v, zoneFilter) then
			local p = byObj[v.obj]
			if not p then
				p = { obj = v.obj, visits = 0, catches = 0, going = 0, spawns = {}, zones = {} }
				byObj[v.obj] = p
			end
			if v.spawn then
				p.spawns[v.spawn] = true
			end
			if v.zone then
				p.zones[v.zone] = true
			end
			if v.last < lastT or now - v.last > gap then
				p.visits, p.catches = p.visits + 1, p.catches + v.n
				p.min = p.min and math.min(p.min, v.n) or v.n
				p.max = p.max and math.max(p.max, v.n) or v.n
			else
				p.going = p.going + 1
			end
		end
	end
	return byObj
end

-- Tables for this character. opts = { zone = zone or subzone name (any case), water = "pool"|"open", key }.
-- { days, gap (minutes), catches, opened, findFish, zones = { { zone, catches, value, unpriced, perCatch,
--   subs = { { sub, catches, value, unpriced, perCatch, rows } } } }, rows (all, flat), pools = { ... } }
-- row = { zone, sub, water = "open"|"pool"|"?", obj, name, catches, units, value, unpriced, perCatch,
--   timed, seconds, timedValue, perHour, items = { { itemID, count, share, unit = { copper, label } | nil } } }
function F.Tables(opts)
	opts = opts or {}
	local log = F.Log(opts.key)
	if not log then
		return nil
	end
	F.Prune()
	local kinds = F.Kinds()
	local gapMin = F.SessionGap()
	local gap = gapMin * 60
	local now = time()
	local zoneFilter = opts.zone and opts.zone ~= "" and Lower(opts.zone) or nil
	local waterFilter = opts.water

	local units = {}
	local function unit(itemID)
		if units[itemID] == nil then
			units[itemID] = F.UnitValue(log, itemID) or false
		end
		return units[itemID] or nil
	end

	local timed = Timed(log, gap)
	local rows, byKey, total = {}, {}, 0
	for _, e in ipairs(timed) do
		local c = e.c
		local water = F.WaterOf(c, kinds)
		if Matches(c, zoneFilter) and (not waterFilter or water == waterFilter) then
			local zone, sub = c.zone or "?", c.sub or ""
			local obj = water ~= "open" and c.obj or nil
			local key = table.concat({ zone, sub, water, tostring(obj) }, "\1")
			local r = byKey[key]
			if not r then
				r = { zone = zone, sub = sub, water = water, obj = obj, name = F.ObjectName(obj), catches = 0, units = 0,
					value = 0, unpriced = 0, timed = 0, seconds = 0, timedValue = 0, counts = {} }
				byKey[key] = r
				rows[#rows + 1] = r
			end
			local value = 0
			for itemID, count in pairs(c.items or {}) do
				r.counts[itemID] = (r.counts[itemID] or 0) + count
				r.units = r.units + count
				local u = unit(itemID)
				if u then
					value = value + u.copper * count
				else
					r.unpriced = r.unpriced + count
				end
			end
			r.catches, r.value, total = r.catches + 1, r.value + value, total + 1
			if e.dt then
				r.timed, r.seconds, r.timedValue = r.timed + 1, r.seconds + e.dt, r.timedValue + value
			end
		end
	end

	local zones, zoneIndex = {}, {}
	for _, r in ipairs(rows) do
		r.items = {}
		for itemID, count in pairs(r.counts) do
			r.items[#r.items + 1] = { itemID = itemID, count = count, share = count / r.units, unit = unit(itemID) }
		end
		table.sort(r.items, function(a, b)
			if a.count ~= b.count then
				return a.count > b.count
			end
			return a.itemID < b.itemID
		end)
		r.counts = nil
		r.perCatch = math.floor(r.value / r.catches)
		r.perHour = r.seconds > 0 and math.floor(r.timedValue * 3600 / r.seconds) or nil
		local z = zoneIndex[r.zone]
		if not z then
			z = { zone = r.zone, catches = 0, value = 0, unpriced = 0, subs = {}, subIndex = {} }
			zoneIndex[r.zone] = z
			zones[#zones + 1] = z
		end
		local s = z.subIndex[r.sub]
		if not s then
			s = { sub = r.sub, catches = 0, value = 0, unpriced = 0, rows = {} }
			z.subIndex[r.sub] = s
			z.subs[#z.subs + 1] = s
		end
		s.rows[#s.rows + 1] = r
		for _, t in ipairs({ z, s }) do
			t.catches, t.value, t.unpriced = t.catches + r.catches, t.value + r.value, t.unpriced + r.unpriced
		end
	end
	local function byCatches(a, b)
		if a.catches ~= b.catches then
			return a.catches > b.catches
		end
		return (a.zone or a.sub or a.water or "") < (b.zone or b.sub or b.water or "")
	end
	for _, z in ipairs(zones) do
		z.perCatch = math.floor(z.value / z.catches)
		z.subIndex = nil
		for _, s in ipairs(z.subs) do
			s.perCatch = math.floor(s.value / s.catches)
			table.sort(s.rows, byCatches)
		end
		table.sort(z.subs, byCatches)
	end
	table.sort(zones, byCatches)

	local pools = {}
	if waterFilter ~= "open" then
		local byObj = Visits(timed, kinds, gap, now, zoneFilter)
		for _, e in ipairs(log.seen or {}) do
			local p = e.obj and byObj[e.obj]
			if not p and e.obj and kinds.kind[e.obj] == "pool" and Matches(e, zoneFilter) then
				p = { obj = e.obj, visits = 0, catches = 0, going = 0, spawns = {}, zones = {} }
				byObj[e.obj] = p
			end
			if p and Matches(e, zoneFilter) then
				p.seen = (p.seen or 0) + 1
				if e.spawn and not p.spawns[e.spawn] then
					p.notFished = (p.notFished or 0) + 1
				end
			end
		end
		for _, p in pairs(byObj) do
			p.name = F.ObjectName(p.obj)
			p.avg = p.visits > 0 and math.floor(p.catches / p.visits * 10 + 0.5) / 10 or nil
			p.spawns, p.zones = nil, nil
			pools[#pools + 1] = p
		end
		table.sort(pools, function(a, b)
			if a.visits ~= b.visits then
				return a.visits > b.visits
			end
			return a.obj < b.obj
		end)
	end

	-- Find Fish as the client says now, else as last read.
	local ff = F.ReadFindFish() or log.findFish
	return { days = F.KEEP_DAYS, gap = gapMin, catches = total, opened = #(log.opened or {}), findFish = ff,
		zones = zones, rows = rows, pools = pools }
end

-- Rows best first: value per hour where any catch was timed, then value per catch.
function F.Ranked(rows)
	local list = {}
	for i, r in ipairs(rows) do
		list[i] = r
	end
	table.sort(list, function(a, b)
		if (a.perHour ~= nil) ~= (b.perHour ~= nil) then
			return a.perHour ~= nil
		end
		if a.perHour and a.perHour ~= b.perHour then
			return a.perHour > b.perHour
		end
		if a.perCatch ~= b.perCatch then
			return a.perCatch > b.perCatch
		end
		return a.catches > b.catches
	end)
	return list
end

----------------------------------------------------------------------------------------------------
-- Snapshot (#63): a compact ranking
----------------------------------------------------------------------------------------------------

local function ItemName(itemID)
	return ns.ItemInfoNow and (ns.ItemInfoNow(itemID)) or nil
end

-- "<itemID> <name> <count>/<units>; ..." for the first F.SNAP_TOP items.
local function TopText(r)
	local parts = {}
	for i = 1, math.min(#r.items, F.SNAP_TOP) do
		local item = r.items[i]
		local name = ItemName(item.itemID)
		parts[i] = ("%d %s%d/%d"):format(item.itemID, name and (name .. " ") or "", item.count, r.units)
	end
	return table.concat(parts, "; ")
end

function F.SnapshotSummary()
	local t = F.Tables()
	if not t then
		return nil, "fishing log not loaded"
	end
	local ff = t.findFish or {}
	local out = { days = t.days, catches = t.catches, containersOpened = t.opened, sessionGapMinutes = t.gap,
		findFish = { spellID = F.FIND_FISH, known = ff.known, tracking = ff.tracking },
		spots = {}, pools = {} }
	local ranked = F.Ranked(t.rows)
	for i = 1, math.min(#ranked, F.SNAP_SPOTS) do
		local r = ranked[i]
		out.spots[i] = { zone = r.zone, sub = r.sub, water = r.water, obj = r.obj, pool = r.name, n = r.catches,
			perCatch = r.perCatch, perHour = r.perHour, timed = r.timed > 0 and r.timed or nil,
			minutes = r.seconds > 0 and math.floor(r.seconds / 6 + 0.5) / 10 or nil,
			unpriced = r.unpriced > 0 and r.unpriced or nil, top = TopText(r) }
	end
	if #ranked > F.SNAP_SPOTS then
		out.moreSpots = #ranked - F.SNAP_SPOTS
	end
	for i = 1, math.min(#t.pools, F.SNAP_POOLS) do
		local p = t.pools[i]
		out.pools[i] = { obj = p.obj, name = p.name, visits = p.visits, perVisit = p.visits > 0
			and ("%d-%d, avg %s"):format(p.min, p.max, p.avg) or nil, going = p.going > 0 and p.going or nil,
			seen = p.seen, notFished = p.notFished }
	end
	if #t.pools > F.SNAP_POOLS then
		out.morePools = #t.pools - F.SNAP_POOLS
	end
	return out
end

----------------------------------------------------------------------------------------------------
-- /craftwise fishing [pools|open] [zone] | gap <minutes> | zones [zone] | ownmin <catches>
----------------------------------------------------------------------------------------------------

local function Money(copper)
	return ns.FormatMoney and ns.FormatMoney(copper) or (tostring(copper) .. "c")
end

local function PerCatchText(value, unpriced, perCatch)
	if value == 0 and unpriced > 0 then
		return F.NO_PRICE
	end
	local text = Money(perCatch)
	if unpriced > 0 then
		text = text .. (" (%d items without price left out)"):format(unpriced)
	end
	return text
end

function F.RowLabel(r)
	if r.water == "open" then
		return "open water"
	end
	if r.water == "pool" then
		return r.name and ("%s (pool)"):format(r.name) or ("pool object %d (name not seen)"):format(r.obj)
	end
	if r.obj then
		return ("water type not known yet (%s, object %d)"):format(r.name or "name not seen", r.obj)
	end
	return "water type not known (no loot source)"
end

local function FindFishText(ff)
	if not ff or ff.known == nil then
		return "Find Fish: not read yet"
	end
	if not ff.known then
		return "Find Fish: not known by this character"
	end
	if ff.tracking == nil then
		return "Find Fish: known, tracking state not read"
	end
	return "Find Fish: known, tracking " .. (ff.tracking and "on" or "off")
end

local function PoolLine(p)
	local name = p.name or ("pool object %d (name not seen)"):format(p.obj)
	local parts = {}
	if p.visits > 0 then
		parts[#parts + 1] = ("%d visits ended, %s catches per visit (n = %d, avg %s)"):format(p.visits,
			p.min == p.max and tostring(p.min) or (p.min .. "-" .. p.max), p.visits, p.avg)
	else
		parts[#parts + 1] = "no ended visit"
	end
	if p.going > 0 then
		parts[#parts + 1] = ("%d going on"):format(p.going)
	end
	if p.seen then
		parts[#parts + 1] = ("seen %d times"):format(p.seen) .. (p.notFished and (", %d not fished"):format(p.notFished) or "")
	end
	return ("  %s: %s"):format(name, table.concat(parts, "; "))
end

function F.Slash(arg)
	arg = arg or ""
	-- zones [name] / ownmin <n>: zone ranking with the local reference (FishingZones.lua, #88)
	local zonesArg = arg:match("^zones%s*(.-)$")
	if zonesArg and ns.FishingZones then
		return ns.FishingZones.Slash(zonesArg)
	end
	local ownMin = arg:match("^ownmin%s*(.-)$")
	if ownMin and ns.FishingZones then
		return ns.FishingZones.SetOwnMin(ownMin)
	end
	local gap = arg:match("^gap%s+(%d+)$")
	if gap then
		gap = tonumber(gap)
		if gap < 1 then
			ns.Print("The session gap is at least 1 minute.")
			return
		end
		if ns.db then
			ns.db.settings.fishingSessionGap = gap
		end
		ns.Print(("Fishing sessions: catches less than %d minutes apart."):format(gap))
		return
	end
	local water
	local first, rest = arg:match("^(%S+)%s*(.-)$")
	if first == "pools" or first == "pool" then
		water, arg = "pool", rest
	elseif first == "open" then
		water, arg = "open", rest
	end
	local t = F.Tables({ zone = arg, water = water })
	if not t then
		ns.Print("fishing log not loaded yet")
		return
	end
	local what = water == "pool" and "pool catches" or water == "open" and "open-water catches" or "catches"
	if t.catches == 0 then
		ns.Print(("No %s%s in the last %d days."):format(what, arg ~= "" and (" in " .. arg) or "", t.days))
		return
	end
	local ids, seenIDs = {}, {}
	for _, r in ipairs(t.rows) do
		for _, item in ipairs(r.items) do
			if not seenIDs[item.itemID] then
				seenIDs[item.itemID] = true
				ids[#ids + 1] = item.itemID
			end
		end
	end
	ns.WithItemNames(ids, function()
		ns.Print(("Fishing, last %d days: %d %s%s. Sessions: catches less than %d min apart. Value = best sell value (AH after cut, else vendor)."):format(
			t.days, t.catches, what, arg ~= "" and (" in " .. arg) or "", t.gap))
		ns.Print(FindFishText(t.findFish))
		for _, z in ipairs(t.zones) do
			ns.Print(("%s: n = %d catches, %s per catch"):format(z.zone, z.catches, PerCatchText(z.value, z.unpriced, z.perCatch)))
			for _, s in ipairs(z.subs) do
				ns.Print(("  %s: n = %d catches, %s per catch"):format(s.sub ~= "" and s.sub or "(no subzone)", s.catches,
					PerCatchText(s.value, s.unpriced, s.perCatch)))
				for _, r in ipairs(s.rows) do
					local hour = r.perHour and ("%s per hour (n = %d timed, %d min)"):format(Money(r.perHour), r.timed,
						math.floor(r.seconds / 60 + 0.5)) or "per hour: no timed catches"
					ns.Print(("    %s: n = %d catches, %s per catch, %s"):format(F.RowLabel(r), r.catches,
						PerCatchText(r.value, r.unpriced, r.perCatch), hour))
					for _, item in ipairs(r.items) do
						local value = item.unit and ("%s each (%s)"):format(Money(item.unit.copper), item.unit.label) or F.NO_PRICE
						ns.Print(("      %s x%d (%d of %d items, %d%%) - %s"):format(ns.ItemChatText(item.itemID), item.count,
							item.count, r.units, math.floor(item.share * 100 + 0.5), value))
					end
				end
			end
		end
		if #t.pools > 0 then
			ns.Print("Pools: a visit ends when you fish elsewhere or stop; its catches are what the pool gave until it vanished or you left.")
			for _, p in ipairs(t.pools) do
				ns.Print(PoolLine(p))
			end
		end
	end)
end
