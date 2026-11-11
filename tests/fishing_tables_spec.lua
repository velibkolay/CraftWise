-- Issue #86: fishing loot tables from own catches - pool or open water from what the client shows, pool
-- names, positions, value per catch and per hour, pool visits, sightings, Find Fish, /craftwise fishing
-- filters, snapshot ranking. Item and object IDs are stub data, not real ones (except Find Fish, 43308,
-- taken from Blizzard's Forever UI source).
local NOW = 1794000000
local FISH, OIL, BOOT, CRATE = 9001, 9002, 9003, 9004
local BOBBER, SCHOOL, WRECK = 5001, 6001, 6002

local function guid(id, spawn) return ("GameObject-0-1-2-3-%d-%s"):format(id, spawn) end

local function setup(opts)
	opts = opts or {}
	local ns, stub = LoadAddon(opts)
	stub.clock, stub.now = NOW, 1000
	time = function() return stub.clock end
	stub.names.player, stub.realm = "Veli", "Forever-EU"
	stub.zone, stub.subzone = "Stranglethorn Vale", "Nek'mani Wellspring"
	stub.mapID, stub.pos = 1434, { x = 0.25432, y = 0.6 }
	C_Map = {
		GetBestMapForUnit = function(unit) return unit == "player" and stub.mapID or nil end,
		GetPlayerMapPosition = function(map, unit)
			if map == stub.mapID and unit == "player" and stub.pos then return { x = stub.pos.x, y = stub.pos.y } end
		end,
	}
	IsFishingLoot = function() return true end
	ns.db.settings.fastLoot = false
	stub.tracking = {}
	stub.known = {}
	C_SpellBook = { IsSpellKnown = function(id) return stub.known[id] == true end }
	C_Minimap = {
		GetNumTrackingTypes = function() return #stub.tracking end,
		GetTrackingInfo = function(i) return stub.tracking[i] end,
	}
	TooltipDataProcessor = { AddTooltipPostCall = function(kind, fn) stub.tipHooks = stub.tipHooks or {}; stub.tipHooks[kind] = fn end }
	Enum.TooltipDataType = { Item = 0, Object = 4 }
	GetLootSlotInfo = function(i)
		local s = stub.loot[i]
		if not s or not s.link then return nil end
		return "tex", "name", s.qty or 1, nil, 1, false, false, nil, nil, false
	end
	stub.items[FISH] = { name = "Test Fish", sellPrice = 6 }
	stub.items[OIL] = { name = "Test Oil", sellPrice = 20 }
	stub.items[BOOT] = { name = "Test Boot" }
	stub.items[CRATE] = { name = "Test Crate" }
	stub.printed = {}
	ns.Print = function(m) stub.printed[#stub.printed + 1] = m end
	stub.Fire("PLAYER_LOGIN")
	return ns, stub
end

-- One catch: `after` seconds after the previous one, from source GUID `src`, the player having clicked
-- `clicked` (mouseover GUID; nil = the client showed none).
local function catch(stub, after, src, clicked, items)
	stub.clock, stub.now = stub.clock + (after or 0), stub.now + (after or 0)
	stub.guids.mouseover = clicked
	local loot = {}
	for itemID, qty in pairs(items or { [FISH] = 1 }) do
		loot[#loot + 1] = { link = "item:" .. itemID, qty = qty, sources = src and { src, qty } or nil }
	end
	table.sort(loot, function(a, b) return a.link < b.link end)
	stub.loot = loot
	stub.Fire("LOOT_READY", false)
	stub.Fire("LOOT_OPENED", false, false)
	stub.Fire("LOOT_CLOSED")
	stub.guids.mouseover = nil
end

local function tip(stub, name, g)
	stub.tipHooks[4](GameTooltip, { type = 4, guid = g, lines = { { leftText = name } } })
end

local function log(ns) return ns.db.fishing["Forever-EU-Veli"] end
local function printed(stub) return table.concat(stub.printed, "\n") end
local function has(text, s) assert(text:find(s, 1, true), ("missing %q in:\n%s"):format(s, text)) end
local function row(t, water, obj)
	for _, r in ipairs(t.rows) do
		if r.water == water and r.obj == obj then return r end
	end
end

it("stores position, source spawn and the clicked object on every catch", function()
	local ns, stub = setup()
	catch(stub, 0, guid(BOBBER, "00000A1"), guid(BOBBER, "00000A1"))
	local c = log(ns).catches[1]
	eq(c.x, 25.4); eq(c.y, 60); eq(c.map, 1434)
	eq(c.obj, BOBBER); eq(c.spawn, "00000A1"); eq(c.clk, BOBBER); eq(c.same, true)
	stub.pos = nil
	catch(stub, 30, guid(SCHOOL, "00000B1"), nil)
	c = log(ns).catches[2]
	eq(c.x, nil, "no position from the client: missing, not 0"); eq(c.clk, nil); eq(c.same, nil); eq(c.spawn, "00000B1")
end)

it("water type: clicked object = source is open water; another source while the bobber was clicked is a pool", function()
	local ns, stub = setup()
	-- Before anything is known: water type unknown.
	catch(stub, 0, guid(SCHOOL, "00000B1"), guid(BOBBER, "00000A1"))
	eq(ns.Fishing.WaterOf(log(ns).catches[1]), "?")
	-- The bobber is learned from an open-water catch ...
	catch(stub, 20, guid(BOBBER, "00000A2"), guid(BOBBER, "00000A2"))
	eq(ns.Fishing.WaterOf(log(ns).catches[2]), "open")
	-- ... and the earlier catch is classified with it, without any list of IDs.
	eq(ns.Fishing.WaterOf(log(ns).catches[1]), "pool")
	local k = ns.Fishing.Kinds()
	eq(k.kind[BOBBER], "open"); eq(k.kind[SCHOOL], "pool"); eq(k.open[BOBBER], 1); eq(k.pool[SCHOOL], 1)
end)

it("water type: the same source GUID in two catches is a pool; a tie stays unknown", function()
	local ns, stub = setup()
	catch(stub, 0, guid(WRECK, "00000C1"), nil)
	eq(ns.Fishing.WaterOf(log(ns).catches[1]), "?", "one catch proves nothing")
	catch(stub, 20, guid(WRECK, "00000C1"), nil)
	eq(ns.Fishing.Kinds().kind[WRECK], "pool")
	-- Conflicting evidence on one object ID: as much open as pool evidence -> unknown.
	catch(stub, 20, guid(WRECK, "00000C9"), guid(WRECK, "00000C9"))
	eq(ns.Fishing.Kinds().kind[WRECK], nil)
end)

it("pool names come from what the client shows: object tooltip with a GUID, or the mouseover unit", function()
	local ns, stub = setup()
	tip(stub, "Test School", guid(SCHOOL, "00000B1"))
	eq(ns.db.fishObjects[SCHOOL], nil, "not a loot source yet: kept for the session only")
	-- No GUID in the tooltip data: the mouseover unit names the object when it is one of the same name.
	stub.guids.mouseover, stub.names.mouseover = guid(WRECK, "00000C1"), "Test Wreckage"
	tip(stub, "Test Wreckage", nil)
	-- A tooltip without either names nothing; objects that are never fished are never stored.
	stub.guids.mouseover, stub.names.mouseover = nil, nil
	tip(stub, "Some Mailbox", nil)
	tip(stub, "Some Herb", guid(8888, "00000H1"))
	-- Fishing them stores the names seen earlier.
	catch(stub, 0, guid(BOBBER, "00000A1"), guid(BOBBER, "00000A1"))
	catch(stub, 20, guid(SCHOOL, "00000B1"), guid(BOBBER, "00000A2"))
	catch(stub, 20, guid(WRECK, "00000C1"), guid(BOBBER, "00000A3"))
	catch(stub, 20, guid(7777, "00000D1"), guid(BOBBER, "00000A4"))
	eq(ns.db.fishObjects[SCHOOL].name, "Test School"); eq(ns.db.fishObjects[WRECK].name, "Test Wreckage")
	eq(ns.db.fishObjects[8888], nil)
	-- Once a source, a later tooltip updates the stored name at once.
	tip(stub, "Test School Renamed", guid(SCHOOL, "00000B2"))
	eq(ns.db.fishObjects[SCHOOL].name, "Test School Renamed")
	-- The table row uses the name; an unnamed pool says so.
	local t = ns.Fishing.Tables()
	eq(ns.Fishing.RowLabel(row(t, "pool", SCHOOL)), "Test School Renamed (pool)")
	eq(ns.Fishing.RowLabel(row(t, "pool", 7777)), "pool object 7777 (name not seen)")
	eq(ns.Fishing.RowLabel(row(t, "open", nil)), "open water")
end)

it("the tooltip shown when the bobber was clicked counts as the clicked object (2 s)", function()
	local ns, stub = setup()
	tip(stub, "Test Bobber", guid(BOBBER, "00000A1"))
	catch(stub, 1, guid(BOBBER, "00000A1"), nil)
	eq(log(ns).catches[1].same, true)
	tip(stub, "Test Bobber", guid(BOBBER, "00000A2"))
	catch(stub, 3, guid(BOBBER, "00000A2"), nil)
	eq(log(ns).catches[2].clk, nil, "a tooltip older than 2 s is not the click")
	-- Interact key: the soft-interact target.
	stub.guids.softinteract = guid(BOBBER, "00000A3")
	catch(stub, 20, guid(BOBBER, "00000A3"), nil)
	eq(log(ns).catches[3].same, true)
end)

it("tables per zone, subzone and water type: shares, value per catch, value per hour from sessions", function()
	local ns, stub = setup()
	-- Session 1: open water, 3 catches 30 s apart (first untimed).
	catch(stub, 0, guid(BOBBER, "A1"), guid(BOBBER, "A1"), { [FISH] = 1 })
	catch(stub, 30, guid(BOBBER, "A2"), guid(BOBBER, "A2"), { [FISH] = 1 })
	catch(stub, 30, guid(BOBBER, "A3"), guid(BOBBER, "A3"), { [BOOT] = 1 })
	-- Same session: a pool, 2 catches 20 s apart (both timed).
	catch(stub, 20, guid(SCHOOL, "B1"), guid(BOBBER, "A4"), { [OIL] = 2 })
	catch(stub, 20, guid(SCHOOL, "B1"), guid(BOBBER, "A5"), { [OIL] = 1, [FISH] = 1 })
	-- 6 minutes later: a new session (gap 5 min), first catch untimed.
	catch(stub, 360, guid(SCHOOL, "B1"), guid(BOBBER, "A6"), { [OIL] = 1 })
	local t = ns.Fishing.Tables()
	eq(t.catches, 6); eq(t.gap, 5)
	local open = row(t, "open", nil)
	eq(open.catches, 3); eq(open.units, 3); eq(open.value, 12); eq(open.unpriced, 1); eq(open.perCatch, 4)
	eq(open.timed, 2); eq(open.seconds, 60); eq(open.timedValue, 6); eq(open.perHour, 6 * 60)
	eq(open.items[1].itemID, FISH); eq(open.items[1].count, 2); eq(open.items[1].share, 2 / 3)
	eq(open.items[2].unit, nil, "boot has no price")
	local pool = row(t, "pool", SCHOOL)
	eq(pool.catches, 3); eq(pool.units, 5); eq(pool.value, 4 * 20 + 6); eq(pool.perCatch, math.floor(86 / 3))
	eq(pool.timed, 2, "the new session's first catch is untimed"); eq(pool.seconds, 40); eq(pool.timedValue, 40 + 26)
	eq(pool.perHour, math.floor(66 * 3600 / 40))
	-- Zone and subzone totals across water types.
	eq(t.zones[1].zone, "Stranglethorn Vale"); eq(t.zones[1].catches, 6); eq(t.zones[1].subs[1].catches, 6)
	-- A longer gap setting joins the sessions.
	ns.Fishing.Slash("gap 10")
	eq(ns.db.settings.fishingSessionGap, 10)
	eq(row(ns.Fishing.Tables(), "pool", SCHOOL).timed, 3)
end)

it("pool visits: catches per pool spawn until it vanished or the player left; a visit going on is apart", function()
	local ns, stub = setup()
	catch(stub, 0, guid(BOBBER, "A1"), guid(BOBBER, "A1"))
	for _ = 1, 3 do catch(stub, 20, guid(SCHOOL, "B1"), guid(BOBBER, "A2")) end
	catch(stub, 60, guid(BOBBER, "A3"), guid(BOBBER, "A3"))
	for _ = 1, 5 do catch(stub, 20, guid(SCHOOL, "B2"), guid(BOBBER, "A4")) end
	catch(stub, 60, guid(WRECK, "C1"), guid(BOBBER, "A5"))
	catch(stub, 20, guid(WRECK, "C1"), guid(BOBBER, "A6"))
	local t = ns.Fishing.Tables()
	local school, wreck
	for _, p in ipairs(t.pools) do
		if p.obj == SCHOOL then school = p elseif p.obj == WRECK then wreck = p end
	end
	eq(school.visits, 2); eq(school.catches, 8); eq(school.min, 3); eq(school.max, 5); eq(school.avg, 4); eq(school.going, 0)
	eq(wreck.visits, 0); eq(wreck.going, 1, "the last pool may still be there")
	stub.clock = stub.clock + 600
	wreck = nil
	for _, p in ipairs(ns.Fishing.Tables().pools) do if p.obj == WRECK then wreck = p end end
	eq(wreck.visits, 1, "after the session gap it has ended"); eq(wreck.min, 2)
	-- Without a spawn part in the GUID: same object, within 1% of the map and the session gap, is one visit.
	local T = stub.clock
	ns.db.fishing["Forever-EU-Veli"].catches = {
		{ t = T + 1, obj = BOBBER, spawn = "Z1", clk = BOBBER, same = true, items = {} },
		{ t = T + 20, obj = SCHOOL, clk = BOBBER, x = 30.0, y = 40.0, items = {} },
		{ t = T + 40, obj = SCHOOL, clk = BOBBER, x = 30.4, y = 40.0, items = {} },
		{ t = T + 60, obj = SCHOOL, clk = BOBBER, x = 50.0, y = 40.0, items = {} },
		{ t = T + 80, obj = BOBBER, spawn = "Z2", clk = BOBBER, same = true, items = {} },
	}
	ns.Fishing.kinds = nil
	school = nil
	for _, p in ipairs(ns.Fishing.Tables().pools) do if p.obj == SCHOOL then school = p end end
	eq(school.visits, 2); eq(school.min, 1); eq(school.max, 2); eq(school.avg, 1.5)
end)

it("pool sightings: a known pool's tooltip or interact target is logged with position and time, once per spawn", function()
	local ns, stub = setup()
	catch(stub, 0, guid(BOBBER, "A1"), guid(BOBBER, "A1"))
	catch(stub, 20, guid(SCHOOL, "B1"), guid(BOBBER, "A2"))
	tip(stub, "Test School", guid(SCHOOL, "B7"))
	local seen = log(ns).seen
	eq(#seen, 1)
	eq(seen[1].obj, SCHOOL); eq(seen[1].spawn, "B7"); eq(seen[1].name, "Test School"); eq(seen[1].how, "tooltip")
	eq(seen[1].zone, "Stranglethorn Vale"); eq(seen[1].x, 25.4); eq(seen[1].t, stub.clock)
	tip(stub, "Test School", guid(SCHOOL, "B7"))
	eq(#seen, 1, "same spawn within 10 minutes: once")
	stub.clock = stub.clock + 601
	tip(stub, "Test School", guid(SCHOOL, "B7"))
	eq(#log(ns).seen, 2)
	-- The bobber or an unknown object is no pool sighting.
	tip(stub, "Test Bobber", guid(BOBBER, "A9"))
	tip(stub, "Some Herb", guid(8888, "H1"))
	eq(#log(ns).seen, 2)
	-- Name only (no GUID from the client): matched to the known pool of that name.
	tip(stub, "Test School", nil)
	seen = log(ns).seen
	eq(#seen, 3); eq(seen[3].obj, SCHOOL); eq(seen[3].spawn, nil)
	-- Soft interact.
	stub.guids.softinteract, stub.names.softinteract = guid(SCHOOL, "B8"), "Test School"
	stub.Fire("PLAYER_SOFT_INTERACT_CHANGED", "", guid(SCHOOL, "B8"))
	eq(log(ns).seen[4].how, "interact")
	-- In the pool table: seen 4 times, 3 of them spawns never fished (B7 twice, B8; the name-only one has no spawn).
	local school
	for _, p in ipairs(ns.Fishing.Tables().pools) do if p.obj == SCHOOL then school = p end end
	eq(school.seen, 4); eq(school.notFished, 3)
	-- Sightings follow the 90-day retention.
	stub.clock = stub.clock + 91 * 86400
	ns.Fishing.Prune()
	eq(#log(ns).seen, 0)
end)

it("Find Fish: known and tracking from the client's spellbook and tracking list, matched by spell ID 43308", function()
	local ns, stub = setup()
	eq(ns.Fishing.FIND_FISH, 43308)
	local ff = ns.Fishing.FindFish()
	eq(ff.known, false); eq(ff.tracking, false); eq(ff.inList, false)
	stub.known[43308] = true
	stub.tracking = { { name = "Find Herbs", spellID = 2383, active = true }, { name = "Find Fish", spellID = 43308, active = false } }
	ff = ns.Fishing.FindFish()
	eq(ff.known, true); eq(ff.inList, true); eq(ff.tracking, false)
	stub.tracking[2].active = true
	catch(stub, 0, guid(BOBBER, "A1"), guid(BOBBER, "A1"))
	eq(log(ns).catches[1].ff, true, "catch made while Find Fish tracked")
	stub.tracking[2].active = false
	stub.Fire("MINIMAP_UPDATE_TRACKING")
	eq(log(ns).findFish.tracking, false); eq(log(ns).findFish.known, true)
	ns.Fishing.Slash("")
	has(printed(stub), "Find Fish: known, tracking off")
	local snap = ns.Fishing.SnapshotSummary()
	eq(snap.findFish.spellID, 43308); eq(snap.findFish.known, true); eq(snap.findFish.tracking, false)
	-- Without the tracking API: unknown, not false.
	C_Minimap, C_SpellBook = nil, nil
	ff = ns.Fishing.FindFish()
	eq(ff.known, nil); eq(ff.tracking, nil)
end)

it("/craftwise fishing pools|open [zone]: filters, counts with every share, pool visit lines", function()
	local ns, stub = setup()
	tip(stub, "Test School", guid(SCHOOL, "B1"))
	catch(stub, 0, guid(BOBBER, "A1"), guid(BOBBER, "A1"))
	catch(stub, 20, guid(SCHOOL, "B1"), guid(BOBBER, "A2"), { [OIL] = 2 })
	catch(stub, 20, guid(SCHOOL, "B1"), guid(BOBBER, "A3"), { [OIL] = 1 })
	stub.zone, stub.subzone = "Tanaris", ""
	catch(stub, 20, guid(BOBBER, "A4"), guid(BOBBER, "A4"))
	stub.printed = {}
	SlashCmdList.CRAFTWISE("fishing pools")
	local text = printed(stub)
	has(text, "Fishing, last 90 days: 2 pool catches.")
	has(text, "    Test School (pool): n = 2 catches, " .. ns.FormatMoney(30) .. " per catch, " .. ns.FormatMoney(60 * 3600 / 40)
		.. " per hour (n = 2 timed, 1 min)")
	has(text, "      Test Oil x3 (3 of 3 items, 100%) - " .. ns.FormatMoney(20) .. " each (vendor)")
	has(text, "  Test School: 1 visits ended, 2 catches per visit (n = 1, avg 2)")
	assert(not text:find("open water", 1, true), "pools only")
	stub.printed = {}
	SlashCmdList.CRAFTWISE("fishing open tanaris")
	text = printed(stub)
	has(text, "1 open-water catches in tanaris")
	has(text, "    open water: n = 1 catches")
	assert(not text:find("Stranglethorn", 1, true), "only Tanaris")
	assert(not text:find("Pools:", 1, true), "no pool lines for open water")
	stub.printed = {}
	SlashCmdList.CRAFTWISE("fishing pools tanaris")
	has(printed(stub), "No pool catches in tanaris in the last 90 days.")
	stub.printed = {}
	SlashCmdList.CRAFTWISE("fishing gap 0")
	has(printed(stub), "at least 1 minute")
	eq(ns.db.settings.fishingSessionGap, 5)
end)

it("snapshot: compact ranking by value per hour, then per catch; pools with visits", function()
	local ns, stub = setup()
	tip(stub, "Test School", guid(SCHOOL, "B1"))
	catch(stub, 0, guid(BOBBER, "A1"), guid(BOBBER, "A1"), { [FISH] = 1 })
	catch(stub, 60, guid(BOBBER, "A2"), guid(BOBBER, "A2"), { [FISH] = 1 })
	catch(stub, 20, guid(SCHOOL, "B1"), guid(BOBBER, "A3"), { [OIL] = 2 })
	catch(stub, 20, guid(SCHOOL, "B1"), guid(BOBBER, "A4"), { [OIL] = 1, [BOOT] = 1 })
	stub.zone, stub.subzone = "Tanaris", ""
	catch(stub, 600, guid(BOBBER, "A5"), guid(BOBBER, "A5"), { [OIL] = 5 }) -- untimed, but high per catch
	local f = ns.Snapshot.Build().fishing
	eq(f.sessionGapMinutes, 5)
	eq(f.spots[1].water, "pool"); eq(f.spots[1].pool, "Test School"); eq(f.spots[1].obj, SCHOOL); eq(f.spots[1].n, 2)
	eq(f.spots[1].timed, 2); eq(f.spots[1].minutes, 0.7); eq(f.spots[1].unpriced, 1)
	eq(f.spots[1].top, OIL .. " Test Oil 3/4; " .. BOOT .. " Test Boot 1/4")
	eq(f.spots[2].water, "open"); eq(f.spots[2].zone, "Stranglethorn Vale"); eq(f.spots[2].perHour, 6 * 60)
	eq(f.spots[3].zone, "Tanaris"); eq(f.spots[3].perHour, nil); eq(f.spots[3].perCatch, 100); eq(f.spots[3].timed, nil)
	eq(f.pools[1].name, "Test School"); eq(f.pools[1].visits, 1); eq(f.pools[1].perVisit, "2-2, avg 2")
end)

it("FishingTables.lua is in the TOC right after Fishing.lua", function()
	local f = assert(io.open("CraftWise/CraftWise.toc"))
	local toc = f:read("*a")
	f:close()
	assert(toc:find("Fishing.lua\nFishingTables.lua\n", 1, true), "FishingTables.lua right after Fishing.lua")
end)
