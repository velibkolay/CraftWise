-- Issue #137: every feature reachable from the UI. The Records window (market, where to buy, snapshot; ledger
-- and auctions moved to Sell, #155: tests/sell_pages_spec.lua; crates and the fishing log to Gather, #156:
-- tests/gather_spec.lua), its view models, the main window's Records button, the item menu entries, the
-- Settings toggles, and the slash commands still working.
local NOW = os.time({ year = 2026, month = 11, day = 12, hour = 15 })
local DAY = 86400
local HORDE, BOOTY = "PvP|H", "PvP|N:BootyBay"
local LINEN, SALT, BOOTS, CRATE, COPPER, FISH = 2589, 4289, 400, 7001, 2840, 9001

local function Load(opts)
	local ns, stub = LoadAddon(opts)
	stub.clock = NOW
	time = function(t)
		if t then return os.time(t) end
		return stub.clock
	end
	stub.names.player, stub.surnames.player = "Veli", "Tanner"
	stub.items[LINEN] = { name = "Linen Cloth", sellPrice = 13, stack = 200 }
	stub.items[SALT] = { name = "Salt", sellPrice = 12, stack = 20 }
	stub.items[BOOTS] = { name = "Old Boots", sellPrice = 70, stack = 1 }
	stub.items[CRATE] = { name = "Waylaid Crate: Copper Bars" }
	stub.items[COPPER] = { name = "Copper Bar", sellPrice = 10 }
	stub.items[FISH] = { name = "Test Fish", sellPrice = 6 }
	stub.money = 100000
	stub.printed = {}
	ns.Print = function(m) stub.printed[#stub.printed + 1] = tostring(m) end
	stub.Fire("PLAYER_LOGIN")
	stub.Fire("PLAYER_ENTERING_WORLD", true, false)
	return ns, stub
end

local function cells(row)
	local out = {}
	for k, v in pairs(row.cells or {}) do out[k] = tostring(v) end
	return out
end

local function has(text, s) assert(tostring(text):find(s, 1, true), ("missing %q in:\n%s"):format(s, tostring(text))) end

local function findButton(stub, label)
	for _, f in ipairs(stub.frames) do
		if f.label and f.label.text == label and f.scripts.OnClick then return f end
	end
end

local function visibleRows(stub)
	local out = {}
	for _, f in ipairs(stub.frames) do
		if f.data and f.shown ~= false and f.cells and f.sub then out[#out + 1] = f.data end
	end
	return out
end

local function seedMarket(itemID, house, o)
	local db = CraftWiseMarketDB
	local today = math.floor(NOW / DAY)
	local days = {}
	for i, typ in ipairs(o.typs or {}) do
		days[today - i + 1] = { lo = typ, typ = typ, hi = typ, n = 1 }
	end
	local raw = o.tiers and { { t = NOW - 3600, total = o.total, listings = o.listings, tiers = o.tiers } } or {}
	db.items[itemID] = db.items[itemID] or {}
	db.items[itemID][house] = { raw = raw, days = days,
		last = { t = NOW - 3600, min = o.tiers and o.tiers[1] or o.min, qty = o.total, listings = o.listings } }
	db.houses[house] = db.houses[house] or (house == HORDE and { realm = "PvP", kind = "faction", faction = "Horde", label = "Horde AH" }
		or { realm = "PvP", kind = "neutral", label = "Booty Bay", cut = { samples = 0 } })
	db.scans[house] = { { t = NOW - 7200, kind = "full", items = 500, source = "replicate" } }
end

------------------------------------------------------------------------------------------- window

it("the main window's Records button opens the Records window; every tab builds and renders", function()
	local ns, stub = Load()
	ns.ToggleProfitFrame()
	local btn = findButton(stub, "Records")
	assert(btn, "Records button in the profit window header")
	btn.scripts.OnEnter(btn); btn.scripts.OnLeave(btn)
	btn.scripts.OnClick(btn)
	assert(CraftWiseRecordsFrame and CraftWiseRecordsFrame:IsShown(), "Records window shown")
	for _, tab in ipairs(ns.RW.tabs) do
		local tb = CraftWiseRecordsFrame.tabButtons[tab.key]
		tb.scripts.OnClick(tb)
		eq(ns.RW.CurrentTab(), tab.key)
		eq(ns.db.settings.recordsTab, tab.key, "the tab is remembered")
		assert(ns.RW.state.model and ns.RW.state.model.summary, tab.key .. " has a summary")
		assert(not ns.RW.state.model.summary:find("Could not build", 1, true), tab.key .. ": " .. ns.RW.state.model.summary)
	end
	-- the order of the tabs
	local keys = {}
	for _, tab in ipairs(ns.RW.tabs) do keys[#keys + 1] = tab.key end
	eq(table.concat(keys, ","), "market,where,snapshot")
	-- toggling: same tab closes, another tab switches
	ns.ToggleRecords("snapshot")
	eq(CraftWiseRecordsFrame:IsShown(), false)
	ns.ToggleRecords("market")
	eq(CraftWiseRecordsFrame:IsShown(), true); eq(ns.RW.CurrentTab(), "market")
end)

it("every tab's columns fit the window, at most six, the first is the name", function()
	local ns = Load()
	local RW = ns.RW
	local room = RW.WIDTH - 2 * RW.PAD - 34 - 14
	for _, tab in ipairs(RW.tabs) do
		for _, mode in ipairs({ {}, { fishWater = "visits" } }) do
			local cols = type(tab.columns) == "function" and tab.columns(mode) or tab.columns
			assert(#cols <= 6, tab.key .. ": too many columns")
			eq(cols[1].key, "name")
			local w = 0
			for _, c in ipairs(cols) do w = w + c.width end
			w = w + 8 * (#cols - 1)
			assert(w <= room, ("%s: columns %d px wide, room %d"):format(tab.key, w, room))
		end
	end
end)

------------------------------------------------------------------------------------------- market

it("market: scope items by default, any recorded item by name, ID or link; a row per house with details", function()
	local ns = Load()
	seedMarket(LINEN, HORDE, { typs = { 15, 16, 14, 15, 15 }, tiers = { 14, 40, 16, 60 }, total = 100, listings = 2 })
	seedMarket(LINEN, BOOTY, { min = 20, total = 5 })
	seedMarket(BOOTS, HORDE, { min = 900, total = 1 })
	CraftWiseMarketDB.scope.items[LINEN] = true
	CraftWiseMarketDB.names[BOOTS] = "Old Boots"
	-- default: the scope only
	local keys = ns.RW.Market.Keys("")
	eq(#keys, 1); eq(keys[1], LINEN)
	local m = ns.RW.Market.Model()
	eq(#m.rows, 2, "Linen Cloth at both houses")
	eq(m.rows[1].cells.house, "Horde AH")
	eq(m.rows[1].cells.last, ns.FormatMoney(14))
	has(m.rows[1].cells.typical, ns.FormatMoney(15))
	local tips = {}
	for _, t in ipairs(m.rows[1].tip) do tips[#tips + 1] = type(t) == "table" and (t[1] .. " " .. t[2]) or t end
	has(table.concat(tips, "\n"), "Cheapest")
	has(m.summary, "Horde AH: full scan")
	-- a name search finds items outside the scope
	ns.RW.SetQuery("market", "boots")
	m = ns.RW.Market.Model()
	eq(#m.rows, 1); eq(m.rows[1].itemID, BOOTS); eq(m.rows[1].cells.last, ns.FormatMoney(900))
	-- an item ID and a link
	eq(ns.RW.Market.Keys(tostring(BOOTS))[1], BOOTS)
	eq(ns.RW.Market.Keys("|cffffffff|Hitem:" .. BOOTS .. "::::|h[Old Boots]|h|r")[1], BOOTS)
	ns.RW.SetQuery("market", "nothing like it")
	m = ns.RW.Market.Model()
	eq(#m.rows, 0); has(m.empty, "No recorded item matches")
end)

it("market: at most MARKET_MAX items are listed, the rest counted", function()
	local ns = Load()
	ns.RW.MARKET_MAX = 3
	for id = 1, 5 do
		CraftWiseMarketDB.items[100 + id] = { [HORDE] = { raw = {}, days = {}, last = { t = NOW, min = 10, qty = 1 } } }
		CraftWiseMarketDB.scope.items[100 + id] = true
	end
	local keys, more = ns.RW.Market.Keys("")
	eq(#keys, 3); eq(more, 2)
	has(ns.RW.Market.Model().summary, "2 more")
end)

------------------------------------------------------------------------------------------- where

it("where to buy: sellers of an item by name or ID, cheapest first, with place, price and stock", function()
	local ns = Load()
	ns.db.merchants[3027] = { name = "Sewa Mistrunner", zone = "Thunder Bluff", sub = "Lower Rise", x = 47.2, y = 58.1, t = NOW - 3600,
		items = { [SALT] = { name = "Salt", p = 40, s = 1, n = -1, t = NOW - 3600 } } }
	ns.db.merchants[3081] = { name = "Wunna Darkmane", zone = "Mulgore", t = NOW - 60,
		items = { [SALT] = { name = "Salt", p = 50, s = 1, n = 3, t = NOW - 60 } } }
	local items = ns.RW.Where.Items("sal")
	eq(#items, 1); eq(items[1], SALT)
	ns.RW.SetQuery("where", "salt")
	local m = ns.RW.Where.Model()
	eq(#m.rows, 2)
	eq(m.rows[1].name, "Sewa Mistrunner")
	has(m.rows[1].cells.place, "Thunder Bluff, Lower Rise")
	has(m.rows[2].cells.stock, "3 in stock")
	has(m.summary, "2 merchants recorded")
	ns.RW.SetQuery("where", tostring(SALT))
	eq(#ns.RW.Where.Model().rows, 2)
	ns.RW.SetQuery("where", "")
	m = ns.RW.Where.Model()
	eq(#m.rows, 0); has(m.empty, "Search for an item")
	ns.RW.SetQuery("where", "unobtainium")
	has(ns.RW.Where.Model().empty, "No merchant you opened sells an item named")
end)

------------------------------------------------------------------------------------------- snapshot

it("snapshot: Save stores it and lists every section with its status; time of the last save", function()
	local ns = Load()
	local st = {}
	local m = ns.RW.Snapshot.Model(st)
	has(m.summary, "not saved yet")
	eq(#m.rows, #ns.Snapshot.SECTIONS)
	eq(ns.RW.Snapshot.Save(st), "saved")
	m = ns.RW.Snapshot.Model(st)
	has(m.summary, "last saved")
	has(m.summary, "Snapshot saved.")
	eq(m.rows[1].name, "char"); has(m.rows[1].cells.status, "saved")
	assert(ns.db.snapshots[ns.CharKey()], "stored under the character key")
	local reloaded = false
	C_UI = { Reload = function() reloaded = true end }
	ns.RW.Snapshot.buttons(st)[2].onClick()
	eq(reloaded, true)
end)

------------------------------------------------------------------------------------------- frame

it("window: search box, buttons, rows, tooltips, item clicks open the item menu, scrolling", function()
	local ns, stub = Load()
	seedMarket(LINEN, HORDE, { min = 14, total = 100 })
	CraftWiseMarketDB.scope.items[LINEN] = true
	ns.ShowRecords("market")
	local rows = visibleRows(stub)
	eq(#rows, 1); eq(rows[1].itemID, LINEN)
	for _, f in ipairs(stub.frames) do
		if f.data and f.cells and f.sub and f.shown ~= false then
			f.scripts.OnEnter(f); f.scripts.OnLeave(f)
			f.scripts.OnClick(f, "LeftButton")
		end
	end
	assert(CraftWiseItemMenu and CraftWiseItemMenu:IsShown(), "item menu opened from the row")
	-- the tab's buttons are real buttons: Reload UI on the Snapshot tab
	ns.ShowRecords("snapshot")
	local reloaded = false
	C_UI = { Reload = function() reloaded = true end }
	local reload = findButton(stub, "Reload UI")
	reload.scripts.OnClick(reload)
	eq(reloaded, true)
	-- search box drives the market tab's query
	ns.ShowRecords("market")
	local box = CraftWiseRecordsFrame.search
	box:SetText("linen")
	box.scripts.OnTextChanged(box)
	eq(ns.RW.Query("market"), "linen")
	CraftWiseRecordsFrame.scripts.OnMouseWheel(CraftWiseRecordsFrame, -1)
	CraftWiseRecordsFrame.scripts.OnUpdate(CraftWiseRecordsFrame, 2)
	-- opening with a query fills the box
	ns.ShowRecords("where", "salt")
	eq(CraftWiseRecordsFrame.search:GetText(), "salt")
	eq(ns.RW.Query("where"), "salt")
end)

it("item menu: Where to buy and Price history open the Records window for the item (until Look up › Items, #157)", function()
	local ns, stub = Load()
	ns.ShowItemMenu(SALT)
	local where = CraftWiseItemMenu.buttons.where
	where.scripts.OnClick(where)
	eq(ns.RW.CurrentTab(), "where"); eq(ns.RW.Query("where"), tostring(SALT))
	ns.ShowItemMenu(LINEN)
	local history = CraftWiseItemMenu.buttons.history
	history.scripts.OnEnter(history); history.scripts.OnLeave(history)
	history.scripts.OnClick(history)
	eq(ns.RW.CurrentTab(), "market"); eq(ns.RW.Query("market"), tostring(LINEN))
	eq(CraftWiseRecordsFrame:IsShown(), true)
end)

------------------------------------------------------------------------------------------- settings

it("settings: loot toast, farm, fishing and minimap switches change what the slash commands change", function()
	local ns, stub = Load()
	ns.ToggleSettings()
	local p = CraftWiseSettings
	-- loot toast: Move unlocks, again locks; With value; duration +/-
	p.toastMove.scripts.OnClick(p.toastMove)
	eq(ns.db.lootToast.locked, false)
	p.toastMove.scripts.OnClick(p.toastMove)
	eq(ns.db.lootToast.locked, true)
	p.toastValue.scripts.OnClick(p.toastValue)
	eq(ns.db.lootToast.value, false)
	local d = ns.LootToast.Duration()
	p.toastDuration.up.scripts.OnClick(p.toastDuration.up)
	eq(ns.LootToast.Duration(), d + 1)
	for _ = 1, 40 do p.toastDuration.down.scripts.OnClick(p.toastDuration.down) end
	eq(ns.LootToast.Duration(), ns.LootToast.MIN_DURATION)
	p.toastTest.scripts.OnClick(p.toastTest)
	p.toastReset.scripts.OnClick(p.toastReset)
	-- farm: lock, idle, scale
	p.farmLock.scripts.OnClick(p.farmLock)
	eq(ns.db.farm.locked, true)
	p.farmIdle.down.scripts.OnClick(p.farmIdle.down)
	eq(ns.Farm.IdleMinutes(), 4)
	for _ = 1, 10 do p.farmIdle.down.scripts.OnClick(p.farmIdle.down) end
	eq(ns.Farm.IdleMinutes(), 0)
	p.farmScale.up.scripts.OnClick(p.farmScale.up)
	eq(ns.db.farm.scale, 1.1)
	for _ = 1, 30 do p.farmScale.up.scripts.OnClick(p.farmScale.up) end
	eq(ns.db.farm.scale, ns.Farm.MAX_SCALE)
	-- fishing: session gap and own-catch minimum
	p.fishGap.up.scripts.OnClick(p.fishGap.up)
	eq(ns.Fishing.SessionGap(), 6)
	local own = ns.FishingZones.OwnMin()
	p.fishOwnMin.up.scripts.OnClick(p.fishOwnMin.up)
	eq(ns.FishingZones.OwnMin(), own + 10)
	-- minimap button
	p.minimap.scripts.OnClick(p.minimap)
	eq(ns.db.minimap.hide, true)
	p.minimap.scripts.OnClick(p.minimap)
	eq(ns.db.minimap.hide, false)
	-- Records and farm history buttons
	p.records.scripts.OnClick(p.records)
	eq(CraftWiseRecordsFrame:IsShown(), true)
	p.farmHistory.scripts.OnClick(p.farmHistory)
	eq(ns.Main.shown.page, "farm", "Farm history: Gather › Farm (#156)")
end)

------------------------------------------------------------------------------------------- slash

it("every slash command still works next to the UI", function()
	local ns, stub = Load()
	for _, cmd in ipairs({ "", "ledger", "ledger today", "ledger reset", "auctions", "crates", "fishing", "fishing pools",
		"fishing zones", "fishing gap 7", "fishing ownmin 30", "market 2589", "where salt", "snapshot", "loottoast",
		"loottoast unlock", "loottoast lock", "loottoast duration 5", "loottoast value off", "farm", "farm history",
		"farm idle 3", "farm scale 1.2", "ahmin 25 20", "minimap", "minimap", "party", "settings", "debug" }) do
		SlashCmdList.CRAFTWISE(cmd)
	end
	eq(ns.db.settings.fishingSessionGap, 7); eq(ns.db.settings.fishingOwnMin, 30)
	eq(ns.db.lootToast.duration, 5); eq(ns.db.lootToast.value, false)
	eq(ns.db.farm.idleMinutes, 3); eq(ns.db.settings.ahMinPercent, 25)
	assert(#stub.printed > 10)
end)

------------------------------------------------------------------------------------------- farm history

local function farmLoot(stub, id, count)
	LOOT_ITEM_SELF = "You receive loot: %s."
	LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d."
	local l = ("|cffffffff|Hitem:%d::::::::20:::::|h[%s]|h|r"):format(id, stub.items[id].name)
	local text = count and count > 1 and LOOT_ITEM_SELF_MULTIPLE:format(l, count) or LOOT_ITEM_SELF:format(l)
	stub.Fire("CHAT_MSG_LOOT", text, "", "", "", "", "", 0, 0, "", 0, 1, "Player-1-SELF")
end

it("farm history: list rows per finished session, details with top items, zones, split and the kept loot log", function()
	local ns, stub = Load({ auctionator = true })
	local FH = ns.FarmHistory
	eq(#FH.ListRows(ns.Farm.History()), 0)
	stub.zone = "Elwynn Forest"
	SlashCmdList.CRAFTWISE("farm idle 0")
	farmLoot(stub, LINEN, 3)
	stub.clock = stub.clock + 1800
	farmLoot(stub, SALT, 1)
	SlashCmdList.CRAFTWISE("farm reset")
	local rows = FH.ListRows(ns.Farm.History())
	eq(#rows, 1)
	eq(rows[1].index, 1); eq(rows[1].zone, "Elwynn Forest"); eq(rows[1].time, "0:30")
	eq(rows[1].items, 3 * 13 + 12); eq(rows[1].fishing, false)
	local d = FH.Detail(ns.Farm.History()[1])
	eq(d.top[1].itemID, LINEN); eq(d.zones[1].zone, "Elwynn Forest"); eq(d.split.vendor, 3 * 13 + 12)
	eq(#d.log, 2, "both drops in the log"); eq(d.log[1].itemID, SALT, "newest first")
	has(d.logNote, "2 loot lines kept")
	-- an older session without its log says why
	local h = ns.Farm.History()[1]
	local logLines = #h.log
	h.log, h.logZones, h.logLines = nil, nil, logLines
	d = FH.Detail(h)
	eq(d.log, nil); has(d.logNote, "Loot log not kept")
end)

it("farm history: the tracker's History button and the Settings button open Gather › Farm; a session opens in place", function()
	local ns, stub = Load({ auctionator = true })
	SlashCmdList.CRAFTWISE("farm idle 0")
	farmLoot(stub, LINEN, 2)
	stub.clock = stub.clock + 600
	SlashCmdList.CRAFTWISE("farm reset")
	SlashCmdList.CRAFTWISE("farm show")
	local btn
	for _, f in ipairs(stub.frames) do
		if f.label and f.label.text == "History" and f.scripts.OnClick and f.shown ~= false then btn = f end
	end
	assert(btn, "History button in the farm tracker")
	btn.scripts.OnClick(btn)
	local M = ns.Main
	eq(M.Frame():IsShown(), true); eq(M.shown.page, "farm")
	local list = M.ListOf("farm")
	eq(#list.rows, 1)
	local row = list.box.frames[1]
	row.scripts.OnClick(row, "LeftButton")
	eq(list.box.frames[2].elementData.open, true)
	-- the Settings button opens it too
	M.Frame():Hide()
	ns.ToggleSettings()
	CraftWiseSettings.farmHistory.scripts.OnClick(CraftWiseSettings.farmHistory)
	eq(M.Frame():IsShown(), true); eq(M.shown.page, "farm")
	-- /craftwise farm history still prints
	stub.printed = {}
	SlashCmdList.CRAFTWISE("farm history")
	has(table.concat(stub.printed, "\n"), "Farm sessions")
end)
