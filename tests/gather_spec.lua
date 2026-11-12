-- Gather section of the main window (#156; spec #150 "Gather: Farm, Fishing, Crates", boards "Gather ›
-- Farm", "Gather › Fishing", "Gather › Crates"): the hero card with and without a running session, the
-- session rows and what they open into, the loot log in place, removing an item, the farm tracker's links,
-- fishing spots with the chips, the rate line and the own-catch minimum, the fishing log, the crates' cards,
-- notes and rows, and the empty states. Invented items, zones, prices and catches only.
local T0 = 1794000000
local ORE, CLOTH, HIDE, GEM = 990301, 990302, 990303, 990304
local SNAPPER, EEL, BOOT, RAG = 990401, 990402, 990403, 990404
local CRATE_A, CRATE_B, BAR_A, BAR_B = 990501, 990502, 990503, 990504
local OPEN_OBJ, POOL_OBJ, SEEN_POOL = 990601, 990602, 990603
local FAVOR = 3402

local function setup(opts)
	local ns, stub = LoadAddon(opts or { auctionator = true })
	LOOT_ITEM_SELF = "You receive loot: %s."
	LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d."
	stub.items[ORE] = { name = "Testite Ore", sellPrice = 5 }
	stub.items[CLOTH] = { name = "Testweave Cloth", sellPrice = 13 }
	stub.items[HIDE] = { name = "Test Hide" } -- no price anywhere
	stub.items[GEM] = { name = "Test Gem", sellPrice = 25, quality = 2 }
	stub.names.player, stub.realm = "Testperson", "Testrealm"
	stub.clock = T0
	time = function(t)
		if t then return os.time(t) end
		return stub.clock
	end
	stub.printed = {}
	ns.Print = function(m) stub.printed[#stub.printed + 1] = m end
	stub.zone = "Testwood"
	stub.money = 0
	stub.Fire("PLAYER_ENTERING_WORLD")
	return ns, stub
end

local function loot(stub, id, count)
	local name = stub.items[id].name
	local l = ("|cffffffff|Hitem:%d::::::::20:::::|h[%s]|h|r"):format(id, name)
	local text = count and count > 1 and LOOT_ITEM_SELF_MULTIPLE:format(l, count) or LOOT_ITEM_SELF:format(l)
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

local function has(text, s) assert(tostring(text):find(s, 1, true), ("missing %q in:\n%s"):format(s, tostring(text))) end

-- The ScrollBox's frames (the stub builds every element): rows and opened parts in order.
local function frames(M, key) return M.ListOf(key).box.frames end
local function rowFrame(M, key, rowKey)
	for _, fr in ipairs(frames(M, key)) do
		if not fr.elementData.open and M.RowKey(fr.elementData.row) == rowKey then return fr end
	end
end
local function opened(M, key)
	for _, fr in ipairs(frames(M, key)) do
		if fr.elementData.open then return fr end
	end
end
-- Texts shown in an opened row's card, in the order they were drawn.
local function texts(fr)
	local out = {}
	for _, fs in ipairs(fr.content.cwPool.kinds.text or {}) do
		if fs.shown ~= false then out[#out + 1] = fs.text end
	end
	return table.concat(out, "\n")
end
local function button(fr, label)
	for _, b in ipairs(fr.content.cwPool.kinds.button or {}) do
		if b.shown ~= false and b.label.text == label then return b end
	end
end
local function cellText(fr, i) return fr.cells[i] and fr.cells[i].text end

-- Two finished sessions and an open one; the newer finished one keeps its log.
local function sessions(ns, stub)
	local F = ns.Farm
	SlashCmdList.CRAFTWISE("farm idle 0")
	stub.ah[ORE], stub.ahAge[ORE] = 100, 0 -- 95 after the cut
	loot(stub, ORE, 2)
	advance(stub, 1800)
	coin(stub, 300)
	F.Reset(stub.clock) -- older: 30 min
	advance(stub, 600)
	stub.zone = "Testmarsh"
	loot(stub, CLOTH, 4)
	loot(stub, HIDE, 1)
	advance(stub, 3600)
	F.Reset(stub.clock) -- newer: 1 h, unpriced hide
	advance(stub, 600)
	loot(stub, ORE, 3)
	loot(stub, GEM, 1)
	loot(stub, HIDE, 2)
	advance(stub, 120)
	coin(stub, 60)
end

----------------------------------------------------------------------------------------------------
-- Farm
----------------------------------------------------------------------------------------------------

it("Farm: the Gather pages are real pages in their order, after the bridges in the TOC", function()
	local _, _, M = (function() local ns, stub = setup(); return ns, stub, ns.Main end)()
	local labels = {}
	for _, p in ipairs(M.SectionPages("gather")) do
		labels[#labels + 1] = p.label
		eq(p.bridge, nil, p.key .. " is no bridge")
	end
	eq(table.concat(labels, ","), "Farm,Fishing,Crates")
	local toc = io.open("CraftWise/CraftWise.toc"):read("*a")
	local b = toc:find("UI\\Main\\Pages\\Bridges.lua", 1, true)
	for _, page in ipairs({ "Farm", "Fishing", "Crates" }) do
		local at = toc:find("UI\\Main\\Pages\\" .. page .. ".lua", 1, true)
		assert(at and at > b, page .. " after Bridges.lua")
	end
	for _, gone in ipairs({ "UI\\ProfitFrame\\Fishing.lua", "UI\\Records\\Crates.lua", "UI\\Records\\FishingLog.lua" }) do
		eq(toc:find(gone, 1, true), nil, gone .. " is gone")
	end
end)

it("Farm: no session: the hero says so with Start; the list's empty line says what to do", function()
	local ns, stub = setup()
	local M, S = ns.Main, ns.Style
	M.Open("farm")
	local f = M.Frame()
	eq(M.shown.page, "farm"); eq(M.shown.state, "list")
	eq(f.hero.name.text, "No session running"); eq(f.hero.name.fontObject, S.Fonts.Hero)
	eq(f.hero.label.textColor[1], S.C.text3[1]); eq(f.hero.sheet.flap.hex, S.C.cardFlap.hex)
	local area = M.SlotsOf("farm").hero.cw
	eq(area.start.shown, true); eq(area.open.shown, false)
	eq(area.cols[1].label.shown, false)
	local list = M.ListOf("farm")
	eq(#list.rows, 0); eq(list.empty.shown, true)
	has(list.empty.text, "End one in the farm tracker")
	eq(f.foot.right.text, "0 of 50 kept")
	-- Start starts a session; the hero turns orange.
	area.start:GetScript("OnClick")(area.start)
	assert(ns.Farm.Current(), "a session")
	eq(f.hero.label.text, "Running now · 0:00:00"); eq(f.hero.label.textColor[1], S.C.live[1])
	eq(f.hero.sheet.flap.hex, S.C.live.hex)
	eq(#M.ListOf("farm").rows, 1, "the open session is a row")
end)

it("Farm: running hero (timer, gold per hour, coin / items at AH / vendor only, Open tracker), rows on one rail scale", function()
	local ns, stub = setup()
	local M, S, FF, FH = ns.Main, ns.Style, ns.FarmFrame, ns.FarmHistory
	sessions(ns, stub)
	M.Open("farm")
	local f = M.Frame()
	local t = ns.Farm.Totals(ns.Farm.Current(), stub.clock)
	eq(f.hero.label.text, "Running now · 0:02:00")
	eq(f.hero.name.text, FF.Coins(t.gph)); eq(f.hero.name.fontObject, S.Fonts.FigureL)
	has(f.hero.sub.text, "per hour · total"); has(f.hero.sub.text, "Testmarsh")
	local area = M.SlotsOf("farm").hero.cw
	eq(area.cols[1].figure.text, FF.Coins(60)); eq(area.cols[2].figure.text, FF.Coins(285))
	eq(area.cols[3].figure.text, FF.Coins(25)); eq(area.open.shown, true); eq(area.start.shown, false)
	eq(area.note.text, "Pause · End in the tracker")
	FF.Hide()
	area.open:GetScript("OnClick")(area.open)
	eq(FF.IsShown(), true, "Open tracker")
	-- The clock moves the hero without a refresh of the list.
	advance(stub, 60)
	ns.GatherFarm.Tick()
	eq(f.hero.label.text, "Running now · 0:03:00")
	-- Rows: the open session on top, then finished ones newest first.
	local list = M.ListOf("farm")
	eq(#list.rows, 3)
	eq(list.rows[1].key, FH.CURRENT); eq(list.rows[2].zone, "Testmarsh"); eq(list.rows[3].zone, "Testwood")
	local cur = rowFrame(M, "farm", FH.CURRENT)
	eq(cur.cells[1].textColor[1], S.C.live[1], "Started in orange while it runs")
	eq(cur.cells[3].text, "0:02")
	local older = rowFrame(M, "farm", list.rows[3].key)
	eq(cellText(older, 3), "0:30"); eq(cellText(older, 5), FF.Coins(190 + 300))
	eq(cellText(older, 6), FF.Coins(ns.Farm.History()[2].gph))
	eq(cellText(older, 1), FH.Started(ns.Farm.History()[2].start))
	-- One shared rail scale: the largest gold per hour fills it.
	local max = 0
	for _, r in ipairs(list.rows) do max = math.max(max, r.gph or 0) end
	for _, r in ipairs(list.rows) do eq(r.railMax, max) end
	local rail = older.rails[4]
	eq(rail.shown, true); eq(rail.spec.value, ns.Farm.History()[2].gph); eq(rail.spec.max, max)
	-- Sorting keeps the open session on top.
	list.headers[6]:GetScript("OnClick")(list.headers[6])
	eq(M.ListOf("farm").rows[1].key, FH.CURRENT)
	eq(list.headers[6].label.text, "Per hour " .. S.Glyph("down", 10, "text"))
	-- The sub bar names the tracker's key binding.
	eq(M.SlotsOf("farm").tools.shown, true)
	-- Paused: the hero in text2 with the rule-strong dog-ear.
	SlashCmdList.CRAFTWISE("farm pause")
	has(f.hero.label.text, "Paused · "); eq(f.hero.label.textColor[1], S.C.text2[1]); eq(f.hero.sheet.flap.hex, S.C.ruleStrong.hex)
	-- Other pages get the hero back as it was.
	M.ShowPage("crates")
	eq(M.SlotsOf("crates").hero.cards ~= nil, true)
	eq(M.SlotsOf("farm").hero.shown, false, "the farm's hero slot hides on other pages")
	M.ShowPage("farm")
	eq(f.hero.name.fontObject, S.Fonts.FigureL)
end)

it("Farm: a finished row opens in place (top items, zones, split, lines kept); Loot log shows the log there", function()
	local ns, stub = setup()
	local M, FF = ns.Main, ns.FarmFrame
	sessions(ns, stub)
	M.Open("farm")
	local key = M.ListOf("farm").rows[2].key
	local fr = rowFrame(M, "farm", key)
	fr:GetScript("OnClick")(fr, "LeftButton")
	local d = opened(M, "farm")
	eq(d.elementData.row.key, key)
	local text = texts(d)
	has(text, "Top items"); has(text, "Testweave Cloth"); has(text, "×4")
	has(text, "Zones"); has(text, "Testmarsh"); has(text, "Split")
	has(text, "AH " .. FF.Coins(0)); has(text, "1 unpriced")
	has(text, "2 loot lines kept")
	eq(d.extent, ns.GatherFarm.OpenHeight(d.elementData.row, M.Context(M.Page("farm"))) + 20 + 8, "measured as drawn")
	-- Loot log in place, newest first; Summary goes back.
	button(d, "Loot log"):GetScript("OnClick")(button(d, "Loot log"))
	d = opened(M, "farm")
	text = texts(d)
	has(text, "Loot log · 2")
	local first = text:find("Test Hide", 1, true)
	local last = text:find("Testweave Cloth", 1, true)
	assert(first and last and first < last, "newest first")
	button(d, "Summary"):GetScript("OnClick")(button(d, "Summary"))
	has(texts(opened(M, "farm")), "Top items")
	-- An older session past HISTORY_LOGS keeps only its line count.
	local h = ns.Farm.History()[2]
	h.logLines, h.log, h.logZones = #h.log, nil, nil
	M.Refresh()
	local older = rowFrame(M, "farm", M.ListOf("farm").rows[3].key)
	older:GetScript("OnClick")(older, "LeftButton")
	d = opened(M, "farm")
	has(texts(d), "loot log not kept"); eq(button(d, "Loot log"), nil)
end)

it("Farm: the open session's row lists every item; × removes one from the session", function()
	local ns, stub = setup()
	local M, FH = ns.Main, ns.FarmHistory
	sessions(ns, stub)
	M.Open("farm")
	local fr = rowFrame(M, "farm", FH.CURRENT)
	fr:GetScript("OnClick")(fr, "LeftButton")
	local d = opened(M, "farm")
	local text = texts(d)
	has(text, "Items · 3"); has(text, "Testite Ore ")
	has(text, ns.Style.Hex("text3") .. "no price|r")
	local x = button(d, "×")
	x:GetScript("OnEnter")(x)
	eq(CraftWiseInverseTip.title.text, "Remove from this session")
	x:GetScript("OnClick")(x)
	eq(ns.Farm.Counts(ns.Farm.Current())[ORE], nil, "removed (the best value was first)")
	d = opened(M, "farm")
	has(texts(d), "Items · 2")
	-- Item lines show the item's tooltip and open the item menu.
	local menus = {}
	ns.ShowItemMenu = function(id) menus[#menus + 1] = id end
	local hits = d.content.cwPool.kinds.hit
	local hit
	for _, h in ipairs(hits) do if h.shown ~= false and h.cwData.itemID then hit = h end end
	hit:GetScript("OnClick")(hit, "RightButton")
	eq(#menus, 1)
end)

it("Farm: the tracker's Log, + N more and History open Gather › Farm (the open session with its log or its items)", function()
	local ns, stub = setup()
	local M, FF, FH = ns.Main, ns.FarmFrame, ns.FarmHistory
	sessions(ns, stub)
	FF.Refresh()
	local f = CraftWiseFarmFrame
	f.loot.log:GetScript("OnClick")(f.loot.log)
	eq(M.Frame():IsShown(), true); eq(M.shown.page, "farm")
	local d = opened(M, "farm")
	eq(d.elementData.row.key, FH.CURRENT); has(texts(d), "Loot log · 4")
	f.loot.more:GetScript("OnClick")(f.loot.more)
	d = opened(M, "farm")
	eq(d.elementData.row.key, FH.CURRENT); has(texts(d), "Items · 3")
	M.ShowPage("crates")
	f.loot.history:GetScript("OnClick")(f.loot.history)
	eq(M.shown.page, "farm")
	-- No session: the tracker's History button.
	SlashCmdList.CRAFTWISE("farm reset")
	M.Frame():Hide()
	f.buttons.b.history:GetScript("OnClick")(f.buttons.b.history)
	eq(M.Frame():IsShown(), true); eq(M.shown.page, "farm")
	-- FH.Open (Settings button) opens a finished session.
	FH.Open(2)
	eq(opened(M, "farm").elementData.row.index, 2)
end)

it("Farm: row data stays apart from drawing (FH.ListRows / FH.SessionRow / FH.Detail are plain values)", function()
	local ns, stub = setup()
	local FH = ns.FarmHistory
	sessions(ns, stub)
	local rows = FH.ListRows(ns.Farm.History())
	eq(rows[1].time, "1:00"); eq(rows[1].zone, "Testmarsh"); eq(rows[1].total, 52); eq(rows[1].unknown, 1)
	eq(rows[2].time, "0:30"); eq(rows[2].coin, 300); eq(rows[2].items, 190)
	local cur = FH.SessionRow(ns.Farm.Current(), stub.clock)
	eq(cur.state, "running"); eq(cur.time, "0:02"); eq(cur.coin, 60)
	local d = FH.Detail(ns.Farm.History()[1])
	eq(d.top[1].itemID, CLOTH); eq(d.zones[1].zone, "Testmarsh"); eq(d.split.unknown, 1); eq(#d.log, 2)
	eq(FH.Duration(3600 + 48 * 60), "1:48")
	eq(FH.Started(T0), ("%s %d · %s"):format(date("%a", T0), tonumber(date("%d", T0)), date("%H:%M", T0)))
	eq(FH.SessionRow(nil), nil)
end)

----------------------------------------------------------------------------------------------------
-- Fishing
----------------------------------------------------------------------------------------------------

local function fishSetup()
	local ns, stub = setup()
	stub.items[SNAPPER] = { name = "Test Snapper", sellPrice = 10, quality = 1 }
	stub.items[EEL] = { name = "Test Eel", sellPrice = 100, quality = 1 }
	stub.items[BOOT] = { name = "Test Boot", sellPrice = 2, quality = 0 }
	stub.items[RAG] = { name = "Test Rag", sellPrice = 1, quality = 0 }
	ns.charDB.professions[356] = { name = "Fishing", skill = 225, maxSkill = 300, recipes = {} }
	ns.db.fishing[ns.CharKey()] = { catches = {}, opened = {}, seen = {} }
	return ns, stub
end

-- n catches in a zone `step` seconds apart (one session), from an open-water or pool source.
local function catches(ns, stub, zone, n, items, water, step)
	local log = ns.db.fishing[ns.CharKey()]
	for i = 1, n do
		local c = { t = stub.clock, zone = zone, sub = "", items = items }
		if water == "open" then
			c.obj, c.same = OPEN_OBJ, true
		elseif water == "pool" then
			c.obj, c.spawn = POOL_OBJ, "S1"
		end
		log.catches[#log.catches + 1] = c
		stub.clock = stub.clock + (step or 20)
	end
	ns.Fishing.kinds = nil
end

local function reference()
	CraftWise_FishingRef = { version = 1, generated = "2026-11-11", containers = {}, pools = {}, zones = {
		{ id = 1, name = "Testwater Bay", total = 200, items = {
			{ id = SNAPPER, count = 120, stack = { 1, 1 } }, { id = EEL, count = 60, stack = { 1, 3 } },
			{ id = BOOT, count = 10, stack = { 1, 1 } }, { id = RAG, count = 10, stack = { 1, 1 } } } },
		{ id = 2, name = "Dull Pond", total = 100, items = { { id = SNAPPER, count = 100, stack = { 1, 1 } } } },
	} }
end

it("Fishing: Spots ranks zones by value per catch × your catch rate; the line names the rate; ~ under the minimum", function()
	local ns, stub = fishSetup()
	local M, S, FF = ns.Main, ns.Style, ns.FarmFrame
	reference()
	ns.db.settings.fishingOwnMin = 5
	catches(ns, stub, "Dull Pond", 3, { [SNAPPER] = 1 }, "open", 20) -- 2 timed catches in 40 s: 180/h, too few
	M.Open("fishing")
	eq(M.shown.page, "fishing"); eq(M.shown.state, "list")
	local f = M.Frame()
	eq(f.hero.shown, false, "no hero card on Fishing (board)")
	eq(f.listBar.title.text, "Where to fish")
	has(f.listBar.note.text, "gold per hour = value per catch × your catch rate (~180 catches/h from 2 of 5 timed catches)")
	has(f.listBar.note.text, "Fishing 225")
	local list = M.ListOf("fishing")
	eq(#list.rows, 2)
	local bay, pond = list.rows[1], list.rows[2]
	eq(bay.name, "Testwater Bay"); eq(bay.source, "ref")
	-- Per catch 0.6 x 10 + 0.3 x 1-3 x 100 + junk 0.05 x 2 + 0.05 x 1 = 36.15 .. 96.15 -> 36 .. 96.
	eq(bay.perCatch, 36); eq(bay.perCatchHigh, 96)
	eq(bay.gph, 36 * 180); eq(bay.gphHigh, 96 * 180); eq(bay.estimate, true)
	local bf = rowFrame(M, "fishing", bay.key)
	eq(cellText(bf, 2), "0"); eq(bf.cells[2].textColor[1], S.C.text3[1], "grey under the own-catch minimum")
	eq(cellText(bf, 5), "~" .. FF.Coins(36 * 180))
	local rail = bf.rails[3]
	eq(rail.spec.point, true); eq(rail.spec.low, 36 * 180); eq(rail.spec.high, 96 * 180); eq(rail.spec.max, 96 * 180)
	eq(rail.range.shown, true); eq(rail.tick.shown, true); eq(rail.bar.shown, false)
	eq(pond.own, 3); eq(pond.source, "ref", "3 own catches < 5: the reference shows")
	has(f.foot.left.text, "fewer than 5 of your own catches"); has(f.foot.right.text, "reference: loaded (2026-11-11)")
	-- From the minimum on: own data, white count, no "~".
	catches(ns, stub, "Dull Pond", 5, { [SNAPPER] = 1 }, "open", 20)
	M.Refresh()
	list = M.ListOf("fishing")
	pond = list.rows[1].name == "Dull Pond" and list.rows[1] or list.rows[2]
	eq(pond.own, 8); eq(pond.source, "own"); eq(pond.estimate, nil)
	local pf = rowFrame(M, "fishing", pond.key)
	eq(pf.cells[2].textColor[1], S.C.text[1])
	has(f.listBar.note.text, "(180 catches/h, your last 90 days)")
end)

it("Fishing: a zone opens into its fish (share of catches, share of money, each), junk as one line, source switch", function()
	local ns, stub = fishSetup()
	local M = ns.Main
	reference()
	catches(ns, stub, "Testwater Bay", 3, { [EEL] = 1 }, "open")
	M.Open("fishing")
	local bay = rowFrame(M, "fishing", "testwater bay")
	bay:GetScript("OnClick")(bay, "LeftButton")
	local d = opened(M, "fishing")
	local text = texts(d)
	has(text, "Reference · n = 200 recorded loots")
	has(text, "Share of catches"); has(text, "Share of money")
	has(text, "Test Eel"); has(text, "Junk: ")
	has(text, "Test Boot"); has(text, "Test Rag")
	-- Shares of catches: snapper 0.6, eel 0.3, junk 0.1 of 1.0 units per catch.
	has(text, "60%"); has(text, "30%"); has(text, "10%")
	local lines = ns.GatherFishing.FishLines(d.elementData.row.zone.side)
	eq(#lines, 3); eq(lines[3].junk, true)
	eq(math.floor(lines[1].moneyShare * 100 + 0.5), math.floor(30 / 36 * 100 + 0.5), "the eel brings most of the money")
	-- The other side.
	local b = button(d, "Show own catches")
	b:GetScript("OnClick")(b)
	d = opened(M, "fishing")
	has(texts(d), "Own catches · n = 3"); has(texts(d), "100%")
	assert(button(d, "Show reference"), "and back")
end)

it("Fishing: no catch rate yet: Per hour says why; water chips filter own catches and pick that water's rate", function()
	local ns, stub = fishSetup()
	local M, S = ns.Main, ns.Style
	reference()
	M.Open("fishing")
	local list = M.ListOf("fishing")
	eq(list.rows[1].gph, nil)
	has(M.Frame().listBar.note.text, "no catch rate yet")
	local fr = rowFrame(M, "fishing", list.rows[1].key)
	eq(cellText(fr, 5), S.Hex("text3") .. "—|r")
	local chips = M.SlotsOf("fishing").tools.chips
	eq(#chips, 5)
	local labels = {}
	for _, c in ipairs(chips) do labels[#labels + 1] = c.label.text end
	eq(table.concat(labels, ","), "Spots,Log,All water,Pools,Open water")
	eq(chips[1].on, true); eq(chips[3].on, true)
	-- Pools: own pool catches only, the pool rate.
	catches(ns, stub, "Testwater Bay", 4, { [EEL] = 1 }, "pool", 30)
	catches(ns, stub, "Dull Pond", 4, { [SNAPPER] = 1 }, "open", 10)
	chips[4]:GetScript("OnClick")(chips[4])
	eq(ns.db.settings.ui.gather.fishWater, "pool"); eq(chips[4].on, true); eq(chips[3].on, false)
	list = M.ListOf("fishing")
	local bay, pond
	for _, r in ipairs(list.rows) do
		if r.name == "Testwater Bay" then bay = r else pond = r end
	end
	eq(bay.own, 4); eq(pond.own, 0, "open-water catches leave the count")
	has(M.Frame().listBar.note.text, "120 catches/h in pools")
	chips[3]:GetScript("OnClick")(chips[3])
	eq(ns.db.settings.ui.gather.fishWater, nil)
end)

it("Fishing: Log lists catches per zone, subzone and water, pool visits and pools only seen; Find Fish in the footer", function()
	local ns, stub = fishSetup()
	local M = ns.Main
	catches(ns, stub, "Testwater Bay", 3, { [EEL] = 1, [BOOT] = 1 }, "pool", 20)
	catches(ns, stub, "Dull Pond", 2, { [SNAPPER] = 2 }, "open", 20)
	local log = ns.db.fishing[ns.CharKey()]
	log.seen[#log.seen + 1] = { t = stub.clock, obj = SEEN_POOL, zone = "Dull Pond", sub = "", spawn = "Z9" }
	ns.db.fishObjects[SEEN_POOL] = { name = "Test School", t = stub.clock }
	ns.db.fishObjects[POOL_OBJ] = { name = "Test Pool", t = stub.clock }
	-- Another character fished that school (so it is known as a pool); this one only saw it.
	ns.db.fishing["Testrealm-Other"] = { catches = {
		{ t = stub.clock, zone = "Dull Pond", sub = "", items = { [SNAPPER] = 1 }, obj = SEEN_POOL, spawn = "Z1" },
		{ t = stub.clock, zone = "Dull Pond", sub = "", items = { [SNAPPER] = 1 }, obj = SEEN_POOL, spawn = "Z1" },
	}, opened = {}, seen = {} }
	ns.Fishing.kinds = nil
	M.Open("fishing")
	local chips = M.SlotsOf("fishing").tools.chips
	chips[2]:GetScript("OnClick")(chips[2])
	eq(ns.db.settings.ui.gather.fishMode, "log"); eq(chips[2].on, true)
	local f = M.Frame()
	eq(f.listBar.title.text, "Fishing log")
	has(f.listBar.note.text, "last 90 days · 5 catches · sessions: catches less than 5 min apart")
	has(f.foot.left.text, "Find Fish")
	local list = M.ListOf("fishing")
	eq(list.headers[2].label.text, "Where")
	eq(list.rows[1].catches, 3, "most catches first")
	local pool = list.rows[1]
	eq(pool.water, "pool"); has(pool.waterLabel, "Test Pool")
	local seen
	for _, r in ipairs(list.rows) do if r.catches == 0 then seen = r end end
	assert(seen, "a pool only seen keeps a line"); has(seen.name, "Test School")
	local fr = rowFrame(M, "fishing", pool.key)
	fr:GetScript("OnClick")(fr, "LeftButton")
	local text = texts(opened(M, "fishing"))
	has(text, "Visits: "); has(text, "Test Eel"); has(text, "×3")
	-- Back to Spots: the default sort of that mode.
	chips[1]:GetScript("OnClick")(chips[1])
	eq(M.Sort(M.Page("fishing")), "gph")
end)

it("Fishing: empty states say what to do (no catches and no reference; no catches in the log)", function()
	local ns = fishSetup()
	local M = ns.Main
	CraftWise_FishingRef = nil
	M.Open("fishing")
	local list = M.ListOf("fishing")
	eq(#list.rows, 0); eq(list.empty.shown, true)
	has(list.empty.text, "No catches yet and no reference loaded")
	has(M.Frame().foot.right.text, "reference: not loaded")
	ns.GatherFishing.SetMode("log")
	eq(list.empty.shown, true); has(list.empty.text, "No catches in the last 90 days.")
	ns.GatherFishing.SetWater("pool")
	has(list.empty.text, "No pool catches in the last 90 days.")
end)

----------------------------------------------------------------------------------------------------
-- Crates
----------------------------------------------------------------------------------------------------

local function crateSetup()
	local ns, stub = setup()
	stub.items[CRATE_A] = { name = "Waylaid Crate: Test Bars" }
	stub.items[CRATE_B] = { name = "Waylaid Crate: Test Cloth" }
	stub.items[BAR_A] = { name = "Test Bar" }
	stub.items[BAR_B] = { name = "Test Bolt" }
	stub.favor = { name = "Merchant's Favor", quantity = 42, maxQuantity = 0, totalEarned = 50 }
	C_CurrencyInfo = { GetCurrencyInfo = function(id) if id == FAVOR then return stub.favor end end }
	stub.bags = { [0] = {} }
	return ns, stub
end

it("Crates: two cards, rows by cost per Favor with measured / tooltip notes, no price, the rail; Favor in the sub bar", function()
	local ns, stub = crateSetup()
	local M, S, FF = ns.Main, ns.Style, ns.FarmFrame
	M.Open("crates")
	local f = M.Frame()
	eq(M.shown.state, "list")
	has(M.ListOf("crates").empty.text, "No Waylaid crate seen yet")
	eq(f.hero.sheet.pieces.a.shown, false, "a bare hero: the page draws two cards")
	local cards = M.SlotsOf("crates").hero.cards
	eq(cards[1].label.text, "Best of the crates you hold"); eq(cards[1].name.text, "None priced")
	eq(cards[2].label.text, "Best to buy and fill")
	-- Two crates: A measured at turn-ins and held, B from its tooltip with no bundle price.
	ns.db.crates[CRATE_A] = { name = "Waylaid Crate: Test Bars", label = "Test Bars", fill = { { n = 10, name = "Test Bar", id = BAR_A } },
		got = { { n = 10, t = T0 }, { n = 10, t = T0 } } }
	ns.db.crates[CRATE_B] = { name = "Waylaid Crate: Test Cloth", label = "Test Cloth", fill = { { n = 5, name = "Test Bolt", id = BAR_B } },
		reward = 8 }
	ns.db.vendor[BAR_A] = 50
	stub.ah[CRATE_A], stub.ah[CRATE_B] = 2000, 1000
	stub.bags[0] = { { itemID = CRATE_A, stackCount = 2 } }
	stub.Fire("BAG_UPDATE_DELAYED")
	M.Refresh()
	local list = M.ListOf("crates")
	eq(#list.rows, 2)
	local a, b = list.rows[1], list.rows[2]
	eq(a.itemID, CRATE_A); eq(a.note, "10 Favor · measured"); eq(b.note, "8 Favor · tooltip")
	local fa, fb = rowFrame(M, "crates", CRATE_A), rowFrame(M, "crates", CRATE_B)
	eq(fa.cwNote.text, "10 Favor · measured"); eq(fa.cwNote.shown, true)
	eq(cellText(fa, 6), "2"); eq(cellText(fb, 6), "0")
	eq(cellText(fb, 4), S.Hex("text3") .. "no price|r", "a fill without bundle prices")
	eq(cellText(fb, 7), S.Hex("text3") .. "—|r")
	eq(fa.rails[5].spec.value, a.perFavor); eq(fa.rails[5].spec.max, a.perFavor)
	eq(cellText(fa, 7), FF.Coins(math.floor(a.perFavor + 0.5)))
	-- Cards.
	cards = M.SlotsOf("crates").hero.cards
	eq(cards[1].name.text, "Waylaid Crate: Test Bars"); has(cards[1].sub.text, "per Merchant's Favor")
	eq(cards[2].name.text, "Waylaid Crate: Test Bars")
	-- Favor on this character, sub bar right.
	eq(M.SlotsOf("crates").tools.balance.text, "Merchant's Favor on this character: " .. S.Hex("text") .. "42|r")
	-- A row opens into its bundles, reward and what is missing.
	fb:GetScript("OnClick")(fb, "LeftButton")
	local text = texts(opened(M, "crates"))
	has(text, "Bundles"); has(text, "5 Test Bolt"); has(text, "from the tooltip"); has(text, "Missing")
	fa = rowFrame(M, "crates", CRATE_A)
	fa:GetScript("OnClick")(fa, "LeftButton")
	has(texts(opened(M, "crates")), "seen at 2 turn-ins")
	has(texts(opened(M, "crates")), "fill only")
end)
