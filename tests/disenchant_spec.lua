-- Disenchant values (#190): measured samples from Disenchantry's records (shaped exactly like
-- DisenchantryDB.disenchantSamples), pooled samples, the Classic guide, the salvager split and the value.
local PREFIX = "1.60.1:70938:"
local DUST, ESSENCE, SHARD = 10940, 10939, 10978
local SWORD, MACE, HELM = 5001, 5002, 5003

-- key = "<version>:<build>:<itemID>:<quality>:<baseItemLevel>:<classID>:<normal|salvager>"
local function Key(itemID, quality, level, class, mode, prefix)
	return ("%s%d:%d:%d:%d:%s"):format(prefix or PREFIX, itemID, quality, level, class, mode or "normal")
end

local function Load()
	local ns, stub = LoadAddon({ auctionator = true })
	GetBuildInfo = function() return "1.60.1", "70938" end
	assert(loadfile("CraftWise/Data/DisenchantGuide.lua"))("CraftWise", ns)
	stub.items[SWORD] = { name = "Green Sword", classID = 2, level = 20, quality = 2 }
	stub.items[MACE] = { name = "Green Mace", classID = 2, level = 18, quality = 2 }
	stub.items[HELM] = { name = "Green Helm", classID = 4, level = 18, quality = 2 }
	stub.ah[DUST], stub.ah[ESSENCE], stub.ah[SHARD] = 100, 400, 2000
	return ns, stub
end

local function Mat(total, hits, min, max)
	return { total = total, hits = hits, min = min, max = max }
end

it("record keys: parsed for this build only", function()
	local ns = Load()
	local D = ns.Disenchant
	eq(D.Prefix(), PREFIX)
	local id, quality, level, class, mode = D.ParseKey(Key(SWORD, 2, 20, 2, "salvager"), PREFIX)
	eq(id, SWORD); eq(quality, 2); eq(level, 20); eq(class, 2); eq(mode, "salvager")
	eq(D.ParseKey(Key(SWORD, 2, 20, 2, "normal", "1.60.0:70000:"), PREFIX), nil, "another build")
	eq(D.ParseKey("garbage", PREFIX), nil)
end)

