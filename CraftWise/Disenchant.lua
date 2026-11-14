-- Disenchant values (#190): what disenchanting an item is expected to give, from the best source there is,
-- always labelled with which one:
--   1. measured: the item's own samples in Disenchantry's records (DisenchantryDB.disenchantSamples,
--      account wide, recorded on Forever only; read only, never written). A key is
--      "<version>:<build>:<itemID>:<quality>:<baseItemLevel>:<classID>:<normal|salvager>" and holds
--      { count, materials = { [materialID] = { total, hits, min, max } } }. Only samples of the running
--      client version and build count. "salvager" samples (Arcane Salvager buff 1283701 raises yields) are
--      kept apart: normal ones are used unless the buff is active.
--   2. pooled: no samples of the item itself: the samples of every item of the same quality, class
--      (armour/weapon) and item-level bracket of the guide's rows, with their sum of disenchants.
--   3. guide: the Classic baseline table (Data/DisenchantGuide.lua, from Disenchantry's Classic rows),
--      "Classic table (guide)". Disenchantry's Forever estimates (guess=true) are not used.
-- Measured and pooled values below Settings' minimum number of disenchants are marked "few samples".
-- Expected value = sum over materials of (expected quantity per disenchant x price); an unknown price or an
-- unverified AH cut gives no value (never understated). Pure parts take plain data (Resolve, Measured,
-- Pooled, Guide, Aggregate); ns.DisenchantValue wires them to the client and the prices.
local _, ns = ...

local D = {}
ns.Disenchant = D

D.DEFAULT_MIN_SAMPLES = 10
D.SALVAGER_AURA = 1283701
D.GUIDE_LABEL = "Classic table (guide)"

function D.MinSamples()
	local n = ns.db and tonumber(ns.db.settings.disenchantMinSamples)
	return n and math.max(1, math.floor(n)) or D.DEFAULT_MIN_SAMPLES
end

----------------------------------------------------------------------------------------------------
-- Disenchantry's records
----------------------------------------------------------------------------------------------------

-- The sample table, nil when Disenchantry has none (not installed, not loaded, nothing recorded yet).
function D.Samples()
	local db = DisenchantryDB
	local samples = type(db) == "table" and db.disenchantSamples
	return type(samples) == "table" and samples or nil
end

-- "1.60.1:70938:" of the running client; samples of other builds are not read.
function D.Prefix()
	local version, build = "", ""
	if GetBuildInfo then
		version, build = GetBuildInfo()
	end
	return tostring(version or "") .. ":" .. tostring(build or "") .. ":"
end

function D.SalvagerActive()
	if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
		local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, D.SALVAGER_AURA)
		return ok and type(aura) == "table"
	end
	return false
end

-- A record key of this build: itemID, quality, level, classID, mode; nil for others.
function D.ParseKey(key, prefix)
	if type(key) ~= "string" or key:sub(1, #prefix) ~= prefix then
		return nil
	end
	local id, quality, level, class, mode = key:sub(#prefix + 1):match("^(%d+):(%d+):(%d+):(%d+):(%a+)$")
	if not id then
		return nil
	end
	return tonumber(id), tonumber(quality), tonumber(level), tonumber(class), mode
end

-- A record that is readable: counts and materials consistent, as Disenchantry itself checks them.
local function Valid(sample)
	if type(sample) ~= "table" or type(sample.count) ~= "number" or sample.count < 1 or type(sample.materials) ~= "table" then
		return false
	end
	for id, m in pairs(sample.materials) do
		if not (type(id) == "number" and type(m) == "table" and type(m.hits) == "number" and m.hits > 0
			and m.hits <= sample.count and type(m.total) == "number" and m.total > 0) then
			return false
		end
	end
	return true
end

-- Adds the records for which keep(itemID, quality, level, class) is true up: { n, mats = { { itemID, chance
-- (0..1), quantity (expected per disenchant), perHit (mean quantity when it drops), min, max } } by itemID }
-- or nil without a record.
function D.Aggregate(samples, prefix, mode, keep)
	local n, sums = 0, {}
	for key, sample in pairs(samples or {}) do
		local id, quality, level, class, m = D.ParseKey(key, prefix)
		if id and m == mode and Valid(sample) and keep(id, quality, level, class) then
			n = n + sample.count
			for mat, d in pairs(sample.materials) do
				local s = sums[mat] or { total = 0, hits = 0, min = d.min or d.total, max = d.max or d.total }
				s.total, s.hits = s.total + d.total, s.hits + d.hits
				s.min, s.max = math.min(s.min, d.min or s.min), math.max(s.max, d.max or s.max)
				sums[mat] = s
			end
		end
	end
	if n == 0 then
		return nil
	end
	local mats = {}
	for mat, s in pairs(sums) do
		mats[#mats + 1] = { itemID = mat, chance = s.hits / n, quantity = s.total / n, perHit = s.total / s.hits, min = s.min, max = s.max }
	end
	table.sort(mats, function(a, b) return a.itemID < b.itemID end)
	return { n = n, mats = mats }
end

-- item = { itemID, quality, level, classID }
function D.Measured(samples, prefix, mode, item)
	return D.Aggregate(samples, prefix, mode, function(id, quality, level, class)
		return id == item.itemID and quality == item.quality and level == item.level and class == item.classID
	end)
end

function D.Pooled(samples, prefix, mode, item, lo, hi)
	return D.Aggregate(samples, prefix, mode, function(_, quality, level, class)
		return quality == item.quality and class == item.classID and level >= lo and level <= hi
	end)
end

----------------------------------------------------------------------------------------------------
-- The guide (Classic table)
----------------------------------------------------------------------------------------------------

local function RowFor(rows, level)
	for _, row in ipairs(rows or {}) do
		if level >= row[1] and level <= row[2] then
			return row
		end
	end
end

-- Materials of the guide for the item, and the item-level bracket of its row: { mats, lo, hi } or nil.
-- mats are shaped like the measured ones (chance 0..1, quantity per disenchant, perHit).
function D.Guide(guide, item)
	if not guide or not item.level or item.level <= 0 then
		return nil
	end
	local mats = {}
	local function add(id, chance, minQ, maxQ)
		local per = (minQ + maxQ) / 2 -- a range has no probabilities of its own: its middle
		mats[#mats + 1] = { itemID = id, chance = chance, quantity = chance * per, perHit = per, min = minQ, max = maxQ }
	end
	local row
	if item.quality == 2 then
		row = RowFor(guide.uncommon, item.level)
		if not row then
			return nil
		end
		local weapon = item.classID == 2
		local dust, essence = row[weapon and 8 or 6], row[weapon and 9 or 7]
		add(row[3], dust / 100, row[10], row[11])
		add(row[4], essence / 100, row[12], row[13])
		if row[5] then
			add(row[5], (100 - dust - essence) / 100, 1, 1)
		end
	elseif item.quality == 3 then
		row = RowFor(guide.rare, item.level)
		if not row then
			return nil
		end
		if row[4] then
			add(row[3], 0.995, 1, 1)
			add(row[4], 0.005, 1, 1)
		else
			add(row[3], 1, 1, 1)
		end
	elseif item.quality == 4 then
		row = RowFor(guide.epic, item.level)
		if not row then
			return nil
		end
		add(row[3], 1, row[4], row[5])
	else
		return nil
	end
	return { mats = mats, lo = row[1], hi = row[2] }
end

----------------------------------------------------------------------------------------------------
-- Which source answers
----------------------------------------------------------------------------------------------------

function D.Excluded(itemID)
	local guide = ns.DisenchantGuide
	return guide and guide.excluded and guide.excluded[itemID] or false
end

-- Uncommon to epic armour or weapon that isn't an enchanter wand, with the data to look it up.
function D.Can(itemID, quality, classID)
	if not (quality == 2 or quality == 3 or quality == 4) or not (classID == 2 or classID == 4) then
		return false
	end
	return not D.Excluded(itemID)
end

-- item = { itemID, quality, level, classID }; env = { samples, prefix, mode, minSamples, guide }.
-- Returns { source = "measured"|"pooled"|"guide", n, mats, few, label, lo, hi } or nil.
function D.Resolve(item, env)
	if not (item and D.Can(item.itemID, item.quality, item.classID)) then
		return nil
	end
	local min = env.minSamples or D.DEFAULT_MIN_SAMPLES
	local guide = D.Guide(env.guide, item)
	local m = env.samples and D.Measured(env.samples, env.prefix, env.mode, item)
	if m then
		return { source = "measured", n = m.n, mats = m.mats, few = m.n < min,
			label = ("measured, %d %s"):format(m.n, m.n == 1 and "disenchant" or "disenchants") }
	end
	if env.samples and guide then
		local p = D.Pooled(env.samples, env.prefix, env.mode, item, guide.lo, guide.hi)
		if p then
			return { source = "pooled", n = p.n, mats = p.mats, few = p.n < min, lo = guide.lo, hi = guide.hi,
				label = ("pooled, %d %s of items of the same quality and type, item level %d-%d"):format(p.n,
					p.n == 1 and "disenchant" or "disenchants", guide.lo, guide.hi) }
		end
	end
	if guide then
		return { source = "guide", n = 0, mats = guide.mats, few = false, lo = guide.lo, hi = guide.hi, label = D.GUIDE_LABEL }
	end
	return nil
end

-- Short word for captions: "14 samples", "few samples", "pooled 85", "guide".
function D.ShortLabel(r)
	if not r then
		return nil
	end
	if r.source == "guide" then
		return "guide"
	end
	if r.few then
		return "few samples"
	end
	return r.source == "pooled" and ("pooled " .. r.n) or (r.n .. " samples")
end

----------------------------------------------------------------------------------------------------
-- Wiring: the client and the prices
----------------------------------------------------------------------------------------------------

local function ItemFacts(itemID, quality)
	local info = C_Item and C_Item.GetItemInfo
	if not info then
		return nil
	end
	local _, _, q, level, _, _, _, _, _, _, _, classID = info(itemID)
	if not (level and classID) then
		return nil -- not in the client's cache yet
	end
	return { itemID = itemID, quality = quality or q, level = level, classID = classID }
end
D.ItemFacts = ItemFacts

function D.Env()
	return { samples = D.Samples(), prefix = D.Prefix(), mode = D.SalvagerActive() and "salvager" or "normal",
		minSamples = D.MinSamples(), guide = ns.DisenchantGuide }
end

-- The source for an item (see Resolve), or nil.
function D.Source(itemID, quality)
	local facts = ItemFacts(itemID, quality)
	if not facts then
		return nil
	end
	return D.Resolve(facts, D.Env())
end

-- One material's value in copper when sold: the AH at the profit house after its measured cut, else what a
-- vendor pays; nil without a price or when the cut is unverified (that would understate it).
local function MaterialValue(id, details, seen)
	local sale = ns.AuctionSale(id, 1)
	if sale then
		if not sale.cut then
			return nil
		end
		details.cutDiffers = details.cutDiffers or sale.cutDiffers
		for kind, text in pairs({ labels = sale.label, cutTexts = sale.cutText }) do
			if text and not seen[kind .. text] then
				seen[kind .. text] = true
				table.insert(details[kind], text)
			end
		end
		return sale.quote.copper * (1 - sale.cut), "auction"
	end
	local vendor = ns.GetVendorSellPrice(id)
	if vendor and vendor > 0 then
		return vendor, "vendor"
	end
	return nil
end

-- Expected value of one item of itemID (see the file header) and the details { labels, cutTexts, cutDiffers,
-- source, sourceLabel, samples, few, materials = { { itemID, chance, quantity, perHit, unit, from } } };
-- nil when there is no source or a material has no price.
function ns.DisenchantValue(itemID, quality)
	local result
	if ns.DisenchantData and ns.DisenchantData.Lookup then -- a verified table, when one exists (#11)
		local facts = ItemFacts(itemID, quality)
		local rows = facts and ns.DisenchantData.Lookup(quality, facts.level)
		if rows then
			local mats = {}
			for i, r in ipairs(rows) do
				mats[i] = { itemID = r.itemID, chance = r.chance, quantity = r.chance * r.quantity, perHit = r.quantity }
			end
			result = { source = "table", n = 0, mats = mats, few = false, label = "verified table" }
		end
	end
	result = result or D.Source(itemID, quality)
	if not result then
		return nil
	end
	local total, details, seen = 0, { labels = {}, cutTexts = {}, materials = {} }, {}
	for _, m in ipairs(result.mats) do
		local unit, from = MaterialValue(m.itemID, details, seen)
		if not unit then
			return nil -- a material without a price or a cut would understate the value
		end
		total = total + unit * m.quantity
		details.materials[#details.materials + 1] = { itemID = m.itemID, chance = m.chance, quantity = m.quantity,
			perHit = m.perHit, min = m.min, max = m.max, unit = unit, from = from }
	end
	details.source, details.sourceLabel, details.samples, details.few = result.source, result.label, result.n, result.few
	return total, details
end

-- Make › Craft: what the product of a row would be worth disenchanted, and the profit over its reagents.
-- Sets r.deValue (per craft: expected value of one item x the output quantity), r.deDetails, r.deProfit
-- (nil without a complete reagent cost), r.deShort. Rows whose product can't be disenchanted get none.
function D.RowValue(r)
	r.deValue, r.deDetails, r.deProfit, r.deShort = nil, nil, nil, nil
	local id = r.outputItemID
	if not id then
		return r
	end
	local facts = ItemFacts(id)
	if not (facts and D.Can(id, facts.quality, facts.classID)) then
		return r
	end
	local value, details = ns.DisenchantValue(id, facts.quality)
	if not value then
		return r
	end
	r.deValue = value * (r.outputQuantity or 1)
	r.deDetails = details
	r.deShort = D.ShortLabel({ source = details.source, few = details.few, n = details.samples })
	if r.costComplete then
		r.deProfit = r.deValue - r.cost
	end
	return r
end
