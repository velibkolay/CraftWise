-- Issue #137, #157: every feature keeps a UI home; slash commands are a second way in and open the matching
-- page of the main window (#150 "Where everything lands"). The Records window, the old Settings panel and
-- the AH rule panel are gone (#157 part 2); their options are on the Settings page
-- (tests/settings_page_spec.lua), their views on the pages (sell_pages, gather, lookup_items specs).
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

local function has(text, s) assert(tostring(text):find(s, 1, true), ("missing %q in:\n%s"):format(s, tostring(text))) end

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

------------------------------------------------------------------------------------------- old windows

it("the old windows are gone: no Records window, Settings panel or AH rule panel, no old entry points", function()
	local ns = Load()
	eq(ns.RW, nil); eq(ns.ToggleRecords, nil); eq(ns.ShowRecords, nil)
	eq(ns.ToggleSettings, nil); eq(ns.ToggleAHRule, nil); eq(ns.StepCopper, nil); eq(ns.RefreshProfitFrame, nil)
	SlashCmdList.CRAFTWISE("settings")
	eq(CraftWiseRecordsFrame, nil); eq(CraftWiseSettings, nil); eq(CraftWiseAHRule, nil)
	local toc = assert(io.open("CraftWise/CraftWise.toc")):read("*a")
	for _, file in ipairs({ "UI\\Records\\", "UI\\Settings.lua", "UI\\AHRule.lua" }) do
		assert(not toc:find(file, 1, true), file .. " still in the TOC")
	end
	-- settings only the old windows used are dropped from the saved file
	for _, key in ipairs({ "sortKey", "view", "bagSortKey", "bagSortDesc", "recordsTab" }) do
		eq(ns.db.settings[key], nil, key)
	end
end)

it("retired settings in an old saved file are dropped on load; the others stay", function()
	local ns = LoadAddon({ savedDB = { settings = { bagSortKey = "name", recordsTab = "snapshot", view = "learn",
		upgradeSection = "ah", ahMinPercent = 35 } } })
	eq(ns.db.settings.bagSortKey, nil); eq(ns.db.settings.recordsTab, nil); eq(ns.db.settings.view, nil)
	eq(ns.db.settings.upgradeSection, nil); eq(ns.db.settings.ahMinPercent, 35)
end)

------------------------------------------------------------------------------------------- slash

-- What a command opened: the page shown (nil when the window stays closed) and the Settings group.
local function Opened(ns, cmd)
	local M = ns.Main
	if M.Frame() then M.Frame():Hide() end
	SlashCmdList.CRAFTWISE(cmd)
	local f = M.Frame()
	local page = f and f:IsShown() and M.shown.page or nil
	return page, page == "settings" and M.UI().settingsGroup or nil
end

it("slash commands open their page (#157): every command against the Where everything lands table", function()
	local ns, stub = Load({ auctionator = true })
	local M = ns.Main
	seedMarket(SALT, HORDE, { tiers = { 30, 40 }, total = 40, typs = { 30 } })
	seedMarket(LINEN, HORDE, { tiers = { 10, 400 }, total = 400, typs = { 10 } })
	local function opens(cmd, page, group)
		local p, g = Opened(ns, cmd)
		eq(p, page, cmd .. ": page")
		if group then eq(g, group, cmd .. ": settings group") end
	end
	opens("", "craft") -- no command: the main window (Make › Craft on a fresh install)
	opens("ledger", "ledger"); opens("ledger today", "ledger")
	opens("auctions", "auctions")
	opens("crates", "crates")
	opens("fishing", "fishing"); eq(ns.GatherFishing.Mode(), "log"); eq(ns.GatherFishing.Water(), "all")
	opens("fishing pools", "fishing"); eq(ns.GatherFishing.Water(), "pool")
	opens("fishing zones", "fishing"); eq(ns.GatherFishing.Mode(), "spots")
	opens("fishing gap 7", "settings", "fishing"); opens("fishing ownmin 30", "settings", "fishing")
	-- market and where: Look up › Items on the item (ID, link with its case kept, or a name)
	opens("market " .. LINEN, "items")
	eq(M.Items.Selected(), LINEN); eq(M.Items.state.focus, "history")
	opens("where " .. SALT, "items")
	eq(M.Items.Selected(), SALT); eq(M.Items.state.focus, "where")
	opens("market |cffffffff|Hitem:" .. LINEN .. "::::::::20:::::|h[Linen Cloth]|h|r", "items")
	eq(M.Items.Selected(), LINEN)
	opens("where Salt", "items")
	eq(M.Items.state.query, "Salt", "the name as typed goes into the search box")
	eq(M.Items.Selected(), SALT, "the one match shows on the card")
	opens("market", "items"); opens("where", "items")
	-- settings
	opens("settings", "settings"); opens("config", "settings")
	opens("snapshot", "settings", "snapshot")
	opens("ahmin 25 20", "settings", "ahrule"); opens("ahmin", "settings", "ahrule")
	opens("loottoast", "settings", "toast"); opens("loottoast unlock", "settings", "toast"); opens("loottoast lock", "settings", "toast")
	opens("minimap", "settings", "look"); opens("minimap", "settings", "look")
	opens("farm lock", "settings", "farm"); opens("farm unlock", "settings", "farm"); opens("farm idle 3", "settings", "farm")
	opens("farm scale 1.2", "settings", "farm"); opens("farm autostart on", "settings", "farm")
	opens("farm history", "farm")
	-- the farm tracker's own commands act on the tracker (its home); the party key's command stays an action
	opens("farm show", nil); eq(CraftWiseFarmFrame:IsShown(), true)
	opens("farm", nil); eq(CraftWiseFarmFrame:IsShown(), false)
	opens("party", nil)
	-- /craftwise debug stays slash-only
	opens("debug", nil); opens("debug style", nil)
	eq(ns.db.settings.ahMinPercent, 25); eq(ns.db.farm.idleMinutes, 3)
end)

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

it("farm history: the tracker's History button and /craftwise farm history open Gather › Farm; a session opens in place", function()
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
	-- /craftwise farm history opens it too, and still prints
	M.Frame():Hide()
	stub.printed = {}
	SlashCmdList.CRAFTWISE("farm history")
	eq(M.Frame():IsShown(), true); eq(M.shown.page, "farm")
	has(table.concat(stub.printed, "\n"), "Farm sessions")
end)
