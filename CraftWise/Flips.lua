-- Flip history (#330): what the AH -> vendor flips actually earned. A flip is units sold to a vendor that
-- have a logged AH purchase (Ledger.lua, L.FlipShare): cost = what those units cost at the AH, got = what the
-- vendor paid for them, profit = got - cost. Units without a logged AH cost (loot, units from before the log,
-- vendor purchases) are left out of the flip and counted in `skip` on the record. No estimates. Read only
-- towards the game: nothing is bought or sold here, it logs what the player did.
--
-- Storage: CraftWiseMarketDB.flips (no new SavedVariables)
--   rows  = { { t, c = charKey, i = itemID, q = units, cost, got, skip, w = merchant, n = name, l = link }, ... }
--           one row per flip, oldest first, kept ROW_DAYS days.
--   days  = { ["YYYY-MM-DD"] = { [itemID] = { f = flips, q, cost, got, n, l } } }  rows older than ROW_DAYS
--           folded per item and day, kept DAY_DAYS days.
--   older = { [itemID] = { f, q, cost, got, n, l } }  days older than DAY_DAYS folded per item, forever.
-- Size: a row is about 100 bytes, so 100 flips a day for 90 days is under 1 MB; a day entry is one item per
-- day (a few dozen bytes each); `older` has at most one entry per item.
local _, ns = ...

local F = {}
ns.Flips = F

local ROW_DAYS = 90
local DAY_DAYS = 365
local DAY_SECONDS = 86400

F.WINDOWS = { "today", "d7", "d30", "all" }

local store

local function Round(x)
	return math.floor(x + 0.5)
end

-- Adds a flip's figures to a bucket { f, q, cost, got, n, l }.
local function Add(bucket, flips, units, cost, got, name, link)
	bucket.f, bucket.q = (bucket.f or 0) + flips, (bucket.q or 0) + units
	bucket.cost, bucket.got = (bucket.cost or 0) + cost, (bucket.got or 0) + got
	bucket.n, bucket.l = name or bucket.n, link or bucket.l
end

function F.Rows()
	return store and store.rows or {}
end

-- Records one realised flip: `sold` units went to the vendor for `copper` in total; `units` of them had an
-- AH cost of `cost` in total.
function F.Record(itemID, sold, copper, merchant, units, cost, charKey)
	if not (store and itemID and sold and sold > 0 and copper and units and units > 0 and cost) then
		return nil
	end
	units = math.min(units, sold)
	local name, link = ns.ItemInfoNow(itemID)
	local row = { t = time(), c = charKey or ns.CharKey(), i = itemID, q = units, cost = cost,
		got = Round(copper * units / sold), skip = sold - units, w = merchant, n = name, l = link }
	store.rows[#store.rows + 1] = row
	ns.Notify("FLIPS_CHANGED", row)
	return row
end

-- A buyback of `quantity` units takes back the newest flips of this item (this character): whole rows go,
-- a row covering more than what is left shrinks in proportion. Returns the AH units and their cost that
-- came back (the ledger puts them into the position again), nil when no flip was touched.
function F.Undo(itemID, quantity, charKey)
	if not (store and quantity and quantity > 0) then
		return nil
	end
	charKey = charKey or ns.CharKey()
	local left, units, cost = quantity, 0, 0
	for i = #store.rows, 1, -1 do
		local r = store.rows[i]
		if left <= 0 then
			break
		end
		if r.i == itemID and r.c == charKey then
			local covers = r.q + (r.skip or 0)
			if left >= covers then
				units, cost = units + r.q, cost + r.cost
				left = left - covers
				table.remove(store.rows, i)
			else
				local f = left / covers
				local q, c, g = Round(r.q * f), Round(r.cost * f), Round(r.got * f)
				units, cost = units + q, cost + c
				r.q, r.cost, r.got = r.q - q, r.cost - c, r.got - g
				r.skip = math.max((r.skip or 0) - (left - q), 0)
				left = 0
				if r.q <= 0 then
					table.remove(store.rows, i)
				end
			end
		end
	end
	if units <= 0 then
		return nil
	end
	ns.Notify("FLIPS_CHANGED")
	return units, cost
end

-- #343: re-prices the flip rows of an item (this character, from `since`) at `perUnit` AH cost per unit; the
-- rows were priced from phantom units. Returns how many rows changed.
function F.Reprice(itemID, charKey, since, perUnit)
	local n = 0
	for _, r in ipairs(F.Rows()) do
		if r.i == itemID and r.c == charKey and r.t >= since then
			r.cost = Round(perUnit * r.q)
			n = n + 1
		end
	end
	if n > 0 then
		ns.Notify("FLIPS_CHANGED")
	end
	return n
end

local function DayKey(t)
	return date("%Y-%m-%d", t)
end

local function DayStart(day)
	local y, m, d = day:match("^(%d+)-(%d+)-(%d+)$")
	return time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 0 })
