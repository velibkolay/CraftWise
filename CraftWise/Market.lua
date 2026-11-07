-- Price history per auction house (issue #26, phase 1): recorder, storage, house detection, pruning.
-- Only prices this account saw in game. Phase 2 reads it for profit (Prices.lua) and the tooltips.
--
-- Why CraftWise records by itself: Auctionator keeps one bucket per realm, so a Booty Bay scan
-- overwrites the prices of the faction house (evidence on #26).
--
-- CraftWiseMarketDB (account-wide, its own SavedVariables so market size never touches CraftWiseDB):
--   v, houses[houseKey], scans[houseKey] (last 30), cutSamples, prunedAt, scope = { items, skillLines }
--   items[itemKey][houseKey] = entry, where itemKey is the itemID or "itemID:suffixID"
--   entry = {
--     last = { t, min, qty, listings },                 latest observation (browse has no listings)
--     raw  = { { t, total, listings, tiers, m }, ... }, 48 h; tiers = { p1, q1, ... } first 8 prices
--     days = { [dayNumber] = { lo, typ, hi, qtyMax, listMax, n, gone } },  30 days
--   }
-- raw.m: median unit price of the point's cheapest 15%, from all rows. Only on points whose stored
-- tiers don't hold all their units, because that median can lie beyond the 8th tier (Veli, #26).
--
-- On disk an entry is one compact string (see Encode): as plain tables the expected load is about
-- 30 MB, as strings under 5 MB (measured on #26, tested in market_spec). Entries become tables when
-- first used and strings again on prune and logout, so a saved file can hold both.
--
-- Never stored: seller names, bids, per-auction rows beyond the tiers.
local _, ns = ...

local M = {}
ns.Market = M

local MAX_TIERS = 8
local RAW_SECONDS = 48 * 3600
local DAY_SECONDS = 86400
local KEEP_DAYS = 30
local TYPICAL_DAYS = 7
local MIN_HISTORY_DAYS = 3
local CHEAPEST_SHARE = 0.15
local DEDUPE_SECONDS = 60 -- the same result set fires several events; identical data later is a new point
local SCANS_KEPT = 30
local ROWS_PER_FRAME = 500 -- Auctionator's full scan reads 250 rows with a link lookup per step
-- Decoding, updating and packing an entry costs 0.2 ms (expected) to 0.5 ms (full) on Lua 5.1.
local COMMIT_PER_FRAME = 40
local PRUNE_PER_FRAME = 20
local PRUNE_ALL_SECONDS = 3600 -- packed entries are revisited this often; entries in use on every prune
local SEARCH_SETTLE_SECONDS = 0.3
local LINK_RETRIES = 10
local LINK_RETRY_SECONDS = 0.5

M.TOO_LITTLE_HISTORY = "too little history"
M.NO_DATA = "no price data"

-- Neutral goblin houses by zone or subzone text. Auctioneers only stand in these towns, so the parent
-- zone is enough when the subzone is a building name. Text is English, so other client languages
-- record nothing rather than file a neutral house under the faction house. Map IDs would avoid that
-- but can't be verified outside the game; see docs/ingame-checks.md.
local NEUTRAL_ZONES = {
	["Booty Bay"] = "BootyBay",
	["Stranglethorn Vale"] = "BootyBay",
	["The Cape of Stranglethorn"] = "BootyBay",
	["Gadgetzan"] = "Gadgetzan",
	["Tanaris"] = "Gadgetzan",
	["Everlook"] = "Everlook",
	["Winterspring"] = "Everlook",
}
local NEUTRAL_LABELS = { BootyBay = "Booty Bay", Gadgetzan = "Gadgetzan", Everlook = "Everlook" }

-- Veli's alt's professions, on another account, so no character cache here (decision 4 on #26).
local EXTRA_SCOPE_PROFESSIONS = { "Engineering", "Mining" }

local db -- CraftWiseMarketDB, set on DB_READY

local function DayNumber(t)
	return math.floor(t / DAY_SECONDS)
end

----------------------------------------------------------------------------------------------------
-- Maths (pure)
----------------------------------------------------------------------------------------------------

-- Quantity-weighted median of the cheapest 15% of `total` units: the price of the unit at 7.5%.
-- tiers = { p1, q1, ... } ascending. nil when the tiers don't reach that far.
function M.CheapestMedian(tiers, total)
	local target = (total or 0) * CHEAPEST_SHARE / 2
	if target <= 0 then
		return nil
	end
	local seen = 0
	for i = 1, #tiers, 2 do
		seen = seen + tiers[i + 1]
		if seen >= target then
			return tiers[i]
		end
	end
	return nil
end

local function StoredUnits(tiers)
	local units = 0
	for i = 2, #tiers, 2 do
		units = units + tiers[i]
	end
	return units
end

-- rows: [unit price] = quantity. Builds what a raw point stores.
function M.BuildObservation(prices, listings, reportedTotal)
	local sorted = {}
	for price in pairs(prices) do
		sorted[#sorted + 1] = price
	end
	table.sort(sorted)
	local all, seen = {}, 0
	for _, price in ipairs(sorted) do
		all[#all + 1] = price
		all[#all + 1] = prices[price]
		seen = seen + prices[price]
	end
	local total = math.max(reportedTotal or 0, seen)
	local tiers = {}
	for i = 1, math.min(#all, MAX_TIERS * 2) do
		tiers[i] = all[i]
	end
	local m
	if StoredUnits(tiers) < total then
		m = M.CheapestMedian(all, total)
	end
	return { tiers = tiers, total = total, listings = listings, m = m }
end

local function WeightedMedian(values)
	table.sort(values, function(a, b)
		return a.value < b.value
	end)
	local weight, seen = 0, 0
	for _, v in ipairs(values) do
		weight = weight + v.weight
	end
	for _, v in ipairs(values) do
		seen = seen + v.weight
		if seen >= weight / 2 then
			return v.value
		end
	end
end

-- typ of one day: quantity-weighted median of the cheapest 15% of the units in its observations.
-- From the pooled tiers when they reach far enough; a point cut off at 8 tiers can hide cheaper units
-- only above its last stored price. Otherwise from each point's own median (m), weighted by its units.
function M.DayTypical(points)
	local pooled, total, ceiling = {}, 0, nil
	for _, p in ipairs(points) do
		total = total + p.total
		for i = 1, #p.tiers, 2 do
			pooled[#pooled + 1] = { price = p.tiers[i], qty = p.tiers[i + 1] }
		end
		if StoredUnits(p.tiers) < p.total then
			local top = p.tiers[#p.tiers - 1]
			if top and (not ceiling or top < ceiling) then
				ceiling = top
			end
		end
	end
	if total <= 0 then
		return nil
	end
	table.sort(pooled, function(a, b)
		return a.price < b.price
	end)
	local target, seen = total * CHEAPEST_SHARE / 2, 0
	for _, tier in ipairs(pooled) do
		seen = seen + tier.qty
		if seen >= target then
			if not ceiling or tier.price <= ceiling then
				return tier.price
			end
			break
		end
	end
	local values = {}
	for _, p in ipairs(points) do
		local value = p.m or M.CheapestMedian(p.tiers, p.total)
		if value and p.total > 0 then
			values[#values + 1] = { value = value, weight = p.total }
		end
	end
	return WeightedMedian(values)
end

-- Median of the `typ` values in the last 7 days, rounded down, and how many days there were.
local function MedianOfDays(days, today)
	local list = {}
	for day = today - TYPICAL_DAYS + 1, today do
		local d = days[day]
		if d and d.typ then
			list[#list + 1] = d.typ
		end
	end
	local n = #list
	if n == 0 then
		return nil, 0
	end
	table.sort(list)
	if n % 2 == 1 then
		return list[(n + 1) / 2], n
	end
	return math.floor((list[n / 2] + list[n / 2 + 1]) / 2), n
end

-- Units listed in `prev` at prices up to `limit` that are missing from `cur`. They sold or expired, so
-- the UI calls them "disappeared", never sales. Prices beyond cur's stored tiers are unknown, not gone.
function M.GoneUnits(prev, cur, limit)
	if not limit then
		return 0
	end
	local cover = math.huge
	if StoredUnits(cur.tiers) < cur.total then
		cover = cur.tiers[#cur.tiers - 1] or 0
	end
	local now = {}
	for i = 1, #cur.tiers, 2 do
		now[cur.tiers[i]] = cur.tiers[i + 1]
	end
	local gone = 0
	for i = 1, #prev.tiers, 2 do
		local price, qty = prev.tiers[i], prev.tiers[i + 1]
		if price <= limit and price <= cover then
			gone = gone + math.max(0, qty - (now[price] or 0))
		end
	end
	return gone
end

local function SameMarket(a, b)
	if a.total ~= b.total or #a.tiers ~= #b.tiers then
		return false
	end
	for i = 1, #a.tiers do
		if a.tiers[i] ~= b.tiers[i] then
			return false
		end
	end
	return true
end

-- Adds one observation to an entry. false when it repeats the point just stored.
function M.ApplyObservation(entry, obs, now)
	local prev = entry.raw[#entry.raw]
	if prev and now - prev.t < DEDUPE_SECONDS and SameMarket(prev, obs) then
		return false
	end
	if prev then
		local limit = MedianOfDays(entry.days, DayNumber(now))
			or prev.m
			or M.CheapestMedian(prev.tiers, prev.total)
		local gone = M.GoneUnits(prev, obs, limit)
		if gone > 0 then
			local day = DayNumber(now)
			entry.days[day] = entry.days[day] or {}
			entry.days[day].gone = (entry.days[day].gone or 0) + gone
		end
	end
	entry.raw[#entry.raw + 1] = { t = now, total = obs.total, listings = obs.listings, tiers = obs.tiers, m = obs.m }
	if obs.tiers[1] then
		entry.last = { t = now, min = obs.tiers[1], qty = obs.total, listings = obs.listings }
	end
	return true
end

-- Raw points into daily aggregates, then retention. Returns false when nothing is left to keep.
-- A day whose oldest points were already dropped keeps the aggregate it got before that (n tells).
function M.AggregateEntry(entry, now)
	local byDay = {}
	for _, point in ipairs(entry.raw) do
		local day = DayNumber(point.t)
		byDay[day] = byDay[day] or {}
		table.insert(byDay[day], point)
	end
	for day, points in pairs(byDay) do
		local d = entry.days[day] or {}
		if (d.n or 0) <= #points then
			local lo, hi, qtyMax, listMax
			for _, p in ipairs(points) do
				for i = 1, #p.tiers, 2 do
					local price = p.tiers[i]
					lo = (not lo or price < lo) and price or lo
					hi = (not hi or price > hi) and price or hi
				end
				qtyMax = math.max(qtyMax or 0, p.total)
				listMax = math.max(listMax or 0, p.listings or 0)
			end
			d.lo, d.hi, d.qtyMax, d.listMax, d.n = lo, hi, qtyMax, listMax, #points
			d.typ = M.DayTypical(points)
			entry.days[day] = d
		end
	end

	local kept, cutoff = {}, now - RAW_SECONDS
	for _, point in ipairs(entry.raw) do
		if point.t >= cutoff then
			kept[#kept + 1] = point
		end
	end
	entry.raw = kept

	local oldest = DayNumber(now) - KEEP_DAYS
	for day in pairs(entry.days) do
		if day < oldest then
			entry.days[day] = nil
		end
	end
	local recent = entry.last and now - entry.last.t <= KEEP_DAYS * DAY_SECONDS
	return recent or #entry.raw > 0 or next(entry.days) ~= nil
end

----------------------------------------------------------------------------------------------------
-- Compact storage (pure): "last|raw|days", numbers in base 36, deltas where neighbours are close.
--   last = t,min,qty,listings
--   raw  = points joined by ";", point = dt,total,listings,m,dp1,q1,dp2,q2...
--   days = days joined by ";", day = dDay,lo,dTyp,dHi,qtyMax,listMax,n,gone
-- Empty field = nil. Deltas are zigzag coded, so a clock step back can't produce a negative number.
----------------------------------------------------------------------------------------------------

local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"

local function Base36(n)
	if not n then
		return ""
	end
	n = math.floor(n)
	if n <= 0 then
		return "0"
	end
	local out = ""
	while n > 0 do
		local r = n % 36
		out = DIGITS:sub(r + 1, r + 1) .. out
		n = (n - r) / 36
	end
	return out
end

local function Zig(n)
	return n >= 0 and n * 2 or -n * 2 - 1
end

local function Unzig(z)
	return z % 2 == 0 and z / 2 or -(z + 1) / 2
end

local function Num(s)
	if not s or s == "" then
		return nil
	end
	return tonumber(s, 36)
end

local function Split(s, sep)
	local out, pos = {}, 1
	while true do
		local at = s:find(sep, pos, true)
		if not at then
			out[#out + 1] = s:sub(pos)
			return out
		end
		out[#out + 1] = s:sub(pos, at - 1)
		pos = at + 1
	end
end

function M.EncodeEntry(entry)
	local last = ""
	if entry.last then
		local l = entry.last
		last = Base36(l.t) .. "," .. Base36(l.min) .. "," .. Base36(l.qty) .. "," .. Base36(l.listings)
	end

	local points, prevT = {}, 0
	for _, p in ipairs(entry.raw or {}) do
		local f = { Base36(Zig(p.t - prevT)), Base36(p.total), Base36(p.listings), Base36(p.m) }
		prevT = p.t
		local prevPrice = 0
		for i = 1, #p.tiers, 2 do
			f[#f + 1] = Base36(Zig(p.tiers[i] - prevPrice))
			f[#f + 1] = Base36(p.tiers[i + 1])
			prevPrice = p.tiers[i]
		end
		points[#points + 1] = table.concat(f, ",")
	end

	local dayNumbers = {}
	for day in pairs(entry.days or {}) do
		dayNumbers[#dayNumbers + 1] = day
	end
	table.sort(dayNumbers)
	local days, prevDay = {}, 0
	for _, day in ipairs(dayNumbers) do
		local d = entry.days[day]
		local lo = d.lo or 0
		days[#days + 1] = table.concat({
			Base36(Zig(day - prevDay)),
			Base36(d.lo),
			d.typ and Base36(Zig(d.typ - lo)) or "",
			d.hi and Base36(Zig(d.hi - lo)) or "",
			Base36(d.qtyMax),
			Base36(d.listMax),
			Base36(d.n),
			(d.gone or 0) > 0 and Base36(d.gone) or "",
		}, ",")
		prevDay = day
	end
	return last .. "|" .. table.concat(points, ";") .. "|" .. table.concat(days, ";")
end

function M.DecodeEntry(s)
	local parts = Split(s, "|")
	local entry = { raw = {}, days = {} }
	if parts[1] ~= "" then
		local f = Split(parts[1], ",")
		entry.last = { t = Num(f[1]), min = Num(f[2]), qty = Num(f[3]), listings = Num(f[4]) }
	end
	if parts[2] ~= "" then
		local prevT = 0
		for _, text in ipairs(Split(parts[2], ";")) do
			local f = Split(text, ",")
			prevT = prevT + Unzig(Num(f[1]))
			local tiers, prevPrice = {}, 0
			for i = 5, #f, 2 do
				prevPrice = prevPrice + Unzig(Num(f[i]))
				tiers[#tiers + 1] = prevPrice
				tiers[#tiers + 1] = Num(f[i + 1])
			end
			entry.raw[#entry.raw + 1] = { t = prevT, total = Num(f[2]), listings = Num(f[3]), m = Num(f[4]), tiers = tiers }
		end
	end
	if parts[3] ~= "" then
		local prevDay = 0
		for _, text in ipairs(Split(parts[3], ";")) do
			local f = Split(text, ",")
			prevDay = prevDay + Unzig(Num(f[1]))
			local lo = Num(f[2])
			local typ, hi = Num(f[3]), Num(f[4])
			entry.days[prevDay] = {
				lo = lo,
				typ = typ and ((lo or 0) + Unzig(typ)) or nil,
				hi = hi and ((lo or 0) + Unzig(hi)) or nil,
				qtyMax = Num(f[5]),
				listMax = Num(f[6]),
				n = Num(f[7]),
				gone = Num(f[8]),
			}
		end
	end
	return entry
end

local function GetEntry(itemKey, houseKey, create)
	local perItem = db.items[itemKey]
	if not perItem then
		if not create then
			return nil
		end
		perItem = {}
		db.items[itemKey] = perItem
	end
	local entry = perItem[houseKey]
	if type(entry) == "string" then
		entry = M.DecodeEntry(entry)
		perItem[houseKey] = entry
	elseif not entry and create then
		entry = { raw = {}, days = {} }
		perItem[houseKey] = entry
	end
	return entry
end

----------------------------------------------------------------------------------------------------
-- Keys, house detection
----------------------------------------------------------------------------------------------------

function M.ItemKey(itemID, suffix)
	if suffix and suffix ~= 0 then
		return itemID .. ":" .. suffix
	end
	return itemID
end

local function ItemIDOfKey(itemKey)
	return tonumber(tostring(itemKey):match("^%d+"))
end

-- The field after the four gem slots in item:id:enchant:gem1:gem2:gem3:gem4:suffix.
local function SuffixFromLink(link)
	local suffix = link and link:match("item:%d+:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:([^:|]*)")
	return tonumber(suffix)
end

-- House the player is standing at: key and its record, or nil when it can't be told.
function M.DetectHouse()
	local faction = UnitFactionGroup("player")
	local realm = GetRealmName()
	local locale = GetLocale()
	if not (realm and realm ~= "") or (faction ~= "Horde" and faction ~= "Alliance") then
		return nil
	end
	if locale ~= "enUS" and locale ~= "enGB" then
		return nil
	end
	local zone, subzone = GetRealZoneText(), GetSubZoneText()
	if (not zone or zone == "") and (not subzone or subzone == "") then
		return nil
	end
	local neutral = NEUTRAL_ZONES[subzone] or NEUTRAL_ZONES[zone]
	if neutral then
		return realm .. "|N:" .. neutral, { realm = realm, kind = "neutral", label = NEUTRAL_LABELS[neutral], cut = { samples = 0 } }
	end
	return realm .. "|" .. faction:sub(1, 1), { realm = realm, kind = "faction", faction = faction, label = faction .. " AH" }
end

----------------------------------------------------------------------------------------------------
-- Scope (decision 4): reagents and products of known and learnable recipes of the player's
-- professions, plus every item the player interacted with. Nothing outside it is stored. It only
-- grows. Buying and selling at a merchant and posting on the AH all pass through the bags.
----------------------------------------------------------------------------------------------------

local function AddToScope(itemID)
	if db and itemID then
		db.scope.items[itemID] = true
	end
end

function M.InScope(itemID)
	return db ~= nil and db.scope.items[itemID] == true
end

local function AddRecipeItems(reagents, output)
	for _, reagent in ipairs(reagents or {}) do
		AddToScope(reagent.itemID)
	end
	if output then
		AddToScope(output.itemID)
	end
end

function M.RefreshScope()
	if not db then
		return
	end
	local lines = db.scope.skillLines
	for professionID, prof in pairs(ns.charDB and ns.charDB.professions or {}) do
		lines[ns.SkillLineOf(professionID)] = true
		for _, recipe in pairs(prof.recipes or {}) do
			AddRecipeItems(recipe.reagents, recipe.output)
		end
	end
	for _, name in ipairs(EXTRA_SCOPE_PROFESSIONS) do
		local line = ns.ProfessionSkillLines and ns.ProfessionSkillLines[name]
		if line then
			lines[line] = true
		end
	end
	for _, data in pairs(ns.RecipeData or {}) do
		if lines[data.skillLine] then
			AddRecipeItems(data.reagents, data.output)
		end
	end
end

local function ScanContainer(bag)
	for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
		local info = C_Container.GetContainerItemInfo(bag, slot)
		if info then
			AddToScope(info.itemID)
		end
	end
end

local function ScanBags()
	if not db then
		return
	end
	for bag = 0, ns.LAST_BAG do
		ScanContainer(bag)
	end
end

-- Container IDs come from the client: bank layouts differ between clients.
local function ScanBank()
	if not (db and Enum and Enum.BagIndex) then
		return
	end
	for _, bag in pairs(Enum.BagIndex) do
		ScanContainer(bag)
	end
end

-- Text and guid may be secret values on 12.x clients (not NeverSecret in the docs), and comparing a
-- secret raises an error. The pcall makes that a skipped line; the item still reaches the bags.
local function OnLoot(_, text, _, _, _, _, _, _, _, _, _, _, guid)
	pcall(function()
		if guid == UnitGUID("player") then
			AddToScope(tonumber(text:match("item:(%d+)")))
		end
	end)
end

----------------------------------------------------------------------------------------------------
-- Recording
----------------------------------------------------------------------------------------------------

local currentHouse -- key while the AH is open, nil when closed or unknown
local job -- running full scan
local lastScan -- { count, t } of the last list read to the end
local pending = {} -- search results waiting to settle
local settleTimer

local function LogScan(houseKey, kind, items, source)
	local list = db.scans[houseKey] or {}
	db.scans[houseKey] = list
	list[#list + 1] = { t = time(), kind = kind, items = items, source = source }
	while #list > SCANS_KEPT do
		table.remove(list, 1)
	end
end

-- Runs step(i) for i = 1..count, perFrame calls per frame.
local function Chunked(count, perFrame, step, done, isCancelled)
	local index = 1
	local function run()
		if isCancelled and isCancelled() then
			return
		end
		for i = index, math.min(index + perFrame - 1, count) do
			step(i)
		end
		index = index + perFrame
		if index > count then
			done()
		else
			C_Timer.After(0, run)
		end
	end
	run()
end

local function AddRow(prices, price, quantity)
	prices[price] = (prices[price] or 0) + quantity
end

-- Rows the client handed over in a non-price order can't be trusted while the list is incomplete:
-- its cheapest rows may not be among them.
local function ReadRows(count, getRow)
	local prices, listings, previous, ascending = {}, 0, nil, true
	for index = 1, count do
		local price, quantity = getRow(index)
		if price and price > 0 and quantity and quantity > 0 then
			AddRow(prices, price, quantity)
			listings = listings + 1
			if previous and price < previous then
				ascending = false
			end
			previous = price
		end
	end
	return prices, listings, ascending
end

local function RecordSearch(itemKey, prices, listings, ascending, reportedTotal, hasFull)
	if listings == 0 or (not hasFull and not ascending) then
		return -- an empty search proves nothing: the client sometimes returns none when there are some
	end
	local obs = M.BuildObservation(prices, listings, reportedTotal)
	if M.ApplyObservation(GetEntry(itemKey, currentHouse, true), obs, time()) then
		LogScan(currentHouse, "search", 1, "ui")
	end
end

local function ReadCommoditySearch(itemID)
	local prices, listings, ascending = ReadRows(C_AuctionHouse.GetNumCommoditySearchResults(itemID), function(index)
		local row = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, index)
		if row then
			return row.unitPrice, row.quantity
		end
	end)
	RecordSearch(M.ItemKey(itemID), prices, listings, ascending,
		C_AuctionHouse.GetCommoditySearchResultsQuantity(itemID), C_AuctionHouse.HasFullCommoditySearchResults(itemID))
end

-- buyoutAmount is treated as the unit price, as Auctionator does for stacks; see docs/ingame-checks.md.
local function ReadItemSearch(itemKeyInfo)
	local prices, listings, ascending = ReadRows(C_AuctionHouse.GetNumItemSearchResults(itemKeyInfo), function(index)
		local row = C_AuctionHouse.GetItemSearchResultInfo(itemKeyInfo, index)
		if row then
			return row.buyoutAmount, row.quantity
		end
	end)
	RecordSearch(M.ItemKey(itemKeyInfo.itemID, itemKeyInfo.itemSuffix), prices, listings, ascending,
		C_AuctionHouse.GetItemSearchResultsQuantity(itemKeyInfo), C_AuctionHouse.HasFullItemSearchResults(itemKeyInfo))
end

local function FlushSearches()
	local list = pending
	pending = {}
	settleTimer = nil
	if not currentHouse then
		return
	end
	for _, read in pairs(list) do
		read()
	end
	if next(list) then
		ns.Notify("PRICES_CHANGED")
	end
end

-- Searching for an item is interacting with it, so it joins the scope. One search fires several
-- events while its rows arrive, so reading waits until they settle.
local function QueueSearch(key, itemID, read)
	if not (db and currentHouse and itemID) then
		return
	end
	AddToScope(itemID)
	pending[key] = read
	if not settleTimer then
		settleTimer = C_Timer.NewTimer(SEARCH_SETTLE_SECONDS, FlushSearches)
	end
end

local function OnCommoditySearch(_, itemID)
	QueueSearch("c" .. tostring(itemID), itemID, function()
		ReadCommoditySearch(itemID)
	end)
end

local function OnItemSearch(_, itemKeyInfo)
	if type(itemKeyInfo) ~= "table" then
		return
	end
	local itemID = itemKeyInfo.itemID
	QueueSearch("i" .. tostring(M.ItemKey(itemID, itemKeyInfo.itemSuffix)), itemID, function()
		ReadItemSearch(itemKeyInfo)
	end)
end

-- Browse rows have no tiers, only the lowest price and total, so they update `last` and nothing else.
local function RecordBrowse(results)
	if not (db and currentHouse and results) then
		return
	end
	local now, recorded = time(), 0
	for _, row in ipairs(results) do
		local key = row.itemKey
		local itemID = key and key.itemID
		if M.InScope(itemID) and (row.totalQuantity or 0) > 0 and (row.minPrice or 0) > 0 then
			local entry = GetEntry(M.ItemKey(itemID, key.itemSuffix), currentHouse, true)
			local last = entry.last
			local repeated = last and now - last.t < DEDUPE_SECONDS and last.min == row.minPrice and last.qty == row.totalQuantity
			if not repeated then
				entry.last = { t = now, min = row.minPrice, qty = row.totalQuantity }
				recorded = recorded + 1
			end
		end
	end
	if recorded > 0 then
		LogScan(currentHouse, "search", recorded, "ui")
	end
end

local function OnBrowseUpdated()
	if db and currentHouse then
		RecordBrowse(C_AuctionHouse.GetBrowseResults())
	end
end

local function OnBrowseAdded(_, results)
	RecordBrowse(results)
end

----------------------------------------------------------------------------------------------------
-- Full scan. Reads the replicate list over several frames, collects in memory, and only stores once
-- every row was read: the list isn't reliable after the AH closes (Auctionator treats that as a
-- failed scan), and a partial list would count most of the market as disappeared.
----------------------------------------------------------------------------------------------------

local function CanHaveSuffix(itemID)
	local classID = select(6, C_Item.GetItemInfoInstant(itemID))
	return classID == nil or classID == 2 or classID == 4 -- unknown, weapon, armor
end

local function CollectRow(scan, index)
	local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = C_AuctionHouse.GetReplicateItemInfo(index)
	if not (M.InScope(itemID) and (count or 0) > 0 and (buyout or 0) > 0) then
		return true
	end
	-- Auctionator's comment: the list sometimes holds rows with no item data. It skips them too.
	if not C_Item.DoesItemExistByID(itemID) then
		return true
	end
	local suffix
	if CanHaveSuffix(itemID) then
		local link = C_AuctionHouse.GetReplicateItemLink(index)
		if not link then
			C_Item.RequestLoadItemDataByID(itemID)
			return false
		end
		suffix = SuffixFromLink(link)
	end
	local key = M.ItemKey(itemID, suffix)
	local rows = scan.rows[key]
	if not rows then
		rows = { prices = {}, listings = 0 }
		scan.rows[key] = rows
	end
	AddRow(rows.prices, math.max(1, math.floor(buyout / count + 0.5)), count)
	rows.listings = rows.listings + 1
	return true
end

local function FinishScan(scan)
	if job == scan then
		job = nil
	end
	lastScan = { count = scan.count, t = scan.t }
	LogScan(scan.house, "full", scan.recorded, scan.source)
	ns.Notify("PRICES_CHANGED")
	if not currentHouse then
		M.Prune()
	end
end

-- An item with no row in a finished scan is really off the market, which a search can't show.
-- Only for items whose rows were all read.
local function CommitScan(scan)
	scan.phase = "commit"
	local keys, seen = {}, {}
	for key in pairs(scan.rows) do
		keys[#keys + 1] = key
		seen[key] = true
	end
	for key, perItem in pairs(db.items) do
		if not seen[key] and perItem[scan.house] then
			keys[#keys + 1] = key
		end
	end
	Chunked(#keys, COMMIT_PER_FRAME, function(i)
		local key = keys[i]
		if scan.unread[ItemIDOfKey(key)] then
			return
		end
		local rows = scan.rows[key]
		if rows then
			local obs = M.BuildObservation(rows.prices, rows.listings)
			if M.ApplyObservation(GetEntry(key, scan.house, true), obs, scan.t) then
				scan.recorded = scan.recorded + 1
			end
		else
			local entry = GetEntry(key, scan.house)
			local prev = entry and entry.raw[#entry.raw]
			if prev and prev.total > 0 then
				M.ApplyObservation(entry, { tiers = {}, total = 0, listings = 0 }, scan.t)
			end
		end
	end, function()
		FinishScan(scan)
	end)
end

-- The list must stay what it was while it is read; a change means the rows moved under us.
local function ReadStopped(scan)
	if not scan.aborted and C_AuctionHouse.GetNumReplicateItems() ~= scan.count then
		scan.aborted = true
		if job == scan then
			job = nil
		end
	end
	return scan.aborted
end

local function RetryLinks(scan, attempt)
	if ReadStopped(scan) then
		return
	end
	local missing = {}
	Chunked(#scan.waiting, ROWS_PER_FRAME, function(i)
		local index = scan.waiting[i]
		if not CollectRow(scan, index) then
			missing[#missing + 1] = index
		end
	end, function()
		scan.waiting = missing
		if #missing == 0 then
			CommitScan(scan)
		elseif attempt >= LINK_RETRIES then
			for _, index in ipairs(missing) do
				local itemID = select(17, C_AuctionHouse.GetReplicateItemInfo(index))
				if itemID then
					scan.unread[itemID] = true
				end
			end
			CommitScan(scan)
		else
			C_Timer.After(LINK_RETRY_SECONDS, function()
				RetryLinks(scan, attempt + 1)
			end)
		end
	end, function()
		return ReadStopped(scan)
	end)
end

local function OnReplicateList()
	if not (db and currentHouse) then
		return
	end
	local count = C_AuctionHouse.GetNumReplicateItems()
	if not count or count <= 0 then
		return
	end
	if job and (job.phase == "commit" or job.count == count) then
		return -- the event again for the list already being handled
	end
	if lastScan and lastScan.count == count and time() - lastScan.t < DEDUPE_SECONDS then
		return
	end
	if job then
		job.aborted = true
	end
	local scan = {
		phase = "read",
		house = currentHouse,
		count = count,
		t = time(),
		rows = {},
		waiting = {},
		unread = {},
		recorded = 0,
		source = ns.HasAuctionator() and "auctionator" or "ui",
	}
	job = scan
	Chunked(count, ROWS_PER_FRAME, function(i)
		local index = i - 1 -- the list is 0-based, as Auctionator reads it
		if not CollectRow(scan, index) then
			scan.waiting[#scan.waiting + 1] = index
		end
	end, function()
		if #scan.waiting > 0 then
			C_Timer.After(LINK_RETRY_SECONDS, function()
				RetryLinks(scan, 1)
			end)
		else
			CommitScan(scan)
		end
	end, function()
		return ReadStopped(scan)
	end)
end

----------------------------------------------------------------------------------------------------
-- Pruning and saving
----------------------------------------------------------------------------------------------------

local pruning = false

-- Aggregates, applies retention and packs entries again, a few per frame. Entries left packed since
-- the last prune have nothing new, so several AH visits in an hour only cost what they recorded.
function M.Prune()
	if not db or pruning then
		return
	end
	pruning = true
	local now = time()
	local all = now - (db.prunedAt or 0) >= PRUNE_ALL_SECONDS
	local list = {}
	for itemKey, perItem in pairs(db.items) do
		for houseKey, entry in pairs(perItem) do
			if all or type(entry) == "table" then
				list[#list + 1] = { itemKey, houseKey }
			end
		end
	end
	if all then
		db.prunedAt = now
	end
	Chunked(#list, PRUNE_PER_FRAME, function(i)
		local itemKey, houseKey = list[i][1], list[i][2]
		local entry = GetEntry(itemKey, houseKey)
		if entry then
			local perItem = db.items[itemKey]
			if M.AggregateEntry(entry, now) then
				perItem[houseKey] = M.EncodeEntry(entry)
			else
				perItem[houseKey] = nil
				if next(perItem) == nil then
					db.items[itemKey] = nil
				end
			end
		end
	end, function()
		pruning = false
	end)
end

-- Entries still in use go to disk as strings. An error here must not lose the save: a table left
-- as it is loads fine.
local function PackAll()
	if not db then
		return
	end
	for _, perItem in pairs(db.items) do
		for houseKey, entry in pairs(perItem) do
			if type(entry) == "table" then
				local ok, packed = pcall(M.EncodeEntry, entry)
				if ok then
					perItem[houseKey] = packed
				end
			end
		end
	end
end

----------------------------------------------------------------------------------------------------
-- Read API for later phases
----------------------------------------------------------------------------------------------------

-- { status = "ok", price, days } / { status = M.TOO_LITTLE_HISTORY, days } / { status = M.NO_DATA }
function M.Typical(itemKey, house)
	local entry = db and GetEntry(itemKey, house)
	if not entry or not (entry.last or next(entry.days) or entry.raw[1]) then
		return { status = M.NO_DATA, days = 0 }
	end
	local price, days = MedianOfDays(entry.days, DayNumber(time()))
	if days < MIN_HISTORY_DAYS then
		return { status = M.TOO_LITTLE_HISTORY, days = days }
	end
	return { status = "ok", price = price, days = days }
end

-- Latest observation { t, min, qty, listings, listed }, nil when never seen. listed is false when a
-- later full scan found none of it.
function M.Current(itemKey, house)
	local entry = db and GetEntry(itemKey, house)
	if not (entry and entry.last) then
		return nil
	end
	local l, latest = entry.last, entry.raw[#entry.raw]
	return { t = l.t, min = l.min, qty = l.qty, listings = l.listings, listed = not (latest and latest.total == 0 and latest.t >= l.t) }
end

-- Cheapest n price tiers of the latest observation with depth: { t, total, { price, qty }, ... }.
function M.Depth(itemKey, house, n)
	local entry = db and GetEntry(itemKey, house)
	local point = entry and entry.raw[#entry.raw]
	if not point then
		return nil
	end
	local depth = { t = point.t, total = point.total }
	for i = 1, math.min(#point.tiers, (n or MAX_TIERS) * 2), 2 do
		depth[#depth + 1] = { price = point.tiers[i], qty = point.tiers[i + 1] }
	end
	return depth
end

-- Houses with data for an item, faction house first, then by name: { { key, label, kind }, ... }.
function M.Houses(itemKey)
	local out = {}
	for houseKey in pairs(db and db.items[itemKey] or {}) do
		local house = db.houses[houseKey] or {}
		out[#out + 1] = { key = houseKey, label = house.label or houseKey, kind = house.kind }
	end
	table.sort(out, function(a, b)
		if (a.kind == "faction") ~= (b.kind == "faction") then
			return a.kind == "faction"
		end
		return a.label < b.label
	end)
	return out
end

-- Units that disappeared at prices up to the typical, last 7 days. Sold or expired, never "sold".
function M.Disappeared(itemKey, house)
	local entry = db and GetEntry(itemKey, house)
	local units, today = 0, DayNumber(time())
	for day = today - TYPICAL_DAYS + 1, today do
		local d = entry and entry.days[day]
		units = units + (d and d.gone or 0)
	end
	return units
end

----------------------------------------------------------------------------------------------------
-- Display (phase 2): price per basis and house, depth figures, thin-market flag, best house.
-- Veli's rule on #26: a cheap price at a thin house doesn't mean the item sells there or that enough
-- is there to buy, so every price comes with its depth.
----------------------------------------------------------------------------------------------------

M.NEAR_MIN_SHARE = 0.10 -- "units within +10% of min"
M.THIN_SHARE = 0.10 -- thin when the cheapest tier holds less than this share of those units
M.MIN_HISTORY_DAYS = MIN_HISTORY_DAYS
M.CHOICES = { "faction", "BootyBay", "Gadgetzan", "Everlook" } -- the profit house setting

-- Lowest and highest price seen in the last 7 days: daily aggregates plus raw points and the latest
-- browse price not aggregated yet. The high end is the dearest stored tier (phase 1's `hi`), not
-- the dearest minimum. nil when nothing was seen.
function M.Range(itemKey, house)
	local entry = db and GetEntry(itemKey, house)
	if not entry then
		return nil
	end
	local first = DayNumber(time()) - TYPICAL_DAYS + 1
	local lo, hi
	local function see(price)
		if price then
			lo = (not lo or price < lo) and price or lo
			hi = (not hi or price > hi) and price or hi
		end
	end
	for day, d in pairs(entry.days) do
		if day >= first then
			see(d.lo)
			see(d.hi)
		end
	end
	for _, point in ipairs(entry.raw) do
		if DayNumber(point.t) >= first then
			for i = 1, #point.tiers, 2 do
				see(point.tiers[i])
			end
		end
	end
	if entry.last and DayNumber(entry.last.t) >= first then
		see(entry.last.min)
	end
	return lo, hi
end

-- Units listed at up to min + 10% in a depth list (pure). The second value is true when the stored
-- tiers end inside that range while more units exist: the real count is at least the first value.
function M.NearMin(depth)
	local first = depth and depth[1]
	if not first then
		return nil
	end
	local limit = first.price * (1 + M.NEAR_MIN_SHARE)
	local units, stored = 0, 0
	for _, tier in ipairs(depth) do
		stored = stored + tier.qty
		if tier.price <= limit then
			units = units + tier.qty
		end
	end
	return units, depth[#depth].price <= limit and (depth.total or stored) > stored
end

-- Thin market (spec on #26), the one definition every view uses (pure): the cheapest tier holds less
-- than one stack, or less than 10% of the units within +10% of min. `stack` is the item's stack size,
-- nil when the client hasn't said (then only the share test runs). Returns thin, reason
-- ("stack" | "share"). A partial +10% count is a lower bound, so a share verdict from it still holds.
function M.IsThin(depth, stack)
	local first = depth and depth[1]
	if not first then
		return false
	end
	if stack and first.qty < stack then
		return true, "stack"
	end
	if first.qty < M.NearMin(depth) * M.THIN_SHARE then
		return true, "share"
	end
	return false
end

-- Cheapest way to buy `need` units from a depth list (pure): { cost, unit (average, rounded up),
-- top (dearest tier used), need }, or nil when the stored tiers don't hold that many.
function M.FillBatch(depth, need)
	need = math.max(1, need or 1)
	local left, cost = need, 0
	for _, tier in ipairs(depth or {}) do
		local take = math.min(left, tier.qty)
		cost = cost + take * tier.price
		left = left - take
		if left == 0 then
			return { cost = cost, unit = math.ceil(cost / need), top = tier.price, need = need }
		end
	end
	return nil
end

-- "3 @ 2s50 · 25 @ 10s" for the cheapest n tiers (pure; money formats copper).
function M.DepthText(depth, n, money)
	local parts = {}
	for i = 1, math.min(n or #depth, #depth) do
		parts[i] = ("%d @ %s"):format(depth[i].qty, money(depth[i].price))
	end
	return table.concat(parts, " · ")
end

function M.StackSize(itemKey)
	local itemID = ItemIDOfKey(itemKey)
	local size = itemID and C_Item.GetItemMaxStackSizeByID and C_Item.GetItemMaxStackSizeByID(itemID)
	return type(size) == "number" and size > 0 and size or nil
end

-- What a listings count means: commodities (stackable) list one row per price level (in-game check
-- on PR #32), other items one row per auction. nil when the stack size isn't known yet.
function M.ListingsLabel(itemKey)
	local stack = M.StackSize(itemKey)
	if not stack then
		return nil
	end
	return stack > 1 and "price levels" or "listings"
end

-- The house a profit setting means for this character: key and label, nil when realm or faction
-- can't be read. choice: "faction" (own faction house) | "BootyBay" | "Gadgetzan" | "Everlook".
function M.HouseFor(choice)
	local realm = GetRealmName()
	if not (realm and realm ~= "") then
		return nil
	end
	if NEUTRAL_LABELS[choice] then
		return realm .. "|N:" .. choice, NEUTRAL_LABELS[choice], "neutral"
	end
	local faction = UnitFactionGroup("player")
	if faction ~= "Horde" and faction ~= "Alliance" then
		return nil
	end
	return realm .. "|" .. faction:sub(1, 1), faction .. " AH", "faction"
end

function M.HouseLabel(houseKey)
	local house = db and db.houses[houseKey]
	return house and house.label or tostring(houseKey)
end

-- Has anything been recorded at this house (any scan, search or browse)?
function M.HasData(houseKey)
	return db ~= nil and db.scans[houseKey] ~= nil and db.scans[houseKey][1] ~= nil
end

function M.HasAnyData()
	if not db then
		return false
	end
	for _, list in pairs(db.scans) do
		if list[1] then
			return true
		end
	end
	return false
end

-- The cut measured at a house from own sales (phase 3), nil until then. Never assumed (decision 6).
function M.MeasuredCut(houseKey)
	local house = db and db.houses[houseKey]
	local cut = house and house.cut
	if cut and (cut.samples or 0) > 0 and cut.rate then
		return cut.rate, cut.samples
	end
	return nil
end

-- The price at one house by basis ("typical" | "current"): { copper, basis, fallback, days, t }.
-- Typical with too little history falls back to the current lowest, marked by `fallback`. The current
-- lowest only counts while the item is listed. nil, why (M.NO_DATA | M.TOO_LITTLE_HISTORY | "not listed").
function M.Quote(itemKey, house, basis)
	local current = M.Current(itemKey, house)
	local listed = current and current.listed and current.min
	if basis ~= "current" then
		local typical = M.Typical(itemKey, house)
		if typical.status == "ok" then
			return { copper = typical.price, basis = "typical", days = typical.days, t = current and current.t }
		end
		if listed then
			return { copper = current.min, basis = "current", fallback = M.TOO_LITTLE_HISTORY, days = typical.days, t = current.t }
		end
		return nil, current and "not listed" or typical.status
	end
	if listed then
		return { copper = current.min, basis = "current", t = current.t }
	end
	return nil, current and "not listed" or M.NO_DATA
end

-- Houses this character can use for an item: its own faction house and the neutral houses of its
-- realm, faction house first. Records of the other faction or another realm (alts) are left out.
function M.UsableHouses(itemKey)
	local own = M.HouseFor("faction")
	local realm = GetRealmName()
	local out = {}
	for _, house in ipairs(M.Houses(itemKey)) do
		if house.key == own or (realm and house.key:sub(1, #realm + 3) == realm .. "|N:") then
			out[#out + 1] = house
		end
	end
	return out
end

-- Everything the tooltip shows for one house.
function M.Snapshot(itemKey, house)
	local s = { key = house, label = M.HouseLabel(house), stack = M.StackSize(itemKey) }
	s.typical = M.Typical(itemKey, house)
	s.current = M.Current(itemKey, house)
	local depth = M.Depth(itemKey, house)
	if depth and depth[1] then
		s.depth = depth
		s.near, s.nearPartial = M.NearMin(depth)
		s.thin, s.thinWhy = M.IsThin(depth, s.stack)
	end
	s.lo, s.hi = M.Range(itemKey, house)
	return s
end

-- Where to buy: the house where `need` units (one craft batch) cost least, from its cheapest tiers.
-- need 1 (no recipe context) uses each house's latest lowest price. Returns
-- { key, label, cost, unit, top, need, atPrice, qty }, or nil plus the cheapest house that can't fill
-- the batch. atPrice: units at that lowest price when the latest tiers show it; qty: units listed.
function M.BestToBuy(itemKey, need)
	need = math.max(1, need or 1)
	local best, cheapest
	for _, house in ipairs(M.UsableHouses(itemKey)) do
		local current = M.Current(itemKey, house.key)
		if current and current.listed and current.min then
			local fill
			if need == 1 then
				local depth = M.Depth(itemKey, house.key)
				local first = depth and depth[1]
				fill = { cost = current.min, unit = current.min, top = current.min, need = 1,
					atPrice = first and first.price == current.min and first.qty or nil, qty = current.qty }
			else
				fill = M.FillBatch(M.Depth(itemKey, house.key), need)
			end
			if fill and (not best or fill.cost < best.cost) then
				fill.key, fill.label = house.key, house.label
				best = fill
			end
			if not cheapest or current.min < cheapest.unit then
				cheapest = { key = house.key, label = house.label, unit = current.min, qty = current.qty }
			end
		end
	end
	if best then
		return best
	end
	return nil, cheapest
end

-- Where to sell: the highest net after a measured cut. Houses whose cut isn't measured can't be
-- netted; when no house has one, the highest gross price wins and is marked cutUnverified.
-- Returns { key, label, gross, net, cut, basis, fallback, qty (units listed there now),
-- cutUnverified, unverifiedLeft } or nil.
function M.BestToSell(itemKey, basis)
	local known, unknown = nil, nil
	local unverified = 0
	for _, house in ipairs(M.UsableHouses(itemKey)) do
		local quote = M.Quote(itemKey, house.key, basis)
		if quote then
			local cut = M.MeasuredCut(house.key)
			local current = M.Current(itemKey, house.key)
			local pick = { key = house.key, label = house.label, gross = quote.copper, basis = quote.basis,
				fallback = quote.fallback, qty = current and current.listed and current.qty or 0 }
			if cut then
				pick.cut, pick.net = cut, math.floor(quote.copper * (1 - cut))
				if not known or pick.net > known.net then
					known = pick
				end
			else
				unverified = unverified + 1
				if not unknown or pick.gross > unknown.gross then
					unknown = pick
				end
			end
		end
	end
	if known then
		known.unverifiedLeft = unverified -- houses not compared because their cut is unknown
		return known
	end
	if unknown then
		unknown.cutUnverified = true
	end
	return unknown
end

----------------------------------------------------------------------------------------------------
-- /craftwise market <itemID or link>
----------------------------------------------------------------------------------------------------

function M.FormatAge(seconds)
	if seconds < 3600 then
		return ("%dm"):format(math.floor(seconds / 60))
	elseif seconds < 2 * DAY_SECONDS then
		return ("%dh"):format(math.floor(seconds / 3600))
	end
	return ("%dd"):format(math.floor(seconds / DAY_SECONDS))
end

local function PrintHouse(itemKey, house)
	local now = time()
	local current = M.Current(itemKey, house.key)
	if current then
		ns.Print(("%s: last %s, %d units%s, seen %s ago%s"):format(house.label, ns.FormatMoney(current.min), current.qty,
			current.listings and (", %d %s"):format(current.listings, M.ListingsLabel(itemKey) or "listings") or "", M.FormatAge(now - current.t),
			current.listed and "" or ", none in the latest full scan"))
	else
		ns.Print(house.label .. ": " .. M.NO_DATA)
	end
	local depth = M.Depth(itemKey, house.key, MAX_TIERS)
	if depth and depth[1] then
		local parts = {}
		for _, tier in ipairs(depth) do
			parts[#parts + 1] = ("%d @ %s"):format(tier.qty, ns.FormatMoney(tier.price))
		end
		ns.Print("  cheapest: " .. table.concat(parts, " · "))
	end
	local typical = M.Typical(itemKey, house.key)
	if typical.status == "ok" then
		ns.Print(("  typical: %s (%d days)"):format(ns.FormatMoney(typical.price), typical.days))
	elseif typical.status == M.TOO_LITTLE_HISTORY then
		ns.Print(("  typical: %s (%d of %d days)"):format(M.TOO_LITTLE_HISTORY, typical.days, MIN_HISTORY_DAYS))
	end
	local gone = M.Disappeared(itemKey, house.key)
	if gone > 0 then
		ns.Print(("  disappeared in 7 days: %d units (sold or expired)"):format(gone))
	end
end

function M.Slash(arg)
	arg = arg or ""
	local itemID = tonumber(arg:match("item:(%d+)") or arg:match("^%s*(%d+)%s*$"))
	if not itemID then
		ns.Print("usage: /craftwise market <itemID or item link>")
		return
	end
	local keys = {}
	local linked = arg:match("item:") and M.ItemKey(itemID, SuffixFromLink(arg))
	if linked and db.items[linked] then
		keys[1] = linked
	else
		for key in pairs(db.items) do
			if ItemIDOfKey(key) == itemID then
				keys[#keys + 1] = key
			end
		end
		table.sort(keys, function(a, b)
			return tostring(a) < tostring(b)
		end)
	end
	if not keys[1] then
		ns.Print(("item %d: %s%s"):format(itemID, M.NO_DATA, M.InScope(itemID) and "" or " (not a recorded item)"))
		return
	end
	for _, key in ipairs(keys) do
		ns.Print("item " .. tostring(key) .. ":")
		for _, house in ipairs(M.Houses(key)) do
			PrintHouse(key, house)
		end
	end
end

----------------------------------------------------------------------------------------------------
-- Events
----------------------------------------------------------------------------------------------------

ns.Listen("DB_READY", function()
	CraftWiseMarketDB = CraftWiseMarketDB or {}
	db = CraftWiseMarketDB
	db.v = db.v or 1
	db.houses = db.houses or {}
	db.scans = db.scans or {}
	db.items = db.items or {}
	db.cutSamples = db.cutSamples or {}
	db.scope = db.scope or {}
	db.scope.items = db.scope.items or {}
	db.scope.skillLines = db.scope.skillLines or {}
end)

ns.Listen("RECIPES_CHANGED", M.RefreshScope)

ns.On("PLAYER_LOGIN", function()
	M.RefreshScope()
	ScanBags()
	M.Prune()
end)
ns.On("PLAYER_LOGOUT", PackAll)
ns.On("BAG_UPDATE_DELAYED", ScanBags)
ns.On("BANKFRAME_OPENED", ScanBank)
ns.On("PLAYERBANKSLOTS_CHANGED", ScanBank)
ns.On("CHAT_MSG_LOOT", OnLoot)

ns.On("AUCTION_HOUSE_SHOW", function()
	if not db then
		return
	end
	local houseKey, house = M.DetectHouse()
	currentHouse = houseKey
	if houseKey then
		db.houses[houseKey] = db.houses[houseKey] or house
	end
end)

ns.On("AUCTION_HOUSE_CLOSED", function()
	if not db then
		return
	end
	if settleTimer then
		settleTimer:Cancel()
	end
	FlushSearches()
	currentHouse = nil
	if job and job.phase == "read" then
		job.aborted = true
		job = nil
	end
	if not job then -- a scan still being stored prunes when it finishes
		M.Prune()
	end
end)

ns.On("REPLICATE_ITEM_LIST_UPDATE", OnReplicateList)
ns.On("COMMODITY_SEARCH_RESULTS_UPDATED", OnCommoditySearch)
ns.On("COMMODITY_SEARCH_RESULTS_ADDED", OnCommoditySearch)
ns.On("ITEM_SEARCH_RESULTS_UPDATED", OnItemSearch)
ns.On("ITEM_SEARCH_RESULTS_ADDED", OnItemSearch)
ns.On("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", OnBrowseUpdated)
ns.On("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", OnBrowseAdded)
