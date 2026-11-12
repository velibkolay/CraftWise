-- Farm tracker (#126): session maths, gold per hour, pause/resume, idle pause, values (AH, vendor,
-- bound, stale, unknown), priciest, remove from list, zone split, history cap, snapshot export, window.
local ORE, CLOTH, HIDE, BOP, GEM = 2770, 2589, 2318, 9100, 1206
local T0 = 1794000000

local function link(id, name, color)
	return ("|cff%s|Hitem:%d::::::::20:::::|h[%s]|h|r"):format(color or "ffffff", id, name)
end

local function setup(opts)
	local ns, stub = LoadAddon(opts or { auctionator = true })
	LOOT_ITEM_SELF = "You receive loot: %s."
	LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d."
	stub.items[ORE] = { name = "Copper Ore", sellPrice = 5 }
	stub.items[CLOTH] = { name = "Linen Cloth", sellPrice = 13 }
	stub.items[HIDE] = { name = "Light Leather" } -- no sell price, no AH price
	stub.items[BOP] = { name = "Bound Trinket", sellPrice = 40, bindType = 1 }
	stub.items[GEM] = { name = "Malachite", sellPrice = 25 }
	stub.names.player, stub.realm = "Veli", "Forever-EU"
	stub.clock = T0
	time = function(t)
		if t then return os.time(t) end
		return stub.clock
	end
	stub.printed = {}
	ns.Print = function(m) stub.printed[#stub.printed + 1] = m end
	stub.zone = "Elwynn Forest"
	stub.money = 0
	stub.Fire("PLAYER_ENTERING_WORLD")
	return ns, stub
end

local function loot(stub, id, count)
	local name = stub.items[id].name
	local text = count and count > 1 and LOOT_ITEM_SELF_MULTIPLE:format(link(id, name), count)
		or LOOT_ITEM_SELF:format(link(id, name))
	stub.Fire("CHAT_MSG_LOOT", text, "", "", "", "", "", 0, 0, "", 0, 1, "Player-1-SELF")
end

local function coin(stub, copper)
	stub.money = stub.money + copper
	stub.Fire("PLAYER_MONEY")
	stub.Fire("CHAT_MSG_MONEY", "You loot some coin")
end

local function advance(stub, seconds)
	stub.clock = stub.clock + seconds
	stub.now = stub.now + seconds
end

it("the first loot starts a session: time, coin, items, gold per hour (coin and coin + items)", function()
	local ns, stub = setup()
	local F = ns.Farm
	eq(F.Current(), nil)
	loot(stub, CLOTH, 2) -- vendor 13 each
	local s = F.Current()
	assert(s, "auto-started")
	eq(s.start, T0); eq(F.Running(s), true)
	advance(stub, 240) -- loot less than idleMinutes (5) apart
	coin(stub, 1234)
	advance(stub, 240)
	local t = F.Totals(s, stub.clock)
	eq(t.seconds, 480); eq(t.coin, 1234); eq(t.items, 26); eq(t.vendor, 26); eq(t.total, 1260)
	eq(t.coinGph, math.floor(1234 * 7.5 + 0.5)); eq(t.gph, 1260 * 7.5)
	eq(F.Rate(100, 59), nil, "no rate from under a minute")
	eq(#t.rows, 1); eq(t.rows[1].n, 2); eq(t.rows[1].value, 26); eq(t.rows[1].source, "vendor")
	assert(CraftWiseFarmFrame and CraftWiseFarmFrame:IsShown(), "the window opens with the session")
end)

it("pause by hand: time stops, loot isn't counted; resume goes on", function()
	local ns, stub = setup()
	local F = ns.Farm
	loot(stub, ORE, 1)
	advance(stub, 100)
	SlashCmdList.CRAFTWISE("farm pause")
	local s = F.Current()
	eq(F.Running(s), false); eq(s.paused, true)
	advance(stub, 500)
	loot(stub, ORE, 5)
	coin(stub, 50)
	eq(F.Counts(s)[ORE], 1, "loot while paused is not counted")
	eq(s.coin, 0)
	eq(F.Elapsed(s, stub.clock), 100)
	SlashCmdList.CRAFTWISE("farm pause") -- toggles back
	eq(F.Running(s), true)
	advance(stub, 50)
	loot(stub, ORE, 2)
	eq(F.Counts(s)[ORE], 3)
	eq(F.Elapsed(s, stub.clock), 150)
	SlashCmdList.CRAFTWISE("farm start")
	assert(stub.printed[#stub.printed]:find("already running", 1, true))
end)

it("idle: no loot for idleMinutes pauses as of the last loot; the next loot goes on; 0 = never", function()
	local ns, stub = setup()
	local F = ns.Farm
	eq(ns.db.farm.idleMinutes, 5)
	loot(stub, ORE, 1)
	advance(stub, 120)
	loot(stub, ORE, 1) -- last loot at +120
	advance(stub, 299)
	local s = F.Tick(stub.clock)
	eq(F.Running(s), true, "under 5 minutes")
	advance(stub, 1)
	F.Tick(stub.clock)
	eq(F.Running(s), false); eq(s.autoPaused, true); eq(s.paused, nil)
	eq(F.Elapsed(s, stub.clock), 120, "the idle stretch doesn't count")
	advance(stub, 3600)
	eq(F.Elapsed(s, stub.clock), 120)
	loot(stub, CLOTH, 1) -- resumes on its own
	eq(F.Running(s), true); eq(s.autoPaused, nil)
	eq(F.Counts(s)[CLOTH], 1)
	advance(stub, 10)
	eq(F.Elapsed(s, stub.clock), 130)
	-- the idle pause also applies when nothing ticks: the next loot after a long gap
	advance(stub, 1000)
	loot(stub, CLOTH, 1)
	eq(F.Elapsed(s, stub.clock), 120, "nothing after the last loot counted, the new loot starts a new stretch")
	SlashCmdList.CRAFTWISE("farm idle 0")
	advance(stub, 10000)
	F.Tick(stub.clock)
	eq(F.Running(s), true, "idle 0: never pauses")
	SlashCmdList.CRAFTWISE("farm idle 500")
	eq(ns.db.farm.idleMinutes, 0, "out of range refused")
end)

it("values: AH after the cut or vendor, whichever CraftWise uses; bound and quest items vendor only; stale AH marked", function()
	local ns, stub = setup()
	local F = ns.Farm
	stub.ah[ORE], stub.ahAge[ORE] = 100, 0 -- 95 after 5%, beats vendor 5
	stub.ah[GEM], stub.ahAge[GEM] = 400, 3 -- 380, three days old: stale
	stub.ah[BOP] = 10000 -- bind on pickup: never AH
	loot(stub, ORE, 3)
	loot(stub, GEM, 1)
	loot(stub, BOP, 1)
	loot(stub, CLOTH, 4)
	local t = F.Totals(F.Current(), stub.clock)
	eq(t.items, 285 + 380 + 40 + 52)
	eq(t.vendor, 15 + 25 + 40 + 52)
	eq(t.ah, 285 + 380); eq(t.stale, 380)
	local byID = {}
	for _, r in ipairs(t.rows) do byID[r.itemID] = r end
	eq(byID[ORE].source, "auction"); eq(byID[ORE].stale, nil)
	eq(byID[GEM].stale, true); eq(byID[GEM].age, 3)
	eq(byID[BOP].source, "vendor"); eq(byID[BOP].noAuction, true); eq(byID[BOP].value, 40)
	eq(t.rows[1].itemID, GEM, "highest value first")
	eq(t.priciest.itemID, GEM, "priciest per unit")
	eq(t.priciest.unit, 380)
	stub.items[CLOTH].bindType = 4 -- quest item: vendor only too
	stub.ah[CLOTH] = 5000
	eq(F.UnitValue(CLOTH).source, "vendor")
end)

it("priciest is per unit, not per stack; ties go to the lower item ID", function()
	local ns, stub = setup()
	local F = ns.Farm
	loot(stub, ORE, 20) -- 5 each, 100 total
	loot(stub, GEM, 1) -- 25
	local t = F.Totals(F.Current(), stub.clock)
	eq(t.rows[1].itemID, ORE, "list by stack value")
	eq(t.priciest.itemID, GEM)
	stub.items[CLOTH].sellPrice = 25
	loot(stub, CLOTH, 1)
	eq(F.Totals(F.Current(), stub.clock).priciest.itemID, GEM, "same unit value: lower ID")
end)

it("unknown values are counted apart, never valued, and used once a price is known", function()
	local ns, stub = setup()
	local F = ns.Farm
	loot(stub, HIDE, 4)
	loot(stub, CLOTH, 1)
	local t = F.Totals(F.Current(), stub.clock)
	eq(t.items, 13); eq(t.unknownUnits, 4); eq(t.unknownItems, 1); eq(t.vendorUnknown, 4)
	eq(t.rows[#t.rows].itemID, HIDE, "unknown last"); eq(t.rows[#t.rows].value, nil)
	eq(t.priciest.itemID, CLOTH)
	eq(ns.FarmFrame.ValueText(t.rows[#t.rows]), ns.Style.colors.warn .. "?|r")
	stub.ah[HIDE] = 200 -- a scan arrives: 190 after the cut
	t = F.Totals(F.Current(), stub.clock)
	eq(t.unknownUnits, 0); eq(t.items, 13 + 760); eq(t.vendorUnknown, 4, "still no vendor price")
end)

it("remove from the list drops the item and ignores it until reset", function()
	local ns, stub = setup()
	local F = ns.Farm
	loot(stub, ORE, 3)
	loot(stub, CLOTH, 2)
	F.RemoveItem(ORE)
	local s = F.Current()
	eq(F.Counts(s)[ORE], nil)
	loot(stub, ORE, 2)
	eq(F.Counts(s)[ORE], nil, "ignored for the rest of the session")
	eq(F.Totals(s, stub.clock).items, 26)
	SlashCmdList.CRAFTWISE("farm reset")
	loot(stub, ORE, 1)
	eq(F.Counts(F.Current())[ORE], 1, "a new session counts it again")
end)

it("zones: time and loot per zone, split when the zone changes", function()
	local ns, stub = setup()
	local F = ns.Farm
	loot(stub, CLOTH, 1)
	advance(stub, 240)
	coin(stub, 100)
	stub.zone = "Westfall"
	stub.Fire("ZONE_CHANGED_NEW_AREA")
	advance(stub, 120)
	loot(stub, ORE, 2)
	coin(stub, 50)
	advance(stub, 200)
	stub.zone = "Duskwood"
	loot(stub, GEM, 1) -- no zone event: the loot's zone moves it
	local t = F.Totals(F.Current(), stub.clock)
	eq(t.seconds, 560)
	eq(#t.zones, 3)
	eq(t.zones[1].zone, "Westfall"); eq(t.zones[1].seconds, 320); eq(t.zones[1].coin, 50); eq(t.zones[1].items, 10)
	eq(t.zones[1].gph, math.floor(60 * 3600 / 320 + 0.5))
	eq(t.zones[2].zone, "Elwynn Forest"); eq(t.zones[2].seconds, 240); eq(t.zones[2].coin, 100); eq(t.zones[2].items, 13)
	eq(t.zones[3].zone, "Duskwood"); eq(t.zones[3].seconds, 0); eq(t.zones[3].items, 25); eq(t.zones[3].gph, nil)
	advance(stub, 60)
	t = F.Totals(F.Current(), stub.clock)
	eq(t.zones[3].seconds, 60, "the current zone keeps counting")
end)

it("history: reset keeps the session's values, newest first, at most 50; an empty session isn't kept", function()
	local ns, stub = setup()
	local F = ns.Farm
	SlashCmdList.CRAFTWISE("farm start")
	SlashCmdList.CRAFTWISE("farm reset")
	eq(#F.History(), 0, "nothing looted, nothing kept")
	assert(stub.printed[#stub.printed]:find("not saved", 1, true))
	SlashCmdList.CRAFTWISE("farm idle 0") -- an hour between loot and coin
	loot(stub, GEM, 1)
	advance(stub, 3600)
	coin(stub, 1000)
	SlashCmdList.CRAFTWISE("farm reset")
	eq(F.Current(), nil)
	local h = F.History()[1]
	eq(h.start, T0); eq(h.stop, T0 + 3600); eq(h.seconds, 3600); eq(h.zone, "Elwynn Forest")
	eq(h.coin, 1000); eq(h.items, 25); eq(h.vendor, 25); eq(h.gph, 1025); eq(h.coinGph, 1000); eq(h.unknown, 0)
	eq(h.top[1].id, GEM); eq(h.top[1].name, "Malachite"); eq(h.top[1].n, 1); eq(h.top[1].value, 25)
	stub.items[GEM].sellPrice = 9999
	eq(F.History()[1].items, 25, "a finished session keeps its values")
	for i = 1, 55 do
		loot(stub, ORE, i)
		advance(stub, 60)
		F.Reset(stub.clock)
	end
	eq(#F.History(), F.HISTORY_MAX)
	eq(F.History()[1].top[1].n, 55, "newest first")
	eq(F.History()[50].top[1].n, 6, "oldest dropped")
	SlashCmdList.CRAFTWISE("farm history")
	assert(stub.printed[#stub.printed - 9]:find("Copper Ore", 1, true), "history lines name the best item")
end)

it("logout stops the clock; the next login goes on without the time offline", function()
	local ns, stub = setup()
	local F = ns.Farm
	loot(stub, ORE, 1)
	advance(stub, 200)
	stub.Fire("PLAYER_LOGOUT")
	local saved = CraftWiseDB
	local snapFarm = saved.snapshots["Forever-EU-Veli"].farm
	eq(snapFarm.current.seconds, 200); eq(snapFarm.current.running, true)
	local s = saved.farmLog["Forever-EU-Veli"].current
	eq(s.resumedAt, nil); eq(s.resumeOnLogin, true); eq(s.active, 200)
	-- next session of the game, an hour later
	local ns2, stub2 = LoadAddon({ savedDB = saved })
	stub2.names.player, stub2.realm = "Veli", "Forever-EU"
	local later = T0 + 200 + 3600
	time = function() return later end
	stub2.Fire("PLAYER_ENTERING_WORLD")
	local s2 = ns2.Farm.Current()
	eq(ns2.Farm.Running(s2), true); eq(s2.resumeOnLogin, nil)
	later = later + 50
	eq(ns2.Farm.Elapsed(s2, later), 250)
	assert(CraftWiseFarmFrame and CraftWiseFarmFrame:IsShown(), "window back with the session")
end)

it("autostart off: loot doesn't start a session, Start does", function()
	local ns, stub = setup()
	local F = ns.Farm
	SlashCmdList.CRAFTWISE("farm autostart off")
	eq(ns.db.farm.autoStart, false)
	loot(stub, ORE, 1)
	eq(F.Current(), nil)
	SlashCmdList.CRAFTWISE("farm start")
	loot(stub, ORE, 1)
	eq(F.Counts(F.Current())[ORE], 1)
	SlashCmdList.CRAFTWISE("farm autostart maybe")
	assert(stub.printed[#stub.printed]:find("Usage", 1, true))
end)

it("one loot feed: the toast and the tracker see the same loot, each on its own switch", function()
	local ns, stub = setup()
	loot(stub, ORE, 2)
	coin(stub, 300)
	eq(#ns.LootToast.Lines(), 2)
	eq(ns.Farm.Counts(ns.Farm.Current())[ORE], 2); eq(ns.Farm.Current().coin, 300)
	SlashCmdList.CRAFTWISE("loottoast off")
	loot(stub, ORE, 1)
	eq(ns.Farm.Counts(ns.Farm.Current())[ORE], 3, "toast off, still tracked")
	SlashCmdList.CRAFTWISE("loottoast on")
	SlashCmdList.CRAFTWISE("farm off")
	eq(ns.Farm.Running(ns.Farm.Current()), false, "off pauses the session")
	eq(CraftWiseFarmFrame:IsShown(), false)
	loot(stub, ORE, 1)
	eq(ns.Farm.Counts(ns.Farm.Current())[ORE], 3, "tracker off, not counted")
	eq(#ns.LootToast.Lines(), 1, "the toast still shows it")
	-- vendor sales (no loot message) never count
	SlashCmdList.CRAFTWISE("farm on")
	SlashCmdList.CRAFTWISE("farm resume")
	stub.money = stub.money + 5000
	stub.Fire("PLAYER_MONEY")
	eq(ns.Farm.Current().coin, 300)
end)

it("snapshot: current session and the latest finished ones, capped, with what is left out counted", function()
	local ns, stub = setup()
	local F = ns.Farm
	local snap = ns.Snapshot.Build()
	eq(snap.farm.current, nil); eq(#snap.farm.sessions, 0); eq(snap.farm.saved, 0); eq(snap.farm.historyMax, 50)
	for i = 1, 25 do
		loot(stub, CLOTH, i)
		advance(stub, 120)
		F.Reset(stub.clock)
	end
	loot(stub, HIDE, 2)
	loot(stub, GEM, 1)
	advance(stub, 90)
	SlashCmdList.CRAFTWISE("farm pause")
	snap = ns.Snapshot.Build()
	local f = snap.farm
	eq(#f.sessions, F.SNAPSHOT_SESSIONS); eq(f.saved, 25); eq(f.more, 25 - F.SNAPSHOT_SESSIONS)
	eq(f.sessions[1].top[1].n, 25, "newest first")
	eq(f.current.running, false); eq(f.current.paused, "manual"); eq(f.current.stop, nil)
	eq(f.current.seconds, 90); eq(f.current.items, 25); eq(f.current.unknown, 2)
	eq(f.current.zone, "Elwynn Forest"); eq(f.current.zones, nil, "one zone: no zone list")
	eq(f.current.gph, nil, "rates are left out of the snapshot")
	eq(f.names[GEM], "Malachite"); eq(f.names[CLOTH], "Linen Cloth")
	eq(f.current.top[1].id, GEM); eq(f.current.top[1].name, nil, "names in f.names")
	eq(snap.skipped and snap.skipped.farm, nil); eq(snap.errors, nil)
end)

it("window: stats, list rows with value and source, x removes, lock, scale, hide and show", function()
	local ns, stub = setup()
	local FF = ns.FarmFrame
	stub.ah[ORE], stub.ahAge[ORE] = 100, 0
	loot(stub, ORE, 3)
	loot(stub, HIDE, 1)
	advance(stub, 120)
	coin(stub, 240)
	FF.Refresh()
	local f = CraftWiseFarmFrame
	eq(f.values.time.text, "00:02:00")
	eq(f.values.coin.text, ns.FormatMoney(240))
	eq(f.values.items.text, ns.FormatMoney(285))
	eq(f.values.gph.text, ns.FormatMoney((240 + 285) * 30))
	eq(f.values.coinGph.text, ns.FormatMoney(240 * 30))
	assert(f.values.priciest.text:find("Copper Ore", 1, true), f.values.priciest.text)
	assert(f.values.unknown.text:find("1", 1, true))
	eq(f.pause.label.text, "Pause")
	local rows = FF.Rows()
	eq(rows[1].data.itemID, ORE)
	assert(rows[1].value.text:find("AH", 1, true), rows[1].value.text)
	assert(rows[1].count.text:find("3x", 1, true))
	assert(rows[1].name.text:find("|hCopper Ore|h", 1, true), "name without brackets")
	eq(rows[2].data.itemID, HIDE)
	eq(rows[3].shown, false)
	rows[1].remove.GetParent = function() return rows[1] end
	rows[1].remove:GetScript("OnClick")(rows[1].remove)
	eq(ns.Farm.Counts(ns.Farm.Current())[ORE], nil)
	eq(rows[1].data.itemID, HIDE, "list redrawn")
	f.pause:GetScript("OnClick")(f.pause)
	eq(f.pause.label.text, "Resume")
	SlashCmdList.CRAFTWISE("farm lock")
	eq(ns.db.farm.locked, true); eq(f.locked, true)
	SlashCmdList.CRAFTWISE("farm unlock")
	eq(f.locked, false)
	SlashCmdList.CRAFTWISE("farm scale 3")
	eq(ns.db.farm.scale, 1, "out of range refused")
	SlashCmdList.CRAFTWISE("farm scale 0.8")
	eq(ns.db.farm.scale, 0.8)
	SlashCmdList.CRAFTWISE("farm hide")
	eq(f:IsShown(), false); eq(ns.db.farm.shown, false)
	SlashCmdList.CRAFTWISE("farm")
	eq(f:IsShown(), true); eq(ns.db.farm.shown, true)
	SlashCmdList.CRAFTWISE("farm reset")
	eq(f.pause.label.text, "Start")
	eq(rows[1].shown, false)
	f.GetPoint = function() return "TOPLEFT", UIParent, "TOPLEFT", 40, -80 end
	f:GetScript("OnDragStop")(f)
	eq(ns.db.farm.pos.x, 40)
	SlashCmdList.CRAFTWISE("farm whatever")
	assert(stub.printed[#stub.printed]:find("/craftwise farm show", 1, true), "usage")
end)

it("hidden window: the session is still tracked, and the window stays hidden on the next session", function()
	local ns, stub = setup()
	SlashCmdList.CRAFTWISE("farm hide")
	loot(stub, ORE, 1)
	eq(ns.Farm.Counts(ns.Farm.Current())[ORE], 1)
	eq(CraftWiseFarmFrame == nil or not CraftWiseFarmFrame:IsShown(), true)
end)