end

-- Folds old rows into days and old days into `older`.
function F.Prune(now)
	if not store then
		return
	end
	now = now or time()
	local rowCutoff, dayCutoff = now - ROW_DAYS * DAY_SECONDS, DayKey(now - DAY_DAYS * DAY_SECONDS)
	local kept = {}
	for _, r in ipairs(store.rows) do
		if r.t >= rowCutoff then
			kept[#kept + 1] = r
		else
			local key = DayKey(r.t)
			local day = store.days[key] or {}
			store.days[key] = day
			day[r.i] = day[r.i] or {}
			Add(day[r.i], 1, r.q, r.cost, r.got, r.n, r.l)
		end
	end
	store.rows = kept
	for key, day in pairs(store.days) do
		if key < dayCutoff then
			for itemID, b in pairs(day) do
				store.older[itemID] = store.older[itemID] or {}
				Add(store.older[itemID], b.f, b.q, b.cost, b.got, b.n, b.l)
			end
			store.days[key] = nil
		end
	end
end

local function WindowStart(window, now)
	if window == "today" then
		return DayStart(DayKey(now))
	elseif window == "d7" then
		return now - 7 * DAY_SECONDS
	elseif window == "d30" then
		return now - 30 * DAY_SECONDS
	end
	return nil
end

F.Since = WindowStart

-- One window: { profit, flips, units, spent, got, avg, best = { { itemID, name, link, profit, flips } } }.
-- spent = what the flipped units cost at the AH, got = what the vendor paid. "all" also counts the folded days.
function F.Stats(window, now)
	now = now or time()
	local since = WindowStart(window, now)
	local total = { f = 0, q = 0, cost = 0, got = 0 }
	local items = {}
	local function item(itemID)
		items[itemID] = items[itemID] or {}
		return items[itemID]
	end
	for _, r in ipairs(F.Rows()) do
		if not since or r.t >= since then
			Add(total, 1, r.q, r.cost, r.got)
			Add(item(r.i), 1, r.q, r.cost, r.got, r.n, r.l)
		end
	end
	if not since and store then
		for _, day in pairs(store.days) do
			for itemID, b in pairs(day) do
				Add(total, b.f, b.q, b.cost, b.got)
				Add(item(itemID), b.f, b.q, b.cost, b.got, b.n, b.l)
			end
		end
		for itemID, b in pairs(store.older) do
			Add(total, b.f, b.q, b.cost, b.got)
			Add(item(itemID), b.f, b.q, b.cost, b.got, b.n, b.l)
		end
	end
	local best = {}
	for itemID, b in pairs(items) do
		best[#best + 1] = { itemID = itemID, name = b.n, link = b.l, profit = b.got - b.cost, flips = b.f }
	end
	table.sort(best, function(a, b)
		if a.profit ~= b.profit then
			return a.profit > b.profit
		end
		return a.itemID < b.itemID
	end)
	return { window = window, profit = total.got - total.cost, flips = total.f, units = total.q, spent = total.cost,
		got = total.got, avg = total.f > 0 and Round((total.got - total.cost) / total.f) or nil, best = best }
end

-- The history list, newest first: per-flip rows, then the folded days (one per item and day).
function F.History(limit)
	local out = {}
	local rows = F.Rows()
	for i = #rows, 1, -1 do
		local r = rows[i]
		out[#out + 1] = { t = r.t, itemID = r.i, name = r.n, link = r.l, units = r.q, cost = r.cost, got = r.got,
			profit = r.got - r.cost, skip = r.skip or 0, merchant = r.w, charKey = r.c, flips = 1 }
	end
	local days = {}
	for key in pairs(store and store.days or {}) do
		days[#days + 1] = key
	end
	table.sort(days, function(a, b) return a > b end)
	for _, key in ipairs(days) do
		for itemID, b in pairs(store.days[key]) do
			out[#out + 1] = { t = DayStart(key), day = key, itemID = itemID, name = b.n, link = b.l, units = b.q,
				cost = b.cost, got = b.got, profit = b.got - b.cost, skip = 0, flips = b.f }
		end
	end
	while limit and #out > limit do
		table.remove(out)
	end
	return out
end

ns.Listen("DB_READY", function()
	CraftWiseMarketDB = CraftWiseMarketDB or {}
	local db = CraftWiseMarketDB
	db.flips = db.flips or {}
	store = db.flips
	store.rows, store.days, store.older = store.rows or {}, store.days or {}, store.older or {}
end)

ns.On("PLAYER_ENTERING_WORLD", function()
	F.Prune()
end)