it("measured: the item's own records add up, salvager ones stay apart, other builds and broken records are left out", function()
	local ns = Load()
	local D = ns.Disenchant
	local samples = {
		[Key(SWORD, 2, 20, 2)] = { count = 10, materials = { [DUST] = Mat(25, 8, 2, 4), [ESSENCE] = Mat(2, 2, 1, 1) } },
		[Key(SWORD, 2, 20, 2, "salvager")] = { count = 5, materials = { [DUST] = Mat(40, 5, 6, 10) } },
		[Key(SWORD, 2, 20, 2, "normal", "1.59.0:60000:")] = { count = 99, materials = { [DUST] = Mat(99, 99, 1, 1) } },
		[Key(MACE, 2, 22, 2)] = { count = 4, materials = { [DUST] = Mat(8, 4, 2, 2) } },
	}
	local item = { itemID = SWORD, quality = 2, level = 20, classID = 2 }
	local m = D.Measured(samples, PREFIX, "normal", item)
	eq(m.n, 10); eq(#m.mats, 2)
	eq(m.mats[1].itemID, ESSENCE); eq(m.mats[1].chance, 0.2) -- by item ID
	eq(m.mats[2].itemID, DUST); eq(m.mats[2].chance, 0.8); eq(m.mats[2].quantity, 2.5); eq(m.mats[2].perHit, 25 / 8)
	local s = D.Measured(samples, PREFIX, "salvager", item)
	eq(s.n, 5); eq(s.mats[1].quantity, 8)
	-- a record whose hits exceed its count is not read at all (as Disenchantry itself refuses it)
	samples[Key(SWORD, 2, 20, 2)].materials[DUST].hits = 11
	eq(D.Measured(samples, PREFIX, "normal", item), nil)
end)

it("pooled: records of other items of the same quality, class and level bracket", function()
	local ns = Load()
	local D = ns.Disenchant
	local samples = {
		[Key(MACE, 2, 22, 2)] = { count = 6, materials = { [DUST] = Mat(24, 6, 4, 4) } },
		[Key(5100, 2, 24, 2)] = { count = 4, materials = { [DUST] = Mat(20, 4, 5, 5) } },
		[Key(5101, 2, 30, 2)] = { count = 50, materials = { [DUST] = Mat(50, 50, 1, 1) } }, -- another bracket
		[Key(5102, 2, 23, 4)] = { count = 50, materials = { [DUST] = Mat(50, 50, 1, 1) } }, -- armour
		[Key(5103, 3, 23, 2)] = { count = 50, materials = { [DUST] = Mat(50, 50, 1, 1) } }, -- rare
	}
	local p = D.Pooled(samples, PREFIX, "normal", { itemID = SWORD, quality = 2, classID = 2 }, 21, 25)
	eq(p.n, 10); eq(p.mats[1].quantity, 4.4)
end)

it("guide: the Classic rows (armour and weapon chances, shard as the rest, rare and epic)", function()
	local ns = Load()
	local D, G = ns.Disenchant, ns.DisenchantGuide
	local g = D.Guide(G, { quality = 2, level = 18, classID = 4 }) -- armour 16-20: dust 75 %, essence 20 %, shard 5 %
	eq(g.lo, 16); eq(g.hi, 20); eq(#g.mats, 3)
	eq(g.mats[1].itemID, DUST); eq(g.mats[1].chance, 0.75); eq(g.mats[1].quantity, 0.75 * 2.5)
	eq(g.mats[2].itemID, ESSENCE); eq(g.mats[2].chance, 0.2); eq(g.mats[2].quantity, 0.2 * 1.5)
	eq(g.mats[3].itemID, SHARD); eq(g.mats[3].chance, 0.05); eq(g.mats[3].quantity, 0.05)
	g = D.Guide(G, { quality = 2, level = 18, classID = 2 }) -- weapon: 20 % dust, 75 % essence
	eq(g.mats[1].chance, 0.2); eq(g.mats[2].chance, 0.75)
	g = D.Guide(G, { quality = 2, level = 8, classID = 4 }) -- 5-15: no shard
	eq(#g.mats, 2)
	g = D.Guide(G, { quality = 3, level = 60, classID = 4 }) -- rare 56-80: 99.5 % / 0.5 %
	eq(#g.mats, 2); eq(g.mats[1].chance, 0.995)
	g = D.Guide(G, { quality = 4, level = 47, classID = 4 }) -- epic: 2-4 of one material
	eq(g.mats[1].quantity, 3)
	eq(D.Guide(G, { quality = 2, level = 200, classID = 4 }), nil, "no row for it: no guide, never extended")
	eq(D.Guide(G, { quality = 1, level = 10, classID = 4 }), nil)
end)

it("source order: measured, then pooled, then the labelled guide; few samples flagged; wands and other items excluded", function()
	local ns = Load()
	local D = ns.Disenchant
	local env = { samples = {}, prefix = PREFIX, mode = "normal", minSamples = 10, guide = ns.DisenchantGuide }
	local item = { itemID = SWORD, quality = 2, level = 20, classID = 2 }
	local r = D.Resolve(item, env)
	eq(r.source, "guide"); eq(r.label, "Classic table (guide)"); eq(D.ShortLabel(r), "guide")
	env.samples[Key(MACE, 2, 19, 2)] = { count = 12, materials = { [DUST] = Mat(24, 12, 2, 2) } }
	r = D.Resolve(item, env)
	eq(r.source, "pooled"); eq(r.n, 12); eq(r.few, false)
	assert(r.label:find("pooled, 12 disenchants", 1, true), r.label)
	env.samples[Key(SWORD, 2, 20, 2)] = { count = 3, materials = { [DUST] = Mat(9, 3, 3, 3) } }
	r = D.Resolve(item, env)
	eq(r.source, "measured"); eq(r.n, 3); eq(r.few, true); eq(D.ShortLabel(r), "few samples")
	eq(r.label, "measured, 3 disenchants")
	env.mode = "salvager" -- no salvager records of the item or its bracket: the guide, never the normal ones
	eq(D.Resolve(item, env).source, "guide")
	eq(D.Resolve({ itemID = 11287, quality = 2, level = 20, classID = 2 }, env), nil, "enchanter wand")
	eq(D.Resolve({ itemID = SWORD, quality = 1, level = 20, classID = 2 }, env), nil, "poor/common")
	eq(D.Resolve({ itemID = SWORD, quality = 2, level = 20, classID = 0 }, env), nil, "not armour or weapon")
end)

it("DisenchantValue: expected quantity x price after the cut, with the source and sample count", function()
	local ns = Load()
	DisenchantryDB = { disenchantSamples = {
		[Key(SWORD, 2, 20, 2)] = { count = 20, materials = { [DUST] = Mat(40, 20, 1, 4), [ESSENCE] = Mat(5, 5, 1, 1) } },
	} }
	local value, d = ns.DisenchantValue(SWORD, 2)
	-- per disenchant: 2 dust at 100 x 0.95 and 0.25 essence at 400 x 0.95
	eq(value, 2 * 95 + 0.25 * 380)
	eq(d.source, "measured"); eq(d.samples, 20); eq(d.few, false); eq(d.sourceLabel, "measured, 20 disenchants")
	eq(#d.materials, 2); eq(d.materials[2].itemID, DUST); eq(d.materials[2].unit, 95); eq(d.materials[2].from, "auction")
	-- another item of the bracket without records: pooled from these
	local v2, d2 = ns.DisenchantValue(MACE, 2)
	eq(d2.source, "pooled"); eq(v2, value)
	-- without Disenchantry's records the guide answers, labelled
	DisenchantryDB = nil
	local v3, d3 = ns.DisenchantValue(HELM, 2)
	eq(d3.source, "guide"); eq(d3.sourceLabel, "Classic table (guide)")
	eq(v3, 0.75 * 2.5 * 95 + 0.2 * 1.5 * 380 + 0.05 * 1.0 * 1900)
end)

it("DisenchantValue: no price for a material, or an unverified cut, is no value; a vendor price stands in when there is no AH price", function()
	local ns, stub = Load()
	DisenchantryDB = { disenchantSamples = {
		[Key(SWORD, 2, 20, 2)] = { count = 10, materials = { [DUST] = Mat(10, 10, 1, 1) } },
	} }
	stub.ah[DUST] = nil
	eq(ns.DisenchantValue(SWORD, 2), nil, "no price at all")
	stub.items[DUST] = { name = "Strange Dust", sellPrice = 7 }
	local value, d = ns.DisenchantValue(SWORD, 2)
	eq(value, 7); eq(d.materials[1].from, "vendor")
	eq(ns.DisenchantValue(99999, 2), nil, "item not in the client's cache")
end)

it("salvager: with the buff the salvager records answer, without it the normal ones", function()
	local ns = Load()
	DisenchantryDB = { disenchantSamples = {
		[Key(SWORD, 2, 20, 2)] = { count = 10, materials = { [DUST] = Mat(10, 10, 1, 1) } },
		[Key(SWORD, 2, 20, 2, "salvager")] = { count = 10, materials = { [DUST] = Mat(30, 10, 3, 3) } },
	} }
	eq(ns.Disenchant.SalvagerActive(), false)
	eq(ns.DisenchantValue(SWORD, 2), 95)
	C_UnitAuras = { GetPlayerAuraBySpellID = function(id) return id == 1283701 and { spellId = id } or nil end }
	eq(ns.Disenchant.SalvagerActive(), true)
	eq(ns.DisenchantValue(SWORD, 2), 3 * 95)
end)
