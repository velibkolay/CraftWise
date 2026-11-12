-- Issue #88: Fishing zones ranked by value per catch from own catches and the optional local reference
-- (CraftWise_FishingRef), containers valued by their contents, Gather › Fishing, /craftwise fishing zones, and
-- the converter tools/fishing_ref.py on a synthetic fixture. Zones, items, counts and prices are made up.
local NOW = 1794000000
local SNAPPER, EEL, TRUNK, RING, PURSE, PEARL = 9101, 9102, 9103, 9201, 9202, 9104

local function setup(opts)
	local ns, stub = LoadAddon(opts)
	stub.clock = NOW
	time = function() return stub.clock end
	stub.names.player, stub.realm = "Veli", "Forever-EU"
	stub.printed = {}
	ns.Print = function(m) stub.printed[#stub.printed + 1] = m end
	-- Stub prices: unit value as ns.GetSellValue gives it (AH after cut or vendor).
	stub.prices = { [SNAPPER] = { copper = 10, source = "vendor", label = "vendor" },
		[EEL] = { copper = 100, source = "auction", label = "AH typical" },
		[RING] = { copper = 500, source = "vendor", label = "vendor" },
		[PURSE] = { copper = 20, source = "vendor", label = "vendor" } }
	ns.GetSellValue = function(id) return stub.prices[id] end
	for id, name in pairs({ [SNAPPER] = "Test Snapper", [EEL] = "Test Eel", [TRUNK] = "Test Trunk", [RING] = "Test Ring",
		[PURSE] = "Test Purse", [PEARL] = "Test Pearl" }) do
		stub.items[id] = { name = name }
	end
	stub.Fire("PLAYER_LOGIN")
	return ns, stub
end

-- Reference as tools/fishing_ref.py writes it.
local function reference()
	CraftWise_FishingRef = {
		version = 1, generated = "2026-11-11",
		zones = {
			{ id = 9001, name = "Testwater Bay", total = 200, items = {
				{ id = SNAPPER, name = "Test Snapper", count = 120, stack = { 1, 1 } },
				{ id = EEL, name = "Test Eel", count = 60, stack = { 1, 3 } },
				{ id = TRUNK, name = "Test Trunk", count = 20, stack = { 1, 1 } },
			} },
			{ id = 9002, name = "Dull Pond", total = 1000, items = {
				{ id = SNAPPER, count = 990, stack = { 1, 1 } },
				{ id = PEARL, count = 10, outof = 500 }, -- no price, no stack
			} },
		},
		containers = {
			[TRUNK] = { id = TRUNK, name = "Test Trunk", total = 50, items = {
				{ id = PURSE, count = 50, stack = { 2, 4 } },
				{ id = RING, count = 10, stack = { 1, 1 } },
			} },
		},
		pools = {},
	}
end

local function key(ns) return ns.CharKey() end
local function addCatches(ns, zone, n, items, step)
	ns.db.fishing[key(ns)] = ns.db.fishing[key(ns)] or { catches = {}, opened = {}, seen = {} }
	local log = ns.db.fishing[key(ns)]
	for i = 1, n do
		log.catches[#log.catches + 1] = { t = NOW - 3600 + #log.catches * (step or 20), zone = zone, sub = "", items = items }
	end
	return log
end
local function zoneOf(rank, name)
	for _, z in ipairs(rank.zones) do
		if z.name == name then return z end
	end
end
local function itemOf(z, id)
	for _, line in ipairs(z.items) do
		if line.itemID == id then return line end
	end
end
local function printed(stub) return table.concat(stub.printed, "\n") end
local function has(text, s) assert(text:find(s, 1, true), ("missing %q in:\n%s"):format(s, text)) end

it("ranks reference zones by value per catch with chances, stack ranges and container contents", function()
	local ns = setup()
	reference()
	local rank = ns.FishingZones.Rank()
	eq(rank.ref, true); eq(#rank.zones, 2)
	local bay = rank.zones[1]
	eq(bay.name, "Testwater Bay"); eq(bay.source, "ref"); eq(bay.n, 200)
	-- Trunk contents: purse 1/1 x 2-4 x 20c = 40-80c, ring 10/50 x 500c = 100c -> 140-180c per trunk.
	local trunk = itemOf(bay, TRUNK)
	eq(trunk.unit.container, "ref"); eq(trunk.unit.copper, 140); eq(trunk.unit.high, 180)
	-- Per catch: snapper 0.6 x 10 = 6, eel 0.3 x 1-3 x 100 = 30-90, trunk 0.1 x 140-180 = 14-18 -> 50-114.
	eq(bay.perCatch, 50); eq(bay.perCatchHigh, 114)
	eq(itemOf(bay, EEL).chance, 0.3); eq(itemOf(bay, EEL).perCatch, 30); eq(itemOf(bay, EEL).perCatchHigh, 90)
	eq(bay.items[1].itemID, EEL, "items by value per catch")
	local pond = rank.zones[2]
	eq(pond.name, "Dull Pond"); eq(pond.perCatch, 10); eq(pond.unpriced, 1, "the pearl has no price")
	local pearl = itemOf(pond, PEARL)
	eq(pearl.chance, 10 / 500, "an item's own outof wins over the zone total"); eq(pearl.stackKnown, false)
	eq(pond.perHour, nil, "no own timed catches: no value per hour")
end)

it("own catches replace the reference from fishingOwnMin catches on; below that the reference shows", function()
	local ns, stub = setup()
	reference()
	addCatches(ns, "Testwater Bay", 10, { [SNAPPER] = 1 })
	local z = zoneOf(ns.FishingZones.Rank(), "Testwater Bay")
	eq(z.source, "ref", "10 own catches < 50"); eq(z.own.n, 10); eq(z.own.perCatch, 10)
	ns.db.fishing[key(ns)] = nil
	addCatches(ns, "Testwater Bay", 60, { [SNAPPER] = 1 })
	z = zoneOf(ns.FishingZones.Rank(), "Testwater Bay")
	eq(z.source, "own"); eq(z.n, 60); eq(z.perCatch, 10); eq(itemOf(z, SNAPPER).chance, 1)
	eq(z.ref.perCatch, 50, "the reference side stays available")
	-- 60 catches 20 s apart in one session: 59 timed in 1180 s -> 180 catches/hour x 10c.
	eq(z.timed, 59); eq(z.perHour, 1800)
	-- The threshold is a setting.
	SlashCmdList.CRAFTWISE("fishing ownmin 100")
	eq(ns.db.settings.fishingOwnMin, 100)
	eq(zoneOf(ns.FishingZones.Rank(), "Testwater Bay").source, "ref")
	eq(zoneOf(ns.FishingZones.Rank(), "Testwater Bay").perHour, 180 * 50, "own speed x the reference value per catch")
	-- A forced side (the tab's source switch).
	eq(ns.FishingZones.Zone("testwater bay", { prefer = "own" }).source, "own")
	-- Zones without reference data use the own sample whatever its size.
	addCatches(ns, "Lonely Lake", 3, { [EEL] = 2 })
	z = zoneOf(ns.FishingZones.Rank(), "Lonely Lake")
	eq(z.source, "own"); eq(z.n, 3); eq(z.perCatch, 200); eq(itemOf(z, EEL).chance, 2, "units per catch")
	stub.printed = {}
end)

it("containers: own openings first (enough of them), else the reference contents, else the sell value", function()
	local ns, stub = setup()
	reference()
	local log = addCatches(ns, "Testwater Bay", 1, { [TRUNK] = 1 })
	-- Two own openings: fewer than OWN_MIN_OPENED and the reference has the trunk -> reference contents.
	log.opened = { { t = NOW, item = TRUNK, items = { [RING] = 1 } }, { t = NOW, item = TRUNK, items = { [PURSE] = 3 } } }
	local u = ns.FishingZones.UnitValue(TRUNK)
	eq(u.container, "ref"); eq(u.copper, 140)
	-- Five openings: own mean (2 rings, 15 purses over 5) = (1000 + 300) / 5 = 260.
	for _ = 1, 3 do log.opened[#log.opened + 1] = { t = NOW, item = TRUNK, items = { [PURSE] = 4 } } end
	u = ns.FishingZones.UnitValue(TRUNK)
	eq(u.container, "own"); eq(u.n, 5); eq(u.copper, (500 + 60 + 240) / 5)
	eq(u.label, "contents of 5 opened")
	-- Without the reference two own openings are enough.
	log.opened = { { t = NOW, item = TRUNK, items = { [RING] = 1 } }, { t = NOW, item = TRUNK, items = { [PURSE] = 5 } } }
	CraftWise_FishingRef = nil
	u = ns.FishingZones.UnitValue(TRUNK)
	eq(u.container, "own"); eq(u.copper, (500 + 100) / 2)
	-- Neither: the sell value, or no price.
	log.opened = {}
	eq(ns.FishingZones.UnitValue(TRUNK), nil)
	stub.prices[TRUNK] = { copper = 7, source = "vendor", label = "vendor" }
	eq(ns.FishingZones.UnitValue(TRUNK).copper, 7)
	-- A contained item without a price is left out and counted.
	reference()
	stub.prices[RING] = nil
	u = ns.FishingZones.UnitValue(TRUNK)
	eq(u.copper, 40); eq(u.unpriced, 1); eq(u.sell.copper, 7, "the unopened sell value stays for the tooltip")
end)

it("without the reference addon: own data only, a clear message when there is nothing", function()
	local ns, stub = setup()
	CraftWise_FishingRef = nil
	local rank = ns.FishingZones.Rank()
	eq(rank.ref, false); eq(#rank.zones, 0)
	SlashCmdList.CRAFTWISE("fishing zones")
	has(printed(stub), "no local reference loaded")
	CraftWise_FishingRef = { zones = "broken" }
	eq(ns.FishingZones.Reference(), nil, "a table that doesn't look like the reference is ignored")
	addCatches(ns, "Lonely Lake", 4, { [SNAPPER] = 1 })
	rank = ns.FishingZones.Rank()
	eq(#rank.zones, 1); eq(rank.zones[1].source, "own"); eq(rank.zones[1].ref, nil)
	stub.printed = {}
	SlashCmdList.CRAFTWISE("fishing zones")
	has(printed(stub), "1. Lonely Lake:"); has(printed(stub), "own catches, n = 4")
	-- The #86 tables are untouched by the new subcommands.
	stub.printed = {}
	SlashCmdList.CRAFTWISE("fishing")
	has(printed(stub), "Lonely Lake: n = 4 catches")
end)

it("/craftwise fishing zones prints the ranking with both sources and the filter", function()
	local ns, stub = setup()
	reference()
	addCatches(ns, "Testwater Bay", 5, { [SNAPPER] = 1 })
	SlashCmdList.CRAFTWISE("fishing zones")
	local text = printed(stub)
	has(text, "1. Testwater Bay:"); has(text, "(reference, n = 200)"); has(text, "own n = 5")
	has(text, "2. Dull Pond:"); has(text, "1 items without price left out")
	stub.printed = {}
	SlashCmdList.CRAFTWISE("fishing zones pond")
	text = printed(stub)
	has(text, "Dull Pond"); eq(text:find("Testwater", 1, true), nil)
end)

it("snapshot keeps a small zone ranking", function()
	local ns, stub = setup()
	reference()
	stub.Fire("PLAYER_LOGOUT")
	local snap = CraftWiseDB.snapshots[ns.CharKey()]
	eq(snap.errors, nil)
	local fz = snap.fishingZones
	eq(fz.reference, true); eq(#fz.zones, 2)
	eq(fz.zones[1].zone, "Testwater Bay"); eq(fz.zones[1].source, "ref"); eq(fz.zones[1].perCatch, 50); eq(fz.zones[1].perCatchHigh, 114)
	eq(fz.zones[2].perCatchHigh, nil); eq(fz.zones[2].unpriced, 1)
	-- #128: every item's units per catch (low-high) and unit value; the trunk keeps its contents value.
	eq(fz.zones[1].items, EEL .. " 0.3-0.9 100; " .. TRUNK .. " 0.1 140-180 c; " .. SNAPPER .. " 0.6 10")
	eq(fz.zones[2].items, SNAPPER .. " 0.99 10; " .. PEARL .. " 0.02 ?")
	eq(fz.zones[1].timed, nil); eq(fz.zones[1].minutes, nil)
end)

it("snapshot compares own catch composition with the reference per zone and pool object (#128)", function()
	local ns, stub = setup()
	reference()
	CraftWise_FishingRef.pools = { [7001] = { id = 7001, name = "Test School", total = 40, items = {
		{ id = EEL, count = 30, stack = { 1, 2 } }, { id = SNAPPER, count = 4, outof = 20 } } } }
	ns.db.fishing[key(ns)] = { catches = {}, opened = {}, seen = {} }
	local log = ns.db.fishing[key(ns)]
	local function add(n, items, water)
		for _ = 1, n do
			local i = #log.catches + 1
			log.catches[i] = { t = NOW - 3600 + i * 20, zone = "Testwater Bay", sub = "", items = items, obj = water == "pool" and 7001 or 50,
				spawn = water == "pool" and "P1" or ("B" .. i), same = water ~= "pool" or nil }
		end
	end
	add(10, { [SNAPPER] = 1 }, "open")
	add(3, { [EEL] = 2, [SNAPPER] = 1 }, "open")
	add(4, { [EEL] = 1 }, "pool")
	stub.Fire("PLAYER_LOGOUT")
	local fz = CraftWiseDB.snapshots[ns.CharKey()].fishingZones
	eq(#fz.compare, 1); eq(fz.compareMore, nil)
	local c = fz.compare[1]
	eq(c.zone, "Testwater Bay"); eq(c.n, 17); eq(c.timed, 16)
	-- own: catches with the item, units, unit value; reference: count (out of refN), stack, unit value
	eq(c.own, SNAPPER .. " 13 13 10; " .. EEL .. " 7 10 100")
	eq(c.refN, 200); eq(c.ref, SNAPPER .. " 120 1 10; " .. EEL .. " 60 1-3 100; " .. TRUNK .. " 20 1 140-180 c")
	eq(#c.waters, 2)
	eq(c.waters[1].water, "open"); eq(c.waters[1].n, 13); eq(c.waters[1].ref, nil)
	eq(c.waters[2].water, "pool"); eq(c.waters[2].obj, 7001); eq(c.waters[2].own, EEL .. " 4 4 100")
	eq(c.waters[2].refN, 40); eq(c.waters[2].ref, EEL .. " 30 1-2 100; " .. SNAPPER .. " 4/20 1 10")
	-- the ranking shows the reference for this zone (17 own catches < 50) and `compare` has it: no second list
	local bay = fz.zones[1]
	eq(bay.zone, "Testwater Bay"); eq(bay.source, "ref"); eq(bay.items, nil)
	eq(fz.zones[2].zone, "Dull Pond"); eq(fz.zones[2].items, SNAPPER .. " 0.99 10; " .. PEARL .. " 0.02 ?")
	CraftWise_FishingRef = nil
end)

it("snapshot zones carry the own timing behind value per hour (#128)", function()
	local ns, stub = setup()
	addCatches(ns, "Own Lake", 60, { [EEL] = 1 }, 30)
	stub.Fire("PLAYER_LOGOUT")
	local z = CraftWiseDB.snapshots[ns.CharKey()].fishingZones.zones[1]
	eq(z.zone, "Own Lake"); eq(z.source, "own"); eq(z.n, 60); eq(z.perCatch, 100)
	eq(z.timed, 59); eq(z.minutes, 29.5); eq(z.perHour, 100 * 120)
	-- the zone's items are in `compare` (own catches), so the ranking leaves them out
	local fz = CraftWiseDB.snapshots[ns.CharKey()].fishingZones
	eq(z.items, nil); eq(fz.compare[1].zone, "Own Lake"); eq(fz.compare[1].own, EEL .. " 60 60 100")
end)

it("Gather › Fishing (#156): zone list, tooltips, sorting by every header, a zone's fish, the source switch", function()
	local ns, stub = setup()
	reference()
	addCatches(ns, "Testwater Bay", 10, { [SNAPPER] = 1 })
	local M = ns.Main
	M.Open("fishing")
	local list = M.ListOf("fishing")
	eq(#list.rows, 2); eq(list.rows[1].name, "Testwater Bay", "by value per catch while there is no catch rate yet")
	has(M.Frame().foot.right.text, "reference: ")
	local row = list.box.frames[1]
	eq(row.elementData.row.key, "testwater bay")
	row.scripts.OnEnter(row); row.scripts.OnLeave(row)
	for _, hit in pairs(row.hits) do hit.scripts.OnEnter(hit); hit.scripts.OnLeave(hit) end
	-- Sort by every header that sorts.
	for _, header in ipairs(list.headers) do
		if header:IsShown() then header.scripts.OnClick(header) end
	end
	M.state.sort.fishing = nil
	M.Refresh()
	-- Open the zone: the reference side (10 own < 50), the eel first by value per catch.
	row = list.box.frames[1]
	row.scripts.OnClick(row, "LeftButton")
	local detail = list.box.frames[2]
	eq(detail.elementData.open, true)
	local z = detail.elementData.row.zone
	eq(z.side.source, "ref")
	local fish = ns.GatherFishing.FishLines(z.side)
	eq(fish[1].itemID, EEL); eq(#fish, 3)
	-- Switch to own catches.
	local switch
	for _, b in ipairs(detail.content.cwPool.kinds.button) do
		if b.shown ~= false and b.label.text == "Show own catches" then switch = b end
	end
	switch.scripts.OnClick(switch)
	eq(ns.GatherFishing.state.prefer["testwater bay"], "own")
	eq(#ns.GatherFishing.FishLines(z.own), 1)
	-- Click again closes the zone.
	list.box.frames[1].scripts.OnClick(list.box.frames[1], "LeftButton")
	eq(#list.box.frames, 2)
end)

it("tools/fishing_ref.py turns the synthetic fixture into a reference CraftWise reads", function()
	local out = os.tmpname()
	os.remove(out)
	local cmd
	for _, py in ipairs({ "python3", "python" }) do
		if os.execute(py .. " -c \"import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)\" > /dev/null 2>&1") == 0 then
			cmd = py
			break
		end
	end
	assert(cmd, "Python 3.10+ is needed for the converter test (python3 or python on PATH)")
	local log = out .. ".log"
	local rc = os.execute(("%s -I tools/fishing_ref.py %s --pages tests/fixtures/fishing_ref/pages --date 2026-11-11 > %s 2>&1"):format(cmd, out, log))
	local f = io.open(log)
	local report = f and f:read("*a") or ""
	if f then f:close() end
	os.remove(log)
	eq(rc, 0, "converter failed:\n" .. report)
	has(report, "4 pages: 1 zones, 1 containers, 1 pools.")
	has(report, "skipped about.html: no fishing or contains listview")
	local base = out:match("([^/]+)$")
	local toc = io.open(out .. "/" .. base .. ".toc"):read("*a")
	has(toc, "## Interface: 16001"); has(toc, "## Title: CraftWise Fishing Reference (local)"); has(toc, "## OptionalDeps: CraftWise")
	has(toc, "\nData.lua\n")
	local ns = setup()
	dofile(out .. "/Data.lua")
	os.remove(out .. "/Data.lua"); os.remove(out .. "/" .. base .. ".toc"); os.remove(out)
	local ref = ns.FishingZones.Reference()
	assert(ref, "generated data not recognised")
	eq(#ref.zones, 1, "the _files folder of a saved page is ignored")
	local zone = ref.zones[1]
	eq(zone.id, 9001); eq(zone.name, "Testwater Bay"); eq(zone.total, 200); eq(#zone.items, 3, "rows without a count are dropped")
	eq(zone.items[2].name, "Test Eel [big]"); eq(zone.items[2].stack[2], 3)
	local trunk = ref.containers[TRUNK]
	eq(trunk.total, 50); eq(trunk.items[1].name, "Test Coin's Purse"); eq(trunk.items[2].name, "Test Silver Ring", "quality digit stripped")
	eq(ref.pools[9301].name, "Test Snapper School")
	-- And it ranks like the hand-written reference.
	local bay = ns.FishingZones.Rank().zones[1]
	eq(bay.name, "Testwater Bay"); eq(bay.perCatch, 50); eq(bay.perCatchHigh, 114)
end)
