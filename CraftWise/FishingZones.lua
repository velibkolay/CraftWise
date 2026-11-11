-- Fishing zones ranked by value per catch (issue #88): own catches (#69/#86) and an optional local reference.
--
-- Two sources per zone, every row says which one it shows:
--   * own: the fishing log's tables (FishingTables.lua, F.Tables): catches, items caught, timed catches.
--   * reference: the local addon CraftWise_FishingRef (not in the repo; built on Veli's PC by
--     tools/fishing_ref.py from saved pages, docs/fishing-reference.md). Its global CraftWise_FishingRef holds
--     per zone how often each item was recorded out of all recorded fishing loots, and the stack range.
--   Own data wins once a zone has settings.fishingOwnMin catches (default 50, `/craftwise fishing ownmin <n>`);
--   below that the reference shows when it has the zone, else the small own sample with its n.
--   Zones are matched by name (the reference's zone IDs are not the client's map IDs), so the pages must be in
--   the client's language.
--
-- Per item: chance = reference count / total (or the item's own outof); own: units caught per catch. Units per
-- catch = chance x stack; a stack range gives a low and a high value (the reference has no mean stack), the
-- ranking uses the low one. Unit value: containers (trunks, crates, clams) by the mean of their contents, own
-- openings first (at least OWN_MIN_OPENED, or any when the reference doesn't have the container), else the
-- reference's `contains` table; everything else by ns.GetSellValue (AH typical/current at the profit house
-- after the cut, else vendor, labelled). Items without a price are left out of the sums and counted.
-- Value per hour: own catches per hour in the zone (timed catches, FishingTables sessions) x value per catch.
local _, ns = ...

local Z = {}
ns.FishingZones = Z

Z.OWN_MIN = 50 -- default of settings.fishingOwnMin
Z.OWN_MIN_OPENED = 5
Z.MAX_DEPTH = 2 -- containers inside containers
Z.SNAP_ZONES = 5

local function Lower(s)
	return type(s) == "string" and s:lower() or ""
end

function Z.OwnMin()
	local s = ns.db and ns.db.settings
	local n = s and tonumber(s.fishingOwnMin)
	return n and n >= 1 and math.floor(n) or Z.OWN_MIN
end

-- The reference addon's table, or nil when it isn't loaded or doesn't look like one.
function Z.Reference()
	local ref = _G.CraftWise_FishingRef
	if type(ref) ~= "table" or type(ref.zones) ~= "table" then
		return nil
	end
	return ref
end

----------------------------------------------------------------------------------------------------
-- Unit values
----------------------------------------------------------------------------------------------------

-- Own openings per container: { [containerID] = { n, units = { [itemID] = units } } }.
local function OwnOpenings(log)
	local out = {}
	for _, o in ipairs(log and log.opened or {}) do
		if o.item then
			local c = out[o.item]
			if not c then
				c = { n = 0, units = {} }
				out[o.item] = c
			end
			c.n = c.n + 1
			for itemID, count in pairs(o.items or {}) do
				c.units[itemID] = (c.units[itemID] or 0) + count
			end
		end
	end
	return out
end

local function SellValue(itemID)
	local value = ns.GetSellValue and ns.GetSellValue(itemID)
	if value and value.copper and value.copper > 0 then
		local label = value.label or value.source
		if value.cutUnverified then
			label = label .. ", cut unverified"
		end
		return { copper = math.floor(value.copper), high = math.floor(value.copper), label = label, source = value.source }
	end
	return nil
end

-- Chance of a reference row: count out of its own outof, else the table's total.
local function RefChance(item, total)
	local outof = tonumber(item.outof) or tonumber(total)
	local count = tonumber(item.count)
	if not (outof and outof > 0 and count) then
		return nil
	end
	return count / outof, outof
end

local function Stack(item)
	local s = item.stack
	if type(s) == "table" and tonumber(s[1]) and tonumber(s[2]) then
		return tonumber(s[1]), tonumber(s[2]), true
	end
	return 1, 1, false -- not given: one per drop as the floor, flagged
end

-- ctx = { ref, opened = OwnOpenings, cache }.
local function NewContext(log)
	return { ref = Z.Reference(), opened = OwnOpenings(log), cache = {} }
end

local UnitValue

-- Value of what one opening gives, from a list of { itemID, perOpen (low), perOpenHigh }.
local function ContentsSum(ctx, lines, depth)
	local low, high, unpriced = 0, 0, 0
	for _, line in ipairs(lines) do
		local u = UnitValue(ctx, line.itemID, depth + 1)
		if u then
			low, high = low + line.low * u.copper, high + line.high * (u.high or u.copper)
		else
			unpriced = unpriced + 1
		end
	end
	return math.floor(low), math.floor(high), unpriced
end

-- Contents value of a container, or nil when no contents table is known.
local function ContentsValue(ctx, itemID, depth)
	if depth >= Z.MAX_DEPTH then
		return nil
	end
	local own = ctx.opened[itemID]
	local refBox = ctx.ref and type(ctx.ref.containers) == "table" and ctx.ref.containers[itemID] or nil
	if own and (own.n >= Z.OWN_MIN_OPENED or not refBox) then
		local lines = {}
		for id, units in pairs(own.units) do
			lines[#lines + 1] = { itemID = id, low = units / own.n, high = units / own.n }
		end
		local low, high, unpriced = ContentsSum(ctx, lines, depth)
		return { copper = low, high = high, unpriced = unpriced, container = "own", n = own.n,
			label = ("contents of %d opened"):format(own.n), lines = lines }
	end
	if type(refBox) == "table" and type(refBox.items) == "table" then
		local lines, ranged = {}, false
		for _, item in ipairs(refBox.items) do
			local chance = RefChance(item, refBox.total)
			if chance and tonumber(item.id) then
				local a, b, known = Stack(item)
				ranged = ranged or a ~= b or not known
				lines[#lines + 1] = { itemID = tonumber(item.id), low = chance * a, high = chance * b, chance = chance,
					stack = known and { a, b } or nil, name = item.name }
			end
		end
		local low, high, unpriced = ContentsSum(ctx, lines, depth)
		return { copper = low, high = high, unpriced = unpriced, container = "ref", n = tonumber(refBox.total),
			label = ("reference contents, n = %s"):format(tostring(refBox.total or "?")), lines = lines, ranged = ranged }
	end
	return nil
end

-- { copper (low), high, label, container = "own"|"ref"|nil, n, unpriced, lines, sell } or nil (no price data).
UnitValue = function(ctx, itemID, depth)
	depth = depth or 0
	local key = itemID .. ":" .. depth
	if ctx.cache[key] ~= nil then
		return ctx.cache[key] or nil
	end
	local value = ContentsValue(ctx, itemID, depth)
	if value then
		value.sell = SellValue(itemID) -- what it sells for unopened, for the tooltip
	else
		value = SellValue(itemID)
	end
	ctx.cache[key] = value or false
	return value
end

function Z.UnitValue(itemID, log)
	return UnitValue(NewContext(log or (ns.Fishing and ns.Fishing.Log())), itemID, 0)
end

----------------------------------------------------------------------------------------------------
-- Zones
----------------------------------------------------------------------------------------------------

-- Items (sorted by value per catch) and totals for one source.
-- lines = { { itemID, name, chance, n, outof, low (units per catch), high, stack, stackKnown } }
local function Valued(ctx, lines)
	local low, high, unpriced = 0, 0, 0
	for _, line in ipairs(lines) do
		local u = UnitValue(ctx, line.itemID, 0)
		line.unit = u
		if u then
			line.perCatch = math.floor(line.low * u.copper + 0.5)
			line.perCatchHigh = math.floor(line.high * (u.high or u.copper) + 0.5)
			low, high = low + line.low * u.copper, high + line.high * (u.high or u.copper)
		else
			unpriced = unpriced + 1
		end
		line.unitValue = u and u.copper or nil
		line.fishChance = line.chance
	end
	table.sort(lines, function(a, b)
		local va, vb = a.perCatch or -1, b.perCatch or -1
		if va ~= vb then
			return va > vb
		end
		if a.chance ~= b.chance then
			return (a.chance or 0) > (b.chance or 0)
		end
		return a.itemID < b.itemID
	end)
	return math.floor(low + 0.5), math.floor(high + 0.5), unpriced
end

local function RefSide(ctx, zone)
	local lines = {}
	local total = tonumber(zone.total)
	for _, item in ipairs(type(zone.items) == "table" and zone.items or {}) do
		local chance, outof = RefChance(item, total)
		if chance and tonumber(item.id) then
			local a, b, known = Stack(item)
			lines[#lines + 1] = { itemID = tonumber(item.id), name = item.name, chance = chance, n = tonumber(item.count),
				outof = outof, low = chance * a, high = chance * b, stack = known and { a, b } or nil, stackKnown = known }
		end
	end
	local low, high, unpriced = Valued(ctx, lines)
	return { source = "ref", n = total or 0, perCatch = low, perCatchHigh = high, unpriced = unpriced, items = lines,
		refID = tonumber(zone.id) }
end

-- Own side of one zone from the FishingTables zone: items aggregated over its subzones and water types.
local function OwnSide(ctx, z)
	local units, timed, seconds, water = {}, 0, 0, {}
	for _, s in ipairs(z.subs or {}) do
		for _, r in ipairs(s.rows or {}) do
			for _, item in ipairs(r.items or {}) do
				units[item.itemID] = (units[item.itemID] or 0) + item.count
			end
			timed, seconds = timed + (r.timed or 0), seconds + (r.seconds or 0)
			water[#water + 1] = r
		end
	end
	local lines = {}
	for itemID, count in pairs(units) do
		local per = count / z.catches
		lines[#lines + 1] = { itemID = itemID, chance = per, n = count, outof = z.catches, low = per, high = per, own = true }
	end
	local low, high, unpriced = Valued(ctx, lines)
	-- Water types (open water, each pool) with this view's unit values.
	local waters = {}
	for _, r in ipairs(water) do
		local v, u = 0, 0
		for _, item in ipairs(r.items or {}) do
			local value = UnitValue(ctx, item.itemID, 0)
			if value then
				v = v + value.copper * item.count
			else
				u = u + 1
			end
		end
		waters[#waters + 1] = { label = ns.Fishing.RowLabel and ns.Fishing.RowLabel(r) or r.water, sub = r.sub,
			water = r.water, obj = r.obj, n = r.catches, perCatch = math.floor(v / r.catches + 0.5), unpriced = u }
	end
	table.sort(waters, function(a, b)
		if a.n ~= b.n then
			return a.n > b.n
		end
		return (a.label or "") < (b.label or "")
	end)
	return { source = "own", n = z.catches, perCatch = low, perCatchHigh = high, unpriced = unpriced, items = lines,
		timed = timed, seconds = seconds, waters = waters,
		rate = seconds > 0 and timed > 0 and (timed * 3600 / seconds) or nil }
end

-- Which side a zone shows: own with enough catches (or no reference), else the reference, else the small own sample.
local function Choose(own, ref, min)
	if own and (own.n >= min or not ref) then
		return own
	end
	return ref or own
end

-- All zones from both sources, ranked by value per catch (low end), best first.
-- opts = { filter = zone name part (any case), key = character key, prefer = "own"|"ref" (force a side) }
-- { zones = { zone }, ref = reference loaded?, refGenerated, own = catches, ownMin, days }
-- zone = { name, key, source, n, perCatch, perCatchHigh, perHour, unpriced, items, own = side|nil, ref = side|nil,
--   rate, timed, top }
function Z.Rank(opts)
	opts = opts or {}
	local F = ns.Fishing
	local t = F and F.Tables and F.Tables({ key = opts.key }) or nil
	local log = F and F.Log and F.Log(opts.key) or nil
	local ctx = NewContext(log)
	local min = Z.OwnMin()
	local byKey, zones = {}, {}
	local function entry(name)
		local key = Lower(name)
		local z = byKey[key]
		if not z then
			z = { name = name, key = key }
			byKey[key] = z
			zones[#zones + 1] = z
		end
		return z
	end
	for _, z in ipairs(t and t.zones or {}) do
		if z.catches > 0 then
			entry(z.zone).own = OwnSide(ctx, z)
		end
	end
	for _, rz in ipairs(ctx.ref and ctx.ref.zones or {}) do
		if type(rz) == "table" and type(rz.name) == "string" and rz.name ~= "" then
			local z = entry(rz.name)
			local side = RefSide(ctx, rz)
			if not z.ref or side.n > z.ref.n then
				z.ref = side
			end
		end
	end
	local filter = opts.filter and opts.filter ~= "" and Lower(opts.filter) or nil
	local out = {}
	for _, z in ipairs(zones) do
		if not filter or z.key:find(filter, 1, true) then
			local side = opts.prefer and z[opts.prefer] or Choose(z.own, z.ref, min)
			z.side = side
			z.source, z.sample, z.n = side.source, side.n, side.n
			z.perCatch, z.perCatchHigh, z.unpriced, z.items = side.perCatch, side.perCatchHigh, side.unpriced, side.items
			-- Value per hour: own catching speed in this zone x the shown value per catch.
			if z.own and z.own.rate then
				z.rate, z.timed = z.own.rate, z.own.timed
				z.perHour = math.floor(z.own.rate * z.perCatch + 0.5)
			end
			local top = {}
			for i = 1, math.min(3, #z.items) do
				top[i] = z.items[i]
			end
			z.top = top
			z.topCatches = top[1] and top[1].perCatch or nil
			out[#out + 1] = z
		end
	end
	table.sort(out, function(a, b)
		if a.perCatch ~= b.perCatch then
			return a.perCatch > b.perCatch
		end
		return a.key < b.key
	end)
	return { zones = out, ref = ctx.ref ~= nil, refGenerated = ctx.ref and ctx.ref.generated or nil,
		own = t and t.catches or 0, ownMin = min, days = t and t.days or (F and F.KEEP_DAYS) }
end

-- One zone by name (any case), or nil.
function Z.Zone(name, opts)
	local key = Lower(name)
	local o = {}
	for k, v in pairs(opts or {}) do
		o[k] = v
	end
	local rank = Z.Rank(o)
	for _, z in ipairs(rank.zones) do
		if z.key == key then
			return z, rank
		end
	end
	return nil, rank
end

function Z.SourceText(z)
	if z.source == "own" then
		return ("own catches, n = %d"):format(z.n)
	end
	return ("reference, n = %d"):format(z.n)
end

----------------------------------------------------------------------------------------------------
-- Snapshot (#63) and /craftwise fishing zones
----------------------------------------------------------------------------------------------------

-- Top zones for the character snapshot: plain data, small.
function Z.SnapshotRanking()
	local rank = Z.Rank()
	local out = { reference = rank.ref, ownMin = rank.ownMin, zones = {} }
	for i = 1, math.min(#rank.zones, Z.SNAP_ZONES) do
		local z = rank.zones[i]
		out.zones[i] = { zone = z.name, source = z.source, n = z.n, perCatch = z.perCatch,
			perCatchHigh = z.perCatchHigh ~= z.perCatch and z.perCatchHigh or nil, perHour = z.perHour,
			unpriced = z.unpriced > 0 and z.unpriced or nil }
	end
	if #rank.zones > Z.SNAP_ZONES then
		out.more = #rank.zones - Z.SNAP_ZONES
	end
	return out
end

local function Money(copper)
	return ns.FormatMoney and ns.FormatMoney(copper) or (tostring(copper) .. "c")
end

function Z.ValueText(low, high)
	if high and high > low then
		return Money(low) .. " - " .. Money(high)
	end
	return Money(low)
end

function Z.Slash(arg)
	arg = arg or ""
	local rank = Z.Rank({ filter = arg })
	if #rank.zones == 0 then
		ns.Print(rank.ref and ("No fishing zone matches \"%s\"."):format(arg)
			or "No own catches yet and no local reference loaded (CraftWise_FishingRef, see docs/fishing-reference.md).")
		return
	end
	ns.Print(("Fishing zones by value per catch. Own catches count from n = %d (/craftwise fishing ownmin <n>), else the local reference%s."):format(
		rank.ownMin, rank.ref and "" or " (not loaded)"))
	local ids = {}
	for _, z in ipairs(rank.zones) do
		for _, item in ipairs(z.top) do
			ids[#ids + 1] = item.itemID
		end
	end
	ns.WithItemNames(ids, function()
		for i, z in ipairs(rank.zones) do
			local parts = { ("%d. %s: %s per catch (%s)"):format(i, z.name, Z.ValueText(z.perCatch, z.perCatchHigh), Z.SourceText(z)) }
			if z.unpriced > 0 then
				parts[#parts + 1] = ("%d items without price left out"):format(z.unpriced)
			end
			if z.perHour then
				parts[#parts + 1] = ("%s per hour (%d catches/hour, own timed n = %d)"):format(Money(z.perHour), math.floor(z.rate + 0.5), z.timed)
			end
			local other = z.source == "own" and z.ref or z.source == "ref" and z.own or nil
			if other then
				parts[#parts + 1] = ("%s: %s"):format(other.source == "own" and ("own n = %d"):format(other.n)
					or ("reference n = %d"):format(other.n), Z.ValueText(other.perCatch, other.perCatchHigh))
			end
			ns.Print(table.concat(parts, "; "))
			local top = {}
			for _, item in ipairs(z.top) do
				top[#top + 1] = ("%s %d%%"):format(ns.ItemChatText(item.itemID, { name = item.name }), math.floor(item.chance * 100 + 0.5))
			end
			if #top > 0 then
				ns.Print("    " .. table.concat(top, ", "))
			end
		end
	end)
end

function Z.SetOwnMin(arg)
	local n = tonumber(arg)
	if not n or n < 1 then
		ns.Print(("Own catches count from n = %d. Change it with /craftwise fishing ownmin <catches>."):format(Z.OwnMin()))
		return
	end
	if ns.db then
		ns.db.settings.fishingOwnMin = math.floor(n)
	end
	ns.Print(("Fishing zones: own catches count from n = %d, below that the reference shows."):format(Z.OwnMin()))
	if ns.RefreshProfitFrame then
		ns.RefreshProfitFrame()
	end
end
