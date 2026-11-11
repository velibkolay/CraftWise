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
--     last = { t, min, qty, listings, off },            latest observation (browse has no listings);
--                                                        off: a later full scan didn't list it (#90)
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
-- Every item of a full scan or a browse list is stored (#90): items in the scope get the history
-- above, items outside it only `last` (on disk "t,min,qty,listings[,off]||", no raw, no days).
--
-- auctionator = { source, house = "unknown", label, items = { [itemID] = "t,copper,age" } } (#90):
-- Auctionator's price for items CraftWise has no price for at the profit house, read through its
-- public API. Auctionator mixes houses (evidence on #26), so it is kept apart and never read back
-- into items[]. t = when CraftWise read it, age = days since Auctionator saw it (its API).
-- names = { [itemID] = name } for the items above, from the client, so the saved file can be read
-- without the game (#90). Not part of any record; rebuilt from the client's cache at logout.
-- itemInfo = { [itemID] = "q,i,c,s,t" } for the same items (#92): quality, icon file ID, class and
-- subclass ID as the client returns them, t = when read; base 36, an unknown field empty. The name
-- stays in names (one name store). Read again after INFO_REFRESH; dropped with the records.
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
-- An entry with `last` only is a short string written or checked without decoding: it counts as
-- 1/LIGHT_SHARE of a full entry in a frame's budget (#90).
local COMMIT_PER_FRAME = 40
local PRUNE_PER_FRAME = 20
local LIGHT_SHARE = 25
local AUCTIONATOR_PER_FRAME = 200
local AUCTIONATOR_REFRESH = 3600 -- an unchanged Auctionator price is written again at most hourly
local AUCTIONATOR_LOGIN_DELAY = 5 -- Auctionator sets up its price database during login
local PRUNE_ALL_SECONDS = 3600 -- packed entries are revisited this often; entries in use on every prune
local SEARCH_SETTLE_SECONDS = 0.3
local LINK_RETRIES = 10
local LINK_RETRY_SECONDS = 0.5
local INFO_PER_FRAME = 500 -- item info (#92): items checked per frame
local INFO_LOAD_BATCH = 100 -- load requests per batch, as the sell prices of #83
local INFO_LOAD_SECONDS = 0.2
local INFO_REFRESH = 30 * 86400 -- stored item info is read from the client again after this

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
		if l.off then
			last = last .. "," .. Base36(l.off)
		end
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
		entry.last = { t = Num(f[1]), min = Num(f[2]), qty = Num(f[3]), listings = Num(f[4]), off = Num(f[5]) }
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

-- An entry with `last` and no history (#90): no raw points, no days. Packed it ends in "||".
local function IsLastOnly(entry)
	if type(entry) == "string" then
		return entry:sub(-2) == "||"
	end
	return type(entry) == "table" and entry.raw[1] == nil and next(entry.days) == nil
end
M.IsLastOnly = IsLastOnly

-- `last` of a packed last-only entry, without building the whole entry.
local function PackedLast(s)
	local f = Split(s:sub(1, -3), ",")
	if not Num(f[1]) then
		return nil
	end
	return { t = Num(f[1]), min = Num(f[2]), qty = Num(f[3]), listings = Num(f[4]), off = Num(f[5]) }
end

-- Stores `last` for an item at a house. A last-only entry is written as its packed string directly;
-- an entry with history keeps it and gets the new `last`.
local function StoreLast(itemKey, houseKey, last)
	local perItem = db.items[itemKey]
	if not perItem then
		perItem = {}
		db.items[itemKey] = perItem
	end
	local entry = perItem[houseKey]
	if entry == nil or (type(entry) == "string" and IsLastOnly(entry)) then
		perItem[houseKey] = M.EncodeEntry({ last = last })
	else
		GetEntry(itemKey, houseKey).last = last
	end
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
-- professions, plus every item the player interacted with. Only scope items keep a history; the rest
-- of a full scan or browse list keeps `last` only (#90). The scope only grows. Buying and selling at
-- a merchant and posting on the AH all pass through the bags.
-- #67 adds the recipe items (recipe, pattern, plans, formula, schematic) of those professions:
--   1. the item that teaches a bundled recipe of a scope profession (ns.SourceData, client DB2),
--   2. recipe items recorded in game for such a recipe (CraftWiseDB.sources, #37),
--   3. any AH row whose item the client files as a recipe of a scope profession (item class Recipe,
--      subclass = the profession). This also takes profession books (Expert Cookbook and the like)
--      when the client files them under the profession; the "Book" subclass names no profession and
--      stays out. Bundled data has no profession-book IDs (no DB2 table in the generators lists them).
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

-- Profession names (ns.ProfessionSkillLines) by the client's Enum.ItemRecipeSubclass field name.
-- Book, Jewelcrafting and Inscription name no profession CraftWise has a skill line for.
local RECIPE_SUBCLASS_PROFESSION = {
	Leatherworking = "Leatherworking",
	Tailoring = "Tailoring",
	Engineering = "Engineering",
	Blacksmithing = "Blacksmithing",
	Cooking = "Cooking",
	Alchemy = "Alchemy",
	FirstAid = "First Aid",
	Enchanting = "Enchanting",
	Fishing = "Fishing",
}

-- [subclassID] = skill line, from the client's enum; nil until both the enum and the bundled names exist.
local function RecipeSubclassLines()
	local enum = Enum and Enum.ItemRecipeSubclass
	if not (enum and ns.ProfessionSkillLines) then
		return nil
	end
	local out = {}
	for field, name in pairs(RECIPE_SUBCLASS_PROFESSION) do
		local subclass, line = enum[field], ns.ProfessionSkillLines[name]
		if subclass and line then
			out[subclass] = line
		end
	end
	return out
end

local function RecipeClass()
	return Enum and Enum.ItemClass and Enum.ItemClass.Recipe or 9
end

-- The skill line of the profession the client files this recipe item under, or nil.
local subclassLines
function M.RecipeItemLine(itemID)
	if not (itemID and C_Item and C_Item.GetItemInfoInstant) then
		return nil
	end
	local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(itemID)
	if classID == nil or classID ~= RecipeClass() then
		return nil
	end
	subclassLines = subclassLines or RecipeSubclassLines()
	return subclassLines and subclassLines[subclassID]
end

-- AH rows of items outside the scope are checked once per session: a full scan reads every row.
local checked = {}
local function InScopeOrRecipe(itemID)
	if M.InScope(itemID) then
		return true
	end
	if not db or itemID == nil or checked[itemID] then
		return false
	end
	checked[itemID] = true
	local line = M.RecipeItemLine(itemID)
	if line and db.scope.skillLines[line] then
		AddToScope(itemID)
		return true
	end
	return false
end
M.InScopeOrRecipe = InScopeOrRecipe

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
	local recipes = ns.RecipeData or {}
	for _, data in pairs(recipes) do
		if lines[data.skillLine] then
			AddRecipeItems(data.reagents, data.output)
		end
	end
	-- Every recipe a trainer showed (#83): its output and reagents, also for recipes the bundled data
	-- lacks, so their prices are recorded before the recipe is learned.
	for _, rec in pairs(ns.db and ns.db.trainer or {}) do
		AddRecipeItems(rec.reagents, rec.output)
	end
	-- Recipe items (#67): bundled, then recorded in game.
	for recipeID, source in pairs(ns.SourceData or {}) do
		local data = recipes[recipeID]
		if source.item and data and lines[data.skillLine] then
			AddToScope(source.item)
		end
	end
	for itemID, rec in pairs(ns.db and ns.db.sources or {}) do
		local data = rec.recipe and recipes[rec.recipe]
		if data and lines[data.skillLine] then
			AddToScope(itemID)
		end
	end
	checked = {} -- a new profession can take items a previous check left out
	if ns.PersistSellPrices then
		ns.PersistSellPrices(db.scope.items) -- vendor floor for uncached items later (#83)
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

-- items: entries recorded with history (the scope); lastOnly: entries outside it that got `last`.
local function LogScan(houseKey, kind, items, source, lastOnly)
	local list = db.scans[houseKey] or {}
	db.scans[houseKey] = list
	list[#list + 1] = { t = time(), kind = kind, items = items, source = source,
		lastOnly = lastOnly and lastOnly > 0 and lastOnly or nil }
	while #list > SCANS_KEPT do
		table.remove(list, 1)
	end
end

-- Runs step(i) for i = 1..count, up to `budget` per frame. A step costs 1 unless it returns a number.
local function Chunked(count, budget, step, done, isCancelled)
	local index = 1
	local function run()
		if isCancelled and isCancelled() then
			return
		end
		local spent = 0
		while index <= count and spent < budget do
			local cost = step(index)
			spent = spent + (type(cost) == "number" and cost or 1)
			index = index + 1
		end
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

-- Browse rows have no tiers, only the lowest price and total, so they update `last` and nothing else,
-- for every item in the list (#90), in the scope or not.
local function RecordBrowse(results)
	if not (db and currentHouse and results) then
		return
	end
	local now, recorded, lastOnly = time(), 0, 0
	for _, row in ipairs(results) do
		local key = row.itemKey
		local itemID = key and key.itemID
		if itemID and (row.totalQuantity or 0) > 0 and (row.minPrice or 0) > 0 then
			local inScope = InScopeOrRecipe(itemID)
			local entry = GetEntry(M.ItemKey(itemID, key.itemSuffix), currentHouse, true)
			local last = entry.last
			local repeated = last and now - last.t < DEDUPE_SECONDS and last.min == row.minPrice and last.qty == row.totalQuantity
			if not repeated then
				entry.last = { t = now, min = row.minPrice, qty = row.totalQuantity }
				if inScope then
					recorded = recorded + 1
				else
					lastOnly = lastOnly + 1
				end
			end
		end
	end
	if recorded + lastOnly > 0 then
		LogScan(currentHouse, "search", recorded, "ui", lastOnly)
	end
end

-- Gear found by the Upgrades view's AH search (#50, decision 1): items outside the scope get their
-- browse price as `last` only, no history (no raw points, no days). Since #90 RecordBrowse stores
-- them as well from the same browse event, so this only stores what that missed. Returns how many
-- were stored.
function M.RecordGear(results)
	if not (db and currentHouse and results) then
		return 0
	end
	local now, recorded = time(), 0
	for _, row in ipairs(results) do
		local key = row.itemKey
		local itemID = key and key.itemID
		if itemID and not M.InScope(itemID) and (row.totalQuantity or 0) > 0 and (row.minPrice or 0) > 0 then
			local entry = GetEntry(M.ItemKey(itemID, key.itemSuffix), currentHouse, true)
			local last = entry.last
			if not (last and now - last.t < DEDUPE_SECONDS and last.min == row.minPrice and last.qty == row.totalQuantity) then
				entry.last = { t = now, min = row.minPrice, qty = row.totalQuantity }
				recorded = recorded + 1
			end
		end
	end
	if recorded > 0 then
		LogScan(currentHouse, "gear", recorded, "upgrades")
	end
	return recorded
end

-- The house the open auction house belongs to, nil when closed or not known.
function M.CurrentHouse()
	return currentHouse
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

-- Every row is read (#90). Items in the scope collect their price levels for a raw point; the rest
-- only what `last` holds (lowest unit price, units, listings).
local function CollectRow(scan, index)
	local name, texture, count, quality, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID, hasAllInfo =
		C_AuctionHouse.GetReplicateItemInfo(index)
	if not ((count or 0) > 0 and (buyout or 0) > 0 and itemID) then
		return true
	end
	-- Auctionator's comment: the list sometimes holds rows with no item data. It skips them too.
	if not C_Item.DoesItemExistByID(itemID) then
		return true
	end
	local inScope = scan.scope[itemID]
	if inScope == nil then
		inScope = InScopeOrRecipe(itemID) -- once per item and scan, so all its rows go the same way
		scan.scope[itemID] = inScope
	end
	if type(name) == "string" and name ~= "" then
		scan.names[itemID] = name
	end
	-- Quality and icon of the row, for items the client cache doesn't hold yet (#92). The docs mark
	-- qualityID as never nil, so it is only taken from rows the client says are complete.
	if hasAllInfo and type(quality) == "number" and not scan.info[itemID] then
		scan.info[itemID] = { q = quality, i = type(texture) == "number" and texture or nil }
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
	local unit = math.max(1, math.floor(buyout / count + 0.5))
	if not inScope then
		local light = scan.light[key]
		if not light then
			scan.light[key] = { min = unit, qty = count, listings = 1 }
		else
			light.min = math.min(light.min, unit)
			light.qty = light.qty + count
			light.listings = light.listings + 1
		end
		return true
	end
	local rows = scan.rows[key]
	if not rows then
		rows = { prices = {}, listings = 0 }
		scan.rows[key] = rows
	end
	AddRow(rows.prices, unit, count)
	rows.listings = rows.listings + 1
	return true
end

local function FinishScan(scan)
	if job == scan then
		job = nil
	end
	lastScan = { count = scan.count, t = scan.t }
	LogScan(scan.house, "full", scan.recorded, scan.source, scan.lastOnly)
	for itemID, name in pairs(scan.names) do
		db.names[itemID] = name
	end
	M.FillItemInfo(scan.info)
	ns.Notify("PRICES_CHANGED")
	if not currentHouse then
		M.Prune()
	end
end

-- An item with no row in a finished scan is really off the market, which a search can't show.
-- Only for items whose rows were all read.
-- Items outside the scope have no raw point to say so: their `last` gets `off` = the scan's time.
-- Steps return their cost: an entry with history 1 unit, a last-only one 1/LIGHT_SHARE (#90).
local function CommitScan(scan)
	scan.phase = "commit"
	local keys, seen = {}, {}
	for key in pairs(scan.rows) do
		keys[#keys + 1] = key
		seen[key] = true
	end
	for key in pairs(scan.light) do
		if not seen[key] then
			keys[#keys + 1] = key
			seen[key] = true
		end
	end
	for key, perItem in pairs(db.items) do
		if not seen[key] and perItem[scan.house] then
			keys[#keys + 1] = key
		end
	end
	Chunked(#keys, COMMIT_PER_FRAME * LIGHT_SHARE, function(i)
		local key = keys[i]
		if scan.unread[ItemIDOfKey(key)] then
			return 1
		end
		local rows, light = scan.rows[key], scan.light[key]
		if rows then
			local obs = M.BuildObservation(rows.prices, rows.listings)
			if M.ApplyObservation(GetEntry(key, scan.house, true), obs, scan.t) then
				scan.recorded = scan.recorded + 1
			end
			return LIGHT_SHARE
		elseif light then
			StoreLast(key, scan.house, { t = scan.t, min = light.min, qty = light.qty, listings = light.listings })
			scan.lastOnly = scan.lastOnly + 1
			return 1
		end
		local perItem = db.items[key]
		local stored = perItem and perItem[scan.house]
		if stored == nil then
			return 1 -- pruned meanwhile
		elseif IsLastOnly(stored) then
			local last = type(stored) == "string" and PackedLast(stored) or stored.last
			if last and last.t < scan.t and not (last.off and last.off >= last.t) then
				last.off = scan.t
				if type(stored) == "string" then
					perItem[scan.house] = M.EncodeEntry({ last = last })
				end
			end
			return 1
		end
		local entry = GetEntry(key, scan.house)
		local prev = entry and entry.raw[#entry.raw]
		if prev and prev.total > 0 then
			M.ApplyObservation(entry, { tiers = {}, total = 0, listings = 0 }, scan.t)
		end
		return LIGHT_SHARE
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
		light = {},
		scope = {},
		names = {},
		info = {},
		waiting = {},
		unread = {},
		recorded = 0,
		lastOnly = 0,
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
-- Packed last-only entries (#90) are only checked for age, without decoding: 1/LIGHT_SHARE of the cost.
-- The full pass also drops Auctionator prices and names nothing refers to any more.
local function DropEntry(itemKey, houseKey)
	local perItem = db.items[itemKey]
	perItem[houseKey] = nil
	if next(perItem) == nil then
		db.items[itemKey] = nil
	end
end

local function PruneExtras(now)
	local exported = db.auctionator.items
	for itemID, packed in pairs(exported) do
		local t = Num(Split(packed, ",")[1])
		if not t or now - t > KEEP_DAYS * DAY_SECONDS then
			exported[itemID] = nil
		end
	end
	local used = {}
	for key in pairs(db.items) do
		used[type(key) == "number" and key or ItemIDOfKey(key) or key] = true
	end
	for itemID in pairs(db.names) do
		if not (used[itemID] or exported[itemID]) then
			db.names[itemID] = nil
		end
	end
	for itemID in pairs(db.itemInfo) do
		if not (used[itemID] or exported[itemID]) then
			db.itemInfo[itemID] = nil
		end
	end
end

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
	Chunked(#list, PRUNE_PER_FRAME * LIGHT_SHARE, function(i)
		local itemKey, houseKey = list[i][1], list[i][2]
		local perItem = db.items[itemKey]
		local stored = perItem and perItem[houseKey]
		if type(stored) == "string" and IsLastOnly(stored) then
			local last = PackedLast(stored)
			if not (last and now - last.t <= KEEP_DAYS * DAY_SECONDS) then
				DropEntry(itemKey, houseKey)
			end
			return 1
		end
		local entry = stored and GetEntry(itemKey, houseKey)
		if entry then
			if M.AggregateEntry(entry, now) then
				perItem[houseKey] = M.EncodeEntry(entry)
			else
				DropEntry(itemKey, houseKey)
			end
		end
		return LIGHT_SHARE
	end, function()
		if all then
			PruneExtras(now)
		end
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
-- Auctionator fallback export (#90). Auctionator keeps one bucket per realm and mixes the houses
-- (evidence on #26), so its price is stored apart, labelled "house unknown", and never read back
-- into the per-house data or the profit numbers (those read Auctionator live, Prices.lua).
----------------------------------------------------------------------------------------------------

M.AUCTIONATOR_HOUSE = "unknown"

-- Stores Auctionator's price for an item CraftWise has no price for. Returns true when written. An
-- unchanged price is written again at most hourly, so a tooltip shown often costs a string compare.
function M.ExportAuctionator(itemID, copper, age)
	if not (db and type(itemID) == "number" and type(copper) == "number" and copper > 0) then
		return false
	end
	age = type(age) == "number" and math.floor(age) or nil
	local now, items = time(), db.auctionator.items
	local old = items[itemID]
	if old then
		local f = Split(old, ",")
		if Num(f[2]) == math.floor(copper) and Num(f[3]) == age and now - (Num(f[1]) or 0) < AUCTIONATOR_REFRESH then
			return false
		end
	end
	items[itemID] = Base36(now) .. "," .. Base36(copper) .. "," .. Base36(age)
	return true
end

-- { t (read by CraftWise), copper, age (days, Auctionator's), label, house = "unknown" } or nil.
function M.AuctionatorExport(itemID)
	local packed = db and db.auctionator.items[itemID]
	if not packed then
		return nil
	end
	local f = Split(packed, ",")
	return { t = Num(f[1]), copper = Num(f[2]), age = Num(f[3]), label = db.auctionator.label, house = M.AUCTIONATOR_HOUSE }
end

-- Every scope item with no record at the profit house gets Auctionator's price, a few per frame.
-- Items looked up elsewhere (ns.AuctionQuote) are exported when they fall back to Auctionator.
local exporting = false
function M.ExportAuctionatorScope()
	if not db or exporting or not (ns.HasAuctionator and ns.HasAuctionator()) then
		return
	end
	local house = ns.ProfitHouse and ns.ProfitHouse()
	local list = {}
	for itemID in pairs(db.scope.items) do
		local perItem = db.items[itemID]
		if type(itemID) == "number" and not (house and perItem and perItem[house]) then
			list[#list + 1] = itemID
		end
	end
	exporting = true
	Chunked(#list, AUCTIONATOR_PER_FRAME, function(i)
		local copper, age = ns.GetAuctionPrice(list[i])
		if copper then
			M.ExportAuctionator(list[i], copper, age)
		end
	end, function()
		exporting = false
	end)
end

----------------------------------------------------------------------------------------------------
-- Names, item info and the snapshot. The saved file holds item IDs; names (#90) and item info (#92:
-- quality, icon, class, subclass) come from the client, so the file (and the price site of #100) can
-- show items without the game or a third-party database.
----------------------------------------------------------------------------------------------------

local function InfoNum(v)
	return type(v) == "number" and v or nil
end

-- "q,i,c,s,t" in base 36; an unknown field stays empty. Negative numbers aren't expected from the
-- client; one would be stored as unknown rather than as a wrong 0.
function M.EncodeItemInfo(info, t)
	local function field(v)
		v = InfoNum(v)
		return v and v >= 0 and Base36(v) or ""
	end
	return table.concat({ field(info.q), field(info.i), field(info.c), field(info.s), field(t) }, ",")
end

-- { n, q, i, c, s, t } for an item, nil when nothing is stored. n comes from names; any field the
-- client didn't give is nil.
function M.ItemInfo(itemID)
	local packed = db and db.itemInfo[itemID]
	if type(packed) ~= "string" then
		return nil
	end
	local f = Split(packed, ",")
	return { n = db.names[itemID], q = Num(f[1]), i = Num(f[2]), c = Num(f[3]), s = Num(f[4]), t = Num(f[5]) }
end

local function InfoTime(packed)
	return type(packed) == "string" and Num(packed:match("([^,]*)$")) or nil
end

-- What the client says about an item now: its name (nil when not cached) and { q, i, c, s }, nil
-- while the quality is unknown. hint = { q, i } from a complete full-scan row, used when the cache
-- doesn't have the item yet. Class, subclass and icon come from GetItemInfoInstant, which the client
-- answers without loading the item.
local function ClientItemInfo(itemID, hint)
	local name, quality, texture, classID, subclassID
	if C_Item and C_Item.GetItemInfo then
		local r = { C_Item.GetItemInfo(itemID) }
		name, quality, texture, classID, subclassID = r[1], r[3], r[10], r[12], r[13]
	end
	local icon, iClass, iSubclass
	if C_Item and C_Item.GetItemInfoInstant then
		local _, _, _, _, ic, c, sc = C_Item.GetItemInfoInstant(itemID)
		icon, iClass, iSubclass = ic, c, sc
	end
	quality = InfoNum(quality) or (hint and InfoNum(hint.q))
	if type(name) ~= "string" or name == "" then
		name = nil
	end
	if quality == nil then
		return name, nil
	end
	return name, {
		q = quality,
		i = InfoNum(icon) or InfoNum(texture) or (hint and InfoNum(hint.i)),
		c = InfoNum(iClass) or InfoNum(classID),
		s = InfoNum(iSubclass) or InfoNum(subclassID),
	}
end

-- Writes what the client knows now. Returns true when the info was stored.
local function StoreItemInfo(itemID, hint, now)
	local name, info = ClientItemInfo(itemID, hint)
	if name and db.names[itemID] == nil then
		db.names[itemID] = name
	end
	if not info then
		return false
	end
	db.itemInfo[itemID] = M.EncodeItemInfo(info, now or time())
	return true
end

-- Every item ID with a price: per-house records (suffix variants count once) and Auctionator exports.
local function PricedItemIDs()
	local list, seen = {}, {}
	local function add(itemID)
		if type(itemID) == "number" and not seen[itemID] then
			seen[itemID] = true
			list[#list + 1] = itemID
		end
	end
	for key in pairs(db.items) do
		add(type(key) == "number" and key or ItemIDOfKey(key))
	end
	for itemID in pairs(db.auctionator.items) do
		add(itemID)
	end
	return list
end

-- infoWaiting: requested, stored when GET_ITEM_INFO_RECEIVED names it. infoQueue / inInfoQueue: not
-- requested yet. An item whose load never answers is requested again by the next pass.
local infoWaiting, infoQueue, inInfoQueue, infoQueued = {}, {}, {}, false

-- Load requests a batch at a time, as for the sell prices (#83), so thousands of items never flood
-- the client.
local function RunInfoQueue()
	infoQueued = false
	local n = 0
	while n < INFO_LOAD_BATCH and #infoQueue > 0 do
		local itemID = table.remove(infoQueue)
		inInfoQueue[itemID] = nil
		if db and not StoreItemInfo(itemID) then
			infoWaiting[itemID] = true
			if C_Item and C_Item.RequestLoadItemDataByID then
				C_Item.RequestLoadItemDataByID(itemID)
			end
			n = n + 1
		end
	end
	if #infoQueue > 0 then
		infoQueued = true
		C_Timer.After(INFO_LOAD_SECONDS, RunInfoQueue)
	end
end

function M.OnItemInfoReceived(itemID, success)
	if not (db and itemID and infoWaiting[itemID]) then
		return
	end
	infoWaiting[itemID] = nil
	if success ~= false then
		StoreItemInfo(itemID)
	end
end

-- Fills item info for every priced item that has none or whose info is older than INFO_REFRESH: from
-- the client cache (or the full-scan row in hints[itemID]) a few hundred per frame, and requests the
-- rest in batches. Runs after a full scan, on AH close and after login.
local filling, fillAgain = false, nil
function M.FillItemInfo(hints)
	if not db then
		return
	end
	if filling then
		fillAgain = fillAgain or {}
		for itemID, hint in pairs(hints or {}) do
			fillAgain[itemID] = hint
		end
		return
	end
	filling = true
	hints = hints or {}
	local list = PricedItemIDs()
	local now = time()
	Chunked(#list, INFO_PER_FRAME, function(i)
		local itemID = list[i]
		local t = InfoTime(db.itemInfo[itemID])
		if t and now - t < INFO_REFRESH then
			return
		end
		if not StoreItemInfo(itemID, hints[itemID], now) and not inInfoQueue[itemID] then
			inInfoQueue[itemID] = true
			infoQueue[#infoQueue + 1] = itemID
		end
	end, function()
		filling = false
		if not infoQueued and #infoQueue > 0 then
			RunInfoQueue()
		end
		if fillAgain then
			local again = fillAgain
			fillAgain = nil
			M.FillItemInfo(again)
		end
	end)
end

-- Names and item info of every item with a record that the client has cached now. Runs at logout,
-- so it only reads the cache and requests nothing.
local function FillNames()
	if not (db and C_Item) then
		return
	end
	local getName = C_Item.GetItemNameByID
	local now = time()
	for _, itemID in ipairs(PricedItemIDs()) do
		if db.names[itemID] == nil and getName then
			local name = getName(itemID)
			if type(name) == "string" and name ~= "" then
				db.names[itemID] = name
			end
		end
		if db.itemInfo[itemID] == nil then
			StoreItemInfo(itemID, nil, now)
		end
	end
end
M.FillNames = FillNames

-- What the character snapshot says about the market data: per house, the last full scan and how
-- many items have a price (with history or `last` only). The prices are in CraftWiseMarketDB.
function M.SnapshotSummary()
	if not db then
		return nil, "market data not loaded"
	end
	local houses = {}
	for houseKey, house in pairs(db.houses) do
		local h = { label = house.label, kind = house.kind, items = 0, withHistory = 0 }
		local list = db.scans[houseKey] or {}
		h.lastRecorded = list[#list] and list[#list].t or nil
		for i = #list, 1, -1 do
			if list[i].kind == "full" then
				h.lastFullScan, h.lastFullScanSource = list[i].t, list[i].source
				h.lastFullScanItems, h.lastFullScanLastOnly = list[i].items, list[i].lastOnly or 0
				break
			end
		end
		houses[houseKey] = h
	end
	for _, perItem in pairs(db.items) do
		for houseKey, entry in pairs(perItem) do
			local h = houses[houseKey]
			if h then
				h.items = h.items + 1
				if not IsLastOnly(entry) then
					h.withHistory = h.withHistory + 1
				end
			end
		end
	end
	local exported, named, described = 0, 0, 0
	for _ in pairs(db.auctionator.items) do
		exported = exported + 1
	end
	for _ in pairs(db.names) do
		named = named + 1
	end
	for _ in pairs(db.itemInfo) do
		described = described + 1
	end
	return { where = "CraftWiseMarketDB", houses = houses, names = named, itemInfo = described,
		auctionator = { label = db.auctionator.label, house = M.AUCTIONATOR_HOUSE, items = exported } }
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
-- later full scan found none of it: a raw point with no units, or `off` on a last-only entry (#90).
function M.Current(itemKey, house)
	local entry = db and GetEntry(itemKey, house)
	if not (entry and entry.last) then
		return nil
	end
	local l, latest = entry.last, entry.raw[#entry.raw]
	local absent = (latest and latest.total == 0 and latest.t >= l.t) or (l.off and l.off >= l.t)
	return { t = l.t, min = l.min, qty = l.qty, listings = l.listings, listed = not absent }
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
	local entry = GetEntry(itemKey, house.key)
	if entry and IsLastOnly(entry) and not M.InScope(ItemIDOfKey(itemKey)) then
		ns.Print("  history: none (outside the market scope, latest price only)")
		return
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
	-- The item's link or name (#59); a suffix variant adds its key.
	ns.WithItemNames({ itemID }, function()
		local item = ns.ItemChatText(itemID, { name = db.names[itemID] })
		local exported = M.AuctionatorExport(itemID)
		local function printExport()
			if exported then
				ns.Print(("%s: %s, read %s ago%s"):format(db.auctionator.label, ns.FormatMoney(exported.copper),
					M.FormatAge(time() - exported.t), exported.age and (", Auctionator saw it %d days ago"):format(exported.age) or ""))
			end
		end
		if not keys[1] then
			ns.Print(("%s: %s%s"):format(item, M.NO_DATA, M.InScope(itemID) and "" or " (not a recorded item)"))
			printExport()
			return
		end
		for _, key in ipairs(keys) do
			local header = item
			if key ~= itemID then
				header = ns.ItemInfoNow(itemID) and ("%s (item %s)"):format(item, tostring(key)) or ("item " .. tostring(key))
			end
			ns.Print(header .. ":")
			for _, house in ipairs(M.Houses(key)) do
				PrintHouse(key, house)
			end
		end
		printExport()
	end)
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
	db.names = db.names or {}
	db.itemInfo = db.itemInfo or {}
	db.auctionator = db.auctionator or {}
	db.auctionator.source = "auctionator"
	db.auctionator.house = M.AUCTIONATOR_HOUSE
	db.auctionator.label = ns.AUCTIONATOR_LABEL or "Auctionator (house unknown)"
	db.auctionator.items = db.auctionator.items or {}
end)

ns.Listen("RECIPES_CHANGED", M.RefreshScope)

ns.On("PLAYER_LOGIN", function()
	M.RefreshScope()
	ScanBags()
	M.Prune()
	C_Timer.NewTimer(AUCTIONATOR_LOGIN_DELAY, M.ExportAuctionatorScope)
	C_Timer.NewTimer(AUCTIONATOR_LOGIN_DELAY, function()
		M.FillItemInfo()
	end)
end)
-- Names first, as a normal handler; packing last (#105): handlers loaded after Market read prices at
-- logout (the snapshot values fishing catches), and a read unpacks the entry it touches.
ns.On("PLAYER_LOGOUT", function()
	pcall(FillNames)
end)
ns.OnLast("PLAYER_LOGOUT", PackAll)
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
	M.ExportAuctionatorScope() -- Auctionator's own scans during the visit changed its prices
	M.FillItemInfo() -- items a search or browse list added
end)
ns.On("GET_ITEM_INFO_RECEIVED", function(_, itemID, success)
	M.OnItemInfoReceived(itemID, success)
end)

ns.On("REPLICATE_ITEM_LIST_UPDATE", OnReplicateList)
ns.On("COMMODITY_SEARCH_RESULTS_UPDATED", OnCommoditySearch)
ns.On("COMMODITY_SEARCH_RESULTS_ADDED", OnCommoditySearch)
ns.On("ITEM_SEARCH_RESULTS_UPDATED", OnItemSearch)
ns.On("ITEM_SEARCH_RESULTS_ADDED", OnItemSearch)
ns.On("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", OnBrowseUpdated)
ns.On("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", OnBrowseAdded)
