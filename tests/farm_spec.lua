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
	eq(ns.FarmFrame.ValueText(t.rows[#t.rows]), ns.Style.Hex("text3") .. "no price|r")
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

it("tracker (#158): top line, gold per hour, split bar, top loot; × on Gather › Farm removes; lock, scale, hide and show", function()
	local ns, stub = setup()
	local FF = ns.FarmFrame
	local S = ns.Style
	stub.ah[ORE], stub.ahAge[ORE] = 100, 0 -- 95 after the cut
	loot(stub, ORE, 3)
	loot(stub, HIDE, 1)
	loot(stub, CLOTH, 2)
	advance(stub, 120)
	coin(stub, 240)
	FF.Refresh()
	local f = CraftWiseFarmFrame
	eq(f.timer.text, "0:02:00")
	eq(f.word.text, "running")
	local gph = (240 + 285 + 26) * 30
	eq(f.hero.value.text, FF.Coins(gph))
	assert(f.hero.caption.text:find("total " .. FF.Coins(240 + 285 + 26), 1, true), f.hero.caption.text)
	assert(f.hero.caption.text:find("Elwynn Forest", 1, true), "zone in the caption")
	eq(f.split.figures[1].text, FF.Coins(240), "coin")
	eq(f.split.figures[2].text, FF.Coins(285), "items at AH")
	eq(f.split.figures[3].text, FF.Coins(26), "vendor only")
	local rows = FF.LootRows()
	eq(rows[1].data.itemID, ORE); eq(rows[1].count.text, "×3"); eq(rows[1].value.text, FF.Coins(285))
	eq(rows[1].name.text, "Copper Ore", "plain name, quality colour on the FontString")
	eq(rows[1].name.textColor[1], S.C.qCommon[1])
	eq(rows[2].data.itemID, CLOTH)
	eq(rows[3].data.itemID, HIDE); eq(rows[3].value.text, S.Hex("text3") .. "no price|r")
	eq(rows[4].shown, false)
	eq(f.loot.more.text.text, "1 unpriced"); eq(f.loot.more.shown, true)
	-- × removes from the session on the open session's row of Gather › Farm (+ N more / Log link, #156).
	FF.OpenList()
	eq(ns.Main.shown.page, "farm")
	local list = ns.Main.ListOf("farm")
	local detail = list.box.frames[2]
	eq(detail.elementData.open, true); eq(detail.elementData.row.key, ns.FarmHistory.CURRENT)
	local x
	for _, b in ipairs(detail.content.cwPool.kinds.button) do
		if not x and b.shown ~= false and b.label.text == "×" then x = b end
	end
	assert(x, "× on the first item's line (best value first)")
	x:GetScript("OnClick")(x)
	eq(ns.Farm.Counts(ns.Farm.Current())[ORE], nil)
	eq(FF.LootRows()[1].data.itemID, CLOTH, "tracker redrawn")
	local b = f.buttons.b
	b.pause:GetScript("OnClick")(b.pause)
	eq(f.word.text, "paused"); eq(b.resume.shown, true); eq(b.pause.shown, false)
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
	b.endLine:GetScript("OnClick")(b.endLine)
	eq(ns.Farm.Current(), nil); eq(#ns.Farm.History(), 1, "End session keeps it in the history")
	eq(b.start.shown, true)
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

----------------------------------------------------------------------------------------------------
-- Fishing (#130): the session's catches from Fishing.lua's catch record
----------------------------------------------------------------------------------------------------

local CRATE, RING = 9004, 9005

-- A loot window: Fishing.lua reads it on LOOT_READY; then the loot lines and the coin reach the feed, as in game.
local function window(stub, slots, fishing, isFromItem)
	stub.fishing = fishing
	stub.loot = {}
	for _, sl in ipairs(slots) do
		if sl.copper then
			stub.loot[#stub.loot + 1] = { coin = true }
		else
			stub.loot[#stub.loot + 1] = { link = link(sl.id, stub.items[sl.id].name), qty = sl.n or 1 }
		end
	end
	stub.Fire("LOOT_READY", false)
	stub.Fire("LOOT_OPENED", false, isFromItem or false)
	stub.Fire("LOOT_CLOSED")
	for _, sl in ipairs(slots) do
		if sl.copper then
			coin(stub, sl.copper)
		else
			loot(stub, sl.id, sl.n)
		end
	end
end

local function fishSetup(opts)
	local ns, stub = setup(opts)
	stub.fishing = false
	IsFishingLoot = function() return stub.fishing end
	GetLootSlotInfo = function(i)
		local s = stub.loot[i]
		if not s then return nil end
		return "tex", "name", s.qty or 1, nil, 1, false, false, nil, nil, s.coin
	end
	stub.items[CRATE] = { name = "Test Crate" } -- no price of its own
	stub.items[RING] = { name = "Test Ring", sellPrice = 300 }
	return ns, stub
end

local function catch(stub, slots)
	window(stub, slots, true)
end

it("fishing: catches counted from the fishing log's record, valued like the loot list; no block without catches", function()
	local ns, stub = fishSetup()
	local F = ns.Farm
	window(stub, { { id = ORE, n = 2 }, { copper = 500 } }, false) -- a mob: not fishing
	eq(F.Totals(F.Current(), stub.clock).fish, nil, "no catches, no fishing block")
	eq(ns.FarmFrame.FishCard().shown, false)
	advance(stub, 30)
	catch(stub, { { id = CLOTH } }) -- 13
	advance(stub, 30)
	catch(stub, { { id = GEM }, { copper = 40 } }) -- 25 + 40 coin
	advance(stub, 40)
	catch(stub, { { id = CLOTH, n = 2 } }) -- 26
	eq(#ns.db.fishing["Forever-EU-Veli"].catches, 3, "the fishing log has the same catches")
	local f = F.Totals(F.Current(), stub.clock).fish
	eq(f.catches, 3); eq(f.coin, 40); eq(f.items, 13 + 25 + 26); eq(f.value, 104)
	eq(f.perCatch, math.floor(104 / 3 + 0.5))
	eq(f.timed, 2); eq(f.seconds, 70, "the time between catches")
	eq(f.cph, math.floor(2 * 36000 / 70 + 0.5) / 10)
	eq(f.gph, math.floor(104 * 2 * 3600 / (3 * 70) + 0.5))
	eq(f.best.itemID, GEM); eq(f.best.unit, 25)
	eq(f.unknownUnits, 0); eq(f.opened, 0)
	local t = F.Totals(F.Current(), stub.clock)
	eq(t.coin, 540, "the session's coin has the mob's and the catch's"); eq(t.items, 10 + 13 + 25 + 26)
	eq(ns.FarmFrame.FishCard().shown, true, "the block shows once there are catches")
end)

it("fishing: coin only from a catch window with coin; unknown values apart; gaps over FISH_GAP aren't fishing time", function()
	local ns, stub = fishSetup()
	local F = ns.Farm
	catch(stub, { { id = HIDE, n = 3 } }) -- no price at all
	advance(stub, 10)
	coin(stub, 77) -- coin loot, but the catch window had none
	advance(stub, F.FISH_GAP + 1)
	catch(stub, { { id = CLOTH }, { copper = 5 } })
	advance(stub, 20)
	-- A catch window with a coin slot whose coin comes too late: not fishing coin.
	stub.fishing, stub.loot = true, { { link = link(CLOTH, "Linen Cloth") }, { coin = true } }
	stub.Fire("LOOT_READY", false)
	stub.Fire("LOOT_CLOSED")
	loot(stub, CLOTH, 1)
	stub.now = stub.now + F.FISH_COIN_SECONDS + 1
	coin(stub, 9)
	local f = F.Totals(F.Current(), stub.clock).fish
	eq(f.catches, 3); eq(f.coin, 5); eq(f.unknownUnits, 3); eq(f.items, 26)
	eq(f.timed, 1, "the first gap was too long"); eq(f.seconds, 20)
	eq(f.cph, nil, "no rate from under a minute of fishing")
	eq(f.perCatch, math.floor(31 / 3 + 0.5), "unknown items are left out of the value")
end)

it("fishing: per zone, paused and removed items, containers opened count as their contents", function()
	local ns, stub = fishSetup()
	local F = ns.Farm
	catch(stub, { { id = CRATE } })
	advance(stub, 30)
	catch(stub, { { id = CLOTH } })
	stub.zone = "Westfall"
	stub.Fire("ZONE_CHANGED_NEW_AREA")
	advance(stub, 30)
	catch(stub, { { id = GEM } })
	advance(stub, 30)
	catch(stub, { { id = GEM } })
	local f = F.Totals(F.Current(), stub.clock).fish
	eq(#f.zones, 2); eq(f.zones[1].zone, "Elwynn Forest"); eq(f.zones[1].catches, 2); eq(f.zones[1].unknownUnits, 1)
	eq(f.zones[2].zone, "Westfall"); eq(f.zones[2].items, 50); eq(f.zones[2].timed, 2); eq(f.zones[2].seconds, 60)
	-- Open the caught crate in Westfall: a ring and coin; the crate leaves Elwynn's fishing items.
	stub.bags[0] = { { itemID = CRATE, isLocked = true, hasLoot = true } }
	window(stub, { { id = RING }, { copper = 200 } }, false, true)
	eq(#ns.db.fishing["Forever-EU-Veli"].opened, 1)
	f = F.Totals(F.Current(), stub.clock).fish
	eq(f.opened, 1); eq(f.zones[1].opened, 1); eq(f.zones[1].unknownUnits, 0)
	eq(f.zones[1].items, 13 + 300); eq(f.zones[1].coin, 200)
	eq(f.best.itemID, RING)
	-- Another opening of a crate not caught this session: left out.
	window(stub, { { id = RING } }, false, true)
	eq(F.Totals(F.Current(), stub.clock).fish.opened, 1)
	-- Remove from the list: gone from fishing too.
	F.RemoveItem(RING)
	eq(F.Totals(F.Current(), stub.clock).fish.items, 13 + 50)
	-- Paused by hand: catches aren't counted.
	SlashCmdList.CRAFTWISE("farm pause")
	catch(stub, { { id = GEM } })
	eq(F.Totals(F.Current(), stub.clock).fish.catches, 4)
	eq(#ns.db.fishing["Forever-EU-Veli"].catches, 5, "the fishing log still records it")
end)

it("fishing: the first catch starts a session; history, /craftwise farm history and the snapshot keep the block", function()
	local ns, stub = fishSetup()
	local F = ns.Farm
	stub.zone = "Westfall"
	catch(stub, { { id = GEM }, { copper = 60 } })
	assert(F.Current(), "a catch starts the session")
	for _ = 1, 4 do
		advance(stub, 30)
		catch(stub, { { id = CLOTH } })
	end
	stub.zone = "Duskwood"
	advance(stub, 30)
	catch(stub, { { id = HIDE } })
	local snap = ns.Snapshot.Build()
	local cf = snap.farm.current.fish
	eq(cf.catches, 6); eq(cf.timed, 5); eq(cf.seconds, 150); eq(cf.coin, 60); eq(cf.items, 25 + 52); eq(cf.unknown, 1)
	eq(cf.opened, 0); eq(cf.best.id, GEM); eq(cf.best.value, 25); eq(cf.best.name, nil, "names in farm.names")
	eq(snap.farm.names[GEM], "Malachite")
	eq(#cf.zones, 2); eq(cf.zones[1].zone, "Westfall"); eq(cf.zones[1].catches, 5); eq(cf.zones[2].unknown, 1)
	eq(cf.perCatch, nil, "rates are left out of the snapshot"); eq(cf.gph, nil)
	SlashCmdList.CRAFTWISE("farm reset")
	local h = F.History()[1]
	eq(h.fish.catches, 6); eq(h.fish.items, 77); eq(h.fish.best.name, "Malachite")
	eq(h.fish.perCatch, math.floor(137 / 6 + 0.5)); eq(h.fish.gph, math.floor(137 * 5 * 3600 / (6 * 150) + 0.5))
	stub.items[GEM].sellPrice = 9999
	eq(F.History()[1].fish.items, 77, "a finished session keeps its values")
	SlashCmdList.CRAFTWISE("farm history")
	assert(stub.printed[#stub.printed]:find("6 catches", 1, true), stub.printed[#stub.printed])
	eq(ns.Snapshot.Build().farm.sessions[1].fish.catches, 6)
	-- A session without catches has no fishing block anywhere.
	loot(stub, ORE, 1)
	advance(stub, 60)
	SlashCmdList.CRAFTWISE("farm reset")
	eq(F.History()[1].fish, nil); eq(ns.Snapshot.Build().farm.sessions[1].fish, nil)
end)

it("open without typing (#130): the minimap right-click and the key binding toggle the window", function()
	local ns, stub = setup()
	local function shown() return CraftWiseFarmFrame ~= nil and CraftWiseFarmFrame:IsShown() end
	eq(shown(), false)
	-- The profit window and its Farm button are gone (#154); the minimap button's right-click toggles it.
	local btn = CraftWiseMinimapButton
	assert(btn, "minimap button")
	btn.scripts.OnClick(btn, "RightButton")
	eq(shown(), true); eq(ns.db.farm.shown, true)
	btn.scripts.OnClick(btn, "RightButton")
	eq(shown(), false); eq(ns.db.farm.shown, false)
	-- Key binding: Bindings.xml calls the global, its name is set for the Key Bindings list.
	local xml = assert(io.open("CraftWise/Bindings.xml")):read("*a")
	assert(xml:find('<Binding name="CRAFTWISE_FARM" header="CRAFTWISE"', 1, true), "binding in Bindings.xml")
	assert(xml:find("CraftWise_FarmToggle()", 1, true))
	eq(BINDING_NAME_CRAFTWISE_FARM, "Toggle CraftWise farm tracker"); eq(BINDING_HEADER_CRAFTWISE, "CraftWise")
	CraftWise_FarmToggle()
	eq(shown(), true)
	CraftWise_FarmToggle()
	eq(shown(), false)
	-- The old Settings panel's Farm window button went with it (#157): Gather › Farm's Open tracker
	-- (tests/gather_spec.lua), the minimap and the key binding open it.
	CraftWise_FarmToggle()
	eq(ns.Farm.Current(), nil, "opening the window starts no session")
end)

----------------------------------------------------------------------------------------------------
-- Loot log (#130): one line per drop, newest first
----------------------------------------------------------------------------------------------------

it("log: one line per drop in order, coin as its own lines, zone, time, value like the list; newest first", function()
	local ns, stub = fishSetup()
	local F = ns.Farm
	stub.ah[ORE], stub.ahAge[ORE] = 100, 0
	loot(stub, ORE, 3)
	advance(stub, 5)
	coin(stub, 120)
	advance(stub, 5)
	stub.zone = "Westfall"
	loot(stub, HIDE, 1)
	advance(stub, 5)
	catch(stub, { { id = CLOTH }, { copper = 30 } })
	advance(stub, 5)
	loot(stub, CLOTH, 2) -- not from the catch: its cloth line came already
	local s = F.Current()
	eq(#s.log, 6)
	local e = F.LogEntries(s)
	eq(#e, 6)
	eq(e[6].itemID, ORE); eq(e[6].n, 3); eq(e[6].value, 285); eq(e[6].source, "auction"); eq(e[6].t, T0); eq(e[6].zone, "Elwynn Forest")
	eq(e[5].copper, 120); eq(e[5].value, 120); eq(e[5].t, T0 + 5); eq(e[5].fish, nil)
	eq(e[4].itemID, HIDE); eq(e[4].value, nil, "unknown stays unknown"); eq(e[4].zone, "Westfall")
	eq(e[3].itemID, CLOTH); eq(e[3].fish, true, "the catch's item is marked"); eq(e[3].t, T0 + 15)
	eq(e[2].copper, 30); eq(e[2].fish, true, "the catch's coin is marked")
	eq(e[1].itemID, CLOTH); eq(e[1].n, 2); eq(e[1].fish, nil, "later loot of the same item is not")
	eq(s.logZones[1], "Elwynn Forest"); eq(s.logZones[2], "Westfall"); eq(#s.logZones, 2)
	-- Remove from the list: its lines leave the log too. Paused: nothing logged.
	F.RemoveItem(ORE)
	eq(#F.LogEntries(s), 5)
	SlashCmdList.CRAFTWISE("farm pause")
	loot(stub, GEM, 1)
	eq(#s.log, 5)
end)

it("log: capped at LOG_MAX lines per session, the oldest dropped and counted", function()
	local ns, stub = setup()
	local F = ns.Farm
	SlashCmdList.CRAFTWISE("farm idle 0")
	for i = 1, F.LOG_MAX + 25 do
		loot(stub, i % 2 == 0 and ORE or CLOTH, i)
		advance(stub, 1)
	end
	local s = F.Current()
	eq(#s.log, F.LOG_MAX); eq(s.logDropped, 25)
	local e = F.LogEntries(s)
	eq(e[1].n, F.LOG_MAX + 25, "newest first"); eq(e[#e].n, 26, "the oldest kept")
	eq(F.Counts(s)[ORE] + F.Counts(s)[CLOTH], (F.LOG_MAX + 25) * (F.LOG_MAX + 26) / 2, "the totals keep everything")
	ns.FarmFrame.OpenLog()
	local detail = ns.Main.ListOf("farm").box.frames[2]
	local head = detail.content.cwPool.kinds.text[1].text
	assert(head:find("25 older dropped", 1, true), head)
end)

it("log: kept across /reload, in the history, and the snapshot carries only the open session's newest lines", function()
	local ns, stub = setup()
	local F = ns.Farm
	SlashCmdList.CRAFTWISE("farm idle 0")
	for i = 1, 30 do
		if i == 25 then stub.zone = "Westfall" end
		loot(stub, CLOTH, i)
		advance(stub, 10)
	end
	coin(stub, 99)
	stub.Fire("PLAYER_LOGOUT")
	local saved = CraftWiseDB
	local snapCur = saved.snapshots["Forever-EU-Veli"].farm.current
	eq(#snapCur.log, F.SNAPSHOT_LOG); eq(snapCur.logLines, 31)
	eq(snapCur.log[#snapCur.log], "300,c,99,2", "the newest last, packed as in the session")
	eq(snapCur.logZones[1], "Elwynn Forest"); eq(snapCur.logZones[2], "Westfall")
	-- The next session of the game.
	local ns2, stub2 = LoadAddon({ savedDB = saved })
	stub2.names.player, stub2.realm = "Veli", "Forever-EU"
	time = function() return T0 + 4000 end
	stub2.Fire("PLAYER_ENTERING_WORLD")
	local s2 = ns2.Farm.Current()
	eq(#s2.log, 31)
	local e = ns2.Farm.LogEntries(s2)
	eq(e[1].copper, 99); eq(e[2].n, 30); eq(e[2].zone, "Westfall"); eq(e[31].n, 1); eq(e[31].t, T0)
	ns2.Farm.Reset(T0 + 4000)
	local h = ns2.Farm.History()[1]
	eq(#h.log, 31); eq(h.logZones[2], "Westfall")
	local snap = ns2.Snapshot.Build()
	eq(snap.farm.sessions[1].logLines, 31); eq(snap.farm.sessions[1].log, nil, "finished sessions: the count only")
	-- The newest HISTORY_LOGS finished sessions keep their log, older ones the line count.
	for i = 1, ns2.Farm.HISTORY_LOGS do
		ns2.Farm.OnFeed("item", { itemID = ORE, count = i })
		ns2.Farm.Reset(T0 + 4000)
	end
	local hist = ns2.Farm.History()
	eq(#hist[ns2.Farm.HISTORY_LOGS].log, 1)
	eq(hist[ns2.Farm.HISTORY_LOGS + 1].log, nil); eq(hist[ns2.Farm.HISTORY_LOGS + 1].logLines, 31)
end)

it("Log link: the open session's loot log on Gather › Farm, newest first, catches marked, coin lines (#156)", function()
	local ns, stub = fishSetup()
	local FF = ns.FarmFrame
	loot(stub, ORE, 2)
	advance(stub, 3)
	coin(stub, 50)
	advance(stub, 3)
	catch(stub, { { id = GEM } })
	FF.OpenLog()
	local detail = ns.Main.ListOf("farm").box.frames[2]
	eq(detail.elementData.row.key, ns.FarmHistory.CURRENT)
	local pool = detail.content.cwPool
	local lines = {}
	for _, fs in ipairs(pool.kinds.text) do
		if fs.shown ~= false then lines[#lines + 1] = fs.text end
	end
	local text = table.concat(lines, "\n")
	assert(text:find("Loot log · 3", 1, true), text)
	local gem = text:find(FF.FISH_MARK, 1, true)
	local coinAt = text:find(FF.Coins(50), 1, true)
	local ore = text:find("×2", 1, true)
	assert(gem and coinAt and ore and gem < coinAt and coinAt < ore, "newest first: catch, coin, ore")
	assert(text:find(date("%H:%M:%S", T0 + 6), 1, true), "time of the catch")
	assert(text:find("Elwynn Forest", 1, true), "zone")
	eq(pool.kinds.icon[2].texture, FF.COIN_ICON, "coin lines carry the coin icon")
	-- Items goes back to the session's items.
	local back
	for _, b in ipairs(pool.kinds.button) do
		if b.shown ~= false and b.label.text == "Items" then back = b end
	end
	back:GetScript("OnClick")(back)
	detail = ns.Main.ListOf("farm").box.frames[2]
	assert(detail.content.cwPool.kinds.text[1].text ~= "Loot log · 3")
end)


----------------------------------------------------------------------------------------------------
-- Tracker in the Origami look (#158): states, dog-ear, buttons, money, split, links
----------------------------------------------------------------------------------------------------

local function flapOf(f)
	return f.cwSheet.flap.hex
end

local function shownButtons(f)
	local out = {}
	for name, b in pairs(f.buttons.b) do
		if b.shown then out[#out + 1] = name end
	end
	table.sort(out)
	return table.concat(out, ",")
end

it("tracker states: no session, running, paused by hand, paused when idle; dog-ear, word, timer and buttons", function()
	local ns, stub = setup()
	local FF, S = ns.FarmFrame, ns.Style
	SlashCmdList.CRAFTWISE("farm show")
	local f = CraftWiseFarmFrame
	-- No session.
	eq(FF.Last().state, "none")
	eq(flapOf(f), S.C.flap.hex, "flap colour without a session")
	eq(f.word.text, "no session"); eq(f.word.textColor[1], S.C.text3[1])
	eq(f.timer.text, "")
	eq(f.empty.shown, true); eq(f.hero.shown, false); eq(f.split.shown, false); eq(f.loot.shown, false); eq(f.fish.shown, false)
	eq(f.empty.title.text, "Press Start, then loot.")
	eq(f.empty.hint.text, "Or just loot: \"Start on first loot\" is on in Settings.")
	eq(shownButtons(f), "history,start")
	SlashCmdList.CRAFTWISE("farm autostart off")
	eq(f.empty.hint.shown, false, "no hint while Start on first loot is off")
	SlashCmdList.CRAFTWISE("farm autostart on")
	assert(f.height and f.height > 0, "height from content")
	local noneHeight = f.height
	-- Start: running, nothing looted yet.
	f.buttons.b.start:GetScript("OnClick")(f.buttons.b.start)
	eq(FF.Last().state, "running")
	eq(flapOf(f), S.C.live.hex, "orange dog-ear while running")
	eq(f.word.text, "running"); eq(f.word.textColor[1], S.C.live[1])
	eq(f.timer.text, "0:00:00")
	eq(f.hero.value.text, S.Hex("text3") .. "—|r", "no rate under a minute")
	eq(f.loot.nothing.shown, true); eq(f.loot.more.shown, false)
	eq(shownButtons(f), "endAction,pause")
	loot(stub, CLOTH, 2)
	advance(stub, 240)
	FF.Refresh()
	eq(f.timer.text, "0:04:00")
	eq(f.hero.value.text, FF.Coins(26 * 15))
	eq(f.loot.nothing.shown, false)
	assert(f.height > noneHeight, "the running tracker is taller")
	-- Paused by hand.
	f.buttons.b.pause:GetScript("OnClick")(f.buttons.b.pause)
	eq(FF.Last().state, "paused")
	eq(flapOf(f), S.C.ruleStrong.hex, "rule-strong dog-ear while paused")
	eq(f.word.text, "paused"); eq(f.timer.textColor[1], S.C.text2[1])
	assert(f.hero.caption.text:find("total", 1, true), "manual pause keeps the total")
	eq(shownButtons(f), "endLine,resume")
	f.buttons.b.resume:GetScript("OnClick")(f.buttons.b.resume)
	eq(FF.Last().state, "running")
	-- Paused when idle (5 minutes without loot).
	advance(stub, 5 * 60 + 1)
	ns.Farm.Tick()
	eq(FF.Last().state, "idle")
	eq(f.word.text, "paused · idle 5 min")
	eq(f.hero.caption.text, "per hour · resumes with your next loot")
	eq(flapOf(f), S.C.ruleStrong.hex)
	eq(shownButtons(f), "endLine,resume")
	loot(stub, CLOTH, 1)
	eq(FF.Last().state, "running", "the next loot resumes")
	-- End session (action button): back to no session, kept in the history.
	f.buttons.b.endAction:GetScript("OnClick")(f.buttons.b.endAction)
	eq(FF.Last().state, "none"); eq(flapOf(f), S.C.flap.hex); eq(#ns.Farm.History(), 1)
end)

it("tracker: top 5 loot by value, footer '+ N more · M unpriced', the links open Gather › Farm", function()
	local ns, stub = setup()
	local FF = ns.FarmFrame
	local ids = {}
	for i = 1, 7 do
		local id = 5000 + i
		stub.items[id] = { name = "Test Item " .. i, sellPrice = i * 10 }
		ids[i] = id
		loot(stub, id, 1)
	end
	stub.items[5100] = { name = "Unpriced A" }
	stub.items[5101] = { name = "Unpriced B" }
	loot(stub, 5100, 1); loot(stub, 5101, 3)
	FF.Refresh()
	local f = CraftWiseFarmFrame
	local rows = FF.LootRows()
	eq(#FF.Last().loot, 5)
	eq(rows[1].data.itemID, ids[7], "best value first"); eq(rows[5].data.itemID, ids[3])
	eq(FF.Last().more, 4); eq(FF.Last().unpriced, 2)
	eq(f.loot.more.text.text, "+ 4 more · 2 unpriced")
	eq(FF.FooterText({ more = 0, unpriced = 0 }), "")
	-- Log: the open session's row with its log; History: the page; + N more: the row with every item.
	local M = ns.Main
	f.loot.log:GetScript("OnClick")(f.loot.log)
	eq(M.shown.page, "farm")
	local detail = M.ListOf("farm").box.frames[2]
	eq(detail.content.cwPool.kinds.text[1].text, "Loot log · 9")
	f.loot.history:GetScript("OnClick")(f.loot.history)
	eq(M.shown.page, "farm")
	f.loot.more:GetScript("OnClick")(f.loot.more)
	detail = M.ListOf("farm").box.frames[2]
	local text = {}
	for _, fs in ipairs(detail.content.cwPool.kinds.text) do
		if fs.shown ~= false then text[#text + 1] = fs.text end
	end
	assert(table.concat(text, "\n"):find("Items · 9", 1, true), "every item on the row")
end)

it("tracker fishing card: only with catches; catches, per catch, catches per hour, best catch and your usual rate", function()
	local ns, stub = fishSetup()
	local FF, S = ns.FarmFrame, ns.Style
	stub.items[GEM].quality = 2
	loot(stub, ORE, 1)
	FF.Refresh()
	local card = FF.FishCard()
	eq(card.shown, false, "no card without catches")
	local plain = CraftWiseFarmFrame.height
	catch(stub, { { id = GEM } })
	for _ = 1, 2 do
		advance(stub, 40)
		catch(stub, { { id = CLOTH }, { copper = 7 } })
	end
	FF.Refresh()
	eq(card.shown, true)
	assert(CraftWiseFarmFrame.height > plain, "the card adds its height")
	local f = FF.Last().fish
	eq(card.values.catches.text, "3")
	eq(card.values.perCatch.text, FF.Coins(f.perCatch))
	eq(card.values.perHour.text, tostring(math.floor(f.cph + 0.5)))
	assert(card.line.text:find("Best catch: " .. S.Hex("qUncommon") .. "Malachite|r", 1, true), card.line.text)
	assert(card.line.text:find("your usual rate: ", 1, true), card.line.text)
	card.hover:GetScript("OnEnter")(card.hover)
	eq(CraftWiseInverseTip.title.text, "Fishing")
	SlashCmdList.CRAFTWISE("farm reset")
	eq(card.shown, false)
end)

it("tracker pieces: money in coin colours, the timer, split geometry, hover tips", function()
	local ns, stub = setup()
	local FF, S = ns.FarmFrame, ns.Style
	local g, s, c = S.Hex("coinGold"), S.Hex("coinSilver"), S.Hex("coinCopper")
	eq(FF.Coins(164023), ns.FormatCoins(164023), "the shared money format (Money.lua)")
	eq(FF.Coins(164023), g .. "16g|r " .. s .. "40s|r", "at most two units")
	eq(FF.Coins(6620), s .. "66s|r " .. c .. "20c|r")
	eq(FF.Coins(nil), S.Hex("text3") .. "—|r")
	eq(FF.PlainCoins(164023), "16g 40s"); eq(FF.PlainCoins(nil), "—")
	eq(FF.Timer(3600 + 12 * 60 + 40), "1:12:40")
	local geo = FF.SplitGeometry({ 100, 300, 0 }, 228)
	eq(geo[1].x, 0); eq(geo[1].w, 57); eq(geo[2].x, 59); eq(geo[2].w, 169); eq(geo[3].w, 0)
	geo = FF.SplitGeometry({ 1, 1, 1 }, 228)
	eq(geo[1].w + geo[2].w + geo[3].w + 4, 228, "two gaps of 2 units")
	eq(FF.SplitGeometry({ 0, 0, 0 }, 228)[1].w, 0)
	-- The split's AH label turns red with stale prices; hover cells show the inverse tooltip.
	stub.ah[ORE], stub.ahAge[ORE] = 100, 3
	loot(stub, ORE, 2)
	advance(stub, 120)
	FF.Refresh()
	local f = CraftWiseFarmFrame
	eq(f.split.labels[2].textColor[1], S.C.danger[1])
	f.hero.hover:GetScript("OnEnter")(f.hero.hover)
	eq(CraftWiseInverseTip.title.text, "Gold per hour")
	assert(CraftWiseInverseTip.body.text:find("Elwynn Forest", 1, true), "zones in the hero tip")
	f.hero.hover:GetScript("OnLeave")(f.hero.hover)
	FF.OpenList()
	local detail = ns.Main.ListOf("farm").box.frames[2]
	local found = false
	for _, fs in ipairs(detail.content.cwPool.kinds.text) do
		if fs.shown ~= false and fs.text:find(S.Hex("danger") .. "3 d|r", 1, true) then found = true end
	end
	assert(found, "stale AH value carries its age in red")
end)

----------------------------------------------------------------------------------------------------
-- Mini mode (#164) and fade (#163)
----------------------------------------------------------------------------------------------------

local function tick(ns, seconds)
	local d = ns.Style.TweenDriver
	local step = d:GetScript("OnUpdate")
	if step then step(d, seconds) end
end

local function click(b, button)
	b:GetScript("OnClick")(b, button or "LeftButton")
end

-- A checkbox on the Settings page (#157), its group shown.
local function settingsCheck(ns, group, key)
	local M = ns.Main
	M.Open("settings")
	M.Settings.SelectGroup(group)
	return M.Settings.RowOf(group, key).holder.control
end

it("mini mode (#164): the – button makes a 30 tall strip, cut 12; running timer, gold per hour, / h", function()
	local ns, stub = setup()
	local FF, S = ns.FarmFrame, ns.Style
	loot(stub, CLOTH, 2)
	advance(stub, 240)
	FF.Refresh()
	local f = CraftWiseFarmFrame
	eq(FF.IsMini(), false); eq(ns.db.farm.mini, false, "full tracker by default")
	eq(f.full.shown, true); eq(f.mini.shown, false); eq(f.cwSheet.cut, 22)
	click(f.minus)
	eq(FF.IsMini(), true); eq(ns.db.farm.mini, true, "remembered")
	eq(f.full.shown, false); eq(f.mini.shown, true)
	eq(f.height, 30); eq(f.cwSheet.cut, 12)
	eq(flapOf(f), S.C.live.hex, "the corner in the state colour")
	local m = f.mini
	eq(m.timer.shown, true); eq(m.timer.text, "0:04:00"); eq(m.timer.textColor[1], S.C.text2[1])
	eq(m.second.text, FF.Coins(26 * 15)); eq(m.second.fontObject, S.Fonts.FigureBold)
	eq(m.unit.shown, true); eq(m.unit.text, "/ h"); eq(m.unit.textColor[1], S.C.text3[1])
	eq(m.word.shown, false)
	-- stub string width 80: 12 + 80 + 12 + 80 + 12 + 80 + 26
	eq(f.width, 12 + 80 + 12 + 80 + 12 + 80 + 26, "width from content")
	eq(m.timer.points[1][4], 12, "padding left 12")
	advance(stub, 30)
	f:GetScript("OnUpdate")(f, 1)
	eq(m.timer.text, "0:04:30", "the strip ticks like the full tracker")
	-- Click opens the full tracker again; its width and height come back.
	click(m)
	eq(FF.IsMini(), false); eq(ns.db.farm.mini, false)
	eq(f.full.shown, true); eq(f.mini.shown, false); eq(f.width, FF.WIDTH); eq(f.cwSheet.cut, 22)
	assert(f.height > 30, "height from content")
end)

it("mini mode: paused shows Paused and the session total; no session the state word; right-click pauses and resumes", function()
	local ns, stub = setup()
	local FF, S = ns.FarmFrame, ns.Style
	loot(stub, CLOTH, 2)
	advance(stub, 240)
	coin(stub, 100)
	FF.SetMini(true)
	local f = CraftWiseFarmFrame
	local m = f.mini
	click(m, "RightButton")
	eq(ns.Farm.Running(ns.Farm.Current()), false, "right-click pauses")
	eq(FF.IsMini(), true, "right-click keeps the strip")
	eq(flapOf(f), S.C.ruleStrong.hex)
	eq(m.timer.shown, false); eq(m.word.shown, true)
	eq(m.word.text, "Paused"); eq(m.word.textColor[1], S.C.text2[1])
	eq(m.second.shown, true); eq(m.second.text, FF.Coins(126), "the session total")
	eq(m.unit.shown, false)
	eq(f.width, 12 + 80 + 12 + 80 + 26)
	click(m, "RightButton")
	eq(ns.Farm.Running(ns.Farm.Current()), true, "right-click resumes")
	eq(m.timer.shown, true)
	-- Paused when idle reads the same.
	advance(stub, 5 * 60 + 1)
	ns.Farm.Tick()
	eq(FF.Last().state, "idle"); eq(m.word.text, "Paused")
	-- No session: the word alone, flap colour; right-click does nothing.
	SlashCmdList.CRAFTWISE("farm reset")
	eq(FF.Last().state, "none")
	eq(flapOf(f), S.C.flap.hex)
	eq(m.word.text, "no session"); eq(m.word.textColor[1], S.C.text3[1])
	eq(m.second.shown, false); eq(m.unit.shown, false)
	eq(f.width, 12 + 80 + 26)
	click(m, "RightButton")
	eq(ns.Farm.Current(), nil, "nothing to pause without a session")
end)

it("mini mode: drag moves the strip (not a click), lock stops it; mode and position kept across a reload", function()
	local ns, stub = setup()
	local FF = ns.FarmFrame
	loot(stub, CLOTH, 1)
	FF.SetMini(true)
	local f = CraftWiseFarmFrame
	local m = f.mini
	local moved = 0
	f.StartMoving = function() moved = moved + 1 end
	f.GetPoint = function() return "TOPLEFT", UIParent, "BOTTOMLEFT", 300, 700 end
	m:GetScript("OnMouseDown")(m, "LeftButton")
	m:GetScript("OnDragStart")(m)
	m:GetScript("OnDragStop")(m)
	click(m)
	eq(moved, 1); eq(FF.IsMini(), true, "the mouse up after a drag is not a click")
	eq(ns.db.farm.pos.x, 300); eq(ns.db.farm.pos.y, 700)
	m:GetScript("OnMouseDown")(m, "LeftButton")
	click(m)
	eq(FF.IsMini(), false, "a plain click opens the full tracker")
	FF.SetMini(true)
	SlashCmdList.CRAFTWISE("farm lock")
	m:GetScript("OnDragStart")(m)
	eq(moved, 1, "locked: no drag")
	-- Switching keeps the top left corner: the tracker is re-anchored there.
	f.GetLeft = function() return 120 end
	f.GetTop = function() return 640 end
	f.GetPoint = function() return "TOPLEFT", UIParent, "BOTTOMLEFT", 120, 640 end
	FF.SetMini(false)
	local p = f.points[1]
	eq(p[1], "TOPLEFT"); eq(p[3], "BOTTOMLEFT"); eq(p[4], 120); eq(p[5], 640)
	eq(ns.db.farm.pos.point, "TOPLEFT"); eq(ns.db.farm.pos.x, 120)
	-- Saved mode and position come back with the next load.
	local saved = CraftWiseDB
	saved.farm.mini = true
	local ns2 = LoadAddon({ savedDB = saved })
	ns2.FarmFrame.Show()
	local f2 = CraftWiseFarmFrame
	eq(ns2.FarmFrame.IsMini(), true); eq(f2.mini.shown, true); eq(f2.full.shown, false); eq(f2.height, 30)
	local p2 = f2.points[1]
	eq(p2[1], "TOPLEFT"); eq(p2[4], 120); eq(p2[5], 640)
end)

it("mini mode: the Settings switch, Settings shows the mode, hover tips", function()
	local ns, stub = setup()
	local FF = ns.FarmFrame
	loot(stub, CLOTH, 1)
	FF.Refresh()
	local mini = settingsCheck(ns, "farm", "mini")
	eq(mini.checked, false)
	click(mini)
	eq(FF.IsMini(), true); eq(CraftWiseFarmFrame.mini.shown, true)
	click(mini)
	eq(FF.IsMini(), false)
	click(CraftWiseFarmFrame.minus)
	eq(FF.IsMini(), true, "the – button")
	mini = settingsCheck(ns, "farm", "mini")
	eq(mini.checked, true, "Settings shows the mode")
	click(mini)
	eq(FF.IsMini(), false)
	-- Hover tips: the – button and the strip.
	local f = CraftWiseFarmFrame
	f.minus:GetScript("OnEnter")(f.minus)
	eq(CraftWiseInverseTip.title.text, "Mini mode")
	f.minus:GetScript("OnLeave")(f.minus)
	FF.SetMini(true)
	f.mini:GetScript("OnEnter")(f.mini)
	eq(CraftWiseInverseTip.title.text, "Farm")
	assert(CraftWiseInverseTip.body.text:find("Right-click: pause / resume", 1, true), CraftWiseInverseTip.body.text)
	f.mini:GetScript("OnLeave")(f.mini)
	eq(CraftWiseInverseTip.shown, false)
end)

it("fade (#163): off by default; on, the tracker sits at 40 % away from the mouse and returns on hover in 140 ms", function()
	local ns, stub = setup()
	local FF = ns.FarmFrame
	loot(stub, CLOTH, 1)
	local f = CraftWiseFarmFrame
	eq(ns.db.farm.fade, false, "off by default")
	f.mouseOver = false
	f:GetScript("OnLeave")(f)
	tick(ns, 1)
	eq(FF.Alpha(), 1, "no fade while the setting is off")
	-- On, from Settings › Look.
	local fade = settingsCheck(ns, "look", "fade")
	eq(fade.checked, false)
	click(fade)
	eq(ns.db.farm.fade, true)
	eq(FF.Alpha(), 1, "starts from 100 %")
	tick(ns, 0.07)
	assert(math.abs(FF.Alpha() - 0.7) < 0.01, "half way after 70 ms: " .. FF.Alpha())
	tick(ns, 0.07)
	eq(FF.Alpha(), 0.4); eq(f.alpha, 0.4)
	-- Hover: back to 100 % in 140 ms.
	f.mouseOver = true
	f:GetScript("OnEnter")(f)
	tick(ns, 0.14)
	eq(f.alpha, 1)
	-- Leaving the frame into one of its children (a row, a button) is still hovering.
	f:GetScript("OnLeave")(f)
	tick(ns, 0.14)
	eq(f.alpha, 1, "still over the tracker")
	-- Leaving through a child doesn't fire the frame's OnLeave: the per-frame check sees it.
	f.mouseOver = false
	f:GetScript("OnUpdate")(f, 0.016)
	tick(ns, 0.14)
	eq(f.alpha, 0.4)
	-- Off again: 100 %, whatever the mouse does.
	click(fade)
	eq(ns.db.farm.fade, false)
	tick(ns, 0.14)
	eq(f.alpha, 1)
	f:GetScript("OnLeave")(f)
	f:GetScript("OnUpdate")(f, 0.016)
	tick(ns, 0.14)
	eq(f.alpha, 1)
end)

it("fade: covers the mini strip too, and a tracker shown away from the mouse starts faded", function()
	local ns, stub = setup()
	local FF = ns.FarmFrame
	loot(stub, CLOTH, 1)
	local f = CraftWiseFarmFrame
	FF.SetFade(true)
	FF.SetMini(true)
	f.mouseOver = false
	f:GetScript("OnLeave")(f)
	tick(ns, 0.14)
	eq(f.alpha, 0.4, "the strip fades")
	-- Over the strip (the mini button covers the frame, so the frame reports the mouse over it).
	f.mouseOver = true
	f:GetScript("OnUpdate")(f, 0.016)
	tick(ns, 0.14)
	eq(f.alpha, 1, "hovering the strip")
	f.mouseOver = false
	f:GetScript("OnUpdate")(f, 0.016)
	tick(ns, 0.05)
	assert(f.alpha < 1 and f.alpha > 0.4, "fading: " .. f.alpha)
	-- Back to full mid-fade: the fade goes on to 40 %.
	click(f.mini)
	tick(ns, 0.14)
	eq(f.alpha, 0.4); eq(f.full.shown, true)
	-- Hide and show away from the mouse: faded at once.
	FF.SetFade(false)
	tick(ns, 0.14)
	eq(f.alpha, 1)
	SlashCmdList.CRAFTWISE("farm hide")
	ns.db.farm.fade = true
	SlashCmdList.CRAFTWISE("farm show")
	eq(f.alpha, 0.4, "shown faded, no flash at 100 %")
end)
