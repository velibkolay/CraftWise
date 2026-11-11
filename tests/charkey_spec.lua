-- Issue #77: the per-character key includes the Forever surname (ns.CharKey/ns.CharName), and the
-- old "<realm>-<name>" entries (ledger, snapshot, fishing log) move to the current character only when
-- the old snapshot's class and race match it; otherwise they stay, marked legacy, with one message.
local NOW = os.time({ year = 2026, month = 11, day = 11, hour = 12 })
local REALM = "CAMWOW EU4 Realm 8 PvP"
local OLD = REALM .. "-Velikopter"
local TANNER = REALM .. "-Velikopter Tanner"
local WRIGHT = REALM .. "-Velikopter Wright"

-- Loads the addon with saved tables; the character is set only after ADDON_LOADED (as at a real
-- load, the migration may have to wait for PLAYER_LOGIN), then logs in.
local function Login(surname, race, class, saved)
	saved = saved or {}
	local ns, stub = LoadAddon({ savedDB = saved.db, savedMarket = saved.market })
	stub.clock = NOW
	time = function(t)
		if t then return os.time(t) end
		return stub.clock
	end
	ns.printed = {}
	ns.Print = function(msg) ns.printed[#ns.printed + 1] = tostring(msg) end
	stub.names.player, stub.surnames.player, stub.realm = "Velikopter", surname, REALM
	function UnitRace() return race, race, 2 end
	function UnitClass() return class, class:upper(), 3 end
	stub.held = { [2589] = 2 } -- the 2 Linen Cloth the old ledger position holds
	C_Item.GetItemCount = function(id) return stub.held[id] or 0 end
	stub.Fire("PLAYER_LOGIN")
	stub.Fire("PLAYER_ENTERING_WORLD", true, false)
	return ns, stub
end

-- What the SavedVariables held before #77: both characters wrote to OLD.
local function OldSaved(snapClass, snapRace)
	local db = {
		fishing = { [OLD] = { catches = { { t = NOW - 3600, zone = "Durotar", items = { [6291] = 1 } } }, opened = {} } },
		snapshots = {},
	}
	if snapClass then
		db.snapshots[OLD] = { v = 1, t = NOW - 7200, char = { name = "Velikopter", realm = REALM, class = snapClass, race = snapRace } }
	end
	local market = { ledger = {
		entries = { { t = NOW - 600, c = OLD, k = "vbuy", i = 2589, q = 2, m = 30, w = "Vendor" },
			{ t = NOW - 500, c = REALM .. "-Someone", k = "vbuy", i = 2589, q = 1, m = 15, w = "Vendor" } },
		chars = { [OLD] = { reset = { t = NOW - 86400, money = 5000 }, days = { ["2026-11-10"] = 4000 }, pos = { [2589] = { held = 2, known = 2, cost = 30, transit = 0 } } },
			[REALM .. "-Someone"] = { days = {}, pos = {} } },
	} }
	return { db = db, market = market }
end

it("key: realm, name and surname joined with the client's separator", function()
	local ns, stub = Login("Tanner", "Orc", "Hunter")
	eq(ns.CharKey(), TANNER)
	local full, first, surname = ns.CharName()
	eq(full, "Velikopter Tanner"); eq(first, "Velikopter"); eq(surname, "Tanner")
	Constants = { CharacterNameSeparatorConsts = { CHARACTERNAME_SURNAME_SEPARATOR = "~" } }
	eq(ns.CharKey(), REALM .. "-Velikopter~Tanner", "the client's constant wins")
	Constants = nil
	eq(ns.Ledger.CharKey(), TANNER, "ledger uses the same key")
	eq(ns.Snapshot.Key(), TANNER, "snapshot uses the same key")
	eq(ns.Fishing.CharKey(), TANNER, "fishing uses the same key")
	stub.names.player = nil
	eq(ns.CharKey(), nil, "no key while the client doesn't know the name")
end)

it("key: a character without a surname keeps <realm>-<name>", function()
	local ns, stub = Login(nil, "Orc", "Hunter")
	eq(ns.CharKey(), REALM .. "-Velikopter")
	local full, first, surname = ns.CharName()
	eq(full, "Velikopter"); eq(first, "Velikopter"); eq(surname, nil)
	stub.surnames.player = ""
	eq(ns.CharKey(), REALM .. "-Velikopter", "an empty surname counts as none")
	eq(ns.MigrateCharKey(), "none")
end)

it("two characters with the same first name keep their own ledger, snapshot and fishing log", function()
	local ns, stub = Login("Tanner", "Orc", "Hunter")
	stub.items[2589] = { name = "Linen Cloth", sellPrice = 13 }
	stub.held[2589] = 1
	ns.Ledger.Record("vbuy", 2589, 1, 15, "Vendor", 0)
	ns.Fishing.Log().catches[1] = { t = NOW, zone = "Durotar", items = { [6291] = 1 } }
	ns.Snapshot.Save()
	-- Same session table, other character (as the account-wide SavedVariables are on the next login).
	local saved = { db = CraftWiseDB, market = CraftWiseMarketDB }
	ns, stub = Login("Wright", "Troll", "Mage", saved)
	stub.items[2589] = { name = "Linen Cloth", sellPrice = 13 }
	stub.held[2589] = 3
	ns.Ledger.Record("vbuy", 2589, 3, 45, "Vendor", 0)
	ns.Snapshot.Save()
	local chars = CraftWiseMarketDB.ledger.chars
	assert(chars[TANNER] and chars[WRIGHT], "one ledger character each")
	eq(chars[TANNER].pos[2589].cost, 15); eq(chars[WRIGHT].pos[2589].cost, 45)
	local byChar = {}
	for _, e in ipairs(CraftWiseMarketDB.ledger.entries) do byChar[e.c] = (byChar[e.c] or 0) + e.q end
	eq(byChar[TANNER], 1); eq(byChar[WRIGHT], 3); eq(byChar[OLD], nil)
	eq(#CraftWiseDB.fishing[TANNER].catches, 1)
	eq(#CraftWiseDB.fishing[WRIGHT].catches, 0, "Wright never fished")
	eq(CraftWiseDB.snapshots[TANNER].char.surname, "Tanner")
	eq(CraftWiseDB.snapshots[TANNER].char.class, "Hunter")
	eq(CraftWiseDB.snapshots[WRIGHT].char.name, "Velikopter")
	eq(CraftWiseDB.snapshots[WRIGHT].char.surname, "Wright")
	eq(CraftWiseDB.snapshots[WRIGHT].char.class, "Mage")
	eq(CraftWiseDB.snapshots[OLD], nil)
	eq(#ns.printed, 0, "nothing to migrate, nothing printed")
end)

it("migration: old entries move to the character whose class and race match the old snapshot", function()
	local ns = Login("Tanner", "Orc", "Hunter", OldSaved("Hunter", "Orc"))
	eq(ns.MigrateCharKey(), "moved")
	local db, ledger = CraftWiseDB, CraftWiseMarketDB.ledger
	eq(db.snapshots[OLD], nil); eq(db.snapshots[TANNER].char.class, "Hunter")
	eq(db.fishing[OLD], nil); eq(#db.fishing[TANNER].catches, 1)
	eq(ledger.chars[OLD], nil); eq(ledger.chars[TANNER].pos[2589].cost, 30)
	eq(ledger.chars[TANNER].reset.t, NOW - 86400, "the old reset point is kept")
	eq(ledger.chars[TANNER].days["2026-11-10"], 4000)
	eq(ledger.entries[1].c, TANNER)
	eq(ledger.entries[2].c, REALM .. "-Someone", "other characters' entries are untouched")
	assert(ledger.chars[REALM .. "-Someone"], "other characters are untouched")
	eq(db.snapshots[TANNER].legacy, nil); eq(ledger.chars[TANNER].legacy, nil)
	eq(#ns.printed, 1)
	assert(ns.printed[1]:find(OLD, 1, true) and ns.printed[1]:find("Velikopter Tanner", 1, true), ns.printed[1])
	-- The other character logs in later: nothing left under the old key, nothing claimed.
	local saved = { db = CraftWiseDB, market = CraftWiseMarketDB }
	ns = Login("Wright", "Troll", "Mage", saved)
	eq(ns.MigrateCharKey(), "none")
	eq(CraftWiseDB.fishing[WRIGHT], nil)
	eq(CraftWiseMarketDB.ledger.chars[WRIGHT].pos[2589], nil, "Wright gets none of the old position")
	eq(#ns.printed, 0)
end)

it("migration: class or race differ -> kept under the old key, marked legacy, printed once", function()
	local ns, stub = Login("Wright", "Troll", "Mage", OldSaved("Hunter", "Orc"))
	eq(ns.MigrateCharKey(), "legacy")
	local db, ledger = CraftWiseDB, CraftWiseMarketDB.ledger
	eq(db.snapshots[OLD].legacy, true); eq(db.fishing[OLD].legacy, true); eq(ledger.chars[OLD].legacy, true)
	eq(db.fishing[WRIGHT], nil, "nothing moved")
	eq(ledger.entries[1].c, OLD)
	eq(#ns.printed, 1)
	assert(ns.printed[1]:find("legacy", 1, true) and ns.printed[1]:find("Orc Hunter", 1, true), ns.printed[1])
	stub.Fire("PLAYER_ENTERING_WORLD", false, true)
	eq(#ns.printed, 1, "a zone change doesn't print again")
	-- Next login of the same character: still legacy, no second message.
	local saved = { db = CraftWiseDB, market = CraftWiseMarketDB }
	ns = Login("Wright", "Troll", "Mage", saved)
	eq(ns.MigrateCharKey(), "legacy")
	eq(#ns.printed, 0, "printed once")
	-- The matching character logs in: the entries move to it and lose the mark.
	saved = { db = CraftWiseDB, market = CraftWiseMarketDB }
	ns = Login("Tanner", "Orc", "Hunter", saved)
	eq(ns.MigrateCharKey(), "moved")
	eq(CraftWiseDB.snapshots[OLD], nil); eq(CraftWiseDB.snapshots[TANNER].legacy, nil)
	eq(CraftWiseDB.fishing[TANNER].legacy, nil); eq(CraftWiseMarketDB.ledger.chars[TANNER].legacy, nil)
	eq(CraftWiseMarketDB.ledger.entries[1].c, TANNER)
end)

it("migration: no old snapshot -> owner unknown, kept as legacy", function()
	local ns = Login("Tanner", "Orc", "Hunter", OldSaved(nil))
	eq(ns.MigrateCharKey(), "legacy")
	eq(CraftWiseDB.fishing[OLD].legacy, true)
	eq(CraftWiseMarketDB.ledger.chars[OLD].legacy, true)
	eq(CraftWiseDB.fishing[TANNER], nil)
	assert(ns.printed[1] and ns.printed[1]:find("no snapshot", 1, true), tostring(ns.printed[1]))
end)

it("migration: ledger entries without a character table are marked legacy too", function()
	local saved = OldSaved(nil)
	saved.db.fishing = {}
	saved.market.ledger.chars[OLD] = nil
	local ns = Login("Tanner", "Orc", "Hunter", saved)
	eq(ns.MigrateCharKey(), "legacy")
	eq(CraftWiseMarketDB.ledger.chars[OLD].legacy, true)
	eq(CraftWiseMarketDB.ledger.entries[1].c, OLD)
	eq(#ns.printed, 1)
end)

it("migration waits while the client doesn't know the character, class or race", function()
	local saved = OldSaved("Hunter", "Orc")
	local ns, stub = LoadAddon({ savedDB = saved.db, savedMarket = saved.market })
	ns.Print = function() end
	eq(ns.MigrateCharKey(), "pending", "no name yet")
	stub.names.player, stub.surnames.player, stub.realm = "Velikopter", "Tanner", REALM
	UnitClass, UnitRace = nil, nil
	eq(ns.MigrateCharKey(), "pending", "no class/race yet")
	eq(CraftWiseDB.fishing[OLD] ~= nil, true, "nothing touched while pending")
	function UnitRace() return "Orc", "Orc", 2 end
	function UnitClass() return "Hunter", "HUNTER", 3 end
	stub.Fire("PLAYER_LOGIN")
	eq(ns.MigrateCharKey(), "moved")
end)

it("migration merges into a ledger character the new key started before it ran", function()
	local saved = OldSaved("Hunter", "Orc")
	saved.market.ledger.chars[TANNER] = { reset = { t = NOW, money = 7000 }, session = { t = NOW, money = 7000 },
		days = { ["2026-11-11"] = 7000 }, pos = {} }
	saved.db.fishing[TANNER] = { catches = { { t = NOW, zone = "Barrens", items = {} } }, opened = {} }
	Login("Tanner", "Orc", "Hunter", saved)
	local c = CraftWiseMarketDB.ledger.chars[TANNER]
	eq(c.reset.t, NOW - 86400, "the older reset point wins")
	eq(c.session.t, NOW, "this session stays")
	eq(c.days["2026-11-11"], 7000); eq(c.days["2026-11-10"], 4000)
	eq(c.pos[2589].cost, 30)
	local catches = CraftWiseDB.fishing[TANNER].catches
	eq(#catches, 2); eq(catches[1].zone, "Durotar", "sorted by time")
end)
